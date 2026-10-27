import { cpSync, mkdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { projectRoot } from "./check.ts";
import { agentRules, parseHandbook } from "./handbook.ts";
import { buildLint, lintChecks } from "./lint.ts";

/**
 * Writes the public site to build/site: the static pages plus the JSON the page
 * loads. Check needs a compiler on the machine that serves it, so the public
 * copy answers /api/health with lint unavailable and every other /api request
 * fails the way an unreachable checker does.
 */

const PUBLIC_NOTICE =
    "The checker runs on a local server only. From a clone of the repo, run bun scripts/server.ts.";

const root = projectRoot(import.meta.dir);
const out = join(root, "build", "site");
const handbookPath = join(root, "docs", "misra-zig-handbook.md");

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
cpSync(join(root, "site"), out, { recursive: true });

const markdown = await Bun.file(handbookPath).text();
const book = parseHandbook(markdown);
writeFileSync(join(out, "handbook.json"), JSON.stringify(book));
writeFileSync(join(out, "rules.json"), `${JSON.stringify(agentRules(book), null, 2)}\n`);

const bin = await buildLint(root);
writeFileSync(join(out, "checks.json"), `${JSON.stringify(await lintChecks(bin), null, 2)}\n`);

// No file extension: the page reads it with res.json(), which ignores the content type.
mkdirSync(join(out, "api"), { recursive: true });
const revised = statSync(handbookPath).mtime.toISOString().slice(0, 10);
writeFileSync(
    join(out, "api", "health"),
    JSON.stringify({ zig: "", lint: false, lintProblem: PUBLIC_NOTICE, revised }),
);

console.log(`built ${out}`);
