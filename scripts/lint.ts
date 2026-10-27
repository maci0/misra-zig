import { mkdirSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import { wrapSource, zigCommand } from "./check.ts";

export type Severity = "violation" | "review";

export type Finding = {
    check: string;
    severity: Severity;
    rules: string[];
    line: number;
    column: number;
    message: string;
    subject: string;
};

export type CheckInfo = {
    id: string;
    severity: Severity;
    rules: string[];
    summary: string;
};

const LINT_TIMEOUT_MS = 10_000;
const BUILD_TIMEOUT_MS = 300_000;

/**
 * Builds tools/misra_lint.zig into .scratch/bin and returns the binary path. Zig's cache makes a rebuild cheap.
 * Each build writes its own file and renames it into place, so a server and a test run that build at
 * the same time never execute a half-written binary.
 */
export async function buildLint(root: string): Promise<string> {
    const bin = join(root, ".scratch", "bin", "misra-lint");
    const staged = `${bin}.${Bun.randomUUIDv7()}.tmp`;
    mkdirSync(join(root, ".scratch", "bin"), { recursive: true });
    const proc = Bun.spawn({
        cmd: [zigCommand(), "build-exe", "-ODebug", "tools/misra_lint.zig", `-femit-bin=${staged}`],
        cwd: root,
        stdout: "pipe",
        stderr: "pipe",
        timeout: BUILD_TIMEOUT_MS,
        killSignal: "SIGKILL",
    });
    const [out, err] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
    if ((await proc.exited) !== 0) {
        rmSync(staged, { force: true });
        throw new Error(`misra-lint did not build:\n${out}${err}`);
    }
    renameSync(staged, bin);
    return bin;
}

async function runLint(bin: string, args: string[], stdin: string): Promise<string> {
    const proc = Bun.spawn({
        cmd: [bin, ...args],
        stdin: new TextEncoder().encode(stdin),
        stdout: "pipe",
        stderr: "pipe",
        timeout: LINT_TIMEOUT_MS,
        killSignal: "SIGKILL",
    });
    const [out, err] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
    const code = await proc.exited;
    if (proc.signalCode) throw new Error(`misra-lint was stopped by ${proc.signalCode}`);
    if (code !== 0 && code !== 1) throw new Error(`misra-lint exited ${code}: ${err.trim()}`);
    return out;
}

/** Lints one source text. Lines and columns are 1-based in that text. */
export async function lintSource(bin: string, source: string): Promise<Finding[]> {
    const out = await runLint(bin, ["--json", "-"], source);
    const parsed = JSON.parse(out) as { files: { findings: Finding[] }[] };
    return parsed.files[0]?.findings ?? [];
}

export async function lintChecks(bin: string): Promise<CheckInfo[]> {
    return JSON.parse(await runLint(bin, ["--checks", "--json"], "")) as CheckInfo[];
}

/** Lints an editor sample the way the compiler sees it, and reports lines in the sample. */
export async function lintSample(bin: string, source: string): Promise<Finding[]> {
    const wrapped = wrapSource(source);
    const last = wrapped.firstLine + source.replace(/\n$/, "").split("\n").length - 1;
    const findings = await lintSource(bin, wrapped.text);
    return findings
        .filter((item) => item.line >= wrapped.firstLine && item.line <= last)
        .map((item) => ({ ...item, line: item.line - wrapped.firstLine + 1 }));
}
