/**
 * The published site's Worker: a plain HTTP request gets a 301 to the same URL on
 * HTTPS, and every other request is served from the static assets.
 *
 * ponytail: run_worker_first sends every request through here, so each one counts
 * against the Workers request quota (static assets alone are free). The zone setting
 * "Always Use HTTPS" on both domains does the same redirect without a Worker; the
 * deploy login cannot change zone settings.
 */

type Env = {
    ASSETS: { fetch(request: Request): Promise<Response> };
};

export default {
    fetch(request: Request, env: Env): Response | Promise<Response> {
        const url = new URL(request.url);
        if (url.protocol !== "http:") return env.ASSETS.fetch(request);
        url.protocol = "https:";
        return Response.redirect(url.toString(), 301);
    },
};
