# Stack semantics: what a blur parameter means at each layer

Status: complete, 2026-10-13. Written by a research agent for the Blur2ool build team; binding brief: `Documentation/BRIEF.md`.

**Key findings in one screen**

- The same typed "10" produces σ from **1.0 to 10.0 px** across tools (16 distinct pixel meanings, section 8). Three conventions dominate: **σ = value** (CSS `blur()`, SVG, SwiftUI, Core Image Gaussian, MPS, Flutter, Sketch, GIMP 2.10), **σ = value/2** (every *shadow* API: CSS, canvas, `CALayer.shadowRadius`, and Figma's blurs), and **σ = 0.577·value + 0.5** (Skia "radius": Android `RenderEffect`, `BlurMaskFilter`, Compose).
- Core Image's own "radius" changes meaning per filter (MEASURED): σ for `CIGaussianBlur`, **full box width** (nearest odd) for `CIBoxBlur`, disc radius for `CIDiscBlur`/`CIBokehBlur`, a 1D Gaussian σ for `CIMotionBlur` (a Gaussian streak, not a box), ≈1.09σ for `CIMaskedVariableBlur`, and an exponential zoom (1.5^(amount/20)) for `CIZoomBlur`. Apple documents none of this.
- SwiftUI `.blur(radius:)` is nominally σ but truncated at about ±2.3σ (σ_eff = 0.91·radius for r ≥ 8), and `opaque: true` is **normalised convolution** (divide by α), not clamp (MEASURED). Apple's own WebKit and Flutter's iOS embedder both map σ → Core Animation `inputRadius` 1:1.
- Edge policies come in five kinds: decal (transparent), clamp, mirror/reflect, wrap, and normalised (divide by accumulated weight: SwiftUI `opaque`, Flutter `bounds`, WebKit `inputNormalizeEdges`, vImage `kvImageTruncateKernel`, Photoshop "Prevent color bleeding").
- Colour space splits the field: CSS, SwiftUI (default), Sketch, Skia surfaces, OpenCV, vImage and ImageMagick blur **gamma-encoded** values; SVG (default `linearRGB`), Core Image, GEGL/GIMP and game engines blur **linear light**. At a black|white edge the 50% pixel is 128 vs 188; a small light keeps only 7.7% of its energy when blurred in gamma space (section 7).
- Photoshop, After Effects and Affinity do not document their radius→σ mapping; Blur2ool must label those UNVERIFIED (section 9).

Scope: how the user-facing blur control of real tools and APIs maps to the underlying math (σ, radius = kσ, box width, proprietary), with edge handling, color space (linear vs gamma sRGB, premultiplied alpha), downsampling for large radii and maximum limits.

Evidence labels (from BRIEF.md): REFERENCE (documented by spec/vendor, cited), INFERRED (proprietary internals, reasoned from indirect evidence), UNVERIFIED (could not confirm), COMPUTED (exact consequence of math), MEASURED (measured by us).

## 0. Summary table

σ is in the tool's own pixel unit (CSS px, points, image pixels) unless stated. "Box width w" means a uniform kernel of w taps; σ = √((w²−1)/12). Evidence: REFERENCE = spec, vendor doc or vendor source code; MEASURED = probed on macOS 27.2 in this study; COMPUTED = follows from the documented math; INFERRED = reasoned from indirect evidence; UNVERIFIED = not established.

| Tool / API | Control label | Units | Maps to σ as | Evidence | Source (section) |
|---|---|---|---|---|---|
| CSS `filter: blur()` | `blur(<length>)` | CSS px | σ = value | REFERENCE | Filter Effects 1 §"Filter Functions" (1.1) |
| SVG `<feGaussianBlur>` | `stdDeviation` | user units | σ = value; spec allows 3 boxes of d = ⌊1.88·s + 0.5⌋ (σ_eff ≈ 0.94–1.06·s) | REFERENCE + COMPUTED | Filter Effects 1 §9.14 (1.2) |
| CSS `box-shadow`, `text-shadow` | blur radius (3rd length) | CSS px | σ = value / 2 | REFERENCE | CSS Backgrounds 3 §6.1.2; CSS Text Decoration 3 (1.3) |
| Canvas 2D `shadowBlur` | `shadowBlur` | unscaled px | σ = value / 2 | REFERENCE | WHATWG HTML "Shadows" (1.3) |
| Canvas 2D `filter` | `"blur(10px)"` | CSS px | σ = value | REFERENCE | WHATWG HTML / Filter Effects (1.3) |
| CSS `backdrop-filter` | `blur(<length>)` | CSS px | σ = value, edge = mirror | REFERENCE | Filter Effects 2 §2.1 (1.4) |
| Chrome (Blink/cc/Skia) | CSS/SVG values | device px | σ passed through; max σ 532 device px; pre-2019 shadows used ≈0.29·radius | REFERENCE (source) | Chromium, Skia (1.5) |
| Skia `SkBlurMask::ConvertRadiusToSigma` | "radius" | px | σ = 0.57735·r + 0.5 | REFERENCE (source) | Skia `SkBlurMask.cpp` (2.1) |
| Skia GPU blur | σ | px | exact Gaussian to σ = 4, then ½× downsample steps; ±ceil(3σ) support | REFERENCE (source) | Skia `SkBlurEngine`, `FilterResult` (2.2) |
| Android `RenderEffect.createBlurEffect` | `radiusX`, `radiusY` | px | σ = 0.57735·r + 0.5 | REFERENCE (source) | AOSP hwui `RenderEffect.cpp`, `Blur.cpp` (2.3) |
| Android `BlurMaskFilter`, `setShadowLayer` | radius | px | σ = 0.57735·r + 0.5 | REFERENCE (source) | AOSP hwui `MaskFilter.cpp` (2.3) |
| Jetpack Compose `Modifier.blur` | `radiusX/Y` | dp | dp → px, then as `RenderEffect` | INFERRED | Compose `Blur.kt` (2.3) |
| Android window blur (SurfaceFlinger) | `setBackgroundBlurRadius` | px | Gaussian σ = 0.57735·r at ¼ res, or Kawase passes | REFERENCE (source) | AOSP renderengine (2.3) |
| Flutter `ImageFilter.blur` (Skia) | `sigmaX/Y` | logical px | σ = value | REFERENCE | `painting.dart` (2.4) |
| Flutter `ImageFilter.blur` (Impeller) | `sigmaX/Y` | logical px | σ′ = min(σ,500)·(1 − 3.4e−3σ + 3.4e−6σ²), cut at ±√3(σ′−0.5); σ_eff ≈ 0.75–0.78σ at 10 | REFERENCE (source) + COMPUTED | Impeller `sigma.cc` (2.4) |
| Flutter iOS platform-view backdrop | `sigmaX` | points | `CAFilter` `inputRadius` = σ | REFERENCE (source) | `FlutterPlatformViewsController.mm` (3.3) |
| SwiftUI `.blur(radius:opaque:)` | `radius` | pt | σ = radius nominal; truncated ±2.3σ for r ≥ 8 (σ_eff 0.91r); `opaque` = normalise by α | REFERENCE (doc says "radial size") + MEASURED | Apple docs; `sdk-feasibility.md` §4 (3.1) |
| SwiftUI `GraphicsContext.Filter.blur` | `radius` | pt | σ = radius ("The standard deviation of the Gaussian blur") | REFERENCE + MEASURED | iOS 27 SDK `.swiftdoc` (3.1) |
| SwiftUI `Material`, UIKit `UIBlurEffect`, Liquid Glass | style name | — | hidden; a `gaussianBlur` `CAFilter` inside | INFERRED / UNVERIFIED | (3.2) |
| `CALayer.shadowRadius` | `shadowRadius` | pt | σ = value / 2 | MEASURED | (3.3) |
| Core Animation `CAFilter` gaussianBlur (private) | `inputRadius` | pt | σ = value (WebKit and Flutter map σ → inputRadius) | REFERENCE (Apple's WebKit source) / INFERRED | WebKit `PlatformCAFiltersCocoa.mm` (3.3) |
| `CIGaussianBlur` | `inputRadius` (def 10) | px | σ = radius | MEASURED (docs say "area of effect") | (3.4) |
| `CIBoxBlur` | `inputRadius` (def 10) | px | box **width** = nearest odd to r (ties down): r 10 → w 9, σ 2.58 | MEASURED | (3.4) |
| `CIDiscBlur` | `inputRadius` (def 8) | px | disc radius = r; per-axis σ = r/2 | MEASURED | (3.4) |
| `CIMotionBlur` | `inputRadius` (def 20), `inputAngle` | px, rad | 1D Gaussian σ ≈ 0.98·r along the angle | MEASURED | (3.4) |
| `CIZoomBlur` | `inputAmount` (def 20), `inputCenter` | — | radial smear from D to 1.5^(a/20)·D, ≈ log-uniform weights | MEASURED | (3.4) |
| `CIBokehBlur` | `inputRadius` (def 20, max 500) | px | disc radius = r (plus ring/softness) | MEASURED | (3.4) |
| `CIMaskedVariableBlur` | `inputRadius` (def 5) + mask | px | σ ≈ 1.09·r·mask, saturates near σ 49 | MEASURED | (3.4) |
| `CIMedianFilter` | none | — | 3×3 median (consistent) | MEASURED | (3.4) |
| `CINoiseReduction` | `noiseLevel`, `sharpness` | — | thresholded local blur + sharpen; no σ | REFERENCE (header) | (3.4) |
| `MPSImageGaussianBlur` | `sigma` | px | σ = sigma ("approximate gaussian") | REFERENCE + MEASURED | `MPSImageConvolution.h` (3.5) |
| `MPSImageBox` | `kernelWidth/Height` (odd) | px | box width w | REFERENCE + MEASURED | (3.5) |
| `MPSImageTent` | `kernelWidth/Height` (odd) | px | two boxes of (w+1)/2 | REFERENCE + MEASURED | (3.5) |
| `MPSImageMedian` | `kernelDiameter` (odd) | px | square median window | REFERENCE | `MPSImageMedian.h` (3.5) |
| `MPSImageAreaMax/Min` | `kernelWidth/Height` (odd) | px | rectangular max/min | REFERENCE | `MPSImageMorphology.h` (3.5) |
| vImage `BoxConvolve` / `TentConvolve` / `Convolve` | `kernel_width/height` (odd) | px | box w / tent w / caller's weights | REFERENCE | `Convolution.h` (3.6) |
| Figma layer / background blur | blur value | px | σ = value / 2 (Dev Mode exports value/2 to CSS) | REFERENCE (staff forum) + INFERRED | forum.figma.com 22642 (4.1) |
| Figma drop shadow | Blur | px | σ = value / 2 (exported 1:1 as `box-shadow` blur) | INFERRED | (4.1) |
| Sketch layer (Gaussian) blur | Blur ("radius" in file) | pt | σ = value, truncated ±2.5σ, gamma space (background blur not measured) | MEASURED (sketchtool 98.3) | (4.2) |
| Sketch motion blur | Blur, Angle | pt, ° | 1D Gaussian σ ≈ 0.96·value | MEASURED | (4.2) |
| Photoshop Gaussian Blur | Radius | px | **unknown**; community guesses conflict | UNVERIFIED | (4.3) |
| Photoshop Box / Motion / Surface / Lens Blur | Radius / Distance / Radius+Threshold / Iris Radius | px | box size / streak length / bilateral radius / aperture radius (exact sizes unknown) | REFERENCE (labels) / UNVERIFIED (math) | Adobe filter reference (4.3) |
| After Effects Fast Box Blur | Blur Radius, Iterations | px, count | n box passes; σ = √(n(w²−1)/12) with w unknown | REFERENCE + COMPUTED / UNVERIFIED (w) | Adobe AE help (4.4) |
| After Effects Gaussian Blur | Blurriness | px | undocumented | UNVERIFIED | (4.4) |
| Affinity Gaussian Blur | Radius | px | undocumented | UNVERIFIED | affinity.help (4.5) |
| GIMP 2.10 / 3.0 (GEGL) | Size X / Size Y | px | σ = value (IIR Young–van Vliet for σ ≥ 1), linear light | REFERENCE (source) | GEGL `gaussian-blur.c`, `gblur-1d.c` (4.6) |
| GIMP 2.8 | Blur Radius | px | σ = (r + 1)/3.329 | REFERENCE (source) | GIMP `blur-gauss.c` (4.6) |
| Unity URP Bloom | Scatter, Max Iterations | 0–1, count | no σ: mip pyramid, 9-tap σ ≈ 1.69 texels per level, Scatter = blend lerp(0.05, 0.95) | REFERENCE (source) + COMPUTED | Unity Graphics (5.1) |
| Unity URP Gaussian DoF | Max Radius | 0.5–1.5 | scale factor, "1 at 1080p", clamped to 2 | REFERENCE (source) | (5.1) |
| Unity URP Bokeh DoF / HDRP DoF | f-number, focal length, focus distance / Max Blur | physical / px | CoC (Potmesil 1981), 42-tap ring kernel, max ≈ 14 px | REFERENCE (source) | (5.1) |
| Unreal bloom (Standard) | Size #1–#5(6), Size Scale | % of screen width ("diameter") | Gaussian sum at ½…1/64 res; diameter→σ unknown | REFERENCE + UNVERIFIED | Epic docs (5.2) |
| Unreal bloom (Convolution) | kernel image, Scale | fraction of viewport minor axis | arbitrary PSF via FFT | REFERENCE | Epic docs (5.2) |
| OpenCV `GaussianBlur` | `ksize`, `sigmaX` | px | σ given, or σ = 0.15·ksize + 0.35; ksize = 2·(3 or 4)σ + 1 | REFERENCE (source) | `smooth.dispatch.cpp` (6.1) |
| ImageMagick `-blur r×σ` | radius × sigma | px | σ = sigma; radius = support; **`-blur 10` → σ = 1** | REFERENCE (source) | `gem.c`, `mogrify.c` (6.2) |

## 1. Web platform

### 1.1 CSS `filter: blur(<length>)`

- **Control and units.** `filter: blur(10px)`. A CSS `<length>`; percentages are not accepted; negative values are invalid; omitted = `0px`.
- **Meaning.** REFERENCE. Filter Effects Module Level 1, section "Filter Functions", `blur()`: "The passed parameter defines the value of the standard deviation to the Gaussian function." The spec adds a note that this "is different to box-shadow's blur radius". So **σ = value** (in CSS px, i.e. before devicePixelRatio; on a 3x phone, `blur(10px)` is σ = 30 device pixels).
- **Markup equivalent.** REFERENCE (Filter Effects 1, section 13.1.9 "blur"): `<feGaussianBlur stdDeviation="[radius radius]" edgeMode="[edge mode]">`, "where edge mode computes to `none` for the filter property and to `duplicate` for the CSS Image `filter()` function." The spec's own placeholder name for σ here is `[radius]`, which is one source of the radius/σ confusion.
- **Edge handling.** `edgeMode=none` (zero-extend, transparent black outside). Because the filter region is UA-defined and "may increase" for `blur()` (section 13.2 "Filter region for shorthands"), the blurred element bleeds outward and its edges fade to transparent. For `filter()` on `<image>` values the edge is `duplicate` (clamp).
- **Color space.** REFERENCE: "color-interpolation-filters has no affect for Filter Functions. Filter Functions must operate in the sRGB color space." (Filter Effects 1, section 5 "The filter property"). So CSS `blur()` averages **gamma-encoded** sRGB values, unlike SVG filters, whose default is `linearRGB` (see 1.2 and section 7).
- **Alpha.** REFERENCE: "Unless otherwise stated, all image filters operate on premultiplied RGBA samples" (Filter Effects 1, section 7 "Filter Region / color space" general text, "premultiplied RGBA").
- **Implementation.** Chrome paints through Skia and maps `blur(σ)` to `SkImageFilters::Blur(σ, σ)` (REFERENCE, Chromium source, 1.5). Firefox uses WebRender (its blur internals were not examined here). Safari's composited path hands σ to Core Animation as `CAFilter` `gaussianBlur` `inputRadius` (REFERENCE, WebKit source, 3.3).
- **Max radius.** Not limited by the spec. Implementations clamp (see Skia, 2.2).

### 1.2 SVG `<feGaussianBlur stdDeviation>` and the three-box approximation

- **Control and units.** `stdDeviation="sx [sy]"` in the coordinate system set by the filter's `primitiveUnits` (default `userSpaceOnUse`, i.e. user units). Initial value 0; negative or zero disables the primitive (result = input). One axis 0 = 1D blur along the other axis.
- **Meaning.** REFERENCE (Filter Effects 1, section 9.14 "Filter primitive feGaussianBlur"): the kernel is an approximation of the normalized convolution G(x,y) = H(x) I(y), H(x) = exp(−x²/(2s²)) / √(2π s²), with s, t the standard deviations from `stdDeviation`. **σ = stdDeviation.** The spec says the blur "can be implemented as a separable convolution".
- **The three-box approximation** (REFERENCE, quoted from the same section): "For larger values of 's' (s >= 2.0), an approximation can be used: Three successive box-blurs build a piece-wise quadratic convolution kernel, which approximates the Gaussian kernel to within roughly 3%."
  - `d = floor(s * 3 * sqrt(2 * π) / 4 + 0.5)`
  - "if d is odd, use three box-blurs of size d, centered on the output pixel."
  - "if d is even, two box-blurs of size d (the first one centered on the pixel boundary between the output pixel and the one to the left, the second one centered on the pixel boundary between the output pixel and the one to the right) and one box blur of size d+1 centered on the output pixel." The two half-pixel shifts cancel, so the result is centred.
- **Where 3√(2π)/4 comes from.** COMPUTED. Three boxes of width d convolve to a quadratic B-spline of support 3d whose peak height is 3/(4d). A Gaussian's peak is 1/(s√(2π)). Setting them equal gives d = 3s√(2π)/4 ≈ 1.880·s. The formula therefore **matches peak height, not variance**. (Checked numerically: for s = 10, continuous d = 18.7997, both peaks = 0.039894.)
- **Consequence: the spec's box approximation under-blurs by about 5–6% for odd d.** COMPUTED (probe `$TMPDIR/blur2ool-stack-semantics/threebox.py`, re-run 2026-10-13). Effective σ of the cascade is √(Σ(dᵢ²−1)/12):

  | s (requested σ) | d | parity | effective σ | ratio |
  |---|---|---|---|---|
  | 2 | 4 | even | 2.121 | 1.061 |
  | 3 | 6 | even | 3.136 | 1.045 |
  | 5 | 9 | odd | 4.472 | 0.894 |
  | 8 | 15 | odd | 7.483 | 0.935 |
  | 10 | 19 | odd | 9.487 | 0.949 |
  | 20 | 38 | even | 19.162 | 0.958 |
  | 50 | 94 | even | 47.165 | 0.943 |
  | 100 | 188 | even | 94.166 | 0.942 |

  Asymptotically σ_eff → d/2 ≈ 0.940·s. A variance-matched cascade would use d = √(4s²+1) ≈ 2s (Wells 1986, "Efficient synthesis of Gaussian filters by cascaded uniform filters", IEEE PAMI; Kovesi 2010, "Fast almost-Gaussian filtering", DICTA). The "within roughly 3%" in the spec refers to kernel shape after peak matching, not to σ. This is a good on-screen teaching moment: same word, two "Gaussians", 5% apart.
- **Edge handling.** REFERENCE: `edgeMode = duplicate | wrap | none`, "The initial value for edgeMode is none" (zero RGBA outside). In the newer Filter Effects 2 draft, `backdrop-filter` uses a fourth mode, `mirror` (see 1.4). Note: older SVG 1.1 had no edgeMode on feGaussianBlur; it was added by Filter Effects 1. Browser support for `edgeMode` on feGaussianBlur is uneven (UNVERIFIED which engines honour `wrap`).
- **Color space.** REFERENCE: `color-interpolation-filters` initial value is **linearRGB** (Filter Effects 1, section 10). So a bare `<feGaussianBlur>` averages in linear light by default, while CSS `filter: blur()` of the same σ averages gamma-encoded values. The two give visibly different results on high-contrast edges (section 7).
- **Alpha.** Premultiplied RGBA (REFERENCE, same general rule as 1.1).
- **Filter region clipping.** REFERENCE: the filter region acts "as a hard clipping region for each filter primitive"; a very large stdDeviation can be clipped by the default region (x/y = −10%, width/height = 120%).

### 1.3 CSS `box-shadow` / `text-shadow` / canvas `shadowBlur`

- **Control and units.** `box-shadow: 0 4px 10px black` — the third length is the "blur radius", `<length [0,∞]>`. `text-shadow` uses the same grammar without spread/inset.
- **Meaning.** REFERENCE (CSS Backgrounds and Borders 3, section 6.1.2 "Blurring Shadow Edges"): "The exact algorithm is not defined; however the resulting shadow must approximate (with each pixel being within 5% of its expected value) the image that would be generated by applying to the shadow a Gaussian blur with a standard deviation equal to half the blur radius." So **σ = blur radius / 2**. The note explains the naming: a straight shadow edge produces a visible transition about **twice the blur radius** wide (= 4σ, i.e. ±2σ, which covers 95.4% of the Gaussian's mass).
- `text-shadow`: REFERENCE (CSS Text Decoration 3, section "Text Shadows: the text-shadow property"): "Values are interpreted as for box-shadow". **σ = blur / 2.**
- `CanvasRenderingContext2D.shadowBlur`: REFERENCE (WHATWG HTML, "Shadows"): "Let σ be half the value of shadowBlur. Perform a 2D Gaussian Blur on B, using σ as the standard deviation." Also: shadowBlur units "do not map to coordinate space units, and are not affected by the current transformation matrix" and "User agents may limit values of σ to an implementation-specific maximum". Canvas `ctx.filter = "blur(10px)"` follows CSS filter semantics (σ = 10).
- **Implementation.** Chrome draws box-shadow with Skia blur mask filters, `SkMaskFilter::MakeBlur(kNormal, σ)` where σ comes from `BlurRadiusToStdDev(radius) = radius * 0.5f` (Chromium `third_party/blink/renderer/platform/graphics/skia/skia_utils.h`; confirmed in 1.5 via `ShadowData::BlurAsSigma()`). Fast paths use analytic rounded-rect blur (error-function profile) rather than convolution (INFERRED, Skia `SkBlurMaskFilterImpl` / `GrBlurUtils` "analytic rrect blur").
- **Edge handling.** Not applicable in the usual sense: the shadow shape is a mask with zero outside.
- **Color space.** Blur is applied to the alpha mask; the color is flat, so gamma does not affect the blur itself, only the compositing of the semi-transparent ramp over the background (sRGB-space blending in all browsers, INFERRED/common knowledge).

### 1.4 CSS `backdrop-filter`

- **Control and units.** `backdrop-filter: blur(20px)`: same `blur()` function, so **σ = value** in CSS px.
- **Meaning and pipeline.** REFERENCE (Filter Effects Module Level 2, section 2.1 "Filtering and Clipping", Editor's Draft at drafts.csswg.org/filter-effects-2): copy the **Backdrop Root Image** into a buffer T′, apply the filters to all of T′, inverse-transform, clip to B's border box (with border-radius), draw B on top, composite source-over into the parent.
- **Edge handling.** REFERENCE (same section): "If the filter functions list includes a blur() filter, the filter will be applied with edgeMode="mirror", with the edge defined by the clipped, transformed border box of the element." Mirror means the pixels just inside the element's box are reflected outward, so content outside the element does **not** bleed into the frosted glass, and the glass edge does not darken. This is a change from early Chrome/Safari behaviour, which sampled outside the box (UNVERIFIED date of change; Chromium shipped mirror edge mode around M76–M114, exact version not confirmed).
- **Color space.** REFERENCE: "Filter functions must operate in the sRGB color space."
- **Backdrop root.** Opacity < 1, masks, clip-path, filters, mix-blend-mode and backdrop-filter itself all start a new Backdrop Root, so the backdrop only reads content up to the nearest such ancestor (REFERENCE, section 3 "Backdrop Root").
- **Implementation.** In Chrome the compositor (cc) runs it as a render-surface effect with `cc::FilterOperation::BLUR` → Skia (INFERRED; see 1.5). Safari maps it to a `CABackdropLayer` with a `gaussianBlur` `CAFilter` whose `inputRadius` is σ, plus `inputNormalizeEdges` (opaque backdrop) or `inputHardEdges` (REFERENCE, WebKit source, 3.3). That is the same machinery `UIVisualEffectView` uses (INFERRED).

### 1.5 Chrome/Blink cc compositor and Skia

All checks below are against Chromium `main` source fetched on 2026-10-13 (REFERENCE, source code).

- **CSS `filter: blur()` and `backdrop-filter: blur()`** become `cc::FilterOperation::BLUR` with an amount equal to σ, and `cc/paint/render_surface_filters.cc` builds `SkImageFilters::Blur(σx, σy, tileMode, …)` from it. The comment there says the crop rect is set to the layer bounds "for well-defined tiling behavior when the blur_tile_mode() is not kDecal". So the `edgeMode=mirror` for backdrop-filter in the spec maps to Skia `SkTileMode::kMirror` inside the backdrop's bounds (INFERRED from the tile-mode plumbing; the code path is there, but which tile mode backdrop-filter sets was not traced to the line).
- **SVG `<feGaussianBlur>`** (`third_party/blink/renderer/platform/graphics/filters/fe_gaussian_blur.cc`): `stdDeviation` is passed **unchanged as σ** to `BlurPaintFilter(std_x, std_y, SkTileMode::kDecal, …)`. Two details:
  - Blink **hard-codes `kDecal`**, so `edgeMode="duplicate"` or `"wrap"` on `feGaussianBlur` does nothing in Chrome. This settles part of the open question in 1.2: Chromium ignores `edgeMode` here (REFERENCE, source).
  - For bounds, Blink uses the spec's three-box width (`ApproximateBoxWidth(s) = floor(s·¾·√(2π) + 0.5)`, minimum 2) and outsets the filter rect by 3·d/2 ≈ 2.82σ. It does **not** use three boxes for the pixels. The pixels come from Skia (2.2).
- **`box-shadow`, `text-shadow`, canvas `shadowBlur`** (`core/style/shadow_data.h`): `BlurAsSigma() = BlurRadiusToStdDev(blur)`. Paint bounds are outset by `ceil(3·σ) + spread`. The conversion has been **σ = radius/2** since Chromium commit `909793b85dd2` "Update shadow blur-radius computations" (Florin Malita, 2018-12-24). The commit message says Blink had used "a scale factor of about 0.28 instead of 0.5", which made shadows about half their expected size, and that the change aligns Blink with Firefox and WebKit. **Before 2019, Chrome shadows had σ ≈ 0.288·radius, about 0.58× the spec.** 0.28 ≈ 0.57735/2 is Skia's legacy factor (2.1) applied to a half radius (INFERRED arithmetic; the old formula's exact form is not in the commit summary).
- **Max σ.** `SkBlurImageFilter` clamps σ to **532 device pixels** per axis. The source comment: "This rather arbitrary-looking value results in a maximum box blur kernel size of 1000 pixels on the raster path, which matches the WebKit and Firefox implementations" (`src/effects/imagefilters/SkBlurImageFilter.cpp`). Check: floor(532·1.87997 + 0.5) = 1000. So `filter: blur(600px)` on a 1x display renders the same as `blur(532px)`, and on a 3x display the clamp starts at `blur(177.3px)` (COMPUTED from the clamp being applied in layer/device space by `mapSigma`).
- **Identity cutoff.** σ ≤ 0.03 is treated as no blur (`SkBlurEngine::IsEffectivelyIdentity`).

## 2. Skia / Android / Flutter

### 2.1 Skia `SkBlurMask::ConvertRadiusToSigma`

REFERENCE (Skia `src/core/SkBlurMask.cpp`, main, 2026-10-13):

```cpp
// This constant approximates the scaling done in the software path's
// "high quality" mode, in SkBlurMask::Blur() (1 / sqrt(3)).
// IMHO, it actually should be 1:  we blur "less" than we should do
// according to the CSS and canvas specs, simply because Safari does the same.
static const SkScalar kBLUR_SIGMA_SCALE = 0.57735f;
SkScalar SkBlurMask::ConvertRadiusToSigma(SkScalar radius) {
    return radius > 0 ? kBLUR_SIGMA_SCALE * radius + 0.5f : 0.0f;
}
SkScalar SkBlurMask::ConvertSigmaToRadius(SkScalar sigma) {
    return sigma > 0.5f ? (sigma - 0.5f) / kBLUR_SIGMA_SCALE : 0.0f;
}
```

- **σ = 0.57735·r + 0.5 = r/√3 + 0.5.** This confirms the formula in the task. For r = 10, σ = 6.274.
- **Why 1/√3.** COMPUTED. A continuous box of half-width r (width 2r) has variance r²/3, so σ = r/√3. Skia's "radius" is the **half-width of a box whose variance matches the Gaussian**. The +0.5 is an empirical offset (UNVERIFIED rationale). One plausible reading is that a discrete box of 2r+1 taps has variance ((2r+1)²−1)/12 = r(r+1)/3, and √(r(r+1)/3) ≈ r/√3 + 0.29, but the source gives no derivation.
- The legacy name is still in public API. `SkMaskFilter::MakeBlur` takes σ directly, while Android's `BlurMaskFilter(radius)` and `Paint.setShadowLayer(radius)` go through hwui's own copy of this conversion (2.3).

### 2.2 Skia GPU Gaussian (Ganesh/Graphite, via `SkShaderBlurAlgorithm`)

REFERENCE (Skia `src/core/SkBlurEngine.h`/`.cpp`, `src/core/SkImageFilterTypes.cpp`, `src/gpu/BlurUtils.h`, main, 2026-10-13):

- **Kernel support.** `SigmaToRadius(σ) = ceil(3σ)`, so the taps run from −ceil(3σ) to +ceil(3σ) and the kernel is 2·ceil(3σ)+1 wide. Weights are the sampled Gaussian exp(−x²/(2σ²)), renormalised to sum to 1 ("the constant term … of the Gaussian" is dropped and replaced by normalisation).
- **Separable, with the linear-sampling trick.** For a 1D pass, `LinearKernelWidth(radius) = radius + 1` texture samples. Pairs of taps are merged into one bilinear fetch at a weighted offset. `kMaxSamples = 28` per pass.
- **Max σ per pass = 4** (`kMaxLinearSigma = 4.f`). The comment says this "-> radius = 27 -> linear kernel width = 28". That comment looks stale: with the current ceil(3σ) rule, σ = 4 gives radius 12 and 13 linear samples (COMPUTED). A TODO (b/297393474) says it could become 9 now that the linear trick halves the samples. There is a single-pass 2D path for very small kernels: "generally it will be small on the order of a 5x5 kernel".
- **Downsampling for σ > 4** (`FilterResult::Builder::blur`). The scale factor is s = maxSigma/σ per axis. The image is reduced in **successive ½× steps** (`downscale_step_count = NextLog2(ceil(1/s))`, with the last step between ½ and 1×), blurred at σ_low = σ·s = 4, and upscaled with bilinear filtering. Example: σ = 10 → s = 0.4 → 2 steps (½, then 0.8) → blur at σ = 4 at 40% resolution. σ = 100 → s = 0.04 → 5 steps. This is why large Skia GPU blurs are cheap and why they are subtly **non-Gaussian**: the downsample filter and the bilinear upsample convolve with the Gaussian (COMPUTED in principle; magnitude not measured).
- **CPU (raster) engine** (`SkBlurEngine.cpp`):
  - σ < 2 uses a true 1D Gaussian pass (`GaussianPass::kMaxSigma = 2`).
  - σ ≥ 2 uses the **SVG three-box approximation** (`ThreeBoxApproxPass`, window `BoxBlurWindow(σ) = floor(σ·3·√(2π)/4 + 0.5)`, the spec formula verbatim). This inherits the ~5% σ shortfall computed in 1.2.
  - `maxSigma() = 135` (box window ≤ 255). Larger σ is rescaled the same way as on the GPU.
  - A legacy `TentPass` (two boxes) supports σ up to 2183.
  - The same CSS blur can therefore differ subtly between GPU and software raster in Chrome (INFERRED consequence).
- **Edge handling.** `SkTileMode` is `kDecal` (transparent outside; the default for image filters), `kClamp`, `kRepeat` or `kMirror`. `SkImageFilters::Blur(σx, σy, tileMode, input, crop)`.
- **Color space.** Skia blurs in the space of the destination surface. For an sRGB 8-bit surface that means **gamma-encoded, premultiplied** values (INFERRED from Skia's general model: no linearization unless the surface's SkColorSpace is linear).
### 2.3 Android `RenderEffect.createBlurEffect(radiusX, radiusY, edgeTreatment)` and friends

- **Control and units.** Float "radius" in **pixels** (View/RenderNode pixels, not dp), plus `Shader.TileMode edgeTreatment` (CLAMP, REPEAT, MIRROR, DECAL). The Javadoc says only "Radius of blur along the X axis" and "Policy for how to blur content near edges of the blur kernel" (REFERENCE, `graphics/java/android/graphics/RenderEffect.java`). It never says what "radius" means.
- **Meaning.** REFERENCE (AOSP `libs/hwui/jni/RenderEffect.cpp`, main, 2026-10-13):
  ```cpp
  SkImageFilters::Blur(Blur::convertRadiusToSigma(radiusX), Blur::convertRadiusToSigma(radiusY),
                       static_cast<SkTileMode>(edgeTreatment), input, nullptr);
  ```
  `libs/hwui/utils/Blur.cpp` has the same constant as Skia, `BLUR_SIGMA_SCALE = 0.57735f`. So **σ = 0.57735·r + 0.5**: r = 10 px gives σ = 6.27 px, and r = 25 gives σ = 14.93. `edgeTreatment` is cast straight to `SkTileMode`. Pixels then go through the Skia GPU path in 2.2 (σ > 4 downsampled).
- **The same conversion is used by** `BlurMaskFilter(radius, style)` (`libs/hwui/jni/MaskFilter.cpp`, own copy of `kBLUR_SIGMA_SCALE = 0.57735f`) and `EmbossMaskFilter`. hwui also keeps a `legacyConvertRadiusToSigma(r) = 0.3·r + 0.6` for its old CPU Gaussian weight generator (`Blur::generateGaussianWeights`), a third mapping in the same file.
- **Jetpack Compose** `Modifier.blur(radiusX: Dp, radiusY: Dp, edgeTreatment: BlurredEdgeTreatment)` converts dp → px and, on Android 12+, creates a `RenderEffect` blur. So it inherits σ = 0.577·r_px + 0.5 (INFERRED: `compose/ui/ui/src/commonMain/.../draw/Blur.kt` builds a `BlurEffect(radiusX.toPx(), …)`; the androidMain file mapping `BlurEffect` → `RenderEffect.createBlurEffect` was not fetched, because its path 404'd). On Android < 12 `Modifier.blur` is a no-op (REFERENCE, Compose docs, widely documented; UNVERIFIED against current source).
- **Window and backdrop blurs (SurfaceFlinger, Android 12+).** `WindowManager.LayoutParams.setBlurBehindRadius(int)` and `Window.setBackgroundBlurRadius(int)` take an integer "radius" in pixels, which the system compositor blurs. REFERENCE (AOSP `frameworks/native/libs/renderengine/skia/filters/`):
  - all variants first **downscale the region to `kInputScale = 0.25`** (`BlurFilter.h`).
  - `GaussianBlurFilter`: `SkImageFilters::Blur(r·0.25·0.57735, …, SkTileMode::kClamp)` on the quarter-res image. That is σ = 0.577·r in full-res pixels, **without** the +0.5, with **clamp** edges.
  - `KawaseBlurFilter` (the long-time default): 5-tap diagonal "Kawase" shader (`c + 4 diagonal taps at ±offset`, ×0.2), r/2 split over up to `kMaxPasses = 4` passes with offsets i·(r/2)/passes. It is not a Gaussian.
  - `KawaseBlurDualFilter` (newer): radius·0.57735 drives a dual-filter pyramid (downscale 1×, 2×, 4× beyond the initial ¼).
  - Which filter a given device uses depends on build flags (UNVERIFIED per device). **So "radius 10" means σ = 6.27 in a View's RenderEffect but a 4-pass Kawase in the window compositor.**

### 2.4 Flutter `ImageFilter.blur(sigmaX, sigmaY, tileMode, bounds)`

- **Control and units.** σ in logical pixels (scaled by the canvas transform). The API doc says: "The `sigma_x` and `sigma_y` are the standard deviation of the Gaussian kernel in the X direction and the Y direction, respectively." `tileMode` sets edge sampling. **σ = sigmaX** (REFERENCE, `engine/src/flutter/lib/ui/painting.dart`, master, 2026-10-13). `BackdropFilter(filter: ImageFilter.blur(...))` is the frosted-glass widget.
- **Bounded blur (new).** If `bounds` is set, "the image filter substitutes transparent black for any sample it reads from outside the defined bounding rectangle. The final weighted sum is then divided by the total weight of the non-transparent samples … resulting in opaque output". The doc says this is for "iOS-style frosted glass effects". This is **normalized convolution**: the edge does not darken and does not bleed. It is a fourth edge policy, distinct from clamp, mirror and decal, and Blur2ool should teach it (REFERENCE).
- **Skia backend.** `SkImageFilters::Blur(σx, σy, tileMode)`, so section 2.2 applies (σ>4 downsampled, max σ 532).
- **Impeller backend** (default on iOS since Flutter 3.10, and on Android in newer releases; dates UNVERIFIED). REFERENCE (`impeller/entity/contents/filters/gaussian_blur_filter_contents.cc`, `impeller/geometry/sigma.cc`, master, 2026-10-13):
  - **Impeller does not use the σ you pass.** `ScaleSigma(σ) = min(σ,500)·(1 − 3.4e−3·σ + 3.4e−6·σ²)`. The comment: "This function was calculated by observing Skia's behavior. Its blur at 500 seemed to be 0.15. Since we clamp at 500 I solved the quadratic equation that puts the minima there and a f(0)=1." `kMaxSigma = 500` ("Limit the kernel size to 1000x1000 pixels, like Skia does").
  - **Kernel half-width** = `Sigma→Radius` = (σ′ − 0.5)·√3 (`kKernelRadiusPerSigma = 1.73205080757`). This is the inverse of Skia's legacy `ConvertRadiusToSigma`, used here as a truncation radius. The Gaussian is therefore cut at about ±1.7σ′ and renormalized (taps beyond radius 16 also drop the outermost pair). The kernel is capped at `kGaussianBlurMaxKernelSize = 50` taps, ×2 with the "lerp hack" (linear-sampling pairs).
  - **Downsample** factor = 4/σ rounded to the nearest power of two, floor 1/16 (`CalculateScale`), with no downsampling for σ ≤ 4.
  - COMPUTED consequences (probe `impeller.py`; it ignores the extra low-pass of the down/up-sample):

    | requested σ | ScaleSigma σ′ | half-width | effective σ after truncation | ratio |
    |---|---|---|---|---|
    | 4 | 3.95 | 5.97 | 3.12 | 0.78 |
    | 10 | 9.66 | 15.9 | 7.81 | 0.78 |
    | 50 | 41.9 | 71.8 | 34.1 | 0.68 |
    | 100 | 69.4 | 119 | 56.3 | 0.56 |
    | 200 | 91.2 | 157 | 74.2 | 0.37 |
    | 500 | 75.0 | 129 | 61.0 | 0.12 |

    Re-check on 2026-10-13 (`impeller.py` recreated): the large-σ rows reproduce exactly (σ = 100 → 56.3, 200 → 74.2, 500 → 61.0). The small-σ rows depend on how the half-width is rounded to taps: with integer taps out to ⌊half-width⌋, σ = 4 → 2.78 and σ = 10 → 7.51 instead of 3.12 and 7.81. Impeller's exact tap rounding was not traced, so treat σ_eff(10) as 7.5–7.8 (COMPUTED range).

    σ′(σ) is **non-monotonic**. It peaks at σ ≈ 219 (σ′ ≈ 91.6) and dips to a minimum at σ ≈ 448, so `sigmaX: 219` is blurrier than `sigmaX: 400` under Impeller (COMPUTED from the formula; not MEASURED on a device). A Flutter frosted panel with `sigma: 10` is visibly softer than CSS `blur(10px)`.

## 3. Apple platforms

Measurement note for this section. Probes are in `$TMPDIR/blur2ool-stack-semantics/` (`ciprobe.swift`, `ciprobe2.swift`, `swiftuiprobe2.swift`), run on 2026-10-13 on the Mac described in `live-calibration.md` (M1 Max, macOS 27.2, Xcode-beta 27.0 SDK). Method: render a 1-pixel vertical white line through the filter in a 32-bit float pipeline with colour management off, read one row (the line-spread function, LSF) and take its second central moment. For a 2D separable or radially symmetric kernel, the LSF variance equals the per-axis variance of the 2D kernel, so σ_LSF is the σ that matters. Everything marked MEASURED is macOS 27.2. iOS 27 on A17 Pro may differ (the SwiftUI result was byte-identical in the iOS 27.0 simulator, `sdk-feasibility.md` section 4, but the simulator runs on the Mac GPU). Distinct kernel shapes are recognisable by kurtosis of the LSF: Gaussian 3.0, triangle (tent) 2.4, semicircle (projection of a uniform disc) 2.0, box 1.8.

### 3.1 SwiftUI `.blur(radius:opaque:)` and `GraphicsContext.Filter.blur(radius:options:)`

- **Control and units.** `radius: CGFloat` in **points** (multiply by the display scale for device pixels: ×3 on iPhone 15 Pro Max). `opaque: Bool = false`. Also available as a `VisualEffect` (iOS 17+) and as a `Canvas` filter.
- **What the docs say.** REFERENCE. `View.blur(radius:opaque:)`: "Applies a Gaussian blur to this view." radius: "The radial size of the blur. A blur is more diffuse when its radius is large." opaque: "whether the blur renderer permits transparency in the blur output" (developer.apple.com/documentation/swiftui/view/blur(radius:opaque:)). The `Canvas` variant, `GraphicsContext.Filter.blur(radius:options:)`, says radius is **"The standard deviation of the Gaussian blur."** `BlurOptions.opaque`: "The filter ensure opacity by dividing each pixel by its alpha value" (doc comments extracted from the iOS 27 SDK `.swiftdoc`, `sdk-feasibility.md` section 3).
- **Meaning.** MEASURED (`sdk-feasibility.md` section 4, macOS 27.2 and iOS 27.0 simulator, `ImageRenderer` offscreen path): **σ = radius** up to r ≈ 4. From r = 8 upward, the kernel is truncated at about ±2.3·radius and renormalised, so the second-moment σ is 0.909·radius (kurtosis 2.53 instead of 3). `View.blur`, `Canvas` `.blur` and `.drawingGroup().blur` gave identical σ. So the nominal meaning is "radius = σ in points"; the practical PSF is a truncated Gaussian. At r = 10 pt on a 3x phone, nominal σ = 30 px.
- **The `opaque` flag is an edge policy.** MEASURED here (`swiftuiprobe2.swift`, a 200×40 pt black|white step drawn in a `Canvas`, `.blur(radius: 10)`):
  - `opaque: false` (default) is **decal**: transparent black outside the view. On a 120×60 pt opaque white rectangle, alpha is 0.52 at the view's edge, 0.87 at 1σ inside, 0.99 at 2σ and 1.00 at 3σ. The view fades out at its borders and its bounds grow outward.
  - `opaque: true` is **normalised convolution**: the same decal blur, then colour ÷ alpha. At x = 199 the premultiplied (0.514, α 0.514) becomes (1.0, α 1.0). Edges neither darken nor fade, and nothing is sampled from outside. This matches the `BlurOptions.opaque` doc text, and it is the same policy as Flutter's bounded blur (2.4) and WebKit's `inputNormalizeEdges` (3.3). It is not clamp-to-edge. Apple's warning that the result "may be undefined if the input to the filter isn't also completely opaque" follows directly: dividing by α changes the colours of genuinely transparent content.
- **Colour space.** MEASURED. The blur averages in the **rendering working space**, which SwiftUI calls `ColorRenderingMode`. At the first pixel on the white side of the black|white step:
  - `colorMode = .nonLinear`: stored sRGB-encoded value 0.514, which is the average of the *encoded* values. That is gamma-space blurring.
  - `colorMode = .extendedLinear`: linear value 0.514, i.e. encoded 0.744. That is linear-light blurring.
  - On screen, SwiftUI renders in `.nonLinear` unless a `drawingGroup(opaque:colorMode:)` says otherwise (INFERRED from `ColorRenderingMode`'s default being `.nonLinear` in `ImageRenderer` and `drawingGroup`; the on-screen render server path was not measured). So the usual `.blur` result is **gamma-space**, like CSS `filter: blur()`.
- **Implementation.** INFERRED. On screen, SwiftUI probably hands `.blur` to Core Animation as a `CAFilter` `gaussianBlur` on the view's layer, executed by the render server, while `ImageRenderer` uses SwiftUI's in-process rasterizer. The offscreen path is the one we measured. No public document confirms the on-screen route.
- **Max radius.** Not documented (UNVERIFIED). The ±2.3σ truncation is MEASURED and scale-invariant (r = 8, 16 and 32 give the same 0.909 ratio), which suggests a downsample pyramid (INFERRED).

### 3.2 SwiftUI `Material`, UIKit `UIBlurEffect` / `UIVisualEffectView`, Liquid Glass

- **Control and units.** None. SwiftUI offers `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`, `.thickMaterial`, `.ultraThickMaterial`, `.bar`; UIKit `UIBlurEffect.Style` has `.systemUltraThinMaterial` … `.systemChromeMaterial` (plus legacy `.light`, `.dark`, `.extraLight`, `.regular`, `.prominent`); iOS 26+ `glassEffect(_:in:)` / `UIGlassEffect`. **No radius is exposed.** REFERENCE (iOS 27 SDK headers, `sdk-feasibility.md` section 3).
- **Meaning.** INFERRED (partly REFERENCE via Flutter's embedder, 3.3, which finds a `gaussianBlur` `CAFilter` with `inputRadius` inside `UIVisualEffectView`). These are system backdrop effects: a `CABackdropLayer` samples what is behind the view, applies a `gaussianBlur` `CAFilter` plus saturation/colour-matrix and tint layers, and the render server composites it. The exact radii are private and can change per OS release and per style. Community reverse-engineering of private `_UIVisualEffect*` classes has reported numbers, but none were verified here (UNVERIFIED). The app should present materials as "system effect, parameters hidden" and, if anything, measure them from a screenshot of a known background.
- **Edge handling.** INFERRED: backdrop blurs use the `inputNormalizeEdges` / `inputHardEdges` keys that WebKit sets on its own backdrop layers (3.3), so materials do not pull in colours from outside the view's bounds.
- **Not measurable in-process.** `ImageRenderer` renders system/backdrop effects as placeholders (Apple's doc comment on `ImageRenderer`, `sdk-feasibility.md` section 4).

### 3.3 Core Animation `CAFilter` `gaussianBlur` (private)

- **Control.** Private SPI: `[CAFilter filterWithType:kCAFilterGaussianBlur]` with key `inputRadius`, set on `CALayer.filters` or on a `CABackdropLayer`. Other keys seen in Apple's own open-source code: `inputNormalizeEdges`, `inputHardEdges`, `inputNormalizeEdgesTransparent` (visionOS). Third-party code also uses `inputQuality` and a private `variableBlur` filter type (INFERRED, not verified).
- **Meaning.** REFERENCE (Apple's own code, not Apple's documentation). WebKit maps CSS `filter: blur(σ)` and `backdrop-filter: blur(σ)` straight to it: `[filter setValue:@(blurOperation->stdDeviation()) forKey:@"inputRadius"]` (WebKit `Source/WebCore/platform/graphics/ca/cocoa/PlatformCAFiltersCocoa.mm`, `main`, fetched 2026-10-13, lines 309–329). WebKit relies on **`inputRadius` = σ** (in layer points). Flutter's iOS embedder does the same for `BackdropFilter` over platform views: it copies the `gaussianBlur` `CAFilter` out of a `UIVisualEffectView`'s backdrop layer and sets `inputRadius` to the Dart-side `sigma_x` ("sigma_x is arbitrarily chosen as the radius value because Quartz sets sigma_x and sigma_y equal to each other"; `FlutterPlatformViewsController.mm` and `FlutterPlatformViews.mm`, flutter/flutter `master`, fetched 2026-10-13). So two independent vendors map σ → `inputRadius` 1:1, and a `UIVisualEffectView` does contain a `gaussianBlur` `CAFilter` with an `inputRadius` (Flutter checks for it at runtime and logs an error if Apple removes it). Together with the SwiftUI measurement (σ = radius before truncation), this is the best available evidence that Core Animation's "radius" is a standard deviation. Whether the render server truncates at about 2.3σ the way SwiftUI's offscreen path does is UNVERIFIED.
- **Edge handling.** REFERENCE, same file: for a `CABackdropLayer`, WebKit sets `inputNormalizeEdges = YES` when the backdrop is opaque and `inputHardEdges = YES` when it is not. The names suggest normalised convolution and hard (clipped) edges respectively (INFERRED meaning; the keys themselves are REFERENCE). This is how Safari implements the spec's `edgeMode="mirror"` requirement for `backdrop-filter` (1.4): it uses normalisation instead of mirroring, which also avoids bleed (INFERRED).
- **Public relatives.** `CALayer.shadowRadius` (public, "The blur radius (in points) used to render the layer's shadow", default 3). MEASURED here with `CALayer.render(in:)` on macOS 27.2 (edge derivative of a shadow-casting black layer): σ/shadowRadius = 0.469, 0.493, 0.496, 0.501 for shadowRadius = 2, 5, 10, 20. So **σ = shadowRadius / 2**, the same convention as CSS `box-shadow`. This is why "CSS box-shadow blur 20px" ≈ `layer.shadowRadius = 10` (COMPUTED from REFERENCE + MEASURED).

### 3.4 Core Image

Core Image's headers (iOS 27 SDK `CIFilterBuiltins.h`) describe nearly every blur radius with the same sentence, "The radius determines how many pixels are used to create the blur. The larger the radius, the blurrier the result." Apple's current `gaussianBlur()` page says the radius is "the area of effect" and "the effect targets the pixels within a circle defined by a radius" (developer.apple.com/documentation/coreimage/cifilter-swift.class/gaussianblur()). The archived Core Image Filter Reference gives only type and default (developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference). **No Apple document says what radius means mathematically for any Core Image blur.** The following is MEASURED (probe `ciprobe.swift`/`ciprobe2.swift`, float RGBAf, `workingColorSpace = NSNull`, input `clampedToExtent()`, output cropped). Attribute defaults and slider ranges come from `CIFilter.attributes` at runtime (REFERENCE, runtime metadata).

| Filter | Parameter (default, sliderMax, type) | MEASURED meaning | Kernel shape (LSF kurtosis) | radius = 10 gives |
|---|---|---|---|---|
| `CIGaussianBlur` | `inputRadius` (10, 100, Scalar; min 0) | **σ = radius** (ratio 0.993–1.005 for r = 2…50) | Gaussian (2.86–2.98), support ≈ ±4σ | σ = 10.0 |
| `CIBoxBlur` | `inputRadius` (10, 100, Distance; min 1) | **full box width = nearest odd integer to radius, ties rounded down** (r = 10 → 9 px, 10.5 → 11, 16 → 15, 25 → 25). So the "radius" is really a **diameter**; σ = √((w²−1)/12) ≈ 0.289·r | square box (1.77–1.80) | 9-px box, σ = 2.58 |
| `CIDiscBlur` | `inputRadius` (8, 100, Distance) | **disc radius = radius** (σ_LSF = r/2, the moment of a uniform disc; 2σ = 9.999 at r = 10) | uniform disc (2.00) | disc of radius 10, σ = 5.0 |
| `CIMotionBlur` | `inputRadius` (20, 100, Distance), `inputAngle` (0, radians) | **σ along the motion direction ≈ radius** (0.98–0.99·r), and the profile is **Gaussian, not a box** (kurtosis 2.92–2.96); support ≈ ±3.9r. Energy 0.989–0.993 | 1D Gaussian streak | 1D σ ≈ 9.86 along the angle |
| `CIBokehBlur` | `inputRadius` (20, max 500, slider 100), `ringAmount` (0), `ringSize` (0.1), `softness` (1) | **disc radius = radius** (σ_LSF = 0.493·r at softness 0) | disc (1.95–2.00) | disc of radius 10 |
| `CIMaskedVariableBlur` | `inputRadius` (5, slider 10, Scalar), `inputMask` (green channel 0…1) | **σ ≈ 1.094·radius·mask** (r = 2…40 at mask 1; mask 0.5 at radius r gives exactly the σ of mask 1 at r/2). Saturates near σ ≈ 49 (r = 80 gave the same support as r = 40) | Gaussian (2.98) | σ ≈ 10.9 at mask 1 |
| `CIZoomBlur` | `inputCenter` (150,150), `inputAmount` (20, slider 200, Distance) | a point at distance D from the centre is smeared radially outward over [D, s·D] with **s = 1.5^(amount/20)** (fits 1.2247 at 10, 1.5 at 20, 2.25 at 40 to within 1%). Weighting is close to log-uniform (density ∝ 1/r), not uniform | radial streak whose length is proportional to D | amount 10: 22.5% longer, 1.22× zoom |
| `CIMedianFilter` | none | consistent with a **3×3** median (a 1-px line vanishes; a 2-px line survives, which a 5×5 window would erase) | rank filter, not a convolution | n/a |
| `CINoiseReduction` | `inputNoiseLevel` (0.02), `inputSharpness` (0.4) | luminance-thresholded local blur plus sharpening (header text). Not a single PSF; σ not measured | nonlinear | n/a |
| `CIMorphologyMaximum/Minimum` | `inputRadius` (0, slider 50) | circular max/min of radius r (header: "circular morphological operation") | rank | n/a |

Further Core Image facts:
- **Edge handling.** Core Image images have infinite extent semantics. Without `clampedToExtent()` the outside is transparent (decal): an unclamped 513×65 image blurred with `CIGaussianBlur` r = 10 returned an output extent grown by exactly 3σ on every side, (−30, −30, 573, 125), with premultiplied value 0.520 at the original edge (MEASURED). Apple's documented idiom for "no dark edge" is `clampedToExtent()` before and `cropped(to:)` after (clamp edge policy) (REFERENCE, `CIImage.clampedToExtent()` docs).
- **Colour space.** REFERENCE plus MEASURED. A default `CIContext` works in **extended linear sRGB, half-float** (`workingColorSpace` printed as "sRGB IEC61966-2.1 Linear; extended range", `workingFormat` RGBAh). Core Image linearises sRGB inputs, blurs in linear light and re-encodes. With an 8-bit sRGB black|white step and r = 10, the 50% point comes out as **191** in the default context, against **133** with `workingColorSpace = sRGB` or no colour management (MEASURED). So Core Image is the one Apple API whose default blur is linear-light, while SwiftUI's default is gamma-space.
- **Premultiplied alpha.** Core Image's working format is premultiplied RGBA (REFERENCE: Core Image Programming Guide, "images are premultiplied" in its working space; not re-checked in this session, UNVERIFIED wording).
- **Large radii.** `CIGaussianBlur` stayed Gaussian (kurtosis 2.96) up to r = 50. The r = 100 run hit the probe's image border, so behaviour above 50 was not measured. Core Image is known to downsample internally for large σ (INFERRED, not measured).

### 3.5 Metal Performance Shaders

REFERENCE (iOS 27 SDK `MPSImage.framework/Headers/MPSImageConvolution.h`, `MPSImageMedian.h`, `MPSImageMorphology.h`, `MPSCore.framework/Headers/MPSCoreTypes.h`) and MEASURED (`ciprobe.swift`, rgba32Float, `edgeMode = .clamp`).

- **`MPSImageGaussianBlur(device:sigma:)`.** The header defines `sigma` as "The standard deviation of gaussian blur filter" with weight formula w(i) ∝ exp(−i²/(2σ²)) and a 1% cut-off "ceil(3.7*sigma)" as a rough filter width. **σ = sigma.** It warns that it is "an approximate gaussian" whose non-Gaussian behaviour "may be detectable with advanced analytical methods such as FFT", "suitable for … ~10 bits of precision or less". MEASURED: σ_LSF/sigma = 1.037, 1.005, 0.993, 0.999, 1.003, 0.992 for sigma = 1, 2, 5, 10, 20, 50; kurtosis 2.86–2.98; support ≈ ±3.9σ. Its cost does not grow with σ (`sdk-feasibility.md` section 8), which points to a scale-invariant algorithm (INFERRED).
- **`MPSImageBox(kernelWidth:kernelHeight:)`.** Width and height in **pixels, must be odd**: the full box width. MEASURED σ = √((w²−1)/12) exactly (w = 21 gives 6.055). Separable.
- **`MPSImageTent`.** Same initialiser. The header shows a 5-wide tent equals two 3-wide boxes. MEASURED: tent of width w = two boxes of width (w+1)/2, so σ = √((((w+1)/2)²−1)/6) (w = 21 gives 4.472, matching exactly), kurtosis → 2.4.
- **`MPSImageMedian(kernelDiameter:)`.** Odd diameter, square window, "currently only supports images with <= 8 bits/channel" (header).
- **`MPSImageAreaMax/Min(kernelWidth:kernelHeight:)`.** Odd rectangular max/min. Header: "The edgeMode property is assumed to always be MPSImageEdgeModeClamp for this filter."
- **Edge handling.** `MPSImageEdgeMode`: `.zero` ((0,0,0,0), or (0,0,0,1) for formats without alpha), `.clamp`, and `.mirror`, `.mirrorWithEdge` and `.constant` (iOS 12.1+), which the header says only `MPSNNPad` supports ("using this with other filters results in undefined behavior").
- **Colour space.** MPS does arithmetic on whatever the texture holds. An `.rgba8Unorm_srgb` texture is linearised on read and re-encoded on write (Metal sRGB pixel-format semantics, REFERENCE: Metal Shading Language spec, sRGB textures), so the pixel format decides linear vs gamma, not MPS.

### 3.6 Accelerate vImage

REFERENCE (iOS 27 SDK `Accelerate.framework/Frameworks/vImage.framework/Headers/Convolution.h`).

- **`vImageBoxConvolve_*` (`kernel_height`, `kernel_width`).** Full box width in pixels, **must be odd**. "A box kernel is a kernel populated with all 1's … the cost of a box convolve algorithm is theoretically constant regardless of kernel size." σ = √((w²−1)/12) (COMPUTED).
- **`vImageTentConvolve_*`.** Full tent width in pixels, odd. "A tent kernel is a kernel populated with slope of 1 rising towards the center", e.g. {1,2,3,2,1}, 2D as the outer product. σ = √((((w+1)/2)²−1)/6) (COMPUTED; same as `MPSImageTent`).
- **`vImageConvolve_*` / `vImageConvolveFloatKernel_*`.** Arbitrary odd-sized kernel plus divisor and bias; the caller supplies the weights, so σ is whatever the caller sampled.
- **Edge flags** (exactly one is required): `kvImageCopyInPlace` (leave edge pixels unconvolved, "a ring of unconvolved content"), `kvImageBackgroundColorFill` (constant colour, i.e. decal when the colour is transparent), `kvImageEdgeExtend` (clamp), `kvImageTruncateKernel` (drop the missing taps and renormalise "the bias and divisor", which is normalised convolution).
- **Colour space.** None: vImage works on raw numbers. Blurring an 8-bit sRGB buffer directly is gamma-space blurring. The caller must convert to linear (e.g. with `vImageConvert_*` and a transfer function) for linear-light results.
- Accelerate has **no Gaussian convenience function**. A Gaussian is either a sampled kernel through `vImageConvolve`, or approximated by repeated box/tent passes, which the header itself describes ("If this process is continued, the shape converges towards a gaussian").

## 4. Design tools

### 4.1 Figma

- **Controls and units.** Effects panel: **Layer blur** (blurs the layer itself; Uniform or **Progressive** with start/end values along a line) and **Background blur** (blurs what is behind a layer with a semi-transparent fill). One numeric value in **px** (canvas pixels at 100% zoom). Drop shadow / inner shadow have a separate "Blur" value plus spread. (REFERENCE for the controls: Figma's Design panel UI and help centre, also described by third parties such as grida.co "Figma blur effects"; the help-centre article itself was not fetched, UNVERIFIED wording.)
- **Meaning.** REFERENCE (second-hand, Figma staff): Figma Community Support relayed an engineering answer on 30 July 2024 that the Dev Mode CSS code divides the value by 2 "due to the Figma radius effect being effectively double", so a Figma background blur of 30 is exported as `backdrop-filter: blur(15px)` (forum.figma.com, "Background blur is different in Dev Mode", thread 22642). A 2023 thread reports the same halving for layer blur (Figma 4 → `filter: blur(2px)`; forum.figma.com thread 81631). Since CSS `blur()` takes σ (1.1), **Figma blur value v ≈ 2σ, i.e. σ = v/2** (INFERRED from the export rule; not measured against Figma's own renderer here). This is the same convention as CSS `box-shadow`, and Figma's drop-shadow "Blur" is exported 1:1 as the `box-shadow` blur radius (e.g. the default `0px 4px 4px rgba(0,0,0,0.25)`), so all Figma blurs plausibly share "value = 2σ" (INFERRED).
- **Implementation.** INFERRED. Figma renders with its own C++ engine compiled to WebAssembly and drawing through WebGL (and newer WebGPU), so the blur kernel, edge policy, downsampling and colour space are Figma's own. Figma's engineering blog describes the renderer in general terms but not the blur algorithm (UNVERIFIED that any public post covers it). Edge behaviour visible in the app: layer blur bleeds outward and fades to transparent (decal); background blur samples only within the layer's shape. Colour space: Figma documents work in sRGB or Display P3 document colour profiles; whether blur averages encoded or linear values was not measured (UNVERIFIED).
- **Practical consequence.** A designer's "Layer blur 20" is σ = 10. In SwiftUI that is `.blur(radius: 10)`; in CSS `filter: blur(10px)`; in Android `RenderEffect` it would need radius ≈ (10 − 0.5)/0.577 = 16.5 (2.3).

### 4.2 Sketch

- **Controls and units.** Effects: **Layer Blur**, **Background Blur** (with **Saturation**), **Motion blur** (Blur + Angle in degrees, 0° = horizontal) and **Zoom blur** (Blur + a centre point dragged on the canvas). Layer and background blur have Uniform, Linear Progressive and Radial Progressive styles. The documentation gives no units or formula (REFERENCE: Sketch docs, "Layer and Background Blur" and "Motion and Zoom Blur", sketch.com/docs/symbols-and-styles/styling/effects/).
- **File format.** REFERENCE: the open Sketch file format stores every blur as `{"_class": "blur", "type": 0|1|2|3 (Gaussian, Motion, Zoom, Background), "radius", "motionAngle", "center", "saturation", "isEnabled"}` (github.com/sketch-hq/sketch-file-format, `packages/file-format/schema/objects/blur.schema.yaml` and `enums/blur-type.schema.yaml`). The stored name is `radius`.
- **Meaning.** MEASURED here with Sketch 98.3's `sketchtool export` on macOS 27.2 (`$TMPDIR/blur2ool-stack-semantics/sketch/make.py` writes a `.sketch` file with a white half-plane on black artboards; `measure.py` differentiates the exported 8-bit edge to get the LSF):

  | Sketch blur | radius | σ (encoded values) | σ / radius | LSF kurtosis | value at the edge (px 299, 300) |
  |---|---|---|---|---|---|
  | Gaussian | 1 | 1.03 | 1.03 | 2.59 | 67, 163 |
  | Gaussian | 2 | 2.01 | 1.00 | 2.63 | 97, 150 |
  | Gaussian | 5 | 5.04 | 1.01 | 2.59 | 117, 138 |
  | Gaussian | 10 | 9.99 | 1.00 | 2.57 | 124, 131 |
  | Gaussian | 20 | 19.97 | 1.00 | 2.58 | 126, 129 |
  | Gaussian | 40 | 40.26 | 1.01 | 2.56 | 127, 128 |
  | Motion (0°) | 5 / 10 / 20 | 4.78 / 9.58 / 19.16 | 0.96 | 2.82 | — |

  So **Sketch Gaussian "radius" = σ** (in points at 1x). The kernel is a truncated Gaussian (kurtosis 2.57, support about ±2.5σ), not a full one. Sketch's motion blur is a **Gaussian-profiled streak** with σ ≈ 0.96·radius along the angle, the same fingerprint as `CIMotionBlur` (3.4), which suggests Sketch uses Core Image's motion blur (INFERRED).
- **Colour space.** MEASURED: the blurred black|white edge crosses at 127/128, the mean of the *encoded* values. Sketch blurs in **gamma-encoded sRGB**. A linear-light blur would put the crossing near 188.
- **Edge handling.** Layer blur spreads beyond the layer's bounds (decal: transparent outside the shape). In the exports, the blur of the half-plane's left edge reaches about 2.5σ into the black background (support starts at x = 274 for radius 10, edge at x = 300).

### 4.3 Adobe Photoshop

REFERENCE for the controls: Adobe, "Filter effects reference", Blur filters section (helpx.adobe.com/photoshop/using/filter-effects-reference.html, read from the Internet Archive's 2024 copy because helpx returns HTTP 403 to scripted fetches), and "Blur Gallery" (helpx.adobe.com/photoshop/using/blur-gallery.html, same route).

- **Gaussian Blur: "Radius (pixels)".** Adobe says only that "Gaussian refers to the bell-shaped curve that is generated when Photoshop applies a weighted average to the pixels". Older help text gives the range 0.1–250; current versions accept up to 1000 (PCWorld, "How to use Photoshop blur filters"; UNVERIFIED against Adobe). **What "Radius" means in σ is not documented, and the public evidence conflicts. UNVERIFIED.**
  - ImageMagick's Fred Weinhaus (fmw42) guessed that a Photoshop radius is "either the same as IM sigma or about 2*sigma+1" and said it needs testing (ImageMagick forum, "Gaussian blur slow (and different) compared to Photoshop CC").
  - Royi Avital ("Drazick") implemented σ = Radius with a ceil(3·Radius) kernel and reported it was "way more blurred than Photoshop" (Luminous Landscape forum, "The Math of Photoshop's Unsharp Mask and Gaussian Blur", topic 89428).
  - Jeff Schewe stated in the same thread that Photoshop uses "three of them [algorithms] based on the radius that is set", possibly four now that the range reaches 1000. If true, the effective σ/Radius ratio may change at the switch points.
  - Blur2ool should therefore label Photoshop's mapping UNVERIFIED and, if it shows a number, show the procedure: blur a one-pixel line in a 32-bit document at Radius = 1, 2, 5, 10, 20, 50, export as float TIFF, and fit σ from the line-spread function, as done for Sketch in 4.2.
- **Box Blur: "Radius".** "You can adjust the size of the area used to calculate the average value for a given pixel; a larger radius results in greater blurring." Whether the box is 2r+1 or r wide is UNVERIFIED.
- **Motion Blur: "Angle" and "Distance".** "Blurs in the specified direction (from –360º to +360º) and at a specified intensity (from 1 to 999)". Adobe calls it "analogous to taking a picture of a moving object with a fixed exposure time", which describes a uniform line PSF of length = Distance. Whether the implementation is a uniform streak or a weighted one is UNVERIFIED.
- **Radial Blur.** Spin (degrees of rotation) or Zoom ("a value from 1 to 100"), quality Draft/Good/Best, centre set by dragging.
- **Surface Blur: "Radius" and "Threshold".** "Blurs an image while preserving edges … Pixels with tonal value differences less than the Threshold value are excluded from the blur." Read literally, this is backwards: in use, raising Threshold increases the blurring (at the maximum it approaches a plain blur), so the pixels excluded are those whose difference *exceeds* the threshold (INFERRED from the filter's behaviour). That is a bilateral-style range gate. After Effects' help says Bilateral Blur "is very similar to the result of the Surface Blur filter in Adobe Photoshop" (4.4). Radius 1–100 and Threshold 2–255 are commonly quoted (UNVERIFIED).
- **Smart Blur.** Radius ("the size of the area searched for dissimilar pixels"), Threshold, Quality and modes Normal / Edge Only / Overlay Edge.
- **Shape Blur.** A custom shape as the kernel; "Radius determines the size of the kernel."
- **Lens Blur.** A depth-of-field simulation with a depth map, Iris shape/Radius/Blade Curvature/Rotation, Specular Highlights (Brightness, Threshold) and Noise. Iris "Radius" is the radius of the polygonal aperture PSF, i.e. a disc-like kernel whose radius is the parameter (INFERRED from the UI; the 2023 help page was not retrievable).
- **Blur Gallery** (Field, Iris, Tilt-Shift, Path, Spin): spatially varying blurs set by on-canvas pins, with a Bokeh panel (Light Bokeh, Bokeh Color, Light Range). These are lens-style blurs (Adobe: "For Lens blurs (Field blur, Iris blur, and Tilt/Shift blur)…").
- **Live Gaussian Blur** (Photoshop 24.0, October 2022, Technology Preview): adds a **"Prevent color bleeding"** checkbox for selections, on by default, "which prevents the color from bleeding across selection boundaries". That is a selection-aware edge policy (normalised convolution or masked sampling, INFERRED), Photoshop's answer to the halo problem Adobe describes for the classic filters: "these blur filters will use image data from outside the selected area".
- **Colour space.** Filters operate on the document's stored values. In 8- and 16-bit RGB documents those are gamma-encoded (sRGB, Adobe RGB, …), so Photoshop blurs in gamma space. 32-bit documents store linear-light values, so the same Gaussian Blur becomes a linear-light blur (INFERRED from Photoshop's HDR/32-bit model; not verified for each filter). The "Blend RGB Colors Using Gamma 1.0" preference affects layer blending, not filters (UNVERIFIED).

### 4.4 Adobe After Effects

REFERENCE: Adobe, "Blur & Sharpen effects" (helpx.adobe.com/after-effects/using/blur-sharpen-effects.html, Internet Archive 2024 copy).

- **General.** "Increased blurriness is the result of increasing the size of the sample, whether the size is expressed as a radius or a length." **Repeat Edge Pixels**: on = clamp ("as if the pixel values beyond the edge of the layer are the same as the values of the edge pixels … preventing them from darkening and becoming more transparent"); off = zero/decal ("as if the pixel values beyond the edge of the layer are zero").
- **Fast Box Blur** (match name `ADBE Box Blur2`, GPU): "Blur Radius" plus **Iterations**: "Number of times the blur is sequentially applied to the image. A value around 3 gives a blur similar in quality to Fast Blur … The default value creates boxy results." So n iterations of a box of width w give σ = √(n·(w²−1)/12), and the kernel tends to a Gaussian as n grows (COMPUTED; the exact width per "radius", 2r+1 or otherwise, is UNVERIFIED). Fast Blur (Legacy) was a fixed three-iteration box blur, and Fast Box Blur at its default iterations reproduces it (Adobe community manager, community.adobe.com "Alternative to Fast Blur"; REFERENCE second-hand).
- **Gaussian Blur: "Blurriness"** with Blur Dimensions (horizontal/vertical/both) and Repeat Edge Pixels; GPU-accelerated; "a replacement for the Gaussian Blur (Legacy) effect and produces a slightly different rendering result". The Blurriness→σ mapping is undocumented (UNVERIFIED). An Adobe community thread asks why the same number gives different results in After Effects and Photoshop, without a resolved answer.
- **Directional Blur**: Direction and Blur Length; "the blur is applied equally on either side of the center of a pixel; therefore, a setting of 180° and a setting of 0° produce the same results" (a symmetric streak).
- **Camera Lens Blur**: Blur Radius up to **500**, with iris Shape/Roundness/Aspect Ratio/Rotation/Diffraction Fringe, highlight controls and a **"Use Linear Working Space"** checkbox: "Produces a result similar to a project set to a linearized working color space … to see realistic bokeh effects" plus advice to use 32-bpc to avoid quantization. This is one of the few vendor documents that tells users to blur in linear light.
- **Bilateral Blur** (Radius, Threshold; edge-preserving, "very similar" to Photoshop's Surface Blur), **Smart Blur**, **Channel Blur** (per-channel), **Compound Blur** ("Maximum Blur", "The maximum amount, in pixels, that any part of the affected layer can be blurred", driven by a blur-map layer's luminance: a variable blur), **Radial Blur** (Spin/Zoom, with antialiasing quality).
- **Colour space.** The project's working space applies. With "Linearize Working Space" on, all blurs run in linear light; otherwise they run on gamma-encoded values (REFERENCE, the Camera Lens Blur text above implies this).

### 4.5 Affinity (Photo / Designer)

- **Controls.** Gaussian Blur (as a destructive filter, a live filter layer and a Layer FX) with **"Radius" in px**; the Layer FX version has **"Preserve Alpha"**, which keeps the object's outline sharp. The live filter help says values above 100 px may hurt performance (REFERENCE: affinity.help, "Gaussian Blur" filter and Layer FX pages). Affinity also offers Box, Lens, Motion, Radial, Zoom, Depth of Field, Field Blur, Diffuse Glow, Bilateral, Median and Surface/"Minimal" blurs (UNVERIFIED list completeness).
- **Meaning.** The help pages describe radius only as "controls the extent of the effect". Radius→σ is **UNVERIFIED**. Affinity also runs on Metal GPU acceleration on Apple platforms (INFERRED from Affinity's hardware-acceleration preference; kernel details unknown).
- **Preserve Alpha** is an edge policy for the alpha channel: blur colour but keep the shape's coverage, which avoids the transparent fringe that decal edges create.

### 4.6 GIMP

- **GIMP 2.10 and 3.0: "Size X" / "Size Y" = σ.** REFERENCE (GEGL source `operations/common/gaussian-blur.c`, master, 2026-10-13): the GUI labels are the properties `std_dev_x` / `std_dev_y` (`property_double (std_dev_x, _("Size X"), 1.5)`, description "Standard deviation for the horizontal axis", unit `pixel-distance`). GEGL docs give a default of 1.5, hard range 0–1500 and UI range 0.24–100 (gegl.org/operations/gegl-gaussian-blur). **σ = Size.**
  - **Algorithm** (`operations/common/gblur-1d.c`): `filter` = auto/FIR/IIR. Auto picks **FIR for σ < 1.0, IIR otherwise** ("Threshold 1.0 is arbitrary"). IIR is the "Recursive Gauss IIR Filter as described by Young / van Vliet" (Young & van Vliet 1995, "Recursive implementation of the Gaussian filter", Signal Processing 44). The FIR kernel length is `ceil(6.5·σ)` rounded up to odd, with weights renormalised to sum 1.
  - **Edges**: `abyss-policy` = none / **clamp (default)** / black / white; `clip-extent` = TRUE by default (output clipped to the input's extent).
  - **Colour space**: the op processes `"RaGaBaA float"` (babl's linear-light, premultiplied RGBA float) or `"RGB float"` (linear) for alpha-less inputs. babl names without the prime (R, G, B) are linear; R′G′B′ would be gamma-encoded. babl converts gamma-encoded input to that format before the blur, so **GEGL blurs in linear light, premultiplied**, whatever the image's precision or encoding (REFERENCE, source).
- **GIMP 2.8 and older: "Blur Radius" ≠ σ.** REFERENCE (GIMP `plug-ins/common/blur-gauss.c`, branch `gimp-2-8`): `vert = fabs (vert) + 1.0; std_dev = sqrt (-(vert * vert) / (2 * log (1.0 / 255.0)));`. So **σ = (r + 1)/√(2·ln 255) = (r + 1)/3.329**. The Gaussian falls to 1/255 of its peak at distance r + 1, i.e. "radius" is (one less than) the distance at which an 8-bit value would round to zero. r = 10 gives σ = 3.30. The old plug-in offered IIR and RLE methods and worked on 8-bit gamma-encoded data.
- **Consequence.** The same number in GIMP 2.8 and GIMP 2.10 differs by a factor of about 3: "radius 10" in 2.8 ≈ "Size 3.3" in 2.10. A 2012 GIMP commit that moved selection feathering to GEGL divided the old radius by 3.5 to get `std-dev` "to visually match the old behavior" (GNOME commits-list, May 2012, "app: implement gimp_channel_real_feather() with gegl:gaussian-blur"), which is close to the 3.33 derived above.

## 5. Game engines

Game engines rarely expose σ. Their blur controls are **screen-relative** (percent of screen width, fractions of 1080p), **pyramid-relative** (how many mip levels, how mips are blended) or **physical** (focal length, f-number, focus distance). They normally work on **linear-light HDR** buffers, because the scene colour is linear before tonemapping (Unity projects set to the Gamma colour space are the exception).

### 5.1 Unity URP and HDRP

REFERENCE (Unity-Technologies/Graphics, `master`, fetched 2026-10-13).

- **URP Bloom** (`Packages/com.unity.render-pipelines.universal/Runtime/Overrides/Bloom.cs`, `Runtime/Passes/PostProcess/BloomPostProcessPass.cs`, `Shaders/PostProcessing/Bloom.shader`):
  - Controls: **Threshold** ("Value is in gamma-space"; the pass converts it with `GammaToLinearSpace` and uses a hard-coded soft knee of threshold × 0.5), **Intensity**, **Scatter** (0–1, default 0.7, tooltip "Set the radius of the bloom effect"), Clamp, Tint, High Quality Filtering (bicubic upsampling), **Filter** = Gaussian / Dual / Kawase, **Downscale** = Half / Quarter, **Max Iterations** (2–8, default 6).
  - "Scatter" is not a radius. In Gaussian mode it is the blend factor between a mip and the next lower mip on the way up: `scatter = Mathf.Lerp(0.05f, 0.95f, bloom.scatter.value)`. In Dual mode it scales the upsample tent (`Lerp(0.3, 1.3, scatter)`, so 0.7 → 1.0), and in Kawase mode it blends between the linear and blurred sample.
  - Pyramid depth: `iterations = floor(log2(max(width, height)) − 1)`, clamped to Max Iterations.
  - Each Gaussian downsample is a **9-tap separable kernel** with weights 0.0162, 0.0541, 0.1216, 0.1946, 0.2270 (symmetrical), taps one destination texel apart. Its σ is **1.69 texels of the level being written** (COMPUTED from the weights), so level i (with Half downscale) has σ ≈ 1.69 · 2^(i+1) screen pixels before the blends. The bloom PSF is therefore a **sum of Gaussians at octave scales**, weighted by powers of Scatter (INFERRED structure, COMPUTED per-level σ). The 9 weights are the binomial-derived set popularised by Rákos (2010, "Efficient Gaussian blur with linear sampling").
  - Kawase mode cites "Bandwidth-Efficient Rendering", SIGGRAPH 2015 (Bjørge, ARM) in a source comment, with per-level offsets `0.5 + i`.
- **URP Depth of Field** (`Runtime/Overrides/DepthOfField.cs`, `DepthOfFieldGaussianPostProcessPass.cs`, `DepthOfFieldBokehProcessPass.cs`):
  - **Gaussian mode**: Start, End (metres), **Max Radius** 0.5–1.5 (default 1; "Values above 1 may show under-sampling artifacts"). The code says "Assumes a radius of 1 is 1 at 1080p": `maxRadius = gaussianMaxRadius · (height_of_half-res_target / 1080)`, clamped to 2. So this "radius" is a resolution-normalised kernel-scale multiplier, not pixels and not σ.
  - **Bokeh mode** (physical): Focus Distance, Aperture (f-number 1–32), Focal Length (1–300 mm), Blade Count (3–9), Blade Curvature, Blade Rotation. The circle of confusion follows Potmesil & Chakravarty (1981), "A Lens and Aperture Camera Model for Synthetic Image Generation": `F = focalLength/1000; A = focalLength/aperture; maxCoC = (A·F)/(P − F)`. The kernel is a fixed 4-ring, 42-tap disc/polygon pattern scaled to `min(0.05, 14 / viewportHeight)` of the screen ("empirically derived from the ring count"), so the largest bokeh is about 14 px of the working buffer.
- **HDRP Bloom** (`com.unity.render-pipelines.high-definition/Runtime/PostProcessing/Components/Bloom.cs`): the same idea, with Threshold ("expressed in gamma-space. A value above 0 will disregard energy conservation rules"), Intensity, **Scatter** ("Set the radius of the bloom effect", 0.7), Anamorphic (stretches with the physical camera's anamorphism), Resolution (Half/Quarter), prefilter and bicubic options.
- **HDRP Depth of Field** (`…/Components/DepthOfField.cs`): manual near/far ranges with **Near Max Blur** (default 4, 0–8) and **Far Max Blur** (default 8, 0–16) "maximum radius the … blur can reach", sample counts (near 5, far 7), resolution and a **physically based** mode. The units of "Max Blur" are pixels of the working resolution (INFERRED; not traced in the shader).
- **Colour space.** Both pipelines blur the HDR camera target, which is linear light in Linear-colour-space projects (INFERRED from the source: the gamma-space Threshold is converted with `GammaToLinearSpace` before it is compared with buffer values). Edges: bilinear sampling with `ClampUVForBilinear` (clamp).

### 5.2 Unreal Engine

REFERENCE: Epic, "Bloom in Unreal Engine" (dev.epicgames.com/documentation/en-us/unreal-engine/bloom-in-unreal-engine) and the `FPostProcessSettings` / `FGaussianSumBloomSettings` / `FConvolutionBloomSettings` API pages (docs.unrealengine.com 4.26 and 5.1).

- **Standard ("Gaussian sum") bloom.** Several Gaussian blurs at successively lower resolutions are added. The current page lists five (#1–#5, Blur1 at ½ resolution down to Blur5 at 1/32); the C++ API also has a sixth (Bloom6 at 1/64). Each has a **Tint** and a **Size**: "The size in percent of the screen width. Is clamped by some number. If you need a larger number, use the next lower resolution blur instead." The API text calls it "**Diameter** size for the Bloom1 in percent of the screen width". `SizeScale` scales all of them. How a "diameter in percent of screen width" becomes σ is not documented (UNVERIFIED; Unreal's renderer source is behind Epic's GitHub access and was not read). Epic also notes Standard bloom "is not conservative (it can result in an overall brightening of the image)".
- **Convolution bloom.** "Energy conserving scatter … formulated as a convolution operations and accelerated by use of a Fast Fourier Transform (FFT)". The PSF is a user texture (**Convolution Kernel**, e.g. a star/glare image, `.exr` recommended), with **Convolution Scale** ("Relative size of the convolution kernel image compared to the minor axis of the viewport", default 1), Center (UV, default (0.5, 0.5)), **Buffer** ("Implicit buffer region as a fraction of the screen size to insure the bloom does not wrap across the screen", i.e. zero padding against FFT circular wrap-around) and Boost (pre-filter Min/Max/Mult). This is the one mainstream real-time blur whose **kernel is an arbitrary image** and whose cost is independent of kernel size.
- **Depth of field.** Cinematic DOF is physically parameterised (sensor width, focal length, aperture f-stop, focal distance, blade count) and computes a circle of confusion per pixel; "Mobile/Gaussian" DOF uses near/far transition regions and a Gaussian size (REFERENCE for the controls: Epic "Depth of Field" documentation; the CoC→kernel mapping in the renderer is UNVERIFIED).
- **Colour space.** Linear HDR scene colour before tonemapping (REFERENCE, standard Unreal post-process order; the Threshold is in luminance units: "how many luminance units a color needs").

## 6. Libraries

### 6.1 OpenCV `GaussianBlur(src, dst, ksize, sigmaX, sigmaY = 0, borderType = BORDER_DEFAULT)`

REFERENCE (`modules/imgproc/src/smooth.dispatch.cpp` and `include/opencv2/imgproc.hpp`, branch 4.x, fetched 2026-10-13).

- **Two coupled parameters.** `ksize` is the full kernel size (odd); `sigmaX` is σ. Either can be derived from the other:
  - **σ from ksize** when `sigma <= 0`: `sigmaX = 0.15·n + 0.35`, which the source comment writes as `((n-1)*0.5 - 1)*0.3 + 0.8`. ksize 3 → 0.8, 5 → 1.1, 7 → 1.4, 21 → 3.5. So "a 21-tap kernel" (radius 10) **defaults to σ = 3.5**.
  - **ksize from σ** when `ksize = (0,0)`: `ksize = cvRound(σ·(depth == CV_8U ? 3 : 4)·2 + 1) | 1`. That is ±3σ for 8-bit images and ±4σ for float.
  - For ksize 1, 3, 5, 7 and 9 with σ ≤ 0, fixed tables are used instead of sampled Gaussians (3: ¼ ½ ¼; 5: 1 4 6 4 1 / 16; 7: 1 3.5 7 9 7 3.5 1 / 32; 9: 4 13 30 51 60 51 30 13 4 / 256).
  - Weights are sampled `exp(−x²/(2σ²))` at integer offsets and renormalised to sum 1 (bit-exact soft-float path for 8-bit).
- **Edges.** `BORDER_DEFAULT = BORDER_REFLECT_101` (`gfedcb|abcdefgh|gfedcba`, mirror without repeating the edge pixel).
- **Colour space.** None. OpenCV convolves whatever numbers it is given, so an 8-bit image straight from `imread` is blurred in gamma space (and in BGR order).
- OpenCV is the canonical example of radius↔σ **coupling by convention**: the same call with `ksize = (21, 21)` and `sigmaX = 0` gives σ = 3.5, while `ksize = (0, 0)`, `sigmaX = 10` gives a 61-tap kernel.

### 6.2 ImageMagick `-blur radius{xsigma}` and `-gaussian-blur radius{xsigma}`

REFERENCE (`MagickCore/gem.c` `GetOptimalKernelWidth1D` and `MagickWand/mogrify.c`, branch `main`, fetched 2026-10-13).

- **radius is a support half-width, σ is σ.** `GetOptimalKernelWidth1D(radius, sigma)`: if radius > 0 the kernel width is `2·ceil(radius) + 1`; if radius = 0, the width grows from 5 in steps of 2 until the outermost normalised weight drops below `QuantumScale` (1/65535 in Q16 builds), which gives roughly ±4σ in Q16 (±3σ in Q8). The `0xσ` idiom ("let IM choose the radius") is the recommended form (ImageMagick forum, fmw42).
- **The trap.** In `mogrify.c`, `-blur`: `if ((flags & SigmaValue) == 0) geometry_info.sigma=1.0;`. So **`-blur 10` means radius 10 with σ = 1.0**, a mild blur, not a strong one. `-blur 0x10` is σ = 10. `-blur 10x10` is σ = 10 truncated at ±10 = ±1σ, which is a visibly box-like kernel.
- **`-blur` vs `-gaussian-blur`.** `-blur` is separable (two 1D passes); `-gaussian-blur` uses a 2D kernel and is slower for the same result (IM docs, "Blur/Sharpen" usage pages; REFERENCE second-hand via the forum).
- **Edges.** Governed by `-virtual-pixel` (default `edge`, i.e. clamp).
- **Colour space.** IM blurs the stored channel values. For sRGB images that is gamma space unless the user converts with `-colorspace RGB` (linear) first and back with `-colorspace sRGB` after (REFERENCE: ImageMagick usage docs on processing in linear RGB; not re-fetched this session).

## 7. Colour space: linear light vs gamma-encoded sRGB, and premultiplied alpha

A blur is a weighted average. Averages are only physically meaningful on quantities that add, i.e. **linear light** (radiance). sRGB-encoded values are roughly light^(1/2.2), so averaging them gives a darker result than averaging the light. All numbers below are COMPUTED (`$TMPDIR/blur2ool-stack-semantics/colorspace.py`, IEC 61966-2-1 sRGB transfer function).

1. **Black | white edge, the 50% pixel.** Gamma-space blur gives encoded 0.5 = **128**, whose light is only 0.214 of white. Linear-light blur gives light 0.5 = encoded **188**. MEASURED confirmations from this study: Core Image default context 191 vs 133 in an sRGB working space (3.4); SwiftUI `.nonLinear` 0.514 encoded vs `.extendedLinear` 0.744 encoded (3.1); Sketch's edge crosses at 127/128 (4.2). Visible effect: in gamma space dark regions "eat" into bright ones and a blurred white-on-black text looks thinner, black-on-white text looks bolder.
2. **Saturated colours.** Red | green at 50%: gamma space gives (128, 128, 0), luminance Y = 0.199; linear light gives (188, 188, 0), Y = 0.464. The gamma-space transition is **57% darker** than it should be, which is the familiar dark "muddy" seam between saturated colours in CSS and SwiftUI blurs.
3. **Point lights and bokeh.** A single white pixel blurred in gamma space keeps the sum of its *encoded* values. Once the spread values fall into sRGB's linear toe (below 0.04045, where light = encoded/12.92), the total light is only **1/12.92 = 7.7%** of the original: 0.096 for σ = 1, 0.077 for σ ≥ 2. A gamma-space blur throws away about 92% of a small light's energy, which is why gamma-space bloom and bokeh look dull and why After Effects' Camera Lens Blur offers "Use Linear Working Space … to see realistic bokeh effects" (4.4). Game engines blur linear HDR buffers for the same reason (5).
4. **A 1-px white line with σ = 1:** peak 102/255 in gamma space vs 169/255 in linear light.
5. **Premultiplied vs straight alpha.** Blur an opaque red square onto transparency, then composite over white. At the 50%-coverage pixel, **premultiplied** averaging gives (0.5, 0, 0, α 0.5), which composites to (255, 128, 128): a clean pink. **Straight-alpha** averaging also mixes in the colour of the transparent pixels (usually stored as black), giving colour (128, 0, 0) at α 0.5, which composites to **(191, 128, 128)**: a dark halo. Every spec and API covered here blurs premultiplied values (Filter Effects 1 says filters "operate on premultiplied RGBA samples"; Core Image, Skia, GEGL's `RaGaBaA float`, MPS on premultiplied textures). The halo appears when an app blurs straight-alpha data itself, e.g. a naive Metal kernel on a `CGImage` with `kCGImageAlphaLast`.

Who blurs in which space by default (summary):

| Layer | Default blur space | Evidence |
|---|---|---|
| CSS `filter: blur()`, `backdrop-filter`, shadows | gamma sRGB ("Filter Functions must operate in the sRGB color space") | REFERENCE (1.1, 1.4) |
| SVG `<feGaussianBlur>` | **linearRGB** (`color-interpolation-filters` initial value) | REFERENCE (1.2) |
| Skia / Android / Flutter | the destination surface's space; gamma for normal 8-bit sRGB surfaces | INFERRED (2.2) |
| SwiftUI `.blur` | the `ColorRenderingMode`: `.nonLinear` (gamma) by default | MEASURED offscreen (3.1) |
| Core Animation / UIKit materials | UNVERIFIED (render server) | — |
| Core Image | **linear** (extended linear sRGB, half float) | MEASURED + runtime value (3.4) |
| MPS / Metal | whatever the texture format implies (`_srgb` formats linearise on read) | REFERENCE (3.5) |
| vImage, OpenCV, ImageMagick | raw stored numbers (gamma for ordinary images) | REFERENCE (3.6, 6) |
| Sketch | gamma sRGB | MEASURED (4.2) |
| Figma | UNVERIFIED | — |
| Photoshop | document values: gamma in 8/16-bit, linear in 32-bit | INFERRED (4.3) |
| After Effects | project working space; linear if "Linearize Working Space" | REFERENCE (4.4) |
| GIMP 2.10+/GEGL | **linear**, premultiplied float | REFERENCE, source (4.6) |
| Unity, Unreal | **linear** HDR | REFERENCE (5) |

## 8. The same word "radius" means at least 16 different things

Take **"radius = 10"** and ask each tool what it does. σ is the per-axis standard deviation of the resulting point-spread function in pixels (for non-Gaussian kernels, the second moment). "Edge 10–90%" is the distance over which a hard black|white edge rises from 10% to 90% (for a Gaussian, 2.563σ): this is roughly what the eye reads as "how blurry". Both are COMPUTED from the mappings documented above (`radius10.py`; continuous approximations, so discrete kernels differ in the second decimal).

| # | Who says "radius 10" (or "blur 10") | What 10 actually is | Kernel | σ (px) | Edge 10–90% (px) | Evidence |
|---|---|---|---|---|---|---|
| 1 | CSS `filter: blur(10px)`, SVG `stdDeviation="10"`, `GraphicsContext.Filter.blur(radius: 10)`, `CIGaussianBlur` radius 10, `MPSImageGaussianBlur(sigma: 10)`, Flutter `sigmaX: 10` (Skia), CAFilter `inputRadius` 10, GIMP 2.10 Size 10, Sketch blur 10 | σ | Gaussian | 10.0 | 25.6 | REFERENCE / MEASURED |
| 2 | SwiftUI `.blur(radius: 10)` (offscreen renderer) | nominal σ, kernel cut at about ±2.3σ | truncated Gaussian | 9.1 | 24.3 | MEASURED (3.1) |
| 3 | SVG/Skia-raster three-box approximation for s = 10 | box width d = 19, three passes | piecewise quadratic | 9.5 | 25.0 | COMPUTED (1.2) |
| 4 | Flutter `sigmaX: 10` on Impeller | σ′ = ScaleSigma(10) = 9.66, then cut at ±15.9 | truncated Gaussian | ≈7.5–7.8 | ≈21 | COMPUTED (2.4) |
| 5 | Android `RenderEffect.createBlurEffect(10, 10, …)`, `BlurMaskFilter(10)`, Compose `Modifier.blur(10.dp)` in px, Skia `ConvertRadiusToSigma(10)` | σ = 0.57735·r + 0.5 | Gaussian | 6.27 | 16.1 | REFERENCE (2.1, 2.3) |
| 6 | "Box blur radius 10" in the usual 2r+1 sense (most box-blur code and tutorials), `MPSImageBox`/`vImageBoxConvolve` width 21 | half-width | box, 21 taps | 6.06 | 16.8 | COMPUTED |
| 7 | Android window blur (`setBackgroundBlurRadius(10)`), SurfaceFlinger Gaussian variant | σ = 0.57735·r, at ¼ resolution, clamp | Gaussian (or Kawase on many builds) | 5.77 | 14.8 | REFERENCE (2.3) |
| 8 | CSS `box-shadow: 0 0 10px`, `text-shadow`, canvas `shadowBlur = 10`, `CALayer.shadowRadius = 10`, Figma blur 10 | 2σ ("blur radius") | Gaussian | 5.0 | 12.8 | REFERENCE / MEASURED / INFERRED |
| 9 | `CIDiscBlur` / `CIBokehBlur` radius 10, a lens-blur iris radius 10 | disc radius | uniform disc | 5.0 | 13.7 | MEASURED (3.4) |
| 10 | `MPSImageTent` / `vImageTentConvolve` width 21 | half-width of a tent | triangle | 4.47 | 12.2 | MEASURED / COMPUTED |
| 11 | Android hwui legacy weight generator | σ = 0.3·r + 0.6 | Gaussian | 3.6 | 9.2 | REFERENCE (2.3) |
| 12 | OpenCV `GaussianBlur(ksize: 21×21, sigmaX: 0)` | kernel half-width; σ = 0.3·((21−1)/2 − 1) + 0.8 | Gaussian | 3.5 | 9.0 | REFERENCE (6.1) |
| 13 | "Kernel radius = 3σ" (Skia `SigmaToRadius = ceil(3σ)` read backwards; the W3C note that the visible blur "radius" is about triple the stdev) | truncation support | Gaussian | 3.33 | 8.5 | COMPUTED |
| 14 | GIMP 2.8 Gaussian "Blur Radius" 10 | the Gaussian falls to 1/255 at r + 1: σ = (r+1)/√(2 ln 255) | Gaussian | 3.30 | 8.5 | REFERENCE (4.6) |
| 15 | `CIBoxBlur` radius 10 | box **width**, rounded to the nearest odd (9) | box, 9 taps | 2.58 | 7.2 | MEASURED (3.4) |
| 16 | ImageMagick `-blur 10` | kernel half-width; σ defaults to 1.0 | Gaussian, cut at ±10σ | 1.0 | 2.6 | REFERENCE (6.2) |

Beyond these sixteen pixel meanings, "radius"/"size" also means: a **diameter in percent of screen width** (Unreal bloom Size 10 = 10% of the screen, 129 px on the 1290-px-wide iPhone 15 Pro Max screen), a **resolution-normalised scale factor** (Unity URP Gaussian DoF "Max Radius", where 1 = "1 at 1080p"), a **pyramid blend weight** (Unity "Scatter", tooltip "Set the radius of the bloom effect"), a **pass count/offset schedule** (Kawase blurs on Android SurfaceFlinger and Unity URP), a **1D σ along a direction** (`CIMotionBlur` radius 10 = σ 9.9 along the angle, 0 across), a **mask-scaled σ** (`CIMaskedVariableBlur` radius 10 = σ ≈ 10.9 × mask), an **exponential zoom factor** (`CIZoomBlur` amount 10 = 1.22× radial smear), and in Photoshop, After Effects and Affinity, **something undocumented** (UNVERIFIED).

The spread is a factor of **10** in σ (1.0 to 10.0) and a factor of 10 in the visible edge width (2.6 px to 25.6 px) for the same typed number. This is the strongest single argument for Blur2ool's "every layer" view: the word on the slider tells you almost nothing until you know the layer underneath.

Conversion rules worth putting in `BlurCore` (σ in device pixels; s = display scale):

- CSS `blur(v)`, SVG, Core Image Gaussian, MPS, Flutter (Skia backend; Impeller rescales, 2.4), CAFilter, SwiftUI (nominal; effective 0.91·v for v ≥ 8 pt offscreen), Sketch, GIMP 2.10: σ = v (× s for points/CSS px).
- Shadows (CSS, canvas, CALayer) and Figma blurs: σ = v/2.
- Android / Skia "radius": σ = 0.57735·v + 0.5; inverse v = (σ − 0.5)/0.57735.
- OpenCV: σ = 0.15·ksize + 0.35 when σ ≤ 0; ksize = round(2·k·σ + 1) | 1 with k = 3 (8-bit) or 4 (float).
- GIMP 2.8: σ = (v + 1)/3.3290.
- Box of width w: σ = √((w² − 1)/12) (discrete), → w/√12. n boxes: σ = √(n(w² − 1)/12).
- Tent of width w: σ = √((((w+1)/2)² − 1)/6).
- Uniform disc of radius R: per-axis σ = R/2.
- Uniform line (motion) of length L: σ = √((L² − 1)/12) along the line.
- `CIBoxBlur` radius v: w = nearest odd integer to v (ties down); `CIZoomBlur` amount a: zoom factor 1.5^(a/20).
- ImageMagick: σ = the sigma part of `-blur r×σ`; a bare `-blur r` means σ = 1.0.

## 9. Open questions / UNVERIFIED list

Each item says what would settle it. Items marked "app can measure" are good candidates for Blur2ool's live MEASURED badges.

1. **Photoshop Gaussian Blur Radius → σ.** Undocumented; community claims conflict (σ = Radius vs "way more blurred than Photoshop"; possibly 3–4 algorithms by radius range). Settle by blurring a 1-px line in a 32-bit document at several radii and fitting σ (procedure in 4.3). Same for Box Blur width, Motion Blur profile and Surface Blur threshold direction.
2. **After Effects** Gaussian Blur "Blurriness" → σ and Fast Box Blur radius → box width. Same procedure.
3. **Affinity** Gaussian Blur Radius → σ. Same procedure.
4. **Figma's own renderer.** The σ = value/2 rule comes from its CSS export; the canvas renderer was not measured. Figma desktop is installed on this Mac, so a node with a blurred 1-px line could be exported via the Figma API or MCP `get_screenshot` and fitted (needs a Figma file the user owns).
5. **SwiftUI on screen vs offscreen.** The ±2.3σ truncation was measured through `ImageRenderer`. Whether the render-server path (Core Animation `gaussianBlur`) truncates the same way, and whether it blurs in gamma or linear space, is unknown. App can measure on device by snapshotting an on-screen view (UNVERIFIED that `drawHierarchy` captures render-server filters).
6. **iOS vs macOS.** All MEASURED Core Image, MPS, SwiftUI and `CALayer` numbers here are macOS 27.2 on M1 Max. The iOS 27 simulator matched SwiftUI byte-for-byte, but A17 Pro hardware was not tested. App can measure.
7. **System materials' radii** (`.ultraThinMaterial` … `.ultraThickMaterial`, `UIBlurEffect` styles, Liquid Glass). Hidden; would need screenshot-based fitting over a known backdrop.
8. **Core Image above r = 50.** The r = 100 probe hit the image border; Core Image's large-radius strategy (downsampling?) is unknown. `CIMaskedVariableBlur`'s cap (σ ≈ 49) and its exact mask→radius law (linear in mask was observed at mask 0.5 only). App can measure.
9. **`CIZoomBlur` algorithm.** The 1.5^(amount/20) law and the near-log-uniform weighting are MEASURED; the implementation (iterated half-step zooms?) is INFERRED.
10. **CAFilter keys.** `inputNormalizeEdges`, `inputHardEdges`, `inputNormalizeEdgesTransparent` are REFERENCE as names (WebKit source); their exact maths are INFERRED from the names.
11. **Unreal bloom size → σ** (renderer source not read) and Unity HDRP "Max Blur" units.
12. **Skia GPU vs raster differences** in Chrome for the same CSS blur (three-box raster vs Gaussian GPU) were not measured.
13. **Chromium `backdrop-filter` mirror edge mode**: which Chromium version switched, and whether WebKit's `inputNormalizeEdges` is visually identical to mirror (it is not mathematically the same).
14. **Edge-mode support for `feGaussianBlur`** in Firefox and Safari (Chromium ignores it; see 1.5).
15. **Compose `Modifier.blur` → `RenderEffect` mapping** on Android (androidMain source path 404'd).

## 10. Sources

Specifications
- W3C, *Filter Effects Module Level 1*, sections "Filter Functions" (`blur()`), 9.14 "Filter primitive feGaussianBlur", 10 "color-interpolation-filters", 13.1.9 shorthand equivalents. https://www.w3.org/TR/filter-effects-1/
- W3C, *Filter Effects Module Level 2* (Editor's Draft), 2.1 "Filtering and Clipping", 3 "Backdrop Root". https://drafts.csswg.org/filter-effects-2/
- W3C, *CSS Backgrounds and Borders Module Level 3*, 6.1.2 "Blurring Shadow Edges". https://www.w3.org/TR/css-backgrounds-3/
- W3C, *CSS Text Decoration Module Level 3*, "text-shadow". https://www.w3.org/TR/css-text-decor-3/
- WHATWG, *HTML Living Standard*, canvas "Shadows" (`shadowBlur`). https://html.spec.whatwg.org/multipage/canvas.html
- Tab Atkins Jr., www-style mailing list, July 2010, on blur "radius" ≈ 3× stdev. https://lists.w3.org/Archives/Public/www-style/2010Jul/0238.html

Source code (fetched 2026-10-13)
- Chromium: `third_party/blink/renderer/platform/graphics/filters/fe_gaussian_blur.cc`, `core/style/shadow_data.h`, `cc/paint/render_surface_filters.cc`; commit 909793b85dd2 "Update shadow blur-radius computations" (2018-12-24).
- Skia: `src/core/SkBlurMask.cpp`, `src/core/SkBlurEngine.{h,cpp}`, `src/core/SkImageFilterTypes.cpp`, `src/gpu/BlurUtils.h`, `src/effects/imagefilters/SkBlurImageFilter.cpp`. https://skia.googlesource.com/skia
- AOSP: `frameworks/base/libs/hwui/jni/RenderEffect.cpp`, `libs/hwui/utils/Blur.cpp`, `libs/hwui/jni/MaskFilter.cpp`, `graphics/java/android/graphics/RenderEffect.java`; `frameworks/native/libs/renderengine/skia/filters/` (`BlurFilter.h`, `GaussianBlurFilter`, `KawaseBlurFilter`, `KawaseBlurDualFilter`).
- Flutter: `engine/src/flutter/lib/ui/painting.dart`; `impeller/entity/contents/filters/gaussian_blur_filter_contents.cc`; `impeller/geometry/sigma.cc`; `shell/platform/darwin/ios/framework/Source/FlutterPlatformViews.mm`, `FlutterPlatformViews_Internal.h`, `FlutterPlatformViewsController.mm`. https://github.com/flutter/flutter
- WebKit: `Source/WebCore/platform/graphics/ca/cocoa/PlatformCAFiltersCocoa.mm`, lines 309–329. https://github.com/WebKit/WebKit
- GEGL: `operations/common/gaussian-blur.c`, `operations/common/gblur-1d.c`. https://gitlab.gnome.org/GNOME/gegl
- GIMP 2.8: `plug-ins/common/blur-gauss.c` (branch `gimp-2-8`). https://gitlab.gnome.org/GNOME/gimp
- Unity Graphics: URP `Runtime/Overrides/Bloom.cs`, `Runtime/Overrides/DepthOfField.cs`, `Runtime/Passes/PostProcess/BloomPostProcessPass.cs`, `DepthOfFieldGaussianPostProcessPass.cs`, `DepthOfFieldBokehProcessPass.cs`, `Shaders/PostProcessing/Bloom.shader`; HDRP `Runtime/PostProcessing/Components/Bloom.cs`, `DepthOfField.cs`. https://github.com/Unity-Technologies/Graphics
- OpenCV 4.x: `modules/imgproc/src/smooth.dispatch.cpp`, `include/opencv2/imgproc.hpp`. https://github.com/opencv/opencv
- ImageMagick: `MagickCore/gem.c` (`GetOptimalKernelWidth1D`), `MagickWand/mogrify.c` (`-blur`). https://github.com/ImageMagick/ImageMagick
- Sketch file format: `packages/file-format/schema/objects/blur.schema.yaml`, `enums/blur-type.schema.yaml`. https://github.com/sketch-hq/sketch-file-format

Vendor documentation and SDK headers
- Apple iOS 27.0 SDK (Xcode-beta 27A5194q): `CoreImage.framework/Headers/CIFilterBuiltins.h`; `MetalPerformanceShaders.framework/.../MPSImageConvolution.h`, `MPSImageMedian.h`, `MPSImageMorphology.h`, `MPSCore.framework/Headers/MPSCoreTypes.h`; `Accelerate.framework/.../vImage.framework/Headers/Convolution.h`; SwiftUI `.swiftinterface`/`.swiftdoc` (via `sdk-feasibility.md`).
- Apple, `blur(radius:opaque:)`. https://developer.apple.com/documentation/swiftui/view/blur(radius:opaque:)
- Apple, `gaussianBlur()` (Core Image). https://developer.apple.com/documentation/coreimage/cifilter-swift.class/gaussianblur()
- Apple, Core Image Filter Reference (archive). https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html
- Adobe, Photoshop "Filter effects reference" and "Blur Gallery" (Internet Archive 2024 copies). https://helpx.adobe.com/photoshop/using/filter-effects-reference.html, https://helpx.adobe.com/photoshop/using/blur-gallery.html
- Adobe, After Effects "Blur & Sharpen effects" (Internet Archive 2024 copy). https://helpx.adobe.com/after-effects/using/blur-sharpen-effects.html
- Affinity, "Gaussian Blur" filter and Layer FX help. https://affinity.help/photo/en-US.lproj/pages/Filters/filter_gaussianBlur.html
- GEGL operation reference, gegl:gaussian-blur. https://gegl.org/operations/gegl-gaussian-blur.html
- Sketch docs, "Layer and Background Blur", "Motion and Zoom Blur". https://www.sketch.com/docs/symbols-and-styles/styling/effects/
- Epic, "Bloom in Unreal Engine"; `FPostProcessSettings`, `FGaussianSumBloomSettings` (4.26), `ConvolutionBloomSettings` (5.1). https://dev.epicgames.com/documentation/en-us/unreal-engine/bloom-in-unreal-engine

Forums and secondary sources (lower confidence, used only where marked)
- Figma Community, "Background blur is different in Dev Mode" (staff reply 30 July 2024). https://forum.figma.com/ask-the-community-7/background-blur-is-different-in-dev-mode-22642 ; and thread 81631.
- grida.co, "Figma blur effects". https://grida.co/docs/@designto-code/figma-blur-effects
- Luminous Landscape forum, "The Math of Photoshop's Unsharp Mask and Gaussian Blur" (topic 89428). https://forum.luminous-landscape.com/index.php?topic=89428.0
- ImageMagick forum, "Gaussian blur slow (and different) compared to Photoshop CC" and "sigma and radius arguments for -blur and -gaussian-blur".
- Adobe Community, "Alternative to Fast Blur" (After Effects) and "the different radius pixels value in gaussian blur in after effects and in photoshop".
- PCWorld, "How to use Photoshop blur filters" (Gaussian range 0.1–1000).
- GNOME commits-list, May 2012, "app: implement gimp_channel_real_feather() with gegl:gaussian-blur".

Papers
- W. M. Wells, "Efficient synthesis of Gaussian filters by cascaded uniform filters", IEEE TPAMI 8(2), 1986.
- P. Kovesi, "Fast almost-Gaussian filtering", DICTA 2010.
- I. T. Young, L. J. van Vliet, "Recursive implementation of the Gaussian filter", Signal Processing 44(2), 1995.
- M. Potmesil, I. Chakravarty, "A Lens and Aperture Camera Model for Synthetic Image Generation", SIGGRAPH 1981.
- M. Bjørge (ARM), "Bandwidth-Efficient Rendering", SIGGRAPH 2015 course (dual/Kawase filtering).
- D. Rákos, "Efficient Gaussian blur with linear sampling", 2010 blog article (rastergrid.com).

Probes written for this document (all under `$TMPDIR/blur2ool-stack-semantics/`)
- `ciprobe.swift`, `ciprobe2.swift`: Core Image attributes and LSFs, MPS LSFs, `CALayer.shadowRadius`.
- `swiftuiprobe2.swift`: SwiftUI `.blur` `opaque` and colour-mode behaviour.
- `sketch/make.py`, `sketch/measure.py`: Sketch file generation, `sketchtool export`, edge fitting.
- `colorspace.py`, `radius10.py`, `zoomcheck.py`: COMPUTED numbers in sections 3.4, 7 and 8.
- `threebox.py`, `impeller.py`: recreated in this run (the previous run's copies were lost); they reproduce the tables in 1.2 and 2.4 (see the rounding note in 2.4).

<!-- STATUS: COMPLETE -->
