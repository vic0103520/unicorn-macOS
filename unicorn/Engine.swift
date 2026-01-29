import Foundation

/// The core logic engine for the Unicorn Input Method.
/// It maintains a state machine that traverses a Trie of symbol sequences.
public class Engine {
    public let root: Trie
    /// The current state. This is the only mutable property in the class.
    public private(set) var state: EngineState

    private let MAX_BUFFER_LENGTH = 50
    private let MAX_HISTORY_DEPTH = 100

    public var initialState: EngineState {
        EngineState(path: [root], buffer: "", active: false, candidateWindow: .empty(), history: [])
    }

    public init(jsonData: Data) throws {
        let decoder = JSONDecoder()
        self.root = try decoder.decode(Trie.self, from: jsonData)
        self.state = EngineState(
            path: [root], buffer: "", active: false, candidateWindow: .empty(), history: [])
    }

    public static func newFromPath(path: String) throws -> Engine {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try Engine(jsonData: data)
    }

    // MARK: - Public State Mutators

    public func navigate(_ direction: CandidateNavigation) {
        let newWindow: CandidateWindow
        switch direction {
        case .up: newWindow = state.candidateWindow.movingUp()
        case .down: newWindow = state.candidateWindow.movingDown()
        case .pageUp: newWindow = state.candidateWindow.movingPageUp()
        case .pageDown: newWindow = state.candidateWindow.movingPageDown()
        }
        state = state.updating(candidateWindow: newWindow)
    }

    public func selectCandidate(index: UInt32) {
        state = state.updating(candidateWindow: state.candidateWindow.selecting(index: Int(index)))
    }

    public func deactivate() {
        state = resetState(active: false, buffer: "")
    }

    /// Imperative shell method that updates the internal state and returns actions.
    public func processKey(keyCode: KeyCode) -> [EngineAction] {
        // Activation check
        if !state.active {
            if case .chars(let s) = keyCode, s == "\\" {
                // proceed to activate
            } else {
                return []
            }
        }

        let (nextState, actions) = reduce(state: self.state, keyCode: keyCode)
        self.state = nextState
        return actions
    }

    // MARK: - Pure Functional Core

    private func resetState(active: Bool, buffer: String) -> EngineState {
        return EngineState(
            path: [root], buffer: buffer, committedPrefix: "", active: active,
            candidateWindow: .empty(), history: [])
    }

    /// Transitions to a new state while archiving the current state into the history stack.
    private func pushHistory(_ nextState: EngineState, current: EngineState) -> EngineState {
        var newHistory = current.history + [current.clearHistory()]
        if newHistory.count > MAX_HISTORY_DEPTH {
            newHistory.removeFirst()
        }
        return nextState.updating(history: newHistory)
    }

    /// Pure transition function: (State, Input) -> (NewState, [Action])
    public func reduce(state: EngineState, keyCode: KeyCode) -> (EngineState, [EngineAction]) {
        switch keyCode {
        case .up:
            return (
                state.updating(candidateWindow: state.candidateWindow.movingUp()), [.navigate(.up)]
            )
        case .down:
            return (
                state.updating(candidateWindow: state.candidateWindow.movingDown()),
                [.navigate(.down)]
            )
        case .left:
            return (
                state.updating(candidateWindow: state.candidateWindow.movingPageUp()),
                [.navigate(.pageUp)]
            )
        case .right:
            return (
                state.updating(candidateWindow: state.candidateWindow.movingPageDown()),
                [.navigate(.pageDown)]
            )

        case .enter:
            return handleEnter(state: state)

        case .backspace:
            guard state.active else { return (state, [.reject]) }
            return handleBackspace(state: state)

        case .chars(let string):
            return string.reduce((state, [EngineAction]())) { acc, char in
                let (currentState, allActions) = acc
                let (nextState, nextActions) = reduceChar(state: currentState, char: char)
                return (nextState, allActions + nextActions)
            }
        }
    }

    private func handleEnter(state: EngineState) -> (EngineState, [EngineAction]) {
        if let selected = state.candidateWindow.selectedCandidate {
            return (
                resetState(active: false, buffer: ""), [.commit(state.committedPrefix + selected)]
            )
        }

        if !state.buffer.isEmpty {
            return (
                resetState(active: false, buffer: ""),
                [.commit(state.committedPrefix + state.buffer)]
            )
        }

        return (state, [.reject])
    }

    private func reduceChar(state: EngineState, char: Character) -> (EngineState, [EngineAction]) {
        if !state.active {
            return char == "\\"
                ? (pushHistory(resetState(active: true, buffer: "\\"), current: state), [.sync])
                : (state, [.reject])
        }

        // 1. Try Trie Continuation
        let trieResult = handleTrieStep(state: state, char: char)
        if trieResult.actions.last != .reject {
            return (trieResult.state, trieResult.actions)
        }

        // 2. Special Handlers
        if char == "\\" {
            return handleSoftCommit(state: state)
        }

        if let digit = Int(String(char)), digit >= 1, digit <= 9 {
            return handleDigitSelection(state: state, digit: digit)
        }

        // 3. Fallback: Implicit Commit
        let candidates = state.candidates()
        let text = state.candidateWindow.selectedCandidate ?? candidates.first ?? state.buffer
        return (
            resetState(active: false, buffer: ""), [.commit(state.committedPrefix + text), .reject]
        )
    }

    private func handleTrieStep(state: EngineState, char: Character) -> (
        state: EngineState, actions: [EngineAction]
    ) {
        guard state.buffer.count < MAX_BUFFER_LENGTH,
            let nextNode = state.currentNode?.children[char]
        else {
            return (state, [.reject])
        }

        let nextPath = state.path + [nextNode]
        let nextBuffer = state.buffer + String(char)

        // Leaf Node Auto-commit
        if nextNode.children.isEmpty,
            let candidate = nextNode.candidates?.first, nextNode.candidates?.count == 1 {
            return (
                resetState(active: false, buffer: ""), [.commit(state.committedPrefix + candidate)]
            )
        }

        let window = CandidateWindow(
            candidates: nextNode.candidates ?? [], selectedIndex: 0, firstVisibleIndex: 0,
            pageSize: 9)

        let nextState = state.updating(path: nextPath, buffer: nextBuffer, candidateWindow: window)
        return (pushHistory(nextState, current: state), [.sync])
    }

    private func handleSoftCommit(state: EngineState) -> (EngineState, [EngineAction]) {
        if let selected = state.candidateWindow.selectedCandidate {
            let nextState = EngineState(
                path: [root],
                buffer: "\\",
                committedPrefix: state.committedPrefix + selected,
                active: true,
                candidateWindow: .empty(),
                history: []  // History will be set by pushHistory
            )
            return (pushHistory(nextState, current: state), [.sync])
        }

        // Hard Commit fallback
        return (
            resetState(active: false, buffer: ""),
            [.commit(state.committedPrefix + state.buffer + "\\")]
        )
    }

    private func handleDigitSelection(state: EngineState, digit: Int) -> (
        EngineState, [EngineAction]
    ) {
        let index = state.candidateWindow.firstVisibleIndex + digit - 1
        let candidates = state.candidates()

        if candidates.indices.contains(index) {
            return (
                resetState(active: false, buffer: ""),
                [.commit(state.committedPrefix + candidates[index])]
            )
        }

        return (state, [.reject])
    }

    private func handleBackspace(state: EngineState) -> (EngineState, [EngineAction]) {
        // 1. Primary: Use Persistent History (Perfect Undo)
        if let previousState = state.history.last {
            var newHistory = state.history
            newHistory.removeLast()
            return (previousState.updating(history: newHistory), [.sync])
        }

        // 2. Secondary: Fallback to Manual Popping (if history is missing/capped)
        if !state.buffer.isEmpty {
            return applyManualBackspace(state: state)
        }

        // 3. Terminal: Deactivate
        return (resetState(active: false, buffer: ""), [.sync])
    }

    private func applyManualBackspace(state: EngineState) -> (EngineState, [EngineAction]) {
        var nextPath = state.path
        var nextBuffer = state.buffer
        if !nextBuffer.isEmpty { nextBuffer.removeLast() }
        if nextPath.count > 1 { nextPath.removeLast() }

        // If everything is empty, deactivate
        if nextBuffer.isEmpty && state.committedPrefix.isEmpty {
            return (resetState(active: false, buffer: ""), [.sync])
        }

        let candidates = nextPath.last?.candidates ?? []
        let window = CandidateWindow(
            candidates: candidates, selectedIndex: 0, firstVisibleIndex: 0, pageSize: 9)

        let nextState = state.updating(path: nextPath, buffer: nextBuffer, candidateWindow: window)
        return (nextState, [.sync])
    }
}
