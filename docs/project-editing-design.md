# Project management UI

Status: design approved by Barrett; Flutter implementation and verification tracked in `../TASKS.md`. Companion: [phone-scale mockup](project-editing-mockup.svg). The mockup is a design reference, not a screenshot of the running app.

## Scope and evidence

Barrett owns the backend/API, including project color and icon; this proposal covers UI only.

Projects contains a simple list and a full-page add/edit form for exactly `Project name`, `Color`, and `Icon`. Existing projects also expose permanent deletion. No counts, descriptions, task lists, priorities, completion, sorting, search, filters, or reordering.

Inspected:
- `ui/lib/heap_style.dart`, `main.dart`, `task_widgets.dart`, `inbox_page.dart`, `task_lists_page.dart`, `task_editor_page.dart`, and `task_toolbar.dart`: warm canvas, mountain/Heap brand, unboxed rows, outlined white fields, Material 3 menus/dialogs, and 1 Save. Current task labels are **Inbox / Heap**, not the older On-deck wording.
- `docs/task-flow-design.md` in full: visual foundation and responsive rules; its older labels do not override current code.
- Original reference: `/home/barrett-lowe/Downloads/ChatGPT Image Oct 3, 2026, 01_07_06 PM.png`.
- Actual images: `/tmp/heap-revised-inbox-android.png`, `heap-revised-editor-android-awaiting.png`, `heap-revised-dirty-cancel-android.png`, `heap-revised-editor-web-qualifying.png`, and `heap-revised-priority-menu-android-320-2x.png` (all under `/tmp`). These show the visual vocabulary, not project functionality; some labels predate current code.
- `src/heap/logic/project.py`, `project_operator.py`, and `persistence/sqlite_project_store.py`: icon/color are optional stored strings; deletion removes every assigned task. Barrett specifies MDI icon names. Storage alone does not establish picker choices, supported glyphs, color formats, or editable transport support. This proposal does not design those interfaces.

## Projects list

Keep the current mountain + `Heap` header and refresh position; refresh tooltip becomes `Refresh projects`. Below it, show the bold `Projects` heading, then a left-aligned green pill button with a small plus and full label `Add project`. Put the action on its own line on phones so it cannot collide with the heading or look like the central capture plus. Leave 16–20 logical pixels before rows; omit an unnecessary subtitle.

Rows contain only a color swatch, an icon, and the project name, in that order. Use a 12-pixel swatch, a 24-pixel dark-green icon, 12-pixel gaps, and an 18-pixel/700-weight name. Use existing row padding (12 horizontal, 16 vertical), thin dividers inset to the name, and no enclosing cards, trailing actions, or chevron. Names wrap and rows grow. Each entire row is 1 target that opens `Edit project`; swatch/icon are not buttons. Pale `heapHighlight` appears only on actual hover/focus/press or confirmed return, never on a default first row.

The proposed working `Projects` toolbar destination replaces only its own `Soon` placeholder and gets the existing selected pale capsule. `Tasks` returns to its remembered Inbox/Heap list. `Today` and `Settings` remain visibly unavailable with `Soon`. The central plus still says `Capture` and opens **Capture task**, never a project form; the existing task-capture flow returns to Inbox. Do not add a task selector or task filters to Projects. No dummy destinations.

Empty state: `No projects yet.` followed by `Use Add project to create one.` Keep the same Add button; do not introduce a second plus.

## Add and edit

Use the current full-page task-editor vocabulary: back arrow (`Cancel editing`), bold `Add project` or `Edit project`, scrollable form, warm background, and exactly 1 filled green `Save`. The list toolbar is absent inside either editor.

Stack these controls with 16-pixel gaps:
1. `Project name`: white outlined text field. Proposed single initial line that grows/wraps for long names; no invented character limit. Blank/whitespace-only names show `Enter a project name.` after interaction or attempted Save. Focus name/keyboard on deliberate Add; focus heading without keyboard on Edit.
2. `Color`: an always-visible grid of selectable circles, without a dropdown or color names.
3. `Icon`: matching picker field, showing glyph + readable selected label and dropdown arrow.

Changes affect the local draft only. Save submits the 3 fields together as 1 user action; selecting a picker never writes. Do not expose or alter unrelated project metadata. A valid unchanged edit may Save, matching the task editor. Return to Projects only after confirmed success, update/reveal the saved row, and announce `Project added.` or `Project saved.` without covering that row.

Edit only: below the fields, leave 32 pixels, then a clearly labeled red text button with trash icon: `Delete project`. Keep it separate from the green Save footer. Add has no deletion action. Do not hide deletion in overflow or provide swipe/long-press deletion.

## Pickers: approved expansion

Barrett selected common icons plus **Browse all**, then requested 20 unnamed, chromatically ordered color circles shown inline without a dropdown. These choices supersede the original small-dropdown details in the mockup. Selection changes only the draft; the main Save remains the sole write. Closing the icon browser preserves all fields and restores Icon focus. Touch targets remain at least 48 pixels.

### Color

Show Color above an always-visible wrapping grid of 20 selectable circles, with None as a separate clearing option. Order hues chromatically, with a relatively even spread across the spectrum; the implemented fixed palette uses 18-degree HSL steps at 60% saturation and 45% lightness. Do not display human color names or hex labels, a dropdown arrow, or an extra popup. Selection uses a small contrasting checkmark badge that leaves the chosen hue visible. Keyboard focus uses an outline outside the colored circle against the canvas; None also exposes its selected state. Screen-reader labels identify the hex value and selected state without assigning names. Keep circles distinct and targets at least 48 pixels. Pointer selection should not interrupt name typing. No custom RGB/hex controls.

### Icon

Keep None, Folder (`folder-outline`), Home (`home-outline`), Leaf (`leaf`), Tools (`wrench-outline`), and Work (`briefcase-outline`) as quick choices. Add a divider and Browse all… last. Bundle the complete MDI 7.4.47 font, 7,447-name mapping, and license locally; no runtime downloads.

Browse all opens Choose icon: full-screen on Android/narrow web, a centered viewport-constrained 640-pixel dialog on wide web. Search icons by name filters locally, case-insensitively, treating spaces/hyphens alike and matching all query words. Clear restores the alphabetical catalog; no matches shows No icons found. Use a lazy grid of actual glyphs and wrapping friendly names. At 320 width / 2.0 text, use 1 column with growing tiles. Selected icons show tint, checkmark, and selected semantics; keyboard focus has an outline. Support Tab/arrows and Enter/Space. Cancel/Back/Escape closes without changing the draft. Restore focus to Icon.

Add defaults remain blank name, Color None, Icon None. Neutral swatch/folder placeholders do not become saved choices. On Edit, preserve any saved value outside the quick choices. Known non-common MDI names show their actual glyph and friendly label. Unknown icon names keep Saved icon: <original> and a folder fallback. Saved colors outside the palette still display their swatch when valid; malformed strings use a neutral fallback. Unrelated edits never replace these values; None deliberately clears them.

## Permanent deletion

`Delete project` opens an ordinary Material 3 alert dialog over the editor with a dimmed background, rounded pale surface, and this exact copy:

> **Delete project?**
>
> This permanently deletes "<saved project name>" and ALL tasks assigned to it, including completed tasks.
>
> This cannot be undone.

Actions: `Cancel` (safe initial focus/default, green text with a visible focus outline) and `Delete project` (red filled destructive action). At narrow width/enlarged text, stack actions without shortening labels. Back/Escape/outside dismissal cancels. Enter on initial focus cancels; it must never implicitly confirm deletion. Keep focus inside the dialog. Cancel restores the editor draft and focus to Delete project.

Use the last loaded saved name, not an unsaved rename; the dialog identifies the stored project being deleted. Confirm does not save the draft first. During deletion show `Deleting…`, prevent repeated confirmation and departure, and disable both dialog actions while awaiting the result. Confirmed deletion returns to Projects and announces `Project and all assigned tasks deleted.` Task views must not continue presenting removed tasks as current. Offer no Undo, archive, reassignment, or task-count claim.

## Minimal states and drafts

- Initial list: spinner + `Loading projects…`; initial failure: `Could not load projects.` + `Retry`. Refresh keeps rows visible; failure adds `Showing previously loaded projects. This list may be out of date.` + `Retry`.
- Edit loads current saved fields before enabling them: `Loading project…`; load failure: `Could not load this project.` + `Retry`. Missing project: `This project is no longer available.` with Back, no Save/Delete; retain any draft read-only.
- Save: `Saving…` + spinner; disable inputs, duplicate Save/Delete, and route departure while pending. Validation/error stays beside the relevant field or in the current inline status-panel style; preserve all draft fields. Deletion rejection keeps the editor draft and shows `Could not delete this project.`; another attempt requires opening confirmation again.
- Dirty Back uses existing copy `Discard changes?` / `Your edits have not been saved.` with `Keep editing` as default and `Discard changes`. Back/Escape/outside dismissal keeps editing. Include color/icon changes in the dirty check. No silent Save.
- Drafts last only while the editor remains open, including picker/dialog cancellation and request failure; do not promise survival across app restart/browser reload. Unknown request result: `The request may have succeeded. Your draft has been kept. Check projects before trying again.` Offer an explicit check/reload, not automatic resubmission. Never infer that a create succeeded from a matching name. Do not claim deletion succeeded merely because a project is now unavailable.

## Responsive and accessibility notes

Reuse `heapCanvas` #FCFCF8, `heapInk` #102E24, `heapTitle` #171C19, `heapMuted` #646D67, `heapGreen` #285A46, `heapHighlight` #EFF3E7, and `heapDivider` #DFE4DE. Brand is 32/800; page heading 30/800. Error/destructive colors and dialog surface follow readable Material roles; the SVG's red/pale values are illustrations, not new tokens.

Use existing 16-pixel phone / 24-pixel wide insets, centered list/toolbar cap 840 and editor cap 640. Keep the full-page flow on web, not a split pane. Save is full-width at the phone footer, right-aligned on wide web. As in the task editor, move Save to the end of scroll content when usable height is below 400 or text scale is at least 1.5. Apply keyboard inset once; keep fields and actions reachable.

Targets are at least 48. At 320 width / 2.0 text, names, field values, warning copy, menus, and dialog actions wrap/grow; never shrink or truncate scaled labels. Reuse the toolbar's existing 2-row fallback with Projects now available. Visible keyboard focus uses outline plus tint. Row semantics: `<name>. Edit project.`; decorative swatch/icon need no separate announcements. Picker semantics announce value and selection; color is never the sole cue. Return focus to the saved row (or Add after creation if the row is unavailable); after deletion use Projects heading. Announce loading/write errors once, with persistent readable copy.

## Handoff checks

After implementation, inspect phone/emulator, physical phone, and wide web: list has only the requested row fields; Add is distinct from Capture task; Add/Edit share exactly the same 3 fields and 1 Save; menu cancellation preserves draft; absent/unrecognized values survive unrelated edits; only existing projects can delete; confirmation names the saved project, warns about ALL tasks, defaults to Cancel, and has no Undo. Verify pending/failure/dirty states plus 320/2.0 wrapping, keyboard/focus, and unobscured saved rows. These checks are future work, not completed verification.
