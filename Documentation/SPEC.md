# Blur2ool — Product and UX Specification (binding)

Date: 14 October 2026. Author: lead designer-architect (synthesis pass). Status: complete. The body was written in the first synthesis run, then reviewed and closed in the second run together with ARCHITECTURE.md; design review round 1 (engineering and product reviews, `design/review-*.md`) was applied the same day, and ARCHITECTURE.md's closing "Review log" lists every change and every rejected item. The completion marker is the last line.

Inputs read for this synthesis: `BRIEF.md`; the three concepts `design/concept-instrument.md` (I), `design/concept-descent.md` (D), `design/concept-engine.md` (E); the three judges `design/judge-delight.md` (JD), `design/judge-truth.md` (JT, interim notes only: the run died before its verdict sections), `design/judge-feasibility.md` (JF, complete except its §4.1 probe result); research `research/CATALOG.md` (CAT), `metro-adaptation.md` (METRO), `sdk-feasibility.md` (SDK), `gpu-pipeline.md` (GPU), `stack-semantics.md` (STACK), `live-calibration.md` (CAL), with `catalog-lsi.md` (LSI), `catalog-spatial.md` (SPA), `catalog-nonlinear.md` (NL) consulted through CATALOG. Section references such as "I §3.1" point into those files.

## 0. How to read this document

- This file is the **product contract**: what the user sees, touches and reads. `ARCHITECTURE.md` is the **engineering contract**: files, frozen Swift interfaces, build areas, verification. Where the two seem to disagree, SPEC decides *what* and ARCHITECTURE decides *how*; a real conflict is a bug to report in the reporting area's request file `Documentation/build/requests/<AREA>.md`.
- **Binding words.** "Must" and "never" are acceptance criteria. "Should" is a strong default that a build area may change only with a written reason in its progress file.
- **Numbers.** Every number in this file keeps the honesty label of its source (LIVE, MEASURED, COMPUTED, MODELED, REFERENCE, INFERRED; UNVERIFIED as a qualifier). Numbers marked "(fixture)" are worked-example values that `BlurCore` unit tests must reproduce. Numbers marked "(illustrative)" only show a format; the app computes or measures the real value.
- **Verification while the simulator hold is active** (`HOLD-SIMULATOR.md`) follows ARCHITECTURE §12. Checks this file describes in terms of the Simulator run on the phone or on the Mac GPU, or are recorded as DEFERRED-BY-HOLD. The product's own Simulator behaviour (§12.2 item 7: `SIM`, no GPU timings) is unchanged.
- **Engineering readings.** ARCHITECTURE §14 (a)–(g) records how the build reads a few places where this file is ambiguous: the median deck, the Gaussian radius rule, MASS CUT, the truncation behind §17 item 8, discretisations as a parameter, FFT padding, and the SAT default. SPEC still decides the product.
- **Internal names vs on-screen words.** This document uses a few internal names for parts of the UI: *Bench* (the root screen), *blur strip* (the row of blur glyphs), *rail* (the seven floor chips), *periscope* (the pinned live mini-specimen on the Layers screen), *deck* (the 98-pt control slot). **None of these words may appear in on-screen copy** (JD M7: no metaphors he has to decode). On screen the words are: "Blur2ool", "Blurs", "Layers", "Compare", "Descend from (x, y)", "Lessons", "Field guide".

### 0.1 The synthesis in one paragraph

The judges split. Delight crowned **Instrument** (a toy you touch: Night City lights, crowns, σ-hold, a draggable image); Feasibility crowned **Descent** (a testable, Metro-conformant shell with an honest pixel trace) on top of **Engine**'s measurement core. Blur2ool takes **Instrument as the chassis** (first ten seconds, blur strip with σ-hold, direct manipulation of the image, Metal loupe, fingerprint card), puts **Descent's rail, trace and divergence** into it, and runs it all on **Engine's Run record and timing discipline**. The two judges' hard conflicts are resolved like this:

| Conflict | JD wants | JF forbids | Binding resolution |
|---|---|---|---|
| Does the root scroll? | A non-scrolling Bench (G1) | A fixed root whose fit depends on unverified safe areas, and a second gesture regime at AX sizes (M-2) | **The root scrolls, but its first viewport is the whole instrument** at the default text size on 430 × 932. Touches that *begin on the image window* belong to the image for the whole sequence (Metro contract A.16, via `instrumentControlOwnsTouches`); the page scrolls from everywhere else. One gesture regime at every text size. |
| How many image gestures? | Tap, drag/pan, handle drags, pinch, long-press loupe, two-finger reset, paint (I §4) | Pan + pinch + loupe + reset + paint + handles at once (M-1) | **Five, with a fixed priority and a unit-tested arbiter:** handle drag > pinch > long-press loupe > one-finger drag (pan) > tap (probe). Two-finger reset and paint are cut (reset is a menu item; paths are presets). |
| Where do Steppers live? | On a sheet, behind the hero (I §3.8) | Not buried (M-13); Metro §9 wants them under the hero | **Directly below the fold, first thing after telemetry**, in a Parameters panel. Tapping the hero scrolls to it. The crowns' ± glass buttons and adjustable actions are the in-viewport native alternative. |
| Telemetry or rail in the first viewport? | Rail replaces telemetry (G4) | Telemetry in the first viewport (G-12) | **Rail in the first viewport** (its GPU chip carries the MEASURED time, its PIXEL chip the LIVE value); the full worded telemetry row (σ EFF · GPU · PARITY) is the first thing below the fold. |
| Launch-time measurement | Calibrate quietly after idle (G19) | Nothing automatic in the first seconds or on the main actor while crowns are live (M-3) | **Nothing measures during the first 10 s.** SwiftUI `.blur` calibration runs only after ≥ 10 s from launch **and** ≥ 3 s with no touch, one `ImageRenderer` render per run-loop turn with back-off, stopping on any touch (ARCHITECTURE §5.13); or immediately when he opens a Tier S blur. Device probes run only on demand. |
| Compare views | Wipe, Flip, Difference, Line-up 2 × 2 (G15) | No 4-up with seven B sources in v1 (M-18) | **Wipe, Flip, Difference in v1 for any pair; Line-up 2 × 2 only for the catalog's triads**, entered from Lessons, with B/C/D on the Operator axis only. |

Section 20 lists every judge graft and must-avoid item and where this spec satisfies it.

## 1. Pitch

**Blur2ool is a pocket optical bench for blurs.** One machined specimen holds a live GPU blur that you turn with crowns, drag with a finger, wipe against its rivals and swap in one tap. Under the specimen sit seven floors, from the number a designer types to the pixel that comes out, and every floor shows its answer about one pixel you chose. Every number on the screen says whether it was measured on this phone, computed from the math, modeled, cited or inferred.

The app is a toy first and the most honest blur textbook on the phone second. Learning is never a mode he enters; it is what he sees when he looks closer.

What it answers, mapped to the four requirements in BRIEF:

| BRIEF requirement | Where Blur2ool answers it |
|---|---|
| 1. Blur simulator: real blurs, real pixels, GPU, live, adjustable | The Bench (§4.1): an 894 × 894 px Metal window, crowns with detents, direct manipulation, **53 live blurs** on the blur strip: 50 on our GPU (Tier 1 and 2) and 3 Apple system blurs run live and measured (Tier S, §10.1) |
| 2. Mathematical visualizer | KERNEL and FREQ pills on the Bench; the Math, Kernel and Algorithm floors (§5); the fingerprint card's four glyphs (§7) |
| 3. Every layer from WYSIWYG to the GPU, following one pixel | The rail (seven live answers on the Bench, §4.1.4), the Layers screen (§4.3, §5) and the Trace (§4.4, §6), with values the GPU itself recorded |
| 4. What makes each blur unique, across dozens | σ-hold on switch (§8.1), the fingerprint card with its unique number (§7), "where two blurs part ways" (§8.4), 30 lessons and 4 guided descents (§8.5), 62 catalog entries in 12 groups (§10) |

## 2. The first ten seconds

Target: within ten seconds of a cold first launch, without reading a paragraph, he has (a) seen a beautiful blur, (b) changed it with his thumb and felt the detents, (c) swapped it for another blur and seen the *shape* change while the *size* stayed, and (d) seen that there are floors underneath, with real numbers. No splash, no onboarding, no permission prompt, no spinner, no placeholder slots (JD M1, M10).

| Time | What is on screen | What the engine does | Why |
|---|---|---|---|
| 0.0 s | The Bench (§4.1). Specimen **Night City** at exposure 0 EV, in linear HDR light (its light energies are specified so that at σ 12 at least 40 lights still peak at ≥ 0.25 linear in SDR, §11; launch fixture). Blur `gaussian-blur`, variant `gaussian-linear-sampling`, **σ = 12.0 px**. The **before/after split** sits at 50 %: left of the divider the INPUT (sharp points of light), right of it the blurred output (round glows). The probe crosshair is pre-placed at Night City's default probe **(447, 455)**, 8 px below the reference light. The rail shows seven chips; the GPU chip reads `–.––` until a measurement exists. The primary floating button reads **`Descend from (447, 455)`**. | Pipelines come from the precompiled `default.metallib` and are specialised off the main actor. The specimen canvas is generated off the main actor (a cached canvas on later launches). Launch never blocks the main thread: until the first Run arrives the housing shows the sharp INPUT window, a real image, with `RENDERING…` in the status row and no spinner (ARCHITECTURE §5.9). | The first picture answers "what is a blur?" by showing before and after at once. Point lights are where blurs look best and differ most (JD G2). A coordinate, not an instruction, is the first thing he reads (JD G5). |
| 0.0–0.6 s | **First launch only:** one focus pull: the right half eases from σ 0 to 12 px over 600 ms; the hero counts up to `12.0`; the pills draw their traces once. Then nothing moves until he touches something. Skipped under Reduce Motion (it starts at 12.0). | Up to 36 renders at intermediate σ, no timing. | A blur has no clock, so there is no idle animation (METRO §C.5). One settle movement makes the instrument feel switched on. |
| ≈ 1 s | The fixed status row reads, once: `TURN A CROWN · DRAG THE IMAGE · TAP A BLUR`. It is replaced by the normal phase line after the first accepted interaction and never shown again (Settings can re-arm it). | — | One coaching line in a slot that already exists (Metro §16). |
| 2–4 s | He turns the **FINE** crown: every 8° detent is ±0.1 px of σ with the fine haptic. The glows breathe; the KERNEL pill's bell widens; the FREQ pill's curve narrows toward DC; the hero reads `12.1`, `12.2` in monospaced digits; the rail's KERNEL, GPU and PIXEL chips update. He flicks the amber **SEMANTIC** crown: it clunks between octave stops 8 · 16 · 32 px and the serif meaning changes *Backdrop* → *Fog*. | Every accepted detent renders (reduced resolution only for heavy blurs, §4.1.6). Timing waits for the value to settle (≈ 300 ms), then 3 warm-ups and up to 15 timed command buffers (at most 1 s of GPU time) fill the GPU chip with a MEASURED median; any touch cancels it. | Two crowns, two feels (Metro signature move). Timing never runs per detent (JF M-4). |
| 4–6 s | He drags the split divider (a 44-pt handle that owns its touch), or drags anywhere else on the image to pan the city under the blur, or taps a pixel: the probe jumps there (120 ms fade) and on the rail **only GPU and PIXEL change**; SLIDE to ALGO keep their values. | Pan moves the specimen by whole pixels under a fixed window (§4.1.3). | Shift invariance falls out of the layout without a word (JD G6). |
| 6–8 s | He taps the **hexagon** glyph in the blur strip. The right half becomes `polygonal-bokeh`: the bright lights (about 30 of them, MODELED from §11's energy distribution) become crisp hexagons; dim ones become faint hexagonal smudges. The status row says `σ HELD 12.0 px → R 26.3 px`; VoiceOver announces the new blur, the held σ, the converted radius and the PSF SHAPE and RESPONSE rows (§14). The lights are the same size in the second-moment sense; only the shape changed. | σ-hold conversion (§8.1) from `BlurCore`, COMPUTED. | σ-hold turns every switch into an experiment (JD G3, M5). |
| 8–10 s | He notices the rail under the crowns: `SLIDE · API · MATH · KERNEL · ALGO · GPU · PIXEL`, each with a value. Tapping one opens the Layers screen at that floor; the primary button opens the Trace from his pixel. | — | The depth is visible as live values on the root (JD G4, M4). |

**Later launches** restore the last state (blur, variant, parameters, specimen, exposure, probe, pan, split, compare state) and show it immediately, with no focus pull and no coaching line. State is per-device (`UserDefaults`/`@SceneStorage`); nothing needs a network or an account.

**Calibration in the background.** If SwiftUI `.blur` has never been measured on this device, the measurement starts only when all of these hold: ≥ 10 s since launch, ≥ 3 s since the last touch, no crown or handle active, thermal state nominal or fair. It runs one `ImageRenderer` render per run-loop turn on the main actor (a render cannot be pre-empted, so each is timed; a render over 16 ms doubles the gap before the next), never while a control is active, and pauses at the next touch. A tiny engraved line in the Field guide's This phone tab (never on the Bench) shows its progress. Until it finishes, every SwiftUI-derived number keeps its INFERRED badge (§13).

## 3. Information architecture

One spine, no tab bar (METRO §F.3 item 3, JD M8). The root is a `NavigationStack` whose root view is the Bench. Depth goes by push; side trips go by sheet; every sheet comes from **one** `.sheet(item:)` destination enum (Toothpaste Toy's two-sheet failure, METRO §F.5 item 3).

```
Bench  (NavigationStack root; ScrollView whose first viewport is the whole instrument)
 ├─ in place:  Probe (tap) · Pan (drag) · Loupe (long press) · Zoom (pinch) · Handles (drag)
 │             Before/after split · Compare mode (Wipe · Flip · Difference · Line-up for triads)
 ├─ below the fold (one short scroll):  Telemetry → Parameters panel → Pass tiles → Fingerprint (compact)
 ├─ push ▸ Layers   (7 floors, vertical paging, pinned live periscope)   ← tap any rail chip
 ├─ push ▸ Trace    (one pixel, floor by floor, pass by pass, fetch by fetch) ← "Descend from (x, y)"
 └─ sheet (one .sheet(item:))
      ├─ Catalog         tabs: Blurs · Fingerprints · Divergence · Lessons   ← "All" in the blur strip,
      │                                                                        the housing caption, "Lessons"
      ├─ Fingerprint     the full card for one blur                          ← tap the kernel well
      ├─ Field guide     tabs: Guide · This phone · Runs · Settings          ← header glass icon button
      └─ Calibrate       measure an Apple blur on this phone                 ← Tier S blurs, This phone, Compare › Apple
```

| # | Screen | Presentation | Reached from | Job (one sentence) |
|---|---|---|---|---|
| S1 | **Bench** | `NavigationStack` root, `ScrollView` with `.id(blurID)` | launch | Play with one live blur and see all seven floors' answers about one pixel. |
| S2 | **Layers** | push (`NavigationTransition` cross-fade, iOS 27) | tap a rail chip (opens at that floor); a floor link in the fingerprint card | Read what each floor says about the current blur and probe, with the live image pinned above. |
| S3 | **Trace** | push | primary button `Descend from (x, y)`; `Descend another pixel`; a guided descent | Walk one output pixel down the seven floors one step at a time, with what happened and what happens next kept apart. |
| S4 | **Catalog** | sheet `.large` | `All` at the end of the blur strip; the blur name in the housing caption; the `Lessons` floating button (opens on the Lessons tab) | Find any blur; compare all blurs by fingerprint; see where any two part ways; start a lesson. |
| S5 | **Fingerprint** | sheet `.medium` / `.large` | tap the kernel well; `Full card ›` in the compact card | What makes this blur unique, in a fixed layout identical for every blur. |
| S6 | **Field guide** | sheet `.large`, `NavigationStack` + `Picker(.tabs)` | header glass icon button | The current blur's field guide with citations; this phone's measured facts; the Run log; settings and the honesty legend. |
| S7 | **Calibrate** | sheet `.large` | `Measure on this phone` (Tier S blurs' Parameters panel); This phone tab; Compare › Apple axis | Measure an Apple blur API on this device, fit competing models, sweep the radius. |
| M1 | **Compare** | in-place mode of S1 | floating `Compare` button; a lesson; `Compare with current` on a strip glyph | Two blurs (or one blur and its reference implementation) on one specimen, varying exactly one thing. |
| — | Specimen menu | native `Menu` (the button at the left of the blur strip) | — | Pick a procedural specimen or a photo; exposure; split; reset view. |

**State model (one source of truth).** A `BenchState` holds the *requested* configuration: blur id, variant id, parameter values, specimen id and its options, probe, pan, zoom, split, colour space, edge mode, alpha mode, precision, preview policy, and the compare state (a second configuration B plus axis and view). Controls write it and show requested values immediately. Everything derived from GPU output follows a **completed Run** (Engine's immutable record, §4.1.6 and ARCHITECTURE §5): the image follows the newest Run of any resolution; the measurement-derived readouts (pills' LIVE content, rail values, PIXEL, loupe, telemetry, pass intermediates, the kernel-well face and support bracket) follow the newest **full-resolution** Run and are marked `HELD` while a preview is on screen. While the two differ the fixed status row says `RENDERING…` (Metro contract A.13). Layers and Trace read the same state and the same Runs; they never compute their own numbers.

**Navigation rules.** Back from Layers or Trace returns to the Bench with the probe crosshair highlighted for one second. The floating group exists only on the Bench. Sheets never stack: opening a destination replaces the current one. Calibrate pushed from the Field guide's This phone tab is a push inside that sheet's `NavigationStack`, not a second sheet. The photo picker is a system presentation attached to the specimen menu button, not to the root (one presentation per view).

## 4. Screens (430 × 932 pt wireframes)

**Conventions for every wireframe.** iPhone 15 Pro Max portrait, 430 × 932 pt at scale 3 (1290 × 2796 px; VERIFIED from the simulator device profile, METRO §D.0). Safe-area insets 59 pt top and 34 pt bottom are the commonly published values and are **UNVERIFIED**; the build reads them from `GeometryReader` and logs them on the device (METRO §G.2 item 2). Screen inset 12 pt, so the content column is x 12…418 (406 pt) and Metro's cluster formula gives D = 322, pill 36 × 212.5, image window D − 24 = 298 pt = 894 px (METRO §B.6, §D.7). The left column of each sketch gives screen y in points; one character is about 6.7 pt. Component names are the Metro starter's (`Instrument*`), the Blur2ool components built in Metro grammar (METRO §E.2, §E.3), or native SwiftUI. Tokens and colours are from METRO §B and are named, never re-typed as literals. **LIVE and MEASURED values drawn in wireframes (GPU ms, parity, probe outputs, ON THIS PHONE rows, Calibrate results) are illustrative formats**, not results; COMPUTED values in wireframes are real and are fixtures where §5.3 lists them.

Colour roles used below (METRO §B.1–§B.2): canvas `#060B0F`; content panel `#0B1216` at 0.85; housing `metalLight #0E1317 → metalDark #05080B`; action cyan `#57EDF5` (selection, Stepper values, primary idle); action amber `#FFBD5E` (primary running, completed steps); instrument cyan `#52E8F5` (crown marks, serif meaning, rulers); instrument amber `#FFB84F` (probe crosshair, support bracket, first divergent floor); wave primary `#4FDBFF` (KERNEL pill); wave secondary `#3666FF` (effective kernel depth); spectrum primary `#C291FF` (FREQ pill); spectrum secondary `#F55CD6` (negative lobes, INFERRED badge ink); carrier `#FFBA57` (−3 dB marker); text display `#E8F2F7`; text secondary `#99B0BA`.

### 4.1 Bench (S1), first viewport: Gaussian on Night City, before/after split at 50 %

```
y    0 ┌──────────────────────────────────────────────────────────────┐
       │ 9:41               (  Dynamic Island  )              ▂▄▆ ▮  │ environment: canvas + cyan wash 0.085 + 28-pt grid
   59  ├──────────────────────────────────────────────────────────────┤ safe area (59 pt, UNVERIFIED)
   69  │  Blur2ool                                          ( ▤ )    │ title 27 pt semibold rounded · glass icon button 44×44
       │  BLUR SIMULATOR · WYSIWYG → GPU                              │ subtitle 11 pt mono, tracking 2.6, white 0.68
  130  │ [▦] ┊ ◍ □ ⬡ ◯ ⁘ ✺ ⟶ ◎ ↻ ⌗ ◐ ▒ ┊ ▫ ▫ ▫ ▫ ▫ ▫ … ( All )  │ blur strip 44: specimen Menu 44 + glyphs 44×44, gap 6
  174  ├──┬───────────────────────────────────────────────────────┬───┤
  186  │K │ ◀ INPUT │ GAUSSIAN ▶ · NIGHT CITY        LIVE · METAL  │ F │ housing caption row, 11 pt mono, in the 24-pt top margin
  210  │E │ ┌──────────────────────┬┬──────────────────────┐       │ R │ image window 298 × 298 pt = 894 × 894 px (MTKView)
       │R │ │  ·    *     ·    ✶   ││  ○    ◯     ○    ◯   │       │ E │ left of the divider: INPUT; right: OUTPUT
       │N │ │      ✶   ·      *    ◀▶     ◯   ○      ◯     │       │ Q │ split divider: 44 × 298 handle, owns its touches
       │E │ │   *    ·      ·      ││   ○   ✛     ○    ◯   │       │   │ ✛ probe crosshair (447, 455), instrument amber
       │L │ │  ·   ✶      ·     *  ││ ○   ◯      ○    ◯    │       │   │ pills 36 × 212.5 at x 12 / 382, y 252.75–465.25
       │  │ └──────────────────────┴┴──────────────────────┘       │   │ rulers in the 12-pt metal margins; amber ±3σ bracket
  516  │  │ SIGMA · PX                             ╭──────────╮    │   │ readout band y 516–620 (foreground, never filtered)
       │  │ 12.0                                   │  kernel  │    │   │ hero 44 pt light rounded, monospaced digits, width for "64.0"
       │  │ Backdrop                               │  well 88 │    │   │ meaning: serif italic, instrument cyan
       │  │ 74 FETCHES · 2 PASSES · LINEAR-SAMPLED ╰──────────╯    │   │ status row: fixed 14 pt, 11 pt mono
  632  ├──┴───────────────────────────────────────────────────────┴───┤
  640  │ ┌SLIDE┐ ┌ API ┐ ┌MATH ┐ ┌KERNL┐ ┌ALGO ┐ ┌ GPU ┐ ┌PIXEL┐      │ rail: 7 chips 54 × 52, gap 4 (event-tile grammar)
       │ │≈4.4 │ │12.0 │ │  G  │ │ 73  │ │ 2×  │ │–.–– │ │0.0885│     │ value 13 pt mono digits (no units on chips); badge glyph 11 pt top-trailing
  692  │ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘      │
  700  │        FINE                          SIGMA · Backdrop        │ deck 98: caption 14 · 4 · crowns 62 · 4 · caption 14
       │   (−)( ◉ )(+)                     (−)( ◉ )(+)               │ FINE (cyan, 8°) · SEMANTIC (amber, 20°); ± glass 44×44
  798  │       ±0.1 PX                     Frosted ⇆ Fog              │
  828  │  ( ⧉ Compare )  ( ⤓  Descend from (447, 455) )  ( ◫ Lessons )│ floating glass group: 62×58 · flex .glassProminent · 54×58
  886  │                                                              │ GlassEffectContainer(spacing: 14), inset 22, bottom 12
  898  ├─────────────────────── home indicator (34) ───────────────────┤
  932  └──────────────────────────────────────────────────────────────┘
```

| Element | Frame (x, y, w, h) pt | Component · tokens | Behaviour |
|---|---|---|---|
| Environment | full screen | `InstrumentDesignBackground` | Ignores safe areas; accessibility-hidden; no hit testing. |
| Header | 24…406, 69–118 | starter header recipe; `InstrumentGlassIconButton` (AssemblerToy's hardened copy, METRO §F.1 item 4) 44 × 44 at x 362, symbol `book.closed` | Button opens the Field guide sheet; spoken "Field guide and settings". Subtitle hidden at accessibility sizes. |
| Blur strip | 12…418, 130–174 | specimen `Menu` 44 × 44 (symbol `photo.on.rectangle.angled`) at x 12; horizontally scrolling glyph row x 64–418 (`ScrollView(.horizontal)`), glyphs 44 × 44 `Canvas` footprint drawings in instrument cyan on recessed metal, gap 6; family boundaries as 1-pt engraved ticks; `All` text button at the end | §4.1.2 |
| Specimen housing | 54, 186, 322, 446 | `SpecimenHousing`: radius 30, `metalLight → metalDark`, 1.4-pt four-stop rim (white 0.36 → 0.025 → black → 0.15), shadow black 0.8 r 22 y 16 (METRO §B.5) | Still frame; never moves. |
| Caption row | 66…364, 186–210 | 11 pt mono (`@ScaledMetric`, capped at the 24-pt margin), white 0.68; provenance engraving right-aligned | Left: split labels or blur name, then specimen (tap the blur name → Catalog). Right: provenance, never truncated: `LIVE · METAL`, `PREVIEW ½`, `PREVIEW ¼`, `ZOOM 4× · NEAREST`, `PASS 1 OF 2 · INTERMEDIATE`, `SYSTEM · ON SCREEN`, `MODELED · METAL`, `INFERRED · NATIVE GLASS`. Truncation order: specimen name first, then blur name. The provenance is also the first phrase of the image's VoiceOver value. At AX sizes the row moves below the housing (§4.1.10). |
| Image window | 66, 210, 298, 298 | `SpecimenWindow`: an `MTKView` (894 × 894 px drawable) under a UIKit touch layer, wrapped in `instrumentControlOwnsTouches(identifier: "specimen")` | §4.1.3. Nothing translucent ever overlaps it (Specimen rule, METRO §C.1). |
| Rulers | metal margins | `Canvas`, white 0.16 minor / 0.36 major; minor every 8 px (2.67 pt), major every 64 px (21.3 pt); engraved `SCALE 1 PX = 0.33 PT` at the left end of the bottom ruler (METRO §C.1; SLIDE values are in the tool's unit, API values in px) | Amber bracket on the top ruler spans the kernel's support (±⌈3σ⌉ = ±36 px here, COMPUTED) of the **acknowledged** Run, like every output-describing element; for LSV blurs, the support at the probe. |
| KERNEL pill | 12, 252.75, 36, 212.5 | `InstrumentSignalPill`, title `KERNEL` in wave primary `#4FDBFF` | §4.1.3 "Pills". |
| FREQ pill | 382, 252.75, 36, 212.5 | `InstrumentSignalPill`, title `FREQ` in spectrum primary `#C291FF` | §4.1.3 "Pills". |
| Readout band | 66, 516, 298, 104 | adapted `InstrumentLargeReadout`: unit line 11 pt mono tracking 2.2 white 0.68 · hero 44 pt light rounded monospaced digits (reserved width of the widest legal value) · meaning serif italic subheadline instrument cyan · status row 11 pt mono fixed 14 pt | Hero = the blur's declared primary parameter, *requested* value (no badge: it is his input). Tap the hero → the Bench scrolls to the Parameters panel. |
| Kernel well | 276, 524, 88, 88 | `InstrumentLensSurface(diameter: 88, motionActive: false)` unmodified (glass 67 pt = 0.76 D, opacity 0.48, 1.0 under Reduce Transparency) over a decorative `Canvas` footprint (§4.1.3 "Kernel well") | Tap → Fingerprint sheet. No number or label under the glass. A one-shot 1.0 → 1.04 → 1.0 bounce when the SEMANTIC crown lands on a new band; never repeating. |
| Rail | 14…416, 640–692 | `DescentRail`: 7 chips 54 × 52, gap 4, radius 8; idle white 0.025 / 0.06; label 11 pt mono; value 13 pt mono monospaced digits; badge glyph 11 pt top-trailing; an INFERRED chip also gets a dashed 1-pt border (a redundant cue that does not depend on reading the glyph) | §4.1.4 |
| Deck | 41…389, 700–798 | per-blur arrangement (§9.1): here `InstrumentCrown` ×2 between glass ± `Button`s 44 × 44 (group 44 + 6 + 62 + 6 + 44 = 162; two groups + 24 gap = 348) | Reserved 98 pt: never collapses, so nothing below moves when the blur changes (METRO §F.1 item 2). |
| Floating group | label frames 22…408, 828–886 | `InstrumentFloatingActionGroup`: `GlassEffectContainer(spacing: 14)`; `Compare` 62 × 58 (`rectangle.split.2x1`), primary flexible ≥ 58 `.glassProminent` (`arrow.down.to.line`), `Lessons` 54 × 58 (`graduationcap`) | §4.1.7. Reports its measured glass height through a preference key; the scroll content's bottom reserve = measured height + 28. |

#### 4.1.1 Header

Title `Blur2ool`, subtitle `BLUR SIMULATOR · WYSIWYG → GPU`. One glass icon button (Field guide). Nothing else: no blur name, no settings gear, no status chip (Engine's `DEVICE · PROBING` chip is cut, JD M1).

#### 4.1.2 Blur strip

- **Order.** First the *hero dozen*, then every other live entry grouped by family F1…F11, then the contrast group, then `All`:
  hero dozen = `gaussian-blur`, `box-blur`, `polygonal-bokeh`, `disc-blur`, `kawase-blur`, `radial-zoom-blur`, `spin-blur`, `linear-motion-blur`, `bilateral`, `median`, `frosted-glass-noise`, `swiftui-layer-blur`.
- **Membership.** Every entry that produces a live image on this device: Tier 1, Tier 2 and Tier S (§10). Tier 3 entries appear only in the Catalog (JD M13: a glyph must always produce a live GPU image). Variants are not glyphs; they are chosen in the Parameters panel's algorithm picker.
- **Glyph.** The blur's 2-D footprint drawn exactly as on the kernel-well face, 44 × 44, instrument cyan on recessed metal. Selected glyph: cyan fill 0.08 + border 0.35 **and** a 2-pt underline (colour plus shape, Metro §17), plus the `isSelected` trait.
- **Tap** switches the blur with **σ-hold** (§8.1): the status row says `σ HELD 12.0 px → R 26.3 px` for 2 s (or, when a range limit binds, `σ HELD 12.0 px → σs 8.0 px (MAX) · Δσ −4.0 px`), or `σ NOT DEFINED · RANK FILTER` / `· SPACE-VARIANT` / `· SYSTEM MATERIAL` when the new blur has no σ. The σ-hold line stays in the readout's accessibility value until the next change, and VoiceOver announces the switch (§14). The previous blur becomes the default B for Compare.
- **Long press** opens a context menu titled with the blur's display name: `Open` · `Compare with current` · `Fingerprint card` · `Field guide`.
- **`All`** opens the Catalog sheet on the Blurs tab.
- The strip scrolls horizontally only; it never scrolls the page vertically (its pan is horizontal). When a blur is chosen from the Catalog, the strip scrolls its glyph into view.

#### 4.1.3 Specimen instrument

The primary object (Metro §8, METRO §C.1): an opaque rectangular metal housing around a live GPU image, a readout band, a kernel well and two flanking pills. A rectangle, not Metro's round gauge, because blurs are judged on square pixel grids and a centred hero numeral would hide the pixels (METRO §C.1).

**Image window.** An `MTKView` whose drawable is exactly the window in device pixels (894 × 894 at scale 3; derived from `displayScale`, never hard-coded). The blur runs on a specimen texture of the same size. The present pass copies the output 1 : 1 (nearest) at zoom 1×. The window is drawn on demand (`isPaused = true`, `enableSetNeedsDisplay = true`) and also while a gesture or crown is active.

**Gestures on the window** (all begin-on-window touches are owned by the window; the page scrolls from anywhere else). Priority, highest first; the arbiter is a pure-Swift state machine with unit tests (ARCHITECTURE §5.10):

| # | Gesture | Recognised when | Effect | Accessible twin |
|---|---|---|---|---|
| 1 | **Handle drag** | one finger lands within 22 pt of a handle's centre (44-pt target): blur handles (centre ⊕, focus band lines, iris knob, glass-shape grip), the split divider, the compare divider | moves that handle; a drag that starts on a handle never pans | each handle is an adjustable element (±8 px per step, or ±10 % for dividers) with `Reset`; numeric Steppers in the Parameters panel |
| 2 | **Pinch** | two fingers | view zoom 1× → 8×, nearest-neighbour, about the pinch centre; snaps to 1·2·4·8 on release; caption engraves `ZOOM 4× · NEAREST`. The blur still runs at 1×: zoom magnifies the result only. | specimen custom actions `Zoom in` / `Zoom out`; specimen menu `Reset view` |
| 3 | **Long press** | one finger held 0.35 s within 8 pt | opens the **Metal loupe** (below); sliding moves it; lifting places the probe on the loupe's centre pixel; lifting outside the window cancels | probe adjustable action (±1 px; rotor `Probe step` 1 / 16 px; rotor `Probe axis` x / y) |
| 4 | **Drag** | one finger moves > 8 pt before 0.35 s | at 1×: **pans the specimen content** under the fixed window by whole specimen pixels (pan range ±256 px, rubber-banded; caption shows `PAN +36, −12 PX` while non-zero); at > 1×: pans the magnified view | specimen custom actions `Pan left/right/up/down 8 px`, `Reset view` |
| 5 | **Tap** | one finger, < 8 pt movement, lifted before 0.35 s | places the **probe** on the nearest output pixel centre (120 ms fade, none under Reduce Motion) | as 3 |

Two-finger double tap and painting are **not** gestures in v1 (JF M-1, M-15).

**Pan.** Panning moves the specimen canvas under the window (the canvas is the window plus a 256-px margin on every side, generated once per specimen, §11). The probe stays at its window pixel; the content moves beneath it. Pan is the shift-variance toy: under a Gaussian the image only moves; under `pyramid-blur` (plain mip chain) the lights snap to the 2^L grid (PSF centroid jumps by up to ±7.5 px at L = 4, CAT P7); under `dual-kawase` they shimmer; under `pixelate` the cells stay put while the content slides through them. Every pan change re-renders (reduced resolution for heavy blurs while moving, §4.1.6).

**Probe.** An instrument-amber crosshair (1-pt lines, 13-pt arms, 3-pt gap so the pixel itself is never covered), drawn on a SwiftUI overlay above the `MTKView` (foreground, never sampled by the blur). Coordinates are window pixels (0…N − 1). Each specimen has a default probe on its most informative feature (§11). One probe per specimen, restored with the state. The probe is the shared cursor of the app: the KERNEL and FREQ pills draw local content at the probe for LSV and adaptive blurs, the rail's PIXEL chip reads it, and the Layers and Trace screens follow it.

**Metal loupe.** Opaque, never glass (a glass loupe would add the system's refraction to the very pixels being inspected, METRO §F.5 item 2): a 112 × 112 pt square with a 1.4-pt metal rim showing 14 × 14 output texels at 8 pt per texel (nearest), floating 84 pt above the finger and clamped to stay inside the housing's image window and caption area (it never covers the readout band, the pills or the rail). Under it, 11-pt mono: the centre texel's linear value (3 significant digits, the one probe-value precision used everywhere) and its 8-bit encoded value with a LIVE badge, e.g. `0.0885 lin · 84/255 · ● LIVE` (0.0885 linear encodes to 83.93, so 84). The loupe reads only full-resolution Runs; during a preview it keeps its last reading marked `HELD`. The loupe is the pixel peeper that makes the box blur's reversed stripes and the binomial's dead-flat checkerboard visible to the eye.

**Handles** (only for blurs that declare them, §9): drawn as instrument-amber engraved rings or lines on the SwiftUI overlay; 44-pt hit targets; each with an adjustable action and `Centre on probe` / `Centre on image` actions. Zoom, spin, god rays, cat's-eye swirl: centre ⊕. Tilt-shift: two parallel focus lines (drag the band to move it, drag a line to change its width). Iris blur: ellipse centre + one radius knob. Liquid Glass exhibit: the glass shape's grip. Probe (amber crosshair) and centre (amber ring with a dot) differ in shape, not only in colour.

**Before/after split.** A view option, on by default at first launch: left of the divider the specimen INPUT, right of it the output. The divider is a 44 × 298 handle with a 1-pt hairline at the split; its accessible value is "Split at 50 percent", adjustable ±10 %. Dragging it fully right hides the input. Toggle: specimen menu `Show input beside output`. In Compare mode the split is replaced by the compare view (§8).

**Readout band.** Unit line (`SIGMA · PX`, `RADIUS · PX`, `STRENGTH · %`, `ANGLE · DEG`, `RANGE σr`, `RADIUS · PT` for SwiftUI), hero (the requested primary value at its declared display precision), serif-italic meaning from the blur's named bands (σ bands: *Sub-pixel* < 0.5 · *Anti-alias* 0.5–1.5 · *Softened* 1.5–4 · *Frosted* 4–12 · *Backdrop* 12–32 · *Fog* ≥ 32 px; these names are Blur2ool's own descriptive words, not a standard, and the Field guide says so; METRO §G.1 item 7), and the fixed status row.

**Status row** (one line, never grows; Metro §16 "Applying"). Its text is 11 pt mono at the default size and scales with `@ScaledMetric` up to 15 pt between default and AX1 (its height scales with it; at AX sizes it moves into the native text block, §4.1.10); when a line is too long it truncates its trailing qualifiers first, never a number or a badge word. It shows exactly one of, in priority order: `RENDERING… PASS 2/2` (requested ≠ acknowledged) · a σ-hold or switch notice (2 s) · a sampling or budget warning (`32 SAMPLES · CORNER GAP 4.08 PX · GHOSTS`, `2-D DIRECT ABOVE σ 8 · USING SEPARABLE`, `5 BLADES · NOT CENTRALLY SYMMETRIC → 2-D GATHER`, `TOO SLOW TO TIME · ≈ 700 ms MODELED`) · a lesson's look-for sentence · the coaching line (first launch) · the phase line (`74 FETCHES · 2 PASSES · LINEAR-SAMPLED`). Every number in it is badged data (`BadgedLine`, ARCHITECTURE §5.1), so VoiceOver speaks it with its badge. It is a readout only: no control ever lives in it (JF M-14).

**Kernel well face** (engraved `Canvas` under the fixed lens; numbers and words stay outside the glass; drawn from the **acknowledged** Run, like the ±3σ bracket): Gaussian rings at 1σ, 2σ, 3σ with tap dots on the axes sized by weight; box a square with four corner dots for SAT; disc a circle; polygonal bokeh the n-gon split into its rhombi by faint lines; zoom rays from a centre dot; spin concentric arcs; motion a hard-ended segment at the current angle; anisotropic Gaussian a soft-ended ellipse; Kawase the four diagonal taps of each pass with the current pass amber; bilateral, median and other adaptive filters a ring with a notch, with `DATA-DEPENDENT` engraved *outside* the well; system materials a dashed circle with `NOT EXPOSED` outside.

**Pills** (Metro §11, METRO §C.5; static 0.8-pt enclosures; interiors ease ≤ 150 ms on an *accepted* change and are otherwise still):

| | KERNEL (wave family) | FREQ (spectrum family) |
|---|---|---|
| Axis | tap offset, running **downward** from −extent to +extent (px) | spatial frequency, running **upward** from DC to Nyquist (0.5 c/px) |
| Quiet reference trace | the continuous kernel | the continuous response H(ν) |
| Primary trace | discrete taps as horizontal stems (normalised to the peak; the accessible value says "normalized") | the DFT of the discrete kernel, **signed**: H(ν) can go below zero; a hairline marks zero; negative lobes are shaded spectrum secondary `#F55CD6` **and** dashed |
| Depth trace | wave secondary `#3666FF`: the effective kernel after all passes (iterated box, Kawase, pyramids) | — |
| Marker | — | carrier `#FFBA57` tick at the −3 dB frequency (H = 1/√2) |
| LSV blurs | title line `LOCAL @ PROBE`: the local PSF profile along its axis at the probe | `LOCAL @ PROBE`: the local response along the PSF's axis |
| Adaptive blurs | `LOCAL @ PROBE` `● LIVE`: the weight row through the probe (the effective PSF there) | `T(ν, A 0.20)`: the amplitude-dependent transfer at the local contrast measured around the probe (NL §0) |
| Rank filters | the sorted window around the probe | engraved `N/A · RANK`, empty interior (honest empty state, Metro §16) |
| Tier S | our model's kernel (dashed) | `INFERRED — NOT EXPOSED` for the system, the model's curve dashed |
| Compare | A solid, B dashed | A solid, B dashed |

**Vocabulary fix (binding, §17 item 3):** the FREQ pill plots the *signed* frequency response H(ν), never "|H| with negative lobes". The word "MTF" means |H| only and appears only where a modulus is meant.

#### 4.1.4 Rail (the seven floors on the Bench)

Seven chips, one per floor, each the probe's answer on that floor for the current, acknowledged Run. Tapping a chip pushes Layers at that floor. Values never animate; they change only when an accepted value changes (D §2 rule 2).

| Chip | Label | Value (≤ 6 characters) | Badge glyph | Example (Gaussian σ 12 on Night City) |
|---|---|---|---|---|
| 1 | `SLIDE` | what his **home tool** would need typed for this blur, in that tool's unit (Settings › Home tool; default SwiftUI points). A value that only matches σ is prefixed `≈` (σ-matched, kernel shape differs); `UNVER.` when the tool's mapping is unknown; `—` when the tool does not offer this blur at all. Spoken forms are full: "about 4.4 points, sigma-matched; SwiftUI's kernel shape differs", "unverified", "not offered in SwiftUI". | REFERENCE, MEASURED or INFERRED per convention; any SwiftUI-derived value also carries `OFFSCREEN` in its spoken value and caption | `≈4.4` INFERRED (SwiftUI's macOS law σ ≈ 0.90·r·scale above ≈ 5 px, MEASURED offscreen on macOS, until this phone measures it; then MEASURED · OFFSCREEN, never plain MEASURED) |
| 2 | `API` | the parameter the API call carries, in px (σ for Gaussians; R, L, a… otherwise) | COMPUTED | `12.0` |
| 3 | `MATH` | the operator's short symbol declared in the catalog (`G`, `rect`, `tent`, `disc`, `hex`, `exp`, `ray`, `arc`, `rank`, `w·f`, `PDE`, `FFT`, `sys`) | COMPUTED (REFERENCE for system entries) | `G` |
| 4 | `KERNL` | taps per axis (separable), taps per pixel (2-D), samples (gathers), window (rank), `LIVE` count for adaptive | COMPUTED or LIVE | `73` |
| 5 | `ALGO` | passes (`2×`), iterations (`32×`), levels (`L4`) | COMPUTED | `2×` |
| 6 | `GPU` | MEASURED median GPU ms of the last settled full-resolution Run; `–.––` until it exists; `SIM` in the Simulator | MEASURED | `–.––` → `0.61` (illustrative) |
| 7 | `PIXEL` | the probe's output value, linear light, 3 significant digits (the same precision as the loupe, the periscope line and floor 7); from the newest **full-resolution** Run only, marked `HELD` during a preview | LIVE | `0.0885` (illustrative) |

- **Units.** Chips print no units (six characters are not enough for honest ones); the unit is in the chip's spoken value, in the floor's header and in the rulers' `SCALE 1 PX = 0.33 PT` engraving.
- Badges on chips are **glyph only** (11 pt, top-trailing; INFERRED chips also get a dashed border): ● LIVE, stopwatch MEASURED, = COMPUTED, ≈ MODELED, book REFERENCE, ? with dashed ring INFERRED. This is the app's single glyph-only badge use; the legend says so, and VoiceOver speaks the word ("Floor 6, GPU, 0.61 milliseconds, measured on this iPhone").
- **Shift invariance lesson:** for LSI blurs, moving the probe changes only GPU and PIXEL (and GPU only after a new timing). For LSV and adaptive blurs MATH and KERNEL also change, because their PSF depends on where you are.
- **Compare mode:** every chip shows `=` or `≠` (or `≈` when the floors differ only in the last bits). The **first ≠** is instrument amber with a ▶ marker and the words in its accessibility label ("Floor 3, Math, first difference: rectangle versus bell"). SLIDE reads `≠` with the caption `NOT IN SWIFTUI` when either blur is absent from the home tool; that floor is then skipped when naming the first difference (§8.4).
- Selected-floor feedback: when he returns from Layers, the chip of the floor he left is focused (cyan fill 0.08 + border 0.35) for one second.

#### 4.1.5 Deck (98-pt control slot)

The deck holds exactly one arrangement declared by the blur in `BlurCore` (never inferred from live values, METRO §F.1 item 3). Arrangements A–E and their per-blur assignment are in §9. In this wireframe (Gaussian, arrangement A): FINE crown (cyan, 8° detent = 0.1 px, caption `FINE` / `±0.1 PX`) and SEMANTIC crown (amber, 20° detent = one octave stop 0.5 · 1 · 2 · 4 · 8 · 16 · 32 · 64 px, caption `SIGMA · Backdrop` / `Frosted ⇆ Fog`). Crown rules (Metro §10, METRO §C.4): at most one step per update, at most 20 events/s, 18 % reversal hysteresis, 7-pt centre exclusion, first touch never changes the value, haptics fine up 0.78/0.95 · fine down 0.82/0.20 · semantic up 1.00/0.60 · semantic down 1.00/0.05. Turning past a range end emits nothing (Metro contract A.17). Crowns live outside every `TimelineView`.

#### 4.1.6 Rendering, preview and timing policy (what he sees while turning)

- **Every accepted change renders.** The image updates in the next frame; the hero shows the requested value instantly; the status row says `RENDERING…` only if the frame is not yet back. Pipelines compile off the main actor; while a new variant, edge mode or traced build is being prepared, the previous image stays on screen with `RENDERING…` (never a spinner, never a frozen crown).
- **Reduced-resolution preview while moving** for heavy blurs (cost class O(r²), iterative, search or FFT) and for any configuration above the preview budget (2·10⁸ texture fetches per frame, MODELED ≈ 13 ms on the A17 Pro, UNVERIFIED until This phone measures it): while a crown, handle or pan is active, render at half resolution (447 × 447) or, when even that exceeds the budget, quarter resolution (223 × 223), upscaled nearest, engraved `PREVIEW ½` / `PREVIEW ¼`; render full resolution 300 ms after the last change (JF G-4, GPU §4.2). **How a preview is made** (one rule for every blur, ARCHITECTURE §5.5): the input is a 2 × 2 mean of the window (itself a tiny box blur, σ 0.5 full-resolution px, stated in the Field guide); pixel-unit parameters (σ, r, R, L, offsets, handle positions) are scaled by ½ (diffusion time t by ¼); counts (samples, passes, taps) stay; integers become max(1, round(x/2)); the probe maps to ⌊p/2⌋. Rank and selection filters (median, Kuwahara, morphology) have **no** preview: they render at full resolution and show `RENDERING…`, because halving changes their character. A blur may opt out for the same reason (Kawase sequences, pixelate cells), and says so in its Field guide page. Settings › Preview can force full resolution.
- **Previews publish the image only.** The PIXEL chip, loupe, pills, telemetry, periscope line and Trace read the newest **full-resolution** Run; while a preview is on screen they keep their last full values, marked `HELD`. Previews are never timed, traced or parity-checked.
- **Budgets.** Above 2·10⁹ fetches per frame a configuration switches to a cheaper variant with its reason in the status row (disc gather → row-span SAT; 2-D Gaussian → separable; heat equation → exact Gaussian above 500 iterations; non-local means patch/search combinations above budget disabled), or the parameter's range ends there with the reason in the Parameters panel. Full renders whose MODELED time exceeds 50 ms are split into horizontal bands, one command buffer each, so the system compositor keeps getting GPU time.
- **Timing only after settle, budgeted and cancellable.** 300 ms after the last accepted change, at full resolution: 3 warm-up command buffers, then up to 15 timed ones, stopping early once at least 3 are taken and their summed GPU time reaches 1 s (`n` is always shown). Any touch cancels timing between command buffers. Timed command buffers contain the **blur passes only**; the window copy and the colour and alpha passes are timed separately and shown as `OVERHEAD` in Layers › GPU › Silicon, so changing the colour space does not change the blur's own time. Above the full budget timing is skipped: `TOO SLOW TO TIME · ≈ 700 ms MODELED`. The median and interquartile range go into the Run; the GPU chip and telemetry update. Never per detent (JF M-4). In the Simulator no timing is recorded (`nil`) and the GPU chip reads `SIM`.
- **Parity after timing.** The 128 × 128 parity check runs after timing completes, at background priority, and is cancelled by the next change or touch.
- **Generation tokens:** only the newest request may publish; a stale render never overwrites a newer one (METRO §F.2 item 3).
- **Probe readback:** one texel per acknowledged full-resolution frame, encoded into the render's own command buffer (no extra round trip), coalesced to the newest generation; never `getBytes` on a mip level of a shared texture (GPU §2.7 item 7).

#### 4.1.7 Floating group

Three controls, no backing strip, native glass (Metro §12; AssemblerToy build-6 lesson, METRO §F.1 item 1):

| Button | Frame | Normal | In Compare | Running state |
|---|---|---|---|---|
| Left | 62 × 58 | `Compare` (`rectangle.split.2x1`): enters Compare with B = the blur he just left (σ-matched), view = last used | `Done` | — |
| Primary | flexible, ≥ 58, `.glassProminent` | `Descend from (447, 455)` (the probe's coordinates, monospaced digits) | `Descend both from (x, y)` | cyan idle; amber while a guided descent auto-steps or a calibration sweep runs |
| Right | 54 × 58 | `Lessons` (`graduationcap`): Catalog sheet on the Lessons tab | `Swap` (A ⇄ B) | — |

At accessibility sizes the group is icon-only with full spoken labels (METRO §F.1 item 10). The specimen window is never under the group in the first viewport (30-pt clearance at default size); scrolled content passes under it.

#### 4.1.8 Below the fold (content y after scrolling; first viewport ends at the deck)

```
 810 ┌──────────────────────────────────────────────────────────────┐
     │  σ EFF             │  GPU (BLUR PASSES)   │  PARITY          │ telemetry row 64: InstrumentMetricReadout ×3
     │  11.86 px          │  0.61 ms             │  ≤ 1 LSB         │ label caption2 mono · value title3 mono + unit
     │  = COMPUTED        │  ⏱ MEASURED · n 15   │  ⏱ MEASURED      │ HonestyBadge (word) · dividers 1 × 30 white 0.10
 874 ├──────────────────────────────────────────────────────────────┤
 886 │ ╭ PARAMETERS · GAUSSIAN BLUR ─────────────────────────────╮  │ InstrumentContentPanel (r 22, fill 0.85, pad 16)
     │ │ [ SIGMA                −    12.0 px    +  ]             │  │ DecimalParameterStepper, Int tenths, ≤ 380 × 48
     │ │ TRUNCATION      [ 2 · 2.5 · [3] · 4 ]  × σ              │  │ Picker(.segmented) 32
     │ │ DISCRETISATION  [ [Sampled] · Integrated · Lindeberg ]  │  │ Picker(.segmented) 32
     │ │ ALGORITHM       [ Linear-sampled ▾ ]                    │  │ Menu 44 (2-D · Separable · Linear-sampled · IIR · Compute tile)
     │ │ ── EVERY BLUR ───────────────────────────────────────── │  │ eyebrow 11 pt mono
     │ │ COLOUR SPACE    [ [Linear light] · sRGB-encoded ]       │  │
     │ │ EDGES           [ [Clamp] · Mirror · Wrap · Zero ] ⋯    │  │ ⋯ = Menu with Renormalise (FIR blurs only)
     │ │ ALPHA           [ [Premultiplied] · Straight ]          │  │
     │ │ PRECISION       [ [fp32 accumulate] · fp16 accumulate ] │  │
     │ │ PREVIEW         [ [Reduced while moving] · Always full ]│  │
     │ ╰─────────────────────────────────────────────────────────╯  │
≈1290│ ╭ WHAT MAKES IT UNIQUE ──────────────────── [ TRUE BLUR ] ╮  │ compact fingerprint (§7.3), ≈ 236 tall
     │ │ "The only blur that is both round and separable; its    │  │
     │ │  continuous response fades every detail smoothly and    │  │
     │ │  never inverts phase."                                  │  │
     │ │ [ PSF ][ STAR ][ EDGE ][  H  ]   AT σ 4 PX · 88 × 88    │  │
     │ │ UNIQUE  kurtosis on axis = at 45° = 0, while separable  │  │
     │ │                                          Full card ›    │  │
≈1526│ ╰─────────────────────────────────────────────────────────╯  │
     │                 bottom reserve = measured group height + 28  │
     └──────────────────────────────────────────────────────────────┘
```

- **Telemetry row** (JF G-12, moved one scroll down): `σ EFF` (2 dp, COMPUTED second moment of the discrete kernel; MEASURED · OFFSCREEN for Tier S fits) · `GPU (BLUR PASSES)` (2 dp, median of up to 15 after 3 warm-ups, blur passes only, refreshed only by settled Runs; `n`, IQR and the separately timed overhead in its accessibility value and in Layers › GPU › Silicon; `< 0.05 ms` printed as such; `TOO SLOW TO TIME` above budget; Simulator: `— NO GPU TIMING IN SIMULATOR`) · `PARITY` (max |GPU − CPU| on a 128 × 128 crop around the probe in 8-bit steps, MEASURED once per settled Run after timing; `≤ 1 LSB`, `3 LSB`, with fp16 ulps in the accessibility value; for blurs that use hardware bilinear filtering it reads `SUB-TEXEL RULE NOT YET MEASURED` until This phone's one-time background probe has run). Live values are observed only by these leaf views (Toothpaste lesson, METRO §F.5 item 4).
- **Parameters panel** (JF G-11, M-13): the primary parameter's native twin first (`DecimalParameterStepper` for decimals, `InstrumentParameterStepper` for integers), then the blur's secondary parameters and its algorithm (variant) picker (§9), then the **EVERY BLUR** group of the five "silent parameters" that every blur shares (colour space, edges, alpha, precision, preview; §9.3). Disabled options stay visible with the reason as their accessibility hint and a one-line caption (e.g. `2-D direct: disabled above σ 8 · 2,401 taps per pixel`).
- **Compact fingerprint** (§7.3) with `Full card ›` opening the Fingerprint sheet.
- Nothing else lives below the fold: plots, pass tiles and cost charts live on the floors (JD M6, M15).

#### 4.1.9 Bench variants (only the regions that differ)

**(a) Space-variant blur with a centre handle: `radial-zoom-blur` on the impulse grid.**

```
  186  │  │ RADIAL ZOOM · IMPULSE GRID                LIVE · METAL  │   │
  210  │  │ ┌────────────────────────────────────────────────┐      │   │
       │  │ │  ╲   ╲    │    ╱   ╱                           │      │   │ every dot is a ray pointing at the centre
       │  │ │ ──── ─  ⊕ ─ ────           ✛ probe (747, 447)   │      │   │ ⊕ centre handle (44-pt target, owns its drag)
       │  │ │  ╱   ╱    │    ╲   ╲                           │      │   │ pills: LOCAL @ PROBE
  516  │  │ STRENGTH · %                          ╭──────────╮    │   │
       │  │ 20.0                                  │  rays    │    │   │ meaning bands: Drift < 5 · Rush 5–25 · Warp > 25
       │  │ Rush                                  ╰──────────╯    │   │ (Blur2ool's own words)
       │  │ 32 SAMPLES · CORNER GAP 4.08 PX · GHOSTS               │   │ sampling warning, COMPUTED (§5.4 fixture)
  700  │        FINE  ±0.5 %              [ SAMPLES   −  32  + ]     │ deck D: FINE crown + InstrumentParameterStepper 48 (≤ 170 wide)
       │   (−)( ◉ )(+)                    [ In · Centred · Out ]     │ + Picker(.segmented) 32
```

**(b) Integer-magnitude blur: `box-blur`** (deck D): FINE crown with 1-px detents for RADIUS r (status row `w 41 · σ 11.83 px`), right column `ALGORITHM [ Separable · Sliding sum · SAT ]` segmented. **(c) Sequence-defined blur: `kawase-blur`** (deck E): a row of event tiles, one per pass, showing each pass's offset (`0 1 2 2 3`; tap a tile to cycle its offset 0–7) above a `PASSES` Stepper; status `σ 5.34 px · 20 FETCHES`. **(d) Named primary: `median`** (deck E): segmented `3×3 · 5×5` above a `NOISE %` Stepper. **(e) Two continuous parameters: `bilateral`** (deck C, as §9.4): FINE crown `RANGE σr` (cyan; the hero, log-spaced detents at 0.01 · 0.02 · 0.05 · 0.10 · 0.20 · 0.50 · 1.00) and a second crown `SPACE σs` (amber, 0.1-px detents, 0.5–8.0).

**(f) Tier S: `swiftui-layer-blur`.** The window shows a **real SwiftUI view** (an `Image` of the specimen canvas, decoded to extended linear sRGB, scale 3) with Apple's `.blur(radius:)` applied, on the left of a compare wipe; on the right, our Gaussian (or box³) model at the fitted σ. Captions: left `SYSTEM · ON SCREEN`, right `MODELED · METAL` (each fits its half of the 298-pt row); the qualifier `NOT READ BACK` is the first line of the Parameters panel and part of the image's VoiceOver value, so no provenance is ever truncated. The hero is `RADIUS · PT` with the SEMANTIC stop at the regime switch (hollow INFERRED marker at 1.7 pt until this phone measures it; then the measured value, MEASURED). Rail values refer to our model (MODELED) except SLIDE (the typed points, no badge: it is the input), API (REFERENCE + MEASURED · OFFSCREEN law) and PIXEL: the app renders the **same specimen view** through `ImageRenderer` and reads the probe texel (MEASURED · OFFSCREEN); when that is not possible the chip reads `—` and speaks why ("not capturable offscreen"). The value never comes from a calibration fit of a different image. The Parameters panel has `Measure on this phone` (opens Calibrate). The system half cannot be read back on screen; every number about it comes from offscreen `ImageRenderer` fits and says so (CAL §5.1, §8).

**(g) Liquid Glass exhibit: `liquid-glass` and `apple-uiblureffect`.** The window switches from the `MTKView` to a **SwiftUI-drawn** copy of the *material backdrop* specimen (stripes, text, white/black split) so the system glass samples known content (METRO §C.2). A native glass shape (rounded rectangle 180 × 120 pt; `.regular` or `.clear` for glass; `ultraThin…ultraThick` for materials) floats over it at full opacity, draggable by its own 44-pt grip. Wipe: left = native (`INFERRED · NATIVE GLASS`), right = our Metal reconstruction, engraved `MODELED · STRUCTURE INFERRED`: its structure (downsample → Gaussian → colour stage, plus an SDF refraction band for glass; CAT rows 47–48) is itself inferred from QuartzCore kernel names, not documented. Pills: `INFERRED — NOT EXPOSED` for the native side, dashed model curves for the reconstruction. This is the only place glass sits over a specimen (JD M9).

#### 4.1.10 Accessibility sizes and other widths

- **AX1–AX5** (METRO §D.6): the root stays a `ScrollView` and the image keeps all its gestures (one gesture regime, JF M-2). Subtitle and ruler numerals hidden (ticks stay); the caption row's **provenance is never hidden**: it becomes the first line of a native text block below the housing (`LIVE · METAL`, `SYSTEM · ON SCREEN`, `MODELED · METAL`, `INFERRED · NATIVE GLASS`, `PREVIEW ½`), followed by the readout (label, value + unit, meaning, status at full Dynamic Type), and it stays the first phrase of the image's VoiceOver value; only the decorative split labels and specimen name are dropped; the housing holds the window with the kernel well centred under it; crowns stack vertically; the rail becomes a vertical list of seven 44-pt rows ("Floor 4, Kernel, 73 taps, computed"); telemetry becomes three stacked rows; the floating group goes icon-only. Nothing shrinks below its Dynamic Type size; decorative engravings disappear first (METRO §F.2 item 6).
- **Other widths** (METRO §D.7, COMPUTED from the cluster formula): 402 pt → D 294, window 270 pt = 810 px; 393 pt → 261 pt = 783 px; 375 pt → 243 pt = 729 px. Specimens are generated at the window's pixel size; probes are defined by feature, not coordinate (§11). The rail's chip width is (available − 24)/7. Portrait only.
- **Text fit.** Every specified string (captions, engravings, status templates, LabeledValue rows, floating-group labels) is checked by a phone AppTest at the default and xxxLarge sizes and at 430, 393 and 375 pt widths. Rows that hold more than one number use two-line `LabeledValues` with one badge per number; badge words are never abbreviated (`COMPUTED`, not `COMP.`), and a row that does not fit wraps rather than shortening a badge.

### 4.2 Compare mode (M1), in place on the Bench: Gaussian (A) vs box (B) at held σ, Wipe

```
  130  │ ( AXIS ▾ Operator )  ( B ▾ Box blur · r 20 · σ held ) ( VIEW ▾ Wipe ) │ compare bar replaces the blur strip: three Menus, 44 tall
  186  │K │ B · BOX r 20 (σ 11.83)       A · GAUSSIAN σ 12.0      │ F │ engravings above each half, never over pixels
  210  │E │ ┌──────────────────────┬┬──────────────────────┐       │ R │
       │R │ │      B (left)        ◀▶       A (right)      │       │ E │ compare divider 44 × 298, owns its touches,
       │N │ │                      ││                      │       │ Q │ "Split at 50 percent", ±10 %
       │E │ └──────────────────────┴┴──────────────────────┘       │   │ pills: A solid, B dashed
  516  │  │ SIGMA · PX (A)                        ╭──────────╮    │   │ hero drives A; DRIVE [A · B] in the B menu and the
       │  │ 12.0                                  │ well: A  │    │   │ Parameters panel switches the crowns ("DRIVING B")
       │  │ Backdrop                              ╰──────────╯    │   │
       │  │ MIN H  A −0.0012 · B −0.217 · PARTS WAYS AT MATH       │   │ status row: the distinguishing number (COMPUTED from the kernels each slot runs)
  640  │ ┌SLIDE┐ ┌ API ┐ ┌▶MATH┐ ┌KERNL┐ ┌ALGO ┐ ┌ GPU ┐ ┌PIXEL┐      │ rail: = / ≠ per floor; first ≠ amber with ▶
       │ │  ≠  │ │  =  │ │  ≠  │ │  ≠  │ │  ≠  │ │  ≠  │ │  ≠  │      │ SLIDE ≠ · NOT IN SWIFTUI (no box blur in SwiftUI; skipped for PARTS WAYS)
  700  │        FINE                          SIGMA · Backdrop        │ crowns drive A (σ-hold keeps B matched when on)
  828  │  ( Done )             ( ⤓ Descend both )             ( Swap ) │
```

Below the fold in Compare, the telemetry row becomes `ΔGPU (A − B)` MEASURED · an axis-specific column (`ΔFETCHES/PX` COMPUTED for Operator and Implementation, `CPU REF TIME` for parity, `Δσ EFF` for Precision) · `MAX |A−B|` in 8-bit steps LIVE with its position (tap → moves the probe there). `MIN H` in Compare is always computed from the discrete kernel each slot actually runs (a Gaussian truncated at 3σ has min H −0.0012 at σ 12, so it is never shown as "> 0"). The full Compare behaviour is §8.

### 4.3 Layers (S2), pushed: Gaussian, floor 4 of 7 (Kernel)

```
y   59 ├──────────────────────────────────────────────────────────────┤
   59  │ ‹ Blur2ool        GAUSSIAN · FLOOR 4 OF 7                    │ inline navigation title
  103  │ ┌──────────────┐ SIGMA · PX                       (−) (+)    │ periscope 130 tall, pinned: live mini-specimen 120 × 120 pt
       │ │ live crop    │ 12.0       Backdrop                         │ (same output texture, cropped around the probe, nearest)
       │ │ around probe │ PROBE (447, 455)                            │ hero 34 pt; ± glass buttons 44 change the primary parameter
       │ │              │ IN 0.0200 ● · OUT 0.0885 lin ●              │ (two lines; one badge per number)
  233  │ └──────────────┘                                            │
  245  │ ╭─────────────────────────────────────────────────────╮┌──┐│ floor section: InstrumentContentPanel, x 12–418 (406)
       │ │ FLOOR 4 · KERNEL                       = COMPUTED   ││ 1││ eyebrow 11 pt mono + dominant badges
       │ │ What finite numbers stand in for the curve?         ││ 2││ question: body semibold
       │ │ GOVERNING RULE                                      ││ 3││ floor rail overlaid inside the column, x 374–418 (44 wide), 7 stops 44 tall;
       │ │ g[n] = exp(−n²/2σ²) / Σ ,  |n| ≤ ⌈3σ⌉ = 36             │ │4│ │ cyan = current, amber dot = probe has passed
       │ │ ┌──────────── plot inset 374 × 140 ─────────────┐      │ │5│ │
       │ │ │ 73 stems over the continuous curve (quiet)    │      │ │6│ │ Swift Charts; stems with explicit 2-pt width
       │ │ └───────────────────────────────────────────────┘      │ │7│ │
       │ │ CENTRE WEIGHT     0.03332                  = COMPUTED  │ └┘ │ at most six badged numbers
       │ │ TAPS              73 per axis              = COMPUTED  │    │
       │ │ MASS CUT          0.235 % per axis         = COMPUTED  │    │ discrete; 2-D 0.47 %; continuous 0.27 % in details
       │ │ σ OF KERNEL       11.86 px                 = COMPUTED  │    │
       │ │ MIN H (ripple)    −0.0012                  = COMPUTED  │    │
       │ │ ERROR VS SAMPLED  1.1·10⁻⁴ per tap         ≈ MODELED   │    │ fixed slot: approximation error (definition in details)
       │ │ ▸ All kernel details (weights, pair table, discretisation) │ │ DisclosureGroup: data table, picker, aside
       │ │ IN THIS APP  BlurCore computes 73 weights (Double). The │    │ honesty line, generated per variant
       │ │ GPU receives 19 pair weights and offsets (37 fetches),  │    │
       │ │ and the hardware rounds each pair's fraction to 8 bits. │    │
       │ ╰───────────────────────────────────────────────────────╯    │
       │          scroll ↑ floor 5 · Algorithm    scroll ↓ floor 3    │ one vertical ScrollView, one section per floor
  898  └──────────────────────────────────────────────────────────────┘
```

- One plain vertical `ScrollView` (no paging), one section per floor, each a content panel with fixed slot heights at the current Dynamic Type size; `.scrollPosition(id:)` with `.scrollTargetLayout()` snaps a section's top under the periscope when a scroll ends near it, and the floor rail jumps to a section. Expanding `All … details` grows its own section in place, and at accessibility sizes sections simply grow: there is no nested same-axis scroll and nothing is unreachable (review fix P-44). Page content is generated from `BlurCore` data (§5); hand-written text is limited to the catalog's signature sentence, one governing rule per floor template and one closing lesson per Tier 1 blur (JF G-10).
- **The `IN THIS APP` line is generated per variant** (review fix P-37). For integer-tap variants: "Weights come from BlurCore (Double) and are the exact numbers the GPU receives." For merged-tap (linear-sampled, Kawase, gathers) variants: the GPU receives the pair table (shown in details), and the hardware rounds each fraction to its sub-texel precision, so the effective taps differ from the stems by a MODELED amount (Gaussian σ 12: at most 1.1·10⁻⁴ per tap, 0.33 % of the centre weight, MODELED for 8-bit round-to-nearest).
- **Periscope** (JD G8): a second small `MTKView` that presents a crop of the *same* output texture around the probe (no second render path for the blur itself). Its ± buttons change the primary parameter by one fine step, so he can stand on the GPU floor and watch dispatch and fetch counts move. When a pass tile is selected on the Algorithm floor, the periscope shows that pass's intermediate texture and engraves `PASS 1 OF 2`.
- **Floor rail** overlaid inside the content column at its right edge (x 374–418, 44 pt wide, 44-pt stops), so the 12-pt screen inset holds and every stop is a 44 × 44 target: tap a stop to jump; VoiceOver rotor `Floors`.
- **GPU floor (6) has two tabs**, `Shader · Silicon` (`Picker(.segmented)` at the top of the page; E's Shader/Silicon split, JD G8):

```
       │ │ FLOOR 6 · GPU          [ Shader · [Silicon] ]   ⏱ MEASURED │
       │ │ Which thread computed it, and what did it cost?          │
       │ │ ┌─ copy of the output, 200 pt ─┐ OVERLAY                   │ overlay drawn on a COPY, never on the specimen
       │ │ │▒▒▒░░░▒▒▒░░░▒▒┏━━┓▒▒░░░▒▒▒ │ ( ) threadgroups           │
       │ │ │░░░▒▒▒░░░▒▒▒░░┃✛ ┃░░▒▒▒░░░ │ (•) the probe's group+apron│
       │ │ └──────────────────────────────┘ ( ) 32 × 32 tiles (REF max)│
       │ │ PASS TIMELINE   H ▕████░░▏ 0.31 ms   V ▕░░░████▏ 0.30 ms    │ MEASURED bars; ░ MODELED ghost bars
       │ │ OVERHEAD        window copy + colour passes 0.04 ms ⏱      │ timed separately
       │ │ BYTES           25.6 MB                       ≈ MODELED     │ two LabeledValues rows, one badge each
       │ │ FLOOR           0.50 ms                       ≈ MODELED     │
       │ │                 at 51.2 GB/s · UNVERIFIED PEAK               │ caption line
       │ │ ▸ All silicon details (dispatch per pass, compression A/B, │
       │ │   roofline, counter sampling, INFERRED lane)               │
```

  The Shader tab shows the exact `.metal` source text that was compiled into the shipped library for the running variant (syntax-coloured, monospaced, horizontally scrollable), its SHA-256 (matching the Run's provenance), the compile options (math mode), the function name and, for traced builds, the `TRACE_PROBE` lines highlighted. Tapping a line shows a one-line explanation from the catalog's annotations ("cooperative load of the apron", "barrier", "bilinear pair").

### 4.4 Trace (S3), pushed: one pixel through a Gaussian (step edges, probe (446, 300), σ 4.0)

```
y   59 │ ‹ Blur2ool         Pixel (446, 300)                 Jump ▾  │ inline title; Jump menu (§6.4)
  103  │ ╭──────────────────────────── context card 406 × 168 ─────╮ │ pinned (does not scroll)
       │ │ ┌ 9×9 texels, 112×112 ┐  GAUSSIAN σ 4.0 · STEP EDGES · LIN │ │ eyebrow 11 pt mono
       │ │ │ 0 0 0 0 ▣ 1 1 1 1  │  IN    0.000              ● LIVE  │ │ 9 × 9 input texels on a COPY; probe ▣ outlined amber;
       │ │ │ 0 0 0 0 ▣ 1 1 1 1  │  Σ     0.399  after fetch 7 of 13  │ │ weights as amber bars under each texel
       │ │ │ ...  weights ▁▃▅█▅▃▁│  OUT   —      (pass V not run)     │ │
       │ │ └─────────────────────┘  Completed  fetch 7 of 13, pass H  │ │ instrument amber
       │ │                          Next       fetch 8 at +7.38 px    │ │ action cyan
       │ │  Step 10 / 15 · fragment (446, 300) · pass 1 of 2          │ │ phase metadata 11 pt mono
  271  │ ╰──────────────────────────────────────────────────────────╯ │
  283  │ [1 SLIDE ][2 API   ][3 MATH  ][4 KERNEL]                     │ floor selector: InstrumentEventTiles, 4 + 3 tiles 95.5 × 54, gap 8
       │ [5 ALGO  ][▐6 GPU ▌][7 PIXEL ]                               │ done = amber caption; current = cyan fill 0.08 + border 0.35
  407  │ ╭ FLOOR 6 · GPU ───────────────────── ● LIVE  ⏱ MEASURED ╮   │ selected floor panel (scrolls)
       │ │ One fragment, 13 bilinear fetches per pass.             │   │
       │ │ FETCHES  7 / 13                        PASS H · 1 / 2   │   │
       │ │ ┌ texel strip 374 × 64: texels 434…458, step after 446 ┐│   │ fetch positions ◆ done (amber), ◇ next (cyan)
       │ │ └───────────────────────────────────────────────────────┘│   │
       │ │ fetch 7: sample(uv − 5.4149 texel) → w 0.07818 · v 0.000 │   │ the GPU's own record (TRACE_PROBE)
       │ │ GOVERNING RULE  one bilinear fetch at k + b/(a+b) blends │   │
       │ │                 taps k and k+1                            │   │
       │ │ ▸ All GPU details (source · dispatch · bytes · timing)   │   │
  836  │ ╰─────────────────────────────────────────────────────────╯   │
  840  │  ( ‹ Back )   ( ↺ )   ( ⇥  Next fetch                     )   │ safeAreaInset(.bottom) 58 over an opaque canvas strip:
  898  │                                                              │ Back 96 · Restart 62 · Next flexible .glassProminent
```

Step grammar, data honesty and per-class behaviour are §6.

### 4.5 Catalog (S4), sheet `.large`, four tabs

`Picker(.tabs)` (iOS 27; segmented look, tab semantics for VoiceOver, SDK §12): **Blurs · Fingerprints · Divergence · Lessons**. Native `List` + `.searchable` (`Search 55 blurs, 7 contrasts, 32 variants`). One `Done`.

**Blurs tab.**

```
       │  Catalog                                              Done   │ largeTitle rounded semibold
       │  [ Blurs · Fingerprints · Divergence · Lessons ]              │ Picker(.tabs)
       │  ⌕ Search 55 blurs, 7 contrasts, 32 variants                  │
       │  F1 · BOX, TENT & RUNNING SUMS · 4        What is the simplest average…? │ eyebrow + count + the family's question
       │ ┌──┐ Box blur                                          ✓     │ row ≥ 72, three lines: 40×40 glyph · name body semibold
       │ │□ │ The honest average: flat and square, and it turns…   │ line 2: signature caption mono (one line, truncates)
       │ └──┘ [O(1)] [TIER 1 · LIVE] [GPU · CPU · TRACE]          │ line 3: cost, tier and capability chips (wrap to a 4th line at AX sizes)
       │      ▸ variants: SAT · sliding window                    │ variants as a disclosure
       │  …                                                              │
       │  F8 · EDGE-PRESERVING & NONLINEAR · 10                          │
       │ ┌──┐ Mean-shift filtering                  [ITER] TIER 3 · PLOTS │ Tier 3 rows open an atlas page (§10.4),
       │ │◈ │ Every pixel walks uphill…              MODEL · CPU PLOT      │ never the Bench
```

Tier chips: `TIER 1 · LIVE` (GPU, CPU reference, all floors, full trace), `TIER 2 · LIVE` (GPU, CPU reference, lighter floors, one-stage trace), `TIER 3 · PLOTS` (CPU math and plots on a 128 × 128 crop), `SYSTEM · MEASURED` (Apple's implementation live and fitted, our model beside it). Selected row: cyan ✓ + `isSelected`. Tapping a live row selects it (σ-held) and dismisses; tapping a Tier 3 row pushes its atlas page.

**Fingerprints tab** (D W5, JD G14): at default sizes a `Grid` with fixed column widths (at AX sizes, one card per row with the properties as a vertical list of label–value pairs; the sort and selection work the same): `LSI · SEP · ISO · H ≥ 0 (AS RUN) · EDGE · COST · PSF · H` (PSF and H as two 28 × 28 glyphs; ● yes, ○ no, ◐ approx/skew, `LSV`/`NL`/`E` words; shape and text, never colour alone). Sort: `Family · Cost · Excess kurtosis · Divergence from Gaussian`. Every row is spoken as words ("Box blur. Linear shift-invariant: yes. Separable: yes. Isotropic: no. Response never negative: no, inverts contrast down to minus 0.217…"). Tap a row → its Fingerprint card; select two rows (checkmarks) → `Open in Compare`.

**Divergence tab** (D W6, JD G13): two chips `A [ … ⌄ ]` and `B [ … ⌄ ]` (197 × 44 each), then seven rows (at least 44 tall, no fixed height), one per floor: line 1 floor name and verdict (`same` in secondary ink / `PARTS WAYS` amber with ▶, first difference only / `differs` / `≈ same`); line 2 the reason from `BlurCore` (§8.4), wrapping as needed. Button `Open in Compare`.

**Lessons tab** (D W8, JD G17): `GUIDED DESCENTS · 4` then `PAIRS THAT TEACH · 30` (§8.5). Each row (≥ 72): title, set-up line, and the "Look for" number with its badge. Tapping a pair sets specimen, A, B, axis, view, σ and probe, dismisses, and writes the look-for sentence into the status row until any control changes. Tapping a guided descent sets the state and pushes the Trace.

### 4.6 Fingerprint (S5)

The card layout is §7. Presented `.medium` (top half: header, strip, six rows) and `.large` (everything). `Show me` and neighbour taps dismiss the sheet and set the Bench.

### 4.7 Field guide (S6), sheet `.large`, four tabs

`NavigationStack` + `Picker(.tabs)` **Guide · This phone · Runs · Settings** + `Done` (METRO §C.11).

- **Guide**: the current blur's field-guide page in content panels: signature; definition (equation, callout mono); every figure with its badge; where it is used (REFERENCE rows); sources in full (paper titles and years, URLs, spec section names); the blur's UNVERIFIED list in words; `HONESTY LABELS ›` (the legend, §12.4); `THE LENS ON THIS INSTRUMENT ›` (§12.5).
- **This phone** (D W10, E §3.8, JD G20): device row (`iPhone 15 Pro Max · A17 Pro · iOS 27.x`); a limits table with the MEASURED runtime value beside the Feature Set Tables value (REFERENCE): GPU family, threadgroup memory, threads per threadgroup, SIMD width, read-write texture tier, 32-bit float filtering, counter sampling points; a probes table with a `Measure` button per row and `Measure everything · ≈ 20 s` (bilinear sub-texel bits, `generateMipmaps` impulse, blit and compute copy bandwidth, compression A/B, FMA throughput, traced-vs-untraced bit equality); SwiftUI calibration status and `Open Calibrate ›`; thermal state and Low Power Mode. Measurements run only on demand (JF G-17), are cached with OS build and date, and upgrade badges in place for the session with both values visible (`32,768 B MEASURED · 32 KB REFERENCE`).
- **Runs** (E §4.2, JD G24): the Run log, newest first: blur, variant, parameters, median ms with n and IQR, parity, thermal state, OS build. Swipe to delete. `Export JSON` through `ShareLink`. Simulator runs are marked `SIMULATOR · NO TIMING`.
- **Settings** (`Form`): Home tool (SwiftUI pt · CSS px · Figma · Sketch · Photoshop · Core Image · Android · Flutter · GIMP · OpenCV) · MATCH σ on switch (on) · defaults for the five silent parameters · Haptics (on) · Display: `SDR (clip at white)` / `HDR highlights (EDR)` · Badges: `Words` / `Words, compact glyphs on chips` · Re-show coaching line · `Erase measurements on this phone`.

### 4.8 Calibrate (S7), sheet `.large`

```
       │  Calibrate                                            Done   │
       │  API  [ SwiftUI .blur(radius:) ▾ ]   PATH [ ImageRenderer.cgImage ▾ ] │ Menus
       │  [ RADIUS        −   2.0 pt   + ]   = 6.0 device px at scale 3  │ DecimalParameterStepper
       │ ╭ RESULT · 14:02 · iPhone 15 Pro Max · iOS 27.x ─────────────╮ │
       │ │ σ             6.06 px     σ / (r·scale) 1.010  ⏱ MEASURED   │ │ (illustrative values)
       │ │ EXCESS KURTOSIS  axis −0.41 · 45° −0.22        ⏱ MEASURED   │ │
       │ │ MODEL FIT     Gaussian 1.9 % · box³ 0.6 % · trunc-G 1.1 %   │ │ RMS residual per model; lowest wins, ✓
       │ │ WOBBLE        centre spread over 4 phases 0.21 px ⏱ MEASURED │ │
       │ │ BLEND         stripes 0.50 → gamma-encoded       ⏱ MEASURED │ │
       │ │ BORDER        opaque: false → transparent, spills ⏱ MEASURED │ │
       │ │ MAC REFERENCE σ/r 0.906 at 6 px (macOS 27.2, M1 Max) ⏱ MEAS. │ │
       │ ╰─────────────────────────────────────────────────────────────╯ │
       │ ╭ SWEEP · σ / (r·scale) vs r ──────────────────────────────────╮ │
       │ │ 1.0 ┤●●●●●●○              ● this iPhone   ○ not yet measured │ │
       │ │ 0.9 ┤      ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  ┄ macOS 27.2 reference           │ │
       │ │     └─┬───┬───┬────┬────┬──→ r (pt, log)  switch ◇ 1.7 pt ?   │ │ hollow marker = INFERRED until measured
       │ │ [ Run sweep · 34 radii × 4 phases ]  ≈ 12 s                   │ │
       │ ╰──────────────────────────────────────────────────────────────╯ │
       │  ON-SCREEN PATH (experiment) · drawHierarchy capture · EXPERIMENTAL │
       │  INSIDE APPLE (INFERRED): CAFilter gaussianBlur → render server; │
       │  NAMES FROM iOS 26.5 SIM / macOS 27.2 · NOT RE-READ FOR iOS 27 │
       │  · NOT OBSERVED RUNNING                                          │
```

Detail in §13.

## 5. The layer stack (the floors)

### 5.0 Rules for every floor

Every blur is the same seven-floor building: **1 SLIDE (WYSIWYG) → 2 API → 3 MATH → 4 KERNEL → 5 ALGORITHM → 6 GPU → 7 PIXELS**. Seven floors, the numbered pipeline he asked Loom to become (JD §1 Loom note); E's Shader/Silicon split lives as two tabs inside floor 6 (JD G8).

1. **One question about the probe per floor**, the same question for every blur (D §6.0). The page's title is that question.
2. **One governing rule** (callout mono, instrument cyan, units next to the equation), **one figure** (plot inset 374 × 140 or a code block), **at most six primary numbers**, each with its badge (JD M6). Everything else goes in `All … details` (`DisclosureGroup`), the only element that grows (AssemblerToy GD-1, METRO §F.1 item 7).
3. **An `IN THIS APP` line** closes every page: one sentence saying what on this page is LIVE, MEASURED, COMPUTED, MODELED, REFERENCE or INFERRED (AssemblerToy `LayerAtlasView`, METRO §C.10).
4. **Honest empty states.** When a floor has nothing honest to show for a blur, it says why in one engraved line instead of disappearing: `N/A · NONLINEAR`, `NO SINGLE RESPONSE · SPACE-VARIANT`, `NO PIXEL FOOTPRINT · GLOBAL (FFT)`, `SYSTEM INTERNALS · INFERRED`, `CPU ONLY IN THIS APP · TIER 3` (Metro §16; CAT §6.1 rule 2).
5. **Generated, not hand-written.** Page content comes from `BlurCore` data (kernel, passes, fetch tables, conventions table, badges, annotations). Hand-written text is limited to the catalog signature, one governing rule per floor template and family, and one closing lesson per Tier 1 entry (JF G-10, D R1). One data model feeds the floors, the Trace and the Divergence rows (JF M-12).
6. **Numbers are about the current state.** Every page reflects the current parameters, variant, specimen, probe and silent parameters, read from the newest acknowledged Run.
7. **Fixed geometry.** A page's slots have fixed heights at a given Dynamic Type size, computed from the largest content any blur puts on that floor, so switching blurs moves nothing (METRO §F.1 item 2).

### 5.1 The seven floors (generic definition)

| # | Floor | The question (page title) | Figure (one) | Primary numbers (≤ 6) | `All … details` | Typical badges |
|---|---|---|---|---|---|---|
| 1 | **SLIDE** (WYSIWYG) | "What would you type, and in which tool, to get this blur here?" | An **input you operate** (review fix P-52): `YOU TYPE [ 10 ] in [ SwiftUI ▾ ]` (a `DecimalParameterStepper` and a tool `Menu`, plain Metro chrome, no tool trade dress); setting it drives the Bench through that tool's convention (σ-held, the new value appears on the hero). Below it, horizontal bars: the typed value in each tool for the current blur, home tool first; rows that match only σ carry the caption `SAME σ, DIFFERENT KERNEL`. Toggle `You typed ⇄ What you get`: reverse mode, "you typed 10: σ per tool" (STACK §8, JD G18) | home tool's typed value; three to five other tools' values; for Tier S the live system value | the full conventions table (the 16 meanings of "radius", STACK §8), the pt → px chain, sources | REFERENCE, MEASURED (Apple APIs; device-measured where possible), INFERRED (Figma, Photoshop internals); UNVERIFIED tools appear as words, never numbers |
| 2 | **API** | "What call does that become, and what does each argument mean?" | The call as code (callout mono), each argument underlined; tap an argument for its unit, colour space, edge policy and alpha mode | σ (or R, L, a…) in px; unit chain (`4.0 pt × 3 = 12.0 px`); colour space; edge policy; alpha; the API's measured law (σ/r) | the Apple twins (Core Image, MPS, SwiftUI) with what each does differently at this probe; the branch "same σ, different pixel" | COMPUTED, REFERENCE, MEASURED, INFERRED |
| 3 | **MATH** | "What continuous operator is this, and what does it do to each frequency?" | Continuous PSF profile with the probe's ±support marked, and the signed response H(ν) (or its substitutes below). **Non-separable and anisotropic entries** (disc, polygons, Kawase, motion, anisotropic Gaussian, 2-D gathers) show a **signed 2-D H heat map** (diverging, zero marked, negative regions hatched; never colour alone) instead of a 1-D slice, so the hexagon's six spokes, Kawase's diagonal anisotropy and motion's zero lines are visible | FWHM; half-amplitude frequency; −3 dB frequency; first zero; minimum of H; 10–90 % edge width | property chips (LINEAR · LSI · SEPARABLE · ISOTROPIC · SEMIGROUP · POSITIVE · H ≥ 0), verdict chip (CAT §1 vocabulary), derivations (e.g. the Herschel–Maxwell two-line argument for "only round + separable kernel", CAT E17) | COMPUTED, REFERENCE |
| 4 | **KERNEL** | "What finite numbers stand in for the curve, and what did that cost?" | Discrete stems over the continuous curve (1-D), or a 2-D weight heat map centred on the probe | taps; centre weight; mass cut by truncation (discrete, per axis, with the 2-D value; the continuous tail in details); σ of the discrete kernel; minimum H of the discrete kernel; and, for every entry that approximates another (box³ → Gaussian, Kawase → Gaussian, linear-sampled → sampled stems, IIR → Gaussian, complex-separable → disc), the fixed slot **`ERROR VS <reference>`** with its definition in details (max \|effective − reference\| per tap, or relative L2 of the PSFs, as the entry declares) | weights table (accessible), discretisation picker (Gaussian: Sampled · Integrated · Lindeberg), truncation k, DFT of the taps | COMPUTED; LIVE for data-dependent kernels |
| 5 | **ALGORITHM** | "In what order, in how many passes, with what in-between images, is it computed?" | Pass tiles (event-tile grammar, 37 tall); tap a tile → the periscope shows that pass's intermediate texture (`PASS 1 OF 2`); plus the Cost plot (fetches per pixel vs size for the family's algorithms, with this phone's MEASURED ms as dots) | passes; fetches per pixel for the running variant; the same for the alternatives; the probe's value after each pass (LIVE); intermediate format | the variant picker (it drives what runs), pass graph, per-pass fetch formulas | COMPUTED, LIVE, MEASURED |
| 6 | **GPU** (tabs `Shader · Silicon`) | "Which thread computed this pixel, what did it fetch, and what did it cost on this phone?" | Shader: the exact compiled source. Silicon: dispatch geometry over a **copy** of the output (threadgroups, SIMD band, the probe's group and apron) | threadgroups × threads; the probe's thread / group / SIMD lane; static threadgroup memory vs the device limit; texture loads per pixel; GPU ms per pass; bytes moved | pass timeline (MEASURED bars, MODELED ghost bars), bandwidth floor, compression note, tile note, counter sampling points, the INFERRED lane for system blurs | REFERENCE (the code, feature tables), MEASURED (timings, limits read from the pipeline), MODELED (bytes, floors), COMPUTED (dispatch math), INFERRED (Apple's own blur) |
| 7 | **PIXELS** | "What went in, what came out, how was it encoded, and does the CPU agree?" | 9 × 9 input and output values side by side on a copy, probe outlined | IN (linear); OUT (linear); OUT encoded (8-bit sRGB); the branch value (other colour space, COMPUTED); CPU reference (Double); \|GPU − CPU\| in 8-bit steps and fp16 ulps | neighbour values, rounding chain (float accumulate → half store → sRGB encode), parity on the 128 × 128 crop | LIVE, COMPUTED, MEASURED |

**Floor 6 details (both tabs).**
- *Shader*: the source text that was compiled into the shipped `default.metallib` for the running variant, shown as a text resource that a build-time test proves byte-identical to the compiled source, with its SHA-256 stamped into the bundle and every Run (JF G-8). No on-device recompilation (JF M-5). Lines carry catalog annotations. Label REFERENCE ("it is the code").
- *Silicon*: dispatch per pass (grid, threadgroup size from `maxTotalThreadsPerThreadgroup`, SIMD width from the pipeline, static threadgroup memory from the pipeline: MEASURED; the Feature Set Tables limit beside it: REFERENCE); the probe's thread, threadgroup and SIMD lane (COMPUTED); per-pass GPU ms (MEASURED; per-encoder timestamps where `supportsCounterSampling(.atStageBoundary)`, otherwise command-buffer times split by pass-isolated command buffers; ARCHITECTURE §5.8); bytes moved and the bandwidth floor (MODELED; the 51.2 GB/s A17 Pro figure is leak-derived and UNVERIFIED, so the floor is shown only as `≈ MODELED · UNVERIFIED PEAK` or replaced by the device-measured copy bandwidth once This phone has run); compression: "render targets written without `.shaderWrite` keep lossless compression on Apple9; compute outputs lose it" (REFERENCE, Tech Talk 111431) and, after This phone's A/B, the MEASURED gap; tiles: "32 × 32 is the maximum tile size in Apple's tables for Apple9 (REFERENCE); the tile size this pass actually uses is not published (UNVERIFIED)" (JT note 5). For Tier S entries the tab is an **INFERRED lane** (dashed outline, magenta ? badge): render server (`backboardd`, INFERRED from the `com.apple.CARenderServer` registration), QuartzCore kernel names (`tile_downsample_{1,2,4,8}`, `tile_simd_blur_{5…27}`, `downsample_blur_*`, `upsample_*`, `variable_blur_*`; GPU §1.1) engraved `NAMES FROM iOS 26.5 SIM / macOS 27.2 · NOT RE-READ FOR iOS 27 · NOT OBSERVED RUNNING`, the WWDC 2014 five-pass diagram, and the measured fit: σ ≈ 0.90·r·scale above ≈ 5 device px and excess kurtosis −0.45 (both MEASURED offscreen on macOS until the phone measures them); closest model box³ (INFERRED).

### 5.2 What changes per kind of blur

Every catalog entry declares one **algorithm class**; the class decides what each floor's slots contain. Floors 1, 2 and 7 change least.

| Class (examples) | 3 MATH | 4 KERNEL | 5 ALGORITHM | 6 GPU (Silicon) | 7 PIXELS |
|---|---|---|---|---|---|
| **Separable FIR** (box, tent, Gaussian, binomial, iterated box, exponential separable form) | PSF + H(ν); separability chip | 1-D stems; 2-D outer product in details | H then V tiles; 2-D vs separable vs linear-sampled vs IIR counts | fragment passes (full-screen triangle) or compute tiles with apron | IN/OUT; branch: colour space |
| **2-D gather, LSI** (disc exact, 2-D Gaussian, odd-bladed polygons, stochastic bokeh) | PSF + signed 2-D H heat map (a 1-D slice in details) | 2-D weight map; sample pattern (golden-angle spiral, Poisson disc) | one gather pass (or row-span SAT for disc) | 16 × 16 groups; samples per pixel | IN/OUT; for stochastic: convergence with S |
| **Skew-separable** (polygonal bokeh 4/6/8 blades, anisotropic Gaussian) | Minkowski-sum figure (a flat hexagon is the union of three rhombi; each rhombus is two line blurs convolved); zonogon rule | the rhombi as tap lattices, one hatch each | two MRT passes, four one-sided 1-D blurs | fragment passes, two colour attachments | IN/OUT; seam test (LIVE) |
| **Recursive (IIR)** (iir-gaussian, exponential) | impulse response with exponential tails; H(ν) | feedback coefficients; effective PSF (infinite, contributions < 1 % summarised) | causal then anticausal, rows then columns | one thread per row/column (fp32) | IN/OUT; boundary transient at the left edge |
| **Running sums / SAT** (box sliding window, SAT box, stack blur; guided and classic Kuwahara via SAT) | as LSI parent | box weights; the 4 SAT corners | scan rows, scan columns, query | SIMD scans (Apple7+) with a threadgroup-memory fallback; fp32 corner magnitude and its ulp spacing | IN/OUT; SAT precision vs distance from the origin (CAT E11) |
| **Sparse iterated / pyramid** (Kawase, dual Kawase, mip chain, CoD 13-tap, Unity 13-tap, bloom chain) | effective PSF of the whole chain; H(ν) of the chain; shift-variance note | per-pass taps; the effective footprint (depth trace) | one tile per pass/level (`0 1 2 2 3`; `↓1 ↓2 ↓3 ↑3 ↑2 ↑1`) | mip levels; blit-based readback | IN/OUT; the probe's phase within 2^L |
| **Space-variant gathers** (zoom, spin, path, motion fields, tilt-shift, iris, variable blur, depth of field, cat's-eye, god rays) | **local** PSF at the probe and the coordinate change that makes it LSI (log-polar, polar); `NO SINGLE RESPONSE · SPACE-VARIANT` engraved for the global H | **PSF field**: a 7 × 7 grid of local PSFs drawn at their positions (a lens spot diagram); the probe's own taps on the texel grid; tap-spacing heat map | gather / adaptive gather / doubling | 16 × 16 groups; samples per pixel varies with position | IN/OUT; sampling warning; extra step "Where is the centre?" |
| **Adaptive weighted** (bilateral, joint bilateral, guided, domain transform, surface blur, non-local means) | weight formula; verdict ADAPTIVE BLUR (passes convexity, low-pass, shift invariance; fails linearity and data independence); **T(ν, A)** amplitude-dependent transfer map replaces H | **LIVE weight map at the probe** (the effective PSF there); it changes when the probe moves, which no LSI card ever does | brute force / separable (approx.) / grid (approx.) | tile + apron in threadgroup memory; no bilinear merging (each tap needs its own weight) | IN/OUT beside the Gaussian of the same σs |
| **Selection / rank** (median, Kuwahara, morphology) | order statistic or selection rule; `N/A · RANK` for H | the window values sorted, chosen one marked; Kuwahara's four sector variances and the winner | sorting network / histogram / SAT | registers; compare-exchange count | IN/OUT; the impulse "loses the vote" |
| **Iterative PDE** (heat equation, Perona–Malik) | PDE and its σ = √(2t) mapping (canonical ∂u/∂t = Δu, CAT E9) | the 5-point stencil and its step response (H ≥ 0 only for λ ≤ ⅛; the kernel itself stays non-negative, a monotone step, up to λ = ¼; §17 item 1) | one tile per iteration batch, scrubber over iterations | ping-pong with threadgroup blocking | IN/OUT vs iterations |
| **Global (FFT)** (frequency low-pass, FFT convolution, Lorentzian via FFT, Airy, Wiener) | H(ν) is the definition; Gibbs overshoot (ideal: 8.9 %) | kernel as an image; `NO PIXEL FOOTPRINT · GLOBAL` for per-tap rows | FFT → multiply → inverse FFT (padding picker) | FFT passes (ARCHITECTURE §6.4) | IN/OUT; the probe's row spectrum; wrap-around demo |
| **Stochastic** (frosted glass, camera shake) | expected PSF (frosted glass: σ² = a(a+1)/3, CAT §5.2); blur in expectation | the random neighbour actually copied (one realization) and the expected kernel | realizations N; the mean converging | noise texture + one fetch | IN/OUT of one realization vs the N-mean |
| **Temporal** (temporal accumulation, velocity-buffer motion blur) | exposure integral; LSV in space | velocity/depth-weighted taps | tile max, neighbour max, reconstruction / N sub-frames | multiple passes, extra buffers | IN/OUT; static parts pixel-identical (accumulation) |
| **System (Tier S)** (SwiftUI `.blur`, materials, Liquid Glass, `.shadow`, `CALayer.shadowRadius`) | our model's math (MODELED), the measured fit (MEASURED) | measured LSF from `ImageRenderer` beside the model kernel | **INFERRED lane** | **INFERRED lane** | `OFFSCREEN · ImageRenderer` values; glass: `NOT CAPTURABLE · INFERRED` |
| **Blur-derived / contrast** (drop shadow, bloom, god rays; unsharp mask, DoG, morphology, pixelate, Lanczos, Wiener) | why it is (or is not) a blur: the failed test (convexity, low-pass, DC gain) | as its construction | as its construction | as its construction | IN/OUT; overshoot (USM), halo, cell mean |
| **Tier 3 (atlas only)** | full math page | CPU-computed kernel and response on a 128 × 128 crop | `CPU ONLY IN THIS APP · TIER 3` and why | `CPU ONLY IN THIS APP · TIER 3` | CPU-computed values on the crop, COMPUTED |

**Floor 1 and 2 by situation.** If no design tool offers the blur, floor 1 says where it lives instead (engines, libraries, papers) and shows that tool's parameter name (e.g. Kawase: Unity URP, KWin, Android SurfaceFlinger; REFERENCE). If a tool's mapping is unknown, the row shows the tool and the word UNVERIFIED (Photoshop Gaussian Radius, Photoshop Radial Blur Amount, After Effects Blurriness; STACK §4). Floor 2 always names Blur2ool's own call (`b2ool_…` and its parameters in px) first, then the platform twins.

### 5.3 Worked examples (fixtures)

These four set-ups are the guided descents (§8.5) and **acceptance fixtures**: `BlurCore` unit tests reproduce every COMPUTED number to the printed precision, and the GPU parity CLI reproduces the GPU values within tolerance (ARCHITECTURE §7). Specimens are at N = 894. Values are from D §6.1–§6.4 and I §5.2–§5.5, re-verified by the truth judge (JT interim notes) unless marked.

**A. One pixel through a Gaussian.** Step edges (x ≤ 446 → 0.0, x ≥ 447 → 1.0, linear light), probe **(446, 300)**, σ = 4.0 px, k = 3 (r = 12), sampled discretisation, clamp, linear light, fp32 accumulation, `rgba16Float` storage.

| Floor | Numbers (badge) |
|---|---|
| 1 SLIDE | SwiftUI `.blur(radius: 1.33)` (small-radius regime σ ≈ r·scale, MEASURED macOS, INFERRED on iOS until calibrated); CSS `blur(1.33px)` (σ = value, REFERENCE); Figma layer blur 2.67 (σ = value/2, INFERRED); `CIGaussianBlur` 4 and `MPSImageGaussianBlur` 4 (MEASURED); Android `RenderEffect` 6.06 px (σ = 0.57735·r + 0.5, REFERENCE); GIMP 2.8 Blur Radius 12.3 (σ = (r + 1)/3.329, REFERENCE); ImageMagick `-blur 0x4`; Photoshop Radius: UNVERIFIED |
| 2 API | 1.33 pt × 3 = 4.0 px; linear light, clamp, premultiplied (ours); `CIGaussianBlur` linear light, transparent edges unless clamped; `MPSImageGaussianBlur` "~10 bits" approximate; SwiftUI default `.nonLinear` blends gamma-encoded values (MEASURED offscreen; on-screen INFERRED) |
| 3 MATH | peak 0.0997; FWHM 9.42 px; half-amplitude 0.0469 c/px; 10–90 % edge 10.25 px; H(0.5) ≈ 5·10⁻³⁵ (COMPUTED) |
| 4 KERNEL | weights k = 0…12: 0.09991, 0.09683, 0.08817, 0.07541, 0.06060, 0.04574, 0.03244, 0.02161, 0.01352, 0.00795, 0.00439, 0.00228, 0.00111; discrete σ **3.963** px; mass cut by truncation at ±12: **0.173 %** per axis, 0.346 % of the 2-D kernel (discrete; the continuous tail beyond ±3σ is 0.27 %); discrete min H **−0.0010**; H(0.5) = 7.1·10⁻⁴ (fixture) |
| 5 ALGORITHM | 2-D direct 625 taps; separable 50; linear-sampled **26** fetches (13 per pass); IIR ≈ 8 MACs per direction; after pass H the probe is **0.4500**, pass V leaves it unchanged (fixture) |
| 6 GPU | bilinear offsets 0, ±1.4766, ±3.4455, ±5.4149, ±7.3849, ±9.3558, ±11.3277 texels, weights 0.09991, 0.18500, 0.13601, 0.07818, 0.03513, 0.01234, 0.00339 (fixture; Rákos 2010 pairing); hardware sub-texel weights 8 bits, round to nearest (MEASURED on the M1 Max only; the Simulator forwards to the Mac GPU, so it is not a second measurement; device: This phone's automatic probe); traffic ≈ 25.6 MB (MODELED); compute-tile variant: 256 × 1 row tile, probe is thread 190 of threadgroup (1, 300), SIMD-group 5 lane 30, **2,240 B** of dynamic threadgroup memory ((256 + 2·12) × 8 B; fixture) |
| 7 PIXELS | IN 0.000 → OUT **0.4500** linear → **179/255**; neighbours x = 445…450: 0.353, 0.450, 0.550, 0.647, 0.735, 0.810; branch: blurred in sRGB-encoded space **115/255** (fixture) |

Closing lesson: "Seven floors, one pixel: you typed 1.33, the GPU fetched 26 times, and the pixel went from 0.000 to 0.450. The floor that most changed the answer was the one nobody shows: the colour space at the API floor (179 vs 115)."

The Bench default (Night City, σ = 12) also pins: r = 36, 73 taps per axis, w₀ 0.03332, w±12 0.02021, w±24 0.00451, w±36 0.00037, mass dropped **0.235 %** per axis and **0.47 %** of the 2-D kernel (discrete; continuous tail 0.27 %), σ of the truncated kernel 11.86 px, minimum H −0.0012, 37 fetches per pass (74 total), largest effective-tap error of the linear-sampled pairs vs the stems 1.1·10⁻⁴ (MODELED, 8-bit round to nearest), linear-sampled offsets 0, 1.4974, 3.4939, 5.4905 … with weights 0.03332, 0.06607, 0.06382, 0.05996 … (I §5.2, fixture).

**B. Why zoom blur spares a star.** Siemens star with **36 cycles** (n_c = 36, CAT E7) centred on the continuous point (447.5, 447.5), the centre of pixel c = (447, 447) (§11 rule 2); zoom strength a = 0.10, **centred** variant (scales 1.05 → 0.95 about the centre), 32 samples, bilinear, clamp, linear light; probe **(747, 460)**: r = 300.3 px at θ = 2.48°, the **middle** of a white wedge (wedges are 5° wide). (The first draft's (747, 447) lies exactly on the spoke boundary θ = 0, where the 4 × 4-supersampled star reads 0.5; review fix P-32.)

| Floor | Numbers (badge) |
|---|---|
| 1 SLIDE | Photoshop Radial Blur › Zoom Amount → strength: UNVERIFIED; `CIZoomBlur` streaks **outward**, length ratio 0.079 at amount 4 and 0.357 at 16 (MEASURED, CAL §5.2) against the fitted law 1.5^(amount/20) (MEASURED fit, STACK §3.4): `SOURCES DISAGREE`, exact law UNVERIFIED |
| 3 MATH | local PSF: radial segment of length a·r = **30 px**, σ along the ray **8.66 px**, zero across; local zero lines every **1/30 c/px** across the ray; in log-polar coordinates the operator is **approximately** a box of width ln(1.05/0.95) = **0.100** in ln r, exact only for geometrically spaced samples (the uniform-in-scale weights make the density along ln r vary 0.950–1.050 for this set-up; JT note (d)) |
| 4 KERNEL | taps at radii r_i = 300.3·(1 − 0.1·(i/31 − 0.5)) along the probe's ray: **315.3 … 285.3 px**, spacing **0.969 px**, weight 1/32; ghost-free corners need N ≥ a·r_max + 1 = **65** (r_max = 632 px); with 32 samples the corner spacing is **2.04 px** (fixture) |
| 5 ALGORITHM | gather 32 fetches; adaptive N(x) = ⌈a·r⌉ + 1 (31 at the probe, 65 at corners); doubling: 6 passes of 2 fetches = 64 geometrically spaced samples for 12 fetches (exact for the geometric variant) |
| 6 GPU | `dispatchThreadgroups(56 × 56, 16 × 16)` = 3,136 groups, bounds check discards 2 surplus rows and columns; probe = thread **(11, 12)** of threadgroup **(46, 28)** (COMPUTED); outputs need `.shaderWrite`, so not compressible on Apple9 (REFERENCE); parity on the Mac 7.3·10⁻⁴ (MEASURED, GPU §6.3) |
| 7 PIXELS | star: IN **1.000** → OUT **1.000** (all taps in one wedge, 12 px from its edges); zone plate: IN **0.224** → OUT **0.499**; modulation along the ray (peak-to-peak over ±6 px) **0.970 → 0.042** (fixture; COMPUTED in review round 1 with exact bilinear fractions, `$TMPDIR/blur2ool-review-apply/py/zoom.py`) |

Closing lesson: "The same blur left your pixel exactly as it was on the star and turned it grey on the zone plate. Zoom blur is (almost exactly) a box along rays: anything made of rays survives. Its dual, spin blur, does the opposite (P21)."

The Bench default for zoom (I §5.3: impulse grid, inward one-sided a = 0.20, 32 samples, probe (747, 447)) pins: local streak 60 px, σ along the ray 17.32 px, tap spacing 1.94 px at the probe and **4.08 px** at the corners, ghost-free N ≥ 128 (fixture).

**C. The blur that looks before it averages (bilateral).** Noisy step with noise **off**: 0.40 (x ≤ 446) → 0.60 (x ≥ 447), linear light; probe **(447, 300)**; σs = 3.0 px, σr = 0.10 of full scale, window radius 8 (17 × 17), luma range distance, clamp.

| Floor | Numbers (badge) |
|---|---|
| 1 SLIDE | OpenCV `bilateralFilter(d 17, sigmaColor 25.5, sigmaSpace 3)`, labelled **same parameters, different range metric**: on 8-bit input OpenCV works on encoded values with an L1 RGB colour distance (3Δ for grey), so it is not this filter (REFERENCE); the matching OpenCV call is single-channel linear float luma with `sigmaColor 0.10` (REFERENCE); After Effects Bilateral Blur (Radius, Threshold) (REFERENCE); Photoshop Surface Blur → `surface-blur` (algorithm INFERRED); Threshold → σr: UNVERIFIED; no Apple API (`CIEdgePreserveUpsampleFilter` INFERRED to be a joint bilateral) |
| 2 API | σr acts in whatever space the numbers are in: the 0.40 → 0.60 linear step is 0.665 → 0.797 encoded (difference 0.132) |
| 3 MATH | range weights e^(−Δ²/2σr²) = **0.61** (Δ = σr), **0.135** (2σr), **0.011** (3σr); T(ν = 0.1, A) = **0.178, 0.214, 0.524, 0.930** for A = 0.01, 0.03, 0.1, 0.3 vs the Gaussian's 0.168 (NL A2) |
| 4 KERNEL | dark-side columns scaled by 0.135; they carry **9.4 %** of the weight vs **43.3 %** for the Gaussian; at the 0.05 step 40.3 %; at the 1.00 step 2·10⁻²² (fixture) |
| 5 ALGORITHM | brute force **289** taps; separable 34 taps (RMS 0.0050 vs brute force on a noisy star, NL A4); grid (cells σs × σs × σr) |
| 6 GPU | tile (16 + 16)² = 1,024 texels × 8 B = **8,192 B** threadgroup memory; 4 device loads per pixel; probe = thread **(15, 12)** of threadgroup **(27, 18)**; 289 × 799,236 ≈ 2.3·10⁸ weight evaluations per frame (COMPUTED) → half-resolution preview while moving |
| 7 PIXELS | IN 0.600 → OUT **0.581** vs Gaussian **0.513**; 0.05 step: 0.5049 vs 0.5033; 1.00 step: **1.000** vs 0.567 (fixture) |

Closing lesson: "This blur asked every neighbour 'do you look like me?' before averaging. On your pixel the dark side answered with weight 0.135, and the edge survived: 0.581 instead of 0.513."

**D. Four line blurs make a hexagon.** Night City with one 1-px light of intensity **100** at (447, 447), linear HDR `rgba16Float`; hexagon circumradius R = 16 px, rotation 0°, 6 blades, curvature 0; probe **(447, 455)** (8 px below the light, inside the hexagon: apothem 13.9 px).

| Floor | Numbers (badge) |
|---|---|
| 1 SLIDE | Photoshop Lens Blur iris controls (REFERENCE controls, INFERRED implementation); Unity URP Bokeh DoF Blade Count 3–9 (REFERENCE source); After Effects Camera Lens Blur "Use Linear Working Space" (REFERENCE); `CIBokehBlur` is a disc (bit-identical to `CIDiscBlur` at default ring and softness, MEASURED) |
| 3 MATH | area (3√3/2)·R² = **665.1 px²**; per-axis σ = √(5/24)·R = **7.30 px**; a flat hexagon is the **union of three rhombi**, each the convolution of two 16-px segments 120° apart; its response is the sum of three rhombus terms (each a product of two sincs with a phase), with six slow-decaying spokes, not circular zeros; zonogon rule: only centrally symmetric polygons (4, 6, 8 blades) are sums of segments |
| 4 KERNEL | 3 rhombi × 16 × 16 = 768 bilinear samples per pixel, weight 1/768; directions (0, −1), (0.866, 0.5), (−0.866, 0.5) texels per step, one-sided, first tap half a step out; five blades → masked 2-D gather of ≈ **609** taps |
| 5 ALGORITHM | pass 1 (two attachments): T1 = blur(src, ↑), T2 = ½[blur(src, ↑) + blur(src, ↘)]; pass 2: ⅓·blur(T1, ↘) + ⅔·blur(T2, ↙) → each rhombus weight exactly ⅓; **4 one-dimensional blurs × 16 taps = 64 fetches** vs ≈ 665 for a 2-D gather; the published 0.5/0.5 normalisation is UNVERIFIED, so Blur2ool states its own weights (fixture) |
| 6 GPU | two fragment passes, MRT in pass 1, render targets without `.shaderWrite` (compressible on Apple9, REFERENCE); traffic ≈ 38.4 MB (MODELED) |
| 7 PIXELS | IN 0.000 → OUT **0.1504** linear → 0.424 encoded → **108/255**; blurred in sRGB-encoded space: plateau ≈ **0.55 %** of the correct light; a light clipped to 1.0 in 8-bit: **5/255** (linear blur) (fixture) |

Closing lesson: "Your pixel was black. It turned 0.150 because a light of 100 was spread evenly over 665 pixels in the shape of a hexagon, built from four straight streaks. Set BLADES to 5 and the streak trick stops working: a pentagon is not a sum of line segments."

(Renamed from D's "Three line blurs make a hexagon": three segments *convolved* give a hexagonal support with a peaked, not flat, PSF (max/mean 3.07, JT note (e)); the flat hexagon needs three rhombi built from four line passes.)

## 6. The pixel trace

The Trace is the AssemblerToy Guide applied to a pixel: AssemblerToy walked one instruction through Assembly → CPU → Registers → Memory → OS; Blur2ool walks **one output pixel** through Slider → API → Math → Kernel → Algorithm → GPU → Pixels (D §7, METRO §C.10). It is pushed from the primary button `Descend from (x, y)` (wireframe §4.4).

### 6.1 Choosing the pixel

- The pixel is the current probe. Placing it is done on the Bench (tap, loupe, adjustable action). The Trace's title is `Pixel (x, y)`.
- **Jump menu** (navigation bar, `Jump ▾`; E §6.1, JD G11), each item moves the probe and restarts the walk: `Feature probe` (the specimen's default probe) · `Brightest output pixel` · `Worst parity pixel` (argmax |GPU − CPU| on the 128 × 128 crop of the last settled Run) · `Predicted inversion ring` (for kernels whose H goes negative: on the 36-cycle star, the radius where the local frequency hits the first negative lobe; for a disc r = 0.261·n_c·R with n_c in cycles, CAT E7) · `Edge` · `Impulse peak` · `Corner` (worst sampling, zoom and spin) · `Tile boundary` (a pixel whose footprint straddles a 32 × 32 tile boundary; the label says the 32 × 32 size is the Apple9 maximum, REFERENCE, and the real tiling is UNVERIFIED). Items that do not apply to the current blur or specimen are hidden, not disabled.

### 6.2 Screen anatomy (§4.4)

1. **Context card** (pinned, 406 × 168): a 9 × 9 texel copy of the probe's neighbourhood at 12 pt per texel (17 × 17 behind `Magnify`), the current pass's weights as amber bars under each texel; four fixed rows `IN` · `Σ` (running partial result while a floor is mid-walk, blank otherwise) · `OUT` (once known) · `Completed` (instrument amber, what has happened) / `Next` (action cyan, what the next tap does) (AssemblerToy GD-2); and a phase metadata line `Step 10 / 15 · fragment (446, 300) · pass 1 of 2 · horizontal`. Values use monospaced digits in reserved widths.
2. **Floor selector**: 4 + 3 `InstrumentEventTiles` (95.5 × 54, gap 8): done floors carry an amber caption `done`, the current floor cyan fill 0.08 + border 0.35, floors ahead idle. Tapping a tile jumps there; floors ahead are allowed (the walk is not a gate), and the context card then shows that floor's state as if the walk had reached it.
3. **Floor panel** (scrolls): one floor's primary facts for this step only (AssemblerToy GD-1): the step's figure (texel strip with fetch markers, sorted window, weight map, pass intermediate crop), the step's row of numbers, the floor's governing rule, and `All … details`.
4. **Bottom controls** (`safeAreaInset(edge: .bottom)`, 58 tall, over an opaque canvas strip: AssemblerToy's accepted exception for stepped flows, METRO §F.1 item 12): `‹ Back` (96) · `↺` Restart (62) · primary `.glassProminent` whose label always names the next unit of work: `Next floor`, `Next pass`, `Next fetch`, `Next iteration`, `Next tap`, `Finish`; a long press on the primary completes the current pass (`Finish pass`). At the end the primary becomes `Back to Blur2ool` and a secondary `Descend another pixel` returns to the Bench with the probe crosshair highlighted for one second.

### 6.3 Step grammar

A walk is a list of **steps**; a step can have **sub-steps** (taps, fetches, iterations, compare-exchanges) that `Next …` advances one at a time. A step never changes the specimen's parameters; it only reveals. Steps are generated from the blur's pass graph and catalog data (JF G-10), so every Tier 1 entry gets a walk without hand-written step lists; the only hand-written text is the closing lesson.

**The Gaussian walk** (guided descent A, §5.3; 15 steps):

| Step | Floor | `Completed` after the tap | Panel shows |
|---|---|---|---|
| 1 | SLIDE | "You would type 1.33 in SwiftUI" | tool table, home tool first |
| 2 | API | "1.33 pt × 3 = 4.0 px" | the unit chain and SwiftUI's ≈ 5-px regime switch |
| 3 | API | "Linear light, clamp, premultiplied" | the three silent parameters, each with its branch value of OUT (179 vs 115 for colour space) |
| 4 | MATH | "G with σ 4.0 px" | formula, profile, response |
| 5 | KERNEL | "25 weights sampled" | stems, weights |
| 6 | KERNEL | "Renormalised after cutting at ±12" | cut tails, discrete σ 3.963, ripple −0.0010 |
| 7 | ALGO | "Split into H then V" | 625 → 50 taps |
| 8 | ALGO | "Merged into 13 bilinear fetches per pass" | the pairing table |
| 9 | GPU | "Draw call issued for pass H" | render pass, target, sampler, fragment count |
| 10 | GPU | "13 fetches done" (13 sub-steps; Σ grows 0 → … → 0.450) | texel strip with fetch markers; each fetch's offset, the two texels it blends, `t` as requested and as the hardware quantizes it, weight, fetched value, Σ |
| 11 | GPU | "Pass H written: 0.4500" | the intermediate texture crop |
| 12 | GPU | "Pass V: 13 fetches, value unchanged" (13 sub-steps) | why V does nothing on a vertical edge |
| 13 | GPU | "GPU time 0.xx ms" | the pass timeline, MEASURED |
| 14 | PIXEL | "OUT 0.450 linear" | 9 × 9 in/out, CPU parity |
| 15 | PIXEL | "Encoded 179/255 for the display" | the sRGB encode; the gamma-space branch 115 |

**Running sum.** On GPU-floor fetch steps the accumulator is drawn as a growing bar beside the fetch list, so the output literally fills up as the weighted fetches land (I §6 item 5, JD G9).

**Branches, not forks** (D §7, JD G9). On the API step(s) he can flip a silent parameter (colour space, edges, alpha, precision). The walk does not restart: the alternative result appears greyed beside the real one (`OUT 0.450 · if sRGB-encoded: 115/255`, COMPUTED) and the walk keeps following the real path. This is how the trace teaches that the API floor's invisible choices can matter more than σ.

**Ending.** The last step's `Completed` line is the one-sentence closing lesson for the blur (§5.3); for blurs without a hand-written lesson, a generated one from the catalog's signature and the walk's numbers ("Your pixel went from 0.000 to 0.450 after 26 fetches in 2 passes.").

### 6.4 Where the trace's numbers come from (binding honesty rules)

1. **GPU values are GPU records.** Every Tier 1 kernel exists in two specializations of one `.metal` source, selected by the function constant `TRACE_PROBE` (D §15 R2, JF §3.1). The traced specialization writes, for the probe pixel only, each tap's position, weight, fetched value and running sum into a small buffer. Those records are the per-fetch rows: badge **LIVE** (they were produced by the GPU for the frame on screen) (JD G10, JF G-7).
2. **The frame on screen is the traced frame.** While the Trace is open, the image (Bench periscope and the Trace's crops) is rendered by the traced specialization itself, so the recorded taps and the displayed pixel come from one execution, whatever the compiler does (JF G-7). The traced pipeline is compiled off the main actor when the Trace is pushed (first specialization took 59–417 ms on a loaded M1 Max, JF §3.1); until it is ready the Trace shows its context card with `PREPARING TRACED BUILD` and the Bench keeps the untraced frame, never a frozen screen. Trace buffers are sized from the pass plan, so every fetch is recorded even for passes with thousands of taps (2-D Gaussian above σ 5, disc gathers, non-local means); each traced pass ends with a final record of the value it stored, which the parity CLI compares with the output.
3. **Bit-exactness is tested, not assumed.** Accumulating kernels spell accumulation as explicit `fma()`; the parity CLI asserts that the traced and untraced specializations produce bit-identical outputs for every Tier 1 kernel (JF §3.1 measured 1-ulp differences in about half of all output words with `sum += x * w` under default fast math, and 0 with explicit `fma`; JF M-7). On the phone the same check runs from This phone (`Traced = untraced`, MEASURED).
4. **Per-pass values are real intermediates.** `Next pass` reads the probe's 9 × 9 footprint from the actual intermediate texture by a blit into a shared buffer (the only correct path in the Simulator for mips, GPU §2.7 item 7), so an error can be pinned to the pass that introduced it (E §6.2 item 4).
5. **Bilinear `t`.** Each fetch row shows the fraction as requested (COMPUTED) and as the hardware quantizes it (MODELED from the MEASURED sub-texel rule: 8 bits, round to nearest, on the M1 Max; This phone measures the A17 Pro automatically once, in the background, after the idle gate), e.g. `t 0.4941 → 0.4922` (E §6.2 item 3).
6. **CPU values say COMPUTED.** The `BlurCore` reference value (Double) sits beside each GPU value with the difference in 8-bit steps and fp16 ulps. **A CPU re-computation of a GPU value is never LIVE** (JF M-6, JD M14). (An adaptive blur's weight map, computed by the CPU from the current image because the GPU never stores it, is `LIVE · CPU`, §12.1: it is not a copy of a GPU value.)
7. **Tier 2 entries** trace one stage (their declared `traceStage`), with GPU records for that stage only; other stages show COMPUTED values from `BlurCore` and say so in the floor panel.

### 6.5 How the trace adapts per class

| Class | A sub-step is | Notes |
|---|---|---|
| Separable FIR | one fetch (bilinear pairs list both texels) | 2 passes |
| 2-D gather (disc, odd blades, stochastic bokeh) | one sample along the pattern | samples that miss a light are flagged |
| Skew-separable (hexagon) | one tap on each of the four line segments | rhombus seams highlighted |
| Recursive (IIR, exponential) | one recursion step along the row, causal then anticausal | contributions < 1 % of the total summarised in one row |
| Running sums / SAT | the entering and leaving texels plus the running state; the 4 SAT corners | fp32 corner magnitude and its ulp spacing |
| Sparse iterated / pyramid | one pass or level, drawn on the pyramid | the probe's phase within 2^L, the cause of shift variance |
| Space-variant gathers | one sample along the ray or arc | extra step "Where is the centre?" (distance and angle from it); gaps between samples drawn |
| Adaptive weighted (bilateral…) | one tap: spatial weight × range weight = product | rows sortable by final weight; the weight map is the effective PSF |
| Rank (median) | one compare-exchange of the sorting network | the sorted window with the chosen value marked; the impulse "loses the vote" |
| Kuwahara | one sector: mean and variance | the winning sector marked |
| Iterative PDE | one iteration of the 5-point stencil, with an iteration scrubber | σ = √(2t) updates as t grows |
| Global (FFT) | one frequency of the probe's row spectrum multiplied by H(ν) | floor 5–6 say `EVERY OUTPUT PIXEL DEPENDS ON EVERY INPUT PIXEL` (CAT §6.1 rule 2) |
| Stochastic (frosted glass) | the one random neighbour copied, then the N-realization mean converging (P24) | — |
| Tier S | no GPU trace: "Runs in the render server; we can measure its output, not follow its fetches." Floors 1, 2, 7 real (offscreen), 3–6 the INFERRED lane | — |
| Tier 3 | floors 1–4 and a CPU-computed floor 7 on a 128 × 128 crop (COMPUTED) | floors 5–6: `CPU ONLY IN THIS APP · TIER 3` |

### 6.6 Pace, motion and feedback

Steps advance only on a tap; there is no autoplay by default. `Play` (inside `All … details`) auto-advances one sub-step every 250 ms with the primary in amber (running); Reduce Motion disables Play's motion and easing but manual stepping always works (Los Alamos precedent, METRO §F.4 item 8). One light haptic per completed *floor*, never per sub-step. VoiceOver: after each step the context card posts one announcement in fixed order ("Completed: fetch 7 of 13, weight 0.078, value 0. Partial sum 0.399. Next: fetch 8 at plus 7.38 pixels."); `Next` is the default action of the whole card. While VoiceOver is running, `Play` announces only when a **floor** completes (never every sub-step, Metro §17), and pauses itself when an announcement is still being spoken.

## 7. The fingerprint card

BRIEF requirement 4 is answered by one artefact with a **fixed layout for every entry**, so any two cards line up and differ only where the blurs differ (I §7, JD G12). It is answered three ways, quick to deep: the **signature sentence** (one line), the **card** (four glyphs, six rows, one unique number), and **where it parts ways** with its neighbours (§8.4).

### 7.1 Card anatomy (sheet; content width 406; fixed slot heights)

```
 ╭──────────────────────────────────────────────────────────────────╮
 │ GAUSSIAN BLUR                         F2 · GAUSSIAN & APPROX.    │ largeTitle rounded semibold · family eyebrow
 │ [TRUE BLUR] [TIER 1] LSI · SEPARABLE · ISOTROPIC                  │ verdict chip · tier chip · property chips
 │ H ≥ 0 (CONTINUOUS) · TRUNCATED: RIPPLE                            │ qualified response chips (as run: min H −0.0012)
 │ "The only blur that is both round and separable; its continuous  │ signature: serif italic, instrument cyan,
 │  response fades every detail smoothly and never inverts phase."   │ CATALOG §2 with §17 fixes
 │ ┌ PSF ─────┐┌ STAR ────┐┌ EDGE ────┐┌ H ───────┐                  │ fingerprint strip: 4 plot insets 88 × 88,
 │ │  ( ◍ )   ││ (smooth) ││   _/‾    ││ ╲__      │                  │ identical inputs and axes for every blur,
 │ │ log int. ││ 36 cyc.  ││ step ESF ││ 0–0.5 c/px│                  │ all at σ_equiv 4 px, engraved AT σ 4 PX
 │ └──────────┘└──────────┘└──────────┘└──────────┘                  │
 │ PSF SHAPE   round bell, no rim; excess kurtosis 0       = COMP.  │ six rows, 22 pt each, fixed order:
 │ RESPONSE    continuous e^(−2π²σ²ν²) > 0 · as run (k 3)    = COMPUTED │ mono label · value prose · badge (word never
 │             min H −0.0012                                          │ abbreviated; a long row wraps to two lines)
 │ EDGES       erf S-curve, 10–90 % = 2.563 σ, no overshoot = COMP. │
 │ COST        O(r) separable · O(1) via IIR or pyramid     = COMP.  │
 │ ARTIFACTS   square halo on HDR lights if cut at 2σ       = COMP.  │
 │ USED IN     CSS blur(), CIGaussianBlur, MPS, SIFT, Canny ▤ REF.   │
 │ UNIQUE      0 · kurtosis on axis = at 45° while separable = COMPUTED │ the unique number, title2 mono, + one line
 │ ├──●───────────────○──────────────────────────┤ EXCESS KURTOSIS   │ shared axis −1.2 … +3: box −1.2 · disc −1.0 ·
 │  box  disc  tent  box³  GAUSS            Laplace                  │ tent −0.6 · box³ −0.4 · Gaussian 0 · Laplace +3
 │ ┌ TELL ──────────────────────────────────────────────────────┐   │ the one test that gives it away
 │ │ Siemens star: no reversed rings, a round grey disc.   [ Show me ] │
 │ └────────────────────────────────────────────────────────────┘   │
 │ NEAREST     box (inverts) · binomial (0 at Nyquist) · iterated box │ one tap → Bench wipe against it at held σ
 │ PARTS WAYS  box at MATH · tent at MATH · IIR at KERNEL           │ amber floor names (§8.4)
 │ ON THIS PHONE  σ 4.00 px ⏱ MEASURED · kurtosis 0.00 / 0.00 ⏱ MEASURED │ two-line LabeledValues, one badge per number;
 │                shift 0.00 px ⏱ MEASURED · 0.8 ms/MP ⏱ MEASURED      │ measured from GPU output, on demand
 │ LOOKS MOST LIKE  gaussian-blur · Δ 0.00 ⏱ MEASURED                 │ nearest catalog fingerprint
 │                                                   Field guide ›   │
 ╰──────────────────────────────────────────────────────────────────╯
```

1. **Header.** Display name; family eyebrow (`F2 · GAUSSIAN & APPROXIMATIONS`); verdict chip from the CATALOG vocabulary (TRUE BLUR · ADAPTIVE BLUR · RANK FILTER · BLUR IN EXPECTATION · LSV BLUR · COMPOSITE · BLUR-DERIVED · NOT A BLUR); tier chip; property chips (LSI / LSV / NL / E; SEPARABLE / SKEW / NO; ISOTROPIC; POSITIVE; SEMIGROUP). The response chip is qualified (review fix P-35): `H ≥ 0 (CONTINUOUS)` describes the continuous operator, and every entry whose **as-run** discrete kernel dips below zero also gets `TRUNCATED: RIPPLE` with the value in its accessibility label ("as run with truncation 3, minimum H minus 0.0012"). No chip or row ever says "never negative" about the kernel the GPU runs unless its discrete minimum is ≥ 0.
2. **Signature**, verbatim from CATALOG §2's master table (truth fixes of §17 applied where a signature carries a wrong word).
3. **Fingerprint strip.** Four 88 × 88 insets from the **same four procedural inputs for every blur**, rendered at **σ_equiv 4 px** (the §7.4 reference size; engraved `AT σ 4 PX`, so cards line up and supports never outgrow the 128² crop): **PSF** (impulse response, log intensity: shows rims, tails, holes, square supports), **STAR** (a crop of the 36-cycle Siemens star: zeros as grey rings, inversion as reversed spokes, anisotropy as square rings), **EDGE** (step-edge profile: linear ramp, erf S-curve, half-disc curve, overshoot), **H** (signed response from 0 to 0.5 c/px with negative lobes shaded and dashed). PSF, STAR and EDGE are rendered by the GPU through the running variant on 128 × 128 inputs (LIVE). **Tier S entries never use our Metal model here** (review fix P-31): their strip is the real Apple modifier or material rendered offscreen with `ImageRenderer` (MEASURED · OFFSCREEN, with the device); before that render or a calibration exists the insets read `NOT YET MEASURED`. H is COMPUTED from the discrete kernel for LSI blurs; LSV blurs show the local response at a standard probe; adaptive blurs show T(ν, A) at A = 0.05 and 0.5 as two curves; rank filters engrave `N/A · RANK`.
4. **Six rows**, exactly the brief's list in this order: PSF SHAPE · RESPONSE · EDGES · COST · ARTIFACTS · USED IN. One line each, an optional disclosure, its own badge. The numbers are CATALOG's CHECKED values (e.g. disc RESPONSE: "zeros at 0.6098/R, 1.1166/R; deepest lobe −0.1323 at 0.8174/R").
5. **UNIQUE.** One headline statistic chosen to be what *only this blur has*, with its badge and one line of context (§7.2).
6. **Excess-kurtosis axis.** The line-spread function's **excess** kurtosis on one labelled axis (Gaussian 0; never the non-excess convention, JT note 4) with this blur's dot (COMPUTED) and, once measured, a hollow dot `ON THIS PHONE` (MEASURED). The same statistic classifies a measured system blur, so the axis is shared between theory and measurement.
7. **TELL** box: the one test image that exposes the blur, with `Show me`, which sets the Bench (specimen, blur, held σ, probe, compare view) and dismisses.
8. **NEAREST**: two or three entries it is most often confused with (from CATALOG §7 pairs), each one tap → Bench in Wipe against it at held σ.
9. **PARTS WAYS**: for each neighbour, the floor where they first differ (§8.4), floor names in instrument amber with ▶.
10. **ON THIS PHONE** (E §7.1, JD G12): for Tier S entries this row comes from the newest `CalibrationResult` for the subject (MEASURED · OFFSCREEN), or reads `NOT YET MEASURED`. For our blurs, when the card opens, four small background dispatches (impulse grid, step edge at 4 phases, 1-px stripes, star crop) feed a measurement from **GPU output**: σ_eff, excess kurtosis on the axis and at 45°, edge-centre shift over 4 whole-pixel phases (the shift-variance detector, CAL §3.3), the minimum of H from the measured PSF, and ms per megapixel. Analytic values sit beside them (COMPUTED). A mismatch beyond tolerance is flagged with a symbol **and** words ("GPU differs from the math by 3.1 %"), never amber alone. In the Simulator the ms column reads `SIM`.
11. **LOOKS MOST LIKE**: the measured fingerprint vector (§7.4) compared with every catalog entry's computed vector; names the nearest and the distance (badged). For SwiftUI `.blur` above ≈ 5 px the vector comes from the CalibrationResult, never from our model, so this is how the app answers "box³ or truncated Gaussian?" without taking sides or answering circularly (E §7.1). A unit test asserts that no Tier S card field is LIVE.
12. **Field guide ›** opens the Field guide sheet on this blur.

System blurs use the same card with different badges: SwiftUI `.blur`'s PSF row is MEASURED · OFFSCREEN with the device name and path (`ImageRenderer`), its internals INFERRED.

### 7.2 Unique numbers (examples; `BlurCore` computes each at the current parameters)

| Entry | UNIQUE | Badge, source |
|---|---|---|
| `box-blur` | minimum of H **−0.217** (continuous sinc; discrete −0.333 at w 3 … −0.219 at w 21): a positive kernel that inverts stripes | COMPUTED, CAT §5.2 |
| `tent-blur` | minimum of H **0**: zeros but never inversion (H = sinc² ≥ 0) | COMPUTED |
| `binomial-blur` | H at Nyquist **exactly 0** (a sampled Gaussian at σ 1 with r = 3 leaves **1.41 %**; the continuous Gaussian would leave 0.72 %) | COMPUTED, JT note (f) |
| `iterated-box` (n = 3) | residual inversion **−1.0 %** (−1.03 % continuous; −1.16 % for three boxes of width 9) | COMPUTED, CAT P3 |
| `gaussian-blur` | excess kurtosis on the axis **= at 45° = 0 while separable**: separable and isotropic at once, which only the Gaussian is (Herschel 1850 / Maxwell 1860). Kurtosis 0 alone does not identify a Gaussian | COMPUTED, CAT E17 |
| `iir-gaussian` | Young–van Vliet moment σ **5.56** at nominal 5 (+11 %) | COMPUTED, CAT §5.2 |
| `kawase-blur` {0,1,2,2,3} | hollow centre **0.0645 < 0.0674** (the ±2 maximum); σ 5.34 for 20 fetches | COMPUTED, CAT E14 |
| `dual-kawase` | ≈ **12.3** fetches per pixel at any size; shift variance 3.7–8.5 % at offset 2 | COMPUTED/MODELED, CAT §5.2, LSI §13 |
| `pyramid-blur` (mip chain) | PSF centroid snaps up to **±7.5 px** at L = 4 | COMPUTED, CAT P7 |
| `exponential-blur` | excess kurtosis **+3**: all tail, no shoulders | COMPUTED |
| `lorentzian-blur` | variance **∞**; 1.3 % of the light lies beyond 50γ | COMPUTED, CAT §5.2 |
| `frequency-lowpass` (ideal) | Gibbs overshoot **8.9 %** | COMPUTED, CAT §5.2 |
| `linear-motion-blur` | zero lines every **1/L** across the motion | COMPUTED |
| `radial-zoom-blur` | a centred star passes **unchanged** (1.000 → 1.000) | COMPUTED, §5.3 B |
| `spin-blur` | the 36-cycle star turns uniformly grey at **10°** (360°/n_c) | COMPUTED, CAT E7 |
| `disc-blur` | first zero **0.6098/R**; deepest lobe **−0.1323** | COMPUTED, CAT §5.2 |
| `polygonal-bokeh` | **4n vs ≈ 2.6n²** fetches (64 vs 665 at R = 16) | COMPUTED, §5.3 D |
| `bilateral` | far-side weight **9.4 %** vs Gaussian 43.3 % at the fixture step | COMPUTED, §5.3 C |
| `median` | impulse error **0.000** on 10 % salt-and-pepper text | COMPUTED, CAT P14 |
| `frosted-glass-noise` | **2** fetches; one realization adds high-frequency energy (8.4 % above 0.25 c/px vs 2.0 % in the input) | COMPUTED, CAT P24 |
| `swiftui-layer-blur` | σ ≈ **0.90·r·scale** above ≈ 5 device px | MEASURED · OFFSCREEN (macOS 27.2) until this phone measures it, CAL §5.1 |
| `heat-equation` | **σ = √(2t)** | COMPUTED, CAT E9 |
| `unsharp-mask` | gain **1.35** at Nyquist (σ 0.5, k 0.5): not a blur | COMPUTED, CAT §5.2 |

### 7.3 Where the card appears

- **Fingerprint sheet** (full card), from the kernel well or `Full card ›`.
- **Bench, below the fold** (compact card, ≈ 236 pt): header line, signature, the four-glyph strip, UNIQUE, `Full card ›`.
- **Catalog › Fingerprints** (the matrix, §4.5) and **Catalog › Blurs** rows (glyph + signature).
- **Layers**: each floor page header shows the signature line only.

### 7.4 The fingerprint vector (what the matrix sorts by and LOOKS MOST LIKE compares)

Computed by `BlurCore` for every entry at a reference size σ_equiv = 4 px (equal second moment, CAT §7 convention), and measured from GPU output for ON THIS PHONE: excess kurtosis on the axis and at 45° (separable vs isotropic signature), minimum of H, first zero frequency, support at 10⁻⁴ of peak over σ, LSI class, cost exponent (fetches ∝ r^p), shift variance (edge-centre spread over 4 phases). Blank cells read `— NOT YET COMPUTED` rather than an estimate (D R14).

## 8. Comparison

### 8.1 σ-hold: switching is a comparison (I §8.1, JD G3, JF G-14)

When the blur strip (or the Catalog) switches blurs, Blur2ool keeps the **per-axis second moment σ** of the PSF and converts it into the new blur's own primary parameter. What changes on screen is the blur's *character*, never its size (JD M5). The status row reports the conversion for 2 s; when the new parameter is an integer, the residual is stated (`σ HELD 4.0 px → r 3 (w 7, σ 2.00)`… or the nearest odd width with `Δσ −0.26 px`). **When the converted parameter hits its range limit, the hold is partial and says so** (review fix P-38; Metro §16): `holdingSigma` returns the achieved σ and the line names the limit, e.g. at the default σ 12: `σ HELD 12.0 px → σs 8.0 px (MAX) · Δσ −4.0 px` (bilateral, σs ≤ 8), `σ HELD 12.0 px → a 16 (MAX) · σ 9.52 px` (frosted glass, a ≤ 16), `σ HELD 12.0 px → r 10 (MAX) · σ 6.06 px` (guided, `CIGuidedFilter`'s maximum), `σ HELD 12.0 px → SEQUENCE 0 1 2 3 4 · σ <achieved> px` (Kawase: the nearest preset, never hidden). Every entry has CORE tests of its conversion at σ 12 and σ 64. Conversions are COMPUTED in `BlurCore` (LSI §20, STACK §8):

| New blur | Parameter from the held σ (px) |
|---|---|
| `box-blur` | w = nearest odd integer to √(12σ² + 1); r = (w − 1)/2 (σ 12 → w 41, r 20, σ 11.83) |
| `tent-blur` | r = round(√(6σ² + 1) − 1) (σ² = r(r + 2)/6; σ 12 → r 28, σ 11.83) |
| `iterated-box` (n passes) | Kovesi split of widths for n passes; achieved σ shown |
| `gaussian-blur`, `anisotropic-gaussian` (along), `iir-gaussian`, `unsharp-mask`, `difference-of-gaussians` (inner), `tilt-shift` (max), `variable-progressive-blur` (max) | σ |
| `binomial-blur` | n = round(4σ²); refused above σ 4 with `σ TOO LARGE FOR BINOMIAL · MAX 4.0` |
| `disc-blur` | R = 2σ |
| `polygonal-bokeh` (6 blades) | R = σ·√(24/5) = 2.191σ (σ 12 → R 26.3) |
| `exponential-blur` (separable) | b = σ/√2 |
| `lorentzian-blur` | infinite variance: hold **FWHM** instead, γ = 1.1774σ, and say `FWHM HELD` |
| `linear-motion-blur` | L = √(12σ² + 1) along the current angle |
| `kawase-blur`, `dual-kawase`, `pyramid-blur`, `bloom` levels | nearest preset (sequence / levels + offset); the achieved σ is shown, never hidden |
| `swiftui-layer-blur` | r (pt) = σ/scale while σ ≤ 5 px; σ/(0.90·scale) above (macOS law, MEASURED offscreen, until the device measures its own; SwiftUI's kernel shape differs from a Gaussian, so the line adds `SAME σ, DIFFERENT KERNEL`) |
| `heat-equation` | t = σ²/2 |
| `frequency-lowpass` | Gaussian shape: D₀ = 1/(2πσ); ideal and Butterworth: D₀ so the half-amplitude frequency equals 0.1874/σ |
| `bilateral`, `joint-bilateral`, `domain-transform`, `surface-blur` (spatial) | σs = σ (the range parameter keeps its last value) |
| `guided` | r = round(√3·σ) (box of width 2r + 1 has σ² = r(r + 1)/3) |
| `frosted-glass-noise` | a = round((√(1 + 12σ²) − 1)/2) (expected σ² = a(a + 1)/3) |
| `css-backdrop-filter` (model) | typed CSS px = σ/scale |
| `drop-shadow` | typed value from the selected tool convention (σ = v/2 for CSS box-shadow; σ = v for CSS drop-shadow(); …) |
| `median`, `kuwahara`, `morphology`, `pixelate`, `radial-zoom-blur`, `spin-blur`, `path-blur`, `cats-eye-swirl-bokeh`, `depth-of-field-coc`, `velocity-buffer-motion-blur`, `temporal-accumulation`, `camera-shake-blur`, `god-rays`, `nonlocal-means`, `perona-malik`, `diffraction-airy`, materials and glass | no σ exists: the blur opens at its own last value and the status row says `σ NOT DEFINED · RANK FILTER`, `· SPACE-VARIANT`, `· NONLINEAR` or `· SYSTEM MATERIAL` |

`MATCH σ` (Settings, on by default; also in Compare's B menu) turns σ-hold off for the "radius 10 in every tool" lesson.

### 8.2 Compare mode: hold everything, vary one thing (E §8, JD G16, JF G-16)

Compare holds two configurations over **one** specimen and **one** probe: A (current; crowns drive it) and B. The compare bar (§4.2) has three menus:

- **AXIS** decides the one field B may differ in; the **B** menu lists only legal choices for that axis.

| Axis | B may differ in | Matching rule | Typical lessons |
|---|---|---|---|
| **Operator** (default) | the catalog entry | `σ` (default, §8.1) · `FWHM` · `10–90 % edge width` · `Cost` (equal MEASURED full-resolution ms within ±5 %, found by bisection over B's primary parameter; "what does each blur buy for 0.5 ms?"; unavailable in the Simulator) | P1, P2, P6, P11, P20, P21 |
| **Implementation** | A's variant (2-D, separable, linear-sampled, IIR, compute tile, SAT, sliding sum, row-span, complex-separable, stochastic, grid, separable bilateral…), or the **CPU reference** (`BlurCore`, Double) | same operator and parameters | P4, P5, P7, P12; GPU vs CPU parity |
| **Precision** | accumulator (`fp32` / `fp16`), intermediate (`rgba16Float` / `rgba8Unorm`), SAT (`fp32` / `mean-centred`) | same kernel | fp16 accumulation (up to 6 LSB for running sums, MEASURED M1 Max); SAT corner error |
| **Space** | colour space (`Linear light` / `sRGB-encoded`), alpha (`Premultiplied` / `Straight`) | same kernel | P18, P19 |
| **Apple** | Apple's in-process twin (Core Image, MPS, vImage, run on this phone and read back: LIVE/MEASURED) or SwiftUI's system blur (on screen, plus offscreen `ImageRenderer` fits) | parameters from the latest Calibrate fit, or the API's documented mapping with its badge | P26; `CIMotionBlur` (Gaussian) vs our box motion blur; `CIZoomBlur` (outward) vs our zoom; `CIBoxBlur` width rule |

- **VIEW**: `Wipe` · `Flip` · `Difference ×1 / ×16 / ×256` · `Line-up` (triads only, §8.3).
- **Default B** when he taps `Compare`: the blur he just left, on the Operator axis, σ-matched. From a lesson: the lesson's B.
- **Driving B.** Crowns and Steppers drive A. A segmented control **`DRIVE  A · B`** (44 tall) at the top of the compare bar's B menu and of the Parameters panel switches the crowns and Steppers to B (`DRIVING B` in the status row) and back; the image element also has the accessibility actions `Drive A` / `Drive B` (review fix P-46: no gesture-only control). `Swap` exchanges A and B.
- **Thermal honesty.** ΔGPU is shown only from interleaved ABAB timing runs; if the thermal state changed between A's and B's runs the column keeps its value and adds `THERMAL CHANGED` (E §4.2).

### 8.3 Views (inside the image window only)

| View | What it shows | Interaction | Badges |
|---|---|---|---|
| **Wipe** (default) | B left, A right, split at 50 % | 44 × 298 divider owns its drag; adjustable ±10 % | images LIVE |
| **Flip** | the whole window shows A; press and hold the `B` engraving to show B; release returns to A | hold-to-show only; an optional `Flicker 2 Hz` (≤ 2 changes/s, below WCAG's three flashes) is off by default and unavailable under Reduce Motion; VoiceOver: a toggle | LIVE |
| **Difference** | \|A − B\| × gain as a luminance ramp (not colour alone) with numeric contours; status row `MAX 6 LSB · RMS 0.8 LSB · ×16` | the probe reads the local difference; `Jump › Worst parity pixel` moves to the maximum | LIVE (MAX, RMS); MEASURED when B is the CPU reference (parity) |
| **Line-up 2 × 2** | four quadrants of 149 × 149 pt (447 × 447 px), each the central 447-px crop of one blur's full-size output; engraved letter and name in a 14-pt band at each quadrant's top edge, outside the pixels | tap a quadrant to make it the kernel well's subject; the hero drives all four (σ-held); the pills show only the tapped quadrant against A (solid vs dashed), because four traces in a 26-pt pill interior are unreadable | LIVE; status row shows the distinguishing number for all four, from the kernels as run (`MIN H  A −0.217 · B 0 · C −0.0012 · D −0.132`) |

Line-up is reachable only from Lessons for the catalog's triads and tetrads whose members all run live (P2, P3, P7, P11, P14, P25, P29, P30) and from Catalog › Fingerprints when three or four rows are selected (JF M-18: no general 4-up with seven B sources).

### 8.4 Where two blurs part ways (divergence; D W6, §9; JD G13)

For any pair, `BlurCore` compares the two configurations floor by floor and names the **first floor where they differ** with a one-line reason. Each floor has a comparison key computed from data, never hand-labelled per pair:

| Floor | Same when |
|---|---|
| 1 SLIDE | the typed value in the home tool's convention is equal at display precision. When either blur is **not offered by the home tool**, the floor reads `≠ · NOT IN <TOOL>` (e.g. `NOT IN SWIFTUI` for a box blur) and is skipped when naming the first difference |
| 2 API | the API tuple **normalised to per-axis σ** (each blur's primary converted to the σ it produces, equal within 3 %, the σ-hold residual) plus colour space, edges and alpha is equal. Blurs without a σ compare their primary in its own unit |
| 3 MATH | the continuous operator id and its parameters are equal (e.g. "Gaussian, σ 4.0") |
| 4 KERNEL | the effective discrete 2-D PSF at the current parameters is equal within 10⁻⁹ (LSI); for NL classes, the weight rule and its parameters |
| 5 ALGORITHM | the pass graph (algorithm id, pass count, per-pass structure) is equal |
| 6 GPU | the kernel functions and fetch pattern (integer vs bilinear taps, tile shape) are equal |
| 7 PIXEL | max \|A − B\| ≤ 1 fp16 ulp → `≈ same`; otherwise `differs` with the max in 8-bit steps |

Where it appears: the rail in Compare mode (`=`/`≠`, first `≠` amber with ▶), Catalog › Divergence (all seven rows), the fingerprint card's PARTS WAYS line, and the status row in Compare (`PARTS WAYS AT MATH`). Reference rows (COMPUTED from the catalog's structure; acceptance fixtures for the divergence function):

| A vs B | First floor where they differ | Why, in one line |
|---|---|---|
| `gaussian-2d-direct` vs `gaussian-separable` | ALGORITHM | same kernel; 625 vs 50 taps at σ 4; pixels equal to ≤ 1 LSB (P4) |
| `gaussian-separable` vs `gaussian-linear-sampling` | GPU | same passes; 25 integer vs 13 bilinear fetches per pass; pixels differ only by the hardware's 8-bit sub-texel weights |
| `gaussian-blur` vs `heat-equation` | KERNEL | same continuous operator (σ = √(2t)); explicit 5-point steps are a different discretisation (at λ = ¼ the PSF lives only on even-parity pixels; §17 item 1) |
| `gaussian-blur` vs `iir-gaussian` | KERNEL | the recursion's impulse response has exponential tails; Young–van Vliet moment σ 5.56 at nominal 5 |
| `box-blur` vs `gaussian-blur` (equal σ) | MATH | rect vs bell; minimum H −0.217 vs > 0 (P1) |
| `iterated-box` (n = 3) vs `gaussian-blur` | MATH | piecewise quadratic vs bell; −1 % inversion left (P3) |
| `kawase-blur` vs `gaussian-blur` | MATH | the chain's effective PSF has a hollow centre (0.0645 < 0.0674) and min H −0.047 |
| `box-blur` (separable) vs `box-blur` → `sat-box` | ALGORITHM | same box; two passes vs scan + 4-read query |
| CSS `blur(10px)` vs SwiftUI `.blur(radius: 10)` | API | same word, but σ 30 vs ≈ 27 device px at scale 3 (CSS σ = value, REFERENCE; SwiftUI σ ≈ 0.90·r·scale, MEASURED offscreen on macOS); then MATH: Gaussian vs a kernel with excess kurtosis −0.45 (MEASURED macOS), closest model box³ (INFERRED). Blend space: CSS gamma-space (REFERENCE); SwiftUI gamma-space offscreen (MEASURED), on screen INFERRED |
| Figma layer blur 10 vs CSS `blur(10px)` | SLIDE | same word, σ 5 vs 10 (Figma rule INFERRED, STACK §4.1) |
| same blur, linear vs sRGB-encoded | API | a silent parameter; stripes 0.735 vs 0.500 encoded; 179 vs 115 at the Gaussian probe |
| `radial-zoom-blur` vs `spin-blur` | MATH | scaling vs rotation about the centre; exact duals (P21) |
| `disc-blur` vs `polygonal-bokeh` | MATH | aperture shape; then ALGORITHM (2-D gather vs four line passes) |
| `bilateral` vs `gaussian-blur` | MATH | the range term; they meet again as σr → ∞ |
| `bilateral` vs `guided` | MATH | weighted average vs local linear regression; no gradient reversal for guided (P15) |
| `median` vs `bilateral` | MATH | rank vs weighted average; impulses deleted vs kept (P14) |

### 8.5 Lessons (Catalog › Lessons; JD G17)

**Guided descents** (each sets the state and pushes the Trace; titles are hooks): A `One pixel through a Gaussian` (15 steps, step edges) · B `Why zoom blur spares a star` (Siemens star) · C `The blur that looks before it averages` (noisy step) · D `Four line blurs make a hexagon` (Night City). Set-ups and numbers: §5.3.

**Pairs that teach** (CATALOG §7, P1–P30): each row sets specimen, A, B (or a triad), axis, view, σ and probe, and writes its look-for line into the status row until a control changes. Numbers keep their source badges; corrections from §17 are applied.

| # | Lesson | View | Look for (badge) |
|---|---|---|---|
| P1 | Box vs Gaussian at equal σ | Wipe, star | reversed spokes inside a grey null ring; min H −0.217 vs > 0 (COMPUTED) |
| P2 | Box vs tent vs Gaussian | Line-up, star | −0.217 · 0 (zeros, no inversion) · > 0 (COMPUTED) |
| P3 | Iterated box n = 1, 2, 3, 4 | Line-up, impulse | shape error, defined as the relative L2 distance ‖boxⁿ − G‖₂ / ‖G‖₂ between the continuous n-fold box and the Gaussian of equal variance: **38 % → 8.8 % → 4.8 % → 3.4 %** (COMPUTED in review round 1; the max-abs-over-peak definition gives 50 / 7.8 / 6.0 / 3.5 %); excess kurtosis −1.2/n; n = 3 keeps −1.0 % inversion (COMPUTED). FAM-F1 recomputes both definitions in BlurCore; the discrete values at the lesson's width are UNVERIFIED until then |
| P4 | 2-D vs separable Gaussian | Difference ×256 | ≤ 1 LSB; **2,401 vs 98 taps at σ 8** (COMPUTED; the 2-D variant is disabled above σ 8, §9.4); the half-blurred streak after pass H |
| P5 | Separable vs linear-sampled | Difference ×256 | 61 → 31 fetches per pass at σ 10 (COMPUTED); difference = sub-texel precision (MEASURE on this phone) |
| P6 | Kawase vs Gaussian | Wipe, Night City | hollow centre 0.0645 < 0.0674; min H −0.047; 20 vs 38 fetches (COMPUTED) |
| P7 | Mip chain vs CoD 13-tap vs dual Kawase | Line-up, moving light (pan) | ±7.5 px snap vs ≤ 2.3 % vs 3.7–8.5 % (COMPUTED) |
| P8 | Binomial vs Gaussian (σ 1) | Wipe + loupe, 1-px checkerboard | binomial leaves **0**; the sampled Gaussian (r = 3) leaves **1.41 %** (COMPUTED; §17 item 6) |
| P9 | Gaussian discretisations at σ 0.3–0.7 | Implementation axis, impulse | sampled σ 0.3 → true 0.088; Lindeberg 0.300 (COMPUTED) |
| P10 | IIR vs Gaussian | Wipe, HDR light (log) + edge bar | σ +11 % at 5 (5.56); exponential tails; boundary transient (COMPUTED) |
| P11 | Disc vs hexagon vs Gaussian | Line-up, Night City | round inversion rings (−0.132 at 0.817/R) · six-fold zeros, straight edges · soft balls (COMPUTED) |
| P12 | Disc exact vs complex-separable (1, 2) vs stochastic | Implementation axis, one HDR light | ripple ±23 % (1 component), ±7.6 % (2); spiral grain converging with S (COMPUTED) |
| P13 | Bilateral vs Gaussian | Wipe, noisy steps | far-side weight 9.4 % vs 43.3 %; 0.581 vs 0.513 (COMPUTED) |
| P14 | Median vs bilateral vs Gaussian | Line-up, salt-and-pepper text | max error 0.000 · impulses kept · 0.183 at σ 1 (COMPUTED) |
| P15 | Bilateral vs guided, detail boost 4 | Wipe, noisy step | reversed gradient vs none (COMPUTED) |
| P16 | Heat equation vs Gaussian | Wipe, impulse over t | σ = 1.4142, 2, 3, 4, 5 at t = 1, 2, 4.5, 8, 12.5; at λ = ¼ a 1-px checkerboard flips sign every step and never fades (COMPUTED) |
| P17 | Heat vs Perona–Malik (+ TV atlas page) | Wipe, noisy step and ramp | heat blurs the step; Perona–Malik keeps it and terraces the ramp; TV (Tier 3 page) loses disc contrast 2λ/R (COMPUTED) |
| P18 | sRGB-encoded vs linear-light blur | Space axis, stripes | stripes average 0.500 vs 0.735 encoded (COMPUTED; matches MEASURED CSS/SwiftUI/CI behaviour) |
| P19 | Premultiplied vs straight alpha | Space axis, shape on transparent | at the 50 % pixel over white, composited in linear light (the app's default) and encoded: (255, 188, 188) vs (225, 188, 188); composited in encoded space, as CSS and most tools do: (255, 128, 128) vs (191, 128, 128) (COMPUTED; the row states which) |
| P20 | Box motion vs directional Gaussian | Wipe, impulse grid | hard-ended streaks and zero lines at k/L vs soft ends, no zeros; `CIMotionBlur` is the Gaussian one (MEASURED) |
| P21 | Zoom vs spin, centred | Wipe, star then zone plate | zoom: star untouched; spin: star grey at 360°/n_c = 10°, inverted beyond: the continuous arc-average (a sinc in the angle) reaches **−0.2172 at 1.430 periods** (COMPUTED); the discrete 32-sample value (first draft: −0.216 at 1.39) is UNVERIFIED until FAM-F5A recomputes it |
| P22 | Velocity buffer vs frame accumulation | Wipe, moving disc | accumulation exact (static parts pixel-identical) but ghosts at low N; velocity buffer under-blurs where motions conflict |
| P23 | Variable blur: mip mix vs per-pixel Gaussian | Wipe + `CIMaskedVariableBlur` (Apple axis) | naive blend 11.8 % too wide at t = 0.5; variance-matched mixture still has excess kurtosis +1.5 vs 0 (COMPUTED) |
| P24 | Frosted glass 1 vs N realizations vs box | Wipe, step edge and text | one realization adds energy above 0.25 c/px (8.4 % vs 2.0 %); the mean converges to the box (COMPUTED) |
| P25 | Gaussian vs unsharp mask vs Wiener | Line-up, blurred text | USM boosts highs up to 1 + k; deconvolution gain at Nyquist for a σ 1 blur: **inverse filter (K = 0): 139**; **Wiener at K = 10⁻² (default): 0.72**; at K = 10⁻⁴ (minimum): 47 (continuous Gaussian response 7.2·10⁻³; with the app's sampled r = 3 kernel, H(0.5) = 1.41 % gives 71, 1.38 and 47). The inverse filter fails at box and disc zeros and explodes noise; Wiener's K caps the gain (COMPUTED). The Wiener entry offers `K = 0 (inverse filter)` as its first detent so the 139 can be seen |
| **P26** | **SwiftUI `.blur` vs our Gaussian vs iterated box (flagship)** | Apple axis wipe, impulse and step under a radius sweep | σ ≈ r below ≈ 5 px; σ ≈ 0.90·r above with excess kurtosis −0.45 (both MEASURED offscreen on macOS; closest model box³, INFERRED), sub-pixel edge wobble (MEASURED macOS); **re-MEASURED on this phone** by Calibrate, MEASURED · OFFSCREEN |
| P27 | Drop shadow, the same "10" in each tool | Operator axis over conventions, square and star | σ = 5 (CSS box-shadow), 10 (CSS drop-shadow()), ≈ 4.4 (Figma, third-party MEASURED); `CALayer.shadowRadius`: `SOURCES DISAGREE` (σ = r/2 per STACK vs ≈ 0.9·r per CAL) until this phone measures it (§17 item 7); while they disagree the image renders the σ = r/2 law engraved `MODELED · σ = r/2 (ONE OF TWO SOURCES)`, with a toggle to the other law |
| P28 | Apple material vs Liquid Glass vs CSS backdrop model | exhibit wipe (§4.1.9 g) | materials look mostly like colour stages (INFERRED); glass looks mostly like refraction (INFERRED); our reconstructions MODELED · STRUCTURE INFERRED; CSS: σ = typed value, sRGB, mirrored edges (REFERENCE) |
| P29 | Bloom vs Gaussian vs Lorentzian | Line-up, Night City at several exposures | Gaussian dims lights; bloom adds a halo with tail slope −2.0; Lorentzian lifts the black level (COMPUTED) |
| P30 | Median vs dilate vs erode | Line-up, Night City and text | median keeps edges in place; dilation grows lights into crisp discs; erosion shrinks them |

## 9. Per-family control mapping

### 9.1 Control grammar

- **Magnitudes** (σ, radius, length, strength, angle, threshold, cut-off) use **crowns** (`InstrumentCrown`), each between real 44 × 44 glass ± `Button`s with an `accessibilityAdjustableAction` of the same step. **Counts** (passes, levels, samples, iterations, blades, taps, realizations) use the native **`InstrumentParameterStepper`** (precise small integers, native hold-repeat, Metro contract A.7). **Choices** use a native `Picker(.segmented)` (2–4 options, 32 tall) or a native `Menu` (5+ options, 44 tall). **Positions** use on-image handles with Stepper twins. There is **no `Slider`** anywhere (D §10.1: a slider has no detent vocabulary and its thumb is a gesture-only target).
- **Every parameter also appears in the Parameters panel** (below the fold) with a native accessible control: the primary's `DecimalParameterStepper` / `InstrumentParameterStepper` twin first (JF G-11, M-13).
- **Display precision = spoken precision = the fine step** (Metro contract A.6, §4). Integers show whole numbers with their noun (`32 samples`, `3 passes`), never decimals.
- **One crown pair on screen at most.** Never a second pair, never crowns below the fold.
- **The deck never collapses.** Each blur declares one arrangement in `BlurCore`; the 98-pt slot is reserved even when an arrangement uses less (JF G-13).
- **Ranges are design choices** for an 894-px specimen, bounded by research where a source exists (threadgroup budgets, CI limits, Tier 1 brute-force limits) and by the **fetch budget** of §4.1.6 (full renders ≤ 2·10⁹ texture fetches per frame; MODELED, UNVERIFIED until This phone measures it); they are not facts about other tools. Where a range would cross the budget, the entry's row below says what happens there (an automatic variant switch with its reason, or the end of the range).

**Deck arrangements** (98-pt slot, centred, max width 380 for Steppers):

| Arr. | Contents (left → right) | Geometry | Used for |
|---|---|---|---|
| **A** | FINE crown (cyan, 8° = one fine step) + SEMANTIC crown (amber, 20° = one named stop) on the **same** parameter | two 162-wide groups, gap 24 | continuous magnitude with named stops |
| **B** | FINE crown (magnitude) + ANGLE crown (cyan, 8° = 1°, semantic snaps at 0/45/90/135° or the blur's symmetry stops) | as A | directional blurs |
| **C** | FINE crown (parameter 1, cyan) + a second crown (parameter 2, amber caption with its own name and detents) | as A | two continuous parameters |
| **D** | FINE crown (magnitude) on the left; on the right a column: `InstrumentParameterStepper` 48 tall (≤ 170 wide) above a `Picker(.segmented)` or `Menu` 32–44 tall | 162 + 24 + ≤ 170 | magnitude plus a count and/or a mode |
| **E** | no crown: a row of `InstrumentEventTiles` (37 tall) or a segmented picker (32) above an `InstrumentParameterStepper` (48) | ≤ 380 wide | sequence-defined blurs, named primaries, counts as primaries |

### 9.2 Detent vocabulary (one row per quantity; a new blur reuses a row)

| Quantity | Unit | Fine step (8°) | Display | Semantic stops (20°) and meaning bands | Range |
|---|---|---|---|---|---|
| σ, disc R, polygon circumradius R, decay b, half-width γ | px | 0.1 | 1 dp | 0.5 · 1 · 2 · 4 · 8 · 16 · 32 · 64; bands *Sub-pixel* < 0.5 · *Anti-alias* 0.5–1.5 · *Softened* 1.5–4 · *Frosted* 4–12 · *Backdrop* 12–32 · *Fog* ≥ 32 (Blur2ool's own words) | per entry, within 0.3–64.0 |
| Integer radius (box, tent, median, Kuwahara, guided, morphology), cell size | px | 1 | integer | octave stops 1 · 2 · 4 · 8 · 16 · 32 · 64 (where in range) | per entry |
| Line length L | px | 0.1 | 1 dp | 2 · 4 · 8 · 16 · 32 · 64 · 128 | 1.0–128.0 |
| SwiftUI radius | pt | 0.1 | 1 dp | 0.5 · **1.7** · 3 · 5 · 10 · 20; the 1.7-pt stop is the regime switch (≈ 5 device px at scale 3), drawn as a hollow INFERRED detent until this phone measures it, then moved to the MEASURED value (band *Regime switch*); the only non-octave stop in the app | 0.0–20.0 |
| Angle (direction, rotation) | ° | 1 | integer | 0 · 45 · 90 · 135 (direction: 0–179); polygon rotation: multiples of 15° within its symmetry period 0–(360/n − 1) | per entry |
| Spin angle Θ | ° | 0.5 | 1 dp | multiples of 360°/n_c for the current star (10° for 36 cycles: the star turns grey on every detent), else 2.5 · 5 · 10 · 20 · 45 · 90 | 0.0–360.0 |
| Zoom strength a | % of distance | 0.5 | 1 dp | 2.5 · 5 · 10 · 20 · 40; bands *Drift* < 5 · *Rush* 5–25 · *Warp* > 25 | 0.0–50.0 |
| Range σr | fraction of full scale (in the active colour space) | 0.01 | 2 dp | 0.01 · 0.02 · 0.05 · 0.10 · 0.20 · 0.50 · 1.00; bands *Edge-locked* < 0.05 · *Edge-aware* 0.05–0.3 · *Nearly Gaussian* > 0.3 | 0.01–1.00 |
| Cut-off D₀ | c/px | 0.005 | 3 dp | 0.010 · 0.025 · 0.050 · 0.100 · 0.250 · 0.500 | 0.005–0.500 |
| f-number | stop | ⅓ stop | named (`f/2.8`) | whole stops f/1.4 · 2 · 2.8 · 4 · 5.6 · 8 · 11 · 16 · 22 | per entry |
| Log quantities (ε, noise-to-signal K) | — | three detents per decade (1 · 2 · 5) | 2 significant digits | one per decade | per entry |
| Exposure | EV | 1 | integer, signed | — | −2 … +6 |
| Diffusion time t | (px²) | 0.5 | 1 dp; meaning line `σ = √(2t) = 4.00 px` | t = σ²/2 for σ = 1 · 2 · 4 · 8 · 16 | 0.0–200.0 |

### 9.3 The silent parameters (every blur; Parameters panel › EVERY BLUR; Settings holds their defaults)

These are the API floor's invisible choices; the Trace offers each as a branch (§6.3).

| Parameter | Control | Options | Default | Why it is global |
|---|---|---|---|---|
| Colour space | segmented | `Linear light` · `sRGB-encoded` (encode before the blur, decode after) | Linear light | 0.735 vs 0.500 on stripes; 179 vs 115 at the Gaussian probe; the hexagon nearly vanishes in encoded space (§5.3) |
| Edges | segmented + `⋯` Menu | `Clamp` · `Mirror` · `Wrap` · `Zero` (+ `Renormalise` for FIR blurs) | Clamp | CSS backdrop mirrors; SwiftUI `opaque: false` and Core Image are transparent unless clamped (STACK §3, CAL §5) |
| Alpha | segmented | `Premultiplied` · `Straight` | Premultiplied | P19 dark fringes |
| Precision | segmented | `fp32 accumulate` · `fp16 accumulate` (intermediates `rgba16Float` either way; `rgba8Unorm` intermediates only on the Compare › Precision axis) | fp32 | GPU §3.8 error budget; parity |
| Preview | segmented | `Reduced while moving` · `Always full` | Reduced while moving (only heavy blurs and configurations above the preview budget use it, §4.1.6; rank filters never do) | live feel at 120 Hz |

### 9.4 Per-entry mapping

Columns: **Deck** (§9.1) · **Primary** (label, unit, range, fine step, default when opened without σ-hold) · **Deck partner** (second crown / Stepper / picker in the deck) · **Parameters panel extras** (besides the primary's twin and the silent parameters) · **Variant picker** · **Handle** · **Default specimen** (§11). Tier per §10.

**F1 · Box, tent & running sums**

| Entry | Deck | Primary | Deck partner | Parameters extras | Variant picker | Handle | Specimen |
|---|---|---|---|---|---|---|---|
| `box-blur` | D | RADIUS r · px · 1–64 · 1 · **6** (status `w 13 · σ 3.74 px`) | ALGORITHM `Separable · Sliding sum · SAT` | — | (in deck) | — | Siemens star |
| `tent-blur` | D | RADIUS r · px · 1–64 · 1 · **5** (status `σ = √(r(r+2)/6)`) | ALGORITHM `FIR · Stack blur` | — | (in deck) | — | Siemens star |
| `iterated-box` | D | TARGET σ · px · 0.5–64.0 · 0.1 · **4.0** (status shows the *achieved* σ) | PASSES Stepper 1–6 · **3** | WIDTH RULE Menu `Equal · Kovesi split · SVG three-box · Extended (fractional)` | — | — | Night City |

**F2 · Gaussian & approximations**

| Entry | Deck | Primary | Deck partner | Parameters extras | Variant picker | Handle | Specimen |
|---|---|---|---|---|---|---|---|
| `gaussian-blur` | A | SIGMA σ · px · 0.3–64.0 · 0.1 · **12.0** | SEMANTIC octave stops | TRUNCATION `2 · 2.5 · 3 · 4` × σ (3); DISCRETISATION `Sampled · Integrated · Lindeberg` (all run on the GPU as weight tables) | Menu `2-D direct · Separable · Linear-sampled · Compute tile` (2-D disabled above σ 8: "2,401 taps per pixel", 1.9·10⁹ fetches per frame, just under the full budget; the compute tile is a 256 × 1 row tile with (256 + 2r) × 8 B of dynamic threadgroup memory, which fits 16 KB up to r = 896, so every σ in range) | — | Night City (Bench), step edges (descent A) |
| `binomial-blur` | A | ORDER n · taps − 1 · 2–64 · 2 · **4** (status `n+1 TAPS · σ = √n/2`) | SEMANTIC n = 2 · 4 · 8 · 16 · 32 · 64 | — | single variant (picker hidden) | — | 1-px checkerboard |
| `iir-gaussian` | D | SIGMA σ · px · 0.5–64.0 · 0.1 · **5.0** | FORM Menu `YvV 3rd order · Deriche 2 · Deriche 3 · Deriche 4` | BORDER INIT `Zero · Steady state` | — | — | edge bar |

**F3 · Pyramids & Kawase**

| Entry | Deck | Primary | Deck partner | Parameters extras | Variant picker | Handle | Specimen |
|---|---|---|---|---|---|---|---|
| `kawase-blur` | E | PASSES Stepper 1–8 · **5** (status `σ 5.34 px · 20 FETCHES`) | event tiles: one per pass, showing its offset (tap cycles 0–7); at most 8 tiles, so they always fit | SEQUENCE Menu `0 1 2 2 3 (Intel 2014) · 0 1 2 3 4 … · 2 3 3 3 · Custom` (every preset has ≤ 8 passes, matching PASSES 1–8; the first draft's 17-pass preset is dropped) | — | — | Night City |
| `dual-kawase` | D | OFFSET o · texel · 0.5–4.0 · 0.1 · **1.0** | LEVELS Stepper 1–6 · **3** | shift-variance readout (8.5 / 4.3 / 3.7 % at o 2, L 2–4) | — | — | text (pan to see shimmer) |
| `pyramid-blur` | E | LEVELS Stepper 1–6 · **4** | segmented `Mip chain · CoD 13-tap · Unity 13-tap` | LOD BIAS DecimalStepper 0.0–6.0 · 0.1 (mip chain only) | (in deck) | — | moving point light (pan) |

**F4 · Kernel shapes & the frequency domain**

| Entry | Deck | Primary | Deck partner | Parameters extras | Variant picker | Handle | Specimen |
|---|---|---|---|---|---|---|---|
| `exponential-blur` | C | DECAY b · px · 0.5–64.0 · 0.1 · **4.0** | second crown EXPOSURE · EV · −2…+6 · 1 (a specimen parameter: tails show at high exposure) | — | `Separable (diamond) · Isotropic` | — | Night City +4 EV |
| `lorentzian-blur` (T2) | C | HALF-WIDTH γ · px · 0.5–32.0 · 0.1 · **4.0** (meaning line: the 50 %-energy radius, not a σ) | EXPOSURE crown | TERMS Stepper 2–6 | `Sum of Gaussians · FFT` | — | Night City +5 EV |
| `frequency-lowpass` (T2) | D | CUT-OFF D₀ · c/px · 0.005–0.500 · 0.005 · **0.050** | SHAPE `Ideal · Butterworth · Gaussian` + ORDER Stepper 1–20 (Butterworth only) | — | (in deck) | — | step edge |
| `fft-convolution` (T2) | D | SIZE · px · 0.5–64.0 · 0.1 · **8.0** | KERNEL Menu `Disc · Hexagon · Box · Airy · Lorentzian · Star` | PADDING `Wrap · Zero · Mirror` | — | — | edge bar |

**F5 · Directional & motion**

| Entry | Deck | Primary | Deck partner | Parameters extras | Variant picker | Handle | Specimen |
|---|---|---|---|---|---|---|---|
| `linear-motion-blur` | B | LENGTH L · px · 1.0–128.0 · 0.1 · **24.0** | ANGLE crown 0–179° | SHUTTER `Box · Trapezoid · Coded`; ANCHOR `Centred · Trailing` | `Gather · Doubling` | — | impulse grid |
| `anisotropic-gaussian` | B | SIGMA ALONG · px · 0.3–64.0 · 0.1 · **8.0** | ANGLE crown | SIGMA ACROSS DecimalStepper 0.0–64.0 · 0.1 (0 = Core Image's line) | single (sheared separable) | — | Siemens star |
| `kawase-streak` (T2) | B | LENGTH · px · 4–256 (base-4 schedule; status shows the exact length) · **64** | ANGLE crown (rotation 0–89°) | ARMS Stepper 2–8 (4); THRESHOLD DecimalStepper 1.0–10.0 × white | — | — | Night City |
| `camera-shake-blur` (T2) | D | AMPLITUDE · px · 1.0–64.0 · 0.1 · **12.0** | TRAJECTORY Menu `Random walk · Tremor · Pause-and-jerk` + SEED Stepper 1–99 | — | — | — | Night City |
| `velocity-buffer-motion-blur` (T2) | E | SHUTTER Stepper 0–360° · 15 · **180** | TAPS Stepper odd 5–31 · 15 | TILE k Stepper 10–40 px; SPEED Stepper (px per frame) | — | — | moving disc |
| `temporal-accumulation` (T2) | E | SUB-FRAMES N Stepper 1–64 · **16** | MODE `Box average · EMA` | α DecimalStepper 0.01–1.00 (EMA only) | — | — | moving disc (rotating bar) |
| `radial-zoom-blur` | D | STRENGTH a · % · 0.0–50.0 · 0.5 · **20.0** | SAMPLES Stepper 4–256 · 32 + DIRECTION `In · Centred · Out` (Out = Core Image's convention) | ADAPTIVE N toggle (N(x) = ⌈a·r⌉ + 1); CENTRE X/Y DecimalSteppers | `Gather · Adaptive gather · Doubling` | centre ⊕ | impulse grid / centred star |
| `spin-blur` | A | ANGLE Θ · ° · 0.0–360.0 · 0.5 · **10.0** | SEMANTIC stops at 360°/n_c multiples | SAMPLES adaptive (default) or Stepper 4–256; CENTRE X/Y | `Arc gather · Doubling` | centre ⊕ | centred Siemens star |
| `path-blur` (T2) | D | SPEED · % · 0–500 · 5 · **100** | PATH Menu `S-curve · Circle · Spiral · Straight` (presets replace drawing, JF M-15) + ANCHOR `Centred · Trailing` | TAPER toggle | — | — | impulse grid |

**F6 · Lens & bokeh**

| Entry | Deck | Primary | Deck partner | Parameters extras | Variant picker | Handle | Specimen |
|---|---|---|---|---|---|---|---|
| `disc-blur` | A | RADIUS R · px · 0.5–64.0 · 0.1 · **8.0** | SEMANTIC octave stops | COMPONENTS `1 · 2` (complex separable only); SAMPLES Stepper 16–400 (stochastic only) | `Gather · Row-span SAT · Complex separable · Stochastic` (Gather above R ≈ 28, where π·R² fetches pass the full budget, switches to Row-span SAT: `GATHER ABOVE BUDGET · USING ROW-SPAN SAT`) | — | Night City +3 EV |
| `polygonal-bokeh` | B | RADIUS R (circumradius) · px · 0.5–64.0 · 0.1 · **16.0** | ANGLE crown = ROTATION 0–(360/n − 1)° | BLADES Stepper 4–9 · 6 (5, 7, 9 and curvature > 0 switch to the 2-D gather with the zonogon reason); CURVATURE DecimalStepper 0.00–1.00 · 0.05 | `Line passes · 2-D gather` (the 2-D gather's radius is capped where it reaches the full budget, R ≈ 32, with the reason in the Parameters panel) | — | Night City |
| `cats-eye-swirl-bokeh` (T2) | C | RADIUS R · px · 0.5–32.0 · 0.1 · **12.0** | second crown BARREL CLIP k · 0.00–1.00 · 0.02 | SWIRL s DecimalStepper 0.00–1.00 | — | centre ⊕ | light grid (impulse grid ×100) |
| `diffraction-airy` (T2) | A | F-NUMBER · f/1.4–f/22 · ⅓ stop · **f/8** | SEMANTIC whole stops | WAVELENGTH `450 · 550 · 650 nm`; PIXEL PITCH DecimalStepper (his sensors' pitch is UNVERIFIED; the default is labelled as an assumption) | `Small gather · FFT` | — | Night City +5 EV |
| `anamorphic-bokeh` (T2) | C | RADIUS R · px · 0.5–64.0 · 0.1 · **12.0** | second crown SQUEEZE · × · 1.00–2.00 · 0.05 | STREAK LENGTH, THRESHOLD DecimalSteppers | — | — | Night City |

**F7 · Spatially varying & stochastic**

| Entry | Deck | Primary | Deck partner | Parameters extras | Variant picker | Handle | Specimen |
|---|---|---|---|---|---|---|---|
| `depth-of-field-coc` (T2) | A | F-NUMBER · f/1.4–f/16 · ⅓ stop · **f/2.8** | SEMANTIC whole stops | FOCUS DISTANCE DecimalStepper 0.10–10.00 · 0.05 (scene units, stated); FOCAL LENGTH `24 · 50 · 85 mm` | `Half-res gather · Full-res gather` | — | tilted plane with depth |
| `tilt-shift` (T2) | A | MAX BLUR σ · px · 0.5–32.0 · 0.1 · **8.0** | SEMANTIC octave stops | BAND WIDTH, TRANSITION DecimalSteppers; ANGLE Stepper 0–179° | `Linear band · Iris (ellipse)` | focus band (2 lines) / iris ellipse | aerial ground plane |
| `variable-progressive-blur` | D | MAX σ · px · 0.5–64.0 · 0.1 · **12.0** | MASK Menu `Ramp · Radial · Top edge · Bottom edge` | — | Menu `Per-pixel Gaussian · Mip mix · Variance-matched mip mix · Stacked layers` (+ Apple axis: `CIMaskedVariableBlur`) | ramp start/end lines | ramp mask over impulse grid |
| `frosted-glass-noise` | D | SPREAD a · px · 1–16 · 1 · **4** (status `expected σ = √(a(a+1)/3) = 2.58 px`) | REALIZATIONS Stepper 1–256 · 1 | NOISE `White · Smooth`; `Reseed` button 44 × 44 | — | — | step edge + text |

**F8 · Edge-preserving & nonlinear**

| Entry | Deck | Primary | Deck partner | Parameters extras | Variant picker | Handle | Specimen |
|---|---|---|---|---|---|---|---|
| `median` | D | RADIUS r · px · 1–3 · 1 · **1** (3 × 3, 5 × 5, 7 × 7) | SHAPE `Square · Disc` | NOISE DENSITY Stepper 0–30 % (salt-and-pepper specimen only) | single (sorting network / partial selection) | — | salt-and-pepper text |
| `bilateral` | C | RANGE σr · 0.01–1.00 · 0.01 · **0.10** (the parameter that makes it unique gets the hero) | second crown SPACE σs · px · 0.5–8.0 · 0.1 · 3.0 (brute force uses r = min(8, ⌈2.5σs⌉); above σs 3.2 the variant switches to `Grid` and says why) | DISTANCE `Luma · RGB` | `Brute force · Separable · Grid` | — | noisy steps |
| `joint-bilateral` (T2) | C | RANGE σr · **0.10** | SPACE σs crown | GUIDE Menu `Colour stripes · Luma of specimen · Depth` | — | — | blocky depth + stripe guide |
| `guided` | C | RADIUS r · px · 1–10 · 1 · **4** (`CIGuidedFilter` max 10) | second crown √ε · 0.01–0.40 · 0.01 (stops 0.1 · 0.2 · 0.4, He et al.) | DETAIL BOOST k Stepper 1–5 (P15) | `Box filters · Fast (subsampled)` | — | noisy step |
| `domain-transform` (T2) | C | SPACE σs · px · 1.0–64.0 · 0.1 · **8.0** | RANGE σr crown | ITERATIONS Stepper 1–4 | `Recursive · Normalised convolution` | — | noisy step + thin line |
| `kuwahara` | D | RADIUS r · px · 1–8 · 1 · **4** | VARIANT `Classic · Generalized · Anisotropic` (the last two Tier 2) | SHARPNESS q Stepper 1–16 (generalized/anisotropic) | (in deck) | — | noisy flat field |
| `surface-blur` (T2) | D | RADIUS · px · 1–16 · 1 · **5** | THRESHOLD Stepper 0–255 levels · 15 (status: tent-model σr and its INFERRED badge, NL A10) | — | `Surface Blur (hard) · Smart Blur · Sigma filter` | — | ramp + noisy step |
| `nonlocal-means` (T2) | D | STRENGTH h · 0.01–0.50 · 0.01 · **0.10** | PATCH `3 · 5 · 7` + SEARCH `7 · 11 · 21` (naive cost is search² × patch² fetches per pixel; combinations above the full budget, SEARCH 21 with any patch and PATCH 5 or 7 with SEARCH 11, are disabled with their fetch count as the reason, COMPUTED; previews use SEARCH 7) | — | — | — | noisy text |

**F9 · Diffusion**

| Entry | Deck | Primary | Deck partner | Parameters extras | Variant picker | Handle | Specimen |
|---|---|---|---|---|---|---|---|
| `heat-equation` | D | TIME t · 0.0–200.0 · 0.5 · **8.0** (meaning line `σ = √(2t) = 4.00 px`; iterations shown, not set: t/λ) | λ segmented `0.125 · 0.20 · 0.25` (default **0.125**, §17 item 1) | — | `Explicit iterations · Exact Gaussian` (explicit iterations above 500, e.g. t > 62.5 at λ ⅛, switch to Exact Gaussian with `ITERATIONS ABOVE BUDGET · USING EXACT GAUSSIAN`) | — | impulse |
| `perona-malik` | D | EDGE K · intensity/px · 0.01–0.50 · 0.01 · **0.10** | ITERATIONS Stepper 0–500 · 50 | c(·) `Exponential · Rational`; λ as heat | — | — | noisy step + ramp |

**F10 · UI materials (system entries measure the real API; crowns drive the API's own parameter in its own unit)**

| Entry | Deck | Primary | Deck partner | Parameters extras | Notes |
|---|---|---|---|---|---|
| `swiftui-layer-blur` (S) | A | RADIUS · **pt** · 0.0–20.0 · 0.1 · **4.0** | SEMANTIC stops incl. the regime switch | OPAQUE `false · true`; RENDERER `.nonLinear · .linear · .extendedLinear`; `Measure on this phone` (Calibrate) | every derived number is MEASURED (device, `ImageRenderer`) or INFERRED; specimen step edge / impulse |
| `apple-uiblureffect` (S) | E | MATERIAL tiles `ultraThin · thin · regular · thick · ultraThick` (no numeric parameter exists: that is the lesson) | — | BACKDROP Menu | native side INFERRED; our reconstruction MODELED |
| `liquid-glass` (S) | E | VARIANT `Regular · Clear` | SHAPE SIZE Stepper 44–200 pt · 4 | TINT `None · Cyan` | the only glass over a specimen (§4.1.9 g) |
| `css-backdrop-filter` (T2, model) | C | BLUR · CSS px (= σ in pt) · 0.0–40.0 · 0.5 · **10.0** | second crown SATURATE · % · 100–300 · 5 | CHAIN order Menu (`saturate()` before/after `blur()`) | MODELED from the spec (REFERENCE): sRGB, mirrored edges; specimen: bright object just outside the panel |

**F11 · Uses of blur**

| Entry | Deck | Primary | Deck partner | Parameters extras | Handle | Specimen |
|---|---|---|---|---|---|---|
| `drop-shadow` (T2) | D | TYPED VALUE · 0.0–64.0 · 0.5 · **10.0** (the number a designer types) | CONVENTION Menu `CSS box-shadow · CSS drop-shadow() · CALayer.shadowRadius · CGContext.setShadow · SwiftUI .shadow · Figma · Sketch` (status converts to σ with each convention's badge; P27) | OFFSET X/Y Steppers | — | shape on transparent (square and star) |
| `bloom` (T2) | D | THRESHOLD · × white · 0.5–10.0 · 0.1 · **1.0** | LEVELS Stepper 1–8 · 5 | INTENSITY DecimalStepper 0.00–1.00 · 0.01 | — | Night City (exposure sweep) |
| `god-rays` (T2) | D | DECAY · 0.900–1.000 · 0.001 · **0.970** | SAMPLES Stepper 16–128 · 64 | DENSITY, WEIGHT DecimalSteppers (GPU Gems 3 ch. 13 names) | sun ⊕ | sun behind bars |

**C · Contrast (not blurs)**

| Entry | Deck | Primary | Deck partner | Parameters extras | Specimen |
|---|---|---|---|---|---|
| `unsharp-mask` (T1 quality) | C | AMOUNT k · 0.00–5.00 · 0.05 · **1.00** | second crown RADIUS σ · px · 0.3–16.0 · 0.1 · 2.0 | THRESHOLD Stepper 0–255 levels | step edge + text |
| `difference-of-gaussians` (T2) | D | SIGMA σ · px · 0.3–32.0 · 0.1 · **2.0** | RATIO `1.6 · √2 · 2 · 5` | XDoG toggle | Siemens star |
| `morphology` (T2) | D | RADIUS r · px · 1–16 · 1 · **3** | OPERATION `Dilate · Erode · Open · Close` | SHAPE `Square · Disc · Line` | Night City / text |
| `pixelate` (T2) | D | CELL · px · 2–64 · 1 · **12** | SHAPE `Square · Hex` | GRID PHASE X/Y Steppers (Core Image's `inputCenter`) | text (pan: the cells stay, content slides) |
| `wiener-deconvolution` (T2) | D | NOISE-TO-SIGNAL K · `0 (inverse filter)`, then 10⁻⁴–10⁻¹ in 1-2-5 detents · **10⁻²** | BLURRED BY `Box · Disc · Gaussian` | BLUR SIZE DecimalStepper; ADD NOISE toggle | blurred text |

**Controls that are never offered:** anything that would put a second crown pair on screen; any control over GPU internals (threadgroup size, sampler filter, tile size) except through the variant picker, because floor 6 must show the code that ran (D §10.2 last paragraph); any parameter whose meaning the sources could not establish (Photoshop's Gaussian Radius, Radial Blur Quality): those appear as UNVERIFIED rows on floor 1, never as knobs.

## 10. The blur catalog in scope

v1 ships the whole canonical catalog of CATALOG.md: **55 entries in 11 families plus 7 contrast entries (62), with 32 variant ids**, at four depths (CAT §6):

- **Tier 1 · LIVE**: Metal implementation, `BlurCore` CPU reference, every floor, full pixel trace with GPU records (`TRACE_PROBE`), GPU↔CPU parity in the CLI, traced = untraced bit-exactness.
- **Tier 2 · LIVE**: Metal implementation and CPU reference with parity; floors with lighter content; a trace of one declared stage.
- **Tier 3 · PLOTS**: an atlas page (floors 1–4 and a CPU floor 7 on a 128 × 128 crop); never on the blur strip.
- **Tier S · SYSTEM**: Apple's implementation run live on this phone and measured (Calibrate, Apple axis), always beside our own model.

### 10.1 Entries

| # | id | Display name | Family | Tier | Strip | Trace | Apple twin (Apple axis / Tier S) |
|---|---|---|---|---|---|---|---|
| 1 | `box-blur` (+ `sat-box`, `box-sliding-window`) | Box blur | F1 | 1 | ● | full | `CIBoxBlur` (W = 2⌈r/2⌉ − 1), `MPSImageBox`, vImage box |
| 2 | `tent-blur` (+ `stack-blur`) | Tent (triangle) blur | F1 | 1 | ● | full | `MPSImageTent`, vImage tent |
| 3 | `iterated-box` (+ `svg-three-box`, `extended-box`, `cubic-b-spline`) | Iterated box | F1 | 1 | ● | full (one sub-step per pass) | — (SwiftUI `.blur` above ≈ 5 px: excess kurtosis −0.45, MEASURED offscreen on macOS; closest model box³, INFERRED; P26) |
| 4 | `average-blur` | Average (the infinite blur) | F1 | 3 | — | atlas | `CIAreaAverage` |
| 5 | `gaussian-blur` (+ `gaussian-2d-direct`, `gaussian-separable`, `gaussian-linear-sampling`, `gaussian-compute-tile`, `gaussian-integrated`, `discrete-gaussian-lindeberg`) | Gaussian blur | F2 | 1 | ● | full | `CIGaussianBlur`, `MPSImageGaussianBlur` |
| 6 | `binomial-blur` | Binomial (Pascal) blur | F2 | 1 | ● | full | — |
| 7 | `iir-gaussian` | Recursive (IIR) Gaussian | F2 | 1 | ● | full | — |
| 8 | `kawase-blur` | Kawase blur | F3 | 1 | ● | full (per pass) | — |
| 9 | `dual-kawase` | Dual Kawase | F3 | 1 | ● | full (per level) | — |
| 10 | `pyramid-blur` (`mip-chain`, `cod-13tap`, `unity-13tap`) | Pyramid (mip-chain) blur | F3 | 1 | ● | full (per level) | — |
| 11 | `exponential-blur` | Exponential (Laplace) blur | F4 | 1 | ● | full | — |
| 12 | `lorentzian-blur` (+ `sum-of-gaussians`) | Lorentzian / Poisson (glare) blur | F4 | 2 | ● | one stage | — |
| 13 | `frequency-lowpass` (`ideal-lowpass`, `butterworth-lowpass`, `gaussian-lowpass`) | Frequency-domain low-pass | F4 | 2 | ● | spectrum steps | — |
| 14 | `fft-convolution` | FFT convolution ("Shape Blur") | F4 | 2 | ● | spectrum steps | — |
| 15 | `linear-motion-blur` (+ `shutter-function-blur`) | Linear motion blur | F5 | 1 | ● | full | (`CIMotionBlur` is Gaussian: twin of 16) |
| 16 | `anisotropic-gaussian` | Directional (elliptical) Gaussian | F5 | 1 | ● | full | `CIMotionBlur` (σ = r, MEASURED) |
| 17 | `kawase-streak` | Star / streak filter | F5 | 2 | ● | one arm | — |
| 18 | `camera-shake-blur` | Camera-shake blur | F5 | 2 | ● | one stage | — |
| 19 | `velocity-buffer-motion-blur` | Per-pixel (velocity-buffer) motion blur | F5 | 2 | ● | reconstruction stage | — |
| 20 | `temporal-accumulation` | Frame accumulation | F5 | 2 | ● | accumulation stage | — |
| 21 | `radial-zoom-blur` | Zoom (radial) blur | F5 | 1 | ● | full | `CIZoomBlur` (outward) |
| 22 | `spin-blur` | Spin (rotational) blur | F5 | 1 | ● | full | — |
| 23 | `path-blur` | Path (flow-field) blur | F5 | 2 | ● | one stage | — |
| 24 | `disc-blur` (+ `circular-separable-bokeh`, `stochastic-bokeh`; `defocus-wave-optics` T3 plot) | Disc (pillbox) blur | F6 | 1 (variants 2) | ● | full | `CIDiscBlur`, `CIBokehBlur` |
| 25 | `polygonal-bokeh` | Polygonal (hexagonal) bokeh | F6 | 1 | ● | full | — |
| 26 | `cats-eye-swirl-bokeh` | Cat's-eye and swirly bokeh | F6 | 2 | ● | one stage | — |
| 27 | `diffraction-airy` | Diffraction (Airy) blur | F6 | 2 | ● | one stage | — |
| 28 | `anamorphic-bokeh` | Anamorphic bokeh and streak | F6 | 2 | ● | one stage | — |
| 29 | `depth-of-field-coc` | Depth of field (circle of confusion) | F7 | 2 | ● | gather stage | `CIDepthBlurEffect` (needs depth; Field guide mention only) |
| 30 | `tilt-shift` (+ `iris-blur`) | Tilt-shift (miniature) blur | F7 | 2 | ● | one stage | — |
| 31 | `variable-progressive-blur` | Variable (progressive) blur | F7 | 1 | ● | full | `CIMaskedVariableBlur` |
| 32 | `frosted-glass-noise` | Frosted glass (random displacement) | F7 | 1 | ● | full | — |
| 33 | `median` | Median filter | F8 | 1 | ● | full | `CIMedianFilter` (3 × 3), `MPSImageMedian` |
| 34 | `bilateral` (+ `bilateral-grid`, `bilateral-separable`) | Bilateral filter | F8 | 1 (variants 2) | ● | full | — |
| 35 | `joint-bilateral` | Joint (cross) bilateral | F8 | 2 | ● | one stage | — |
| 36 | `guided` | Guided filter | F8 | 1 | ● | full | `CIGuidedFilter`, `MPSImageGuidedFilter` |
| 37 | `domain-transform` | Domain transform | F8 | 2 | ● | one stage | — |
| 38 | `kuwahara` (+ `kuwahara-generalized`, `kuwahara-anisotropic`) | Kuwahara | F8 | 1 (variants 2) | ● | full | — |
| 39 | `surface-blur` (+ `smart-blur`, `sigma-filter`) | Surface Blur / Smart Blur | F8 | 2 | ● | one stage | — |
| 40 | `nonlocal-means` | Non-local means | F8 | 2 | ● | one stage | — |
| 41 | `mean-shift` | Mean-shift filtering | F8 | 3 | — | atlas | — |
| 42 | `tv-denoise` | Total-variation (ROF) smoothing | F8 | 3 | — | atlas | — |
| 43 | `heat-equation` (+ `heat-equation-explicit`) | Heat equation | F9 | 1 | ● | full (per iteration) | — |
| 44 | `perona-malik` | Perona–Malik diffusion | F9 | 1 | ● | full (per iteration) | — |
| 45 | `coherence-enhancing-diffusion` | Coherence-enhancing diffusion | F9 | 3 | — | atlas | — |
| 46 | `swiftui-layer-blur` | SwiftUI `.blur(radius:)` | F10 | S | ● | INFERRED lane | itself (Calibrate) |
| 47 | `apple-uiblureffect` | Apple materials | F10 | S (+ 2 model) | ● | INFERRED lane | itself |
| 48 | `liquid-glass` | Liquid Glass | F10 | S (+ 2 model) | ● | INFERRED lane | itself |
| 49 | `css-backdrop-filter` | CSS `backdrop-filter` (model) | F10 | 2 | ● | one stage | — |
| 50 | `windows-acrylic` | Fluent Acrylic | F10 | 3 | — | atlas | — |
| 51 | `windows-mica` | Fluent Mica | F10 | 3 | — | atlas | — |
| 52 | `android-renderEffect` | Android `RenderEffect` and window blurs | F10 | 3 | — | atlas | — |
| 53 | `drop-shadow` (+ `inner-shadow`, `outer-glow`) | Drop shadow | F11 | 2 | ● | blur stage | SwiftUI `.shadow`, `CALayer.shadowRadius`, `CGContext.setShadow` (Calibrate) |
| 54 | `bloom` | Bloom / glow | F11 | 2 | ● | blur stage | `CIBloom` (Field guide mention) |
| 55 | `god-rays` | Light shafts (god rays) | F11 | 2 | ● | gather stage | — |
| C1 | `unsharp-mask` (+ `high-pass`) | Unsharp mask | C | 1 (quality) | ● | full | `CIUnsharpMask` |
| C2 | `difference-of-gaussians` (+ `xdog`) | DoG / XDoG | C | 2 | ● | one stage | — |
| C3 | `morphology` (`dilate`, `erode`, `open`, `close`) | Min / max | C | 2 | ● | one stage | `CIMorphologyMaximum/Minimum`, `MPSImageAreaMax/Min` |
| C4 | `pixelate` (+ `pixelate-hex`, `crystallize`, `pointillize`) | Pixelate / mosaic | C | 2 | ● | one stage | `CIPixellate` (cell = `inputScale` px) |
| C5 | `lanczos` | Lanczos (windowed sinc) | C | 3 | — | atlas | — |
| C6 | `apple-vibrancy` | Vibrancy | C | 3 | — | atlas (inside the materials breakdown) | — |
| C7 | `wiener-deconvolution` (+ `richardson-lucy`) | Deconvolution | C | 2 | ● | spectrum steps | — |

Totals: Tier 1 = 23 catalog entries (27 GPU kernels with the four implementation variants), plus `heat-equation` and `unsharp-mask` built to Tier 1 quality; Tier 2 = 25 entries plus the Tier 2 variants of Tier 1 parents; Tier 3 = 10 atlas pages (7 entries, 2 contrast entries and the `defocus-wave-optics` plot; the `extended-box` and `cubic-b-spline` plots live on the `iterated-box` page); Tier S = 3 entries plus the Apple-axis twins. **53 glyphs on the blur strip** (23 Tier 1 + `heat-equation` + `unsharp-mask` + 25 Tier 2 + 3 Tier S): 50 run on our GPU, 3 are Apple's own blurs run live. This is the count §1 and §19 use.

`gaussian-compute-tile` is a Blur2ool implementation variant not in CATALOG's list (the threadgroup-tile compute pass of GPU §6.2 sketch 1); it exists so the GPU floor can show tile + apron geometry and so the Implementation axis can compare fragment vs compute (compressible vs not on Apple9).

### 10.2 What each tier must deliver (acceptance)

| | Tier 1 | Tier 2 | Tier 3 | Tier S |
|---|---|---|---|---|
| Live GPU image on the Bench | yes | yes | no | yes (system view or our model) |
| CPU reference in `BlurCore` | yes, every variant | yes | CPU computation of the plots | our model only |
| GPU↔CPU parity in `blur-gpucheck` | yes, at the tolerances of ARCHITECTURE §7 | yes | n/a | model kernel only |
| Traced = untraced bit-exact | yes | traced stage only | n/a | n/a |
| Floors | all seven, full content | all seven, lighter (empty states allowed with reasons) | 1–4 and CPU 7; 5–6 engraved | 1, 2, 7 real; 3–6 the INFERRED lane plus our model |
| Trace | every fetch / tap / iteration | one declared stage with GPU records | floors 1–4 | none (INFERRED lane) |
| Fingerprint card | full, ON THIS PHONE measured | full | computed rows only | full, MEASURED rows from Calibrate |
| Lessons | per CATALOG §7 | where listed | P17 (TV page) | P26, P27, P28 |

### 10.3 Build priority (if the build must cut, it cuts from the bottom; never a Tier 1 entry)

1. Tier 1 F2 + F1 (Gaussian family, box/tent/iterated box), then F6 disc + hexagon, F5 zoom/spin/motion/anisotropic, F8 bilateral/median/guided/Kuwahara, F3 pyramids, F4 exponential, F7 variable/frosted, F9 heat/Perona–Malik, unsharp mask.
2. Tier S: SwiftUI `.blur` with Calibrate; the Liquid Glass / materials exhibit.
3. Tier 3 atlas pages (cheap: CPU plots).
4. Tier 2 in this order: `bloom`, `drop-shadow`, `tilt-shift`, `lorentzian-blur`, `frequency-lowpass`, `fft-convolution`, `wiener-deconvolution`, `kawase-streak`, `diffraction-airy`, `cats-eye-swirl-bokeh`, `anamorphic-bokeh`, `depth-of-field-coc`, `path-blur`, `camera-shake-blur`, `velocity-buffer-motion-blur`, `temporal-accumulation`, `god-rays`, `joint-bilateral`, `domain-transform`, `surface-blur`, `nonlocal-means`, `css-backdrop-filter`, `difference-of-gaussians`, `morphology`, `pixelate`.

### 10.4 Tier 3 atlas pages

Pushed from the Catalog (never the Bench). Header and fingerprint card as for any entry; floors 1–4 in full; floor 5–6 engraved `CPU ONLY IN THIS APP · TIER 3` with the reason (slow iterative method, platform material we cannot run, or a limit); floor 7 computed by `BlurCore` on a 128 × 128 crop of a fixed specimen with a static image of the result (COMPUTED, engraved `CPU · 128² CROP · COMPUTED`). Windows and Android materials show their documented recipes (REFERENCE) and our modelled plots (MODELED).

## 11. Test images (specimens)

On-screen the menu is called **Test image** (plain words, JD M7); "specimen" is the internal name.

**Rules.**
1. **Procedural and deterministic.** Every built-in test image is generated by `BlurCore` from a formula and a fixed seed, in **linear light**, premultiplied alpha, stored as `rgba16Float` (values above 1.0 survive for HDR lights). The same image is bit-identical on the Mac (parity CLI), in the Simulator and on the phone, so the §5.3 fixtures can be unit-tested (BRIEF). The one exception is **Text**, which the app renders with Core Text into a coverage mask (BlurCore stays Foundation-only); parity tests do not use it.
2. **Window-sized, with a pan margin.** Each image is generated as a **canvas** of (N + 512) × (N + 512) px (N = the window's pixel size: 894 on the 15 Pro Max, 810 on a 402-pt simulator) centred on the window, so panning (±256 px) reveals real content. Geometry is defined relative to the window centre pixel c = (⌊N/2⌋, ⌊N/2⌋) = (447, 447) so features keep their meaning at other sizes; the §5.3 numbers are pinned at N = 894 and checked feature-relative at N = 810 (D R3). **Coordinate convention (binding, review fix P-32):** a pixel's value is evaluated at its centre (x + 0.5, y + 0.5) in window coordinates, y down; radial images are centred on the continuous point c + (0.5, 0.5) = (447.5, 447.5), the centre of pixel c, so r is measured from there; the angle is θ = atan2(y − 447.5, x − 447.5) with y down, so θ grows clockwise on screen; supersampled images (the star) average the 4 × 4 points (x + (i + 0.5)/4, y + (j + 0.5)/4). TESTIMAGES has CORE tests that assert every default probe's IN value (star (747, 460) = 1.000; zone plate (747, 460) = 0.224; star edge probe (404, 288) = 0.875; Night City (447, 455) = 0) and that the canvas hashes on the phone equal the Mac hashes (an AppTest; generators use only +, −, ×, ÷, √ and BlurCore's own transcendental functions, so platform libm differences cannot enter).
3. **Default probe on the most informative feature** (listed below), in window pixels.
4. **Nothing moves by itself.** Only `scene-motion` and diffusion-over-time animate, and only after an explicit `Play` in the Parameters panel. Periodic high-contrast images (zone plate, checkerboards, stripes, star) never move except under his own pan; animated content moves at most 0.25 px per frame and nothing changes brightness more than three times per second (WCAG 2.2 SC 2.3.1, REFERENCE). The menu marks periodic images `HIGH-CONTRAST PATTERN`.
5. **Exposure** (−2 … +6 EV, 1 EV steps) multiplies light-carrying images (Night City, impulse, impulse grid, tilted plane, sun and bars) by 2^EV **at render time**, in the window pass, never in the canvas (review fix E-10): an EXPOSURE detent is a cheap re-render, not a new 31.6 MB canvas. Powers of two commute with fp16 rounding, so parity is unchanged.

| # | id · menu name | Definition (at N = 894; canvas adds the margin) | Default probe | Reveals | Default for |
|---|---|---|---|---|---|
| 1 | `night-city` · Night City | dark building silhouettes (values 0.02–0.06) under a black sky; 160 point lights at Poisson-disc positions (seed 7): 120 of 1 × 1 px with intensities log-uniform **20–1,000** and 40 of 3 × 3 px with intensities log-uniform 2–100 (energies chosen so that after the σ 12 Gaussian about 60 lights, and by the launch fixture at least 40, still peak at ≥ 0.25 linear, MODELED from the distribution and asserted by a TESTIMAGES test; the brightest light at +6 EV, 64,000, stays below fp16's maximum 65,504), three colour temperatures (sodium 2,000 K-like warm, 4,000 K neutral, 6,500 K cool, as fixed RGB triples in BlurCore), a few in rows like streets; a white **reference light of 100 (1 px) at c**; one pair 20 px apart; three lights within 8 px of the window border | **(447, 455)**, 8 px below the reference light | PSF shape made visible (bokeh, rims, square supports, tails); linear vs gamma energy loss | first launch; F3, F4, F6, F11; descent D |
| 2 | `siemens-star` · Siemens star | **36 dark–light cycles** about (447.5, 447.5) (value 1 where sin(36θ) ≥ 0, else 0) out to r = 440, 0.5 outside; edges anti-aliased by 4 × 4 supersampling; label `36 CYCLES` (CAT E7) | **(404, 288)**, r 164.7 px, 0.38 px from the spoke edge at θ = 255° (IN 0.875; the first draft's (412, 287) was 6.7 px from any edge) | zeros (grey rings), inversion (reversed spokes), anisotropy (square vs round rings), spin's grey ring at 360°/n_c, zoom's invariance | F1, F2 comparisons; spin; descent B |
| 3 | `zone-plate` · Zone plate | 0.5 + 0.5·cos(π k r²), k = 0.5/632.2, r from (447.5, 447.5), so the local frequency k·r reaches Nyquist at the window corners | (747, 460) (descent B's probe; IN 0.224) | the response laid out in space; zero rings; aliasing; zoom destroys it, spin spares it | pyramids, motion, P21 |
| 4 | `step-edges` · Step edges | vertical step: 0 for x ≤ 446, 1 for x ≥ 447; picker `Vertical · 45°` (x − y ≥ 0) | (446, 300) | edge spread, 10–90 % width, overshoot; separable vs isotropic (axis vs 45° marginal) | descent A; low-pass; USM |
| 5 | `noisy-step` · Noisy step | a vertical step centred on 0.5, height `0.05 · 0.20 · 1.00` (default 0.20: 0.40 → 0.60); Gaussian noise σ 0.02 (seed 1), switchable; option `+ thin horizontal line` (1 px, value 0.9, y = 600) | (447, 300) | edge-aware filters by contrast; amplitude-dependent transfer; leaks along rows (domain transform) | descent C; F8, F9 |
| 6 | `impulse` · Impulse | one pixel at c with intensity `1 · 10 · 100`; display toggle `Linear · Log` | (447, 455) | the PSF itself; tails (IIR, Lorentzian, exponential); truncation squares; moving point light under pan (pyramid snapping) | P3, P9, P10, P16; heat, pyramid |
| 7 | `impulse-grid` · Impulse grid | 13 × 13 one-pixel dots every 64 px, one at c (x, y ∈ {63, 127, …, 831}), intensity `1 · 100` | (455, 447) | PSF fields of space-variant blurs (zoom rays, cat's eyes, variable blur); bokeh polygons | zoom, motion, path, variable, cat's-eye (×100) |
| 8 | `checkerboard` · Checkerboard | period `2 px · 16 px` | (447, 447) | Nyquist content: binomial erases the 1-px checker exactly; a sampled Gaussian at σ 1 leaves 1.41 % | binomial (P8), box |
| 9 | `stripes` · Stripes | 1-px vertical black/white columns | (447, 447) | the colour-space verdict: 0.500 encoded (gamma blend) vs 0.735 (linear blend) | P18 |
| 10 | `text` · Text | four lines rendered by the app with Core Text in the system font at 9, 12, 18 and 32 px, white-on-black left half, black-on-white right half; Blur2ool's own sentences ("Blur is an average of light."); option `Noise: none · salt-and-pepper (0–30 %, seed 3) · Gaussian σ 0.05` | first stem on the 12-px line | legibility; doubled strokes (camera shake); halos (USM); rank vs average on impulses | median (salt-and-pepper), dual Kawase (pan), NLM, Wiener, pixelate |
| 11 | `ramp` · Ramp | horizontal 0 → 1 in linear light across the width; toggle `Linear ramp · Encoded ramp`; optional noise 0.01 | (447, 447) | terraces (surface blur, Perona–Malik), staircasing (TV) | P17, surface blur |
| 12 | `noise-field` · Noise field | uniform 0.5 with Gaussian noise σ 0.1 (seed 9), a 36-cycle star inset in the right third | (300, 447) | Kuwahara's blocks; smoothing strength | Kuwahara |
| 13 | `alpha-shape` · Shape on transparent | a saturated red disc (radius 200 px) centred on fully transparent (0, 0, 0, 0); option `Square and star` (a 300-px square and a five-point star) for drop shadows | (647, 447), on the rim | premultiplied vs straight alpha (dark fringe); shadow conventions | P19, drop shadow |
| 14 | `edge-bar` · Bar at the border | a 32-px bright bar (value 1) touching x = 0, on black | (40, 447) | IIR boundary transient; FFT wrap-around; edge modes | IIR, FFT convolution |
| 15 | `rings` · Noisy rings | concentric rings of period 12 px about c, contrast 0.5, Gaussian noise σ 0.1 (seed 5) | (543, 447) | flow-following filters (anisotropic Kuwahara; coherence-enhancing diffusion page) | Kuwahara anisotropic |
| 16 | `material-backdrop` · Stripes, text and split | top: six saturated 32-px colour stripes; middle: one text line; bottom: white/black split. Drawn **in SwiftUI** for the native glass exhibit and as a canvas for our models (METRO §C.2) | (447, 700), on the split | how much of a material is colour stage vs blur (our reading: mostly colour stages, INFERRED); vibrancy; luminance squeeze | F10 |
| 17 | `scene-depth` · Tilted plane | a receding plane of HDR lights plus a near dark bar, with a matching depth buffer | on the bar's edge | depth of field, CoC, near/far edge handling | depth of field |
| 18 | `scene-motion` · Moving disc | a 120-px disc moving 24 px per frame over a 16-px checker, with velocity and depth buffers; a rotating bar rendered as N sub-frames | on the disc's trailing edge | per-pixel motion blur vs frame accumulation | P22 |
| 19 | `aerial` · Aerial ground plane | a 32-px checker in perspective, horizon at the top third | on the focus line | tilt-shift's "toy town" | tilt-shift |
| 20 | `sun-and-bars` · Sun behind bars | an HDR disc (radius 40 px, value 20) behind a pattern of black occluder bars | the disc centre's ray at 200 px | light shafts from an occlusion mask | god rays |
| 21 | `guide-pair` · Blocky depth + stripes | a 16-px blocky depth map to upsample, with a colour-stripe guide image | (447, 447) | joint bilateral upsampling | joint bilateral |
| 22 | `photo` · Your photo… | `PhotosPicker` (out of process, no permission prompt, SDK §10); decoded through the image's colour profile into linear `rgba16Float`, centre-cropped and **area-averaged** to the canvas size; the caption engraves `PHOTO · RESAMPLED ×s (BOX)` because the resample is itself a box blur | centre | real content; but every number is LIVE only, and lessons are disabled | anything |

The specimen menu also holds: `Exposure ▸` (light images), `Show input beside output` (the split), `Reset view` (pan and zoom), and the per-image options above. **Why no photographs ship:** procedural images avoid copyright and have known answers (on the star, zoom must give 1.000 at the probe; on stripes, 0.735 vs 0.500 decides the colour space). A photograph has no ground truth, so it is an optional extra, never a default.

## 12. Honesty labels: where each appears

### 12.1 The six badges, one qualifier, one caption

`HonestyBadge` (METRO §C.12): a capsule, caption2 mono, tracking 1.2, fill white 0.06, 0.6-pt border white 0.12 (0.25 under Increased Contrast). **The word is primary**; glyph and ink are redundant cues (Metro §3, §17). Badges never animate, and a badge never changes without its value changing.

| Badge | Glyph · ink | Means | Typical homes |
|---|---|---|---|
| **LIVE** | `circle.fill` 5-pt dot · action cyan | computed now from the current image and parameters, by the GPU for the frame on screen (or by the CPU on the current image for adaptive weight maps, which the GPU never stores; these say LIVE · CPU). A CPU re-computation of a GPU value is never LIVE (§6.4 item 6) | PIXEL chip, loupe value, Trace fetch rows (`TRACE_PROBE` records), floor 7 IN/OUT, adaptive weight maps, compare MAX \|A−B\|, the fingerprint strip's PSF/STAR/EDGE |
| **MEASURED** | `stopwatch` · instrument amber | timed or fitted on a **named device**, with OS build and date | GPU chip and telemetry GPU, parity, This phone values, Calibrate fits, ON THIS PHONE rows, Mac research values (labelled with the Mac) |
| **COMPUTED** | `equal` · display ink | an exact consequence of the math, computed by `BlurCore` in Double | Math, Kernel and Algorithm floor numbers; σ EFF; fetch counts; conversions; dispatch geometry; branch values |
| **MODELED** | `approximately` (≈) · spectrum violet | an estimate from a stated model, its assumption in the disclosure | bytes moved, bandwidth floors, ghost bars, scaled timings, our reconstructions of Apple materials and glass, hardware-quantized bilinear `t` |
| **REFERENCE** | `book.closed` · secondary ink | documented by a spec, header, paper or vendor source, cited in the Field guide | tool conventions (floor 1), API documentation (floor 2), Feature Set Tables limits, the shown shader source ("it is the code") |
| **INFERRED** | `questionmark` + **dashed** border · spectrum secondary | about internals nobody outside the vendor can see; measured live where possible and upgraded to MEASURED when a device measurement exists | SwiftUI `.blur` mechanism, render-server lane, Figma's σ rule, Photoshop internals, Liquid Glass and materials |

- **UNVERIFIED is a qualifier, not a seventh badge** (D §11.1). It appears only (a) as the value itself, in words, in place of a number (`Photoshop Gaussian Radius — UNVERIFIED`), or (b) as a trailing caption after a badge when a number exists but its source is weak (`51.2 GB/s · MODELED · UNVERIFIED PEAK`). It is set in secondary ink with no capsule, so it can never be mistaken for a provenance. **An UNVERIFIED figure is never shown as a bare number** (JD M11).
- **`SOURCES DISAGREE`** is a caption shown under two rows that each carry their own badge when two sources conflict (`CIZoomBlur` length law; `CALayer.shadowRadius` σ; SwiftUI's large-radius kernel shape). Disagreement is shown, never resolved silently (D §11.2 item 7, JD §2 Engine strength).
- **Inputs carry no badge.** The hero, Stepper values, crown captions and typed values are what he *set*; they are questions, not claims. Everything derived from them is badged (D §11.1).

### 12.2 Placement rules

1. **One badge per number, at the number.** Rows carry it at the trailing edge; telemetry under the label; floor pages carry the floor's dominant badges in the eyebrow and per-row badges where rows differ.
2. **The one compact exception: rail chips** show the glyph only (11 pt; INFERRED chips also get a dashed border); the shapes differ without colour; VoiceOver speaks the word. Stated in the legend. Everywhere else badge words are written in full, never abbreviated (`COMPUTED`, not `COMP.`); rows that do not fit wrap.
3. **Engraved provenance on instruments** (Los Alamos precedent, METRO §F.4 item 3) in the housing caption's right side: `LIVE · METAL`, `PREVIEW ½`, `SYSTEM · ON SCREEN · NOT READ BACK`, `SYSTEM · MEASURED (OFFSCREEN)`, `MODELED · METAL`, `INFERRED · NATIVE GLASS`, `CPU · 128² CROP · COMPUTED`, `PASS 1 OF 2 · INTERMEDIATE`, `TRACED BUILD` (while Trace is open), `PHOTO · RESAMPLED ×s (BOX)`.
4. **Pills**: `COMPUTED` (LSI), `LOCAL @ PROBE` with `● LIVE` (adaptive) or `= COMPUTED` (LSV), `N/A · RANK`, `NO SINGLE RESPONSE · SPACE-VARIANT`, `INFERRED — NOT EXPOSED`; engraved empty states, never blank.
5. **Device and date travel with MEASURED**: `MEASURED · iPhone 15 Pro Max · iOS 27.x · 14 Oct`, or `MEASURED · macOS 27.2 (M1 Max)` for research values. A Mac value is shown on the phone only with its Mac label until the phone replaces it (CAL §6 item 3).
6. **Upgrades are visible.** When This phone or Calibrate measures something that was REFERENCE, MODELED or INFERRED, the row keeps both values for the session (`32,768 B MEASURED · 32 KB REFERENCE`) so he watches the claim being checked (D W10, JD G20).
7. **Simulator honesty.** In the Simulator every timing is `nil`: the GPU chip reads `SIM`, telemetry reads `— NO GPU TIMING IN SIMULATOR` (GPU §2.7 item 4); A17 Pro rows read `NOT THIS DEVICE`; This phone's probes run but are labelled `SIMULATOR (APPLE2 LIMITS)`. Simulator GPU milliseconds are never shown (JD M11, JF M-16).
8. **No number without a badge** on any screen, except inputs (§12.1) and the coordinates in `Descend from (x, y)` (which are the probe he placed). Lines that mix words and numbers (status row, σ-hold notices, MIN H lines, Difference MAX/RMS, signatures with numbers, LOOKS MOST LIKE's distance) carry each number as badged data (ARCHITECTURE §5.1 `BadgedLine`); a lint test fails any view-bound plain string with digits outside its allow-list (equations, coordinates, identifiers).
9. **SwiftUI-derived values carry `OFFSCREEN`** on every surface: the chip mark, the spoken value and the caption. Every SwiftUI measurement is an offscreen `ImageRenderer` render; the two offscreen paths differ by 9 % and on-screen equivalence is UNVERIFIED (§13.3, §16).

### 12.3 Where each label dominates (by region)

| Region | LIVE | MEASURED | COMPUTED | MODELED | REFERENCE | INFERRED |
|---|---|---|---|---|---|---|
| Bench image and caption | output image, loupe | — | — | Tier S/exhibit reconstructions | — | native glass, system blur half |
| Rail | PIXEL | GPU | API, MATH, KERNEL, ALGO | — | SLIDE (most tools) | SLIDE (SwiftUI before calibration, Figma) |
| Telemetry | MAX \|A−B\| (compare) | GPU, PARITY | σ EFF | — | — | — |
| Floor 1 SLIDE | — | Apple APIs (device or Mac) | conversions | — | specs, vendor source | Figma, Photoshop internals |
| Floor 2 API | — | API laws | unit chain | — | API docs | SwiftUI blend space on screen |
| Floor 3 MATH | T(ν, A) at the probe | — | everything else | — | definitions | — |
| Floor 4 KERNEL | adaptive weight maps | — | weights, σ, ripple | — | — | system kernels (measured fit is MEASURED) |
| Floor 5 ALGORITHM | values after each pass | per-pass ms | counts | — | — | — |
| Floor 6 GPU | — | timings, pipeline limits | dispatch math | bytes, floors, `t` quantization | source, feature tables | render-server lane |
| Floor 7 PIXELS | IN/OUT | parity | encoding, branches, CPU reference | — | — | system offscreen values are MEASURED with path |
| Trace | fetch rows, Σ, OUT | — | CPU reference beside each | quantized `t` | — | — |
| Fingerprint | strip PSF/STAR/EDGE | ON THIS PHONE, LOOKS MOST LIKE | rows, UNIQUE, kurtosis dot | — | USED IN | system internals |
| This phone / Calibrate | — | everything measured | derived ratios | — | Feature Set Tables | regime-switch marker before measurement |

### 12.4 The legend

Field guide › Guide › `HONESTY LABELS`: one row per badge with glyph, ink, meaning, an example from the current blur, and the rules for UNVERIFIED, `SOURCES DISAGREE` and inputs. A long press on any badge anywhere opens this page scrolled to that badge (a `contextMenu` preview, with a button alternative in the element's accessibility actions).

### 12.5 The lens on this instrument

Field guide › Guide › `THE LENS ON THIS INSTRUMENT` (METRO §C.2, F.5 item 8), verbatim intent: "The glass on the controls and on the kernel well is Apple's Liquid Glass. It is drawn by the system; its lensing, scattering and tint are not exposed, and every figure about them is INFERRED. Blur2ool measures and models glass only in the Liquid Glass exhibit. The image you study is never under glass on the Bench, and every number is read back from Metal textures or from offscreen renders, never from the screen. When the page scrolls under the floating buttons, you are looking at the image through glass; the numbers are unaffected." Apple's own framing is quoted with its source: Liquid Glass "dynamically bends, shapes, and concentrates light" (WWDC25 session 219, REFERENCE) — the line between a warp (moves samples) and a blur (averages them).

## 13. Live calibration

Live calibration is how the app keeps the brief's INFERRED rule honest: internals it cannot see are **measured from outside, on this phone**, and the badges change when a measurement exists (BRIEF "Honesty rules"; E §3.7; JD G19–G20; JF G-17, G-18).

### 13.1 What is measured

| Subject | How | Produces | Where it shows |
|---|---|---|---|
| **SwiftUI `.blur(radius:opaque:)`** | `measurePSF` (CAL §7): `ImageRenderer` renders a black \| white step at the device's `displayScale` and colour mode, reads 16 centre rows in float, fits σ (moment and erf least squares), excess kurtosis, extent, support, centre offset, encoded midpoint; `phases > 1` moves the edge by whole device pixels to detect resampling | σ and σ/(r·scale) per radius; shape; centre wobble; blend space verdict; border behaviour; regime-switch radius | SLIDE chip and floor 1 (SwiftUI row); floor 2 (law); the SwiftUI crown's semantic stop; σ-hold conversion for SwiftUI; P26; the `swiftui-layer-blur` fingerprint |
| SwiftUI `.shadow(radius:)` | the same fit on a shadow pattern | σ/r (Mac: ≈ 0.96, MEASURED offscreen; shape closest to box³, INFERRED) | drop-shadow conventions (P27) |
| `CALayer.shadowRadius` | `render(in:)` of a layer with a shadow (software path; on-screen INFERRED) | σ/r; settles the `SOURCES DISAGREE` row | drop-shadow conventions |
| `CGContext.setShadow` | offscreen CG context | σ/blur (Mac: 0.44–0.47, tent-like) | drop-shadow conventions |
| Core Image / MPS / vImage twins | run in-process into Metal textures or bitmaps and read back (impulse + step + stripes) | σ, shape, edge policy, blend space (MEASURED, CAL §5.2–5.4) | Apple axis in Compare; floor 2 twins |
| Device GPU facts | This phone probes (§4.7): bilinear sub-texel bits, `generateMipmaps` impulse, copy bandwidth (blit and compute), compression A/B, FMA throughput, counter sampling points, traced = untraced | MEASURED device card | floor 6, Trace `t` quantization, bandwidth floor |
| Per-blur fingerprints | ON THIS PHONE (§7.1 item 10) | measured σ, kurtosis, shift, min H, ms/MP | fingerprint card, LOOKS MOST LIKE |

### 13.2 When it runs (never in the first ten seconds; never per crown detent)

- **SwiftUI basic set** (radii 0.5, 1, 2, 3, 4, 8 pt × 4 phases at `displayScale`, `.nonLinear`): automatically only when ≥ 10 s since launch **and** ≥ 3 s since the last touch **and** no crown/handle active **and** thermal state nominal or fair; one render per run-loop turn (`measurePSF` is `@MainActor`, CAL §7; a single `ImageRenderer` render cannot be pre-empted and the first one compiles RenderBox pipelines, so a 16-ms slice cannot be enforced): each render is timed, a render over 16 ms doubles the gap before the next, no render runs while a control is active, and any touch pauses the queue (JF M-3). Or immediately when he opens a Tier S blur. Once per OS build; re-offered when the OS build changes.
- **Full sweep** (34 radii × 4 phases, ≈ 12 s): on demand in Calibrate (`Run sweep`), with the primary progress shown in the sheet and the floating primary amber (running).
- **Device probes**: on demand (`Measure` per row, or `Measure everything · ≈ 20 s`), cached with OS build and date. One exception: the **bilinear sub-texel probe** (a ≈ 1 ms dispatch) runs once automatically in the background after the same idle gate, because in-app parity of every linear-sampled or gather blur depends on it (ARCHITECTURE §4.3).
- **ON THIS PHONE** fingerprint rows: when a fingerprint card opens, four small background dispatches (not timed per detent).

### 13.3 Calibrate sheet behaviour (§4.8)

- **API** menu: SwiftUI `.blur`, SwiftUI `.shadow`, `CALayer.shadowRadius`, `CGContext.setShadow`, `CIGaussianBlur`, `CIBoxBlur`, `CIDiscBlur`, `CIBokehBlur`, `CIMotionBlur`, `CIZoomBlur`, `CIMaskedVariableBlur`, `MPSImageGaussianBlur`, `MPSImageBox`, `MPSImageTent`, vImage box and tent.
- **PATH** menu (SwiftUI only): `ImageRenderer.cgImage` (default: CAL §5.1 item 7 argues it uses the GPU renderer that also draws on-screen content, INFERRED), `ImageRenderer.render(into:)` (a different blur: σ ≈ 0.98·r on the Mac, 9 % apart), and the **experiment** `drawHierarchy` on-screen capture (UNVERIFIED whether it captures render-server filters; its results stay labelled `ON-SCREEN · EXPERIMENTAL` until an objective capture test passes: a render-server-only effect, such as a `Material` over the known backdrop, must appear in the capture with the expected colour shift; a user's confirmation cannot change a provenance label).
- **Model competition** (E §3.7, JD G19): for each measurement, three models are fitted and their RMS residuals shown: Gaussian, Gaussian truncated at ±2.3σ (SDK §4's reading), and box³ (CAL §5.1's reading). The lowest residual gets a ✓; the app never picks a model in advance. Both research readings give σ ≈ 0.90–0.91·r and kurtosis ≈ −0.45 excess; the shape *interpretation* stays INFERRED, the numbers are MEASURED.
- **Sweep plot**: σ/(r·scale) against r (log axis), this iPhone's points filled, the macOS 27.2 reference dashed, the regime switch marked: hollow ◇ (INFERRED, ≈ 1.7–1.8 pt from 5 device px ÷ 3) until measured, then a filled marker (MEASURED) that also moves the SwiftUI crown's semantic stop.
- **Inside Apple** (INFERRED, dashed panel): `CAFilter gaussianBlur` → render server; QuartzCore kernel names engraved `NAMES FROM iOS 26.5 SIM / macOS 27.2 · NOT RE-READ FOR iOS 27 · NOT OBSERVED RUNNING`.
- Every result is a **Run** of kind `calibration` in the Run log (exportable JSON), so device numbers can replace the "MEASURED on macOS 27.2" figures in the research files (E §4.2, JF G-19).

### 13.4 Label lifecycle (what changes on screen when a measurement lands)

| Before | After the device measures |
|---|---|
| `≈ 10.8 px · INFERRED (macOS law 0.90·r·scale)` | `11.1 px · MEASURED · OFFSCREEN · iPhone 15 Pro Max · iOS 27.x` with the Mac value kept beside it for the session (illustrative values) |
| SwiftUI crown stop: hollow ◇ at 1.7 pt, INFERRED | filled stop at the measured switch, MEASURED |
| `CALayer.shadowRadius: SOURCES DISAGREE` | MEASURED σ/r on this phone (software path) with `ON SCREEN: INFERRED` |
| Floor 6 bandwidth floor `≈ MODELED · UNVERIFIED PEAK` | floor from the measured copy bandwidth, MODELED on a MEASURED ceiling |
| Trace `t` quantization `MODELED from M1 Max 8 bits` | `MODELED from this phone's N bits` (the probe runs once automatically, §13.2) |
| PARITY of bilinear blurs `SUB-TEXEL RULE NOT YET MEASURED` | pass/fail against this phone's MEASURED rule |
| Traced = untraced: `MEASURED · macOS (M1 Max)` | `MEASURED · this phone` (or the failure, stated) |

## 14. Accessibility

Metro treats accessibility settings as part of the contract (METRO §A.20). Blur2ool adds one rule (D §13): **every descent must be completable without seeing a pixel**: every visual on every floor has a spoken equivalent carrying the same number at the same precision.

| Need | What Blur2ool does |
|---|---|
| **VoiceOver: the image** | One adjustable element whose value starts with the provenance: "Live, Metal. Test image, Night City, blurred with Gaussian, sigma 12.0 pixels. Probe at 447, 455, output 0.0885 linear, live." Swipe up/down moves the probe ±1 px along x; rotor items `Probe axis` (x/y) and `Probe step` (1 / 16 px). Custom actions: `Descend from this pixel`, `Centre probe`, `Probe to brightest pixel`, `Probe to feature`, `Pan left/right/up/down 8 px`, `Zoom in`, `Zoom out`, `Reset view`, `Open loupe` (speaks the 14 × 14 neighbourhood's centre value). |
| **VoiceOver: handles and dividers** | Adjustable elements (±8 px, or ±10 % for dividers) with separate x/y rotor items and `Centre on probe` / `Centre on image`; numeric Stepper twins in the Parameters panel. |
| **VoiceOver: rail** | One element per chip, word badge spoken ("Floor 4 of 7, Kernel, 73 taps, computed. Double-tap to open the Kernel floor."). Rotor `Floors` jumps between the seven chips on the Bench, the seven pages in Layers and the seven tiles in Trace. In Compare: "Floor 3, Math, first difference: rectangle versus bell." |
| **VoiceOver: crowns** | Adjustable with the same fine step; the ± buttons are real buttons; the semantic crown's adjustable action moves one named stop and speaks the band ("Sigma 16.0 pixels, Backdrop"). |
| **VoiceOver: the core lesson** (review fix P-47) | On a blur switch, one announcement (not timed): the new blur's name, the held σ, the converted parameter, then its PSF SHAPE and RESPONSE rows ("Polygonal bokeh. Sigma held at 12.0 pixels: radius 26.3 pixels. Shape: flat hexagon, six straight edges. Response: six slow-decaying spokes, not circular zeros."). The σ-hold line stays in the readout's accessibility value until the next change, so it never depends on a 2-s notice. |
| **VoiceOver: Trace** | One announcement per step in fixed order (§6.6); `Next` is the default action of the context card. The 9 × 9 texel grid is a table: rows and columns navigable; each cell "x 446, y 300, input 0.000, weight 0.0999". |
| **Plots** | Every plot (pills, floor figures, fingerprint glyphs, Calibrate sweep) has an `AXChartDescriptor` (which also gives iOS Audio Graphs: the KERNEL pill becomes a rising and falling tone, the FREQ pill's negative lobes audible dips) and a `DisclosureGroup` data table with the same numbers (Los Alamos precedent, METRO §F.4 item 2). Axes are spoken with units and "normalized" where they are. |
| **Fingerprint matrix** | Every cell spoken as words (§4.5). |
| **Dynamic Type (AX1–AX5)** | §4.1.10: the root stays a scroll view with the same image gestures; the readout band becomes a native text block that starts with the provenance line; crowns stack; the rail becomes seven 44-pt rows; telemetry stacks; floor sections grow in the Layers scroll view (their slot heights come from the Dynamic Type size and the largest content any blur puts there, never from the current blur). Nothing below its Dynamic Type size; engravings disappear first. |
| **Reduce Motion** | No first-launch focus pull; pill traces snap; no probe fade, lens bounce or end-of-Trace highlight; `Play` in the Trace and animated specimens do not auto-advance (manual stepping works); `Flicker 2 Hz` unavailable. |
| **Reduce Transparency** | Kernel-well lens opacity 1.0 (never removed, unlike QuantumToy's drift, METRO §F.3 item 1); content panels opaque; the environment's cyan wash dropped; the floating group falls back to an opaque `safeAreaInset` strip. |
| **Increased Contrast** | Panel borders 0.20; pill outlines 0.70; badge borders 0.25; INFERRED badge's dashed border 1 pt; probe crosshair 1.5 pt with a 1-pt black keyline. |
| **Text that carries meaning scales** | The status row, caption row, rail values and badges use `@ScaledMetric` between default and AX1 (status and caption up to 15 pt, rail values up to 16 pt, badge glyphs never below 11 pt), with a stated truncation order (trailing qualifiers first, never a number or a badge word). Only decorative metadata may disappear (Metro §17). |
| **Colour never alone** | Probe amber **crosshair** vs centre amber **ring with a dot**; first divergent floor amber **plus** ▶ **plus** the words; negative lobes magenta **and** dashed **and** below a zero line; compare B **dashed**, C dotted, D dash-dot; badges lead with the word; selected strip glyph has an underline and the `isSelected` trait. |
| **Motor** | No gesture-only control (Metro contract A.18, JD M12): crowns have 44 × 44 ± buttons; Steppers hold-repeat; handles and dividers have adjustable actions and Steppers; the probe has an adjustable action; the loupe has `Open loupe`; driving B has a segmented control and accessibility actions (§8.2). All targets ≥ 44 × 44, including the Layers floor rail (44 wide). Switch Control order: header → blur strip → image → readout → rail → deck → floating group. |
| **Haptics** | Optional (Settings), never the only channel: every detent also changes a visible number. |
| **Photosensitivity** | §11 rule 4 (WCAG 2.3.1). |
| **Seeing pixels** | The loupe (8 pt per texel, value printed), pinch zoom up to 8× (nearest), and the Trace's `Magnify` (17 × 17) make one-pixel effects visible without good eyesight. Magnification is always of a copy or a nearest-neighbour present, never glass. |

What is **not** claimed: none of this is validated until it runs. Metro's validation list (native glass rendering, held and edge touches during redraw, Dynamic Type, Reduce Motion/Transparency, Increased Contrast, VoiceOver) applies to Blur2ool itself, with simulator, device and hands-on results kept separate (METRO §A closing paragraph). WCAG contrast of text over the cyan wash and under glass is UNVERIFIED until sampled from real screenshots (METRO §G.2 item 6).

## 15. Copy tone

His past feedback is the rule (JD §1): a numbered pipeline, real numbers, formulas shown, plain words; no metaphors he must decode (Loom); calm instrument chrome (Metro).

- **Plain words for places and actions:** "Blur2ool", "Blurs" (accessibility name of the strip), "Test image", "Layers", "Floor 4 · Kernel", "Compare", "Descend from (447, 455)", "Lessons", "Field guide", "This phone", "Calibrate", "Measure on this phone". Never on screen: Bench, Turret, periscope, deck, rail, specimen, Run (except the "Runs" log tab, which he chose as engineering curiosity, JD G24).
- **Labels** are ALL CAPS mono with tracking, short, with units: `SIGMA · PX`, `RADIUS · PT`, `74 FETCHES · 2 PASSES`. Counts carry their noun (`32 samples`, `2 passes`), never an invented symbol (Los Alamos `8 g` lesson, METRO §F.4 item 4). Units are spelled or standard-abbreviated: px, pt, ms, c/px, dB, EV, %.
- **Prose** is sentence case, short, present tense, second person sparingly. Questions as floor titles ("What finite numbers stand in for the curve?"). One sentence per idea.
- **Meaning words** (the serif italic line) are evocative but honest and labelled as Blur2ool's own (*Softened*, *Frosted*, *Backdrop*, *Fog*; *Drift*, *Rush*, *Warp*; *Edge-locked*, *Edge-aware*, *Nearly Gaussian*).
- **Signatures** are the catalog's one-liners: concrete, with a number where it helps ("The honest average: flat and square, and it turns fine stripes inside out (minimum response −0.217).").
- **Lessons and descents** have hook titles ("Why zoom blur spares a star"; "The blur that looks before it averages"; "Four line blurs make a hexagon"), and their closing lessons tell what happened to *his* pixel with its numbers.
- **Status lines** are terse engineering facts, not exclamations: `σ HELD 12.0 px → R 26.3 px`; `CORNER GAP 4.08 PX · GHOSTS`; `5 BLADES · NOT CENTRALLY SYMMETRIC → 2-D GATHER`.
- **Honesty language** is exact and unembarrassed: "measured on this iPhone", "measured on a Mac, not yet on this phone", "inferred: Apple does not expose this", "the sources disagree", "UNVERIFIED". Never "approximately Apple's", never a guessed number.
- **Errors** need text plus a symbol (amber already means activity, Metro §3): "GPU differs from the math by 3.1 % ⚠︎".
- **No exclamation marks, emoji, jokes, streaks or praise.** The instrument is calm; the delight is in the pictures and the feel.

## 16. Non-goals

| Not in v1 | Why |
|---|---|
| A tab bar | its floating glass covered live controls in QuantumToy and Los Alamos; one spine (METRO §F.3 item 3, JD M8) |
| More than three floating buttons; large persistent bottom controls | AssemblerToy build-5 rejection (METRO §F.1 item 1) |
| Onboarding, carousel, tips, splash, idle animation | one focus pull and one coaching line, once (JD M10) |
| A measuring screen, progress counter or placeholder slots at launch | JD M1, JF M-3 |
| Glass, `Material`, `.blur` or shaders over the image or a plot (except the labelled Liquid Glass exhibit); a glass or draggable lens | Specimen rule; Metro contract 2 (JD M9, JF M-10) |
| `Slider`s | §9.1 |
| Painting paths or masks; two-finger reset | no good accessible twin; gesture load (JF M-1, M-15) — preset menus instead |
| Line-up 4-up with arbitrary B sources | JF M-18; Line-up only for live triads (§8.3) |
| `Chart3D` / `SurfacePlot` kernel surfaces | phone performance UNVERIFIED; 2-D heat maps say the same and read aloud better (JF M-18) |
| Metal 4 command model; runtime compilation of shown shaders on device | simulator SDK stubs Metal 4; precompiled library + build-time byte-equality test instead (JF G-6, M-5, M-9) |
| Per-pass Metal 4 counter heaps | deferred past v1; classic per-encoder sampling where supported, command-buffer times otherwise (JF G-6) |
| A `LabKitMetro` package dependency | copy the starter (METRO §E.5) |
| Photo editing, export of blurred images, filter stacks, layers, undo | an instrument, not an editor; a "copy these numbers" action is a candidate for later |
| Live camera input | needs a permission prompt, nondeterministic, no ground truth (JD R5: a later decision for him, §18) |
| Custom kernel editor | kernels without fingerprints, tiers or CPU references |
| Configurable GPU internals (threadgroup size, sampler, tile size) | floor 6 must show the code that ran; variants are the only switch |
| Per-tap traces for FFT and global methods | every output pixel depends on every input pixel; the trace steps through frequencies instead |
| Modelled Photoshop internals presented as Photoshop's | UNVERIFIED; they appear only as UNVERIFIED rows |
| A σ for Liquid Glass, materials or on-screen SwiftUI blur labelled MEASURED | not capturable offscreen (glass) / on-screen capture UNVERIFIED; offscreen fits say `OFFSCREEN` |
| Live Windows or Android materials | cannot run on iOS; Tier 3 models only |
| Private API (`CAFilter`, `CABackdropLayer`, private `variableBlur`) | public API only; internals are INFERRED and measured from outside |
| Landscape, iPad, light appearance, tilt optics on the lens | portrait Metro layout, dark-only palette, `motionActive: false` in v1 (METRO §G.1) |
| Sound, sonification, quizzes, scores, streaks | not asked for; Metro feedback density |
| Network, accounts, analytics, third-party runtime code | BRIEF |
| XCUITest as the acceptance gate for gestures | QuantumToy's simulator automation failed; gestures are gated by unit-tested arbitration plus his hands-on device check (JF M-17) |

## 17. Corrections that bind (truth fixes)

The truth judge's run died before its verdict, but its interim notes list verified errors and suspected misconceptions in the concepts (JT). Combined with CATALOG §5's corrections, these bind every screen, string and test. Items marked "re-checked" were recomputed for this synthesis (`$TMPDIR/blur2ool-synth/checks.py`).

| # | Wrong or loose (where) | Binding statement |
|---|---|---|
| 1 | The explicit heat equation at λ = ¼ as the default (all three concepts) | At λ = ¼ the 5-point step has centre weight 0 and response **−1** at the Nyquist corner: a 1-px checkerboard flips sign every step and never fades, and the PSF lives only on even-parity pixels (JT (a); re-checked: G(π, π) = 1 − 8λ). **Default λ = ⅛** (response ≥ 0 everywhere, 64 iterations for σ 4); λ = 0.20 and ¼ remain selectable as the lesson "the stability limit is not the accuracy limit" (P16). |
| 2 | "Zoom blur is an exact box in log-polar" (concepts) | Exact only for **geometrically spaced** samples; with uniform-in-scale samples the density along ln r varies 0.950–1.050 (centred, a = 0.1) and 0.889–1.111 (one-sided, a = 0.2) (JT (d), re-checked). Copy says "approximately a box along rays (exact for geometric spacing)". |
| 3 | "MTF" for a signed response; "\|H\| with negative lobes" (concepts) | H(ν) is the signed frequency response; MTF = \|H\| ≥ 0. Contrast inversion is H < 0. The FREQ pill, fingerprint glyph and floor figures plot **signed H**; labels say `H` or "response", and "MTF" only for a modulus (JT note 3). |
| 4 | Kurtosis 3.0 vs 0 mixed (Instrument) | Always **excess** kurtosis (Gaussian 0, box −1.2, disc −1.0, tent −0.6, box³ −0.4, Laplace +3); every axis and row says "excess" (JT note 4). CATALOG's P23 "kurtosis 4.5" becomes excess **+1.5**. |
| 5 | 32 × 32 render tiles labelled COMPUTED (Engine) | 32 × 32 is the Apple9 **maximum** in the Feature Set Tables (REFERENCE); the tile size an ordinary render pass actually uses is not published (UNVERIFIED) (JT note 5, GPU §1.2). |
| 6 | Hexagon spectrum "sinc²"; "three line blurs make a hexagon" (Descent) | The flat hexagon is the **union of three rhombi** (each the convolution of two segments), weight ⅓ each, built by **four** one-sided line passes; its response is the sum of three rhombus terms (products of two sincs with phase). Three segments *convolved* give a hexagonal support but a peaked PSF (max/mean 3.07; JT (e)). |
| 7 | `CALayer.shadowRadius` as one number (concepts) | Three MEASURED research values disagree by ≈ 2× (σ = r/2 in STACK §0; ≈ 0.88–0.93·r via `render(in:)` in CAL §5.5; ≈ 0.94 r implied by CATALOG P27). Show `SOURCES DISAGREE` until this phone measures it (§13). |
| 8 | "A sampled Gaussian at σ 1 leaves 0.72 % at Nyquist" (all three concepts, P8) | 0.72 % is the **continuous** Gaussian. The app's sampled kernel (r = 3) leaves **1.41 %**; pixel-integrated 0.92 % (at truncation k ≥ 4; 0.87 % at the default k = 3, COMPUTED in ARCHITECTURE §14 (d)); Lindeberg's discrete Gaussian **13.5 %** (JT (f), re-checked). |
| 9 | SwiftUI's default gamma-space blend stated as a fact | MEASURED **offscreen** (`ImageRenderer`, `.nonLinear`); on screen it is INFERRED (CAL §5.1 item 5, JT note 7). |
| 10 | `CIZoomBlur` amount law stated as one number | Two MEASURED sources disagree (0.079 at amount 4 vs 0.085 predicted by the 1.5^(a/20) fit): `SOURCES DISAGREE`, exact law UNVERIFIED (CAT E5). |
| 11 | Kac 1939 cited for "the only separable isotropic kernel" | Cite Herschel (1850) / Maxwell (1860) or show the two-line derivation; Kac 1939 is further reading only, its content UNVERIFIED here (CAT E17). |
| 12 | `CIBoxBlur` "width ≈ r − 1" | width **W = 2⌈r/2⌉ − 1**; radii ≤ 2 do nothing (CAT E4, MEASURED). |
| 13 | `CIMotionBlur` filed under the box motion blur | it is a 1-px line with **Gaussian** weights, σ = r: the system twin of `anisotropic-gaussian` (CAT E5, MEASURED). |
| 14 | "The CoD 13-tap downsample" as one kernel | two kernels: `cod-13tap` (LearnOpenGL geometry, 36-texel footprint, ≤ 2.3 % shift variance) and `unity-13tap` (half the footprint; σ and shift variance computed by `BlurCore` tests); which matches Jimenez 2014 is UNVERIFIED (CAT E1, E2). |
| 15 | Heat-equation conventions mixed | canonical ∂u/∂t = Δu, **σ = √(2t)**; Lindeberg's ½Δ convention (σ² = t) only as an aside (CAT E9). |
| 16 | Kawase "shape error 14.7 %"; binomial shape errors | state the definition with the number: Kawase 16.5 % (1-D, max abs difference over the Kawase peak); binomial 12.8 / 6.4 / 3.2 / 1.6 / 0.78 % for n = 2…32 (CAT E14, E15). |
| 17 | SAT "unusable at full resolution" | fp32 SATs are inaccurate for **small boxes far from the origin** (a few 8-bit LSB at phone resolution); mean-centring fixes it (CAT E11). |
| 18 | Pyramid cost "≈ 9" vs "≈ 16.3" fetches | both MODELED with different accounting: ≈ 16 if the last level is full resolution, ≈ 9 if composited from half resolution; show the assumption (CAT E12). |
| 19 | The feasibility judge's M-8: "`await commandBuffer.completed()` after encoding main-actor textures is a Swift 6 compile error" (its §4.1 result was never written) | **Not reproduced.** In this synthesis, Swift 6.4 with `-strict-concurrency=complete -warnings-as-errors` typechecks both `await cb.completed()` in a `@MainActor` async method after encoding main-actor-owned textures and a `withCheckedContinuation` + `addCompletedHandler` pattern capturing only Sendable values, for the iOS 27 simulator and macOS SDKs (MEASURED here: `$TMPDIR/blur2ool-synth/iso/probeA–C.swift`, exit 0). ARCHITECTURE §5.8 freezes the continuation pattern anyway because it also returns GPU timestamps and errors as one Sendable value. |
| 21 | "The Gaussian never inverts / H > 0 everywhere" said of the kernel the GPU runs (card, pills, Compare) | True only of the **continuous** Gaussian. The truncated discrete kernel has min H −0.0012 at σ 12 and −0.0010 at σ 4 (k 3; fixtures), worse at k 2. Say `H ≥ 0 (CONTINUOUS)` and `TRUNCATED: RIPPLE` with the as-run value (review fix P-35). |
| 22 | "Excess kurtosis 0 identifies the Gaussian" (card UNIQUE) | Kurtosis 0 alone does not; the unique property is separable **and** isotropic at once (Herschel–Maxwell), tested as kurtosis on the axis = at 45° while separable (review fix P-58). |
| 23 | "Step response non-negative only for λ ≤ ⅛" (§5.2) | H ≥ 0 only for λ ≤ ⅛; the explicit kernel itself is non-negative (a monotone step response) up to λ = ¼ (review fix P-59). |
| 20 | "Traced and untraced builds are bit-identical" as an assumption (Descent R2) | False under default fast math with `sum += x * w` (≈ half of all output words differ by 1 ulp, JF §3.1, MEASURED M1 Max); true with explicit `fma()` accumulation. Bound by §6.4 and tested by the parity CLI. |

## 18. Open decisions for the user

The build proceeds with the **default** in each row; none blocks it. They are listed because they are taste calls or because they reverse a judge, and he may want to overrule them after the first device build.

| # | Decision | Default taken | Alternative |
|---|---|---|---|
| D1 | **The root scrolls** (JF) but its first viewport is the whole toy and the image owns its touches (JD). This reverses METRO §C.1's advice against owning touches on the whole 298-pt specimen; the reason is that four of the five gestures begin on the image, and the page still scrolls from the 270 pt of chrome around it (review fix P-67). | Scrolling root, one gesture regime at every text size | A fixed, non-scrolling Bench (Instrument's original), with a second layout at accessibility sizes |
| D2 | **Image gestures:** tap probe, drag pan/handle, long-press Metal loupe, pinch zoom (JD), with a unit-tested arbiter (answering JF's risk). | All five in v1 | Tap + handles + loupe only (JF's safer set) if the feel is wrong on his phone |
| D3 | **First launch:** Night City at σ 12 with a before/after split (JD), not a grey Siemens star (D) or a measuring screen (E). | Night City | Siemens star |
| D4 | **SwiftUI calibration** runs by itself once, after the app has been idle (≥ 10 s from launch, ≥ 3 s without touch), one render per run-loop turn, pausing at any touch. | Deferred automatic | Only on demand (Calibrate / first Tier S open) |
| D11 | **Night City's light energies** were raised (1-px lights 20–1,000) so that the first screen's σ 12 blur shows bright glows and crisp hexagons (review fix P-50). | Brighter lights at 0 EV | Keep 2–100 and launch at +3 EV (buildings then read 0.16–0.48) |
| D5 | **Display of HDR lights:** SDR, clipped at white. | SDR | HDR highlights through the XDR display's extended range (EDR) by default |
| D6 | **A live camera test image** (JD R5) needs a permission prompt and has no ground truth. | Not in v1 | Add later as an opt-in "Camera" test image |
| D7 | **Home tool** for the SLIDE chip and floor 1. | SwiftUI (points) | Figma, CSS, Photoshop, … (Settings) |
| D8 | **Inputs carry no badge** (hero, Steppers, typed values are questions, not claims). | No badge | A seventh word `SET` on inputs |
| D9 | **Scope:** all 62 entries in v1, built in the §10.3 order. | Everything | Cut Tier 2 from the bottom of §10.3 if time runs short |
| D10 | **Median controls.** §9.4 gives deck D (RADIUS crown 1–3, SHAPE segmented, NOISE DENSITY in the Parameters panel); §4.1.9 (d) sketches deck E (segmented `3×3 · 5×5` above a NOISE Stepper). | Deck D (§9.4 governs) | Deck E |

## 19. Acceptance summary (what QA checks against this SPEC)

1. **First ten seconds** (§2) on a cold first launch on the phone: Night City, σ 12, split at 50 %, probe (447, 455), focus pull once, coaching line once, `Descend from (447, 455)`, no spinner or placeholder (the sharp input until the first Run), at least 40 lights peaking at ≥ 0.25 linear after the blur (TESTIMAGES launch fixture), GPU chip `–.––` then MEASURED after settle; nothing measures for ≥ 10 s.
2. **Every screen exists** as wireframed (§4): Bench (with all variants a–g), Compare, Layers (7 floors, GPU tabs), Trace, Catalog (4 tabs), Fingerprint, Field guide (4 tabs), Calibrate.
3. **Every catalog entry** behaves per its tier (§10.2): 53 live glyphs; Tier 3 only in the Catalog; Tier S beside our model.
4. **Fixtures** (§5.3, §7.2, §8.4) reproduced by `BlurCore` tests and, for GPU values, by `blur-gpucheck`.
5. **Trace honesty** (§6.4): GPU fetch rows come from `TRACE_PROBE` records; traced = untraced bit-exact in the CLI; CPU values say COMPUTED.
6. **Honesty labels** (§12): no unbadged number (including numbers inside status and caption lines, checked by the lint); UNVERIFIED never a number; Simulator shows no GPU ms; MEASURED carries device and date; SwiftUI-derived values say OFFSCREEN; no Tier S card field is LIVE.
7. **Controls** (§9): each blur's deck arrangement, ranges, steps and defaults; no Slider; every parameter has a native twin in the Parameters panel.
8. **Metro contracts** (METRO §A): fixed foreground outside optics; constant lens opacity, fixed centre; static pill outlines; touch ownership; one `.sheet(item:)`; floating group with measured bottom reserve; no glass over the image except the exhibit.
9. **Accessibility** (§14) at AX5, Reduce Motion, Reduce Transparency, Increased Contrast, VoiceOver (a full descent completed by VoiceOver alone).
10. **Truth fixes** (§17) present in strings and numbers.

## 20. Traceability to the judges

**Delight judge (JD) grafts:** G1 → §4.1.3 (gestures; root scrolls per D1) · G2 → §2 · G3 → §4.1.2, §8.1 · G4 → §4.1.4 · G5 → §4.1.7 · G6 → §2 (4–6 s), §4.1.3 Pan · G7 → §4.1.3 Handles, §9.4 (paths as presets) · G8 → §4.3, §5 · G9 → §6.2–6.3 · G10 → §6.4 · G11 → §6.1, §6.4 item 5 · G12 → §7 · G13 → §8.4, §4.5 · G14 → §4.5 · G15 → §8.3 (Line-up limited to live triads) · G16 → §8.2 · G17 → §8.5 · G18 → §5.1 floor 1, §4.7 Settings · G19 → §13 · G20 → §4.7, §12.2 item 6 · G21 → §4.1.9 g · G22 → §4.1.3 status row, §9.2 (spin stops), §9.4 (blades) · G23 → §4.3 (periscope shows intermediates) · G24 → §4.7 Runs.
**JD must-avoid:** M1 → §2, §13.2 · M2 → §2 · M3 → §4.1.3 · M4 → §4.1.4 · M5 → §8.1 · M6 → §5.0 · M7 → §0, §15 · M8 → §4.1.7, §16 · M9 → §4.1.3, §16 · M10 → §2 · M11 → §12 · M12 → §14 Motor · M13 → §4.1.2 · M14 → §6.4 · M15 → §4.1.8.

**Feasibility judge (JF) grafts:** G-1 (Run) → §3, ARCHITECTURE §5.7 · G-2 (@MainActor GPU context, readback, generation tokens) → §4.1.6, ARCHITECTURE §5.8 · G-3 (timing protocol) → §4.1.6 · G-4 (half-res preview) → §4.1.6 · G-5 (safe dispatch) → ARCHITECTURE §4, §6 · G-6 (classic Metal, precompiled library) → §16, ARCHITECTURE §6 · G-7 (`TRACE_PROBE`, `fma`, traced frame) → §6.4 · G-8 (shown source byte-identical, SHA) → §5.1 floor 6 · G-9 (parity CLI) → ARCHITECTURE §3 · G-10 (generated floors) → §5.0 · G-11 (Parameters panel high) → §4.1.8 · G-12 (telemetry) → §4.1.8 · G-13 (declared control arrangement) → §9.1 · G-14 (σ-hold) → §8.1 · G-15 (local pills, T(ν, A)) → §4.1.3 Pills · G-16 (one-axis Compare) → §8.2 · G-17 (on-demand probes) → §4.7, §13.2 · G-18 (Calibrate, model competition) → §13.3 · G-19 (Run log JSON) → §4.7 · G-20 (honesty grammar) → §12 · G-21 (lens unmodified; magnify copies) → §4.1.3 · G-22 (procedural, feature probes, WCAG) → §11 · G-23 (build order) → §10.3, ARCHITECTURE §10.
**JF must-avoid:** M-1 → reduced and arbitrated gesture set, §4.1.3 (D2) · M-2 → scrolling root, one gesture regime (D1) · M-3 → §13.2 · M-4 → §4.1.6 · M-5 → §5.1 floor 6 · M-6, M-7 → §6.4 · M-8 → §17 item 19 · M-9 → ARCHITECTURE §4, §6 · M-10 → §16 · M-11 → §3, ARCHITECTURE · M-12 → §5.0 · M-13 → §4.1.8 · M-14 → §4.1.3 status row · M-15 → §9.4 · M-16 → §12.2 item 7 · M-17 → §16, ARCHITECTURE §11 · M-18 → §8.3, §16.

**Truth judge (JT, interim notes):** every listed suspicion is resolved in §17 (items 1–8) and the verified numbers are fixtures in §5.3, §7.2.

<!-- STATUS: COMPLETE -->
