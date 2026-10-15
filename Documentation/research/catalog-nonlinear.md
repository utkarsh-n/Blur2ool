# Blur2ool research: nonlinear, edge-preserving and composite UI blurs

Status: COMPLETE (all sections A1–A17, B1–B12, C–F filled; probes in Part D).
Date: 13 October 2026. Author: research agent (nonlinear/composite catalog).
Binding brief: `Documentation/BRIEF.md`. Honesty labels used below: LIVE, MEASURED, COMPUTED, MODELED, REFERENCE, INFERRED, plus UNVERIFIED for claims I could not check.

## 0. Scope, conventions and the "is it a true blur?" test

Sibling files: linear shift-invariant blurs (box, Gaussian, Kawase, IIR, ...) are in `catalog-lsi.md`; directional, lens and spatially varying blurs in `catalog-spatial.md`; what each tool's "radius" means in `stack-semantics.md`; Metal patterns in `gpu-pipeline.md`; device measurements in `live-calibration.md`. This file reuses their conventions (Fourier in cycles/pixel, Nyquist 0.5, kernels normalized to sum 1, `G_σ(x) = exp(−x²/2σ²)` written unnormalized when used as a weight).

**Notation.** `f` input image, `g` output, `p`, `q` pixel positions, `f_p` the value (scalar or RGB vector) at `p`, `N(p)` a window around `p`, `|·|` a norm (absolute difference for grey, Euclidean distance for colour unless stated). `W_p` is a normalizer that makes weights sum to 1.

**Why this family has no single MTF.** A linear shift-invariant (LSI) blur is fully described by one PSF `h` and one transfer function `H`. Every filter in Part A is either nonlinear (bilateral, guided, median, Kuwahara, diffusion, NLM, mean shift, morphology) or shift-variant (pixelate), so `G ≠ H·F` for any fixed `H`. What the app can show instead (all LIVE):

1. **The local "PSF" at a probe pixel**: for any filter whose output is a weighted average `g_p = Σ_q w_pq f_q` (bilateral, joint bilateral, NLM, guided filter written in its kernel form, Kuwahara with its winning sector, diffusion), the weight map `w_p·` *is* the effective PSF at `p`. It changes from pixel to pixel and depends on the image. Drawing it on top of the image at a dragged probe point is the single most revealing visualization of an edge-preserving filter.
2. **An amplitude-dependent transfer function** `T(ν, A)`: feed a sinusoid of frequency ν and amplitude A, measure the output amplitude at ν. For an LSI blur `T` does not depend on A. For edge-preserving filters it does: the bilateral filter behaves like its spatial Gaussian for small A (A ≪ σ_r) and like the identity for large A (A ≫ σ_r). A 2-D heat map of `T(ν, A)` is the honest replacement for an MTF plot (COMPUTED by probe `amp_transfer.py`, Part D).
3. **The edge-spread function at several contrasts**: a step edge of height 0.05, 0.2 and 1.0. A linear blur gives the same shape scaled; an edge-preserving filter keeps the large step sharp and smooths the small one.

**"Is it a true blur?" test.** The brief asks to label which entries are true blurs. This file uses five tests:

- (T1) **Convex average**: each output value is a weighted average of input values with non-negative weights that sum to 1. Consequence: no new extrema (the output stays in `[min, max]` of the window), no halos, constants are preserved.
- (T2) **Low-pass on average**: the expected output has less high-frequency energy than the input (total variation does not increase for the 1-D cases where that can be stated).
- (T3) **Linear**: `F(a f1 + b f2) = a F(f1) + b F(f2)`.
- (T4) **Shift-invariant**: shifting the input shifts the output.
- (T5) **Data-independent weights**: the weights do not depend on the pixel values.

A **true (LSI) blur** passes all five. The app should use these verdict labels:

| Verdict | Meaning | Members in this file |
|---|---|---|
| ADAPTIVE BLUR | T1, T2, T4 pass; T3 and T5 fail (weights depend on the image) | bilateral and its grid/separable approximations, joint bilateral, guided filter (approximately; see A6), domain transform, Kuwahara family, Surface Blur, Smart Blur, anisotropic diffusion, non-local means, mean-shift filtering |
| TRUE BLUR | all five pass | heat equation (isotropic diffusion = Gaussian), the blur stage inside every composite UI material |
| RANK FILTER (smoothing, not averaging) | output is one of the input values chosen by order; T2, T4 pass; T1 passes in the weak sense (output inside window range) | median, percentile filters |
| NOT A BLUR (contrast entry) | fails T2 or moves edges | min/max (dilate/erode), open/close; unsharp mask and high pass (anti-blur); difference-of-Gaussians (band-pass) |
| BLUR IN EXPECTATION ONLY | each realization is a random permutation of input pixels (histogram preserved, no averaging); only the average over noise realizations is an LSI blur whose PSF equals the displacement distribution | noise-displacement "frosted glass", Diffuse, Spread, Jitter |
| RESAMPLER | linear, low-pass then nearest-neighbour upsample, periodically shift-variant; adds new high frequencies at block edges | pixelate / mosaic, crystallize, pointillize |
| COMPOSITE | a true blur plus colour operations (saturation, tint, luminance clamp, noise, refraction) | all of Part B except B3 (vibrancy, a blend) and B9–B12 |
| BLUR-DERIVED | uses a blur to build something that is not a blur | bloom, unsharp mask, DoG/XDoG, drop shadow (a blurred alpha mask, offset and tinted) |

**Property glossary used in each "Key properties" line**: linear, shift-invariant (SI), separable, isotropic, positive weights, semigroup (`F_s∘F_t = F_{s+t}`), idempotent (`F∘F = F`), edge-preserving (a large step stays a step), maximum principle (output within local input range), monotone (preserves order: `f1 ≤ f2 ⇒ F(f1) ≤ F(f2)`), self-dual (commutes with negation `f → 1 − f`).

**Test images used below** (all procedural, per the brief): impulse, impulse grid, step edge at several contrasts, step edge plus Gaussian noise ("noisy step", the canonical edge-preserving test), Siemens star, zone plate, checkerboard, text, night-city point lights, salt-and-pepper noise field, and a smooth ramp (shows staircasing/terracing in bilateral and mean shift).

## Part A. Nonlinear and edge-preserving smoothing

### A1. median — Median filter

**id** `median`. **Aliases:** median filter, 50th-percentile rank filter, order-statistic filter; Photoshop *Filter > Noise > Median* (Radius) and *Dust & Scratches* (a median with a Threshold); GIMP *Median Blur*; ImageMagick `-statistic Median`; OpenCV `medianBlur`; Core Image `CIMedianFilter` (fixed 3×3, D2); Metal `MPSImageMedian` (D1). **Family:** rank (order-statistic) filters. Verdict: RANK FILTER.

**Definition.** `g_p = median{ f_q : q ∈ N(p) }`, the middle value of the window after sorting. Generalization: the percentile filter `g_p = P_α{f_q}`; α = 0 is erosion (min), α = 1 is dilation (max), α = 0.5 is the median (A15). Colour: either a **per-channel** median (cheap, can output an RGB triple that does not occur in the window) or a **vector median** `g_p = argmin_{f_q} Σ_{q'} |f_q − f_q'|` (Astola, Haavisto & Neuvo 1990, "Vector median filters", Proc. IEEE 78(4)), which always returns an existing colour. The **weighted median** repeats each sample by an integer weight before sorting (Brownrigg 1984).

**Parameters.** Window shape and size: square `w×w` with `w = 2r+1`, or a disc of radius r (rounder corners, closer to isotropic). Photoshop and OpenCV call r or w "radius"/"ksize"; `MPSImageMedian.kernelDiameter` is w (odd only). The window size sets the **largest feature that is deleted**, not a spread σ: a median of width w deletes any bright or dark structure narrower than about w/2 (COMPUTED by `edges.py`: a 5×5 median deletes a 2-px line and keeps a 3-px line). There is no σ and no "equivalent Gaussian".

**Discrete construction.** Odd sample count makes the median unique; with an even count, implementations take the lower middle or the mean of the two middles (unspecified per tool, UNVERIFIED). Edge handling: replicate, reflect or shrink the window at the border; `MPSImageMedian` uses the kernel's `edgeMode` (REFERENCE, MPS headers).

**Frequency response.** None (nonlinear). A useful replacement: the median **commutes with every monotone non-decreasing intensity map** φ: `median(φ(f)) = φ(median(f))`. Consequences: (1) its response to a sinusoid does not depend on amplitude (COMPUTED by `amp_transfer.py` for a 7×7 median on a horizontal sine: gain 0.908, 0.724, 0.447 at ν = 0.05, 0.1, 0.2 cycles/px, identical for amplitudes 0.01 to 0.3, while a sharp sinusoid's peaks get clipped flat); (2) it gives the same result in gamma-encoded sRGB and in linear light (the sRGB transfer curve is monotone), a property no averaging blur has (COMPUTED from the commutation identity; holds per channel for a per-channel colour median, not for a vector median).

**Key properties.** Nonlinear; shift-invariant; **not separable** (a row median followed by a column median is a different filter, the "separable median" of Narendra 1981); isotropic only with a disc window; monotone; self-dual (for odd counts); positive in the weak sense (output is one of the input samples, so no new grey levels, no overshoot, no halo); **not idempotent** but repeated application converges to a **root signal** (in 1-D, every signal made of constant runs of length ≥ r+1 and monotone segments is a root: Gallagher & Wise 1981, "A theoretical analysis of the properties of median filters", IEEE TASSP 29(6)). **Edge-preserving:** an ideal step is a root, so it passes unchanged. **Impulse rejection:** the median of a window with fewer than half outliers ignores them (breakdown point 50%). The **impulse response is zero**: a single bright pixel is deleted. **Corner rounding:** a square's corner pixel loses its vote (COMPUTED: 5×5 median turns the corner pixel of a 20×20 square from 1 to 0).

**Algorithms and cost per pixel (window w×w).**
- Sort: O(w² log w). Quickselect: O(w²) average.
- Sorting/selection networks for small fixed windows: 3×3 needs 19 compare-exchange (min/max) operations with the classic "opt_med9" network (Paeth 1990, *Graphics Gems*, "Median finding on a 3×3 grid"; Devillard 1998 notes). On a GPU this is branch-free min/max on registers (McGuire 2008, "A fast, small-radius GPU median filter", *ShaderX6*). Adams 2021 ("Fast median filters using separable sorting networks", ACM TOG 40(4), SIGGRAPH 2021) sorts columns once and shares the sorted columns between neighbouring output pixels, merging them with pruned sorting networks; it is reported as the fastest approach for small-to-medium windows on CPUs and GPUs (exact complexity and crossover sizes are in the paper and were not re-checked: UNVERIFIED).
- Running histogram (Huang, Yang & Tang 1979, "A fast two-dimensional median filtering algorithm", IEEE TASSP 27(1)): slide the window, remove one column of w values and add one column: O(w) per pixel for 8-bit data.
- **Constant time** (Perreault & Hébert 2007, "Median filtering in constant time", IEEE TIP 16(9)): keep one 256-bin histogram per image column; moving right, update one column histogram (remove the top pixel, add the bottom one, O(1)) and add/subtract whole column histograms to the kernel histogram (O(256) bins, constant in w). The median is found by scanning the cumulative histogram. With 2-tier (16+256) histograms and SIMD the cost is independent of radius; the paper reports that it beats Huang's O(r) method above r ≈ 7 (REFERENCE). It is exact for 8-bit data only; float data need quantization.
- Weiss 2006 ("Fast median and bilateral filtering", SIGGRAPH 2006, ACM TOG 25(3)) gets O(log r) per pixel by sharing histograms across many columns.

**GPU implementation.** Small windows (3×3, 5×5): load the window (9 or 25 fetches, or a threadgroup tile with an r-pixel apron so each texel is fetched once per tile), then a min/max network in registers. Large windows: histogram or bit-plane binary search (for 8-bit data, 8 passes each counting how many window values have the current bit prefix; each pass is a box count, which a SAT or running sum makes O(1)). `MPSImageMedian` (8-bit only, max diameter 127 on the Mac GPU, D1) is the Apple-provided route; its algorithm is not documented (INFERRED: probably histogram-based for large windows).

**Visual fingerprint.** (1) Salt-and-pepper noise disappears completely instead of being smeared into grey blobs (COMPUTED: 10% salt-and-pepper on flat grey, 3×3 median max error 0.000; Gaussian σ = 1 max error 0.183; 3×3 box 0.222). (2) An **impulse grid vanishes**: the PSF is empty. (3) Edges stay sharp, corners round off, lines thinner than w/2 vanish, so text loses its thin strokes and serifs abruptly rather than softening. (4) Photos turn "painterly": flat, blotchy plateaus with crisp boundaries. (5) On a Siemens star the spokes do not fade to grey; they stay full-contrast until they are narrower than w/2, then merge into irregular blotches. Best test images: **salt-and-pepper on text** and an **impulse grid**.

**Where used.** Despeckling scans and video, removing cosmic-ray hits in astronomy, Photoshop Median and Dust & Scratches, `CIMedianFilter`, `MPSImageMedian`, OpenCV `medianBlur`, depth-map cleanup in computational photography (INFERRED, common practice).

**Signature.** "It votes instead of averaging: a lone bright pixel loses the vote and vanishes, while an edge wins on both sides and stays sharp."

### A2. bilateral — Bilateral filter

**id** `bilateral`. **Aliases:** bilateral filter, Gaussian bilateral, SUSAN-style edge-preserving smoothing (Smith & Brady 1997 introduced a near-identical filter), "Surface Blur" in Photoshop (A10, INFERRED), `cv::bilateralFilter`. **Family:** adaptive weighted average (non-linear "edge-aware" filters). Verdict: ADAPTIVE BLUR.

**Definition** (Tomasi & Manduchi 1998, "Bilateral filtering for gray and color images", ICCV 1998):

`g_p = (1/W_p) Σ_{q∈N(p)} G_σs(‖p − q‖) · G_σr(|f_p − f_q|) · f_q`,  `W_p = Σ_q G_σs(‖p − q‖) · G_σr(|f_p − f_q|)`.

`G_σs` is the **domain (spatial) kernel**, `G_σr` the **range kernel**. Tomasi and Manduchi measured colour distance in CIE-Lab so that the range kernel matches perceived difference; most implementations use RGB or luma. The **effective PSF at p** is the product of a Gaussian bump and a mask of "pixels that look like p".

**Parameters.**
- `σs` (pixels): spatial reach, the same meaning as the Gaussian σ. Window radius r ≈ 2σs to 3σs.
- `σr` (intensity units, e.g. 0.1 of full scale, or 25 on 0–255): **the edge threshold**. Steps much larger than σr are kept; variations much smaller are smoothed as by a Gaussian of σs. Limits: σr → ∞ gives Gaussian blur with σs; σr → 0 gives the identity. A step of height Δ is blurred across with relative weight `exp(−Δ²/2σr²)`: 0.61 at Δ = σr, 0.135 at 2σr, 0.011 at 3σr (COMPUTED).
- Durand & Dorsey 2002 ("Fast bilateral filtering for the display of high-dynamic-range images", SIGGRAPH 2002) use σs ≈ 2% of image size and σr = 0.4 in log10 luminance for HDR tone mapping (REFERENCE).

**Discrete kernel.** Sample `G_σs` on the integer grid over a square or disc of radius r = ⌈2σs⌉ to ⌈3σs⌉; compute `G_σr` per neighbour (exp, or a lookup table indexed by |Δ| for 8-bit data); normalize by `W_p` **per pixel** (this division is what makes it adaptive). Edge handling: as for Gaussian (mirror is best; renormalization comes free because `W_p` is computed anyway, so "skip out-of-image samples" is natural).

**Frequency response.** None. The amplitude-dependent transfer `T(ν, A)` (§0) shows the mechanism (COMPUTED, `amp_transfer.py`, σs = 3, σr = 0.1): at ν = 0.1 cycles/px the gain is 0.178 at A = 0.01 (almost the Gaussian's 0.168), 0.214 at A = 0.03, 0.524 at A = 0.1 and 0.930 at A = 0.3. **Small wiggles are blurred like a Gaussian; large ones pass.** At ν = 0.2 the Gaussian passes 0.000 but the bilateral passes 0.917 of a 0.3-amplitude wave: a strong high-frequency texture survives untouched.

**Key properties.** Nonlinear; shift-invariant; **not separable** (A4); isotropic in space if σs is isotropic; positive weights summing to 1 (maximum principle: no overshoot, no halo in the output itself); **not** a semigroup and not idempotent: iterating converges toward piecewise-constant images (Barash 2002, "A fundamental relationship between bilateral filtering, adaptive smoothing, and the nonlinear diffusion equation", IEEE TPAMI 24(6), shows it is one step of a nonlinear diffusion). Edge-preserving. Not monotone.

**Known artifacts.**
- **Staircasing / terracing** on smooth ramps: the range kernel treats the far end of a ramp as "different", so ramps break into plateaus, worse when iterated (COMPUTED, mild in one pass: on a 0→1 ramp over 64 px with noise 0.01, σs = 3, σr = 0.1, max deviation 0.008 vs Gaussian 0.002).
- **Gradient reversal** when the bilateral is used as a base layer in detail enhancement (`detail = f − bilateral(f)` amplified): near edges the base layer is too sharp, and the boosted detail overshoots with reversed gradients (He, Sun & Tang 2010/2013 §1 and Fig. 1 make this the motivation for the guided filter; REFERENCE).
- **Noisy edges stay noisy**: pixels right at an edge have few similar neighbours (small `W_p`), so they are smoothed less: the "edge halo of residual noise" (COMPUTED: residual noise sd on the flat area is 0.0039 for the bilateral vs 0.0024 for the Gaussian at σ = 3, for input noise 0.03).
- Impulses (salt-and-pepper) are **kept**: a lone outlier has no similar neighbours, so `g_p ≈ f_p`. This is the opposite of the median, and the best side-by-side contrast in the app.

**Algorithms and cost per pixel.**
- Brute force: `(2r+1)²` taps, each with one exp (or LUT), one multiply-add and one fetch. For σs = 5 and r = 10: 441 taps. Costly but trivially parallel.
- Separable approximation (A4): `2(2r+1)` taps.
- Bilateral grid / permutohedral lattice (A3): O(1) taps per pixel, independent of σs, plus grid passes.
- Constant-time methods: Porikli 2008 ("Constant time O(1) bilateral filtering", CVPR) with box spatial kernels and polynomial range kernels; Yang, Tan & Ahuja 2009 ("Real-time O(1) bilateral filtering", CVPR) with PBFIC (principle bilateral filtered image components): quantize the range into k levels, run k ordinary linear blurs, interpolate. Chaudhury, Sage & Unser 2011 ("Fast O(1) bilateral filtering using trigonometric range kernels", IEEE TIP 20(12)) expand the range kernel in raised cosines.
- Durand & Dorsey 2002: piecewise-linear in intensity plus FFT, the conceptual precursor of the grid.

**GPU implementation.** Fragment or compute shader with a 2-D loop: each tap does a fetch, a squared difference (or a colour distance), an `exp` (fast `exp2` in half precision is fine), a weight product and two accumulators (weighted sum, weight sum). Threadgroup tiling with an r apron cuts device-memory fetches to about `(T + 2r)²/T²` per output for tile size T. Practical GPU versions cap r at ~8–12 or switch to the grid. Real-time games use a small bilateral (5×5 to 9×9, often separable) to upsample or denoise SSAO and other half-resolution buffers (depth-aware "bilateral upsampling", A5).

**Visual fingerprint.** Skin and skies go smooth while eyelashes, hair and text edges stay crisp ("plastic skin"); low-contrast texture (fabric, pores) is erased but high-contrast texture survives; noise survives right next to strong edges; impulses survive; smooth gradients develop faint bands. Best test: **noisy step at three contrasts** (0.05, 0.2, 1.0) with σr between them: the 0.05 step is blurred like a Gaussian, the 0.2 and 1.0 steps stay sharp (COMPUTED by `edges.py`: 10–90% edge width 10 px for the 0.05 step, under 1 px for the 0.2 and 1.0 steps; Gaussian σ = 3 gives 8–10 px for all three). Second test: salt-and-pepper (kept).

**Where used.** HDR tone mapping base/detail decomposition (Durand & Dorsey 2002); flash/no-flash fusion (Petschnigg et al. 2004; Eisemann & Durand 2004); "beauty"/skin smoothing; cartoon/abstraction (Winnemöller, Olsen & Gooch 2006, "Real-time video abstraction", SIGGRAPH, iterated separable bilateral); OpenCV `bilateralFilter`; Photoshop Surface Blur (INFERRED, A10); Lightroom/Camera Raw noise reduction internals are not public (UNVERIFIED). Survey: Paris, Kornprobst, Tumblin & Durand 2009, "Bilateral filtering: theory and applications", Foundations and Trends in Computer Graphics and Vision 4(1).

**Signature.** "A Gaussian that refuses to average across anything that looks different from the centre pixel: smooth skin, sharp eyelashes."
### A3. bilateral-grid — Bilateral grid (and permutohedral lattice)

**id** `bilateral-grid`. **Aliases:** bilateral grid, "signal-processing approximation of the bilateral filter", fast bilateral; generalizations: permutohedral lattice, Gaussian KD-tree, bilateral guided upsampling. **Family:** algorithms for the bilateral filter (A2), and a data structure for edge-aware processing in general. Verdict: ADAPTIVE BLUR (approximates A2).

**Definition.** Paris & Durand (2006, "A fast approximation of the bilateral filter using a signal processing approach", ECCV; extended in IJCV 81(1), 2009) observed that the bilateral filter is a **linear 3-D Gaussian convolution in (x, y, intensity) space followed by two nonlinear steps**. Lift each pixel to a point `(x, y, f(x,y))` in a 3-D space with homogeneous value `(f, 1)`. Convolve that 3-D "image" with a separable Gaussian of widths (σs, σs, σr). Read the result back at `(x, y, f(x,y))` ("slicing") and divide the first component by the second. Chen, Paris & Durand (2007, "Real-time edge-aware image processing with the bilateral grid", ACM TOG 26(3), SIGGRAPH 2007) made the grid a GPU data structure. The formula is exact before discretization; the approximation comes from sampling the 3-D space coarsely.

**Parameters.** The grid's sampling rates are tied to the filter's: one cell is about `σs × σs` pixels in space and `σr` in intensity (Chen et al. use sampling rates s_s and s_r and set the blur in cells; the conventional choice is s_s = σs, s_r = σr, blur of about 1 cell). So **a bigger σs makes the grid smaller and the filter faster** — the reverse of brute force.

**Discrete construction.**
1. **Splat** (create): for every pixel, add `(f, 1)` to the cell `(round(x/s_s), round(y/s_s), round(f/s_r))` (nearest; trilinear splatting is smoother).
2. **Blur**: a small separable 3-D Gaussian (3 or 5 taps per axis) on the grid.
3. **Slice**: trilinearly interpolate `(Σwf, Σw)` at `(x/s_s, y/s_s, f/s_r)` and divide.
Grid memory: `(W/s_s)·(H/s_s)·(1/s_r)` cells × 2 channels. For a 1920×1080 image with s_s = 16, s_r = 0.1: 120 × 68 × 10 ≈ 82 k cells (COMPUTED). Edge handling: the grid is padded by a cell or two of zeros; zeros carry no weight, so borders are renormalized automatically.

**Accuracy** (COMPUTED, `grid_sep.py`, 96×96 noisy Siemens star, contrast 0.6, noise σ = 0.04, compared with brute force at the same σs, σr): s_s = 3, s_r = 0.1 (15.9 k cells): RMS error 0.0026, max 0.012. s_s = 12, s_r = 0.1 (1.6 k cells, under 0.2 cells per pixel): RMS 0.0021, max 0.008. s_s = 6, s_r = 0.2: RMS 0.0059, max 0.024. For scale, the difference between the bilateral and a plain Gaussian on the same image is RMS 0.25. Errors concentrate at strong edges where nearest-neighbour splatting quantizes intensity.

**Frequency view.** The 3-D Gaussian blur is LSI in the lifted space and its transfer function is `exp(−2π²(σs²(νx² + νy²) + σr²νf²))`; the grid exploits the fact that this kills everything above about 1/(2σ) per axis, so the grid can be sampled at the σ scale without aliasing (Paris & Durand 2009 §4). The 2-D image-domain operator still has no MTF.

**Key properties.** Same as A2 up to discretization error; cost per pixel **O(1)**, independent of σs; memory and grid-blur cost grow as σs⁻² σr⁻¹, so it degrades for **small σs or small σr** (fine grids). Colour range kernels need a 5-D grid (x, y, r, g, b), which is exponential in dimension. The **permutohedral lattice** (Adams, Baek & Davis 2010, "Fast high-dimensional filtering using the permutohedral lattice", Computer Graphics Forum 29(2), Eurographics 2010) replaces the cubic grid with a lattice whose cells are simplices: splat to d+1 vertices instead of 2^d, blur along d+1 directions, cost linear-ish in dimension. Gaussian KD-trees (Adams et al. 2009, SIGGRAPH) are another route.

**GPU implementation.** Chen et al. 2007 splatted with point primitives (a vertex shader computes the cell and additive blending accumulates `(wf, w)` into a 3-D grid stored as tiled 2-D slices), blurred with fragment passes and sliced with hardware trilinear filtering of a 3-D texture. On Metal today: (1) splat with a compute kernel using threadgroup-memory atomics per spatial cell (one threadgroup per `s_s × s_s` pixel block, so the spatial binning is a gather; only the intensity bin needs atomics), (2) three 1-D grid blurs, (3) slice from an `MTLTexture` of type 3-D with a linear sampler: **one trilinear fetch** per pixel for slicing (two values, so one RGBA16F fetch suffices for grey; colour needs `(wr, wg, wb, w)` per cell). Per output pixel: 1 read + 1 atomic add for splat, 1 trilinear fetch for slice; grid passes are negligible for large σs. The paper reports real-time (≥ 30 fps) HD rates on 2007 GPUs (REFERENCE, Chen et al. 2007 §5; exact fps not re-checked here).

**Visual fingerprint.** Same look as the bilateral, plus at coarse grids (a) slight **blockiness / trilinear "diamonds"** in smooth gradients, (b) **intensity quantization**: edges whose contrast is near one range bin can leak or bend. Best test: smooth ramp plus a low-contrast step near σr, with the grid lattice overlaid.

**Where used.** Real-time tone mapping and local contrast in Chen et al. 2007; **bilateral guided upsampling** (Chen, Adams, Wadhwa & Hasinoff 2016, ACM TOG 35(6), SIGGRAPH Asia) and **HDRnet** (Gharbi, Chen, Barron, Hasinoff & Durand 2017, ACM TOG 36(4)): a low-res grid of **affine colour transforms**, sliced at full res by the guide image, the basis of mobile real-time photo enhancement research at Google. Permutohedral lattice in dense CRFs (Krähenbühl & Koltun 2011) for segmentation. Whether Apple's camera pipeline uses grids is not public (UNVERIFIED).

**Signature.** "Lift the picture into 3-D so that brightness becomes distance, blur the 3-D cloud with an ordinary Gaussian, and slice it back: edges survive because the two sides of an edge are far apart in brightness."

### A4. bilateral-separable — Separable bilateral approximation

**id** `bilateral-separable`. **Aliases:** separable bilateral, x-y bilateral, 1-D bilateral passes. **Family:** bilateral approximation. Verdict: ADAPTIVE BLUR.

**Definition** (Pham & van Vliet 2005, "Separable bilateral filtering for fast video preprocessing", IEEE ICME 2005): apply the 1-D bilateral along x, then apply the 1-D bilateral along y to the **result** of the first pass:

`u_p = Σ_{|k|≤r} G_σs(k) G_σr(f_p − f_{p+k·ex}) f_{p+k·ex} / W`,  `g_p = Σ_{|k|≤r} G_σs(k) G_σr(u_p − u_{p+k·ey}) u_{p+k·ey} / W'`.

Because the bilateral weights are data-dependent, the 2-D kernel `w(p, q)` does **not** factor into x and y parts, so this is a different filter, not an exact factorization.

**Parameters.** Same σs, σr as A2. Variants: iterate the x-y pair 2–4 times (Winnemöller, Olsen & Gooch 2006 used separable passes for real-time video abstraction); align the two passes with the local edge tangent and gradient instead of x and y (Kyprianidis & Döllner 2008, "Image abstraction by structure adaptive filtering", EG UK TPCG), which removes most axis artifacts.

**Discrete construction, edge handling.** As A2, in 1-D.

**Frequency response.** None.

**Key properties.** Not rotation invariant (axis-aligned by construction); **pass-order dependent**: x-then-y ≠ y-then-x; a pixel can receive weight from a diagonal neighbour that is dissimilar to it, through an intermediate pixel that is similar to both, so diagonal edges leak slightly. Cost O(r) per pixel instead of O(r²).

**Approximation error** (COMPUTED, `grid_sep.py`, noisy Siemens star, σs = 3, σr = 0.1, r = 8): separable vs full RMS 0.0050, max 0.026; x-then-y vs y-then-x differ by RMS 0.0038, max 0.023. The bilateral itself differs from a Gaussian by RMS 0.25 on the same image, so the approximation preserves the character. Errors are larger for edges and textures with contrast near σr and for thin diagonal lines (Pham & van Vliet 2005 report the axis-aligned artifacts on diagonal structures; REFERENCE, magnitudes in the paper not re-checked).

**GPU implementation.** Two fragment or compute passes, `2r+1` fetches each (no bilinear tap merging is possible because each tap needs its own range weight), one `exp` per tap; with r = 8: 34 fetches vs 289 for brute force (COMPUTED).

**Visual fingerprint.** Like the bilateral, plus faint **horizontal and vertical streaks** along diagonal edges and at corners, and a slight "plus-shaped" smear around isolated features. Best test: a rotated square or a Siemens star of contrast ≈ 2σr; compare with the full bilateral and toggle pass order.

**Where used.** Real-time abstraction and stylization shaders, SSAO/denoise upsampling in games (most "bilateral blur" passes in game engines are separable, depth-weighted versions; INFERRED from common engine practice, e.g. the NVIDIA HBAO+ and Unity/Unreal SSAO blur passes, specifics UNVERIFIED).

**Signature.** "Two 1-D edge-aware passes pretending to be one 2-D filter: fast, almost right, and slightly streaky on diagonals."

### A5. joint-bilateral — Joint / cross bilateral (and joint bilateral upsampling)

**id** `joint-bilateral`. **Aliases:** joint bilateral filter, cross bilateral filter, guided bilateral, depth-aware blur, joint bilateral upsampling (JBU), edge-preserving upsampling; Core Image `CIEdgePreserveUpsampleFilter` (INFERRED to be this from its parameters `inputSpatialSigma`, `inputLumaSigma`, D2). **Family:** guided (cross) edge-aware filters. Verdict: ADAPTIVE BLUR.

**Definition.** Like A2, but the range weight is computed on a **different image** I (the guide), while the values averaged come from f:

`g_p = (1/W_p) Σ_q G_σs(‖p − q‖) G_σr(|I_p − I_q|) f_q`.

Introduced simultaneously by Petschnigg et al. 2004 ("Digital photography with flash and no-flash image pairs", SIGGRAPH; "joint bilateral") and Eisemann & Durand 2004 ("Flash photography enhancement via intrinsic relighting", SIGGRAPH; "cross bilateral"). **Joint bilateral upsampling** (Kopf, Cohen, Lischinski & Uyttendaele 2007, "Joint bilateral upsampling", ACM TOG 26(3)): f is a low-resolution solution (depth, tone map, colourization), I is the high-resolution image; `g_p = (1/W_p) Σ_{q↓} f↓_{q↓} G_σs(‖p↓ − q↓‖) G_σr(|I_p − I_q|)`, summing over low-res samples near p.

**Parameters.** σs, σr as in A2, with σr in the guide's units; guide choice (flash image, luma, depth, normals). The guide decides where edges are; f decides what is averaged. With I = f it reduces to A2.

**Key properties.** **Linear in f** for a fixed guide (`F_I(a f1 + b f2) = a F_I(f1) + b F_I(f2)`), nonlinear in I. So for a fixed guide it **is** a linear, shift-variant operator with a well-defined per-pixel PSF (the weight map), a clean teaching point: "the nonlinearity lives in the guide". Positive weights, normalized.

**Algorithms, GPU.** Same as A2 (brute force, separable, grid: the grid is splatted at the guide's intensity and carries f). JBU per output pixel: a small window (e.g. 5×5) of low-res samples, `25` low-res fetches plus `25` guide fetches.

**Visual fingerprint.** Edges in the output appear exactly where the **guide** has edges, even if f has none (or has them in the wrong place): a blurry, blocky depth map snaps to object outlines. Artifact: **texture copying**: guide texture (e.g. a pattern on a flat wall) imprints into a smooth f such as depth. Best test: blocky low-res depth of a circle, upsampled with a high-res colour guide that has the circle plus a striped texture.

**Where used.** Flash/no-flash denoising; depth upsampling for portrait-mode bokeh and AR (INFERRED for specific commercial pipelines); SSAO, volumetric fog and half-res effect upsampling in games ("depth-aware bilateral upsample"); `CIEdgePreserveUpsampleFilter` (INFERRED).

**Signature.** "Average this image, but ask that image where the edges are."
### A6. guided — Guided filter

**id** `guided`. **Aliases:** guided image filter, (fast) guided filter, local linear filter; Core Image `CIGuidedFilter` (inputGuideImage, inputRadius 1 [1, 10], inputEpsilon 1e-4 [1e-9, 0.1]; REFERENCE, `CIFilter.attributes`, probe `probe_ci_names.swift`); Metal `MPSImageGuidedFilter` (D1); OpenCV `ximgproc::guidedFilter`; MATLAB `imguidedfilter`. **Family:** guided (cross) edge-aware filters; box-filter based. Verdict: ADAPTIVE BLUR (approximately convex, see properties).

**Definition** (He, Sun & Tang 2010, "Guided image filtering", ECCV 2010; journal version IEEE TPAMI 35(6), 2013). Assume the output q is a **local linear function of the guide I** in every window ω_k of radius r centred at k: `q_i = a_k I_i + b_k` for i ∈ ω_k. Choose (a_k, b_k) by ridge regression against the input p:

`E(a_k, b_k) = Σ_{i∈ω_k} ((a_k I_i + b_k − p_i)² + ε a_k²)`
`a_k = ( (1/|ω|) Σ_{i∈ω_k} I_i p_i − μ_k p̄_k ) / (σ_k² + ε)`,  `b_k = p̄_k − a_k μ_k`,

with μ_k, σ_k² the mean and variance of I in ω_k and p̄_k the mean of p. Every pixel lies in |ω| = (2r+1)² windows, so the output averages their predictions: `q_i = ā_i I_i + b̄_i`, where ā, b̄ are box means of a, b. With a colour guide, a_k is a 3-vector: `a_k = (Σ_k + εU)⁻¹ (cov_k(I, p))`, a 3×3 solve per pixel.

**Self-guided case (I = p), the one to teach.** `a_k = σ_k² / (σ_k² + ε)`, `b_k = (1 − a_k) μ_k`. In a flat window (σ_k² ≪ ε) a ≈ 0 and the output is the **box mean**; in a high-variance window (σ_k² ≫ ε) a ≈ 1 and the output is the **input**. So **√ε plays the role of the bilateral's σr** and r the role of σs. For a window centred on a step of height Δ, σ_k² = Δ²/4, so `a = Δ² / (Δ² + 4ε)`: a step of height 2√ε is kept only halfway (COMPUTED). This soft threshold makes the guided filter a gentler edge preserver than the bilateral at the same nominal scale: `edges.py` (r = 4, ε = 0.01, i.e. √ε = 0.1) gives a 10–90% width of 6 px for a 0.2 step where the bilateral (σr = 0.1) keeps it under 1 px; both keep a 1.0 step under 1 px.

**Kernel form.** The output is linear in p for a fixed I: `q_i = Σ_j W_ij(I) p_j` with
`W_ij(I) = (1/|ω|²) Σ_{k: i,j ∈ ω_k} ( 1 + (I_i − μ_k)(I_j − μ_k) / (σ_k² + ε) )`
(He et al. 2013, eq. 19; REFERENCE). Σ_j W_ij = 1. Weights are not guaranteed non-negative: a term goes negative when `(I_i − μ_k)(I_j − μ_k) < −(σ_k² + ε)`, which happens for rare extreme values in a window with several grey levels (COMPUTED from the formula; for a two-level step the term is `ε/(σ²+ε) > 0`). So T1 holds only approximately: small overshoots are possible, unlike the bilateral.

**Parameters.** r (box radius, pixels; window `2r+1`), ε (regularizer in squared intensity units; 0.1², 0.2², 0.4² in He et al.'s figures for [0, 1] images). For `CIGuidedFilter`, inputRadius is r (max 10) and inputEpsilon is ε (default 1e-4, i.e. √ε = 0.01: strong edge preservation). MPS adds the subsampling of the Fast Guided Filter.

**Frequency response.** None in general. For a fixed guide, a shift-variant linear operator. `amp_transfer.py` (self-guided, r = 4, ε = 0.01) gives gains at ν = 0.1 of 0.017, 0.055, 0.340, 0.819 for amplitudes 0.01, 0.03, 0.1, 0.3 (COMPUTED): low-amplitude detail is removed (the underlying box filter's Dirichlet response is only ±0.111 at ν = 0.1 and 0.2), high-amplitude detail passes.

**Key properties.** **Gradient-preserving** (no gradient reversal): in each window `∇q = ā ∇I`, so q's gradients point the same way as the guide's (He et al. 2013 §3.4, the main argument over the bilateral). Not a semigroup; edge-preserving; uses only box means, hence O(1).

**Algorithms and cost per pixel.** Self-guided grey: box means of I, p, I·I, I·p (4 boxes; only 2 if I = p, since I·p = I²), then a, b, then box means of a, b (2 boxes): **about 6 box filters**, each O(1) per pixel with a SAT or running sum, independent of r. Colour guide: 3 + 1 + 6 + 3 = 13 box means for I, p, ΣII, ΣIp, then a 3×3 inverse per pixel, then 4 more boxes (COMPUTED count). **Fast guided filter** (He & Sun 2015, "Fast guided filter", arXiv 1505.00996): compute a, b on an image subsampled by s (r/s window) and bilinearly upsample ā, b̄ before applying them to the full-resolution I: cost O(N/s²) with "almost no visible degradation" for s up to 4 (REFERENCE, the paper's claim). This is exactly MPSImageGuidedFilter's "Regression" (low-res a, b texture) + "Reconstruction" (`a·I + b` at full res) split (D1).

**GPU implementation.** Pass 1: downsample I and p (optional), compute means and correlations with a separable box (sliding window or SAT), pass 2: per-pixel a, b, pass 3: box-mean a and b, pass 4: full-res `ā·I + b̄` using one bilinear fetch of the low-res coefficient texture (4 channels: a.rgb, b). Fetch count at full res: 1 guide fetch + 1 coefficient fetch per pixel (COMPUTED); everything else runs at 1/s² resolution.

**Visual fingerprint.** Smooths like a box filter in flat areas (so a slight boxy softness, not Gaussian roundness), keeps strong edges with gradients intact, leaves a **faint halo of unsmoothed noise** around very strong edges (windows that straddle an edge have large σ² and pass noise through; He et al. 2013 §7 note halos near some edges as a limitation, REFERENCE). Transfers structure from guide to output (feathering a coarse alpha matte to hair). Best test: **detail enhancement** (`p + k(p − q)` with k = 4) on a noisy step: the guided filter shows no gradient reversal where the bilateral shows the classic reversed overshoot. Second test: feather a blocky mask using a photo as guide.

**Where used.** Haze removal transmission refinement (He, Sun & Tang 2009/2011 dark channel prior); matting/feathering; HDR compression; flash/no-flash; reportedly in MATLAB, OpenCV, and Apple's `CIGuidedFilter`/`MPSImageGuidedFilter`. Apple's own use of it (e.g. Portrait mode matte refinement) is plausible but not documented (UNVERIFIED).

**Signature.** "In every small window, explain the output as a straight-line function of the guide; where the guide is flat it becomes a box blur, where it has edges it becomes a copy."

### A7. domain-transform — Domain transform (bonus)

**id** `domain-transform`. **Aliases:** domain transform filter, edge-aware recursive filter (RF), normalized convolution (NC) and interpolated convolution (IC) variants; OpenCV `ximgproc::dtFilter`. **Family:** edge-aware filters via geodesic distance. Verdict: ADAPTIVE BLUR.

**Definition** (Gastal & Oliveira 2011, "Domain transform for edge-aware image and video processing", ACM TOG 30(4), SIGGRAPH 2011). In 1-D, warp the axis so that distance includes intensity change:

`ct(u) = ∫_0^u ( 1 + (σs/σr) Σ_c |I'_c(x)| ) dx`,

then apply an ordinary **linear** 1-D filter (box, Gaussian or exponential) of width σ_H in the warped coordinate `ct`. Across an edge `ct` jumps by `(σs/σr)·Δ`, so the edge's two sides are far apart and do not mix. 2-D: alternate horizontal and vertical 1-D passes N times (N = 3 typical) with shrinking widths `σ_{H,i} = σ_H √3 · 2^{N−i} / √(4^N − 1)` so that the total variance equals σ_H² (REFERENCE, paper eq. 14; the variances add to σ_H², COMPUTED check: Σ 3·4^{N−i}/(4^N−1) = 1).

**Recursive (RF) variant.** `J[n] = (1 − a^{d_n}) I[n] + a^{d_n} J[n−1]` with `a = exp(−√2/σ_H)` and `d_n = ct(x_n) − ct(x_{n−1}) = 1 + (σs/σr)|I[n] − I[n−1]|`, run left-to-right then right-to-left (REFERENCE, Gastal & Oliveira 2011 §5.2). One multiply-add and one `pow` (or `exp`) per pixel per direction.

**Key properties.** O(1) per pixel, independent of σs; separable passes (with axis artifacts like A4, reduced by iterations); the RF variant's 1-D kernel is a two-sided exponential (Laplace) in the warped domain, so it has long tails ("infinite impulse response"), and it can leak along thin edges parallel to the pass direction. Positive weights, normalized.

**GPU.** The RF version is sequential along rows (one thread per row, or a parallel scan of the first-order linear recurrence); the NC version uses a box in the warped domain, found by binary search or a running pointer, after a prefix sum of `ct`. Runs real time on 2011 GPUs at megapixel sizes (REFERENCE, paper reports; numbers not re-checked).

**Fingerprint.** Bilateral-like look at a fraction of the cost; long, exponential tails (soft glow-like smoothing along flat areas); slight streaking along pass directions. Best test: noisy step plus a long horizontal thin line (leak along rows).

**Signature.** "Stretch the ruler wherever the image changes, then do an ordinary blur with the stretched ruler."
### A8. kuwahara — Classic Kuwahara

**id** `kuwahara`. **Aliases:** Kuwahara filter, Kuwahara–Nagao filter (Nagao & Matsuyama 1979 used 9 rotated sub-windows), "oil paint" filter in many apps (Photoshop's *Oil Paint* is a different, brush-based filter; INFERRED, its algorithm is not public). **Family:** selection-of-subregion filters. Verdict: ADAPTIVE BLUR (output is a local mean, but of a data-chosen sub-window).

**Definition** (Kuwahara, Hachimura, Eiho & Kinoshita 1976, "Processing of RI-angiocardiographic images", in *Digital Processing of Biomedical Images*, Plenum, pp. 187–202). Around pixel p take four overlapping square sub-windows Q_1..Q_4 of size (r+1)×(r+1), each having p as one corner (they share the centre row and column). Compute each sub-window's mean m_i and variance s_i². Output the mean of the sub-window with the **smallest variance**: `g_p = m_{i*}`, `i* = argmin_i s_i²`. Colour: use the sum of per-channel variances (or luma variance) to choose, then output the RGB mean.

**Parameters.** r: sub-window size r+1, total footprint `(2r+1)²`. Nothing else. Like the median, r sets the scale of features removed and the size of "paint strokes"; there is no σ.

**Discrete construction.** Means and variances of the four quadrants from box sums of f and f² (`s² = E[f²] − E[f]²`), so 2 SATs give everything in O(1). Ties (equal variances, e.g. on a perfectly linear ramp where all four quadrants have the same variance) are broken by index order, which biases the output toward one quadrant (COMPUTED by `edges.py`: on a 0→1 ramp over 64 px a r = 3 Kuwahara shifts the ramp by 1.5 px, max deviation 0.030 against the true ramp vs 0.002 for a Gaussian σ = 3). Edge handling: mirror/clamp padding.

**Frequency response.** None. Like the median, the classic Kuwahara is **invariant under affine intensity maps** `f → a f + b` (a > 0): variances scale by a², so the same quadrant wins. So its sinusoid gain does not depend on amplitude (COMPUTED, `amp_transfer.py`, r = 3: gain 1.10, 0.85, 0.23 at ν = 0.05, 0.1, 0.2 at every amplitude tested). A gain **above 1** at low frequency is unusual: it squares up a sine wave into flatter plateaus with steeper sides, so the fundamental grows. That is the mathematical root of the "painterly" look.

**Key properties.** Nonlinear, shift-invariant, not separable, not isotropic (square quadrants), edge-preserving and corner-preserving in principle (at an edge some quadrant lies wholly on one side and has the lowest variance), maximum principle holds (output is a mean). Not monotone. **Unstable under noise:** when the four variances are similar (flat noisy regions), the winner flips from pixel to pixel, so flat noisy areas turn into small square "blocks" (Kyprianidis et al. 2009 §2 cite noise sensitivity and block artifacts as its main defects; REFERENCE). Weak denoiser: the winner averages only (r+1)² samples (COMPUTED: noise sd 0.03 → 0.0076 for r = 3, vs 0.0023 for Gaussian σ = 3).

**Algorithms and cost.** Naive: 4(r+1)² reads (with overlap, (2r+1)² distinct). SAT of f and f²: 4 sub-windows × 4 corners × 2 tables = 32 fetches, O(1) in r (COMPUTED). Separable running sums also work because the sub-windows are boxes.

**GPU implementation.** One fragment pass with (2r+1)² fetches for small r (r ≤ 5), accumulating four (sum, sum²) pairs; or a SAT build (prefix-scan compute passes) plus a 32-fetch evaluation pass. Precision: `E[f²] − E[f]²` in fp16 cancels badly; use fp32 accumulators.

**Visual fingerprint.** Oil-painting flat patches with crisp boundaries; **square block artifacts** and "clustering" in flat or noisy areas; thin dark lines and corners survive better than with the median; ramps shift. Best test: noisy flat field (shows blocks) next to a Siemens star (spokes survive with blocky ends).

**Where used.** Medical imaging origin (angiocardiograms); non-photorealistic rendering ("oil paint" shaders); GIMP/G'MIC and many shader collections (INFERRED).

**Signature.** "Look in four directions, pick the calmest neighbourhood, and paint with its average colour."

### A9. kuwahara-generalized / kuwahara-anisotropic

**ids** `kuwahara-generalized`, `kuwahara-anisotropic`. **Aliases:** generalized Kuwahara (Papari, Petkov & Campisi 2007), anisotropic Kuwahara filter (AKF; Kyprianidis, Kang & Döllner 2009), multi-scale AKF (Kyprianidis 2011), AKF with polynomial weights (Kyprianidis, Semmo, Kang & Döllner 2010). **Family:** Kuwahara family. Verdict: ADAPTIVE BLUR.

**Generalized Kuwahara** (Papari, Petkov & Campisi 2007, "Artistic edge and corner enhancing smoothing", IEEE TIP 16(10)). Replace the four squares with **N sectors of a disc** (N = 8), each with a smooth weighting function `K_i` (sector indicator smoothed by a Gaussian, times a radial Gaussian). Replace the hard argmin with a **soft** combination: `g = Σ_i α_i m_i / Σ_i α_i` with `α_i = s_i^{−q}` (REFERENCE, as restated by Kyprianidis et al. 2009 §3.2). Large q approaches the hard selection.

**Anisotropic Kuwahara** (Kyprianidis, Kang & Döllner 2009, "Image and video abstraction by anisotropic Kuwahara filtering", Computer Graphics Forum 28(7), Pacific Graphics 2009; all details below REFERENCE from the paper's §3):
1. Structure tensor from Gaussian-derivative gradients of RGB: `(E, F; F, G) = (f_x·f_x, f_x·f_y; f_x·f_y, f_y·f_y)`, smoothed by a Gaussian of σ = 2.0 (not normalized, so strong edges dominate).
2. Eigenvalues `λ_{1,2} = (E + G ± √((E − G)² + 4F²))/2`; orientation φ = arg of the minor eigenvector `t = (λ1 − E, −F)`; **anisotropy** `A = (λ1 − λ2)/(λ1 + λ2)` ∈ [0, 1].
3. Ellipse: `S = diag(α/(α + A), (α + A)/α)` with α = 1 (maximum eccentricity 4), rotated by φ; the filter region is `{x : ‖S R_φ x‖ ≤ h}`, h = ⌈2σ_r⌉.
4. N = 8 sectors with weights `K_i = (χ_i * G_σs)·G_σr`, pulled back through the ellipse map; σ_r = 3.0, σ_s = 1.0 in their examples. Note Σ_i K_i = G_σr, so the sectors together form a Gaussian.
5. Weighted means m_i and standard deviations s_i per sector; output `Σ α_i m_i / Σ α_i` with `α_i = 1/(1 + ‖s_i‖^q)`, **q = 8**, values in 0–255 units (the "+1" avoids Papari's division by zero).
GPU (2009): the sector weights K_0..K_3 are pre-sampled into one RGBA texture of size (4h + 2)², so one bilinear fetch yields four weights, and ellipse symmetry halves lookups; 512×512 and DVD video at **12 fps on a GeForce GTX 280** with σ_r = 3, N = 8 (REFERENCE). N = 4 is faster with slightly less sharp boundaries.

**Parameters.** Radius (σ_r or h), sector count N, sharpness q, anisotropy tuning α, structure-tensor smoothing σ. In the app: radius and q are the user-facing sliders; α and the tensor σ are "advanced".

**Fetch count.** Per pixel ≈ (number of samples in the ellipse) × (1 image fetch + N/4 weight fetches), i.e. about `π h² · (1 + 2)` fetches for N = 8; with h = 6: ≈ 340 (MODELED). Plus the structure-tensor passes (Gaussian derivatives, tensor smoothing: separable, ~4 passes).

**Key properties.** Nonlinear, shift-invariant, **orientation-adaptive** (anisotropic by design), not separable, edge- and corner-preserving, soft selection makes it temporally stable for video without extra processing (REFERENCE claim of the paper).

**Visual fingerprint.** Brush-stroke-like smoothing **along** local edges and flow lines (hair and grass become directional strokes), crisp boundaries between colour regions, no square blocks; the classic Kuwahara's clustering disappears. Best test: a circular zone plate or a "flow" image (concentric rings): classic Kuwahara gives blocks, generalized gives round blobs, anisotropic gives strokes that follow the rings.

**Where used.** NPR and painterly video abstraction; shader packs and image-filter apps; Blender's compositor has a *Kuwahara* node with Classic and Anisotropic modes since Blender 4.0 (UNVERIFIED version number; REFERENCE-level confirmation not fetched).

**Signature.** "Kuwahara's 'pick the calmest neighbourhood', but with soft votes from eight wedges of an ellipse that turns to follow the strokes in the picture."
### A10. surface-blur — Photoshop Surface Blur

**id** `surface-blur`. **Aliases:** Surface Blur (Photoshop, *Filter > Blur > Surface Blur*, added in Photoshop CS2; version UNVERIFIED), thresholded blur, selective mean, sigma filter (Lee 1983). **Family:** bilateral variants with a truncated range kernel. Verdict: ADAPTIVE BLUR.

**What Adobe documents** (REFERENCE, paraphrased from Adobe Photoshop Elements help "Blur filters", helpx.adobe.com/photoshop-elements/using/blur-filters.html, and Adobe's Photoshop help text as quoted in the Adobe community forum): it blurs while preserving edges; *Radius* is the size of the sampled area; *Threshold* controls how far a neighbour's tonal value may diverge from the **centre pixel's** value before it is left out of the blur. (The Elements page adds a sentence saying pixels with differences **less** than the threshold are excluded, which contradicts the filter's observed behaviour and the Photoshop wording; treat it as a documentation error. UNVERIFIED which wording is current.) Parameters: Radius (pixels) and Threshold (levels, 0–255 scale). The slider ranges (Radius 1–100 px, Threshold 2–255) are from memory, UNVERIFIED.

**INFERRED definition.** The documented behaviour (average over a radius, include only neighbours whose value is within a threshold of the **centre** pixel) is the bilateral filter (A2) with (a) a spatial kernel that is flat or nearly flat over a disc/square of the given radius and (b) a range kernel that falls to zero at |Δ| = T (hard cutoff, or a linear tent): 

`g_p = Σ_{‖q−p‖≤R} w(|f_q − f_p|) f_q / Σ w`, with `w(Δ) = 1` (hard, "sigma filter") or `w(Δ) = max(0, 1 − Δ/(cT))` (tent).

That makes it essentially **Lee's sigma filter** (Lee 1983, "Digital image smoothing and the sigma filter", Computer Vision, Graphics, and Image Processing 24(2): average only the neighbours within ±2σ_noise of the centre) and the ImageJ "Surface Blur"/"Thresholded Blur" plugins, which describe themselves exactly that way. A widely copied community reverse-engineering uses the tent with c = 2.5 (`w = 1 − |Δ|/(2.5·T)`), but I could not find it in a citable source: **UNVERIFIED**. Whether the spatial kernel is flat or Gaussian-weighted is also UNVERIFIED; the app should label the whole definition INFERRED and, if the user owns Photoshop, offer to fit it from an impulse-plus-step test file (a MEASURED path outside the app).

**Parameters, physical meaning.** Radius = spatial reach in pixels (for a flat disc of radius R, σ per axis ≈ R/2; COMPUTED for a uniform disc: σ² = R²/4). Threshold = range cutoff in 8-bit levels; with the tent model of half-width cT the range kernel's standard deviation is `cT/√6` (COMPUTED: variance of a triangular density of half-width a is a²/6). Threshold at maximum (255) makes it a plain disc/box blur (consistent with Ben Willmore's CreativeLive lesson, which advises setting Threshold to maximum first so the filter acts like an ordinary blur).

**Frequency response, properties, cost, GPU.** As A2, with a flat spatial kernel (so its small-amplitude limit has the box/disc's sinc-like **negative lobes**, unlike the Gaussian bilateral; COMPUTED consequence of the inferred model) and a compactly supported range kernel (so a step larger than cT has **exactly zero** leakage, not just exp-small). A flat spatial kernel makes a **constant-time** implementation possible: Porikli 2008 and Yang et al. 2009 (A2) handle box spatial kernels with arbitrary range kernels in O(1) per pixel via range quantization and integral histograms. Brute force is `πR²` taps.

**Visual fingerprint.** Plastic, posterized-looking skin; noise removed in flat areas; edges stay razor sharp; with a flat kernel, faint **ring/box ghosts** around small bright details below threshold (the disc's MTF has negative lobes). Best test: noisy step at contrasts below and above T, plus a smooth ramp (it terraces, more strongly than the Gaussian bilateral because the range cutoff is hard).

**Where used.** Photoshop portrait retouching ("frequency separation" low layer, skin smoothing), noise reduction, cartoon look.

**Signature.** "Photoshop's bilateral: average everything inside the radius that is within Threshold levels of me, and ignore the rest."

### A11. smart-blur — Photoshop Smart Blur

**id** `smart-blur`. **Aliases:** Smart Blur (Photoshop, *Filter > Blur > Smart Blur*, since Photoshop 4/5; version UNVERIFIED), selective Gaussian blur (GIMP's *Selective Gaussian Blur* has the same two controls: blur radius and "max delta"). **Family:** thresholded (truncated-range) bilateral. Verdict: ADAPTIVE BLUR (Normal mode); NOT A BLUR (Edge Only / Overlay Edge modes, which are edge detectors).

**What Adobe documents** (REFERENCE, paraphrased from Adobe Photoshop Elements help "Blur filters" and the Adobe Photoshop CS5 JavaScript reference `SmartBlurMode`): Radius sets how far the filter searches for dissimilar pixels; Threshold sets how different pixel values must be before they are excluded; Quality sets blur quality; Mode applies the effect to the whole selection (Normal) or only to the edges of colour transitions (Edge Only draws black-and-white edges where contrast is significant; Overlay Edge draws white edges over the image). Parameters: Radius (0.1–100), Threshold (0.1–100), Quality (Low, Medium, High), Mode (Normal, Edge Only, Overlay Edge). Defaults Radius 3.0, Threshold 25.0, Quality Low, Mode Normal (third-party source, astropix.com Photoshop for Astrophotographers notes; UNVERIFIED against a current Photoshop build).

**INFERRED definition.** Normal mode: a Gaussian-weighted average restricted to neighbours whose value differs from the centre by less than the threshold (a bilateral with a **box range kernel**, i.e. GIMP's selective Gaussian blur). Edge modes: pixels where some neighbour within the radius exceeds the threshold are marked as edges and drawn white (on black for Edge Only, on the image for Overlay Edge). *Quality* most likely sets the sampling density or kernel truncation (UNVERIFIED). Adobe has not published the algorithm.

**How it differs from Surface Blur (A10).** Both are bilateral variants with thresholds. In practice Smart Blur produces **visible hard contour lines** where the threshold switches neighbours in and out (posterization-like banding with sudden steps), while Surface Blur's transitions are softer (consistent with a tent or smoother range weight; INFERRED). Smart Blur also exposes its edge map, which makes the threshold visible: the app can reproduce that as a "range mask" overlay for any thresholded bilateral.

**Visual fingerprint.** Watercolour/posterized patches with abrupt tone boundaries; outlines in Edge mode look like a binary Canny-free edge sketch. Best test: smooth ramp (hard contour lines at every threshold crossing) and a portrait.

**Signature.** "A blur with a bouncer at the door: neighbours that differ by more than Threshold are not let in, and in Edge mode it shows you exactly where the door is."
### A12. heat-equation and anisotropic-diffusion (Perona–Malik)

**ids** `heat-equation`, `perona-malik`. **Aliases:** isotropic (linear) diffusion, heat flow, Gaussian scale space; anisotropic diffusion, nonlinear diffusion, edge-stopping diffusion, Perona–Malik diffusion. True anisotropic (tensor) diffusion: edge-enhancing and coherence-enhancing diffusion (Weickert 1998). **Family:** PDE-based smoothing. Verdicts: heat equation TRUE BLUR (it *is* Gaussian blur); Perona–Malik ADAPTIVE BLUR (and edge-sharpening, see properties).

**Heat equation: definition and the σ = √(2t) identity.** `∂u/∂t = Δu = u_xx + u_yy`, `u(x, 0) = f(x)`. In Fourier space `∂û/∂t = −4π²|ν|² û`, so `û(ν, t) = exp(−4π²|ν|² t) f̂(ν)`. A normalized Gaussian of standard deviation σ has transfer function `exp(−2π²σ²|ν|²)`. Equating exponents: **`σ² = 2t`, i.e. diffusion for time t equals Gaussian blur with σ = √(2t)** (COMPUTED; classical: Koenderink 1984, "The structure of images", Biological Cybernetics 50; Witkin 1983, "Scale-space filtering", IJCAI). Convention warning: Lindeberg's scale-space papers write `∂_t L = ½ΔL`, which gives `σ² = t` instead (Lindeberg 1994, *Scale-Space Theory in Computer Vision*, Kluwer); the app should show which convention it uses.

MEASURED-in-simulation check (COMPUTED by `heat.py`, explicit 5-point scheme, Δt = 0.1, impulse input, reflecting boundary): measured σ = 1.4142, 2.0000, 3.0000, 4.0000, 5.0000 at t = 1, 2, 4.5, 8, 12.5, matching √(2t) to 4 decimals; mass conserved exactly; the shape differs from a sampled Gaussian by 4.6% of peak at t = 1, falling to 0.2% at t = 12.5 (the discrete-space heat kernel is `e^{−2t} I_n(2t)` per axis, the modified-Bessel "discrete Gaussian" of Lindeberg 1990, "Scale-space for discrete signals", IEEE TPAMI 12(3), not a sampled Gaussian).

**Heat equation properties.** Linear, shift-invariant, isotropic, positive kernel, **semigroup** (`u(t1+t2) = heat_{t2}(heat_{t1}(f))`, so σ²'s add), maximum principle, **causality** (no new level curves or extrema are created as t grows, Koenderink 1984). Edge-blurring.

**Perona–Malik definition** (Perona & Malik 1990, "Scale-space and edge detection using anisotropic diffusion", IEEE TPAMI 12(7)): `∂u/∂t = div( c(|∇u|) ∇u )` with an **edge-stopping** conductivity, one of
`c1(s) = exp(−(s/K)²)`  or  `c2(s) = 1 / (1 + (s/K)²)`.
Where the gradient is small (s ≪ K) it diffuses like the heat equation; where it is large it stops. The flux `φ(s) = s·c(s)` **decreases** for s > K/√2 (c1) or s > K (c2) (COMPUTED by differentiating), which is **backward diffusion**: edges steeper than that threshold get *sharper*. That makes the continuous problem ill-posed (Catté, Lions, Morel & Coll 1992, "Image selective smoothing and edge detection by nonlinear diffusion", SIAM J. Numer. Anal. 29(1), fix it by computing c on a Gaussian-smoothed gradient). Weickert (1998, *Anisotropic Diffusion in Image Processing*, Teubner) notes that Perona–Malik is really *inhomogeneous isotropic* diffusion (scalar c); "anisotropic" in his sense needs a diffusion tensor that smooths along edges but not across them. Black, Sapiro, Marimont & Heeger 1998 ("Robust anisotropic diffusion", IEEE TIP 7(3)) link c to robust error norms (Tukey's biweight gives a sharper stop).

**Parameters.** Stopping time t (or iterations n with t = nΔt; reported as σ_equiv = √(2t) for the small-gradient regime), contrast threshold K (gradient magnitude units: intensity per pixel), and the choice of c. Note K is a **gradient** threshold, not an intensity-difference threshold as in the bilateral's σr; with 4-neighbour differences these coincide numerically.

**Discretization.** Perona–Malik's scheme: `u ← u + λ Σ_{d∈{N,S,E,W}} c(|∇_d u|) ∇_d u` with `∇_d u` the difference to neighbour d and **λ ≤ 1/4** for stability (REFERENCE, Perona & Malik 1990 §V). Each iteration is one 5-tap pass; total time t = nλ. Semi-implicit AOS schemes (Weickert, ter Haar Romeny & Viergever 1998, "Efficient and reliable schemes for nonlinear diffusion filtering", IEEE TIP 7(3)) allow large time steps via tridiagonal solves.

**Frequency response.** Heat equation: `exp(−4π²|ν|² t)`, exactly Gaussian. Perona–Malik: none; `amp_transfer.py` (t = 4.5, i.e. σ_equiv = 3, K = 0.05) gives gains at ν = 0.2 of 0.001 for amplitude 0.01 (as the Gaussian) but 0.994 for amplitude 0.3 (COMPUTED): steep features are frozen.

**Algorithms and cost.** Heat equation: never iterate in practice; use any Gaussian (separable, IIR, pyramid) with σ = √(2t). Iterating explicitly costs `n = t/λ = σ²/(2λ)` passes of 5 taps: σ = 10 needs 200 passes (COMPUTED), against 2 passes of a separable Gaussian. Perona–Malik: n passes × (5 fetches + 4 conductivities) per pixel; σ_equiv = 3 at λ = 0.25 is 18 passes (COMPUTED).

**GPU implementation.** Ping-pong two textures, one compute dispatch per iteration with 5 fetches. Temporal blocking (several iterations per dispatch inside a threadgroup tile whose valid region shrinks by one pixel per iteration) cuts device-memory traffic by the number of fused iterations. fp16 accumulates rounding error over hundreds of iterations; use fp32 storage for long runs (MODELED risk).

**Visual fingerprint.** Heat equation: identical to Gaussian blur (the app's teaching moment is that *time is blur*: animate t and show σ = √(2t) live). Perona–Malik: flat cartoon regions with **sharpened** edges, **staircasing** (a ramp breaks into terraces, because backward diffusion steepens any gradient above threshold), isolated noise spikes with gradient > K survive as dots (the ill-posedness). Best test: **noisy step and noisy ramp side by side, as an animation in t**. On a piecewise-constant test (noisy oblique bars, noise 0.1, `nlm_ms.py`) Perona–Malik is the best denoiser in this file: PSNR 20.3 → 29.6 dB (t = 2, K = 0.15), vs bilateral 25.3 dB and Gaussian σ = 1 17.7 dB (worse than doing nothing) (COMPUTED).

**Where used.** Scale-space theory (heat equation); medical image denoising (Perona–Malik and tensor diffusion); edge detection pre-filtering; image inpainting ancestors. Few consumer apps expose it by name (G'MIC "anisotropic smoothing" does, INFERRED).

**Signatures.** Heat: "Let heat flow for time t and you get a Gaussian of σ = √(2t): blur is diffusion." Perona–Malik: "Heat that refuses to flow across steep cliffs, and even makes the cliffs steeper."

### A13. nonlocal-means — Non-local means

**id** `nonlocal-means`. **Aliases:** NL-means, NLM, patch-based denoising; OpenCV `fastNlMeansDenoising`; relatives BM3D (Dabov et al. 2007), which is a collaborative transform-domain filter, not a weighted average. **Family:** patch-similarity weighted average (denoiser). Verdict: ADAPTIVE BLUR, included as a **denoiser contrast**.

**Definition** (Buades, Coll & Morel 2005, "A non-local algorithm for image denoising", CVPR 2005; long version "A review of image denoising algorithms, with a new one", SIAM Multiscale Model. Simul. 4(2), 2005):

`g_p = (1/W_p) Σ_{q∈S(p)} exp( −‖P(p) − P(q)‖²_{2,a} / h² ) f_q`,

where P(p) is the patch (e.g. 7×7) around p, `‖·‖²_{2,a}` a Gaussian-weighted squared distance between patches, S(p) the search window (e.g. 21×21; the "non-local" ideal is the whole image), and h a filtering parameter tied to the noise level. Buades et al. 2005 used 7×7 patches and a 21×21 search window (REFERENCE). Compared with the bilateral: the similarity test compares **whole patches** instead of single pixel values, and spatial distance is **not** used (or only to bound the search).

**Parameters.** Patch size (texture scale that counts as "the same"), search size (how far it looks; cost grows quadratically), h (≈ 0.4σ_noise to σ_noise in later IPOL recommendations, Buades, Coll & Morel 2011, "Non-local means denoising", Image Processing On Line 1; exact table not re-checked, UNVERIFIED). The centre pixel's self-weight is 1 and dominates when nothing matches; implementations replace it with the maximum of the other weights.

**Frequency response.** None. NLM is not a low-pass on texture: repeated high-frequency texture is **preserved** because patches of the same texture match and average only with each other.

**Key properties.** Nonlinear, shift-invariant, positive normalized weights (maximum principle), not separable. Weights depend on patch content, so it can average pixels across the image that look alike (periodic patterns, repeated text). Adapts to any noise level through h.

**Algorithms and cost.** Naive: `|S|·|P|` operations per pixel: 11×11 search × 3×3 patch = 1 089; 15×15 × 5×5 = 5 625; 21×21 × 7×7 = 21 609 (COMPUTED). Integral-image acceleration (Darbon, Cunha, Chan, Osher & Jensen 2008, "Fast nonlocal filtering applied to electron cryomicroscopy", ISBI): for each offset d in the search window, compute the squared-difference image `(f − shift_d f)²`, build its integral image, read every patch distance with 4 fetches: O(|S|) per pixel independent of patch size (≈ 6 ops per offset, so 2 646 for 21×21; COMPUTED estimate). FFT-based and PCA-patch variants exist.

**GPU implementation.** Offset-major ordering (loop over the |S| offsets; each offset is a full-image pass: difference image → box filter (separable or SAT) → weight → accumulate into two running sums). For 21×21 that is 441 passes of O(1) work per pixel: heavy for a phone at full res, fine at preview res. Pixel-major (each thread loops over offsets and patches) works for small windows (5×5 patch, 11×11 search: 3 025 fetches per pixel, cached through threadgroup tiles).

**Visual fingerprint.** Clean flat areas *and* clean, sharp repeated textures (fabric, text, brick); low-contrast unique details can be "hallucinated away" or replaced by a similar patch's content; at too-large h, everything turns into a smooth, waxy paint. Best test: **noisy periodic texture or noisy text** where Gaussian, median and bilateral all lose detail. `nlm_ms.py` (noisy oblique bars of period 8 px, contrast 0.5, noise 0.1, input PSNR 20.3 dB): NLM 5×5 patch, 21×21 search, h = 0.1 gives 29.3 dB; with a 3×3 patch, 15×15 search, 25.3 dB; bilateral 25.3 dB; median 3×3 22.2 dB; Gaussian σ = 1 17.7 dB (COMPUTED). (On this piecewise-constant target Perona–Malik ties NLM; NLM's advantage grows on non-piecewise-constant textures, not tested here.)

**Where used.** Camera and scientific denoising, OpenCV `fastNlMeansDenoising(Colored)`, video denoisers; ancestor of BM3D and of patch priors used by modern neural denoisers. Apple's camera pipeline is neural and undocumented (UNVERIFIED for any NLM component).

**Signature.** "Average a pixel with every pixel anywhere whose *neighbourhood* looks the same, near or far."

### A14. mean-shift — Mean-shift filtering

**id** `mean-shift`. **Aliases:** mean-shift filtering, mean-shift smoothing, discontinuity-preserving mean shift; OpenCV `pyrMeanShiftFiltering`; EDISON system. **Family:** mode-seeking in the joint spatial-range domain. Verdict: ADAPTIVE BLUR (with posterizing behaviour).

**Definition** (Comaniciu & Meer 2002, "Mean shift: a robust approach toward feature space analysis", IEEE TPAMI 24(5); mean shift itself: Fukunaga & Hostetler 1975, Cheng 1995). Treat each pixel as a point `x = (x^s, x^r)` in a joint space of position and colour. For each pixel start at its own point `z_0 = x_p` and iterate the mean-shift step

`z_{j+1} = Σ_q k(‖(x^s_q − z^s_j)/h_s‖²) k(‖(x^r_q − z^r_j)/h_r‖²) x_q / Σ_q (same weights)`

until convergence; output `g_p = (x^s_p, z^r_∞)`, the **range value of the mode** the pixel's point climbs to (kernels k: uniform (Epanechnikov profile) or Gaussian). Comaniciu & Meer note that the first iteration of the Gaussian-kernel version, with the spatial component held fixed, is exactly the bilateral filter: **mean shift is the iterated bilateral where the window also moves** (REFERENCE, their §4 discussion; also Barash & Comaniciu 2004, "A common framework for nonlinear diffusion, adaptive smoothing, bilateral filtering and mean shift", Image and Vision Computing 22(1)).

**Parameters.** h_s (spatial bandwidth, pixels), h_r (range bandwidth, colour units; they use L*u*v*), and an optional minimum region size M for the segmentation step that follows. Typical in their paper: (h_s, h_r) = (8, 4) to (16, 7) in L*u*v* units with M ≈ 20–40 px for segmentation (REFERENCE values as I recall them from the paper's figures; UNVERIFIED exact pairs).

**Properties.** Nonlinear, shift-invariant, edge-preserving, positive (output is a weighted mean of input values at convergence), converges (for convex profiles the sequence of density estimates is monotone; Comaniciu & Meer 2002 Theorem 1). Pushes values toward density **modes**, so it posterizes: regions collapse to a few colours. `nlm_ms.py` with uniform kernels h_s = 4, h_r = 0.1 on a noisy 0.1 → 0.9 ramp reduces 88 distinct (0.01-rounded) levels to 68, with small plateaus forming (COMPUTED; mild at this bandwidth, much stronger at h_r near the ramp's local range).

**Cost.** Per pixel: (iterations ≈ 5–20) × (window size πh_s²) kernel evaluations. Comparable to running the bilateral 5–20 times. GPU: one thread per pixel looping until convergence; divergence between pixels hurts SIMD efficiency (MODELED). Pyramid version (OpenCV) runs on a downsampled image first.

**Visual fingerprint.** Flat poster-like colour regions with clean boundaries, stronger flattening than a single bilateral, "cel-shaded" look; thin details disappear when they do not form their own mode. Best test: smooth ramp and a photo (it terraces and segments). Neighbour contrast: bilateral = one step of averaging; mean shift = averaging until nothing changes.

**Where used.** Image segmentation pre-processing, abstraction/cartoon filters, object tracking (mean-shift tracking is a different use of the same mode seeking).

**Signature.** "Every pixel walks uphill in a joint position-and-colour histogram and takes the colour of the summit it reaches."
### A15. morphology — Min / max / dilate / erode / open / close (contrast: not blurs)

**id** `morphology` (sub-ids `dilate`, `erode`, `open`, `close`, `morph-gradient`). **Aliases:** grey-scale dilation/erosion, max/min filter, Photoshop *Other > Maximum / Minimum* (radius; "squareness"/"roundness" option in recent versions, UNVERIFIED), `CIMorphologyMaximum/Minimum` (circular, inputRadius) and `CIMorphologyRectangleMaximum/Minimum` (width × height, odd), `CIMorphologyGradient`, `MPSImageAreaMax/Min`, `MPSImageDilate/Erode`. Note: **Apple files all of these under `CICategoryBlur`** (D2), which is why the app should explain why they are not blurs. **Family:** mathematical morphology (Matheron 1975, Serra 1982, *Image Analysis and Mathematical Morphology*). Verdict: NOT A BLUR (contrast entry).

**Definitions.** Flat structuring element B (disc or square of radius r): dilation `(f ⊕ B)(p) = max_{b∈B} f(p + b)`, erosion `(f ⊖ B)(p) = min_{b∈B} f(p − b)`. Opening `f ∘ B = (f ⊖ B) ⊕ B`, closing `f • B = (f ⊕ B) ⊖ B`. Morphological gradient = dilation − erosion. Non-flat structuring function s(b): `max_b (f(p+b) + s(b))` (this is what `MPSImageDilate`'s "probe" values are). Rank-filter view: dilation and erosion are the 100th and 0th percentile filters; the median is the 50th (A1).

**Parameters.** Radius r or width × height of the structuring element; its shape (square → square-shaped growth, disc → rounded growth, line → directional).

**Why not a blur.** Fails T1 (not an average: the output is an extreme value), fails T2 in the useful sense (it **moves edges**: dilation grows bright regions by r, erosion shrinks them), is not self-dual (dilation of f ≠ inverse of dilation of inverse f; dilation and erosion are duals of each other). Total variation is not increased, and no new values are created, but no averaging happens and no amplitude is reduced. Opening and closing are **idempotent** (`(f∘B)∘B = f∘B`), which no blur is. In the max-plus algebra dilation is a "convolution" (`⊕` replaces `*`, max replaces Σ, + replaces ×), and the Legendre/slope transform plays the Fourier transform's role (Dorst & van den Boomgaard 1994, "Morphological signal processing and the slope transform", Signal Processing 38(1)); a nice aside for the math view but not needed.

**Algorithms and cost.** Naive `|B|` comparisons. Separable for rectangles (row max then column max). **Van Herk / Gil–Werman** algorithm (van Herk 1992, "A fast algorithm for local minimum and maximum filters on rectangular and octagonal kernels", Pattern Recognition Letters 13(7); Gil & Werman 1993, IEEE TPAMI 15(5)): about 3 comparisons per pixel per dimension, **independent of r**, by block-wise prefix and suffix maxima. Discs are approximated by octagons (combinations of line segments) or by decomposition into several line structuring elements.

**GPU.** Separable max/min passes with threadgroup tiles; van Herk on GPU uses per-block prefix/suffix scans (Domanski, Vallotton & Wang 2009, "Parallel van Herk/Gil-Werman image morphology on GPUs using CUDA", GTC poster; UNVERIFIED citation details). `MPSImageAreaMax/Min` are rectangular and assume clamp edges (D1).

**Visual fingerprint.** Dilation: bright shapes swell into **flat-topped, hard-edged** shapes the shape of B (a point light becomes a sharp-edged disc or square of radius r, not a soft blob); dark text thins, light text thickens. Erosion: the reverse. Opening deletes bright specks smaller than B; closing fills dark holes. No softness anywhere. Best test: night-city point lights (crisp discs) and text.

**Why the app needs it.** (1) Apple calls it a blur. (2) **Dilate-then-blur** is how real-time "bokeh" approximations make bright points into discs before a cheap blur, and how "max blur" / "glow" tricks spread highlights (INFERRED, common shader practice). (3) The median sits between them in the rank-filter family.

**Signature.** "Not a blur: every pixel takes the brightest (or darkest) neighbour, so shapes grow or shrink with hard edges instead of softening."

### A16. pixelate — Mosaic / pixelate (and hex, crystallize, pointillize)

**id** `pixelate` (sub-ids `pixelate-hex`, `crystallize`, `pointillize`). **Aliases:** mosaic (Photoshop *Pixelate > Mosaic*, cell size), pixelation, censor blocks, `CIPixellate` (inputScale, inputCenter), `CIHexagonalPixellate`, `CICrystallize` (Voronoi cells), `CIPointillize` (dots). **Family:** block-average resamplers. Verdict: RESAMPLER (not a true blur).

**Definition.** Tile the plane with cells C_k of size B (squares, hexagons or Voronoi cells of seed points). `g(p) = (1/|C_k|) Σ_{q∈C_k} f(q)` for p ∈ C_k: the **cell mean**, held constant across the cell. Equivalently: box prefilter of width B → sample at cell centres → nearest-neighbour (zero-order hold) reconstruction. Variants sample one pixel (the cell centre) instead of averaging, which aliases badly.

**What Core Image does** (MEASURED on this Mac, `probe_pixellate.swift`, 64×64 linear float image, scale/radius 8): `CIPixellate` returns **exactly the cell mean** (a 1-px checkerboard becomes uniform 0.50; a ramp's 8-px blocks become 0.11, 0.37, 0.63, 0.89, the means of the ramp values in each block). `CIHexagonalPixellate` also averages (checker → 0.48–0.50) with interpolated values at hexagon boundaries. `CICrystallize` and `CIPointillize` do **not** return the cell mean (checker region cell values 0.26–0.40, not 0.50), so they sample a filtered image at the seed rather than averaging the cell (INFERRED from the measurement). `inputCenter` sets the grid phase.

**Parameters.** Cell size B (pixels), grid origin/phase, cell shape. A Gaussian with σ ≈ B/√12 has the same per-axis variance as the box prefilter (COMPUTED), but the output is not blurred: it is blocky.

**Frequency response.** Linear, but **periodically shift-variant** (cyclostationary with period B), so there is no single transfer function: shifting the input by less than B does not shift the output by the same amount. Its spectrum is `sinc(Bν)·F(ν)` **replicated** at multiples of 1/B (from sampling) and multiplied by the hold's `sinc(Bν)`: it removes content above 1/(2B) partly and **adds new high frequencies** (the block edges and aliased replicas). In the "blur test" sense it fails T2 and T4.

**Key properties.** Linear, mean-preserving per cell, not shift-invariant, idempotent (pixelating a pixelated image with the same grid changes nothing), positive weights. Not edge-preserving and not smooth: introduces hard edges along the grid.

**Algorithms, GPU.** Per pixel: compute the cell index, read the cell mean. Two passes: (1) reduce each cell to its mean (a mip level for power-of-two B: one fetch from mip level log2 B of an auto-generated mipmap gives the exact 2×2-box-cascade mean; for arbitrary B, a compute reduction or a B×B box via SAT, 4 fetches), (2) a full-res pass with 1 fetch per pixel (nearest sampler). Total ≈ 1 read + 1 write per pixel (COMPUTED). Hex and Voronoi cells need a nearest-seed search (3–9 candidate seeds per pixel).

**Visual fingerprint.** Hard-edged squares; moving the image under a fixed grid makes cells **flicker** (shift variance); a step edge becomes a staircase; fine text becomes unreadable blocks while faces remain partly recognizable from block means. **Not a secure redaction**: averaging is linear and low-dimensional, so known-content attacks can recover text and faces from mosaics (Hill, Zhou, Saul & Shacham 2016, "On the (in)effectiveness of mosaicing and blurring as tools for document redaction", PoPETs 2016(4); McPherson, Shokri & Shmatikov 2016, "Defeating image obfuscation with deep learning", arXiv 1609.00408). Best test: text and a slowly panning Siemens star.

**Where used.** Censorship/redaction (insecurely), retro "pixel art" effects, `CIPixellate`, Photoshop Mosaic, video face obfuscation.

**Signature.** "Not a blur but a coarser grid: each block shows its average, and the block edges add sharpness the original never had."

### A17. frosted-glass-noise — Noise-displacement "frosted glass" / diffuse / spread

**id** `frosted-glass-noise`. **Aliases:** random-offset (jitter) sampling, "frosted glass" shader, GIMP *Noise > Spread* and *Pick*, ImageMagick `-spread`, Photoshop *Stylize > Diffuse* (Normal, Darken Only, Lighten Only, Anisotropic modes) and *Distort > Glass* (texture "Frosted"); `CIGlassDistortion` (displaces by a texture, inputScale 200 [0.01, 500]) and `CIDisplacementDistortion` (displacement image, inputScale 50) given a noise texture. **Family:** stochastic resamplers. Verdict: BLUR IN EXPECTATION ONLY.

**Definition.** `g(p) = f(p + D_p)`, where D_p is a random offset drawn independently per pixel from a distribution P(d) (uniform square of half-width a, uniform disc, or Gaussian of σ), or from a fixed noise texture (deterministic but pseudo-random). With a smooth displacement texture (CIGlassDistortion with a smooth bump map), it is a refraction/warp, not a blur at all.

**Expectation and variance (the key math, COMPUTED).** Over the noise: `E[g(p)] = Σ_d P(d) f(p + d) = (P̃ * f)(p)` with `P̃(d) = P(−d)`: the **expected output is exactly an LSI blur whose PSF is the offset distribution**. Uniform square offsets → box blur of width 2a+1; Gaussian offsets → Gaussian blur of the same σ. And `Var[g(p)] = E_P[f(p+D)²] − (E_P[f(p+D)])²`: the **local variance of the image under P**. So flat regions get **zero** noise; noise appears only where the image varies within reach a.
Checks (`frosted.py`, step edge, uniform offsets a = 4): the mean of 2 000 realizations matches a 9×9 box blur to 0.031 (Monte-Carlo error ≈ 0.011 per pixel); the per-column variance of one realization matches `p(1 − p)` of the box-blurred step (0.11, 0.19, 0.21, 0.23, 0.25, ... vs predicted 0.10, 0.17, 0.22, 0.25, 0.25); with Gaussian offsets σ = 3 the mean edge profile matches the Gaussian edge-spread function to ±0.01.

**Single realization.** Each output pixel is an input pixel: **no new grey levels** (a black/white step stays strictly black/white), the histogram is resampled from the input (exactly preserved if the offsets form a permutation, as in a "swap" spread), and high-frequency energy goes **up**, not down: energy above 0.25 cycles/px is 8.4% of the total for one realization vs 2.0% for the input and 1.1% for the box blur (COMPUTED). Fails T1 and T2 per realization; passes them in expectation.

**Parameters.** Offset distribution and its scale (a, or σ). For integer offsets uniform on {−a, …, a} per axis, the expected PSF has per-axis `σ² = a(a+1)/3` (COMPUTED: variance of a discrete uniform of width 2a+1 is ((2a+1)² − 1)/12); a = 4 gives σ ≈ 2.58 px. Noise frequency (per-pixel white noise vs a smooth noise texture: smooth noise gives "wobbly glass" refraction, white noise gives "sandblasted"). Temporal behaviour: static noise vs re-seeded each frame (the latter averages over time to a true blur, the basis of **stochastic blurs in path tracers and TAA-resolved effects**).

**GPU.** One fetch per pixel at an offset read from a blue-noise or white-noise texture: the **cheapest "blur" in the catalog** (1 noise fetch + 1 image fetch, no passes). Blue-noise offsets (Ulichney 1993 dithering heritage; real-time blue-noise practice, e.g. Wolfe et al. 2022, "Spatiotemporal blue noise masks", EGSR) make the error less visible and easier for TAA or a small denoise blur to remove. Many "frosted glass" UI shaders combine 4–16 jittered taps averaged together, which moves the result toward the expected blur (variance falls as 1/taps) (MODELED).

**Visual fingerprint.** Sparkly, sandblasted dither along edges; flat areas untouched; text becomes "sprinkled" but its colour stays pure; at a distance (or after a small Gaussian) it looks like the corresponding box or Gaussian blur. Best test: **step edge and text**, with a toggle to average N realizations live (the app can show convergence to the expected PSF as N grows).

**Where used.** Photoshop Diffuse and Glass (Frosted), GIMP Spread, ImageMagick `-spread`, "frosted glass" shader-toy style UIs, Windows Acrylic's noise layer is **additive** noise, not displacement (B6), so it is a different thing that shares the name "frosted".

**Signature.** "Every pixel is swapped with a random neighbour: no pixel is averaged, yet the average over many throws is exactly a blur."

## Part B. Composite UI blurs (the WYSIWYG layer)

Part B describes the materials that designers meet first (the WYSIWYG layer) and decomposes each into the primitive blurs of this file and `catalog-lsi.md`. Every material here is a **pipeline**; the app should show it as a stack of stages, with the one true blur stage highlighted.

### B1. backdrop-blur — The generic backdrop ("frosted glass") pipeline

**id** `backdrop-blur`. **Aliases:** frosted glass, glassmorphism, background blur (Figma, Sketch), backdrop filter, material, translucency. **Family:** COMPOSITE (true blur + colour operations). Verdict: COMPOSITE.

**Definition (the common skeleton).** For a panel P over a backdrop image B (everything already drawn behind P):

`out(p) = Composite_P( T( C( U_k( G_σ * D_k(Capture(B, P ⊕ margin)) ) ) ) (p) ), then content on top`

1. **Capture**: render the region behind P, enlarged by a margin of about the blur support, into an offscreen texture. This is what makes backdrop blurs expensive: everything behind must be finished before P can be drawn, which forces an extra render pass and breaks the GPU's single-pass tile rendering (see `gpu-pipeline.md` §1.3).
2. **Downsample** by k (Apple: k = 4 for system materials, 8 for legacy styles and macOS materials, 2 for Liquid Glass; Android window blur: 4; Acrylic: not downsampled in the effect graph, INFERRED). This is a cheap prefilter, cuts the blur's pixel count by k², and multiplies the effective blur radius by k.
3. **Blur** with a normalized, positive, usually Gaussian kernel (Apple `gaussianBlur`; Win2D `GaussianBlurEffect`; Android Kawase or Gaussian; CSS `blur()`), with an edge policy (Apple `inputNormalizeEdges = 1`: renormalized edges; CSS: mirror; Acrylic: hard border).
4. **Colour stage** (point operations, no spatial extent): saturation boost (Apple 1.1–2.2), brightness offset, luminance remapping or clamping (Apple iOS `luminanceCurveMap`; macOS lighten/darken floor layers; Acrylic's luminosity blend), tint overlay (source-over with a semi-transparent colour), noise (Acrylic 2% texture; Apple `inputDither`).
5. **Upsample** (bilinear) and **composite** inside P's shape (corner radius, clip), then draw P's content, often with **vibrancy** (B3).

**Why a saturation boost.** Averaging many different colours pulls chroma toward grey (the mean of red and green is a dull olive), so a plain blur of a colourful backdrop looks washed out. A saturation matrix `c' = L + s(c − L)` with s > 1 (L = luminance) restores vividness; it is linear in c, so it **commutes with the blur** (blur-then-saturate = saturate-then-blur up to clipping at 0 and 1; COMPUTED: both are linear and the blur acts per channel with weights summing to 1, so it preserves the luminance-chroma split). Nonlinear stages (luminance curves, clamps, lighten/darken blends) do not commute, so their order matters.

**Effective σ in full-resolution pixels** (MODELED, assuming box downsampling and bilinear upsampling): `σ_eff² ≈ (k² − 1)/12 + (k·σ_blur)² + k²/6`, where σ_blur is the blur's σ in downsampled pixels; for k = 4 the resampling terms add only ≈ (1.25 + 2.67) px², negligible next to (4σ_blur)². So "radius 30 at 1/8 scale" would be a very large blur (σ in the hundreds of device pixels) **if** 30 were in downsampled pixels; the unit is UNVERIFIED (Part F), and the app should present the measured σ, not this number.

**Linear or not.** Stages 1–3 and the saturation/brightness/tint parts of 4 are linear (affine) in the backdrop; luminance curves, floors and clamps are not. So a material is "a true blur followed by an affine colour map", plus a few nonlinear contrast guards. It is shift-invariant only while the backdrop moves by multiples of k pixels: with point-sampled downsampling, slow scrolling **shimmers** (aliasing from step 2), which is why implementations use filtered downsampling and dithering (Apple `inputDither = 1`; INFERRED purpose).

**Cost per output pixel** (MODELED): capture = full redraw of the region behind (usually the dominant cost); downsample ≈ 1 bilinear fetch per *low-res* pixel per 2× level; blur at 1/k² resolution (for k = 4, a 2-pass 33-tap Gaussian costs about 66/16 ≈ 4 fetches per full-res pixel); upsample = 1 bilinear fetch per full-res pixel; colour stage = ALU only.

**Visual fingerprint.** Shapes behind the panel become soft colour fields with no detail; colours look **more** vivid than the backdrop (saturation boost); bright and dark backdrops are pulled toward the material's luminance band so text on top stays legible; at the panel's edge the blur does not darken (edge renormalization or mirror) and content just outside the panel may or may not bleed in (Apple captures with a margin; CSS mirrors to prevent bleed). Best tests: **scroll text or a Siemens star under the panel** (shimmer, effective σ); **saturated stripes** (saturation boost); **white and black halves** under one panel (luminance clamping).

**Signature.** "Copy what is behind, shrink it, blur it, make it more colourful, pull its brightness into a safe band, and lay it under the panel."

### B2. apple-uiblureffect — UIVisualEffectView / UIBlurEffect / SwiftUI Material / CABackdropLayer

**id** `apple-uiblureffect`. **Aliases:** `UIVisualEffectView` + `UIBlurEffect(style:)` (iOS 8+; system material styles iOS 13+), SwiftUI `Material` (`.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`, `.thickMaterial`, `.ultraThickMaterial`, `.bar`; iOS 15+), AppKit `NSVisualEffectView` (`material`, `blendingMode` `.behindWindow` / `.withinWindow`, `state`), private `CABackdropLayer` / `UICABackdropLayer`. **Family:** COMPOSITE. Verdict: COMPOSITE (true Gaussian blur + colour stage).

**What Apple documents (REFERENCE, Apple Developer Documentation for UIVisualEffectView, UIBlurEffect, UIBlurEffect.Style, Material, NSVisualEffectView).** A blur effect blurs the content layered behind the view; styles name materials of different thickness and their light/dark adaptation; the effect view must not have alpha below 1 itself or in a superview, or the effect renders incorrectly (UIVisualEffectView documentation, section on setting the correct alpha value); when the user enables **Reduce Transparency** (`UIAccessibility.isReduceTransparencyEnabled`), materials are replaced by opaque colours. No radius, σ, saturation or tint value is documented anywhere: everything numeric below is INFERRED.

**Recipes observed (INFERRED, from private layer trees; D4 for macOS 27, D6 for iOS 27).**
- iOS system materials: backdrop captured at **1/4 scale**; `luminanceCurveMap` (amount 0.5–0.88), `colorSaturate` 1.1–2.0, `colorBrightness` (+0.045 to +0.12 in light appearance), `gaussianBlur` radius **22.5 / 29.5 / 29.5 / 45 / 22.5** (ultraThin / thin / regular / thick / chrome), renormalized edges, dithered. No separate tint layer.
- iOS legacy styles (`.light`, `.extraLight`, `.dark`, `.regular`, `.prominent`): **1/8 scale**, `gaussianBlur` radius 30 (light) or 20, `colorSaturate` 1.8, then a tint layer (white α 0.30; 0.97 α 0.80; 0.11 α 0.73).
- macOS materials: **1/8 scale**, `sdrNormalize`, `gaussianBlur` radius 30 for every blurring material, `colorSaturate` 1.6–2.4, a grey tint layer, a lighten (dark mode) or darken (light mode) **floor/ceiling** layer, and a 5–8% `CAChameleonLayer` (INFERRED: wallpaper-tinted).
- SwiftUI `Material` on iOS maps onto the system material styles (INFERRED: the SwiftUI names mirror the UIKit system styles; `.ultraThickMaterial` and `.bar` mappings UNVERIFIED).
- SwiftUI `.blur(radius:)` is a **different** effect: a layer blur of the view's own content, not of the backdrop (see `stack-semantics.md` §3.1 and `live-calibration.md` §5.1 for its measured σ).

**Math, stage by stage.** (1) Capture at scale s ∈ {1/4, 1/8}: a downsample whose prefilter is not documented (bilinear or box; INFERRED). (2) `luminanceCurveMap`: a point map on luminance, `Y' = mix(Y, curve(Y), amount)`, curve given by 4 values (INFERRED reading, D6). (3) `colorSaturate(s)`: `c' = Y + s(c − Y)` (INFERRED to be the standard saturation matrix; the luma weights are UNVERIFIED). (4) `colorBrightness(b)`: `c' = c + b` (INFERRED). (5) `gaussianBlur(r)`: Gaussian of radius r with `inputNormalizeEdges` (divide by the in-bounds weight, so no dark rim) and `inputDither`. (6) Bilinear upscale and composite. The blur is the only spatial stage. Since iOS dark ultra-thin maps luminance into roughly [0.24, 0.39] at 50% strength, a white wallpaper and a black wallpaper produce backdrops much closer in brightness than the originals: that is a **contrast compressor**, the nonlinear part of the material (COMPUTED from the D6 values, given the INFERRED reading of the curve).

**Unit of `inputRadius`.** Not documented. Candidates: points of the layer, device pixels, or pixels of the downsampled capture. They differ by factors up to 12 on a 3× display at 1/4 scale. **UNVERIFIED**; the app should measure the effective σ live: place a `UIVisualEffectView` over a known step-edge or impulse-grid image, capture with `drawHierarchy(in:afterScreenUpdates:)` (whether this captures backdrop effects faithfully on device is itself UNVERIFIED) or with a screenshot via `UIScreen` APIs, and fit σ (method as in `live-calibration.md` §3.3).

**GPU and render server.** Backdrop layers are composited by the system render server (backboardd on iOS, WindowServer on macOS) rather than by the app: the app's layer tree declares a `CABackdropLayer` and the server performs capture, filtering and compositing (INFERRED from the private class names and from `windowServerAware`, `disablesOccludedBackdropBlurs`, `groupName` properties in D3; `groupName` lets several backdrop layers share one capture). Cost is not measurable from inside the app except through frame timing (MEASURED via `CADisplayLink` jitter / Instruments; see `gpu-pipeline.md` §4).

**Visual fingerprint.** Thicker materials: bigger blur **and** stronger luminance compression; thin materials: smaller blur, more of the backdrop's own brightness and colour; legacy `.light`: a white veil (30% white) over a radius-30 blur; macOS: the same blur for all materials, differing only in tint and floor. Best test: the app's "material ladder": the same wallpaper (colour stripes + text + a white/black split) under all five system materials and all legacy styles, with the fitted σ and the measured luminance band printed under each (LIVE/MEASURED).

**Where used.** Every iOS navigation bar, tab bar, sheet, Control Center, Notification Center (pre-Liquid-Glass), macOS sidebars, menus and popovers.

**Signature.** "Apple's frosted glass: one Gaussian blur on a quarter-size copy of what is behind, then a saturation boost and a luminance squeeze that keep text readable on any wallpaper."
### B3. apple-vibrancy — UIVibrancyEffect and NSVisualEffectView vibrancy

**id** `apple-vibrancy`. **Aliases:** vibrancy, vibrant content, `UIVibrancyEffect(blurEffect:style:)` with styles `.label`, `.secondaryLabel`, `.tertiaryLabel`, `.quaternaryLabel`, `.fill`, `.secondaryFill`, `.tertiaryFill`, `.separator` (iOS 13+); `NSView.allowsVibrancy` inside an `NSVisualEffectView`; SwiftUI foreground styles on materials (`.foregroundStyle(.secondary)` over a `Material` is rendered vibrantly; INFERRED). **Family:** compositing (blend modes), not a blur. Verdict: NOT A BLUR, but part of every material; included because it is what makes text "belong" to the glass.

**What Apple documents (REFERENCE, UIVibrancyEffect / NSVisualEffectView documentation, paraphrased).** Vibrancy makes content placed over a blur effect take on colour from the content behind it; it is meant for labels, symbols and fills, and must be used with a matching blur effect.

**What it is (MEASURED on macOS 27, `probe_vibrancy_mac.swift`, INFERRED-class evidence from the private layer tree).** In a sidebar `NSVisualEffectView`, vibrant subviews (an `NSTextField` with `secondaryLabelColor`, and a view with `allowsVibrancy = true` filled with `labelColor`) are given a **compositing filter**: `plusL` (**plus-lighter**) in dark appearance and `plusD` (**plus-darker**) in light appearance. `labelColor` resolves to white at α 0.898 (dark) and black at α 0.698 (light) for the vibrant view. Liquid Glass content uses `vibrantColorMatrix` filters instead (D5), and the CAFilter catalogue also has `vibrantDark` / `vibrantLight` (D3), which iOS's `UIVibrancyEffect` presumably uses (INFERRED; the iOS vibrancy probe hung in the headless simulator, so this is not observed on iOS).

**Math.** Premultiplied colours, source S (content), destination D (blurred, tinted backdrop):
- plus-lighter: `R = min(1, S + D)` per channel.
- plus-darker: `R = max(0, S + D − 1)` per channel (Core Graphics `kCGBlendModePlusDarker`, REFERENCE: Apple `CGBlendMode` documentation; equivalently `1 − min(1, (1−S) + (1−D))`).
So dark-mode vibrant white-ish text **adds** brightness to the backdrop instead of covering it: where the backdrop is reddish, the text is a pale red, where it is bluish, a pale blue. Light-mode vibrant text **subtracts** brightness from a light backdrop. Both are point operations: no spatial extent, no blur.

**Why it matters for the app.** It is the last stage of the material pipeline (B1 step 5) and explains why text on Apple materials looks tinted by the wallpaper. Contrast is guaranteed jointly by the luminance squeeze of the material (D6) and the clamp in the plus-lighter/plus-darker blend.

**Visual fingerprint.** Labels on a material subtly change hue as colourful content scrolls behind them; secondary labels look "etched" rather than grey. Best test: scroll saturated stripes behind a material with vibrant text, compare against the same text drawn normally.

**Signature.** "Not a blur: the text on the glass is added to (or subtracted from) the blurred backdrop, so it borrows the colour of whatever is behind it."
### B4. liquid-glass — Apple Liquid Glass (iOS 26 / 27)

**id** `liquid-glass`. **Aliases:** Liquid Glass (introduced at WWDC25, June 2025, across iOS 26, iPadOS 26, macOS Tahoe 26, watchOS 26, tvOS 26, visionOS 26); SwiftUI `.glassEffect(_:in:)` with `Glass.regular` / `.clear` / `.identity`, `.tint(_:)`, `.interactive()`, `GlassEffectContainer(spacing:)`, `glassEffectID(_:in:)`; UIKit `UIGlassEffect(style:)`, `UIGlassContainerEffect`; AppKit `NSGlassEffectView`, `NSGlassEffectContainerView`; internal codename "Solarium" (D6, INFERRED). **Family:** COMPOSITE, but mostly **refraction** (a resampler), not blur. Verdict: COMPOSITE (small true blur + spatially varying displacement + colour stage + highlights + shadow).

**What Apple has published (REFERENCE: WWDC25 session 219 "Meet Liquid Glass"; Apple Human Interface Guidelines, "Materials"; Apple Developer Documentation for `glassEffect`, `Glass`, `UIGlassEffect`).**
- The defining optical behaviour is **lensing**: the session says earlier materials "scattered light" while Liquid Glass bends, shapes and concentrates light in real time. Appearing and disappearing are animated by modulating the light bending, not by fading.
- **Highlights** respond to the shape's geometry and to device motion; touched elements "illuminate from within".
- **Shadows** grow more opaque over text and lighter over plain light backgrounds; larger elements cast deeper shadows.
- **Adaptivity**: small elements (tab bars, nav bars) flip between light and dark according to what is behind them; larger ones (menus, sidebars) adapt without flipping. Larger elements simulate a **thicker** material with more pronounced lensing and refraction and "a softer scattering of light".
- **Variants**: *regular* (adaptive, works at any size over any content) and *clear* (permanently more transparent, no adaptive behaviours, needs a **dimming layer** behind it for legibility; use only over media-rich content with bold, bright content on top). The variants should not be mixed. Tinting generates a range of tones mapped to the brightness of the content underneath.
- Accessibility: Reduce Transparency makes the glass "frostier" (more blur/opacity), Increase Contrast adds borders; Reduce Motion tones down effects (session 219 and HIG).
- `GlassEffectContainer` lets nearby glass shapes **merge** and morph into each other (shape blending), which on macOS is implemented with signed-distance-field layers (`CASDFLayer`, `mergeElements`, D3/D5; INFERRED).

**What is blur and what is refraction (INFERRED from the macOS 27 recipe, D5; iOS could not be dumped, D6).**
- **Blur (true LSI blur):** a Gaussian of radius **5** (regular) or **≈ 8.6** (clear) on a backdrop captured at **1/2 scale**, against radius 22.5–45 at 1/4–1/8 scale for classic materials. So Liquid Glass blurs roughly an order of magnitude less (in σ) than the materials it replaced (MODELED, assuming the same radius unit). Five distance/opacity pairs (`inputBlurOpacity0..3`, `inputBlurDistance*`) make the blur's strength vary with distance from the shape's edge: a **spatially varying** (not shift-invariant) blur, weaker (opacity 0.55) in the outer band for regular glass.
- **Refraction (a resampler, not a blur):** `inputInnerRefractionAmount` −50 (regular) / −60 (clear) over `inputInnerRefractionHeight` 20 from the SDF edge. Modeled as a displacement `g(p) = B(p + d(p))` with `d(p) = A · φ(D(p)/H) · n̂(p)`, where D is the signed distance to the shape's edge, n̂ the SDF gradient (edge normal), H the bevel height, A the amount, and φ a falloff that is 1 at the edge and 0 deeper than H (INFERRED model; the exact φ and the sign convention are UNVERIFIED). Thin-lens intuition: a glass slab with a rounded bevel of height profile h has ray displacement roughly proportional to ∇h, so content near the rim is **compressed or magnified** and the interior is undistorted. A displacement map preserves sharpness: it **moves** detail instead of averaging it, so it fails T1 and T2 (it is a resampler, like A16/A17).
- **Chromatic aberration** (`inputAberration*`): per-channel displacement amounts, so the rim shows faint colour fringes (INFERRED, keys only; values in D5 not recorded per channel).
- **Colour stage:** "face colour matrix" with saturation 1.2–1.3 (regular) or 1.0 (clear), white/black points (brightness and contrast), max luma; a **blur-fill** layer (radius 8) blended with darken (dark mode) or lighten (light mode) at 0.675; **bleed** (amount 35, height 35 for regular: backdrop colour bled inward from the rim, INFERRED); `inputMaxHeadroom` 1.2 (EDR highlights up to 1.2× SDR white).
- **Specular "key fill highlight":** amount 0.5 (regular) / 0.4 (clear), spread 120° / 75°, angle 90° (from the top): an **additive** rim light computed from the SDF normal (INFERRED), motion-responsive on iOS (REFERENCE: session 219).
- **Shadow and ring shadow:** a blurred, offset mask of the shape (B9) under the glass.
- **Luma tracking for the light/dark flip:** `CABackdropLayer.tracksLuma` and `lumaUpdateRate` (D3) and the `averageColor` CAFilter type suggest the backdrop's average luminance is measured continuously to drive the flip (INFERRED).

**Key properties.** Not shift-invariant (everything depends on distance to the shape's edge); mostly not a low-pass (refraction keeps detail sharp); the blur stage is LSI but spatially weighted; nonlinear colour stage (darken/lighten blends, clamps, EDR). Rendered by the system compositor through SDF layers and a backdrop layer at half resolution (D5).

**GPU sketch for the app** (MODELED cost, one fragment pass after a half-res capture and a small separable Gaussian): per pixel 1 SDF evaluation (analytic rounded-rect SDF: a few ALU ops), 1 displaced bilinear fetch (3 with per-channel aberration), 1 fetch of the blurred half-res backdrop, colour matrix, highlight from the SDF gradient and a light direction. The blur itself costs about 2 × 9 taps at half resolution for radius ≈ 5 (σ small), i.e. ≈ 4.5 fetches per full-res pixel. Refraction is cheap; capture is the expensive part, as for every backdrop effect.

**Visual fingerprint.** The interior of a glass button is **only lightly blurred** (text behind it is often still half-legible), while the **rim bends** the background: straight lines behind the glass curve near the edge, a checkerboard shows compressed squares around the border, colours fringe slightly, and a bright crescent highlight sits at the top. Merged glass shapes flow into each other like liquid. Best test: a **checkerboard or grid** scrolled behind a rounded rectangle (refraction band, compression, aberration), plus text (light blur), plus a black/white split (adaptive flip and dimming).

**Where used.** iOS/iPadOS/macOS 26+ system chrome: tab bars, toolbars, sidebars, controls, the Lock Screen clock, app icons (layered "glass" icons).

**Signature.** "Less frosting, more lens: a light blur in the middle and a refracting, highlighted rim that bends the world behind it."

### B5. css-backdrop-filter — CSS backdrop-filter

**id** `css-backdrop-filter`. **Aliases:** `backdrop-filter: blur(20px) saturate(180%)`, "glassmorphism" (the 2020-era design trend name), `-webkit-backdrop-filter`. **Family:** COMPOSITE (filter list applied to the backdrop). Verdict: COMPOSITE; its `blur()` stage is a TRUE BLUR.

**Definition (REFERENCE).** Filter Effects Module Level 2, "backdrop-filter": the user agent copies the **Backdrop Root Image** under the element into a buffer, applies the filter function list to it, clips it to the element's border box (with border-radius), draws the element (its own background, usually a semi-transparent colour, provides the tint) on top, and composites source-over. If the list contains `blur()`, edges use **edgeMode = mirror** relative to the element's clipped box, so nothing outside the element bleeds in and the edge does not darken. Backdrop Root: the backdrop only includes content up to the nearest ancestor that is a backdrop root (filters, opacity < 1, masks, clip-path, mix-blend-mode, backdrop-filter). Details and citations in `stack-semantics.md` §1.4.

**Filter functions used in materials (REFERENCE, Filter Effects Module Level 1, W3C).** `blur(<length>)`: "the passed parameter defines the value of the standard deviation to the Gaussian function", so **σ = the value** in CSS px. `saturate(<number|percentage>)`: amounts over 100% are allowed ("super-saturated"). `brightness()`, `contrast()`, `grayscale()`, `hue-rotate()`, `opacity()`, `drop-shadow()`: all point operations except `blur` and `drop-shadow`. The list "is applied in the order provided". Filter functions **operate in sRGB** (gamma-encoded) space; `color-interpolation-filters` has no effect on them. So CSS blurs gamma-encoded values (bright highlights shrink, dark halos appear), unlike the linear-light blur recommended in `catalog-lsi.md` §0.

**The usual recipe and its math.** `background: rgba(255,255,255,0.6); backdrop-filter: saturate(180%) blur(20px);` = Gaussian σ = 20 CSS px (= 60 device px on a 3× phone), saturation ×1.8, then a 60% white tint by the element's own background. Because `saturate()` is a linear colour matrix and `blur()` acts per channel with weights summing to 1, the two commute except for clipping at 0 and 1 (COMPUTED; clipping happens for super-saturation of already vivid colours, so in practice `saturate(180%) blur()` and `blur() saturate(180%)` differ slightly on saturated content because the clip happens before vs after averaging). `brightness()` with a factor is linear too; `contrast()` is affine; all commute with blur up to clipping.

**Implementations.** Chrome: the compositor (cc) creates a render surface for the backdrop and runs a Skia Gaussian (downsampled for σ > 4 per `stack-semantics.md` §2.2); Safari: Core Animation backdrop layers on Apple platforms (INFERRED); Firefox: WebRender, shipped by default in Firefox 103 (2022; from MDN browser-compatibility data as I recall, UNVERIFIED).

**Cost and GPU.** As B1, with the browser's Gaussian. Many stacked backdrop-filter elements each force a separate capture (a known performance trap).

**Visual fingerprint.** No downsampling-specific look at small σ; at large σ, Chrome's downsampled blur may show slight blockiness while scrolling (UNVERIFIED); mirrored edges mean content at the very edge of the panel is reflected rather than pulled in from outside, so a bright object just outside the panel does **not** glow into it (unlike some native implementations). Best test: a bright object placed just outside the panel's edge.

**Where used.** Web "glass" UIs, apple.com's navigation bar (which uses a saturate + blur backdrop; exact current values UNVERIFIED), dashboards and landing pages.

**Signature.** "The web's frosted glass: a real Gaussian with σ equal to the number you typed, in sRGB, mirrored at the edges, then whatever colour filters you list, in order."
### B6. windows-acrylic — Fluent Acrylic

**id** `windows-acrylic`. **Aliases:** Acrylic material, `AcrylicBrush` (UWP/WinUI 2, WinUI 3), `DesktopAcrylicBackdrop` / `DesktopAcrylicController` (background acrylic for a whole window), in-app vs background acrylic. **Family:** COMPOSITE. Verdict: COMPOSITE (true Gaussian blur + luminosity/colour blends + additive noise).

**What Microsoft documents (REFERENCE, Microsoft Learn "Acrylic material", updated 2 Oct 2026).** The published recipe diagram lists five layers: **background, blur, exclusion blend, color/tint overlay, noise**. The page explains the design intent: translucency, blur and noise for depth; an exclusion-blend layer for contrast and legibility; a colour tint for personalization. Two blend types: **background acrylic** (shows the desktop and other windows; used for transient surfaces such as menus and flyouts) and **in-app acrylic** (blurs the app's own content). Acrylic falls back to a solid colour when transparency effects are off, in Battery Saver, on low-end hardware, and (background acrylic only) when the window is inactive or on Xbox/HoloLens/tablet mode. Rendering acrylic is described as GPU-intensive.

**What the code does (REFERENCE, WinUI 3 source, `microsoft/microsoft-ui-xaml`, `controls/dev/Materials/Acrylic/AcrylicBrush.cpp` and `.h`, main branch fetched 13 Oct 2026).** The modern recipe ("shadow-friendly luminosity-based recipe", introduced in Windows 10 19H1 per the code comments) replaced the exclusion blend:
1. Backdrop composited **source-over an opaque FallbackColor** (so the blur never mixes with transparency: the code comment notes that blurring with transparent pixels yields minimal blur).
2. `GaussianBlurEffect` with `BlurAmount = sc_blurRadius = 30.0` and `BorderMode = Hard`. In Direct2D the Gaussian blur's amount is the **standard deviation** in DIPs, the kernel radius is 3σ, the "Hard" border mode clamps the output to the input size and extends the input with a **mirror-type** border, and the default "balanced" optimization **pre-scales (downsamples)** internally with trilinear filtering (REFERENCE: Microsoft Learn, Direct2D "Gaussian blur effect", `D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION`, border and optimization modes). That the composition-layer `GaussianBlurEffect` used by AcrylicBrush has the same semantics is INFERRED from the shared effect definitions. So **Acrylic's blur is σ = 30 DIPs** (= 30 px at 100% scaling, 45 px at 150%), mirrored at the edges.
3. **Luminosity blend**: the blurred backdrop keeps its hue and saturation but takes its **luminosity** from a solid "luminosity colour" (the tint's RGB with V clamped to [0.125, 0.965] in HSV and opacity mapped from the tint opacity into [0.15, 1.03], capped at 1; or the app's `TintLuminosityOpacity`). The code comment gives the purpose: reduce contrast in the backdrop so that sharp brightness differences (for example from shadows) are suppressed while colour comes through. (The source notes that the `BlendEffectMode` names Luminosity and Color are swapped by a bug, so the code passes `Color` to get a luminosity blend and vice versa.)
4. **Color blend** with the tint colour (alpha = tint opacity × an opacity modifier computed from the tint's HSV value: max 0.45 for white, 0.90 at mid grey, 0.85 for black).
5. **Noise**: a 256×256 tiled noise PNG (`NoiseAsset_256X256_PNG.png`) at **opacity 0.02**, composited source-over.
6. Optional cross-fade with the fallback colour (for activation/deactivation transitions).
The header still declares `sc_exclusionColor = (A 26, white)` (white at ≈ 10%) and `sc_saturation = 1.25`, but neither is referenced in the current `.cpp`: they are leftovers of the original exclusion-blend recipe (COMPUTED from a grep of the file). Default `TintColor` is white with A = 204, tint opacity 1.0; theme brushes use tint opacities 0.6–0.8.

**Math summary.** `out = noise_0.02 ⊕ ColorBlend(tint, LuminosityBlend(lumColor, G_{σ=30} * (backdrop over fallback)))`. Luminosity and colour blends are nonlinear (HSL-style decompositions); the blur is a true Gaussian; the noise is **additive texture** (not displacement as in A17), there to hide banding in the very smooth blurred gradients and to give a tactile "material" feel.

**GPU / cost.** Composition effect graph compiled into shaders by the Windows compositor (DWM for background acrylic). A σ = 30 Gaussian at full resolution would be expensive; Direct2D's blur pre-scales internally in its default modes (above), and whether the composition path does the same is not documented (UNVERIFIED). Microsoft's own guidance (Mica, B7) treats per-frame blurring as costly enough to design a material that avoids it.

**Visual fingerprint.** Very soft (σ = 30) and **low-contrast** backdrop: the luminosity blend flattens brightness differences much more than Apple's materials, so shapes behind acrylic are visible mostly as colour, not as light and dark; fine grain visible on close inspection (2% noise); a whitish or tinted veil. Best test: a black/white checkerboard of large squares behind acrylic (luminosity flattened, hue kept) next to the same under an Apple material.

**Where used.** Windows 10/11 context menus, flyouts, Start menu (background acrylic), WinUI navigation panes (in-app acrylic).

**Signature.** "Windows' frosted glass: a σ-30 Gaussian whose brightness is replaced by the tint's, so colour passes through but light and dark do not, finished with 2% noise grain."

### B7. windows-mica — Fluent Mica / Mica Alt

**id** `windows-mica`. **Aliases:** Mica, Mica Alt (`MicaKind.BaseAlt`), `MicaBackdrop` (WinUI 3), `MicaController` (Windows App SDK), `DWMSBT_MAINWINDOW` / `DWMSBT_TABBEDWINDOW` system backdrop types for Win32 (REFERENCE names, Microsoft Learn "Apply Mica in Win32 desktop apps"). **Family:** COMPOSITE, with a **cached** blur. Verdict: COMPOSITE.

**What Microsoft documents (REFERENCE, Microsoft Learn "Mica material", updated 22 Jul 2026).** Mica is "an opaque, dynamic material that incorporates theme and desktop wallpaper" to paint the background of long-lived windows; it is designed for performance because it **samples the desktop wallpaper only once** to create its visualization; as the window moves, the material adapts to the wallpaper underneath; it falls back to a neutral solid colour when the window is inactive, when transparency is off, in Battery Saver, on low-end hardware, and on Windows builds below 22000. Mica Alt tints more strongly with the user's desktop background colour, for tabbed title bars (Windows App SDK 1.1+, Windows 11 22000+). Apps should apply backdrop material only once, as the base layer, with transparent layers above it.

**Definition (INFERRED from the documented behaviour).** `Mica(p) = Tint( W_blur(p_screen) )`, where `W_blur = G_σ_large * Wallpaper` is computed **once per wallpaper change** (not per frame), and the window shows the crop of `W_blur` at its screen position, then a strong tint and luminosity layer. It is **not** a backdrop blur: other windows and app content behind it are not seen; only the wallpaper is. It is "opaque": the result does not depend on what is between the wallpaper and the window. The size of Mica's blur and its tint values are not published (UNVERIFIED); visually the wallpaper reduces to large soft colour fields, implying a very large σ (an estimate would need a MEASURED fit on Windows, outside this project's reach).

**Key properties.** The blur is LSI on the wallpaper, but the output is a **position-dependent lookup** into a cached image (moving the window changes the output; the content behind the window does not). Per-frame cost ≈ one texture fetch + tint per pixel (MODELED), versus capture + blur per frame for Acrylic: this is the design point.

**Visual fingerprint.** A faint, smooth wash of the wallpaper's colours under the title bar and sidebar that shifts as you drag the window; never shows other windows; goes flat grey when the window loses focus. Best test (in-app simulation): drag a "window" over a "wallpaper" while another "window" moves under it: Mica ignores the moving window, Acrylic shows it.

**Signature.** "Blur the wallpaper once, then let each window peek at its own patch of that blurred wallpaper: frosted glass with the per-frame cost removed."

### B8. android-renderEffect — Android RenderEffect blur and window blurs

**id** `android-renderEffect`. **Aliases:** `RenderEffect.createBlurEffect(radiusX, radiusY, edgeTreatment)` (API 31, Android 12) applied with `View.setRenderEffect` or `RenderNode.setRenderEffect`; Jetpack Compose `Modifier.blur(radius, edgeTreatment)`; window blurs `Window.setBackgroundBlurRadius(int)` ("background blur", frosted window backdrop) and `FLAG_BLUR_BEHIND` + `WindowManager.LayoutParams.setBlurBehindRadius(int)` ("blur behind", whole screen behind a dialog). **Family:** LSI blur API (RenderEffect) and COMPOSITE system blur (window blurs). Verdict: RenderEffect blur = TRUE BLUR (of the view itself, not a backdrop); window background blur = COMPOSITE (with the app's own translucent window background as tint).

**Semantics (REFERENCE, detailed with sources in `stack-semantics.md` §2.3).** RenderEffect "radius" r maps to Skia σ = 0.57735·r + 0.5; edge treatment = Skia tile mode (clamp, repeat, mirror, decal). Window blurs are drawn by SurfaceFlinger's RenderEngine, which downsamples the region to 1/4 and uses a Kawase (long-time default) or Gaussian or dual-Kawase filter depending on build flags.

**Window blur documentation (REFERENCE, Android Open Source Project, "Window blurs", source.android.com/docs/core/display/window-blurs).** Two kinds: background blur (suggested radius about 80 px) and blur behind (about 20 px); Android 12+; the window must be translucent and its background drawable defines the blurred shape (rounded corners); cross-window blur is expensive and only on selected devices (`ro.surface_flinger.supports_background_blur=1`); the system may disable blurs during battery saver, some video playback, multimedia tunneling, or developer override, and apps should listen (`WindowManager.addCrossWindowBlurEnabledListener`, `isCrossWindowBlurEnabled()`) and fall back to a more opaque background with stronger dim; radii above 150 px are discouraged. So unlike Apple and Windows, Android's frosted glass is **opt-in per window and may silently disappear**, and the tint is whatever translucent colour the app draws.

**In-app backdrop blur.** Android has no public API to blur *what is behind a view inside the same window* (RenderEffect blurs the view's own content). Libraries render the content behind into an offscreen RenderNode, blur it with RenderEffect, and draw it as the view's background (e.g. the open-source Haze library for Compose; INFERRED mechanism, library details UNVERIFIED). Material Design 3 defines elevation by tonal colour and shadows rather than by translucent blur materials; system UI blur (notification shade, recents) varies by Android version and OEM (UNVERIFIED for specific releases).

**Visual fingerprint.** RenderEffect: a clean Gaussian of the view itself (σ ≈ 0.58 r). Window blur: on Kawase devices, a slightly "boxy-diamond" softness typical of Kawase passes at 1/4 resolution; dims and blur disappear in battery saver. Best test: a point-light grid behind a blurred dialog (Kawase diamond vs Gaussian disc).

**Signature.** "Android's blur is either an honest Gaussian of your own view, or a system compositor's quarter-resolution Kawase behind your window that the OS may switch off at any time."
### B9. drop-shadow — Drop shadow blur (CSS, CALayer, Figma, SwiftUI)

**id** `drop-shadow`. **Aliases:** CSS `box-shadow`, `text-shadow`, `filter: drop-shadow()`; canvas `shadowBlur`; SVG `<feDropShadow stdDeviation>`; `CALayer.shadowRadius` / `shadowOffset` / `shadowOpacity` / `shadowPath`; `CGContext.setShadow(offset:blur:color:)`; SwiftUI `.shadow(color:radius:x:y:)`; Figma, Sketch and Photoshop "Drop Shadow" (blur/size, spread, offset); Core Image `CIBlurredRectangleGenerator` / `CIBlurredRoundedRectangleGenerator` (σ directly, D7). **Family:** BLUR-DERIVED (a blurred alpha mask). Verdict: BLUR-DERIVED.

**Definition.** For an object with coverage (alpha) mask α:
`shadow(p) = c · o · (G_σ * S_spread(α))(p − offset)`, drawn **under** the object (or inside it for inset shadows), where c is the colour, o the opacity, S_spread a dilation (spread > 0) or erosion (spread < 0) of the mask by the spread distance (A15 morphology), and G_σ a Gaussian. The image itself is never blurred: only its silhouette.

**What the number means, per tool** (σ in the tool's px/pt):

| Tool / API | Parameter | σ | Label |
|---|---|---|---|
| CSS `box-shadow`, `text-shadow`, canvas `shadowBlur` | blur radius B | **B/2** | REFERENCE (CSS Backgrounds and Borders 3, §6.1.2 "Blurring Shadow Edges"; WHATWG HTML canvas "Shadows"; details in `stack-semantics.md` §1.3) |
| CSS `filter: drop-shadow(x y L)` | third length L | **L** (standard deviation, not blur radius) | REFERENCE (Filter Effects 1, `drop-shadow()`: values as for box-shadow but the third length is the standard deviation) |
| SVG `feDropShadow`, `feGaussianBlur` | stdDeviation | = value | REFERENCE (Filter Effects 1) |
| `CALayer.shadowRadius` | r (points; default 3) | **≈ 0.94–0.99 r** (MEASURED, `render(in:)` path on macOS 27, D7) | Apple documents only "the blur radius (in points)"; σ is MEASURED |
| `CGContext.setShadow(blur:)` | b | ≈ 0.47–0.54 b; `shadowRadius r` renders exactly as `blur 2r` | MEASURED (D7) |
| Figma drop shadow / layer blur / background blur | blur F | ≈ **0.44 F** | Bjango 2024 measured Figma's value as 1.136 × the matching CSS box-shadow blur, so σ = F / (2 × 1.136) (third-party MEASURED, REFERENCE to bjango.com "Blur radius comparison") |
| Sketch drop shadow | blur | ≈ 0.48 × value (factor 1.042 vs CSS) | same source |
| Photoshop layer style Drop Shadow | Size | ≈ 0.44 × size (factor 1.136) | same source |
| SwiftUI `.shadow(radius:)` | radius | UNVERIFIED (INFERRED to follow CALayer); measure live (`live-calibration.md` §5.5) | |

Consequences the app should teach: **the same "10" means σ = 5 in CSS box-shadow, σ = 10 in CSS drop-shadow(), σ ≈ 9.4 as CALayer shadowRadius, and σ ≈ 4.4 in Figma**; the common designer rule "iOS shadowRadius = Figma blur ÷ 2" is consistent with these numbers: shadowRadius F/2 gives σ ≈ 0.94 · F/2 = 0.47F, against Figma's ≈ 0.44F, a 7% difference (COMPUTED from the table).

**Frequency response.** The mask blur is LSI (Gaussian); the full operation is affine in the mask and nonlinear in the image (it depends only on α).

**Closed forms.** A rectangle [x0, x1] × [y0, y1] blurred by G_σ has the separable profile
`S(x, y) = ¼ [erf((x − x0)/(σ√2)) − erf((x − x1)/(σ√2))] · [erf((y − y0)/(σ√2)) − erf((y − y1)/(σ√2))]`
(COMPUTED: convolution of a box with a Gaussian per axis). Rounded rectangles have no elementary closed form; Wallace (2016, "Fast rounded rectangle shadows", madebyevan.com/shaders/fast-rounded-rectangle-shadows/) integrates exactly along one axis and samples the other in a few steps; Skia uses analytic blurred round-rect paths for CSS box-shadow (INFERRED, `stack-semantics.md` §1.3). This is why rectangular UI shadows are nearly free while arbitrary-shape shadows are not.

**GPU and cost.** Analytic (rects, round rects): ALU only, about 4 `erf` evaluations per pixel, no texture fetches (MODELED). Arbitrary shapes: render the alpha mask offscreen (an extra pass), separable Gaussian (2 × (6σ+1) taps, or downsampled for big σ), composite. Core Animation without `shadowPath` must derive the shape from the layer's rendered alpha, which forces an offscreen pass; Apple's `shadowPath` documentation notes that an explicit path usually improves performance (REFERENCE, CALayer.shadowPath docs).

**Visual fingerprint.** A soft dark copy of the silhouette, offset, with **rounder corners than the shape** (the blur rounds every corner to radius ≈ σ), and a penumbra about 4σ wide (CSS: about twice the blur radius, as the CSS spec's note says). Spread grows the shadow with hard morphology before blurring, so large spread + small blur gives a near-solid "outline". Material Design elevation uses two shadows (a sharper "key light" and a softer "ambient" one; REFERENCE, Material Design "Elevation" guidance, wording not re-checked). Best test: a square and a star shape with the same "10" typed into each tool's convention, side by side.

**Signature.** "Not a blurred image but a blurred silhouette: and every tool disagrees on what the blur number means."

### B10. bloom — Bloom / glow

**id** `bloom`. **Aliases:** bloom, glow, glare, light bleeding, "Glow" (After Effects), `CIBloom` (inputRadius 10, inputIntensity 0.5) and its darkening twin `CIGloom` (D2/D7), Unity Bloom (threshold, soft knee/intensity, scatter or diffusion, clamp, tint, dirt), Unreal Bloom (Standard: sum of 6 Gaussians with per-size tint; Convolution: FFT with a kernel image). **Family:** BLUR-DERIVED (threshold → multi-scale blur → add). Verdict: BLUR-DERIVED (adds energy, so never a blur).

**Definition.** `out = f + I · Σ_i w_i (G_{σ_i} * T(f))`, where T is a brightness threshold (only highlights bloom), σ_i are roughly geometric (σ_i ∝ 2^i, one per pyramid level), w_i per-level weights and I the intensity. Physical motivation: scattering in the eye and in lenses spreads a fraction of very bright light into a wide, heavy-tailed halo (Spencer, Shirley, Zimmerman & Greenberg 1995, "Physically-based glare effects for digital images", SIGGRAPH 1995). It works on **linear HDR** values; in 8-bit sRGB it can only approximate.

**The PSF of a pyramid bloom is a power law (COMPUTED, `blur_derived.py`).** A sum of Gaussians with σ_i = 2^i and **equal** weights has a radial PSF whose log-log slope is −2.00 between r = 4 and 64 px, i.e. `PSF ∝ r^−2`; with weights a^i the slope is −2 + log2 a (a = 0.7 gives −2.51, matching the probe's −2.51 to −2.54). Reason: at distance r only the levels with σ_i ≈ r contribute, each with peak height ∝ 1/σ_i². So the per-level weight curve **is** the glare law, which is why artists tune "scatter" and level tints rather than one radius.

**Threshold (Unity Post-Processing Stack v2, REFERENCE: `PostProcessing/Shaders/Colors.hlsl`, `QuadraticThreshold`, and `Runtime/Effects/Bloom.cs`, branch v2).** With brightness `br = max(r, g, b)`, threshold t (converted from gamma to linear space), knee `K = t · softKnee`: `rq = clamp(br − (t − K), 0, 2K)`, `rq = rq² / (4K)`, `colour ← colour · max(rq, br − t) / max(br, ε)`. A hard threshold (softKnee = 0) pops highlights on and off; the quadratic knee blends them in. This makes bloom **nonlinear** (and intensity-dependent: dim images do not bloom at all).

**Pyramid (REFERENCE, Unity v2 `Sampling.hlsl`; the design follows Jimenez 2014, "Next generation post processing in Call of Duty: Advanced Warfare", SIGGRAPH Advances in Real-Time Rendering).** Downsample with a **13-tap** filter: four bilinear taps at (±0.5, ±0.5) texels (a 2×2 box each) weighted 0.5 in total, plus four overlapping 2×2-box groups built from 9 taps at {−1, 0, 1}² texels, each group weighted 0.125 (the code: `div = (1/4)·(0.5, 0.125)`; `o = (D+E+I+J)·div.x + (A+B+G+F + B+C+H+G + F+G+L+K + G+H+M+L)·div.y`). Upsample with a **9-tap tent** scaled by `sampleScale` and add the level above. Number of levels: `iterations = clamp(floor(log2(max(w, h)) + min(diffusion, 10) − 10), 1, maxPyramid)` (from `Bloom.cs`: `logs = log2(s) + min(diffusion, 10) − 10`). Jimenez also weights the first downsample by a "Karis average" (each 2×2 group by 1/(1 + luma)) to suppress single-pixel fireflies (REFERENCE, Jimenez 2014 slides; not checked against Unity v2 code here).

**Cost per full-res pixel** (MODELED): downsample 13 fetches per half-res pixel and per level, summing to 13/4 · 4/3 ≈ 4.3 fetches per full-res pixel; upsample 9 taps per level ≈ 3.0; prefilter and composite ≈ 2: **about 9 fetches per pixel regardless of glow size**, which is why every engine uses a pyramid rather than a big Gaussian. Kawase's 2003 GDC talk ("Frame buffer postprocessing effects in DOUBLE-S.T.E.A.L (Wreckless)") popularized the iterated small-kernel approach (see `catalog-lsi.md` §12). Unreal's Convolution Bloom does one FFT convolution with an arbitrary (often star/diffraction) kernel image instead (REFERENCE, Unreal Engine "Bloom" documentation; version introduced UNVERIFIED).

**Key properties.** Not normalized (adds light: DC gain 1 + I·Σw for above-threshold regions), nonlinear (threshold, clamp), shift-invariant, isotropic (unless anamorphic ratio or streak kernels are used).

**Visual fingerprint.** Bright lights get wide, soft halos that fall off slowly (power law), merging into a haze around clusters; dark regions are untouched; with a hard threshold, highlights pop on and off as exposure changes. Best test: the **night-city point lights** at several exposures; compare with a Gaussian blur of the same image (which dims lights rather than adding glow).

**Signature.** "Keep only what is brighter than white, blur it at every scale at once, and add it back: light that spills."
### B11. unsharp-mask — Unsharp mask and high pass ("what blur enables")

**id** `unsharp-mask` (sub-ids `high-pass`, `local-contrast`). **Aliases:** unsharp mask (USM), Photoshop *Sharpen > Unsharp Mask* (Amount %, Radius px, Threshold levels), *Other > High Pass* (Radius), `CIUnsharpMask` (inputRadius 2.5 [0, 100], inputIntensity 0.5 [0, 1]), `CISharpenLuminance` (sharpness, radius 1.69), "Clarity"/local contrast (large-radius, low-amount USM). **Family:** BLUR-DERIVED (anti-blur). Verdict: NOT A BLUR.

**Definition.** `g = f + k (f − G_σ * f) = (1 + k) f − k G_σ * f`. The term `f − G_σ * f` is the **high pass** (Photoshop High Pass shows it offset by mid-grey: `f − G*f + 0.5`). With a threshold T (Photoshop): sharpen only where `|f − G*f| > T` (a nonlinear gate that protects smooth areas and noise; Adobe's exact gating rule is UNVERIFIED).

**Parameters.** k = Amount (Photoshop 100% = 1.0; `CIUnsharpMask` intensity 0.5 = 0.5, INFERRED to be the same k), σ = Radius (Photoshop's radius is close to σ: Bjango 2024 finds Photoshop's Gaussian blur radius ≈ 0.49 × the matching CSS box-shadow radius, i.e. ≈ σ; for CI, see `live-calibration.md`), T = Threshold. Small σ (0.5–2 px) sharpens detail; large σ (20–100 px) with small k is "local contrast"/"clarity".

**Frequency response (LSI when T = 0).** `H(ν) = 1 + k (1 − exp(−2π²σ²|ν|²))`: 1 at DC (brightness kept), rising to **1 + k** at high frequencies (COMPUTED). It is an **inverse-blur shelf**, not a deblur: it boosts all high frequencies, including noise, by up to 1 + k (k = 0.5: gain 1.35, 1.50, 1.50 at Nyquist for σ = 0.5, 1, 2.5; COMPUTED by `blur_derived.py`). Kernel: positive centre `1 + k − k·G(0)` and a negative Gaussian surround, so it **violates** the maximum principle (T1): overshoots are guaranteed.

**Overshoot (halo) on a unit step (COMPUTED, `blur_derived.py`).** Just beside the edge (pixel centres ±0.5 px away) the high-pass value is `1 − Φ(0.5/σ)`, so the overshoot is k × 0.159, 0.309, 0.401, 0.421, 0.460 for σ = 0.5, 1, 2, 2.5, 5 (→ 0.5k as σ grows), and the halo extends about 1.5, 3.5, 5.5, 7.5, 13.5 px (until it falls below 1% of its peak). Large-σ USM therefore gives the familiar wide bright/dark halos around edges.

**Relation to the heat equation (COMPUTED).** For small σ, `G_σ * f ≈ f + (σ²/2) ∇²f`, so `g ≈ f − k(σ²/2) ∇²f`: one explicit step of the heat equation **run backward** for time kσ²/2 (A12) and the classic Laplacian sharpening kernel. Running it further is ill-posed (noise explodes), which is why deblurring needs regularized deconvolution instead.

**Cost and GPU.** A Gaussian (any LSI method from `catalog-lsi.md`) plus one fused pass `(1+k)f − k·blur` (with the threshold test): the blur dominates. `CIUnsharpMask` and `CISharpenLuminance` are the Apple routes.

**Visual fingerprint.** Crisper edges and text, with light/dark halos at strong edges, amplified noise and JPEG blocks in flat areas, and a "crunchy" look when overdone. Best test: a **step edge and fine text** with an overlay of the ESF showing the overshoot lobes; a noisy flat field shows the noise gain.

**Signature.** "Subtract a blur to find the detail, then add the detail back louder: sharpening is blur run backwards."

### B12. difference-of-gaussians — DoG / XDoG

**id** `difference-of-gaussians` (sub-id `xdog`). **Aliases:** DoG, centre-surround filter, Mexican-hat approximation, band-pass; LoG (Laplacian of Gaussian) approximation; Laplacian pyramid level; XDoG (eXtended DoG) for stylization; FDoG (flow-based DoG). **Family:** BLUR-DERIVED (band-pass). Verdict: NOT A BLUR.

**Definition.** `D = G_σ * f − G_{kσ} * f` with k > 1. Since `∂G_σ/∂σ = σ ∇²G_σ`, `G_{kσ} − G_σ ≈ (k − 1) σ² ∇²G_σ`: the DoG is a scale-normalized Laplacian of Gaussian (REFERENCE: Lowe 2004, "Distinctive image features from scale-invariant keypoints", IJCV 60(2), §3). Marr & Hildreth (1980, "Theory of edge detection", Proc. R. Soc. Lond. B 207) recommended k ≈ 1.6 as the best DoG approximation of the LoG (REFERENCE). Laplacian pyramid levels are DoGs of a Gaussian pyramid (Burt & Adelson 1983, "The Laplacian pyramid as a compact image code", IEEE Trans. Communications 31(4)).

**Frequency response (COMPUTED).** `H(ν) = exp(−2π²σ²ν²) − exp(−2π²k²σ²ν²)`: zero at DC, a single peak, then decay: a **band-pass**. Peak at `ν* = sqrt( ln(k²) / (2π²σ²(k² − 1)) )`: for k = 1.6, ν* = 0.1747/σ cycles/px with peak response 0.334; for k = √2, 0.1874/σ and 0.250; k = 2, 0.1530/σ and 0.472; k = 5, 0.0824/σ and 0.840 (`blur_derived.py`). Kernel: positive centre, negative surround, sum 0.

**XDoG** (Winnemöller 2011, "XDoG: advanced image stylization with eXtended Difference-of-Gaussians", NPAR 2011; Winnemöller, Kyprianidis & Olsen 2012, "XDoG: An eXtended difference-of-Gaussians compendium including advanced image stylization", Computers & Graphics 36(6)): `D_p = (1 + p) G_σ * f − p G_{kσ} * f` (a DoG added to a blurred image, i.e. an unsharp mask with a Gaussian "original") followed by a soft threshold `T(u) = 1` if `u ≥ ε`, else `1 + tanh(φ(u − ε))`; k = 1.6 typical. Varying p, ε, φ moves from edge lines to ink washes and woodcut looks. FDoG (Kang, Lee & Chui 2007, "Coherent line drawing", NPAR) computes the DoG across an edge tangent flow for continuous lines.

**Properties and cost.** Linear and LSI (DoG); XDoG nonlinear (threshold). Two Gaussians (share the first as input to the second via the semigroup: `G_{kσ} = G_{σ√(k²−1)} * G_σ`, COMPUTED) and one subtract pass.

**Visual fingerprint.** Edges become thin bright/dark line pairs with zero crossings exactly at the edge; flat areas go to zero (grey); blobs of size ≈ σ light up (blob detection, SIFT keypoints); XDoG produces crisp ink-drawing and woodcut stylizations. Best test: Siemens star and text (rings at the band-pass frequency), and a face/photo for XDoG.

**Signature.** "Subtract a bigger blur from a smaller one and only the edges and blobs of one size survive: the retina's centre-surround trick."

## Part C. Summary table

Cost is per output pixel for the best practical algorithm named; "fetches" are for the GPU route suggested in the section. All verdicts use §0.

| id | Verdict | Linear | Shift-inv. | Separable | Edge-preserving | Best algorithm, cost | Typical GPU fetches / px | Best test image | One-line fingerprint |
|---|---|---|---|---|---|---|---|---|---|
| median | RANK FILTER | no | yes | no | yes | Perreault–Hébert O(1) (8-bit); sorting network for 3×3/5×5 | 9 / 25 + min-max network | salt-and-pepper on text; impulse grid | impulses vanish, edges stay, corners round |
| bilateral | ADAPTIVE BLUR | no | yes | no | yes (steps ≫ σr) | grid O(1); brute O(r²) | (2r+1)² brute | noisy step at 3 contrasts | Gaussian that won't cross edges; keeps impulses |
| bilateral-grid | ADAPTIVE BLUR | no | yes | — | yes | O(1) + grid (∝ σs⁻²σr⁻¹) | 1 splat + 1 trilinear | ramp + low-contrast step | bilateral via 3-D blur; slight blockiness |
| bilateral-separable | ADAPTIVE BLUR | no | yes | approx. | yes | O(r) | 2(2r+1) | rotated square, star | axis streaks on diagonals |
| joint-bilateral | ADAPTIVE BLUR | in f yes, in guide no | yes | no | guide's edges | as bilateral | as bilateral (+ guide fetches) | blocky depth + photo guide | edges come from the guide |
| guided | ADAPTIVE BLUR | in p yes (fixed guide) | yes | via boxes | yes, soft (a = σ²/(σ²+ε)) | ~6 box filters, O(1); fast GF O(N/s²) | 2 at full res + low-res passes | detail boost on noisy step | box blur in flats, copy at edges, no gradient reversal |
| domain-transform | ADAPTIVE BLUR | no | yes | 1-D passes | yes | O(1) recursive | ~2 per pass, 3 iterations | noisy step + thin line | ruler stretched at edges, exponential tails |
| kuwahara | ADAPTIVE BLUR | no | yes | no | yes | SAT O(1) | 32 (SAT) or (2r+1)² | noisy flat field | oil-paint blocks |
| kuwahara-anisotropic | ADAPTIVE BLUR | no | yes | no | yes | O(r²) per pixel | ≈ 3πh² (≈ 340 for h = 6) | zone plate / flow rings | strokes that follow edges |
| surface-blur | ADAPTIVE BLUR (INFERRED bilateral) | no | yes | no | yes (hard cutoff) | O(1) with box spatial kernel | πR² brute | ramp + noisy step | Photoshop's bilateral, terraces ramps |
| smart-blur | ADAPTIVE BLUR (INFERRED) | no | yes | no | yes (hard) | as above | as above | ramp | posterized steps; Edge mode shows the threshold |
| heat-equation | TRUE BLUR | yes | yes | yes | no | any Gaussian, σ = √(2t) | as Gaussian | impulse animated over t | time is blur |
| perona-malik | ADAPTIVE BLUR | no | yes | no | yes, sharpens | n = t/λ iterations | 5 × n | noisy step and ramp, animated | cartoon regions, staircase |
| nonlocal-means | ADAPTIVE BLUR (denoiser) | no | yes | no | yes | integral images, O(search area) | ≈ 6 × search area (2 646 for 21×21) | noisy periodic texture/text | averages look-alike patches anywhere |
| mean-shift | ADAPTIVE BLUR | no | yes | no | yes | iterations × πh_s² | 5–20 × window | ramp, photo | posterized segments |
| morphology | NOT A BLUR | no | yes | yes (rect) | moves edges | van Herk O(1) | ~3 compares per pass | point lights, text | hard-edged growth/shrink |
| pixelate | RESAMPLER | yes | no (periodic) | yes | no | mip/SAT cell mean | 1 + reduction | text, panning star | coarser grid with new hard edges |
| frosted-glass-noise | BLUR IN EXPECTATION | yes (per realization: a resampler) | in law | — | no | 1 random fetch | 2 | step edge, text, N-average toggle | no averaging, yet the average is a blur |
| backdrop-blur | COMPOSITE | mostly (affine) | ≈ | blur stage yes | no | capture + downsampled Gaussian | ≈ 4–6 after capture | text scrolled under panel | soft, saturated, luminance-squeezed |
| apple-uiblureffect | COMPOSITE | mostly | ≈ | blur stage yes | no | 1/4 or 1/8 scale Gaussian | render server | material ladder | one blur, many luminance curves |
| apple-vibrancy | NOT A BLUR (blend) | no (clamped add) | yes | — | — | point op | 0 extra | stripes behind labels | text borrows backdrop colour |
| liquid-glass | COMPOSITE (mostly refraction) | no | no (SDF-dependent) | blur stage yes | refracts | half-res small blur + displacement | ≈ 4.5 + 1–3 displaced | grid behind rounded rect | light blur, bending rim, highlight |
| css-backdrop-filter | COMPOSITE | mostly | yes | blur stage yes | no | Skia Gaussian (downsampled σ > 4) | per browser | bright object at panel edge | σ = the number, sRGB, mirrored |
| windows-acrylic | COMPOSITE | no (luminosity blend) | yes | blur stage yes | no | σ = 30 DIP Gaussian + blends | DWM | large black/white checker | colour passes, brightness flattened, 2% grain |
| windows-mica | COMPOSITE (cached) | — | position-dependent | — | no | one-time wallpaper blur | ≈ 1 | window dragged over wallpaper | blurred wallpaper only, never other windows |
| android-renderEffect | TRUE BLUR / COMPOSITE | yes / mostly | yes | yes | no | Skia Gaussian; SurfaceFlinger Kawase at 1/4 | per path | point-light grid behind dialog | Gaussian of the view, or system Kawase |
| drop-shadow | BLUR-DERIVED | affine in mask | yes | yes | — | analytic erf (rects) | 0 (ALU) or mask + blur | same "10" in each tool | blurred silhouette; units disagree |
| bloom | BLUR-DERIVED | no (threshold) | yes | yes | — | 13-tap down / 9-tap tent up pyramid | ≈ 9 | night-city lights | power-law halo added to highlights |
| unsharp-mask | NOT A BLUR | yes (T = 0) | yes | via blur | sharpens | Gaussian + 1 pass | blur + 2 | step edge, text | blur run backwards: halos and crunch |
| difference-of-gaussians | NOT A BLUR | yes (DoG) | yes | yes | — | two Gaussians | 2 blurs + 1 | Siemens star, text, photo (XDoG) | only one band of scales survives |

## Part D. Probes run for this document

All probes live in `$TMPDIR/blur2ool-nonlinear/` (`/var/folders/ww/m595r7m942g0h7w9c016dj6w0000gn/T/blur2ool-nonlinear/`). They were compiled with `xcrun swiftc` from Xcode 27.0 beta and run on this Mac (Darwin 27.2, macOS 27.x) on 13 Oct 2026. Re-run them to refresh the numbers; nothing here touches iCloud or xcodebuild.

### D1. SDK headers (REFERENCE, Apple's own header comments)

- `MPSImageMedian` (iOS 9+): per-channel median in a `kernelDiameter x kernelDiameter` square window, odd diameters only. Header note: "currently only supports images with <= 8 bits/channel". Probe result on the Mac GPU: `minKernelDiameter = 3`, `maxKernelDiameter = 127` (MEASURED on this Mac; the iPhone limit may differ, so query it at runtime).
- `MPSImageGuidedFilter` (iOS 11.3+): two stages, "Regression" (writes a 4-channel coefficient texture `a.rgb, b` "typically at a very low resolution") and "Reconstruction" (upsamples coefficients and computes `a.r*R + a.g*G + a.b*B + b`). Parameters `kernelDiameter`, `epsilon`, `reconstructScale`, `reconstructOffset`; optional weights texture. The header cites the Fast Guided Filter paper (arXiv 1505.00996, He & Sun 2015).
- `MPSImageAreaMax/Min` (rectangular max/min, "edgeMode is assumed to always be Clamp") and `MPSImageDilate/Erode` (arbitrary "probe" structuring function, i.e. grey-scale morphology with a non-flat structuring element).

### D2. Core Image filter attributes (`probe_ci.swift`, REFERENCE: values returned by `CIFilter.attributes` on macOS 27)

| Filter | Category | Parameters (default, slider range) |
|---|---|---|
| CIMedianFilter | Blur | none (fixed 3x3, per Apple's filter reference; the attribute list exposes no radius) |
| CINoiseReduction | Blur | inputNoiseLevel 0.02 [0, 0.1]; inputSharpness 0.4 [0, 2] |
| CIMorphologyMaximum / Minimum | **Blur** (Apple files morphology under CICategoryBlur) | inputRadius 0 [0, 50], "circular" structuring element |
| CIMorphologyRectangleMaximum / Minimum | Blur | inputWidth 5, inputHeight 5 [1, 49], rounded to odd |
| CIMorphologyGradient | Blur | inputRadius 5 [0, 50] |
| CIEdgePreserveUpsampleFilter | Geometry | inputSpatialSigma 3 [0, 5]; inputLumaSigma 0.15 [0, 1] (a joint bilateral upsampler by its parameter names; INFERRED) |
| CIBloom / CIGloom | Stylize | inputRadius 10 [0, 100]; inputIntensity 0.5 [0, 1] |
| CIUnsharpMask | Sharpen | inputRadius 2.5 [0, 100]; inputIntensity 0.5 [0, 1] |
| CISharpenLuminance | Sharpen | inputSharpness 0.4 [0, 2]; inputRadius 1.69 [0, 20] |
| CIPixellate / CIHexagonalPixellate | Stylize | inputScale 8 [1, 100]; inputCenter (grid phase) |
| CICrystallize / CIPointillize | Stylize | inputRadius 20 [1, 100]; inputCenter |
| CIGlassDistortion | Distortion | inputTexture (displacement source); inputScale 200 [0.01, 500] |
| CIDisplacementDistortion | Distortion | inputDisplacementImage; inputScale 50 [0, 200] |
| CIBokehBlur | Blur | inputRadius 20, inputRingAmount 0, inputRingSize 0.1, inputSoftness 1 |
| CIMaskedVariableBlur | Blur | inputMask (green channel), inputRadius 5 [0, 10] |
| CIHighlightShadowAdjust | Stylize | inputRadius 0 [0, 10] (a local-tone-mapping filter built on a blur; INFERRED) |

### D3. Private Core Animation filter catalogue (`probe_ca.swift`, `probe_ca2.swift`) — INFERRED-class evidence, observed by Objective-C runtime introspection

`+[CAFilter filterTypes]` on macOS 27 returns 44 types, including `gaussianBlur`, `variableBlur`, `colorSaturate`, `colorMatrix`, `vibrantDark`, `vibrantLight`, `vibrantColorMatrix`, `averageColor`, `luminanceCurveMap`, `curves`, `lanczosResize`, `displacementMap`, `chromaticAberration`, `chromaticAberrationMap`, `glassBackground`, `glassForeground`, `distanceField`, `sdrNormalize`, `edrGain`, `limitAveragePixelLuminance`. Input keys of the blur-relevant ones:

- `gaussianBlur`: inputRadius, inputQuality, inputBounds, inputHardEdges, inputNormalizeEdges, inputNormalizeEdgesTransparent, inputDither, inputLinear, inputIntermediateBitDepth.
- `variableBlur`: inputMaskImage, inputRadius, inputNormalizeEdges, inputFade, inputDither, inputZeroFillEdges, inputQuality, inputBlurFill* (blur-fill radius and lighten/darken/normal opacities).
- `glassBackground` (Liquid Glass backdrop): 78 keys in groups: refraction (inner/outer amount and height, two distances, opacity), blur (one radius plus five opacity/distance pairs, i.e. a blur whose strength varies with distance from the shape edge), face colour matrix (white, black, saturation, fill colour, max luma, max luma SDR), bleed (amount, height, blur radius, distances, opacity, darken blend, colour matrix), drop shadow and ring shadow (offset, blur radius, opacity, colour matrix), key-fill highlight (height, angle, spread, amount, offset, colour bias — the specular rim), blur-fill (radius and lighten/darken/normal opacities), SDR holding tone, max EDR headroom, clamp, chromatic aberration (amount, height, offset, angle).
- `glassForeground`: refraction amount/height/offset/angle, aberration amount/height/offset/angle, edge start/end and edge opacity start/end.

`CABackdropLayer` properties include `scale`, `bleedAmount`, `marginWidth`, `zoom`, `groupName`, `captureOnly`, `allowsInPlaceFiltering`, `tracksLuma`, `lumaUpdateRate`, `disablesOccludedBackdropBlurs`, `windowServerAware`. A `CASDFLayer` (properties `effect`, `gaussianRadius`, `smoothness`, `mergeElements`) and `CASDFElementLayer` exist and are used by Liquid Glass.

### D4. NSVisualEffectView material recipes on macOS 27 (`probe_vev.swift`) — INFERRED (private layer tree), observed live

Each blurring material is a `CABackdropLayer` with `scale = 0.125` (the backdrop is captured at 1/8 linear resolution), filters `[sdrNormalize, gaussianBlur(inputRadius = 30, inputNormalizeEdges = 1), colorSaturate(inputAmount = s)]`, then a semi-transparent grey **tint** `CALayer`, then (for most materials) a solid grey layer with `compositingFilter = lightenBlendMode` (dark appearance) or `darkenBlendMode` (light appearance) — a luminance floor/ceiling — then a `CAChameleonLayer` at opacity 0.05 to 0.08 (wallpaper-tint, INFERRED from name).

| Material | Dark: saturation / tint (grey, alpha) / lighten floor | Light: saturation / tint / darken ceiling |
|---|---|---|
| titlebar | none / 0.235 @ layer opacity 0.8 / — | none / 0.992 @ 0.8 / — |
| menu | 2.2 / 0.157 @ 0.70 / 0.125 | 2.1 / 0.965 @ 0.72 / 0.93 |
| popover | 2.0 / 0.157 @ 0.60 / 0.110 | 2.0 / 0.965 @ 0.60 / 0.945 |
| sidebar | 2.4 / 0.157 @ 0.80 / 0.140 | 2.2 / 0.965 @ 0.84 / 0.915 |
| headerView | none / 0.118 @ 0.8 / — | none / 1.0 @ 0.8 / — |
| hudWindow | 1.6 / 0.157 @ 0.40 / 0.080 | 1.9 / 0.965 @ 0.48 / 0.96 |
| fullScreenUI | 1.8 / 0.157 @ 0.50 / 0.095 | 1.9 / 0.965 @ 0.48 / 0.96 |
| toolTip, underWindowBackground | 2.4 / 0.157 @ 0.80 / 0.140 | 2.2 / 0.965 @ 0.84 / 0.915 |
| windowBackground, contentBackground, underPageBackground, sheet | no backdrop: opaque or near-opaque grey | same |
| selection | no blur: a `vibrantColorMatrixSourceOver` compositing filter | same |

So on macOS 27 every blurring material uses the **same blur** (radius 30 at 1/8 scale) and differs only in saturation, tint and luminance clamp. The blur parameter is a `CAFilter` radius, not a documented σ; what "30" means in pixels is UNVERIFIED (see Part F).

### D5. NSGlassEffectView (Liquid Glass on macOS 27) recipe (`probe_glass.swift`) — INFERRED, observed live

Layer tree: `SwiftUI.SDFLayer` → `CABackdropLayer` (`scale = 0.5`, `marginWidth = 0.5`, `groupName = "SwiftUI:…"`) carrying a single `glassBackground` filter, plus `CASDFLayer`s whose `effect` objects are `CASDFOutputEffect` and `CASDFKeyFillHighlightEffect` (`smoothness = 8`), a `CASDFElementLayer` holding the shape (`cornerRadius = 24` as set), `SDFPortalLayer`/`CAPortalLayer` for content, and `vibrantColorMatrix` filters for the content's vibrancy. Values (cornerRadius 24):

| Key | regular (dark) | regular (light) | clear (dark) | clear (light) |
|---|---|---|---|---|
| inputBlurRadius | 5 | 5 | 8.61 | 8.61 |
| inputBlurOpacity0..3 | 0.55, 0.55, 1, 1 | 0.55, 0.55, 1, 1 | 1, 1, 1, 1 | 1, 1, 1, 1 |
| inputInnerRefractionAmount / Height | −50 / 20 | −50 / 20 | −60 / 20 | −60 / 20 |
| inputOuterRefractionAmount | 0 | 0 | 0 | 0 |
| inputFaceColorMatrixWhite / Black / Saturation | 1.125 / 0.08 / 1.3 | 0.96 / 0.40 / 1.2 | 0.80 / 0.05 / 1.0 | 0.95 / 0.20 / 1.0 |
| inputBleedAmount / Height | 35 / 35 | 35 / 35 | 0 / 0 | 0 / 0 |
| inputKeyFillHighlightAmount / Spread (rad) / Angle (rad) | 0.5 / 2.094 (120°) / 1.571 (90°) | same | 0.4 / 1.309 (75°) / 1.571 | same |
| inputBlurFillBlurRadius; lighten / darken opacity | 8; 0 / 0.675 | 8; 0.675 / 0 | 0 | 0 |
| inputMaxHeadroom | 1.2 | 1.2 | 1.2 | 1.2 |

Reading: Liquid Glass captures the backdrop at **half** resolution (materials use 1/8), applies a **small** blur (radius 5 for regular, about 8.6 for clear, against 30 for classic materials), and spends most of its effect on **refraction near the edge** (inner refraction amount −50 over a 20-unit band from the SDF edge), a **specular key-light rim** (120° spread from the top), a saturation boost of 1.2 to 1.3 for regular glass, and a blurred "blur-fill" layer blended with darken (dark mode) or lighten (light mode). The units of these numbers are not documented (UNVERIFIED).

### D6. UIKit material recipes on iOS 27 (`ios/probe_uikit.swift`, iOS 27.0 simulator runtime 24A5355p) — INFERRED (private layer tree), observed live

Method: a command-line binary compiled with `swiftc -target arm64-apple-ios27.0-simulator` and run with `simctl spawn` in the simulator "Blur2ool nonlinear"; it creates `UIVisualEffectView(effect: UIBlurEffect(style:))` in an offscreen `UIWindow`, forces layout, and prints the layer tree with each `CAFilter`'s `inputKeys`. The simulator runs the same UIKit as the device, but the device's render server is not involved, so this shows the **recipe**, not the pixels.

**System materials (iOS 13+ styles; SwiftUI `Material` maps onto these, INFERRED).** One `UICABackdropLayer` with `scale = 0.25` (backdrop captured at quarter resolution per axis, 1/16 of the pixels), **no tint sublayer**, and four filters in this array order: `luminanceCurveMap(inputAmount, inputValues[4])`, `colorSaturate(inputAmount)`, `colorBrightness(inputAmount)` (light appearance, and dark chrome), `gaussianBlur(inputRadius, inputNormalizeEdges = 1, inputDither = 1)`.

| Style | Blur radius | Saturation | Luminance curve: amount; 4 values (dark) | Luminance curve (light) | Brightness (light) |
|---|---|---|---|---|---|
| systemUltraThinMaterial | 22.5 | 1.1 | 0.50; 0.24, 0.24, 0.30, 0.39 | 0.50; 0.45, 0.55, 0.65, 0.68 | +0.12 |
| systemThinMaterial | 29.5 | 1.35 | 0.60; 0.20, 0.21, 0.10, 0.15 | 0.60; 0.725, 0.825, 0.76, 0.73 | +0.12 |
| systemMaterial | 29.5 | 1.5 | 0.75; 0.16, 0.26, 0.10, 0.10 | 0.75; 0.90, 0.83, 0.925, 0.815 | +0.10 |
| systemThickMaterial | 45 | 1.5 | 0.88; 0.14, 0.16, 0.10, 0.03 | 0.88; 0.99, 0.95, 0.98, 0.905 | +0.045 |
| systemChromeMaterial | 22.5 | 2.0 dark / 1.1 light | 0.75; 0.23, 0.52, 0.27, 0.255 (+ brightness −0.1) | 0.75; 0.80, 0.90, 1.10, 0.825 | +0.10 |

**Legacy styles (iOS 8–12 names, still shipping).** `UICABackdropLayer` with `scale = 0.125` (1/8 per axis), filters `gaussianBlur(inputRadius, inputQuality = default, inputNormalizeEdges = 1)` then `colorSaturate(1.8)`, plus one `_UIVisualEffectSubview` tint layer composited source-over:

| Style | Blur radius | Saturation | Tint layer (grey, alpha) |
|---|---|---|---|
| light | 30 | 1.8 | white, 0.30 |
| extraLight | 20 | 1.8 | 0.97, 0.80 |
| dark | 20 | 1.8 | 0.11, 0.73 |
| regular | follows appearance: = dark (dark mode), = light (light mode) | | |
| prominent | follows appearance: = dark (dark mode), = extraLight (light mode) | | |

Readings: (1) the **same Gaussian blur** family is used everywhere; materials differ mainly in a **luminance remapping** and saturation, not in blur. (2) The luminance curves compress the backdrop's luminance into a narrow band (dark ultra-thin: outputs 0.24–0.39, blended 50% with the original), which is how a material guarantees text contrast over any wallpaper; macOS does the same job with a lighten/darken floor layer (D4). Some curves are **non-monotonic** (dark thick ends at 0.03), so a bright backdrop is pushed *darker* than a mid-grey one. (3) `luminanceCurveMap` is a nonlinear point operation; whether the render server applies the filter array in the listed order (curve → saturate → brightness → blur) or blurs first is UNVERIFIED and matters only for the curve (saturation and brightness are affine colour maps and commute with a normalized blur up to clipping; COMPUTED). (4) The units of `inputRadius` (layer points, device pixels, or pixels of the 1/4-scale capture) are UNVERIFIED; the app must measure the effective σ on device (Part F). (5) The curve's four values are presumably control points at equally spaced input luminances (0, 1/3, 2/3, 1), with `inputAmount` mixing toward identity: INFERRED from the shape of the numbers, UNVERIFIED.

**Liquid Glass on iOS (`UIGlassEffect`).** In an offscreen window without a scene the glass view builds no sublayers, so its recipe could not be dumped on iOS; the macOS 27 `NSGlassEffectView` recipe (D5) is the best available evidence. The `UIGlassEffect` object wraps a private `_UIViewGlass` whose description exposes `GlassMaterialProvider.Configuration(regular|clear)`, a bridged SwiftUI `_Glass`, `frost: automatic`, `size: dynamic`, and Boolean switches `contentLensing`, `excludingPlatter`, `excludingForeground`, `excludingShadow`, `excludingControlLensing`, `excludingControlDisplacement`, `boostWhitePoint`, `highlightsDisplayAngle`, plus `_enabledWithoutSolarium` (INFERRED: "Solarium" is the internal name of the Liquid Glass design). These names confirm the component split: **platter** (the blurred, tinted backdrop), **lensing/displacement** (refraction), **highlights**, **shadow**, **foreground** (content vibrancy).

### D7. Other measurements made for this document (MEASURED on this Mac unless stated)

- `probe_ci_names.swift`: Core Image on macOS 27 has 252 built-in filters. Added to D2: `CIGuidedFilter` (GeometryAdjustment; inputGuideImage, inputRadius 1 [1, 10], inputEpsilon 1e-4 [1e-9, 0.1]); `CIBlurredRectangleGenerator` (inputSigma 10) and `CIBlurredRoundedRectangleGenerator` (inputRadius, inputSmoothness, inputSigma): **analytic shadow generators parameterized directly by σ**; `CICannyEdgeDetector` (inputGaussianSigma 1.6); `CIDepthOfField` (embeds an unsharp mask: inputUnsharpMaskRadius 2.5, inputUnsharpMaskIntensity 0.5); `CIEdgeWork` (radius 3).
- `probe_pixellate.swift`: `CIPixellate` returns the exact cell mean; `CIHexagonalPixellate` also averages; `CICrystallize` / `CIPointillize` do not (A16).
- `probe_shadow.swift` (macOS 27, `CALayer.render(in:)` and `CGContext.setShadow`, 1× linear-grey float context, σ fitted from the 15.9%–84.1% width of the shadow edge, i.e. assuming a Gaussian edge-spread): `CALayer.shadowRadius` r gives σ = 1.977, 3.846, 7.566, 14.96, 29.92 for r = 2, 4, 8, 16, 32 (σ/r = 0.99 → 0.935); `CGContext.setShadow(blur: b)` gives exactly the CALayer value at b = 2r (σ/b = 0.54 → 0.47). So **CALayer shadowRadius r ≈ Quartz shadow blur 2r, σ ≈ 0.94·r for large r**. This is the CPU `render(in:)` path; the GPU render server's shadow on device may differ and should be measured on the iPhone (see `live-calibration.md` §5.5).
- `probe_vibrancy_mac.swift`: vibrant subviews inside a macOS sidebar material get `compositingFilter = plusL` (dark) / `plusD` (light) (B3). The iOS counterpart `ios/probe_vibrancy.swift` hung in the headless simulator (timed out twice) and produced no data.
- `blur_derived.py`: unsharp-mask overshoot and halo extent, USM gain at Nyquist, DoG peak frequencies, and the power-law tail of pyramid bloom PSFs (B10–B12).
- `vev_dump.txt` (re-run of D4 with `probe_vev.swift`): reproduces the D4 table (e.g. menu, dark: radius 30, saturation 2.2, tint 0.157 @ α 0.70, lighten floor 0.125; sidebar, light: saturation 2.2, tint 0.965 @ 0.84, darken ceiling 0.915).

**Note on probe files.** The temp directory of an earlier attempt was cleared, which removed the original `probe_ca.swift`, `probe_ca2.swift` and `probe_glass.swift` scripts behind D3 and D5. Their results were recorded in this file on the same day and are kept. D4 was re-verified by `probe_vev.swift`. Scripts present now: `nl.py` (reference implementations), `amp_transfer.py`, `edges.py`, `grid_sep.py`, `heat.py`, `nlm_ms.py`, `frosted.py`, `probe_ci_names.swift`, `probe_pixellate.swift`, `probe_shadow.swift`, `probe_vev.swift`, `probe_vibrancy_mac.swift`, `blur_derived.py`, `ios/probe_uikit.swift`, `ios/probe_glass_ios.swift`, `ios/probe_glass2.swift`, `ios/probe_vibrancy.swift`. The Python probes need only numpy (the installed SciPy is binary-incompatible with NumPy 2.2 on this Mac, so none of them import SciPy).

## Part E. Sources

Papers and books (cited by title and year in the sections; not all re-read for this document; claims attributed to them are from my knowledge of the papers unless a section says "REFERENCE, fetched"):
- Tomasi & Manduchi 1998, "Bilateral filtering for gray and color images", ICCV.
- Smith & Brady 1997, "SUSAN — a new approach to low level image processing", IJCV 23(1).
- Durand & Dorsey 2002, "Fast bilateral filtering for the display of high-dynamic-range images", SIGGRAPH.
- Paris & Durand 2006 (ECCV) / 2009 (IJCV 81(1)), "A fast approximation of the bilateral filter using a signal processing approach".
- Chen, Paris & Durand 2007, "Real-time edge-aware image processing with the bilateral grid", ACM TOG 26(3).
- Paris, Kornprobst, Tumblin & Durand 2009, "Bilateral filtering: theory and applications", Foundations and Trends in CG&V 4(1).
- Adams, Baek & Davis 2010, "Fast high-dimensional filtering using the permutohedral lattice", CGF 29(2).
- Chen, Adams, Wadhwa & Hasinoff 2016, "Bilateral guided upsampling", ACM TOG 35(6); Gharbi et al. 2017, "Deep bilateral learning for real-time image enhancement" (HDRnet), ACM TOG 36(4).
- Pham & van Vliet 2005, "Separable bilateral filtering for fast video preprocessing", ICME.
- Porikli 2008, "Constant time O(1) bilateral filtering", CVPR; Yang, Tan & Ahuja 2009, "Real-time O(1) bilateral filtering", CVPR; Chaudhury, Sage & Unser 2011, IEEE TIP 20(12).
- Weiss 2006, "Fast median and bilateral filtering", ACM TOG 25(3).
- Petschnigg et al. 2004, "Digital photography with flash and no-flash image pairs", SIGGRAPH; Eisemann & Durand 2004, "Flash photography enhancement via intrinsic relighting", SIGGRAPH; Kopf, Cohen, Lischinski & Uyttendaele 2007, "Joint bilateral upsampling", ACM TOG 26(3).
- He, Sun & Tang 2010, "Guided image filtering", ECCV; 2013, IEEE TPAMI 35(6). He & Sun 2015, "Fast guided filter", arXiv:1505.00996.
- Gastal & Oliveira 2011, "Domain transform for edge-aware image and video processing", ACM TOG 30(4).
- Huang, Yang & Tang 1979, "A fast two-dimensional median filtering algorithm", IEEE TASSP 27(1); Perreault & Hébert 2007, "Median filtering in constant time", IEEE TIP 16(9); Gallagher & Wise 1981, IEEE TASSP 29(6); Astola, Haavisto & Neuvo 1990, "Vector median filters", Proc. IEEE 78(4); Paeth 1990, *Graphics Gems*; McGuire 2008, *ShaderX6*; Adams 2021, "Fast median filters using separable sorting networks", ACM TOG 40(4).
- Kuwahara, Hachimura, Eiho & Kinoshita 1976, in *Digital Processing of Biomedical Images* (Plenum); Papari, Petkov & Campisi 2007, "Artistic edge and corner enhancing smoothing", IEEE TIP 16(10); **Kyprianidis, Kang & Döllner 2009, "Image and video abstraction by anisotropic Kuwahara filtering", CGF 28(7)** (REFERENCE, fetched: kyprianidis.com/p/pg2009/jkyprian-pg2009.pdf; formulas in A9 checked against §3); Kyprianidis, Semmo, Kang & Döllner 2010, EG UK TPCG.
- Lee 1983, "Digital image smoothing and the sigma filter", CVGIP 24(2).
- Koenderink 1984, "The structure of images", Biol. Cybern. 50; Witkin 1983, "Scale-space filtering", IJCAI; Lindeberg 1990, IEEE TPAMI 12(3); Lindeberg 1994, *Scale-Space Theory in Computer Vision*.
- Perona & Malik 1990, "Scale-space and edge detection using anisotropic diffusion", IEEE TPAMI 12(7); Catté, Lions, Morel & Coll 1992, SIAM J. Numer. Anal. 29(1); Weickert 1998, *Anisotropic Diffusion in Image Processing*; Weickert, ter Haar Romeny & Viergever 1998, IEEE TIP 7(3); Black, Sapiro, Marimont & Heeger 1998, IEEE TIP 7(3); Barash 2002, IEEE TPAMI 24(6); Barash & Comaniciu 2004, Image and Vision Computing 22(1).
- Buades, Coll & Morel 2005, "A non-local algorithm for image denoising", CVPR, and SIAM MMS 4(2); Buades, Coll & Morel 2011, IPOL; Darbon et al. 2008, ISBI; Dabov et al. 2007 (BM3D), IEEE TIP 16(8).
- Comaniciu & Meer 2002, "Mean shift: a robust approach toward feature space analysis", IEEE TPAMI 24(5).
- Serra 1982, *Image Analysis and Mathematical Morphology*; van Herk 1992, Pattern Recognition Letters 13(7); Gil & Werman 1993, IEEE TPAMI 15(5); Dorst & van den Boomgaard 1994, Signal Processing 38(1).
- Hill, Zhou, Saul & Shacham 2016, PoPETs 2016(4); McPherson, Shokri & Shmatikov 2016, arXiv:1609.00408.
- Spencer, Shirley, Zimmerman & Greenberg 1995, "Physically-based glare effects for digital images", SIGGRAPH; Kawase 2003, GDC; Jimenez 2014, "Next generation post processing in Call of Duty: Advanced Warfare", SIGGRAPH Advances in Real-Time Rendering.
- Marr & Hildreth 1980, "Theory of edge detection", Proc. R. Soc. Lond. B 207; Burt & Adelson 1983, IEEE Trans. Commun. 31(4); Lowe 2004, IJCV 60(2); Winnemöller, Olsen & Gooch 2006, "Real-time video abstraction", SIGGRAPH; Kang, Lee & Chui 2007, NPAR; Winnemöller 2011, NPAR; Winnemöller, Kyprianidis & Olsen 2012, Computers & Graphics 36(6); Kyprianidis & Döllner 2008, EG UK TPCG.

Specifications and vendor documentation (fetched 13 Oct 2026 unless noted):
- W3C Filter Effects Module Level 1 (w3.org/TR/filter-effects-1/): `blur()` parameter is the Gaussian's standard deviation; `drop-shadow()` third length is a standard deviation; `saturate()` > 100% allowed; filter list applied in order; filter functions operate in sRGB. Filter Effects Module Level 2 (`backdrop-filter`) via `stack-semantics.md` §1.4.
- CSS Backgrounds and Borders 3 (shadow blur σ = radius/2) and HTML canvas shadows, via `stack-semantics.md` §1.3.
- Microsoft Learn: "Acrylic material" (learn.microsoft.com/en-us/windows/apps/design/style/acrylic, updated 2026-10-02); "Mica material" (…/style/mica, updated 2026-07-22); Direct2D "Gaussian blur effect" (learn.microsoft.com/en-us/windows/win32/direct2d/gaussian-blur).
- WinUI 3 source, github.com/microsoft/microsoft-ui-xaml, `controls/dev/Materials/Acrylic/AcrylicBrush.cpp`, `AcrylicBrush.h`, `AcrylicBrush_themeresources.xaml`, `Assets/NoiseAsset_256X256_PNG.png` (main branch).
- Unity Post-Processing Stack v2 source, github.com/Unity-Technologies/PostProcessing (branch v2): `PostProcessing/Shaders/Colors.hlsl` (QuadraticThreshold), `PostProcessing/Shaders/Sampling.hlsl` (DownsampleBox13Tap, UpsampleTent), `PostProcessing/Runtime/Effects/Bloom.cs`.
- Android Open Source Project, "Window blurs" (source.android.com/docs/core/display/window-blurs); RenderEffect semantics via `stack-semantics.md` §2.3.
- Apple WWDC25 session 219, "Meet Liquid Glass" (developer.apple.com/videos/play/wwdc2025/219), transcript paraphrased in B4; Apple Human Interface Guidelines "Materials"; Apple Developer Documentation for UIVisualEffectView, UIBlurEffect, UIVibrancyEffect, Material, NSVisualEffectView, CALayer.shadowRadius/shadowPath, CGBlendMode, glassEffect/UIGlassEffect (consulted for API names; wording paraphrased, not re-fetched page by page).
- Adobe Photoshop Elements help, "Blur filters" (helpx.adobe.com/photoshop-elements/using/blur-filters.html) and Adobe Photoshop CS5 JavaScript reference (`SmartBlurMode`), via search excerpts; Adobe's Photoshop "Filter effects reference" page returned HTTP 403 and was not read.
- Bjango, "Blur radius comparison", 11 Jan 2024 (bjango.com/articles/blurradiuscomparison/): measured scale factors between CSS, Figma, Sketch, Photoshop, Illustrator blur and shadow values.
- Evan Wallace 2016, "Fast rounded rectangle shadows" (madebyevan.com/shaders/fast-rounded-rectangle-shadows/), cited from memory.
- Ben Willmore, CreativeLive lesson "Surface Blur in Photoshop" (via search excerpt).
- ImageJ plugin documentation "Surface Blur" / "Thresholded Blur" (imagejdocu.list.lu), via search excerpts.

On-device / on-Mac evidence: Part D (probes D1–D7), all run 13 Oct 2026 on macOS 27.2 (Darwin 27.2), Xcode 27.0 beta toolchain (Swift 6.4), iOS 27.0 simulator runtime 24A5355p.

## Part F. UNVERIFIED and open questions

1. **Units of Apple's `gaussianBlur.inputRadius`** inside backdrop layers (points, device pixels, or pixels of the 1/4- or 1/8-scale capture) and therefore the effective σ of every Apple material and of Liquid Glass. Plan: on the iPhone, render a high-contrast step and an impulse grid, place each material over it, capture, and fit σ (method of `live-calibration.md` §3.3). Until then, show the recipe numbers labeled INFERRED and the fitted σ labeled MEASURED.
2. Whether Core Animation applies a backdrop layer's `filters` array in listed order (iOS system materials list `luminanceCurveMap` before `gaussianBlur`). Matters only for the nonlinear curve.
3. The meaning of `luminanceCurveMap.inputValues` (assumed: 4 control points at equally spaced luminances, mixed with identity by `inputAmount`) and the luma weights of `colorSaturate`.
4. SwiftUI `Material` → `UIBlurEffect.Style` mapping, especially `.ultraThickMaterial` and `.bar`.
5. Liquid Glass on iOS: the `glassBackground` parameter values were read on **macOS 27** (`NSGlassEffectView`, D5); the iOS values may differ (the iOS probe could not build a glass layer tree without a window scene). The refraction model `d = A·φ(D/H)·n̂` and the sign of "amount −50" are INFERRED; the falloff φ is unknown.
6. `UIVibrancyEffect` on iOS: assumed to use `vibrantDark`/`vibrantLight` filters; the simulator probe hung, so only macOS (`plusL`/`plusD`) was observed.
7. Photoshop Surface Blur's exact range weight (hard cutoff vs tent; the community "2.5 × threshold" constant) and spatial kernel (flat vs Gaussian); slider ranges; Smart Blur's algorithm and the meaning of Quality; the CS2/PS4–5 introduction versions. Adobe's Elements help sentence that pixels with differences *less* than Threshold are excluded appears to be a documentation error.
8. Photoshop *Oil Paint* algorithm; Blender's Kuwahara node version (stated as 4.0 from memory).
9. Acrylic: whether the Windows composition `GaussianBlurEffect.BlurAmount` is exactly Direct2D's standard deviation in DIPs and whether DWM downsamples internally. Mica's blur size and tint values (not published).
10. Android: which window-blur filter (Kawase, Gaussian, dual Kawase) a given device ships; system-UI blur in specific Android releases; the Haze library's exact mechanism.
11. Firefox's `backdrop-filter` default-on version (stated as 103, 2022, from memory); apple.com's current backdrop recipe.
12. CALayer shadow σ on the **GPU** render server path (measured here only through `render(in:)` on macOS, σ ≈ 0.94–0.99 r); SwiftUI `.shadow(radius:)` semantics.
13. Kuwahara colour handling in specific apps; mean-shift parameter pairs in Comaniciu & Meer's figures; NLM h recommendations in the IPOL paper.
14. Adams 2021's exact complexity claim for separable sorting networks (summarized loosely in A1).
15. Whether `CIEdgePreserveUpsampleFilter` is a joint bilateral upsampler (INFERRED from parameter names only).
16. `CICrystallize` / `CIPointillize` sampling rule (measured: not the cell mean; exact rule unknown).

Status of honesty labels in this file: every number from a probe is COMPUTED (closed-form or numerical consequence of a definition) or MEASURED (timed/fitted on this Mac); every private-API recipe value is INFERRED evidence (observed live in private layer trees, could change in any OS update); vendor and spec statements are REFERENCE with their source; anything else is marked UNVERIFIED.

<!-- STATUS: COMPLETE -->
