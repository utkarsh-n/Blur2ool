# Blur2ool: concept "Descent" (pedagogy-first)

Status: COMPLETE (written incrementally across two sessions; sections 10–15 and a few corrections added in the second).

## 0. Sources read

Inputs (all under `Documentation/`): `BRIEF.md`; `research/CATALOG.md` (master table, tiers §6, pairs §7, corrections §5); `research/catalog-lsi.md`, `catalog-spatial.md`, `catalog-nonlinear.md` (worked numbers for Gaussian, zoom, bilateral, hexagonal bokeh); `research/stack-semantics.md` (the 16 meanings of "radius", colour space, edge policies); `research/gpu-pipeline.md` (A17 Pro facts, pass costs, MSL sketches, measurement); `research/metro-adaptation.md` (Metro contracts, tokens, 430 x 932 layout); `research/sdk-feasibility.md`; `research/live-calibration.md`. Visual references: Metro `visual-reference.png` and adopter screenshots (listed in §4).

This document cites those files as `CAT §n`, `LSI §n`, `SPA §n`, `NL §n`, `STACK §n`, `GPU §n`, `METRO §n`, `SDK §n`, `CAL §n`. Numbers carry the provenance label they have in the source; where I computed a number myself for a worked example, it is marked COMPUTED (here) and the arithmetic is shown.

## 1. One-line pitch

**Tap one pixel of a blurred picture and fall through the seven floors that made it, from the designer's slider to the GPU fetch, for every blur in the catalog; then compare any two blurs and see the floor where they part ways.**

The angle in one paragraph. Blur2ool is a descent, not a dashboard. Every blur is the same seven-floor building: **WYSIWYG → API → Math → Kernel → Algorithm → GPU → Pixels**. The user always stands on one pixel (the *probe*) and every floor answers the same question about it: *what does this floor say about this pixel?* The slider floor says "you typed 8"; the API floor says "that is σ = 4.0 px on this phone"; the math floor says "a Gaussian with that σ"; the kernel floor shows 25 numbers; the algorithm floor shows two passes; the GPU floor shows the 13 bilinear fetches the fragment at (446, 300) issued in each of two passes; the pixels floor shows 0.000 going in and 0.450 coming out (linear light; 179 of 255 once encoded). The atlas compares blurs by the **floor at which they first differ** ("box and Gaussian part ways at Math; separable and linear-sampled Gaussian part ways only at GPU"), which is the clearest single answer to "what makes each blur unique".

## 2. The first ten seconds

No splash, no onboarding, no coach marks. The app opens straight into the Lab with a working blur and a probe that is already placed, so the very first frame already contains the whole idea: a blurred picture, one marked pixel, and a strip of seven floors that each say something about that pixel.

| Time | What is on screen | What the user can do |
|---|---|---|
| 0.0 s | Header `Blur2ool` / `BLUR SIMULATOR · WYSIWYG → GPU`. Blur chip `Gaussian · F2`. The specimen housing shows a 36-cycle Siemens star blurred live on the GPU with σ = 4.0 px (engraving `SIEMENS STAR · 36 CYCLES` left, `LIVE · METAL` right). An amber probe crosshair sits near a spoke edge, 164 px from the star's centre. The readout band shows `SIGMA · PX`, hero `4.0`, serif italic *Softened*, status row `25 TAPS · 2 PASSES · SEPARABLE`. KERNEL and FREQ pills flank the window with their traces already drawn. Under the crowns, the **descent rail** shows seven chips, `SLIDE 1.33pt · API 4.0px · MATH G · KERNEL 25 · ALGO 2× · GPU 13 · PIXEL 0.52` (the PIXEL value here is illustrative; on device it is LIVE), each the probe's summary at that floor. The SLIDE chip speaks in the user's *home tool*, SwiftUI points by default (Settings can switch it to Figma, CSS, Photoshop, Core Image…). The primary floating button reads **Descend from (412, 287)**. | Nothing moves. A blur has no clock, so nothing pulses or animates while idle (METRO §C.5, Metro §19). The only invitation is the primary button naming a concrete pixel. |
| 1–4 s | User turns the amber SEMANTIC crown one detent (σ 4 → 8). One semantic haptic. Hero reads `8.0` instantly (requested value); the status row reads `RENDERING… PASS 2/2` for one frame, then `49 TAPS · 2 PASSES · SEPARABLE`. The grey disc in the star's centre grows; the pills' traces ease to the new shape in about 150 ms; the rail's KERNEL chip changes from 25 to 49 and GPU from 13 to 25. | Learn that the slider, the kernel and the GPU work all moved together. |
| 4–6 s | User taps somewhere else in the star. The probe crosshair jumps there (no glass, no animation beyond a 120 ms fade). Rail chips SLIDE…ALGO keep their values (they do not depend on the pixel for an LSI blur) while GPU and PIXEL change. | Discover, without being told, that for a Gaussian only the bottom two floors depend on *which* pixel. This is the first lesson about shift invariance, and it falls out of the layout. |
| 6–10 s | User taps **Descend**. The Trace screen pushes. Floor 1 is selected and answers "what would I type to get σ = 8.0 px on this phone?": `.blur(radius: 2.67)` in SwiftUI *nominally*, but 2.96 to really get it (the MEASURED large-radius law σ ≈ 0.90·r·scale); **5.33** in Figma's Layer blur (σ = value/2, INFERRED); `blur(2.67px)` in CSS; **8** for `CIGaussianBlur`; **25.6** in GIMP 2.8 (σ = (r+1)/3.329); **13.0** for Android `RenderEffect` (σ = 0.57735·r + 0.5); Photoshop: `UNVERIFIED`. Point-based tools are converted at 3 px per pt; pixel-based tools act on the 894-px specimen. `Next step` is the primary bottom button. | The descent has begun. |

Design rules this sequence depends on:

1. **The probe is pre-placed and the primary button names it.** The first thing the user reads is a coordinate, not an instruction.
2. **Rail chips are live but still.** They change only when an accepted value changes; they never animate on their own.
3. **First launch is deterministic.** Gaussian, σ = 4.0 px, Siemens star, probe at (412, 287), linear light, clamp edges. Later launches restore the last state (blur, parameters, specimen, probe) from `@SceneStorage`/`UserDefaults`; nothing about state needs to be durable beyond the device.
4. **VoiceOver first focus** is the specimen: "Specimen, Siemens star, blurred with Gaussian, sigma 4.0 pixels. Probe at 412, 287. Adjustable: swipe up or down to move the probe one pixel. Actions: Descend from this pixel."

## 3. Information architecture

**No tab bar.** A glass tab bar floating over live content cut controls in half in QuantumToy and Los Alamos (METRO §F.3 item 3, §F.4 item 5), and a descent app has one spine, not four peers. The spine is a `NavigationStack` whose root is the Lab. Everything else is a push (the Trace, This phone) or one of the sheets presented from a **single** `.sheet(item: $destination)` enum (two `.sheet` modifiers on one view silently failed in Toothpaste Toy, METRO §F.5 item 3).

```
Lab (root, NavigationStack, ScrollView .id(blur.id))
 ├─ first viewport: header · selector row · SPECIMEN INSTRUMENT (+ KERNEL / FREQ pills)
 │                  · crowns or Stepper · DESCENT RAIL · floating group
 ├─ below the fold: telemetry row · FLOOR 1 … FLOOR 7 cards · FINGERPRINT card · parameters panel
 │
 ├─ push  ▸ Trace ("Descend")            stepped walk of one pixel, floor by floor, pass by pass
 │          └─ push ▸ This phone          GPU probe / device card (also reachable from Settings)
 ├─ sheet ▸ Atlas                         Families · Fingerprints · Divergence  (.pickerStyle(.tabs))
 ├─ sheet ▸ Lessons                       30 ready-made pairs (CAT §7) + 4 guided descents
 ├─ sheet ▸ Field guide & Settings        per-blur field guide, global settings, honesty legend
 └─ in place ▸ Compare mode               A/B wipe · difference · floor-aligned descent · twin
```

| # | Screen | Presentation | Reached from | Job (one sentence) |
|---|---|---|---|---|
| S1 | **Lab** | root | launch | One blur, live, with the probe and the seven floors summarised and then expanded below. |
| S2 | **Trace** | push | primary button `Descend`; any rail chip long-press; any floor card's `Walk this floor` | Walk one pixel down the seven floors one step at a time, with what has happened and what happens next kept separate. |
| S3 | **Atlas** | sheet `.large` | blur chip in the selector row | Choose a blur; compare all blurs by fingerprint; find the floor where any two blurs part ways. |
| S4 | **Lessons** | sheet `.large` | floating group, right button | Ready-made pairs and guided descents that set up the specimen, parameters and probe for one concept and state the number to look for. |
| S5 | **Compare** | in-place mode of S1 | floating group, left button; any lesson | Two blurs (or a blur and its system twin, or its CPU reference) on one specimen, with a wipe, a difference map and a floor-by-floor comparison. |
| S6 | **Field guide & Settings** | sheet, `NavigationStack` + `Form` + Done | header glass icon button | The current blur's field guide with citations; global settings; the honesty-label legend; the "lens on this instrument" disclosure. |
| S7 | **This phone** | push (from S2 GPU floor, or S6) | `Measure this phone` | Measures and records the A17 Pro facts the GPU floor depends on, replacing REFERENCE/MODELED values with MEASURED ones. |
| — | Specimen menu | native `Menu` in the selector row | — | Pick one of the procedural test images, or a photo (`PhotosPicker`, no permission prompt, SDK §10). |

**Why the floors live in the Lab scroll and also in the Trace.** They answer two different questions. The floor *cards* in the Lab are a reference you browse: all seven floors for the current parameters, each with its numbers. The *Trace* is a narrative you step through: it shows intermediate states (after tap 7 of 25, after the horizontal pass, after the barrier) that a static card cannot. AssemblerToy has the same split between its Layers atlas and its Guide, and the user accepted it after the build-6 ergonomics pass (METRO §F.1 items 7–8).

**State model (one object).** `Descent = (blurID, variantID, parameters, specimenID, probe, colourSpace, edgeMode, precision)`. Every screen reads it; only the Lab's controls, the Atlas and Lessons write it. Compare holds a second `Descent` (B). Requested and rendered states are separate (Metro §7): controls show the requested values immediately; the specimen, pills, rail values, telemetry and floor cards describe the frame actually rendered, and the fixed status row says `RENDERING…` while the two differ.

## 4. Wireframes (430 x 932 pt)

Conventions for every wireframe: iPhone 15 Pro Max portrait, 430 × 932 pt at scale 3 (1290 × 2796 px; VERIFIED from the simulator device profile, METRO §D.0). Safe-area insets are taken as 59 pt top and 34 pt bottom; these are the commonly published values and are **UNVERIFIED** until read from `GeometryReader` on the phone (METRO §G.2 item 2). One character of ASCII is about 5 pt horizontally; the left column gives screen y in points. Screen inset 12 pt, so the content column is x 12…418 (406 pt) and Metro's cluster formula gives D = 322, pill width 36, pill height 212.5 (METRO §B.6). Every component named is from the Metro starter, the Metro source app, or a Blur2ool component built in Metro grammar (METRO §C.0, §E.2 names); sizes are given in the tables under each sketch.

What I looked at to make these fit the real Metro look: Metro `visual-reference.png` (tokens, the three material families, layer ownership); Metro Station `Documentation/crowns-v4-preview.jpg` (crown pair with ± glass buttons, three-column telemetry, beat-grid tiles, signal lab, three-button floating group with a flexible amber primary); ClassicalMLSimulator `Documentation/Screenshots/workbench.jpg` (eyebrow + headline header, model chip, plot panel with a `READY` chip); AssemblerToy `Documentation/Ergonomics/After/06-guide-registers-compact-build6.jpg` (pinned context card, Completed in amber / Next in cyan, 5-tile layer selector, Back · Restart · Next bottom row) and `Documentation/QA/layer-atlas.jpg` (`LAYER 6 OF 14` eyebrow, FOLLOW THE PIXEL / GOVERNING RULE / IN THIS TOY, ↓ Lower / ↑ Higher layer buttons).

### W1. Lab, first viewport (blur with a continuous primary parameter)

```
  y  ┌────────────────────────────────── 430 pt ───────────────────────────────────┐
   0 │ 9:41                        ( Dynamic Island )                     ▂▄▆ ◔ ▮ │ environment (canvas #060B0F + cyan wash 0.085 + 28-pt grid) runs under it
  59 ├──────────────────────────────────────────────────────────────────────────────┤
  69 │  Blur2ool                                                          ╭──────╮ │ header: title 27 pt semibold rounded
     │  BLUR SIMULATOR · WYSIWYG → GPU                                    │ book │ │ subtitle 11 pt mono, tracking 2.6
 118 │                                                                    ╰──────╯ │ InstrumentGlassIconButton 44×44 (field guide & settings)
 130 │ ╭────╮ ╭────╮ ╭──────────────────────────────────────────────╮ ╭────╮     │ selector row, 44 tall, spacing 8
     │ │ ▦  │ │ ‹  │ │ F2 · GAUSSIAN & APPROXIMATIONS                │ │ ›  │     │ specimen Menu 44 · prev 44 · BLUR CHIP 250×44 · next 44
     │ ╰────╯ ╰────╯ │ Gaussian   · separable · linear-sampled    ⌄ │ ╰────╯     │ (chip opens the Atlas)
 174 │               ╰──────────────────────────────────────────────╯            │
 186 │   ╔══════════════════════════ housing 322 × 446 ══════════════════════╗   │ SpecimenHousing, radius 30, metal gradient, 1.4-pt rim
     │ K ║ SIEMENS STAR · 36 CYCLES                         LIVE · METAL    ║ F │ caption row 11 pt mono in the 24-pt top margin
 210 │ E ║ ┊┊┊┊┊┊┊┊┊┊┊┊┊┊┊┊┊ ruler (minor 8 px, major 64 px) ┊┊┊┊┊┊┊┊┊┊┊┊┊ ║ R │
     │ R ║ ┌──────────────────── image window 298 × 298 pt ─────────────────┐║ E │ MTKView 894×894 px, LIVE GPU output
 253 │ N ║ │                         ╲  │  ╱                                 │║ Q │ pills 36 × 212.5, y 252.75–465.25,
     │ E ║ │                      ────(blur)────                            │║   │ centred on the image window
     │ L ║ │                          ╱ ┼ ╲   ← amber probe crosshair        │║ ⎺ │ KERNEL (cyan #4FDBFF): taps vs offset, −3σ … +3σ
     │ ⎺ ║ │                               (412, 287)                        │║ ⎺ │ FREQ (violet #C291FF): |H| vs ν, DC … NYQ,
     │ ⎺ ║ │                                                                 │║ ⎺ │ amber −3 dB carrier mark; magenta = negative lobes
 465 │   ║ │                                                                 │║   │
 508 │   ║ └─────────────────────────────────────────────────────────────────┘║   │
 516 │   ║  SIGMA · PX                                      ╭─ kernel well ─╮ ║   │ readout band y 516–620 (foreground, never filtered)
     │   ║  4.0                                             │ ◎ rings at   │ ║   │ hero 44 pt light rounded, monospaced digits
     │   ║  Softened                                        │ 1σ 2σ 3σ     │ ║   │ meaning: serif italic, instrument cyan
     │   ║  25 TAPS · 2 PASSES · SEPARABLE                  ╰── D = 88 ────╯ ║   │ fixed 14-pt phase/status row
 632 │   ╚═══════════════════════════════════════════════════════════════════╝   │
 644 │        FINE  ±0.1 PX                        SIGMA · Softened             │ crown captions 14 pt
     │    ╭──╮  ╭──────╮  ╭──╮              ╭──╮  ╭──────╮  ╭──╮                │ InstrumentCrown 62×62 between
     │    │ −│  │ ◉◉◉◉ │  │+ │              │ −│  │ ◉◉◉◉ │  │+ │                │ glass ± buttons 44×44 (gap 6)
     │    ╰──╯  ╰──────╯  ╰──╯              ╰──╯  ╰──────╯  ╰──╯                │ FINE cyan (8° = 0.1 px); SEMANTIC amber
 742 │                                         Softened ⇆ Frosted                  │ (20° = one octave stop)
 754 │ ┌─────┐┌─────┐┌─────┐┌──────┐┌─────┐┌─────┐┌─────┐                         │ DESCENT RAIL: 7 floor chips, 54 × 52,
     │ │SLIDE││ API ││MATH ││KERNEL││ALGO ││ GPU ││PIXEL│                         │ gap 4 (event-tile grammar, radius 8)
     │ │1.33 ││ 4.0 ││  G  ││  25  ││ 2×  ││ 13  ││0.52 │                         │ label 11 pt mono; value 13 pt mono digits
 806 │ └─────┘└─────┘└─────┘└──────┘└─────┘└─────┘└─────┘                         │ tap: scroll to that floor card
 828 │  ╭──────────╮ ╭────────────────────────────────────────╮ ╭────────╮        │ floating glass group (GlassEffectContainer 14)
     │  │ ◧ Compare│ │      ⤓  Descend from (412, 287)        │ │ ◫ Less.│        │ Compare 62×58 · Descend flex .glassProminent
 886 │  ╰──────────╯ ╰────────────────────────────────────────╯ ╰────────╯        │ · Lessons 54×58; inset 22, bottom 12
 898 ├──────────────────────── home indicator (34) ─────────────────────────────────┤
 932 └──────────────────────────────────────────────────────────────────────────────┘
```

| Element | Frame (x, y, w, h) pt | Metro component / token | Notes |
|---|---|---|---|
| Environment | full screen | `InstrumentDesignBackground` | Ignores safe areas, hidden from accessibility. |
| Header | 24…406, 69–118 | starter header recipe; `InstrumentGlassIconButton` (AssemblerToy's hardened copy) 44×44 at x 362 | Subtitle hidden at accessibility sizes. |
| Selector row | 12…418, 130–174 | specimen `Menu` 44 · prev/next `InstrumentGlassIconButton` 44 · blur chip 250×44 (content panel grammar, radius 22, eyebrow + name) | Chip shows family eyebrow and `name · variant`; tap opens Atlas. |
| KERNEL / FREQ pills | x 12 and 382, w 36; y 252.75–465.25 | `InstrumentSignalPill` (ported from Metro `MetroStationPillView`) | Static outline; interior eases ≤ 150 ms on accepted changes only. |
| Specimen housing | x 54, w 322; y 186–632 | `SpecimenHousing` (new, tokens `metalLight→metalDark`, rim 1.4 pt, shadow black 0.8 r22 y16) | Caption row + rulers in metal margins. |
| Image window | x 66, w 298; y 210–508 | `MTKView` via `UIViewRepresentable`, 894×894 px | Nothing overlaps it (Specimen rule, METRO §C.1). |
| Readout band | x 66, w 298; y 516–620 | `InstrumentLargeReadout` adapted to band layout | Hero = primary parameter declared by the catalog. |
| Kernel well | 88×88 at x 276; lens 67 | `InstrumentLensSurface(diameter: 88, motionActive: false)` over a `Canvas` face | Engraved footprint; numbers stay outside the glass. |
| Crown row | centred 348 wide; 644–742 | `InstrumentCrown` ×2 (ported) + glass ± buttons | Only when the primary parameter is continuous. |
| Descent rail | 12…418; 754–806 | `DescentRail` (new; `InstrumentEventTiles` grammar: 7 tiles, radius 8, idle white 0.025/0.06, focused cyan 0.08/0.35) | One accessible element per chip: "Floor 4, Kernel, 25 taps". |
| Floating group | label frames 828–886 | `InstrumentFloatingActionGroup` | Primary is cyan when idle, amber while a Trace auto-step or a sweep runs. |

**Deliberate deviation from METRO §D.1.** Metro puts a `DecimalParameterStepper` directly under the hero and the crowns below it. Descent drops the Stepper from the first viewport when the primary parameter is continuous and uses that 60 pt for the descent rail. The crowns already carry real 44×44 glass ± buttons and an accessibility adjustable action (Metro §10, §17), which are the native, non-gesture alternatives; the full `DecimalParameterStepper` is still present in the parameters panel below the fold. For integer-primary blurs (box radius, Kawase iterations, median window) the crown row is replaced by the `InstrumentParameterStepper` (y 644–692, 48 tall) plus the blur's algorithm picker (native segmented `Picker`, y 704–736, e.g. `Separable · Sliding sum · SAT` for box), and the rail sits at y 748–800. Named-primary blurs (bokeh blade shape, median window size) use a segmented picker in the Stepper's place. In every case the first viewport ends on a whole component above the measured floating group (METRO §F.3 item 3); if the measured glass is taller than its 58-pt label frame, the difference comes out of the housing's top margin (24 → 18 pt), never out of the image window (METRO §D.1).

### W2. Lab, below the fold (scrolled: telemetry, floor cards, fingerprint)

Scrolling the Lab *is* descending: the specimen scrolls away and the seven floor cards follow in order. Coordinates below are content offsets from the top of the scroll content (the first viewport ends at about 806).

```
 818 ┌──────────────────────────────────────────────────────────────────────────────┐
     │  σ EFF               │  TAPS / PX            │  GPU                          │ telemetry row 64 (InstrumentMetricReadout ×3,
     │  3.96 px             │  26 fetches           │  0.61 ms                      │ dividers 1×30 white 0.10)
     │  [= COMPUTED]        │  [= COMPUTED]         │  [⏱ MEASURED · A17 Pro]       │ HonestyBadge under each label
 882 ├──────────────────────────────────────────────────────────────────────────────┤
 894 │ ╭ FLOOR 1 / 7 · WYSIWYG ───────────────────────────────── [? INFERRED] ╮     │ FloorCard (content panel, r 22, pad 16)
     │ │ What would you type to get σ = 4.0 px here?                           │     │ title: body semibold
     │ │ ┌─ probe inset 112×112 ─┐  SwiftUI  .blur(radius:)   1.33 pt  [⏱]    │     │ left: plot inset (surface.plot, r 10)
     │ │ │  ▁▂▃ typed value      │  Figma    Layer blur        2.67     [?]    │     │ right: 4 tool rows, value + unit + badge
     │ │ │  bar per tool,        │  CSS      blur()            1.33 px  [▤]    │     │ (rows chosen by the "home tool" set)
     │ │ │  same σ               │  Photoshop Gaussian Radius  —  UNVERIFIED   │     │
     │ │ └───────────────────────┘  ▸ All 14 tools                             │     │ DisclosureGroup
     │ │ GOVERNING RULE  σ = value (CSS, SwiftUI*, CI) · σ = value/2 (shadows,  │     │ callout mono, instrument cyan
     │ │                 Figma) · σ = 0.577·value + 0.5 (Android, Skia)         │     │
     │ │ [ Walk this floor › ]                          [ Type a number ⇄ ]     │     │ two 44-tall text buttons
1126 │ ╰───────────────────────────────────────────────────────────────────────╯     │ card height fixed 232
1138 │ ╭ FLOOR 2 / 7 · API ─────────────────────────── [= COMPUTED] [⏱ MEAS.] ╮     │
     │ │ ...                                                                     │     │
1370 │ ╰───────────────────────────────────────────────────────────────────────╯     │
1382 │ ╭ FLOOR 3 / 7 · MATH ──────────────────────────────────── [= COMPUTED] ╮     │
     │ │ G(x) = e^(−x²/2σ²) / (σ√2π)       Ĝ(ν) = e^(−2π²σ²ν²)                 │     │
     │ │ ┌───────────────────────┐  FWHM          9.42 px                       │     │
     │ │ │  ╱‾‾╲  G(x)   ¦ probe │  half-amp ν   0.0469 c/px                   │     │
     │ │ │ ╱    ╲ ......¦ offset │  10–90 edge   10.25 px                      │     │
     │ │ └───────────────────────┘  Nyquist gain 5·10⁻³⁵                       │     │
     │ │ ...                                                                     │     │
1614 │ ╰───────────────────────────────────────────────────────────────────────╯     │
     │                 … FLOOR 4 KERNEL · FLOOR 5 ALGORITHM (with pass tiles) …       │
     │                 … FLOOR 6 GPU · FLOOR 7 PIXELS …                               │
2604 │ ╭ WHAT MAKES IT UNIQUE ─────────────────────────────── fingerprint card ╮     │ FingerprintCard, ≈ 368 tall (§8)
     │ │ ...                                                                     │     │
2940 │ ╰───────────────────────────────────────────────────────────────────────╯     │
2952 │ ╭ PARAMETERS ──────────────────────────────────────────────────────────╮     │ content panel: DecimalParameterStepper (σ),
     │ │ [ SIGMA         −   4.0 px   + ]   [ TRUNCATION  2 · 2.5 · [3] · 4 ]  │     │ segmented pickers, edge / colour / precision
     │ │ [ VARIANT  2-D · separable · [linear-sampled] · IIR ]                  │     │
     │ │ [ EDGE  clamp · mirror · wrap · zero ]  [ SPACE  [linear] · sRGB ]    │     │
3188 │ ╰───────────────────────────────────────────────────────────────────────╯     │
3200 │                      bottom reserve = measured group height + 28              │
     └──────────────────────────────────────────────────────────────────────────────┘
```

| Element | Height | Component | Notes |
|---|---|---|---|
| Telemetry row | 64 | `InstrumentMetricReadout` ×3 + `HonestyBadge` | `σ EFF` (2 dp), `TAPS / PX` (integer, with noun), `GPU` (2 dp, rolling median of 30, ≤ 4 Hz). In the Simulator GPU shows `—  no GPU timing in Simulator` (GPU §2.7). |
| Floor card ×7 | 232 each, gap 12 | `FloorCard` (new): content panel; eyebrow `FLOOR n / 7 · NAME`; title; 112×112 plot inset; four right-hand readout rows; GOVERNING RULE; two 44-tall buttons | **Fixed height** whatever the blur (AssemblerToy "changing content moved panels", METRO §F.1 item 2). Overflow goes into `All … details` (`DisclosureGroup`), which is the only thing that grows. |
| Pass tiles | inside Floor 5 | `InstrumentEventTiles` (37 tall, radius 8, gap 7) | One tile per GPU pass; tapping a tile shows that pass's intermediate texture in the specimen (METRO §C.7). |
| Fingerprint card | ≈ 368 | `FingerprintCard` (§8) | |
| Parameters panel | ≈ 236 | content panel with `DecimalParameterStepper`, `InstrumentParameterStepper`, native segmented pickers | All secondary controls live here, never in the first viewport. |
| Bottom reserve | group height + 28 | — | Nothing interactive may end under the floating group (METRO §F.1 item 5). |

(Values in W2 such as `GPU 0.61 ms` are placeholders that show format and badge; on device they are MEASURED.)

### W3. Trace ("Descend"), pushed

The AssemblerToy guide pattern, adapted: a compact pinned context card, a floor selector grid, one selected floor's primary facts, and the stepped controls in a bottom `safeAreaInset` (AssemblerToy's accepted exception to floating glass for a stepped flow, METRO §F.1 item 12).

```
  y  ┌──────────────────────────────────────────────────────────────────────────────┐
  59 ├──────────────────────────────────────────────────────────────────────────────┤
  59 │ ‹ Lab                 Pixel 446, 300                                  Done   │ inline navigation bar (44)
 103 ├──────────────────────────────────────────────────────────────────────────────┤
 111 │ ╭──────────────────────────── context card 406 × 168 ─────────────────────╮ │ pinned (does not scroll)
     │ │ ┌ 9×9 texels, 112×112 ┐  GAUSSIAN σ 4.0 px · STEP EDGES · linear     │ │ eyebrow 11 pt mono
     │ │ │ 0 0 0 0 ▣ 1 1 1 1  │  IN    0.000                       [● LIVE]   │ │ 9×9 input texels drawn on a COPY,
     │ │ │ 0 0 0 0 ▣ 1 1 1 1  │  Σ     0.399  after 7 of 13 fetches (pass H) │ │ probe ▣ outlined amber, weights as
     │ │ │ 0 0 0 0 ▣ 1 1 1 1  │  OUT   —      (pass V not run yet)           │ │ amber bars under each texel
     │ │ │ ...  weights ▁▃▅█▅▃▁│  Completed  fetch 7 of 13, pass H (amber)    │ │ Completed: instrument amber
     │ │ └─────────────────────┘  Next       fetch 8 at +7.38 px (cyan)        │ │ Next: action cyan
     │ │  Step 10 / 15 · fragment (446, 300) · pass 1 of 2 · horizontal        │ │ phase metadata 11 pt mono
 279 │ ╰─────────────────────────────────────────────────────────────────────────╯ │
 291 │ ┌──────────┐┌──────────┐┌──────────┐┌──────────┐                            │ floor selector grid: 4 + 3 tiles,
     │ │ 1 SLIDE  ││ 2 API    ││ 3 MATH   ││ 4 KERNEL │                            │ each 95.5 × 54, gap 8
     │ │ done     ││ done     ││ done     ││ done     │                            │ done = amber caption,
     │ └──────────┘└──────────┘└──────────┘└──────────┘                            │ current = cyan fill 0.08 + border 0.35,
     │ ┌──────────┐┌──────────┐┌──────────┐                                        │ ahead = idle (white 0.025 / 0.06)
     │ │ 5 ALGO   ││▐6 GPU   ▌││ 7 PIXEL  │                                        │
     │ │ done     ││▐current ▌││ ahead    │                                        │
 407 │ └──────────┘└──────────┘└──────────┘                                        │
 419 │ ╭ FLOOR 6 / 7 · GPU ─────────────────────── [▤ REFERENCE] [⏱ MEASURED] ╮   │ selected floor panel (scrolls)
     │ │ One fragment, 13 bilinear fetches per pass.                            │   │
     │ │ FETCHES  7 / 13                                     PASS H · 1 / 2    │   │ InstrumentEventTiles header
     │ │ ┌────────────────────────────────────────────────────────────────┐   │   │ texel strip 374 × 64: texels 434…458
     │ │ │ ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  · ▣|·  ·  ·  ·  ·  ·  ·  ·  ·  · │   │   │ as dots, step line after 446,
     │ │ │             ◆     ◆     ◆     ●     ◆     ◆     ◇              │   │   │ fetch positions ◆ done (amber),
     │ │ └────────────────────────────────────────────────────────────────┘   │   │ ◇ next (cyan), ● centre
     │ │ fetch 7: sample(s, uv − 5.4149·texel) → w 0.07818 · value 0.000       │   │ the fetch just done, with its weight
     │ │ GOVERNING RULE  one bilinear fetch at k + b/(a+b) = taps k and k+1     │   │
     │ │ ▸ All GPU details (source · dispatch · bytes · timing · INFERRED lane) │   │ DisclosureGroup
 838 │ ╰─────────────────────────────────────────────────────────────────────────╯ │
 840 │  ╭────────╮  ╭─────────╮  ╭────────────────────────────────────────────╮   │ safeAreaInset(.bottom) 58 tall,
     │  │ ‹ Back │  │ ↺       │  │          ⇥  Next fetch                     │   │ over an opaque canvas strip
 898 │  ╰────────╯  ╰─────────╯  ╰────────────────────────────────────────────╯   │ Back 96 · Restart 62 · Next flex (.glassProminent)
 932 └──────────────────────────────────────────────────────────────────────────────┘
```

| Element | Frame | Component | Notes |
|---|---|---|---|
| Context card | 406 × 168, pinned | content panel; 9×9 texel `Canvas` 112×112 (12 pt per texel + 0.5 gaps); readout rows mono with monospaced digits | `IN`, `Σ` (partial sum while a floor is mid-walk), `OUT` reserve fixed widths; `Completed` amber, `Next` cyan (METRO §F.1 item 8). |
| Floor selector | 4 + 3 tiles, 95.5 × 54 | `InstrumentEventTiles` | Tapping a tile jumps there; floors ahead are allowed (the walk is not a gate), but the context card then shows that floor's state as if the walk had reached it. |
| Floor panel | 406 × flexible | content panel + `DisclosureGroup` | One floor's primary facts only (AssemblerToy GD-1). |
| Bottom row | 58 tall | glass buttons; primary `.glassProminent` | The primary label always names the next unit of work: `Next floor`, `Next pass`, `Next fetch`, `Finish pass` (long-press), `Back to Lab` at the end. |

### W4. Atlas sheet, tab 1: Families

```
  y  ┌──────────────────────────────────────────────────────────────────────────────┐
  ≈70│                         ─── grabber ───                                       │ .large sheet over the Lab
     │  Atlas                                                             Done      │ title largeTitle rounded semibold
     │  ┌ Families ┐┌ Fingerprints ┐┌ Divergence ┐                                  │ Picker(.tabs) (new in iOS 27; on iPhone
     │  └──────────┘└──────────────┘└────────────┘                                  │ renders like .segmented, SDK §12)
     │  🔍 Search 55 blurs, 7 contrasts, 32 variants                                 │ .searchable
     │  F2 · GAUSSIAN & APPROXIMATIONS · 3                       What is the reference │ section header: eyebrow + count +
     │ ┌──────────────────────────────────────────────────────────────────────────┐ │ the family's question (CAT §1)
     │ │ ◎  Gaussian blur                                     O(r) · O(1)   ✓     │ │ row ≥ 64: 40×40 footprint glyph
     │ │    The only blur that is round and separable.        TIER 1 · LIVE       │ │ (same drawing as the kernel well),
     │ ├──────────────────────────────────────────────────────────────────────────┤ │ name body semibold, signature
     │ │ ⁙  Binomial (Pascal) blur                            O(n)                │ │ caption, cost-class chip, tier chip,
     │ │    The Gaussian in integers; erases a 1-px checker.  TIER 1 · LIVE       │ │ selected = cyan ✓ + isSelected trait
     │ ├──────────────────────────────────────────────────────────────────────────┤ │
     │ │ ↺  Recursive (IIR) Gaussian                          O(1)                │ │
     │ │    Any σ for eight multiplies; tails and transients. TIER 1 · LIVE       │ │
     │ └──────────────────────────────────────────────────────────────────────────┘ │
     │  F3 · PYRAMIDS & KAWASE · 3                 How do engines get huge blurs…   │
     │  …                                                                            │
     │  C · CONTRAST: NOT BLURS · 7             What looks like a blur but fails?    │
     └──────────────────────────────────────────────────────────────────────────────┘
```

Tier chips tell the user what the descent will contain for that blur: `TIER 1 · LIVE` (full GPU, all seven floors, full pixel trace), `TIER 2 · LIVE` (GPU, lighter floors, trace of one stage), `TIER 3 · PLOTS` (math, kernel and response floors only, computed on the CPU on a 128×128 crop), `SYSTEM · MEASURED` (Apple's own implementation run live and fitted, beside our model). Variants appear as a disclosure under their parent row, never as separate blurs (CAT §0).

### W5. Atlas sheet, tab 2: Fingerprints (the matrix)

```
     │  Sort: [Family] · Cost · Divergence from Gaussian                Filter ▾      │
     │ ┌──────────────────────┬─────┬─────┬─────┬─────┬─────┬──────┬───────────┐  │ Grid, fixed column widths
     │ │                      │ LSI │ SEP │ ISO │ H≥0 │EDGE │ COST │ PSF  MTF  │  │ header 11 pt mono
     │ ├──────────────────────┼─────┼─────┼─────┼─────┼─────┼──────┼───────────┤  │
     │ │ Box blur             │  ●  │  ●  │  ○  │  ○  │  ○  │ O(1) │ ▢    ▦    │  │ ● yes  ○ no  ◐ approx / skew
     │ │ Tent blur            │  ●  │  ●  │  ○  │  ●  │  ○  │ O(1) │ ◇    ▦    │  │ (shape + text, never colour alone)
     │ │ Gaussian blur        │  ●  │  ●  │  ●  │  ●  │  ○  │ O(r) │ ◎    ◎    │  │ last column: two 28×28 glyphs,
     │ │ Disc blur            │  ●  │  ○  │  ●  │  ○  │  ○  │ O(R) │ ●    ◎̶   │  │ PSF (log scale) and |H| (magenta
     │ │ Hexagonal bokeh      │  ●  │  ◐  │  ○  │  ○  │  ○  │ O(R) │ ⬡    ✳    │  │ = negative lobes, dashed)
     │ │ Zoom (radial) blur   │ LSV │  ○  │  ○  │  —  │  ○  │ O(N) │ ⟋⟍   —    │  │ "—" = no single MTF (LSV / NL)
     │ │ Bilateral            │ NL  │  ○  │  ●  │  —  │  ●  │ O(r²)│ ◑    —    │  │
     │ │ …                    │     │     │     │     │     │      │           │  │
     │ └──────────────────────┴─────┴─────┴─────┴─────┴─────┴──────┴───────────┘  │
     │  Tap a row: its fingerprint card. Tap two rows: open Compare with both.       │
```

Columns: LSI (yes / LSV / NL / E), SEPARABLE (yes / skew / approx / no), ISOTROPIC, POSITIVE MTF (H ≥ 0: no contrast inversion), EDGE-PRESERVING, COST class (CAT §2 vocabulary), PSF and MTF glyphs. Every cell is spoken as words ("Box blur. Linear shift-invariant: yes. Separable: yes. Isotropic: no. Positive response: no, inverts contrast down to minus 0.217…").

### W6. Atlas sheet, tab 3: Divergence

```
     │  Pick two blurs                                                               │
     │  A [ Gaussian · separable        ⌄ ]     B [ Gaussian · linear-sampled ⌄ ]   │ two chips, 197 × 44 each
     │ ┌──────────────────────────────────────────────────────────────────────────┐ │
     │ │ 1 SLIDE      same       σ = 4.0 px from the same typed value             │ │ one row per floor, 44 tall
     │ │ 2 API        same       same parameters                                  │ │ "same" in secondary ink,
     │ │ 3 MATH       same       G(x) = e^(−x²/2σ²)/(σ√2π)                        │ │ first divergent floor in amber with
     │ │ 4 KERNEL     same       25 taps, identical weights                       │ │ a ▶ marker and the reason;
     │ │ 5 ALGO       same       two 1-D passes                                   │ │ later floors in display ink
     │ │▶6 GPU        PARTS WAYS 25 integer fetches vs 13 bilinear fetches/pass   │ │
     │ │ 7 PIXEL      ≈ same     max |A−B| ≤ 1 fp16 ulp; RMS 9.5·10⁻⁵ (MEASURED  │ │
     │ │                          at σ 8, M1 Max; re-MEASURE on A17 Pro)          │ │
     │ └──────────────────────────────────────────────────────────────────────────┘ │
     │  [ Open in Compare ]                                                          │
```

### W7. Compare mode (in place in the Lab)

```
 186 │   ╔══════════════════════════ housing 322 × 446 ══════════════════════╗   │
     │ K ║  A · GAUSSIAN σ 4.0                       B · BOX r 6 (σ 3.74→4.0) ║ F │ A/B engravings in the metal margin,
 210 │ E ║ ┌──────────────────────────────┃──────────────────────────────────┐║ R │ never over pixels
     │ R ║ │                              ┃                                  │║ E │ divider: 44 × 298 hit area, owns its
     │ N ║ │      A (left)          ◀ ━━ ┃ ━━ ▶       B (right)             │║ Q │ touches; "Split at 50 percent",
     │ E ║ │                              ┃                                  │║   │ adjustable ±10 %
     │ L ║ │                              ┃                                  │║   │ pills: A solid, B dashed
 508 │   ║ └──────────────────────────────┃──────────────────────────────────┘║   │
     │   ║  MATCH  σ ⟷        [ Wipe · |A−B| · Floors ]           kernel well A ║   │ segmented: Wipe / Difference / Floors
     │   ║  4.0 / 4.0                                                          ║   │ hero shows A / B primary values
     │   ║  ΔGPU +0.04 ms · ΔTAPS −2 · MAX |A−B| 6 LSB                          ║   │ status row becomes the Δ row
 632 │   ╚═══════════════════════════════════════════════════════════════════╝   │
     │     (crowns drive A; long-press the B engraving to drive B)                 │
 754 │ ┌─────┐┌─────┐┌─────┐┌──────┐┌─────┐┌─────┐┌─────┐                         │ rail in compare: each chip shows
     │ │SLIDE││ API ││▶MATH││KERNEL││ALGO ││ GPU ││PIXEL│                         │ "=" or "≠"; the first ≠ is amber
     │ │  =  ││  =  ││  ≠  ││  ≠   ││  =  ││  ≠  ││  ≠  │                         │
     │ └─────┘└─────┘└─────┘└──────┘└─────┘└─────┘└─────┘                         │
 828 │  ╭──────────╮ ╭────────────────────────────────────────╮ ╭────────╮        │ left button becomes Done
     │  │  Done    │ │      ⤓  Descend both from (412, 287)   │ │ ⇄ Swap │        │ right becomes Swap A⇄B
```

(`ΔGPU`, `ΔTAPS` and `MAX |A−B|` in this sketch are placeholders for format. The box shows the MATCH σ rule: box r = 6, w = 13 has σ = √((169−1)/12) = 3.74 px; matching σ = 4.0 needs w ≈ √(12·16 + 1) = 13.9, so a fractional "extended box" (Gwosdek et al. 2011, LSI §7) or the nearest odd width with the residual stated: `σ 3.74 → 4.0 needs w 13.9; showing w 13 (Δσ −0.26 px)`. COMPUTED here.)

### W8. Lessons sheet

```
     │  Lessons                                                            Done      │
     │  GUIDED DESCENTS · 4                                                          │
     │ ┌──────────────────────────────────────────────────────────────────────────┐ │ content panel rows ≥ 72
     │ │ ⤓ One pixel through a Gaussian         7 floors · 15 steps · Step edges   │ │
     │ │ ⤓ Why zoom blur spares a star          7 floors · 12 steps · Siemens star │ │
     │ │ ⤓ The blur that looks before it averages 7 floors · 14 steps · Noisy step │ │
     │ │ ⤓ Three line blurs make a hexagon      7 floors · 16 steps · Night city   │ │
     │ └──────────────────────────────────────────────────────────────────────────┘ │
     │  PAIRS THAT TEACH · 30                                     (CAT §7, P1–P30)   │
     │ ┌──────────────────────────────────────────────────────────────────────────┐ │
     │ │ P1  Box vs Gaussian at equal σ           Look for: reversed spokes, −0.217│ │ "Look for" = the one number the
     │ │ P4  2-D vs separable Gaussian            Look for: 3,721 → 122 taps       │ │ lesson is about, with its badge
     │ │ P18 sRGB vs linear blur                  Look for: 0.500 vs 0.735          │ │
     │ │ P26 SwiftUI .blur vs our Gaussian         Look for: σ ≈ 0.90·r above 5 px  │ │
     │ │ …                                                                        │ │
     │ └──────────────────────────────────────────────────────────────────────────┘ │
```

A lesson sets blur(s), variant, parameters, specimen and probe, opens Compare if it is a pair, and puts its "look for" sentence in the Lab's fixed status row until any control changes.

### W9. Field guide & Settings sheet

```
     │  Gaussian blur                                                      Done      │ NavigationStack + Form
     │  FIELD GUIDE                                                                   │
     │   Signature        "The only blur that is round and separable…"               │
     │   Definition       G(x) = …                                   [▤ REFERENCE]   │
     │   Where it is used CSS blur(), CIGaussianBlur, MPS, SIFT …    [▤ REFERENCE]   │
     │   Sources          Getreuer 2013 · Lindeberg 1990 · Rákos 2010 ›               │
     │  SPECIMEN & PIXELS                                                             │
     │   Colour space     Linear light ✓ · sRGB-encoded                               │
     │   Edge mode        Clamp ✓ · Mirror · Wrap · Zero · Renormalise                │
     │   Alpha            Premultiplied ✓ · Straight                                  │
     │   Accumulator      fp32 ✓ · fp16                                               │
     │   Live preview     Full resolution ✓ · Half while dragging                     │
     │  WYSIWYG                                                                       │
     │   Home tool        SwiftUI (pt) ✓ · CSS · Figma · Photoshop · Core Image …      │
     │  INSTRUMENT                                                                    │
     │   Haptics ✓   Tilt optics (off in v1)   Badges: always / on tap                │
     │  HONESTY LABELS ›   THE LENS ON THIS INSTRUMENT ›   THIS PHONE ›               │
```

### W10. This phone (pushed from the GPU floor or Settings)

```
     │ ‹ GPU floor            This phone                                              │
     │ ╭ iPhone 15 Pro Max · A17 Pro · iOS 27.x ──────────────── [⏱ MEASURED] ╮     │
     │ │ GPU family            Apple9                 Feature tables: Apple9 [▤]  │     │ every row: MEASURED value beside
     │ │ Threadgroup memory    32,768 B               REFERENCE 32 KB       [▤]  │     │ the REFERENCE value
     │ │ Threads / threadgroup 1024                   REFERENCE 1024        [▤]  │     │
     │ │ SIMD width            32                                              │     │
     │ │ Bilinear sub-texel    —  [ Measure ]          M1 Max: 8 bits        [⏱]  │     │
     │ │ generateMipmaps       —  [ Measure ]          M1 Max: 2×2 box       [⏱]  │     │
     │ │ Copy bandwidth        —  [ Measure ]          leak-derived 51.2 GB/s UNVERIFIED │
     │ │ Compression A/B       —  [ Measure ]          M1 Max: 1.3–1.5×      [⏱]  │     │
     │ │ Counter sampling      —                       Metal 4 heaps .precise      │     │
     │ ╰──────────────────────────────────────────────────────────────────────╯     │
     │  [ Measure everything · ~20 s ]   thermal state: nominal                       │ records thermalState and Low Power
```

Measurements run once on demand, are cached on the device with the OS build and date, and replace the MODELED/REFERENCE numbers in the GPU floor with MEASURED ones (GPU §9 "GPU probe" screen). Nothing here needs a network.

## 5. The primary object

**The Specimen instrument, and the probe pixel inside it.** Metro asks for one primary object with a large, stable value (Metro §8, METRO §C.1). In Descent the *object* is the Specimen instrument (rectangular metal housing, live GPU image window, readout band, kernel well), its *value* is the blur's primary parameter (σ, radius, length, iterations, as declared per blur in the catalog), and its *subject* is the **probe**: one output pixel that every floor talks about.

Why a rectangle and not Metro's round gauge: blur results are judged on square pixel grids and the specimens are square; putting the hero numeral in the face would hide the pixels being blurred. Metro §8 allows a content view with an adjacent text block, and AssemblerToy's `AT-8 / LIVE OUTPUT` display and Los Alamos's `TRINITY / OBSERVATION 01` are accepted precedents (METRO §C.1, §F.4). I agree with the research recommendation and do not offer the round eyepiece variant.

The probe:

- **Placement.** A tap on the image window places the probe on the nearest output pixel centre (`SpatialTapGesture`, which does not fight the scroll pan; the touch bridge is never put on the whole 298-pt window, METRO §C.1 "Touch"). Accessible alternative: the specimen is an adjustable element (swipe up/down moves the probe ±1 px along x; a rotor item switches to y), plus `Centre probe` and `Probe to brightest pixel` actions.
- **Drawing.** An instrument-amber crosshair of 0.9-pt lines with a 3-px gap around the probed pixel, so the pixel itself is never covered. No glass, no magnifier over the specimen: a glass loupe would add the system's refraction to the very pixels being inspected (METRO §F.5 item 2). Magnification happens only on a *copy* (the 9×9 texel grid in the Trace context card and the floor-card insets).
- **Units.** The probe coordinate is in specimen pixels (0…893). The housing engraving states the scale once: `1 px = 0.33 pt` (derived from the drawable, never hard-coded, METRO §D.7).
- **Persistence.** One probe per specimen, restored with the Descent state. Changing blur keeps the probe; changing specimen restores that specimen's last probe (or its default, chosen to sit on the specimen's most informative feature: a spoke edge, the step, a light's centre).
- **Second handle for shift-variant blurs.** Zoom, spin, god rays, tilt-shift and variable blurs also have a **centre** (or a focus line). It is a 44×44 touch-owning handle drawn as a cyan ring with a dot, shown only for those blurs, with `Centre on probe` as the button alternative and adjustable x/y in the parameters panel. The probe and the centre are different colours (amber vs cyan) and different shapes (crosshair vs ring).

The **kernel well** (88-pt native clear lens over a decorative `Canvas`, METRO §C.2) shows the blur's footprint engraved: Gaussian rings at 1σ/2σ/3σ with tap dots on the axes; a square for box; a coin for disc; a hexagon of three rhombi for polygonal bokeh, each rhombus in its own hatch; a ray segment for zoom (the one at the probe); a ring plus the engraved word `DATA-DEPENDENT` outside the glass for bilateral. The lens centre never moves, its opacity is constant 0.48 (1.0 under Reduce Transparency), and no number sits under the glass (METRO §F.3 item 2).

## 6. The descent: seven floors, four worked examples

### 6.0 The floors in general

Each floor answers one question about the probe and has one probe inset (the 112×112 plot inset on its card), a fixed set of readout rows, a governing rule and an `IN THIS APP` honesty line. The structure is identical for every blur; only the content changes. A blur that has nothing honest to say at a floor shows an engraved empty state with the reason (`N/A · NONLINEAR`, `NO SINGLE MTF · SHIFT-VARIANT`, `SYSTEM INTERNALS · INFERRED`), never a blank (Metro §16 "Error/clear empty state").

| # | Floor | Question it answers about the probe | Probe inset (112×112) | Typical badges |
|---|---|---|---|---|
| 1 | **WYSIWYG** (the designer's slider) | What number would a person type, in which tool, to get exactly this blur here? | Horizontal bars: the typed value per tool for the same σ, plus the reverse mode ("you typed 10: σ per tool", STACK §8) | REFERENCE (specs, vendor source), MEASURED (Apple APIs on the Mac, re-measured on device), INFERRED (Figma, Photoshop), UNVERIFIED (Photoshop Radius) |
| 2 | **API** | What call does that become, what does each argument mean, and in what units, colour space, edge policy and alpha mode? | The call as code (callout mono), with each argument underlined and its meaning on tap | REFERENCE, MEASURED, COMPUTED |
| 3 | **Math** | What continuous operator is this, and what does it do to each frequency? | The continuous PSF profile with the probe's footprint marked; or the local PSF for LSV; or the weight formula for NL | COMPUTED, REFERENCE |
| 4 | **Kernel** | What finite numbers (taps, weights, offsets) approximate that operator, and what did discretisation cost? | Discrete stems over the continuous curve; for 2-D kernels, a heat map of weights centred on the probe | COMPUTED (LSI), LIVE (NL: the weights depend on the image) |
| 5 | **Algorithm** | In what order, in how many passes, with what intermediate images, is the kernel applied? | The probe's neighbourhood after each pass (tap a pass tile to see it full-size in the specimen) | COMPUTED, LIVE |
| 6 | **GPU** | Which thread computed the probe, what did it fetch from where, how long did it take, and what did it cost in bytes? | The dispatch geometry around the probe: threadgroup rectangle, SIMD band, apron, fetch positions on the texel grid | REFERENCE (code, feature tables), MEASURED (timings, limits), MODELED (bytes, bandwidth floors), INFERRED (Apple's own blur) |
| 7 | **Pixels** | What value went in, what came out, how was it encoded for the screen, and does the CPU reference agree? | 9×9 input and output values side by side, probe outlined; parity |GPU − CPU| in 8-bit steps | LIVE, MEASURED (parity), COMPUTED (encoding) |

The **rail chips** in the first viewport are the one-line summaries of these seven cards; the **Trace** steps through them with intermediate states. The GPU floor always names which implementation variant is running (the Algorithm floor's variant picker drives it), so the GPU floor never shows code that is not the code that ran: the `.metal` source shown on screen ships as a text resource next to the precompiled `default.metallib` (runtime compilation is too slow on first use: 1 s on the Mac, 6–19 s in the Simulator, SDK §14), a unit test asserts that the shipped text is byte-identical to the compiled source, and the Mac parity CLI compiles the same text with `makeLibrary(source:)` (GPU §5 item 1, §6.3).

### 6.1 Gaussian (`gaussian-blur`, variant `gaussian-linear-sampling`)

**Set-up (the "One pixel through a Gaussian" guided descent).** Specimen *Step edges*, vertical black|white step: pixels x ≤ 446 are 0.0, x ≥ 447 are 1.0 (linear light, rgba16Float). Probe **(446, 300)**, the last black pixel. σ = 4.0 px, truncation k = 3 (r = ⌈3σ⌉ = 12), sampled discretisation, clamp edges, linear-light blending, fp32 accumulators. Numbers marked "COMPUTED (here)" were computed for this document with `$TMPDIR/blur2ool-concept-descent/gauss.py`.

| Floor | What the card displays | Real numbers (badge) |
|---|---|---|
| 1 WYSIWYG | "To get σ = 4.0 px on this phone, type:" One row per tool, home tool first. A toggle flips to "You typed 4: what σ does each tool give?" | SwiftUI `.blur(radius: 1.33)` pt → 4.0 px: in the measured small-radius regime (r·scale ≤ 5 px: σ ≈ r·scale within 1.2%; MEASURED macOS 27.2, CAL §5.1; INFERRED for iOS until `measurePSF` runs on the phone). CSS `filter: blur(1.33px)` (σ = value, REFERENCE Filter Effects 1). Figma Layer blur **2.67** (σ = value/2, INFERRED from Dev Mode export, STACK §4.1). `CIGaussianBlur` radius **4** and `MPSImageGaussianBlur` sigma **4** (σ = value, MEASURED). Android `RenderEffect` radius **6.06 px** (σ = 0.57735·r + 0.5, REFERENCE AOSP). OpenCV `GaussianBlur(ksize 25×25, sigmaX 4)` (ksize = 2·3σ+1 for 8-bit, REFERENCE). GIMP 2.10 Size **4**; GIMP 2.8 Blur Radius **12.3** (σ = (r+1)/3.329, REFERENCE source). ImageMagick `-blur 0x4` (a bare `-blur 4` would be σ = 1.0!). Photoshop Gaussian Blur Radius: **UNVERIFIED** (STACK §4.3). |
| 2 API | Our call and three Apple twins, each with units, colour space, edge policy, alpha. The point of this card: three Apple APIs give the same σ = 4 but **not the same pixel** at the probe, because they differ in colour space and edges. | Ours: `b2ool_gauss_linear_fs`, σ 4.0 px, k 3, clamp, linear, premultiplied. `CIGaussianBlur(4)`: σ = r, blends **linear light** (default context), transparent edges unless `clampedToExtent()` (MEASURED, CAL §5.2). `MPSImageGaussianBlur(sigma: 4)`: σ = sigma, "approximate Gaussian… ~10 bits" (REFERENCE header; MEASURED σ/sigma 0.993–1.037), filters the stored numbers. SwiftUI `.blur(radius: 1.33)`: blends **gamma-encoded** values in the default `.nonLinear` mode, transparent (decal) edges with `opaque: false`, normalised convolution with `opaque: true` (MEASURED, STACK §3.1). |
| 3 Math | `G(x) = e^(−x²/2σ²) / (σ√2π)`, `Ĝ(ν) = e^(−2π²σ²ν²)`. Probe inset: G(x) with the probe's footprint ±3σ marked as an amber bracket; the step position marked 0.5 px to the right of the probe. | Peak 1/(4√2π) = **0.0997**; FWHM 2.3548σ = **9.42 px**; half-amplitude frequency 0.1874/σ = **0.0469 c/px**; 10–90% edge width 2.563σ = **10.25 px**; Ĝ(0.5) = e^(−π²·16/2) ≈ **5·10⁻³⁵** (COMPUTED). Separable *and* isotropic, the only such kernel (Herschel–Maxwell argument; CAT §5 E17 corrects the earlier Kac 1939 attribution). Semigroup: G₃ * G₄ = G₅. |
| 4 Kernel | 25 stems over the continuous curve; the 13 non-negative offsets listed; truncation shown as a shaded tail. Readouts: taps, discrete σ, mass cut, MTF ripple. | Weights for k = 0…12: **0.09991, 0.09683, 0.08817, 0.07541, 0.06060, 0.04574, 0.03244, 0.02161, 0.01352, 0.00795, 0.00439, 0.00228, 0.00111** (sampled, renormalised; COMPUTED here). Discrete σ **3.963 px** (−0.9% from truncation). Continuous mass beyond ±3σ **0.27%**. Truncation makes the discrete MTF dip to **−0.0010** and leaves **7.1·10⁻⁴** at Nyquist instead of 5·10⁻³⁵: a 1-px checkerboard survives at 0.07% contrast, under a fifth of an 8-bit step (COMPUTED here). |
| 5 Algorithm | Variant picker (2-D · separable · **linear-sampled** · IIR). Pass tiles `H 13` · `V 13`. Inset: the probe's 9×9 neighbourhood after pass H, then after pass V. | 2-D direct **625** taps/px; separable **50**; linear-sampled **26** fetches/px (1 + 2⌈12/2⌉ = 13 per pass); IIR ≈ 8 MACs per direction regardless of σ (COMPUTED, LSI §2–§4). After pass H the probe is already **0.4500**; pass V leaves it unchanged, because a vertical edge is constant along each column. (On the Siemens star the same card shows the half-blurred horizontal streak, the clearest picture of separability, LSI §3.) |
| 6 GPU | Fragment shader `b2ool_gauss_linear_fs`, source shown; one full-screen triangle per pass; sampler `filter::linear, clamp_to_edge`; the 13 fetch positions drawn between texel centres around (446, 300); bytes and time. A second tab shows the compute variant's threadgroup geometry. An INFERRED lane says what Apple's own `.blur` does instead. | Bilinear offsets (texels) **0, ±1.4766, ±3.4455, ±5.4149, ±7.3849, ±9.3558, ±11.3277** with weights **0.09991, 0.18500, 0.13601, 0.07818, 0.03513, 0.01234, 0.00339** (COMPUTED here, Rákos 2010 pairing). The first pair samples x = 447.48: texels 447 and 448 mixed at t = 0.477, which the texture unit rounds to 8 sub-texel bits (MEASURED 8 bits on M1 Max and Simulator, GPU §2.3; A17 Pro: to MEASURE in This phone). Intermediate and output 894×894 `rgba16Float` (6.39 MB each), created **without** `.shaderWrite` so they stay losslessly compressible on Apple9 (REFERENCE, Tech Talk 111431). Traffic ≈ 4 × 6.39 = **25.6 MB** per blur (MODELED); bandwidth floor ≈ 0.5 ms at the leak-derived 51.2 GB/s (MODELED on an UNVERIFIED peak); GPU time: MEASURED on device. Compute variant: threadgroup **(1, 300)** of 256×1, thread 190, SIMD-group 5 lane 30; 3,072 B threadgroup memory; 1 + 2·12/256 = **1.094** texture loads per pixel (COMPUTED). INFERRED lane: SwiftUI's on-screen blur is a private `CAFilter gaussianBlur` run by the render server (`backboardd`), using QuartzCore kernels named `tile_downsample_*`, `tile_simd_blur_5…27`, `upsample_*` (GPU §1.1). |
| 7 Pixels | IN/OUT for the probe and its neighbours; encoding to 8-bit sRGB; CPU reference; the colour-space toggle as a one-tap A/B. | IN **0.000**. OUT **0.4500** linear → encoded **0.701** → **179/255**. Neighbours x = 445…450: 0.353, **0.450**, 0.550, 0.647, 0.735, 0.810 (COMPUTED here). Blurred in sRGB-encoded space instead (what SwiftUI and CSS do by default), the same weights give encoded **0.450 → 115/255**: 64 levels darker at the same pixel, the P18 lesson (STACK §7). CPU reference `BlurCore` (double) 0.45005; parity |GPU − CPU| shown in 8-bit steps, MEASURED on device. |

What the user should come away with, stated on the last Trace step: "Seven floors, one pixel: you typed 1.33, the GPU fetched 26 times, and the pixel went from 0.000 to 0.450. The floor that most changed the answer was the one nobody shows: the colour space at the API floor (179 vs 115)."

### 6.2 Radial zoom (`radial-zoom-blur`)

**Set-up ("Why zoom blur spares a star").** Specimen *Siemens star*, 36 dark–light cycles (n_c = 36, CAT §5 E7), centred on the texture centre c = (447, 447). Zoom strength a = 0.10, **centred** variant (each output pixel averages the input at scale factors from 1.05 down to 0.95 about c, the form of the `radial_blur` sketch, GPU §6.2), 32 samples, bilinear, clamp, linear light. Probe **(747, 447)**: on the ray θ = 0, r = 300 px from the centre, inside a white wedge. A specimen toggle in every card switches to the *zone plate* `0.5 + 0.5·cos(π k r²)` with k = 0.5/632.2 (local frequency k·r reaches Nyquist at the corners), same centre, same probe.

| Floor | What the card displays | Real numbers (badge) |
|---|---|---|
| 1 WYSIWYG | Tools that offer zoom blur, what their "amount" means, and what to type for a 10% streak. Centre is set by dragging in every tool, so the card also shows the centre handle. | Photoshop *Radial Blur › Zoom*, Amount 1–100, Quality Draft/Good/Best: Amount → strength mapping **UNVERIFIED** (SPA §1.8). Sketch *Zoom blur* (Blur + centre): mapping not documented (REFERENCE controls, STACK §4.2). `CIZoomBlur` `inputAmount`: an outward streak from D to s·D with s = 1.5^(amount/20) (MEASURED fit, STACK §3.4), so a 10% streak needs amount = 20·ln 1.1 / ln 1.5 = **4.70** (COMPUTED here from that law). CAL §5.2 measured length/distance 0.079 at amount 4, about 7% shorter than the law predicts (0.085): the two MEASURED sources disagree slightly, and the card says so (UNVERIFIED which is exact). |
| 2 API | Our call `b2ool_radial_blur(center: (447, 447) px, strength: 0.10, samples: 32, mode: .zoom)`; `CIZoomBlur(inputCenter:, inputAmount:)` as the system twin. The card's point: same picture, different *direction* conventions. | Ours: centred, scales 1.05 → 0.95, weights 1/32. `CIZoomBlur`: one-sided **outward** (D → s·D), weights near-uniform along the streak (MEASURED kurtosis −1.03 to −1.09, CAL §5.2; STACK §3.4 describes them as closer to log-uniform; the difference over a 10% streak is at most 10% in density, and the card shows both readings as MEASURED with their sources). Photoshop: direction convention UNVERIFIED. |
| 3 Math | `g(x) = (1/a) ∫_{−a/2}^{a/2} f(c + (1 − s)(x − c)) ds`. No global MTF: the FREQ pill shows `NO SINGLE MTF · SHIFT-VARIANT` engraved, and the card shows the **local** MTF at the probe instead, plus the log-polar picture in which the blur becomes an ordinary 1-D box. | Local PSF at the probe: a radial segment of length a·r = **30 px** (x 732 → 762 on y = 447), σ along the ray 30/√12 = **8.66 px**, zero across it (COMPUTED here). Local MTF sinc(30·ν_r): zero lines perpendicular to the ray every **1/30 = 0.0333 c/px** (COMPUTED, SPA §1.8). In log-polar coordinates (ρ = ln r) it is a box of width ln(1.05/0.95) = **0.100** in ρ, the same for every pixel: shift-variant in x, shift-invariant in ρ (COMPUTED). A centred Siemens star is invariant under scaling about c, so the operator leaves it unchanged; concentric rings are not, so the zone plate is destroyed. |
| 4 Kernel | The **PSF field**: on the impulse grid every dot becomes a ray pointing at c, longer with distance; the probe's own 32 taps drawn on the texel grid; a tap-spacing heat map (magenta + dashed hatching where spacing > 1 px). | Probe taps at x_i = 447 + 300·(1 − 0.1·(i/31 − 0.5)): **762.0 … 732.0**, spacing **0.968 px**, weight **1/32 = 0.03125** each (COMPUTED here). Sampling condition N ≥ a·r_max + 1: r_max = 447·√2 = **632 px**, so ghost-free corners need **N ≥ 65**; with 32 samples the corner spacing is **2.04 px**, which is why the corners band (COMPUTED here, SPA §1.8 rule). |
| 5 Algorithm | Variant picker: *Gather (fixed N)* · *Gather (adaptive N)* · *Doubling*. One pass tile for gather; k tiles for doubling. | Fixed gather: **32** fetches/px everywhere. Adaptive: N(x) = ⌈a·r⌉ + 1, **31** at the probe, 1 at the centre, 65 at the corners. Doubling: k passes of 2 fetches give 2^k geometrically spaced samples, **k = 6 → 64 samples for 12 fetches** (exact for the geometric-spacing form, COMPUTED SPA §1.8). |
| 6 GPU | Compute kernel `b2ool_radial_blur` (GPU §6.2 sketch 6), source shown; dispatch grid over the specimen; the probe's threadgroup and its 32 bilinear sample positions; time and bytes. | `dispatchThreadgroups(56 × 56, 16 × 16)` = **3,136** threadgroups of 256 threads, with a bounds check that discards the 2 surplus rows and columns (896 − 894) (SDK §15: never `dispatchThreads`, whose non-uniform grids the Simulator's Apple2-class GPU does not support); the probe is thread **(11, 15)** of threadgroup **(46, 27)** (COMPUTED). 32 `sample()` calls with `level(0)`, `clamp_to_edge`. Fetch-bound gather: the cache hit rate falls as the streak grows (GPU §4.1). M1 Max MEASURED 1.08 ms for 32 samples at 2796×1290; scaled by pixel count to 894², ≈ 0.24 ms on the M1 Max and ≈ 1.2 ms on the A17 Pro (both MODELED, the latter with GPU §4.2's rough 5× factor; MEASURED on device replaces both). The output texture needs `.shaderWrite`, so on Apple9 it is not losslessly compressed (REFERENCE, Tech Talk 111431); the card offers the fragment version as the A/B. Parity on the Mac: max error 7.3·10⁻⁴ (fast-math trig plus 8-bit bilinear weights; MEASURED, GPU §6.3). |
| 7 Pixels | IN/OUT at the probe for the star and for the zone plate; the 9×9 neighbourhood. | **Siemens star: IN 1.000 → OUT 1.000.** All 32 taps lie on the ray θ = 0 inside the same white wedge, so the probe is untouched (COMPUTED here; exact in the continuous limit, up to bilinear resampling at wedge edges). **Zone plate: IN 0.082 → OUT 0.508**; local peak-to-peak contrast falls from **1.000 to 0.045** (COMPUTED here with 32 taps). The rings are perpendicular to the ray, so the 30-px streak crosses about seven of them (ν = 0.237 c/px at r = 300). |

The last Trace step says: "The same blur left your pixel exactly as it was on the star and turned it grey on the zone plate. Zoom blur is a box along rays: anything made of rays survives. Its exact dual, spin blur, does the opposite (CAT P21)." The Divergence tab puts zoom and spin side by side: they part ways at **Math** (scaling vs rotation about c); below that floor they keep the same *shape* (one gather of N taps along a curve, the same GPU kernel with a mode switch), which the Divergence rows say in words.

### 6.3 Bilateral (`bilateral`, brute force)

**Set-up ("The blur that looks before it averages").** Specimen *Noisy step*, here with the noise switched **off** so the numbers are exact: a vertical step from 0.40 (x ≤ 446) to 0.60 (x ≥ 447), height 0.20, linear light. Probe **(447, 300)**, the first bright pixel. σs = 3.0 px, σr = 0.10 (fraction of full scale), window radius 8 (17 × 17 taps), range distance on luma, clamp edges. The card's contrast picker switches the step height between 0.05, 0.20 and 1.00 (the three contrasts of CAT P13). Numbers marked COMPUTED (here) come from `$TMPDIR/blur2ool-concept-descent/bilat.py`.

| Floor | What the card displays | Real numbers (badge) |
|---|---|---|
| 1 WYSIWYG | Where people meet this filter and what their two knobs are called. The card is honest that no Apple API offers it. | OpenCV `bilateralFilter(d, sigmaColor, sigmaSpace)`: here **d 17, sigmaColor 25.5, sigmaSpace 3** (REFERENCE, NL A2). After Effects *Bilateral Blur* (Radius, Threshold), "very similar to the result of the Surface Blur filter" (REFERENCE, STACK §4.4). Photoshop *Surface Blur* (Radius, Threshold) is the hard-threshold cousin `surface-blur`, its algorithm INFERRED (NL A10). Threshold → σr: **UNVERIFIED** (a hard gate has no σ). Core Image: none (`CINoiseReduction` is a different operator; `CIEdgePreserveUpsampleFilter` is INFERRED to be the *joint* bilateral). |
| 2 API | `b2ool_bilateral(sigmaS: 3.0 px, sigmaR: 0.10, radius: 8, space: .linear, distance: .luma)`. The card's point: σr is a distance **in whatever space the numbers are in**. | OpenCV's 25.5 acts on 8-bit *encoded* values; ours acts on linear light. The same "0.10" therefore keeps different edges: a 0.40 → 0.60 linear step is 0.665 → 0.797 encoded, a difference of 0.132 (COMPUTED here). The colour-space toggle on this card shows which edges change verdict. |
| 3 Math | `g_p = Σ_q G_σs(‖p−q‖) · G_σr(|f_p − f_q|) · f_q / W_p`. The FREQ pill is engraved `N/A · NONLINEAR`; the card's inset shows the honest replacement, the **amplitude-dependent transfer map T(ν, A)** (NL §0). Verdict chip: ADAPTIVE BLUR (passes convexity, low-pass and shift-invariance; fails linearity and data-independence). | Range weight of a neighbour differing by Δ: e^(−Δ²/2σr²) = **0.61** (Δ = σr), **0.135** (2σr), **0.011** (3σr) (COMPUTED). T(ν = 0.1 c/px, A): **0.178** at A 0.01, **0.214** at 0.03, **0.524** at 0.1, **0.930** at 0.3, against the plain Gaussian's **0.168** at every amplitude (COMPUTED, NL A2): small wiggles are blurred like a Gaussian, large ones pass. Limits: σr → ∞ is the Gaussian; σr → 0 is the identity. |
| 4 Kernel | The **local PSF at the probe**: the 17 × 17 weight map (LIVE: it depends on the image), drawn as a heat map with the step line marked. The KERNEL pill shows the centre row of this map and is labelled `LOCAL · AT PROBE`. Moving the probe changes the kernel, which no LSI blur's card ever does. | At (447, 300) the eight columns on the dark side are scaled by **0.135**; they carry **9.4%** of the total weight, against **43.3%** for a Gaussian of the same σ (COMPUTED here). At the 0.05 step the dark side keeps **40.3%** (almost Gaussian); at the 1.00 step **2·10⁻²²** (none). |
| 5 Algorithm | Variant picker: **Brute force** · Separable (approx.) · Grid (approx.). One pass tile for brute force, two for separable, three (splat, blur, slice) for the grid. | Brute force **289** taps, one `exp` each. Separable **34** taps; RMS error vs brute force 0.0050, max 0.026 on a noisy star, and pass order matters (x→y vs y→x differ by RMS 0.0038) (COMPUTED, NL A4). Grid with cells σs × σs × σr: about 298 × 298 × 11 ≈ **9.8·10⁵** cells for this specimen, more than the 8.0·10⁵ pixels, so at σs = 3 the grid is no bargain; it wins for large σs (COMPUTED here; NL A3 explains why). |
| 6 GPU | Compute kernel `b2ool_bilateral_brute`, 16 × 16 threadgroups with a shared tile plus an 8-px apron; the probe's tile and apron drawn on the specimen; why bilinear tap merging is impossible here. | Tile (16 + 2·8)² = **1,024** texels × 8 B = **8,192 B** of threadgroup memory: fits both the Simulator's 16 KB and the A17 Pro's 32 KB (REFERENCE Feature Set Tables; GPU §2.2). Device loads per output pixel (32/16)² = **4**; the other 285 reads come from threadgroup memory (COMPUTED). The probe is thread **(15, 12)** of threadgroup **(27, 18)**. No linear-sampling trick: each tap needs its own range weight (NL A4). 289 taps × 799,236 px ≈ **2.3·10⁸** weight evaluations per frame (COMPUTED), so the live preview runs at half resolution while a control moves and at full resolution when it stops, and says which (GPU §4.2). Time: MEASURED on device. |
| 7 Pixels | IN/OUT at the probe beside the Gaussian of the same σs; salt-and-pepper toggle. | **IN 0.600 → OUT 0.581** (bilateral) vs **0.513** (Gaussian σ 3): the edge keeps 90% of its height at the probe (COMPUTED here). At the 0.05 step: 0.5049 vs 0.5033 (both blur it). At the 1.00 step: **1.000** vs 0.567. With noise on (σ 0.02), the values become LIVE and the card adds the residual-noise readout (NL A2: noise survives next to strong edges). Salt-and-pepper: a lone impulse has no similar neighbours, so it is **kept**, the opposite of the median (CAT P14). |

The last Trace step says: "This blur asked every neighbour 'do you look like me?' before averaging. On your pixel, the dark side answered 'no' with weight 0.135, and the edge survived: 0.581 instead of 0.513." The Divergence tab puts bilateral against Gaussian: they part ways at **Math** (the range term), and the card adds that they meet again as σr → ∞.

### 6.4 Hexagonal bokeh (`polygonal-bokeh`, triple-rhombus separable construction)

**Set-up ("Three line blurs make a hexagon").** Specimen *Night city*: black background with 1-px point lights stored in **linear light, HDR** (`rgba16Float`), one of them of intensity **100** at (447, 447). Circumradius R = 16 px, rotation 0 (pointy-top), 6 blades, blade curvature 0, no highlight boost, clamp edges. Probe **(447, 455)**, 8 px below that light: black in the input, inside the hexagon in the output (apothem 0.866·16 = 13.9 px). Numbers marked COMPUTED (here) come from `$TMPDIR/blur2ool-concept-descent/hex.py`.

| Floor | What the card displays | Real numbers (badge) |
|---|---|---|
| 1 WYSIWYG | The aperture controls people actually see, and a physical-lens strip: the PSF is an image of the aperture, scaled by the circle of confusion (SPA §2 intro). | Photoshop *Lens Blur*: Iris Shape (triangle … octagon), Radius, Blade Curvature, Rotation (REFERENCE controls; implementation INFERRED, SPA §2.3). Unity URP Bokeh DoF: Blade Count 3–9, Blade Curvature, Blade Rotation, f-number, focal length, with a fixed 42-tap kernel whose largest bokeh is about 14 px of the working buffer (REFERENCE source, STACK §5.1). After Effects *Camera Lens Blur*: Shape, Roundness, Rotation and a "Use Linear Working Space" checkbox "to see realistic bokeh effects" (REFERENCE, STACK §4.4). Stride `TripleRhombiBokeh` with a Phase rotation (REFERENCE). |
| 2 API | `b2ool_hex_bokeh(radius: 16 px, blades: 6, rotation: 0°, curvature: 0, space: .linear, hdr: true)`. System twin: `CIBokehBlur(radius: 16)`, which is a **disc**, so the card pairs it as "nearest Apple equivalent, different shape". | `CIBokehBlur` with default ring and softness is bit-identical to `CIDiscBlur`: a uniform disc of radius r (MEASURED, CAL §5.2). There is no public Apple polygonal-bokeh API (SDK §9 lists the blur filters). |
| 3 Math | `h = 1_hexagon / Area`. The FREQ pill shows the 2-D |H| slice along the axis the user picks; the inset shows the hexagon split into its three rhombi and the zonogon rule. | Area (3√3/2)·R² = **665.1 px²**; per-axis σ = √(5/24)·R = **7.30 px** (a disc with the same σ has R = 14.6 px) (COMPUTED here, SPA §2.3). Each rhombus is the Minkowski sum of two 16-px segments 120° apart, so its spectrum is sinc(16 ν·a)·sinc(16 ν·b)·phase, with zero lines every **1/16 = 0.0625 c/px** along each edge normal; the hexagon's |H| is the sum of three such terms and shows six slow-decaying spokes instead of the disc's circular zeros (COMPUTED, SPA §2.3). **Zonogon rule:** a convex polygon is a sum of segments if and only if it is centrally symmetric, so 4, 6 and 8 blades are exact and 5, 7, 9 are impossible with line passes. |
| 4 Kernel | The three rhombi as tap lattices, one hatch per rhombus, with the probe's position inside one of them; a `BLADES` stepper that, at 5, 7 or 9, turns the lattice into a masked 2-D gather and says why. | 3 rhombi × 16 × 16 = **768** bilinear samples per output pixel, each weight **1/768**, on a skewed lattice whose cell area is sin 120° = 0.866 px² (COMPUTED here). Directions (texture space, y down): **(0, −1)**, **(0.866, 0.5)**, **(−0.866, 0.5)** texels per step, one-sided, the first tap half a step from the pixel (SPA §2.3, after Barre-Brisebois 2017). Five blades: no line construction; a masked gather of about **609** taps (pentagon area 2.5·R²·sin 72°) (COMPUTED here). |
| 5 Algorithm | Two pass tiles: `P1 ↑ ↘ · 2 MRT` and `P2 ↘ ↙`. The inset shows the probe's neighbourhood after pass 1 (two line streaks) and after pass 2 (the hexagon). | Pass 1 writes T1 = blur(src, ↑) and T2 = ½[blur(src, ↑) + blur(src, ↘)]. Pass 2 outputs ⅓·blur(T1, ↘) + ⅔·blur(T2, ↙), which gives each rhombus weight exactly ⅓ (COMPUTED here). Four 1-D blurs × 16 taps = **64 fetches** per pixel, against ≈ **665** for a 2-D gather of the same hexagon (COMPUTED, SPA §2.3). The published two-pass code averages its halves 0.5/0.5; read literally that would weight one rhombus ½ and the other two ¼ each. Its exact normalisation is UNVERIFIED (SPA §2.3), so Blur2ool states its own weights and the card offers a *seam test* that probes along the rhombus boundaries. |
| 6 GPU | Two fragment passes, the first with two colour attachments (MRT); source shown; the probe's 32 + 32 fetch positions drawn as three line segments; time and bytes. | Textures `rgba16Float` 894², 6.39 MB each, render targets without `.shaderWrite`, so compressible on Apple9 (REFERENCE). Traffic ≈ read 6.39 + write 2 × 6.39, then read 2 × 6.39 + write 6.39 ≈ **38.4 MB** per blur (MODELED, ideal cache). 32 fetches per fragment per pass. Pixels near the image border read clamped texels, so a light near the edge grows a smeared half-hexagon (the edge-mode setting on this card changes it). Time: MEASURED on device; the gather alternative (`bokeh_golden`, 64 samples) measured 2.96 ms at 2796×1290 on the M1 Max (MEASURED, GPU §6.3), which the card scales by pixel count as a MODELED comparison. |
| 7 Pixels | IN/OUT at the probe in three versions of the same light: HDR linear (default), HDR blurred in sRGB-encoded space, and an 8-bit clipped light. This is the bokeh lesson. | **IN 0.000 → OUT 0.1504 linear → 0.424 encoded → 108/255** (100 / 665.1; COMPUTED here). Same light blurred in sRGB-encoded space: plateau encoded 0.0107 → linear **0.00083**, i.e. **0.55%** of the correct light: the hexagon all but disappears. A light clipped to 1.0 in 8-bit: **5/255** (linear blur) or **0.4/255** (encoded blur), invisible. "Bokeh needs light that is brighter than white, blurred as light" (SPA §2 intro; STACK §7 item 3). Seam test: max deviation along rhombus boundaries vs the plateau, LIVE. |

The last Trace step says: "Your pixel was black. It turned 0.150 because a light of 100 was spread evenly over 665 pixels in the shape of a hexagon, built from four straight streaks. Change BLADES to 5 and the streak trick stops working: a pentagon is not a sum of line segments." The Divergence tab puts hexagon against disc at the same σ: they part ways at **Math** (aperture shape) and again at **Algorithm** (four line passes vs a 2-D gather or row-span SAT).

## 7. The pixel trace (Guide)

The Trace is the heart of the descent: the AssemblerToy Guide walked one instruction through Assembly → CPU → Registers → Memory → OS; the Blur2ool Trace walks one pixel through Slider → API → Math → Kernel → Algorithm → GPU → Pixels.

**Step grammar.** A walk is a list of **steps**; a step can have **sub-steps** (taps, fetches, iterations) that `Next fetch` advances one at a time and a long-press on the primary button (`Finish pass`) completes. The context card always shows four things in fixed slots: `IN` (the probe's input value), `Σ` (the running partial result while a floor is mid-walk, blank otherwise), `OUT` (the value once known), and the `Completed` / `Next` pair (instrument amber for what has happened, action cyan for what the next tap will do; AssemblerToy GD-2). A step never changes the specimen's parameters; it only reveals.

**The Gaussian walk (15 steps; sub-steps in brackets).**

| Step | Floor | Completed (after the tap) | What the panel shows |
|---|---|---|---|
| 1 | SLIDE | "You would type 1.33 in SwiftUI" | the tool table (§6.1 floor 1) |
| 2 | API | "1.33 pt × 3 = 4.0 px" | the scale conversion and the 5-px regime switch of SwiftUI's own blur |
| 3 | API | "Linear light, clamp, premultiplied" | the three silent parameters, each with an `if you changed this` preview of OUT (179 vs 115 for colour space) |
| 4 | MATH | "G with σ 4.0 px" | formula, profile, spectrum |
| 5 | KERNEL | "25 weights sampled" | stems, weights |
| 6 | KERNEL | "Renormalised after cutting at ±12" | the cut tails, discrete σ 3.963, ripple −0.0010 |
| 7 | ALGO | "Split into H then V" | 625 → 50 taps |
| 8 | ALGO | "Merged into 13 bilinear fetches per pass" | the pairing table |
| 9 | GPU | "Draw call issued for pass H" | render pass, target, sampler, threads (fragments) |
| 10 | GPU | "13 fetches done" [13 sub-steps, Σ grows 0 → 0.185 → … → 0.450] | the texel strip with fetch markers |
| 11 | GPU | "Pass H written: 0.4500" | intermediate texture, compressible |
| 12 | GPU | "Pass V: 13 fetches, value unchanged" [13 sub-steps] | why V does nothing on a vertical edge |
| 13 | GPU | "GPU time 0.xx ms" | the pass timeline, MEASURED |
| 14 | PIXEL | "OUT 0.450 linear" | 9×9 in/out, CPU parity |
| 15 | PIXEL | "Encoded 179/255 for the display" | the sRGB encode; the gamma-space alternative 115 |

**What changes per kind of blur.**

- **Tier 1 LSI blurs** walk all seven floors with tap- or fetch-level sub-steps. Iterated blurs (Kawase, dual Kawase, iterated box, diffusion) put one sub-step per *pass* or *iteration* rather than per fetch, and show Σ as "value after pass n".
- **Nonlinear blurs** (bilateral, median, guided, Kuwahara, Perona–Malik): the Kernel floor's weights are LIVE and the sub-steps show the per-tap *decision* (range weight 0.135 for a dark neighbour; the median's sorting network compare-exchange count; Kuwahara's four sector variances and the winner). The FREQ pill and Math-floor spectrum are replaced by the amplitude map T(ν, A) and engraved `N/A · NONLINEAR`.
- **Shift-variant blurs** (zoom, spin, tilt-shift, variable, cat's-eye): the Math floor shows the local PSF at the probe and the coordinate change that makes it LSI (log-polar, polar), and the walk has an extra step "Where is the centre?" that shows the probe's distance and angle from it.
- **FFT-based Tier 2 entries** (frequency low-pass, FFT convolution, Lorentzian via FFT, Wiener): the Kernel and GPU floors cannot show a pixel footprint, because every output pixel depends on every input pixel (CAT §6.1 rule 2). Their walk replaces the fetch steps with "multiply this frequency by H(ν)" steps on the probe's row spectrum, and says so in one sentence.
- **Tier 3 entries** walk Floors 1–4 only (plus a CPU-computed Floor 7 on a 128×128 crop); Floors 5–6 show `CPU ONLY IN THIS APP · TIER 3` and why.
- **System implementations (Tier S)** — SwiftUI `.blur`, materials, Liquid Glass: Floors 1, 2 and 7 are real (the call, and the pixels MEASURED through `ImageRenderer` where it can capture them); Floors 3–6 are drawn as an **INFERRED lane** (dashed outline, magenta question-mark badge) holding the measured fit (σ ≈ 0.90·r above 5 device px, box³-like, edge wobble up to 1.2–1.4 px, CAL §5.1), the QuartzCore kernel names, and the WWDC 2014 five-pass diagram (GPU §1.1). Glass cannot be captured offscreen at all (SDK §4), so its Floor 7 says `NOT CAPTURABLE · INFERRED` and points to our MODELED reconstruction.

**Branches, not forks.** At step 3 (and its equivalents) the user can flip a silent parameter (colour space, edge mode, alpha, accumulator precision). The Trace does not restart; it shows the alternative OUT greyed beside the real one (`OUT 0.450 · if sRGB-encoded: 115/255`) and keeps walking the real path. This is how the walk teaches that the API floor's invisible choices can matter more than σ.

**Pace and motion.** Steps advance only on a tap; there is no autoplay by default. An optional `Play` (in the `All … details` menu) auto-advances one sub-step every 250 ms with the primary button in amber (running); Reduce Motion disables Play's easing but keeps manual stepping (Los Alamos precedent, METRO §F.4 item 8). One light haptic per completed *floor*, never per sub-step (Metro feedback density).

**Ending.** The last step's `Completed` line states the one-sentence lesson for this blur (§6.1–§6.4 ends), the primary button becomes `Back to Lab`, and a secondary `Descend another pixel` returns to the Lab with the probe crosshair highlighted for one second.

## 8. What makes each blur unique: the fingerprint card

"What makes each blur unique" is answered three ways, from quick to deep: the **signature sentence** (one line, from the catalog), the **fingerprint card** (six facts, four glyphs, a handful of numbers), and the **divergence floor** (where it parts ways with its nearest neighbour, §9).

### 8.1 Card anatomy (406 × ≈ 368, content panel)

```
 ╭ WHAT MAKES IT UNIQUE ──────────────────────────────── [TRUE BLUR] ╮   eyebrow + verdict chip (NL §0 vocabulary)
 │ Gaussian blur                                      F2 · TIER 1     │   title body semibold; family + tier caption
 │ "The only blur that is round and separable at once; it fades      │   signature: serif italic, instrument cyan
 │  every detail smoothly and never lies about phase."               │
 │ ┌ PSF ──────┐┌ |H| ──────┐┌ EDGE ─────┐┌ COST ─────┐              │   four 88×88 plot insets (surface.plot, r 10)
 │ │   (◎)     ││    ◎      ││   _/‾     ││  ╱ O(r)   │              │   PSF: impulse, log scale; |H|: 2-D, magenta
 │ │  log      ││  no lobes ││  erf      ││ • 0.61 ms │              │   dashed = negative lobes; EDGE: step response
 │ └───────────┘└───────────┘└───────────┘└───────────┘              │   (3 contrasts for NL); COST: fetches/px vs σ
 │ PSF SHAPE   round, soft, no rim; kurtosis 3.0         [= COMP.]   │   six fact rows, 22 pt each, mono label +
 │ RESPONSE    e^(−2π²σ²ν²): no zeros, never negative    [= COMP.]   │   prose value + badge
 │ EDGES       erf S-curve, 10–90% = 2.56σ, no overshoot [= COMP.]   │
 │ COST        O(r) separable; O(1) via IIR or pyramid   [= COMP.]   │
 │ ARTIFACTS   square halo on HDR lights if cut at 2σ    [= COMP.]   │
 │ USED IN     CSS blur(), CIGaussianBlur, MPS, SIFT     [▤ REF.]    │
 │ PARTS WAYS WITH  box at MATH · tent at MATH · IIR at ALGORITHM    │   divergence line (amber floor names)
 │ [ Show on Siemens star ]                      [ Field guide › ]   │
 ╰────────────────────────────────────────────────────────────────────╯
```

The six rows are exactly the brief's fingerprint list (PSF shape, frequency response, edge behaviour, cost class, artifacts, where used). The four glyphs are drawn from `BlurCore` for LSI blurs (COMPUTED), from the live specimen at the probe for nonlinear blurs (LIVE local PSF; the |H| inset becomes the T(ν, A) map), and as a PSF *field* (a 5×5 grid of local PSFs) for shift-variant blurs. The COST inset carries this phone's MEASURED time as a dot on the modelled curve.

### 8.2 The fingerprint numbers (what the Atlas sorts and compares by)

Every entry gets the same small vector, computed by `BlurCore` at a reference size (σ_equiv = 4 px) so that blurs are compared at equal second moment, the convention of CAT §7:

| Number | Meaning | Gaussian | Box | Disc | Hexagon | Bilateral | Zoom |
|---|---|---|---|---|---|---|---|
| LSF kurtosis (axis) | shape of the PSF's marginal; Gaussian 3.0, tent 2.4, disc 2.0, box 1.8 (STACK §3) | 3.0 | 1.8 | 2.0 | between disc and box (computed per blade count) | n/a (local) | n/a (local) |
| Axis vs 45° kurtosis | separable vs isotropic | equal | 1.8 vs 2.4 | equal | six-fold | — | — |
| MTF minimum | deepest contrast inversion | ≥ 0 | −0.217 | −0.132 | six-fold, computed | — | local sinc: −0.217 along the ray |
| First MTF zero | where detail first vanishes | none | ν = 1/w | ρ = 0.610/R | edge-normal 1/L | — | 1/(a·r) along the ray |
| Support at 10⁻⁴ / σ | truncation, tails | 4.29 (untruncated) | √3 ≈ 1.73 | 2.0 | ≈ 2.2 | — | — |
| LSI class | yes / LSV / NL / E | yes | yes | yes | yes | NL | LSV |
| Cost exponent | fetches ∝ r^p | 1 (separable) | 0 (running sum) | 1 (row-span) | 1 | 2 (brute) | 1 (per pixel, ∝ a·r) |

(Box, disc and Gaussian values are COMPUTED in CAT §5.2. The hexagon's kurtosis is left to `BlurCore`: I did not compute it for this document. Its support figure is the circumradius over σ, 16/7.30 = 2.19, COMPUTED here; along the apothem it is 1.90. Zoom's "−0.217" is the continuous sinc minimum along the ray, COMPUTED, SPA §1.8.)

### 8.3 The four worked examples, side by side

| | Gaussian | Radial zoom | Bilateral | Hexagonal bokeh |
|---|---|---|---|---|
| Verdict | TRUE BLUR | LSV BLUR | ADAPTIVE BLUR | TRUE BLUR (per radius) |
| PSF shape | round soft bell, no rim | a ray segment toward the centre, length ∝ distance (30 px at r = 300, a = 0.1) | a Gaussian bump with everything that "looks different" cut away (dark side × 0.135 at the probe) | flat hexagon, straight edges, same orientation everywhere |
| Frequency response | Gaussian, no zeros, never negative | none globally; local sinc along the ray, zero lines every 1/(a·r); a 1-D box in log-polar | none; T(ν, A): 0.178 at A 0.01 → 0.930 at A 0.3 (ν 0.1) | sum of three rhombus sinc² terms; six slow spokes; zeros not circles |
| Edge behaviour | erf S-curve, no overshoot | edges along rays untouched; edges across rays smeared | steps ≫ σr kept, ≪ σr blurred | half-hexagon ramp; hard rims on lights |
| Cost class | O(r), 26 fetches at σ 4 | O(N), 32 fetches (65 needed at the corners) | O(r²), 289 taps | O(R), 64 fetches vs ≈ 665 |
| Artifacts | square halo on HDR if truncated; banding with 8-bit intermediates | corner banding when N < a·r_max + 1 | terraces on ramps; noise kept beside edges; impulses kept | rhombus seams; odd blades impossible; dull in gamma space |
| Where used | CSS, Core Image, MPS, SIFT, Canny | Photoshop Radial Blur (Zoom), `CIZoomBlur`, god rays | HDR tone mapping, skin smoothing, SSAO upsampling | Battlefield 3 / Frostbite 2, Stride, VTK, lens-blur iris shapes |
| Parts ways with its neighbour at | box: MATH | spin: MATH | Gaussian: MATH (meets again as σr → ∞) | disc: MATH, then ALGORITHM |

## 9. Comparison modes

All comparisons hold two `Descent` states, A and B, over **one** specimen and one probe. B defaults to the CAT §7 partner of A (Gaussian → box at equal σ, zoom → spin, bilateral → Gaussian, hexagon → disc).

| Mode | Where | What it shows | Numbers (badge) |
|---|---|---|---|
| **Wipe** | specimen, divider handle | A left, B right, a 44 × 298 touch-owning divider; pills draw A solid, B dashed | Telemetry becomes ΔGPU ms (MEASURED), ΔTAPS (COMPUTED), MAX \|A−B\| in 8-bit steps (LIVE) |
| **Difference** | specimen | \|A − B\| as a heat map (spectrum-primary violet ramp, with a numeric legend), scaled ×1, ×16 or ×256 | MAX and RMS in 8-bit steps; the probe's own difference |
| **Floors** (divergence) | Lab floor cards + rail | The seven floor cards show A and B in two columns; the rail chips show `=` or `≠`; the **first `≠` floor is amber** and its card leads with the reason | per floor: same / differs / differs only in the last bits |
| **Match σ** | toggle in compare | B's primary parameter is set so its per-axis second moment equals A's (box w = √(12σ² + 1), disc R = 2σ, hexagon R = σ/0.456, line L = √12·σ, bilateral σs = σ); the residual is stated when B's parameter is an integer | COMPUTED |
| **Same typed number** | Floor 1 card, reverse mode | One typed value ("10") through every tool: the 16 pixel meanings of "radius" and the resulting σ and 10–90% edge width (STACK §8): σ from 1.0 (ImageMagick `-blur 10`) to 10.0 (CSS `blur(10px)`) | REFERENCE / MEASURED / INFERRED per row, UNVERIFIED for Photoshop |
| **System twin** | Floor 2 card, `Compare with Apple` | Our implementation vs Apple's (`MPSImageGaussianBlur`, `CIGaussianBlur`, `CIDiscBlur`, `CIMedianFilter`, SwiftUI `.blur` through `ImageRenderer`) at the fitted parameter | the twin's fitted σ, kurtosis and centre wobble: MEASURED on this device |
| **CPU reference** | Floor 7 card | GPU vs `BlurCore` on a crop around the probe | max and RMS in 8-bit steps: MEASURED (parity) |
| **Lessons** | Lessons sheet | One of the 30 pairs of CAT §7, set up with the right specimen, parameters and probe, and its "look for" number in the status row | the lesson's number with its original badge |

**Divergence floors for common pairs** (the content of the Atlas Divergence tab; each row is COMPUTED from the catalog's structure, not measured):

| A vs B | First floor where they differ | Why, in one line |
|---|---|---|
| `gaussian-2d-direct` vs `gaussian-separable` | ALGORITHM | Same kernel; 625 vs 50 taps at σ 4; pixels equal to ≤ 1 LSB (CAT P4) |
| `gaussian-separable` vs `gaussian-linear-sampling` | GPU | Same passes; 25 integer vs 13 bilinear fetches per pass; pixels differ only by the 8-bit sub-texel weights (GPU §2.3) |
| `gaussian-blur` vs `heat-equation` | ALGORITHM | Same operator (σ = √(2t)); 2 passes vs σ²/(2λ) = 32 explicit iterations at σ 4, λ 0.25 (COMPUTED here) |
| `gaussian-blur` vs `iir-gaussian` | KERNEL | IIR's impulse response has exponential tails; Young–van Vliet moment σ 5.56 at nominal 5 (CAT §5.2) |
| `box-blur` vs `gaussian-blur` (equal σ) | MATH | rect vs bell; MTF −0.217 vs ≥ 0 (CAT P1) |
| `iterated-box` (n = 3) vs `gaussian-blur` | MATH | piecewise quadratic vs bell; −1% inversion left (CAT P3) |
| CSS `blur(10px)` vs SwiftUI `.blur(radius: 10)` | API → ALGORITHM | Both σ = 10 by name (and both gamma-space); SwiftUI's large-radius kernel is box³-like at σ ≈ 0.90·r (MEASURED macOS; INFERRED mechanism) |
| Figma Layer blur 10 vs CSS `blur(10px)` | SLIDE → API | Same word, σ 5 vs 10 (INFERRED Figma rule, STACK §4.1) |
| Same blur, linear vs sRGB-encoded | API | A silent parameter; 0.735 vs 0.500 on stripes, 179 vs 115 at the Gaussian probe |
| `radial-zoom-blur` vs `spin-blur` | MATH | scaling vs rotation about c; exact duals (CAT P21) |
| `disc-blur` vs `polygonal-bokeh` | MATH | aperture shape; then ALGORITHM (2-D gather vs four line passes) |
| `bilateral` vs `gaussian-blur` | MATH | range term; converge as σr → ∞ |
| `bilateral` vs `guided` | MATH | weighted average vs local linear regression; no gradient reversal for guided (CAT P15) |
| `median` vs `bilateral` | MATH | rank vs weighted average; impulses deleted vs kept (CAT P14) |

## 10. Controls per family

### 10.1 The control grammar (one rule set for all 55 entries)

Descent uses **four control types and nothing else**. There is no `Slider` anywhere in the app: ClassicalML used sliders for continuous values (METRO §F.2 item 9), but a slider is a second continuous control competing with the crowns, it has no detent vocabulary, and its thumb is a gesture-only target. The crowns plus the `DecimalParameterStepper` already give a continuous value a gesture, a native ± alternative and an accessible adjustable action (Metro §8, §10, §17).

| Control | Metro component | Size (pt) | Used for | Where |
|---|---|---|---|---|
| **Crown pair** | `InstrumentCrown` ×2 (ported, METRO §C.4), each between 44×44 glass ± buttons | crown 62×62; row 348 wide, 98 tall incl. captions | the blur's **primary continuous parameter**: FINE (cyan, 8° detent = one fine step) and SEMANTIC (amber, 20° detent = one named stop) | Lab first viewport only, y 644–742 |
| **Decimal stepper** | `DecimalParameterStepper` (new, stores `Int` tenths or hundredths, METRO §C.3) | min 48 tall, max 380 wide, padding 14 | secondary continuous parameters; the primary parameter's native twin | parameters panel (below the fold) |
| **Integer stepper** | `InstrumentParameterStepper` (starter, AssemblerToy hardened copy) | min 48 tall, max 380 wide | every integer: radius in whole px, passes, levels, blades, taps, iterations, N | first viewport when the primary is an integer; otherwise the parameters panel |
| **Picker** | native `Picker(.segmented)` for 2–4 options; native `Menu` for 5+ | 32 tall (segmented), 44 tall (menu row) | variant / algorithm, colour space, edge mode, precision, shapes, tool conventions | first viewport (algorithm picker, integer-primary blurs only) and parameters panel |

Plus two **on-specimen handles** for position parameters, both touch-owning 44×44 targets (METRO §A.16), both with numeric twins in the parameters panel: the **centre** (cyan ring with a dot) for zoom, spin, god rays, cat's-eye swirl; the **focus line** (cyan line with two 44×44 end knobs) for tilt-shift and iris blur. A **third** handle is the compare divider (§9). The probe is not a control: it is placed by `SpatialTapGesture` and moved by the specimen's adjustable action (§5).

**Crown detent policy.** Every continuous quantity declares, in `BlurCore`, exactly one fine step, one display precision and one list of semantic stops. Display precision equals spoken precision equals the fine step (Metro §4, contract A.6). The table below is the full list; a new blur reuses one of these rows or adds one.

| Quantity | Unit | Fine step (8°) | Display | Semantic stops (20°) and meaning-band names | Range |
|---|---|---|---|---|---|
| σ, disc radius R, polygon circumradius R, decay b, line length L | px (specimen pixels) | 0.1 px | 1 dp | 0.5 · 1 · 2 · 4 · 8 · 16 · 32 · 64 px; bands *Sub-pixel* < 0.5 · *Anti-alias* 0.5–1.5 · *Softened* 1.5–4 · *Frosted* 4–12 · *Backdrop* 12–32 · *Fog* > 32 (Blur2ool's own descriptive names, METRO §G.1 item 7) | 0.3–64.0 (σ); 0.5–64.0 (R, b); 1.0–128.0 (L) |
| SwiftUI radius | pt | 0.1 pt | 1 dp | 0.5 · **1.7** · 3 · 5 · 10 · 20 pt. The 1.7-pt stop is the MEASURED regime switch (5 device px at scale 3, CAL §6 item 2: "about 1.8 pt"; 5/3 = 1.67 pt, rounded to the 0.1-pt grid); its band name is *Regime switch* and the amber detent there is the only one in the app that is not an octave | 0.0–20.0 |
| Angle (motion direction, polygon rotation) | ° | 1° | integer | 0 · 45 · 90 · 135 (ANGLE crown, METRO §C.4) | 0–179 (direction is a line); 0–59 for a hexagon's rotation (its symmetry period) |
| Spin angle Θ | ° | 0.5° | 1 dp | 2.5 · 5 · **360/n_c** · 20 · 45 · 90°. With the 36-cycle star the 360/n_c stop is 10°, where the star turns uniformly grey (CAT P21, E7); the stop moves if the specimen changes | 0.0–360.0 |
| Zoom strength a | % of distance | 0.5 % | 1 dp | 2.5 · 5 · 10 · 20 · 40 % | 0.0–50.0 |
| Range σr (bilateral family) | fraction of full scale (linear light) | 0.01 | 2 dp | 0.01 · 0.02 · 0.05 · 0.10 · 0.20 · 0.50 · 1.00; bands *Edge-locked* < 0.05 · *Edge-aware* 0.05–0.3 · *Nearly Gaussian* > 0.3 | 0.01–1.00 |
| Cut-off D₀ (frequency low-pass) | c/px | 0.005 c/px | 3 dp | 0.010 · 0.025 · 0.050 · 0.100 · 0.250 · 0.500 | 0.005–0.500 |

The SEMANTIC crown fires one stronger haptic per stop (Metro §15: up 1.00/0.60, down 1.00/0.05); the FINE crown fires the fine vocabulary (0.78/0.95 up, 0.82/0.20 down) and never more than 20 events/s (METRO §B.7). Turning past the range end emits nothing and changes nothing (contract A.17). For integer primaries, the native Stepper's held repeat is the only acceleration; Descent adds no custom acceleration curve.

**What the first viewport holds, by primary type** (this is the only per-blur variation of the W1 layout):

| Primary type | y 644–742 (98 pt) | y 754–806 | Examples |
|---|---|---|---|
| continuous | crown pair | descent rail | Gaussian σ, disc R, zoom a, bilateral σr |
| integer | integer Stepper (644–692) + algorithm picker (704–736) | rail at 748–800 | box r, Kawase passes, median window, frosted-glass a |
| named | segmented picker (644–676) + one integer Stepper (686–734) | rail at 748–800 | median `3×3 · 5×5`, morphology op |
| none | engraved `NO PARAMETER · THE LIMIT OF EVERY BLUR` in the band; crown row empty but reserved | rail at 754–806 | `average-blur` |

The reserved 98 pt never collapses, so the rail and the floating group do not move when the user changes blur (AssemblerToy's "changing content moved panels", METRO §F.1 item 2).

**Global parameters (every blur).** These are the API floor's "silent parameters". They live in the parameters panel of every blur and in the Settings sheet as defaults, and the Trace's step 3 (and its equivalents) offers each as a branch (§7).

| Parameter | Control | Options | Default | Why it is global |
|---|---|---|---|---|
| Colour space | segmented | `Linear` · `sRGB-encoded` | Linear | 0.735 vs 0.500 on stripes; 179 vs 115 at the Gaussian probe (§6.1); the hexagon nearly vanishes in encoded space (§6.4) |
| Edge mode | segmented | `Clamp` · `Mirror` · `Wrap` · `Zero` (+ `Renormalise` in a `Menu` overflow for FIR blurs) | Clamp | CSS mirrors, SwiftUI `.blur(opaque: false)` is transparent (decal), CI is transparent unless clamped (STACK §3, CAL §5.2) |
| Alpha | segmented | `Premultiplied` · `Straight` | Premultiplied | P19 dark fringes |
| Accumulator / intermediate | segmented | `fp32` · `fp16` | fp32 accumulators, fp16 intermediates (`rgba16Float`) | GPU §3.8 error budget; parity |
| Preview resolution | segmented | `Full` · `Half while moving` | Half while moving for O(r²) and iterative blurs, Full otherwise | bilateral brute force is 2.3·10⁸ weight evaluations per frame (§6.3) |

### 10.2 Per-family control map

Ranges are **design choices** for an 894-px specimen, not facts from the sources, unless a source is cited; where a source bounds a range (CI's guided radius max 10, the Tier 1 brute-force bilateral r ≤ 8, Kawase passes 1–8, blades 5–9 from METRO §C.3) the citation is given. Units: px = specimen pixels; % = percent of distance from a centre; levels = 8-bit code values where a tool uses them.

**F1 · Box, tent & running sums**

| Blur | Primary (hero, control) | Range · step | Secondary controls | Algorithm / variant picker |
|---|---|---|---|---|
| `box-blur` | `RADIUS · PX` integer r, Stepper; the status row shows `w 13 · σ 3.74 px` | 1–48 · 1 | `MATCH σ` toggle (sets r from a typed σ and states the residual, §9) | `Separable · Sliding sum · SAT` |
| `tent-blur` | `RADIUS · PX` integer r, Stepper; status `σ = √(r(r+2)/6)` | 1–48 · 1 | — | `FIR · Stack blur` |
| `iterated-box` | `SIGMA · PX` target σ, crowns; status shows the **achieved** σ (integer widths quantise it, LSI §7) | 0.5–64.0 · 0.1 | `PASSES` Stepper 1–6 (METRO §C.3) | `Equal · Kovesi split · SVG three-box · Extended (fractional)` (Menu, 4 options in the panel; segmented would be too narrow at 380 pt with these labels) |
| `average-blur` | none (engraved), hero shows the image mean, LIVE | — | colour space only (the mean of the star is 0.500 linear, 0.735 encoded: the P18 lesson as a single number) | — |

**F2 · Gaussian & approximations**

| Blur | Primary | Range · step | Secondary | Variant picker |
|---|---|---|---|---|
| `gaussian-blur` | `SIGMA · PX`, crowns | 0.3–64.0 · 0.1 | `TRUNCATION k` segmented `2 · 2.5 · 3 · 4` (default 3); `DISCRETISATION` segmented `Sampled · Integrated · Lindeberg` (Lindeberg and Integrated draw Tier 3 plots at σ < 1 and fall back to Sampled on the GPU, saying so) | `2-D · Separable · Linear-sampled · IIR` (2-D is disabled above σ 8 with the reason "2-D direct: 2,401 taps per pixel at σ 8; use separable", COMPUTED (2·24+1)² = 2,401) |
| `binomial-blur` | `ORDER n`, Stepper; status `n+1 TAPS · σ = √n/2` | 1–32 · 1 | — | `Separable merged taps` (single variant; the picker is hidden, not disabled) |
| `iir-gaussian` | `SIGMA · PX`, crowns | 0.5–64.0 · 0.1 (YvV's q formula is defined from σ 0.5, LSI §10) | `FORM` segmented `YvV cascade (3rd order) · Deriche K 2 · K 3 · K 4`; `BORDER INIT` segmented `Zero · Steady state` (P10's boundary transient) | — |

**F3 · Pyramids & Kawase**

| Blur | Primary | Range · step | Secondary | Variant picker |
|---|---|---|---|---|
| `kawase-blur` | `PASSES`, Stepper; status `σ 5.34 px · 20 FETCHES` for {0,1,2,2,3} | 1–8 · 1 (METRO §C.3) | `SEQUENCE` Menu: `0 1 2 2 3` (Intel 2014) · `0 1 2 3 4…` · `2 3 3 3` (streak-like, Intel) · `custom` (one Stepper per pass, 0–15) | — |
| `dual-kawase` | `LEVELS`, Stepper; status `σ ≈ 1.5·2^L px` at o 2 | 1–6 · 1 | `OFFSET o` DecimalStepper 0.5–4.0 · 0.5, with the shift-variance readout (8.5 / 4.3 / 3.7 % at o 2, L 2–4; 26–55 % at o 3, LSI §13) | — |
| `pyramid-blur` | `LEVELS`, Stepper | 1–6 · 1 | `LOD BIAS` DecimalStepper 0.0–6.0 · 0.1 (mip-chain only: fractional bias = the mip mixture of P23) | `Mip chain · CoD 13-tap · Unity 13-tap` (CAT §5 E2: two different kernels) |

**F4 · Kernel shapes & the frequency domain**

| Blur | Primary | Range · step | Secondary | Variant picker |
|---|---|---|---|---|
| `exponential-blur` | `DECAY b · PX`, crowns | 0.5–64.0 · 0.1 | — | `Separable (diamond) · Isotropic` |
| `lorentzian-blur` | `HALF-WIDTH γ · PX`, crowns; the meaning line is the 50 %-energy radius, not a σ (a Lorentzian has no variance, LSI §16) | 0.5–32.0 · 0.1 | `TERMS` Stepper 2–6 (sum-of-Gaussians) | `Sum of Gaussians · FFT` |
| `frequency-lowpass` | `CUT-OFF D₀ · C/PX`, crowns | 0.005–0.500 · 0.005 | `ORDER n` Stepper 1–20 (Butterworth only) | `Ideal · Butterworth · Gaussian` |
| `fft-convolution` | `SIZE · PX` (the kernel's R or σ), crowns | 0.5–64.0 · 0.1 | `KERNEL` Menu: any LSI entry's kernel (box, disc, hexagon, Airy, Lorentzian…); `PADDING` segmented `Wrap · Zero · Mirror` (the wrap-around lesson) | — |

**F5 · Directional & motion**

| Blur | Primary | Range · step | Secondary | Variant picker |
|---|---|---|---|---|
| `linear-motion-blur` | `LENGTH · PX`, crowns | 1.0–128.0 · 0.1 | `ANGLE` integer Stepper 0–179° (the ANGLE crown replaces the FINE crown when the user taps the angle readout; only one crown pair is ever on screen); `SHUTTER` segmented `Box · Trapezoid · Coded`; `ANCHOR` segmented `Centred · Trailing` | `Gather · Doubling` |
| `anisotropic-gaussian` | `SIGMA ALONG · PX`, crowns | 0.3–64.0 · 0.1 | `SIGMA ACROSS · PX` DecimalStepper 0.0–64.0 · 0.1 (0 = Core Image's line, CAT §5 E5); `ANGLE` Stepper 0–179° | `Sheared separable` (single) |
| `kawase-streak` | `LENGTH · PX`, crowns (rounded to the base-4 schedule; status shows the exact length used) | 4–256 | `ARMS` Stepper 2–8; `THRESHOLD` DecimalStepper 1.0–10.0 · 0.1 (× white, linear HDR); `ROTATION` Stepper 0–89° | — |
| `camera-shake-blur` | `AMPLITUDE · PX`, crowns | 1.0–64.0 · 0.1 | `TRAJECTORY` Menu (random walk, tremor, pause-and-jerk); `SEED` Stepper 1–99 | — |
| `velocity-buffer-motion-blur` | `SHUTTER · °`, Stepper | 0–360 · 15 | `TAPS S` Stepper odd 5–31 (paper default 15, SPA §1.6); `TILE k` Stepper 10–40 px · 5 | — |
| `temporal-accumulation` | `SUB-FRAMES N`, Stepper | 1–64 · 1 | `MODE` segmented `Box average · EMA`; `α` DecimalStepper 0.01–1.00 · 0.01 (EMA only) | — |
| `radial-zoom-blur` | `STRENGTH · %`, crowns | 0.0–50.0 · 0.5 | **centre handle** + `CENTRE X/Y · PX` DecimalSteppers; `SAMPLES N` Stepper 4–128 with an `Adaptive` toggle (N(x) = ⌈a·r⌉ + 1); `DIRECTION` segmented `Centred · Outward · Inward` (Outward matches `CIZoomBlur`, CAL §5.2) | `Gather · Adaptive gather · Doubling` |
| `spin-blur` | `ANGLE Θ · °`, crowns | 0.0–360.0 · 0.5 | centre handle + X/Y steppers; `SAMPLES` adaptive (default) or fixed Stepper 4–256 | `Arc gather · Doubling` |
| `path-blur` | `SPEED · %`, crowns | 0–500 % (Photoshop's range, SPA §1.10) | `PATH` Menu of preset paths (S-curve, circle, spiral, straight) instead of drawing (drawing is a gesture with no good accessible twin; out of v1, §14); `ANCHOR` `Centred · Trailing` | — |

**F6 · Lens & bokeh**

| Blur | Primary | Range · step | Secondary | Variant picker |
|---|---|---|---|---|
| `disc-blur` | `RADIUS R · PX`, crowns | 0.5–64.0 · 0.1 | `SAMPLES S` Stepper 16–400 (stochastic only); `COMPONENTS` segmented `1 · 2` (complex separable only) | `Gather · Row-span SAT · Complex separable · Stochastic` |
| `polygonal-bokeh` | `RADIUS R · PX` (circumradius), crowns | 0.5–64.0 · 0.1 | `BLADES` Stepper 4–9 (4, 6, 8 use line passes; 5, 7, 9 switch to a masked 2-D gather and say why, §6.4); `ROTATION · °` Stepper 0–59 (hexagon), 0–(360/n − 1) in general; `CURVATURE` DecimalStepper 0.00–1.00 · 0.05 (curvature > 0 is not a zonogon either, so it also forces the gather; this is my inference from the zonogon rule, which needs straight parallel sides) | `Line passes · 2-D gather` |
| `cats-eye-swirl-bokeh` | `RADIUS R · PX`, crowns | 0.5–32.0 · 0.1 | `BARREL CLIP k` DecimalStepper 0.00–1.00 · 0.05; `SWIRL s` DecimalStepper 0.00–1.00 · 0.05; centre handle | — |
| `diffraction-airy` | `F-NUMBER`, Menu `1.78 · 2.8 · 4 · 5.6 · 8 · 11 · 16` (named primary; 1.78 is CAT §5.2's phone example) | named | `WAVELENGTH` segmented `450 · 550 · 650 nm`; `PIXEL PITCH · µm` DecimalStepper (default UNVERIFIED for his phone's sensors; the card says so) | — |
| `anamorphic-bokeh` | `RADIUS R · PX`, crowns | 0.5–64.0 · 0.1 | `SQUEEZE` segmented `1.33 · 1.5 · 2.0` (SPA §2.8); `STREAK LENGTH · PX` DecimalStepper; `THRESHOLD` DecimalStepper | — |

**F7 · Spatially varying & stochastic**

| Blur | Primary | Range · step | Secondary | Variant picker |
|---|---|---|---|---|
| `depth-of-field-coc` | `F-NUMBER`, Menu (named) | as Airy | `FOCUS DISTANCE · m` DecimalStepper 0.10–10.00 · 0.05 (scene units of the procedural depth scene, stated); `FOCAL LENGTH · mm` Menu `24 · 50 · 85` | `Half-res gather · Full-res gather` |
| `tilt-shift` | `MAX BLUR σ · PX`, crowns | 0.5–32.0 · 0.1 | **focus-line handle**; `BAND WIDTH · PX` and `TRANSITION · PX` DecimalSteppers; `ANGLE` Stepper 0–179° | `Linear band · Iris (ellipse)` |
| `variable-progressive-blur` | `MAX SIGMA · PX`, crowns | 0.5–64.0 · 0.1 | `MASK` Menu `Ramp · Radial · Top edge (scroll-edge) · Bottom edge` | `Per-pixel Gaussian · Mip mix · Variance-matched mip mix · Stacked layers · CIMaskedVariableBlur (system twin)` (Menu: 5 options) |
| `frosted-glass-noise` | `AMOUNT a · PX` integer, Stepper; status `expected σ = √(a(a+1)/3)` | 1–16 · 1 | `REALIZATIONS N` Stepper 1–256 (the convergence lesson P24); `NOISE` segmented `White · Smooth`; `Reseed` glass button 44×44 | — |

**F8 · Edge-preserving & nonlinear**

| Blur | Primary | Range · step | Secondary | Variant picker |
|---|---|---|---|---|
| `median` | `WINDOW`, segmented `3×3 · 5×5` (named) | — | `NOISE DENSITY · %` Stepper 0–30 · 1 (salt-and-pepper specimen only) | `Sorting network · Histogram (8-bit)` (histogram enables 7×7–31×31 as a Tier 2 extension) |
| `bilateral` | `RANGE σr`, crowns (the parameter that makes it unique, so it gets the hero) | 0.01–1.00 · 0.01 | `SPACE σs · PX` DecimalStepper 0.5–3.2 · 0.1 for brute force (window r = ⌈2.5·σs⌉ ≤ 8, the Tier 1 limit, CAT §6.2; NL A2 gives r ≈ 2–3σs), up to 32.0 for the approximate variants; `DISTANCE` segmented `Luma · RGB` | `Brute force · Separable · Grid` |
| `joint-bilateral` | `RANGE σr`, crowns | 0.01–1.00 · 0.01 | σs as above; `GUIDE` Menu `Colour stripes · Luma of specimen · Depth` | — |
| `guided` | `RADIUS r · PX` integer, Stepper | 1–10 · 1 (`CIGuidedFilter` max 10, NL A6) | `√ε` DecimalStepper 0.01–0.40 · 0.01 (He et al.'s 0.1, 0.2, 0.4 are stops); `DETAIL BOOST k` Stepper 1–5 (P15) | `Box filters · Fast (subsampled)` |
| `domain-transform` | `SPACE σs · PX`, crowns | 1.0–64.0 · 0.1 | `σr` DecimalStepper; `ITERATIONS` Stepper 1–4 | `Recursive · Normalised convolution` |
| `kuwahara` | `RADIUS r · PX` integer, Stepper | 1–8 · 1 | `SHARPNESS q` Stepper 1–16 (generalized/anisotropic only) | `Classic · Generalized · Anisotropic` |
| `surface-blur` | `RADIUS · PX` integer, Stepper | 1–16 · 1 | `THRESHOLD · LEVELS` Stepper 0–255 (Photoshop's unit; status shows the tent model's σr = cT/√6, NL A10, and the mapping's INFERRED badge) | `Surface Blur (hard) · Smart Blur · Sigma filter` |
| `nonlocal-means` | `STRENGTH h`, crowns (fraction of full scale) | 0.01–0.50 · 0.01 | `PATCH` segmented `3 · 5 · 7`; `SEARCH` segmented `7 · 11 · 21` | — |
| `mean-shift`, `tv-denoise` (Tier 3) | `h_r` / `λ`, DecimalStepper (no crowns: Tier 3 has no live GPU image to turn them against) | per NL A14 / CAT §3.2 | `ITERATIONS` Stepper | — |

**F9 · Diffusion**

| Blur | Primary | Range · step | Secondary | Variant picker |
|---|---|---|---|---|
| `heat-equation` | `TIME t`, DecimalStepper as primary with `σ = √(2t)` as the meaning line (CAT §5 E9 convention) | 0.0–200.0 · 0.5 | `λ` segmented `0.25 · 0.20 · 0.10` (explicit stability needs λ ≤ 1/4) | `Explicit iterations · Exact Gaussian` |
| `perona-malik` | `ITERATIONS n`, Stepper | 1–200 · 1 | `K` DecimalStepper 0.01–0.50 · 0.01 (gradient units: intensity per px, NL A12); `c(·)` segmented `Exponential · Rational`; `λ` as heat | — |
| `coherence-enhancing-diffusion` (Tier 3) | `ITERATIONS`, Stepper | 1–200 | `σ` and `ρ` (tensor scales) DecimalSteppers | — |

**F10 · UI materials** (system entries measure the real API; the crowns drive the API's own parameter in its own unit)

| Blur | Primary | Range · step | Secondary | Notes |
|---|---|---|---|---|
| `swiftui-layer-blur` | `RADIUS · PT`, crowns (the SwiftUI unit, with the 1.7-pt regime stop) | 0.0–20.0 · 0.1 | `OPAQUE` segmented `false · true`; `RENDERER` segmented `ImageRenderer default · .extendedLinear`; `Measure on this phone` button | Every value derived from it is MEASURED via `measurePSF` (CAL §7) or INFERRED |
| `apple-uiblureffect` | `MATERIAL`, Menu `ultraThin · thin · regular · thick · ultraThick` (named) | — | `BACKDROP` Menu (stripes + text, white/black split) | Native side INFERRED; our model MODELED |
| `liquid-glass` | `VARIANT`, segmented `Regular · Clear` (named) | — | `SHAPE SIZE · PT` Stepper 44–200 · 4; `TINT` segmented `None · Cyan`; A/B `Native · Model` | The only place glass sits over a specimen (METRO §C.2) |
| `css-backdrop-filter` | `BLUR · PX` (CSS px = σ), crowns | 0.0–64.0 · 0.1 | `CHAIN` Menu (`saturate()`, `brightness()` order) | MODELED from the spec (REFERENCE) |
| `windows-acrylic`, `windows-mica`, `android-renderEffect` (Tier 3) | their typed value, DecimalStepper | per NL B6–B8 | — | plots only; cannot run on iOS |

**F11 · Uses of blur**

| Blur | Primary | Range · step | Secondary |
|---|---|---|---|
| `drop-shadow` | `TYPED VALUE`, crowns (the number a designer types) | 0.0–64.0 · 0.1 | `CONVENTION` Menu `CSS box-shadow · CSS drop-shadow() · CALayer.shadowRadius · CGContext.setShadow · SwiftUI .shadow · Figma · Sketch`; the status row converts to σ with each convention's badge (P27); `OFFSET X/Y · PX` integer Steppers |
| `bloom` | `THRESHOLD`, crowns (× white, linear HDR) | 0.5–10.0 · 0.1 | `LEVELS` Stepper 1–8; `INTENSITY` DecimalStepper 0.00–1.00 · 0.01 (LearnOpenGL's ≈ 0.04 as a stop) |
| `god-rays` | `DECAY`, crowns | 0.900–1.000 · 0.001 | `SAMPLES` Stepper 16–128; `DENSITY` and `WEIGHT` DecimalSteppers (GPU Gems 3 ch. 13 names, CAT §3.5); centre handle |

**Contrast group (not blurs)**

| Entry | Primary | Secondary |
|---|---|---|
| `unsharp-mask` | `AMOUNT k`, crowns 0.00–5.00 · 0.01 | `RADIUS σ · PX` DecimalStepper; `THRESHOLD · LEVELS` Stepper 0–255 |
| `difference-of-gaussians` | `SIGMA · PX`, crowns | `RATIO k` segmented `1.6 · √2 · 2 · 5` (CAT §5.2's four ratios) |
| `morphology` | `OPERATION`, segmented `Dilate · Erode · Open · Close` (named) | `RADIUS · PX` Stepper 1–16; `SHAPE` segmented `Square · Disc · Line` |
| `pixelate` | `CELL · PX` integer, Stepper 2–64 | `GRID PHASE X/Y` Steppers (CI's `inputCenter`) |
| `lanczos` (Tier 3) | `LOBES a`, segmented `2 · 3` | `SCALE` DecimalStepper 0.25–4.00 |
| `wiener-deconvolution` | `NOISE-TO-SIGNAL`, crowns 0.0001–1.0 on a log detent grid (one semantic stop per decade) | `BLURRED BY` Menu `Box · Disc · Gaussian`; `ADD NOISE` toggle |

**Controls that are never offered.** Anything that would put a second crown pair on screen; any control over the GPU floor's numbers (threadgroup size, sampler filter) except through the variant picker, because the GPU floor must show the code that really ran, not a configurable diagram (§6.0); and any parameter whose meaning the sources could not establish (Photoshop's Radial Blur "Quality", Photoshop's Gaussian "Radius"): those appear as UNVERIFIED rows on the WYSIWYG floor, never as knobs.

## 11. Honesty labels in use

### 11.1 The six badges and one qualifier

The badge is the `HonestyBadge` capsule of METRO §C.12: caption2 mono, tracking 1.2, fill white 0.06, 0.6-pt border white 0.12 (0.25 under Increased Contrast). **The word is primary**; glyph and ink are redundant cues.

| Badge | Glyph | Ink | Means, in Descent | Typical home |
|---|---|---|---|---|
| **LIVE** | `circle.fill` (5-pt dot) | action cyan | read back from the GPU texture for the current image and parameters, this frame | Pixels floor (IN/OUT at the probe), Trace `Σ` and `OUT`, nonlinear local PSFs, compare `MAX |A−B|` |
| **MEASURED** | `stopwatch` | instrument amber | timed or fitted on a named device, with OS build and date: GPU ms, fitted σ of an Apple API, parity, sub-texel bits | telemetry `GPU`, API floor's Apple twins, This phone |
| **COMPUTED** | `equal` | display ink | an exact consequence of the math, computed by `BlurCore` (double precision) | Math, Kernel and Algorithm floors; σ EFF; TAPS |
| **MODELED** | `approximately` (≈) | spectrum violet | an estimate from a stated model: bytes, bandwidth floors, scaled timings, our reconstructions of Apple materials | GPU floor bytes and floors; material and glass models |
| **REFERENCE** | `book.closed` | secondary ink | a spec, header, paper or vendor source, cited by name in the row's disclosure | WYSIWYG floor conventions; Feature Set Tables; field guide |
| **INFERRED** | `questionmark`, **dashed** border | spectrum-depth magenta | about internals nobody outside the vendor can see; measured live where possible, never presented as fact | SwiftUI `.blur` mechanism, render server lane, Figma's σ rule, Liquid Glass |

**UNVERIFIED is a qualifier, not a seventh badge.** It means "no team member could confirm this". It appears in two forms only: (a) as the *value itself*, in place of a number (`Photoshop Gaussian Radius  —  UNVERIFIED`), so the app never shows a guessed number; (b) as a trailing caption after a badge when a number exists but its source is weak (`51.2 GB/s · MODELED · UNVERIFIED peak`). It is set in secondary ink with no capsule, so it can never be mistaken for a provenance.

**Inputs carry no badge.** The hero value, Stepper values and crown captions are what the user *set*; they are not claims about the world. Everything derived from them is badged. This is my reading of BRIEF's "every number on screen is one of the following": a number the user typed is the question, not an answer. If he wants inputs badged too, the natural label is a seventh word (`SET`), which I would rather not add.

### 11.2 Placement rules

1. **One badge per number, at the number.** Rows carry the badge at their trailing edge; telemetry carries it under the label (W2); floor cards carry the floor's *dominant* badges in the eyebrow and per-row badges where rows differ.
2. **The one compact exception: rail chips.** At 54 × 52 pt a word badge does not fit. Each chip shows its badge **glyph only** (9 pt, top-trailing corner); the glyph shapes are distinct without colour (dot, stopwatch, =, ≈, book, ? with dashed ring). VoiceOver speaks the word ("Floor 6, GPU, 13 fetches per pass, computed"). This is the only glyph-only use in the app and it is stated in the legend.
3. **Engraved provenance on instruments** (Los Alamos precedent, METRO §F.4 item 3), in the housing's top margin, right side: `LIVE · METAL` (our GPU output), `SYSTEM · MEASURED` (an Apple API rendered offscreen and read back), `MODELED · RECONSTRUCTION` (our model of a material), `INFERRED · NATIVE GLASS` (the Liquid Glass exhibit), `CPU · 128² CROP · COMPUTED` (Tier 3), `PASS 1 OF 2 · INTERMEDIATE` (a pass tile is selected).
4. **Pills**: `COMPUTED` (LSI), `LIVE · LOCAL AT PROBE` (nonlinear), `N/A · NONLINEAR` and `NO SINGLE MTF · SHIFT-VARIANT` (engraved empty states, never blank), `INFERRED — NOT EXPOSED` (system).
5. **Device and date travel with MEASURED.** Every MEASURED value names where: `MEASURED · A17 Pro · iOS 27.x · 14 Oct` or `MEASURED · macOS 27.2 (M1 Max)`. A Mac value is shown on the phone only with its Mac label, until This phone replaces it (CAL §6 item 3).
6. **Upgrades are visible.** When This phone measures something that was REFERENCE or MODELED, the row keeps both values for one session (`32,768 B MEASURED · 32 KB REFERENCE`), so the user sees the claim being checked.
7. **Disagreement is shown, not resolved silently.** When two sources disagree, both rows appear with their badges and a `SOURCES DISAGREE` caption: `CIZoomBlur` length at amount 4 (0.079 MEASURED, CAL §5.2 vs 0.085 from the fitted 1.5^(a/20) law, STACK §3.4), and `CIZoomBlur` weights (near-uniform vs log-uniform).
8. **Simulator honesty.** In the Simulator the GPU column reads `— NO GPU TIMING IN SIMULATOR` (GPU §2.7), and every A17 Pro row reads `NOT THIS DEVICE`.
9. **Badges never animate**, and a badge never changes without its value changing.

### 11.3 The labels in the four worked examples (audit)

| Example | LIVE | MEASURED | COMPUTED | MODELED | REFERENCE | INFERRED | UNVERIFIED |
|---|---|---|---|---|---|---|---|
| Gaussian (§6.1) | OUT at the probe on device; parity | SwiftUI σ ≈ r below 5 px (Mac; iOS pending); CI and MPS σ; 8 sub-texel bits (M1 Max); GPU ms | weights, discrete σ 3.963, 26 fetches, 0.4500, 179/255 | 25.6 MB traffic; 0.5 ms bandwidth floor | CSS σ = value; Android 0.57735r + 0.5; OpenCV ksize rule; `.shaderWrite` compression rule | Figma σ = value/2; render-server kernel names | Photoshop Radius; the 51.2 GB/s peak |
| Radial zoom (§6.2) | zone-plate OUT on device | CIZoomBlur length (CAL) and its law fit (STACK); 1.08 ms at 32 samples on M1 Max | 30-px local PSF, 32 taps at 0.968 px, N ≥ 65, 1.000 → 1.000 and 0.082 → 0.508 | 0.24 / 1.2 ms scaled timings | Photoshop control names | — | Photoshop Amount → strength; which CI law is exact |
| Bilateral (§6.3) | noisy-step values; local weight map at the probe | GPU ms | 0.135, 9.4 % vs 43.3 %, T(ν, A) values, 0.581 vs 0.513, 8,192 B | — | OpenCV parameter names; AE description | `CIEdgePreserveUpsampleFilter` is a joint bilateral; Photoshop Surface Blur algorithm | Threshold → σr |
| Hexagonal bokeh (§6.4) | seam test | 2.96 ms gather on M1 Max; `CIBokehBlur` = `CIDiscBlur` at default ring and softness (CAL §5.2) | area 665.1, σ 7.30, 768 samples, 64 fetches, 0.1504 → 108/255, 0.55 % in encoded space | 38.4 MB traffic; scaled gather timing | Unity, AE, Stride controls | Photoshop Lens Blur implementation | the published 0.5/0.5 normalisation |

### 11.4 Where the labels are explained

The Field guide & Settings sheet has a `HONESTY LABELS` page: one row per badge with its glyph, ink, meaning, an example from the current blur, and the rule for UNVERIFIED and for inputs. A long-press on any badge opens that page scrolled to the badge (a `contextMenu` preview, with a button alternative in the row's accessibility actions). The same sheet carries "The lens on this instrument" (METRO §C.2): the kernel well's glass is Apple Liquid Glass at 48 % opacity whose internals are INFERRED, and the floating buttons are Liquid Glass that Blur2ool neither measures nor simulates except in the `liquid-glass` exhibit.

## 12. Test-image set

**Rules.** Every built-in specimen is **procedural**: `BlurCore` generates it from a formula and a fixed seed, so the same specimen is bit-identical on the Mac (parity CLI), in the Simulator and on the phone, and the worked numbers in §6 can be unit-tested (BRIEF "Built-in test images are procedural"). Specimens are generated at the image window's pixel size (894 × 894 on the 15 Pro Max; 810 on a 402-pt simulator, METRO §D.7), in **linear light**, `rgba16Float`, premultiplied alpha, so values above 1.0 (HDR lights) survive. Geometry is defined relative to the centre c = (N/2 − 0.5 rounded, here 447) so features keep their meaning on other sizes; the §6 numbers are pinned at N = 894, and the tests say so. The specimen `Menu` in the selector row lists them in the groups below; each has a **default probe** on its most informative feature (§5).

| # | id · menu name | Definition (at N = 894) | Default probe | What it reveals | Used by (examples) |
|---|---|---|---|---|---|
| 1 | `siemens-star` · Siemens star | 36 dark–light **cycles** (n_c, CAT §5 E7) about c = (447, 447), value 1 where sin(36θ) ≥ 0 else 0, out to r = 440; outside 0.5; edges anti-aliased by 4 × 4 supersampling | (412, 287), 164 px from c | isotropy, contrast inversion rings (box: square; disc: round at r ≈ 0.261·n_c·R), spin's grey ring at 360°/n_c, zoom's invariance | P1, P2, P11, P21; first launch |
| 2 | `zone-plate` · Zone plate | 0.5 + 0.5·cos(π k r²), k = 0.5/632.2 (local frequency k·r reaches Nyquist at the corners) | (747, 447) | the MTF laid out in space; zero rings; aliasing; zoom destroys it, spin spares it | P1, P8, P11, P21, P23 |
| 3 | `step-edges` · Step edges | vertical step: 0 for x ≤ 446, 1 for x ≥ 447; picker `Vertical · 45°` (x − y ≥ 0, CAL §3.1) | (446, 300) | edge-spread function, 10–90 % width, overshoot, ringing; separable vs isotropic (axis vs 45° marginal) | §6.1; P9, P13 (noise off) |
| 4 | `noisy-step` · Noisy step | step centred on 0.5 with height `0.05 · 0.20 · 1.00` (default 0.20: 0.40 → 0.60); Gaussian noise σ 0.02, seed 1, switchable | (447, 300) | edge-aware filters by contrast; amplitude-dependent transfer | §6.3; P13, P15, P17 |
| 5 | `impulse` · Impulse | one pixel at c with intensity `1 · 10 · 100` (HDR); display toggle `Linear · Log` | (447, 455) | the PSF itself; tails (IIR, Lorentzian), truncation squares | P3, P9, P10, P16 |
| 6 | `impulse-grid` · Impulse grid | 13 × 13 one-pixel dots every 64 px, one at c (x, y ∈ {63, 127, …, 831}), intensity 1 or 100 | (455, 447) | PSF **fields** of shift-variant blurs (zoom rays, cat's eyes, variable blur); bokeh polygons | §6.2 kernel floor; P20, P23 |
| 7 | `checkerboard` · Checkerboard | period `2 px · 16 px` | (447, 447) | Nyquist content: binomial erases 1-px checker exactly, Gaussian leaves 0.72 % at σ 1 | P8, P6 |
| 8 | `stripes` · Stripes | 1-px vertical black/white columns (CAL §3.1) | (447, 447) | the colour-space verdict: 0.500 encoded (gamma blend) vs 0.735 (linear blend) | P18; every blur's API floor branch |
| 9 | `text` · Text | four lines in the system font rendered by Core Text at 9, 12, 18 and 32 px, white-on-black left half, black-on-white right half; the sentences are Blur2ool's own (e.g. "Blur is an average of light.") | on the 12-px line's first stem | legibility; doubled strokes (camera shake); halos (USM); median and morphology | P14, P24, P25, P30 |
| 10 | `night-city` · Night city | black, 120 one-pixel HDR lights at Poisson-disc positions (seed 7), intensities log-uniform 1–100, three colour temperatures; a white light of 100 at c; one pair 20 px apart; three lights within 8 px of the border. Toggle `HDR · Clipped to 1.0 (8-bit)` | (447, 455) | bokeh shape; HDR vs clipped highlights; additive overlap; edge-mode smears | §6.4; P6, P11, P12, P29, P30 |
| 11 | `ramp` · Ramp | horizontal 0 → 1 in linear light across the width; toggle `Linear ramp · Encoded ramp` | (447, 447) | terraces (surface blur, Perona–Malik, mean shift), staircasing (TV) | P17; `surface-blur` |
| 12 | `salt-pepper-text` · Text with impulses | specimen 9 with `NOISE DENSITY` % of pixels set to 0 or 1 (default 10 %, seed 3) | first impulse on the 18-px line | rank vs average: median deletes, bilateral keeps, Gaussian smears | P14 |
| 13 | `alpha-shape` · Shape on transparent | saturated red disc, radius 200 px, centred, on α = 0 (colour (0, 0, 0, 0)) | (647, 447), the rim | premultiplied vs straight alpha: dark fringe | P19 |
| 14 | `edge-bar` · Bar at the border | 32-px bright bar (value 1) touching x = 0, on black | (40, 447) | IIR boundary transient; FFT wrap-around; edge modes | P10; `fft-convolution` |
| 15 | `rings` · Noisy rings | concentric rings of period 12 px about c, contrast 0.5, Gaussian noise σ 0.1 (seed 5) | (543, 447) | flow-following filters (coherence-enhancing diffusion, anisotropic Kuwahara) | Tier 2–3 lessons |
| 16 | `material-backdrop` · Stripes, text and split | top: six saturated 32-px colour stripes; middle: one text line; bottom: white/black split | (447, 700), on the split | materials are mostly colour stages; vibrancy; luminance squeeze | P28 (drawn in SwiftUI for native glass, METRO §C.2) |
| 17 | `scene-depth` · Tilted plane (with depth) | a receding plane of HDR lights plus a near dark bar, with a matching depth buffer | on the bar's edge | depth of field, CoC, near/far edge handling | `depth-of-field-coc`, `tilt-shift` |
| 18 | `scene-motion` · Moving disc (with velocity) | a 120-px disc moving 24 px per frame over a 16-px checker, with velocity and depth buffers; and a rotating bar rendered as N sub-frames | on the disc's trailing edge | per-pixel motion blur vs frame accumulation | P22 |
| 19 | `aerial` · Aerial ground plane | a 32-px checker in perspective, horizon at the top third | on the focus line | tilt-shift's "toy town" | `tilt-shift` |
| 20 | `photo` · Your photo | `PhotosPicker` (out-of-process, no permission prompt, SDK §10); decoded through the image's colour profile into linear `rgba16Float`, centre-cropped, then **area-averaged** to N × N. The resample is itself a box blur and the housing engraving says so: `PHOTO · RESAMPLED ×s (BOX)` | centre | real content; but every number becomes LIVE only, and lessons are disabled | anything |

**Why no photographs ship.** Procedural specimens avoid copyright and, more importantly, have known answers: on the star, zoom must give 1.000 at the probe; on the stripes, 0.735 vs 0.500 decides the colour space. A photograph has no ground truth, so it is an optional extra, not the default.

**Animated specimens.** Only four ever move, and only after an explicit `Play` in the parameters panel: the slowly panning Siemens star (dual-Kawase shimmer, P7, at 0.25 px per frame), the moving point light (pyramid snapping, P7), `scene-motion`, and the impulse "over time" for diffusion (P16). Nothing moves on its own (§2 rule 2, §13).

## 13. Accessibility alternatives

Metro treats accessibility settings as part of the contract (METRO §A.20). Descent adds one rule of its own: **the descent must be completable without seeing a pixel**. Every visual on every floor has a spoken equivalent that carries the same number.

| Need | What Descent does | Metro / source |
|---|---|---|
| **VoiceOver: the specimen** | One adjustable element: "Specimen, Siemens star, blurred with Gaussian, sigma 4.0 pixels. Probe at 412, 287, value 0.52 live." Swipe up/down moves the probe ±1 px along x; a rotor item `Probe axis` switches to y; a second rotor item `Probe step` switches to 8 px. Custom actions: `Descend from this pixel`, `Centre probe`, `Probe to brightest pixel`, `Probe to feature` (the specimen's default probe). | METRO §C.1 item 7 |
| **VoiceOver: centre and focus-line handles** | Adjustable elements with x and y as separate rotor items; actions `Centre on probe`, `Centre on image`. The numeric twins in the parameters panel are ordinary Steppers. | §10.1 |
| **VoiceOver: descent rail** | One element per chip: "Floor 4 of 7, Kernel, 25 taps, computed. Double-tap to show the Kernel card." A custom rotor `Floors` jumps between the seven floor cards in the Lab and the seven tiles in the Trace. | AssemblerToy layer selector |
| **VoiceOver: Trace** | After each step the context card posts one announcement, in fixed order: "Completed: fetch 7 of 13, weight 0.078, value 0. Partial sum 0.399. Next: fetch 8 at plus 7.38 pixels." `Next` is the default action of the whole card, so a double-tap anywhere advances. | METRO §F.1 items 7–8 |
| **Plots** | Every plot (pills, floor insets, fingerprint glyphs, signal lab) has an `AXChartDescriptor`, which also gives iOS **Audio Graphs** (the KERNEL pill becomes a rising and falling tone, the FREQ pill's negative lobes become audible dips), plus a `DisclosureGroup` data table with the same numbers at the same precision. Axes are spoken with units and "normalised" where they are. | METRO §F.4 item 2; Apple `AXChartDescriptor` (iOS 15, REFERENCE) |
| **The 9 × 9 texel grid** | Read as a table: rows and columns are navigable; each cell speaks "x 446, y 300, input 0.000, weight 0.0999". | — |
| **Fingerprint matrix** | Every cell is spoken as words (W5): "Box blur. Linear shift-invariant: yes. Separable: yes. Isotropic: no. Positive response: no, inverts contrast to minus 0.217." | — |
| **Compare** | The divider is adjustable ("Split at 50 percent", ±10 %); a `Swap A and B` action; the difference map's legend is a spoken table of the MAX and RMS values; the Floors mode speaks "First difference at floor 3, Math: rectangle versus bell." | METRO §D.3 |
| **Dynamic Type (AX1–AX5)** | METRO §D.6 layout: subtitle and engravings hidden (ruler ticks stay), the readout band moves below the housing as a native text block, crowns stack vertically, telemetry stacks, the floating group goes icon-only with full spoken labels. The descent rail becomes a vertical list of seven 44-pt rows. Floor cards **grow** at AX sizes: their height is computed from the Dynamic Type size and the largest content any blur puts on that floor, never from the current blur's content, so switching blur still moves nothing. | METRO §D.6, §F.1 item 10, §F.2 item 6 |
| **Reduce Motion** | Pill traces snap instead of easing; the probe's 120-ms fade, the end-of-Trace highlight and the lens bounce are removed; `Play` in the Trace and the four animated specimens stop advancing on their own (manual `Next` and `Step` still work). | METRO §A.20, §F.4 item 8 |
| **Reduce Transparency** | The kernel-well lens goes to opacity 1.0 (never removed, unlike QuantumToy's drift, METRO §F.3 item 1); content panels go opaque; the environment's cyan wash is dropped; the floating group falls back to the opaque `safeAreaInset` strip. | METRO §B.5 |
| **Increased Contrast** | Panel borders 0.20, pill outlines 0.70, badge borders 0.25, the INFERRED badge's dashed border thickens to 1 pt, the probe crosshair thickens to 1.5 pt with a 1-pt black keyline. | METRO §B.5, §C.12 |
| **Colour never alone** | Probe amber **crosshair** vs centre cyan **ring**; the first divergent floor is amber **plus** a ▶ marker **plus** the words `PARTS WAYS`; negative lobes are magenta **and** dashed; compare B is **dashed**; badges lead with the word; selected Atlas row has a ✓ and the `isSelected` trait. | METRO §A.10, §17 |
| **Motor** | No gesture-only control: crowns have 44×44 ± buttons, Steppers hold-repeat, handles have Steppers, the probe has an adjustable action. All targets are at least 44×44. Switch Control order: header → selector row → specimen → crowns → rail → floating group. | METRO §A.18 |
| **Haptics** | Optional (Settings), never the only channel: every detent also changes a visible number. | METRO §15 |
| **Photosensitivity** | Zone plates, 1-px checkers and stripes are high-contrast periodic patterns. They never move unless the user presses `Play`, animated specimens move at most 0.25 px per frame, and nothing changes brightness more than three times a second (WCAG 2.3.1 "Three Flashes or Below Threshold", REFERENCE). The specimen menu marks the periodic patterns with `HIGH-CONTRAST PATTERN` in their row subtitle. | WCAG 2.2 SC 2.3.1 |
| **Low vision on pixels** | The only magnification is of a **copy**: `Magnify` in the Trace shows the 9 × 9 (or 17 × 17) neighbourhood at integer nearest-neighbour scale, never a glass loupe over the specimen (METRO §F.5 item 2). | §5 |

What is **not** claimed: none of the above has been validated. Metro's validation checklist (native glass rendering, held and edge touches during redraw, Dynamic Type, Reduce Motion/Transparency, Increased Contrast, VoiceOver) applies to Blur2ool itself, with simulator, device and hands-on results kept separate (METRO §A, closing paragraph). WCAG contrast of text over the cyan wash and under glass is UNVERIFIED until sampled from real screenshots (METRO §G.2 item 6).

## 14. Deliberately not included

Each exclusion keeps Metro's "smallest useful component set" or protects the honesty rules. Items marked *later* are good ideas that do not belong in v1.

| Not included | Why |
|---|---|
| **Tab bar** | A glass tab bar over live content cut controls in QuantumToy and Los Alamos (METRO §F.3 item 3, §F.4 item 5); a descent has one spine (§3). |
| **Onboarding, coach marks, splash** | The first frame already contains the idea: a pre-placed probe and a button that names it (§2). |
| **`Slider`** | The crowns plus `DecimalParameterStepper` cover continuous values with detents and native alternatives; a slider would be a third continuous control (§10.1). |
| **A second crown pair, or crowns below the fold** | One primary parameter per blur, one crown pair per screen (§10.1). |
| **Round eyepiece specimen** | Crops corner pixels and pushes the readout outside the object (METRO §C.1, §G.1 item 1). Offered only if he asks. |
| **Any glass, `Material` or `.blur` over the specimen or a plot** | The Specimen rule (METRO §C.1): a blur app must not contaminate the pixels it demonstrates. The `liquid-glass` exhibit is the single labelled exception. |
| **A draggable lens or glass loupe** | Breaks Metro contract 2 (fixed lens centre) and adds the system's refraction to the pixels under inspection (METRO §F.5 item 2). Magnification is of a copy only. |
| **Tilt optics in v1** | At D = 88 the warp is at most 2.2 pt and the split about 0.27 pt; Metro puts material response last (METRO §G.1 item 2). `motionActive: false`. *Later.* |
| **Idle motion** | A blur has no clock: no pulsing pills, no breathing lens, no autoplay (§2 rule 2). |
| **Camera or live video input** | Needs a permission prompt, is nondeterministic and has no ground truth. `PhotosPicker` covers "my own picture" without a prompt (SDK §10). *Later.* |
| **Export, share, save** | Blur2ool is an instrument, not an editor. No layers, no mask painting, no saving images. A "copy these numbers" action is a candidate for *later*. |
| **Drawing paths and masks by hand** | Path blur and variable-blur masks use preset menus: freehand drawing has no good accessible twin (§10.2). *Later*, with a Stepper-driven path editor. |
| **Custom kernel editor** | FFT convolution takes any catalog kernel from a menu; a free kernel editor would produce kernels without fingerprints, tiers or CPU references. *Later.* |
| **Configurable GPU internals** (threadgroup size, sampler filter, tile size) | The GPU floor shows the code that ran (§6.0); configurability would turn it into a diagram. Variants are the only switch. |
| **Per-tap traces for FFT and global methods** | Every output pixel depends on every input pixel (CAT §6.1 rule 2); the walk says so and steps through frequencies instead (§7). |
| **Modelled Photoshop internals** | Photoshop's Gaussian radius, Radial Blur Quality and Surface Blur range weight are UNVERIFIED; they appear as UNVERIFIED rows, never as kernels presented as Photoshop's (§10.2 last paragraph). |
| **A σ for Liquid Glass, materials or on-screen SwiftUI blur labelled MEASURED** | Glass is absent from `ImageRenderer` output and on-screen capture is UNVERIFIED (SDK §0, §17 item 1). Offscreen fits are labelled as offscreen. |
| **Live Windows or Android materials** | They cannot run on iOS; Tier 3 models and plots only (CAT §6.4). |
| **Metal 4 on the main path** | Stubbed out of the Simulator SDK; classic Metal throughout, with Metal 4 counter heaps optional on device (SDK §7, GPU §9). |
| **3-D kernel surfaces (`Chart3D`, `SurfacePlot`)** | 2-D heat maps carry the same information, are easier to read aloud, and the phone's 3-D chart performance is UNVERIFIED (SDK §17 item 8). *Later*, as an Atlas ornament. |
| **Landscape, iPad, light appearance** | Portrait-only layout and tilt mapping; dark-only Metro palette (METRO §A.23, §E.6; BRIEF identity). |
| **Sound, quizzes, scores, streaks** | Nothing in the brief asks for them, and Metro's feedback density rules would fight them. |
| **Network, accounts, analytics** | BRIEF: no third-party runtime dependencies, accounts or network. Every measurement stays on the device. |

## 15. Risks

| # | Risk | Why it is real | Impact | Mitigation | How we will know |
|---|---|---|---|---|---|
| R1 | **Content volume.** 55 entries × 7 floors is 385 floor cards, plus a Trace per Tier 1 entry. | Hand-writing them all is weeks of work and would drift from the code. | High | Floors are **templates filled from `BlurCore` data** (kernel, passes, fetch tables, conventions table, badges). Hand-written text is limited to one signature sentence, one governing rule per floor and one closing lesson per Tier 1 entry (23). Tier 3 entries get Floors 1–4 only. Trace steps are generated from each blur's pass graph. | A unit test that every catalog entry renders all its floors without a placeholder string. |
| R2 | **The Trace shows numbers the GPU did not produce.** Recomputing the walk on the CPU would quietly break the LIVE label. | It is the easy implementation. | High (honesty) | Each Tier 1 shader is compiled twice from one source with a function constant `TRACE_PROBE`: the traced build writes, for the probe pixel only, each tap's position, weight, fetched value and running sum into a small buffer. A parity test asserts that the traced build's final value equals the untraced build's output at the probe, bit for bit, and equals `BlurCore` within the stated tolerance. | Parity CLI on the Mac; the same test in the app's debug menu on device. |
| R3 | **The worked numbers depend on N = 894.** On a 402-pt simulator (N = 810) the probe coordinates and some values change. | Specimens are generated at the window's pixel size (§12). | Medium | Probes are defined by feature, not coordinate; tests pin the §6 numbers at N = 894 and check the feature-relative values at 810. | `swift test` on `BlurCore` at both sizes. |
| R4 | **A17 Pro facts are unverified** (bilinear sub-texel bits, bandwidth, compression cost, counter sampling). | Everything device-specific so far was measured on the M1 Max or read from tables (SDK §17, GPU §8). | Medium | The This phone screen measures them and upgrades the badges in place (§11.2 item 6); until then rows say REFERENCE, MODELED or UNVERIFIED. | This phone run on his phone, recorded with OS build and date. |
| R5 | **SwiftUI and system blurs measured offscreen may differ from the screen.** | `ImageRenderer` paths already differ by 9 % in σ on the Mac (CAL §8). | Medium | Every system number says `OFFSCREEN · ImageRenderer`; on-screen capture is attempted once (SDK §17 item 1) and only then labelled on-screen. | Device test of `drawHierarchy` vs `ImageRenderer` on an impulse. |
| R6 | **GPU timing is noisy at small sizes.** A 0.1-ms blur is dominated by command-buffer overhead and clock ramp. | GPU §4.3; SDK §17 item 5. | Low–medium | Median of 30 after warm-up, refreshed at most 4 Hz; values under 0.05 ms print `< 0.05 ms`; the Cost plot shows the overhead floor as a measured baseline (an empty pass). | Repeated runs on device; thermal state recorded. |
| R7 | **Heavy entries stall the live preview.** Brute bilateral is 2.3·10⁸ weight evaluations per frame; NLM and Perona–Malik are worse. | §6.3. | Medium | `Half while moving` preview, generation tokens so stale renders never publish (METRO §F.2 item 3), and an honest status row (`PREVIEW · HALF RES`). | Frame time on device with the crown spinning at 20 events/s. |
| R8 | **Simulator limits** (Apple2-class: 16 KB threadgroup memory, no non-uniform dispatch, no 32-bit float filtering). | SDK §15. | Medium | `dispatchThreadgroups` with bounds checks everywhere; tiles sized to ≤ 16 KB (bilateral tile 8,192 B); no linear sampling of 32-bit float textures. | Simulator run with Metal API validation on. |
| R9 | **The descent is too long and users never reach the GPU floor.** | Seven cards below a tall first viewport. | Medium | The rail shows all seven answers in the first viewport; any chip jumps to its card; the Trace's floor tiles allow skipping ahead; Lessons start four guided descents in one tap. | Hands-on session with him: does he reach Floor 6 unprompted? |
| R10 | **Fixed-height floor cards overflow** for verbose entries (system blurs, FFT entries). | 232 pt is tight for four rows plus a rule. | Low | `All … details` disclosure is the only growing element; card text is length-checked in a unit test against the 406-pt width at the default Dynamic Type size. | Snapshot test of every entry's seven cards. |
| R11 | **Metro deviations accumulate.** Descent drops the first-viewport Stepper for continuous primaries, uses glyph-only badges on rail chips and a `safeAreaInset` strip in the Trace. | Each is argued, but together they could drift from Metro's feel. | Low–medium | Every deviation is listed in this document with its precedent (§4 W1 note, §11.2 item 2, §4 W3); they are reviewed together at the first device build. | Side-by-side screenshot with Metro Station build 14. |
| R12 | **Native glass over a scrolling `MTKView`.** The floating group passes over the specimen when the Lab scrolls; whether glass samples Metal content correctly is UNVERIFIED (METRO §G.2 item 1). | It is harmless to measurements (all numbers come from textures), but it could look broken. | Low | If it looks wrong on device, the floating group falls back to the `safeAreaInset` strip (METRO §F.1 item 12). | Device screenshot while scrolling. |
| R13 | **Third-party conventions change or are wrong.** Figma's σ = value/2 is INFERRED; GIMP and Android rules come from source code that can change. | STACK §4, §9. | Low | Every convention row carries its badge and source date; the conventions table lives in `BlurCore` data so it can be corrected in one place. | Periodic re-check; user reports. |
| R14 | **Fingerprint numbers not yet computed.** The hexagon's kurtosis, the Unity 13-tap σ and shift variance, and some Tier 2 MTF minima are blank in the research. | CAT §5 E2; §8.2 above. | Low | `BlurCore` computes them with tests; the Atlas shows `—  NOT YET COMPUTED` rather than an estimate. | Unit tests fill the matrix with no blanks. |
| R15 | **Pattern-sensitive users.** Zone plates and checkers are high-contrast periodic patterns. | WCAG 2.3.1. | Low | Static by default, slow when animated, labelled in the menu (§13). | Review with Reduce Motion on and off. |
| R16 | **Build infrastructure.** `xcodebuild` hangs inside iCloud; simulators hang under load. | BRIEF build rules; METRO §F.4 items 6–7. | Medium (schedule) | `Tools/build.sh` mirror with a manifest hash, dedicated `Blur2ool <topic>` simulators, `simctl` behind timeouts, headless checks first (`swift test`, offscreen PNGs). | Build log records the source hash for every screenshot. |

**Build order this concept implies** (so the riskiest honesty pieces land first): `BlurCore` catalog data, kernels and the four worked examples as tests → the Mac parity CLI with the `TRACE_PROBE` build → the Lab first viewport for the Gaussian → the seven floor templates → the Trace for the Gaussian → the other three worked examples → the remaining Tier 1 entries → Atlas, Compare and Lessons → This phone → Tier 2 and Tier S entries.
<!-- STATUS: COMPLETE -->
