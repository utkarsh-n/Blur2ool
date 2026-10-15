# Blur2ool: judge verdict on user delight and fidelity to the ask

Date: 14 October 2026. Judge lens: **user delight and fidelity to the ask.** The questions are which concept Utkarsh would love, keep open and actually use, and which one answers every clause of his request. The request is: a blur simulator; a mathematical visualizer; every layer from WYSIWYG to the GPU; what makes each of dozens of blurs unique; a SwiftUI iPhone app; Metro design.

Concepts judged (all three read in full):
- `design/concept-instrument.md` (abbreviated **I**)
- `design/concept-descent.md` (**D**)
- `design/concept-engine.md` (**E**)

Research used for grounding: `BRIEF.md`; `research/CATALOG.md` (§1 taxonomy, §2 master table, §6 tiers, §7 pairs); `research/metro-adaptation.md` (§C.1 Specimen rule and touch, §C.10 layers, §F adopter pitfalls, §G.1 decisions); `research/sdk-feasibility.md` §0; `research/gpu-pipeline.md` §0, §4.2, §5; `research/live-calibration.md` §6. I read the section headings of `catalog-lsi.md`, `catalog-spatial.md`, `catalog-nonlinear.md` and `stack-semantics.md`, and relied on CATALOG for their content.

---

## 1. Method

**1. What the ask demands, clause by clause.** BRIEF.md splits the request into four requirements plus identity and design. I rated each concept on each clause from 1 to 5 (§2).

**2. What this user has rewarded or rejected before.** His past toy projects give direct evidence of taste. Each item below names its source.

- **Loom.** He found the Jacquard-loom metaphor hard to follow. He asked for a "modern but futuristic math engine" look: a **numbered pipeline, one colour per stage, real numbers**, formulas shown, plain terms, and LIVE-style badges. Source: project memory note `loom-llm-toy.md`, entry for the 2026-10-04 redesign.
- **Toothpaste Toy.** At his direction, the lens became the finger: one-finger touches anywhere in the chamber drive it, because the toy's verb is "poke". He wants to touch the simulation directly. Source: `metro-adaptation.md` §F.5 item 2.
- **AssemblerToy.** He rejected large persistent bottom controls. The compact transport row plus a settings sheet got "Much better". He also accepted the Layers atlas plus a stepped Guide that walks one instruction through every layer. Source: `metro-adaptation.md` §F.1 items 1 and 7–8.
- **Gyre and Spectra.** He keeps asking for richer sensory objects: a glass orb with abrasion and chromatic aberration, audio-visualiser knobs, an EMF knob. On Spectra he contributed his own mathematics (a spacetime Wigner distribution) and asked for it to be built in. He wants the visuals to feel alive and the maths to be deep and real. Source: project memory notes `gyre-gyroscope-toy-app.md` and `spectra-em-spectrum-toy.md`.
- **Working style.** "I would rather break the mac by overclock than shy from risk." Ambition is welcome. Source: `feedback-max-parallelism.md`.

**3. Weighting.** Delight decides how much he opens the app. Fidelity decides whether the app is what he asked for. I weighted them about equally, and I treated "visible within one gesture" as part of fidelity. A layer he never finds does not answer "every layer".

---

## 2. Clause-by-clause fidelity matrix

Scale: 5 = answers the clause fully and visibly; 3 = answers it but hides it or answers part of it; 1 = missing.

| Clause (BRIEF) | Instrument | Descent | Engine | Notes |
|---|---|---|---|---|
| **1. Blur simulator.** Real blurs on real pixels, GPU, live, adjustable | **5** | 4 | 4.5 | **I**: drag, pan, pinch zoom, Metal loupe and on-image handles (zoom centre, tilt-shift band, painted paths) make the image itself the control (I §4, §3.3). **D** and **E** allow taps only on the image, because their roots scroll (D §5, E §3.1). **E** adds real timing and parity. |
| **2. Mathematical visualizer.** Definitions, kernels, frequency responses, discretization, error, complexity | 4 | **4.5** | **4.5** | **I** keeps the KERNEL and FREQ pills on the Bench and puts all other plots one layer down. It adds a log-polar figure and a PSF field (I §5). **D** adds a fingerprint matrix across all blurs (D W5). **E** puts a Kernel / Response / Error / Cost signal lab on the Bench (E §3.2). |
| **3. Every layer, WYSIWYG → GPU; follow one pixel** | 4.5 | **5** | 4.5 | **D** shows all seven floors' answers for the probe in the first viewport (the descent rail, D W1). Its Trace adds "branches, not forks". A `TRACE_PROBE` shader build makes trace values real GPU values (D §7, §15 R2). **I**'s pinned periscope keeps the live image on screen while you descend (I §3.4). **E** goes deepest at the bottom (Silicon page, readback of real intermediates, hardware-quantized bilinear `t`), but its layers sit behind a button or below the fold. |
| **4. What makes each blur unique, dozens of them** | **5** | 4.5 | 4 | **I**: σ-hold on switch means that swapping blurs changes the *shape* while the *size* stays put (I §8.1). The fingerprint card has a "unique number", a kurtosis axis, a TELL box with `Show me`, and nearest neighbours (I §7). The Turret holds about 45 live blurs one tap apart. **D**: "the floor where two blurs part ways" is the most original answer (D §9, W6). **E**: measured "ON THIS PHONE" fingerprints and a "LOOKS MOST LIKE" classifier (E §7.1). |
| **5. SwiftUI iPhone app in Metro Station** | 4 | **5** | 4.5 | **D** follows `metro-adaptation.md` most closely. **I** knowingly departs: a non-scrolling root and a touch-owning image, both against §C.1 "Touch", with its reasons argued in I §2. **E** departs only in where the telemetry sits. |
| **Delight.** Feels alive, wow in the first 10 s, tactile | **5** | 3 | 2.5 | **I** opens on Night City HDR lights with a one-time focus pull, crown haptics and a wipe, then a tap turns every light into a hexagon (I §1). **D** opens on a still Siemens star and a strip of chips. **E** opens on a grey star while the app measures itself (`MEASURING · RUN 7/18`), with `‹0.__›` slots on screen. |
| **Long-term use.** Would he keep opening it? | 4.5 | 4 | 3.5 | **I**: the toy loop plus the Descent and Lessons. **D**: the guided descents and the Divergence tab have high replay value for learning. **E**: Calibrate (measuring SwiftUI `.blur` on his own phone) is the one piece with ongoing professional value to him as a SwiftUI developer. The Run log is a nerd delight but not a daily draw. |

---

## 3. Concept: Instrument (score 8.5 / 10)

**What it is.** A pocket optical bench. The root screen is a fixed, non-scrolling Bench: a machined housing around a live 894 × 894 px Metal window, a Turret of footprint glyphs under the title, FINE and SEMANTIC crowns, three telemetry numbers, and three floating buttons (Compare · **Trace a pixel** · Layers). The Descent is seven vertically paged layer pages under a pinned live "periscope". Trace walks fetch by fetch with a running-sum bar.

**Strengths (delight and fidelity).**
1. **Its first 10 seconds are the best of the three, by a wide margin** (I §1). Night City in linear HDR light is the specimen where blurs look most beautiful and differ most. A single 600 ms focus pull, then nothing moves until he touches it. Crown detents give haptics. Tapping the hexagon glyph turns every light into a hexagon at the same size. That moment answers "what makes each blur unique" without a word of text.
2. **σ-hold on switch** (I §8.1) is the single most important comparison rule in any of the three concepts. It turns every switch into an experiment: same second moment, different character. Blurs with no σ are handled honestly (`σ NOT DEFINED · RANK FILTER`). There is a `MATCH σ` off-switch for the "radius 10 in every tool" lesson.
3. **Direct manipulation fits his proven taste for touch** (Toothpaste, Gyre). Drag moves handles or pans the specimen. Pinch zooms pixels. A long press opens an opaque Metal loupe. Paths can be painted.
4. **Pan as a teaching gesture** (I §3.3). Under a Gaussian the image just moves. Under a plain mip pyramid the lights snap to a grid (±7.5 px at L = 4, CATALOG P7). Under dual Kawase they shimmer. "That one gesture teaches shift invariance better than any paragraph", and it is true.
5. **The periscope** (I §3.4). The live image never leaves the screen while you descend, and its ± buttons change σ from layer 6. The concept states the principle: learning is what you see when you look closer, never a mode you enter.
6. **The fingerprint card is the strongest "unique" artefact** (I §7):
   - a fixed layout, so any two cards line up;
   - a four-glyph strip at σ-held size;
   - a **unique number** per blur (box −0.217; binomial 0 at Nyquist; Kawase's hollow centre 0.0645 < 0.0674; hexagon 96 vs 1,496 fetches);
   - a **kurtosis axis** shared by theory and on-device measurement;
   - **TELL · Show me**, which loads the one test image that exposes the blur;
   - nearest neighbours, each one tap from a wipe.
7. **Compare modes are physical and varied.** Wipe, Flip (hold to see B), Difference with gain detents, and **Line-up 2×2**, which suits CATALOG's triads (P2 box/tent/Gaussian, P11 disc/hexagon/Gaussian).
8. **The controls are themselves lessons.** The spin crown's semantic detents land on multiples of 360°/n_c, so the 36-cycle star vanishes on every detent. Odd blade counts are disabled, with the zonogon reason given. `σ > 56 · SWITCHED TO PYRAMID` is announced as a lesson.
9. **The Liquid Glass exhibit** lets him drag a real glass shape over a SwiftUI-drawn specimen, wiped against a MODELED reconstruction. Given his love of Liquid Glass knobs and orbs (Gyre), this exhibit will be a favourite.

**Weaknesses.**
1. **The depth is invisible on the root screen.** The seven layers sit behind a swipe or the `Layers` button, and nothing on the Bench shows what each floor says about the probe. Fidelity to "every layer" suffers until he finds it. This is exactly what Descent's rail solves (graft G4).
2. **The non-scrolling Bench is budgeted to 430 × 932 with 22 pt to spare** (I §14 R3). It must become a scroll view at accessibility sizes and below 402 pt width. It departs from `metro-adaptation.md` §C.1 "Touch" and §D.1. The departure is well argued but adds layout risk.
3. **Six gestures share one 298-pt square** (handles, pan, probe, pinch, loupe, wipe divider; I §14 R2). Without careful priority and device testing, this can feel fiddly rather than alive.
4. **About 45 abstract footprint glyphs in the Turret** are hard to discover. The concept mitigates this with a hero dozen first, long-press names and `[All]`.
5. **Internal vocabulary** (Turret, Periscope, Bench, Specimen) risks leaking into on-screen copy. The Loom lesson says he dislikes metaphors he has to decode.
6. **The engine-side honesty is thinner than E's.** It has no measured "on this phone" fingerprint and no Calibrate sheet: the device measures `measurePSF` only on first use of a Tier S blur.

---

## 4. Concept: Descent (score 8.0 / 10)

**What it is.** Pedagogy first. The root Lab scrolls. Its first viewport holds the specimen, the crowns and a **descent rail**: seven chips, each the probe's answer on one floor (`SLIDE 1.33pt · API 4.0px · MATH G · KERNEL 25 · ALGO 2× · GPU 13 · PIXEL 0.52`). The primary button names a concrete pixel: **Descend from (412, 287)**. Seven fixed-height floor cards follow below the fold. Trace is a stepped walk. The Atlas has three tabs: Families, Fingerprints matrix and Divergence.

**Strengths.**
1. **The rail is literally what he asked Loom to become:** a numbered pipeline, one stage per floor, with real numbers in it (Loom redesign note). It makes "every layer from WYSIWYG to the GPU" visible in the first viewport, all the time, for every blur. It is the best fidelity device in any of the three concepts.
2. **Shift invariance falls out of the layout** (D §2, 4–6 s). Tap another pixel: for an LSI blur only the GPU and PIXEL chips change. No text needed.
3. **Divergence: "the floor where two blurs part ways"** (D §9, W6, W7). Examples: box vs Gaussian part at MATH; separable vs linear-sampled at GPU; CSS `blur(10px)` vs Figma Layer blur 10 at SLIDE. It is a new, memorable answer to "what makes each blur unique", and it works for any pair.
4. **The Trace is the most honest and the most narrative of the three** (D §7):
   - `Completed` / `Next` and a Σ running sum;
   - **branches, not forks**: the sRGB alternative is shown greyed beside the real result, e.g. `OUT 0.450 · if sRGB-encoded: 115/255`;
   - a one-sentence lesson at the end ("The floor that most changed the answer was the one nobody shows: the colour space at the API floor (179 vs 115)");
   - a **`TRACE_PROBE` function-constant build**, so trace values are real GPU values with bit-exact parity against the untraced build.
5. **The WYSIWYG floor is personal.** A "home tool" setting, a "what would you type in each tool" table, and a reverse mode ("you typed 10: σ per tool"). The SwiftUI crown has a semantic stop at the measured regime switch (about 1.7 pt), the only non-octave detent in the app.
6. **The four guided descents** in Lessons are one-tap stories, each with a hook as its title: "Why zoom blur spares a star"; "The blur that looks before it averages"; "Three line blurs make a hexagon".
7. **This phone** upgrades badges in place and keeps both values for a session (`32,768 B MEASURED · 32 KB REFERENCE`), so he watches a claim being checked.
8. **Accessibility is the most complete of the three:** Audio Graphs through `AXChartDescriptor`, a 9×9 texel table, a "Floors" rotor, and photosensitivity rules.

**Weaknesses.**
1. **It is the least alive at first contact.** The first frame is a grey Siemens star. The rail chips are information, not wonder.
2. **The image is tap-only, because the Lab scrolls.** There is no pan, pinch, loupe or drag of a zoom centre on the image (the centre handle is a small 44-pt control). Freehand path and mask drawing are cut (D §14). The toy verb "poke" is mostly gone.
3. **Scrolling the Lab "is" descending**, so the live specimen scrolls away while he reads floor cards. The link between picture and floor breaks exactly when he needs it. Instrument's periscope does better.
4. **Fixed-height floor cards** (232 pt × 7, plus fingerprint and parameters, about 3,200 pt of scroll) risk reading as a lecture. The concept knows this (D §15 R9).
5. **Switching blurs** goes through a chip, prev/next or the Atlas. σ is matched only inside Compare. Casually flipping through blurs to see their character is slower than with I's Turret plus σ-hold.

---

## 5. Concept: Engine (score 6.5 / 10)

**What it is.** GPU truth first. The root Bench scrolls. In the first 10 seconds the app times its own GPU (`MEASURING · RUN 7/18`), fills in a parity column, probes the device (`APPLE9 · PROBED`) and runs `measurePSF` on SwiftUI `.blur`. Everything on screen is a field of an immutable **Run**. The concept has eight layers (Shader and Silicon split), a Calibrate sheet with model competition, an Instrument sheet (Device, Runs with JSON export, Settings) and one-variable Compare axes.

**Strengths.**
1. **Its stance is admirable and fits the brief's honesty rules exactly:** "the app never shows a number about a GPU that it could have measured on this GPU instead" (E §0).
2. **Calibrate** (E §3.7) has real personal value to a SwiftUI developer:
   - it measures Apple's `.blur` on *his* phone;
   - it **fits competing models** (truncated Gaussian vs box³-like) and shows which wins, which settles a real disagreement in the research (`sdk-feasibility.md` §4 vs `live-calibration.md` §5.1) live;
   - it plots a sweep of σ/(r·scale) against r with the regime switch marked.
3. **The fingerprint "ON THIS PHONE" row and the "LOOKS MOST LIKE" classifier** (E §7.1). The app measures each blur's fingerprint from GPU output and names its nearest catalog relative. That is a delightful way to classify an unknown system blur.
4. **The one-variable Compare axes** (Operator, Implementation, Precision, Space, Apple) are the most rigorous comparison model. **Cost-match**, "what does each blur buy for 0.5 ms?", is an original and fun question.
5. **The Trace jump menu** (E §6.1): `Worst parity pixel`, `Predicted inversion ring`, `Tile boundary`. The fetch table shows bilinear `t` as requested and as the hardware quantizes it (t 0.4941 → 0.4922 at 8 bits).
6. **The Silicon page** (dispatch overlay on a copy, pass timeline with MODELED ghost bars, measured roofline, compression A/B) is the deepest GPU layer of the three. It matches `gpu-pipeline.md` §5 items 2–9 nearly one for one.

**Weaknesses.**
1. **The first impression is a lab warming up, not a blur.** He sees a grey star, a status line counting runs, and placeholder slots `‹0.__›`. The concept itself names the risk "The app reads as a spec sheet" (E §14 R12). For a toy maker, that is the wrong first 10 seconds.
2. **The image is tap-only, and the centre is set by a `Centre` toggle in the status row** (E §9.1): a mode switch where a drag is expected. There is no pan, pinch or loupe. Its long press opens Trace, which is useful but not playful.
3. **Root-screen density.** Below the fold come more telemetry, pass tiles, a four-tab signal lab with a sweep button, a fingerprint card and an 8-tile descend grid. That is a lot of engineering on the root before any wonder.
4. **Its strongest features have the narrowest audience.** The Run log, roofline and compression A/B are excellent but secondary to the ask. He asked to see how blurs work and what makes each unique, not for a GPU benchmarking suite.
5. **Switching blurs** goes through a chip or prev/next. σ-matching exists only inside the Operator compare axis.

---

## 6. Scores

| Concept | Score | One-line reason |
|---|---|---|
| **Instrument** | **8.5** | The concept he would love on first touch and keep playing with, and the best answer to "what makes each blur unique". Its depth is hidden on the root screen. |
| **Descent** | **8.0** | The most faithful to "every layer" and the closest to his Loom feedback (a numbered pipeline with real numbers). Too still and tap-only to delight on its own. |
| **Engine** | **6.5** | The most rigorous honesty and a superb Calibrate. It opens like a benchmark, and its best parts are side trips. |

---

## 7. Winner

**Instrument is the chassis**, with Descent's rail, divergence and trace mechanics grafted in, and Engine's measurement core running quietly underneath.

Why Instrument and not Descent, given that Descent scores higher on clause 3:
- Delight decides whether he reaches clause 3 at all.
- Descent's best feature, the rail, transplants cleanly into the Instrument Bench: it fits the 60-pt telemetry slot, and the Bench gives up nothing else (graft G4).
- Instrument's best features cannot be transplanted into Descent's scrolling Lab: the drag, pan, pinch and loupe on the image, and the non-scrolling Bench that makes them possible. Metro's own touch rule forbids owning drags on the whole image inside a scroll view (`metro-adaptation.md` §C.1 "Touch").

So the merged design should start from Instrument and import Descent, not the reverse.

---

## 8. Graft list: what the final design must include

Each item names its source concept and section. Items are in priority order within each group.

### A. The root experience (from Instrument, with one Descent transplant)

- **G1. Non-scrolling Bench with direct manipulation of the image** (I §2, §4).
  - Tap places the probe. Drag moves a handle when the touch starts within 22 pt of one, otherwise it pans the specimen. Pinch zooms 1–8× nearest-neighbour. Long press opens an **opaque Metal loupe** that prints the centre texel's value.
  - The image becomes scrollable, with gestures handed over to controls, only at accessibility text sizes or below 402 pt width.
- **G2. First launch: Night City HDR, Gaussian σ 12, wipe at 50 %, one 600 ms focus pull, then stillness** (I §1).
  - One coaching line, shown once, in the fixed status row.
  - The Siemens star is a lesson specimen, never the first frame.
- **G3. Turret glyph strip plus σ-hold on switch** (I §3.1, §8.1).
  - The hero dozen comes first. Every blur that runs live on the GPU (Tiers 1, 2 and S) is one tap away.
  - The status row reports the conversion (`σ HELD 12.0 px → R 26.3 px`), and a `MATCH σ` switch can turn σ-hold off.
- **G4. Descent's rail on the Bench, replacing the three-cell telemetry row** (D W1, §11.2 item 2).
  - Seven chips, each the probe's live answer on that floor: SLIDE (in his home tool's units) · API (σ px) · MATH (class) · KERNEL (taps) · ALGO (passes) · GPU (**MEASURED ms**, so the honesty spine survives) · PIXEL (**LIVE** out value).
  - Each chip carries a glyph badge and a full spoken label.
  - Tapping a chip opens that layer page.
  - In Compare, the chips show `=` / `≠`, and the first `≠` is amber with a ▶ marker.
- **G5. The primary button names the pixel:** `Descend from (453, 447)`, which replaces "Trace a pixel" (D §2 rule 1). The first thing he reads is a coordinate, not an instruction.
- **G6. The probe tap reveals shift invariance through the rail:** for LSI blurs only GPU and PIXEL change (D §2, 4–6 s). Pair this with **pan as the shift-variance toy:** mip snapping, dual-Kawase shimmer and the pixelate grid (I §3.3).
- **G7. On-image handles with accessible twins:** zoom, spin and god-ray centre; tilt-shift band; iris ellipse; and **Paint · Pan for path blur**, with Descent's preset-path menu as the accessible alternative (I §4 "Handles", D §10.2 path-blur row).

### B. The descent and the trace

- **G8. Seven layer pages under a pinned live periscope** (I §3.4).
  - Each page frames its content as Descent's question about the probe ("What would you type…", "Which thread computed it…"; D §6.0).
  - Each page has one governing rule, one figure, at most six badged numbers, and an `All … details` disclosure.
  - Keep seven floors, matching the seven-stage pipeline he chose for Loom. Engine's Shader / Silicon split becomes two tabs inside the GPU floor (E §3.4).
- **G9. A trace that steps per floor, per pass and per fetch, with a growing running-sum bar** (I §6 items 4–5; D §7 `Completed`/`Next`/Σ). It must include:
  - **branches, not forks**: the alternative OUT greyed beside the real one, e.g. `if sRGB-encoded: 115/255` (D §7);
  - a **one-sentence lesson** on the last step (D §6.1–§6.4 endings);
  - `Descend another pixel`.
- **G10. Honest trace values:** a `TRACE_PROBE` function-constant build of each Tier 1 shader that records the probe's taps, with a parity test against the untraced build and `BlurCore` (D §15 R2). Combine it with Engine's readback of real intermediates per pass (E §6.2 item 4).
- **G11. Engine's trace details** (E §6.1, §6.2 item 3):
  - the jump menu: `Worst parity pixel`, `Predicted inversion ring`, `Tile boundary`, `Corner` for zoom and spin;
  - the fetch table with bilinear `t` as requested and as hardware-quantized.

### C. What makes each blur unique

- **G12. The Instrument fingerprint card** (I §7):
  - fixed layout;
  - a four-glyph strip (PSF, STAR, EDGE, |H|) at σ-held size;
  - six rows (PSF shape, |H|, edges, cost, artifacts, used in);
  - the **unique number**;
  - the **kurtosis ID axis**;
  - **TELL · Show me**;
  - **nearest neighbours**, one tap to a wipe.

  Add Descent's **PARTS WAYS WITH** line, naming the floor where it diverges from each neighbour (D §8.1), and Engine's **ON THIS PHONE** measured row and **LOOKS MOST LIKE** classifier (E §7.1).
- **G13. A Divergence view in Compare and in the Catalog:** "the floor where two blurs part ways", with the reason in one line (D W6, §9 table).
- **G14. A Fingerprints matrix tab in the Catalog** (LSI · SEP · ISO · H≥0 · EDGE · COST · PSF/MTF glyphs). Every cell is spoken as words. Tapping two rows opens Compare (D W5).

### D. Comparison

- **G15. Four in-window compare modes: Wipe, Flip, Difference (gain detents ×1/×16/×256) and Line-up 2×2** (I §8.2). Disable Flip's alternation under Reduce Motion, as E does.
- **G16. Compare states what is held and what varies.** Use Engine's axis vocabulary (Operator · Implementation · Precision · Space · Apple) as the B-source menu. Default the Operator axis to σ-match, and offer **cost-match** ("what does each blur buy for 0.5 ms?") (E §8).
- **G17. Lessons: CATALOG's 30 pairs (P1–P30) as one-tap presets**, each with its "look for" number in the status row (I §8.2, D W8). Add Descent's **four guided descents**, which have the best titles in the documents. P26 (SwiftUI `.blur` vs Gaussian vs box³, measured on his phone) is the flagship lesson.

### E. The WYSIWYG floor and Apple's own blurs

- **G18. "What would you type in each tool" plus reverse mode "you typed 10"** (D §6.1 floor 1, §9 "Same typed number"), with a **home tool** setting (D W9), so the SLIDE chip speaks SwiftUI points by default.
- **G19. The Calibrate sheet with model competition and the σ/(r·scale) sweep** (E §3.7).
  - `measurePSF` of SwiftUI `.blur` runs **quietly after the Bench is idle** on first launch (E §1, deferred).
  - The SwiftUI crown's semantic stop sits at the **device-measured** regime switch. Use the hollow INFERRED marker (about 1.7–1.8 pt) until the device measures it.
- **G20. A "This phone" device card that upgrades badges in place and shows both values for a session** (D W10, §11.2 item 6; E §3.8). It runs in the background after idle, never as the first impression.
- **G21. The Liquid Glass exhibit, with a draggable native glass shape over a SwiftUI-drawn specimen**, wiped against the MODELED reconstruction and labelled `INFERRED` (I §3.10).

### F. Smaller delights worth keeping

- **G22. Controls that teach:**
  - the spin crown's semantic detents at 360°/n_c, where the star vanishes (I §9);
  - disabled odd blade counts with the zonogon reason;
  - `σ > 56 · SWITCHED TO PYRAMID` as an announced lesson;
  - the `CORNER GAP 4.08 PX · GHOSTS` sampling warning in the status row.
- **G23. Tapping a pass tile shows that pass's intermediate texture** in the specimen or periscope. The half-blurred horizontal streak is "the money shot" (I §5.1 L5; E §3.2).
- **G24. A Run log with JSON export** behind the Instrument / Settings sheet (E §4.2). It costs little, serves the research loop, and satisfies his engineering curiosity without touching the root screen.

---

## 9. Must avoid

- **M1. Never open on a measuring screen, a progress counter or `‹0.__›` placeholder slots** (E §1). Device probes and calibration run after the Bench is idle. Until a value exists, the GPU chip shows `–.––`.
- **M2. Never use a grey test chart as the first frame.** The Siemens star, zone plate and checkerboards are lesson specimens, not the welcome.
- **M3. Never make the image tap-only.** A scrolling root where the specimen cannot be dragged, panned, pinched or inspected kills the toy (D §5, E §6.1). Never set a centre through a mode toggle (E §9.1).
- **M4. Never hide the layers on the root screen.** The seven floors must be visible as live values from the Bench (graft G4), not only behind a button or below a fold.
- **M5. Never let a switch change size silently.** Without σ-hold, a switch confounds size with character and teaches nothing.
- **M6. No lecture walls.** At most six badged numbers per page, one figure and one rule, with everything else in disclosures. No 3,000-pt scroll of fixed cards on the root.
- **M7. No metaphors he has to decode in on-screen copy.** Internal names (Turret, Periscope, Bench) must not become UI jargon that needs explaining (Loom lesson). Use plain words: "Blurs", "Layers", "Compare", "Descend from (x, y)".
- **M8. No large persistent bottom controls, no tab bar, and at most three floating buttons** (AssemblerToy rejection; QuantumToy and Los Alamos cut-off controls; `metro-adaptation.md` §F.1, §F.3).
- **M9. No glass, `Material` or `.blur` over the specimen or a plot, and no glass loupe.** The only exception is the labelled Liquid Glass exhibit (Specimen rule, `metro-adaptation.md` §C.1).
- **M10. No idle animation, autoplay, onboarding carousel, splash or tips.** One focus pull on first launch and one coaching line, once.
- **M11. No number without a badge. An UNVERIFIED figure never appears as a number**, only as words (I §10 rule 2, D §11.1). Simulator GPU timings are never shown.
- **M12. No gesture-only controls.** Every crown, handle, divider and painted path has a native, accessible twin.
- **M13. No dead toys on the Bench.** Tier 3 entries live in the Catalog atlas only. A Turret glyph must always produce a live GPU image.
- **M14. No trace values recomputed on the CPU and presented as LIVE GPU values** (D §15 R2).
- **M15. Never show the root screen as a benchmarking suite.** Rooflines, compression A/B and run logs belong on the GPU floor and in the Instrument sheet, not on the Bench.

---

## 10. Open risks to delight (for the synthesis and build)

| # | Risk | Why it matters for delight | What to do |
|---|---|---|---|
| R1 | Six gestures on one 298-pt square | If the wrong gesture wins, the toy feels broken rather than alive | Use I §14 R2's priority order. Test on his phone with held and edge touches during redraw. Blurs declare whether pan means anything. |
| R2 | Adding the rail to a Bench budgeted with 22 pt to spare | The layout might not fit | The rail (52 pt) replaces the 60-pt telemetry row. GPU ms moves into the GPU chip. Verify on device; the 59/34-pt safe areas are UNVERIFIED (`metro-adaptation.md` §G.2 item 2). |
| R3 | Heavy blurs miss 120 Hz while a crown turns | Laggy crowns kill the tactile feel | Use a half-resolution preview while turning, labelled `PREVIEW ½` (`gpu-pipeline.md` §4.2), and full resolution on release. |
| R4 | About 45 abstract glyphs | He may not find the blur he wants | Hero dozen first, long-press shows names, `[All]` opens a searchable Catalog, and the housing caption always names the current blur. |
| R5 | A live camera specimen is excluded by all three concepts | Given Gyre (mic, EMF), a "blur my room live" specimen would likely delight him | It needs a permission prompt, and the brief prefers prompt-free inputs. Not in v1. Raise it with him as a later decision; do not add it silently. |
| R6 | The build runs overnight with no human review | Nobody checks taste before code exists | Keep this verdict's graft list and must-avoid list as acceptance checks in the synthesis. The first device screenshot should be checked against §1 of I. |

<!-- STATUS: COMPLETE -->
