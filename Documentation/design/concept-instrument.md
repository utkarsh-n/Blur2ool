# Blur2ool concept: Instrument-first

Date: 13 October 2026. Angle: **INSTRUMENT-FIRST / TOY-FIRST**. Author: design agent (senior product designer + graphics engineer).
Status: complete (sections 0–15). Probe scripts for the numbers in this file: `$TMPDIR/blur2ool-concept-instrument/gauss.py`, `others.py`.

Inputs, all read: `BRIEF.md`; `research/CATALOG.md` (canonical ids, tiers, pairs, corrections); `catalog-lsi.md`, `catalog-spatial.md`, `catalog-nonlinear.md`; `stack-semantics.md`; `gpu-pipeline.md`; `metro-adaptation.md`; `sdk-feasibility.md`; `live-calibration.md`. Visual references viewed: Metro Station `assets/visual-reference.png`, the Metro Station build-14 device screenshot (`Documentation/PhysicalQA/Build14/appearance-only/native-pair/5D948488….png`), ClassicalMLSimulator `Screenshots/workbench.jpg`, LosAlamosSimulator `Documentation/QA/Trinity.jpg`.

Honesty labels follow the brief: **LIVE, MEASURED, COMPUTED, MODELED, REFERENCE, INFERRED**. UNVERIFIED marks a claim nobody on the team has confirmed; it never appears on screen as a number. Every number in this document that comes from a research file keeps that file's label; numbers I derived for this concept are COMPUTED by the two probe scripts above. Where this concept knowingly departs from `metro-adaptation.md`, the departure is marked **DEPARTURE** with the reason.

---

## 0. One-line pitch

**A pocket optical bench: one machined metal specimen holding a live GPU blur that you twist with crowns, drag with a finger, wipe against its rivals and swap in one tap, and that opens downward, layer by layer, from the designer's slider to the exact pixel that came out.**

The app is a toy you pick up for the feel of the crown detents and the way city lights swell into hexagons, and it happens to be the most honest blur textbook on the phone. Learning is never a mode you enter. It is what you see when you look closer.

---

## 1. The first 10 seconds

The design target: within 10 seconds of a cold launch, without reading a word, he has (a) seen a beautiful blur, (b) changed it with his thumb and felt it, (c) swapped it for a different blur and noticed the *shape* change while the *size* stayed put, and (d) seen that there is something underneath. No onboarding carousel, no permission prompt, no splash.

| Time | What happens | Why |
|---|---|---|
| 0.0 s | The app opens straight onto the **Bench** (the root screen, §3.1). The specimen window shows **Night City**: a procedural HDR field of warm and cool point lights over dark buildings, in linear light (§11). The blur is `gaussian-blur` at σ = 12.0 px. The divider of the wipe comparison sits at 50 %: left half **INPUT** (sharp lights), right half **GAUSSIAN** (soft round glows). | The very first frame answers "what is a blur?" by showing before and after in one picture. Point lights are where blurs look best and differ most. |
| 0.0–0.6 s | First launch only: a one-shot **focus pull**. The right half eases from σ = 0 to 12 px over 600 ms (Metro "domain motion"; skipped under Reduce Motion). Pills draw their traces once; the hero numeral counts up to `12.0`. After that nothing moves until he touches something. | A blur has no clock (`metro-adaptation.md` §C.5), so there is no idle animation. One settle movement makes the instrument feel switched on. |
| ~1 s | The fixed-height status row in the readout band reads, once: `TURN A CROWN · DRAG THE IMAGE · SWIPE UP TO DESCEND`. It is replaced by the normal phase line after the first accepted interaction and never shown again (a Settings toggle can re-arm it). | One line of coaching in a slot that already exists (Metro §16 constant-height status row). |
| 2–4 s | He turns the **FINE** crown. Each 8° detent is ±0.1 px of σ with a crisp haptic (Metro §15: 0.78/0.95 up, 0.82/0.20 down). The glows breathe in real time; the KERNEL pill's bell widens; the FREQ pill's curve narrows toward DC; the hero reads `12.1`, `12.2` with monospaced digits that never shift. He flicks the **SEMANTIC** crown: it clunks between octave stops 8 → 16 px, and the serif meaning changes *Frosted* → *Backdrop*. | Two crowns, two feels: fine and named. This is the Metro Station signature move, mapped one to one. |
| 4–6 s | He drags the wipe divider (a 44-pt handle that owns its touch) across the city. | Comparison is physical. |
| 6–8 s | He taps the **hexagon glyph** in the Turret (the glyph strip under the title, §3.1). The right half becomes `polygonal-bokeh`: every light is now a crisp hexagon. The status row says `σ HELD 12.0 px → R 26.3 px`. The lights are the same *size* in the second-moment sense; only the *shape* changed. | σ-hold on switch (§8.1) is the single most important teaching rule in the app: when you switch, the size you chose is preserved, so what changes on screen is the blur's character. |
| 8–10 s | He notices the small round glass lens in the readout band whose face now shows a hexagon outline, and the floating glass button **Layers**. Swiping up on the readout band (or tapping Layers) slides the Bench up and away into the **Descent**: `LAYER 1 OF 7 · SLIDER`. | The depth is one swipe away and visibly *under* the instrument, not in another tab. |

What is deliberately absent in those 10 seconds: any menu, any explanation paragraph, any number without a label, any spinner. If the GPU is cold, the first frame is rendered before the window appears (pipelines precompiled at launch from `default.metallib`; `sdk-feasibility.md` §14 shows cold runtime compiles of 1–19 s, which is why runtime compilation is reserved for the Mac parity CLI).

---

## 2. Information architecture

Smallest useful set of screens. One root, one deep view, four sheets, all sheets from **one** `.sheet(item:)` destination enum (Toothpaste Toy's two-sheet failure, `metro-adaptation.md` §F.5 item 3).

```
Bench (NavigationStack root, does NOT scroll)
 ├─ in-place modes:  Compare (Wipe · Flip · Difference · Line-up), Loupe (long press), Probe (tap)
 ├─ push  → Descent (7 layers, vertical paging)          ← swipe up on the readout band, or "Layers"
 │            └─ Trace mode (same Descent, with the pixel thread and Back/Restart/Next)  ← "Trace a pixel"
 └─ sheet (one .sheet(item:))
      ├─ Fingerprint card     ← tap the kernel-well lens, or the blur name in the housing caption
      ├─ Catalog              ← long-press the Turret, or the "All" glyph at the end of the Turret
      │     └─ Lessons (P1–P30 from CATALOG §7 as one-tap A/B setups)
      ├─ Parameters           ← tap the hero numeral (every parameter of the current blur, native controls)
      └─ Field guide & Settings  ← header glass icon button
```

| Screen | Presentation | Purpose | Metro components |
|---|---|---|---|
| **Bench** | `NavigationStack` root, fixed layout, no `ScrollView` | Play: one live blur, crowns, wipe, switch | Environment, Specimen housing (primary object), KERNEL + FREQ signal pills, kernel-well lens (`InstrumentLensSurface` D = 88), large readout, telemetry row (`InstrumentMetricReadout` ×3 + honesty badges), crowns, floating glass action group, glass icon button |
| **Descent** | push with `NavigationTransition.crossFade` (iOS 27, `sdk-feasibility.md` §12) | Learn: the same blur at 7 layers, live | Periscope (mini specimen + hero + ± glass buttons), content panels, plot insets, pass tiles (event-tile grammar), honesty badges, layer rail |
| **Trace** | a mode of the Descent | Follow one output pixel through every layer | Same as Descent + bottom `safeAreaInset` Back · Restart · Next pass (AssemblerToy's accepted pattern) |
| **Fingerprint card** | sheet, `.medium` and `.large` detents | What makes this blur unique, in a fixed six-row card that is identical in layout for every blur | Content panel, 4-cell fingerprint strip (plot insets), badges |
| **Catalog** | sheet `.large`, `List` + `.searchable` | All 55 entries + 7 contrast entries by family; Lessons | Native List, Canvas footprint glyphs, cost chips |
| **Parameters** | sheet `.medium` | Every parameter of the current blur, with the native accessible control for each (Steppers, pickers, toggles), plus edge mode and colour space | `DecimalParameterStepper`, `InstrumentParameterStepper`, native `Picker` (`.tabs` style where it switches views), `Toggle` |
| **Field guide & Settings** | sheet `.large`, `NavigationStack` + `Form` + Done | Per-blur prose with citations; app settings; "the lens on this instrument" honesty note; device card | Content panels, Form |

**Why the Bench does not scroll (DEPARTURE from `metro-adaptation.md` §D.1–D.2).** The adaptation note puts the specimen inside a scrolling Lab and keeps the specimen tap-only so it does not steal the scroll pan. A toy needs the opposite: one-finger *drag on the image* is how you move a zoom centre, sweep a tilt-shift band, pan the city under a pyramid blur to see it shimmer, and paint a path for path blur. A drag on a third of the screen cannot coexist with a page scroll (Metro contract A.16: a touch that starts on a control belongs to it). So the Bench is a fixed instrument that fits one 430 × 932 screen, and everything that would have been "below the fold" (signal lab plots, pass tiles, cost charts) moves **down a layer** into the Descent, where it belongs anyway. At accessibility text sizes the Bench does become a scroll view and the drag gestures hand over to controls (§12).

---

## 3. Wireframes (iPhone 15 Pro Max portrait, 430 × 932 pt)

Grid: each wireframe is drawn about 64 characters wide, so one character ≈ 6.7 pt. Y coordinates on the left are screen points. Frames come from the Metro §5 cluster formula at 430 pt: inset 12, cluster 406, pill 36 × 212.5, D = 322, image window 298 × 298 pt = 894 × 894 px at scale 3 (COMPUTED in `metro-adaptation.md` §D.0). Safe areas 59 / 34 pt are the commonly published values and are UNVERIFIED (read them from `GeometryReader` on the device).

### 3.1 Bench, default (Gaussian on Night City, wipe at 50 %)

```
y    0 ┌──────────────────────────────────────────────────────────────┐
       │ 9:41               (  Dynamic Island  )              ▂▄▆ ▮  │ environment (canvas #060B0F + cyan wash 0.085 + 28-pt grid) under status bar
   59  ├──────────────────────────────────────────────────────────────┤
   69  │  Blur2ool                                          ( ⓘ )    │ title 27 pt semibold rounded · glass icon button 44×44 at x 362 → Field guide & Settings
       │  BLUR SIMULATOR · WYSIWYG → GPU                              │ subtitle 11 pt mono, tracking 2.6, white 0.68
  130  │ [▦] ┊ ● □ ⬡ ◯ ✺ ⟶ ◎ ↻ ◇ ▒ ⊞ ≋ ┊ ▫ ▫ ▫ ▫ ▫ ▫ ▫ … [All]   │ TURRET 44 tall: specimen Menu button 44 (x 12) + horizontally scrolling glyph strip x 64–418, glyphs 44×44, gap 6
  174  ├──┬───────────────────────────────────────────────────────┬───┤
  186  │K │ NIGHT CITY · LINEAR · +2 EV        A INPUT │ B GAUSSIAN │ F │ housing x 54, w 322, h 446, radius 30; caption row 11 pt mono in the 24-pt top margin
       │E │ ┌────────────────────────┬┬────────────────────────┐   │ R │
  210  │R │ │  ·    *     ·    ✶     ││  ○    ◯     ○    ◯      │   │ E │ image window 298×298 pt (894×894 px MTKView, LIVE)
       │N │ │      ✶   ·      *      ││      ◯   ○      ◯       │   │ Q │ wipe divider handle 44 wide (owns its touches), hairline at split
       │E │ │   *    ✛ probe    ·    ◀▶       ○      ◯         │   │   │ amber probe crosshair (tap to place)
       │L │ │  ·   ✶      ·     *    ││   ○   ◯      ○    ◯     │   │   │ ruler ticks in the 12-pt metal margins: minor 8 px, major 64 px
       │  │ └────────────────────────┴┴────────────────────────┘   │   │ pills 36 × 212.5 at x 12 / 382, centred on the window (y 252.75–465.25)
  516  │  │ SIGMA · PX                             ╭──────────╮    │   │ readout band y 516–620: unit line 11 pt mono tracking 2.2
       │  │ 12.0                                   │  ◎ well  │    │   │ hero 44 pt light rounded, monospaced digits, width reserved for "64.0"
       │  │ Frosted                                │  D 88    │    │   │ serif italic, instrument cyan
       │  │ 74 FETCHES · 2 PASSES · SEPARABLE      ╰──────────╯    │   │ phase/status row, fixed 14 pt; kernel well at x 276–364
  632  ├──┴───────────────────────────────────────────────────────┴───┤
  640  │  σ EFF            │  FETCHES / PX      │  GPU                 │ telemetry row 60: label caption2 mono · value title3 mono + unit · badge
       │  11.86 px         │  74                │  –.–– ms             │ dividers 1 × 30, white 0.10
       │  = COMPUTED       │  = COMPUTED        │  ⏱ MEASURED  n=30    │
  700  ├──────────────────────────────────────────────────────────────┤
  708  │        FINE                          SIGMA · Frosted         │ crown deck 98: captions 14 · gap 4 · crowns 62 · gap 4 · captions 14
       │   (−)( ◉ )(+)                     (−)( ◉ )(+)               │ each group 44 + 6 + 62 + 6 + 44 = 162; two groups + 24 gap = 348, centred
       │       ±0.1 PX                    Softened ⇆ Backdrop         │ cyan FINE crown · amber SEMANTIC crown (Metro §10)
  806  │                                                              │ 22-pt clearance
  828  │  ( ⧉ Compare )   ( ✛  Trace a pixel           )  ( ≋ Layers ) │ floating glass group, label frames 62×58 · flex × ≥58 (.glassProminent) · 54×58
  886  │                                                              │ GlassEffectContainer(spacing: 14), inset 22, bottom 12
  898  ├─────────────────────── home indicator (34) ───────────────────┤
  932  └──────────────────────────────────────────────────────────────┘
```

Notes on the Bench:

- **Turret** (new name for the blur selector, replaces the adaptation's 250-pt chip row). A horizontally scrolling strip of 44 × 44 Canvas glyphs, each the blur's footprint drawn exactly as on the kernel-well face, in instrument cyan on recessed metal. It scrolls horizontally, which does not conflict with anything because the Bench has no vertical scroll. Family boundaries are 1-pt engraved ticks. The selected glyph has the tile grammar's cyan fill 0.08 + border 0.35 *and* a 2-pt underline (colour plus shape, Metro §17). Order: the **Hero dozen** first (Gaussian, box, hexagon, disc, Kawase, zoom, spin, motion, bilateral, median, frosted glass, SwiftUI `.blur`), then every other entry that runs on the GPU (Tiers 1, 2 and S), grouped by family F1–F11, then the contrast group, then `[All]` which opens the Catalog. Tier 3 entries (CPU-only plots) live only in the Catalog; they are not toys.
- The **specimen button** (`[▦]`, 44 × 44) is a native `Menu`: specimen (§11), exposure (Night City only, 0 to +6 EV), colour space (Linear light / sRGB-encoded), edge mode (Clamp · Mirror · Wrap · Zero · Renormalize), and "Photo…" (`PhotosPicker`, no permission needed, `sdk-feasibility.md` §10).
- The **housing caption** carries the engraved provenance (`LIVE · METAL`, or `LIVE · SWIFTUI` for Tier S, `MODELED` for a reconstruction) in its right half when not comparing, and the `A …│ B …` labels when comparing. Engravings never sit on pixels (Specimen rule, `metro-adaptation.md` §C.1).
- **Telemetry** stays on the Bench (DEPARTURE: the adaptation placed it below the fold). It is the honesty spine of the toy: what you are looking at, how much it cost, measured on this phone. GPU time shows `–.––` until 30 warmed frames exist and in the Simulator it is struck through with `SIMULATOR · NO GPU TIMING` (`gpu-pipeline.md` §2.7).
- **No Stepper on the Bench** (DEPARTURE from Metro §9 placement). The ± glass buttons on each crown are native `Button`s with `accessibilityAdjustableAction`, so the crown deck already carries its own non-gesture alternative (Metro §8, §18). The `DecimalParameterStepper` and every integer Stepper live in the Parameters sheet one tap away (tap the hero). This keeps the smallest component set on the Bench and buys back 60 pt for telemetry.
- **Floating group**: `Compare` (left; becomes `Done` while comparing; its context menu picks the comparison mode), **Trace a pixel** (primary, cyan idle, amber while a trace or an auto-sweep runs), `Layers` (right). Three controls only (AssemblerToy build-6 lesson). The specimen is never under the glass group in the Bench's fixed layout (clearance 22 pt).

### 3.2 Bench in Compare mode, Line-up (4-up) variant

```
  174  ├──┬───────────────────────────────────────────────────────┬───┤
  186  │K │ LINE-UP · σ HELD 6.0 px · SIEMENS STAR (36 CYCLES)    │ F │ caption row
       │E │ ┌───────────────────────┬───────────────────────────┐ │ R │
  210  │R │ │ A  BOX  w 21          │ B  TENT  r 14             │ │ E │ four quadrants 149×149 pt (447×447 px), engraved letter + name in a
       │N │ │   (square rings,      │   (grey null rings,       │ │ Q │ 14-pt black band at each quadrant's top edge, outside the pixels
       │E │ │    reversed spokes)   │    no reversal)           │ │   │
       │L │ ├───────────────────────┼───────────────────────────┤ │   │
       │  │ │ C  GAUSSIAN σ 6.0     │ D  DISC  R 12.0           │ │   │ KERNEL pill: four traces, A solid, B dashed, C dotted, D dash-dot
       │  │ │   (smooth fade)       │   (round reversed ring)   │ │   │ FREQ pill: four |H| curves, negative lobes in spectrum magenta
       │  │ └───────────────────────┴───────────────────────────┘ │   │
  516  │  │ SIGMA · PX (ALL FOUR)                 ╭──────────╮    │   │ the hero drives all four; σ-hold converts per blur (§8.1)
       │  │ 6.0                                   │ well: A  │    │   │ the well shows the footprint of the quadrant last tapped
       │  │ Softened                              ╰──────────╯    │   │
       │  │ MIN MTF  A −0.217 · B 0 · C 0 · D −0.132              │   │ status row in comparison: the distinguishing number (COMPUTED)
  632  ├──┴───────────────────────────────────────────────────────┴───┤
  640  │  ΔGPU  (B−A)       │  ΔFETCHES          │  MAX |A−C|          │ telemetry switches to differences
       │  –.–– ms           │  ±– / px           │  –– /255            │ (values here are illustrative placeholders, not results)
       │  ⏱ MEASURED        │  = COMPUTED        │  ● LIVE             │
```

The equal-σ widths come from the CATALOG conversions: box w = √(12σ² + 1) → 21 (σ 6.06), tent r ≈ √(6σ² + 1) − 1 = 13.7 → 14 (σ = √(r(r+2)/6) = 6.11), disc R = 2σ = 12 (COMPUTED). The status row shows the one number that tells them apart: the deepest MTF value (box −0.217, tent ≥ 0, Gaussian > 0, disc −0.132; CATALOG §5.2, CHECKED).

### 3.3 Bench with a spatial blur: zoom (radial) blur, centre handle

```
  186  │K │ IMPULSE GRID · ZOOM · INWARD           LIVE · METAL   │ F │
       │E │ ┌────────────────────────────────────────────────┐   │ R │
  210  │R │ │  ╲   ╲    │    ╱   ╱      rays point at the    │   │ E │ PSF field visible: streak length grows with distance
       │N │ │   ╲  ╲    │   ╱  ╱        centre; length ∝ r   │   │ Q │
       │E │ │ ──── ─  ⊕ centre ─ ────                        │   │   │ ⊕ = centre handle: 44-pt hit target, owns the drag; amber ring
       │L │ │   ╱  ╱    │   ╲  ╲                ✛ probe       │   │   │ ✛ probe placed by tap (here at 747, 447 px)
       │  │ │  ╱   ╱    │    ╲   ╲                            │   │   │ FREQ pill: "LOCAL @ PROBE" (local MTF, sinc along the ray)
       │  │ └────────────────────────────────────────────────┘   │   │
  516  │  │ STRENGTH · %                          ╭──────────╮    │   │
       │  │ 20.0                                  │ rays     │    │   │ well face: radial rays from a centre dot
       │  │ Rush                                  ╰──────────╯    │   │ named bands for zoom: Drift < 5 · Rush 5–25 · Warp > 25 (descriptive, Blur2ool's own)
       │  │ 32 SAMPLES · CORNER GAP 4.08 PX · GHOSTS               │   │ status row warns when tap spacing at the far corner > 1 px (COMPUTED)
  632  ├──┴───────────────────────────────────────────────────────┴───┤
  640  │  STREAK @ PROBE    │  FETCHES / PX      │  GPU                │
       │  60.0 px           │  32                │  –.–– ms            │
       │  = COMPUTED        │  = COMPUTED        │  ⏱ MEASURED         │
  708  │        STRENGTH                        SAMPLES               │ deck variant: FINE crown + integer Stepper (counts use Steppers)
       │   (−)( ◉ )(+)                 [ SAMPLES   −  32  + ]        │ InstrumentParameterStepper 48 tall, ≤ 170 wide
       │       ±0.5 %                  [ IN · CENTRED · OUT ]        │ native segmented Picker 32 tall (direction; OUT = Core Image's convention)
```

One-finger drag on the image moves the centre handle if the drag starts within 44 pt of it; anywhere else it **pans the specimen** under the blur. Pan is the toy for spatial variance: the impulse grid slides and its streaks re-orient live. For blurs without a handle, pan is the toy for *shift* variance: under `pyramid-blur` (plain mip) the lights visibly snap to a coarse grid (PSF centroid jumps up to ±7.5 px at L = 4, CATALOG §2 row 10), under `dual-kawase` they shimmer, under `gaussian-blur` nothing changes except position. That one gesture teaches shift invariance better than any paragraph.

### 3.4 Descent (layer page; Gaussian, layer 4 of 7)

```
y   59 ├──────────────────────────────────────────────────────────────┤
   69  │ ‹ Bench          GAUSSIAN · LAYER 4 OF 7                     │ inline nav title; back returns to the Bench (crossfade)
  113  │ ┌──────────────┐ SIGMA · PX                       (−) (+)    │ PERISCOPE 130 tall, pinned: live mini-specimen 120×120 pt
       │ │ live mini    │ 12.0       Frosted                         │ (same texture, cropped around the probe), hero 34 pt, ± glass buttons 44
       │ │ specimen ✛   │ PROBE (453, 447) · IN 1.000 → OUT 0.707 lin  │ probe line: Trace values always visible (§6)
  243  │ └──────────────┘                                            │
  255  │ ┌────────────────────────────────────────────────────────┐ ▲│ content panel (radius 22, fill 0.85, border 0.09), x 12–394
       │ │ LAYER 4 · DISCRETE KERNEL                  = COMPUTED  │ ①│ LAYER RAIL at x 400–424: 7 stops, each a 44-pt-tall target,
       │ │ GOVERNING RULE                                        │ ②│ amber dot = probe has passed through, cyan = current
       │ │ g[n] = exp(−n²/2σ²) / Σ ,  |n| ≤ ⌈3σ⌉ = 36             │ ③│
       │ │ ┌──────────────── plot inset 374 × 140 ───────────────┐│ ④│ Swift Charts: 73 stems (explicit 2-pt width) over the continuous curve
       │ │ │  stems w[n], n = −36 … +36; continuous G (quiet)     ││ ⑤│
       │ │ └──────────────────────────────────────────────────────┘│ ⑥│
       │ │ w₀ 0.03332 · w±12 0.02021 · w±24 0.00451 · w±36 0.00037 │ ⑦│
       │ │ 73 taps · mass dropped 0.27 % · σ of kernel 11.86 px    │  │
       │ │ ▸ Discretization: Sampled · Integrated · Lindeberg     │  │ native Picker; at σ = 12 the three differ invisibly (COMPUTED), at σ 0.3 wildly
       │ │ ▸ Data table (73 rows)                                  │  │ DisclosureGroup: accessible table for every plot
       │ └────────────────────────────────────────────────────────┘ ▼│
       │        swipe up ↑ LAYER 5 · PASSES      swipe down ↓ LAYER 3 │ vertical paging between layers
  898  └──────────────────────────────────────────────────────────────┘
```

The Descent is one vertical paging `ScrollView` (`.scrollTargetBehavior(.paging)`), one page per layer, each page a content panel sized to the viewport below the periscope. The periscope's mini-specimen is the same Metal texture, drawn into a second small `MTKView` region (no glass on it). Its ± buttons change the primary parameter, so you can stand on layer 6 and watch the dispatch grid and fetch counts update as σ moves.

### 3.5 Trace mode (Descent with the pixel thread; Gaussian at layer 5)

```
   69  │ ‹ Bench      TRACE · PIXEL (453, 447)                       │
  113  │ ┌──────────────┐ COMPLETED  Horizontal pass                  │ amber = what already happened
       │ │ 9×9 texels   │ NEXT       Vertical pass                    │ cyan  = what the next tap does (AssemblerToy guide split)
       │ │ around probe │ IN  1.000 1.000 1.000  (linear)             │
       │ │ amber weights│ AFTER H 0.707 · OUT 0.707 (= 219/255)       │ step edge is vertical, so the V pass leaves this pixel unchanged
  243  │ └──────────────┘                                            │ the 9×9 neighbourhood is a COPY (112×112 pt), never drawn on the specimen
  255  │ [ L1 ][ L2 ][ L3 ][ L4 ]                                     │ layer selector grid 4 + 3 tiles, ≈ 95 × 54, gap 8 (AssemblerToy)
       │ [ L5 ][ L6 ][ L7 ]                                          │
  379  │ ┌ LAYER 5 · PASSES ─────────────────────────────────────┐   │ the selected layer's primary facts only
       │ │ PASSES                                       1 / 2     │   │ pass tiles: 37 tall, radius 8; completed amber, next cyan
       │ │ [ H  ▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮ 37 ]  [ V  ▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮ 37 ]  │   │ markers: fetches per pixel (cap 16 marks + number)
       │ │ Fetch 1 of 37: offset 0 · weight 0.03332 · value 1.000│   │ stepping fetch by fetch with Next
       │ │ ▸ All pass details                                     │   │ DisclosureGroup
  836  │ └────────────────────────────────────────────────────────┘   │
  840  │ [ ‹ Back ]        [ ⟲ Restart ]        [ Next fetch › ]     │ safeAreaInset(edge: .bottom), 58 tall, native buttons
```

### 3.6 Fingerprint card (sheet, `.large`; Gaussian)

```
   ~90 │ ─────  (grabber)                                             │
       │ GAUSSIAN BLUR                                F2 · GAUSSIAN & │ largeTitle rounded semibold; family eyebrow
       │ TRUE BLUR · LSI · SEPARABLE · ISOTROPIC          APPROXIMATIONS │ verdict chips (CATALOG §1 vocabulary)
       │ "The only blur that is both round and separable; it fades     │ signature, serif italic, from CATALOG master table
       │  every detail smoothly and never inverts phase."               │
       │ ┌──────────┬──────────┬──────────┬──────────┐                 │ FINGERPRINT STRIP: 4 plot insets 88×88, identical axes for every blur
       │ │ PSF      │ STAR     │ EDGE     │ |H|      │                 │ PSF (log intensity) · Siemens star crop · step ESF · MTF 0–0.5 c/px
       │ │  ( ◍ )   │ (smooth) │  ╱‾      │ ╲__      │                 │ all at the σ-held size, so any two cards line up
       │ └──────────┴──────────┴──────────┴──────────┘                 │
       │ PSF SHAPE     round bell, no rim; kurtosis 3.0      = COMPUTED│ six rows, fixed order, fixed heights
       │ |H|           exp(−2π²σ²ν²); no zeros; half at 0.1874/σ = …   │
       │ EDGES         erf S-curve, 10–90 % = 2.563σ, no overshoot     │
       │ COST          O(r) separable · O(1) via IIR / pyramid         │
       │ ARTIFACTS     square support if truncated hard on HDR lights  │
       │ USED IN       CSS blur(), CIGaussianBlur, MPS, Photoshop, …   │ REFERENCE rows link to the Field guide citations
       │ ┌ TELL ─────────────────────────────────────────────────┐    │
       │ │ Siemens star: no reversed rings, perfectly round grey   │    │ the one test that gives it away; "Show me" sets the Bench
       │ │ disc.                                   [ Show me ]     │    │
       │ └────────────────────────────────────────────────────────┘    │
       │ NEAREST NEIGHBOURS   box (inverts) · binomial (0 at Nyquist)  │ tap → Bench in Wipe against that blur at held σ
       │                      · iterated-box (1 % lie)                  │
```

### 3.7 Catalog (sheet, `.large`)

```
       │ Catalog                                   [ Search ⌕ ]       │ native List, .searchable
       │ [ Blurs · Lessons · Not blurs ]                               │ Picker(.tabs) (iOS 27: segmented look, tab semantics)
       │ F1  BOX, TENT & RUNNING SUMS · 4                              │ section header: eyebrow + count
       │ ┌──┐ Box blur                                       [O(1)]   │ rows ≥ 64: 40×40 footprint glyph · name (body semibold) ·
       │ │□ │ The honest average: flat and square …           TIER 1   │ one-line signature (caption mono) · cost chip · tier chip
       │ └──┘                                                          │
       │ ┌──┐ Tent (triangle) blur                           [O(1)]   │ selected row: cyan checkmark + isSelected trait
       │ │◇ │ Two boxes stacked: zeros but never negative …    ✓        │
       │ …                                                             │
       │ F9  DIFFUSION (PDE) · 3                                       │
       │ ┌──┐ Coherence-enhancing diffusion            [ITER] TIER 3   │ Tier 3 rows open an atlas page (CPU plots on a 128² crop),
       │ │≈ │ Heat that flows along the grain …          ATLAS ONLY     │ not the Bench
```

The Lessons tab lists CATALOG §7's pairs P1–P30, each one tap: it loads the specimen, sets A and B, sets the comparison mode and the held σ, and returns to the Bench with the status row showing the number to look for ("MIN MTF −0.217 vs > 0").

### 3.8 Parameters (sheet, `.medium`; bilateral)

```
       │ Bilateral · parameters                                 Done  │
       │ ┌───────────────────────────────────────────────────────┐    │
       │ │ SPATIAL σs        [  −   3.0 px   +  ]                 │    │ DecimalParameterStepper, Int tenths, 0.5–8.0 px
       │ │ RANGE σr          [  −   0.10     +  ]                 │    │ DecimalParameterStepper, Int hundredths, 0.01–1.00 (of full scale)
       │ │ WINDOW r          [  −   8 px     +  ]   = ⌈2.67 σs⌉   │    │ InstrumentParameterStepper; "auto" toggle ties it to σs
       │ │ ALGORITHM         [ Brute · Separable · Grid ]          │    │ native segmented Picker (variant ids, CATALOG §2)
       │ │ RANGE SPACE       [ Luma · RGB · Lab ]                  │    │
       │ └───────────────────────────────────────────────────────┘    │
       │ ┌ EVERY BLUR ───────────────────────────────────────────┐    │
       │ │ EDGE MODE    [ Clamp · Mirror · Wrap · Zero · Renorm ] │    │
       │ │ COLOUR SPACE [ Linear light · sRGB-encoded ]            │    │
       │ │ PRECISION    [ float accum · half accum ]               │    │ half accumulators are a lesson, not a default (gpu-pipeline §3.8)
       │ │ PREVIEW      [ Full res · Half while turning ]          │    │
       │ └───────────────────────────────────────────────────────┘    │
```

### 3.9 Field guide & Settings (sheet, `.large`)

A `NavigationStack` + `Form` + Done, as the adaptation specifies (§C.11): the current blur's field-guide page (definition, every figure with its badge, citations in full), "The lens on this instrument" (the Liquid Glass honesty note, §10.3), the **Device card** (GPU family, threadgroup memory, threads per threadgroup, SIMD width, bilinear sub-texel bits, `generateMipmaps` impulse, copy bandwidth, counter sampling points: all MEASURED on the phone by a one-time probe, each with its Feature Set Tables value beside it as REFERENCE; `gpu-pipeline.md` §5 item 7), and settings (haptics, coaching line, badge verbosity, Simulator warning). No wireframe beyond this: it is a stock Form in Metro panels.

### 3.10 The Liquid Glass exhibit (Bench, `liquid-glass` selected)

When the Turret selects `liquid-glass` (or `apple-uiblureffect`), the specimen switches from the `MTKView` to a **SwiftUI-drawn** copy of the specimen so the system glass samples known content (`metro-adaptation.md` §C.2). A native glass shape (rounded rectangle 180 × 120 pt, `.regular` or `.clear`, picked in Parameters) floats over it at full opacity, draggable by its own 44-pt handle (it is the subject, not the Metro lens). The housing caption reads `LIVE · SYSTEM GLASS · INFERRED`. The wipe's B side is our MODELED Metal reconstruction (half-res capture, Gaussian radius 5, SDF refraction band, CATALOG row 48). The pills read `INFERRED — NOT EXPOSED` for A and show the model's curves for B. This is the only place glass is allowed over the specimen.

---

## 4. The primary object: the Specimen instrument

One object, always on screen on the Bench: a rectangular, opaque, machined housing that holds a live GPU image. It follows Metro §8's seven-part anatomy exactly as `metro-adaptation.md` §C.1 maps it (rectangle rather than round gauge, because blurs are judged on square pixel grids and the hero numeral must not cover the pixels; Los Alamos's `TRINITY / OBSERVATION 01` and AssemblerToy's display instrument are the accepted precedents). What this concept adds is the toy layer on top of that anatomy.

| Part (Metro §8) | Blur2ool | Toy behaviour |
|---|---|---|
| 1. Housing + inset face | 322 × 446 pt, radius 30, `metalLight → metalDark`, 1.4-pt four-stop rim, shadow black 0.8 r22 y16, built from tokens (not AssemblerToy's drifted literals) | none: it is the still frame around the play |
| 2. Calibration marks | Engraved pixel rulers in the 12-pt metal margins (minor every 8 px = 2.67 pt, major every 64 px = 21.3 pt); amber bracket on the top ruler showing the kernel's support (±3σ = ±36 px for the Gaussian example); `SCALE 1 px = 0.33 pt` engraved bottom-left, derived from `displayScale`, never hard-coded | the support bracket slides as you turn a crown, so you see the kernel's reach against the ruler |
| 3. Mechanism | The **image window** 298 × 298 pt, an `MTKView` of exactly 894 × 894 px (not full screen; Toothpaste Toy precedent: ≈ 3× fewer pixels, and GPU timing stays about the blur) | **tap** = place probe · **one-finger drag** = move the blur's handle if the touch starts within 22 pt of it, else pan the specimen · **long press** = loupe · **pinch** = pixel zoom 1×–8× nearest-neighbour (the blur is computed at 1×; zoom only magnifies the result, and the scale engraving updates) · **two-finger double tap** = reset view |
| 4. Dominant readout | Hero numeral of the blur's declared primary parameter (σ, R, length, strength, iterations, σs…), 44 pt light rounded, monospaced digits, width reserved for the widest legal value | tap the hero → Parameters sheet |
| 5. Units + meaning | Unit line (`SIGMA · PX`, `STRENGTH · %`, `RADIUS · PX`, `ANGLE · DEG`) and a serif-italic meaning from the blur's named bands (σ: *Sub-pixel* < 0.5 · *Anti-alias* 0.5–1.5 · *Softened* 1.5–4 · *Frosted* 4–12 · *Backdrop* 12–32 · *Fog* > 32; these names are Blur2ool's own, not a standard, `metro-adaptation.md` §G.1 item 7) | the SEMANTIC crown's detents land on band boundaries, and the meaning word changes with a one-shot 1.0 → 1.04 → 1.0 lens bounce (Metro §13) |
| 6. Phase / status | One fixed 14-pt row: normally `74 FETCHES · 2 PASSES · SEPARABLE`; while the GPU is behind the request `RENDERING… PASS 2/2`; during a pass walk `PASS 1/2 · HORIZONTAL`; after a switch `σ HELD 12.0 px → R 26.3 px`; for LSV blurs a sampling warning `CORNER GAP 4.08 PX · GHOSTS` | the row is the toy's quiet narrator; it never grows |
| 7. Fixed interaction region | The window is the interaction region; its touches are owned by the instrument because the Bench does not scroll (§2) | accessible alternatives in §12 |

**Handles.** Spatial blurs declare zero to two handles drawn as amber engraved rings *on a SwiftUI overlay above the `MTKView`* (foreground, never sampled by the blur): zoom/spin/god-rays centre ⊕; tilt-shift focus band (two parallel lines, drag the band, drag either line for width); iris-blur ellipse (centre + one radius knob); path blur (draw mode: the drag paints a Bézier path instead of panning; a `Paint · Pan` segmented toggle in the deck decides). Handles are 44-pt hit targets and each has an accessible adjustable action (move ±8 px per step) and a `Reset` action.

**The probe.** An amber crosshair (instrument amber `#FFB84F`, 1-pt lines, 13-pt arms with a 3-pt gap) placed by tap, default at the window centre. It is the shared cursor of the whole app: the KERNEL pill draws the *local* weights at the probe for adaptive and LSV blurs, every Descent page shows the probe's value at that layer, and Trace follows it.

**The loupe.** Long-press shows an opaque **Metal** loupe (never glass: a glass loupe would add the system's own refraction to the pixels being inspected; `metro-adaptation.md` §F.5 item 2): a 112 × 112 pt square with a 1.4-pt metal rim, floating 84 pt above the finger, showing 14 × 14 texels at 8 pt per texel with nearest-neighbour sampling, and the centre texel's linear RGB printed under it in 11-pt mono (`0.707 0.707 0.707 · LIVE`). Lift to dismiss. This is the "pixel peeper" that makes the box blur's reversed stripes and the binomial's dead-flat checkerboard *visible to the eye*, not just in a plot.

**The kernel well (the isolated glass lens).** D = 88 pt at the trailing end of the readout band, `InstrumentLensSurface` unmodified: `.glassEffect(.clear, in: .circle)` on a 67-pt frame (0.76 D), constant opacity 0.48 (1.0 under Reduce Transparency), centre fixed, optics shader off in v1 (`metro-adaptation.md` §G.1 item 2: at D = 88 the warp would be 2.2 pt and the RGB split 0.27 pt). Under it, a decorative `Canvas` engraves the blur's 2-D footprint, the domain mechanism:

| Blur | Well face (engraved, instrument cyan on recessed metal) |
|---|---|
| `gaussian-blur` | rings at 1σ, 2σ, 3σ; tap dots on the axes sized by weight |
| `box-blur`, `sat-box` | a square outline; four corner dots for SAT's 4 reads |
| `disc-blur` | a circle; `polygonal-bokeh` an n-gon at the current rotation, split into its three rhombi by faint lines |
| `radial-zoom-blur` | rays from a centre dot; `spin-blur` concentric arcs |
| `linear-motion-blur` | a hard-ended segment at the current angle; `anisotropic-gaussian` a soft-ended ellipse |
| `kawase-blur` | the four diagonal taps per pass, current pass in amber |
| `bilateral`, `median`, other adaptive | a ring with a notch, plus the engraving `DATA-DEPENDENT` **outside** the well (labels never sit under glass, QuantumToy lesson) |

Tap the well → Fingerprint card. The lens never moves, never grows past 1.04×, never carries a number.

**Signal pills.** KERNEL (wave primary `#4FDBFF`) and FREQ (spectrum primary `#C291FF`), 36 × 212.5 pt, static 0.8-pt enclosures, flanking the window and centred on it, exactly as `metro-adaptation.md` §C.5 specifies (taps run downward from −extent to +extent in KERNEL; frequency runs upward from DC to Nyquist in FREQ; negative lobes in spectrum depth `#F55CD6`; the −3 dB marker in carrier amber). Interior traces ease to the new shape in ≈ 150 ms on an *accepted* change and otherwise stay still. This concept's additions:

- **LSV blurs** (zoom, spin, motion fields, tilt-shift, variable): both pills switch their title line to `LOCAL @ PROBE` and draw the local PSF profile and local MTF at the probe. Move the probe, the pills change. That is the honest replacement for a global MTF (`catalog-spatial.md` §0).
- **Adaptive blurs** (bilateral, guided, Kuwahara, diffusion): KERNEL draws the LIVE weight row through the probe (the effective PSF there). FREQ draws the **amplitude-dependent transfer** T(ν, A) evaluated at the local contrast A measured around the probe, titled `T(ν, A 0.20)`, instead of an empty `N/A`. For rank filters (median) FREQ engraves `N/A · RANK` and its interior shows nothing (honest empty state, Metro §16).
- **Comparison**: A solid, B dashed (shape as well as colour, Metro §17).

---

## 5. The layer descent (WYSIWYG → GPU), with worked examples

### 5.1 The seven layers and how they are presented

The layers are those of `metro-adaptation.md` §C.10, kept in the same order so the Descent reads top to bottom as "what you asked for → what you got":

| # | Layer | The question it answers | What the page shows (always LIVE against the current parameters) |
|---|---|---|---|
| L1 | **SLIDER** (WYSIWYG) | What did the designer type, and in which tool? | A row of **tool chips** (SwiftUI · CSS · Figma · Sketch · Photoshop · Core Image · Android · Flutter) each showing what *that* tool would need you to type to get the σ you have now, plus the reverse ("you typed 10 in Figma: σ = 5"). For SwiftUI, a **live SwiftUI view** with `.blur(radius:)` rendered next to our Metal result and fitted on device (Tier S). |
| L2 | **API** | What does the API call's parameter mean, in which units, colour space and edge policy? | The call as code text; unit chain (pt → px at scale 3); colour space; edge policy; the API's measured σ law with its badge. |
| L3 | **MATH** | What is the continuous operator? | The definition; its transfer function; the derived numbers (FWHM, half-amplitude frequency, −3 dB frequency, zeros); properties as chips (linear, LSI, separable, isotropic, semigroup, positive). |
| L4 | **KERNEL** | What did discretization do to it? | The discrete taps as stems over the continuous curve; truncation, mass dropped, actual σ of the kernel; discretization picker; for LSV blurs a **PSF field** (7 × 7 local PSFs at their positions, like a lens spot diagram); for adaptive blurs the weight map at the probe. |
| L5 | **PASSES** | How is it computed, and what does the image look like between passes? | Pass tiles (event-tile grammar); tapping a tile shows that pass's intermediate texture in the periscope (the half-blurred horizontal streak of a separable Gaussian is the money shot); fetch counts per algorithm with the Cost plot (fetches/px vs size, measured GPU-ms dots overlaid). |
| L6 | **METAL** | What actually runs on the A17 Pro? | The shader source text (the same string that is compiled; `gpu-pipeline.md` §5 item 1); dispatch geometry drawn over the image (threadgroups, SIMD-groups, apron); threadgroup memory; bytes moved (MODELED) vs time (MEASURED); precision; for system blurs an **INFERRED lane** (render server, QuartzCore kernel names). |
| L7 | **PIXELS** | What came out at the probe, and is it right? | The probe's input and output values in linear and encoded form; GPU vs CPU reference difference (`BlurCore`), in 8-bit LSB and fp16 ulps. |

Presentation rules: one page per layer; each page is a single content panel with eyebrow `LAYER n OF 7 · NAME`, a `GOVERNING RULE` line (callout mono, cyan), one figure (plot inset 374 × 140, Swift Charts or Canvas), at most six primary numbers each with a badge, and an `All … details` disclosure (AssemblerToy GD-1 fix). The periscope (live mini-specimen + hero + ± buttons) is pinned above all pages, so the image never leaves the screen while you descend.

### 5.2 Worked example A: Gaussian (`gaussian-blur`)

Set-up: SwiftUI's `.blur(radius: 4)` is the designer's intent; Blur2ool runs its own Gaussian at the nominal σ that call implies on this phone. Specimen: vertical **step edge** (black for x < 447, white for x ≥ 447 in the 894-px texture), probe at (453, 447), 6 px into the white side. All numbers COMPUTED by `gauss.py` unless labelled otherwise.

| Layer | What it displays | Real numbers |
|---|---|---|
| L1 SLIDER | SwiftUI chip selected: a live 120 × 120 pt SwiftUI view with `.blur(radius: 4)` beside our Metal output at the same scale; the other chips show the equivalent typed values | Same blur, other tools: CSS `filter: blur(4px)` (σ = value, REFERENCE, Filter Effects 1); Figma layer blur **8** (σ = value/2, REFERENCE second-hand via the Figma staff forum reply, so INFERRED for Figma's renderer); `CIGaussianBlur` radius **12** on a device-pixel image (σ = r, MEASURED macOS); Android `RenderEffect` radius **19.9** px (σ = 0.577r + 0.5, REFERENCE Skia/AOSP source); CSS `box-shadow` blur **8** (σ = value/2, REFERENCE). The "radius = 10 means 16 things" table from `stack-semantics.md` §8 is one disclosure away. |
| L2 API | `Text("…").blur(radius: 4)` as code; unit chain `4 pt × 3 = 12 px nominal σ`; colour mode `.nonLinear` → averages **gamma-encoded** values; `opaque: false` → decal edges (fades to transparent, spills outside the frame) | Nominal σ 12.0 px (REFERENCE: Apple documents radius = standard deviation only for `GraphicsContext.Filter.blur`). Measured law: σ ≈ 0.90·r·scale above ≈ 5 device px, box³-like kernel (excess kurtosis −0.45) with up to 1.2–1.4 px edge wobble (MEASURED on macOS 27.2, `live-calibration.md` §5.1), so on this phone **≈ 10.8 px is INFERRED** until `measurePSF` runs on the device, after which the badge flips to MEASURED and shows the device name. Note the two research files read the same large-radius kernel differently (truncated Gaussian, `sdk-feasibility.md` §4; box³-like, `live-calibration.md` §5.1); both give σ ≈ 0.90–0.91 r and kurtosis ≈ 2.55, so the page shows the measured numbers and labels the *shape interpretation* INFERRED. Blur2ool's own Gaussian: σ = 12.0 px, linear light, clamp edges. |
| L3 MATH | G(x) = e^(−x²/2σ²)/(σ√2π); Ĝ(ν) = e^(−2π²σ²ν²); property chips: LINEAR · LSI · SEPARABLE · ISOTROPIC · SEMIGROUP · POSITIVE · NO ZEROS | FWHM 28.26 px; 10–90 % edge width 30.76 px (2.563σ); half-amplitude at 0.0156 c/px (0.1874/σ); −3 dB at 0.0111 c/px; response at Nyquist e^(−π²σ²/2) < 10⁻³⁰⁰. |
| L4 KERNEL | 73 stems over the continuous bell; truncation slider k = 2–4 (default 3); discretization picker | r = ⌈3σ⌉ = 36, 73 taps per axis; w₀ 0.03332, w±12 0.02021, w±24 0.00451, w±36 0.00037; mass dropped 0.27 %; σ of the truncated kernel 11.86 px; truncation ripple in the MTF min −0.0012 (the table in `catalog-lsi.md` §2 gives −0.0011 at σ = 5). |
| L5 PASSES | Pass tiles `H · V`; tapping H shows the intermediate (a horizontal smear; on Night City every light becomes a horizontal streak) | Discrete taps: 2 × 73 = 146 per pixel; linear-sampled: 19 entries, **37 fetches per pass, 74 total**, offsets 0, 1.4974, 3.4939, 5.4905 … with weights 0.03332, 0.06607, 0.06382, 0.05996 …; direct 2-D would be 73² = 5,329. Intermediate in `rgba16Float` (8-bit intermediates band; `catalog-lsi.md` §3). |
| L6 METAL | `gauss_linear_fs` source (two fragment passes, compressible render targets) with a toggle to `gauss_tile_h/v` (compute); dispatch overlay | Compute variant: H pass 4 × 894 threadgroups of 256 × 1; threadgroup tile (256 + 72) × 8 B = **2,624 B** (limit 32 KB on Apple9, REFERENCE Feature Set Tables); 1.28 texture reads per pixel. Bytes: 894² = 799,236 px; 25.6 MB for two passes in `rgba16Float` → **0.50 ms floor at 51.2 GB/s (MODELED; the bandwidth figure is UNVERIFIED, leak-derived)**. Scaling the M1 Max measurement (0.67 ms for σ = 8 at 3.6 MP) by 5× compute, 0.22× pixels and 1.48× fetches gives ≈ 1.1 ms (MODELED). The real number is the MEASURED median of 30 warmed command buffers, shown live. On the A17 Pro the compute variant loses lossless compression because its outputs need `.shaderWrite` (REFERENCE, Tech Talk 111431); the compression A/B toggle measures the gap on this phone. Bilinear weights are quantized to 8 sub-texel bits (MEASURED on M1 Max; the device probe re-measures). |
| L7 PIXELS | Probe input 1.000 (white); output in both colour spaces; GPU − CPU | Linear-light blur: 0.7065 linear = **219/255** encoded. Gamma-space blur (what SwiftUI's default `.nonLinear` mode does): **180/255**. At the edge pixel itself (x = 447): 132/255 gamma vs 190/255 linear (`stack-semantics.md` §7 gives 128 vs 188 for the ideal half-plane). Parity |GPU − CPU| ≤ one fp16 ulp (4.9 × 10⁻⁴; MEASURED on the Mac harness, `gpu-pipeline.md` §6.3), shown LIVE on device. |

### 5.3 Worked example B: zoom / radial blur (`radial-zoom-blur`)

Set-up: Impulse grid specimen; centre handle dragged to the window centre c = (447, 447) px; strength a = 0.20 (each pixel averages the image scaled about c from 1.0 down to 0.8), inward; probe at (747, 447), 300 px right of centre. Numbers COMPUTED by `others.py` unless labelled.

| Layer | What it displays | Real numbers |
|---|---|---|
| L1 SLIDER | Tool chips: Photoshop Radial Blur (Zoom, Amount 1–100, Draft/Good/Best), Core Image `CIZoomBlur`, Sketch Zoom blur; the centre is a dragged point in every tool, so L1 shows the handle convention | Photoshop's Amount → strength mapping is **UNVERIFIED** (shown as text, no number). `CIZoomBlur` streaks **outward** with near-log-uniform weights; to smear 1.2× outward needs amount ≈ **9.0** by the law s = 1.5^(amount/20) (MEASURED on macOS, `stack-semantics.md` §3.4); `live-calibration.md` §5.2 measured 0.079·d at amount 4 and 0.357·d at 16, which that law predicts as 0.085 and 0.383, so the law is labelled MEASURED-with-conflict and the exact mapping UNVERIFIED. Core Image's y-up `inputCenter` vs the screen's y-down handle: the page shows the flip. |
| L2 API | `CIFilter.zoomBlur()` with `center`, `amount` as code; Blur2ool's own op with `In · Centred · Out` direction | Our operator: inward, a = 0.20. Equivalent Core Image call is outward, so A/B against the Apple twin uses `Out`. |
| L3 MATH | g(x) = (1/a)∫₀ᵃ f(c + (1 − s)(x − c)) ds; log-polar view as a figure: the specimen remapped to (ln r, θ) where the zoom becomes a horizontal box | No global MTF (LSV). Local PSF at the probe: a radial segment of length L = a·r = **60 px**, σ along the ray 17.32 px, local MTF a sinc with zero lines every **1/60 = 0.0167 c/px** perpendicular to the ray. In log-polar coordinates it is an exact 1-D box of length −ln(1 − a) = **0.2231** in ln r. A Siemens star centred on c passes unchanged (its spokes are rays); a centred zone plate smears (`catalog-spatial.md` §1.8). |
| L4 KERNEL | **PSF field**: a 7 × 7 grid of local PSFs drawn at their positions (rays lengthening outward); the sampling-condition plot | Ghost-free sampling needs N ≥ a·r_max + 1 = 0.2 × 632.2 + 1 = **127.4 → 128 taps** for the window corners (r_max = 447√2 = 632.2 px). With the default N = 32 the tap spacing is 1.94 px at the probe and **4.08 px at the corners**, which is why the status row warns `CORNER GAP 4.08 PX · GHOSTS`. |
| L5 PASSES | Two algorithms as tiles: `GATHER ×32` (one pass) and `DOUBLING ×7` (seven passes of two fetches) | Naive gather: 32 bilinear fetches per pixel, ghosts at the corners. Doubling: 7 passes × 2 fetches = **14 fetches for 128 geometrically spaced samples** (exact for the geometric-spacing variant, `catalog-spatial.md` §1.8). The periscope shows each doubling pass: 2, 4, 8 … ghost copies merging into a streak. |
| L6 METAL | `radial_blur` compute source; 16 × 16 threadgroups, 56 × 56 = 3,136 groups for 894²; per-pixel loop of bilinear `sample()`s at fractional positions | M1 Max: 1.08 ms for 32 samples at 3.6 MP (MEASURED, `gpu-pipeline.md` §6.3); parity 7.3 × 10⁻⁴ max vs CPU (fast-math trig + 8-bit bilinear weights). A17 Pro at 894²: ≈ 1.2 ms (MODELED from those figures); device number MEASURED live. Gathers are fetch-bound, so this is the first blur whose cost rises steeply with the sample count, and the Cost plot shows it. |
| L7 PIXELS | The probe's 32 taps listed: position, the two texels each bilinear fetch blends, fraction, weight 1/32 | Taps on the ray at x = 747.000, 745.065, 743.129, …, 717.968 (tap 15), …, 687.000 (tap 31), all on row 447; fractions 0.000, 0.065, 0.129, …, 0.968, …, 0.000. On the impulse grid the output at the probe is the fraction of taps that land on lit dots: a dotted streak when N is low, a continuous one when N ≥ 128. |

### 5.4 Worked example C: bilateral (`bilateral`)

Set-up: **Noisy steps** specimen: three vertical steps of height 0.05, 0.2 and 1.0 side by side (with optional Gaussian noise σ = 0.03); σs = 3 px, σr = 0.10 (of full scale), brute force over a 17 × 17 window (r = 8). Probe on the bright side, 2.5 px from each step in turn. Numbers COMPUTED by `others.py` (noise-free) unless labelled.

| Layer | What it displays | Real numbers |
|---|---|---|
| L1 SLIDER | Tool chips: Photoshop **Surface Blur** (Radius, Threshold) as the closest designer control, with its own catalog id `surface-blur` one tap away; OpenCV `bilateralFilter`; "skin smoothing" sliders as a REFERENCE-free mention | Photoshop Surface Blur is a thresholded bilateral cousin (INFERRED; its docs read backwards, `stack-semantics.md` §4.3). No Apple API exposes a bilateral (`CIEdgePreserveUpsampleFilter` is INFERRED to be a joint bilateral). |
| L2 API | `cv::bilateralFilter(src, dst, d: 17, sigmaColor: 25.5, sigmaSpace: 3)` as code (REFERENCE: OpenCV docs) | σr = 25.5/255 = 0.10 of full scale; range distance on luma (picker: Luma · RGB · Lab, Tomasi & Manduchi 1998 used Lab). |
| L3 MATH | g_p = (1/W_p) Σ G_σs(‖p − q‖) G_σr(|f_p − f_q|) f_q; verdict chip **ADAPTIVE BLUR** (passes T1, T2, T4; fails T3, T5); the **T(ν, A) heat map** replaces the MTF | Range weight for a step of height Δ: 0.61 (Δ = σr), 0.135 (2σr), 0.011 (3σr). T(ν = 0.1, A): 0.178, 0.214, 0.524, 0.930 for A = 0.01, 0.03, 0.1, 0.3, against the Gaussian's 0.168 at every A (COMPUTED, `catalog-nonlinear.md` §A2). |
| L4 KERNEL | The **weight map at the probe**, drawn as a 17 × 17 heat map over a copy of the neighbourhood, one per step | 0.05 step: far-side weight share **18.1 %** (Gaussian 20.0 %), local σx 2.90 px. 0.2 step: **3.3 %**, local σx 2.40 px, centroid pushed 0.87 px away from the edge. 1.0 step: **0.0000 %** (range weight 1.9 × 10⁻²²), local σx 2.24 px. The PSF is a Gaussian with a bite taken out of it, and the bite size depends on the image. |
| L5 PASSES | Tiles for the three algorithms: `BRUTE 289`, `SEPARABLE 34`, `GRID` (splat · blur · slice) | Brute force 17² = **289** taps per pixel; separable 2 × 17 = **34** (RMS 0.0050 from brute force on a noisy Siemens star, `catalog-nonlinear.md` §A4, with pass-order dependence RMS 0.0038); grid with s_s = σs, s_r = σr: RMS 0.0021–0.0059 (§A3). Each toggle shows its artifact in the periscope: separable streaks on diagonals, grid diamonds on ramps. |
| L6 METAL | Brute-force compute kernel: per tap one fetch, one squared difference, one `exp`, two FMAs into float accumulators (weighted sum and W_p); 16 × 16 threadgroup tile with an 8-px apron | Tile (16 + 16)² × 8 B = **8,192 B** in `half4` (fits the Simulator's 16 KB); 4.0 device reads per output pixel, the other 285 from threadgroup memory. 289 × 799,236 = 231 M weighted taps per frame (COMPUTED). Time: no Mac measurement exists for this kernel, so the page shows only the MEASURED device number; while a crown turns the Bench previews at half resolution and says so (`PREVIEW ½`). Parity CLI compiles it with `mathMode = .safe` because of `exp` (`sdk-feasibility.md` §13). |
| L7 PIXELS | Probe output vs Gaussian (σ = 3) at each step | Bright side, 2.5 px from the step, noise-free: 0.05 step → bilateral 0.9910, Gaussian 0.9900; 0.2 step → **0.9935 vs 0.9600**; 1.0 step → **1.0000 vs 0.8001**. With the noise switched on, the panel adds the residual noise next to the edge (the "noisy edges stay noisy" artifact; `catalog-nonlinear.md` §A2 gives 0.0039 vs 0.0024 on flat areas). |

### 5.5 Worked example D: hexagonal bokeh (`polygonal-bokeh`)

Set-up: **Night City** in linear light, `rgba16Float`, each light a 3 × 3 px block of value 16.0 (well above white); hexagon circumradius R = 24 px, rotation 0°, six blades. Numbers COMPUTED by `others.py` unless labelled.

| Layer | What it displays | Real numbers |
|---|---|---|
| L1 SLIDER | Tool chips: Photoshop **Lens Blur** (Iris Shape: Hexagon, Radius, Blade Curvature, Rotation; implementation INFERRED); Unity URP Bokeh DoF (Blade Count 3–9, f-number, focal length; REFERENCE source); Core Image `CIBokehBlur` shown greyed with "disc only" (MEASURED: a uniform disc) | No Apple API makes a polygonal bokeh. |
| L2 API | Stride `TripleRhombiBokeh` / VTK `vtkHexagonalBokehBlurPass` as the API-level names (REFERENCE); Blur2ool's parameters R, rotation, blades ∈ {4, 6, 8} | Odd blade counts (5, 7, 9) are shown disabled with the reason: only centrally symmetric polygons (zonogons) can be built from 1-D line blurs (`catalog-spatial.md` §2.3). |
| L3 MATH | h = indicator(hexagon)/area; the zonogon theorem as a two-line figure (a hexagon = Minkowski sum of three segments at 120°); the 2-D |H| image with six-fold spokes | Area 2.598 R² = **1,496.5 px²**; σ_equiv 0.456 R = **10.94 px** (a disc with the same σ has R = 21.9 px); MTF zero curves are not circles; six slow-decay spokes perpendicular to the edges. |
| L4 KERNEL | The hexagon mask split into its three rhombi, coloured by the pass that builds each one; one-sided 1-D segments of 24 taps starting half a step from the pixel | Directions 90°, −30°, −150°; P(90°, −30°) ∪ P(90°, −150°) ∪ P(−30°, −150°) tiles the hexagon (mismatch 7 × 10⁻⁷ of the area on a 1,201² grid, `catalog-spatial.md` §2.3). |
| L5 PASSES | Two tiles `PASS 1 · MRT` (vertical blur V; diagonal blur D = V + blur(−30°)) and `PASS 2` (blur(V, −30°) and blur(V + D, −150°), averaged) | **4 one-dimensional blurs × 24 taps = 96 fetches per pixel**, vs ≈ 2.6 n² = **1,496** for a 2-D gather of the same hexagon; the relative normalization of the two halves in the published code is UNVERIFIED and the CPU reference settles it for our implementation. |
| L6 METAL | Two render passes, two colour attachments in pass 1; fragment shaders, so render targets keep lossless compression on the A17 Pro | Each 1-D segment: n bilinear taps at ≤ 1 px spacing (sparser taps leave stripes inside the rhombi, a toggle demonstrates it). Time MEASURED live; no Mac number exists for this kernel. |
| L7 PIXELS | One hexagon's interior pixel and its value in three pipelines | Linear light HDR: a 3 × 3 light of 16.0 carries 144 units, spread over 1,496.5 px² → **0.0962 linear = 87/255** encoded: a clearly visible hexagon. The same scene clipped to 8-bit sRGB and blurred in encoded values: the light clips to 1.0, interior **0.0060 encoded = 2/255**: the hexagon practically vanishes. This is the "bokeh needs linear HDR" lesson (`catalog-spatial.md` §2 preamble; `stack-semantics.md` §7 item 3: a small light keeps 7.7 % of its energy in gamma space). |

### 5.6 What every other blur shows at each layer

Every catalog entry fills the same seven slots; when a slot has nothing honest to show, it says so in one line instead of disappearing (fixed layout). Examples of the rule: FFT-based entries show the spectrum multiply at L5 and `NO PIXEL FOOTPRINT · GLOBAL` at L7 (CATALOG §6.1 rule 2); Tier S entries put the system path at L6 as an INFERRED lane (render server `backboardd`, QuartzCore kernel names such as `tile_simd_blur_5…27`, `downsample_blur_*`, read from the iOS 26.5 Simulator runtime; `gpu-pipeline.md` §1.1) next to our model; Tier 3 entries are not on the Bench, so they have no Descent, only an atlas page.

---

## 6. The pixel-trace experience

"Trace a pixel" is the primary button on the Bench. It turns the Descent into a guided walk with a single thread running through it: **one output pixel, followed from the slider to the photon.**

1. **Choose the pixel.** Tap the image first (the probe), or accept the default. Trace starts from wherever the probe is. Good default probes are pre-set per specimen (on the step edge 6 px into the white side; on Night City, inside a light's bokeh; on the impulse grid, 300 px from the zoom centre).
2. **The context card** (pinned, 406 × ≈ 132 pt; AssemblerToy's accepted guide pattern): a 9 × 9 texel copy of the neighbourhood at 12 pt per texel with the current pass's weights overlaid in amber, then `IN` and `OUT` values in mono with monospaced digits, `COMPLETED:` (amber) and `NEXT:` (cyan).
3. **Layer selector** grid (4 + 3 tiles). The thread is drawn on the right-hand layer rail as a 2-pt amber line that has reached every layer already visited.
4. **Stepping.** `Next` advances at the granularity the layer supports: L1–L4 one layer at a time; at L5 one **pass** at a time, and inside a pass one **fetch** at a time (Gaussian: 37 fetches per pass, with offset, weight and fetched value for each; radial: the 32 taps listed in §5.3; bilateral: 289 taps grouped by row, each with its spatial weight, range weight and product; hexagon: 24 taps on each of the four segments); at L6 one **dispatch**: the threadgroup containing the probe lights up in the dispatch overlay with its apron shaded and its SIMD-group in a second colour; at L7 the final value and the parity check.
5. **Running sum.** At L5 the accumulator is shown as a growing bar beside the fetch list, so the Gaussian's output literally fills up to 0.7065 as the 37 weighted fetches land.
6. **Restart / Back** behave as AssemblerToy's do; Reduce Motion stops any auto-advance but manual stepping keeps working (Los Alamos rule).
7. **What a trace is not.** For FFT-based and global methods the trace says at L5 `EVERY OUTPUT PIXEL DEPENDS ON EVERY INPUT PIXEL` and shows the spectrum bin instead of a footprint. For the median it shows the sorted window and where the middle falls. For frosted glass it shows the single random neighbour that was copied, then the N-realization average converging (`P24`).

The trace's values are LIVE: they are read back from the actual intermediate textures of the frame on screen (a private-to-shared blit of a 9 × 9 region per pass, then `await commandBuffer.completed()`; never `getBytes` on a mip level of a shared texture, `gpu-pipeline.md` §2.7 item 7), and the CPU reference value from `BlurCore` sits beside each GPU value with the difference in fp16 ulps.

---

## 7. "What makes each blur unique": the fingerprint card

The brief's fourth requirement is answered by one artefact with a **fixed layout for every entry**, so that any two cards can be laid side by side and differ only where the blurs differ. It opens from the kernel-well lens (tap) or the housing caption, as a sheet (§3.6).

**Card anatomy (top to bottom, fixed heights):**

1. **Name, family eyebrow, verdict chips.** Verdict vocabulary from CATALOG §1 (TRUE BLUR · ADAPTIVE BLUR · RANK FILTER · BLUR IN EXPECTATION · LSV BLUR · COMPOSITE · BLUR-DERIVED · NOT A BLUR), plus property chips (LSI, SEPARABLE / SKEW / NO, ISOTROPIC, POSITIVE, SEMIGROUP).
2. **Signature** sentence (serif italic), verbatim from the CATALOG master table, e.g. box: "The honest average: flat and square, and it turns fine stripes inside out (MTF dips to −0.217)."
3. **Fingerprint strip.** Four 88 × 88 plot insets rendered by the GPU at the **σ-held size** (§8.1) from the same four procedural inputs for every blur:
   - **PSF**: impulse response, log intensity (shows rims, tails, holes, square supports);
   - **STAR**: a 36-cycle Siemens star crop (shows zeros as grey rings, inversion as reversed spokes, anisotropy as square rings);
   - **EDGE**: step-edge profile (linear ramp, erf S-curve, half-disc curve, overshoot);
   - **|H|**: radial MTF from 0 to 0.5 c/px with negative lobes in spectrum magenta; LSV blurs show the local MTF at a standard probe; adaptive blurs show T(ν, A) at A = 0.05 and 0.5 as two curves; rank filters show `N/A · RANK`.
4. **Six rows** (the brief's list, in this order): PSF SHAPE · |H| · EDGES · COST · ARTIFACTS · USED IN. Each row is one line with an optional disclosure and its own badge. The numbers are the CATALOG's CHECKED values, e.g. disc: "zeros at 0.6098/R, 1.1166/R; deepest lobe −0.1323 at 0.8174/R" (COMPUTED).
5. **The unique number.** One headline statistic per entry, chosen to be the thing *only this blur has*, engraved large: box **−0.217** (deepest MTF lobe), binomial **0** (exact zero at Nyquist; Gaussian σ = 1 leaves 0.72 %), Kawase **0.0645 < 0.0674** (hollow centre), iterated box **−1.0 %** (residual inversion for n = 3), plain mip **±7.5 px** (centroid snap at L = 4), ideal low-pass **8.9 %** (Gibbs overshoot), spin **10° → 0** (36-cycle star vanishes; CATALOG E7 cycle-count convention), SwiftUI `.blur` **0.90·r** above ≈ 5 px (MEASURED macOS), hexagon **96 vs 1,496** fetches.
6. **Kurtosis ID.** The excess kurtosis of the line-spread function as a shape fingerprint on a single labelled axis (box −1.2 · disc −1.0 · tent −0.6 · box³ −0.4 · Gaussian 0 · Laplace +3; `catalog-lsi.md` §19), with this blur's dot on it. It is the same statistic the device uses to classify a *measured* system blur, so the axis is shared between theory and measurement.
7. **TELL** box: the one test image that exposes it, with a `Show me` button that loads the Bench into that state (specimen, blur, held σ, probe).
8. **Nearest neighbours**: two or three entries it is most often confused with, each one tap → Bench in Wipe against it at held σ (the CATALOG §7 pairs supply these).

The card is the same for system blurs, whose rows simply carry different badges: SwiftUI `.blur`'s PSF row is MEASURED with the device name, its internals row INFERRED.

---

## 8. Comparison modes

### 8.1 σ-hold: the rule that makes switching a comparison

When the Turret switches blurs, Blur2ool keeps the **per-axis second moment** (σ) of the PSF constant and converts it into the new blur's own parameter. The change you see is therefore the blur's *character*, never its size. The status row reports the conversion for two seconds (`σ HELD 12.0 px → R 26.3 px`). Conversions (COMPUTED, from `catalog-lsi.md` §20 and `stack-semantics.md` §8):

| New blur | Parameter from held σ |
|---|---|
| box | w = nearest odd to √(12σ² + 1) (σ = 12 → w = 41, σ 11.83) |
| tent / stack blur | r = round(√(6σ² + 1) − 1) |
| iterated box (n) | Kovesi width split for n passes |
| binomial | n = 4σ² (practical only up to σ ≈ 4; above it the switch is refused with `σ TOO LARGE FOR BINOMIAL · MAX 4.0`) |
| disc | R = 2σ |
| hexagon | R = σ / 0.456 |
| exponential | b = σ/√2 (separable) |
| Lorentzian | infinite variance: hold **FWHM** instead, γ = 1.1774σ, and say so |
| motion (box / Gaussian) | L = √12·σ along the angle / σ_u = σ |
| Kawase, dual Kawase, pyramid | nearest preset (sequence / levels + offset) to σ; the achieved σ is shown, not hidden |
| SwiftUI `.blur` | r (pt) = σ / 3 below ≈ 5 px, σ / (0.90 × 3) above (MEASURED macOS law until the device measures its own) |
| heat equation | t = σ²/2 |
| frequency low-pass | D₀ such that the half-amplitude frequency matches 0.1874/σ |
| bilateral, guided, domain transform | σs = σ (range parameter keeps its last value) |
| median, Kuwahara, morphology, pixelate, LSV blurs (zoom, spin, path) | no σ exists: the blur opens at its own last value and the status row says `σ NOT DEFINED · RANK FILTER` (or `· SPACE-VARIANT`) |

A `MATCH σ` switch (Compare menu and Settings) turns this off for people who want to compare raw parameters ("radius 10 in every tool"), which is the stack-semantics lesson.

### 8.2 The four modes

All modes live inside the specimen window (in place, never a new screen). The `Compare` floating button toggles the last-used mode; its context `Menu` picks mode and B source.

| Mode | How it looks | Interaction | Best for |
|---|---|---|---|
| **Wipe** (default) | Vertical split, A left, B right | 44-pt divider handle owns its drag; adjustable action ±10 % | Any two blurs on the same specimen; the first-launch view |
| **Flip** | Full window shows A; press and hold the `B` engraving (or the Compare button) to show B | Hold = B, release = A; VoiceOver: a toggle | Detecting small differences the eye only sees in alternation (linear-sampling vs discrete taps; SwiftUI `.blur` vs Gaussian at fitted σ) |
| **Difference** | |A − B| × gain as a heat map (gain 1×, 16×, 256× by detents of the SEMANTIC crown) with the max printed in 8-bit LSB and fp16 ulps | Probe reads the local difference | Parity (GPU vs CPU), approximation error (three-box vs Gaussian), colour space (sRGB vs linear), precision (half vs float accumulators) |
| **Line-up** | 2 × 2 quadrants A–D, each 447 × 447 px (§3.2) | Tap a quadrant to make it the well's subject; the hero drives all four | The CATALOG triads: P2 box/tent/Gaussian, P11 disc/hexagon/Gaussian, P17 heat/Perona–Malik/TV, P28 three materials |

**B sources** (Compare menu): *the blur you just left* (default, so "switch then compare" is one gesture), *any blur* (long-press a Turret glyph → `Set as B`), *Input* (unblurred), *CPU reference* (`BlurCore`; Difference mode shows parity), *Apple twin* (Tier S: `CIGaussianBlur`, `MPSImageGaussianBlur`, `CIDiscBlur`, `CIMotionBlur`, `CIZoomBlur`, SwiftUI `.blur` via `ImageRenderer`), *same blur, other colour space*, *same blur, other algorithm variant* (the variant ids: separable vs linear-sampling, exact disc vs complex-separable vs stochastic, bilateral brute vs grid).

**Lessons** (Catalog → Lessons tab) are CATALOG §7's 30 pairs as one-tap presets; each sets specimen, A, B, mode, σ and the status-row number to look for. P26 (SwiftUI vs Gaussian vs iterated box, measured live) is the flagship lesson of the WYSIWYG requirement.

---

## 9. Controls per blur family

**Deck grammar.** The 98-pt crown deck below telemetry holds exactly one of these arrangements, declared per blur in `BlurCore`'s catalog (never inferred from live values, AssemblerToy `ViewThatFits` lesson):

- **A.** FINE crown (cyan, 8° detents) + SEMANTIC crown (amber, 20° detents) — continuous magnitude with named stops.
- **B.** FINE crown + ANGLE crown (cyan, 8° = 1°, snaps at 0/45/90/135°) — directional blurs.
- **C.** FINE crown + a second continuous crown with its own name (amber), e.g. `RANGE σr` — two-parameter blurs.
- **D.** FINE crown + integer `InstrumentParameterStepper` (48 tall) and/or a native segmented `Picker` (32 tall) — magnitude plus a count or a mode.
- **E.** Event tiles (37 tall, Metro beat-grid grammar) + Stepper — sequence-defined blurs (Kawase) and the material ladder.

Counts (passes, levels, samples, iterations, realizations) always use Steppers: precise small integers, native hold-repeat (Metro contract A.7). Magnitudes always use crowns, with ± glass buttons as their native alternative. Every crown obeys Metro §10: ≤ 1 step per update, ≤ 20 events/s, 18 % reversal hysteresis, 7-pt centre exclusion, haptics fine up 0.78/0.95, fine down 0.82/0.20, semantic up 1.00/0.60, semantic down 1.00/0.05. Every parameter also appears in the Parameters sheet with a Stepper.

| Family / entry | Deck | FINE crown (unit, range, detent) | Second control | Specimen handle | Default specimen |
|---|---|---|---|---|---|
| F1 `box-blur` (+ `sat-box`) | D | RADIUS r, px, 1–64, 1 px (width 2r + 1 shown in status) | Picker `Separable · Sliding · SAT` | — | Siemens star |
| F1 `tent-blur` (+ `stack-blur`) | D | RADIUS r, px, 1–64, 1 px | Picker `Separable · Stack` | — | Siemens star |
| F1 `iterated-box` | D | target σ, px, 0.5–64.0, 0.1 | PASSES 1–6; Parameters: width rule `Equal · Kovesi · SVG 3-box · Extended` | — | Night City +3 EV |
| F2 `gaussian-blur` | A | σ, px, 0.3–64.0, 0.1 | SEMANTIC stops 0.5 · 1 · 2 · 4 · 8 · 16 · 32 · 64 px (σ bands) | — | Night City / step edge |
| F2 `binomial-blur` | A | ORDER n, 2–64, 2 per detent | SEMANTIC stops n = 2 · 4 · 8 · 16 · 32 · 64 | — | 1-px checkerboard |
| F2 `iir-gaussian` | D | σ, px, 0.5–64.0, 0.1 | Picker `Deriche 2 · 3 · 4 · YvV` | — | bar touching left edge |
| F3 `kawase-blur` | E | — | tiles = distance sequence (tap a tile to cycle 0–7), PASSES 1–8; SEMANTIC preset list in Parameters `{0,1,2,2,3}`, `{0,1,2,3}`, `{2,3,3,3}`, 17-pass | — | Night City |
| F3 `dual-kawase` | D | OFFSET o, 1.0–4.0, 0.1 | LEVELS 1–6 | pan = shimmer toy | text (panning) |
| F3 `pyramid-blur` | D | — (LEVELS drive size) | LEVELS 1–6; Picker `Mip · CoD 13 · Unity 13` | pan = snap toy | moving point light |
| F4 `exponential-blur` | A | decay b, px, 0.5–32.0, 0.1 | SEMANTIC = EXPOSURE 0 to +6 EV, 1 EV | — | Night City +4 EV |
| F4 `lorentzian-blur` | A | half-width γ, px, 0.5–32.0, 0.1 | EXPOSURE | — | Night City +5 EV |
| F4 `frequency-lowpass` | D | cut-off D₀, c/px, 0.005–0.500, 0.005 | ORDER n 1–20 + `∞` (ideal); Picker `Ideal · Butterworth · Gaussian` | — | step edge (overshoot) |
| F4 `fft-convolution` | D | kernel size, px, 4–256, 1 | Picker kernel `Disc · Hexagon · Star · Airy · Drawn`; Parameters padding `None (wrap) · Zero · Mirror` | — | bright object at the edge |
| F5 `linear-motion-blur` | B | length L, px, 1–200, 1 | ANGLE 0–180°, 1°; Parameters profile `Box · Trapezoid · Coded` | — | impulse grid |
| F5 `anisotropic-gaussian` | B | σ along, px, 0.5–64.0, 0.1 | ANGLE; Parameters σ across | — | Siemens star |
| F5 `kawase-streak` | B | length, px, 4–256, doubling stops | ANGLE; Parameters ARMS 2–8 | — | Night City |
| F5 `camera-shake-blur` | D | scale, %, 10–400, 5 | `Paint · Pan` | paint the shake path | Night City / text |
| F5 `velocity-buffer-motion-blur` | D | shutter, °, 0–360, 5 | SAMPLES 4–32 | drag the moving disc | procedural V/Z scene |
| F5 `temporal-accumulation` | D | shutter, °, 0–360, 5 | FRAMES 1–256 | drag rotation speed | rotating star |
| F5 `radial-zoom-blur` | D | STRENGTH a, %, 0–50, 0.5 | SAMPLES 8–256; Picker `In · Centred · Out` | centre ⊕ | impulse grid / centred star |
| F5 `spin-blur` | A | ANGLE Θ, °, 0–90, 0.5 | SEMANTIC stops at multiples of 360°/n_c (10°, 20°, 30° … for the 36-cycle star: the star vanishes on every detent) | centre ⊕ | centred Siemens star |
| F5 `path-blur` | D | SPEED, %, 0–500, 5 | `Paint · Pan`; Parameters taper, centred | paint paths | text + S path |
| F6 `disc-blur` | A | RADIUS R, px, 0.5–64.0, 0.1 | EXPOSURE; Parameters algorithm `Exact · Complex ×1 · Complex ×2 · Stochastic` + SAMPLES | — | Night City +3 EV |
| F6 `polygonal-bokeh` | B | RADIUS R, px, 1–64, 0.5 | ANGLE = rotation 0–60°, 1°; Parameters blades `4 · 6 · 8` (5, 7, 9 disabled with reason) | — | Night City +3 EV |
| F6 `cats-eye-swirl-bokeh` | C | RADIUS R, px, 1–64, 0.5 | `VIGNETTE` crown 0.00–1.00, 0.02 | — | full-frame light grid |
| F6 `diffraction-airy` | A | f-number, f/1.4–f/22, ⅓ stop | SEMANTIC wavelength stops 450 · 550 · 650 nm | — | Night City +5 EV / zone plate |
| F6 `anamorphic-bokeh` | C | RADIUS R, px, 1–64, 0.5 | `SQUEEZE` crown 1.00–2.00×, 0.05 | — | Night City |
| F7 `depth-of-field-coc` | A | f-number, f/1.4–f/16, ⅓ stop | SEMANTIC focus distance stops (near · mid · far layers) | — | depth scene (procedural) |
| F7 `tilt-shift` (+ iris) | A | max blur σ, px, 0–32, 0.1 | SEMANTIC band width stops | focus band / ellipse | aerial checkerboard |
| F7 `variable-progressive-blur` | D | max σ, px, 0–48, 0.1 | Picker `Mip mix · Per-pixel · Stacked`; mask in Parameters `Ramp · Radial · Scroll edge` | mask ramp ends | ramp mask over impulse grid |
| F7 `frosted-glass-noise` | D | SPREAD a, px, 0–16, 0.1 | REALIZATIONS 1–256 | — | step edge + text |
| F8 `median` | D | RADIUS r, px, 1–7, 1 (3×3 … 15×15) | Picker `Square · Disc` | — | salt-and-pepper text |
| F8 `bilateral` (+ grid, separable) | C | SPATIAL σs, px, 0.5–8.0, 0.1 | `RANGE σr` crown 0.01–1.00 of full scale, 0.01 | — | noisy steps |
| F8 `joint-bilateral` | C | σs | σr; Parameters guide image | — | blocky depth + stripe guide |
| F8 `guided` | C | RADIUS r, px, 1–32, 1 | `ε` crown 10⁻⁴–1, three detents per decade | — | noisy step, detail boost |
| F8 `domain-transform` | C | σs, px, 1–64, 0.5 | σr crown | — | noisy step + thin line |
| F8 `kuwahara` | D | RADIUS r, px, 2–16, 1 | Picker `Classic · Generalized · Anisotropic` | — | noisy flat field |
| F8 `surface-blur` | C | RADIUS, px, 1–32, 1 | `THRESHOLD` crown 2–255 levels, 1 | — | ramp + noisy step |
| F8 `nonlocal-means` | D | filtering h, 0.01–0.30, 0.01 | Parameters patch 3/5/7, search 11–31 | — | noisy text |
| F9 `heat-equation` | D | TIME t, 0–512, ¼ steps (σ = √(2t) shown) | ITERATIONS shown, not set (t / λ, λ = 0.25) | — | impulse |
| F9 `perona-malik` | D | edge K, 0.01–0.50, 0.01 | ITERATIONS 0–500 | — | noisy step + ramp |
| F10 `swiftui-layer-blur` | D | RADIUS r, **pt**, 0–32, 0.25 | Picker `.nonLinear · .linear · .extendedLinear`; Parameters `opaque` | — | step edge / impulse |
| F10 `apple-uiblureffect` | E | — (no parameter is exposed: that is the lesson) | material tiles `ultraThin · thin · regular · thick · chrome` | the panel | colour stripes + text + B/W split |
| F10 `liquid-glass` | E | — | tiles `Regular · Clear`; tint in Parameters | glass shape | checkerboard |
| F10 `css-backdrop-filter` (model) | C | blur σ, CSS px, 0–40, 0.5 | `SATURATE` crown 100–300 %, 5 % | panel | bright object outside the panel |
| F11 `drop-shadow` | D | typed value, 0–40, 1 | Picker tool `CSS box-shadow · drop-shadow() · CALayer · Figma · SwiftUI` | — | square + star |
| F11 `bloom` | D | THRESHOLD, ×white, 0.5–4.0, 0.1 | LEVELS 1–8; SEMANTIC exposure in Parameters | — | Night City, several exposures |
| F11 `god-rays` | D | DECAY, 0.900–1.000, 0.005 | SAMPLES 16–128 | sun ⊕ | disc behind occluder bars |
| C `unsharp-mask` | C | σ, px, 0.3–16.0, 0.1 | `AMOUNT k` crown 0–4, 0.05 | — | step edge + text |
| C `difference-of-gaussians` | C | σ, px | `RATIO k` crown 1.1–5.0, 0.1 | — | Siemens star |
| C `morphology` | D | RADIUS r, px, 1–16, 1 | Picker `Dilate · Erode · Open · Close` | — | Night City / text |
| C `pixelate` | D | CELL, px, 2–64, 1 | Picker `Square · Hex` | pan = cyclostationary toy | text (panning) |
| C `wiener-deconvolution` | C | blur σ / R of the PSF to undo | `NOISE K` crown 10⁻⁴–10⁻¹, three detents per decade | — | blurred text |

Ranges are design choices bounded by the research: the Gaussian's 0.3 floor is where sampled kernels collapse (σ 0.3 → true 0.088, `catalog-lsi.md` §2), so below 0.7 the Parameters sheet offers Lindeberg's discrete Gaussian; the 64-px ceiling keeps tiled separable passes within the threadgroup budget (`half4`, R ≤ 56 fits 16 KB, `sdk-feasibility.md` §15) and beyond it the blur switches algorithm, which the status row announces as a lesson (`σ > 56 · SWITCHED TO PYRAMID`).

---

## 10. The honesty labels in use

Six badges, built in Metro grammar as `metro-adaptation.md` §C.12 specifies: a capsule, caption2 mono, tracking 1.2, white 0.06 fill, 0.6-pt border; **the word is primary**, glyph and ink are redundant cues; badges never animate and are spoken with the value ("GPU time, 1.08 milliseconds, measured on this iPhone", with whatever value the phone measured).

| Badge | Glyph · ink | Where it appears on the Bench | Where in the Descent | Rule |
|---|---|---|---|---|
| **LIVE** | ● · action cyan | housing caption `LIVE · METAL`; Difference max; loupe values; local σ at probe | L7 values; L4 weight maps for adaptive blurs; periscope | computed from the current image and parameters, this frame |
| **MEASURED** | ⏱ · instrument amber | GPU ms (median of 30 warmed command buffers, `n=30` shown); fitted σ of Tier S blurs | L2 measured laws; L6 times, device card | always carries the platform: "MEASURED · iPhone 15 Pro Max" or "MEASURED · macOS 27.2 (M1 Max)" until the phone re-measures. Simulator: struck through, `SIMULATOR · NO GPU TIMING` |
| **COMPUTED** | = · display ink | σ EFF, fetches/px, conversions in the status row | L3, L4, L5 numbers | exact consequence of the math in `BlurCore` |
| **MODELED** | ≈ · spectrum violet | none by default (the Bench prefers measurements) | L6 bytes, bandwidth floors, ghost bars beside measured pass bars, A17 Pro estimates | carries its assumption in the disclosure, e.g. "51.2 GB/s, leak-derived, UNVERIFIED" |
| **REFERENCE** | book · secondary ink | none | L1 tool conventions, L2 API docs, Feature Set Tables values on the device card | always with a citation in the Field guide |
| **INFERRED** | ? + **dashed** border · spectrum depth | housing caption for system glass; KERNEL/FREQ pills on system materials (`INFERRED — NOT EXPOSED`) | L2 shape interpretation of SwiftUI `.blur`; L6 render-server lane and QuartzCore kernel names; Apple material recipes | used for proprietary internals; measured live wherever possible, and the badge changes to MEASURED when the device measurement exists |

Three placement rules that the toy must not break:

1. **No number without a badge** on any screen, except the hero and crown captions, whose provenance is the user (the hero is the *requested* value; the telemetry row next to it carries the *acknowledged* frame's numbers, Metro contract A.13).
2. **UNVERIFIED is never a badge on a number.** If a figure is UNVERIFIED it does not appear as a number; the Field guide states the claim in words with UNVERIFIED (Photoshop's radius → σ, the unit of Apple's backdrop `inputRadius`, Figma's own renderer, the A17 Pro bandwidth).
3. **The lens on this instrument.** The Field guide page says, in the mirror image of Toothpaste Toy's honesty line: "The glass on the controls and the lens is Apple's Liquid Glass. It is drawn by the system; its lensing, scattering and tint are not exposed, and every figure about them is INFERRED. Blur2ool measures it only in the Liquid Glass exhibit." The specimen is never under glass except in that exhibit, and every measurement is read back from Metal textures, not screen pixels (`metro-adaptation.md` §C.1 Specimen rule).

---

## 11. Test-image set

All procedural (copyright-free, mathematically exact), generated by `BlurCore` at 894 × 894 into `rgba16Float` linear light, with an HDR range for the light scenes. Photos come in only through `PhotosPicker` (out of process, no permission; downsampled with ImageIO to ≤ 2048 px, then cropped to the window).

| Specimen | Definition | Reveals | Default for |
|---|---|---|---|
| **Night City** | dark building silhouettes (value 0.02–0.06) + ≈ 180 point lights (1 × 1 to 3 × 3 px, values 2–32, warm sodium and cool LED tints, a few in rows like streets), seeded so it is identical every launch; EXPOSURE 0 to +6 EV | PSF shape made visible (bokeh, rims, square supports, tails), linear vs gamma energy loss | first launch; F4, F6, F11 |
| **Siemens star** | **36 cycles** (n_c = 36, CATALOG E7 convention, labelled "36 CYCLES"), contrast 1.0, centred | zeros (grey rings), inversion (reversed spokes), anisotropy (square vs round rings), spin duality | F1, F2 comparisons, spin |
| **Zone plate** | cos(π k r²) reaching Nyquist at the window edge | the MTF laid out in space; moiré from decimation; direction-dependent zeros | pyramids, motion |
| **Step edges** | single vertical step (default probe 6 px into white); **noisy steps** at contrasts 0.05 · 0.2 · 1.0 with optional Gaussian noise σ = 0.03 | edge spread, overshoot, colour-space midpoints, edge preservation | Gaussian trace, bilateral, low-pass |
| **Impulse grid** | single white pixels every 64 px | the PSF itself, and the PSF field of LSV blurs | motion, zoom, spin, path, median (it vanishes) |
| **Checkerboards** | 1-px and 8-px | Nyquist behaviour (binomial erases it exactly), box inversion | binomial, box |
| **Text** | a paragraph rendered with the system font via Core Text at 9–24 px heights; a **salt-and-pepper** variant (10 %) | legibility, doubled strokes, shimmer under panning, impulse rejection | median, dual Kawase, deconvolution |
| **Ramp** | 0 → 1 over the window, optional noise 0.01 | staircasing / terracing (bilateral, TV, mean shift) | adaptive blurs |
| **Material wallpaper** | saturated colour stripes + text + a white/black split | saturation boost, luminance squeeze, refraction band | F10 |
| **Depth scene** | three procedural depth layers of lights with a depth buffer | CoC, foreground bleeding | DoF |
| **Rings** | noisy concentric rings with gaps (fingerprint-like) | flow-following diffusion | CED (atlas) |
| **Photo** | user's own, via PhotosPicker | real-world look | any |

---

## 12. Accessibility alternatives

| Need | Alternative |
|---|---|
| **No fine motor / no drag** | Every crown has ± glass buttons (44 × 44) and `accessibilityAdjustableAction`; every parameter has a Stepper in the Parameters sheet; handles (centre, band) have adjustable actions (±8 px) and Reset; the wipe divider is adjustable ±10 %; the probe is adjustable ±1 px and ±16 px with a rotor. |
| **VoiceOver** | The specimen is one element: "Night City, Gaussian blur, sigma 12.0 pixels, probe at 453, 447, output 0.707 linear". Pills speak a summary ("Kernel, 73 taps, normalized peak 0.033"; "Frequency response, half amplitude at 0.016 cycles per pixel") and offer an `AXChartDescriptor` plus a data table. Badges are spoken as part of the value. Decorative paths (rulers, well face, grid) are hidden. The Descent pages are headings; Trace's Next announces the completed step. Catalog uses `Picker(.tabs)` so its sections are announced as tabs (iOS 27). |
| **Dynamic Type (AX1–AX5)** | The Bench becomes a vertical `ScrollView` (the one case where it scrolls); because a scroll and an image drag cannot share the window, image gestures are switched off and the handles move by their controls; the header subtitle and ruler numerals hide; the readout band becomes a native text block below the housing; crowns stack vertically; telemetry becomes three rows; the floating group goes icon-only with full spoken labels (AssemblerToy). |
| **Reduce Motion** | No first-launch focus pull; pills snap; no lens bounce; no auto-sweeps or auto-advance in Trace (manual stepping still works); temporal demos (shimmer under pan) only on the user's own drag. |
| **Reduce Transparency** | Lens opacity 1.0, content panels opaque, floating group on an opaque backing (Metro §17); the Liquid Glass exhibit shows a note that the system has made the glass frostier, which is itself a measured difference if he wants it. |
| **Increased Contrast** | Panel borders 0.20, pill outlines 0.70, badge borders 0.25. |
| **Colour vision** | Comparison traces differ by dash pattern (A solid, B dashed, C dotted, D dash-dot); negative lobes are shaded *and* drawn below a zero line; badges are words; amber is never the only error cue. |
| **Haptics off / no sound** | Haptics are a setting; the app makes no sound. |
| **Seeing pixels** | The loupe (8 pt per texel, value printed) and pinch zoom make one-pixel effects visible without good eyesight. |

---

## 13. What is deliberately NOT included

- **No scrolling Lab page on the Bench.** The plots, pass tiles and cost charts live one layer down. The Bench is an instrument, not a document.
- **No photo editor.** No export of blurred photos, no filter stacks, no layers, no undo history. A blur toy that becomes an editor loses its focus. (A share sheet for a *comparison screenshot* with its badges burned in is the one export, and only if he asks.)
- **No live camera feed.** It would be irresistible, but it needs a camera permission prompt, the brief asks for no permissions beyond PhotosPicker, and moving camera content makes measurements unrepeatable.
- **No onboarding carousel, tips, or tutorials**; one coaching line, once.
- **No tilt optics on the lens in v1** (`metro-adaptation.md` §G.1 item 2) and no tilt-driven anything: tilt is never a domain edit (Metro contract A.19).
- **No private API.** No `CAFilter`, no `CABackdropLayer`, no private `variableBlur`; system internals are described as INFERRED and measured from outside.
- **No Metal 4 command model** for rendering (Simulator SDK lacks it); Metal 4 counter heaps are used only for per-pass timing on the device behind `#if !targetEnvironment(simulator)` (`gpu-pipeline.md` §4.3).
- **No Tier 3 blur on the Bench.** `mean-shift`, `tv-denoise`, `coherence-enhancing-diffusion`, Windows and Android materials and the discrete-Gaussian footnotes live as atlas pages with CPU plots on a small crop.
- **No landscape, no iPad, no light appearance** (Metro is dark-only; portrait tilt mapping; adaptation §E.6).
- **No tab bar.** Its floating glass would cover live controls in the first viewport (QuantumToy and Los Alamos screenshots show this; adaptation §F.3 item 3).
- **No glass over the specimen** except the Liquid Glass exhibit; no draggable glass lens anywhere (Metro contract 2; the probe and the Metal loupe move instead).
- **No accounts, network, analytics or third-party runtime code.**
- **No sonification** of PSFs. Tempting, but it would be a second instrument.

---

## 14. Risks

| # | Risk | Why it is real | Mitigation |
|---|---|---|---|
| 1 | **Heavy blurs miss 120 Hz** while a crown turns | Gathers and brute-force adaptive filters are fetch-bound: bokeh 64 samples ≈ 15 ms and SAT ≈ 10 ms full-screen MODELED on the A17 Pro (`gpu-pipeline.md` §4.2); bilateral brute force is 289 taps/px | The window is 0.8 MP, not 3.6 MP (≈ 4.5× fewer pixels); `PREVIEW ½` while turning, full resolution on release, and the status row says which; per-blur caps (SAMPLES ≤ 256, r ≤ 8 brute bilateral) |
| 2 | **Gesture conflicts** on the specimen (handle vs pan vs probe vs pinch vs loupe vs wipe divider) | Six gestures share one 298-pt square | Priority order: wipe divider and handles (hit-tested first, 44 pt) > long press > pinch > drag (pan) > tap (probe); a drag that starts on a handle never pans; blurs declare whether pan is meaningful; verify on device with held and edge touches during redraw (Metro contract A.7) |
| 3 | **Non-scrolling Bench does not fit** on smaller phones or with larger text | The layout is budgeted to 430 × 932 with 22 pt to spare | The cluster formula scales D (402 pt → window 270 pt, `metro-adaptation.md` §D.7); below 402 pt wide and at AX sizes the Bench becomes scrollable with gestures handed to controls (§12) |
| 4 | **σ-hold confuses** when a blur has no σ | LSV and rank filters cannot hold σ | Explicit status line (`σ NOT DEFINED · RANK FILTER`), the hero's unit line changes with the parameter, and `MATCH σ` can be switched off |
| 5 | **Tier S numbers on device differ from the Mac** | Every SwiftUI/Core Image law was MEASURED on macOS 27.2; `ImageRenderer` may not match the on-screen render-server path (`live-calibration.md` §8) | Badges carry the platform; the device runs `measurePSF` on first use of a Tier S blur and replaces the Mac value; the `drawHierarchy` on-screen capture is an experiment, not a dependency |
| 6 | **Turret discoverability** with ~45 glyphs | Footprint glyphs are abstract | Hero dozen first; long-press any glyph shows its name in the status row; `[All]` opens the searchable Catalog; the housing caption always names the current blur |
| 7 | **Badge clutter** | Honest numbers everywhere can become noise | The Bench shows exactly three badged numbers (telemetry); everything else badged lives in the Descent, at most six per page |
| 8 | **GPU timing noise and thermal throttling** | Clock ramp and heat move timings by 2× (`gpu-pipeline.md` §6.3) | Median of 30 after 3 warm-ups; `ProcessInfo.thermalState` and Low Power Mode recorded with every MEASURED time and shown in the disclosure; Simulator timings never shown |
| 9 | **Liquid Glass over Metal content** may not sample the `MTKView` faithfully | UNVERIFIED (`metro-adaptation.md` §G.2 item 1) | The exhibit draws its specimen in SwiftUI; the floating group never overlaps the window on the Bench |
| 10 | **Descent pages become lectures** | Seven layers × 50 blurs is a lot of copy | One rule, one figure, ≤ 6 numbers per page, details in disclosures; the periscope keeps the toy on screen; pages generated from `BlurCore` data, not hand-written prose |
| 11 | **Readback stalls** during Trace | Reading intermediates every step could stall the GPU | Trace reads a 9 × 9 region per pass via a blit into a small shared buffer, only when stepping, with `await commandBuffer.completed()` |
| 12 | **Research numbers that conflict** | e.g. `CIZoomBlur` law vs calibration points; truncated-Gaussian vs box³ reading of SwiftUI's kernel; the 13-tap geometry split (CATALOG E2) | Show measured numbers, label interpretations INFERRED, state the conflict in the Field guide, and let the device measurement settle it |

---

## 15. Sources

Project research (all read in full for this concept): `Documentation/BRIEF.md`; `research/CATALOG.md` (master table, tiers §6, pairs §7, corrections §5); `research/catalog-lsi.md` (§0 conventions, §1–§20); `research/catalog-spatial.md` (§0, §1.1, §1.8–§1.10, §2.1–§2.4); `research/catalog-nonlinear.md` (§0, A1–A4, B1–B4); `research/stack-semantics.md` (§0–§9); `research/gpu-pipeline.md` (§0–§9, sketches §6.2); `research/metro-adaptation.md` (§A–§G); `research/sdk-feasibility.md` (§0–§17); `research/live-calibration.md` (§1–§8).

Design-system references viewed: Metro Station skill `assets/visual-reference.png` (edition 1.0, build 14); Metro Station `Documentation/PhysicalQA/Build14/appearance-only/native-pair/5D948488-E870-48E7-B66E-F3EFDFA80A34.png` (WAVE/FREQ pills flanking the dial, FINE and TEMPO crowns with ± glass buttons, three-column telemetry, beat grid tiles, floating glass group); ClassicalMLSimulator `Documentation/Screenshots/workbench.jpg` (glass tab bar over content); LosAlamosSimulator `Documentation/QA/Trinity.jpg` (rectangular instrument with readout band and serif meaning line).

External sources are cited through the research files (each number above names its file and section). Key primary sources behind the worked examples: W3C Filter Effects Module Level 1 (`blur()`, `feGaussianBlur`) and Level 2 (`backdrop-filter`); Apple Developer Documentation for `View.blur(radius:opaque:)`, `GraphicsContext.Filter.blur(radius:options:)`, Core Image filters, `MPSImageGaussianBlur`; Apple Metal Feature Set Tables (PDF dated 21 May 2026); Apple Tech Talks 10855, 10857, 111374, 111431; WWDC25 session 219 "Meet Liquid Glass"; Rákos 2010 "Efficient Gaussian blur with linear sampling"; Tomasi & Manduchi 1998 "Bilateral filtering for gray and color images" (ICCV); Paris & Durand 2006/2009 (bilateral grid); Pham & van Vliet 2005 (separable bilateral); White & Barré-Brisebois 2011 "More Performance! Five Rendering Ideas from Battlefield 3 and Need For Speed: The Run" (SIGGRAPH Advances); McIntosh, Riecke & DiPaola 2012 (Computer Graphics Forum 31(6)); Mitchell 2007 (GPU Gems 3 ch. 13); Getreuer 2013 "A Survey of Gaussian Convolution Algorithms" (IPOL).

Numbers derived for this concept (COMPUTED): `$TMPDIR/blur2ool-concept-instrument/gauss.py` (Gaussian σ = 12 kernel, linear-sampling table, MTF points, step-edge probe values, dispatch and byte counts) and `others.py` (zoom sampling condition and tap positions, bilateral probe weight shares, hexagon area, σ and HDR levels).

UNVERIFIED items this concept depends on (each must be settled on the device before its number appears as anything but text): iPhone 15 Pro Max safe areas 59/34 pt; A17 Pro DRAM bandwidth (51.2 GB/s is leak-derived); SwiftUI `.blur` law on iOS; `CIZoomBlur` amount → length law; Photoshop Radial Blur and Lens Blur internals; whether native glass samples `MTKView` content faithfully; the published normalization of the two-pass hexagon.

<!-- STATUS: COMPLETE -->
