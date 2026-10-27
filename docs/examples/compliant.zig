const std = @import("std");

// x86_64 System V aligns u64 to 8, so this header is 16 bytes.
// A target that aligns u64 to 4 gets 12, and the asserts fail.
const Header = extern struct {
    magic: u32,
    size: u64,
};

comptime {
    std.debug.assert(@sizeOf(Header) == 16);
    std.debug.assert(@alignOf(Header) == 8);
}

const block_size: u32 = 512;
const max_frame_bytes: u32 = 64 * 1024;
const max_config_bytes: usize = 64 * 1024;

fn boundedAdd(a: u32, b: u32) error{Overflow}!u32 {
    return std.math.add(u32, a, b);
}

fn shift(value: u32, amount: u32) error{Overflow}!u32 {
    if (amount >= @bitSizeOf(u32)) return error.Overflow;
    return value << @as(std.math.Log2Int(u32), @intCast(amount));
}

fn narrow(wide: u32) error{Overflow}!u16 {
    return std.math.cast(u16, wide) orelse error.Overflow;
}

fn signedQuotient(a: i32, b: i32) error{ DivisionByZero, Overflow }!i32 {
    return std.math.divTrunc(i32, a, b);
}

fn perItem(total: u32, count: u32) error{DivisionByZero}!u32 {
    if (count == 0) return error.DivisionByZero;
    return total / count;
}

fn blocksFor(bytes: u64) u64 {
    const whole = bytes / block_size;
    return whole + @intFromBool(bytes % block_size != 0);
}

fn sumWide(a: u16, b: u16) error{Overflow}!u32 {
    return std.math.add(u32, a, b);
}

fn scale(a: u16, b: u16, c: u32) error{Overflow}!u32 {
    const sum = try sumWide(a, b);
    return std.math.mul(u32, sum, c);
}

fn decimalDigit(n: u8) error{Overflow}!u8 {
    if (n > 9) return error.Overflow;
    return '0' + n;
}

fn both(ready: bool, allowed: bool) bool {
    return ready and allowed;
}

fn nonEmpty(n: u32) bool {
    return n != 0;
}

fn storedFlag() bool {
    var n: u32 = 0;
    n = 1;
    if (n != 0) return true;
    return false;
}

fn pack(n: u32, tag: u32) u32 {
    return (n << 4) | (tag & 0xF);
}

const Opcode = enum(u8) { load = 1, store = 2 };

fn opcodeByte(op: Opcode) u8 {
    return @backingInt(op);
}

fn decode(byte: u8) error{Unknown}!Opcode {
    return std.enums.fromInt(Opcode, byte) orelse error.Unknown;
}

fn opcodeName(code: u8) error{Unknown}![]const u8 {
    return switch (code) {
        1 => "load",
        2 => "store",
        else => error.Unknown,
    };
}

const Color = enum { red, blue };

fn nameOf(c: Color) []const u8 {
    return switch (c) {
        .red => "red",
        .blue => "blue",
    };
}

fn warm(c: Color) bool {
    return switch (c) {
        .red, .blue => true,
    };
}

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

fn checksum(data: []const u8) u8 {
    var sum: u8 = 0;
    for (data) |b| sum +%= b;
    return sum;
}

fn lenOf(p: ?[]const u8) usize {
    const s = p orelse return 0;
    return s.len;
}

/// `p` is borrowed. The returned slice points at `p` through the sentinel.
fn fromC(p: [*:0]const u8) []const u8 {
    return std.mem.span(p);
}

fn wipe(buf: *[32]u8) void {
    std.crypto.secureZero(u8, buf);
}

/// `bytes` is borrowed. The returned pointer points into `bytes`.
fn headerOf(bytes: []const u8) error{ Truncated, Misaligned }!*const Header {
    if (bytes.len < @sizeOf(Header)) return error.Truncated;
    if (!std.mem.isAligned(@intFromPtr(bytes.ptr), @alignOf(Header))) return error.Misaligned;
    const aligned: [*]align(@alignOf(Header)) const u8 = @alignCast(bytes.ptr);
    return @ptrCast(aligned);
}

/// Caller owns the returned slice and frees it with the same allocator.
fn take(allocator: std.mem.Allocator, n: usize) ![]u8 {
    const buf = try allocator.alloc(u8, n);
    errdefer allocator.free(buf);
    @memset(buf, 0);
    return buf;
}

fn zeroFour(allocator: std.mem.Allocator) !void {
    const buf = try allocator.alloc(u8, 4);
    defer allocator.free(buf);
    @memset(buf, 0);
}

/// Caller owns the returned slice and frees it with the same allocator.
fn grow(allocator: std.mem.Allocator) ![]u32 {
    var list: std.ArrayList(u32) = .empty;
    errdefer list.deinit(allocator);
    try list.append(allocator, 1);
    return try list.toOwnedSlice(allocator);
}

fn withLock(io: std.Io, mu: *std.Io.Mutex) !void {
    try mu.lock(io);
    defer mu.unlock(io);
}

fn connect(dial: *const fn () error{Busy}!void) error{GaveUp}!void {
    for (0..4) |_| {
        dial() catch continue;
        return;
    }
    return error.GaveUp;
}

fn dialBusy() error{Busy}!void {
    return error.Busy;
}

fn dialReady() error{Busy}!void {}

/// `out` is the caller's storage. Null and overflow both return 1.
export fn diskSize(blocks: u32, block_size_bytes: u32, out: ?*u32) c_int {
    const dest = out orelse return 1;
    dest.* = std.math.mul(u32, blocks, block_size_bytes) catch return 1;
    return 0;
}

/// `buf` is borrowed. The returned slice points into `buf`.
fn render(buf: []u8, n: u32) error{NoSpaceLeft}![]u8 {
    return std.mem.print(buf, "{d}", .{n});
}

/// `buf` is borrowed. The returned sentinel slice points into `buf`.
fn renderZ(buf: []u8, n: u32) error{NoSpaceLeft}![:0]u8 {
    return std.mem.printSentinel(buf, "{d}", .{n}, 0);
}

fn copyBounded(dest: []u8, src: []const u8) error{NoSpaceLeft}!void {
    if (dest.len < src.len) return error.NoSpaceLeft;
    @memmove(dest[0..src.len], src);
}

const Node = struct {
    value: u32,
    left: ?*const Node,
    right: ?*const Node,
};

/// Walks at most 64 nodes. A deeper frontier or a longer walk, including a cycle, returns `error.TooDeep`.
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

fn captureErrno(rc: c_int) error{Failed}!c_int {
    if (rc != -1) return 0;
    const err = std.c._errno().*;
    if (err == 0) return error.Failed;
    return err;
}

/// Sets `errno` to 0, calls `access`, and reads `errno` only when the call returns -1.
fn missingPath(path: [*:0]const u8) error{Failed}!c_int {
    std.c._errno().* = 0;
    const rc = std.c.access(path, 0);
    return captureErrno(rc);
}

/// Returns how many bytes this call read. `error.EndOfStream` is end of file. Zero is not end of file.
fn readSome(file: std.Io.File, io: std.Io, dest: []u8) !usize {
    return file.readStreaming(io, &.{dest});
}

fn writeOwnFile(dir: std.Io.Dir, io: std.Io, name: []const u8, data: []const u8) !void {
    const file = try dir.createFile(io, name, .{ .read = true });
    defer file.close(io);
    try file.writeStreamingAll(io, data);
}

fn priceOf(prices: *const std.StringHashMapUnmanaged(u32), name: []const u8) error{UnknownItem}!u32 {
    return prices.get(name) orelse error.UnknownItem;
}

fn pushPair(gpa: std.mem.Allocator, list: *std.ArrayList(u32), a: u32, b: u32) !void {
    try list.ensureUnusedCapacity(gpa, 2);
    list.appendAssumeCapacity(a);
    list.appendAssumeCapacity(b);
}

fn toMillis(seconds: f64) error{OutOfRange}!u32 {
    const ms = seconds * 1000.0;
    if (!(ms >= 0.0 and ms < 4294967296.0)) return error.OutOfRange;
    return @trunc(ms);
}

fn fillHeader(out: *[4]u8, n: u8) []const u8 {
    out.* = .{ n, 0, 0, 0 };
    return out[0..];
}

const Op = enum { nop, halt };

fn decodeOp(byte: u8) error{BadOpcode}!Op {
    return switch (byte) {
        0 => .nop,
        1 => .halt,
        else => error.BadOpcode,
    };
}

/// Caller owns the returned slice and frees it with `gpa`.
fn frameBody(gpa: std.mem.Allocator, len: u32) ![]u8 {
    if (len > max_frame_bytes) return error.FrameTooLarge;
    return gpa.alloc(u8, len);
}

/// Caller owns the returned slice and frees it with `gpa`.
fn readConfig(dir: std.Io.Dir, io: std.Io, gpa: std.mem.Allocator) ![]u8 {
    return dir.readFileAlloc(io, "config", gpa, .limited(max_config_bytes));
}

fn find(items: []const u32, x: u32) ?usize {
    for (items, 0..) |item, i| {
        if (item == x) return i;
    }
    return null;
}

fn colon(s: []const u8) ?usize {
    return std.mem.findScalar(u8, s, ':');
}

fn bitsOf(x: f32) u32 {
    return @bitCast(x);
}

fn setReuse(fd: std.posix.socket_t) error{ InvalidOption, Unexpected }!void {
    const one: c_int = 1;
    const rc = std.posix.system.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&one), @sizeOf(c_int));
    return switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        .INVAL, .NOPROTOOPT => error.InvalidOption,
        else => error.Unexpected,
    };
}

const max_workers: usize = 4;

fn work(hits: *std.atomic.Value(u64)) void {
    _ = hits.fetchAdd(1, .seq_cst);
}

fn readOwnFile(dir: std.Io.Dir, io: std.Io, name: []const u8, dest: []u8) !usize {
    const file = try dir.openFile(io, name, .{ .mode = .read_only });
    defer file.close(io);
    return readSome(file, io, dest);
}

fn bitWidth(x: u32) error{Zero}!u5 {
    if (x == 0) return error.Zero;
    return std.math.log2_int(u32, x);
}

fn removeAt(list: *std.ArrayList(u32), i: usize) error{OutOfRange}!u32 {
    if (i >= list.items.len) return error.OutOfRange;
    return list.orderedRemove(i);
}

fn mean(sum: f64, count: u32) error{ Empty, NotFinite }!f64 {
    if (count == 0) return error.Empty;
    const m = sum / @as(f64, @floatFromInt(count));
    if (!std.math.isFinite(m)) return error.NotFinite;
    return m;
}

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

fn addTwice(total: *u32, step: *const u32) error{Overflow}!void {
    total.* = try std.math.add(u32, total.*, step.*);
    total.* = try std.math.add(u32, total.*, step.*);
}

fn upperInto(out: []u8, text: []const u8) error{NoSpaceLeft}![]u8 {
    if (out.len < text.len) return error.NoSpaceLeft;
    for (out[0..text.len], text) |*o, c| o.* = std.ascii.toUpper(c);
    return out[0..text.len];
}

fn sumAll(values: []const i32) error{Overflow}!i32 {
    var sum: i32 = 0;
    for (values) |v| sum = try std.math.add(i32, sum, v);
    return sum;
}

fn third(p: [*]const u32, len: usize) error{OutOfRange}!u32 {
    const items = p[0..len];
    if (items.len < 3) return error.OutOfRange;
    return items[2];
}

fn dropFront(buf: []u8, n: usize) error{OutOfRange}![]u8 {
    if (n > buf.len) return error.OutOfRange;
    const rest = buf.len - n;
    @memmove(buf[0..rest], buf[n..]);
    return buf[0..rest];
}

fn publish(ready: *std.atomic.Value(bool)) void {
    ready.store(true, .seq_cst);
}

fn isReady(ready: *const std.atomic.Value(bool)) bool {
    return ready.load(.seq_cst);
}

test "arithmetic and types" {
    try std.testing.expectEqual(@as(u32, 3), try boundedAdd(1, 2));
    try std.testing.expectError(error.Overflow, boundedAdd(std.math.maxInt(u32), 1));
    try std.testing.expectEqual(@as(u32, 8), try shift(1, 3));
    try std.testing.expectError(error.Overflow, shift(1, 32));
    try std.testing.expectEqual(@as(u16, 12), try narrow(12));
    try std.testing.expectError(error.Overflow, narrow(70_000));
    try std.testing.expectEqual(@as(i32, -3), try signedQuotient(-7, 2));
    try std.testing.expectError(error.DivisionByZero, signedQuotient(1, 0));
    try std.testing.expectError(error.Overflow, signedQuotient(std.math.minInt(i32), -1));
    try std.testing.expectEqual(@as(u32, 5), try perItem(10, 2));
    try std.testing.expectError(error.DivisionByZero, perItem(10, 0));
    try std.testing.expectEqual(@as(u64, 0), blocksFor(0));
    try std.testing.expectEqual(@as(u64, 2), blocksFor(1024));
    try std.testing.expectEqual(@as(u64, 3), blocksFor(1025));
    try std.testing.expectEqual(@as(u32, 65_535 + 2), try sumWide(65_535, 2));
    try std.testing.expectEqual(@as(u32, 12), try scale(2, 2, 3));
    try std.testing.expectEqual(@as(u8, '7'), try decimalDigit(7));
    try std.testing.expectError(error.Overflow, decimalDigit(10));
    try std.testing.expect(both(true, true));
    try std.testing.expect(nonEmpty(1));
    try std.testing.expect(!nonEmpty(0));
    try std.testing.expect(storedFlag());
    try std.testing.expectEqual(@as(u32, 0x13), pack(1, 3));
    try std.testing.expectEqual(@as(u8, 1), opcodeByte(.load));
    try std.testing.expectEqual(Opcode.store, try decode(2));
    try std.testing.expectError(error.Unknown, decode(9));
    try std.testing.expectEqual(@as(f32, 1.5), try asFloat(.{ .float = 1.5 }));
    try std.testing.expectError(error.WrongKind, asFloat(.{ .int = 1 }));
    try std.testing.expectEqualStrings("store", try opcodeName(2));
    try std.testing.expectError(error.Unknown, opcodeName(9));
    try std.testing.expectEqualStrings("red", nameOf(.red));
    try std.testing.expect(warm(.red));
    try std.testing.expect(warm(.blue));
    try std.testing.expectEqual(@as(u8, 3), checksum("\x01\x02"));
    try std.testing.expectEqual(@as(usize, 0), lenOf(null));
    try std.testing.expectEqualStrings("ab", fromC("ab"));
    try connect(dialReady);
    try std.testing.expectError(error.GaveUp, connect(dialBusy));
}

test "memory layout and copy" {
    var secret: [32]u8 = undefined;
    @memset(&secret, 'k');
    wipe(&secret);

    var raw align(8) = std.mem.zeroes([16]u8);
    raw[0] = 1;
    const header = try headerOf(&raw);
    try std.testing.expectEqual(@as(u32, 1), header.magic);

    const buf = try take(std.testing.allocator, 4);
    defer std.testing.allocator.free(buf);
    try std.testing.expectEqual(@as(u8, 0), buf[0]);

    try zeroFour(std.testing.allocator);

    const owned = try grow(std.testing.allocator);
    defer std.testing.allocator.free(owned);
    try std.testing.expectEqual(@as(u32, 1), owned[0]);

    var text: [8]u8 = undefined;
    const rendered = try render(&text, 7);
    try std.testing.expectEqualStrings("7", rendered);
    const z = try renderZ(&text, 7);
    try std.testing.expectEqualStrings("7", z);
    try std.testing.expectEqual(@as(u8, 0), text[z.len]);

    var dest: [4]u8 = undefined;
    try copyBounded(&dest, "ab");
    try std.testing.expectEqualStrings("ab", dest[0..2]);
    try std.testing.expectError(error.NoSpaceLeft, copyBounded(dest[0..1], "ab"));

    var out: u32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), diskSize(2, 512, &out));
    try std.testing.expectEqual(@as(u32, 1024), out);
    try std.testing.expectEqual(@as(c_int, 1), diskSize(std.math.maxInt(u32), 2, &out));
    try std.testing.expectEqual(@as(c_int, 1), diskSize(2, 512, null));
}

test "lookups, capacity, floats, termination, outside sizes" {
    const gpa = std.testing.allocator;
    var prices: std.StringHashMapUnmanaged(u32) = .empty;
    defer prices.deinit(gpa);
    try prices.put(gpa, "tea", 3);
    try std.testing.expectEqual(@as(u32, 3), try priceOf(&prices, "tea"));
    try std.testing.expectError(error.UnknownItem, priceOf(&prices, "milk"));

    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(gpa);
    try pushPair(gpa, &list, 1, 2);
    try std.testing.expectEqualSlices(u32, &.{ 1, 2 }, list.items);

    try std.testing.expectEqual(@as(u32, 1500), try toMillis(1.5));
    try std.testing.expectError(error.OutOfRange, toMillis(std.math.nan(f64)));
    try std.testing.expectError(error.OutOfRange, toMillis(5e9));
    try std.testing.expectError(error.OutOfRange, toMillis(-1));

    var storage: [4]u8 = undefined;
    try std.testing.expectEqualSlices(u8, &.{ 7, 0, 0, 0 }, fillHeader(&storage, 7));

    try std.testing.expectEqual(Op.halt, try decodeOp(1));
    try std.testing.expectError(error.BadOpcode, decodeOp(9));

    const body = try frameBody(gpa, 16);
    defer gpa.free(body);
    try std.testing.expectEqual(@as(usize, 16), body.len);
    try std.testing.expectError(error.FrameTooLarge, frameBody(gpa, max_frame_bytes + 1));

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "config", .data = "x=1" });
    const config = try readConfig(tmp.dir, std.testing.io, gpa);
    defer gpa.free(config);
    try std.testing.expectEqualStrings("x=1", config);
}

test "not-found, deprecated names, reinterpretation, system calls" {
    try std.testing.expectEqual(@as(?usize, 1), find(&.{ 4, 7 }, 7));
    try std.testing.expectEqual(@as(?usize, null), find(&.{4}, 7));
    try std.testing.expectEqual(@as(?usize, 1), colon("a:b"));
    try std.testing.expectEqual(@as(u32, 0x3f800000), bitsOf(1.0));
    // -1 is not a descriptor, so the kernel answers EBADF, which is reported, not assumed.
    try std.testing.expectError(error.Unexpected, setReuse(-1));
}

test "workers start once, a fixed number, and are joined" {
    var hits: std.atomic.Value(u64) = .init(0);
    {
        var workers: [max_workers]std.Thread = undefined;
        var started: usize = 0;
        defer for (workers[0..started]) |w| w.join();
        for (&workers) |*w| {
            w.* = try std.Thread.spawn(.{}, work, .{&hits});
            started += 1;
        }
    }
    try std.testing.expectEqual(@as(u64, max_workers), hits.load(.seq_cst));
}

test "std preconditions, floats, aliasing, casts, variadics, pointers" {
    try std.testing.expectEqual(@as(u5, 3), try bitWidth(8));
    try std.testing.expectError(error.Zero, bitWidth(0));

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(gpa);
    try list.appendSlice(gpa, &.{ 4, 5 });
    try std.testing.expectEqual(@as(u32, 4), try removeAt(&list, 0));
    try std.testing.expectError(error.OutOfRange, removeAt(&list, 1));

    try std.testing.expectEqual(@as(f64, 1.5), try mean(3, 2));
    try std.testing.expectError(error.Empty, mean(1, 0));
    try std.testing.expectError(error.NotFinite, mean(std.math.nan(f64), 2));
    try std.testing.expectError(error.NotFinite, mean(std.math.inf(f64), 1));

    var x: u32 = 1;
    try addTwice(&x, &x);
    try std.testing.expectEqual(@as(u32, 4), x);
    const big: u32 = std.math.maxInt(u32);
    try std.testing.expectError(error.Overflow, addTwice(&x, &big));

    var out: [4]u8 = undefined;
    try std.testing.expectEqualStrings("ABC", try upperInto(&out, "abc"));
    try std.testing.expectError(error.NoSpaceLeft, upperInto(out[0..2], "abc"));

    try std.testing.expectEqual(@as(i32, 3), try sumAll(&.{ 1, 2 }));
    try std.testing.expectError(error.Overflow, sumAll(&.{ std.math.maxInt(i32), 1 }));

    const words = [_]u32{ 10, 20, 30, 40 };
    try std.testing.expectEqual(@as(u32, 30), try third(&words, words.len));
    try std.testing.expectError(error.OutOfRange, third(&words, 2));

    var buf = "abcde".*;
    try std.testing.expectEqualStrings("cde", try dropFront(&buf, 2));
    try std.testing.expectError(error.OutOfRange, dropFront(&buf, 6));
}

test "two accounts lock in one order, and a flag is published seq_cst" {
    const io = std.testing.io;
    var a: Account = .{ .id = 1, .balance = 100 };
    var b: Account = .{ .id = 2, .balance = 0 };
    try transfer(io, &a, &b, 30);
    try transfer(io, &b, &a, 10);
    try std.testing.expectEqual(@as(u64, 80), a.balance);
    try std.testing.expectEqual(@as(u64, 20), b.balance);
    try std.testing.expectError(error.Overflow, transfer(io, &b, &a, 21));
    try std.testing.expectEqual(@as(u64, 20), b.balance);
    try std.testing.expectEqual(@as(u64, 80), a.balance);
    try std.testing.expectError(error.SameAccount, transfer(io, &a, &a, 1));

    var ready: std.atomic.Value(bool) = .init(false);
    try std.testing.expect(!isReady(&ready));
    publish(&ready);
    try std.testing.expect(isReady(&ready));
}

test "copyBounded handles overlapping slices" {
    var buf = "abcde".*;
    try copyBounded(buf[1..5], buf[0..4]);
    try std.testing.expectEqualStrings("aabcd", &buf);
}

test "tree and errno" {
    const child = Node{ .value = 3, .left = null, .right = null };
    const root = Node{ .value = 1, .left = null, .right = &child };
    try std.testing.expectEqual(@as(u32, 4), try sumTree(&root));

    var left = Node{ .value = 1, .left = null, .right = null };
    var right = Node{ .value = 1, .left = null, .right = null };
    left.left = &right;
    right.left = &left;
    try std.testing.expectError(error.TooDeep, sumTree(&left));

    std.c._errno().* = 0;
    try std.testing.expectEqual(@as(c_int, 0), try captureErrno(0));
    std.c._errno().* = 2;
    try std.testing.expectEqual(@as(c_int, 2), try captureErrno(-1));
    const missing = try missingPath("no-such-misra-zig-path");
    try std.testing.expect(missing != 0);
    std.c._errno().* = 0;

    var mu: std.Io.Mutex = .init;
    try withLock(std.testing.io, &mu);
}

test "one file handle" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    try writeOwnFile(tmp.dir, io, "note", "ab");
    var dest: [8]u8 = undefined;
    const n = try readOwnFile(tmp.dir, io, "note", &dest);
    try std.testing.expectEqualStrings("ab", dest[0..n]);

    const file = try tmp.dir.openFile(io, "note", .{ .mode = .read_only });
    defer file.close(io);
    var again: [8]u8 = undefined;
    const first = try readSome(file, io, &again);
    try std.testing.expectEqual(@as(usize, 2), first);
    try std.testing.expectError(error.EndOfStream, readSome(file, io, &again));
    // misra-lint: allow write_read_only the test asserts that the write is refused
    try std.testing.expectError(error.NotOpenForWriting, file.writeStreamingAll(io, "z"));
}
