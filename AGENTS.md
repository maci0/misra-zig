# Zig 0.17 coding standard

Rules inspired by MISRA C, applied to Zig 0.17.0. Seven groups. The rules are the ones named below, not the whole of MISRA C, and the ids are MISRA C:2025 numbers. `docs/misra-c-2025.md` places every C:2025 guideline: adopted here, rejected by the compiler, without a Zig counterpart, or left out, with the reason. Worked do and don't samples are in `docs/misra-zig-handbook.md`. Names and whitespace follow the Zig 0.17 language reference style guide: `zig fmt` is the formatter and it has no config file.

A safety check in Debug or ReleaseSafe is not compliance. ReleaseFast and ReleaseSmall delete those checks, and the same operation becomes illegal behavior. Guard the input, or call a function that returns an error. Do not use `@setRuntimeSafety(false)` to quiet a check.

`zig fmt --check` is clean, and `zig test` passes at `-ODebug` and `-OReleaseSafe`, before a change is done. Tests that allocate use `std.testing.allocator`.

## Already rejected by the compiler

These C rules need no extra convention:

- No implicit narrowing. A `u32` does not assign to a `u16`. An arithmetic operator does not mix signedness unless one side coerces: `i32 + u32` is rejected, and `i32 + u16` compiles as an `i32` add. A `u8` does coerce to an `i16`, because every value fits. A `u16` does not coerce to an `i16`. A wider integer type accepts a narrower one of the same signedness. That coercion is not a wider operation: `a + b` for two `u16` values is still a `u16` add when the result is stored in a `u32`.
- `*T` and `[]T` are not null. Null is `?*T` or `?[]T`. A C caller can still pass null to an `export` parameter typed `*T`, so the C boundary takes `?*T` and rejects null before the dereference.
- A `switch` on an enum or tagged union with no `else` must list every tag. With `else` it compiles, so Rule 16.4 limits `else`. Prongs do not fall through. An uncalled function is not analyzed, so a sample that must be rejected is `export`ed.
- Assignment is not an expression, so a condition cannot assign.
- A non-void result cannot be dropped and an error union cannot be ignored: `_ =` discards on purpose, `try` or `catch` handles. Unused locals and parameters, and shadowing, are errors.
- A literal with a leading zero (`010`) is rejected. Octal is `0o10`.
- Code after a `return`, an unused label, an array literal shorter than its type, a field named twice in one literal, two enum tags with one value, a comptime-known value that does not fit its type, a non-void function that can reach its end, a `noreturn` function that returns, an assignment to a parameter, `if (p)` on an optional, and `<` between two pointers are all rejected.
- `allocator.alloc` returns `error.OutOfMemory` instead of a null pointer.
- A slice carries its length. There is no `strcpy`.

## Where a rule departs from the MISRA text

Each group cites the MISRA directive or rule it is inspired by. These do not follow the MISRA text:

- Dir 4.12 and Rule 21.3 forbid dynamic allocation. Here allocation is allowed through an `Allocator` parameter with one release path. A project that must not allocate after start-up keeps the MISRA text.
- Rule 9.2 is about braces in an initializer, which Zig has no partial form of. Here it also carries MISRA Rule 9.3's content: every field and element is written.
- Rule 15.1 forbids `goto`, which Zig does not have. Here it also asks for a bound on every retry loop.
- Rule 8.8 asks for `static` on internal linkage. In Zig that is the absence of `pub`, so here it forbids republishing a file-local function through a `pub` wrapper.

## 1. Types, portability, and arithmetic

MISRA Dir 4.6, Dir 4.15, Rule 8.1, Rules 10.1-10.8.

Widths are explicit. Lengths and indices are `usize`. A value that crosses a file, a socket, or a C header is `u8`, `u16`, `u32`, `u64`, or the matching signed type. `c_int` and `c_long` appear only where the C header uses `int` or `long`: an `export` parameter, an `extern` field, a callback, or an imported declaration.

A file or a wire image is decoded from `[]u8` with a stated endianness. `packed struct` has the ABI of its backing integer, so its byte order is the target's endianness, and a field cannot be an array. A C ABI struct that must match a header is `extern struct`. Assert the layout next to the type. Field widths do not add up to the size. On the x86_64 System V ABI the `u64` below forces 4 bytes of padding, so `@sizeOf` is 16 and `@alignOf` is 8. On a target whose C alignment of a 64-bit integer is 4, the same struct is 12 bytes and the assert fails.

```zig
const Header = extern struct {
    magic: u32,
    size: u64,
};

comptime {
    std.debug.assert(@sizeOf(Header) == 16);
    std.debug.assert(@alignOf(Header) == 8);
}
```

`extern` padding follows the target C ABI. Do not use it for a file format. When a header requires a gap, write those bytes in the `[]u8` decode.

Arithmetic on a runtime integer uses `std.math.add`, `std.math.sub`, or `std.math.mul` when the result must fit. Those return `error.Overflow`.

```zig
fn boundedAdd(a: u32, b: u32) error{Overflow}!u32 {
    return std.math.add(u32, a, b);
}
```

`+`, `-`, and `*` are for values already proven to fit, including `comptime` values. `+%`, `-%`, and `*%` are for an operation whose specified result wraps (a checksum, a hash). `+|` and `-|` are for a specified saturating result. A shift amount from outside the function is compared with `@bitSizeOf` before `<<`. `std.math.shl` truncates and is not that check.

A cast across widths or signedness at a trust boundary is `std.math.cast`, which returns null when the value does not fit:

```zig
fn narrow(wide: u32) error{Overflow}!u16 {
    return std.math.cast(u16, wide) orelse error.Overflow;
}
```

`@truncate` means the low bits are the result. `@bitCast` reinterprets the same width. It is not a numeric conversion. `@intCast` is only legal after a check that proves the value fits, and that check sits in the same function. An integer from outside becomes an enum through `std.enums.fromInt`, which returns null for a value with no tag. `@fromBackingInt` (`zig fmt` rewrites `@enumFromInt` to it) is for a value already proven to be a tag. A non-exhaustive enum (`_`) accepts every value of its backing type, so its `switch` handles the unknown values. A float becomes an integer (`@trunc`, `@floor`, `@ceil`, `@round`) only after a check that it is finite and in range; a safe build does not catch every bad value (NaN gave 0 in a 0.17.0 Debug run).

A float computed from outside data passes `std.math.isFinite` before it is stored, compared, or converted. Every comparison with NaN is false, so `x > limit` lets NaN through. `@setFloatMode(.optimized)` is not used: it lets the compiler assume no operand or result is NaN or infinite.

Signed division is `std.math.divTrunc`, `std.math.divFloor`, `std.math.divCeil`, or `std.math.divExact`. Each returns `error.DivisionByZero` or `error.Overflow`, and `std.math.divExact` also returns `error.UnexpectedRemainder`. The overflow case is the minimum signed value divided by `-1`. `@divExact`, `@shlExact`, and `@shrExact` assume instead of checking; `std.math.divExact` and `std.math.shlExact` return the error. `/` does not compile for two runtime signed integers. Unsigned `/` still faults on zero in safe modes and is illegal behavior in ReleaseFast.

```zig
fn signedQuotient(a: i32, b: i32) error{ DivisionByZero, Overflow }!i32 {
    return std.math.divTrunc(i32, a, b);
}
```

## 2. Initialization, pointers, and unions

MISRA Dir 4.1, Rule 8.13, Rule 8.14, Rule 9.1, Rule 9.2, Rule 11.3, Rule 11.8, Rule 18.4, Rule 18.6, Rule 19.2, Rule 19.3.

`undefined` may be stored and may not be read. `allocator.alloc` returns undefined bytes. Write every element, or `@memset`, before a read. `std.mem.zeroes(T)` is the zero value. Wipe a secret with `std.crypto.secureZero`, not `@memset`: a dead store can be deleted.

A parameter that is not mutated is `[]const T` or `*const T`. `@constCast` and `@volatileCast` are not used, except at one C call whose header leaves `const` off a parameter the function only reads, with an allow comment that names the header. `noalias` is not used: nothing checks it, and a caller that passes one object twice gets a result that changes with the build mode. A pointer or a slice into a local does not outlive the call: return the value, or write into storage the caller passes in. Nothing checks this in any build mode.

`.?` is `orelse unreachable`. A lookup keyed by outside data uses `orelse` with an error. An `AssumeCapacity` call follows a reserve (`ensureUnusedCapacity`, `initCapacity`) for every item it adds, in the same function.

Unwrap an optional before use. A many-item pointer (`[*]T`, `[*:0]T`) has no length. The function that learns the length turns it into a slice, and later functions take the slice. `+` and `-` do not take a many-item or C pointer: nothing checks where the result points.

```zig
fn lenOf(p: ?[]const u8) usize {
    const s = p orelse return 0;
    return s.len;
}
```

`[*c]T` and `allowzero` stay in the file that talks to C. Convert to `[]T` or `?*T` there. Coercing a `[*c]T` of address 0 to `*T` is a safety-checked fault in Debug and illegal behavior in ReleaseFast. A union that holds one of several values is `union(enum)`, and its payload is read through a `switch` capture or after a test of the tag. A bare `union` is not used. Reading a field other than the stored one is illegal behavior in ReleaseFast, tagged or not. `extern union` and `packed union` are for a C header or a register layout, in the file that talks to it.

A pointer to one object type is not cast to a pointer to another; a value is reinterpreted with `@bitCast`. `@ptrCast` to an `extern` or `packed` type is the one expression that overlays a struct on bytes, and only after `slice.len >= @sizeOf(T)`. `@alignCast` follows an alignment test. `@intFromPtr` and `@ptrFromInt` are not a cast between two pointee types. `headerOf` in `docs/examples/compliant.zig` is that check.

## 3. Memory and other resources

MISRA Dir 4.12, Rule 21.3, Rules 22.1-22.10.

The allocator is a parameter, and so is the `std.Io`: only `main` builds a `std.Io.Threaded` (or takes `init.io`), because `Threaded.init` installs process-wide signal handlers. `main` may construct an allocator (`std.heap.page_allocator` as the backing store, `std.heap.SafeAllocator` when the process should detect leaks) and pass it down. A library does not allocate from a global.

`try` is the null check. Every allocation has one release path:

- `defer` when this function always releases the resource.
- `errdefer` when success returns the resource to the caller and failure must release it.

Do not reassign the binding the `defer` closes over. A `defer` registers only when execution reaches it. A failed `try` above that line does not run it.

```zig
fn take(allocator: std.mem.Allocator, n: usize) ![]u8 {
    const buf = try allocator.alloc(u8, n);
    errdefer allocator.free(buf);
    @memset(buf, 0);
    return buf;
}
```

`std.ArrayList(T)` in 0.17 does not store the allocator. Pass it on each call and free with the same one.

```zig
var list: std.ArrayList(u32) = .empty;
defer list.deinit(allocator);
try list.append(allocator, 1);
```

`initCapacity` when the length is known. `toOwnedSlice` moves ownership out and leaves the list empty. Say in the doc comment whether the caller owns the returned slice or it is borrowed for the call. `items` is invalid after the next growth.

A file, socket, or mapping is an `std.Io` resource. Open it through `std.Io` and `std.Io.Dir`, and `defer` the matching `close`. Tests use `std.testing.io`. A mutex is `std.Io.Mutex`:

```zig
var mu: std.Io.Mutex = .init;
try mu.lock(io);
defer mu.unlock(io);
```

`lock` returns `error.Canceled` without holding the mutex. The `defer` is registered only after `lock` returns, so a failed lock is not unlocked. `unlock` on a mutex that was not taken is illegal.

With `-lc`, `std.posix` calls libc and `std.Io` can too. Either one may replace `errno`. Read `errno` before any later call, including an `std.Io` call.

## 4. Functions and linkage

MISRA Dir 4.7, Dir 4.11, Rule 1.5, Rule 8.2, Rule 8.4, Rule 8.7, Rule 8.8, Rule 17.1, Rule 17.2, Rule 21.8.

Failure and not-found are an error or `?T`, and the caller handles them. An in-band value (`-1`, `std.math.maxInt`) is used only where a C ABI requires it.

A declaration the 0.17 std marks deprecated is not used. `tools/std_lists.zig` lists every one, generated from the installed std by `bun scripts/gen_std_lists.ts`.

A declaration without `pub` is file scope, the Zig form of C's `static`. `pub` makes it visible to other Zig files and creates no linker symbol. `export fn` is the C ABI: the parameter types and the `extern struct` layouts match the header, and the return type is the header's type, not `usize` standing in for `uint32_t`. A C function comes from the header translated in `build.zig` (`addTranslateC`); a handwritten `extern fn` is for an ABI no header exposes, with a comment that names it.

Every parameter has a name and a type. `anytype` is for a generic whose body rejects a bad type at compile time. It is not on an `export` function.

Inferred error sets (`!T`) are the default inside a module. Name the set wherever the caller branches on which error it is. An `export` function cannot return an error union: it returns the header's status type and maps each error to a code. `anyerror` is not a return type. `try` propagates. `catch {}` and `catch unreachable` are not error handling. `unreachable` is unchecked illegal behavior if it runs. Use it when a local invariant already proves the path is dead, not when outside data is merely unexpected. `std.debug.assert` is `if (!ok) unreachable`: it states an invariant this module already proves. It never validates input from a caller, a file, or C. A `std.posix` wrapper that maps an errno to `unreachable` (listed in `tools/std_lists.zig`) is called through `std.posix.system` with a `switch` on `std.posix.errno` instead. The build that ships does not hard-code `.ReleaseFast` or `.ReleaseSmall` and keeps `sanitize_c` on. An update to two structures reserves capacity in both before the first change. Only `main` ends the process: a library returns an error instead of calling `@panic`, `std.debug.panic`, or `std.process.exit`.

A value passed to a std function meets that function's preconditions, and the caller checks it first. Many std functions assert an argument instead of returning an error (`orderedRemove`, `std.math.log2_int`), and the doc comment does not always say so: read the body. No variadic function is defined: `@cVaStart` reads arguments that nothing counts or types. Take a slice.

No runtime recursion. A tree or a chain is a loop, an explicit stack with a fixed capacity, and a separate bound on how many nodes the loop visits. A cycle does not grow the stack, so the visit bound is what stops it. Recursion that exists only at `comptime`, to build a type, is allowed. That is not a recursive algorithm, and `@setEvalBranchQuota` still bounds the compiler.

## 5. Control flow

MISRA Rule 2.1, Rule 12.1, Rule 13.4, Rule 14.4, Rule 15.1, Rule 16.3, Rule 16.4.

Every source file is reachable from the test root through `@import`; Zig analyzes only what is referenced. `misra-lint --root ROOT FILE...` reports a FILE the root does not reach.

`if` and `while` take a `bool`, an optional, or an error union. They do not take an integer. `for` walks a slice, an array, or a range. A bare integer is not one of those.

An enum or tagged-union `switch` lists every tag. `else` is for an integer, or for a non-exhaustive enum, and that prong returns an error or handles the unknown value. On an exhaustive enum or tagged union whose value comes from outside (a `std.json.Value`), an `else` that returns an error is allowed: a new tag is refused at run time, not swallowed. An empty `else => {}` hides a new tag. Combine values in one prong with a comma. There is no fallthrough.

```zig
const Color = enum { red, blue };

fn nameOf(c: Color) []const u8 {
    return switch (c) {
        .red => "red",
        .blue => "blue",
    };
}
```

Parenthesize a mix of `and` and `or`. Parenthesize a mix of bitwise and arithmetic.

There is no `goto`. Release is `defer` and `errdefer`. A labeled `break` leaves a block. A retry loop has a bound and returns an error when the bound is hit.

## 6. Buffers and strings

MISRA Dir 4.14, Rule 19.1, Rule 21.17, Rule 21.18.

Zig text is `[]const u8`: pointer and length, no terminator. A C string is `[*:0]const u8` or `[:0]const u8`, and `std.mem.span` converts it once, at the boundary.

```zig
fn fromC(p: [*:0]const u8) []const u8 {
    return std.mem.span(p);
}
```

Format into a caller-supplied buffer with `std.mem.print`. The buffer is too small when the result is `error.NoSpaceLeft`. Nothing is written past `buffer.len`. `std.mem.printSentinel` when the callee needs a `[:0]u8`. `std.fmt.bufPrint` is deprecated.

```zig
fn render(n: u32) error{NoSpaceLeft}!u8 {
    var buf: [16]u8 = undefined;
    const s = try std.mem.print(&buf, "{d}", .{n});
    return s[0];
}
```

`@memcpy` copies equal lengths that do not overlap. `@memmove` copies equal lengths that might: a move inside one buffer uses it, and so does a helper that takes two slices from its caller. `std.mem.copyForwards` and `std.mem.copyBackwards` are deprecated. Compare with `std.mem.eql` and `std.mem.startsWith`.

A value from outside sizes nothing until it is checked: a length field is compared with a named maximum before it sizes an allocation, a read, or a loop, and a read limit is `.limited(max)`, never `.unlimited`. A list or map that grows once per request, peer, or loop pass has a named cap and returns an error at it.

An index or a slice from outside is checked against `len` before use. The built-in bounds check is absent in ReleaseFast. A sentinel slice (`[:0]u8`) owns its trailing zero. Do not store a zero one past a `[]u8`.

End of file from `readStreaming` is `error.EndOfStream`. A returned length of 0 is not end of file. Do not map the error onto 0.

## 7. Threads, locks, and atomics

MISRA Dir 5.1, Dir 5.2, Dir 5.3, Rule 21.25.

Threads are created at start-up, a fixed number of them, and every one is joined once. No thread is spawned per request or inside a `while` loop, and none is detached. Data written by one thread and read by another goes through `std.Io.Mutex` or `std.atomic.Value`; a plain shared variable is a data race, which is illegal behavior. Every atomic operation is `.seq_cst`.

A function that holds two mutexes takes them in one documented order, the same in every function that takes both. A thread does not lock a mutex it already holds: `std.Io.Mutex` is not recursive, and the second `lock` waits forever.

## Layout, names, comments

From the Zig 0.17 style guide. `zig fmt` is mandatory.

- 4 spaces, no tabs, LF, UTF-8. The opening brace stays on the same line. A list longer than two items gets one item per line and a trailing comma. Aim at 100 columns and let `zig fmt` wrap.
- Functions are `camelCase`. Types and functions that return a type are `TitleCase`. Variables, fields, and constants are `snake_case`.
- A file that is only a namespace is `snake_case.zig`. A file whose top level is a struct with fields is `TitleCase.zig`. Directories are `snake_case`.
- An acronym is an ordinary word: `readU32Be`, `XmlParser`, `xml_document`.
- No `_prefixed` privacy, and no `utils` or `misc` module. Pick a name from the fully qualified path and do not repeat a segment the path already has (`json.Value`, not `json.JsonValue`).
- `///` documents the contract: what is returned, who frees it, and how long a borrowed slice lives. "Assert" means the check is safety-checked. "Assume" means a broken invariant is unchecked illegal behavior. Leave out a sentence that only repeats the function name.

## Checks

```bash
zig fmt --check .
zig test -lc -ODebug docs/examples/compliant.zig
zig test -lc -OReleaseSafe docs/examples/compliant.zig
zig test -ODebug tools/misra_lint.zig
zig test -OReleaseSafe tools/misra_lint.zig
bun test scripts/
bun scripts/check_samples.ts
vnu --format text site/index.html
vnu --css --format text site/site.css
```

There is no `build.zig`. `zig test` needs the file. `-lc` is required because the file calls libc. `std.testing.allocator` fails the test on a leak, a double free, or a free of memory it did not hand out. `std.testing.checkAllAllocationFailures` covers a function that allocates more than once. ReleaseFast is not the compliance build.

`bun test scripts/` builds misra-lint into `.scratch/bin/` and checks it against the handbook: every do sample lints clean, and every don't marked compiles is flagged under its own rule or listed in `UNDECIDED` in `scripts/lint.test.ts` with what a syntax tree cannot see. `check_samples.ts` compiles every sample and compares the result with its mark.

## misra-lint

`tools/misra_lint.zig` decides the don't patterns a syntax tree can decide, with `std.zig.Ast` and no types. `zig run -ODebug tools/misra_lint.zig -- FILE...` prints `path:line:col: violation[check] Rule N.M: summary`; `--json` prints fields, `--checks` lists every check and its rules, `-` reads stdin. Exit 1 means at least one finding. `// misra-lint: allow <check> <reason>`, in a comment on the finding's line or on a comment-only line above it, silences that finding, and only with a reason. Nesting deeper than 256 levels is reported as `parse_error` instead of parsed. The checker follows this standard and lints itself clean. `--root ROOT FILE...` also reports each FILE the root does not reach through `@import`. `tools/std_lists.zig` (deprecated std declarations, and `std.posix` wrappers with an `=> unreachable` errno prong) is generated by `bun scripts/gen_std_lists.ts` from the installed std; regenerate it when Zig changes, and `bun test scripts/` fails while it is stale. Coverage, severities, and blind spots are in `docs/misra-lint.md`.

## Site

`site/` is the handbook in a browser, set as a component datasheet. The front sheet carries the features, a description, a pin map with one pin per rule in group order, the compiler note last (an odd count leaves the last pin of the package NC), and the pin function table. Each rule sheet has its description, the do and the don't as figures, the evidence for each don't (rejected by the compiler, flagged by misra-lint, or left to a reader), and the misra-lint checks that decide it. "Evaluate a file" checks a whole file. Light and dark follow the OS; the bar's switch stores a choice. Keys: `/` find, `[` and `]` previous and next rule, `Ctrl`+`Enter` check in an editor.

```bash
bun scripts/server.ts
```

Open `http://127.0.0.1:4173`. The process listens on localhost. `PORT` changes the port. `ZIG` chooses the compiler. At start the server builds misra-lint; when that fails the site says so and Check runs the compiler alone. Pages are sent with `cache-control: no-store`, so a refresh shows the files on disk. Check (`POST /api/check`) runs `zig test --test-no-exec -lc -ODebug` and misra-lint on the edited source and returns `status`, `output`, `errors` (compiler errors in source lines), and `findings` (null when misra-lint did not run). `POST /api/lint` returns only `findings`. Zig accepting the file is not compliance: a don't can compile and still be wrong, and a clean misra-lint run is not compliance either.

Published copy: `bun scripts/build_site.ts` writes `build/site`, the static pages plus `handbook.json`, `rules.json`, `checks.json`, and an `api/health` that reports the checker unavailable. `bun --env-file=.secrets x wrangler deploy` publishes it as the Worker `misra-zig` on misra-zig.dev and misra-zig.com (`wrangler.jsonc`). `scripts/worker.ts` runs before the assets: a plain HTTP request gets a 301 to HTTPS, and every request counts against the Workers request quota. The zone setting "Always Use HTTPS" would make the Worker unnecessary, but the OAuth login cannot change zone settings. The published copy never runs a compiler: `POST /api/check` is a 404 there. `.secrets` holds `CLOUDFLARE_ACCOUNT_ID` only, mode 600 and gitignored. wrangler signs in with its OAuth login in `~/.config/.wrangler`, outside the repo, so no API token is stored in the project.

`GET /rules.json` is the same rules as fields: `id`, `number`, `kind`, `group`, `obligation`, `do.zig`, `do.note`, and `dont.cases`. A case is `mark` (`rejected` or `compiles`), `why`, and `zig`. `zig` is empty when that don't has no sample. One rule may have several cases, with the same mark or different marks. The rule sheet shows the same id and marks. `GET /checks.json` is the misra-lint check list: `id`, `severity`, `rules`, `summary`. `/handbook.json` is the page model. `agentRules` in `scripts/handbook.ts` builds the fields from the handbook.

`DESIGN.md` records the datasheet world. `.impeccable/` holds its design sidecar; its review captures, local config, and caches stay out of git.

## Skills

`skills/` holds agent skills; `.claude/skills` links to it.

- `misra-zig-write`: write Zig under this standard, with the compliant form for each common task.
- `misra-zig-review`: review Zig code against this standard. `bun scripts/review.ts FILE...` prints the skeleton: misra-lint findings by rule, then a checklist of every rule, split into rules no check decides and rules decided only in part.
- `misra-zig-rule`: change a rule and keep the handbook, `compliant.zig`, `GROUP_DEFS`, the site, and the tests in step.
- `misra-lint-check`: add or fix a misra-lint check, test first.

## Decisions

A rule still being decided is an RFC in `docs/`, named `rfc-NNN-topic.md`. A decision made is an ADR in `docs/adr/`, listed in `docs/adr/README.md`.

## Ledger

`docs/ledger.md` records every change to a deliverable: date, what, why, evidence, who decided, and how it was verified. Append only.
