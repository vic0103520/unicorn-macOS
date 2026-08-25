#!/usr/bin/env python3
"""Bounded hosted ARM64 control using the official Rime Squirrel release."""

from __future__ import annotations

import argparse
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

SCHEMA_VERSION = 1
BUNDLE_ID = "im.rime.inputmethod.Squirrel"
MODE_ID = "im.rime.inputmethod.Squirrel.Hans"
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
BUILTIN_RUN_URL = "https://github.com/vic0103520/unicorn-macOS/actions/runs/32820366744"
UNICORN_RUN_URL = "https://github.com/vic0103520/unicorn-macOS/actions/runs/32818022996"


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
    installation_state = {
        "schemaVersion": SCHEMA_VERSION,
        "createdAt": shared.timestamp(),
        "selectionStarted": False,
        "trackedPaths": [
            {"path": str(path), "existedBefore": path.exists()}
            for path in tracked_paths
        ],
    }
    write_json(evidence / "installation-state.json", installation_state)

    summary = {
        "schemaVersion": SCHEMA_VERSION,
        "probe": "github-hosted-arm64-macos-third-party-inputmethod-control",
        "status": "running",
        "startedAt": shared.timestamp(),
        "actionsRunURL": github_run_url(),
        "boundedScope": {
            "thirdPartyProductCount": 1,
            "product": "Rime Squirrel",
            "release": RELEASE_TAG,
            "runnerLabel": "macos-15",
            "expectedArchitecture": "arm64",
            "screenshotsAndVideoAreDiagnosticOnly": True,
            "passFailUsesScreenshotPixels": False,
        },
        "productSelection": {
            "name": "Rime Squirrel",
            "sourceRepository": SOURCE_URL,
            "officialRelease": RELEASE_URL,
            "releaseCommit": RELEASE_COMMIT,
            "stableRelease": True,
            "openSource": True,
            "inputMethodKitFrontend": True,
            "appleSiliconEvidenceRequired": "arm64 slice in the signed release app",
        },
        "assertion": {
            "inputModeID": MODE_ID,
            "physicalKeys": ["n", "i", "h", "a", "o", "space"],
            "expectedCommittedText": EXPECTED_TEXT,
            "expectedTextScalars": EXPECTED_SCALARS,
            "compositionMustEnd": True,
            "reason": "The clean official release defaults to Luna Pinyin; nihao plus Space should commit its first candidate.",
        },
        "fixedPriorEvidence": {
            "builtIn": {
                "runURL": BUILTIN_RUN_URL,
                "target": "com.apple.keylayout.Dvorak",
                "enableStatus": 0,
                "selectionStatus": 0,
                "selected": True,
                "physicalKeyCode37CommittedText": "n",
            },
            "disposableUnicorn": {
                "runURL": UNICORN_RUN_URL,
                "registrationStatus": 0,
                "discovered": True,
                "enableStatus": 0,
                "systemSettingsAllowClicked": True,
                "selectionStatus": -50,
                "selected": False,
                "imkProcessObserved": False,
                "hardwareStyleTextScalars": ["U+005C", "U+006C", "U+000A"],
            },
        },
        "causalTerms": {
            "initiatingTrigger": "TISEnableInputSource after TISRegisterInputSource starts the System Settings third-party input-source consent path; the live helper then retries TISSelectInputSource.",
            "maskingCondition": "Registration, discovery, an Allow click, or Appium text injection can look successful without selecting or traversing InputMethodKit. Selection identifiers, live process evidence, CGEvent delivery, and client diagnostics are evaluated independently.",
            "visibleSymptom": "pending experiment",
        },
        "smallestCounterfactual": {
            "changedVariable": "Replace only the disposable ad hoc Unicorn input-method target with one official Developer ID signed and notarized known-working Squirrel release while retaining macos-15, the Aqua user, public TIS APIs, System Settings Accessibility automation, the test client, and hardware-style CGEvents.",
            "leadingExplanationBeforeRun": "A general GitHub-hosted restriction may prevent any third-party input method from passing approval and selection.",
            "disconfirmingEvidenceSought": "A zero TISSelectInputSource result with Squirrel selected, followed by Squirrel process launch and deterministic composition, would disprove a general third-party hosted-runner prohibition.",
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
    write_json(evidence / "summary.json", summary)


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
    results = {name: shared.run_command(command) for name, command in commands.items()}
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
    results["initialSources"] = shared.run_command(
        [str(helper), "sources", str(evidence / "input-sources-initial.json")],
        timeout=30,
    )
    write_json(evidence / "environment.json", results)

    summary = load_json(evidence / "summary.json", {})
    summary["environment"] = {
        "architecture": results["architecture"].get("stdout", "").strip(),
        "runnerArchitecture": os.environ.get("RUNNER_ARCH"),
        "aquaSession": load_json(evidence / "aqua-session.json", {}),
        "windowServerExitCode": results["windowServer"].get("exitCode"),
        "aquaLaunchDomainExitCode": results["aquaLaunchDomain"].get("exitCode"),
        "automationModeEnableExitCode": results["automationModeEnable"].get("exitCode"),
    }
    write_json(evidence / "summary.json", summary)


def sha256(path: pathlib.Path) -> str:
    import hashlib

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
        "appGatekeeper": ["spctl", "--assess", "--type", "execute", "--verbose=4", str(app)],
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
        "packageDeveloperIDInstaller": "Developer ID Installer: Yuncao Liu (28HU5A7B46)" in package_signature_output,
        "packageNotarizationTrusted": "trusted by the Apple notary service" in package_signature_output,
        "appDeveloperIDApplication": "Developer ID Application: Yuncao Liu (28HU5A7B46)" in app_signature_output,
        "appTeamIdentifierMatches": "TeamIdentifier=28HU5A7B46" in app_signature_output,
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


def source_snapshot(
    helper: pathlib.Path, evidence: pathlib.Path, filename: str
) -> dict[str, Any]:
    path = evidence / filename
    command = shared.run_command([str(helper), "sources", str(path)], timeout=30)
    data = load_json(path, {})
    return {
        "command": command,
        "data": data,
        "target": next(
            (
                source
                for source in data.get("sources", [])
                if source.get("bundleID") == BUNDLE_ID
                and (
                    source.get("inputModeID") == MODE_ID
                    or source.get("inputSourceID") == MODE_ID
                )
            ),
            {"present": False},
        ),
    }


def selected(snapshot: dict[str, Any]) -> bool:
    current = snapshot.get("data", {}).get("current", {})
    return current.get("bundleID") == BUNDLE_ID and (
        current.get("inputModeID") == MODE_ID
        or current.get("inputSourceID") == MODE_ID
        or str(current.get("inputSourceID", "")).endswith(".Hans")
    )


def semantic_element(
    driver: Any, session_id: str, element_id: str
) -> dict[str, Any]:
    names = (
        "identifier",
        "label",
        "title",
        "value",
        "enabled",
        "hittable",
        "elementType",
        "frame",
    )
    return {
        name: shared.attribute(driver, session_id, element_id, name)
        for name in names
    }


def truthy(value: Any) -> bool:
    return value is True or str(value).lower() == "true"


def approve_system_settings(
    driver: Any, helper: pathlib.Path, evidence: pathlib.Path
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "attempted": True,
        "startedAt": shared.timestamp(),
        "method": "Appium Mac2 Accessibility tree",
        "screenshotsDiagnosticOnly": True,
    }
    session_id: str | None = None
    try:
        session_id, response = shared.create_bundle_session(
            driver,
            "com.apple.systempreferences",
            {"appium:noReset": True},
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
            raise RuntimeError(f"Refusing to click non-matching consent control: {semantic}")
        driver.request(
            "POST", f"/session/{session_id}/element/{allow_element}/click", {}
        )
        result["allowClicked"] = True
        time.sleep(1.0)
        result["diagnosticScreenshotAfter"] = shared.save_screenshot(
            driver, session_id, evidence / "system-settings-consent-after.png"
        )
    except Exception as error:
        result["error"] = {
            "type": type(error).__name__,
            "message": shared.bounded(str(error)),
        }
    finally:
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                result.setdefault("session", {})["deleted"] = True
            except Exception as error:
                result.setdefault("session", {})["deleteError"] = shared.bounded(
                    str(error)
                )

    observation: dict[str, Any] = {}
    for attempt in range(1, 61):
        observation = source_snapshot(
            helper, evidence, "input-sources-after-approval.json"
        )
        if selected(observation):
            break
        time.sleep(0.5)
    result["selectionObservation"] = {
        "attempts": attempt,
        "selected": selected(observation),
        "current": observation.get("data", {}).get("current"),
        "target": observation.get("target"),
        "fullEvidencePath": "input-sources-after-approval.json",
    }
    result["completedAt"] = shared.timestamp()
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


def exact_text_assertion(diagnostics: dict[str, Any]) -> dict[str, Any]:
    marked = diagnostics.get("markedRange") or {}
    composition_ended = (
        diagnostics.get("hasMarkedText") is False and marked.get("length") == 0
    )
    scalars = diagnostics.get("textScalars")
    passed = scalars == EXPECTED_SCALARS and composition_ended
    return {
        "expectedText": EXPECTED_TEXT,
        "expectedTextScalars": EXPECTED_SCALARS,
        "actualText": diagnostics.get("text"),
        "actualTextScalars": scalars,
        "hasMarkedText": diagnostics.get("hasMarkedText"),
        "markedRange": marked,
        "compositionEnded": composition_ended,
        "passed": passed,
    }


def run_control(
    evidence: pathlib.Path,
    helper: pathlib.Path,
    client_app: pathlib.Path,
) -> int:
    transcript = evidence / "webdriver-transcript.jsonl"
    appium_log = evidence / "appium.log"
    appium_handle = appium_log.open("w")
    appium_process: subprocess.Popen[str] | None = None
    driver = shared.WebDriver("http://127.0.0.1:4723", transcript)
    client_session: str | None = None
    report: dict[str, Any] = {
        "startedAt": shared.timestamp(),
        "server": {},
        "systemSettingsApproval": {"attempted": False},
        "typedComposition": {"attempted": False},
    }
    completed = False

    try:
        appium_process = subprocess.Popen(
            ["appium", "--base-path", "/", "--log-no-colors", "--log-timestamp"],
            stdout=appium_handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
        report["server"]["pid"] = appium_process.pid
        report["server"]["readiness"] = shared.wait_for_server(driver)
        if not report["server"]["readiness"].get("ready"):
            raise RuntimeError("Appium server did not become ready")

        before_approval = source_snapshot(
            helper, evidence, "input-sources-before-approval.json"
        )
        report["registrationAndDiscovery"] = {
            "current": before_approval.get("data", {}).get("current"),
            "sourceCount": before_approval.get("data", {}).get("sourceCount"),
            "target": before_approval.get("target"),
            "fullEvidencePath": "input-sources-before-approval.json",
        }
        report["systemSettingsApproval"] = approve_system_settings(
            driver, helper, evidence
        )

        delivery_source = source_snapshot(
            helper, evidence, "input-sources-at-delivery.json"
        )
        report["sourceAtDelivery"] = {
            "selected": selected(delivery_source),
            "current": delivery_source.get("data", {}).get("current"),
            "target": delivery_source.get("target"),
            "fullEvidencePath": "input-sources-at-delivery.json",
        }

        diagnostics = evidence / "client-current.json"
        timeline = evidence / "client-timeline.jsonl"
        client_session, session_response = shared.create_session(
            driver, client_app, diagnostics, timeline
        )
        report["clientSession"] = {
            "created": True,
            "sessionID": client_session,
            "response": session_response,
        }
        element = shared.find_text_view(driver, client_session)
        focus = shared.focus_text_view(
            driver, client_session, element, diagnostics
        )
        report["clientFocus"] = focus
        if not focus.get("success"):
            raise RuntimeError("Mac2 could not focus the native test text view")

        report["diagnosticScreenshotBeforeKeys"] = shared.save_screenshot(
            driver, client_session, evidence / "before-keys.png"
        )
        report["processBeforeKeys"] = process_snapshot()
        key_specs = [
            (45, "n"),
            (34, "i"),
            (4, "h"),
            (0, "a"),
            (31, "o"),
            (49, "space"),
        ]
        key_results: list[dict[str, Any]] = []
        for index, (key_code, label) in enumerate(key_specs, start=1):
            key_path = evidence / f"key-{index}-{label}.json"
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
            time.sleep(0.6)
            key_results.append(
                {
                    "index": index,
                    "label": label,
                    "keyCode": key_code,
                    "command": command,
                    "event": load_json(key_path, {}),
                    "clientDiagnosticsAfter": shared.diagnostics_snapshot(diagnostics),
                    "processAfter": process_snapshot(),
                }
            )
        time.sleep(1.0)

        final_diagnostics = shared.diagnostics_snapshot(diagnostics)
        timeline = timeline_entries(timeline)
        marked_entries = [entry for entry in timeline if entry.get("hasMarkedText") is True]
        process_observed = report["processBeforeKeys"].get("processCount", 0) > 0 or any(
            item["processAfter"].get("processCount", 0) > 0
            for item in key_results
        )
        assertion = exact_text_assertion(final_diagnostics)
        report["typedComposition"] = {
            "attempted": True,
            "deliveryMechanism": "CGEvent at cghidEventTap",
            "keys": key_results,
            "finalClientDiagnostics": final_diagnostics,
            "timelineEntryCount": len(timeline),
            "markedCompositionObserved": bool(marked_entries),
            "markedCompositionSamples": marked_entries[:8],
            "exactTextAssertion": assertion,
            "processObserved": process_observed,
            "strongestIndependentActivationEvidence": (
                "Selected Squirrel source, a live signed Squirrel process, and marked-text transitions"
                if report["sourceAtDelivery"]["selected"]
                and process_observed
                and marked_entries
                else None
            ),
            "independentEvidenceIsNotEquivalentToExactTextAssertion": not assertion["passed"],
        }
        report["diagnosticScreenshotAfterKeys"] = shared.save_screenshot(
            driver, client_session, evidence / "after-keys.png"
        )
        completed = True
    except Exception as error:
        report["error"] = {
            "type": type(error).__name__,
            "message": shared.bounded(str(error)),
            "timestamp": shared.timestamp(),
        }
    finally:
        if client_session:
            try:
                driver.request("DELETE", f"/session/{client_session}", timeout=30)
                report.setdefault("clientSession", {})["deleted"] = True
            except Exception as error:
                report.setdefault("clientSession", {})["deleteError"] = shared.bounded(
                    str(error)
                )
        if appium_process:
            appium_process.terminate()
            try:
                appium_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                appium_process.kill()
                appium_process.wait(timeout=5)
            report["server"]["exitCode"] = appium_process.returncode
        appium_handle.close()

    report["completedAt"] = shared.timestamp()
    report["executionCompleted"] = completed
    write_json(evidence / "control-experiment.json", report)
    summary = load_json(evidence / "summary.json", {})
    summary["controlExperiment"] = report
    if not completed:
        summary["status"] = "execution-failed"
    write_json(evidence / "summary.json", summary)
    return 0 if completed else 3


def incorporate_selection(evidence: pathlib.Path) -> None:
    selection = load_json(evidence / "input-source-selection.json", {})
    summary = load_json(evidence / "summary.json", {})
    summary["tisRegistrationAndSelection"] = {
        "registrationStatus": selection.get("registrationStatus"),
        "discoveryAttempts": selection.get("discoveryAttempts"),
        "targetAtDiscovery": selection.get("targetAtDiscovery"),
        "enableStatus": selection.get("enableStatus"),
        "expectedSelectedInputSourceID": selection.get(
            "expectedSelectedInputSourceID"
        ),
        "selectionAttemptCount": len(selection.get("selectionAttempts", [])),
        "selectionStatuses": [
            attempt.get("selectionStatus")
            for attempt in selection.get("selectionAttempts", [])
        ],
        "finalSelectionStatus": selection.get("finalSelectionStatus"),
        "selectedSource": selection.get("selectedSource"),
        "selectionVerified": selection.get("selectionVerified", False),
        "fullEvidencePath": "input-source-selection.json",
    }
    write_json(evidence / "summary.json", summary)


def finalize(evidence: pathlib.Path, producer_status: int) -> None:
    summary = load_json(evidence / "summary.json", {})
    selection = load_json(evidence / "input-source-selection.json", {})
    control = load_json(evidence / "control-experiment.json", {})
    approval = load_json(evidence / "system-settings-approval.json", {})
    cleanup = load_json(evidence / "cleanup.json", {})
    provenance_data = load_json(evidence / "provenance.json", {})
    process_before_registration = load_json(
        evidence / "process-after-build-before-registration.json", {}
    )

    typed = control.get("typedComposition", {})
    exact = typed.get("exactTextAssertion", {})
    source_selected = bool(selection.get("selectionVerified"))
    process_observed = bool(typed.get("processObserved"))
    marked_observed = bool(typed.get("markedCompositionObserved"))
    exact_passed = bool(exact.get("passed"))
    approval_proven = bool(
        approval.get("semanticAllowVerified") and approval.get("allowClicked")
    )
    activation_proven = source_selected and process_observed and exact_passed
    independent_activation = source_selected and process_observed and marked_observed

    registration_status = selection.get("registrationStatus")
    selection_status = selection.get("finalSelectionStatus")
    if registration_status != 0:
        earliest = "registration: Squirrel diverged before the disposable Unicorn, whose registration returned 0"
        leading = "The control did not reach the prior selection boundary, so no runner-versus-Unicorn diagnosis is supported."
        visible = f"Squirrel registration returned {registration_status}."
    elif source_selected:
        earliest = "selection: built-in Dvorak and Squirrel returned 0 and became current; disposable Unicorn returned -50 and remained on U.S."
        leading = "A general hosted-runner prohibition on third-party input methods is disproved. The failure is specific to the disposable Unicorn probe or a condition it uniquely introduces, but this experiment does not identify which one."
        visible = (
            f"Squirrel became current with TISSelectInputSource={selection_status}; "
            f"processObserved={process_observed}, exactComposition={exact_passed}."
        )
    else:
        earliest = "selection: built-in Dvorak became current with status 0; Squirrel and disposable Unicorn did not become current"
        leading = "The result remains consistent with a hosted-runner restriction on third-party input-source approval or selection, rather than a defect unique to disposable Unicorn."
        visible = (
            f"Squirrel was registered and discovered but remained unselected; "
            f"final TISSelectInputSource={selection_status}, current source="
            f"{(selection.get('selectedSource') or {}).get('inputSourceID')}."
        )

    summary["completedAt"] = shared.timestamp()
    summary["producerExitCode"] = producer_status
    summary["actionsRunURL"] = github_run_url() or summary.get("actionsRunURL")
    summary["systemSettingsApproval"] = {
        "attempted": approval.get("attempted", False),
        "semanticAllowVerified": approval.get("semanticAllowVerified", False),
        "allowClicked": approval.get("allowClicked", False),
        "approvalProvenThroughAccessibility": approval_proven,
        "selectionObservedAfterApproval": approval.get(
            "selectionObservation", {}
        ).get("selected", False),
        "fullEvidencePath": "system-settings-approval.json",
    }
    summary["activationEvidence"] = {
        "sourceSelected": source_selected,
        "selectedSource": selection.get("selectedSource"),
        "tisSelectInputSourceReturnValue": selection_status,
        "processAbsentAfterBuildBeforeRegistration": process_before_registration.get(
            "processAbsent", False
        ),
        "processObserved": process_observed,
        "markedCompositionObserved": marked_observed,
        "exactTextAssertionPassed": exact_passed,
        "actualText": exact.get("actualText"),
        "actualTextScalars": exact.get("actualTextScalars"),
        "actualActivationProven": activation_proven,
        "strongIndependentActivationEvidence": independent_activation,
        "independentEvidenceEquivalentToDeterministicTextProof": (
            independent_activation and exact_passed
        ),
        "qualification": (
            None
            if exact_passed
            else "Marked text and process evidence, if present, are retained as independent activation evidence and are not called equivalent to the deterministic committed-text assertion."
        ),
    }
    summary["comparison"] = {
        "stageOrder": [
            "registration and discovery",
            "System Settings approval",
            "TIS selection",
            "IMK process launch",
            "hardware-style composition",
        ],
        "builtIn": summary.get("fixedPriorEvidence", {}).get("builtIn"),
        "thirdPartySquirrel": {
            "registrationStatus": registration_status,
            "discovered": bool(selection.get("targetAtDiscovery", {}).get("present")),
            "systemSettingsApprovalProven": approval_proven,
            "selectionStatus": selection_status,
            "selected": source_selected,
            "processObserved": process_observed,
            "markedCompositionObserved": marked_observed,
            "exactCompositionPassed": exact_passed,
        },
        "disposableUnicorn": summary.get("fixedPriorEvidence", {}).get(
            "disposableUnicorn"
        ),
        "earliestDivergence": earliest,
    }
    summary["causalTerms"] = {
        "initiatingTrigger": summary.get("causalTerms", {}).get(
            "initiatingTrigger"
        ),
        "maskingCondition": summary.get("causalTerms", {}).get("maskingCondition"),
        "visibleSymptom": visible,
    }
    summary["diagnosis"] = {
        "leadingExplanation": leading,
        "smallestCounterfactual": summary.get("smallestCounterfactual", {}).get(
            "changedVariable"
        ),
        "evidenceThatCouldDisproveLeadingExplanation": (
            "If Squirrel had reproduced Unicorn's -50 result and stayed on U.S., that would have falsified the product-specific explanation."
            if source_selected
            else "A selected Squirrel identifier, a live Squirrel IMK process, or marked/committed Squirrel composition would disprove the leading general-restriction explanation; none is treated as present unless recorded independently."
        ),
        "scopeLimit": "This diagnosis is evidence only and does not authorize product, security, runner, or infrastructure changes.",
    }
    summary["cleanup"] = cleanup
    summary["cleanupPassed"] = bool(cleanup.get("success"))
    summary["experimentExecutionCompleted"] = bool(
        control.get("executionCompleted")
    )
    summary["provenancePassed"] = bool(
        provenance_data.get("allRequiredVerificationPassed")
    )
    summary["boundedExperimentCompleted"] = (
        producer_status == 0
        and summary["experimentExecutionCompleted"]
        and summary["provenancePassed"]
        and summary["cleanupPassed"]
    )
    summary["controlResult"] = (
        "third-party activation proven"
        if activation_proven
        else (
            "third-party activation independently observed but deterministic text assertion not proven"
            if independent_activation
            else "third-party activation not proven"
        )
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

    selection_parser = commands.add_parser("incorporate-selection")
    selection_parser.add_argument("evidence", type=pathlib.Path)

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
        return run_control(arguments.evidence, arguments.helper, arguments.client_app)
    if arguments.command == "incorporate-selection":
        incorporate_selection(arguments.evidence)
        return 0
    if arguments.command == "finalize":
        finalize(arguments.evidence, arguments.producer_status)
        return 0
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
