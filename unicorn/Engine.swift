import Foundation

/// A node in the symbol lookup Trie.
/// This is a reference type (`final class`) to allow for efficient sharing of subtrees
/// without deep copying. All properties are immutable (`let`), making it safe to share.
public final class Trie: Decodable, Equatable {
    public let candidates: [String]?
    public let children: [Character: Trie]

    public static func == (lhs: Trie, rhs: Trie) -> Bool {
        // Structural equality check: identical if they are the same instance (fast path)
        // or if their contents match.
        return lhs === rhs || (lhs.candidates == rhs.candidates && lhs.children == rhs.children)
    }

    struct DynamicKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { return nil }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var candidates: [String]?
        var children: [Character: Trie] = [:]

        for key in container.allKeys {
            if key.stringValue == ">>" {
                candidates = try container.decode([String].self, forKey: key)
            } else if key.stringValue.count == 1, let char = key.stringValue.first {
                let child = try container.decode(Trie.self, forKey: key)
                children[char] = child
            }
        }
        self.candidates = candidates
        self.children = children
    }
}

/// Actions produced by the Engine in response to a key event.
public enum EngineAction: Equatable {
    case reject
    case updateComposition(String)
    case commit(String)
    case showCandidates(String)
    case navigate(CandidateNavigation)
}

public enum CandidateNavigation {
    case up
    case down
    case pageUp
    case pageDown
}

/// Manages the state of the candidate list, including selection and paging.
public struct CandidateWindow: Equatable {
    public let candidates: [String]
    public let selectedIndex: Int
    public let firstVisibleIndex: Int
    public let pageSize: Int

    public var selectedCandidate: String? {
        guard candidates.indices.contains(selectedIndex) else { return nil }
        return candidates[selectedIndex]
    }

    public var isVisible: Bool {
        return !candidates.isEmpty
    }

    public static func empty(pageSize: Int = 9) -> CandidateWindow {
        return CandidateWindow(
            candidates: [], selectedIndex: 0, firstVisibleIndex: 0, pageSize: pageSize)
    }

    public func movingDown() -> CandidateWindow {
        guard selectedIndex < candidates.count - 1 else { return self }
        let newSelected = selectedIndex + 1
        let newFirst =
            newSelected >= firstVisibleIndex + pageSize
            ? newSelected - pageSize + 1 : firstVisibleIndex

        return CandidateWindow(
            candidates: candidates, selectedIndex: newSelected, firstVisibleIndex: newFirst,
            pageSize: pageSize)
    }

    public func movingUp() -> CandidateWindow {
        guard selectedIndex > 0 else { return self }
        let newSelected = selectedIndex - 1
        var newFirst = firstVisibleIndex
        if newSelected < firstVisibleIndex {
            newFirst = newSelected
        }
        return CandidateWindow(
            candidates: candidates, selectedIndex: newSelected, firstVisibleIndex: newFirst,
            pageSize: pageSize)
    }

    public func movingPageDown() -> CandidateWindow {
        let count = candidates.count
        var newFirst = firstVisibleIndex + pageSize
        var newSelected = selectedIndex

        if newFirst < count {
            newSelected = newFirst  // Logic from InputController: selectionIndex = firstVisibleCandidateIndex
        } else {
            newSelected = count - 1
            newFirst = max(0, count - pageSize)
        }

        return CandidateWindow(
            candidates: candidates, selectedIndex: newSelected, firstVisibleIndex: newFirst,
            pageSize: pageSize)
    }

    public func movingPageUp() -> CandidateWindow {
        let delta = selectedIndex - firstVisibleIndex
        var newFirst = firstVisibleIndex - pageSize
        if newFirst < 0 { newFirst = 0 }

        let newSelected = selectedIndex < pageSize && newFirst == 0 ? 0 : newFirst + delta
        // Clamp selection just in case, though logically it should be safe if delta is valid
        let safeSelected = min(max(0, newSelected), candidates.count - 1)

        return CandidateWindow(
            candidates: candidates, selectedIndex: safeSelected, firstVisibleIndex: newFirst,
            pageSize: pageSize)
    }

    public func selecting(index: Int) -> CandidateWindow {
        guard candidates.indices.contains(index) else { return self }
        // Simple selection update, naive scrolling if needed could be added,
        // but typically direct selection (1-9) assumes visibility or simple jump.
        // For simplicity, we keep firstVisibleIndex unless selected is out of view.
        var newFirst = firstVisibleIndex
        if index < firstVisibleIndex {
            newFirst = index
        } else if index >= firstVisibleIndex + pageSize {
            newFirst = index - pageSize + 1
        }
        return CandidateWindow(
            candidates: candidates, selectedIndex: index, firstVisibleIndex: newFirst,
            pageSize: pageSize)
    }
}

/// Represents the immutable state of the Input Engine at a point in time.
public struct EngineState: Equatable {
    /// The sequence of Trie nodes traversed.
    public let path: [Trie]
    /// The raw input buffer (e.g., "\lam").
    public let buffer: String
    /// The text that has been "soft committed" but is still visually part of the composition.
    public let committedPrefix: String
    /// Whether the engine is currently capturing input.
    public let active: Bool

    public let candidateWindow: CandidateWindow

    public var currentNode: Trie? { path.last }
    // Convenience proxy
    public var candidates: [String] { candidateWindow.candidates }
    public var selectedCandidate: Int { candidateWindow.selectedIndex }

    public init(
        path: [Trie], buffer: String, committedPrefix: String = "", active: Bool,
        candidateWindow: CandidateWindow
    ) {
        self.path = path
        self.buffer = buffer
        self.committedPrefix = committedPrefix
        self.active = active
        self.candidateWindow = candidateWindow
    }
}

/// The core logic engine for the Unicorn Input Method.
/// It maintains a state machine that traverses a Trie of symbol sequences.
public class Engine {
    public let root: Trie
    /// The current state. This is the only mutable property in the class.
    public private(set) var state: EngineState
    /// History of states for undoing soft commits.
    private var history: [EngineState] = []
    
    private let MAX_BUFFER_LENGTH = 50

    public var initialState: EngineState {
        EngineState(path: [root], buffer: "", active: false, candidateWindow: .empty())
    }

    public init(jsonData: Data) throws {
        let decoder = JSONDecoder()
        self.root = try decoder.decode(Trie.self, from: jsonData)
        self.state = EngineState(path: [root], buffer: "", active: false, candidateWindow: .empty())
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
        state = EngineState(
            path: state.path, buffer: state.buffer, committedPrefix: state.committedPrefix,
            active: state.active, candidateWindow: newWindow
        )
    }

    /// Updates the selected candidate index in the current state.
    public func selectCandidate(index: UInt32) {
        let idx = Int(index)
        let newWindow = state.candidateWindow.selecting(index: idx)
        state = EngineState(
            path: state.path,
            buffer: state.buffer,
            committedPrefix: state.committedPrefix,
            active: state.active,
            candidateWindow: newWindow
        )
    }

    public func getCandidates() -> [String] {
        return state.candidates
    }

    /// Resets the engine to its initial inactive state.
    public func deactivate() {
        state = resetState(active: false, buffer: "")
        history.removeAll()
    }

    /// Imperative shell method that updates the internal state and returns actions.
    public func processKey(keyCode: KeyCode) -> [EngineAction] {
        // Optimization: Early exit if inactive and key is not an activator.
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

    /// Helper to create a fresh state starting at the root.
    private func resetState(active: Bool, buffer: String) -> EngineState {
        // When resetting, candidates should be derived from the new path (which is just root)
        return EngineState(
            path: [root], buffer: buffer, committedPrefix: "", active: active,
            candidateWindow: .empty())
    }

    /// Helper to perform an implicit commit (commit best match and reset).
    /// Used when the sequence is interrupted (e.g. by space or invalid char).
    private func implicitCommit(_ state: EngineState) -> (EngineState, [EngineAction]) {
        let text = state.candidateWindow.selectedCandidate ?? state.candidates.first ?? state.buffer
        let fullCommitText = state.committedPrefix + text
        // Side effect: Clear history on implicit commit
        history.removeAll()
        return (resetState(active: false, buffer: ""), [.commit(fullCommitText)])
    }

    /// Pure transition function: (State, Input) -> (NewState, [Action])
    public func reduce(state: EngineState, keyCode: KeyCode) -> (EngineState, [EngineAction]) {
        let move = { (newWindow, direction) -> (EngineState, [EngineAction]) in
            let nextState = EngineState(
                path: state.path, buffer: state.buffer, committedPrefix: state.committedPrefix,
                active: state.active,
                candidateWindow: newWindow)
            return (nextState, [.navigate(direction)])
        }

        switch keyCode {
        case .up:
            return move(state.candidateWindow.movingUp(), .up)
        case .down:
            return move(state.candidateWindow.movingDown(), .down)
        case .left:  // PageUp
            return move(state.candidateWindow.movingPageUp(), .pageUp)
        case .right:  // PageDown
            return move(state.candidateWindow.movingPageDown(), .pageDown)

        case .enter:
            if state.candidateWindow.isVisible {
                if let selected = state.candidateWindow.selectedCandidate {
                    let fullCommitText = state.committedPrefix + selected
                    history.removeAll()
                    return (resetState(active: false, buffer: ""), [.commit(fullCommitText)])
                }
            } else if !state.buffer.isEmpty {
                // Enter with buffer but no candidates -> Commit buffer
                let fullCommitText = state.committedPrefix + state.buffer
                history.removeAll()
                return (resetState(active: false, buffer: ""), [.commit(fullCommitText)])
            }
            return (state, [.reject])

        case .backspace:
            if !state.active { return (state, [.reject]) }
            return handleBackspace(state: state)

        case .chars(let string):
            // Fold over the string characters
            var currentState = state
            var allActions = [EngineAction]()

            for char in string {
                let (next, acts) = reduceChar(state: currentState, char: char)
                currentState = next
                allActions.append(contentsOf: acts)
            }
            return (currentState, allActions)
        }
    }

    /// Helper for processing a single character.
    private func reduceChar(state: EngineState, char: Character) -> (EngineState, [EngineAction]) {
        if !state.active {
            return handleInactiveState(state: state, char: char)
        }

        // 1. Try Trie Continuation
        // We simulate the handleCharacter call logic here to detect rejection without side effects if possible,
        // or just call it and check the action.
        let (newState, actions) = handleCharacter(state: state, char: char)
        
        // If handleCharacter accepted the input (no reject action), return it.
        // We check if the last action is .reject
        let isRejected = actions.last == .reject
        
        if !isRejected {
            return (newState, actions)
        }

        // 2. If rejected, check for Special Handlers
        
        // A. Backslash Trigger (Soft Commit)
        if char == "\\" {
            return handleBackslash(state: state)
        }

        // B. Candidate Selection (1-9)
        if state.candidateWindow.isVisible,
            let digit = Int(String(char)), digit >= 1, digit <= 9 {
            let index = state.candidateWindow.firstVisibleIndex + digit - 1
            if index < state.candidates.count {
                let text = state.committedPrefix + state.candidates[index]
                history.removeAll()
                return (resetState(active: false, buffer: ""), [.commit(text)])
            }
        }

        // 3. Fallback: Return the original rejection (Implicit Commit)
        return (newState, actions)
    }

    private func handleInactiveState(state: EngineState, char: Character) -> (
        EngineState, [EngineAction]
    ) {
        if char == "\\" {
            let nextState = resetState(active: true, buffer: "\\")
            return (nextState, [.updateComposition(nextState.buffer)])
        }
        return (state, [.reject])
    }

    private func handleBackslash(state: EngineState) -> (EngineState, [EngineAction]) {
        // Trigger Logic: The user typed '\' but it's not a continuation.
        
        if let selected = state.candidateWindow.selectedCandidate {
            // Soft Commit: We have a match. Keep the session active.
            history.append(state)
            let newCommittedPrefix = state.committedPrefix + selected
            let nextState = EngineState(
                path: [root], buffer: "\\", committedPrefix: newCommittedPrefix, active: true,
                candidateWindow: .empty())
            return (nextState, [.updateComposition(nextState.committedPrefix + nextState.buffer)])
        } else {
            // Hard Commit: No match for the current buffer. 
            // We commit the prefix, the buffer, and the backslash as a single block.
            let fullCommitText = state.committedPrefix + state.buffer + "\\"
            history.removeAll()
            return (resetState(active: false, buffer: ""), [.commit(fullCommitText)])
        }
    }

    private func handleBackspace(state: EngineState) -> (EngineState, [EngineAction]) {
        // 1. If buffer is empty, try to Undo from history
        if state.buffer.isEmpty {
            if !history.isEmpty {
                let restoredState = history.removeLast()
                return deleteLastChar(state: restoredState)
            } else {
                // No history, empty buffer -> Close session
                return (resetState(active: false, buffer: ""), [.updateComposition("")])
            }
        }

        // 2. Standard backspace: Remove last char from buffer
        return deleteLastChar(state: state)
    }

    private func deleteLastChar(state: EngineState) -> (EngineState, [EngineAction]) {
        var nextPath = state.path
        var nextBuffer = state.buffer
        if !nextBuffer.isEmpty { nextBuffer.removeLast() }
        if nextPath.count > 1 { nextPath.removeLast() }

        // If everything is empty, deactivate immediately
        if nextBuffer.isEmpty && state.committedPrefix.isEmpty && history.isEmpty {
            return (resetState(active: false, buffer: ""), [.updateComposition("")])
        }

        // Determine candidates for the new state
        let candidates = nextPath.last?.candidates ?? []
        let window = CandidateWindow(
            candidates: candidates, selectedIndex: 0, firstVisibleIndex: 0, pageSize: 9)

        let nextState = EngineState(
            path: nextPath, buffer: nextBuffer, committedPrefix: state.committedPrefix, active: true,
            candidateWindow: window)
        let action: EngineAction =
            nextState.candidates.isEmpty
            ? .updateComposition(nextState.committedPrefix + nextState.buffer)
            : .showCandidates(nextState.committedPrefix + nextState.buffer)
        return (nextState, [action])
    }

    private func handleCharacter(state: EngineState, char: Character) -> (
        EngineState, [EngineAction]
    ) {
        // Prevent buffer overflow
        if state.buffer.count >= MAX_BUFFER_LENGTH {
            return (state, [.reject])
        }

        guard let current = state.currentNode, let nextNode = current.children[char] else {
            // Rejection Path: The char is not in the Trie.
            if state.active {
                // Implicit Commit: Commit best match...
                let (newState, actions) = implicitCommit(state)
                // ...AND reject the new char so the system inserts it.
                return (newState, actions + [.reject])
            }
            return (state, [.reject])
        }

        var nextPath = state.path
        nextPath.append(nextNode)
        let nextBuffer = state.buffer + String(char)

        // Check for leaf node auto-commit
        if nextNode.children.isEmpty {
            let text: String
            if let candidates = nextNode.candidates, candidates.count == 1 {
                text = candidates[0]
            } else if nextNode.candidates == nil || nextNode.candidates!.isEmpty {
                text = nextBuffer
            } else {
                text = ""
            }

            if !text.isEmpty {
                let fullCommitText = state.committedPrefix + text
                history.removeAll()
                return (resetState(active: false, buffer: ""), [.commit(fullCommitText)])
            }
        }

        let candidates = nextNode.candidates ?? []
        let window = CandidateWindow(
            candidates: candidates, selectedIndex: 0, firstVisibleIndex: 0, pageSize: 9)

        let nextState = EngineState(
            path: nextPath, buffer: nextBuffer, committedPrefix: state.committedPrefix, active: true,
            candidateWindow: window)
        let action: EngineAction =
            nextState.candidates.isEmpty
            ? .updateComposition(nextState.committedPrefix + nextState.buffer)
            : .showCandidates(nextState.committedPrefix + nextState.buffer)
        return (nextState, [action])
    }
}
