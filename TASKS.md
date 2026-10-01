# V1 implementation tasks

Work through these together, one small change at a time. The order is a starting point; adjust it as we learn. Check off tasks after verification, not just implementation.

The original spec is in `personal_task_project_manager_v1_spec.md`. Decisions made since that draft:

- Blocking is derived from incomplete dependencies and external blocking reasons.
- A recurring task's next instance is eligible immediately. Its due date affects ranking, not eligibility.
- Staleness is measured from activation.
- Unknown-duration items go to the inbox for clarification and stay out of actionable recommendations.
- Project-completion review rules are deferred until step 14.

For coding tasks: agree on the immediate behavior, write a failing test, implement the smallest change, then review together. Names and package boundaries below are responsibilities to design, not a prescribed class hierarchy.

## 1. Spec cleanup (optional; likely skipped)

- [ ] Fold the decisions above into the original spec.
- [ ] Record unresolved questions without deciding them prematurely.

Verification: the spec matches our current decisions. This is not a prerequisite for coding.

## 2. Architecture boundaries

- [ ] Agree on the division between domain models, application services, persistence, and ranking policies.
- [ ] Sketch package boundaries and the persistence interface for the first slice.
- [ ] Decide how to supply time explicitly in tests.
- [ ] Trace capture and recommendation requests through the proposed components.

Verification: we can explain which component owns each responsibility without designing every future class.

## 3. Python project and test setup

- [ ] Choose dependency management and test tooling.
- [ ] Create the initial package and test layout.
- [ ] Add a smoke test and document the test command.

Verification: one command runs the tests successfully.

## 4. Capture service and SQLite round trip

- [ ] Define the minimum inbox task model: identifier, title, and timestamps.
- [ ] Add the persistence operations needed to save and retrieve it.
- [ ] Implement those operations in SQLite.
- [ ] Route title-only capture through the application service.
- [ ] Test retrieval after closing and reopening the database.

Verification: a captured inbox item survives a restart. This is the first working end-to-end slice.

## 5. Project model and task activation

- [ ] Add project creation and retrieval through the service and persistence layers.
- [ ] Define priority levels and their descriptive labels.
- [ ] Define duration buckets.
- [ ] Agree on activation requirements, including whether active tasks require a project.
- [ ] Add task organization and activation, recording activation time.
- [ ] Keep unknown-duration items in the inbox for clarification.

Verification: a captured item can become a scoped, active task associated with a project; an unknown-duration item cannot enter actionable recommendations.

## 6. Lifecycle services

- [ ] Add task and project editing.
- [ ] Define meaningful changes for updated timestamps.
- [ ] Add task completion with a completion timestamp and retained history.
- [ ] Add intentional task hard deletion.

Verification: lifecycle tests check state and timestamps, including SQLite round trips.

## 7. Dependency model and derived blocking

- [ ] Represent task dependencies and external blocking reasons.
- [ ] Derive blocking from unresolved prerequisites and external reasons.
- [ ] Reject self-dependencies and cycles.
- [ ] Decide what happens when a prerequisite is deleted.

Verification: completing a prerequisite removes its blocking effect; other blockers still apply.

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
- [ ] Add a bounded age contribution measured from activation.
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
- [ ] Flag active tasks beyond the configurable staleness threshold.
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

- [ ] Add a minimal script or CLI that calls the same application services.
- [ ] Create realistic sample data.
- [ ] Request the five best tasks given available time and context.
- [ ] Verify explanations, diversification, recurrence history, and persistence together.

Verification: the spec's "five best tasks, 30 minutes, inside" example works reproducibly without adding business rules to the interface.
