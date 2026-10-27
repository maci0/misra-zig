# misra-lint

`tools/misra_lint.zig` reports the MISRA Zig don't patterns that a syntax tree
decides. It parses each file with `std.zig.Ast` from the Zig 0.17 standard
library. It has no types, no data flow, and sees one file at a time, so a clean
run is not compliance: the rules it cannot decide still need a reader.

```bash
zig run -ODebug tools/misra_lint.zig -- FILE...      # text findings
zig run -ODebug tools/misra_lint.zig -- --json FILE  # fields
zig run -ODebug tools/misra_lint.zig -- --checks     # the check list
zig run -ODebug tools/misra_lint.zig -- --root src/main.zig src/*.zig  # also: files main.zig does not reach
echo 'fn f() void { g() catch {}; }' | zig run tools/misra_lint.zig -- -
```

Exit 0: no finding. Exit 1: at least one finding. Exit 2: usage or read error.

```
t.zig:2:9: violation[catch_empty] Dir 4.1: catch {} discards the error, and so does a handler that only discards its capture. Propagate it with try or handle each error.
```

## Severity

- `violation`: the pattern is the breach the rule describes.
- `review`: the pattern is usually the breach, and a reader decides:
  `undefined_then_branch`, `field_by_field_init`, `truncate_param`,
  `unbounded_loop`, `index_at_len`, `same_path_twice`, `enum_else`,
  `unwrap_assumed`, `assume_capacity`, `thread_outside_main`,
  `handwritten_extern`, `sentinel_return`, `ptrcast_reinterpret`,
  `memcpy_alias`.

## Lists generated from the standard library

`tools/std_lists.zig` is written by `bun scripts/gen_std_lists.ts` from the
installed Zig std (`zig env`):

- `deprecated`: every top-level `pub` declaration whose doc comment starts
  `Deprecated` or says `This function is deprecated`, with the replacement it
  names. `deprecated_api` reports a use and shows the replacement.
- `posix_assumes_errno`: every `std.posix` function with an errno prong that is
  `=> unreachable`. `posix_assumes_errno` reports a call.

`bun scripts/gen_std_lists.ts --check` exits 1 when the file no longer matches
the installed std, and `bun test scripts/` runs it. Methods marked deprecated
inside a type are not listed: a method call names no type in the syntax tree.

## Files the root does not reach

`--root ROOT FILE...` follows `@import("x.zig")` string literals from ROOT,
resolving each path against the importing file's directory, and reports every
FILE it does not reach (`unreachable_file`, Rule 2.1). Only the files named on
the command line are considered, and an import built at compile time is not
followed.

## Silencing one finding

`// misra-lint: allow <check> <reason>` in a comment on the finding's line, or
on a line above it that holds only that comment. The reason is required; a
comment without one silences nothing. Text inside a string literal is not a
comment, and a trailing comment on one line does not reach the next. The
checker's own switches over `std.zig.Ast.Node.Tag` and `std.zig.Token.Tag`
carry allow comments: those enums belong to the standard library and have
hundreds of tags.

## Input it refuses to parse

`std.zig.Ast.parse` recurses once per nesting level, and about 2000 nested
parentheses exhausted its stack. Before parsing, the tokenizer (which does not
recurse) measures bracket nesting and runs of prefix operators (`!!!x`,
`****T`). Past 256 levels the file gets one `parse_error` finding, "nesting
deeper than 256 levels", and no other check runs.

## Coverage

Measured with `misra-lint --checks` and `bun test scripts/lint.test.ts`:

- 67 checks, plus `parse_error`. Together they name 50 of the 59 cited rules.
- Of the handbook's 71 don't samples marked compiles, 59 are flagged under
  their own rule. The other 12 are listed in `UNDECIDED` in
  `scripts/lint.test.ts`, each with what a syntax tree cannot see: a reserve
  smaller than the appends (Dir 4.1), which std functions assert an argument
  (Dir 4.11, two samples), whether a float can be NaN (Dir 4.15), which
  threads touch a variable (Dir 5.1), the lock order the callers use
  (Dir 5.2), the C header (Rule 8.4), other files (Rule 8.7), whether a byte is
  a character (Rule 10.2), pasted prong bodies (Rule 16.3), a field access on
  a tagged union (Rule 19.3), and a data byte used as an end marker
  (Rule 22.7). Rule 2.1's don't has no sample; `--root`
  decides it on a file set.
- The 8 don't samples marked rejected are the compiler's job.
- Every do sample, `docs/examples/compliant.zig`, and the checker itself lint
  clean. `compliant.zig` carries one allow comment, on a test that writes to a
  read-only handle to check that the write is refused.

## Known blind spots

- Names are matched as written: `const heap = std.heap;` then
  `heap.page_allocator` is not seen.
- Recursion is followed through plain calls to functions in the same file, not
  through methods (`self.walk()`) or other files. A function whose every
  parameter is `comptime` is treated as compile-time only and is not reported.
- Integer widths come from parameters and typed locals written as `uN` or
  `iN`; `usize`, aliases, and inferred locals are unknown, and the width checks
  stay silent on them.
- An allocation whose receiver chain names an arena (`arena.alloc`,
  `l.arena.alloc`) needs no release of its own. An arena under another name
  (`alloc`) is not recognized, so `try_before_release` can fire on it.
- "Checked" means a comparison next to the parameter's name earlier in the
  function. `unchecked_divisor` needs a comparison with the literal `0`;
  `unchecked_intcast`, `unchecked_enum`, and `float_to_int` accept any
  comparison, so `if (n > 100)` before `@intCast(n)` counts as a check even when
  it is not the right one. A guard through a helper (`if (!inRange(n))`) still
  reports.
- `assert_on_input` looks only at `export fn`. Outside data that arrives
  through a file or a socket inside the module is not followed.
- `index_at_len` exempts a name declared with a sentinel type (`[:0]u8`,
  `[2:0]u8`) in the same function. A sentinel slice that arrives from a call
  is still reported, as `review`.
- `float_to_int` sees a rounding builtin only where its integer result is
  visible: returned from a function with an integer return type, or stored in
  a local typed `uN` or `iN`.
- `stack_escape` sees `return &local` and `return local[a..b]` for a local
  declared in the same function, not a pointer stored first and returned
  later.
- `enum_else` takes a `switch` as an enum switch when every other prong names
  `.tags`. An `else` that returns `error.X` is not reported; one that calls a
  helper to fail (`return lib.fail(...)`) is.
- `main`, a test block, and `fn build(b: *std.Build)` count as entry points for
  `terminate_outside_main`, `thread_outside_main`, and `io_outside_main`. A
  helper function of a `build.zig` does not, so a `@panic` there is reported.
- `ptrcast_reinterpret` exempts a `@ptrCast` of a name declared with `u8` in
  its type (bytes overlaid by a struct, after the checks of Dir 4.1). It cannot
  see the two pointee types.
- `sentinel_return` sees `return -1` and `return std.math.maxInt(...)` outside
  an `export fn`; an in-band value from a named constant is not seen.
- `build_unsafe_mode` reads `.optimize = .ReleaseFast` (or `.ReleaseSmall`) and
  `.sanitize_c = .off` written as field initializers.
- `pointer_arith` knows a many-item pointer only from a parameter or a local
  whose declared type starts `[*`; an inferred local and a struct field are
  not seen.
- `memcpy_alias` compares the sliced expressions as written. Two names for
  one buffer are not seen, and two slices of one buffer that cannot overlap
  are still reported, which is why it is `review`.
- `atomic_order` reads an ordering written as an enum literal in a call to a
  `std.atomic.Value` method or an `@atomic` builtin; an ordering passed
  through a constant is not seen.
- `lock_twice` matches receivers as written, inside one function. A `defer`
  unlock frees the mutex at the end of its block, and an `errdefer` unlock
  does not count. A lock order across functions is not checked.

## Field test

misra-lint ran on 364 `.zig` files from two other projects, written for Zig
0.16. 55 files did not parse with the 0.17 parser (the `**` operator is gone).

On 2026-10-20, a sample of the findings read true under the rule: `catch {}`
(320), `std.fmt.bufPrint` (247), allocations before a second `try` with a
process-global allocator (85), and real recursion over a JSON tree. One
`try_before_release` sample was an arena named `alloc`.

On 2026-10-21 the new checks first reported 593 `unwrap_assumed` and 341
`enum_else`. Most of the first were `.?` in test blocks, and most of the second
were `else => return error.X` on a `std.json.Value`. Both are now exempt, which
leaves 27 and 217. The `enum_else` that remain are `else => false` predicates
and failures through a helper call.

On 2026-10-21 the third set of checks ran on the same files. `deprecated_api`
reported 1224 uses, 810 of them `std.fmt.allocPrint` (0.17 replaces it with
`Allocator.print`). `posix_assumes_errno` reported 32 calls such as
`std.posix.kill` and `std.posix.setrlimit`. `io_outside_main` fired on
`build.zig` functions named `build`, which now count as an entry point.

On 2026-10-27 the checks for the MISRA C:2025 rules ran on 1,559 `.zig` files
from other projects. `atomic_order` reported 1,232 orderings weaker than
`.seq_cst`; all 8 sampled were atomic operations. `pointer_arith` reported
605, `const_cast` 142, `memcpy_alias` 13, `c_variadic` 10, and
`noalias_param` 2. `memcpy_alias` became `review` after it fired on a
doubling copy whose regions cannot overlap. `lock_twice` first reported 2
functions that unlock in an `errdefer`, which counted as a second lock; with
that fixed it reports none.

## Design

One flat pass over the node array, then one pass per function, then file-wide
passes for opened paths and the call graph. There is no recursive tree walk,
and the call graph walk reuses one scratch array and stack, so the tool keeps
Rule 17.2 itself. `skills/misra-lint-check/SKILL.md` describes how to add a
check.
