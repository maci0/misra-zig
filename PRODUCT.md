# Product

<!-- impeccable:product-schema 1 -->

Assumptions below are inferred from the request: a generic Zig 0.17 standard inspired by MISRA C, read in a browser, with highlighted samples that can be edited and checked. No visual world was chosen in advance.

## Platform

web

## Stack

delegated: static HTML, CSS, and JavaScript, served by `bun scripts/server.ts`, because the page has to highlight Zig and run the local 0.17 compiler and misra-lint. No framework. misra-lint is Zig, built on `std.zig.Ast`.

## Users

Someone applying a small set of MISRA-inspired rules to Zig 0.17 code. They look up a rule, compare a do and a don't, and edit the sample.

## Product Purpose

State the Zig obligation for each cited rule, show a do and a don't, and let the reader check the edited sample, or a whole file, with Zig 0.17 and misra-lint on their machine.

## Positioning

The page is the handbook. The sample is source the reader can change. The checker reports the compiler's own result. It does not claim that a clean compile meets the rule.

## Operating Context

Local use. Zig 0.17.0 is on PATH or in `ZIG`. The server listens on 127.0.0.1.

## Capabilities and Constraints

The cited directives and rules are the ones named in `AGENTS.md`, not the whole of MISRA C. Wording is the Zig obligation, not the C standard's text. The documents do not name a source project. Zig accepting a file is not compliance, and a clean misra-lint run is not compliance either: it decides only what a syntax tree shows. The checker is not a public compile service.

## Brand Commitments

The title is MISRA Zig. The site says it is not a publication of the MISRA Consortium.

## Evidence on Hand

`docs/misra-zig-handbook.md` and `docs/examples/compliant.zig`. No customers, benchmarks, or endorsement.

## Product Principles

Show the rule and the sample together. Keep one source for the wording, the markdown handbook. `/rules.json` is that handbook in fields, not a second wording. Report compiler output as the compiler wrote it. Say for each don't how it is known: rejected by the compiler, flagged by misra-lint, or left to a reader. Do not treat a safe-build panic as proof.
