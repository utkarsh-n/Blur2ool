# Blur2ool — Judge verdict: Engineering feasibility + Metro compliance

Date: 14 October 2026. Judge lens: can a team of AI agents build this well in SwiftUI + Metal for iOS 27 / Swift 6 strict concurrency, real-time on an A17 Pro and in the Simulator; does it respect Metro Station contracts (fixed foreground, constant glass opacity, touch ownership, smallest useful component set, accessible alternatives); what is the scope risk.

Status: IN PROGRESS (being written incrementally).

## 0. Method and inputs

Read in full: `BRIEF.md`; `design/concept-instrument.md` (674 lines); `design/concept-descent.md` (957 lines); `design/concept-engine.md` (863 lines). Research read for grounding (feasibility-relevant sections in depth, catalog files skimmed for tier and cost facts): `research/CATALOG.md`, `catalog-lsi.md`, `catalog-spatial.md`, `catalog-nonlinear.md`, `stack-semantics.md`, `gpu-pipeline.md`, `metro-adaptation.md`, `sdk-feasibility.md`, `live-calibration.md`. Metro Station skill and spec sections cited through `metro-adaptation.md` and checked directly where a compliance call depends on exact wording (see §1.3).

Scoring scale (this lens only): 10 = buildable to a high standard by an AI agent team in the available time with no Metro contract broken; 7 = buildable with named, bounded fixes; 5 = buildable only after material re-scoping; 3 or below = a core promise is not buildable or breaks a Metro contract that cannot be argued away.

Interim reading notes (kept so a killed run loses nothing):

- **Instrument**: non-scrolling Bench (DEPARTURE from Metro adaptation §D.1-D.2), six gestures on one 298-pt window (tap probe, drag pan/handle, long-press Metal loupe, pinch 1-8x zoom, two-finger double-tap reset, wipe divider), Turret glyph strip of ~45 entries, 7-layer Descent with a pinned periscope that is a *second* MTKView region, Trace that reads back 9x9 per pass, Fingerprint card with 4 GPU-rendered insets per card, sigma-hold on switch, Line-up 2x2 compare. Parameters sheet instead of Stepper on Bench. Deck grammar A-E declared per blur.
- **Descent**: scrolling Lab (Metro-conformant), descent rail of 7 chips in first viewport, 7 floor cards of fixed height 232 below the fold, pushed Trace with step grammar, Atlas sheet with Families / Fingerprints matrix / Divergence ("floor where two blurs part ways"), Lessons, This-phone probe screen. Proposes the `TRACE_PROBE` function-constant build so trace values are what the GPU produced (R2). Generates floors from BlurCore templates (R1). Build order puts honesty pieces first.
- **Engine**: scrolling Bench with telemetry + PARITY in first viewport, immutable `Run` record as the single data object, timing protocol (3 warm-up + 15 timed, per-pass encoders, Metal 4 counter heaps device-only), first-launch device probe and SwiftUI `measurePSF` running automatically, Calibrate sheet with model competition, Run log JSON export, 8 layers (Shader and Silicon split), Compare that varies exactly one axis (Operator, Implementation, Precision, Space, Apple), "ON THIS PHONE" fingerprint row measured from GPU output, source SHA stamping.

## 1. Ground truth from research that constrains every concept

These facts come from the research files and decide most of the feasibility calls below. Labels are kept from the source.

### 1.1 Swift 6 and Metal shape

- `MTKView` hosted through `UIViewRepresentable`, with a `@MainActor` renderer as the `MTKViewDelegate`, typechecks with zero diagnostics in Swift 6 language mode, complete strict concurrency and `-warnings-as-errors`, for both the simulator and the device (MEASURED, `sdk-feasibility.md` §5, §16).
- `MTLTexture`, `MTLBuffer` and `MTLCommandBuffer` are **not** Sendable; `MTLDevice`, `MTLCommandQueue`, pipeline states and libraries are. `waitUntilCompleted()` is a compile error inside `async`; readback uses `await commandBuffer.completed()` (REFERENCE, SDK headers, `sdk-feasibility.md` §5).
- Consequence: the engine should be one `@MainActor` GPU context that encodes on the main actor (microseconds per blur) and publishes **immutable value records** (Sendable, Codable) to the UI. `BlurCore` stays nonisolated so CPU references run in `swift test` and on background tasks. An actor-hopping engine around non-Sendable textures is the wrong design (`sdk-feasibility.md` §5 "Architecture advice").
- Ship a precompiled `default.metallib`: cold `makeLibrary(source:)` took 1.08 s on the Mac and 6.6 s (fast) / 19.0 s (safe) in the simulator (MEASURED, `sdk-feasibility.md` §14).
- Classic Metal only. Metal 4 is stubbed out of the simulator SDK, so any Metal 4 code needs `#if !targetEnvironment(simulator)` and a classic fallback, i.e. two engines (MEASURED compile failure, `sdk-feasibility.md` §7).

### 1.2 Simulator realities

- Apple2-class: 512 threads per threadgroup, 16 KB threadgroup memory, no read-write textures, no 32-bit float filtering, no non-uniform dispatch under validation (MEASURED, `sdk-feasibility.md` §15; `gpu-pipeline.md` §2.7).
- It silently runs work its family does not cover unless Metal API validation is on, and it does not enforce the 16 KB limit even then (MEASURED, `gpu-pipeline.md` §2.7 items 2–3). Tile sizes must come from runtime limits and be unit-tested.
- Simulator GPU timings are meaningless (a 1.07 GB blit "took" 0.055 ms, MEASURED). Numerical results were identical to the M1 Max, so the simulator is a valid **correctness** host (`gpu-pipeline.md` §2.7 items 4–5).
- `getBytes` on a mip level of a shared texture returned level 0 in the simulator; blit-based readback was correct (MEASURED, `gpu-pipeline.md` §2.7 item 7).

### 1.3 Real-time budget on the A17 Pro (all MODELED; nothing has run on the phone)

The specimen window is 894 × 894 = 0.80 MP, 22 % of the 3.61 MP full screen. Scaling `gpu-pipeline.md` §4.2's full-screen A17 Pro estimates by 0.22 (my arithmetic, COMPUTED from MODELED inputs):

| Kernel | Full screen, A17 Pro (MODELED, `gpu-pipeline.md` §4.2) | 894² window (MODELED) | Fits an 8.33 ms 120 Hz frame? |
|---|---|---|---|
| Linear-sampled Gaussian σ 8 | ≈ 3.4 ms | ≈ 0.75 ms | yes |
| Compute-tile Gaussian σ 21 | ≈ 11 ms | ≈ 2.4 ms | yes |
| SAT box (RGBA fp32) | ≈ 9.7 ms | ≈ 2.1 ms | yes |
| Golden-angle bokeh, 64 samples | ≈ 15 ms | ≈ 3.3 ms | yes, with little room |
| Brute bilateral, 17 × 17 = 289 taps with `exp` | not in the table | ≈ 8–15 ms (from the M1 Max 289-tap 2-D convolution, 0.13–0.24 ms at 256², `sdk-feasibility.md` §14, × 12.2 for pixel count × 5 for the A17 Pro factor) | **no**: needs the half-resolution preview |

All three concepts already specify a half-resolution preview while a control moves. That is necessary, not optional, for the O(r²) and search-based filters. The 5× M1 Max → A17 Pro factor and the 51.2 GB/s bandwidth are UNVERIFIED (`gpu-pipeline.md` §2.5, §4.2).

### 1.4 What an AI agent team can and cannot verify

- **Can, headlessly:** `swift test` on `BlurCore`; the Mac GPU↔CPU parity CLI (MEASURED working, `sdk-feasibility.md` §14); the same binary in the simulator via `simctl spawn` as an Apple2-limits checker; offscreen PNG renders and `simctl io screenshot`; `swiftc -typecheck` against the iOS SDK in about 4 s.
- **Cannot reliably:** gesture feel, held/edge touches during redraw, or touch ownership. QuantumToy's simulator UI automation failed outright (`DTServiceHubClient failed to bless service hub`) and injected taps "left the UI unchanged" (`metro-adaptation.md` §F.3 item 4). Metro's own acceptance matrix needs held contact traces (spec §20). Those checks need his hands on his phone.
- **So:** a concept whose correctness lives in custom gestures carries more risk for this team than one whose correctness lives in data, kernels and layouts that can be tested headlessly.

### 1.5 Metro contracts that separate the concepts

From `metro-adaptation.md` §A and the spec (sections checked directly: §8 interaction, §9, §12, §19, §20):

- **A.1** Foreground (values, units, labels, control frames) is never filtered or transformed. **Specimen rule** (`metro-adaptation.md` §C.1): no glass, Material, `.blur` or optical shader over the image window or a plot, except the labelled Liquid Glass exhibit.
- **A.2** Lens opacity is constant (0.48, 1.0 under Reduce Transparency); its centre never moves.
- **A.7** Native held Stepper repeat keeps working while the instrument redraws. Spec §9: "The Stepper sits immediately under the hero."
- **A.8** Content stays reachable above floating controls and at large text sizes.
- **A.13** Requested and acknowledged states are separate; a fixed-height status row says "applying".
- **A.16** A touch that begins on a control belongs to it for the whole sequence. The bridge protects only the nearest `UIScrollView` pan.
- **A.18** Every gesture has a native or accessible alternative.
- **Spec §12:** the floating group is native glass with no backing strip; "Explain quantities and model limits in a separate readable surface rather than overloading the instrument face with implementation detail."
- **Spec §19 adoption sequence:** palette and panels first, then one primary object, then direct controls, then compact channels "only when they communicate independent information", and material response last. SKILL.md: "Adopt the smallest useful component set."
- **Spec §20:** drawings consume prepared snapshots; expensive transforms run off the main actor; "limit simultaneous native glass effects".

Note that Metro does **not** require the root to scroll. Spec §9 says only that touches beginning outside a Stepper "may scroll the page". So the Instrument concept's fixed Bench is not itself a Metro violation. Its risks are the gesture load and the layout slack, discussed in §2.

## 2. Concept: Instrument (toy-first)

**Shape.** A fixed, non-scrolling Bench that fits one 430 × 932 screen. Six gestures share the 298-pt specimen window: tap places the probe; a one-finger drag moves a handle or pans the specimen; a long press opens a Metal loupe; a pinch zooms 1–8×; a two-finger double tap resets; and the wipe divider is dragged. Path blur adds a paint mode. A horizontal "Turret" of about 45 footprint glyphs selects the blur. The 7-layer Descent is pushed, with a pinned "periscope" (a second live Metal view). The fingerprint card, the catalog, the parameters and the settings are sheets.

### Feasibility

| Item | Verdict | Why |
|---|---|---|
| Specimen gesture set | **High risk** | SwiftUI cannot cleanly rank six gestures over a `UIViewRepresentable` `MTKView`. Handle hit-tests must win over pan, long press must beat drag, pinch must coexist with both, and the divider must own its touch inside the same window. In practice this needs a UIKit gesture layer with `UIGestureRecognizerDelegate` priorities. None of it can be certified headlessly (§1.4), and the concept's own risk table (#2) admits it must be verified "on device with held and edge touches during redraw". |
| Pan-the-specimen toy | Medium | Each drag event must offset or regenerate the procedural specimen and re-run the blur. That is cheap for Gaussians and too slow for brute bilateral (§1.3), so pan needs the half-res path. It also moves the probe's meaning: the probe is in window coordinates, the content moves under it. |
| Fixed Bench | Medium–high | Its budget has 22 pt to spare at 430 pt wide. That slack must absorb two UNVERIFIED quantities: the safe areas (`metro-adaptation.md` §G.2 #2) and the rendered glass height, which "native style padding can enlarge" (spec §12; §G.2 #3). A scrolling root absorbs both; a fixed one breaks. The 402-pt simulator the adopters use needs a recomputed layout. At AX sizes the Bench becomes a scroll view and **image gestures are switched off**: two layouts and two gesture regimes to build and test. |
| Periscope | Low–medium | A second `MTKView` (or a second drawable) showing a crop of the same texture. That is doable, but it is a second render path that must stay in step with the first. |
| Trace | Medium | It reads back 9 × 9 texels per pass, which is honest per pass. Per-fetch values (offset, weight, fetched value) are not recorded by the GPU in this design, so they would be CPU reconstructions labelled LIVE. See §3 for the fix. |
| σ-hold on switch | **Low risk, high value** | A COMPUTED conversion table in `BlurCore` (`catalog-lsi.md` §20). |
| Deck grammar A–E declared per blur in `BlurCore` | Low risk | Data, not inference from live values (AssemblerToy `ViewThatFits` lesson). |
| Fingerprint strip rendered by the GPU at the held σ | Low | Four small extra dispatches per card. |

### Metro compliance

- **Good:** foreground is literally still (nothing scrolls); `InstrumentLensSurface` unmodified, constant 0.48, no numbers under the glass; no glass over the specimen except the exhibit; the floating group never overlaps the window; the loupe is Metal, not glass (Specimen rule; contract A.2).
- **Weak:** spec §9 puts the native Stepper directly under the hero. Instrument moves every Stepper into a Parameters **sheet** and relies on the crowns' ± glass `Button`s, which are not native held-repeat Steppers (contract A.7). This is the largest Stepper deviation of the three.
- **Weak:** contract A.16 ownership becomes a priority puzzle inside one region rather than "a touch that begins on a control belongs to it".
- **Weak:** largest component set: Turret, periscope, loupe, pinch zoom, four compare modes (Wipe, Flip, Difference, Line-up) with seven B sources, deck grammars D and E, paint modes. This runs against SKILL.md's "smallest useful component set" and spec §19's "compact channels only when they communicate independent information".
- The loupe floats 84 pt above the finger and can transiently cover the readout band or pills. That is acceptable only if it is constrained never to cover the hero.

### Scope

Every Tier 1, Tier 2 and Tier S entry is a live toy on the Bench, each with a deck, default specimen and often a bespoke handle: paint the shake path, drag the moving disc, drag the rotation speed, paint a path for path blur. That is the widest interaction surface of the three, and most of it can only be judged by hand.

**Score: 5.5 / 10.** It has excellent individual ideas (σ-hold, Metal loupe, local pills, the deck declaration). But the core interaction model is the hardest to build correctly and the least testable for an agent team, and the fixed layout has no slack for the unverified geometry.

## 3. Concept: Descent (pedagogy-first)

**Shape.** A scrolling Lab exactly in the shape `metro-adaptation.md` §D recommends. The first viewport holds the specimen, crowns and a 7-chip **descent rail**. Below the fold come telemetry, seven fixed-height (232 pt) floor cards, the fingerprint card and the parameters panel. A pushed Trace walks one pixel with a step grammar. The Atlas sheet has Families, a Fingerprints matrix and Divergence (the floor where two blurs part ways). There is a Lessons sheet and an on-demand "This phone" probe screen.

### Feasibility

| Item | Verdict | Why |
|---|---|---|
| Interaction | **Low risk** | Tap places the probe through `SpatialTapGesture`, which does not fight the scroll. The touch bridge sits only on small controls: crowns, Steppers, tiles, the 44-pt centre and focus-line handles, and the compare divider. Path and mask drawing are replaced by preset menus, because freehand drawing "has no good accessible twin" (§10.2, §14). This is the smallest custom-gesture surface of the three. |
| `TRACE_PROBE` (R2) | **Feasible: probed for this verdict** (§3.1) | One `.metal` source, two specializations by function constant. The traced build writes each tap's offset, weight, fetched value and running sum for the probe pixel only. A test asserts traced == untraced output bit for bit. This is the only design among the three in which per-fetch Trace values are genuinely what the GPU fetched. |
| Shown source = compiled source | Low risk | The `.metal` text ships as a resource, and a unit test asserts it is byte-identical to the compiled source. A build-time check is cheaper and more certain than Engine's on-device recompile (§4). |
| Floors as templates (R1) | Medium risk, well mitigated | 55 entries × 7 floors = 385 cards. The plan generates them from `BlurCore` data, hand-writes only a signature sentence, a governing rule per floor and a closing lesson per Tier 1 entry, and adds a unit test that no card renders a placeholder plus a length check at the default Dynamic Type size. That plan is exactly what makes the volume tractable for agents. |
| Rail chip `PIXEL` (LIVE) | Medium | It needs a probe readback per acknowledged frame. That is a 1-texel blit and cheap, but it must be coalesced (newest generation only) and must not trigger a timing run. |
| Long Lab scroll with Swift Charts in seven cards | Medium | It needs `LazyVStack` and leaf-only observation of live values (Toothpaste lesson, `metro-adaptation.md` §F.5 item 4). Chart performance with many marks on the A17 Pro is UNVERIFIED (`sdk-feasibility.md` §11). |
| Atlas Fingerprints matrix | Low–medium | An 8-column `Grid` in 406 pt is tight, and every cell must be spoken. The data comes from `BlurCore`. |
| Build order | Strong | Honesty pieces first: `BlurCore` and the four worked examples as tests, then the parity CLI with `TRACE_PROBE`, then the Gaussian Lab. |

### Metro compliance

- **Best of the three.** It is the adaptation note's layout, with `.id(blur.id)`, one `.sheet(item:)`, no tab bar, a bottom reserve taken from the measured group, and a reserved 98-pt control slot that never collapses. It uses four control types and no `Slider`, adds a photosensitivity rule (WCAG 2.3.1), and lists its deviations (R11).
- **Weak:** the parameters panel, which holds the `DecimalParameterStepper` twin of the primary parameter and the variant, edge, colour-space and precision pickers, sits at content y ≈ 2,950, **after** all seven floor cards and the fingerprint. Spec §9 wants the Stepper immediately under the hero. Engine's "just below the fold" is a smaller deviation. Fix: move the parameters panel directly under telemetry, ahead of the floors (graft G-11).
- Rail chips carry glyph-only badges. This is acknowledged and is the only exception, and the glyphs differ by shape, not colour alone.
- The floating glass passes over the scrolling `MTKView` (R12). Whether glass samples Metal content correctly is UNVERIFIED, but it is harmless to measurements, and the same is true of Engine.

### Scope

Large, but shaped as data: 385 templated floor cards, the Atlas (three tabs), 30 lessons plus 4 guided descents, 20 procedural specimens, and a Trace for every algorithm class. The risk is content duplicated across three surfaces (Lab cards, Trace, Divergence). That is tractable only if all three read one data model (must-avoid M-12).

**Score: 8.0 / 10.** It has the simplest interaction, the best Metro fit, the most testable content pipeline and the only honest per-fetch trace mechanism. It loses points for content volume, a long Lab, and the buried parameters panel.

### 3.1 Probe: is `TRACE_PROBE` buildable from a precompiled library? (MEASURED for this verdict)

Probe files are in `$TMPDIR/blur2ool-judge-feasibility/` (`trace.metal`, `trace_fma.metal`, `main.swift`). The kernel is a horizontal linear-sampled Gaussian pass (σ 8, k 3, 12 bilinear pairs per side = 25 fetches) on an 894 × 894 `rgba16Float` step edge with seeded noise. It declares `constant bool TRACE_PROBE [[function_constant(0)]]` and an optional trace buffer `[[buffer(5), function_constant(TRACE_PROBE)]]`. When the constant is true it writes `{offset, weight, fetched value, running sum}` for each tap of one probe pixel, (412, 300). Output goes to a `float4` buffer so it can be compared bit for bit. Host: Apple M1 Max, macOS 27.2. The host was under very heavy load from parallel agents (load average up to ≈ 950), so the timings are indicative only.

| Check | Result (MEASURED, M1 Max) |
|---|---|
| The same source compiles offline for `macosx`, `iphoneos` and `iphonesimulator` | yes, all three exit 0 |
| Specialize both variants from a **precompiled** `.metallib` (`makeFunction(name:constantValues:)` + pipeline) | first specialization 417 ms (plain, cold, on the loaded host), 59.5 ms (traced), 0.5 ms when repeated (cached). This is far below the 1–19 s of a source compile (§1.1), so Trace does not need runtime source compilation. |
| GPU time, plain vs traced (median of 12, host GPU, **not** the phone) | 0.557 vs 0.558 ms: the traced build costs nothing measurable |
| **Default fast math:** traced vs untraced output, bitwise | **1,621,131 of 3,196,944 words differ** (about half). The probe value is 0.7429128 untraced vs 0.74291295 for the traced final running sum: a 1-ulp float difference. Adding the trace stores changed the compiler's contraction or ordering for **every** pixel, not only the probe. |
| `-fno-fast-math` | 0 words differ; probe bit-equal |
| `-fmetal-math-mode=safe` | 0 words differ; probe bit-equal |
| **Default fast math, but accumulation written as explicit `sum = fma(x, w, sum)`** | **0 words differ; probe bit-equal**; GPU time unchanged (0.498 vs 0.503 ms) |

Reading:

1. Descent's `TRACE_PROBE` is buildable from the shipped `default.metallib`, at no measurable GPU cost.
2. Its R2 claim, that the traced build equals the untraced build "bit for bit", is **false as written** under Xcode 27's default fast math. It becomes true when accumulation is spelled with explicit `fma()` (or the kernels compile with safe math). The difference is 1 float ulp: invisible after the `rgba16Float` store, but it would fail a bit-exact test and must not be papered over.
3. The final design should therefore (a) write every accumulating blur kernel with explicit `fma()`, (b) keep the bit-exact traced-vs-untraced assertion in the parity CLI, and (c) when Trace is open, render the displayed frame with the traced specialization itself, so the honesty claim does not depend on compiler behaviour (graft G-7).
4. Whether the same holds on Apple9 (A17 Pro) is UNVERIFIED. The check belongs in the app's debug menu on the phone.

## 4. Concept: Engine (GPU-truth-first)

**Shape.** A scrolling Bench whose first viewport ends on a telemetry row of `σ EFF · GPU · PARITY vs CPU`. One immutable **Run** record (identity, context, kernel, timing, cost model, correctness, shape, provenance) is the source of every number. A timing protocol uses 3 warm-ups and 15 timed command buffers, one encoder per pass, thermal state per Run, and a device-only Metal 4 counter-heap path. The first launch runs an automatic device probe and a SwiftUI `measurePSF`. A Calibrate sheet holds model competition. A Run log exports as JSON. There are 8 layers (Shader and Silicon split). Compare varies exactly one axis: Operator, Implementation, Precision, Space or Apple.

### Feasibility

| Item | Verdict | Why |
|---|---|---|
| Run record | **Best architecture of the three** | An immutable `Sendable, Codable` value is exactly what Swift 6 wants to cross isolation domains (§1.1). It makes A.13 (requested vs acknowledged) structural, makes Compare a diff of two Runs, and makes the log free. |
| Timing protocol | Strong, needs coalescing | Per-pass encoders, median + IQR, N shown, ABAB interleaving for A/B, thermal exclusion, a fused-vs-split "measurement overhead" readout, nil timings in the simulator. But "each value gets its own Run" at ≤ 20 crown events/s would mean up to 360 command buffers per second. Timing must run only after the value settles (the concept's own 300-ms full-res rule), never per detent. |
| First-launch automatic probes | **High risk as designed** | In the first 10 s it runs a copy-bandwidth probe, an FMA throughput probe, mip and sub-texel probes, and `measurePSF` at 6 radii × 4 phases. `measurePSF` uses `ImageRenderer` and is `@MainActor` (`live-calibration.md` §7), so it competes with the first crown touch (contract A.7). The benchmarks also heat the GPU and contaminate the very GPU times the Bench shows next. These should be on demand (Descent's "This phone") or deferred to idle with a visible state. |
| On-device recompile of the shown source | Medium–high cost, low value | The simulator took 6.6–19 s cold (§1.1), and the on-device time is UNVERIFIED. Comparing function lists does not prove the code is identical; the SHA stamp plus a build-time byte-equality test does. Drop the runtime recompile. |
| Trace | Medium honesty gap | `Next pass` reads back the probe's footprint from the real intermediate texture (honest per pass). But each fetch row's blended value and running sum are recomputed on the CPU from those texels, with the hardware's `t` quantization MODELED. Per-fetch values are therefore not GPU records. The fix is Descent's `TRACE_PROBE`. |
| Calibrate, model competition | Medium | Numerical fitting of box³ vs truncated Gaussian vs Gaussian on device. The fitting code is pure Swift and testable on the Mac against `live-calibration.md`'s numbers. |
| Metal 4 counter heaps (device only) | Low–medium | It is a second timing path behind `#if !targetEnvironment(simulator)`. Keep it optional or defer it (§1.1). |
| Swift 6 readback | See §4.1 | Applies to all three concepts, but Engine reads back the most (parity per Run, fingerprint shape fits, Trace). |

### Metro compliance

- **Good:** the adaptation layout; telemetry directly under the crowns, which matches Metro build 14's own screen; `SpatialTapGesture` probe; badges that cannot be hidden on MEASURED and INFERRED values; the strongest structural requested/acknowledged split.
- **Weak:** the zoom/spin centre is moved by a **"Centre" toggle in the status row**: "while it is on, a tap moves the centre instead of the probe". The status row is Metro's fixed-height readout (§16 "Applying"). Making it a control mixes foreground metadata with control, and it introduces a tap mode. Descent's 44-pt handle plus `Centre on probe` is the Metro-shaped answer.
- **Weak:** the first ten seconds are busy without input: pills ease in, the status row counts `RUN 7/18`, a device chip changes state. That is honest state, not decoration, but it sits uneasily with "a blur has no clock" and with A.7 if `measurePSF` hitches the main actor.
- `Flicker 2 Hz` is properly capped below WCAG's three flashes and off under Reduce Motion.

### Scope

Bounded by its own rule ("change one variable at a time"), which caps Compare. It has a staged family order and data-driven Tier 2 and 3 pages. The measurement subsystem (device probe, Calibrate, Run log, cost sweeps) is substantial engineering, but almost all of it is headless and Mac-testable, which suits an agent team.

**Score: 7.5 / 10.** It has the strongest engine architecture and measurement discipline. It loses points for automatic launch-time measurement load, per-detent Run pressure, a runtime recompile, CPU-reconstructed per-fetch trace values, and the status-row toggle.

### 4.1 Swift 6 readback trap that every concept inherits (MEASURED for this verdict)

ISOLATION_RESULT_PLACEHOLDER

## 5. Scores

Sub-scores are on the same 1–10 scale. "Scope safety" is high when the scope is safe. The overall score is a judgement, not an average: feasibility and Metro compliance weigh most, because scope can be cut later and a broken interaction model cannot.

| Concept | Feasibility (SwiftUI + Metal, Swift 6, A17 Pro, simulator) | Metro compliance | Scope safety | Agent-testability | **Overall** |
|---|---|---|---|---|---|
| Instrument | 5 | 6 | 4 | 4 | **5.5** |
| Descent | 8 | 8.5 | 5.5 | 8.5 | **8.0** |
| Engine | 7.5 | 7.5 | 6.5 | 8 | **7.5** |

### Strengths and weaknesses (summary)

**Instrument**
- Strengths: σ-hold on switch (COMPUTED, nearly free, high teaching value); a non-glass Metal loupe that respects the Specimen rule; `LOCAL @ PROBE` pills for shift-variant blurs and T(ν, A) at local contrast for adaptive ones instead of empty plots; deck grammar declared per blur in `BlurCore`; exactly three badged numbers on the root; foreground physically still.
- Weaknesses: six gestures on one 298-pt Metal view; a fixed layout with 22 pt of slack against UNVERIFIED safe areas and glass size; a second layout and gesture regime at AX sizes; Steppers only in a sheet (spec §9, A.7); the largest component set; every Tier 2 entry live on the root with bespoke handles; per-fetch Trace values reconstructed on the CPU.

**Descent**
- Strengths: the most Metro-conformant layout (`metro-adaptation.md` §D); the smallest gesture surface; `TRACE_PROBE` per-fetch honesty; shipped source checked byte-identical at build time; floors generated from `BlurCore` with no-placeholder and text-length tests; feature-relative probes (R3); an explicit deviation list; a photosensitivity rule; an honesty-first build order; on-demand "This phone" probe.
- Weaknesses: 385 floor cards plus Trace plus Divergence (content volume); a ~3,200-pt Lab with Charts in seven cards; the parameters panel buried after the floors; a per-frame LIVE rail readback that must be coalesced; rail chips with glyph-only badges.

**Engine**
- Strengths: the immutable Sendable `Run` record; the timing protocol (warm-ups, median + IQR, N, per-pass encoders, ABAB, thermal state, measurement-overhead readout, simulator nil); Compare varying exactly one axis with a legal-only B menu; model competition for the SwiftUI kernel; an "ON THIS PHONE" fingerprint row measured from GPU output; a Run log that sends device numbers back to research; PARITY in the first viewport.
- Weaknesses: automatic launch-time probes and a `@MainActor` `measurePSF` in the first 10 s; Run-per-detent pressure; an on-device recompile of the shown source; CPU-reconstructed per-fetch trace values; a centre toggle in the status row; an optional second timing path (Metal 4).

## 6. Winner

**Descent**, under this lens. It is the concept an AI-agent team is most likely to build *well*. Its correctness lives in data, kernels and layouts that `swift test`, the Mac parity CLI, offscreen renders and simulator screenshots can check. Its only custom touch targets are small, touch-owning controls, which the Metro starter already handles. It needs the fewest Metro deviations, and it is the only concept whose pixel trace can honestly carry LIVE on every fetch.

The final design should not be Descent alone. Build **Descent's shell and content pipeline on Engine's Run engine**, with Instrument's σ-hold, local pills and Metal loupe added. Engine is a close second, and its architecture should be adopted wholesale under Descent's screens. Instrument's fixed multi-gesture Bench should not be built.

## 7. Graft list (the final design must include)

Grouped by layer. Each item names its source concept.

**Engine and concurrency**

- **G-1 (Engine)** One immutable `Run` value (`Sendable`, `Codable`) per acknowledged render: identity, context (device, GPU family, OS build, thermal state, Low Power Mode, simulator flag), kernel facts, timing, cost model, parity, shape fit and source SHA. Screens only read Runs. Requested values live separately and show immediately; everything output-derived follows the newest completed Run. The fixed status row says `RENDERING…` while they differ (contract A.13).
- **G-2 (research + this probe)** One `@MainActor` GPU context owning device, queue, pipelines and textures. `BlurCore` is nonisolated. Readback uses the continuation-plus-completion-handler pattern measured in §4.1, **not** `await commandBuffer.completed()` on a command buffer that touched main-actor textures. Generation tokens ensure only the newest request publishes (`metro-adaptation.md` §F.2 item 3).
- **G-3 (Engine, amended)** Timing protocol: one command buffer per blur, one encoder per pass, 3 warm-ups, median + IQR of N with N shown, thermal state and Low Power Mode stored per Run, ABAB interleaving for A/B deltas, and the fused-vs-split overhead shown. Timing runs **only after the value settles** (about 300 ms after the last accepted change), never per crown detent. In the simulator every timing is `nil` and drawn struck through.
- **G-4 (all three)** Half-resolution preview while a control moves for O(r²), gather, iterative and search filters, with full resolution after settle. The status row says `PREVIEW ½`. Timings are recorded only for full-resolution Runs.
- **G-5 (research)** Safe-dispatch rules everywhere: `dispatchThreadgroups` with a bounds check after barriers; 16 × 16 groups clamped to `maxTotalThreadsPerThreadgroup`; threadgroup memory ≤ 16 KB sized from runtime limits and unit-tested; ping-pong instead of `read_write`; no filtered sampling of 32-bit float; mip readback by blit; Metal API validation on in debug; Apple7-only fast paths behind `supportsFamily` with the fallback forced and tested on the Mac.
- **G-6 (research)** Classic Metal only, with a precompiled `default.metallib`. The Metal 4 counter-heap timing path is deferred past v1 (command-buffer `gpuStartTime/gpuEndTime` plus stage-boundary counters where `supportsCounterSampling(.atStageBoundary)` is true are enough).

**Trace honesty**

- **G-7 (Descent, amended by §3.1)** `TRACE_PROBE` by function constant from one `.metal` source, specialized at runtime from the precompiled library. Every accumulating kernel spells its accumulation as explicit `fma()`, which made traced and untraced outputs bit-identical under default fast math in §3.1. The parity CLI keeps the bit-exact traced-vs-untraced assertion. When Trace is open, the **frame on screen is rendered by the traced specialization itself**, so the recorded taps and the displayed pixel come from one execution whatever the compiler does. Pre-warm the traced pipeline when Trace opens (first specialization took 59–417 ms on a loaded M1 Max).
- **G-8 (Descent + Engine)** The shown shader text ships as a resource. A build-time unit test asserts it is byte-identical to the compiled source, and its SHA-256 is stamped into the bundle and every Run. There is no on-device recompile.

**Verification**

- **G-9 (research, all)** A Mac parity CLI that loads only `App/GPU/Shaders/*.metal` with `mathMode` set explicitly on both sides, runs every kernel against `BlurCore` with the tolerances of `sdk-feasibility.md` §14 (1e-5 float, 2e-3 half), and also runs under `simctl spawn` as an Apple2-limits checker.
- **G-10 (Descent)** Floor and layer pages generated from `BlurCore` data. Unit tests check that every catalog entry renders every floor with no placeholder string, that card text fits 406 pt at the default Dynamic Type size, and snapshot every entry's floors offscreen. One data model feeds the Lab cards, the Trace and the Divergence rows.

**Layout and Metro**

- **G-11 (Descent layout, fixed)** A scrolling Lab per `metro-adaptation.md` §D: `.id(blur.id)`, `SpatialTapGesture` for the probe, the touch bridge only on small controls, one `.sheet(item:)`, no tab bar, and a floating group with a bottom reserve from its measured height. Order below the fold: **telemetry → parameters panel (`DecimalParameterStepper` + variant/edge/space/precision pickers) → pass tiles → floor cards → fingerprint**, so the native Stepper is within one short scroll of the hero (spec §9).
- **G-12 (Engine)** The first viewport ends on `σ EFF · GPU · PARITY` telemetry directly under the crowns, as in Metro build 14. Live values are observed only by those leaf views (Toothpaste lesson).
- **G-13 (Instrument deck + Descent primary type)** Each blur declares in `BlurCore` its primary parameter kind (continuous, integer, named, none), fine step, display precision, semantic stops and control arrangement. The 98-pt control slot is reserved and never collapses. Layout never depends on live values.
- **G-14 (Instrument)** σ-hold on switch, with the status line `σ HELD 12.0 px → R 26.3 px`, the explicit `σ NOT DEFINED · RANK FILTER / SPACE-VARIANT` cases, and a `MATCH σ` toggle.
- **G-15 (Instrument)** For shift-variant blurs, the pills switch to `LOCAL @ PROBE`. For adaptive blurs, FREQ draws T(ν, A) at the measured local contrast. Rank filters engrave `N/A · RANK`. Pill outlines and titles stay static.

**Compare and measurement**

- **G-16 (Engine + Descent)** Compare changes exactly one axis (Operator, Implementation, Precision, Space, Apple), and the B menu offers only legal choices. Views are Wipe (44-pt touch-owning divider, adjustable ±10 %) and |A−B| with a numeric legend. Descent's "first floor where they part ways" row is static `BlurCore` data shown with it.
- **G-17 (Descent "This phone" + Engine probes)** Device probes (sub-texel bits, `generateMipmaps` impulse, copy bandwidth, compression A/B, limits beside Feature Set Table values) run **on demand**, cached with OS build and date. Upgrades from REFERENCE or MODELED to MEASURED stay visible for a session.
- **G-18 (Engine)** Calibrate with model competition for SwiftUI `.blur` (Gaussian vs box³ vs truncated Gaussian), with the path named on the badge (`ImageRenderer`). It runs on first use of a Tier S entry, not at launch, so the main actor stays free for the crowns.
- **G-19 (Engine)** The Run log is persisted in the app container and exportable as JSON, so device numbers can replace the "MEASURED on macOS 27.2" figures in the research files.

**Honesty rules and glass**

- **G-20 (Descent + Engine)** Honesty grammar: the badge word is primary; badges never animate; MEASURED carries device, OS and date; UNVERIFIED is a qualifier or the value itself, never a guessed number; user inputs carry no badge; the simulator shows `NO GPU TIMING IN SIMULATOR` and `NOT THIS DEVICE`; source disagreements are shown with a `SOURCES DISAGREE` caption.
- **G-21 (all three)** `InstrumentLensSurface` is used unmodified for the kernel well (D 88, `motionActive: false`, 0.48 constant, 1.0 under Reduce Transparency), with a token-parity test against hand-rolled values. Magnification happens only of a **copy**: the Trace texel grid, plus Instrument's opaque Metal loupe as an optional long press in a later build. No glass over the specimen except the Liquid Glass exhibit, whose specimen is drawn in SwiftUI.

**Specimens and build order**

- **G-22 (Descent)** Procedural specimens generated at the window's pixel size, with probes defined by feature rather than coordinate. Tests pin the worked numbers at N = 894 and check feature-relative values at N = 810. Periodic patterns never move without `Play` (WCAG 2.3.1).
- **G-23 (Descent + Engine)** Build order: `BlurCore` catalog, kernels and the four worked examples as tests → parity CLI with `TRACE_PROBE` → Gaussian Lab first viewport on the Run engine → floor templates → Gaussian Trace → zoom, bilateral, hexagon → remaining Tier 1 in Engine's family order → Compare, Atlas, Lessons → This phone, Calibrate → Tier 2 and Tier S.

## 8. Must avoid

- **M-1** A specimen window that hosts pan, pinch zoom, long-press loupe, two-finger reset, paint and handle drags at once (Instrument). Keep it to tap-to-probe, 44-pt handles with button and Stepper twins, and the compare divider.
- **M-2** A fixed, non-scrolling root whose fit depends on UNVERIFIED safe areas and glass height, and a second gesture regime at accessibility text sizes (Instrument).
- **M-3** Benchmarks, device probes or `measurePSF` sweeps that run automatically in the first seconds after launch or on the main actor while the crowns are live (Engine §1).
- **M-4** A timed Run (warm-ups + N command buffers) per crown detent. Render on every accepted change; time only after settle.
- **M-5** Recompiling the shown shader source on the device at runtime as proof of identity (Engine R6). Use a build-time byte-equality test and the SHA instead.
- **M-6** Per-fetch Trace values computed on the CPU and labelled LIVE (Engine §6.2, Instrument §6). They come from `TRACE_PROBE` records, or carry COMPUTED or MODELED.
- **M-7** Writing accumulation as `sum += x * w` under default fast math and then asserting that traced and untraced outputs are bit-identical. §3.1 measured half the output words differing by 1 ulp. Use explicit `fma()` (or safe math for those kernels), and render the traced frame itself while Trace is open.
- **M-8** `await commandBuffer.completed()` on a command buffer that encoded main-actor-isolated textures or buffers (§4.1: a Swift 6 compile error). Do not paper over it with `nonisolated(unsafe)`.
- **M-9** Metal 4 command model; `dispatchThreads`; `read_write` textures; linear sampling of `r32Float` and `rgba32Float`; a hard-coded 1024 threads per threadgroup; `getBytes` on a mip level of a shared texture.
- **M-10** Glass, `Material`, `.blur` or shaders over the specimen or a plot outside the Liquid Glass exhibit; a draggable or glass lens; numbers or labels under the kernel-well glass.
- **M-11** A tab bar; two `.sheet` modifiers on one view; `ViewThatFits` or layout choices driven by live values.
- **M-12** Three hand-written copies of layer content (Lab cards, Trace, Divergence). One `BlurCore` data model feeds all three.
- **M-13** Burying the native parameter Steppers below seven floor cards (Descent) or only in a sheet (Instrument).
- **M-14** A control or mode toggle inside the fixed status row (Engine's `Centre` toggle). The status row is readout only.
- **M-15** Bespoke on-root interactions for Tier 2 entries in v1 (painting shake paths and path-blur paths, dragging a moving disc or rotation speed). Use preset menus with Stepper twins.
- **M-16** Showing a MEASURED badge on a Mac or simulator number without its platform, or showing simulator GPU milliseconds at all.
- **M-17** Using XCUITest as the acceptance gate for gestures (QuantumToy failure). Gate on `swift test`, the parity CLI, offscreen and `simctl` screenshots, and record his hands-on device checks separately.
- **M-18** In v1: Instrument's Line-up 4-up with seven B sources; `Chart3D`/`SurfacePlot` kernel surfaces (phone performance UNVERIFIED); a `LabKitMetro` package dependency (`metro-adaptation.md` §E.5).

## 9. Open risks and UNVERIFIED items

| # | Item | Status | How to settle it |
|---|---|---|---|
| 1 | A17 Pro timings for every kernel (all window figures in §1.3 are MODELED from M1 Max × 5) | UNVERIFIED | Run log on his phone (G-19) |
| 2 | Brute bilateral at 894² misses 120 Hz (8–15 ms MODELED here) | UNVERIFIED | Device Run; the half-res preview covers it either way |
| 3 | Safe areas 59/34 pt and the rendered floating-glass height | UNVERIFIED (`metro-adaptation.md` §G.2 #2–3) | `GeometryReader` log and measured glass frame on device |
| 4 | Native glass sampling a scrolling `MTKView` | UNVERIFIED (§G.2 #1) | Device screenshot while scrolling; fall back to the `safeAreaInset` strip |
| 5 | `ImageRenderer` `.blur` equals the on-screen blur | UNVERIFIED (`live-calibration.md` §8) | Calibrate labels the path; `drawHierarchy` experiment |
| 6 | Stage-boundary counter sampling on the A17 Pro | UNVERIFIED (`sdk-feasibility.md` §17 #4) | Query `supportsCounterSampling` at runtime |
| 7 | Runtime specialization time for the traced pipeline on the A17 Pro | MEASURED on the M1 Max only (§3.1) | Measure on device; pre-warm the traced pipeline when Trace opens |
| 8 | Swift Charts performance with seven chart cards in one scroll | UNVERIFIED | Device scroll test with Instruments-free frame logging |
| 9 | Whether `fma()` makes traced and untraced builds bit-identical on Apple9 | Mac result in §3.1; device UNVERIFIED | Run the probe kernel through the app's debug menu on the phone |
