# Threat model

Last reviewed: 2026-11-13. No owner and no review cadence are set.
Companion: `SECURITY.md`.

This is a coding standard, a static handbook, and a local checker. It has
no accounts, no personal data, and no database. The network listeners are
`scripts/server.ts` (localhost) and `scripts/worker.ts` (published static
site).

## What can go wrong

| # | Risk | Bound |
|---|------|-------|
| R1 | Anyone who can open a TCP connection to the listen port can POST a compile. The server has no authentication. | Bound to `127.0.0.1`. A request whose `Host` is not `127.0.0.1:PORT` or `localhost:PORT` gets 421 before any compile, including a DNS-rebinding `Host`. |
| R2 | `zig test --test-no-exec` analyzes the sample as the user who started the server. It does not execute the sample's tests. There is no OS sandbox: the scratch directory is a working directory and a cache, not a confinement boundary. | Zig rejects imports and embedded files outside the module path in the probes below. This is a compiler restriction, not OS isolation. |
| R3 | Compile requests are queued with no depth limit (`oneAtATime`) and share persistent caches under `.scratch/site-check/` with no size cap. Each temporary source directory is removed after compilation. misra-lint runs are not queued. | One compile at a time; each lint run stops at 10 s. Body 256 KiB, source 64 KiB of UTF-8. |
| R4 | The published Worker runs before static assets (`run_worker_first: true`), so every request counts against the Workers request quota. There is no rate limit in this repo. | A full quota stops the public handbook. The Worker does not compile. |
| R5 | `/api/health` returns `lintProblem`, the misra-lint build failure text, which the page displays in its feature list and when a Check has no lint findings available. Compiler output has the sample path replaced by `sample.zig` and is then clipped, and a failed `Bun.spawn` returns `err.message` to the client. | A 500 from the fetch handler is a fixed sentence. The build failure and the spawn error are not. |
| R6 | `build/site/` is whatever `scripts/build_site.ts` wrote. The Worker serves those bytes. | A bad build is what readers copy, and what `rules.json` and `checks.json` tell tools. |

When `scripts/server.ts`, `scripts/check.ts`, `scripts/lint.ts`,
`scripts/worker.ts`, or `wrangler.jsonc` changes, re-check the rows above
against those files.

## Listeners and inputs

**Local server.** `Bun.serve` in `scripts/server.ts`, hostname `127.0.0.1`,
port `PORT` or 4173. `PORT` must be an integer from 1 to 65535 or the
process throws before it listens.

- `GET /` and files under `site/`. `siteFile` decodes the path, rejects a
  NUL, and requires the normalized path to stay under `site/`.
- `GET /handbook.json`, `/rules.json`, `/checks.json`.
- `GET /api/health`: `{ zig, lint, lintProblem, revised, compileLimit }`.
- `POST /api/check`: `zig test --test-no-exec -lc -ODebug` (`checkSource`)
  and misra-lint (`lintSample`).
- `POST /api/lint`: misra-lint only.

Every request checks `Host` against `127.0.0.1:PORT` and `localhost:PORT` and
returns 421 on a mismatch. A POST then checks `Origin`, only when the header is
present (403 unless it is `http://127.0.0.1:PORT` or `http://localhost:PORT`),
followed by `Content-Type` starting with `application/json` (415). A POST with
no `Origin` is not refused by the origin check. The body cap is
`maxRequestBodySize` 256 KiB (413). The source cap is `MAX_SOURCE_BYTES` (64
KiB of UTF-8).

**Published site.** `wrangler.jsonc` serves `build/site/` through
`scripts/worker.ts` on misra-zig.dev and misra-zig.com. `build_site.ts`
writes `api/health` and no `api/check`. The Worker redirects `http:` to
`https:` with 301 and passes every other request to the asset binding.
Static assets answer an unknown path with their own 404.

**CLI, not a listener.** `tools/misra_lint.zig`, `scripts/check_samples.ts`,
`scripts/review.ts`, `scripts/gen_std_lists.ts`, and `scripts/build_site.ts`
read paths the developer passed and files in the repo; `gen_std_lists.ts` also
reads the installed std (`std_dir` from `zig env`).

**Environment.** `PORT` (`scripts/server.ts`), `ZIG` (`zigCommand` in
`scripts/check.ts`), `MISRA_ZIG_COMPILE_LIMIT` (`compileLimitFromEnv`:
bytes, or a number with `M` or `G`; below 512 MiB throws; default
4 GiB). `ZIG` is the compiler binary path and is not otherwise checked.

**Deploy.** `wrangler.jsonc` names the two domains and
`run_worker_first: true`. `CLOUDFLARE_ACCOUNT_ID` is in gitignored
`.secrets` (mode 600). Wrangler uses the OAuth login outside the repo.
No code under `site/` or `scripts/` reads the account id. There is no
admin port.

## Controls on a local check

Zig 0.17.0 probes rejected `@embedFile("/etc/hostname")` and a parent-directory
`@embedFile` with "embed of file outside package path". An absolute
`@import("/etc/hostname")` reported "no module named"; an import leaving the
module directory reported "import of file outside module path". Sibling-file
imports and embeds were accepted. These probes did not cover `@cInclude`,
build-system module roots, or other compiler file access. The compiler runs
with the user's account, reads the Zig installation, and writes `.scratch/`.

`checkSource` writes the wrapped sample to a fresh directory under
`.scratch/site-check/run-*` and deletes that directory in `finally`. The
cache directories next to it stay.

Each submitted compile is started under `prlimit --as=`
at `compileLimit` (default 4 GiB). The server refuses to start when
`prlimit` is not on `PATH`. The warm-up calls `checkSource` with no memory
limit so the first libc build can finish; that call still uses the 60 s
timeout (`ZIG_TIMEOUT_MS`). Any compile that ends by SIGKILL, from the timeout
or from another source such as the kernel OOM killer, is reported as "Zig did
not finish within 60 seconds." A capped compile that aborts, segfaults, or
prints `error: OutOfMemory` is reported as stopped under the memory limit.

`readCapped` keeps 12,000 bytes of stdout and 12,000 of stderr. `present`
replaces the sample path with `sample.zig`, then `clip` keeps `OUTPUT_LIMIT`
(12,000) UTF-16 code units of the joined text, after stripping ANSI and
trimming. That is a string-length cap, not a 12 KiB byte cap.

misra-lint is built once at start into `.scratch/bin`, written to a temp
name and `rename`d into place (`buildLint`). A lint run times out at 10 s.
A build failure is stored in `lintProblem`, returned by `/api/health`, and
displayed in the front-sheet feature list and Check results when lint is
unavailable (`site/site.js`). Check still runs the compiler when the lint
binary is missing; `findings` is then null.

`site/site.js` posts JSON and inserts compiler output through `escapeHtml`.
The body size, source size, `Host`, and content type are enforced only in
`scripts/server.ts`.

## Published site and deploy

The Worker does not branch on the path. Quota exhaustion is the
availability failure (R4). Content is the last `build_site.ts` output (R6).

A leaked account id does not deploy: the OAuth login is a separate secret,
stored outside the repo. This file does not claim what an attacker can do
with the OAuth credential.

## Reporting

`console.error` in `scripts/server.ts` is the server log. Check and lint
output are returned to the caller. There is no request log and no record
of who submitted a check. `SECURITY.md` states that no disclosure contact
is published.
