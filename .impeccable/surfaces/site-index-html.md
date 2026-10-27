---
version: 1
slug: "site-index-html"
primary_target: "site/index.html"
related_targets: ["site/site.css","site/site.js"]
---

Scope: site/index.html and its CSS and JavaScript. Mode: Read. Replacement visual world, code-led, replacing the university press frame (seed 114c8b8c). Handbook data, /rules.json, the compiler check, and misra-lint findings stay authoritative. Reader's job: learn the rules; checking code supports it. Wrong: a generic docs site, decoration that slows reading. Light and dark follow the OS with a manual switch.

## Direction contract

THESIS: The handbook is a datasheet family: each rule is a part with a part number, a description, typical application, and characteristics, refusing the docs-sidebar template.

OWN-WORLD: White sheet, black ink, one manufacturer red on the running bar, rules, and part numbers; light grey table headers; hairline black ruled tables with MIN/TYP/MAX discipline; figures captioned "Figure n". Archivo condensed bold for part numbers and section heads, Archivo for prose, Hack for source. Dark is the same sheet printed in reverse.

STORY: Read what the standard covers, find a rule in the pin map or pin function table, read its description, compare the typical application with the don't, see which checks decide it, edit and check.

FIRST VIEWPORT: Red running bar with doc number, revision, and search; part number MZ-0.17 at display scale with the title; Features list beside the Description; below it a package drawing whose 39 pins are the rules, grouped by side as the six groups, beside the Pin Functions table. Signature: hovering a pin lights its row and its group side; the pin map is the contents.

FORM: Component datasheet, candidate 1 of 7 (Impeccable's pick), seed key e7045df5. Raises: verdicts drawn by shape (jackfield), resume flag on the last sheet (cutting bench), evidence level per don't (provenance), fixed regions (PC-98), whole-sheet dark printing (cyclorama).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
