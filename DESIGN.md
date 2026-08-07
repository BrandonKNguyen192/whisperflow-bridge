# komodos-ui — design language

The visual identity for **Whisper Flow Bridge** follows the *Komodos* design
language (as seen in *Komodos Links*). This file is the single source of truth
so every surface — the Mac web console, the Android app, and the workflow
mockup — stays visually consistent.

## Principles

1. **Warm-neutral canvas.** Surfaces are paper-like off-whites, never cold
   grays. Page `#FBFBF9`, panels/sidebar `#F6F6F3`, cards `#FFFFFF`.
2. **One accent: sage green.** Green is the affirmative/active color — primary
   buttons, links, selected pills, live status. `#2E7D46` on a pale tint
   `#E6F0E8`. Everything else stays neutral.
3. **Soft geometry.** Generous radii (cards 16, inputs 12, pills/chips/buttons
   fully rounded). Separation comes from **hairline borders** (`#E9E8E3`), not
   heavy shadows. Shadows, when used, are whisper-soft.
4. **Quiet typography.** A clean grotesque (Inter / system sans). Bold for
   titles, regular for body, muted gray for secondary. Section labels are
   **11px uppercase, letter-spaced, tertiary gray**.
5. **Pill & chip vocabulary.** Categories, tags, counts, toggles and buttons
   are all rounded pills/chips with light fills and right-aligned muted counts.
6. **Thin line icons.** Monochrome outline glyphs (Material "outline" family),
   tinted secondary gray; white when sitting on a green button.
7. **Signature gradient.** A thin `blue → green → amber` line
   (`#4C8DFF → #34C77B → #F2C14E`) used as a brand flourish under headers /
   card tops — the one place color is allowed to be loud.
8. **Calm density.** Airy spacing, content breathes, restrained palette. The
   neutral gray pill (`#8A887F`) is the *disabled/quiet* state; green is *go*.

## Tokens

| Token            | Hex       | Use                                  |
|------------------|-----------|--------------------------------------|
| canvas           | `#FBFBF9` | page background                      |
| surface          | `#F6F6F3` | sidebar / panels                     |
| card             | `#FFFFFF` | cards, inputs                        |
| border           | `#E9E8E3` | hairlines, input strokes             |
| ink              | `#1C1B19` | primary text                         |
| text-2           | `#6E6C66` | secondary text                       |
| text-3           | `#9A988F` | tertiary / micro labels              |
| green            | `#2E7D46` | accent / primary / links / live dot  |
| green-soft       | `#E6F0E8` | selected pill bg / callouts / icon bg|
| green-text       | `#2E7D46` | text on green-soft                   |
| chip             | `#F1F0EB` | tag / count chips                    |
| neutral          | `#8A887F` | disabled / quiet button              |
| grad-blue        | `#4C8DFF` | gradient stop 1                      |
| grad-green       | `#34C77B` | gradient stop 2                      |
| grad-amber       | `#F2C14E` | gradient stop 3                      |
| ok / err / idle  | green / `#D14343` / `#B6B4AC` | status states        |

Radii: card `16`, input `12`, pill `999`, thumb `10`.
Type scale: title `20–24/700`, label `11/600 uppercase +0.08em`, body `14–15/400`.

## Per-surface adaptation

- **Mac web console** mirrors *Komodos Links* literally: left sidebar (brand +
  nav with right-aligned counts + a `MODES` category list + footer), main column
  with a big rounded *compose* card, a search/sort row that filters the
  activity grid, and a grid of *recent send* cards (mode pill, gradient accent
  line, title, body, `#mode #source` chips, footer actions).
- **Android** is too narrow for a sidebar, so the same language is expressed as
  a top brand bar (mark + title + gear), the gradient accent line, then stacked
  white hairline cards (Connection / Compose) with pill buttons and a green-soft
  tip callout.
