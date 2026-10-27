# ADR 001: rules from the Zig review guides

Status: Accepted, 2026-10-21.

## Context

The user's Zig review guides (`clanker/docs/prompts/`, `modelfs/docs/review-guides/`, `hordeforge/zdtd-server/docs/prompts/`) hold practices beyond this standard. Seventeen were filtered for MISRA's purpose: behavior that stays defined in every build mode, no hidden failure paths, bounded resources. The user asked to adopt all of them. Every Zig fact below was checked with a probe against Zig 0.17.0 before it was written into the handbook.

## Decision

| Practice | Rule | misra-lint |
|---|---|---|
| No process termination outside `main` | Rule 21.8 | `terminate_outside_main` |
| `.?` and `orelse unreachable` on a lookup | Dir 4.1 | `orelse_unreachable`, `unwrap_assumed` |
| `AssumeCapacity` only after a reserve | Dir 4.1 | `assume_capacity`; a short reserve is left to a reader |
| Float to integer after a range check | Rule 10.3 | `float_to_int` |
| Outside lengths capped, no `.unlimited` | Dir 4.14 | `unlimited_limit` |
| Growth driven by input has a named cap | Dir 4.14 | reader |
| Threads start once, a fixed number, joined | Dir 5.3 (new group 7) | `thread_in_loop`, `thread_outside_main`, `thread_detached` |
| Shared data locked or atomic | Dir 5.1 (new group 7) | reader |
| `std.posix` wrappers that map an errno to `unreachable` | Dir 4.1 | `posix_assumes_errno`, from a list generated out of the installed std |
| One `std.Io` per process, built in `main` | Dir 4.12 | `io_outside_main` |
| An update to two structures is all or nothing | Dir 4.1 | reader |
| C declarations come from the translated header | Rule 8.4 | `handwritten_extern` |
| Not-found is `?T` or an error, not an in-band value | Dir 4.7 | `sentinel_return` |
| No deprecated std declarations | Rule 1.5 | `deprecated_api`, from the generated list |
| Reinterpret with `@bitCast`, not a pointer cast | Rule 11.3 | `ptrcast_reinterpret` |
| The build keeps safety on | Dir 4.1 | `build_unsafe_mode` |
| Every file reachable from the test root | Rule 2.1 | `misra-lint --root` (`unreachable_file`) |

Two choices were made for the user where a guide left a question open:

- The posix practice in the guides also asks for all OS calls in one wrapper module. That part is not adopted: a module name differs per project, and the errno hazard is checked directly.
- `std.Thread.spawn` outside `main` is `review`, not a violation, because a pool started once from an init function is the intended pattern.

## Consequences

- The standard has seven groups: Concurrency is new.
- `tools/std_lists.zig` must be regenerated (`bun scripts/gen_std_lists.ts`) when Zig changes; `bun test scripts/` fails while it is stale.
- These guide habits still conflict with this standard. They live in other repositories and were not edited:
  - the guides count on the `@trunc` / `@intFromFloat` trap, which ReleaseFast deletes and which a 0.17.0 Debug run did not fire for NaN;
  - the guides allow `catch {}` with a comment;
  - modelfs recommends `+|` for hostile sizes;
  - clanker spawns one thread per tool batch.
