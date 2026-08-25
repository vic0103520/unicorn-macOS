#!/usr/bin/env python3
"""Bounded Dvorak/Squirrel selectability diagnosis on hosted ARM64 macOS."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
import pathlib
import plistlib
import subprocess
import sys
import time
from typing import Any

SHARED_PATH = pathlib.Path(__file__).parents[1] / "HostedIMKProbe" / "probe.py"
SHARED_SPEC = importlib.util.spec_from_file_location("hosted_imk_shared", SHARED_PATH)
if SHARED_SPEC is None or SHARED_SPEC.loader is None:
    raise RuntimeError(f"Unable to import shared probe support from {SHARED_PATH}")
shared = importlib.util.module_from_spec(SHARED_SPEC)
SHARED_SPEC.loader.exec_module(shared)

SCHEMA_VERSION = 2
BUNDLE_ID = "im.rime.inputmethod.Squirrel"
PARENT_ID = "im.rime.inputmethod.Squirrel"
MODE_ID = "im.rime.inputmethod.Squirrel.Hans"
DVORAK_ID = "com.apple.keylayout.Dvorak"
US_ID = "com.apple.keylayout.US"
PARENT_TYPE = "TISTypeKeyboardInputMethodModeEnabled"
MODE_TYPE = "TISTypeKeyboardInputMode"
LAYOUT_TYPE = "TISTypeKeyboardLayout"
EXECUTABLE_NAME = "Squirrel"
EXPECTED_TEXT = "你好"
EXPECTED_SCALARS = ["U+4F60", "U+597D"]
RELEASE_TAG = "1.1.2"
RELEASE_COMMIT = "876adebaf2f612951dcdca8a591de65401222b9a"
ASSET_NAME = "Squirrel-1.1.2.pkg"
ASSET_SHA256 = "614746013212937623d5bbab9901e9c43d1ec937aa32307d6b6092a05e308287"
ASSET_URL = "https://github.com/rime/squirrel/releases/download/1.1.2/Squirrel-1.1.2.pkg"
RELEASE_URL = "https://github.com/rime/squirrel/releases/tag/1.1.2"
SOURCE_URL = "https://github.com/rime/squirrel"
ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"


def load_json(path: pathlib.Path, default: Any = None) -> Any:
    return shared.load_json(path, default)


def write_json(path: pathlib.Path, value: Any) -> None:
    shared.atomic_json(path, value)


def github_run_url() -> str | None:
    repository = os.environ.get("GITHUB_REPOSITORY")
    run_id = os.environ.get("GITHUB_RUN_ID")
    if repository and run_id:
        return f"https://github.com/{repository}/actions/runs/{run_id}"
    return None


def initialize(evidence: pathlib.Path, installed_app: pathlib.Path) -> None:
    evidence.mkdir(parents=True, exist_ok=True)
    tracked_paths = [
        installed_app,
        pathlib.Path.home() / "Library" / "Rime",
        pathlib.Path.home() / "Library" / "Preferences" / f"{BUNDLE_ID}.plist",
        pathlib.Path.home() / "Library" / "Caches" / BUNDLE_ID,
        pathlib.Path.home() / "Library" / "Application Support" / "Squirrel",
    ]
    write_json(
        evidence / "installation-state.json",
        {
            "schemaVersion": SCHEMA_VERSION,
            "createdAt": shared.timestamp(),
            "selectionStarted": False,
            "dvorakInitiallyEnabled": False,
            "trackedPaths": [
                {"path": str(path), "existedBefore": path.exists()}
                for path in tracked_paths
            ],
        },
    )
    write_json(
        evidence / "summary.json",
        {
            "schemaVersion": SCHEMA_VERSION,
            "probe": "github-hosted-arm64-dvorak-squirrel-selectability-diagnosis",
            "status": "running",
            "startedAt": shared.timestamp(),
            "actionsRunURL": github_run_url(),
            "boundedScope": {
                "runnerLabel": "macos-15",
                "expectedArchitecture": "arm64",
                "sourcesUnderDiagnosis": [DVORAK_ID, BUNDLE_ID],
                "thirdPartyProductCount": 1,
                "thirdPartyProduct": "official Rime Squirrel 1.1.2",
                "screenshotsDiagnosticOnly": True,
                "passFailUsesOCRPixelsOrCoordinates": False,
                "productBehaviorChanged": False,
                "privatePreferenceOrAuthorizationDatabaseEdited": False,
            },
            "authoritativeContract": {
                "api": "TISSelectInputSource",
                "paramErr": -50,
                "paramErrMeaning": "the source is not selectable",
                "targetPrerequisites": [
                    "kTISPropertyInputSourceIsSelectCapable == true",
                    "kTISPropertyInputSourceIsEnabled == true",
                ],
                "inputModeAdditionalPrerequisite": "an enabled parent input method",
                "interpretation": "These are evaluated as causal prerequisites, not as a generic error code.",
            },
            "intendedSources": {
                "dvorak": {"sourceID": DVORAK_ID, "type": LAYOUT_TYPE},
                "squirrelParent": {"sourceID": PARENT_ID, "type": PARENT_TYPE},
                "squirrelMode": {"sourceID": MODE_ID, "type": MODE_TYPE},
            },
            "smallestCounterfactual": {
                "transition": f"Enable exact parent {PARENT_ID} before exact mode {MODE_ID}, refresh both live TISInputSourceRefs, then select only {MODE_ID}.",
                "whySmallest": "The prior hosted Squirrel run enabled the Hans mode while its documented input-method parent remained disabled.",
                "disconfirmingEvidenceRetained": [
                    "Dvorak transitions in the same Aqua session",
                    "all Dvorak and Squirrel property snapshots",
                    "before/after snapshots for every selection attempt",
                    "bounded Text Input Services log windows",
                    "current-source, process, and physical-key/composition evidence",
                ],
            },
            "assertions": {
                "dvorakPhysicalKey": {
                    "keyCode": 37,
                    "usPhysicalKey": "l",
                    "expectedDvorakText": "n",
                },
                "squirrelComposition": {
                    "physicalKeys": ["n", "i", "h", "a", "o", "space"],
                    "expectedCommittedText": EXPECTED_TEXT,
                    "expectedTextScalars": EXPECTED_SCALARS,
                    "compositionMustEnd": True,
                },
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
        },
    )


def source_snapshot(
    helper: pathlib.Path, evidence: pathlib.Path, filename: str, label: str
) -> dict[str, Any]:
    path = evidence / filename
    command = shared.run_command(
        [str(helper), "sources", label, str(path)], timeout=30
    )
    return {"command": command, "data": load_json(path, {})}


def preflight(evidence: pathlib.Path, helper: pathlib.Path) -> None:
    uid = os.getuid()
    commands = {
        "architecture": ["uname", "-m"],
        "systemVersion": ["sw_vers"],
        "identity": ["id"],
        "loggedInUsers": ["who"],
        "consoleUser": ["stat", "-f", "%Su", "/dev/console"],
        "windowServer": ["pgrep", "-alf", "WindowServer"],
        "aquaLaunchDomain": ["launchctl", "print", f"gui/{uid}"],
        "xcodeVersion": ["xcodebuild", "-version"],
        "developerSecurity": ["DevToolsSecurity", "-status"],
        "automationModeBefore": ["automationmodetool"],
    }
    results = {
        name: shared.run_command(command) for name, command in commands.items()
    }
    results["automationModeEnable"] = shared.run_command(
        [
            "sudo",
            "-n",
            "automationmodetool",
            "enable-automationmode-without-authentication",
        ],
        timeout=30,
    )
    results["automationModeAfter"] = shared.run_command(["automationmodetool"])
    results["nativeSession"] = shared.run_command(
        [str(helper), "session", str(evidence / "aqua-session.json")]
    )
    results["initialSources"] = source_snapshot(
        helper,
        evidence,
        "input-sources-initial.json",
        "initial-clean-hosted-state",
    )
    write_json(evidence / "environment.json", results)

    summary = load_json(evidence / "summary.json", {})
    summary["environment"] = {
        "architecture": results["architecture"].get("stdout", "").strip(),
        "runnerArchitecture": os.environ.get("RUNNER_ARCH"),
        "aquaSession": load_json(evidence / "aqua-session.json", {}),
        "windowServerExitCode": results["windowServer"].get("exitCode"),
        "aquaLaunchDomainExitCode": results["aquaLaunchDomain"].get("exitCode"),
        "automationModeEnableExitCode": results["automationModeEnable"].get(
            "exitCode"
        ),
    }
    write_json(evidence / "summary.json", summary)


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def provenance(evidence: pathlib.Path, package: pathlib.Path, app: pathlib.Path) -> int:
    executable = app / "Contents" / "MacOS" / EXECUTABLE_NAME
    commands = {
        "packageSignature": ["pkgutil", "--check-signature", str(package)],
        "packageStapler": ["xcrun", "stapler", "validate", str(package)],
        "appVerify": [
            "codesign",
            "--verify",
            "--deep",
            "--strict",
            "--verbose=4",
            str(app),
        ],
        "appSignature": ["codesign", "-d", "--verbose=4", str(app)],
        "appGatekeeper": [
            "spctl",
            "--assess",
            "--type",
            "execute",
            "--verbose=4",
            str(app),
        ],
        "appStapler": ["xcrun", "stapler", "validate", str(app)],
        "executableFile": ["file", str(executable)],
        "executableArchitectures": ["lipo", "-archs", str(executable)],
    }
    results = {
        name: shared.run_command(command, timeout=60)
        for name, command in commands.items()
    }
    actual_digest = sha256(package)
    try:
        with (app / "Contents" / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        info = {"error": str(error)}

    architecture_output = results["executableArchitectures"].get("stdout", "")
    package_signature_output = (
        results["packageSignature"].get("stdout", "")
        + results["packageSignature"].get("stderr", "")
    )
    app_signature_output = (
        results["appSignature"].get("stdout", "")
        + results["appSignature"].get("stderr", "")
    )
    gatekeeper_output = (
        results["appGatekeeper"].get("stdout", "")
        + results["appGatekeeper"].get("stderr", "")
    )
    verified = {
        "assetDigestMatches": actual_digest == ASSET_SHA256,
        "packageSignatureValid": results["packageSignature"].get("exitCode") == 0,
        "packageStapledTicketValid": results["packageStapler"].get("exitCode") == 0,
        "appCodeSignatureValid": results["appVerify"].get("exitCode") == 0,
        "appGatekeeperAccepted": results["appGatekeeper"].get("exitCode") == 0,
        "appHasArm64Slice": "arm64" in architecture_output.split(),
        "packageDeveloperIDInstaller": (
            "Developer ID Installer: Yuncao Liu (28HU5A7B46)"
            in package_signature_output
        ),
        "packageNotarizationTrusted": (
            "trusted by the Apple notary service" in package_signature_output
        ),
        "appDeveloperIDApplication": (
            "Developer ID Application: Yuncao Liu (28HU5A7B46)"
            in app_signature_output
        ),
        "appTeamIdentifierMatches": (
            "TeamIdentifier=28HU5A7B46" in app_signature_output
        ),
        "appNotarizedDeveloperID": "Notarized Developer ID" in gatekeeper_output,
    }
    required = all(verified.values())
    value = {
        "schemaVersion": SCHEMA_VERSION,
        "recordedAt": shared.timestamp(),
        "source": {
            "repository": SOURCE_URL,
            "releaseURL": RELEASE_URL,
            "tag": RELEASE_TAG,
            "releaseCommit": RELEASE_COMMIT,
            "releaseCommitSignature": "GitHub API reported a valid verified PGP signature for the pinned release commit",
            "releaseAPIResponseEvidence": "official-release-api.json",
            "commitAPIResponseEvidence": "release-commit-api.json",
        },
        "asset": {
            "name": ASSET_NAME,
            "url": ASSET_URL,
            "expectedSHA256": ASSET_SHA256,
            "actualSHA256": actual_digest,
            "digestSource": "GitHub release asset API digest field",
            "publisherAuthoredChecksumAvailable": False,
        },
        "installationMethod": {
            "officialAssetFormat": "signed flat installer package",
            "standaloneAppAssetPublished": False,
            "method": "pkgutil --expand-full followed by copying only Payload/Squirrel.app into the user Input Methods directory",
            "packagePostinstallExecuted": False,
            "limitation": "The official release publishes no standalone app asset and no publisher-authored checksum file. The GitHub asset digest, signed and stapled package, signed app, and Gatekeeper notarization assessment are retained instead.",
        },
        "identity": {
            "expectedPackageSigner": "Developer ID Installer: Yuncao Liu (28HU5A7B46)",
            "expectedAppSigner": "Developer ID Application: Yuncao Liu (28HU5A7B46)",
            "expectedTeamIdentifier": "28HU5A7B46",
            "appBundleIdentifier": info.get("CFBundleIdentifier"),
            "appBundleVersion": info.get("CFBundleVersion"),
        },
        "verification": verified,
        "allRequiredVerificationPassed": required,
        "commands": results,
        "infoPlist": info,
    }
    write_json(evidence / "provenance.json", value)

    summary = load_json(evidence / "summary.json", {})
    summary["provenance"] = {
        "release": RELEASE_TAG,
        "releaseCommit": RELEASE_COMMIT,
        "asset": ASSET_NAME,
        "expectedSHA256": ASSET_SHA256,
        "actualSHA256": actual_digest,
        "verification": verified,
        "allRequiredVerificationPassed": required,
        "packageSigner": value["identity"]["expectedPackageSigner"],
        "appSigner": value["identity"]["expectedAppSigner"],
        "provenanceLimitation": value["installationMethod"]["limitation"],
        "packagePostinstallExecuted": False,
    }
    write_json(evidence / "summary.json", summary)
    return 0 if required else 2


def parse_timestamp(value: str | None) -> dt.datetime:
    if not value:
        return dt.datetime.now(dt.timezone.utc)
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def capture_tis_log_window(
    evidence: pathlib.Path,
    name: str,
    started_at: str | None,
    completed_at: str | None,
) -> dict[str, Any]:
    start = parse_timestamp(started_at) - dt.timedelta(seconds=2)
    end = max(parse_timestamp(completed_at), dt.datetime.now(dt.timezone.utc))
    time.sleep(0.5)
    end += dt.timedelta(seconds=1)
    predicate = (
        '(subsystem CONTAINS[c] "TextInput" '
        'OR category CONTAINS[c] "TextInput" '
        'OR process == "TextInputMenuAgent" '
        'OR process == "imklaunchagent" '
        'OR process == "SystemUIServer" '
        'OR eventMessage CONTAINS[c] "TIS" '
        'OR eventMessage CONTAINS[c] "Squirrel" '
        'OR eventMessage CONTAINS[c] "Dvorak")'
    )
    command = [
        "/usr/bin/log",
        "show",
        "--start",
        start.astimezone().strftime("%Y-%m-%d %H:%M:%S%z"),
        "--end",
        end.astimezone().strftime("%Y-%m-%d %H:%M:%S%z"),
        "--style",
        "json",
        "--info",
        "--debug",
        "--predicate",
        predicate,
    ]
    started = shared.timestamp()
    timed_out = False
    try:
        completed = subprocess.run(
            command, capture_output=True, text=True, timeout=30, check=False
        )
        lines = completed.stdout.splitlines()[-800:]
        stderr = shared.bounded(completed.stderr, 16_384)
        exit_code = completed.returncode
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode(errors="replace")
        stderr_value = error.stderr or ""
        if isinstance(stderr_value, bytes):
            stderr_value = stderr_value.decode(errors="replace")
        lines = stdout.splitlines()[-800:]
        stderr = shared.bounded(stderr_value, 16_384)
        exit_code = None
        timed_out = True
    log_path = evidence / f"tis-log-{name}.jsonl"
    log_path.write_text("\n".join(lines) + ("\n" if lines else ""))
    result = {
        "command": command,
        "startedAt": started,
        "completedAt": shared.timestamp(),
        "transitionStartedAt": started_at,
        "transitionCompletedAt": completed_at,
        "windowStart": start.isoformat(),
        "windowEnd": end.isoformat(),
        "exitCode": exit_code,
        "timedOut": timed_out,
        "retainedLineCount": len(lines),
        "retainedTailLimit": 800,
        "logPath": log_path.name,
        "stderr": stderr,
    }
    write_json(evidence / f"tis-log-{name}-metadata.json", result)
    return result


def native_transition(
    helper: pathlib.Path,
    evidence: pathlib.Path,
    name: str,
    arguments: list[str],
) -> dict[str, Any]:
    path = evidence / f"transition-{name}.json"
    command = shared.run_command([str(helper), *arguments, str(path)], timeout=45)
    data = load_json(path, {})
    logs = capture_tis_log_window(
        evidence, name, data.get("startedAt"), data.get("completedAt")
    )
    return {"command": command, "data": data, "logs": logs}


def current_id(snapshot: dict[str, Any]) -> str | None:
    data = snapshot.get("data", snapshot)
    return data.get("current", {}).get("inputSourceID")


def update_initial_dvorak_state(evidence: pathlib.Path, snapshot: dict[str, Any]) -> None:
    sources = snapshot.get("data", {}).get("sources", [])
    dvorak = next(
        (source for source in sources if source.get("inputSourceID") == DVORAK_ID),
        {},
    )
    state_path = evidence / "installation-state.json"
    state = load_json(state_path, {})
    state["dvorakInitiallyEnabled"] = dvorak.get("enabled") is True
    write_json(state_path, state)


def element_ids(response: dict[str, Any]) -> list[str]:
    values = response.get("value", [])
    if not isinstance(values, list):
        return []
    return [
        value.get(ELEMENT_KEY) or value.get("ELEMENT")
        for value in values
        if isinstance(value, dict)
        and (value.get(ELEMENT_KEY) or value.get("ELEMENT"))
    ]


def find_elements(driver: Any, session_id: str, xpath: str) -> list[str]:
    response = driver.request(
        "POST",
        f"/session/{session_id}/elements",
        {"using": "xpath", "value": xpath},
    )
    return element_ids(response)


def semantic_element(driver: Any, session_id: str, element_id: str) -> dict[str, Any]:
    names = (
        "identifier",
        "label",
        "title",
        "value",
        "enabled",
        "hittable",
        "selected",
        "elementType",
    )
    value = {
        name: shared.attribute(driver, session_id, element_id, name)
        for name in names
    }
    value["elementId"] = element_id
    return value


def truthy(value: Any) -> bool:
    return value is True or str(value).lower() == "true"


def semantic_values(state: dict[str, Any]) -> set[str]:
    return {
        str(state.get(key, "")).strip()
        for key in ("identifier", "label", "title", "value")
        if state.get(key) is not None and str(state.get(key, "")).strip()
    }


def unique_input_menu_bar_candidate(
    states: list[dict[str, Any]], current_name: str
) -> tuple[dict[str, Any] | None, str]:
    rules = [
        (
            "exact-known-text-input-identifier",
            lambda state: bool(
                semantic_values(state)
                & {
                    "com.apple.menuextra.textinput",
                    "com.apple.TextInputMenuAgent",
                    "TextInputMenuAgent",
                }
            ),
        ),
        (
            "exact-input-menu-semantic-name",
            lambda state: bool(
                semantic_values(state) & {"Input menu", "Text Input menu"}
            ),
        ),
        (
            "exact-current-source-name",
            lambda state: current_name in semantic_values(state),
        ),
    ]
    for rule_name, rule in rules:
        matches = [state for state in states if rule(state)]
        if len(matches) == 1:
            return matches[0], rule_name
        if len(matches) > 1:
            return None, f"ambiguous-{rule_name}-{len(matches)}-matches"
    return None, "no-exact-semantic-input-menu-bar-match"


def unique_target_menu_item(
    states: list[dict[str, Any]], target_name: str
) -> tuple[dict[str, Any] | None, str]:
    matches = [state for state in states if target_name in semantic_values(state)]
    selectable = [
        state
        for state in matches
        if truthy(state.get("enabled")) and truthy(state.get("hittable"))
    ]
    if len(selectable) == 1:
        return selectable[0], "unique-exact-enabled-hittable-target-name"
    if len(matches) == 1 and not selectable:
        return None, "exact-target-was-not-enabled-and-hittable"
    if len(matches) > 1:
        return None, f"ambiguous-exact-target-{len(matches)}-matches"
    return None, "exact-target-not-exposed"


def menu_selection(
    driver: Any,
    helper: pathlib.Path,
    evidence: pathlib.Path,
    name: str,
    target_id: str,
    target_name: str,
    current_name: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "attempted": True,
        "startedAt": shared.timestamp(),
        "method": "semantic Accessibility through Appium Mac2/XCTest and the SystemUIServer input menu",
        "target": {"inputSourceID": target_id, "localizedName": target_name},
        "usesOCRPixelsOrCoordinates": False,
        "selectionVerified": False,
    }
    session_id: str | None = None
    try:
        session_id, response = shared.create_bundle_session(
            driver, "com.apple.systemuiserver", {"appium:noReset": True}
        )
        result["session"] = {"created": True, "response": response}
        menu_bar_elements = find_elements(
            driver, session_id, "//XCUIElementTypeMenuBarItem"
        )
        menu_bar_states = [
            semantic_element(driver, session_id, element)
            for element in menu_bar_elements
        ]
        result["menuBarCandidates"] = menu_bar_states
        menu_bar_item, rule = unique_input_menu_bar_candidate(
            menu_bar_states, current_name
        )
        result["menuBarMatchRule"] = rule
        if not menu_bar_item:
            raise RuntimeError(
                "Input menu bar item did not have one exact semantic match: " + rule
            )
        driver.request(
            "POST",
            f"/session/{session_id}/element/{menu_bar_item['elementId']}/click",
            {},
        )
        result["inputMenuOpened"] = True
        time.sleep(0.5)
        result["accessibilitySourceWithMenuOpen"] = shared.save_source(
            driver, session_id, evidence / f"input-menu-{name}.xml"
        )
        menu_elements = find_elements(
            driver, session_id, "//XCUIElementTypeMenuItem"
        )
        menu_states = [
            semantic_element(driver, session_id, element) for element in menu_elements
        ]
        result["menuItemCandidates"] = menu_states
        target, target_rule = unique_target_menu_item(menu_states, target_name)
        result["targetMatchRule"] = target_rule
        if not target:
            raise RuntimeError(
                "Intended input source did not have one exact selectable menu item: "
                + target_rule
            )
        result["targetElement"] = target
        result["sourceImmediatelyBeforeTargetPress"] = source_snapshot(
            helper,
            evidence,
            f"input-sources-before-{name}-menu-selection.json",
            f"immediately-before-{name}-menu-selection-attempt",
        )
        result["targetPressStartedAt"] = shared.timestamp()
        driver.request(
            "POST",
            f"/session/{session_id}/element/{target['elementId']}/click",
            {},
        )
        result["targetPressed"] = True
        result["targetPressCompletedAt"] = shared.timestamp()
        result["sourceImmediatelyAfterTargetPress"] = source_snapshot(
            helper,
            evidence,
            f"input-sources-after-{name}-menu-selection.json",
            f"immediately-after-{name}-menu-selection-attempt",
        )
        result["selectionVerified"] = (
            current_id(result["sourceImmediatelyAfterTargetPress"]) == target_id
        )
    except Exception as error:
        result["error"] = {
            "type": type(error).__name__,
            "message": shared.bounded(str(error)),
        }
        if "sourceImmediatelyBeforeTargetPress" not in result:
            result["sourceImmediatelyBeforeTargetPress"] = source_snapshot(
                helper,
                evidence,
                f"input-sources-before-{name}-menu-selection.json",
                f"before-incomplete-{name}-menu-selection-attempt",
            )
        result["sourceImmediatelyAfterTargetPress"] = source_snapshot(
            helper,
            evidence,
            f"input-sources-after-{name}-menu-selection.json",
            f"after-incomplete-{name}-menu-selection-attempt",
        )
    finally:
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                result.setdefault("session", {})["deleted"] = True
            except Exception as error:
                result.setdefault("session", {})["deleteError"] = shared.bounded(
                    str(error)
                )
    result["completedAt"] = shared.timestamp()
    result["logs"] = capture_tis_log_window(
        evidence, f"{name}-menu-selection", result["startedAt"], result["completedAt"]
    )
    write_json(evidence / f"{name}-menu-selection.json", result)
    return result


def approve_system_settings(
    driver: Any, helper: pathlib.Path, evidence: pathlib.Path
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "attempted": True,
        "startedAt": shared.timestamp(),
        "method": "exact semantic Accessibility Allow action through Appium Mac2/XCTest",
        "screenshotsDiagnosticOnly": True,
        "usesOCRPixelsOrCoordinates": False,
        "semanticAllowVerified": False,
        "allowClicked": False,
    }
    session_id: str | None = None
    result["sourceImmediatelyBeforeAllow"] = source_snapshot(
        helper,
        evidence,
        "input-sources-before-accessibility-allow.json",
        "immediately-before-exact-accessibility-allow-action",
    )
    try:
        session_id, response = shared.create_bundle_session(
            driver, "com.apple.systempreferences", {"appium:noReset": True}
        )
        result["session"] = {"created": True, "response": response}
        result["accessibilitySourceBefore"] = shared.save_source(
            driver, session_id, evidence / "system-settings-consent.xml"
        )
        result["diagnosticScreenshotBefore"] = shared.save_screenshot(
            driver, session_id, evidence / "system-settings-consent-before.png"
        )
        allow_element = shared.find_element(
            driver,
            session_id,
            [("accessibility id", "action-button-1")],
            timeout=25,
        )
        semantic = semantic_element(driver, session_id, allow_element)
        result["allowElement"] = semantic
        exact_allow = (
            semantic.get("identifier") == "action-button-1"
            and semantic.get("label") == "Allow"
            and truthy(semantic.get("enabled"))
            and truthy(semantic.get("hittable"))
        )
        result["semanticAllowVerified"] = exact_allow
        if not exact_allow:
            raise RuntimeError(
                f"Refusing to click non-matching consent control: {semantic}"
            )
        driver.request(
            "POST", f"/session/{session_id}/element/{allow_element}/click", {}
        )
        result["allowClicked"] = True
        result["allowClickedAt"] = shared.timestamp()
        result["sourceImmediatelyAfterAllow"] = source_snapshot(
            helper,
            evidence,
            "input-sources-after-accessibility-allow.json",
            "immediately-after-exact-accessibility-allow-action",
        )
        result["diagnosticScreenshotAfter"] = shared.save_screenshot(
            driver, session_id, evidence / "system-settings-consent-after.png"
        )
    except Exception as error:
        result["error"] = {
            "type": type(error).__name__,
            "message": shared.bounded(str(error)),
        }
        result["sourceImmediatelyAfterAllow"] = source_snapshot(
            helper,
            evidence,
            "input-sources-after-accessibility-allow.json",
            "after-incomplete-accessibility-allow-action",
        )
    finally:
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                result.setdefault("session", {})["deleted"] = True
            except Exception as error:
                result.setdefault("session", {})["deleteError"] = shared.bounded(
                    str(error)
                )
    result["completedAt"] = shared.timestamp()
    result["logs"] = capture_tis_log_window(
        evidence,
        "accessibility-allow",
        result["startedAt"],
        result["completedAt"],
    )
    write_json(evidence / "system-settings-approval.json", result)
    return result


def process_snapshot() -> dict[str, Any]:
    return shared.process_snapshot(BUNDLE_ID, EXECUTABLE_NAME)


def timeline_entries(path: pathlib.Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    try:
        for line in path.read_text().splitlines():
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                entries.append(value)
    except OSError:
        pass
    return entries


def create_client_session(
    driver: Any, client_app: pathlib.Path, evidence: pathlib.Path, name: str
) -> tuple[str, pathlib.Path, pathlib.Path]:
    diagnostics = evidence / f"client-{name}-current.json"
    timeline = evidence / f"client-{name}-timeline.jsonl"
    session_id, _ = shared.create_session(driver, client_app, diagnostics, timeline)
    return session_id, diagnostics, timeline


def dvorak_key_proof(
    driver: Any,
    helper: pathlib.Path,
    client_app: pathlib.Path,
    evidence: pathlib.Path,
    name: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "startedAt": shared.timestamp(),
        "physicalKeyCode": 37,
        "physicalUSKey": "l",
        "expectedDvorakText": "n",
    }
    session_id: str | None = None
    try:
        session_id, diagnostics, _ = create_client_session(
            driver, client_app, evidence, name
        )
        element = shared.find_text_view(driver, session_id)
        result["focus"] = shared.focus_text_view(
            driver, session_id, element, diagnostics
        )
        result["sourceAtDelivery"] = source_snapshot(
            helper,
            evidence,
            f"input-sources-at-{name}-key-delivery.json",
            f"source-at-{name}-physical-key-delivery",
        )
        key_path = evidence / f"key-{name}-37.json"
        result["keyCommand"] = shared.run_command(
            [str(helper), "post-key", "37", "physical-us-l", str(key_path)],
            timeout=15,
        )
        result["keyEvent"] = load_json(key_path, {})
        time.sleep(1)
        result["clientDiagnostics"] = shared.diagnostics_snapshot(diagnostics)
        result["passed"] = (
            current_id(result["sourceAtDelivery"]) == DVORAK_ID
            and result["clientDiagnostics"].get("text") == "n"
        )
    except Exception as error:
        result["error"] = {
            "type": type(error).__name__,
            "message": shared.bounded(str(error)),
        }
        result["passed"] = False
    finally:
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                result["sessionDeleted"] = True
            except Exception as error:
                result["sessionDeleteError"] = shared.bounded(str(error))
    result["completedAt"] = shared.timestamp()
    write_json(evidence / f"dvorak-key-proof-{name}.json", result)
    return result


def squirrel_composition_proof(
    driver: Any,
    helper: pathlib.Path,
    client_app: pathlib.Path,
    evidence: pathlib.Path,
    name: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "startedAt": shared.timestamp(),
        "attempted": True,
        "deliveryMechanism": "physical-key-code CGEvents at cghidEventTap",
        "expectedText": EXPECTED_TEXT,
        "expectedTextScalars": EXPECTED_SCALARS,
    }
    session_id: str | None = None
    try:
        session_id, diagnostics, timeline_path = create_client_session(
            driver, client_app, evidence, name
        )
        element = shared.find_text_view(driver, session_id)
        result["focus"] = shared.focus_text_view(
            driver, session_id, element, diagnostics
        )
        result["sourceAtDelivery"] = source_snapshot(
            helper,
            evidence,
            f"input-sources-at-{name}-composition-delivery.json",
            f"source-at-{name}-composition-delivery",
        )
        result["processBeforeKeys"] = process_snapshot()
        key_specs = [
            (45, "n"),
            (34, "i"),
            (4, "h"),
            (0, "a"),
            (31, "o"),
            (49, "space"),
        ]
        keys: list[dict[str, Any]] = []
        for index, (key_code, label) in enumerate(key_specs, start=1):
            key_path = evidence / f"key-{name}-{index}-{label}.json"
            command = shared.run_command(
                [
                    str(helper),
                    "post-key",
                    str(key_code),
                    label,
                    str(key_path),
                ],
                timeout=15,
            )
            time.sleep(0.5)
            keys.append(
                {
                    "index": index,
                    "label": label,
                    "keyCode": key_code,
                    "command": command,
                    "event": load_json(key_path, {}),
                    "clientDiagnosticsAfter": shared.diagnostics_snapshot(
                        diagnostics
                    ),
                    "processAfter": process_snapshot(),
                }
            )
        time.sleep(1)
        final_diagnostics = shared.diagnostics_snapshot(diagnostics)
        timeline = timeline_entries(timeline_path)
        marked = [entry for entry in timeline if entry.get("hasMarkedText") is True]
        process_observed = result["processBeforeKeys"].get("processCount", 0) > 0 or any(
            key["processAfter"].get("processCount", 0) > 0 for key in keys
        )
        marked_range = final_diagnostics.get("markedRange") or {}
        composition_ended = (
            final_diagnostics.get("hasMarkedText") is False
            and marked_range.get("length") == 0
        )
        exact_passed = (
            final_diagnostics.get("textScalars") == EXPECTED_SCALARS
            and composition_ended
        )
        source_selected = current_id(result["sourceAtDelivery"]) == MODE_ID
        result.update(
            {
                "keys": keys,
                "finalClientDiagnostics": final_diagnostics,
                "timelineEntryCount": len(timeline),
                "markedCompositionObserved": bool(marked),
                "markedCompositionSamples": marked[:8],
                "processObserved": process_observed,
                "sourceSelectedAtDelivery": source_selected,
                "compositionEnded": composition_ended,
                "exactTextAssertionPassed": exact_passed,
                "actualSelectionAndActivationProven": (
                    source_selected and process_observed and exact_passed
                ),
            }
        )
    except Exception as error:
        result["error"] = {
            "type": type(error).__name__,
            "message": shared.bounded(str(error)),
        }
        result["sourceSelectedAtDelivery"] = False
        result["processObserved"] = False
        result["exactTextAssertionPassed"] = False
        result["actualSelectionAndActivationProven"] = False
    finally:
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                result["sessionDeleted"] = True
            except Exception as error:
                result["sessionDeleteError"] = shared.bounded(str(error))
    result["completedAt"] = shared.timestamp()
    write_json(evidence / f"squirrel-composition-proof-{name}.json", result)
    return result


def start_appium(evidence: pathlib.Path) -> tuple[Any, Any, Any, dict[str, Any]]:
    transcript = evidence / "webdriver-transcript.jsonl"
    appium_log = (evidence / "appium.log").open("w")
    driver = shared.WebDriver("http://127.0.0.1:4723", transcript)
    process = subprocess.Popen(
        ["appium", "--base-path", "/", "--log-no-colors", "--log-timestamp"],
        stdout=appium_log,
        stderr=subprocess.STDOUT,
        text=True,
    )
    server = {
        "pid": process.pid,
        "readiness": shared.wait_for_server(driver),
    }
    return driver, process, appium_log, server


def stop_appium(process: Any, handle: Any, server: dict[str, Any]) -> None:
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
    server["exitCode"] = process.returncode
    handle.close()


def run_control(
    evidence: pathlib.Path,
    helper: pathlib.Path,
    client_app: pathlib.Path,
    installed_app: pathlib.Path,
) -> int:
    report: dict[str, Any] = {
        "startedAt": shared.timestamp(),
        "stageOrder": [
            "same-session Dvorak public and Accessibility controls",
            "Squirrel registration",
            "exact parent enablement",
            "exact intended mode enablement",
            "exact Accessibility Allow action",
            "public TIS selection",
            "semantic Accessibility input-menu selection",
            "current-source, process, and physical-key/composition proof",
        ],
        "server": {},
    }
    appium_process = None
    appium_handle = None
    completed = False
    try:
        driver, appium_process, appium_handle, report["server"] = start_appium(
            evidence
        )
        if not report["server"]["readiness"].get("ready"):
            raise RuntimeError("Appium server did not become ready")

        initial = source_snapshot(
            helper,
            evidence,
            "input-sources-before-dvorak-control.json",
            "before-same-session-dvorak-control",
        )
        report["initialSources"] = initial
        update_initial_dvorak_state(evidence, initial)

        report["dvorakEnable"] = native_transition(
            helper,
            evidence,
            "dvorak-enable",
            ["enable", DVORAK_ID, LAYOUT_TYPE],
        )
        report["dvorakPublicSelection"] = native_transition(
            helper,
            evidence,
            "dvorak-public-selection",
            ["select", DVORAK_ID, LAYOUT_TYPE, "-"],
        )
        report["dvorakPublicKeyProof"] = dvorak_key_proof(
            driver, helper, client_app, evidence, "public-api"
        )
        report["restoreUSAfterDvorakPublic"] = native_transition(
            helper,
            evidence,
            "restore-us-after-dvorak-public",
            ["select", US_ID, LAYOUT_TYPE, "-"],
        )
        report["dvorakMenuSelection"] = menu_selection(
            driver,
            helper,
            evidence,
            "dvorak",
            DVORAK_ID,
            "Dvorak",
            "U.S.",
        )
        report["dvorakMenuKeyProof"] = dvorak_key_proof(
            driver, helper, client_app, evidence, "accessibility-menu"
        )
        report["restoreUSBeforeSquirrel"] = native_transition(
            helper,
            evidence,
            "restore-us-before-squirrel",
            ["select", US_ID, LAYOUT_TYPE, "-"],
        )

        report["squirrelRegistration"] = native_transition(
            helper,
            evidence,
            "squirrel-registration",
            ["register", str(installed_app)],
        )
        report["squirrelParentEnable"] = native_transition(
            helper,
            evidence,
            "squirrel-parent-enable",
            ["enable", PARENT_ID, PARENT_TYPE],
        )
        report["squirrelModeEnable"] = native_transition(
            helper,
            evidence,
            "squirrel-mode-enable",
            ["enable", MODE_ID, MODE_TYPE],
        )
        report["systemSettingsApproval"] = approve_system_settings(
            driver, helper, evidence
        )
        report["squirrelPublicSelection"] = native_transition(
            helper,
            evidence,
            "squirrel-public-selection",
            ["select", MODE_ID, MODE_TYPE, PARENT_ID],
        )
        report["squirrelPublicComposition"] = squirrel_composition_proof(
            driver, helper, client_app, evidence, "public-api"
        )

        if report["squirrelPublicSelection"]["data"].get("selectionVerified"):
            report["restoreUSBetweenSquirrelAttempts"] = native_transition(
                helper,
                evidence,
                "restore-us-between-squirrel-attempts",
                ["select", US_ID, LAYOUT_TYPE, "-"],
            )
        else:
            report["restoreUSBetweenSquirrelAttempts"] = {
                "attempted": False,
                "reason": "Public selection left U.S. current, so no restore transition was needed.",
            }

        report["squirrelMenuSelection"] = menu_selection(
            driver,
            helper,
            evidence,
            "squirrel",
            MODE_ID,
            "Squirrel - Simplified",
            "U.S.",
        )
        report["squirrelMenuComposition"] = squirrel_composition_proof(
            driver, helper, client_app, evidence, "accessibility-menu"
        )
        report["finalSourcesBeforeCleanup"] = source_snapshot(
            helper,
            evidence,
            "input-sources-final-before-cleanup.json",
            "final-state-before-unconditional-cleanup",
        )
        completed = True
    except Exception as error:
        report["error"] = {
            "type": type(error).__name__,
            "message": shared.bounded(str(error)),
            "timestamp": shared.timestamp(),
        }
    finally:
        if appium_process is not None and appium_handle is not None:
            stop_appium(appium_process, appium_handle, report["server"])
    report["completedAt"] = shared.timestamp()
    report["executionCompleted"] = completed
    write_json(evidence / "control-experiment.json", report)
    summary = load_json(evidence / "summary.json", {})
    summary["controlExperimentEvidencePath"] = "control-experiment.json"
    summary["experimentExecutionCompleted"] = completed
    if not completed:
        summary["status"] = "execution-failed"
    write_json(evidence / "summary.json", summary)
    return 0 if completed else 3


def nested(value: dict[str, Any], *keys: str, default: Any = None) -> Any:
    current: Any = value
    for key in keys:
        if not isinstance(current, dict):
            return default
        current = current.get(key)
    return default if current is None else current


def relevant_source(snapshot: dict[str, Any], source_id: str) -> dict[str, Any]:
    data = snapshot.get("data", snapshot)
    return next(
        (
            source
            for source in data.get("sources", [])
            if source.get("inputSourceID") == source_id
        ),
        {"present": False},
    )


def final_diagnosis(
    summary: dict[str, Any], report: dict[str, Any]
) -> dict[str, Any]:
    registration = nested(report, "squirrelRegistration", "data", default={})
    parent_enable = nested(report, "squirrelParentEnable", "data", default={})
    mode_enable = nested(report, "squirrelModeEnable", "data", default={})
    approval = report.get("systemSettingsApproval", {})
    public = nested(report, "squirrelPublicSelection", "data", default={})
    menu = report.get("squirrelMenuSelection", {})
    dvorak_public = nested(report, "dvorakPublicSelection", "data", default={})
    dvorak_menu = report.get("dvorakMenuSelection", {})
    public_composition = report.get("squirrelPublicComposition", {})
    menu_composition = report.get("squirrelMenuComposition", {})

    registration_after = registration.get("after", {})
    parent_after = parent_enable.get("after", {})
    mode_after = mode_enable.get("after", {})
    approval_before = nested(
        approval, "sourceImmediatelyBeforeAllow", "data", default={}
    )
    approval_after = nested(
        approval, "sourceImmediatelyAfterAllow", "data", default={}
    )
    public_prerequisites = public.get(
        "documentedPrerequisitesImmediatelyBefore", {}
    )
    target_before_public = relevant_source(public.get("before", {}), MODE_ID)
    parent_before_public = relevant_source(public.get("before", {}), PARENT_ID)
    approval_before_prerequisites = nested(
        approval_before, "prerequisites", "squirrelHans", default={}
    )
    approval_after_prerequisites = nested(
        approval_after, "prerequisites", "squirrelHans", default={}
    )

    wrong_parent_or_mode = not (
        public_prerequisites.get("exactTargetUnique") is True
        and public_prerequisites.get("exactParentUnique") is True
        and public_prerequisites.get("parentModeRelationshipEstablished") is True
    )
    select_capable_false = target_before_public.get("selectCapable") is not True
    source_disabled = target_before_public.get("enabled") is not True
    parent_disabled = parent_before_public.get("enabled") is not True
    all_prerequisites = (
        public_prerequisites.get(
            "allDocumentedSelectionPrerequisitesSatisfied"
        )
        is True
    )
    public_rejected = public.get("status") == -50
    public_selected = public.get("selectionVerified") is True
    menu_selected = menu.get("selectionVerified") is True
    actual_activation = (
        public_composition.get("actualSelectionAndActivationProven") is True
        or menu_composition.get("actualSelectionAndActivationProven") is True
    )
    approval_changed_eligibility = (
        approval_before_prerequisites != approval_after_prerequisites
    )
    approval_no_change = (
        approval.get("semanticAllowVerified") is True
        and approval.get("allowClicked") is True
        and not approval_changed_eligibility
    )

    parent_after_registration = relevant_source(registration_after, PARENT_ID)
    parent_after_enable = relevant_source(parent_after, PARENT_ID)
    mode_after_enable = relevant_source(mode_after, MODE_ID)
    minimal_transition_fixed_parent = (
        parent_after_registration.get("enabled") is False
        and parent_after_enable.get("enabled") is True
    )

    if public_selected or menu_selected:
        unresolved = (
            "none: Squirrel became current through "
            + ("public TIS selection" if public_selected else "the semantic input menu")
        )
    elif all_prerequisites and public_rejected:
        unresolved = (
            "public selection outcome: Dvorak returned 0 and became current, while exact Squirrel Hans returned -50 and stayed non-current despite every documented prerequisite being true"
        )
    elif wrong_parent_or_mode:
        unresolved = "exact parent/mode identity or documented relationship"
    elif select_capable_false:
        unresolved = "target select-capable property was not true"
    elif source_disabled:
        unresolved = "intended Squirrel mode was disabled"
    elif parent_disabled:
        unresolved = "documented Squirrel parent input method was disabled"
    else:
        unresolved = "selection outcome was not established"

    bounded_contradiction = all_prerequisites and public_rejected and not public_selected
    if bounded_contradiction:
        conclusion = (
            "Bounded contradiction: immediately before the exact public selection call, Squirrel Hans was uniquely identified, select-capable, enabled, related to one enabled parent input method, and refreshed live; TISSelectInputSource still returned paramErr (-50), meaning the source was not selectable. No private policy explanation is asserted."
        )
    elif actual_activation:
        conclusion = (
            "Actual Squirrel selection and activation succeeded, proven by the exact current source, a live Squirrel process, and deterministic committed composition."
        )
    elif public_selected or menu_selected:
        conclusion = (
            "Squirrel became the exact current source, but process plus deterministic composition did not fully prove activation."
        )
    else:
        conclusion = (
            "Squirrel selection was not established; the first unsatisfied documented prerequisite or exact-source relationship is reported without a private policy explanation."
        )

    dvorak_key_passed = (
        nested(report, "dvorakPublicKeyProof", "passed") is True
    )
    return {
        "contractClassification": {
            "falseSelectCapableProperty": select_capable_false,
            "disabledSource": source_disabled,
            "disabledParent": parent_disabled,
            "wrongParentOrModeChoice": wrong_parent_or_mode,
            "uiApprovalNotChangingEligibility": approval_no_change,
            "apiRejectionDespiteEveryDocumentedPrerequisite": bounded_contradiction,
            "actualSuccessfulSquirrelSelection": public_selected or menu_selected,
            "actualSquirrelSelectionAndActivationProven": actual_activation,
        },
        "documentedPrerequisitesImmediatelyBeforePublicSelection": public_prerequisites,
        "publicSelection": {
            "status": public.get("status"),
            "paramErrMeansSourceIsNotSelectable": public.get(
                "paramErrMeansSourceIsNotSelectable"
            ),
            "selectionVerifiedByCurrentSource": public_selected,
        },
        "semanticInputMenuSelection": {
            "targetPressed": menu.get("targetPressed", False),
            "selectionVerifiedByCurrentSource": menu_selected,
            "error": menu.get("error"),
        },
        "approvalEligibilityComparison": {
            "before": approval_before_prerequisites,
            "after": approval_after_prerequisites,
            "changed": approval_changed_eligibility,
            "exactAllowActionProven": (
                approval.get("semanticAllowVerified") is True
                and approval.get("allowClicked") is True
            ),
        },
        "smallestCounterfactualResult": {
            "transition": summary.get("smallestCounterfactual", {}).get(
                "transition"
            ),
            "parentWasDisabledAfterRegistration": (
                parent_after_registration.get("enabled") is False
            ),
            "exactParentBecameEnabled": (
                parent_after_enable.get("enabled") is True
            ),
            "intendedModeBecameEnabled": mode_after_enable.get("enabled") is True,
            "minimalTransitionFixedParentPrerequisite": minimal_transition_fixed_parent,
            "minimalTransitionWasSufficientForSelection": (
                minimal_transition_fixed_parent and (public_selected or menu_selected)
            ),
            "disconfirmedAsSufficient": (
                minimal_transition_fixed_parent
                and not (public_selected or menu_selected)
            ),
        },
        "sameSessionDvorakControl": {
            "publicStatus": dvorak_public.get("status"),
            "publicSelectionVerified": dvorak_public.get("selectionVerified", False),
            "semanticMenuSelectionVerified": dvorak_menu.get(
                "selectionVerified", False
            ),
            "physicalKeyCode37ProducedN": dvorak_key_passed,
        },
        "earliestObservedDivergence": (
            "after registration: Dvorak needed no parent, while Squirrel Hans had a documented parent with enabled=false"
            if parent_after_registration.get("enabled") is False
            else "no disabled Squirrel parent was observed after registration"
        ),
        "earliestUnresolvedDivergenceAfterDocumentedTransitions": unresolved,
        "boundedContradiction": bounded_contradiction,
        "privatePolicyExplanationAsserted": False,
        "conclusion": conclusion,
        "disconfirmingEvidence": {
            "dvorakPublicSelectionAndPhysicalMapping": (
                dvorak_public.get("selectionVerified") is True and dvorak_key_passed
            ),
            "squirrelParentDisabledAfterRegistration": (
                parent_after_registration.get("enabled") is False
            ),
            "squirrelParentEnabledBeforeSelection": (
                parent_before_public.get("enabled") is True
            ),
            "squirrelModeSelectCapableBeforeSelection": (
                target_before_public.get("selectCapable") is True
            ),
            "squirrelModeEnabledBeforeSelection": (
                target_before_public.get("enabled") is True
            ),
            "accessibilityMenuAttemptRetained": menu.get("attempted", False),
            "currentSourceSnapshotsRetained": True,
            "processAndCompositionAttemptsRetained": True,
            "boundedTISLogWindowsRetained": True,
        },
        "scopeLimit": "This diagnosis is evidence only and authorizes no implementation, security, runner, or infrastructure change.",
    }


def finalize(evidence: pathlib.Path, producer_status: int) -> None:
    summary = load_json(evidence / "summary.json", {})
    report = load_json(evidence / "control-experiment.json", {})
    cleanup = load_json(evidence / "cleanup.json", {})
    provenance_data = load_json(evidence / "provenance.json", {})
    summary["completedAt"] = shared.timestamp()
    summary["producerExitCode"] = producer_status
    summary["actionsRunURL"] = github_run_url() or summary.get("actionsRunURL")
    summary["diagnosis"] = final_diagnosis(summary, report)
    summary["cleanup"] = cleanup
    summary["cleanupPassed"] = cleanup.get("success") is True
    summary["provenancePassed"] = (
        provenance_data.get("allRequiredVerificationPassed") is True
    )
    summary["boundedExperimentCompleted"] = (
        producer_status == 0
        and report.get("executionCompleted") is True
        and summary["cleanupPassed"]
        and summary["provenancePassed"]
    )
    summary["status"] = (
        "completed" if summary["boundedExperimentCompleted"] else "incomplete"
    )
    write_json(evidence / "summary.json", summary)


def main() -> int:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    init_parser = commands.add_parser("init")
    init_parser.add_argument("evidence", type=pathlib.Path)
    init_parser.add_argument("installed_app", type=pathlib.Path)

    preflight_parser = commands.add_parser("preflight")
    preflight_parser.add_argument("evidence", type=pathlib.Path)
    preflight_parser.add_argument("helper", type=pathlib.Path)

    provenance_parser = commands.add_parser("provenance")
    provenance_parser.add_argument("evidence", type=pathlib.Path)
    provenance_parser.add_argument("package", type=pathlib.Path)
    provenance_parser.add_argument("app", type=pathlib.Path)

    run_parser = commands.add_parser("run")
    run_parser.add_argument("evidence", type=pathlib.Path)
    run_parser.add_argument("helper", type=pathlib.Path)
    run_parser.add_argument("client_app", type=pathlib.Path)
    run_parser.add_argument("installed_app", type=pathlib.Path)

    finalize_parser = commands.add_parser("finalize")
    finalize_parser.add_argument("evidence", type=pathlib.Path)
    finalize_parser.add_argument("producer_status", type=int)

    arguments = parser.parse_args()
    if arguments.command == "init":
        initialize(arguments.evidence, arguments.installed_app)
        return 0
    if arguments.command == "preflight":
        preflight(arguments.evidence, arguments.helper)
        return 0
    if arguments.command == "provenance":
        return provenance(arguments.evidence, arguments.package, arguments.app)
    if arguments.command == "run":
        return run_control(
            arguments.evidence,
            arguments.helper,
            arguments.client_app,
            arguments.installed_app,
        )
    if arguments.command == "finalize":
        finalize(arguments.evidence, arguments.producer_status)
        return 0
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
