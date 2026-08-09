# komodos-ui — design language

The visual identity for **Whisper Flow Bridge** follows the *Komodos* design
language (as seen in *Komodos Links*). This file is the single source of truth
so every surface — the Mac web console, the Android app, and the workflow
mockup — stays visually consistent.

As of the v1.2 branding refresh the identity leans **Apple-inspired**: system
typography with size-aware tracking, translucent "glass" materials on the web,
pure-black OLED support, hairline borders, generous whitespace, and motion that
starts on press and respects reduced-motion settings.

## Brand mark

The mascot is a smiling microphone under a blue → green → amber "bridge" arc
with a whisper sparkle. It renders in three places:

- **Launcher icon** — `android-app/app/src/main/res/drawable/ic_launcher_foreground.xml`
  on the themed `icon_bg` tile.
- **In-app mark** — `android-app/app/src/main/res/drawable/brand_mark.xml`
  on a `green_soft` tile.
- **Marketing kit** — editable sources plus PNG renders in `branding/`
  (`icon.svg`, `logo.svg`, `social-preview.svg`).

## Principles

1. **Warm-neutral canvas.** Surfaces are Apple-style neutrals. Page `#F5F5F7`,
   panels/sidebar `#EFEFF2`, cards `#FFFFFF`; dark mode is pure black `#000`.
2. **Accent system, sage by default.** Green is the default accent — primary
   buttons, links, selected pills, live status. `#2E7D46` on a pale tint
   `#E6F0E8`. Users can pick any preset or RGB accent, and every tinted surface
   (buttons, chips, sliders, blobs) derives from that accent.
3. **Soft geometry.** Generous radii (cards 16, inputs 12, pills/chips/buttons
   fully rounded). Separation comes from **hairline borders** (`#E9E8E3`), not
   heavy shadows. Shadows, when used, are whisper-soft.
4. **Quiet typography.** System sans first (`-apple-system` / Roboto). Display
   text carries tight negative tracking (`-0.02em` to `-0.03em`) and tight
   leading; body sits near `0` tracking with comfortable leading. Section
   labels are **11px uppercase, `+0.08em`, tertiary gray**.
5. **Pill & chip vocabulary.** Categories, tags, counts, toggles and buttons
   are all rounded pills/chips with light fills and right-aligned muted counts.
6. **Thin line icons.** Monochrome outline glyphs (Material "outline" family),
   tinted secondary gray; white when sitting on a green button.
7. **Signature gradient.** A `blue → green → amber` line
   (`#4C8DFF → #34C77B → #F2C14E`) used as a brand flourish under headers /
   card tops — the one place color is allowed to be loud.
8. **Calm density.** Airy spacing, content breathes, restrained palette.
   Materials are translucent on the web (`backdrop-filter` glass over content),
   hairline-separated, with soft layered shadows. Buttons respond on press
   (`scale .97`, 100ms) and respect `prefers-reduced-motion`.

## Motion

Motion starts on press and reinforces where the user's finger is:

- **Press:** scale `0.97` with a quick 100-150ms spring; haptics fire on the
  phone when a control confirms a change.
- **Entrance:** chips, cards, and sheet rows rise and fade in with a gentle
  stagger so the layout reads left to right.
- **Ambient:** a slow-drifting accent blob sits behind the glass surfaces so
  the frost has something alive to refract. It breathes on a multi-second
  ease-in-out loop and never moves fast enough to distract.
- **Platform:** Android implements these as Material 3 expressive springs
  (`MotionKit.kt`); iOS uses SwiftUI spring tokens (`Motion` in `Theme.swift`).
  Both collapse to instant under `prefers-reduced-motion`.

## Tokens

| Token            | Hex       | Use                                  |
|------------------|-----------|--------------------------------------|
| canvas           | `#F5F5F7` | page background                      |
| surface          | `#EFEFF2` | sidebar / panels                     |
| card             | `#FFFFFF` | cards, inputs                        |
| border           | `#E3E3E8` | hairlines, input strokes             |
| ink              | `#1D1D1F` | primary text                         |
| text-2           | `#6E6E73` | secondary text                       |
| text-3           | `#86868B` | tertiary / micro labels              |
| green            | `#2E7D46` | accent / primary / links / live dot  |
| green-soft       | `#E9F2EC` | selected pill bg / callouts / icon bg|
| green-text       | `#2E7D46` | text on green-soft                   |
| chip             | `#ECECF0` | tag / count chips                    |
| neutral          | `#8E8E93` | disabled / quiet button              |
| grad-blue        | `#4C8DFF` | gradient stop 1                      |
| grad-green       | `#34C77B` | gradient stop 2                      |
| grad-amber       | `#F2C14E` | gradient stop 3                      |
| ok / err / idle  | green / `#D14343` / `#B6B4AC` | status states        |

Radii: card `18`, input `14`, pill `999`, thumb `10`.
Type scale: display `34–56/-3%`, title `20–24/700/-2%`, label
`11/600 uppercase +0.08em`, body `14–15/400`.

## Per-surface adaptation

- **Mac web console** gets the product-page treatment: a display hero ("Talk.
  Type. Anywhere.") with the gradient flourish, a glass sidebar and glass cards
  (`backdrop-filter: blur(20px) saturate(180%)`), a pill segmented control,
  capsule send button, and scroll-reveal on cards. Dark mode is pure black
  glass; `prefers-reduced-motion` collapses reveals to instant.
- **Android** is too narrow for a sidebar, so the same language is expressed as
  a top brand bar (mark + title + gear), the gradient accent line, then stacked
  frosted glass cards (Compose, Mouse) over an ambient backdrop of drifting
  accent blobs. Cards, inputs, and the trackpad use translucent fills with
  white-alpha hairline borders; the Settings bottom sheet and dialogs get real
  window backdrop blur on Android 12+. Capsule buttons stay 56dp with centered
  labels, negative tracking on the brand title, and a soft tip callout. Pure
  OLED black stays `#000`.
- **iOS** carries the same identity through Liquid Glass: layered translucent
  materials on every surface, an ambient drifting background, spring chips and
  buttons, and system haptics. The iPad layout uses a sidebar for profiles and
  settings; the iPhone keeps the single-column Compose-first flow.
