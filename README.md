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
*   **Backspace (Universal Undo):** Reverts the composition to the exact previous state (character-by-character or undoing a soft commit).
*   **Double Backslash:** Typing `\\` commits a single `\` character and exits the mode.
*   **Accumulating Composition (Soft Commits):** For sequences like `\==\`, typing a backslash `\` when a symbol is matched will "soft commit" the result (e.g., `≡`) and keep the composition session active. This allows for fluid typing of complex symbols like `≡⟨⟩` without re-activating manually, and ensures compatibility with editor plugins like VSCodeVim.

---

## 🏗 Architecture

Unicorn is designed with a **Pure Core, Impure Shell** architecture:
*   **Pure Core:** The logical engine and presentation models are deterministic and state-isolated, ensuring high reliability and easy testing.
*   **Impure Shell:** A thin layer that interfaces with macOS `InputMethodKit`, handling side effects and system events.

---

## 🛠 Building & Installation

### Prerequisites
*   **macOS:** 14.0 or later.
*   **Xcode:** 16.0 or later (Swift 6.0).

### Option A: Installation via Pre-built Binary (Recommended)
1.  **Download:** Get `unicorn-macos.zip` from **[Releases](https://github.com/zyshih/unicorn-macos/releases)**.
2.  **Extract:** Unzip the archive. You will see `unicorn.app` and `install.sh`.
3.  **Run Installer:** Open your Terminal in the extracted folder and run:
    ```bash
    sh install.sh
    ```
4.  **Authorize:** Follow the prompts to acknowledge the security notice. The script will move Unicorn to your Library and register it.

### Option B: Build & Install from Source
The project includes a `Makefile` to automate the process.

```bash
# Build and install (Release)
make install
```

### Release Management (Developers)
For maintainers, the `Makefile` includes targets to manage the release lifecycle:
*   **Test Release:** `make test-release` (Runs an end-to-end simulation; automatically cleans up after itself).
*   **Formal Release:** `make release TAG=v1.0.0` (Tags and triggers the production release workflow).
*   **Re-release:** `make re-release TAG=v1.0.0` (Wipes an existing release and re-triggers the workflow).

### Enabling the Input Method
1.  Open **System Settings** -> **Keyboard** -> **Input Sources**.
2.  Click **Edit...** then the **+** button.
3.  Search for **Unicorn** and click **Add**.

---

## 🛡️ Security & Privacy (IMPORTANT)

Unicorn is an independent, open-source project. Because it is **not notarized by Apple**, you will encounter security warnings during installation. Please read the following risks carefully before proceeding.

### ⚠️ Security Risks of Unverified Input Method

1.  **Full Keystroke Access (Keylogging Risk):**
    As an Input Method, Unicorn has the technical capability to monitor and record **EVERY keystroke** you type across **ALL apps** on your system. This includes passwords, credit card numbers, and private messages.
2.  **Lack of Apple Notarization:**
    This application is unsigned and has NOT been scanned for malware by Apple's automated services. Its developer's identity is not officially verified by Apple.
3.  **Potential for Corruption or Tampering:**
    The "App is Damaged" warning macOS may show is a default mechanism to protect you from code that might have been altered or injected with malicious payloads during or after download.
4.  **Data Exfiltration Risk:**
    While Unicorn does not request network permissions, unverified software could theoretically attempt to exfiltrate data if security vulnerabilities are present or if it is maliciously modified.

### 🛡️ Our Commitment to Privacy
*   **Open Source:** The entire logic of Unicorn is [open source](https://github.com/zyshih/unicorn-macos). We encourage users to audit the code.
*   **No Network Access:** Unicorn does not request or use network entitlements. It operates entirely locally on your machine.
*   **Integrity Verification:** We provide SHA256 checksums for every release. You can verify the main binary yourself:
    ```bash
    shasum -a 256 ~/Library/Input\ Methods/unicorn.app/Contents/MacOS/unicorn
    ```

### How to Handle macOS Warnings
*   **"App is Damaged":** This is a quarantine flag for unnotarized downloads. The `install.sh` script removes this flag after you acknowledge the risks.
*   **"Unverified Developer":** If prompted, you may need to right-click `unicorn.app` in Finder and select **Open** to authorize it manually.

---

## 📖 Technical Documentation

For details on the internal architecture, state machine logic, and the `Engine`/`InputController` separation, please refer to the **[Specification Document](docs/SPECIFICATION.md)**.
