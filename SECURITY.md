# Security policy

The surface and how to reach it are mapped in
[docs/THREAT_MODEL.md](docs/THREAT_MODEL.md). This file covers versions and
reporting only.

## Supported versions

The checker and site target Zig 0.17.0 and Bun, as the README states.
There is no release channel; fixes land on the main branch, and the
published site is rebuilt from it.

## Reporting

There is no published disclosure contact or advisory process today; that
gap is recorded in the threat model. No supported disclosure path is
established here.

## What this project does not do

No account system, no database, no personal data. The local checker server
(`scripts/server.ts`) listens on `127.0.0.1` only and compiles untrusted
samples without running them; the published site (`scripts/worker.ts`)
serves static assets and never runs a compiler. The Zig standard itself,
not this repo, is the authority on the rules in `AGENTS.md`.
