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
    expect(Array.isArray((await res.json()).findings)).toBe(true);
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
