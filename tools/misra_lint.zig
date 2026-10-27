//! Deterministic checks for the MISRA Zig rules that a syntax tree can decide.
//!
//! The checker parses each file with `std.zig.Ast` and reports patterns the handbook
//! marks as a don't. It has no types and no data flow, so a clean run is not compliance:
//! the rules it cannot decide still need a reader. `--checks` lists what it decides.
//!
//! A finding is silenced by a comment on its line or the line above:
//! `// misra-lint: allow <check> <reason>`. The reason is required.

const std = @import("std");
const Ast = std.zig.Ast;
const Node = Ast.Node;
const TokenIndex = Ast.TokenIndex;
const Allocator = std.mem.Allocator;
const std_lists = @import("std_lists.zig");

const max_source_bytes: usize = 16 * 1024 * 1024;
const allow_marker = "misra-lint: allow ";
const usage =
    \\usage: misra-lint [--json] [--root FILE] FILE...
    \\       misra-lint --checks [--json]
    \\
    \\Reports MISRA Zig don't patterns in each FILE. `-` reads stdin.
    \\With --root, a FILE the root does not reach through @import is reported.
    \\Exit 0: no finding. Exit 1: at least one finding. Exit 2: usage or read error.
    \\
;

const Severity = enum {
    /// The pattern is the breach the rule describes.
    violation,
    /// The pattern is usually the breach. A reader decides.
    review,
};

const Check = enum {
    parse_error,
    runtime_safety_off,
    untyped_literal_const,
    extern_usize_field,
    global_allocator,
    anytype_unused,
    anyerror_return,
    catch_empty,
    catch_unreachable,
    pub_wrapper,
    mutable_param_read_only,
    undefined_then_branch,
    field_by_field_init,
    truncate_param,
    bitcast_arith,
    enum_int_arith,
    narrow_sum_widened,
    narrow_operand,
    widening_cast_of_sum,
    mixed_precedence,
    unbounded_loop,
    empty_else_prong,
    recursion,
    global_c_alloc,
    deprecated_api,
    ptrcast_span,
    index_at_len,
    memcpy_unchecked_len,
    try_before_release,
    free_not_owned,
    same_path_twice,
    raw_handle,
    use_after_close,
    errno_clear_after_call,
    errno_without_failure,
    errno_after_call,
    assert_on_input,
    unchecked_divisor,
    unchecked_intcast,
    unchecked_enum,
    bare_union,
    write_read_only,
    enum_else,
    terminate_outside_main,
    orelse_unreachable,
    unwrap_assumed,
    assume_capacity,
    unlimited_limit,
    float_to_int,
    stack_escape,
    posix_assumes_errno,
    thread_in_loop,
    thread_outside_main,
    thread_detached,
    io_outside_main,
    handwritten_extern,
    sentinel_return,
    build_unsafe_mode,
    ptrcast_reinterpret,
    unreachable_file,
    float_mode_optimized,
    noalias_param,
    const_cast,
    c_variadic,
    pointer_arith,
    memcpy_alias,
    atomic_order,
    lock_twice,
};

const Info = struct {
    severity: Severity,
    /// Handbook ids, for example `rule-22-4`.
    rules: []const []const u8,
    summary: []const u8,
};

fn info(check: Check) Info {
    return switch (check) {
        .parse_error => .{
            .severity = .violation,
            .rules = &.{},
            .summary = "Zig cannot parse this file, so no check ran.",
        },
        .runtime_safety_off => .{
            .severity = .violation,
            .rules = &.{"dir-4-1"},
            .summary = "@setRuntimeSafety(false) deletes the checks in every build mode. Guard the input or return an error.",
        },
        .untyped_literal_const => .{
            .severity = .violation,
            .rules = &.{ "dir-4-6", "rule-8-1" },
            .summary = "A container-level number has no width. Write the type on the declaration.",
        },
        .extern_usize_field => .{
            .severity = .violation,
            .rules = &.{"dir-4-6"},
            .summary = "An extern struct field crosses a C header. Name the width: u32 or u64, not usize.",
        },
        .global_allocator => .{
            .severity = .violation,
            .rules = &.{ "dir-4-12", "rule-21-3" },
            .summary = "A global allocator outside main hides the owner. Take a std.mem.Allocator parameter.",
        },
        .global_c_alloc => .{
            .severity = .violation,
            .rules = &.{"rule-21-3"},
            .summary = "malloc, calloc, realloc, and free are not the allocator. Take a std.mem.Allocator parameter.",
        },
        .anytype_unused => .{
            .severity = .violation,
            .rules = &.{"rule-8-2"},
            .summary = "This anytype parameter is never used, so no type is rejected. Give it a concrete type.",
        },
        .anyerror_return => .{
            .severity = .violation,
            .rules = &.{"dir-4-1"},
            .summary = "anyerror is not a return type. Infer the set with !T or name it.",
        },
        .catch_empty => .{
            .severity = .violation,
            .rules = &.{"dir-4-1"},
            .summary = "catch {} discards the error, and so does a handler that only discards its capture. Propagate it with try or handle each error.",
        },
        .catch_unreachable => .{
            .severity = .violation,
            .rules = &.{"dir-4-1"},
            .summary = "catch unreachable is illegal behavior when the error happens. Propagate it with try.",
        },
        .pub_wrapper => .{
            .severity = .violation,
            .rules = &.{"rule-8-8"},
            .summary = "This pub function only forwards to a file-local function, which publishes it again.",
        },
        .mutable_param_read_only => .{
            .severity = .violation,
            .rules = &.{"rule-8-13"},
            .summary = "The function only reads this parameter. Make it []const T or *const T.",
        },
        .undefined_then_branch => .{
            .severity = .review,
            .rules = &.{"rule-9-1"},
            .summary = "The first write after = undefined is inside a branch. A path that skips it reads undefined.",
        },
        .field_by_field_init => .{
            .severity = .review,
            .rules = &.{"rule-9-2"},
            .summary = "A struct starts as undefined and is written field by field. Write every field in one literal.",
        },
        .truncate_param => .{
            .severity = .review,
            .rules = &.{"rule-10-3"},
            .summary = "@truncate on a parameter drops the high bits of a value from outside. Use std.math.cast unless the low bits are the result.",
        },
        .bitcast_arith => .{
            .severity = .violation,
            .rules = &.{"rule-10-4"},
            .summary = "@bitCast changes the signedness and the result goes straight into arithmetic. Convert with std.math.cast.",
        },
        .enum_int_arith => .{
            .severity = .violation,
            .rules = &.{"rule-10-5"},
            .summary = "Arithmetic on an enum's integer invents a tag the enum may not have.",
        },
        .narrow_sum_widened => .{
            .severity = .violation,
            .rules = &.{"rule-10-6"},
            .summary = "The operation runs at the narrow operand width and only the result is widened. Use std.math.add(Wide, a, b).",
        },
        .narrow_operand => .{
            .severity = .violation,
            .rules = &.{"rule-10-7"},
            .summary = "A narrow inner operation feeds a wider one. Finish the inner operation at the wider width.",
        },
        .widening_cast_of_sum => .{
            .severity = .violation,
            .rules = &.{"rule-10-8"},
            .summary = "The cast widens the result after a narrow operation. Widen the operands first.",
        },
        .mixed_precedence => .{
            .severity = .violation,
            .rules = &.{"rule-12-1"},
            .summary = "Operators of different kinds share an expression without parentheses.",
        },
        .unbounded_loop => .{
            .severity = .review,
            .rules = &.{"rule-15-1"},
            .summary = "while (true) has no bound. A retry loop counts and returns an error at the bound.",
        },
        .empty_else_prong => .{
            .severity = .violation,
            .rules = &.{"rule-16-4"},
            .summary = "else => {} swallows every value the prongs do not list. Return an error or handle it.",
        },
        .recursion => .{
            .severity = .violation,
            .rules = &.{"rule-17-2"},
            .summary = "This function reaches itself through calls in this file. Use a loop and an explicit stack.",
        },
        .deprecated_api => .{
            .severity = .violation,
            .rules = &.{"rule-1-5"},
            .summary = "The Zig 0.17 std marks this deprecated. Use the replacement in parentheses.",
        },
        .ptrcast_span => .{
            .severity = .violation,
            .rules = &.{"rule-21-17"},
            .summary = "std.mem.span over a cast pointer walks until a zero that may be outside the object.",
        },
        .index_at_len => .{
            .severity = .review,
            .rules = &.{"rule-21-17"},
            .summary = "x[x.len] is one past the end, unless x is a sentinel slice or array.",
        },
        .memcpy_unchecked_len => .{
            .severity = .violation,
            .rules = &.{"rule-21-18"},
            .summary = "The copy length is a parameter that is never compared with either length.",
        },
        .try_before_release => .{
            .severity = .violation,
            .rules = &.{"rule-22-1"},
            .summary = "A later try or return leaves before this resource has a defer or errdefer.",
        },
        .free_not_owned => .{
            .severity = .violation,
            .rules = &.{"rule-22-2"},
            .summary = "free takes the exact slice alloc returned, not an address or a sub-slice.",
        },
        .same_path_twice => .{
            .severity = .review,
            .rules = &.{"rule-22-3"},
            .summary = "The same path is opened twice in one function. Open one handle that can do both.",
        },
        .raw_handle => .{
            .severity = .violation,
            .rules = &.{"rule-22-5"},
            .summary = "file.handle passed to std.posix bypasses the std.Io implementation that owns it.",
        },
        .use_after_close => .{
            .severity = .violation,
            .rules = &.{"rule-22-6"},
            .summary = "The handle is used after close.",
        },
        .errno_clear_after_call => .{
            .severity = .violation,
            .rules = &.{"rule-22-8"},
            .summary = "errno is cleared after the libc call. Clear it on the line before.",
        },
        .errno_without_failure => .{
            .severity = .violation,
            .rules = &.{"rule-22-9"},
            .summary = "errno is read without a -1 return in front of it.",
        },
        .errno_after_call => .{
            .severity = .violation,
            .rules = &.{"rule-22-10"},
            .summary = "A call runs between the -1 test and the errno read, and it can replace errno.",
        },
        .assert_on_input => .{
            .severity = .violation,
            .rules = &.{"dir-4-1"},
            .summary = "std.debug.assert on a C caller's value is an assumption in ReleaseFast. Check it and return an error.",
        },
        .unchecked_divisor => .{
            .severity = .violation,
            .rules = &.{"dir-4-1"},
            .summary = "The divisor is a parameter that is never compared in this function. Zero is illegal behavior in ReleaseFast.",
        },
        .unchecked_intcast => .{
            .severity = .violation,
            .rules = &.{ "rule-10-3", "rule-10-1" },
            .summary = "@intCast of a parameter that is never compared in this function. Use std.math.cast or check the range first.",
        },
        .unchecked_enum => .{
            .severity = .violation,
            .rules = &.{"rule-10-5"},
            .summary = "@enumFromInt of a parameter that is never compared in this function. Use std.enums.fromInt.",
        },
        .bare_union => .{
            .severity = .violation,
            .rules = &.{"rule-19-2"},
            .summary = "A bare union does not know its stored field. Use union(enum), or extern or packed union for a C or register layout.",
        },
        .write_read_only => .{
            .severity = .violation,
            .rules = &.{"rule-22-4"},
            .summary = "This handle was opened read-only (the openFile default) and is written. Open it .read_write or .write_only.",
        },
        .enum_else => .{
            .severity = .review,
            .rules = &.{"rule-16-4"},
            .summary = "The prongs name enum tags and else takes the rest without an error. On an exhaustive enum, list every tag so a new one is a compile error.",
        },
        .terminate_outside_main => .{
            .severity = .violation,
            .rules = &.{"rule-21-8"},
            .summary = "Only main ends the process. Return an error instead of @panic, std.debug.panic, or std.process.exit.",
        },
        .orelse_unreachable => .{
            .severity = .violation,
            .rules = &.{"dir-4-1"},
            .summary = "orelse unreachable is illegal behavior when the value is null. Return an error.",
        },
        .unwrap_assumed => .{
            .severity = .review,
            .rules = &.{"dir-4-1"},
            .summary = ".? on a call result assumes it is not null. Use orelse with an error unless a local check proves it.",
        },
        .assume_capacity => .{
            .severity = .review,
            .rules = &.{"dir-4-1"},
            .summary = "An AssumeCapacity call with no ensure...Capacity or initCapacity on this list earlier in the function.",
        },
        .unlimited_limit => .{
            .severity = .violation,
            .rules = &.{"dir-4-14"},
            .summary = "An unlimited read lets the file or the peer choose the allocation. Pass .limited(max).",
        },
        .float_to_int => .{
            .severity = .violation,
            .rules = &.{"rule-10-3"},
            .summary = "A float becomes an integer with no range check in this function. NaN, infinity, and large values are illegal behavior.",
        },
        .stack_escape => .{
            .severity = .violation,
            .rules = &.{"rule-18-6"},
            .summary = "This returns a pointer into a local that dies when the function returns.",
        },
        .posix_assumes_errno => .{
            .severity = .violation,
            .rules = &.{"dir-4-1"},
            .summary = "This std.posix wrapper maps an errno to unreachable. Call std.posix.system and switch on std.posix.errno.",
        },
        .thread_in_loop => .{
            .severity = .violation,
            .rules = &.{"dir-5-3"},
            .summary = "A thread is spawned inside a while loop, so the count follows the input. Spawn a fixed set of workers at start-up.",
        },
        .thread_outside_main => .{
            .severity = .review,
            .rules = &.{"dir-5-3"},
            .summary = "A thread is spawned outside main. Confirm it runs once at start-up for a fixed count, not per request.",
        },
        .thread_detached => .{
            .severity = .violation,
            .rules = &.{"dir-5-3"},
            .summary = "A detached thread has no end anyone waits for. Join every thread.",
        },
        .io_outside_main => .{
            .severity = .violation,
            .rules = &.{"dir-4-12"},
            .summary = "std.Io.Threaded is built outside main; it installs process-wide signal handlers. Take io: std.Io as a parameter.",
        },
        .handwritten_extern => .{
            .severity = .review,
            .rules = &.{"rule-8-4"},
            .summary = "A handwritten extern fn can drift from the C header. Take it from the translated header unless no header exposes it.",
        },
        .sentinel_return => .{
            .severity = .review,
            .rules = &.{"dir-4-7"},
            .summary = "An in-band value reports failure or not-found. Return ?T or an error unless a C ABI requires it.",
        },
        .build_unsafe_mode => .{
            .severity = .violation,
            .rules = &.{"dir-4-1"},
            .summary = "The build hard-codes a mode without safety checks. Use b.standardOptimizeOption and keep sanitize_c on.",
        },
        .ptrcast_reinterpret => .{
            .severity = .review,
            .rules = &.{"rule-11-3"},
            .summary = "@ptrCast between pointers to two value types. Reinterpret a value with @bitCast.",
        },
        .unreachable_file => .{
            .severity = .violation,
            .rules = &.{"rule-2-1"},
            .summary = "The root does not reach this file through @import, so the compiler never analyzes it.",
        },
        .float_mode_optimized => .{
            .severity = .violation,
            .rules = &.{"dir-4-15"},
            .summary = "@setFloatMode(.optimized) lets the compiler assume no NaN or infinity, so one from outside gives an undefined result.",
        },
        .noalias_param => .{
            .severity = .violation,
            .rules = &.{"rule-8-14"},
            .summary = "noalias is a promise nothing checks. A caller that passes two pointers to one object gets wrong results in ReleaseFast.",
        },
        .const_cast => .{
            .severity = .violation,
            .rules = &.{"rule-11-8"},
            .summary = "@constCast and @volatileCast drop a qualifier. A write through the result can hit a constant, and a dropped volatile can be optimized away.",
        },
        .c_variadic => .{
            .severity = .violation,
            .rules = &.{"rule-17-1"},
            .summary = "@cVaStart reads arguments that nothing counts or types. Take a slice.",
        },
        .pointer_arith => .{
            .severity = .violation,
            .rules = &.{"rule-18-4"},
            .summary = "Arithmetic on a many-item pointer has no length to check against. Slice it with its length and index the slice.",
        },
        .memcpy_alias => .{
            .severity = .review,
            .rules = &.{"rule-19-1"},
            .summary = "Both @memcpy arguments slice the same object. Unless the bounds keep the two regions apart, use @memmove.",
        },
        .atomic_order => .{
            .severity = .violation,
            .rules = &.{"rule-21-25"},
            .summary = "An atomic operation with an ordering weaker than .seq_cst. Use .seq_cst.",
        },
        .lock_twice => .{
            .severity = .violation,
            .rules = &.{"dir-5-2"},
            .summary = "This mutex is locked again while this function still holds it. A non-recursive lock waits for itself forever.",
        },
    };
}

const Finding = struct {
    check: Check,
    /// 1-based.
    line: usize,
    /// 1-based, in bytes.
    column: usize,
    /// The name the finding is about, or the parse error text. Lives as long as the arena.
    subject: []const u8,
};

const Fn = struct {
    decl: Node.Index,
    name: []const u8,
    name_token: TokenIndex,
    body_first: TokenIndex,
    body_last: TokenIndex,
    is_pub: bool,
    is_export: bool,
    return_type: Node.OptionalIndex,
};

const IntType = struct {
    signed: bool,
    bits: u16,
};

const Edge = struct {
    from: usize,
    to: usize,
};

const OpClass = enum { logic, bitwise, shift, arith, other };

const Linter = struct {
    arena: Allocator,
    tree: *const Ast,
    source: [:0]const u8,
    fns: []const Fn,
    token_count: TokenIndex,
    /// The path argument of each `openFile` and `createFile` call, by enclosing function.
    opens: std.ArrayList(Open),
    /// Every `x.lock()` and `x.unlock()` call, by enclosing function.
    locks: std.ArrayList(LockCall),
    findings: std.ArrayList(Finding),

    fn add(l: *Linter, check: Check, tok: TokenIndex, subject: []const u8) Allocator.Error!void {
        const loc = l.tree.tokenLocation(0, tok);
        if (allowed(l.source, loc.line_start, check)) return;
        try l.findings.append(l.arena, .{
            .check = check,
            .line = loc.line + 1,
            .column = loc.column + 1,
            .subject = subject,
        });
    }

    fn text(l: *const Linter, tok: TokenIndex) []const u8 {
        return l.tree.tokenSlice(tok);
    }

    fn tag(l: *const Linter, node: Node.Index) Node.Tag {
        return l.tree.nodeTag(node);
    }

    fn tokTag(l: *const Linter, tok: TokenIndex) std.zig.Token.Tag {
        return l.tree.tokenTag(tok);
    }
};

const Open = struct {
    fn_index: usize,
    path: Node.Index,
};

const LockCall = struct {
    fn_index: usize,
    receiver: Node.Index,
    at: TokenIndex,
    is_lock: bool,
    /// For an unlock, the token where the mutex is free again: the call itself, or
    /// the end of the block that holds a `defer` of it. Null for a lock, and for an
    /// `errdefer` unlock, which does not run on success.
    frees_at: ?TokenIndex,
};

/// Lints one file. Every finding and subject lives in `arena`.
fn lint(arena: Allocator, source: [:0]const u8) Allocator.Error![]Finding {
    if (tooDeep(source)) |offset| {
        const findings = try arena.alloc(Finding, 1);
        const line = std.mem.count(u8, source[0..offset], "\n") + 1;
        const line_start = if (std.mem.findScalarLast(u8, source[0..offset], '\n')) |nl| nl + 1 else 0;
        findings[0] = .{ .check = .parse_error, .line = line, .column = offset - line_start + 1, .subject = deep_subject };
        return findings;
    }
    const tree = try Ast.parse(arena, source, .{});
    var l: Linter = .{
        .arena = arena,
        .tree = &tree,
        .source = source,
        .fns = &.{},
        .token_count = std.math.cast(TokenIndex, tree.tokens.len) orelse return error.OutOfMemory,
        .opens = .empty,
        .locks = .empty,
        .findings = .empty,
    };
    if (tree.errors.len > 0) {
        const first = tree.errors[0];
        var message: std.Io.Writer.Allocating = .init(arena);
        tree.renderError(first, &message.writer) catch return error.OutOfMemory;
        try l.add(.parse_error, first.token, message.written());
        return l.findings.items;
    }
    l.fns = try collectFns(arena, &tree);
    const count = std.math.cast(u32, tree.nodes.len) orelse return error.OutOfMemory;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        try lintNode(&l, @fromBackingInt(@intCast(index)));
    }
    for (l.fns) |f| try lintFn(&l, f);
    try lintOpens(&l);
    try lintLocks(&l);
    try lintRecursion(&l);
    std.mem.sortUnstable(Finding, l.findings.items, {}, findingBefore);
    return l.findings.items;
}

fn findingBefore(_: void, a: Finding, b: Finding) bool {
    if (a.line != b.line) return a.line < b.line;
    if (a.column != b.column) return a.column < b.column;
    return @backingInt(a.check) < @backingInt(b.check);
}

const max_nesting: usize = 256;
const deep_subject = "nesting deeper than 256 levels; misra-lint does not parse it";

const opening_tags = [_]std.zig.Token.Tag{ .l_paren, .l_bracket, .l_brace };
const closing_tags = [_]std.zig.Token.Tag{ .r_paren, .r_bracket, .r_brace };
/// Tokens the parser handles by calling itself once per token, such as `!!!x` or `****T`.
const prefix_tags = [_]std.zig.Token.Tag{
    .bang,
    .minus,
    .minus_percent,
    .tilde,
    .ampersand,
    .keyword_try,
    .asterisk,
    .question_mark,
};

fn tokenIn(tag: std.zig.Token.Tag, set: []const std.zig.Token.Tag) bool {
    return std.mem.findScalar(std.zig.Token.Tag, set, tag) != null;
}

/// The byte offset where bracket nesting or a run of prefix operators passes
/// `max_nesting`, or null. std.zig.Ast.parse recurses once per level, so deep
/// input would exhaust the stack; the tokenizer does not recurse.
fn tooDeep(source: [:0]const u8) ?usize {
    var tokenizer: std.zig.Tokenizer = .init(source);
    var depth: usize = 0;
    var prefix_run: usize = 0;
    // A file has at most one token per byte, plus the end-of-file token.
    var budget: usize = source.len + 1;
    while (budget > 0) : (budget -= 1) {
        const token = tokenizer.next();
        if (token.tag == .eof) return null;
        if (tokenIn(token.tag, &opening_tags)) {
            depth += 1;
            if (depth > max_nesting) return token.loc.start;
        } else if (tokenIn(token.tag, &closing_tags)) {
            depth -|= 1;
        }
        prefix_run = if (tokenIn(token.tag, &prefix_tags)) prefix_run + 1 else 0;
        if (prefix_run > max_nesting) return token.loc.start;
    }
    return null;
}

/// True when the comment on the line holding `line_start`, or a comment that
/// fills the line above it, carries `misra-lint: allow <check> <reason>` with a
/// non-empty reason. Text inside a string literal does not count.
fn allowed(source: []const u8, line_start: usize, check: Check) bool {
    const line_end = std.mem.findScalarPos(u8, source, line_start, '\n') orelse source.len;
    if (commentOf(source[line_start..line_end])) |comment| {
        if (allowsOn(comment, check)) return true;
    }
    if (line_start == 0) return false;
    const above_end = line_start - 1;
    const above_start = if (std.mem.findScalarLast(u8, source[0..above_end], '\n')) |nl| nl + 1 else 0;
    const above = std.mem.trimStart(u8, source[above_start..above_end], " \t");
    return std.mem.startsWith(u8, above, "//") and allowsOn(above, check);
}

/// The `//` comment of a line, skipping string and character literals, or null.
fn commentOf(line: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t"), "\\\\")) return null;
    var quote: ?u8 = null;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const c = line[i];
        if (quote) |q| {
            if (c == '\\') {
                i += 1;
            } else if (c == q) {
                quote = null;
            }
        } else if (c == '"' or c == '\'') {
            quote = c;
        } else if (c == '/' and i + 1 < line.len and line[i + 1] == '/') {
            return line[i..];
        }
    }
    return null;
}

fn allowsOn(line: []const u8, check: Check) bool {
    const at = std.mem.find(u8, line, allow_marker) orelse return false;
    const rest = line[at + allow_marker.len ..];
    const name = @tagName(check);
    if (!std.mem.startsWith(u8, rest, name) or rest.len == name.len) return false;
    if (rest[name.len] != ' ' and rest[name.len] != '\t') return false;
    return std.mem.trim(u8, rest[name.len..], " \t\r").len > 0;
}

fn collectFns(arena: Allocator, tree: *const Ast) Allocator.Error![]const Fn {
    var fns: std.ArrayList(Fn) = .empty;
    const count = std.math.cast(u32, tree.nodes.len) orelse return error.OutOfMemory;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const node: Node.Index = @fromBackingInt(@intCast(index));
        if (tree.nodeTag(node) != .fn_decl) continue;
        var buf: [1]Node.Index = undefined;
        const proto = tree.fullFnProto(&buf, node) orelse continue;
        const body = tree.nodeData(node).node_and_node[1];
        const name_token = proto.name_token orelse proto.ast.fn_token;
        try fns.append(arena, .{
            .decl = node,
            .name = if (proto.name_token) |t| tree.tokenSlice(t) else "",
            .name_token = name_token,
            .body_first = tree.firstToken(body),
            .body_last = tree.lastToken(body),
            .is_pub = proto.visib_token != null,
            .is_export = if (proto.extern_export_inline_token) |t| tree.tokenTag(t) == .keyword_export else false,
            .return_type = proto.ast.return_type,
        });
    }
    return fns.items;
}

/// The innermost function whose body holds `tok`.
// ponytail: linear scan per lookup, O(nodes * fns). An interval tree pays off only on files with thousands of functions.
fn enclosingFn(l: *const Linter, tok: TokenIndex) ?usize {
    var best: ?usize = null;
    for (l.fns, 0..) |f, i| {
        if (tok < f.body_first or tok > f.body_last) continue;
        if (best) |b| {
            if (f.body_last - f.body_first >= l.fns[b].body_last - l.fns[b].body_first) continue;
        }
        best = i;
    }
    return best;
}

fn fnIndexByName(l: *const Linter, name: []const u8) ?usize {
    var found: ?usize = null;
    for (l.fns, 0..) |f, i| {
        if (!std.mem.eql(u8, f.name, name)) continue;
        if (found != null) return null;
        found = i;
    }
    return found;
}

fn tagIn(tag: Node.Tag, set: []const Node.Tag) bool {
    return std.mem.findScalar(Node.Tag, set, tag) != null;
}

fn isEmptyBlock(l: *const Linter, node: Node.Index) bool {
    if (!tagIn(l.tag(node), &.{ .block_two, .block_two_semicolon })) return false;
    var buf: [2]Node.Index = undefined;
    const statements = l.tree.blockStatements(&buf, node) orelse return false;
    return statements.len == 0;
}

fn addressTaken(l: *const Linter, first: TokenIndex, last: TokenIndex, name: []const u8) bool {
    var t = first;
    while (t < last) : (t += 1) {
        if (l.tokTag(t) == .ampersand and std.mem.eql(u8, l.text(t + 1), name)) return true;
    }
    return false;
}

const branch_tags = [_]Node.Tag{
    .if_simple,
    .@"if",
    .while_simple,
    .while_cont,
    .@"while",
    .for_simple,
    .@"for",
    .@"switch",
    .switch_comma,
};

fn unparen(l: *const Linter, start: Node.Index) Node.Index {
    var node = start;
    while (l.tag(node) == .grouped_expression) node = l.tree.nodeData(node).node_and_token[0];
    return node;
}

fn isIdent(l: *const Linter, node: Node.Index, name: []const u8) bool {
    return l.tag(node) == .identifier and std.mem.eql(u8, l.text(l.tree.nodeMainToken(node)), name);
}

/// True when `node` is the field chain `names[0].names[1]...`.
fn isChain(l: *const Linter, start: Node.Index, names: []const []const u8) bool {
    var node = start;
    var i = names.len;
    while (i > 1) {
        i -= 1;
        if (l.tag(node) != .field_access) return false;
        const data = l.tree.nodeData(node).node_and_token;
        if (!std.mem.eql(u8, l.text(data[1]), names[i])) return false;
        node = data[0];
    }
    return isIdent(l, node, names[0]);
}

/// The root identifier of a field chain, as text, or null.
fn chainRoot(l: *const Linter, start: Node.Index) ?[]const u8 {
    var node = start;
    while (l.tag(node) == .field_access) node = l.tree.nodeData(node).node_and_token[0];
    if (l.tag(node) != .identifier) return null;
    return l.text(l.tree.nodeMainToken(node));
}

fn fieldName(l: *const Linter, node: Node.Index) ?[]const u8 {
    if (l.tag(node) != .field_access) return null;
    return l.text(l.tree.nodeData(node).node_and_token[1]);
}

fn builtinName(l: *const Linter, node: Node.Index) ?[]const u8 {
    return switch (l.tag(node)) {
        .builtin_call_two, .builtin_call_two_comma, .builtin_call, .builtin_call_comma => l.text(l.tree.nodeMainToken(node)),
        // misra-lint: allow enum_else std.zig.Ast.Node.Tag has about 200 std-owned tags; only the builtin call tags apply
        else => null,
    };
}

fn isBuiltin(l: *const Linter, node: Node.Index, name: []const u8) bool {
    const found = builtinName(l, node) orelse return false;
    return std.mem.eql(u8, found, name);
}

fn sameTokens(l: *const Linter, a: Node.Index, b: Node.Index) bool {
    const a_first = l.tree.firstToken(a);
    const a_last = l.tree.lastToken(a);
    const b_first = l.tree.firstToken(b);
    const b_last = l.tree.lastToken(b);
    if (a_last - a_first != b_last - b_first) return false;
    var i: TokenIndex = 0;
    while (i <= a_last - a_first) : (i += 1) {
        if (!std.mem.eql(u8, l.text(a_first + i), l.text(b_first + i))) return false;
    }
    return true;
}

fn tokensHoldIdent(l: *const Linter, first: TokenIndex, last: TokenIndex, name: []const u8) bool {
    var t = first;
    while (t <= last) : (t += 1) {
        if (l.tokTag(t) == .identifier and std.mem.eql(u8, l.text(t), name)) return true;
    }
    return false;
}

fn tokensHoldTag(l: *const Linter, first: TokenIndex, last: TokenIndex, wanted: std.zig.Token.Tag) bool {
    var t = first;
    while (t <= last) : (t += 1) {
        if (l.tokTag(t) == wanted) return true;
    }
    return false;
}

fn nodeHoldsIdent(l: *const Linter, node: Node.Index, name: []const u8) bool {
    return tokensHoldIdent(l, l.tree.firstToken(node), l.tree.lastToken(node), name);
}

fn isAssignOp(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .equal,
        .plus_equal,
        .plus_percent_equal,
        .plus_pipe_equal,
        .minus_equal,
        .minus_percent_equal,
        .minus_pipe_equal,
        .asterisk_equal,
        .asterisk_percent_equal,
        .asterisk_pipe_equal,
        .slash_equal,
        .percent_equal,
        .ampersand_equal,
        .pipe_equal,
        .caret_equal,
        .angle_bracket_angle_bracket_left_equal,
        .angle_bracket_angle_bracket_left_pipe_equal,
        .angle_bracket_angle_bracket_right_equal,
        => true,
        // misra-lint: allow enum_else std.zig.Token.Tag is std-owned; only the listed tags are assignments
        else => false,
    };
}

fn isCompareOp(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .equal_equal,
        .bang_equal,
        .angle_bracket_left,
        .angle_bracket_left_equal,
        .angle_bracket_right,
        .angle_bracket_right_equal,
        => true,
        // misra-lint: allow enum_else std.zig.Token.Tag is std-owned; only the listed tags are comparisons
        else => false,
    };
}

fn opClass(tag: Node.Tag) OpClass {
    return switch (tag) {
        .bool_and, .bool_or => .logic,
        .bit_and, .bit_or, .bit_xor => .bitwise,
        .shl, .shr, .shl_sat => .shift,
        .add, .sub, .mul, .div, .mod, .add_wrap, .sub_wrap, .mul_wrap, .add_sat, .sub_sat, .mul_sat => .arith,
        // misra-lint: allow enum_else std.zig.Ast.Node.Tag is std-owned; only the listed tags are binary operators
        else => .other,
    };
}

/// The operations whose result is undefined when it does not fit.
fn isTrappingArith(tag: Node.Tag) bool {
    return switch (tag) {
        .add, .sub, .mul, .shl => true,
        // misra-lint: allow enum_else std.zig.Ast.Node.Tag is std-owned; only the listed tags trap on overflow
        else => false,
    };
}

fn intType(name: []const u8) ?IntType {
    if (name.len < 2) return null;
    const signed = switch (name[0]) {
        'i' => true,
        'u' => false,
        else => return null,
    };
    const bits = std.fmt.parseInt(u16, name[1..], 10) catch return null;
    return .{ .signed = signed, .bits = bits };
}

fn typeOfNode(l: *const Linter, node: Node.Index) ?IntType {
    if (l.tag(node) != .identifier) return null;
    return intType(l.text(l.tree.nodeMainToken(node)));
}

/// The declared integer type of a parameter or a typed local of function `f`.
fn identType(l: *const Linter, f: Fn, name: []const u8) ?IntType {
    var buf: [1]Node.Index = undefined;
    if (l.tree.fullFnProto(&buf, f.decl)) |proto| {
        var it = proto.iterate(l.tree);
        while (it.next()) |param| {
            const name_token = param.name_token orelse continue;
            if (!std.mem.eql(u8, l.text(name_token), name)) continue;
            const type_expr = param.type_expr orelse return null;
            return typeOfNode(l, type_expr);
        }
    }
    // Zig forbids shadowing, so one `const name: T =` in the body is the declaration.
    var t = f.body_first;
    while (t + 4 <= f.body_last) : (t += 1) {
        const kw = l.tokTag(t);
        if (kw != .keyword_const and kw != .keyword_var) continue;
        if (!std.mem.eql(u8, l.text(t + 1), name)) continue;
        if (l.tokTag(t + 2) != .colon or l.tokTag(t + 4) != .equal) return null;
        return intType(l.text(t + 3));
    }
    return null;
}

/// The width a trapping `+`, `-`, `*`, or `<<` runs at, when every operand is a
/// typed name or a literal and the typed names agree.
fn arithType(l: *const Linter, node: Node.Index) ?IntType {
    if (!isTrappingArith(l.tag(node))) return null;
    const f = l.fns[enclosingFn(l, l.tree.nodeMainToken(node)) orelse return null];
    const sides = l.tree.nodeData(node).node_and_node;
    var found: ?IntType = null;
    for ([_]Node.Index{ sides[0], sides[1] }) |side| {
        switch (l.tag(side)) {
            .number_literal => continue,
            .identifier => {
                const t = identType(l, f, l.text(l.tree.nodeMainToken(side))) orelse return null;
                if (found) |prev| {
                    if (prev.bits != t.bits or prev.signed != t.signed) return null;
                }
                found = t;
            },
            // misra-lint: allow enum_else std.zig.Ast.Node.Tag is std-owned; only these node kinds name a builtin
            else => return null,
        }
    }
    return found;
}

fn returnType(l: *const Linter, f: Fn) ?IntType {
    const node = f.return_type.unwrap() orelse return null;
    if (l.tag(node) == .error_union) return typeOfNode(l, l.tree.nodeData(node).node_and_node[1]);
    return typeOfNode(l, node);
}

fn wider(outer: IntType, inner: IntType) bool {
    return outer.bits > inner.bits;
}

fn lintNode(l: *Linter, node: Node.Index) Allocator.Error!void {
    const tree = l.tree;
    const main_token = tree.nodeMainToken(node);
    switch (l.tag(node)) {
        .block, .block_semicolon, .block_two, .block_two_semicolon => {
            var buf: [2]Node.Index = undefined;
            const statements = tree.blockStatements(&buf, node) orelse return;
            try lintStatements(l, statements);
        },
        .builtin_call_two, .builtin_call_two_comma, .builtin_call, .builtin_call_comma => try lintBuiltin(l, node),
        .simple_var_decl, .aligned_var_decl, .local_var_decl, .global_var_decl => try lintVarDecl(l, node),
        .container_decl,
        .container_decl_trailing,
        .container_decl_two,
        .container_decl_two_trailing,
        .container_decl_arg,
        .container_decl_arg_trailing,
        => try lintContainer(l, node),
        .field_access => {
            const heap = [_][]const u8{ "page_allocator", "c_allocator", "raw_c_allocator" };
            for (heap) |name| {
                if (!isChain(l, node, &.{ "std", "heap", name })) continue;
                const f = enclosingFn(l, main_token);
                const in_main = if (f) |i| std.mem.eql(u8, l.fns[i].name, "main") else false;
                if (!in_main) try l.add(.global_allocator, tree.nodeData(node).node_and_token[1], name);
            }
            const libc = [_][]const u8{ "malloc", "calloc", "realloc", "free" };
            for (libc) |name| {
                if (isChain(l, node, &.{ "std", "c", name })) try l.add(.global_c_alloc, tree.nodeData(node).node_and_token[1], name);
            }
            for (std_lists.deprecated) |entry| {
                if (!matchesDotted(l, node, entry[0])) continue;
                try l.add(.deprecated_api, tree.nodeData(node).node_and_token[1], if (entry[1].len > 0) entry[1] else entry[0]);
                break;
            }
            if (isChain(l, node, &.{ "std", "Io", "Threaded", "global_single_threaded" }) and !inMainOrTest(l, main_token)) {
                try l.add(.io_outside_main, tree.nodeData(node).node_and_token[1], "");
            }
        },
        .@"catch" => {
            const handler = unparen(l, tree.nodeData(node).node_and_node[1]);
            if (l.tag(handler) == .unreachable_literal) try l.add(.catch_unreachable, main_token, "");
            const payload: ?[]const u8 = if (l.tokTag(main_token + 1) == .pipe) l.text(main_token + 2) else null;
            if (isEmptyBlock(l, handler) or discardsOnly(l, handler, payload)) try l.add(.catch_empty, main_token, "");
        },
        .@"orelse" => {
            const handler = unparen(l, tree.nodeData(node).node_and_node[1]);
            if (l.tag(handler) == .unreachable_literal) try l.add(.orelse_unreachable, main_token, "");
        },
        .unwrap_optional => {
            const value = unparen(l, tree.nodeData(node).node_and_token[0]);
            var call_buf: [1]Node.Index = undefined;
            // In a test block a null is a failed test, which is the point of the test.
            const in_fn = enclosingFn(l, main_token) != null;
            if (in_fn and tree.fullCall(&call_buf, value) != null) try l.add(.unwrap_assumed, tree.nodeData(node).node_and_token[1], "");
        },
        .enum_literal => {
            const value = l.text(main_token);
            if (std.mem.eql(u8, value, "unlimited")) try l.add(.unlimited_limit, main_token, "");
            // `.field = .Value`: the field name sits three tokens back.
            if (main_token >= 3 and l.tokTag(main_token - 2) == .equal) {
                const field = l.text(main_token - 3);
                const unsafe_mode = std.mem.eql(u8, value, "ReleaseFast") or std.mem.eql(u8, value, "ReleaseSmall");
                if (std.mem.eql(u8, field, "optimize") and unsafe_mode) try l.add(.build_unsafe_mode, main_token, value);
                if (std.mem.eql(u8, field, "sanitize_c") and std.mem.eql(u8, value, "off")) try l.add(.build_unsafe_mode, main_token, "sanitize_c = .off");
            }
        },
        .fn_proto_simple, .fn_proto_multi, .fn_proto_one, .fn_proto => {
            var buf: [1]Node.Index = undefined;
            const proto = tree.fullFnProto(&buf, node) orelse return;
            const marker = proto.extern_export_inline_token orelse return;
            if (l.tokTag(marker) == .keyword_extern) try l.add(.handwritten_extern, marker, if (proto.name_token) |t| l.text(t) else "");
        },
        .@"switch", .switch_comma => try lintSwitch(l, node),
        .switch_case_one, .switch_case, .switch_case_inline_one, .switch_case_inline => {
            const case = tree.fullSwitchCase(node) orelse return;
            if (case.ast.values.len != 0) return;
            if (isEmptyBlock(l, case.ast.target_expr)) try l.add(.empty_else_prong, tree.firstToken(node), "");
        },
        .while_simple, .while_cont, .@"while" => {
            const loop = tree.fullWhile(node) orelse return;
            if (isIdent(l, loop.ast.cond_expr, "true")) try l.add(.unbounded_loop, loop.ast.while_token, "");
        },
        .array_access => {
            const data = tree.nodeData(node).node_and_node;
            const index = unparen(l, data[1]);
            const field = fieldName(l, index) orelse return;
            if (!std.mem.eql(u8, field, "len")) return;
            if (!sameTokens(l, data[0], tree.nodeData(index).node_and_token[0])) return;
            const object = unparen(l, data[0]);
            if (l.tag(object) == .identifier) {
                if (enclosingFn(l, main_token)) |fn_index| {
                    if (sentinelDeclared(l, l.fns[fn_index], l.text(tree.nodeMainToken(object)))) return;
                }
            }
            try l.add(.index_at_len, main_token, "");
        },
        .call_one, .call_one_comma, .call, .call_comma => try lintCall(l, node),
        .div, .mod => {
            const divisor = uncheckedDivisor(l, tree.nodeData(node).node_and_node[1], main_token) orelse return;
            try l.add(.unchecked_divisor, main_token, divisor);
        },
        .add, .sub, .assign_add, .assign_sub => {
            const f = l.fns[enclosingFn(l, main_token) orelse return];
            const sides = tree.nodeData(node).node_and_node;
            for ([_]Node.Index{ sides[0], sides[1] }) |start| {
                const side = unparen(l, start);
                if (l.tag(side) != .identifier) continue;
                const name = l.text(tree.nodeMainToken(side));
                if (!declaredManyPtr(l, f, name)) continue;
                try l.add(.pointer_arith, main_token, name);
                break;
            }
        },
        .@"return" => {
            const value = tree.nodeData(node).opt_node.unwrap() orelse return;
            const inner = unparen(l, value);
            try lintEscape(l, inner);
            if (enclosingFn(l, main_token)) |fn_index| {
                if (returnType(l, l.fns[fn_index]) != null) try lintFloatToInt(l, inner, true);
                const minus_one = l.tag(inner) == .negation and std.mem.eql(u8, l.text(tree.nodeMainToken(tree.nodeData(inner).node)), "1");
                var call_buf: [1]Node.Index = undefined;
                const max_int = if (tree.fullCall(&call_buf, inner)) |call| isChain(l, call.ast.fn_expr, &.{ "std", "math", "maxInt" }) else false;
                if ((minus_one or max_int) and !l.fns[fn_index].is_export) try l.add(.sentinel_return, main_token, "");
            }
            const narrow = arithType(l, inner) orelse return;
            const f = l.fns[enclosingFn(l, main_token) orelse return];
            const ret = returnType(l, f) orelse return;
            if (wider(ret, narrow)) try l.add(.narrow_sum_widened, tree.nodeMainToken(inner), "");
        },
        // misra-lint: allow empty_else_prong only the tags above have a node check
        else => {},
    }
    const class = opClass(l.tag(node));
    if (class != .other) try lintBinary(l, node, class);
}

fn lintBinary(l: *Linter, node: Node.Index, class: OpClass) Allocator.Error!void {
    const tree = l.tree;
    const node_tag = l.tag(node);
    const sides = tree.nodeData(node).node_and_node;
    for ([_]Node.Index{ sides[0], sides[1] }) |side| {
        const side_tag = l.tag(side);
        const side_class = opClass(side_tag);
        if (side_class == .other or side_tag == node_tag) continue;
        const both_arith = class == .arith and side_class == .arith;
        const logic_mix = class == .logic and side_class == .logic;
        const bit_mix = class != .logic and side_class != .logic;
        if (!both_arith and (logic_mix or bit_mix)) {
            try l.add(.mixed_precedence, tree.nodeMainToken(node), "");
            break;
        }
    }
    if (class != .arith) return;
    for ([_][2]Node.Index{ .{ sides[0], sides[1] }, .{ sides[1], sides[0] } }) |pair| {
        const side = unparen(l, pair[0]);
        if (isBuiltin(l, side, "@intFromEnum") or isBuiltin(l, side, "@backingInt")) {
            try l.add(.enum_int_arith, tree.nodeMainToken(node), "");
        }
        if (isBitCast(l, side) and isTrappingArith(node_tag)) try l.add(.bitcast_arith, tree.nodeMainToken(node), "");
        if (!isTrappingArith(node_tag)) continue;
        const inner = arithType(l, side) orelse continue;
        const f = l.fns[enclosingFn(l, tree.nodeMainToken(node)) orelse continue];
        const other = unparen(l, pair[1]);
        if (l.tag(other) != .identifier) continue;
        const outer = identType(l, f, l.text(tree.nodeMainToken(other))) orelse continue;
        if (wider(outer, inner)) try l.add(.narrow_operand, tree.nodeMainToken(side), "");
    }
}

fn isBitCast(l: *const Linter, node: Node.Index) bool {
    if (isBuiltin(l, node, "@bitCast")) return true;
    if (!isBuiltin(l, node, "@as")) return false;
    var buf: [2]Node.Index = undefined;
    const params = l.tree.builtinCallParams(&buf, node) orelse return false;
    return params.len == 2 and isBuiltin(l, unparen(l, params[1]), "@bitCast");
}

fn lintBuiltin(l: *Linter, node: Node.Index) Allocator.Error!void {
    const tree = l.tree;
    const main_token = tree.nodeMainToken(node);
    const name = l.text(main_token);
    var buf: [2]Node.Index = undefined;
    const params = tree.builtinCallParams(&buf, node) orelse return;
    if (std.mem.eql(u8, name, "@setRuntimeSafety")) {
        if (params.len == 1 and !isIdent(l, params[0], "true")) try l.add(.runtime_safety_off, main_token, "");
    } else if (std.mem.eql(u8, name, "@as")) {
        if (params.len != 2) return;
        const target = typeOfNode(l, params[0]) orelse return;
        const narrow = arithType(l, unparen(l, params[1])) orelse return;
        if (wider(target, narrow)) try l.add(.widening_cast_of_sum, main_token, "");
    } else if (std.mem.eql(u8, name, "@truncate")) {
        if (params.len != 1 or l.tag(params[0]) != .identifier) return;
        const value = l.text(tree.nodeMainToken(params[0]));
        const f = l.fns[enclosingFn(l, main_token) orelse return];
        if (isParam(l, f, value)) try l.add(.truncate_param, main_token, value);
    } else if (std.mem.eql(u8, name, "@intCast")) {
        if (params.len != 1) return;
        // `zig fmt` writes `@fromBackingInt(@intCast(x))`; the enum check owns that pair.
        if (l.tokTag(main_token - 1) == .l_paren and isEnumConversion(l.text(main_token - 2))) return;
        const value = uncheckedParam(l, params[0], main_token) orelse return;
        try l.add(.unchecked_intcast, main_token, value);
    } else if (isEnumConversion(name)) {
        if (params.len != 1) return;
        var arg = unparen(l, params[0]);
        if (isBuiltin(l, arg, "@intCast")) {
            var inner_buf: [2]Node.Index = undefined;
            const inner = tree.builtinCallParams(&inner_buf, arg) orelse return;
            if (inner.len != 1) return;
            arg = inner[0];
        }
        const value = uncheckedParam(l, arg, main_token) orelse return;
        try l.add(.unchecked_enum, main_token, value);
    } else if (isDivision(name)) {
        if (params.len != 2) return;
        const divisor = uncheckedDivisor(l, params[1], main_token) orelse return;
        try l.add(.unchecked_divisor, main_token, divisor);
    } else if (std.mem.eql(u8, name, "@ptrCast")) {
        if (params.len != 1) return;
        const arg = unparen(l, params[0]);
        const f = l.fns[enclosingFn(l, main_token) orelse return];
        // Overlaying a struct on checked bytes is the allowed case (Rule 21.17's headerOf).
        if (l.tag(arg) == .identifier and declaredOverBytes(l, f, l.text(tree.nodeMainToken(arg)))) return;
        if (l.tag(arg) == .identifier or l.tag(arg) == .address_of) try l.add(.ptrcast_reinterpret, main_token, "");
    } else if (std.mem.eql(u8, name, "@panic")) {
        if (!inMainOrTest(l, main_token)) try l.add(.terminate_outside_main, main_token, "");
    } else if (std.mem.eql(u8, name, "@intFromFloat")) {
        try lintFloatToInt(l, node, false);
    } else if (std.mem.eql(u8, name, "@setFloatMode")) {
        if (params.len == 1 and std.mem.eql(u8, l.text(tree.lastToken(params[0])), "optimized")) {
            try l.add(.float_mode_optimized, main_token, "");
        }
    } else if (std.mem.eql(u8, name, "@constCast") or std.mem.eql(u8, name, "@volatileCast")) {
        try l.add(.const_cast, main_token, name);
    } else if (std.mem.eql(u8, name, "@cVaStart")) {
        try l.add(.c_variadic, main_token, "");
    } else if (isAtomicBuiltin(name)) {
        try lintOrders(l, params);
    } else if (std.mem.eql(u8, name, "@memcpy") or std.mem.eql(u8, name, "@memmove")) {
        if (params.len != 2) return;
        if (std.mem.eql(u8, name, "@memcpy") and sameTokens(l, sliceBase(l, params[0]), sliceBase(l, params[1]))) {
            try l.add(.memcpy_alias, main_token, "");
        }
        const dest = tree.fullSlice(unparen(l, params[0])) orelse return;
        const src = tree.fullSlice(unparen(l, params[1])) orelse return;
        const dest_end = dest.ast.end.unwrap() orelse return;
        const src_end = src.ast.end.unwrap() orelse return;
        if (l.tag(dest_end) != .identifier or !sameTokens(l, dest_end, src_end)) return;
        const len_name = l.text(tree.nodeMainToken(dest_end));
        const f = l.fns[enclosingFn(l, main_token) orelse return];
        if (!isParam(l, f, len_name)) return;
        if (!comparedIn(l, f.body_first, main_token, len_name)) try l.add(.memcpy_unchecked_len, main_token, len_name);
    }
}

/// True when `name` is declared in `f` (parameter or local) with `u8` in its type,
/// such as `[]const u8` or `[*]align(8) const u8`.
fn declaredOverBytes(l: *const Linter, f: Fn, name: []const u8) bool {
    var t = l.tree.firstToken(f.decl);
    while (t + 1 <= f.body_last) : (t += 1) {
        if (l.tokTag(t) != .identifier or !std.mem.eql(u8, l.text(t), name) or l.tokTag(t + 1) != .colon) continue;
        // The type ends at `=`, `,`, `;`, or the `)` that closes a parameter list.
        var u = t + 2;
        var depth: usize = 0;
        while (u <= f.body_last) : (u += 1) {
            const tag = l.tokTag(u);
            if (tag == .l_paren) depth += 1;
            if (tag == .r_paren) {
                if (depth == 0) break;
                depth -= 1;
            }
            if (depth == 0 and tokenIn(tag, &.{ .equal, .comma, .semicolon })) break;
            if (std.mem.eql(u8, l.text(u), "u8")) return true;
        }
        return false;
    }
    return false;
}

/// True when the field chain at `start` spells `dotted` (`std.mem.indexOfScalar`).
fn matchesDotted(l: *const Linter, start: Node.Index, dotted: []const u8) bool {
    var node = start;
    var rest = dotted;
    while (l.tag(node) == .field_access) {
        const dot = std.mem.findScalarLast(u8, rest, '.') orelse return false;
        const data = l.tree.nodeData(node).node_and_token;
        if (!std.mem.eql(u8, l.text(data[1]), rest[dot + 1 ..])) return false;
        rest = rest[0..dot];
        node = data[0];
    }
    return isIdent(l, node, rest);
}

/// True when `tok` is inside the body of a `while` loop.
fn insideWhile(l: *const Linter, tok: TokenIndex) bool {
    const count = std.math.cast(u32, l.tree.nodes.len) orelse return false;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const node: Node.Index = @fromBackingInt(index);
        if (!tagIn(l.tag(node), &.{ .while_simple, .while_cont, .@"while" })) continue;
        const loop = l.tree.fullWhile(node) orelse continue;
        if (tok >= l.tree.firstToken(loop.ast.then_expr) and tok <= l.tree.lastToken(loop.ast.then_expr)) return true;
    }
    return false;
}

fn isEnumConversion(name: []const u8) bool {
    return std.mem.eql(u8, name, "@fromBackingInt") or std.mem.eql(u8, name, "@enumFromInt");
}

const float_rounding = [_][]const u8{ "@trunc", "@floor", "@ceil", "@round", "@intFromFloat" };

/// Reports a rounding builtin whose result is an integer (it is returned from an
/// integer function or stored in an integer local) when its argument is not a
/// name compared earlier in the function.
fn lintFloatToInt(l: *Linter, start: Node.Index, in_result: bool) Allocator.Error!void {
    const node = unparen(l, start);
    const name = builtinName(l, node) orelse return;
    // `@intFromFloat` always yields an integer, so the builtin pass reports it wherever it stands.
    if (in_result and std.mem.eql(u8, name, "@intFromFloat")) return;
    var known = false;
    for (float_rounding) |item| known = known or std.mem.eql(u8, name, item);
    if (!known) return;
    const main_token = l.tree.nodeMainToken(node);
    const f = l.fns[enclosingFn(l, main_token) orelse return];
    var buf: [2]Node.Index = undefined;
    const params = l.tree.builtinCallParams(&buf, node) orelse return;
    if (params.len != 1) return;
    const arg = unparen(l, params[0]);
    if (l.tag(arg) == .identifier and comparedIn(l, f.body_first, main_token, l.text(l.tree.nodeMainToken(arg)))) return;
    try l.add(.float_to_int, main_token, "");
}

/// True when `at` is in `fn main`, in a build script's `fn build(b: *std.Build)`
/// (the build program's entry point), in a test block, or in no function at all.
fn inMainOrTest(l: *const Linter, at: TokenIndex) bool {
    const fn_index = enclosingFn(l, at) orelse return true;
    const f = l.fns[fn_index];
    if (std.mem.eql(u8, f.name, "main")) return true;
    if (!std.mem.eql(u8, f.name, "build")) return false;
    var t = f.name_token;
    while (t + 2 < f.body_first) : (t += 1) {
        if (std.mem.eql(u8, l.text(t), "std") and l.tokTag(t + 1) == .period and std.mem.eql(u8, l.text(t + 2), "Build")) return true;
    }
    return false;
}

/// Reports `return &local` and `return local[a..b]` for a local declared in this function.
fn lintEscape(l: *Linter, value: Node.Index) Allocator.Error!void {
    const tree = l.tree;
    const object = switch (l.tag(value)) {
        .address_of => unparen(l, tree.nodeData(value).node),
        .slice_open, .slice, .slice_sentinel => unparen(l, (tree.fullSlice(value) orelse return).ast.sliced),
        // misra-lint: allow enum_else only these node kinds take an address
        else => return,
    };
    if (l.tag(object) != .identifier) return;
    const name = l.text(tree.nodeMainToken(object));
    const f = l.fns[enclosingFn(l, tree.nodeMainToken(value)) orelse return];
    if (!declaredLocalValue(l, f, name)) return;
    try l.add(.stack_escape, tree.nodeMainToken(value), name);
}

/// True when `name` is a `const` or `var` in the body of `f` that holds a
/// value of its own: an array or a scalar, not a slice or pointer into
/// something else.
fn declaredLocalValue(l: *const Linter, f: Fn, name: []const u8) bool {
    var t = f.body_first;
    while (t + 2 <= f.body_last) : (t += 1) {
        const kw = l.tokTag(t);
        if (kw != .keyword_const and kw != .keyword_var) continue;
        if (!std.mem.eql(u8, l.text(t + 1), name)) continue;
        if (l.tokTag(t + 2) == .colon) {
            const first_type = l.tokTag(t + 3);
            if (first_type == .asterisk or first_type == .question_mark) return false;
            if (first_type == .l_bracket) return l.tokTag(t + 4) != .r_bracket and l.tokTag(t + 4) != .asterisk and l.tokTag(t + 4) != .colon;
            return true;
        }
        // `const local = [4]u8{ ... };` and `@splat` hold their own storage.
        return l.tokTag(t + 3) == .l_bracket or (l.tokTag(t + 3) == .builtin and std.mem.eql(u8, l.text(t + 3), "@splat"));
    }
    return false;
}

/// True when `name` is declared in `f` (parameter or local) with a sentinel type such as `[:0]u8` or `[2:0]u8`.
fn sentinelDeclared(l: *const Linter, f: Fn, name: []const u8) bool {
    var t = l.tree.firstToken(f.decl);
    while (t + 3 <= f.body_last) : (t += 1) {
        if (l.tokTag(t) != .identifier or !std.mem.eql(u8, l.text(t), name)) continue;
        if (l.tokTag(t + 1) != .colon or l.tokTag(t + 2) != .l_bracket) continue;
        const close = matching(l, t + 2, .l_bracket, .r_bracket) orelse return false;
        return tokensHoldTag(l, t + 3, close, .colon);
    }
    return false;
}

/// True when the block holds only `_ = payload;` statements.
fn discardsOnly(l: *const Linter, handler: Node.Index, payload: ?[]const u8) bool {
    const name = payload orelse return false;
    if (!tagIn(l.tag(handler), &.{ .block_two, .block_two_semicolon, .block, .block_semicolon })) return false;
    var buf: [2]Node.Index = undefined;
    const statements = l.tree.blockStatements(&buf, handler) orelse return false;
    if (statements.len == 0) return false;
    for (statements) |statement| {
        if (l.tag(statement) != .assign) return false;
        const sides = l.tree.nodeData(statement).node_and_node;
        if (!isIdent(l, sides[0], "_") or !isIdent(l, sides[1], name)) return false;
    }
    return true;
}

fn lintSwitch(l: *Linter, node: Node.Index) Allocator.Error!void {
    const tree = l.tree;
    const full = tree.fullSwitch(node) orelse return;
    var else_case: ?Node.Index = null;
    var tags: usize = 0;
    for (full.ast.cases) |case_node| {
        const case = tree.fullSwitchCase(case_node) orelse return;
        if (case.ast.values.len == 0) {
            else_case = case_node;
            continue;
        }
        for (case.ast.values) |value| {
            if (l.tag(value) != .enum_literal) return;
            tags += 1;
        }
    }
    const prong = else_case orelse return;
    if (tags == 0) return;
    const target = (tree.fullSwitchCase(prong) orelse return).ast.target_expr;
    // An empty else is reported as empty_else_prong already. An else that returns
    // an error refuses a new tag at run time instead of swallowing it.
    if (isEmptyBlock(l, target) or returnsError(l, target)) return;
    try l.add(.enum_else, tree.firstToken(prong), "");
}

/// True for `error.X` and `return error.X`.
fn returnsError(l: *const Linter, start: Node.Index) bool {
    var node = unparen(l, start);
    if (l.tag(node) == .@"return") node = unparen(l, l.tree.nodeData(node).opt_node.unwrap() orelse return false);
    return l.tag(node) == .error_value;
}

/// Like `uncheckedParam`, but only a comparison with the literal 0 counts as the guard.
fn uncheckedDivisor(l: *const Linter, start: Node.Index, at: TokenIndex) ?[]const u8 {
    const node = unparen(l, start);
    if (l.tag(node) != .identifier) return null;
    const name = l.text(l.tree.nodeMainToken(node));
    const f = l.fns[enclosingFn(l, at) orelse return null];
    if (!isParam(l, f, name)) return null;
    var t = f.body_first + 2;
    while (t + 2 < at) : (t += 1) {
        if (l.tokTag(t) != .identifier or !std.mem.eql(u8, l.text(t), name)) continue;
        if (isCompareOp(l.tokTag(t + 1)) and std.mem.eql(u8, l.text(t + 2), "0")) return null;
        if (isCompareOp(l.tokTag(t - 1)) and std.mem.eql(u8, l.text(t - 2), "0")) return null;
    }
    return name;
}

fn isDivision(name: []const u8) bool {
    const names = [_][]const u8{ "@divTrunc", "@divFloor", "@divExact", "@rem", "@mod" };
    for (names) |item| {
        if (std.mem.eql(u8, name, item)) return true;
    }
    return false;
}

/// The name of a parameter of the enclosing function that `node` is, when no
/// comparison in that function before `at` mentions it.
fn uncheckedParam(l: *const Linter, start: Node.Index, at: TokenIndex) ?[]const u8 {
    const node = unparen(l, start);
    if (l.tag(node) != .identifier) return null;
    const name = l.text(l.tree.nodeMainToken(node));
    const f = l.fns[enclosingFn(l, at) orelse return null];
    if (!isParam(l, f, name)) return null;
    if (comparedIn(l, f.body_first, at, name)) return null;
    return name;
}

fn holdsParam(l: *const Linter, f: Fn, first: TokenIndex, last: TokenIndex) bool {
    var t = first;
    while (t <= last) : (t += 1) {
        if (l.tokTag(t) == .identifier and isParam(l, f, l.text(t))) return true;
    }
    return false;
}

fn isParam(l: *const Linter, f: Fn, name: []const u8) bool {
    var buf: [1]Node.Index = undefined;
    const proto = l.tree.fullFnProto(&buf, f.decl) orelse return false;
    var it = proto.iterate(l.tree);
    while (it.next()) |param| {
        const t = param.name_token orelse continue;
        if (std.mem.eql(u8, l.text(t), name)) return true;
    }
    return false;
}

/// True when `name` sits next to a comparison operator between `first` and `last`.
fn comparedIn(l: *const Linter, first: TokenIndex, last: TokenIndex, name: []const u8) bool {
    var t = first + 1;
    while (t + 1 < last) : (t += 1) {
        if (l.tokTag(t) != .identifier or !std.mem.eql(u8, l.text(t), name)) continue;
        if (isCompareOp(l.tokTag(t - 1)) or isCompareOp(l.tokTag(t + 1))) return true;
        // `n > dest.len` and `dest.len < n` both hold the name next to the operator.
    }
    return false;
}

fn lintVarDecl(l: *Linter, node: Node.Index) Allocator.Error!void {
    const tree = l.tree;
    const decl = tree.fullVarDecl(node) orelse return;
    const init = decl.ast.init_node.unwrap() orelse return;
    const name_token = decl.ast.mut_token + 1;
    if (decl.ast.type_node.unwrap()) |type_node| {
        const declared = typeOfNode(l, type_node) orelse return;
        const narrow = arithType(l, unparen(l, init)) orelse return;
        if (wider(declared, narrow)) try l.add(.narrow_sum_widened, tree.nodeMainToken(unparen(l, init)), l.text(name_token));
        return;
    }
    if (enclosingFn(l, decl.ast.mut_token) != null) return;
    var value = init;
    if (l.tag(value) == .negation) value = tree.nodeData(value).node;
    if (tagIn(l.tag(value), &.{ .number_literal, .char_literal })) {
        try l.add(.untyped_literal_const, name_token, l.text(name_token));
    }
}

fn lintContainer(l: *Linter, node: Node.Index) Allocator.Error!void {
    const tree = l.tree;
    var buf: [2]Node.Index = undefined;
    const container = tree.fullContainerDecl(&buf, node) orelse return;
    const bare = container.layout_token == null and container.ast.enum_token == null and container.ast.arg == .none;
    if (bare and l.tokTag(container.ast.main_token) == .keyword_union) try l.add(.bare_union, container.ast.main_token, "");
    const layout = container.layout_token orelse return;
    if (l.tokTag(layout) != .keyword_extern) return;
    for (container.ast.members) |member| {
        const field = tree.fullContainerField(member) orelse continue;
        const type_expr = field.ast.type_expr.unwrap() orelse continue;
        if (isIdent(l, type_expr, "usize") or isIdent(l, type_expr, "isize")) {
            try l.add(.extern_usize_field, field.ast.main_token, l.text(field.ast.main_token));
        }
    }
}

fn lintCall(l: *Linter, node: Node.Index) Allocator.Error!void {
    const tree = l.tree;
    var buf: [1]Node.Index = undefined;
    const call = tree.fullCall(&buf, node) orelse return;
    const callee = call.ast.fn_expr;
    const ends = isChain(l, callee, &.{ "std", "debug", "panic" }) or isChain(l, callee, &.{ "std", "process", "exit" });
    if (ends and !inMainOrTest(l, tree.nodeMainToken(node))) try l.add(.terminate_outside_main, tree.firstToken(callee), "");
    if (fieldName(l, callee)) |method| {
        if (std.mem.endsWith(u8, method, "AssumeCapacity")) try lintAssumeCapacity(l, callee);
        if (isAtomicMethod(method)) try lintOrders(l, call.ast.params);
        try recordLock(l, callee, method, call.ast.params.len);
        if (std.mem.eql(u8, method, "detach") and call.ast.params.len == 0) try l.add(.thread_detached, tree.firstToken(callee), "");
        for (std_lists.posix_assumes_errno) |name| {
            if (isChain(l, callee, &.{ "std", "posix", name })) try l.add(.posix_assumes_errno, tree.firstToken(callee), name);
        }
    }
    if (isChain(l, callee, &.{ "std", "Thread", "spawn" })) {
        const at = tree.nodeMainToken(node);
        if (insideWhile(l, at)) {
            try l.add(.thread_in_loop, tree.firstToken(callee), "");
        } else if (!inMainOrTest(l, at)) {
            try l.add(.thread_outside_main, tree.firstToken(callee), "");
        }
    }
    if (isChain(l, callee, &.{ "std", "Io", "Threaded", "init" }) and !inMainOrTest(l, tree.nodeMainToken(node))) {
        try l.add(.io_outside_main, tree.firstToken(callee), "");
    }
    if (isChain(l, callee, &.{ "std", "debug", "assert" }) and call.ast.params.len == 1) {
        if (enclosingFn(l, tree.nodeMainToken(node))) |fn_index| {
            const f = l.fns[fn_index];
            const arg = call.ast.params[0];
            if (f.is_export and holdsParam(l, f, tree.firstToken(arg), tree.lastToken(arg))) {
                try l.add(.assert_on_input, tree.firstToken(callee), f.name);
            }
        }
    }
    if (isChain(l, callee, &.{ "std", "mem", "span" }) and call.ast.params.len == 1) {
        const arg = call.ast.params[0];
        if (tokensHoldBuiltin(l, tree.firstToken(arg), tree.lastToken(arg), "@ptrCast")) {
            try l.add(.ptrcast_span, tree.firstToken(callee), "");
        }
    }
    const field = fieldName(l, callee) orelse return;
    if (std.mem.eql(u8, field, "free") and call.ast.params.len > 0) {
        const arg = unparen(l, call.ast.params[call.ast.params.len - 1]);
        if (tagIn(l.tag(arg), &.{ .address_of, .slice_open, .slice, .slice_sentinel })) {
            try l.add(.free_not_owned, tree.firstToken(arg), "");
        }
    }
    if (isPosixCall(l, callee)) {
        for (call.ast.params) |param| {
            const name = fieldName(l, unparen(l, param)) orelse continue;
            if (std.mem.eql(u8, name, "handle")) try l.add(.raw_handle, tree.firstToken(param), "");
        }
    }
    const opens = std.mem.eql(u8, field, "openFile") or std.mem.eql(u8, field, "createFile");
    if (opens and call.ast.params.len >= 2) {
        const fn_index = enclosingFn(l, tree.nodeMainToken(node)) orelse return;
        try l.opens.append(l.arena, .{ .fn_index = fn_index, .path = call.ast.params[1] });
    }
}

/// Reports `list.xAssumeCapacity(...)` with no reserve on `list` earlier in the function:
/// `list.ensure...Capacity(` or a declaration of `list` that calls `initCapacity`.
fn lintAssumeCapacity(l: *Linter, callee: Node.Index) Allocator.Error!void {
    const receiver = chainRoot(l, callee) orelse return;
    const at = l.tree.firstToken(callee);
    const f = l.fns[enclosingFn(l, at) orelse return];
    var t = f.body_first;
    var declared_at: ?TokenIndex = null;
    while (t < at) : (t += 1) {
        if (l.tokTag(t) != .identifier) continue;
        const word = l.text(t);
        if (std.mem.startsWith(u8, word, "ensure") and std.mem.endsWith(u8, word, "Capacity")) {
            if (t >= 2 and l.tokTag(t - 1) == .period and std.mem.eql(u8, l.text(t - 2), receiver)) return;
        }
        if (std.mem.eql(u8, word, receiver) and t >= 1 and tokenIn(l.tokTag(t - 1), &.{ .keyword_const, .keyword_var })) declared_at = t;
        if (std.mem.eql(u8, word, "initCapacity") and declared_at != null) return;
    }
    try l.add(.assume_capacity, at, receiver);
}

fn lintOpens(l: *Linter) Allocator.Error!void {
    for (l.opens.items, 0..) |open, i| {
        for (l.opens.items[i + 1 ..]) |later| {
            if (later.fn_index != open.fn_index or !sameTokens(l, open.path, later.path)) continue;
            try l.add(.same_path_twice, l.tree.firstToken(later.path), l.tree.getNodeSource(later.path));
            break;
        }
    }
}

/// Records `x.lock()`, `x.lockUncancelable(io)`, and `x.unlock(...)`. A `lock` with two
/// arguments is a file lock, which the same process may take again.
fn recordLock(l: *Linter, callee: Node.Index, method: []const u8, arg_count: usize) Allocator.Error!void {
    const is_lock = std.mem.eql(u8, method, "lock") or std.mem.eql(u8, method, "lockUncancelable");
    const is_unlock = std.mem.eql(u8, method, "unlock");
    if (!(is_lock and arg_count <= 1) and !is_unlock) return;
    const at = l.tree.firstToken(callee);
    const fn_index = enclosingFn(l, at) orelse return;
    var frees_at: ?TokenIndex = null;
    if (is_unlock) {
        const before = l.tokTag(at - 1);
        if (before == .keyword_defer) {
            frees_at = blockEnd(l, at);
        } else if (before != .keyword_errdefer) {
            frees_at = at;
        }
    }
    try l.locks.append(l.arena, .{
        .fn_index = fn_index,
        .receiver = l.tree.nodeData(callee).node_and_token[0],
        .at = at,
        .is_lock = !is_unlock,
        .frees_at = frees_at,
    });
}

/// Reports a lock on a receiver this function already holds: an earlier lock with no
/// unlock that takes effect before this one.
fn lintLocks(l: *Linter) Allocator.Error!void {
    for (l.locks.items, 0..) |second, i| {
        if (!second.is_lock) continue;
        for (l.locks.items[0..i]) |first| {
            if (!first.is_lock or first.fn_index != second.fn_index) continue;
            if (!sameTokens(l, first.receiver, second.receiver)) continue;
            if (freedBetween(l, first, second)) continue;
            try l.add(.lock_twice, second.at, l.tree.getNodeSource(second.receiver));
            break;
        }
    }
}

fn freedBetween(l: *const Linter, first: LockCall, second: LockCall) bool {
    for (l.locks.items) |unlock| {
        const frees_at = unlock.frees_at orelse continue;
        if (unlock.fn_index != first.fn_index or !sameTokens(l, unlock.receiver, first.receiver)) continue;
        if (unlock.at > first.at and frees_at < second.at) return true;
    }
    return false;
}

/// The `}` that closes the innermost block holding `tok`.
fn blockEnd(l: *const Linter, tok: TokenIndex) ?TokenIndex {
    var depth: usize = 0;
    var t = tok;
    while (t > 0) {
        t -= 1;
        switch (l.tokTag(t)) {
            .r_brace => depth += 1,
            .l_brace => {
                if (depth == 0) return matching(l, t, .l_brace, .r_brace);
                depth -= 1;
            },
            // misra-lint: allow empty_else_prong only braces change the depth
            else => {},
        }
    }
    return null;
}

const atomic_methods = [_][]const u8{
    "load",
    "store",
    "swap",
    "fetchAdd",
    "fetchSub",
    "fetchAnd",
    "fetchNand",
    "fetchOr",
    "fetchXor",
    "fetchMax",
    "fetchMin",
    "bitSet",
    "bitReset",
    "bitToggle",
    "cmpxchgWeak",
    "cmpxchgStrong",
    "rmw",
};

const atomic_builtins = [_][]const u8{ "@atomicLoad", "@atomicStore", "@atomicRmw", "@cmpxchgWeak", "@cmpxchgStrong" };

const weak_orders = [_][]const u8{ "unordered", "monotonic", "acquire", "release", "acq_rel" };

fn isAtomicMethod(name: []const u8) bool {
    for (atomic_methods) |item| {
        if (std.mem.eql(u8, name, item)) return true;
    }
    return false;
}

fn isAtomicBuiltin(name: []const u8) bool {
    for (atomic_builtins) |item| {
        if (std.mem.eql(u8, name, item)) return true;
    }
    return false;
}

fn lintOrders(l: *Linter, params: []const Node.Index) Allocator.Error!void {
    for (params) |param| {
        const arg = unparen(l, param);
        if (l.tag(arg) != .enum_literal) continue;
        const order = l.text(l.tree.nodeMainToken(arg));
        for (weak_orders) |weak| {
            if (std.mem.eql(u8, order, weak)) try l.add(.atomic_order, l.tree.nodeMainToken(arg), order);
        }
    }
}

/// The object a slice expression slices, or the expression itself.
fn sliceBase(l: *const Linter, start: Node.Index) Node.Index {
    const node = unparen(l, start);
    const slice = l.tree.fullSlice(node) orelse return node;
    return unparen(l, slice.ast.sliced);
}

/// True when `name` is declared in `f` (parameter or local) with a many-item or C
/// pointer type: `[*]T`, `[*:0]T`, `[*c]T`.
fn declaredManyPtr(l: *const Linter, f: Fn, name: []const u8) bool {
    var t = l.tree.firstToken(f.decl);
    while (t + 3 <= f.body_last) : (t += 1) {
        if (l.tokTag(t) != .identifier or !std.mem.eql(u8, l.text(t), name) or l.tokTag(t + 1) != .colon) continue;
        if (l.tokTag(t + 2) == .l_bracket and l.tokTag(t + 3) == .asterisk) return true;
    }
    return false;
}

fn isPosixCall(l: *const Linter, callee: Node.Index) bool {
    var node = callee;
    var second: ?[]const u8 = null;
    while (l.tag(node) == .field_access) {
        const data = l.tree.nodeData(node).node_and_token;
        second = l.text(data[1]);
        node = data[0];
    }
    const s = second orelse return false;
    return isIdent(l, node, "std") and std.mem.eql(u8, s, "posix");
}

fn tokensHoldBuiltin(l: *const Linter, first: TokenIndex, last: TokenIndex, name: []const u8) bool {
    var t = first;
    while (t <= last) : (t += 1) {
        if (l.tokTag(t) == .builtin and std.mem.eql(u8, l.text(t), name)) return true;
    }
    return false;
}

fn lintFn(l: *Linter, f: Fn) Allocator.Error!void {
    const tree = l.tree;
    var buf: [1]Node.Index = undefined;
    const proto = tree.fullFnProto(&buf, f.decl) orelse return;
    if (f.return_type.unwrap()) |ret| {
        if (tokensHoldIdent(l, tree.firstToken(ret), tree.lastToken(ret), "anyerror")) {
            try l.add(.anyerror_return, tree.firstToken(ret), f.name);
        }
    }
    var it = proto.iterate(tree);
    while (it.next()) |param| {
        const name_token = param.name_token orelse continue;
        const name = l.text(name_token);
        if (param.comptime_noalias) |t| {
            if (l.tokTag(t) == .keyword_noalias) try l.add(.noalias_param, t, name);
        }
        if (param.anytype_ellipsis3) |t| {
            if (l.tokTag(t) == .keyword_anytype and !usedBeyondDiscard(l, f, name)) {
                try l.add(.anytype_unused, name_token, name);
            }
            continue;
        }
        const type_expr = param.type_expr orelse continue;
        const ptr = tree.fullPtrType(type_expr) orelse continue;
        if (ptr.const_token != null) continue;
        if (ptr.size != .slice and ptr.size != .one) continue;
        if (onlyRead(l, f, name)) try l.add(.mutable_param_read_only, name_token, name);
    }
    if (f.is_pub and !f.is_export) try lintPubWrapper(l, f);
    try lintErrnoReads(l, f);
}

fn usedBeyondDiscard(l: *const Linter, f: Fn, name: []const u8) bool {
    var t = f.body_first;
    while (t <= f.body_last) : (t += 1) {
        if (l.tokTag(t) != .identifier or !std.mem.eql(u8, l.text(t), name)) continue;
        const discard = l.tokTag(t - 1) == .equal and std.mem.eql(u8, l.text(t - 2), "_");
        if (!discard) return true;
    }
    return false;
}

/// True when every use of `name` in the body is a read: `for (name)`, `name.len`,
/// `name.*`, or `name[i]` as a value. Any other use counts as a possible write.
fn onlyRead(l: *const Linter, f: Fn, name: []const u8) bool {
    var reads: usize = 0;
    var t = f.body_first;
    while (t <= f.body_last) : (t += 1) {
        if (l.tokTag(t) != .identifier or !std.mem.eql(u8, l.text(t), name)) continue;
        if (l.tokTag(t - 1) == .equal and std.mem.eql(u8, l.text(t - 2), "_")) continue;
        if (l.tokTag(t - 1) == .ampersand) return false;
        const next = l.tokTag(t + 1);
        if (l.tokTag(t - 1) == .l_paren and l.tokTag(t - 2) == .keyword_for) {
            const close = matching(l, t - 1, .l_paren, .r_paren) orelse return false;
            if (l.tokTag(close + 1) == .pipe and l.tokTag(close + 2) == .asterisk) return false;
            reads += 1;
        } else if (next == .period and std.mem.eql(u8, l.text(t + 2), "len")) {
            reads += 1;
        } else if (next == .period_asterisk) {
            if (isAssignOp(l.tokTag(t + 2)) or l.tokTag(t + 2) == .period) return false;
            reads += 1;
        } else if (next == .l_bracket) {
            const close = matching(l, t + 1, .l_bracket, .r_bracket) orelse return false;
            if (tokensHoldTag(l, t + 1, close, .ellipsis2)) return false;
            const after = l.tokTag(close + 1);
            if (isAssignOp(after) or after == .period or after == .l_bracket or after == .period_asterisk) return false;
            reads += 1;
        } else return false;
    }
    return reads > 0;
}

fn matching(l: *const Linter, open: TokenIndex, open_tag: std.zig.Token.Tag, close_tag: std.zig.Token.Tag) ?TokenIndex {
    var depth: usize = 0;
    var t = open;
    const end = l.token_count;
    while (t < end) : (t += 1) {
        const tag = l.tokTag(t);
        if (tag == open_tag) depth += 1;
        if (tag == close_tag) {
            depth -= 1;
            if (depth == 0) return t;
        }
    }
    return null;
}

fn lintPubWrapper(l: *Linter, f: Fn) Allocator.Error!void {
    const tree = l.tree;
    const body = tree.nodeData(f.decl).node_and_node[1];
    var buf: [2]Node.Index = undefined;
    const statements = tree.blockStatements(&buf, body) orelse return;
    if (statements.len != 1 or l.tag(statements[0]) != .@"return") return;
    const value = tree.nodeData(statements[0]).opt_node.unwrap() orelse return;
    var call_buf: [1]Node.Index = undefined;
    const call = tree.fullCall(&call_buf, unparen(l, value)) orelse return;
    if (l.tag(call.ast.fn_expr) != .identifier) return;
    const target = fnIndexByName(l, l.text(tree.nodeMainToken(call.ast.fn_expr))) orelse return;
    if (l.fns[target].is_pub or l.fns[target].is_export) return;
    try l.add(.pub_wrapper, f.name_token, f.name);
}

const acquire = [_][]const u8{
    "alloc",
    "alignedAlloc",
    "allocSentinel",
    "create",
    "dupe",
    "dupeZ",
    "openFile",
    "createFile",
    "openDir",
};

fn lintStatements(l: *Linter, statements: []const Node.Index) Allocator.Error!void {
    const tree = l.tree;
    for (statements, 0..) |statement, i| {
        const rest = statements[i + 1 ..];
        const first = tree.firstToken(statement);
        if (tree.fullVarDecl(statement)) |decl| {
            const name_token = decl.ast.mut_token + 1;
            if (decl.ast.init_node.unwrap()) |init| {
                if (isAcquire(l, init)) try lintRelease(l, name_token, rest);
                if (opensReadOnly(l, init)) try lintReadOnlyWrites(l, name_token, rest);
                if (decl.ast.type_node.unwrap()) |type_node| {
                    if (typeOfNode(l, type_node) != null) try lintFloatToInt(l, init, true);
                    if (isChain(l, type_node, &.{ "std", "Io", "Threaded" }) and !inMainOrTest(l, decl.ast.mut_token)) {
                        try l.add(.io_outside_main, decl.ast.mut_token, l.text(name_token));
                    }
                }
                if (isIdent(l, init, "undefined") and l.tokTag(decl.ast.mut_token) == .keyword_var) {
                    try lintFirstWrite(l, name_token, rest);
                }
            }
        }
        if (closedHandle(l, statement)) |handle| {
            for (rest) |later| {
                if (nodeHoldsIdent(l, later, handle)) {
                    try l.add(.use_after_close, tree.firstToken(later), handle);
                    break;
                }
            }
        }
        if (isErrnoClear(l, first, tree.lastToken(statement)) and i > 0) {
            const before = statements[i - 1];
            if (callsLibc(l, tree.firstToken(before), tree.lastToken(before))) {
                try l.add(.errno_clear_after_call, first, "");
            }
        }
    }
}

/// True for `try dir.openFile(...)` whose options do not ask for writing.
/// True when any name in the call's receiver chain (`l.arena.alloc`, `arena.alloc`) contains "arena".
fn namesArena(l: *const Linter, callee: Node.Index) bool {
    var t = l.tree.firstToken(callee);
    const last = l.tree.lastToken(callee);
    while (t < last) : (t += 1) {
        if (l.tokTag(t) == .identifier and std.mem.find(u8, l.text(t), "arena") != null) return true;
    }
    return false;
}

fn opensReadOnly(l: *const Linter, init: Node.Index) bool {
    if (l.tag(init) != .@"try") return false;
    var buf: [1]Node.Index = undefined;
    const call = l.tree.fullCall(&buf, l.tree.nodeData(init).node) orelse return false;
    const field = fieldName(l, call.ast.fn_expr) orelse return false;
    if (!std.mem.eql(u8, field, "openFile")) return false;
    const first = l.tree.firstToken(init);
    const last = l.tree.lastToken(init);
    var t = first;
    while (t <= last) : (t += 1) {
        const word = l.text(t);
        if (std.mem.eql(u8, word, "read_write") or std.mem.eql(u8, word, "write_only")) return false;
    }
    return true;
}

fn lintReadOnlyWrites(l: *Linter, name_token: TokenIndex, rest: []const Node.Index) Allocator.Error!void {
    const name = l.text(name_token);
    for (rest) |later| {
        const last = l.tree.lastToken(later);
        var t = l.tree.firstToken(later);
        while (t + 3 <= last) : (t += 1) {
            if (!std.mem.eql(u8, l.text(t), name) or l.tokTag(t + 1) != .period) continue;
            if (!std.mem.startsWith(u8, l.text(t + 2), "write") or l.tokTag(t + 3) != .l_paren) continue;
            try l.add(.write_read_only, t, name);
            return;
        }
    }
}

fn isAcquire(l: *const Linter, init: Node.Index) bool {
    if (l.tag(init) != .@"try") return false;
    var buf: [1]Node.Index = undefined;
    const call = l.tree.fullCall(&buf, l.tree.nodeData(init).node) orelse return false;
    const field = fieldName(l, call.ast.fn_expr) orelse return false;
    // An arena frees every allocation at once, so its allocations need no release of their own.
    if (namesArena(l, call.ast.fn_expr)) return false;
    for (acquire) |name| {
        if (std.mem.eql(u8, field, name)) return true;
    }
    return false;
}

fn lintRelease(l: *Linter, name_token: TokenIndex, rest: []const Node.Index) Allocator.Error!void {
    const tree = l.tree;
    const name = l.text(name_token);
    for (rest) |later| {
        const first = tree.firstToken(later);
        const last = tree.lastToken(later);
        const releases = tagIn(l.tag(later), &.{ .@"defer", .@"errdefer" });
        if (releases and tokensHoldIdent(l, first, last, name)) return;
        if (tokensHoldTag(l, first, last, .keyword_try)) {
            try l.add(.try_before_release, name_token, name);
            return;
        }
        if (tokensHoldTag(l, first, last, .keyword_return)) {
            if (!tokensHoldIdent(l, first, last, name)) try l.add(.try_before_release, name_token, name);
            return;
        }
    }
}

fn lintFirstWrite(l: *Linter, name_token: TokenIndex, rest: []const Node.Index) Allocator.Error!void {
    const tree = l.tree;
    const name = l.text(name_token);
    for (rest) |later| {
        if (!nodeHoldsIdent(l, later, name)) continue;
        // `f(&name)` hands the storage to a callee that writes it.
        if (addressTaken(l, tree.firstToken(later), tree.lastToken(later), name)) return;
        if (tagIn(l.tag(later), &branch_tags)) try l.add(.undefined_then_branch, name_token, name);
        if (l.tag(later) == .assign) {
            const target = tree.nodeData(later).node_and_node[0];
            if (l.tag(target) == .field_access and isIdent(l, tree.nodeData(target).node_and_token[0], name)) {
                try l.add(.field_by_field_init, name_token, name);
            }
        }
        return;
    }
}

/// The receiver of a `handle.close(...)` statement, or null.
fn closedHandle(l: *const Linter, statement: Node.Index) ?[]const u8 {
    var buf: [1]Node.Index = undefined;
    const call = l.tree.fullCall(&buf, statement) orelse return null;
    const field = fieldName(l, call.ast.fn_expr) orelse return null;
    if (!std.mem.eql(u8, field, "close")) return null;
    const receiver = l.tree.nodeData(call.ast.fn_expr).node_and_token[0];
    if (l.tag(receiver) != .identifier) return null;
    return l.text(l.tree.nodeMainToken(receiver));
}

/// Matches the token run `std . c . _errno ( ) .*` starting at `t`.
fn isErrnoAt(l: *const Linter, t: TokenIndex) bool {
    const words = [_][]const u8{ "std", ".", "c", ".", "_errno", "(", ")", ".*" };
    if (t + words.len > l.token_count) return false;
    var at = t;
    for (words) |word| {
        if (!std.mem.eql(u8, l.text(at), word)) return false;
        at += 1;
    }
    return true;
}

fn isErrnoClear(l: *const Linter, first: TokenIndex, last: TokenIndex) bool {
    if (!isErrnoAt(l, first)) return false;
    return first + 10 == last + 1 and l.tokTag(first + 8) == .equal and std.mem.eql(u8, l.text(first + 9), "0");
}

/// True when the tokens hold a call `std.c.name(` other than `_errno`.
fn callsLibc(l: *const Linter, first: TokenIndex, last: TokenIndex) bool {
    var t = first;
    while (t + 5 <= last) : (t += 1) {
        if (!std.mem.eql(u8, l.text(t), "std") or l.tokTag(t + 1) != .period) continue;
        if (!std.mem.eql(u8, l.text(t + 2), "c") or l.tokTag(t + 3) != .period) continue;
        if (l.tokTag(t + 5) != .l_paren) continue;
        if (!std.mem.eql(u8, l.text(t + 4), "_errno")) return true;
    }
    return false;
}

/// Checks every `std.c._errno().*` read in `f` against the nearest `-1` test before it.
fn lintErrnoReads(l: *Linter, f: Fn) Allocator.Error!void {
    var t = f.body_first;
    while (t <= f.body_last) : (t += 1) {
        if (!isErrnoAt(l, t)) continue;
        if (isAssignOp(l.tokTag(t + 8))) continue;
        const failure = lastFailureTest(l, f.body_first, t) orelse {
            // A call such as strtoul reports failure only through errno, which this function cleared first.
            if (clearsErrno(l, f.body_first, t)) continue;
            try l.add(.errno_without_failure, t, "");
            continue;
        };
        var c = failure;
        while (c < t) : (c += 1) {
            if (l.tokTag(c) == .identifier and l.tokTag(c + 1) == .l_paren and !std.mem.eql(u8, l.text(c), "_errno")) {
                try l.add(.errno_after_call, c, l.text(c));
                break;
            }
        }
    }
}

/// The token after the last `== -1`, `!= -1`, `== null`, or `!= null` in `first..before`.
fn lastFailureTest(l: *const Linter, first: TokenIndex, before: TokenIndex) ?TokenIndex {
    var found: ?TokenIndex = null;
    var t = first;
    while (t + 2 < before) : (t += 1) {
        const op = l.tokTag(t);
        if (op != .equal_equal and op != .bang_equal) continue;
        if (l.tokTag(t + 1) == .minus and std.mem.eql(u8, l.text(t + 2), "1")) found = t + 3;
        if (std.mem.eql(u8, l.text(t + 1), "null")) found = t + 2;
    }
    return found;
}

fn clearsErrno(l: *const Linter, first: TokenIndex, before: TokenIndex) bool {
    var t = first;
    while (t + 10 <= before) : (t += 1) {
        if (isErrnoAt(l, t) and l.tokTag(t + 8) == .equal and std.mem.eql(u8, l.text(t + 9), "0")) return true;
    }
    return false;
}

fn lintRecursion(l: *Linter) Allocator.Error!void {
    const tree = l.tree;
    var edges: std.ArrayList(Edge) = .empty;
    const count = std.math.cast(u32, tree.nodes.len) orelse return error.OutOfMemory;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const node: Node.Index = @fromBackingInt(@intCast(index));
        var buf: [1]Node.Index = undefined;
        const call = tree.fullCall(&buf, node) orelse continue;
        if (l.tag(call.ast.fn_expr) != .identifier) continue;
        const to = fnIndexByName(l, l.text(tree.nodeMainToken(call.ast.fn_expr))) orelse continue;
        const from = enclosingFn(l, tree.nodeMainToken(node)) orelse continue;
        try edges.append(l.arena, .{ .from = from, .to = to });
    }
    const seen = try l.arena.alloc(bool, l.fns.len);
    var stack: std.ArrayList(usize) = try .initCapacity(l.arena, l.fns.len);
    for (l.fns, 0..) |f, start| {
        if (returnsType(l, f) or comptimeOnly(l, f)) continue;
        if (reaches(edges.items, seen, &stack, start)) try l.add(.recursion, f.name_token, f.name);
    }
}

/// True when every parameter of `f` is `comptime`, so a call runs at compile time,
/// the way a helper that sizes a type does.
fn comptimeOnly(l: *const Linter, f: Fn) bool {
    var buf: [1]Node.Index = undefined;
    const proto = l.tree.fullFnProto(&buf, f.decl) orelse return false;
    var it = proto.iterate(l.tree);
    var count: usize = 0;
    while (it.next()) |param| {
        const marker = param.comptime_noalias orelse return false;
        if (l.tokTag(marker) != .keyword_comptime) return false;
        count += 1;
    }
    return count > 0;
}

fn returnsType(l: *const Linter, f: Fn) bool {
    const ret = f.return_type.unwrap() orelse return false;
    return isIdent(l, ret, "type");
}

/// True when a path of one or more edges leads from `start` back to `start`.
// ponytail: one walk per function, O(fns * edges). Tarjan's SCC is the upgrade for files with thousands of calls.
/// `seen` and `stack` are scratch space with room for every function; each walk resets them.
fn reaches(edges: []const Edge, seen: []bool, stack: *std.ArrayList(usize), start: usize) bool {
    @memset(seen, false);
    stack.clearRetainingCapacity();
    // misra-lint: allow assume_capacity lintRecursion reserves room for every function before the first walk
    stack.appendAssumeCapacity(start);
    while (stack.pop()) |at| {
        for (edges) |edge| {
            if (edge.from != at) continue;
            if (edge.to == start) return true;
            if (seen[edge.to]) continue;
            seen[edge.to] = true;
            // Each function enters the stack at most once, so the capacity is never exceeded.
            // misra-lint: allow assume_capacity lintRecursion reserves room for every function before the first walk
            stack.appendAssumeCapacity(edge.to);
        }
    }
    return false;
}

fn ruleLabel(id: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    const kind, const rest = if (std.mem.startsWith(u8, id, "dir-"))
        .{ "Dir", id[4..] }
    else
        .{ "Rule", id[5..] };
    const dash = std.mem.findScalar(u8, rest, '-') orelse rest.len;
    const minor = if (dash < rest.len) rest[dash + 1 ..] else "";
    try w.print("{s} {s}.{s}", .{ kind, rest[0..dash], minor });
}

fn writeText(w: *std.Io.Writer, path: []const u8, findings: []const Finding) std.Io.Writer.Error!void {
    for (findings) |finding| {
        const about = info(finding.check);
        try w.print("{s}:{d}:{d}: {t}[{t}]", .{ path, finding.line, finding.column, about.severity, finding.check });
        for (about.rules, 0..) |rule, i| {
            try w.writeAll(if (i == 0) " " else ", ");
            try ruleLabel(rule, w);
        }
        try w.print(": {s}", .{about.summary});
        if (finding.subject.len > 0) try w.print(" ({s})", .{finding.subject});
        try w.writeByte('\n');
    }
}

const FindingJson = struct {
    check: Check,
    severity: Severity,
    rules: []const []const u8,
    line: usize,
    column: usize,
    message: []const u8,
    subject: []const u8,
};

const FileJson = struct {
    path: []const u8,
    findings: []const FindingJson,
};

const CheckJson = struct {
    id: Check,
    severity: Severity,
    rules: []const []const u8,
    summary: []const u8,
};

fn toJson(arena: Allocator, findings: []const Finding) Allocator.Error![]const FindingJson {
    const out = try arena.alloc(FindingJson, findings.len);
    for (findings, out) |finding, *item| {
        const about = info(finding.check);
        item.* = .{
            .check = finding.check,
            .severity = about.severity,
            .rules = about.rules,
            .line = finding.line,
            .column = finding.column,
            .message = about.summary,
            .subject = finding.subject,
        };
    }
    return out;
}

/// The `.zig` paths a file names in `@import("...")`, as written.
fn importsOf(arena: Allocator, source: [:0]const u8) Allocator.Error![]const []const u8 {
    const tree = try Ast.parse(arena, source, .{});
    var out: std.ArrayList([]const u8) = .empty;
    const count = std.math.cast(u32, tree.nodes.len) orelse return error.OutOfMemory;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const node: Node.Index = @fromBackingInt(index);
        var buf: [2]Node.Index = undefined;
        const params = tree.builtinCallParams(&buf, node) orelse continue;
        if (!std.mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(node)), "@import") or params.len != 1) continue;
        if (tree.nodeTag(params[0]) != .string_literal) continue;
        const literal = tree.tokenSlice(tree.nodeMainToken(params[0]));
        if (literal.len < 2) continue;
        const name = literal[1 .. literal.len - 1];
        if (std.mem.endsWith(u8, name, ".zig")) try out.append(arena, name);
    }
    return out.items;
}

/// Adds an `unreachable_file` finding to every given file that `root` does not
/// reach through `@import`. Paths are compared after `resolveAlloc`.
// ponytail: a linear scan per import, O(files * imports). A hash map is the upgrade for very large file sets.
fn markUnreached(arena: Allocator, root: []const u8, paths: []const []const u8, sources: []const [:0]u8, results: [][]Finding) Allocator.Error!void {
    const resolved = try arena.alloc([]const u8, paths.len);
    for (paths, resolved) |path, *out| out.* = try std.Io.Dir.path.resolveAlloc(arena, &.{path});
    const reached = try arena.alloc(bool, paths.len);
    @memset(reached, false);
    var stack: std.ArrayList(usize) = try .initCapacity(arena, paths.len);
    const root_resolved = try std.Io.Dir.path.resolveAlloc(arena, &.{root});
    for (resolved, 0..) |path, i| {
        if (!std.mem.eql(u8, path, root_resolved)) continue;
        reached[i] = true;
        stack.appendAssumeCapacity(i);
    }
    while (stack.pop()) |at| {
        const dir = std.Io.Dir.path.dirname(resolved[at]) orelse ".";
        for (try importsOf(arena, sources[at])) |name| {
            const target = try std.Io.Dir.path.resolveAlloc(arena, &.{ dir, name });
            for (resolved, 0..) |path, i| {
                if (reached[i] or !std.mem.eql(u8, path, target)) continue;
                reached[i] = true;
                // Each file enters the stack at most once, so the capacity is never exceeded.
                // misra-lint: allow assume_capacity the stack holds room for every file
                stack.appendAssumeCapacity(i);
            }
        }
    }
    for (reached, results) |hit, *result| {
        if (hit) continue;
        const grown = try arena.alloc(Finding, result.len + 1);
        grown[0] = .{ .check = .unreachable_file, .line = 1, .column = 1, .subject = root };
        @memcpy(grown[1..], result.*);
        result.* = grown;
    }
}

fn readSource(arena: Allocator, io: std.Io, path: []const u8) ![:0]u8 {
    if (std.mem.eql(u8, path, "-")) {
        var reader = std.Io.File.stdin().reader(io, &.{});
        return reader.interface.allocRemainingAlignedSentinel(arena, .limited(max_source_bytes), .of(u8), 0);
    }
    return std.Io.Dir.cwd().readFileAllocOptions(io, path, arena, .limited(max_source_bytes), .of(u8), 0);
}

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    var out_buf: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buf);
    const w = &out.interface;
    var err_buf: [1024]u8 = undefined;
    var err_out = std.Io.File.stderr().writer(io, &err_buf);
    const ew = &err_out.interface;

    var json = false;
    var root_path: ?[]const u8 = null;
    var list_checks = false;
    var paths: std.ArrayList([]const u8) = .empty;
    var args = try init.minimal.args.iterateAllocator(arena);
    defer args.deinit();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (std.mem.eql(u8, arg, "--root")) {
            root_path = args.next() orelse {
                try ew.print("misra-lint: --root needs a file\n{s}", .{usage});
                try ew.flush();
                return 2;
            };
        } else if (std.mem.eql(u8, arg, "--checks")) {
            list_checks = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try w.writeAll(usage);
            try w.flush();
            return 0;
        } else if (arg.len > 1 and arg[0] == '-') {
            try ew.print("misra-lint: unknown option {s}\n{s}", .{ arg, usage });
            try ew.flush();
            return 2;
        } else {
            try paths.append(arena, arg);
        }
    }

    if (list_checks) {
        const all = std.enums.values(Check);
        if (json) {
            const items = try arena.alloc(CheckJson, all.len);
            for (all, items) |check, *item| {
                const about = info(check);
                item.* = .{ .id = check, .severity = about.severity, .rules = about.rules, .summary = about.summary };
            }
            try std.json.Stringify.value(items, .{}, w);
            try w.writeByte('\n');
        } else {
            for (all) |check| {
                const about = info(check);
                try w.print("{t} ({t})", .{ check, about.severity });
                for (about.rules, 0..) |rule, i| {
                    try w.writeAll(if (i == 0) " " else ", ");
                    try ruleLabel(rule, w);
                }
                try w.print(": {s}\n", .{about.summary});
            }
        }
        try w.flush();
        return 0;
    }

    if (paths.items.len == 0) {
        try ew.writeAll(usage);
        try ew.flush();
        return 2;
    }

    const sources = try arena.alloc([:0]u8, paths.items.len);
    const results = try arena.alloc([]Finding, paths.items.len);
    for (paths.items, sources, results) |path, *source, *result| {
        source.* = readSource(arena, io, path) catch |err| {
            try ew.print("misra-lint: {s}: {t}\n", .{ path, err });
            try ew.flush();
            return 2;
        };
        result.* = try lint(arena, source.*);
    }
    if (root_path) |root| try markUnreached(arena, root, paths.items, sources, results);

    var total: usize = 0;
    var files: std.ArrayList(FileJson) = .empty;
    for (paths.items, results) |path, findings| {
        total += findings.len;
        if (json) {
            try files.append(arena, .{ .path = path, .findings = try toJson(arena, findings) });
        } else {
            try writeText(w, path, findings);
        }
    }
    if (json) {
        try std.json.Stringify.value(.{ .files = files.items }, .{}, w);
        try w.writeByte('\n');
    }
    try w.flush();
    return if (total == 0) 0 else 1;
}

fn checksOf(source: [:0]const u8) ![]const Check {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const findings = try lint(arena_state.allocator(), source);
    const out = try std.testing.allocator.alloc(Check, findings.len);
    for (findings, out) |finding, *check| check.* = finding.check;
    return out;
}

fn expectChecks(source: [:0]const u8, want: []const Check) !void {
    const got = try checksOf(source);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualSlices(Check, want, got);
}

test "clean code has no finding" {
    try expectChecks(
        \\const std = @import("std");
        \\pub const block_size: u32 = 512;
        \\fn boundedAdd(a: u32, b: u32) error{Overflow}!u32 {
        \\    return std.math.add(u32, a, b);
        \\}
        \\fn checksum(data: []const u8) u8 {
        \\    var sum: u8 = 0;
        \\    for (data) |b| sum +%= b;
        \\    return sum;
        \\}
        \\fn pack(n: u32, tag: u32) u32 {
        \\    return (n << 4) | (tag & 0xF);
        \\}
        \\
    , &.{});
}

test "parse error stops the checks" {
    try expectChecks("fn f( {\n", &.{.parse_error});
}

test "safety, widths, and allocators" {
    try expectChecks(
        \\fn bump(x: *u8) void {
        \\    @setRuntimeSafety(false);
        \\    x.* += 1;
        \\}
    , &.{.runtime_safety_off});
    try expectChecks("pub const block_size = 512;\nconst neg = -1;\n", &.{ .untyped_literal_const, .untyped_literal_const });
    try expectChecks("const Disk = extern struct {\n    blocks: usize,\n};\n", &.{.extern_usize_field});
    try expectChecks(
        \\const std = @import("std");
        \\fn hidden(n: usize) ![]u8 {
        \\    return std.heap.page_allocator.alloc(u8, n);
        \\}
        \\pub fn main() void {
        \\    _ = std.heap.page_allocator;
        \\}
    , &.{.global_allocator});
}

test "error handling" {
    try expectChecks(
        \\fn a(f: anytype) void {
        \\    f() catch {};
        \\}
        \\fn b() anyerror!void {
        \\    g() catch unreachable;
        \\}
    , &.{ .catch_empty, .anyerror_return, .catch_unreachable });
}

test "parameters" {
    try expectChecks(
        \\fn readAt(a: anytype, b: anytype) void {
        \\    _ = a;
        \\    _ = b;
        \\}
    , &.{ .anytype_unused, .anytype_unused });
    try expectChecks(
        \\fn checksum(data: []u8) u8 {
        \\    var sum: u8 = 0;
        \\    for (data) |b| sum +%= b;
        \\    return sum;
        \\}
        \\fn zero(data: []u8) void {
        \\    for (data) |*b| b.* = 0;
        \\}
        \\fn set(data: []u8) void {
        \\    data[0] = 1;
        \\}
        \\fn len(data: []u8) usize {
        \\    return data.len;
        \\}
    , &.{ .mutable_param_read_only, .mutable_param_read_only });
}

test "pub wrapper" {
    try expectChecks(
        \\fn checksum(data: []const u8) u8 {
        \\    _ = data;
        \\    return 0;
        \\}
        \\pub fn checksumPub(data: []const u8) u8 {
        \\    return checksum(data);
        \\}
    , &.{.pub_wrapper});
}

test "initialization" {
    try expectChecks(
        \\fn value(flag: bool) u32 {
        \\    var x: u32 = undefined;
        \\    if (flag) x = 1;
        \\    return x;
        \\}
        \\fn blank() H {
        \\    var header: H = undefined;
        \\    header.magic = 1;
        \\    return header;
        \\}
        \\fn ok() [4]u8 {
        \\    var buf: [4]u8 = undefined;
        \\    @memset(&buf, 0);
        \\    return buf;
        \\}
    , &.{ .undefined_then_branch, .field_by_field_init });
}

test "arithmetic" {
    try expectChecks("export fn f(a: u32) u16 {\n    return @truncate(a);\n}\n", &.{.truncate_param});
    try expectChecks("export fn f(a: i32, b: u32) u32 {\n    return @as(u32, @bitCast(a)) + b;\n}\n", &.{.bitcast_arith});
    try expectChecks("fn nextOp(op: Op) u8 {\n    return @backingInt(op) + 1;\n}\n", &.{.enum_int_arith});
    try expectChecks("export fn f(a: u16, b: u16) u32 {\n    return a + b;\n}\n", &.{.narrow_sum_widened});
    try expectChecks("export fn f(a: u16, b: u16, c: u32) u32 {\n    return (a + b) * c;\n}\n", &.{.narrow_operand});
    try expectChecks("export fn f(a: u16, b: u16) u32 {\n    return @as(u32, a + b);\n}\n", &.{.widening_cast_of_sum});
    try expectChecks("fn f(a: u16, b: u16) u32 {\n    const s: u32 = a * b;\n    return s;\n}\n", &.{.narrow_sum_widened});
    try expectChecks("fn f(a: u32, b: u32) u32 {\n    return a + b;\n}\n", &.{});
    try expectChecks("fn f(a: u16, b: u16) u32 {\n    return a +% b;\n}\n", &.{});
}

test "precedence" {
    try expectChecks("fn f(n: u32, t: u32) u32 {\n    return n << 4 | t & 0xF;\n}\n", &.{ .mixed_precedence, .mixed_precedence });
    try expectChecks("fn f(a: bool, b: bool, c: bool) bool {\n    return a and b or c;\n}\n", &.{.mixed_precedence});
    try expectChecks("fn f(a: u32, b: u32, c: u32) u32 {\n    return a + b * c;\n}\n", &.{});
}

test "control flow" {
    try expectChecks(
        \\fn connect(dial: *const fn () error{Busy}!void) !void {
        \\    while (true) {
        \\        dial() catch continue;
        \\        return;
        \\    }
        \\}
        \\fn ignore(code: u8) void {
        \\    switch (code) {
        \\        1 => {},
        \\        else => {},
        \\    }
        \\}
    , &.{ .unbounded_loop, .empty_else_prong });
}

test "recursion" {
    try expectChecks(
        \\fn walk(n: u32) void {
        \\    if (n > 0) walk(n - 1);
        \\}
        \\fn ping(n: u32) void {
        \\    if (n > 0) pong(n - 1);
        \\}
        \\fn pong(n: u32) void {
        \\    ping(n);
        \\}
        \\fn List(comptime n: u32) type {
        \\    return if (n == 0) void else List(n - 1);
        \\}
    , &.{ .recursion, .recursion, .recursion });
}

test "buffers" {
    try expectChecks(
        \\const std = @import("std");
        \\fn asText(raw: [*]const u8) []const u8 {
        \\    return std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
        \\}
        \\fn terminate(buf: []u8) void {
        \\    buf[buf.len] = 0;
        \\}
        \\fn copyN(dest: []u8, src: []const u8, n: usize) void {
        \\    @memcpy(dest[0..n], src[0..n]);
        \\}
        \\fn copyChecked(dest: []u8, src: []const u8, n: usize) void {
        \\    if (n > dest.len or n > src.len) return;
        \\    @memcpy(dest[0..n], src[0..n]);
        \\}
        \\fn old(buf: []u8) ![]u8 {
        \\    return std.fmt.bufPrint(buf, "x", .{});
        \\}
    , &.{ .ptrcast_span, .index_at_len, .memcpy_unchecked_len, .deprecated_api });
}

test "resources" {
    try expectChecks(
        \\fn two(allocator: Allocator) !void {
        \\    const first = try allocator.alloc(u8, 8);
        \\    const second = try allocator.alloc(u8, 8);
        \\    allocator.free(second);
        \\    allocator.free(first);
        \\}
        \\fn take(allocator: Allocator, n: usize) ![]u8 {
        \\    const buf = try allocator.alloc(u8, n);
        \\    errdefer allocator.free(buf);
        \\    @memset(buf, 0);
        \\    return buf;
        \\}
        \\fn freeSub(allocator: Allocator, buf: []u8) void {
        \\    allocator.free(buf[1..]);
        \\}
        \\fn rawRead(file: File, dest: []u8) !usize {
        \\    return std.posix.read(file.handle, dest);
        \\}
        \\fn readClosed(file: File, io: Io, dest: []u8) !usize {
        \\    file.close(io);
        \\    return readSome(file, io, dest);
        \\}
    , &.{ .try_before_release, .free_not_owned, .posix_assumes_errno, .raw_handle, .use_after_close });
}

test "errno" {
    try expectChecks(
        \\fn tooLate(path: [*:0]const u8) c_int {
        \\    const rc = std.c.access(path, 0);
        \\    std.c._errno().* = 0;
        \\    if (rc == -1) return std.c._errno().*;
        \\    return rc;
        \\}
        \\fn ignoreRc() c_int {
        \\    return std.c._errno().*;
        \\}
        \\fn late(rc: c_int) c_int {
        \\    if (rc == -1) {
        \\        std.debug.print("failed\n", .{});
        \\        return std.c._errno().*;
        \\    }
        \\    return 0;
        \\}
        \\fn captureErrno(rc: c_int) error{Failed}!c_int {
        \\    if (rc != -1) return 0;
        \\    const err = std.c._errno().*;
        \\    if (err == 0) return error.Failed;
        \\    return err;
        \\}
    , &.{ .errno_clear_after_call, .errno_without_failure, .errno_after_call });
}

test "outside values that reach an assumption" {
    try expectChecks(
        \\export fn at(buf: [*]const u8, len: usize, i: usize) u8 {
        \\    std.debug.assert(i < len);
        \\    return buf[i];
        \\}
        \\fn inner(i: usize, len: usize) void {
        \\    std.debug.assert(i < len);
        \\}
    , &.{.assert_on_input});
    try expectChecks(
        \\fn perItem(total: u32, count: u32) u32 {
        \\    return total / count;
        \\}
        \\fn rest(total: u32, count: u32) u32 {
        \\    return @rem(total, count);
        \\}
        \\fn checked(total: u32, count: u32) error{DivisionByZero}!u32 {
        \\    if (count == 0) return error.DivisionByZero;
        \\    return total / count;
        \\}
        \\fn half(total: u32) u32 {
        \\    return total / 2;
        \\}
    , &.{ .unchecked_divisor, .unchecked_divisor });
    try expectChecks(
        \\fn narrowUnchecked(wide: u32) u16 {
        \\    return @intCast(wide);
        \\}
        \\fn shift(value: u32, amount: u32) error{Overflow}!u32 {
        \\    if (amount >= @bitSizeOf(u32)) return error.Overflow;
        \\    return value << @as(u5, @intCast(amount));
        \\}
        \\fn rawOpcode(byte: u8) Opcode {
        \\    return @enumFromInt(byte);
        \\}
    , &.{ .unchecked_intcast, .unchecked_enum });
}

test "bare unions" {
    try expectChecks(
        \\const Raw = union {
        \\    int: u32,
        \\    float: f32,
        \\};
        \\const Value = union(enum) { int: u32, float: f32 };
        \\const Tagged = union(Tag) { a: u8 };
        \\const C = extern union { a: u32, b: f32 };
        \\const P = packed union { a: u32, b: f32 };
    , &.{.bare_union});
}

test "review fixes: suppression, sentinels, comptime, wrapping, guards" {
    try expectChecks(
        \\fn bump(x: *u8) void {
        \\    _ = "misra-lint: allow runtime_safety_off quoted"; @setRuntimeSafety(false);
        \\    x.* += 1;
        \\}
    , &.{.runtime_safety_off});
    try expectChecks(
        \\fn twice(f: anytype) void {
        \\    f() catch {}; // misra-lint: allow catch_empty the caller logs it
        \\    f() catch {};
        \\}
    , &.{.catch_empty});
    try expectChecks(
        \\fn terminate(buf: [:0]u8) void {
        \\    buf[buf.len] = 0;
        \\}
        \\fn past(buf: []u8) void {
        \\    buf[buf.len] = 0;
        \\}
    , &.{.index_at_len});
    try expectChecks(
        \\fn depth(comptime T: type) usize {
        \\    if (@typeInfo(T) != .optional) return 0;
        \\    return 1 + depth(@typeInfo(T).optional.child);
        \\}
        \\fn hashFloat(x: f32) u32 {
        \\    return @as(u32, @bitCast(x)) +% 1;
        \\}
    , &.{});
    try expectChecks(
        \\fn perItem(total: u32, count: u32) u32 {
        \\    if (count > 100) return 0;
        \\    return total / count;
        \\}
        \\fn g(f: anytype) void {
        \\    f() catch |err| {
        \\        _ = err;
        \\    };
        \\}
    , &.{ .unchecked_divisor, .catch_empty });
    try expectChecks(
        \\fn raw(byte: u8) Op {
        \\    return @fromBackingInt(@intCast(byte));
        \\}
    , &.{.unchecked_enum});
}

test "review fixes: errno, enums, read-only writes" {
    try expectChecks(
        \\fn parse(s: [*:0]const u8) error{Range}!c_ulong {
        \\    std.c._errno().* = 0;
        \\    const v = std.c.strtoul(s, null, 10);
        \\    if (std.c._errno().* != 0) return error.Range;
        \\    return v;
        \\}
        \\fn open(path: [*:0]const u8) c_int {
        \\    const f = std.c.fopen(path, "r");
        \\    if (f == null) {
        \\        const e = std.c._errno().*;
        \\        return e;
        \\    }
        \\    return 0;
        \\}
    , &.{});
    try expectChecks(
        \\fn color(c: Color) u8 {
        \\    return switch (c) {
        \\        .red => 1,
        \\        else => 0,
        \\    };
        \\}
        \\fn code(n: u8) u8 {
        \\    return switch (n) {
        \\        1 => 1,
        \\        else => 0,
        \\    };
        \\}
    , &.{.enum_else});
    try expectChecks(
        \\fn appendNote(dir: Dir, io: Io, name: []const u8) !void {
        \\    const file = try dir.openFile(io, name, .{ .mode = .read_only });
        \\    defer file.close(io);
        \\    try file.writeStreamingAll(io, "z");
        \\}
        \\fn rewrite(dir: Dir, io: Io, name: []const u8) !void {
        \\    const file = try dir.openFile(io, name, .{ .mode = .read_write });
        \\    defer file.close(io);
        \\    try file.writeStreamingAll(io, "z");
        \\}
    , &.{.write_read_only});
}

test "an else that returns an error, and .? in a test, are not reported" {
    try expectChecks(
        \\fn text(v: Value) error{NotText}![]const u8 {
        \\    return switch (v) {
        \\        .string => |s| s,
        \\        else => error.NotText,
        \\    };
        \\}
        \\test "lookup" {
        \\    _ = map.get("k").?;
        \\}
    , &.{});
}

test "deep nesting is reported, not parsed" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(std.testing.allocator);
    try source.appendSlice(std.testing.allocator, "const x: u32 = ");
    try source.appendNTimes(std.testing.allocator, '(', 10_000);
    try source.append(std.testing.allocator, '1');
    try source.appendNTimes(std.testing.allocator, ')', 10_000);
    try source.appendSlice(std.testing.allocator, ";\n");
    const text = try source.toOwnedSliceSentinel(std.testing.allocator, 0);
    defer std.testing.allocator.free(text);
    try expectChecks(text, &.{.parse_error});
}

test "termination, unwraps, capacity, limits, floats, escapes" {
    try expectChecks(
        \\fn decode(byte: u8) u8 {
        \\    if (byte > 1) @panic("bad");
        \\    return byte;
        \\}
        \\fn quit() noreturn {
        \\    std.process.exit(2);
        \\}
        \\pub fn main() void {
        \\    std.process.exit(1);
        \\}
    , &.{ .terminate_outside_main, .terminate_outside_main });
    try expectChecks(
        \\fn first(m: *const M, k: []const u8) u32 {
        \\    return m.get(k) orelse unreachable;
        \\}
        \\fn second(m: *const M, k: []const u8) u32 {
        \\    return m.get(k).?;
        \\}
    , &.{ .orelse_unreachable, .unwrap_assumed });
    try expectChecks(
        \\fn push(gpa: Allocator, list: *List, a: u32) !void {
        \\    try list.ensureUnusedCapacity(gpa, 1);
        \\    list.appendAssumeCapacity(a);
        \\}
        \\fn pushBlind(list: *List, a: u32) void {
        \\    list.appendAssumeCapacity(a);
        \\}
    , &.{.assume_capacity});
    try expectChecks(
        \\fn slurp(dir: Dir, io: Io, gpa: Allocator) ![]u8 {
        \\    return dir.readFileAlloc(io, "x", gpa, .unlimited);
        \\}
        \\fn sip(dir: Dir, io: Io, gpa: Allocator) ![]u8 {
        \\    return dir.readFileAlloc(io, "x", gpa, .limited(4096));
        \\}
    , &.{.unlimited_limit});
    try expectChecks(
        \\fn toMillis(seconds: f64) u32 {
        \\    return @trunc(seconds * 1000.0);
        \\}
        \\fn old(x: f64) u32 {
        \\    return @intFromFloat(x);
        \\}
        \\fn checked(seconds: f64) error{OutOfRange}!u32 {
        \\    const ms = seconds * 1000.0;
        \\    if (!(ms >= 0.0 and ms < 4294967296.0)) return error.OutOfRange;
        \\    return @trunc(ms);
        \\}
        \\fn whole(x: f64) f64 {
        \\    return @trunc(x);
        \\}
    , &.{ .float_to_int, .float_to_int });
    try expectChecks(
        \\fn makeSlice(n: u8) []const u8 {
        \\    const local = [4]u8{ n, 0, 0, 0 };
        \\    return local[0..];
        \\}
        \\fn addr() *u32 {
        \\    var x: u32 = 1;
        \\    x += 1;
        \\    return &x;
        \\}
        \\fn view(buf: []const u8) []const u8 {
        \\    return buf[1..];
        \\}
    , &.{ .stack_escape, .stack_escape });
}

test "generated std lists: deprecated declarations and posix wrappers" {
    try expectChecks(
        \\fn colon(s: []const u8) ?usize {
        \\    return std.mem.indexOfScalar(u8, s, ':');
        \\}
        \\fn reuse(fd: i32) !void {
        \\    try std.posix.setsockopt(fd, 1, 2, &.{});
        \\}
    , &.{ .deprecated_api, .posix_assumes_errno });
}

test "threads, io, extern, sentinels, builds, pointer casts" {
    try expectChecks(
        \\fn handle(conns: []const Conn) !void {
        \\    for (conns) |c| {
        \\        const t = try std.Thread.spawn(.{}, serve, .{c});
        \\        t.detach();
        \\    }
        \\}
        \\pub fn main() !void {
        \\    var workers: [4]std.Thread = undefined;
        \\    for (&workers) |*w| w.* = try std.Thread.spawn(.{}, work, .{});
        \\    for (workers) |w| w.join();
        \\}
    , &.{ .thread_outside_main, .thread_detached });
    try expectChecks(
        \\pub fn main() !void {
        \\    while (accepting()) {
        \\        const t = try std.Thread.spawn(.{}, work, .{});
        \\        t.join();
        \\    }
        \\}
    , &.{.thread_in_loop});
    try expectChecks(
        \\pub fn build(b: *std.Build) void {
        \\    var threaded = std.Io.Threaded.init(b.allocator, .{});
        \\    defer threaded.deinit();
        \\}
    , &.{});
    try expectChecks(
        \\fn logLine(msg: []const u8) !void {
        \\    var threaded: std.Io.Threaded = .init(std.heap.smp_allocator, .{});
        \\    defer threaded.deinit();
        \\    _ = msg;
        \\}
    , &.{.io_outside_main});
    try expectChecks(
        \\extern "c" fn fuse_reply_buf(req: ?*anyopaque) c_int;
        \\fn find(items: []const u32, x: u32) usize {
        \\    for (items, 0..) |item, i| {
        \\        if (item == x) return i;
        \\    }
        \\    return std.math.maxInt(usize);
        \\}
        \\export fn status() c_int {
        \\    return -1;
        \\}
    , &.{ .handwritten_extern, .sentinel_return });
    try expectChecks(
        \\pub fn build(b: *std.Build) void {
        \\    _ = b.addModule("m", .{ .optimize = .ReleaseFast, .sanitize_c = .off });
        \\}
    , &.{ .build_unsafe_mode, .build_unsafe_mode });
    try expectChecks(
        \\fn bitsByPointer(x: *const f32) u32 {
        \\    const p: *const u32 = @ptrCast(x);
        \\    return p.*;
        \\}
        \\fn headerOf(bytes: []const u8) *const Header {
        \\    const aligned: [*]align(8) const u8 = @alignCast(bytes.ptr);
        \\    return @ptrCast(aligned);
        \\}
    , &.{.ptrcast_reinterpret});
}

test "float mode, noalias, const casts, variadics, pointer arithmetic" {
    try expectChecks(
        \\fn scaled(a: f64, b: f64) f64 {
        \\    @setFloatMode(.optimized);
        \\    return a * b;
        \\}
        \\fn strict(a: f64, b: f64) f64 {
        \\    @setFloatMode(.strict);
        \\    return a * b;
        \\}
    , &.{.float_mode_optimized});
    try expectChecks(
        \\fn addTwice(noalias total: *u32, step: *const u32) void {
        \\    total.* +%= step.*;
        \\}
        \\fn plain(total: *u32, step: *const u32) void {
        \\    total.* +%= step.*;
        \\}
    , &.{.noalias_param});
    try expectChecks(
        \\fn raise(xs: []const u32) []u32 {
        \\    return @constCast(xs);
        \\}
        \\fn unvolatile(p: *volatile u32) *u32 {
        \\    return @volatileCast(p);
        \\}
    , &.{ .const_cast, .const_cast });
    try expectChecks(
        \\export fn first(n: c_int, ...) callconv(.c) c_int {
        \\    _ = n;
        \\    var ap = @cVaStart();
        \\    defer @cVaEnd(&ap);
        \\    return @cVaArg(&ap, c_int);
        \\}
        \\extern "c" fn printf(fmt: [*:0]const u8, ...) c_int;
    , &.{ .c_variadic, .handwritten_extern });
    try expectChecks(
        \\fn third(p: [*]const u32) u32 {
        \\    return (p + 2)[0];
        \\}
        \\fn span(p: [*]const u32, q: [*]const u32) usize {
        \\    return q - p;
        \\}
        \\fn walk(start: [*c]const u8) u8 {
        \\    var p: [*c]const u8 = start;
        \\    p += 1;
        \\    return p[0];
        \\}
        \\fn sliced(p: [*]const u32, len: usize) usize {
        \\    const items = p[0..len];
        \\    return items.len + 2;
        \\}
    , &.{ .pointer_arith, .pointer_arith, .pointer_arith });
}

test "aliasing copies, atomic orders, and a mutex locked twice" {
    try expectChecks(
        \\fn shiftLeft(buf: []u8) void {
        \\    @memcpy(buf[0..4], buf[1..5]);
        \\}
        \\fn dropFront(buf: []u8) void {
        \\    @memmove(buf[0..4], buf[1..5]);
        \\}
        \\fn copyTo(dest: []u8, src: []const u8) void {
        \\    @memcpy(dest[0..4], src[0..4]);
        \\}
    , &.{.memcpy_alias});
    try expectChecks(
        \\fn publish(ready: *std.atomic.Value(bool)) void {
        \\    ready.store(true, .release);
        \\}
        \\fn seen(ready: *std.atomic.Value(bool)) bool {
        \\    return ready.load(.acquire);
        \\}
        \\fn bump(n: *u32) u32 {
        \\    return @atomicRmw(u32, n, .Add, 1, .monotonic);
        \\}
        \\fn strong(ready: *std.atomic.Value(bool), hits: *std.atomic.Value(u64)) void {
        \\    ready.store(true, .seq_cst);
        \\    _ = hits.fetchAdd(1, .seq_cst);
        \\}
        \\fn unrelated(pedal: *Pedal) void {
        \\    pedal.set(.release);
        \\}
    , &.{ .atomic_order, .atomic_order, .atomic_order });
    try expectChecks(
        \\fn relock(io: std.Io, mu: *std.Io.Mutex) !void {
        \\    try mu.lock(io);
        \\    defer mu.unlock(io);
        \\    try mu.lock(io);
        \\    defer mu.unlock(io);
        \\}
        \\fn twice(io: std.Io, mu: *std.Io.Mutex) !void {
        \\    try mu.lock(io);
        \\    mu.unlock(io);
        \\    try mu.lock(io);
        \\    defer mu.unlock(io);
        \\}
        \\fn branches(io: std.Io, mu: *std.Io.Mutex, fast: bool) !void {
        \\    if (fast) {
        \\        try mu.lock(io);
        \\        defer mu.unlock(io);
        \\    }
        \\    try mu.lock(io);
        \\    defer mu.unlock(io);
        \\}
        \\fn logout(io: std.Io, mu: *std.Io.Mutex) !void {
        \\    mu.lockUncancelable(io);
        \\    errdefer mu.unlock(io);
        \\    try work();
        \\    mu.unlock(io);
        \\}
        \\fn both(io: std.Io, a: *std.Io.Mutex, b: *std.Io.Mutex) !void {
        \\    try a.lock(io);
        \\    defer a.unlock(io);
        \\    try b.lock(io);
        \\    defer b.unlock(io);
        \\}
    , &.{.lock_twice});
}

test "an allow comment needs the check and a reason" {
    try expectChecks(
        \\fn serve() void {
        \\    // misra-lint: allow unbounded_loop the process runs until it is killed
        \\    while (true) {}
        \\}
        \\fn spin() void {
        \\    while (true) {} // misra-lint: allow unbounded_loop
        \\}
    , &.{.unbounded_loop});
}

test "every check has rules and a summary" {
    for (std.enums.values(Check)) |check| {
        const about = info(check);
        try std.testing.expect(about.summary.len > 0);
        if (check != .parse_error) try std.testing.expect(about.rules.len > 0);
    }
}
