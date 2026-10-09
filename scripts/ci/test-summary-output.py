#!/usr/bin/env python3

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SUMMARY = ROOT / "scripts/ci/summarize-tests.py"
ANSI = re.compile(r"\x1b\[[0-9;]*m")


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
result = os.environ.get("SUMMARY_RESULT", "Passed")
failed = 0 if result == "Passed" else 1
if "summary" in sys.argv:
    print(json.dumps({"result": result, "totalTestCount": 2,
                      "passedTests": 2 - failed, "failedTests": failed,
                      "skippedTests": 0, "expectedFailures": 0}))
elif "tests" in sys.argv:
    first = "Passed" if result == "Passed" else "Failed"
    print(json.dumps({"testNodes": [{"nodeType": "Test Suite", "name": "Suite",
        "children": [{"nodeType": "Test Case", "name": "first()", "result": first},
                     {"nodeType": "Test Case", "name": "second()", "result": "Passed"}]}]}))
elif "xccov" in sys.argv:
    print("UnicornCore.framework 87.50% (14/16)")
else:
    raise SystemExit(2)
""")
        xcrun.chmod(0o755)
        self.env = os.environ | {"PATH": f"{directory}:{os.environ['PATH']}"}

    def run_summary(
        self, *arguments: str, result: str = "Passed"
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SUMMARY), "result.xcresult", *arguments],
            cwd=ROOT,
            env=self.env | {"SUMMARY_RESULT": result},
            text=True,
            capture_output=True,
            check=False,
        )

    def test_success_reports_required_result_and_artifacts(self) -> None:
        result = self.run_summary()
        output = ANSI.sub("", result.stdout)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Result: Passed | total=2 passed=2 failed=0", output)
        self.assertIn("Coverage: UnicornCore.framework 87.50% (14/16)", output)
        self.assertIn("xcresult: result.xcresult", output)

    def test_failure_returns_nonzero_with_test_diagnostics(self) -> None:
        result = self.run_summary("--no-color", result="Failed")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed             first()", result.stdout)
        self.assertIn("Result: Failed | total=2 passed=1 failed=1", result.stdout)
        self.assertIn("xcresult: result.xcresult", result.stdout)

    def test_no_color_output_contains_no_ansi_escapes(self) -> None:
        result = self.run_summary("--no-color")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotRegex(result.stdout, ANSI)


if __name__ == "__main__":
    unittest.main()
