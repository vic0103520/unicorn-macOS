#!/usr/bin/env python3

from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts/ci/require-successful-checks.py"
WORKFLOW = ROOT / ".github/workflows/ci.yml"
CHECKS = (
    "lint",
    "tests-and-coverage",
    "sanitizers",
    "release-bundle",
)


class RequiredChecksTests(unittest.TestCase):
    def run_checker(
        self, results: dict[str, str]
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(CHECKER), *(f"{name}={result}" for name, result in results.items())],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_all_required_checks_succeed(self) -> None:
        result = self.run_checker(dict.fromkeys(CHECKS, "success"))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_non_successful_required_check_fails(self) -> None:
        for check in CHECKS:
            for outcome in ("failure", "cancelled", "skipped"):
                with self.subTest(check=check, outcome=outcome):
                    results = dict.fromkeys(CHECKS, "success")
                    results[check] = outcome
                    result = self.run_checker(results)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn(f"{check}={outcome}", result.stderr)

    def test_missing_required_check_fails(self) -> None:
        results = dict.fromkeys(CHECKS[:-1], "success")
        result = self.run_checker(results)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("missing=['release-bundle']", result.stderr)

    def test_workflow_runs_aggregate_after_every_required_job(self) -> None:
        workflow = WORKFLOW.read_text()
        aggregate = workflow.split("  build-and-test:\n", maxsplit=1)[1]
        required_lines = (
            "    name: build-and-test",
            "    if: ${{ always() }}",
            "    - lint",
            "    - native-tests-and-coverage",
            "    - sanitizer-verification",
            "    - release-cross-architecture",
            "LINT_RESULT: ${{ needs.lint.result }}",
            "TEST_RESULT: ${{ needs.native-tests-and-coverage.result }}",
            "SANITIZER_RESULT: ${{ needs.sanitizer-verification.result }}",
            "RELEASE_RESULT: ${{ needs.release-cross-architecture.result }}",
            "scripts/ci/require-successful-checks.py",
            '"lint=$LINT_RESULT"',
            '"tests-and-coverage=$TEST_RESULT"',
            '"sanitizers=$SANITIZER_RESULT"',
            '"release-bundle=$RELEASE_RESULT"',
        )
        for line in required_lines:
            with self.subTest(line=line):
                self.assertIn(line, aggregate)


if __name__ == "__main__":
    unittest.main()
