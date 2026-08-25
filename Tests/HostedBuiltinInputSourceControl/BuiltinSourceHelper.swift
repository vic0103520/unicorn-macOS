import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import SystemConfiguration

private let sourceIDKey = kTISPropertyInputSourceID!
private let bundleIDKey = kTISPropertyBundleID!
private let localizedNameKey = kTISPropertyLocalizedName!
private let categoryKey = kTISPropertyInputSourceCategory!
private let typeKey = kTISPropertyInputSourceType!
private let enabledKey = kTISPropertyInputSourceIsEnabled!
private let selectedKey = kTISPropertyInputSourceIsSelected!
private let asciiCapableKey = kTISPropertyInputSourceIsASCIICapable!

private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
    return CFBooleanGetValue(value)
}

private func allSources() -> [TISInputSource] {
    guard let unmanaged = TISCreateInputSourceList(nil, true) else { return [] }
    return (unmanaged.takeRetainedValue() as NSArray).map { $0 as! TISInputSource }
}

private func source(withID identifier: String) -> TISInputSource? {
    allSources().first { stringProperty($0, sourceIDKey) == identifier }
}

private func currentSource() -> TISInputSource? {
    TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
}

private func summary(_ source: TISInputSource?) -> [String: Any] {
    guard let source else { return ["present": false] }
    return [
        "present": true,
        "inputSourceID": stringProperty(source, sourceIDKey) as Any,
        "bundleID": stringProperty(source, bundleIDKey) as Any,
        "localizedName": stringProperty(source, localizedNameKey) as Any,
        "category": stringProperty(source, categoryKey) as Any,
        "type": stringProperty(source, typeKey) as Any,
        "enabled": boolProperty(source, enabledKey) as Any,
        "selected": boolProperty(source, selectedKey) as Any,
        "asciiCapable": boolProperty(source, asciiCapableKey) as Any,
    ]
}

private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func writeJSON(_ value: Any, path: String) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

private func readJSON(path: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func printJSON(_ value: Any) {
    guard let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys]
    ), let text = String(data: data, encoding: .utf8) else { return }
    print(text)
}

private func isBuiltInKeyboardLayout(_ identifier: String) -> Bool {
    identifier.hasPrefix("com.apple.keylayout.")
}

private func waitForCurrent(_ identifier: String) -> [String: Any] {
    var current = currentSource()
    var attempts = 0
    for attempt in 1...50 {
        attempts = attempt
        current = currentSource()
        if let current, stringProperty(current, sourceIDKey) == identifier { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return [
        "attempts": attempts,
        "verified": current.flatMap { stringProperty($0, sourceIDKey) } == identifier,
        "current": summary(current),
    ]
}

private func captureState(targetID: String, statePath: String) throws -> Int32 {
    guard isBuiltInKeyboardLayout(targetID), let target = source(withID: targetID) else {
        return 2
    }
    let value: [String: Any] = [
        "schemaVersion": 1,
        "createdAt": timestamp(),
        "priorSource": summary(currentSource()),
        "targetSource": summary(target),
        "targetID": targetID,
        "targetInitiallyEnabled": boolProperty(target, enabledKey) ?? false,
    ]
    try writeJSON(value, path: statePath)
    printJSON(value)
    return 0
}

private func snapshot(outputPath: String) throws {
    let sources = allSources().filter {
        stringProperty($0, sourceIDKey)?.hasPrefix("com.apple.keylayout.") == true
    }
    let value: [String: Any] = [
        "timestamp": timestamp(),
        "current": summary(currentSource()),
        "builtInKeyboardLayoutCount": sources.count,
        "sources": sources.map(summary),
    ]
    try writeJSON(value, path: outputPath)
    printJSON([
        "timestamp": value["timestamp"] as Any,
        "current": value["current"] as Any,
        "builtInKeyboardLayoutCount": sources.count,
    ])
}

private func transition(targetID: String, outputPath: String) throws -> Int32 {
    guard isBuiltInKeyboardLayout(targetID), let target = source(withID: targetID) else {
        let result: [String: Any] = [
            "timestamp": timestamp(), "success": false, "targetID": targetID,
            "error": "Target is not an available built-in keyboard layout",
        ]
        try writeJSON(result, path: outputPath)
        return 2
    }
    let before = summary(currentSource())
    let targetBefore = summary(target)
    let wasEnabled = boolProperty(target, enabledKey) ?? false
    let enableStatus = TISEnableInputSource(target)
    let refreshedTarget = source(withID: targetID)
    let selectionStatus = refreshedTarget.map(TISSelectInputSource)
    let observation = waitForCurrent(targetID)
    let success = enableStatus == noErr && selectionStatus == noErr
        && observation["verified"] as? Bool == true
    let result: [String: Any] = [
        "timestamp": timestamp(),
        "success": success,
        "before": before,
        "targetBefore": targetBefore,
        "targetInitiallyEnabled": wasEnabled,
        "enableStatus": enableStatus,
        "selectionStatus": selectionStatus as Any,
        "observation": observation,
        "targetAfter": summary(source(withID: targetID)),
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return success ? 0 : 3
}

private func cleanup(statePath: String, outputPath: String) throws -> Int32 {
    guard let state = readJSON(path: statePath),
        let prior = state["priorSource"] as? [String: Any],
        let priorID = prior["inputSourceID"] as? String,
        let targetID = state["targetID"] as? String,
        isBuiltInKeyboardLayout(targetID)
    else {
        let result: [String: Any] = [
            "timestamp": timestamp(), "success": false, "error": "Control state unavailable",
        ]
        try writeJSON(result, path: outputPath)
        return 4
    }
    let targetInitiallyEnabled = state["targetInitiallyEnabled"] as? Bool ?? true
    let restoreEnableStatus = source(withID: priorID).map(TISEnableInputSource)
    let restoreSelectStatus = source(withID: priorID).map(TISSelectInputSource)
    let restoreObservation = waitForCurrent(priorID)
    let disableStatus = targetInitiallyEnabled ? nil : source(withID: targetID).map(TISDisableInputSource)
    let targetAfter = source(withID: targetID)
    let targetStateRestored = targetInitiallyEnabled
        || targetAfter.flatMap { boolProperty($0, enabledKey) } == false
    let success = restoreSelectStatus == noErr
        && restoreObservation["verified"] as? Bool == true
        && targetStateRestored
    let result: [String: Any] = [
        "timestamp": timestamp(),
        "success": success,
        "priorID": priorID,
        "targetID": targetID,
        "targetInitiallyEnabled": targetInitiallyEnabled,
        "restoreEnableStatus": restoreEnableStatus as Any,
        "restoreSelectStatus": restoreSelectStatus as Any,
        "restoreObservation": restoreObservation,
        "disableStatus": disableStatus as Any,
        "targetAfter": summary(targetAfter),
        "targetStateRestored": targetStateRestored,
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return success ? 0 : 5
}

private func session(outputPath: String) throws {
    let sessionDictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
    let consoleUser = SCDynamicStoreCopyConsoleUser(nil, nil, nil) as String?
    let value: [String: Any] = [
        "timestamp": timestamp(),
        "runnerArchitecture": ProcessInfo.processInfo.environment["RUNNER_ARCH"] as Any,
        "processUser": NSUserName(),
        "consoleUser": consoleUser as Any,
        "hasAquaSessionDictionary": sessionDictionary != nil,
        "screenCount": NSScreen.screens.count,
        "accessibilityTrusted": AXIsProcessTrusted(),
        "cgEventPostPreflight": CGPreflightPostEventAccess(),
    ]
    try writeJSON(value, path: outputPath)
    printJSON(value)
}

private func postKey(keyCode: CGKeyCode, outputPath: String) throws -> Int32 {
    let preflight = CGPreflightPostEventAccess()
    var result: [String: Any] = [
        "timestamp": timestamp(),
        "keyCode": keyCode,
        "accessibilityTrusted": AXIsProcessTrusted(),
        "cgEventPostPreflight": preflight,
        "posted": false,
    ]
    guard preflight, let source = CGEventSource(stateID: .hidSystemState),
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else {
        try writeJSON(result, path: outputPath)
        return 6
    }
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.1)
    up.post(tap: .cghidEventTap)
    result["posted"] = true
    result["completedAt"] = timestamp()
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return 0
}

private func usage() -> Never {
    fputs(
        "usage: BuiltinSourceHelper session OUT | snapshot OUT | capture-state TARGET STATE | transition TARGET OUT | cleanup STATE OUT | post-key KEYCODE OUT\n",
        stderr
    )
    exit(64)
}

let arguments = CommandLine.arguments
let command = arguments.count > 1 ? arguments[1] : ""

do {
    let status: Int32
    switch command {
    case "session" where arguments.count == 3:
        try session(outputPath: arguments[2])
        status = 0
    case "snapshot" where arguments.count == 3:
        try snapshot(outputPath: arguments[2])
        status = 0
    case "capture-state" where arguments.count == 4:
        status = try captureState(targetID: arguments[2], statePath: arguments[3])
    case "transition" where arguments.count == 4:
        status = try transition(targetID: arguments[2], outputPath: arguments[3])
    case "cleanup" where arguments.count == 4:
        status = try cleanup(statePath: arguments[2], outputPath: arguments[3])
    case "post-key" where arguments.count == 4:
        guard let keyCode = UInt16(arguments[2]) else { usage() }
        status = try postKey(keyCode: keyCode, outputPath: arguments[3])
    default:
        usage()
    }
    exit(status)
} catch {
    fputs("BuiltinSourceHelper error: \(error)\n", stderr)
    exit(70)
}
