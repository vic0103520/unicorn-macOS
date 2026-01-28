import Foundation

// MARK: - Test Helpers

func assertEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ message: String, file: String = #file, line: Int = #line
) {
    if actual != expected {
        print("FAIL: \(message) - Expected \(expected), got \(actual) at \(file):\(line)")
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition {
        print("FAIL: \(message) - Expected true at \(file):\(line)")
        exit(1)
    }
}

func assertFalse(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        print("FAIL: \(message) - Expected false at \(file):\(line)")
        exit(1)
    }
}

func makeEngine(json: String) -> Engine {
    guard let data = json.data(using: .utf8),
        let engine = try? Engine(jsonData: data)
    else {
        print("FAIL: Could not initialize engine with JSON: \(json)")
        exit(1)
    }
    return engine
}

// MARK: - Unit Tests

func testAccumulatingComposition() {
    print("Test: Accumulating Composition & Backspace Undo")
    let engine = makeEngine(json: "{\"l\": {\"e\": {\">>\": [\"≤\"]}}}")

    // 1. Type: \le
    var state = engine.initialState
    state = engine.reduce(state: state, keyCode: .chars("\\")).0
    state = engine.reduce(state: state, keyCode: .chars("l")).0
    let (s3, _) = engine.reduce(state: state, keyCode: .chars("e"))
    
    // Check setup state
    assertEqual(s3.buffer, "\\le", "Buffer should be \\le")
    assertEqual(s3.committedPrefix, "", "Nothing committed yet")

    // 2. Soft Commit: Type \
    // Expectation: committedPrefix becomes "≤", buffer becomes "\", active=true
    let (s4, a4) = engine.reduce(state: s3, keyCode: .chars("\\"))
    
    assertTrue(s4.active, "State should remain active")
    assertEqual(s4.committedPrefix, "≤", "committedPrefix should be ≤")
    assertEqual(s4.buffer, "\\", "Buffer should start new sequence \\")
    
    // Action should be .updateComposition("≤\") NOT .commit + .update
    if !a4.isEmpty {
        // The action payload includes prefix + buffer
        assertEqual(a4[0], EngineAction.updateComposition("≤\\"), "Should update composition with full text")
        // Ensure no hard commit happened
        for action in a4 {
            if case .commit = action {
                print("FAIL: Should not emit .commit action on soft commit")
                exit(1)
            }
        }
    }

    // 3. Backspace #1: Delete \
    // Expectation: committedPrefix "≤", buffer ""
    let (s5, a5) = engine.reduce(state: s4, keyCode: .backspace)
    assertEqual(s5.committedPrefix, "≤", "Prefix remains")
    assertEqual(s5.buffer, "", "Buffer cleared")
    assertEqual(a5[0], EngineAction.updateComposition("≤"), "Should show prefix")

    // 4. Backspace #2: Undo Soft Commit AND Delete Last Char
    // Expectation: Restore state before soft commit (\le) AND remove 'e' -> \l
    let (s6, _) = engine.reduce(state: s5, keyCode: .backspace)
    assertEqual(s6.buffer, "\\l", "Restored buffer should be \\l (popped \\le and removed e)")
    assertEqual(s6.committedPrefix, "", "Restored prefix (empty)")
    
    // 5. Redo Soft Commit
    // Type e -> \le
    let (s7, _) = engine.reduce(state: s6, keyCode: .chars("e"))
    // Type \ -> ≤\
    let (s8, _) = engine.reduce(state: s7, keyCode: .chars("\\"))
    assertEqual(s8.committedPrefix, "≤", "Redo soft commit")
    
    // 6. Hard Commit (Enter)
    // Expectation: Commit "≤\" (prefix + buffer)
    let (s9, a9) = engine.reduce(state: s8, keyCode: .enter)
    assertFalse(s9.active, "Should deactivate")
    assertEqual(a9[0], EngineAction.commit("≤\\"), "Should hard commit full text")
    assertEqual(s9.committedPrefix, "", "Prefix reset")
}

func testBasicInput() {
    print("Test: Basic Input Sequence")
    let engine = makeEngine(json: "{\"l\": {\"a\": {\">>\": [\"λ\"]}}}")

    // 1. Start: \
    let (s1, a1) = engine.reduce(
        state: engine.initialState, keyCode: .chars("\\"))
    assertTrue(s1.active, "State should be active")
    assertEqual(s1.buffer, "\\", "Buffer should be \\")
    if !a1.isEmpty {
        assertEqual(a1[0], EngineAction.updateComposition("\\"), "Action 1 mismatch")
    }

    // 2. Type: l
    let (s2, _) = engine.reduce(state: s1, keyCode: .chars("l"))
    assertEqual(s2.buffer, "\\l", "Buffer should be \\l")

    // 3. Type: a (Leaf node -> Commit)
    let (s3, a3) = engine.reduce(state: s2, keyCode: .chars("a"))
    assertFalse(s3.active, "Should deactivate after commit")
    assertEqual(s3.buffer, "", "Buffer cleared")
    if !a3.isEmpty {
        assertEqual(a3[0], EngineAction.commit("λ"), "Should commit λ")
    }
}

func testBackspace() {
    print("Test: Backspace Logic")
    let engine = makeEngine(json: "{\"l\": {\"a\": {\">>\": [\"λ\"]}}}")

    // Setup state: \l
    var state = engine.initialState
    state = engine.reduce(state: state, keyCode: .chars("\\")).0
    state = engine.reduce(state: state, keyCode: .chars("l")).0

    // 1. Backspace -> \
    let (s1, _) = engine.reduce(state: state, keyCode: .backspace)
    assertTrue(s1.active, "Should remain active")
    assertEqual(s1.buffer, "\\", "Buffer should be \\")

    // 2. Backspace -> Empty/Inactive
    let (s2, _) = engine.reduce(state: s1, keyCode: .backspace)
    assertFalse(s2.active, "Should deactivate")
    assertEqual(s2.buffer, "", "Buffer empty")
}

func testSelectionAndBackslashCommit() {
    print("Test: Selection and Backslash Restart")
    let engine = makeEngine(json: "{\"l\": {\">>\": [\"L1\", \"L2\"]}}")

    // Imperatively advance to \l to set up internal state
    _ = engine.processKey(keyCode: .chars("\\"))
    _ = engine.processKey(keyCode: .chars("l"))

    assertEqual(engine.state.candidates, ["L1", "L2"], "Candidates mismatch")

    // Select index 1 (L2)
    engine.selectCandidate(index: 1)
    assertEqual(engine.state.selectedCandidate, 1, "Selection index mismatch")

    // Commit with \
    let (sNext, actions) = engine.reduce(
        state: engine.state, keyCode: .chars("\\"))

    // Should soft-commit L2 and restart
    assertTrue(sNext.active, "Should be active (restarted)")
    assertEqual(sNext.buffer, "\\", "Buffer reset to \\")
    assertEqual(sNext.committedPrefix, "L2", "Prefix should be L2")

    // Verify actions: Should be ONE updateComposition with "L2\"
    if let action = actions.first {
        assertEqual(action, EngineAction.updateComposition("L2\\"), "Should update composition with accumulated text")
        assertEqual(actions.count, 1, "Should only have 1 action (no hard commit)")
    } else {
        print("FAIL: Expected 1 action, got 0")
        exit(1)
    }
}

func testEnterDeactivation() {
    print("Test: Enter Key Deactivation")
    let engine = makeEngine(json: "{\"l\": {\">>\": [\"L1\", \"L2\"]}}")
    // State: \l
    _ = engine.processKey(keyCode: .chars("\\"))
    _ = engine.processKey(keyCode: .chars("l"))

    let (sEnd, actions) = engine.reduce(
        state: engine.state, keyCode: .enter)  // Enter

    assertFalse(sEnd.active, "State should be inactive")
    if let act = actions.first {

        assertEqual(act, EngineAction.commit("L1"), "Should commit L1")
    }
}

func testNumericSelection() {
    print("Test: Numeric Selection (1-9)")
    let engine = makeEngine(json: "{\"l\": {\">>\": [\"A\", \"B\", \"C\"]}}")
    // State: \l
    _ = engine.processKey(keyCode: .chars("\\"))
    _ = engine.processKey(keyCode: .chars("l"))

    // Press '2' -> Commit "B"
    let (sEnd, actions) = engine.reduce(
        state: engine.state, keyCode: .chars("2"))

    assertFalse(sEnd.active, "Should deactivate")
    if let act = actions.first {
        assertEqual(act, EngineAction.commit("B"), "Should commit B")
    }
}

func testSpaceRejection() {
    print("Test: Space Rejection (Implicit Commit)")
    let engine = makeEngine(json: "{\"l\": {\">>\": [\"A\", \"B\"]}}")
    // State: \l
    _ = engine.processKey(keyCode: .chars("\\"))
    _ = engine.processKey(keyCode: .chars("l"))

    // Press Space
    let (sEnd, actions) = engine.reduce(
        state: engine.state, keyCode: .chars(" "))

    // Space is not in Trie -> Implicit Commit + Reject
    // State should be inactive (implicit commit happened)
    assertFalse(sEnd.active, "State should be inactive after implicit commit")

    // Actions should be [.commit("A"), .reject]
    if actions.count == 2 {
        assertEqual(actions[0], EngineAction.commit("A"), "First action should be commit")
        assertEqual(actions[1], EngineAction.reject, "Second action should be reject")
    } else {
        print(
            "FAIL: Expected 2 actions for implicit commit, got \(actions.count). Actions: \(actions)"
        )
        exit(1)
    }
}

func testNavigation() {
    print("Test: Arrow Navigation")
    let engine = makeEngine(json: "{\"l\": {\">>\": [\"A\", \"B\", \"C\"]}}")
    // State: \l
    _ = engine.processKey(keyCode: .chars("\\"))
    _ = engine.processKey(keyCode: .chars("l"))

    assertEqual(engine.state.selectedCandidate, 0, "Start at 0")

    // Down -> 1
    let (sDown, aDown) = engine.reduce(state: engine.state, keyCode: .down)
    assertEqual(aDown.first, EngineAction.navigate(.down), "Action navigate down")
    assertEqual(sDown.selectedCandidate, 1, "Index should be 1")

    // Up -> 0
    let (sUp, aUp) = engine.reduce(state: sDown, keyCode: .up)
    assertEqual(aUp.first, EngineAction.navigate(.up), "Action navigate up")
    assertEqual(sUp.selectedCandidate, 0, "Index should be 0")
}

func testPageNavigation() {
    print("Test: Page Navigation")
    // Create enough candidates for paging (pageSize = 9)
    let candidates = (1...20).map { "Item\($0)" }
    let jsonString = "{\"p\": {\">>\": \(candidates.description)}}"
    let engine = makeEngine(json: jsonString)

    _ = engine.processKey(keyCode: .chars("\\"))
    _ = engine.processKey(keyCode: .chars("p"))

    assertEqual(engine.state.selectedCandidate, 0, "Start 0")

    // Page Down (Right Arrow) -> Index 9 (Start of page 2)
    // Page 1: 0-8. Page 2: 9-17.
    let (sPage2, aPage2) = engine.reduce(state: engine.state, keyCode: .right)
    assertEqual(aPage2.first, EngineAction.navigate(.pageDown), "Action navigate pageDown")
    assertEqual(sPage2.candidateWindow.firstVisibleIndex, 9, "First visible should be 9")
    assertEqual(sPage2.selectedCandidate, 9, "Selected should be 9")

    // Page Down -> Index 18 (Start of page 3, items 18-19)
    let (sPage3, _) = engine.reduce(state: sPage2, keyCode: .right)
    assertEqual(sPage3.candidateWindow.firstVisibleIndex, 18, "First visible should be 18")

    // Page Up -> Index 9
    let (sBack, aBack) = engine.reduce(state: sPage3, keyCode: .left)
    assertEqual(aBack.first, EngineAction.navigate(.pageUp), "Action navigate pageUp")
    assertEqual(sBack.candidateWindow.firstVisibleIndex, 9, "First visible should be 9")
}

func testBufferOverflow() {
    print("Test: Buffer Overflow Protection (True Limit Test)")

    // 1. Construct a deep JSON Trie: l -> l -> l ... (60 times)
    // format: {"l": {"l": ... }}
    var json = "{\">>\": [\"end\"]}"
    for _ in 0..<60 {
        json = "{\"l\": \(json)}"
    }

    let engine = makeEngine(json: json)
    var state = engine.initialState

    // 2. Activate with '\'
    state = engine.reduce(state: state, keyCode: .chars("\\")).0

    // 3. Attempt to traverse the deep trie 60 times
    // valid sequence: \llllll...
    // The engine allows it because 'l' is a valid child at every step.
    // BUT our limit should stop it at 50.

    for _ in 0..<60 {
        state = engine.reduce(state: state, keyCode: .chars("l")).0
    }

    // 4. Verify
    print("Buffer length: \(state.buffer.count)")
    assertTrue(
        state.buffer.count == 50, "Buffer should be exactly 50. Actual: \(state.buffer.count)")
}

// MARK: - Main Runner

func runTests() {
    testBasicInput()
    testBackspace()
    testSelectionAndBackslashCommit()
    testEnterDeactivation()
    testNumericSelection()
    testSpaceRejection()
    testNavigation()
    testPageNavigation()
    testBufferOverflow()

    print("\nAll Engine Unit Tests Passed!")
}

runTests()
