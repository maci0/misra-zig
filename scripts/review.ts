import { readFileSync } from "node:fs";
import { join } from "node:path";
import { projectRoot } from "./check.ts";
import { agentRules, parseHandbook } from "./handbook.ts";
import { buildLint, type CheckInfo, type Finding, lintChecks, lintSource } from "./lint.ts";

const USAGE = `usage: bun scripts/review.ts FILE...

Prints a MISRA Zig review skeleton in markdown: misra-lint findings grouped by
rule, then a reader checklist of every rule, split into rules no check decides
and rules a check decides only in part.
Exit 0: no finding. Exit 1: at least one finding. Exit 2: usage or read error.
`;

/** "rule-10-6" -> "Rule 10.6". */
function ruleLabel(id: string): string {
    const match = /^(dir|rule)-(\d+)-(\d+)$/.exec(id);
    if (!match) return id;
    return `${match[1] === "dir" ? "Dir" : "Rule"} ${match[2]}.${match[3]}`;
}

function firstSentence(text: string): string {
    const flat = text.replace(/\s+/g, " ").trim();
    return flat.split(/(?<=\.)\s/)[0] ?? flat;
}

export type Reviewed = {
    path: string;
    findings: Finding[];
};

/** The review skeleton for already linted files. Pure, so tests can drive it. */
export function renderReview(files: Reviewed[], checks: CheckInfo[], markdown: string): string {
    const rules = agentRules(parseHandbook(markdown)).rules;
    const decided = new Set(checks.flatMap((check) => check.rules));
    const out: string[] = [`# MISRA Zig review`, "", `Files: ${files.map((file) => `\`${file.path}\``).join(", ")}`, ""];
    const all = files.flatMap((file) => file.findings.map((finding) => ({ path: file.path, finding })));
    out.push(`## misra-lint findings (${all.length})`, "");
    if (all.length === 0) out.push("misra-lint reported nothing. That is not compliance: read the checklist below.", "");
    const parse = all.filter((item) => item.finding.check === "parse_error");
    for (const item of parse) {
        out.push(`- \`${item.path}:${item.finding.line}:${item.finding.column}\` parse error: ${item.finding.subject}. No check ran on this file.`);
    }
    if (parse.length) out.push("");
    for (const rule of rules) {
        const hits = all.filter((item) => item.finding.rules.includes(rule.id));
        if (hits.length === 0) continue;
        out.push(`### ${ruleLabel(rule.id)}: ${firstSentence(rule.obligation)}`, "");
        for (const { path, finding } of hits) {
            const subject = finding.subject ? ` (${finding.subject})` : "";
            out.push(`- \`${path}:${finding.line}:${finding.column}\` ${finding.severity} \`${finding.check}\`: ${finding.message}${subject}`);
        }
        out.push("");
    }
    out.push("## Reader checklist", "", "No check decides these rules. Read every file for each one.", "");
    for (const rule of rules.filter((item) => !decided.has(item.id))) {
        out.push(`- [ ] ${ruleLabel(rule.id)}: ${firstSentence(rule.obligation)}`);
    }
    out.push("", "misra-lint decides these only in part. Read for what the listed checks do not see.", "");
    for (const rule of rules.filter((item) => decided.has(item.id))) {
        const names = checks.filter((check) => check.rules.includes(rule.id)).map((check) => `\`${check.id}\``);
        out.push(`- [ ] ${ruleLabel(rule.id)}: ${firstSentence(rule.obligation)} Checked by ${names.join(", ")}.`);
    }
    out.push("");
    return out.join("\n");
}

if (import.meta.main) {
    const paths = Bun.argv.slice(2);
    if (paths.length === 0 || paths.some((path) => path === "-h" || path === "--help")) {
        process.stdout.write(USAGE);
        process.exit(paths.length === 0 ? 2 : 0);
    }
    const root = projectRoot(import.meta.dir);
    const files: Reviewed[] = [];
    let bin = "";
    try {
        bin = await buildLint(root);
        for (const path of paths) files.push({ path, findings: await lintSource(bin, readFileSync(path, "utf8")) });
    } catch (err) {
        process.stderr.write(`review: ${err instanceof Error ? err.message : String(err)}\n`);
        process.exit(2);
    }
    const markdown = readFileSync(join(root, "docs", "misra-zig-handbook.md"), "utf8");
    process.stdout.write(renderReview(files, await lintChecks(bin), markdown));
    process.exit(files.some((file) => file.findings.length > 0) ? 1 : 0);
}
