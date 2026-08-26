#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys


COLORS = {
    "green": "\033[1;32m",
    "red": "\033[1;31m",
    "yellow": "\033[1;33m",
    "cyan": "\033[1;36m",
    "reset": "\033[0m",
}


def styled(value: object, color: str, enabled: bool) -> str:
    text = str(value)
    return f"{COLORS[color]}{text}{COLORS['reset']}" if enabled else text


def command_json(arguments: list[str]) -> dict:
    return json.loads(subprocess.check_output(arguments, text=True))


def test_cases(nodes: list[dict]) -> list[tuple[str, str]]:
    cases: list[tuple[str, str]] = []
    for node in nodes:
        if node.get("nodeType") == "Test Case":
            cases.append((node["name"], node.get("result", "unknown")))
        cases.extend(test_cases(node.get("children", [])))
    return cases


def padded(value: str, width: int, color: str, enabled: bool) -> str:
    return styled(value.ljust(width), color, enabled)


def result_color(result: str) -> str:
    if result == "Passed":
        return "green"
    if result == "Skipped" or result == "Expected Failure":
        return "yellow"
    return "red"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("result_bundle")
    parser.add_argument("--configuration", default="Debug")
    parser.add_argument("--no-color", action="store_true")
    args = parser.parse_args()
    color = not args.no_color

    try:
        summary = command_json([
            "xcrun", "xcresulttool", "get", "test-results", "summary",
            "--path", args.result_bundle,
        ])
        tests = command_json([
            "xcrun", "xcresulttool", "get", "test-results", "tests",
            "--path", args.result_bundle,
        ])
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"{styled('[FAIL]', 'red', color)} Test summary: {error}", file=sys.stderr)
        return 1

    try:
        coverage = subprocess.check_output([
            "xcrun", "xccov", "view", "--report", "--only-targets",
            args.result_bundle,
        ], text=True, stderr=subprocess.PIPE).strip()
    except (OSError, subprocess.CalledProcessError):
        coverage = "unavailable"

    result = summary.get("result", "unknown")
    passed = summary.get("passedTests", 0)
    failed = summary.get("failedTests", 0)
    skipped = summary.get("skippedTests", 0)
    expected_failures = summary.get("expectedFailures", 0)
    total = summary.get(
        "totalTestCount", passed + failed + skipped + expected_failures
    )
    cases = test_cases(tests.get("testNodes", []))

    label = "[PASS]" if result == "Passed" and failed == 0 else "[FAIL]"
    print(
        f"{styled(label, result_color(result), color)} Tests: "
        f"configuration={styled(args.configuration, 'cyan', color)}"
    )
    for name, case_result in cases:
        print(f"  {padded(case_result, 18, result_color(case_result), color)} {name}")
    print(
        "  Result: "
        f"{styled(result, result_color(result), color)} | "
        f"total={styled(total, 'cyan', color)} "
        f"passed={styled(passed, 'green', color)} "
        f"failed={styled(failed, 'red', color)} "
        f"skipped={styled(skipped, 'yellow', color)} "
        f"expected-failures={styled(expected_failures, 'yellow', color)}"
    )
    print(f"  Coverage: {styled(coverage or 'unavailable', 'cyan', color)}")
    print(f"  xcresult: {styled(args.result_bundle, 'cyan', color)}")
    return 0 if result == "Passed" and failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
