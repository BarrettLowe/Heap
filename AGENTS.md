# Heap project guidance

- Build this together with Barrett, one agreed step at a time. Do not autonomously implement the roadmap.
- Heap is intended for server-side execution with remote access through VPN/Tailscale. Python was chosen with cloud execution in mind, but hosted cloud versus self-hosting is not yet decided. Current local SQLite storage is not a decision to run only on Barrett's workstation.
- Track progress in `TASKS.md`; check off work only after verification. The original requirements are in `personal_task_project_manager_v1_spec.md`.
- Resolve design questions as they arise. Keep changes small and test business behavior.
- Update this file as we establish architecture and working conventions. Keep it minimal.
- Use `logic/`, `persistence/`, and eventually an interface layer. Name files for their contents (for example, `task.py`, `task_operator.py`, `task_store.py`). Avoid “models”; reserve “service” for background services.
- Task dataclasses are in-memory snapshots, not database-connected objects. Field changes do not automatically persist.
- Use “on-deck” for organized tasks (`ON_DECK`, `move_to_on_deck`, `on_deck_since`). Priority and known duration are required to move on-deck; projects are optional. On-deck does not imply unblocked or started. Clearing priority or duration returns an on-deck task to the inbox and clears its on-deck timestamp; restoring the value does not automatically move it on-deck.
- Use uv and pytest; run tests with `uv run pytest`.
- Production operations read current UTC time once. Tests replace the time source; do not require callers to pass timestamps or inject a clock.
- Use an injected Strategy object for ranking scores and their explanation contributions. It receives data and explicit time, with no database access. Keep eligibility and diversification outside the scoring strategy.
- Route writes through application operations that apply business rules and explicitly save before reporting success. Save related changes in one transaction; test persistence by reloading from storage.
- When you discover something about this project that should be stored in durable memory, save it to AGENTS.md in the project root. Only save things that cannot be easily inferred from the code.
- Store task dependencies in a separate table. Deleting a task removes every dependency link involving it, whether it is the dependent task or a prerequisite; removing a prerequisite may unblock remaining tasks. Batch deletion is all-or-nothing, including link cleanup, if any ID is missing or any deletion fails. Empty batches do nothing; repeated IDs count once.
- Explicit dependency edits update only the dependent task's `updated_at`; unchanged links do not write or read time. Cycle validation currently requires non-overlapping dependency edits.
- External blocking is limited to a fully manual `externally_blocked` boolean, with no ranking influence, reason text, or automatic updates.
- Multi-task views should use bulk dependency checks, not call the single-task check in a loop. Dependency checks report prerequisite state, separate from task eligibility.
