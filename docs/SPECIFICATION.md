# Unicorn Input Method Specification

## 1. Architecture
Unicorn is a native macOS Input Method implemented in Swift. It follows a **Pure Core, Impure Shell** design consisting of three distinct tiers:

*   **Tier 1: Domain Logic (Engine):** The **Pure Core**. A deterministic state machine. It receives `KeyCode` events and returns semantic `EngineAction` intents (`sync`, `navigate`, `commit`, `reject`). It encapsulates all business logic, trie traversal, and history management.
*   **Tier 2: Presentation Model (EngineState Extensions):** Part of the **Pure Core**. A bridge between logic and UI. This layer consists of pure functions on `EngineState` that calculate UI-specific data (e.g., `compositionText()`, `selectionRange()`)
*   **Tier 3: Framework Glue (InputController):** The **Impure Shell**. A "dumb" layer that translates macOS `NSEvent`s into `KeyCode`s, feeds them to the `Engine`, and maps the logic outputs to macOS InputMethodKit APIs.

## 2. Activation & Deactivation
*   **Activation:** Typing the backslash `\` character activates "Unicorn Mode".
*   **ABC Fallback:** When not in Unicorn Mode (no active buffer), all keys are passed through to the system, making Unicorn behave like the default "ABC" input method.
*   **Deactivation:** 
    *   Committing a symbol.
    *   Implicitly committing due to invalid input.
    *   Pressing Escape or Backspace until the buffer and history are empty.

## 3. Engine State Transition (Priority Order)

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

### C. Special Keys (`\`)
If the key is not a valid Trie continuation, the engine checks for the Backslash trigger.
*   **Backslash (`\`):** 
    *   Acts as a **Sequence Terminator** and **Soft Commit** command.
    *   **Logic:**
        *   **If Symbol Selected:** Soft-commits the selected candidate. **The current state is pushed to history.**
        *   **If No Match:** Hard-commits the current composition + `\`.
    *   **Result:** Starts a new sequence with `\` in the buffer. Returns `.sync`.

### D. Candidate Selection (Numeric)
If the key is a digit (1-9) AND candidates are currently visible:
*   The key acts as a selection command.
*   **Action:** The candidate at the corresponding index is **Committed**, and the engine resets.

### E. Implicit Commit (Rejection Logic)
If the key is not a valid Trie continuation, not a control key, and not a selection command:
1.  **Implicit Commit:** The engine determines the "best match" for the *current* buffer.
2.  **Action Sequence:** Returns `[.commit(text), .reject]`.

## 4. UI Behavior & Navigation
*   **Composition:** Underlined text showing the current buffer (e.g., `\lambda`).
*   **Candidates Window:** A floating window appearing when multiple options exist.
*   **Paging:** Handled by `CandidateWindow` logic (Page Up/Down jumps by page size).

## 5. Security & Limits
*   **Persistent State Cap:** 
    *   The Engine maintains a history of content-changing states for undo. The stack is capped at **100 entries**.
*   **Input Buffer Limit:** 
    *   The Engine enforces a hard limit on the input buffer size.
    *   **Constraint:** `MAX_BUFFER_LENGTH = 50` characters.
    *   **Behavior:** If the buffer reaches this limit, the engine triggers an **Implicit Commit** and resets the session.

## 6. Signing & Distribution
*   **Ad-hoc Signing:** All binaries are signed with an ad-hoc identity (`-`). This satisfies macOS architecture requirements (especially on Apple Silicon) and changes the system error from "Damaged" to "Unverified Developer" for local usage.
*   **Gatekeeper Quarantine:** Because the project is not notarized by Apple, macOS applies the `com.apple.quarantine` attribute to downloaded binaries, which can still trigger a "Damaged" warning despite ad-hoc signing.
*   **Installer Workflow:** Distribution includes an `install.sh` script that provides a comprehensive security disclosure:
    1.  **Keylogging Risk:** Disclosure that Input Methods can monitor all keystrokes.
    2.  **Notarization Status:** Disclosure that the app has not been scanned by Apple.
    3.  **Tampering Risk:** Disclosure that the "Damaged" warning is a protection against altered code.
    4.  **Informed Consent:** Requires explicit `y/N` approval before:
        - Removing the quarantine attribute (`xattr -d`).
        - Installing to `~/Library/Input Methods/`.
        - Registering the component with the system.

### 6.1 Verification Strategy
The project uses two complementary verification layers to ensure distribution reliability:

1.  **Source Verification (CI):**
    - **Trigger:** Every push/PR.
    - **Mechanism:** `make install`.
    - **Purpose:** Confirms the source code builds correctly and that the `Makefile` logic for system registration is functional in a clean environment.
2.  **Artifact Verification (Release):**
    - **Trigger:** Tagged releases.
    - **Mechanism:** Downloads the final `.zip` from GitHub and runs `sh install.sh`.
    - **Purpose:** Simulates the end-user experience. Confirms the archive integrity, the effectiveness of the quarantine removal script, and the automated installation of the pre-built binary.
