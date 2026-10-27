import { expect, test } from "bun:test";
import worker from "./worker.ts";

const env = {
    ASSETS: { fetch: async (request: Request) => new Response(`asset ${new URL(request.url).pathname}`) },
};

test("plain http is redirected to https with the path and query kept", async () => {
    const res = await worker.fetch(new Request("http://misra-zig.dev/rules.json?x=1"), env);
    expect(res.status).toBe(301);
    expect(res.headers.get("location")).toBe("https://misra-zig.dev/rules.json?x=1");
});

test("https is served from the static assets", async () => {
    const res = await worker.fetch(new Request("https://misra-zig.com/checks.json"), env);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("asset /checks.json");
});
