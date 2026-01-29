# Functional Swift Style Guide (Unicorn)

## Core Philosophy
Unicorn follows a **Pure Core, Impure Shell** design. We prioritize predictability and testability by keeping our business logic deterministic, while isolating side effects and framework interactions in a thin, imperative layer.

---

## 1. Immutability & State Management
- **Prefer `let` over `var`:** All data structures should be immutable by default.
- **Value Types for State:** Use `struct` or `enum` for all data representing a "moment in time" (e.g., `EngineState`). 
- **Controlled Mutation:** Mutation is restricted to the state-management layer (e.g., the `Engine` class). Logic functions must never mutate state in place.
- **Pure Transformers:** Methods on state structs must return a new `Self` rather than using `mutating func`.

## 2. The Three-Tier Architecture
To keep logic clean and the UI predictable, code is split into three layers:
1.  **Domain Logic (Engine):** Pure functions that decide *what* happens. Returns semantic `EngineAction` intents.
2.  **Presentation Logic (Extensions):** Pure functions/extensions on states that calculate *how it looks* (e.g., string concatenations, `NSRange` calculations).
3.  **Framework Glue (InputController):** A "dumb" shell that maps logic outputs to macOS APIs. It contains **zero decisions**.

## 3. Class Usage Policy
While we prefer value types, `class` is permitted in specific scenarios:
- **Framework Compliance:** When inheriting from system classes (e.g., `IMKInputController`).
- **Structural Efficiency:** Use `final class` for large, static, or recursive data structures (e.g., `Trie`). These must be **strictly immutable** (`let` properties only).
- **Manager Identity:** Use `class` for objects that provide a stable reference and manage the state transition loop (e.g., `Engine`).

## 4. Higher-Order Functions & Performance
- **Declarative Collections:** Use `map`, `filter`, and `compactMap` for clarity on small collections (Buffers, Candidate lists).
- **Lazy Evaluation:** Use `.lazy` when chaining multiple transformations on potentially large datasets.
- **Locally Imperative:** For complex reductions, it is acceptable to use a `for-in` loop with a local `var` accumulator *inside* a pure function to maintain performance and readability.

## 5. Functional Error Handling
- **Optional:** Use for "expected absence" (e.g., a dictionary lookup that might fail).
- **Result:** Use `Result<Value, Error>` for logic that can fail with a specific reason.
- **Throws:** Reserve `throws` for the shell layer (I/O, file loading). Core logic should be error-agnostic or use `Result`.

## 6. Composition
- **Single Responsibility:** Functions should be small and do one thing. If a logic function exceeds 30 lines, extract its sub-steps into private pure functions.
- **Sequential Narratives:** For complex multi-step transformations, prefer intermediate `let` variables with descriptive names over deeply nested parentheses. This mimics the clarity of a Haskell `do` block.
- **Functions as Dependencies:** Prefer passing closures `(A) -> B` into logic functions rather than using complex Protocols/Delegates.
- **Logical Extensions:** Use `extension Engine { ... }` to group related logic into modules.

## 7. Functional Operators
To clarify the flow of computation, Unicorn provides a set of generic operators in `FunctionalHelpers.swift`:
- **Pipeline (`|>`):** Use for forward application of functions (`x |> f`). Best for data transformations where naming an intermediate variable adds noise.
- **Bind (`>>=`):** Use for chaining operations on `Optional` or `Result` types. This short-circuits nested `if let` or `guard let` chains.
- **Avoid Custom Operators:** Do not introduce new operators beyond these two without a project-wide discussion.
