#!/usr/bin/env python3
"""Focused tests for benchmark terminal report rendering."""

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

import benchmark_report


class FakeStream:
    def __init__(self, interactive: bool):
        self.interactive = interactive

    def isatty(self) -> bool:
        return self.interactive


def metric(identifier: str, value: float, unit: str, variation: float) -> dict:
    return {
        "identifier": identifier,
        "displayName": identifier,
        "unitOfMeasurement": unit,
        "measurements": [value] * 5,
        "average": value,
        "relativeStandardDeviationPercent": variation,
    }


WALL = "com.apple.dt.XCTMetric_Clock.time.monotonic"
CPU = "com.apple.dt.XCTMetric_CPU.time"
MEMORY = "com.apple.dt.XCTMetric_Memory.physical_peak"
ANSI_PATTERN = re.compile(r"\x1b\[[0-9;]*m")


class BenchmarkReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.report = {
            "context": {
                "configuration": "Release",
                "hostArchitecture": "arm64",
                "measurementIterations": 5,
            },
            "xcodeTestSummary": {
                "result": "Passed",
                "passedTests": 2,
                "totalTestCount": 2,
            },
            "performanceTests": [
                {
                    "name": "testInMemoryInitializationFromProductionKeymap",
                    "metrics": [
                        metric(WALL, 0.012345, "s", 1.25),
                        metric(CPU, 0.01, "s", 2.0),
                        metric(MEMORY, 2048, "kB", 0.0),
                    ],
                },
                {
                    "name": "testCommonProductionComposition",
                    "metrics": [
                        metric(WALL, 1.2, "s", 12.5),
                        metric(CPU, 0.95, "s", 3.0),
                    ],
                },
            ],
        }

    def test_colored_report_styles_without_changing_plain_alignment(self) -> None:
        plain = benchmark_report.render_human_summary(
            self.report, "build/Benchmark", use_color=False
        )
        colored = benchmark_report.render_human_summary(
            self.report, "build/Benchmark", use_color=True
        )

        self.assertEqual(ANSI_PATTERN.sub("", colored), plain)
        self.assertIn("\033[36mUNICORN BENCHMARKS\033[0m", colored)
        self.assertIn("\033[32mPASS  2/2\033[0m", colored)
        self.assertIn("\033[36mRelease · arm64 · 5 iterations\033[0m", colored)
        self.assertIn("\033[1mIn-memory initialization\033[0m", colored)
        self.assertIn("Results: \033[36mbuild/Benchmark\033[0m", colored)
        self.assertIn("Thresholds: \033[33mnot enforced\033[0m", colored)

        table = plain.splitlines()[3:6]
        header, first_row, second_row = table
        expected_column_ends = [
            header.index(heading) + len(heading)
            for heading in ("WALL", "CPU", "PEAK MEMORY", "VARIATION")
        ]
        for row, values in [
            (first_row, ("12.345 ms", "10.000 ms", "2.00 MiB", "1.25%")),
            (second_row, ("1200.000 ms", "950.000 ms", "-", "12.50%")),
        ]:
            search_from = 0
            for value, expected_end in zip(values, expected_column_ends):
                value_start = row.index(value, search_from)
                self.assertEqual(value_start + len(value), expected_end)
                search_from = expected_end

    def test_color_requires_interactive_terminal(self) -> None:
        self.assertTrue(benchmark_report.color_enabled(FakeStream(True), {}))
        self.assertFalse(benchmark_report.color_enabled(FakeStream(False), {}))
        self.assertFalse(benchmark_report.color_enabled(FakeStream(True), {"CI": "true"}))
        self.assertFalse(
            benchmark_report.color_enabled(FakeStream(True), {"NO_COLOR": ""})
        )
        self.assertFalse(
            benchmark_report.color_enabled(FakeStream(True), {"NO_COLOR": "0"})
        )

    def test_failure_result_is_red(self) -> None:
        self.report["xcodeTestSummary"]["result"] = "Failed"
        colored = benchmark_report.render_human_summary(
            self.report, "build/Benchmark", use_color=True
        )
        self.assertIn("\033[31mFAIL  2/2\033[0m", colored)


class BenchmarkMakeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.tools = Path(self.temporary_directory.name) / "tools"
        self.tools.mkdir()
        self.xcodebuild = self.tools / "xcodebuild"
        self.xcodebuild.write_text(
            """#!/bin/sh
if [ \"${FAIL_XCODEBUILD:-0}\" = 1 ]; then
    echo 'actionable benchmark failure' >&2
    exit 42
fi
while [ \"$#\" -gt 0 ]; do
    if [ \"$1\" = '-resultBundlePath' ]; then
        shift
        mkdir -p \"$1\"
    fi
    shift
done
echo 'routine xcodebuild output'
echo 'routine xcodebuild diagnostic' >&2
"""
        )
        (self.tools / "xcrun").write_text(
            """#!/bin/sh
if [ \"$1\" = swift ]; then
    echo 'Swift version test'
elif [ \"$4\" = summary ]; then
    printf '%s\\n' '{"result":"Passed","passedTests":7,"totalTestCount":7}'
elif [ \"$4\" = metrics ]; then
    printf '%s\\n' '[]'
else
    echo 'unexpected xcrun invocation' >&2
    exit 1
fi
"""
        )
        for tool in (self.xcodebuild, self.tools / "xcrun"):
            tool.chmod(0o755)

    def run_make(self, target: str, fail: bool = False) -> subprocess.CompletedProcess:
        benchmark_root = Path(self.temporary_directory.name) / target
        environment = dict(os.environ)
        environment["PATH"] = f"{self.tools}:{environment['PATH']}"
        if fail:
            environment["FAIL_XCODEBUILD"] = "1"
        return subprocess.run(
            [
                "make",
                "--no-print-directory",
                target,
                f"XCODEBUILD={self.xcodebuild}",
                f"BENCHMARK_ROOT={benchmark_root}",
                "NATIVE_ARCH=arm64",
                "NO_COLOR=1",
            ],
            cwd=Path(__file__).resolve().parents[1],
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )

    def test_benchmark_targets_hide_routine_output_and_chain_summary(self) -> None:
        for target in ("benchmark", "benchmark-native"):
            with self.subTest(target=target):
                result = self.run_make(target)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertNotIn("routine xcodebuild", result.stdout)
                self.assertEqual(result.stdout.count("UNICORN BENCHMARKS  PASS  7/7"), 1)
                self.assertIn("Release · arm64 · 5 iterations", result.stdout)
                self.assertNotIn("\033[", result.stdout)
                summary = (
                    Path(self.temporary_directory.name)
                    / target
                    / "Summary/benchmark-summary.json"
                )
                self.assertTrue(summary.is_file())

    def test_benchmark_failure_replays_actionable_build_output(self) -> None:
        result = self.run_make("benchmark-native", fail=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("actionable benchmark failure", result.stdout)
        self.assertIn("Core benchmarks: configuration=Release arch=arm64 exit=42", result.stdout)
        self.assertNotIn("UNICORN BENCHMARKS", result.stdout)


if __name__ == "__main__":
    unittest.main()
