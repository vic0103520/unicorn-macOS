# Security & Distribution

## 1. Runtime Security & Limits
*   **Persistent State Cap:** 
    *   The Engine maintains a history of content-changing states for undo. The stack is capped at **100 entries**.
*   **Input Buffer Limit:** 
    *   The Engine enforces a hard limit on the input buffer size.
    *   **Constraint:** `MAX_BUFFER_LENGTH = 50` characters.
    *   **Behavior:** If the buffer reaches this limit, the engine triggers an **Implicit Commit** and resets the session.

## 2. Signing & Code Integrity
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

## 3. Verification Strategy
The project uses two complementary verification layers to ensure distribution reliability:

1.  **Source Verification (CI):**
    - **Trigger:** Every push/PR.
    - **Mechanism:** `make install`.
    - **Purpose:** Confirms the source code builds correctly and that the `Makefile` logic for system registration is functional in a clean environment.
2.  **Artifact Verification (Release):**
    - **Trigger:** Tagged releases (`v*` or `test-*`).
    - **Mechanism:** Downloads the final `.zip` from GitHub and runs `sh install.sh`.
    - **Outcome Logic:**
        - **Real Versions (`v*`):** Published only if verification succeeds.
        - **Test Versions (`test-*`):** Always deleted from GitHub after the run to maintain history cleanliness.
    - **Purpose:** Simulates the end-user experience. Confirms the archive integrity, the effectiveness of the quarantine removal script, and the automated installation of the pre-built binary.
