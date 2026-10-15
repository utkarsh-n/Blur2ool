# Live calibration: what Apple blur APIs actually do (MEASURED)

Status: complete (macOS pass). Date: 13 October 2026. Raw numbers: `Documentation/research/calibration-macos.json` (412 records).

## 1. Scope and honesty label

This document records what Apple's blur APIs actually do to pixels when you run them on this Mac. It covers SwiftUI `.blur(radius:)` (rendered offscreen through `ImageRenderer`), the Core Image blur filters, Metal Performance Shaders, vImage, and the four shadow APIs (`CGContext.setShadow`, `NSShadow`, `CALayer.shadowRadius`, SwiftUI `.shadow(radius:)`). For each API it fits the effective Gaussian σ, the support, the kernel shape, the working colour space, signs of downsampling and the border behaviour.

The app's WYSIWYG and API layers should show these numbers with the **MEASURED** badge. The badge should carry the platform. A figure measured on the Mac is "MEASURED (macOS 27.2, M1 Max)" until the phone repeats it with the code in section 7. Whatever the numbers suggest about how an API is built inside (for example "downsamples above radius N") is **INFERRED**. The docs do not state it.

## 2. Test machine and toolchain

| Item | Value |
|---|---|
| OS | macOS 27.2 (build 26B5101f), Darwin 27.2.0 (from `sw_vers`) |
| Machine | MacBookPro18,2, Apple M1 Max, 32-core GPU, 64 GB, Metal 4 |
| Display | Built-in Liquid Retina XDR (backing scale 2). Not used: all renders are offscreen at scale 1 |
| Toolchain | Xcode-beta 27.0 (27A5194q), Apple Swift 6.4 (swiftlang-6.4.0.20.104), MacOSX27.0 SDK, iPhoneSimulator27.0 SDK |
| Probe sources | `Blur2ool/Tools/calibrate/calibrate.swift` (macOS measurement), `Blur2ool/Tools/calibrate/MeasurePSF.swift` (iOS-ready function). Builds go to `$TMPDIR/blur2ool-calibration/` |

Every number in this document is **MEASURED on this Mac under macOS 27.2**. iOS 27 on A17 Pro may differ. SwiftUI, Core Animation and Core Image are separate builds per platform, and the GPU differs. Section 7 provides the code that repeats the measurement on the phone.

## 3. Method

The probe is `Tools/calibrate/calibrate.swift`: one self-contained file that uses only Apple frameworks. It builds with `swiftc -O -parse-as-library -swift-version 5 calibrate.swift -o $TMPDIR/blur2ool-calibration/calibrate`. Each API family runs as a separate process (`calibrate swiftui|swiftui-scale|swiftui-sweep|swiftui-format|ci|ci-sweep|mps|vimage|shadow|shadow-sweep <outdir>`; all ten ran in parallel in under a minute), so a crash in one family cannot lose the others. `calibrate merge <outdir>` then writes `calibration-macos.json`. `calibrate selftest` feeds exact sampled Gaussians and boxes through the analysers. It recovers σ = 1, 4, 16 to 4 decimal places, gives box excess kurtosis −1.2, and classifies both shapes correctly.

### 3.1 Test images

Every input is generated in code from exact values (0 or 1 per channel, alpha 1). Pixels are at **scale 1**: `ImageRenderer.scale = 1`, `CALayer.contentsScale = 1`, and Core Image, MPS and vImage are pixel-native. One point is therefore one pixel. A separate run at scale 2 and 3 checks how points map to device pixels (section 5.1).

| Test | Image | What it gives |
|---|---|---|
| Impulse | 1024², one white pixel at (512, 512) on black | 2-D PSF: centroid, σx, σy, principal axes, isotropic least-squares σ, contour radii along the axis and the diagonal, r(peak/255), r(1e-4·peak) |
| Vertical step | 2048 × 512, white for x ≥ 1024 + k, for k = 0…15 (sweeps: k = 0…3) | Edge spread function (ESF). Its derivative is the line-spread function (LSF), the PSF's marginal along x. The 16 edge phases test shift invariance. The analysis window is ±400 px, at least 600 px from any border |
| 45° step | 1024², white where x − y ≥ 0 | The marginal along the diagonal. Compared with the axis marginal, it separates separable kernels (box², box³) from isotropic ones (Gaussian, disc) |
| Stripes | 768², 1-px vertical black/white columns, central 64² averaged | Working colour space: the blurred mean is 0.500 in sRGB-encoded terms if the blur averages encoded values, and 0.735 if it averages linear light |
| Border | 256² all white, and the same with column 0 black, rendered with 16 px padding where the API can draw outside | Edge mode: transparent/zero padding vs clamp vs mirror, and whether the blur spills outside the view's bounds |
| Shadow band | 2048 × 512, white band x ∈ [100, 700) spanning the full height, shadow offset +1100 px in x | Shadow ESF on the alpha channel. The shadow's rising edge is at x = 1200, well away from the band |

The ESF is the main measurement for 8-bit pipelines. A single impulse blurred to σ = 64 peaks at 1/(2π·64²) ≈ 4·10⁻⁵, far below one 8-bit step. A step edge uses the full 0…255 range at every σ.

### 3.2 Readback

- **CGImage outputs** (SwiftUI, shadows) are drawn 1:1 with `.copy` blend into a 32-bit float `CGContext` whose colour space is either `extendedSRGB` (encoded) or `extendedLinearSRGB` (linear). CG performs any colour conversion, and the extended spaces keep negative lobes. 8-bit values come back as exactly v/255.
- **Core Image** renders with `CIContext.render(_:toBitmap:rowBytes:bounds:format: .RGBAf, colorSpace:)` into the same two spaces. Inputs are `CIImage(bitmapData:…format: .RGBAf, colorSpace: sRGB)`.
- **MPS** uses `rgba32Float` textures in shared storage, read back with `getBytes`. **vImage** uses Planar8 buffers. Neither is colour managed, so the raw values are the encoded values we uploaded. A linear readback decodes them with the sRGB EOTF.
- Every pipeline first renders a white top-left quadrant to detect a vertical flip, and corrects for one if found.
- Measurement space: the stripes test runs first. If it shows linear-light averaging, the ESF and PSF are read back in linear space. Otherwise they are read back in encoded space. Either way, the kernel is measured in the space where the blur actually summed.

### 3.3 Fits

- **Moment σ (ESF)**: the LSF is the first difference of the normalised ESF (0 → 1). σ² is its second central moment inside ±6σ of the centre (two passes), which keeps 8-bit noise in the far tails out of the sum. For a separable or isotropic PSF this equals the PSF's σx.
- **Least-squares σ**: the cumulative profile is fitted with Φ((t + ½ − μ)/s), a pixel-integrated Gaussian, by golden-section search on s. The reported value is the equivalent sampled σ = √(s² + 1/12), so it is directly comparable to the moment σ (the self-test agrees to 10⁻³).
- **2-D PSF**: centroid and covariance give σx, σy, σmajor, σminor and the angle. An isotropic Gaussian with closed-form amplitude is fitted by golden section on σ, with the RMS residual reported in % of peak. Contour radii at ½ and ⅒ of peak are measured along +x and along the 45° diagonal (bilinear sampling).
- **Support**: `esf.r255` is the visible extent of a hard black/white edge on an 8-bit display, the largest distance from the edge centre where the blurred edge is strictly between 1/255 and 254/255 (Gaussian: 2.66σ). `psf.r255` is where the PSF falls below peak/255 (Gaussian: 3.33σ). `psf.r1e4` is where it falls below 10⁻⁴·peak (Gaussian: 4.29σ). If r1e4 is much less than 4.29σ, the kernel is truncated.
- **Shape**: five one-parameter models are fitted to the cumulative marginal: Gaussian, box, tent (box²), box³ (Irwin–Hall n = 3) and disc (semicircle marginal). The RMS residual in % of full scale is reported for each. The excess kurtosis of the marginal also discriminates between them: Gaussian 0, box³ −0.4, tent −0.6, disc −1.0, box −1.2. Comparing the axis marginal with the 45° marginal separates isotropic kernels (identical) from separable ones (they differ).
- **Colour space**: the stripes mean in encoded terms (0.500 gamma, 0.735 linear). A second check is the encoded value of the two pixels either side of the step centre (`stepMidEncoded`).
- **Downsampling**: (i) shift variance, the change in fitted edge centre and σ as the step moves through 16 integer positions. An LTI filter at full resolution gives 0. A filter that decimates by 2ⁿ gives a phase-dependent response. (ii) Staircase, a periodicity score of |ΔLSF|. A piecewise-linear (bilinear-upsampled) ESF has a piecewise-constant LSF whose steps recur every 2ⁿ px.
- **Edge mode**: the value and alpha at column 0 of an all-white image (zero padding gives about 0.5 and alpha about 0.5; clamp gives 1). The value at column 0 when that column is black (clamp gives about 0.5, mirror or renormalisation stays near 1). The alpha 4 px outside the original bounds.

## 4. Results table

All values are **MEASURED on macOS 27.2 (26B5101f), MacBookPro18,2 (M1 Max), scale 1 (1 pt = 1 px)**. They may differ on iOS 27 and on A17 Pro. "σ" is the moment σ of the line-spread function from the vertical step, in pixels. "LSQ" is the least-squares erf fit, expressed as a sampled-equivalent σ. For non-Gaussian kernels (box, disc, tent) the two differ by design, and the moment σ is the one to quote. "Support" gives two numbers. The first is the visible extent r255, the distance from the edge centre at which a hard black/white edge is back within 1/255 of its plateau (a Gaussian gives 2.66σ). The second is the impulse-response radius where the PSF falls below 10⁻⁴ of its peak, divided by σ (an untruncated Gaussian gives 4.29). "–" means the impulse could not be measured (an 8-bit render whose blurred impulse peak is below 32/255) or does not apply. "Kurtosis axis / 45°" is the excess kurtosis of the PSF marginal along x and along the diagonal. They are equal for an isotropic kernel, and for a separable kernel the 45° value is half the axis value. "Stripes" is the sRGB-encoded mean of blurred 1-px black/white stripes: 0.500 means the blur averaged gamma-encoded values, and 0.735 means it averaged linear light. "Not flat" means the parameter was too small to average the stripes. "Shift-variant" means the fitted edge centre or σ changes as the edge moves across 16 integer pixel positions. A full-resolution linear shift-invariant filter shows 0.

### 4.0 Summary (one line per API)

| API | parameter → effective σ (MEASURED) | kernel shape | blends in | border (default) | full-resolution LTI? |
|---|---|---|---|---|---|
| SwiftUI `.blur(radius:)`, `ImageRenderer.cgImage` | σ ≈ 1.00·r while r·scale ≤ 5 px; σ = 0.90·r (0.896–0.909) above | small r: sampled Gaussian; r·scale ≥ 5.5: separable, box³-like (kurtosis −0.45), compact (to 1e-4 at 3.55σ) | gamma-encoded in `.nonLinear` (default); linear light in `.linear`/`.extendedLinear` | `opaque: false`: fades to transparent and spills outside the frame; `opaque: true`: opaque, clamp at r ≤ 4, not a plain clamp at r ≥ 8 | yes ≤ 5 px; **no** above (edge centre wobbles up to 1.2–1.4 px with grid phase) |
| SwiftUI `.blur`, `ImageRenderer.render(rasterizationScale:)` into a CGContext | σ = 0.98·r (0.979–0.998) | near-Gaussian, isotropic, 0.2% negative lobes | gamma-encoded | transparent, spills | yes ≤ 5 px; no above (same phase pattern) |
| SwiftUI `.shadow(radius:)` | σ ≈ 0.96·r | box³-like (kurtosis −0.5) | alpha mask | – | not tested |
| `CIGaussianBlur` | σ = r (0.994–1.007 for r ≥ 1) | isotropic Gaussian (residual ≤ 0.12% of peak); truncated at 4.2σ (σ 8) → 3.6σ (σ 64) | linear light (default context) | transparent; extent grows; clamp with `clampedToExtent()` | almost (≤ 0.1 px, ≤ 1.4% σ at some radii) |
| `CIBoxBlur` | square box of width W = 2⌈r/2⌉ − 1 px, so σ = √((W² − 1)/12) ≈ 0.29·r; r ≤ 2 gives no blur | separable square box | linear light | transparent | yes |
| `CIDiscBlur` = `CIBokehBlur` (defaults) | uniform disc of radius r (σ = r/2) | isotropic disc (kurtosis −1.0) | linear light | transparent | yes |
| `CIMotionBlur` | σ = r along `inputAngle`, 0 across | 1-px line, **Gaussian-weighted** (kurtosis ≈ 0), centred, two-sided | linear light | transparent | yes |
| `CIZoomBlur` | streak length ∝ distance from `inputCenter` (≈ 0.08·d at amount 4, ≈ 0.36·d at amount 16) | one-sided outward streak, near-uniform weights | (not measured) | – | no (space-variant by design) |
| `MPSImageGaussianBlur` | σ = sigma (0.993–1.037) | isotropic Gaussian, residual ≤ 0.07%, no truncation to 1e-4 | raw stored values | `.zero` (transparent) default; `.clamp` | yes |
| `MPSImageBox` / `vImageBoxConvolve` (kernel 2r+1) | σ = √(((2r+1)² − 1)/12) exactly | square box | raw stored values | MPS `.zero`; vImage per flag | yes |
| `MPSImageTent` / `vImageTentConvolve` (kernel 2r+1) | σ = √(((r+1)² − 1)/6) exactly | separable tent | raw stored values | MPS `.zero`; vImage per flag | yes |
| `CGContext.setShadow(blur: b)` = `NSShadow.shadowBlurRadius` | σ ≈ 0.44–0.47·b (b ≥ 3) | tent-like (kurtosis −0.6), visible extent ≈ b px | alpha mask | – | not tested |
| `CALayer.shadowRadius = r` (via `render(in:)`) | **identical to CG blur 2r** (Δσ = 0.000 at every tested r); σ ≈ 0.88–0.93·r | tent-like | alpha mask | – | not tested |

### 4.1–4.17 Per-API tables (σ parameter values 1, 2, 4, 8, 16, 32, 64)

**4.1 SwiftUI .blur(radius:), ImageRenderer .cgImage, colorMode .nonLinear (8-bit sRGB), opaque: false**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.994 / 0.994 | 0.994 | 2.0 · 2.94 | gaussian; -0.06 / -0.15 | gamma-encoded (0.500) | edge: zero/transparent |
| 2 | 2.002 / 1.996 | 1.001 | 5.0 · – | gaussian; 0.01 / -0.10 | gamma-encoded (0.500) | edge: zero/transparent (spills outside bounds) |
| 4 | 3.940 / 3.964 | 0.985 | 10.0 · – | gaussian; -0.14 / -0.11 | gamma-encoded (0.500) | edge: zero/transparent (spills outside bounds) |
| 8 | 7.245 / 7.472 | 0.906 | 16.0 · – | tent; -0.50 / -0.29 | gamma-encoded (0.524) | shift-variant: centre spread 1.21 px, σ spread 0.5%; edge: zero/transparent (spills outside bounds) |
| 16 | 14.417 / 14.818 | 0.901 | 33.0 · – | box3; -0.45 / -0.28 | gamma-encoded (0.521) | shift-variant: centre spread 1.19 px, σ spread 1.2%; edge: zero/transparent (spills outside bounds) |
| 32 | 28.982 / 29.805 | 0.906 | 67.1 · – | tent; -0.46 / -0.27 | gamma-encoded (0.509) | shift-variant: centre spread 1.18 px, σ spread 0.5%; edge: zero/transparent (spills outside bounds) |
| 64 | 57.685 / 59.247 | 0.901 | 131.9 · – | box3; -0.45 / -0.28 | gamma-encoded (0.512) | shift-variant: centre spread 1.20 px, σ spread 1.0%; edge: zero/transparent (spills outside bounds) |

**4.2 SwiftUI .blur(radius:opaque: true), same renderer**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.994 / 0.994 | 0.994 | 2.0 · 2.94 | gaussian; -0.06 / -0.15 | gamma-encoded (0.500) | edge: clamp |
| 2 | 2.002 / 1.996 | 1.001 | 5.0 · – | gaussian; 0.01 / -0.10 | gamma-encoded (0.500) | edge: clamp |
| 4 | 3.940 / 3.964 | 0.985 | 10.0 · – | gaussian; -0.14 / -0.11 | gamma-encoded (0.500) | edge: clamp |
| 8 | 7.245 / 7.472 | 0.906 | 16.0 · – | tent; -0.50 / -0.29 | gamma-encoded (0.524) | shift-variant: centre spread 1.21 px, σ spread 0.5%; edge: not clamp (mirror/renormalised) |
| 16 | 14.417 / 14.818 | 0.901 | 33.0 · – | box3; -0.45 / -0.28 | gamma-encoded (0.521) | shift-variant: centre spread 1.19 px, σ spread 1.2%; edge: not clamp (mirror/renormalised) |
| 32 | 28.982 / 29.805 | 0.906 | 67.1 · – | tent; -0.46 / -0.27 | gamma-encoded (0.509) | shift-variant: centre spread 1.18 px, σ spread 0.5%; edge: not clamp (mirror/renormalised) |
| 64 | 57.685 / 59.247 | 0.901 | 131.9 · – | box3; -0.45 / -0.28 | gamma-encoded (0.512) | shift-variant: centre spread 1.20 px, σ spread 1.0%; edge: not clamp (mirror/renormalised) |

**4.3 SwiftUI .blur(radius:), colorMode .extendedLinear (float16, linear)**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.996 / 0.997 | 0.996 | 3.0 · 4.26 | gaussian; -0.04 / -0.03 | linear-light (0.735) | edge: zero/transparent |
| 2 | 1.996 / 1.998 | 0.998 | 5.0 · 4.25 | gaussian; -0.03 / -0.02 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 4 | 3.920 / 3.957 | 0.980 | 10.0 · 3.97 | gaussian; -0.20 / -0.11 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 8 | 7.265 / 7.472 | 0.908 | 17.0 · 3.55 | tent; -0.47 / -0.23 | linear-light (0.751) | shift-variant: centre spread 1.19 px, σ spread 0.0%; edge: zero/transparent (spills outside bounds) |
| 16 | 14.482 / 14.875 | 0.905 | 34.0 · 3.58 | box3; -0.45 / -0.22 | linear-light (0.749) | shift-variant: centre spread 1.19 px, σ spread 0.6%; edge: zero/transparent (spills outside bounds) |
| 32 | 28.964 / 29.768 | 0.905 | 68.0 · 3.57 | box3; -0.46 / -0.23 | linear-light (0.740) | shift-variant: centre spread 1.19 px, σ spread 0.6%; edge: zero/transparent (spills outside bounds) |
| 64 | 57.725 / 59.290 | 0.902 | 135.0 · 3.54 | box3; -0.45 / -0.23 | linear-light (0.743) | shift-variant: centre spread 1.19 px, σ spread 0.5%; edge: zero/transparent (spills outside bounds) |

**4.4 SwiftUI .blur(radius:), colorMode .linear (8-bit; output re-tagged as sRGB, see 5.1)**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.989 / 0.999 | 0.989 | 3.0 · 3.63 | gaussian; -0.21 / -0.19 | linear-light (0.735) | edge: zero/transparent |
| 2 | 1.978 / 1.995 | 0.989 | 5.0 · – | gaussian; -0.15 / -0.14 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 4 | 3.917 / 3.945 | 0.979 | 10.0 · – | gaussian; -0.19 / -0.18 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 8 | 7.252 / 7.486 | 0.906 | 17.0 · – | tent; -0.50 / -0.25 | linear-light (0.751) | shift-variant: centre spread 1.17 px, σ spread 0.4%; edge: zero/transparent (spills outside bounds) |
| 16 | 14.481 / 14.875 | 0.905 | 34.0 · – | box3; -0.46 / -0.26 | linear-light (0.750) | shift-variant: centre spread 1.21 px, σ spread 0.9%; edge: zero/transparent (spills outside bounds) |
| 32 | 29.052 / 29.820 | 0.908 | 68.9 · – | tent; -0.45 / -0.25 | linear-light (0.742) | shift-variant: centre spread 1.23 px, σ spread 0.7%; edge: zero/transparent (spills outside bounds) |
| 64 | 57.363 / 59.104 | 0.896 | 133.7 · – | box3; -0.48 / -0.27 | linear-light (0.745) | shift-variant: centre spread 1.37 px, σ spread 1.1%; edge: zero/transparent (spills outside bounds) |

**4.5 SwiftUI .blur(radius:), ImageRenderer.render(rasterizationScale:) into a float CGContext**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.998 / 0.999 | 0.998 | 3.0 · 4.25 | gaussian; -0.05 / -0.03 | gamma-encoded (0.500) | edge: zero/transparent |
| 2 | 1.990 / 1.997 | 0.995 | 5.0 · 4.27 | gaussian; -0.09 / -0.04 | gamma-encoded (0.500) | edge: zero/transparent (spills outside bounds) |
| 4 | 3.962 / 3.986 | 0.991 | 10.0 · 4.28 | gaussian; -0.13 / -0.07 | gamma-encoded (0.500) | edge: zero/transparent (spills outside bounds) |
| 8 | 7.874 / 7.945 | 0.984 | 20.0 · 4.18 | gaussian; -0.19 / -0.09 | gamma-encoded (0.476) | shift-variant: centre spread 1.19 px, σ spread 0.0%; edge: zero/transparent (spills outside bounds); negative lobe 0.15% of peak |
| 16 | 15.718 / 15.881 | 0.982 | 40.0 · 4.16 | gaussian; -0.20 / -0.11 | gamma-encoded (0.476) | shift-variant: centre spread 1.19 px, σ spread 0.0%; edge: zero/transparent (spills outside bounds); negative lobe 0.18% of peak |
| 32 | 31.341 / 31.712 | 0.979 | 80.0 · 4.09 | gaussian; -0.23 / -0.12 | gamma-encoded (0.476) | shift-variant: centre spread 1.19 px, σ spread 0.0%; edge: zero/transparent (spills outside bounds); negative lobe 0.21% of peak |
| 64 | 62.625 / 63.399 | 0.979 | 160.0 · 4.07 | gaussian; -0.24 / -0.12 | gamma-encoded (0.476) | shift-variant: centre spread 1.19 px, σ spread 0.0%; edge: zero/transparent (spills outside bounds); negative lobe 0.20% of peak |

**4.6 CIGaussianBlur (inputRadius), default CIContext**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 1.037 / 1.040 | 1.037 | 3.0 · 4.09 | gaussian; -0.07 / -0.06 | linear-light (0.735) | edge: zero/transparent |
| 2 | 2.013 / 2.020 | 1.007 | 5.0 · 4.22 | gaussian; -0.09 / 0.03 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 4 | 4.000 / 4.009 | 1.000 | 10.0 · 4.25 | gaussian; -0.05 / -0.02 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 8 | 7.975 / 8.003 | 0.997 | 21.0 · 4.19 | gaussian; -0.08 / 0.25 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 16 | 15.943 / 15.980 | 0.996 | 42.0 · 4.06 | gaussian; -0.00 / 0.22 | linear-light (0.735) | shift-variant: centre spread 0.06 px, σ spread 1.1%; edge: zero/transparent (spills outside bounds) |
| 32 | 32.095 / 32.051 | 1.003 | 86.9 · 3.96 | gaussian; 0.04 / 0.42 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 64 | 63.871 / 64.017 | 0.998 | 170.9 · 3.57 | gaussian; -0.05 / -0.02 | linear-light (0.735) | shift-variant: centre spread 0.29 px, σ spread 1.2%; edge: zero/transparent (spills outside bounds) |

**4.7 CIBoxBlur (inputRadius)**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.000 / 0.293 | – | 0.0 · – | box; 0.00 / 0.00 | stripes not flat (0.500) | edge: clamp |
| 2 | 0.000 / 0.293 | – | 0.0 · – | box; 0.00 / 0.00 | stripes not flat (0.500) | edge: clamp |
| 4 | 0.759 / 0.807 | 0.190 | 1.4 · 1.73 | box; -0.62 / -0.61 | stripes not flat (0.724) | edge: zero/transparent |
| 8 | 1.999 / 2.230 | 0.250 | 3.0 · 2.12 | box; -1.25 / -0.63 | linear-light (0.733) | edge: zero/transparent |
| 16 | 4.322 / 4.796 | 0.270 | 7.0 · 2.29 | box; -1.21 / -0.60 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 32 | 8.948 / 9.916 | 0.280 | 15.0 · 2.37 | box; -1.20 / -0.60 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 64 | 18.192 / 20.157 | 0.284 | 31.0 · 2.41 | box; -1.20 / -0.60 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |

**4.8 CIDiscBlur (inputRadius); CIBokehBlur with default ring/softness is pixel-identical**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.629 / 0.672 | 0.629 | 1.4 · 2.05 | box; -0.66 / -0.47 | stripes not flat (0.726) | edge: zero/transparent |
| 2 | 1.040 / 1.112 | 0.520 | 2.0 · 2.15 | disc; -0.73 / -0.77 | linear-light (0.735) | edge: zero/transparent |
| 4 | 2.020 / 2.189 | 0.505 | 4.0 · 2.22 | disc; -0.95 / -0.94 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 8 | 4.010 / 4.353 | 0.501 | 8.0 · 2.12 | disc; -0.99 / -0.99 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 16 | 8.004 / 8.691 | 0.500 | 15.0 · 2.05 | disc; -1.00 / -0.99 | linear-light (0.734) | edge: zero/transparent (spills outside bounds); negative lobe 0.06% of peak |
| 32 | 15.990 / 17.373 | 0.500 | 31.1 · 2.32 | disc; -1.00 / -0.95 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 64 | 31.999 / 34.757 | 0.500 | 62.9 · 2.34 | disc; -1.00 / -0.95 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |

**4.9 CIMotionBlur (inputRadius, inputAngle 0): σ along the motion direction; σ across it is 0**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 1.040 / 1.041 | 1.040 | 3.0 · 2.89 | gaussian; -0.06 / -0.06 | linear-light (0.735) | edge: zero/transparent |
| 2 | 2.016 / 2.021 | 1.008 | 5.0 · 2.98 | gaussian; -0.07 / -0.07 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 4 | 3.904 / 3.923 | 0.976 | 10.0 · 3.38 | gaussian; -0.11 / -0.11 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 8 | 7.974 / 7.983 | 0.997 | 21.0 · 3.92 | gaussian; -0.03 / -0.03 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 16 | 15.883 / 15.962 | 0.993 | 42.0 · 3.85 | gaussian; -0.09 / -0.08 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 32 | 31.879 / 31.911 | 0.996 | 85.0 · 3.97 | gaussian; -0.03 / -0.02 | linear-light (0.735) | edge: zero/transparent (spills outside bounds) |
| 64 | 63.511 / 63.821 | 0.992 | 166.9 · 3.88 | gaussian; -0.09 / -0.07 | linear-light (0.735) | shift-variant: centre spread 0.09 px, σ spread 0.2%; edge: zero/transparent (spills outside bounds) |

**4.10 MPSImageGaussianBlur(sigma:), rgba32Float, edgeMode .zero (default)**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 1.037 / 1.039 | 1.037 | 3.0 · 4.09 | gaussian; -0.07 / -0.03 | gamma-encoded (0.500) | edge: zero/transparent |
| 2 | 2.010 / 2.019 | 1.005 | 5.0 · 4.22 | gaussian; -0.10 / -0.05 | gamma-encoded (0.500) | edge: zero/transparent |
| 4 | 3.991 / 4.006 | 0.998 | 10.0 · 4.25 | gaussian; -0.09 / -0.04 | gamma-encoded (0.500) | edge: zero/transparent |
| 8 | 7.955 / 7.994 | 0.994 | 21.0 · 4.19 | gaussian; -0.11 / -0.06 | gamma-encoded (0.500) | edge: zero/transparent |
| 16 | 15.888 / 15.968 | 0.993 | 42.0 · 4.22 | gaussian; -0.12 / -0.06 | gamma-encoded (0.500) | edge: zero/transparent |
| 32 | 31.942 / 31.997 | 0.998 | 85.0 · 4.31 | gaussian; -0.05 / -0.02 | gamma-encoded (0.500) | edge: zero/transparent |
| 64 | 63.664 / 63.957 | 0.995 | 167.0 · 4.25 | gaussian; -0.11 / -0.05 | gamma-encoded (0.500) | edge: zero/transparent |

**4.11 MPSImageBox(kernelWidth: 2r+1), param = r**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.816 / 0.949 | 0.816 | 1.0 · 1.73 | box; -1.50 / -0.75 | stripes not flat (0.500) | edge: zero/transparent |
| 2 | 1.414 / 1.589 | 0.707 | 2.0 · 2.00 | box; -1.30 / -0.65 | stripes not flat (0.500) | edge: zero/transparent |
| 4 | 2.582 / 2.872 | 0.645 | 4.0 · 2.19 | box; -1.23 / -0.62 | stripes not flat (0.500) | edge: zero/transparent |
| 8 | 4.899 / 5.434 | 0.612 | 8.0 · 2.31 | box; -1.21 / -0.60 | gamma-encoded (0.500) | edge: zero/transparent |
| 16 | 9.522 / 10.552 | 0.595 | 16.0 · 2.38 | box; -1.20 / -0.60 | gamma-encoded (0.500) | edge: zero/transparent |
| 32 | 18.762 / 20.788 | 0.586 | 32.0 · 2.41 | box; -1.20 / -0.60 | gamma-encoded (0.500) | edge: zero/transparent |
| 64 | 37.238 / 41.257 | 0.582 | 64.0 · 2.43 | box; -1.20 / -0.60 | gamma-encoded (0.500) | edge: zero/transparent |

**4.12 MPSImageTent(kernelWidth: 2r+1), param = r**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.707 / 0.772 | 0.707 | 1.0 · 2.00 | disc; -1.00 / -0.50 | gamma-encoded (0.500) | edge: zero/transparent |
| 2 | 1.155 / 1.217 | 0.577 | 2.0 · 2.45 | tent; -0.75 / -0.38 | stripes not flat (0.500) | edge: zero/transparent |
| 4 | 2.000 / 2.091 | 0.500 | 4.0 · 2.83 | tent; -0.65 / -0.32 | gamma-encoded (0.500) | edge: zero/transparent |
| 8 | 3.651 / 3.808 | 0.456 | 8.0 · 3.10 | tent; -0.61 / -0.31 | gamma-encoded (0.500) | edge: zero/transparent |
| 16 | 6.928 / 7.219 | 0.433 | 15.0 · 3.27 | tent; -0.60 / -0.30 | gamma-encoded (0.500) | edge: zero/transparent |
| 32 | 13.466 / 14.028 | 0.421 | 30.0 · 3.36 | tent; -0.60 / -0.30 | gamma-encoded (0.500) | edge: zero/transparent |
| 64 | 26.533 / 27.638 | 0.415 | 59.0 · 3.41 | tent; -0.60 / -0.30 | gamma-encoded (0.500) | edge: zero/transparent |

**4.13 vImageBoxConvolve_Planar8 (kernel 2r+1, kvImageEdgeExtend), param = r**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.816 / 0.949 | 0.816 | 1.0 · – | box; -1.50 / -0.75 | stripes not flat (0.500) | edge: clamp |
| 2 | 1.414 / 1.589 | 0.707 | 2.0 · – | box; -1.30 / -0.66 | stripes not flat (0.500) | edge: clamp |
| 4 | 2.580 / 2.871 | 0.645 | 4.0 · – | box; -1.23 / -0.62 | stripes not flat (0.500) | edge: clamp |
| 8 | 4.899 / 5.434 | 0.612 | 8.0 · – | box; -1.21 / -0.60 | gamma-encoded (0.500) | edge: clamp |
| 16 | 9.521 / 10.552 | 0.595 | 16.0 · – | box; -1.20 / -0.60 | gamma-encoded (0.500) | edge: clamp |
| 32 | 18.769 / 20.792 | 0.587 | 32.0 · – | box; -1.20 / -0.60 | gamma-encoded (0.500) | edge: clamp |
| 64 | 37.262 / 41.273 | 0.582 | 64.0 · – | box; -1.20 / -0.60 | gamma-encoded (0.500) | edge: clamp |

**4.14 vImageTentConvolve_Planar8 (kernel 2r+1, kvImageEdgeExtend), param = r**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.708 / 0.774 | 0.708 | 1.0 · 2.00 | box; -1.01 / -0.51 | gamma-encoded (0.502) | edge: clamp |
| 2 | 1.151 / 1.213 | 0.576 | 2.0 · – | tent; -0.75 / -0.39 | stripes not flat (0.500) | edge: clamp |
| 4 | 2.000 / 2.092 | 0.500 | 4.0 · – | tent; -0.66 / -0.40 | gamma-encoded (0.500) | edge: clamp |
| 8 | 3.636 / 3.792 | 0.455 | 8.0 · – | tent; -0.62 / -0.31 | gamma-encoded (0.500) | edge: clamp |
| 16 | 6.947 / 7.239 | 0.434 | 16.0 · – | tent; -0.60 / -0.32 | gamma-encoded (0.500) | edge: clamp |
| 32 | 13.460 / 14.020 | 0.421 | 31.0 · – | tent; -0.60 / -0.32 | gamma-encoded (0.500) | edge: clamp |
| 64 | 26.506 / 27.620 | 0.414 | 61.0 · – | tent; -0.60 / -0.32 | gamma-encoded (0.500) | edge: clamp |

**4.15 CGContext.setShadow(offset:blur:color:); NSShadow.shadowBlurRadius gives identical numbers**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.460 / 0.494 | 0.460 | 1.0 · – | tent; 1.72 / – | n/a (alpha mask) |  |
| 2 | 0.962 / 0.983 | 0.481 | 2.0 · – | tent; -0.38 / – | n/a (alpha mask) |  |
| 4 | 1.851 / 1.916 | 0.463 | 4.0 · – | box3; -0.52 / – | n/a (alpha mask) |  |
| 8 | 3.628 / 3.773 | 0.453 | 8.0 · – | tent; -0.57 / – | n/a (alpha mask) |  |
| 16 | 7.148 / 7.454 | 0.447 | 16.0 · – | tent; -0.60 / – | n/a (alpha mask) |  |
| 32 | 14.086 / 14.702 | 0.440 | 31.9 · – | tent; -0.61 / – | n/a (alpha mask) |  |
| 64 | 28.221 / 29.551 | 0.441 | 63.0 · – | tent; -0.64 / – | n/a (alpha mask) |  |

**4.16 CALayer.shadowRadius via CALayer.render(in:)**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 0.962 / 0.983 | 0.962 | 2.0 · – | tent; -0.38 / – | n/a (alpha mask) |  |
| 2 | 1.851 / 1.916 | 0.926 | 4.0 · – | box3; -0.52 / – | n/a (alpha mask) |  |
| 4 | 3.628 / 3.773 | 0.907 | 8.0 · – | tent; -0.57 / – | n/a (alpha mask) |  |
| 8 | 7.148 / 7.454 | 0.893 | 16.0 · – | tent; -0.60 / – | n/a (alpha mask) |  |
| 16 | 14.086 / 14.702 | 0.880 | 31.9 · – | tent; -0.61 / – | n/a (alpha mask) |  |
| 32 | 28.221 / 29.551 | 0.882 | 63.0 · – | tent; -0.64 / – | n/a (alpha mask) |  |
| 64 | 56.486 / 59.019 | 0.883 | 127.7 · – | tent; -0.63 / – | n/a (alpha mask) |  |

**4.17 SwiftUI .shadow(radius:) via ImageRenderer**

| param | fitted σ px (moment / LSQ) | σ / param | support: visible r255 px · PSF r(1e-4)/σ | shape (best fit; kurtosis axis / 45°) | colour space (stripes) | notes |
|---|---|---|---|---|---|---|
| 1 | 1.002 / 1.039 | 1.002 | 2.0 · – | box3; -0.51 / – | n/a (alpha mask) |  |
| 2 | 1.941 / 2.013 | 0.970 | 4.0 · – | box3; -0.50 / – | n/a (alpha mask) |  |
| 4 | 3.874 / 4.012 | 0.969 | 9.0 · – | box3; -0.48 / – | n/a (alpha mask) |  |
| 8 | 7.712 / 8.000 | 0.964 | 18.0 · – | box3; -0.51 / – | n/a (alpha mask) |  |
| 16 | 15.366 / 15.968 | 0.960 | 35.0 · – | box3; -0.53 / – | n/a (alpha mask) |  |
| 32 | 30.733 / 31.952 | 0.960 | 70.0 · – | box3; -0.54 / – | n/a (alpha mask) |  |
| 64 | 61.515 / 63.935 | 0.961 | 140.0 · – | box3; -0.54 / – | n/a (alpha mask) |  |


### 4.18 Sweeps

**SwiftUI `.blur(radius:)`, `opaque: true`, `.nonLinear`, scale 1, 34 radii (4 edge phases each).** The algorithm change at about 5–5.5 device pixels is visible as the jump in "centre spread" and the drop of σ/r from ~0.99 to ~0.90.

| radius r (pt = px at scale 1) | RenderBox `.cgImage`: σ px | σ/r | kurtosis | best model | centre spread over 4 phases px | `render(into CGContext)`: σ px | σ/r | kurtosis | centre spread px |
|---|---|---|---|---|---|---|---|---|---|
| 0.25 | 0.000 | 0.000 | 0.00 | box | 0.00 | 0.029 | 0.115 | 1211.26 | 0.00 |
| 0.5 | 0.460 | 0.921 | 1.72 | tent | 0.00 | 0.465 | 0.929 | 1.83 | 0.00 |
| 0.75 | 0.746 | 0.995 | 0.01 | gaussian | 0.00 | 0.749 | 0.998 | -0.02 | 0.00 |
| 1 | 0.994 | 0.994 | -0.06 | gaussian | 0.00 | 0.998 | 0.998 | -0.05 | 0.00 |
| 1.5 | 1.482 | 0.988 | -0.16 | gaussian | 0.00 | 1.498 | 0.998 | -0.03 | 0.00 |
| 2 | 2.002 | 1.001 | 0.01 | gaussian | 0.00 | 1.990 | 0.995 | -0.09 | 0.00 |
| 2.5 | 2.475 | 0.990 | -0.14 | gaussian | 0.00 | 2.468 | 0.987 | -0.16 | 0.00 |
| 3 | 2.845 | 0.948 | -0.36 | box3 | 0.00 | 2.977 | 0.992 | -0.12 | 0.00 |
| 3.5 | 3.130 | 0.894 | -0.48 | box3 | 0.00 | 3.454 | 0.987 | -0.17 | 0.00 |
| 4 | 3.940 | 0.985 | -0.14 | gaussian | 0.00 | 3.962 | 0.991 | -0.13 | 0.00 |
| 4.5 | 4.302 | 0.956 | -0.34 | gaussian | 0.00 | 4.441 | 0.987 | -0.17 | 0.00 |
| 5 | 4.626 | 0.925 | -0.41 | box3 | 0.00 | 4.913 | 0.983 | -0.20 | 0.00 |
| 5.5 | 4.988 | 0.907 | -0.50 | tent | 0.15 | 5.446 | 0.990 | -0.19 | 0.14 |
| 6 | 5.439 | 0.906 | -0.48 | tent | 0.43 | 5.907 | 0.984 | -0.19 | 0.43 |
| 6.5 | 5.905 | 0.908 | -0.49 | box3 | 1.00 | 6.418 | 0.987 | -0.18 | 1.00 |
| 7 | 6.339 | 0.906 | -0.49 | tent | 1.00 | 6.891 | 0.984 | -0.18 | 1.00 |
| 7.5 | 6.818 | 0.909 | -0.47 | tent | 1.00 | 7.391 | 0.985 | -0.19 | 1.00 |
| 8 | 7.245 | 0.906 | -0.50 | tent | 1.00 | 7.874 | 0.984 | -0.19 | 1.00 |
| 9 | 8.169 | 0.908 | -0.48 | tent | 1.40 | 8.866 | 0.985 | -0.19 | 1.00 |
| 10 | 9.059 | 0.906 | -0.49 | tent | 1.09 | 9.852 | 0.985 | -0.18 | 1.10 |
| 11 | 9.852 | 0.896 | -0.47 | tent | 0.12 | 10.817 | 0.983 | -0.21 | 0.14 |
| 12 | 10.830 | 0.902 | -0.45 | box3 | 0.44 | 11.789 | 0.982 | -0.21 | 0.43 |
| 14 | 12.622 | 0.902 | -0.44 | box3 | 1.00 | 13.751 | 0.982 | -0.21 | 1.00 |
| 16 | 14.417 | 0.901 | -0.45 | box3 | 1.00 | 15.718 | 0.982 | -0.20 | 1.00 |
| 20 | 18.049 | 0.902 | -0.45 | box3 | 1.07 | 19.646 | 0.982 | -0.21 | 1.09 |
| 24 | 21.711 | 0.905 | -0.46 | tent | 0.49 | 23.510 | 0.980 | -0.23 | 0.43 |
| 28 | 25.345 | 0.905 | -0.46 | tent | 1.00 | 27.425 | 0.979 | -0.23 | 1.00 |
| 32 | 28.982 | 0.906 | -0.46 | tent | 1.00 | 31.341 | 0.979 | -0.23 | 1.00 |
| 40 | 36.215 | 0.905 | -0.48 | tent | 1.14 | 39.177 | 0.979 | -0.23 | 1.09 |
| 48 | 43.266 | 0.901 | -0.45 | box3 | 0.36 | 46.970 | 0.979 | -0.24 | 0.43 |
| 56 | 50.503 | 0.902 | -0.45 | box3 | 1.00 | 54.800 | 0.979 | -0.24 | 1.00 |
| 64 | 57.685 | 0.901 | -0.45 | box3 | 1.00 | 62.625 | 0.979 | -0.24 | 1.00 |
| 80 | 72.205 | 0.903 | -0.46 | box3 | 1.08 | 78.286 | 0.979 | -0.24 | 1.10 |
| 96 | 86.590 | 0.902 | -0.45 | box3 | 1.15 | 93.947 | 0.979 | -0.24 | 1.28 |

**`CIBoxBlur` width versus `inputRadius`** (read in linear light, the filter's working space). The implied width √(12σ² + 1) is an exact odd integer every time.

| CIBoxBlur inputRadius | σ px | implied box width √(12σ²+1) | 2·⌈r/2⌉−1 |
|---|---|---|---|
| 0.5 | 0.000 | 1.00 | 1 |
| 1 | 0.000 | 1.00 | 1 |
| 1.5 | 0.000 | 1.00 | 1 |
| 2 | 0.000 | 1.00 | 1 |
| 2.5 | 0.816 | 3.00 | 3 |
| 3 | 0.816 | 3.00 | 3 |
| 3.5 | 0.816 | 3.00 | 3 |
| 4 | 0.816 | 3.00 | 3 |
| 4.5 | 1.414 | 5.00 | 5 |
| 5 | 1.414 | 5.00 | 5 |
| 5.5 | 1.414 | 5.00 | 5 |
| 6 | 1.414 | 5.00 | 5 |
| 6.5 | 1.999 | 7.00 | 7 |
| 7 | 1.999 | 7.00 | 7 |
| 7.5 | 1.999 | 7.00 | 7 |
| 8 | 1.999 | 7.00 | 7 |
| 9 | 2.582 | 9.00 | 9 |
| 10 | 2.582 | 9.00 | 9 |
| 11 | 3.163 | 11.00 | 11 |
| 12 | 3.163 | 11.00 | 11 |
| 13 | 3.743 | 13.00 | 13 |
| 14 | 3.743 | 13.00 | 13 |
| 15 | 4.322 | 15.01 | 15 |
| 16 | 4.322 | 15.01 | 15 |
| 20 | 5.478 | 19.00 | 19 |
| 24 | 6.636 | 23.01 | 23 |
| 32 | 8.948 | 31.01 | 31 |
| 48 | 13.568 | 47.01 | 47 |
| 64 | 18.192 | 63.03 | 63 |

**Shadows.** Each `CALayer.shadowRadius = p` result equals `CGContext.setShadow(blur: 2p)` exactly. Values for σ > 80 px are limited by the 300-px analysis window and are omitted.

| parameter p | CGContext.setShadow(blur: p) σ px | σ/p | kurtosis | CALayer.shadowRadius = p σ px | σ/p | equals CG blur 2p? | SwiftUI .shadow(radius: p) σ px | σ/p | kurtosis |
|---|---|---|---|---|---|---|---|---|---|
| 0.5 | 0.460 | 0.921 | 1.72 | 0.460 | 0.921 | yes (Δσ = 0.000) | 0.567 | 1.135 | 0.11 |
| 1 | 0.460 | 0.460 | 1.72 | 0.962 | 0.962 | yes (Δσ = 0.000) | 1.002 | 1.002 | -0.51 |
| 1.5 | 0.962 | 0.641 | -0.38 | 1.406 | 0.937 | yes (Δσ = 0.000) | 1.470 | 0.980 | -0.42 |
| 2 | 0.962 | 0.481 | -0.38 | 1.851 | 0.926 | yes (Δσ = 0.000) | 1.941 | 0.970 | -0.50 |
| 3 | 1.406 | 0.469 | -0.49 | 2.742 | 0.914 | yes (Δσ = 0.000) | 2.895 | 0.965 | -0.51 |
| 4 | 1.851 | 0.463 | -0.52 | 3.628 | 0.907 | yes (Δσ = 0.000) | 3.874 | 0.969 | -0.48 |
| 5 | 2.299 | 0.460 | -0.53 | 4.501 | 0.900 | yes (Δσ = 0.000) | 4.800 | 0.960 | -0.53 |
| 6 | 2.742 | 0.457 | -0.55 | 5.389 | 0.898 | yes (Δσ = 0.000) | 5.760 | 0.960 | -0.55 |
| 8 | 3.628 | 0.453 | -0.57 | 7.148 | 0.893 | yes (Δσ = 0.000) | 7.712 | 0.964 | -0.51 |
| 10 | 4.501 | 0.450 | -0.58 | 8.909 | 0.891 | yes (Δσ = 0.000) | 9.624 | 0.962 | -0.52 |
| 12 | 5.389 | 0.449 | -0.59 | 10.683 | 0.890 | yes (Δσ = 0.000) | 11.541 | 0.962 | -0.53 |
| 16 | 7.148 | 0.447 | -0.60 | 14.086 | 0.880 | yes (Δσ = 0.000) | 15.366 | 0.960 | -0.53 |
| 20 | 8.909 | 0.445 | -0.61 | 17.618 | 0.881 | – | 19.265 | 0.963 | -0.52 |
| 24 | 10.683 | 0.445 | -0.60 | 21.135 | 0.881 | yes (Δσ = 0.000) | 23.092 | 0.962 | -0.53 |
| 32 | 14.086 | 0.440 | -0.61 | 28.221 | 0.882 | yes (Δσ = 0.000) | 30.733 | 0.960 | -0.54 |
| 48 | 21.135 | 0.440 | -0.63 | 41.829 | 0.871 | yes (Δσ = 0.000) | 46.100 | 0.960 | -0.54 |
| 64 | 28.221 | 0.441 | -0.64 | 56.486 | 0.883 | yes (Δσ = 0.000) | 61.515 | 0.961 | -0.54 |

### 4.19 ImageRenderer output formats (MEASURED, flat sRGB 0.5 grey, no blur)

| `colorMode` | CGImage colour space tag | bits/component | raw first pixel | read back through CG as encoded / linear |
|---|---|---|---|---|
| `.nonLinear` | kCGColorSpaceSRGB | 8 | 128,128,128,255 | 0.502 / 0.216 (correct) |
| `.linear` | **kCGColorSpaceLinearSRGB** | 8 | **127**,127,127,255 | 0.734 / 0.498 (**wrong**: 0.5 grey should be linear 0.214 → 55) |
| `.extendedLinear` | kCGColorSpaceExtendedLinearSRGB | 16 (half float) | 0.2140, …, 1.0 | 0.500 / 0.214 (correct) |

In `.linear` mode the bytes are sRGB-encoded but the image is tagged linear. Anything that honours the tag (CG drawing, `UIImage`, PNG export) displays it too bright: a blurred black/white stripe pattern reads 0.873 instead of 0.735. Re-tagging with `image.copy(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)` gives correct values (table 4.4). The measured blur in `.linear` mode is the same as in `.extendedLinear`. This looks like a framework bug. It is MEASURED on macOS 27.2 and UNVERIFIED on iOS.

## 5. Per-API findings

### 5.1 SwiftUI `.blur(radius:)` via ImageRenderer

Documentation (REFERENCE): "Applies a Gaussian blur to this view." `radius` is "The radial size of the blur", and `opaque` is whether "the blur renderer permits transparency in the blur output" ([View.blur(radius:opaque:)](https://developer.apple.com/documentation/swiftui/view/blur(radius:opaque:))). Nothing in the documentation says how radius relates to σ, in what space it blends, or how it treats borders. The measurements below answer those questions on macOS 27.2.

1. **Radius is in points.** At `scale` 2 and 3, σ in device pixels is 0.90·r·scale (tables in the JSON, `swiftui-scale`). So the iPhone 15 Pro Max (scale 3) should see σ ≈ 2.7·r device pixels. That figure is INFERRED from the Mac and needs on-device confirmation.
2. **σ ≈ r for small radii, σ = 0.90·r for large ones.** From r = 0.75 to 2.5 device pixels the kernel is a sampled Gaussian with σ = r within 1.2% (kurtosis about 0). At 3–5 px, σ/r wobbles between 0.89 and 0.99 and the shape is sometimes box-like. From r ≥ 5.5 px it settles at σ/r = 0.896–0.909 for every radius up to 96 px. At r = 0.25 nothing happens. At r = 0.5 there is a 3-tap kernel (σ 0.46).
3. **The large-radius kernel is not a Gaussian.** It is separable: the 45° kurtosis, −0.23 to −0.28, is half the axis kurtosis of −0.45. Its marginal is box³-like (Irwin–Hall n = 3 gives −0.40, a Gaussian 0). Its PSF is 8–11% wider along the axes than along the diagonals at half maximum. It ends abruptly: it falls to 10⁻⁴ of its peak at 3.55σ, where a Gaussian would reach 4.29σ. A three-pass box blur, the classic cheap Gaussian approximation (Wells, 1986), fits all of these, but this is INFERRED. The isotropic Gaussian fit leaves about 1% of peak RMS residual.
4. **It resamples above about 5 device pixels (INFERRED from three MEASURED signatures).** (a) Shift variance. As the edge steps through 16 integer positions, the blurred edge's centre wobbles by up to 1.2 px (2048 px canvas) or 0.2–1.4 px growing with r (the smaller canvas used by `measurePSF`), while σ varies by at most 1.2%. A full-resolution convolution gives exactly 0, and CI's and MPS's Gaussians give ≤ 0.1 px. (b) The phase pattern repeats for r and 2r (6, 12, 24, 48 share one pattern, and 7, 14, 28, 56 another). That points to power-of-two pyramid levels plus a fractional resample. (c) Aliasing. Blurred 1-px stripes should average exactly 0.500 but read 0.509–0.524, so the Nyquist-frequency pattern folded into DC, which only happens if the image was decimated without a perfect prefilter. Below 5 px all three signatures are absent.
5. **Colour space follows `ImageRenderer.colorMode`.** In `.nonLinear` (the default, and the one that matches ordinary sRGB UI rendering) the blur averages gamma-encoded values: stripes 0.500, step midpoint 0.500. In `.linear` and `.extendedLinear` it averages linear light: stripes 0.735 (0.74–0.75 above 5 px because of the aliasing in point 4). So the same view, blurred, looks different depending on the renderer's working space. On a black/white edge the bright side spreads further in linear mode.
6. **Borders.** With `opaque: false`, pixels outside the view count as transparent. The white image's border column drops to 0.70 (r 1) and 0.53 (r 8), with equal alpha, and the blur draws outside the view's frame (alpha 0.04–0.47 4 px outside, depending on r). With `opaque: true` the output stays opaque at the border and nothing is drawn outside. At r ≤ 4 the edge pixels are clamped: a black first column pulls the border to 0.30/0.40/0.45. At r ≥ 8 the black column only pulls it to 0.85–0.93, which a plain clamp would not do. That is consistent with clamping a downsampled copy, but this is UNVERIFIED.
7. **Two SwiftUI blurs.** `ImageRenderer.render(rasterizationScale:)` into a caller-supplied `CGContext` produces a *different* blur. σ = 0.98·r (not 0.90·r), the kernel is near-Gaussian (LSQ residual 0.13–0.21% of peak), it is isotropic, its tails reach 4.1σ, and it has tiny 0.15–0.21% negative lobes. Above 5.5 px it shows the same resampling signatures, and its stripes read 0.476. So `.cgImage` and `render(into:)` of the same view differ by 9% in σ. For the app, the `.cgImage` path is the one to measure, because it uses the GPU renderer that also draws on-screen SwiftUI content. That last part is INFERRED, see section 8.

### 5.2 Core Image

The default `CIContext` blends in linear light (stripes 0.735 for every filter), which matches Core Image's documented default linear working space ([CIContextOption.workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace)). Outside the input's extent every filter samples transparent black, so borders darken and lose alpha, and the output extent grows. `clampedToExtent()` turns that into clamping (table 4.6 variant in the JSON).

- **CIGaussianBlur**: σ = `inputRadius` (σ/r 0.994–1.007 for r ≥ 1; r = 0.5 gives 0.57). It is isotropic and very close to Gaussian (2-D residual 0.05–0.12% of peak). The kernel is truncated more aggressively as σ grows: it reaches 10⁻⁴ of peak at 4.19σ (σ 8), 3.96σ (σ 32) and 3.57σ (σ 64). Residual shift variance is tiny but non-zero at some radii (≤ 0.1 px and ≤ 1.4% σ at r = 10, 13, 16, 48), which suggests a reduced-resolution path for some sizes (INFERRED). Documented description (REFERENCE): "Spreads source pixels by an amount specified by a Gaussian distribution", default radius 10 ([Core Image Filter Reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html)).
- **CIBoxBlur**: a separable *square* box. Axis kurtosis is −1.20, 45° kurtosis −0.60, and the half-max contour is 1.40× farther along the diagonal. Its width is **W = 2⌈r/2⌉ − 1** at every tested radius, so `inputRadius` behaves like a diameter, and radii ≤ 2 return the image unchanged (W = 1). The runtime attributes give a minimum of 1 and a default of 10 (W = 9). Shift-invariant.
- **CIDiscBlur**: a uniform disc of radius r. σ = r/2 (σ/r = 0.497–0.520 for r ≥ 2, 0.500–0.502 for r ≥ 5; r = 1–1.5 deviate), marginal kurtosis −1.00 (semicircle), isotropic, support ends at r. **CIBokehBlur** with default ring and softness parameters is bit-identical to CIDiscBlur (max |difference| = 0 at r = 4, 16, 40). The runtime attribute table for `inputSoftness` gives default 1 but slider maximum 0.4, so it is inconsistent.
- **CIMotionBlur**: the PSF is a 1-px-thin line along `inputAngle` with **Gaussian** weights of σ = `inputRadius` (kurtosis −0.03 to −0.11), centred on the source pixel and two-sided, with a cross-direction σ of 0. It is not a uniform one-sided smear, which is what a physical camera move would give. Documented as "simulate the effect of using a camera that moves a specified angle and distance".
- **CIZoomBlur** (qualitative): each point smears into a streak pointing *away* from `inputCenter`. The streak length grows in proportion to the distance from the centre: length/distance ≈ 0.079 at amount 4 and ≈ 0.357 at amount 16, the same at d = 100, 200 and 300 px. The weights along the streak are near-uniform (kurtosis −1.03 to −1.09). The exact amount → length law is UNVERIFIED (not linear in amount: 0.079/4 vs 0.357/16).

### 5.3 Metal Performance Shaders

- **MPSImageGaussianBlur(sigma:)**: σ = sigma (0.993–0.998 for σ ≥ 4, 1.037 at σ = 1 because a narrow kernel sampled on pixels has extra variance). It is isotropic, its 2-D residual is 0.04–0.07% of peak, it is untruncated to 10⁻⁴ (4.2–4.3σ), and it is shift-invariant (≤ 0.006 px). Apple's description (REFERENCE) calls it "an approximate Gaussian … suitable for all common image processing needs demanding ~10 bits of precision or less" ([MPSImageGaussianBlur](https://developer.apple.com/documentation/metalperformanceshaders/mpsimagegaussianblur)). The measured residuals are consistent with that.
- **MPSImageBox / MPSImageTent** with kernel width 2r + 1 are the exact discrete box (σ² = ((2r+1)² − 1)/12) and the separable tent, i.e. two boxes of width r + 1 (σ² = ((r+1)² − 1)/6). They match to 4 decimals.
- MPS filters the numbers stored in the texture. With sRGB-encoded data in an `rgba32Float` texture the blend is in encoded space (stripes 0.500). An `*_srgb` pixel format would be linearised on read and re-encoded on write by Metal (REFERENCE: Metal Shading Language Specification, sRGB texture conversion rules; section number UNVERIFIED). That variant was not measured here.
- Edge mode: `.zero` (the default) gives transparent padding, and `.clamp` clamps. Both MEASURED.

### 5.4 vImage

`vImageBoxConvolve_Planar8` and `vImageTentConvolve_Planar8` with kernel 2r + 1 give the same σ as MPS to 3 decimals. They operate on raw 8-bit values (stripes 0.500). Edge flags, MEASURED at r = 8: `kvImageEdgeExtend` clamps (black first column → 0.47); `kvImageTruncateKernel` renormalises the kernel inside the image (white border stays 1.0, black first column → 0.89); `kvImageBackgroundColorFill` with 0 pads with black (white border → 0.53).

### 5.5 Shadows: `CGContext.setShadow`, `NSShadow`, `CALayer.shadowRadius`, SwiftUI `.shadow`

- **`CGContext.setShadow(offset:blur:color:)`**: σ ≈ 0.44–0.47·blur for blur ≥ 3 (0.469 at 3 falling to 0.436 at 96), and the visible extent is ≈ blur px. The kernel is tent-like (kurtosis −0.52 to −0.65), not Gaussian. Results are the same in 8-bit and float contexts. The documentation says only "A non-negative number specifying the amount of blur" ([setShadow](https://developer.apple.com/documentation/coregraphics/cgcontext/setshadow(offset:blur:color:))). **`NSShadow.shadowBlurRadius`** gives identical numbers to 3 decimals at every value, so AppKit passes it straight through (INFERRED).
- **`CALayer.shadowRadius = r`**, rendered with `render(in:)`, is *exactly* the CG shadow with blur = 2r at every tested value (Δσ = 0.000): σ ≈ 0.88–0.93·r for r ≥ 2 (0.96 at r = 1). Apple documents shadowRadius as "The blur radius (in points) used to render the layer’s shadow", default 3 ([shadowRadius](https://developer.apple.com/documentation/quartzcore/calayer/shadowradius)). Caveat: `render(in:)` is Core Animation's software path. On screen, shadows are drawn by the render server, which may use a different kernel (UNVERIFIED).
- **SwiftUI `.shadow(radius:)`**: σ ≈ 0.96·r (0.960–0.970 for r ≥ 2), box³-like (kurtosis −0.5). Its σ/r is not the same as `.blur`'s 0.90, so shadow and blur radii in SwiftUI are not interchangeable.
- Shadows blur an alpha mask, so colour space does not apply to the blur itself. The shadow colour is composited afterwards.

## 6. Implications for the app (what to label how)

1. **Parameter-semantics layer (BlurCore conversions).** These are the MEASURED (macOS 27.2) conversions to ship, each with its badge:

   | API parameter | effective σ (px at scale 1) | badge |
   |---|---|---|
   | SwiftUI `.blur(radius: r)` | r·s ≤ 5: σ ≈ r·s; above: σ ≈ 0.90·r·s (s = display scale), box³-like | MEASURED (Mac); re-MEASURED on device with `measurePSF` |
   | SwiftUI `.shadow(radius: r)` | 0.96·r·s | MEASURED (Mac) |
   | `CIGaussianBlur` radius r | σ = r | MEASURED; matches the documented Gaussian |
   | `CIBoxBlur` radius r | box width 2⌈r/2⌉ − 1 | MEASURED (contradicts the natural reading of "radius") |
   | `CIDiscBlur`/`CIBokehBlur` radius r | disc radius r, σ = r/2 | MEASURED |
   | `CIMotionBlur` radius r | Gaussian σ = r along the angle | MEASURED |
   | `MPSImageGaussianBlur` sigma | σ = sigma | MEASURED, REFERENCE |
   | `MPSImageBox/Tent`, `vImage…Convolve` | exact box / tent of width 2r + 1 | COMPUTED (and MEASURED to 4 dp) |
   | `CGContext.setShadow` blur b, `NSShadow` | σ ≈ 0.45·b, tent-like | MEASURED |
   | `CALayer.shadowRadius` r | same as CG blur 2r (σ ≈ 0.9·r) | MEASURED (software path) |
   | CSS `blur(r)`, Figma, Photoshop | not measured here | REFERENCE from the stack-semantics research |

2. **"What the designer's slider really does" moments worth showing.** (a) SwiftUI swaps algorithms at about 5 device pixels: a true Gaussian below, a cheaper separable box³-like blur on a resampled image above. The resampling makes the blurred edge wobble by up to about a pixel as content moves, and on an iPhone at scale 3 that threshold is a `.blur(radius:)` of only about 1.8 pt. (b) The same `.blur` blends gamma-encoded values by default but linear light if the renderer is linear. (c) `CIBoxBlur`'s "radius" is a diameter. (d) `CIMotionBlur` is Gaussian, not a streak. (e) A CALayer shadow is twice as blurry per unit as a CG shadow.
3. **Every SwiftUI number on screen should be re-measured on the phone.** Run `measurePSF` (section 7) at the device's `displayScale` for the radius the user picks, and show σ, σ/r, shape, centre wobble and colour-space verdict with the MEASURED badge and the device name. A Mac value may be shown only as "MEASURED on macOS 27.2" until the device value arrives. It is cheap: 58 renders of the self-check took 0.4 s on the M1 Max.
4. **INFERRED, not MEASURED:** how SwiftUI implements the blur (box passes, pyramid factors), why the large-radius regime starts at about 5 px, Core Image's internal truncation choice, the on-screen render-server path for both SwiftUI blur and CALayer shadows, and whether `ImageRenderer` matches what the screen shows.
5. **GPU-parity tests.** Use MPS Gaussian (σ = sigma, untruncated) and vImage box/tent (exact) as the trusted references for the app's own Metal kernels. Do not use SwiftUI or CI as references for an "exact Gaussian" test.

## 7. iOS-ready measurement code (`measurePSF`)

File: `Tools/calibrate/MeasurePSF.swift`. It depends only on SwiftUI and CoreGraphics (no UIKit, no AppKit), compiles in Swift 6 language mode, and can be dropped into the app target unchanged.

```swift
@MainActor
public func measurePSF<Content: View>(parameter: CGFloat,
                                      scale: CGFloat = 1,
                                      colorMode: ColorRenderingMode = .nonLinear,
                                      phases: Int = 1,
                                      blur: (CalibrationEdge) -> Content) -> PSFFit?

// usage
let fit = measurePSF(parameter: 8, scale: displayScale, phases: 4) { $0.blur(radius: 8) }
```

The requested `(some View) -> some View` form is not expressible, because Swift does not allow opaque parameter types in closure types. The closure therefore receives the concrete `CalibrationEdge` pattern and returns any `View`, which keeps the call site identical in practice. Any blur-like modifier can be measured: `{ $0.blur(radius: r, opaque: true) }`, `{ $0.shadow(radius: r) }` (with a pattern change), or a custom `layerEffect`.

How it works:
1. `CalibrationEdge` is a black | white step. The canvas is sized from the parameter: an analysis half-window of 6·r + 8 pt plus a margin of 4·r + 8 pt. The margin keeps the transparent-border fade of `opaque: false` out of the window.
2. `ImageRenderer` renders it at the requested `scale` and `colorMode`. For `.linear`, the output is re-tagged sRGB because of the tagging bug in 4.19.
3. Only the 16 centre rows are drawn into a 16-row float RGBA `CGContext` in the blur's working space (extended sRGB for `.nonLinear`, extended linear sRGB otherwise). That keeps memory low at scale 3: a radius-64 canvas is 2.7k × 0.8k px, but only 2.7k × 16 floats are read.
4. The edge is fitted with the same estimators as the Mac probe: two-pass moment σ of the LSF within ±6σ, an erf least-squares σ, excess kurtosis → shape name, visible extent at 1/255, support at 10⁻³ of the LSF peak, the centre offset, and the encoded midpoint value. With `phases > 1` the edge is moved by whole device pixels and the spread of centre and σ is reported, which is the downsampling detector.
5. The result is a `Sendable, Codable` `PSFFit`, with the LSF samples included for plotting the measured kernel next to the theoretical one.

Verification (MEASURED, this session):
- `xcrun swiftc -typecheck -swift-version 6 -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) -target arm64-apple-ios27.0-simulator MeasurePSF.swift` passes with no errors or warnings, and the same check against the `iphoneos` SDK with `-target arm64-apple-ios27.0` also passes.
- On the Mac, `swiftc -O -parse-as-library -swift-version 6 -D MEASUREPSF_MAIN MeasurePSF.swift` builds a self-check that measures SwiftUI `.blur` with 4 phases. Its output (below) agrees with the independent probe: σ/r = 0.994, 1.001, 0.985 at r = 1, 2, 4 (identical), and 0.906–0.913 above (probe: 0.901–0.906; the ≤ 1% difference comes with the different canvas size, as does the larger centre wobble). Scale 2 and 3 give σ_pt = 7.29–7.30 for r = 8.

```
parameter scale mode        sigma_pt  sigma/param  lsq_px  kurt  shape     extent_px  centreSpread_px  sigmaSpread%
   1.0   1.0  nonLinear    0.994     0.994     0.994  -0.06  gaussian      1.5       0.000        0.00
   2.0   1.0  nonLinear    2.002     1.001     1.996   0.01  gaussian      4.5       0.000        0.00
   4.0   1.0  nonLinear    3.940     0.985     3.964  -0.14  gaussian      9.5       0.000        0.00
   8.0   1.0  nonLinear    7.308     0.913     7.529  -0.48  box3     16.4       0.215        0.98
  16.0   1.0  nonLinear   14.590     0.912    15.021  -0.48  box3     32.6       0.448        0.50
  32.0   1.0  nonLinear   29.076     0.909    29.952  -0.48  box3     65.7       0.713        0.38
  64.0   1.0  nonLinear   57.958     0.906    59.663  -0.48  box3    130.8       1.428        0.48
   1.0   1.0  extendedLinear    0.996     0.996     0.997  -0.04  gaussian      2.5       0.000        0.00
   2.0   1.0  extendedLinear    1.995     0.997     1.998  -0.05  gaussian      4.5       0.000        0.00
   4.0   1.0  extendedLinear    3.920     0.980     3.957  -0.20  gaussian      9.5       0.000        0.00
   8.0   1.0  extendedLinear    7.290     0.911     7.496  -0.46  box3     16.6       0.223        0.47
  16.0   1.0  extendedLinear   14.589     0.912    15.002  -0.46  box3     33.6       0.439        0.47
  32.0   1.0  extendedLinear   29.177     0.912    30.006  -0.46  box3     67.6       0.726        0.51
  64.0   1.0  extendedLinear   58.068     0.907    59.724  -0.47  box3    133.8       1.446        0.21
scale 2 radius 8: sigma_px 14.584 sigma_pt 7.292 sigma/param 0.911
scale 3 radius 8: sigma_px 21.897 sigma_pt 7.299 sigma/param 0.912
```

Not yet done: running it **on the iPhone 15 Pro Max**. That needs the app target (or a tiny harness app) built through `Tools/build.sh` from a `$TMPDIR` mirror, which is outside this research task. Until then every SwiftUI number in this document is a macOS number.

Optional second method for the device (UNVERIFIED, worth one experiment): snapshot a live on-screen view with `UIView.drawHierarchy(in:afterScreenUpdates: true)` and fit the same edge. If that path captures the render-server composite, it measures what the screen actually shows rather than what `ImageRenderer` produces, and the two can be compared.

## 8. Open questions and UNVERIFIED items

- **iOS 27 / A17 Pro values.** Nothing here was measured on iOS. SwiftUI, Core Animation and Core Image are separate per-platform builds, and the GPU differs. The σ laws, the 5-px regime switch, the `.linear` tagging bug and the CI truncation may all change.
- **ImageRenderer vs the screen.** On screen, SwiftUI content is composited by Core Animation's render server. Whether `.blur` on a live view uses the same implementation as `ImageRenderer.cgImage` is UNVERIFIED. The two ImageRenderer paths already differ by 9% in σ (5.1, point 7).
- **The SwiftUI resampling mechanism** (pyramid levels, fractional factor, how it depends on layer size) is INFERRED from shift variance, phase patterns and stripe aliasing. The exact factor was not identified. The wobble pattern depended on canvas size (2048 px probe: constant ≈ 1.2 px; `measurePSF` canvas: 0.2–1.4 px growing with r).
- **Timing.** The probe records one wall-clock time per ESF render (`ms` in the JSON), but that includes CPU readback and is not a GPU timing. Whether SwiftUI's cost stops growing with r above 5 px (as a pyramid would predict) is UNVERIFIED.
- **Core Image** truncation (4.2σ → 3.6σ as σ grows) and its small shift variance at some radii: mechanism INFERRED/UNVERIFIED. CIZoomBlur's exact amount → streak-length law: UNVERIFIED.
- **CALayer shadows on screen** may not equal `render(in:)` (software path) = CG blur 2r. The CG shadow kernel is tent-like. Whether it is two box passes is INFERRED.
- **Metal `*_srgb` textures under MPS**: not measured. The linearise-on-read behaviour is from the Metal specification (section number UNVERIFIED).
- **Large shadow σ**: shadow fits above σ ≈ 80 px are limited by the 300-px analysis window and are not reported.
- **NSShadow** was measured only in an unflipped 8-bit sRGB context.

## 9. Sources

- Apple, SwiftUI `View.blur(radius:opaque:)`: https://developer.apple.com/documentation/swiftui/view/blur(radius:opaque:) (abstract "Applies a Gaussian blur to this view").
- Apple, SwiftUI `ImageRenderer` and `ImageRenderer.colorMode` ("The working color space and storage format of the image"): https://developer.apple.com/documentation/swiftui/imagerenderer, https://developer.apple.com/documentation/swiftui/imagerenderer/colormode
- Apple, SwiftUI `ColorRenderingMode` (nonLinear / linear / extendedLinear sRGB working spaces): https://developer.apple.com/documentation/swiftui/colorrenderingmode
- Apple, Core Image Filter Reference (archived): CIBoxBlur "box-shaped convolution kernel" default 10; CIDiscBlur default 8; CIGaussianBlur default 10; CIMotionBlur default 20, angle 0; CIZoomBlur center [150 150], amount 20: https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html. CIBokehBlur defaults (radius 20, ringAmount 0, ringSize 0.1, softness 1) are read from the runtime `CIFilter.attributes` on macOS 27.2, because the documentation page returned 404 on 13 Oct 2026.
- Apple, `CIContextOption.workingColorSpace`: https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace
- Apple, `MPSImageGaussianBlur` ("approximate Gaussian … ~10 bits of precision or less"): https://developer.apple.com/documentation/metalperformanceshaders/mpsimagegaussianblur; `MPSImageBox`, `MPSImageTent`, `MPSImageEdgeMode` on the same site.
- Apple, Accelerate `vImageBoxConvolve_Planar8`, `vImageTentConvolve_Planar8` and the `kvImageEdgeExtend` / `kvImageTruncateKernel` / `kvImageBackgroundColorFill` flags: https://developer.apple.com/documentation/accelerate/vimage
- Apple, `CGContext.setShadow(offset:blur:color:)` ("A non-negative number specifying the amount of blur"): https://developer.apple.com/documentation/coregraphics/cgcontext/setshadow(offset:blur:color:)
- Apple, `CALayer.shadowRadius` ("The blur radius (in points) used to render the layer’s shadow", default 3.0): https://developer.apple.com/documentation/quartzcore/calayer/shadowradius; `CALayer.render(in:)` (does not render filters, backgroundFilters, compositingFilter or masks): https://developer.apple.com/documentation/quartzcore/calayer/render(in:)
- Apple, Metal Shading Language Specification (sRGB texture read/write conversion): https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf (section number UNVERIFIED).
- W. M. Wells, "Efficient synthesis of Gaussian filters by cascaded uniform filters", IEEE Trans. PAMI 8(2), 1986. The basis for reading kurtosis −0.4 as a three-box cascade.
- ISO 12233:2017, Photography — Electronic still picture imaging — Resolution and spatial frequency responses. The edge-spread/line-spread method used here (a vertical edge rather than the standard's slanted edge, with explicit integer phase stepping instead).
- Excess kurtosis references for the shape test: uniform −1.2; sum of n uniforms −1.2/n (Irwin–Hall); semicircle (disc marginal) −1.0; Gaussian 0. These are standard results, COMPUTED.

<!-- STATUS: COMPLETE -->
