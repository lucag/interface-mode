# Coding standards

Rules this repo holds code and commits to, beyond what the compiler and the tests already enforce. `/code-review` checks a diff against them.

## Tests

- **Red first.** A test for a bug fix fails on the code before the fix. Run it against the pre-fix code (`git show <before>:<file>`) and say in the commit message that it failed, and how (`fails 10/10 with -15`). A test that has never been seen red proves nothing.
- **Races are forced, not sampled.** A test for a timing bug drives the state the bug needs on every run:
  - hold the process at the risky point (a fake bus that takes the connection and never answers), or
  - cover the whole window (`keep_asking_to_stop()` sends SIGTERM until the process has exited).
  
  A test that sleeps a varying amount, or acts only `if` the process is still in some state, can pass without exercising anything.
- **Every Linux change is checked with `make test-linux`.** It runs the suite in Docker, so it works on any host. Run it before committing.
- **Every macOS change is checked with `make test` on a Mac.** A change to `cli.c`, `stop.c`, either header or `tests/contract.py` touches both platforms, so it gets both runs.

## Signals

Stop handling follows [ADR 0003](docs/adr/0003-a-stopped-watcher-always-exits-0.md): every stop exits 0, early and repeated ones included. Handlers stay installed until the process exits, and they do async-signal-safe work only. This applies to the examples as well as the Watcher.

## Commits

- **Name the issue.** A commit message says which issue it serves (`Refs #4`, `Closes #6`). That is how `/code-review` finds the spec for a diff.
