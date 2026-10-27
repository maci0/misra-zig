import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { wrapSource } from "./check.ts";
import { agentRules, parseHandbook } from "./handbook.ts";

const markdown = readFileSync(new URL("../docs/misra-zig-handbook.md", import.meta.url), "utf8");
const book = parseHandbook(markdown);
const rules = agentRules(book);

function marksOf(id: string): string[] {
    const rule = rules.rules.find((item) => item.id === id);
    if (!rule) throw new Error(`missing ${id}`);
    return rule.dont.cases.map((item) => item.mark);
}

test("each group says what it covers", () => {
    expect(book.groups).toHaveLength(8);
    for (const group of book.groups) {
        expect(group.blurb.length).toBeGreaterThan(20);
    }
    expect(book.groups.map((group) => group.title)).toContain("Control flow");
});

test("counts the cited rules", () => {
    expect(book.rules.filter((rule) => rule.kind === "dir")).toHaveLength(10);
    expect(book.rules.filter((rule) => rule.kind === "rule")).toHaveLength(49);
    expect(book.rules.some((rule) => rule.id === "reading")).toBe(true);
    expect(book.rules.some((rule) => rule.id === "compiler")).toBe(true);
});

test("keeps the source project unnamed", () => {
    expect(JSON.stringify(book).toLowerCase()).not.toContain("openvddk");
    expect(JSON.stringify(rules).toLowerCase()).not.toContain("openvddk");
});

test("rules.json marks every don't from the handbook leads", () => {
    expect(rules.zig).toBe("0.17.0");
    expect(rules.source).toBe("docs/misra-zig-handbook.md");
    expect(rules.rules).toHaveLength(59);
    const leads = markdown.match(/^\*\*(?:Rejected|Compiles)\b/gm) ?? [];
    const cases = rules.rules.flatMap((rule) => rule.dont.cases);
    expect(cases).toHaveLength(leads.length);
    for (const rule of rules.rules) {
        expect(rule.obligation.length).toBeGreaterThan(0);
        expect(rule.do.zig.length + rule.do.note.length).toBeGreaterThan(0);
        expect(rule.dont.cases.length).toBeGreaterThan(0);
        for (const item of rule.dont.cases) {
            expect(item.mark === "rejected" || item.mark === "compiles").toBe(true);
            expect(item.why.length + item.zig.length).toBeGreaterThan(0);
        }
    }
    expect(marksOf("rule-8-1")).toEqual(["rejected", "compiles"]);
    expect(marksOf("rule-10-1")).toEqual(["rejected", "rejected", "compiles"]);
    expect(marksOf("rule-10-2")).toEqual(["compiles"]);
    expect(marksOf("rule-10-3")).toEqual(["rejected", "compiles", "compiles", "compiles"]);
    expect(marksOf("rule-10-5")).toEqual(["compiles", "compiles"]);
    expect(marksOf("rule-14-4")).toEqual(["rejected"]);
    expect(marksOf("rule-19-2")).toEqual(["compiles"]);
    expect(marksOf("rule-16-4")).toEqual(["compiles", "rejected"]);
    expect(marksOf("dir-5-2")).toEqual(["compiles", "compiles"]);
    expect(marksOf("rule-19-3")).toEqual(["compiles"]);
    const union = rules.rules.find((rule) => rule.id === "rule-19-3");
    expect(union?.do.zig).toEqual([]);
    expect(union?.do.note).toContain("asFloat");
    const pointed = rules.rules.find((rule) => rule.id === "rule-8-1");
    expect(pointed?.dont.cases[1]?.zig).toBe("");
    expect(pointed?.dont.cases[1]?.why).toContain("Dir 4.6");
    const loop = rules.rules.find((rule) => rule.id === "rule-14-4");
    expect(loop?.dont.cases[0]?.why).toContain("Rule 10.1");
    const rejected = rules.rules.flatMap((rule) => rule.dont.cases).filter((item) => item.mark === "rejected" && item.zig);
    expect(rejected.every((item) => item.zig.includes("export fn"))).toBe(true);
    const sum = rules.rules.find((rule) => rule.id === "rule-10-8");
    expect(sum?.do.zig).toEqual([]);
    expect(sum?.do.note).toContain("sumWide");
    const width = rules.rules.find((rule) => rule.id === "dir-4-6");
    expect(width?.dont.cases[1]?.why.startsWith("still the wrong width")).toBe(true);
    const libc = rules.rules.find((rule) => rule.id === "rule-21-3");
    expect(libc?.dont.cases[0]?.why.startsWith("when libc is linked")).toBe(true);
    const repair = rules.rules.find((rule) => rule.id === "rule-22-1");
    expect(repair?.dont.cases[0]?.why).toContain("errdefer allocator.free(first)");
});

test("every cited rule has a don't, with a sample or a pointer", () => {
    const missing = book.rules
        .filter((rule) => rule.kind !== "note")
        .filter((rule) => {
            if (!rule.dont) return true;
            if (rule.dont.samples.length > 0) return false;
            return rule.dont.after.trim().length === 0;
        })
        .map((rule) => rule.id);
    expect(missing).toEqual([]);
    const pointed = book.rules.find((rule) => rule.id === "rule-8-1");
    expect(pointed?.dont?.after).toContain("Dir 4.6");
});

test("rule 10.8 points at sumWide instead of a second do", () => {
    const rule = book.rules.find((item) => item.id === "rule-10-8");
    expect(rule?.do?.samples).toEqual([]);
    expect(rule?.do?.after).toContain("sumWide");
});

test("directive 4.12 does not swallow the next heading", () => {
    const rule = book.rules.find((item) => item.id === "dir-4-12");
    expect(rule?.intro.includes("## Rules")).toBe(false);
    expect(rule?.dont?.samples.length).toBeGreaterThan(0);
});

test("user source stays on line 1 and a missing Header is supplied", () => {
    const wrapped = wrapSource("fn headerOf(bytes: []const u8) void {\n    _ = Header;\n}\n");
    expect(wrapped.firstLine).toBe(1);
    expect(wrapped.text.startsWith("fn headerOf")).toBe(true);
    expect(wrapped.text).toContain("const Header");
    expect(wrapped.text).toContain("_ = &headerOf;");
});

test("a fragment is wrapped in a function and starts on line 2", () => {
    const wrapped = wrapSource("defer file.close(io);\nreturn 0;");
    expect(wrapped.firstLine).toBe(2);
    expect(wrapped.text.split("\n")[1]).toBe("defer file.close(io);");
});
