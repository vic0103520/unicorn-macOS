# Unicorn Project Backlog

This document tracks planned features, architectural improvements, and technical debt.

## 1. Features & UX Improvements
*   [ ] **Configurable Constants:** Move `MAX_BUFFER_LENGTH` and `MAX_HISTORY_DEPTH` from hardcoded constants in `Engine.swift` to a configuration file (e.g., `Settings.plist` or `unicorn.json`).
*   [ ] **Visual Soft-Commit Feedback:** Add a visual indicator (e.g., a different underline style or color) to the `compositionText` to distinguish between the `committedPrefix` and the active `buffer`.
*   [ ] **Custom Keymaps:** Implement a mechanism for users to provide their own `keymap.json` in `~/Library/Application Support/Unicorn/`.
*   [ ] **Paging UI:** Improve the candidate window to explicitly show "Page X of Y" information.

## 2. Architectural Improvements
*   [ ] **Trie Optimization:** Evaluate the performance and memory benefits of a Double-Array Trie (DAT) if the keymap grows beyond 1MB. (Currently, the JSON-backed Trie is sufficient).
*   [ ] **Implicit Commit Refinement:** Standardize the "Implicit Commit" behavior across all edge cases (e.g., ensuring consistent rejection logic for different categories of punctuation).
*   [ ] **State Serialization:** Implement `Codable` for `EngineState` to allow for session persistence across app restarts or crashes.

## 3. Refactoring (Golden Cleanup)
*   [ ] **Engine Logic Partitioning:** Consider splitting the large `reduce` function in `Engine.swift` into smaller, specialized reducers (e.g., `NavigationReducer`, `CharacterReducer`) to maintain legibility.
*   [ ] **Test Coverage:** Increase unit test coverage for complex "Soft Commit" sequences and edge cases in `EngineTests.swift`.

## 4. Distribution & CI/CD
*   [ ] **Automated Integrity Checks:** Integrate SHA256 checksum generation directly into the GitHub Release workflow and embed it in the release's `metadata.json`.
*   [ ] **Installer Localization:** Localize the security disclosures in `install.sh` for multi-language support.

## 5. Documentation
*   [x] Modularize system specifications (Architecture, Engine, UI, Security).
*   [x] Create a "How to Read" navigation guide for specifications.
*   [ ] Add a "Contributor's Guide" detailing the environment setup for new developers.
