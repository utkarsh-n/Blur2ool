# Blur2ool — SDK feasibility (Xcode 27.0 beta, iOS 27 SDK)

Status: complete (written incrementally over two sessions). Date: 2026-10-13.
Toolchain checked: `/Applications/Xcode-beta.app` (Xcode 27.0). Probes ran in `$TMPDIR/blur2ool-sdk/`; durable copies of the sources are in `Documentation/research/sdk-probes/`. Simulator used: "Blur2ool SDK Probe" (iOS 27.0), shut down after use.

Evidence convention: every API claim names the SDK file it was found in. Paths are abbreviated:
- `IOS_SDK` = `Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk`
- `SIM_SDK` = `.../iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk`
- `MAC_SDK` = `.../MacOSX.platform/Developer/SDKs/MacOSX.sdk`

## 0. Summary / verdicts

Everything the brief's engineering plan needs exists in the installed iOS 27.0 SDK. All of it typechecks in Swift 6 strict-concurrency mode for both the simulator and the device. The only real constraint is that the iOS simulator's GPU has Apple2-class limits, so GPU code must be written to those limits (section 15).

| Question | Verdict | Evidence |
|---|---|---|
| SwiftUI shaders (`layerEffect`, `colorEffect`, `distortionEffect`, `ShaderLibrary`, `visualEffect`) | **Use** for the "SwiftUI layer" demos only. They are single-pass and half precision, take a `maxSampleOffset`, and do not work on UIKit-backed views such as `MTKView`. | §2; a box blur through `.layerEffect` was MEASURED exact via ImageRenderer |
| `.blur(radius:opaque:)` | Exists (iOS 13). Docs call radius "the radial size"; the Canvas filter's docs say "standard deviation". MEASURED offscreen: σ = radius for small radii; the kernel is hard-truncated at about ±2.3 r for r ≥ 8, so σ_eff = 0.909 r. Same result on macOS and the iOS simulator. | §3, §4 |
| Variable or progressive blur API | **None public** in SwiftUI, UIKit or QuartzCore. `CIMaskedVariableBlur` is the only system one. The `.soft` scroll edge effect is progressive but has no parameters. Build our own in Metal. | §3 |
| Liquid Glass (`glassEffect`, `Glass`, `GlassEffectContainer`), `backgroundExtensionEffect`, Materials | Exist (glass iOS 26). Not measurable offscreen: glass is absent from ImageRenderer output. Materials come out as ImageRenderer's own approximation (σ ≈ 20–27 pt, 4× point-sampled downsample, MEASURED offscreen in the simulator), which may differ from the screen. | §3, §4 |
| `ImageRenderer` → `CGImage` in float | **Yes**, `colorMode = .extendedLinear` gives 16-bit float RGBA. It is the engine for live PSF measurement of `.blur`, Canvas blur and custom layer shaders. Main-actor only. | §4 |
| `MTKView` in SwiftUI under Swift 6 | **Yes**: a `UIViewRepresentable` with a `@MainActor` renderer as `MTKViewDelegate`. Compiles with no warnings. `MTLTexture`, `MTLBuffer` and `MTLCommandBuffer` are not Sendable; use `await cb.completed()` for readback. | §5, §16 |
| GPU timing | **`gpuStartTime`/`gpuEndTime`** per command buffer work everywhere. Counter sampling has stage-boundary (per-encoder) timestamps on Apple GPUs and none in the simulator; treat it as optional. | §6 |
| Metal 4 | Present in the device SDK, **stubbed out of the simulator SDK** (does not compile). **Use classic Metal.** | §7 |
| MPS blurs | Available on device, Mac and simulator. `MPSImageGaussianBlur` is documented as approximate, and its cost is flat in σ (MEASURED). Good as the "vendor library" layer. | §8 |
| Core Image blurs | All requested typed builtins exist. 15 filters in `kCICategoryBlur` at runtime. | §9 |
| `PhotosPicker` | iOS 16, out-of-process, **no permission or usage string** needed. | §10 |
| Swift Charts | 2D marks, function plots (`LinePlot(x:y:domain:)`, iOS 18), and **`Chart3D` + `SurfacePlot` on iPhone (iOS 26)** for kernel surfaces. | §11 |
| `.pickerStyle(.tabs)` | **Exists, new in iOS 27.** On iPhone it looks like `.segmented` and VoiceOver announces the options as tabs. | §12 |
| Offline Metal compile | Works for iphonesimulator, iphoneos and macosx. Default is **MSL 4.1** (AIR 2.9) with fast math on. | §13 |
| Mac GPU↔CPU parity harness | **Works.** `makeLibrary(source:)` 2D conv on 256² `r32Float`: max abs error 9.5e-7 vs CPU; the same binary runs in the simulator via `simctl spawn`. The cold runtime compile is slow (1 s on the Mac, 6–19 s in the simulator), so ship a precompiled metallib. | §14 |
| Safe dispatch | `dispatchThreadgroups` (never `dispatchThreads`), **16×16** groups, **≤ 16 KB** threadgroup memory, no `read_write` textures, no linear sampling of 32-bit float textures. MEASURED valid on the simulator (with Metal API validation) and the Mac; within the A17 Pro limits by REFERENCE (not run on the phone). | §15 |

Probe sources are saved in `Documentation/research/sdk-probes/` (they were also in `$TMPDIR/blur2ool-sdk/`, which is not durable; an earlier copy was lost). They are reference files only, not part of any target.

## 1. Toolchain versions

Verified by running the tools (2026-10-13):

| Item | Value | How verified |
|---|---|---|
| Xcode | 27.0, build 27A5194q | `Xcode-beta.app/Contents/version.plist` |
| `xcode-select -p` | `/Applications/Xcode-beta.app/Contents/Developer` (already the active developer dir) | `xcode-select -p` |
| Swift | Apple Swift 6.4 (swiftlang-6.4.0.20.104, clang-2100.3.20.102), swift-driver 1.167 | `xcrun swiftc --version` |
| iOS device SDK | `iPhoneOS27.0.sdk` (`iPhoneOS.sdk` symlink) | `xcrun --sdk iphoneos --show-sdk-version` → 27.0 |
| iOS simulator SDK | `iPhoneSimulator27.0.sdk` | `xcrun --sdk iphonesimulator --show-sdk-version` → 27.0 |
| macOS SDK | `MacOSX27.0.sdk` | → 27.0 |
| Host OS | macOS 27.2 (26B5101f) | `sw_vers` |
| Metal compiler | Apple metal version 32023.917 (metalfe-32023.917); installed as a downloadable MobileAsset toolchain (`com.apple.MobileAsset.MetalToolchain-v27.1.5194.15`) | `xcrun -sdk iphoneos metal --version` |

Note: the Metal compiler is no longer inside Xcode.app; it is a separately downloaded "Metal Toolchain" component mounted from a cryptex. It is installed on this Mac. A fresh machine would need `xcodebuild -downloadComponent MetalToolchain` (UNVERIFIED exact command for 27.0; it was the Xcode 26 mechanism).

SwiftUI is split into two modules: most view-level graphics API lives in `SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface` (1.40 MB) and app-level API in `SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface` (1.97 MB). `import SwiftUI` re-exports both. Paths below say `SwiftUICore.swiftinterface` / `SwiftUI.swiftinterface` for these two files in `IOS_SDK`.

## 2. SwiftUI shader APIs (layerEffect, colorEffect, distortionEffect, ShaderLibrary, visualEffect)

All present, iOS 17.0+. Verdict: **usable for "SwiftUI-layer" demos** (a hand-written Gaussian/box/radial as a `layerEffect` next to `.blur`). Not usable as the main blur engine (see constraints).

Verified signatures (file: `IOS_SDK/.../SwiftUICore.swiftinterface`):

```swift
// line 8278-8282, extension View, @available(iOS 17.0, macOS 14.0, tvOS 17.0, *), watchOS unavailable
nonisolated public func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some View
nonisolated public func distortionEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View
nonisolated public func layerEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View

// line 2351-2355, the same three on `extension VisualEffect` (usable inside .visualEffect { })
public func layerEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some VisualEffect

// line 19526, @available(iOS 17.0, ...)
nonisolated public func visualEffect(_ effect: @escaping @Sendable (EmptyVisualEffect, GeometryProxy) -> some VisualEffect) -> some View

// line 8167
@dynamicMemberLookup public struct ShaderLibrary : Equatable, @unchecked Sendable {
  public static let `default`: ShaderLibrary
  public static func bundle(_ bundle: Bundle) -> ShaderLibrary
  public init(data: Data)          // a .metallib blob
  public init(url: URL)
  public static subscript(dynamicMember name: String) -> ShaderFunction { get }
}
// line 8185
@dynamicCallable public struct ShaderFunction : Equatable, Sendable { ... }
// line 8197
public struct Shader : Equatable, Sendable {
  public struct Argument { float, float2, float3, float4 (generic BinaryFloatingPoint), float2(CGPoint/CGSize/CGVector),
                           floatArray([Float]), boundingRect, color(Color), colorArray([Color]), image(Image), data(Data) }
  public var dithersColor: Bool
  public init(function: ShaderFunction, arguments: [Shader.Argument])
}
// line ~8253, @available(iOS 18.0, ...): pre-compile to avoid first-use hitch
public func compile(as type: Shader.UsageType) async throws   // .shapeStyle / .colorEffect / .distortionEffect / .layerEffect

// GraphicsContext (Canvas) equivalents, line 8511-8521
public static func blur(radius: CGFloat, options: GraphicsContext.BlurOptions = BlurOptions()) -> GraphicsContext.Filter
public static func layerShader(_ shader: Shader, maxSampleOffset: CGSize) -> GraphicsContext.Filter
public static func distortionShader(_ shader: Shader, maxSampleOffset: CGSize) -> GraphicsContext.Filter
public static func colorShader(_ shader: Shader) -> GraphicsContext.Filter
```

Shader-side contract (doc comments in `SwiftUICore.swiftdoc`, extracted with `strings`):

- layer effect: `[[ stitchable ]] half4 name(float2 position, SwiftUI::Layer layer, args...)`
- color effect: `[[ stitchable ]] half4 name(float2 position, half4 color, args...)`
- distortion: `[[ stitchable ]] float2 name(float2 position, args...)`
- `maxSampleOffset`: "If the shader function samples from the layer at locations not equal to the destination position, this value must specify the maximum sampling distance in each axis, for all source pixels." For a blur of support radius R points, pass `CGSize(width: R, height: R)`.
- Important caveat from the same doc: "Views backed by AppKit or UIKit views may not render into the filtered layer. Instead, they log a warning and display a placeholder image." So **a `layerEffect` cannot be applied to an `MTKView`** (UIViewRepresentable). Shader effects only work on pure-SwiftUI content (Image, shapes, Text, Canvas).

`SwiftUI::Layer` is fully visible in `IOS_SDK/System/Library/Frameworks/SwiftUICore.framework/Headers/SwiftUI_Metal.h` (identical copy in `SwiftUI.framework/Headers/`):

```metal
namespace SwiftUI {
struct Layer {
  metal::texture2d<half> tex;
  float2 info[5];
  half4 sample(float2 p) const {
    p = metal::fma(p.x, info[0], metal::fma(p.y, info[1], info[2]));   // user space -> texture uv (affine)
    p = metal::clamp(p, info[3], info[4]);                               // clamp to layer's rect
    return tex.sample(metal::sampler(metal::filter::linear), p);         // bilinear
  }
};
}
```

This is a rare piece of REFERENCE truth about SwiftUI internals that Blur2ool can show at the "SwiftUI shader" layer: samples are **bilinear**, **half precision**, **premultiplied RGBA** "in the layer's working color space", and out-of-bounds positions are **clamped** to the layer rectangle (clamp-to-edge boundary). A kernel tap therefore costs one `sample()` = one bilinear fetch, so the linear-sampling trick (two taps per fetch) works inside a SwiftUI layer shader too.

### Probe: a SwiftUI layer-shader box blur, captured by ImageRenderer (MEASURED)

`$TMPDIR/blur2ool-sdk/swiftuishader/` (saved as `sdk-probes/swiftui-layer-boxH.metal` and `swiftui-layer-effect-imagerenderer.swift`). The shader is `[[ stitchable ]] half4 boxH(float2 position, SwiftUI::Layer layer, float R)` with `#include <SwiftUI/SwiftUI.h>`, summing `layer.sample(position + float2(k, 0))` for k = −R…R. It compiles offline for macosx, iphonesimulator and iphoneos with plain `xcrun -sdk <sdk> metal -c` + `metallib` (no special flags), loads with `ShaderLibrary(url:)`, and is applied with `.layerEffect(lib.boxH(.float(R)), maxSampleOffset: CGSize(width: R, height: 0))`. Rendering a 1-pt line through it with `ImageRenderer` (`colorMode = .extendedLinear`) gave exactly 2R + 1 non-zero pixels of value 1/(2R + 1) (0.2000 for R = 2, 0.0909 for R = 5) and area 0.9998 / 0.9997 (half-precision rounding), on macOS and in the iOS 27 simulator. So:

- custom SwiftUI shader blurs are **measurable** with the same ImageRenderer harness as `.blur` (both feed the PSF fitter);
- sampling at integer offsets from `position` lands on texel centres, so one `sample()` returns one texel (the bilinear filter has no effect there; half-integer offsets would mix two texels, which is the linear-sampling trick).

Constraints that rule SwiftUI shaders out as the main engine:
1. Single pass only. No intermediate render targets, so separable (H then V) blurs need two nested `.layerEffect` modifiers (each rasterizes a layer) — workable but you cannot control the intermediate format or read it back.
2. `half4` output and `texture2d<half>` input: 10-11 bit mantissa; fine for display, not for parity measurements.
3. No timing hooks (no command buffer), no compute, no threadgroup memory, no readback except via `ImageRenderer`.
4. Dynamic per-frame argument arrays only via `floatArray`/`data`; kernel weights can be passed that way (size limits UNVERIFIED).

## 3. SwiftUI blur and materials (blur(radius:opaque:), Material, glassEffect, Glass, GlassEffectContainer, backgroundExtensionEffect, variable/progressive blur)

Verified signatures:

```swift
// SwiftUICore.swiftinterface line 4332, @available(iOS 13.0, ...)
@inlinable nonisolated public func blur(radius: CGFloat, opaque: Bool = false) -> some View {
    return modifier(_BlurEffect(radius: radius, opaque: opaque))
}
// line 4343, @available(iOS 17.0, ...) on VisualEffect (animatable inside .visualEffect)
public func blur(radius: CGFloat, opaque: Bool = false) -> some VisualEffect

// line 8511 / 8545, GraphicsContext (Canvas)
public static func blur(radius: CGFloat, options: GraphicsContext.BlurOptions = BlurOptions()) -> GraphicsContext.Filter
@frozen public struct BlurOptions : OptionSet { static var opaque; static var dithersResult }

// line 7566: Material (iOS 15+): .ultraThin, .thin, .regular, .thick, .ultraThick, .bar (bar: iOS/macOS only)

// line 2899, @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *), visionOS unavailable
nonisolated public func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View
// line 6874, @available(iOS 26.0, ...)
public struct Glass : Equatable, Sendable {
  public static var regular: Glass { get }
  public static var clear: Glass { get }
  public static var identity: Glass { get }
  public func tint(_ color: Color?) -> Glass
  public func interactive(_ isEnabled: Bool = true) -> Glass
}
// line 10990, @available(iOS 26.0, ...)
public struct GlassEffectContainer<Content: View> : View {
  public init(spacing: CGFloat? = nil, @ContentBuilder content: () -> Content)
}
// also: glassEffectID(_:in:) line 21206, glassEffectUnion(id:namespace:) line 12111, glassEffectTransition(_:) line 3347

// SwiftUI.swiftinterface line 15708-15711, @available(iOS 26.0, ...)
@MainActor public func backgroundExtensionEffect() -> some View
@MainActor public func backgroundExtensionEffect(isEnabled: Bool) -> some View
// line 15780-15803, @available(iOS 26.0, ...)
public struct ScrollEdgeEffectStyle { static var automatic, hard, soft }
nonisolated public func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View
nonisolated public func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View
```

UIKit counterparts (`IOS_SDK/System/Library/Frameworks/UIKit.framework/Headers/`): `UIBlurEffect.h` (styles incl. `systemUltraThinMaterial`… `systemChromeMaterial`), `UIGlassEffect.h` (`UIGlassEffect`, style `.regular`/`.clear`, `interactive`, `tintColor`; `UIGlassContainerEffect.spacing`; all `API_AVAILABLE(ios(26.0))`), `UIVibrancyEffect.h`, `UIVisualEffectView.h`.

What the documentation itself says the parameter means (doc comments in the `.swiftdoc`, extracted with `strings`):

- `View.blur(radius:opaque:)`: "Applies a Gaussian blur to this view… radius: The radial size of the blur." (No statement that radius = σ.)
- `GraphicsContext.Filter.blur(radius:options:)`: "Returns a filter that applies a Gaussian blur… radius: **The standard deviation of the Gaussian blur.**"
- `BlurOptions.opaque`: "The filter ensure opacity by dividing each pixel by its alpha value. The result may be undefined if the input to the filter isn't also completely opaque."

So Apple documents σ = radius for the Canvas filter but not for the View modifier. That gap is exactly what the app's live PSF measurement (section 4) should close; label the View modifier's σ as INFERRED until measured.

**Variable / progressive blur: there is no public API** in SwiftUI or UIKit in the iOS 27.0 SDK. Evidence: `grep -i -E 'variable.?blur|progressive|gradientBlur|maskedBlur'` over both SwiftUI `.swiftinterface` files returns nothing; `grep -i 'variableBlur|progressiveBlur'` over `UIKit.framework/Headers`, `QuartzCore.framework/Headers` and `CoreImage.framework/Headers` only hits `CIFilterBuiltins.h` (that is `CIMaskedVariableBlur`, section 9). The closest public system effect is the iOS 26 scroll edge effect (`scrollEdgeEffectStyle(.soft)`), which renders a progressive blur at scroll edges but exposes no radius/mask parameters. The common "progressive blur" in third-party SwiftUI code uses private `CAFilter` `variableBlur` via the private `CABackdropLayer`; the app must not use it (private API) but can **describe** it as INFERRED and **implement its own** variable blur in Metal (and show `CIMaskedVariableBlur`).

`CALayer.filters` / `backgroundFilters` are declared in `QuartzCore.framework/Headers/CALayer.h` (lines 665, 670) without an iOS restriction in the header, but Apple's CALayer documentation has historically said these properties are not supported on iOS (macOS only for CIFilter objects). UNVERIFIED for iOS 27; do not rely on them.

The materials and Liquid Glass are rendered by the system (backdrop sampling in the render server). Their blur radii, saturation and tint are not exposed: label any number about them INFERRED, measured from screenshots if at all. Glass cannot be captured by `ImageRenderer` at all, and materials come out as ImageRenderer's own offscreen approximation (MEASURED in section 4: σ ≈ 20–27 pt, 4× point-sampled downsample, per-material transmission), which may differ from the on-screen render-server result; the only route is a screenshot of a known background (UNVERIFIED that `UIScreen`/`drawHierarchy` captures backdrop effects faithfully).

## 4. ImageRenderer (measuring SwiftUI blur PSF on device)

Verdict: **yes, `ImageRenderer` rasterizes `.blur(radius:)` into a `CGImage`, in float if asked**, so the live PSF measurement in the brief is feasible. Proven by a run on the Mac (below); the iOS run is in the same section further down. Caveat: it measures SwiftUI's **in-process rasterizer**, which is not necessarily the code path that draws `.blur` on screen (on screen, SwiftUI may hand the blur to Core Animation as a layer filter executed by the render server: INFERRED, not documented). Label the result "MEASURED (offscreen ImageRenderer path)".

Verified signatures (`IOS_SDK/.../SwiftUICore.swiftinterface` line 19907; moved from SwiftUI to SwiftUICore in iOS 18.2 per `@_originallyDefinedIn`):

```swift
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
final public class ImageRenderer<Content> : ObservableObject, ~Sendable where Content : View {
  @MainActor public init(content view: Content)
  @MainActor final public var content: Content
  @MainActor final public var proposedSize: ProposedViewSize
  @MainActor final public var scale: CGFloat
  @MainActor final public var isOpaque: Bool
  @MainActor final public var colorMode: ColorRenderingMode          // .nonLinear / .linear / .extendedLinear
  @available(iOS 26.0, ...) @MainActor final public var allowedDynamicRange: Image.DynamicRange?
  @MainActor final public var cgImage: CGImage? { get }
  @MainActor final public func render(rasterizationScale: CGFloat = 1, renderer: (CGSize, (CGContext) -> Void) -> Void)
  @available(iOS 17.2, ...) final public var isObservationEnabled: Bool
}
// SwiftUI.swiftinterface line 7212, iOS 16+: extension ImageRenderer { @MainActor final public var uiImage: UIImage? }
```

The class is `~Sendable` and every member is `@MainActor`: in Swift 6 the measurement must run on the main actor (fine for a 257×257 render; it takes milliseconds).

Documented limit (doc comment in `SwiftUICore.swiftdoc`, quoted in short): output "only includes views that SwiftUI rasterizes directly using its own drawing primitives"; views composited by Core Animation (complex controls, UIKit views, media) appear as a placeholder. Consequences for Blur2ool:
- `.blur`, `Canvas` + `GraphicsContext.Filter.blur`, `.layerEffect` on Image/Shape content: measurable (`.layerEffect` verified by the box-blur probe in section 2).
- `.glassEffect`, `UIVisualEffectView`, `MTKView`: **not** measurable through `ImageRenderer` (glass is absent from the output; platform views become placeholders).
- `Material`: **partly** measurable offscreen: ImageRenderer on iOS draws its own wide backdrop blur for materials, with a fingerprint worth showing, but it may not be what the render server draws on screen. Details below.

### Probe: do Material and glassEffect render through ImageRenderer? (MEASURED)

Files: `sdk-probes/imagerenderer-backdrop-effects.swift` and `sdk-probes/imagerenderer-material-psf.swift` (run on macOS 27.2 and in the iOS 27.0 simulator as `simctl spawn` binaries).

- `.glassEffect(.regular, in: .rect)` over a 2-px black/white stripe pattern: **no effect at all** in the rendered image on either platform (the stripes under the glass keep their full 0…1 range and 0.5 mean). Glass is simply absent from offscreen renders.
- Materials (`.ultraThinMaterial` … `.ultraThickMaterial`) on **iOS (simulator), offscreen**, measured with a black→white step, bars of 1–16 px and flat backdrops under a full-frame material (`imagerenderer-material-backdrops.swift`, `imagerenderer-material-edge-aliasing.swift`):
  - The material **is** a backdrop blur plus a tint: output = tint level + transmission × blurred backdrop. Light scheme: black → 0.345 / white → 0.959 for ultraThin (transmission 0.615), thin 0.402, regular 0.186, thick and ultraThick identical at 0.044. Dark scheme: ultraThin 0.575, thin 0.369, regular 0.205, thick/ultraThick 0.023. (Linear-light values at scale 1.)
  - Spread: the step's derivative gives σ ≈ 20 px (ultraThin) and ≈ 27 px (thin, regular) at scale 1 (1 px = 1 pt); thick/ultraThick transmit too little for a stable fit. The kurtosis estimates are unstable (noisy derivative tails), so report σ only.
  - **Aliasing fingerprint**: a white bar 1 px wide contributes only at one horizontal phase out of every 4 (response per unit width 0.658, 0, 0, 0 at offsets 0–3), 2–4 px bars are strongly phase-dependent, and bars ≥ 6 px settle near the flat transmission (≈ 0.17–0.20). That is the signature of a **4× downsample with point-like sampling before the blur** (INFERRED mechanism; the measurement is MEASURED). A 1-px line under a material can therefore vanish completely, which the first probe (`imagerenderer-material-psf.swift`, line at x = 128) showed as a zero response.
  - This is ImageRenderer's offscreen rendition. Whether the on-screen material (drawn by the render server) uses the same σ, downsample factor and tint is UNVERIFIED; label these numbers "MEASURED (offscreen ImageRenderer, iOS simulator)" and confirm on the phone.
- Materials on **macOS**: ImageRenderer does blur the backdrop: σ_eff ≈ 49–54 px at scale 1 for every thickness, kurtosis ≈ 2.5 (truncated-Gaussian-like), line gain 2.4–2.6 (ultraThin) down to 0.61 (ultraThick), i.e. a brightness or saturation boost on thin materials. This is macOS-only behaviour, not applicable to the iPhone app; mention it at most as a cross-platform curiosity (MEASURED, macOS offscreen).
- Not yet verified: whether a device `UIView.drawHierarchy(in:afterScreenUpdates: true)` snapshot includes the render server's material and glass blur. If it does, the app could measure the on-screen PSF of `.blur`, materials and glass from a known on-screen test pattern. This is the single most valuable on-device experiment left (see section 17).

### Probe: SwiftUI `.blur` PSF through ImageRenderer on macOS 27.2 (MEASURED)

`$TMPDIR/blur2ool-sdk/imagerenderer/main.swift`, built with `swiftc -swift-version 6 -O`. Method: a 1-pt white vertical line on a transparent 257×257 canvas at scale 1, `.blur(radius:)`, `colorMode = .extendedLinear` (the `cgImage` comes back as 16-bit float RGBA, `kCGColorSpaceExtendedLinearSRGB`), alpha channel read as Float. The middle row is the line-spread function (LSF). σ from the second central moment; cross-check from a step edge's 10–90 % width (Gaussian: 10–90 % = 2.5631 σ).

| radius | σ (LSF 2nd moment) | LSF area | σ (edge 10–90) | σ/radius | kurtosis (Gauss = 3) | support half-width |
|---|---|---|---|---|---|---|
| 1 | 0.996 | 1.0002 | 1.035 | 0.996 | 2.95 | 3.5 px |
| 2 | 1.987 | 0.9991 | 1.987 | 0.993 | 2.90 | 6.5 px |
| 4 | 3.919 | 0.9999 | 3.984 | 0.980 | 2.80 | 11.5 px |
| 8 | 7.270 | 1.0000 | 7.564 | 0.909 | 2.53 | 19 px |
| 16 | 14.540 | 1.0000 | 15.120 | 0.909 | 2.53 | 37.5 px |
| 32 | 29.081 | 1.0000 | 29.327 | 0.909 | 2.53 | 74 px |

Readings (MEASURED on this Mac, SwiftUI macOS 27.2; whether iOS matches is tested below):
- The nominal σ is the radius: σ/radius → 1 for small radii. This supports "radius = σ" (Apple documents this only for the Canvas filter, section 3).
- For radius ≥ 8 the kernel is **hard-truncated** at about ±2.3·radius (the LSF is exactly 0 beyond ±2.4 r; at r = 16, x = 40 gives 0.00000), which lowers the effective σ to 0.909·radius and the kurtosis to 2.53. A Gaussian truncated at ±2.15 σ has σ_eff/σ = 0.908, which fits. The constant ratio for r = 8, 16, 32 suggests a scale-invariant scheme (for example a downsample pyramid), INFERRED.
- Energy is preserved (area 1.000), so it is normalized after truncation.

This is exactly the kind of finding Blur2ool should show live, labelled MEASURED, with the "truncated at ~2.3σ" interpretation labelled INFERRED.

Re-run (second session, same day): the original probe folder was lost with `$TMPDIR`, so the probe was rewritten as `$TMPDIR/blur2ool-sdk/imagerenderer/main.swift` (saved as `Documentation/research/sdk-probes/imagerenderer-blur-psf.swift`). It reproduced the LSF columns exactly on macOS and in the simulator: σ = 0.996, 1.987, 3.919, 7.270, 14.540, 29.081; area 1.0002 … 1.0000; kurtosis 2.95, 2.90, 2.80, 2.53, 2.53, 2.53. The edge-derived σ came out 1.035, 1.987, 3.984, 7.590, 15.170, 30.263 (the r ≥ 8 values differ from the table above by 0.3–3 % because the edge geometry and plateau normalisation differ; for a truncated Gaussian the 10–90 % width is not exactly 2.5631 σ, so treat the edge column as a cross-check only). Support half-width at a 1e-5 threshold: 3, 6, 11, 18.5, 37, 75 px.

### Same probe inside the iOS 27.0 simulator (MEASURED)

The same `main.swift` compiled with `xcrun -sdk iphonesimulator swiftc -swift-version 6 -target arm64-apple-ios27.0-simulator` and run as a plain command-line binary with `xcrun simctl spawn` on the simulator "Blur2ool SDK Probe" (iOS 27.0, 24A5355p). No app bundle and no `UIApplication` were needed. Result: **byte-for-byte the same table** as on macOS (σ = 0.996, 1.987, 3.919, 7.270, 14.540, 29.081 for r = 1…32; same kurtosis and support). The only console noise was `IOSurfaceClientSetSurfaceNotify failed e00002c7`, harmless.

A second probe (`canvas.swift`) compared three routes at r = 2, 4, 8, 16, on both Mac and simulator: `View.blur(radius:)`, `Canvas` with `GraphicsContext.Filter.blur(radius:)` (the one Apple documents as "standard deviation"), and `.drawingGroup().blur(radius:)`. All three gave identical σ (1.987, 3.919, 7.270, 14.540). So, at least in the offscreen renderer, the View modifier and the Canvas filter are the same Gaussian, and radius means σ before truncation.

Not yet verified: the same measurement **on the A17 Pro device**, and whether the **on-screen** composited `.blur` matches the offscreen one. A way to test the on-screen path in the app: put the line view on screen and capture with `UIView.drawHierarchy(in:afterScreenUpdates:)` or `UIGraphicsImageRenderer` on the hosting view (UNVERIFIED that this capture includes render-server filters faithfully). The simulator also proves a useful trick for the build team: **headless SwiftUI rendering checks can run as `simctl spawn` command-line binaries**, without building an app.

## 5. MetalKit MTKView in SwiftUI under Swift 6; CAMetalLayer

Verdict: **host an `MTKView` through `UIViewRepresentable`, with a `@MainActor` renderer class as the coordinator and the `MTKViewDelegate`.** This compiles cleanly in Swift 6 language mode with complete strict concurrency and `-warnings-as-errors`, for both the simulator and the device (section 16). Use on-demand drawing (`isPaused = true`, `enableSetNeedsDisplay = true`, `setNeedsDisplay()` from `updateUIView`) because blurs only need redrawing when a parameter changes.

Verified (`IOS_SDK/System/Library/Frameworks/MetalKit.framework/Headers/MTKView.h`; the simulator copy is identical except that the Metal 4 property is wrapped in `#if !TARGET_OS_SIMULATOR`):

```objc
API_AVAILABLE(macos(10.11), ios(9.0))
NS_SWIFT_UI_ACTOR                                   // line 23: the class is @MainActor in Swift
@interface MTKView : UIView <NSCoding,CALayerDelegate>
- (instancetype)initWithFrame:(CGRect)frameRect device:(nullable id<MTLDevice>)device;   // line 32
@property (nonatomic, weak, nullable) id <MTKViewDelegate> delegate;                   // 45
@property (nonatomic, readonly, nullable) id <CAMetalDrawable> currentDrawable;        // 59
@property (nonatomic) BOOL framebufferOnly;                                             // 66: set NO to write the drawable from compute
@property (nonatomic) MTLPixelFormat colorPixelFormat;                                  // 94
@property (nonatomic) NSInteger preferredFramesPerSecond;                               // 178
@property (nonatomic) BOOL enableSetNeedsDisplay;                                       // 185
@property (nonatomic) BOOL autoResizeDrawable;                                          // 192
@property (nonatomic) CGSize drawableSize;                                              // 199
@property (nonatomic, getter=isPaused) BOOL paused;                                     // 221
- (void)draw;                                                                           // 235
#if !TARGET_OS_SIMULATOR   // line 164 (simulator SDK only)
@property (readonly, nullable) MTL4RenderPassDescriptor *currentMTL4RenderPassDescriptor API_AVAILABLE(macos(26.0), ios(26.0)); // 170
@property (readonly, nonnull) id<MTLResidencySet> residencySet API_AVAILABLE(macos(26.4), ios(26.4));                           // 242
@protocol MTKViewDelegate <NSObject>                                                    // 251
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size NS_SWIFT_UI_ACTOR;  // 260
- (void)drawInMTKView:(MTKView *)view NS_SWIFT_UI_ACTOR;                                // 267
```

`UIViewRepresentable` (`SwiftUI.swiftinterface` line 29032): `@preconcurrency @MainActor public protocol UIViewRepresentable : View where Body == Never`. So `makeUIView`, `updateUIView` and `makeCoordinator` all run on the main actor.

Swift 6 facts found by the probes (section 16 has the file):

1. `MTKView` and both delegate methods are main-actor isolated (`NS_SWIFT_UI_ACTOR`). A renderer class that conforms to `MTKViewDelegate` gets main-actor isolation for its `draw(in:)` witness by inference even without annotation (a variant with the class-level `@MainActor` removed also typechecked with zero diagnostics). Annotate it `@MainActor` explicitly for clarity.
2. Sendability of Metal types in this SDK (`NS_SWIFT_SENDABLE` in `IOS_SDK/.../Metal.framework/Headers/`): **Sendable**: `MTLDevice` (`MTLDevice.h` 406), `MTLCommandQueue` (`MTLCommandQueue.h` 20), `MTLComputePipelineState` (`MTLComputePipeline.h` 161), `MTLFunction` (`MTLLibrary.h` 128), `MTLLibrary` (`MTLLibrary.h` 443), `MTLFence`, `MTLEvent`, `MTLSharedEvent`, `MTLDepthStencilState`, counter sets; the completion-handler block type `MTLCommandBufferHandler` is `NS_SWIFT_SENDABLE` (`MTLCommandBuffer.h` 221). **Not Sendable**: `MTLTexture` (`MTLTexture.h` 314), `MTLBuffer` (`MTLBuffer.h` 34), `MTLCommandBuffer` (`MTLCommandBuffer.h` 245) and encoders.
3. Consequence: capturing a texture in `addCompletedHandler { }` produces `warning: capture of 'tex' with non-Sendable type 'any MTLTexture' in a '@Sendable' closure` (a warning, not an error, in Swift 6.4 language mode; it becomes an error under `-warnings-as-errors`). The clean patterns are:
   - read only Sendable values (for example `gpuEndTime - gpuStartTime`, a `Double`) inside the handler and hop to the main actor with `Task { @MainActor in … }`, as in the probe; or
   - for readback, use the async API and stay in one isolation domain: `await commandBuffer.completed()` then `texture.getBytes(...)`. `completed()` and `scheduled()` are declared in the Metal Swift overlay (`IOS_SDK/usr/lib/swift/Metal.swiftmodule/arm64e-apple-ios.swiftinterface` lines 61 and 73, `@available(iOS 13.0)`, `@backDeployed(before: iOS 26.0)`). `waitUntilCompleted()` is `NS_SWIFT_UNAVAILABLE_FROM_ASYNC("Use 'await completed()' instead.")` (`MTLCommandBuffer.h` line 354), so it is a compile **error** inside any `async` function (verified).
4. `-default-isolation MainActor` (the Xcode 26+ app-template default, SE-0466) also typechecks the probe. `BlurCore` must stay **nonisolated** (do not set default MainActor isolation on the package), so CPU reference blurs can run on background tasks and in `swift test`.

Architecture advice that follows from these facts:

- Keep one `@MainActor` `GPUContext` (device, queue, pipeline cache), because UI parameter changes arrive there anyway; GPU work is asynchronous, so the main thread only encodes (microseconds per blur). Do not build an actor-hopping engine around non-Sendable textures.
- Compute blurs into offscreen textures (`rgba16Float` for display, `r32Float`/`rgba32Float` for measurement), then copy or draw to the drawable in a final render pass. Writing a compute result straight into `currentDrawable.texture` needs `framebufferOnly = false` and a writable drawable format; it compiled, but the offscreen route avoids format and simulator surprises (not tested on device: UNVERIFIED that `bgra8Unorm` drawables accept compute writes on the simulator).
- Measurement readback: `storageMode = .shared` textures on iOS (unified memory) or a blit to a shared `MTLBuffer`; then `await cb.completed()`.

`CAMetalLayer` (`IOS_SDK/System/Library/Frameworks/QuartzCore.framework/Headers/CAMetalLayer.h`): `device` (66), `pixelFormat` (77), `framebufferOnly` (87), `drawableSize` (93), `- nextDrawable` (102), `maximumDrawableCount` (108, iOS 11.2), `presentsWithTransaction` (116), `colorspace` (122), `wantsExtendedDynamicRangeContent` (128, iOS 16), `EDRMetadata` (137), `developerHUDProperties` (157, iOS 16), `residencySet` (171, iOS 26). `CAMetalDisplayLink` (`CAMetalDisplayLink.h` lines 19-49, iOS 17): `initWithMetalLayer:`, `preferredFrameLatency`, `preferredFrameRateRange`, delegate `metalDisplayLink:needsUpdate:` with `CAMetalDisplayLinkUpdate.drawable/targetTimestamp/targetPresentationTimestamp`. A raw `CAMetalLayer` in a custom `UIView` subclass is the alternative to `MTKView`; it gives nothing Blur2ool needs (we are not frame-pacing a game), so **`MTKView` is the recommendation**. `CAMetalDisplayLink` is only worth it for a continuously animated demo (for example an animated σ sweep), and `MTKView` with `isPaused = false` and `preferredFramesPerSecond = 120` covers that too.

## 6. GPU timing: MTLCommandBuffer gpuStartTime/gpuEndTime, MTLCounterSampleBuffer

Verdict: **use `gpuStartTime`/`gpuEndTime` per command buffer as the app's MEASURED GPU time** (works on device, Mac and simulator). Put one blur (all its passes) in its own command buffer when timing it. Use counter sample buffers only as an optional, device-only refinement for per-pass times, and do not depend on them.

Verified (`IOS_SDK/System/Library/Frameworks/Metal.framework/Headers/MTLCommandBuffer.h`):

```objc
// line 276-277
@property (readonly) CFTimeInterval kernelStartTime API_AVAILABLE(macos(10.15), macCatalyst(13.0), ios(10.3));
@property (readonly) CFTimeInterval kernelEndTime   API_AVAILABLE(macos(10.15), macCatalyst(13.0), ios(10.3));
// line 286-294: "The host time in seconds that GPU starts executing this command buffer. Returns zero if it has
// not started. This usually can be called in command buffer completion handler."
@property (readonly) CFTimeInterval GPUStartTime API_AVAILABLE(macos(10.15), macCatalyst(13.0), ios(10.3));
@property (readonly) CFTimeInterval GPUEndTime   API_AVAILABLE(macos(10.15), macCatalyst(13.0), ios(10.3));
```

In Swift these import as `gpuStartTime` / `gpuEndTime` (compiled and ran in the probes below). Units are seconds of host time (`CACurrentMediaTime` timebase). Metal 4 has its own equivalent on `MTL4CommitFeedback` (`MTL4CommitFeedback.h` lines 37/40: `GPUStartTime`, `GPUEndTime`), device SDK only.

Counter sampling (`MTLCounters.h`, `MTLDevice.h` lines 282-307, 1062, 1101; all iOS 14+):

```objc
typedef NS_ENUM(NSUInteger, MTLCounterSamplingPoint) { AtStageBoundary, AtDrawBoundary, AtDispatchBoundary, AtTileDispatchBoundary, AtBlitBoundary };
- (BOOL)supportsCounterSampling:(MTLCounterSamplingPoint)samplingPoint;            // ios(14.0)
@property (readonly, nullable) NSArray<id<MTLCounterSet>>* counterSets;          // ios(14.0)
- (void)sampleTimestamps:(MTLTimestamp *)cpuTimestamp gpuTimestamp:(MTLTimestamp *)gpuTimestamp;
// MTLCommonCounterSetTimestamp / StageUtilization / Statistic; MTLCounterSampleBufferDescriptor { counterSet, label, storageMode, sampleCount }
```

MEASURED with `$TMPDIR/blur2ool-sdk/gpuinfo/main.swift` (first run; the probe was rewritten after `$TMPDIR` was wiped and a second run reproduced every cell of this table, including the 16-byte resolve on the Mac and the empty counter sets in the simulator):

| | Apple M1 Max (macOS 27.2) | iOS 27.0 simulator ("Apple iOS simulator GPU") |
|---|---|---|
| `counterSets` | `timestamp[GPUTimestamp]` | **empty** |
| stage / draw / dispatch / tileDispatch / blit boundary | true / false / false / false / false | false / true / true / false / true (but no counter sets, so unusable) |
| stage-boundary timestamp sample buffer (compute pass `sampleBufferAttachments`) | works, resolved 16 bytes for 2 samples | not supported |
| `gpuEndTime − gpuStartTime` | works | works |

So on Apple-family GPUs the only sampling point is the **encoder (stage) boundary**: you get start/end of each compute or render pass, not per dispatch. That is still enough for per-pass times (H pass vs V pass) if each pass is its own encoder. On A17 Pro I expect the same pattern as M1 Max (both Apple-family TBDR GPUs), but that is UNVERIFIED until run on the phone; the app should query `supportsCounterSampling(.atStageBoundary)` and fall back to command-buffer times.

Honesty notes for the UI: command-buffer GPU time includes scheduling gaps between encoders inside the buffer and is subject to GPU clock ramping (first frames run at low clocks). Report a median of N runs after warm-up, label it MEASURED, and show N.

## 7. Metal 4 (MTL4*) vs classic Metal — recommendation

Verdict: **use classic Metal (`MTLCommandQueue` / `MTLCommandBuffer` / `MTLComputeCommandEncoder`), Metal Shading Language 3.2 or 4.x as compiler default.** Do not use the Metal 4 command model in v1.

Evidence:
1. Metal 4 exists in the device SDK: 31 `MTL4*.h` headers in `IOS_SDK/.../Metal.framework/Headers/` (`MTL4CommandQueue.h`, `MTL4CommandAllocator.h`, `MTL4ComputeCommandEncoder.h`, `MTL4ArgumentTable.h`, `MTL4Compiler.h`, `MTL4Counters.h`, `MTL4MachineLearningCommandEncoder.h`, …), all `API_AVAILABLE(macos(26.0), ios(26.0))`. `MTLDevice.h` line 1297: `- (nullable id<MTL4CommandQueue>)newMTL4CommandQueue API_AVAILABLE(macos(26.0), ios(26.0));` line 1278 `newCommandAllocator`, 1412 `newCounterHeapWithDescriptor:`. `MTLGPUFamilyMetal4 = 5002` (line 213). `MTLLanguageVersion4_0` (iOS 26) and **`MTLLanguageVersion4_1` (iOS 27)** in `MTLLibrary.h` lines 222-224. Timestamps: `MTL4ComputeCommandEncoder writeTimestampWithGranularity:intoHeap:atIndex:` (line 832), `MTL4CounterHeapTypeTimestamp`.
2. **The iOS simulator SDK strips the Metal 4 API.** The 31 `MTL4*.h` files exist in `SIM_SDK` too, but they are stubs (`MTL4CommandQueue.h` is 19 lines in `SIM_SDK` versus 437 in `IOS_SDK`; `MTKView.h` wraps `currentMTL4RenderPassDescriptor` in `#if !TARGET_OS_SIMULATOR`). `SIM_SDK/.../Metal.framework/Headers/MTLDevice.h` is 1121 lines versus 1450 on device; it has no `MTLGPUFamilyMetal4`, no `newMTL4CommandQueue`, no `newCommandAllocator`, no `MTL4Counters.h` import. A probe that used `.metal4` and `makeMTL4CommandQueue()` failed to compile for `arm64-apple-ios27.0-simulator` with `type 'MTLGPUFamily' has no member 'metal4'` and `value of type 'any MTLDevice' has no member 'makeMTL4CommandQueue'`. Any Metal 4 code would need `#if !targetEnvironment(simulator)` plus a classic fallback, i.e. two engines.
3. On the Mac (M1 Max), `supportsFamily(.metal4)` is true and `makeMTL4CommandQueue()` / `makeCommandAllocator()` both returned non-nil (MEASURED). A17 Pro is Apple9 and supports Metal 4: Apple's *Metal Feature Set Tables* (PDF dated May 21, 2026) list "A14 Bionic — Metal 3 & 4 — Apple7", "A17 Pro — Metal 3 & 4 — Apple9", "M1-series — Metal 3 & 4 — Apple7" (REFERENCE, fetched 2026-10-13). Re-checked in the second session: `M4.swift` (`supportsFamily(.metal4)`, `makeMTL4CommandQueue()`, `makeCommandAllocator()`) typechecks for `arm64-apple-ios27.0` and fails for `arm64-apple-ios27.0-simulator` with the two errors quoted above.
4. Blur2ool's GPU work is small compute dispatches on a few textures. Metal 4's benefits (explicit residency, command allocators, argument tables, barriers, ML encoders) are about CPU overhead and large resource sets. They add explicit-barrier and residency bookkeeping that the app does not need, and they break the simulator.

Optional later: a "Metal 4" layer card could explain the newer model as REFERENCE, without running it.

## 8. Metal Performance Shaders blur kernels

Verdict: **available on device, Mac and simulator** (`MPSSupportsMTLDevice` returned true on all three tested environments); useful as the "vendor library" layer and as a comparison against our own kernels. Not useful as a ground truth, because Apple documents its Gaussian as approximate.

Classes found in `IOS_SDK/System/Library/Frameworks/MetalPerformanceShaders.framework/Frameworks/MPSImage.framework/Headers/`:

| Class | File | Availability | Init |
|---|---|---|---|
| `MPSImageGaussianBlur` | `MPSImageConvolution.h` line 237 | iOS 9.0 | `initWithDevice:sigma:` (line 251-252) |
| `MPSImageBox` | `MPSImageConvolution.h` line 145 | iOS 9.0 | `initWithDevice:kernelWidth:kernelHeight:` (odd sizes) |
| `MPSImageTent` | `MPSImageConvolution.h` line 219 | iOS 9.0 | inherits Box init |
| `MPSImageConvolution` | `MPSImageConvolution.h` line 48 | iOS 9.0 | `initWithDevice:kernelWidth:kernelHeight:weights:` (line 85-87) |
| `MPSImageLaplacian`, `MPSImageSobel`, `MPSImageCanny` | `MPSImageConvolution.h` | iOS 10 / 9 / 17 | edge filters (blur-adjacent) |
| `MPSImageGaussianPyramid`, `MPSImageLaplacianPyramid` (+Add/Subtract) | `MPSImageConvolution.h` | iOS 10+ | pyramids |
| `MPSImageMedian` | `MPSImageMedian.h` line 26 | iOS 9.0 | `initWithDevice:kernelDiameter:`; header: "currently only supports images with <= 8 bits/channel" |
| `MPSImageAreaMax` / `MPSImageAreaMin` / `MPSImageDilate` / `MPSImageErode` | `MPSImageMorphology.h` | iOS 9.0 | `kernelWidth:kernelHeight:` (+ `values:` for dilate/erode) |
| `MPSImageGuidedFilter` | `MPSImageGuidedFilter.h` | iOS 12 | edge-aware smoothing |
| `MPSImageIntegral` / `MPSImageIntegralOfSquares` | `MPSImageIntegral.h` | iOS 9 | summed-area tables (box blur in O(1)) |

REFERENCE quotes from `MPSImageConvolution.h` (short): the Gaussian "utilizes a very fast algorith that typically runs at approximately 1/2 of copy speeds", is "Mathematically… an approximate gaussian", and "If a analytically clean gaussian filter is required, please use the MPSImageConvolution filter". The `sigma` parameter doc gives the weight formula and the 1 % cut-off width `ceil(3.7*sigma)`. The `MPSImageTent` doc says two 3-wide box passes equal a 5-wide tent and more passes "tend to approximate a gaussian".

MEASURED (1024×1024 `rgba16Float`, `.clamp` edge mode, best of 5, `gpuEndTime − gpuStartTime`):

| σ | M1 Max | iOS simulator (host GPU through the simulator's Metal layer) |
|---|---|---|
| 2 | 0.114 ms | 0.054 ms |
| 8 | 0.108 ms | 0.121 ms |
| 32 | **0.069 ms** | 0.102 ms |

Second run (rewritten probe `$TMPDIR/blur2ool-sdk/gpuinfo/main.swift`, private-storage textures, n = 9, median): M1 Max 0.187 / 0.200 / 0.190 ms for σ = 2 / 8 / 32; simulator 0.064 / 0.057 / 0.045 ms. The absolute numbers moved by up to 2.7× between runs (GPU clock state, storage mode), but in both runs **the cost does not grow with σ** (a direct 1D kernel would cost about 16× more at σ = 32 than at σ = 2). That is consistent with Apple's "approximate" note and suggests a downsampling or recursive scheme (INFERRED). For the app: show MPS timing only as MEASURED median-of-N on the phone after warm-up, and show the flat cost-vs-σ curve as the interesting fact. Simulator timings are not representative of any phone and must never be shown as device numbers.

## 9. Core Image built-in blur filters (CIFilterBuiltins)

Verdict: **all requested filters exist** as typed builtins; good for the "framework" layer and as a second vendor implementation to fingerprint.

`IOS_SDK/System/Library/Frameworks/CoreImage.framework/Headers/CIFilterBuiltins.h`, section `// CICategoryBlur` (lines 2692-2706), class methods on `CIFilter (Builtins)`:

```objc
+ (CIFilter<CIBokehBlur>*) bokehBlurFilter;                 // radius, ringAmount, ringSize, softness   (protocol line 2173)
+ (CIFilter<CIBoxBlur>*) boxBlurFilter;                     // radius                                   (2189)
+ (CIFilter<CIDiscBlur>*) discBlurFilter;                   // radius                                   (2199)
+ (CIFilter<CIGaussianBlur>*) gaussianBlurFilter;           // radius                                   (2209)
+ (CIFilter<CIMaskedVariableBlur>*) maskedVariableBlurFilter; // mask (CIImage), radius                  (2219)
+ (CIFilter<CIMedian>*) medianFilter;                       // (no parameters besides inputImage)       (2231)
+ (CIFilter<CIMorphologyGradient>*) morphologyGradientFilter; // radius                                 (2239)
+ (CIFilter<CIMorphologyMaximum>*) morphologyMaximumFilter;   // radius
+ (CIFilter<CIMorphologyMinimum>*) morphologyMinimumFilter;   // radius
+ (CIFilter<CIMorphologyRectangleMaximum>*) morphologyRectangleMaximumFilter; // width, height
+ (CIFilter<CIMorphologyRectangleMinimum>*) morphologyRectangleMinimumFilter; // width, height
+ (CIFilter<CIMotionBlur>*) motionBlurFilter;               // radius, angle                            (2293)
+ (CIFilter<CINoiseReduction>*) noiseReductionFilter;       // noiseLevel, sharpness                    (2305)
+ (CIFilter<CIZoomBlur>*) zoomBlurFilter;                   // center (CGPoint), amount                 (2317)
```

In Swift: `import CoreImage.CIFilterBuiltins`, then `CIFilter.gaussianBlur()`, `.boxBlur()`, `.discBlur()`, `.motionBlur()`, `.zoomBlur()`, `.bokehBlur()`, `.maskedVariableBlur()`, `.median()`, `.morphologyGradient()` (all compiled in the probes). Note the request said "CIMedianFilter": that is the runtime filter **name**; the typed protocol is `CIMedian` and the factory is `medianFilter` / `CIFilter.median()`.

Runtime registry, MEASURED on both macOS 27.2 and the iOS 27.0 simulator with `CIFilter.filterNames(inCategory: kCICategoryBlur)` (15 filters, identical lists): `CIBokehBlur CIBoxBlur CIDepthBlurEffect CIDiscBlur CIGaussianBlur CIMaskedVariableBlur CIMedianFilter CIMorphologyGradient CIMorphologyMaximum CIMorphologyMinimum CIMorphologyRectangleMaximum CIMorphologyRectangleMinimum CIMotionBlur CINoiseReduction CIZoomBlur`. (`CIDepthBlurEffect` is the portrait depth-of-field effect; it needs depth/disparity input, so only describe it.) Also blur-adjacent: `CIEdgePreserveUpsample` (`spatialSigma`, `lumaSigma`, header line 260), `CIBlurredRoundedRectangleGenerator` (iOS 26, line 2637), `CIUnsharpMask`, `CIBloom`/`CIGloom` (blur-based).

Note: Core Image's `radius` semantics differ per filter (for `CIGaussianBlur`, Apple's filter reference describes radius as the standard deviation; that is from the online Core Image Filter Reference, not the header, so REFERENCE but not re-verified here). This belongs in `stack-semantics.md`; the app can measure each CI filter's PSF on device the same way as section 4 (CIContext renders into a float `MTLTexture` or `CGImage`).

## 10. PhotosPicker (PhotosUI)

Verdict: **available (iOS 16+) and needs no photo-library permission or Info.plist usage string** when used with the plain initializers. Load the picked item as `Data`, decode and downsample with ImageIO, then upload to a texture.

Verified (`IOS_SDK/System/Library/Frameworks/_PhotosUI_SwiftUI.framework/Modules/_PhotosUI_SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`; `import PhotosUI` re-exports it):

```swift
// line 126-129, @available(iOS 16.0, macOS 13.0, watchOS 9.0, *), tvOS unavailable
@MainActor @preconcurrency public struct PhotosPicker<Label> : View where Label : View {
  nonisolated public init(selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                          preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                          @ViewBuilder label: @Sendable () -> Label)
  // + multi-selection (maxSelectionCount:selectionBehavior:), + photoLibrary: PHPhotoLibrary variants (lines 130-134)
}
// line 145: init(_ titleKey: LocalizedStringKey, selection:matching:preferredItemEncoding:) where Label == Text
// line 161: View.photosPicker(isPresented: Binding<Bool>, selection: Binding<PhotosPickerItem?>, matching:preferredItemEncoding:)
// line 97: public struct PhotosPickerItem : Equatable, Hashable, @unchecked Sendable
//   var itemIdentifier: String?             (line 109; nil unless a photoLibrary: initializer is used)
//   var supportedContentTypes: [UTType]     (line 112)
//   func loadTransferable<T: Transferable>(type: T.Type) async throws -> sending T?   (line 117)
```

Privacy evidence: `IOS_SDK/.../PhotosUI.framework/Headers/PHPicker.h` line 254: the picker "is out-of-process, so photo library access authorization is not needed"; the `_PhotosUI_SwiftUI.swiftdoc` comments repeat "The user explicitly grants access only to items they choose, so photo library access authorization is not needed." Do not use the `photoLibrary:` initializers (they exist to return asset identifiers, and fetching `PHAsset`s by identifier does need authorization).

Recommended load path (typechecked in `ApiSurfaceProbe.swift`, section 16): `try await item.loadTransferable(type: Data.self)` → `CGImageSourceCreateWithData` → `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = 2048` and `kCGImageSourceCreateThumbnailWithTransform = true` (applies EXIF orientation) → `MTKTextureLoader.newTexture(cgImage:options:)` with `.SRGB: false` for a linear working texture (or convert explicitly). A 48 MP iPhone photo must be downsampled before upload; the simulator's `maxBufferLength` is 256 MiB (section 15).

## 11. Swift Charts incl. 3D (Chart3D / SurfacePlot)

Verdict: **Swift Charts covers every 2D plot the math layer needs, and `Chart3D` + `SurfacePlot` (iOS 26) exist on iPhone** for kernel surfaces (2D Gaussian, disc, bokeh PSF) and 2D frequency responses. Use Charts for axes, labels and selection; use Metal or `Canvas` for dense images (the kernel heat map at full resolution, spectra as images).

Verified (`IOS_SDK/System/Library/Frameworks/Charts.framework/Modules/Charts.swiftmodule/arm64e-apple-ios.swiftinterface`, 222 KB):

```swift
// 2D marks, iOS 16: AreaMark (1916), BarMark (1986), LineMark (2044), PointMark (2259), RectangleMark (2306), RuleMark (2369), SectorMark (2426, iOS 17)
// Function plots, iOS 18 (line 2052-2080): no data array needed, evaluated over a domain
LinePlot(x: "x", y: "g(x)", domain: -12...12) { x in ... }                    // (Double) -> Double
LinePlot(x: Text, y: Text, t: Text, domain: ClosedRange<Double>, function: @Sendable (Double) -> (x: Double, y: Double))  // parametric, line 2080
AreaPlot(x:y:domain:function:), AreaPlot(x:yStart:yEnd:domain:function:)       // line 1954-1960 (error bands, |H(f)| envelopes)
// Interaction: chartXSelection(value:) (2937), chartXSelection(range:) (2939), chartOverlay { ChartProxy } (1801), chartGesture (2959), chartScrollableAxes (1187)

// 3D, @available(iOS 26.0, macOS 26.0, visionOS 26.0, *), tvOS/watchOS unavailable
public struct Chart3D<Content: Chart3DContent> : View { init(@Chart3DContentBuilder content: () -> Content) }   // line 358
public struct SurfacePlot : Chart3DContent {                                                                     // line 154
  nonisolated public init(x: LocalizedStringKey, y: LocalizedStringKey, z: LocalizedStringKey,
                          function: @escaping @Sendable (_ x: Double, _ z: Double) -> Double)                    // y = f(x, z)
}
// PointMark/RuleMark/RectangleMark also conform to Chart3DContent (3D scatter, axes guides)
public struct Chart3DPose { init(azimuth: Angle2D, inclination: Angle2D); static default/front/back/top/bottom/left/right }  // line 252
func chart3DPose(_ pose: Binding<Chart3DPose>) -> some View          // line 296 (drag to rotate)
func chart3DCameraProjection(_ projection: Chart3DCameraProjection = .automatic) -> some View   // line 306; .orthographic/.perspective/.automatic; visionOS unavailable
func foregroundStyle(_ surfaceStyle: some Chart3DSurfaceStyle) -> some Chart3DContent           // line 330; .heightBased, .heightBased(Gradient, yRange:), .normalBased (485+)
// chart3DRenderingStyle(_:) is visionOS-only (line 315: iOS unavailable)
```

iOS 27 additions to Charts are result-builder plumbing only (`EmptyView`, `_ConditionalContent`, `TupleContent` conform to `ChartContent`, lines 1110-1132), which makes `if`/`switch` inside `Chart { }` cleaner. No new plot types.

Caveats: `SurfacePlot` takes a closure `y = f(x, z)` that Charts samples itself; the sampling density is not exposed (UNVERIFIED how fine it is; probably fine for smooth kernels, wrong for a box/disc kernel's discontinuity, which will look like a ramp). For discrete kernels (a 9×9 box), `RectangleMark` or `PointMark` in 3D, or a custom Metal height field, show the discretization honestly. Performance with thousands of marks on A17 Pro is UNVERIFIED; `LinePlot` function plots avoid materializing arrays. All Charts types are `@MainActor`.

## 12. iOS 27 SwiftUI APIs of interest (pickerStyle(.tabs)?, TabView styles)

**`.pickerStyle(.tabs)` exists and is new in iOS 27.** `SwiftUI.swiftinterface` line 16483-16496:

```swift
@available(iOS 27.0, macOS 27.0, tvOS 27.0, visionOS 27.0, *) @available(watchOS, unavailable)
extension PickerStyle where Self == TabsPickerStyle { public static var tabs: TabsPickerStyle { get } }
public struct TabsPickerStyle : PickerStyle { public init() }
```

Its doc comment (from `SwiftUI.swiftdoc`): "A picker style that presents options as segmented tabs." On iOS "the visual appearance matches that of the standard `.segmented` style"; on all platforms "VoiceOver announces options as tabs". So on iPhone it looks like `.segmented` but has tab semantics for accessibility, which suits a WYSIWYG → API → Math → Kernel → GPU layer switcher. The Metro Station system may prefer its own segmented control; either way `.tabs` gives the right accessibility trait.

TabView styles available on iOS (`SwiftUI.swiftinterface`): `DefaultTabViewStyle` (22396), `PageTabViewStyle` (13254, swipe pages), `SidebarAdaptableTabViewStyle` (9533, iOS 18), `TabBarOnlyTabViewStyle` (16681, iOS 18). `VerticalPageTabViewStyle`, `CarouselTabViewStyle` are watchOS-only and `GroupedTabViewStyle` is macOS-only. iOS 26 tab-bar APIs: `tabBarMinimizeBehavior(_:)` (11338; `.automatic`, `.onScrollDown`, …), `tabViewBottomAccessory { }` (17718), `tabViewSearchActivation(_:)` (14635). New in iOS 27: `TabContent.help(_:)` (31162).

Other iOS 27 SwiftUI additions found by listing every `@available(iOS 27.0` declaration in `SwiftUI.swiftinterface` and `SwiftUICore.swiftinterface` (about 110 lines; none is a new blur, material or graphics-effect API):
- `NavigationTransition.crossFade` (`CrossFadeNavigationTransition`, line 11313) and `AnyNavigationTransition` (11325): useful for moving between layers without a push animation.
- `reorderable()` / `reorderContainer(for:...)` / `reorderDestination` (12739-12839), `copyable`, `cuttable`, `pasteDestination` (13736-13748).
- Toolbar: `ToolbarItemVisibilityPriority` (13199), `toolbarOverflowMenu { }` (31288), `ToolbarItemPlacement.topBarPinnedTrailing` (7851), `ToolbarPlacement.statusBar` (31681).
- `sceneAccessory { }` (19996, iOS only), document APIs (`ReadableDocument`, `WritableDocument`, `URLDocumentConfiguration`, 1757-1968), `BackgroundTask.processingTask` (23627), `onDragSessionUpdated` (32367).
- SwiftUICore iOS 27 additions are internal or builder plumbing (`TupleContent` builders, `PreferenceKey` helpers). The visual-effect surface (`blur`, shaders, `glassEffect`, materials) is unchanged from iOS 26.

## 13. Probe 1 — offline Metal compile (iphonesimulator / iphoneos), language version defaults

Result: **the offline Metal compiler works for all three SDKs**, including a kernel that uses `threadgroup` memory and `half`. Default language is **Metal Shading Language 4.1** on all three, with fast math on.

File: `$TMPDIR/blur2ool-sdk/metalc/blur.metal`: a horizontal Gaussian pass `gaussH_tg` with a 16×16 threadgroup, a `threadgroup half4 tile[16][48]` (6144 bytes: 16 rows × (16 + 2·16 apron) × 8 bytes), clamp-to-edge loads, `threadgroup_barrier(mem_flags::mem_threadgroup)`, `half4` accumulation, weights from a `constant float*` buffer.

| Command | Result |
|---|---|
| `xcrun -sdk iphonesimulator metal -c blur.metal -o blur-iphonesimulator.air` | exit 0, 5280 B |
| `xcrun -sdk iphoneos metal -c blur.metal -o blur-iphoneos.air` | exit 0, 5248 B |
| `xcrun -sdk macosx metal -c blur.metal` | exit 0 |
| `xcrun -sdk <sdk> metallib blur-<sdk>.air -o blur-<sdk>.metallib` | exit 0 (simulator 5439 B, device 5423 B) |
| `-std=metal3.0`, `metal3.1`, `metal3.2`, `metal4.0`, `metal4.1`, `ios-metal2.4` for the simulator | all exit 0 |

Defaults, read from the compiler itself:

- `xcrun -sdk <sdk> metal -E -dM empty.metal` → `#define __METAL_VERSION__ 410` for iphonesimulator, iphoneos and macosx. The simulator additionally defines `__APPLE_EMBEDDED_SIMULATOR__ 1` (usable in `#if` for simulator-only workarounds in shared `.metal` files).
- `metal -S -emit-llvm` → target triples `air64_v29-apple-ios27.0.0-simulator`, `air64_v29-apple-ios27.0.0`, `air64_v29-apple-macosx27.0.0`; `!air.version = {2, 9, 0}` (AIR 2.9); `!air.language_version = {"Metal", 4, 1, 0}`; compile options `air.compile.denorms_disable`, `air.compile.fast_math_enable`, `air.compile.framebuffer_fetch_enable`. The threadgroup tile lowers to `addrspace(3) global [16 x [48 x <4 x half>]]`, as expected.
- Predefined `__FAST_MATH__ 1`, `__FINITE_MATH_ONLY__ 1`, `__METAL_MATH_FP32_FUNCTIONS_FAST__ 1`, `__METAL_HALF_MATH__ 1`. (`__METAL_FAST_MATH__ 0` / `__METAL_NATIVE_MATH__ 2` / `__METAL_PRECISE_MATH__ 3` are enum constants, not switches.)

Runtime compile options (`IOS_SDK/.../Metal.framework/Headers/MTLLibrary.h`, identical in `SIM_SDK`): `MTLLanguageVersion4_0 API_AVAILABLE(macos(26.0), ios(26.0))` (line 222), `MTLLanguageVersion4_1 API_AVAILABLE(macos(27.0), ios(27.0))` (line 224); `MTLCompileOptions.mathMode` (line 316, iOS 18; `MTLMathModeSafe = 0`, `Relaxed = 1`, `Fast = 2`; "Default depends on the language standard version"); `mathFloatingPointFunctions` (line 322, iOS 18; default `Fast`); `fastMathEnabled` deprecated since iOS 18 (line 310); `enableLogging` (line 407, iOS 18; `os_log` from shaders).

Recommendations for the build:

1. Let Xcode compile the app's `.metal` files into `default.metallib` (no flags needed; MSL 4.1 is the default for an iOS 27 target). Do not set `MTL_LANGUAGE_REVISION` unless a feature needs it.
2. **Precision for parity and measurement kernels:** fast math and flushed denormals are on by default. MEASURED in section 14: for a Gaussian evaluated in-shader with `exp()`, fast and safe math both stay within 7e-7 of the CPU reference, so fast math is not a practical parity risk for blurs. Still (a) generate weights on the CPU in `BlurCore` and pass them in a buffer (it is the same data the math view shows, and it gave the smallest error, 3e-7), and (b) let the parity harness compile with `MTLCompileOptions.mathMode = .safe` and `mathFloatingPointFunctions = .precise` when testing kernels with transcendental functions (bilateral range weights, Kawase/dual-filter variants that use `exp`/`pow`).
3. `half` is fine for display paths; keep `float` accumulation for kernels whose output feeds a number on screen (parity, fitted σ, energy), and say so on the shader layer card.
4. The Metal compiler is a downloaded component (section 1). If `xcrun metal` ever reports it is missing on a build machine, that is the cause.

## 14. Probe 2 — Mac GPU↔CPU parity harness (makeLibrary(source:), 256×256 r32Float convolution)

Result: **the planned parity harness works.** A plain Swift command-line program compiles `.metal` source at runtime with `makeLibrary(source:options:)`, runs 2D and separable convolutions on a 256×256 `r32Float` texture, reads back, and matches a CPU loop to within float rounding (max abs error ≤ 1e-6 on data in [0, 1] with one impulse of 50). The same binary, cross-compiled, also runs **inside the iOS 27 simulator** via `xcrun simctl spawn` with identical errors, and runs clean under Metal API validation once it uses `dispatchThreadgroups` (section 15).

File: `$TMPDIR/blur2ool-sdk/parity/main.swift` (about 280 lines; copy in `Documentation/research/sdk-probes/`). Builds: `xcrun -sdk macosx swiftc -swift-version 6 -O main.swift -o parity-mac` (Swift 6 mode, no errors); simulator: `xcrun -sdk iphonesimulator swiftc -swift-version 6 -O -target arm64-apple-ios27.0-simulator -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" main.swift -o parity-sim`, run with `xcrun simctl spawn <udid> $PWD/parity-sim`.

Test image: deterministic LCG noise in [0, 1], a step edge at x = 200, and one impulse of value 50 at (64, 128). Boundary: clamp-to-edge in both GPU and CPU. CPU reference: a straightforward loop accumulating in `Double` (and a `Float` variant with the same summation order).

MEASURED (2026-10-13, Apple M1 Max, macOS 27.2; GPU time = `gpuEndTime − gpuStartTime`, median of 21 command buffers, each one pass; Metal API validation on, which adds overhead):

| Test | max abs error vs CPU (Double) | vs CPU (Float, same order) | GPU time (median) | CPU loop |
|---|---|---|---|---|
| 2D conv, R = 4 (9×9 = 81 taps), σ = 1.5 | 9.54e-7 | 4.77e-7 | 0.078 ms | 9.7–11.2 ms (Double) |
| 2D conv, R = 8 (17×17 = 289 taps), σ = 3 | 8.35e-7 | 1.79e-7 | 0.13–0.24 ms | 94–253 ms (Double, unoptimized loop, noisy) |
| Separable H+V, R = 12, σ = 4, weights from CPU buffer | 2.98e-7 | – | 0.062 ms (two encoders) | – |
| Same, Gaussian weights computed in-shader with `exp()`, `mathMode = .fast` | 5.96e-7 | – | – | – |
| Same, in-shader `exp()`, `mathMode = .safe`, `mathFloatingPointFunctions = .precise` | 6.56e-7 | – | 0.062 ms | – |
| Threadgroup-tiled `half` H pass, R = 8 (probe 1 kernel, 16×16 groups, 6144 B static tg memory) | 1.60e-3 (rows without the impulse); 7.4e-3 on the impulse row (value 50) | – | 0.030 ms | – |

Same binary in the iOS 27.0 simulator ("Apple iOS simulator GPU"): **identical error figures to all printed digits**; GPU times 0.04–0.08 ms (the host GPU through the simulator's translation layer; meaningless as a phone number).

Readings:

1. Float parity is at the level of float rounding (about 1e-6 for sums of O(1) values). A tolerance of `1e-5` absolute (or `4 ulp × Σ|wᵢ·xᵢ|`) for float kernels, and `2e-3` relative for `half` kernels, is safe. These tolerances are COMPUTED-level claims the app can show next to each parity check.
2. Fast math does **not** hurt this kind of kernel measurably: the in-shader `exp()` variant differs from the CPU by 6e-7 with either math mode. The weights-from-buffer approach is still recommended (exactly the same numbers as the math view), but the fast-math default is not a parity risk for blurs. (Updates the caution in section 13.)
3. `half` storage of the tile and weights costs about 3 decimal digits (1.6e-3 on [0, 1] data), as expected from half's 11-bit significand. Good material for a "precision" layer card.
4. Runtime compile cost: **cold** `makeLibrary(source:)` took 1.08 s (fast math) on the Mac and **6.6 s (fast) / 19.0 s (safe)** in the simulator on first run; **warm** (the system shader cache hit on a re-run) it took 1–6 ms. So the app must ship precompiled `default.metallib` (Xcode does this for `.metal` files in the target) and only the Mac parity CLI should compile from source.
5. `MTLCompileOptions()` defaults, MEASURED on both Mac and simulator: `languageVersion = 0x40001` (MSL 4.1), `mathMode = 2` (`.fast`), `mathFloatingPointFunctions = 0` (`.fast`).

Recommended harness shape (for the build team): a SwiftPM executable target `blur2ool-parity` on macOS that depends on `BlurCore`, loads `App/Shaders/*.metal` as source text (concatenated, or with `#include` resolved by passing the directory through `MTLCompileOptions.preprocessorMacros` and keeping shaders header-free), runs every blur's GPU kernel on the procedural test images in `r32Float`, and asserts against the `BlurCore` CPU references with the tolerances above. It can also run in the simulator with `simctl spawn` as a second GPU (Apple2-class limits), which catches limit violations without a device.

## 15. Probe 3 — GPU limits; simulator vs A17 Pro; safe dispatch sizes

MEASURED by `$TMPDIR/blur2ool-sdk/caps/main.swift`, `parity/main.swift` and `tglimit/main.swift` (all copied to `Documentation/research/sdk-probes/`):

| Property | Apple M1 Max (macOS 27.2) | iOS 27.0 simulator ("Apple iOS simulator GPU") | A17 Pro (Apple9), REFERENCE |
|---|---|---|---|
| GPU families reported (`supportsFamily`) | apple1–apple7, metal3, metal4 | **apple1, apple2 only** (no metal3) | Apple9, Metal 3 & 4 (Feature Set Tables, GPU list) |
| `maxThreadsPerThreadgroup` | 1024 | **512** | 1024 |
| `maxThreadgroupMemoryLength` | 32768 B | **16384 B** | 32 KB |
| pipeline `maxTotalThreadsPerThreadgroup` (our kernels) | 1024 | 512 | ≤ 1024, check at runtime |
| `threadExecutionWidth` (SIMD width) | 32 | 32 | 32 (UNVERIFIED on device; Apple GPUs use 32-wide SIMD groups) |
| `hasUnifiedMemory` | true | **false** | true |
| `maxBufferLength` | 39813 MiB | **256 MiB** | device-dependent |
| `readWriteTextureSupport` | tier 2 | **tier 0** | tier 2 (Apple GPUs from A11; check at runtime) |
| `supports32BitFloatFiltering` | true | **false** | **not guaranteed**: the tables say only "some GPUs in the Apple7 and Apple8 families … in iPadOS" filter 32-bit float formats; check at runtime |
| `argumentBuffersSupport` | tier 2 | tier 1 | tier 2 (Apple6+) |
| `supportsFunctionPointers`, `supportsDynamicLibraries` | true | false | – |

REFERENCE: Apple, *Metal Feature Set Tables* (PDF, dated May 21, 2026, https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf), "GPU implementation limits by family": Maximum threads per threadgroup 512 (Apple2, Apple3), 1024 (Apple4–Apple10); Maximum total threadgroup memory allocation 16,352 B (Apple2), 16 KB (Apple3), 32 KB (Apple4–Apple10); threadgroup memory length alignment 16 B; `setBytes` max 4 KB; Nonuniform threadgroup size: Apple4+; "A17 Pro — Metal 3 & 4 — Apple9". Footnote 5: the threads figure is a theoretical maximum; check `MTLComputePipelineState.maxTotalThreadsPerThreadgroup` at runtime.

REFERENCE: Apple, *Developing Metal apps that run in Simulator* (https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator): "Simulator provides a device instance with capabilities similar to an Apple family 2 GPU". It also lists: constant-address-space buffers ≤ 64 KB, constant buffer offsets aligned to 256 bytes (iOS needs 4), ≤ 14 constant buffers per pipeline; **no writes to sRGB textures**; avoid `r8Unorm_srgb`, `b5g6r5Unorm`, `a1bgr5Unorm`, `abgr4Unorm`, `bgr5A1Unorm`, XR10 and YUV formats; no rendering to `rgb9e5Float`; heaps private only; no programmable blending; no Xcode GPU profiling.

What the simulator actually does (MEASURED):

| Feature | Simulator, no validation | Simulator, `MTL_DEBUG_LAYER=1` (Metal API validation) |
|---|---|---|
| `dispatchThreads` (any grid, even 256×256 with 32×16 groups) | runs correctly | **aborts**: `failed assertion 'Dispatch Threads with Non-Uniform Threadgroup Size is not supported on this device'` |
| `access::read_write` on `r32Float` | runs correctly (value 3.0) | **aborts**: `Shader uses texture(t[0]) as read-write, but hardware does not support read-write texture of this pixel format.` |
| 1024 threads per threadgroup | runs (!) | **aborts**: `threadsPerThreadgroup … (1024) must be <= 512. (device threadgroup size limit)` |
| 32 KB dynamic threadgroup memory; 24 KB static tg array | runs; pipeline created | (not reached; expected to abort like the threads case) |
| `simd_sum` | correct (496) | passes |
| bilinear `sample()` of `r32Float` / `r16Float` | 0.5 (filtered) | passes |

So without validation the simulator silently runs work that a real Apple2-class device would reject, and with validation it enforces the Apple2 limits. Xcode turns Metal API validation on for debug runs by default (UNVERIFIED for Xcode 27 specifically; it is the long-standing default in the scheme's Diagnostics tab). The 32-bit float filtering case shows the opposite trap: the simulator filters `r32Float` even though the iPhone may not.

### Safe dispatch rules for Blur2ool (work on simulator, M1-class Mac, and A17 Pro)

1. **Use `dispatchThreadgroups`, never `dispatchThreads`,** and put a bounds check (`if (gid.x >= w || gid.y >= h) return;`) at the top of every kernel, after any threadgroup loads and barriers (threads outside the image must still reach the barrier). Grid = `ceil(W / tw) × ceil(H / th)`.
2. **Threadgroup size: 16×16 = 256 threads** (or 32×8) for 2D image kernels. It fits the simulator's 512 cap, is a multiple of the 32-wide SIMD group, and leaves room for kernels whose `maxTotalThreadsPerThreadgroup` drops because of register pressure. Always clamp with `min(256, pso.maxTotalThreadsPerThreadgroup)` at runtime, and fall back to 32×(max/32) if a pipeline reports less.
3. **Threadgroup memory ≤ 16 KB per threadgroup** (simulator cap; Apple2 is 16,352 B). Round dynamic sizes up to 16 B. Budget for a separable tiled pass with 16×16 threads: rows × (16 + 2R) × bytes-per-pixel. `half4` (8 B): R ≤ 56 fits in 16 KB (16 × 128 × 8 = 16384). `float4` (16 B): R ≤ 24 (16 × 64 × 16 = 16384). `float` (4 B): R ≤ 120. Larger radii should switch algorithm (box-cascade, running sum, downsample pyramid, or non-tiled global reads), which is itself a teachable "algorithm choice depends on σ" moment. If a phone-only fast path wants 32 KB, gate it on `device.maxThreadgroupMemoryLength`.
4. **No `read_write` textures**: always ping-pong between a source and a destination texture. That is also how separable passes naturally work.
5. **Never `sample()` an `r32Float`/`rgba32Float` texture with a linear filter** unless `supports32BitFloatFiltering` is true. Use `read()` with integer coordinates for measurement kernels (float precision), and `rgba16Float` (filterable everywhere) for the bilinear "two taps per fetch" trick in display kernels.
6. Pass kernel weights in an `MTLBuffer` or with `setBytes` (≤ 4 KB, i.e. ≤ 1024 floats, which covers R ≤ 511 for a 1D kernel). Keep constant buffers ≤ 64 KB and offsets 256-byte aligned for the simulator.
7. Do not write compute output into an sRGB texture (simulator rule); keep intermediate textures linear (`rgba16Float`) and set the `MTKView` to `bgra8Unorm` or `rgba16Float`, converting in the final pass.
8. Run the app's debug builds with Metal API validation on, both in the simulator and on the phone; the simulator then acts as an Apple2-limits checker.

## 16. Probe 4 — Swift 6 typecheck of SwiftUI + MTKView representable for iOS 27 simulator

Result: **passes with zero diagnostics** in Swift 6 language mode, complete strict concurrency and `-warnings-as-errors`, for both simulator and device targets. It also links into a Mach-O arm64 simulator executable.

File: `$TMPDIR/blur2ool-sdk/typecheck/MetalViewProbe.swift` (about 100 lines; copy in `Documentation/research/sdk-probes/`). Contents: an `@Observable @MainActor GPUStats`, a `@MainActor final class BlurRenderer: NSObject, MTKViewDelegate` that compiles a compute kernel with `makeLibrary(source:)`, dispatches it with `dispatchThreads` into the drawable, reads `gpuEndTime − gpuStartTime` in `addCompletedHandler` and hops to the main actor with `Task { @MainActor in … }`; a `UIViewRepresentable` `MetalBlurView` whose `makeCoordinator()` returns the renderer; and a `@main App`.

Commands (run from `$TMPDIR`, never in iCloud):

```sh
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator swiftc -typecheck -parse-as-library -swift-version 6 \
  -strict-concurrency=complete -warnings-as-errors \
  -target arm64-apple-ios27.0-simulator -sdk "$SDK" MetalViewProbe.swift          # exit 0, no output
xcrun -sdk iphoneos swiftc -typecheck -parse-as-library -swift-version 6 \
  -strict-concurrency=complete -warnings-as-errors \
  -target arm64-apple-ios27.0 -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" MetalViewProbe.swift   # exit 0
# same with -default-isolation MainActor: exit 0
# full compile: swiftc ... -O -o ProbeApp  -> "Mach-O 64-bit executable arm64" in 4 s
```

Notes:
- `-parse-as-library` is needed for a single file with `@main` (otherwise: `'main' attribute cannot be used in a module that contains top-level code`). Xcode passes it automatically.
- `Pitfalls.swift` in the same folder shows the two concurrency traps described in section 5: the non-Sendable `MTLTexture` captured in a completion handler (warning) and `waitUntilCompleted()` inside `async` (error; use `await cb.completed()`).
- This makes `swiftc -typecheck` against the iOS simulator SDK a fast (about 4 s) pre-flight for the build team that never touches `xcodebuild` or iCloud.

Second file, `ApiSurfaceProbe.swift` (in `sdk-probes/`): one view and two helpers that use **every SDK API this document recommends**: `Picker` with `.pickerStyle(.tabs)`, `Chart { LinePlot(x:y:domain:) { … }; RuleMark }`, `Chart3D { SurfacePlot(x:y:z:) { x, z in … }.foregroundStyle(.heightBased) }` with `.chart3DPose($pose)` and `.chart3DCameraProjection(.perspective)`, `.blur(radius:)`, `.layerEffect(ShaderLibrary.gaussianH(.float(σ)), maxSampleOffset:)`, `.glassEffect(.regular.tint(.orange), in: .rect(cornerRadius: 0))`, `PhotosPicker(selection:matching:)` + `loadTransferable(type: Data.self)` in `.task(id:)`, an ImageIO thumbnail downsample, `ImageRenderer` with `colorMode = .extendedLinear`, all nine `CIFilter` blur builtins (`gaussianBlur`, `boxBlur`, `discBlur`, `motionBlur`, `zoomBlur`, `bokehBlur`, `maskedVariableBlur`, `median`, `morphologyGradient`) and `MPSImageGaussianBlur` / `MPSImageBox` / `MPSImageTent` / `MPSImageMedian`. **Typechecks with zero diagnostics** in Swift 6 mode with complete strict concurrency, for both `arm64-apple-ios27.0-simulator` and `arm64-apple-ios27.0`.

## 17. Open items / UNVERIFIED

Nothing here was run on the iPhone 15 Pro Max (A17 Pro). Every device-specific statement is either REFERENCE (Apple's tables) or INFERRED. In priority order, the build should verify on the phone:

1. **On-screen vs offscreen blur.** Does `UIView.drawHierarchy(in:afterScreenUpdates: true)` (or a `UIGraphicsImageRenderer` snapshot of the hosting view) capture the render server's `.blur`, Material and glass output faithfully? If it does, the app can MEASURE the on-screen PSF of all three. If not, offscreen ImageRenderer remains the only in-process measurement, and the app must say so.
2. ImageRenderer `.blur` PSF on the A17 Pro: expected to match the simulator and Mac (σ = r, truncation at about ±2.3 r for r ≥ 8) because it is the same SwiftUI code. UNVERIFIED.
3. `supports32BitFloatFiltering` on A17 Pro. Apple's tables only promise it for "some" Apple7/Apple8 iPads. The app must check at runtime and must not depend on it.
4. Counter sampling on A17 Pro: expected to be stage-boundary only, like M1 Max. UNVERIFIED.
5. MPS and our kernels' GPU times on the phone: warm-up behaviour and clock ramp. Report the median of N after warm-up.
6. Whether Xcode 27's default scheme turns on Metal API validation for debug runs. It has historically, but this is UNVERIFIED for 27.0. Turn it on explicitly in `project.yml` (scheme `enableGPUValidationMode` / `gpuValidationMode`; the exact XcodeGen key is UNVERIFIED) so the simulator enforces the Apple2 limits.
7. `Shader.Argument.floatArray` and `.data` size limits for passing kernel weights to SwiftUI shaders. UNVERIFIED; keep weight arrays ≤ 1024 floats.
8. `SurfacePlot` sampling density and `Chart3D` performance on the phone. UNVERIFIED.
9. The exact command to install the Metal Toolchain component on a fresh Xcode 27 machine (`xcodebuild -downloadComponent MetalToolchain` was the Xcode 26 form). UNVERIFIED.
10. `CALayer.filters`/`backgroundFilters` on iOS 27. These are declared in the header without an iOS restriction, but historically they had no effect on iOS. Not needed; do not rely on them.

Lost-and-rebuilt note: the first session's probe folder (`$TMPDIR/blur2ool-sdk/`) disappeared before this session. The ImageRenderer PSF, counter-sampling and MPS probes were rewritten and re-run. Their results reproduced the earlier tables, except for MPS absolute timings (noted in §8).

<!-- STATUS: COMPLETE -->
