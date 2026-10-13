# Completion-based recurrence UI

Status: presentation handoff for approved completion-based recurrence behavior. This covers the task editor and the existing Heap completion control only. It does not define API or persistence shape.

## Scope and behavior

Offer recurrence only for completion-based intervals: every positive whole number of days or months, measured from the device-local calendar date on which the task is actually completed. Month intervals clamp to the last valid day when needed; each later occurrence calculates from its own completion date, not the original day-of-month. There is no calendar-based cadence, weekday picker, catch-up schedule, or pile of missed occurrences.

The next occurrence is created atomically with confirmed completion. It is not inserted into or otherwise shown on the currently loaded screen until a successful refresh. Keep the existing completed row and completion/undo behavior; do not optimistically add a task or change list ordering. A refresh is authoritative.

The recurrence belongs to the current task. Its settings can be changed in that task's existing editor. `Off` stops future recurrence. Deleting the current task ends its recurrence. Do not add a series editor, recurrence history, new destination, or extra navigation. A task's repeat setting is part of the existing draft and is submitted only by the existing `Save`.

A generated occurrence copies the completed task's title, project, priority, duration, and repeat setting. It starts with waiting off, no dependencies, and fresh Heap age. Do not copy due date or invent other copied metadata; recurrence is not a date-based schedule. Calendar-based recurrence remains out of scope.

## Task editor control

Add the `Repeat` controls to the existing full-page `Edit task` form, after Duration and before Due date. Preserve the current warm canvas, outlined fields, 640-pixel editor cap, form spacing, and single `Save` action styled by the current Paper desk theme.

Use 1 outlined selector labeled `Repeat` with exactly 3 choices: `Off`, `Days`, and `Months`. When `Days` or `Months` is selected, show an outlined numeric field labeled `Interval` for the positive whole-number count. The selected unit remains visible in the Repeat selector; do not add a second Unit selector or combine the number and unit into a menu. The form reads, for example, `Repeat [Months ▾]` followed by `Interval [ 2 ]`.

When `Off` is selected, hide the Interval field and clear recurrence from the draft. Switching between Days and Months keeps the interval number. Turning recurrence on from Off reuses the number still in the open form, or defaults to `1` if none exists. Avoid a new card, icon-only affordance, or decorative recurrence metadata. Reuse existing dropdown and outlined text-field styling; stack controls on narrow layouts.

Repeat changes are draft-only and participate in the editor's dirty check, discard confirmation, save disabling, server rejection preservation, conflict comparison, and uncertain-save recovery like the other fields. Do not auto-save after selecting a unit or changing the interval. Saving `Off` is how the user stops future recurrence; do not add a separate stop action or confirmation.

Completed tasks keep the existing read-only terminal editor behavior. Do not make recurrence edits available from a completed-task screen; undo remains the explicit way to restore the completed occurrence, subject to the guard below.

## Validation and recovery presentation

Represent the interval as canonical positive decimal text. Any digit string matching `[1-9][0-9]*` is valid; do not parse it into a bounded numeric type or impose an arbitrary maximum. Blank, zero, negative, leading-zero, signed, whitespace-containing, decimal, exponent, or nondigit values are invalid. Use an integer keyboard where available, but always validate the submitted text. Keep the user's text in the draft after validation or server rejection. Large values remain lossless and editable, can be scrolled within the numeric text field, and can be turned Off. Show a concise field error such as `Enter a whole number greater than 0.` for invalid text and focus/scroll to Interval as the editor does for other invalid fields. The task editor does no interval arithmetic; if a resulting due date is unsupported, present that as a backend completion rejection, not a client numeric conversion failure. `Off` requires no interval.

Include the recurrence value in saved-task and draft summaries wherever the editor already shows a comparison or preserved draft: show `Repeat: Off` or `Repeat: Every 2 months`. A conflict or uncertain save must preserve and compare the recurrence setting; do not silently replace either version or write during reconciliation. Apply the existing explicit `Use saved version` / `Keep my edits` choices and require a deliberate Save after keeping edits.

Undo of a completed recurring task must be guarded against destructive cleanup of its successor or changes to the current incoming/outgoing dependency links. If undo is rejected because the generated successor has since been edited, completed, or deleted, or because dependency links have changed, keep the completed occurrence in its last confirmed visual state and do not claim the undo succeeded. Show persistent, readable task-associated feedback, for example: `Can't undo completion because the next occurrence or its dependencies changed. The completed task is unchanged.` Distinguish a normal definite rejection from an unknown request outcome. For unknown outcomes, retain the existing completion design's locked state and explicit task-status check; never retry the undo automatically. On rejection, leave the successor and dependency links untouched and provide a deliberate refresh/status check where needed to see current tasks. Do not remove a successor, alter links, or restore the prior task optimistically.

If the server confirms undo, follow existing confirmed undo behavior and preserve the original Heap age. A retry after a definite rejection is a new deliberate user action, not an automatic retry.

## Accessibility and responsive layout

- Every field and selector has a persistent visible label; expose current value, selection, and validation error to screen readers. The numeric field has an integer keyboard hint but remains operable with hardware keyboards and web.
- Use at least 48 logical pixels for tap targets, including the Repeat menu affordance. Preserve visible focus outlines, standard keyboard menu navigation, and predictable Tab order: existing fields, Repeat, Interval when enabled, then remaining fields and Save.
- At 320-pixel width and 2.0 text scale, stack Repeat and Interval, let labels and errors wrap, and keep all text and Save reachable by scrolling. Do not shrink text, clip labels, or introduce horizontal scrolling.
- On wide web, retain the single-column editor inside its existing centered 640-pixel cap; do not create a split pane. Existing priority/duration responsive layout remains unchanged.
- Follow the task editor's existing short-height/large-text rule: when usable height is below 400 logical pixels or text scale is at least 1.5, put Save at the end of the scrolling form. Apply the keyboard inset once and keep a focused error field scrollable into view.
- Announce validation and save state changes once. Keep undo rejection and uncertain-outcome copy persistently visible and readable, not snackbar-only. Error text must wrap without covering the task row or completion control.

## Frontend handoff

Implement only the editor controls and presentation for completion/undo outcomes in the existing screens. Keep recurrence in the existing task draft/Save flow; rely on the confirmed completion response and normal refresh rather than synthesizing a successor in the client. Render the backend's guarded-undo rejection as a persistent row-associated error while retaining the existing uncertainty recovery for timeouts. Include Off, Days/Months values, interval validation, draft/discard, conflict and uncertain-save presentation, narrow/large-text layout, and undo rejection when the successor was edited/completed/deleted or dependency links changed in the frontend checks. This is design guidance, not verification or authorization to change files beyond this handoff.

## Screenshot review

Visual review: approved. The editor controls follow the design: Repeat is a single Off/Days/Months selector, Interval appears only when enabled, and both sit after Duration and before Due date. The web screenshots show the normal, invalid, discard, Off, completed, and undo-rejection states. The Android screenshots show the controls at the supplied 320-logical-pixel width and 2.0 text scale, including scrolling to Save; the field order and wrapping remain clear. No visual layout blocker found.

The copy correction is verified in `/tmp/heap-repeating-integration/web-final-linked-undo-conflict.png`. The message says the next occurrence was `changed or linked to another task`, then clarifies that the completed task is unchanged and tells the user to refresh. It wraps across 2 readable lines without covering adjacent task rows or controls. This addresses the prior copy finding. Coordinator-reported integration verification exercised a real incoming dependency change; this screenshot review itself verifies only how the message reads and wraps.

Scope reviewed: `/tmp/heap-repeating-integration/web-editor-months.png`, `web-editor-days.png`, `web-invalid-interval.png`, `web-invalid-discard.png`, `web-editor-off.png`, `web-completed.png`, `web-undo-conflict.png`, `web-final-linked-undo-conflict.png`, `android-editor-months-scrolled.png`, `android-narrow-editor.png`, `android-narrow-keyboard.png`, and `android-narrow-editor-save.png`. Android narrow screenshots were supplied as an 840-pixel physical / 320-logical-pixel emulator capture at font scale 2.0. The keyboard is floating, so these images do not verify docked-keyboard insets. This review covers screenshots only; it is not physical-phone, live screen-reader, interaction, or backend verification.
