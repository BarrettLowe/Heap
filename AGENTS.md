# Heap project guidance

- Build this together with Barrett, one agreed step at a time; do not autonomously implement the roadmap.
- The UI is Flutter/Material 3, Android-first, with web support kept viable. Test on both a physical phone and an emulator.
- Treat Barrett's supplied UI image as the primary visual target. Keep behavior grounded in the requirements; don't invent task metadata or fake navigation.
- Barrett hosts the backend at `heap.lowehomeautomation.xyz`; Android beta builds use `http://heap.lowehomeautomation.xyz` on the trusted private network; Barrett manages Caddy.
- Heap runs on a server reached through VPN/Tailscale. Use Docker Compose and keep SQLite in its persistent volume. The API has no authentication, so keep it on a trusted private network; run only one writer against its SQLite database. Hosted cloud versus self-hosting remains undecided. See `docs/backend.md` for deployment details.
- For UI work, use Designer for design/review, Frontend for Flutter, and Backend for API changes. Plan first, keep implementation paths separate, and have the coordinator own shared documents and coordinate independent code review.
- Track progress in `TASKS.md`; requirements are in `personal_task_project_manager_v1_spec.md`. Check off work only after verification.
- This is a personal project: prefer the simplest change that delivers the agreed behavior.
- Deleting a project permanently deletes every task assigned to it.
- Heap is live. Preserve existing production data; production databases are not disposable. Database/schema changes require a safe upgrade path and verification on a backup. Consider compatibility with already-installed clients when changing the API; do not assume backend and app updates happen together.
