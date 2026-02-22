# Engine State Transition (Priority Order)

When a key is pressed, it is converted to a `KeyCode` and passed to `Engine.processKey`. The Engine applies the following priority logic:

### A. Navigation & Control
*   **Arrows:** Update the internal selection state (`CandidateWindow`). Returns `.navigate` action. **These are transient UI changes and are not stored in the undo history.**
*   **Enter:** Commits the current selection or buffer. Returns `.commit`.
*   **Backspace:** 
    *   **Universal Undo:** Reverts the state to the exact previous **content-changing** moment (character entry or soft-commit) by popping from the history stack in `EngineState`.
    *   **Fallback:** If history is empty, manually removes the last character from the buffer.
    *   **Deactivate:** If the state is empty, deactivates.

### B. Trie Continuation
The engine checks if the key extends the current buffer to a valid path in the Keymap (Trie).
*   **Match:** The key is consumed and added to the buffer. **The current state is pushed to history before the transition.**
    *   Returns `.sync`.
*   **Leaf:** If the new path is a leaf node (no further children):
    *   **Single Candidate:** The candidate is automatically **Committed**.
    *   **No Candidate:** The raw buffer is **Committed**.

### C. Special Keys (``)
If the key is not a valid Trie continuation, the engine checks for the Backslash trigger.
*   **Backslash (``):** 
    *   Acts as a **Sequence Terminator** and **Soft Commit** command.
    *   **Logic:**
        *   **If Symbol Selected:** Soft-commits the selected candidate. **The current state is pushed to history.**
        *   **If No Match:** Hard-commits the current composition + ``.
    *   **Result:** Starts a new sequence with `` in the buffer. Returns `.sync`.

### D. Candidate Selection (Numeric)
If the key is a digit (1-9) AND candidates are currently visible:
*   The key acts as a selection command.
*   **Action:** The candidate at the corresponding index is **Committed**, and the engine resets.

### E. Implicit Commit (Rejection Logic)
If the key is not a valid Trie continuation, not a control key, and not a selection command:
1.  **Implicit Commit:** The engine determines the "best match" for the *current* buffer.
2.  **Action Sequence:** Returns `[.commit(text), .reject]`.
