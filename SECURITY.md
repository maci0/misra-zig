# Security policy

The local server, the published site, and the deploy path are mapped in
[docs/THREAT_MODEL.md](docs/THREAT_MODEL.md). This file covers versions and
reporting only.

## Supported versions

Local tooling targets Zig 0.17.0 and Bun. Releases are tagged in Git and
published on [GitHub](https://github.com/maci0/misra-zig/releases). Fixes
land on `main`; no backport policy is documented. The published handbook
is static and is deployed from `main`.

## Reporting

There is no published disclosure contact or advisory process. A report has
no documented path to a fix.

## What this project does not do

No account system, no database, no personal data. The local checker server
(`scripts/server.ts`) listens on `127.0.0.1` only and compiles untrusted
samples with `zig test --test-no-exec`; it does not run the sample. The
published site (`scripts/worker.ts`) serves static assets and never runs a
compiler. The Zig obligations in `AGENTS.md` are this repo's text, not a
statement of the Zig language reference.
