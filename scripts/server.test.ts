import { afterAll, beforeAll, expect, test } from "bun:test";
import { join } from "node:path";
import { projectRoot } from "./check.ts";

const root = projectRoot(import.meta.dir);
const PORT = 4191;
const base = `http://127.0.0.1:${PORT}`;
const sample = JSON.stringify({ source: "fn f() void {}\n" });
let server: ReturnType<typeof Bun.spawn> | null = null;

beforeAll(async () => {
    server = Bun.spawn({
        cmd: ["bun", join(root, "scripts", "server.ts")],
        cwd: root,
        env: { ...process.env, PORT: String(PORT) },
        stdout: "pipe",
        stderr: "pipe",
    });
    // The server prints its address once misra-lint is built.
    const reader = (server.stdout as ReadableStream<Uint8Array>).getReader();
    let seen = "";
    while (!seen.includes("MISRA Zig at")) {
        const { value, done } = await reader.read();
        if (done) throw new Error(`server stopped: ${seen}`);
        seen += new TextDecoder().decode(value);
    }
    reader.releaseLock();
}, 300_000);

afterAll(() => {
    server?.kill();
});

function post(path: string, headers: Record<string, string>, body = sample): Promise<Response> {
    return fetch(`${base}${path}`, { method: "POST", headers, body });
}

test("the site's own JSON request is checked", async () => {
    const res = await post("/api/lint", { "content-type": "application/json", origin: base });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(Array.isArray(body.findings)).toBe(true);
    // The sample is a clean function, so the lint result must be exactly empty:
    // a non-array (null when misra-lint did not run) or a stray finding fails here.
    expect(body.findings).toEqual([]);
}, 120_000);

test("/api/check accepts a valid sample and rejects an invalid one", async () => {
    const good = await post("/api/check", { "content-type": "application/json", origin: base });
    expect(good.status).toBe(200);
    const goodBody = await good.json();
    expect(goodBody.status).toBe("accepted");
    expect(goodBody.errors).toEqual([]);
    expect(goodBody.findings).toEqual([]);

    const bad = await post("/api/check", { "content-type": "application/json", origin: base }, JSON.stringify({ source: "export fn f(n: u32) u32 {\n    if (n) return 1;\n    return 0;\n}\n" }));
    expect(bad.status).toBe(200);
    const badBody = await bad.json();
    expect(badBody.status).toBe("rejected");
    expect(badBody.errors.map((item: { line: number }) => item.line)).toEqual([2]);
}, 300_000);

test("a malformed request body is refused with a structured failure", async () => {
    const notJson = await post("/api/lint", { "content-type": "application/json", origin: base }, "not json");
    expect(notJson.status).toBe(400);
    const notJsonBody = await notJson.json();
    expect(notJsonBody.status).toBe("failed");

    const noSource = await post("/api/lint", { "content-type": "application/json", origin: base }, JSON.stringify({}));
    expect(noSource.status).toBe(400);
    const noSourceBody = await noSource.json();
    expect(noSourceBody.status).toBe("failed");
    // The two sides must give different reasons, not one generic failure.
    expect(noSourceBody.output).not.toBe(notJsonBody.output);
}, 120_000);

test("path traversal and static file serving", async () => {
    const traversal = await fetch(`${base}/../scripts/server.ts`);
    expect(traversal.status).toBe(404);
    const root = await fetch(`${base}/`);
    expect(root.status).toBe(200);
    expect(root.headers.get("content-type")).toContain("text/html");
    const health = await fetch(`${base}/api/health`);
    expect(health.status).toBe(200);
    const healthBody = await health.json();
    expect(healthBody.lint).toBe(true);
    expect(healthBody.zig).toBeTruthy();
}, 120_000);

test("a request from another origin is refused before any compile", async () => {
    const res = await post("/api/check", { "content-type": "application/json", origin: "http://evil.example" });
    expect(res.status).toBe(403);
});

test("a text/plain body, which skips the CORS preflight, is refused", async () => {
    const res = await post("/api/check", { "content-type": "text/plain" });
    expect(res.status).toBe(415);
});

test("a foreign Host header, as in DNS rebinding, is refused on every path", async () => {
    for (const path of ["/", "/rules.json", "/api/check"]) {
        const res = await fetch(`${base}${path}`, {
            method: path.startsWith("/api") ? "POST" : "GET",
            headers: { host: `attacker.example:${PORT}`, "content-type": "application/json" },
            body: path.startsWith("/api") ? sample : undefined,
        });
        expect({ path, status: res.status }).toEqual({ path, status: 421 });
    }
});

test("a body over the limit is refused", async () => {
    const huge = JSON.stringify({ source: "x".repeat(300 * 1024) });
    const res = await post("/api/check", { "content-type": "application/json" }, huge);
    expect(res.status).toBe(413);
});
