#!/usr/bin/env python3
"""Combine supported xcresulttool exports with reproducibility context."""

import argparse
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
import sys
from pathlib import Path


ANSI_BOLD = "\033[1m"
ANSI_CYAN = "\033[36m"
ANSI_GREEN = "\033[32m"
ANSI_RED = "\033[31m"
ANSI_YELLOW = "\033[33m"
ANSI_RESET = "\033[0m"

WORKLOAD_NAMES = {
    "testInMemoryInitializationFromProductionKeymap": "In-memory initialization",
    "testTraversalOfEveryCandidateBearingProductionPath": "Candidate-bearing path traversal",
    "testCommonProductionComposition": "Common production composition",
    "testDeterministicMixedComposition": "Deterministic mixed composition",
    "testAccumulatingSoftCommitAndHistory": "Accumulating soft commit and history",
    "testUndoAndHistoryPressureAtCap": "Undo and history pressure",
    "testProductionCandidateNavigationAndSelection": (
        "Production candidate navigation and selection"
    ),
}


def command_output(*arguments: str) -> str:
    return subprocess.check_output(
        arguments,
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()


def version_context() -> dict:
    xcode_lines = command_output("xcodebuild", "-version").splitlines()
    macos = {
        "productName": command_output("sw_vers", "-productName"),
        "productVersion": command_output("sw_vers", "-productVersion"),
        "buildVersion": command_output("sw_vers", "-buildVersion"),
    }
    return {
        "hostArchitecture": platform.machine(),
        "macOS": macos,
        "xcode": {
            "version": xcode_lines[0] if xcode_lines else "",
            "buildVersion": xcode_lines[1] if len(xcode_lines) > 1 else "",
        },
        "swiftVersion": command_output("xcrun", "swift", "--version"),
    }


def metric_summary(metric: dict) -> dict:
    measurements = metric["measurements"]
    average = statistics.fmean(measurements)
    deviation = statistics.pstdev(measurements) if len(measurements) > 1 else 0.0
    relative_deviation = 0.0 if average == 0 else deviation / average * 100
    return {
        "identifier": metric["identifier"],
        "displayName": metric["displayName"],
        "unitOfMeasurement": metric["unitOfMeasurement"],
        "measurements": measurements,
        "average": average,
        "relativeStandardDeviationPercent": relative_deviation,
    }


def compact_test_name(identifier: str) -> str:
    name = identifier.rsplit("/", maxsplit=1)[-1]
    return name.removesuffix("()")


def display_value(metric: dict) -> str:
    value = metric["average"]
    unit = metric["unitOfMeasurement"]
    if unit == "s":
        return f"{value * 1_000:.3f} ms"
    if unit == "kB":
        return f"{value / 1_024:.2f} MiB"
    if math.isfinite(value):
        return f"{value:.3f} {unit}"
    return f"{value} {unit}"


def color_enabled(stream, environment: dict[str, str]) -> bool:
    return (
        stream.isatty()
        and "CI" not in environment
        and "NO_COLOR" not in environment
    )


def styled(value: str, code: str, use_color: bool) -> str:
    return f"{code}{value}{ANSI_RESET}" if use_color else value


def terminal_artifact_path(artifact_path: str) -> str:
    path = Path(artifact_path)
    try:
        return str(path.resolve().relative_to(Path.cwd().resolve()))
    except ValueError:
        return artifact_path


def render_human_summary(
    report: dict,
    artifact_path: str,
    use_color: bool,
) -> str:
    test_summary = report["xcodeTestSummary"]
    context = report["context"]
    passed = test_summary["passedTests"]
    total = test_summary["totalTestCount"]
    status = "PASS" if test_summary["result"] == "Passed" and passed == total else "FAIL"

    title = styled("UNICORN BENCHMARKS", ANSI_CYAN, use_color)
    status_color = ANSI_GREEN if status == "PASS" else ANSI_RED
    result = styled(f"{status}  {passed}/{total}", status_color, use_color)
    configuration = (
        f"{context['configuration']} · {context['hostArchitecture']} · "
        f"{context['measurementIterations']} iterations"
    )
    lines = [
        f"{title}  {result}",
        styled(configuration, ANSI_CYAN, use_color),
        "",
    ]

    metric_identifiers = {
        "wall": "com.apple.dt.XCTMetric_Clock.time.monotonic",
        "cpu": "com.apple.dt.XCTMetric_CPU.time",
        "memory": "com.apple.dt.XCTMetric_Memory.physical_peak",
    }
    rows = []
    workload_order = {name: index for index, name in enumerate(WORKLOAD_NAMES)}
    tests = sorted(
        report["performanceTests"],
        key=lambda test: workload_order.get(test["name"], len(workload_order)),
    )
    for test in tests:
        metrics = {metric["identifier"]: metric for metric in test["metrics"]}
        wall = metrics.get(metric_identifiers["wall"])
        cpu = metrics.get(metric_identifiers["cpu"])
        memory = metrics.get(metric_identifiers["memory"])
        rows.append(
            (
                WORKLOAD_NAMES.get(test["name"], test["name"]),
                display_value(wall) if wall else "-",
                display_value(cpu) if cpu else "-",
                display_value(memory) if memory else "-",
                (
                    f"{wall['relativeStandardDeviationPercent']:.2f}%"
                    if wall
                    else "-"
                ),
            )
        )

    headings = ("WORKLOAD", "WALL", "CPU", "PEAK MEMORY", "VARIATION")
    widths = [
        max([len(headings[index])] + [len(row[index]) for row in rows])
        for index in range(len(headings))
    ]

    def plain_row(values: tuple[str, ...]) -> str:
        return "   ".join(
            [values[0].ljust(widths[0])]
            + [values[index].rjust(widths[index]) for index in range(1, 5)]
        )

    lines.append(styled(plain_row(headings), ANSI_CYAN, use_color))
    for row in rows:
        workload = styled(row[0], ANSI_BOLD, use_color) + " " * (
            widths[0] - len(row[0])
        )
        measurements = "   ".join(
            row[index].rjust(widths[index]) for index in range(1, 5)
        )
        lines.append(f"{workload}   {measurements}")

    lines.extend(
        [
            "",
            f"Results: {styled(terminal_artifact_path(artifact_path), ANSI_CYAN, use_color)}",
            f"Thresholds: {styled('not enforced', ANSI_YELLOW, use_color)}",
        ]
    )
    return "\n".join(lines)


def print_human_summary(report: dict, artifact_path: str) -> None:
    print(
        render_human_summary(
            report,
            artifact_path,
            color_enabled(sys.stdout, dict(os.environ)),
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--keymap", required=True)
    parser.add_argument("--test-summary", required=True)
    parser.add_argument("--metrics", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--artifact-path", required=True)
    arguments = parser.parse_args()

    keymap_path = Path(arguments.keymap)
    keymap_data = keymap_path.read_bytes()
    test_summary = json.loads(Path(arguments.test_summary).read_text())
    metrics = json.loads(Path(arguments.metrics).read_text())

    context = version_context()
    context.update(
        {
            "configuration": "Release",
            "architectureSelection": "native host architecture",
            "measurementIterations": 5,
            "measuredBatchSizes": {
                "initializationDecodes": 10,
                "candidatePathTraversals": 102_300,
                "commonCompositionCycles": 1_000,
                "mixedCompositionCycles": 500,
                "accumulatingCompositionCycles": 50,
                "historyPressureCycles": 500,
                "candidateNavigationCycles": 5_000,
            },
            "productionKeymap": {
                "path": str(keymap_path),
                "byteCount": len(keymap_data),
                "sha256": hashlib.sha256(keymap_data).hexdigest(),
            },
            "syntheticHistoryFixture": {
                "jsonByteCount": 30,
                "nodeCount": 3,
                "maximumDepth": 2,
                "maximumBranchingFactor": 1,
                "candidateBearingNodeCount": 1,
                "candidateCount": 2,
                "seedHistoryEntryCount": 99,
                "historyCap": 100,
            },
        }
    )

    performance_tests = []
    for test in metrics:
        runs = test.get("testRuns", [])
        run_metrics = runs[0].get("metrics", []) if runs else []
        performance_tests.append(
            {
                "identifier": test["testIdentifier"],
                "name": compact_test_name(test["testIdentifier"]),
                "metrics": [metric_summary(metric) for metric in run_metrics],
            }
        )

    report = {
        "schemaVersion": 1,
        "context": context,
        "xcodeTestSummary": test_summary,
        "performanceTests": performance_tests,
        "blockingNumericThresholds": False,
    }
    output_path = Path(arguments.output)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print_human_summary(report, arguments.artifact_path)


if __name__ == "__main__":
    main()
