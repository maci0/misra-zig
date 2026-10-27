import { readFileSync } from "node:fs";
import { checkSource, projectRoot } from "./check.ts";
import { parseHandbook, type Rule, type Sample } from "./handbook.ts";

const root = projectRoot(import.meta.dir);
const markdown = readFileSync(new URL("../docs/misra-zig-handbook.md", import.meta.url), "utf8");
const book = parseHandbook(markdown);

function expected(side: "do" | "dont", sample: Sample): "accepted" | "rejected" {
    if (side === "do") return "accepted";
    return sample.before.trimStart().startsWith("**Rejected") ? "rejected" : "accepted";
}

function samplesOf(rule: Rule, side: "do" | "dont"): Sample[] {
    return rule[side]?.samples ?? [];
}

let failed = 0;
for (const rule of book.rules) {
    if (rule.kind === "note") continue;
    for (const side of ["do", "dont"] as const) {
        const samples = samplesOf(rule, side);
        for (let index = 0; index < samples.length; index++) {
            const sample = samples[index];
            if (!sample) continue;
            const want = expected(side, sample);
            const got = await checkSource(root, sample.code);
            const ok = got.status === want;
            if (!ok) {
                failed += 1;
                const first = got.output.split("\n")[0] ?? "";
                console.log(`${rule.id} ${side} ${index} want ${want} got ${got.status} ${first}`);
            }
        }
    }
}
if (failed > 0) {
    console.log(`${failed} samples differed`);
    process.exit(1);
}
console.log("samples match the handbook marks");
