# Adversarial review: product, truth and Metro

Date: 14 October 2026. Reviewer lens: PRODUCT and TRUTH and METRO.

**Scope.** SPEC.md (1,473 lines) and ARCHITECTURE.md (4,511 lines, including Appendix A), both read in full. They were checked against BRIEF.md, HOLD-SIMULATOR.md, the Metro Station spec (sections 1, 7, 13, 14, 16 and 17), and the research files `metro-adaptation.md`, `live-calibration.md`, `gpu-pipeline.md` and `stack-semantics.md`.

**Method.** Every COMPUTED fixture in SPEC §5.3 A–D, §7.2 and §8.1 was re-derived by hand or with a short script in `$TMPDIR/blur2ool-review-product/` (`p3.py`, `star.py`). Text fit was estimated from 11-pt SF Mono at about 6.6 pt per character and 13-pt at about 7.8 pt. No simulator was used (the simulator hold is active), and no app build was needed.

**Severity.**
- **Blocker:** the app would show something false, or two acceptance fixtures contradict each other.
- **Major:** a clause of the brief is weakened, a Metro contract is broken, or a screen does not fit at 430 pt.
- **Minor:** a local error with a cheap fix.

Style nits are not reported.

## 0. Summary

Most of the arithmetic is right. I re-derived these by hand and they match:
- the Gaussian weights, the linear-sampling offsets (1.4766, 5.4149, 7.3849…) and the trace's Σ 0.399 after fetch 7;
- the 179/115 colour-space branch;
- the zoom tap geometry (762.0…732.0, 2.04 px, N ≥ 65, threadgroup (46, 27) thread (11, 15));
- the bilateral numbers (43.3 %, 9.4 %, 0.581, 0.513, thread (15, 12) of (27, 18));
- the hexagon numbers (665.1 px², 7.30 px, ⅓-weight rhombi, 0.1504 → 108/255, 0.55 %, 609 taps);
- every σ-hold conversion in §8.1;
- disc zeros, box/tent/box³/Laplace kurtosis, Gibbs 8.9 %, Lorentzian 1.3 %, USM 1.35.

The real problems are elsewhere:
1. **The app would lie in a few places.** The Tier S fingerprint card is built from our own Metal model. The SLIDE chip implies that SwiftUI `.blur` gives this Gaussian. The Gaussian is advertised as "H ≥ 0, never inverts" while the kernel the GPU runs has negative ripple. The half-resolution preview publishes LIVE values from a different computation.
2. **Several fixtures contradict each other or the spec's own rules.** These are the descent B star and zone-plate probes, the Compare rail's `=` at SLIDE/API, and the divergence reference rows.
3. **Accessibility and Metro gaps.** The provenance engraving disappears at accessibility sizes. Layers' vertical paging cannot hold growing content. A gesture-only "drive B" exists. Text frequently overflows the 298 to 406 pt columns.

Coverage of the brief is good. The weakest clause is "mathematical visualizer": approximation error is not a standard number, and there is no 2-D frequency view for non-separable blurs.

Counts: 3 blockers, 18 majors, 24 minors.

## 1. Coverage of the user ask

| Clause | Verdict | Where |
|---|---|---|
| Blur simulator (real pixels, GPU, live, adjustable) | Covered (Bench, 53 live glyphs, crowns, Steppers) | SPEC §4.1, §10 |
| Mathematical visualizer | **Partly.** No standard "approximation error vs the operator it imitates" number (BRIEF item 2 names it), and no 2-D H view for non-separable blurs. See C1. | §5.1, §5.2 |
| Every layer WYSIWYG → GPU, following one pixel | Covered (seven floors, Trace with TRACE_PROBE records). The WYSIWYG floor is a static table; see C2. | §5, §6 |
| What makes each blur unique | Covered (fingerprint card, UNIQUE, PARTS WAYS, lessons). The Gaussian's UNIQUE number is not unique; see T14. | §7, §8 |
| Gaussian, box, radial, "dozens" | Covered: 62 entries. "Radial" is satisfied by `radial-zoom-blur` + `spin-blur` (Photoshop's Radial Blur has both modes). | §10.1 |
| SwiftUI app | Covered | ARCH §2 |
| Metro design | Covered in grammar; violations listed in §5 | §4, §14 |

**C1 (major) — The mathematical visualizer omits approximation error and 2-D response.** (SPEC §5.1 floors 3–4, §5.2 "2-D gather" and "skew-separable" rows.)
- *Problem.*
  - BRIEF requirement 2 lists "approximation error". In SPEC it appears only inside lessons (P3, §17 item 16), never as a floor number.
  - For non-separable or anisotropic blurs, the MATH floor shows only "a 2-D H slice along a chosen axis". The hexagon claim "six slow-decaying spokes, not circular zeros" (§5.3 D floor 3) cannot be seen in a 1-D slice. The same holds for Kawase's diagonal anisotropy and motion's zero lines.
- *Fix.*
  - Add a fixed KERNEL-floor slot `ERROR VS <reference operator>` with its definition, for every entry that approximates another: box³, Kawase, dual Kawase, pyramids, IIR, linear-sampled, binomial, stochastic. Example: "max |PSF − Gaussian| / peak, equal σ, COMPUTED".
  - Add a signed 2-D H heat map (`HeatmapSpec.signed = true`, already in the contract) as the MATH figure for every entry whose `separability` is not `.separable`. Keep the 1-D slice in details.

**C2 (minor) — The WYSIWYG floor is a table, not something you operate.** (SPEC §5.1 floor 1.)
- *Problem.* The brief's top layer is "the designer's slider", but floor 1 is read-only bars. The reverse mode ("you typed 10") is the WYSIWYG idea, and it is buried as a toggle.
- *Fix.* Make the floor-1 figure an input. A Stepper "YOU TYPE · 10 in [tool ▾]" sets the Bench's primary through that tool's convention, with the convention's badge. The bars then show what every other tool needs for the same pixels. Use plain Metro chrome only: no tool trade dress, per the impersonation rule.

## 2. Truth: places the app would lie or overclaim

**T1 (blocker) — The Tier S fingerprint card is computed from our own Metal model.** (SPEC §7.1 items 3, 10, 11; §7.4; ARCH `RenderCoordinator.renderStrip`, `ShapeService`.)
- *Problem.* The PSF/STAR/EDGE strip is "rendered by the GPU through the running variant" (LIVE), and ON THIS PHONE / LOOKS MOST LIKE come from `ShapeService` on Metal output. For `swiftui-layer-blur`, `apple-uiblureffect` and `liquid-glass`, the running Metal variant is *our model*. So a card titled "SwiftUI `.blur(radius:)`" would show our Gaussian/box³ as LIVE. That is exactly the "SwiftUI layer that is really our own Gaussian" failure.
  - LOOKS MOST LIKE is meant to settle "box³ or truncated Gaussian?" without taking sides. If it is computed from the model we chose, the answer is circular.
- *Fix.*
  - For Tier S, render the strip by `ImageRenderer` on the real modifier, using the same 128² inputs. Badge it `MEASURED · OFFSCREEN` with the device stamp. Feed ON THIS PHONE and LOOKS MOST LIKE from the `CalibrationResult` (the `PSFFit` vector), never from `ShapeService`.
  - Before a calibration exists, show the strip as `NOT YET MEASURED` (engraved), not as model output.
  - Add a test: for `tier == .system`, no card field may carry `.live` provenance.

**T2 (major) — The SLIDE chip implies SwiftUI gives this Gaussian, and the badge loses its path.** (SPEC §4.1.4 chip 1, §5.1 floor 1, §13.4 first row; ARCH §5.1 qualifiers; research CAL §5.1 item 7, §8.)
- *Problem.*
  - The first-viewport chip reads `4.4pt` for "what his home tool would need typed for this blur". SwiftUI's kernel above about 5 px is not a Gaussian, so the typed value matches σ only, not the blur. The shape reading is itself contested (box³ vs truncated Gaussian, SPEC §13.3).
  - After calibration the chip turns MEASURED, but the measurement is offscreen `ImageRenderer.cgImage`. The two ImageRenderer paths already differ by 9 % in σ, and whether either matches the screen is UNVERIFIED (CAL §8).
  - A 9-pt glyph-only badge cannot carry `.offscreen`. SPEC §16 itself forbids "on-screen SwiftUI blur labelled MEASURED".
- *Fix.*
  - Show the chip as `≈4.4pt` and speak "sigma-matched; SwiftUI's kernel shape differs".
  - Give floor 1 a `SAME σ, DIFFERENT KERNEL` caption on every tool row whose kernel family differs from the current blur's.
  - Make the upgraded value carry `.offscreen` everywhere: a small `OFF` mark on the chip, "measured offscreen on this iPhone" in VoiceOver, and the `OFFSCREEN` caption on floors 1–2.
  - Add an `honestyViolations` rule: any value derived from a SwiftUI `CalibrationLaw` must carry `.offscreen` or `.experimental`.

**T3 (major) — The Gaussian is advertised as never inverting, while the kernel the GPU runs does invert.** (SPEC §4.1.8 compact card "H > 0 everywhere"; §7.1 RESPONSE row "never negative", chips `H ≥ 0`; §4.2 status `MIN H A > 0`; §8.4 box row "> 0"; P1, P2 "> 0".)
- *Problem.* §7.1 item 3 says the H glyph is COMPUTED "from the discrete kernel". SPEC's own Kernel floor fixture prints `MIN H (ripple) −0.0012` at σ 12, k = 3, and §5.3 A prints −0.0010 at σ 4. The truncation options 2 and 2.5 × σ go further negative. The card and the Compare status row therefore contradict the plot drawn next to them, and the app's claim of exact honesty.
- *Fix.* Every "H > 0" for an LSI blur must state its domain: `CONTINUOUS H > 0 · AS RUN (k 3) MIN H −0.0012`. Keep the property chip `H ≥ 0` for the continuous operator and add a `· TRUNCATED: RIPPLE` chip when the discrete minimum is below 0. In Compare, `MIN H` must come from the discrete kernels both slots actually run.

**T4 (major) — The half-resolution preview publishes LIVE values from a different computation, and is undefined.** (SPEC §4.1.6; ARCH `RenderQuality.half`, `OperatorRequest.size` 447, §5.9 render loop, `BenchModel.acknowledged`.)
- *Problem.* Nothing says how the 447² input is made. If it is area-averaged, that is itself a box blur (SPEC §11 photo row admits exactly this). Nothing says whether pixel-unit parameters (σ, R, L, r, a, window radius, PDE time t → σ²) are halved. Nothing says how the probe maps to the half grid.
  - Rank filters (median 3 × 3), Kuwahara and the bilateral grid change character at half size.
  - The zone plate and 1-px checkerboard alias violently under a nearest ×2 upscale, which can be mistaken for blur artifacts.
  - Because `acknowledged[slot]` is "the newest completed Run" of either quality, the PIXEL chip, loupe and pills would show LIVE values from the preview.
- *Fix.*
  - Specify it. Downsample by point sampling at even texels (no extra blur), scale every pixel-unit parameter by ½ (time by ¼), and map the probe to ⌊p/2⌋.
  - Never publish PIXEL, loupe, pills, telemetry or Trace from a `.half` Run. Those keep the last full Run's values and append `· HELD` while `PREVIEW ½` is engraved.
  - Exempt rank, selection and adaptive-grid classes from half-resolution preview, or engrave `PREVIEW ½ · RANK WINDOW SCALED`.

**T5 (major) — "These are the exact numbers the GPU receives" is false for the default variant.** (SPEC §4.3 Kernel floor `IN THIS APP`; ARCH `B2_BUF_WEIGHTS` comment.)
- *Problem.* The Bench default is `gaussian-linear-sampling`. That GPU receives 37 merged (offset, weight) pairs per pass, not the 73 stems drawn. The hardware then splits each pair with 8-bit sub-texel fractions (MEASURED rule, ARCH §4.3), so the effective taps differ from the stems.
- *Fix.* For merged-tap variants, generate the line from data: "The GPU receives 37 pair weights and offsets (Algorithm floor). The hardware's 8-bit interpolation makes the effective taps differ from these stems by ≤ x (MODELED)." Print the pair table in details and the effective-tap difference as a number.

**T6 (major) — σ-hold silently fails for hero-dozen blurs at the default σ 12.** (SPEC §2 6–8 s, §4.1.2, §8.1, §9.4 ranges.)
- *Problem.* The promise is "the size stays". From σ 12:
  - `bilateral`: σs = 12 exceeds its 0.5–8.0 range.
  - `frosted-glass-noise`: a = round((√1729 − 1)/2) = 20 exceeds its 1–16 range, so the achieved σ is 9.52.
  - `guided`: r = 21 exceeds 1–10.
  - `kawase-blur`: the presets cannot reach 12.
  
  Only binomial's refusal is specified. Two of these (bilateral, frosted glass) are in the hero dozen, so the first-session experiment quietly changes size.
- *Fix.* `holdingSigma` must return the clamped, achieved σ and a status line `σ HELD 12.0 px → σs 8.0 (MAX) · Δσ −4.0 px`. This is Metro §16 "Domain limit: show the valid boundary". Add one unit test per entry at σ = 12 and σ = 64 asserting either "held within ±0.5 px" or a domain-limit line.

**T7 (major) — The Tier S PIXEL chip is not the probe's pixel.** (SPEC §4.1.9 f: "PIXEL (`OFFSCREEN` value from the last `ImageRenderer` fit when available)".)
- *Problem.* The calibration fit renders a step or impulse, not the specimen at the probe. Showing a value from it on the PIXEL floor misreports what the probe pixel is.
- *Fix.* Render the same SwiftUI view (specimen, radius, scale) with `ImageRenderer` and read the probe texel, badged `MEASURED · OFFSCREEN`. Otherwise show `—` with the spoken reason "the on-screen system blur cannot be read back".

**T8 (minor) — LIVE · CPU contradicts the CPU-never-LIVE rule.** (SPEC §12.1 LIVE row and ARCH `Qualifiers.cpu` vs SPEC §6.4 rule 6, "A value recomputed on the CPU is never labelled LIVE".)
- *Fix.* Pick one. Keep `LIVE · CPU` only for values computed from the current image that have no GPU counterpart (adaptive weight maps), and change §6.4 rule 6 to say "a CPU *re-computation of a GPU value* is never LIVE".

**T9 (minor) — The lens note overstates where numbers come from.** (SPEC §12.5: "every number is read back from Metal textures, not from screen pixels".)
- *Problem.* This is false for Tier S, Calibrate and the Apple twins: their readback is CGImage, CIContext or vImage.
- *Fix.* Say "read back from Metal textures or offscreen renders, never from the screen".

**T10 (minor) — The user cannot be the evidence that upgrades a label.** (SPEC §13.3 PATH menu, "labelled `ON-SCREEN · EXPERIMENTAL` until he confirms them".)
- *Fix.* Define an objective check, such as a render-server-only effect that `drawHierarchy` must capture. Until it passes, the label stays EXPERIMENTAL.

**T11 (minor) — While `CALayer.shadowRadius` sources disagree, the drop-shadow image still renders one of them.** (SPEC §9.4 `drop-shadow` CONVENTION menu, P27.)
- *Problem.* The image presents one source's law as what CALayer does.
- *Fix.* While `SOURCES DISAGREE`, render both laws in a Wipe, or engrave `MODELED · σ = r/2 (ONE OF TWO SOURCES)`.

**T12 (minor) — GPU milliseconds have no stated scope.** (SPEC §4.1.4 GPU chip, §4.1.8; ARCH §5.7 `TimingSummary`.)
- *Problem.* Nothing says whether the median includes the window-copy blit and the colour pre/post passes (present in sRGB-encoded and straight-alpha modes). Switching COLOUR SPACE would then change the "blur" time.
- *Fix.* Time blur passes only. Report pre/post and copy as `+ x ms OVERHEAD` in the Silicon tab, and say so in the GPU chip's spoken value.

## 3. Math and terminology errors

**T13 (blocker) — The descent B fixtures depend on an unstated centre and angle convention, and contradict each other.** (SPEC §5.3 B floor 7; §11 rows 2–3; ARCH §5.6 "centre is c = (⌊N/2⌋, ⌊N/2⌋)", §5.1 "pixel centre (x + 0.5, y + 0.5)".)
- *Problem.* Checked with `star.py`.
  - The star probe (747, 447) lies on θ = 0, which is *exactly a spoke boundary* of `sin(36θ) ≥ 0`.
    - With c at pixel centre (447.5, 447.5), the 4 × 4-supersampled probe reads **0.5**, not 1.000.
    - With c = (447.0, 447.0), it reads 1.0 with y down but **0.0** with y up.
  - The zone-plate fixture IN 0.082 is reproduced only with c ≈ 447.5 (0.078 point-sampled; 0.372 with c = 447.0), and that convention makes the star fixture 0.5.
  - So no single convention satisfies both rows of the same fixture. FAM-F5A's acceptance cannot pass honestly.
  - The star's default probe (412, 287), "on a spoke edge", is actually 6.3–6.7 px from the nearest edge (mid-wedge) under every convention.
- *Fix.*
  - State in §11 rule 2: c is the continuous point (N/2, N/2) or the centre of pixel ⌊N/2⌋, and θ is measured counter-clockwise with y up (or another explicit choice).
  - Move the descent B probe to a mid-wedge pixel (θ = 2.5°: r = 300 gives an offset of about 13 px off-axis) and recompute both IN/OUT pairs.
  - Pick the star's default probe on an edge under the stated convention.
  - Add a TESTIMAGES test that asserts the probe's IN value.

**T14 (minor) — The Gaussian's UNIQUE number does not identify it.** (SPEC §7.1 UNIQUE row, §7.2 `gaussian-blur`.)
- *Problem.* "excess kurtosis 0: the only kernel both separable and isotropic". Zero excess kurtosis does not single out a Gaussian; many profiles have it. The unique property (Herschel–Maxwell) is separability *with* isotropy.
- *Fix.* UNIQUE = `kurtosis on axis = kurtosis at 45° = 0 while separable` (both are already in the fingerprint vector), with the derivation link.

**T15 (minor) — Wrong quantity in the heat-equation note.** (SPEC §5.2 Iterative PDE row: "step response (non-negative only for λ ≤ ⅛)".)
- *Problem.* The 5-point kernel has weights 1 − 4λ and λ, so it is non-negative, and its step response is monotone, for λ ≤ ¼. The ⅛ bound is for the *frequency response* (H(π, π) = 1 − 8λ ≥ 0), as §17 item 1 correctly says.
- *Fix.* Change the text to "H ≥ 0 only for λ ≤ ⅛; kernel non-negative up to ¼".

**T16 (major) — P25's "Wiener" number is the inverse filter, and the app cannot produce it.** (SPEC P25, ARCH §8.2 F4 fixture "Wiener gain 139 at Nyquist for σ 1".)
- *Problem.* At σ 1, H(0.5) = e^(−π²/2) = 0.00719, so 1/H = 139 is the **inverse filter** (K = 0). Wiener gain is H/(H² + K):
  - 0.72 at the app's default K = 10⁻²;
  - 47 at the range minimum 10⁻⁴.
  
  So 139 cannot be produced with the app's controls. "Wiener fails at box and disc zeros" is also the inverse filter's failure; Wiener's gain goes to 0 there.
- *Fix.* Say "inverse filter (K = 0): gain 139; Wiener at K = 10⁻²: 0.72". Either add K = 0 as an `Inverse` choice, or drop 139 from the fixtures.

**T17 (minor) — The P3 and P21 numbers are not reproducible as written.** (SPEC P3 "shape error 36 % → 8.5 % → 6.7 % → 3.7 %"; P21 "−0.216 at 1.39 periods".)
- *Problem.*
  - P3 gives no definition, which violates SPEC's own §17 item 16. Under the obvious continuous definitions, `p3.py` gives:
    - max |f − g|/peak: 50 / 7.8 / 6.0 / 3.5 %;
    - relative L2: 38 / 8.8 / 4.8 / 3.4 %.
    
    Neither matches.
  - For P21, the continuous sinc minimum is −0.2172 at 1.430 periods.
- *Fix.* State the definition and discretisation with each number, recompute it in a `BlurCore` test, and mark it UNVERIFIED until that test exists.

**T18 (minor) — Two OpenCV bilateral mismatches.** (SPEC §5.3 C floor 1: OpenCV `bilateralFilter(d 17, sigmaColor 25.5, sigmaSpace 3)` badged REFERENCE as the equivalent.)
- *Problem.*
  1. OpenCV runs on whatever 8-bit values it gets (normally sRGB-encoded), while the fixture's σr = 0.10 is in linear light. The spec's own floor 2 row says σr "acts in whatever space the numbers are in".
  2. For 3-channel input, OpenCV's range distance is the L1 sum over channels, not luma, so a grey step of Δ gives a distance of 3Δ.
- *Fix.* Badge the row "same parameters, different range metric (L1 RGB, encoded): not the same pixels", or give the matching OpenCV call (single-channel, linear float input).

**T19 (minor) — Two example values are off.** (SPEC §4.1.3 loupe example; §4.1.4 PIXEL chip.)
- *Problem.*
  - `0.0885 lin · 83/255`: 0.0885 encodes to 83.93, which is **84**.
  - The PIXEL chip is specified as "3 significant digits" but shows `0.089`, which is 2. The loupe shows 0.0885 for the same pixel.
- *Fix.* Fix the examples, since agents copy wireframe strings into tests, and use one precision for the probe value everywhere.

**T20 (minor) — MASS CUT shows the wrong quantity.** (SPEC §4.3, §5.1 floor 4; ARCH §14 (c).)
- *Problem.* The floor asks "what did the finite kernel cost?", but the value is the continuous 1-D tail (0.27 %). The kernel actually dropped 0.235 % per axis (ARCH §14 c) and about 0.54 % of a light's energy in 2-D.
- *Fix.* Print `MASS CUT 0.235 % PER AXIS (0.47 % 2-D)` from the discrete kernel, with the continuous 0.27 % in details.

## 4. Unlabeled claims about Apple / Figma / Adobe internals

**A1 (major) — Contested and inferred claims about Apple's blurs are printed without the right label.**
- *Problem.*
  - "box³-like" appears as MEASURED or unlabelled in four places: §5.1 floor 6 INFERRED-lane text ("box³-like, MEASURED macOS"); §10.1 row 3 (unlabelled); P26 look-for; §13.1 SwiftUI `.shadow` row. Yet §13.3 says "the shape interpretation stays INFERRED", and SDK §4 fits a truncated Gaussian equally well.
  - §8.4's CSS-vs-SwiftUI row says "both gamma-space". For SwiftUI on screen that is INFERRED (§17 item 9).
  - §11 row 16 states "materials are mostly colour stages" as what the test image *reveals*, and P28 attaches a single label triple to three claims.
- *Fix.*
  - Replace "box³-like" with "kurtosis −0.45 (MEASURED macOS); closest model box³ (INFERRED)" everywhere.
  - Write "CSS gamma-space (REFERENCE); SwiftUI gamma-space offscreen (MEASURED), on screen INFERRED".
  - Label the materials claim INFERRED in §11 and per claim in P28.

**A2 (minor) — The internals lane does not say its names come from a different OS.** (SPEC §5.1 floor 6 Tier S lane, §13.3.)
- *Problem.* The QuartzCore kernel names were read from the iOS **26.5 Simulator** runtime and macOS 27.2. The iOS 27 runtime was not mounted (GPU research source 33). The lane shows them on an iOS 27 device.
- *Fix.* Engrave `NAMES FROM iOS 26.5 SIMULATOR / macOS 27.2 · NOT RE-READ FOR iOS 27 · NOT OBSERVED RUNNING`.

**A3 (minor) — The model's structure is itself inferred.** (SPEC §4.1.9 g Liquid Glass reconstruction.)
- *Problem.* The model's structure (downsample → Gaussian → colour stage → SDF refraction) is inferred from kernel names. Only its parameters are modelled.
- *Fix.* Label the exhibit's right half `MODELED · STRUCTURE INFERRED`.

## 5. Metro contract violations

**M1 (major) — At accessibility sizes the provenance engraving disappears.** (SPEC §4.1.10 "caption row … hidden" at AX1–AX5; Metro §17 Dynamic Type, "remove decorative metadata before shrinking essential values".)
- *Problem.* The caption row holds the image's provenance (`LIVE · METAL`, `SYSTEM · ON SCREEN · NOT READ BACK`, `MODELED · METAL`, `INFERRED · NATIVE GLASS`, `PREVIEW ½`, `TRACED BUILD`). That is essential metadata, not decoration. At AX sizes the Tier S wipe and the Liquid Glass exhibit would show system and model halves with no label.
- *Fix.* At AX sizes move the provenance into the native text block below the housing (first line, full Dynamic Type), and make it part of the image element's VoiceOver value.

**M2 (major) — Layers' vertical paging cannot hold growing content.** (SPEC §4.3 "One vertical paging ScrollView … overflow lives in `All … details` (the only element that grows)"; §14 "floor pages grow"; Metro §1 contract 8.)
- *Problem.* With `.scrollTargetBehavior(.paging)`, a page is one viewport tall. Expanding `All … details`, or any page at AX sizes (six rows + a 140-pt plot + rule + question in about 600 pt below the periscope), makes content taller than the page. It then needs a nested same-axis scroll view, which fights the pager, or it becomes unreachable.
- *Fix.* Use a plain vertical `ScrollView` with one section per floor, `scrollPosition(id:)` snapping to section tops, and the floor rail as the jump control. Alternatively, open `All … details` as a pushed page inside Layers. Specify which.

**M3 (major) — Several fixed-size texts do not scale with Dynamic Type.** (SPEC §4.1.3 status row "fixed 14 pt … never grows", caption 11 pt, rail values 13 pt and badges 9 pt; Metro §17 "scale useful text".)
- *Problem.* Below AX1 (xLarge to xxxLarge), the σ-hold notice, sampling warnings and provenance stay at 11 pt, and the honesty glyphs at 9 pt.
- *Fix.* Use `@ScaledMetric` for these, with a cap and the truncation order. Raise the chip badge to at least 11 pt. Add a chip-level redundant cue for INFERRED (a dashed chip border) so the most important honesty signal in the first viewport is not the least legible element.

**M4 (minor) — Requested vs acknowledged ownership is not declared for the kernel-well face and the ±3σ ruler bracket.** (SPEC §4.1.3; Metro §7: "evidence of output must follow the authoritative rendered state".)
- *Problem.* These describe the kernel that ran, so they must follow the acknowledged Run.
- *Fix.* Add both to the §3 state model: acknowledged.

**M5 (minor) — Departures from the Metro adaptation research are not recorded.** (SPEC §4.1.3 image touch ownership; METRO §C.1.)
- *Problem.* The research advised against owning touches on the whole 298-pt specimen, and recommended an always-visible `SCALE 1 px = 0.33 pt` engraving because SLIDE is in points while API is in pixels. SPEC takes the opposite touch decision (D1) without citing C.1, and has no scale engraving.
- *Fix.* Add the scale engraving to the ruler margin, and cite METRO C.1 in D1 as the reversed advice.

**M6 (minor) — Layers floor rail breaks the screen inset.** (SPEC §4.3 floor rail at x 400–424.)
- *Problem.* The rail ends 6 pt from the screen edge, inside Metro's 12-pt inset, and its panel width (12–394) departs from the 406-pt column.
- *Fix.* See X4: overlay the rail inside the column.

## 6. Accessibility gaps

**X1 (major) — "Driving B" is gesture-only, hidden and too small.** (SPEC §8.2 "A long press on the B engraving in the caption row switches the crowns to B", also §4.2.)
- *Problem.* It is a hidden long press on 11-pt text in a 24-pt margin. That is below the 44-pt target, has no visible affordance, and has no non-gesture twin (Metro A.18).
- *Fix.* Add a segmented `DRIVE  A · B` control in the compare bar's B menu or in the Parameters panel, plus an accessibility action on the image.

**X2 (major) — There is no non-visual equivalent of the core lesson, "the shape changed, the size stayed".** (SPEC §2 6–8 s, §4.1.2, §14.)
- *Problem.* On switching blurs, VoiceOver gets the 2-s status notice at best. Nothing tells a non-sighted user how the new blur looks different.
- *Fix.* On each switch, post one announcement: "<name>. Sigma held at 12.0 pixels (radius 26.3). Point spread: <PSF SHAPE row>. Response: <RESPONSE row>." Keep the σ-hold line in the readout's accessibility value until the next change, since a 2-s visual notice is a timing barrier.

**X3 (minor) — Trace Play floods VoiceOver.** (SPEC §6.6, Play at 250 ms with per-sub-step announcements.)
- *Problem.* Metro §17 says "Do not announce every animation frame".
- *Fix.* Under VoiceOver, Play announces per floor only (or pauses), and the card's value answers queries.

**X4 (minor) — Touch targets below 44 pt.**
- *Problem.*
  - Layers floor-rail stops are 24 pt wide (§4.3). That contradicts §14 "All targets ≥ 44 × 44" and breaks the inset (M6).
  - Kawase deck E event tiles shrink below 44 pt for the `17-pass` preset, and that preset contradicts PASSES 1–8 (§9.4).
- *Fix.* Make the rail 44 pt wide, overlaid inside the column. Cap the sequence at 8 tiles or let the tiles scroll horizontally, and reconcile the PASSES range with the presets.

**X5 (minor) — The Catalog Fingerprints matrix has no accessibility-size layout.** (SPEC §4.5.)
- *Problem.* It is a fixed-width 9-column `Grid` with no AX layout.
- *Fix.* At AX sizes, switch to one card per row with the eight properties as a vertical list (the spoken form already exists).

## 7. Density at 430 pt

**D1 (major) — Specified strings overflow their columns at 430 pt.** (11-pt mono ≈ 6.6 pt per character.)

| Where | String | Needs | Has |
|---|---|---|---|
| §4.1.9 f caption, Tier S | `SYSTEM · ON SCREEN · NOT READ BACK` + `MODELED · METAL` (both "never truncated") | ≈ 317 pt | 298 |
| §4.2 compare caption | `B · BOX r 20 (σ 11.83)   A · GAUSSIAN σ 12.0` | ≈ 317 pt | 298 |
| §4.3 periscope line | `PROBE (447, 455) · IN 0.020 → OUT 0.089 lin ●` | ≈ 297 pt | ≈ 274 |
| §4.3 Silicon | `BYTES 25.6 MB ≈ MODELED · FLOOR 0.50 ms ≈ (51.2 GB/s UNVERIFIED)` | ≈ 422 pt | ≈ 350 |
| §6.2 Trace phase line | `Step 10 / 15 · fragment (446, 300) · pass 1 of 2 · horizontal` | ≈ 409 pt | 374 |
| §4.4 fetch row | `fetch 7: sample(uv − 5.4149 texel) → w 0.07818 · v 0.000` | ≈ 376 pt | ≈ 342 |
| §7.1 ON THIS PHONE row | `σ 11.86 · kurt 0.00/0.00 · shift 0.00 px · 0.8 ms/MP ⏱` (four MEASURED numbers sharing one badge) | ≈ 450 pt | 374 |
| §7.1 six rows, §4.8 | badge words already abbreviated in the wireframes (`= COMP.`, `▤ REF.`, `⏱ MEAS.`), contradicting §12.1 "the word is primary" | — | — |
| §4.1.7 Compare primary | `Descend both from (447, 455)` | ≈ 260 pt with icon | ≈ 242 |

- *Fix.*
  - Give each two-provenance caption its own line, or move the second provenance into the half's engraving below the window.
  - Split the long rows into two-line `LabeledValue`s, one badge per number.
  - Shorten the Compare primary to `Descend A+B (447, 455)`.
  - Extend the CONTENT-VIEWS text-fit test (ARCH §11.3, default size only) to every engraving and status template at default and xxxLarge sizes, and to the 393 and 375-pt widths, where the rail chip shrinks to 49 and 47 pt (§4.1.10).

**D2 (major) — Catalog rows and the Divergence tab cannot fit one-line layouts in 406 pt.** (SPEC §4.5.)
- *Problem.*
  - Blurs rows put a 40-pt glyph, a semibold name, a cost chip, a tier chip (`TIER 1 · LIVE ✓`), capability chips and a signature on two lines. Names such as "Per-pixel (velocity-buffer) motion blur" or "Depth of field (circle of confusion)" leave no room for the chips.
  - Divergence rows are 44 pt tall with "one-line reason" text such as "same continuous operator (σ = √(2t)); explicit 5-point steps are a different discretisation…". That cannot be one line.
- *Fix.* Use a three-line row (name / chips / signature) with a minimum height of 72. Make Divergence rows two lines (floor + verdict / reason, wrapping) with no fixed height.

**D3 (minor) — Line-up's four styles do not fit in a 36-pt pill.** (SPEC §8.3 Line-up: "pills draw A solid, B dashed, C dotted, D dash-dot".)
- *Problem.* The pill interior is 26 pt wide. Four overlapping traces with dash patterns are unreadable there, and the FREQ negative region is about 5 pt wide at −0.217.
- *Fix.* In Line-up, pills show only the tapped quadrant's blur (solid) against A (dashed). The four-way comparison lives in the status row and the Divergence tab.

**D4 (minor) — The SLIDE chip has no short form for its two common non-numeric cases.** (SPEC §4.1.4.)
- *Problem.* When the home tool is Photoshop it must read UNVERIFIED (10 characters, over the 6-character limit). When no tool offers the blur, nothing is specified. Units are also inconsistent across chips (`4.4pt` carries one, `12.0` and `0.61` do not).
- *Fix.* Define `UNVER.` with a full spoken form, `—` with "not offered by <tool>", and units either on all chips or on none.

## 8. Other product issues

**P1 (blocker) — The Compare rail and the divergence reference rows contradict the divergence rules.** (SPEC §4.2 wireframe: rail `SLIDE =`, `API =`, first `≠` at MATH for Gaussian σ 12 vs box r 20; §8.4 keys; §8.4 reference rows; ARCH §8.2 ANALYSIS acceptance "the 16 reference rows".)
- *Problem.* By the stated keys:
  - Floor 2 compares "σ **or primary** in px". Box's primary is r 20 ≠ σ 12, so API differs.
  - Floor 1 compares the home tool's typed value. SwiftUI has no box blur, so SLIDE cannot be `=`.
  - The same applies to `gaussian-blur vs heat-equation` (σ vs t: API) and `CSS blur(10px) vs SwiftUI .blur(radius: 10)`. At scale 3 their σ is 30 vs about 27 device px, so they part at **API**, not MATH.
  
  ANALYSIS cannot satisfy both the keys and the fixture rows.
- *Fix.* Decide what floor 2 compares. My recommendation is "the API tuple **normalised to per-axis σ** plus colour, edges and alpha", stated in the key, so σ-held pairs read `=` there and part at MATH. Floor 1 must read `≠ · NOT IN <TOOL>` when either blur is absent from the home tool. Recompute the CSS-vs-SwiftUI row (API) and keep its MATH note as the second difference.

**P2 (major) — The first viewport may be mostly dark.** (SPEC §2 0.0 s and 6–8 s, §11 row 1.)
- *Problem.* At 0 EV the 1-px lights (I = 2–100) peak at I/(2π·12²) ≤ 0.11 linear (≤ 94/255) after the σ 12 Gaussian. The median 1-px light peaks at about 0.016 (≈ 35/255).
  - About 16 of 160 lights exceed 0.2 linear, all of them 3 × 3 lights.
  - After the hexagon switch (R 26.3, area ≈ 1,797 px²), about 9 lights exceed 0.2.
  
  So "every light is now a crisp hexagon" and "a beautiful blur" are unlikely: the after-half is a dim field with a few glows. These are estimates from the specified intensity distribution, not measured.
- *Fix.* Add a TESTIMAGES or ENGINE fixture: at the launch state, at least N lights have an output peak ≥ 0.25 linear in SDR. Meet it by raising Night City's light energies (specify them by blurred peak at σ 12) or by launching at +3 EV, as disc already does. Reword the 6–8 s line to "the bright lights become hexagons".

**P3 (major) — Plain-string numbers bypass the honesty check.** (ARCH binding rule 4 "Honesty is a compile-time concern"; §5.1 `honestyViolations`; Appendix A `StatusLine` (String cases), `ContentBlock.paragraph/equation/note/chips`, `CatalogEntry.signature`, `NearestMatch.distance: Double`, `LoupeReading.centreCode8: Int`.)
- *Problem.* SPEC §12.2 item 8 says "no number without a badge", but these unbadged numbers reach the screen as plain strings: the status row (`σ HELD 12.0 px → R 26.3 px`, `MIN H A > 0 · B −0.217`, `w 41 · σ 11.83 px`, Difference `MAX 6 LSB · RMS 0.8 LSB`, which §8.3 calls LIVE), the ruler bracket, signatures ("minimum response −0.217") and LOOKS MOST LIKE `Δ 0.00`. The test cannot see them.
- *Fix.*
  - Make `StatusLine` carry `[BadgedValue]` segments; the status row may then show glyph badges like the rail.
  - Give `NearestMatch` a `BadgedValue`.
  - Add a lint test: any digit in a plain `String` that reaches a view fails unless it is in an allow-list (coordinates in `Descend from`, equation constants).
  - State in §12.2 which plain-text numbers are exempt (equations) and why.

**P4 (minor) — The fingerprint strip breaks at large sizes.** (SPEC §7.1 item 3: "at the current (σ-held) size" on 128 × 128 inputs.)
- *Problem.* At σ ≥ 21 px (±3σ ≥ 64) the support exceeds the crop. The STAR and EDGE insets then show edge-mode artifacts that read as the blur's own character, and two cards no longer line up.
- *Fix.* Render the strip at the fingerprint reference size σ_equiv = 4 px (as §7.4 already does for the vector), engraved `AT σ 4 px`, or scale the input crop with the support.

**P5 (minor) — Internal inconsistencies to resolve before agents build from them.**
- §1 says "about 45 blurs live on the GPU", while §10.1 has 53 strip glyphs.
- The bilateral crowns are swapped between §4.1.9 (e) (FINE = SPACE σs, amber second = RANGE σr) and §9.4 (primary/FINE = RANGE σr, second = SPACE σs).
- Kawase PASSES 1–8 vs the `17-pass` preset (see X4).
- P19's numbers (255, 128, 128 vs 191, 128, 128) assume gamma-space compositing while the default is linear light (in linear light, 0.5 encodes to 188, not 128). Say "composited in encoded space" or recompute.

<!-- STATUS: COMPLETE -->
