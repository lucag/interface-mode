# Coding standards

Judgement calls this repo holds code to. `/code-review` checks a diff against them. Mechanical rules are checks instead: CI (`.github/workflows/test.yml`) builds with `-Werror` and runs both platforms' tests on every push, and every commit message must name its issue (the `commit-msg` hook from `make hooks`, and CI).

## Backends

- **Shared behaviour lives once.** When a second backend needs something the first already does, move it into a file every platform builds (like `cli.c` or `stop.c`) instead of copying it. This is ADR 0002's "the contract lives once", applied below the contract too.

## Tests

- **Red first.** A test for a bug fix fails on the code before the fix. Run it against the pre-fix code (`git show <before>:<file>`) and say in the commit message that it failed, and how (`fails 10/10 with -15`). A test that has never been seen red proves nothing.
- **Races are forced, not sampled.** A test for a timing bug drives the state the bug needs on every run:
  - hold the process at the risky point (a fake bus that takes the connection and never answers), or
  - cover the whole window (`keep_asking_to_stop()` sends SIGTERM until the process has exited).
  
  A test that sleeps a varying amount, or acts only `if` the process is still in some state, can pass without exercising anything.

## Signals

Stop handling follows [ADR 0003](docs/adr/0003-a-stopped-watcher-always-exits-0.md), in the examples as well as the Watcher.

Under ARC, anything that must outlive setup (a dispatch source, an observer) is held in a strong reference for as long as the Watcher runs. A local variable is released when its scope ends, which silently cancels a dispatch source.
