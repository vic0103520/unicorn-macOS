import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import SystemConfiguration

private let unicornBundleID = "Vic-Shih.inputmethod.unicorn"
private let declaredModeID = "Vic-Shih.inputmethod.unicorn"
private let expectedTargetSourceID = "Vic-Shih.inputmethod.unicorn.unicorn"
private let dvorakID = "com.apple.keylayout.Dvorak"
private let sourceIDKey = kTISPropertyInputSourceID!
private let bundleIDKey = kTISPropertyBundleID!
private let inputModeIDKey = kTISPropertyInputModeID!
private let localizedNameKey = kTISPropertyLocalizedName!
private let categoryKey = kTISPropertyInputSourceCategory!
private let typeKey = kTISPropertyInputSourceType!
private let selectCapableKey = kTISPropertyInputSourceIsSelectCapable!
private let enabledKey = kTISPropertyInputSourceIsEnabled!
private let enableCapableKey = kTISPropertyInputSourceIsEnableCapable!
private let selectedKey = kTISPropertyInputSourceIsSelected!
private let asciiCapableKey = kTISPropertyInputSourceIsASCIICapable!
private let parentType = kTISTypeKeyboardInputMethodModeEnabled as String
private let modeType = kTISTypeKeyboardInputMode as String
private let layoutType = kTISTypeKeyboardLayout as String

private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
    return CFBooleanGetValue(value)
}

private func jsonValue(_ value: String?) -> Any { value ?? NSNull() }
private func jsonValue(_ value: Bool?) -> Any { value ?? NSNull() }
private func jsonValue(_ value: OSStatus?) -> Any { value ?? NSNull() }

private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func allSources() -> [TISInputSource] {
    guard let unmanaged = TISCreateInputSourceList(nil, true) else { return [] }
    return (unmanaged.takeRetainedValue() as NSArray).map { $0 as! TISInputSource }
}

private func currentSource() -> TISInputSource? {
    TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
}

private func sourceSummary(_ source: TISInputSource?) -> [String: Any] {
    guard let source else { return ["present": false] }
    return [
        "present": true,
        "inputSourceID": jsonValue(stringProperty(source, sourceIDKey)),
        "bundleID": jsonValue(stringProperty(source, bundleIDKey)),
        "inputModeID": jsonValue(stringProperty(source, inputModeIDKey)),
        "localizedName": jsonValue(stringProperty(source, localizedNameKey)),
        "category": jsonValue(stringProperty(source, categoryKey)),
        "type": jsonValue(stringProperty(source, typeKey)),
        "selectCapable": jsonValue(boolProperty(source, selectCapableKey)),
        "enabled": jsonValue(boolProperty(source, enabledKey)),
        "enableCapable": jsonValue(boolProperty(source, enableCapableKey)),
        "selected": jsonValue(boolProperty(source, selectedKey)),
        "asciiCapable": jsonValue(boolProperty(source, asciiCapableKey)),
    ]
}

private func sourceKey(_ source: TISInputSource) -> String {
    [
        stringProperty(source, sourceIDKey) ?? "",
        stringProperty(source, typeKey) ?? "",
        stringProperty(source, inputModeIDKey) ?? "",
    ].joined(separator: "|")
}

private func relevantSources(_ sources: [TISInputSource]) -> [TISInputSource] {
    sources.filter {
        stringProperty($0, sourceIDKey) == dvorakID
            || stringProperty($0, bundleIDKey) == unicornBundleID
    }.sorted {
        sourceKey($0) < sourceKey($1)
    }
}

private func unicornSources(_ sources: [TISInputSource]) -> [TISInputSource] {
    sources.filter { stringProperty($0, bundleIDKey) == unicornBundleID }
}

private func targetSources(_ sources: [TISInputSource]) -> [TISInputSource] {
    unicornSources(sources).filter {
        boolProperty($0, selectCapableKey) == true
            && stringProperty($0, sourceIDKey) == expectedTargetSourceID
            && stringProperty($0, inputModeIDKey) == declaredModeID
    }
}

private func parentSources(_ sources: [TISInputSource]) -> [TISInputSource] {
    unicornSources(sources).filter { stringProperty($0, typeKey) == parentType }
}

private func targetPrerequisites(_ sources: [TISInputSource]) -> [String: Any] {
    let targets = targetSources(sources)
    let target = targets.count == 1 ? targets[0] : nil
    let parents = parentSources(sources)
    let targetIsMode = target.flatMap { stringProperty($0, typeKey) } == modeType
    let enabledParents = parents.filter { boolProperty($0, enabledKey) == true }
    let parentRequirementSatisfied = !targetIsMode || (!parents.isEmpty && enabledParents.count == parents.count)
    let targetEnabled = target.flatMap { boolProperty($0, enabledKey) } == true
    return [
        "declaredModeID": declaredModeID,
        "expectedTargetSourceID": expectedTargetSourceID,
        "exactTargetCount": targets.count,
        "exactTargetUnique": targets.count == 1,
        "target": sourceSummary(target),
        "targetEnabledIsTrue": targetEnabled,
        "targetSelectCapableIsTrue": target.flatMap { boolProperty($0, selectCapableKey) } == true,
        "targetIsInputMode": targetIsMode,
        "parentCount": parents.count,
        "enabledParentCount": enabledParents.count,
        "parentRequirementSatisfied": parentRequirementSatisfied,
        "allDocumentedSelectionPrerequisitesSatisfied": targets.count == 1
            && targetEnabled && parentRequirementSatisfied,
    ]
}

private func snapshotValue(label: String) -> [String: Any] {
    let sources = allSources()
    let relevant = relevantSources(sources)
    let unicorn = unicornSources(sources)
    let parents = parentSources(sources)
    let targets = targetSources(sources)
    return [
        "schemaVersion": 1,
        "timestamp": timestamp(),
        "label": label,
        "current": sourceSummary(currentSource()),
        "declaredIdentity": [
            "bundleID": unicornBundleID,
            "parentSourceID": unicornBundleID,
            "declaredModeID": declaredModeID,
            "expectedTargetSourceID": expectedTargetSourceID,
        ],
        "relevantSourceCount": relevant.count,
        "sources": relevant.map { source in
            var summary = sourceSummary(source)
            summary["sourceKey"] = sourceKey(source)
            summary["role"] = stringProperty(source, sourceIDKey) == dvorakID
                ? "dvorak-layout"
                : (stringProperty(source, typeKey) == parentType
                    ? "unicorn-input-method-parent"
                    : (targets.contains { $0 === source }
                        ? "unicorn-selectable-target"
                        : "unicorn-other-source"))
            return summary
        },
        "enumeration": [
            "unicornSourceCount": unicorn.count,
            "unicornParentCount": parents.count,
            "unicornSelectableTargetCount": targets.count,
            "unicornModeCount": unicorn.filter { stringProperty($0, typeKey) == modeType }.count,
            "dvorakCount": relevant.filter { stringProperty($0, sourceIDKey) == dvorakID }.count,
        ],
        "prerequisites": targetPrerequisites(sources),
        "documentedSelectionContract": [
            "paramErr": paramErr,
            "paramErrMeaning": "the source is not selectable",
            "requiredTargetProperties": [
                "kTISPropertyInputSourceIsSelectCapable == true",
                "kTISPropertyInputSourceIsEnabled == true",
            ],
            "inputModeAdditionalRequirement": "an enabled parent input method",
        ],
    ]
}

private func writeJSON(_ value: Any, path: String) throws {
    let data = try JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys]
    )
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

private func printJSON(_ value: Any) {
    guard let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys]
    ), let text = String(data: data, encoding: .utf8) else { return }
    print(text)
}

private func readJSON(_ path: String) -> [String: Any] {
    guard let data = FileManager.default.contents(atPath: path),
        let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return value
}

private func session(outputPath: String) throws {
    let sessionDictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
    let consoleUser = SCDynamicStoreCopyConsoleUser(nil, nil, nil) as String?
    let value: [String: Any] = [
        "timestamp": timestamp(),
        "runnerArchitecture": jsonValue(ProcessInfo.processInfo.environment["RUNNER_ARCH"]),
        "processUser": NSUserName(),
        "uid": getuid(),
        "consoleUser": jsonValue(consoleUser),
        "hasAquaSessionDictionary": sessionDictionary != nil,
        "screenCount": NSScreen.screens.count,
        "accessibilityTrusted": AXIsProcessTrusted(),
        "cgEventPostPreflight": CGPreflightPostEventAccess(),
    ]
    try writeJSON(value, path: outputPath)
    printJSON(value)
}

private func snapshot(label: String, outputPath: String) throws {
    let value = snapshotValue(label: label)
    try writeJSON(value, path: outputPath)
    printJSON([
        "timestamp": value["timestamp"] as Any,
        "label": label,
        "current": value["current"] as Any,
        "enumeration": value["enumeration"] as Any,
    ])
}

private func register(appPath: String, outputPath: String) throws -> Int32 {
    let startedAt = timestamp()
    let before = snapshotValue(label: "immediately-before-registration")
    let canonicalURL = URL(fileURLWithPath: appPath).standardizedFileURL
    let status = TISRegisterInputSource(canonicalURL as CFURL)
    let afterImmediate = snapshotValue(label: "immediately-after-registration")
    var attempts = 0
    for attempt in 1...50 {
        attempts = attempt
        if !unicornSources(allSources()).isEmpty { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    let result: [String: Any] = [
        "schemaVersion": 1,
        "operation": "TISRegisterInputSource",
        "publicAPI": true,
        "startedAt": startedAt,
        "completedAt": timestamp(),
        "appPath": appPath,
        "canonicalAppURL": canonicalURL.path,
        "status": status,
        "before": before,
        "afterImmediate": afterImmediate,
        "refreshAttempts": attempts,
        "after": snapshotValue(label: "after-registration-and-live-refresh"),
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return status == noErr ? 0 : 2
}

private func enableParents(outputPath: String) throws -> Int32 {
    let startedAt = timestamp()
    let before = snapshotValue(label: "immediately-before-parent-enablement")
    let parents = parentSources(allSources())
    var operations: [[String: Any]] = []
    for source in parents {
        let status = TISEnableInputSource(source)
        operations.append([
            "source": sourceSummary(source),
            "sourceKey": sourceKey(source),
            "status": status,
        ])
    }
    Thread.sleep(forTimeInterval: 0.5)
    let result: [String: Any] = [
        "schemaVersion": 1,
        "operation": "TISEnableInputSource for exact Unicorn parent sources",
        "publicAPI": true,
        "startedAt": startedAt,
        "completedAt": timestamp(),
        "parentCount": parents.count,
        "operations": operations,
        "noParentWasRequired": parents.isEmpty,
        "before": before,
        "after": snapshotValue(label: "after-parent-enablement-and-live-refresh"),
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return operations.allSatisfy { ($0["status"] as? Int32) == noErr } ? 0 : 2
}

private func enableTarget(outputPath: String) throws -> Int32 {
    let startedAt = timestamp()
    let before = snapshotValue(label: "immediately-before-target-enablement")
    let targets = targetSources(allSources())
    let status = targets.count == 1 ? TISEnableInputSource(targets[0]) : nil
    var refreshAttempts = 0
    if status != nil {
        for attempt in 1...30 {
            refreshAttempts = attempt
            let refreshed = targetSources(allSources())
            if refreshed.count == 1, boolProperty(refreshed[0], enabledKey) == true {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    let result: [String: Any] = [
        "schemaVersion": 1,
        "operation": "TISEnableInputSource for exact Unicorn target",
        "publicAPI": true,
        "startedAt": startedAt,
        "completedAt": timestamp(),
        "exactTargetCount": targets.count,
        "target": sourceSummary(targets.count == 1 ? targets[0] : nil),
        "status": jsonValue(status),
        "refreshAttempts": refreshAttempts,
        "before": before,
        "after": snapshotValue(label: "after-target-enablement-and-live-refresh"),
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return targets.count == 1 && status == noErr ? 0 : 2
}

private func enableSource(
    sourceID: String, expectedType: String, outputPath: String
) throws -> Int32 {
    let startedAt = timestamp()
    let matches = allSources().filter {
        stringProperty($0, sourceIDKey) == sourceID
            && stringProperty($0, typeKey) == expectedType
    }
    let status = matches.count == 1 ? TISEnableInputSource(matches[0]) : nil
    let result: [String: Any] = [
        "schemaVersion": 1,
        "operation": "TISEnableInputSource",
        "startedAt": startedAt,
        "completedAt": timestamp(),
        "sourceID": sourceID,
        "expectedType": expectedType,
        "exactTargetCount": matches.count,
        "status": jsonValue(status),
        "after": snapshotValue(label: "after-enable-\(sourceID)"),
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return matches.count == 1 && status == noErr ? 0 : 2
}

private func selectSource(
    sourceID: String, expectedType: String, outputPath: String
) throws -> Int32 {
    let startedAt = timestamp()
    let before = snapshotValue(label: "immediately-before-select-\(sourceID)")
    let matches = allSources().filter {
        stringProperty($0, sourceIDKey) == sourceID
            && stringProperty($0, typeKey) == expectedType
    }
    let status = matches.count == 1 ? TISSelectInputSource(matches[0]) : nil
    var attempts = 0
    for attempt in 1...30 {
        attempts = attempt
        if stringProperty(currentSource()!, sourceIDKey) == sourceID { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    let after = snapshotValue(label: "after-select-\(sourceID)")
    let selected = (after["current"] as? [String: Any])?["inputSourceID"] as? String == sourceID
    let result: [String: Any] = [
        "schemaVersion": 1,
        "operation": "TISSelectInputSource",
        "publicAPI": true,
        "startedAt": startedAt,
        "completedAt": timestamp(),
        "sourceID": sourceID,
        "expectedType": expectedType,
        "exactTargetCount": matches.count,
        "status": jsonValue(status),
        "observationAttempts": attempts,
        "selectionVerified": selected,
        "before": before,
        "after": after,
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return matches.count == 1 && status == noErr && selected ? 0 : 2
}

private func selectTarget(outputPath: String) throws -> Int32 {
    let startedAt = timestamp()
    let before = snapshotValue(label: "immediately-before-select-exact-unicorn-target")
    let sources = allSources()
    let targets = targetSources(sources)
    let prerequisites = targetPrerequisites(sources)
    let status = targets.count == 1 ? TISSelectInputSource(targets[0]) : nil
    var attempts = 0
    var current = currentSource()
    let expectedID = targets.count == 1 ? stringProperty(targets[0], sourceIDKey) : nil
    for attempt in 1...30 {
        attempts = attempt
        current = currentSource()
        if stringProperty(current!, sourceIDKey) == expectedID { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    let selectionVerified = expectedID != nil
        && stringProperty(current!, sourceIDKey) == expectedID
        && stringProperty(current!, bundleIDKey) == unicornBundleID
    let result: [String: Any] = [
        "schemaVersion": 1,
        "operation": "TISSelectInputSource",
        "publicAPI": true,
        "startedAt": startedAt,
        "completedAt": timestamp(),
        "exactTargetCount": targets.count,
        "target": sourceSummary(targets.count == 1 ? targets[0] : nil),
        "documentedPrerequisitesImmediatelyBefore": prerequisites,
        "status": jsonValue(status),
        "expectedSelectedInputSourceID": jsonValue(expectedID),
        "selectionVerified": selectionVerified,
        "observationAttempts": attempts,
        "before": before,
        "after": snapshotValue(label: "after-select-exact-unicorn-target"),
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return targets.count == 1 && status == noErr && selectionVerified ? 0 : 2
}

private func postKey(keyCode: CGKeyCode, label: String, outputPath: String) throws -> Int32 {
    let startedAt = timestamp()
    var result: [String: Any] = [
        "schemaVersion": 1,
        "operation": "CGEvent hardware-style key delivery",
        "startedAt": startedAt,
        "keyCode": keyCode,
        "label": label,
        "accessibilityTrusted": AXIsProcessTrusted(),
        "cgEventPostPreflight": CGPreflightPostEventAccess(),
        "posted": false,
    ]
    guard CGPreflightPostEventAccess(),
        let eventSource = CGEventSource(stateID: .hidSystemState),
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
        let up = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
    else {
        result["completedAt"] = timestamp()
        try writeJSON(result, path: outputPath)
        printJSON(result)
        return 3
    }
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    up.post(tap: .cghidEventTap)
    result["posted"] = true
    result["completedAt"] = timestamp()
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return 0
}

private func cleanup(statePath: String, outputPath: String) throws -> Int32 {
    let state = readJSON(statePath)
    let initialID = state["initialCurrentSourceID"] as? String
    let initialType = state["initialCurrentSourceType"] as? String
    let initialSources = state["initialUnicornSources"] as? [[String: Any]] ?? []
    let dvorakInitiallyEnabled = state["dvorakInitiallyEnabled"] as? Bool ?? false
    let initiallyEnabledKeys = Set(initialSources.compactMap { source -> String? in
        guard source["enabled"] as? Bool == true else { return nil }
        return source["sourceKey"] as? String
    })
    var restoreStatus: OSStatus?
    var restoreVerified = false
    if let initialID, let initialType {
        let matches = allSources().filter {
            stringProperty($0, sourceIDKey) == initialID
                && stringProperty($0, typeKey) == initialType
        }
        if matches.count == 1 {
            _ = TISEnableInputSource(matches[0])
            restoreStatus = TISSelectInputSource(matches[0])
            for _ in 0..<30 {
                if stringProperty(currentSource()!, sourceIDKey) == initialID {
                    restoreVerified = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    let currentUnicorn = unicornSources(allSources()).sorted {
        let lhsParent = stringProperty($0, typeKey) == parentType
        let rhsParent = stringProperty($1, typeKey) == parentType
        return lhsParent == rhsParent ? sourceKey($0) < sourceKey($1) : !lhsParent
    }
    var disableResults: [[String: Any]] = []
    for source in currentUnicorn where !initiallyEnabledKeys.contains(sourceKey(source)) {
        let status = TISDisableInputSource(source)
        disableResults.append([
            "source": sourceSummary(source),
            "sourceKey": sourceKey(source),
            "status": status,
        ])
    }
    var dvorakDisableStatus: OSStatus?
    if !dvorakInitiallyEnabled {
        let matches = allSources().filter {
            stringProperty($0, sourceIDKey) == dvorakID
                && stringProperty($0, typeKey) == layoutType
        }
        if matches.count == 1 {
            dvorakDisableStatus = TISDisableInputSource(matches[0])
        }
    }
    let unicornDisableSucceeded = disableResults.allSatisfy {
        ($0["status"] as? Int32) == noErr
    }
    let dvorakRestored = dvorakInitiallyEnabled || dvorakDisableStatus == noErr
    let result: [String: Any] = [
        "schemaVersion": 1,
        "timestamp": timestamp(),
        "initialCurrentSourceID": jsonValue(initialID),
        "initialCurrentSourceType": jsonValue(initialType),
        "restoreStatus": jsonValue(restoreStatus),
        "restoredOriginalSource": restoreVerified,
        "disableResults": disableResults,
        "disabledOnlyInitiallyDisabledUnicornSources": true,
        "dvorakInitiallyEnabled": dvorakInitiallyEnabled,
        "dvorakDisableStatus": jsonValue(dvorakDisableStatus),
        "dvorakStateRestored": dvorakRestored,
        "after": snapshotValue(label: "after-source-cleanup"),
        "success": restoreVerified && unicornDisableSucceeded && dvorakRestored,
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return restoreVerified ? 0 : 4
}

private func usage() -> Never {
    fputs(
        "usage: UnicornSourceHelper session OUT | sources LABEL OUT | register APP OUT | enable-parents OUT | enable-target OUT | enable-source ID TYPE OUT | select-source ID TYPE OUT | select-target OUT | post-key CODE LABEL OUT | cleanup STATE OUT\n",
        stderr
    )
    exit(64)
}

private let arguments = CommandLine.arguments
private let command = arguments.count > 1 ? arguments[1] : ""

do {
    let status: Int32
    switch command {
    case "session" where arguments.count == 3:
        try session(outputPath: arguments[2]); status = 0
    case "sources" where arguments.count == 4:
        try snapshot(label: arguments[2], outputPath: arguments[3]); status = 0
    case "register" where arguments.count == 4:
        status = try register(appPath: arguments[2], outputPath: arguments[3])
    case "enable-parents" where arguments.count == 3:
        status = try enableParents(outputPath: arguments[2])
    case "enable-target" where arguments.count == 3:
        status = try enableTarget(outputPath: arguments[2])
    case "enable-source" where arguments.count == 5:
        status = try enableSource(
            sourceID: arguments[2], expectedType: arguments[3], outputPath: arguments[4]
        )
    case "select-source" where arguments.count == 5:
        status = try selectSource(
            sourceID: arguments[2], expectedType: arguments[3], outputPath: arguments[4]
        )
    case "select-target" where arguments.count == 3:
        status = try selectTarget(outputPath: arguments[2])
    case "post-key" where arguments.count == 5:
        guard let keyCode = UInt16(arguments[2]) else { usage() }
        status = try postKey(
            keyCode: CGKeyCode(keyCode), label: arguments[3], outputPath: arguments[4]
        )
    case "cleanup" where arguments.count == 4:
        status = try cleanup(statePath: arguments[2], outputPath: arguments[3])
    default:
        usage()
    }
    exit(status)
} catch {
    fputs("UnicornSourceHelper error: \(error)\n", stderr)
    exit(70)
}
