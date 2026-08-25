import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import SystemConfiguration

private let sourceIDKey = kTISPropertyInputSourceID!
private let bundleIDKey = kTISPropertyBundleID!
private let inputModeIDKey = kTISPropertyInputModeID!
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

private func source(bundleID: String, modeID: String) -> TISInputSource? {
    let sources = allSources()
    return sources.first {
        stringProperty($0, sourceIDKey) == modeID
            || stringProperty($0, inputModeIDKey) == modeID
    } ?? sources.first {
        stringProperty($0, bundleIDKey) == bundleID
            && stringProperty($0, typeKey) == (kTISTypeKeyboardInputMode as String)
    }
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
        "inputModeID": stringProperty(source, inputModeIDKey) as Any,
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

private func session(outputPath: String) throws {
    let sessionDictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
    let consoleUser = SCDynamicStoreCopyConsoleUser(nil, nil, nil) as String?
    let value: [String: Any] = [
        "timestamp": timestamp(),
        "runnerArchitecture": ProcessInfo.processInfo.environment["RUNNER_ARCH"] as Any,
        "processUser": NSUserName(),
        "uid": getuid(),
        "consoleUser": consoleUser as Any,
        "hasAquaSessionDictionary": sessionDictionary != nil,
        "screenCount": NSScreen.screens.count,
        "accessibilityTrusted": AXIsProcessTrusted(),
        "cgEventPostPreflight": CGPreflightPostEventAccess(),
    ]
    try writeJSON(value, path: outputPath)
    printJSON(value)
}

private func snapshot(outputPath: String) throws {
    let sources = allSources()
    let value: [String: Any] = [
        "timestamp": timestamp(),
        "current": summary(currentSource()),
        "sourceCount": sources.count,
        "sources": sources.map(summary),
    ]
    try writeJSON(value, path: outputPath)
    printJSON([
        "timestamp": value["timestamp"] as Any,
        "current": value["current"] as Any,
        "sourceCount": sources.count,
        "outputPath": outputPath,
    ])
}

private func installAndSelect(
    appPath: String,
    bundleID: String,
    modeID: String,
    statePath: String,
    resultPath: String
) throws -> Int32 {
    let prior = currentSource()
    var state: [String: Any] = [
        "schemaVersion": 1,
        "createdAt": timestamp(),
        "appPath": appPath,
        "bundleID": bundleID,
        "modeID": modeID,
        "priorSource": summary(prior),
        "registrationAttempted": false,
        "selectionAttempted": false,
    ]
    try writeJSON(state, path: statePath)

    state["registrationAttempted"] = true
    try writeJSON(state, path: statePath)
    let registrationStatus = TISRegisterInputSource(
        URL(fileURLWithPath: appPath) as CFURL
    )

    var target: TISInputSource?
    var discoveryAttempts = 0
    for attempt in 1...50 {
        discoveryAttempts = attempt
        target = source(bundleID: bundleID, modeID: modeID)
        if target != nil { break }
        Thread.sleep(forTimeInterval: 0.1)
    }

    let targetAtDiscovery = summary(target)
    let expectedID = target.flatMap { stringProperty($0, sourceIDKey) }
    let enableStatus = target.map(TISEnableInputSource)
    state["selectionAttempted"] = target != nil
    state["registrationStatus"] = registrationStatus
    state["enableStatus"] = enableStatus as Any
    state["expectedSelectedInputSourceID"] = expectedID as Any
    try writeJSON(state, path: statePath)

    var attempts: [[String: Any]] = []
    var finalSelectionStatus: OSStatus?
    var selected = currentSource()
    if target != nil {
        for attempt in 1...120 {
            let refreshed = source(bundleID: bundleID, modeID: modeID)
            let status = refreshed.map(TISSelectInputSource)
            finalSelectionStatus = status
            selected = currentSource()
            let selectedID = selected.flatMap { stringProperty($0, sourceIDKey) }
            attempts.append([
                "attempt": attempt,
                "timestamp": timestamp(),
                "selectionStatus": status as Any,
                "target": summary(refreshed),
                "selectedSource": summary(selected),
                "selectionVerified": expectedID != nil && selectedID == expectedID,
            ])
            let interim: [String: Any] = [
                "timestamp": timestamp(),
                "completed": false,
                "appPath": appPath,
                "bundleID": bundleID,
                "modeID": modeID,
                "priorSource": summary(prior),
                "registrationStatus": registrationStatus,
                "discoveryAttempts": discoveryAttempts,
                "targetAtDiscovery": targetAtDiscovery,
                "enableStatus": enableStatus as Any,
                "expectedSelectedInputSourceID": expectedID as Any,
                "selectionAttempts": attempts,
                "selectedSource": summary(selected),
            ]
            try writeJSON(interim, path: resultPath)
            if selectedID == expectedID { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    let selectedID = selected.flatMap { stringProperty($0, sourceIDKey) }
    let selectionVerified = expectedID != nil && selectedID == expectedID
    let success = registrationStatus == noErr
        && target != nil
        && enableStatus == noErr
        && finalSelectionStatus == noErr
        && selectionVerified
    let result: [String: Any] = [
        "timestamp": timestamp(),
        "completed": true,
        "success": success,
        "appPath": appPath,
        "bundleID": bundleID,
        "modeID": modeID,
        "priorSource": summary(prior),
        "registrationStatus": registrationStatus,
        "discoveryAttempts": discoveryAttempts,
        "targetAtDiscovery": targetAtDiscovery,
        "enableStatus": enableStatus as Any,
        "expectedSelectedInputSourceID": expectedID as Any,
        "selectionAttempts": attempts,
        "finalSelectionStatus": finalSelectionStatus as Any,
        "selectedSource": summary(selected),
        "selectionVerified": selectionVerified,
    ]
    state["selectionVerified"] = selectionVerified
    state["finalSelectionStatus"] = finalSelectionStatus as Any
    try writeJSON(state, path: statePath)
    try writeJSON(result, path: resultPath)
    printJSON(result)
    return success ? 0 : 2
}

private func postKey(keyCode: CGKeyCode, label: String, outputPath: String) throws -> Int32 {
    let preflight = CGPreflightPostEventAccess()
    var value: [String: Any] = [
        "timestamp": timestamp(),
        "keyCode": keyCode,
        "label": label,
        "accessibilityTrusted": AXIsProcessTrusted(),
        "cgEventPostPreflight": preflight,
        "posted": false,
    ]
    guard preflight, let eventSource = CGEventSource(stateID: .hidSystemState),
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
        let up = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
    else {
        try writeJSON(value, path: outputPath)
        return 3
    }
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    up.post(tap: .cghidEventTap)
    value["posted"] = true
    value["completedAt"] = timestamp()
    try writeJSON(value, path: outputPath)
    printJSON(value)
    return 0
}

private func cleanupSources(bundleID: String, outputPath: String) throws -> Int32 {
    let usID = "com.apple.keylayout.US"
    let usSource = source(withID: usID)
    let restoreEnableStatus = usSource.map(TISEnableInputSource)
    let restoreSelectStatus = usSource.map(TISSelectInputSource)
    var selected = currentSource()
    var restoreAttempts = 0
    for attempt in 1...50 {
        restoreAttempts = attempt
        selected = currentSource()
        if selected.flatMap({ stringProperty($0, sourceIDKey) }) == usID { break }
        Thread.sleep(forTimeInterval: 0.1)
    }

    let targets = allSources().filter {
        stringProperty($0, bundleIDKey) == bundleID
    }
    let disableResults = targets.map { target -> [String: Any] in
        let before = summary(target)
        let status = TISDisableInputSource(target)
        return ["sourceBefore": before, "disableStatus": status]
    }

    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    let terminateRequested = running.map { $0.terminate() }.filter { $0 }.count
    Thread.sleep(forTimeInterval: 0.5)
    let remaining = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    let forceTerminateRequested = remaining.map { $0.forceTerminate() }.filter { $0 }.count
    Thread.sleep(forTimeInterval: 0.5)

    let current = currentSource()
    let restored = current.flatMap { stringProperty($0, sourceIDKey) } == usID
    let success = restoreSelectStatus == noErr && restored
    let value: [String: Any] = [
        "timestamp": timestamp(),
        "success": success,
        "bundleID": bundleID,
        "restoreEnableStatus": restoreEnableStatus as Any,
        "restoreSelectStatus": restoreSelectStatus as Any,
        "restoreAttempts": restoreAttempts,
        "selectedSourceAfter": summary(current),
        "targetCount": targets.count,
        "disableResults": disableResults,
        "terminateRequested": terminateRequested,
        "forceTerminateRequested": forceTerminateRequested,
    ]
    try writeJSON(value, path: outputPath)
    printJSON(value)
    return success ? 0 : 4
}

private func usage() -> Never {
    fputs(
        "usage: ThirdPartySourceHelper session OUT | sources OUT | install-select APP BUNDLE MODE STATE RESULT | post-key KEYCODE LABEL OUT | cleanup-sources BUNDLE OUT\n",
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
    case "sources" where arguments.count == 3:
        try snapshot(outputPath: arguments[2])
        status = 0
    case "install-select" where arguments.count == 7:
        status = try installAndSelect(
            appPath: arguments[2], bundleID: arguments[3], modeID: arguments[4],
            statePath: arguments[5], resultPath: arguments[6]
        )
    case "post-key" where arguments.count == 5:
        guard let keyCode = UInt16(arguments[2]) else { usage() }
        status = try postKey(
            keyCode: keyCode, label: arguments[3], outputPath: arguments[4]
        )
    case "cleanup-sources" where arguments.count == 4:
        status = try cleanupSources(bundleID: arguments[2], outputPath: arguments[3])
    default:
        usage()
    }
    exit(status)
} catch {
    fputs("ThirdPartySourceHelper error: \(error)\n", stderr)
    exit(70)
}
