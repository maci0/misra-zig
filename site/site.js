const KEYWORDS = new Set(`
addrspace align allowzero and anyframe anytype asm break callconv catch comptime
const continue defer else enum errdefer error export extern fn for if inline
linksection noalias nosuspend noinline opaque or orelse packed pub resume return
struct suspend switch test threadlocal try union unreachable var volatile while
bool f16 f32 f64 f128 void noreturn type anyerror anyopaque comptime_int comptime_float
i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize
c_char c_short c_ushort c_int c_uint c_long c_ulong c_longlong c_ulonglong c_longdouble
true false null undefined
`.split(/\s+/).filter(Boolean));

const LAST_KEY = "misra-zig-last";
const BENCH_KEY = "misra-zig-bench";
const THEME_KEY = "misra-zig-theme";
const MIN_EDITOR_LINES = 3;
const BENCH_LINES = 24;

const BENCH_EXAMPLE = `// Example file: each declaration below breaks one MISRA Zig rule.
const std = @import("std");

pub const max_items = 64;

const Packet = extern struct {
    kind: u8,
    len: usize,
};

/// Caller owns the returned slice.
fn readPacket(allocator: std.mem.Allocator, dir: std.Io.Dir, io: std.Io, name: []const u8) ![]u8 {
    const file = try dir.openFile(io, name, .{});
    const buf = try allocator.alloc(u8, max_items);
    defer file.close(io);
    _ = try file.readStreaming(io, &.{buf});
    return buf;
}

fn checksum(data: []u8) u8 {
    var sum: u8 = 0;
    for (data) |b| sum +%= b;
    return sum;
}

fn total(a: u16, b: u16) u32 {
    return a + b;
}

fn armed(ready: bool, set: bool, forced: bool) bool {
    return ready and set or forced;
}

fn depth(n: u32) u32 {
    if (n == 0) return 0;
    return 1 + depth(n - 1);
}

fn dispatch(code: u8) void {
    switch (code) {
        1 => {},
        else => {},
    }
}
`;

const state = {
    book: null,
    agent: null,
    checks: [],
    health: { zig: "", lint: false, lintProblem: "" },
    id: "reading",
    editing: null,
    drafts: new Map(),
    lintCache: new Map(),
};

const main = document.getElementById("sheet");
const searchBox = document.getElementById("q");
const hitsBox = document.getElementById("hits");
const themeButton = document.getElementById("theme");

function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function stored(key) {
    try {
        return localStorage.getItem(key);
    } catch {
        // Storage disabled: nothing was stored.
        return null;
    }
}

function store(key, value) {
    try {
        if (value === null) localStorage.removeItem(key);
        else localStorage.setItem(key, value);
    } catch {
        // Storage disabled: the choice lasts until the page closes.
    }
}

/* Zig highlighting. Zig has no multi-line comment, so one line is always a whole set of tokens. */

function span(cls, text) {
    return `<span class="${cls}">${escapeHtml(text)}</span>`;
}

function highlight(src) {
    let i = 0;
    let html = "";
    const n = src.length;
    while (i < n) {
        if (src.startsWith("//", i)) {
            const end = src.indexOf("\n", i);
            const j = end === -1 ? n : end;
            html += span("cmt", src.slice(i, j));
            i = j;
            continue;
        }
        const c = src[i];
        if (c === '"' || c === "'") {
            let j = i + 1;
            while (j < n && src[j] !== c && src[j] !== "\n") j += src[j] === "\\" ? 2 : 1;
            if (src[j] === c) j += 1;
            html += span("str", src.slice(i, j));
            i = j;
            continue;
        }
        if (c === "\\" && src[i + 1] === "\\") {
            const end = src.indexOf("\n", i);
            const j = end === -1 ? n : end;
            html += span("str", src.slice(i, j));
            i = j;
            continue;
        }
        if (c === "@") {
            let j = i + 1;
            while (j < n && /[A-Za-z0-9_]/.test(src[j])) j += 1;
            html += span("blt", src.slice(i, j));
            i = j;
            continue;
        }
        if (/[0-9]/.test(c)) {
            let j = i;
            if (c === "0" && /[xXoObB]/.test(src[i + 1] || "")) {
                j = i + 2;
                while (j < n && /[0-9a-fA-F_]/.test(src[j])) j += 1;
            } else {
                while (j < n && /[0-9_]/.test(src[j])) j += 1;
                if (src[j] === "." && /[0-9]/.test(src[j + 1] || "")) {
                    j += 1;
                    while (j < n && /[0-9_]/.test(src[j])) j += 1;
                }
            }
            html += span("num", src.slice(i, j));
            i = j;
            continue;
        }
        if (/[A-Za-z_]/.test(c)) {
            let j = i + 1;
            while (j < n && /[A-Za-z0-9_]/.test(src[j])) j += 1;
            const word = src.slice(i, j);
            html += KEYWORDS.has(word) ? span("kw", word) : escapeHtml(word);
            i = j;
            continue;
        }
        html += escapeHtml(c);
        i += 1;
    }
    return html;
}

/* Handbook prose. */

function inline(text) {
    return escapeHtml(text)
        .replace(/`([^`]+)`/g, "<code>$1</code>")
        .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
        .replace(/Dir (\d+\.\d+)/g, (_, n) => `<a href="#dir-${n.replace(".", "-")}">Dir ${n}</a>`)
        .replace(/Rule (\d+\.\d+)/g, (_, n) => `<a href="#rule-${n.replace(".", "-")}">Rule ${n}</a>`);
}

function prose(text) {
    if (!text.trim()) return "";
    return text
        .trim()
        .split(/\n\n+/)
        .map((block) => {
            const lines = block.split("\n");
            if (lines.every((line) => line.startsWith("- "))) {
                return `<ul>${lines.map((line) => `<li>${inline(line.slice(2))}</li>`).join("")}</ul>`;
            }
            return `<p>${inline(lines.join(" "))}</p>`;
        })
        .join("");
}

function renderRich(text) {
    const re = /```([a-z]*)\n([\s\S]*?)```/g;
    let html = "";
    let last = 0;
    let match;
    while ((match = re.exec(text))) {
        html += prose(text.slice(last, match.index));
        const code = match[2].replace(/\n$/, "");
        html += match[1] === "zig"
            ? `<figure class="fig"><pre>${highlight(code)}</pre></figure>`
            : `<pre class="plain">${escapeHtml(code)}</pre>`;
        last = match.index + match[0].length;
    }
    return html + prose(text.slice(last));
}

function plain(text) {
    return text.replace(/`([^`]*)`/g, "$1").replace(/\*\*([^*]*)\*\*/g, "$1");
}

/* The pin order: the groups in handbook order, then the compiler note. */

function ruleById(id) {
    return state.book.rules.find((rule) => rule.id === id) ?? null;
}

function groupOf(id) {
    return state.book.groups.find((group) => group.ids.includes(id)) ?? null;
}

function pins() {
    return state.book.groups.flatMap((group) => group.ids);
}

function pinNo(id) {
    return pins().indexOf(id) + 1;
}

function pinName(rule) {
    if (rule.kind === "dir") return `D${rule.number}`;
    if (rule.kind === "rule") return `R${rule.number}`;
    return "ZIG";
}

function label(rule) {
    if (rule.kind === "dir") return `Dir ${rule.number}`;
    if (rule.kind === "rule") return `Rule ${rule.number}`;
    return rule.heading;
}

function checksFor(id) {
    return state.checks.filter((check) => check.rules.includes(id));
}

function ruleLabel(id) {
    const rule = ruleById(id);
    return rule ? label(rule) : id;
}

/** A check id that may break after each underscore. */
function idHtml(id) {
    return escapeHtml(id).replaceAll("_", "_<wbr>");
}

function shape(kind) {
    return `<span class="shape ${kind}" aria-hidden="true"></span>`;
}

/* Pin map: a dual in-line package, pin 1 at the top left, counting down the left side and up the right.
   A package has an even pin count, so an odd number of rules leaves the last pin NC (no connection). */

const PIN_PITCH = 17;
const BODY_LEFT = 164;
const BODY_RIGHT = 284;
const BODY_TOP = 10;

function pinY(row) {
    return BODY_TOP + 12 + row * PIN_PITCH + PIN_PITCH / 2;
}

function pinMap(resume, lit = null) {
    const ids = pins();
    const perSide = Math.ceil(ids.length / 2);
    const height = BODY_TOP * 2 + 24 + perSide * PIN_PITCH;
    const bodyHeight = height - BODY_TOP * 2;
    let out = `<svg viewBox="0 0 448 ${height}" role="group" aria-label="Pin map of MZ-0.17: one pin per rule">`;
    out += `<rect class="pkg" x="${BODY_LEFT}" y="${BODY_TOP}" width="${BODY_RIGHT - BODY_LEFT}" height="${bodyHeight}"/>`;
    const mid = (BODY_LEFT + BODY_RIGHT) / 2;
    out += `<path class="notch" d="M ${mid - 12} ${BODY_TOP} A 12 12 0 0 0 ${mid + 12} ${BODY_TOP}"/>`;
    out += `<circle class="dot" cx="${BODY_LEFT + 30}" cy="${BODY_TOP + 16}" r="3"/>`;
    out += `<text class="pkg-name" x="${mid}" y="${BODY_TOP + bodyHeight / 2}" text-anchor="middle" transform="rotate(-90 ${mid} ${BODY_TOP + bodyHeight / 2})">MZ-0.17</text>`;
    out += `<text class="pkg-sub" x="${mid + 22}" y="${BODY_TOP + bodyHeight / 2}" text-anchor="middle" transform="rotate(-90 ${mid + 22} ${BODY_TOP + bodyHeight / 2})">ZIG ${escapeHtml(state.health.zig || "0.17")}</text>`;
    const rowOf = (n) => (n <= perSide ? n - 1 : perSide * 2 - n);
    ids.forEach((id, index) => {
        const rule = ruleById(id);
        if (!rule) return;
        const n = index + 1;
        const left = n <= perSide;
        const y = pinY(rowOf(n));
        const legX = left ? BODY_LEFT - 14 : BODY_RIGHT;
        const noX = left ? BODY_LEFT + 7 : BODY_RIGHT - 7;
        const nameX = left ? BODY_LEFT - 19 : BODY_RIGHT + 19;
        const anchor = left ? "end" : "start";
        const hitX = left ? BODY_LEFT - 66 : BODY_RIGHT;
        const cls = `pin-g ${left ? "pin-left" : "pin-right"}${id === resume ? " resume" : ""}${id === lit ? " on" : ""}`;
        out += `<a class="${cls}" href="#${id}" data-pin="${id}" aria-label="Pin ${n}, ${escapeHtml(label(rule))}">`;
        out += `<rect class="hit" x="${hitX}" y="${y - PIN_PITCH / 2}" width="66" height="${PIN_PITCH}"/>`;
        out += `<rect class="leg" x="${legX}" y="${y - 2.5}" width="14" height="5"/>`;
        out += `<text class="pin-no" x="${noX}" y="${y + 3}" text-anchor="${left ? "start" : "end"}">${n}</text>`;
        out += `<text class="pin-name" x="${nameX}" y="${y + 4}" text-anchor="${anchor}">${escapeHtml(pinName(rule))}</text>`;
        out += "</a>";
    });
    if (ids.length % 2 === 1) {
        const y = pinY(0);
        out += `<g class="nc"><rect class="leg" x="${BODY_RIGHT}" y="${y - 2.5}" width="14" height="5"/><text class="pin-no" x="${BODY_RIGHT - 7}" y="${y + 3}" text-anchor="end">${perSide * 2}</text><text class="pin-name" x="${BODY_RIGHT + 19}" y="${y + 4}">NC</text></g>`;
    }
    state.book.groups.forEach((group, gi) => {
        if (group.ids.includes("compiler")) return;
        const numbers = group.ids.map((id) => pinNo(id));
        const sides = [numbers.filter((n) => n <= perSide), numbers.filter((n) => n > perSide)];
        const word = group.title.split(/[ ,]/)[0].toUpperCase();
        out += `<g class="grp${lit && group.ids.includes(lit) ? " on" : ""}" data-group="${gi}">`;
        sides.forEach((side, s) => {
            if (side.length === 0) return;
            const rows = side.map(rowOf);
            const top = pinY(Math.min(...rows)) - PIN_PITCH / 2 + 2;
            const bottom = pinY(Math.max(...rows)) + PIN_PITCH / 2 - 2;
            const x = s === 0 ? 96 : 352;
            const tick = s === 0 ? 5 : -5;
            out += `<path class="bracket" d="M ${x + tick} ${top} H ${x} V ${bottom} H ${x + tick}"/>`;
            const cy = (top + bottom) / 2;
            const lx = s === 0 ? x - 8 : x + 8;
            const turn = s === 0 ? -90 : 90;
            out += `<text class="bracket-label" x="${lx}" y="${cy}" text-anchor="middle" transform="rotate(${turn} ${lx} ${cy})">${escapeHtml(word)}</text>`;
        });
        out += "</g>";
    });
    return `${out}</svg>`;
}

function wirePinMap() {
    const table = main.querySelector("[data-pins]");
    const svg = main.querySelector(".pinmap svg");
    if (!table || !svg) return;
    const light = (id, on) => {
        const group = state.book.groups.findIndex((item) => item.ids.includes(id));
        svg.querySelector(`[data-pin="${id}"]`)?.classList.toggle("on", on);
        svg.querySelector(`.grp[data-group="${group}"]`)?.classList.toggle("on", on);
        table.querySelector(`tr[data-row="${id}"]`)?.classList.toggle("on", on);
    };
    const bind = (el, id) => {
        el.addEventListener("pointerenter", () => light(id, true));
        el.addEventListener("pointerleave", () => light(id, false));
        el.addEventListener("focusin", () => light(id, true));
        el.addEventListener("focusout", () => light(id, false));
    };
    for (const pin of svg.querySelectorAll("[data-pin]")) bind(pin, pin.dataset.pin);
    for (const row of table.querySelectorAll("tr[data-row]")) bind(row, row.dataset.row);
}

/* Sheets. */

function sec(n, title, body, extra = "") {
    return `<section class="sec"${extra}><h2><span class="n">${n}</span> ${escapeHtml(title)}</h2>${body}</section>`;
}

function renderFront() {
    const reading = ruleById("reading");
    const rules = state.book.rules.filter((rule) => rule.kind !== "note");
    const dirs = rules.filter((rule) => rule.kind === "dir").length;
    const decided = new Set(state.checks.flatMap((check) => check.rules));
    const decidedCount = rules.filter((rule) => decided.has(rule.id)).length;
    const checkCount = state.checks.filter((check) => check.id !== "parse_error").length;
    const features = [
        `${dirs} directives and ${rules.length - dirs} rules in ${state.book.groups.length - 1} groups, each stated as a Zig obligation`,
        "A do and a don't for every rule. Every don't is marked rejected by Zig, or compiles and is still wrong",
        state.health.lint
            ? `${checkCount} misra-lint checks decide ${decidedCount} of the ${rules.length} rules from the syntax tree`
            : `misra-lint is not built on this server: ${state.health.lintProblem || "unknown reason"}`,
        state.health.zig
            ? `Every sample editable and checked with Zig ${state.health.zig} on this machine`
            : "Zig was not found, so Check cannot compile",
        "The same rules as fields at rules.json, and the checks at checks.json",
    ];
    const last = stored(LAST_KEY);
    const lastRule = last ? ruleById(last) : null;
    const resume = lastRule
        ? `<p class="resume"><span class="flag" aria-hidden="true"></span><span>You stopped at ${escapeHtml(label(lastRule))}, ${escapeHtml(groupOf(lastRule.id)?.title ?? "")}.</span><a href="#${lastRule.id}">Resume at ${escapeHtml(label(lastRule))}</a></p>`
        : "";
    const rows = state.book.groups
        .map((group) => {
            const first = pinNo(group.ids[0]);
            const last = pinNo(group.ids.at(-1));
            const span = first === last ? `pin ${first}` : `pins ${first} to ${last}`;
            const head = `<tr class="grp-row"><th colspan="4" scope="rowgroup">${escapeHtml(group.title)}<span>${span}</span></th></tr>`;
            const body = group.ids
                .map((id) => {
                    const rule = ruleById(id);
                    if (!rule) return "";
                    const desc = rule.kind === "note" ? group.blurb : plain(rule.short);
                    return `<tr data-row="${id}"><td class="tnum">${pinNo(id)}</td><td><a class="pin-link" href="#${id}">${escapeHtml(pinName(rule))}</a></td><td>${escapeHtml(desc)}</td><td class="tnum">${rule.kind === "note" ? "" : checksFor(id).length}</td></tr>`;
                })
                .join("");
            return head + body;
        })
        .join("");
    document.title = "MISRA Zig: MZ-0.17 coding standard for Zig";
    main.className = "front";
    main.innerHTML = `
<div class="part"><p class="part-num">MZ-0.17</p><div><h1 class="part-title">MISRA Zig: a coding standard for Zig 0.17, inspired by MISRA C</h1><p class="part-side">Rules applied to Zig as it is. Read the obligation, compare the source, check it.</p></div></div>
${resume}
<div class="cols">
${sec("1", "Features", `<ul class="features">${features.map((item) => `<li>${inline(item)}</li>`).join("")}</ul>`)}
${sec("2", "Description", `<div class="prose"><p>Code has to stay defined after safety checks are removed. ReleaseFast and ReleaseSmall delete the checks that Debug and ReleaseSafe insert. A panic in Debug is not a pass.</p><p>The named directives and rules are the whole of this standard, numbered as in MISRA C:2025. The wording is the Zig obligation, not the text of MISRA C. A file the compiler accepts, or misra-lint passes, can still break a rule.</p></div>`)}
</div>
${sec("3", "Pin configuration and functions", `<div class="pinout"><figure class="pinmap"><div class="pin-scroll">${pinMap(last)}</div><figcaption><b>Figure 3-1.</b> One pin per rule. Each side bracket is a group.<span class="scroll-hint">Scroll the figure sideways for the group names on the right side.</span></figcaption></figure><div class="tablewrap"><table class="spec" data-pins><caption><b>Table 3-1.</b> Pin functions</caption><thead><tr><th class="tnum">Pin</th><th>Name</th><th>Function</th><th class="tnum">Checks</th></tr></thead><tbody>${rows}</tbody></table></div></div>`, ' id="pins"')}
${sec("4", "Detailed description: how a sample is marked", `<div class="prose">${reading ? renderRich(reading.intro) : ""}</div>`)}
${sec("5", "Evaluation", `<div class="prose"><p>Paste a whole Zig file to compile it and run every misra-lint check on it. Findings link to the rule they break.</p></div><p><a class="act" href="#playground">Evaluate a file</a></p>`)}`;
    wirePinMap();
}

function lintEvidence(code) {
    if (!state.health.lint) return Promise.resolve(null);
    if (!state.lintCache.has(code)) {
        state.lintCache.set(
            code,
            fetch("/api/lint", {
                method: "POST",
                headers: { "content-type": "application/json" },
                body: JSON.stringify({ source: code }),
            })
                .then((res) => (res.ok ? res.json() : { findings: null }))
                .then((body) => body.findings)
                .catch(() => null),
        );
    }
    return state.lintCache.get(code);
}

function figure(code, caption, key) {
    const editing = state.editing === key;
    if (editing) {
        return `<div class="fig" data-fig="${key}"><div class="bench" data-bench="${key}"></div><figcaption><b>${escapeHtml(caption)}</b> Editing. Tab indents; Esc then Tab leaves the editor.</figcaption></div>`;
    }
    return `<figure class="fig" data-fig="${key}"><pre>${highlight(code)}</pre><figcaption><b>${escapeHtml(caption)}</b><button type="button" class="quiet act-edit" data-edit="${key}">Edit and check</button></figcaption></figure>`;
}

function renderRule(rule) {
    const group = groupOf(rule.id);
    const order = pins();
    const at = order.indexOf(rule.id);
    const prev = at > 0 ? ruleById(order[at - 1]) : null;
    const next = at < order.length - 1 ? ruleById(order[at + 1]) : null;
    store(LAST_KEY, rule.id);
    document.title = `${label(rule)}: MISRA Zig`;
    main.className = "rule";
    const pager = `<nav class="pager" aria-label="Previous and next rule">${prev ? `<a class="prev" href="#${prev.id}" rel="prev"><small>Previous, pin ${pinNo(prev.id)}</small><span class="pager-name">${escapeHtml(label(prev))}</span></a>` : "<span></span>"}${next ? `<a class="next" href="#${next.id}" rel="next"><small>Next, pin ${pinNo(next.id)}</small><span class="pager-name">${escapeHtml(label(next))}</span></a>` : "<span></span>"}</nav>`;
    if (rule.kind === "note") {
        main.innerHTML = `<div class="part"><p class="part-num"><span class="kind">Pin</span> ${pinNo(rule.id)}</p><div><h1 class="part-title">${escapeHtml(rule.heading)}</h1><p class="part-side">${escapeHtml(group?.title ?? "")}</p></div></div>${sec("1", "Description", `<div class="prose">${renderRich(rule.intro)}</div>`)}${pager}`;
        return;
    }
    const kind = rule.kind === "dir" ? "Dir" : "Rule";
    const record = (state.agent?.rules ?? []).find((item) => item.id === rule.id);
    const checks = checksFor(rule.id);
    const doSide = rule.do ?? { samples: [], after: "" };
    const dontSide = rule.dont ?? { samples: [], after: "" };
    let fig = 0;
    const doBody =
        doSide.samples
            .map((sample, index) => {
                fig += 1;
                const note = sample.before ? `<div class="note">${renderRich(sample.before)}</div>` : "";
                return `${note}${figure(state.drafts.get(`do-${index}`) ?? sample.code, `Figure 2-${fig}. Compliant source`, `do-${index}`)}`;
            })
            .join("") + (doSide.after ? `<div class="prose">${renderRich(doSide.after)}</div>` : "");
    let dfig = 0;
    const dontBody =
        dontSide.samples
            .map((sample, index) => {
                const rejected = sample.before.trimStart().startsWith("**Rejected");
                dfig += 1;
                const markHtml = rejected
                    ? `<span class="mark">${shape("rejected")}Rejected by Zig ${escapeHtml(state.health.zig || "0.17")}</span>`
                    : `<span class="mark">${shape("compiles")}Compiles, and is still wrong</span>`;
                return `<div class="case"><div class="case-head">${markHtml}<span class="evidence" data-evidence="${index}"></span></div><div class="note">${renderRich(sample.before)}</div>${figure(state.drafts.get(`dont-${index}`) ?? sample.code, `Figure 3-${dfig}. Non-compliant source`, `dont-${index}`)}</div>`;
            })
            .join("") + (dontSide.after ? `<div class="prose">${renderRich(dontSide.after)}</div>` : "");
    const checkRows = checks
        .map((check) => `<tr><td><code>${idHtml(check.id)}</code></td><td><span class="mark">${shape(check.severity === "review" ? "review" : "flagged")}${escapeHtml(check.severity)}</span></td><td class="hide-narrow">${check.rules.map((id) => `<a href="#${id}">${escapeHtml(ruleLabel(id))}</a>`).join(", ")}</td><td>${escapeHtml(check.summary)}</td></tr>`)
        .join("");
    const checkTable = checks.length
        ? `<div class="tablewrap"><table class="spec stack"><caption><b>Table 4-1.</b> misra-lint checks that decide ${escapeHtml(label(rule))}</caption><thead><tr><th>Check</th><th>Severity</th><th class="hide-narrow">Rules</th><th>Reports</th></tr></thead><tbody>${checkRows}</tbody></table></div>`
        : `<p class="prose"><span class="mark">${shape("reader")}No misra-lint check decides ${escapeHtml(label(rule))}.</span> The compiler rejects some of its don'ts; a reader decides the rest.</p>`;
    const marks = record ? record.dont.cases.map((item) => item.mark) : [];
    const isRejected = (sample) => sample.before.trimStart().startsWith("**Rejected");
    const rejectedCount = dontSide.samples.filter(isRejected).length;
    const compilesCount = dontSide.samples.length - rejectedCount;
    const pending = state.health.lint ? '<span class="hint">checking</span>' : "n/a";
    const aside = `<aside class="chars" aria-label="Characteristics of ${escapeHtml(label(rule))}"><table class="spec"><caption><b>Characteristics</b></caption><thead><tr><th>Parameter</th><th class="tnum">Value</th></tr></thead><tbody>
<tr><td>Pin</td><td class="tnum">${pinNo(rule.id)} of ${order.length}</td></tr>
<tr><td>Name</td><td class="tnum">${escapeHtml(pinName(rule))}</td></tr>
<tr><td>Group</td><td>${escapeHtml(group?.title ?? "")}</td></tr>
<tr><td>Do samples</td><td class="tnum">${doSide.samples.length}</td></tr>
<tr><td><span class="mark">${shape("rejected")}Don't, rejected by Zig</span></td><td class="tnum">${rejectedCount}</td></tr>
<tr><td><span class="mark">${shape("compiles")}Don't, compiles</span></td><td class="tnum">${compilesCount}</td></tr>
<tr><td><span class="mark">${shape("flagged")}Flagged by misra-lint</span></td><td class="tnum" data-char="flagged">${compilesCount ? pending : "0"}</td></tr>
<tr><td><span class="mark">${shape("reader")}Left to a reader</span></td><td class="tnum" data-char="reader">${compilesCount ? pending : "0"}</td></tr>
<tr><td>misra-lint checks</td><td class="tnum">${checks.length}</td></tr>
</tbody></table><figure class="pinmap mini">${pinMap(null, rule.id)}<figcaption><b>Pin ${pinNo(rule.id)}</b> on the package. <a href="#pins">Full pin map</a></figcaption></figure></aside>`;
    main.innerHTML = `
<div class="part"><p class="part-num"><span class="kind">${kind}</span> ${escapeHtml(rule.number)}</p><div><h1 class="part-title">${escapeHtml(plain(rule.short))}</h1><p class="part-side">Pin ${pinNo(rule.id)}, ${escapeHtml(pinName(rule))}. ${escapeHtml(group?.title ?? "")}</p></div></div>
<p class="record"><span>id <code>${escapeHtml(rule.id)}</code></span><span>${doSide.samples.length} do, ${marks.length} don't (${marks.map((mark) => escapeHtml(mark)).join(", ") || "none"})</span><span>${checks.length} misra-lint ${checks.length === 1 ? "check" : "checks"}</span></p>
<div class="sheet-body"><div class="sheet-main">
${sec("1", "Description", `<div class="prose lede">${renderRich(rule.intro)}</div>`)}
${sec("2", "Do", doBody || '<p class="hint">No separate sample.</p>')}
${sec("3", "Don't", dontBody || '<p class="hint">No separate sample.</p>')}
${sec("4", "Machine checks", checkTable)}
</div>${aside}</div>
${pager}`;
    wireFigures(rule);
    fillEvidence(rule);
}

async function fillEvidence(rule) {
    const samples = rule.dont?.samples ?? [];
    let flagged = 0;
    let reader = 0;
    let ran = true;
    await Promise.all(
        samples.map(async (sample, index) => {
            const slot = main.querySelector(`[data-evidence="${index}"]`);
            if (!slot || !sample.code.trim()) return;
            if (sample.before.trimStart().startsWith("**Rejected")) {
                slot.innerHTML = `<span class="mark">${shape("rejected")}Known from the compiler</span>`;
                return;
            }
            const findings = await lintEvidence(sample.code);
            if (state.id !== rule.id || !slot.isConnected) return;
            if (findings === null) {
                ran = false;
                slot.innerHTML = '<span class="hint">misra-lint did not run.</span>';
                return;
            }
            const hits = findings.filter((item) => item.rules.includes(rule.id));
            if (hits.length) flagged += 1;
            else reader += 1;
            slot.innerHTML = hits.length
                ? `<span class="mark">${shape("flagged")}Flagged by misra-lint: ${[...new Set(hits.map((item) => item.check))].map((id) => `<code>${idHtml(id)}</code>`).join(", ")}</span>`
                : `<span class="mark">${shape("reader")}Not decided by misra-lint; a reader decides</span>`;
        }),
    );
    if (state.id !== rule.id) return;
    const flaggedCell = main.querySelector('[data-char="flagged"]');
    const readerCell = main.querySelector('[data-char="reader"]');
    if (flaggedCell && flaggedCell.querySelector(".hint")) flaggedCell.textContent = ran ? String(flagged) : "n/a";
    if (readerCell && readerCell.querySelector(".hint")) readerCell.textContent = ran ? String(reader) : "n/a";
}

function wireFigures(rule) {
    for (const button of main.querySelectorAll("[data-edit]")) {
        button.addEventListener("click", () => {
            state.editing = button.dataset.edit;
            renderRule(rule);
            main.querySelector(`[data-bench="${state.editing}"] textarea`)?.focus();
        });
    }
    const host = main.querySelector("[data-bench]");
    if (!host) return;
    const key = host.dataset.bench;
    const [side, index] = key.split("-");
    const original = rule[side === "do" ? "do" : "dont"].samples[Number(index)].code;
    mountBench(host, {
        value: state.drafts.get(key) ?? original,
        minLines: MIN_EDITOR_LINES,
        onInput: (value) => state.drafts.set(key, value),
        restore: () => {
            state.drafts.delete(key);
            return original;
        },
        close: () => {
            state.editing = null;
            renderRule(rule);
        },
    });
}

function renderBench() {
    document.title = "Evaluate a file: MISRA Zig";
    main.className = "bench-page";
    main.innerHTML = `
<div class="part"><p class="part-num"><span class="kind">EVM</span> 0.17</p><div><h1 class="part-title">Evaluate a Zig file against MISRA Zig</h1><p class="part-side">Check runs <code>zig test --test-no-exec -lc -ODebug</code> and every misra-lint check. Findings link to the rule they break.</p></div></div>
${sec("1", "Source", '<div data-bench="bench"></div>')}`;
    mountBench(main.querySelector("[data-bench]"), {
        value: stored(BENCH_KEY) ?? BENCH_EXAMPLE,
        minLines: BENCH_LINES,
        onInput: (value) => store(BENCH_KEY, value),
        restore: () => {
            store(BENCH_KEY, null);
            return BENCH_EXAMPLE;
        },
        restoreLabel: "Load the example",
        clear: true,
    });
}

/* Editor with gutter marks, and the Check bench around it. */

function mountBench(host, options) {
    host.innerHTML = `<div class="editor"><ol class="gutter" aria-hidden="true"></ol><div class="code"><pre aria-hidden="true"></pre><textarea spellcheck="false" autocapitalize="off" autocomplete="off" aria-label="Zig source" aria-describedby="bench-status"></textarea></div></div>
<div class="toolbar"><button type="button" class="act" data-act="check">Check with Zig${state.health.lint ? " and misra-lint" : ""}</button><button type="button" class="quiet" data-act="restore">${escapeHtml(options.restoreLabel ?? "Restore the sample")}</button>${options.clear ? '<button type="button" class="quiet" data-act="clear">Clear</button>' : ""}<button type="button" class="quiet" data-act="copy">Copy</button>${options.close ? '<button type="button" class="quiet" data-act="close">Close the editor</button>' : ""}<span class="hint"><kbd>Ctrl</kbd>+<kbd>Enter</kbd> checks</span></div>
<p class="status" id="bench-status" role="status"></p><div class="results"></div>`;
    const area = host.querySelector("textarea");
    const pre = host.querySelector(".code pre");
    const gutter = host.querySelector(".gutter");
    const code = host.querySelector(".code");
    const status = host.querySelector(".status");
    const results = host.querySelector(".results");
    const button = host.querySelector('[data-act="check"]');
    let marks = new Map();
    let escaped = false;

    const paint = () => {
        const lines = area.value.split("\n");
        const count = Math.max(lines.length, options.minLines);
        let body = "";
        let numbers = "";
        for (let i = 0; i < count; i++) {
            const line = lines[i] ?? "";
            const here = marks.get(i + 1);
            body += `<span class="l${here ? " hit" : ""}">${highlight(line)}</span>`;
            const title = here ? ` title="${escapeHtml(here.map((item) => item.title).join("\n"))}"` : "";
            const glyph = here ? shape(here[0].kind) : "";
            numbers += `<li${here ? ` class="hit" data-line="${i + 1}"` : ""}${title}>${glyph}${i < lines.length ? i + 1 : ""}</li>`;
        }
        pre.innerHTML = body;
        gutter.innerHTML = numbers;
        code.style.height = `calc(${count} * var(--line) + 2rem)`;
    };

    const goToLine = (line) => {
        const lines = area.value.split("\n");
        let offset = 0;
        for (let i = 0; i < line - 1 && i < lines.length; i++) offset += lines[i].length + 1;
        area.focus();
        area.setSelectionRange(offset, offset + (lines[line - 1]?.length ?? 0));
        host.querySelector(".editor").scrollIntoView({ block: "nearest" });
    };

    const clearResult = () => {
        marks = new Map();
        status.className = "status";
        status.textContent = "";
        results.innerHTML = "";
    };

    const check = async () => {
        button.disabled = true;
        status.className = "status";
        status.textContent = "Checking with Zig.";
        results.innerHTML = "";
        try {
            const response = await fetch("/api/check", {
                method: "POST",
                headers: { "content-type": "application/json" },
                body: JSON.stringify({ source: area.value }),
            });
            const body = await response.json();
            showResult(body);
        } catch {
            status.className = "status bad";
            status.textContent = "The checker is not running. From the repo, run bun scripts/server.ts.";
        } finally {
            button.disabled = false;
        }
    };

    const showResult = (body) => {
        const findings = body.findings ?? null;
        const errors = body.errors ?? [];
        const rows = [
            ...errors.map((item) => ({ line: item.line, kind: "error", check: "zig", rules: [], message: item.message })),
            ...(findings ?? []).map((item) => ({
                line: item.line,
                kind: item.severity === "review" ? "review" : "flagged",
                check: item.check,
                rules: item.rules,
                message: item.subject ? `${item.message} (${item.subject})` : item.message,
            })),
        ].sort((a, b) => a.line - b.line);
        marks = new Map();
        for (const row of rows) {
            const list = marks.get(row.line) ?? [];
            list.push({ kind: row.kind, title: `${row.check}: ${row.message}` });
            marks.set(row.line, list);
        }
        paint();
        const lintCount = findings?.length ?? 0;
        if (body.status === "accepted") {
            status.className = lintCount ? "status bad" : "status ok";
            status.innerHTML = lintCount
                ? `${shape("flagged")}Zig accepted the file. misra-lint reported ${lintCount} ${lintCount === 1 ? "finding" : "findings"}.`
                : `${shape("ok")}Zig accepted the file${findings ? " and misra-lint reported nothing" : ""}. The rules no check decides still need a reader.`;
        } else if (body.status === "rejected") {
            status.className = "status bad";
            status.innerHTML = `${shape("error")}Zig rejected the file${findings ? `. misra-lint reported ${lintCount} ${lintCount === 1 ? "finding" : "findings"}` : ""}.`;
        } else {
            status.className = "status bad";
            status.textContent = `The check did not finish: ${body.output ?? "no reason given"}`;
            return;
        }
        const table = rows.length
            ? `<div class="tablewrap"><table class="spec stack"><caption><b>Findings.</b><span class="legend"><span class="mark">${shape("error")}compiler error</span><span class="mark">${shape("flagged")}violation</span><span class="mark">${shape("review")}review</span></span></caption><thead><tr><th class="tnum">Line</th><th>Source</th><th>Rules</th><th>Report</th></tr></thead><tbody>${rows
                  .map((row) => `<tr><td class="tnum"><button type="button" class="line-btn" data-line="${row.line}">${row.line}</button></td><td><span class="mark">${shape(row.kind)}<code>${idHtml(row.check)}</code></span></td><td>${row.rules.map((id) => `<a href="#${id}">${escapeHtml(ruleLabel(id))}</a>`).join(", ") || "<span class=\"hint\">compiler</span>"}</td><td>${escapeHtml(row.message)}</td></tr>`)
                  .join("")}</tbody></table></div>`
            : "";
        const lintNote = findings === null ? `<p class="hint">misra-lint did not run${state.health.lintProblem ? `: ${escapeHtml(state.health.lintProblem)}` : "."}</p>` : "";
        results.innerHTML = `${table}${lintNote}<h3>Compiler output</h3><pre class="compiler">${escapeHtml(body.output ?? "")}</pre>`;
        for (const line of results.querySelectorAll("[data-line]")) {
            line.addEventListener("click", () => goToLine(Number(line.dataset.line)));
        }
    };

    area.value = options.value;
    paint();
    area.addEventListener("input", () => {
        options.onInput(area.value);
        if (marks.size) clearResult();
        paint();
    });
    area.addEventListener("scroll", () => {
        pre.scrollLeft = area.scrollLeft;
    });
    area.addEventListener("keydown", (event) => {
        if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
            event.preventDefault();
            check();
            return;
        }
        if (event.key === "Escape") {
            escaped = true;
            return;
        }
        if (event.key === "Tab" && !event.shiftKey && !escaped) {
            event.preventDefault();
            const start = area.selectionStart;
            area.setRangeText("    ", start, area.selectionEnd, "end");
            area.dispatchEvent(new Event("input"));
        }
        escaped = false;
    });
    gutter.addEventListener("click", (event) => {
        const item = event.target.closest("li[data-line]");
        if (item) goToLine(Number(item.dataset.line));
    });
    button.addEventListener("click", check);
    host.querySelector('[data-act="restore"]').addEventListener("click", () => {
        area.value = options.restore();
        clearResult();
        paint();
        area.focus();
    });
    host.querySelector('[data-act="clear"]')?.addEventListener("click", () => {
        area.value = "";
        options.onInput("");
        clearResult();
        paint();
        area.focus();
    });
    host.querySelector('[data-act="close"]')?.addEventListener("click", options.close);
    host.querySelector('[data-act="copy"]').addEventListener("click", async () => {
        try {
            await navigator.clipboard.writeText(area.value);
            status.className = "status";
            status.textContent = "Copied.";
        } catch {
            area.focus();
            area.select();
            status.className = "status bad";
            status.textContent = "Copy failed. The source is selected.";
        }
    });
}

/* Search. */

function haystack(rule) {
    const chunks = [label(rule), rule.heading, rule.number, rule.short, rule.intro];
    for (const side of [rule.do, rule.dont]) {
        if (!side) continue;
        chunks.push(side.after);
        for (const sample of side.samples) chunks.push(sample.before, sample.code);
    }
    for (const check of checksFor(rule.id)) chunks.push(check.id, check.summary);
    return chunks.join("\n").toLowerCase();
}

function renderHits() {
    const query = searchBox.value.trim().toLowerCase();
    if (!query || !state.book) {
        hitsBox.hidden = true;
        searchBox.setAttribute("aria-expanded", "false");
        return;
    }
    const hits = pins()
        .map(ruleById)
        .filter((rule) => rule && haystack(rule).includes(query));
    hitsBox.innerHTML = hits.length
        ? `<ul>${hits.map((rule) => `<li><a href="#${rule.id}"><span class="hit-id">${escapeHtml(label(rule))}</span><span>${escapeHtml(plain(rule.short))}</span></a></li>`).join("")}</ul>`
        : '<p class="empty">No rule matches.</p>';
    hitsBox.hidden = false;
    searchBox.setAttribute("aria-expanded", "true");
}

function closeHits() {
    hitsBox.hidden = true;
    searchBox.setAttribute("aria-expanded", "false");
}

searchBox.addEventListener("input", renderHits);
searchBox.addEventListener("keydown", (event) => {
    if (event.key === "ArrowDown") {
        event.preventDefault();
        hitsBox.querySelector("a")?.focus();
    } else if (event.key === "Escape") {
        searchBox.value = "";
        closeHits();
    }
});
hitsBox.addEventListener("keydown", (event) => {
    const links = [...hitsBox.querySelectorAll("a")];
    const at = links.indexOf(document.activeElement);
    if (event.key === "ArrowDown" && at < links.length - 1) {
        event.preventDefault();
        links[at + 1].focus();
    } else if (event.key === "ArrowUp") {
        event.preventDefault();
        if (at <= 0) searchBox.focus();
        else links[at - 1].focus();
    } else if (event.key === "Escape") {
        searchBox.focus();
        closeHits();
    }
});
hitsBox.addEventListener("click", (event) => {
    if (event.target.closest("a")) {
        searchBox.value = "";
        closeHits();
    }
});
document.querySelector(".search").addEventListener("submit", (event) => {
    event.preventDefault();
    const first = hitsBox.querySelector("a");
    if (first) {
        location.hash = first.getAttribute("href");
        searchBox.value = "";
        closeHits();
    }
});
document.addEventListener("click", (event) => {
    if (!event.target.closest(".search")) closeHits();
});

/* Theme: auto follows the OS; light and dark are stored. */

const THEMES = ["auto", "light", "dark"];

function applyTheme(theme) {
    if (theme === "auto") delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = theme;
    themeButton.textContent = theme === "auto" ? "Auto" : theme === "light" ? "Light" : "Dark";
    themeButton.setAttribute("aria-label", theme === "auto" ? "Color theme: follows the system" : `Color theme: ${theme}`);
}

themeButton.addEventListener("click", () => {
    const current = stored(THEME_KEY) ?? "auto";
    const next = THEMES[(THEMES.indexOf(current) + 1) % THEMES.length];
    store(THEME_KEY, next === "auto" ? null : next);
    applyTheme(next);
});

/* Keys: / finds, [ and ] step through the pins. */

document.addEventListener("keydown", (event) => {
    const typing = event.target.closest?.("input, textarea, select, [contenteditable]");
    if (typing || event.ctrlKey || event.metaKey || event.altKey) return;
    if (event.key === "/") {
        event.preventDefault();
        searchBox.focus();
        searchBox.select();
        return;
    }
    if ((event.key === "[" || event.key === "]") && state.book) {
        const order = pins();
        const at = order.indexOf(state.id);
        if (at === -1) return;
        const to = order[at + (event.key === "]" ? 1 : -1)];
        if (to) location.hash = `#${to}`;
    }
});

document.querySelector(".skip").addEventListener("click", (event) => {
    event.preventDefault();
    main.focus();
    main.scrollIntoView();
});

/* Routing. */

function show() {
    const id = location.hash.replace(/^#/, "") || "reading";
    const footPage = document.getElementById("footpage");
    if (id !== state.id) state.editing = null;
    if (id !== state.id) state.drafts.clear();
    for (const link of document.querySelectorAll("[data-nav]")) {
        const current = link.dataset.nav === id || (link.dataset.nav === "reading" && id === "pins");
        if (current) link.setAttribute("aria-current", "page");
        else link.removeAttribute("aria-current");
    }
    if (id === "playground") {
        state.id = id;
        renderBench();
        footPage.textContent = "Evaluation module";
    } else {
        const rule = ruleById(id);
        if (!rule || rule.id === "reading") {
            state.id = "reading";
            renderFront();
            footPage.textContent = "Front sheet";
        } else {
            state.id = rule.id;
            renderRule(rule);
            footPage.textContent = `Pin ${pinNo(rule.id)} of ${pins().length}`;
        }
    }
    const anchor = id === "pins" ? document.getElementById("pins") : null;
    if (anchor) anchor.scrollIntoView();
    else window.scrollTo(0, 0);
}

applyTheme(stored(THEME_KEY) ?? "auto");
window.addEventListener("hashchange", show);

try {
    const [book, agent, checks, health] = await Promise.all(
        ["/handbook.json", "/rules.json", "/checks.json", "/api/health"].map((url) =>
            fetch(url).then((res) => {
                if (!res.ok) throw new Error(url);
                return res.json();
            }),
        ),
    );
    state.book = book;
    state.agent = agent;
    state.checks = checks;
    state.health = health;
    if (health.revised) document.getElementById("docnum").textContent = `MZ-0.17, revised ${health.revised}`;
    show();
} catch {
    main.innerHTML = '<p class="loading">The handbook did not load. From the repo, run <code>bun scripts/server.ts</code> and open the address it prints.</p>';
}
