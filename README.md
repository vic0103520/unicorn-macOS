# Unicorn Input Method

**Unicorn** is a native macOS Unicode Input Method designed to allow easy insertion of Agda and Unicode symbols (e.g., typing `\lambda` to get `λ`). It is built entirely in **Swift**, offering a seamless, high-performance experience.

## 🚀 Features & Usage

### Activation
*   **Activate:** Type the backslash `\` character to enter Unicorn Mode. The character will be underlined.
*   **English Input:** When no symbol sequence is active, Unicorn behaves exactly like the default "ABC" input method.

### Typing & Composition
*   **Sequence:** Type characters to extend the sequence (e.g., `l`, `a`, `m`...).
*   **Live Updates:** The input method provides real-time feedback:
    *   **Composition:** The raw buffer (e.g., `\lam`) is shown inline and underlined.
    *   **Candidates:** A floating window displays available symbols matching the current sequence.

### Commitment
*   **Explicit Commit:** Press **Space** or **Enter** to commit the first candidate.
    *   **Space:** Commits the symbol and inserts a space (e.g., `λ `).
    *   **Enter:** Commits the symbol and inserts a newline.
*   **Selection:**
    *   **Number Keys (1-9):** Press a number to select and commit the specific candidate at that index.
    *   **Arrow Keys (Up/Down):** Navigate the candidate list one by one.
    *   **Arrow Keys (Left/Right):** Page Up/Down through the candidate list (in blocks of 9).
*   **Implicit Commit:** If you type a character that is NOT part of a valid sequence (e.g., typing `.` after `\lambda`), Unicorn will automatically commit the best match (`λ`) and then insert the new character (`.`), resulting in `λ.`.

### Special Actions
*   **Backspace:** Deletes the last character in the buffer, reversing the state of the engine.
*   **Double Backslash:** Typing `\\` commits a single `\` character and exits the mode.
*   **Stateful Commits (Re-activation):** For sequences like `\==\`, the engine commits the intermediate result (`≡`) and immediately restarts the composition session. This allows for fluid typing of complex symbols like `≡⟨⟩` without re-activating manually.

---

## 🛠 Building & Installation

### Prerequisites
*   **macOS:** 14.0 or later.
*   **Xcode:** 16.0 or later (Swift 6.0).

### Build & Install
The project includes a `Makefile` to automate the build and installation process:

```bash
# Build and install for development (Debug)
make install

# Build and install for production (Release)
make install CONFIG=Release
```

**What this command does:**
1.  **Build:** Builds the `unicorn.app` bundle using `xcodebuild`.
2.  **Installation:** Copies the app bundle to `~/Library/Input Methods/`.
3.  **Registration:** Runs `lsregister` to notify macOS of the new Input Method.
4.  **Restart:** Restarts the `unicorn` process to apply changes immediately.

### Enabling the Input Method
Once installed, you must enable it in macOS:
1.  Open **System Settings** -> **Keyboard** -> **Input Sources**.
2.  Click **Edit...** then the **+** button.
3.  Search for **Unicorn** (usually under "English" or "Others").
4.  Select it and click **Add**.
5.  (Optional) Enable **"Use Caps Lock to switch to and from last used input source"** to toggle between Unicorn and your other primary language (e.g., Chinese).

---

## 📖 Technical Documentation

For details on the internal architecture, state machine logic, and the `Engine`/`InputController` separation, please refer to the **[Specification Document](docs/SPECIFICATION.md)**.

## 🧪 Development Commands

*   `unicorn/`
    *   `Engine.swift`: Core logic implementation.
    *   `KeyCode.swift`: Event normalization layer.
    *   `InputController.swift`: Main InputMethodKit controller.
    *   `keymap.json`: The data source for input sequences.
*   `unicornTests/`
    *   `EngineTests.swift`: Unit tests for the engine logic.
*   `Makefile`: Build automation (run `make help` for all commands).