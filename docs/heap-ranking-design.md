# Heap due-date and ranking design handoff

Status: design handoff for the proposed ranking slice. This document specifies presentation and interaction only; it does not authorize implementation. The ranking/API behavior in `heap-ranking-plan.md` and `personal_task_project_manager_v1_spec.md` remains authoritative.

## Visual direction

Extend the existing warm, reference-led Material 3 interface: warm off-white canvas, dark-green Heap identity, unboxed wrapping task rows, quiet muted metadata, thin inset dividers, and the current outlined editor fields. Preserve current priority colors and full code + label pills. Due dates are metadata, not a new priority color, urgency badge, or saved-priority change.

## Task editor: optional Due date

Place **Due date** immediately after **Duration** in the existing full-page editor. Use a read-only outlined Material field showing a localized, unambiguous calendar date, with a calendar affordance that opens Flutter's Material date picker. Keep the stored/displayed value date-only: do not convert through UTC or represent it as an instant. Date formatting may follow locale, but the selected calendar day must not shift with timezone.

Provide a separate, clearly labeled **Clear date** action when a draft date exists. It is a distinct touch/keyboard target of at least 48 logical pixels; selecting or clearing updates only the editor draft. Both actions participate in the same dirty check and the existing single atomic **Save**. Do not auto-save when the picker closes. An unset date remains valid.

Picker behavior:

- Opening the picker does not modify the draft. **Cancel**, Escape, system Back, or dismiss leaves its prior value unchanged and returns keyboard focus to the Due date field/control.
- Confirming a day updates the draft and returns focus to the field. Selecting the already-saved day is a no-op.
- Permit past dates. Do not impose a today-based minimum, arbitrary year window, or other UI restriction that rejects a valid saved date. Preserve and display every valid saved date, including supported date boundaries. If the platform picker cannot select a boundary that the data model supports, explain the limitation before implementation and choose a control that can represent the supported range; do not silently clamp or erase it.
- While Save is pending, disable the date field and Clear date along with other editor inputs. Picker cancellation or field focus must not bypass dirty-cancel, conflict, or uncertain-save safeguards.

Include Due date in every relevant read-only and comparison summary: saved task, saved-on-server conflict/reconciliation version, preserved unsaved draft, completed task, and missing-task draft. Show an explicit `Due date: None` for null and the actual date otherwise. On conflict, compare and retain the date just like other editable fields; explain that the later deliberate Save replaces it atomically. No choice or reload writes automatically.

## Heap rows

Show an actual non-null due date in the existing wrapping row metadata group, alongside duration and the awaiting badge when present. Omit the date metadata entirely when null. Use a small calendar icon and the actual date (for example, `Oct 5, 2026` according to locale); the date itself is sufficient, so no extra “Today” or “Tomorrow” copy is needed. Do not show elapsed-time or overdue labels. Let the metadata wrap or move to its own line; never truncate the date or squeeze the task title. At narrow layout, retain the existing full-width title followed by wrapping metadata.

Completed tasks remain in their existing position until authoritative reload. Retain their actual due date, rendered in the existing neutral/grey completed metadata treatment (including the calendar icon); do not erase or recolor it as an urgency signal. Do not reorder rows in Flutter.

The priority pill always displays the task's **saved** P1–P5 priority and label. Deadline promotion affects server ordering only; never mutate the saved priority, replace its label with a promoted level, or add a promotion badge. The actual due-date metadata provides the relevant context. Preserve the existing awaiting-external-dependencies badge and its neutral style independently.

## Truthful ranking copy

Replace any Heap subtitle that says **“Oldest on-deck first”** or otherwise promises age-only order. Suggested concise copy:

> Ordered by priority, due date, and time on the Heap.

This describes the ranking inputs without implying that due date overrides protected priority rules or that every older task comes first. Do not call the full list “recommendations,” imply it is a shortlist, or add invented ranking explanations. The Inbox retains its existing capture/organization copy.

## Responsive and accessible behavior

- All dimensions are logical pixels. At 320 logical width and 2× text, stack/wrap the date field and clear action cleanly; allow the editor to scroll and keep all labels/actions readable. Do not reduce text size, clip, or put clear in a tiny icon-only target.
- On wide web, retain the centered editor cap and existing single-column form flow; no split pane. Ensure picker dialog/calendar and keyboard navigation fit the viewport and expose readable focus.
- The date field announces `Due date` plus its selected date or `None`; the clearing control announces `Clear due date`. Calendar icon is decorative. Keep keyboard focus after picker dismissal, and allow keyboard operation of both date selection and clearing.
- Keep wrapping row metadata within the row's existing accessible semantics; announce the actual due date when present. Completed rows announce their retained actual date. Do not create separate focus stops for decorative metadata.

## Scope boundary

This handoff covers only due-date presentation, editor interaction, row metadata, and truthful ranking copy. It does not authorize code changes, alter ranking semantics, add notifications or date-derived labels, change task eligibility, or introduce extra navigation. Implementation and verification remain downstream work under the coordinator's plan.


## Actual visual review: ranking and due-date slice

**Status: represented screenshots approved; physical-device and accessibility verification remain open.** Reviewed the supplied web, Android-emulator, and narrow-layout captures. No visual blocker was found in the states shown.

Evidence reviewed:

- Standard web: `/tmp/heap-ranking-integration/web-ranked.png`, `web-completed.png`, `web-editor.png`, `web-picker.png`, and final `/tmp/heap-ranking-integration/web-final-editor.png`.
- Android emulator: `/tmp/heap-ranking-integration/android-ranked.png`, `android-completed.png`, `android-editor.png`, `android-picker.png`, `android-saved.png`, and final `/tmp/heap-ranking-integration/android-final-editor.png`.
- 320-logical-width / 2× text emulator: `/tmp/heap-ranking-integration/android-narrow-ranked.png`, `android-narrow-rows.png`, `android-narrow-row-full.png`, `android-narrow-row-scrolled.png`, `android-narrow-editor2.png`, and `android-narrow-picker.png`.

The standard and narrow row captures show actual due-date text including the year, wrapping without clipping once the list is scrolled. The narrow full-row and scrolled captures show title, saved P3 badge, duration, and `Tuesday, October 6, 2026` metadata reachable above the toolbar. In ranked views the due-soon P3 keeps its saved P3 badge; ranking does not replace it with a promoted priority. The completed row retains its date and uses neutral grey completed metadata and priority treatment. The final editor captures resolve the earlier year-clarity concern: Android at narrow size displays `10/06/2026`, and Firefox displays `10/07/2026`. The picker and clear control are visible in the reviewed editor captures. The ranking subtitle truthfully says `Ordered by priority, due date, and time on the Heap.`

The coordinator separately reports a functional emulator timezone/resume check: Pacific/Kiritimati local October 6 versus America/New_York October 5 produced the expected different ordering after resume, then the test timezone was restored. This is coordinator-reported functional verification, not something established by these screenshots.

Evidence limits: no physical phone was available; live keyboard behavior and screen-reader operation were not verified. Screenshots cannot establish actual touch hit rectangles, picker cancellation/focus behavior, or persistence/ranking correctness by themselves. These remain verification work rather than visual findings.
