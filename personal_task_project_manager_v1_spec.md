# Heap — Personal Task & Project Manager

## Version 1 Domain Specification

Task terminology: **on-deck** means organized work waiting for its turn, not
necessarily unblocked or started. Older references below to active tasks mean
on-deck tasks; project status remains Active.

### 1. Purpose

Build a personal task and project management system optimized around the
question:

**"Given my current constraints, what should I work on next?"**

The system is intended primarily for personal projects and hobbies,
where hard deadlines are relatively uncommon and priorities change over
time.

It should differ from conventional task managers by emphasizing:

-   Manual priority rather than due-date-first organization
-   Time available
-   Current context
-   Prevention of stale or forgotten tasks
-   A small, useful ranked list rather than an overwhelming backlog
-   Easy capture without requiring immediate organization
-   Encouragement to break large or vague work into actionable tasks

Version 1 should focus only on the **domain model, persistence, and
business logic**.

UI design, AI-assisted ranking, external integrations, notifications,
and collaboration are explicitly outside the Version 1 scope.

------------------------------------------------------------------------

# 2. Architectural Requirements

The application should use three conceptual layers.

## 2.1 Persistence Layer

Initial implementation may use SQLite.

Responsibilities:

-   Persist tasks
-   Persist projects
-   Persist dependencies
-   Persist recurrence information
-   Persist completion/history information
-   Persist context metadata
-   Provide storage and retrieval operations

The persistence layer should contain as little business logic as
possible.

Avoid:

-   Business rules implemented in SQL
-   Database triggers for application behavior
-   Ranking calculations inside SQL
-   Tight coupling between the schema and a particular UI

Database constraints for basic data integrity are acceptable.

## 2.2 Domain / Logic Layer

Implemented in Python.

This is the authoritative layer for all application behavior.

All writes to persistent storage should flow through this layer.

Responsibilities include:

-   Task lifecycle
-   Project lifecycle
-   Ranking
-   Eligibility filtering
-   Duration handling
-   Context filtering
-   Dependency handling
-   Recurrence
-   Inbox handling
-   Staleness detection
-   Completion behavior
-   Project diversification

Business rules should be independently testable.

Major behaviors should be modular enough to replace or modify without
restructuring the whole application.

Examples:

-   Ranking strategy should be replaceable.
-   Persistence implementation should be replaceable.
-   Recurrence logic should be isolated.
-   Context filtering should be isolated.
-   Staleness logic should be isolated.

Dependency injection or equivalent loose-coupling techniques are
preferred over components importing concrete implementations throughout
the codebase.

## 2.3 Interface Layer

Not part of Version 1 implementation requirements beyond whatever
minimal interface is useful for testing.

Eventually, multiple interfaces may coexist:

-   Web application
-   Mobile application
-   Desktop GUI
-   REST or similar API
-   CLI
-   AI/agent interface

All interfaces must invoke the same domain layer rather than
implementing their own business rules.

------------------------------------------------------------------------

# 3. Core Design Principles

### 3.1 Priority First

Manual priority represents how much the task matters.

Due dates represent urgency, not importance.

A task should not dominate the system merely because somebody assigned
it a date.

Priority should be represented to the user with **both a level and a
descriptive label**, rather than relying on the number alone.

This avoids the ambiguity that although **P1 is the highest priority**,
the number 1 can intuitively feel "lower" than 5.

Initial priority labels:

-   **P1 --- Critical**
-   **P2 --- Important**
-   **P3 --- Normal**
-   **P4 --- Someday**
-   **P5 --- Maybe**

The descriptive label should be prominent anywhere the user is choosing
or reviewing priority.

### 3.2 Due Dates Are Optional

Many personal tasks have no meaningful due date.

A task without a due date is completely valid and should participate
normally in ranking.

Due dates should become increasingly influential only as they approach.

### 3.3 Tasks Should Be Actionable

The system should discourage giant tasks that remain on the list
indefinitely.

Large goals should normally become projects.

Tasks should represent work that can reasonably be completed in one
working session.

### 3.4 Capture Should Be Cheap

Users should be able to record an idea immediately without fully
classifying it.

Organization can happen later.

However, unsorted captured items must not remain forgotten indefinitely.

### 3.5 Ranking Must Be Explainable

Version 1 ranking should be deterministic.

For a given database state and query context, the same input should
produce the same ranking.

The system should eventually be capable of explaining why a task ranked
where it did.

Examples:

-   Critical priority
-   Due tomorrow
-   Has been neglected for several weeks
-   Fits the available 30-minute window
-   Higher-ranked tasks from the same project were suppressed by
    diversification

------------------------------------------------------------------------

# 4. Task Model

A task should contain at least the following concepts.

## Required / Core Fields

### ID

Unique task identifier.

### Title

Short description of the work.

### Project

Tasks may belong to a project. Standalone tasks are permitted both in the
inbox and on-deck.

### Status

Suggested states include:

-   Inbox
-   On Deck
-   Needs Scoping
-   Completed

Dependency blocking is a derived condition, not a stored lifecycle status.
It results from incomplete task dependencies. External blocking is recorded
separately as a fully manual boolean.

On-deck membership is the query of unfinished tasks with an assigned priority
and known duration. Project membership is optional; there is no separately
chosen membership flag or move-on-deck action. Keep `on_deck_since` to track
time on-deck for possible future ranking. Ordinary qualifying edits preserve
that timestamp. Clearing a requirement returns the task to the inbox and
clears its age; restoring requirements qualifies it automatically and starts
a new age at the actual operation time.

“Hidden” was a wording mistake: awaiting external dependencies uses the
existing fully manual `externally_blocked` flag, not a separate hiding feature.
Organized waiting tasks remain in the on-deck pool, clearly marked; blocking
and organization are separate concerns. The earlier explicit-move policy is
superseded. Existing qualifying Inbox snapshots are normalized atomically at
startup before the server becomes healthy; GETs do not mutate task state.

Additional internal states may be introduced if justified.

Do not introduce complicated workflow states without a clear
requirement.

### Priority

Five manually assigned levels:

-   **P1 --- Critical**
-   **P2 --- Important**
-   **P3 --- Normal**
-   **P4 --- Someday**
-   **P5 --- Maybe**

P1 is highest priority.

Priority represents **importance**, not urgency.

The descriptive labels are part of the user-facing model and should
normally be shown alongside or instead of the numeric code.

The numeric code is still useful internally because it provides a stable
ordered identifier, but users should not be expected to remember that
"1" means higher priority than "5."

The exact numeric weights used internally are configurable and
intentionally unspecified at this stage.

### Duration

Use fixed duration buckets rather than arbitrary estimates.

Initial buckets:

-   5 minutes
-   15 minutes
-   30 minutes
-   1 hour
-   2 hours
-   4 hours

An additional state should represent:

-   Unknown / Unscoped

Unknown duration is meaningful. Items with unknown duration should appear
in the inbox for further user clarification or specification. They are
excluded from actionable recommendations, whether or not available time
is specified.

Tasks larger than approximately four hours should normally be broken
into smaller tasks.

### Due Date

Optional calendar date, with no time-of-day. The agreed first ranking change
adds a date-only Due date field to the task editor, backed by persisted task
metadata and the API. Leaving it blank or clearing it is valid. Interpret the
date against the viewing device's current local calendar date for ranking.

Undated tasks participate normally; within the same ranking level, dated tasks
precede undated tasks under the agreed ordering rule.

### Created Timestamp

Used for history and inbox review age.

### On-Deck Timestamp

Record `on_deck_since` when the task moves on-deck. Task age bonuses and
staleness calculations use this timestamp, not creation or the last update.
Ordinary edits do not reset it.

### Updated Timestamp

Track meaningful task changes.

### Completed Timestamp

Set when completed.

Completed work should remain available historically.

------------------------------------------------------------------------

# 5. Task Size and Scoping

Tasks should normally represent work taking no more than approximately
four hours.

If something is:

-   Too vague to estimate
-   Clearly larger than four hours
-   More appropriately considered a goal

...it should not appear in the normal actionable ranking.

Instead, it should be marked as needing scoping or breakdown.

Example:

> Build a treehouse

This should probably begin as a captured idea, project seed, or
oversized item rather than an ordinary ranked task.

Later it might become a project containing tasks such as:

-   Choose location
-   Measure trees
-   Sketch platform
-   Create material list
-   Purchase lumber
-   Build platform

Version 1 does not require true nested subtasks.

A strong initial rule is:

**Projects can be large. Tasks should be small enough to finish.**

------------------------------------------------------------------------

# 6. Inbox / Cheap Capture

The system should provide an inbox for low-friction capture.

An inbox item may initially contain little more than:

-   Title
-   Created timestamp

Additional fields may be absent.

Inbox items should not be required to participate in normal task
ranking.

The system should identify inbox items that have remained unsorted
beyond a configurable period.

Example default:

**3 days**

The system should then surface a review condition such as:

> 6 inbox items have been waiting for more than 3 days.

The system should not silently auto-classify or delete these items.

The goal is to encourage deliberate sorting.

------------------------------------------------------------------------

# 7. Blocking and Dependencies

A task may be dependency-blocked. This is derived from incomplete task
dependencies, rather than stored as a separate lifecycle status. Completing
a prerequisite removes its blocking effect; other incomplete prerequisites
still apply.

Blocking may result from:

### Another Task

Example:

> Paint wall

blocked by:

> Repair drywall

This should use an explicit task dependency relationship.

Support both single-task and bulk dependency-blocking checks against current
saved state. A task is dependency-blocked when any direct prerequisite is not
completed. Do not store a separate dependency-blocking flag. A bulk check for
a 100-task view should use 1 database query rather than fetch prerequisites
individually. These checks report dependency state, not overall task eligibility.

### External Condition

A task may also be blocked by something outside the application.

Examples:

-   Waiting for a shipment
-   Waiting for another person
-   Waiting for weather
-   Waiting for a contractor

External blocking is limited to a fully manual `externally_blocked` boolean
on each task, defaulting to false. It has no effect on ranking. No reason
text or automatic updates are required.

Dependency-blocked tasks should not appear as ordinary actionable recommendations.

------------------------------------------------------------------------

# 8. Completion and Deletion

Completion and deletion are distinct concepts.

## Completion

Completed tasks should remain in the database indefinitely unless a
future retention policy is deliberately added.

Completion should record a completion timestamp.

Historical completion information may later support:

-   Project history
-   Recurring tasks
-   Analytics
-   Personal activity history

Completed tasks should simply be excluded from normal active views.

## Hard Delete

A user must be able to permanently delete a task.

Typical reasons:

-   Accidental duplicate
-   Erroneous capture
-   Junk entry

Hard deletion should be intentional and distinct from completion.

------------------------------------------------------------------------

# 9. Recurring Tasks

Recurring tasks are required.

The system must avoid accumulating duplicate missed instances.

There should generally be only **one active instance** of a recurring
task.

Two recurrence modes should be supported.

## 9.1 Completion-Based Recurrence

The next occurrence is calculated from when the previous occurrence is
completed.

Example:

> Clean tractor air filter every 14 days

If completed five days late, the next occurrence should be scheduled 14
days after the actual completion.

This recurrence therefore drifts.

## 9.2 Calendar-Based Recurrence

The recurrence remains attached to a calendar rhythm.

Examples:

-   Every Monday
-   First day of each month
-   Every Saturday

Completing the task early or late does not permanently move the cadence.

The next occurrence is eligible for recommendations immediately, even
when its due date is in the future. The due date influences ranking; it
does not act as a "not before" date or an eligibility gate. A future
occurrence may therefore be recommended early.

## 9.3 Missed Occurrences

Missed recurring tasks must **not pile up**.

If a weekly task is ignored for three weeks, the user should not receive
three or four copies.

The existing task remains actionable until completed or otherwise
handled.

------------------------------------------------------------------------

# 10. Context Model

Context should help determine whether a task is currently appropriate.

Do not initially rely on one large collection of uncontrolled tags for
core ranking behavior.

Use structured context dimensions for fields the ranking/filtering
system actually understands.

## 10.1 Location

Initial candidate values:

-   Inside
-   Outside
-   Garage / Workshop
-   Away / Errand
-   Anywhere

These values are provisional and should be easy to change.

## 10.2 Resource / Mode

Initial candidate values might include:

-   Computer
-   Phone
-   Tools
-   Driving
-   None / unrestricted

The model should allow future expansion.

## 10.3 Free-Form Tags

Optional free-form tags may also exist.

In Version 1, they should primarily support organization and search.

They should **not automatically influence ranking** unless a future rule
explicitly gives them meaning.

This avoids uncontrolled tag semantics affecting core behavior.

------------------------------------------------------------------------

# 11. Project Model

Projects are containers for related tasks.

A project should initially contain:

### ID

Unique identifier.

### Name

Required.

### Description

Optional.

### Status

At minimum:

-   Active
-   Completed

Other states should only be added when justified.

### Priority

Projects may optionally have a priority.

If the same five-level priority model is reused for projects, the same
user-facing labels should be used:

-   P1 --- Critical
-   P2 --- Important
-   P3 --- Normal
-   P4 --- Someday
-   P5 --- Maybe

Initial concept:

Project priority may provide a **small secondary ranking influence** to
tasks contained within it.

Project priority should not overpower explicit task priority.

Exact behavior remains tunable.

### Created Timestamp

### Updated Timestamp

### Completed Timestamp

Optional until completed.

------------------------------------------------------------------------

# 12. Project Completion

Project completion should be explicit, but the system should assist the
user.

If all actionable tasks inside a project are completed, the system
should flag the project for review.

Example:

> All tasks in "Build Beehive" are complete. Mark the project complete?

Do not automatically assume that a project is finished merely because
the currently recorded tasks are done.

The user may still need to add another task.

The exact review condition remains undecided, including whether blocked,
inbox, or unscoped work should prevent a completion-review flag. Resolve
this when implementing project-completion behavior.

------------------------------------------------------------------------

# 13. Global Ranking vs Project View

The application has two fundamentally different task-viewing modes.

## Current Heap ranking scope

Agreed first implementation: show the full organized Heap in ranked order,
without project caps, diversification, or a smaller recommendation shortlist.
Do not hide tasks merely because their project already has higher-ranked tasks.
The recommendation and project-diversification design below remains future work,
not part of this first ranking change. Tasks awaiting external dependencies
remain visible and use the same ranking rules; retain their existing badge.
The manual waiting flag must not hide or demote them.

## Global Ranked View

Purpose:

**"What should I work on next?"**

The global list should intentionally diversify results across projects.

A single project containing many eligible tasks should not flood the
ranked list.

Example:

If a project has six eligible tasks, the global ranked view may
initially show only one or two.

The exact cap should be configurable.

Importantly:

**Project diversification should affect presentation of ranked results,
not the underlying task score.**

## Project Detail View

When intentionally viewing a project, show all appropriate tasks for
that project.

No project diversification cap is needed.

This view answers:

**"What needs to happen for this project?"**

------------------------------------------------------------------------

# 14. Ranking Pipeline

The agreed first Heap ranking uses ordered groups and date/age tie-breakers,
not numeric weights or additive age bonuses. Implementation tasks and approved
HTTP/UI details are in `docs/heap-ranking-plan.md`; implementation is in progress.
This agreement supersedes conflicting provisional score/curve suggestions below
for the current full-Heap view. Future recommendation policies remain separate.

Ranking should be deterministic.

Avoid treating ranking as a single arbitrary weighted sum if a clearer
staged process is available.

A useful conceptual pipeline is:

## Stage 1 --- Eligibility

Remove tasks that cannot currently be acted upon.

Examples:

-   Completed
-   Blocked
-   Inbox / unclassified
-   Needs scoping
-   Unknown duration (surfaced in the inbox for clarification)
-   Oversized task
-   Context mismatch
-   Duration exceeds available time

## Stage 2 --- Base Ranking

Rank eligible tasks using factors such as:

1.  Manual task priority
2.  Due-date urgency
3.  Age / staleness
4.  Small project-priority influence

## Stage 3 --- Diversification

Apply project caps or similar rules so one project does not dominate the
global list.

------------------------------------------------------------------------

# 15. Priority Behavior

Priority is the normal foundation of the ranking system.

The five levels are:

  -----------------------------------------------------------------------
  Code                    Label                   Meaning
  ----------------------- ----------------------- -----------------------
  P1                      Critical                Among the most
                                                  important things
                                                  currently in the system

  P2                      Important               Clearly important and
                                                  should receive
                                                  meaningful attention

  P3                      Normal                  Ordinary worthwhile
                                                  work

  P4                      Someday                 Worth keeping, but not
                                                  presently important

  P5                      Maybe                   Low-commitment idea or
                                                  task that may never
                                                  need to happen
  -----------------------------------------------------------------------

The labels should carry most of the user-facing meaning.

The P1--P5 codes provide compact identifiers and ordering but should not
be relied upon by themselves where doing so would create ambiguity.

P1 through P5 should represent meaningful differences.

The internal numeric spacing does not have to be linear.

For example, the eventual implementation might decide that the jump from
Important to Critical matters more than the jump from Maybe to Someday.

The exact curve is intentionally left tunable.

The user-facing model remains these five stable priority categories.

------------------------------------------------------------------------

# 16. Due-Date Behavior

Due dates should provide a **nonlinear urgency boost**.

A distant due date should have little effect.

As the due date becomes genuinely close, its impact should increase
substantially.

Conceptually:

-   Due in several months: almost no influence
-   Due in several weeks: minor influence
-   Due soon: increasing influence
-   Due tomorrow: strong influence
-   Overdue: potentially very strong influence

This should allow a lower-priority task with a genuinely imminent
deadline to outrank a higher-priority task without a deadline.

Agreed ranking example: a P3 task due tomorrow outranks an undated P2 task.
Priority is therefore not a strict grouping that urgency can never cross.
Due-date urgency may cross at most 1 priority level, except that P1 Critical
is protected: P1 tasks always rank ahead of lower-priority tasks. A P3 task
due tomorrow outranks an undated P2, but not P1; even P2 due tomorrow cannot
outrank P1. Ranking does not change the task's saved priority.

The agreed upcoming-deadline promotion window is 2 calendar dates: today or
tomorrow, not a rolling 48-hour window. Dates after tomorrow do not earn the
1-level promotion. Overdue tasks retain the same 1-level promotion until
completed or rescheduled; becoming further overdue adds no extra promotion.
P1 remains protected. Interpret today and tomorrow in Barrett's local
timezone, not the server's timezone. Use the viewing device's current timezone,
following timezone changes when traveling rather than fixing a home timezone.

Within the same ranking level, sort earliest due date first, placing undated
tasks after dated tasks, then oldest-on-Heap first. P1 remains ahead of every
lower-priority task. The final deterministic tie-breaker remains to be settled.

However, distant dates must not dominate manual priority.

This is intentionally designed to avoid reproducing conventional
"everything is sorted by date" task managers.

Exact timing thresholds and score curves are tunable.

------------------------------------------------------------------------

# 17. Age / Staleness Behavior

Age should matter, but only as a bounded anti-staleness mechanism.

Measure task age and staleness from `on_deck_since`, not creation or the last
meaningful update.

An older task should gradually receive more visibility.

Agreed limit: age may reorder tasks within the same priority level, but must
not lift a task across priority levels. An old P3 does not outrank a new,
undated P2 merely because of age. Age must not compound a due-date promotion
into crossing additional levels.

However:

**Age must never increase without limit.**

A forgotten Maybe task should not inevitably become the most important
task in the system merely because it is old.

Suggested conceptual behavior:

-   New task: no age bonus
-   Moderately old: small boost
-   Older: somewhat larger boost
-   Beyond threshold: boost reaches a cap

After a separate staleness threshold, the task should be flagged for
review rather than receiving additional ranking power.

Example review prompt:

> This task has been on-deck for 45 days. Is it still important, does it
> need to be broken down, or should it be removed?

The exact age curve and review threshold are tunable.

------------------------------------------------------------------------

# 18. Duration Behavior

Duration primarily acts as an **eligibility / fit filter**, not an
importance score.

Example query:

> I have 30 minutes.

Tasks estimated at:

-   5 minutes
-   15 minutes
-   30 minutes

may qualify.

Tasks estimated at:

-   1 hour
-   2 hours
-   4 hours

should normally be excluded.

A shorter task should not automatically outrank another task simply
because it is shorter.

Duration answers:

**"Can I reasonably do this now?"**

not:

**"How important is this?"**

------------------------------------------------------------------------

# 19. Ranking Explainability

The ranking implementation should expose enough information to explain
results.

An internal ranking result should ideally contain something analogous
to:

-   Base priority contribution
-   Due-date contribution
-   Age contribution
-   Project contribution
-   Eligibility decisions
-   Diversification decisions

The exact API is up to the implementation.

This capability is important because ranking rules are expected to
evolve.

A developer or user should be able to answer:

> Why is task A above task B?

without reverse-engineering hidden logic.

Where possible, explanations should use descriptive priority labels
rather than only numeric codes.

For example:

> Ranked highly because it is Critical priority and due tomorrow.

is preferable to:

> Ranked highly because it is P1.

------------------------------------------------------------------------

# 20. AI / LLM Ranking

AI-assisted ranking is explicitly postponed.

Version 1 ranking should remain deterministic.

The architecture should not prevent a future layer where an LLM:

-   Reviews the deterministic top N tasks
-   Suggests a reorder
-   Identifies tasks that need breakdown
-   Interprets natural-language context
-   Explains unusual recommendations

If added later, deterministic ranking should remain available as the
stable baseline.

------------------------------------------------------------------------

# 21. Tunable / Provisional Values

The following decisions should be treated as configuration or
replaceable policy rather than hard-coded assumptions wherever
practical:

-   Exact numeric weights behind the five priority levels
-   Due-date urgency curve
-   Age bonus curve
-   Staleness review threshold
-   Inbox review age
-   Project priority influence
-   Maximum tasks shown per project in global results
-   Context values
-   Maximum recommended task duration
-   Recurrence details beyond the two basic modes

The five priority labels are initially:

-   Critical
-   Important
-   Normal
-   Someday
-   Maybe

These labels may also be treated as configuration if doing so is
inexpensive, but the implementation should maintain a stable ordered
five-level priority model.

The implementation should make experimentation with ranking values
straightforward.

------------------------------------------------------------------------

# 22. Explicit Non-Goals for Version 1

Do not spend significant effort yet on:

-   Polished graphical UI
-   Mobile application
-   AI ranking
-   Calendar synchronization
-   Email integration
-   Notifications
-   Multi-user support
-   Collaboration
-   Team assignments
-   Complex permissions
-   Time tracking
-   Gamification
-   Productivity analytics
-   Natural-language task entry
-   Automatic task classification
-   Nested subtasks
-   Complex database triggers
-   Enterprise-scale concurrency

The goal is a clean, testable core.

------------------------------------------------------------------------

# 23. Suggested Initial Deliverable

The first coding pass should produce:

1.  Domain classes/models for projects and tasks.
2.  A persistence abstraction.
3.  A SQLite implementation of that abstraction.
4.  CRUD operations routed through the domain/service layer.
5.  Task lifecycle behavior.
6.  Dependency/blocking logic.
7.  Recurrence logic.
8.  Eligibility filtering.
9.  Deterministic ranking.
10. Project diversification.
11. Inbox/staleness detection.
12. Unit tests for each major business rule.
13. A simple CLI, script, or test harness sufficient to exercise the
    system.

Before implementing a larger UI, the developer should be able to create
realistic test data and ask something equivalent to:

> Give me the five best tasks I can work on right now, with 30 minutes
> available, while staying inside.

The returned results should be deterministic and explainable.

------------------------------------------------------------------------

# 24. Implementation Guidance for the Coding Agent

Before writing significant code, propose:

-   Domain model
-   Module/package boundaries
-   Persistence abstraction
-   SQLite schema
-   Ranking architecture
-   Recurrence representation
-   Dependency representation
-   Testing strategy

Prefer the simplest implementation that satisfies the current
specification.

Do not add speculative abstractions merely because they might someday be
useful.

At the same time, avoid tightly coupling components where the
specification explicitly anticipates experimentation or replacement.

When an ambiguity exists, favor:

1.  Simple behavior
2.  Explicit behavior
3.  Testable behavior
4.  Replaceable behavior

Document assumptions rather than silently expanding scope.
