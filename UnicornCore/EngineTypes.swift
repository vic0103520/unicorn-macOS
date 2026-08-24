import Foundation

/// Actions produced by the Engine in response to a key event.
/// These represent "Intents" that the Shell must execute.
public enum EngineAction: Equatable {
    /// The engine does not handle this key; let the system handle it.
    case reject

    /// The internal state has changed.
    /// The UI should sync itself with the current Presentation Model.
    case sync

    /// Explicit instruction to move the candidate selection in the UI.
    case navigate(CandidateNavigation)

    /// A terminal action: insert the provided text and usually reset the engine.
    case commit(String)
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

    /// Functional update helper.
    public func updating(
        candidates: [String]? = nil,
        selectedIndex: Int? = nil,
        firstVisibleIndex: Int? = nil,
        pageSize: Int? = nil
    ) -> CandidateWindow {
        return CandidateWindow(
            candidates: candidates ?? self.candidates,
            selectedIndex: selectedIndex ?? self.selectedIndex,
            firstVisibleIndex: firstVisibleIndex ?? self.firstVisibleIndex,
            pageSize: pageSize ?? self.pageSize
        )
    }

    public func movingDown() -> CandidateWindow {
        guard selectedIndex < candidates.count - 1 else { return self }
        let newSelected = selectedIndex + 1
        let newFirst =
            newSelected >= firstVisibleIndex + pageSize
            ? newSelected - pageSize + 1 : firstVisibleIndex

        return updating(selectedIndex: newSelected, firstVisibleIndex: newFirst)
    }

    public func movingUp() -> CandidateWindow {
        guard selectedIndex > 0 else { return self }
        let newSelected = selectedIndex - 1
        var newFirst = firstVisibleIndex
        if newSelected < firstVisibleIndex {
            newFirst = newSelected
        }
        return updating(selectedIndex: newSelected, firstVisibleIndex: newFirst)
    }

    public func movingPageDown() -> CandidateWindow {
        let count = candidates.count
        var newFirst = firstVisibleIndex + pageSize
        var newSelected = selectedIndex

        if newFirst < count {
            newSelected = newFirst
        } else {
            newSelected = count - 1
            newFirst = max(0, count - pageSize)
        }

        return updating(selectedIndex: newSelected, firstVisibleIndex: newFirst)
    }

    public func movingPageUp() -> CandidateWindow {
        let delta = selectedIndex - firstVisibleIndex
        var newFirst = firstVisibleIndex - pageSize
        if newFirst < 0 { newFirst = 0 }

        let newSelected = selectedIndex < pageSize && newFirst == 0 ? 0 : newFirst + delta
        let safeSelected = min(max(0, newSelected), candidates.count - 1)

        return updating(selectedIndex: safeSelected, firstVisibleIndex: newFirst)
    }

    public func selecting(index: Int) -> CandidateWindow {
        guard candidates.indices.contains(index) else { return self }
        var newFirst = firstVisibleIndex
        if index < firstVisibleIndex {
            newFirst = index
        } else if index >= firstVisibleIndex + pageSize {
            newFirst = index - pageSize + 1
        }
        return updating(selectedIndex: index, firstVisibleIndex: newFirst)
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

    /// Persistent history stack for universal undo.
    public let history: [EngineState]

    public var currentNode: Trie? { path.last }

    // MARK: - Initializer

    public init(
        path: [Trie],
        buffer: String,
        committedPrefix: String = "",
        active: Bool,
        candidateWindow: CandidateWindow,
        history: [EngineState] = []
    ) {
        self.path = path
        self.buffer = buffer
        self.committedPrefix = committedPrefix
        self.active = active
        self.candidateWindow = candidateWindow
        self.history = history
    }

    // MARK: - Functional Updates

    /// Returns a new state by applying specified updates to the current state.
    public func updating(
        path: [Trie]? = nil,
        buffer: String? = nil,
        committedPrefix: String? = nil,
        active: Bool? = nil,
        candidateWindow: CandidateWindow? = nil,
        history: [EngineState]? = nil
    ) -> EngineState {
        return EngineState(
            path: path ?? self.path,
            buffer: buffer ?? self.buffer,
            committedPrefix: committedPrefix ?? self.committedPrefix,
            active: active ?? self.active,
            candidateWindow: candidateWindow ?? self.candidateWindow,
            history: history ?? self.history
        )
    }

    /// Returns a copy of the state with an empty history array.
    /// Used when pushing snapshots into the history stack to prevent recursive memory growth.
    public func clearHistory() -> EngineState {
        return updating(history: [])
    }

    // MARK: - Presentation Model (Tier 2)

    /// Returns the full text to be displayed in the marked (composition) area.
    public func compositionText() -> String {
        return committedPrefix + buffer
    }

    /// Returns the cursor position/range within the composition.
    public func selectionRange() -> NSRange {
        let text = compositionText()
        return NSRange(location: text.count, length: 0)
    }

    /// Determines if the candidate window should be displayed.
    public func shouldShowCandidates() -> Bool {
        return active && !candidateWindow.candidates.isEmpty
    }

    /// Returns the currently selected candidate index.
    public func selectedCandidateIndex() -> Int {
        return candidateWindow.selectedIndex
    }

    /// Returns the list of candidates to display.
    public func candidates() -> [String] {
        return candidateWindow.candidates
    }
}
