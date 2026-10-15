# Blur2ool concept: Engine-first / GPU-truth-first

Date: 13 October 2026. Author: design agent (concept-engine). Status: complete.

Inputs, all read: `BRIEF.md`; `research/CATALOG.md` (complete, sections 0–8); `catalog-lsi.md` (§0–§19); `catalog-spatial.md` (§0, §1.1, §1.8–§2.3); `catalog-nonlinear.md` (§0, A1–A4, B1–B2, D6–D7); `stack-semantics.md`; `gpu-pipeline.md`; `live-calibration.md`; `metro-adaptation.md`; `sdk-feasibility.md`. Visual references viewed: Metro `assets/visual-reference.png`, `ClassicalMLSimulator/Documentation/Screenshots/workbench.jpg`, `LosAlamosSimulator/Documentation/QA/Trinity.jpg`, `Metro Station/Documentation/crowns-v4-preview.jpg`.

Probe script for the numbers in this document: `$TMPDIR/blur2ool-concept-engine/nums.py` (Python, standard library only). Every number below carries one of the BRIEF labels. Numbers I computed for this document are COMPUTED. Numbers copied from research files keep the label and platform they had there (most MEASURED values are **macOS 27.2 on the M1 Max**, not the phone). Wherever a screen would show a device measurement that does not exist yet, the wireframe shows a slot such as `‹0.__ ms›` rather than a made-up value.

---

## 0. One-line pitch

**Blur2ool is a pocket GPU lab: every blur runs as real Metal on your iPhone, is timed pass by pass on this phone, is checked against a CPU reference, and shows you its source code. Apple's own blurs are measured on the device and fitted the same way. Every number on screen says whether it was measured, computed, modeled, cited or inferred.**

The stance in one rule: *the app never shows a number about a GPU that it could have measured on this GPU instead.* Where it cannot measure (render-server internals, Liquid Glass, Photoshop), it says INFERRED or UNVERIFIED and shows why.

---

## 1. The first 10 seconds

The app opens straight onto the Bench. There is no splash screen, onboarding carousel or permission prompt. Everything below happens without any input from the user.

| t (s) | What the user sees | What the engine is doing | Label shown |
|---|---|---|---|
| 0.0 | Metro environment (canvas + cyan wash + 28-pt grid). Header `Blur2ool` / `BLUR LAB · WYSIWYG → GPU`. The housing is already drawn, and its window shows the unblurred Siemens star (36 cycles). | Builds the specimen texture (894 × 894 px, `rgba16Float`, linear light) and loads pipelines from the precompiled `default.metallib`. | caption `SPECIMEN · SIEMENS STAR 36 CYC` |
| ≈ 0.3 | The window shows the Gaussian blur at σ 8.0 px. The hero reads `8.0` with `SIGMA · PX` and *Frosted* (serif italic). The KERNEL and FREQ pills ease in from flat. | First dispatch: a linear-sampled separable Gaussian, 25 fetches per pass. The first frame is shown immediately, before any timing. | specimen caption `LIVE · METAL` |
| 0.3–1.5 | The status row reads `MEASURING · RUN 7/18`, then `18 RUNS · MEDIAN`. The GPU column of the telemetry goes from `—` to a value with a **MEASURED** badge. | 3 warm-up command buffers, then 15 timed ones. Each pass is its own encoder, so the per-pass times also come back (gpu-pipeline §4.3). It records `thermalState` and Low Power Mode. | MEASURED · this iPhone |
| 1.5–2.5 | The PARITY column fills in, e.g. `≤ 1 LSB` with MEASURED. | Reads back a 128 × 128 crop around the probe and compares it with the `BlurCore` CPU reference (Double). | MEASURED |
| 2.5–6 | A small chip under the header changes from `DEVICE · PROBING` to `APPLE9 · PROBED`. | First launch only: a background device probe (§3.8) measures the bilinear sub-texel bits, the `generateMipmaps` impulse response, blit and compute copy bandwidth, counter sampling points and threadgroup limits. It runs at low priority after the Bench is idle. | MEASURED, stored |
| 6–10 | Nothing moves. The crowns are lit and waiting. | First launch only: `measurePSF` of SwiftUI `.blur(radius:)` at r = 0.5, 1, 2, 3, 4, 8 pt, scale 3, 4 phases (live-calibration §7). This is the "Apple twin" that the Compare button can show. | MEASURED · ImageRenderer path |

The point of these ten seconds: **before the user touches anything, the app has already timed its own GPU and measured Apple's blur.** The first touch (turning the FINE crown) re-dispatches. The image updates within a frame. The status row says `RENDERING…` until the new timing exists, and only then does the GPU value change. Requested and acknowledged states stay separate (Metro contract A.13).

A one-line hint sits in the serif-italic slot under the crowns on first launch only: *Turn the crown. Every number below is timed on this phone.* It disappears after the first accepted change and never comes back.

On later launches the device probe and the Apple-twin fit come from the Run log (§4). The status row says `DEVICE PROBE · 2 DAYS AGO · iOS 27.1` and offers a re-run in the Instrument sheet when the OS build has changed.

---

## 2. Information architecture

### 2.1 Principles

1. **One root, no tab bar.** A Metro adopter's tab bar floats over live controls: QuantumToy's and Los Alamos's first viewports end on a half-covered control (metro-adaptation §F.3, §F.4). The Bench is the only root.
2. **One `.sheet(item:)` enum** for every sheet. Toothpaste Toy found that a second `.sheet` on the same view silently did nothing (metro-adaptation §F.5).
3. **Pushes for depth, sheets for side trips.** Descend (the layers) and Trace go deeper into the same blur, so they are pushed screens. Catalog, Calibrate and Instrument are side trips, so they are sheets.
4. **Everything is a view of a Run** (§4). Screens never compute their own numbers. They read the latest acknowledged Run, or ask the engine for a new one.

### 2.2 Screen map

| # | Screen | Presentation | Opened from | Purpose |
|---|---|---|---|---|
| S1 | **Bench** | `NavigationStack` root, `ScrollView` with `.id(blur.id)` | app launch | One blur, live: specimen, controls, telemetry, pass tiles, signal lab, fingerprint |
| S2 | **Descend** | push | floating group `Layers`; the fingerprint's layer strip | The 8 layers from WYSIWYG to pixels for the current blur, with this probe's numbers on every layer |
| S3 | **Trace** | push | floating group `Trace a pixel`; a long press on the specimen | One output pixel, fetch by fetch and pass by pass, with GPU readback against the CPU at every step |
| S4 | **Catalog** | sheet `.large` | the blur chip in the selector row | 55 entries + 7 contrast entries in 11 families + C, with tier and capability chips |
| S5 | **Calibrate** | sheet `.large` | Compare → `Apple twin`; the catalog's F10 rows; the Instrument sheet | Measures Apple's system blurs on the device (PSF fit, sweeps, model competition) |
| S6 | **Instrument** | sheet `.large`, `NavigationStack` + `Picker(.tabs)` `Device · Runs · Settings` | header glass icon button | Device card (probed limits), Run log (JSON export), global settings |
| S7 | **Field guide** | push inside S6, or sheet from the fingerprint's `Field guide` link | fingerprint card | Per-blur citations, UNVERIFIED list, the "lens on this instrument" note |
| M1 | **Compare** | in-place mode of S1 | floating group `Compare` | A/B on exactly one variable (§8) |

There are six destinations plus one in-place mode. Each of the sheets S4–S6 holds one job.

### 2.3 Navigation sketch

```
                 ┌───────────── S4 Catalog (sheet) ─────────────┐
                 │                                              │
  launch ──► S1 Bench ──push──► S2 Descend ──push──► S3 Trace (same probe)
                 │  │ └──push──► S3 Trace
                 │  └──in place──► M1 Compare ──"Apple twin"──► S5 Calibrate (sheet)
                 └──header icon──► S6 Instrument (sheet: Device · Runs · Settings) ──► S7 Field guide
```

## 3. Wireframes (iPhone 15 Pro Max portrait, 430 × 932 pt)

Conventions for every wireframe:

- One character is about 5.4 pt wide. Vertical positions are given in points in the left margin.
- Geometry follows metro-adaptation §D: screen inset 12, cluster width 406, D = 322, pill 36 × 212.5, image window 298 pt = 894 px at scale 3.
- The safe-area insets (59 / 34 pt) are the commonly published values and are UNVERIFIED (metro-adaptation §G.2 item 2). The engineering phase reads them from `GeometryReader`.
- Badge shorthand in the drawings: `[MEAS]` MEASURED, `[COMP]` COMPUTED, `[MOD]` MODELED, `[REF]` REFERENCE, `[INF]` INFERRED, `[LIVE]` LIVE. On screen these are the honesty-badge capsules described in §10.
- Slots shaped like `‹0.__›` mark device measurements that do not exist yet. They are not invented values.

### 3.1 S1 Bench, first viewport

This screen departs from metro-adaptation §D.1 in one deliberate way. Its first viewport puts the **telemetry row** directly under the crowns and moves the `DecimalParameterStepper` below the fold. Metro Station's own build-14 screen does the same: crowns flanked by real ± glass buttons, then a three-column telemetry row (`crowns-v4-preview.jpg`). The ± buttons, together with the crown's accessibility adjustable action, are the native alternative that Metro contract A.18 asks for. For an engine-first app, the GPU time and the parity have to be visible without scrolling. Everything still fits above the floating group with 29 pt to spare.

```
y pt   ┌─────────────────────────────── 430 pt ───────────────────────────────┐
   0   │░░░░░░░░░░░░░░░░░░░░░ status bar · Dynamic Island ░░░░░░░░░░░░░░░░░░░░│
  59   ├──────────────────────────────────────────────────────────────────────┤
  69   │  Blur2ool                                                   ╭──────╮ │
       │  BLUR LAB · WYSIWYG → GPU      ● APPLE9 · PROBED            │  ≡   │ │
 113   │                                                             ╰──────╯ │
 121   │ [▣ 44][‹ 44] [ Gaussian blur · F2 · LINEAR-SAMPLED     ▾ ] [› 44]    │
 165   │                                                                      │
 173   │       ╔════════════════ housing 322 × 440, r 30 ═════════════╗       │
       │       ║ SPECIMEN · SIEMENS STAR 36 CYC   LIVE · METAL · LIN  ║       │
 191   │       ║ ┌──────────── image window 298 pt = 894 px ────────┐ ║       │
       │       ║ │                                                  │ ║       │
 234   │ ┃KERN ║ │                                                  │ ║ FREQ┃ │
       │ ┃ −3σ ║ │               MTKView · LIVE GPU OUTPUT          │ ║ NYQ ┃ │
       │ ┃  │  ║ │                                                  │ ║  ↑  ┃ │
       │ ┃  │  ║ │                       ─┼─  probe (amber)         │ ║  │  ┃ │
       │ ┃  ↓  ║ │                                                  │ ║  │  ┃ │
       │ ┃ +3σ ║ │                                                  │ ║ DC  ┃ │
 446   │ ┃36pt ║ │                                                  │ ║ 36pt┃ │
 489   │       ║ └──────────────────────────────────────────────────┘ ║       │
 497   │       ║ SIGMA · PX                              ╭─ kernel ─╮ ║       │
       │       ║  8.0                                    │ well 88  │ ║       │
       │       ║ Frosted                                 │ lens 67  │ ║       │
 587   │       ║ 25 FETCH/PASS · 2 PASSES · LINEAR       ╰──────────╯ ║       │
 613   │       ╚══════════════════════════════════════════════════════╝       │
 625   │          FINE   ±0.1 PX                SIGMA · Frosted               │
       │     (−)  ( crown 62 )  (+)         (−)  ( crown 62 )  (+)            │
 723   │                                       Softened ⇆ Backdrop            │
 735   │   σ EFF            │   GPU · 2 PASSES     │   PARITY vs CPU          │
       │   7.91 px          │   ‹0.__› ms          │   ‹≤ _› LSB              │
 799   │   [= COMPUTED]     │   [⏱ MEASURED]       │   [⏱ MEASURED]           │
 828   │   ╭ Compare ╮  ╭────────── Trace a pixel ───────────╮  ╭ Layers ╮    │
 886   │   ╰ 62×58  ╯  ╰──── .glassProminent · flex ─────────╯  ╰ 54×58  ╯    │
 898   ├────────────────────────── home indicator ────────────────────────────┤
 932   └──────────────────────────────────────────────────────────────────────┘

```

| Element | Metro component | Frame (x, y, w, h) pt | Content and rules |
|---|---|---|---|
| Header | title + subtitle recipe (§4), `InstrumentGlassIconButton` (AssemblerToy hardened copy) | 24, 69, 382, 44; button 362, 69, 44, 44 | `Blur2ool` 27 pt semibold rounded. Subtitle 11 pt mono, tracking 2.6. The device chip `● APPLE9 · PROBED` is part of the subtitle line: cyan dot = probe valid; while the probe runs it reads `DEVICE · PROBING`. The ≡ glass icon opens S6 Instrument. |
| Selector row | glass icon buttons + chip | 12, 121, 406, 44 | `▣` specimen menu (Menu of test images, §11) · ‹ previous blur · **blur chip** 250 × 44 (name · family · active variant; opens S4) · › next blur. Prev/next walk the catalog order *within the tier filter* set in S4. |
| Specimen housing | `SpecimenHousing` (rectangular metal, tokens §B.5 of metro-adaptation) | 54, 173, 322, 440, r 30 | Caption row in the 18-pt top margin: specimen name (left) and engine provenance (right): `LIVE · METAL · LIN` or `· sRGB` (blend space, §5.0), `LIVE · CORE IMAGE`, `LIVE · SWIFTUI` (Apple twin), `MODELED` (our reconstruction of a material). Pixel rulers sit in the 12-pt side margins (minor tick 8 px, major 64 px). |
| Image window | `MTKView` in a `UIViewRepresentable`, on-demand drawing | 66, 191, 298, 298 = 894 × 894 px | The only thing in it is pixels plus the amber probe crosshair. **Specimen rule** (metro-adaptation §C.1): no glass, `Material`, `.blur()` or shader over the window. A tap moves the probe (`SpatialTapGesture`, no touch bridge). A long press opens S3 Trace. |
| KERNEL pill | `InstrumentSignalPill` (ported) | 12, 233.75, 36, 212.5 | Cyan. Tap offsets run downward −3σ → +3σ. Quiet trace = the continuous PSF profile; stems = discrete taps; depth colour = the effective kernel after all passes. For LSV and nonlinear blurs it shows the *local* kernel at the probe, labelled `AT PROBE`. |
| FREQ pill | same | 382, 233.75, 36, 212.5 | Violet. DC → NYQ upward. Primary = DFT of the discrete kernel; magenta = negative lobes; amber carrier marker at the −3 dB point. Nonlinear blurs: `N/A · NONLINEAR` engraved (§5.3). LSV blurs: `LOCAL · AT PROBE`. |
| Readout band | `InstrumentLargeReadout` adapted to a band | 66, 497, 298, 104 | Unit line `SIGMA · PX`; hero 44 pt light rounded, monospaced digits, showing the **requested** primary parameter; serif-italic meaning band; fixed 14-pt phase/status row (`25 FETCH/PASS · 2 PASSES · LINEAR`, `RENDERING…`, `MEASURING · RUN 7/18`, `PASS 1/2 · HORIZONTAL`). |
| Kernel well | `InstrumentLensSurface(diameter: 88, motionActive: false)` | 276, 505, 88, 88 | The one isolated native clear lens (0.48 opacity, 1.0 under Reduce Transparency) over an engraved Canvas of the 2-D footprint: σ rings for Gaussians, square for box, hexagon for polygonal bokeh, rays for zoom, `DATA-DEPENDENT` ring for bilateral. Tilt optics off in v1 (metro-adaptation §G.1 item 2). |
| Crown row | `InstrumentCrown` × 2 between 44 × 44 glass ± buttons | 41, 625, 348, 98 | Declared per blur family (§9). Default: FINE (±0.1 px, 8° detents) + SEMANTIC (octave stops, 20° detents). Integer-only blurs replace the crowns with a native `InstrumentParameterStepper` in the same 98-pt slot. |
| Telemetry row | `InstrumentMetricReadout` × 3 + `HonestyBadge` | 12, 735, 406, 64 | `σ EFF` (COMPUTED second moment of the effective discrete kernel; MEASURED when it comes from an impulse fit) · `GPU · n PASSES` (MEASURED median of 15, refreshed ≤ 4 Hz, struck through in the Simulator) · `PARITY vs CPU` (MEASURED max \|GPU − CPU\| on the probe crop, in 8-bit LSB). Dividers 1 × 30 white 0.10. |
| Floating group | `InstrumentFloatingActionGroup`, `GlassEffectContainer(spacing: 14)` | label frames 22…408, 828, h 58 | `Compare` 62 × 58 · **`Trace a pixel`** flexible, `.glassProminent` · `Layers` 54 × 58. No backing strip. The scroll content gets bottom padding = measured group height + 28. |

### 3.2 S1 Bench, below the fold

```
scroll ┌──────────────── Bench, scrolled one screen down (content y) ─────────┐
  +0   │   σ EFF            │   GPU · 2 PASSES     │   PARITY vs CPU          │
       │   7.91 px          │   ‹0.__› ms          │   ‹≤ _› LSB              │
       │   [COMPUTED]       │   [MEASURED]         │   [MEASURED]             │
 +76   │  ▸ More telemetry  FETCH/PX 50 [COMP] · 25.6 MB [MOD] · ms/MP [MEAS] │
+100   │  PASSES                                       ‹0.__› + ‹0.__› ms     │
       │ ┌──────── H ──────────┐ ┌──────── V ──────────┐ tiles 199.5 × 37     │
       │ │ ▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮ 25 │ │ ▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮ 25 │ radius 8, gap 7      │
       │ └─────────────────────┘ └─────────────────────┘ marks = fetches      │
+172   │  ┌─ SIGNAL LAB ────────────────────────────────── [MEASURED] ─────┐  │
       │  │ [ Kernel | Response | Error | Cost ]  Picker(.tabs), 32 tall   │  │
       │  │ ms (log) ↑                       o 2-D direct (to σ 4)         │  │
       │  │          │            o       o * separable·linear (this)      │  │
       │  │          │       o  *     *    # box³ running sum              │  │
       │  │          │   *  *  #  #  #  #  # + dual Kawase   ^ MPS         │  │
       │  │          │ +  +  +  +  +  ^  ^  ^   dots MEASURED here         │  │
       │  │          └──┬──┬──┬──┬──┬──┬──┬──→ σ px   dashes MODELED       │  │
       │  │            0.5 1  2  4  8 16 32 64   scope 374 × 140           │  │
       │  │ log-log slope: separable ‹_.__› · MPS ‹_.__›   [MEASURED]      │  │
       │  │ [ Sweep 8 σ × 7 algorithms ]  ≈ 1,000 dispatches, ≈ 10 s       │  │
       │  └────────────────────────────────────────────────────────────────┘  │
+466   │  ┌─ WHAT MAKES IT UNIQUE ───────────────── Gaussian blur ─────────┐  │
       │  │ The only blur that is round and separable at once.             │  │
       │  │ PSF      round, no rim · kurt axis ‹_› / 45° ‹_›  [MEAS]       │  │
       │  │ |H|      exp(−2π²σ²ν²) · half-amp 0.0234 c/px     [COMP]       │  │
       │  │ EDGES    erf S-curve, no overshoot · 10–90 20.5 px [COMP]      │  │
       │  │ COST     O(r) · 50 fetch/px · slope ‹_.__›   [COMP][MEAS]      │  │
       │  │ ARTIFACT square support on HDR lights at k = 3     [COMP]      │  │
       │  │ USED IN  CSS blur(), CIGaussianBlur, MPS, SVG       [REF]      │  │
       │  │ σ-matched twins: box³ · Kawase · SwiftUI    Field guide ›      │  │
       │  └────────────────────────────────────────────────────────────────┘  │
+790   │  ┌─ DESCEND ──────────────────────────────────── 8 LAYERS ────────┐  │
       │  │ [1 SLIDER] [2 API] [3 MATH] [4 KERNEL]    4 + 4 tiles          │  │
       │  │ [5 PASSES] [6 SHADER] [7 SILICON] [8 PIXELS]  each ≥ 44        │  │
       │  └────────────────────────────────────────────────────────────────┘  │
+922   │  bottom reserve = measured floating-group height + 28                │
       └──────────────────────────────────────────────────────────────────────┘
```

| Element | Metro component | Height pt | Content and rules |
|---|---|---|---|
| More telemetry | `DisclosureGroup` holding a second `InstrumentMetricReadout` row | 24 closed, 88 open | `FETCH/PX` (COMPUTED: texture reads per output pixel summed over passes) · `BYTES` (MODELED, ideal-cache model of gpu-pipeline §4.1) · `ms/MP` (MEASURED, GPU time ÷ megapixels, so window-size changes do not hide cost) |
| Pass tiles | `InstrumentEventTiles` | 60 per row | One tile per encoder: `H · V`; `0 1 2 2 3` (Kawase); `↓1 ↓2 ↓3 ↑3 ↑2 ↑1`; `ΣROW ΣCOL READ` (SAT); `P1 MRT · P2` (hexagon). Capsule marks = fetches per pixel for that pass, capped at 16 marks with the number beside them. Each tile's caption is that pass's MEASURED time. Tapping a tile puts that pass's **intermediate texture** in the specimen window, and the status row says which one is showing. |
| Signal lab | `InstrumentContentPanel` + `Picker(.tabs)` + Swift Charts | 282 | **Kernel** (1-D profile: continuous line, discrete stems, measured impulse response as dots) · **Response** (\|H(ν)\| linear/dB, −3 dB marker, magenta negative lobes; for nonlinear blurs the amplitude-transfer heat map T(ν, A)) · **Error** (GPU − CPU heat map in LSB on the probe crop, with a histogram) · **Cost** (MEASURED cost-vs-σ dots for every algorithm of the family, MODELED dashed lines, fitted log-log slope). Every chart has an `AXChartDescriptor` and a data-table disclosure. |
| Fingerprint card | `InstrumentContentPanel` | ≈ 300 | §7. Six fixed rows, each with badges; the serif-italic signature line on top. |
| Descend entry | 4 + 4 event tiles | 120 | Opens S2 at the tapped layer. |

### 3.3 M1 Compare mode (in place on S1)

```
y pt   ┌──────────────────── S1 in Compare mode (M1) ─────────────────────────┐
 121   │ [A Gaussian·LIN] vs [B ▾ CPU reference (Double)]  VARY: IMPLEMENT.   │
 165   │ [ Operator | Implementation | Precision | Space | Apple ]  .tabs     │
 173   │       ╔═ A · GPU LINEAR ══════════════ B · CPU DOUBLE ═══════╗       │
 191   │       ║ ┌────────────────────────┬┬────────────────────────┐ ║       │
       │ ┃KERN ║ │                        ││                        │ ║ FREQ┃ │
       │ ┃ A ━ ║ │     A half             ◀▶      B half            │ ║  A ━┃ │
       │ ┃ B ┄ ║ │                        ││                        │ ║  B ┄┃ │
       │ ┃     ║ │ divider handle 44 × 298││ owns its touches       │ ║     ┃ │
       │ ┃     ║ │                        ││                        │ ║     ┃ │
 489   │       ║ └────────────────────────┴┴────────────────────────┘ ║       │
 497   │       ║ VIEW [ Wipe | |A−B| ×64 | Flicker 2 Hz ]             ║       │
       │       ║ SIGMA · PX  8.0 (both)                 ╭ kernel ─╮   ║       │
       │       ║ Frosted                                │ A━  B┄  │   ║       │
 587   │       ║ MAX |A−B| ‹_› LSB at ‹x, y›            ╰─────────╯   ║       │
 613   │       ╚══════════════════════════════════════════════════════╝       │
 625   │          FINE   ±0.1 PX                SIGMA · Frosted               │
       │     (−)  ( crown 62 )  (+)         (−)  ( crown 62 )  (+)            │
 735   │   Δ GPU ms         │   CPU REF TIME      │   MAX |A−B|               │
       │   ‹+_.__› ms       │   ‹__› ms           │   ‹_› LSB                 │
 799   │   [MEASURED]       │   [COMPUTED]        │   [MEASURED]              │
 828   │   ╭  Done  ╮  ╭────────── Trace a pixel ───────────╮  ╭ Layers ╮     │
 886   │   ╰ 62×58  ╯  ╰────────────────────────────────────╯  ╰ 54×58  ╯     │
       └──────────────────────────────────────────────────────────────────────┘
```

- The selector row turns into the **A vs B** bar: A is the current configuration, and B is a menu whose options depend on the axis chosen in the `.tabs` picker below it. Compare **varies exactly one thing** (§8). The housing's top margin engraves both labels: `A · GPU LINEAR` and `B · CPU DOUBLE`.
- The divider handle is 44 × 298 pt and owns its touches (`instrumentControlOwnsTouches`). Its accessible value is "Split at 50 percent", adjustable in steps of 10%.
- `VIEW` is a segmented control in the readout band. **Wipe** shows A on the left and B on the right. **|A−B| ×64** is a difference heat map in 8-bit LSB, drawn as a luminance ramp with numeric contours, not as a colour scale only. **Flicker 2 Hz** alternates A and B, which makes small shape differences visible; it is disabled under Reduce Motion.
- In the pills, A is drawn solid and B dashed, so the two are told apart by shape as well as colour (metro-adaptation §D.3).
- The telemetry row switches to differences: `Δ GPU ms` · axis-specific column (`CPU REF TIME`, `Δ FETCH/PX` or `Δ σ EFF`) · `MAX |A−B|`.
- The floating group's left button becomes `Done`.

### 3.4 S2 Descend (pushed), shown on layer 7 "Dispatch & silicon"

```
y pt   ┌──────────────────── S2 Descend (pushed) ─────────────────────────────┐
  59   │ ‹ Bench        Gaussian · σ 8.0 px · probe (412, 488)                │
 103   │ [1 SLIDER ] [2 API    ] [3 MATH   ] [4 KERNEL ]   tiles 95.5 × 54    │
 165   │ [5 PASSES ] [6 SHADER ] [7 SILICON] [8 PIXELS ]   gap 8, 2 rows      │
 230   │  LAYER 7 OF 8 · DISPATCH & SILICON                      [MEASURED]   │
       │  ┌─ copy of output texture, 200 pt ─┐ OVERLAY                        │
       │  │▒▒▒▒░░░░▒▒▒▒░░░░▒▒▒▒░░░░▒▒▒▒░░░░▒ │ ( ) threadgroups 256 × 1    │  │
       │  │▒▒▒▒░░░░▒▒▒▒░░░░▒▒▒▒░░░░▒▒▒▒░░░░▒ │ ( ) SIMD-groups (32 lanes)  │  │
       │  │░░░░▒▒▒▒░░░░▒▒▒▒░░┏━━━┓▒▒▒░░░░▒▒▒ │ (•) apron of probe's group  │  │
       │  │░░░░▒▒▒▒░░░░▒▒▒▒░░┃ ┼ ┃▒▒▒░░░░▒▒▒ │ ( ) 32 × 32 render tiles    │  │
       │  │▒▒▒▒░░░░▒▒▒▒░░░░▒▒┗━━━┛░░░▒▒▒▒░░░ │ ( ) footprint 49 × 49       │  │
       │  └──────────────────────────────────┘ not the live specimen          │
 448   │  ┌─ DISPATCH ─────────────────────────────────────── per pass ────┐  │
       │  │ H  grid 4 × 894 TG · 256 × 1 threads · 8 SIMD-groups / TG      │  │
       │  │    tile 304 texels · static TG mem 3,072 B [MEAS] / 32 KB [REF]│  │
       │  │    texture reads/px 1.19 [COMP] · TG-mem reads/px 49 [COMP]    │  │
       │  │ V  grid 894 × 4 TG · 1 × 256 threads           (same tile)     │  │
       │  └────────────────────────────────────────────────────────────────┘  │
 566   │  ┌─ PASS TIMELINE ─────────────────── 15 runs, median, IQR ───────┐  │
       │  │ H ▕████████████░░░▏ ‹0.__› ms   ░ = MODELED ghost bar          │  │
       │  │ V ▕░░░░░░░░░░░░███████████████▏ ‹0.__› ms                      │  │
       │  │ gap ‹0.__› ms · cmd buffer ‹0.__› ms · thermal NOMINAL         │  │
       │  └────────────────────────────────────────────────────────────────┘  │
 664   │  ┌─ BYTES & ROOFLINE ─────────────────────────────────────────────┐  │
       │  │ moved 25.6 MB [MOD] · floor 0.50 ms at 51.2 GB/s [MOD,UNVER]   │  │
       │  │ ceiling measured here: copy ‹__› GB/s [MEAS] → floor ‹0.__›    │  │
       │  │ compression A/B: no .shaderWrite ‹0.__› vs with ‹0.__› ms      │  │
       │  └────────────────────────────────────────────────────────────────┘  │
 796   │  IN THIS APP  Timings come from per-encoder GPU counters on this     │
       │  phone. Apple's own .blur runs in another process; its passes        │
       │  are INFERRED from QuartzCore kernel names (see Calibrate).          │
 874   │  [ ↑ 6 Shader ]                    [ ↓ 8 Pixels ]   safeAreaInset    │
       └──────────────────────────────────────────────────────────────────────┘
```

- **Eight layers, not seven.** metro-adaptation §C.10 proposed seven layers. An engine-first app splits "Metal shader and dispatch" into **6 Shader** (the source text, what each line does, precision choices) and **7 Dispatch & silicon** (grid, threadgroups, SIMD-groups, apron, tiles, per-pass timing, bytes, roofline, compression). The 4 + 4 tile grid is also tidier than 4 + 3.
- Every layer page has the same four slots, in this order: `GOVERNING RULE` (callout mono, cyan), `FOLLOW THE PIXEL` (this probe's numbers at this layer), the layer's own instrument panel(s), and `IN THIS APP` (what is LIVE, MEASURED or INFERRED at this layer).
- The overlay image is a **copy** of the output texture, drawn in a Canvas with the overlay on top. The live specimen is never annotated (Specimen rule).
- Navigation: tiles jump to any layer. `↑ Higher` / `↓ Lower` sit in a `safeAreaInset(edge: .bottom)` bar, which is AssemblerToy's accepted exception for stepped flows (metro-adaptation §F.1 item 12). An `AnyNavigationTransition.crossFade` moves between layers (iOS 27, sdk-feasibility §12).

### 3.5 S3 Trace a pixel (pushed)

```
y pt   ┌──── S3 Trace a pixel (pushed) ───────────────────────────────────────┐
  59   │ ‹ Bench    Pixel (412, 488) · STEP EDGE at x 408 · σ 8.0 · LIN       │
 103   │  ┌─ CONTEXT ───────────────────────────────────────────────────────┐ │
       │  │ ┌ 13×13 ────┐  IN   linear 1.0000  encoded 255     [LIVE]       │ │
       │  │ │▓▓░░░░░░░░░│  OUT  linear 0.7137  encoded 220     [LIVE]       │ │
       │  │ │▓▓░░░░░░░░░│       (sRGB-space blur would give 182)  [COMP]    │ │
       │  │ │▓▓░░░░┼░░░░│  Completed: H pass · 25 fetches   (amber)         │ │
       │  │ │▓▓░░░░░░░░░│  Next:      V pass · 25 fetches   (cyan)          │ │
       │  │ └ copy, not the specimen · ▓ 0.0 ░ 1.0 · edge at 408            │ │
 235   │  └─────────────────────────────────────────────────────────────────┘ │
 247   │  [1 SLIDER] [2 API] [3 MATH] [4 KERNEL]   layer grid, 4 + 4          │
       │  [5 PASSES] [6 SHADER] [7 SILICON] [8 PIXELS]   selected: 8          │
 371   │  ┌─ PASS 1/2 · HORIZONTAL · FETCH TABLE ───────────────────────────┐ │
       │  │  #  offset   texels     t     weight   value    Σ (float)       │ │
       │  │  0   0.000   412        —    0.04998  1.0000   0.04998          │ │
       │  │  1  +1.494   413|414   .494  0.09803  1.0000   0.14801          │ │
       │  │  2  −1.494   410|411   .506  0.09803  1.0000   0.24604          │ │
       │  │  …                                 (25 rows, scrollable)        │ │
       │  │ 24  −23.41   388|389   .591  0.00136  0.0000   ‹0.____›         │ │
       │  │ half(Σ) = ‹0.____›  ·  CPU Double ‹0.____›  ·  Δ ‹_› LSB        │ │
       │  │ t is the hardware bilinear weight: ‹8› bits on this GPU [MEAS]  │ │
       │  │ fragment in render tile (12, 15) of 28 × 28 tiles      [COMP]   │ │
 640   │  └─────────────────────────────────────────────────────────────────┘ │
 652   │  ▸ All Pixels-layer details (running sum per tap, rounding)          │
 874   │  [ ‹ Back ]      [ ↺ Restart ]      [  Next pass ›  ]   58 tall      │
       └──────────────────────────────────────────────────────────────────────┘
```

- This follows the AssemblerToy guide pattern that he accepted after its ergonomics pass (metro-adaptation §F.1 items 7–9): a compact context card, then the layer grid, then one selected layer's primary facts, with the rest behind a `DisclosureGroup`.
- The numbers shown are the real worked example from §5.1: a black | white step edge at x = 408, the probe 4 px into the white side, a linear-light blend, σ = 8, and the linear-sampled kernel. The OUT value 0.7137 (encoded 220) and the sRGB-space alternative of 182 are COMPUTED by `nums.py`. The `‹…›` slots are GPU readbacks that will exist only on the device.
- Each fetch row names the **two texels** the bilinear fetch blends and its fraction `t`. The footnote says `t` is quantized by the hardware to the number of bits measured by the device probe (8 on the M1 Max, MEASURED there; UNVERIFIED on the A17 Pro until the probe runs).

### 3.6 S4 Catalog (sheet)

```
y pt   ┌──── S4 Catalog (sheet, .large) ──────────────────────────────────────┐
  70   │   ━━━━ grabber                                         Done          │
 100   │  ⌕ Search 62 entries                                                 │
 150   │  [ All | Runs on GPU | Measured system | Atlas ]   .tabs             │
 200   │  F2 · GAUSSIAN & ITS APPROXIMATIONS · 3                              │
       │  ┌──┐ Gaussian blur                      [T1] ✓ selected             │
       │  │◎ │ round and separable · no inversion  O(r) · GPU·CPU·TRACE       │
       │  └──┘ variants: 2-D · separable · linear · integrated · Lindeberg    │
       │  ┌──┐ Binomial (Pascal) blur              [T1]                       │
       │  │▦ │ erases a 1-px checkerboard exactly  O(n) · GPU·CPU·TRACE       │
       │  └──┘                                                                │
       │  ┌──┐ Recursive (IIR) Gaussian            [T1]                       │
       │  │◌ │ any σ, 8 MACs; exponential tails    O(1) · GPU·CPU·TRACE       │
       │  └──┘                                                                │
 520   │  F10 · UI MATERIALS (THE WYSIWYG LAYER) · 7                          │
       │  ┌──┐ SwiftUI .blur(radius:)              [S] measured here          │
       │  │◎┄│ Gaussian to 5 px, box³-like above   system · CALIBRATE ›       │
       │  └──┘                                                                │
       │  ┌──┐ Fluent Acrylic                      [T3] atlas only            │
       │  │▒ │ σ 30 DIP + luminosity blend          MODEL · CPU PLOT          │
       │  └──┘                                                                │
 760   │  C · NOT BLURS (CONTRAST) · 7                                        │
       │  Unsharp mask · DoG · Min/max · Pixelate · Lanczos · …               │
       └──────────────────────────────────────────────────────────────────────┘
```

- A native `List` with `.searchable`, one section per family, and each section header carrying a count. The filter picker answers the engine-first question first: **what actually runs on this phone's GPU?** `Runs on GPU` covers Tier 1 and Tier 2. `Measured system` covers Tier S. `Atlas` covers Tier 3 (CPU plots and models only).
- Every row carries **capability chips**, so tier honesty is visible before a blur is opened: `GPU · CPU · TRACE` (Tier 1), `GPU · CPU` (Tier 2), `system · CALIBRATE ›` (Tier S), `MODEL · CPU PLOT` (Tier 3).
- Row: a 40 × 40 Canvas glyph of the footprint (the same drawing as the kernel well), the name, the one-line signature from CATALOG §2, a cost-class chip and a tier chip. Rows are at least 64 pt tall.

### 3.7 S5 Calibrate · Apple twin (sheet)

```
y pt   ┌──── S5 Calibrate · Apple twin (sheet, .large) ───────────────────────┐
  70   │   ━━━━                                                  Done         │
 100   │  API [ SwiftUI .blur(radius:) ▾ ]   path [ ImageRenderer ▾ ]         │
 150   │  RADIUS  [ −   2.0 pt   + ]  = 6.0 device px at scale 3              │
 206   │  ┌─ RESULT · RUN 14:02 · iPhone 15 Pro Max · iOS 27.x ─────────────┐ │
       │  │  σ          ‹_.___› px   σ / (r·scale) ‹0.___›      [MEAS]      │ │
       │  │  kurtosis   axis ‹−0.__›  45° ‹−0.__›                 [MEAS]    │ │
       │  │  MODEL FIT  Gaussian ‹_%› · box³ ‹_%› · trunc-G ‹_%› [MEAS]     │ │
       │  │  wobble     edge centre spread over 4 phases ‹_.__› px [MEAS]   │ │
       │  │  blend      stripes ‹0.5__› → gamma-encoded           [MEAS]    │ │
       │  │  border     opaque:false → transparent, spills        [MEAS]    │ │
       │  │  Mac ref.   σ/r 0.906 at 6 px (macOS 27.2, M1 Max)    [MEAS]    │ │
 452   │  └─────────────────────────────────────────────────────────────────┘ │
 464   │  ┌─ SWEEP · σ / (r·scale) vs r ────────────────────────────────────┐ │
       │  │ 1.0 ┤●●●●●●○                 ● this iPhone   ○ predicted        │ │
       │  │     │       ○ ○                ┄ macOS 27.2 reference           │ │
       │  │ 0.9 ┤          ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄                      │ │
       │  │     └──┬────┬────┬────┬────┬────┬─→ r pt (log)                  │ │
       │  │       0.5   1   1.8   4    8   32     switch ≈ 1.8 pt [INF]     │ │
       │  │ [ Run sweep · 34 radii × 4 phases ]   ≈ ‹_› s                   │ │
 680   │  └─────────────────────────────────────────────────────────────────┘ │
 692   │  ON-SCREEN PATH (experimental) · drawHierarchy capture  [INF]        │
       │  ‹not yet run› · may not capture render-server filters               │
 760   │  INSIDE APPLE (INFERRED): CAFilter gaussianBlur → render server      │
       │  QuartzCore kernels tile_downsample_{1,2,4,8} · tile_simd_blur_5…27  │
       │  read from iOS 26.5 Simulator runtime; not observed running          │
       └──────────────────────────────────────────────────────────────────────┘
```

- APIs offered: SwiftUI `.blur`, `.shadow`; `CIGaussianBlur`, `CIBoxBlur`, `CIDiscBlur`, `CIBokehBlur`, `CIMotionBlur`, `CIZoomBlur`, `CIMaskedVariableBlur`; `MPSImageGaussianBlur`, `MPSImageBox`, `MPSImageTent`; vImage box and tent; `CALayer.shadowRadius`. Paths offered for SwiftUI: `ImageRenderer.cgImage`, `ImageRenderer.render(into:)` (the two differ by 9% in σ on the Mac, live-calibration §5.1 item 7), and the experimental on-screen capture.
- **Model competition.** Several fits compete for the same measurement, and the app shows the residual of each. For SwiftUI's large-radius kernel, the research produced two readings of the same data: a Gaussian truncated at ±2.3σ (sdk-feasibility §4) and a box³-like kernel (live-calibration §5.1). The app does not pick one in advance. It fits both on the phone and shows which one wins.
- The predicted regime switch at 1.8 pt on the iPhone (5 device px ÷ scale 3) is INFERRED from the Mac and drawn as a hollow marker until the device sweep replaces it.

### 3.8 S6 Instrument (sheet), Device tab

```
y pt   ┌──── S6 Instrument (sheet) · Device tab ──────────────────────────────┐
  70   │   ━━━━                                                  Done         │
 100   │  [ Device | Runs | Settings ]           Picker(.tabs)                │
 150   │  iPhone 15 Pro Max · A17 Pro · iOS 27.x · probed ‹date›              │
 190   │  ┌─ LIMITS                  THIS PHONE        FEATURE TABLE ───────┐ │
       │  │  GPU family              ‹Apple9› [MEAS]    Apple9 [REF]        │ │
       │  │  threadgroup memory      ‹32,768 B›         32 KB               │ │
       │  │  threads / threadgroup   ‹1024›             1024                │ │
       │  │  SIMD width              ‹32›               32                  │ │
       │  │  32-bit float filtering  ‹yes/no›           not promised        │ │
       │  │  counter sampling        ‹stage only?›      —                   │ │
       │  │  Metal 4 timestamp clock ‹__ MHz›           —                   │ │
 440   │  └─────────────────────────────────────────────────────────────────┘ │
 452   │  ┌─ PROBES                                       [MEASURED] ───────┐ │
       │  │  bilinear sub-texel bits ‹8›   (M1 Max: 8, 1/512 max error)     │ │
       │  │  generateMipmaps filter  ‹2×2 box›  (impulse 1 → 0.25 → 0.0625) │ │
       │  │  copy bandwidth  blit ‹__› GB/s · compute ‹__› GB/s             │ │
       │  │  vs 51.2 GB/s leak-derived figure              [UNVERIFIED]     │ │
       │  │  FMA throughput ‹___› GFLOP/s (fp32) · ‹___› (fp16)             │ │
       │  │  compression A/B  fragment no-write ‹_.__› vs write ‹_.__› ms   │ │
       │  │  thermal NOMINAL · Low Power Mode off · on charger ‹?›          │ │
 730   │  └─────────────────────────────────────────────────────────────────┘ │
 742   │  [ Re-probe (≈ 4 s) ]          [ Export Run log (JSON) ]             │
 800   │  Simulator detected → timing rows struck through, Apple2 limits      │
       └──────────────────────────────────────────────────────────────────────┘
```

- **Runs tab.** A list of Run records (§4), newest first, each showing the blur, its parameters, the median ms, parity, thermal state and OS build. Swipe to delete. `Export` produces JSON through `ShareLink`. This is the lab notebook.
- **Settings tab.** A `Form`: blend space default (linear / sRGB-encoded), precision (fp16 storage + fp32 accumulation by default; experimental fp16 accumulation), edge mode (clamp / mirror / zero / normalized), timing runs (N = 15, warm-ups = 3), preview resolution while a crown turns (full / half, default half for O(r²) and gather blurs), haptics, badge visibility (badges cannot be hidden on MEASURED and INFERRED numbers; they can be compacted to the glyph alone).
- Device facts are MEASURED on the phone, with the Metal Feature Set Tables value (21 May 2026) beside each as REFERENCE (gpu-pipeline §2.2).

## 4. The primary object

### 4.1 What the user sees: the Specimen instrument

The visible primary object is the **Specimen instrument**: a rectangular metal housing around a live `MTKView` of the blurred test image, with the readout band, the kernel well and the two flanking pills (§3.1). The arguments for a rectangle rather than Metro's round gauge are in metro-adaptation §C.1 and I accept them: pixels are judged on square grids, and a centred hero would hide the pixels being measured. Los Alamos's `TRINITY / OBSERVATION 01` instrument (viewed) shows that a rectangle with a band under it reads as Metro.

### 4.2 What the engine holds: the Run

Underneath, the engine-first concept has one data object, the **Run**. Every number on every screen is a field of a Run, or is computed from Runs. A Run is an immutable record of one measured execution:

| Field group | Contents | Label of each field |
|---|---|---|
| Identity | catalog id, variant id, parameter values (requested), specimen id, blend space, precision mode, edge mode, preview scale | — (inputs) |
| Context | device model, GPU family, OS build, `thermalState` at start and end, Low Power Mode, battery charging state, Simulator flag | MEASURED |
| Kernel | effective discrete weights or tap list (from `BlurCore`), fetches per pixel per pass, σ_eff, kurtosis | COMPUTED |
| Timing | per-pass GPU ms (median, IQR, N = 15 after 3 warm-ups), command-buffer ms, gaps | MEASURED |
| Cost model | bytes moved per pass, bandwidth floor, ALU estimate | MODELED |
| Correctness | parity on the probe crop: max and RMS \|GPU − CPU\| in 8-bit LSB, and its location | MEASURED |
| Shape | impulse and step responses read back from the GPU output: fitted σ, kurtosis on axis and at 45°, shift variance over 4 phases, MTF minimum from the measured PSF | MEASURED |
| Provenance | SHA-256 of the `.metal` source text shown on screen, compile options (math mode) | REFERENCE (it is the code) |

Why a Run and not live state:

1. **Requested vs acknowledged becomes structural.** The crown writes the request instantly. The image, pills and telemetry show the newest *completed* Run. The status row reads `RENDERING…` while the two differ (Metro contract A.13).
2. **Comparisons are honest by construction.** Compare (§8) is a diff of two Runs, which must have identical fields except for the one axis being varied. If the thermal state changed between them, the Δ GPU ms column gets a footnote `THERMAL CHANGED` and stays, unhidden, under its MEASURED badge.
3. **The Run log is the lab notebook.** It survives launches, so the first-10-seconds probes are not repeated, and it exports as JSON. The research team can then read device numbers and replace every "MEASURED on macOS" figure in the docs.
4. **Staleness is visible.** A Run measured on an older OS build is marked with that build in its badge text (`MEASURED · iOS 27.0`), and Calibrate offers a re-run.

Timing protocol (gpu-pipeline §4.3, sdk-feasibility §6). Each blur gets one command buffer, and each pass is its own encoder, so that stage-boundary counter samples give per-pass times on Apple GPUs. That is the only sampling point the M1 Max supports (MEASURED); the same is expected on the A17 Pro (INFERRED). On the device only, when `supportsFamily(.metal4)` is true, an optional path writes `.precise` Metal 4 counter-heap timestamps between dispatches (MEASURED to work on the M1 Max). This path is compiled out of Simulator builds, because the Simulator SDK lacks the API. The engine itself stays on classic Metal, as sdk-feasibility §7 recommends. GPU ticks are converted with `sampleTimestamps()` or `queryTimestampFrequency()` at run time and never assumed. In the Simulator every timing field is recorded as `nil` and drawn struck through, because Simulator GPU times are meaningless (a 1 GB copy "took" 0.055 ms, gpu-pipeline §2.7).

---

## 5. WYSIWYG → GPU: how the layers are presented, with four worked examples

### 5.0 The eight layers

| # | Layer | Governing question | Instrument on the layer page | Typical labels |
|---|---|---|---|---|
| 1 | **Slider** (WYSIWYG) | What number do designers type, in which tool, to get *this* blur on *this* phone? | "Same blur, many dials" table: tool · control · value · resulting σ in device px | REFERENCE, MEASURED (Mac or device), INFERRED, UNVERIFIED |
| 2 | **API** | What does the parameter mean in code, and in what units and colour space? | Conversion card (pt ↔ px at scale 3, radius ↔ σ), blend space, edge policy, `opaque`/normalization | REFERENCE, MEASURED |
| 3 | **Math** | What is the continuous operator? | Equation (callout mono), continuous PSF and \|H(ν)\| plots, or the local / amplitude-dependent substitutes for LSV and nonlinear blurs | COMPUTED |
| 4 | **Kernel** | What exact discrete weights are used, and what did discretization cost? | Tap stems + continuous overlay, truncation table, DFT of the taps; for LSV blurs a PSF field (spot diagram), for nonlinear blurs the weight map at the probe | COMPUTED, LIVE |
| 5 | **Passes** | Which algorithm, how many passes, what each intermediate looks like? | Pass tiles with intermediate thumbnails, fetch counts, the algorithm toggle for the variants | COMPUTED, LIVE |
| 6 | **Shader** | What code runs? | The `.metal` source with line annotations, its SHA, compile options, precision notes | REFERENCE |
| 7 | **Silicon** | How is it dispatched, and what does it cost on this GPU? | Dispatch geometry overlay (on a copy), pass timeline, bytes and roofline, compression A/B, tile view | MEASURED, MODELED, COMPUTED |
| 8 | **Pixels** | What came out at the probe, and does it agree with the CPU? | Probe IN/OUT in linear and encoded values, parity, rounding, the link to Trace | LIVE, MEASURED, COMPUTED |

For Apple system blurs (Tier S), layers 5–7 are drawn with **dashed borders and the INFERRED badge**. They hold the 2014 five-pass diagram (WWDC 2014 session 419) and the QuartzCore kernel names read from the iOS 26.5 Simulator runtime (gpu-pipeline §1.1). The app cannot see that work. Layers 1, 2 and 8 hold MEASURED fits from Calibrate.

**Units everywhere:** "px" means a texel of the specimen texture, which is one device pixel. The window is 894 px = 298 pt, so 1 px = 0.33 pt. Every page that mixes the two shows the conversion.

**Blend space (the linear-light truth).** The specimen is stored as linear light in `rgba16Float`. The default blend is **linear light**. A global toggle switches the engine to blending **sRGB-encoded** values: it encodes before the blur and decodes after, which is what CSS `filter: blur()` and SwiftUI's default `.nonLinear` mode do (stack-semantics §7, live-calibration §5.1). The housing caption always shows which is active (`LIN` or `sRGB`). The stripes test (§11) measures the difference: 0.500 vs 0.735 encoded.

### 5.1 Worked example: Gaussian blur, σ = 8.0 px, linear-sampled, linear light, specimen = step edge

| Layer | What the page shows (real numbers) | Labels |
|---|---|---|
| 1 Slider | To get σ = 8 device px on this phone: CSS `filter: blur(2.67px)` (σ = value in CSS px, ×3). Figma layer blur **5.33** (σ = value/2; from Figma's own CSS export rule). SwiftUI `.blur(radius: 2.67)` *nominally*, but the measured large-radius law σ ≈ 0.90·r·scale says **2.96 pt** for an effective 8 px (macOS law; the device value comes from Calibrate and replaces it). `CIGaussianBlur` inputRadius **8** (σ = r). `MPSImageGaussianBlur` sigma **8**. Android `RenderEffect` radius **13.0 px** (σ = 0.57735·r + 0.5). GIMP 2.8 "Blur Radius" **25.6** (σ = (r+1)/3.329) vs GIMP 2.10 "Size" **8**. ImageMagick `-blur 0x8` (a bare `-blur 8` would be σ = 1). Photoshop Gaussian "Radius": **unknown**. | REFERENCE (CSS, MPS, Skia/Android, GIMP, ImageMagick source); INFERRED (Figma); MEASURED macOS → device (SwiftUI, CI); UNVERIFIED (Photoshop) |
| 2 API | `σ = 8.0 px = 2.67 pt`. This app's kernel takes σ in px; `BlurCore` builds the taps. Blend space linear; edge clamp-to-edge; premultiplied alpha. Side note: Core Image blends in linear light by default, SwiftUI in gamma-encoded values by default. Same σ, different pixels. | REFERENCE, MEASURED (Mac) |
| 3 Math | G(x) = e^(−x²/2σ²)/(σ√2π); Ĝ(ν) = e^(−2π²σ²ν²). Half amplitude at **0.0234 c/px**; FWHM **18.84 px**; step 10–90% width **20.5 px**; response at Nyquist e^(−π²σ²/2) ≈ 10⁻¹³⁷, i.e. zero for any display. Semigroup: two σ = 8 blurs equal one σ = 11.3. No negative lobes, so the zone plate fades in perfect circles. | COMPUTED |
| 4 Kernel | Sampled and normalized, truncated at k = 3 → r = 24, **49 taps**. Centre weight **0.04998**; edge tap / peak **0.0111**; mass beyond ±3σ 0.27%. The truncated kernel's own σ is **7.91 px** (this is what `σ EFF` shows, not 8.00). Its DFT has a ripple minimum of **−0.00115**, the truncation lie. Separable truncation makes the support a **square**: visible only on HDR lights at high exposure. Toggles: k = 2 / 2.5 / 3 / 4; discretization sampled / integrated / Lindeberg (matters below σ ≈ 0.7). | COMPUTED |
| 5 Passes | Separable, linear-sampled: 13 (offset, weight) entries per side; offsets 0, 1.4941, 3.4863, 5.4785 … 23.4092; weights 0.04998, 0.09803, 0.09069, 0.07883 … 0.00136. **25 fetches per pass, 50 per pixel**, against 98 discrete separable taps and 2,401 for direct 2-D. Pass tiles `H · V`. Tapping `H` shows the intermediate: the step edge already blurred horizontally (for a point light, a horizontal streak). Intermediate format `rgba16Float`. Variant toggle: 2-D direct (σ ≤ 4 only) / separable discrete / linear-sampled / compute tile / box³ / IIR / MPS. | COMPUTED, LIVE |
| 6 Shader | `gauss_linear_fs` (gpu-pipeline §6.2, sketch 2): one full-screen-triangle fragment pass per axis, `sampler(filter::linear, address::clamp_to_edge)`, `float4` accumulator, `half4` output, weights and offsets from a buffer filled by `BlurCore`. Annotations by line: "pairs of taps become one bilinear fetch", "float accumulator: a half accumulator would cost up to 2.1 × 10⁻³ at this size (MEASURED, M1 Max)". Source SHA and `mathMode` are shown. | REFERENCE; MEASURED (M1 Max) |
| 7 Silicon | Fragment path: 799,236 fragments per pass in **28 × 28 render tiles of 32 × 32**. The probe's ±24-px footprint crosses into neighbouring tiles, which is the hardware reason a blur needs an offscreen pass (gpu-pipeline §1.2). Bytes: 4 × 6.39 MB = **25.6 MB** (MODELED), floor **0.50 ms** at the 51.2 GB/s figure (MODELED on an UNVERIFIED input). The app's own copy-bandwidth probe replaces that figure. Scaling the A17 Pro full-screen estimate (≈ 3.4 ms MODELED, gpu-pipeline §4.2) to this window (22% of the screen) gives ≈ 0.75 ms MODELED, shown as a ghost bar next to the MEASURED bar. Compression note: these textures have no `.shaderWrite`, so they stay losslessly compressed on the A17 Pro; the compute-tile variant (`gauss_tile_h/v`: 4 × 894 threadgroups of 256 threads, 8 SIMD-groups each, a 304-texel tile in 3,072 B of static threadgroup memory, 1.19 texture reads per pixel) does not (REFERENCE, Tech Talk 111431). The A/B button measures the difference on this phone. | COMPUTED, MODELED, MEASURED, REFERENCE |
| 8 Pixels | Probe 4 px into the white side of a black \| white edge. Linear-light blend: **0.7137** linear → encoded **220**. The same blur in sRGB-encoded space gives encoded **182**, whose light is only 0.468. The first white pixel reads **191.7** (linear blend) vs **133.9** (gamma blend). This matches Core Image's 191 vs 133 measured on the Mac (stack-semantics §3.4), a cross-check between this app's math and Apple's pixels. GPU readback vs CPU Double: `‹_› LSB`. | COMPUTED; LIVE; MEASURED |

The "what makes it unique" sentence that heads every layer page: *The only blur that is round and separable at once: it fades every detail smoothly and never inverts phase.*

### 5.2 Worked example: radial (zoom) blur, strength a = 0.20, centre at the window centre, N = 32 taps, impulse grid

A zoom blur is **linear but shift-variant**, so three layers show something different from the Gaussian. Math shows a *local* response and a log-polar identity, not one MTF. Kernel shows a **PSF field**, not one kernel. Silicon shows a **sampling-condition ring**.

| Layer | What the page shows | Labels |
|---|---|---|
| 1 Slider | Photoshop Radial Blur › Zoom, Amount 1–100 (mapping to strength UNVERIFIED). Core Image `CIZoomBlur` `inputAmount`: streaks **outward** over [D, s·D] with s = 1.5^(amount/20) and near log-uniform weights (macOS law). Our inward a = 0.20 covers the same log-polar length, ln(1/0.8) = **0.223**, as `CIZoomBlur` amount **11.0**. The Apple-twin comparison therefore uses amount 11.0, and the difference left over is direction and weighting, not size. Sketch "Zoom blur" exists but was not measured. GIMP Motion Blur › Zoom. | REFERENCE (labels); MEASURED macOS (CI law); COMPUTED (the 11.0 match); UNVERIFIED (Photoshop) |
| 2 API | `RadialParams { center (uv), strength 0.20, samples 32, mode zoom }` (gpu-pipeline §6.2 sketch 6). The compiled sketch samples **centred** scales 0.9 → 1.1, while CATALOG's definition is one-sided (1 → 0.8). Blur2ool exposes both as variants: `centred` (default; zero phase, so the image is not displaced) and `one-sided` (matches Photoshop and CIZoomBlur). The page says which one is running. | REFERENCE (the code) |
| 3 Math | g(x) = (1/a)∫₀ᵃ f(c + (1−s)(x−c)) ds. Not LSI, so there is **no global MTF** and the FREQ pill engraves `LOCAL · AT PROBE`. Local PSF at r = 400 px: a radial segment **80 px** long, σ along the ray **23.1 px**, local zero lines every **0.0125 c/px** across the ray. In log-polar coordinates it is an ordinary 1-D box of length 0.223. The test the page offers: a **centred Siemens star passes unchanged** (its spokes are rays) while a centred zone plate smears (its rings are not). | COMPUTED |
| 4 Kernel | A **PSF field**: the impulse grid (16-px pitch) becomes a spot diagram of rays whose length grows with distance from the centre. The KERNEL pill shows the 1-D profile at the probe. Weights 1/32, scales 1 − 0.2·(i/31 − 0.5) in the centred form. The kernel well engraves rays. | COMPUTED, LIVE |
| 5 Passes | Variant `gather`: 1 pass, 32 fetches per pixel. Variant `ghost-free`: N = ⌈a·r_max⌉ + 1 = **128** taps (r_max = 632 px at the window corners). Variant `doubling`: **7 passes × 2 fetches = 14 fetches** for 128 geometrically spaced samples, which is exactly LSI in log-polar coordinates. Pass tiles: one tile, or seven tiles labelled `×s^64 … ×s^1`. | COMPUTED |
| 6 Shader | `radial_blur` (sketch 6): `dispatchThreadgroups`, a per-pixel loop of N `sample()` calls along (x − c), aspect correction, `float4` accumulator. Annotation: "tap spacing at this pixel = a·r/(N−1)". | REFERENCE |
| 7 Silicon | 56 × 56 = 3,136 threadgroups of 16 × 16. 32 bilinear fetches per pixel; fetch-bound, and the cache hit rate falls toward the periphery as taps spread out. The **ghost-free radius** for N = 32 is **155 px** (tap spacing ≤ 1 px), drawn as a ring on the overlay copy. Outside it, discrete ghost copies appear, and at the corners the spacing reaches 4.08 px. Timing: M1 Max full screen at 32 samples took 1.08 ms (MEASURED there). The ×5 A17 Pro scaling and the 22% window fraction give ≈ 1.2 ms (MODELED), shown as the ghost bar. Measured on this phone: `‹_.__› ms`. | COMPUTED, MEASURED (Mac), MODELED |
| 8 Pixels | Probe at r = 400 px right of the centre, (847, 447). Its 32 taps lie on x = 807 … 887 along row 447, **2.58 px apart**, so the trace shows the gaps between taps, and an impulse that falls between taps is missed. Parity vs the CPU gather with exact bilinear: `‹_› LSB`; the M1 Max gave 7.3 × 10⁻⁴ max (MEASURED there; fast-math trig plus the 8-bit bilinear weights). | COMPUTED, LIVE, MEASURED |

Signature line: *Everything streaks toward one point and the streak grows with distance: a box blur along rays, which in log-polar space is just an ordinary 1-D box.*

### 5.3 Worked example: bilateral filter, σs = 3 px, σr = 0.10 (linear light), window r = 8, noisy step at three contrasts

A bilateral filter is **nonlinear**, so Math and Kernel change character again. The FREQ pill engraves `N/A · NONLINEAR`. The kernel is a **weight map that differs at every pixel**, read at the probe.

| Layer | What the page shows | Labels |
|---|---|---|
| 1 Slider | Photoshop Surface Blur (Radius, Threshold; INFERRED to be a thresholded bilateral; the threshold direction in Adobe's text reads backwards and is INFERRED from behaviour). After Effects Bilateral Blur. OpenCV `bilateralFilter(d, sigmaColor, sigmaSpace)`: sigmaColor 25.5 on 0–255 ≈ σr 0.10 **in encoded values**. Apple's SDK offers **no** bilateral slider: SwiftUI, Core Image and MPS have none (`CIEdgePreserveUpsampleFilter` is a joint bilateral upsampler, INFERRED). | REFERENCE, INFERRED |
| 2 API | Two parameters in **two different units**: σs in px, σr in intensity. σr depends on the blend space: 0.10 in linear light is not 0.10 in encoded values. The page shows σr in both (0.10 linear ≈ encoded difference that varies with brightness: it is a different threshold in shadows than in highlights). | COMPUTED |
| 3 Math | g_p = (1/W_p) Σ G_σs(‖p−q‖)·G_σr(\|f_p−f_q\|)·f_q. No MTF. In its place: the **amplitude-transfer map T(ν, A)** (signal lab, Response tab). At ν = 0.1 c/px the gain is **0.178 at A = 0.01** (the Gaussian alone gives 0.168), **0.214** at 0.03, **0.524** at 0.10, **0.930** at 0.30. Small wiggles are blurred, large ones pass. Range weights: **0.61** at Δ = σr, **0.135** at 2σr, **0.011** at 3σr. | COMPUTED (NL A2 probe `amp_transfer.py`) |
| 4 Kernel | The KERNEL pill reads `AT PROBE`. The page shows the 17 × 17 weight map at the probe, as a heat map with numeric contours. Probe 1 px into the bright side of the 0.2 step: pixels across the step get relative weight **exp(−0.2²/(2·0.1²)) = 0.135**, so the effective PSF is a Gaussian with its far half dimmed to 13.5%. On the 1.0 step the far half is effectively **zero** (e^(−50)). On the 0.05 step it is **0.88**, almost a plain Gaussian. | COMPUTED, LIVE |
| 5 Passes | `brute` (Tier 1): 1 pass, **289 taps**. `separable` (Tier 2): 2 passes, **34 taps**, RMS 0.005 from brute on a noisy Siemens star, and pass-order dependent. `grid` (Tier 2): splat · blur · slice; at s_s = 12 px and s_r = 0.1 the 894² window needs **56,250 cells**. Pass tiles `1` / `X · Y` / `SPLAT · BLUR³ · SLICE`. | COMPUTED (NL A3, A4 probes) |
| 6 Shader | Compute kernel, 16 × 16 threadgroup tile plus an 8-px apron: 32 × 32 texels × 8 B = **8 KB** of threadgroup memory (fits even the Simulator's 16 KB). Per tap: read from threadgroup memory, Δ, `exp`, two FMAs into (Σw·f, Σw). Parity builds compile with `mathMode = .safe` and precise transcendental functions, because `exp` appears per tap (sdk-feasibility §13). | REFERENCE, COMPUTED |
| 7 Silicon | 3,136 threadgroups. **4.0 device reads per pixel** (the rest come from threadgroup memory), 289 `exp` per pixel = **231 million exp per frame**: ALU-bound, not bandwidth-bound, and the roofline point lands on the ALU ceiling measured by the device probe. While a crown turns, the preview runs at half resolution and the status row says `PREVIEW ½`. | COMPUTED, MODELED, MEASURED |
| 8 Pixels | Noisy step (noise σ 0.03) at contrasts 0.05 / 0.2 / 1.0: the 10–90% edge width is **10 px** for the 0.05 step and **under 1 px** for the 0.2 and 1.0 steps. A noise-free Gaussian σ = 3 gives **7.7 px** for all three. The trace lists taps sorted by weight, each with its spatial weight × range weight. Salt-and-pepper impulses survive: a lone outlier has no similar neighbours. | COMPUTED (NL A2 `edges.py`, CATALOG E16), LIVE |

Signature line: *A Gaussian that refuses to average across anything that looks different from the centre pixel: smooth skin, sharp eyelashes.*

### 5.4 Worked example: hexagonal bokeh, R = 16 px (n = 16 taps per 1-D pass), night-city HDR lights

| Layer | What the page shows | Labels |
|---|---|---|
| 1 Slider | Photoshop Lens Blur › Iris (Shape: hexagon, Radius, Blade Curvature, Rotation; implementation INFERRED). After Effects Camera Lens Blur (Iris Shape, "Use Linear Working Space"). Unity URP Bokeh DoF (Blade Count 3–9; a fixed 42-tap ring kernel). Core Image has **no polygonal bokeh**: `CIBokehBlur` with default ring and softness is bit-identical to `CIDiscBlur` (MEASURED macOS). | REFERENCE, MEASURED, INFERRED |
| 2 API | R = 16 px, rotation 0°, directions 90°, −30°, −150°. **Blades segmented control: 4 · 6 · 8 enabled; 5 · 7 · 9 shown disabled** with the reason "Only centrally symmetric polygons (zonogons) can be built from line blurs" (the zonogon theorem, CATALOG SPA §2.3). Odd-bladed shapes live in the stochastic-bokeh variant (Tier 2). | COMPUTED |
| 3 Math | h = 1/Area on a regular hexagon: area **665 px²**, per-axis σ = 0.456R = **7.30 px**. A disc with the same σ has R = **14.6 px**. The spectrum is the sum of three rhombus spectra (sinc products with phases): six-fold slow-decay spokes and non-circular zero curves. The FREQ pill shows the radial average plus a "spoke" slice, labelled. | COMPUTED |
| 4 Kernel | Three rhombi P(90°, −30°), P(90°, −150°), P(−30°, −150°) tiling the hexagon. The GPU's own impulse response is read back and **the mean weight of each rhombus is measured**: it should be 1/3 each. The published two-pass code's normalization is UNVERIFIED (CATALOG SPA §2.3), so the device result settles it for this implementation: `‹0.33_› · ‹0.33_› · ‹0.33_›`. | COMPUTED, MEASURED |
| 5 Passes | **4 one-sided 1-D passes in 2 MRT render passes**: P1 writes V and V + D; P2 blurs V along −30° and (V + D) along −150° and averages. **64 fetches per pixel vs ≈ 665** for a 2-D gather (n² × 2.6). Pass tiles `P1 · MRT(2)` and `P2 · AVG`. Tapping P1 shows its two intermediates side by side: a vertical streak and a slanted parallelogram. | COMPUTED |
| 6 Shader | Fragment shader with **two `rgba16Float` colour attachments**. Each 1-D loop starts half a step out (`uv += dir * 0.5`), which is what makes the segments one-sided. Optional highlight gain. Annotation: "this shape only works because a hexagon has parallel opposite sides". | REFERENCE (Barre-Brisebois 2017 structure) |
| 7 Silicon | Bytes: P1 reads 1 image and writes 2; P2 reads 2 and writes 1: 6 × 6.39 MB = **38.4 MB** (MODELED), floor **0.75 ms** at 51.2 GB/s (UNVERIFIED input). Render targets only, no `.shaderWrite`, so compression stays on. Tile view: the 2 MRT targets cost 16 B per pixel of tile storage, well inside the tile budget. Measured: `‹_.__› ms`. | MODELED, REFERENCE, MEASURED |
| 8 Pixels | An isolated HDR light of **16.0** (linear) spreads over 665 px, so each pixel of the hexagon gets **0.0241** linear, encoded **43/255**: a visible coin. Blurred in sRGB-encoded space after the usual 8-bit clip to 1.0, each pixel gets encoded 0.0015, i.e. light 0.000116: **207 × dimmer**, effectively invisible. Even an unclipped white light keeps only **1/12.92 = 7.7%** of its energy when blurred in gamma space (stack-semantics §7 item 3). This is the page where "linear-light truth" stops being abstract. | COMPUTED |

Signature line: *A hexagon is three rhombi and a rhombus is two line blurs: four 1-D passes buy aperture-shaped highlights, but only for shapes with parallel opposite sides.*

### 5.5 What changes between the four examples (the pattern the user learns)

| | Gaussian | Zoom | Bilateral | Hexagon |
|---|---|---|---|---|
| Verdict (CATALOG §1) | TRUE BLUR | LSV BLUR | ADAPTIVE BLUR | TRUE BLUR (fixed R) |
| FREQ pill | DFT of taps | `LOCAL · AT PROBE` | `N/A · NONLINEAR` | radial average + spoke slice |
| Layer 4 object | one kernel | PSF field | weight map at probe | one kernel built from 3 rhombi |
| Bottleneck in layer 7 | bandwidth at small σ, fetches at large σ | fetches, cache misses at the rim | ALU (`exp`) | bandwidth (MRT writes) |
| The truth only the device can tell | per-pass ms; compression gain | ghost-free radius vs speed | ALU ceiling | rhombus normalization |

## 6. The pixel-trace experience

**Goal.** Follow one output pixel through every fetch of every pass, using the GPU's own intermediate values. These are read back from the real intermediate textures, not recomputed. At each step they are set against the CPU reference.

### 6.1 Choosing the pixel

- **Tap** the specimen to move the amber probe crosshair. It is a `SpatialTapGesture`, not a touch-owning control, so the page still scrolls (metro-adaptation §C.1).
- **Accessibility**: the specimen has an adjustable action that moves the probe ±1 px. Trace has arrow buttons too.
- **Jump menu** (in Trace's navigation bar). These are the engine-first shortcuts:
  - `Worst parity pixel`: the argmax of \|GPU − CPU\| on the probe crop, from the last Run.
  - `Predicted inversion ring`: the Siemens-star radius where the MTF goes negative. For a disc that is r = 0.261·n_c·R, with n_c in **cycles** (CATALOG E7).
  - `Edge`, `Impulse peak`, `Corner` (the worst sampling for zoom and spin blurs).
  - `Tile boundary`: a pixel whose footprint straddles a 32 × 32 render tile.

### 6.2 The trace screen (S3)

1. **Context card**: a magnified copy of the texel neighbourhood (never the specimen itself), IN and OUT in both linear and encoded values, `Completed:` (amber) and `Next:` (cyan) pass lines.
2. **Layer grid** (4 + 4): each tile jumps to that layer's facts *for this pixel*. Layer 1 shows which slider values in other tools give this pixel's value. Layer 7 shows which render tile or threadgroup, SIMD-group and lane computed it.
3. **Fetch table** for the current pass, one row per fetch: index, offset, the two (or four) texels blended, the bilinear fraction `t` **as requested** and **as the hardware quantizes it** (with the measured sub-texel bits; for example t 0.4941 → 0.4922 at 8 bits, MODELED from the MEASURED bit count), weight, fetched value, and the running sum in `float`. The last row shows the rounding to `half`, the CPU Double value and the Δ in LSB.
4. **Next pass** reads the probe's footprint from the **actual intermediate texture** (blit to a shared buffer, the only correct readback path in the Simulator, gpu-pipeline §2.7 item 7). It runs the next table on those values and shows the per-stage parity, so an error can be pinned to the pass that introduced it.

### 6.3 How the trace adapts per algorithm class

| Class (examples) | What a trace step is | Notes |
|---|---|---|
| Separable FIR (Gaussian, box, tent, binomial) | One fetch row per tap, 2 passes | Merged bilinear taps list both texels |
| Gathers (zoom, spin, disc, golden-angle bokeh, motion) | One row per sample along the ray, arc or spiral | Gaps between samples are drawn; samples that miss an impulse are flagged |
| Running sums and SAT (box sliding window, stack blur, sat-box) | The 2 entering and leaving texels plus the running state; for SAT the 4 corners | Shows the fp32 magnitude of the SAT corner and its spacing (ulp), which is why precision fails far from the origin (CATALOG E11) |
| Recursive (IIR, exponential) | The recursion state along the row: feedback taps, causal then anticausal | The footprint is infinite; contributions under 1% of the total are summarized in one row |
| Pyramids (dual Kawase, CoD 13-tap, mip chain) | A tree: 5 taps on each down level, 8 on each up level, drawn on the pyramid | The probe's texel at each level is highlighted; the phase within 2^L is shown, since that is the cause of shift variance |
| Iterative (Perona–Malik, heat) | One row per iteration for the 5-tap stencil, with a scrubber over iterations | The σ = √(2t) readout updates as t grows |
| Nonlinear weighted averages (bilateral, guided, Kuwahara) | Rows sorted by final weight: spatial × range (or the winning sector) | The weight map at the probe is the effective PSF |
| Rank (median) | The 9 or 25 window values, sorted, with the chosen one marked | The impulse "loses the vote" visibly |
| FFT-based (Tier 2: low-pass, FFT convolution, deconvolution) | **No pixel trace.** The page says why: every output pixel depends on every input pixel. It shows the probe's contribution as a spectrum product instead | Honest empty state, Metro §16 |
| Apple system blurs (Tier S) | **No trace.** The page says: "Runs in the render server; we can measure its output, not follow its fetches" | INFERRED pipeline shown dashed |

### 6.4 Motion and stepping

`Next pass` is the primary action. Holding `Trace a pixel` on the Bench starts an **auto-walk**: the button turns amber (Metro's running colour) and steps one pass every 600 ms, with the specimen showing each intermediate. Reduce Motion disables the auto-walk; manual stepping always works (Los Alamos precedent, metro-adaptation §F.4 item 8).

---

## 7. "What makes each blur unique": the fingerprint card

### 7.1 Card anatomy (fixed slots, fixed heights)

```
┌─ WHAT MAKES IT UNIQUE ───────────────────────────── <display name> ─┐
│ <signature line, serif italic, instrument cyan>                     │
│ PSF       <shape words> · <numbers>                    [badges]     │
│ |H|       <frequency words> · <numbers>                [badges]     │
│ EDGES     <edge behaviour> · <numbers>                 [badges]     │
│ COST      <class> · <fetches/px> · <measured slope>    [badges]     │
│ ARTIFACT  <the tell, and the test image that shows it> [badges]     │
│ USED IN   <real products and APIs>                     [REF]        │
│ ON THIS PHONE  σ ‹_› · kurt ‹_›/‹_› · shift ‹_› px · ‹_› ms/MP      │
│ LOOKS MOST LIKE  <nearest catalog entry> (Δ in the fingerprint)     │
│ [ PSF 40×40 ] [ |H| sparkline ] [ ESF sparkline ]     Field guide ›  │
└─────────────────────────────────────────────────────────────────────┘
```

- The first six rows follow the brief's list (PSF shape, frequency response, edge behaviour, cost class, artifacts, where used). Their text comes from CATALOG §2 and the researcher files.
- **`ON THIS PHONE`** is the engine-first row. When a blur is opened, the engine queues four background dispatches: impulse grid, step edge with 4 phases, 1-px stripes, and the Siemens star. From the GPU output it **measures** σ_eff, kurtosis on the axis and at 45°, edge-centre shift over 4 phases (the shift-variance detector of live-calibration §3.3), the minimum of the measured MTF, and ms per megapixel. The analytic values sit beside them as COMPUTED. A mismatch beyond tolerance is flagged with a symbol **and** text ("GPU differs from math by 3.1% · Error tab ›"), never amber alone (Metro §3).
- **`LOOKS MOST LIKE`** compares the measured fingerprint vector (σ-normalized kurtosis pair, MTF minimum, shift variance, support/σ) with every catalog entry's computed vector and names the nearest one. For SwiftUI `.blur` above 5 px this is how the app answers "is it box³ or a truncated Gaussian?" without taking sides.
- The three mini glyphs at the bottom are drawn **from the GPU output**: the PSF at a log exposure (so tails and square supports show), and the |H| and ESF sparklines. They are Canvas drawings, no glass.

### 7.2 Example: three cards side by side (σ-matched at 5.34 px)

| Row | Gaussian | Kawase {0,1,2,2,3} | Disc R = 10.7 px |
|---|---|---|---|
| Signature | *The only blur that is round and separable at once.* | *Four diagonal taps at growing distances: a hollow heart and a 5% lie.* | *A flat coin with a hard rim; stripes at the wrong spacing come back inverted.* |
| PSF | round, no rim [COMP] | centre 0.0645 < ±2 px max 0.0674: hollow [COMP] | flat top, hard rim [COMP] |
| \|H\| | no zeros, never negative [COMP] | minimum **−0.047** at 0.14 c/px [COMP] | first zero 0.6098/R = 0.057 c/px; minimum **−0.132** [COMP] |
| EDGES | erf S-curve | erf-like with faint steps | half-disc-area S-curve, steeper middle |
| COST | O(r), 50 fetch/px at σ 8 | **20 fetches** (5 passes × 4) at σ 5.34, bandwidth-bound | O(R) row-SAT or O(R²) gather |
| ARTIFACT | square support on HDR lights | squarish glow, reversed faint ring on the zone plate | round inversion ring on the Siemens star at r = 0.261·n_c·R |
| ON THIS PHONE | ‹measured› | ‹measured› | ‹measured› |

(Kawase numbers: CATALOG §5.2 CHECKED. Disc first zero: 0.6098/10.7 = 0.057 c/px, COMPUTED. The disc radius that matches σ = 5.34 is R = 2σ = 10.7, COMPUTED.)

### 7.3 Where the card appears

The card appears on the Bench below the fold, as the header of every Descend layer page (the signature line only), in Catalog rows (signature only), and in the Field guide in full with citations.

---

## 8. Comparison modes

**The lab rule: change one variable at a time.** Compare offers five **axes**. B is always A with exactly one field of the Run changed. The axis picker (`Picker(.tabs)`) decides which field B may differ in, and the B menu lists only legal choices.

| Axis | B may differ in | Matching rule | Typical lesson (CATALOG §7) |
|---|---|---|---|
| **Operator** | the catalog entry | **σ-match by default** (equal per-axis second moment), or match FWHM, 10–90 edge width, or **equal measured ms** (cost-match: "what does each blur buy for 0.5 ms?") | P1 box vs Gaussian, P2 box/tent/Gaussian, P6 Kawase vs Gaussian, P11 disc/hexagon/Gaussian, P20 motion box vs directional Gaussian, P21 zoom vs spin |
| **Implementation** | the variant id, the CPU reference, or MPS | same operator and parameters | P4 2-D vs separable, P5 discrete vs linear-sampled, P7 mip vs CoD vs dual Kawase, P12 disc exact vs complex-separable vs stochastic, `GPU vs CPU Double` (parity) |
| **Precision** | accumulator (`float`/`half`), intermediate (`rgba16Float`/`rgba8Unorm`), math mode (fast/safe), SAT (fp32 / mean-centred / uint32) | same kernel | fp16 accumulation error (up to 6 LSB for running sums, MEASURED M1 Max); SAT corner error 7.5 × 10⁻² at 4096² vs 3.5 × 10⁻⁵ mean-centred |
| **Space** | blend space (linear / sRGB-encoded), alpha (premultiplied / straight) | same kernel | P18 linear vs sRGB (0.735 vs 0.500 stripes; 191 vs 133 at an edge), P19 premultiplied vs straight (dark fringe) |
| **Apple** | our implementation vs the Apple system twin at the fitted parameters | parameters from the latest Calibrate Run | P26 SwiftUI `.blur` vs Gaussian vs box³; `CIMotionBlur` vs our box motion blur (Core Image's is Gaussian-weighted, MEASURED); `CIZoomBlur` amount 11.0 vs our zoom a = 0.2 |

**Views** (segmented control in the readout band): `Wipe` · `|A−B| ×64` · `Flicker 2 Hz`. All three draw inside the specimen window, which is the honest place for pixel comparisons. There is no separate side-by-side screen, because two half-size images hide exactly the differences that matter.

**Two comparisons that are not wipes:**

1. **Cost-vs-σ overlay** (signal lab › Cost): every algorithm of the family, MEASURED dots, MODELED dashed lines, log-log slopes. This is the comparison of *algorithms*, not images.
2. **Lessons**: CATALOG §7's thirty pairs as one-tap presets in the B menu (`Lessons ▸ P11 Bokeh is the aperture`). Each preset sets A, B, the axis, the specimen and the view, and writes its "what to look for" sentence into the status row.

## 9. Controls per blur family

### 9.1 The control grammar (applies to every family)

| Parameter kind | Metro control | Placement | Rules |
|---|---|---|---|
| **Primary continuous** (σ, R, L, a, Θ, D₀ …) | `InstrumentCrown` **FINE** (cyan, 8° detents) + **SEMANTIC** (amber, 20° detents, named stops), each between real 44 × 44 glass ± buttons | crown row of the first viewport | ≤ 1 step per update, ≤ 20 events/s, 7 pt centre exclusion, first touch does not change the value (metro-adaptation §C.4). Accessible as an adjustable action with the same step. |
| Same parameter, native fallback | `DecimalParameterStepper` (Int tenths or hundredths) | below the fold (and replacing the crowns at accessibility text sizes) | Binding written before `onAcceptedChange`; displayed precision = spoken precision |
| **Directional angle** | `InstrumentCrown` **ANGLE** (8° detent = 1°; semantic snaps at 0/45/90/135°) | replaces SEMANTIC in the crown row | Angles are measured clockwise in screen space (y-down); the Layer 2 page converts to Core Image's y-up convention |
| **Integer** (radius in taps, passes, levels, order, samples, iterations) | `InstrumentParameterStepper` | crown-row slot when the primary is an integer; otherwise below the fold | Shown as whole numbers with their noun (`3 passes`, `25 taps`), never decimals (Metro contract A.6) |
| **Named choice** (variant, blades, discretization, method) | native `Picker(.segmented)`, or `InstrumentEventTiles` when the choice is a sequence | below the fold, next to the parameter it changes | Disabled options stay visible with the reason as their accessibility hint (example: odd blades) |
| **Position** (probe, zoom/spin centre, tilt-shift band) | tap on the specimen; a 44-pt drag handle for bands | specimen | The centre is set by a `Centre` toggle in the status row: while it is on, a tap moves the centre instead of the probe |

**No `Slider`s** for blur parameters. A slider emits a continuous stream of values with no discrete identity, which makes "which Run produced this frame" ambiguous and floods the timer with half-finished measurements. Detented crowns produce one accepted value per detent, and each value gets its own Run.

**Heavy kernels preview at half resolution** while a crown is turning (O(r²) gathers, bilateral, NLM, bokeh, zoom with N ≥ 128), and run at full resolution 300 ms after the last accepted change. The status row says `PREVIEW ½` and timing is recorded only for the full-resolution Run.

### 9.2 Per family

Units: px = specimen texels = device pixels (1 px = 0.33 pt). Ranges are limited by the 894-px window and by Tier 1 GPU budgets.

| Family | Parameter | Control | Unit | Range | FINE step / SEMANTIC stops | Default |
|---|---|---|---|---|---|---|
| F1 Box, tent, running sums | radius r (width 2r + 1 shown) | Stepper | px | 1–64 | 1 | 4 |
| | algorithm | segmented: merged taps · sliding window · SAT | — | — | — | merged |
| | iterated box: σ target | crowns | px | 1.0–64.0 | 0.1 / octave stops | 8.0 |
| | iterated box: passes n | Stepper | count | 1–6 | 1 | 3 |
| | width rule | segmented: equal · Kovesi split · SVG three-box · extended | — | — | — | Kovesi |
| F2 Gaussian & approximations | σ | crowns | px | 0.3–64.0 | 0.1 / 0.5 · 1 · 2 · 4 · 8 · 16 · 32 · 64 | 8.0 |
| | truncation k | segmented 2 · 2.5 · 3 · 4 | σ | — | — | 3 |
| | discretization | segmented sampled · integrated · Lindeberg | — | — | — | sampled |
| | variant | picker: 2-D (σ ≤ 4) · separable · linear-sampled · compute tile · box³ · IIR · MPS | — | — | — | linear-sampled |
| | binomial order n | Stepper (even) | taps − 1 | 2–32 | 2 | 4 |
| | IIR method | segmented Deriche K3 · K4 · Young–van Vliet | — | — | — | Deriche K4 |
| F3 Pyramids & Kawase | Kawase sequence | event tiles, each tile a Stepper 0–15; presets {0,1,2,2,3} · {0,1,2,3} · {2,3,3,3} · 17-pass | texel distance | 1–17 passes | 1 | {0,1,2,2,3} |
| | dual Kawase levels L | Stepper | levels | 1–6 | 1 | 3 |
| | dual Kawase offset o | crown FINE only | half-texels | 0.5–4.0 | 0.5 | 2.0 |
| | pyramid kernel | segmented mip · CoD 13-tap · Unity 13-tap | — | — | — | CoD |
| F4 Kernel shapes & frequency | exponential b | crowns | px | 0.5–32.0 | 0.1 / octaves | 4.0 |
| | Lorentzian γ | crowns | px | 0.5–16.0 | 0.1 / octaves | 2.0 |
| | low-pass cut-off D₀ | crowns | c/px | 0.005–0.500 | 0.005 / 0.01 · 0.02 · 0.05 · 0.1 · 0.2 · 0.5 | 0.05 |
| | Butterworth order n | Stepper | — | 1–20 | 1 | 2 |
| | FFT padding | segmented none (wrap) · zero · mirror | — | — | — | zero |
| F5 Directional & motion | motion length L | crowns FINE + ANGLE | px, ° | 1.0–128.0; 0–179° | 0.5 px; 1° (snaps 0/45/90/135) | 32.0 px, 0° |
| | shutter profile | segmented box · trapezoid · coded | — | — | — | box |
| | zoom strength a | crowns | fraction | 0.00–0.50 | 0.01 / 0.05 · 0.1 · 0.2 · 0.3 · 0.5 | 0.20 |
| | zoom/spin samples N | Stepper | samples | 8–256 | 8 | 32 |
| | zoom/spin variant | segmented gather · ghost-free · doubling; form centred · one-sided | — | — | — | gather, centred |
| | spin angle Θ | crowns | ° | 0.0–90.0 | 0.5° / multiples of 360°/n_c (10°, 20° … for the 36-cycle star) | 10.0° |
| | anisotropic Gaussian σu, σv, θ | crowns (σu), Stepper (σv in tenths), ANGLE | px, ° | 0.3–64; 0–179° | 0.1; 1° | 8, 1, 30° |
| F6 Lens & bokeh | disc radius R | crowns | px | 0.5–48.0 | 0.1 / 2 · 4 · 8 · 16 · 32 | 10.0 |
| | disc algorithm | segmented exact row-SAT · gather · complex-separable (1 or 2 components) · stochastic | — | — | — | row-SAT |
| | stochastic samples S | Stepper | samples | 16–400 | 16 | 64 |
| | polygon R | crowns | px | 2.0–48.0 | 0.5 / 4 · 8 · 16 · 32 | 16.0 |
| | blades | segmented 4 · 6 · 8 (5 · 7 · 9 disabled with reason) | — | — | — | 6 |
| | rotation | ANGLE crown | ° | 0–59 (hexagon period 60°) | 1° | 0° |
| | Airy: λ, f-number | segmented 450 · 550 · 650 nm; Stepper of named stops f/1.4 … f/16 | nm, f/ | — | one stop | 550 nm, f/8 |
| | highlight boost (HDR lights) | Stepper | × | 1–64 | ×2 | ×16 |
| F7 Spatially varying & stochastic | mask | picker ramp · radial · tilt band · user photo luma | — | — | — | ramp |
| | σ_max | crowns | px | 1.0–32.0 | 0.1 / octaves | 12.0 |
| | method | segmented per-pixel σ · mip mixture · stacked layers | — | — | — | per-pixel |
| | frosted spread a | Stepper | px | 1–16 | 1 | 4 |
| | realizations N | Stepper (powers of 2) | count | 1–256 | ×2 | 1 |
| F8 Edge-preserving & nonlinear | bilateral σs | crown FINE | px | 0.5–4.0 | 0.1 | 3.0 |
| | bilateral σr | crown SEMANTIC | intensity (blend space) | 0.01–1.00, then ∞ | 0.02 · 0.05 · 0.1 · 0.2 · 0.5 · 1.0 · ∞ (= Gaussian) | 0.10 |
| | bilateral method | segmented brute · separable · grid | — | — | — | brute |
| | median window | segmented 3 × 3 · 5 × 5 | px | — | — | 3 × 3 |
| | guided r, ε, detail boost k | Stepper; Stepper of log stops 10⁻⁴ … 10⁻¹; Stepper | px; —; × | 1–16; —; 1–8 | 1; one decade/3; 1 | 4; 10⁻²; 1 |
| | Kuwahara r | Stepper | px | 2–12 | 1 | 4 |
| | surface blur radius, threshold | Stepper; Stepper | px; encoded levels | 1–16; 2–255 | 1; 1 | 5; 15 |
| F9 Diffusion | heat iterations n (λ = 0.25, t = 0.25·n, σ = √(2t) shown) | Stepper | iterations | 1–400 | 1 (hold to repeat) | 32 → σ 4.0 |
| | Perona–Malik K, conductance | crowns; segmented exp · rational | intensity | 0.01–0.50 | 0.01 / 0.02 · 0.05 · 0.1 · 0.2 | 0.10 |
| F10 UI materials | SwiftUI `.blur` radius | crowns | **pt** (px shown beside) | 0.00–32.00 | 0.25 pt / 0.5 · 1 · 1.8 · 2 · 4 · 8 · 16 | 2.00 |
| | `opaque`, `colorMode` | toggle; segmented nonLinear · linear · extendedLinear | — | — | — | false, nonLinear |
| | material | picker ultraThin … ultraThick, chrome; legacy styles | — | — | — | regular |
| F11 Uses of blur | drop shadow: tool + typed value | picker CSS box-shadow · CSS drop-shadow · CALayer · SwiftUI · Figma; crowns for the value | tool units | 0–64 | 1 / — | CSS, 10 |
| | bloom threshold, levels | crowns; Stepper | linear; levels | 0.5–8.0; 1–6 | 0.1; 1 | 1.0; 5 |
| | god rays N, decay, density | Stepper; crowns; crowns | —; —; — | 16–128; 0.80–1.00; 0.1–1.0 | 8; 0.01; 0.05 | 64; 0.96; 0.5 |
| C Contrast | USM amount k, DoG ratio, morphology r, pixelate cell, Wiener K | Stepper or crowns, as for the blur each pairs with | — | — | — | per CATALOG §7 pair |

The SEMANTIC stop at **1.8 pt** for SwiftUI `.blur` is deliberate. It marks the regime switch predicted for scale 3 (INFERRED from the 5-px switch measured on the Mac). Calibrate moves this stop to the device's measured switch once that exists.

---

## 10. Honesty labels in use

### 10.1 The badge

The `HonestyBadge` capsule (metro-adaptation §C.12): caption2 mono, tracking 1.2, white 0.06 fill, 0.6-pt white 0.12 border (0.25 under Increased Contrast). **The word comes first.** Glyph and ink repeat it as redundant cues, so meaning never rests on colour.

| Label | Glyph | Ink | Means in this app | Typical places |
|---|---|---|---|---|
| **LIVE** | filled 5-pt dot | action cyan | Computed now from the current image and parameters, on the GPU or CPU, with no fitting or timing | specimen caption `LIVE · METAL`; Trace IN/OUT; weight map at the probe |
| **MEASURED** | `stopwatch` | instrument amber | Timed or fitted on a device. The badge text carries **where**: `MEASURED` alone means this iPhone; anything else says so (`MEASURED · M1 Max macOS 27.2`, `MEASURED · iOS 27.0`, an older build) | GPU ms, parity, fitted σ, kurtosis, shift variance, device probes, Calibrate results |
| **COMPUTED** | `equal` | display ink | An exact consequence of the math, from `BlurCore` | σ_eff of the discrete kernel, fetch counts, MTF of the taps, dispatch geometry, thread/tile indices |
| **MODELED** | `≈` | spectrum violet | An estimate from a model with stated assumptions | bytes moved, bandwidth floors, ghost bars on the pass timeline, dashed cost lines, quantized bilinear `t` |
| **REFERENCE** | `book.closed` | secondary ink | Documented by a spec, vendor doc, paper or source code, with the citation one tap away | Feature Set Tables limits, CSS σ = value, Skia's 0.57735, Tech Talk 111431, the shown shader source |
| **INFERRED** | `questionmark` + **dashed border** | spectrum depth magenta | A claim about proprietary internals that we cannot see | render-server path of `.blur`, QuartzCore kernel names, material recipes, Liquid Glass, Photoshop Surface Blur's algorithm |

**UNVERIFIED** is not a seventh badge. It is a text tag that can accompany REFERENCE, MODELED or INFERRED when nobody on the team could confirm a value. It appears as the word `UNVERIFIED` after the value (for example the 51.2 GB/s bandwidth figure and Photoshop's radius mapping). Values tagged UNVERIFIED never feed a MEASURED number without the tag following them.

### 10.2 Rules

1. **Every number has exactly one badge.** A row that shows both a computed and a measured value shows two numbers with two badges, side by side (fingerprint `COST` row).
2. **Badges never animate**, and they are part of the spoken value: "GPU time, 0.42 milliseconds, measured on this iPhone, median of 15 runs".
3. **Simulator**: every MEASURED timing is drawn struck through, with the text `SIMULATOR · NO GPU TIMING`. Correctness numbers (parity, fitted σ) remain valid there, because they matched the Mac exactly (gpu-pipeline §2.7 item 5), and keep their badge with `· SIMULATOR`.
4. **Thermal honesty**: if `thermalState` was `.serious` or worse during a Run, the GPU column shows `THROTTLED` under the value, and the Run is excluded from cost curves by default.
5. **Engraved provenance on the instrument itself** (Los Alamos precedent, metro-adaptation §F.4 item 3): `LIVE · METAL`, `LIVE · CORE IMAGE`, `LIVE · SWIFTUI (ImageRenderer)`, `MODELED · MATERIAL RECONSTRUCTION`, `INFERRED · SYSTEM GLASS`.
6. **The chrome confesses too.** The field guide entry "The glass on this instrument" states that the kernel-well lens and the floating buttons are Apple's Liquid Glass. Blur2ool does not measure them, and every number about them would be INFERRED (metro-adaptation §C.2).

### 10.3 Where each label dominates, by layer

| Layer | Dominant labels |
|---|---|
| 1 Slider | REFERENCE, MEASURED (Calibrate), INFERRED (Figma), UNVERIFIED (Photoshop, After Effects, Affinity) |
| 2 API | REFERENCE, MEASURED |
| 3 Math | COMPUTED |
| 4 Kernel | COMPUTED; LIVE for data-dependent kernels |
| 5 Passes | COMPUTED, LIVE (intermediates) |
| 6 Shader | REFERENCE |
| 7 Silicon | MEASURED, MODELED, COMPUTED; INFERRED for Apple's system path |
| 8 Pixels | LIVE, MEASURED (parity), COMPUTED (expected values) |

## 11. The test-image set

Every specimen is **procedural**: generated in code by `BlurCore` as exact values, then uploaded as an 894 × 894 `rgba16Float` texture in **linear light, premultiplied**. There are no copyrighted images, and every specimen has a known analytic answer, so CPU parity and fitted σ have something to compare against. The specimen menu (▣ in the selector row) lists them, and each catalog entry declares its "best test image" (CATALOG §2 column), which becomes the default when that blur is opened.

| Specimen | Definition (exact) | What it measures | Best for |
|---|---|---|---|
| **Impulse** | one texel of 1.0 (or 16.0 HDR) at the centre on 0 | the PSF itself; σ_eff, kurtosis, support | fingerprint "on this phone" row |
| **Impulse grid** | 1.0 texels on a 16-px pitch | the PSF *field* of LSV blurs (spot diagram) | zoom, spin, path, cat's-eye, motion |
| **Step edge** | 0 \| 1 vertical edge at x = 408; variants at 4 phases | ESF/LSF, shift variance, edge policy, linear vs gamma midpoint | Gaussian, SwiftUI calibration, pyramids |
| **Noisy steps** | steps of 0.05 / 0.2 / 1.0 plus Gaussian noise σ = 0.03 (seeded) | edge-preserving behaviour per contrast | bilateral, guided, Perona–Malik, TV |
| **Siemens star** | 36 **cycles** (CATALOG E7 fix; the UI says "36 cyc") | contrast inversion rings, isotropy, spin nulls at 10° | box vs tent vs Gaussian, disc, spin |
| **Zone plate** | cos(π k r²) reaching 0.5 c/px at the window edge | the MTF laid out in space; aliasing and moiré | low-pass, pyramids, hexagon spokes |
| **1-px checkerboard** | alternating 0/1 | Nyquist response (binomial erases it exactly; Gaussian σ 1 leaves 0.72%) | binomial vs Gaussian, Kawase |
| **1-px stripes** | alternating black/white columns | **blend space**: blurred mean 0.500 encoded (gamma) or 0.735 (linear); aliasing in resampled blurs reads 0.509–0.524 | every Apple twin; the global LIN/sRGB toggle |
| **Night city (HDR)** | 200 Poisson-disc lights, values 1–16 linear, three colours, on 0.01 | bokeh shape, tails, square supports, energy conservation | disc, hexagon, cat's-eye, bloom, Lorentzian, exponential |
| **Text** | procedurally laid-out glyph strokes rendered with Core Text into the texture (system font, no font files shipped) | legibility, doubled strokes in negative lobes | deconvolution, motion, median |
| **Salt-and-pepper text** | text + 10% random 0/1 texels (seeded) | rank vs average vs adaptive | median vs bilateral vs Gaussian |
| **Smooth ramp** | 0 → 1 over the window, with optional noise 0.01 | terracing (bilateral, surface blur), staircasing (TV, Perona–Malik) | F8, F9 |
| **Noisy discs** | discs of radius 8 / 16 / 32 px, height 1, noise | TV contrast loss 2λ/R | `tv-denoise` (Tier 3, CPU) |
| **Rings with gaps** | concentric sinusoidal rings with gaps, noise | flow-following diffusion | coherence-enhancing diffusion (Tier 3) |
| **Material backdrop** | saturated colour stripes + text + a white/black split | saturation boost, luminance compression, edge bleed | materials, CSS backdrop model, Liquid Glass exhibit (drawn in SwiftUI, not Metal, so system glass can sample it) |
| **Transparent shape** | a red square on α = 0 | premultiplied vs straight alpha fringes | Compare › Space |
| **Occluder pattern** | a bright disc behind black bars | light shafts | god rays |
| **Your photo** | `PhotosPicker` (out of process, no permission prompt), downsampled with ImageIO to ≤ 2048 px, centre-cropped to 894², decoded **to linear** | real content | any; the caption says `YOUR PHOTO · sRGB 8-bit → linear` |

A user photo is never sent anywhere and never saved by the app. Only the Run record (the parameters and numbers, not the pixels) goes into the log.

---

## 12. Accessibility alternatives

| Need | Alternative in Blur2ool | Source of the rule |
|---|---|---|
| VoiceOver | Each telemetry metric is one element: label + value + unit + provenance ("GPU time, 0.42 milliseconds, measured on this iPhone, median of 15"). Pills speak a summary ("Kernel: Gaussian profile, 49 taps, normalized"). Decorative paths, rulers, the lens and the environment grid are hidden | Metro §17; contract A.20 |
| Images as data | Every chart has an `AXChartDescriptor` and a `DisclosureGroup` data table. The specimen has an accessibility value describing the probe ("Probe at 412, 488: input 1.0, output 0.714"). Trace is natively a table | metro-adaptation §C.8, §F.4 item 2 |
| Motor | Crowns have ± glass buttons and adjustable actions with the same step. Every Stepper is native, with hold-to-repeat. The compare divider is adjustable in 10% steps. The probe moves ±1 px by adjustable action. No action requires a gesture only | contract A.18 |
| Dynamic Type (AX1–AX5) | Crowns stack vertically, then give way to the `DecimalParameterStepper`. The readout band moves to a native text block under the housing. Telemetry stacks into 3 rows. Pills move below the housing as a pair (197 × 140) if their titles cannot fit. The floating group becomes icon-only with full spoken labels | metro-adaptation §D.6 |
| Reduce Motion | No pill easing (traces snap), no auto-walk in Trace, no Flicker view, no lens bounce. Manual stepping works | contract A.20; Los Alamos precedent |
| Reduce Transparency | The lens goes to opacity 1.0 (not removed). Panels become opaque. The floating group keeps native glass, which the system handles | Metro §6, §17; QuantumToy lens drift (metro-adaptation §F.3) |
| Increased Contrast | Panel borders 0.20, badge borders 0.25, pill outlines 0.70 | Metro §6 |
| Colour vision | No meaning carried by colour alone: badges carry words; A/B are solid vs dashed; difference maps use a luminance ramp with numeric contours; negative MTF lobes are shaded **and** drawn below an axis line at 0 | Metro §3, §17 |
| Photosensitivity | Flicker is capped at 2 Hz and is off by default. Sweeps never flash full-field contrast changes faster than 3 per second | WCAG 2.3.1 (three flashes) |
| Haptics off | Detents still produce visual tick marks on the crown and a value change. Haptics are optional in Settings | Metro §15 |

---

## 13. Deliberately NOT included

| Left out | Why |
|---|---|
| A tab bar | Floating glass tab bars hid live controls in two adopters' first viewports (metro-adaptation §F.3, §F.4). Bench is the only root. |
| `Slider` for blur parameters | Continuous streams make "which Run produced this frame" ambiguous; detented crowns give one Run per value (§9.1). |
| Simulator timings shown as numbers | They are meaningless (gpu-pipeline §2.7). Struck through, always. |
| The Metal 4 command model as the engine | It does not exist in the Simulator SDK and adds residency and barrier bookkeeping the app does not need (sdk-feasibility §7). Only an optional, device-only Metal 4 counter-heap timing path. |
| Private API (`CAFilter`, `CABackdropLayer`, `variableBlur`) | Not allowed, and not needed: the app *measures* Apple's blurs through public paths and labels internals INFERRED. |
| Measured σ for Liquid Glass or materials presented as fact | Glass is absent from `ImageRenderer`; materials come out as ImageRenderer's own approximation (sdk-feasibility §4). The exhibit is MODELED next to the INFERRED native glass. |
| Glass, materials or `.blur` over the specimen or plots | Specimen rule: a blur instrument must not contaminate the pixels it demonstrates (metro-adaptation §C.1). |
| Tilt-driven lens optics in v1 | At D = 88 the warp is 2.2 pt and the split 0.27 pt, near invisible, and it costs a CoreMotion lifecycle (metro-adaptation §G.1 item 2). The lens and its rim stay; the optics shader is off. |
| A draggable glass loupe | It would add the system's own refraction to the pixels under inspection. Trace magnifies a *copy* of the texels instead. |
| Live camera input | It would need a permission prompt and frame pacing; procedural specimens and `PhotosPicker` cover the teaching. |
| Exporting blurred photos | This is a lab instrument, not a photo editor. Run logs (JSON) are the export. |
| Pixel traces for FFT-based and system blurs | There is no honest per-pixel footprint (CATALOG §6.1 rule 2). These pages say so and show a spectrum or an INFERRED diagram. |
| Landscape | The layout and the Metro tilt mapping are portrait (metro-adaptation §E.6). |
| Accounts, network, analytics, third-party packages | BRIEF: no runtime dependencies, no accounts, no network. |
| Tier 3 blurs on the GPU | `mean-shift`, `tv-denoise`, `coherence-enhancing-diffusion`, Windows and Android materials run as CPU plots on small crops, labelled `MODEL · CPU PLOT`. |
| An "auto" mode that picks the fastest algorithm | It would hide exactly the trade-off the app exists to show. The Cost tab shows the trade-off; the user picks. |

---

## 14. Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| 1 | **No device numbers exist yet.** Every MEASURED value in the research is from the M1 Max or the Simulator. The phone may differ (bilinear bits, mip filter, counter points, SwiftUI's switch point). | The concept's core promise is unproven. | First-launch device probe and Calibrate (§1) fill the gaps. The Run log export lets the research docs be corrected. Until then, badges say `MEASURED · M1 Max macOS 27.2`. |
| 2 | **Per-pass timing perturbs what it measures.** One encoder per pass (needed for stage-boundary counters) adds pass switches. Metal 4 `.precise` timestamps "may cause splitting of command encoders" (SDK header). | Per-pass bars may overstate the cost of multi-pass algorithms. | Always show the **whole-command-buffer** median too. Offer a "fused" timing mode (all passes in one encoder, total only) and show the difference as `MEASUREMENT OVERHEAD ‹_.__› ms`. |
| 3 | **Thermal throttling and clock ramps** make ms noisy on a phone. | Cost curves and A/B deltas wobble. | 3 warm-ups, median of 15, IQR shown, thermal state stored per Run; `.serious` Runs excluded from curves; A/B runs interleaved (ABAB…), not sequential. |
| 4 | **The on-screen SwiftUI blur may not equal the `ImageRenderer` blur.** The two `ImageRenderer` paths already differ by 9% in σ; whether `drawHierarchy` captures render-server filters is UNVERIFIED (sdk-feasibility §17 item 1). | The "Apple twin" might describe an offscreen renderer the screen never uses. | The path is always named on the badge (`ImageRenderer`). The on-screen capture is labelled experimental and INFERRED until it is validated against a known pattern. |
| 5 | **The research disagrees with itself in two places.** SwiftUI's large-radius kernel: "truncated Gaussian at ±2.3r" (sdk-feasibility §4, stack-semantics §3.1) vs "box³-like" (live-calibration §5.1). `CALayer.shadowRadius`: σ = r/2 (stack-semantics §3.3) vs σ ≈ 0.88–0.94·r, equal to CG blur 2r (live-calibration §4.16 and catalog-nonlinear D7). | Wrong REFERENCE-looking claims on screen. | The app never states either as fact. Model competition (§3.7) fits both on the device. For shadows, two of three research measurements agree on ≈ 0.9·r. The research files should be reconciled before the shadow lesson (P27) ships. **This needs a decision from the research lead.** |
| 6 | **"The source shown is the code that runs" needs proof.** The app ships a precompiled `default.metallib` (cold runtime compiles took 6–19 s in the Simulator, sdk-feasibility §14), but shows `.metal` text. | The claim could silently drift. | The build stamps each source file's SHA-256 into the bundle. On first launch, the device compiles the shown text once in the background with `makeLibrary(source:)` and compares the function list. The Mac parity CLI loads the same files. `SwiftUI.h`-dependent shaders (the lens) are excluded from this path (metro-adaptation §E.4 item 3). |
| 7 | **Scope.** 55 entries, 27 Tier 1 kernels, each with 8 layers, traces, fingerprints and parity. | The build stalls before the engine is good. | Build in order: engine + Run + Gaussian family + Calibrate (SwiftUI) → box/tent/iterated/Kawase/pyramid → zoom/spin/motion → disc/hexagon → bilateral/median/guided → the rest. Tier 2 and 3 pages are data-driven from `BlurCore` metadata, not hand-built. |
| 8 | **The 51.2 GB/s bandwidth figure is a pre-launch leak** that got the RAM size wrong (gpu-pipeline §2.5). | MODELED floors look authoritative. | It is tagged UNVERIFIED everywhere it appears and replaced by the device's own copy-bandwidth measurement as soon as the probe runs. |
| 9 | **Simulator lies in both directions**: it runs Apple7-only features despite reporting Apple2, and does not enforce its 16 KB limit (gpu-pipeline §2.7). | Kernels that pass in the Simulator could fail on another device class (not on the A17 Pro). | Size tiles from runtime limits; Metal API validation on in debug; fallback paths behind `supportsFamily(.apple7)` tested on the Mac by forcing them. |
| 10 | **32-bit float filtering is not guaranteed** on the A17 Pro (sdk-feasibility §15). | Linear-sampling tricks on `r32Float` would break. | All filtered sampling is on `rgba16Float`; measurement kernels use `read()`. The device card shows the flag. |
| 11 | **Specimen size vs speed.** Gathers and bilateral at 894² may not hold 120 Hz (bokeh 64 samples modeled at ≈ 15 ms full screen, gpu-pipeline §4.2; the window is 22% of that). | Crowns feel laggy. | Half-resolution preview while turning (§9.1), full-resolution Run on release; `PREVIEW ½` in the status row. |
| 12 | **Dense engineering text may overwhelm** someone who came for "what does a blur look like". | The app reads as a spec sheet. | The first viewport is image-first. Layers 6–7 are opt-in (Descend). The serif-italic signature line and the meaning band carry the human reading on every screen. Lessons (§8) give guided entry points. |
| 13 | **Glass over a live Metal view** (floating group over the specimen while scrolling) is UNVERIFIED to sample `CAMetalLayer` faithfully (metro-adaptation §G.2 item 1). | Visual glitches in the chrome, not in measurements. | Measurements read textures, never the screen. A device check is on the QA list. |

---

## 15. Sources

Project research (all read for this concept; section numbers cited inline): `BRIEF.md`; `research/CATALOG.md` (§1 taxonomy, §2 master table, §5 corrections E1–E17, §6 tiers, §7 pairs); `research/catalog-lsi.md` (§0, §1–§17, §19); `research/catalog-spatial.md` (§0, §1.1, §1.8, §1.9, §1.10, §2.1–§2.3); `research/catalog-nonlinear.md` (§0, A1–A4, B1–B2, D6–D7); `research/stack-semantics.md` (§0, §1–§8); `research/gpu-pipeline.md` (§0–§9); `research/live-calibration.md` (§1–§8); `research/metro-adaptation.md` (§A–§G); `research/sdk-feasibility.md` (§0–§17).

Design references viewed: Metro Station `Skills/metro-station-design-system/assets/visual-reference.png` (build 14, edition 1.0); `ClassicalMLSimulator/Documentation/Screenshots/workbench.jpg`; `LosAlamosSimulator/Documentation/QA/Trinity.jpg`; `Metro Station/Documentation/crowns-v4-preview.jpg`.

External sources relied on through the research files (not re-fetched for this document): Apple Tech Talks 10855, 10857, 111374, 111431, 10001; WWDC 2014 session 419; WWDC25 session 219 "Meet Liquid Glass"; Metal Feature Set Tables (21 May 2026); W3C Filter Effects Module Level 1 and 2; CSS Backgrounds 3 §6.1.2; Skia `SkBlurMask.cpp`; Rákos 2010 "Efficient Gaussian blur with linear sampling"; Bjørge 2015 "Bandwidth-Efficient Rendering"; Tomasi & Manduchi 1998; Paris & Durand 2006/2009; Barre-Brisebois 2017 "Hexagonal Bokeh Blur Revisited"; White & Barré-Brisebois, SIGGRAPH 2011; McIntosh, Riecke & DiPaola 2012; Mitchell 2007 (GPU Gems 3 ch. 13); WCAG 2.x success criterion 2.3.1 (three flashes, cited from memory).

Numbers computed for this document: `$TMPDIR/blur2ool-concept-engine/nums.py` and `nums2.py` (σ = 8 kernel and merged taps, step-edge probe values in both blend spaces, dispatch counts, zoom sampling radii, bilateral range weights, hexagon energy per pixel). Wireframes were drafted and width-checked with `wf/*.py` in the same folder.

<!-- STATUS: COMPLETE -->
