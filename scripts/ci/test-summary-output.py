#!/usr/bin/env python3

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SUMMARY = ROOT / "scripts/ci/summarize-tests.py"


class SummaryOutputTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        xcrun = directory / "xcrun"
        xcrun.write_text("""#!/usr/bin/env python3
import json
import os
import sys
result = os.environ.get('SUMMARY_RESULT', 'Passed')
if 'summary' in sys.argv:
    print(json.dumps({'result': result, 'totalTestCount': 4,
                      'passedTests': 2 if result == 'Passed' else 1,
                      'failedTests': 0 if result == 'Passed' else 1,
                      'skippedTests': 1, 'expectedFailures': 1}))
elif 'tests' in sys.argv:
    first_result = 'Passed' if result == 'Passed' else 'Failed'
    print(json.dumps({'testNodes': [{'nodeType': 'Test Suite', 'name': 'Suite', 'children': [
        {'nodeType': 'Test Case', 'name': 'first()', 'result': first_result},
        {'nodeType': 'Test Case', 'name': 'second()', 'result': 'Passed'},
        {'nodeType': 'Test Case', 'name': 'third()', 'result': 'Skipped'},
        {'nodeType': 'Test Case', 'name': 'knownIssue()', 'result': 'Expected Failure'}]}]}))
elif 'xccov' in sys.argv:
    print('UnicornCore.framework 87.50% (14/16)')
else:
    raise SystemExit(2)
""")
        xcrun.chmod(0o755)
        xcodebuild = directory / "xcodebuild"
        xcodebuild.write_text("""#!/usr/bin/env python3
import sys
if '-quiet' not in sys.argv:
    print('routine xcodebuild output')
""")
        xcodebuild.chmod(0o755)
        self.xcodebuild = xcodebuild
        self.env = os.environ | {"PATH": f"{directory}:{os.environ['PATH']}"}

    def run_summary(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SUMMARY), "result.xcresult", *arguments],
            cwd=ROOT,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_lists_every_test_with_aggregate_result_and_coverage(self) -> None:
        result = self.run_summary("--no-color")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Passed             first()", result.stdout)
        self.assertIn("Passed             second()", result.stdout)
        self.assertIn("Skipped            third()", result.stdout)
        self.assertIn("Expected Failure   knownIssue()", result.stdout)
        self.assertIn(
            "Result: Passed | total=4 passed=2 failed=0 skipped=1 expected-failures=1",
            result.stdout,
        )
        self.assertIn("Coverage: UnicornCore.framework 87.50% (14/16)", result.stdout)
        self.assertIn("xcresult: result.xcresult", result.stdout)
        self.assertNotIn("\033[", result.stdout)

    def test_colors_results_counts_coverage_and_artifact_path(self) -> None:
        result = self.run_summary()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("\033[1;32m[PASS]\033[0m", result.stdout)
        self.assertIn("configuration=\033[1;36mDebug\033[0m", result.stdout)
        self.assertIn("total=\033[1;36m4\033[0m", result.stdout)
        self.assertIn("passed=\033[1;32m2\033[0m", result.stdout)
        self.assertIn("failed=\033[1;31m0\033[0m", result.stdout)
        self.assertIn("expected-failures=\033[1;33m1\033[0m", result.stdout)
        self.assertIn("Coverage: \033[1;36m", result.stdout)
        self.assertIn("xcresult: \033[1;36m", result.stdout)

    def test_quiet_test_native_automatically_prints_summary(self) -> None:
        result = subprocess.run(
            ["make", "--silent", "test-native", "XCODEBUILD=" + str(self.xcodebuild),
             "TEST_ROOT=" + self.temp.name + "/results"],
            cwd=ROOT,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("routine xcodebuild output", result.stdout)
        self.assertIn("[PASS]", result.stdout)
        self.assertIn("first()", result.stdout)
        self.assertIn("Coverage:", result.stdout)

    def test_failed_test_run_still_prints_accurate_summary(self) -> None:
        env = self.env | {"SUMMARY_RESULT": "Failed"}
        result = subprocess.run(
            ["make", "--silent", "test-native", "XCODEBUILD=false", "NO_COLOR=1",
             "TEST_ROOT=" + self.temp.name + "/failed"],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[FAIL]", result.stdout)
        self.assertIn(
            "Result: Failed | total=4 passed=1 failed=1 skipped=1 expected-failures=1",
            result.stdout,
        )

    def test_quiet_test_automatically_prints_summary(self) -> None:
        result = subprocess.run(
            ["make", "--silent", "test", "XCODEBUILD=" + str(self.xcodebuild),
             "ARCHS=x86_64", "APP_EXECUTABLE=/usr/bin/true", "NO_COLOR=1",
             "TEST_ROOT=" + self.temp.name + "/complete"],
            cwd=ROOT,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("routine xcodebuild output", result.stdout)
        self.assertIn("[PASS] App build:", result.stdout)
        self.assertIn("[PASS] Tests:", result.stdout)
        self.assertIn("knownIssue()", result.stdout)


if __name__ == "__main__":
    unittest.main()
