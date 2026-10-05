# Heap-list task completion: presentation handoff

**Scope:** completion controls and retained completed rows in the On-deck list only. Inbox rows, editor controls, toolbar, filtering, history screens, and all other navigation remain unchanged. This document guides presentation; it does not define or imply an API shape.

## Row presentation

Replace the On-deck row's decorative leading priority dot with a distinct circular completion control. Keep the established unboxed row, divider, title/metadata hierarchy, spacing, and responsive layout. Center a 22–24 px circle/check visual inside a minimum 48 × 48 logical-pixel hit target. Keep the row's existing content inset and align the control with the title; do not compress the text column to make room. At narrow widths and enlarged text, allow title and metadata to wrap exactly as they do today. The divider remains inset to the text column, not under the control.

The control is the only completion/undo action. It is independent of the row body:

- Unfinished: tapping the row body opens the existing editor; tapping the circle completes the task.
- Retained completed row: tapping the body does nothing and it is not exposed as an editor button. The circle remains available to undo.
- Do not make the whole row a completion target, add swipe actions, or add confirmation dialogs.

Preserve all existing row metadata and its arrangement, including title, full priority label, duration, project-independent existing information, and the awaiting-external-dependencies badge when true. Do not add completion timestamps, new metadata, or history affordances to the row.

## Completion appearance and retention

Only show the checked state after the server confirms completion. On confirmation, keep the row in its exact current position with the same task fields and metadata; do not reorder, remove, replace, or optimistically alter its content. Render the whole retained row in a neutral grey treatment: title and supporting metadata remain clearly readable, and the priority pill is neutralized while preserving its text label. Do not use a blanket low-opacity overlay, which would also wash out text and controls. Do not strike through the title. Keep the checked control visually distinct and clearly checked.

The checked row is temporary list state, not a new completed-task view. Keep it in place until any successful On-deck list reload. A successful reload is authoritative: replace the list from the server response, so a completed task no longer returned by the On-deck endpoint disappears. A failed reload is not successful and must not clear the retained checked row or its metadata.

A confirmed undo returns the row to its unfinished appearance in the same position, with its original fields and original `on_heap_since`; do not reset its age, alter metadata, or reorder it. Do not claim the undo succeeded before server confirmation.

## Pending and failure states

While a completion or undo request is pending, disable that row's control so repeated taps cannot submit duplicate operations. Keep the current confirmed visual state (unchecked for completion, checked for undo); do not show speculative success. Provide a small, legible pending indicator/state associated with that row without changing its position or hiding metadata. Leave other rows usable.

For a definite server rejection, keep the prior confirmed state and show a readable, row-associated error with a deliberate retry via the same control. Do not silently swallow the error or remove the row.

For an outcome that is unknown (for example, a timeout), do not claim success or failure and do not immediately allow another toggle. A timeout does not cancel the write: a successful On-deck list GET alone cannot prove that the write failed or is finished. Keep the last confirmed row appearance and its unresolved warning; keep completion/undo writes disabled until the outcome is explicitly checked. Do not automatically resubmit the write.

Provide an explicit per-task `Check task status` action. It performs a fresh GET of that task's status, not another completion/undo write:

- If the fetched status matches the requested outcome (completed after completion, On-deck/unfinished after undo), accept that as confirmation of the task's current state. Clear the unresolved warning and render that state using the normal retention rules. For confirmed completion, keep the checked row until a successful list reload; for confirmed undo, show the unchecked row in its original position with original fields and `on_heap_since`.
- If the fetched status differs from the requested outcome, do not treat it as proof that the write failed or has finished. Keep the unresolved warning and disable further writes. Offer `Check again` as an explicit status GET; never unlock completion/undo merely because the fetched state matches the pre-write state.
- If the status check fails, keep the unresolved warning and disabled writes; allow another explicit `Check again`.

A successful list reload still reconciles the visible On-deck rows and removes completed tasks returned no longer by that endpoint. However, a reload is not a substitute for `Check task status`: if it shows a differing/pre-write state, or omits the task, preserve the unresolved warning and the explicit status-check path. Do not infer write failure from row absence or list state, and do not discard unresolved state just because the list GET succeeded. Failed reloads also preserve the unresolved warning. Only a status check matching the requested outcome resolves this uncertainty.

Use concise inline text or an equivalent persistent, accessible warning, not snackbar-only feedback. Identify the task and action; for example, “Completion of [title] may have succeeded. Check task status before trying again.” The warning must retain a reachable `Check task status` / `Check again` action even if a successful list reload removes the row. A pending indicator must have an accessible status announcement.

## Accessibility and responsive behavior

- Give the control a minimum 48 × 48 logical-pixel target, including on web and at narrow widths. Keep the visible circle compact; do not turn the whole row into an oversized checkbox.
- Expose a button/toggle semantic with task-specific action and state: `Complete [title]` when unfinished; `Undo completion for [title]` when completed. Expose checked state and disabled/pending state, not color alone.
- Keep row-body semantics separate: unfinished body announces the existing task details and `Open task editor`; completed body is readable content, not an actionable button. Exclude the nested control from the row body's semantics to avoid a combined or duplicate action.
- Preserve a clear keyboard focus outline on the control and visible hover/pressed feedback. Tab/activation must operate the control without opening the editor; body activation must not toggle completion.
- Neutral colors must retain readable contrast for title, labels, metadata, pending/error copy, and focus. Priority remains explicitly named (for example `P2 Important`) even when its color treatment is neutralized.
- At 320 px and enlarged text, retain the full target and let all existing text wrap; no clipping, forced single-line title, or horizontal scrolling. Error/uncertain messages wrap and remain reachable without covering the row or list controls.

## Review checklist

1. On-deck only: Inbox dot/rows and every other screen remain untouched.
2. Before server confirmation the row is not checked; after confirmation it is checked and remains at the same position with unchanged fields/metadata.
3. Successful list reload reconciles/removes completed rows, but does not resolve uncertain writes; unresolved warnings and status-check actions survive differing/pre-write results and row absence. Failed reload preserves them too.
4. Undo is server-confirmed, returns the row in place, and preserves fields and the exact original `on_heap_since`.
5. Pending blocks duplicate toggles. Definite rejection and unknown outcome are visibly and accessibly distinct. After an unknown outcome, only an explicit task-status GET matching the requested state resolves uncertainty; differing/pre-write status, row absence, or list reload alone keeps writes disabled and offers Check again.
6. Completed row body cannot open the editor; unfinished row body still does. Control and body are separately reachable and announced.
7. 48 px target, keyboard focus/activation, readable neutral completed styling, and 320 px / enlarged-text wrapping are verified.
