---
name: misra-zig-write
description: Write new Zig 0.17 code that follows the MISRA Zig standard from the first draft. Use when writing or changing Zig in a project that follows MISRA Zig, when asked for "safe", "MISRA", or "ReleaseFast-proof" Zig, or when porting C to Zig under the standard. Gives the compliant form for each common task, then checks the result with misra-lint and the compiler.
---

# Write Zig under MISRA Zig

`$MZ` is the MISRA Zig repo: this skill sits at `$MZ/skills/misra-zig-write/`.
The rule text is `$MZ/AGENTS.md`. Every form below is a do sample from
`$MZ/docs/misra-zig-handbook.md`, tested in `$MZ/docs/examples/compliant.zig`.

The test for every line: is it defined in ReleaseFast, where the safety checks
are gone? A panic in Debug is not a pass.

## Compliant forms

| Task | Write | Not | Rule |
|---|---|---|---|
| Add, subtract, multiply values that must fit | `std.math.add(u32, a, b)` and `try` | `a + b` on outside values | Dir 4.1 |
| Wrap or saturate on purpose | `+%`, `-%`, `*%`, `+\|`, `-\|` | `+` and hope | Dir 4.1 |
| Divide by a value from outside | `if (n == 0) return error.DivisionByZero;` first | `total / n` | Dir 4.1 |
| Divide signed values | `std.math.divTrunc(i32, a, b)` | `@divTrunc` on outside values | Dir 4.1 |
| Narrow or change signedness of an outside value | `std.math.cast(u16, x) orelse error.Overflow` | `@intCast(x)` with no check, `@truncate(x)` | Rule 10.3 |
| Shift by an outside amount | compare with `@bitSizeOf` first, then `@intCast` | `x << @intCast(amount)` | Rule 10.1 |
| Integer from a file or wire to an exhaustive enum | `std.enums.fromInt(E, x) orelse error.Unknown` (a non-exhaustive enum accepts every value; `switch` with `_`) | `@fromBackingInt(x)`, which `zig fmt` writes for `@enumFromInt` | Rule 10.5 |
| Float to integer | check finite and in range (`if (!(x >= 0.0 and x < max))`), then `@trunc` | `@trunc` or `@intFromFloat` unchecked | Rule 10.3 |
| Float from outside data | `if (!std.math.isFinite(x)) return error.NotFinite;` before storing or comparing | `x > limit` on a possible NaN; `@setFloatMode(.optimized)` | Dir 4.15 |
| Pass a value to a std function | check its precondition first (`if (i >= list.items.len)`, `if (x == 0)`); read the body for `assert` | `list.orderedRemove(i)`, `std.math.log2_int(T, x)` on outside values | Dir 4.11 |
| Lookup that can miss | `map.get(k) orelse error.Unknown` | `map.get(k).?`, `orelse unreachable` | Dir 4.1 |
| Append without allocating | `ensureUnusedCapacity(gpa, n)` for all n items, then `AssumeCapacity` | an `AssumeCapacity` call with no reserve, or a short one | Dir 4.1 |
| Length or size from outside | compare with a named maximum, then allocate or read; `.limited(max)` | allocate the length as read; `.unlimited` | Dir 4.14 |
| Give a buffer back | write into storage the caller passes in | return `&local` or `local[0..]` | Rule 18.6 |
| Bad input in a library | return an error | `@panic`, `std.debug.panic`, `std.process.exit` outside `main` | Rule 21.8 |
| Not found | return `?T` or an error | `-1`, `std.math.maxInt` (except at a C ABI) | Dir 4.7 |
| A std declaration | the name `misra-lint` suggests (`findScalar`, `std.mem.print`, `Allocator.print`) | anything in `tools/std_lists.zig` `deprecated` | Rule 1.5 |
| An OS call | `std.posix.system.call(...)` and `switch (std.posix.errno(rc))` with an error per errno | a `std.posix` wrapper listed in `posix_assumes_errno` | Dir 4.1 |
| Get an `std.Io` | take `io: std.Io` as a parameter; only `main` builds one | `std.Io.Threaded.init` in a helper | Dir 4.12 |
| Worker threads | a fixed array spawned once at start-up, joined on every path | `spawn` per request, in a `while`, or `detach` | Dir 5.3 |
| Data two threads touch | `std.atomic.Value` or `std.Io.Mutex` | a plain `var` | Dir 5.1 |
| Atomic load, store, or read-modify-write | `.seq_cst` | `.acquire`, `.release`, `.monotonic` | Rule 21.25 |
| Hold two mutexes | one documented order, the same in every function | `a` then `b` here, `b` then `a` elsewhere; locking a mutex you hold | Dir 5.2 |
| Reinterpret bits | `@bitCast` | `@ptrCast` between value pointers | Rule 11.3 |
| Call C | the header translated in `build.zig` | a handwritten `extern fn` | Rule 8.4 |
| Build options | `b.standardOptimizeOption(.{})`, `sanitize_c` left on | `.optimize = .ReleaseFast` | Dir 4.1 |
| A new source file | import it from the test root | a file nothing imports | Rule 2.1 |
| Widen a sum | `std.math.add(u32, a16, b16)` | `@as(u32, a16 + b16)` | Rule 10.6 to 10.8 |
| Validate input | `if (bad) return error.X;` | `std.debug.assert(...)`, `unreachable` | Dir 4.1 |
| One of several values | `union(enum)` and a `switch` | bare `union` | Rule 19.2 |
| Read a tagged union's payload | `switch (v) { .float => \|x\| ... }` | `v.float` | Rule 19.3 |
| Many-item pointer from C | `const items = p[0..len];`, check `len`, index `items` | `p + n`, `q - p` | Rule 18.4 |
| Write through a parameter | take `[]T` or `*T` | `@constCast` on a `[]const T`; `noalias` | Rule 11.8, Rule 8.14 |
| Several values of one type | a slice parameter | a `...` parameter with `@cVaArg` | Rule 17.1 |
| Move bytes inside one buffer | `@memmove(buf[0..rest], buf[n..])` | `@memcpy` between two slices of one buffer | Rule 19.1 |
| Allocate | take `allocator: std.mem.Allocator`; `errdefer allocator.free(buf)` when returning it | `std.heap.page_allocator` in a library | Dir 4.12 |
| Two resources in one function | `defer`/`errdefer` right after each acquire | a second `try` before the first has a release | Rule 22.1 |
| Copy | check `dest.len >= src.len`, then `@memmove(dest[0..src.len], src)` (`@memcpy` only when the two cannot overlap) | `@memcpy(dest[0..n], src[0..n])` | Rule 21.18 |
| Format into a buffer | `std.mem.print(buf, ...)` | `std.fmt.bufPrint` | Rule 21.17 |
| C string in | `std.mem.span(p)` once, at the boundary, on `[*:0]const u8` | `span` over a cast pointer | Rule 21.17 |
| C pointer in | `?*T` on the `export` parameter, `orelse` before use | `*T` from C | Rule 8.2 |
| Fail an `export fn` | return the header's status type, one code per error | an error union (the C ABI cannot return one) | Rule 8.2 |
| Loop that retries | `for (0..max) \|_\|`, then `return error.GaveUp` | `while (true)` | Rule 15.1 |
| Walk a tree | explicit stack with a fixed capacity and a visit bound | recursion | Rule 17.2 |
| Switch on an enum | list every tag; on a value from outside, `else => error.X` is allowed | `else => {}`, `else => false` | Rule 16.4 |
| Mix `and`/`or` or bitwise and arithmetic | parentheses | precedence | Rule 12.1 |
| Container constant | `const max: u32 = 64;` | `const max = 64;` | Dir 4.6, Rule 8.1 |
| Field of a C header struct | `u32`, `u64` in `extern struct`, layout asserted | `usize` | Dir 4.6 |
| Parameter only read | `[]const T`, `*const T` | `[]T` | Rule 8.13 |
| Handle an error | `try`, or `catch \|err\| switch (err) { ... }` | `catch {}`, `catch unreachable` | Dir 4.1 |
| Read errno | clear before the libc call, read right after `== -1` | clear after, or print first | Rule 22.8 to 22.10 |

## Workflow

1. Write the code in the forms above. When a task is not in the table, find
   its rule in `$MZ/AGENTS.md` and copy the handbook's do.
2. Run `zig run -ODebug $MZ/tools/misra_lint.zig -- --root <test root> <files>`
   and fix every finding. An allow comment needs a true reason.
3. Run `zig fmt --check`, and `zig test` at `-ODebug` and `-OReleaseSafe`. Tests
   that allocate use `std.testing.allocator`; cover the error path, not only
   success.
4. For anything that crosses a trust boundary, run the `misra-zig-review` skill
   before calling it done.
