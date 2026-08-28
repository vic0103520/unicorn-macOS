#!/usr/bin/env python3
"""Bounded hosted automatic-activation experiment for the exact Unicorn build."""

from __future__ import annotations

import argparse
import datetime as dt
import grp
import hashlib
import importlib.util
import json
import os
import pathlib
import plistlib
import pwd
import shutil
import stat
import subprocess
import time
from typing import Any

SHARED_PATH = pathlib.Path(__file__).parents[1] / "HostedIMKProbe" / "probe.py"
SHARED_SPEC = importlib.util.spec_from_file_location("hosted_imk_shared", SHARED_PATH)
if SHARED_SPEC is None or SHARED_SPEC.loader is None:
    raise RuntimeError(f"Unable to import shared probe support from {SHARED_PATH}")
shared = importlib.util.module_from_spec(SHARED_SPEC)
SHARED_SPEC.loader.exec_module(shared)

BUNDLE_ID = "Vic-Shih.inputmethod.unicorn"
DECLARED_MODE_ID = "Vic-Shih.inputmethod.unicorn"
TARGET_SOURCE_ID = "Vic-Shih.inputmethod.unicorn.unicorn"
EXECUTABLE_NAME = "unicorn"
DVORAK_ID = "com.apple.keylayout.Dvorak"
US_ID = "com.apple.keylayout.US"
LAYOUT_TYPE = "TISTypeKeyboardLayout"
EXPECTED_TEXT = "λ"
EXPECTED_SCALARS = ["U+03BB"]
AUTOMATIC_DEADLINE_SECONDS = 15
EXPERIMENT = "unicorn-supported-installer"


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


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def initialize(evidence: pathlib.Path, installed_app: pathlib.Path) -> None:
    evidence.mkdir(parents=True, exist_ok=True)
    home = pathlib.Path.home()
    tracked_paths = [
        installed_app,
        home / "Library" / "Containers" / BUNDLE_ID,
        home / "Library" / "Preferences" / f"{BUNDLE_ID}.plist",
        home / "Library" / "Caches" / BUNDLE_ID,
        home / "Library" / "Application Support" / "Unicorn",
    ]
    write_json(
        evidence / "installation-state.json",
        {
            "schemaVersion": 1,
            "createdAt": shared.timestamp(),
            "experiment": EXPERIMENT,
            "selectionStarted": False,
            "initialCurrentSourceID": None,
            "initialCurrentSourceType": None,
            "initialUnicornSources": [],
            "automaticProcess": None,
            "trackedPaths": [
                {"path": str(path), "existedBefore": path.exists()}
                for path in tracked_paths
            ],
        },
    )
    write_json(
        evidence / "summary.json",
        {
            "schemaVersion": 1,
            "probe": "github-hosted-arm64-unicorn-automatic-activation",
            "experiment": EXPERIMENT,
            "status": "running",
            "startedAt": shared.timestamp(),
            "actionsRunURL": github_run_url(),
            "exactRevision": os.environ.get("GITHUB_SHA"),
            "intendedSourceIdentity": {
                "bundleID": BUNDLE_ID,
                "parentSourceID": BUNDLE_ID,
                "declaredModeID": DECLARED_MODE_ID,
                "selectableSourceID": TARGET_SOURCE_ID,
            },
            "assertions": {
                "composition": {
                    "physicalKeys": ["backslash", "l", "enter"],
                    "keyCodes": [42, 37, 36],
                    "expectedCommittedText": EXPECTED_TEXT,
                    "expectedTextScalars": EXPECTED_SCALARS,
                    "markedTextMustAppear": True,
                    "compositionMustEnd": True,
                },
                "automaticActivation": {
                    "directExecutableLaunchPerformed": False,
                    "exactProcessMustStart": True,
                    "exactExecutableIdentityMustMatch": True,
                    "processMustRemainAliveThroughComposition": True,
                    "correlatedIMKEndpointMustAppear": True,
                    "exactSourceMustBeCurrent": True,
                },
            },
            "treatment": {
                "name": "checked-in supported Unicorn installer plus public TIS convergence",
                "installerPath": "install.sh",
                "installationLocation": str(installed_app),
                "registration": [
                    "the installer's exact-app LaunchServices registration",
                    "public TISRegisterInputSource for the exact installed app",
                ],
                "enablement": "public TISEnableInputSource for exact enumerated parent and target sources",
                "approval": "exact semantic System Settings Allow action if required",
                "selection": "public TISSelectInputSource for exact source Vic-Shih.inputmethod.unicorn.unicorn with declared mode Vic-Shih.inputmethod.unicorn",
                "activation": "focused AppKit client plus physical backslash-l-enter input",
            },
            "boundedScope": {
                "runnerLabel": "macos-15",
                "expectedArchitecture": "arm64",
                "sameLoggedInAquaUserRequired": True,
                "directExecutableLaunchPerformed": False,
                "privateDatabaseEdited": False,
                "securityWeakened": False,
                "broadServiceRestarted": False,
                "persistentInfrastructureUsed": False,
                "tartUsed": False,
                "screenshotsDiagnosticOnly": True,
                "passFailUsesOCRPixelsOrCoordinates": False,
            },
            "squirrelObservedSufficientTreatment": {
                "runURL": "https://github.com/vic0103520/unicorn-macOS/actions/runs/33147470444",
                "observedBoundary": "official package installation into /Library/Input Methods followed by exact registration, parent and mode enablement, semantic Allow, exact mode selection, and AppKit client input automatically started Squirrel and completed deterministic composition",
                "causalLimit": "Squirrel success proves that combined treatment sufficient for Squirrel. It does not identify which installer side effect is individually necessary for Unicorn.",
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


def current_id(snapshot: dict[str, Any]) -> str | None:
    data = snapshot.get("data", snapshot)
    return data.get("current", {}).get("inputSourceID")


def current_bundle(snapshot: dict[str, Any]) -> str | None:
    data = snapshot.get("data", snapshot)
    return data.get("current", {}).get("bundleID")


def preflight(evidence: pathlib.Path, helper: pathlib.Path) -> None:
    uid = os.getuid()
    commands = {
        "architecture": ["uname", "-m"],
        "systemVersion": ["sw_vers"],
        "identity": ["id"],
        "processUser": ["id", "-un"],
        "loggedInUsers": ["who"],
        "consoleUser": ["stat", "-f", "%Su", "/dev/console"],
        "windowServer": ["pgrep", "-alf", "WindowServer"],
        "aquaLaunchDomain": ["launchctl", "print", f"gui/{uid}"],
        "xcodeVersion": ["xcodebuild", "-version"],
        "developerSecurity": ["DevToolsSecurity", "-status"],
        "automationModeBefore": ["automationmodetool"],
        "unicornProcessBefore": ["pgrep", "-x", EXECUTABLE_NAME],
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
    results["nativeSessionProbe"] = shared.run_command(
        [str(helper), "session", str(evidence / "aqua-session.json")]
    )
    initial = source_snapshot(
        helper, evidence, "input-sources-initial.json", "fresh-runner-initial"
    )
    results["initialInputSources"] = initial["command"]
    write_json(evidence / "environment.json", results)

    aqua = load_json(evidence / "aqua-session.json", {})
    architecture = results["architecture"].get("stdout", "").strip()
    process_user = results["processUser"].get("stdout", "").strip()
    console_user = results["consoleUser"].get("stdout", "").strip()
    initial_sources = [
        source
        for source in initial["data"].get("sources", [])
        if source.get("bundleID") == BUNDLE_ID
    ]
    state_path = evidence / "installation-state.json"
    state = load_json(state_path, {})
    current = initial["data"].get("current", {})
    state.update(
        {
            "initialCurrentSourceID": current.get("inputSourceID"),
            "initialCurrentSourceType": current.get("type"),
            "initialUnicornSources": initial_sources,
            "dvorakInitiallyEnabled": next(
                (
                    source.get("enabled") is True
                    for source in initial["data"].get("sources", [])
                    if source.get("inputSourceID") == DVORAK_ID
                ),
                False,
            ),
        }
    )
    write_json(state_path, state)
    checks = {
        "architectureIsArm64": architecture == "arm64",
        "runnerArchitectureIsARM64": os.environ.get("RUNNER_ARCH") == "ARM64",
        "sameProcessAndConsoleUser": process_user == console_user == aqua.get("processUser") == aqua.get("consoleUser"),
        "uidMatchesAquaSession": aqua.get("uid") == uid,
        "aquaSessionPresent": aqua.get("hasAquaSessionDictionary") is True,
        "screenPresent": aqua.get("screenCount", 0) > 0,
        "accessibilityTrusted": aqua.get("accessibilityTrusted") is True,
        "cgEventPostingAllowed": aqua.get("cgEventPostPreflight") is True,
        "guiBootstrapDomainPresent": results["aquaLaunchDomain"].get("exitCode") == 0,
        "windowServerPresent": results["windowServer"].get("exitCode") == 0,
        "noPreexistingUnicornProcess": results["unicornProcessBefore"].get("exitCode") == 1,
        "noPreexistingUnicornSources": not initial_sources,
        "noTrackedPathPreexisted": not any(
            item.get("existedBefore") for item in state.get("trackedPaths", [])
        ),
    }
    write_json(evidence / "preflight-checks.json", checks)
    summary = load_json(evidence / "summary.json", {})
    summary["environment"] = {
        "architecture": architecture,
        "runnerArchitecture": os.environ.get("RUNNER_ARCH"),
        "uid": uid,
        "processUser": process_user,
        "consoleUser": console_user,
        "aquaSession": aqua,
        "checks": checks,
    }
    write_json(evidence / "summary.json", summary)
    if not all(checks.values()):
        raise RuntimeError(f"Fresh hosted Aqua preflight failed: {checks}")


def plist_value(app: pathlib.Path) -> dict[str, Any]:
    with (app / "Contents" / "Info.plist").open("rb") as handle:
        return plistlib.load(handle)


def record_build(
    evidence: pathlib.Path, app: pathlib.Path, client_app: pathlib.Path
) -> None:
    executable = app / "Contents" / "MacOS" / EXECUTABLE_NAME
    info = plist_value(app)
    head = shared.run_command(["git", "rev-parse", "HEAD"])
    head_sha = head.get("stdout", "").strip()
    commands = {
        "gitHead": head,
        "lipo": shared.run_command(["lipo", "-info", str(executable)]),
        "codesignVerify": shared.run_command(
            ["codesign", "--verify", "--deep", "--strict", "--verbose=4", str(app)]
        ),
        "codesignMetadata": shared.run_command(["codesign", "-dvvv", str(app)]),
        "codesignEntitlements": shared.run_command(
            ["codesign", "-d", "--entitlements", ":-", str(app)]
        ),
        "file": shared.run_command(["file", str(executable)]),
    }
    mode_list = info.get("ComponentInputModeDict", {}).get("tsInputModeListKey", {})
    value = {
        "timestamp": shared.timestamp(),
        "githubSHA": os.environ.get("GITHUB_SHA"),
        "gitHead": head_sha,
        "exactRevisionMatchesCheckout": head_sha == os.environ.get("GITHUB_SHA"),
        "appPath": str(app),
        "executablePath": str(executable),
        "executableSHA256": sha256(executable),
        "keymapSHA256": sha256(app / "Contents" / "Resources" / "keymap.json"),
        "clientExecutableSHA256": sha256(
            client_app / "Contents" / "MacOS" / "HostedIMKProbeClient"
        ),
        "infoPlist": info,
        "bundleID": info.get("CFBundleIdentifier"),
        "declaredSourceIDs": sorted(mode_list),
        "commands": commands,
    }
    value["success"] = (
        value["exactRevisionMatchesCheckout"]
        and value["bundleID"] == BUNDLE_ID
        and value["declaredSourceIDs"] == [DECLARED_MODE_ID]
        and commands["lipo"].get("exitCode") == 0
        and "arm64" in commands["lipo"].get("stdout", "")
        and commands["codesignVerify"].get("exitCode") == 0
    )
    write_json(evidence / "build-identity.json", value)
    if not value["success"]:
        raise RuntimeError("Exact Unicorn build identity verification failed")


def filesystem_identity(path: pathlib.Path) -> dict[str, Any]:
    if not path.exists():
        return {"path": str(path), "exists": False}
    metadata = path.stat()
    return {
        "path": str(path),
        "resolvedPath": str(path.resolve()),
        "exists": True,
        "isDirectory": path.is_dir(),
        "uid": metadata.st_uid,
        "user": pwd.getpwuid(metadata.st_uid).pw_name,
        "gid": metadata.st_gid,
        "group": grp.getgrgid(metadata.st_gid).gr_name,
        "mode": stat.filemode(metadata.st_mode),
        "modeOctal": oct(stat.S_IMODE(metadata.st_mode)),
        "device": metadata.st_dev,
        "inode": metadata.st_ino,
        "parent": str(path.parent),
    }


def launchservices_excerpt(app: pathlib.Path) -> dict[str, Any]:
    command = [
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
        "-dump",
    ]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    lines = completed.stdout.splitlines()
    indexes = [
        index
        for index, line in enumerate(lines)
        if BUNDLE_ID.lower() in line.lower() or str(app).lower() in line.lower()
    ]
    selected: list[str] = []
    seen: set[int] = set()
    for index in indexes:
        for candidate in range(max(0, index - 12), min(len(lines), index + 20)):
            if candidate not in seen:
                seen.add(candidate)
                selected.append(lines[candidate])
    return {
        "command": command,
        "exitCode": completed.returncode,
        "matchingLineIndexes": indexes[:50],
        "matchCount": len(indexes),
        "retainedContextLineLimit": 500,
        "retainedContext": selected[:500],
        "stderr": shared.bounded(completed.stderr, 16_384),
    }


def capture_log_window(
    evidence: pathlib.Path,
    name: str,
    started_at: str | None,
    completed_at: str | None,
    limit: int = 1200,
) -> dict[str, Any]:
    def parse(value: str | None) -> dt.datetime:
        if not value:
            return dt.datetime.now(dt.timezone.utc)
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))

    start = parse(started_at) - dt.timedelta(seconds=2)
    end = max(parse(completed_at), dt.datetime.now(dt.timezone.utc)) + dt.timedelta(seconds=1)
    predicate = (
        '(subsystem CONTAINS[c] "TextInput" '
        'OR subsystem CONTAINS[c] "LaunchServices" '
        'OR subsystem CONTAINS[c] "RunningBoard" '
        'OR subsystem CONTAINS[c] "InputMethodKit" '
        'OR category CONTAINS[c] "TextInput" '
        'OR process == "imklaunchagent" '
        'OR process == "unicorn" '
        'OR process == "lsd" '
        'OR process == "launchservicesd" '
        'OR process == "runningboardd" '
        'OR process == "amfid" '
        'OR process == "taskgated" '
        'OR process == "syspolicyd" '
        'OR process == "ReportCrash" '
        'OR eventMessage CONTAINS[c] "Vic-Shih.inputmethod.unicorn" '
        'OR eventMessage CONTAINS[c] "LaunchInputMethod" '
        'OR eventMessage CONTAINS[c] "IMKXPCEndpoint" '
        'OR eventMessage CONTAINS[c] "dyld")'
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
    completed = subprocess.run(command, capture_output=True, text=True, timeout=45, check=False)
    lines = completed.stdout.splitlines()[-limit:]
    path = evidence / f"{name}.jsonl"
    path.write_text("\n".join(lines) + ("\n" if lines else ""))
    result = {
        "command": command,
        "exitCode": completed.returncode,
        "windowStart": start.isoformat(),
        "windowEnd": end.isoformat(),
        "retainedLineCount": len(lines),
        "retainedTailLimit": limit,
        "path": path.name,
        "stderr": shared.bounded(completed.stderr, 16_384),
    }
    write_json(evidence / f"{name}-metadata.json", result)
    return result


def record_installation(
    evidence: pathlib.Path,
    app: pathlib.Path,
    helper: pathlib.Path,
    stage: str,
) -> None:
    executable = app / "Contents" / "MacOS" / EXECUTABLE_NAME
    value: dict[str, Any] = {
        "timestamp": shared.timestamp(),
        "stage": stage,
        "app": filesystem_identity(app),
        "appParent": filesystem_identity(app.parent),
        "executable": filesystem_identity(executable),
        "process": process_snapshot(app),
        "launchServices": launchservices_excerpt(app),
        "xattrs": shared.run_command(["xattr", "-lr", str(app)]),
        "codesignVerify": shared.run_command(
            ["codesign", "--verify", "--deep", "--strict", "--verbose=4", str(app)]
        ),
        "sourceSnapshot": source_snapshot(
            helper,
            evidence,
            f"input-sources-installation-{stage}.json",
            f"installation-{stage}",
        ),
    }
    if stage == "after":
        before = load_json(evidence / "installation-before.json", {})
        value["installerObservedEffects"] = {
            "appCreated": before.get("app", {}).get("exists") is False
            and value["app"].get("exists") is True,
            "installedInConventionalUserInputMethodsDirectory": app.parent
            == pathlib.Path.home() / "Library" / "Input Methods",
            "launchServicesExactAppMatchObserved": value["launchServices"].get("matchCount", 0) > 0,
            "processRemainedAbsent": value["process"].get("processCount") == 0,
            "sourceCountBefore": before.get("sourceSnapshot", {}).get("data", {}).get("enumeration", {}).get("unicornSourceCount", 0),
            "sourceCountAfter": value["sourceSnapshot"].get("data", {}).get("enumeration", {}).get("unicornSourceCount", 0),
            "quarantinePresentAfter": "com.apple.quarantine" in value["xattrs"].get("stdout", ""),
        }
        value["installerLogWindow"] = capture_log_window(
            evidence,
            "installer-system-log",
            before.get("timestamp"),
            value["timestamp"],
        )
    write_json(evidence / f"installation-{stage}.json", value)


def native_transition(
    helper: pathlib.Path,
    evidence: pathlib.Path,
    name: str,
    arguments: list[str],
) -> dict[str, Any]:
    path = evidence / f"transition-{name}.json"
    command = shared.run_command([str(helper), *arguments, str(path)], timeout=45)
    data = load_json(path, {})
    logs = capture_log_window(
        evidence,
        f"transition-{name}-system-log",
        data.get("startedAt"),
        data.get("completedAt"),
        800,
    )
    return {"command": command, "data": data, "logs": logs}


def process_snapshot(installed_app: pathlib.Path) -> dict[str, Any]:
    expected = installed_app / "Contents" / "MacOS" / EXECUTABLE_NAME
    lookup = shared.run_command(["pgrep", "-x", EXECUTABLE_NAME], timeout=10)
    pids = [line for line in lookup.get("stdout", "").splitlines() if line.isdigit()]
    processes: list[dict[str, Any]] = []
    for pid in pids:
        details = shared.run_command(
            [
                "ps",
                "-p",
                pid,
                "-o",
                "pid=,ppid=,uid=,user=,state=,etime=,lstart=,comm=,args=",
            ],
            timeout=10,
        )
        text_mapping = shared.run_command(
            ["lsof", "-a", "-p", pid, "-d", "txt", "-Fn"], timeout=10
        )
        expected_text_record = f"n{expected}"
        exact_path = (
            expected_text_record in text_mapping.get("stdout", "").splitlines()
            or str(expected) in details.get("stdout", "")
        )
        processes.append(
            {
                "pid": int(pid),
                "expectedExecutablePath": str(expected),
                "ps": details,
                "textMapping": text_mapping,
                "exactExecutablePathProven": exact_path,
            }
        )
    return {
        "timestamp": shared.timestamp(),
        "bundleID": BUNDLE_ID,
        "executableName": EXECUTABLE_NAME,
        "expectedExecutablePath": str(expected),
        "pids": [int(pid) for pid in pids],
        "processCount": len(pids),
        "processes": processes,
        "allObservedProcessesHaveExactExecutablePath": bool(processes)
        and all(item["exactExecutablePathProven"] for item in processes),
        "pgrep": lookup,
    }


def start_appium(evidence: pathlib.Path) -> tuple[Any, Any, Any, dict[str, Any]]:
    transcript = evidence / "webdriver-transcript.jsonl"
    log_handle = (evidence / "appium.log").open("w")
    driver = shared.WebDriver("http://127.0.0.1:4723", transcript)
    process = subprocess.Popen(
        ["appium", "--base-path", "/", "--log-no-colors", "--log-timestamp"],
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
    )
    server = {
        "pid": process.pid,
        "startedByExperiment": True,
        "readiness": shared.wait_for_server(driver),
    }
    return driver, process, log_handle, server


def stop_appium(process: Any, handle: Any, server: dict[str, Any]) -> None:
    server["terminationTargetPID"] = process.pid
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
        server["forceTerminationRequired"] = True
    server["exitCode"] = process.returncode
    server["stoppedOnlyTrackedExperimentProcess"] = True
    handle.close()


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


def approve_if_required(
    driver: Any, helper: pathlib.Path, evidence: pathlib.Path
) -> dict[str, Any]:
    before = source_snapshot(
        helper,
        evidence,
        "input-sources-before-accessibility-allow.json",
        "immediately-before-approval-decision",
    )
    prerequisites = before["data"].get("prerequisites", {})
    required = prerequisites.get("allDocumentedSelectionPrerequisitesSatisfied") is not True
    result: dict[str, Any] = {
        "startedAt": shared.timestamp(),
        "approvalRequiredByObservedSourceProperties": required,
        "attempted": required,
        "method": "exact semantic Accessibility Allow action through Appium Mac2/XCTest",
        "screenshotsDiagnosticOnly": True,
        "usesOCRPixelsOrCoordinates": False,
        "sourceImmediatelyBeforeAllow": before,
        "semanticAllowVerified": False,
        "allowClicked": False,
    }
    session_id: str | None = None
    if not required:
        result["reason"] = "Every documented selection prerequisite was already true"
    else:
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
            allow = shared.find_element(
                driver,
                session_id,
                [("accessibility id", "action-button-1")],
                timeout=25,
            )
            semantic = semantic_element(driver, session_id, allow)
            result["allowElement"] = semantic
            exact = (
                semantic.get("identifier") == "action-button-1"
                and semantic.get("label") == "Allow"
                and truthy(semantic.get("enabled"))
                and truthy(semantic.get("hittable"))
            )
            result["semanticAllowVerified"] = exact
            if not exact:
                raise RuntimeError(f"Refusing non-matching consent control: {semantic}")
            driver.request("POST", f"/session/{session_id}/element/{allow}/click", {})
            result["allowClicked"] = True
            result["allowClickedAt"] = shared.timestamp()
            time.sleep(0.5)
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
    result["sourceImmediatelyAfterAllow"] = source_snapshot(
        helper,
        evidence,
        "input-sources-after-accessibility-allow.json",
        "immediately-after-approval-treatment",
    )
    result["completedAt"] = shared.timestamp()
    result["logs"] = capture_log_window(
        evidence,
        "approval-system-log",
        result["startedAt"],
        result["completedAt"],
        800,
    )
    write_json(evidence / "system-settings-approval.json", result)
    return result


def create_client_session(
    driver: Any, client_app: pathlib.Path, evidence: pathlib.Path, name: str
) -> tuple[str, pathlib.Path, pathlib.Path]:
    current = evidence / f"client-{name}-current.json"
    timeline = evidence / f"client-{name}-timeline.jsonl"
    session_id, _ = shared.create_session(driver, client_app, current, timeline)
    return session_id, current, timeline


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


def dvorak_control(
    driver: Any,
    helper: pathlib.Path,
    client_app: pathlib.Path,
    evidence: pathlib.Path,
    initial: dict[str, Any],
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "startedAt": shared.timestamp(),
        "physicalKeyCode": 37,
        "physicalUSKey": "l",
        "expectedDvorakText": "n",
    }
    session_id: str | None = None
    result["enable"] = native_transition(
        helper, evidence, "dvorak-enable", ["enable-source", DVORAK_ID, LAYOUT_TYPE]
    )
    result["selection"] = native_transition(
        helper, evidence, "dvorak-select", ["select-source", DVORAK_ID, LAYOUT_TYPE]
    )
    try:
        session_id, diagnostics, _ = create_client_session(
            driver, client_app, evidence, "dvorak-control"
        )
        element = shared.find_text_view(driver, session_id)
        result["focus"] = shared.focus_text_view(
            driver, session_id, element, diagnostics
        )
        result["sourceAtDelivery"] = source_snapshot(
            helper,
            evidence,
            "input-sources-at-dvorak-control.json",
            "source-at-dvorak-control-key-delivery",
        )
        key_path = evidence / "key-dvorak-control-37.json"
        result["key"] = shared.run_command(
            [str(helper), "post-key", "37", "physical-us-l", str(key_path)]
        )
        time.sleep(1)
        result["clientDiagnostics"] = shared.diagnostics_snapshot(diagnostics)
    finally:
        if session_id:
            driver.request("DELETE", f"/session/{session_id}", timeout=30)
            result["sessionDeleted"] = True
    original = initial["data"].get("current", {})
    result["restoreOriginal"] = native_transition(
        helper,
        evidence,
        "restore-original-after-dvorak",
        [
            "select-source",
            str(original.get("inputSourceID", US_ID)),
            str(original.get("type", LAYOUT_TYPE)),
        ],
    )
    result["passed"] = (
        current_id(result["sourceAtDelivery"]) == DVORAK_ID
        and result.get("clientDiagnostics", {}).get("text") == "n"
        and result["restoreOriginal"]["data"].get("selectionVerified") is True
    )
    result["completedAt"] = shared.timestamp()
    write_json(evidence / "dvorak-control.json", result)
    return result


def parse_endpoint_evidence(path: pathlib.Path, expected_pid: int | None) -> dict[str, Any]:
    events: list[dict[str, Any]] = []
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        lines = []
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            events.append(event)
    peer_marker = f"setxpcendpoint.peer[{expected_pid}]" if expected_pid else None
    peer = [
        event
        for event in events
        if peer_marker and peer_marker in str(event.get("eventMessage", "")).lower()
    ]
    endpoints = [
        event
        for event in events
        if "received setimkxpcendpoint:forbundleidentifier: from inputmethod"
        in str(event.get("eventMessage", "")).lower()
    ]
    relevant = [
        {
            "timestamp": event.get("timestamp"),
            "process": event.get("process"),
            "processImagePath": event.get("processImagePath"),
            "subsystem": event.get("subsystem"),
            "category": event.get("category"),
            "eventMessage": event.get("eventMessage"),
        }
        for event in events
        if any(
            keyword in str(event.get("eventMessage", "")).lower()
            for keyword in (
                "launchinputmethod",
                "imkxpcendpoint",
                "setxpcendpoint.peer",
                BUNDLE_ID.lower(),
            )
        )
    ]
    return {
        "expectedPID": expected_pid,
        "peerMarker": peer_marker,
        "peerEventCount": len(peer),
        "endpointEventCount": len(endpoints),
        "correlatedEndpointObserved": bool(expected_pid and peer and endpoints),
        "retainedRelevantEvents": relevant[:150],
        "retainedRelevantEventLimit": 150,
    }


def collect_crashes(evidence: pathlib.Path, started_epoch: float) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    directories = [
        pathlib.Path.home() / "Library" / "Logs" / "DiagnosticReports",
        pathlib.Path("/Library/Logs/DiagnosticReports"),
    ]
    for directory in directories:
        try:
            candidates = list(directory.glob("unicorn*")) + list(directory.glob("Unicorn*"))
        except OSError:
            candidates = []
        for source in candidates:
            try:
                metadata = source.stat()
            except OSError:
                continue
            if metadata.st_mtime < started_epoch:
                continue
            destination = evidence / f"crash-{len(results) + 1}-{source.name}"
            try:
                with source.open("rb") as handle:
                    destination.write_bytes(handle.read(1_048_576))
                results.append(
                    {
                        "source": str(source),
                        "modifiedAtEpoch": metadata.st_mtime,
                        "size": metadata.st_size,
                        "retainedPath": destination.name,
                        "retainedByteLimit": 1_048_576,
                    }
                )
            except OSError as error:
                results.append({"source": str(source), "error": str(error)})
    return results


def automatic_activation(
    driver: Any,
    helper: pathlib.Path,
    client_app: pathlib.Path,
    installed_app: pathlib.Path,
    evidence: pathlib.Path,
    trigger_started_at: str,
) -> dict[str, Any]:
    started_epoch = time.time()
    result: dict[str, Any] = {
        "startedAt": trigger_started_at,
        "attempted": True,
        "initiatingTrigger": "exact Unicorn TIS selection followed by focused AppKit client activation and physical backslash-l-enter input",
        "directExecutableLaunchPerformed": False,
        "deadlineSeconds": AUTOMATIC_DEADLINE_SECONDS,
    }
    session_id: str | None = None
    process_observations: list[dict[str, Any]] = []
    try:
        session_id, diagnostics, timeline_path = create_client_session(
            driver, client_app, evidence, "unicorn-supported-installer"
        )
        element = shared.find_text_view(driver, session_id)
        result["focus"] = shared.focus_text_view(
            driver, session_id, element, diagnostics
        )
        result["sourceAtTrigger"] = source_snapshot(
            helper,
            evidence,
            "input-sources-at-unicorn-automatic-trigger.json",
            "source-at-unicorn-automatic-trigger",
        )
        deadline = time.monotonic() + AUTOMATIC_DEADLINE_SECONDS
        while time.monotonic() < deadline:
            observation = process_snapshot(installed_app)
            process_observations.append(observation)
            if observation.get("processCount") == 1:
                break
            time.sleep(0.5)
        keys: list[dict[str, Any]] = []
        for index, (key_code, label) in enumerate(
            ((42, "backslash"), (37, "l"), (36, "enter")), start=1
        ):
            key_path = evidence / f"key-unicorn-{index}-{label}.json"
            command = shared.run_command(
                [str(helper), "post-key", str(key_code), label, str(key_path)],
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
                    "clientDiagnosticsAfter": shared.diagnostics_snapshot(diagnostics),
                    "processAfter": process_snapshot(installed_app),
                }
            )
        final_deadline = time.monotonic() + 4
        while time.monotonic() < final_deadline:
            process_observations.append(process_snapshot(installed_app))
            if shared.diagnostics_snapshot(diagnostics).get("textScalars") == EXPECTED_SCALARS:
                break
            time.sleep(0.25)
        time.sleep(0.5)
        final_process = process_snapshot(installed_app)
        process_observations.append(final_process)
        final_diagnostics = shared.diagnostics_snapshot(diagnostics)
        timeline = timeline_entries(timeline_path)
        marked = [entry for entry in timeline if entry.get("hasMarkedText") is True]
        completed_at = shared.timestamp()
        logs = capture_log_window(
            evidence,
            "automatic-activation-system-log",
            result["startedAt"],
            completed_at,
            1600,
        )
        all_pid_sets = [
            set(observation.get("pids", []))
            for observation in process_observations
            if observation.get("processCount", 0) > 0
        ] + [
            set(key["processAfter"].get("pids", []))
            for key in keys
            if key["processAfter"].get("processCount", 0) > 0
        ]
        observed_pids = sorted(set().union(*all_pid_sets)) if all_pid_sets else []
        exact_pid = observed_pids[0] if len(observed_pids) == 1 else None
        endpoint = parse_endpoint_evidence(evidence / logs["path"], exact_pid)
        exact_path_proven = any(
            observation.get("allObservedProcessesHaveExactExecutablePath") is True
            and observation.get("pids") == [exact_pid]
            for observation in process_observations
        ) if exact_pid else False
        first_exact = next(
            (
                observation
                for observation in process_observations
                if observation.get("pids") == [exact_pid]
            ),
            None,
        )
        final_same_process = final_process.get("pids") == [exact_pid]
        composition_ended = (
            final_diagnostics.get("hasMarkedText") is False
            and (final_diagnostics.get("markedRange") or {}).get("length") == 0
        )
        exact_text = final_diagnostics.get("textScalars") == EXPECTED_SCALARS
        exact_source = (
            current_id(result["sourceAtTrigger"]) == TARGET_SOURCE_ID
            and current_bundle(result["sourceAtTrigger"]) == BUNDLE_ID
        )
        success = (
            exact_source
            and exact_pid is not None
            and exact_path_proven
            and first_exact is not None
            and final_same_process
            and endpoint["correlatedEndpointObserved"]
            and bool(marked)
            and exact_text
            and composition_ended
        )
        result.update(
            {
                "completedAt": completed_at,
                "keys": keys,
                "processObservations": process_observations,
                "automaticProcessPIDs": observed_pids,
                "exactAutomaticProcessCount": len(observed_pids),
                "automaticProcessObserved": exact_pid is not None,
                "exactExecutableIdentityProven": exact_path_proven,
                "processLifetime": {
                    "firstExactObservation": first_exact,
                    "finalObservation": final_process,
                    "sameExactProcessAliveAfterComposition": final_same_process,
                },
                "endpointEvidence": endpoint,
                "correlatedEndpointObserved": endpoint["correlatedEndpointObserved"],
                "markedCompositionObserved": bool(marked),
                "markedCompositionSamples": marked[:12],
                "finalClientDiagnostics": final_diagnostics,
                "sourceSelectedAtTrigger": exact_source,
                "exactTextAssertionPassed": exact_text,
                "compositionEnded": composition_ended,
                "automaticActivationSucceeded": success,
                "logs": logs,
                "newDiagnosticReports": collect_crashes(evidence, started_epoch),
            }
        )
        if exact_pid is not None:
            state_path = evidence / "installation-state.json"
            state = load_json(state_path, {})
            state["automaticProcess"] = {
                "pid": exact_pid,
                "executablePath": str(
                    installed_app / "Contents" / "MacOS" / EXECUTABLE_NAME
                ),
                "launchMethod": "automatic InputMethodKit activation",
                "launchedByUID": os.getuid(),
                "firstObservedAt": first_exact.get("timestamp") if first_exact else None,
            }
            write_json(state_path, state)
    except Exception as error:
        result["error"] = {
            "type": type(error).__name__,
            "message": shared.bounded(str(error)),
        }
        result["automaticActivationSucceeded"] = False
    finally:
        if session_id:
            try:
                driver.request("DELETE", f"/session/{session_id}", timeout=30)
                result["sessionDeleted"] = True
            except Exception as error:
                result["sessionDeleteError"] = shared.bounded(str(error))
    result.setdefault("completedAt", shared.timestamp())
    write_json(evidence / "automatic-activation.json", result)
    return result


def run_experiment(
    evidence: pathlib.Path,
    helper: pathlib.Path,
    client_app: pathlib.Path,
    installed_app: pathlib.Path,
) -> int:
    report: dict[str, Any] = {
        "startedAt": shared.timestamp(),
        "experiment": EXPERIMENT,
        "stageOrder": [
            "same-Aqua-user Dvorak public selection and physical-event control",
            "exact installed Unicorn public TIS registration",
            "exact parent then target public enablement",
            "exact semantic Allow action if source properties show approval pending",
            "exact target public selection without direct process execution",
            "focused AppKit client physical backslash-l-enter composition",
            "automatic exact process, endpoint, source, marked-text, commit, and lifetime proof",
        ],
        "directExecutableLaunchPerformed": False,
        "server": {},
    }
    appium_process = None
    appium_handle = None
    completed = False
    try:
        driver, appium_process, appium_handle, report["server"] = start_appium(evidence)
        if not report["server"]["readiness"].get("ready"):
            raise RuntimeError("Appium server did not become ready")
        initial = source_snapshot(
            helper,
            evidence,
            "input-sources-before-control.json",
            "before-same-session-control",
        )
        report["initialSources"] = initial
        report["dvorakControl"] = dvorak_control(
            driver, helper, client_app, evidence, initial
        )
        report["unicornRegistration"] = native_transition(
            helper,
            evidence,
            "unicorn-registration",
            ["register", str(installed_app)],
        )
        report["unicornParentEnablement"] = native_transition(
            helper, evidence, "unicorn-parent-enablement", ["enable-parents"]
        )
        report["unicornTargetEnablement"] = native_transition(
            helper, evidence, "unicorn-target-enablement", ["enable-target"]
        )
        report["systemSettingsApproval"] = approve_if_required(
            driver, helper, evidence
        )
        report["sameSessionBoundary"] = {
            "timestamp": shared.timestamp(),
            "uid": os.getuid(),
            "user": os.environ.get("USER"),
            "consoleUser": load_json(evidence / "aqua-session.json", {}).get("consoleUser"),
            "guiBootstrapDomain": f"gui/{os.getuid()}",
            "canonicalAppURL": str(installed_app.resolve()),
            "exactExecutablePath": str(
                installed_app / "Contents" / "MacOS" / EXECUTABLE_NAME
            ),
            "processBeforeSelection": process_snapshot(installed_app),
        }
        if report["sameSessionBoundary"]["processBeforeSelection"].get("processCount") != 0:
            raise RuntimeError("Unicorn was running before the automatic activation trigger")
        state_path = evidence / "installation-state.json"
        state = load_json(state_path, {})
        state["selectionStarted"] = True
        write_json(state_path, state)
        report["unicornSelection"] = native_transition(
            helper, evidence, "unicorn-selection", ["select-target"]
        )
        report["automaticActivation"] = automatic_activation(
            driver,
            helper,
            client_app,
            installed_app,
            evidence,
            report["unicornSelection"]["data"].get(
                "startedAt", shared.timestamp()
            ),
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
    write_json(evidence / "experiment.json", report)
    return 0 if completed else 3


def earliest_divergence(report: dict[str, Any]) -> str:
    installation = load_json(
        pathlib.Path(report.get("evidencePath", "")) / "installation-after.json", {}
    ) if report.get("evidencePath") else {}
    registration = report.get("unicornRegistration", {}).get("data", {})
    after_approval = (
        report.get("systemSettingsApproval", {})
        .get("sourceImmediatelyAfterAllow", {})
        .get("data", {})
    )
    selection = report.get("unicornSelection", {}).get("data", {})
    activation = report.get("automaticActivation", {})
    if installation and not installation.get("app", {}).get("exists"):
        return "supported installer did not create the exact app"
    if registration.get("status") != 0:
        return "public TIS registration"
    if registration.get("after", {}).get("enumeration", {}).get("unicornSourceCount", 0) == 0:
        return "exact Unicorn source enumeration after registration"
    if after_approval.get("prerequisites", {}).get("allDocumentedSelectionPrerequisitesSatisfied") is not True:
        return "exact source enablement or required approval"
    if selection.get("selectionVerified") is not True:
        return "exact Unicorn source selection"
    if activation.get("automaticProcessObserved") is not True:
        return "automatic exact Unicorn process creation"
    if activation.get("exactExecutableIdentityProven") is not True:
        return "automatic executable identity proof"
    if activation.get("correlatedEndpointObserved") is not True:
        return "correlated InputMethodKit endpoint registration"
    if activation.get("markedCompositionObserved") is not True:
        return "marked-text composition"
    if activation.get("exactTextAssertionPassed") is not True:
        return "exact committed Unicode output"
    if activation.get("compositionEnded") is not True:
        return "clean composition end"
    return "none"


def finalize(evidence: pathlib.Path, producer_status: int) -> None:
    summary = load_json(evidence / "summary.json", {})
    report = load_json(evidence / "experiment.json", {})
    cleanup = load_json(evidence / "cleanup.json", {})
    activation = report.get("automaticActivation", {})
    report_for_diagnosis = dict(report)
    report_for_diagnosis["evidencePath"] = str(evidence)
    divergence = earliest_divergence(report_for_diagnosis)
    success = (
        producer_status == 0
        and report.get("executionCompleted") is True
        and activation.get("automaticActivationSucceeded") is True
        and cleanup.get("success") is True
    )
    summary.update(
        {
            "status": "completed",
            "completedAt": shared.timestamp(),
            "producerExitCode": producer_status,
            "experimentExecutionCompleted": report.get("executionCompleted") is True,
            "automaticActivationSucceeded": activation.get("automaticActivationSucceeded") is True,
            "cleanupPassed": cleanup.get("success") is True,
            "allSuccessConditionsProven": success,
            "resultMatrix": {
                "automaticExactProcess": activation.get("automaticProcessObserved") is True
                and activation.get("exactExecutableIdentityProven") is True
                and activation.get("processLifetime", {}).get("sameExactProcessAliveAfterComposition") is True,
                "correlatedEndpoint": activation.get("correlatedEndpointObserved") is True,
                "exactSourceCurrent": activation.get("sourceSelectedAtTrigger") is True,
                "markedText": activation.get("markedCompositionObserved") is True,
                "exactCommittedText": activation.get("exactTextAssertionPassed") is True
                and activation.get("compositionEnded") is True,
                "cleanup": cleanup.get("success") is True,
                "dvorakControl": report.get("dvorakControl", {}).get("passed") is True,
            },
            "diagnosis": {
                "earliestDivergenceFromSuccessfulSquirrel": divergence,
                "directExecutableLaunchPerformed": False,
                "conclusion": (
                    "Every required automatic Unicorn activation condition was directly proven."
                    if success
                    else f"Unicorn E2E success is not claimed. The earliest directly observed divergence is {divergence}."
                ),
                "residualUncertainty": (
                    "This single fresh-runner arm establishes sufficiency only for the recorded hosted treatment and revision."
                    if success
                    else "The failed boundary does not identify a deeper cause. Installer topology, signature policy, LaunchServices resolution, and other downstream conditions remain hypotheses unless isolated by a one-condition fresh-runner counterfactual."
                ),
            },
            "boundary": {
                "hostedSetup": "build exact revision, run checked-in installer, configure XCTest automation, request public source enablement, and complete any exact Allow prompt",
                "normalUserActivation": "select exact Unicorn source, focus a normal AppKit text client, and type physical backslash-l-enter",
            },
        }
    )
    write_json(evidence / "summary.json", summary)


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    init_parser = subparsers.add_parser("init")
    init_parser.add_argument("evidence", type=pathlib.Path)
    init_parser.add_argument("installed_app", type=pathlib.Path)
    preflight_parser = subparsers.add_parser("preflight")
    preflight_parser.add_argument("evidence", type=pathlib.Path)
    preflight_parser.add_argument("helper", type=pathlib.Path)
    build_parser = subparsers.add_parser("record-build")
    build_parser.add_argument("evidence", type=pathlib.Path)
    build_parser.add_argument("app", type=pathlib.Path)
    build_parser.add_argument("client_app", type=pathlib.Path)
    install_parser = subparsers.add_parser("record-installation")
    install_parser.add_argument("evidence", type=pathlib.Path)
    install_parser.add_argument("app", type=pathlib.Path)
    install_parser.add_argument("helper", type=pathlib.Path)
    install_parser.add_argument("stage", choices=("before", "after"))
    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("evidence", type=pathlib.Path)
    run_parser.add_argument("helper", type=pathlib.Path)
    run_parser.add_argument("client_app", type=pathlib.Path)
    run_parser.add_argument("installed_app", type=pathlib.Path)
    finalize_parser = subparsers.add_parser("finalize")
    finalize_parser.add_argument("evidence", type=pathlib.Path)
    finalize_parser.add_argument("producer_status", type=int)
    arguments = parser.parse_args()
    if arguments.command == "init":
        initialize(arguments.evidence, arguments.installed_app)
    elif arguments.command == "preflight":
        preflight(arguments.evidence, arguments.helper)
    elif arguments.command == "record-build":
        record_build(arguments.evidence, arguments.app, arguments.client_app)
    elif arguments.command == "record-installation":
        record_installation(
            arguments.evidence, arguments.app, arguments.helper, arguments.stage
        )
    elif arguments.command == "run":
        return run_experiment(
            arguments.evidence,
            arguments.helper,
            arguments.client_app,
            arguments.installed_app,
        )
    elif arguments.command == "finalize":
        finalize(arguments.evidence, arguments.producer_status)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
