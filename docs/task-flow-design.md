# Heap task flow: reference-led revision

**Status: final design approved by Barrett, including visible unavailable future tabs. Toolbar handoff is ready; implementation GO remains coordinator-owned. The previous layout and its visual approval are withdrawn.**

The supplied image is the primary visual target. Every unfinished task with priority and known duration belongs to the organized On-deck pool automatically. Barrett clarified that waiting means the existing manual `externally_blocked` boolean, not a separate visibility feature. Waiting does not change list membership or imply a ranking calculation. The editor saves title, priority, duration, and this flag together with 1 atomic Save.

Reference: `/home/barrett-lowe/Downloads/ChatGPT Image Oct 3, 2026, 01_07_06 PM.png`.
Related documents: [task-flow-plan.md](task-flow-plan.md), [api-contract.md](api-contract.md). The coordinator is updating them for the clarified automatic-status rule and existing waiting flag. The updated HTTP contract governs transport and legacy-data normalization; this document governs the final presentation.

## Why the previous result missed the reference

The mismatch came primarily from my design directions, not from Frontend failing to follow them:

| Reference evidence | Previous direction/result | Correction |
| --- | --- | --- |
| Large, heavy Heap wordmark beside a recognizable green mountain mark | Small, regular-weight Material app-bar title and stock landscape icon | Larger, bolder wordmark; closer 2-peak mark and proportions. |
| Strong black-green titles with softer supporting text | Modest task titles on uniform filled cards | Heavier task titles, quieter metadata, deliberate spacing. |
| Mostly unboxed rows separated by thin inset rules; a pale-green highlighted row | Every row was a separate, identically green rounded card | Unboxed rows with subtle dividers; pale-green interaction/returned-task highlight, not a default fill on every task. |
| Colored priority pills and solid dots | I explicitly requested neutral, uncolored priority text | A consistent meaningful palette, code + label, and noninteractive solid dot. |
| Clock icon and secondary metadata arranged beneath the title | A plain sentence/subtitle | Clock duration metadata and a distinct priority badge. Only actual data is shown. |
| A fixed bottom toolbar with a large central plus | I explicitly prohibited bottom navigation and used top tabs plus a large inline field | Reference's Tasks / Today / Capture / Projects / Settings composition, with real Inbox/On-deck inside Tasks and clearly unavailable future tabs. |
| Compact, intentional information hierarchy | Repeated generic “Open to organize” lines and form-like capture above every list | Specific missing-field hints when known; actual priority/duration; capture separated from list presentation. |

My earlier screenshot reviews checked usability and agreement with my own document, but did not adequately check visual fidelity to the supplied image. Those reviews are not approval of the corrected design. The previous screenshots demonstrate the mismatch above; they do not verify this revision.

## Preserve scope and truth

Build 2 actual list destinations, 1 reusable task editor, and the existing title-only capture flow presented from the central plus. This changes presentation and the user-corrected organization rule, not the list of domain features.

- Keep Inbox and On-deck as their real destination names. Do not rename On-deck to Today or “Top of the heap,” which would imply a different view or ranking.
- Keep server ordering. On-deck is organized, not necessarily unblocked or started. Colors communicate priority, never task eligibility, readiness, or ranking.
- No fabricated description, project, location, aging reason, seasonal hint, duration range, completion control, filter, or ranking explanation.
- Barrett approved displaying Today, Projects, and Settings as clearly unavailable placeholders. Show their reference-like icons and labels with `Soon`, but no navigation, API calls, pages, or selection changes. Search, overflow, and filtering remain out of scope; the Inbox/On-deck selector is real list navigation, not a fake filter.
- Expose only the existing manual `externally_blocked` flag, labeled `Awaiting external dependencies`. It is not a dependency editor, reason field, automatic waiting detector, or list-membership control.
- Continue server-confirmed updates, explicit retry, draft preservation, and conflict protection. No offline cache, queued writes, or new state package.

## Final handoff boundaries

1. **Atomic Save:** Submit title, nullable priority, nullable duration, and `externally_blocked` together with the fresh comparison token. Frontend must not chain separately committed field/flag/status writes. The backend derives status; there is only 1 Save intention.
2. **Accurate bulk metadata:** Inbox, On-deck, and fresh detail expose actual priority, duration, and `externally_blocked`. This supports the row design without a detail GET per row. The coordinator's updated contract defines required fields and capture-response compatibility.
3. **Status expectation:** For unfinished tasks, both priority and known duration imply On-deck; otherwise Inbox. Waiting true or false does not alter this rule. Reconciliation compares all 4 editable fields plus this automatic status expectation.
4. **Legacy records:** Backend/coordinator owns normalization and on-deck timestamps. Do not add a UI destination or compute a client-side ranking to handle legacy state. Use validated server responses.
5. Coordinator owns shared plan/contract/project guidance and Frontend GO. Designer owns only this document. No design questions remain open from the clarified waiting behavior.

The final proposal is ready for implementation coordination. This handoff is not a claim that the revised UI has been built or visually verified.

## Visual foundation

All dimensions are logical pixels and defaults; text scaling and longer content can increase heights.

| Token/component | Revised direction |
| --- | --- |
| Canvas | Warm off-white `#FCFCF8`, close to the reference's nearly white surface. |
| Primary text / wordmark | Black-green `#102E24`; task titles `#171C19`. |
| Supporting text | Muted gray-green `#646D67`, still contrast checked against its surface. |
| Primary action | Deep green `#285A46`; white foreground. |
| Mountain | 2 simple overlapping peaks in `#52875B` and `#365F47`; approximately 40 wide × 32 high. Use a small vector/custom drawing, not a scenic illustration or new asset package. |
| Wordmark | `Heap`, approximately 32, weight 800, tight default tracking. Keep brand and mark aligned. At enlarged text allow the header to grow; never crop the word. |
| Page heading | 28–30, weight 800; supporting line 15, regular. |
| Row title | 18, weight 700; on wide web 19 is acceptable. No arbitrary title length or line cap. |
| Row metadata | 14; clock icon 18; muted text, not washed-out gray. |
| Priority pill | Pastel rounded capsule, 12–13 semibold dark text, code + label. Minimum 28 visual height, 10 horizontal padding. It is not interactive. |
| Dividers | 1-pixel visual rule using `#DFE4DE`, inset to row text alignment; no card shadows. |
| Highlight | Very pale green `#EFF3E7`, 20 radius; limited to pointer hover, keyboard focus, press, or the just-saved task being revealed. Never implies “recommended.” |
| Page inset | 16 on narrow screens; 24 at 600 and above. Rows may extend 8 outside heading inset to give the pale highlight the reference's broad shape. |
| Content cap | List/header/toolbar content maximum 840, centered on web. Editor maximum 640. |
| Touch targets | At least 48 for every interactive target. Metadata/dots/pills are decorative, not tiny buttons. |

Use explicit colors only for this visual vocabulary; derive error/disabled/focus behavior from readable Material roles. Do not depend on a seed theme to coincidentally reproduce the reference. Use the existing font at the specified weights first; adding a font dependency is not necessary to achieve the hierarchy.

### Priority palette: P1 remains highest

The reference's P5-red example must not reverse the actual priority labels. Use its pastel visual language with urgency decreasing from P1 to P5:

| Value | Full badge label | Pill fill | Text | Solid dot |
| --- | --- | --- | --- | --- |
| 1 | `P1 Critical` | `#FFC4B8` coral | `#7F2418` | `#C45843` |
| 2 | `P2 Important` | `#FFD790` amber | `#644000` | `#BC830E` |
| 3 | `P3 Normal` | `#CAE0FA` blue | `#244E7A` | `#468BBB` |
| 4 | `P4 Someday` | `#DCE7C8` sage | `#40551F` | `#779252` |
| 5 | `P5 Maybe` | `#E3E5E4` gray | `#414B44` | `#87918A` |
| null, known | `Unset` | `#EBEEEA` neutral | `#4B554E` | `#A3AAA4` |

Always show the code and label; do not make the user memorize color. Calculated contrast for these proposed solid-color pairs is 6.36–7.17:1 for badge text, 5.20:1 for supporting text on canvas, and 7.95:1 for white primary-action text. Final rendered states still need inspection. P1 is coral/red, not P5. Use the same palette on rows, the editor's selected priority, and priority menu accents. Null is not P5.

Absent metadata is not null or false: never guess `Unset`, `Unknown`, or a cleared waiting flag. Follow the updated contract's missing/malformed-response handling. The finished bulk list must provide real priority, duration, and `externally_blocked`; no per-row detail calls are needed.

## List shell and bottom toolbar

### Header and list heading

Warm header, generous breathing room, no global top-navigation tabs. At normal size allow approximately 72 header height, with mountain + Heap on the left and an actual refresh action on the right. Refresh replaces the reference's unsupported search/overflow controls rather than inventing them. Tooltip is `Refresh inbox` or `Refresh on-deck`.

Below header: 20–24 vertical gap, destination heading, then subtitle:
- Inbox: `Inbox` / `Capture now. Organize later.`
- On-deck: `On-deck` / `Organized, not necessarily unblocked or started.`
- On-deck also has a quiet `Oldest on-deck first.` line. Do not say ranked.

After the heading/subtitle, show the real Inbox/On-deck inner selector, then leave 20 before the first row. Do not add filtering chips or fabricated descriptions. Heading, selector, state panels, and rows share 1 scroll area. Header and bottom toolbar remain outside it.

### Tasks container and real inner selector

Use the reference's 5 bottom groups rather than squeezing 6 separate controls into narrow screens. `Tasks` is the actual container for the 2 approved task lists. It stays selected for both Inbox and On-deck. Preserve the chosen list and its scroll position in memory.

Inside Tasks, directly beneath the current list heading/subtitle, use a Material single-selection `SegmentedButton` or equivalent pair of 48-minimum-height pills labeled `Inbox` and `On-deck`. Selected segment is deep green with white text; the other uses a readable warm/pale surface with a subtle outline. No counts, decorative checkmark, or fake filtering. Accessible group label: `Task lists`; selected segment exposes selected state. Selecting a segment switches the real list, with existing lazy load/retry semantics. A confirmed Save to another list updates this selector.

Tapping the selected bottom `Tasks` control keeps the active list and reveals its heading/selector by scrolling to the top; it does not make an API request or reset the list. This keeps both real destinations reachable even after scrolling far down. No new Tasks page is necessary.

### Toolbar: reference tabs with explicit availability

A warm fixed `BottomAppBar`/equivalent surface with a fine top rule and safe-area padding. At normal text allow approximately 88–96 height before the system bottom inset. Normal arrangement is 5 equal groups in reference order:

| Group | Presentation and behavior |
| --- | --- |
| Tasks | List icon in selected pale-green capsule; label `Tasks`. Working container control described above. |
| Today | Calendar icon; `Today` and small `Soon` caption. Unavailable placeholder. |
| Capture | Prominent central round deep-green plus, 64 diameter, white plus around 30, subtle elevation. Visible `Capture` label when space permits; tooltip/accessible label `Capture task`. Opens the real capture sheet. |
| Projects | Bar-chart reference-like icon; `Projects` and `Soon`. Unavailable placeholder. |
| Settings | Gear icon; `Settings` and `Soon`. Unavailable placeholder. |

The plus is an action, not a selected tab. Tasks and its current inner list remain selected while capture is open. Placeholder taps/keyboard activation must not navigate, call an API, change selection, or open a dummy page. Prefer genuinely disabled controls with semantics `enabled: false`, readable labels, and announcements such as `Today. Coming later. Unavailable.` They may be skipped in keyboard Tab traversal but remain discoverable to a screen reader. Do not apply a low-opacity style that makes their text unreadable: muted `#646D67` on warm canvas is acceptable. `Soon` makes the unavailable status visible, not merely an accessibility-only detail. No toast or additional confirmation is required.

At 320 with ordinary text, use 12-size labels and 5 equal groups; retain 48 interactive target width/height for Tasks and Capture. Never shrink scaled text. If 5 labels cannot fit at the actual text scale (typically 1.5 and above), use a taller 2-row toolbar: first row `Tasks | Capture | Today`, with capture still central; second row `Projects | Settings`, centered in 2 equal wider groups. Preserve labels and Soon captions. Reading/focus order follows that displayed order. This narrow/large-text exception is preferable to clipping or horizontally hiding destinations. No new pages are introduced.

Let the bar grow to its content. The plus may project up by at most 8 only into reserved space; it must not overlap rows. Reserve the actual toolbar height and any projection so the last task remains reachable. Wide web retains the normal 5-group order inside the centered content cap.

### Android Inbox sketch: 360 normal text

```text
┌──────────────────────────────────────┐
│  green mountain  Heap           ↻    │ larger, heavy brand
│                                      │
│  Inbox                               │ strong heading
│  Capture now. Organize later.         │ muted subtitle
│  [ Inbox selected ][ On-deck ]        │ working inner list selector
│                                      │
│  ● Fix driveway             [Unset]  │ title wraps; solid decorative dot
│    washout                           │
│    Needs priority and duration        │ truthful hint, not fake description
│    clock  Unknown                    │ only when known-null duration
│    ──────────────────────────────    │ thin inset divider
│  ● Order bee         [P2 Important]  │ actual full code + label pill
│    equipment                         │ title wraps rather than shrinking
│    Needs duration                    │
│    clock  Unknown                    │
│    [Awaiting external dependencies]  │ only if actual flag is true
│    ──────────────────────────────    │
│  ● Call supplier             [Unset] │
│    Needs priority                    │
│    clock  15 min                     │
│                                      │
├──────────────────────────────────────┤
│ [list] calendar  (+)  chart   gear   │ prominent central capture
│  Tasks   Today Capture Projects Settings│ full labels in app, no truncation
│          Soon          Soon    Soon │ unavailable future tabs
└──────────────────────────────────────┘
```

The sketch's examples are test data, not seeded rows. Do not copy its illustrative line breaks into fixed-height widgets.

### Android On-deck sketch

```text
┌──────────────────────────────────────┐
│  green mountain  Heap           ↻    │
│                                      │
│  On-deck                             │
│  Organized, not necessarily          │
│  unblocked or started.                │
│  Oldest on-deck first.                │
│  [ Inbox ][ On-deck selected ]        │ working inner list selector
│                                      │
│ ╭──────────────────────────────────╮ │ optional just-saved/focus highlight
│ │● Fix driveway       [P2 Important]│ │ same row geometry, pale green
│ │  washout                         │ │
│ │  clock 30 min                    │ │ no fabricated description
│ ╰──────────────────────────────────╯ │
│    ──────────────────────────────    │
│  ● Order bee           [P3 Normal]   │ regular row unboxed
│    equipment                         │
│    clock 15 min                      │
│    [Awaiting external dependencies]  │ still part of On-deck
│    ──────────────────────────────    │
│  ● Make mower          [P1 Critical] │ P1 color does not change order
│    axle spacers                      │
│    clock 60 min                      │
├──────────────────────────────────────┤
│ [list] calendar  (+)  chart   gear   │ Tasks selected for either list
│  Tasks   Today Capture Projects Settings│ full labels in app, no truncation
│          Soon          Soon    Soon │
└──────────────────────────────────────┘
```

### Exact row construction

Use a tappable Material/InkWell row, not the previous separate filled-card stack. Outer horizontal inset 8; approximately 12 internal horizontal and 16 vertical padding. Leading solid dot 12; 12 gap before main content. The whole row has 1 focus/tap target. Dots have no ring, checkbox, or completion action.

Normal width of at least 360 and text scale at most 1.2: main content has a top row with expanded title and a trailing priority pill, separated by 12. Let the title wrap. The pill can grow; its label is never truncated. Below: optional specific Inbox hint, then a wrapping metadata group with clock + actual duration and the awaiting badge when applicable, aligned with title text rather than the dot. There is no need for a trailing chevron once the row's hover/ripple/focus and accessible button semantics establish its action; removing it gives room to the reference-like badge.

Below 360 or above 1.2 text scale: title gets the full main-content width; place the full priority pill in a wrapping metadata group below it, alongside clock/duration when they fit. If they do not fit, they stack. This avoids forcing a large title into a tiny column. Dividers align with title text and end at the row's trailing inset.

Inbox hints only when metadata is known:
- Missing both: `Needs priority and duration`.
- Missing priority only: `Needs priority`.
- Missing duration only: `Needs duration`.
- Both present: no missing-field hint. Under the clarified rule, a current unfinished task with both values belongs to On-deck. Backend normalizes legacy state; the UI must not invent an explanation for an inconsistent snapshot.

On-deck has no invented secondary description; clock metadata occupies that line. Duration values: `Unknown`, `5 min`, `15 min`, `30 min`, `60 min`, `120 min`, `240 min`. Do not display made-up ranges.

### Awaiting row badge

When `externally_blocked == true`, show a noninteractive badge labeled `Awaiting external dependencies` beside clock metadata where it fits, or on its own next line. Use a small hourglass icon, neutral pale `#EDF0F4` fill, dark `#475465` text, approximately 12–13 text size, and rounded 8 corners. Badge text may wrap; it is never truncated. It appears in either list according to actual task status. When false, omit the badge; do not replace it with “Ready.”

Waiting does not recolor the priority pill/dot, fade the task title, change row order, or exclude a task from On-deck. It is a manual flag, not evidence of checked prerequisite state. Do not add a row checkbox, toggle, reason, or secondary tap target. Editing the flag belongs in the task editor.

No default highlight on the first row: that could look like a recommendation. Highlight only an actual press/hover/focus or the row just returned from a confirmed save. Use an outline as well as tint for keyboard focus. Announce row title, list status, actual priority/duration, `Awaiting external dependencies` when true, and `Open task editor`; merge decorative dot/clock/pills into that single accessible target.

### Wide web

Keep the same header/list/bottom-toolbar composition, centered with maximum 840 content width. Warm canvas extends outside it; toolbar surface may span the viewport but its 5 groups align inside the content cap. Tasks contains the same working Inbox/On-deck selector. No rail, global top tabs, or side-by-side editor.

```text
         centered maximum 840; generous warm margins
       ┌────────────────────────────────────────────┐
       │ mountain Heap                          ↻   │
       │                                            │
       │ On-deck                                    │
       │ Organized, not necessarily unblocked …     │
       │ Oldest on-deck first.                      │
       │ [ Inbox ][ On-deck selected ]               │
       │                                            │
       │ ● Fix driveway washout       [P2 Important]│
       │   clock 30 min                             │
       │   ───────────────────────────────────────  │
       │ ● Order bee equipment           [P3 Normal]│
       │   clock 15 min  [Awaiting external          │
       │                  dependencies]             │
       ├────────────────────────────────────────────┤
       │  Tasks    Today      (+)  Projects Settings│
       │           Soon    Capture    Soon     Soon │
       └────────────────────────────────────────────┘
```

Use a visible scrollbar for overflowing lists. Keep each destination's scroll position. Do not shrink the typography to make desktop rows artificially dense. At enlarged text apply the same wrapping row layout as Android.

## Central capture presentation

The central plus opens a Material modal bottom sheet labeled `Capture task`, using the existing capture operation and state rather than a second task-creation mechanism. On web cap sheet content at 560. This is a presentation of the existing operation, not a new domain operation.

- Show `Task title`, hint `What needs doing?`, plus one green `Add task` action. No priority/duration/waiting fields in quick capture; organization remains in the editor.
- Autofocus this new-task field on deliberately pressing plus. Keep draft in memory when the sheet is dismissed; reopening plus restores it. A short sheet helper can say `Unsaved capture text stays here until you add it or clear it.` Do not imply disk persistence.
- Include a working Close button with accessible label `Close capture`. Closing while idle preserves the draft and does not submit; it does not discard text. Do not introduce a second dirty-discard scheme for capture when nothing is being discarded.
- During pending capture block Close, sheet drag/barrier dismissal, duplicate Add, and navigation that would lose the in-flight draft. Preserve newer text according to existing capture rules; clear only the successfully submitted text.
- On confirmed capture select Inbox, reveal the confirmed new row, and announce `Task added to inbox.` Close the sheet only if the submitted text is still the current draft. If newer text was typed during POST, keep the sheet open with that newer draft; do not erase it or dismiss input underneath the user. No automatic editor jump or synthetic On-deck row.
- On rejection keep sheet and text. On uncertain capture keep the current refresh-before-resubmit and explicit duplicate warning semantics. Refresh means GET Inbox; matching a title never confirms this capture. No automatic resubmission.
- On deliberate close after an uncertain result, retain draft and the uncertainty flag. Show `A capture may have succeeded. Reopen capture to check before submitting again.` on the list so the warning is not hidden when the sheet closes.

Sheet uses viewport-constrained scroll content, safe areas, and exactly 1 keyboard inset. With a docked keyboard, title and Add remain visible or reachable by scrolling; Close remains available except during pending POST. This reuses existing capture behavior but relocates it out of the reference-led list layout.

```text
┌──────────────────────────────────────┐
│ list remains behind modal barrier    │ bottom toolbar cannot be activated
├──────────────────────────────────────┤
│ Capture task                   Close │ sheet header
│ [ Task title                       ] │ deliberately focused
│ [ What needs doing?|               ] │
│ [             Add task             ] │ above keyboard; scroll if necessary
├──────────────────────────────────────┤
│            docked keyboard           │ exactly 1 inset
└──────────────────────────────────────┘
```

## Reusable editor: 1 atomic Save

Keep the existing full-page editor shape rather than redesigning every form. No bottom list toolbar inside the editor; its bottom region is reserved for the single Save action. This prevents accidental destination changes with unsaved text.

App bar: back arrow + bold `Edit task`. Back tooltip `Cancel editing`. Load fresh known-ID detail before editing; do not populate from a stale row and overwrite later. Show `In inbox` or `On-deck` status, then:

1. `Task title`: white outlined multiline field, 2 initial lines up to 4 visible, internal scrolling after that. Enter inserts a newline. No length limit and no automatic keyboard on opening an existing task.
2. `Priority`: white outlined Material dropdown; `Unset`, `P1 Critical`, `P2 Important`, `P3 Normal`, `P4 Someday`, `P5 Maybe`. Add the priority-colored dot/pill treatment to selected value and menu accents, while retaining clear label and selection semantics.
3. `Duration`: white outlined Material dropdown; `Unknown`, `5 min`, `15 min`, `30 min`, `60 min`, `120 min`, `240 min`. Clock accent is decorative. Null choices are genuinely selectable.
4. `Awaiting external dependencies`: a labeled Material `CheckboxListTile` below the dropdowns, checked from the saved/draft `externally_blocked` boolean. Use a leading checkbox, no enclosing card, and the whole label row as a target of at least 48. Label and helper wrap at narrow width/large text. Helper: `Manual flag only. Organized tasks stay on-deck while waiting.` This is the only checkbox and clearly labels waiting, not completion.

Changing the checkbox changes only the draft until Save. It never immediately writes or changes destination. It participates in dirty-cancel checks, pending-save input disabling, rejection preservation, conflict comparison, and uncertain-save matching exactly like the other editable fields. Read-only terminal states show `Awaiting external dependencies: Yes` or `No` as text, not a disabled actionable checkbox.

Stack controls on narrow/large-text screens; priority/duration can share a row at width 600 and above with normal text. Menus scroll within the viewport; dismiss text keyboard before opening them.

### Save helper and consequences

There is exactly 1 filled green `Save`. It is available for any valid nonblank title, even with missing priority/duration, and for a valid unchanged task. Missing requirements do not disable saving.

- Missing both: `Choose a priority and duration for on-deck. You can save without them.`
- Missing priority only: `Choose a priority for on-deck. You can save without it.`
- Missing duration only: `Choose a duration for on-deck. You can save without it.`
- Qualifying Inbox draft: `Saving will put this task on-deck automatically.`
- Qualifying On-deck draft: `This task stays on-deck when saved.`
- Previously On-deck draft clearing either requirement: visible warning directly above Save, `Saving will return this task to the inbox.` Use a warning icon, explicit words, and a pale contrasting surface.
- Checking or clearing awaiting does not show a return-to-Inbox warning. The checkbox helper explains that organized tasks stay on-deck while waiting. If priority/duration were also cleared, the warning is about those missing requirements, not waiting.
- No copy claiming that qualifying unfinished tasks remain in Inbox after Save.

The business flow is incomplete → Inbox, qualifying → On-deck, clearing a requirement → Inbox, restoring requirements → On-deck automatically on Save, regardless of `externally_blocked`. Never update lists from a client-side guess; use returned server status. On-deck age and legacy normalization are backend-owned details.

```text
┌──────────────────────────────────────┐
│ ‹ Edit task                          │
│                                      │
│ In inbox                             │ saved status, not guessed draft state
│ [ Task title                       ] │
│ [ Fix driveway washout             ] │
│                                      │
│ [ Priority: ● P2 Important        ▾ ] │ palette consistent with list
│                                      │
│ [ Duration: clock 30 min          ▾ ] │
│                                      │
│ [✓] Awaiting external dependencies   │ manual draft checkbox, not completion
│ Manual flag only. Organized tasks    │
│ stay on-deck while waiting.           │
│                                      │
│ Saving will put this task on-deck     │
│ automatically.                       │
│                                      │
├──────────────────────────────────────┤
│ [               Save               ] │ only save intention
└──────────────────────────────────────┘
```

Ordinary footer: warm surface, subtle top divider, 16 padding, single full-width Save on Android; right-aligned Save on wide web inside 640 cap. For usable height below 400 after insets or text scale at least 1.5, place helper/warning/Save at the end of the form's scroll content. Never shrink fonts to fit. Use exactly 1 keyboard inset; focused field/error remains above the footer or can be scrolled into view.

```text
┌──────────────────────────────────────┐
│ ‹ Edit task                          │ ordinary keyboard-open layout
├──────────────────────────────────────┤
│ Task title                           │ scroll focused field into view
│ [ Fix driveway washout|            ] │
│             ↕ scroll form            │ dropdowns remain reachable
├──────────────────────────────────────┤
│ [               Save               ] │ 1 action above keyboard
├──────────────────────────────────────┤
│            docked keyboard           │
└──────────────────────────────────────┘
```

At 320 / 2.0 text the same form scrolls through title → priority → duration → awaiting checkbox/helper → consequence → Save; Save is inline at the end instead of consuming the shortened viewport. Large row titles occupy the full row content width, then clock and badge wrap below. This is an accessibility layout, not a reduced-font imitation of the reference.

On Save dismiss keyboard; disable inputs, Save, repeated submit, and route departure. Show `Saving…` + spinner; announce `Saving task`. No optimistic navigation. Android Back may dismiss keyboard/menu but cannot leave during a pending write.

## Confirmed returns, cancellation, and recovery

These safeguards remain required despite the visual/business change:

- A server-confirmed atomic Save updates/removes the known ID in both list states, invalidates older GETs, and returns to the server's actual Inbox/On-deck destination. Preserve same-list scroll; reveal the saved row on a destination change. Highlighting the returned row is an interaction cue, not ranking.
- Announce `Task saved.`, `Task saved to inbox.`, or `Task saved to on-deck.` Refresh both lists. A refresh failure remains a successful save: persistent `Saved, but lists could not be refreshed.` + `Refresh lists`, with stale data labeled.
- Dirty editor Back: `Discard changes?` / `Your edits have not been saved.`; safe default `Keep editing`, alternate `Discard changes`. Escape, Back, or outside dialog dismissal keeps editing. No action silently saves. Restore last field focus on Keep editing and source-row/heading focus on exit.
- Uncertain editor exit: `Leave without checking the save?` / `The task may already have been saved on the server. Discarding these local edits will not undo a possible save.`; `Keep editing` / `Leave and discard draft`. Invalidate lists on uncertain exit. No undo claim.
- Browser/system back uses the same guard wherever Flutter controls it. Hard reload/tab close cannot guarantee draft retention; do not claim durable drafts.

### List states

Show status content below the heading/inner selector, before rows. Preserve Tasks/Capture availability and clearly unavailable future tabs during list errors:

| State | Presentation |
| --- | --- |
| Initial load | Spinner + `Loading inbox…` / `Loading on-deck…`; no fake empty rows. |
| Empty Inbox | `Your inbox is empty.` / `Tap + to capture a task.` |
| Empty On-deck | `Nothing on-deck yet.` / `Give an inbox task a priority and duration, then save.` Working `Go to inbox`. |
| First load unavailable | Cloud-off icon; `Could not load the inbox.` / `Could not load on-deck.`; server/VPN explanation + `Retry`. |
| Refreshing | Retain previous rows/confirmed empty data; progress line + `Refreshing…`; block duplicate refresh only. |
| Refresh failed | `Showing previously loaded tasks. This list may be out of date.` + `Retry`. Even previous empty data is labeled stale. |
| Invalid server setup | Existing explicit configuration error, not an empty list or an ineffective Retry. |

Stale rows can open, but fresh detail GET is required before editing. Refresh never retries POST/PUT. Keep decorative priority color separate from error/availability colors.

### Editor errors and conflict

- Initial detail loading: `Loading task…`, Back available, no Save/fields yet. Unavailable: `Could not load this task. Your list may be out of date.` + `Retry`.
- Validation rejection: preserve draft, show `Task could not be saved. Check the highlighted fields.`, relevant field errors, and focus/scroll to first invalid field. Deliberate Save only after correction; no automatic retry.
- Missing: `This task is no longer available.`; no Save. Preserve any existing draft read-only with `Your draft is shown below, but this task cannot be saved.`
- Completed: `Completed` / `This task is completed and cannot be edited.` Show fetched values read-only; if there was a draft, retain it separately under `Your unsaved draft`. No Restore/Save/history/completion action.
- Conflict: `This task changed on the server. Your edits have been kept. Reload the saved task before deciding what to keep.` + `Reload saved task`. Hold draft read-only and Save disabled while deciding.
- After conflict GET, show `Saved on server` summary of title, priority, duration, `Awaiting external dependencies: Yes/No`, and status alongside the preserved draft's same 4 fields. `Use saved version` adopts all fetched editable values without writing. `Keep my edits` adopts fresh comparison token/status while retaining all 4 draft values, including the waiting checkbox; explain `Your edits are not saved. Saving will replace the server's title, priority, duration, and awaiting flag with your values.` A separate deliberate Save is required. A conflict only in the flag is still a real conflict.

### Uncertain atomic Save

Keep original saved snapshot, current/submitted draft, and fetched comparison separate. Timeout/lost response/malformed or wrong-ID success/`5xx` means possible success:

`The save may have succeeded. Your draft has been kept. Reload the saved task before trying again.`

Only recovery action initially: `Reload saved task`, GET of the same known ID. Ordinary Save remains disabled and draft read-only until an explicit choice. Never capture a duplicate task or automatically repeat PUT.

- Match the submitted trimmed title, nullable priority/duration, exact `externally_blocked` boolean, and automatic final status: On-deck when both required values are present, Inbox otherwise. Waiting never changes the expected status. Do not require matching operation timestamps or claim which request caused the fetched current state.
- If all 4 fields and expected status match, show `The saved task matches your changes. This confirms its current state.` Offer `Return to inbox` / `Return to on-deck` from fetched status.
- If any field or status differs, including a mismatch only in awaiting or a GET equal to the original, show `The saved task does not match your draft. The earlier save may still finish.` Show both versions including awaiting Yes/No and offer explicit `Use saved version` or `Keep my edits` with fresh token. Keeping edits retains all 4 draft values and requires a separate Save plus warning that it is a new request.
- Reload failure: `Could not check the saved task. The save may still have succeeded.` Preserve uncertainty/draft; another explicit Reload only.
- Missing/completed results use the read-only terminal states, retaining the draft and possible-save warning.

Adopting a differing saved version does not prove the prior PUT failed; retain possible-save/leave wording until resolution under the revised contract. No background write polling or disk draft cache.

## Accessibility and responsive checks

- All interactive targets at least 48; color pills/dots are not extra controls. Row is 1 button-like semantic target with actual metadata.
- At 320 width / 2.0 text, row title spans available width, metadata wraps, toolbar labels grow, and editor/capture actions remain reachable by scrolling.
- Preserve readable contrast; priority labels communicate meaning without color. Visible keyboard focus uses outline + tint, not tint alone. Selected bottom destination exposes selected semantics.
- Web traversal follows visual order: header refresh, real Inbox/On-deck inner selector, list rows/recovery actions, bottom Tasks/Capture. Unavailable Today/Projects/Settings are not active Tab stops but have readable unavailable screen-reader semantics. Editor order is Back, status/reconciliation choices, title/priority/duration, awaiting checkbox, Save. The checkbox exposes its checked state and toggles with Space. No global Enter-to-save handler. Standard menu arrow/Enter/Escape behavior.
- Capture sheet/dialog contains focus and returns it to the plus on idle Close. Editor opens focused on heading/status, not title. Refreshes do not steal focus during input.
- Announce new errors, warnings, load/save changes without repeated announcements on unrelated rebuilds. Consequences and field errors remain readable, not snackbar-only.

## Acceptance gate for this revision

Final proposal is ready; no waiting-behavior design question remains. Coordinator issues Frontend GO after its shared contract/plan updates and backend coordination. No old screenshot approval counts as verification of this revision.

After implementation, compare actual screens side by side with the original reference, not just against source or this document:

1. Narrow Inbox and On-deck: bold recognizable brand, strong row titles, actual colored code/label pills and dots, clock metadata, delicate dividers, predominantly unboxed rows, limited pale highlight, working inner selector, no global top tabs/inline capture field.
2. Bottom toolbar: selected Tasks container, central working capture, reference Today/Projects/Settings visibly marked Soon and accessible as unavailable. Placeholder taps do not change selection/navigation or call APIs. Both real lists remain reachable through the Tasks selector; selected Tasks tap reveals it. Safe areas and last row remain reachable.
3. Capture: plus opens the working input, full docked-keyboard screenshot, Close preserves idle draft, in-flight submission cannot lose input, all prior capture uncertainty protections remain.
4. Editor: exactly 1 Save, truthful automatic-qualification helper, waiting checkbox, and return warning only when clearing requirements. Backend-confirmed automatic transitions tested, including restored requirements. Toggle awaiting both ways on a fully organized task: it stays On-deck, with row badge added/removed after confirmation. An incomplete awaiting task remains Inbox with a badge; no readiness claim.
5. 320 width / 2.0 text: rows, inner list selector, 2-row toolbar fallback with readable labels/Soon captions, capture, editor, open menus, and scrolled actions. Capture actual docked keyboard; a floating IME toolbar does not prove inset behavior.
6. Wide web: same visual vocabulary, capped layout, normal 5-group toolbar with correct availability, readable focus and scrollbar; no placeholder pages.
7. Empty/unavailable/stale, validation, dirty-cancel, conflict comparisons, uncertain-save reload, missing/completed, and successful-save/failed-refresh presentation; preserved drafts and explicit choices. Include flag-only dirty edits, flag-only conflicts, uncertain flag-only saves, and summaries/read-only states showing awaiting Yes/No.
8. Interactive screen-reader/keyboard/hit-target checks, real Android/browser integration, and independent code review of revised source. Physical-phone/VPN and real HTTPS remain unverified unless actually exercised.

Previous screenshots demonstrated standard-size and enlarged-form usability for the superseded design, not fidelity to this reference-led proposal or the corrected automatic organization rule. New screenshots and verification are required.

## Revised web screenshot review: partial coverage

Reviewed the original reference alongside these actual revised web screenshots, without re-reviewing source:

- `/tmp/heap-revised-inbox-web.png`
- `/tmp/heap-revised-inbox-web-priority.png`
- `/tmp/heap-revised-capture-web.png`
- `/tmp/heap-revised-editor-web-incomplete.png`
- `/tmp/heap-revised-editor-web-qualifying.png`
- `/tmp/heap-revised-editor-web-awaiting.png`
- `/tmp/heap-revised-on-deck-web-awaiting.png`
- `/tmp/heap-revised-dirty-cancel-web.png`
- `/tmp/heap-revised-editor-web-return-warning.png`
- `/tmp/heap-revised-on-deck-web-functional.png`

### Reference comparison

The revised list is substantially closer to the reference, not merely unclipped. The larger 2-peak mountain/Heap header, strong title-versus-metadata hierarchy, pastel priority capsules with matching solid dots, clock metadata, unboxed rows/inset dividers, limited pale-green highlight, and prominent central plus in the 5-group toolbar reproduce its main visual vocabulary. Visible P1 Critical coral, P2 Important amber, and P3 Normal blue preserve the actual priority meanings. P4/P5 treatment is not evidenced in this screenshot set.

The toolbar includes the reference's Today/Projects/Settings composition and visibly marks each `Soon`. The waiting badge is a quiet secondary element, distinct from priority; the editor checkbox has an explicit manual-waiting label/helper. The single Save, automatic-qualification helper, and explicit return-to-Inbox warning are visually clear. Missing projects, descriptions, ranking reasons, and filter actions are intentional scope/data differences, not excuses to fabricate their appearance.

The web captures cannot establish reference fidelity at phone proportions. The full-width inner selector remains more utilitarian than the reference's compact rounded control group; see nonblocking polish below. This is **not full visual approval**.

### Findings

1. **Medium — save notification obscures the row just revealed.** In `inbox-web-priority`, `on-deck-web-awaiting`, and `on-deck-web-functional`, the highlighted just-saved row lies immediately behind the full-viewport-width success snackbar above the toolbar. Its lower clock/awaiting metadata is cut off or covered. In the awaiting screenshot the badge is only partly exposed directly above the dark notice. The saved destination/title/priority are visible, but the user cannot immediately inspect the full saved result while the confirmation is present. Ensure save-return scrolling reserves the notification's height as well as the toolbar, or place a compact confirmation so it does not cover the revealed row. Reveal the entire row after layout settles; if it cannot fit, prioritize title and metadata in the remaining viewport. Obtain a replacement screenshot showing the full clock/awaiting group visible while success feedback is displayed. This is a presentation finding, not a claim that persistence failed or that rows cannot be reached by manual scrolling.
2. **Low, nonblocking — wide-web selector is stretched into a long segmented strip.** In `inbox-web` and `capture-web`'s background, Inbox/On-deck spans nearly the entire content width, with widely separated labels. The reference uses compact rounded controls with more intentional spacing. On wide screens, consider a left-aligned, content-sized selector approximately 280–320 wide instead of stretching it across the 840 cap. Preserve 48 targets, selected semantics, and responsive growth at large text. No new filters or destinations are requested. Narrow-screen behavior must be judged from the upcoming Android images, not assumed from this web result.

### Evidence limits

Screenshots show presentation only. The coordinator reports Firefox capture draft restoration, partial-priority Inbox rows, atomic Save/automatic qualification, waiting edits preserving age, dirty Keep editing, requirement clears, and automatic restoration. These remain coordinator functional verification, not behavior proven by still images.

At this web-only pass, pending visual evidence included revised Android/320/2.0 text, actual docked keyboard (floating IME toolbar is not proof of inset handling), open menus including all priorities, error/stale/empty/loading states, conflict/uncertain-save reconciliation, missing/completed read-only, and saved-success/failed-refresh. The Android follow-up below updates standard-size coverage. Keyboard/screen-reader behavior and real hit rectangles are not verified from images. No claim of physical-phone/VPN/HTTPS verification or overall acceptance is made here.

## Revised Android follow-up: standard-size screenshots

Reviewed the original reference again alongside these 8 actual revised Android screenshots and the preceding web evidence; no source/code re-audit:

- `/tmp/heap-revised-inbox-android.png`
- `/tmp/heap-revised-on-deck-android.png`
- `/tmp/heap-revised-editor-android-incomplete.png`
- `/tmp/heap-revised-editor-android-awaiting.png`
- `/tmp/heap-revised-on-deck-android-awaiting.png`
- `/tmp/heap-revised-dirty-cancel-android.png`
- `/tmp/heap-revised-editor-android-return-warning.png`
- `/tmp/heap-revised-on-deck-android-functional.png`

### Combined visual-match judgment

At actual phone proportions the primary visual corrections are present: a substantial dark-green Heap wordmark and 2-peak mark, bold dark row titles, colored priority capsules with full labels and matching dots, clock metadata, light inset dividers, predominantly unboxed rows, and the reference-like bottom Tasks/Today/central plus/Projects/Settings composition. Soon captions visibly distinguish future tabs. The reference is now recognizable in the actual Android UI, not just in a design document. P1 Critical remains coral/highest, rather than copying the reference's contradictory P5-red example.

The inbox's many neutral Unset badges follow its actual missing priorities; making those rows colorful without data would be false. Some titles wrap more than the reference because they are longer test content and badges include full priority labels. These are not evidence of a broken editor or an excuse to invent descriptions. Limited pale highlighting is visible on the returned task, not all rows.

Standard-size editor labels, priority pill, clock duration, awaiting checkbox/helper, single Save, dirty-cancel choices, and explicit requirement-clear consequence are readable. The awaiting helper states that organized tasks stay on-deck; no false readiness label is shown. This is a positive partial visual-match judgment, **not full acceptance**.

### Findings and follow-up

- **Medium, confirmed on both platforms — save-return metadata is obscured by the success snackbar.** `on-deck-android-awaiting` shows the just-saved highlighted task with its clock/awaiting group behind the dark snackbar; the waiting badge is only partially exposed. `on-deck-android-functional` likewise cuts off the newly returned task's duration. This strengthens the existing web finding rather than adding a separate bug. Route the same fix through Frontend: reserve actual toolbar plus notice space when revealing the row, or position feedback without covering it. New Android and web proof should show the whole saved title/priority/clock/awaiting group while confirmation remains visible. There is no claim that manual scrolling is impossible or persistence failed.
- **Low, optional reference polish — Android has more empty space between brand and destination heading than the reference.** Compare the top of `inbox-android` and `on-deck-android` with the original's tighter brand-to-heading rhythm. If closer fidelity is wanted, trim approximately 16–24 logical pixels from this discretionary blank spacing, preserving text sizes, safe areas, and the real selector. This is not a clipping or functional defect; it should not delay the snackbar fix or expand scope. The earlier low-priority compact wide-web selector suggestion remains optional.
- No additional high/medium defect is evidenced by the standard-size editor/cancellation/warning shots. The warning is prominent above Save and includes a warning icon; the waiting checkbox does not resemble a task-row completion control.

### Remaining coverage

Still pending: revised 320/2.0 text, open priority/duration menus including P4/P5, scrolled actions, Android capture presentation, full docked keyboard/inset compression, empty/loading/error/stale states, conflict/uncertain-save comparisons, missing/completed, and confirmed-save/failed-refresh presentation. No full keyboard is present in this set; filenames or a floating hardware/IME toolbar cannot establish that coverage. Keyboard/screen-reader interaction and real hit rectangles remain outside screenshot proof.

The coordinator reports native capture draft restoration, automatic organization including waiting, flag-only dirty Keep editing, waiting clears preserving age, and priority clear/restoration transitions. These are coordinator functional checks, not results reproduced by Designer or inferred from stills. Future visual checks should cover revised UI only. No overall approval, physical-phone/VPN/HTTPS claim, or source re-review is made here.

## Enlarged Android and web recovery follow-up

Screenshot-only review of:

- `/tmp/heap-revised-on-deck-android-320-2x.png`
- `/tmp/heap-revised-editor-android-320-2x-top.png`
- `/tmp/heap-revised-priority-menu-android-320-2x.png`
- `/tmp/heap-revised-editor-android-320-2x-actions.png`
- `/tmp/heap-revised-capture-android-320-2x.png`
- `/tmp/heap-revised-conflict-web.png`
- `/tmp/heap-revised-conflict-comparison-web.png`
- `/tmp/heap-revised-uncertain-save-web.png`
- `/tmp/heap-revised-uncertain-matching-web.png`
- `/tmp/heap-revised-on-deck-web-checked.png`

The coordinator reports 320 logical width and 2.0 font scaling. The images visibly show enlarged text, a 2-row toolbar, full priority labels, and scrolled editor actions; the actual device settings and successful no-op/transport checks are coordinator test evidence, not independently reproduced here.

### Positive coverage

The open enlarged priority menu displays Unset plus P1–P5 without clipped labels. P4 sage and P5 gray are now visually evidenced alongside P1 coral/highest, P2 amber, and P3 blue. Editor labels/title/duration wrap legibly; the scrolled single Save is fully visible above the gesture area. The capture sheet shows enlarged field/helper/Add action; the floating IME toolbar obscures its left edge, so this is not proof of keyboard-inset behavior or an app-originated clipping defect.

Web uncertainty wording, known-ID reload action, readable 4-field draft summary including awaiting Yes, matching-current-state message, and explicit Return to on-deck action are shown. The conflict summary visibly includes saved awaiting Yes and preserves the local draft. These screens present real recovery choices instead of silently repeating a save. Their transport success is established only by the coordinator's reported checks.

### Additional findings

1. **Medium — at 320/2.0 the list's navigation/explanation crowds actual tasks out of the initial view.** In `on-deck-android-320-2x`, the 2-row toolbar occupies approximately the lower 35% of the screenshot; the large heading/explanation/selector use the remaining initial list view, leaving only part of a decorative task dot and no task title visible. This is not a claim that scrolling is impossible—the coordinator reports reaching rows—but it makes the primary content unusually hard to discover. Tighten the large-text toolbar's discretionary vertical padding/gaps and use compact icon/label groups, retaining full scaled text, 48 targets, all approved placeholders, Soon availability, and central capture. Also shorten large-text-only explanatory copy, for example `Organized tasks. Oldest first.`, instead of repeating the longer multi-line explanation plus order sentence. Preserve truthful wording and the real inner selector. Obtain a 320/2.0 initial-view screenshot with a task title visible; do not fix by capping font scale or concealing future tabs. This refines the fallback's spacing/copy, not business behavior.
2. **Medium — the explicit draft waiting value is below the fold when version choices are already offered.** In `conflict-comparison-web`, `Saved on server` includes `Awaiting external dependencies: Yes` above Use saved version/Keep my edits, while the normal dark `Your unsaved draft` summary's corresponding No value lies below the visible scroll area. A faint unchecked disabled checkbox is the only visible local indication. Show readable Saved/Your draft summaries of all 4 fields together, preferably before the choice buttons; when frozen for reconciliation, avoid making users scroll through a duplicate disabled form before reaching the draft's waiting value. Use compact stacked summaries rather than inventing a merge or changing version semantics. A replacement screenshot should clearly expose the flag difference and both choices. No data-loss or failed conflict-protection claim is made.
3. **Low — a recognized conflict also displays a redundant technical “unexpected response” error.** `conflict-web` correctly explains the server change, but adds `The server returned an unexpected response (409).` That second panel makes a handled business conflict sound like an unrelated protocol failure. Retain the specific conflict/draft-kept/reload guidance and suppress or replace the redundant generic technical panel for this recognized case. Recovery remains available, so this is clarity polish rather than a navigation failure.
4. **Low — matched-state confirmation retains a warning-triangle icon.** `uncertain-matching-web` says that the saved state matches but uses the same warning symbol as the return-to-Inbox consequence. Use an information or success icon for resolved current-state confirmation while preserving warning icons for real unresolved/consequence states. The words are already clear; this is nonblocking polish.

The previous **medium success-snackbar occlusion** remains visible in `on-deck-web-checked`: the highlighted returned task's clock/awaiting group is covered. It is not resolved by the new recovery proof. The optional normal-size spacing/compact-selector suggestions remain lower priority.

### Coverage still open

Now evidenced: enlarged priority menu including every priority, enlarged editor top/scrolled Save, capture presentation with floating toolbar, and standard-size web conflict/uncertain matching presentation. Still needed: actual full docked keyboard, duration menu, clearly visible scrolled large-text task/awaiting metadata and initial-list density after adjustment, large-text error/comparison states, unknown-outcome differing-version/reload-failed presentation, missing/completed, empty/loading/unavailable/stale, and saved-success/failed-refresh. No whole-suite visual approval or interactive accessibility proof follows from this set.

The coordinator reports real flag-only conflict handling and a committed PUT with dropped response followed by known-ID GET, no duplicate POST/automatic retry, and preserved age. Those are coordinator functional results; Designer did not re-audit source, duplicate those tests, or infer request counts from the screenshots.

## Heap filter pills: approved Time or Priority

Barrett requests real `Time` and `Priority` filter pills on the heap page. He clarified that the pickers are **mutually exclusive**, and explicitly deferred Project until projects are available. Do not show a Project filter or implement project metadata/API changes in this step. This overrides the earlier exclusion of filtering only for the requested Time/Priority feature; it does not authorize sorting or project management.

### Behavior

- Tapping a pill opens its single-value picker. Opening/dismissing a picker does not alter the current filter.
- Time `30m` means duration **greater than or equal to 30 minutes**, not an available-time maximum. Offer existing durations 5/15/30/60/120/240 minutes with minimum-duration wording.
- Priority `P1` matches only P1 tasks. Offer P1–P5 with their existing full labels/colors.
- Only 1 filter type can be active: selecting a Time value clears Priority; selecting Priority clears Time. Never combine criteria.
- Each picker includes `Any`, which returns to the full unfiltered heap. Clearing does not write task data or reorder rows.
- Filters remove nonmatching rows without changing incoming server order, task membership, waiting flags, or the canonical list. Filtering works on the complete already-fetched heap list; no additional HTTP calls or backend changes are needed.
- Keep the active filter while visiting Inbox/editing/refreshing; reset on app restart. Apply filtering again to fresh/confirmed task snapshots without silently clearing the user's selection.

### Presentation

Put 2 compact, reference-like rounded controls below the real list selector. Inactive labels are `Time` and `Priority`, with clock/priority icons and dropdown indicators. The selected pill uses the existing deep-green active treatment and exposes its selected state; selected labels are `Time: ≥30m` or `Priority: P1`. Expose the full selected value in accessible labels, for example `Time filter, at least 30 minutes` or `Priority filter, P1 Critical`. Never rely only on color. Wrap at narrow widths/large text instead of shrinking text or extending beyond the viewport. Maintain 48 logical-pixel targets and readable labels/options.

A filtered-empty result says `No tasks match this filter` and offers `Clear filter`, distinct from a genuinely empty heap or unavailable API. Existing loading/stale/error messages remain independent of filtering. If a confirmed saved task is excluded, retain the filter, give accurate save feedback, and restore heading/filter focus instead of hidden-row focus; do not claim to reveal the excluded row. Inbox is not filtered.

### Handoff and verification

Frontend owns implementation under `ui/**`; Designer owns this document only. No backend, ranking, shared contract, project editor, or unrelated visual cleanup is part of this step. Verify Time 30 includes 30/60/120/240 and excludes 5/15, exact Priority matching, switching filter types, cancelled picker preservation, Any/clear, unchanged input order, no filter HTTP writes/reads, distinct empty/no-match/error states, save/refresh retention and focus, and 320/2.0 text wrapping/readable menus. Provide real normal-size and enlarged Android/web screenshots for Designer review after tests.

Separate follow-up reported by Frontend while reading existing source: the task-row status accessibility label in `ui/lib/task_widgets.dart` reportedly announces Inbox for heap rows as well. This has not been independently verified by Designer; keep it separate from filter implementation and do not claim screen-reader approval from screenshots.

### Filter independent review

The coordinator-launched high-reasoning reviewer approved the filter implementation with no blocking findings. It independently ran 21 tests across `heap_filter_test.dart`, `heap_filters_widget_test.dart`, and `task_lists_test.dart`; all passed. Targeted analysis of the 7 reviewed implementation/test files found no issues. Review confirmed minimum Time, exact Priority, mutual exclusion, canonical-list/order preservation, no extra HTTP, selection retention, empty/no-match/error/stale distinctions, excluded-save heading focus, and widget coverage of 320/2.0 menus/selected semantics/48-pixel targets.

Optional test improvement, not a blocker: change filter or destination before completing the delayed refresh, then assert selection/focus stay unchanged. The present filter test changes the filter afterward; existing unfiltered tests cover newer capture/editor interactions. Actual screenshots and full checks are recorded separately below; interactive accessibility is not established by this source/test review.

### Filter screenshot review: 26-image pass

Compared the filter controls with the original reference's compact rounded controls while preserving the explicitly requested minimum-duration and exclusive-filter behavior. Read every supplied image:

- `/tmp/heap-filters-android-{normal,time-menu,time30,priority-menu,priority1,no-matches}.png` (6 actual normal-size Android captures).
- `/tmp/heap-filters-android-320-2x-{initial,controls,time-menu,time30,priority-menu,priority1,no-matches}.png` (7 actual enlarged Android captures).
- `/tmp/heap-filters-web-{normal,time-menu,time30,priority-menu,priority1,no-matches}.png` (6 actual normal-size Firefox captures).
- `/tmp/heap-filters-web-320-2x-{initial,controls,time-menu,time30,priority-menu,priority1,no-matches-scrolled}.png` (7 actual narrow enlarged app-frame captures).

Frontend reports the web enlargement uses a real 320×800 same-origin app frame with browser text scale 2.0, not a resized bitmap or a claimed 320-wide browser window. Device/window settings restoration, unchanged GET data, and live interaction results are Frontend checks, not independently reproduced by Designer.

**Filter-specific visual judgment: accepted for the Time/Priority feature; both final recaptures are verified below.** The 2 pills are compact and recognizable beside the reference's rounded controls; clock/flag/chevron and deep-green selected treatment communicate filter type and current selection without fabricating data. Android and narrow web wrap into 2 readable rows instead of shrinking labels. `Time: ≥30m` is explicit; priority P1 selection leaves Time neutral, and Time selection leaves Priority neutral. Full-colored priority menus including P4/P5 are readable. Android menus show all minimum-duration options. Narrow enlarged web menus also show all options; overlays may cover underlying content while open, which is expected for a picker. No Project filter is present.

Normal and scrolled enlarged no-match views clearly say `No tasks match this filter`, display the active P4 pill, and expose Clear filter; they do not claim the heap is empty. Scrolled controls/task titles are visible in enlarged shots. The prior large-text initial-view density finding remains: the long header and tall footer hide filters/tasks until scrolling. It is not a new filter regression or authorization for unrelated cleanup; no claim of entire-app large-text acceptance is made here.

Final recaptures:

1. **Resolved:** reread the replaced `/tmp/heap-filters-web-time-menu.png`; Any plus all 6 minimum-duration options (5/15/30/60/120/240) are fully visible and readable within the normal-size web viewport. The earlier partial capture was not evidence of disabled or unreachable choices.
2. **Resolved:** reread the final-source replacement `/tmp/heap-filters-web-320-2x-no-matches-scrolled.png`; full no-match text and Clear filter are visible. Frontend reports the actual Clear reset and semantic 48 target verified on final web/Android builds. Actual hit size is covered by widget/interaction checks, not measured from this image alone. Both requested filter recaptures are now complete.

Frontend reports full 89 tests passing (78 prior + 11 added filter tests), clean Flutter analysis/format/diff check, debug/release Android builds and web build. The independent reviewer separately ran 21 targeted tests and targeted analysis successfully. No live Save was performed for this visual pass; filtered-save/delayed-refresh focus is covered by regression tests, not a screenshot claim. Physical phone, full keyboard, VPN/HTTPS connection, and interactive screen-reader behavior remain unverified. The earlier row-status accessibility issue and other visual findings remain separate. Project/API changes being implemented elsewhere require a separate coordinated contract/frontend step; they are not part of this filter acceptance.

**Closeout:** Frontend confirms the final source is unchanged, with 89 tests/analysis/builds passing. The independent review has already passed; do not spawn a duplicate reviewer. Designer accepts the filter-specific visuals, including both final recaptures. Frontend confirms final Clear sizing and obsolete-notice removal preceded the reviewed source freeze; no source delta or duplicate review is needed. The agreed feature is ready for Barrett's review: Time or Priority, no Project, minimum duration, exact priority, no new sorting. This does not approve unrelated app-wide visual/accessibility issues or the upcoming project API integration.
