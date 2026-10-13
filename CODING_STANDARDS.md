# Coding standards

Rules this repo holds code and commits to, beyond what the compiler and the tests already enforce. `/code-review` checks a diff against them.

## Backends

- **Shared behaviour lives once.** When a second backend needs something the first already does, move it into a file every platform builds (like `cli.c` or `stop.c`) instead of copying it. This is ADR 0002's "the contract lives once", applied below the contract too.

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

Under ARC, anything that must outlive setup (a dispatch source, an observer) is held in a strong reference for as long as the Watcher runs. A local variable is released when its scope ends, which silently cancels a dispatch source.

## Commits

- **Name the issue.** A commit message says which issue it serves (`Refs #4`, `Closes #6`). That is how `/code-review` finds the spec for a diff.
- **Say what ran.** A commit message names the suites run before committing, with their results (`make test-linux 26/26; make test on macOS 11/11`). A reviewer can't verify a run nobody recorded.

## Decisions

- **An accepted ADR changes only with the maintainer's sign-off.** When the code needs a decision to read differently, propose the new wording, show it, and wait for a yes before editing `docs/adr/`.
