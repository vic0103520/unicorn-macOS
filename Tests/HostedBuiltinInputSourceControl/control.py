#!/usr/bin/env python3
"""Bounded built-in input-source control for a GitHub-hosted Aqua session."""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Tests" / "HostedIMKProbe"))
import probe as webdriver_support  # noqa: E402

TARGET_ID = "com.apple.keylayout.Dvorak"
TARGET_NAME = "Dvorak"
TEXT_VIEW_ID = "unicorn-hosted-imk-probe-text-view"
ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"


def timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def load_json(path: pathlib.Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return default


def command(args: list[str], timeout: int = 30) -> dict[str, Any]:
    return webdriver_support.run_command(args, timeout=timeout)


def element_ids(response: dict[str, Any]) -> list[str]:
    values = response.get("value", [])
    if not isinstance(values, list):
        return []
    return [
        value.get(ELEMENT_KEY) or value.get("ELEMENT")
        for value in values
        if isinstance(value, dict) and (value.get(ELEMENT_KEY) or value.get("ELEMENT"))
    ]


def find_elements(
    driver: webdriver_support.WebDriver, session_id: str, xpath: str
) -> list[str]:
    response = driver.request(
        "POST",
        f"/session/{session_id}/elements",
        {"using": "xpath", "value": xpath},
    )
    return element_ids(response)


def element_rect(
    driver: webdriver_support.WebDriver, session_id: str, element_id: str
) -> dict[str, Any]:
    try:
        response = driver.request(
            "GET", f"/session/{session_id}/element/{element_id}/rect"
        )
        value = response.get("value")
        return value if isinstance(value, dict) else {}
    except Exception as error:
        return {"error": str(error)}


def element_state(
    driver: webdriver_support.WebDriver, session_id: str, element_id: str
) -> dict[str, Any]:
    state = webdriver_support.element_snapshot(driver, session_id, element_id)
    state["rect"] = element_rect(driver, session_id, element_id)
    state["elementId"] = element_id
    return state


def click(driver: webdriver_support.WebDriver, session_id: str, element_id: str) -> None:
    driver.request("POST", f"/session/{session_id}/element/{element_id}/click", {})


def semantic_ui_state(xml_path: pathlib.Path) -> dict[str, Any]:
    try:
        root = ET.fromstring(xml_path.read_text(errors="replace"))
    except (OSError, ET.ParseError) as error:
        return {"error": str(error)}
    elements: list[dict[str, str]] = []
    interesting = {
        "XCUIElementTypeButton",
        "XCUIElementTypeCell",
        "XCUIElementTypeSearchField",
        "XCUIElementTypeStaticText",
        "XCUIElementTypeSheet",
        "XCUIElementTypeWindow",
    }
    for node in root.iter():
        if node.tag not in interesting:
            continue
        values = {
            key: node.attrib.get(key, "")
            for key in (
                "identifier",
                "label",
                "title",
                "value",
                "enabled",
                "selected",
                "x",
                "y",
                "width",
                "height",
            )
        }
        if any(values[key] for key in ("identifier", "label", "title", "value")):
            values["role"] = node.tag
            elements.append(values)
    return {"elementCount": len(elements), "elements": elements[:500]}


def capture_ui(
    driver: webdriver_support.WebDriver,
    session_id: str,
    evidence: pathlib.Path,
    name: str,
) -> dict[str, Any]:
    source_path = evidence / f"ui-{name}.xml"
    screenshot_path = evidence / f"ui-{name}.png"
    source_result = webdriver_support.save_source(driver, session_id, source_path)
    result = {
        "timestamp": timestamp(),
        "source": source_result,
        "screenshot": webdriver_support.save_screenshot(
            driver, session_id, screenshot_path
        ),
        "semanticState": semantic_ui_state(source_path),
    }
    write_json(evidence / f"ui-{name}.json", result)
    return result


def source_snapshot(helper: pathlib.Path, output: pathlib.Path) -> dict[str, Any]:
    result = command([str(helper), "snapshot", str(output)], timeout=30)
    return {"command": result, "snapshot": load_json(output, {})}


def current_id(snapshot_result: dict[str, Any]) -> str | None:
    return (
        snapshot_result.get("snapshot", {})
        .get("current", {})
        .get("inputSourceID")
    )


def create_client_session(
    driver: webdriver_support.WebDriver,
    client_app: pathlib.Path,
    evidence: pathlib.Path,
    name: str,
) -> tuple[str, pathlib.Path]:
    diagnostics = evidence / f"typed-{name}-current.json"
    timeline = evidence / f"typed-{name}-timeline.jsonl"
    session_id, _ = webdriver_support.create_session(
        driver, client_app, diagnostics, timeline
    )
    return session_id, diagnostics


def capture_typed_text(
    driver: webdriver_support.WebDriver,
    helper: pathlib.Path,
    client_app: pathlib.Path,
    evidence: pathlib.Path,
    name: str,
    expected_text: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "startedAt": timestamp(),
        "physicalKeyCode": 37,
        "physicalUSKey": "l",
        "expectedTextForSelectedLayout": expected_text,
    }
    session_id: str | None = None
    try:
        session_id, diagnostics = create_client_session(
            driver, client_app, evidence, name
        )
        element_id = webdriver_support.find_text_view(driver, session_id)
        result["focus"] = webdriver_support.focus_text_view(
            driver, session_id, element_id, diagnostics
        )
        result["sourceAtDelivery"] = source_snapshot(
            helper, evidence / f"typed-{name}-source.json"
        )
        result["screenshotBefore"] = webdriver_support.save_screenshot(
            driver, session_id, evidence / f"typed-{name}-before.png"
        )
        key_output = evidence / f"typed-{name}-key-event.json"
        result["keyCommand"] = command(
            [str(helper), "post-key", "37", str(key_output)], timeout=15
        )
        result["keyEvent"] = load_json(key_output, {})
        time.sleep(1.0)
        result["clientDiagnostics"] = load_json(diagnostics, {})
        result["textMatchesExpected"] = (
            result["clientDiagnostics"].get("text") == expected_text
        )
        result["screenshotAfter"] = webdriver_support.save_screenshot(
            driver, session_id, evidence / f"typed-{name}-after.png"
        )
    except Exception as error:
        result["error"] = {"type": type(error).__name__, "message": str(error)}
        result["textMatchesExpected"] = False
    finally:
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                result["sessionDeleted"] = True
            except Exception as error:
                result["sessionDeleteError"] = str(error)
    result["completedAt"] = timestamp()
    write_json(evidence / f"typed-{name}.json", result)
    return result


def visible_element_states(
    driver: webdriver_support.WebDriver, session_id: str, elements: list[str]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    states = [element_state(driver, session_id, element) for element in elements]
    visible = [
        state
        for state in states
        if isinstance(state.get("rect"), dict)
        and state["rect"].get("width", 0) > 0
        and state["rect"].get("height", 0) > 0
        and state["rect"].get("y", -1) >= 0
    ]
    return visible, states


def choose_topmost(
    driver: webdriver_support.WebDriver, session_id: str, elements: list[str]
) -> tuple[str | None, list[dict[str, Any]]]:
    visible, states = visible_element_states(driver, session_id, elements)
    visible.sort(
        key=lambda state: (
            state["rect"].get("y", 10_000),
            state["rect"].get("x", 10_000),
        )
    )
    return (visible[0]["elementId"] if visible else None), states


def choose_rightmost(
    driver: webdriver_support.WebDriver, session_id: str, elements: list[str]
) -> tuple[str | None, list[dict[str, Any]]]:
    visible, states = visible_element_states(driver, session_id, elements)
    visible.sort(key=lambda state: state["rect"].get("x", -1), reverse=True)
    return (visible[0]["elementId"] if visible else None), states


def system_settings_phase(
    driver: webdriver_support.WebDriver,
    helper: pathlib.Path,
    evidence: pathlib.Path,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "startedAt": timestamp(),
        "method": "Accessibility through Appium Mac2/XCTest",
        "target": {"inputSourceID": TARGET_ID, "localizedName": TARGET_NAME},
        "uiInteractionSucceeded": False,
        "sourceSelectionSucceeded": False,
        "steps": [],
    }
    session_id: str | None = None
    try:
        result["openKeyboardSettings"] = command(
            [
                "open",
                "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            ],
            timeout=20,
        )
        time.sleep(2.0)
        session_id, response = webdriver_support.create_bundle_session(
            driver,
            "com.apple.systempreferences",
            {"appium:noReset": True},
        )
        result["session"] = {"created": True, "response": response}
        result["initialUI"] = capture_ui(
            driver, session_id, evidence, "keyboard-settings-initial"
        )

        edit_buttons = find_elements(
            driver, session_id, '//XCUIElementTypeButton[@label="Edit…"]'
        )
        edit_button, edit_states = choose_topmost(driver, session_id, edit_buttons)
        result["editButtonCandidates"] = edit_states
        if not edit_button:
            raise RuntimeError("Input Sources Edit button was not exposed through Accessibility")
        click(driver, session_id, edit_button)
        result["steps"].append("clicked-input-sources-edit")
        time.sleep(1.0)
        result["inputSourcesUI"] = capture_ui(
            driver, session_id, evidence, "input-sources-sheet"
        )

        add_buttons = find_elements(
            driver,
            session_id,
            '//XCUIElementTypeButton['
            '@label="Add Input Source" or @label="Add" or @label="add" '
            'or @title="Add Input Source" or @title="Add"]',
        )
        add_button, add_states = choose_topmost(driver, session_id, add_buttons)
        result["addButtonCandidatesBeforeChooser"] = add_states
        if not add_button:
            raise RuntimeError("Add Input Source button was not exposed through Accessibility")
        click(driver, session_id, add_button)
        result["steps"].append("clicked-add-input-source")
        time.sleep(1.0)
        result["chooserUI"] = capture_ui(
            driver, session_id, evidence, "input-source-chooser"
        )

        search_fields = find_elements(driver, session_id, "//XCUIElementTypeSearchField")
        search_field, search_states = choose_rightmost(driver, session_id, search_fields)
        result["searchFieldCandidates"] = search_states
        if search_field:
            click(driver, session_id, search_field)
            driver.request(
                "POST",
                f"/session/{session_id}/element/{search_field}/value",
                {"text": TARGET_NAME, "value": list(TARGET_NAME)},
            )
            result["steps"].append("searched-for-dvorak")
            time.sleep(1.0)
            result["searchResultsUI"] = capture_ui(
                driver, session_id, evidence, "input-source-search-results"
            )

        target_elements = find_elements(
            driver,
            session_id,
            '//*[@label="Dvorak" or @value="Dvorak" or @title="Dvorak"]',
        )
        target_element, target_states = choose_topmost(
            driver, session_id, target_elements
        )
        result["targetCandidates"] = target_states
        if not target_element:
            raise RuntimeError("Dvorak was not exposed in the built-in source chooser")
        click(driver, session_id, target_element)
        result["steps"].append("selected-dvorak-in-chooser")
        time.sleep(0.5)

        final_add_buttons = find_elements(
            driver,
            session_id,
            '//XCUIElementTypeButton[@label="Add" or @title="Add"]',
        )
        final_add, final_add_states = choose_topmost(
            driver, session_id, final_add_buttons
        )
        result["finalAddButtonCandidates"] = final_add_states
        if not final_add:
            raise RuntimeError("Chooser Add button was not exposed through Accessibility")
        click(driver, session_id, final_add)
        result["steps"].append("clicked-chooser-add")
        time.sleep(2.0)
        result["afterAddUI"] = capture_ui(
            driver, session_id, evidence, "input-sources-after-add"
        )
        result["uiInteractionSucceeded"] = True
    except Exception as error:
        result["interactionError"] = {
            "type": type(error).__name__,
            "message": str(error),
        }
    finally:
        result["sourceAfterUI"] = source_snapshot(
            helper, evidence / "source-after-system-settings-ui.json"
        )
        result["sourceSelectionSucceeded"] = (
            current_id(result["sourceAfterUI"]) == TARGET_ID
        )
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                result.setdefault("session", {})["deleted"] = True
            except Exception as error:
                result.setdefault("session", {})["deleteError"] = str(error)
    result["completedAt"] = timestamp()
    write_json(evidence / "system-settings-phase.json", result)
    return result


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: control.py EVIDENCE HELPER CLIENT_APP STATE", file=sys.stderr)
        return 64
    evidence = pathlib.Path(sys.argv[1])
    helper = pathlib.Path(sys.argv[2])
    client_app = pathlib.Path(sys.argv[3])
    state_path = pathlib.Path(sys.argv[4])
    evidence.mkdir(parents=True, exist_ok=True)

    summary: dict[str, Any] = {
        "schemaVersion": 1,
        "experiment": "github-hosted-arm64-built-in-input-source-control",
        "startedAt": timestamp(),
        "target": {"inputSourceID": TARGET_ID, "localizedName": TARGET_NAME},
        "conditions": [
            "System Settings interaction through Accessibility and XCTest",
            "public TISEnableInputSource and TISSelectInputSource APIs",
        ],
        "thirdPartyInputMethodAttempted": False,
        "productBehaviorChanged": False,
        "github": {
            key: os.environ.get(key)
            for key in (
                "GITHUB_RUN_ID",
                "GITHUB_RUN_ATTEMPT",
                "GITHUB_SHA",
                "RUNNER_ARCH",
                "ImageOS",
                "ImageVersion",
            )
        },
    }
    write_json(evidence / "summary.json", summary)

    transcript = evidence / "webdriver-transcript.jsonl"
    driver = webdriver_support.WebDriver("http://127.0.0.1:4723", transcript)
    appium_log = (evidence / "appium.log").open("w")
    appium: subprocess.Popen[str] | None = None
    result_code = 1
    try:
        summary["environment"] = {
            "uname": command(["uname", "-a"]),
            "architecture": command(["uname", "-m"]),
            "systemVersion": command(["sw_vers"]),
            "consoleUser": command(["stat", "-f", "%Su", "/dev/console"]),
            "windowServer": command(["pgrep", "-alf", "WindowServer"]),
            "automationMode": command(["automationmodetool"]),
            "nativeSession": command(
                [str(helper), "session", str(evidence / "aqua-session.json")]
            ),
        }
        summary["initialSource"] = source_snapshot(
            helper, evidence / "source-initial.json"
        )
        summary["controlState"] = load_json(state_path, {})
        write_json(evidence / "summary.json", summary)

        appium = subprocess.Popen(
            ["appium", "--base-path", "/", "--log-no-colors", "--log-timestamp"],
            stdout=appium_log,
            stderr=subprocess.STDOUT,
            text=True,
        )
        summary["appium"] = {
            "pid": appium.pid,
            "version": command(["appium", "--version"]),
            "drivers": command(["appium", "driver", "list", "--installed"]),
            "readiness": webdriver_support.wait_for_server(driver),
        }
        if not summary["appium"]["readiness"]["ready"]:
            raise RuntimeError("Appium did not become ready")

        summary["baselineTypedText"] = capture_typed_text(
            driver, helper, client_app, evidence, "baseline-us", "l"
        )

        summary["systemSettings"] = system_settings_phase(
            driver, helper, evidence
        )
        if summary["systemSettings"]["sourceSelectionSucceeded"]:
            summary["systemSettings"]["typedText"] = capture_typed_text(
                driver, helper, client_app, evidence, "system-settings-dvorak", "n"
            )
        else:
            summary["systemSettings"]["typedText"] = {
                "attempted": False,
                "reason": "System Settings interaction did not select Dvorak",
            }

        ui_cleanup_path = evidence / "cleanup-after-system-settings.json"
        summary["cleanupAfterSystemSettings"] = {
            "command": command(
                [str(helper), "cleanup", str(state_path), str(ui_cleanup_path)],
                timeout=30,
            ),
            "result": load_json(ui_cleanup_path, {}),
        }
        summary["sourceBeforeAPI"] = source_snapshot(
            helper, evidence / "source-before-api.json"
        )

        api_result_path = evidence / "public-tis-transition.json"
        summary["publicTIS"] = {
            "command": command(
                [str(helper), "transition", TARGET_ID, str(api_result_path)],
                timeout=30,
            ),
            "transition": load_json(api_result_path, {}),
        }
        summary["publicTIS"]["selectionSucceeded"] = (
            summary["publicTIS"]["transition"].get("success") is True
        )
        if summary["publicTIS"]["selectionSucceeded"]:
            summary["publicTIS"]["typedText"] = capture_typed_text(
                driver, helper, client_app, evidence, "public-tis-dvorak", "n"
            )
        else:
            summary["publicTIS"]["typedText"] = {
                "attempted": False,
                "reason": "Public TIS APIs did not select Dvorak",
            }

        api_cleanup_path = evidence / "cleanup-after-public-tis.json"
        summary["cleanupAfterPublicTIS"] = {
            "command": command(
                [str(helper), "cleanup", str(state_path), str(api_cleanup_path)],
                timeout=30,
            ),
            "result": load_json(api_cleanup_path, {}),
        }
        summary["finalSource"] = source_snapshot(
            helper, evidence / "source-final.json"
        )

        ui_interaction_complete = summary["systemSettings"]["uiInteractionSucceeded"]
        public_api_complete = "selectionStatus" in summary["publicTIS"]["transition"]
        cleanups_passed = (
            summary["cleanupAfterSystemSettings"]["result"].get("success") is True
            and summary["cleanupAfterPublicTIS"]["result"].get("success") is True
        )
        summary["builtInSwitching"] = {
            "systemSettingsUIInteractionSucceeded": ui_interaction_complete,
            "systemSettingsSelectionSucceeded": summary["systemSettings"][
                "sourceSelectionSucceeded"
            ],
            "publicTISSelectionSucceeded": summary["publicTIS"][
                "selectionSucceeded"
            ],
            "publicTISEnableStatus": summary["publicTIS"]["transition"].get(
                "enableStatus"
            ),
            "publicTISSelectStatus": summary["publicTIS"]["transition"].get(
                "selectionStatus"
            ),
        }
        summary["experimentCompleted"] = (
            ui_interaction_complete and public_api_complete and cleanups_passed
        )
        summary["status"] = "completed" if summary["experimentCompleted"] else "incomplete"
        result_code = 0 if summary["experimentCompleted"] else 1
    except Exception as error:
        summary["status"] = "incomplete"
        summary["experimentCompleted"] = False
        summary["error"] = {"type": type(error).__name__, "message": str(error)}
    finally:
        if appium:
            appium.terminate()
            try:
                appium.wait(timeout=10)
            except subprocess.TimeoutExpired:
                appium.kill()
                appium.wait(timeout=5)
            summary.setdefault("appium", {})["exitCode"] = appium.returncode
        appium_log.close()
        summary["completedAt"] = timestamp()
        write_json(evidence / "summary.json", summary)
    return result_code


if __name__ == "__main__":
    sys.exit(main())
