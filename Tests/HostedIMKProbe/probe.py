#!/usr/bin/env python3
"""Bounded GitHub-hosted InputMethodKit feasibility probe."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Any

SCHEMA_VERSION = 1
TEXT_VIEW_ID = "unicorn-hosted-imk-probe-text-view"
ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"
MAX_COMMAND_OUTPUT = 32_768
MAX_TRANSCRIPT_VALUE = 8_192


def timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def atomic_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def load_json(path: pathlib.Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def bounded(value: str, limit: int = MAX_COMMAND_OUTPUT) -> str:
    if len(value) <= limit:
        return value
    return f"[truncated to last {limit} characters]\n" + value[-limit:]


def run_command(command: list[str], timeout: int = 20) -> dict[str, Any]:
    started = timestamp()
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "command": command,
            "startedAt": started,
            "completedAt": timestamp(),
            "exitCode": completed.returncode,
            "stdout": bounded(completed.stdout),
            "stderr": bounded(completed.stderr),
            "timedOut": False,
        }
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
        stderr = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else (error.stderr or "")
        return {
            "command": command,
            "startedAt": started,
            "completedAt": timestamp(),
            "exitCode": None,
            "stdout": bounded(stdout),
            "stderr": bounded(stderr),
            "timedOut": True,
        }
    except OSError as error:
        return {
            "command": command,
            "startedAt": started,
            "completedAt": timestamp(),
            "exitCode": None,
            "stdout": "",
            "stderr": str(error),
            "timedOut": False,
        }


def update_summary(evidence: pathlib.Path, updates: dict[str, Any]) -> dict[str, Any]:
    path = evidence / "summary.json"
    summary = load_json(path, {})
    summary.update(updates)
    atomic_json(path, summary)
    return summary


def initialize(evidence: pathlib.Path) -> None:
    evidence.mkdir(parents=True, exist_ok=True)
    summary = {
        "schemaVersion": SCHEMA_VERSION,
        "probe": "github-hosted-arm64-macos-unicorn-inputmethodkit",
        "startedAt": timestamp(),
        "status": "running",
        "assertion": {
            "keys": ["backslash", "l", "enter"],
            "finalTextScalars": ["U+03BB"],
            "markedTextEnded": True,
            "testKeymapRemapping": False,
        },
        "hostedRunner": {
            "requestedLabel": "macos-15",
            "expectedArchitecture": "arm64",
            "repositoryVisibility": "public",
            "availableStandardArm64LabelsInspected": [
                "macos-latest",
                "macos-14",
                "macos-15",
                "macos-26",
            ],
        },
        "requirementsBasis": {
            "githubHostedRunnerReference": "https://docs.github.com/en/actions/reference/runners/github-hosted-runners",
            "mac2GettingStarted": "https://appium.github.io/appium-mac2-driver/latest/getting-started/",
            "mac2KeysReference": "https://appium.github.io/appium-mac2-driver/latest/reference/execute-methods/#macos-keys",
            "mac2Version": "4.2.0",
            "appiumVersion": "3.7.0",
            "tisRegistrationAPI": "TISRegisterInputSource",
            "tisSelectionAPI": "TISSelectInputSource",
            "cgEventAccessibilityPreflightAPI": "CGPreflightPostEventAccess",
        },
        "github": {
            key: os.environ.get(key)
            for key in (
                "GITHUB_ACTIONS",
                "GITHUB_REPOSITORY",
                "GITHUB_RUN_ID",
                "GITHUB_RUN_ATTEMPT",
                "GITHUB_SHA",
                "GITHUB_REF",
                "RUNNER_NAME",
                "RUNNER_ARCH",
                "RUNNER_OS",
                "ImageOS",
                "ImageVersion",
            )
        },
    }
    atomic_json(evidence / "summary.json", summary)


def preflight(evidence: pathlib.Path, helper: pathlib.Path) -> None:
    uid = os.getuid()
    xcode_helper = pathlib.Path(
        "/Applications/Xcode.app/Contents/Developer/Platforms/"
        "MacOSX.platform/Developer/Library/Xcode/Agents/Xcode Helper.app"
    )
    commands = {
        "uname": ["uname", "-a"],
        "architecture": ["uname", "-m"],
        "archCommand": ["arch"],
        "systemVersion": ["sw_vers"],
        "identity": ["id"],
        "loggedInUsers": ["who"],
        "consoleUser": ["stat", "-f", "%Su", "/dev/console"],
        "windowServer": ["pgrep", "-alf", "WindowServer"],
        "aquaLaunchDomain": ["launchctl", "print", f"gui/{uid}"],
        "displayProfile": ["system_profiler", "-json", "SPDisplaysDataType"],
        "xcodeVersion": ["xcodebuild", "-version"],
        "xcodeSelect": ["xcode-select", "-p"],
        "developerSecurity": ["DevToolsSecurity", "-status"],
        "automationModeBefore": ["automationmodetool"],
        "xcodeHelperMetadata": ["codesign", "-dvv", str(xcode_helper)],
        "nodeVersion": ["node", "--version"],
        "npmVersion": ["npm", "--version"],
    }
    results = {name: run_command(command) for name, command in commands.items()}
    automation_enable = run_command(
        [
            "sudo",
            "-n",
            "automationmodetool",
            "enable-automationmode-without-authentication",
        ],
        timeout=30,
    )
    results["automationModeEnable"] = automation_enable
    results["automationModeAfter"] = run_command(["automationmodetool"])
    session_result = run_command(
        [str(helper), "session", str(evidence / "aqua-session.json")]
    )
    results["nativeSessionProbe"] = session_result
    sources_result = run_command(
        [str(helper), "sources", str(evidence / "input-sources-before.json")],
        timeout=30,
    )
    results["initialInputSources"] = sources_result
    atomic_json(evidence / "environment.json", results)

    aqua = load_json(evidence / "aqua-session.json", {})
    architecture = results["architecture"].get("stdout", "").strip()
    update_summary(
        evidence,
        {
            "environment": {
                "architecture": architecture,
                "runnerArchitecture": os.environ.get("RUNNER_ARCH"),
                "aquaSession": aqua,
                "windowServerProbe": results["windowServer"],
                "aquaLaunchDomainExitCode": results["aquaLaunchDomain"].get("exitCode"),
                "automationMode": {
                    "before": results["automationModeBefore"],
                    "enable": automation_enable,
                    "after": results["automationModeAfter"],
                },
                "xcodeHelperExists": xcode_helper.exists(),
                "xcodeHelperAccessibilityRequirement": "Mac2 requires Xcode Helper Accessibility access",
            }
        },
    )


class WebDriverError(RuntimeError):
    def __init__(self, method: str, path: str, status: int | None, body: Any):
        super().__init__(f"{method} {path} failed with HTTP {status}: {body}")
        self.method = method
        self.path = path
        self.status = status
        self.body = body


class WebDriver:
    def __init__(self, base_url: str, transcript: pathlib.Path):
        self.base_url = base_url.rstrip("/")
        self.transcript = transcript

    def request(
        self,
        method: str,
        path: str,
        payload: Any | None = None,
        timeout: int = 130,
    ) -> Any:
        data = None
        headers = {"Accept": "application/json"}
        if payload is not None:
            data = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            self.base_url + path, data=data, method=method, headers=headers
        )
        status: int | None = None
        raw = b""
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                status = response.status
                raw = response.read()
        except urllib.error.HTTPError as error:
            status = error.code
            raw = error.read()
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            self._record(method, path, payload, None, {"transportError": str(error)})
            raise WebDriverError(method, path, None, str(error)) from error

        try:
            body = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            body = {"nonJSONBody": raw.decode(errors="replace")}
        self._record(method, path, payload, status, body)
        if status is None or status >= 400:
            raise WebDriverError(method, path, status, body)
        if isinstance(body, dict) and isinstance(body.get("value"), dict):
            value = body["value"]
            if value.get("error"):
                raise WebDriverError(method, path, status, body)
        return body

    def _record(self, method: str, path: str, payload: Any, status: Any, body: Any) -> None:
        record = {
            "timestamp": timestamp(),
            "method": method,
            "path": path,
            "payload": self._bounded_json(payload),
            "status": status,
            "response": self._bounded_json(body),
        }
        with self.transcript.open("a") as handle:
            handle.write(json.dumps(record, sort_keys=True) + "\n")

    @staticmethod
    def _bounded_json(value: Any) -> Any:
        try:
            serialized = json.dumps(value, sort_keys=True)
        except (TypeError, ValueError):
            return str(value)
        if len(serialized) <= MAX_TRANSCRIPT_VALUE:
            return value
        return {
            "truncated": True,
            "length": len(serialized),
            "sha256": hashlib.sha256(serialized.encode()).hexdigest(),
        }


def wait_for_server(driver: WebDriver, timeout: int = 45) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    last_error = ""
    while time.monotonic() < deadline:
        try:
            response = driver.request("GET", "/status", timeout=3)
            return {"ready": True, "response": response, "timestamp": timestamp()}
        except WebDriverError as error:
            last_error = str(error)
            time.sleep(0.5)
    return {"ready": False, "error": last_error, "timestamp": timestamp()}


def create_bundle_session(
    driver: WebDriver,
    bundle_id: str,
    extra_capabilities: dict[str, Any] | None = None,
) -> tuple[str, Any]:
    capabilities: dict[str, Any] = {
        "platformName": "mac",
        "appium:automationName": "mac2",
        "appium:bundleId": bundle_id,
        "appium:showServerLogs": True,
        "appium:serverStartupTimeout": 120_000,
    }
    capabilities.update(extra_capabilities or {})
    response = driver.request(
        "POST",
        "/session",
        {"capabilities": {"alwaysMatch": capabilities, "firstMatch": [{}]}},
        timeout=150,
    )
    session_id = response.get("sessionId")
    if not session_id and isinstance(response.get("value"), dict):
        session_id = response["value"].get("sessionId")
    if not session_id:
        raise WebDriverError("POST", "/session", 200, response)
    return session_id, response


def create_session(
    driver: WebDriver,
    client_app: pathlib.Path,
    current_diagnostics: pathlib.Path,
    timeline: pathlib.Path,
) -> tuple[str, Any]:
    capabilities = {
        "platformName": "mac",
        "appium:automationName": "mac2",
        "appium:bundleId": "dev.unicorn.hosted-imk-probe.client",
        "appium:appPath": str(client_app),
        "appium:environment": {
            "UNICORN_PROBE_DIAGNOSTICS": str(current_diagnostics),
            "UNICORN_PROBE_TIMELINE": str(timeline),
        },
        "appium:showServerLogs": True,
        "appium:serverStartupTimeout": 120_000,
    }
    return create_bundle_session(
        driver,
        "dev.unicorn.hosted-imk-probe.client",
        {key: value for key, value in capabilities.items() if key != "appium:bundleId"},
    )


def find_element(
    driver: WebDriver,
    session_id: str,
    locators: list[tuple[str, str]],
    timeout: int = 15,
) -> str:
    deadline = time.monotonic() + timeout
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        for strategy, value in locators:
            try:
                response = driver.request(
                    "POST",
                    f"/session/{session_id}/element",
                    {"using": strategy, "value": value},
                )
                element = response.get("value", {})
                element_id = element.get(ELEMENT_KEY) or element.get("ELEMENT")
                if element_id:
                    return element_id
            except WebDriverError as error:
                last_error = error
        time.sleep(0.5)
    raise RuntimeError(f"Element was not found through accessibility: {last_error}")


def find_text_view(driver: WebDriver, session_id: str, timeout: int = 30) -> str:
    return find_element(
        driver,
        session_id,
        [("accessibility id", TEXT_VIEW_ID)],
        timeout=timeout,
    )


def attribute(driver: WebDriver, session_id: str, element_id: str, name: str) -> Any:
    try:
        response = driver.request(
            "GET", f"/session/{session_id}/element/{element_id}/attribute/{name}"
        )
        return response.get("value")
    except WebDriverError as error:
        return {"error": str(error)}


def element_snapshot(driver: WebDriver, session_id: str, element_id: str) -> dict[str, Any]:
    return {
        name: attribute(driver, session_id, element_id, name)
        for name in (
            "identifier",
            "elementType",
            "value",
            "amHasKeyboardInputFocus",
            "enabled",
            "visible",
        )
    }


def diagnostics_snapshot(path: pathlib.Path) -> dict[str, Any]:
    value = load_json(path)
    return value if isinstance(value, dict) else {"present": False}


def process_snapshot(bundle_id: str, executable_name: str) -> dict[str, Any]:
    lookup = run_command(["pgrep", "-x", executable_name], timeout=10)
    pids = [
        value
        for value in lookup.get("stdout", "").splitlines()
        if value.isdigit()
    ]
    details: dict[str, Any] | None = None
    if pids:
        details = run_command(
            ["ps", "-p", ",".join(pids), "-o", "pid=,ppid=,user=,comm=,args="],
            timeout=10,
        )
    return {
        "timestamp": timestamp(),
        "bundleID": bundle_id,
        "executableName": executable_name,
        "pids": pids,
        "processCount": len(pids),
        "pgrepExitCode": lookup.get("exitCode"),
        "processDetails": details,
    }


def save_source(driver: WebDriver, session_id: str, path: pathlib.Path) -> dict[str, Any]:
    try:
        response = driver.request("GET", f"/session/{session_id}/source")
        source = response.get("value", "")
        encoded = source.encode(errors="replace")
        if len(encoded) > 1_000_000:
            encoded = encoded[:1_000_000] + b"\n[truncated]\n"
        path.write_bytes(encoded)
        return {
            "success": True,
            "bytes": len(encoded),
            "sha256": hashlib.sha256(encoded).hexdigest(),
        }
    except WebDriverError as error:
        return {"success": False, "error": str(error)}


def save_screenshot(
    driver: WebDriver, session_id: str, path: pathlib.Path
) -> dict[str, Any]:
    try:
        response = driver.request("GET", f"/session/{session_id}/screenshot")
        value = response.get("value", "")
        image = base64.b64decode(value, validate=True)
        path.write_bytes(image)
        return {
            "success": True,
            "bytes": len(image),
            "sha256": hashlib.sha256(image).hexdigest(),
            "path": path.name,
        }
    except (WebDriverError, ValueError, TypeError) as error:
        return {"success": False, "error": str(error), "path": path.name}


def key_command(
    driver: WebDriver, session_id: str, element_id: str, key: str
) -> Any:
    return driver.request(
        "POST",
        f"/session/{session_id}/execute/sync",
        {
            "script": "macos: keys",
            "args": [{"elementId": element_id, "keys": [key]}],
        },
    )


def focus_text_view(
    driver: WebDriver,
    session_id: str,
    element_id: str,
    diagnostics_path: pathlib.Path,
) -> dict[str, Any]:
    driver.request("POST", f"/session/{session_id}/element/{element_id}/click", {})
    deadline = time.monotonic() + 10
    snapshot: dict[str, Any] = {}
    diagnostic: dict[str, Any] = {}
    while time.monotonic() < deadline:
        snapshot = element_snapshot(driver, session_id, element_id)
        diagnostic = diagnostics_snapshot(diagnostics_path)
        webdriver_focus = str(snapshot.get("amHasKeyboardInputFocus", "")).lower() == "true"
        if webdriver_focus or diagnostic.get("firstResponder") is True:
            return {
                "success": True,
                "webdriverElement": snapshot,
                "clientDiagnostics": diagnostic,
            }
        time.sleep(0.25)
    return {
        "success": False,
        "webdriverElement": snapshot,
        "clientDiagnostics": diagnostic,
    }


def lambda_assertion(diagnostics: dict[str, Any]) -> dict[str, Any]:
    scalars = diagnostics.get("textScalars")
    marked_range = diagnostics.get("markedRange") or {}
    ended = diagnostics.get("hasMarkedText") is False and marked_range.get("location") == -1
    return {
        "text": diagnostics.get("text"),
        "textScalars": scalars,
        "markedRange": marked_range,
        "hasMarkedText": diagnostics.get("hasMarkedText"),
        "compositionEnded": ended,
        "isExactLambda": scalars == ["U+03BB"],
        "passed": scalars == ["U+03BB"] and ended,
    }


def literal_mac2_delivery(diagnostics: dict[str, Any]) -> bool:
    text = diagnostics.get("text")
    scalars = diagnostics.get("textScalars") or []
    return (isinstance(text, str) and text.startswith("\\l")) or scalars[:2] == [
        "U+005C",
        "U+006C",
    ]


def native_source_snapshot(helper: pathlib.Path, path: pathlib.Path) -> dict[str, Any]:
    result = run_command([str(helper), "sources", str(path)], timeout=30)
    return {"command": result, "data": load_json(path, {})}


def source_is_selected(snapshot: dict[str, Any], bundle_id: str) -> bool:
    current = snapshot.get("data", {}).get("current", {})
    return current.get("bundleID") == bundle_id


def attempt_input_source_consent(
    driver: WebDriver,
    helper: pathlib.Path,
    evidence: pathlib.Path,
    bundle_id: str,
    mode_id: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {"attempted": True, "startedAt": timestamp()}
    session_id: str | None = None
    try:
        session_id, response = create_bundle_session(
            driver,
            "com.apple.systempreferences",
            {"appium:noReset": True},
        )
        result["session"] = {"created": True, "response": response}
        result["sourceBefore"] = save_source(
            driver, session_id, evidence / "input-source-consent-source.xml"
        )
        result["screenshotBefore"] = save_screenshot(
            driver, session_id, evidence / "input-source-consent-before.png"
        )
        allow_element = find_element(
            driver,
            session_id,
            [
                ("accessibility id", "Allow"),
                (
                    "predicate string",
                    "name == 'Allow' OR label == 'Allow' OR value == 'Allow'",
                ),
            ],
            timeout=15,
        )
        result["allowElement"] = element_snapshot(driver, session_id, allow_element)
        driver.request(
            "POST", f"/session/{session_id}/element/{allow_element}/click", {}
        )
        result["allowClicked"] = True
        time.sleep(1.0)
        result["screenshotAfter"] = save_screenshot(
            driver, session_id, evidence / "input-source-consent-after.png"
        )
    except Exception as error:
        result["error"] = {
            "type": type(error).__name__,
            "message": bounded(str(error)),
        }
    finally:
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                result.setdefault("session", {})["deleted"] = True
            except Exception as error:
                result.setdefault("session", {})["deleteError"] = bounded(str(error))

    retry_path = evidence / "input-source-selection-after-consent.json"
    retry = run_command(
        [str(helper), "select", bundle_id, mode_id, str(retry_path)], timeout=30
    )
    result["selectionRetry"] = {
        "command": retry,
        "data": load_json(retry_path, {}),
    }
    result["completedAt"] = timestamp()
    return result


def run_probe(
    evidence: pathlib.Path,
    client_app: pathlib.Path,
    helper: pathlib.Path,
    probe_bundle_id: str,
    probe_mode_id: str,
    probe_executable_name: str,
) -> int:
    transcript = evidence / "webdriver-transcript.jsonl"
    appium_full_log = evidence / "appium-full.log"
    appium_log_handle = appium_full_log.open("w")
    appium_process: subprocess.Popen[str] | None = None
    driver = WebDriver("http://127.0.0.1:4723", transcript)
    session_id: str | None = None
    report: dict[str, Any] = {
        "startedAt": timestamp(),
        "server": {},
        "session": {},
        "accessibility": {},
        "keyDelivery": {"driver": "appium-mac2", "keys": []},
        "fallback": {"attempted": False, "reason": "Mac2 did not inject literal text"},
        "inputSourceConsent": {"attempted": False},
        "screenshots": [],
    }
    result_status = 1
    classification = "probe_exception"
    passed = False

    try:
        appium_process = subprocess.Popen(
            ["appium", "--base-path", "/", "--log-no-colors", "--log-timestamp"],
            stdout=appium_log_handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
        report["server"]["pid"] = appium_process.pid
        report["server"]["appiumVersion"] = run_command(["appium", "--version"])
        report["server"]["installedDrivers"] = run_command(
            ["appium", "driver", "list", "--installed"]
        )
        report["server"]["readiness"] = wait_for_server(driver)
        if not report["server"]["readiness"]["ready"]:
            classification = "appium_server_unavailable"
            raise RuntimeError("Appium server did not become ready")

        initial_source = native_source_snapshot(
            helper, evidence / "input-sources-before-consent.json"
        )
        report["inputSourceBeforeConsent"] = initial_source
        if not source_is_selected(initial_source, probe_bundle_id):
            report["inputSourceConsent"] = attempt_input_source_consent(
                driver,
                helper,
                evidence,
                probe_bundle_id,
                probe_mode_id,
            )
        source_after_consent = native_source_snapshot(
            helper, evidence / "input-sources-after-consent.json"
        )
        report["inputSourceAfterConsent"] = source_after_consent
        input_source_ready = source_is_selected(
            source_after_consent, probe_bundle_id
        )
        report["inputSourceSelectionVerified"] = input_source_ready

        current_diagnostics = evidence / "client-current.json"
        timeline = evidence / "client-timeline.jsonl"
        try:
            session_id, session_response = create_session(
                driver, client_app, current_diagnostics, timeline
            )
        except Exception:
            classification = "mac2_session_unavailable"
            raise
        report["session"] = {
            "created": True,
            "sessionId": session_id,
            "response": session_response,
        }

        try:
            element_id = find_text_view(driver, session_id)
        except Exception:
            classification = "mac2_accessibility_tree_unavailable"
            report["accessibility"]["source"] = save_source(
                driver, session_id, evidence / "accessibility-source.xml"
            )
            raise
        report["accessibility"]["elementId"] = element_id
        report["accessibility"]["source"] = save_source(
            driver, session_id, evidence / "accessibility-source.xml"
        )
        report["accessibility"]["focusedElement"] = focus_text_view(
            driver, session_id, element_id, current_diagnostics
        )
        if not report["accessibility"]["focusedElement"]["success"]:
            classification = "mac2_could_not_focus_text_view"
            raise RuntimeError("Mac2 found the text view but could not focus it")

        report["screenshots"].append(
            save_screenshot(driver, session_id, evidence / "before-keys.png")
        )
        report["inputSourceAtDelivery"] = native_source_snapshot(
            helper, evidence / "input-sources-at-delivery.json"
        )
        report["imkServerBeforeKeys"] = process_snapshot(
            probe_bundle_id, probe_executable_name
        )

        key_specs = [
            ("backslash", "\\"),
            ("l", "l"),
            ("enter", "XCUIKeyboardKeyEnter"),
        ]
        for logical_name, key in key_specs:
            entry: dict[str, Any] = {
                "logicalKey": logical_name,
                "wireKey": key,
                "sentAt": timestamp(),
            }
            response = key_command(driver, session_id, element_id, key)
            entry["response"] = response
            time.sleep(0.6)
            entry["clientDiagnosticsAfter"] = diagnostics_snapshot(current_diagnostics)
            entry["webdriverElementAfter"] = element_snapshot(
                driver, session_id, element_id
            )
            entry["imkServerAfter"] = process_snapshot(
                probe_bundle_id, probe_executable_name
            )
            report["keyDelivery"]["keys"].append(entry)

        time.sleep(1.0)
        final_diagnostics = diagnostics_snapshot(current_diagnostics)
        report["mac2Final"] = {
            "clientDiagnostics": final_diagnostics,
            "webdriverElement": element_snapshot(driver, session_id, element_id),
            "assertion": lambda_assertion(final_diagnostics),
        }
        report["imkServerAfterKeys"] = process_snapshot(
            probe_bundle_id, probe_executable_name
        )
        report["screenshots"].append(
            save_screenshot(driver, session_id, evidence / "after-mac2-keys.png")
        )

        imk_started = report["imkServerAfterKeys"]["processCount"] > 0 or any(
            entry["imkServerAfter"]["processCount"] > 0
            for entry in report["keyDelivery"]["keys"]
        )
        report["imkServerStartupObserved"] = imk_started
        mac2_passed = report["mac2Final"]["assertion"]["passed"] and imk_started
        if mac2_passed:
            passed = True
            result_status = 0
            classification = "hosted_imk_e2e_feasible_via_mac2"
        elif literal_mac2_delivery(final_diagnostics):
            report["fallback"] = {
                "attempted": True,
                "reason": "Mac2 injected literal backslash-l text instead of traversing InputMethodKit",
            }
            driver.request("DELETE", f"/session/{session_id}")
            session_id = None
            shutil.copy2(current_diagnostics, evidence / "client-mac2-final.json")
            current_diagnostics.unlink(missing_ok=True)
            time.sleep(0.5)

            fallback_session, _ = create_session(
                driver, client_app, current_diagnostics, timeline
            )
            session_id = fallback_session
            fallback_element = find_text_view(driver, fallback_session)
            fallback_focus = focus_text_view(
                driver, fallback_session, fallback_element, current_diagnostics
            )
            report["fallback"]["focusedElement"] = fallback_focus
            if not fallback_focus["success"]:
                classification = "cgevent_fallback_could_not_focus_text_view"
            else:
                cg_result_path = evidence / "cgevent-attempt.json"
                cg_command = run_command(
                    [str(helper), "cg-keys", str(cg_result_path)], timeout=15
                )
                report["fallback"]["command"] = cg_command
                report["fallback"]["preflightAndPost"] = load_json(cg_result_path, {})
                time.sleep(1.5)
                fallback_final = diagnostics_snapshot(current_diagnostics)
                report["fallback"]["final"] = {
                    "clientDiagnostics": fallback_final,
                    "webdriverElement": element_snapshot(
                        driver, fallback_session, fallback_element
                    ),
                    "assertion": lambda_assertion(fallback_final),
                    "imkServer": process_snapshot(probe_bundle_id, probe_executable_name),
                }
                report["screenshots"].append(
                    save_screenshot(
                        driver, fallback_session, evidence / "after-cgevent-keys.png"
                    )
                )
                fallback_passed = (
                    report["fallback"]["final"]["assertion"]["passed"]
                    and report["fallback"]["final"]["imkServer"]["processCount"] > 0
                )
                if fallback_passed:
                    passed = True
                    result_status = 0
                    classification = "hosted_imk_e2e_feasible_via_cgevent"
                elif not report["fallback"]["preflightAndPost"].get(
                    "cgEventPostPreflight", False
                ):
                    classification = "mac2_bypassed_imk_cgevent_accessibility_denied"
                elif (
                    fallback_final.get("textScalars") == ["U+2190"]
                    and report["fallback"]["final"]["imkServer"]["processCount"] > 0
                ):
                    classification = "production_sequence_committed_left_arrow_not_lambda"
                else:
                    classification = "mac2_and_cgevent_failed_lambda_assertion"
        elif imk_started and final_diagnostics.get("textScalars") == ["U+2190"]:
            classification = "production_sequence_committed_left_arrow_not_lambda"
        elif imk_started:
            classification = "lambda_assertion_failed_after_imk_server_startup"
        else:
            classification = "unicorn_imk_server_not_started"

        if not input_source_ready:
            passed = False
            result_status = 1
            consent = report.get("inputSourceConsent", {})
            retry = consent.get("selectionRetry", {}).get("data", {})
            if consent.get("error"):
                classification = "input_source_consent_not_automatable_with_mac2"
            elif consent.get("allowClicked") and retry.get("selectionStatus") != 0:
                classification = "input_source_selection_denied_after_allow_click"
            else:
                classification = "input_source_selection_blocked"
    except Exception as error:
        report["error"] = {
            "type": type(error).__name__,
            "message": str(error),
            "timestamp": timestamp(),
        }
    finally:
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                report["session"]["deleted"] = True
            except Exception as error:
                report["session"]["deleteError"] = str(error)
        if appium_process:
            appium_process.terminate()
            try:
                appium_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                appium_process.kill()
                appium_process.wait(timeout=5)
            report["server"]["exitCode"] = appium_process.returncode
        appium_log_handle.close()

    report["completedAt"] = timestamp()
    report["passed"] = passed
    report["classification"] = classification
    atomic_json(evidence / "appium-probe.json", report)
    update_summary(
        evidence,
        {
            "status": "passed" if passed else "failed",
            "classification": classification,
            "hostedE2EPassed": passed,
            "appiumProbe": report,
        },
    )
    return result_status


def record_build(
    evidence: pathlib.Path,
    unicorn_app: pathlib.Path,
    client_app: pathlib.Path,
    helper: pathlib.Path,
) -> None:
    commands = {
        "unicornFile": ["file", str(unicorn_app / "Contents/MacOS/UnicornHostedIMKProbe")],
        "unicornArchitectures": [
            "lipo",
            "-archs",
            str(unicorn_app / "Contents/MacOS/UnicornHostedIMKProbe"),
        ],
        "unicornSignature": ["codesign", "-dvvv", str(unicorn_app)],
        "unicornEntitlements": ["codesign", "-d", "--entitlements", ":-", str(unicorn_app)],
        "unicornVerify": ["codesign", "--verify", "--deep", "--strict", "--verbose=4", str(unicorn_app)],
        "clientFile": ["file", str(client_app / "Contents/MacOS/HostedIMKProbeClient")],
        "clientSignature": ["codesign", "-dvvv", str(client_app)],
        "helperFile": ["file", str(helper)],
    }
    results = {name: run_command(command) for name, command in commands.items()}
    info_path = unicorn_app / "Contents/Info.plist"
    try:
        with info_path.open("rb") as handle:
            results["unicornInfoPlist"] = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        results["unicornInfoPlistError"] = str(error)
    keymap_path = unicorn_app / "Contents/Resources/keymap.json"
    try:
        keymap = json.loads(keymap_path.read_text())
        results["productionSequenceCandidates"] = {
            "keysAfterActivation": ["l"],
            "candidates": keymap.get("l", {}).get(">>", []),
            "firstCandidate": (keymap.get("l", {}).get(">>") or [None])[0],
            "keymapSHA256": hashlib.sha256(keymap_path.read_bytes()).hexdigest(),
        }
    except (OSError, json.JSONDecodeError) as error:
        results["productionSequenceCandidatesError"] = str(error)
    atomic_json(evidence / "build-metadata.json", results)
    update_summary(evidence, {"build": results})


def finalize(evidence: pathlib.Path, producer_status: int) -> None:
    summary = load_json(evidence / "summary.json", {})
    cleanup = load_json(evidence / "cleanup.json", {"present": False})
    summary["completedAt"] = timestamp()
    summary["producerExitCode"] = producer_status
    summary["cleanup"] = cleanup
    if producer_status != 0 and summary.get("status") == "running":
        summary["status"] = "failed"
        summary["hostedE2EPassed"] = False
        summary["classification"] = "probe_setup_or_execution_failed"
    cleanup_passed = cleanup.get("success", False)
    summary["cleanupPassed"] = cleanup_passed
    path_passed = summary.get("hostedE2EPassed", False)
    summary["qualifiedHostedProbePassed"] = path_passed and cleanup_passed
    if path_passed and not cleanup_passed:
        summary["status"] = "failed"
        summary["classificationBeforeCleanupFailure"] = summary.get("classification")
        summary["classification"] = "cleanup_failed_after_lambda_proof"
    atomic_json(evidence / "summary.json", summary)


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_parser = subparsers.add_parser("init")
    init_parser.add_argument("evidence", type=pathlib.Path)

    preflight_parser = subparsers.add_parser("preflight")
    preflight_parser.add_argument("evidence", type=pathlib.Path)
    preflight_parser.add_argument("helper", type=pathlib.Path)

    build_parser = subparsers.add_parser("record-build")
    build_parser.add_argument("evidence", type=pathlib.Path)
    build_parser.add_argument("unicorn_app", type=pathlib.Path)
    build_parser.add_argument("client_app", type=pathlib.Path)
    build_parser.add_argument("helper", type=pathlib.Path)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("evidence", type=pathlib.Path)
    run_parser.add_argument("client_app", type=pathlib.Path)
    run_parser.add_argument("helper", type=pathlib.Path)
    run_parser.add_argument("probe_bundle_id")
    run_parser.add_argument("probe_mode_id")
    run_parser.add_argument("probe_executable_name")

    finalize_parser = subparsers.add_parser("finalize")
    finalize_parser.add_argument("evidence", type=pathlib.Path)
    finalize_parser.add_argument("producer_status", type=int)

    arguments = parser.parse_args()
    if arguments.command == "init":
        initialize(arguments.evidence)
        return 0
    if arguments.command == "preflight":
        preflight(arguments.evidence, arguments.helper)
        return 0
    if arguments.command == "record-build":
        record_build(
            arguments.evidence,
            arguments.unicorn_app,
            arguments.client_app,
            arguments.helper,
        )
        return 0
    if arguments.command == "run":
        return run_probe(
            arguments.evidence,
            arguments.client_app,
            arguments.helper,
            arguments.probe_bundle_id,
            arguments.probe_mode_id,
            arguments.probe_executable_name,
        )
    if arguments.command == "finalize":
        finalize(arguments.evidence, arguments.producer_status)
        return 0
    return 64


if __name__ == "__main__":
    sys.exit(main())
