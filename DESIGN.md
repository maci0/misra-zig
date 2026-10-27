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

**Creative North Star: "The Component Datasheet"**

The handbook is printed as a semiconductor datasheet family. The front sheet is part MZ-0.17: a red running bar, the part number at display scale, Features beside Description, then a package drawing whose pins are the rules beside a Pin Functions table. Every rule is its own sheet with a part number ("Rule 10.6", "Dir 4.6"), a numbered Description, Do, Don't, and Machine checks, and a Characteristics table that holds the counts. The system is white sheet, black ink, hairline and heavy black rules, light grey table heads, and one manufacturer red.

Density is that of a reference document: 17px Archivo prose at a 68ch measure, ruled tables with tabular figures, numbered sections (red numeral, condensed head, 1px ink underline), and figures and tables captioned "Figure n-m." and "Table n-m.". Archivo carries everything that is read; its condensed widths carry everything that is a name or a number. Hack carries source. Dark is the same sheet printed in reverse: the bar keeps its red, ink and paper swap, text red lifts.

The page has no sidebar, no cards, no rounded corners, and no decorative imagery. The only drawings are the package (pin map), the maker mark, and the verdict shapes, all built from straight strokes in ink and red.

**Key Characteristics:**
- Part numbers in Archivo at 70% width, weight 800, up to 6rem.
- One red: a solid field only on the running bar; elsewhere at line weight.
- Ruled tables: 2px ink top and bottom, 1px ink under the grey head, 1px hairline between rows.
- Verdicts drawn as shapes, so they read without color.
- Square corners everywhere; circles only inside the verdict shapes and the pin-1 dot.
- Light and dark from one token set, following the system with a manual Auto, Light, Dark switch.

## Colors

One manufacturer red over a neutral black-on-white sheet, with green and amber kept for verdict states and five muted syntax hues for source.

### Primary
- **Manufacturer Red** (bar-red, red): The running bar fill, the favicon field, and the browser theme color. As `red` it is the line-weight accent: feature-list markers, the focus outline, the editor caret, lit pin legs and group brackets, the compiles and flagged verdict shapes, the resume flag, and the primary button hover. The bar value is the same in both printings.
- **Signal Red Text** (red-text): Red that has to be read as text on the sheet: links, section numerals, the "Rule" or "Dir" word in a part number, table caption labels, the lit pin name, failing check status, search hit ids. In dark both `red` and `red-text` become **Reverse Red** (dark-red).

### Tertiary
- **Pass Green** (ok, dark-ok): The ok tick and a clean check status. Nothing else.
- **Review Amber** (warn, dark-warn): Stroke of the review diamond. Nothing else.

### Neutral
- **Sheet White** (sheet; dark-sheet in reverse): The page. Also the text on the primary button.
- **Datasheet Ink** (ink; dark-ink): Body text, heavy rules, the package outline, the rejected and compiler-error shapes, the primary button fill.
- **Second Ink** (ink-2; dark-ink-2): Docline, side lines under titles, captions, pin numbers, unlit legs and bracket labels, hints.
- **Hairline** (hair; dark-hair): Row rules, source figure borders, the editor gutter rule, kbd borders, unlit group brackets.
- **Table Head Grey** (head; dark-head): Table head fill, search hit hover, disabled button fill.
- **Source Paper** (code; dark-code): Background of source figures, the editor, and compiler output.
- **Lit Row** (row; dark-row): The table row, editor line, and gutter line lit by a pin hover or a finding.
- **Selection** (sel; dark-sel): Text selection.
- **On Bar** (on-bar): White text, borders, and focus outline inside the running bar. The search field border is on-bar at 55% and its fill is black at 16%.

Syntax highlighting uses syntax-keyword, syntax-string, syntax-number, syntax-builtin, and an italic syntax-comment, each with a lighter dark counterpart. They appear only inside Hack source.

### Named Rules
**The Running Bar Rule.** The bar is the only large field of red. Everywhere else red is a stroke, a numeral, a link, a marker, or a shape at most 0.9rem tall.

**The Same Bar Rule.** Dark printing keeps the bar at bar-red with white text. Only the sheet reverses; the text and line red lifts to dark-red so it stays legible on dark-sheet.

## Typography

**Display Font:** Archivo (variable, width 62% to 125%, weight 100 to 900), with Helvetica Neue and Arial
**Body Font:** Archivo, same file
**Label/Mono Font:** Hack Regular and Bold, with ui-monospace

**Character:** One grotesque in two widths. Condensed Archivo is the datasheet's nameplate voice for part numbers, section heads, table heads, and captions; normal-width Archivo is the reading voice. Hack sets source, compiler output, check ids, and kbd keys. All figures are tabular.

### Hierarchy
- **Display** (800, clamp(3.25rem, 9vw, 6rem), 0.88, width 70%): The part number: MZ-0.17 on the front sheet, "Rule 10.6", "Pin 40", "EVM 0.17". Also the package name in the pin map (22px) and the footer part number (1.5rem).
- **Title** (500, clamp(1.15rem, 2vw, 1.5rem), 1.3): The h1 beside the part number, max 40ch.
- **Headline** (700, 1.375rem, 1.2, width 78%): Numbered section heads; also the pager rule names.
- **Subhead** (700, 1.0625rem, width 78%): h3 within a section; the primary button label at 1rem.
- **Maker** (800, 1.3rem, width 75%, uppercase): "MISRA ZIG" in the running bar only.
- **Lede** (400, 1.1875rem, 1.6): A rule's Description paragraph.
- **Body** (400, 1.0625rem, 1.6; 1rem under 48rem): Prose at a 68ch measure.
- **Table** (400, 0.9375rem, 1.45): Table cells; 0.875rem in Characteristics and under 48rem.
- **Label** (700, 0.8125rem, 0.03em, uppercase, width 78%): Table head cells.
- **Caption** (400, 0.875rem): Figure captions in ink-2 with a bold condensed "Figure n-m." label; table captions are bold condensed 0.9375rem with a red-text "Table n-m." label.
- **Source** (Hack 400, 0.875rem, line 1.6rem, tab 4): Figures and the editor; 0.8125rem under 48rem.

### Named Rules
**The Condensed Nameplate Rule.** Condensed width is for names and numbers only: 70% for part numbers, 75% for the maker, 78% for heads, labels, captions, and pin names. Prose and table cells stay at normal width.

**The Numbered Caption Rule.** Every figure and table carries a bold condensed label numbered by its section ("Figure 2-1.", "Table 3-1."). Sections are numbered with a red-text numeral before the head.

## Layout

A single sheet column, max 84rem, centered, with a gutter of clamp(1rem, 4vw, 3rem). Fixed regions frame it on every sheet: the sticky running bar (min 3.25rem), the docline (doc number and revision left, the non-affiliation notice right, 0.8125rem condensed, 1px ink rule below), the part head, and the footer (part number and page, the check notice, JSON links, keyboard keys) under a 3px ink rule.

The front sheet sets Features and Description as two equal columns with a 3.5rem gap, then the pinout: the package figure (20rem to 34rem, sticky at 5rem) beside the Pin Functions table. A rule sheet is a main column beside a 19rem Characteristics aside, sticky at 4.5rem, with a 3.5rem gap; the aside carries a small package inset. Sections are spaced 2.75rem apart, figures 1.75rem, don't cases 2.25rem, and the pager sits 3.5rem below the last section.

At 64rem and below, the aside and the pin map drop under the main column, unsticky and capped at 30rem. At 48rem and below, the bar stops sticking and wraps with search on its own full-width line, the docline stacks, the part head and columns go to one column, the pin map scrolls sideways at 28rem behind a dashed hairline edge with a scroll hint, and check and findings tables restack each row as a grid.

## Elevation & Depth

The sheet is flat. Depth is drawn with rules, not light: 3px ink under the part head, above the pager, and above the footer; 2px ink at the top of every table and source figure and at the bottom of every table; 1px ink under section heads, table heads, and the docline; 1px hairline between rows. The bar stays above content by being sticky, not by a shadow.

### Shadow Vocabulary
- **Hit list drop** (`box-shadow: 0 0.75rem 2rem rgb(0 0 0 / 0.22)`): The search results list only, which also takes a 2px ink border. It is the one surface that floats over the sheet.

### Named Rules
**The Ruled Depth Rule.** Hierarchy between regions is the weight of the black rule (3px, 2px, 1px ink, 1px hairline), never a shadow or a tint panel.

## Shapes

Every box is square-cornered: buttons, inputs, the theme switch, figures, the editor, tables, the search list. Strokes are 1px, 2px, or 3px. The package drawing is a 2px ink rectangle with a half-circle notch and a pin-1 dot; legs are 14 by 5 rectangles; group brackets are 1.5px hairline square brackets with rotated uppercase labels. The maker mark and favicon are the same package glyph in 2px strokes. The resume flag is a red pennant cut from a rectangle.

## Components

### Buttons
- **Shape:** Square (0 radius), 2px border.
- **Primary:** Ink fill, sheet text, bold condensed 1rem, 0.02em tracking, 0.55rem by 1.1rem padding. Used for "Evaluate a file" and "Check with Zig".
- **Hover / Focus:** Fill and border go to red with white text. Focus is the global 2px red outline at 2px offset.
- **Disabled:** Head fill, hairline border, ink-2 text, progress cursor while a check runs.
- **Quiet:** No box. Red-text underlined text at 0.9375rem; the underline thickens from 1px to 2px on hover. Used for Edit and check, Restore, Copy, Close.

### Inputs / Fields
- **Search:** In the bar, 15rem, square, on-bar border at 55%, black 16% fill, white text and placeholder "Find a rule  /". On focus it turns to a sheet field with ink text, red caret, and a 2px white outline. Results drop below in a 32rem list with a 2px ink border, rows split into a condensed red-text id column (5rem) and the rule title, head-grey on hover.
- **Editor:** Source paper, hairline border with a 2px ink top, a 3.75rem gutter of line numbers with verdict shapes on lines that have a finding. The highlighted source sits under a transparent textarea; the focused editor takes a 2px red outline inset by 1px.

### Navigation
- **Running bar:** Maker mark and name, then two links (Contents, Evaluate a file) at 0.9375rem with a 2px white underline on hover and on the current sheet, then search, then the theme switch (Auto, Light, Dark; square, white 55% border, black 16% fill on hover).
- **Pager:** Two columns under a 3px ink rule: "Previous, pin n" and "Next, pin n" in small ink-2, the rule name in the headline style, turning red-text and underlined on hover.
- **Keys:** `/` finds, `[` and `]` page, Ctrl+Enter checks. kbd keys are Hack in a hairline box with a 2px bottom edge.

### Tables
- Full width, collapsed. Head row in Table Head Grey with uppercase condensed labels. Numeric columns right-aligned with tabular figures. Group rows inside the pin table are bold condensed with the pin span in ink-2. A row lit from the pin map takes Lit Row and its name turns red-text.

### Source figures
- Source paper, 1rem by 1.25rem padding, hairline border with a 2px ink top rule, caption below. Compiler output uses the same paper at 0.8125rem with wrapping.

### Pin map (signature)
The package drawing is the contents. Pins run down the left side and up the right, one per rule, bracketed by group. Hovering or focusing a pin fills its leg in red, turns its name red-text, turns its group bracket and label red, and lights its row in the Pin Functions table. Leg color moves in 160ms on cubic-bezier(0.22, 1, 0.36, 1); brackets in 160ms ease-out. The pin of the last-read rule keeps a red-text name. A rule sheet repeats the package as an unsticky inset with its own pin lit.

### Verdict marks
Shape first, color second: 0.7rem shapes (the tick 0.85rem, 0.55rem in the editor gutter) beside a 600-weight label:
- **Rejected by Zig:** filled ink square.
- **Compiles, and is still wrong:** hollow red square, 2px.
- **Flagged by misra-lint:** filled red diamond.
- **Review:** hollow amber diamond, 2px.
- **Left to a reader:** hollow ink-2 ring, 2px.
- **Compiler error:** filled ink disc.
- **Ok:** green tick drawn by an SVG mask.

### Characteristics
A two-column Parameter and Value table in the 19rem aside: pin, name, group, do samples, and one row per verdict shape with its count. Values right-aligned. Pending lint counts read "checking", and "n/a" when misra-lint is absent.

### Resume flag
Under the front part head: the red pennant, "You stopped at Rule n, group", and a link to resume.

## Do's and Don'ts

### Do:
- **Do** lead every sheet with a part number in the display style and number its sections with a red-text numeral.
- **Do** caption every figure and table "Figure n-m." or "Table n-m." in bold condensed.
- **Do** separate regions with ink rules of 3px, 2px, and 1px, and rows with the hairline.
- **Do** draw each verdict with its shape so it reads in monochrome.
- **Do** define new colors in both printings, light in `:root` and dark under `[data-theme="dark"]` and the `prefers-color-scheme` block.
- **Do** keep reduced motion: every transition and animation is cut under `prefers-reduced-motion: reduce`.

### Don't:
- **Don't** fill any region with red other than the running bar, the favicon, and the small verdict shapes and flag.
- **Don't** round corners. Circles are for the reader and error shapes and the pin-1 dot only.
- **Don't** add a shadow beyond the search hit list.
- **Don't** set prose or table cells in condensed widths.
- **Don't** mark a verdict with color alone.
- **Don't** add a docs sidebar; the pin map and pin table are the contents.
