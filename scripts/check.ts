import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const HEADER = `const Header = extern struct {
    magic: u32,
    size: u64,
};
`;

const COLOR = `const Color = enum { red, blue };
`;

const OPCODE = `const Opcode = enum(u8) { load = 1, store = 2 };
`;

const SUM_WIDE = `fn sumWide(a: u16, b: u16) error{Overflow}!u32 {
    return std.math.add(u32, a, b);
}
`;

const NODE = `const Node = struct {
    value: u32,
    left: ?*const Node,
    right: ?*const Node,
};
`;

const RIGHT = `const right: Node = .{ .value = 0, .left = null, .right = null };
`;

const READ_SOME = `fn readSome(file: std.Io.File, io: std.Io, dest: []u8) !usize {
    return file.readStreaming(io, &.{dest});
}
`;

const CAPTURE = `fn captureErrno(rc: c_int) error{Failed}!c_int {
    if (rc != -1) return 0;
    const err = std.c._errno().*;
    if (err == 0) return error.Failed;
    return err;
}
`;

function isFragment(source: string): boolean {
    const hasFn = /^[ \t]*(?:export[ \t]+|pub[ \t]+)?(?:inline[ \t]+)?fn[ \t]+/m.test(source);
    if (hasFn) return false;
    return /^[ \t]*(?:defer|return)\b/m.test(source);
}

const CONTAINER_KEYWORDS = new Set(["struct", "union", "enum", "opaque"]);

/**
 * The functions to reference so Zig analyzes their bodies: every `fn` at the top
 * level and inside a named container at any depth, written `A.B.name`. A `fn`
 * inside a function body (a generic's returned struct) is not referenced, since
 * it has no name outside that call. Strings and comments are skipped.
 */
export function referencedFns(source: string): string[] {
    const names: string[] = [];
    // One entry per open brace: the container name it opens, or null for any other brace.
    const braces: (string | null)[] = [];
    let pendingContainer: string | null = null;
    let pendingFn = false;
    let i = 0;
    const word = /[A-Za-z_][A-Za-z0-9_]*/y;
    while (i < source.length) {
        const c = source[i];
        if (c === "/" && source[i + 1] === "/") {
            const nl = source.indexOf("\n", i);
            i = nl === -1 ? source.length : nl;
            continue;
        }
        if (c === "\\" && source[i + 1] === "\\") {
            const nl = source.indexOf("\n", i);
            i = nl === -1 ? source.length : nl;
            continue;
        }
        if (c === '"' || c === "'") {
            i += 1;
            while (i < source.length && source[i] !== c && source[i] !== "\n") i += source[i] === "\\" ? 2 : 1;
            i += 1;
            continue;
        }
        if (c === "{") {
            braces.push(pendingFn ? null : pendingContainer);
            pendingContainer = null;
            pendingFn = false;
            i += 1;
            continue;
        }
        if (c === "}") {
            braces.pop();
            i += 1;
            continue;
        }
        word.lastIndex = i;
        const match = word.exec(source);
        if (!match) {
            if (c === ";") {
                pendingContainer = null;
                pendingFn = false;
            }
            i += 1;
            continue;
        }
        const token = match[0];
        i += token.length;
        if (token === "fn") {
            const name = /\s+([A-Za-z_][A-Za-z0-9_]*)/y;
            name.lastIndex = i;
            const fnName = name.exec(source)?.[1];
            // Only a fn whose every enclosing brace is a named container is reachable by name.
            if (fnName && braces.every((brace) => brace !== null)) names.push([...braces, fnName].join("."));
            pendingFn = true;
            continue;
        }
        if (token === "const" || token === "var") {
            const decl = /\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:extern\s+|packed\s+)?([A-Za-z_]+)\b/y;
            decl.lastIndex = i;
            const found = decl.exec(source);
            if (found?.[1] && found[2] && CONTAINER_KEYWORDS.has(found[2])) pendingContainer = found[1];
        }
    }
    return [...new Set(names)];
}

function declares(source: string, name: string): boolean {
    const re = new RegExp(`^[ \\t]*(?:pub[ \\t]+)?(?:const|var|fn)[ \\t]+${name}\\b`, "m");
    return re.test(source);
}

function mentions(source: string, name: string): boolean {
    return new RegExp(`\\b${name}\\b`).test(source);
}

function addDecl(source: string, name: string, decl: string, out: string[]): void {
    if (mentions(source, name) && !declares(source, name)) out.push(decl);
}

export type Wrapped = {
    text: string;
    /** The line of `text` that holds the first line of the source. */
    firstLine: number;
};

export function wrapSource(source: string): Wrapped {
    const fragment = isFragment(source);
    const ended = source.endsWith("\n") ? source : `${source}\n`;
    const body = fragment
        ? `fn siteFragment(dir: std.Io.Dir, io: std.Io, name: []const u8, dest: []u8) !usize {\n${ended}}\n`
        : ended;
    const extra: string[] = [];
    if (!declares(source, "std") && !source.includes('@import("std")')) {
        extra.push('const std = @import("std");\n');
    }
    addDecl(source, "Header", HEADER, extra);
    addDecl(source, "Color", COLOR, extra);
    addDecl(source, "Opcode", OPCODE, extra);
    addDecl(source, "sumWide", SUM_WIDE, extra);
    addDecl(source, "Node", NODE, extra);
    addDecl(source, "readSome", READ_SOME, extra);
    addDecl(source, "captureErrno", CAPTURE, extra);
    if (source.includes("&right") && !declares(source, "right")) extra.push(RIGHT);
    const touches = referencedFns(body).map((name) => `test {\n    _ = &${name};\n}\n`).join("");
    return { text: `${body}${extra.join("\n")}${touches}`, firstLine: fragment ? 2 : 1 };
}

export type CompilerError = {
    /** 1-based line in the source the caller sent. */
    line: number;
    column: number;
    message: string;
};

export type CheckResult = {
    status: "accepted" | "rejected" | "failed";
    output: string;
    errors: CompilerError[];
};

const ERROR_LINE = /^sample\.zig:(\d+):(\d+): error: (.*)$/gm;

/** The compiler's `error:` lines that fall inside the source, in source line numbers. */
export function compilerErrors(output: string, wrapped: Wrapped, source: string): CompilerError[] {
    const last = wrapped.firstLine + source.replace(/\n$/, "").split("\n").length - 1;
    const errors: CompilerError[] = [];
    for (const match of output.matchAll(ERROR_LINE)) {
        const line = Number(match[1]);
        if (line < wrapped.firstLine || line > last) continue;
        errors.push({ line: line - wrapped.firstLine + 1, column: Number(match[2]), message: match[3] ?? "" });
    }
    return errors;
}

export const MAX_SOURCE_BYTES = 64 * 1024;

/** The UTF-8 size of a source text; `string.length` counts UTF-16 units. */
export function sourceBytes(source: string): number {
    return Buffer.byteLength(source, "utf8");
}
const ZIG_TIMEOUT_MS = 60_000;
const OUTPUT_LIMIT = 12_000;

/** Reads a stream as text and stops keeping it after `limit` bytes; the rest is drained so the child does not block. */
async function readCapped(stream: ReadableStream<Uint8Array>, limit: number): Promise<{ text: string; cut: boolean }> {
    const reader = stream.getReader();
    const kept: Uint8Array[] = [];
    let size = 0;
    let cut = false;
    for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        if (size >= limit) {
            cut = true;
            continue;
        }
        const room = limit - size;
        kept.push(value.length > room ? value.subarray(0, room) : value);
        cut = cut || value.length > room;
        size += Math.min(value.length, room);
    }
    return { text: Buffer.concat(kept).toString("utf8"), cut };
}

/** The address-space cap for one compile, in bytes. */
export const DEFAULT_COMPILE_LIMIT = 4 * 1024 * 1024 * 1024;
const MIN_COMPILE_LIMIT = 512 * 1024 * 1024;

/**
 * The compile memory cap from `MISRA_ZIG_COMPILE_LIMIT`: bytes, or a number with
 * a `M` or `G` suffix (MiB, GiB). Throws when the value is malformed or below 512 MiB.
 */
export function compileLimitFromEnv(value: string | undefined): number {
    if (value === undefined || value === "") return DEFAULT_COMPILE_LIMIT;
    const match = /^(\d+)([MG]?)$/.exec(value.trim());
    if (!match?.[1]) throw new Error("MISRA_ZIG_COMPILE_LIMIT must be bytes, or a number followed by M or G");
    const scale = match[2] === "G" ? 1024 ** 3 : match[2] === "M" ? 1024 ** 2 : 1;
    const bytes = Number(match[1]) * scale;
    if (bytes < MIN_COMPILE_LIMIT) throw new Error("MISRA_ZIG_COMPILE_LIMIT must be at least 512M");
    return bytes;
}

function projectScratch(root: string): string {
    const dir = join(root, ".scratch", "site-check");
    mkdirSync(dir, { recursive: true });
    return dir;
}

export function zigCommand(): string {
    return process.env.ZIG && process.env.ZIG.length > 0 ? process.env.ZIG : "zig";
}

/** `zig version`, or "" when the compiler cannot be started. */
export async function zigVersion(bin: string): Promise<string> {
    try {
        const proc = Bun.spawn({ cmd: [bin, "version"], stdout: "pipe", stderr: "ignore" });
        const out = await new Response(proc.stdout).text();
        return (await proc.exited) === 0 ? out.trim() : "";
    } catch {
        // Bun.spawn throws when the binary is missing; the caller shows "not on PATH".
        return "";
    }
}

function present(output: string, file: string): string {
    return output
        .replaceAll(file, "sample.zig")
        .replace(/\.scratch\/site-check\/run-[^/\s]+\/sample\.zig/g, "sample.zig")
        .split("\n")
        .filter((line) => !line.includes("referenced by:") && !/^\s+test_\d+:/.test(line))
        .join("\n");
}

function clip(text: string): string {
    const clean = text.replace(/\u001b\[[0-9;]*m/g, "").trim();
    if (clean.length <= OUTPUT_LIMIT) return clean;
    return `${clean.slice(0, OUTPUT_LIMIT)}\n…`;
}

/**
 * Compiles a sample. `memoryLimit` caps the compiler's address space in bytes
 * through `prlimit`; null runs it uncapped (tests, and the start-up warm-up that
 * builds libc into the cache, which needs more than a sample does).
 */
export async function checkSource(root: string, source: string, memoryLimit: number | null = null): Promise<CheckResult> {
    if (sourceBytes(source) > MAX_SOURCE_BYTES) {
        return { status: "failed", output: "The sample is longer than 64 KiB.", errors: [] };
    }
    if (source.trim().length === 0) {
        return { status: "failed", output: "The editor is empty.", errors: [] };
    }
    const scratch = projectScratch(root);
    const work = mkdtempSync(join(scratch, "run-"));
    const file = join(work, "sample.zig");
    const wrapped = wrapSource(source);
    writeFileSync(file, wrapped.text);
    const cache = join(scratch, "cache");
    const globalCache = join(scratch, "global-cache");
    mkdirSync(cache, { recursive: true });
    mkdirSync(globalCache, { recursive: true });
    try {
        // prlimit is an external process because Bun.spawn has no rlimit option.
        const cap = memoryLimit === null ? [] : ["prlimit", `--as=${memoryLimit}`, "--"];
        const proc = Bun.spawn({
            cmd: [
                ...cap,
                zigCommand(),
                "test",
                "--test-no-exec",
                "-lc",
                "-ODebug",
                "--color",
                "off",
                "--cache-dir",
                cache,
                "--global-cache-dir",
                globalCache,
                "sample.zig",
            ],
            cwd: work,
            stdout: "pipe",
            stderr: "pipe",
            timeout: ZIG_TIMEOUT_MS,
            killSignal: "SIGKILL",
        });
        const [out, err] = await Promise.all([readCapped(proc.stdout, OUTPUT_LIMIT), readCapped(proc.stderr, OUTPUT_LIMIT)]);
        const code = await proc.exited;
        if (proc.signalCode === "SIGKILL") {
            return { status: "failed", output: "Zig did not finish within 60 seconds.", errors: [] };
        }
        // Under the cap Zig either crashes (abort, segfault) or reports `error: OutOfMemory`.
        const outOfMemory = /^error: OutOfMemory$/m.test(`${out.text}${err.text}`);
        if (memoryLimit !== null && (proc.signalCode !== null || code === 134 || code === 139 || outOfMemory)) {
            const gib = (memoryLimit / 1024 ** 3).toFixed(1);
            return { status: "failed", output: `Zig stopped under the ${gib} GiB compile memory limit (exit ${code ?? proc.signalCode}).`, errors: [] };
        }
        const output = clip(present(`${out.text}${err.text}`, file)) + (out.cut || err.cut ? "\n…" : "");
        if (code === 0) {
            return {
                status: "accepted",
                output: output.length > 0 ? output : "zig test --test-no-exec -lc -ODebug passed.",
                errors: [],
            };
        }
        return {
            status: "rejected",
            output: output.length > 0 ? output : `zig exited ${code}.`,
            errors: compilerErrors(output, wrapped, source),
        };
    } catch (err) {
        const message = err instanceof Error ? err.message : "Zig could not be started.";
        return { status: "failed", output: message, errors: [] };
    } finally {
        rmSync(work, { recursive: true, force: true });
    }
}

/** Walks up from `here` to the directory that holds AGENTS.md. */
export function projectRoot(here: string): string {
    let dir = here;
    for (;;) {
        if (existsSync(join(dir, "AGENTS.md"))) return dir;
        const parent = dirname(dir);
        if (parent === dir) throw new Error("AGENTS.md not found");
        dir = parent;
    }
}
