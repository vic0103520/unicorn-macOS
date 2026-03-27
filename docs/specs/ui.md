# UI Behavior & Presentation

The UI layer (Tier 2 and Tier 3) transforms the internal **Engine State** into a user-facing interface using macOS `InputMethodKit` (IMK) APIs.

## 1. Composition Area (Marked Text)
The composition area displays the current input session directly in the focused application's text field.
*   **Composition Text:** The text displayed is the concatenation of `committedPrefix` and the active `buffer`.
*   **Visual Style:** Following macOS standards, the composition text is underlined to indicate it is not yet committed.
*   **Cursor Position:** The cursor (selection range) is always maintained at the **end** of the composition text.

## 2. Candidate Window
The candidate window is a floating panel that appears when multiple symbols match the current input sequence.
*   **Visibility:** The window is shown only when the engine is `active` and the `candidateWindow` state contains at least one candidate.
*   **Capacity:** Each "page" of candidates displays up to **9 items**, corresponding to the numerical selection keys `1-9`.
*   **Synchronization:**
    *   When the engine state changes, `InputController` triggers a `syncUI` call.
    *   The `IMKCandidates` window is updated with the full candidate list from the engine state.
    *   The `candidateWindow` state in the engine tracks the currently selected index and the first visible index for pagination.

## 3. Navigation
User navigation actions update the `candidateWindow` state and are reflected in the UI:
*   **Vertical Movement:** Arrow `Up` and `Down` keys move the selection index within the list.
*   **Horizontal/Page Movement:** `Page Up` and `Page Down` (mapped to `Left`/`Right` arrow keys in some contexts) jump the selection by the page size.
*   **Numeric Selection:** Direct selection of a candidate on the current page using digits `1-9` (see [Engine Logic](engine.md) for selection resolution).
