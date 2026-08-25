import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import SystemConfiguration

private let inputSourceIDKey = kTISPropertyInputSourceID!
private let bundleIDKey = kTISPropertyBundleID!
private let localizedNameKey = kTISPropertyLocalizedName!
private let categoryKey = kTISPropertyInputSourceCategory!
private let typeKey = kTISPropertyInputSourceType!
private let inputModeIDKey = kTISPropertyInputModeID!

private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

private func allInputSources() -> [TISInputSource] {
    guard let unmanaged = TISCreateInputSourceList(nil, true) else { return [] }
    let values = unmanaged.takeRetainedValue() as NSArray
    return values.map { $0 as! TISInputSource }
}

private func source(matchingID inputSourceID: String) -> TISInputSource? {
    allInputSources().first {
        stringProperty($0, inputSourceIDKey) == inputSourceID
    }
}

private func source(matchingBundleID bundleID: String, modeID: String) -> TISInputSource? {
    let sources = allInputSources()
    let exactMode = sources.first {
        stringProperty($0, inputSourceIDKey) == modeID
            || stringProperty($0, inputModeIDKey) == modeID
    }
    return exactMode ?? sources.first {
        stringProperty($0, bundleIDKey) == bundleID
            && stringProperty($0, typeKey) == (kTISTypeKeyboardInputMode as String)
    }
}

private func sourceSummary(_ source: TISInputSource?) -> [String: Any] {
    guard let source else { return ["present": false] }
    return [
        "present": true,
        "inputSourceID": stringProperty(source, inputSourceIDKey) as Any,
        "bundleID": stringProperty(source, bundleIDKey) as Any,
        "inputModeID": stringProperty(source, inputModeIDKey) as Any,
        "localizedName": stringProperty(source, localizedNameKey) as Any,
        "category": stringProperty(source, categoryKey) as Any,
        "type": stringProperty(source, typeKey) as Any,
    ]
}

private func currentKeyboardInputSource() -> TISInputSource? {
    guard let unmanaged = TISCopyCurrentKeyboardInputSource() else { return nil }
    return unmanaged.takeRetainedValue()
}

private func isoTimestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func writeJSON(_ value: Any, to path: String) throws {
    guard JSONSerialization.isValidJSONObject(value) else {
        throw NSError(
            domain: "HostedIMKProbe", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid JSON object"]
        )
    }
    let data = try JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys]
    )
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

private func readJSON(_ path: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: path),
        let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }
    return value
}

private func printJSON(_ value: Any) {
    guard let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys]
    ), let string = String(data: data, encoding: .utf8) else {
        return
    }
    print(string)
}

private func runSessionProbe(outputPath: String) throws {
    let sessionDictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
    let serializableSession = sessionDictionary?.reduce(into: [String: String]()) {
        $0[String(describing: $1.key)] = String(describing: $1.value)
    } ?? [:]
    let consoleUser = SCDynamicStoreCopyConsoleUser(nil, nil, nil) as String?
    let screens = NSScreen.screens.enumerated().map { index, screen in
        [
            "index": index,
            "frame": NSStringFromRect(screen.frame),
            "visibleFrame": NSStringFromRect(screen.visibleFrame),
            "backingScaleFactor": screen.backingScaleFactor,
        ] as [String: Any]
    }
    let value: [String: Any] = [
        "timestamp": isoTimestamp(),
        "processUser": NSUserName(),
        "uid": getuid(),
        "consoleUser": consoleUser as Any,
        "hasAquaSessionDictionary": sessionDictionary != nil,
        "sessionDictionary": serializableSession,
        "screenCount": screens.count,
        "screens": screens,
        "mainDisplayID": CGMainDisplayID(),
        "accessibilityTrusted": AXIsProcessTrusted(),
        "cgEventPostPreflight": CGPreflightPostEventAccess(),
        "cgEventListenPreflight": CGPreflightListenEventAccess(),
    ]
    try writeJSON(value, to: outputPath)
    printJSON(value)
}

private func runInputSourceSnapshot(outputPath: String) throws {
    let sources = allInputSources().map(sourceSummary)
    let value: [String: Any] = [
        "timestamp": isoTimestamp(),
        "current": sourceSummary(currentKeyboardInputSource()),
        "sourceCount": sources.count,
        "sources": sources,
    ]
    try writeJSON(value, to: outputPath)
    printJSON([
        "timestamp": value["timestamp"] as Any,
        "current": value["current"] as Any,
        "sourceCount": sources.count,
        "outputPath": outputPath,
    ])
}

private func runInstallAndSelect(
    appPath: String,
    bundleID: String,
    modeID: String,
    statePath: String,
    resultPath: String
) throws -> Int32 {
    let prior = currentKeyboardInputSource()
    var state: [String: Any] = [
        "schemaVersion": 1,
        "createdAt": isoTimestamp(),
        "appPath": appPath,
        "bundleID": bundleID,
        "modeID": modeID,
        "priorSource": sourceSummary(prior),
        "registrationAttempted": false,
        "selectionAttempted": false,
    ]
    try writeJSON(state, to: statePath)

    state["registrationAttempted"] = true
    try writeJSON(state, to: statePath)
    let registrationStatus = TISRegisterInputSource(
        URL(fileURLWithPath: appPath) as CFURL
    )

    var probeSource: TISInputSource?
    for _ in 0..<50 {
        probeSource = source(matchingBundleID: bundleID, modeID: modeID)
        if probeSource != nil { break }
        Thread.sleep(forTimeInterval: 0.1)
    }

    var enableStatus: OSStatus?
    var selectionStatus: OSStatus?
    if let probeSource {
        enableStatus = TISEnableInputSource(probeSource)
        state["selectionAttempted"] = true
        try writeJSON(state, to: statePath)
    }

    let expectedSelectedID = probeSource.flatMap {
        stringProperty($0, inputSourceIDKey)
    }
    var selected = currentKeyboardInputSource()
    if let probeSource {
        for _ in 0..<120 {
            selectionStatus = TISSelectInputSource(probeSource)
            selected = currentKeyboardInputSource()
            let selectedID = selected.flatMap { stringProperty($0, inputSourceIDKey) }
            if selectedID == expectedSelectedID { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    let selectedID = selected.flatMap { stringProperty($0, inputSourceIDKey) }
    let selectionVerified = expectedSelectedID != nil && selectedID == expectedSelectedID
    let success = registrationStatus == noErr
        && probeSource != nil
        && enableStatus == noErr
        && selectionStatus == noErr
        && selectionVerified
    let result: [String: Any] = [
        "timestamp": isoTimestamp(),
        "success": success,
        "appPath": appPath,
        "bundleID": bundleID,
        "modeID": modeID,
        "priorSource": sourceSummary(prior),
        "registrationStatus": registrationStatus,
        "probeSource": sourceSummary(probeSource),
        "enableStatus": enableStatus as Any,
        "selectionStatus": selectionStatus as Any,
        "expectedSelectedInputSourceID": expectedSelectedID as Any,
        "selectedSource": sourceSummary(selected),
        "selectionVerified": selectionVerified,
    ]
    state["registrationStatus"] = registrationStatus
    state["selectionStatus"] = selectionStatus as Any
    state["selectionVerified"] = selectionVerified
    try writeJSON(state, to: statePath)
    try writeJSON(result, to: resultPath)
    printJSON(result)
    return success ? 0 : 2
}

private func runCleanup(
    statePath: String,
    bundleID: String,
    modeID: String,
    appPath: String,
    resultPath: String
) throws -> Int32 {
    let state = readJSON(statePath)
    let selectionAttempted = state?["selectionAttempted"] as? Bool ?? false
    let priorSource = state?["priorSource"] as? [String: Any]
    let priorID = priorSource?["inputSourceID"] as? String

    var restoreStatus: OSStatus?
    var restoreVerified = !selectionAttempted
    if selectionAttempted, let priorID, let prior = source(matchingID: priorID) {
        _ = TISEnableInputSource(prior)
        restoreStatus = TISSelectInputSource(prior)
        for _ in 0..<50 {
            let currentID = currentKeyboardInputSource().flatMap {
                stringProperty($0, inputSourceIDKey)
            }
            if currentID == priorID {
                restoreVerified = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    let probeSource = source(matchingBundleID: bundleID, modeID: modeID)
    let disableStatus = probeSource.map(TISDisableInputSource)

    let runningApplications = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleID
    )
    let terminateRequested = runningApplications.map { $0.terminate() }.filter { $0 }.count
    Thread.sleep(forTimeInterval: 0.5)
    let remainingApplications = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleID
    )
    let forceTerminateRequested = remainingApplications.map { $0.forceTerminate() }.filter { $0 }.count

    let standardizedPath = URL(fileURLWithPath: appPath).standardizedFileURL.path
    let expectedParent = URL(
        fileURLWithPath: NSHomeDirectory()
    ).appendingPathComponent("Library/Input Methods").standardizedFileURL.path
    let safePath = URL(fileURLWithPath: standardizedPath).deletingLastPathComponent().path == expectedParent
        && URL(fileURLWithPath: standardizedPath).lastPathComponent == "UnicornHostedIMKProbe.app"

    var removeError: String?
    if safePath && FileManager.default.fileExists(atPath: standardizedPath) {
        do {
            try FileManager.default.removeItem(atPath: standardizedPath)
        } catch {
            removeError = String(describing: error)
        }
    }
    let appExistsAfter = FileManager.default.fileExists(atPath: standardizedPath)
    let current = currentKeyboardInputSource()
    let currentBundleID = current.flatMap { stringProperty($0, bundleIDKey) }
    let currentModeID = current.flatMap { stringProperty($0, inputModeIDKey) }
    let probeNotSelected = currentBundleID != bundleID && currentModeID != modeID
    let success = restoreVerified && safePath && !appExistsAfter && probeNotSelected

    let result: [String: Any] = [
        "timestamp": isoTimestamp(),
        "success": success,
        "stateWasPresent": state != nil,
        "selectionAttempted": selectionAttempted,
        "priorInputSourceID": priorID as Any,
        "restoreStatus": restoreStatus as Any,
        "restoreVerified": restoreVerified,
        "probeSourceBeforeDisable": sourceSummary(probeSource),
        "disableStatus": disableStatus as Any,
        "terminateRequested": terminateRequested,
        "forceTerminateRequested": forceTerminateRequested,
        "safePath": safePath,
        "appPath": standardizedPath,
        "removeError": removeError as Any,
        "appExistsAfter": appExistsAfter,
        "selectedSourceAfter": sourceSummary(current),
        "probeNotSelected": probeNotSelected,
    ]
    try writeJSON(result, to: resultPath)
    printJSON(result)
    return success ? 0 : 3
}

private func runCGEventKeys(outputPath: String) throws -> Int32 {
    let preflight = CGPreflightPostEventAccess()
    var result: [String: Any] = [
        "timestamp": isoTimestamp(),
        "attempted": true,
        "accessibilityTrusted": AXIsProcessTrusted(),
        "cgEventPostPreflight": preflight,
        "posted": false,
        "keys": ["backslash", "l", "enter"],
    ]
    guard preflight else {
        result["error"] = "Accessibility denied hardware-style event posting"
        try writeJSON(result, to: outputPath)
        printJSON(result)
        return 4
    }
    guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
        result["error"] = "Unable to create CGEventSource"
        try writeJSON(result, to: outputPath)
        printJSON(result)
        return 5
    }

    for keyCode: CGKeyCode in [42, 37, 36] {
        guard let keyDown = CGEvent(
            keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false
        ) else {
            result["error"] = "Unable to create keyboard CGEvent"
            try writeJSON(result, to: outputPath)
            printJSON(result)
            return 6
        }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.2)
    }

    result["posted"] = true
    result["completedAt"] = isoTimestamp()
    try writeJSON(result, to: outputPath)
    printJSON(result)
    return 0
}

private func usage() -> Never {
    fputs(
        "usage: ProbeHelper session OUTPUT | sources OUTPUT | install-select APP BUNDLE MODE STATE RESULT | cleanup STATE BUNDLE MODE APP RESULT | cg-keys OUTPUT\n",
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
        try runSessionProbe(outputPath: arguments[2])
        status = 0
    case "sources" where arguments.count == 3:
        try runInputSourceSnapshot(outputPath: arguments[2])
        status = 0
    case "install-select" where arguments.count == 7:
        status = try runInstallAndSelect(
            appPath: arguments[2], bundleID: arguments[3], modeID: arguments[4],
            statePath: arguments[5], resultPath: arguments[6]
        )
    case "cleanup" where arguments.count == 7:
        status = try runCleanup(
            statePath: arguments[2], bundleID: arguments[3], modeID: arguments[4],
            appPath: arguments[5], resultPath: arguments[6]
        )
    case "cg-keys" where arguments.count == 3:
        status = try runCGEventKeys(outputPath: arguments[2])
    default:
        usage()
    }
    exit(status)
} catch {
    fputs("ProbeHelper error: \(error)\n", stderr)
    exit(70)
}
