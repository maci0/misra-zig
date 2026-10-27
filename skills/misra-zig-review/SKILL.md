---
name: misra-zig-review
description: Review Zig 0.17 code against the MISRA Zig coding standard. Use when asked to review, audit, or check Zig code for MISRA Zig compliance, safety rules, or "the standard", or before committing Zig in a project that follows MISRA Zig. Runs misra-lint, the compiler in Debug and ReleaseSafe, and a reader pass over every rule, then reports by rule.
---

# Review Zig against MISRA Zig

`$MZ` below is the MISRA Zig repo: this skill sits at `$MZ/skills/misra-zig-review/`.
The standard is `$MZ/AGENTS.md`; every rule's do and don't is in
`$MZ/docs/misra-zig-handbook.md`. Needs Zig 0.17.0 and Bun.

A clean result is not compliance. The report says what each step proved and
what it could not see.

## 1. Skeleton

```bash
bun $MZ/scripts/review.ts <files>      # exit 0 clean, 1 findings, 2 error
```

It prints markdown: misra-lint findings grouped by rule, then a reader
checklist of every rule in two lists, rules no check decides and rules a check
decides only in part. The checklist comes from the handbook and the check list,
so it is never stale. Start the report from it.

## 2. Compiler gates

Run these in the project under review and keep each exit code:

```bash
zig fmt --check <files>
zig run -ODebug $MZ/tools/misra_lint.zig -- --root <test root> <every .zig file>
zig test -ODebug <test root>
zig test -OReleaseSafe <test root>
```

Add `-lc` when the code calls libc. A test that passes only in Debug is a
finding. The `--root` run reports every file the test root never imports
(Rule 2.1): the compiler has not checked those at all, so read them first. ReleaseFast is not the compliance build.

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
"only in part" rules, look for what the named checks miss. misra-lint has no
types and sees one file, so it misses:

- names reached through an alias (`const heap = std.heap;` then
  `heap.page_allocator`), or through a struct field holding an allocator;
- recursion through methods (`self.walk()`) or another file;
- widths it cannot see: `usize`, aliases, and inferred locals in arithmetic;
- a check that guards a parameter but is not a comparison next to its name
  (it accepts `if (n > len)`, not `if (!inRange(n))`), and a comparison that
  is next to the name but is not the right guard (`if (n > 100)` before
  `@intCast(n)` counts);
- an `AssumeCapacity` reserve that is smaller than the appends, and a reserve
  made by the caller;
- a std call whose body asserts an argument (Dir 4.11), a float that can be
  NaN (Dir 4.15), and a tagged union field read without a tag test
  (Rule 19.3): all need types or the std source;
- two functions that take the same two mutexes in opposite orders (Dir 5.2),
  and an atomic ordering passed through a constant (Rule 21.25);
- a pointer to a local stored first and returned later;
- every trust boundary that is not an `export fn` (file bytes, sockets, parsed
  config) where `std.debug.assert`, `@intCast`, `@fromBackingInt`, a length
  that sizes an allocation, or an index meets outside data;
- everything across files: Rule 8.4 headers, Rule 8.7 `pub` use.

## 5. Report

One line per problem: `path:line`, the rule (`Rule 22.1`), what is wrong, and
the fix. Group by rule in handbook order. Then state:

- which gates ran and their exit codes;
- how many misra-lint findings were fixed, kept with an allow comment (quote the
  reason), or judged not a breach (say why);
- which checklist rules were read and which could not be checked, with why.

No score and no percentage. A gate that did not run is reported as not run,
never as passed.
