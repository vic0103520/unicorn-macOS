# Activation and Deactivation

## Activation

Typing backslash (`\`) while the engine is inactive activates Unicorn composition. The engine starts with `\` in its `buffer`, the trie `path` at its root, an empty `candidateWindow`, and the prior inactive state in `history`. It returns `.sync`, which causes `InputController` to synchronize marked text and the candidate panel.

## Pass-through Outside a Composition

`InputController` translates macOS events into `KeyCode` values and executes the actions returned by the engine.

- Events that cannot be translated, including non-key-down events and Command- or Control-modified key events, are not consumed.
- While the engine is inactive, a translated key other than backslash produces no action and is not consumed.
- An `.reject` action makes the controller return the original event to macOS. During invalid-input fallback, the engine can first return `.commit` and then `.reject`, so the resolved composition is inserted before macOS handles the triggering event.

This behavior provides ABC-style pass-through whenever no Unicorn composition is `active`.

## Commit and Deactivation

Terminal engine commits reset the engine to an inactive state with an empty `buffer` and `committedPrefix`, a root-only trie `path`, an empty `candidateWindow`, and empty `history`.

### Enter

Enter commits `committedPrefix` plus the selected candidate when one exists. If no candidate is selected and the `buffer` is nonempty, it commits `committedPrefix` plus the raw `buffer`. The current implementation consumes Enter and does not append a newline. Enter outside a composition produces no engine action; an `active` state with an empty `buffer` would return `.reject` without resetting.

### Numeric selection

Trie continuation has priority over numeric selection. If a digit from `1` through `9` does not continue the current trie `path`, it commits the corresponding candidate in the engine's current nine-item page when that candidate exists. An out-of-range selection returns `.reject` and leaves the composition `active`.

### Mouse selection

When `InputMethodKit` reports a clicked candidate, `InputController` inserts the clicked candidate string and then deactivates the engine. This `candidateSelected` callback does not use the engine's normal terminal-commit path.

### Automatic transitions

- Reaching a trie leaf with exactly one candidate commits that candidate automatically.
- An unmatched non-backslash, non-selection character commits the selected candidate, first candidate, or raw `buffer` as the best available resolution. The triggering character is then rejected for normal macOS handling.
- When backslash cannot continue the trie and a candidate is selected, the engine soft-commits that candidate into `committedPrefix`, resets the `buffer` to `\`, and keeps the composition `active`.
- When backslash cannot continue the trie and no candidate is selected, the engine commits `committedPrefix` + `buffer` + `"\\"` and deactivates.
- **Double backslash:** In the bundled keymap, backslash is a root child with one literal-backslash candidate. Two consecutive backslashes from an inactive state therefore reach that leaf and auto-commit one literal backslash. The engine's no-candidate fallback can produce different output for a keymap without that mapping.

## Backspace

Backspace first restores the most recent `history` snapshot. If `history` is unavailable, it removes one buffered character and one trie-`path` step. That fallback deactivates when both the resulting `buffer` and existing `committedPrefix` are empty. Backspace with neither `history` nor buffered text also deactivates.

`KeyCode` has no explicit Escape case. An Escape event that reaches the character path is therefore handled by the same trie or fallback rules as its translated characters.

## InputMethodKit Lifecycle

When `InputMethodKit` deactivates the input-method server, `InputController.deactivateServer` resets the engine, hides the candidate panel, and forwards the lifecycle event to its superclass.
