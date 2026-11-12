---
name: MISRA Zig
description: A component datasheet family for Zig obligations; every rule is a part with a pin, a description, and characteristics.
colors:
  bar-red: "#c41e1e"
  red: "#c41e1e"
  red-text: "#b71c1c"
  on-bar: "#ffffff"
  sheet: "#ffffff"
  ink: "#121316"
  ink-2: "#474a52"
  hair: "#c8cad0"
  head: "#eaebed"
  code: "#f5f5f6"
  row: "#fbeceb"
  sel: "#ffd8d2"
  ok: "#0d6a39"
  warn: "#8a5800"
  syntax-keyword: "#2445b8"
  syntax-string: "#8c2c58"
  syntax-comment: "#686c76"
  syntax-number: "#8a5200"
  syntax-builtin: "#0a6a6a"
  dark-sheet: "#131416"
  dark-ink: "#ecebe7"
  dark-ink-2: "#aeb0b6"
  dark-hair: "#3b3d43"
  dark-head: "#202226"
  dark-code: "#1a1b1e"
  dark-red: "#e8463f"
  dark-row: "#2c1b1a"
  dark-sel: "#6a1a14"
  dark-ok: "#5fd28f"
  dark-warn: "#f2b84e"
  dark-syntax-keyword: "#93a8ff"
  dark-syntax-string: "#f39cc3"
  dark-syntax-comment: "#8d9099"
  dark-syntax-number: "#e9b36b"
  dark-syntax-builtin: "#6fd5cf"
typography:
  display:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(3.25rem, 9vw, 6rem)"
    fontWeight: 800
    lineHeight: 0.88
    letterSpacing: "-0.02em"
    fontVariation: "'wdth' 70"
  title:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(1.15rem, 2vw, 1.5rem)"
    fontWeight: 500
    lineHeight: 1.3
  headline:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.375rem"
    fontWeight: 700
    lineHeight: 1.2
    fontVariation: "'wdth' 78"
  subhead:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 700
    fontVariation: "'wdth' 78"
  maker:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.3rem"
    fontWeight: 800
    letterSpacing: "0.01em"
    fontVariation: "'wdth' 75"
  lede:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.1875rem"
    fontWeight: 400
    lineHeight: 1.6
  body:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.6
    fontFeature: "tnum"
  table:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.45
    fontFeature: "tnum"
  label:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 700
    letterSpacing: "0.03em"
    fontVariation: "'wdth' 78"
  caption:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 400
  source:
    fontFamily: "Hack, ui-monospace, monospace"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: "1.6rem"
rounded:
  none: "0"
spacing:
  gutter: "clamp(1rem, 4vw, 3rem)"
  cell: "0.45rem 0.6rem"
  figure: "1.75rem"
  section: "2.75rem"
  column-gap: "3.5rem"
  pager: "3.5rem"
  measure: "68ch"
  page: "84rem"
  aside: "19rem"
components:
  running-bar:
    backgroundColor: "{colors.bar-red}"
    textColor: "{colors.on-bar}"
    height: "3.25rem"
    padding: "0.4rem clamp(1rem, 4vw, 3rem)"
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.sheet}"
    typography: "{typography.subhead}"
    rounded: "{rounded.none}"
    padding: "0.55rem 1.1rem"
  button-primary-hover:
    backgroundColor: "{colors.red}"
    textColor: "{colors.on-bar}"
  button-primary-disabled:
    backgroundColor: "{colors.head}"
    textColor: "{colors.ink-2}"
  button-quiet:
    textColor: "{colors.red-text}"
    padding: "0.35rem 0"
  search-input:
    backgroundColor: "rgb(0 0 0 / 0.16)"
    textColor: "{colors.on-bar}"
    rounded: "{rounded.none}"
    padding: "0.4rem 0.7rem"
    width: "15rem"
  search-input-focus:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.ink}"
  theme-switch:
    textColor: "{colors.on-bar}"
    rounded: "{rounded.none}"
    padding: "0.3rem 0.6rem"
  table-head:
    backgroundColor: "{colors.head}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    padding: "{spacing.cell}"
  table-row-lit:
    backgroundColor: "{colors.row}"
  source-figure:
    backgroundColor: "{colors.code}"
    textColor: "{colors.ink}"
    typography: "{typography.source}"
    rounded: "{rounded.none}"
    padding: "1rem 1.25rem"
  characteristics:
    width: "{spacing.aside}"
    typography: "{typography.caption}"
---

# Design System: MISRA Zig

## Overview

The handbook is a semiconductor datasheet family. The front sheet is part MZ-0.17: a red running bar, the part number at display scale, Features beside Description, then a package drawing whose pins are the rules beside a Pin Functions table. Every rule is its own sheet: part number ("Rule 10.6", "Dir 4.6"), numbered Description, Do, Don't, and Machine checks, and a Characteristics table. Evaluate a file is part "EVM 0.17".

White sheet, black ink, hairline and heavy black rules, light grey table heads, one manufacturer red. Archivo at 17px (1.0625rem) on a 68ch measure for prose; condensed Archivo for names and numbers; Hack for source. Dark keeps the bar red and swaps ink and paper. No sidebar, no cards, no rounded corners, no decorative imagery. Drawings are the package, the maker mark, and the verdict shapes.

Tokens and component metrics in the frontmatter match `site/site.css`. `.impeccable/surfaces/site-index-html.md` is the page sidecar and defers here for those values.

## Colors

`site/site.css` stores the light set on `:root` and the dark set on `[data-theme="dark"]` and inside `prefers-color-scheme: dark`. Syntax tokens in CSS are `--kw`, `--str`, `--cmt`, `--num`, `--blt`; the frontmatter names are syntax-keyword, syntax-string, syntax-comment, syntax-number, syntax-builtin.

- **bar-red / red** (`#c41e1e`): bar fill, favicon, `theme-color`. `red` also marks feature-list bullets, the focus outline, the editor caret, lit pin legs and brackets, the compiles and flagged shapes, the resume flag, and the primary button hover. The bar stays `#c41e1e` in dark.
- **red-text** (`#b71c1c`, dark `#e8463f`): links, section numerals, the "Rule" or "Dir" word, table caption labels, the lit pin name, failing status, search hit ids. In dark, `--red` and `--red-text` are both `#e8463f`.
- **ok** (`#0d6a39`, dark `#5fd28f`): the ok tick and a clean check status.
- **warn** (`#8a5800`, dark `#f2b84e`): stroke of the review diamond.
- **sheet, ink, ink-2, hair, head, code, row, sel**: page, body ink, secondary ink, hairline, table-head grey, source paper, lit row, selection. **on-bar** (`#ffffff`): text and focus outline inside the bar. The search border is white at 55% and its fill is black at 16%.

The bar is the only large red field. Elsewhere red is a stroke, a numeral, a link, a marker, or a shape at most 0.9rem tall.

## Typography

Archivo is one variable file: weight 100 to 900, width 62% to 125% (`site/site.css` `@font-face`). Fallback: Helvetica Neue, Arial. Hack Regular (400) and Bold (700) are separate files; fallback ui-monospace. `font-variant-numeric: tabular-nums` is set on `body`.

Condensed width is for names and numbers: 70% part numbers (and the package name at 22px, footer part number at 1.5rem), 75% maker, 78% (`--cond`) heads, labels, captions, pin names. Prose and table cells stay at normal width.

| Role | Size | Weight | Line | Width |
|------|------|--------|------|-------|
| Display | clamp(3.25rem, 9vw, 6rem) | 800 | 0.88 | 70% |
| Title | clamp(1.15rem, 2vw, 1.5rem), max 40ch | 500 | 1.3 | |
| Headline | 1.375rem | 700 | 1.2 | 78% |
| Subhead | 1.0625rem (button label 1rem) | 700 | | 78% |
| Maker | 1.3rem, uppercase, tracking 0.01em | 800 | | 75% |
| Lede | 1.1875rem | 400 | 1.6 | |
| Body | 1.0625rem (1rem under 48rem) | 400 | 1.6 | |
| Table | 0.9375rem (0.875rem in Characteristics and under 48rem) | 400 | 1.45 | |
| Label | 0.8125rem, uppercase, tracking 0.03em | 700 | | 78% |
| Caption | 0.875rem; table captions 0.9375rem condensed | 400 (label 700) | | 78% on the label |
| Source | 0.875rem (0.8125rem under 48rem), line 1.6rem, tab 4 | 400 | | |

Figure captions are ink-2 with a bold condensed "Figure n-m." in ink. Table captions are bold condensed 0.9375rem with a red-text "Table n-m." label. Section heads put a red-text numeral before the text and a 1px ink underline under the head.

## Layout

`main` max-width 84rem, gutter `clamp(1rem, 4vw, 3rem)`. Sticky bar, min-height 3.25rem. Docline: document number left, "Not a publication of the MISRA Consortium" right, 0.8125rem condensed, 1px ink rule below. Footer under a 3px ink rule: part number and page, the check notice, JSON links, keyboard keys.

Front sheet: Features and Description in two equal columns, gap 3.5rem. Pinout: package figure `minmax(20rem, 34rem)`, sticky at `top: 5rem`, beside the Pin Functions table. Rule sheet: main column plus a 19rem Characteristics aside, sticky at `top: 4.5rem`, gap 3.5rem, with an unsticky package inset. Sections 2.75rem apart, figures 1.75rem, don't cases 2.25rem, pager 3.5rem below the last section.

At `max-width: 64rem` the aside and the pin map stack, `position: static`, max-width 30rem. At `max-width: 48rem` the bar is `position: static` and wraps, search is full width, the docline stacks, the part head and feature columns become one column, the pin map scrolls sideways at 28rem with a 2px dashed hairline edge and a scroll hint, and `.spec.stack` rows become a grid.

## Depth

Flat sheet. 3px ink under the part head, above the pager, and above the footer. 2px ink on the top of every table and source figure and on the bottom of every table. 1px ink under section heads, table heads, and the docline. 1px hairline between rows. The bar sits above content by `position: sticky` and `z-index: 10`.

The search hit list is the one shadow: `box-shadow: 0 0.75rem 2rem rgb(0 0 0 / 0.22)`, plus a 2px ink border. Region weight is the rule weight, not a tint panel.

## Shapes

Buttons, inputs, the theme switch, figures, the editor, tables, and the search list use `border-radius: 0`. Strokes are 1px, 2px, or 3px. The package is a 2px ink rectangle with a notch and a pin-1 dot. Legs are rectangles; group brackets are 1.5px hairline with rotated uppercase labels. The maker mark uses the same package glyph at `stroke-width: 2`. The resume flag is a red pennant (`clip-path` on a 0.65rem by 0.9rem rectangle).

`prefers-reduced-motion: reduce` sets `transition: none` and `animation: none` on every element.

## Components

**Primary button.** Ink fill, sheet text, 2px ink border, condensed 700 at 1rem, tracking 0.02em, padding 0.55rem 1.1rem. "Evaluate a file" is a bar link; "Check with Zig" is this button. Hover and focus-visible: red fill, red border, on-bar text. The global focus outline is 2px red at 2px offset. Disabled: head fill, hairline border, ink-2 text, `cursor: progress`.

**Quiet control.** No box. red-text, 0.9375rem, underline 1px, 2px on hover. Edit and check, Restore, Copy, Clear, Close the editor.

**Search.** 15rem, square, on-bar border at 55%, black fill at 16%, on-bar text, placeholder "Find a rule  /". Focus: sheet background, ink text, red caret, 2px on-bar outline. The list is `min(32rem, 90vw)`, 2px ink border. Each row is a 5rem condensed red-text id and the title; hover and focus use head grey.

**Editor.** Source paper, 1px hairline, 2px ink top, 3.75rem gutter (2.75rem under 48rem). Findings put a 0.55rem verdict shape on the gutter line. Highlighted source sits under a transparent textarea. `:focus-within` draws a 2px red outline inset 1px (`outline-offset: -1px`).

**Bar.** Maker mark and "MISRA Zig", then Contents and Evaluate a file at 0.9375rem. Hover and the current sheet get a 2px white underline. Theme switch: Auto, Light, Dark; square; white border at 55%; black fill at 16% on hover.

**Pager.** Two columns under a 3px ink rule. "Previous, pin n" and "Next, pin n" in 0.8125rem ink-2. The rule name uses the headline size and turns red-text with an underline on hover.

**Keys.** `/` finds, `[` and `]` page, Ctrl+Enter checks. `kbd` is Hack, 1px hairline, 2px bottom edge.

**Tables.** Full width, collapsed borders. Head row: head grey, uppercase condensed labels, 2px ink top, 1px ink bottom. Last body row: 2px ink bottom. Numeric columns right-aligned. Pin-table group rows are bold condensed with the pin span in ink-2. A row lit from the pin map uses the lit-row fill and red-text for the name.

**Source figures.** Padding 1rem 1.25rem, hairline border, 2px ink top, caption below. Compiler output uses the same paper at 0.8125rem with wrapping.

**Pin map.** One pin per rule, down the left side and up the right, brackets by group. Hover or focus fills the leg red, sets the name to red-text, turns that group's bracket and label red, and lights the Pin Functions row. Legs transition fill and stroke over 160ms with `cubic-bezier(0.22, 1, 0.36, 1)`. Brackets transition stroke, and labels fill, over 160ms ease-out. The last-read rule keeps a red-text name (`.pin-g.resume`). A rule sheet repeats the package as an unsticky inset with its own pin lit.

**Verdict marks.** Shape, then color. 0.7rem, except the tick at 0.85rem and gutter marks at 0.55rem. Label weight 600.

- Rejected by Zig: filled ink square.
- Compiles, and is still wrong: hollow red square, 2px.
- Flagged by misra-lint: filled red diamond (`rotate(45deg)`).
- Review: hollow amber diamond, 2px.
- Left to a reader: hollow ink-2 ring, 2px (`border-radius: 50%`).
- Compiler error: filled ink disc.
- Ok: green tick, an SVG mask.

**Characteristics.** Two columns, Parameter and Value, in the 19rem aside. Pin, name, group, do samples, and one row per verdict shape with its count. Values right-aligned. Until the lint pass finishes, counts read "checking". When misra-lint is absent they read "n/a".

**Resume flag.** Under the front part head: the pennant, "You stopped at {rule}, {group}.", and a resume link.

## Do's and Don'ts

Do:

- Lead every sheet with a display-style part number and a red-text section numeral.
- Caption figures "Figure n-m." and tables "Table n-m." in bold condensed.
- Separate regions with 3px, 2px, and 1px ink rules, and rows with the hairline.
- Draw each verdict as its shape so it reads in monochrome.
- Add a color to both printings: `:root`, and `[data-theme="dark"]` plus the `prefers-color-scheme` block.
- Keep the reduced-motion cut on every transition and animation.

Don't:

- Fill a region with red other than the running bar, the favicon, and the small verdict shapes and flag.
- Round corners. Circles are the reader ring, the compiler-error disc, and the pin-1 dot.
- Add a shadow other than the search hit list.
- Set prose or table cells in a condensed width.
- Mark a verdict with color alone.
- Add a docs sidebar. The pin map and the pin table are the contents.
