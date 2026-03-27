# Engine Logic & State Transitions

The Engine is a deterministic state machine representing the **Pure Core** of Unicorn. It processes normalized `KeyCode` inputs and produces `EngineAction` intents.

## 1. Engine State Structure
The `EngineState` captures the complete logical state of an input session:
*   **`path`**: A stack of `Trie` nodes (from `keymap.json`) representing the current traversal path.
*   **`buffer`**: The raw characters entered since the last (soft) commit (e.g., `lambda`).
*   **`committedPrefix`**: Text from previous segments in the same session that have been "soft-committed" (e.g., if typing `\alpha\beta`, `\alpha` is the prefix).
*   **`candidateWindow`**: Selection state (selected index, pagination).
*   **`history`**: A stack of immutable `EngineState` snapshots used for undo operations.

## 2. Key Processing Logic
When the engine is active (see [Activation](activation.md)), keys are processed in priority order:

### A. Navigation
*   **Arrow/Page Keys:** Update the `candidateWindow` state (selection or pagination). These actions are **transient** and do not modify the `buffer` or `history`.
*   **Enter:** Commits the current logical resolution (`committedPrefix` + selected candidate) and triggers deactivation.

### B. Trie Traversal (Character Entry)
When a character is typed:
1.  **Lookahead:** The engine checks if the character exists as a child of the current `Trie` node (`path.last`).
2.  **Match:** 
    *   The current state is pushed to `history`.
    *   The new node is appended to `path`.
    *   The character is appended to `buffer`.
3.  **Auto-Commit:** If the new node is a leaf (no children) and contains exactly one candidate, the engine resolves and commits automatically.

### C. Sequence Termination (`\`)
The backslash acts as a **Soft Commit** command:
*   **Success:** If a candidate is selected (or available), it is appended to the `committedPrefix`. The `buffer` is reset to `\`, and the `path` is reset to the root node. This allows continuous symbol entry in a single session.
*   **Fallback:** If no candidate can be resolved, the engine performs an **Implicit Commit** (see [Activation](activation.md)) and deactivates.

### D. Numerical Selection
Digits `1-9` select the candidate at the corresponding index in the current `candidateWindow` page, resulting in an immediate commit and deactivation.

## 3. History & Undo Mechanism
Unicorn implements a "Perfect Undo" system.
*   **Snapshots:** A snapshot of the `EngineState` is taken before any action that modifies the `buffer` or `path`.
*   **Backspace:** 
    *   **Primary Path:** Pops the last entry from the `history` stack, reverting the engine to its exact previous state (including previous selection and prefix).
    *   **Fallback:** If history is empty, the engine manually removes the last character or deactivates (see [Security & Limits](security_and_distribution.md) for history depth constraints).
