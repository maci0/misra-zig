# MISRA Zig handbook

Zig 0.17.0 samples for rules inspired by MISRA C. The rules are the ones named in `AGENTS.md`, not the whole of MISRA C. The wording here is the Zig obligation, not the text of the C standard.

The do blocks are the functions in `docs/examples/compliant.zig`. That file passes:

```bash
zig test -lc -ODebug docs/examples/compliant.zig
zig test -lc -OReleaseSafe docs/examples/compliant.zig
```

`-lc` links libc. The example file needs it for `std.c`. A Don't that calls `std.heap.c_allocator` needs it too, or the compiler rejects that call. A program that never touches libc does not need it.

A don't line is marked **rejected** when Zig 0.17.0 refuses to compile it, and **compiles** when the compiler accepts it and the code is still wrong. Debug and ReleaseSafe insert safety checks. ReleaseFast and ReleaseSmall delete them, and the same operation becomes illegal behavior. A panic in Debug is not a pass.

`+%`, `-%`, and `*%` are wraparound. `+|` and `-|` saturate. Plain `+`, `-`, and `*` trap on overflow in a safe build and are illegal behavior in ReleaseFast and ReleaseSmall.

## Directives

### Dir 4.1

Runtime failure is a returned error, or a check that runs in every optimization mode. `@setRuntimeSafety` does not count. `std.debug.assert` and `unreachable` do not count either: in ReleaseFast and ReleaseSmall a false one is illegal behavior, so each states an assumption, not a check. `orelse unreachable`, `.?`, the `AssumeCapacity` methods, and `@divExact`, `@shlExact`, and `@shrExact` are assumptions in the same way. `std.math.divExact` and `std.math.shlExact` return errors instead. Some `std.posix` wrappers switch on errno with an `=> unreachable` prong, so an errno the OS can return becomes illegal behavior; `tools/std_lists.zig` lists them, generated from the installed std. Those calls go through `std.posix.system` with a `switch` on `std.posix.errno`. The build that ships does not hard-code `.ReleaseFast` or `.ReleaseSmall`, and keeps `sanitize_c` on. An operation that updates two structures reserves capacity in both before the first change, so an error leaves both as they were.

#### Do

```zig
fn boundedAdd(a: u32, b: u32) error{Overflow}!u32 {
    return std.math.add(u32, a, b);
}

fn signedQuotient(a: i32, b: i32) error{ DivisionByZero, Overflow }!i32 {
    return std.math.divTrunc(i32, a, b);
}
```

`@divTrunc` still overflows when the numerator is the minimum `i32` and the divisor is `-1`. `std.math.divTrunc` returns `error.Overflow` for that pair and `error.DivisionByZero` for a zero divisor.

Unsigned `/` cannot overflow, but a zero divisor is still illegal behavior. The divisor is checked in the same function:

```zig
fn perItem(total: u32, count: u32) error{DivisionByZero}!u32 {
    if (count == 0) return error.DivisionByZero;
    return total / count;
}
```

A lookup that can miss returns an error, and an `AssumeCapacity` call follows a reserve for every item it adds:

```zig
fn priceOf(prices: *const std.StringHashMapUnmanaged(u32), name: []const u8) error{UnknownItem}!u32 {
    return prices.get(name) orelse error.UnknownItem;
}

fn pushPair(gpa: std.mem.Allocator, list: *std.ArrayList(u32), a: u32, b: u32) !void {
    try list.ensureUnusedCapacity(gpa, 2);
    list.appendAssumeCapacity(a);
    list.appendAssumeCapacity(b);
}
```

A socket option set through the system call, with every errno an error:

```zig
fn setReuse(fd: std.posix.socket_t) error{ InvalidOption, Unexpected }!void {
    const one: c_int = 1;
    const rc = std.posix.system.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&one), @sizeOf(c_int));
    return switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        .INVAL, .NOPROTOOPT => error.InvalidOption,
        else => error.Unexpected,
    };
}
```

A C or untrusted byte slice is checked before a pointer cast. `headerOf` rejects a short buffer and a misaligned address, then `@alignCast` and `@ptrCast`.

```zig
fn headerOf(bytes: []const u8) error{ Truncated, Misaligned }!*const Header {
    if (bytes.len < @sizeOf(Header)) return error.Truncated;
    if (!std.mem.isAligned(@intFromPtr(bytes.ptr), @alignOf(Header))) return error.Misaligned;
    const aligned: [*]align(@alignOf(Header)) const u8 = @alignCast(bytes.ptr);
    return @ptrCast(aligned);
}
```

#### Don't

**Compiles.** The safety switch deletes the overflow check on `+=` in every build mode, including Debug. `+%` is the wrong sample: wrapping addition has no check to delete.

```zig
fn bump(x: *u8) void {
    @setRuntimeSafety(false);
    x.* += 1;
}
```

**Compiles.** `std.debug.assert` is `if (!ok) unreachable`. `i` comes from the C caller, and in ReleaseFast a false assert lets the read leave the buffer.

```zig
export fn at(buf: [*]const u8, len: usize, i: usize) u8 {
    std.debug.assert(i < len);
    return buf[i];
}
```

**Compiles.** A zero `count` panics in a safe build and is illegal behavior in ReleaseFast and ReleaseSmall.

```zig
fn perItemUnchecked(total: u32, count: u32) u32 {
    return total / count;
}
```

**Compiles.** `.?` is `orelse unreachable`. A name that is not in the map panics in a safe build and is illegal behavior in ReleaseFast and ReleaseSmall.

```zig
fn priceUnchecked(prices: *const std.StringHashMapUnmanaged(u32), name: []const u8) u32 {
    return prices.get(name).?;
}
```

**Compiles.** The reserve is for one item and two are appended. `ensureUnusedCapacity` may grow by more than it was asked, so a test can pass. With `initCapacity(gpa, 1)` the second append fails the capacity assertion in Debug, and in ReleaseFast it is illegal behavior.

```zig
fn pushShort(gpa: std.mem.Allocator, list: *std.ArrayList(u32), a: u32, b: u32) !void {
    try list.ensureUnusedCapacity(gpa, 1);
    list.appendAssumeCapacity(a);
    list.appendAssumeCapacity(b);
}
```

**Compiles.** In Zig 0.17.0 `std.posix.setsockopt` maps `EINVAL` to `unreachable`, so an option the kernel refuses is illegal behavior in ReleaseFast.

```zig
fn setReuseAssumed(fd: std.posix.socket_t) !void {
    const one: c_int = 1;
    try std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&one));
}
```

**Compiles.** The build that ships has no safety checks at all, whatever `-Doptimize` says.

```zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    b.installArtifact(exe);
}
```

### Dir 4.6

A numeric value that means a size, a count, or a wire field names its width and its signedness. `usize` is for lengths and indices. `c_int` and `c_long` appear only where the C header says `int` or `long`.

#### Do

```zig
pub const block_size: u32 = 512;
```

`Header` is an `extern struct` because it has to match a C header. On the x86_64 System V ABI the `u64` forces 4 bytes of padding, so the size is 16 and the alignment is 8. On a target whose C alignment of a 64-bit integer is 4, the same struct is 12 bytes and the assert fails. A file format is an explicit decode from `[]u8` with a stated endianness. `packed struct` has the ABI of its backing integer, so its byte order is the target endianness, and a field cannot be an array. `extern` padding follows the target C ABI, so it is not a file format either.

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

#### Don't

**Compiles.** `comptime_int` has no width. A later use can be 32 bits on one call and 64 on the next.

```zig
pub const block_size = 512;
```

**Compiles, still the wrong width.** A `u32` field in a header is not a `usize`.

```zig
const Disk = extern struct {
    blocks: usize,
};
```

### Dir 4.7

Failure and not-found are reported as an error or as `?T`, and the caller handles them. An in-band value (`-1`, `std.math.maxInt`, an empty slice that means "absent") is not used, except where a C ABI requires it.

#### Do

```zig
fn find(items: []const u32, x: u32) ?usize {
    for (items, 0..) |item, i| {
        if (item == x) return i;
    }
    return null;
}
```

#### Don't

**Compiles.** A caller that forgets the test indexes with `maxInt(usize)`, which is past the end of any slice.

```zig
fn findOrMax(items: []const u32, x: u32) usize {
    for (items, 0..) |item, i| {
        if (item == x) return i;
    }
    return std.math.maxInt(usize);
}
```

### Dir 4.11

A value passed to a std function meets that function's preconditions, and the caller checks it first. Many std functions assert an argument instead of returning an error, and in ReleaseFast a false assert is illegal behavior. A doc comment that says "Asserts" names such a precondition, but not every one is named: `std.math.log2_int` asserts `x != 0` in its body and its doc comment does not say so. Read the body before passing a std function a value from outside.

#### Do

```zig
fn bitWidth(x: u32) error{Zero}!u5 {
    if (x == 0) return error.Zero;
    return std.math.log2_int(u32, x);
}

fn removeAt(list: *std.ArrayList(u32), i: usize) error{OutOfRange}!u32 {
    if (i >= list.items.len) return error.OutOfRange;
    return list.orderedRemove(i);
}
```

#### Don't

**Compiles.** `log2_int` asserts that `x` is not zero. A zero panicked with `reached unreachable code` in a 0.17.0 Debug run and crashed a ReleaseFast run.

```zig
fn bitWidthUnchecked(x: u32) u5 {
    return std.math.log2_int(u32, x);
}
```

**Compiles.** `orderedRemove` asserts that the index is in bounds. An index past the end panicked in a 0.17.0 Debug run and crashed a ReleaseFast run.

```zig
fn removeUnchecked(list: *std.ArrayList(u32), i: usize) u32 {
    return list.orderedRemove(i);
}
```

### Dir 4.12

Allocation goes through an `Allocator` argument. The function that allocates either frees on every path or returns the memory and documents that the caller owns it. The `std.Io` is a parameter too: only `main` builds a `std.Io.Threaded` (or takes `init.io`), because `Threaded.init` installs process-wide signal handlers.

#### Do

```zig
fn take(allocator: std.mem.Allocator, n: usize) ![]u8 {
    const buf = try allocator.alloc(u8, n);
    errdefer allocator.free(buf);
    @memset(buf, 0);
    return buf;
}
```

#### Don't

**Compiles.** A library that allocates from `std.heap.c_allocator` or `std.heap.page_allocator` hides the owner. The caller cannot use one allocator for the whole call, and a test cannot see the leak.

```zig
fn hidden(n: usize) ![]u8 {
    return std.heap.page_allocator.alloc(u8, n);
}
```

**Compiles.** Every call builds an `std.Io` and installs signal handlers for the whole process.

```zig
fn logLine(msg: []const u8) !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    try std.Io.File.stdout().writeStreamingAll(threaded.io(), msg);
}
```

### Dir 4.14

A value from outside (a file, a socket, a C caller) is checked before it sizes an allocation, a read, or a loop. A length field is compared with a named maximum first. A read limit is `.limited(max)`, never `.unlimited`. A list or map that grows once per request, peer, or loop pass has a named cap and returns an error at it.

#### Do

```zig
const max_frame_bytes: u32 = 64 * 1024;
const max_config_bytes: usize = 64 * 1024;

fn frameBody(gpa: std.mem.Allocator, len: u32) ![]u8 {
    if (len > max_frame_bytes) return error.FrameTooLarge;
    return gpa.alloc(u8, len);
}

fn readConfig(dir: std.Io.Dir, io: std.Io, gpa: std.mem.Allocator) ![]u8 {
    return dir.readFileAlloc(io, "config", gpa, .limited(max_config_bytes));
}
```

#### Don't

**Compiles.** The file chooses how much memory this allocates.

```zig
fn readConfigUnbounded(dir: std.Io.Dir, io: std.Io, gpa: std.mem.Allocator) ![]u8 {
    return dir.readFileAlloc(io, "config", gpa, .unlimited);
}
```

### Dir 4.15

A float computed from outside data is checked with `std.math.isFinite` before it is stored, compared, or converted. A zero divisor or an overflow gives an infinity, `0.0 / 0.0` gives NaN, and every comparison with NaN is false, so a range check such as `x > limit` lets NaN through. `@setFloatMode(.optimized)` is not used: in that mode the compiler may assume no operand or result is NaN or infinite, and the language reference calls the result undefined. A float that becomes an integer also follows Rule 10.3.

#### Do

```zig
fn mean(sum: f64, count: u32) error{ Empty, NotFinite }!f64 {
    if (count == 0) return error.Empty;
    const m = sum / @as(f64, @floatFromInt(count));
    if (!std.math.isFinite(m)) return error.NotFinite;
    return m;
}
```

#### Don't

**Compiles.** A NaN reading is never over the limit. In a 0.17.0 run, a NaN compared false with `< 1.0` and with `>= 1.0`.

```zig
fn overLimit(reading: f64, limit: f64) bool {
    return reading > limit;
}
```

**Compiles.** `.optimized` lets the compiler assume `b` is not zero and the quotient is finite. A zero `b` panicked with `division by zero` in a 0.17.0 Debug run. ReleaseFast has no check.

```zig
fn ratio(a: f64, b: f64) f64 {
    @setFloatMode(.optimized);
    return a / b;
}
```

### Dir 5.1

Data written by one thread and read by another goes through `std.Io.Mutex` or `std.atomic.Value`. A plain variable shared between threads is a data race, which is illegal behavior.

#### Do

```zig
fn work(hits: *std.atomic.Value(u64)) void {
    _ = hits.fetchAdd(1, .seq_cst);
}
```

#### Don't

**Compiles.** Two workers that call `countHit` race on `hits`.

```zig
var hits: u64 = 0;

fn countHit() void {
    hits += 1;
}
```

### Dir 5.2

Threads do not deadlock. A function that holds two mutexes takes them in one documented order, and every function that takes both uses that order. A thread does not lock a mutex it already holds: `std.Io.Mutex` is not recursive.

#### Do

```zig
const Account = struct {
    id: u32,
    balance: u64,
    mu: std.Io.Mutex = .init,
};

/// Takes the two locks in ascending `id` order, the order every caller uses.
fn transfer(io: std.Io, from: *Account, to: *Account, amount: u64) !void {
    if (from.id == to.id) return error.SameAccount;
    const first = if (from.id < to.id) from else to;
    const second = if (from.id < to.id) to else from;
    try first.mu.lock(io);
    defer first.mu.unlock(io);
    try second.mu.lock(io);
    defer second.mu.unlock(io);
    const debited = try std.math.sub(u64, from.balance, amount);
    const credited = try std.math.add(u64, to.balance, amount);
    from.balance = debited;
    to.balance = credited;
}
```

`transfer` computes both balances before it writes either, so an error leaves both accounts as they were (Dir 4.1).

#### Don't

**Compiles.** One thread calls `lockBoth(io, &x, &y)` and another calls `lockBoth(io, &y, &x)`. Each can take its first mutex and then wait forever for the other's.

```zig
fn lockBoth(io: std.Io, a: *std.Io.Mutex, b: *std.Io.Mutex) !void {
    try a.lock(io);
    defer a.unlock(io);
    try b.lock(io);
    defer b.unlock(io);
}
```

**Compiles.** The second `lock` waits for the first, which this thread holds. A 0.17.0 run hung in Debug and in ReleaseFast.

```zig
fn relock(io: std.Io, mu: *std.Io.Mutex) !void {
    try mu.lock(io);
    defer mu.unlock(io);
    try mu.lock(io);
    defer mu.unlock(io);
}
```

### Dir 5.3

Threads are created at start-up, a fixed number of them, and every one is joined once. No thread is spawned per request or inside a `while` loop, and none is detached. A second `join` of the same `std.Thread` segfaulted a 0.17.0 run in Debug and in ReleaseFast.

#### Do

```zig
const max_workers: usize = 4;

fn work(hits: *std.atomic.Value(u64)) void {
    _ = hits.fetchAdd(1, .seq_cst);
}

pub fn main() !void {
    var hits: std.atomic.Value(u64) = .init(0);
    var workers: [max_workers]std.Thread = undefined;
    var started: usize = 0;
    defer for (workers[0..started]) |w| w.join();
    for (&workers) |*w| {
        w.* = try std.Thread.spawn(.{}, work, .{&hits});
        started += 1;
    }
}
```

`started` counts the threads that exist, so a failed `spawn` joins only those.

#### Don't

**Compiles.** One thread per connection, never joined: the count follows the input, and nothing waits for them to finish.

```zig
fn serveAll(conns: []const u32) !void {
    for (conns) |conn| {
        const t = try std.Thread.spawn(.{}, handle, .{conn});
        t.detach();
    }
}

fn handle(conn: u32) void {
    _ = conn;
}
```

## Rules

### Rule 1.5

A declaration the Zig 0.17 standard library marks deprecated is not used. misra-lint checks every one, from a list generated out of the installed std (`tools/std_lists.zig`).

#### Do

```zig
fn colon(s: []const u8) ?usize {
    return std.mem.findScalar(u8, s, ':');
}
```

#### Don't

**Compiles.** `indexOfScalar` is deprecated in favor of `findScalar`, and a later release may remove it.

```zig
fn colonOld(s: []const u8) ?usize {
    return std.mem.indexOfScalar(u8, s, ':');
}
```

### Rule 2.1

Every source file is reachable from the test root through `@import`. Zig analyzes only what is referenced, so a file nothing imports is never type-checked. `misra-lint --root ROOT FILE...` reports each FILE the root does not reach.

#### Do

The test root names every file: `test { _ = @import("parser.zig"); }`.

#### Don't

**Compiles.** A `parser.zig` that nothing imports is never analyzed, so the tests pass while it holds a type error.

### Rule 8.1

The type is written on a container-level declaration, and on any declaration whose value is a literal. A local may take its type from a typed expression: a call, a typed name, or an operation on typed values.

#### Do

```zig
pub const block_size: u32 = 512;

fn blocksFor(bytes: u64) u64 {
    const whole = bytes / block_size;
    return whole + @intFromBool(bytes % block_size != 0);
}
```

`whole` is inferred, and its type is the `u64` of `bytes`, named on the line above.

#### Don't

**Rejected.** A `var` with a literal and no type is `comptime_int`, which has no runtime width.

```zig
export fn f() u32 {
    var n = 0;
    n += 1;
    return n;
}
```

**Compiles.** Dropping the type on a public constant is the same hole as a bare `int` in C. See Dir 4.6.

### Rule 8.2

A function has a prototype: every parameter has a name and a concrete type. `anytype` is for a generic whose body rejects a bad type at compile time. It is not how an `export` function talks to C.

#### Do

```zig
export fn diskSize(blocks: u32, block_size_bytes: u32, out: ?*u32) c_int {
    const dest = out orelse return 1;
    dest.* = std.math.mul(u32, blocks, block_size_bytes) catch return 1;
    return 0;
}
```

The status is `c_int` because the header says `int`. The sizes stay `u32` because the header says `uint32_t`. `out` is optional because a C caller can pass null. Null returns 1 and is not dereferenced.

#### Don't

**Compiles.** The names say nothing, and `anytype` will accept a `u64` offset at one call site and a pointer at another.

```zig
fn readAt(a: anytype, b: anytype) void {
    _ = a;
    _ = b;
}
```

### Rule 8.4

An `export` function has one signature, and it is the signature in the header. Callers inside Zig call the `pub` function. There is no second handwritten prototype. A C function comes from the header translated in `build.zig` (`addTranslateC`); a handwritten `extern fn` is for an ABI no header exposes, with a comment that names it.

#### Do

`diskSize` above is the declaration and the definition.

#### Don't

**Compiles.** The comment says `uint32_t`. The parameter is `usize`. On a 64-bit target those are different types, and the C caller will pass 32 bits.

```zig
// uint32_t blocks
export fn diskBlocks(blocks: usize) void {
    _ = blocks;
}
```

**Compiles.** The declaration is a second copy of `unistd.h`. If the header changes, nothing compares the two.

```zig
extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
```

### Rule 8.7

A function used in one file is not `pub`.

#### Do

`boundedAdd`, `take`, and `sumTree` have no `pub`. A test in the same file can call them. Another file cannot.

#### Don't

**Compiles.** `pub` on a helper used only in this file makes it visible to other Zig files. It does not create a linker symbol. `export` does that. It becomes API, and a later edit has to keep it stable.

```zig
pub fn helperOnlyThisFileUses(n: u32) u32 {
    return n + 1;
}
```

### Rule 8.8

Internal linkage is the absence of `pub` and `export` on that one declaration. Do not add a public alias that publishes it again.

#### Do

```zig
fn checksum(data: []const u8) u8 {
    var sum: u8 = 0;
    for (data) |b| sum +%= b;
    return sum;
}
```

#### Don't

**Compiles.** The wrapper publishes a file-local function to other Zig files. `pub` is visibility, not a second linker symbol.

```zig
fn checksum(data: []const u8) u8 {
    _ = data;
    return 0;
}

pub fn checksumPub(data: []const u8) u8 {
    return checksum(data);
}
```

### Rule 8.13

A pointer or a slice that the function does not write is `const`.

#### Do

```zig
fn checksum(data: []const u8) u8 {
    var sum: u8 = 0;
    for (data) |b| sum +%= b;
    return sum;
}
```

#### Don't

**Compiles.** `[]u8` says the function may write. A caller with `[]const u8` cannot pass the data, and a caller who can will not know whether the buffer comes back changed.

```zig
fn checksum(data: []u8) u8 {
    var sum: u8 = 0;
    for (data) |b| sum +%= b;
    return sum;
}
```

### Rule 8.14

`noalias` is not used. It promises the compiler that no other pointer reaches the same memory during the call, and nothing checks the promise in any build mode. A caller that breaks it gets a result that changes with the optimization mode.

#### Do

```zig
fn addTwice(total: *u32, step: *const u32) error{Overflow}!void {
    total.* = try std.math.add(u32, total.*, step.*);
    total.* = try std.math.add(u32, total.*, step.*);
}
```

`addTwice(&x, &x)` is defined: the second read of `step` sees the first write.

#### Don't

**Compiles.** Called as `addTwiceNoalias(&x, &x)` with `x` at 1, a 0.17.0 Debug build gave 4, and ReleaseSafe and ReleaseFast gave 3.

```zig
fn addTwiceNoalias(noalias total: *u32, noalias step: *const u32) error{Overflow}!void {
    total.* = try std.math.add(u32, total.*, step.*);
    total.* = try std.math.add(u32, total.*, step.*);
}
```

### Rule 9.1

`undefined` may be stored. It may not be read. `allocator.alloc` returns undefined bytes. Write them, or `@memset`, before a read. Wipe a secret with `std.crypto.secureZero`. A plain `@memset` of a dead buffer can be deleted.

#### Do

```zig
fn take(allocator: std.mem.Allocator, n: usize) ![]u8 {
    const buf = try allocator.alloc(u8, n);
    errdefer allocator.free(buf);
    @memset(buf, 0);
    return buf;
}

fn wipe(buf: *[32]u8) void {
    std.crypto.secureZero(u8, buf);
}
```

The stack in `sumTree` is `undefined` and the first write is `stack[0] = root` before any read. Each later read is a slot written on an earlier iteration.

#### Don't

**Compiles.** `flag == false` returns an unread `u32`. Safe builds do not always catch this.

```zig
fn value(flag: bool) u32 {
    var x: u32 = undefined;
    if (flag) x = 1;
    return x;
}
```

### Rule 9.2

Every field of a struct literal is written. An array is a full value, `@memset`, or `std.mem.zeroes`. There is no C `{0}` that fills the tail.

#### Do

```zig
const root = Node{ .value = 1, .left = null, .right = &right };
var raw align(8) = std.mem.zeroes([16]u8);
```

#### Don't

**Compiles.** `size` is never stored. The return reads undefined padding and an undefined field.

```zig
fn blank() Header {
    var header: Header = undefined;
    header.magic = 1;
    return header;
}
```

### Rule 10.1

An operator gets an operand of the right kind. `and` and `or` take `bool`. A shift amount is an unsigned integer in range. A boolean is not an integer, and an integer is not a condition.

#### Do

```zig
fn both(ready: bool, allowed: bool) bool {
    return ready and allowed;
}

fn shift(value: u32, amount: u32) error{Overflow}!u32 {
    if (amount >= @bitSizeOf(u32)) return error.Overflow;
    return value << @as(std.math.Log2Int(u32), @intCast(amount));
}
```

#### Don't

**Rejected.** `if` does not take a `u32`.

```zig
export fn f(n: u32) u32 {
    if (n) return 1;
    return 0;
}
```

**Rejected.** `i32` and `u32` do not add.

```zig
export fn f(a: i32, b: u32) u32 {
    return a + b;
}
```

**Compiles.** `amount` from the caller goes straight into `@intCast`. 32 or more panics in a safe build and is illegal behavior in ReleaseFast and ReleaseSmall. The do checks it against `@bitSizeOf` first.

```zig
fn shiftUnchecked(value: u32, amount: u32) u32 {
    return value << @intCast(amount);
}
```

### Rule 10.2

A byte that means a character is not incremented or decremented as if the encoding were arithmetic. Convert a small integer to a digit only after the value is in range.

#### Do

```zig
fn decimalDigit(n: u8) error{Overflow}!u8 {
    if (n > 9) return error.Overflow;
    return '0' + n;
}
```

#### Don't

**Compiles.** `c + 1` is the next integer, not the next character. At 255 it panics in a safe build and is illegal behavior in ReleaseFast and ReleaseSmall.

```zig
fn nextByte(c: u8) u8 {
    return c + 1;
}
```

### Rule 10.3

A value from outside the function is not forced into a narrower type or a different signedness. `std.math.cast` returns null when it does not fit. `@truncate` means the low bits are the result you want. `@bitCast` reinterprets the same width. It is not a conversion. A float becomes an integer (`@trunc`, `@floor`, `@ceil`, or `@round` with an integer result) only after a check that it is finite and in range. `@intFromFloat` is deprecated in 0.17 and means `@trunc`.

#### Do

```zig
fn narrow(wide: u32) error{Overflow}!u16 {
    return std.math.cast(u16, wide) orelse error.Overflow;
}

fn toMillis(seconds: f64) error{OutOfRange}!u32 {
    const ms = seconds * 1000.0;
    if (!(ms >= 0.0 and ms < 4294967296.0)) return error.OutOfRange;
    return @trunc(ms);
}
```

NaN fails both comparisons, so it takes the error path.

#### Don't

**Rejected.** The implicit narrowing is the C bug.

```zig
export fn f(a: u32) u16 {
    return a;
}
```

**Compiles.** `@truncate` silences that error and keeps the low 16 bits. `0x1_0000` becomes 0.

```zig
export fn f(a: u32) u16 {
    return @truncate(a);
}
```

**Compiles.** `@intCast` asserts that the value fits. With no check in this function, 70000 panics in a safe build and is illegal behavior in ReleaseFast and ReleaseSmall.

```zig
fn narrowUnchecked(wide: u32) u16 {
    return @intCast(wide);
}
```

**Compiles.** 5e9 seconds panics in a safe build. In a Zig 0.17.0 Debug run NaN gave 0 with no panic, so a safe build does not catch every bad value. In ReleaseFast both are illegal behavior.

```zig
fn toMillisUnchecked(seconds: f64) u32 {
    return @trunc(seconds * 1000.0);
}
```

### Rule 10.4

The two operands of an arithmetic operator have the same signedness. Zig rejects `i32 + u32`. It accepts `i32 + u16`, because a `u16` coerces to `i32` and the add is an `i32` add. Do not bitcast past the rejection.

#### Do

```zig
fn boundedAdd(a: u32, b: u32) error{Overflow}!u32 {
    return std.math.add(u32, a, b);
}
```

#### Don't

**Rejected.**

```zig
export fn f(a: i32, b: u32) u32 {
    return a + b;
}
```

**Compiles.** `@bitCast` makes a negative `i32` look like a large `u32`, then the add proceeds.

```zig
export fn f(a: i32, b: u32) u32 {
    return @as(u32, @bitCast(a)) + b;
}
```

### Rule 10.5

A `bool` stays a `bool`. An `enum` stays an `enum` until the bytes hit the wire. `@backingInt` is that boundary, and the result is not fed back into arithmetic to mean "the next tag". The way back from the wire is `std.enums.fromInt`, which returns null for a value with no tag. `@fromBackingInt` of such a value is illegal behavior; `zig fmt` rewrites the older `@enumFromInt` to it. A non-exhaustive enum (`_`) accepts every value of its backing type, so `fromInt` never returns null for it and the `switch` handles the unknown values with a `_` prong.

#### Do

```zig
const Opcode = enum(u8) { load = 1, store = 2 };

fn opcodeByte(op: Opcode) u8 {
    return @backingInt(op);
}
```

`zig fmt` writes `@backingInt`. That is the 0.17 builtin for the enum's integer value.

```zig
fn decode(byte: u8) error{Unknown}!Opcode {
    return std.enums.fromInt(Opcode, byte) orelse error.Unknown;
}
```

#### Don't

**Compiles.** Adding 1 to the tag invents a value the enum may not have.

```zig
fn nextOp(op: Opcode) u8 {
    return @backingInt(op) + 1;
}
```

**Compiles.** Byte 9 has no tag. `@fromBackingInt` panics in a safe build and is illegal behavior in ReleaseFast and ReleaseSmall.

```zig
fn rawOpcode(byte: u8) Opcode {
    return @fromBackingInt(byte);
}
```

### Rule 10.6

Widen the operands, then add. A `u16` addition assigned to a `u32` still happens at `u16`.

#### Do

```zig
fn sumWide(a: u16, b: u16) error{Overflow}!u32 {
    return std.math.add(u32, a, b);
}
```

`sumWide(65535, 2)` is 65537. The `u16` arguments convert to `u32` at the call, and the add is 32 bits.

#### Don't

**Compiles.** `a + b` is a `u16` add. In a safe build, `65535 + 2` panics. In ReleaseFast and ReleaseSmall the add is illegal behavior. The `u32` return does not make that result 1. Specified wrap is `+%`.

```zig
export fn f(a: u16, b: u16) u32 {
    return a + b;
}
```

### Rule 10.7

A composite expression is not the operand of a wider arithmetic operation. Finish the inner operation at the wider width first.

#### Do

```zig
fn scale(a: u16, b: u16, c: u32) error{Overflow}!u32 {
    const sum = try sumWide(a, b);
    return std.math.mul(u32, sum, c);
}
```

#### Don't

**Compiles.** `(a + b)` is a `u16` add, before the multiply. In a safe build that add panics on overflow. In ReleaseFast and ReleaseSmall it is illegal behavior, so there is no defined wrapped product.

```zig
export fn f(a: u16, b: u16, c: u32) u32 {
    return (a + b) * c;
}
```

### Rule 10.8

A cast is not how you widen a sum. Casting the sum casts the narrow result after the add. In a safe build that add panics. In ReleaseFast and ReleaseSmall the add is illegal behavior. Widen the inputs, as in Rule 10.6.

#### Do

`sumWide`.

#### Don't

**Compiles.** `@as(u32, a + b)` still adds at `u16`, then widens whatever came out.

```zig
export fn f(a: u16, b: u16) u32 {
    return @as(u32, a + b);
}
```

### Rule 11.3

A pointer to one object type is not cast to a pointer to another. A value is reinterpreted with `@bitCast`. The one overlay is a struct on checked bytes, `headerOf` under Dir 4.1.

#### Do

```zig
fn bitsOf(x: f32) u32 {
    return @bitCast(x);
}
```

#### Don't

**Compiles.** It reads an `f32` through a `*const u32`. `@bitCast` states the same reinterpretation without a pointer.

```zig
fn bitsByPointer(x: *const f32) u32 {
    const p: *const u32 = @ptrCast(x);
    return p.*;
}
```

### Rule 11.8

`@constCast` and `@volatileCast` are not used. A function that writes takes `[]T` or `*T`, and one that only reads takes `[]const T` or `*const T` (Rule 8.13). Where a C header leaves `const` off a parameter that the C function only reads, the cast sits at that one call, with an allow comment that names the header.

#### Do

```zig
fn upperInto(out: []u8, text: []const u8) error{NoSpaceLeft}![]u8 {
    if (out.len < text.len) return error.NoSpaceLeft;
    for (out[0..text.len], text) |*o, c| o.* = std.ascii.toUpper(c);
    return out[0..text.len];
}
```

#### Don't

**Compiles.** `limit` can point at a constant. In a 0.17.0 run, `raise(&max_retries)` on `const max_retries: u32 = 10` left `max_retries` reading 10 in Debug, ReleaseSafe, and ReleaseFast. The write was lost, and nothing reported it.

```zig
fn raise(limit: *const u32) void {
    const m = @constCast(limit);
    m.* = 99;
}
```

### Rule 12.1

Parenthesize a mix of `and` and `or`. Parenthesize a mix of shifts, bitwise operators, and arithmetic.

#### Do

```zig
fn pack(n: u32, tag: u32) u32 {
    return (n << 4) | (tag & 0xF);
}
```

#### Don't

**Compiles, and it is a different value.** `&`, `^`, and `|` share one precedence level and associate left. `<<` is tighter. So the line below is `((n << 4) | tag) & 0xF`. `pack(1, 3)` is then 3. The parenthesized do is `(1 << 4) | (3 & 0xF)`, which is 19 (`0x13`).

```zig
fn pack(n: u32, tag: u32) u32 {
    return n << 4 | tag & 0xF;
}
```

### Rule 13.4

Assignment is a statement. The condition is a separate expression.

#### Do

```zig
fn storedFlag() bool {
    var n: u32 = 0;
    n = 1;
    if (n != 0) return true;
    return false;
}
```

#### Don't

**Rejected.**

```zig
export fn f() void {
    var x: u32 = 0;
    if (x = 1) {}
}
```

### Rule 14.4

The condition of `if` and `while` is a `bool`, an optional, or an error union. `for` walks a slice, an array, or a range, and a bare integer is rejected. Compare an integer before it is a bound or a condition.

#### Do

```zig
fn nonEmpty(n: u32) bool {
    return n != 0;
}
```

An optional unwrap is a condition of optional type, which is the Zig form of a null test:

```zig
fn lenOf(p: ?[]const u8) usize {
    const s = p orelse return 0;
    return s.len;
}
```

#### Don't

**Rejected.** `for` takes a slice, an array, or a range, and `n` is none of them. Walk `0..n`. `if (n)` on a `u32` is the same error, shown under Rule 10.1.

```zig
export fn f(n: usize) void {
    for (n) |_| {}
}
```

### Rule 15.1

There is no `goto`. Cleanup is `defer` and `errdefer`. A retry has a bound and returns an error when the bound is hit. One cleanup path, not a jump back to an earlier label.

#### Do

```zig
fn take(allocator: std.mem.Allocator, n: usize) ![]u8 {
    const buf = try allocator.alloc(u8, n);
    errdefer allocator.free(buf);
    @memset(buf, 0);
    return buf;
}
```

```zig
fn connect(dial: *const fn () error{Busy}!void) error{GaveUp}!void {
    for (0..4) |_| {
        dial() catch continue;
        return;
    }
    return error.GaveUp;
}
```

#### Don't

**Compiles.** `continue` back to `while (true)` is a backward jump with no bound.

```zig
fn connect(dial: *const fn () error{Busy}!void) !void {
    while (true) {
        dial() catch continue;
        return;
    }
}
```

### Rule 16.3

Prongs do not fall through. The compiler has no fallthrough. Two tags that share a body are one prong, joined with a comma. Do not paste the next case's body into this prong to fake the fall.

#### Do

```zig
const Color = enum { red, blue };

fn nameOf(c: Color) []const u8 {
    return switch (c) {
        .red => "red",
        .blue => "blue",
    };
}
```

Shared body:

```zig
fn warm(c: Color) bool {
    return switch (c) {
        .red, .blue => true,
    };
}
```

#### Don't

**Compiles.** `.red` adds 1 and then also adds 2 because someone meant to fall into `.blue`. `.blue` alone adds 2. `.red` now means something else, and a new tag will not inherit either body.

```zig
fn score(c: Color) u8 {
    var total: u8 = 0;
    switch (c) {
        .red => {
            total += 1;
            total += 2;
        },
        .blue => total += 2,
    }
    return total;
}
```

### Rule 16.4

A `switch` on an enum or a tagged union lists every tag. `else` is for an integer, or for a non-exhaustive enum, and that prong handles the unknown value. An empty `else` swallows a new opcode.

#### Do

```zig
fn opcodeName(code: u8) error{Unknown}![]const u8 {
    return switch (code) {
        1 => "load",
        2 => "store",
        else => error.Unknown,
    };
}
```

`nameOf` has no `else` because `Color` is exhaustive. Adding a tag and forgetting a prong is **rejected**.

#### Don't

**Compiles.** Code 9 is ignored.

```zig
fn ignore(code: u8) void {
    switch (code) {
        1 => {},
        else => {},
    }
}
```

**Rejected.**

An uncalled function is not analyzed, so the sample is `export`ed. The tag is `u8` so the diagnostic is the missing prong.

```zig
const E = enum(u8) { a, b };
export fn missingProng(e: E) void {
    switch (e) {
        .a => {},
    }
}
```

### Rule 17.1

A variadic function is not defined in Zig: no `...` parameter read with `@cVaStart`, `@cVaArg`, and `@cVaEnd`. Nothing checks how many arguments the caller passed or what types they have, in any build mode. Take a slice.

#### Do

```zig
fn sumAll(values: []const i32) error{Overflow}!i32 {
    var sum: i32 = 0;
    for (values) |v| sum = try std.math.add(i32, sum, v);
    return sum;
}
```

#### Don't

**Compiles.** A caller that passes an `int` gets garbage. In a 0.17.0 run, `firstValue(1, @as(c_int, 7))` returned 0 in Debug and in ReleaseSafe, with no check.

```zig
export fn firstValue(count: c_int, ...) callconv(.c) f64 {
    _ = count;
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return @cVaArg(&ap, f64);
}
```

### Rule 17.2

No runtime recursion, direct or through another function. A tree is a loop, an explicit stack with a fixed capacity, and a separate bound on how many nodes the loop visits. A cycle does not grow the stack, so the visit bound is what stops it. Recursion that exists only at `comptime`, to build a type, is a different mechanism. It is not a recursive algorithm, and `@setEvalBranchQuota` still bounds the compiler.

#### Do

```zig
const Node = struct {
    value: u32,
    left: ?*const Node,
    right: ?*const Node,
};

fn sumTree(root: *const Node) error{ Overflow, TooDeep }!u32 {
    var total: u32 = 0;
    var stack: [64]*const Node = undefined;
    var len: usize = 1;
    var seen: usize = 0;
    stack[0] = root;
    while (len > 0) {
        if (seen == stack.len) return error.TooDeep;
        seen += 1;
        len -= 1;
        const node = stack[len];
        total = try std.math.add(u32, total, node.value);
        if (node.left) |left| {
            if (len == stack.len) return error.TooDeep;
            stack[len] = left;
            len += 1;
        }
        if (node.right) |right| {
            if (len == stack.len) return error.TooDeep;
            stack[len] = right;
            len += 1;
        }
    }
    return total;
}
```

#### Don't

**Compiles.** A deep chain overflows the call stack. Zig 0.17 does not insert a stack check on this call.

```zig
fn walk(node: *const Node) void {
    if (node.left) |left| walk(left);
    if (node.right) |right| walk(right);
}
```

### Rule 18.4

`+` and `-` do not take a many-item or C pointer (`[*]T`, `[*c]T`). A many-item pointer has no length, so nothing checks where the result points, in any build mode. The function that learns the length slices the pointer once, checks the length, and indexes the slice. `<` and `>` between two pointers do not compile.

#### Do

```zig
fn third(p: [*]const u32, len: usize) error{OutOfRange}!u32 {
    const items = p[0..len];
    if (items.len < 3) return error.OutOfRange;
    return items[2];
}
```

#### Don't

**Compiles.** Nothing knows where the object ends. With an offset past the end, as in `(p + 6)[0]` on a four-element array, a 0.17.0 Debug run returned whatever was in memory, with no panic.

```zig
fn thirdUnchecked(p: [*]const u32) u32 {
    return (p + 2)[0];
}
```

### Rule 18.6

A pointer or a slice into a local does not outlive the call. Return the value, or write into storage the caller passes in.

#### Do

```zig
fn fillHeader(out: *[4]u8, n: u8) []const u8 {
    out.* = .{ n, 0, 0, 0 };
    return out[0..];
}
```

#### Don't

**Compiles.** `local` dies when `makeSlice` returns, and the slice points into a dead stack frame. Zig 0.17.0 inserts no check for this in any build mode.

```zig
fn makeSlice(n: u8) []const u8 {
    const local = [4]u8{ n, 0, 0, 0 };
    return local[0..];
}
```

### Rule 19.1

`@memcpy` does not copy between two regions that overlap. Moving data inside one buffer is `@memmove`. A safe build checks `@memcpy` for overlap and panics. ReleaseFast does not check, and the language reference requires the two regions not to overlap.

#### Do

```zig
fn dropFront(buf: []u8, n: usize) error{OutOfRange}![]u8 {
    if (n > buf.len) return error.OutOfRange;
    const rest = buf.len - n;
    @memmove(buf[0..rest], buf[n..]);
    return buf[0..rest];
}
```

#### Don't

**Compiles.** Source and destination share three bytes. A 0.17.0 Debug run panicked with `@memcpy arguments alias`.

```zig
fn shiftLeft(buf: *[5]u8) void {
    @memcpy(buf[0..4], buf[1..5]);
}
```

### Rule 19.2

A bare `union` is not used. A union that holds one of several values is `union(enum)`, so the stored field is known and a `switch` reads it. `extern union` and `packed union` exist for a C header or a register layout, and stay in the file that talks to it. Reinterpreting bits on purpose is `@bitCast`.

#### Do

```zig
const Value = union(enum) {
    int: u32,
    float: f32,
};

fn asFloat(v: Value) error{WrongKind}!f32 {
    return switch (v) {
        .float => |x| x,
        .int => error.WrongKind,
    };
}
```

#### Don't

**Compiles.** The stored field is `int`. Reading `float` panics in a safe build and is illegal behavior in ReleaseFast and ReleaseSmall.

```zig
const Raw = union {
    int: u32,
    float: f32,
};

fn wrongField(x: u32) f32 {
    const v: Raw = .{ .int = x };
    return v.float;
}
```

### Rule 19.3

A `union(enum)` payload is read through a `switch` prong capture, or after a test of the tag in the same function. Reading a field that is not the active one panics in a safe build. ReleaseFast has no check and reads the other field's bits.

#### Do

`asFloat` reads the payload through a `switch` capture and returns an error for the other tag.

#### Don't

**Compiles.** `floatOf(.{ .int = 7 })` panicked in a 0.17.0 Debug run with `access of union field 'float' while field 'int' is active`. ReleaseFast returned the bits of 7 read as an `f32`, about 1e-44.

```zig
const Value = union(enum) {
    int: u32,
    float: f32,
};

fn floatOf(v: Value) f32 {
    return v.float;
}
```

### Rule 21.3

`malloc`, `free`, and `std.heap.c_allocator` are not the allocator. Take `std.mem.Allocator`. `try` is the null check: `alloc` returns `error.OutOfMemory`.

#### Do

`take` and `grow`.

```zig
fn grow(allocator: std.mem.Allocator) ![]u32 {
    var list: std.ArrayList(u32) = .empty;
    errdefer list.deinit(allocator);
    try list.append(allocator, 1);
    return try list.toOwnedSlice(allocator);
}
```

`std.ArrayList` in 0.17 does not store the allocator. Pass the same one to every method and to `deinit`.

#### Don't

**Compiles** when libc is linked. `c_allocator.alloc` is `malloc` with a Zig type. The matching `c_allocator.free` is `free`. Library code that calls either one cannot be checked by `std.testing.allocator`. Without `-lc` the compiler rejects `c_allocator`.

```zig
fn buffer(n: usize) ![]u8 {
    return std.heap.c_allocator.alloc(u8, n);
}
```

### Rule 21.8

Only `main` ends the process. A library does not call `@panic`, `std.debug.panic`, or `std.process.exit`: bad input from outside is a returned error, and the caller decides. A test may panic.

#### Do

```zig
const Op = enum { nop, halt };

fn decodeOp(byte: u8) error{BadOpcode}!Op {
    return switch (byte) {
        0 => .nop,
        1 => .halt,
        else => error.BadOpcode,
    };
}
```

#### Don't

**Compiles.** One bad byte from a file or a peer ends the whole process.

```zig
const Op = enum { nop, halt };

fn decodeOrPanic(byte: u8) Op {
    return switch (byte) {
        0 => .nop,
        1 => .halt,
        else => @panic("bad opcode"),
    };
}
```

### Rule 21.17

A copy or a format stays inside the destination object. Zig text is `[]const u8` (pointer and length). A C string is `[*:0]const u8`, and `std.mem.span` runs only when a zero sits inside that object.

#### Do

```zig
fn fromC(p: [*:0]const u8) []const u8 {
    return std.mem.span(p);
}

fn render(buf: []u8, n: u32) error{NoSpaceLeft}![]u8 {
    return std.mem.print(buf, "{d}", .{n});
}

fn copyBounded(dest: []u8, src: []const u8) error{NoSpaceLeft}!void {
    if (dest.len < src.len) return error.NoSpaceLeft;
    @memmove(dest[0..src.len], src);
}
```

`std.mem.print` returns `error.NoSpaceLeft` instead of writing past `buf`. The returned slice points at `buf`, so `buf` has to outlive it. `std.fmt.bufPrint` is deprecated. `@memcpy` requires equal lengths and no overlap. A helper that takes two slices from its caller cannot know whether they overlap, so `copyBounded` uses `@memmove`.

#### Don't

**Compiles.** `span` walks until a zero. If `raw` is a length-delimited buffer with no terminator inside it, the walk leaves the object. Safe builds do not know where the object ends.

```zig
fn asText(raw: [*]const u8) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
}
```

**Compiles.** The index `buf.len` is one past the slice. Safe builds panic. ReleaseFast is illegal behavior.

```zig
fn terminate(buf: []u8) void {
    buf[buf.len] = 0;
}
```

Use `std.mem.printSentinel` when the result has to be `[:0]u8`. The sentinel is inside the buffer you passed.

### Rule 21.18

The length passed to a copy is the length of the smaller object, and it is checked against both sides. `@memcpy` will accept any `n` you slice to. The check is yours, because ReleaseFast does not bounds-check.

#### Do

`copyBounded`.

#### Don't

**Compiles** as an ordinary function. `n` from the caller is used as both lengths. If `n` is larger than either slice, a safe build panics and ReleaseFast writes off the end.

```zig
fn copyN(dest: []u8, src: []const u8, n: usize) void {
    @memcpy(dest[0..n], src[0..n]);
}
```

### Rule 21.25

Every atomic operation uses `.seq_cst`: the `std.atomic.Value` methods (`load`, `store`, `swap`, `fetchAdd`, `cmpxchgStrong`, and the rest) and the `@atomicLoad`, `@atomicStore`, `@atomicRmw`, and `@cmpxchg` builtins. A weaker order (`.acquire`, `.release`, `.acq_rel`, `.monotonic`, `.unordered`) is correct only with a proof about every other access to the same data.

#### Do

```zig
fn publish(ready: *std.atomic.Value(bool)) void {
    ready.store(true, .seq_cst);
}

fn isReady(ready: *const std.atomic.Value(bool)) bool {
    return ready.load(.seq_cst);
}
```

#### Don't

**Compiles.** `.monotonic` orders each atomic variable on its own. A thread that sees `ready` true is not guaranteed to see `value` in `slot`.

```zig
fn publishRelaxed(ready: *std.atomic.Value(bool), slot: *std.atomic.Value(u32), value: u32) void {
    slot.store(value, .monotonic);
    ready.store(true, .monotonic);
}
```

### Rule 22.1

Every resource has one release. `defer` when this function always releases it. `errdefer` when success returns it to the caller. Do not reassign the binding the defer closes over. A lock uses the same pattern. `lock` returns `error.Canceled` without holding the mutex. The `defer` is registered only after `lock` returns, so a cancelled lock is not unlocked. Unlocking a mutex that was not taken is illegal.

#### Do

```zig
fn withLock(io: std.Io, mu: *std.Io.Mutex) !void {
    try mu.lock(io);
    defer mu.unlock(io);
}

fn writeOwnFile(dir: std.Io.Dir, io: std.Io, name: []const u8, data: []const u8) !void {
    const file = try dir.createFile(io, name, .{ .read = true });
    defer file.close(io);
    try file.writeStreamingAll(io, data);
}
```

#### Don't

**Compiles.** The second allocation's failure returns without freeing `first`.

```zig
fn two(allocator: std.mem.Allocator) !void {
    const first = try allocator.alloc(u8, 8);
    const second = try allocator.alloc(u8, 8);
    allocator.free(second);
    allocator.free(first);
}
```

The repair is `errdefer allocator.free(first);` immediately after the first `try`.

### Rule 22.2

`allocator.free` takes the slice that `alloc` returned, and it takes the same allocator. Freeing a sub-slice, a stack array, or a slice from another allocator typechecks and is still wrong.

#### Do

```zig
fn zeroFour(allocator: std.mem.Allocator) !void {
    const buf = try allocator.alloc(u8, 4);
    defer allocator.free(buf);
    @memset(buf, 0);
}
```

`grow` ends in `toOwnedSlice`. The caller frees that slice with the same allocator. `items` from the list is not a separate allocation.

#### Don't

**Compiles.** Neither call frees a block `alloc` returned.

```zig
fn freeStack(allocator: std.mem.Allocator) void {
    var local: [4]u8 = .{ 1, 2, 3, 4 };
    allocator.free(&local);
}

fn freeSub(allocator: std.mem.Allocator, buf: []u8) void {
    allocator.free(buf[1..]);
}
```

### Rule 22.3

One open file for one job. If the function both reads and writes, open one handle that can do both (`createFile` with `.read = true`, or `openFile` with `.mode = .read_write`). Do not open the same path again on a second handle.

#### Do

`writeOwnFile` creates one handle, writes, and closes it. `readOwnFile` opens one read-only handle later, after the first close.

#### Don't

**Compiles.** Two handles on `name` at the same time: one read-only, one write-only.

```zig
fn bothEnds(dir: std.Io.Dir, io: std.Io, name: []const u8) !void {
    const reading = try dir.openFile(io, name, .{ .mode = .read_only });
    defer reading.close(io);
    const writing = try dir.openFile(io, name, .{ .mode = .write_only });
    defer writing.close(io);
    try writing.writeStreamingAll(io, "z");
}
```

### Rule 22.4

A handle opened `.read_only` is only read. On Linux, Zig 0.17, `writeStreamingAll` on that handle returns `error.NotOpenForWriting`. The tested sample is the last lines of `docs/examples/compliant.zig`.

#### Do

```zig
fn readOwnFile(dir: std.Io.Dir, io: std.Io, name: []const u8, dest: []u8) !usize {
    const file = try dir.openFile(io, name, .{ .mode = .read_only });
    defer file.close(io);
    return readSome(file, io, dest);
}
```

#### Don't

**Compiles, and the write fails at runtime.** `openFile` opens read-only unless the options say otherwise, so the write returns `error.NotOpenForWriting`.

```zig
fn appendNote(dir: std.Io.Dir, io: std.Io, name: []const u8) !void {
    const file = try dir.openFile(io, name, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, "z");
}
```

### Rule 22.5

Use `std.Io.File` methods. `file.handle` is the raw descriptor. It is not a field to pass to `std.posix` beside the `Io` calls.

#### Do

`readSome` and `writeStreamingAll`.

#### Don't

**Compiles.** `std.posix.read` takes the descriptor out of the `Io` implementation that owns it.

```zig
fn rawRead(file: std.Io.File, dest: []u8) !usize {
    return std.posix.read(file.handle, dest);
}
```

### Rule 22.6

After `close`, the handle is not a file. The `defer` is the last use.

#### Do

```zig
const file = try dir.openFile(io, name, .{ .mode = .read_only });
defer file.close(io);
return readSome(file, io, dest);
```

#### Don't

**Compiles.** The read is ordered after `close`.

```zig
fn readClosed(file: std.Io.File, io: std.Io, dest: []u8) !usize {
    file.close(io);
    return readSome(file, io, dest);
}
```

### Rule 22.7

End of file is `error.EndOfStream` from the read that just ran. It is not a data byte, and it is not a length of 0. `readStreaming` may return 0 without being the end of the file, so the sample does not turn the error into 0.

#### Do

```zig
fn readSome(file: std.Io.File, io: std.Io, dest: []u8) !usize {
    return file.readStreaming(io, &.{dest});
}
```

`readSome` of a consumed two-byte file returns `error.EndOfStream`. `docs/examples/compliant.zig` checks that on the second read.

#### Don't

**Compiles.** `0xFF` in the buffer is data. Treating it as an end marker drops the rest of the file.

```zig
fn untilFf(buf: []const u8) usize {
    for (buf, 0..) |b, i| {
        if (b == 0xFF) return i;
    }
    return buf.len;
}
```

### Rule 22.8

Zig's own error unions are not `errno`. With `-lc`, `std.posix` is libc and `std.Io` can call it, so those calls can change `errno` too. Set `errno` to 0 on the line before the libc call you mean, and read it before any later call.

#### Do

```zig
fn missingPath(path: [*:0]const u8) error{Failed}!c_int {
    std.c._errno().* = 0;
    const rc = std.c.access(path, 0);
    return captureErrno(rc);
}
```

`captureErrno` is the function under Rule 22.9. `access` of a missing path returns `-1`. Do not clear `errno` after it returns.

#### Don't

**Compiles.** The clear is on the wrong side of the call, so the value read afterwards is 0 even when `access` failed.

```zig
fn tooLate(path: [*:0]const u8) c_int {
    const rc = std.c.access(path, 0);
    std.c._errno().* = 0;
    if (rc == -1) return std.c._errno().*;
    return rc;
}
```

### Rule 22.9

Read `errno` only when the call reported failure, and use that value before you do anything else. The report is `-1`, a null pointer, or, for a call such as `strtoul` whose result cannot signal failure, a non-zero `errno` after the function cleared it to 0 just before the call. `std.c.errno` reads it for a return of `-1`. If you read it yourself, keep the same order.

#### Do

```zig
fn captureErrno(rc: c_int) error{Failed}!c_int {
    if (rc != -1) return 0;
    const err = std.c._errno().*;
    if (err == 0) return error.Failed;
    return err;
}
```

#### Don't

**Compiles.** The return code said success. `errno` is leftover from an earlier call.

```zig
fn ignoreRc() c_int {
    return std.c._errno().*;
}
```

### Rule 22.10

Nothing runs between a failed libc call and the read of `errno`. A log, an allocation, or another libc call is allowed to replace it.

#### Do

`captureErrno` reads `errno` as the next operation after `rc == -1`. With `-lc`, an `std.Io` or `std.posix` call can replace `errno` the same way another libc call can.

#### Don't

**Compiles.** `std.debug.print` can be a write. The `errno` you read afterwards can be the print's, not the failed call's.

```zig
fn late(rc: c_int) c_int {
    if (rc == -1) {
        std.debug.print("failed\n", .{});
        return std.c._errno().*;
    }
    return 0;
}
```

## What the compiler already rejects

The bare form of each of these does not compile on Zig 0.17.0. Some still have a rule above, because a cast or a `@ptrCast` can put the bug back.

- Assigning a `u32` to a `u16`, or adding `i32` to `u32`. A `u8` does coerce to an `i16`, because every value fits. A `u16` does not.
- `if (n)` when `n` is an integer.
- `if (x = 1)`.
- `a / b` when both are runtime signed integers. Use `std.math.divTrunc`, `std.math.divFloor`, `std.math.divCeil`, or `std.math.divExact`.
- A missing prong on an exhaustive enum, when the `switch` has no `else`. With `else` the compiler accepts it, which is why Rule 16.4 limits `else`. There is no fallthrough keyword.
- A null `*T` or `[]T`. Absence is `?*T` or `?[]T`.
- A call whose non-void result is dropped, or whose error union is ignored. `_ =` discards a value on purpose, and `try` or `catch` handles an error.
- An unused local or parameter, and a local that shadows another declaration.
- `010`. A leading zero is rejected, so there is no octal by accident. Octal is `0o10`.
- Code after a `return` in the same block, and an unused label.
- A struct literal that names a field twice, an array literal with fewer elements than its length, two enum tags with one value, and two `switch` prongs with one value.
- A comptime-known value that does not fit its type, such as `const x: u8 = 255 + 1`.
- `if (p)` when `p` is an optional. Unwrap it with a capture or compare it with `null`.
- A non-void function that can reach its closing brace, and a `noreturn` function that returns.
- An assignment to a parameter. Parameters are constant.
- A string literal assigned to `[]u8`, and a declaration named after a primitive type, such as `const u8 = 1`.
- `<` or `>` between two pointers.
