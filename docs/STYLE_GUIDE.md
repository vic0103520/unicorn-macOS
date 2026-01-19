# Functional Swift Style Guide

## Core Philosophy
Unicorn prioritizes a functional programming approach to ensure predictable, testable, and robust logic, particularly within the Core Engine.

## 1. Immutability
- **Prefer `let` over `var`:** All data structures should be immutable by default. Only use `var` within local scopes (like loop accumulators) if absolutely necessary and contained.
- **Immutable Models:** Define core data types (e.g., `Trie`) as `structs` with `let` properties.
- **State Management:** Avoid mutating state in place. Instead of modifying an object, return a new instance with the updated value.

## 2. Pure Functions
- **Definition:** Functions should rely only on their inputs and produce output without side effects (no global state mutation, no I/O within logic functions).
- **Determinism:** Given the same input, a function must always return the same output. This makes unit testing the Engine logic trivial and reliable.
- **Separation:** Strictly separate "Logic" (pure functions) from "Effects" (UI updates, system calls). The `Engine` class should ideally be a value type or a manager of value types, while `InputController` handles the effects.

## 3. Higher-Order Functions
- **Declarative Collection Handling:** Prefer `map`, `filter`, `reduce`, `flatMap`, and `compactMap` over imperative `for` loops.
  - *Bad:*
    ```swift
    var results: [String] = []
    for item in items {
        if item.isValid { results.append(item.name) }
    }
    ```
  - *Good:*
    ```swift
    let results = items.filter { $0.isValid }.map { $0.name }
    ```
- **Function Composition:** Build complex logic by composing smaller, single-purpose functions.

## 4. Value Types over Reference Types
- **Structs & Enums:** Use `struct` for data models and `enum` for state/actions.
- **Avoid Classes:** Use `class` only when reference semantics are explicitly required (e.g., interfacing with Objective-C APIs like `InputMethodKit`).
- **Enums for State:** Use `enum` with associated values to model finite states (e.g., `EngineAction.commit(text: String)`).

## 5. Optionals & Error Handling
- **No Force Unwrapping:** Never use `!`. Use `guard let` or `if let` to safely handle optional values.
- **Result Type:** Use `Result<Success, Failure>` for operations that can fail, rather than throwing exceptions, to keep control flow explicit and functional.
