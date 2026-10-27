export type Sample = {
    before: string;
    code: string;
};

export type Side = {
    samples: Sample[];
    after: string;
};

export type RuleKind = "dir" | "rule" | "note";

export type Rule = {
    id: string;
    heading: string;
    number: string;
    kind: RuleKind;
    short: string;
    intro: string;
    do: Side | null;
    dont: Side | null;
};

export type Group = {
    title: string;
    blurb: string;
    ids: string[];
};

export type Handbook = {
    rules: Rule[];
    groups: Group[];
};

export type Mark = "rejected" | "compiles";

export type AgentCase = {
    mark: Mark;
    why: string;
    zig: string;
};

export type AgentRule = {
    id: string;
    number: string;
    kind: "dir" | "rule";
    group: string;
    obligation: string;
    do: { zig: string[]; note: string };
    dont: { cases: AgentCase[] };
};

export type AgentRules = {
    zig: string;
    source: string;
    rules: AgentRule[];
};

const GROUP_DEFS: Group[] = [
    {
        title: "Types, portability, and arithmetic",
        blurb: "Widths are explicit. An operation that must fit returns an error. A cast across a trust boundary is std.math.cast. A float from outside is checked for NaN and infinity.",
        ids: [
            "dir-4-6",
            "dir-4-15",
            "rule-8-1",
            "rule-10-1",
            "rule-10-2",
            "rule-10-3",
            "rule-10-4",
            "rule-10-5",
            "rule-10-6",
            "rule-10-7",
            "rule-10-8",
        ],
    },
    {
        title: "Initialization, pointers, and unions",
        blurb: "undefined may be stored and may not be read. A parameter that is not mutated is const, and no cast removes const. A pointer into a local does not outlive the call. A union carries its tag, and a switch reads it.",
        ids: [
            "dir-4-1",
            "rule-9-1",
            "rule-9-2",
            "rule-8-13",
            "rule-8-14",
            "rule-11-3",
            "rule-11-8",
            "rule-18-4",
            "rule-18-6",
            "rule-19-2",
            "rule-19-3",
        ],
    },
    {
        title: "Memory and other resources",
        blurb: "The allocator and the Io are parameters. Every allocation, file, and lock has one release path. Read errno before the next call.",
        ids: [
            "dir-4-12",
            "rule-21-3",
            "rule-22-1",
            "rule-22-2",
            "rule-22-3",
            "rule-22-4",
            "rule-22-5",
            "rule-22-6",
            "rule-22-7",
            "rule-22-8",
            "rule-22-9",
            "rule-22-10",
        ],
    },
    {
        title: "Functions and linkage",
        blurb: "A declaration without pub is file scope. export is the C ABI. Failure is an error or ?T. A std precondition is checked by the caller. There is no runtime recursion and no variadic function. Only main ends the process. Nothing deprecated is used.",
        ids: [
            "dir-4-7",
            "dir-4-11",
            "rule-1-5",
            "rule-8-2",
            "rule-8-4",
            "rule-8-7",
            "rule-8-8",
            "rule-17-1",
            "rule-17-2",
            "rule-21-8",
        ],
    },
    {
        title: "Control flow",
        blurb: "if and while take a bool, an optional, or an error union. An enum switch lists every tag. There is no goto.",
        ids: ["rule-2-1", "rule-12-1", "rule-13-4", "rule-14-4", "rule-15-1", "rule-16-3", "rule-16-4"],
    },
    {
        title: "Buffers and strings",
        blurb: "A length from outside is capped before it sizes anything. Text is a slice, pointer and length. A copy inside one buffer is @memmove. End of file is an error, not a zero length.",
        ids: ["dir-4-14", "rule-19-1", "rule-21-17", "rule-21-18"],
    },
    {
        title: "Threads, locks, and atomics",
        blurb: "Threads start once, a fixed number, and are joined once. Data two threads touch is locked or atomic, and atomics are .seq_cst. Two locks are taken in one order.",
        ids: ["dir-5-1", "dir-5-2", "dir-5-3", "rule-21-25"],
    },
    {
        title: "Already rejected by the compiler",
        blurb: "Narrowing, mixed signedness, null pointers, fallthrough, assignment inside a condition, partial initializers, and code after return are already compile errors.",
        ids: ["compiler"],
    },
];

function shortText(text: string, fallback: string): string {
    const flat = text.replace(/\s+/g, " ").trim();
    if (!flat) return fallback;
    return flat.split(/(?<=\.)\s/)[0] ?? flat;
}

function extractSide(body: string): Side {
    const samples: Sample[] = [];
    const re = /```zig\n([\s\S]*?)```/g;
    let last = 0;
    let match: RegExpExecArray | null;
    while ((match = re.exec(body))) {
        samples.push({
            before: body.slice(last, match.index).trim(),
            code: match[1].replace(/\n$/, ""),
        });
        last = match.index + match[0].length;
    }
    return { samples, after: body.slice(last).trim() };
}

function ruleIdentity(heading: string): Pick<Rule, "id" | "number" | "kind"> {
    const dir = /^Dir\s+(\d+\.\d+)\s*$/.exec(heading);
    if (dir) {
        const number = dir[1] ?? "";
        return { id: `dir-${number.replace(".", "-")}`, number, kind: "dir" };
    }
    const rule = /^Rule\s+(\d+\.\d+)\s*$/.exec(heading);
    if (rule) {
        const number = rule[1] ?? "";
        return { id: `rule-${number.replace(".", "-")}`, number, kind: "rule" };
    }
    return { id: "compiler", number: "", kind: "note" };
}

function parseClause(chunk: string): Rule {
    const nl = chunk.indexOf("\n");
    const headingLine = (nl === -1 ? chunk : chunk.slice(0, nl)).replace(/^#{2,3}\s+/, "").trim();
    let body = nl === -1 ? "" : chunk.slice(nl + 1);
    body = body.replace(/\n## (?:Rules|Directives)\s*/g, "\n").trim();
    const identity = ruleIdentity(headingLine);
    if (identity.kind === "note") {
        return {
            ...identity,
            heading: headingLine,
            short: shortText(body, headingLine),
            intro: body,
            do: null,
            dont: null,
        };
    }
    const doParts = body.split(/\n#### Do\n/);
    const intro = (doParts[0] ?? "").trim();
    const rest = doParts[1] ?? "";
    const dontParts = rest.split(/\n#### Don't\n/);
    const doBody = dontParts[0] ?? "";
    const dontBody = dontParts[1];
    return {
        ...identity,
        heading: headingLine,
        short: shortText(intro, headingLine),
        intro,
        do: doBody.trim() ? extractSide(doBody) : { samples: [], after: "" },
        dont: dontBody === undefined ? null : extractSide(dontBody),
    };
}

export function parseHandbook(markdown: string): Handbook {
    const text = markdown.replace(/\r\n/g, "\n");
    const chunks = text.split(/\n(?=### |## What )/);
    const first = chunks[0] ?? "";
    const preamble = first
        .replace(/^#[^\n]*\n/, "")
        .replace(/\n## (?:Rules|Directives)\s*/g, "\n")
        .trim();
    const reading: Rule = {
        id: "reading",
        heading: "How the samples work",
        number: "",
        kind: "note",
        short: "What a do and a don't show",
        intro: preamble,
        do: null,
        dont: null,
    };
    const rules = [reading, ...chunks.slice(1).map(parseClause)];
    const known = new Set(rules.map((rule) => rule.id));
    for (const group of GROUP_DEFS) {
        for (const id of group.ids) {
            if (!known.has(id)) throw new Error(`group lists unknown rule ${id}`);
        }
    }
    const placed = new Set(GROUP_DEFS.flatMap((group) => group.ids));
    for (const rule of rules) {
        if (rule.id !== "reading" && !placed.has(rule.id)) {
            throw new Error(`rule ${rule.id} is not in a group`);
        }
    }
    return { rules, groups: GROUP_DEFS };
}

function plainText(text: string): string {
    const stripped = text
        .replace(/```[a-z]*\n[\s\S]*?```/g, "")
        .replace(/`([^`]*)`/g, "$1")
        .replace(/\*\*([^*]*)\*\*/g, "$1");
    return stripped
        .split(/\n\n+/)
        .map((block) => block.replace(/\s+/g, " ").trim())
        .filter(Boolean)
        .join("\n\n");
}

function leadOf(text: string): { mark: Mark; why: string } | null {
    const match = /^\*\*(Rejected|Compiles)\b([^*]*)\*\*([\s\S]*)$/.exec(text.trim());
    if (!match) return null;
    const raw = `${match[2] ?? ""}${match[3] ?? ""}`.replace(/^\s*[.,]\s*/, "");
    return { mark: match[1] === "Rejected" ? "rejected" : "compiles", why: plainText(raw) };
}

function doFields(id: string, side: Side): AgentRule["do"] {
    const notes: string[] = [];
    const zig: string[] = [];
    for (const sample of side.samples) {
        const note = plainText(sample.before);
        if (note) notes.push(note);
        if (!sample.code.trim()) throw new Error(`${id} do fence is empty`);
        zig.push(sample.code);
    }
    const after = plainText(side.after);
    if (after) notes.push(after);
    if (zig.length === 0 && notes.length === 0) throw new Error(`${id} do is empty`);
    return { zig, note: notes.join("\n\n") };
}

function dontCases(id: string, side: Side): AgentCase[] {
    const cases: AgentCase[] = [];
    for (const sample of side.samples) {
        const lead = leadOf(sample.before);
        if (!lead) throw new Error(`${id} don't sample has no mark`);
        if (!lead.why && !sample.code.trim()) throw new Error(`${id} don't case is empty`);
        cases.push({ mark: lead.mark, why: lead.why, zig: sample.code });
    }
    const after = side.after.trim();
    if (after) {
        const lead = leadOf(after);
        if (lead) {
            if (!lead.why) throw new Error(`${id} don't case is empty`);
            cases.push({ mark: lead.mark, why: lead.why, zig: "" });
        } else if (cases.length === 0) {
            throw new Error(`${id} don't has no mark`);
        } else {
            const last = cases.at(-1);
            if (!last) throw new Error(`${id} don't has no mark`);
            const extra = plainText(after);
            if (extra) last.why = last.why ? `${last.why}\n\n${extra}` : extra;
        }
    }
    if (cases.length === 0) throw new Error(`${id} don't has no case`);
    return cases;
}

export function agentRules(book: Handbook): AgentRules {
    const reading = book.rules.find((rule) => rule.id === "reading");
    const version = /Zig (\d+\.\d+\.\d+)/.exec(reading?.intro ?? "")?.[1];
    if (!version) throw new Error("handbook does not name a Zig version");
    const rules: AgentRule[] = [];
    for (const rule of book.rules) {
        if (rule.kind === "note") continue;
        if (!rule.do || !rule.dont) throw new Error(`${rule.id} is missing a side`);
        const group = book.groups.find((item) => item.ids.includes(rule.id));
        if (!group) throw new Error(`${rule.id} is not in a group`);
        const obligation = plainText(rule.intro);
        if (!obligation) throw new Error(`${rule.id} obligation is empty`);
        rules.push({
            id: rule.id,
            number: rule.number,
            kind: rule.kind,
            group: group.title,
            obligation,
            do: doFields(rule.id, rule.do),
            dont: { cases: dontCases(rule.id, rule.dont) },
        });
    }
    return { zig: version, source: "docs/misra-zig-handbook.md", rules };
}
