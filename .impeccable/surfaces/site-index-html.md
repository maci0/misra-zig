---
version: 1
slug: "site-index-html"
primary_target: "site/index.html"
related_targets: ["site/site.css","site/site.js"]
---

# Handbook design direction

Scope: `site/index.html`, `site/site.css`, and `site/site.js`. The reader looks
up rules and compares samples; editing and checking support that task. The
handbook and generated JSON own the rule content. [DESIGN.md](../../DESIGN.md)
owns the shipped tokens, typography, layout, and component details.

## Direction contract

- The handbook is a component datasheet family. Each rule has a part number,
  description, sample figures, evidence, and characteristics.
- The front sheet has features, a description, a package drawing, and a pin
  function table. Pins follow the 59 directives and rules in group order, then
  the compiler note; an odd pin count leaves the last package pin NC.
- The pin map and table are the contents. Hovering or focusing a pin lights its
  table row and group bracket. Keep this navigation instead of a docs sidebar.
- Use a white sheet, black ink, ruled tables, and one manufacturer red. Red
  fills the running bar; elsewhere it marks lines, links, and small symbols.
- Set names and numbers in condensed Archivo, prose in normal-width Archivo,
  and source in Hack. Every figure and table has a numbered caption.
- Verdict shapes must distinguish outcomes without color. Use square corners;
  circles belong only to verdict marks and the pin-1 dot.
- Light and dark follow the OS. The bar offers Auto, Light, and Dark and stores
  the choice. The running bar keeps its red in both themes. Respect reduced motion.

## Decision record

The datasheet direction (seed `e7045df5`, candidate 1 of 7) replaced the earlier
university-press direction (seed `114c8b8c`). The finish review and subsequent
corrections are recorded in [the ledger](../../docs/ledger.md). Review captures
are disposable local files; the design contract and shipped source remain
tracked.
