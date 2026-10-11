# 3 Heap theme directions

Sol 6.1 design brief for Luna's standalone local HTML. This supersedes the earlier A/B palette proposals. **Barrett selected Paper desk.** The HTML remains a preview, not the app; Blueprint and Graphite are comparison history, not implementation targets. Flutter handoff is appended below.

## Directions

### 1. Paper desk

Warm editorial stationery: cream canvas, ivory fields, serif screen headings, cobalt actions, softly rounded controls. The hand-drawn pile feels at home on the page. Use generous vertical space rather than adding decorative paper texture.

Tradeoff: more relaxed and less compact; serif headings depart from the current all-sans UI.

### 2. Blueprint

Cool, structured utility: pale blue-gray canvas, white fields, deep cyan-blue actions, compact spacing, small-radius rectangles, monospace control labels. Clearly separated sections and precise alignment contrast with the loose paper mark. No grids, diagrams, code, or invented technical metadata.

Tradeoff: orderly but less cozy; monospace labels occupy more width and must wrap rather than shrink.

### 3. Graphite

Expressive monochrome: near-white canvas, black primary actions, bold sans headings, flat squared controls, strong rules. Electric blue appears only in focus and text actions, echoing the note without making the whole UI blue. The colored logo and semantic priority pills provide the limited color.

Tradeoff: strongest contrast and visual weight; less gentle than the other directions. This is a light theme, not a dark theme.

## Color tokens

All values are opaque hex colors. These choices derive from paper, graphite, and the blue note; the default brand contains no forest green. Use these tokens directly for the preview, not an automatically generated palette.

| Role | Paper desk | Blueprint | Graphite |
|---|---|---|---|
| `primary`: filled actions, selected list/filter, completion check | `#1B5EC4` | `#0B5670` | `#242424` |
| `onPrimary` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |
| `canvas`: screen and toolbar | `#FAF7F0` | `#F0F5FA` | `#F7F7F7` |
| `surface`: fields, menus, capture sheet | `#FFFCF5` | `#FFFFFF` | `#FFFFFF` |
| `text`: wordmark, heading, body, unselected navigation | `#282723` | `#172B3A` | `#202020` |
| `muted`: secondary copy and Soon destinations | `#666158` | `#506171` | `#606060` |
| `selection`: selected navigation, hover | `#E4EDFC` | `#D7E9F5` | `#E5E5E5` |
| `border`: identifying control outlines | `#82766A` | `#718396` | `#777777` |
| `divider`: decorative separators only | `#D8D1C5` | `#CDD7E1` | `#D6D6D6` |
| `focus`, `link`: visible focus outline, outlined/text action label | `#1B5EC4` | `#0B5670` | `#174DF0` |
| `error`: error text / destructive action | `#B42318` | `#B42318` | `#B42318` |
| `onError` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |
| `errorSurface` | `#FEECE8` | `#FEECE8` | `#FEECE8` |
| `completionNeutral`: retained completed pill fill | `#EBE7DF` | `#E6EBEF` | `#EBEBEB` |
| `completionText`: retained completed primary copy | `#49463F` | `#44515C` | `#494949` |

Completed secondary copy uses `muted`. Never use the old hardcoded green-gray completion colors. Use `border`, not `divider`, where a boundary identifies an input/control. Focus: 2px `focus` outline with a 2px canvas-colored gap; pale selection fill alone is not a focus indicator.

## Typography, shapes, density

Offline fonts only; no CDN, font downloads, or icon-font dependency. A later Flutter implementation would need its own font decision; this HTML does not promise exact platform font matching.

| Role | Paper desk | Blueprint | Graphite |
|---|---|---|---|
| Body font stack | `system-ui, sans-serif` | `system-ui, sans-serif` | `Arial, Helvetica, sans-serif` |
| Screen/sheet heading family | `Georgia, 'Times New Roman', serif` | Body stack | Body stack |
| Heading weight | 700 | 700 | 800 |
| Control/field label family | Body stack | `ui-monospace, 'DejaVu Sans Mono', 'Courier New', monospace` | Body stack |
| Control/field label weight | 600 | 600 | 700 |
| Body / muted weight | 400 / 400 | 400 / 400 | 400 / 400 |
| Screen/sheet heading size | 30 / 24px | 30 / 24px | 30 / 24px |
| Main / secondary copy | 16 / 15px | 16 / 15px | 16 / 15px |
| Field / control labels | 14px | 14px | 14px |
| Body line height | 1.55 | 1.45 | 1.45 |
| Button / selector / filter radius | 24px | 6px | 2px |
| Field radius | 12px | 4px | 2px |
| Capture sheet top radius | 24px | 12px | 8px |
| Priority pill / choice-chip radius | 14px | 6px | 2px |
| Selected nav indicator radius | 24px | 6px | 2px |
| Capture + control shape | 64px circle | 64px rounded square, 12px radius | 64px rounded square, 4px radius |
| Control outline / decorative rule | 1 / 1px | 1 / 1px | 2 / 2px |
| Content / sheet inset | 20 / 20px | 16 / 16px | 20 / 20px |
| Between major sections / fields | 24 / 16px | 16 / 12px | 24 / 16px |

Header invariant: unchanged `../header-mark.png`, untinted, transparent, centered contain fit in **40×32px**; **12px** gap; **Heap** wordmark **32px / 800**, body sans stack in all 3. Keep the logo's natural colors, texture, and proportions. No new logo drawing. Screen headings, shapes, density, and primary treatment carry the differences.

All actionable controls retain **48px minimum touch targets**; chips may have smaller visible faces inside those targets. Priority display pills can remain 28px tall when not interactive. Preserve readable toolbar labels and current wrapping; do not compress the preview to force everything onto 1 row. Shadows: none on the main screen; at most a subtle shared sheet shadow. Graphite uses `text` for a strong section rule, but `border` still outlines ordinary fields.

## Same content in each preview

Luna: show exactly 3 responsive theme cards, side by side when space permits, stacked on narrow screens. Each card starts with its name, 1-sentence vision, and tradeoff **outside** the app specimen. Give each a matched phone-width specimen (roughly 360–390px), not a fake device status bar. Use the same content/state across all 3. Permit synchronized **preview-only** view buttons named `Inbox`, `Heap`, `Capture`, and `Controls`; label these as artifact controls outside the specimens. Default to Inbox. Include all views in the local artifact; a small swatch row alone is insufficient.

### Inbox — real loaded empty screen

Header: pile + **Heap**, refresh icon (accessible label **Refresh inbox**; **Refresh the heap** in Heap view). Body, in order:

1. **Inbox**
2. **Capture now. Organize later.**
3. 48px Inbox/Heap segmented control, **Inbox selected**.
4. **Your inbox is empty.**
5. **Tap + to capture a task.**
6. Bottom toolbar: **Tasks** selected; **Today** with **Soon**; central + and **Capture**; **Projects**; **Settings** with **Soon**. Today/Settings stay unavailable.

Keep empty copy left-aligned and modest, as in the actual screen. Do not add an illustration, task count, suggested task, motivational copy, or oversized empty-state card. In narrow previews the toolbar can use the current 2-row order: Tasks/Capture/Today, then Projects/Settings.

### Heap — real loaded empty screen

Same header and toolbar. Body, in order:

1. **Heap**
2. **On the heap, not necessarily unblocked or started.**
3. **Ordered by priority, due date, and time on the Heap.**
4. Same selector, **Heap selected**.
5. Unselected **Time** and **Priority** filter controls.
6. **Nothing on the heap yet.**
7. **Give an inbox task a priority and duration, then save.**
8. Outlined **Go to inbox** button.

Do not place a selected P3 filter on this unfiltered empty screen; selected filter states belong in Controls.

### Capture — actual sheet, not an invented full editor

Show a sheet over the Inbox specimen with subdued backdrop. Exact content:

- **Capture task**, close icon with accessible label **Close capture**.
- Empty outlined field **Task title**, placeholder **What needs doing?**
- **Unsaved capture text stays here until you add it or clear it.**
- Filled + **Add task** button.

No priority, duration, project, or due-date fields inside Capture: those belong to the editor. Blank title remains blank; do not seed a fictional task. For the artifact, Add task is a disabled visual specimen with a nearby **Preview only — no task is created** note outside the sheet. Show the button's normal filled appearance in Controls if disabled styling obscures it. Closing the sheet only changes preview view.

### Controls — matched isolated specimens, not a saved task

Use small outside-specimen captions (`Selected filter`, `Editor fields`, `Focus`, `Completion`, `Error`) so these are not mistaken for task data. Show:

- Selected **Priority: P3** filter with flag/dropdown; unselected **Time**. Do not make both filters simultaneously active; the current filter model is exclusive.
- The 6 priority display pills listed below, all with full existing labels. Separately show the editor **Priority** choice group with **Unset** selected.
- **Duration** choice group with **Unknown** selected, followed by **5 min**, **15 min**, **30 min**, **1 hour**, **2 hours**, **4 hours**.
- Editor field specimens: blank **Task title**; **Project** displaying **No project**; blank **Due date** showing **None**. No invented project or date. These are separate specimens, not a claim that an empty saved task exists.
- A second blank Task title field with visible focus treatment; a focusable preview field can show the actual CSS focus style, with input read-only to avoid implying saved draft behavior.
- Completion circle: unchecked and white check on `primary`, each inside a 48px slot; adjacent neutral priority pill, **P3 Normal**, styled with completion tokens. No fake completed task row.
- Blank editor title error specimen: **Enter a task title.** in `error`, error outline. This is existing validation copy, displayed only as a specimen; do not trigger validation on the app or imply a failed save.
- Normal filled **Add task** and outlined **Go to inbox** specimens, clearly non-writing.

## Shared priority semantics

Use the same semantic colors across the directions, changing only pill geometry/type. Labels and meaning never change. These are priority colors, not theme branding. P4's old olive becomes plum in these proposals; P5/Unset become neutral gray. Stored user-selected project colors, including green, are unrelated and must not be rewritten.

| Exact label | Fill | Text | Label contrast |
|---|---|---|---:|
| P1 Critical | `#FFC4B8` | `#7F2418` | 6.38:1 |
| P2 Important | `#FFD790` | `#644000` | 6.76:1 |
| P3 Normal | `#CAE0FA` | `#244E7A` | 6.36:1 |
| P4 Someday | `#EEE5F3` | `#624270` | 6.77:1 |
| P5 Maybe | `#F1F1F1` | `#414141` | 9.04:1 |
| Unset | `#F1F1F1` | `#414141` | 9.04:1 |

Editor choice chips remain ordinary theme controls with an explicit selected check/border; do not use semantic pill fills as the only selection signal. Never relabel priorities or alter ranking, organization, filtering, capture, or completion behavior.

## Verified color contrast

WCAG sRGB relative luminance; opaque token pairs, rounded to 2 decimals. Minimum across listed backgrounds is reported where noted. Text is at least **4.5:1**; identifying outlines are at least **3:1**. Larger text is not used to excuse a failing color pair.

| Pair | Paper desk | Blueprint | Graphite |
|---|---:|---:|---:|
| White / primary | 6.10 | 8.14 | 15.52 |
| Text / canvas | 13.97 | 13.27 | 15.21 |
| Muted / canvas | 5.75 | 5.82 | 5.87 |
| Text / surface | 14.59 | 14.55 | 16.29 |
| Muted / surface | 6.00 | 6.38 | 6.29 |
| Text / selection | 12.68 | 11.69 | 12.93 |
| Muted / selection | 5.22 | 5.13 | 4.99 |
| Border / canvas, surface, selection (minimum) | 3.75 | 3.13 | 3.55 |
| Focus/link / canvas, surface, selection (minimum) | 5.17 | 6.54 | 4.97 |
| Completion text / neutral fill | 7.63 | 6.79 | 7.55 |
| Muted / neutral fill | 4.99 | 5.32 | 5.27 |

Shared error/errorSurface: **5.75:1**; white/error: **6.57:1**. Do not use raw logo-note blue for white-label buttons. Do not reduce opacity on copy and assume these checks still hold. Selected filled filters use `onPrimary`; selected navigation uses `text` on `selection`, with an explicit selected outline/indicator rather than pale fill alone.

## HTML boundaries and review

Use local assets and inline/local CSS/JS only. View switching is the only interaction needed. App-like navigation, refresh, filters, editor choices, and submit specimens must not fake a server request, persist a choice, or announce invented success. Preview toolbar actions may switch to the matching Inbox/Heap/Capture specimen only when explained by the outside artifact instructions; Projects/Today/Settings must not invent pages.

Check the HTML at wide 3-column and narrow stacked widths, 200% zoom, keyboard focus, and with network unavailable. Keep all copy readable, full priority labels visible, sheets scrollable, and 48px controls intact. This is a browser design review, not physical-phone/emulator verification or approval to implement a Flutter theme.

Source labels/anatomy: `ui/lib/inbox_page.dart`, `task_toolbar.dart`, `capture_sheet.dart`, `heap_filter_pills.dart`, `task_editor_page.dart`, `inbox_task.dart`. Behavior boundaries: `personal_task_project_manager_v1_spec.md` and project `AGENTS.md`. Only this design brief is owned by Sol; Luna owns the HTML separately. Parent owns shared docs and TASKS.

## Selected Paper desk — Flutter handoff

Implement only Paper desk's column in the color and typography/shape tables above. Visual-only change: keep all existing behavior, labels, navigation, responsive wrapping, focus order, data, and saved project colors. The in-app pile is already correct: leave its asset, untinted 40×32 frame, and 12px gap unchanged. No launcher/art changes.

### Offline typography

Bundle the confirmed local **`/usr/share/fonts/truetype/noto/NotoSerif-Bold.ttf`** as a Flutter font family **HeapSerif**, weight **700**. It is freely redistributable under **SIL Open Font License 1.1**; include the Google copyright notice and full OFL text from `/usr/share/doc/fonts-noto-core/copyright`, and expose that font license through the existing license registry. Do not download Georgia or use a runtime font package/CDN. Noto Serif is a sturdy editorial substitute, not an exact Georgia match; use the same bundled file on Android and web.

Keep the existing Flutter/Material default **sans** family for body, controls, field labels, navigation, metadata, project/task row titles, priority pills, and status copy. **Heap wordmark stays sans, 32/w800.** Body is 16/w400, secondary copy 15/w400, control/field labels 14/w600, body line height about 1.55; retain established smaller navigation/metadata sizes and task-title 18/w700 rather than enlarging every Text widget.

Apply explicit HeapSerif/w700 heading styles only to:

- **30px screen headings:** Inbox and Heap (`inbox_page.dart`), Projects (`project_widgets.dart`).
- **24px sheet/editor headings:** Capture task (`capture_sheet.dart`), Edit task (`task_editor_page.dart`), Add/Edit project (`project_editor_page.dart`), Choose icon (`project_icon_browser.dart`). The editor AppBar title needs its explicit style; default theme styling alone will not override current hardcoded weights.
- **24px dialog titles:** Time range and existing confirmation/delete/dialog titles. Leave dialog bodies and button labels sans. Configuration-page Heap brand title stays sans.

Do not change all Material `title*` styles to serif: those also style field groups, task summaries, and body content. Use a named heading style at these actual heading locations.

### Color and control coverage

Paper desk is the source of truth: primary/focus/link **#1B5EC4**, on-primary **white**, canvas **#FAF7F0**, surface **#FFFCF5**, text **#282723**, muted **#666158**, selection **#E4EDFC**, control border **#82766A**, decorative divider **#D8D1C5**. Remove default green cast from seeded Material roles as well as explicit shared tokens; fields, menus, dialogs, date picker, sliders, selected controls, app bars, toolbar, hover/focus, and completion must use the agreed blue/cream/charcoal treatment. Check surface tint/state overlays so they do not introduce a new palette.

- Completed rows/pills: fill **#EBE7DF**, primary text **#49463F**, secondary text **#666158**; check uses primary + white. Replace all hardcoded completed green-gray variants, including completed dependency badges. Non-completed dependency badge may retain its existing slate **#EDF0F4 / #475465** semantic pair.
- Normal P1–P5/Unset fills and text use the shared priority table. Preserve full **P1 Critical … P5 Maybe** labels, including editor choices; wrap instead of abbreviating. Priority dots: keep P1 **#C45843**, P2 **#BC830E**, P3 **#468BBB**; P4 becomes plum **#8B6A9C**; P5/Unset become neutral **#7C776D**. No remaining default olive P4 or green-tinted neutral pills.
- Error/destructive: **#B42318**, white on filled error, error surface **#FEECE8**. Warning/consequence remains semantic amber, not brand blue: retain existing readable amber where already explicit; otherwise use **#FFF1D6** fill with **#644000** text. Ordinary status/body copy remains charcoal. Do not change which messages are errors versus warnings.
- Apply cream/blue defaults to project controls and selection, but **never recolor saved user project colors**, even green. No project-data write or backend change.

Geometry: buttons/selectors/filters and selected navigation **24px radius**; fields **12px**; sheet tops **24px**; priority pills/choice chips **14px**; capture **64px circle**. Identifying outlines and decorative rules **1px**, focus **2px primary** with a **2px canvas gap** where feasible. Content/sheet inset **20px**, major section gap **24px**, field gap **16px**; preserve existing wide-screen caps, safe areas, toolbar layout, scrolling, and large-text adaptations. Keep **48px** actionable touch targets. No new card layout or paper textures.

Use the contrast checks above, then check actual focused/hovered/selected/disabled/error/pending/complete states; do not assume generated Material overlays preserve them. Parent owns tests, builds, emulator and web verification. Physical-phone visual verification may remain pending while the phone is disconnected. This handoff itself changes no production files.
