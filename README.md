# Unicorn Input Method

**Unicorn** is a native macOS Unicode input method implemented in Swift with `InputMethodKit`. It converts Agda-style sequences into Unicode symbols, such as `\lambda` into `λ`.

## Features and Usage

### Activation and composition

- Type backslash (`\`) while Unicorn is inactive to start a composition.
- The `active` composition is displayed as marked text in the focused application.
- When the current sequence has candidates, Unicorn shows the native candidate panel.
- While no composition is `active`, translated key events other than backslash pass through to macOS.

### Commit and selection

- **Enter:** Commits the selected candidate, or the raw composition when no candidate is selected. The current implementation consumes Enter and does not insert a newline.
- **Number keys 1-9:** When trie continuation fails for the digit, a valid number selects and commits the corresponding candidate in the engine's current nine-item page.
- **Up and Down:** Move through candidates one item at a time.
- **Left and Right:** Move through candidate pages.
- **Other characters:** A character that cannot continue the sequence commits the selected candidate, first candidate, or raw `buffer`, then returns the triggering event to macOS for normal handling. For example, Space commits the current resolution and the host application handles the space.

### Backslash and undo behavior

- **Backspace:** Restores the latest available composition snapshot. If no snapshot remains, it removes buffered input or deactivates the composition.
- **Soft commit:** Typing backslash soft-commits when trie continuation fails for that character.
- **Double backslash:** With the bundled keymap, typing two backslashes from an inactive state commits one literal backslash and exits the composition. The engine currently reaches that result through the keymap's backslash mapping, not through a universal double-backslash rule.

See the [behavior specifications](docs/SPECIFICATION.md) for precise state transitions and edge cases.

## Architecture

Unicorn follows a three-tier **Pure Core, Impure Shell** design:

- **Domain logic:** `Engine` performs deterministic state transitions and trie lookup.
- **Presentation model:** `EngineState` derives composition and candidate data.
- **Framework shell:** `InputController` maps engine actions to macOS `InputMethodKit` APIs.

The [technical specification](docs/SPECIFICATION.md#architecture) is the canonical architecture definition.

## Building and Installation

The project currently has a macOS 15.5 deployment target. The published v0.1.2 archive contains an arm64 binary, so it does not run on Intel Macs.

### Install the published archive

1. Download `unicorn-macos.zip` and `checksum.txt` from [GitHub Releases](https://github.com/vic0103520/unicorn-macOS/releases).
2. Extract `unicorn-macos.zip`.
3. From the extracted directory, verify that the SHA256 digest of `unicorn.app/Contents/MacOS/unicorn` matches the separately downloaded checksum.
4. Run the installer from that directory in Terminal:

   ```sh
   sh install.sh
   ```

5. Read the security notice and confirm only if you accept the risks.

### Build and install from source

The [Makefile](Makefile) builds the Xcode project and installs the app in the current user's input-method directory:

```sh
make install
```

Contributor build, test, and release entry points are documented in [`AGENTS.md`](AGENTS.md); the [`Makefile`](Makefile) is authoritative for command behavior.

### Enable the input method

1. Open **System Settings** > **Keyboard** > **Input Sources**.
2. Click **Edit**, then click **+**.
3. Search for **Unicorn** and click **Add**.

## Security and Privacy

Unicorn is an independent open-source project. The [Makefile](Makefile) build and published v0.1.2 artifact are ad-hoc signed and are not notarized by Apple, so macOS may display security warnings. Read the following risks before installing.

1. **Full keystroke access:** Input methods can technically observe every keystroke across applications, including passwords and private data.
2. **No Apple notarization:** Apple has not notarized or scanned the distributed binary, and ad-hoc signing does not verify the developer's identity.
3. **Tampering risk:** A warning that the app is damaged can indicate quarantine or that downloaded software may have been altered.
4. **Data exfiltration risk:** Any untrusted input method could potentially transmit captured data.

The source is available in this [GitHub repository](https://github.com/vic0103520/unicorn-macOS) for inspection. Unicorn's entitlements do not request network access, and the current source contains no network client behavior. The installer displays the main binary's SHA256 digest, but trust requires comparing it with a checksum obtained independently from the release assets.

The installer asks for confirmation before removing the app's quarantine attribute, copying it to `~/Library/Input Methods/`, and registering it with Launch Services. If macOS still blocks the app, use the authorization options shown by System Settings or Finder only after verifying and trusting the artifact.

Technical signing, installer, integrity, and release-verification behavior is canonical in [Security and Distribution](docs/specs/security_and_distribution.md).

## Technical Documentation

- [Specification index](docs/SPECIFICATION.md)
- [Functional Swift style guide](docs/STYLE_GUIDE.md)
- [Documentation guide](docs/DOCUMENTATION_GUIDE.md)
