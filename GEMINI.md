# Project Context: Unicorn Input Method

## Overview
**Unicorn** is a native macOS Unicode Input Method designed to allow easy insertion of Agda and Unicode symbols (e.g., typing `\lambda` to get `λ`).

The project follows a **Pure Core, Impure Shell** architecture:
*   **Language:** Written entirely in **Swift**.
*   **Frameworks:** Built on `InputMethodKit` (macOS) and `XCTest`.

## Architecture

The project is structured into three tiers:

### 1. Tier 1: Domain Logic (Engine)
*   **Role:** The brain of the input method. Pure logic.
*   **Location:** `unicorn/Engine.swift`
*   **Responsibility:**
    *   Loads and traverses the Trie from `keymap.json`.
    *   Manages the state machine (buffer, active status, candidates, committed prefix).
    *   Maintains a state history for Undo operations.
    *   Determines semantic actions (`sync`, `navigate`, `commit`, `reject`) based on input.
    *   **Deterministic:** Contains no UI or system dependency code.

### 2. Tier 2: Presentation Model (EngineState Extensions)
*   **Role:** Bridge between logic and effects.
*   **Location:** `unicorn/EngineTypes.swift`
*   **Responsibility:**
    *   Calculates UI-specific data (e.g., `compositionText()`, `selectionRange()`).
    *   Pure functions that transform domain state into "UI-ready" data for macOS APIs.

### 3. Tier 3: Framework Glue (InputController)
*   **Role:** The system shell. Handles the "Effects".
*   **Location:** `unicorn/InputController.swift`
*   **Responsibility:**
    *   Implements `IMKInputController`.
    *   Intercepts key events and normalizes them via `KeyCode.swift`.
    *   Forwards input to `Engine`.
    *   Maps state data to `IMKTextInput` and `IMKCandidates`.

## Coding Standards
All Swift code in this project must strictly adhere to the **Functional Swift** approach defined in `docs/STYLE_GUIDE.md`.

**Mandatory Principles:**
*   **Immutability:** Use `let` and immutable structs/enums by default.
*   **Three-Tier Architecture:** Keep logic pure in the `Engine`, put UI calculations in `Extensions`, and use `InputController` as a "dumb" effect shell.
*   **Controlled Mutation:** Limit `var` to local accumulators or the central `Engine.state`.
*   **Computation Flow:** Use the `|>` (pipeline) and `>>=` (bind) operators for clear, monadic data transformations.

## Building and Running

The project is a standard Xcode project wrapped with a Makefile for convenience. All builds are automatically ad-hoc signed (`-`) to ensure compatibility with modern macOS security requirements. 

**Note on Security:** Because the project is not notarized by Apple, users will encounter "Unverified Developer" or "Damaged" warnings. Distribution includes an `install.sh` script to handle Gatekeeper bypass and installation while providing necessary security disclosures.

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

**Check Coverage:**
```bash
make coverage
```
Generates a detailed line coverage report for the Engine logic.

## Key Files & Directories

*   `docs/SPECIFICATION.md`: Detailed architectural and behavioral specification.
*   `docs/STYLE_GUIDE.md`: Swift functional programming style guide.
*   **`install.sh`**: One-click installer for pre-built binaries (handles Gatekeeper bypass).
*   **`unicorn/`**: Source code.
    *   `Engine.swift`: Core logic state machine.
    *   `EngineTypes.swift`: Data structures (`EngineState`, `CandidateWindow`) and Presentation Model.
    *   `FunctionalHelpers.swift`: Generic functional operators (`|>`, `>>=`).
    *   `Trie.swift`: Trie data structure for symbol lookups.
    *   `KeyCode.swift`: Input event normalization.
    *   `InputController.swift`: macOS InputMethodKit integration.
    *   `keymap.json`: Symbol data.
*   **`unicornTests/`**: Unit tests.
    *   `EngineTests.swift`: Tests for `Engine` logic and Presentation Model.
*   `Makefile`: Build automation.

**Key Summary:**
*   **Architecture:** Three-Tier architecture (Domain -> Presentation -> Effect).
*   **State:** The `Engine` is the source of truth; `EngineState` provides the view.
*   **Testing:** Logic and Presentation Model verified by unit tests in `unicornTests/EngineTests.swift`.