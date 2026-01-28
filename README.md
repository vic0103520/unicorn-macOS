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
*   **Accumulating Composition (Soft Commits):** For sequences like `\==\`, typing a backslash `\` when a symbol is matched will "soft commit" the result (e.g., `≡`) and keep the composition session active. This allows for fluid typing of complex symbols like `≡⟨⟩` without re-activating manually, and ensures compatibility with editor plugins like VSCodeVim.

---

## 🛠 Building & Installation

### Prerequisites
*   **macOS:** 14.0 or later.
*   **Xcode:** 16.0 or later (Swift 6.0).

### Build & Install from Source
The project includes a `Makefile` to automate the process. By default, it installs in **Release** mode for performance.

```bash
# Build and install (Release)
make install
```

**What this command does:**
1.  **Build:** Builds the `unicorn.app` bundle using `xcodebuild`.
2.  **Installation:** Copies the bundle to `~/Library/Input Methods/`.
3.  **Registration:** Runs `lsregister` to notify macOS of the new source.
4.  **Restart:** Restarts the process to apply changes.

### Alternative: Installation via Pre-built Binary
1.  **Download:** Get `unicorn-macos.zip` from **[Releases](https://github.com/zyshih/unicorn-macos/releases)**.
2.  **Install:** Move `unicorn.app` to `~/Library/Input Methods/`.
3.  **Register:** Run:
    ```bash
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Library/Input\ Methods/unicorn.app
    ```
4.  **Gatekeeper:** Right-click the app in Finder and select **Open** to authorize it.

### Enabling the Input Method
1.  Open **System Settings** -> **Keyboard** -> **Input Sources**.
2.  Click **Edit...** then the **+** button.
3.  Search for **Unicorn** and click **Add**.

---

## 📖 Technical Documentation

For details on the internal architecture, state machine logic, and the `Engine`/`InputController` separation, please refer to the **[Specification Document](docs/SPECIFICATION.md)**.
