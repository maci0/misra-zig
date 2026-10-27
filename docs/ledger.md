# Ledger

Append only. A reversal is a new entry.

## 2026-10-20: misra-lint

- What: added `tools/misra_lint.zig`, a `std.zig.Ast` checker with 35 checks plus `parse_error`, a text and `--json` CLI, `--checks`, stdin, and `// misra-lint: allow <check> <reason>`.
- Why: the user asked for deterministic tools that check the rules where possible.
- Evidence: every check maps to a handbook don't; `.scratch/coverage.ts` run on the handbook flagged 32 of 37 compiling don't samples under their own rule, and the 5 others are `UNDECIDED` in `scripts/lint.test.ts` with their reason.
- Decided by: the user (request); check set chosen in this session.
- Verified: `zig test -ODebug` and `-OReleaseSafe tools/misra_lint.zig` (16 tests), `bun test scripts/`, and misra-lint run on `docs/examples/compliant.zig` and on itself, exit 0.

## 2026-10-20: compliant.zig sentinel test

- What: `renderZ`'s test reads the sentinel as `text[z.len]`, inside the caller's buffer, instead of `z[z.len]`.
- Why: misra-lint's `index_at_len` has no types and reports `x[x.len]`; the new form checks what the handbook claims (the sentinel sits inside the buffer passed).
- Evidence: `docs/misra-zig-handbook.md` Rule 21.17, "The sentinel is inside the buffer you passed."
- Verified: `zig test -lc -ODebug` and `-OReleaseSafe docs/examples/compliant.zig`.

## 2026-10-20: server and scripts

- What: `scripts/check.ts` uses `Bun.spawn` instead of `node:child_process`, has one root finder (`projectRoot`), returns compiler `errors` in source lines, and `wrapSource` reports where the source starts. `scripts/server.ts` builds misra-lint at start, adds `GET /checks.json` and `POST /api/lint`, and returns `findings` from `POST /api/check`. The ENOENT text sniff that turned a failure into HTTP 500 is gone; a failed check is `status: "failed"` in the body.
- Why: the site shows lint findings and compiler errors on the editor's lines; two root finders did the same job.
- Verified: `bun test scripts/` (16 tests, including compiler error line mapping and fragment line mapping).

## 2026-10-20: site redesign

- What: replaced the university press world with a component datasheet world: front sheet with features, pin map (one pin per rule) and pin function table; rule sheets with figures, per-don't evidence, and machine checks table; "Evaluate a file" bench; editor gutter with line numbers and finding marks; light and dark printings; keys `/`, `[`, `]`, `Ctrl`+`Enter`; resume flag. Fonts: Archivo (OFL, subset to woff2) and Hack; STIX Two Text, Fira Sans, and Atkinson removed.
- Why: the user asked to make the UI better, chose to replace the visual world, and picked the datasheet direction (seed e7045df5) on the decision page.
- Evidence: direction contract in `.impeccable/surfaces/site-index-html.md`; captures in `.impeccable/review/`.
- Verified: vnu HTML and CSS with zero errors; desktop and mobile captures in light and dark; finish review.

## 2026-10-20: agent skills

- What: `skills/misra-zig-review`, `skills/misra-zig-rule`, `skills/misra-lint-check`; `.claude/skills` links to `skills/`.
- Why: the user asked for agent skills.
- Verified: every command in the skills was run in this session (`zig run ... tools/misra_lint.zig --`, the gate commands).

## 2026-10-20: site finish review

- What: an independent finish review found 7 material issues. All were fixed: a Characteristics block and package inset on rule sheets, the revision date and page marks, the pin hover no longer covering its label, one red in dark, stacked narrow tables, a scrollable mobile pin map, and no colored row stripe. The verdict pass found 3 regressions, which were also fixed. The last caption fix shipped after the two-round review budget without its own verdict. `DESIGN.md` and `.impeccable/design.json` were rewritten from the shipped CSS.
- Why: the redesign workflow ends with a review and a design record.
- Verified: recaptures in `.impeccable/review/`, measured in the browser (no horizontal overflow at 375px; pin label 12px; rule links on one line); vnu HTML and CSS have zero errors.

## 2026-10-20: rules

- What: new Rule 19.2 (no bare `union`; `union(enum)`, or `extern`/`packed union` for a C or register layout), placed in group 2, renamed "Initialization, pointers, and unions". Dir 4.1: `std.debug.assert` and `unreachable` are assumptions, a checked unsigned divide (`perItem`), and don'ts for assert on C input and unchecked `/`. Rule 8.1: a do (`blocksFor`) and a rejected don't (`var n = 0`) about the declaration's type, replacing a narrowing sample that belonged to Rule 10.3. Rule 10.1: unchecked shift amount. Rule 10.3: `@intCast` with no check. Rule 10.5: `std.enums.fromInt` (`decode`) and an `@enumFromInt` don't. Rule 14.4: its own rejected `for (n)` sample. Compiler-rejected list: dropped results, ignored errors, unused locals, shadowing, leading-zero literals. AGENTS.md: the sentence that said one rule's cases "may not share a mark" was false and is corrected.
- Why: the user asked to improve the rules. Each addition is a Zig operation that is illegal behavior in ReleaseFast with no compile error.
- Evidence: probes in `.scratch/facts/`: the compiler rejects `var n = 0`, `for (n)`, a dropped `u32`, an ignored error union, an unused local, shadowing, and `010`; a bare union, `assert` on input, and unchecked unsigned `/` compile; `zig run -ODebug` printed "access of union field 'float' while field 'int' is active" and "division by zero".
- Verified: `zig test -lc` at Debug and ReleaseSafe on `compliant.zig`; `bun scripts/check_samples.ts`; `bun test scripts/`.

## 2026-10-20: misra-lint checks for the new rules

- What: `assert_on_input`, `unchecked_divisor`, `unchecked_intcast`, `unchecked_enum`, `bare_union`. 40 checks plus `parse_error`, naming 33 of 40 rules; 38 of 43 compiling don'ts flagged.
- Verified: failing tests first, then `zig test` at Debug and ReleaseSafe (18 tests); misra-lint on itself and `compliant.zig`, exit 0; field run on 364 files from two other projects, findings sampled and read (see `docs/misra-lint.md`).

## 2026-10-20: skills and review script

- What: `scripts/review.ts` prints a review skeleton from live data (findings by rule, a checklist of every rule). `misra-zig-review` uses it in place of a hand-kept table; new `misra-zig-write` skill with the compliant form for each common task; `misra-zig-rule` and `misra-lint-check` updated with the probe-first rule, count assertions, the helpers, and a field test step.
- Verified: `bun test scripts/` drives `review.ts` as a subprocess and checks its output and exit code.

## 2026-10-20: server fixes

- What: an exception now returns a plain 500 ("Internal error. The server log has the detail.") with `development: false`, instead of the development error page; `buildLint` writes to a unique staging file and renames it into place.
- Why: the development page sent error detail to the browser; a server and a test run building at once executed a half-written binary (ETXTBSY), which started the server with 0 checks and failed the test run.
- Verified: `bun test scripts/` includes two concurrent builds followed by a run; `/handbook.json` returns 200 after restart.

## 2026-10-21: adversarial review, fixes

- What: two independent adversarial reviews, each with the brief in `.scratch/adversarial/brief.md`. Every finding marked confirmed was reproduced again before a fix. Fixed:
  - **Server:** `Host`, `Origin`, and `application/json` are required; the request body is capped at 256 KiB (`maxRequestBodySize`); the source limit counts UTF-8 bytes; one compile runs at a time.
  - **Check:** methods of a top-level container are referenced as `Container.method`, so a valid method is accepted and a broken one is rejected.
  - **misra-lint:**
    - nesting past 256 levels is a `parse_error` instead of a stack overflow;
    - an allow marker counts only inside a comment, and a trailing comment does not reach the next line;
    - `x[x.len]` on a sentinel-typed name is exempt, and the check is now `review`;
    - all-`comptime` functions are exempt from `recursion`;
    - `bitcast_arith` only fires on trapping operators;
    - `unchecked_divisor` needs a comparison with `0`;
    - `@fromBackingInt(@intCast(x))` is one `unchecked_enum` finding;
    - errno after a cleared errno or a `null` test is accepted;
    - `catch |e| { _ = e; }` is `catch_empty`;
    - `catch_empty` no longer cites Rule 22.4;
    - the recursion walk reuses one scratch array, so memory is no longer quadratic;
    - the arena exemption looks at the whole receiver chain;
    - the tool's own switches over std enums carry allow comments, and `pub` is removed where no other file uses it.
  - **Text:**
    - `i32 + u16` compiles;
    - an exhaustive switch with `else` compiles;
    - `std.enums.fromInt` accepts any value of a non-exhaustive enum;
    - an `export fn` cannot return an error union;
    - `divExact` also returns `UnexpectedRemainder`;
    - Rule 8.1 matches its samples;
    - Rule 22.9 covers null returns and errno-only failures such as `strtoul`;
    - Rule 22.4's don't is a real read-only write;
    - `copyBounded` uses `@memmove`;
    - a section lists where a cited MISRA number departs from its MISRA topic (Dir 4.12, Rule 21.3, Rule 9.2, Rule 15.1, Rule 8.8).
  - **Compliant code:** `compliant.zig` drops an unused `pub`.
- Not fixed: no per-compile memory limit (Bun.spawn has no rlimit option); compiler output is read whole before it is clipped; a method on the same line as its `struct {` is not referenced (unformatted code).
- Evidence: reproduced probes in the two reviewers' directories under `.scratch/adversarial/`; `zig run -ODebug` showed `@fromBackingInt` panics with "invalid enum value", and `openFile` with default options returns `NotOpenForWriting` on write.
- Verified: `zig test -ODebug tools/misra_lint.zig` (23 tests, failing first); `bun test scripts/` (24 tests, including `scripts/server.test.ts`, which failed 3 of 5 with the refusal code disabled); `bun scripts/check_samples.ts`.

## 2026-10-21: rules from the Zig review guides

- What: Rule 21.8 (only `main` ends the process), Rule 18.6 (no pointer into a local outlives the call), Dir 4.14 (outside lengths capped, no `.unlimited`), Dir 4.1 (`.?`, `orelse unreachable`, `AssumeCapacity` after a reserve, `@divExact` and the exact shifts), Rule 10.3 (float to integer after a range check). Rule 16.4: on a value from outside, an `else` that returns an error is allowed. Checks: `terminate_outside_main`, `stack_escape`, `unlimited_limit`, `orelse_unreachable`, `unwrap_assumed`, `assume_capacity`, `float_to_int`, `write_read_only`, `enum_else`. Totals: 4 directives and 39 rules; 49 checks plus `parse_error`, naming 36 of 43 rules; 43 of 49 compiling don'ts flagged.
- Why: the user asked what from their Zig review guides fits MISRA's spirit. The candidates still open are in `docs/rfc-001-rules-from-review-guides.md`.
- Evidence: probes in `.scratch/facts/` and `.scratch/facts2/`: `.?` on a missing key panics; `@trunc(5e9)` to `u32` panics and `@trunc(NaN)` gave 0 with no panic in Debug; `initCapacity(1)` then two `appendAssumeCapacity` hits the assert; `ensureUnusedCapacity(1)` then two appends passed silently; the escaped local slice compiled with no check; the langref marks `@intFromFloat` deprecated.
- Verified: `zig test -lc` at Debug on `compliant.zig` (6 tests); misra-lint field run on 364 files, where `unwrap_assumed` and `enum_else` were narrowed after sampling (`docs/misra-lint.md`, Field test).

## 2026-10-21: the remaining limits and the review-guide candidates

- What (server): every check runs under `prlimit --as` (default 4 GiB, `MISRA_ZIG_COMPILE_LIMIT`, validated at start, at least 512M), after one uncapped warm-up that builds libc into the cache; a compile stopped by the cap, or ending in `error: OutOfMemory`, is reported as the limit. Compiler output is read in chunks and no longer kept past the clip limit. Check references functions at any container depth, including a container on one line, through a scanner that skips strings and comments.
- What (rules): all 12 open candidates from RFC 001 are adopted, and the RFC became `docs/adr/001-rules-from-zig-review-guides.md`. New: Dir 4.7, Dir 5.1, Dir 5.3 (new group 7, Concurrency), Rule 1.5, Rule 2.1, Rule 11.3. Extended: Dir 4.1 (posix wrappers, build modes, two-structure updates), Dir 4.12 (`std.Io` is a parameter), Dir 4.14 (growth caps), Rule 8.4 (handwritten `extern fn`). Totals: 7 directives and 42 rules in seven groups.
- What (misra-lint): `tools/std_lists.zig` generated by `scripts/gen_std_lists.ts` from the installed std (205 deprecated declarations, 35 `std.posix` wrappers with an `=> unreachable` errno prong); `deprecated_api` now uses it (Rule 1.5). New checks: `posix_assumes_errno`, `thread_in_loop`, `thread_outside_main`, `thread_detached`, `io_outside_main`, `handwritten_extern`, `sentinel_return`, `build_unsafe_mode`, `ptrcast_reinterpret`, `unreachable_file` (`--root`). `fn build(b: *std.Build)` counts as an entry point. The checker itself moved off deprecated names (`std.mem.indexOf*`, `std.fs.path`). Totals: 59 checks plus `parse_error`, naming 42 of 49 rules; 51 of 58 compiling don'ts flagged.
- Why: the user asked to fix everything still open.
- Not changed: the four places where the user's guides conflict with this standard are in other repositories and were not edited (listed in the ADR).
- Evidence: probes in `.scratch/limit/` (a 512 MiB comptime array stopped within 2 s under a 2 GiB cap with a warm cache; a cold cache needed more than 2 GiB for a trivial file) and `.scratch/facts3/` (thread spawn and join, `std.posix.system.setsockopt` with `std.posix.errno`, `@ptrCast` between value pointers, a local `std.Io.Threaded`); `std/posix.zig` maps `setsockopt`'s `INVAL` to `unreachable`; the langref marks `@intFromFloat` deprecated.
- Verified: `zig test` on `tools/misra_lint.zig` (25 tests) and `compliant.zig` (8 tests); `bun test scripts/` (29 tests, including the memory cap, `--root`, and the std list staleness check, which failed with a line removed); `bun scripts/check_samples.ts`; misra-lint on itself, `tools/std_lists.zig`, and `compliant.zig`, exit 0.

## 2026-10-27: public site on misra-zig.dev and misra-zig.com

- What: the static handbook is published as the Cloudflare Worker `misra-zig` on both domains (custom domains, `wrangler.jsonc`, assets from `build/site`). `scripts/build_site.ts` builds that directory: the site files, `handbook.json`, `rules.json`, `checks.json` (from a fresh misra-lint build), and `api/health` reporting the checker unavailable. `.secrets` (mode 600, gitignored) holds `CLOUDFLARE_ACCOUNT_ID`. `build/` and `.secrets` were added to `.gitignore`. README and AGENTS.md describe the published copy.
- Why: the user registered both domains in Cloudflare and asked for them to be set up with wrangler. The checker stays local: `PRODUCT.md` says it is not a public compile service.
- Evidence: `wrangler deploy` printed both custom domains; the Worker's domain list shows `misra-zig.dev` and `misra-zig.com` enabled with certificates; `curl` returned 200 for `/`, `/handbook.json`, `/rules.json` (49 rules), `/checks.json`, `/api/health`, and the font on both domains; `POST /api/check` returned 404 on both.
- Not done: "Always Use HTTPS" is not enabled. The OAuth login reads zones but cannot change zone settings (`PATCH /zones/{id}/settings/always_use_https` returned an authentication error), so plain `http://` is served without redirecting. Enable it in the dashboard under SSL/TLS, Edge Certificates, for both zones.
- Note: `misra-zig.com` had no nameserver delegation for about seven minutes after registration (registered 04:03 UTC, delegated 04:15 UTC). It needed no action.

## 2026-10-27: MISRA C:2025

- What (rules): ids are MISRA C:2025 numbers. New: Dir 4.11 (std preconditions), Dir 4.15 (NaN and infinity, no `@setFloatMode(.optimized)`), Dir 5.2 (lock order, no second lock of a held mutex), Rule 8.14 (no `noalias`), Rule 11.8 (no `@constCast` or `@volatileCast`), Rule 17.1 (no variadic definitions), Rule 18.4 (no `+` or `-` on many-item pointers), Rule 19.1 (no overlapping `@memcpy`), Rule 19.3 (a `union(enum)` payload through a `switch` capture), Rule 21.25 (`.seq_cst` atomics). Dir 5.3 says each thread is joined once. The compiler-rejected lists in AGENTS.md and the handbook gained the C:2025 hazards Zig refuses. Group 7 is renamed "Threads, locks, and atomics": the first word labels its pin-map bracket, and "CONCURRENCY" overflowed four pins into the next label. Totals: 10 directives and 49 rules in seven groups.
- What (docs): `docs/misra-c-2025.md` places all 223 guidelines (59 adopted, 23 covered, 30 rejected, 81 without a counterpart, 27 left out, 1 process, 2 not assessed). `docs/adr/002-misra-c-2025.md` records the decision. README, `docs/misra-lint.md`, the site description, and the write, review, and rule skills follow.
- What (misra-lint): new checks `float_mode_optimized`, `noalias_param`, `const_cast`, `c_variadic`, `pointer_arith`, `memcpy_alias` (review), `atomic_order`, `lock_twice`. Totals: 67 checks plus `parse_error`, naming 50 of 59 rules; 59 of 71 compiling don'ts flagged, 12 in `UNDECIDED`.
- What (repo): `.wrangler/`, wrangler's local cache, added to `.gitignore`.
- Why: the user asked what in MISRA C:2025 applies to Zig, and to run the unslop and humanizer prose passes.
- Evidence: the guideline list from the Perforce QAC C:2025 enforcement document; probes in `.scratch/c2025/` (`rej/`, `comp/`, `run/`, `more/`). Debug and ReleaseFast runs: `log2_int(0)` and `orderedRemove` past the end panicked in Debug and crashed in ReleaseFast; a broken `noalias` gave 4 in Debug and 3 in ReleaseSafe and ReleaseFast; a `@constCast` write to a constant was lost in all three modes; `@cVaArg` with the wrong type returned 0 in Debug and ReleaseSafe; `(p + 6)[0]` read memory past an array in Debug; overlapping `@memcpy` panicked in Debug; the inactive `union(enum)` field panicked in Debug and was read as raw bits in ReleaseFast; a relocked `std.Io.Mutex` hung in Debug and ReleaseFast; a second `join` segfaulted in both. `@setFloatMode(.optimized)` division by zero panicked in Debug. The 0.17.0 language reference (shipped in `~/.zvm/0.17.0/doc/langref.html`) defines `.optimized` results over NaN and infinity as undefined and requires `@memcpy` regions not to overlap.
- Prose: unslop 2.3.0 (`banned_phrase_scan.py`, `structure_scan.py`, revision 17ed39c) and the humanizer 3.1.0 patterns over every changed document. One finding fixed (the "No `pub` is file scope. That is the `static` rule." fragment in AGENTS.md); the rest were soft template findings in the handbook and a skill's numbered steps, left as they are.
- Verified: misra-lint tests failed first for the new checks, then 27 pass at Debug and ReleaseSafe; `compliant.zig` 10 tests at Debug and ReleaseSafe; `bun test scripts/` 29 tests; `bun scripts/check_samples.ts`; vnu on `site/index.html` and `site/site.css`; misra-lint on itself and `compliant.zig`, exit 0; a field run on 1,559 `.zig` files from other projects (counts in `docs/misra-lint.md`); the front sheet and the Dir 5.2 sheet read in a browser at 1440 px.
- Published: `bun scripts/build_site.ts` and `wrangler deploy` (version 0e579172); `curl` on both domains returned 200 for `/`, 59 rules in `/rules.json`, 68 entries in `/checks.json`, the renamed group in `/handbook.json`, and 404 for `POST /api/check`.

## 2026-10-27: first commit

- What: the project became a git repository on `main`. `.gitignore` also keeps out `.impeccable/` review captures, its `*.local.json` config, and its caches; AGENTS.md says so. The 2026-10-21 review entries no longer name the review tools; their facts are unchanged.
- Why: the user asked to commit and push.

## 2026-10-27: HTTPS redirect, public repo

- What: `scripts/worker.ts` (tested in `scripts/worker.test.ts`) runs before the static assets (`main`, `assets.binding`, and `assets.run_worker_first` in `wrangler.jsonc`) and answers plain HTTP with a 301 to the same URL on HTTPS. AGENTS.md describes it. The GitHub repository `maci0/misra-zig` is public.
- Why: the user asked to enable "Always Use HTTPS" and to make the repo public. The zone setting needs a scope the wrangler OAuth login does not offer (`wrangler login --scopes-list` lists only `zone:read` for zones), so the Worker makes the same redirect. Cost: every request now invokes the Worker and counts against the Workers request quota; static assets alone are free (Cloudflare, "Billing and limitations" for static assets).
- Evidence: the worker test failed before `worker.ts` existed. After `wrangler deploy` (version fd71ce2d; the previous version was 68c793a1), `curl` on both domains: `http://` for `/` and `/rules.json?a=1` returned 301 to the same path and query on `https://`; over HTTPS, `/`, `/api/health` returned 200, `/rules.json` held 59 rules, `POST /api/check` and an unknown path returned 404, and the HTML, CSS, JS, JSON, and font content types were unchanged. `gh repo view` reports the repo `PUBLIC`.
- Verified: `bun test scripts/` (31 tests); `wrangler deploy --dry-run` showed the `ASSETS` binding.
