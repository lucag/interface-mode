## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues on `lucag/interface-mode`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Working on the code

- **Coding standards**: read `CODING_STANDARDS.md` before writing a test, a signal handler or a commit message, and before reviewing a diff.
- **Linux tests from any host**: `make test-linux` runs the suite in Docker (`tests/Dockerfile`). Docker Desktop must be running; on macOS, `open -a Docker` starts it.
