#!/usr/bin/env python3
"""Combine supported xcresulttool exports with reproducibility context."""

import argparse
import hashlib
import json
import math
import platform
import statistics
import subprocess
from pathlib import Path


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


def print_human_summary(report: dict, artifact_path: str) -> None:
    test_summary = report["xcodeTestSummary"]
    context = report["context"]
    keymap = context["productionKeymap"]
    print(
        f"Benchmark {test_summary['result']}: "
        f"{test_summary['passedTests']}/{test_summary['totalTestCount']} tests "
        f"(Release {context['hostArchitecture']})"
    )
    print(
        f"Fixture: {keymap['byteCount']} bytes, "
        f"SHA-256 {keymap['sha256']}"
    )
    print("Measured batch averages:")
    for test in report["performanceTests"]:
        metrics = {metric["identifier"]: metric for metric in test["metrics"]}
        fields = []
        for identifier, label in [
            ("com.apple.dt.XCTMetric_Clock.time.monotonic", "wall"),
            ("com.apple.dt.XCTMetric_CPU.time", "CPU"),
            ("com.apple.dt.XCTMetric_Memory.physical_peak", "peak memory"),
        ]:
            if identifier in metrics:
                fields.append(f"{label} {display_value(metrics[identifier])}")
        print(f"  {test['name']}: {' | '.join(fields)}")
    print(f"Artifacts: {artifact_path}")
    print("No numeric regression thresholds were applied.")


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
