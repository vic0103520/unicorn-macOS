# UI Behavior and Presentation

The presentation model on `EngineState` derives values without calling macOS APIs. `InputController` and the global `IMKCandidates` panel form the framework shell that applies those values.

## Marked Text

`EngineState.compositionText()` concatenates `committedPrefix` and `buffer`. `selectionRange()` returns a zero-length range at the end of that string.

For each `.sync` action, `InputController` passes those values to `IMKTextInput.setMarkedText`. The source does not assign an explicit underline, color, or other attributed-string styling; rendering of the plain marked-text value is left to the host and `InputMethodKit`.

A terminal `.commit(text)` calls `IMKTextInput.insertText`, hides the candidate panel, and relies on the engine's already-reset state.

## Candidate Panel

`AppDelegate` creates a single-column scrolling `IMKCandidates` panel. The presentation model requests candidate visibility only while the engine is `active` and its current candidate list is nonempty.

During `.sync`, `InputController` asks the panel to update and either shows or hides it. The controller's `candidates(_:)` data-source method exposes the engine's complete current candidate list to `InputMethodKit`.

The engine separately maintains:

- `selectedIndex`, the logical selected candidate;
- `firstVisibleIndex`, the start used for numeric page selection; and
- `pageSize`, currently 9.

These values define engine navigation and number-key selection. They do not claim a fixed number of rows rendered by the native scrolling panel.

## Navigation and Selection

- Up and Down move the engine selection by one candidate and ask the native panel to move in the same direction.
- Left and Right move the engine's paging state and map to the panel's left and right movement methods, which `InputController` uses for page movement in the vertical panel.
- Digits `1` through `9` can commit candidates relative to the engine's `firstVisibleIndex` when trie continuation does not take priority.
- A mouse-selected candidate is inserted through `InputMethodKit`'s `candidateSelected` callback, after which the engine deactivates.

The detailed processing priority and selection formulas are defined in [Engine Logic and State Transitions](engine.md).
