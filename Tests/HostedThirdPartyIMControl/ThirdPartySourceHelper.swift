import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import SystemConfiguration

private let dvorakID = "com.apple.keylayout.Dvorak"
private let usID = "com.apple.keylayout.US"
private let squirrelBundleID = "im.rime.inputmethod.Squirrel"
private let squirrelParentID = "im.rime.inputmethod.Squirrel"
private let squirrelModeID = "im.rime.inputmethod.Squirrel.Hans"

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

private func jsonValue(_ value: String?) -> Any {
    value ?? NSNull()
}

private func jsonValue(_ value: Bool?) -> Any {
    value ?? NSNull()
}

private func jsonValue(_ value: OSStatus?) -> Any {
    value ?? NSNull()
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
        "type": jsonValue(stringProperty(source, typeKey)),
        "category": jsonValue(stringProperty(source, categoryKey)),
        "selectCapable": jsonValue(boolProperty(source, selectCapableKey)),
        "enabled": jsonValue(boolProperty(source, enabledKey)),
        "enableCapable": jsonValue(boolProperty(source, enableCapableKey)),
        "selected": jsonValue(boolProperty(source, selectedKey)),
        "asciiCapable": jsonValue(boolProperty(source, asciiCapableKey)),
    ]
}

private func sourceRole(_ source: TISInputSource) -> String {
    let identifier = stringProperty(source, sourceIDKey)
    let bundleID = stringProperty(source, bundleIDKey)
    let type = stringProperty(source, typeKey)
    if identifier == dvorakID && type == layoutType { return "dvorak-layout" }
    if bundleID == squirrelBundleID && type == parentType {
        return "squirrel-input-method-parent"
    }
    if bundleID == squirrelBundleID && type == modeType { return "squirrel-input-mode" }
    return "unexpected-relevant-source-type"
}

private func relevantSources(from sources: [TISInputSource]) -> [TISInputSource] {
    sources.filter {
        stringProperty($0, sourceIDKey) == dvorakID
            || stringProperty($0, bundleIDKey) == squirrelBundleID
    }.sorted {
        let lhs = stringProperty($0, sourceIDKey) ?? ""
        let rhs = stringProperty($1, sourceIDKey) ?? ""
        if lhs != rhs { return lhs < rhs }
        return (stringProperty($0, typeKey) ?? "") < (stringProperty($1, typeKey) ?? "")
    }
}

private func exactMatches(
    in sources: [TISInputSource], identifier: String, expectedType: String
) -> [TISInputSource] {
    sources.filter {
        stringProperty($0, sourceIDKey) == identifier
            && stringProperty($0, typeKey) == expectedType
    }
}

private func relationshipSummary(
    parents: [TISInputSource], modes: [TISInputSource]
) -> [[String: Any]] {
    modes.map { mode in
        let modeSourceID = stringProperty(mode, sourceIDKey)
        let modeInputModeID = stringProperty(mode, inputModeIDKey)
        let modeBundleID = stringProperty(mode, bundleIDKey)
        let candidates = parents.filter { parent in
            guard let parentSourceID = stringProperty(parent, sourceIDKey) else {
                return false
            }
            let identifiers = [modeSourceID, modeInputModeID].compactMap { $0 }
            return stringProperty(parent, bundleIDKey) == modeBundleID
                && identifiers.contains { $0.hasPrefix(parentSourceID + ".") }
        }
        return [
            "modeSourceID": jsonValue(modeSourceID),
            "modeInputModeID": jsonValue(modeInputModeID),
            "documentedModeType": stringProperty(mode, typeKey) == modeType,
            "parentCandidateIDs": candidates.compactMap {
                stringProperty($0, sourceIDKey)
            },
            "uniqueParentEstablished": candidates.count == 1,
        ]
    }
}

private func prerequisites(
    sources: [TISInputSource], targetID: String, expectedType: String,
    parentID: String? = nil
) -> [String: Any] {
    let targets = exactMatches(in: sources, identifier: targetID, expectedType: expectedType)
    let target = targets.count == 1 ? targets[0] : nil
    var result: [String: Any] = [
        "targetID": targetID,
        "expectedType": expectedType,
        "exactTargetCount": targets.count,
        "exactTargetUnique": targets.count == 1,
        "targetSelectCapableIsTrue": target.flatMap {
            boolProperty($0, selectCapableKey)
        } == true,
        "targetEnabledIsTrue": target.flatMap {
            boolProperty($0, enabledKey)
        } == true,
    ]
    var allSatisfied = targets.count == 1
        && target.flatMap { boolProperty($0, selectCapableKey) } == true
        && target.flatMap { boolProperty($0, enabledKey) } == true

    if let parentID {
        let parents = exactMatches(in: sources, identifier: parentID, expectedType: parentType)
        let parent = parents.count == 1 ? parents[0] : nil
        let relationshipEstablished: Bool
        if let target, let parent,
            let targetSourceID = stringProperty(target, sourceIDKey),
            let targetBundleID = stringProperty(target, bundleIDKey),
            let parentSourceID = stringProperty(parent, sourceIDKey)
        {
            relationshipEstablished = targetBundleID == stringProperty(parent, bundleIDKey)
                && targetSourceID.hasPrefix(parentSourceID + ".")
        } else {
            relationshipEstablished = false
        }
        result["parentID"] = parentID
        result["parentExpectedType"] = parentType
        result["exactParentCount"] = parents.count
        result["exactParentUnique"] = parents.count == 1
        result["parentEnabledIsTrue"] = parent.flatMap {
            boolProperty($0, enabledKey)
        } == true
        result["parentModeRelationshipEstablished"] = relationshipEstablished
        allSatisfied = allSatisfied
            && parents.count == 1
            && parent.flatMap { boolProperty($0, enabledKey) } == true
            && relationshipEstablished
    }
    result["allDocumentedSelectionPrerequisitesSatisfied"] = allSatisfied
    return result
}

private func snapshotValue(label: String) -> [String: Any] {
    let sources = allSources()
    let relevant = relevantSources(from: sources)
    let squirrel = relevant.filter {
        stringProperty($0, bundleIDKey) == squirrelBundleID
    }
    let parents = squirrel.filter { stringProperty($0, typeKey) == parentType }
    let modes = squirrel.filter { stringProperty($0, typeKey) == modeType }
    return [
        "schemaVersion": 2,
        "timestamp": timestamp(),
        "label": label,
        "current": sourceSummary(currentSource()),
        "relevantSourceCount": relevant.count,
        "sources": relevant.map { source in
            var summary = sourceSummary(source)
            summary["role"] = sourceRole(source)
            return summary
        },
        "enumeration": [
            "dvorakCount": relevant.filter {
                stringProperty($0, sourceIDKey) == dvorakID
            }.count,
            "squirrelParentCount": parents.count,
            "squirrelModeCount": modes.count,
            "squirrelUnexpectedTypeCount": squirrel.count - parents.count - modes.count,
            "squirrelParentModeRelationships": relationshipSummary(
                parents: parents, modes: modes
            ),
        ],
        "intendedSources": [
            "dvorakID": dvorakID,
            "squirrelParentID": squirrelParentID,
            "squirrelModeID": squirrelModeID,
        ],
        "documentedSelectionContract": [
            "paramErr": paramErr,
            "paramErrMeaning": "the source is not selectable",
            "requiredTargetProperties": [
                "kTISPropertyInputSourceIsSelectCapable == true",
                "kTISPropertyInputSourceIsEnabled == true",
            ],
            "inputModeAdditionalRequirement": "an enabled parent input method",
        ],
        "prerequisites": [
            "dvorak": prerequisites(
                sources: sources, targetID: dvorakID, expectedType: layoutType
            ),
            "squirrelHans": prerequisites(
                sources: sources, targetID: squirrelModeID, expectedType: modeType,
                parentID: squirrelParentID
            ),
        ],
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

private func readJSON(path: String) -> [String: Any] {
    guard let data = FileManager.default.contents(atPath: path),
        let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return value
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
        "relevantSourceCount": value["relevantSourceCount"] as Any,
    ])
}

private func register(appPath: String, outputPath: String) throws -> Int32 {
    let startedAt = timestamp()
    let before = snapshotValue(label: "immediately-before-registration")
    let status = TISRegisterInputSource(URL(fileURLWithPath: appPath) as CFURL)
    let afterImmediate = snapshotValue(label: "immediately-after-registration")
    var attempts = 0
    for attempt in 1...50 {
        attempts = attempt
        let sources = allSources()
        if exactMatches(in: sources, identifier: squirrelParentID, expectedType: parentType).count == 1,
            exactMatches(in: sources, identifier: squirrelModeID, expectedType: modeType).count == 1
        {
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    let result: [String: Any] = [
        "schemaVersion": 2,
        "operation": "TISRegisterInputSource",
        "startedAt": startedAt,
        "completedAt": timestamp(),
        "appPath": appPath,
        "status": status,
        "before": before,
        "afterImmediate": afterImmediate,
        "refreshAttempts": attempts,
        "after": snapshotValue(label: "after-registration-and-live-refresh"),
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return 0
}

private func enable(
    targetID: String, expectedType: String, outputPath: String
) throws -> Int32 {
    let startedAt = timestamp()
    let before = snapshotValue(label: "immediately-before-enable-\(targetID)")
    let matches = exactMatches(
        in: allSources(), identifier: targetID, expectedType: expectedType
    )
    var status: OSStatus?
    if matches.count == 1 {
        status = TISEnableInputSource(matches[0])
    }
    let afterImmediate = snapshotValue(label: "immediately-after-enable-\(targetID)")
    var refreshAttempts = 0
    if status != nil {
        for attempt in 1...30 {
            refreshAttempts = attempt
            let refreshed = exactMatches(
                in: allSources(), identifier: targetID, expectedType: expectedType
            )
            if refreshed.count == 1,
                boolProperty(refreshed[0], enabledKey) == true
            {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    let result: [String: Any] = [
        "schemaVersion": 2,
        "operation": "TISEnableInputSource",
        "startedAt": startedAt,
        "completedAt": timestamp(),
        "targetID": targetID,
        "expectedType": expectedType,
        "exactTargetCount": matches.count,
        "operationPerformed": matches.count == 1,
        "status": jsonValue(status),
        "before": before,
        "afterImmediate": afterImmediate,
        "refreshAttempts": refreshAttempts,
        "after": snapshotValue(label: "after-enable-and-live-refresh-\(targetID)"),
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return matches.count == 1 ? 0 : 2
}

private func select(
    targetID: String, expectedType: String, parentID: String?, outputPath: String
) throws -> Int32 {
    let startedAt = timestamp()
    let before = snapshotValue(label: "immediately-before-select-\(targetID)")
    let sources = allSources()
    let matches = exactMatches(
        in: sources, identifier: targetID, expectedType: expectedType
    )
    let contractBefore = prerequisites(
        sources: sources, targetID: targetID, expectedType: expectedType,
        parentID: parentID
    )
    var status: OSStatus?
    if matches.count == 1 {
        status = TISSelectInputSource(matches[0])
    }
    let afterImmediate = snapshotValue(label: "immediately-after-select-\(targetID)")
    var observationAttempts = 0
    for attempt in 1...20 {
        observationAttempts = attempt
        if currentSource().flatMap({ stringProperty($0, sourceIDKey) }) == targetID {
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    let after = snapshotValue(label: "after-select-and-live-refresh-\(targetID)")
    let selectedID = (after["current"] as? [String: Any])?["inputSourceID"] as? String
    let result: [String: Any] = [
        "schemaVersion": 2,
        "operation": "TISSelectInputSource",
        "startedAt": startedAt,
        "completedAt": timestamp(),
        "targetID": targetID,
        "expectedType": expectedType,
        "parentID": parentID ?? NSNull(),
        "exactTargetCount": matches.count,
        "operationPerformed": matches.count == 1,
        "documentedPrerequisitesImmediatelyBefore": contractBefore,
        "status": jsonValue(status),
        "paramErrMeansSourceIsNotSelectable": status.map { $0 == paramErr } ?? false,
        "before": before,
        "afterImmediate": afterImmediate,
        "observationAttempts": observationAttempts,
        "after": after,
        "selectionVerified": selectedID == targetID,
    ]
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return matches.count == 1 ? 0 : 2
}

private func axValue(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return value
}

private func axString(_ element: AXUIElement, attribute: CFString) -> String? {
    axValue(element, attribute: attribute) as? String
}

private func axBool(_ element: AXUIElement, attribute: CFString) -> Bool? {
    guard let number = axValue(element, attribute: attribute) as? NSNumber else {
        return nil
    }
    return number.boolValue
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    guard let values = axValue(element, attribute: kAXChildrenAttribute as CFString)
        as? [AXUIElement]
    else { return [] }
    return values
}

private func axSummary(
    _ element: AXUIElement, bundleID: String
) -> [String: Any] {
    var actions: CFArray?
    let actionStatus = AXUIElementCopyActionNames(element, &actions)
    return [
        "bundleID": bundleID,
        "role": jsonValue(axString(element, attribute: kAXRoleAttribute as CFString)),
        "subrole": jsonValue(axString(element, attribute: kAXSubroleAttribute as CFString)),
        "identifier": jsonValue(
            axString(element, attribute: kAXIdentifierAttribute as CFString)
        ),
        "title": jsonValue(axString(element, attribute: kAXTitleAttribute as CFString)),
        "description": jsonValue(
            axString(element, attribute: kAXDescriptionAttribute as CFString)
        ),
        "value": jsonValue(axString(element, attribute: kAXValueAttribute as CFString)),
        "enabled": jsonValue(axBool(element, attribute: kAXEnabledAttribute as CFString)),
        "actionCopyStatus": actionStatus.rawValue,
        "actions": (actions as? [String]) ?? [],
    ]
}

private struct AXNode {
    let element: AXUIElement
    let bundleID: String
}

private func appendAXTree(
    element: AXUIElement, bundleID: String, depth: Int,
    maximumDepth: Int, maximumCount: Int, nodes: inout [AXNode]
) {
    guard depth <= maximumDepth, nodes.count < maximumCount else { return }
    nodes.append(AXNode(element: element, bundleID: bundleID))
    for child in axChildren(element) where nodes.count < maximumCount {
        appendAXTree(
            element: child, bundleID: bundleID, depth: depth + 1,
            maximumDepth: maximumDepth, maximumCount: maximumCount, nodes: &nodes
        )
    }
}

private func inputMenuAXNodes() -> (nodes: [AXNode], applications: [[String: Any]]) {
    let bundleIDs = [
        "com.apple.TextInputMenuAgent",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
    ]
    var nodes: [AXNode] = []
    var applications: [[String: Any]] = []
    for bundleID in bundleIDs {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        )
        applications.append([
            "bundleID": bundleID,
            "runningApplicationCount": running.count,
            "processIdentifiers": running.map { $0.processIdentifier },
        ])
        for application in running {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            if let menuBarValue = axValue(
                root, attribute: kAXMenuBarAttribute as CFString
            ) {
                appendAXTree(
                    element: menuBarValue as! AXUIElement, bundleID: bundleID, depth: 0,
                    maximumDepth: 8, maximumCount: 1_000, nodes: &nodes
                )
            } else {
                appendAXTree(
                    element: root, bundleID: bundleID, depth: 0,
                    maximumDepth: 8, maximumCount: 1_000, nodes: &nodes
                )
            }
        }
    }
    return (nodes, applications)
}

private func axSemanticValues(_ element: AXUIElement) -> [String] {
    [
        axString(element, attribute: kAXIdentifierAttribute as CFString),
        axString(element, attribute: kAXTitleAttribute as CFString),
        axString(element, attribute: kAXDescriptionAttribute as CFString),
        axString(element, attribute: kAXValueAttribute as CFString),
    ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func uniqueAXCandidate(
    nodes: [AXNode], role: String, exactValues: [String]
) -> (node: AXNode?, rule: String) {
    let roleNodes = nodes.filter {
        axString($0.element, attribute: kAXRoleAttribute as CFString) == role
    }
    for expected in exactValues {
        let matches = roleNodes.filter { node in
            axSemanticValues(node.element).contains {
                $0.compare(expected, options: [.caseInsensitive]) == .orderedSame
            }
        }
        if matches.count == 1 {
            return (matches[0], "unique-exact-semantic-value:\(expected)")
        }
        if matches.count > 1 {
            return (nil, "ambiguous-exact-semantic-value:\(expected):\(matches.count)")
        }
    }
    return (nil, "no-exact-semantic-value-match")
}

private func menuSelect(
    targetID: String, targetName: String, currentName: String, outputPath: String
) throws -> Int32 {
    let startedAt = timestamp()
    var result: [String: Any] = [
        "schemaVersion": 2,
        "operation": "semantic Accessibility selection through the macOS input menu",
        "attempted": true,
        "startedAt": startedAt,
        "targetID": targetID,
        "targetName": targetName,
        "currentName": currentName,
        "accessibilityTrusted": AXIsProcessTrusted(),
        "usesOCRPixelsOrCoordinates": false,
        "targetPressed": false,
        "selectionVerified": false,
    ]

    let initial = inputMenuAXNodes()
    result["applications"] = initial.applications
    let menuBarNodes = initial.nodes.filter {
        axString($0.element, attribute: kAXRoleAttribute as CFString)
            == (kAXMenuBarItemRole as String)
    }
    result["menuBarCandidates"] = menuBarNodes.map {
        axSummary($0.element, bundleID: $0.bundleID)
    }
    let inputMenu = uniqueAXCandidate(
        nodes: menuBarNodes,
        role: kAXMenuBarItemRole as String,
        exactValues: [
            "com.apple.menuextra.textinput",
            "com.apple.TextInputMenuAgent",
            "Input menu",
            "Text Input menu",
            currentName,
        ]
    )
    result["menuBarMatchRule"] = inputMenu.rule
    guard let inputMenuNode = inputMenu.node else {
        result["completedAt"] = timestamp()
        result["error"] = "Input menu bar item did not have one exact semantic match"
        result["sourceAfterIncompleteAttempt"] = snapshotValue(
            label: "after-incomplete-menu-selection-\(targetID)"
        )
        try writeJSON(result, path: outputPath)
        printJSON(result)
        return 0
    }

    let openStatus = AXUIElementPerformAction(
        inputMenuNode.element, kAXPressAction as CFString
    )
    result["inputMenuOpenActionStatus"] = openStatus.rawValue
    guard openStatus == .success else {
        result["completedAt"] = timestamp()
        result["error"] = "Accessibility press on the exact input menu bar item failed"
        result["sourceAfterIncompleteAttempt"] = snapshotValue(
            label: "after-incomplete-menu-selection-\(targetID)"
        )
        try writeJSON(result, path: outputPath)
        printJSON(result)
        return 0
    }
    Thread.sleep(forTimeInterval: 0.5)

    let opened = inputMenuAXNodes()
    let menuItemNodes = opened.nodes.filter {
        axString($0.element, attribute: kAXRoleAttribute as CFString)
            == (kAXMenuItemRole as String)
    }
    result["menuItemCandidates"] = menuItemNodes.map {
        axSummary($0.element, bundleID: $0.bundleID)
    }
    let target = uniqueAXCandidate(
        nodes: menuItemNodes,
        role: kAXMenuItemRole as String,
        exactValues: [targetName]
    )
    result["targetMatchRule"] = target.rule
    guard let targetNode = target.node,
        axBool(targetNode.element, attribute: kAXEnabledAttribute as CFString) == true
    else {
        result["completedAt"] = timestamp()
        result["error"] = "Intended source did not have one exact enabled semantic menu item"
        result["sourceAfterIncompleteAttempt"] = snapshotValue(
            label: "after-incomplete-menu-selection-\(targetID)"
        )
        try writeJSON(result, path: outputPath)
        printJSON(result)
        return 0
    }

    result["targetElement"] = axSummary(
        targetNode.element, bundleID: targetNode.bundleID
    )
    result["sourceImmediatelyBeforeTargetPress"] = snapshotValue(
        label: "immediately-before-menu-selection-\(targetID)"
    )
    result["targetPressStartedAt"] = timestamp()
    let targetStatus = AXUIElementPerformAction(
        targetNode.element, kAXPressAction as CFString
    )
    result["targetPressStatus"] = targetStatus.rawValue
    result["targetPressed"] = targetStatus == .success
    result["targetPressCompletedAt"] = timestamp()
    result["sourceImmediatelyAfterTargetPress"] = snapshotValue(
        label: "immediately-after-menu-selection-\(targetID)"
    )
    let selectedID = currentSource().flatMap { stringProperty($0, sourceIDKey) }
    result["selectionVerified"] = selectedID == targetID
    result["completedAt"] = timestamp()
    try writeJSON(result, path: outputPath)
    printJSON(result)
    return 0
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
        let down = CGEvent(
            keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true
        ),
        let up = CGEvent(
            keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false
        )
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

private func cleanupSources(statePath: String, outputPath: String) throws -> Int32 {
    let state = readJSON(path: statePath)
    let dvorakInitiallyEnabled = state["dvorakInitiallyEnabled"] as? Bool ?? false
    let originalSourceID = state["initialCurrentSourceID"] as? String ?? usID
    let originalSourceType = state["initialCurrentSourceType"] as? String ?? layoutType
    let before = snapshotValue(label: "immediately-before-cleanup")

    let originalMatches = exactMatches(
        in: allSources(), identifier: originalSourceID, expectedType: originalSourceType
    )
    let restoreEnableStatus = originalMatches.count == 1
        ? TISEnableInputSource(originalMatches[0]) : nil
    let refreshedOriginal = exactMatches(
        in: allSources(), identifier: originalSourceID, expectedType: originalSourceType
    )
    let restoreSelectStatus = refreshedOriginal.count == 1
        ? TISSelectInputSource(refreshedOriginal[0]) : nil
    Thread.sleep(forTimeInterval: 0.3)

    let squirrelTargets = allSources().filter {
        stringProperty($0, bundleIDKey) == squirrelBundleID
            && [modeType, parentType].contains(stringProperty($0, typeKey) ?? "")
    }.sorted {
        (stringProperty($0, typeKey) == modeType ? 0 : 1)
            < (stringProperty($1, typeKey) == modeType ? 0 : 1)
    }
    let squirrelDisableResults = squirrelTargets.map { source -> [String: Any] in
        let beforeSource = sourceSummary(source)
        let status = TISDisableInputSource(source)
        return ["sourceBefore": beforeSource, "disableStatus": status]
    }

    var disableRefreshAttempts = 0
    for attempt in 1...50 {
        disableRefreshAttempts = attempt
        let refreshedSquirrel = allSources().filter {
            stringProperty($0, bundleIDKey) == squirrelBundleID
                && [modeType, parentType].contains(
                    stringProperty($0, typeKey) ?? ""
                )
        }
        if refreshedSquirrel.allSatisfy({
            boolProperty($0, enabledKey) == false
        }) {
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    var dvorakDisableStatus: OSStatus?
    if !dvorakInitiallyEnabled {
        let dvorakMatches = exactMatches(
            in: allSources(), identifier: dvorakID, expectedType: layoutType
        )
        if dvorakMatches.count == 1 {
            dvorakDisableStatus = TISDisableInputSource(dvorakMatches[0])
        }
    }
    Thread.sleep(forTimeInterval: 0.3)

    let after = snapshotValue(label: "after-cleanup")
    let currentID = (after["current"] as? [String: Any])?["inputSourceID"] as? String
    let afterSources = after["sources"] as? [[String: Any]] ?? []
    let squirrelDisabled = afterSources.filter {
        ($0["bundleID"] as? String) == squirrelBundleID
    }.allSatisfy { ($0["enabled"] as? Bool) == false }
    let dvorakRestored = dvorakInitiallyEnabled
        || afterSources.first { ($0["inputSourceID"] as? String) == dvorakID }?["enabled"] as? Bool == false
    let success = restoreSelectStatus == noErr
        && currentID == originalSourceID
        && squirrelDisabled
        && dvorakRestored
    let value: [String: Any] = [
        "timestamp": timestamp(),
        "success": success,
        "dvorakInitiallyEnabled": dvorakInitiallyEnabled,
        "originalSourceID": originalSourceID,
        "originalSourceType": originalSourceType,
        "restoreEnableStatus": jsonValue(restoreEnableStatus),
        "restoreSelectStatus": jsonValue(restoreSelectStatus),
        "squirrelDisableResults": squirrelDisableResults,
        "squirrelDisableRefreshAttempts": disableRefreshAttempts,
        "dvorakDisableStatus": jsonValue(dvorakDisableStatus),
        "squirrelProcessTerminationAttemptedBySourceCleanup": false,
        "before": before,
        "after": after,
        "restoredOriginalSource": currentID == originalSourceID,
        "squirrelSourcesDisabled": squirrelDisabled,
        "dvorakStateRestored": dvorakRestored,
    ]
    try writeJSON(value, path: outputPath)
    printJSON(value)
    return success ? 0 : 4
}

private func usage() -> Never {
    fputs(
        "usage: ThirdPartySourceHelper session OUT | sources LABEL OUT | register APP OUT | enable ID TYPE OUT | select ID TYPE PARENT_OR_DASH OUT | menu-select ID NAME CURRENT_NAME OUT | post-key KEYCODE LABEL OUT | cleanup-sources STATE OUT\n",
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
    case "sources" where arguments.count == 4:
        try snapshot(label: arguments[2], outputPath: arguments[3])
        status = 0
    case "register" where arguments.count == 4:
        status = try register(appPath: arguments[2], outputPath: arguments[3])
    case "enable" where arguments.count == 5:
        status = try enable(
            targetID: arguments[2], expectedType: arguments[3], outputPath: arguments[4]
        )
    case "select" where arguments.count == 6:
        status = try select(
            targetID: arguments[2], expectedType: arguments[3],
            parentID: arguments[4] == "-" ? nil : arguments[4],
            outputPath: arguments[5]
        )
    case "menu-select" where arguments.count == 6:
        status = try menuSelect(
            targetID: arguments[2], targetName: arguments[3],
            currentName: arguments[4], outputPath: arguments[5]
        )
    case "post-key" where arguments.count == 5:
        guard let keyCode = UInt16(arguments[2]) else { usage() }
        status = try postKey(
            keyCode: keyCode, label: arguments[3], outputPath: arguments[4]
        )
    case "cleanup-sources" where arguments.count == 4:
        status = try cleanupSources(statePath: arguments[2], outputPath: arguments[3])
    default:
        usage()
    }
    exit(status)
} catch {
    fputs("ThirdPartySourceHelper error: \(error)\n", stderr)
    exit(70)
}
