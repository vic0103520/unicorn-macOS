#!/usr/bin/env python3

import sys


REQUIRED_CHECKS = (
    "lint",
    "tests-and-coverage",
    "sanitizers",
    "release-bundle",
)


def parse_results(arguments: list[str]) -> dict[str, str]:
    results: dict[str, str] = {}
    for argument in arguments:
        name, separator, result = argument.partition("=")
        if not separator or not name or not result or name in results:
            raise ValueError(f"invalid check result: {argument!r}")
        results[name] = result
    return results


def main(arguments: list[str]) -> int:
    try:
        results = parse_results(arguments)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    if set(results) != set(REQUIRED_CHECKS):
        missing = sorted(set(REQUIRED_CHECKS) - set(results))
        unexpected = sorted(set(results) - set(REQUIRED_CHECKS))
        print(
            f"required check set mismatch: missing={missing} unexpected={unexpected}",
            file=sys.stderr,
        )
        return 1

    unsuccessful = [
        f"{name}={results[name]}"
        for name in REQUIRED_CHECKS
        if results[name] != "success"
    ]
    if unsuccessful:
        print(
            "Required product checks did not all succeed: " + ", ".join(unsuccessful),
            file=sys.stderr,
        )
        return 1

    print("All required product checks succeeded.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
