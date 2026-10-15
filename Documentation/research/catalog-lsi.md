# Blur2ool research — catalog of linear shift-invariant (convolution) blurs

Status: COMPLETE (written incrementally across two passes). Date: 13 October 2026.
Scope: every blur in this file is (or is presented as an approximation of) a linear shift-invariant operator `g = h * f`. Non-LSI blurs (bilateral, radial/zoom, lens-dependent bokeh with occlusion, variable-σ) live in other catalog files (`catalog-nonlinear.md`, `catalog-spatial.md`). What each tool's "radius" means is in `stack-semantics.md`; Metal patterns and bandwidth models are in `gpu-pipeline.md`. This file is the math and fingerprint layer.
Honesty labels follow BRIEF.md: COMPUTED (exact math, many verified numerically here with probe scripts in `$TMPDIR/blur2ool-lsi/`), REFERENCE (cited), MODELED, INFERRED, UNVERIFIED.

## Contents

0. Conventions and shared math
1. box-blur
2. gaussian-blur (continuous + truncation at kσ)
3. gaussian-separable (two-pass)
4. gaussian-linear-sampling (bilinear tap merging)
5. tent-blur (triangle, box∘box)
6. binomial-blur (Pascal kernels)
7. iterated-box (CLT, Wells 1986, Kovesi 2010, Kutskir)
8. stack-blur (Klingemann 2004)
9. sat-box (summed-area table, Crow 1984)
10. iir-gaussian (Deriche 1993, Young–van Vliet 1995)
11. fft-convolution
12. kawase-blur (Kawase 2003)
13. dual-kawase (Bjørge 2015)
14. pyramid-blur (mip chain, Jimenez 2014 CoD bloom)
15. disc-blur (pillbox)
16. exponential / Laplace / Lorentzian kernels
17. frequency-domain low-pass: ideal (brick-wall) and Butterworth
18. contrast note: Lanczos / sinc (not a blur)
19. Others found (motion/line PSF as LSI, hexagonal/polygon aperture, Bartlett/Hann/raised-cosine windows, cubic B-spline)
20. Comparison table
21. Sources
22. Open questions / UNVERIFIED list

---

## 0. Conventions and shared math

These conventions hold for every section below, so the app can compare blurs on one axis system.

**Operator.** An LSI blur is a convolution `g(x) = (h * f)(x) = ∫ h(t) f(x − t) dt` (2-D: `∫∫ h(s,t) f(x−s, y−t) ds dt`). The kernel `h` is the point-spread function (PSF): the image of a single bright pixel (an impulse). Linearity means `blur(a·f1 + b·f2) = a·blur(f1) + b·blur(f2)`; shift invariance means the same PSF everywhere. Together they mean one PSF and one frequency response describe the blur completely. A blur that is not LSI (bilateral, zoom, variable radius, Kawase with its per-pass offsets is still LSI, but a mip-chain with nonlinear thresholding is not) has no single PSF or MTF.

**Discrete form.** `g[n] = Σ_k h[k] f[n − k]`. In 2-D, `g[m,n] = Σ_j Σ_k h[j,k] f[m−j, n−k]`. Images are sampled on the integer grid, pixel centres at integers.

**Fourier convention.** `H(ν) = ∫ h(x) e^{−2πiνx} dx`, with ν in cycles per pixel. The Nyquist frequency of a pixel grid is ν = 0.5 cycles/pixel. For discrete kernels the DTFT is `H(ν) = Σ_k h[k] e^{−2πiνk}`, periodic with period 1. Convolution theorem: `G = H·F`. The modulation transfer function (MTF) is `|H|`. For a real, symmetric kernel `H` is real; where `H < 0` the blur passes that frequency **with inverted phase** (a light bar becomes dark): "contrast inversion" or "spurious resolution", the signature of box and disc blurs.

**Normalization.** `Σ h = 1` ⇔ `H(0) = 1`: flat regions keep their value (DC preserved). Every blur here is normalized unless stated otherwise.

**Spread (σ).** For a zero-mean kernel, `σ² = Σ k² h[k]` (continuous: `∫ x² h(x) dx`). **Variances add under convolution** (cumulants are additive), so a chain of blurs has `σ_total = sqrt(σ1² + σ2² + …)`. This one rule underlies iterated box, tent, binomial, Kawase, dual-Kawase and the "match σ" conversions in the app. The 2-D PSF of a separable kernel `h(x)h(y)` has per-axis σ equal to the 1-D σ. COMPUTED.

**Separability vs isotropy.** A 2-D kernel is separable if `h(x,y) = a(x)·b(y)`: one horizontal and one vertical 1-D pass give the same result, and cost drops from O(r²) to O(r) per pixel. It is isotropic if it depends only on `sqrt(x² + y²)`. The Gaussian is the only kernel (with finite variance) that is both separable and isotropic (a classic characterization; one statement is Maxwell's derivation of the velocity distribution; see Kac 1939, "On a characterization of the normal distribution", Amer. J. Math. 61). Every other separable kernel (box, tent, binomial) is anisotropic: its PSF is a square or a diamond-ish blob, which shows on a Siemens star as stronger blur along the diagonals than along the axes (for box) or vice versa. REFERENCE (Kac 1939) + COMPUTED (probe `aniso.py`, §1).

**Positivity.** A kernel with all `h ≥ 0` is a weighted average: output stays inside the input range [min, max] and no overshoot/halo appears at edges. Kernels with negative lobes (sinc, Lanczos, ideal low-pass, Butterworth in the spatial domain) ring. Note that a kernel can be positive in space and still have negative `H` (box, disc, tent is the exception: `sinc²` is ≥ 0).

**Semigroup.** A family `h_t` is a semigroup if `h_s * h_t = h_{s+t}`. Gaussians with parameter `t = σ²` form a semigroup (scale space). Boxes do not (box∘box = tent). Binomials do in their discrete parameter: `B_m * B_n = B_{m+n}`.

**Edge (boundary) handling.** A convolution needs pixels outside the image. The options the app should expose, with their visual signatures on a bright-edged image:
- *zero / transparent black* (`clamp_to_zero` in Metal, `CIImage` unclamped default): edges darken and alpha falls off; output extent grows by the kernel radius (Core Image's blur output extent is larger than its input for this reason; the usual fix is `clampedToExtent()` then crop).
- *clamp to edge / replicate* (`clamp_to_edge`): the border pixel is smeared outward; no darkening; streaks at strongly coloured borders.
- *mirror / reflect* (`mirror_repeat`): symmetric continuation; least visible for natural images; preserves mean near edges.
- *wrap / periodic* (`repeat`): the opposite edge bleeds in. This is what FFT convolution does unless you pad.
- *renormalize* ("valid weights only"): divide by the sum of weights that fell inside. No darkening, but the effective kernel becomes one-sided near edges, so the PSF changes there (the blur is no longer exactly shift invariant at the border).
Metal sampler address modes: `clamp_to_zero`, `clamp_to_edge`, `clamp_to_border`, `mirrored_repeat`, `repeat` (REFERENCE: Metal Shading Language Specification, "Sampler" section; `MTLSamplerAddressMode`).

**Colour space.** All the math here is linear. Blurring gamma-encoded sRGB values is a different (nonlinear) operator in light: bright highlights shrink and dark halos appear around them. Blurring premultiplied alpha is the correct way to avoid dark fringes at transparent edges. The app should blur in linear light, premultiplied, and offer the gamma-space variant as a comparison (see `stack-semantics.md` §7).

**Cost vocabulary.** Per output pixel, for a kernel of radius `r` (width `w = 2r+1`):
- naive 2-D: `w²` taps (multiply-adds and texture fetches)
- separable: `2w` taps in 2 passes
- separable + bilinear tap merging: about `2·(r+1)` fetches (≈ half)
- sliding window / running sum: O(1) per pixel per pass, independent of r (box family only)
- SAT: 4 fetches per pixel after an O(1)-per-pixel build; any box size, any position
- IIR: O(1) per pixel per pass, independent of σ, about 2·(3 or 4) MADs per direction
- FFT: O(log N) per pixel, independent of kernel size and shape
- pyramid / Kawase / dual-Kawase: O(1) taps per pass, O(log σ) passes on shrinking textures, so total work ≈ O(1) per full-res pixel.

**Test images (procedural, per BRIEF).** impulse (PSF directly), impulse grid, step edge (edge-spread function, overshoot, ringing), Siemens star (isotropy and contrast inversion: rings where the MTF crosses zero), zone plate `cos(π k r²)` (frequency response laid out in space, aliasing), checkerboard (Nyquist and near-Nyquist content), text (perceived legibility), night-city point lights (PSF shape made visible, bokeh).

---

## 1. box-blur

**id** `box-blur`. **Name / aliases:** box blur, mean filter, moving average, boxcar, uniform filter, "Box Blur" (Photoshop), `CIBoxBlur` (Core Image), `MPSImageBox`, `vImageBoxConvolve_*`, OpenCV `blur()` / `boxFilter()`. **Family:** LSI, separable, positive, FIR; first member of the B-spline / iterated-box family.

**Continuous definition.** 1-D: `h(x) = (1/W)·rect(x/W)` (1/W for |x| < W/2, else 0). 2-D square box: `h(x,y) = h(x)·h(y)`. The output is the plain average over a W×W window.

**Parameters.** Width `W` (or radius `r`, `W = 2r+1` discrete). Variance per axis: continuous `W²/12`; discrete odd width `w`: `σ² = (w² − 1)/12` (COMPUTED, verified in `basics.py`: w=3 → 0.667, w=9 → 6.667, w=31 → 80.0). So a box "radius 10" (w = 21) has σ ≈ 6.06 px, not 10. To match a Gaussian σ with one box: `w ≈ sqrt(12σ² + 1)` ≈ 3.46σ. Tools disagree on whether "radius" means r or w and whether w can be even (even widths shift the image by half a pixel); see `stack-semantics.md`.

**Discrete kernel.** `h[k] = 1/w` for `|k| ≤ r`. Normalization is exact. No truncation (finite support). Fractional widths are possible by giving the two end taps a fractional weight (the "extended box" of Gwosdek et al. 2011, §7). Edge handling: any of the §0 modes. With a sliding window the edges are handled by pre-padding (mirror or clamp) or by dividing by the in-bounds count (renormalize).

**Frequency response (closed form).** Continuous: `H(ν) = sinc(Wν) = sin(πWν)/(πWν)`. Discrete odd w: the Dirichlet kernel `H(ν) = sin(πwν)/(w·sin(πν))`. First zero at `ν = 1/w`; half-amplitude at `ν ≈ 0.604/w`. **Negative lobes:** the deepest is −0.2172 (continuous; at `Wν ≈ 1.430`), and −0.333, −0.250, −0.227, −0.219 for w = 3, 5, 9, 21 (COMPUTED). So the box passes about 22% of some frequencies with inverted contrast. At Nyquist (checkerboard) the response is `(−1)^r / w`: a 3-tap box returns a checkerboard at −1/3 contrast, phase-inverted (COMPUTED). In 2-D the MTF is `sinc(Wνx)·sinc(Wνy)`: the zero set is a square grid of lines `νx = k/W` and `νy = k/W`, not circles.

**Properties.** Linear, shift invariant, separable, positive (no overshoot in space), normalized. **Not isotropic:** the 2-D PSF is a square. Second moments are equal in every direction (any separable kernel with equal axis variances has isotropic covariance), so the anisotropy only appears at fourth order: directional kurtosis is 1.8 along the axes and 2.4 along the diagonals (Gaussian: 3) (COMPUTED). In frequency the axis and diagonal MTFs of a 9-px box differ by more than 0.05 from ρ ≈ 0.72/w, and the first null is at ρ = 1/w along the axes but √2/w along the diagonals (COMPUTED, `aniso.py`). Not a semigroup (box∘box = tent). Not edge preserving. Positive in space but **not** positive in frequency: this is the clearest "positive kernel ≠ positive MTF" example in the catalog.

**Algorithms and cost per pixel (2-D, radius r).**
- Naive 2-D: `w²` adds. Separable: `2w`.
- Sliding window / running sum (moving average): per pass `s[n] = s[n−1] + f[n+r] − f[n−r−1]`, then one multiply. **O(1) per pixel, independent of r**: 2 adds + 1 multiply per pass, 2 passes (Getreuer 2013, §3.3, eq. 32). Integer arithmetic is exact; float accumulators drift (error grows like √N·ε along a row for fp32), so GPU implementations either restart the sum per tile or use the SAT form.
- SAT (integral image): 4 fetches, any w, even per-pixel varying w (§9).
- FFT: possible but pointless for a box.

**Approximation error.** None for the box itself (it is exact). As an approximation of a Gaussian of equal σ, one box pass has ℓ∞ operator error ≈ 0.13–0.2 at σ = 5 (Getreuer 2013, Table 3 lists 0.129 for K=3 boxes; a single box is worse; PSNR 41.6 dB on a test image for K=1 vs exact, Fig. 11). REFERENCE.

**GPU implementation.**
- Fragment, separable: horizontal pass of `w` taps, vertical pass of `w` taps. With bilinear tap merging (two equal-weight neighbours fetched at the half-texel point) a box needs `ceil(w/2)` fetches per pass, and the merge is exact because both weights are equal (the bilinear midpoint gives 0.5/0.5). A 2×2 box is a single bilinear fetch at a texel corner.
- Compute, sliding window: one thread per row (then per column) keeps the running sum in a register: 2 reads per pixel per pass regardless of r, but only `height` threads are active in the horizontal pass, so it is latency-bound on small images. A tiled variant (threadgroup loads a row segment plus an r-pixel apron into threadgroup memory, then each thread does a prefix sum and subtracts) is the usual compromise. See `gpu-pipeline.md` §3.3.
- Apple: `MPSImageBox` (kernel width/height; documented as odd sizes) and `vImageBoxConvolve_ARGB8888` (CPU) exist. REFERENCE (Apple developer documentation pages for these symbols). Core Image `CIBoxBlur` has an `inputRadius` parameter whose width is not documented; `live-calibration.md` MEASURED it on macOS 27.2 as a square box of width ≈ r − 1 (not 2r+1), while `MPSImageBox` and vImage box are exact (2r+1) kernels. iOS may differ; the app re-measures with an impulse.

**Visual fingerprint (what makes it unique).**
- PSF of a point light is a **hard-edged square** (anisotropic, "pixel-art" bokeh). On the night-city image every light becomes a flat square tile.
- Edge spread is a **linear ramp** (the integral of a rect) with sharp corners at the ramp ends: edges look "flat-shaded" rather than soft.
- **Contrast inversion:** fine stripes at spatial periods between w/2 and w come out phase-reversed at up to 22% contrast. On a **Siemens star** this shows as a grey ring (first null) and then a ring of reversed spokes inside it, and the rings are squarish, not round. This is the best single test image for the box. A zone plate shows the same as nested square null contours.
- Text: stems of width close to w/2 can invert or "double".
- Neighbours: tent and iterated box remove the inversion (tent: MTF = sinc² ≥ 0); Gaussian removes the square shape.

**Where used.** Photoshop Filter > Blur > Box Blur; `CIBoxBlur`; `MPSImageBox`; vImage box convolve; OpenCV `blur`/`boxFilter`; three successive box passes implement SVG/CSS `feGaussianBlur` for σ ≥ 2 (Filter Effects Module Level 1, `feGaussianBlur` section; see §7) and Skia/Blink historically (see `stack-semantics.md`); integral-image box filters in Viola–Jones face detection (2001) and SURF (2006).

**Signature.** "The honest average: flat, square, and fast, but it flips fine stripes inside out."

## 2. gaussian-blur

**id** `gaussian-blur`. **Aliases:** Gaussian blur, Gaussian smoothing, normal kernel, heat kernel, scale-space smoothing, `feGaussianBlur`, CSS `filter: blur()`, `CIGaussianBlur`, `MPSImageGaussianBlur`, OpenCV `GaussianBlur`. **Family:** LSI, separable **and** isotropic, positive, semigroup. Reference kernel for the whole catalog: every other "smooth" blur is described by how it deviates from this one.

**Continuous definition.** `G_σ(x) = (2πσ²)^(−1/2) · exp(−x²/(2σ²))`; 2-D `G_σ(x,y) = (2πσ²)^(−1) · exp(−(x²+y²)/(2σ²)) = G_σ(x)·G_σ(y)`. It is the solution of the heat equation `∂u/∂t = ½∇²u` at time `t = σ²` (Getreuer 2013 §2.1; Lindeberg 1990).

**Parameters.** One: σ (standard deviation, pixels). Derived: variance σ²; FWHM = `2·sqrt(2 ln 2)·σ ≈ 2.3548σ`; "radius" in most tools is a truncation radius `r = k·σ` with k between 2 and 4, or σ itself (CSS `blur(10px)` means σ = 10 px), or 2σ (CSS `box-shadow` blur radius, canvas `shadowBlur`). The mapping per tool is in `stack-semantics.md`. 2-D anisotropic generalization: covariance matrix Σ (σx, σy, angle θ): `G(x) ∝ exp(−½ xᵀ Σ⁻¹ x)`; separable only when θ is 0° or 90° (otherwise use two 1-D passes along skewed axes, e.g. Geusebroek, Smeulders & van de Weijer 2003, "Fast anisotropic Gauss filtering", IEEE TIP 12(8)).

**Discrete kernel construction.** Four common discretizations (Getreuer 2013 §2.1, Table 1):
- *Sampled + normalized* `g[n] = G_σ(n)/S`: the default everywhere. For σ ≥ 1 it is essentially exact; below σ ≈ 0.7 the samples under-represent the tails and the kernel's true σ falls short: target σ = 0.5 gives actual σ = 0.464; σ = 0.4 → 0.284; σ = 0.3 → 0.088 (the centre weight is 0.992, so the "blur" does almost nothing). COMPUTED (`basics.py`).
- *Integrated (box-averaged)* `g[n] = ½[erf((n+½)/(σ√2)) − erf((n−½)/(σ√2))]`: models a pixel as an area; adds the pixel's own 1/12 variance, true σ = sqrt(σ² + 1/12) (σ = 1 → 1.041). COMPUTED.
- *Lindeberg's discrete Gaussian* `g[n] = e^(−t) I_n(t)`, t = σ², modified Bessel `I_n`: the only one that keeps the semigroup property exactly on the integer grid and has true σ for all σ (σ = 0.3 gives σ = 0.300). Lindeberg 1990, "Scale-space for discrete signals", IEEE PAMI 12(3). COMPUTED.
- *Band-limited (sinc-interpolated)* `g[n] = (G_σ * sinc)(n)`: what you get by multiplying a DFT by `exp(−2π²σ²ν²)` (§11).
**Truncation at kσ.** Finite kernels keep `|n| ≤ r = ceil(kσ)` and renormalize. COMPUTED values (continuous, `basics.py`):

| k | mass outside ±kσ | edge tap / peak | σ of truncated kernel / σ | min of MTF (σ = 5) |
|---|---|---|---|---|
| 1.5 | 13.4% | 0.325 | 0.743 | −0.052 |
| 2.0 | 4.55% | 0.135 | 0.880 | −0.017 |
| 2.5 | 1.24% | 0.044 | 0.955 | −0.0042 |
| 3.0 | 0.27% | 0.011 | 0.987 | −0.0011 |
| 3.5 | 0.047% | 0.0022 | 0.997 | — |
| 4.0 | 0.0063% | 0.00034 | 0.9995 | — |

Getreuer's Theorem 1 bounds the ℓ∞ error of truncation by `2·erfc(r/(σ√2))·‖f‖∞`, so `r = ceil(√2·erfc⁻¹(tol/2)·σ)`, e.g. `r ≈ 3.48σ` for tol = 10⁻³ (REFERENCE, Getreuer 2013 eq. 20 and 24). For 8-bit SDR output, k = 3 is invisible; for HDR highlights 100× brighter than white, a truncation step of 1% of the peak is visible as a hard boundary. Note that **separable truncation gives a square support** (side 2kσ): on an HDR point light a k = 2 truncated Gaussian draws a faint square, not a circle.
**Edge handling:** any §0 mode; Getreuer uses half-sample symmetric (mirror) extension throughout.

**Frequency response.** `Ĝ(ν) = exp(−2π²σ²ν²)`: a Gaussian, positive everywhere, no zeros, no contrast inversion. 2-D: `exp(−2π²σ²(νx² + νy²))`, perfectly circular. Half-amplitude at `ν½ = sqrt(ln 2/(2π²))/σ ≈ 0.1874/σ` cycles/px. At Nyquist (ν = 0.5): `exp(−π²σ²/2)` = 0.29 for σ = 0.5, 0.0072 for σ = 1, 2.7·10⁻⁹ for σ = 2 (COMPUTED). Truncation multiplies by a rect in space = convolves the MTF with a sinc, which adds the small negative ripples in the table above.

**Properties.** Linear, shift invariant, separable, isotropic (the only kernel that is both; Kac 1939), positive, normalized, infinitely smooth, **semigroup** `G_σ1 * G_σ2 = G_sqrt(σ1²+σ2²)`. Scale-space causality: in 1-D, it is the only kernel in a broad class that never creates new local extrema or new zero crossings of the second derivative as σ grows (Babaud, Witkin, Baudin & Duda 1986, IEEE PAMI 8(1); Yuille & Poggio 1986, IEEE PAMI 8(1)). Minimum space–bandwidth product (Heisenberg–Weyl equality only for Gaussians). Not edge preserving.

**Algorithms and cost (per pixel, 2-D).**
- Naive 2-D FIR: `(2r+1)²` with `r = kσ`: O(σ²).
- Separable FIR: `2(2r+1)`: O(σ). §3.
- Separable FIR + bilinear merging: `2(r+1)` fetches. §4.
- Iterated box / extended box / SII: O(1), approximate. §7, §9.
- Recursive IIR (Deriche, Young–van Vliet, Alvarez–Mazorra): O(1), ~10⁻³–10⁻² error. §10.
- FFT/DCT: O(log N), exact for the band-limited discretization. §11.
- Pyramid (downsample, small blur, upsample): O(1), approximate and slightly shift-variant. §14.
Getreuer's recommendation (REFERENCE, 2013 §6): FIR for σ < 2; Deriche or Vliet–Young–Verbeek above; DCT for best accuracy; box/SII for best speed.

**GPU implementation.** Two-pass separable fragment or compute shader (§3), with bilinear tap merging (§4). For large σ the common production path is to downsample by 2^m first, blur with σ/2^m, and upsample (§14). `MPSImageGaussianBlur(device:sigma:)` is Apple's GPU primitive; how it chooses kernels internally is not documented (INFERRED: it is expected to use separable passes, possibly with downsampling for large σ; the app can measure the PSF it actually produces).

**Visual fingerprint.** Round, soft PSF with no hard edge (a point light becomes a soft round glow with no visible rim); edge-spread is an erf S-curve with no overshoot; Siemens star loses contrast smoothly toward the centre with **no** reversed rings and a perfectly circular grey disc; zone plate fades out as concentric circles. Best test: Siemens star or zone plate side by side with box (§1) and disc (§15) of equal σ; the Gaussian is the only one with no rings at all. Truncation shows only on HDR point lights (square boundary).

**Where used.** Everywhere: CSS `filter: blur()` and `backdrop-filter` (Filter Effects Module Level 1 defines `blur()` via `feGaussianBlur` with stdDeviation = the length); SVG `feGaussianBlur`; Core Image `CIGaussianBlur`; MPS; Photoshop/GIMP/Figma/Sketch "Gaussian blur" / "layer blur"; SwiftUI `.blur(radius:)` (INFERRED to be Gaussian-like; measure, see `live-calibration.md`); Android `RenderEffect.createBlurEffect`; Flutter `ImageFilter.blur`; scale-space and SIFT (Lowe 1999/2004); Canny edge detection (1986).

**Signature.** "The only blur that is round and separable at once; it fades every detail smoothly and never lies about phase."

## 3. gaussian-separable

**id** `gaussian-separable`. **Aliases:** two-pass Gaussian, separable convolution, H+V blur. **Family:** implementation strategy of `gaussian-blur` (and of any separable kernel: box, tent, binomial, exponential-product).

**Definition.** `G_σ(x,y) = G_σ(x)·G_σ(y)` ⇒ `G * f = G_y * (G_x * f)`. Exact (no approximation) for any separable kernel; the order of the passes does not matter mathematically.

**Parameters.** σ, truncation k, intermediate precision, pass order.

**Discrete construction.** Same 1-D taps as §2, applied once along rows and once along columns. The intermediate image must hold values with more precision than the output: rounding the intermediate to 8 bits adds an extra quantization step of up to ½ LSB, which shows as **banding in smooth gradients and dark skies**, made worse by gamma (dark tones have few codes). Use `rgba16Float` (or 32-bit) for the intermediate. MODELED.

**Frequency response.** Identical to the 2-D kernel: `Ĝ(νx)·Ĝ(νy)`. For truncated kernels, separable truncation gives a square support (not a disc), so the MTF error is anisotropic (largest along the diagonals). COMPUTED in principle; the app can show it.

**Properties.** As §2. Two passes need one intermediate texture (ping-pong) and one extra full-image write + read.

**Algorithms and cost.** Per pixel: `2(2r+1)` MACs vs `(2r+1)²`. Example σ = 10, k = 3 → r = 30: 122 taps (61 per pass) vs 3,721 for direct 2-D (COMPUTED). Memory traffic per pass (fragment, no cache reuse model): 1 write + (2r+1) reads, but texture caches turn the reads into roughly 1 read per pixel per pass for a horizontal pass, and vertical passes are more cache-sensitive on row-major layouts (Apple GPUs use twiddled/tiled texture layouts, so vertical and horizontal behave similarly; INFERRED). CPU implementations often transpose between passes so both passes stream along rows.

**GPU implementation.**
- *Fragment ping-pong:* pass H: render quad into texture T1, each fragment sums `2r+1` (or `r+1` with §4) taps along x; pass V: T1 → output along y. Two render passes, one intermediate.
- *Compute with threadgroup tile + apron:* a threadgroup loads `T + 2r` pixels of a row (or a `T×T` tile plus an r-wide apron on one axis) into threadgroup memory once, then each thread does the dot product from fast memory. Loads per output pixel = `(T+2r)/T`, e.g. T = 256, r = 30 → 1.23 loads/pixel instead of 61 (COMPUTED). See `gpu-pipeline.md` §3.2.
- Apple: `MPSImageGaussianBlur`.
**Approximation error.** None beyond truncation and intermediate precision.

**Visual fingerprint.** Identical to `gaussian-blur` when done in float. In 8-bit intermediate: banding. With large k-truncation and HDR: square halo boundary. The interesting thing for the app is the **intermediate image**: after the H pass a point light is a horizontal streak, which the V pass turns into a round blob. Showing the half-blurred streak is the clearest way to explain separability.

**Where used.** Practically every real-time Gaussian (games, browsers' Skia GPU backend, MPS).

**Signature.** "One blur, done as two cheap streaks: horizontal smear, then vertical smear, and the round blob appears only at the end."

## 4. gaussian-linear-sampling

**id** `gaussian-linear-sampling`. **Aliases:** linear-sampled Gaussian, bilinear tap merging, "free" bilinear taps, optimized Gaussian. **Family:** GPU implementation trick for any positive separable kernel (Gaussian, binomial, tent, box). Rákos, "Efficient Gaussian blur with linear sampling", RasterGrid blog, 7 Sept 2010 (REFERENCE; the idea predates the post in demo-scene and vendor material, original inventor UNVERIFIED).

**Definition.** A bilinear texture fetch at a fractional position `k + t` between texels `k` and `k+1` returns `(1−t)·f[k] + t·f[k+1]`. So two adjacent taps with positive weights `a` (at k) and `b` (at k+1) equal one fetch at offset `k + b/(a+b)` multiplied by `a + b`. The kernel is unchanged; only the fetch count drops.

**Parameters.** Same as the underlying kernel. Tap-pairing scheme: centre tap alone plus pairs (1,2), (3,4), … for odd-length kernels; or pairs straddling the centre when sampling from a half-resolution texture.

**Discrete construction (worked example, COMPUTED and matching Rákos 2010).** Pascal row 12 (`1 12 66 220 495 792 924 792 495 220 66 12 1`, sum 4096), drop the 1 and 12 at each end (sum 4070): 9 taps with weights 0.2270270270 (centre), 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162. Merged: offsets 0, 1.3846153846, 3.2307692308 with weights 0.2270270270, 0.3162162162, 0.0702702703. Nine fetches become five per pass. (The blog text says four outermost coefficients are dropped; the numbers show the two outermost per side. Its 9-tap kernel is a binomial with σ = sqrt(12)/2 ≈ 1.73 before truncation; the truncated 9-tap kernel has σ ≈ 1.69 (COMPUTED).) General count for a radius-r kernel: `1 + 2·ceil(r/2)` fetches per pass instead of `2r+1`, about half (σ = 10, k = 3: 31 instead of 61).
**2-D single-pass variant:** a 2×2 block of weights merges into one bilinear fetch if the block is rank-1 (`w00·w11 = w01·w10`), which holds for any separable kernel. A single-pass `(2r+1)²` separable kernel needs `(r+1)²` fetches. Useful when a second pass is not allowed (e.g. one fragment pass in a backdrop).

**Frequency response.** Same as the underlying kernel, up to sub-texel quantization. GPUs carry texel coordinates with a limited fraction: Direct3D requires at least 8 fractional bits (1/256 texel) for filtering and many GPUs interpolate with 8-bit weights (REFERENCE: Reed, "Texture Gathers and Coordinate Precision", reedbeta.com; Quilez, "hardware interpolation" article, iquilezles.org). With 8-bit weights the merged-pair weight error is at most `(a+b)/512`; for the example above ≤ 6·10⁻⁴ of the total, invisible in 8-bit output. Apple GPU sub-texel precision is **UNVERIFIED**; the app can MEASURE it by sampling a two-texel 0→1 ramp at 1,024 positions and counting distinct outputs.

**Properties.** Exact restatement of a positive kernel (merging needs `a, b ≥ 0`; for negative pairs the offset falls outside [k, k+1]). Requires a filterable texture format (`rgba8Unorm`, `rgba16Float` are filterable on all Apple GPUs; 32-bit float filtering support varies by GPU family, check the Metal feature set tables; UNVERIFIED for A17 Pro here) and a sampler with `linear` min/mag filter and the chosen address mode. Does not apply to compute kernels that read with `read()` (no filtering) unless they `sample()`.

**Cost.** Per pixel per pass: `1 + 2·ceil(r/2)` fetches, same MAC count as fetches. Rákos measured roughly 60% higher throughput on a Radeon HD 5770 for the linear version, roughly proportional to fetches saved (REFERENCE; exact frame rates are only shown in a graph).

**GPU implementation.** Precompute `(offset, weight)` pairs on the CPU (BlurCore), pass as a small constant buffer, loop in the fragment shader: `sum += w[i] * (tex.sample(s, uv + o[i]*dir) + tex.sample(s, uv − o[i]*dir))`. Fragment shaders on Apple GPUs can use the texture unit's filtering for free; compute shaders can too via `sample()`.

**Visual fingerprint.** None by design: it should be pixel-identical to the discrete kernel within 1 LSB. That **is** its fingerprint for the app: show the two fetch patterns over the texel grid (taps at integer centres vs taps at fractional points between them) and a difference image that is black. A deliberately broken variant (fetching at the wrong fraction, or on a `nearest` sampler) shows a one-sided ghost and a σ change, which is a good teaching toggle.

**Where used.** Most real-time engines' Gaussian and bloom passes; Rákos 2010; also built into the dual-Kawase and CoD-style downsample filters (§13, §14), which are linear-sampled kernels by construction.

**Signature.** "The same Gaussian for half the fetches: let the texture hardware do the in-between."

## 5. tent-blur

**id** `tent-blur`. **Aliases:** tent filter, triangle filter, Bartlett window/kernel, box∘box, linear B-spline (order 2), "bilinear" kernel (the bilinear interpolation kernel is a tent of half-width 1 px). **Family:** LSI, separable, positive, FIR; second member of the B-spline / iterated-box family.

**Continuous definition.** `Λ_a(x) = (1/a)·max(0, 1 − |x|/a)`, half-width `a`, total support `2a`. It equals `rect_a * rect_a`, the convolution of two boxes of width `a`. 2-D separable form `Λ_a(x)·Λ_a(y)`: a square-based pyramid (not a cone).

**Parameters.** Half-width `a` (or discrete radius `r`). Variance per axis: continuous `a²/6`; discrete radius-r tent `h[k] = (r+1−|k|)/(r+1)²`, `|k| ≤ r`, has `σ² = r(r+2)/6` (it is the convolution of two width-(r+1) boxes: `2·((r+1)²−1)/12`). r = 1 → σ = 0.707 (the `[1 2 1]/4` kernel), r = 2 → 1.155, r = 5 → 2.415, r = 10 → 4.472 (COMPUTED, `fam1.py`). To match a Gaussian σ: `r ≈ sqrt(6σ² + 1) − 1 ≈ 2.45σ − 1`.

**Discrete kernel.** Integer weights `1, 2, …, r+1, …, 2, 1`, sum `(r+1)²`; exact normalization with integer arithmetic. Edge handling: any §0 mode.

**Frequency response.** Continuous `H(ν) = sinc²(aν)`: **non-negative everywhere** (zeros at `ν = k/a`, never negative). Discrete radius-r: the squared Dirichlet kernel `[sin(π(r+1)ν)/((r+1)·sin πν)]²`, also ≥ 0; at Nyquist it is 0 when r+1 is even and `1/(r+1)²` when r+1 is odd (r = 2 → 0.111) (COMPUTED). So the tent has **zeros but no contrast inversion**: a Siemens star shows grey null rings but no reversed spokes between them. The sidelobes are small: largest secondary maximum `0.2172² ≈ 0.047`.

**Properties.** Linear, shift invariant, separable, positive in space and frequency, not isotropic (diamond-ish level sets near the edge of support; directional kurtosis of the 2-D PSF is 2.39 along the axes vs 2.70 along the diagonals for r = 10, Gaussian 3.0; COMPUTED `aniso2.py`), not a semigroup (tent∘tent = cubic B-spline). C⁰ continuous (has corners at 0 and ±a), so its MTF decays like `ν⁻²`.

**Algorithms and cost.**
- Direct separable: `2(2r+1)` MACs.
- Two box passes with running sums: O(1) per pixel per box (4 sliding passes total for 2-D).
- One pass with a doubly-running sum (the stack-blur bookkeeping, §8): O(1).
- Repeated integration: integrate twice, then a 3-tap second difference `[1, −2, 1]` at stride (r+1): O(1) with only 3 taps per axis (Heckbert 1986, "Filtering by repeated integration", SIGGRAPH '86; REFERENCE).
- GPU: a tent with even width can be fetched with bilinear taps placed at half-texel points (§4); for r = 1, the `[1 2 1]/4` kernel is a **single bilinear fetch at a texel corner, applied twice** (one fetch at +½, one at −½ texel and averaged) or, in 2-D, the 4-fetch "corner" pattern that Kawase pass 0 uses (§12).

**GPU implementation.** Separable 2-pass with bilinear merging gives about `r+1` fetches per pass. A bilinear upsample from a half-resolution texture **is** a tent of half-width 2 full-res pixels (bilinear interpolation kernel scaled by 2), which is why mip-chain blurs (§14) produce tent-shaped, slightly faceted PSFs.

**Visual fingerprint.** Point light → a **soft square pyramid** (bright centre, linear falloff, square outline, no flat top): visibly less blocky than the box but still not round. Edge-spread: a smooth quadratic S-curve (integral of a triangle) with no overshoot. Siemens star: grey null rings (square-ish) but no reversed rings, the cleanest way to show the difference from box at equal σ. Best test: point lights and Siemens star next to box.

**Where used.** Bilinear texture filtering and bilinear upsampling (the tent is the bilinear kernel); "triangle filter" option in image resamplers (e.g. ImageMagick `-filter Triangle`, REFERENCE: ImageMagick "Resampling Filters" documentation); stack blur is a tent (§8); tent upsample in CoD bloom (§14) and dual-Kawase upsample (§13, approximately).

**Signature.** "Two boxes stacked: a soft pyramid that has blind spots but never flips a stripe."

## 6. binomial-blur

**id** `binomial-blur`. **Aliases:** binomial filter, Pascal kernel, `[1 2 1]`, `[1 4 6 4 1]`, Burt–Adelson 5-tap (a = 0.375), discrete B-spline, "Gaussian 3×3" in many tools. **Family:** LSI, separable, positive, FIR, discrete semigroup; the discrete analogue of the Gaussian built from `[1 1]/2` steps.

**Continuous definition.** None needed; it is natively discrete: `B_n[k] = C(n, k)/2ⁿ`, k = 0…n, centred at n/2. `B_n = ([1 1]/2)^{*n}` (n-fold convolution of the 2-tap average). Even n gives an odd-length, pixel-centred kernel. In the limit `B_n → G_σ` with `σ = √n/2` (de Moivre–Laplace).

**Parameters.** Order n (kernel length n+1). Variance `σ² = n/4` (COMPUTED: n = 2 → 0.707 px, n = 4 → 1.0, n = 8 → 1.414, n = 16 → 2.0). So binomials are only practical for small σ; σ = 5 needs n = 100.

**Discrete kernel.** Pascal row n divided by `2ⁿ`: exact with integer shifts (`[1 2 1] >> 2`, `[1 4 6 4 1] >> 4`), which is why it is popular in fixed-point hardware and ISPs. No truncation needed. Rows of the Pascal triangle with a few outer taps dropped are a common "Gaussian" (Rákos's 9-tap kernel in §4 is row 12 minus 2 taps per side).

**Frequency response.** Exactly `H(ν) = cos^n(πν)` (COMPUTED, error < 10⁻¹⁵). On `[0, 0.5]` it is **monotonic, non-negative, and exactly 0 at Nyquist** for every n ≥ 1. Near DC, `cos^n(πν) ≈ exp(−nπ²ν²/2) = exp(−2π²σ²ν²)` with σ² = n/4, i.e. Gaussian. Binomials are therefore **better than the sampled Gaussian at killing a checkerboard**: a sampled σ = 1 Gaussian leaves `exp(−π²/2) = 0.72%` at Nyquist, `B_4` (also σ = 1) leaves 0.

**Properties.** Linear, shift invariant, separable, positive (space and frequency), semigroup in n: `B_m * B_n = B_{m+n}`. Anisotropic in 2-D but only mildly (directional kurtosis 2.875 axis vs 2.94 diagonal for n = 16, COMPUTED). Shape error vs equal-σ Gaussian: max |difference| / peak = 13.2% (n = 2), 6.9% (n = 4), 3.2% (n = 8), 1.6% (n = 16), 0.78% (n = 32), i.e. about `0.25/n`; excess kurtosis exactly `−2/n` (COMPUTED). Platykurtic (flatter top, shorter tails than a Gaussian).

**Algorithms and cost.** Direct separable `2(n+1)` taps; or n repeated passes of `[1 1]/2` (n fetches but n passes); or log₂-style composition (`B_4 = B_2 * B_2`). With bilinear tap merging (§4) `B_{2m}` needs about m+1 fetches per pass. A single bilinear fetch at a texel corner of a 2×2 block applies `B_1⊗B_1` (the 2×2 box) for free; two such fetches offset by one texel give `B_2`.

**GPU implementation.** Fragment separable with merged taps; or as the generating kernel of image pyramids (Burt & Adelson 1983, "The Laplacian Pyramid as a Compact Image Code", IEEE Trans. Communications 31(4), use the 5-tap `[¼−a/2, ¼, a, ¼, ¼−a/2]`; a = 0.375 gives `[1 4 6 4 1]/16 = B_4`; REFERENCE).

**Visual fingerprint.** Indistinguishable from a Gaussian by eye except for (1) exact removal of checkerboard/Nyquist content (a 1-px checkerboard becomes flat grey with zero residue, while a Gaussian of equal σ leaves faint residue) and (2) its small fixed sizes. Best test: 1-px checkerboard and a zone plate's outer rim.

**Where used.** ISP and camera pipelines; image pyramids (Burt–Adelson); OpenCV `pyrDown`/`pyrUp` use the 5×5 `[1 4 6 4 1]` kernel (REFERENCE: OpenCV `pyrDown` documentation); the "3×3 Gaussian" `[1 2 1]⊗[1 2 1]/16` in countless shaders; Kawase pass 0 (§12) is `B_2⊗B_2`.

**Signature.** "Pascal's triangle as a blur: the Gaussian in integers, and the only one here that erases a checkerboard exactly."

## 7. iterated-box

**id** `iterated-box`. **Aliases:** cascaded box filters, repeated moving average, n-box Gaussian approximation, "three-box blur", B-spline smoothing, extended box (Gwosdek et al. 2011). **Family:** LSI, separable, positive in space, O(1)-per-pixel approximation of the Gaussian.

**Continuous definition.** `h = b_{W1} * b_{W2} * … * b_{Wn}` (n boxes). With equal widths this is the **cardinal B-spline of order n** (degree n−1): n = 1 box, 2 tent, 3 quadratic B-spline, 4 cubic B-spline. By the central limit theorem it tends to a Gaussian as n grows. Wells 1986 ("Efficient synthesis of Gaussian filters by cascaded uniform filters", IEEE PAMI 8(2):234–239, doi:10.1109/TPAMI.1986.4767776) proposed it for Gaussian synthesis with the radius rule `σ² = K((2r+1)² − 1)/12`; REFERENCE (via Getreuer 2013 §3.3; Wells' full text not read here).

**Parameters.** n (passes) and widths `w_i`. Variance adds: discrete odd widths `σ² = Σ (w_i² − 1)/12`; equal widths `σ² = n(w² − 1)/12` (COMPUTED, `ibox.py`: n = 3, w = 9 → σ = 4.472). The integer-width constraint makes σ jump in steps; two remedies:
- **Kovesi / Kutskir width split.** Choose `w_ideal = sqrt(12σ²/n + 1)`; `w_l` = largest odd integer ≤ `w_ideal`; `w_u = w_l + 2`; use `m = round((12σ² − n·w_l² − 4n·w_l − 3n)/(−4w_l − 4))` passes of `w_l` and `n − m` of `w_u`. This is the `boxesForGauss(sigma, n)` function in Kutskir's "Fastest Gaussian Blur (in linear time)" (blog.ivank.net; the page credits Peter Kovesi's MATLAB functions, which correspond to Kovesi, "Fast almost-Gaussian filtering", DICTA 2010; REFERENCE). Achieved σ (COMPUTED): σ = 5, n = 3 → widths 9, 9, 11, σ = 4.83 (−3.4%); n = 4 → 7, 9, 9, 9, σ = 4.90 (−2.0%); n = 5 → 7, 7, 7, 9, 9, σ = 5.03 (+0.7%); σ = 10, n = 3 → 19, 19, 21, σ = 9.83 (−1.7%); σ = 2, n = 3 → 3, 3, 5, σ = 1.83 (−8.7%). Small σ is poorly served (σ = 1, n = 3 gives 0.82).
- **Extended box.** Give the two end taps a fractional weight so that each box has a continuously adjustable variance (Gwosdek, Grewenig, Bruhn & Weickert, "Theoretical foundations of Gaussian convolution by extended box filtering", SSVM 2011, pp. 447–458; REFERENCE). Getreuer's eq. 34 gives the parameters: `r = floor(½·sqrt(12σ²/K + 1) − ½)`, `α = (2r+1)·(r(r+1) − 3σ²/K) / (6(σ²/K − (r+1)²))`, end-tap weight `c1 = α/(2α+2r+1)`, inner weight `c2 = (1−α)/(2α+2r+1)`. Still O(1) with a running sum plus two end corrections.

**The SVG / CSS three-box rule (REFERENCE, Filter Effects Module Level 1, `feGaussianBlur`).** For stdDeviation s ≥ 2.0 user agents may use three successive box blurs of width `d = floor(s·3·sqrt(2π)/4 + 0.5)`; if d is odd, three centred boxes of size d; if d is even, two boxes of size d (offset half a pixel left, then right) and one of size d+1. Derivation (COMPUTED here): the peak of three continuous boxes of width d is `3/(4d)`; equating it to the Gaussian peak `1/(sqrt(2π)·s)` gives exactly `d = 3·sqrt(2π)·s/4 ≈ 1.880·s`. So the rule **matches the peak height, not the variance**, and the effective σ is `≈ d/2 ≈ 0.94·s`, about **6% narrower** than requested for large s: s = 5 → d = 9, σ_eff = 4.47 (−10.6%); s = 10 → d = 19, 9.49 (−5.1%); s = 20 → d = 38, 19.16 (−4.2%); s = 50 → 47.16 (−5.7%); s = 2 → d = 4, 2.12 (+6.1%). The spec text says the three boxes build "a piece-wise quadratic convolution kernel, which approximates the Gaussian kernel to within roughly 3%" (W3C Filter Effects Module Level 1, Working Draft 18 Dec 2018, `feGaussianBlur`; REFERENCE, quoted from the downloaded spec). Measured against a Gaussian of the nominal s, the max PSF error relative to the peak is 12.8% (s = 2), 4.8% (s = 5), 2.6% (s = 10), 2.4% (s = 20), 2.8% (s = 50), with max MTF error 2.2–8.7% (COMPUTED): "roughly 3%" holds for s ≳ 10. The app should label any browser-matching "CSS blur" with this effective σ as COMPUTED, and note that browsers may instead use true Gaussians on the GPU (`stack-semantics.md` §1.2).

**Discrete kernel.** Convolve the boxes (length `Σw_i − n + 1`). Edge handling must be applied per pass (each pass pads its own input), which is not identical to padding once for the composite kernel; mirror padding per pass is the usual choice.

**Frequency response.** `H(ν) = Π sinc(w_i ν)` (discrete: product of Dirichlet kernels). **Parity matters:** an even number of equal boxes gives `sinc^{2m} ≥ 0` (no inversion); an odd number keeps negative lobes: continuous minima `sinc` −0.217, `sinc³` −0.0103, `sinc⁵` −0.00048 (COMPUTED). So **the standard three-box Gaussian still inverts contrast at about 1%** (discrete: −0.0116 for 3×w9, −0.0086 for widths 9, 9, 11; COMPUTED). Usually invisible, but measurable on a high-contrast Siemens star or zone plate in the app's MTF plot.
Error vs the target Gaussian (COMPUTED, max |PSF error| / peak and max |MTF error|): n equal boxes w = 9: n = 1: 0.36 / 0.27; n = 2: 0.085 / 0.069; n = 3: 0.067 / 0.042; n = 4: 0.037 / 0.031; n = 6: 0.026 / 0.020. Getreuer's Table 3 (N = 1000, σ = 5, double precision; A Survey of Gaussian Convolution Algorithms, IPOL 3:286–310, 2013; REFERENCE, read from the PDF) gives the ℓ∞ operator error of plain box filtering with Wells' radius as 0.129 (K = 3), 0.0655 (K = 4), 0.0896 (K = 5): not monotonic in K, because the integer radius quantizes σ (with K = 3 the reachable variances are r(r+1) = 2, 6, 12, 20, 30, …; the survey prints these as σ values, which looks like a typo for σ²). Extended box: 0.0516 / 0.0379 / 0.0279 (K = 3/4/5); SII: 0.202 / 0.187 / 0.180. Timings 12–19 ms (box) vs 54 ms (FIR at tol 10⁻²) for N = 1000 on a Core 2 Duo T7700. Kutskir reports 0.04% average per-pixel error for his three-box method on a test photo (REFERENCE; blog measurement on one image).

**Properties.** Linear, shift invariant, separable, positive in space; anisotropic in 2-D (it is separable and non-Gaussian); support exactly finite (`Σw_i − n + 1`), so no truncation step at the boundary; piecewise polynomial PSF of degree n−1 (n = 3: piecewise quadratic, C¹).

**Algorithms and cost.** Each pass is a sliding-window box: O(1) per pixel per pass (2 adds + 1 multiply); n passes × 2 axes. Kutskir's timings on an 800×200 RGBA image (hardware unstated): naive 2-D 7,077 ms at r = 5 vs 32 ms for the running-sum three-box, essentially flat in r (34 ms at r = 10) (REFERENCE). Alternatives: one SAT per box pass (§9); **stacked integral images (SII)**, a sum of K boxes of different widths taken from one integral image, fitted to a Gaussian (Bhatia, Snyder & Bilbro, "Stacked integral image", ICRA 2010, pp. 1530–1535; Elboher & Werman, "Efficient and accurate Gaussian image filtering using running sums", arXiv:1107.4958, 2011; REFERENCE via Getreuer 2013).

**GPU implementation.** Either (a) n × 2 compute passes of a running-sum box (one thread per row/column or a tiled prefix sum, `gpu-pipeline.md` §3.3), or (b) n × 2 fragment passes of a merged-tap box (`ceil(w/2)` bilinear fetches each). For large σ on a GPU the running sum wins: about 2 reads per pixel per pass regardless of σ. fp32 running sums drift; restart or re-anchor the sum every few hundred pixels.

**Visual fingerprint.** With n = 1 it is the box; with n = 2 a tent; with n ≥ 3 nearly a Gaussian. What gives it away: (1) a **slightly square** point-light PSF on HDR lights (the corners of the support are a square, and the PSF falls to exactly zero at a finite square), (2) faint (~1%) contrast-inverted rings on a Siemens star for odd n, (3) quantized σ steps when the slider moves (without the Kovesi split or extended box, σ jumps in visible increments). Best test: night-city lights with a strong exposure boost (shows the square support), and a σ slider sweep.

**Where used.** SVG/CSS `feGaussianBlur` in browsers for s ≥ 2 (permitted by spec; Skia/Chromium used it on CPU, see `stack-semantics.md` §1.2 and §2.1); Kutskir's three-box method in many JavaScript libraries; SwiftUI `.blur(radius:)` rendered through `ImageRenderer` behaves like a separable box³ for r ≥ 8 pt (excess kurtosis −0.45, σ ≈ 0.90·r, slightly shift-variant), and like a Gaussian with σ ≈ r for r ≤ 4 (MEASURED on macOS 27.2 in `live-calibration.md`; internals INFERRED); Photoshop's Gaussian blur is widely believed to use box iterations (UNVERIFIED, no Adobe source); Intel's moving-box compute-shader blur (Intel, "An Investigation of Fast Real-Time GPU-based Image Blur Algorithms", 2014, which notes a 3-pass version looks noticeably better than 2-pass; REFERENCE).

**Signature.** "Three flat boxes in a row become almost a Gaussian, with a square shadow and a one-percent lie left over."

## 8. stack-blur

**id** `stack-blur`. **Aliases:** StackBlur, Klingemann stack blur, `stack_blur_rgba32` (AGG). **Family:** LSI, separable, positive; an O(1)-per-pixel **tent** filter. Mario Klingemann, "StackBlur (2004-)", quasimondo.com, 25 Feb 2004, first written in Java for Processing (REFERENCE).

**Continuous definition.** Identical to the tent (§5): the 1-D weights are `r+1−|k|` for `|k| ≤ r`, divisor `(r+1)²`. Confirmed in the AGG reference implementation (`agg_blur.h`, Maxim Shemanarev, which credits Klingemann): leading weights `i + 1`, trailing weights `radius + 1 − i`, `div_sum = (radius + 1) * (radius + 1)` (REFERENCE). Klingemann's own page describes a "stack" with the centre pixel weighted highest but does not state the formula; the triangle comes from the code. Wikipedia's "Box blur" article also describes stack blur's impulse response as triangular.

**Parameters.** Radius r (integer, ≥ 1; AGG's 8-bit path caps it at 254). σ per axis `= sqrt(r(r+2)/6)` ≈ 0.408·(r+1): r = 5 → 2.42, r = 10 → 4.47, r = 20 → 8.56 (COMPUTED). So "stack blur radius 10" has σ ≈ 4.5, while "Gaussian radius 10" means σ = 10 in CSS terms. To match σ: `r ≈ 2.45σ − 1`.

**Discrete kernel / algorithm.** The "stack" is the window of `2r+1` pixels. The filter keeps three running sums per channel: `sum` (the weighted sum, i.e. current output × (r+1)²), `sum_in` (pixels in the right half, entering), `sum_out` (pixels in the left half, leaving). Moving one pixel right: `sum −= sum_out; sum_out −= stack[oldest]; …; sum_in += new pixel; sum += sum_in; …` so each pixel costs a handful of adds regardless of r. The division by `(r+1)²` is replaced by a multiply and a right shift from two lookup tables (`mul_table`, `shg_table` in the JS port; `g_stack_blur8_mul`, `g_stack_blur8_shr` in AGG; REFERENCE), which introduces a rounding error of at most about 1 LSB in 8-bit. Edge handling in the reference code is **clamp to edge** (the stack is pre-filled with copies of the first pixel).

**Frequency response.** As tent: `[sin(π(r+1)ν)/((r+1)sin πν)]²` ≥ 0 (no contrast inversion; null rings exist).

**Properties.** Linear (up to integer rounding), shift invariant, separable, positive, anisotropic (square pyramid PSF). It is **not** a Gaussian approximation in the CLT sense (only two boxes' worth); it is a tent computed cleverly.

**Algorithms and cost.** O(1) per pixel per pass, one horizontal + one vertical pass, integer adds only plus one multiply-shift per output; memory: a ring buffer of `2r+1` pixels per row. Inherently sequential along each row (like any running sum), so on GPUs it maps to one thread per row/column; the same kernel is usually done on GPUs as a tent via bilinear taps instead.

**GPU implementation.** Rarely done literally. GPU equivalent: separable tent with `≈ r+1` merged bilinear fetches per pass, or two running-sum box passes of width r+1 per axis.

**Visual fingerprint.** Same as tent: soft square-pyramid point lights, smooth edges with no overshoot, square null rings on a Siemens star with **no** reversed spokes. Practical tell: the integer pipeline produces slightly different rounding (±1 LSB banding in very smooth gradients) and clamp-to-edge streaks at borders.

**Where used.** Processing, StackBlur.js and its many ports (canvas libraries, Android blur libraries, ActionScript, CUDA, Go); AGG `stack_blur_rgba32`; the Wikipedia "Box blur" page lists it under variants. INFERRED/UNVERIFIED: many mobile "fast blur" helpers copied from StackBlur Java ports; not verified per product.

**Signature.** "A tent filter with a running-sum trick: two boxes' smoothness at one box's cost."

## 9. sat-box

**id** `sat-box`. **Aliases:** summed-area table (SAT), integral image, box filter by integral image, "prefix-sum blur". **Family:** LSI box filter (exactly §1) computed by a different algorithm; the same table also gives **spatially varying** boxes (then not LSI; see `catalog-spatial.md`). Crow, "Summed-area tables for texture mapping", SIGGRAPH '84, Computer Graphics 18(3):207–212, 1984 (REFERENCE). Popularized in vision as the "integral image" by Viola & Jones, "Rapid object detection using a boosted cascade of simple features", CVPR 2001 (REFERENCE).

**Definition.** `S(x, y) = Σ_{i ≤ x} Σ_{j ≤ y} f(i, j)`. The sum over any axis-aligned rectangle `(x0, x1] × (y0, y1]` is `S(x1,y1) − S(x0,y1) − S(x1,y0) + S(x0,y0)`: **4 fetches, any size**. Box blur output = that sum / area.

**Parameters.** Box half-widths `rx, ry` (independent, can be non-square and can vary per pixel). Same σ relation as §1: `σ² = (w² − 1)/12` per axis.

**Discrete construction.** Build `S` with a row prefix sum then a column prefix sum (or one 2-D scan). Pad by one zero row/column so `S(−1, ·) = 0`. Edge handling: clamp the rectangle to the image and divide by the clamped area (renormalize), or build `S` from a pre-padded (mirror) image.

**Frequency response.** Identical to the box: `sinc(wν_x)·sinc(wν_y)`, with the same −22% inverted lobes. Higher-order SATs (repeated integration, Heckbert 1986) give tent and B-spline kernels with `2^d`-ish fetches per dimension.

**Properties.** Exactly the box filter (in exact arithmetic). Its distinctive property is **cost independent of size and of position**, so a different box per pixel costs the same as a fixed box: this is what makes SAT the basis of cheap variable blurs (depth-of-field, "glossy" lookups, Crow's original texture filtering).

**Precision (the real engineering issue; COMPUTED, `sat.py`).**
- Integer SAT of 8-bit data: maximum value `255·W·H`. 1080p: 5.3·10⁸ (fits int32); 4K UHD: 2.12·10⁹ (fits int32, barely); 12 MP iPhone photo: 3.11·10⁹ (needs uint32); 48 MP: 1.24·10¹⁰ (exceeds uint32). **But unsigned wrap-around is harmless:** the four-corner difference is exact modulo 2³², so box sums are exact as long as the box's own sum fits in 32 bits (checked numerically). So uint32 SATs work for any image size with 8-bit data and boxes up to 16.8 M pixels.
- fp32 SAT: the table's largest value on a 1080p image of mean 0.5 is about 1.04·10⁶, where the fp32 spacing is 0.0625. A 3×3 box mean at the bottom-right then has an error of 0.8 LSB on average and up to 3.6 LSB (8-bit); 11×11: 0.11 / 0.6 LSB; 31×31: 0.02 / 0.15 LSB. **Small boxes far from the origin are the worst case**, the opposite of the usual intuition. Subtracting the image mean (or 0.5) before building the table, as Hensley et al. recommend, drops the error to below 0.002 LSB on this test (Hensley, Scheuermann, Coombe, Singh & Lastra, "Fast summed-area table generation and its applications", Computer Graphics Forum 24(3), Eurographics 2005; REFERENCE for the offset idea).

**Algorithms and cost.** Build: O(1) per pixel (2 adds); serial scans are trivial on CPU. Query: 4 fetches + 3 adds + 1 multiply per pixel per channel, **for any w** (versus `2·ceil(w/2)` bilinear fetches for a separable box). Memory: one 32-bit (or 2×32) value per channel per pixel, i.e. 4× the bytes of an RGBA8 image (16 bytes per pixel for 4 channels).

**GPU implementation.** Build with parallel prefix scans: Hensley et al. 2005 use recursive doubling (`log₂ W + log₂ H` render passes, O(n log n) work); compute-shader work-efficient scans (Blelloch 1990; Harris, Sengupta & Owens, "Parallel Prefix Sum (Scan) with CUDA", GPU Gems 3 ch. 39, 2007) do it in O(n) work with a few dispatches; SIMD-group prefix intrinsics (`simd_prefix_inclusive_sum` in MSL) make the in-threadgroup part cheap. The query is one fragment/compute pass with 4 `read()`s (no filtering; SATs must be read point-sampled). See `gpu-pipeline.md` §3.4. Total traffic is higher than a separable blur for small boxes (build = 2 full read/write passes of 16 B/px), so SAT wins only for large or varying boxes.

**Visual fingerprint.** For a fixed box: identical to `box-blur` (square PSF, inverted rings), plus **position-dependent quantization noise** in fp32 (worse toward the bottom-right of the image, worse for small boxes) if no offset is used. Best tests: a Siemens star (box rings) and a flat mid-grey field with a small box (exposes fp32 noise growing across the frame). For a varying box: abrupt, square-shaped blur changes.

**Where used.** Crow's texture filtering; Viola–Jones face detection; SURF features (Bay, Tuytelaars & Van Gool, ECCV 2006); OpenCV `integral()`; real-time depth of field and glossy reflections with variable box sizes (Hensley et al. 2005).

**Signature.** "Precompute once, then any box anywhere costs four reads: the box blur that doesn't care how big it is."

## 10. iir-gaussian

**id** `iir-gaussian`. **Aliases:** recursive Gaussian, Deriche filter, Young–van Vliet (YvV), Vliet–Young–Verbeek (VYV), Alvarez–Mazorra, infinite impulse response (IIR) Gaussian. **Family:** LSI (on an infinite domain), separable, approximately Gaussian, **O(1) per pixel independent of σ**; causal + anticausal recursions.

**Continuous / operator definition.** A rational transfer function `H(z) = N(z)/D(z)` whose impulse response approximates `G_σ`. Two families:
- *Parallel (Deriche 1993):* approximate the right half of the Gaussian by a sum of K damped (complex) exponentials, `G_σ(n) ≈ (2πσ²)^(−½)·Σ α_k e^(−λ_k n/σ)` for n ≥ 0, run it causally, run its mirror anticausally, and **add** (subtracting the doubled n = 0 sample). Coefficients (Getreuer 2013 eq. 37, from Deriche, "Recursively implementing the Gaussian and its derivatives", INRIA RR-1893, 1993): K = 2: α₁ = 0.48145 + 0.971i, λ₁ = 1.26 + 0.8448i; K = 3: α₁ = −0.44645 + 0.5105i, λ₁ = 1.512 + 1.475i, α₃ = 1.898, λ₃ = 1.556; K = 4: α₁ = 0.84 + 1.8675i, λ₁ = 1.783 + 0.6318i, α₃ = −0.34015 − 0.1299i, λ₃ = 1.723 + 1.997i (with conjugate pairs). REFERENCE.
- *Cascade (Young & van Vliet 1995):* an all-pole third-order filter applied forward then backward (a cascade, so the transfer functions multiply): `H(z) = B/(1 − (b₁z⁻¹ + b₂z⁻² + b₃z⁻³)/b₀) · B/(1 − (b₁z + b₂z² + b₃z³)/b₀)`, with `q = 0.98711σ − 0.96330` (σ ≥ 2.5) or `q = 3.97156 − 4.14554·sqrt(1 − 0.26891σ)` (0.5 ≤ σ < 2.5), `b₀ = 1.57825 + 2.44413q + 1.4281q² + 0.422205q³`, `b₁ = 2.44413q + 2.85619q² + 1.26661q³`, `b₂ = −(1.4281q² + 1.26661q³)`, `b₃ = 0.422205q³`, `B = 1 − (b₁ + b₂ + b₃)/b₀`; recursion `w[n] = B·x[n] + (b₁w[n−1] + b₂w[n−2] + b₃w[n−3])/b₀`, then the same backwards on w. (Young & van Vliet, "Recursive implementation of the Gaussian filter", Signal Processing 44(2):139–151, 1995; coefficients as reproduced in AGG `recursive_blur`, which uses `s = radius·0.5`, i.e. AGG "radius" = 2σ; REFERENCE.) Improved poles: van Vliet, Young & Verbeek, "Recursive Gaussian derivative filters", ICPR 1998 (VYV).
- *Alvarez–Mazorra (1994):* K passes of a first-order causal/anticausal pair `u'n = f_n + ν u'_{n−1}` from a finite-difference heat-equation step; simplest of all.

**Parameters.** σ and order K (number of poles). σ enters only through the coefficients, so changing σ costs nothing.

**Discrete construction.** Coefficients from σ (above). **Boundary initialization** is the hard part: the recursion needs past outputs before the first pixel. Options: zero (darkens edges), constant-extension steady state, or exact initial conditions for mirror boundaries (Triggs & Sdika, "Boundary conditions for Young–van Vliet recursive filtering", IEEE TSP 54(6):2365–2367, 2006; REFERENCE). Getreuer's survey initializes each recursion to a tolerance by summing the decaying response into the mirrored signal.

**Frequency response.** Rational: `|H(e^{2πiν})|` is a ratio of trigonometric polynomials, not a Gaussian. Positive, no zeros for YvV (all-pole); Deriche's sum of exponentials has tiny negative values in the impulse response (K = 4: min ≈ −1.4·10⁻⁴ of the peak; K = 2: −0.9%; COMPUTED). The tails of any IIR response decay **exponentially**, not like `e^{−x²}`: too heavy far out.

**Accuracy (COMPUTED with `iir.py`, ℓ∞ operator norm = ℓ1 norm of the impulse-response error, matching Getreuer's Table 3 to 3 digits at σ = 5).**

| method | σ = 1 | σ = 2 | σ = 5 | σ = 10 | σ = 20 | Getreuer σ = 5 |
|---|---|---|---|---|---|---|
| Deriche K = 2 | 4.8·10⁻² | 3.8·10⁻² | 3.5·10⁻² | 3.4·10⁻² | 3.3·10⁻² | 3.48·10⁻² |
| Deriche K = 3 | 6.1·10⁻³ | 5.0·10⁻³ | 4.5·10⁻³ | 4.3·10⁻³ | 4.2·10⁻³ | 4.50·10⁻³ |
| Deriche K = 4 | 8.3·10⁻⁴ | 5.8·10⁻⁴ | 6.3·10⁻⁴ | 6.3·10⁻⁴ | 6.3·10⁻⁴ | 6.25·10⁻⁴ |
| Young–van Vliet 1995 (3 poles, cascade) | 0.149 | 8.1·10⁻² | 4.8·10⁻² | 3.3·10⁻² | 2.0·10⁻² | (VYV 1998 K = 3: 2.1·10⁻²) |
| Alvarez–Mazorra K = 3 (Getreuer's q) | | 0.103 | 7.8·10⁻² | 7.7·10⁻² | | 7.83·10⁻² |

Other numbers (COMPUTED): Deriche K = 2 loses about 1.1% of DC (sum ≈ 0.989) and is ~11% narrow; K = 3 is 1.6% wide; K = 4 is 0.22% narrow with DC within 2·10⁻⁴. YvV 1995 has the right DC exactly (B normalizes it) and the right peak height within 0.4% at σ = 5, but its **second-moment σ is 9–13% too large** (5.56 at σ = 5, 10.99 at σ = 10) because of the exponential tails; the best ℓ1-fit Gaussian has σ only 2–2.4% larger. Getreuer's verdict (2013 §5.1, REFERENCE): Deriche and VYV have the best speed/accuracy trade-off; recommend FIR for σ < ~2 and Deriche/VYV above; IIR error is much higher for σ < 2.

**Properties.** Linear; shift invariant except near boundaries (initialization); separable (apply along x then y); approximately isotropic (inherits Gaussian isotropy only to the accuracy above; the separable product of exponential tails has diamond-shaped far-field contours). Not exactly positive (Deriche). Numerically sensitive: poles close to the unit circle for large σ (e.g. YvV q = 19 at σ = 20) make fp32 recursion lose precision, and `half` is unusable.

**Algorithms and cost.** Per pixel per axis: Deriche K: `4K` multiplies + `4K − 1` adds (Getreuer); YvV: 3 feedback + 1 feed-forward multiply per direction, 2 directions → ~8 MACs; Alvarez–Mazorra: 2K MACs. **Independent of σ.** Getreuer's timing at σ = 5, N = 1000: Deriche K = 3/4: 18/20 ms vs FIR (tol 10⁻²) 54 ms and box K = 3 12 ms (REFERENCE).

**GPU implementation.** Recursions are sequential along a row, so the natural GPU mapping is **one thread per row (horizontal) then one thread per column (vertical)**, each running the causal and anticausal recursions in registers: perfectly coalesced if threads in a SIMD-group own adjacent rows when traversing columns. Only `H` or `W` threads are active (1,080–3,840), which under-fills a GPU on small images; block-parallel IIR (split rows into chunks, solve chunk boundary conditions with a second pass; Nehab, Maximo, Lima & Hoppe, "GPU-efficient recursive filtering and summed-area tables", ACM TOG 30(6), SIGGRAPH Asia 2011; REFERENCE) fixes that. Must use fp32. Not used by mainstream real-time engines (INFERRED from the absence in public engine docs).

**Visual fingerprint.** Nearly Gaussian in the core; the tells are (1) **one-sided bias near borders** with poor initialization (a dark or bright smear entering from the first pixel of each row, worse on the side where the recursion starts), (2) **exponential tails**: on an exposure-boosted point light, a faint halo that extends further than a Gaussian's and has a slightly diamond-shaped outline, (3) for Deriche K = 2, a faint dark ring (negative lobe −0.9%), (4) loss of accuracy for σ < 1 (YvV σ = 1 is 24% too wide in moment terms). Best tests: HDR point light (tails), a bright vertical bar touching the left edge (boundary transient).

**Where used.** ITK `RecursiveGaussianImageFilter` ("base class for computing IIR convolution with an approximation of a Gaussian kernel", implementing Deriche's method with Farnebäck & Westin 2006 improvements; REFERENCE: ITK Doxygen); AGG `recursive_blur` (YvV coefficients); GIMP's Gaussian Blur (GEGL `gegl:gaussian-blur`) has a Filter choice of Auto / FIR / IIR, and the manual says both produce the same result at different speeds (REFERENCE: GIMP manual "Gaussian Blur", docs.gimp.org; GEGL commit "change gaussian-blur's filter property into an enum", May 2013); scientific image libraries (scikit-image uses FIR; OpenCV uses FIR; not IIR). Apple Accelerate: vImage does not document an IIR Gaussian (UNVERIFIED).

**Signature.** "A Gaussian from a feedback loop: any σ for the same eight multiplies, paid for with exponential tails and edge transients."

## 11. fft-convolution

**id** `fft-convolution`. **Aliases:** frequency-domain convolution, fast convolution, DFT/DCT filtering, "Convolution bloom" (Unreal). **Family:** an algorithm for **any** LSI kernel (separable or not, positive or not, any shape), and the natural home of kernels that are defined in frequency (§17).

**Definition.** Convolution theorem: `h * f = F⁻¹{ F{h} · F{f} }`. On a discrete N×M grid the DFT computes **circular** convolution (the image is treated as periodic), so the plain FFT result equals `wrap` edge handling. Linear (non-wrapping) convolution needs zero/mirror padding by at least the kernel radius on each side. With a half-sample-symmetric extension the DCT-II/DCT-I pair implements mirror-boundary convolution without padding (Martucci 1994, via Getreuer 2013 §3.2.2; REFERENCE).

**Parameters.** The kernel (any image or any analytic `H(ν)`), padding mode, padded size (FFTs are fastest at sizes with small prime factors).

**Discrete construction.** Two choices: (a) take the spatial kernel, zero-pad it to the image size, centre it at index 0 (wrap its left half to the end), FFT it once; (b) **sample the frequency response directly**, e.g. `exp(−2π²σ²(k/N)²)` for a Gaussian, which gives the band-limited discretization `g_sinc` (Getreuer Algorithm 5/6; its spatial kernel is the Gaussian convolved with a sinc and aliased onto the grid). For σ ≥ ~1, (a) and (b) differ by ≤ 10⁻⁸; for σ < 1 they differ visibly (§2).

**Frequency response.** Exactly the sampled `H` (to fp precision): there is no approximation in the method itself. Getreuer's DCT Gaussian has ℓ∞ operator error 2.9·10⁻¹⁵ at σ = 5 (Table 3; REFERENCE).

**Properties.** Exact for any LSI kernel; cost independent of kernel size and shape; boundary is periodic unless padded; numerical noise floor about 10⁻⁷ relative in fp32 (round-off grows ~ε·log N); **ringing from the wrap** if not padded (bright content at the right edge bleeds into the left edge).

**Algorithms and cost (MODELED).** For a padded N_p-pixel real image: forward real FFT + pointwise complex multiply + inverse FFT ≈ `2·(2.5·log₂N_p) + 6` real flops per pixel per channel (the kernel's FFT is computed once). For a 2048×2048 padded frame (log₂N_p = 22): ≈ 116 flops per pixel per channel, independent of the kernel. Compare: separable Gaussian FIR with merged taps at σ = 10 ≈ 2·31 = 62 fetch+MACs; disc of radius 10 by direct 2-D sum ≈ 317 MACs; disc of radius 40 ≈ 5,000. So FFT pays off for **large non-separable kernels** (bokeh shapes, star/streak kernels, measured lens PSFs, ideal/Butterworth low-pass), not for Gaussians, where IIR/pyramids are cheaper. Memory traffic dominates on GPUs: each FFT stage reads and writes the complex buffer (8 bytes per channel per pixel in fp32) unless stages are fused in threadgroup memory.

**GPU implementation.** Row FFTs then column FFTs (each a sequence of radix-2/4/8 butterfly passes, or one threadgroup-resident FFT per row when a row fits in threadgroup memory: 2048 complex fp32 = 16 KB); pointwise multiply; inverse. On Apple platforms: `MPSGraph.fastFourierTransform(_:axes:descriptor:name:)` and real↔Hermitian variants (MPSGraph, iOS 17+/macOS 14+, per `MPSGraphFourierTransformOps.h` in the iOS 27 SDK; REFERENCE), and `vDSP_fft2d_zrip` on the CPU (Accelerate vDSP; REFERENCE). Blur2ool can use vDSP in `BlurCore` for the CPU reference and MPSGraph (or a hand-written Metal FFT) on the GPU.

**Visual fingerprint.** For a Gaussian: identical to the exact Gaussian except **wrap-around bleeding at the image borders** if unpadded (the clearest tell: a bright object at the right edge glows on the left edge). For arbitrary kernels: whatever the kernel is (a hexagon, a star, an Airy pattern), at a cost that does not change as the kernel grows. Best tests: a bright object touching one edge (wrap), and a large non-separable bokeh kernel on the night-city image.

**Where used.** Unreal Engine "Convolution" bloom: the scene is convolved with a user-supplied kernel image ("an energy conserving scatter … formulated as a convolution operation and accelerated by use of a Fast Fourier Transform"), recommended for cinematics or high-end hardware, with a `BufferScale` guard region against wrap-around (REFERENCE: Epic, "Bloom in Unreal Engine" documentation; `FConvolutionBloomSettings`); scientific imaging (deconvolution, PSF modelling); Getreuer's "best accuracy" recommendation for σ ≥ 2 (DCT).

**Signature.** "Multiply instead of slide: any kernel, any size, the same price, as long as you remember the image wraps around."

## 12. kawase-blur

**id** `kawase-blur`. **Aliases:** Kawase blur, Kawase bloom filter, "Kawase method" (Silicon Studio's term for reduction-buffer post effects), multi-pass 4-tap diagonal blur. **Family:** LSI (at full resolution), separable (each pass and the chain), positive in space, **not** positive in frequency; an iterated sparse kernel. Masaki Kawase, "Frame Buffer Postprocessing Effects in DOUBLE-S.T.E.A.L (Wreckless)", GDC 2003 (REFERENCE; slides not re-read here, the per-pass offset convention below is the one used by the Intel 2014 article and open implementations).

**Definition.** Pass i (distance i = 0, 1, 2, …) takes 4 bilinear samples at the diagonal offsets `(±(i+½), ±(i+½))` texels from the output pixel centre and averages them. Each sample sits exactly on a texel corner, so it returns the mean of a 2×2 block; one pass therefore averages **four 2×2 blocks = 16 texels with 4 fetches**. The output of each pass feeds the next. A chain is written as a distance sequence, e.g. `{0, 1, 2, 2, 3}`.

**Kernel of one pass (COMPUTED).** In 1-D, pass i is `k_i = ¼(δ_{−i−1} + δ_{−i} + δ_i + δ_{i+1})`, and the 2-D pass kernel is exactly `k_i(x)·k_i(y)` (the four diagonal 2×2 blocks are the outer product), so the whole chain is **separable** even though no pass is written as two 1-D passes. Pass 0 is `[1 2 1]/4 ⊗ [1 2 1]/4` (a binomial, §6). For i ≥ 1 the pass kernel has a **hole in the middle**: `k_1 = ¼[1 1 0 1 1]` on offsets −2…+2, `k_2 = ¼[1 1 0 0 0 1 1]` on −3…+3.

**Parameters.** The distance sequence. Variance per pass `(i² + (i+1)²)/2` per axis: 0.5, 2.5, 6.5, 12.5, 20.5, 30.5 for i = 0…5. Variances add: `σ² = Σ (i_j² + (i_j+1)²)/2`. `{0,1,2,2,3}`: σ = 5.34 px per axis, support ±13 (COMPUTED, `kaw.py`; confirmed by direct simulation of the bilinear passes, `pyr.py`). Intel's article says this sequence matches a "35×35 Gaussian" closely but not perfectly, and that `{2,3,3,3}` "do[es] not closely match any Gaussian" and suits light streaks (REFERENCE: Intel, "An Investigation of Fast Real-Time GPU-based Image Blur Algorithms", 2014; the sequences were chosen "based on empirical comparison"). A 17-pass sequence `{0,1,2,3,4,4,5,…,15}` reaches σ = 37.3 with 68 fetches.

**Frequency response (COMPUTED).** Each pass: `K_i(ν) = cos(π(2i+1)ν)·cos(πν)`. The chain: `Π_j cos(π(2i_j+1)ν)·cos^n(πν)`, per axis. The factors `cos(π(2i+1)ν)` go negative above `ν = 1/(2(2i+1))`, so the chain has **negative lobes**: minimum −0.047 (`{0,1,2,2,3}`, at ν ≈ 0.14), −0.043 (`{0,1,2,3}`), −0.078 (`{2,3,3,3}`), −0.0001 (17-pass). The chain also zeros Nyquist exactly (the pass-0 binomial factor, and every `cos(πν)`).

**Properties.** Linear, shift invariant (at full resolution), separable, positive in space, not a semigroup in i, anisotropic (directional kurtosis 2.43 axis vs 2.71 diagonal for `{0,1,2,2,3}`, Gaussian 3; COMPUTED `pyr2.py`). **Non-monotonic PSF:** the 1-D profile of `{0,1,2,2,3}` peaks at ±2 px (0.0674) above the centre value (0.0645) and has secondary bumps at ±9…±10, so the 2-D PSF has a shallow dip at its centre (COMPUTED). Shape error vs an equal-σ Gaussian: 14.7% of peak.

**Algorithms and cost.** 4 fetches per pixel per pass, n passes: `4n` fetches, and n full-image writes. Total σ grows roughly like `n^{3/2}` for an increasing sequence (pass i adds ~i² variance), so large σ is cheap in fetches but each pass costs a full-res read+write: **bandwidth-bound**, which is what dual filtering (§13) fixes. Intel measured Kawase at 1.5–3.0× less time than an optimized (linear-sampled) separable Gaussian, more so at large kernels and on low-power GPUs (REFERENCE, 2014 article). Kawase is often run at half or quarter resolution (Intel: half-res `{0,1,2,2,3}` + upsample compares with a full-res 35-px-radius Gaussian).

**GPU implementation.** One fragment pass per distance, ping-pong between two textures, 4 `sample()` calls at `uv ± (i+0.5)·texelSize` (diagonals), linear filter, clamp-to-edge. Each pass is "full-screen quad, 4 taps, 1 write". MSL sketch in `gpu-pipeline.md` §3.6.

**Visual fingerprint.** Looks Gaussian at a glance on photos. The tells: (1) on **point lights**, a slightly squarish, flat-topped/hollow-centred glow with faint concentric square "steps" (the bumpy PSF), especially with short or irregular sequences; (2) **~5% contrast inversion** in the MTF at mid frequencies (visible on a high-contrast Siemens star or zone plate as a faint reversed ring); (3) blur increases in jumps between sequences; (4) `{2,3,3,3}` without the small passes leaves a **grid/lattice pattern** (sparse taps alias fine detail: the pass kernel's holes never get filled). Best tests: night-city lights and zone plate; also a 1-px checkerboard (removed exactly, like a binomial).

**Where used.** Bloom/glare in Wreckless (2002, Bunkasha/Activision; GDC 2003 talk); Silicon Studio's YEBIS middleware traces its "Kawase method" lineage (REFERENCE: Silicon Studio YEBIS news page, 2012); Intel's 2014 article; KDE KWin's older blur effect (before dual filtering; INFERRED from KWin history, UNVERIFIED).

**Signature.** "Four diagonal taps, repeated at growing distances: a Gaussian-looking glow built from 2×2 blocks, with a hollow heart and a 5% lie in its spectrum."

## 13. dual-kawase

**id** `dual-kawase`. **Aliases:** dual filtering, dual blur, dual Kawase blur (KWin, Unity community), "Dual filter" (Bjørge). **Family:** pyramid blur (§14) with Kawase-style 4/8-tap bilinear kernels; **approximately** LSI (downsampling makes it slightly shift-variant). Marius Bjørge (ARM), "Bandwidth-Efficient Rendering", SIGGRAPH 2015 course "Moving Mobile Graphics" (REFERENCE; the original slides/notes PDF could not be retrieved here, so kernel details below are taken from public implementations: KWin `plugins/blur` and a 2015 UWA Technology write-up on Qiita, cross-checked against each other).

**Definition.** L downsample passes, each to half resolution, then L upsample passes back to full resolution. With `h` = half a source texel times an `offset` multiplier o:
- *Downsample* (5 fetches, output at half res; the output pixel centre lies on a source texel corner): `(4·S(c) + S(c + (−h,−h)) + S(c + (h,h)) + S(c + (h,−h)) + S(c + (−h,h)))/8`.
- *Upsample* (8 fetches, output at double res): `(S(c ± (2h, 0)) + S(c ± (0, 2h)) + 2·[S(c + (±h, ±h))])/12` (4 axis taps of weight 1 and 4 diagonal taps of weight 2).
KWin computes `halfpixel = 0.5/(source width, height)` and multiplies by a strength-dependent offset (1.5…8.0 in its 15-step table), with 1–4 levels ("Down sample size / 2 … / 16") (REFERENCE: `kwin/src/plugins/blur/blur.cpp`). The Unity/Qiita version uses ±1 source texel for the downsample diagonals and ±1 / ±½ texel for upsample axis/diagonal taps, which is o = 2 in KWin's terms.

**Parameters.** Levels L (main control: each level doubles σ) and offset o (fine control and artifact risk). Effective σ (COMPUTED by simulating the exact bilinear passes on impulses, `pyr.py`): o = 2: L = 2 → 5.85 px, L = 3 → 11.98, L = 4 → 24.1, i.e. **σ ≈ 1.5·2^L**; o = 3: L = 2 → 8.35, L = 3 → 17.1, L = 4 → 34.5; o = 1: L = 2 → 3.23, L = 3 → 6.61, L = 4 → 13.3.

**Discrete construction.** Sample positions as above on bilinear-filtered textures; clamp-to-edge. For o = 1 the downsample's diagonal taps land on texel centres and the pass degenerates to a plain 2×2 box downsample.

**Frequency response.** No single MTF (not exactly shift-invariant). The phase-averaged response is low-pass with **negative lobes**: the real MTF of the o = 2, L = 3 PSF has minimum −0.046 (COMPUTED, `pyr2.py`): Kawase-like ~5% contrast inversion.

**Properties.** Linear; positive kernel; second moments isotropic, fourth moments slightly anisotropic (kurtosis 2.55 axis vs 2.43 diagonal for o = 2, L = 3; Gaussian 3: **flatter-topped than a Gaussian**); approximately shift-invariant. **Shift variance depends on o** (COMPUTED: max PSF change over all sub-2^L impulse positions, relative to the peak, after aligning): o = 2: 8.5% (L = 2), 4.3% (L = 3), 3.7% (L = 4), centroid exact; o = 3: 26–55%, centroid wobbles ±0.5 px; o = 1: 71–79% with the centroid snapping by up to ±(2^L−1)/2 px (the PSF jumps to the coarse grid, like a plain mip chain).

**Algorithms and cost.** Downsample: 5 fetches per **output** pixel at 1/4, 1/16, … of full res; upsample: 8 fetches per output pixel at 1/16 … full res. Per full-res pixel: downsample `5·(1/4 + 1/16 + …) < 5/3`, upsample `8·(1 + 1/4 + …) ≈ 8·4/3 ≈ 10.7` (if the last upsample writes full res), total ≈ 12.3 fetches and about 1.33 full-res writes for any L (COMPUTED). Bandwidth is the reason it exists: it touches each full-res pixel about twice, versus 2 reads + 1 write per pass × n passes for Kawase. The Qiita write-up reports Dual Blur as fastest on a Mali-T760 MP8 (Galaxy S6) (REFERENCE, qualitative).

**GPU implementation.** L render passes into a mip-like chain of textures (each half the size), L passes back up; each pass a full-screen triangle with 5 or 8 `sample()`s. On tile-based GPUs (Apple, Mali) each pass is small and stays in tile memory; no compute needed. See `gpu-pipeline.md` §3.6.

**Visual fingerprint.** Smooth, wide, cheap; slightly flat-topped glow (kurtosis < 3, so point lights look like soft discs with a firmer edge than a Gaussian); faint ~5% reversed ring on a Siemens star; with large o, **blocky/lattice artifacts and shimmering** when the content moves by sub-2^L-pixel steps (shift variance), worst on thin bright lines and text scrolling under a blurred panel. Best tests: a slowly panning Siemens star or text behind the blur (temporal shimmer), and point lights at large o.

**Where used.** KDE Plasma KWin blur effect (window/panel translucency; `blur.cpp` uses the dual-filter down/upsample passes); VLC's Qt interface ("qt: use 'Dual Kawase' blur", VideoLAN merge request 7461; REFERENCE); Unity mobile post-processing community implementations; ARM's mobile guidance.

**Signature.** "Shrink, blur a little, grow, blur a little: a huge glow for about a dozen fetches per pixel, slightly flat-topped and slightly shimmery."

## 14. pyramid-blur

**id** `pyramid-blur`. **Aliases:** mip-chain blur, downsample–upsample blur, Gaussian pyramid blur, LOD-bias blur, "bloom chain" (when accumulated). **Family:** multi-resolution approximation of a large Gaussian; **approximately** LSI (decimation aliasing makes it shift-variant). Variants: plain mipmap (2×2 box down + bilinear up), Burt–Adelson Gaussian pyramid (5-tap binomial down/up, Burt & Adelson 1983), dual-Kawase (§13), and the Call of Duty: Advanced Warfare bloom chain (Jorge Jimenez, "Next Generation Post Processing in Call of Duty: Advanced Warfare", SIGGRAPH 2014 Advances in Real-Time Rendering course; REFERENCE via the author's page and the LearnOpenGL "Physically Based Bloom" article by Alexander Christensen, which reproduces the kernels; the 407 MB slide deck was not opened here).

**Definition.** `blur = U^L ∘ D^L`, where D low-pass filters and decimates by 2 and U interpolates by 2 and low-pass filters. Since decimation is not shift invariant, the operator's PSF depends on the input position modulo 2^L. Kernels:
- *Plain mip:* D = 2×2 box (what `generateMipmaps`/`MTLBlitCommandEncoder.generateMipmaps(for:)` does; Apple does not document the exact filter, INFERRED box), U = bilinear (a tent of half-width 2 output pixels).
- *CoD 13-tap downsample:* 13 bilinear fetches at offsets {−2, 0, 2}² and {±1}² source texels from the output centre (which lies on a source texel corner, so each fetch is a 2×2 block mean, 36 texels touched). Weights: centre 0.125; the four (±2,±2) corners 0.03125; the four edge midpoints (±2,0),(0,±2) 0.0625; the four inner (±1,±1) 0.125. Equivalently, five overlapping 4×4 boxes: inner box weight 0.5, four corner boxes 0.125 each. *Upsample:* 3×3 tent `[1 2 1; 2 4 2; 1 2 1]/16` with a radius fixed in UV (not texels), each level added to the next finer one.
- *Firefly suppression (CoD):* the first downsample weights each 2×2 group by `1/(1 + luma)` ("Karis average"), which makes the chain **nonlinear** (no PSF at all for HDR content).

**Parameters.** Levels L (σ roughly ∝ 2^L), kernel choice, upsample radius, and for bloom the per-level weights and final mix (CoD/LearnOpenGL: about 0.04).

**Effective σ and shift variance (COMPUTED, `pyr.py`, exact bilinear simulation on impulses at all 2^L × 2^L sub-positions).**

| variant | L = 2 | L = 3 | L = 4 | shift variance (max ΔPSF / peak) | centroid error |
|---|---|---|---|---|---|
| plain mip (box down, bilinear up) | σ 1.94 | 3.97 | 7.98 | 0.89–0.97 | snaps by up to ±(2^L − 1)/2 px (±7.5 px at L = 4) |
| CoD 13-tap down + tent up (single chain, no accumulation) | 4.74 | 9.72 | 19.56 | 0.011–0.023 | 0 |
| dual-Kawase, o = 2 | 5.85 | 11.98 | 24.1 | 0.037–0.085 | 0 |

So the plain mip chain is **not a usable blur for moving content**: its output for a moving point light jumps between coarse texels. The CoD kernel is nearly shift-invariant (≤ 2%) and nearly Gaussian (kurtosis 2.81 axis / 2.93 diagonal; real-MTF minimum −0.0008: practically no inversion). That combination is why it is the modern default for bloom.

**Bloom accumulation.** When the levels are **summed** (each upsampled level added to the next finer mip, as CoD and LearnOpenGL do), the result is not a Gaussian but a sum of Gaussians with σ doubling per level: a sharp core with a **power-law tail**. For 5 levels the radial profile falls about as `r^−2.2` between 4 and 64 px (COMPUTED, `pyr2.py`; centre-relative values 1, 0.077, 0.020, 0.0085, 0.0045 at r = 0, 8, 16, 24, 32 px). This heavy tail resembles optical veiling glare and is the visual reason modern bloom looks "physical"; it relates to the Lorentzian/Poisson kernels of §16.

**Frequency response.** No single MTF; phase-averaged responses are low-pass. Aliasing from decimation folds high frequencies down: a zone plate shows **moiré** (spurious low-frequency rings) in a plain mip chain; the 13-tap pre-filter suppresses it strongly.

**Algorithms and cost.** Per full-res pixel: downsample work `taps·(1/4 + 1/16 + …) = taps/3`; upsample `taps·(1 + 1/4 + …) ≈ 4·taps/3` if the final level is written at full res. CoD: `13/3 + 9·4/3 ≈ 16.3` fetches per full-res pixel; plain mip: hardware box (blit) + 1 bilinear fetch if sampling the coarse level directly. Constant in σ. LOD-bias variant: one `sample(s, uv, bias(b))` with trilinear filtering reads the mip chain directly (cheapest, blockiest).

**GPU implementation.** Mip chain textures (`MTLTexture` with `mipmapLevelCount`, or separate textures), one render or compute pass per level each way; or `MTLBlitCommandEncoder.generateMipmaps` for the box chain. See `gpu-pipeline.md` §3.5. On tile-based GPUs each small pass is cheap; the deep levels (≤ 64×64) are latency- not bandwidth-bound.

**Visual fingerprint.** Plain mip: **blocky, diamond-faceted glows** (bilinear tents on a coarse grid) and **shimmer/popping** when the image moves; zone-plate moiré. CoD chain: smooth Gaussian-like glow, stable in motion; when accumulated, a bright core plus long, soft tail. Best tests: a slowly moving point light (shift variance becomes temporal flicker), and a zone plate (aliasing).

**Where used.** Call of Duty: Advanced Warfare bloom (2014) and many engines and tutorials after it (LearnOpenGL 2022); Unity/Unreal standard bloom also use downsample/upsample chains (REFERENCE for Unreal: "the standard method is not conservative", Epic Bloom docs; kernel details per engine UNVERIFIED here); OpenCV `pyrDown`/`pyrUp` (Burt–Adelson); UI backdrop blurs on mobile very likely downsample before blurring (INFERRED for Apple; see `gpu-pipeline.md` §1.3 and `live-calibration.md`).

**Signature.** "Blur by shrinking: the cheapest wide blur there is, as long as you hide the grid it was computed on."

## 15. disc-blur

**id** `disc-blur`. **Aliases:** pillbox, circular averaging filter (MATLAB `fspecial('disk')`), uniform disc, defocus PSF (geometric optics), `CIDiscBlur`. **Family:** LSI (constant radius), isotropic, positive in space, sign-changing in frequency, **not separable**. This section is the LSI summary; the full optical treatment (bokeh, polygonal apertures, complex-Gaussian separable approximations, stochastic sampling, depth-varying CoC) is in `catalog-spatial.md` §2.1–2.5, whose numbers agree with these.

**Continuous definition.** `h(r) = 1/(πR²)` for `r ≤ R`, else 0.

**Parameters.** Radius R (= half the circle-of-confusion diameter). Per-axis variance `R²/4`, so `σ_equiv = R/2` (COMPUTED; discrete check: hard-sampled R = 5 → 2.548, area-coverage → 2.520, R = 20 → 10.00). So a disc of radius 10 and a Gaussian of σ = 5 have the same second moment but look completely different.

**Discrete kernel.** Hard sampling (`x² + y² ≤ R²`; R = 10 → 317 taps vs πR² = 314.2) or area-coverage antialiasing (supersample each pixel; needed for small R and for smooth animation of R). Normalize to sum 1. Edge handling: any §0 mode; zero-extension darkens borders strongly because the kernel is flat.

**Frequency response (closed form).** `H(ρ) = 2·J₁(2πRρ)/(2πRρ)` (the "jinc"/Airy amplitude pattern), radially symmetric. Half amplitude at `ρ = 0.3525/R`; first zero at `ρ = 0.6099/R` (`2πRρ = 3.8317`); deepest negative lobe −0.1323 at `ρ = 0.8174/R`; next positive lobe +0.0645 at `ρ = 1.3396/R` (COMPUTED, `jinc.py`, matching `catalog-spatial.md`). Contrast inversion is weaker than the box's (−0.217) but **the same in every direction**: on a Siemens star the null/inversion rings are perfect circles.

**Properties.** Linear, shift invariant, isotropic, positive, normalized, compact support with a hard rim, flat top, **not separable** (matrix rank grows with R), not a semigroup (disc∗disc is a smooth bump). Platykurtic in every direction (excess kurtosis of a 1-D projection −1.0 vs box −1.2, Gaussian 0; COMPUTED from the semicircle line-spread function `LSF(x) ∝ sqrt(R² − x²)`, whose kurtosis is 2.0).

**Algorithms and cost.**
- Direct 2-D: `≈ πR²` MACs per pixel (R = 10: 317; R = 40: ~5,000).
- Row decomposition: a disc is a stack of `2R+1` horizontal spans, each a 1-D box; with a per-row prefix sum (1-D SAT), each span costs 2 fetches → `≈ 2(2R+1)` fetches per pixel, O(R). Exact.
- FFT (§11): O(log N), best for large R.
- Sum of complex Gaussians (separable complex kernels approximating a disc; Kleber Garcia, "Circular Separable Convolution Depth of Field", SIGGRAPH 2017 Talks; see `catalog-spatial.md` §2.4): O(R) with a few complex separable passes; approximate, with small ripples.
- Polygon apertures from skewed boxes (hexagon as 3 rhombi; McIntosh, Riecke & DiPaola 2012; `catalog-spatial.md` §2.3).
- Stochastic gather (golden-angle/Vogel spiral or Poisson disc of K taps): O(K), noisy; not exactly LSI if jittered per pixel.

**GPU implementation.** Gather with K taps in a spiral or ring pattern (common in game depth-of-field), at half resolution; or the row-SAT exact method in compute; or MPSGraph FFT. Core Image `CIDiscBlur` (radius default 8) MEASURED on macOS 27.2 as a uniform disc of radius r (`live-calibration.md`); its internal algorithm is INFERRED.

**Visual fingerprint.** Point light → **flat disc with a hard rim** (the bokeh ball); edges → the "half-disc area" S-curve (steeper in the middle than a Gaussian's); Siemens star → **round** grey null rings with reversed spokes between them (vs square rings for box, none for Gaussian); text → doubled/ghosted strokes where stroke spacing falls in the negative lobe. Best tests: night-city lights (shape), Siemens star (round inversion rings).

**Where used.** Lens/defocus blur in Photoshop Lens Blur, Core Image `CIDiscBlur`/`CIBokehBlur`, game depth of field, portrait modes (INFERRED internals); see `catalog-spatial.md` §2.1.

**Signature.** "The lens's blur: every point becomes a flat coin, and stripes at the wrong spacing come back inverted in perfect circles."

## 16. exponential / Laplace / Lorentzian kernels

**ids** `exponential-blur` (Laplace kernel), `lorentzian-blur` (Cauchy / Poisson kernel). **Aliases:** exponential smoothing, single-pole IIR, ISEF (infinite symmetric exponential filter, Shen & Castan 1992), "glow", Cauchy/Lorentzian PSF, Poisson kernel, veiling-glare kernel. **Family:** LSI, positive in space **and** frequency, heavy-tailed ("peaky") kernels: the opposite end from the flat-topped box/disc.

**Continuous definitions.**
- *Laplace (exponential), 1-D:* `h(x) = (1/2b)·e^{−|x|/b}`; `H(ν) = 1/(1 + (2πbν)²)` (a Lorentzian in frequency). Variance `2b²` (σ = √2·b). Cusp at x = 0 (not differentiable), so `H` decays only like `ν⁻²`.
- *Separable 2-D:* `h(x)h(y) ∝ e^{−(|x|+|y|)/b}`: **diamond-shaped** level sets (the 1% contour reaches 0.707× as far along the diagonal as along the axis; COMPUTED `bw.py`).
- *Isotropic 2-D:* `h(r) = e^{−r/b}/(2πb²)`; `H(ρ) = 1/(1 + (2πbρ)²)^{3/2}`; per-axis σ = √3·b. Not separable.
- *Lorentzian / Cauchy, 1-D:* `h(x) = γ/(π(x² + γ²))`; `H(ν) = e^{−2πγ|ν|}`; FWHM = 2γ; **infinite variance** (σ undefined). *2-D Poisson kernel:* `h(r) = γ/(2π(r² + γ²)^{3/2})`, `H(ρ) = e^{−2πγρ}`. Both form a semigroup in γ (γ's add, unlike Gaussian σ² adding).

**Parameters.** Decay length b (exponential) or half-width γ (Lorentzian). Because the Lorentzian has no variance, "match σ" conversions are meaningless; match FWHM or the 50%-energy radius instead.

**Discrete construction.** Exponential: exactly realizable by a first-order recursion `y[n] = (1−a)x[n] + a·y[n−1]` forward, then backward, with `a = e^{−1/b}`; the cascade's impulse response is `((1−a)/(1+a))·a^{|n|}` (sum 1), discrete variance `2a/(1−a)²` (b = 5 → σ = 7.06 vs continuous 7.07); MTF `(1−a)²/(1 − 2a·cos 2πν + a²)`, at Nyquist `((1−a)/(1+a))²` = 0.0099 for b = 5 (COMPUTED). Lorentzian: sampled and truncated FIR (the tail must be cut somewhere; 1/x² tails hold ~2/π·γ/r of the mass beyond r, so truncation at r = 50γ still drops ~1.3%) or FFT with `e^{−2πγρ}` directly.

**Properties.** Linear, shift invariant, positive in space and frequency (no zeros, no inversion), not edge preserving. Exponential separable form is anisotropic (diamond); isotropic forms are not separable. Peaky: excess kurtosis +3 (Laplace) vs 0 (Gaussian).

**Algorithms and cost.** Exponential: 2 MACs per pixel per direction, 2 directions per axis: **the cheapest O(1) blur that exists**, exact (no approximation), but only the separable/diamond version. Isotropic exponential and Lorentzian: FFT, or a sum of Gaussians at doubling σ (which is exactly what an accumulated bloom chain produces, §14). GPU: one thread per row/column recursion (like §10), or FFT.

**Visual fingerprint.** **Sharp core + long glow**: edges keep a crisp step but gain a wide soft skirt; point lights look like glowing stars rather than soft balls; with the separable exponential, the glow is visibly **diamond-shaped** on HDR lights. Lorentzian is the extreme: a bright light lifts the black level across a large area (veiling glare). Best tests: night-city lights at high exposure (tail shape), and a step edge (cusp-preserving profile).

**Where used.** Shen & Castan's ISEF edge detector (Shen & Castan, "An optimal linear operator for step edge detection", CVGIP: Graphical Models and Image Processing 54(2), 1992; REFERENCE, not re-read); exponential smoothing in signal processing; physically based glare (Spencer, Shirley, Zimmerman & Greenberg, "Physically-Based Glare Effects for Digital Images", SIGGRAPH 1995, model the eye's PSF with power-law terms; REFERENCE, details not re-read); subsurface-scattering diffusion profiles in rendering, e.g. Burley's normalized diffusion `(e^{−r/d} + e^{−r/(3d)})/(8πdr)` (Burley, "Extending the Disney BRDF to a BSDF with Integrated Subsurface Scattering", SIGGRAPH 2015 course notes; formula recalled, UNVERIFIED in this pass); summed bloom chains (§14) approximate a power-law tail.

**Signature.** "All tail, no shoulders: a pin-sharp core inside a wide glow, and the only blurs here whose spectrum never touches zero at any width."

## 17. frequency-domain low-pass: ideal (brick-wall), Butterworth, Gaussian

**ids** `ideal-lowpass`, `butterworth-lowpass`, `gaussian-lowpass`. **Aliases:** ILPF, BLPF, GLPF (Gonzalez & Woods, *Digital Image Processing*, ch. 4 "Filtering in the Frequency Domain"; REFERENCE), brick-wall filter, sinc/jinc filter. **Family:** LSI, defined by `H(ρ)` and applied by FFT (§11); the ideal and high-order Butterworth have **negative spatial lobes** (they ring), so they are "blurs" only in the frequency sense.

**Definitions (cut-off D₀ in cycles/px; radial frequency ρ).**
- *Ideal:* `H = 1` for `ρ ≤ D₀`, else 0. Spatial kernel: 1-D `2D₀·sinc(2D₀x)`; 2-D circular `D₀·J₁(2πD₀r)/r` (jinc). Infinite support, slow `1/r^{3/2}` decay in 2-D.
- *Butterworth of order n:* image-processing convention `H = 1/(1 + (ρ/D₀)^{2n})` (Gonzalez & Woods); signal-processing convention `|H| = 1/sqrt(1 + (ρ/D₀)^{2n})`. n → ∞ gives the ideal filter. In 1-D, the order-1 image-processing Butterworth **is** the exponential kernel of §16 (`e^{−2πD₀|x|}`).
- *Gaussian:* `H = e^{−ρ²/(2D₀²)}` = a spatial Gaussian with `σ = 1/(2πD₀)` (D₀ = 0.05 cycles/px ↔ σ = 3.18 px).

**Parameters.** D₀ (cut-off) and n (sharpness). Relation to spatial size: the first zero of the ideal 1-D kernel is at `x = 1/(2D₀)`.

**Discrete construction.** Sample `H` on the DFT grid (`k/N` cycles/px, with wrap for negative frequencies), multiply, inverse FFT; pad the image to avoid wrap. Sampling an ideal `H` makes a spatial kernel that is aliased (periodic sinc), so the ringing wraps around the image too.

**Frequency response.** As defined: flat passband, then a cliff (ideal), a soft shoulder (Butterworth), or a smooth roll-off (Gaussian).

**Ringing (COMPUTED, `bw.py`, step-edge overshoot as % of the step, D₀ = 0.05).** Ideal: 8.87% (the Gibbs phenomenon; continuous limit 8.95%). Butterworth, image-processing convention: n = 1: 0%, n = 2: 3.4%, n = 3: 5.6%, n = 4: 6.8%, n = 6: 7.9%, n = 8: 8.3%, n = 20: 8.8%. Signal-processing convention: n = 2: 2.4%, n = 3: 4.4%, n = 4: 5.7%, n = 6: 7.0%, n = 8: 7.8%. Gaussian: 0 (to 10⁻¹³). Gonzalez & Woods make the same qualitative point (order-1 BLPF has no ringing; ringing becomes significant at higher orders; REFERENCE).

**Properties.** Linear, shift invariant (circularly, under FFT), isotropic (radial H), not separable (except the Gaussian), not positive in space (ideal, Butterworth n ≥ 2): outputs overshoot the input range, so 8-bit results clip.

**Algorithms and cost.** FFT only (the spatial kernels are infinite): see §11. Not a real-time UI blur.

**Visual fingerprint.** **Ripples**: concentric halos around every point light and parallel echo lines along every edge (ideal), weaker but present for Butterworth n ≥ 2; and nothing at all above the cut-off (the zone plate is cut off at a sharp circle for the ideal filter, a soft one for Butterworth). Best tests: step edge (overshoot), night-city lights (rings), zone plate (the cut-off circle).

**Where used.** Textbook image processing (Gonzalez & Woods ch. 4), signal-processing teaching, anti-alias filters in theory; real products avoid ideal low-pass for images precisely because of ringing.

**Signature.** "Remove every frequency above the line and keep everything below it, and the image answers with ripples."

## 18. lanczos (contrast note: not a blur)

**id** `lanczos` (contrast entry). **Aliases:** Lanczos-windowed sinc, Lanczos-2 / Lanczos-3. **Family:** LSI interpolation kernel with negative lobes: a **reconstruction/resampling** filter, included to show what a blur is *not*.

**Definition.** `L_a(x) = sinc(x)·sinc(x/a)` for `|x| < a`, else 0 (a = 2 or 3). Separable in 2-D in practice (`L_a(x)L_a(y)`).

**Key facts (COMPUTED, `misc.py`).** At unit scale, sampled at integer offsets, `L_a[n] = δ[n]`: **applied to an image without resampling, Lanczos does nothing** (it is an interpolator: zero at every non-zero integer). It acts only when sampling between pixels (resampling) or when stretched by s ≥ 1 for downscaling (a low-pass with cut-off ≈ 0.5/s cycles/px). Negative lobes: Lanczos-2 minimum −0.086 at x ≈ ±1.30; Lanczos-3 minimum −0.147 at x ≈ ±1.37. Stretched by s = 4 as a low-pass: step overshoot 4.1% (Lanczos-2) and 6.9% (Lanczos-3), and its MTF stays ≈ 1 up to near the cut-off (0.94 / 1.01 at ν = 0.0625).

**Why it matters for the app.** It is the honest counter-example: same family (LSI, separable, normalized), but its MTF is designed to stay **flat** up to the cut-off and fall sharply, so it preserves detail and rings, the opposite goal from a blur. Showing Lanczos next to Gaussian on the step edge (overshoot halo vs smooth S-curve) explains why blurs need positive kernels.

**Where used.** Image resampling in ImageMagick, FFmpeg/libswscale, Pillow, GIMP and most photo apps (REFERENCE: ImageMagick "Resampling Filters" documentation describes Lanczos as a windowed sinc).

**Signature.** "A sinc with manners: it sharpens while it resizes, and at scale one it changes nothing at all."

## 19. Others found

Short entries for further LSI kernels worth including in the catalog (each could be promoted to a full card).

- **`cubic-b-spline`** (4 boxes, order-4 B-spline): `σ² = 4·(w²−1)/12`; continuous unit-spacing B-spline has σ² = 1/3 per box → 4/12; MTF `sinc⁴` ≥ 0; C² smooth PSF; excess kurtosis −0.3. On GPUs, 2-D cubic B-spline filtering of a texture costs **4 bilinear fetches** instead of 16 taps (Sigg & Hadwiger, "Fast Third-Order Texture Filtering", GPU Gems 2 ch. 20, 2005; REFERENCE). Signature: "four boxes deep: smooth enough to be a Gaussian, cheap enough to be a texture fetch."
- **Excess kurtosis as a shape ID (COMPUTED).** n equal boxes have excess kurtosis `−1.2/n`: box −1.2, tent −0.6, box³ −0.4, B-spline −0.3; binomial `B_n`: `−2/n`; Gaussian 0; disc line-spread −1.0; Laplace +3; Lorentzian undefined. The app can fit kurtosis to any measured PSF (as `live-calibration.md` does) to classify it.
- **`hann-blur` / raised-cosine kernel** `h(x) ∝ ½(1 + cos(πx/R))` for |x| < R: positive, C¹, compact; σ = 0.3615·R; MTF first zero at ν = 1/R and minimum −0.027 at ν ≈ 1.18/R (COMPUTED): about a tenth of the box's inversion. Used as a smooth window in DSP; INFERRED to be rare as an image blur.
- **`anisotropic-gaussian`** (elliptical, rotated covariance): LSI, separable only when axis-aligned; rotated versions via two skewed 1-D passes (Geusebroek et al. 2003) or Lam & Shi's triple-axis decomposition (Lam & Shi, "Recursive anisotropic 2-D Gaussian filtering based on a triple-axis decomposition", IEEE TIP 16(7), 2007; REFERENCE, not re-read). Covered in `catalog-spatial.md` §1.2.
- **`linear-motion-blur`** (line PSF of length L at angle θ): LSI, MTF `sinc(L·ν_θ)` along the motion direction only, contrast inversion in stripes perpendicular to the motion. Covered in `catalog-spatial.md` §1.1.
- **`polygonal-bokeh`** (hexagon, octagon aperture PSFs): LSI for fixed size, built from 2–3 skewed box passes. `catalog-spatial.md` §2.3.
- **`airy-diffraction`**: the physical diffraction PSF `[2J₁(πr/λN)/(πr/λN)]²` (intensity), positive, with faint rings in space (not in frequency: its MTF is the positive "chinese hat" `(2/π)(arccos ρ̂ − ρ̂·sqrt(1−ρ̂²))`). `catalog-spatial.md` §2.7.
- **`lindeberg-discrete-gaussian`** (`e^{−t}I_n(t)`): the exact discrete scale-space kernel (§2); worth its own toggle for σ < 1, where sampled Gaussians fail (σ = 0.3 sampled has true σ 0.088; Lindeberg's has 0.300).
- **`sum-of-gaussians`** (e.g. 2–6 Gaussians at different σ with weights): positive, isotropic, separable per term; how skin diffusion profiles and accumulated bloom are implemented in real time (d'Eon & Luebke, "Advanced Techniques for Realistic Real-Time Skin Rendering", GPU Gems 3 ch. 14, 2007; REFERENCE). Signature: "a long tail built from round pieces."
- **`texture-lod-bias-blur`**: sampling a mipmapped texture with a positive LOD bias (`sample(s, uv, bias(b))`), the one-instruction blur; trilinear between box-filtered levels; strongly shift-variant (see §14 plain mip); used in cheap UI and particle effects. INFERRED usage.


## 20. Comparison table

Cost is per output pixel for a 2-D image; r = kernel radius in pixels, σ = Gaussian standard deviation, L = pyramid levels, n = passes. "MTF ≥ 0" means no contrast inversion. "Overshoot" is the step-edge overshoot (ringing). Numbers are COMPUTED in this document unless marked.

| id | separable | cost per pixel vs size | passes | positive kernel | MTF ≥ 0 (no inversion) | isotropic | overshoot / ringing | exactly LSI | typical use |
|---|---|---|---|---|---|---|---|---|---|
| box-blur | yes | 2(2r+1) separable; **O(1)** sliding sum | 2 | yes | **no** (−21.7%) | no (square) | none | yes | Photoshop Box Blur, `CIBoxBlur`, `MPSImageBox`, building block |
| gaussian-blur (2-D FIR) | yes | (2r+1)², r = kσ (k ≈ 3) | 1 | yes | yes (truncation ripples ≤ 0.1% at k = 3) | **yes** | none | yes | reference blur; CSS `blur()`, `CIGaussianBlur` |
| gaussian-separable | yes | 2(2r+1) | 2 | yes | yes | yes | none | yes | real-time default, `MPSImageGaussianBlur` |
| gaussian-linear-sampling | yes | ≈ 2(r+1) fetches | 2 | yes | yes | yes | none | yes (≤ 1/512 weight quantization) | engines, bloom, any positive separable kernel |
| tent-blur | yes | 2(2r+1), or O(1) (2 sliding boxes / repeated integration) | 2 | yes | **yes** (zeros only) | no (square pyramid) | none | yes | bilinear filtering/upsampling |
| binomial-blur | yes | 2(n+1) | 2 | yes | yes, **exact 0 at Nyquist** | nearly | none | yes | ISPs, Burt–Adelson pyramids, "3×3 Gaussian" |
| iterated-box | yes | **O(1)**: 2 adds + 1 mul per pass | 2n | yes | n even yes; **n odd ≈ −1%** | no (square support) | none | yes | SVG/CSS three-box, fast CPU Gaussian, SwiftUI large r (MEASURED box³-like) |
| stack-blur | yes | **O(1)** (integer adds, mul+shift) | 2 | yes | yes | no | none | yes (±1 LSB rounding) | StackBlur.js, AGG, mobile CPU blur |
| sat-box | (box) | **4 fetches** for any size + O(1) build | build (2 scans) + 1 | yes | no (−21.7%) | no | none | yes (variable box: no) | variable-size blur, Viola–Jones, SURF |
| iir-gaussian | yes | **O(1)**: ≈ 8–16 MACs per axis | 2 axes × 2 directions | ≈ (Deriche K = 4: −1.4·10⁻⁴) | ≈ yes | ≈ (diamond tails) | none visible | yes except at borders | ITK, GIMP/GEGL IIR, AGG |
| fft-convolution | any kernel | **O(log N)**, ≈ 116 flops at 2048² padded | FFT, ×, iFFT | kernel's | kernel's | kernel's | kernel's | yes (circular) | huge or arbitrary kernels, Unreal Convolution bloom |
| kawase-blur | yes (implicitly) | 4 fetches × n passes; σ grows ≈ n^1.5 | n | yes | **no** (≈ −4.7% for {0,1,2,2,3}) | no | none | yes | bloom, older UI blur |
| dual-kawase | no | ≈ 12.3 fetches total for any L | 2L | yes | no (≈ −4.6%) | ≈ (flat-topped) | none | **no** (3.7–8.5% shift variance at o = 2) | KWin, VLC, mobile UI blur |
| pyramid-blur (plain mip) | no | ≈ blit + 1 fetch | 2L or LOD bias | yes | (no single MTF) | no (faceted) | none | **no** (PSF snaps up to ±(2^L−1)/2 px) | cheapest wide blur, LOD-bias tricks |
| pyramid-blur (CoD 13-tap + tent) | no | ≈ 16.3 fetches total | 2L | yes | ≈ yes (−0.08%) | ≈ | none | approx. (≤ 2.3% shift variance) | modern bloom (accumulated: power-law tail) |
| disc-blur | no | πR² direct; 2(2R+1) row-SAT; FFT | 1 | yes | **no** (−13.2%, round rings) | **yes** | none | yes | bokeh, depth of field, `CIDiscBlur` |
| exponential-blur (separable) | yes | **O(1)**: 4 MACs per axis | 2 axes × 2 directions | yes | yes | no (diamond) | none | yes | glow, ISEF edge detection |
| lorentzian-blur / Poisson | no | FFT, or sum of Gaussians | — | yes | yes | yes | none | yes | glare, physically based bloom tails |
| ideal-lowpass | no (radial) | FFT | 3 | **no** | yes (0/1) | yes | **8.9%** (Gibbs) | yes (circular) | textbook contrast case |
| butterworth-lowpass (order n) | no | FFT | 3 | n = 1 yes; n ≥ 2 no | yes | yes | 0% (n = 1) → 3.4% (n = 2) → 8.8% (n = 20) | yes | textbook |
| gaussian-lowpass (frequency) | (= Gaussian) | FFT | 3 | yes | yes | yes | none | yes | textbook; same as Gaussian with σ = 1/(2πD₀) |
| lanczos (contrast) | yes | 2·2a taps per resample | 2 | **no** | flat to cut-off | no | 4–7% when used as low-pass | yes | resampling, not blurring |
| cubic-b-spline | yes | O(1) (4 sliding boxes) or 4 bilinear fetches (2-D texture) | 2–8 | yes | yes | no | none | yes | smooth texture filtering |

**Parameter → σ (per axis) cheat sheet (COMPUTED).**

| blur and its parameter | σ |
|---|---|
| box, odd width w | sqrt((w² − 1)/12) ≈ 0.289·w |
| tent / stack blur, radius r | sqrt(r(r+2)/6) ≈ 0.408·(r+1) |
| binomial `B_n` | √n / 2 |
| n boxes of width w | sqrt(n(w² − 1)/12) |
| SVG/CSS three-box for stdDeviation s | ≈ 0.94·s (d = floor(1.880·s + 0.5)) |
| Kawase sequence {i_j} | sqrt(Σ (i_j² + (i_j+1)²)/2); {0,1,2,2,3} → 5.34 |
| dual-Kawase, o = 2, L levels | ≈ 1.5·2^L (5.85, 11.98, 24.1 for L = 2, 3, 4) |
| CoD 13-tap chain (no accumulation), L levels | ≈ 1.22·2^L (4.74, 9.72, 19.56) |
| plain mip chain, L levels | ≈ 0.5·2^L (1.94, 3.97, 7.98) |
| disc radius R | R/2 |
| exponential, decay b | √2·b (1-D or separable); √3·b per axis (isotropic) |
| Lorentzian γ | undefined (infinite variance); FWHM = 2γ |
| Gaussian low-pass cut-off D₀ | 1/(2πD₀) |
| Young–van Vliet target σ | target, but moment σ +9–13% (tails), best-fit σ +2% |
| AGG `recursive_blur` "radius" | radius / 2 |
| CSS `blur(L)`, `CIGaussianBlur` r, `MPSImageGaussianBlur` sigma | L, r, sigma (per spec / MEASURED in `live-calibration.md`) |

## 21. Sources

Papers and books
- Babaud, Witkin, Baudin & Duda, "Uniqueness of the Gaussian kernel for scale-space filtering", IEEE PAMI 8(1):26–33, 1986.
- Bay, Tuytelaars & Van Gool, "SURF: Speeded Up Robust Features", ECCV 2006.
- Bhatia, Snyder & Bilbro, "Stacked integral image", IEEE ICRA 2010, pp. 1530–1535.
- Burt & Adelson, "The Laplacian Pyramid as a Compact Image Code", IEEE Trans. Communications 31(4):532–540, 1983.
- Crow, "Summed-area tables for texture mapping", SIGGRAPH '84, Computer Graphics 18(3):207–212, 1984.
- d'Eon & Luebke, "Advanced Techniques for Realistic Real-Time Skin Rendering", GPU Gems 3 ch. 14, 2007.
- Deriche, "Recursively implementing the Gaussian and its derivatives", INRIA Research Report 1893, 1993 (coefficients via Getreuer 2013).
- Elboher & Werman, "Efficient and accurate Gaussian image filtering using running sums", arXiv:1107.4958, 2011.
- Garcia, "Circular Separable Convolution Depth of Field", SIGGRAPH 2017 Talks.
- Geusebroek, Smeulders & van de Weijer, "Fast anisotropic Gauss filtering", IEEE TIP 12(8), 2003.
- Getreuer, "A Survey of Gaussian Convolution Algorithms", Image Processing On Line 3:286–310, 2013, doi:10.5201/ipol.2013.87, https://www.ipol.im/pub/art/2013/87/ (PDF read for Table 3, §3.3–3.5, §6).
- Gonzalez & Woods, *Digital Image Processing*, ch. 4 (ideal, Butterworth, Gaussian low-pass filters).
- Gwosdek, Grewenig, Bruhn & Weickert, "Theoretical foundations of Gaussian convolution by extended box filtering", SSVM 2011, pp. 447–458.
- Harris, Sengupta & Owens, "Parallel Prefix Sum (Scan) with CUDA", GPU Gems 3 ch. 39, 2007.
- Heckbert, "Filtering by repeated integration", SIGGRAPH '86, Computer Graphics 20(4), 1986.
- Hensley, Scheuermann, Coombe, Singh & Lastra, "Fast summed-area table generation and its applications", Computer Graphics Forum 24(3) (Eurographics 2005).
- Kac, "On a characterization of the normal distribution", American Journal of Mathematics 61(3), 1939.
- Kovesi, "Fast Almost-Gaussian Filtering", DICTA 2010, pp. 121–125, doi:10.1109/DICTA.2010.30 (bibliographic record only; full text not read).
- Lam & Shi, "Recursive anisotropic 2-D Gaussian filtering based on a triple-axis decomposition", IEEE TIP 16(7), 2007 (not re-read).
- Lindeberg, "Scale-space for discrete signals", IEEE PAMI 12(3), 1990.
- Martucci, "Symmetric convolution and the discrete sine and cosine transforms", IEEE TSP 42, 1994 (via Getreuer).
- McIntosh, Riecke & DiPaola, "Efficiently Simulating the Bokeh of Polygonal Apertures in a Post-Process Depth of Field Shader", Computer Graphics Forum 31(6), 2012 (via `catalog-spatial.md`).
- Nehab, Maximo, Lima & Hoppe, "GPU-efficient recursive filtering and summed-area tables", ACM TOG 30(6), SIGGRAPH Asia 2011.
- Shen & Castan, "An optimal linear operator for step edge detection", CVGIP: Graphical Models and Image Processing 54(2), 1992 (not re-read).
- Sigg & Hadwiger, "Fast Third-Order Texture Filtering", GPU Gems 2 ch. 20, 2005.
- Spencer, Shirley, Zimmerman & Greenberg, "Physically-Based Glare Effects for Digital Images", SIGGRAPH 1995 (not re-read).
- Triggs & Sdika, "Boundary conditions for Young–van Vliet recursive filtering", IEEE TSP 54(6):2365–2367, 2006.
- van Vliet, Young & Verbeek, "Recursive Gaussian derivative filters", ICPR 1998, vol. 1, pp. 509–514.
- Viola & Jones, "Rapid object detection using a boosted cascade of simple features", CVPR 2001.
- Wells, "Efficient synthesis of Gaussian filters by cascaded uniform filters", IEEE PAMI 8(2):234–239, 1986, doi:10.1109/TPAMI.1986.4767776 (via Getreuer).
- Young & van Vliet, "Recursive implementation of the Gaussian filter", Signal Processing 44(2):139–151, 1995.
- Yuille & Poggio, "Scaling theorems for zero crossings", IEEE PAMI 8(1):15–25, 1986.

Talks, articles, documentation, code
- Bjørge (ARM), "Bandwidth-Efficient Rendering", SIGGRAPH 2015 course "Moving Mobile Graphics" (slides not retrieved; kernels from implementations below).
- Christensen, "Physically Based Bloom", LearnOpenGL guest article, 2022, https://learnopengl.com/Guest-Articles/2022/Phys.-Based-Bloom (reproduces the CoD 13-tap downsample, tent upsample, Karis average).
- Epic Games, "Bloom in Unreal Engine" (Convolution bloom via FFT), https://dev.epicgames.com/documentation/en-us/unreal-engine/bloom-in-unreal-engine ; `FConvolutionBloomSettings` API docs.
- GEGL commit "operations: change gaussian-blur's 'filter' property into an enum", May 2013, https://mail.gnome.org/archives/commits-list/2013-May/msg05402.html ; GIMP manual "Gaussian Blur", https://docs.gimp.org/en/gimp-filter-gaussian-blur.html .
- Intel, "An Investigation Of Fast Real-Time GPU-based Image Blur Algorithms", 2014 (author credited as Filip Strugar on Intel video pages, spelling inconsistent), https://www.intel.com/content/www/us/en/developer/articles/technical/an-investigation-of-fast-real-time-gpu-based-image-blur-algorithms.html .
- ITK, `itk::RecursiveGaussianImageFilter` Doxygen, https://docs.itk.org/projects/doxygen/en/latest/classitk_1_1RecursiveGaussianImageFilter.html .
- Jimenez, "Next Generation Post Processing in Call of Duty: Advanced Warfare", SIGGRAPH 2014 Advances in Real-Time Rendering, https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/ (page read; 407.8 MB slides not opened).
- Kawase, "Frame Buffer Postprocessing Effects in DOUBLE-S.T.E.A.L (Wreckless)", GDC 2003 (slides not re-read; description via Intel 2014 and `geoffoxholm/kawase_halide`, https://github.com/geoffoxholm/kawase_halide).
- KDE KWin blur plugin, `src/plugins/blur/blur.cpp`, https://invent.kde.org/plasma/kwin/-/raw/master/src/plugins/blur/blur.cpp (halfpixel and offset table).
- Klingemann, "StackBlur (2004-)", https://quasimondo.com/2004/02/25/stackblur-2004/ ; AGG `agg_blur.h` (stack_blur, recursive_blur), https://agg.sourceforge.net/antigrain.com/__code/include/agg_blur.h.html .
- Kutskir, "Fastest Gaussian Blur (in linear time)", https://blog.ivank.net/fastest-gaussian-blur.html (boxesForGauss, timings).
- Rákos, "Efficient Gaussian blur with linear sampling", RasterGrid blog, 2010, https://www.rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/ .
- Reed, "Texture Gathers and Coordinate Precision", reedbeta.com; Quilez, texture hardware interpolation article, iquilezles.org (sub-texel precision; cited in §4 by the earlier pass, not re-read in this pass).
- UWA Technology, Dual Blur write-up (Qiita), https://qiita.com/UWATechnology/items/8b0eff5650d2c659c019 (dual-filter shader code, Mali-T760 note).
- VideoLAN, "qt: use 'Dual Kawase' blur", merge request 7461, https://code.videolan.org/videolan/vlc/-/merge_requests/7461 (title only).
- W3C, Filter Effects Module Level 1, Working Draft 18 December 2018, `feGaussianBlur` and `blur()`, https://www.w3.org/TR/filter-effects-1/ (three-box paragraph quoted from the downloaded spec).
- Apple SDK headers (iOS 27 SDK in Xcode 27.0 beta): `MPSGraphFourierTransformOps.h` (FFT, iOS 17+), `vDSP.h` (`vDSP_fft2d_zrip`), `MTLDevice.h` (`supports32BitFloatFiltering`, iOS 14+), `MTLBlitCommandEncoder.h` (`generateMipmapsForTexture:`).
- Sibling Blur2ool research: `stack-semantics.md`, `gpu-pipeline.md`, `live-calibration.md` (MEASURED Apple API behaviour), `catalog-spatial.md`, `catalog-nonlinear.md`.

Probe scripts (all COMPUTED numbers; in `$TMPDIR/blur2ool-lsi/`): `fam1.py` (tent, binomial), `aniso2.py` (directional kurtosis), `ibox.py` (iterated box, Kovesi split, SVG three-box), `sat.py` (SAT precision), `iir.py`/`iir2.py` (Deriche, Young–van Vliet, Alvarez–Mazorra errors), `kaw.py` (Kawase chains), `pyr.py`/`pyr2.py` (exact bilinear simulation of mip, dual-Kawase, CoD and Kawase; shift variance; bloom tail), `misc.py`/`jinc.py`/`bw.py` (disc, exponential, ideal/Butterworth/Gaussian low-pass, Lanczos). The `basics.py` and `aniso.py` probes cited in §0–§2 came from an earlier pass whose scratch directory no longer exists; `recheck.py` reproduces their box minima and variances, sampled-Gaussian σ shortfall, truncation masses, Gaussian half-amplitude and Nyquist values, and Rákos's merged weights and offsets, all matching to the digits printed.

## 22. Open questions / UNVERIFIED

1. **Apple GPU sub-texel precision** for bilinear filtering (affects §4, §12–§14): UNVERIFIED. MEASURE on device by sampling a 2-texel 0→1 ramp at 1,024 positions and counting distinct outputs.
2. **32-bit float filtering on A17 Pro**: query `MTLDevice.supports32BitFloatFiltering` at runtime (API exists since iOS 14); value for A17 Pro not checked here.
3. **`generateMipmaps` filter**: Apple documents only "generate mipmaps"; the 2×2 box is INFERRED. MEASURE with an impulse at each 2×2 phase.
4. **`MPSImageGaussianBlur` internals** (separable? downsampling for large σ?): INFERRED; `live-calibration.md` MEASURED σ = sigma exactly on macOS; timing vs σ on device would reveal whether it switches algorithms.
5. **Kawase's original offsets and sequences**: the GDC 2003 slides were not re-read; the `(i + ½)` diagonal convention is from the Intel 2014 article family and open implementations.
6. **Bjørge 2015 dual-filter original "halfpixel" definition**: implementations differ (KWin: 0.5/source size × offset; Unity/Qiita: ±1 source texel down, ±1/±½ up). Our σ and shift-variance numbers are given per offset o so any convention maps onto them.
7. **CoD 13-tap weights** come from LearnOpenGL's reproduction, not from the 407 MB slide deck.
8. **Wells 1986, Kovesi 2010, Deriche 1993, Young–van Vliet 1995** full texts were not read; formulas and coefficients come via Getreuer 2013 (which we reproduced numerically to 3 digits) and AGG source.
9. **Photoshop Gaussian Blur algorithm** (box iterations?): UNVERIFIED; no Adobe source. Kutskir reports 0.09% average per-pixel error for Photoshop vs a true Gaussian on his test image.
10. **Burley 2015 diffusion profile formula** in §16 recalled from memory: UNVERIFIED.
11. **Where KWin used plain Kawase before dual filtering**: UNVERIFIED.
12. **Young–van Vliet σ bias**: our implementation of the 1995 coefficients (as published and as in AGG) gives a moment σ 9–13% high and an ℓ1-best σ about 2% high; whether later errata adjust the q formula was not checked (VYV 1998 / Young, van Vliet & van Ginkel 2002 give improved poles).
13. **Browser behaviour**: whether Chromium/WebKit still use the three-box CPU path for SVG/CSS blur in 2026 is covered (and partly UNVERIFIED) in `stack-semantics.md`.

<!-- STATUS: COMPLETE -->
