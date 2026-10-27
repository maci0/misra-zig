import { existsSync, readFileSync, statSync } from "node:fs";
import { join, normalize, sep } from "node:path";
import { checkSource, compileLimitFromEnv, MAX_SOURCE_BYTES, projectRoot, sourceBytes, zigCommand, zigVersion } from "./check.ts";
import { agentRules, parseHandbook } from "./handbook.ts";
import { buildLint, type CheckInfo, type Finding, lintChecks, lintSample } from "./lint.ts";

const root = projectRoot(import.meta.dir);
const site = join(root, "site");
const handbookPath = join(root, "docs", "misra-zig-handbook.md");

const types: Record<string, string> = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".ttf": "font/ttf",
    ".woff2": "font/woff2",
    ".txt": "text/plain; charset=utf-8",
    ".md": "text/plain; charset=utf-8",
};

const fresh = { "cache-control": "no-store" };

function contentType(path: string): string {
    const dot = path.lastIndexOf(".");
    const ext = dot === -1 ? "" : path.slice(dot);
    return types[ext] ?? "application/octet-stream";
}

function siteFile(pathname: string): string | null {
    let rel = pathname;
    try {
        rel = decodeURIComponent(pathname);
    } catch {
        // A malformed escape is not a file name.
        return null;
    }
    if (rel.includes("\0")) return null;
    const full = normalize(join(site, rel));
    if (full !== site && !full.startsWith(site + sep)) return null;
    return full;
}

function json(text: string): Response {
    return new Response(text, { headers: { "content-type": "application/json; charset=utf-8", ...fresh } });
}

function handbook() {
    return parseHandbook(readFileSync(handbookPath, "utf8"));
}

const port = Number(process.env.PORT ?? 4173);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("PORT must be an integer from 1 to 65535");
}

/** A request body larger than this is refused before it is read. */
const MAX_BODY_BYTES = 256 * 1024;

// Only this machine's own page may use the API. A Host check stops DNS rebinding,
// an Origin check stops other sites, and the JSON content type forces a CORS
// preflight that this server never answers.
const allowedHosts = new Set([`127.0.0.1:${port}`, `localhost:${port}`]);
const allowedOrigins = new Set([...allowedHosts].map((host) => `http://${host}`));

function refusal(req: Request): Response | null {
    if (!allowedHosts.has(req.headers.get("host") ?? "")) return new Response("Unknown host.", { status: 421 });
    if (req.method !== "POST") return null;
    const origin = req.headers.get("origin");
    if (origin !== null && !allowedOrigins.has(origin)) return new Response("Cross-origin requests are refused.", { status: 403 });
    if (!(req.headers.get("content-type") ?? "").startsWith("application/json")) {
        return new Response("Send application/json.", { status: 415 });
    }
    return null;
}

// One compile at a time: each check queues behind the one before it.
let compiling: Promise<unknown> = Promise.resolve();

function oneAtATime<T>(task: () => Promise<T>): Promise<T> {
    const run = compiling.then(task, task);
    compiling = run.catch(() => undefined);
    return run;
}

const compileLimit = compileLimitFromEnv(process.env.MISRA_ZIG_COMPILE_LIMIT);
if (!Bun.which("prlimit")) throw new Error("prlimit (util-linux) is required to cap compiler memory; it is not on PATH");

const version = await zigVersion(zigCommand());
if (version) {
    // The first compile builds libc into the cache and needs far more memory than a sample;
    // it runs once here, uncapped, so that every capped check after it starts warm.
    const warm = await checkSource(root, "fn warm() void {}\n");
    if (warm.status !== "accepted") console.error(`cache warm-up failed: ${warm.output}`);
}

let lintBin: string | null = null;
let checks: CheckInfo[] = [];
let lintProblem = "";
if (version) {
    try {
        lintBin = await buildLint(root);
        checks = await lintChecks(lintBin);
    } catch (err) {
        lintProblem = err instanceof Error ? err.message : "misra-lint did not build.";
        console.error(lintProblem);
    }
} else {
    lintProblem = "Zig is not on PATH, so misra-lint was not built.";
}

async function sourceOf(req: Request): Promise<string | Response> {
    if (req.method !== "POST") return new Response("POST a sample.", { status: 405 });
    let body: unknown;
    try {
        body = await req.json();
    } catch {
        // The body is not JSON; say so instead of echoing the parser's message.
        return Response.json({ status: "failed", output: "The request was not JSON." }, { status: 400 });
    }
    const source = typeof body === "object" && body !== null && "source" in body ? body.source : undefined;
    if (typeof source !== "string") {
        return Response.json({ status: "failed", output: "The request needs a source string." }, { status: 400 });
    }
    return source;
}

async function findingsFor(source: string): Promise<Finding[] | null> {
    if (!lintBin || source.trim().length === 0 || sourceBytes(source) > MAX_SOURCE_BYTES) return null;
    try {
        return await lintSample(lintBin, source);
    } catch (err) {
        console.error(err instanceof Error ? err.message : err);
        return null;
    }
}

Bun.serve({
    port,
    hostname: "127.0.0.1",
    development: false,
    maxRequestBodySize: MAX_BODY_BYTES,
    error(err) {
        // The detail goes to the server log only; the page gets no stack or path.
        console.error(err);
        return new Response("Internal error. The server log has the detail.", { status: 500 });
    },
    async fetch(req) {
        const refused = refusal(req);
        if (refused) return refused;
        const url = new URL(req.url);
        if (url.pathname === "/api/health") {
            const revised = statSync(handbookPath).mtime.toISOString().slice(0, 10);
            return Response.json({ zig: version, lint: lintBin !== null, lintProblem, revised, compileLimit });
        }
        if (url.pathname === "/handbook.json") return json(JSON.stringify(handbook()));
        if (url.pathname === "/rules.json") return json(`${JSON.stringify(agentRules(handbook()), null, 2)}\n`);
        if (url.pathname === "/checks.json") return json(`${JSON.stringify(checks, null, 2)}\n`);
        if (url.pathname === "/api/check") {
            const source = await sourceOf(req);
            if (source instanceof Response) return source;
            const [result, findings] = await Promise.all([oneAtATime(() => checkSource(root, source, compileLimit)), findingsFor(source)]);
            return Response.json({ ...result, findings });
        }
        if (url.pathname === "/api/lint") {
            const source = await sourceOf(req);
            if (source instanceof Response) return source;
            return Response.json({ findings: await findingsFor(source) });
        }
        const path = url.pathname === "/" ? "/index.html" : url.pathname;
        const file = siteFile(path);
        if (!file || !existsSync(file) || !statSync(file).isFile()) {
            return new Response("Not found.", { status: 404 });
        }
        return new Response(Bun.file(file), { headers: { "content-type": contentType(file), ...fresh } });
    },
});

console.log(`MISRA Zig at http://127.0.0.1:${port} (zig ${version || "not on PATH"}, ${checks.length} lint checks)`);
