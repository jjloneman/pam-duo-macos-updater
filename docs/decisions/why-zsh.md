---
type: Decision
title: Why zsh
description: It stays in zsh because root needs a root-owned shell that ships with macOS, a text helper can be reviewed, and runtime speed doesn't matter here.
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-07T03:20:57Z }
---

# Why zsh

The owner chose zsh on 2026-11-06, after comparing TypeScript, Python, Go, Rust and Swift with measurements. This isn't reopened in the current plan.

## Decision

- **Everything stays in zsh:** the main script, the root helper, the tests, lint and coverage.
- **It's `/bin/zsh`:** root-owned and part of macOS, started with `-f`.
- **Zsh's weak tooling is handled in the repo:** a custom lint script and strict rules, in [Zsh scripting rules](../references/zsh-scripting-rules.md).

## Why

All measurements are from one Mac on 2026-11-06, and weren't repeated for this record.

- **Root must run only root-owned code with no user-writable dependencies:**
  - `/bin/zsh` ships with macOS.
  - Node lived in the user-owned `/opt/homebrew`, linking 93 libraries there, which rules it out for root.
  - `/usr/bin/python3` is a shim that honors `DEVELOPER_DIR`, so it depends on a cleaned environment.
  - Go and Rust would need a root-owned toolchain, kept patched, to build as root.
- **Review is what protects root:** `install-helper` shows a text diff. A compiled helper reduces that to comparing checksums of a file built as the user. Reproducible builds don't fix that alone, since a process running as the user can tamper with both builds. See [Why the helper is root-owned](root-owned-helper.md).
- **Runtime speed doesn't matter.** A build took 56 s, 49 s of it compiling, and a daily check took 1.67 s, mostly waiting on the network. The biggest gap between candidates on a sample task was 133 ms a day:

  | Candidate   | Trivial run |   Task | On disk                          |
  | :---------- | ----------: | -----: | :------------------------------- |
  | Go 1.27     |        4 ms |  17 ms | 4.4 MB binary                    |
  | Node 26, TS |      131 ms | 150 ms | 77 MB, plus 19 Homebrew formulae |
  | Python 3.9  |       37 ms | 107 ms | 21 MB, in the Command Line Tools |
  | Rust 1.99   |        3 ms |  29 ms | 536 KB binary                    |
  | Swift 6.4   |        2 ms | 183 ms | 92 KB binary                     |
  | zsh + `jq`  |        4 ms |  34 ms | 2 MB, ships with macOS           |

- **A dead runtime is silent.** A launchd job pointing at a missing interpreter ended with exit 78 and an empty log, and sent nothing. The daily check is what sends alerts, so the runtime it depends on should be the hardest one to break.
- **The serious bugs weren't type errors.** They were about `sudo`, Duo and ordering: cached approvals, a marker written too early, Duo's template failing open. Another language would've prevented only a few smaller ones, such as `grep -q` under `pipe_fail`.
- **A port has a real cost:** the same real install tests, for something that had just passed them and rarely changes.

## Consequences

- **No mature linter or formatter fully supports zsh.** ShellCheck rejects it, the formatter has a known bug, and this repo's lint script fills the gap. See the rules record.
- **Tests stay zero-install:** a harness split up, using only `/bin/zsh`, and a `DEBUG` trap tracer for coverage, which sees less than branch coverage.
- **`sudo`, `otool`, `make` and Duo stay external** in every language, so only a real run can prove them.
- **A Node toolchain still exists for contributors,** only for the formatter and Changesets. The tool never needs it.
- **Tied to `/bin/zsh`:** the error tests must run again before adopting zsh 5.10, which changes `ERR_EXIT` and `ERR_RETURN`.
- **What would change this:** substantial new logic, or frequent changes. The earlier comparison's choice in that case was Go for the main script, keeping the helper in zsh.

## Not verified

- A real Homebrew Node upgrade wasn't simulated, so how often it'd break a job is unmeasured.
- The timings weren't true cold starts, since clearing caches needs root.
- Building a Swift helper as root is untested.
