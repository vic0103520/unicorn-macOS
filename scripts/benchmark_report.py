#!/usr/bin/env python3
"""Combine supported xcresulttool exports with reproducibility context."""

import argparse
import hashlib
import json
import math
import os
import platform
import re
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

WALL_METRIC = "com.apple.dt.XCTMetric_Clock.time.monotonic"
CPU_METRIC = "com.apple.dt.XCTMetric_CPU.time"
MEMORY_METRIC = "com.apple.dt.XCTMetric_Memory.physical_peak"

PROVENANCE_SCHEMA_VERSION = 1
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")

WORKLOADS = {
    "testInMemoryInitializationFromProductionKeymap": (
        "In-memory initialization",
        {WALL_METRIC, CPU_METRIC, MEMORY_METRIC},
    ),
    "testTraversalOfEveryCandidateBearingProductionPath": (
        "Candidate-bearing path traversal",
        {WALL_METRIC, CPU_METRIC},
    ),
    "testCommonProductionComposition": (
        "Common production composition",
        {WALL_METRIC, CPU_METRIC},
    ),
    "testDeterministicMixedComposition": (
        "Deterministic mixed composition",
        {WALL_METRIC, CPU_METRIC},
    ),
    "testAccumulatingSoftCommitAndHistory": (
        "Accumulating soft commit and history",
        {WALL_METRIC, CPU_METRIC, MEMORY_METRIC},
    ),
    "testUndoAndHistoryPressureAtCap": (
        "Undo and history pressure",
        {WALL_METRIC, CPU_METRIC, MEMORY_METRIC},
    ),
    "testProductionCandidateNavigationAndSelection": (
        "Production candidate navigation and selection",
        {WALL_METRIC, CPU_METRIC},
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


def keymap_context(keymap_path: Path) -> dict:
    keymap_data = keymap_path.read_bytes()
    return {
        "path": str(keymap_path),
        "byteCount": len(keymap_data),
        "sha256": hashlib.sha256(keymap_data).hexdigest(),
    }


def captured_provenance(keymap_path: Path) -> dict:
    context = version_context()
    context["productionKeymap"] = keymap_context(keymap_path)
    return {
        "schemaVersion": PROVENANCE_SCHEMA_VERSION,
        "context": context,
    }


def require_nonempty_string(value, field: str) -> None:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field} must be a nonempty string")


def validated_provenance(value) -> dict:
    if not isinstance(value, dict):
        raise ValueError("document must be an object")
    if value.get("schemaVersion") != PROVENANCE_SCHEMA_VERSION:
        raise ValueError(
            f"schemaVersion must be {PROVENANCE_SCHEMA_VERSION}"
        )

    context = value.get("context")
    if not isinstance(context, dict):
        raise ValueError("context must be an object")

    require_nonempty_string(context.get("hostArchitecture"), "hostArchitecture")
    require_nonempty_string(context.get("swiftVersion"), "swiftVersion")

    for group_name, fields in {
        "macOS": ("productName", "productVersion", "buildVersion"),
        "xcode": ("version", "buildVersion"),
    }.items():
        group = context.get(group_name)
        if not isinstance(group, dict):
            raise ValueError(f"{group_name} must be an object")
        for field in fields:
            require_nonempty_string(group.get(field), f"{group_name}.{field}")

    keymap = context.get("productionKeymap")
    if not isinstance(keymap, dict):
        raise ValueError("productionKeymap must be an object")
    require_nonempty_string(keymap.get("path"), "productionKeymap.path")
    byte_count = keymap.get("byteCount")
    if isinstance(byte_count, bool) or not isinstance(byte_count, int) or byte_count < 0:
        raise ValueError("productionKeymap.byteCount must be a nonnegative integer")
    digest = keymap.get("sha256")
    if not isinstance(digest, str) or not SHA256_PATTERN.fullmatch(digest):
        raise ValueError("productionKeymap.sha256 must be a lowercase SHA-256 digest")

    return context


def load_provenance(path: Path) -> dict:
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(str(error)) from error
    return validated_provenance(value)


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


def has_complete_measurements(report: dict) -> bool:
    tests = report["performanceTests"]
    names = [test["name"] for test in tests]
    if len(names) != len(WORKLOADS) or set(names) != set(WORKLOADS):
        return False

    for test in tests:
        required_metrics = WORKLOADS[test["name"]][1]
        metrics = test["metrics"]
        identifiers = [metric["identifier"] for metric in metrics]
        if any(identifiers.count(identifier) != 1 for identifier in required_metrics):
            return False
        by_identifier = {metric["identifier"]: metric for metric in metrics}
        if any(
            len(by_identifier[identifier]["measurements"]) != 5
            for identifier in required_metrics
        ):
            return False
    return True


def benchmark_passed(report: dict) -> bool:
    summary = report["xcodeTestSummary"]
    return (
        summary["result"] == "Passed"
        and summary["passedTests"] == len(WORKLOADS)
        and summary["failedTests"] == 0
        and summary["skippedTests"] == 0
        and summary["totalTestCount"] == len(WORKLOADS)
        and has_complete_measurements(report)
    )


def render_human_summary(
    report: dict,
    artifact_path: str,
    use_color: bool,
) -> str:
    test_summary = report["xcodeTestSummary"]
    context = report["context"]
    passed = test_summary["passedTests"]
    failed = test_summary["failedTests"]
    skipped = test_summary["skippedTests"]
    total = test_summary["totalTestCount"]
    status = "COMPLETE" if benchmark_passed(report) else "FAIL"

    title = styled("UNICORN BENCHMARKS", ANSI_CYAN, use_color)
    status_color = ANSI_GREEN if status == "COMPLETE" else ANSI_RED
    counts = f"passed={passed} failed={failed} skipped={skipped} total={total}"
    result = styled(f"{status}  {counts}", status_color, use_color)
    configuration = (
        f"{context['configuration']} · {context['hostArchitecture']} · "
        f"{context['measurementIterations']} iterations"
    )
    lines = [
        f"{title}  {result}",
        styled(configuration, ANSI_CYAN, use_color),
        "",
    ]

    rows = []
    workload_order = {name: index for index, name in enumerate(WORKLOADS)}
    tests = sorted(
        report["performanceTests"],
        key=lambda test: workload_order.get(test["name"], len(workload_order)),
    )
    for test in tests:
        metrics = {metric["identifier"]: metric for metric in test["metrics"]}
        wall = metrics.get(WALL_METRIC)
        cpu = metrics.get(CPU_METRIC)
        memory = metrics.get(MEMORY_METRIC)
        rows.append(
            (
                WORKLOADS.get(test["name"], (test["name"], set()))[0],
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


def required_argument(parser, arguments, name: str) -> str:
    value = getattr(arguments, name)
    if value is None:
        parser.error(f"--{name.replace('_', '-')} is required")
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-provenance", action="store_true")
    parser.add_argument("--keymap")
    parser.add_argument("--provenance")
    parser.add_argument("--test-summary")
    parser.add_argument("--metrics")
    parser.add_argument("--output")
    parser.add_argument("--artifact-path")
    arguments = parser.parse_args()

    output_path = Path(required_argument(parser, arguments, "output"))
    if arguments.capture_provenance:
        keymap_path = Path(required_argument(parser, arguments, "keymap"))
        output_path.write_text(
            json.dumps(captured_provenance(keymap_path), indent=2, sort_keys=True)
            + "\n"
        )
        return

    provenance_path = Path(required_argument(parser, arguments, "provenance"))
    test_summary_path = Path(required_argument(parser, arguments, "test_summary"))
    metrics_path = Path(required_argument(parser, arguments, "metrics"))
    artifact_path = required_argument(parser, arguments, "artifact_path")

    try:
        context = dict(load_provenance(provenance_path))
    except ValueError as error:
        print(f"Invalid benchmark provenance: {error}", file=sys.stderr)
        raise SystemExit(1) from error

    test_summary = json.loads(test_summary_path.read_text())
    metrics = json.loads(metrics_path.read_text())

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
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print_human_summary(report, artifact_path)
    if test_summary["result"] == "Passed" and not benchmark_passed(report):
        print("Benchmark measurements are incomplete.", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
