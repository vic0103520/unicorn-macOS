#!/usr/bin/env python3
"""Bounded Squirrel direct-launch counterfactual on hosted ARM64 macOS."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
import pathlib
import plistlib
import shutil
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

SCHEMA_VERSION = 3
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
VERIFIED_ACTIVATION_FAILURE_RUN_URL = (
    "https://github.com/vic0103520/unicorn-macOS/actions/runs/32830534336"
)
DIRECT_LAUNCH_DEADLINE_SECONDS = 20


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
            "directLaunch": None,
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
            "probe": "github-hosted-arm64-squirrel-direct-launch-counterfactual",
            "status": "running",
            "startedAt": shared.timestamp(),
            "actionsRunURL": github_run_url(),
            "boundedScope": {
                "runnerLabel": "macos-15",
                "expectedArchitecture": "arm64",
                "sourcesUnderDiagnosis": [DVORAK_ID, BUNDLE_ID],
                "primaryCounterfactualCount": 1,
                "primaryCounterfactual": "direct execution of the exact signed Squirrel executable as runner",
                "thirdPartyProductCount": 1,
                "thirdPartyProduct": "official Rime Squirrel 1.1.2",
                "screenshotsDiagnosticOnly": True,
                "passFailUsesOCRPixelsOrCoordinates": False,
                "productBehaviorChanged": False,
                "privatePreferenceOrAuthorizationDatabaseEdited": False,
                "packageInstallerOrPostinstallExecuted": False,
                "systemInputMethodsDirectoryUsed": False,
                "securityWeakened": False,
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
            "verifiedStartingPoint": {
                "priorRunURL": VERIFIED_ACTIVATION_FAILURE_RUN_URL,
                "priorResult": "Exact Squirrel Hans became enabled, select-capable, selected, and current after parent enablement plus exact Allow, but automatic activation failed before process creation with LaunchInputMethod status -50, no Squirrel PID, no endpoint, and no composition.",
                "reusedWithoutBroadReinvestigation": [
                    "pinned publisher provenance checks",
                    "safe payload extraction and user-local copy",
                    "Rime prebuild",
                    "exact registration, parent/mode enablement, and Allow sequence",
                    "Dvorak public selection and physical-event control",
                    "focused AppKit client and deterministic nihao-space composition proof",
                ],
            },
            "smallestCounterfactual": {
                "transition": "After the verified setup and exact approval sequence, execute the no-argument signed Squirrel executable directly as runner, wait a bounded deadline for the exact PID and setIMKXPCEndpoint, then select Hans and compose only if both boundaries pass.",
                "whySmallest": "Only the automatic LaunchServices/imklaunchagent startup boundary is bypassed. The product, payload, user, path, provenance, registration, data, approval, source, client, and physical events remain unchanged.",
                "explicitOutcomes": [
                    "process exits before endpoint",
                    "process lives but no endpoint",
                    "process lives plus endpoint but composition fails",
                    "process lives, endpoint registers, and composition succeeds",
                ],
                "causalClaimLimit": "Success isolates automatic LaunchServices/session resolution. Exit or no endpoint reports only the earliest observed application boundary.",
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
        'OR process == "Squirrel" '
        'OR eventMessage CONTAINS[c] "im.rime.inputmethod.Squirrel" '
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
        "ndjson",
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


def bounded_imk_log_evidence(path: pathlib.Path) -> dict[str, Any]:
    retained: list[dict[str, Any]] = []
    keywords = (
        "launchinputmethod",
        "imklaunchagent",
        "getimkxpcendpoint",
        "no endpoint",
        BUNDLE_ID.lower(),
        MODE_ID.lower(),
    )
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        lines = []
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        message = str(event.get("eventMessage", ""))
        if any(keyword in message.lower() for keyword in keywords):
            retained.append(
                {
                    "timestamp": event.get("timestamp"),
                    "process": event.get("process"),
                    "processImagePath": event.get("processImagePath"),
                    "subsystem": event.get("subsystem"),
                    "category": event.get("category"),
                    "eventMessage": message,
                }
            )
    launch_failure = any(
        "launchinputmethod() error" in str(event.get("eventMessage", "")).lower()
        or "no endpoint" in str(event.get("eventMessage", "")).lower()
        for event in retained
    )
    return {
        "sourcePath": path.name,
        "matchingEventCount": len(retained),
        "retainedEvents": retained[:100],
        "retainedEventLimit": 100,
        "imkLaunchFailureObserved": launch_failure,
    }


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
    current = snapshot.get("data", {}).get("current", {})
    state["initialCurrentSourceID"] = current.get("inputSourceID")
    state["initialCurrentSourceType"] = current.get("type")
    write_json(state_path, state)


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


def menu_selection(
    driver: Any,
    helper: pathlib.Path,
    evidence: pathlib.Path,
    name: str,
    target_id: str,
    target_name: str,
    current_name: str,
) -> dict[str, Any]:
    del driver
    path = evidence / f"{name}-menu-selection.json"
    command = shared.run_command(
        [
            str(helper),
            "menu-select",
            target_id,
            target_name,
            current_name,
            str(path),
        ],
        timeout=45,
    )
    result = load_json(path, {})
    result["command"] = command
    result["logs"] = capture_tis_log_window(
        evidence,
        f"{name}-menu-selection",
        result.get("startedAt"),
        result.get("completedAt"),
    )
    write_json(path, result)
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
    value = shared.process_snapshot(BUNDLE_ID, EXECUTABLE_NAME)
    value["inputMethodLaunchProcesses"] = shared.run_command(
        ["pgrep", "-alf", "Squirrel|imklaunchagent"], timeout=15
    )
    return value


def exact_process_snapshot(pid: int, executable: pathlib.Path) -> dict[str, Any]:
    return {
        "timestamp": shared.timestamp(),
        "expectedPID": pid,
        "expectedExecutablePath": str(executable),
        "exactPID": shared.run_command(
            [
                "ps",
                "-p",
                str(pid),
                "-o",
                "pid=,ppid=,uid=,user=,state=,etime=,lstart=,comm=,args=",
            ],
            timeout=10,
        ),
        "relevantProcesses": process_snapshot(),
    }


def endpoint_events(
    path: pathlib.Path, expected_pid: int | None = None
) -> list[dict[str, Any]]:
    parsed: list[dict[str, Any]] = []
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return []
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        parsed.append(event)
    peer_marker = (
        f"setxpcendpoint.peer[{expected_pid}]" if expected_pid is not None else None
    )
    peer_events = [
        event
        for event in parsed
        if peer_marker
        and peer_marker in str(event.get("eventMessage", "")).lower()
    ]
    if expected_pid is not None and not peer_events:
        return []
    events: list[dict[str, Any]] = []
    for event in parsed:
        message = str(event.get("eventMessage", ""))
        if "Received setIMKXPCEndpoint:forBundleIdentifier: from InputMethod" in message:
            events.append(
                {
                    "timestamp": event.get("timestamp"),
                    "process": event.get("process"),
                    "processImagePath": event.get("processImagePath"),
                    "subsystem": event.get("subsystem"),
                    "category": event.get("category"),
                    "eventMessage": message,
                    "exactPIDPeerCorrelation": expected_pid is not None,
                    "expectedPID": expected_pid,
                    "peerEvents": [
                        {
                            "timestamp": peer.get("timestamp"),
                            "processImagePath": peer.get("processImagePath"),
                            "eventMessage": peer.get("eventMessage"),
                        }
                        for peer in peer_events[:8]
                    ],
                }
            )
    return events


def diagnostic_reports() -> list[dict[str, Any]]:
    directories = [
        pathlib.Path.home() / "Library" / "Logs" / "DiagnosticReports",
        pathlib.Path("/Library/Logs/DiagnosticReports"),
    ]
    reports: list[dict[str, Any]] = []
    for directory in directories:
        try:
            candidates = list(directory.glob("Squirrel*"))
        except OSError:
            candidates = []
        for path in candidates:
            try:
                stat = path.stat()
            except OSError:
                continue
            reports.append(
                {
                    "path": str(path),
                    "size": stat.st_size,
                    "modifiedAtEpoch": stat.st_mtime,
                }
            )
    return sorted(reports, key=lambda item: str(item["path"]))


def capture_direct_log_show(
    evidence: pathlib.Path,
    started_at: str,
    completed_at: str | None = None,
    expected_pid: int | None = None,
) -> dict[str, Any]:
    start = parse_timestamp(started_at) - dt.timedelta(seconds=1)
    end = parse_timestamp(completed_at) + dt.timedelta(seconds=1) if completed_at else None
    predicate = (
        '(subsystem CONTAINS[c] "TextInput" '
        'OR subsystem CONTAINS[c] "LaunchServices" '
        'OR subsystem CONTAINS[c] "RunningBoard" '
        'OR subsystem CONTAINS[c] "InputMethodKit" '
        'OR process == "Squirrel" '
        'OR process == "imklaunchagent" '
        'OR process == "lsd" '
        'OR process == "launchservicesd" '
        'OR process == "runningboardd" '
        'OR process == "amfid" '
        'OR process == "taskgated" '
        'OR process == "syspolicyd" '
        'OR process == "ReportCrash" '
        'OR process == "CrashReporterSupportHelper" '
        'OR eventMessage CONTAINS[c] "im.rime.inputmethod.Squirrel" '
        'OR eventMessage CONTAINS[c] "LaunchInputMethod" '
        'OR eventMessage CONTAINS[c] "IMKXPCEndpoint" '
        'OR eventMessage CONTAINS[c] "dyld")'
    )
    command = [
        "/usr/bin/log",
        "show",
        "--start",
        start.astimezone().strftime("%Y-%m-%d %H:%M:%S%z"),
    ]
    if end:
        command.extend(
            ["--end", end.astimezone().strftime("%Y-%m-%d %H:%M:%S%z")]
        )
    command.extend(
        ["--style", "ndjson", "--info", "--debug", "--predicate", predicate]
    )
    completed = subprocess.run(
        command, capture_output=True, text=True, timeout=45, check=False
    )
    all_lines = completed.stdout.splitlines()
    lines = (
        all_lines
        if len(all_lines) <= 4_000
        else [
            *all_lines[:2_000],
            '{"boundedEvidence":"middle log lines omitted"}',
            *all_lines[-2_000:],
        ]
    )
    path = evidence / "direct-launch-log-show.jsonl"
    path.write_text("\n".join(lines) + ("\n" if lines else ""))
    metadata = {
        "command": command,
        "exitCode": completed.returncode,
        "sourceLineCount": len(all_lines),
        "retainedLineCount": len(lines),
        "retainedHeadAndTailLimit": 4_000,
        "path": path.name,
        "stderr": shared.bounded(completed.stderr, 32_768),
        "endpointEvents": endpoint_events(path, expected_pid),
        "endpointCorrelationExpectedPID": expected_pid,
    }
    write_json(evidence / "direct-launch-log-show-metadata.json", metadata)
    return metadata


def start_direct_launch(
    evidence: pathlib.Path, installed_app: pathlib.Path
) -> tuple[dict[str, Any], dict[str, Any]]:
    executable = installed_app / "Contents" / "MacOS" / EXECUTABLE_NAME
    working_directory = installed_app / "Contents" / "SharedSupport"
    process_preflight = process_snapshot()
    write_json(evidence / "direct-launch-preflight-process.json", process_preflight)
    if process_preflight.get("processCount") != 0:
        raise RuntimeError(
            "Refusing direct launch because a pre-existing Squirrel process is present"
        )
    reports_before = diagnostic_reports()
    stream_path = evidence / "direct-launch-unified-log.jsonl"
    stream_stderr_path = evidence / "direct-launch-unified-log.stderr"
    stdout_path = evidence / "direct-launch-stdout.log"
    stderr_path = evidence / "direct-launch-stderr.log"
    timeline_path = evidence / "direct-launch-process-timeline.jsonl"
    predicate = (
        '(subsystem CONTAINS[c] "TextInput" '
        'OR subsystem CONTAINS[c] "LaunchServices" '
        'OR subsystem CONTAINS[c] "RunningBoard" '
        'OR subsystem CONTAINS[c] "InputMethodKit" '
        'OR process == "Squirrel" OR process == "imklaunchagent" '
        'OR process == "lsd" OR process == "launchservicesd" '
        'OR process == "runningboardd" OR process == "amfid" '
        'OR process == "taskgated" OR process == "syspolicyd" '
        'OR process == "ReportCrash" OR process == "CrashReporterSupportHelper" '
        'OR eventMessage CONTAINS[c] "im.rime.inputmethod.Squirrel" '
        'OR eventMessage CONTAINS[c] "LaunchInputMethod" '
        'OR eventMessage CONTAINS[c] "IMKXPCEndpoint" '
        'OR eventMessage CONTAINS[c] "dyld")'
    )
    stream_stdout = stream_path.open("w")
    stream_stderr = stream_stderr_path.open("w")
    stream_started_at = shared.timestamp()
    stream_process = subprocess.Popen(
        [
            "/usr/bin/log",
            "stream",
            "--style",
            "ndjson",
            "--level",
            "debug",
            "--predicate",
            predicate,
        ],
        stdout=stream_stdout,
        stderr=stream_stderr,
        text=True,
    )
    time.sleep(0.5)

    stdout_handle = stdout_path.open("w")
    stderr_handle = stderr_path.open("w")
    launched_at = shared.timestamp()
    process = subprocess.Popen(
        [str(executable)],
        cwd=working_directory,
        stdout=stdout_handle,
        stderr=stderr_handle,
        text=True,
    )
    state_path = evidence / "installation-state.json"
    state = load_json(state_path, {})
    state["directLaunch"] = {
        "pid": process.pid,
        "executablePath": str(executable),
        "launchedAt": launched_at,
        "launchedByUID": os.getuid(),
        "arguments": [],
    }
    write_json(state_path, state)

    result: dict[str, Any] = {
        "startedAt": launched_at,
        "loggingStartedAt": stream_started_at,
        "loggingStartedBeforeLaunch": parse_timestamp(stream_started_at)
        <= parse_timestamp(launched_at),
        "deadlineSeconds": DIRECT_LAUNCH_DEADLINE_SECONDS,
        "launchMethod": "direct no-argument execution by the runner user",
        "runnerUID": os.getuid(),
        "runnerUser": os.environ.get("USER"),
        "executablePath": str(executable),
        "workingDirectory": str(working_directory),
        "pid": process.pid,
        "stdoutPath": stdout_path.name,
        "stderrPath": stderr_path.name,
        "streamLogPath": stream_path.name,
        "streamLogStderrPath": stream_stderr_path.name,
        "processTimelinePath": timeline_path.name,
        "diagnosticReportsBefore": reports_before,
    }
    deadline = time.monotonic() + DIRECT_LAUNCH_DEADLINE_SECONDS
    observations: list[dict[str, Any]] = []
    observed_endpoint_events: list[dict[str, Any]] = []
    while time.monotonic() < deadline:
        snapshot = exact_process_snapshot(process.pid, executable)
        snapshot["popenExitStatus"] = process.poll()
        observations.append(snapshot)
        with timeline_path.open("a") as timeline:
            timeline.write(json.dumps(snapshot, sort_keys=True) + "\n")
        observed_endpoint_events = endpoint_events(stream_path, process.pid)
        if process.poll() is not None or observed_endpoint_events:
            break
        time.sleep(0.25)

    readiness_completed_at = shared.timestamp()
    shown = capture_direct_log_show(
        evidence, launched_at, readiness_completed_at, process.pid
    )
    observed_endpoint_events = observed_endpoint_events or shown["endpointEvents"]
    natural_status = process.poll()
    result.update(
        {
            "readinessCompletedAt": readiness_completed_at,
            "readinessObservationCount": len(observations),
            "processAliveAtReadiness": natural_status is None,
            "naturalExitStatusAtReadiness": natural_status,
            "endpointObserved": bool(observed_endpoint_events),
            "endpointObservedAtReadiness": bool(observed_endpoint_events),
            "endpointEvents": observed_endpoint_events,
            "firstProcessSnapshot": observations[0] if observations else None,
            "lastProcessSnapshotAtReadiness": observations[-1] if observations else None,
        }
    )
    runtime = {
        "process": process,
        "streamProcess": stream_process,
        "stdoutHandle": stdout_handle,
        "stderrHandle": stderr_handle,
        "streamStdout": stream_stdout,
        "streamStderr": stream_stderr,
        "executable": executable,
    }
    write_json(evidence / "direct-launch.json", result)
    return result, runtime


def finish_direct_launch(
    evidence: pathlib.Path,
    result: dict[str, Any],
    runtime: dict[str, Any],
    composition: dict[str, Any] | None,
) -> dict[str, Any]:
    process: subprocess.Popen[str] = runtime["process"]
    executable: pathlib.Path = runtime["executable"]
    result["processBeforeExactCleanup"] = exact_process_snapshot(
        process.pid, executable
    )
    natural_status = process.poll()
    result["processAliveBeforeExactCleanup"] = natural_status is None
    result["naturalExitStatusBeforeExactCleanup"] = natural_status
    result["exactTerminationRequested"] = False
    result["exactForceTerminationRequested"] = False
    if natural_status is None:
        result["exactTerminationRequested"] = True
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            result["exactForceTerminationRequested"] = True
            process.kill()
            process.wait(timeout=3)
    result["finalExitStatus"] = process.returncode
    result["completedAt"] = shared.timestamp()
    result["processAfterExactCleanup"] = exact_process_snapshot(
        process.pid, executable
    )
    runtime["stdoutHandle"].close()
    runtime["stderrHandle"].close()

    time.sleep(0.5)
    stream_process: subprocess.Popen[str] = runtime["streamProcess"]
    stream_process.terminate()
    try:
        stream_process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        stream_process.kill()
        stream_process.wait(timeout=2)
    runtime["streamStdout"].close()
    runtime["streamStderr"].close()
    result["unifiedLogStreamExitStatus"] = stream_process.returncode
    shown = capture_direct_log_show(
        evidence,
        result["startedAt"],
        result["completedAt"],
        process.pid,
    )
    result["endpointEvents"] = shown["endpointEvents"] or result.get(
        "endpointEvents", []
    )
    result["endpointObserved"] = bool(result["endpointEvents"])

    before_paths = {
        item["path"] for item in result.get("diagnosticReportsBefore", [])
    }
    reports_after = diagnostic_reports()
    created_reports = [
        item for item in reports_after if item["path"] not in before_paths
    ]
    retained_reports: list[dict[str, Any]] = []
    for index, item in enumerate(created_reports, start=1):
        source = pathlib.Path(str(item["path"]))
        destination = evidence / f"direct-launch-crash-{index}{source.suffix}"
        try:
            with source.open("rb") as handle:
                destination.write_bytes(handle.read(1_048_576))
            retained_reports.append(
                {**item, "retainedPath": destination.name, "retainedByteLimit": 1_048_576}
            )
        except OSError as error:
            retained_reports.append({**item, "retentionError": str(error)})
    result["diagnosticReportsAfter"] = reports_after
    result["newDiagnosticReports"] = retained_reports

    composition_passed = bool(
        composition
        and composition.get("actualSelectionAndActivationProven") is True
    )
    endpoint_ready = result.get("endpointObservedAtReadiness") is True
    if not result.get("processAliveAtReadiness") and not endpoint_ready:
        classification = "process-exits-before-endpoint"
        earliest = "direct application process exit before endpoint registration"
    elif result.get("processAliveAtReadiness") and not endpoint_ready:
        classification = "process-lives-but-no-endpoint"
        earliest = "live direct application process without setIMKXPCEndpoint by the bounded deadline"
    elif not result.get("processAliveAtReadiness"):
        classification = "process-exits-after-endpoint-before-composition"
        earliest = "direct application process exit after endpoint registration"
    elif composition_passed and result.get("processAliveBeforeExactCleanup"):
        classification = "process-lives-endpoint-registers-composition-succeeds"
        earliest = "none observed through deterministic composition"
    else:
        classification = "process-lives-endpoint-registers-composition-fails"
        earliest = (
            "composition or process lifetime after a live process and endpoint registration"
        )
    result["outcome"] = {
        "classification": classification,
        "processExitedBeforeEndpoint": classification
        == "process-exits-before-endpoint",
        "processLivesButNoEndpoint": classification
        == "process-lives-but-no-endpoint",
        "processLivesPlusEndpointButCompositionFails": classification
        == "process-lives-endpoint-registers-composition-fails",
        "processLivesEndpointRegistersCompositionSucceeds": classification
        == "process-lives-endpoint-registers-composition-succeeds",
        "earliestObservedApplicationBoundary": earliest,
        "automaticLaunchServicesSessionResolutionIsolated": classification
        == "process-lives-endpoint-registers-composition-succeeds",
        "causalClaimLimit": (
            "Only a full direct-launch success isolates automatic LaunchServices/session resolution; all other outcomes report the earliest observed boundary without assigning root cause."
        ),
    }
    write_json(evidence / "direct-launch.json", result)
    return result


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
    result["logs"] = capture_tis_log_window(
        evidence,
        f"squirrel-composition-{name}",
        result["startedAt"],
        result["completedAt"],
    )
    result["boundedIMKLaunchEvidence"] = bounded_imk_log_evidence(
        evidence / result["logs"]["logPath"]
    )
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
            "same-session Dvorak public selection and physical-event control",
            "verified Squirrel registration, exact parent/mode enablement, and exact Allow action",
            "bounded unified logging started before direct no-argument executable launch",
            "exact direct PID lifetime and setIMKXPCEndpoint readiness",
            "exact Hans public selection and deterministic composition only after process-plus-endpoint readiness",
            "exact current-source, process, endpoint, composition, and cleanup evidence",
        ],
        "primaryCounterfactualCount": 1,
        "server": {},
    }
    appium_process = None
    appium_handle = None
    direct_runtime: dict[str, Any] | None = None
    direct_result: dict[str, Any] | None = None
    composition: dict[str, Any] | None = None
    direct_finish_attempted = False
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
        report["restoreOriginalAfterDvorakControl"] = native_transition(
            helper,
            evidence,
            "restore-original-after-dvorak-control",
            [
                "select",
                str(
                    nested(
                        initial,
                        "data",
                        "current",
                        "inputSourceID",
                        default=US_ID,
                    )
                ),
                str(
                    nested(
                        initial,
                        "data",
                        "current",
                        "type",
                        default=LAYOUT_TYPE,
                    )
                ),
                "-",
            ],
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

        direct_result, direct_runtime = start_direct_launch(evidence, installed_app)
        report["directLaunch"] = direct_result
        readiness = (
            direct_result.get("processAliveAtReadiness") is True
            and direct_result.get("endpointObserved") is True
        )
        if readiness:
            report["squirrelPublicSelection"] = native_transition(
                helper,
                evidence,
                "squirrel-public-selection-after-direct-readiness",
                ["select", MODE_ID, MODE_TYPE, PARENT_ID],
            )
            composition = squirrel_composition_proof(
                driver, helper, client_app, evidence, "direct-launch-public-api"
            )
            report["squirrelPublicComposition"] = composition
        else:
            current = source_snapshot(
                helper,
                evidence,
                "input-sources-after-direct-launch-not-ready.json",
                "after-direct-launch-readiness-failed-before-selection",
            )
            reason = (
                "The exact direct process exited before endpoint registration."
                if not direct_result.get("processAliveAtReadiness")
                else "The exact direct process lived but no setIMKXPCEndpoint was observed by the bounded deadline."
            )
            report["squirrelPublicSelection"] = {
                "attempted": False,
                "reason": reason,
                "currentSourceEvidence": current,
            }
            report["squirrelPublicComposition"] = {
                "attempted": False,
                "reason": reason,
                "currentSourceEvidence": current,
            }

        direct_finish_attempted = True
        direct_result = finish_direct_launch(
            evidence, direct_result, direct_runtime, composition
        )
        report["directLaunch"] = direct_result
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
        if (
            direct_runtime is not None
            and direct_result is not None
            and not direct_finish_attempted
        ):
            direct_finish_attempted = True
            try:
                direct_result = finish_direct_launch(
                    evidence, direct_result, direct_runtime, composition
                )
                report["directLaunch"] = direct_result
            except Exception as error:
                report["directLaunchCleanupError"] = {
                    "type": type(error).__name__,
                    "message": shared.bounded(str(error)),
                    "timestamp": shared.timestamp(),
                }
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
    direct = report.get("directLaunch", {})
    outcome = direct.get("outcome") or {
        "classification": "not-established",
        "earliestObservedApplicationBoundary": "experiment did not reach direct launch",
    }
    selection = nested(report, "squirrelPublicSelection", "data", default={})
    composition = report.get("squirrelPublicComposition", {})
    dvorak = nested(report, "dvorakPublicSelection", "data", default={})
    approval = report.get("systemSettingsApproval", {})
    approval_after = nested(
        approval,
        "sourceImmediatelyAfterAllow",
        "data",
        "prerequisites",
        "squirrelHans",
        default={},
    )
    final_current = nested(
        report,
        "finalSourcesBeforeCleanup",
        "data",
        "current",
        default={},
    )
    classification = outcome.get("classification", "not-established")
    conclusions = {
        "process-exits-before-endpoint": (
            "The exact direct Squirrel process exited before endpoint registration. The retained exit status, stdout/stderr, crash reports, process timeline, and security/dyld logs define the earliest observed application boundary; no deeper cause is asserted."
        ),
        "process-lives-but-no-endpoint": (
            "The exact direct Squirrel process remained alive but did not register setIMKXPCEndpoint by the bounded deadline. The earliest observed boundary is endpoint registration; no deeper cause is asserted."
        ),
        "process-lives-endpoint-registers-composition-fails": (
            "Direct Squirrel startup and endpoint registration succeeded, but exact-current Hans plus deterministic composition did not complete successfully. Automatic LaunchServices/session resolution is not claimed as the sole cause because composition still failed."
        ),
        "process-lives-endpoint-registers-composition-succeeds": (
            "The exact direct Squirrel process remained alive, registered setIMKXPCEndpoint, exact Hans became current, and physical n i h a o Space committed the expected text. This isolates the prior failure to automatic LaunchServices/session resolution rather than Squirrel startup or endpoint behavior, without choosing a more specific cause."
        ),
        "process-exits-after-endpoint-before-composition": (
            "The exact direct Squirrel process registered an endpoint and then exited before composition. The process exit is the earliest observed application boundary; no deeper cause is asserted."
        ),
    }
    return {
        "primaryCounterfactualCount": report.get("primaryCounterfactualCount"),
        "primaryCounterfactual": summary.get("smallestCounterfactual"),
        "outcome": outcome,
        "conclusion": conclusions.get(
            classification,
            "The direct-launch outcome was not established; no causal claim is made.",
        ),
        "directApplicationBoundary": {
            "exactExecutablePath": direct.get("executablePath"),
            "runnerUID": direct.get("runnerUID"),
            "pid": direct.get("pid"),
            "loggingStartedBeforeLaunch": direct.get("loggingStartedBeforeLaunch"),
            "processAliveAtReadiness": direct.get("processAliveAtReadiness"),
            "naturalExitStatusAtReadiness": direct.get(
                "naturalExitStatusAtReadiness"
            ),
            "naturalExitStatusBeforeExactCleanup": direct.get(
                "naturalExitStatusBeforeExactCleanup"
            ),
            "finalExitStatusAfterExactCleanup": direct.get("finalExitStatus"),
            "endpointObservedAtReadiness": direct.get(
                "endpointObservedAtReadiness"
            ),
            "endpointObservedInFullWindow": direct.get("endpointObserved"),
            "endpointEvents": direct.get("endpointEvents", []),
            "newDiagnosticReports": direct.get("newDiagnosticReports", []),
            "stdoutPath": direct.get("stdoutPath"),
            "stderrPath": direct.get("stderrPath"),
            "processTimelinePath": direct.get("processTimelinePath"),
            "unifiedLogPaths": [
                direct.get("streamLogPath"),
                "direct-launch-log-show.jsonl",
                "system-log.jsonl",
            ],
        },
        "verifiedSetupSequence": {
            "exactAllowActionProven": (
                approval.get("semanticAllowVerified") is True
                and approval.get("allowClicked") is True
            ),
            "allSelectionPrerequisitesTrueAfterAllow": approval_after.get(
                "allDocumentedSelectionPrerequisitesSatisfied"
            )
            is True,
            "packagePostinstallExecuted": False,
            "privateDatabaseEdited": False,
        },
        "exactSourceAndComposition": {
            "selectionAttempted": report.get("squirrelPublicSelection", {}).get(
                "attempted", True
            ),
            "selectionStatus": selection.get("status"),
            "selectionVerified": selection.get("selectionVerified") is True,
            "finalCurrentSource": final_current,
            "compositionAttempted": composition.get("attempted") is True,
            "markedCompositionObserved": composition.get(
                "markedCompositionObserved"
            ),
            "committedTextScalars": nested(
                composition,
                "finalClientDiagnostics",
                "textScalars",
                default=[],
            ),
            "expectedTextScalars": EXPECTED_SCALARS,
            "compositionPassed": composition.get(
                "actualSelectionAndActivationProven"
            )
            is True,
        },
        "sameSessionDvorakControl": {
            "publicStatus": dvorak.get("status"),
            "publicSelectionVerified": dvorak.get("selectionVerified") is True,
            "physicalKeyCode37ProducedN": nested(
                report, "dvorakPublicKeyProof", "passed"
            )
            is True,
            "role": "selection, focus, and physical-event control only",
        },
        "evidenceBoundaries": {
            "currentSourceRetained": True,
            "compositionOutcomeRetained": True,
            "markedAndCommittedTextRetainedWhenAttempted": composition.get(
                "attempted"
            )
            is True,
            "endpointRetained": True,
            "processBirthAndLifetimeRetained": True,
            "stdoutStderrAndExitStatusRetained": True,
            "crashDyldSecurityLaunchServicesRunningBoardIMKLogsRetained": True,
            "cleanupRetained": True,
        },
        "causalClaimLimit": (
            "Only direct process, endpoint, and composition success isolates automatic LaunchServices/session resolution. Any exit, no-endpoint, or composition failure reports the earliest observed boundary without assigning a deeper cause."
        ),
        "privatePolicyExplanationAsserted": False,
        "scopeLimit": (
            "One Squirrel direct-launch counterfactual only; no installer scripts, system installation, private database edits, security weakening, second product, or persistent infrastructure."
        ),
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
