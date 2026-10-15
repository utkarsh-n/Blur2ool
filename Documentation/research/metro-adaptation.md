# Metro Station → Blur2ool: adaptation research

Date: 13 October 2026. Author: research agent (metro-adaptation). Status: complete. The note was written over three attempts: §A–§C and §F.1–§F.2 came from the first two (interrupted) runs, and the third added §D, §E, §F.3–§F.5 and §G, and re-checked the cross-references.

**Deliverable map:**

- (a) Metro contracts that must hold → §A
- (b) Palette, typography and material tokens → §B
- (c) Component inventory mapped to the blur domain → §C. This covers the specimen, the kernel-well lens and the Liquid Glass irony, crowns vs Steppers, the KERNEL/FREQ pills, telemetry, pass tiles, the signal lab, the floating group, settings/explanations and the honesty badge.
- (d) iPhone 15 Pro Max layouts with point dimensions → §D
- (e) Starter copy-in plan and the shader-lookup caveats → §E
- (f) Adopter pitfalls → §F
- Open decisions and UNVERIFIED items → §G

Sources read: see §0.

## 0. Sources read

Metro Station skill (edition 1.0, extracted from Metro Station build 14, dated 2026-10-12), all at `/path/to/developer/Documents/AI Stuff/Metro Station/Skills/metro-station-design-system/`:

- `SKILL.md` (66 lines), `references/design-system-spec.md` (all 814 lines, §1–§22), `references/swiftui-integration.md`, `references/sea-glass.md`
- `assets/design-tokens.json` (563 lines), `assets/visual-reference.png` (viewed)
- `assets/swiftui-starter/`: `InstrumentDesignSystem.swift` (393), `InstrumentControlTouchBoundary.swift` (214), `LensRefraction.swift` (133), `InstrumentLensOptics.metal` (44), `UsageExample.swift` (145)
- `assets/sea-glass/Sources/MetroSeaGlass/SeaGlassSurface.swift` (skimmed: it is built on `.ultraThinMaterial`, i.e. a native backdrop blur)

Adopters (see §F and §C for what was taken from each): AssemblerToy, ClassicalMLSimulator, QuantumToy, LosAlamosSimulator, Toothpaste Toy `Documentation/REDESIGN.md`.

- **AssemblerToy:** `README.md`, `App/Views/*`, `App/DesignSystem/*` (diffed against the starter), `project.yml` + `project.pbxproj`, `Documentation/QA.md`, `Documentation/Ergonomics/audit.json`, screenshots.
- **ClassicalMLSimulator:** `README.md`, `App/Views/*`, `App/DesignSystem/MLTheme.swift`, `Documentation/StressTest.md`, `QA.md`, `Screenshots/*`.
- **QuantumToy:** `README.md`, `Documentation/Validation.md`, `App/Views/QubitLabView.swift`, `App/Views/QuantumComponents.swift`, `App/DesignSystem/*` (diffed), `Documentation/QA/QubitLab.jpg` (viewed).
- **LosAlamosSimulator:** `README.md`, `Documentation/Validation.md`, `App/Design/MetroComponents.swift`, `Documentation/QA/Trinity.jpg` and `Chain.png` (viewed).
- **Toothpaste Toy:** `Documentation/REDESIGN.md`, `progress-ui.md`, `progress-qa.md`, `progress-labkit-metro.md`. No Metro-era screenshots exist yet.
- **Also consulted:**
  - `AI Stuff/LabKit/README.md`, `Package.swift` and `Sources/LabKitMetro/` (file list, shader lookup).
  - The Metro Station source app's `App/Views/` and `Sources/MetronomeCore/` file inventory, for porting crowns and pills.
  - Blur2ool's sibling notes `sdk-feasibility.md` and `live-calibration.md`.
  - The `iPhone 15 Pro Max.simdevicetype` profile.
  - The WWDC25 session 219 page.

Spec section references below are written as **§n** and refer to `design-system-spec.md`.

## A. Metro contracts that MUST hold

These are the non-negotiables for Blur2ool. Each one cites where it comes from. Items 1–8 are the spec's own "Essential visual contracts" (§1); items 9–22 are contracts stated elsewhere in the spec, the skill, or the token manifest's `contract` block.

1. **Foreground is never filtered or transformed.** Values, units, semantic labels and control frames stay independent of sensor transforms and optical sampling (§1 contract 1, §7 layer diagram, `contract.readoutTransforms=false`). *Blur2ool consequence:* the σ readout, unit and labels must never sit inside the blurred image layer, the lens shader, or a `.blur()` modifier. The blur is content; the readout is foreground.
2. **Lens opacity constant; center fixed.** Glass opacity is constant (0.48 composite) across ordinary updates; the lens may change radius but its center never moves (§1 contract 2, §6 material table, §13 lens bounce).
3. **Light is a faint rim arc only.** A highlight follows a small part of the lens perimeter (76° arc, 0.9 pt stroke, peak white 0.085). No broad moving fill, no oval patches, no bloom on the face (§1 contract 3, §6 light recipe, `optics.faceHighlightFill=false`).
4. **Chromatic separation is subtle and diagonal-only.** At most ~1 pt red-to-blue at D = 322 pt, capped at 1.2 pt, zero at center, axes and rim (§1 contract 4, §14).
5. **Pill outlines are static.** Signal-pill enclosure, titles and frame never animate; only interior energy/geometry changes (§1 contract 5, §11, `contract.pillOutlineBeatAnimation=false`).
6. **Integers show whole digits; other quantities keep their legitimate precision and units** (§1 contract 6, §4 formatting contracts). *Blur2ool:* passes, taps, iterations, kernel size → integers; σ, radius in pt/px, GPU ms, error dB → fixed decimal policy per quantity, with units.
7. **Native held Stepper repeat and knob interaction keep working while the instrument redraws** (§1 contract 7, §9 behavioural contract). Keep Steppers/crowns *outside* any `TimelineView` and give them stable identity (§7 last paragraph, `contract.nativeHoldRepeat=true`).
8. **Content stays reachable above floating controls and at large text sizes** (§1 contract 8, §5 "bottom content reserve", §12 floating action group).
9. **Material roles are distinct:** near-black blue-green environment, quiet content panels, opaque precise metal, native Liquid Glass — glass only on controls and one isolated lens; charts and explanations stay calm (SKILL.md "Apply the system" bullet 1, §1 "Glass", §6).
10. **Color semantics:** cyan = continuous signal/control; amber = events/emphasis; violet/magenta = a distinct second signal family. Always pair color with position, text or shape (SKILL.md, §3 accents, §17 color differentiation). Amber already means "activity", so errors need text + symbol, not amber alone (§3).
11. **Color density:** most of the screen is dark; saturated color only on thin traces, small indicators, selected values and primary actions (§3 "Color density").
12. **Layer stack ownership** (bottom → top): environment+grid → opaque housing/recessed metal → decorative Canvas → Canvas-only refraction/chromatic sampling → centered native clear glass → faint rim reflection → unfiltered value/units/meaning → fixed interaction region (§7 first diagram).
13. **Requested vs acknowledged state are separate.** Each displayed quantity has an explicit owner; requested values may show immediately, but output-derived visuals follow the authoritative rendered state; reserve a constant-height status row for "applying" text (§7 ownership table, §16 "Applying"). *Blur2ool:* the Stepper shows requested σ instantly; the GPU-ms telemetry, the measured PSF and the rendered image describe the frame actually produced, and a fixed-height status row says `RENDERING…` while they differ.
14. **Shader only on decorative SwiftUI drawing**, one `layerEffect` combining warp + chroma, declared `maxSampleOffset` = maxShift + split/2, premultiplied alpha preserved, identity outside the lens, `#include <SwiftUI/SwiftUI.h>` (§7, §14 compositing requirements, SKILL.md "Implementation boundaries").
15. **Glass after sizing:** size the real label/hit surface first, then apply `.glassEffect`; group nearby glass in a deliberate `GlassEffectContainer` (§6, §18 "Native glass control", SKILL.md last bullet of "Apply the system").
16. **Touch ownership:** a touch that begins on a control belongs to it for the whole sequence; use `instrumentControlOwnsTouches` on the full framed bounds; the bridge only protects the *nearest* containing `UIScrollView` pan — nested scrolls and sheet dismissal need their own checks (§9, SKILL.md "Implementation boundaries", `contract.controlTouchOwnsWholeSequence=true`).
17. **Stepper writes the Binding before `onAcceptedChange`.** Treat the callback as a post-write notification; never publish the same domain change twice; clamped/unchanged values emit nothing (SKILL.md, §9, §18, swiftui-integration.md).
18. **Every gesture has a native/accessible alternative** (+/− buttons, Stepper, accessibility adjustable actions, named increments); feedback once per accepted change, density capped (crowns ≤ 20 events/s) (§8 interaction, §10, §15, §17 motor access).
19. **Three motion purposes stay independent:** domain motion, material response (tilt), interaction response. Tilt is never a domain-value edit (§13).
20. **Accessibility settings are part of the contract:** Reduce Motion freezes lens/sensor decoration and disables distortion/chroma/rim glide; Reduce Transparency restores full lens opacity and opaque panels; Increased Contrast strengthens borders; Dynamic Type reflows rather than shrinks; VoiceOver speaks label+value+unit+state and hides decorative paths (§17 table).
21. **Honest data semantics on plots:** axes have units; normalized plots say "normalized"; a synthesized model is never labeled as a measurement (§12 signal lab, §19, SKILL.md "Give physics, waveform and spectrum displays honest data/model semantics"). This lines up exactly with the Blur2ool LIVE/MEASURED/COMPUTED/MODELED/REFERENCE/INFERRED badges in `BRIEF.md`.
22. **Performance hygiene:** drawings consume prepared snapshots; expensive spectra/kernels computed off the main actor and cached by the parameters that change them; pause idle/inactive timelines; no state mutation or allocation-heavy work in a render closure; limit simultaneous native glass effects (§20 engineering constraints, §13 "Sampling and updates").
23. **Dark appearance only.** A light appearance requires its own palette and validation (§0 preamble, `portability.lightTheme`). Blur2ool is dark-only per BRIEF.md.

Validation reminder (SKILL.md "Validate the adopted result", §20): the source app's tests and the starter's compile checks do **not** certify Blur2ool. Blur2ool must check native glass rendering, held/edge touches during redraw, Dynamic Type, Reduce Motion/Transparency, Increased Contrast, and VoiceOver itself, and keep simulator results, installed-device observations and hands-on feel distinct.

## B. Tokens: palette, typography, materials, geometry, motion

All values from `assets/design-tokens.json` unless stated. RGB doubles are canonical (sRGB); hex is nearest 8-bit approximation (§2). `basis` = "current" means reproduces build 14; "recommended" means the consolidated value for a new app.

### B.1 Surfaces and ink (§3)

| Token | RGB (canonical) | Hex ≈ | Role | Blur2ool use |
|---|---|---|---|---|
| `surface.canvas` | 0.025, 0.042, 0.058 | `#060B0F` | App environment | Full-screen background |
| `surface.content` | 0.045, 0.070, 0.087 | `#0B1216` | Content panel (filled at 0.85) | Signal lab, explanations, catalog cards |
| `surface.gaugeHousing` | 0.027, 0.041, 0.055 | `#070A0E` | Opaque primary-object body | Specimen housing body |
| `surface.metalLight` | 0.055, 0.073, 0.090 | `#0E1317` | Upper lit metal | Housing gradient top-leading |
| `surface.metalDark` | 0.021, 0.032, 0.042 | `#05080B` | Recessed metal | Housing gradient bottom-trailing |
| `surface.pillLight` | 0.055, 0.069, 0.095 | `#0E1218` | Pill gradient leading stop | KERNEL/FREQ pill enclosure |
| `surface.pillDark` | 0.014, 0.022, 0.037 | `#040609` | Pill gradient trailing stop | KERNEL/FREQ pill enclosure |
| `surface.plot` | 0.022, 0.036, 0.047 | `#06090C` | Plot inset | PSF / MTF / error plots |
| `text.display` | 0.91, 0.95, 0.97 | `#E8F2F7` | Main numeral | Hero σ value |
| `text.secondary` | 0.60, 0.69, 0.73 | `#99B0BA` | Labels, context | Labels, axis captions |

White-opacity ink (§3): 0.68 dial metadata/units, 0.74–0.75 supporting axes/captions, 0.09 panel border, 0.025 background grid.

### B.2 Accents and signal families (§3)

| Token | RGB | Hex ≈ | Meaning in Metro | Proposed meaning in Blur2ool |
|---|---|---|---|---|
| `accent.actionCyan` | 0.34, 0.93, 0.96 | `#57EDF5` | Actions, selection, Stepper value | Selected blur, primary action idle, Stepper values |
| `accent.actionAmber` | 1.00, 0.74, 0.37 | `#FFBD5E` | Running primary action, events | "Trace a pixel" running, pass/event emphasis |
| `accent.instrumentCyan` | 0.32, 0.91, 0.96 | `#52E8F5` | Dial, crown, large waveform ink | Specimen calibration ticks, crown markings, human-meaning serif line |
| `accent.instrumentAmber` | 1.00, 0.72, 0.31 | `#FFB84F` | Dial index, crown, carrier ink | Specimen index marker, probe cross-hair, cutoff marker |
| `signal.wavePrimary` | 0.31, 0.86, 1.00 | `#4FDBFF` | Compact waveform trace | **KERNEL** pill trace (spatial PSF profile) |
| `signal.waveSecondary` | 0.21, 0.40, 1.00 | `#3666FF` | Waveform depth | KERNEL pill reference / discrete taps depth |
| `signal.spectrumPrimary` | 0.76, 0.57, 1.00 | `#C291FF` | Compact spectrum trace | **FREQ** pill trace (|H(f)| magnitude response) |
| `signal.spectrumSecondary` | 0.96, 0.36, 0.84 | `#F55CD6` | Spectrum depth | FREQ pill negative lobes / phase-flip regions |
| `signal.carrier` | 1.00, 0.73, 0.34 | `#FFBA57` | Frequency carrier marker | FREQ pill −3 dB / half-power cutoff marker |

### B.3 Crown metal (§6, §10; `metal.*`)

| Token | RGB | Hex ≈ |
|---|---|---|
| `metal.crownBase` | 0.12, 0.15, 0.17 | `#1F262B` |
| `metal.crownRimLight` | 0.49, 0.57, 0.61 | `#7D919C` |
| `metal.crownRimDark` | 0.10, 0.13, 0.15 | `#1A2126` |
| `metal.crownRimMid` | 0.32, 0.39, 0.43 | `#52636E` |
| `metal.crownFaceLight` | 0.27, 0.33, 0.37 | `#45545E` |
| `metal.crownFaceDark` | 0.08, 0.11, 0.13 | `#141C21` |

Note: the starter's `InstrumentPalette` does **not** include the metal/crown/pill/plot/housing colors; only canvas, content, the four action/instrument accents, two inks and five signal colors. Blur2ool must add the rest as named tokens in its own palette extension (§E.3). Adopters did not do this cleanly: AssemblerToy's `MetalHousing` (`App/Views/WorkbenchComponents.swift`) uses inline literals that drifted from the tokens (gradient 0.08/0.10/0.12 → 0.018/0.03/0.04 instead of `metalLight → metalDark`, shadow black 0.5 r15 y8 instead of 0.8 r22 y16, a 3-stop 1.5 pt rim instead of the 4-stop 1.4 pt rim), and ClassicalMLSimulator and LosAlamosSimulator re-declared their own small theme enums (`MLTheme`, `MetroTheme`). See §F.

### B.4 Typography (§4, `typography.*`)

All Apple system fonts; three designs with distinct jobs: **rounded** for live values, **monospaced** for labels/units/engineering, **serif italic** for the human meaning line.

| Role | Recipe | Blur2ool example |
|---|---|---|
| App title | 27 pt semibold rounded, 1 line, minScale 0.75 (`@ScaledMetric(relativeTo: .title)` in starter example) | `Blur2ool` |
| App subtitle | 9 pt medium mono, tracking 2.6 (recommend scalable 11–12 pt for new apps) | `BLUR SIMULATOR · WYSIWYG → GPU` |
| Hero numeral | 0.23·D light rounded, monospaced digits, width 0.64·D, minScale 0.7 (Blur2ool's band layout: 44 pt, §D.1) | `4.0` (requested σ, shown at the Stepper's 0.1 px precision) |
| Hero unit | ScaledMetric 11 pt rel. caption2, medium mono, tracking 2.2, white 0.68 | `SIGMA · PX` |
| Human meaning | subheadline, medium serif italic, instrument cyan | *Gaussian — separable, isotropic* or *Soft*, *Dreamy*, *Smeared* |
| Phase metadata | ScaledMetric 11 pt regular mono, monospaced digits | `PASS 2/2 · VERTICAL` |
| Stepper label | 10 pt medium mono tracking 1.5 (starter: scalable 11 pt) | `PASSES` |
| Stepper value | 18 pt medium rounded, monospaced digits (starter: scalable) | `3 passes` |
| Telemetry label | caption2 mono tracking 1.2 | `GPU` |
| Telemetry value | title3 mono, monospaced digits | `0.42` |
| Telemetry unit | caption2 mono, first-baseline aligned | `ms` |
| Pill title | ScaledMetric 10 pt semibold mono | `KERNEL`, `FREQ` |
| Pill axes | ScaledMetric 9 pt medium mono | `0`, `3σ`, `DC`, `NYQ` |
| Explanation title | largeTitle rounded semibold | `Gaussian blur` |
| Equation | callout mono | `G(x) = e^(−x²/2σ²) / (σ√2π)` |
| Prose | subheadline or body | explanations |

Recommended minimum caption: 11 pt scaled relative to caption2 (`typography.reuseCaptionMinimum`, basis recommended). Formatting contracts (§4): `.monospacedDigit()` on values that change in place; reserve value width and label height; magnitude and unit separated with first-baseline alignment; one fixed precision policy per quantity; displayed and spoken precision match; minimum-scale is a compact fallback, not an accessibility strategy; ALL-CAPS tracking only for short labels, sentence case for prose and errors.

### B.5 Materials and elevation (§6)

| Surface | Recipe |
|---|---|
| Environment | canvas fill + action-cyan radial wash at 0.085, center top-trailing, radii 5→620 pt + 28 pt grid, white 0.025, 0.5 pt stroke; ignores safe areas; accessibility-hidden; no hit testing. Starter drops the wash under Reduce Transparency. |
| Content panel | `surface.content` at 0.85 (1.0 under Reduce Transparency), corner radius 22, white 0.09 border at 1 pt (0.20 under Increased Contrast), padding 16 |
| Instrument housing | opaque blue-black metal, `metalLight→metalDark` gradient; black 0.8 shadow radius 22 y 16; 1.4 pt outer rim through white 0.36 → white 0.025 → black → white 0.15; recessed face inset 0.038·D with white 0.07 stroke at 0.6 pt |
| Native control glass | `.glassEffect(.regular.tint(accent.opacity(0.08)).interactive(), in: .circle)` on a 44×44 framed label |
| Native lens | `.glassEffect(.clear, in: .circle)` on a `Color.clear` frame of 0.76·D, opacity 0.48 (1.0 under Reduce Transparency), `scaleEffect` 0.92–1.09 about center |
| Plot inset | `surface.plot`, radius 10, white 0.075 border at 0.6 pt |
| Pill enclosure | leading→trailing gradient `pillLight→pillDark`; 0.8 pt capsule outline: primary 0.36 (0.70 Increased Contrast), white 0.10, secondary 0.38 |
| Crown | 62×62 metal face, 40 knurls, concentric grooves; shadow black 0.75 radius 6 y 5 resting, radius 3 y 2 pressed |
| Floating action group | native glass over the page, no black backing strip; `GlassEffectContainer(spacing: 14)`; `.buttonStyle(.glassProminent)` primary |

Opacity tokens (`opacity.*`): panelFill 0.85, panelBorder 0.09, grid 0.025, environmentWash 0.085, lensComposite 0.48 (1.0 RT), rimLightPeak 0.085, crownGlassTint 0.08, pillPrimaryBorder 0.36 (0.70 IC), pillSecondaryBorder 0.38.

Strokes (`strokes.*`, pt): panel 1, plot 0.6, grid 0.5, pill 0.8, housingRim 1.4, glassRimLight 0.9.

### B.6 Geometry (§5, `layout.*`, `gauge.*`)

- Spacing family (recommended): **4, 8, 12, 16, 24, 32**. Micro values 3, 5, 6, 7, 10 stay inside component recipes.
- Portrait screen inset 12 (subsidiary rows +10); header H 24 / top 10 / bottom 12; main stack spacing 12; content max width 540.
- Cluster: `clusterWidth = min(available, 490)`; `pillWidth = clusterWidth < 350 ? 30 : 36`; `D = min(360, clusterWidth − 2·pillWidth − 12)`; `pillHeight = min(218, 0.66·D)`; pill-to-object gap 6 each side. At 430 pt wide → D = 322 (spec §5).
- Control row max 380; Stepper min height 48, horizontal padding 14; secondary target 44×44; crown face 62×62; transport label min height 58 (Tap 62×58, primary flexible, settings 54×58; row spacing 12; container spacing 14; horizontal inset 22, bottom 12); bottom reserve 98 (source-specific: compute your own).
- Radii: panel 22, plot 10, event tile 8, pill capsule, controls circle/capsule.
- Gauge ratios: calibration radius 0.445·D, metal inset 0.038·D, lens diameter 0.76·D (lens radius 0.38·D), readout y 0.52·D, units y 0.665·D, meaning y 0.745·D (0.79·D at accessibility sizes), phase y 0.835·D, readout width 0.64·D. Rim scrub begins outside 0.30·D.

### B.7 Motion, optics, haptics (§10, §13–§15)

- Timeline requests: gauge/pills 60 Hz; telemetry 30 Hz; Reduce Motion 10 Hz with main motion effects off. Requests, not guarantees.
- Tilt: 30 Hz gravity; `target = clamp(1.7·(g − ref), −1, 1)` with visual X ← gravity.x, visual Y ← gravity.z (portrait only); low-pass α 0.18; enhancement `e = 2g/(1+|g|²)` after unit-disk clamp.
- Refraction: `maxShift = min(9.5, 0.025·D)` (8.05 pt at D=322); feather from r = 0.82; curvature 0.32; chroma window 0.52→0.82→1.0, angular weight sin²(2θ); total split `min(1.2, D/322)`; `maxSampleOffset = maxShift + split/2` (8.55 pt at D=322).
- Rim arc: radius 0.985·R, center angle −90° + 70°·e.x + 20°·e.y, span 76°, 0.9 pt, clear → white 0.085 → clear, constant peak.
- Lens bounce clamp 0.92–1.09 (starter clamps `radiusScale` to this range).
- Crowns: fine 8° detents, semantic 20°, reversal hysteresis 18% of detent, 7 pt center exclusion, ≤ 1 step per update, ≤ 20 events/s.
- Haptic detents (Core Haptics transient intensity/sharpness): fine up 0.78/0.95, fine down 0.82/0.20, semantic up 1.00/0.60, semantic down 1.00/0.05.

## C. Component inventory mapped to the blur domain

Principle (SKILL.md "Apply the system", §19 "Adoption sequence"): adopt the smallest useful set, in this order: palette, type and quiet panels; one primary object with a large stable value; direct controls with feedback; compact channels only where they carry independent information; bounded material response last.

### C.0 Inventory at a glance

| # | Metro component (spec §) | In the starter? | Blur2ool role | Verdict |
|---|---|---|---|---|
| 1 | Environment (§6) | `InstrumentDesignBackground` | App background on every screen and sheet | Adopt as is |
| 2 | Content panel (§6, §12) | `InstrumentContentPanel` | Signal lab, telemetry, layer panels, catalog cards, field guide | Adopt as is |
| 3 | Primary instrument (§8) | No (only `InstrumentLargeReadout` + `InstrumentLensSurface`) | **Specimen instrument**: metal housing around the live GPU image | Build (C.1) |
| 4 | Native clear lens + optics (§13–14) | `InstrumentLensSurface`, `LensRefraction`, `.metal` | **Kernel well**: fixed glass lens over the kernel's 2D footprint; plus a separate Liquid Glass exhibit | Adapt (C.2) |
| 5 | Large readout (§4, §8) | `InstrumentLargeReadout` (circular geometry) | Hero value of the blur's primary parameter (σ, radius, iterations…) | Adapt to a band layout (C.1) |
| 6 | Native Stepper (§9) | `InstrumentParameterStepper` (integer only) | Integer quantities; a decimal variant for σ as the native alternative to the crowns | Adopt + add decimal variant (C.3) |
| 7 | Tactile crowns (§10) | **No** | Fine σ/radius (8° detents) and semantic σ stops (20° detents); angle crown for directional blurs | Port (C.4) |
| 8 | Vertical signal pills (§11) | **No** | **KERNEL** (cyan) and **FREQ** (violet) flanking the specimen | Port (C.5) |
| 9 | Telemetry row (§12) | `InstrumentMetricReadout` | σ EFF · TAPS · GPU ms, each with an honesty badge | Adopt + badge (C.6) |
| 10 | Event/beat tiles (§12) | **No** | **Pass tiles**: one tile per GPU pass (H, V; ↓1 ↓2 ↑2 ↑1; …) | Build (C.7) |
| 11 | Signal lab panel (§12) | No | Kernel · Response · Error · Cost plots | Build (C.8) |
| 12 | Floating action group (§12) | Pattern only (`UsageExample`) | Compare · **Trace a pixel** · Layers | Build (C.9) |
| 13 | Settings and explanations (§12) | Pattern only | Field guide per blur, settings form, layer atlas, trace guide | Build (C.10–C.11) |
| 14 | Glass icon button (§18) | `InstrumentGlassIconButton` | Header buttons (field guide/settings), crown ± buttons | Adopt the hardened AssemblerToy copy (§F.1 item 4) |
| 15 | Touch bridge (§9) | `instrumentControlOwnsTouches` | Steppers, crowns, compare divider handle, pass tiles | Adopt; **not** on the whole specimen (C.1) |
| 16 | Honesty badge | Not in Metro | LIVE / MEASURED / COMPUTED / MODELED / REFERENCE / INFERRED on every number (BRIEF.md) | New component, built from Metro grammar (C.12) |
| — | Sea Glass (`references/sea-glass.md`) | Separate package | Not needed; optional experimental material | Skip |
| — | Metronome appendix (§21) | — | Domain-specific; nothing carries over | Skip |

### C.1 Primary object: the Specimen instrument

Spec §8 lists seven anatomical parts. Each maps to the blur domain:

| §8 part | Blur2ool |
|---|---|
| 1. Housing and inset face | Opaque rounded-rectangle metal housing (`metalLight → metalDark` gradient, 1.4 pt rim through white 0.36 → 0.025 → black → 0.15, shadow black 0.8 r22 y16), corner radius 30 (AssemblerToy's `MetalHousing` precedent; the spec gives no radius for a rectangular housing). Inset face 12 pt (≈ 0.038 × 322). |
| 2. Calibration marks, scale, index | Engraved pixel rulers along the top and left edges of the image window (minor tick every 8 px, major every 64 px, white 0.16 / 0.36 like the starter's calibration); an amber 3σ bracket on the top ruler showing the kernel's support at the current σ; a `SCALE 1 px = 0.33 pt` engraving (see the units note below). |
| 3. Mechanism tied to the domain | The **live blurred image** itself: an `MTKView` (Metal output, LIVE) sized to the window, not full screen (Toothpaste Toy's chamber-sized `MTKView` rendered about 3× fewer pixels; §F.5). |
| 4. Dominant numerical readout | The blur's **primary parameter**: σ for Gaussians, r for box/disc/median, iterations for Kawase, length for motion blur. Declared per blur in the catalog, never guessed from the UI. |
| 5. Units + human interpretation | Unit line `SIGMA · PX` (mono 11 pt, tracking 2.2, white 0.68). Serif italic meaning in instrument cyan, from named σ bands. These are illustrative names, not standards: *Sub-pixel* (< 0.5), *Anti-alias* (0.5–1.5), *Softened* (1.5–4), *Frosted* (4–12), *Backdrop* (12–32), *Fog* (> 32). |
| 6. Phase/state metadata | `13 TAPS · 2 PASSES · SEPARABLE`, or during a pass walk `PASS 2/2 · VERTICAL` (mono 11 pt, monospaced digits). |
| 7. Fixed interaction region + accessible actions | Tap on the image places the **probe** (amber crosshair) used by Trace. Accessible alternatives are an adjustable action (moves the probe ±1 px) and ±1 px arrow buttons in the Trace sheet. |

**Why a rectangle and not Metro's round gauge.** Blur results are judged on square pixel grids. The procedural specimens (Siemens star, zone plate, checkerboard, impulse grid) are square, and putting the hero numeral in the centre of the face, as Metro does at y 0.52D, would hide the very pixels being blurred. Spec §8 explicitly allows this: *"a new app with more complex values may replace the decorative gauge readout with a larger adjacent native text block"*. SKILL.md also lists "content view" as a valid primary object. AssemblerToy's rectangular `DisplayInstrumentView` (`AT-8 / LIVE OUTPUT`) and Los Alamos's `TRINITY / OBSERVATION 01` instrument are accepted precedents. A **round alternative** is the microscope eyepiece, which has a circular field stop. It keeps Metro's silhouette but crops corner pixels and pushes the readout outside the object. Offer it as a design option only if he asks for the round silhouette.

**Readout placement.** A readout band inside the housing, below the image window, with the hero value on the left and the kernel well (C.2) on the right. The band is foreground. It is never under a shader, a material or `.blur` (contract A.1).

**Specimen rule (new, Blur2ool-specific, follows from contracts A.1 and A.21).** No native glass, `Material`, `.blur()` or optical shader may overlap the image window or a plot while it represents a measurement. A blur app must never contaminate the pixels it is demonstrating. The one exception is the Liquid Glass exhibit in C.2, where the glass is the subject and is labelled INFERRED. When the page scrolls under the floating glass group, the on-screen specimen is momentarily seen through glass. That is harmless because every measurement is read back from the Metal texture, not from screen pixels. Say this in the field guide.

**Units note.** Spec §2 says points are not pixels. If the specimen texture equals the drawable (298 pt × 3 = 894 px on the 15 Pro Max), then "px" means a device pixel, 1 px = 0.33 pt. SwiftUI's `.blur(radius:)` is specified in points, so the API layer must show the ×3 conversion. This is a recommendation; the engineering phase may pick another texture size, but the scale engraving must always state it.

**Touch.** Do **not** put `instrumentControlOwnsTouches` on the whole 298-pt specimen. It would take scroll ownership away from roughly a third of the screen. Use a `SpatialTapGesture`, because taps do not compete with scroll pans. Reserve the touch bridge for small controls: the compare divider handle (44 pt wide), Steppers, crowns and tiles. AssemblerToy did mark its `PixelMatrix` as touch-owning, but that matrix is only 176 pt.

### C.2 The isolated native clear lens: "kernel well", and the Liquid Glass irony

**What Metro requires** (§1 contracts 2–4, §6, §7, §13–14). One centred native `.glassEffect(.clear, in: .circle)` at constant 0.48 opacity (1.0 under Reduce Transparency), with a fixed centre and an optional radius bounce in 0.92–1.09. It sits over a *decorative* SwiftUI Canvas that receives the bounded `instrumentLensOptics` warp and diagonal RGB split. Above it go a faint 76° rim arc and then the unfiltered readout.

**Blur2ool mapping: the kernel well.** A small round well (D ≈ 88 pt) at the trailing end of the readout band. Its Canvas face draws the blur's **2D footprint** as an engraved mechanism. This is the domain mechanism, the counterpart of Metro's ticker:

- Gaussian: concentric rings at 1σ, 2σ and 3σ, with tap dots on the axes sized by weight (cyan).
- Box: a square outline. Disc/bokeh: a circle, or an n-gon for blades.
- Motion: a line segment at the current angle. Radial/zoom: arcs or rays.
- Kawase: the four diagonal sample points per pass, spreading outward (amber for the current pass).
- Bilateral or median: a ring plus the label `DATA-DEPENDENT`.

The `InstrumentLensSurface` geometry scales with D. At D = 88 pt: lens 0.76D ≈ 67 pt, `maxShift` = min(9.5, 0.025 × 88) = 2.2 pt, RGB split = min(1.2, 88/322) ≈ 0.27 pt, `maxSampleOffset` ≈ 2.34 pt (COMPUTED from §14 formulas). The centre never moves.

- *Radius bounce* (optional, §13): a one-shot native spring (1.0 → ≤ 1.04 → 1.0) when the semantic crown lands on a new named σ band. There must be no repeating bounce, since an idle blur has no clock (§19: "a dashboard should not bounce every poll").
- **Never** a draggable lens. Toothpaste Toy made its lens the finger (REDESIGN.md §3), which breaks contract 2. Blur2ool moves the probe crosshair instead and keeps the lens still.

**The irony, and the opportunity.** Blur2ool's Metro lens is itself a production backdrop effect whose parameters are hidden, inside an app whose rule is that every number carries a provenance badge. Two facts make this a teaching moment rather than an embarrassment:

1. Apple frames Liquid Glass as **lensing, not blurring**. In WWDC25 session 219, "Meet Liquid Glass" (Dynamics chapter), Apple says that where previous materials "scattered light", this material "dynamically bends, shapes, and concentrates light", and calls lensing "the primary way Liquid Glass visually defines itself". Larger elements get "a softer scattering of light" (Adaptivity chapter). Source: https://developer.apple.com/videos/play/wwdc2025/219/ (REFERENCE). The wording of these quotes was re-checked against the session page transcript on 13 Oct 2026. The page's chapters are Introduction, Dynamics, Adaptivity, Principles and Next steps. The chapter assigned to each quote here was not re-checked. Apple's iOS 7 materials, which the same session cites as ancestors, were blurs. So the lens shows the line between a **warp, which moves samples**, and a **blur, which averages them**. Metro's own `instrumentLensOptics` shader is purely a warp plus channel offset: a bounded displacement of at most 2.2 pt here, which never averages anything.
2. The `.clear` variant "does not have adaptive behaviors", is "permanently more transparent" and "needs a dimming layer" (same session, Principles chapter). Metro supplies that dimming with near-black metal plus 0.48 opacity. Blur2ool should not use `.clear` anywhere except the lens (the session says the variants "should never be mixed" on one element).

**How the lens stays honest:**

- The lens covers only the decorative well face, never the specimen (Specimen rule, C.1).
- A field-guide entry titled "The lens on this instrument" states that it is Apple Liquid Glass (`.clear`) composited at 48% opacity, that its internal lensing, scattering and tint are rendered by the system and not exposed, and that every figure about them is INFERRED. It also states that the small tilt-driven shift beneath the glass is Blur2ool's own shader: a displacement of at most 2.2 pt with an RGB split of at most 0.27 pt (COMPUTED from Metro §14). It moves pixels and does not blur them.
- According to `sdk-feasibility.md` §3–4, Materials and Liquid Glass are backdrop effects drawn by the system render server, so `ImageRenderer` is expected not to capture them. That note marks the glass case itself as UNVERIFIED. Either way, do not show any σ for the lens as MEASURED.

**The Liquid Glass exhibit (catalog entry `liquid-glass`, family "Composite UI blurs").** Here glass becomes the subject:

- The specimen is drawn in SwiftUI rather than an `MTKView`, so the system glass samples known content.
- Native glass shapes (regular/clear, tint, interactive, size small → large) sit over it at full opacity.
- An A/B toggle switches to a MODELED Metal reconstruction: backdrop downsample + Gaussian + saturation + an SDF-driven edge displacement for lensing.
- The KERNEL and FREQ pills show `INFERRED — NOT EXPOSED` for the native side and the model's curves for the reconstruction.
- The same entry can point out that the floating action group at the bottom is a live backdrop-glass exhibit over whatever is scrolling.

Whether native glass samples `CAMetalLayer` content faithfully is UNVERIFIED (§G); that is why the exhibit uses SwiftUI content.

### C.3 Steppers: integers, and a decimal variant for σ

- `InstrumentParameterStepper` (integer, writes the Binding before `onAcceptedChange`; §9, §18). Use it for integer quantities, never shown with decimals (contract A.6):
  - PASSES: iterated box 1–6, Kawase iterations 1–8
  - LEVELS: pyramid/dual Kawase 1–6
  - RADIUS: box/median/Kuwahara, integer px
  - TAPS PER SIDE, when kernel truncation is a teaching variable
  - BLADES: bokeh 5–9
  - ITERATIONS: diffusion steps
- `swiftui-integration.md` notes that the integer Stepper formats its stored integer directly, so a value stored in tenths needs a domain-formatted Stepper. Blur2ool therefore needs a **`DecimalParameterStepper`**: σ stored as `Int` tenths of a px (3…640 → 0.3–64.0 px), shown as `4.0 px`, step 0.1 px. It is the native, accessible alternative to the crowns (§8 "Provide non-gesture alternatives"). The display precision must equal the spoken precision (§4).
- Placement follows Metro: directly under the hero (§9), max width 380, min height 48, padding 14, panel fill 0.85, cyan 0.14 border.

### C.4 Crowns: fine σ and semantic σ stops (port; not in the starter)

| Crown | Detent | Blur2ool meaning | Caption (top / bottom) |
|---|---|---|---|
| FINE (cyan) | 8°, hysteresis 1.44° | ±0.1 px of the primary continuous parameter (σ, disc radius, motion length) | `FINE` / `±0.1 PX` |
| SEMANTIC (amber) | 20°, hysteresis 3.6° | Jump between σ octave stops 0.5 · 1 · 2 · 4 · 8 · 16 · 32 · 64 px, which match the named meaning bands | `SIGMA · Frosted` / `Softened ⇆ Backdrop` (mirrors Metro's `Moderato ⇆ Presto`) |
| ANGLE (cyan), directional blurs only | 8° = 1°; semantic snaps at 0/45/90/135° | Motion/directional blur angle in degrees | `ANGLE` / `±1°` |

- Rules: emit at most one step per update, at most 20 events/s, 7 pt centre exclusion, and initialise on first touch without a value change (§10). Haptic vocabulary per §15: fine up 0.78/0.95, fine down 0.82/0.20, semantic up 1.00/0.60, semantic down 1.00/0.05.
- Each crown sits between real 44 × 44 glass ± buttons (§10, §18 recipe).
- At accessibility text sizes the crowns stack vertically (§10).
- Crowns sit outside every `TimelineView` (contract A.7).
- **Source to port from:** Metro Station `App/Views/TempoCrownsView.swift` (301 lines) + `Sources/MetronomeCore/CrownDetentTracker.swift`, or LabKit's `Sources/LabKitMetro/Components/MetroCrown.swift` (408 lines) + `Logic/MetroDetents.swift`. Copy the files in; do not take a package dependency (see §E).

### C.5 Vertical signal pills: KERNEL (cyan) and FREQ (violet)

This mirrors Metro Station's WAVE/FREQ pair flanking the dial (see the build-14 device screenshot `Metro Station/Documentation/PhysicalQA/Build14/appearance-only/native-pair/5D948488….png`).

| | **KERNEL** pill (wave family) | **FREQ** pill (spectrum family) |
|---|---|---|
| Title | `KERNEL` (`signal.wavePrimary` #4FDBFF) | `FREQ` (`signal.spectrumPrimary` #C291FF) |
| Upper endpoint | `−3σ` (or `−R`), in px | `NYQ` (0.5 cycles/px) |
| Vertical axis | Tap offset, running **downward** from −extent to +extent (Metro's wave runs downward in time) | Spatial frequency, running **upward** from DC to Nyquist (Metro's spectrum runs upward) |
| Horizontal axis | Weight, normalised to the peak (the accessible value says "normalized") | \|H(f)\|, linear, 1 at DC for a normalised kernel |
| Quiet reference trace | The continuous ideal (e.g. the analytic Gaussian) | The ideal continuous response (e.g. the Gaussian `exp(−2π²σ²f²)`) |
| Primary trace | The discrete taps as horizontal stems | The DFT of the discrete kernel |
| Depth colour | `waveDepth` #3666FF: the effective kernel after all passes (iterated box → near-Gaussian; Kawase effective footprint) | `spectrumDepth` #F55CD6: **sign-flipped lobes** (box/disc sinc/jinc). Contrast reversal is a fingerprint of box blur |
| Marker | — | Amber carrier marker (`signal.carrier` #FFBA57) at the −3 dB cutoff f_c where \|H\| = 1/√2 |
| Provenance | COMPUTED (BlurCore), or LIVE local weights at the probe for data-dependent filters | COMPUTED (analytic + DFT). For nonlinear filters, `N/A · NONLINEAR` engraved inside the pill (honest empty state, §16 "Error/clear empty state") |

- Geometry (§5, §11): width 36 at a cluster width of 406 pt; height min(218, 0.66 × 322) = 212.5 pt; gap 6; padding 5 horizontal and 10 vertical; internal gap 3.
- Enclosure: gradient `pillLight → pillDark`. The 0.8 pt outline is **static**, with primary at 0.36 (0.70 under Increased Contrast) (contract A.5).
- Interior motion: on an *accepted* parameter change, the trace eases from the old to the new shape with Metro's bounded attack/decay structure (§11: attack ≤ 20 ms, smooth decay; retune to about 150 ms total). Reduce Motion snaps.
- No pulse while idle: a blur has no clock, so the pills are still unless something changed.

### C.6 Telemetry row

§12 calls for three equal columns, 1 × 30 pt dividers at white 0.10, one accessible element per metric and a lower cadence than the hero. Use `InstrumentMetricReadout` plus a badge under the label:

| Column | Example | Precision policy (§4) | Badge |
|---|---|---|---|
| `σ EFF` | `3.98 px` | 2 decimals | COMPUTED (second moment of the discrete kernel). MEASURED when it is an impulse fit of a system API, e.g. `.blur` via `ImageRenderer` (`live-calibration.md`) |
| `TAPS` | `26` | integer | COMPUTED (texture reads per output pixel, summed over passes) |
| `GPU` | `0.42 ms` | 2 decimals, rolling median of the last 30 frames, refreshed ≤ 4 Hz | MEASURED (`gpuEndTime − gpuStartTime`, BRIEF.md) |

- An optional second row behind a disclosure holds `BYTES/PX` (MODELED bandwidth), `PASSES` (COMPUTED) and `PARITY` (MEASURED max |GPU − CPU| in 8-bit steps).
- Colours: cyan for continuous values. Amber is reserved for the MEASURED event value (GPU ms) only if he wants emphasis (Metro's Tick Pitch precedent). Violet for MODELED.

### C.7 Pass tiles (event-tile grammar, §12)

- One tile per GPU pass: `H · V` (separable); `0 1 2 2 3` (Kawase offsets); `↓1 ↓2 ↓3 ↑3 ↑2 ↑1` (dual Kawase); `ΣROW ΣCOL READ` (SAT); `FFT ×K IFFT`. Header `PASSES` on the left and `2 / 2` on the right (Metro's `BEAT GRID 2 / 4`).
- Geometry: 37 pt high, radius 8, row gap 7. Active: cyan fill 0.08 + border 0.35. Idle: white 0.025 + 0.06.
- Subdivision markers (2-pt capsules) show taps per pixel for that pass, capped at 16 marks, with the number beside them if there are more.
- Tapping a tile shows that pass's **intermediate texture** in the specimen. The phase metadata then reads `PASS 1/2 · HORIZONTAL`, and the status row says which pass is on screen (spec §12: "staged processing").
- In the Trace guide, completed passes are amber and the next pass is cyan (AssemblerToy's accepted split, §F.1 item 8).
- More than about 6 passes wrap to a second row. This needs a bounded height (ClassicalML legend lesson, §F.2 item 5).

### C.8 Signal lab panel (§12)

A quiet content panel with a native segmented `Picker`: **Kernel · Response · Error · Cost**. Scope height 140 pt; at accessibility sizes the fixed height is removed and metadata stacks. The metadata line reads like Metro's carrier line, e.g. `f₋₃dB 0.047 c/px · σ 4.00 px · normalized`, with the provenance badge at the top-right (the ClassicalML `READY` chip precedent).

- **Kernel:** 1D profile, continuous vs discrete stems; x in px, y in weight (normalised, stated).
- **Response:** \|H(f)\| from 0 to 0.5 cycles/px, linear or dB toggle, −3 dB marker, negative lobes in magenta.
- **Error:** discrete vs continuous (truncation at ±kσ), or GPU vs CPU parity in 8-bit LSB (MEASURED on device by readback).
- **Cost:** reads per pixel vs σ for the algorithms in the family (COMPUTED: O(σ²) brute force, O(σ) separable, O(1) SAT/IIR, O(log σ) pyramid), with this device's measured GPU ms dots overlaid (MEASURED).

Every plot needs an accessible data table behind a disclosure (Los Alamos added one for its chart; §F.4 item 2). Bars and stems need explicit widths (§F.4 item 1).

### C.9 Floating action group (§12)

Native glass over the page, no backing strip, `GlassEffectContainer(spacing: 14)`, row spacing 12, horizontal inset 22, bottom 12. Label frames, with the actual glass measured after layout:

- Left: **Compare** 62 × 58 (`rectangle.split.2x1`). Opens an A/B wipe with a 44-pt drag handle that owns its touches.
- Primary: **Trace a pixel**, flexible width, ≥ 58 tall, `.glassProminent`. Cyan when idle; amber while an auto-sweep or pass walk is running (Metro's stopped/running colour rule).
- Right: **Layers** 54 × 58 (`square.3.layers.3d`). Opens the WYSIWYG → GPU atlas.

The catalog is reached from the header chip, and settings plus the field guide from the header glass icon button. That keeps the bottom row to three controls, honouring AssemblerToy's build-6 lesson (§F.1 item 1).

### C.10 Layers: WYSIWYG → GPU (new, modelled on AssemblerToy's atlas and guide)

Seven layers, each with a symbol and an eyebrow (`LAYER 3 OF 7`):

1. **Designer's slider** (Figma, Photoshop, CSS, SwiftUI `.blur`)
2. **API call** and what its parameter means (radius vs σ conversions from `stack-semantics.md`)
3. **Continuous math**
4. **Discrete kernel**
5. **Algorithm and passes**
6. **Metal shader and dispatch** (threadgroup size, texture reads, precision)
7. **Pixels out** (the probe's input → output values)

Each layer page follows AssemblerToy's `LayerAtlasView` grammar: a panel with `FOLLOW THE PIXEL` and `GOVERNING RULE` (callout mono, cyan, units near the equation, §4), then `IN THIS APP` (honesty: what is LIVE vs INFERRED at this layer), then ↓ Lower layer / ↑ Higher layer buttons.

**Trace a pixel** reuses AssemblerToy's guide pattern, which the user accepted after the ergonomics pass:

- A compact context card: pixel (x, y), input RGB, output RGB, `Completed: Horizontal pass` in amber, `Next: Vertical pass` in cyan.
- A layer selector grid (4 + 3 tiles, min height 54).
- One selected layer's primary facts, with `All … details` in a `DisclosureGroup`.
- Bottom `safeAreaInset` controls: Back · Restart · **Next pass**.

### C.11 Settings and explanations (§12)

- Use `NavigationStack` + `Form` + Done.
- Present every sheet from **one** `.sheet(item:)` enum. Toothpaste found that two `.sheet`s on one view silently failed (§F.5).
- **Field guide per blur:** the fingerprint (PSF shape, \|H\|, edge behaviour, cost class, artifacts, where used) with REFERENCE citations.
- **Settings:** specimen, **edge mode** (clamp/mirror/wrap/zero), **colour space** (sRGB-encoded vs linear-light blurring: a real, visible difference), precision (fp16/fp32), tilt optics on/off, haptics on/off, badge visibility.
- The field guide also carries the lens honesty text from C.2.

### C.12 Honesty badge (new component in Metro grammar)

- A small capsule: label in caption2 mono, tracking 1.2. Fill white 0.06, 0.6 pt border white 0.12; 0.25 under Increased Contrast.
- The **word is primary**. Colour and a glyph are redundant cues, per §3 and §17 (pair colour with shape and text):

| Badge | Glyph | Ink |
|---|---|---|
| LIVE | `circle.fill` (5 pt dot) | action cyan |
| MEASURED | `stopwatch` | instrument amber (a timing *event*) |
| COMPUTED | `equal` | display ink |
| MODELED | `approximately` (≈) | spectrum violet (second, model family) |
| REFERENCE | `book.closed` | secondary ink |
| INFERRED | `questionmark` + **dashed** border | spectrum depth magenta |

- Badges never animate. They are part of the spoken value, e.g. "GPU time, 0.42 milliseconds, measured on this device".
- Amber already means activity (§3), so errors still need text plus a symbol, not an amber badge.

## D. Recommended iPhone 15 Pro Max portrait layouts (430 × 932 pt)

### D.0 Frame and screen map

- **Screen:** 430 × 932 pt at scale 3, i.e. 1290 × 2796 px. VERIFIED from the simulator profile: `iPhone 15 Pro Max.simdevicetype` has `ArtworkDeviceScaleFactor` 3, `ArtworkDeviceSubType` 2796 and `DeviceCornerRadius` 55.
- **Safe-area insets:** top 59 pt, bottom 34 pt, as commonly published for this model. These were **not** verified here. Read them from `GeometryReader` on the device before tuning to the point. The usable column is about 839 pt tall.
- **Width math (§5):** screen inset 12 → available width 406 → `clusterWidth` 406, `pillWidth` 36, **D = 322**, `pillHeight` = min(218, 0.66 × 322) = **212.5**. These are the spec's own tested values.
- **Screens.** The Lab is the root of a `NavigationStack`. Trace is a push from it. Every sheet comes from **one** `.sheet(item: $destination)`, so two sheets can never compete (§F.5 item 3).

| Screen | Presentation | Purpose |
|---|---|---|
| **Lab** (root) | `NavigationStack` root, `ScrollView` with `.id(blur.id)` (§F.2 item 1) | One blur, live: specimen, controls, channels, telemetry, lab, fingerprint |
| **Catalog** | sheet (`.large`) | 30+ blurs grouped into families |
| **Trace a pixel** | push | Walk one pixel through the layers and passes (§C.10) |
| **Layers atlas** | sheet | WYSIWYG → GPU, 7 layers (§C.10) |
| **Field guide + Settings** | sheet, `NavigationStack` + `Form` + Done | Per-blur fingerprint with citations; global settings (§C.11) |
| **Compare** | in-place mode of the Lab | A/B wipe inside the specimen window |

### D.1 Lab: first viewport (screen y coordinates, pt)

```
y   0 ┌──────────────── status bar / Dynamic Island (environment extends under it) ───────────────┐
   59 ├─ safe area ─────────────────────────────────────────────────────────────────────────────────┤
   69 │  Blur2ool                                                                        (book) 44  │ header: h-inset 24, top 10, bottom 12
      │  BLUR SIMULATOR · WYSIWYG → GPU                                                             │
  130 ├─────────────────────────────────────────────────────────────────────────────────────────────┤
      │ (photo)44  ‹44  [ Gaussian · SEPARABLE ▾ ]  250 × 44 chip                         ›44       │ selector row, 44 tall
  186 ├──┬─┬──────────────────────────────── housing 322 × 446 ────────────────────────────┬─┬──────┤
      │K │ │ SPECIMEN · SIEMENS STAR                                        LIVE · METAL   │ │F     │ caption row in the 24-pt top margin
      │E │ │ ┌──────────────────── image window 298 × 298 pt (894 px) ─────────────────────┐│ │R     │ y 210–508
      │R │ │ │                      MTKView, LIVE GPU output                             ││ │E     │ pills 36 × 212.5, centred on the window:
      │N │ │ │                      + amber probe crosshair                              ││ │Q     │ y 252.75–465.25
      │E │ │ └───────────────────────────────────────────────────────────────────────────┘│ │      │
      │L │ │ SIGMA · PX                                                    ╭ kernel well ╮ │ │      │ readout band y 516–620 (104)
      │  │ │ 4.0                                                           │  D = 88    │ │ │      │
      │  │ │ Softened                                                      ╰ clear lens ╯ │ │      │
      │  │ │ 13 TAPS · 2 PASSES · SEPARABLE   ← phase / status row, fixed 14 pt            │ │      │
  632 ├──┴─┴──────────────────────────────────────────────────────────────────────────────┴─┴──────┤
  644 │              [ SIGMA        −  4.0 px  + ]   DecimalParameterStepper, ≤ 380 × 48           │ y 644–692
  704 │    FINE   ±0.1 PX               SIGMA · Softened                                            │ crown row 98: captions 14 + 4 + crown 62 + 4 + 14
      │  (−) (crown 62) (+)           (−) (crown 62) (+)                                            │ y 704–802
  802 │                                                                                             │
 ≈828 │   ┌Compare 62×58┐  ┌──── Trace a pixel (flex, ≥ 58, .glassProminent) ────┐  ┌Layers 54×58┐  │ floating glass group, bottom 12
  886 │   └─────────────┘  └──────────────────────────────────────────────────────┘  └────────────┘  │
  898 ├─ home indicator safe area (34) ──────────────────────────────────────────────────────────────┤
  932 └─────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Element | Frame (x, y, w, h), pt | Notes |
|---|---|---|
| Header | x 24…406, y 69–118 | Title 27 pt semibold rounded. Subtitle 11 pt mono with tracking 2.6 (the spec recommends scalable 11–12 pt). The field-guide/settings `InstrumentGlassIconButton` is 44 × 44 at x 362. |
| Selector row | x 12…418, y 130–174 | Specimen menu 44 · previous blur 44 · **blur chip** 250 × 44 (name + family; opens Catalog) · next blur 44. Spacing 8. |
| KERNEL pill | x 12, w 36; y 252.75–465.25 | Centred on the image window, not on the whole housing, so the trace lines up with the pixels it describes (§C.5). |
| Specimen housing | x 54, w 322; y 186–632 (h 446) | Margins: top 24 (caption row 11 pt mono + ruler ticks), sides 12, bottom 12. Window-to-band gap 8. Corner radius 30. |
| Image window | x 66, w 298; y 210–508 | `MTKView`, 894 × 894 px. Ruler ticks sit in the 12-pt metal margins (minor every 8 px = 2.67 pt, major every 64 px = 21.3 pt). Nothing overlaps the window (Specimen rule, §C.1). |
| Readout band | x 66, w 298; y 516–620 (h 104) | Left block, 198 wide: unit line 14 · hero 44 pt light rounded, monospaced digits (line ≈ 52) · serif-italic meaning (≈ 20) · phase/status row 14. Right: kernel well D = 88 at x 276–364. |
| Kernel well | 88 × 88; lens 67 (0.76·D) | `InstrumentLensSurface(diameter: 88)`. `maxShift` 2.2 pt, split ≈ 0.27 pt (§C.2). |
| FREQ pill | x 382, w 36; same y as KERNEL | |
| σ Stepper | centred, ≤ 380 × 48; y 644–692 | Directly under the hero (§9). It shows the *requested* value. |
| Crown row | centred, 2 × 162 + 24 = 348 wide; y 704–802 | Each group: 44 + 6 + 62 + 6 + 44. Shown only when the blur's primary parameter is continuous. |
| Floating group | label frames y ≈ 828–886; inset 22 | Measure the real glass (§12). It reports its height through a preference key. |

Clearance between the crowns and the group is about 26 pt, so the first viewport ends on a whole component (§F.3 item 3). If the measured glass is taller than the 58-pt label frame, take the difference out of the housing's top margin (24 → 18), not out of the image window.

**Merged phase/status row.** §8 item 6 (phase metadata) and §16 "Applying" (a constant-height status row) share the fixed 14-pt bottom row of the band. Normally it reads `13 TAPS · 2 PASSES · SEPARABLE`. While the requested σ differs from the frame on screen it reads `RENDERING… PASS 2/2`, and during a pass walk `PASS 1/2 · HORIZONTAL`. The height never changes (§F.1 item 2, §F.2 item 4).

**Per-blur control sets.** The catalog declares each blur's primary parameter kind. The Lab composes its controls from that declaration, never from live values (§F.1 item 3):

| Primary parameter kind | Under the hero | Crown row |
|---|---|---|
| Continuous (σ, disc radius, motion length, zoom strength) | `DecimalParameterStepper` | FINE + SEMANTIC, or FINE + ANGLE for directional blurs |
| Integer (box radius, Kawase iterations, median radius) | `InstrumentParameterStepper` | None. The freed 110 pt moves the telemetry row into the first viewport. |
| Named (bokeh blade shape, edge mode) | Native `Picker(.segmented)` or event tiles | None |

### D.2 Lab: below the fold (heights, pt; 12-pt stack spacing)

| Order | Component | Height | Notes |
|---|---|---|---|
| 1 | Secondary integer Steppers (passes, taps, levels…) | 0–2 × 48, gap 8 | Only the ones this blur has |
| 2 | Telemetry row (§C.6) | 64 | Three columns of ≈ 135 pt; dividers 1 × 30 white 0.10. Each column is label (caption2 mono) · value (title3 mono) + unit · badge. The disclosure for a second row adds 64. |
| 3 | Pass tiles (§C.7) | 60 (one row) / 104 (two rows) | Header 16 + gap 7 + tiles 37. Tile width = (406 − (n−1)·7)/n, at least 44. |
| 4 | Signal lab panel (§C.8) | 282 | Padding 16 · segmented picker 32 · metadata 14 · scope 140 · caption ≈ 40, inner gaps 8. The scope is 374 wide (406 − 32). |
| 5 | Fingerprint panel ("What makes it unique") | ≈ 240 | Six rows (PSF shape, \|H\|, edges, cost class, artifacts, used in), each with a badge. A `Field guide` link at the end. |
| 6 | Layers entry panel | ≈ 120 | A 7-step strip (`SLIDER → API → MATH → KERNEL → PASSES → SHADER → PIXELS`). Each step is ≥ 44 wide in a 2-row grid; tapping one opens that layer. |
| 7 | Bottom reserve | measured group height + 12 + 16 | ≈ 86–98. Metro's own 98 is "source-specific" (§5). |

The Lab is about 1.8k pt tall, a little over two screens. Nothing interactive may end under the floating group once scrolled to the bottom (§F.1 item 5).

### D.3 Compare mode (in place)

- The image window splits at a vertical divider. A is on the left (current blur), B on the right: another blur, the CPU reference, or the unblurred input.
- The divider handle is 44 × 298 pt and owns its touches (`instrumentControlOwnsTouches`). Its accessible value is "Split at 50 percent", with adjustable ±10%.
- The `A` and `B` engravings sit in the housing's top margin above each half, not over the pixels.
- Each pill draws A solid and B dashed: shape as well as colour (§17).
- The telemetry row switches to Δ values: `ΔGPU ms`, `ΔTAPS`, `MAX |A−B|` in 8-bit LSB.
- The floating group's left button becomes `Done` while comparing.

### D.4 Trace a pixel (pushed screen; AssemblerToy guide pattern, §C.10)

| Region | Frame, pt | Content |
|---|---|---|
| Navigation bar | inline title `Pixel 148, 92` | Back to the Lab |
| Context card | 406 × ≈ 132 | Left: a 9 × 9 texel neighbourhood, 112 × 112 (12 pt per texel), with tap weights as an amber overlay **on a copy**, never on the specimen. Right: `IN` RGB, `OUT` RGB (mono, monospaced digits), `Completed: Horizontal pass` (amber), `Next: Vertical pass` (cyan). |
| Layer selector grid | 4 + 3 tiles, each ≈ 95.5 × 54, gap 8; 116 total | `LAYER n OF 7` + name. Selected tile has cyan fill 0.08 and border 0.35 (tile grammar). |
| Selected layer facts | panel, flexible | Primary facts, then `All … details` in a `DisclosureGroup` (§F.1 item 7) |
| Bottom controls | `safeAreaInset(edge: .bottom)`, 58 tall | Back · Restart · **Next pass**. A stepped flow is AssemblerToy's accepted exception to floating glass (§F.1 item 12). |

### D.5 Catalog sheet

- A native `List` in a `.large` sheet, with `.searchable`. One section per family; the section header is an eyebrow plus a count (`LINEAR · SEPARABLE · 6`).
- Rows have a minimum height of 64:
  - a 40 × 40 Canvas glyph of the blur's footprint, the same drawing as the kernel well, without glass;
  - the name in body semibold;
  - a one-line fingerprint in caption mono;
  - a cost-class chip (`O(1)`, `O(r)`, `O(r²)`, `O(log r)`, `DATA-DEP`).
- The selected blur gets a cyan checkmark and the `isSelected` trait (colour plus shape, §17).

### D.6 Accessibility text sizes (AX1–AX5)

Following §17 ("stack dense rows and remove decorative metadata before shrinking essential values") and §8:

- **Header:** the subtitle is hidden. The title may wrap.
- **Selector row:** the chip takes its own full-width row, and the 44-pt buttons move to the row below.
- **Housing:**
  - The caption row and ruler numerals are hidden. The ruler ticks stay (§F.2 item 6).
  - The readout band is replaced by a **native text block below the housing**: label, value + unit, meaning and status, at full Dynamic Type size. Spec §8 allows this for complex values.
  - The housing then holds the window plus the kernel well, centred under it.
- **Pills:** they keep their geometry. Titles scale only to the ScaledMetric ceiling, and their accessible values carry the content. If the pill titles cannot fit, the pills move below the housing as a side-by-side pair, each 197 × 140, and are relabelled with explicit axis words.
- **Crowns** stack vertically (§10). **Steppers** use the starter's accessibility-size label stacking. **Telemetry** becomes three stacked rows.
- **Floating group:** icon-only, with full spoken labels (§F.1 item 10).

### D.7 Other widths (for the simulator and future phones)

| Width | Available | D | Pill | Pill height | Image window (D − 24) |
|---|---|---|---|---|---|
| 430 (15 Pro Max) | 406 | 322 | 36 | 212.5 | 298 pt = 894 px |
| 402 (17 Pro, the adopters' usual simulator) | 378 | 294 | 36 | 194.0 | 270 pt = 810 px |
| 393 (15 / 15 Pro) | 369 | 285 | 36 | 188.1 | 261 pt = 783 px |
| 375 (SE / mini class) | 351 | 267 | 36 | 176.2 | 243 pt = 729 px |

All values are COMPUTED from the §5 formula with a 12-pt inset. The specimen texture should follow the window's pixel size, and the `SCALE 1 px = 0.33 pt` engraving must be derived, never hard-coded (§C.1 units note). The layout targets portrait only (§E.6).

## E. Starter copy-in plan

Sources: `references/swiftui-integration.md` ("App-target installation"), spec §18 "Installation into a new project", SKILL.md "Implementation boundaries", the adopters' `App/DesignSystem/` folders (diffed against the starter on 2026-10-13), and two probes run for this note in `$TMPDIR/blur2ool-metro/` (results marked VERIFIED below).

### E.1 Files to copy, verbatim unless stated

| Destination in Blur2ool | Source | Change |
|---|---|---|
| `App/DesignSystem/InstrumentDesignSystem.swift` | **AssemblerToy's hardened copy** `AI Stuff/AssemblerToy/App/DesignSystem/InstrumentDesignSystem.swift` | Restore the two starter doc comments AssemblerToy removed (the "Binding is updated before onAcceptedChange" comment above the Stepper's callback property and the "Post-write notification" line). The functional diff is the `InstrumentGlassIconButton` hardening listed in §F.1 item 4. |
| `App/DesignSystem/InstrumentControlTouchBoundary.swift` | Starter, verbatim | None. AssemblerToy shortened the header comment to "rather than to an ancestor's scroll pan", which overstates what the bridge does. The starter's wording ("nearest containing UIScrollView … nested scroll views and presentation-sheet dismissal gestures require separate host validation") is the accurate one. |
| `App/DesignSystem/LensRefraction.swift` | Starter, verbatim | None. It is Foundation-only, so the same math can also be unit-tested (D = 88 → `maximumShift` 2.2 pt, split ≈ 0.273 pt). |
| `App/DesignSystem/InstrumentLensOptics.metal` | Starter, verbatim | None. VERIFIED: compiles and links for iOS with Xcode 27 beta (`xcrun -sdk iphoneos metal -c` then `metallib`, exit 0). |
| `Documentation/metro-station-design-tokens.json` | `assets/design-tokens.json` | None. A reference manifest, not bundled and not loaded at runtime (swiftui-integration.md). AssemblerToy keeps the same file at the same path. |
| *(not copied)* `UsageExample.swift` | — | Skip it. It is an angle-explorer demonstration (swiftui-integration.md), and neither AssemblerToy nor QuantumToy shipped it. |

QuantumToy's four files are byte-identical to the starter, and AssemblerToy's differ only as described above. Both kept the `Instrument*` names, which keeps future `diff`s against new skill editions trivial.

### E.2 What to rename: nothing in the starter

- Keep every starter type name (`InstrumentPalette`, `InstrumentMetrics`, `InstrumentDesignBackground`, `InstrumentContentPanel`, `InstrumentGlassIconButton`, `InstrumentMetricReadout`, `InstrumentParameterStepper`, `InstrumentLargeReadout`, `InstrumentLensSurface`, `LensRefraction`, `instrumentControlOwnsTouches`) and the Metal function name `instrumentLensOptics`.
- Name the Blur2ool-built Metro components in the same family: `InstrumentCrown`, `InstrumentSignalPill`, `InstrumentEventTiles`, `InstrumentFloatingActionGroup`, `DecimalParameterStepper`. Do not reuse LabKitMetro's `Metro*` names (`MetroCrown`, `MetroSignalPill`, …), so a later migration to that package cannot produce ambiguous unqualified names.
- Domain views take domain names: `SpecimenInstrument`, `SpecimenHousing`, `KernelWell`, `PassTileStrip`, `SignalLabPanel`, `HonestyBadge`. Avoid bare names that `BlurCore` is likely to use for models (`Kernel`, `Pass`, `Blur`, `Specimen`). Views end in `View` or describe the component, not the data.

### E.3 Blur2ool's own design-system files (new)

| File | Contents | Origin |
|---|---|---|
| `App/DesignSystem/InstrumentPalette+Blur2ool.swift` | `extension InstrumentPalette` with the tokens the starter omits: `gaugeHousing`, `metalLight`, `metalDark`, `pillLight`, `pillDark`, `plot`, the six `metal.crown*` colours. Use the manifest key as a comment on each line, and RGB doubles exactly as in §B. Also `extension InstrumentMetrics`: plot radius 10, tile height 37, tile radius 8, tile gap 7, the cluster function from §5. | Tokens (§B) |
| `App/DesignSystem/HonestyBadge.swift` | `enum Provenance { live, measured, computed, modeled, reference, inferred }` (or reuse `BlurCore`'s if it defines one) + the capsule from §C.12 | New |
| `App/DesignSystem/DecimalParameterStepper.swift` | A native `Stepper` over `Int` tenths, with its label formatted in the domain unit (§C.3). Same Binding-before-callback contract | Adapted from the starter's `InstrumentParameterStepper` |
| `App/DesignSystem/InstrumentCrown.swift` + `CrownDetentTracker.swift` | The metal crown and detent tracker (§C.4) | Port from `Metro Station/App/Views/TempoCrownsView.swift` + `Metro Station/Sources/MetronomeCore/CrownDetentTracker.swift` (the source app, build 14). LabKitMetro's `MetroCrown.swift` + `MetroDetents.swift` are a second reference, but are still in development (§E.5). |
| `App/DesignSystem/InstrumentSignalPill.swift` | Static enclosure + interior trace (§C.5) | Port from `Metro Station/App/Views/MetroStationPillView.swift` (+ `PillTickResponse.swift` for the envelope) |
| `App/DesignSystem/InstrumentEventTiles.swift` | Tile row grammar (§C.7) | From the beat strip in `Metro Station/App/Views/InstrumentView.swift` |
| `App/DesignSystem/InstrumentFloatingActionGroup.swift` | `GlassEffectContainer(spacing: 14)` row that reports its measured height through a preference key, for the bottom reserve (§D.5) | New, per §12 |
| `App/DesignSystem/SpecimenHousing.swift` | Rectangular metal housing built from the tokens (not AssemblerToy's drifted literals; see §B.3) | New |
| `App/Services/TiltService.swift` (only if tilt optics ship) | `CMMotionManager` gravity at 30 Hz, the low-pass filter (α 0.18) and the portrait mapping from §13. It pauses on inactive scenes and under Reduce Motion, and it stops only what it started. | Pattern from `Metro Station/App/Services/MotionLighting.swift` |

### E.4 Shader library lookup: the caveats that bite

1. **The lens must compile into the app target's default library.** `ShaderLibrary.instrumentLensOptics` is a dynamic-member lookup on `ShaderLibrary.default`, which resolves the main bundle's `default.metallib`. It does **not** resolve a Metal file added as a copy-only resource (swiftui-integration.md). XcodeGen's `sources: [App]` does the right thing. AssemblerToy's `project.pbxproj` shows `InstrumentLensOptics.metal in Sources` (VERIFIED by grep).
2. **`BlurCore` holds no shaders** (Foundation-only, BRIEF.md). Blur kernels live in the app target, e.g. `App/GPU/Shaders/*.metal`, and Xcode links them into the **same** `default.metallib`. Metal function names are global within that library. Give blur kernels a prefix (`b2ool_gaussianH`, …) and keep helpers `static`, as the starter does with `instrumentSmootherstep`.
3. **Keep SwiftUI shader files separate from blur kernels.** VERIFIED on this Mac (M1 Max, Xcode 27 beta toolchain): `MTLDevice.makeLibrary(source:)` on `InstrumentLensOptics.metal` fails with `fatal error: 'SwiftUI/SwiftUI.h' file not found`, while a plain compute kernel compiles. A quoted `#include "T.h"` **also fails** under runtime source compilation, because the source has no file location. Consequences for the GPU↔CPU parity CLI:
   - It loads only the `App/GPU/Shaders/` glob, never `App/DesignSystem/`.
   - Blur kernels never include `<SwiftUI/SwiftUI.h>`.
   - Shared Swift/MSL structs in a C header (LabKit's `LabKitShaderTypes` precedent) must be **textually prepended** by the CLI. Alternatively, the CLI compiles offline with `xcrun -sdk macosx metal -I …` and loads the `.metallib` with `makeLibrary(URL:)`. The second option is closer to what Xcode does.
4. **Match the math mode on both sides.** VERIFIED: Xcode 27 beta's `MetalCompiler.xcspec` defaults `MTL_FAST_MATH = YES` → `MTL_MATH_MODE = FAST`, and a fresh `MTLCompileOptions().mathMode` is `.fast` (raw 2). Defaults agree today. Set both explicitly anyway (`MTL_MATH_MODE` in `project.yml`, `options.mathMode` in the CLI), so a parity failure can never come from a toolchain default changing. Fast math can change `exp`/`pow` results in the last bits. Parity tolerances are in 8-bit LSB, so this matters at the margin only.
5. **Check it in Release and on device** (swiftui-integration.md). Add a unit or UI test asserting `device.makeDefaultLibrary()?.functionNames` contains `instrumentLensOptics` and every blur kernel name. LabKitMetro's `MetroShaders.verify()` is the precedent. A missing stitchable function fails silently as a visual no-op, not a crash (UNVERIFIED: the failure mode was not reproduced here).
6. **If components ever move into a package or framework** (e.g. LabKitMetro), the lookup must become `ShaderLibrary.bundle(…)` with the `.metal` processed as a target resource. That is LabKitMetro's `MetroShaders.library` pattern. SwiftPM Metal builds there need `TOOLCHAINS=metal` (his LabKit note).
7. **`layerEffect` only applies to SwiftUI-drawn content.** UIKit-backed views such as `MTKView` "cannot be assumed to participate" (swiftui-integration.md). The kernel well's face is therefore a `Canvas`, and the Liquid Glass exhibit draws its specimen in SwiftUI (§C.2).

### E.5 Copy, not a LabKitMetro dependency (for v1)

LabKit now ships a `LabKitMetro` product (`AI Stuff/LabKit/Sources/LabKitMetro/`: crown, pill, gauge, lens, stepper, touch boundary, a `Bundle.module` shader lookup). His LabKit memory note says new toys should depend on LabKit. For Blur2ool v1, copy the starter anyway:

- BRIEF.md says "Copy the starter into `App/DesignSystem` as the adopters do".
- LabKitMetro was started today (`Toothpaste Toy/Documentation/progress-labkit-metro.md`, 19:55 and 20:20 entries). Its status section is still empty and no gallery PNGs exist, so it is unverified and is being edited by another session right now.
- A path dependency would make Blur2ool's `Tools/build.sh` mirror `../LabKit` as well, and would need `TOOLCHAINS=metal` for its Metal resources.
- A dependency is also not needed for the small set Blur2ool uses.

Record this as an open decision (§G). Migrating later is mechanical, because the names do not collide (§E.2).

### E.6 `project.yml` points that touch the design system

- `deploymentTarget: iOS '27.0'`, `SWIFT_VERSION: '6.0'`, `TARGETED_DEVICE_FAMILY: '1'`, `UIUserInterfaceStyle: Dark` (§0 preamble: dark only), and `CFBundleShortVersionString: $(MARKETING_VERSION)` / `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` (§F.2 item 8). The adopters' `project.yml` files are a working template.
- **Portrait only** for v1. Spec §13's tilt mapping (`visual Y ← gravity.z`) is defined for portrait, and §D lays out portrait. AssemblerToy, QuantumToy and Los Alamos all declare landscape too, so this is a deliberate choice; see §G.
- If tilt optics ship, add `NSMotionUsageDescription` (spec §18 step 5). Toothpaste Toy crashed with a TCC SIGABRT when it stopped a `CMAltimeter` it had not started, with no usage string present (his LabKit memory note). Whether `CMMotionManager` gravity alone needs the string is UNVERIFIED. Include it anyway; it is harmless.
- `@available(iOS 26.0, *)` annotations in the starter are redundant at iOS 27 but harmless. Leave them, to keep the diff against the starter clean.

## F. Pitfalls adopters hit (and how Blur2ool avoids them)

Each item: what happened (source), then the Blur2ool rule.

### F.1 AssemblerToy (`AI Stuff/AssemblerToy/Documentation/QA.md`, `Documentation/Ergonomics/audit.json`)

1. **Large persistent bottom controls were rejected by the user** (build 5). Build 6 replaced them with one compact transport row plus a settings sheet; user feedback "Much better" (audit.json `userFeedback`). → Blur2ool: one compact floating row (≤ 5 controls, 44–48 pt tall); move speed/precision/step-size options into a sheet. Never stack a scrubber + transport + tab bar at the bottom.
2. **"Changing content moved panels"** (build 2 physical feedback, QA.md line ~59). Fix: CPU phase, bus and ALU content reserve stable slots; memory/console use bounded viewports. → Blur2ool: telemetry, status row, explanation captions and pills reserve fixed heights; numeric text uses `.monospacedDigit()` and fixed widths so σ going from `9.99` to `10.00` doesn't shift anything.
3. **`ViewThatFits` flipped layout as counter digits grew, then flipped back on Reset** (QA.md line ~154). → Choose arrangement only from available geometry and `dynamicTypeSize`, never from live values. Size candidates with fixed widths (AssemblerToy now passes a fixed-width telemetry candidate).
4. **Icon buttons had tiny accessibility nodes** (15 × 18 pt glyph, 13.7 × 13.3 pt) so synthetic taps missed; also the header icon lost its button role (QA.md lines ~146–152). AssemblerToy's copy of the starter therefore adds to `InstrumentGlassIconButton`: `.accessibilityHidden(true)` on the image, `.contentShape(.circle)`, `.accessibilityElement(children: .ignore)`, `.accessibilityAddTraits(.isButton)`, `.accessibilityIdentifier("instrumentIconButton.\(label)")`, `.accessibilityAction(.default, action)`. → **Take AssemblerToy's hardened copy of `InstrumentDesignSystem.swift`, not the raw starter** (diff verified: these are the only functional differences).
5. **A pinned footer obscured controls:** a test tap meant for Clear landed on the pinned Build & run button and executed the sprite; a chip below the footer was reported hittable but wasn't (QA.md lines ~43–45, ~146). → Every interactive element must fit fully between the navigation bar and the floating group; compute the bottom reserve from the measured floating-group height (spec §5 says the source's 98 pt is not universal).
6. **`.accessibilityElement(children: .ignore)` on a Button wrapper erased child identifiers** (audit.json `verificationDiagnostics`, build 5). → Use `.ignore` only on leaf elements that carry their own label/value/identifier.
7. **Guide entry filled the viewport with narration; values and layer selectors were below the fold** (audit GD-1). Fix: pin compact context (instruction, bytes with named fields, completed/next phase) above a selector grid, show one selected layer's primary facts, and put "All … details" behind a `DisclosureGroup`. → This is the right template for Blur2ool's "Trace a pixel" guide (§C.10, §D.4).
8. **"Ready/current" language didn't distinguish what already happened from what the next tap does** (audit GD-2). → Blur2ool's guide shows `Completed: Horizontal pass` and `Next: Vertical pass` separately, amber for the completed event, cyan for next (AssemblerToy's exact color split, see screenshot `06-guide-registers-compact-build6.jpg`).
9. **Hex bytes without field roles** (audit GD-3/AS-1). → Kernel taps and weights must show their role: tap offset `−3…+3`, weight, and which texel they sample.
10. **Largest-text Guide footer grew to ~250 pt as labels split vertically** (audit, build 6 initial). Fix: icon-only controls with full spoken labels at accessibility sizes, one-column context. → Same rule for Blur2ool's floating group.
11. **Shared simulator collisions:** another app took the shared simulator foreground (QA.md line ~148). → Use a dedicated simulator named `Blur2ool <topic>` (BRIEF.md build rules agree).
12. **AssemblerToy deliberately moved the transport into `.safeAreaInset(edge: .bottom)` over an opaque canvas strip** (`WorkbenchView.swift` `transport` + `.background(InstrumentPalette.canvas...)`). This guarantees reachability (contract 8) but departs from spec §12 ("no black backing strip"). → Blur2ool should prefer the spec's floating glass (it makes the irony of glass-over-blur visible, see §C.2) **plus** a scroll content bottom padding equal to the measured group height + 16 pt. If tests show reachability problems, fall back to AssemblerToy's `safeAreaInset` pattern; note the deviation explicitly.

### F.2 ClassicalMLSimulator (`AI Stuff/ClassicalMLSimulator/Documentation/StressTest.md`, `QA.md`, screenshots)

1. **Switching model while scrolled left the new lab half-way down** (StressTest.md line ~129). Fix: `.id(session.algorithm.rawValue)` on the workbench `ScrollView`. → Blur2ool: give the lab's `ScrollView` an identity keyed by the selected blur id so switching Gaussian → Kawase starts at the top.
2. **Accessibility slider adjustment didn't schedule work because it relied on a drag-end callback** (StressTest.md line ~131). Fix: accepted value writes schedule the debounced computation directly. → Blur2ool: the Binding setter for σ/radius schedules the (debounced, cancellable) CPU reference/spectrum recompute; GPU render may follow every write.
3. **Rapid changes must coalesce; stale results must not revive cancelled work** (StressTest.md line ~43: 80 rapid requests → 1 solver run). → Blur2ool: kernel/DFT/fit computations run off the main actor with a generation token; only the newest generation may publish.
4. **Pending telemetry panel collapsed and jumped** → it now reserves its last measured height (StressTest.md line ~131). Same for Blur2ool's telemetry row and status row.
5. **Unbounded legends** (DBSCAN groups) grew the layout → bounded legend layout with a fixed min height. → Blur2ool's family legends and badge rows get bounded heights.
6. **Accessibility XXXL screenshot** (`Screenshots/accessibility.jpg`, viewed): the engraved caption "SAMPLING CHAMBER" breaks mid-word ("CHAM / BER"), and the translucent frame scrubber + transport + tab bar occupy roughly the bottom 40% of the screen with content showing through. → At accessibility sizes, hide decorative engravings (QA.md line 14 says the header was suppressed, but this panel engraving was not), and collapse the floating group to icons.
7. **ClassicalML did not copy the starter**; it re-implemented a smaller `MLTheme` (`App/DesignSystem/MLTheme.swift`). Consequences visible in source: `LabPanel` is fully opaque (no 0.85 fill, so no Reduce Transparency branch), `LabIconButton` lacks `instrumentControlOwnsTouches` and the accessibility hardening, and there is no touch bridge. → Blur2ool should copy the starter (hardened) rather than re-implement, then add a domain extension file.
8. **Info.plist had literal version numbers that would mislabel an update** (StressTest.md line ~137). → Use `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` in Blur2ool's Info.plist via XcodeGen.
9. **Continuous parameters used `Slider` + monospaced-digit label; integers used native `Stepper`** (`ModelControlsView.swift`). This is the adopter precedent for Blur2ool's σ (continuous) vs passes/taps (integer) split.

### F.3 QuantumToy (`AI Stuff/QuantumToy/README.md`, `Documentation/Validation.md`, `App/Views/QubitLabView.swift`, screenshot `Documentation/QA/QubitLab.jpg`, viewed)

What the screen looks like: an eyebrow `04 / COHERENT CONTROL`, a large rounded headline, a round metal dial with a Canvas Bloch sphere, then a three-column telemetry row (P(|1⟩) cyan %, COHERENCE violet %, TIME amber µs), Run/Reset glass buttons, quiet panels below, and a four-tab glass tab bar floating over the content. It is the closest existing picture of "Metro dial + telemetry + panels". It copied the four starter files byte for byte (§E.1).

1. **The lens drifted from the contract.** `QubitLabView.swift` around line 326 draws `Color.clear.frame(width: d * 0.77 …).glassEffect(.clear, in: .circle).opacity(0.35)` and **removes the lens entirely** when Reduce Transparency is on (`if !reduceTransparency`). The spec says 0.76·D, constant 0.48, and **full opacity** under Reduce Transparency (§6, §17). It also drew the lens by hand instead of using `InstrumentLensSurface`, so there is no rim arc, no optics gating and no `.transaction { $0.animation = nil }`. → Blur2ool uses `InstrumentLensSurface` unmodified for the kernel well. A token-parity unit test should catch any hand-rolled 0.35/0.77.
2. **Semantic labels were drawn under the glass.** The `|0⟩`/`|1⟩` labels and the state vector are Canvas content beneath `.clear` glass, so they are refracted by the system material. Contract 1 (§1) keeps semantic labels out of optical sampling. → In the kernel well, only engraved geometry sits under the lens. Every number and label (σ rings' captions, `DATA-DEPENDENT`) is in the readout layer above the glass, or outside the well.
3. **A glass tab bar over content hid live controls in the first screen** (screenshot: `QUBIT ENERGY GAP 5.00 GHz` and the next control are half under the tab bar). That is normal scroll-under behaviour, but on first launch the user sees a cut control. → Blur2ool has no tab bar (§D). The first viewport must end on a whole component, not a half-covered row.
4. **Simulator UI automation didn't run** (`DTServiceHubClient failed to bless service hub`), and "injected taps on native buttons and tab-bar items left the UI unchanged" (Validation.md). → Do not plan Blur2ool's acceptance around XCUITest alone. Prefer `swift test` on `BlurCore`, offscreen `ImageRenderer` PNGs and in-app `-uiTour` snapshots (the Toothpaste/Rheo precedent, §F.5). Keep build, simulator and device evidence separate, as QuantumToy's Validation.md does.
5. **Validation phrasing to copy:** "This verifies rendering, not tab interaction" and "no UI test pass is claimed" are the honest register Blur2ool's own QA notes should use.

### F.4 LosAlamosSimulator (`AI Stuff/LosAlamosSimulator/README.md`, `Documentation/Validation.md`, screenshots `QA/Trinity.jpg` and `QA/Chain.png`, viewed)

What it looks like: the same eyebrow, headline and subtitle header. A rectangular instrument (`TRINITY / OBSERVATION 01 · SCHEMATIC · NOT TO SCALE`) has its scene above an inset readout band: label `ILLUSTRATIVE ELAPSED TIME`, a large light rounded `18.0 s`, and a serif-italic amber meaning *The cloud develops*. Below it come a slider with `0 s · ILLUSTRATIVE SEQUENCE · 30 s` engravings and Reset/Play glass buttons. This is the best precedent for Blur2ool's **specimen with a readout band under the image** (§C.1). It shows that a rectangle-plus-band reads as Metro without a round gauge.

1. **Relative-width bars on a numeric axis rendered invisible.** The fix was explicit widths (Validation.md: "relative-width bars on the numeric generation axis were invisible. The implementation now assigns an explicit width"). → Every Swift Charts `BarMark` and Canvas stem in the signal lab gets an explicit width in points.
2. **Charts needed an accessible table.** The chain chart gained "an accessible disclosure table covering all 13 generations". → Every Blur2ool plot (kernel, response, error, cost) has a `DisclosureGroup` data table and an `AXChartDescriptor` (LabKit's `LabPlot` precedent).
3. **The model's honesty is engraved on the instrument itself** (`SCHEMATIC · NOT TO SCALE`, `ILLUSTRATIVE ELAPSED TIME`). → Blur2ool engraves provenance in the same place: `LIVE · METAL` on the specimen, `MODELED` on a reconstruction, `INFERRED` on the Liquid Glass exhibit. The badge row adds to this but does not replace it.
4. **Unit-label oddities slip through.** In `Chain.png`, generation is shown as `8 g`, an abbreviation that reads as grams. → Blur2ool spells or standard-abbreviates units (`px`, `pt`, `ms`, `c/px`, `dB`). Counts carry their noun (`26 taps`, `2 passes`), per §4's integer contract, rather than an invented symbol.
5. **The glass tab bar again floated over live content** (`Chain.png`: the `k = 1.20` readout is visibly refracted under the bar). → Same rule as §F.3 item 3.
6. **iCloud build stall and source parity.** The Documents build blocked in `NSFileCoordinator`, so builds moved to a staged copy and a checksum comparison proved parity (Validation.md "Build location and source parity"). → Blur2ool's `Tools/build.sh` mirror (BRIEF.md) should print a manifest hash of the mirrored sources. QA notes then record which source state a screenshot came from.
7. **Load-induced simulator failures were not app defects** (load averages above 450, simulator `Shutting Down` mid-check). → Wrap `simctl` in timeouts (BRIEF.md), and record "blocked by infrastructure" as distinct from "failed".
8. **Reduce Motion stops automatic playback but keeps manual exploration** (README). → The direct analogue for Blur2ool: Reduce Motion stops any auto-sweep of σ and pass-walk animation. Manual stepping (Next pass, Steppers) keeps working.

### F.5 Toothpaste Toy (`Documentation/REDESIGN.md`, `progress-ui.md`, `progress-qa.md`; the ambitious adaptation, in progress on 13 Oct 2026, so no redesigned screenshots exist yet; the `screenshots/ui-*.png` files are the pre-Metro Rheo UI)

What it attempts: a metal "holo chamber" housing a chamber-sized `MTKView`. A Squeeze crown sits over the nozzle, three signal pills (γ̇ cyan, σ amber, λ violet) form a rack beside the chamber, and event tiles, a telemetry row and a five-action floating group fill out the screen. The cyan/amber/violet semantics carry over onto the simulation itself.

1. **Chamber-sized `MTKView` instead of full screen.** It renders "~3× fewer pixels than a full-screen drawable" (progress-ui.md, design decisions 20:30). Everything outside the chamber is SwiftUI, and a thin SwiftUI metal bezel frames the Metal view. → Blur2ool does the same: the `MTKView` is exactly the specimen window (§C.1), and the housing and readout band are SwiftUI. For a blur app this also keeps GPU timing about the blur, not about compositing a full-screen drawable.
2. **The lens became the finger, which breaks Metro contract 2** (REDESIGN.md §3; progress-ui.md: "One-finger touches anywhere in the chamber drive the glass lens"). This was a deliberate, user-directed departure for a toy whose verb is "poke". → Blur2ool keeps the lens fixed (§C.2) and moves an amber probe crosshair instead. If he ever wants a draggable magnifier (a "loupe" over the specimen), it must be a *non-glass* Metal loupe that shows the true texels, because a glass loupe would add the system's own refraction to the very pixels being inspected (Specimen rule, §C.1).
3. **Two `.sheet` modifiers on one view: the second silently did nothing** ("How Rheo works" tapped while the strip was up did nothing; progress-ui.md, independent verification). → One `.sheet(item:)` driven by an enum of destinations (§C.11).
4. **The whole screen rebuilt at the telemetry rate.** The fix: only small leaf views (`LiveCanvas`, `TelemetryTap`, …) read 10 Hz telemetry, so the screen and info sheet stopped rebuilding (progress-ui.md). → In Blur2ool, GPU-ms and other live telemetry live in a separate `@Observable` read only by the telemetry row's leaf views. The specimen, Steppers and crowns never observe it (contract A.7, §20).
5. **The top bar flipped layout as digits changed.** The fix was a fixed `idealWidth` (progress-ui.md 18:20). This repeats AssemblerToy's `ViewThatFits` lesson (§F.1 item 3).
6. **The libAccessibility automation flag persisted in the simulator and deadlocked every later launch** (the simulator had to be erased), and the simulator audio server aborted the test host under load (progress-ui.md). → Never toggle that flag in Blur2ool's test host. Keep haptics and sound off in automated tours.
7. **Feedback ownership was split explicitly.** Control detent haptics belong to the UI; domain-event feedback belongs to the domain, "so nothing is played twice" (progress-ui.md). → Blur2ool: crowns and Steppers own detent haptics. A completed pass walk or a parity failure gets at most one notification-style haptic, owned by the session model.
8. **Honesty line for a style that looks like physics.** REDESIGN.md §6: "The quantum shimmer, ghosts and fringes are a hologram look, not quantum mechanics." → Blur2ool needs the mirror-image sentence for the chrome: "The glass on the controls and the lens is Apple's Liquid Glass. Blur2ool does not measure or simulate it except in the Liquid Glass exhibit, where it is labelled INFERRED." (§C.2.)
9. **Crash from stopping a sensor it never started** (`CMAltimeter.stopRelativeAltitudeUpdates()` without a usage string → TCC SIGABRT; his LabKit memory note). → `TiltService` stops only what it started (§E.6).

## G. Open questions / UNVERIFIED

### G.1 Decisions for Utkarsh (design phase)

1. **Rectangular specimen vs round eyepiece** (§C.1). The recommendation is the rectangle, with the hero in an adjacent band (spec §8 allows it; Los Alamos and AssemblerToy are precedents). The round microscope eyepiece keeps Metro's silhouette but crops corner pixels.
2. **Tilt optics in v1?** At D = 88 the lens warp is at most 2.2 pt and the RGB split is about 0.27 pt (≈ 0.8 device px). The effect is real but faint, and it costs a CoreMotion lifecycle (§E.3 `TiltService`). The spec's adoption sequence puts "bounded material response" **last** (§19). Recommendation: ship v1 with `InstrumentLensSurface(…, motionActive: false)`. The native lens and rim stay; the optics shader is off. Add tilt once everything else passes.
3. **Copy the starter vs depend on `LabKitMetro`** (§E.5). Copy for v1. Revisit when LabKitMetro has a verification record.
4. **Portrait only** (§E.6). The other adopters allow landscape; Blur2ool's layout and the tilt mapping are portrait.
5. **Merged phase/status row** (§D.1). Metro's source keeps a separate status row. Merging saves about 20 pt in the first viewport. It is a deliberate reading of §8 item 6 plus §16, not a source copy.
6. **Floating glass vs `safeAreaInset` strip** (§F.1 item 12). Prefer the spec's floating glass, and fall back to AssemblerToy's strip only if reachability tests fail.
7. **The σ meaning-band names** (*Sub-pixel, Anti-alias, Softened, Frosted, Backdrop, Fog*) are Blur2ool's invention, not a standard (§C.1). Keep them labelled as descriptive.

### G.2 UNVERIFIED facts (check before relying on them)

| # | Claim | Why it matters | How to check |
|---|---|---|---|
| 1 | Native Liquid Glass faithfully samples `MTKView`/`CAMetalLayer` content scrolled beneath it | The floating group over the specimen; the Liquid Glass exhibit (§C.2) | On device: a known Metal pattern under `.glassEffect`, captured with `simctl io screenshot` / device screenshot |
| 2 | 15 Pro Max portrait safe-area insets are 59 / 34 pt | All y coordinates in §D.1 | `GeometryReader.safeAreaInsets` logged on device |
| 3 | The floating group's rendered glass is close to its 58-pt label frame | The bottom reserve and the 26-pt clearance (§D.1) | Measure the rendered frame in the simulator and on device (§12 says native padding can enlarge it) |
| 4 | A missing `[[stitchable]]` function fails as a silent visual no-op rather than a crash | §E.4 item 5 test design | Rename the function in a scratch build and run |
| 5 | `CMMotionManager` gravity alone needs no `NSMotionUsageDescription` | §E.6. The string is included anyway. | Apple docs or a device run without the key |
| 6 | Composited text contrast over the cyan wash and under glass meets WCAG | §17: "Color tokens and low opacity do not constitute contrast certification" | Sample real screenshots, including Increased Contrast and Reduce Transparency |
| 7 | `.glassEffect(.clear)` at opacity 1 (Reduce Transparency) still reads as a lens, not a grey disc, over the kernel-well face | §C.2, §17 | Device check with Reduce Transparency on |
| 8 | The 0.27-pt chromatic split at D = 88 is perceptible at all | Whether to keep chroma for the small lens (§G.1 item 2) | Device, hands-on |
| 9 | Pill-title ScaledMetric ceilings: the spec gives a 10-pt base but no cap | §D.6 accessibility layout | Choose a cap and test at AX5 |

### G.3 What this note did and did not verify

- **Verified here (probes in `$TMPDIR/blur2ool-metro/`):**
  - The starter lens shader compiles and links for iOS with Xcode 27 beta.
  - Runtime `makeLibrary(source:)` cannot resolve `<SwiftUI/SwiftUI.h>` or quoted includes on this Mac.
  - The Xcode 27 beta default Metal math mode is FAST, and `MTLCompileOptions` defaults to `.fast`.
  - QuantumToy's four starter files are byte-identical to the starter; AssemblerToy's diff is the icon-button hardening plus comment edits.
  - AssemblerToy's `.metal` is in its Sources build phase.
  - iPhone 15 Pro Max simulator profile: scale 3, 2796-px subtype, corner radius 55.
  - The WWDC25 "Meet Liquid Glass" quotes were checked against the session page transcript.
- **Read but not run:** every adopter's QA claims are quoted from its own documents. None of their screens was re-run for this note.
- **Not done:** no Blur2ool code exists yet. Nothing here is a runtime, accessibility or device validation of Blur2ool (SKILL.md "Validate the adopted result").

<!-- STATUS: COMPLETE -->
