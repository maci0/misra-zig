# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Static HTML, CSS, and JavaScript, with no framework. Bun serves the local
site and invokes Zig 0.17.0 and misra-lint. The linter uses `std.zig.Ast`;
the published handbook is a static build served by a Cloudflare Worker.

## Users

Someone applying the Zig obligations in `AGENTS.md` to Zig 0.17 code. They look up a rule, compare a do and a don't, and edit the sample.

## Product Purpose

State the Zig obligation for each cited rule, show a do and a don't, and let the reader check the edited sample, or a whole file, with Zig 0.17 and misra-lint on their machine.

## Positioning

The page is the handbook. The sample is source the reader can change. The checker reports whether Zig accepts the sample, alongside lint findings. Zig accepting a file is not compliance, and a clean misra-lint run is not compliance either.

## Operating Context

Requirements and the published URLs are in [README.md](README.md#run-it). The
server listens on `127.0.0.1`; the published copy is static, and Check runs
only on the local server.

## Capabilities and Constraints

The cited directives and rules are the ones named in `AGENTS.md`, not the whole of MISRA C. Wording is the Zig obligation, not the C standard's text. The handbook does not name a source project. misra-lint decides only what a syntax tree shows. The checker is not a public compile service.

## Brand Commitments

The title is MISRA Zig. The site says it is not a publication of the MISRA Consortium.

## Evidence on Hand

[The handbook](docs/misra-zig-handbook.md) and
[tested examples](docs/examples/compliant.zig).

## Product Principles

Show the rule and the sample together. Keep one source for the site's rule wording, the markdown handbook. `/rules.json` is that handbook in fields, not a second wording. Show compiler diagnostics and map editor findings to sample lines. Say for each don't how it is known: rejected by the compiler, flagged by misra-lint, or left to a reader. Do not treat a safe-build panic as proof.
