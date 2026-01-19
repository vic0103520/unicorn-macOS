# Project Context: Unicorn Input Method

## Overview
**Unicorn** is a native macOS Unicode Input Method designed to allow easy insertion of Agda and Unicode symbols (e.g., typing `\lambda` to get `λ`).

The project follows a **Native macOS Architecture**:
*   **Language:** Written entirely in **Swift**.
*   **Frameworks:** Built on `InputMethodKit` (macOS) and `XCTest`.
*   **Design:** Separates pure logic (`Engine`) from system effects (`InputController`).

## Architecture

### 1. Engine (Swift)
*   **Role:** The brain of the input method. Pure logic.
*   **Location:** `unicorn/Engine.swift`
*   **Responsibility:**
    *   Loads and traverses the Trie from `keymap.json`.
    *   Manages the state machine (buffer, active status, candidates).
    *   Determines actions (`Commit`, `Update`, `Reject`) based on input.
    *   **Deterministic:** Contains no UI or system dependency code.

### 2. KeyCode (Swift)
*   **Role:** Event Normalization.
*   **Location:** `unicorn/KeyCode.swift`
*   **Responsibility:**
    *   Maps raw `NSEvent` key codes and modifiers to a type-safe `KeyCode` enum.
    *   Enforces standard macOS text input rules (e.g. ignoring Command/Control shortcuts).

### 3. InputController (Swift)
*   **Role:** The system shell. Handles the "Effects".
*   **Location:** `unicorn/InputController.swift`
*   **Responsibility:**
    *   Implements `IMKInputController`.
    *   Intercepts key events from macOS.
    *   Forwards input to `Engine`.
    *   Renders the Candidate Window and Composition Text.

## Building and Running

The project is a standard Xcode project wrapped with a Makefile for convenience.

**Build & Install:**
```bash
make install
```
This builds the app, installs it to `~/Library/Input Methods/`, registers it, and restarts the process.

**Run Tests:**
```bash
make test
```
Runs the `EngineTests` suite.

## Key Files & Directories

*   `docs/SPECIFICATION.md`: Detailed architectural and behavioral specification.
*   `docs/STYLE_GUIDE.md`: Swift functional programming style guide.
*   **`unicorn/`**: Source code.
    *   `Engine.swift`: Core logic state machine.
    *   `KeyCode.swift`: Input event normalization.
    *   `InputController.swift`: macOS InputMethodKit integration.
    *   `keymap.json`: Symbol data.
*   **`unicornTests/`**: Unit tests.
    *   `EngineTests.swift`: Tests for `Engine` logic.
*   `Makefile`: Build automation.

**Key Summary:**
*   **Architecture:** Separation of concerns is paramount. Logic lives in `Engine.swift` (Pure), Normalization in `KeyCode.swift`, UI in `InputController.swift` (Effects).
*   **State:** The `Engine` is the single source of truth.
*   **Testing:** Logic sequences must be covered by unit tests in `unicornTests/EngineTests.swift`.
