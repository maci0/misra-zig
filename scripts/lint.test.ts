import { beforeAll, expect, test } from "bun:test";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { checkSource, compileLimitFromEnv, projectRoot } from "./check.ts";
import { parseHandbook } from "./handbook.ts";
import { buildLint, lintChecks, lintSample } from "./lint.ts";

const root = projectRoot(import.meta.dir);
const book = parseHandbook(readFileSync(join(root, "docs", "misra-zig-handbook.md"), "utf8"));

/**
 * Don't samples that compile and that misra-lint does not flag, keyed `rule-id/index`.
 * Each reason names what a syntax tree cannot see. Moving an entry out means a check now decides it.
 */
const UNDECIDED: Record<string, string> = {
    "dir-5-1/0": "which threads touch a variable is not in one file's syntax tree",
    "dir-4-1/4": "whether a reserve covers every AssumeCapacity call is a count of items, not syntax",
    "rule-8-4/0": "the C header is not in the file, so a usize parameter cannot be compared with uint32_t",
    "rule-8-7/0": "whether another file uses a pub function needs every file of the program",
    "rule-10-2/0": "a u8 plus 1 is a character step only if the byte means a character",
    "rule-16-3/0": "a pasted body that fakes fallthrough is ordinary statements",
    "rule-22-7/0": "comparing a byte with 0xFF is data handling until the reader knows it marks the end",
    "dir-4-11/0": "which std functions assert an argument is in the std source, not in the file",
    "dir-4-11/1": "which std functions assert an argument is in the std source, not in the file",
    "dir-4-15/0": "whether a parameter is a float and can be NaN needs types and the caller",
    "dir-5-2/0": "the lock order is set by the callers, in other functions and threads",
    "rule-19-3/0": "a field access on a tagged union looks like any field access without types",
};

let bin = "";

beforeAll(async () => {
    bin = await buildLint(root);
}, 300_000);

function dontSamples() {
    return book.rules.flatMap((rule) =>
        (rule.dont?.samples ?? []).map((sample, index) => ({ rule, sample, index })),
    );
}

test("every do sample lints clean", async () => {
    for (const rule of book.rules) {
        for (const sample of rule.do?.samples ?? []) {
            const findings = await lintSample(bin, sample.code);
            expect({ rule: rule.id, findings }).toEqual({ rule: rule.id, findings: [] });
        }
    }
});

test("every compiling don't sample is flagged under its rule or listed as undecided", async () => {
    const missed: string[] = [];
    for (const { rule, sample, index } of dontSamples()) {
        if (!sample.before.trimStart().startsWith("**Compiles")) continue;
        const key = `${rule.id}/${index}`;
        const findings = await lintSample(bin, sample.code);
        const flagged = findings.some((item) => item.rules.includes(rule.id));
        if (key in UNDECIDED) {
            expect({ key, flagged }).toEqual({ key, flagged: false });
        } else if (!flagged) {
            missed.push(key);
        }
    }
    expect(missed).toEqual([]);
});

test("the reference file and the checker itself lint clean", async () => {
    for (const file of ["docs/examples/compliant.zig", "tools/misra_lint.zig"]) {
        const proc = Bun.spawn({ cmd: [bin, file], cwd: root, stdout: "pipe", stderr: "pipe" });
        const out = await new Response(proc.stdout).text();
        expect({ file, code: await proc.exited, out }).toEqual({ file, code: 0, out: "" });
    }
});

test("every check names handbook rules that exist", async () => {
    const ids = new Set(book.rules.map((rule) => rule.id));
    const checks = await lintChecks(bin);
    expect(checks.length).toBeGreaterThan(30);
    for (const check of checks) {
        if (check.id === "parse_error") continue;
        expect(check.rules.length).toBeGreaterThan(0);
        for (const id of check.rules) expect(ids.has(id)).toBe(true);
    }
});

test("findings map back to the lines of a fragment", async () => {
    const findings = await lintSample(bin, "const file = try dir.openFile(io, name, .{});\ntry file.sync(io);\nfile.close(io);\nreturn readSome(file, io, dest);\n");
    expect(findings.map((item) => [item.check, item.line])).toEqual([
        ["try_before_release", 1],
        ["use_after_close", 4],
    ]);
});

test("an unparsable sample reports one parse error", async () => {
    const findings = await lintSample(bin, "fn f( {\n");
    expect(findings.map((item) => item.check)).toEqual(["parse_error"]);
    expect(findings[0]?.subject.length).toBeGreaterThan(0);
});

test("compiler errors map to the lines of the sample", async () => {
    const result = await checkSource(root, "export fn f(n: u32) u32 {\n    if (n) return 1;\n    return 0;\n}\n");
    expect(result.status).toBe("rejected");
    expect(result.errors.map((item) => item.line)).toEqual([2]);
    expect(result.errors[0]?.message).toContain("bool");
}, 120_000);

test("review.ts groups findings by rule and lists the rules no check decides", async () => {
    const dir = join(root, ".scratch", "review-test");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "demo.zig"), "const Raw = union {\n    int: u32,\n    float: f32,\n};\n");
    const proc = Bun.spawn({ cmd: ["bun", join(root, "scripts", "review.ts"), "demo.zig"], cwd: dir, stdout: "pipe", stderr: "pipe" });
    const out = await new Response(proc.stdout).text();
    expect(await proc.exited).toBe(1);
    expect(out).toContain("### Rule 19.2: A bare union is not used.");
    expect(out).toContain("- `demo.zig:1:13` violation `bare_union`");
    expect(out).toContain("- [ ] Rule 16.3: Prongs do not fall through.");
    expect(out).toContain("Checked by `bare_union`.");
}, 300_000);

test("two builds at once leave a binary that runs", async () => {
    const [a, b] = await Promise.all([buildLint(root), buildLint(root)]);
    expect(a).toBe(b);
    expect((await lintChecks(a)).length).toBeGreaterThan(30);
}, 300_000);

test("Check analyzes methods of a top-level struct and accepts a valid one", async () => {
    const good = await checkSource(root, "const S = struct {\n    fn get(n: u32) u32 {\n        return n;\n    }\n};\n");
    expect({ status: good.status, output: good.output }).toEqual({ status: "accepted", output: "zig test --test-no-exec -lc -ODebug passed." });
    const bad = await checkSource(root, "const S = struct {\n    fn bad(n: u32) bool {\n        return n;\n    }\n};\n");
    expect(bad.status).toBe("rejected");
    expect(bad.errors.map((item) => item.line)).toEqual([3]);
}, 300_000);

test("Check analyzes methods at any container depth, and not a generic's returned struct", async () => {
    const sameLine = await checkSource(root, "const S = struct { fn bad(n: u32) bool { return n; } };\n");
    expect(sameLine.status).toBe("rejected");
    const deep = await checkSource(root, "const A = struct {\n    const B = struct {\n        fn bad(n: u32) bool {\n            return n;\n        }\n    };\n};\n");
    expect(deep.errors.map((item) => item.line)).toEqual([4]);
    const generic = await checkSource(root, "fn List(comptime T: type) type {\n    return struct {\n        fn first(items: []const T) T {\n            return items[0];\n        }\n    };\n}\n");
    expect(generic.status).toBe("accepted");
}, 300_000);

test("a compile over the memory limit is stopped and reported", async () => {
    const big = "comptime {\n    var a: [512 * 1024 * 1024]u8 = undefined;\n    a[7] = 1;\n    if (a[7] != 1) @compileError(\"x\");\n}\n";
    const result = await checkSource(root, big, compileLimitFromEnv("1G"));
    expect(result.status).toBe("failed");
    expect(result.output).toContain("compile memory limit");
}, 300_000);

test("the compile limit setting is validated", () => {
    expect(compileLimitFromEnv(undefined)).toBe(4 * 1024 ** 3);
    expect(compileLimitFromEnv("2G")).toBe(2 * 1024 ** 3);
    expect(compileLimitFromEnv("768M")).toBe(768 * 1024 ** 2);
    expect(() => compileLimitFromEnv("100M")).toThrow("at least 512M");
    expect(() => compileLimitFromEnv("lots")).toThrow("bytes, or a number");
});

test("--root reports a file the root does not reach through @import", async () => {
    const dir = join(root, ".scratch", "root-test", "src");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "main.zig"), 'test {\n    _ = @import("parse/a.zig");\n}\n');
    mkdirSync(join(dir, "parse"), { recursive: true });
    writeFileSync(join(dir, "parse", "a.zig"), 'const b = @import("../util.zig");\n');
    writeFileSync(join(dir, "util.zig"), "const x: u32 = 1;\n");
    writeFileSync(join(dir, "orphan.zig"), "const y: u32 = 2;\n");
    const files = ["src/main.zig", "src/parse/a.zig", "src/util.zig", "src/orphan.zig"];
    const proc = Bun.spawn({ cmd: [bin, "--root", "src/main.zig", ...files], cwd: join(dir, ".."), stdout: "pipe", stderr: "pipe" });
    const out = await new Response(proc.stdout).text();
    expect(await proc.exited).toBe(1);
    expect(out.trim().split("\n")).toEqual([
        "src/orphan.zig:1:1: violation[unreachable_file] Rule 2.1: The root does not reach this file through @import, so the compiler never analyzes it. (src/main.zig)",
    ]);
});

test("tools/std_lists.zig matches the installed standard library", async () => {
    const proc = Bun.spawn({ cmd: ["bun", join(root, "scripts", "gen_std_lists.ts"), "--check"], cwd: root, stdout: "pipe", stderr: "pipe" });
    const [out, err] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
    expect({ code: await proc.exited, out: out.trim(), err: err.trim() }).toEqual({ code: 0, out: "tools/std_lists.zig matches the installed std", err: "" });
}, 120_000);
