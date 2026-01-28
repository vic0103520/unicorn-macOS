import Foundation

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
