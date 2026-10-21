#!/usr/bin/env python3
"""Focused tests for benchmark terminal report rendering."""

import errno
import hashlib
import json
import os
import pty
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
EXPECTED_WORKLOAD_METRICS = {
    "testInMemoryInitializationFromProductionKeymap": {WALL, CPU, MEMORY},
    "testTraversalOfEveryCandidateBearingProductionPath": {WALL, CPU},
    "testCommonProductionComposition": {WALL, CPU},
    "testDeterministicMixedComposition": {WALL, CPU},
    "testAccumulatingSoftCommitAndHistory": {WALL, CPU, MEMORY},
    "testUndoAndHistoryPressureAtCap": {WALL, CPU, MEMORY},
    "testProductionCandidateNavigationAndSelection": {WALL, CPU},
}
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
                "failedTests": 0,
                "skippedTests": 0,
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
        self.assertIn(
            "\033[31mFAIL  passed=2 failed=0 skipped=0 total=2\033[0m", colored
        )
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

    def test_failure_result_is_red_with_explicit_counts(self) -> None:
        self.report["xcodeTestSummary"].update(
            {
                "result": "Failed",
                "passedTests": 1,
                "failedTests": 1,
                "skippedTests": 1,
                "totalTestCount": 3,
            }
        )
        colored = benchmark_report.render_human_summary(
            self.report, "build/Benchmark", use_color=True
        )
        self.assertIn(
            "\033[31mFAIL  passed=1 failed=1 skipped=1 total=3\033[0m", colored
        )


class BenchmarkMakeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.tools = Path(self.temporary_directory.name) / "tools"
        self.tools.mkdir()
        self.xcodebuild = self.tools / "xcodebuild"
        self.xcodebuild.write_text(
            """#!/bin/sh
first_argument=${1:-}
if [ "$first_argument" = -version ]; then
    printf 'Xcode %s\nBuild version %s\n' \
        "${CAPTURED_XCODE_VERSION:-Test}" \
        "${CAPTURED_XCODE_BUILD:-TESTBUILD}"
    exit 0
fi
result_bundle=
is_test=0
while [ \"$#\" -gt 0 ]; do
    if [ \"$1\" = test ]; then
        is_test=1
    elif [ \"$1\" = '-resultBundlePath' ]; then
        shift
        result_bundle=$1
    fi
    shift
done
if [ \"${FAIL_XCODEBUILD:-0}\" = 1 ] && [ \"$is_test\" = 1 ]; then
    if [ \"${LEAVE_XCRESULT:-0}\" = 1 ]; then
        mkdir -p \"$result_bundle\"
    fi
    echo 'actionable benchmark failure' >&2
    exit 42
fi
mkdir -p \"$result_bundle\"
echo 'routine xcodebuild output'
echo 'routine xcodebuild diagnostic' >&2
"""
        )
        metrics_export = []
        for name, identifiers in EXPECTED_WORKLOAD_METRICS.items():
            exported_metrics = []
            for identifier in identifiers:
                exported_metrics.append(
                    {
                        "identifier": identifier,
                        "displayName": identifier,
                        "unitOfMeasurement": "kB" if identifier == MEMORY else "s",
                        "measurements": [1.0] * 5,
                    }
                )
            metrics_export.append(
                {
                    "testIdentifier": f"UnicornCorePerformanceTests/{name}()",
                    "testRuns": [{"metrics": exported_metrics}],
                }
            )
        metrics_json = json.dumps(metrics_export, separators=(",", ":"))
        (self.tools / "xcrun").write_text(
            """#!/bin/sh
if [ "$1" = swift ]; then
    printf '%s\n' "${CAPTURED_SWIFT_VERSION:-Swift version test}"
elif [ "$4" = summary ]; then
    if [ \"${FAILED_XCRESULT:-0}\" = 1 ]; then
        printf '%s\\n' '{"result":"Failed","passedTests":6,"failedTests":1,"skippedTests":0,"totalTestCount":7}'
    else
        printf '%s\\n' '{"result":"Passed","passedTests":7,"failedTests":0,"skippedTests":0,"totalTestCount":7}'
    fi
elif [ "$4" = metrics ]; then
    if [ "${FAIL_XCRESULT_EXPORT:-0}" = 1 ]; then
        echo 'metrics export failure' >&2
        exit 44
    elif [ "${INCOMPLETE_METRICS:-0}" = 1 ]; then
        printf '%s\\n' '[]'
    else
        printf '%s\\n' '"""
            + metrics_json
            + """'
    fi
else
    echo 'unexpected xcrun invocation' >&2
    exit 1
fi
"""
        )
        (self.tools / "sw_vers").write_text(
            """#!/bin/sh
case "$1" in
    -productName) printf '%s\n' "${CAPTURED_PRODUCT_NAME:-macOS Test}" ;;
    -productVersion) printf '%s\n' "${CAPTURED_PRODUCT_VERSION:-1.0}" ;;
    -buildVersion) printf '%s\n' "${CAPTURED_OS_BUILD:-TESTOS}" ;;
    *) exit 1 ;;
esac
"""
        )
        for tool in (self.xcodebuild, self.tools / "xcrun", self.tools / "sw_vers"):
            tool.chmod(0o755)

    def write_provenance(self, path: Path, keymap: bytes = b"test keymap") -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "context": {
                        "hostArchitecture": "arm64",
                        "macOS": {
                            "productName": "macOS Test",
                            "productVersion": "1.0",
                            "buildVersion": "TESTOS",
                        },
                        "xcode": {
                            "version": "Xcode Test",
                            "buildVersion": "Build version TESTBUILD",
                        },
                        "swiftVersion": "Swift version test",
                        "productionKeymap": {
                            "path": "captured-keymap.json",
                            "byteCount": len(keymap),
                            "sha256": hashlib.sha256(keymap).hexdigest(),
                        },
                    },
                }
            )
        )

    def run_make(
        self,
        target: str,
        fail: bool = False,
        interactive: bool = False,
        environment_updates=None,
        make_variables=None,
        provide_provenance: bool = True,
    ) -> subprocess.CompletedProcess:
        make_variables = make_variables or []
        benchmark_root = Path(self.temporary_directory.name) / target
        provenance = benchmark_root / "captured-provenance.json"
        for variable in make_variables:
            if variable.startswith("BENCHMARK_ROOT="):
                benchmark_root = Path(variable.split("=", maxsplit=1)[1])
            elif variable.startswith("BENCHMARK_PROVENANCE="):
                provenance = Path(variable.split("=", maxsplit=1)[1])
        if provide_provenance and not provenance.exists():
            self.write_provenance(provenance)
        environment = dict(os.environ)
        environment.pop("CI", None)
        environment.pop("NO_COLOR", None)
        environment["PATH"] = f"{self.tools}:{environment['PATH']}"
        environment.update(environment_updates or {})
        if fail:
            environment["FAIL_XCODEBUILD"] = "1"
        command = [
            "make",
            "--no-print-directory",
            target,
            f"XCODEBUILD={self.xcodebuild}",
            f"BENCHMARK_ROOT={benchmark_root}",
            f"BENCHMARK_PROVENANCE={provenance}",
            "NATIVE_ARCH=arm64",
        ]
        command.extend(make_variables)
        if not interactive:
            return subprocess.run(
                command,
                cwd=Path(__file__).resolve().parents[1],
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )

        master, slave = pty.openpty()
        process = subprocess.Popen(
            command,
            cwd=Path(__file__).resolve().parents[1],
            env=environment,
            stdout=slave,
            stderr=subprocess.STDOUT,
        )
        os.close(slave)
        output = bytearray()
        try:
            while True:
                try:
                    chunk = os.read(master, 4096)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                output.extend(chunk)
        finally:
            os.close(master)
        return subprocess.CompletedProcess(
            command,
            process.wait(),
            output.decode(errors="replace"),
        )

    def test_benchmark_targets_hide_routine_output_and_chain_summary(self) -> None:
        for target in ("benchmark", "benchmark-native"):
            with self.subTest(target=target):
                result = self.run_make(target)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertNotIn("routine xcodebuild", result.stdout)
                self.assertEqual(
                    result.stdout.count(
                        "UNICORN BENCHMARKS  COMPLETE  "
                        "passed=7 failed=0 skipped=0 total=7"
                    ),
                    1,
                )
                self.assertIn("Release · arm64 · 5 iterations", result.stdout)
                self.assertNotIn("\033[", result.stdout)
                summary = (
                    Path(self.temporary_directory.name)
                    / target
                    / "Summary/benchmark-summary.json"
                )
                self.assertTrue(summary.is_file())
                provenance = (
                    Path(self.temporary_directory.name)
                    / target
                    / "captured-provenance.json"
                )
                self.assertTrue(provenance.is_file())
                self.assertIn(
                    "productionKeymap",
                    json.loads(provenance.read_text())["context"],
                )

    def test_passed_xctest_with_incomplete_metrics_fails_report(self) -> None:
        result = self.run_make(
            "benchmark-summary",
            environment_updates={"INCOMPLETE_METRICS": "1"},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "UNICORN BENCHMARKS  FAIL  passed=7 failed=0 skipped=0 total=7",
            result.stdout,
        )
        self.assertIn("Benchmark measurements are incomplete.", result.stdout)
        summary = (
            Path(self.temporary_directory.name)
            / "benchmark-summary"
            / "Summary/benchmark-summary.json"
        )
        self.assertFalse(summary.exists())

    def test_standalone_summary_creates_configured_output_directories(self) -> None:
        root = Path(self.temporary_directory.name) / "standalone"
        result_bundle = root / "existing/Benchmark.xcresult"
        result_bundle.mkdir(parents=True)
        xcode_summary = root / "exports/summary/xcode.json"
        xcode_metrics = root / "exports/metrics/xcode.json"
        benchmark_summary = root / "reports/final/benchmark.json"

        result = self.run_make(
            "benchmark-summary",
            make_variables=[
                f"BENCHMARK_RESULT_BUNDLE={result_bundle}",
                f"BENCHMARK_XCODE_SUMMARY={xcode_summary}",
                f"BENCHMARK_XCODE_METRICS={xcode_metrics}",
                f"BENCHMARK_SUMMARY={benchmark_summary}",
            ],
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(xcode_summary.is_file())
        self.assertTrue(xcode_metrics.is_file())
        self.assertTrue(benchmark_summary.is_file())

    def test_failed_export_removes_all_stale_final_artifacts(self) -> None:
        root = Path(self.temporary_directory.name) / "failed-export"
        outputs = [
            root / "exports/xcode-summary.json",
            root / "exports/xcode-metrics.json",
            root / "reports/benchmark-summary.json",
        ]
        for output in outputs:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text("stale artifact\n")

        result = self.run_make(
            "benchmark-summary",
            environment_updates={"FAIL_XCRESULT_EXPORT": "1"},
            make_variables=[
                f"BENCHMARK_XCODE_SUMMARY={outputs[0]}",
                f"BENCHMARK_XCODE_METRICS={outputs[1]}",
                f"BENCHMARK_SUMMARY={outputs[2]}",
            ],
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("metrics export failure", result.stdout)
        self.assertIn("[FAIL] Benchmark summary export:", result.stdout)
        for output in outputs:
            self.assertFalse(output.exists())
            self.assertFalse(Path(f"{output}.tmp").exists())

    def test_success_atomically_replaces_all_final_artifacts(self) -> None:
        root = Path(self.temporary_directory.name) / "successful-export"
        outputs = [
            root / "exports/xcode-summary.json",
            root / "exports/xcode-metrics.json",
            root / "reports/benchmark-summary.json",
        ]
        for output in outputs:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text("stale artifact\n")

        result = self.run_make(
            "benchmark-summary",
            make_variables=[
                f"BENCHMARK_XCODE_SUMMARY={outputs[0]}",
                f"BENCHMARK_XCODE_METRICS={outputs[1]}",
                f"BENCHMARK_SUMMARY={outputs[2]}",
            ],
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(json.loads(outputs[0].read_text())["result"], "Passed")
        self.assertEqual(len(json.loads(outputs[1].read_text())), 7)
        self.assertEqual(json.loads(outputs[2].read_text())["schemaVersion"], 1)
        for output in outputs:
            self.assertNotEqual(output.read_text(), "stale artifact\n")
            self.assertFalse(Path(f"{output}.tmp").exists())

    def test_missing_provenance_fails_and_removes_final_artifacts(self) -> None:
        root = Path(self.temporary_directory.name) / "missing-provenance"
        provenance = root / "missing.json"
        outputs = [root / "summary.json", root / "metrics.json", root / "report.json"]
        for output in outputs:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text("stale artifact\n")

        result = self.run_make(
            "benchmark-summary",
            provide_provenance=False,
            make_variables=[
                f"BENCHMARK_PROVENANCE={provenance}",
                f"BENCHMARK_XCODE_SUMMARY={outputs[0]}",
                f"BENCHMARK_XCODE_METRICS={outputs[1]}",
                f"BENCHMARK_SUMMARY={outputs[2]}",
            ],
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid benchmark provenance:", result.stdout)
        for output in outputs:
            self.assertFalse(output.exists())

    def test_malformed_provenance_fails_and_removes_final_artifacts(self) -> None:
        root = Path(self.temporary_directory.name) / "malformed-provenance"
        provenance = root / "malformed.json"
        provenance.parent.mkdir(parents=True)
        provenance.write_text('{"schemaVersion":1,"context":{}}')
        outputs = [root / "summary.json", root / "metrics.json", root / "report.json"]
        for output in outputs:
            output.write_text("stale artifact\n")

        result = self.run_make(
            "benchmark-summary",
            provide_provenance=False,
            make_variables=[
                f"BENCHMARK_PROVENANCE={provenance}",
                f"BENCHMARK_XCODE_SUMMARY={outputs[0]}",
                f"BENCHMARK_XCODE_METRICS={outputs[1]}",
                f"BENCHMARK_SUMMARY={outputs[2]}",
            ],
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("hostArchitecture must be a nonempty string", result.stdout)
        for output in outputs:
            self.assertFalse(output.exists())

    def test_regeneration_uses_captured_keymap_and_system_provenance(self) -> None:
        root = Path(self.temporary_directory.name) / "immutable-provenance"
        provenance = root / "results/run.provenance.json"
        keymap = Path(self.temporary_directory.name) / "immutable-keymap.json"
        keymap.parent.mkdir(parents=True, exist_ok=True)
        measured_keymap = b'{"measured":true}'
        keymap.write_bytes(measured_keymap)
        provenance.parent.mkdir(parents=True)
        variables = [
            f"BENCHMARK_ROOT={root}",
            f"BENCHMARK_PROVENANCE={provenance}",
        ]
        measured_environment = {
            "CAPTURED_XCODE_VERSION": "Measured-16.1",
            "CAPTURED_XCODE_BUILD": "MeasuredBuild",
            "CAPTURED_SWIFT_VERSION": "Measured Swift",
            "CAPTURED_PRODUCT_VERSION": "15.1",
            "CAPTURED_OS_BUILD": "MeasuredOSBuild",
        }

        environment = dict(os.environ)
        environment["PATH"] = f"{self.tools}:{environment['PATH']}"
        environment.update(measured_environment)
        captured_result = subprocess.run(
            [
                "python3",
                "scripts/benchmark_report.py",
                "--capture-provenance",
                "--keymap",
                str(keymap),
                "--output",
                str(provenance),
            ],
            cwd=Path(__file__).resolve().parents[1],
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(captured_result.returncode, 0, captured_result.stdout)
        captured = json.loads(provenance.read_text())["context"]

        keymap.write_bytes(b'{"workspace":"changed"}')
        regenerated = self.run_make(
            "benchmark-summary",
            environment_updates={
                "CAPTURED_XCODE_VERSION": "Changed-99",
                "CAPTURED_XCODE_BUILD": "ChangedBuild",
                "CAPTURED_SWIFT_VERSION": "Changed Swift",
                "CAPTURED_PRODUCT_VERSION": "99.0",
                "CAPTURED_OS_BUILD": "ChangedOSBuild",
            },
            make_variables=variables,
        )

        self.assertEqual(regenerated.returncode, 0, regenerated.stdout)
        report = json.loads((root / "Summary/benchmark-summary.json").read_text())
        self.assertEqual(report["context"]["xcode"], captured["xcode"])
        self.assertEqual(report["context"]["macOS"], captured["macOS"])
        self.assertEqual(report["context"]["swiftVersion"], captured["swiftVersion"])
        self.assertEqual(
            report["context"]["productionKeymap"],
            {
                "path": str(keymap),
                "byteCount": len(measured_keymap),
                "sha256": hashlib.sha256(measured_keymap).hexdigest(),
            },
        )

    def test_benchmark_failure_replays_actionable_build_output(self) -> None:
        result = self.run_make("benchmark-native", fail=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("actionable benchmark failure", result.stdout)
        self.assertIn("Core benchmarks: configuration=Release arch=arm64 exit=42", result.stdout)
        self.assertNotIn("UNICORN BENCHMARKS", result.stdout)
        self.assertNotIn("\033[", result.stdout)

    def test_benchmark_start_removes_independently_configured_outputs(self) -> None:
        output_directory = Path(self.temporary_directory.name) / "external-outputs"
        output_directory.mkdir()
        xcode_summary = output_directory / "xcode-summary.json"
        xcode_metrics = output_directory / "xcode-metrics.json"
        benchmark_summary = output_directory / "benchmark-summary.json"
        sibling = output_directory / "keep.txt"
        for output in (xcode_summary, xcode_metrics, benchmark_summary):
            output.write_text("stale\n")
        sibling.write_text("keep\n")

        result = self.run_make(
            "benchmark-native",
            fail=True,
            make_variables=[
                f"BENCHMARK_XCODE_SUMMARY={xcode_summary}",
                f"BENCHMARK_XCODE_METRICS={xcode_metrics}",
                f"BENCHMARK_SUMMARY={benchmark_summary}",
            ],
        )

        self.assertEqual(result.returncode, 2)
        for output in (xcode_summary, xcode_metrics, benchmark_summary):
            self.assertFalse(output.exists())
        self.assertTrue(output_directory.is_dir())
        self.assertEqual(sibling.read_text(), "keep\n")

    def test_benchmark_failure_with_result_emits_summary_once(self) -> None:
        result = self.run_make(
            "benchmark-native",
            fail=True,
            environment_updates={
                "LEAVE_XCRESULT": "1",
                "FAILED_XCRESULT": "1",
                "INCOMPLETE_METRICS": "1",
            },
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("actionable benchmark failure", result.stdout)
        self.assertEqual(
            result.stdout.count(
                "UNICORN BENCHMARKS  FAIL  "
                "passed=6 failed=1 skipped=0 total=7"
            ),
            1,
        )

    def test_benchmark_failure_color_respects_environment(self) -> None:
        colored = self.run_make("benchmark-native", fail=True, interactive=True)
        self.assertIn("\033[1;31m[FAIL]\033[0m", colored.stdout)

        for environment in ({"CI": ""}, {"NO_COLOR": ""}, {"NO_COLOR": "0"}):
            with self.subTest(environment=environment):
                plain = self.run_make(
                    "benchmark-native",
                    fail=True,
                    interactive=True,
                    environment_updates=environment,
                )
                self.assertEqual(plain.returncode, 2)
                self.assertIn("[FAIL] Core benchmarks", plain.stdout)
                self.assertNotIn("\033[", plain.stdout)


class MainBehaviorPreservationTests(unittest.TestCase):
    def test_standard_test_keeps_main_reporting_and_native_app_build(self) -> None:
        makefile = (Path(__file__).resolve().parents[1] / "Makefile").read_text()
        test_recipe = makefile.split("\ntest:\n", maxsplit=1)[1].split(
            "\n# Core test execution", maxsplit=1
        )[0]

        self.assertIn('ARCH="$(NATIVE_ARCH)"', test_recipe)
        self.assertIn("summary_status=0", test_recipe)
        self.assertIn("Warning: test result reporting failed", test_recipe)
        self.assertIn('[ "$$test_status" -eq 0 ] || exit "$$test_status"', test_recipe)
        self.assertIn('[ "$$build_status" -eq 0 ] || exit "$$build_status"', test_recipe)
        self.assertNotIn("ARCH=universal", test_recipe)

    def test_standard_build_keeps_main_native_default_and_universal_alias(self) -> None:
        makefile = (Path(__file__).resolve().parents[1] / "Makefile").read_text()

        self.assertIn("ARCH ?= $(shell uname -m)", makefile)
        self.assertIn(
            "BUILD_ARCHS = $(if $(filter universal,$(ARCH)),arm64 x86_64,$(ARCH))",
            makefile,
        )
        self.assertIn('build CONFIG="$(CONFIG)" ARCH=universal', makefile)
        self.assertIn("install: ARCH = universal", makefile)


if __name__ == "__main__":
    unittest.main()
