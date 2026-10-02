# Heap project guidance

- Build this together with Barrett, one agreed step at a time. Do not autonomously implement the roadmap.
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
