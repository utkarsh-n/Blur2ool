# Blur2ool catalog: directional, spatially-varying and optical/lens blurs

Status: complete (written incrementally over two runs; the second run recreated the lost probe scripts). Author: research agent "spatial", 13 Oct 2026. Probe scripts: `$TMPDIR/blur2ool-spatial/probe1.py` (box/sinc), `probe4.py` (streak, coded shutter), `probe5.py` (jinc, Airy, spin, hexagon tiling), `probe6.py` (discrete pillbox, complex kernels, golden spiral, CoC), `probe7.py` (mip mixtures, SAT precision, CoC symmetry); they need numpy and mpmath (scipy in the default Python is broken against numpy 2.2).
Scope: the blurs whose point-spread function (PSF) has a direction, a shape that comes from an aperture, or a size/shape that changes across the image. Isotropic LSI blurs (box, Gaussian, tent, Kawase, dual filter, etc.) live in other catalog files; they are referenced here only as building blocks.

Honesty labels used in this file follow BRIEF.md: COMPUTED (exact consequence of the math, often checked numerically by a probe script in `$TMPDIR/blur2ool-spatial/`), REFERENCE (cited spec, paper or vendor doc), INFERRED (proprietary internals we cannot see), UNVERIFIED (a claim I could not confirm; treat with care).

## Contents

0. Conventions and cross-cutting ideas (LSI vs non-LSI, coordinate changes, the zone-plate trick, test images)
1. Directional family
   1.1 linear-motion-blur
   1.2 anisotropic-gaussian (directional Gaussian)
   1.3 kawase-streak / star-filter (iterated exponential-step directional blur)
   1.4 camera-shake-blur
   1.5 shutter-function-blur (box, trapezoid, coded/flutter shutter)
   1.6 velocity-buffer-motion-blur (McGuire et al. 2012 reconstruction filter)
   1.7 temporal-accumulation (frame blending, accumulation buffer, EMA trails)
   1.8 radial-zoom-blur
   1.9 spin-blur (rotational)
   1.10 path-blur
2. Aperture / lens family
   2.1 disc-bokeh (pillbox, lens blur)
   2.2 defocus-frequency-domain (jinc, zeros, spurious resolution; Hopkins defocus OTF)
   2.3 polygonal-bokeh (hexagon via skewed boxes; McIntosh et al. 2012; Frostbite/BF3)
   2.4 circular-separable-bokeh (Garcia 2017 complex kernels)
   2.5 stochastic-bokeh (Poisson disc, golden-angle spiral; Gustafsson 2018)
   2.6 cats-eye-swirl-bokeh (optical vignetting, Petzval swirl), plus soap-bubble / onion-ring / chromatic bokeh
   2.7 diffraction-airy (physical PSF; starburst spikes)
   2.8 anamorphic (oval bokeh, horizontal streaks)
3. Depth-dependent and spatially-varying family
   3.1 depth-of-field-coc (thin-lens CoC; scatter vs gather; foreground bleeding)
   3.2 tilt-shift (gradient CoC, miniature effect)
   3.3 variable-progressive-blur (mask-driven radius; CIMaskedVariableBlur; mip interpolation)
4. Comparison table (fingerprints)
5. Sources
6. UNVERIFIED list

---

## 0. Conventions and cross-cutting ideas

**Notation.** Images are functions f(x, y) (continuous) or f[m, n] (discrete). A blur produces g. A linear shift-invariant (LSI) blur is a convolution g = h * f with point-spread function (PSF) h, so the Fourier transform satisfies G(u, v) = H(u, v) F(u, v); H is the optical transfer function (OTF) and |H| the modulation transfer function (MTF). Frequencies u, v are in cycles per pixel unless noted; Nyquist is 0.5 cycles/pixel. "sinc(x)" means sin(pi x)/(pi x). "jinc(r)" means J1(2 pi r)/(pi r) up to normalisation (J1 is the Bessel function of the first kind, order 1); see 2.2.

**LSI vs non-LSI (the key split in this file).** Most blurs here are *linear* (g depends linearly on f) but many are *not shift-invariant*:

- A **linear shift-variant** (LSV) operator has the general form g(x) = integral of k(x, x') f(x') dx'. The kernel k depends on *both* the output position x and the input position x'. Two different ways to read k give two different "local PSFs":
  - **Gather / backward model:** fix the output pixel x; k(x, .) is the set of input pixels it averages. GPU post-processing almost always works this way (one fragment or thread per output pixel).
  - **Scatter / forward model:** fix the input point x'; k(., x') is the spot that point spreads into. Physical optics works this way (each scene point forms its own blur spot), and so does "splatting" bokeh.
  - For an LSI blur the two readings agree. For an LSV blur they do *not*, and the difference is visible: gather gives each output pixel a radius, scatter gives each source pixel a radius. This is exactly the depth-of-field foreground-bleeding problem (3.1) and the reason variable-blur masks look different in different products (3.3).
- **No single MTF exists** for an LSV blur. G is not H times F for any single H. What you can show instead: (a) the *local* MTF at a chosen pixel (the Fourier transform of the local PSF, valid only for a small patch where the PSF is nearly constant); (b) a *map* of a scalar summary (radius, angle, half-width) across the image; (c) for radial and spin blurs, an exact MTF *after a change of coordinates* (see below).
- **Coordinate tricks.** Some LSV blurs become LSI in a different coordinate system:
  - Spin blur (rotation about centre c) is a 1-D box blur along the angle axis in polar coordinates (r, theta) about c. It is LSI in theta for every r (circular convolution), but the blur length in pixels is r times the angle, so it grows linearly with distance from the centre.
  - Zoom/radial blur (sampling along rays towards c) is a 1-D box blur in *log-polar* coordinates (log r, theta) if the samples are spaced geometrically (scale factors), because scaling becomes translation in log r. With *linearly spaced* samples it is approximately so. The blur length in pixels is again proportional to r. COMPUTED (by definition of the coordinate change).
  - A depth-dependent defocus blur is LSI *within one depth layer*; layered DoF methods exploit this (3.1).
- **What the app should show for non-LSI blurs:** a PSF *field* (a grid of local PSFs drawn at their positions, like an optical spot diagram), a heat map of the local radius/length, and the local MTF at a probe pixel the user drags.

**Shared test images (procedural, per BRIEF).** The best image for each blur is listed in its section. In summary:

| Test image | What it reveals in this family |
|---|---|
| Impulse grid (isolated white dots on black) | The PSF itself, and in non-LSI blurs the PSF *field*: lines for motion, arcs for spin, rays for zoom, discs/hexagons for bokeh, cat's-eyes near corners |
| Night-city point lights (bright HDR dots) | Bokeh shape, edge brightness (soap-bubble vs smooth), chromatic fringing, highlight preservation (needs HDR / float input; in 8-bit the lights clip and bokeh looks dull) |
| Siemens star | Contrast inversion (phase reversal) in rings where the MTF goes negative (box, disc, line blurs); zeros in the MTF show as grey rings; rotation-direction dependence for motion blur |
| Zone plate (chirp, cos(k r^2)) | Plots the MTF directly as an image: each radius is one frequency, each angle one orientation. A linear motion blur shows dark lines perpendicular to the motion; a disc blur shows concentric dark rings (jinc zeros) |
| Step edge | Edge-spread function (ESF) = integral of the line-spread function; linear ramp for box/motion, S-curve for Gaussian, the "half-disc area" curve for a pillbox |
| Text / checkerboard | Readability and spurious resolution; checkerboard under a box/line blur can come back with *inverted* phase |

**Units used for "size".** These blurs have several incompatible size parameters. This file uses: L = length of a line PSF in pixels; R = radius of a disc/polygon in pixels; c = diameter of the circle of confusion (CoC); sigma = Gaussian standard deviation. Conversions: a box/line of length L has variance L^2/12 (continuous), so sigma_equiv = L/sqrt(12) ~= 0.2887 L. A uniform disc of radius R has per-axis variance R^2/4, so sigma_equiv = R/2. COMPUTED.


---

## 1. Directional family

### 1.1 linear-motion-blur

- **Name and aliases:** linear motion blur, directional blur, "Motion Blur" (Photoshop: Angle + Distance; Core Image `CIMotionBlur`: `inputAngle`, `inputRadius`), box blur along a line, camera-pan blur.
- **Family:** directional, LSI (when the same velocity applies to the whole image).

**Continuous definition.** A point moving at constant velocity v during an exposure of length T leaves a uniform line segment of length L = |v| T in direction theta. With unit direction d = (cos theta, sin theta):

    h(x) = (1/L) * integral_{-L/2}^{L/2} delta(x - s d) ds

i.e. h is a 1-D box of length L along d multiplied by a Dirac delta across d. The blurred image is g(x) = (1/L) integral_{-L/2}^{L/2} f(x - s d) ds. Centering on [-L/2, L/2] gives a zero-phase (symmetric) blur; a physically "trailing" blur uses [0, L] and is the same up to a shift of L/2 (which is a linear phase in the frequency domain, invisible in the MTF).

**Parameters and meaning.**
- L (length, pixels): distance travelled during the exposure. Photoshop calls it "Distance" (pixels). `CIMotionBlur.inputRadius` is documented only as "Radius" (default 20, attribute type distance) with `inputAngle` default 0 (REFERENCE: Apple Core Image Filter Reference). Whether Core Image's "radius" is half of L, all of L, or a Gaussian-like falloff is not documented: **INFERRED / UNVERIFIED**. The app should measure it live by blurring an impulse and reading the streak length and profile.
- theta (angle): direction of motion. Note the sign convention differs between y-up (Core Image, math) and y-down (UIKit, Photoshop screen space) systems; a 30 degree blur in one tool is -30 degrees in the other unless converted.
- Equivalent Gaussian sigma along d: L / sqrt(12) = 0.2887 L; zero blur across d. COMPUTED.

**Discrete kernel construction.**
1. *Axis-aligned (theta = 0 or 90 degrees):* an N-tap box, N = round(L) (prefer odd N for a centred kernel), weights 1/N. Exact.
2. *Arbitrary angle, "rasterised line" kernel:* draw an antialiased line of length L at angle theta into a small 2-D kernel (size ceil(L)+2 squared), using Wu's algorithm or by integrating the area each pixel covers of a 1-pixel-wide segment; normalise to sum 1. This is what MATLAB `fspecial('motion', len, theta)` does (it builds an antialiased line kernel). REFERENCE: MathWorks `fspecial` documentation (https://www.mathworks.com/help/images/ref/fspecial.html). The result is not exactly a line: rasterisation gives it a ~1 px width, so the MTF across d is not exactly 1.
3. *Arbitrary angle, "sampled along the line" (GPU style):* N taps at positions x + t_i d with t_i = L (i/(N-1) - 1/2), each fetched with bilinear filtering, weights 1/N. Bilinear fetches add a small, direction-dependent smoothing across d (maximum near 45 degrees where the bilinear footprint is widest). Sample spacing must be <= 1 px (N >= L+1) or the streak breaks into separate "ghost" copies (the classic "stepping"/banding artifact of under-sampled motion blur).
- **Normalisation:** sum of weights = 1 (energy preserving). **Truncation:** none needed, the kernel is compact. **Edges:** clamp-to-edge smears the border colour into a streak; mirror keeps statistics; zero (transparent) darkens/fades at the border. For a whole-image camera pan, clamp is the common default (Core Image extends images infinitely by clamping when you call `clampedToExtent()`; otherwise the output extent grows by the blur length and is transparent outside).

**Frequency response.** For the continuous line PSF:

    H(u, v) = sinc(L (u cos theta + v sin theta))    [sinc(x) = sin(pi x)/(pi x)]

- H depends only on the frequency component *along* d; frequencies perpendicular to d pass unchanged (H = 1). The MTF is a set of ridges: it is constant along lines perpendicular to d.
- **Zero lines:** H = 0 on the parallel lines u cos theta + v sin theta = k / L, k = +-1, +-2, ... Any sinusoid whose wave vector projected on d is k/L cycles/px is erased completely. In the 2-D spectrum of a motion-blurred photo these show as dark parallel stripes perpendicular to the motion, which is how blind deblurring methods estimate L and theta (REFERENCE: e.g. Cannon 1976, "Blind deconvolution of spatially invariant image blurs with phase", IEEE TASSP 24(1); the stripe method is textbook, UNVERIFIED for the exact first paper).
- **Negative lobes (contrast inversion):** first negative lobe minimum -0.2172 at L u_d = 1.4303; second positive lobe +0.1284 at L u_d = 2.459. 50% MTF at L u_d = 0.6034. COMPUTED (probe1.py). A Siemens star blurred horizontally shows grey rings (zeros) and phase-reversed bands only in the sectors whose stripes run across the motion; sectors whose stripes run *along* the motion stay sharp.
- **Discrete N-tap box:** H(u) = sin(pi N u)/(N sin(pi u)) (Dirichlet kernel). First zero at 1/N cycles/px; min -0.2500 (N=5), -0.2266 (N=9), -0.2201 (N=16); H at Nyquist = sin(pi N/2)/N (0 for even N; -1/3 for N=3, +1/5 for N=5), so a 3-tap box *inverts* a 1-px checkerboard (or 1-px stripes across the motion) at one-third contrast. COMPUTED (probe1.py).

**Key properties.** Linear: yes. Shift-invariant: yes (single velocity). Separable: only for theta = 0 or 90 degrees (it is then 1-D); at other angles it is a 1-D operator along a rotated axis, not a product of x and y kernels. Isotropic: no (maximally anisotropic: rank-1 support). Semigroup: box lengths do not compose into a box (L1 box * L2 box = trapezoid), so no. Positive kernel: yes (but MTF has negative lobes). Edge-preserving: no; edges parallel to d are untouched, edges perpendicular to d become linear ramps of width L.

**Algorithms and complexity (per pixel).**
- Naive gather along d: O(L) taps. Simple and the usual GPU choice.
- Rotate-then-separable: rotate image by -theta, run a 1-D running-sum (sliding window) box along x at O(1) per pixel independent of L, rotate back. Two resampling steps cost ~2 bilinear interpolations and soften the image slightly.
- Sliding window along Bresenham lines: O(1) per pixel along digital lines in direction d (lines are "sheared" rows); exact up to the rasterisation of the line.
- Repeated doubling (Kawase-style for streaks, see 1.3): log2(L) passes of 2 taps (offsets 1, 2, 4, ... px along d) builds a box of length 2^k in k passes: 2 log2 L fetches per pixel. COMPUTED: a box of 2^k equals the convolution of k two-tap kernels with spacings 1, 2, ..., 2^(k-1).
- FFT: O(log N) per pixel for very long blurs; exact only with periodic boundaries.
- SAT along a direction: build a 1-D prefix sum along sheared lines; O(1) per pixel; precision issues for long lines in fp16.

**GPU implementation.** One fragment/compute pass; N = ceil(L)+1 bilinear taps along d (for L = 40 px: ~41 fetches). Bilinear-pairing trick (sample between two texels with combined weight) works only for axis-aligned directions; at arbitrary angle each tap already blends 4 texels. Threadgroup tiling helps only for axis-aligned directions (load a row segment of width tile+L into threadgroup memory). For long blurs: downsample by 2^k, blur with L/2^k taps, upsample; acceptable because the result is smooth along d (but it also blurs across d by the downsample factor, so mixed-resolution artifacts appear on edges parallel to d).

**Visual fingerprint.**
- Unique vs neighbours: blur in exactly one direction; edges parallel to the motion stay razor sharp. A box (not Gaussian) profile gives *hard-ended* streaks: a bright point becomes a uniform line with crisp ends (Gaussian-directional blur gives soft tapering ends; exponential "streak" filters give a comet tail).
- Artifacts: ghost copies when undersampled (N < L); phase-inverted stripes on fine periodic texture moving across its stripes; dark halo on a bright moving object when clamped edges are dark.
- Best test images: impulse grid (shows the line PSF and its hard ends); Siemens star (direction-dependent rings: grey zero rings and inverted bands only in sectors across the motion); zone plate (dark straight stripes perpendicular to motion at spacing 1/L in the frequency plane); text (letters smear into horizontal strokes but horizontal strokes stay readable when the motion is horizontal).

**Where used.** Photoshop Filter > Blur > Motion Blur (Angle, Distance) (REFERENCE: Adobe Photoshop User Guide, "Blur filters", https://helpx.adobe.com/photoshop/using/blur-filters.html, UNVERIFIED exact URL path); Core Image `CIMotionBlur` (macOS 10.4+, iOS 9+; REFERENCE: Apple Core Image Filter Reference archive); GIMP "Motion Blur" (linear/radial/zoom modes; REFERENCE: GIMP docs "Motion Blur"); MATLAB `fspecial('motion')`; game camera-pan blur before per-pixel velocity buffers (e.g. "camera motion blur" using the previous view-projection matrix, Rosado 2008 GPU Gems 3 ch. 27 "Motion Blur as a Post-Processing Effect").

**Signature:** "A box along one direction: points become hard-ended lines, and every frequency whose stripes cross the motion at k/L cycles per pixel is erased."

### 1.2 anisotropic-gaussian

- **Name and aliases:** directional Gaussian, elliptical Gaussian, oriented Gaussian, "anisotropic Gaussian blur".
- **Family:** directional, LSI.

**Continuous definition.** h(x) = (1/(2 pi sqrt(det S))) exp(-x^T S^{-1} x / 2), S = R(theta) diag(sigma_u^2, sigma_v^2) R(theta)^T. The degenerate case sigma_v = 0 is a 1-D Gaussian along d (a "Gaussian motion blur").

**Parameters.** sigma_u (along d), sigma_v (across d), theta. A linear motion blur of length L has the same variance as sigma_u = L/sqrt(12); the elliptical Gaussian is the smooth "soft-ended" relative of 1.1.

**Discrete kernel.** Sample the 2-D formula on a grid of radius ~3 sigma_u, normalise to 1. Truncation at 3 sigma loses 0.27% of the mass per axis (COMPUTED: 1 - erf(3/sqrt 2)).

**Frequency response.** H(w) = exp(-2 pi^2 w^T S w): another (rotated) Gaussian, sigma_freq = 1/(2 pi sigma) per principal axis. Never zero, never negative: no contrast inversion. COMPUTED.

**Properties.** Linear, shift-invariant, positive, semigroup (variances add as matrices: S1 + S2), not isotropic. Separable in x and y only for theta = 0 or 90 degrees; at a general angle it factors into a 1-D Gaussian along x followed by a 1-D Gaussian along a *sheared* (non-orthogonal) direction (Geusebroek, Smeulders and van de Weijer 2003, "Fast anisotropic Gauss filtering", IEEE TIP 12(8)). REFERENCE.

**Algorithms.** Naive 2-D: O(sigma_u sigma_v). Geusebroek sheared separable: two 1-D passes, O(sigma) each, or O(1) each with recursive IIR Gaussians (Young-van Vliet). GPU: two passes, the second along a sheared line with bilinear taps.

**Fingerprint.** Like 1.1 but streak ends taper smoothly, no zero lines in the spectrum, no inversion on the Siemens star (just monotone loss of contrast in the across-motion sectors). Best test: Siemens star or zone plate side-by-side with 1.1 at equal variance.

**Where used.** Anisotropic texture filtering footprints (EWA, Heckbert 1989 "Fundamentals of texture mapping and image warping"), edge-tangent flows (line integral convolution, Cabral and Leedom 1993), some "motion blur" filters in apps are Gaussian-weighted rather than box-weighted (UNVERIFIED for any specific product).

**Signature:** "Motion blur with soft ends: an elliptical Gaussian whose spectrum is another ellipse, never zero, never inverted."

### 1.3 kawase-streak (star filter, light streaks)

- **Name and aliases:** light streaks, star filter, cross filter, glare streaks, "Kawase streak". Family: directional, LSI per direction, usually applied only to the bright-pass (thresholded) image and added back (so the full effect is non-linear because of the threshold).
- **Continuous definition.** One streak direction d: h(x) = (1/Z) * integral_0^inf a^t delta(x - t d) dt: a one-sided exponentially decaying line ("comet tail"), with a in (0, 1) the per-pixel attenuation. A star with K arms is the sum of K such streaks at angles theta_0 + 2 pi j / K (K = 4 "cross", 6 or 8 "star"), each normalised and scaled by an intensity.
- **Parameters.** Number of arms K, arm angle offset theta_0, decay a (or a length 1/ln(1/a) in px), intensity per arm, often a per-pass colour shift to mimic chromatic dispersion in real star-filter glass.
- **Discrete construction (the iterated trick).** Pass p (p = 0, 1, ..., n-1) samples 4 taps at offsets 4^p * s * d, s = 0..3, with weights a^(4^p s). Because every integer t in [0, 4^n - 1] has a unique base-4 expansion t = sum s_p 4^p, the product of the n per-pass kernels is *exactly* the truncated geometric series sum_{t=0}^{4^n - 1} a^t delta(x - t d). COMPUTED (probe4.py: max error 1e-16 for n = 2..4). Cost: 4n fetches per pixel per arm for a 4^n-pixel streak (n = 3: 12 fetches for 64 px, vs 64 direct). This is the same doubling idea as the Kawase blur, applied along a line. Sources: Kawase, M., "Frame Buffer Postprocessing Effects in DOUBLE-S.T.E.A.L (Wreckless)", GDC 2003 (REFERENCE for the technique's origin; I could not retrieve the slides, so the exact constants, e.g. 4 taps per pass and a ~ 0.9 to 0.95, are **UNVERIFIED** and come from common re-implementations such as the DirectX 9 SDK "HDRLighting" sample's star/glare definitions, also UNVERIFIED).
- **Frequency response.** For one arm: H(w) = (1 - a) / (1 - a e^{-i 2 pi w.d}) (one-sided exponential = first-order IIR low-pass along d; truncation at 4^n adds a small ripple). |H| never reaches zero, phase is non-zero (the streak is one-sided so it shifts energy in the d direction). COMPUTED (discrete-time Fourier transform of a geometric sequence). Perpendicular frequencies pass unchanged.
- **Properties.** Linear per arm, shift-invariant, positive, *not* symmetric (one-sided unless both directions are drawn), not separable, not isotropic. Applied to a thresholded bright-pass the overall effect is non-linear (only highlights streak).
- **GPU.** Bright-pass + downsample (1/4 res is typical), n passes per arm, ping-pong render targets, add arms together, upsample and add to the scene. Fetches: K arms x 4n at reduced resolution.
- **Fingerprint.** Thin bright rays from highlights only, brightest at the source and decaying exponentially, with fixed angles regardless of where the light is (unlike diffraction spikes from a real aperture, which also have fixed angles but a 1/r^2 profile and colour fringing, see 2.7). Best test: night-city point lights on black.
- **Where used.** HDR "glare" in games since the early 2000s (Wreckless 2002), YEBIS middleware (Kawase is its architect, Silicon Studio), star filters in photo apps (e.g. Photoshop has no built-in star filter; UNVERIFIED for others). Physical analogue: cross-screen/star filters (etched glass) on camera lenses.
- **Signature:** "Highlights grow comet-tail rays at fixed angles; a 64-pixel exponential streak costs only 12 taps because base-4 digits tile the line exactly."

### 1.4 camera-shake-blur

- **Name and aliases:** handshake blur, camera shake, jitter blur, blind motion blur kernel. Family: directional (trajectory), LSI only in the translation-only approximation; spatially varying in reality.
- **Continuous definition (translation-only model).** The camera image-plane displacement during the exposure follows a path p(t), t in [0, T]. With shutter weight w(t) (box for a normal shutter), the PSF is the time-weighted occupancy of the path:

      h(x) = (1/W) integral_0^T w(t) delta(x - p(t)) dt,   W = integral w

  So h is a thin curve whose brightness is proportional to dwell time: slow parts of the path (where the hand reverses direction) are bright, fast parts are faint. This is the classic look of real shake kernels (Fergus, Singh, Hertzmann, Roweis and Freeman 2006, "Removing camera shake from a single photograph", ACM TOG 25(3), SIGGRAPH 2006; REFERENCE).
- **Spatially varying model.** Real shake includes rotation about the optical axis (roll) and about the x/y axes; with focal length f the image motion is a homography per instant, so the PSF changes across the frame: roll produces small arcs that grow with distance from the centre (a spin blur, 1.9, superimposed on the translation). Whyte, Sivic, Zisserman and Ponce 2010/2012, "Non-uniform deblurring for shaken images" (CVPR 2010; IJCV 98(2) 2012) model this as a weighted sum of rotated copies of the sharp image (REFERENCE). Depth parallax adds another variation (near objects shake more for translation, not for rotation).
- **Parameters.** Path generator: e.g. a random walk with momentum, an Ornstein-Uhlenbeck process, or a sum of a few low-frequency sinusoids (physiological hand tremor is commonly quoted as ~8 to 12 Hz; UNVERIFIED as a precise figure); amplitude in pixels; exposure time; focal length (longer lens magnifies angular shake). Boracchi and Foi 2012, "Modeling the performance of image restoration from motion blur", IEEE TIP 21(8), give a widely used random-trajectory generator for synthetic shake (REFERENCE; details of their generator UNVERIFIED here). Folk rule: hand-held shutter time <= 1/(35 mm-equivalent focal length) seconds (UNVERIFIED, folklore).
- **Discrete construction.** Supersample the path (e.g. 4 to 16 sub-steps per pixel of travel), splat each point bilinearly into a kernel grid, normalise to 1. Kernel sizes in deblurring benchmarks are typically 13 to 30+ px (Levin, Weiss, Durand and Freeman 2009, "Understanding and evaluating blind deconvolution algorithms", CVPR 2009, released 8 recorded kernels; the size range is UNVERIFIED here).
- **Frequency response.** H(w) = (1/W) integral w(t) e^{-i 2 pi w.p(t)} dt. No closed form; generically complex (non-zero phase, because the kernel is asymmetric), with irregular near-zeros. Because the path folds back on itself, |H| tends to have *fewer exact zeros* than a straight box, but strong attenuation along the dominant direction of motion. COMPUTED (general property of the Fourier transform of a curve measure; specific spectra must be computed per kernel).
- **Properties.** Linear; shift-invariant only under the translation model; positive kernel; asymmetric (so it also *shifts* edges, and a centred-vs-not choice matters); not separable, not isotropic, no semigroup.
- **Algorithms.** Arbitrary 2-D kernel: direct O(K^2) per pixel or FFT O(log N). On a GPU, sparse sampling of the kernel's non-zero texels is efficient: only ~K to 3K of the K^2 texels are non-zero, so gather only those (store them as an offset/weight list). For the spatially varying model, the Whyte et al. formulation g = sum_j w_j (f warped by homography H_j) maps directly to the GPU: J warped bilinear fetches per pixel.
- **Fingerprint.** Unique: a *curved, uneven-brightness* PSF. Point lights become squiggles with bright knots, all identical across the frame (translation) or slowly rotating/scaling across the frame (with roll). Double images ("ghosting") when the hand pauses at two places. Best test: night-city point lights (the squiggle is directly visible); text shows doubled strokes.
- **Where used.** Synthetic data for deblurring research and training (GoPro dataset uses frame averaging instead, see 1.7); Photoshop "Shake Reduction" (Filter > Sharpen) estimates such kernels (REFERENCE: Adobe Photoshop, introduced in Photoshop CC 2013; UNVERIFIED exact version); optical/sensor image stabilisation exists to cancel it.
- **Signature:** "A hand-drawn squiggle as the PSF: bright where the hand paused, faint where it moved fast, rotating across the frame when the camera rolls."

### 1.5 shutter-function-blur (box, trapezoid, rolling, coded/flutter)

- **Name and aliases:** shutter efficiency / temporal aperture, exposure profile, rolling-shutter skew (related), flutter shutter, coded exposure. Family: directional/temporal; it modifies the *weighting along* a motion path.
- **Continuous definition.** For motion p(t) and a temporal shutter function s(t) (how open the shutter is at time t), the PSF is h(x) = (1/S) integral s(t) delta(x - p(t)) dt. For constant velocity v: h is s(.) mapped along the line, i.e. a 1-D profile along d equal to s(t) with t = position / |v|.
  - **Box shutter** (ideal, instant open and close): box PSF; MTF sinc with exact zeros (1.1).
  - **Trapezoid** (finite open/close times, mechanical leaf or focal-plane shutters; also the typical "shutter efficiency" curve): box convolved with a short box; MTF = product of two sincs; zeros of both remain. COMPUTED.
  - **Gaussian / smooth window** (renderers' "shutter curve", e.g. a cosine or Gaussian ramp): soft-ended streaks, no zeros (like 1.2).
  - **Coded / fluttered shutter:** the shutter opens and closes in a pseudo-random binary pattern during the exposure. The PSF is a binary "barcode" along the motion. Raskar, Agrawal and Tumblin 2006, "Coded exposure photography: motion deblurring using fluttered shutter" (ACM TOG 25(3), SIGGRAPH 2006; MERL TR2006-124) chose codes whose spectrum has no zeros, which makes deconvolution well-posed (REFERENCE). Probe: for a 52-chip exposure, the box has exact zeros (min MTF 0) while the best of ~20,000 random 26-of-52 codes reached min |H| = 0.036 over [0, 0.5] cycles/px (seed 1; an earlier run with another seed gave 0.026), at half the light. COMPUTED (probe4.py; the paper's own published code is not reproduced here).
  - **Rolling shutter** (CMOS, row-sequential readout) is not a blur but a *time skew*: row y is exposed at t0 + y * t_row, so vertical lines lean during horizontal pans, and propellers bend. Combined with exposure time it shears the motion PSF field. Mention for completeness; it is a geometric warp, not a blur.
- **Parameters.** s(t) shape, exposure time T, velocity; for coded exposure, the code length and duty cycle. Renderers expose "shutter angle" (film convention: 180 degrees = exposure of half the frame interval; T = (angle/360) / fps). REFERENCE: standard cinematography convention; e.g. Blender's "Shutter" (in frames) and "Shutter Curve" settings (Blender manual, Render > Motion Blur; UNVERIFIED exact wording).
- **Frequency response.** With constant velocity v (px per unit time) and the shutter profile normalised to unit area: H(w) = integral s(t) e^{-i 2 pi (w.v) t} dt / S = S_hat(w.v), i.e. the 1-D Fourier transform of the shutter profile in time, evaluated at the temporal frequency w.v that a spatial frequency w produces when it moves at v. Box -> sinc zeros; trapezoid -> product of sincs; Gaussian -> Gaussian; coded -> broadband, no zeros.
- **Fingerprint.** On a moving point light: box -> uniform line with hard ends; trapezoid -> line with ramped ends; Gaussian -> soft comet with symmetric fade; coded -> dashed line (visible "Morse code"). Best test: a moving point light on black, then the zone plate to show zeros vs broadband.
- **Where used.** Offline renderers (Blender Cycles shutter curve; RenderMan shutter opening controls, UNVERIFIED names), game engines (a "shutter angle" or "exposure fraction" scales the velocity buffer in 1.6), computational photography (flutter shutter cameras).
- **Signature:** "The PSF along a motion is the shutter's opening curve drawn in space: a box shutter leaves spectral zeros, a coded shutter leaves a barcode and none."

### 1.6 velocity-buffer-motion-blur (McGuire et al. 2012 reconstruction filter)

- **Name and aliases:** per-pixel motion blur, object motion blur, velocity-buffer blur, "reconstruction filter for plausible motion blur", tile-based motion blur. Family: directional, **linear but spatially varying** (every pixel has its own velocity, so its own line PSF), and *not even strictly linear* in practice because the per-sample weights depend on depth and velocity buffers (they are linear in colour C, but chosen non-linearly from Z and V).
- **Source (verified, primary):** McGuire, Hennessy, Bukowski and Osman, "A Reconstruction Filter for Plausible Motion Blur", ACM SIGGRAPH Symposium on Interactive 3D Graphics and Games (I3D) 2012, pp. 135-142. PDF: https://casual-effects.com/research/McGuire2012Blur/McGuire12Blur.pdf (read in full for this section; text extracted into the probe dir). Deployed in a production engine at Vicarious Visions (paper abstract).

**Continuous definition (what is being approximated).** A real exposure integrates the moving scene: g(x) = (1/T) integral_0^T f_t(x) dt, where f_t is the instantaneous image at time t. If each scene point moves with its own constant screen velocity, then in a *scatter* reading every source point Y spreads into a line segment of length 2|v_Y| centred on Y along v_Y, and occluders in front hide what is behind (depth order matters). This is a linear shift-variant operator with occlusion; no single PSF or MTF exists. The local PSF at a pixel is the line segment of *that pixel's* velocity (gather) or of *the points passing over it* (scatter); the paper's whole point is that these differ at silhouettes.

**Inputs (paper, section 2.2).** Colour C (HDR, RGB16F, before tone mapping), screen-space velocity V and linear camera-space depth Z (R16F). The stored velocity is the *half* velocity, clamped:

    q_X = (1/2) (X - X') * (exposure time) * (frame rate)
    V[X] = q_X * max(0.5 px, min(|q_X|, k)) / (|q_X| + epsilon)

where X' is the point's position in the previous frame. So a pixel blurs over X +- V[X]; a 180-degree shutter (exposure = half a frame) halves the streak. (REFERENCE, paper eq. in sec. 2.2.) V is stored biased/scaled in RG8.

**Passes (paper section 2.3, listing 1).**
1. *TileMax* (w/k x h/k): for each k x k tile, keep the velocity with the largest magnitude ("vmax", a vector argmax by length, not a per-component max).
2. *NeighborMax* (w/k x h/k): vmax over the 3 x 3 neighbouring tiles. Because |V| <= k, this guarantees each pixel knows the fastest thing that can reach it, under the "one dominant velocity per neighbourhood" assumption.
3. *Reconstruction* at full resolution: gather S taps along the neighbourhood's dominant velocity v_N:
   - if |v_N| <= epsilon + 0.5 px, return C[X] (no blur);
   - centre weight 1/|V[X]|;
   - for i in [0, S), i != (S-1)/2: t = mix(-1, 1, (i + j + 1)/(S + 1)) with one random jitter j in [-0.5, 0.5] per pixel; Y = round(X + v_N t);
   - f = softDepthCompare(Z[X], Z[Y]), b = softDepthCompare(Z[Y], Z[X]);
   - alpha_Y = f * cone(Y, X, V[Y])  [case 1: blurry Y in front of X]  + b * cone(X, Y, V[X])  [case 2: anything behind a blurry X, used to estimate the hidden background]  + cylinder(Y, X, V[Y]) * cylinder(X, Y, V[X]) * 2  [case 3: both blurry];
   - result = sum alpha_Y C[Y] / sum alpha_Y.
   - cone(X, Y, v) = clamp(1 - |X - Y| / |v|, 0, 1); cylinder(X, Y, v) = 1 - smoothstep(0.95 |v|, 1.05 |v|, |X - Y|); softDepthCompare(za, zb) = clamp(1 - (za - zb)/SOFT_Z_EXTENT, 0, 1), SOFT_Z_EXTENT = 1 mm to 10 cm in their scenes. (REFERENCE, paper listing 1 and fig. 4.)

**Parameters and meaning.** k = maximum blur radius in pixels and also the tile size (paper default k = 20 at 1280 x 720; "large values (e.g. 40 pixels) may adversely affect texture cache performance"). S = odd tap count (default 15; "S = 5 is sufficient for consoles", S = 15 visibly better on desktop monitors at nearly the same cost). Exposure fraction (shutter angle / 360) scales V. SOFT_Z_EXTENT sets how sharply foreground/background are separated. Equivalent Gaussian sigma for a pixel with half-velocity |V|: the full streak is 2|V| long, so sigma_eq = 2|V|/sqrt(12) = 0.577 |V| along V. COMPUTED.

**Discrete kernel.** Per pixel, a 1-D set of S taps along v_N (not along the pixel's own V), with *data-dependent* weights alpha_Y; normalised by the weight sum. The cone weight makes each moving point's contribution a *triangle* along its path in the gather reading, which is why the result is a smooth streak rather than a hard box. Edges: taps are rounded to integer pixels (no bilinear filtering, to keep V/Z lookups exact); off-screen taps are clamped.

**Frequency response.** None globally (LSV, data-dependent). Locally, in the interior of a uniformly moving region where all V are equal and all cases reduce to cylinder*cylinder plus cones, the gather is a jittered S-tap average along V, approximately a box of length 2|V| (MTF ~ sinc(2|V| u_d) with the zero lines of 1.1), plus noise from the jitter. COMPUTED by reduction to 1.1; the exact local profile depends on the cone/cylinder mix and is best measured in-app with an impulse inside a moving region.

**Key properties.** Linear in C for fixed V and Z; shift-variant; positive weights; anisotropic per pixel; not separable; not semigroup; *occlusion-aware* (the defining property): a sharp object in front of a blurry background stays sharp, and a moving object's blur extends *beyond its own silhouette* over the static background (the "dilation" that earlier per-pixel methods lacked).

**Algorithms and complexity.** Scatter (draw a line per pixel, depth-sort) is O(k n) but needs ordering/synchronisation. Conservative gather over a disc of radius k is O(k^2 n). The paper's tile trick makes it O(k n / m) on an m-way parallel machine: per output pixel, S taps (each reading C, V, Z: 3 fetches) plus O(1) for the tiles. Measured in the paper: 3 ms at 1280 x 720 on a GeForce 480 (k = 20, S = 15, full-screen camera motion); 6.2 ms at k = 31, 3.0 ms at k = 15, 2.8 ms at k = 7, 2.7 ms at k = 5; Xbox 360: 1.5 ms at k = 5. All data buffers total 15 MB at 720p. (REFERENCE.)

**GPU implementation.** Three compute (or fragment) passes. TileMax: one thread per tile, k^2 velocity reads (often split into a k x 1 then 1 x k pass, or done with threadgroup reductions). NeighborMax: 9 tile reads per tile. Reconstruction: per pixel ~3S + 4 fetches (S = 15: ~49). Jitter j from a per-pixel hash or blue noise; TAA downstream hides the noise. Velocity is written in the main geometry pass from current and previous model-view-projection matrices (camera-only motion blur can derive V from depth plus the previous view-projection matrix: Rosado, "Motion Blur as a Post-Processing Effect", GPU Gems 3 ch. 27, 2007; REFERENCE via the paper's bibliography).

**Known failure modes (paper's own results section).** Under-blur when a tile contains two different motions (interlocking gears rotating opposite ways: the big background gear dominates NeighborMax and suppresses the spoke velocity); sample noise at low S; "blurring in the wrong direction" because case 1 assumes V[Y] is along v_N. Follow-ups: Guertin, McGuire and Nowrouzezahrai 2014, "A Fast and Stable Feature-Aware Motion Blur Filter" (HPG 2014; https://research.nvidia.com/publication/2013-11_fast-and-stable-feature-aware-motion-blur-filter) address overlapping motions and fine features; Jimenez 2014 (SIGGRAPH Advances, "Next Generation Post Processing in Call of Duty: Advanced Warfare") is a widely cited production variant (UNVERIFIED details).

**Visual fingerprint.** Unique vs 1.1: blur direction and length change per object, the background behind a moving object stays sharp, moving silhouettes become semi-transparent and extend past their outline, static objects in front of moving ones keep crisp edges. Characteristic artifacts: tile-sized blocks of wrong blur where motions conflict, grainy streaks at low S, halo of "smeared background" at silhouettes when the hidden background is guessed (case 2). Best test: a synthetic scene with a fast-moving disc in front of a static checkerboard, plus a static bar in front of a moving one (needs a velocity and depth buffer, so the app must provide procedural V and Z alongside the image). Impulse grid with a vortex velocity field shows the PSF *field*.

**Where used.** Vicarious Visions engine (paper); G3D Innovation Engine (`G3D::MotionBlur`, https://casual-effects.com/g3d/G3D10/build/manual/class_g3_d_1_1_motion_blur.html); NVIDIA GameWorks "Motion Blur Advanced" samples (OpenGL/GLES and D3D; suggested K ~ 20, S ~ 15; https://archive.docs.nvidia.com/gameworks/content/gameworkslibrary/graphicssamples/opengl_samples/motionblurgl4gles3advancedsample.htm); Unity post-processing stack v2 and Unreal Engine both ship tile-based velocity motion blur (descended from this family; exact lineage UNVERIFIED).

**Signature:** "Every pixel carries its own velocity; tiles find the fastest neighbour, then a depth-aware line gather lets moving things smear over a background that stays sharp."

### 1.7 temporal-accumulation (frame blending, accumulation buffer, long exposure, EMA trails)

- **Name and aliases:** accumulation-buffer motion blur, frame averaging, frame blending, long exposure, temporal supersampling of motion, "Long Exposure" Live Photo effect, ghost trails, exponential moving average (EMA) feedback blur. Family: temporal; the spatial blur is an *emergent* consequence of averaging images over time. Linear in the frames; shift-variant in space (each pixel's blur follows whatever moved through it).

**Continuous definition.** g(x) = integral s(t) f_t(x) dt / integral s(t) dt with shutter weight s(t) (1.5). This is the *ground truth* that 1.1, 1.4, 1.5 and 1.6 approximate: it handles occlusion, rotation, deformation, shading changes and transparency correctly because each sub-frame is a fully rendered image. Two discrete forms:
- **Box (finite window) average:** g = (1/N) sum_{i=0}^{N-1} f_{t_i}, sub-frames t_i evenly spaced (or jittered) over the exposure. Haeberli and Akeley, "The Accumulation Buffer: Hardware Support for High-Quality Rendering", SIGGRAPH 1990 (Computer Graphics 24(4)) is the classic source: render N jittered sub-frames (in time for motion blur, in lens position for depth of field, in sub-pixel offset for antialiasing) and sum them in a high-precision buffer (REFERENCE; standard citation, paper not re-read for this file).
- **Recursive (EMA / feedback):** g_n = alpha f_n + (1 - alpha) g_{n-1}. The effective temporal weight is geometric: w_i = alpha (1 - alpha)^i, an infinitely long *one-sided exponential* shutter. A moving point leaves an exponentially fading comet trail behind it (the trail points backwards along the motion). Mean age = (1 - alpha)/alpha frames; e.g. alpha = 0.1 gives a 9-frame mean lag. COMPUTED (geometric series).

**Parameters.** N sub-frames (or alpha), exposure time / shutter angle, sub-frame time distribution (uniform, jittered, or importance-sampled from s(t)), and for photos the capture frame rate.

**Discrete construction and the sampling condition.** If an object moves d pixels between sub-frames and d > ~1 px, the average shows N distinct *ghost copies* ("strobing", "stepping") instead of a continuous streak. To avoid it: N >= (streak length in px) + 1, or jitter sub-frame times per pixel (trading ghosts for noise), or combine with a small per-sub-frame velocity blur (1.6) of length d to fill the gaps. COMPUTED (same sampling condition as the tap spacing in 1.1).

**Frequency response.** In space-time, averaging over a window of length T is a temporal box: H(omega_t) = sinc(T omega_t). For a pattern translating at velocity v, omega_t = w.v, which reproduces the spatial sinc of 1.1/1.5 for that region only. Each region gets the MTF of its own motion; static regions get H = 1 (stay perfectly sharp, which is a defining difference from any spatial blur). With N discrete sub-frames, the temporal response is the Dirichlet kernel sin(pi N d u)/(N sin(pi d u)) for spatial frequency u along the motion and per-sub-frame displacement d, which has *aliases* (returns to 1) at u = k/d: fine texture moving fast can reappear unblurred (the "wagon-wheel" family of artifacts). COMPUTED.

**Key properties.** Linear in the frame sequence; exact for occlusion; static parts untouched; cost scales with N full renders (or N captured frames); the EMA version is O(1) memory and time per pixel but its trail is one-sided and never fully ends (8-bit buffers end it by quantisation, often leaving faint "stuck" residue unless dithered; COMPUTED: with alpha = 0.1, a difference smaller than ~5 levels cannot decay further in 8-bit because 0.1 * 5 rounds to 0.5).

**Algorithms and GPU.** Render or capture N frames; accumulate in an RGBA16F/32F texture with additive blending or a compute kernel (1 read + 1 write per pixel per sub-frame), divide by N at the end. EMA: one full-screen pass per frame reading the history texture (1 extra fetch). Temporal antialiasing (TAA) uses EMA with *reprojection* (history fetched at x - v) plus neighbourhood colour clamping, precisely to *avoid* this blur (Karis 2014, "High Quality Temporal Supersampling", SIGGRAPH Advances course; REFERENCE, details UNVERIFIED here). Real-world datasets: the GoPro deblurring dataset synthesises motion blur by averaging consecutive frames of 240 fps video (Nah, Kim and Lee 2017, "Deep Multi-scale Convolutional Neural Network for Dynamic Scene Deblurring", CVPR 2017; the 7-13 frame count is from memory, UNVERIFIED).

**Visual fingerprint.** Unique: the *only* method in this family that gets occlusion, rotation and lighting change exactly right, and the only one that leaves static parts pixel-identical. Artifacts: discrete ghost copies when N is too small (a fan blade becomes 8 translucent blades); for EMA, one-sided fading trails and "smearing" of anything that changes. Best test: a rotating Siemens star or spinning bar rendered as N sub-frames (shows ghosts at low N and converges to the true rotational blur 1.9 at high N); a moving point light (box average -> uniform line; EMA -> exponential comet).

**Where used.** Offline renderers' reference motion blur; Apple Photos "Long Exposure" effect for Live Photos (introduced iOS 11, blends the Live Photo's frames; REFERENCE: Apple iOS 11 feature pages, exact implementation INFERRED); After Effects "Pixel Motion Blur"/frame blending and Premiere "Frame Blending" (UNVERIFIED names); GoPro dataset (above); "trails"/"echo" video effects; light painting.

**Signature:** "The ground truth everything else fakes: average real frames over the exposure. Static things stay sharp, moving things smear exactly right, and too few frames turn a streak into ghosts."

### 1.8 radial-zoom-blur

- **Name and aliases:** zoom blur, radial blur (Photoshop "Radial Blur > Zoom"), "zoom burst" (the in-camera trick of zooming during the exposure), crash zoom, warp-speed blur; light-shaft / god-ray blur is the same sampling with an exponential decay. Family: directional, **linear shift-variant** (LSI only after a log-polar change of coordinates).

**Continuous definition.** Centre c, strength a in [0, 1). Each output pixel averages the input along the ray towards c:

    g(x) = (1/a) integral_0^a f(c + (1 - s)(x - c)) ds          (linear-in-scale form)

i.e. the average of the image scaled about c by factors from 1 down to (1 - a). The *zoom-burst* photograph (focal length changing during the exposure) is exactly this with s weighted by the shutter function. A variant samples *outwards* (scales > 1) or symmetrically. The local PSF at x is a radial line segment from x towards c of length L(x) = a |x - c|: zero at the centre, growing linearly with distance. COMPUTED.

**Coordinate trick.** In log-polar coordinates (rho = ln |x - c|, theta), scaling by (1 - s) is a translation of rho by ln(1 - s). With geometrically spaced scale factors (or after re-weighting the integral by 1/(1 - s)), zoom blur is an exact 1-D box along rho, the same for every theta: an LSI blur on the log-polar image. COMPUTED.

**Parameters.** Centre c (Core Image `inputCenter`, default [150 150]; Photoshop drags the centre in a preview square); strength: Core Image `CIZoomBlur.inputAmount` (attribute type *distance*, default 20; REFERENCE: Core Image Filter Reference) whose exact mapping to a or to a pixel length is not documented, so it is **INFERRED** and should be measured in-app with an impulse grid (streak length versus distance from centre: a constant length would mean "pixels", a linear growth would mean "scale fraction"); Photoshop Radial Blur: Amount 1-100, Method Spin/Zoom, Quality Draft/Good/Best (REFERENCE: Adobe Photoshop help "Blur filters"; the mapping of Amount to a and what "Quality" changes are UNVERIFIED; Draft is visibly grainy, which suggests fewer and/or jittered samples). Equivalent Gaussian sigma along the ray at distance r: a r / sqrt(12). COMPUTED.

**Discrete construction.** N taps at scales s_i = 1 - a i/(N - 1), bilinear fetches, weights 1/N (or decaying weights for light shafts). Sampling condition: the spacing between consecutive taps at the farthest pixel, a r_max / (N - 1), must be <= ~1 px, so N >= a r_max + 1. For a 1170 x 2532 portrait image with the centre in the middle, r_max = 1395 px (the corners), so a = 0.2 needs ~280 taps for ghost-free corners. COMPUTED. Real filters therefore (i) accept banding/ghosting near corners, (ii) jitter the start offset per pixel (noise instead of bands), (iii) use the doubling trick (below), or (iv) downsample.

**Frequency response.** Not LSI: no global MTF. Local MTF at radius r: H(w) = sinc(a r (w . e_r)) with e_r the radial unit vector: zero *lines* perpendicular to the ray at spacing 1/(a r) cycles/px, i.e. the local zero spacing shrinks with distance (centre: no blur; edges: strong blur). In log-polar coordinates it is a true sinc along rho. COMPUTED.

**Key properties.** Linear, shift-variant (but rotation-equivariant about c and scale-equivariant about c), positive weights, not separable in x/y, not isotropic, no semigroup in the linear-scale form (geometric-scale form: boxes in log r compose to trapezoids, so no). Exactly preserves anything that is *scale-invariant about c*: **a Siemens star centred at c passes through zoom blur unchanged** (its spokes are rays), while concentric rings are destroyed. COMPUTED (scale invariance; exact in the continuous limit, discrete only up to bilinear resampling).

**Algorithms and complexity.**
- Naive gather: N taps per pixel, N ~ a r_max (hundreds) for strong zooms.
- Doubling (iterated rescale-and-average): pass p averages the image with a copy of itself scaled by s^(2^p) about c; after k passes the result is the average of 2^k geometrically spaced scales. Cost 2k bilinear fetches per pixel for 2^k samples (k = 8: 16 fetches for 256 samples). COMPUTED (same base-2 digit argument as 1.1/1.3; exact for the geometric-spacing variant).
- Log-polar resample + 1-D sliding-window box along rho + inverse resample: O(1) per pixel in the blur length, but two resampling steps blur the image slightly and the log-polar grid undersamples the periphery or oversamples the centre.
- Downsample-blur-upsample: acceptable because the result is smooth along rays, but loses detail across rays near the centre.

**GPU implementation.** One full-screen pass with N bilinear fetches along (c - x), or k ping-pong passes of 2 fetches each (doubling). Light-shaft variant (Mitchell, "Volumetric Light Scattering as a Post-Process", GPU Gems 3 ch. 13, 2007; REFERENCE, standard): render occluders black over a bright light at low resolution, then for each pixel march NUM_SAMPLES steps towards the light's screen position, accumulating sample * illuminationDecay * weight with illuminationDecay *= decay each step, then scale by exposure. The exponential decay makes it a radial version of 1.3's comet tail.

**Visual fingerprint.** Unique: streaks all point at one centre, length grows with distance, the centre stays perfectly sharp; a centred Siemens star is untouched while a centred zone plate's rings smear (the exact dual of spin blur). Artifacts: concentric *banding rings* or ghost copies near the edges when N is too small (the corners need the most taps); noise with jitter. Best test: impulse grid (rays of growing length), centred Siemens star versus centred zone plate (duality with 1.9), text (letters near the edge stretch radially).

**Where used.** Core Image `CIZoomBlur` (OS X 10.4+, iOS 9+); Photoshop Radial Blur (Zoom); GIMP Motion Blur (Zoom mode); game "speed" effects and crash zooms; god rays/light shafts (GPU Gems 3 ch. 13; Crysis-era sun shafts are commonly described the same way, UNVERIFIED).

**Signature:** "Everything streaks toward one point and the streak grows with distance: a box blur along rays, which in log-polar space is just an ordinary 1-D box."

### 1.9 spin-blur (rotational blur)

- **Name and aliases:** spin blur, rotational blur, radial blur (Photoshop "Radial Blur > Spin"), circular motion blur, angular blur; Photoshop Blur Gallery "Spin Blur" (elliptical, CC 2014). Family: directional, linear shift-variant (LSI in polar coordinates).

**Continuous definition.** Centre c, total angle Theta (radians):

    g(x) = (1/Theta) integral_{-Theta/2}^{Theta/2} f(c + R(phi)(x - c)) dphi

with R(phi) the rotation by phi. The local PSF at radius r = |x - c| is a circular *arc* of angle Theta and arc length L(r) = r Theta, curving around c. Near the centre the arc is shorter than a pixel (no visible blur); at r = 1000 px a 5 degree spin is an 87 px arc. COMPUTED.

**Coordinate trick.** In polar coordinates (r, theta), g(r, theta) = (1/Theta) integral f(r, theta - phi) dphi: a 1-D *circular* box convolution along theta, independently for each r. In angular-frequency terms, the angular Fourier harmonic e^{i m theta} is multiplied by H(m) = sinc(m Theta / (2 pi)) (normalised sinc), the same for every radius. COMPUTED.

**Consequence (striking, testable).** A Siemens star with n spokes centred at c has fundamental angular harmonic m = n. Its contrast after a spin of Theta is sinc(n Theta / 2 pi), *independent of radius*: for n = 36 spokes, 2.5 degrees -> 0.900, 5 degrees -> 0.637, 7.5 degrees -> 0.300, **10 degrees -> 0 (the whole star turns uniform grey)**, 13.9 degrees -> -0.216 (the star comes back with *inverted* spokes). In general the star vanishes whenever Theta is a multiple of the spoke period 360/n degrees. Conversely, a centred zone plate or any rotationally symmetric pattern is completely unchanged by spin blur. COMPUTED (probe5.py).

**Parameters.** c; angle Theta (Photoshop Radial Blur Spin: Amount 1-100, mapping to degrees UNVERIFIED; Blur Gallery Spin Blur: "Blur Angle" in degrees, an elliptical region with feathered edge, plus "Strobe Strength"/"Strobe Flashes"/"Strobe Flash Duration" in Motion Effects; REFERENCE: Adobe tutorials for Photoshop CC 2014, e.g. https://design.tutsplus.com/tutorials/quick-tip-using-the-path-blur-and-spin-blur-in-photoshop-cc-2014--cms-21250; the official helpx page returned 403 to this agent). Equivalent local sigma along the tangent: r Theta / sqrt(12). Elliptical spin (Photoshop) is a spin in a coordinate system squashed by the ellipse's aspect ratio, which models a wheel seen at an angle.

**Discrete construction.** N taps at angles phi_i evenly spaced over [-Theta/2, Theta/2], bilinear fetches of f(c + R(phi_i)(x - c)), weights 1/N. Sampling condition: r_max Theta / (N - 1) <= 1 px, so N >= r_max Theta + 1 (for r_max = 1400 px and Theta = 10 degrees: N >= 246). COMPUTED. Strobe variant: weights are a sum of a constant (ambient) and K narrow peaks (flashes), giving K sharp ghost copies superimposed on the arc blur.

**Frequency response.** No global MTF (LSV). Polar-domain response H(m) = sinc(m Theta/2pi) per angular harmonic (exact, all radii). Local Cartesian MTF at (r, theta): approximately sinc(r Theta (w . e_theta)) with e_theta the tangent direction (valid while the arc is nearly straight over the patch). COMPUTED.

**Key properties.** Linear; shift-variant but exactly rotation-equivariant about c; positive; not separable; not isotropic; semigroup in angle *only as boxes compose* (box * box = trapezoid; no). Preserves rotationally symmetric content perfectly; destroys angular content at a rate independent of radius.

**Algorithms and complexity.**
- Naive gather: N ~ r_max Theta taps (hundreds for strong spins).
- Doubling: average the image with itself rotated by Theta/2, then by Theta/4, ...: k passes x 2 fetches give 2^k evenly spaced angles (cost 2k per pixel). COMPUTED (base-2 argument).
- Polar resample + O(1) sliding-window circular box along theta + inverse resample: O(1) per pixel independent of angle, but the polar grid must have >= 2 pi r_max angular samples at the rim (~8800 for r_max = 1400) to avoid softening the periphery.
- Adaptive tap count per pixel: N(x) = ceil(r(x) Theta) + 1, cheap at the centre, expensive at the rim (divergent loop lengths in a SIMD group are fine because neighbouring pixels have similar r).

**GPU implementation.** One pass, per-pixel loop of N(x) rotated bilinear fetches (rotation via a precomputed cos/sin step: x_{i+1} = R(delta) x_i, two FMAs per step), or doubling with k passes. For Photoshop-style elliptical spins, transform x into the ellipse's frame, rotate, transform back.

**Visual fingerprint.** Unique: concentric arcs around one centre; sharp centre, blur growing linearly outwards; rotationally symmetric things (rings, the zone plate) survive untouched; the Siemens star greys out or inverts *uniformly at all radii* at specific angles. The exact dual of zoom blur (1.8). Artifacts: ghost copies (discrete spokes) at the rim when N is too small, an arc-shaped "stepping"; strobe copies when strobe weights are used. Best test: centred Siemens star at Theta = 360/n degrees (vanishes), centred zone plate (unchanged), impulse grid (arcs of increasing length), a rendered wheel.

**Where used.** Photoshop Radial Blur (Spin) and Blur Gallery Spin Blur (CC 2014, used to animate wheels and propellers in still images); GIMP Motion Blur (Radial mode); video editors' "spin"/"radial" blurs; real photographs of rotating objects (wheels, fans) and star-trail long exposures (the sky rotates about the celestial pole: a physical spin blur of point lights).

**Signature:** "Arcs around a centre: a box blur along the angle, so a Siemens star with n spokes turns uniformly grey at every radius when you spin it by exactly 360/n degrees, while rings never change."

### 1.10 path-blur (flow-field / line-integral blur)

- **Name and aliases:** path blur (Photoshop Blur Gallery "Path Blur", CC 2014), curved motion blur, flow blur, line integral convolution (LIC), streamline blur, vector-field motion blur. Family: directional, linear shift-variant; the most general member of the directional family (1.1, 1.8 and 1.9 are the special cases of a constant, radial and circular flow field).

**Continuous definition.** Given a vector field v(x) (from user-drawn paths, interpolated, or from optical flow), let gamma_x(s) be the streamline through x: d gamma/ds = v(gamma)/|v(gamma)|, gamma_x(0) = x. Then

    g(x) = integral w(s) f(gamma_x(s)) ds / integral w(s) ds

over s in [-L(x)/2, L(x)/2] (centred) or [-L(x), 0] (trailing, "uncentred"). This is Cabral and Leedom's line integral convolution ("Imaging Vector Fields Using Line Integral Convolution", SIGGRAPH 1993; REFERENCE, standard) applied to an image instead of to noise. Length L(x) and weight profile w can vary along the field.

**Parameters (Photoshop Path Blur, REFERENCE via tutorials since the official help page returned 403):** one or more Bezier paths that define the motion; **Speed** 0-500% (global blur length); **Taper** (global; how gradually the blur fades at the path ends); **Centered Blur** checkbox (symmetric vs one-sided trailing blur); per-endpoint **End Point Speed** (blur length at each end, interpolated along the path); **Edit Blur Shapes** (curvature of the blur near endpoints); Motion Effects: **Strobe Strength** (balance between continuous blur and flash copies), **Strobe Flashes** (number of sharp copies), **Strobe Flash Duration**; and a **Rear Sync Flash** mode that adds a sharp copy at the end of the motion. (Sources: https://planetphotoshop.com/using-the-path-blur-in-photoshop.html, https://www.tipsquirrel.com/photoshop-blur-gallery-path-blur/; how Photoshop interpolates the field between paths is proprietary: INFERRED to be a smooth weighted interpolation of the nearest paths' tangents.)

**Discrete construction.** Integrate the streamline numerically from x in both directions with step h <= 1 px (Euler, or RK2 midpoint for curved fields), sampling f bilinearly at each step; weights w(s_i) (box, taper ramp, or strobe peaks); normalise. Number of steps N = L(x)/h. For strobe: w(s) = (1 - k_s)/L + k_s * sum_j delta(s - s_j)/K.

**Frequency response.** None globally. Locally, where the field is straight and constant over the PSF length, it reduces to 1.1's sinc along the local direction; where the streamline curves, the local PSF is a curved segment and its spectrum is that of a curve measure (like 1.4). COMPUTED (reduction).

**Key properties.** Linear (for a fixed field), shift-variant, positive weights, anisotropic, not separable; one-sided (uncentred) versions also *displace* content along the path (phase shift). Edges *along* the flow stay sharp; edges across it smear.

**Algorithms and complexity.** Per pixel O(L/h) steps, each one vector-field fetch plus one image fetch (2 fetches per step). Fast LIC (Stalling and Hege 1995, "Fast and resolution independent line integral convolution", SIGGRAPH 1995; REFERENCE, standard) reuses the running sum along one long streamline so that every pixel the streamline passes gets its box average in O(1): O(1) per pixel amortised for box weights. Doubling does not apply exactly (streamlines do not compose into a group action unless the field is a symmetry field, as in spin and zoom).

**GPU implementation.** One pass; the vector field is a texture (RG16F) generated from the user's paths (e.g. by rasterising path tangents and diffusing them, or by evaluating the nearest-path tangent analytically per pixel); a per-pixel loop of N RK2 steps: 2 field fetches + 1 image fetch per step (~3N fetches). For L = 60 px and h = 1 px: ~180 fetches, which is fine on an A17 Pro at 1170 x 2532 for a single still frame but too slow for 120 Hz interaction, so the app should preview at half resolution. MODELED.

**Visual fingerprint.** Unique: streaks *curve* and follow user-drawn paths; blur length can change along a path (speed ramps); strobe mode leaves several sharp ghost copies along the curve. Artifacts: tearing where streamlines from two different paths meet, sharp seams where the field is discontinuous, swirling where the field has a singularity (vortex) and pinching at sinks/sources. Best test: impulse grid (each dot becomes a curved streak following the field); checkerboard (shows the field's geometry); text with an S-shaped path.

**Where used.** Photoshop Blur Gallery Path Blur (CC 2014); LIC in scientific flow visualisation (Cabral and Leedom 1993); painterly "flow" filters; optical-flow-driven motion blur in video tools (e.g. RSMB-style plug-ins; UNVERIFIED product details).

**Signature:** "Motion blur along curves you draw: every pixel integrates the image along its own streamline, so straight, radial and circular blurs are just three special flow fields."

---

## 2. Aperture / lens family

Common physics for this family (thin-lens geometric optics). A point that is not on the focal plane forms, on the sensor, a scaled image of the **aperture (entrance pupil)**. So the defocus PSF is the aperture shape, scaled by the circle of confusion (3.1), and filled uniformly (geometric optics) or with a diffraction pattern superimposed (wave optics, 2.7). Points in front of the focal plane form an image of the aperture that is *rotated 180 degrees* relative to points behind it, because the rays cross at the focus; with an odd-bladed aperture (pentagon, heptagon) foreground and background bokeh point in opposite directions. COMPUTED (ray geometry). Bokeh is only convincing in **linear-light, high-dynamic-range** input: a highlight that clipped at 1.0 in 8-bit sRGB spreads into a dim grey disc, so real tools either work on HDR/RAW data or boost pixels above a threshold before blurring (Photoshop Lens Blur "Specular Highlights: Brightness, Threshold"). Blurring sRGB-encoded values instead of linear values also darkens bright discs and shifts colours.

### 2.1 disc-bokeh (pillbox, lens blur)

- **Name and aliases:** disc blur, pillbox, circular averaging filter (MATLAB `fspecial('disk')`), lens blur, defocus blur, bokeh blur, "Disc Blur" (Core Image `CIDiscBlur`). Family: aperture/lens; LSI when the radius is constant (spatially varying when driven by depth, 3.1).

**Continuous definition.** h(x) = 1/(pi R^2) if |x| <= R, else 0. The edge-spread function (step-edge response) is the fraction of the disc on one side of a line: ESF(x) = 1/2 + (1/pi) [ (x/R) sqrt(1 - x^2/R^2) + arcsin(x/R) ] for |x| <= R. COMPUTED.

**Parameters.** R = radius in pixels = half the circle-of-confusion diameter c (3.1). Variance per axis R^2/4, so sigma_equiv = R/2 (a Gaussian with the same second moment has sigma = R/2). COMPUTED. Core Image `CIDiscBlur.inputRadius` default 8 (REFERENCE: Core Image Filter Reference, OS X 10.5+, iOS 9+). `CIBokehBlur` (iOS 13+/macOS 10.15+) adds `ringAmount` and `ringSize` ("extra emphasis at the ring of the bokeh") and `softness` (REFERENCE: Apple docs https://developer.apple.com/documentation/coreimage/cibokehblur ; default values and exact ring model not documented: INFERRED, measure with an impulse).

**Discrete kernel construction.** Rasterise the disc with *area coverage* (supersample each pixel, e.g. 16 x 16, or compute exact circle-pixel intersection area) and normalise to sum 1. Without antialiasing, small discs are lumpy (an R = 2 binary disc is a plus-shaped blob) and the radius can only change in jumps, which makes animated defocus "pop". Non-zero taps with area coverage: R = 2: 21, R = 4: 69, R = 8: 241 (approximately pi (R + 0.5)^2). COMPUTED (probe6.py). Edges: clamp (border pixels smear into discs), mirror, or zero/transparent (Core Image's default output extent grows by R on each side unless the input is `clampedToExtent()`).

**Frequency response.** The 2-D Fourier transform of the unit-area disc is radially symmetric:

    H(rho) = 2 J1(2 pi R rho) / (2 pi R rho)          ("jinc", the Airy amplitude function)

with rho the radial frequency in cycles/px. COMPUTED (probe5.py, mpmath Bessel functions):
- 50% contrast at rho R = 0.3525.
- **Zeros on circles** rho_k = j_{1,k} / (2 pi R): rho R = 0.6098, 1.1166, 1.6192, ... (j_{1,k} = 3.8317, 7.0156, 10.1735 are the zeros of J1). Unlike the box's evenly spaced zeros k/L, these are not evenly spaced; the spacing tends to 1/(2R).
- **First negative lobe** minimum -0.1323 at rho R = 0.8173; second positive lobe +0.0645 at rho R = 1.3396. So a disc blur inverts contrast in an annulus of frequencies, but less strongly than a box (-0.217) and equally in all directions.
- Discrete antialiased disc vs the continuous jinc along the u axis: R = 2: min -0.082, max deviation 0.054; R = 4: min -0.121, deviation 0.022; R = 8: min -0.129, deviation 0.008. Small discs are noticeably less "ringy" than the ideal because pixel-area coverage softens the rim. COMPUTED (probe6.py).

**Key properties.** Linear; shift-invariant; isotropic (up to rasterisation); positive kernel but a sign-changing MTF; **not separable** (it is not a product f(x) g(y), and its rank as a matrix grows with R); no semigroup (disc * disc is a smooth bump, not a disc); compact support with a hard edge; flat top (every point inside contributes equally, which is what makes bokeh balls look uniform).

**Algorithms and complexity (per pixel).**
- Naive 2-D gather: ~pi R^2 taps (R = 20: ~1257). The baseline.
- **Row-span decomposition with a horizontal prefix sum:** the rasterised disc is a stack of 2R + 1 horizontal spans; with a per-row running-sum image, each span costs 2 fetches, so 2(2R + 1) fetches per pixel = O(R) (R = 20: 82). Exact for a binary disc; antialiased rims need an extra fetch per span end. Precision: prefix sums need fp32. COMPUTED.
- Complex-kernel separable approximation (2.4): 2 passes x (2R + 1) taps x C components.
- Polygon approximation with skewed boxes (2.3): an octagon or hexagon instead of a disc, O(R).
- Stochastic/spiral sampling (2.5): S taps (tens to hundreds), noisy, usually denoised temporally.
- FFT: O(log N) per pixel, exact for one radius, impractical for depth-varying radius.
- Scatter (sprite per pixel): O(R^2) fill per *source* pixel; only economical for the few brightest pixels (sprite bokeh, 3.1).
- Mip/pyramid or Gaussian approximations are cheap but lose the flat top and hard rim (they produce "Gaussian bokeh", the most common give-away of cheap DoF).

**GPU implementation.** Gather fragment/compute kernel at half or quarter resolution (reduces taps by 4x or 16x), loop over a precomputed list of disc offsets with weights (bilinear sampling cannot pair taps on a circle as neatly as on a line). Threadgroup tiling: load a (T + 2R)^2 tile into threadgroup memory once and gather from it, which turns pi R^2 device reads into ~((T + 2R)/T)^2 reads per pixel (T = 16: R = 4 gives 2.25 and R = 8 gives 4 device reads per output pixel, the rest from threadgroup memory; tiles must fit the 32 KB threadgroup memory limit, e.g. 32 x 32 RGBA16F = 8 KB). MODELED.

**Visual fingerprint.** Unique: point lights become **flat, hard-edged, uniformly bright discs** that overlap additively; the Siemens star shows a grey ring where the local spoke frequency hits 0.61/R and an inverted-spoke band just inside it; the zone plate shows concentric dark rings (jinc zeros). Versus Gaussian: hard rim, flat top, contrast inversion. Versus polygonal bokeh: circular outline, isotropic spectrum. Best test: night-city point lights (HDR), centred Siemens star (predicted grey ring at radius r = n R / (2 pi 0.6098) = 0.261 n R for an n-spoke star; n = 36, R = 8 gives r ~ 75 px; COMPUTED), zone plate.

**Where used.** Core Image `CIDiscBlur` and `CIBokehBlur`; Photoshop Filter > Blur > Lens Blur (Depth Map source and Blur Focal Distance, Iris Shape triangle to octagon, Radius, Blade Curvature, Rotation, Specular Highlights Brightness and Threshold, Noise; REFERENCE: Adobe help "Create depth of field with Lens Blur", https://helpx.adobe.com/photoshop/desktop/effects-filters/blur-sharpen-filters/create-depth-of-field-with-lens-blur.html , and Peachpit "Applying the Lens Blur Filter in Adobe Photoshop CS5"); MATLAB `fspecial('disk', r)`; every game DoF that aims for "round bokeh"; smartphone portrait modes (INFERRED internals).

**Signature:** "A flat, hard-edged disc of light: its spectrum is a jinc with circular zeros at 0.61/R, so fine detail at just the wrong scale comes back inverted."

### 2.2 defocus-frequency-domain (jinc zeros, spurious resolution, the Hopkins defocus OTF)

This is less a separate blur than the frequency-domain view of 2.1 as a *physical* lens defocus; the app should present it as its own entry because it is the clearest demonstration that "blur" is not just "loss of detail".

- **Name and aliases:** defocus OTF, defocus MTF, spurious resolution, contrast reversal, phase reversal. Family: aperture/lens, LSI (for one depth).

**Definitions.**
- *Geometric limit* (defocus much larger than the wavelength): OTF = jinc as in 2.1, rho R scaled by the CoC radius.
- *Wave-optics defocus:* the OTF is the autocorrelation of the pupil function P(x) exp(i k W20 |x|^2) (W20 = defocus wavefront coefficient). Hopkins derived it in "The Frequency Response of a Defocused Optical System", Proc. Royal Society A 231(1184):91-103, 1955 (REFERENCE, citation verified; full text not read). It tends to the diffraction-limited MTF of 2.7 at W20 = 0 and to the geometric jinc for W20 >> lambda. Stokseth, "Properties of a Defocused Optical System", JOSA 59(10):1314, 1969, gives a widely used approximation (REFERENCE, not read).

**Spurious resolution.** Between the first and second zeros the OTF is negative, so a bar target or a Siemens star at those frequencies is imaged with *black and white swapped*: the detail looks "resolved" but is phase-reversed. Beyond the second zero it flips back to positive at low contrast. This is the textbook demonstration of defocus on a Siemens star (a grey ring with reversed spokes inside it) and it matters in vision science: Yellott and Yellott, "Correcting spurious resolution in defocused images", Proc. SPIE 6492, 2007, report that the defocus typical of presbyopia produces contrast sign reversals around 2 cycles/letter (REFERENCE via abstract). COMPUTED values as in 2.1: first zero rho R = 0.6098, deepest inversion -0.1323 at rho R = 0.8173.

**Zeros as a fingerprint.** The zero circles let you *measure* the blur radius from the image spectrum (the cepstrum of a defocused image peaks at the ring spacing), the basis of classic blur identification and depth-from-defocus; they also make naive deconvolution unstable (division by ~0), which is why Wiener/regularised deconvolution or coded apertures are used (Levin, Fergus, Durand and Freeman, "Image and Depth from a Conventional Camera with a Coded Aperture", SIGGRAPH 2007; REFERENCE, standard, not re-read).

**What the app should show.** (1) The 1-D radial MTF curve with the zero crossings marked and the negative lobe shaded; (2) a zone plate before and after blur (rings of grey at the zeros, inverted rings between); (3) a Siemens star with the predicted inversion ring drawn at r = 0.261 n R; (4) the same for a box (sinc, deeper inversion, anisotropic) and a Gaussian (no zeros) for comparison.

**Signature:** "Defocus does not just erase detail: between its zero rings it brings detail back upside-down."

### 2.3 polygonal-bokeh (hexagon via skewed boxes; McIntosh et al. 2012; Frostbite/BF3)

- **Name and aliases:** polygonal aperture bokeh, hexagonal bokeh, iris-shaped bokeh, aperture-blade bokeh, triple-rhombi bokeh. Family: aperture/lens, LSI per radius.

**Continuous definition.** h = (1/Area) * indicator of a polygon (the aperture formed by n diaphragm blades), scaled by the CoC. A regular n-gon of circumradius R has area (n/2) R^2 sin(2 pi/n) (hexagon: 2.598 R^2). Real blades are curved arcs, so a lens wide open is nearly circular and becomes more polygonal when stopped down (Photoshop models this with "Blade Curvature").

**Parameters.** Number of blades n, rotation, blade curvature, radius/CoC. Equivalent sigma for a regular hexagon: per-axis variance (5/24) R^2, sigma = 0.456 R (between the inscribed and circumscribed discs' R/2 values, apothem 0.866 R). COMPUTED (second moment of a regular hexagon: I = (5 sqrt3/16) R^4 per axis divided by area 2.598 R^2 gives 0.2083 R^2).

**Frequency response.** The Fourier transform of a polygon has a closed form as a sum over its edges (Lee and Mittra 1983, "Fourier transform of a polygonal shape function and its application in electromagnetics", IEEE Trans. Antennas and Propagation; REFERENCE, standard). Its magnitude decays most slowly along the directions *perpendicular to each edge*, so the 2-D MTF of a hexagon has six "spokes" of slower decay and zero curves that are not circles (hexagonal-ish rings on a zone plate). For a parallelogram spanned by segments a L and b L, H(w) = sinc(L w.a) sinc(L w.b) times a phase factor (one-sided segments); a hexagon built from three rhombi has H = the sum of three such products with phases. COMPUTED.

**Separable construction (the key trick).** A one-sided 1-D box blur along direction a followed by one along b produces a uniform *parallelogram* (Minkowski sum of the two segments). With three unit vectors a, b, c at 120 degrees (for example 90, -30 and -150 degrees), the three rhombi P(a,b), P(b,c), P(c,a) tile a regular hexagon of circumradius L exactly, meeting at the centre. COMPUTED (probe5.py: rasterised on a 1201 x 1201 grid, the union of the three rhombi differs from the analytic hexagon only on boundary pixels, mismatch fraction 7e-7, no interior overlap). Production versions:
- **Kawase** (CEDEC 2009, "Anti-Downsized Buffer Artifacts", Japanese slides): hexagon from three skewed boxes in **7 passes** (REFERENCE via https://lousodrome.net/blog/light/?p=116 ; slides not read).
- **DICE / Frostbite 2, Battlefield 3** (John White and Colin Barre-Brisebois, "More Performance! Five Rendering Ideas from Battlefield 3 and Need For Speed: The Run", SIGGRAPH 2011 Advances in Real-Time Rendering course): slides state "Decompose a hexagon into 3 rhombi. Each rhombi can be computed via separable blur. 7 Passes in total", then "7 passes and 6 blurs is not competitive. Need to reduce passes", and reduce it to **2 passes using multiple render targets** (REFERENCE via search excerpts of the slides; https://www.slideshare.net/slideshow/five-rendering-ideas-from-battlefield-3-need-for-speed-the-run/8907879).
- Barre-Brisebois's 2017 blog series "Hexagonal Bokeh Blur Revisited" gives code: pass 1 writes two MRTs, a CoC-weighted vertical blur (direction 90 degrees) and a diagonal blur (-30 degrees) summed with the vertical result; pass 2 blurs the vertical target along -30 degrees and the combined target along -150 degrees and averages the two (`(color.rgb + color2.rgb) * 0.5f`). Each 1-D blur starts half a step from the pixel and runs one way (`uv += direction * 0.5f`), which is what makes the segments one-sided. (REFERENCE: https://colinbarrebrisebois.com/2017/04/18/hexagonal-bokeh-blur-revisited-part-2-improved-2-pass-version/ and part 1. My reading of how these two passes add up to exactly three rhombi of equal weight: blur(V, -30) = P(90, -30); blur(V + D, -150) = P(90, -150) + P(-30, -150). The relative normalisation of the two halves in the published code is UNVERIFIED.)
- Cost: 4 one-dimensional blurs of n taps = **4n fetches per pixel** (plus CoC weights from alpha) for a hexagon of radius n taps, versus ~2.6 n^2 for a 2-D gather (n = 16: 64 versus ~665). COMPUTED.

**Which polygons work this way.** A convex polygon is a Minkowski sum of segments (a *zonogon*) if and only if it is centrally symmetric. So squares (2 directions, 1 parallelogram: the ordinary separable box), hexagons (3 directions, 3 rhombi) and octagons (4 directions, 6 parallelograms) can be built exactly from 1-D directional boxes; **odd-bladed apertures (5, 7, 9 blades, common on real lenses) cannot**. COMPUTED (zonogon theorem). For those, use a 2-D gather with a polygon mask, stochastic sampling inside the polygon (2.5), or scatter sprites.

**McIntosh, Riecke and DiPaola 2012.** L. McIntosh, B. E. Riecke and S. DiPaola, "Efficiently Simulating the Bokeh of Polygonal Apertures in a Post-Process Depth of Field Shader", Computer Graphics Forum 31(6):1810-1822, 2012, DOI 10.1111/j.1467-8659.2012.02097.x (REFERENCE: Eurographics Digital Library record https://diglib.eg.org/handle/10.1111/v31i6pp1810-1822). Note: the task brief attributed this paper to "McIntosh, Nowrouzezahrai & Hachisuka"; the library record lists McIntosh, Riecke and DiPaola. Per its abstract, it extends a post-process *gathering* DoF shader with a "novel separable filtering approach" that models **square, hexagonal and octagonal** apertures, and in a game engine runs at much better frame rates than a naive non-separable gather. The paper's exact construction (I recall a combination of separately blurred images, possibly using a min/intersection for the octagon) is **UNVERIFIED**: the PDF was not accessible to this agent (403).

**Key properties.** Linear, LSI (for a fixed radius), positive, anisotropic (n-fold symmetric), separable along *skewed* axes (not x and y), not semigroup. In DoF use, the per-tap CoC weighting makes it spatially varying and non-linear in the depth buffer.

**Discrete construction and edge handling.** Each 1-D pass: n bilinear taps along the direction with spacing <= 1 px (otherwise the rhombi show stripes), weights 1/n (or CoC-weighted and renormalised). Rotation of the hexagon = rotating the three directions. Edges as in 1.1.

**Visual fingerprint.** Unique: point lights become **hexagons (or octagons) with straight edges and a fixed orientation everywhere in the frame**, unlike discs; fine artifacts are faint seams where the three rhombi meet (especially when CoC differs across the rhombi; Barre-Brisebois's part 4 covers "rhombi overlaps"), and stripe/ghost patterns when taps are too sparse. Spectrum: six-fold streaks. With an odd-bladed physical aperture, foreground and background polygons point in opposite directions (the separable trick cannot reproduce odd n at all). Best test: night-city point lights; impulse grid to see the exact polygon; zone plate for the six-fold zero pattern.

**Where used.** Battlefield 3 and Need for Speed: The Run (Frostbite 2, 2011); Kawase's engines (2009); Stride engine `TripleRhombiBokeh` ("based on DICE's presentation at Siggraph 2011", with a `Phase` rotation parameter; https://doc.stride3d.net/4.0/en/API/Stride.Rendering.Images.TripleRhombiBokeh.html); VTK `vtkHexagonalBokehBlurPass` (https://vtk.org/doc/nightly/html/vtkHexagonalBokehBlurPass_8h.html); Photoshop Lens Blur iris shapes (triangle to octagon, blade curvature, rotation; implementation INFERRED).

**Signature:** "A hexagon is three rhombi and a rhombus is two line blurs: four 1-D passes buy you aperture-shaped highlights, but only for shapes with parallel opposite sides."

### 2.4 circular-separable-bokeh (complex-kernel separable disc; Garcia 2017, Niemitalo 2010)

- **Name and aliases:** Circular Separable Convolution Depth of Field (CSC DoF), complex-phasor bokeh, separable disk blur, "sum of complex Gaussians". Family: aperture/lens, LSI per radius.
- **Sources (both read for this section):** Kleber Garcia (Electronic Arts), "Circular Separable Convolution Depth of Field", SIGGRAPH 2017 Talks, DOI 10.1145/3084363.3085022 (2-page PDF, https://history.siggraph.org/wp-content/uploads/2022/09/2017-Talks-Garcia_Circular-Separable-Convolution-Depth-of-Field.pdf); Olli Niemitalo, "Circularly symmetric convolution and lens blur", 2010, http://yehar.com/blog/?p=1495 (the derivation and fitted parameters Garcia cites). Bart Wronski, "Separable disk-like depth of field", 2017, https://bartwronski.com/2017/08/06/separable-bokeh/ (an implementation of Niemitalo's method inspired by Garcia's talk).

**Why it is possible.** The Gaussian is the only real, radially symmetric kernel that is also separable (it is exp of a function of x^2 + y^2 that splits into a product). Allowing the exponent to be *complex* keeps both properties: exp(-(a - i b) x^2) * exp(-(a - i b) y^2) = exp(-a r^2) exp(i b r^2) depends only on r. A 2-D *real* kernel is then taken as a weighted combination of the real and imaginary parts, and a sum of several such components is fitted to a disc. Every component is exactly radially symmetric, so the result is exactly isotropic; only the radial *profile* is approximate.

**Continuous definition (Garcia eq. 1).** With x the tap offset divided by the blur radius (so the disc edge is at x = 1):

    F_c(x) = exp(-a_c x^2) [cos(b_c x^2) + i sin(b_c x^2)]
    2-D kernel  K(x, y) = sum_c [ A_c Re(F_c(x) F_c(y)) + B_c Im(F_c(x) F_c(y)) ]

Parameters (identical in Garcia's Table 1 and Niemitalo's table; Niemitalo writes a with a negative sign):

| filter | component | a | b | A | B |
|---|---|---|---|---|---|
| low quality (1 component) | c0 | 0.862325 | 1.624835 | 0.767583 | 1.862321 |
| high quality (2 components) | c0 | 0.886528 | 5.268909 | 0.411259 | -0.548794 |
| | c1 | 1.960518 | 1.558213 | 0.513282 | 4.561110 |

Niemitalo also lists 3 to 6 component fits; the fit target is a unit disc with pass band r in [0, 1] and a transition band of width 0.2 (stop band r >= 1.2). Reported ripple: 1 component +-0.232417, 2: +-0.075459, 3: +-0.026297, 4: +-0.010843, 5: +-0.004062 (about one 8-bit LSB), 6: 0.001918; the component weights grow with the count (for 5 components "as much as 36 times their sum"), which costs precision. (REFERENCE, Niemitalo.) **Reproduced:** with the parameters above I get pass-band ripple +-0.2324 (1 component) and +-0.0757 (2 components), stop-band |K| <= 0.233 and 0.077, so the radial profile dips to -0.23 of the disc height outside the rim with one component. COMPUTED (probe6.py), matching Niemitalo's figures.

**Discrete construction (Garcia section 2).** An offline step generates an HLSL header with normalised complex weights G_c(x) = F_c(x)/alpha for every tap x in [-R, R], where alpha^2 = sum over the (2R+1)^2 grid of the 2-D real kernel (Garcia eq. 3), so the 2-D result sums to 1. Intermediate (complex) images contain large and negative values, so Garcia "brackets" each 1-D kernel into [0, 1]: G'_c = (G_c - O_c)/S_c, stores the convolution in an 8- or 10-bit target, and recovers I_blur = I'_blur S_c + O_c * sum_x I_x (eqs. 4-5), with separate offset/scale for real and imaginary parts. On hardware with fp16/fp32 render targets (an A17 Pro has both) bracketing is unnecessary.

**Passes and cost.** Pass 1 (horizontal): for each component, convolve each colour channel with the complex 1-D kernel, producing a real and an imaginary image per channel (RGB: 6 values per component, e.g. two RGBA16F targets for one component). Pass 2 (vertical): convolve each complex intermediate with the same complex kernel (complex multiply-accumulate), then combine A_c Re + B_c Im and sum over components. Fetches per pixel: (2R + 1) in pass 1 plus C x (2R + 1) multi-channel fetches in pass 2; arithmetic grows as ~4 C (2R + 1) MACs per channel. For R = 16 and 2 components: ~33 + 66 = 99 texture reads versus ~804 for a brute-force disc gather. COMPUTED. Bandwidth, not ALU, dominates (6 floats per component per pixel written and read back).

**Frequency response.** Each component has a closed-form 2-D Fourier transform (a complex Gaussian transforms to a complex Gaussian: the FT of exp(-(a - i b) r^2) is (pi/(a - i b)) exp(-pi^2 rho^2/(a - i b))), so H(rho) is a short sum of such terms: a smooth approximation of the jinc of 2.1 with its first zero and negative lobe roughly in place but without the exact infinite ring structure. COMPUTED (Gaussian Fourier pair continued to complex parameter, valid for a > 0).

**Key properties.** Linear; LSI for a fixed radius; **separable in x and y** (the defining property) yet **exactly isotropic**; kernel is *not* positive (ripple and a negative ring of up to -23% with one component, -7.7% with two), so isolated highlights get faint ringing and a darker halo just outside the disc; not semigroup.

**DoF composition (Garcia section 2.2).** Two blurred images: a **near** blur using the cheap 1-component filter and a lower-resolution tiled CoC buffer holding the *minimum* CoC per tile, so foreground blur can bleed over sharp background edges; a **far** blur using the 2-component filter; then near, far and in-focus are composited. CoC is stored in sRGB targets (or a power-of-two encoding) to keep precision at small CoC. Variable CoC inside one layer is handled by the layer split rather than exactly (exact details of per-pixel radius scaling are not in the 2-page talk: UNVERIFIED).

**Visual fingerprint.** Unique: **round, flat-ish bokeh produced by two 1-D passes**, with faint concentric ripple inside the disc and a thin dark ring outside it (strong with 1 component, subtle with 2), never polygonal; Garcia's figure 2 notes "more components, the closer circular representation and less banding". Best test: a single HDR point light on black (shows the ripple and dark ring; compare 1 vs 2 components vs brute-force disc), zone plate (isotropic zero ring at about the jinc position).

**Where used.** Shipped in Madden NFL 15, 16 and 17, FIFA 17 and PGA Tour Rory McIlroy (Garcia abstract); Frostbite news page (https://www.ea.com/frostbite/news/circular-separable-convolution-depth-of-field); open-source re-implementations (Wronski 2017; others on Shadertoy, UNVERIFIED).

**Signature:** "A disc from two 1-D passes: complex Gaussians are both separable and round, so a weighted pair of them fakes a pillbox with only a faint ripple."

### 2.5 stochastic-bokeh (Poisson disc, golden-angle spiral; Gustafsson 2018 single-pass DoF)

- **Name and aliases:** sampled bokeh, spiral bokeh, Vogel-disc sampling, golden-angle sampling, scatter-as-gather DoF, single-pass bokeh DoF. Family: aperture/lens; LSI in expectation for a constant radius, spatially varying (and data-dependent) in DoF use.

**Continuous definition.** Estimate the disc integral g(x) = (1/(pi R^2)) integral_{|y|<=R} f(x + y) dy by S samples y_i inside the disc: g ~ (1/S) sum f(x + y_i). Sample sets:
- **Poisson-disc / blue-noise** points (minimum distance between samples, precomputed offline).
- **Vogel / golden-angle spiral:** y_i = R sqrt((i + 0.5)/S) (cos(i phi), sin(i phi)), phi = pi (3 - sqrt 5) = 2.39996 rad = 137.508 degrees; equal-area rings by construction, no clumping, any S (Vogel 1979, "A better way to construct the sunflower head", Mathematical Biosciences 44; REFERENCE, standard). COMPUTED angle value (probe6.py).
- Concentric rings (e.g. Shirley and Chiu 1997, "A low distortion map between disk and square", J. Graphics Tools; REFERENCE, standard) mapped from a square grid.
- Per-pixel random rotation/scale of the pattern (blue-noise or interleaved gradient noise) plus temporal accumulation turns the pattern's structure into noise that TAA averages away.

**Gustafsson's single-pass DoF (read for this section).** Dennis Gustafsson, "Bokeh depth of field in a single pass", 4 May 2018, https://blog.voxagon.se/2018/05/04/bokeh-depth-of-field-in-single-pass.html (formerly blog.tuxedolabs.com). Facts from the post's code:
- Constants: `GOLDEN_ANGLE = 2.39996323`, `MAX_BLUR_SIZE = 20.0` (px), `RAD_SCALE = 0.5` ("Smaller = nicer blur, larger = faster").
- Loop: `for (float ang = 0.0; radius < MAX_BLUR_SIZE; ang += GOLDEN_ANGLE)` with `radius += RAD_SCALE/radius`, starting at RAD_SCALE. Since r^2 grows by ~2 RAD_SCALE per sample, the sample count is ~MAX_BLUR_SIZE^2 / (2 RAD_SCALE): **398 samples** for the defaults (198 with RAD_SCALE = 1; 98 for MAX = 10). Each sample stands for ~pi px^2 of disc at the defaults (spacing ~1.8 px). COMPUTED (probe6.py).
- CoC: `getBlurSize = abs(clamp((1.0/focusPoint - 1.0/depth) * focusScale, -1.0, 1.0)) * MAX_BLUR_SIZE`: linear in **inverse depth**, which is what the thin-lens formula gives (3.1).
- Scatter-as-gather weight: `m = smoothstep(radius - 0.5, radius + 0.5, sampleSize)`: a sample at distance `radius` contributes only if *its own* CoC reaches the centre pixel (a gather that imitates scatter).
- Foreground/background handling: if the sample is behind the centre (`sampleDepth > centerDepth`), its size is clamped to `centerSize * 2.0`, which the author calls "totally unphysical", to stop a blurry background from bleeding over a sharp foreground.
- Accumulation: `color += mix(color/tot, sampleColor, m); tot += 1.0;` then `color /= tot`: a sample that does not reach the pixel adds the current running mean instead, keeping the normalisation simple.
- The author's own engine computes CoC into alpha while downscaling to **quarter resolution** and blends the original and blurred images by average sample size; he notes there is "no correct solution" because a post-process lacks what is behind objects.

**Frequency response.** For a fixed (non-rotated) pattern the kernel is a sum of S weighted deltas, an LSI kernel whose MTF follows the jinc at low frequencies and then shows *replica peaks* at high frequencies (aliasing of the point set); with random per-pixel rotation the kernel is random, its *expected* MTF is the jinc, and the error appears as noise with variance ~ Var(f within the disc)/S. COMPUTED (sampling theory).

**Key properties.** Linear in colour for fixed depths; unbiased (in expectation) for a uniform disc; shape-agnostic: the same loop gives any aperture by rejecting or warping samples (polygon, cat's eye 2.6, anamorphic oval 2.8), which is its big advantage over separable tricks; noisy; not separable.

**Algorithms and GPU.** One full-screen pass, S fetches per pixel (each reading colour plus depth/CoC). Cost scales with R^2/(spacing^2); real-time engines run it at half or quarter resolution with S = 16 to 64 and rely on TAA (typical counts, UNVERIFIED per engine). Threadgroup tiling helps for small R (cache the neighbourhood); for large R the spiral's scattered reads are cache-unfriendly. Pre-filtering (a 2x2 or 4x4 downsample) reduces noise per sample.

**Visual fingerprint.** Unique: **grainy or swirly-structured bokeh** that converges to a clean disc with more samples or temporal accumulation; undersampled spirals show a faint spiral/sunflower texture inside large discs and "ring" artifacts; highlights become speckled discs. Because CoC is tested per sample, foreground blur extends over sharp background edges (good) but the clamp creates soft halos. Best test: night-city point lights at large R with S = 16 vs 64 vs 400; a sharp foreground bar in front of blurred lights (shows the clamp behaviour).

**Where used.** Gustafsson's post (Teardown's developer; whether Teardown ships this exact shader is UNVERIFIED); the bgfx example "45-bokeh" (implements the post, multi-pass with CoC in alpha); LYGIA shader library `sample/dof` (credits Gustafsson); ValveResourceFormat's DOF renderer (golden-angle spiral); countless Shadertoy DoF shaders.

**Signature:** "Throw samples into the disc along a 137.5-degree spiral: any aperture shape for the price of noise, and each sample asks 'does your blur reach me?'"

### 2.6 cats-eye-swirl-bokeh (optical vignetting, Petzval swirl), with soap-bubble, onion-ring and chromatic bokeh

- **Name and aliases:** cat's-eye bokeh, optical (mechanical) vignetting of bokeh, "barrel clipping" (Unity), swirly bokeh, Petzval swirl, Helios swirl; related aperture-profile variants: soap-bubble bokeh (bright rim), onion-ring bokeh (concentric ripples), chromatic / longitudinal-CA bokeh fringing. Family: aperture/lens, **linear shift-variant** (the PSF's shape, orientation and area depend on position in the frame).

**Physical cause.** For an off-axis point, the cone of light that reaches the sensor is limited not only by the diaphragm but also by the rims of the front and rear lens elements/barrel; seen from that point, the entrance pupil is partly hidden ("vignetted"). The visible aperture becomes the intersection of the pupil with a second, offset circle, a lens/almond shape whose long axis is *tangential* (perpendicular to the line to the image centre). Sources: forum-level explanations agree that "vignetting is caused by shading of the entrance pupil"; product documentation states the effect directly: Unity's physical camera "Barrel Clipping" ("a higher value creates a cat's eye effect", due to lens self-occlusion; https://docs-alpha.unity3d.com/Manual/urp/cameras/physical-camera-reference.html and Unity Live Capture lens docs). Swirl: Petzval-type lenses keep strong field curvature on purpose ("enhances the effects of field curvature rather than attempting to correct it", review of the Lomography Petzval 55 mm, https://phillipreeve.net/blog/review-lomography-petzval-55mm-f-1-7-bokeh-control-mark-ii-art-lens/); together with the tangentially elongated cat's eyes, background highlights line up along circles around the centre. A rigorous optics paper explaining swirl was **not found**; the mechanism "field curvature + tangential vignetting" is the consensus of practitioner sources and is marked INFERRED.

**Continuous model (for the app).** Image centre c, normalised field position p = (x - c)/r_max, CoC radius R(x). Local PSF (gather form):

    h_x(y) = (1/Z_x) 1[|y| <= R] * 1[|y - k R p| <= R]        (barrel clipping strength k >= 0)

i.e. the intersection of the aperture disc with an identical disc shifted *radially* by k R |p|. At the centre (p = 0) it is the plain disc; towards the corners it narrows into a tangential almond; when k|p| >= 2 the intersection vanishes. If Z_x is the *full-disc* area instead of the intersection area, the model also reproduces the brightness falloff (optical vignetting) of corner bokeh. Swirl: add field-dependent anisotropy, e.g. scale the PSF by (1 + s|p|) along the tangent and (1 - s'|p|) along the radius, which mimics tangential-sagittal astigmatism from field curvature. MODELED (a phenomenological model, not a lens design).

**Parameters.** Barrel-clipping strength k (Unity "Barrel Clipping"), clipping-disc radius (can differ from R), swirl strength s, centre c. Lomography's Petzval lenses expose a mechanical "Bokeh Control" ring that changes the swirl strength (product pages; mechanism INFERRED).

**Frequency response.** No global MTF. Locally, the PSF is elongated tangentially, so it removes tangential detail more than radial detail: around a centred Siemens star (whose spoke stripes vary tangentially) the corners blur *more* than a disc blur of the same area, while concentric rings blur *less*. In other words the cat's-eye field is a *partial spin blur* (1.9) layered on a disc blur, which is exactly why the viewer reads it as a swirl. COMPUTED (shape argument; the app can confirm with the local-MTF probe).

**Aperture-profile variants (all LSI for a fixed R, they change the radial profile h(r) inside the disc):**
- **Soap-bubble bokeh** (bright rim, dark centre): overcorrected spherical aberration (e.g. Meyer-Optik Trioplan, commonly cited; UNVERIFIED as an optical claim). Model h(r) proportional to 1 + w (r/R)^q. A lens with spherical aberration shows the *opposite* profile (bright centre, soft edge) on the other side of the focal plane: foreground and background bokeh differ, a strong realism cue. Core Image `CIBokehBlur.ringAmount/ringSize` emulate a rim boost.
- **Onion-ring bokeh:** concentric ripples inside each disc from polishing/moulding marks on aspherical elements. Model h(r)(1 + e cos(2 pi r / lambda_r)).
- **Chromatic (longitudinal CA) bokeh:** focus distance depends on wavelength, so each colour channel has its own CoC; foreground and background highlights get opposite colour fringes (magenta/purple on one side of focus, green on the other, lens-dependent). Model: per-channel radius R_c = R (1 + delta_c) with delta of opposite sign in front of and behind the focal plane.
- Real-time rendering of these optical effects was addressed by Lee, Eisemann and Seidel, "Real-Time Lens Blur Effects and Focus Control", ACM TOG 29(4) (SIGGRAPH 2010) (REFERENCE, standard; which effects it covers in detail is UNVERIFIED).

**Key properties.** Linear, shift-variant (all variants of the cat's eye), positive, anisotropic away from the centre; not separable (the shape changes with position and is not a zonogon); for the radial-profile variants: LSI, isotropic, positive, non-flat.

**Algorithms and GPU.** Separable tricks (2.3, 2.4) cannot express a position-dependent almond. Use stochastic gather (2.5) with one extra test per sample (|y - k R p| <= R, or warp samples into the intersection), or scatter sprites whose texture is chosen/clipped per position. Cost = cost of 2.5 plus ~2 ALU ops per sample. The radial-profile variants cost nothing extra in a gather (they change the weight table) and cost 1 extra multiply per sample in stochastic sampling (importance weights).

**Visual fingerprint.** Unique: bokeh shape **changes across the frame**: round in the centre, tangential almonds ("cat's eyes") towards the corners, dimmer in the corners, arranged in circles that read as a swirl. Soap bubble: bright rims. Onion ring: rippled discs. Chromatic: coloured rims that swap colour between foreground and background. Best test: a uniform grid of HDR point lights across the whole frame (the PSF field is the whole story); Siemens star at the corner versus the centre.

**Where used.** Unity HDRP/URP physical camera (Blade Count, Curvature, Barrel Clipping, Anamorphism); Unreal Engine cinematic DoF (blade count; curvature tied to the lens's maximum aperture; https://dev.epicgames.com/documentation/unreal-engine/cinematic-depth-of-field-in-unreal-engine); compositing plug-ins that simulate cat's-eye bokeh and optical vignetting (e.g. Richard Rosenman's After Effects tools, https://richardrosenman.com/elevating-photorealism-why-cats-eye-bokeh-optical-vignetting-are-essential-for-after-effects-compositors/); real lenses: Helios 44, Lomography Petzval (marketing and reviews).

**Signature:** "The aperture gets eclipsed by the lens barrel off-axis: discs turn into tangential cat's eyes that line up in circles, so the background seems to swirl."

### 2.7 diffraction-airy (the physical PSF of a perfect lens; diffraction spikes)

- **Name and aliases:** Airy pattern, Airy disc, diffraction-limited PSF, Fraunhofer diffraction PSF, "Chinese-hat" MTF; starburst / sunstar / diffraction spikes for polygonal apertures and support struts. Family: aperture/lens (wave optics), LSI over a small field.

**Continuous definition.** In the Fraunhofer (far-field) approximation the incoherent PSF is the squared magnitude of the Fourier transform of the pupil function P: h(x) proportional to |FT{P}(x / (lambda f))|^2. For a circular pupil of diameter D at f-number N = f/D:

    h(r) = [2 J1(v) / v]^2 ,   v = pi r / (lambda N)

(Airy, "On the Diffraction of an Object-glass with Circular Aperture", Trans. Cambridge Philosophical Society 5, 1835; REFERENCE, standard). COMPUTED (probe5.py): first dark ring at r = 1.2197 lambda N (the "1.22" of the Rayleigh criterion), second at 2.2331 lambda N; 83.8% of the energy falls inside the first dark ring; FWHM 1.029 lambda N; a Gaussian with the same FWHM has sigma = 0.437 lambda N (a commonly quoted best-fit value is about 0.42 lambda N, e.g. Zhang, Zerubia and Olivo-Marin 2007, Applied Optics 46(10); value UNVERIFIED here).

**Frequency response (closed form).** The OTF is the autocorrelation of the pupil; for a circular, aberration-free pupil:

    MTF(nu) = (2/pi) [ arccos(nu/nu_c) - (nu/nu_c) sqrt(1 - (nu/nu_c)^2) ],  nu <= nu_c = 1/(lambda N); 0 beyond

Values: 0.873 at 0.1 nu_c, 0.685 at 0.25, 0.391 at 0.5, 0.144 at 0.75. COMPUTED. It is **never negative** and has a **hard cutoff**: diffraction is a truly band-limited blur, unlike defocus (2.2). At lambda = 550 nm: f/1.78 -> cutoff 1021 cycles/mm, Airy dark-ring diameter 2.39 um; f/2.8 -> 649 cycles/mm, 3.76 um; f/8 -> 227 cycles/mm, 10.7 um; f/16 -> 114 cycles/mm, 21.5 um. COMPUTED. For a phone main camera at f/1.78 with ~1.22 um pixels (iPhone 15 Pro Max class; pixel pitch UNVERIFIED), the sensor Nyquist (410 cycles/mm) sits at 0.40 nu_c, where the diffraction MTF is still 0.50; with 2x2 binning (2.44 um effective) Nyquist is at 0.20 nu_c and MTF 0.75. COMPUTED. Diffraction grows with N while defocus shrinks with N; the f-number where they balance is the "diffraction-limited aperture".

**Polygonal apertures and spikes.** A straight aperture edge transforms into a streak perpendicular to it (the FT of a straight edge falls off only as 1/rho along its normal, so 1/rho^2 in intensity). "A diaphragm with n blades yields n spikes if n is even, and 2n spikes if n is odd" (REFERENCE: Wikipedia, "Diffraction spike", https://en.wikipedia.org/wiki/Diffraction_spike). Telescopes' secondary-mirror spider vanes give 4 (or 6 for JWST's hexagonal segments plus struts) spikes.

**Parameters.** Wavelength lambda (per colour channel: red Airy discs are ~1.3-1.4x larger than blue), f-number N, pupil shape (blades, struts), pixel pitch (to convert to pixels: r_px = 1.22 lambda N / pitch).

**Discrete construction.** Compute the pupil P on a grid (with any obstruction, blade polygon, defocus phase exp(i k W20 rho^2) or aberrations), zero-pad, FFT, take |.|^2, resample to pixel scale for each wavelength, sum over wavelengths with the sensor's spectral weights, normalise. Truncation: the Airy pattern's rings decay slowly (~r^-3), so a kernel truncated at the first few rings loses a few percent of energy into a faint halo. COMPUTED (asymptotics of J1).

**Key properties.** Linear, shift-invariant (over an isoplanatic patch), isotropic for circular pupils, positive PSF with a non-negative band-limited MTF, not separable (circular) but separable for a square pupil (sinc^2 x sinc^2). Not semigroup.

**Algorithms and GPU.** Small Airy kernels (a few px) are best as a direct 2-D gather. Large glare kernels (with spikes, rings and the long scattering tail) are done by **FFT convolution**: forward FFT of the image, multiply by the precomputed kernel spectrum, inverse FFT; O(log N) per pixel. Physically-based glare in graphics: Spencer, Shirley, Zimmerman and Greenberg, "Physically-Based Glare Effects for Digital Images", SIGGRAPH 1995; Ritschel et al., "Temporal Glare: Real-Time Dynamic Simulation of the Scattering in the Human Eye", Eurographics 2009 (both REFERENCE, standard, not re-read). Cheaper real-time imitation: Gaussian core plus a star/streak filter (1.3) for the spikes.

**Visual fingerprint.** Unique: the blur that **cannot invert contrast** and that **cuts off completely** above nu_c (a zone plate's outer rings go flat grey without ever reversing); point lights get a tight core, faint rings and (for blades) symmetric spikes with rainbow fringes; the blur *grows* when you stop down. Best test: HDR point lights on black (rings and spikes), zone plate (hard cutoff ring with no inversion), and the f-number slider beside 2.1 to show the defocus/diffraction trade-off.

**Where used.** Optical design and lens MTF charts (diffraction-limited curve as the upper bound); astronomy and microscopy (PSF models for deconvolution); physically based glare/bloom in games (FFT "convolution bloom" in Unreal Engine is commonly cited; UNVERIFIED version and details); star-filter effects.

**Signature:** "The blur a perfect lens still has: an Airy disc whose MTF never goes negative and stops dead at 1/(lambda N), so stopping down makes it worse."

### 2.8 anamorphic (oval bokeh, horizontal streak flares)

- **Name and aliases:** anamorphic bokeh, oval bokeh, elliptical aperture blur, "Anamorphism" (Unity), anamorphic lens flare, horizontal streak, "J.J. Abrams flare". Family: aperture/lens; the oval bokeh is LSI per radius, the streak is a thresholded (non-linear) directional effect like 1.3.

**Physical cause.** A front-anamorphic lens has a cylindrical element with power along one axis that squeezes the horizontal field (common squeeze factors 1.33x, 1.5x, 1.8x, 2x). After de-squeezing, a round defocused highlight becomes a **vertical oval** (tall by the squeeze factor); rear-anamorphic designs lose most of the oval shape. Bright sources produce long **horizontal streak flares** because the cylinder spreads stray light along one axis; their blue colour comes from particular coatings, not from anamorphosis itself. (REFERENCE, practitioner sources: https://www.indepthcine.com/videos/anamorphic-squeeze , https://filmdaft.com/a-beginners-guide-to-anamorphic-lenses/ , https://www.adorama.com/alc/anamorphic-lens ; these are not optics papers, so the optics are summarised conservatively.)

**Continuous definition.** Oval bokeh: elliptical pillbox h(x, y) = 1/(pi a b) for (x/a)^2 + (y/b)^2 <= 1, b = s a with squeeze s. Streak flare: g = f + k * B(T(f)) where T is a bright-pass threshold and B a 1-D horizontal blur with a long (exponential or Gaussian) profile and a tint.

**Parameters.** Squeeze s (1.33 to 2), radius, streak length, threshold, tint, intensity. Unity "Anamorphism": positive stretches vertically, negative horizontally, and it also drives Bloom's anamorphic option (REFERENCE: Unity physical camera docs above).

**Frequency response.** Elliptical pillbox: H(u, v) = 2 J1(2 pi rho') / (2 pi rho') with rho' = sqrt((a u)^2 + (b v)^2): the zero rings of 2.1 become ellipses squashed in the *opposite* direction (a tall PSF has its zeros closer together vertically). Streak: 1-D response along x only (as 1.3), applied to highlights. COMPUTED (scaling theorem).

**Properties and algorithms.** Linear, LSI per radius, positive, anisotropic, not separable as a pillbox. Two neat facts: (1) any disc method becomes an oval method by scaling one axis of the sample offsets (stochastic, 2.5) or by blurring a vertically squeezed copy of the image and stretching back; (2) the complex-kernel separable method (2.4) supports ovals for free, because F_c(x/a) F_c(y/b) = exp(-(a_c - i b_c)(x^2/a^2 + y^2/b^2)) is elliptically symmetric: use radius a in the horizontal pass and b in the vertical pass. COMPUTED. Streak: bright-pass at reduced resolution, a few passes of 1-D horizontal blur (or the base-4 exponential trick of 1.3), tint, add.

**Visual fingerprint.** Unique: **tall oval bokeh** plus **long horizontal streaks** from bright lights: the "cinema" look. Versus 2.6: ovals have the *same* orientation everywhere (vertical), cat's eyes rotate with position. Best test: night-city point lights; zone plate (elliptical zero rings).

**Where used.** Cinema anamorphic lenses; Unity physical camera Anamorphism; game "anamorphic flare" options in bloom/lens-flare post-processing (e.g. Unity bloom's anamorphic setting; others UNVERIFIED); Core Image has no anamorphic filter (an elliptical blur can be built by scaling, blurring with `CIDiscBlur`, and unscaling).

**Signature:** "A squeezed aperture: bokeh turns into tall ovals and highlights shoot long horizontal streaks, the same in every corner of the frame."

---

## 3. Depth-dependent and spatially-varying family

### 3.1 depth-of-field-coc (thin-lens circle of confusion; scatter vs gather; foreground bleeding)

- **Name and aliases:** depth of field (DoF), defocus blur, lens blur with a depth map, synthetic aperture, "Portrait mode" / "Cinematic mode" background blur (Apple; INFERRED internals), bokeh DoF. Family: spatially varying (depth-dependent), linear in colour for a fixed depth map, with occlusion.

**Thin-lens circle of confusion (REFERENCE: Wikipedia "Circle of confusion", https://en.wikipedia.org/wiki/Circle_of_confusion, which notes it is exact for a paraxial thin lens or a symmetrical lens).** Focus distance S1, object distance S2, focal length f, aperture diameter A = f/N:

    c = A * |S2 - S1| / S2 * f / (S1 - f)  =  |S2 - S1| / S2 * f^2 / (N (S1 - f))
    background at infinity:  c_inf = f^2 / (N (S1 - f))

Rewritten: c = [A f S1 / (S1 - f)] * |1/S1 - 1/S2|. **The blur diameter is proportional to the difference of inverse depths (disparities), not of depths.** COMPUTED (algebra). Consequences:
- An object at half the focus distance (S2 = S1/2) is exactly as blurred as one at infinity; an object at 2 S1 has half the infinity blur (COMPUTED, probe7.py). Blur grows quickly in front of the focal plane and saturates behind it, which is why foreground bokeh is so large.
- Real-time shaders compute CoC as a clamped linear function of 1/depth (Gustafsson's `(1/focusPoint - 1/depth) * focusScale`), which matches the formula exactly.
- Worked examples (COMPUTED, probe6.py): a phone main camera (f ~ 6.86 mm, f/1.78, focus 1 m, background at infinity; focal length and pixel pitch UNVERIFIED) gives c = 0.027 mm = ~11 px at 2.44 um (binned) or ~22 px at 1.22 um: barely any natural bokeh, which is why phones synthesise it from depth. A full-frame 50 mm f/1.8 focused at 2 m gives c_inf = 0.71 mm = ~119 px on a 6000-px-wide sensor; an 85 mm f/1.4 at 2 m with background at 4 m gives 1.35 mm = ~225 px.
- Acceptable-sharpness limits (for DoF tables, not for rendering): d/1500 = 0.029 mm for full frame is "widely used" (REFERENCE, same article).

**Definition of the operator.** Ground truth integrates over the lens aperture: g(x) = (1/|A|) integral_{aperture} f_lens(u)(x) du, the average of pinhole images seen from every point u of the aperture (this is what the accumulation buffer of Haeberli and Akeley 1990 computes by jittering the camera across the lens, and what distributed ray tracing computes). It includes occlusion: a blurry foreground object is *partly transparent* at its edges, and you can see some of the background behind it. In post-processing, with only a single pinhole image plus depth, each pixel p with depth z_p is given a CoC c_p (signed: negative in front of focus, positive behind) and the PSF of that pixel is the aperture shape (2.1-2.6) of diameter |c_p|. Since c varies per pixel, this is a linear shift-variant operator, and the two readings of section 0 give different answers:
- **Scatter (forward, physically right):** each source pixel spreads its colour over a disc of its own CoC: g(x) = sum_p f_p h_{c_p}(x - p), composited front-to-back by depth. Cost proportional to sum c_p^2; ordering needed for occlusion.
- **Gather (backward, GPU-friendly):** each output pixel averages a disc of *its own* CoC: g(x) = sum_p f_p h_{c_x}(x - p). Cheap and parallel, but wrong at depth edges.

**The depth-edge problems (gather vs scatter).**
1. **Foreground bleeding (missing):** a blurry foreground object should spill over the sharp background behind it. In a gather, a sharp background pixel has CoC ~ 0, gathers nothing, and the foreground's edge stays cut out sharply ("sharp silhouettes of blurry foreground"). Fixes: dilate the near CoC (tile max/min CoC over neighbours, as in 1.6's NeighborMax; Garcia uses a tiled *min* signed CoC for the near layer "so there is edge bleeding when blurring from the front"), or use **scatter-as-gather** weights in which a sample contributes if *its* CoC reaches the pixel (Gustafsson's `smoothstep(radius - 0.5, radius + 0.5, sampleSize)`; Jimenez's SIGGRAPH 2014 "Next Generation Post Processing in Call of Duty: Advanced Warfare", http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/ ; details known only via third-party notes: a presort pass splitting each pixel into foreground/background with CoC into an R11G11B10 target, tile max-CoC/min-depth with a 3x3 neighbourhood, a **49-tap circular** gather because separable hex/octagonal kernels did not suit scatter-as-gather, and a larger foreground blur to cover missing background; UNVERIFIED against the slides).
2. **Background leaking / haloes:** a blurry background pixel next to a sharp foreground object gathers the sharp foreground colour, producing a glowing halo of foreground colour around the object. Fix: depth-aware weights (ignore samples that are in front and in focus; Gustafsson clamps a background sample's size to 2x the centre's, a deliberately "unphysical" hack).
3. **Disocclusion:** the background hidden behind a blurry foreground edge is unknown in a single image; it must be extrapolated (pyramidal hole filling: Kraus and Strengert, "Depth-of-Field Rendering by Pyramidal Image Processing", Computer Graphics Forum 26(3):645-654, Eurographics 2007, DOI 10.1111/j.1467-8659.2007.01088.x, which use GPU pyramid methods for blurring and for filling occluded pixels and compare against distributed ray tracing), or rendered in layers.
4. **Intensity leakage in scatter:** splatted sprites must be normalised and depth-ordered, or a slightly blurred object bleeds over a very blurred one (reader reports on Wronski's Witcher 2 sprite bokeh, https://bartwronski.com/2014/04/07/bokeh-depth-of-field-going-insane-part-1/).

**Discrete pipeline (typical real-time).** (1) CoC from depth (signed, in pixels, clamped to a max); (2) downsample colour to half resolution with a CoC-aware prefilter (and premultiply near/far weights); (3) tile pass: max |CoC| and min depth per 8 x 8 or 16 x 16 tile, then a 3 x 3 neighbour max (as in 1.6); (4) gather near and far layers with the chosen kernel (disc 2.1, hexagon 2.3, complex separable 2.4 or stochastic 2.5), weights by scatter-as-gather tests; (5) optional 3 x 3 median/max to clean undersampling; (6) upsample and composite near over (focus mixed with far) using alpha from CoC. Extra: highlight boosting or HDR input for bright bokeh; sprite scatter for the brightest pixels only (Pettineo 2011 "How To Fake Bokeh (And Make It Look Pretty Good)", UNVERIFIED title; Wronski 2014 describes Witcher 2's per-half-res-pixel sprite scatter at "up to 10 ms" on GPUs of the time and 11 ms full-screen on a GTX Titan).

**Frequency response.** No global MTF. Within one depth layer (constant CoC c) it is the aperture's MTF (for a disc of diameter c, a jinc whose first zero is at rho = 0.6098/(c/2) = 1.2197/c cycles/px). The app should show a map of |CoC| and the local MTF at the probe pixel.

**Key properties.** Linear in colour for a fixed depth map; shift-variant; occlusion-dependent (scatter version) or not (naive gather); positive weights; isotropic per pixel for round apertures; not separable (even the separable kernels of 2.3/2.4 are only exact for constant CoC); depth-order dependent.

**Algorithms and complexity summary.** Naive gather O(c_max^2) per pixel; separable hex/complex O(c_max); stochastic O(S); pyramidal O(1) per pixel with layer blending (Kraus and Strengert 2007); summed-area-table variable box O(1) per pixel (Hensley et al., "Fast Summed-Area Table Generation and its Applications", Eurographics 2005; REFERENCE, standard) but box-shaped bokeh; scatter O(sum c^2) fill; FFT not applicable to varying CoC except per depth layer (layered FFT DoF). Ground truth: accumulation over many lens samples (1.7) or ray tracing.

**GPU implementation notes for the app.** The procedural test scenes must carry a depth buffer: (a) a tilted plane of point lights (CoC varies smoothly), (b) a sharp foreground bar in front of blurred lights (tests foreground bleeding and haloes), (c) a blurry foreground bar in front of a sharp checkerboard (tests the missing-foreground-bleed problem), (d) the Siemens star on a plane at known depth. Use half-resolution near/far layers and a tile max-CoC pass, as above; on an A17 Pro a 49-tap half-resolution gather at 1170 x 2532 is ~0.74 M pixels x 49 = 36 M fetches per frame. MODELED.

**Visual fingerprint.** Unique: blur that **follows depth**: a sharp focal plane, blur growing faster in front than behind, bokeh size encoding distance; at object boundaries the quality of the method shows (sharp-edged blurry foregrounds and coloured haloes are the tell-tales of a naive gather; missing background is the tell-tale of any single-layer method). Best test: the depth scenes above, especially (b) and (c).

**Where used.** Every modern game engine (Unreal cinematic DoF with procedural bokeh and blade count; Unity HDRP physical DoF; Frostbite; Call of Duty), Photoshop Lens Blur with a depth map (Blur Focal Distance), smartphone Portrait/Cinematic modes (depth from dual pixels/stereo/LiDAR/ML; INFERRED internals), Core Image `CIDepthBlurEffect` (exists on Apple platforms; its parameters were not read for this file: UNVERIFIED), GPU Gems 3 ch. 28, Earl Hammon, "Practical Post-Process Depth of Field" (Call of Duty 4; https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-28-practical-post-process-depth-field). Historical origin of post-process DoF: Potmesil and Chakravarty, "A Lens and Aperture Camera Model for Synthetic Image Generation", SIGGRAPH 1981 (REFERENCE, standard, not re-read).

**Signature:** "Blur from depth: the circle of confusion grows with the difference of inverse depths, and the hard part is not the blur but the edges where near and far meet."

### 3.2 tilt-shift (gradient CoC, miniature effect)

- **Name and aliases:** tilt-shift blur, fake tilt-shift, miniature effect, diorama effect, Photoshop Blur Gallery "Tilt-Shift", linear/radial focus blur (Instagram-style). Family: spatially varying (mask-driven CoC), linear.

**Physical basis.** A real tilt lens tilts the plane of sharp focus relative to the sensor (Scheimpflug principle), so the in-focus region becomes a wedge through the scene; tilting it "against" the subject plane makes the sharp band on a receding ground plane very narrow. The fake version assumes the scene is a plane (ground seen from above): **for any plane in front of a pinhole camera, inverse depth is an affine function of image position**, 1/z = alpha x + beta y + gamma. Combined with c proportional to |1/S1 - 1/z| (3.1), the CoC of a planar scene is |affine function of (x, y)|: a V-shaped linear ramp that is zero along one line in the image. COMPUTED (projective geometry + thin lens). That is exactly what the fake does, which is why it is so convincing.

**Why it looks like a miniature.** Strong blur gradients in a photo imply a short camera-to-scene distance relative to the aperture, so the visual system reads the scene as small. Held, Cooper, O'Brien and Banks, "Using Blur to Affect Perceived Distance and Size", ACM TOG 29(2), 2010 (REFERENCE, standard; not re-read) showed this experimentally.

**Continuous definition (fake).** Focus line through point p0 with unit normal n (perpendicular to the band), half-width w of the sharp band, transition width t (Photoshop draws solid lines for the band edges and dashed lines where full blur is reached), maximum blur R_max:

    d(x) = |n . (x - p0)|
    R(x) = R_max * clamp((d(x) - w) / t, 0, 1)        (or a linear ramp with no upper clamp, which is the physical planar-scene case)

then g = variable disc/Gaussian blur with radius field R(x) (3.3). A "radial" (elliptical) variant uses d(x) = elliptical distance from a centre (Photoshop "Iris Blur").

**Parameters.** Band position, angle, width, transition, max blur; Photoshop Tilt-Shift also has "Distortion" and "Symmetric Distortion" (bokeh shape is stretched in the lower or both zones) and the Blur Gallery's shared Effects (Light Bokeh, Bokeh Color, Light Range) (from memory of Photoshop CS6+, the Adobe page returned 403 to this agent: UNVERIFIED wording). Equivalent per-pixel sigma: R/2 for a disc kernel, or the Gaussian sigma directly.

**Frequency response.** No global MTF. Local MTF varies only with d(x): bands parallel to the focus line share one local MTF. In a planar-scene model the local blur scales linearly with distance from the focus line, like zoom blur's linear growth but isotropic and one-dimensional in its variation.

**Key properties.** Linear, shift-variant (but invariant along the focus line's direction), positive, isotropic per pixel (for disc/Gaussian kernels), no occlusion handling (no depth buffer: objects standing up from the plane get the plane's blur, a giveaway of the fake).

**Algorithms and GPU.** Any variable-radius method (3.3); because R depends on one coordinate only (after rotating so the band is horizontal), a **row-wise blur pyramid** is natural: rows at the same d share a radius, so a separable Gaussian with per-row sigma is *exact* for the horizontal pass and only approximate for the vertical pass (sigma changes across the vertical support). Cost: O(1) with mip interpolation, O(R) with separable per-row blur. MODELED.

**Visual fingerprint.** Unique: one sharp band (or ellipse), blur increasing linearly to both sides, the whole scene looking like a toy model; strong saturation/contrast boosts are usually added. Tells of the fake: tall objects crossing the band are sharp at the base and blurred at the top even though they are at one depth. Best test: an aerial-style procedural city grid or checkerboard ground plane, plus text crossing the band.

**Where used.** Photoshop Blur Gallery Tilt-Shift and Iris Blur (introduced with the Blur Gallery in Photoshop CS6, 2012; UNVERIFIED date), Instagram's tilt-shift tool (linear and radial), iOS/Android photo apps, tilt-shift time-lapse videos; real tilt-shift lenses (architecture, product photography).

**Signature:** "A depth of field for a world that is a flat plane: blur grows linearly from a focus line, and the brain concludes the city is a toy."

### 3.3 variable-progressive-blur (mask-driven radius; CIMaskedVariableBlur; progressive blur UI; mip interpolation)

- **Name and aliases:** variable blur, masked blur, spatially varying Gaussian, progressive blur (UI), gradient blur, "Field Blur" (Photoshop: several pins each with its own blur, interpolated), `CIMaskedVariableBlur`, CSS "progressive blur", iOS variable blur (private `CAFilter` type used by system UI and community packages). Family: spatially varying, linear (for a fixed mask).

**Continuous definition.** A radius (or sigma) field s(x), usually s(x) = s_max * m(x) with a grey mask m in [0, 1]. Two non-equivalent definitions (section 0):
- **Gather:** g(x) = integral G_{s(x)}(x - y) f(y) dy (each output pixel uses its own radius). Normalised by construction; a sharp-mask edge produces an abrupt change in blur *in the output*.
- **Scatter:** g(x) = integral G_{s(y)}(x - y) f(y) dy (each source pixel spreads by its own radius). Conserves energy (sum of output = sum of input) but is not normalised per output pixel (brightness can change near radius gradients) and blurred pixels spill into the sharp region.
- **Diffusion (PDE):** solve df/dt = div(c(x) grad f) for time T: smoothly varying, energy-conserving, symmetric operator, but its local PSF is not a simple Gaussian near gradients of c.

**Apple's public filter (REFERENCE, Core Image Filter Reference archive):** `CIMaskedVariableBlur`, "Blurs the source image according to the brightness levels in a mask image", inputs `inputImage`, `inputMask`, `inputRadius` (default 10; slider 0-100); "Shades of gray in the mask image vary the blur radius from zero (where the mask image is black) to the radius specified in the inputRadius parameter (where the mask image is white)"; OS X 10.10+ (iOS availability of the named filter not stated on that page; `CIFilter.maskedVariableBlur()` exists in the CIFilterBuiltins API; first iOS version UNVERIFIED). **How Core Image implements it is not documented: INFERRED** (a plausible guess is a pyramid of blurred images interpolated by mask value). The app can test this live: blur an impulse grid under a constant mask of 0.25, 0.5 and 0.75, fit sigma and the kurtosis of the PSF; a mip-interpolated implementation shows the mixture signature computed below (kurtosis ~4.5 instead of 3 halfway between levels), a true per-pixel Gaussian shows 3.

**Progressive blur in UI (the "trend").** A blur whose radius ramps from 0 to a maximum across a bar or the top/bottom edge of scrolling content, replacing the hard edge of a uniform material blur. On iOS 26+, SwiftUI's `ScrollEdgeEffectStyle.soft` is described by Apple as "a subtler blurred boundary" that becomes more opaque towards the edge (versus `.hard`, a nearly opaque boundary), applied by `scrollEdgeEffectStyle(_:for:)` (REFERENCE: https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle ; whether it is implemented as a true variable-radius blur or a fixed blur faded by a mask is not documented: INFERRED, measurable on device by rendering an impulse grid under a scroll edge and photographing with `ImageRenderer`/screenshots). Apple's own variable blur is a private Core Animation filter (`CAFilter` "variableBlur" with a mask image and radius) that community packages use with explicit App Store rejection warnings: jtrivedi/VariableBlurView (original), aheze/VariableBlurView ("use at your own risk"), nikstar/VariableBlur, oblador/react-native-variable-blur; TimOliver/BlurUIKit copies the filter from a public `UIVisualEffectView` instead (REFERENCE: those repositories' READMEs as summarised by search; key names UNVERIFIED). On the web, progressive blur is faked with **several stacked `backdrop-filter: blur()` layers**, each masked by a `linear-gradient` band, with radii stepping geometrically (e.g. 0.5 px to 64 px across ~8 layers) (REFERENCE: community write-ups and components, e.g. https://www.mintlify.com/SikandarJODD/animations/components/progressive-blur and Framer's ProgressiveBlur component). Blur2ool cannot use the private API (App Store and honesty rules); it should implement its own variable blur in Metal and label Apple's as INFERRED.

**Efficient variable-radius algorithms (per pixel cost, errors).**
1. **Per-pixel gather with radius-dependent taps:** exact gather semantics; cost O(s(x)^2) (2-D) or O(s(x)) when approximated with two 1-D passes using the per-pixel sigma. The separable version is exact only where s is constant across the kernel support; where s changes quickly, the horizontal and vertical passes see different sigmas and the PSF becomes a non-Gaussian, slightly anisotropic blob. COMPUTED (reasoning).
2. **Mip / pyramid interpolation (O(1)):** build a Gaussian pyramid, level k having sigma_k = sigma_0 2^k (each level blurred properly before 2x decimation), and sample at fractional LOD l = log2(s/sigma_0) with trilinear filtering: K = (1 - t) G_{sigma_k} + t G_{2 sigma_k}, t = frac(l). Cost: 2 bilinear lookups (8 texels) per pixel, plus ~4/3 of a pass to build the pyramid. Errors, COMPUTED (probe7.py, per axis):
   - The blend of two Gaussians is a **mixture, not a Gaussian**: with the naive weight t its sigma is 11.2% / 11.8% / 7.2% too wide at t = 0.25 / 0.5 / 0.75. A **variance-matched** weight t' = (4^t - 1)/3 fixes the width (t = 0.5 -> t' = 1/3).
   - Even variance-matched, the shape is wrong: kurtosis 4.61 / 4.50 / 3.80 (Gaussian: 3), a peak 11-18% higher and an L1 profile error of 0.10-0.15: a sharp core with a wide skirt, seen as a faint "glow" around edges and as visible pulsing when the radius animates through levels.
   - Bilinear magnification of coarse levels shows a grid/diamond pattern (a 2^k-decimated image upsampled bilinearly has tent-shaped interpolation kernels 2^(k+1) wide); smooth B-spline (bicubic) upsampling or a dual-filter (Kawase-style) upsample chain hides it.
3. **Discrete layers + mask blending (O(L)):** blur the image at L fixed radii (often geometric, e.g. 1, 2, 4, ... px) and blend the two nearest by mask value; this is the CSS stacked-layer method and the most likely shape of many UI implementations (INFERRED). Same mixture error as (2) without the pyramid's resampling error; cost L full blurs (cheap for downsampled blurs).
4. **Summed-area table variable box (O(1)):** 4 fetches per pixel for a box of any half-width (Crow, "Summed-Area Tables for Texture Mapping", SIGGRAPH 1984; Hensley et al. 2005 for GPU construction); box shape (use 2-3 iterated SATs or a SAT of a SAT for tent/quadratic shapes). Precision: a 1170 x 2532 image with mean 0.5 sums to ~1.48 M, where the fp32 spacing is 0.125, far coarser than one 8-bit step (0.0039), so fp32 SATs are unusable at full resolution without tricks; integer SATs of 8-bit data fit in uint32 (max 7.6e8 < 4.3e9), or subtract the mean / work in tiles. COMPUTED (probe7.py).
5. **Recursive (IIR) Gaussian with per-pixel coefficients:** O(1) per pixel for any sigma; spatially varying coefficients make it causal-asymmetric and only approximately Gaussian near sigma changes (UNVERIFIED: no standard reference checked).
6. **Stochastic sampling:** S samples scaled by s(x) (2.5); noise, any shape.

**Frequency response.** No global MTF; local MTF is the Gaussian (or disc) of the local radius; the method-dependent PSF shape (mixture kurtosis, box from SAT) changes the local MTF's tail: a mixture's MTF is the same-weight mixture of two Gaussian MTFs, which falls slower at high frequency than the matching Gaussian (more residual fine detail visible through the blur). COMPUTED (linearity of the Fourier transform).

**Key properties.** Linear for a fixed mask; shift-variant; positive; gather version normalised but not energy conserving, scatter version energy conserving but not normalised; isotropic per pixel; no semigroup (blurring twice with masks m1 and m2 is not one blur with any mask, except for constant masks).

**Visual fingerprint.** Unique: blur strength **follows a painted mask or gradient**, independent of image content; in UI, content dissolves progressively into the bar instead of being cut off by a hard material edge. Method tells: mip-interpolated blurs "breathe" (non-monotone softness) and glow as the radius animates; layered blurs show faint bands where layers meet; gather vs scatter differ at mask edges (gather keeps the sharp side clean; scatter spills blurred colour into it). Best test: a horizontal ramp mask over a checkerboard and over text (shows banding and method), an impulse grid under a ramp (shows the PSF growing smoothly or in steps), the Siemens star under a radial mask.

**Where used.** Core Image `CIMaskedVariableBlur`; iOS system UI and SwiftUI scroll-edge effects (iOS 26+, implementation INFERRED); Photoshop Blur Gallery (Field Blur, Iris Blur, Tilt-Shift are all variable blurs driven by on-canvas pins/shapes); CSS progressive-blur components; game DoF (3.1) and tilt-shift (3.2) are its depth- and line-driven special cases.

**Signature:** "The blur radius becomes an image of its own: a mask decides how blurred each pixel is, and the cheap ways of doing that (mip levels, stacked layers) leave a mixture of blurs you can measure."

---

## 4. Comparison table (fingerprints)

LSI = linear shift-invariant. "Zeros/neg." = whether the (local) MTF has exact zeros and negative lobes (contrast inversion). Costs are fetches per output pixel for the best practical GPU method named in the section (L = streak length, R = radius, S = samples, N = taps, k = passes).

| id | LSI? | local PSF | MTF: zeros / negative lobes | separable? | best practical cost | signature artifact | best test image |
|---|---|---|---|---|---|---|---|
| linear-motion-blur | yes | hard-ended line | zero lines at k/L, min -0.217 | only at 0/90 deg | L+1 (gather) or 2 log2 L (doubling) | ghost copies when undersampled; inverted stripes | Siemens star, zone plate, impulse |
| anisotropic-gaussian | yes | soft ellipse | none / none | sheared-separable (Geusebroek 2003) | 2 x 3 sigma, or O(1) IIR | none; monotone smear | Siemens star vs 1.1 |
| kawase-streak | yes per arm (thresholded) | one-sided exponential rays | none / none, non-zero phase | no | 4k per arm for 4^k px | fixed-angle rays from highlights only | night-city lights |
| camera-shake-blur | approx. (translation) | squiggle with bright knots | irregular near-zeros, complex phase | no | sparse kernel taps ~K..3K | doubled edges, squiggle highlights | night-city lights, text |
| shutter-function-blur | yes (const. velocity) | shutter profile along motion | box: zeros; coded: none | 1-D along motion | N along motion | dashed "barcode" streaks (coded) | moving point light, zone plate |
| velocity-buffer-motion-blur | no (per-pixel V, Z) | line along own/neighbour velocity | local sinc-like | no | ~3S + 4 (S = 5..15) + tile passes | tile-sized under-blur, noise at low S | moving object over checkerboard |
| temporal-accumulation | no (exact space-time) | whatever moved through the pixel | per-region sinc; aliases with few frames | n/a | N full renders (or 1 history fetch for EMA) | discrete ghosts; EMA comet trails | rotating star rendered as N sub-frames |
| radial-zoom-blur | no (LSI in log-polar) | radial segment, length a r | local zero lines at 1/(a r) | no | 2k (doubling) or a r_max | rings/ghosts near corners | centred Siemens star (untouched) vs zone plate (smeared) |
| spin-blur | no (LSI in polar) | arc, length r Theta | angular sinc(m Theta/2pi) at all radii | no | 2k (doubling) or r_max Theta | rim ghosts; star greys at 360/n deg | centred Siemens star (vanishes) vs zone plate (untouched) |
| path-blur | no | curved streamline segment | local sinc / curve spectrum | no | ~3 L/h (RK2 LIC) | tears where flow fields meet | impulse grid, checkerboard |
| disc-bokeh | yes | flat hard-edged disc | zero circles at 0.6098/R, min -0.132 | no | 2(2R+1) (row spans) or pi R^2 | flat bokeh balls; inversion ring | night-city lights, Siemens star ring at 0.261 n R |
| defocus-frequency-domain | yes | disc (geometric) / Hopkins (wave) | zero rings, spurious resolution | no | (as 2.1) | detail returns phase-reversed | zone plate, Siemens star |
| polygonal-bokeh | yes | hexagon / octagon | non-circular zeros, edge-normal streaks | skewed 1-D boxes (zonogons only) | 4n (hexagon, 2 passes) | rhombus seams; no odd-bladed shapes | night-city lights, impulse |
| circular-separable-bokeh | yes | disc with ripple (+-23% / +-7.6%) | near-jinc, smooth | yes (complex) | (2R+1)(1 + C) reads | faint concentric ripple, dark rim ring | single HDR light, zone plate |
| stochastic-bokeh | in expectation | S dots in a disc/any shape | expected jinc + noise/aliases | no | S (16-400) | grain, spiral texture | lights at S = 16 vs 400 |
| cats-eye-swirl-bokeh | no | almond, tangential, shrinking off-axis | local anisotropic | no | S + 2 ALU per sample | bokeh shape rotates with position; swirl | full-frame grid of lights |
| diffraction-airy | yes (isoplanatic) | Airy core + rings (+ spikes) | no negative lobes; hard cutoff 1/(lambda N) | square pupil only | FFT or small gather | rings, spikes, grows when stopped down | HDR point lights, zone plate |
| anamorphic | yes per radius | tall ellipse (+ horizontal streak) | elliptical zero rings | complex-kernel form yes | as 2.4 / 2.5 | vertical ovals, horizontal flares | night-city lights |
| depth-of-field-coc | no (depth-driven, occlusion) | aperture shape scaled by CoC(z) | per-layer jinc | no | 49-tap half-res gather + tiles | sharp blurry-foreground edges, haloes | foreground bar over lights, tilted plane |
| tilt-shift | no (line-driven) | disc/Gaussian, radius linear in distance from band | per-band | per-row exact horizontally | O(1) mip or O(R) | tall objects blurred at the top only | aerial grid / checkerboard plane |
| variable-progressive-blur | no (mask-driven) | Gaussian of local radius (or mixture) | per-pixel; mixture tails | approx. | 8 texels (mip) / 4 (SAT) | mip "breathing", layer bands | ramp mask over text and impulses |

**Size conventions (all COMPUTED).** Box/line of length L: sigma_eq = L/sqrt(12) = 0.2887 L. Velocity-buffer half-velocity |V|: sigma_eq = 0.577 |V|. Uniform disc of radius R (CoC diameter c = 2R): sigma_eq = R/2 = c/4. Regular hexagon of circumradius R: sigma_eq = 0.456 R. Zoom blur at distance r with strength a: a r/sqrt(12). Spin blur at radius r with angle Theta: r Theta/sqrt(12). Airy pattern: FWHM 1.029 lambda N, Gaussian sigma ~0.42-0.44 lambda N. These give the app one common axis ("equivalent sigma") on which to compare every blur's strength, while the PSF/MTF plots show how they differ at equal sigma.

**Equal-sigma "uniqueness" demo (recommended for the app).** At the same sigma_eq, show line (1.1), elliptical Gaussian (1.2), disc (2.1), hexagon (2.3), complex-separable disc (2.4) and Airy (2.7) side by side on the zone plate: only the box and disc families produce grey zero rings and inverted bands; the Gaussian and Airy never invert; the hexagon's rings are hexagonal; the separable disc shows its ripple. On a centred Siemens star, spin and zoom blurs are perfect duals (one destroys it at 360/n degrees, the other leaves it untouched).

---

## 5. Sources

Primary sources read (fully or in the cited parts) for this file:
- McGuire, Hennessy, Bukowski, Osman. "A Reconstruction Filter for Plausible Motion Blur". I3D 2012, pp. 135-142. https://casual-effects.com/research/McGuire2012Blur/McGuire12Blur.pdf
- Garcia, K. "Circular Separable Convolution Depth of Field". SIGGRAPH 2017 Talks, DOI 10.1145/3084363.3085022. https://history.siggraph.org/wp-content/uploads/2022/09/2017-Talks-Garcia_Circular-Separable-Convolution-Depth-of-Field.pdf
- Niemitalo, O. "Circularly symmetric convolution and lens blur". 2010. http://yehar.com/blog/?p=1495
- Gustafsson, D. "Bokeh depth of field in a single pass". 4 May 2018. https://blog.voxagon.se/2018/05/04/bokeh-depth-of-field-in-single-pass.html
- Barre-Brisebois, C. "Hexagonal Bokeh Blur Revisited" parts 1 and 2. 2017. https://colinbarrebrisebois.com/2017/04/18/hexagonal-bokeh-blur-revisited/
- Apple. Core Image Filter Reference (archive): CIZoomBlur, CIMotionBlur, CIDiscBlur, CIMaskedVariableBlur, CIBoxBlur. https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html
- Apple. CIBokehBlur and `CIFilter.bokehBlur()` (iOS 13+, macOS 10.15+). https://developer.apple.com/documentation/coreimage/cibokehblur
- Apple. SwiftUI `ScrollEdgeEffectStyle` (`.soft`, `.hard`). https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle
- Wikipedia. "Circle of confusion" (thin-lens CoC formula, limits). https://en.wikipedia.org/wiki/Circle_of_confusion
- Wikipedia. "Diffraction spike" (n vs 2n spikes rule). https://en.wikipedia.org/wiki/Diffraction_spike
- NVIDIA GameWorks. "Motion Blur Advanced" OpenGL sample documentation (K ~ 20, S ~ 15). https://archive.docs.nvidia.com/gameworks/content/gameworkslibrary/graphicssamples/opengl_samples/motionblurgl4gles3advancedsample.htm
- Wronski, B. "Bokeh depth of field - going insane! part 1". 2014. https://bartwronski.com/2014/04/07/bokeh-depth-of-field-going-insane-part-1/
- Unity. Physical camera reference (Blade Count, Curvature, Barrel Clipping, Anamorphism). https://docs-alpha.unity3d.com/Manual/urp/cameras/physical-camera-reference.html ; HDRP Depth of Field https://docs.unity3d.com/Packages/hdrp/manual/Post-Processing-Depth-of-Field.html
- Epic Games. "Cinematic Depth of Field in Unreal Engine". https://dev.epicgames.com/documentation/unreal-engine/cinematic-depth-of-field-in-unreal-engine

Bibliographic records verified (abstract or citation seen, full text not read):
- McIntosh, L., Riecke, B. E., DiPaola, S. "Efficiently Simulating the Bokeh of Polygonal Apertures in a Post-Process Depth of Field Shader". Computer Graphics Forum 31(6):1810-1822, 2012. DOI 10.1111/j.1467-8659.2012.02097.x. https://diglib.eg.org/handle/10.1111/v31i6pp1810-1822
- White, J., Barre-Brisebois, C. "More Performance! Five Rendering Ideas from Battlefield 3 and Need For Speed: The Run". SIGGRAPH 2011 Advances in Real-Time Rendering. https://www.slideshare.net/slideshow/five-rendering-ideas-from-battlefield-3-need-for-speed-the-run/8907879
- Kawase, M. CEDEC 2009 separable hexagonal bokeh (7 passes), via https://lousodrome.net/blog/light/?p=116
- Kraus, M., Strengert, M. "Depth-of-Field Rendering by Pyramidal Image Processing". CGF 26(3):645-654, 2007. https://diglib.eg.org/handle/10.2312/CGF.v26i3pp645-654
- Jimenez, J. "Next Generation Post Processing in Call of Duty: Advanced Warfare". SIGGRAPH 2014 Advances course. http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/ (content via third-party notes)
- Guertin, McGuire, Nowrouzezahrai. "A Fast and Stable Feature-Aware Motion Blur Filter". HPG 2014. https://research.nvidia.com/publication/2013-11_fast-and-stable-feature-aware-motion-blur-filter
- Hopkins, H. H. "The Frequency Response of a Defocused Optical System". Proc. R. Soc. A 231(1184):91-103, 1955.
- Yellott, J. I., Yellott, J. W. "Correcting spurious resolution in defocused images". Proc. SPIE 6492, 2007. https://opticalengineering.spiedigitallibrary.org/conference-proceedings-of-spie/6492/64920O/Correcting-spurious-resolution-in-defocused-images/10.1117/12.698240.full
- Hammon, E. "Practical Post-Process Depth of Field". GPU Gems 3 ch. 28, 2007. https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-28-practical-post-process-depth-field
- Stride engine `TripleRhombiBokeh`. https://doc.stride3d.net/4.0/en/API/Stride.Rendering.Images.TripleRhombiBokeh.html ; VTK `vtkHexagonalBokehBlurPass`. https://vtk.org/doc/nightly/html/vtkHexagonalBokehBlurPass_8h.html
- Photoshop Lens Blur: Adobe help "Create depth of field with Lens Blur" https://helpx.adobe.com/photoshop/desktop/effects-filters/blur-sharpen-filters/create-depth-of-field-with-lens-blur.html ; Path/Spin Blur tutorials: https://design.tutsplus.com/tutorials/quick-tip-using-the-path-blur-and-spin-blur-in-photoshop-cc-2014--cms-21250 , https://planetphotoshop.com/using-the-path-blur-in-photoshop.html , https://www.tipsquirrel.com/photoshop-blur-gallery-path-blur/
- Variable-blur packages: https://github.com/aheze/VariableBlurView (and jtrivedi/VariableBlurView), https://swiftpackageregistry.com/nikstar/VariableBlur , https://github.com/oblador/react-native-variable-blur , https://github.com/TimOliver/BlurUIKit/wiki
- Anamorphic practice: https://www.indepthcine.com/videos/anamorphic-squeeze , https://filmdaft.com/a-beginners-guide-to-anamorphic-lenses/ , https://www.adorama.com/alc/anamorphic-lens
- Cat's eye / Petzval practice: https://phillipreeve.net/blog/review-lomography-petzval-55mm-f-1-7-bokeh-control-mark-ii-art-lens/ , https://richardrosenman.com/elevating-photorealism-why-cats-eye-bokeh-optical-vignetting-are-essential-for-after-effects-compositors/

Standard references cited from knowledge (not re-read in this session; treat titles/years as reliable, details as REFERENCE-from-memory): Haeberli and Akeley 1990 (accumulation buffer); Potmesil and Chakravarty 1981 (lens and aperture camera model); Crow 1984 (summed-area tables); Hensley et al. 2005 (GPU SAT); Cabral and Leedom 1993 (LIC); Stalling and Hege 1995 (fast LIC); Mitchell 2007 (GPU Gems 3 ch. 13, volumetric light scattering); Rosado 2007 (GPU Gems 3 ch. 27, motion blur as a post-process); Fergus et al. 2006 (removing camera shake); Whyte et al. 2010/2012 (non-uniform deblurring); Levin et al. 2009 (blind deconvolution evaluation); Levin et al. 2007 (coded aperture); Raskar, Agrawal, Tumblin 2006 (flutter shutter); Geusebroek, Smeulders, van de Weijer 2003 (fast anisotropic Gauss); Heckbert 1989 (EWA); Airy 1835; Lee and Mittra 1983 (polygon Fourier transform); Vogel 1979 (sunflower spiral); Shirley and Chiu 1997 (concentric disc map); Held, Cooper, O'Brien, Banks 2010 (blur and perceived size); Lee, Eisemann, Seidel 2010 (real-time lens blur effects); Spencer et al. 1995 and Ritschel et al. 2009 (glare); Karis 2014 (temporal AA); Nah, Kim, Lee 2017 (GoPro deblurring dataset).

---

## 6. UNVERIFIED list (claims I could not confirm; do not put these on screen as REFERENCE)

1. What `CIMotionBlur.inputRadius` and `CIZoomBlur.inputAmount` mean in pixels (half-length, full length, or a scale fraction) and their weight profiles: undocumented, INFERRED; measure live with an impulse grid.
2. `CIBokehBlur` defaults and its ring model; `CIMaskedVariableBlur` internal algorithm (pyramid vs per-pixel); the first iOS version of `CIMaskedVariableBlur` by name; `CIDepthBlurEffect` parameters.
3. Whether SwiftUI's `.soft` scroll edge effect is a true variable-radius blur or a masked fixed blur; the private `CAFilter` "variableBlur" key names (`inputMaskImage`, etc.).
4. McIntosh, Riecke and DiPaola 2012: the exact separable construction (I recall combining blurred images, possibly a min/intersection for the octagon); the task brief's author list ("Nowrouzezahrai & Hachisuka") conflicts with the Eurographics record (McIntosh, Riecke, DiPaola), and the record was trusted.
5. BF3/Barre-Brisebois 2-pass hexagon: the relative normalisation of the two halves in pass 2 (my three-rhombi decomposition of the published passes is a reconstruction).
6. Kawase's original constants for streaks (4 taps per pass, attenuation ~0.9-0.95) and the DirectX 9 HDRLighting sample's star definitions; Kawase CEDEC 2009 slide contents.
7. Jimenez 2014 details (presort target format, 49 taps, toe function): known only via a third-party summary.
8. Photoshop: the exact mapping of Radial Blur "Amount" to degrees/scale and what "Quality" changes; Tilt-Shift "Distortion"/"Symmetric Distortion" and Blur Gallery bokeh panel wording; Blur Gallery introduction in CS6 (2012) and Path/Spin Blur in CC 2014 (the latter supported by tutorial titles); Shake Reduction's introduction version.
9. Camera-shake numbers: hand tremor ~8-12 Hz; the 1/focal-length hand-holding rule; Boracchi-Foi generator details; Levin et al. kernel size range.
10. iPhone 15 Pro Max main camera focal length (~6.86 mm) and pixel pitch (~1.22 um, 2.44 um binned) used in worked examples.
11. Airy best-fit Gaussian sigma ~0.42 lambda N (Zhang et al. 2007); the 0.437 lambda N FWHM-matched value is COMPUTED.
12. Soap-bubble bokeh attributed to overcorrected spherical aberration (Trioplan); the physical mechanism of Petzval swirl (field curvature + tangential vignetting is practitioner consensus, not a paper I read).
13. Product lineage claims: Unity/Unreal motion blur descending from McGuire 2012; Unreal "convolution bloom" (FFT) version; Teardown shipping Gustafsson's shader; Crysis sun shafts as radial blur; RSMB-style optical-flow motion blur; Apple Photos Long Exposure implementation.
14. GoPro dataset frame counts (7-13 frames at 240 fps) from Nah et al. 2017.
15. Stokseth 1969 and Hopkins 1955 contents (citations verified, texts not read); Cannon 1976 as the first spectral-stripe blur-identification paper.
16. Variable-coefficient recursive Gaussian behaviour near sigma changes (no reference checked).
17. Pettineo 2011 post title "How To Fake Bokeh (And Make It Look Pretty Good)".

<!-- STATUS: COMPLETE -->
