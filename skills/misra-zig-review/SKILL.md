---
name: misra-zig-review
description: Review Zig 0.17 code against the MISRA Zig coding standard. Use when asked to review, audit, or check Zig code for MISRA Zig compliance, safety rules, or "the standard", or before committing Zig in a project that follows MISRA Zig. Runs misra-lint, the compiler in Debug and ReleaseSafe, and a reader pass over every rule, then reports by rule.
---

# Review Zig against MISRA Zig

Set `MZ` to the absolute path of the MISRA Zig repo, which contains this skill
at `skills/misra-zig-review/`. Run commands from the project you are reviewing.
The standard is `$MZ/AGENTS.md`; every rule's do and don't is in
`$MZ/docs/misra-zig-handbook.md`. Needs Zig 0.17.0 and Bun.

A clean result is not compliance. The report says what each step proved and
what it could not see.

## 1. Skeleton

```bash
bun "$MZ/scripts/review.ts" path/to/file.zig  # exit 0 no findings, 1 findings, 2 error
```

It prints markdown: misra-lint findings grouped by rule, then a reader
checklist of every rule in two lists, rules no check decides and rules a check
decides only in part. The checklist comes from the handbook and the check list,
so it reflects those files at the time of the run. Start the report from it.
This command runs misra-lint; it does not compile the reviewed files or check
import reachability. Exit 0 still requires the gates and reader pass below.

## 2. Gates

Run these in the project under review and keep each exit code:

```bash
zig fmt --check path/to/file.zig
zig run -ODebug "$MZ/tools/misra_lint.zig" -- test_root.zig src/*.zig
```

Resolve every `parse_error` before continuing: the `--root` import pass
reparses files without the per-file nesting guard. Then run:

```bash
zig run -ODebug "$MZ/tools/misra_lint.zig" -- --root test_root.zig test_root.zig src/*.zig
zig test -ODebug test_root.zig
zig test -OReleaseSafe test_root.zig
```

Replace the example paths with the project's files. Include the root and all
intermediate imports in the file list; `src/*.zig` does not include subdirectories.
Add `-lc` when the code calls libc. A test that passes only in Debug is a
finding. The `--root` run reports every file the test root never imports
(Rule 2.1). Read those files first. Even an imported file can contain
unreferenced declarations the compiler has not analyzed. ReleaseFast is not the
compliance build.

## 3. Findings

- `violation`: the pattern is the breach the rule names. Fix it, or report it.
- `review`: usually the breach. Read the code, decide, and say why.
- `parse_error`: no check ran on that file. Fix the syntax first.

`// misra-lint: allow <check> <reason>` silences one finding when the reason is
true. Never add one to make the run pass, and never reshape code only to dodge
the matcher (a rename, a split expression) without fixing what the rule is
about.

## 4. Reader pass

Work through the checklist with the handbook open on each rule's don't. For the
"only in part" rules, look for what the named checks miss: read
`$MZ/docs/misra-lint.md`, "Known blind spots" and the `UNDECIDED` list under
"Coverage", first. Beyond those, look for:

- an allocator reached through a struct field;
- an `AssumeCapacity` reserve made by the caller;
- every trust boundary that is not an `export fn` (file bytes, sockets, parsed
  config) where `std.debug.assert`, `@intCast`, `@fromBackingInt`, a length
  that sizes an allocation, or an index meets outside data.

## 5. Report

One line per problem: `path:line`, the rule (`Rule 22.1`), what is wrong, and
the fix. Group by rule in handbook order. Then state:

- which gates ran and their exit codes;
- how many misra-lint findings were fixed, kept with an allow comment (quote the
  reason), or judged not a breach (say why);
- which checklist rules were read and which could not be checked, with why.

No score and no percentage. A gate that did not run is reported as not run,
never as passed.
