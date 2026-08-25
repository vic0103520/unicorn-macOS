#!/usr/bin/env python3
"""Focused tests for benchmark terminal report rendering."""

import re
import unittest

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
        self.assertIn("\033[32mPASS\033[0m", colored)
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


if __name__ == "__main__":
    unittest.main()
