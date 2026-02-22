# Unicorn Input Method Specification

## 1. Architecture
Unicorn is a native macOS Input Method implemented in Swift. It follows a **Pure Core, Impure Shell** design consisting of three distinct tiers:

*   **Tier 1: Domain Logic (Engine):** The **Pure Core**. A deterministic state machine. It receives `KeyCode` events and returns semantic `EngineAction` intents (`sync`, `navigate`, `commit`, `reject`). It encapsulates all business logic, trie traversal, and history management.
*   **Tier 2: Presentation Model (EngineState Extensions):** Part of the **Pure Core**. A bridge between logic and UI. This layer consists of pure functions on `EngineState` that calculate UI-specific data (e.g., `compositionText()`, `selectionRange()`)
*   **Tier 3: Framework Glue (InputController):** The **Impure Shell**. A "dumb" layer that translates macOS `NSEvent`s into `KeyCode`s, feeds them to the `Engine`, and maps the logic outputs to macOS InputMethodKit APIs.

## 2. How to Read These Specifications
This documentation is modular. To understand or modify specific parts of the system, please refer to the following modules:

*   **If you are working on the Engine state machine:** See [Engine State Transition](specs/engine.md).
*   **If you are working on Activation/Deactivation:** See [Activation & Deactivation](specs/activation.md).
*   **If you are working on the UI/Presentation Layer:** See [UI Behavior](specs/ui.md).
*   **If you are working on Security, Signing, or Distribution:** See [Security & Distribution](specs/security_and_distribution.md).

## 3. Module Map
Detailed logic and constraints are housed in the `docs/specs/` directory:

| Module | Description |
| :--- | :--- |
| [Architecture](#1-architecture) | The foundational Three-Tier design (defined in this document). |
| [Activation](specs/activation.md) | Triggers for starting/stopping the input method. |
| [Engine](specs/engine.md) | State machine logic, key processing, and undo history. |
| [UI Behavior](specs/ui.md) | Candidate window and composition text rules. |
| [Security & Distribution](specs/security_and_distribution.md) | Runtime limits, ad-hoc signing, and verification strategies. |
