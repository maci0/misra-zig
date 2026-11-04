# Threat model

Last reviewed: 2026-11-04 (starter version; no owner or review cadence is
recorded here because none is established). Companion: `SECURITY.md`.

This is a coding standard plus a static handbook site and a local checker
server. It holds no user accounts, no personal data, and no database. The
attack surface is the local checker server, the published static site, and
the deploy path. Everything below names the file that implements it.

## Risk-ranked summary

| # | Risk | Why it matters | Where |
|---|------|----------------|-------|
| R1 | Local checker server has no authentication; it trusts localhost. | Any process or DNS-rebinding page that reaches it can queue compiler runs and read compiler output. | `scripts/server.ts` |
| R2 | Untrusted Zig source is compiled on the same host. It is never executed, but the compiler still reads files it names. | A sample naming a local file via `@import` / `@embedFile` makes the compiler read outside its scratch directory. | `scripts/check.ts` (`checkSource`) |
| R3 | Compile queue and caches are unbounded. | Repeated checks fill `.scratch/` and queue memory on the developer's machine; the start-up warm-up compile is uncapped. | `scripts/server.ts` (`oneAtATime`), `scripts/check.ts` (`projectScratch`) |
| R4 | Published worker counts every request against a quota, with no rate limit. | Unauthenticated traffic can exhaust the Workers request quota and take the public site down. | `scripts/worker.ts` |
| R5 | Build and compiler diagnostics can carry local paths. | `/api/health` returns the misra-lint build failure text; compiler output is the only other channel to the page. | `scripts/server.ts` (`lintProblem`, `/api/health`), `scripts/check.ts` (`present`, `clip`) |

Emerging risk (recorded, not fixed here): a new check, endpoint, or deploy
setting changes this surface. Re-verify against the file references when
`scripts/server.ts`, `scripts/check.ts`, `scripts/worker.ts`, or
`wrangler.jsonc` changes. sec-review owns point fixes; this document owns
the map.

## 1. Attack surface inventory

**Local checker server** (`scripts/server.ts`, `Bun.serve` on `127.0.0.1`,
default port 4173, `PORT` overrides, validated 1–65535):

- `GET /` and static files under `site/` (path traversal-checked in
  `siteFile`).
- `GET /handbook.json`, `/rules.json`, `/checks.json`, `/api/health`.
- `POST /api/check` — compiles untrusted Zig source with
  `zig test --test-no-exec -lc -ODebug` (`scripts/check.ts` `checkSource`)
  and lints it with misra-lint (`scripts/lint.ts` `lintSample`).
- `POST /api/lint` — lints only.

**Published site** (`wrangler.jsonc`, `scripts/worker.ts`): static assets from
`build/site/` plus `scripts/build_site.ts`. No `/api/check` exists there
(`build_site.ts` writes only `api/health`). The worker redirects plain HTTP
to HTTPS and passes everything else to `ASSETS`.

**CLI entry points** (developer-run, not network): `tools/misra_lint.zig`
(`zig run ... -- FILE...`, `--json`, `--checks`, stdin `-`),
`scripts/check_samples.ts`, `scripts/review.ts`, `scripts/gen_std_lists.ts`,
`scripts/build_site.ts`. They read files named on the command line and the
handbook on disk.

**Environment variables**: `PORT`, `ZIG` (compiler path, `scripts/check.ts`
`zigCommand`), `MISRA_ZIG_COMPILE_LIMIT` (validated in
`compileLimitFromEnv`, minimum 512 MiB). None beyond these is read.

**Deployment surface**: `wrangler.jsonc` (custom domains misra-zig.dev and
misra-zig.com, HTTPS redirect, `run_worker_first: true`). The only secret
named anywhere is `CLOUDFLARE_ACCOUNT_ID` in gitignored `.secrets` (mode
600); wrangler signs in with an OAuth login outside the repo. There is no
admin port, debug endpoint, or extra service.

No entry point in the model is stale; no network listener exists besides
the two above.

## 2. Trust boundaries and data flow

- **Browser → local server.** Untrusted: the `source` string in
  `POST /api/check` / `/api/lint`. The page itself is served from `site/`.
- **Local server → Zig compiler.** Crossed in `scripts/check.ts`
  (`checkSource`). The source is written to a fresh scratch directory and
  compiled with fixed flags and `--test-no-exec`, so it is analyzed, not
  run. The compiler is the privilege step: it runs with the developer's
  account and a 4 GiB address-space cap (`prlimit`) and a 60 s timeout.
- **Local server → misra-lint.** Crossed in `scripts/lint.ts`
  (`lintSample`); the binary is built once at start-up into
  `.scratch/bin` with an atomic rename.
- **Developer → published site.** Crossed by `wrangler deploy` with the
  OAuth login; the Worker serves static assets only.
- **Secrets → code.** `CLOUDFLARE_ACCOUNT_ID` enters only through the
  deploy command's env file; nothing in `site/`, `scripts/`, or the Worker
  reads it.

No database, no tenant boundary, no service-to-service call exists.

## 3. Assets and impact

Worth stealing or corrupting: the developer's local files and account
(reachable only through the compiler in R2), the Cloudflare account behind
the deploy token, and availability of the public handbook. The handbook
itself is public content; there is no user data, credential store, or
signing key in the code. A corrupted handbook build is a reputational risk
only (wrong rule text served from `build/site/`).

## 4. Threats per boundary (STRIDE)

**Browser → local server** (`scripts/server.ts` `refusal`):

- Spoofing / CSRF from another site: mitigated by the `Origin` check (403)
  and the `application/json` content-type check (415), which forces a
  preflight this server never answers.
- Spoofing via DNS rebinding: mitigated by the exact `Host` check (421)
  against `127.0.0.1:PORT` / `localhost:PORT`.
- Denial of service: partially mitigated — 256 KiB request body cap,
  64 KiB source cap, one compile at a time. No limit on queued requests or
  total cache growth (R3).
- Elevation of privilege: none in the server; impact comes from R2.

**Local server → compiler** (`scripts/check.ts`):

- Tampering / information disclosure: the compiler reads files the sample
  names (`@import`, `@embedFile`). Results are clipped (12 KiB) and file
  paths in output are rewritten to `sample.zig`, but compile errors embed
  sampled text and could name local paths. No sandbox beyond the scratch
  directory, `--test-no-exec`, and the memory cap (R2).
- Denial of service: 60 s timeout, memory cap, serialized queue. The
  start-up warm-up compile in `scripts/server.ts` is uncapped by design
  (it builds libc into the cache).

**Published worker** (`scripts/worker.ts`):

- Denial of service by quota exhaustion: every request is counted because
  `run_worker_first` is true; no rate limit or cache rule exists (R4).
- Tampering of served content: the assets are whatever `build_site.ts`
  wrote; a poisoned build serves it as-is.

**Deploy** (`wrangler.jsonc`, `.secrets`): a leaked account ID alone does
not deploy (OAuth login is required); nothing else is stored.

## 5. Mitigations mapping

| Threat | Control in code | File |
|--------|-----------------|------|
| DNS rebinding | Exact Host allowlist, 421 | `scripts/server.ts` (`refusal`) |
| Cross-origin POST | Origin allowlist (403) + JSON content type (415) | `scripts/server.ts` (`refusal`) |
| Oversized input | 256 KiB body, 64 KiB source, 12 KiB output clip | `scripts/server.ts`, `scripts/check.ts` (`MAX_SOURCE_BYTES`, `clip`) |
| Compiler runaway | 60 s timeout, `prlimit` memory cap, serialized queue | `scripts/check.ts` (`checkSource`) |
| Path traversal on static files | `decodeURIComponent`, `\0` reject, normalized prefix check | `scripts/server.ts` (`siteFile`) |
| Stack / path leak to page | Generic 500 body; detail to server log only | `scripts/server.ts` (`error`) |
| HTTP downgrade on public site | 301 to HTTPS in the Worker | `scripts/worker.ts` |
| Partial build execution | Atomic rename of `misra-lint` binary | `scripts/lint.ts` (`buildLint`) |

Threats with no mitigation, ranked: R4 (quota, public, unauthenticated) >
R3 (local disk/queue growth) > R2 residual (compiler file reads) > R5
(diagnostic path text in `/api/health`). The Host check is a single point of
failure for R1: it is the only thing between a rebinding page and the
compiler, and it depends on the server staying bound to `127.0.0.1`.

Claims check: no document claims a mitigation the code lacks. `README.md`
says the published copy is read-only and Check runs only locally, which
matches `build_site.ts` (no `/api/check` in the build). `AGENTS.md` says the
published copy never runs a compiler and `POST /api/check` is a 404 there;
the build writes no such route, and the Worker passes unknown paths to the
assets, which 404.

## 6. Abuse cases

There is no authenticated or multi-user surface, so business-logic abuse is
limited to local use:

- A hostile page cannot reach the server while the Host check holds; if a
  developer binds the server to `0.0.0.0` or the check is removed, that
  page could submit compiler jobs from any site the developer visits.
- A local user can exhaust disk by repeated checks: the compiler cache in
  `.scratch/site-check/` grows without a cap (`scripts/check.ts`
  `projectScratch`), and queued compiles are not bounded.
- A hostile sample can make the compiler spend the full 60 s / 4 GiB; that is
  the designed cap, and the queue serializes it, so it delays only the
  developer's own checks.

No client-side enforcement is trusted: `site/site.js` sends the source as
JSON and renders compiler output escaped (`escapeHtml`); limits are also
enforced server-side.

## 7. Document quality

This file is the starter model; it replaces the previous state of no model.
It has a risk rank and a last-reviewed date above; no owner or cadence is
recorded because none exists (noted, not invented). `SECURITY.md` carries
the supported versions and what to report; its disclosure contact is a gap
(see `SECURITY.md`).

## 8. Response readiness

Events worth investigating exist only as process output: `console.error`
in `scripts/server.ts` (server log), and compiler/lint output returned to
the page. There is no request log, no audit trail of who submitted a check,
and no documented path from a vulnerability report to a shipped fix.
o11y-review owns log structure; this notes the gap only.
