# Project guidance

- Build this together with Barrett, one agreed step at a time. Do not autonomously implement the roadmap.
- Track progress in `TASKS.md`; check off work only after verification. The original requirements are in `personal_task_project_manager_v1_spec.md`.
- Resolve design questions as they arise. Keep changes small and test business behavior.
- Update this file as we establish architecture and working conventions. Keep it minimal.

## Domain decisions

- Blocking is derived from incomplete dependencies and external blocking reasons.
- Future recurring instances are eligible immediately; due dates affect ranking, not eligibility.
- Staleness starts at activation.
- Unknown-duration items belong in the inbox for clarification, not actionable recommendations.
- Project-completion review rules remain undecided.
