# Security & Distribution

## 1. Runtime Security & Limits
The Engine enforces strict memory and operational boundaries to ensure system stability.
*   **Persistent State Cap:** The `history` stack for universal undo is capped at **100 entries** (`MAX_HISTORY_DEPTH`).
*   **Input Buffer Limit:** The input `buffer` is capped at **50 characters** (`MAX_BUFFER_LENGTH`).
*   **Boundary Behavior:** If the buffer reaches its limit, the engine triggers an **Implicit Commit** (see [Activation](activation.md)) and resets the session to prevent memory exhaustion or UI lag.

## 2. Signing & Code Integrity
*   **Ad-hoc Signing:** All binaries are signed with an ad-hoc identity (`-`). This satisfies macOS architecture requirements for Apple Silicon and changes the system error from "Damaged" to "Unverified Developer" for local usage.
*   **Gatekeeper Quarantine:** macOS applies the `com.apple.quarantine` attribute to downloaded binaries. This can trigger a "Damaged" warning even if the binary is ad-hoc signed.

## 3. Installer & Security Disclosure
Distribution includes an `install.sh` script that manages the security lifecycle and provides mandatory disclosures.
*   **Quarantine Removal:** The script uses `xattr -rd com.apple.quarantine` to manually bypass Gatekeeper blocks after user confirmation.
*   **Mandatory Disclosures:** The installer requires explicit consent (`y/N`) after presenting a detailed security notice covering:
    1.  **Keylogging Risk:** Disclosure that Input Methods have technical access to all keystrokes.
    2.  **Notarization Status:** Disclosure that the app has not been scanned or verified by Apple.
    3.  **Tampering Risk:** Explanation of the "Damaged" warning as a protection against altered code.
    4.  **Data Exfiltration Risk:** Potential for malicious code to send typed data to remote servers.
*   **Integrity Verification:** The script calculates and displays the **SHA256 checksum** of the main binary to allow users to verify the integrity of the downloaded artifact.

## 4. Verification Strategy (CI/CD)
The project uses two verification layers:
1.  **Source Verification:** `make install` is run in CI to confirm the code builds and registers correctly from source.
2.  **Artifact Verification:** Tagged releases trigger a workflow that downloads the final `.zip` and runs `install.sh` to simulate the end-user experience, verifying the archive integrity and the effectiveness of the quarantine removal script.
