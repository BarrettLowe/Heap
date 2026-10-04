# Heap V1 implementation tasks

Work through these together, one small change at a time. The order is a starting point; adjust it as we learn. Check off tasks after verification, not just implementation.

Requirements and domain decisions live in `personal_task_project_manager_v1_spec.md`.

For coding tasks: agree on the immediate behavior, write a failing test, implement the smallest change, then review together. Names and package boundaries below are responsibilities to design, not a prescribed class hierarchy.

## 1. Spec cleanup (optional; likely skipped)

- [x] Fold the agreed domain decisions into the original spec.
- [ ] Record unresolved questions without deciding them prematurely.

Verification: the spec matches our current decisions. This is not a prerequisite for coding.

## 2. Architecture boundaries

- [ ] Agree on the division between task/project dataclasses, application operations, persistence, and ranking policies.
- [x] Sketch package boundaries and the persistence interface for the first slice.
- [x] Decide how to supply time explicitly in tests.

First slice: `src/heap/logic/` holds task snapshots, `TaskOperator`, and the `TaskStore` interface (`save`, `get`); `persistence/` holds SQLite. Production reads current UTC time; tests patch the time source without changing the public API.
- [ ] Trace capture and recommendation requests through the proposed components.

Verification: we can explain which component owns each responsibility without designing every future class.

## 3. Python project and test setup

- [x] Choose dependency management and test tooling.
- [x] Create the initial package and test layout.
- [x] Add a smoke test and document the test command.

Verified with `uv run pytest`: three capture/storage tests pass. Tooling: uv, pytest, and pytest-cov; commands are in `README.md`.

Verification: one command runs the tests successfully.

## 4. Capture operation and SQLite round trip

- [x] Define the minimum inbox task model: identifier, title, and timestamps.
- [x] Add the persistence operations needed to save and retrieve it.
- [x] Implement those operations in SQLite.
- [x] Route title-only capture through the application operation.
- [x] Test retrieval after closing and reopening the database.
- [x] Add `TaskOperator.list_inbox()` with oldest-first ordering and ID tie-breaking.

Inbox listing verified: empty results, reopening with multiple tasks, stable ordering, independent snapshots, and exclusion of non-inbox rows. Full suite: eight passing tests, 100% line coverage.

Verified: capture preserves ID, title, inbox status, and UTC timestamps across reopening. Tests also check missing IDs and explicit-save behavior. First-slice line coverage: 100%.

Verification: a captured inbox item survives a restart. This is the first working end-to-end slice.

## 5. Projects and moving tasks on-deck

- [x] Add project creation and retrieval through the logic and persistence layers.

Project creation/retrieval verified: active projects with optional descriptions and UTC timestamps survive reopening SQLite; missing IDs return `None`; snapshot changes require explicit saves. Full suite: twelve passing tests, 100% line coverage.
- [x] Define priority levels and their descriptive labels.
- [x] Define duration buckets.

Priority/duration verified: P1–P5 carry the agreed labels; duration supports unknown and 5/15/30/60/120/240 minutes. Capture leaves priority unset and duration unknown. All combinations survive SQLite reopening; the previous schema upgrades without losing tasks. Full suite: 61 passing tests, 100% line coverage.
- [x] Agree on on-deck requirements: assigned priority, known duration, project optional.
- [x] Add task organization and moving on-deck, recording `on_deck_since`.
- [x] Keep unknown-duration items in the inbox for clarification.
  - [x] Reject moving an unknown-duration inbox task on-deck.
  - [x] Clearing priority/duration returns an on-deck task to the inbox and clears `on_deck_since`.

On-deck verified: standalone and project-associated tasks survive reopening; repeated moves and valid edits preserve on-deck age. Clearing a required field returns the task to the inbox, and a later explicit move starts a new timestamp. Full suite: 86 passing tests, 100% line coverage.

Verification: a captured item can become a scoped, on-deck task with or without a project; an unknown-duration item cannot enter actionable recommendations.

## 6. Lifecycle operations

- [x] Add task and project editing.
  - [x] Add task priority/duration setters, including clearing values.
  - [x] Add task title editing and project assignment/reassignment/removal.
  - [x] Add project name/description editing, including clearing the description.
- [x] Define meaningful changes for updated timestamps.
  - [x] Priority/duration changes update `updated_at`; unchanged values do not save or change timestamps.
  - [x] Apply the same timestamp/no-op rules to title and project edits.
  - [x] Apply the same timestamp/no-op rules to project name/description edits.

Task editing verified: title, priority, duration, and project edits survive reopening, preserve inbox status and unrelated fields, and leave unchanged values alone. Project assignment checks existence; missing IDs raise `KeyError`. Older task tables gain nullable project IDs. Full suite at that step: 74 passing tests, 100% line coverage.

Project editing verified: name and description edits (including clearing descriptions) through `ProjectOperator` survive reopening SQLite and preserve unrelated fields. Unchanged values do not save or change timestamps; missing IDs raise `KeyError`. Existing direct-save snapshot tests remain unchanged. Full suite: 93 passing tests, 100% line coverage.
- [x] Persist optional custom project MDI icon names and color strings in SQLite.

Custom project icon/color fields default to `None` and survive explicit save/reopen; full suite: 297 passing tests.
- [x] Expose project icon and color through the create, update, and read API.

API verification covers setting and returning custom values through create/update/read; omitted values default to or clear to `None`.
- [x] Add task completion with a completion timestamp and retained history.
- [x] Add intentional task hard deletion.
  - [x] Add all-or-nothing batch deletion and dependency-link cleanup.

Completion/deletion verified: inbox and on-deck tasks retain their fields and completion timestamps across reopening; repeated completion does not save or read time. Completed tasks stay out of the inbox and cannot move back on-deck. Explicit deletion removes inbox, on-deck, or completed tasks without changing other tasks or their projects. Missing IDs raise `KeyError`; write failures propagate without reporting success. Older task tables gain nullable completion timestamps without losing existing data. Full suite: 104 passing tests, 100% line coverage.

Verification: lifecycle tests check state and timestamps, including SQLite round trips.

## 7. Dependency model and derived blocking

- [x] Represent task dependencies and a manual external-blocking flag.
  - [x] Store task-to-task dependencies and add application operations to add, remove, and list them.
  - [x] Add a fully manual `externally_blocked` boolean and setter, with no ranking influence.
- [x] Derive dependency blocking from unfinished prerequisite tasks.
  - [x] Add single-task and bulk checks; verify a 100-task lookup uses 1 query.
- [x] Reject self-dependencies and cycles.
- [x] Decide what happens when a prerequisite is deleted.

Dependencies/batch deletion verified: links survive reopening in stable ID order; self-dependencies, cycles, and missing task IDs are rejected. Explicit link edits update only the dependent task's timestamp in the same transaction; unchanged links do not write or read time. Deleting a task removes all incoming/outgoing links without changing surviving task snapshots. Batch deletion rolls back tasks and links if any ID is missing or any deletion fails; empty batches do nothing and repeated IDs count once. Existing databases gain the dependency table without losing task data. Full suite: 133 passing tests, 100% line and branch coverage. Cycle validation currently assumes non-overlapping dependency edits; overlapping writers are not yet supported. At that step, external blocking and derived blocking remained open.

Manual external blocking verified: tasks default to `externally_blocked=False`; setting/clearing through `TaskOperator` survives reopening and changes only the flag and `updated_at`. Unchanged values do not save or read time; missing IDs raise `KeyError`; failed saves propagate. The flag stays manual through dependency and lifecycle operations. Older databases gain a false default without losing task data. No ranking or eligibility behavior was added. Full suite: 146 passing tests, 100% line and branch coverage. At that step, derived dependency blocking remained open.

Dependency blocking verified: `TaskOperator.is_dependency_blocked()` uses `get_dependency_blocking()` for a single ID. Bulk checks use 1 SQL query against current saved prerequisite statuses; no prerequisites or only completed prerequisites produce `False`. Completing, unlinking, or deleting a prerequisite changes the result without saving a blocking flag, while other unfinished prerequisites still block. Checks ignore the manual external flag and do not decide task eligibility. Empty input returns `{}` without SQL; repeated IDs count once; missing IDs raise `KeyError` in input order. Tests trace the SQL to verify single-task and 100-task lookups use 1 query, including after reopening. Full suite: 163 passing tests, 100% line and branch coverage.

Verification: completing a prerequisite removes its dependency-blocking effect; other unfinished prerequisites still apply.

## 8. Context model and eligibility policy

- [ ] Define structured location and resource requirements.
- [ ] Represent optional organizational tags without giving them ranking influence.
- [ ] Define recommendation query inputs, including available time and context.
- [ ] Exclude completed, inbox, unscoped, oversized, and derived-blocked tasks.
- [ ] Filter by duration fit and context match.
- [ ] Test that future recurring due dates do not make tasks ineligible.

Verification: tests identify exactly which tasks qualify for a query such as "30 minutes, inside." Duration changes eligibility, not importance.

## 9. Ranking policy and explanation results

- [ ] Agree on initial priority weights and the nonlinear due-date urgency curve.
- [ ] Add a bounded age contribution measured from `on_deck_since`.
- [ ] Add a small optional project-priority contribution.
- [ ] Expose the contributions and eligibility decisions in result data.
- [ ] Define a stable tie-breaker and test with a fixed time.

Verification: identical state, time, and query inputs produce identical ordering. Results explain why one task ranks above another.

## 10. Diversification and project queries

- [ ] Apply a configurable per-project cap after scoring and sorting.
- [ ] Decide how project-less tasks count toward caps.
- [ ] Expose diversification decisions without changing underlying scores.
- [ ] Add a project-specific query without the global cap.

Verification: one project cannot flood global results, while its project view remains uncapped.

## 11. Review policies for inbox and staleness

- [ ] Detect inbox items beyond the configurable review age.
- [ ] Flag on-deck tasks beyond the configurable staleness threshold.
- [ ] Keep review conditions separate from actionable recommendations.
- [ ] Test threshold boundaries and the age-bonus cap.

Verification: review flags do not silently classify, modify, or delete tasks, and old tasks do not receive unlimited ranking power.

## 12. Completion-based recurrence

- [ ] Define recurring series metadata and its relationship to task occurrences.
- [ ] Generate the next occurrence from actual completion time.
- [ ] Preserve completed occurrences as history.
- [ ] Complete the current occurrence and create the next one in a single transaction.
- [ ] Prevent repeated completion from generating duplicate outstanding occurrences.

Verification: late completion shifts the next due date correctly, with only one outstanding occurrence and no partial database writes.

## 13. Calendar-based recurrence

- [ ] Agree on the calendar rules supported in V1.
- [ ] Define which scheduled date follows early or late completion.
- [ ] Calculate the next date without shifting the calendar cadence.
- [ ] Keep missed occurrences from accumulating as duplicate tasks.

Verification: early, late, and several-weeks-missed cases preserve the agreed cadence with only one outstanding occurrence.

## 14. Project-completion policy

- [ ] Decide when a project should be flagged for completion review, including blocked and unsorted work.
- [ ] Decide how explicit project completion affects unfinished tasks and recurring series.
- [ ] Implement explicit completion and review flags without auto-completing projects.

Verification: project completion is deliberate, and tests cover its effect on recommendations.

## 15. V1 integration harness

- [ ] Add a minimal script or CLI that calls the same application operations.
- [ ] Create realistic sample data.
- [ ] Request the five best tasks given available time and context.
- [ ] Verify explanations, diversification, recurrence history, and persistence together.

Verification: the spec's "five best tasks, 30 minutes, inside" example works reproducibly without adding business rules to the interface.

## 16. Flutter UI — Android first

UI work starts alongside the unfinished Python core, in small agreed steps.

- [x] Create a separate UI worktree and choose the first target.
- [x] Set up the Android SDK and choose a physical device or emulator.
- [x] Agree on the Flutter project location and launch the starter app on Android.
- [ ] Set up and verify physical-phone testing alongside emulator testing.
- [x] Replace the counter starter with a temporary in-memory Heap inbox and capture form.

Worktree verified with `git worktree list`: `feat/flutter-ui` at `/home/barrett-lowe/PersonalDev/Heap-ui`. Android is the first target. `flutter doctor -v` passes the Android toolchain check with the SDK at `~/Android/Sdk`; `flutter devices` detects `emulator-5554`.

Starter verified: generated the Android-only `heap_app` package in `ui/`. `flutter analyze` found no issues; `flutter test` passed the counter test. `flutter run -d emulator-5554 --no-resident` built, installed, and launched the app; an adb screenshot confirmed the counter screen. Physical-phone testing remains unverified.

Inbox verified: 4 widget tests pass for the empty state and temporary-storage notice, trimmed title capture and input clearing, blank-title rejection, and keyboard submission in capture order. `flutter analyze` reports no issues. The app builds and launches on `emulator-5554`; adb input and screenshots confirm empty and populated inboxes. Tasks are temporary in-memory titles, not saved to Python. Styling takes inspiration from Barrett's supplied reference; ranking, filtering, and navigation are not implemented.

Verification: the Android inbox accepts and displays titles; the temporary-storage boundary is explicit.

## 17. Server-backed framework setup

Agreed scope and ownership are in `docs/framework-plan.md`; the shared HTTP contract is in `docs/api-contract.md`. Existing Frontend and Backend agents implement separate paths and each obtains its own Sol 6.1/high review with iterative fixes.

- [x] Plan the framework setup and freeze the first HTTP contract.
- [x] Backend: add and test the HTTP interface over existing capture/inbox operations.
- [x] Backend: add Docker/Compose, health checks, and persistent SQLite volume configuration.
- [x] Frontend: replace temporary storage with an HTTP client and loading/error/retry/capture state.
- [x] Frontend: verify Android builds and add a minimal web target.
- [x] Complete both independent review/fix cycles and rerun checks.
- [x] Verify integrated capture/list and storage across container/app restarts.
- [x] Verify browser behavior against the API with explicit CORS configuration.
- [ ] Verify physical-phone connectivity and behavior.

Backend verified: coordinator independently ran `uv run pytest` (175 passed; 1 upstream Starlette/httpx deprecation warning), coverage (98.93% overall lines; core 100%), lock validation, Compose config validation, and whitespace checks. An isolated Docker project passed health, real capture/list, allowed-origin CORS preflight/error checks, and exact snapshot retention across forced container recreation. Backend's required Sol 6.1/high reviewer found JSON-parser and invalid-Unicode handling issues; regression tests and follow-up review passed.

Frontend verified: coordinator independently ran analysis (no issues), 25 passing tests, and the web build. Frontend reported final debug/release APK builds; coordinator installed the debug APK and independently checked both merged manifests for INTERNET permission and debug-only cleartext networking. Its explicit Sol 6.1/high reviewer approved the final source after fixes for refresh reactivity, guarded uncertain-write resubmission, stale state, origin/response validation, timestamps, and read/write merge races.

Integrated verification: Android emulator and Firefox web UI both captured into the same real SQLite inbox. Android app and browser page restarts reloaded saved tasks; exact task snapshots survived forced container recreation. Stopping the backend produced visible stale/unavailable warnings in both clients; refresh/retry recovered. A disconnected Android POST preserved its draft without queued retries. Browser fault injection dropped a response after a real save: the UI warned of an unknown outcome, kept the draft, and refresh revealed exactly 1 saved task without resubmitting. Physical-phone checks remain pending.

Only check off implementation after its tests/reviews pass. Browser and phone checks remain pending unless actually performed. Do not implement the unfinished ranking, recurrence, or eligibility roadmap in this step.

## 18. Inbox → editor → On-deck

Barrett approved this batch. Plan/ownership: `docs/task-flow-plan.md`; API additions: `docs/api-contract.md`; Designer owns `docs/task-flow-design.md`. Coordinator now spawns independent Sol 6.1/high code reviewers; the earlier team ceiling is relaxed for temporary planning/review help.

- [x] Revise/freeze the contract for qualification-based On-deck membership, manual external waiting, retained age, and atomic startup normalization.
- [x] Designer: revise layouts to closely follow the reference, including authorized future-tab placeholders and responsive toolbar.
- [ ] Backend: revise atomic organization and listing for automatic on-deck qualification.
- [ ] Backend: align HTTP contract/validation and tests with the corrected policy.
- [ ] Frontend: Inbox/On-deck navigation and reusable task editor.
- [ ] Frontend: draft/conflict/uncertain-save handling and server-confirmed list transitions.
- [ ] Run independent code review/fix cycles and regression checks.
- [ ] Verify real Android/web atomic Save, automatic placement/restoration, waiting flag, age, recovery, and persistence.
- [ ] Designer: review running narrow/keyboard-open Android and wide-web/error screenshots.

Approved correction: qualification determines unfinished-task On-deck membership; there is 1 atomic Save and no move action. “Hidden” meant existing manual external waiting, not another feature; organized waiting tasks remain visible with a badge. Keep time-on-deck for possible future ranking. Normalize existing qualifying Inbox rows atomically at startup. Barrett lifted the pause and approved reference-led styling plus visible placeholder tabs without pages (Today/Projects/Settings). Coordinator read and accepted Designer's final amendment: Tasks / Today / Capture + / Projects / Settings, with Inbox/On-deck inside Tasks and Soon placeholders. Backend and Frontend received GO in non-overlapping paths. Prior explicit-move verification below is historical, not completion of this revision.

Prior-policy backend verified: independent coordinator-spawned Sol 6.1/high review approved the source, ran 218 tests with 99% line coverage, and probed no-ops/repeated moves, competing stale PUTs, rollback/reopening, strict validation, and CORS errors. Coordinator rebuilt the Docker preview and verified real HTTP save+move, both list transitions, unchanged-save behavior, preserved age on edits, stale conflict, each/both nullable requirement clears, restoration staying Inbox, renewed age on explicit moves, and PUT CORS. Frontend/code-review/visual/integration completion remains pending.

Stop after this task flow. The manual external-waiting checkbox and visible future-tab placeholders are approved; no project/Today/Settings pages, ranking, filters, completion/history, dependency editor, recurrence, or offline storage.

## 19. Pull-request CI and container publishing

Barrett requested CI tests for pull requests and publishing the Docker container
to the registry. This step only covers build/test/release infrastructure.

- [x] Verify the existing Python suite and coverage baseline.
- [x] Verify pull-request CI: locked Python dependencies, coverage, Flutter analysis/tests, and Docker build/smoke checks.
- [ ] Verify GHCR publishing after successful checks, with `latest`, full commit SHA, and version tags.
- [x] Document registry image use and publishing permissions.

Local baseline: 297 Python tests passed with 97.75% line coverage. CI uses the
existing Python 3.12/uv 0.9.22 container toolchain and Flutter 3.47.6, matching
the stable revision recorded in `ui/.metadata`.

Remote verification: [PR #1](https://github.com/BarrettLowe/Heap/pull/1) passed
the Python coverage job, Flutter analysis/tests, and Docker build/configuration/
health/capture/volume-persistence checks in
[CI run 37198829776](https://github.com/BarrettLowe/Heap/actions/runs/37198829776).
The publishing job was correctly skipped for the pull-request event. First GHCR
publication remains pending merge: Barrett requested review before merging.

## 20. Project list and editor UI

Barrett approved the design and Flutter implementation. Barrett owns the
backend/API; Frontend owns the UI, with independent code and visual review.

- [x] Design a simple list with each project's color, icon, and name, plus Add project.
- [x] Design add/edit for those 3 fields and deletion with a clear warning that all assigned tasks are permanently deleted.
- [x] Review the proposal with Barrett before implementation.
- [x] Implement Projects navigation, list, and add/edit/delete UI against the existing API.
- [x] Pass independent code review and Flutter checks.
- [x] Verify actual Android emulator and web project flows and visual match.
- [ ] Verify on a physical phone.

Design: `docs/project-editing-design.md`; mockup: `docs/project-editing-mockup.svg`.
Keep the existing Heap style. No project task view or unrelated features.

Coordinator checks so far: 114 Flutter tests and analysis passed; web/debug APK
built. Against an isolated Compose API, Firefox and emulator verified creation,
all 3 edits, picker-only dirty cancellation, delete cancellation and confirmation,
and task capture remaining separate. Firefox confirmed deletion removes assigned
Inbox/Heap tasks but retains standalone tasks; initial Enter cancels deletion.
Android at 320 width / 2.0 text kept menus and destructive actions reachable.
Saved colors/icons outside the menus and the hidden description survived
name-only editing; explicit None cleared color/icon. A stopped API left web rows
visibly stale, and the persistent database retained saved values after restart.

Independent review found a delayed-delete stale-task issue; Frontend added a
failing regression then fixed it. UI-only task transport now preserves the
API's required nullable `project_id`, without adding assignment controls.
Coordinator reran analysis and all 126 tests, and verified final rebuilt apps:
Firefox saves both standalone and assigned tasks without losing associations;
Android task Save and Projects navigation work; final web create/pickers/delete
smoke passes. A create-404 error-path bug was fixed with a failing regression;
a live browser-injected 404 preserved all 3 fields and deliberate retry succeeded.
Web and debug APK builds pass. No backend files changed.

Designer approved the represented settled web, Android, and 320/2.0 text
screenshots with no blocking findings. Independent reviewer approved final UI
source after the delayed-delete and create-404 fixes. Conservative uncertain-delete
stale warnings may remain until checked or restarted; this is nonblocking.
Physical phone is not connected and remains unverified.
The emulator uses a floating keyboard; conventional docked-keyboard and live
screen-reader interaction remain unverified.

## 21. Expanded project pickers

Barrett chose common icons plus Browse all for the full offline MDI library,
and requested 20 unnamed color circles in an always-visible grid, ordered
chromatically with an even spread across the spectrum. This is UI-only;
backend/API remain Barrett-owned. Luna implements and Sol reviews this work.
Shared design: `docs/project-editing-design.md`.

- [x] Bundle the full MDI library and add searchable Browse all, keeping quick choices.
- [x] Show 20 hue-ordered color circles plus None inline, with no dropdown or color names.
- [x] Pass combined independent review and Flutter checks after both changes are ready.
- [x] Verify real Android/web icon search, selection, colors, cancellation, and saved values.
- [x] Designer: review actual narrow/large-text and wide-web picker screenshots.
- [ ] Verify on a physical phone.

MDI 7.4.47 bundles all 7,447 icons. Luna implemented the inline grid with
18-degree HSL steps (60% saturation / 45% lightness). Sol approved the final
changes after fixes for None/checkmark overlap, focus-ring contrast, and a
smaller selection badge that keeps the chosen hue visible.
Coordinator independently passed analysis and all 153 tests, rebuilt web/debug
APK with the correct `HEAP_API_BASE_URL`, and exercised both final apps.

Firefox and emulator verified inline colors, full-library search/selection,
actual non-common glyphs, draft-only edits, saved hex/icon names, and reopening.
Web verified no results, Clear, Escape and dirty discard; Android at 320 width /
2.0 text verified None selection, browser cancellation and dirty discard. Actual
narrow Firefox viewport was 500 pixels (browser minimum), not 320. No backend
files changed. Physical-phone/docked-keyboard/live screen-reader checks remain
unverified. Designer approved the other represented picker states, including the
readable 2-column Android 320/2.0 icon browser as an acceptable design deviation.
Sol Designer approved the final selected-hue and None screenshots, including
Android 320/2.0 text, with no blocking visual findings.
