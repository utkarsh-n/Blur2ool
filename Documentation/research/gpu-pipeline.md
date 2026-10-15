# Blur2ool research: the GPU layer and Apple's rendering pipeline

Status: complete. Date: 13 October 2026.
Scope: how a blur travels from SwiftUI to photons on iPhone, the Apple GPU features that matter for convolution, Metal implementation patterns, cost models and measurement, and what Blur2ool can show at the GPU layer.

Honesty labels follow BRIEF.md: LIVE, MEASURED, COMPUTED, MODELED, REFERENCE, INFERRED. Claims I could not verify are marked UNVERIFIED.

## 0. Summary

- **Path of a SwiftUI blur.** `.blur(radius:)` is a modifier value; SwiftUI turns it into either a Core Animation layer filter (most likely the private `CAFilter` `gaussianBlur`, INFERRED from strings in `SwiftUICore`) or a pass in its own Metal rasterizer RenderBox (used by `drawingGroup` and `ImageRenderer`). The layer tree is committed to the render server, a separate process (Apple, Tech Talk 10855), which is `backboardd` on iOS (INFERRED: it registers `com.apple.CARenderServer` in the iOS 26.5 Simulator runtime). The server compiles the tree into GPU passes ("render prepare"), the GPU executes them ("render execute"), and the frame is shown at the next VSYNC. The app's own timers cannot see this work.
- **Why blurs cost so much.** A blur needs neighbours up to ~3σ away. A tile-based GPU renders 32 × 32-pixel tiles in on-chip memory and a fragment can read only its own pixel, so the blur input must first be written to memory and read back in a new pass: an **offscreen pass** (Apple's term). A **backdrop** blur additionally has to stop the frame half-way, read back everything behind it, blur that, and resume, every frame anything behind it changes. Apple's 2014 numbers: a full-screen iOS 8 blur cost 14.5–18 ms of GPU time on an iPad Air. QuartzCore today ships kernels named `tile_downsample_{1,2,4,8}`, `tile_simd_blur_{5…27}`, `downsample_blur_*`, `upsample_*`, `variable_blur_*` (INFERRED pipeline: downsample, short separable blur, upsample).
- **A17 Pro facts that matter** (Apple9; Feature Set Tables, 21 May 2026): 32 KB threadgroup memory, 1024 threads per threadgroup, SIMD width 32, SIMD reductions and permutes, 32-bit float filtering, 32 × 32 tiles, 256 KB implicit imageblock; registers, threadgroup and tile memory allocated dynamically from L1 (Tech Talk 111374). Memory: 8 GB LPDDR5, **51.2 GB/s peak per third-party data (UNVERIFIED)**. Lossless compression since A12, but not for textures with `.shaderWrite` usage.
- **Implementation patterns, verified.** Seven Metal sketches (separable Gaussian with threadgroup tile, linear-sampled Gaussian fragment shader, dual-Kawase down/up, SAT box, running-sum box, radial gather, golden-angle bokeh) compile with no warnings for `iphoneos` and `iphonesimulator` (Metal 3.1/3.2/4.0) and match independent CPU references to one fp16 ulp on the M1 Max and in the iOS 27.0 Simulator.
- **Measured findings worth showing in the app** (M1 Max / Simulator): hardware bilinear filtering has **8 bits** of sub-texel precision (the linear-sampling trick's error source); fragment blurs whose textures lack `.shaderWrite` ran **1.3–1.5× faster**; **`half` accumulators** cost up to one 8-bit step in a Gaussian and six in a running sum; a **fp32 SAT** on a 4096² image is wrong by up to 7.5 × 10⁻² at the far corner, and mean-centring fixes it; dual-Kawase σ ≈ 1.29, 2.89, 5.92, 11.90 px for 1–4 levels; `MPSImageGaussianBlur` is approximate (2.4 × 10⁻³) and its cost does not grow with σ; `generateMipmaps` is a 2 × 2 box on the M1 Max.
- **Measuring on iOS.** Use `gpuStartTime`/`gpuEndTime` per command buffer (median of warmed runs) and a `timestamp` `MTLCounterSampleBuffer` for per-pass times. The classic counter API supports **only stage-boundary sampling** on Apple GPUs (MEASURED on the M1 Max), so it gives timestamps per encoder and per vertex/fragment stage: put each pass in its own encoder. **Metal 4 counter heaps** with `.precise` granularity do give per-dispatch timestamps inside a single encoder (MEASURED on the M1 Max; 24 MHz tick rate); with `.relaxed` they do not. The Metal 4 API does not exist in the iOS Simulator SDK.
- **Compression and compute.** Apple confirms (Tech Talk 111431, 2026) that before M5/A19, "compression was disabled for textures with MTLTextureUsageShaderWrite". So on the A17 Pro, blur intermediates written by a compute shader lose lossless compression and fragment-written ones keep it. Apple10 "universal texture compression" removes this difference. The **Simulator** exposes no counters and its GPU times are meaningless (a 1 GB copy "took" 0.055 ms); its numerical results, however, matched the Mac exactly.
- **Cost model.** A two-pass separable blur moves about 4 bytes × B per pixel: 115 MB for a full `rgba16Float` iPhone 15 Pro Max screen, a 2.25 ms floor at 51.2 GB/s. Scaling the M1 Max measurements gives MODELED A17 Pro times of roughly 1.6 ms (MPS), 2.7 ms (dual-Kawase), 3.4–4.6 ms (σ = 8 separable), 10 ms (SAT) and 15 ms (64-sample bokeh): wide and gather blurs need a half-resolution live preview. The app should replace every one of these with its own MEASURED numbers.
- **What to show at the GPU layer:** the actual kernel source (compiled at runtime from the same text), dispatch grids and aprons over the image, one pixel's fetch footprint, a per-pass timeline from counters with modeled ghost bars, bytes and a measured roofline, precision heat maps, a measured device card, a compression A/B, a tile view, and a clearly labelled INFERRED lane for the system's own blur.

## 1. From `.blur(radius:)` to photons

### 1.1 Stage map (public vs INFERRED)

Apple documents the outline of this pipeline (the "render loop") in two 2020 Tech Talks: "Explore UI animation hitches and the render loop" (10855) and "Demystify and eliminate hitches in the render phase" (10857), plus the older WWDC 2014 session 419 "Advanced Graphics and Animations for iOS Apps". Everything below the level of "the render server renders your layer tree on the GPU" is private. Where I name private classes, shader functions or processes, the evidence is strings, symbols and launchd plists in Apple's shipped binaries (iOS 26.5 Simulator runtime 23F73 and macOS 27.2 on this Mac), which shows what exists but not when it is used. Those rows are INFERRED.

| # | Stage | Process | What happens to a blur | Evidence | Label |
|---|---|---|---|---|---|
| 0 | `View.blur(radius:opaque:)` | app | A modifier value in the view tree. Doc: "Applies a Gaussian blur to this view." It does not say radius = σ. | SwiftUI docs; `sdk-feasibility.md` §3 | REFERENCE |
| 1 | SwiftUI update | app | The attribute graph re-evaluates `body`, produces a display list, and hands it to one of two renderers: (a) a **Core Animation renderer** that builds/updates a `CALayer` tree, or (b) SwiftUI's own **Metal rasterizer** (private `RenderBox.framework`), used for `.drawingGroup()`, `ImageRenderer` and (probably) `Canvas`. | `drawingGroup` doc: it only includes "views that SwiftUI rasterizes directly using its own drawing primitives"; `RenderBox.framework` ships a `default.metallib` with `filter_blur_fragment` and a `RB_EXACT_BLUR` environment switch (strings, iOS 26.5 sim runtime) | INFERRED |
| 2 | Blur becomes a layer filter | app | On path (a), `.blur` most likely becomes a private `CAFilter` of type `gaussianBlur` on the layer, with `inputRadius` and `inputNormalizeEdges` (the `opaque:` flag maps naturally to edge normalization). Public `CALayer.filters` is documented as "not supported on layers in iOS", so this route is only open to Apple's frameworks. | `SwiftUICore` binary contains the strings `gaussianBlur`, `inputNormalizeEdges`, `variableBlur`, `filters`; `QuartzCore` contains `CAFilter`, `gaussianBlur`, `inputRadius`, `inputNormalizeEdges`, `inputHardEdges`, `inputQuality`, `inputIntermediateBitDepth`, `variableBlur`, `CABackdropLayer` | INFERRED |
| 3 | Commit | app → render server | At the end of the run-loop turn, `CATransaction` commits: "the entire altered layer tree is collected and sent to the render server for rendering" (10855). The blur travels as a few numbers (filter type, radius, flags), not pixels. | Tech Talk 10855 | REFERENCE |
| 4 | Render server process | `backboardd` | "The next stage happens in a separate process called the render server" (10855). On iOS that process is `backboardd`: in the iOS 26.5 Simulator runtime, `com.apple.backboardd.plist` registers the Mach service `com.apple.CARenderServer`, and `backboardd` imports `CAWindowServer`/`CAWindowServerDisplay` from QuartzCore. Not verified on a device image. | launchd plist + `nm -u` | INFERRED |
| 5 | Render prepare | render server, CPU | "Our layer tree is compiled down into a pipeline of simple operations for the GPU to execute" (10857). This is where the server decides which layers need **offscreen passes** (§1.2). | Tech Talk 10857 | REFERENCE |
| 6 | Render execute | render server → GPU | "The GPU draws the app's layers into a final image" (10857). For a UIKit blur in 2014 Apple listed five passes: render content, capture + downscale, horizontal blur, vertical blur, upscale + tint (session 419). Today's QuartzCore ships Metal kernels named `tile_downsample_{1,2,4,8}`, `tile_simd_blur_{5,7,11,15,19,23,27}`, `narrow_blur_{7…27}_frag`, `downsample_blur_{2,4}_frag`, `upsample_frag`, `single_pass_blur_3`, `resolve_blur_weight_frag` and a `variable_blur_*` family (both iOS 26.5 sim and macOS 27.2 `default.metallib`; the macOS one adds `narrow_blur_N_compute`). The names suggest the same shape: **downsample by 1/2/4/8, then a separable blur with 5–27 taps, then upsample**, with some passes done as tile shaders in tile memory. | session 419; `strings` on `QuartzCore.framework/default.metallib` | REFERENCE (2014 passes) / INFERRED (current kernels) |
| 7 | Metal on the AGX GPU | GPU | Tile-based deferred rendering, tile memory, texture units, compression (§2). | Apple Metal docs, WWDC | REFERENCE |
| 8 | Display | display controller | The finished frame is shown on the next VSYNC. Double-buffered by default (two frames of latency from commit to glass), triple-buffered under load (10855). The iPhone 15 Pro Max panel runs up to 120 Hz (ProMotion), so each stage has 8.33 ms at full rate. | Tech Talk 10855; Apple tech specs | REFERENCE |

Facts worth surfacing in the app at this layer:

- **The app never runs the blur.** For a `.blur` drawn on screen through Core Animation, the pixels are produced by another process (`backboardd`, INFERRED) on the shared GPU. The app's own Metal timers cannot see that work. Instruments can (Core Animation / Animation Hitches templates, 10857).
- **SwiftUI has two blur implementations** (INFERRED): the render-server `gaussianBlur` filter for on-screen layers and RenderBox's `filter_blur_fragment` for `drawingGroup`/`ImageRenderer`. `sdk-feasibility.md` §4 measured the second one (σ ≈ radius, hard truncation near ±2.3·radius for radius ≥ 8). Whether the on-screen path matches is open (UNVERIFIED). `RB_EXACT_BLUR` in RenderBox implies the default blur is an approximation with an exact mode behind a debug switch (INFERRED from the name only).
- **The 2014 numbers show why Apple downsamples.** Session 419 quoted about 14.5 ms (light/dark) and 18.15 ms (extra light) of GPU time for a full-screen blur on an iPad Air, and said the blur was disabled on the iPad 3rd generation (replaced by a tint). Separability cut an 11 × 11 kernel from 121 to 11 samples per pixel per pass. Each switch between passes left the GPU idle for roughly 0.1–0.2 ms. REFERENCE, 2014 hardware, quoted as history.

### 1.2 Why blurs force offscreen passes

Apple's definition (10857): an offscreen pass is "anytime the GPU must render a layer by first rendering it somewhere else and then copying it over". A blur needs one for three reasons:

1. **A blur is a neighbourhood operation.** Output pixel (x, y) needs input pixels up to about 3σ away in every direction. A fragment shader can read *its own* pixel in the render target (programmable blending / framebuffer fetch), but never its neighbours'. The neighbours must already exist in a texture that can be sampled. So the content to be blurred is first rendered to a separate texture, the render pass ends, and a new pass samples that texture. COMPUTED (from the definition of convolution) + REFERENCE (Metal programmable blending reads only the current pixel).
2. **On a tile-based GPU the neighbours are not even on chip.** The GPU renders the frame one screen tile at a time in on-chip tile memory (§2.1). A pixel near a tile edge needs texels from the next tile, which has not been rendered yet or has already been flushed. So the whole input has to be stored to device memory first. This is the main hardware reason a blur breaks a render pass. The tile size Apple uses for rendering is not published (it is selectable for tile shaders: 16×16, 32×16, 32×32 are typical; UNVERIFIED for render-server use).
3. **A blur grows the drawn area.** A blurred layer paints up to ~3σ outside its bounds, so the offscreen texture must include an apron (margin) around the layer, and partial updates must redraw a larger dirty region. COMPUTED.

Each extra pass costs (a) writing the intermediate texture to memory, (b) reading it back, possibly several times, and (c) a pass switch where the GPU can drain and go idle. Downsampling first (as Apple's passes do) shrinks (a) and (b) by 4× per halving.

### 1.3 Why backdrop blurs are expensive

A backdrop blur (`Material`, `UIVisualEffectView`, `.glassEffect`, CSS `backdrop-filter`) blurs whatever is *behind* the view, which belongs to other layers and often other processes (wallpaper, other apps' windows in multitasking). 10857 says the renderer "must copy what's beneath the visual effect view to another texture with an offscreen pass", then "applies the visual effect types to the result and copies it back". In GPU terms:

1. **Render everything below first.** The server renders all layers beneath the effect, in z-order, into the frame.
2. **End the pass and read back.** Because the effect needs neighbours (§1.2), the server must end the render pass so that the tiles reach memory, then copy the region under the effect **plus an apron of about 3σ** into a new texture. That is a full read of the region from memory, which on a tile-based GPU is exactly the traffic TBDR was designed to avoid.
3. **Blur it** (downsample, separable passes, upsample: INFERRED from the kernel names in §1.1).
4. **Resume compositing on top.** The layers above the effect are drawn in a new render pass that must load the partially finished frame back from memory (load action `load` instead of `clear`/`dontCare`). One backdrop can therefore split a frame's single on-chip pass into two or more passes, each of which writes and reads the full frame.
5. **Nothing can be cached.** A static blurred layer could be rasterized once and reused; a backdrop's input changes whenever anything behind it scrolls or animates, so it is redone every frame the region is dirty (INFERRED, follows from 1–4). Overlapping backdrops chain: the second one samples the output of the first.

The private QuartzCore metallib contains a function constant named `fc_memoryless_backdrop`, which suggests Apple keeps some backdrop captures in memoryless (tile-only) attachments when the capture fits a tile pass (INFERRED from the name only; I could not see the code). The newer `glassBackground`/`glassForeground` filters and the `SdfFragmentUniforms` struct (fields such as `blur_radius`, `edge_bleed_blur_radius`, `inner_refraction_amount`) in the same metallib are the Liquid Glass shaders; they also sample the backdrop (INFERRED).

### 1.4 What the app can measure about this layer

| Quantity | How | Label |
|---|---|---|
| Effective σ of SwiftUI `.blur(radius:)` in the offscreen renderer | `ImageRenderer` on an impulse or line, fit the PSF (`sdk-feasibility.md` §4) | MEASURED |
| Same, on-screen path | Capture the hosting view with `UIView.drawHierarchy(in:afterScreenUpdates:)`; whether render-server filters are captured faithfully is UNVERIFIED | MEASURED if it works |
| Cost of system blurs (materials, glass) | Not visible to the app's Metal timers. The app can measure **frame pacing**: stack N `Material` layers over a scrolling field and record `CADisplayLink` `targetTimestamp` vs actual callback times to count missed frames | MEASURED (indirect) |
| Offscreen pass counts | Instruments only (Core Animation / Animation Hitches templates, 10857), not available in-app | REFERENCE |
| Its own Metal blurs | Everything in §4.3 | MEASURED |
| Names of Apple's blur kernels | The list in §1.1, shown as a static table with the date and OS build they were read from | INFERRED |

## 2. Apple GPU architecture relevant to convolution

The iPhone 15 Pro Max has the **A17 Pro**, which Apple's Metal Feature Set Tables (version dated 21 May 2026) place in GPU family **Apple9** (with A18, M3, M4). The A17 Pro GPU has 6 cores (Apple, September 2023 launch; the 5-core part is the iPad mini). Apple calls the Apple9 shader core "a completely new shader core architecture" (Tech Talk 111374, "Discover new Metal profiling tools for M3 and A17 Pro").

### 2.1 Tile-based deferred rendering, tile memory, imageblocks

REFERENCE, Apple article "Tailor your apps for Apple GPUs and tile-based deferred rendering":

- The GPU "breaks up the render destination into a grid of smaller regions, called tiles", processes each tile on one core, and "defers" shading until all geometry for the tile is known. Fragments write into **tile memory**, "fast, temporary storage that resides on the GPU itself", with bandwidth and latency "many times" better than device memory. Only at the end of the pass does the tile go to device memory (the **store action**); at the start of a pass a tile is filled by the **load action** (`load` reads memory, `clear` and `dontCare` do not).
- **Imageblocks** (A11 / Apple4 and later) expose tile memory as a 2-D structure to fragment, tile and compute functions. "Within a fragment shader, the current fragment has access to only the imageblock data associated with that fragment's position in the tile. In a compute function, a thread can access all of the imageblock data."
- **Tile shaders** (Apple4+) are compute functions dispatched inside a render pass that see the whole tile. They let an algorithm "remain in local GPU memory by keeping multiple operations within a tile".
- Feature Set Tables limits for Apple9: maximum tile size 32 × 32 in render passes without MSAA; explicit imageblock allocation 32 KB; **implicit imageblock allocation 256 KB** (128 KB on Apple4–Apple8); imageblock + threadgroup allocations share the same budget (footnote 6).

What this means for blurs (COMPUTED / INFERRED):

- A **tile shader can blur only within a tile**. A 32 × 32 tile with radius r has only (32 − 2r)² interior pixels whose whole footprint is on chip. At r = 4 that is 24² = 56% of the tile; at r = 8, 16² = 25%; at r ≥ 16 nothing. So in-tile blurs are only useful for **small kernels and for downsampling**, which is exactly what Apple's private `tile_downsample_{1,2,4,8}` and `tile_simd_blur_{5…27}` kernels suggest (§1.1; the 27-tap maximum is r = 13, INFERRED).
- Anything wider needs the result in device memory first. That is the hardware reason for the offscreen passes in §1.2.
- **Memoryless** attachments (Apple2+) have no backing memory at all; they are useful for intermediates consumed within the same pass (for example a downsample feeding a tile-shader blur), never for a texture that a later pass samples.

### 2.2 Threadgroup memory and SIMD-groups

REFERENCE (Metal Feature Set Tables, 21 May 2026, "GPU implementation limits by family"): maximum total threadgroup memory allocation is **16,352 B on Apple2, 16 KB on Apple3, 32 KB on Apple4 through Apple10**; maximum threads per threadgroup is 512 on Apple2–Apple3 and 1024 on Apple4+; threadgroup memory length alignment 16 B. **SIMD-scoped permute** operations (`simd_shuffle*`) need **Apple6+**, **SIMD-scoped reduction** operations (`simd_sum`, `simd_prefix_*_sum`) need **Apple7+**. So on the A17 Pro (Apple9) the limits are 32 KB and 1024 threads, and every SIMD-group function the sketches use is available.

Apple9 changes how that memory is provisioned. Tech Talk 111374: on M3 and A17 Pro, "Registers, threadgroup, tile stack, and other shader core memory types are assigned dynamically from L1 cache", and an "occupancy manager" caps the number of resident SIMD-groups to avoid spilling to the last-level cache. Before Apple9, occupancy was set by the worst-case register count. Consequence for blur kernels: a big threadgroup tile no longer reserves a fixed slice of a fixed scratchpad; it competes with registers and cached texture data in the same L1. The only reliable way to choose a tile size on the phone is to measure several (INFERRED; the app can do this).

MEASURED on this Mac (Apple M1 Max, macOS 27.2) with a probe that queries `MTLDevice` and builds a trivial compute pipeline (`$TMPDIR/blur2ool-gpu-pipeline/devprobe.swift`):

| Property | M1 Max (Apple7 family) | iOS 27.0 Simulator ("Apple iOS simulator GPU") |
|---|---|---|
| GPU families reported | apple1 to apple7, mac2, common1 to common3, metal3, metal4 | **apple1, apple2, common1 only** |
| `maxThreadgroupMemoryLength` | 32,768 B (32 KB) | **16,384 B (16 KB)** |
| `maxThreadsPerThreadgroup` | 1024 | **512** |
| `threadExecutionWidth` (SIMD-group width) | 32 | 32 |
| `readWriteTextureSupport` | tier 2 | **tier 0 (no `access::read_write` textures)** |
| `supports32BitFloatFiltering` | true | false |
| Counter sampling points | stage boundary only | draw, dispatch, blit (no stage); `counterSets` = nil |
| Counter sets | `timestamp` (`GPUTimestamp`) | none |
| Memoryless render targets | yes | yes (accepted) |

What this means for a blur kernel:

- **Threadgroup memory is 32 KB on Apple GPUs of the A11 (Apple4) generation and later.** The Feature Set Tables list 32 KB for Apple9 (A17 Pro); I confirmed 32 KB on the M1 Max (Apple7) by query. I did not query the A17 Pro directly. Treat "32 KB on the iPhone 15 Pro Max" as REFERENCE until the app's own probe reads `maxThreadgroupMemoryLength` on the phone and shows it as MEASURED.
- **A tile with its apron must fit.** A horizontal line tile of `TG` pixels with radius `r` holds `TG + 2r` texels. In `half4` (8 B) at TG = 256 and r = 64 that is 384 x 8 = 3,072 B. A 2-D tile of 16 x 16 pixels with radius r needs `(16 + 2r)^2` texels: r = 16 gives 48^2 x 8 B = 18 KB (fits in 32 KB, does not fit the simulator's 16 KB); r = 24 gives 64^2 x 8 B = 32 KB (exactly the device limit, leaving nothing else). COMPUTED. This is why practical tiled blurs are separable (1-D tiles) or switch to mip/downsample algorithms at large radii.
- **Occupancy falls as threadgroup memory per threadgroup rises**, at least before Apple9. Apple does not publish per-core sizes. Philip Turner's community microbenchmarks (`github.com/philipturner/metal-benchmarks`) estimate about 208 KB of registers and about 60 KB of threadgroup ("shared") memory per core on Apple7/Apple8, with an 8 KB L1 data cache; nothing for Apple9 (UNVERIFIED, not Apple data). On Apple9 the dynamic L1 allocation described above replaces fixed partitions.
- **SIMD-group width is 32** on the M1 Max and in the Simulator (MEASURED via `threadExecutionWidth`), and Apple states it for Apple silicon generally ("On Apple silicon, SIMD groups are composed of 32 threads", Tech Talk 10876 on the A15). `simd_prefix_exclusive_sum`, `simd_shuffle` and friends operate across those 32 lanes, which is what the SAT row-scan sketch in §6 relies on.

### 2.3 Texture sampling hardware and the linear-sampling trick

Every Apple GPU core has texture units that fetch and **bilinearly filter** in fixed-function hardware. A `sample()` with `filter::linear` at a non-integer coordinate returns the weighted average of the 2 × 2 nearest texels, with weights given by the fractional position, for roughly the price of one fetch. (REFERENCE for filtering semantics: Metal Shading Language spec, "Sampler"; the "roughly one fetch" cost is the standard GPU design and Apple does not publish texture-unit throughput, UNVERIFIED for A17 Pro.)

Which formats filter (REFERENCE, Feature Set Tables pixel-format capabilities): `RGBA8Unorm`, `RGBA8Unorm_sRGB` and `RGBA16Float` are filterable on every Apple family; 32-bit float formats (`R32Float`, `RGBA32Float`) list "All" capabilities, including Filter, only from **Apple9** (some Apple7/8 iPads optionally, footnote 6, `MTLDevice.supports32BitFloatFiltering`). The Simulator reports no 32-bit float filtering (MEASURED). Practical rule for Blur2ool: store images and intermediates as `rgba16Float`, sample with linear filtering, accumulate in `float`.

**The linear-sampling Gaussian trick** (Daniel Rákos, "Efficient Gaussian blur with linear sampling", RasterGrid blog, 2010). Two adjacent discrete taps at integer offsets k and k+1 with weights w₁ and w₂ equal **one** bilinear fetch at

  offset = (k·w₁ + (k+1)·w₂) / (w₁ + w₂),  weight = w₁ + w₂.

This is exact in real arithmetic because bilinear interpolation between texels k and k+1 at fraction t returns (1−t)·I(k) + t·I(k+1), and t = w₂/(w₁+w₂) reproduces the ratio w₁ : w₂. A symmetric kernel of radius r (2r+1 taps) needs only 1 + 2⌈r/2⌉ fetches. Rákos' 9-tap binomial example becomes 5 fetches with offsets 0, 1.3846153846, 3.2307692308 and weights 0.2270270270, 0.3162162162, 0.0702702703 (from binomial coefficients with the outer ones dropped, total 4070). He reports linear sampling "about 60% faster" than discrete sampling on a Radeon HD 5770 (2010 hardware). Two caveats the app should show:

1. **Weight quantization.** The hardware computes the fractional weight t with limited sub-texel precision, which Apple does not publish. MEASURED with the `probe_bilinear` harness kernel (a 2-texel texture holding 0 and 1, sampled at 65,536 positions): on the M1 Max and in the Simulator the result takes **257 distinct values**, i.e. **8 bits** of sub-texel precision, for `rgba32Float`, `rgba16Float` and `rgba8Unorm` alike; the largest deviation from the exact t is 1.95 × 10⁻³ = 1/512. So each merged pair carries a weight error of up to 1/512 of the pair's weight. In the full σ = 8 blur this raised the RMS error against the exact CPU result from 2.3 × 10⁻⁶ (discrete taps) to 9.5 × 10⁻⁵, while the maximum error stayed at one fp16 output ulp (4.9 × 10⁻⁴) (MEASURED, §6.3). Invisible in 8-bit output, but visible in an error heat map. The A17 Pro value is UNVERIFIED until the app runs the probe.
2. **Edges are handled for free.** The sampler applies the address mode to each of the 2 × 2 texel coordinates before weighting, so a merged fetch at the border equals the two separate taps under the same mode (clamp-to-edge, clamp-to-zero or mirror). COMPUTED from the sampling definition and consistent with the measured clamp-to-edge match.

The same idea in 2-D: four taps forming a 2 × 2 block with separable weights merge into one fetch. Dual-Kawase downsampling (§3.6) uses this: each of its 5 fetches averages 4 source texels.

Two more texture features matter for blurs:

- `gather()` returns one channel of the 2 × 2 footprint (4 values) in one instruction. Useful for median and min/max filters, which cannot use filtering.
- **Mip levels and `level()` / `bias()`**: sampling a mip level is a free box-ish prefilter; a trilinear sample (`mip_filter::linear`) blends two levels. "Blur by mip level" is the naive method in Bjørge's comparison (§3.6) and shows blocky, unstable output when the image moves by sub-pixel amounts.

### 2.4 Half precision

REFERENCE, WWDC 2020 session 10632 "Optimize Metal Performance for Apple silicon Macs": "Apple GPUs are optimized for 16-bit data types"; "in most cases, 16-bit data types use faster arithmetic instructions than the equivalent 32-bit data types"; type conversions are "typically free, even between single precision and half precision floating point values". Use `half`, and suffix literals with `h`, because the MSL rule is that an expression is evaluated at the highest precision among its operands.

How much faster is not published. Community microbenchmarks (metal-benchmarks) report FP16 FMA at twice the FP32 rate on the A14 and at the same rate on the M1 and A15 (UNVERIFIED; no A17 Pro data). The more durable benefit is **register footprint**: a `half4` occupies half the registers of a `float4`, which matters more on Apple9, where registers are allocated dynamically from L1 and occupancy follows live register use (Tech Talk 111374).

Precision facts (COMPUTED, IEEE 754 binary16): 11-bit significand, so the spacing of representable values in [1, 2) is 2⁻¹⁰ ≈ 9.8 × 10⁻⁴, in [0.5, 1) it is 4.9 × 10⁻⁴; largest finite value 65,504. An 8-bit display step is 1/255 ≈ 3.9 × 10⁻³, so `half` storage is about 8× finer than 8-bit output in [0.5, 1). Storage in half is safe; **accumulation in half is not**: a sum of N terms rounds at each step, and once the partial sum exceeds 1 each addition can lose up to 2⁻¹¹ relative. §3.8 and §6.3 quantify this per algorithm. Rule for every Blur2ool kernel: `half` for texture storage and fetched values, `float` for accumulators, running sums and SAT entries.

### 2.5 Memory bandwidth on A17 Pro / iPhone 15 Pro Max

- **Memory.** iPhone 15 Pro and Pro Max have 8 GB of LPDDR5 (Wikipedia "Apple A17", citing 9to5Mac, 15 Sep 2023). Apple does not publish the memory speed or bus width. Third-party chip databases (Geektopia, AskGeek) list **LPDDR5-6400** on a **64-bit** interface, which gives a theoretical peak of 6400 MT/s × 8 B = **51.2 GB/s** (COMPUTED from REFERENCE inputs that Apple has not confirmed: UNVERIFIED). Where the figure comes from: Applesfera (10 August 2023, "iPhone 15 Pro: filtrados muchos detalles de su chip A17 Bionic y nuevo tipo de RAM") reported a pre-launch leak by the X user @URedditor ("Unknownz21") of "LPDDR5, 6400 Mbps, 51.2 GB/s" made by Micron/Samsung. The same leak gave 6 GB of RAM, and that part turned out wrong: Xcode files and later reports showed 8 GB. I found no teardown or Apple source that confirms the speed, so this document treats 51.2 GB/s as a **leak-derived ceiling**, not a specification. For comparison, the A19 Pro is listed with LPDDR5X-9600 and 76.8 GB/s, and the M1 Max on this Mac has 400 GB/s (Apple).
- **The GPU does not get all of it.** The same DRAM serves the CPU, the display engine, the camera/ISP and the Neural Engine. Display scan-out alone at 2796 × 1290 × 4 B × 120 Hz is about 1.73 GB/s (COMPUTED; less if the display path compresses, UNVERIFIED). Sustained GPU streaming on mobile SoCs is typically well below the theoretical peak; I found no measured A17 Pro figure. **The app should measure it** with a blit copy and a trivial compute copy of a large texture (bytes moved ÷ GPU time), label it MEASURED, and use that number, not 51.2 GB/s, in its cost model.
- **System-level cache.** Wikipedia lists a 24 MB last-level (system-level) cache for the A17 Pro without a citation (UNVERIFIED). If true, a full-screen `RGBA8` image (2796 × 1290 × 4 B = 14.4 MB) can stay in the SLC between passes, while an `RGBA16Float` one (28.9 MB) cannot. Small blurs may therefore run faster than a DRAM-bandwidth model predicts, and a 16-bit pipeline can show a step change in cost that an 8-bit one does not (MODELED; the app can test it by sweeping image size).

### 2.6 Lossless compression

REFERENCE, Apple article "Optimizing texture data" and Tech Talk 10876 ("Discover advances in Metal for A15 Bionic"):

- "The A12 Bionic first introduced lossless texture compression in 2018, and the A14 Bionic added further improvements to the feature in 2020." It "saves memory bandwidth, which in turn saves power". It cannot guarantee any ratio, so it "must allocate enough memory to cover the full uncompressed texture size" (and slightly more for metadata).
- On Apple5 and later, Metal **attempts** lossless compression when the format is not block-compressed, the texture is not backed by an `MTLBuffer`, and its **usage does not include `.shaderWrite`**, `.pixelFormatView` or `.unknown`. Private textures and render targets are optimized for GPU access by default.
- **Lossy** compression (A15 / Apple8+, `MTLTextureDescriptor.compressionType = .lossy`) halves the memory footprint with the same bandwidth savings, but only for private textures, and "you cannot populate a lossy texture with shader write operations".

Consequence for blur design (INFERRED from the conditions above; Apple does not say whether Apple7+ relaxes the `.shaderWrite` rule, UNVERIFIED): **a blur written by a compute kernel with `texture.write()` needs `.shaderWrite` usage and so loses lossless compression on its intermediate textures, while a blur written by a fragment shader into a render target keeps it.** Blurred images are smooth and should compress well, so on Apple GPUs the fragment-shader ping-pong (§3.1) can move fewer bytes than a compute version of the same math, even though the compute version looks leaner on paper. MEASURED on the M1 Max (Apple7): the identical two-pass fragment Gaussian ran 1.3–1.5× faster when its textures lacked `.shaderWrite` usage (§6.3). That the speed-up comes from compression is INFERRED (the only difference is the usage flag); it does suggest the `.shaderWrite` rule still applies on Apple7. The app should repeat the A/B on the A17 Pro.

**Update: Apple has since confirmed the rule for all GPUs before Apple10, and says Apple10 lifts it.** Tech Talk 111431, "Boost your graphics performance with the M5 and A19 GPUs" (2026; it covers "the A19, A19 Pro and M5 family of chips", Apple family 10), says that "Apple GPUs have supported lossless block based texture compression… However, compression was disabled for textures with MTLTextureUsageShaderWrite." It then says that on M5 "compression now works with MTLTextureUsageShaderWrite", because new hardware tracks reads and writes for coherence. Apple calls this **"universal texture compression"** (the Feature Set Tables list it under Apple10) and says it "works by default on M5"; to opt a texture out, set `allowGPUOptimizedContents` to false. REFERENCE. Consequences:

- On the **A17 Pro (Apple9)**, compute-written textures are **not** losslessly compressed. The fragment-versus-compute bandwidth gap described above applies to his phone (REFERENCE for the rule; the size of the gap is still to be MEASURED on the phone).
- On **Apple10** devices (A19 family, M5) the gap should mostly disappear. The compression A/B in §5 is therefore a generational story the app can tell: "on this phone, writing from a compute shader costs you compression; on A19 it does not". The A19 half is REFERENCE only, because his phone cannot measure it.

### 2.7 Simulator limits

MEASURED (table in 2.2): the iOS 27.0 Simulator exposes a translated GPU named "Apple iOS simulator GPU" that reports only the **Apple2** family, **16 KB** threadgroup memory, **512** threads per threadgroup, **no read-write textures** (tier 0), no 32-bit float filtering, and **no stage-boundary counter sampling** (it reports draw/dispatch/blit boundaries but exposes no counter sets at all, so there is nothing to sample). Apple's article "Developing Metal apps that run in Simulator" describes the Simulator GPU as a translation layer over the Mac GPU with Apple2-family capabilities (REFERENCE).

Consequences for Blur2ool:

1. Every kernel must pick threadgroup sizes from `pipeline.maxTotalThreadsPerThreadgroup`, never a constant 1024 (every pipeline in the harness reported 512 in the Simulator, 1024 on the Mac). An earlier draft of the SAT row-scan sketch hard-coded 1024 threads in its chunk arithmetic and would have scanned only half of each row in the Simulator. The final sketch reads `[[threads_per_threadgroup]]` and `[[threads_per_simdgroup]]`, and the harness dispatches it with 512 threads there; it then matched the CPU reference exactly as on the Mac (MEASURED).
2. **The Simulator ran kernels that its reported family does not cover.** `sat_scan_rows` uses SIMD-scoped reductions (Apple7+ in the Feature Set Tables) and `sat_scan_cols_serial` uses an `access::read_write` texture (the device reports read-write tier 0), yet both built and produced results identical to the M1 Max (MEASURED, iOS 27.0 Simulator 24A5355p on macOS 27.2). The Simulator evidently forwards to the Mac GPU. Do not rely on this: Apple documents the Simulator as Apple2-class, so keep a fallback (two-texture ping-pong instead of read-write, and a threadgroup-memory scan instead of SIMD reductions) behind a `supportsFamily(.apple7)` check, and test the fallback on the Mac by forcing it.
3. The 16 KB threadgroup limit is not enforced in the Simulator either: kernels with 24 KB and 32 KB of static threadgroup memory built and ran to completion without error (`tgprobe.swift`, MEASURED). So the Simulator cannot catch a tile that is too large for the limit it reports. Size tiles from `maxThreadgroupMemoryLength` anyway, and test the limit logic with a unit test rather than by running in the Simulator.
4. **Simulator GPU timings are meaningless**, not just unrepresentative: an 8192 × 8192 `rgba16Float` blit copy (1.07 GB moved) reported 0.055 ms, and every timed kernel reported 0.03–0.16 ms regardless of work (MEASURED). The app must hide timings in the Simulator, or show them struck through with "Simulator: no GPU timing".
5. All numerical results (errors, measured σ, bilinear precision, MPS behaviour) were identical in the Simulator and on the M1 Max, so the Simulator is fine for checking **correctness** of the GPU path in UI tests.
6. Other Simulator rules from Apple's article that touch a blur app (REFERENCE): no programmable blending (no reading color attachments in a fragment function); "Don't write to sRGB textures in Simulator" (so keep render targets linear `rgba16Float` and convert for display); constant-buffer offsets aligned to 256 bytes and constant buffers no larger than 64 KB; and "You can't use Xcode to analyze the memory footprint or measure performance when running in Simulator". Apple's own advice is to use the Simulator for behaviour and a device for the rendering design.
7. **Mip-level readback from shared textures is wrong in the Simulator** (MEASURED in the final re-run, §6.3): `getBytes(…mipmapLevel: 1)` on a `.shared` texture returned the level-0 texels. Blitting from a private texture into a buffer gave the correct levels. Do every mip readback with a blit.

## 3. Implementation patterns in Metal

All measurements in this section come from the harness in §6.3 (`$TMPDIR/blur2ool-gpu-pipeline/parity.swift`), run on the M1 Max (macOS 27.2) and inside the iOS 27.0 Simulator. They are MEASURED on those GPUs, not on the A17 Pro. Image size for timings is the iPhone 15 Pro Max screen, 2796 × 1290 (3.607 MP), `rgba16Float` (28.86 MB per full image).

### 3.1 Fragment separable blur with ping-pong textures

Shape: two render passes per blur, each drawing one full-screen triangle (`fullscreen_vs`). Pass 1 samples the source with horizontal offsets and writes an intermediate texture; pass 2 samples the intermediate with vertical offsets and writes the output. Iterated blurs alternate ("ping-pong") between two textures. Load action `dontCare` (every pixel is overwritten), store action `store`.

- **Fetches per output pixel per pass:** 2r + 1 discrete taps, or 1 + 2⌈r/2⌉ with the linear-sampling trick (§2.3). For σ = 8, r = 24: 49 taps become 25 fetches.
- **DRAM traffic per pass (ideal):** one read and one write of the image, because neighbouring fragments share texels through the texture cache.
- **Why it suits Apple GPUs:** the textures need only `.shaderRead` and `.renderTarget` usage, so they stay eligible for lossless compression (§2.6). MEASURED on the M1 Max: the same two passes took **0.67 ms** with compressible textures and **1.02 ms** when the textures also carried `.shaderWrite` (minimum of 6 runs; 0.78 vs 1.03 ms at the median), so about 1.3–1.5× slower. A plain blit copy showed the same effect in some runs (0.082 vs 0.167 ms) and only 1.1× in others (§6.3).
- **Limitation:** a fragment cannot share fetched texels with its neighbours explicitly; reuse depends on the texture cache, which is small on mobile GPUs (Bjørge 2015 notes that wide kernels "will quickly start thrashing the cache").

### 3.2 Compute separable blur with threadgroup tile + apron

Shape (sketch `gauss_tile_h` / `gauss_tile_v`): one threadgroup handles TG consecutive pixels on one row (or column). It cooperatively loads the TG pixels plus an **apron** of r pixels on each side into threadgroup memory, waits at a barrier, then each thread convolves from threadgroup memory.

| Quantity | Formula | TG = 256, r = 24 | TG = 256, r = 64 |
|---|---|---|---|
| Texels loaded per threadgroup | TG + 2r | 304 | 384 |
| Texture reads per output pixel | 1 + 2r/TG | 1.19 | 1.50 |
| Threadgroup-memory reads per output pixel | 2r + 1 | 49 | 129 |
| Threadgroup memory (`half4`) | (TG + 2r) × 8 B | 2,432 B (allocated 3,072 B for MAX_R = 64) | 3,072 B |

COMPUTED; `staticThreadgroupMemoryLength` of the compiled pipeline is 3,072 B (MEASURED on Mac and Simulator).

The **apron grows linearly with r for a 1-D tile** but quadratically for a 2-D tile: a T × T tile needs (T + 2r)² texels, so the load overhead factor is (1 + 2r/T)². For T = 16 and r = 16 that is 9 loads per output pixel and 18 KB of `half4`, which does not fit the Simulator's 16 KB (§2.2). This is why tiled blurs are separable (1-D tiles) or switch to downsampling algorithms at large radii.

MEASURED on the M1 Max (H + V, 2796 × 1290, minimum of 6 runs): σ = 8 (r = 24) **0.92 ms**; σ = 21 (r = 63) **2.23 ms**. Time grows with r, so at these sizes the kernel is limited by arithmetic and threadgroup-memory reads, not by DRAM (the effective DRAM rate was 125 and 52 GB/s against 340 GB/s available). The compute version was **slower than the compressible fragment version** (0.92 vs 0.67 ms at σ = 8), partly because its outputs need `.shaderWrite` (§2.6, INFERRED). Per-encoder counters put the H and V passes at 0.457 and 0.470 ms, so column passes over a texture cost the same as row passes here; textures use a GPU-private tiled layout, so there is no row-major penalty (INFERRED from `allowGPUOptimizedContents`; the layout itself is not documented).

### 3.3 Sliding-window running sum (one thread per row)

Shape (sketch `box_running_rows`): one thread walks a whole row, keeping a running sum. Each step adds the texel entering the window and subtracts the texel leaving it: 2 reads, 1 write, 2 adds per pixel, **independent of r**. Two passes (rows, then columns) give a box blur; three box blurs in sequence approximate a Gaussian (Wells 1986, "Efficient synthesis of Gaussian filters by cascaded uniform filters", IEEE PAMI; see `stack-semantics.md` §1.2 for the σ formula).

- **Parallelism is the problem.** There are only H threads (1,290 for a portrait screen read row-wise). On the M1 Max it took **0.96 ms** for rows alone at r = 32 (minimum of 6 runs), slower than the whole two-pass compressible Gaussian at σ = 8. The fix is to split each row into S segments, with each segment re-seeding its window by summing 2r + 1 texels; that gives H × S threads at an extra (2r + 1)/segment-length reads per pixel (COMPUTED).
- **Precision is the second problem** (§3.8): a running sum adds and subtracts thousands of times, so rounding errors random-walk. With a `float` accumulator the 4096-pixel row stayed at the output rounding level (2.4 × 10⁻⁴); with a `half` accumulator the error reached **2.4 × 10⁻²**, about six 8-bit steps (MEASURED).

### 3.4 Summed-area table via parallel prefix scan

A summed-area table (SAT; Crow 1984, "Summed-area tables for texture mapping", SIGGRAPH) stores S(x, y) = Σ I(i, j) over i ≤ x, j ≤ y. Any axis-aligned box sum then costs **4 reads**, whatever the radius: S(x₁, y₁) − S(x₀, y₁) − S(x₁, y₀) + S(x₀, y₀). Building it is a prefix sum along rows, then along columns.

- **Parallel scan.** Blelloch's work-efficient scan (Blelloch 1990, "Prefix Sums and Their Applications", CMU-CS-90-190) does an up-sweep (reduce) and a down-sweep in O(n) work and O(log n) depth; Harris, Sengupta and Owens, "Parallel Prefix Sum (Scan) with CUDA" (GPU Gems 3, ch. 39, 2007) is the standard GPU treatment. Hensley et al. 2005 ("Fast Summed-Area Table Generation and its Applications", Computer Graphics Forum 24(3)) built SATs in fragment shaders by recursive doubling. On Apple GPUs the 32-lane `simd_prefix_exclusive_sum` does the inner scan directly, so the sketch `sat_scan_rows` is a **reduce-then-scan**: each thread reduces a contiguous chunk serially, SIMD-groups scan the chunk totals, one SIMD-group scans the SIMD-group totals, and each thread re-walks its chunk writing inclusive sums. The column scan in the sketch is the simplest correct one: one thread per column, serial; adjacent threads read adjacent texels of the same row, so loads are coherent.
- **Cost** (MEASURED, M1 Max, 2796 × 1290, RGBA fp32 table, minimum of 6 runs): row scan 0.55 ms, column scan 0.65 ms, box lookup 0.31 ms, total **1.54 ms**. The table itself is 57.7 MB (16 B per pixel), double the image.
- **Precision is the real limit.** A fp32 table accumulates values up to W·H·mean. For a 4096 × 4096 image with values uniform in [0, 1) the far corner is about 8.4 × 10⁶ ≈ 2²³, where the fp32 spacing is 1.0, so the four-corner difference loses most of its significant bits. MEASURED (GPU fp32 SAT, box r = 2, area 25): maximum error **2.6 × 10⁻⁴** in the top-left 256² block, **3.4 × 10⁻²** in the centre and **7.5 × 10⁻²** in the bottom-right (about 19 8-bit steps). The corner entry was 8,386,077 against an exact 8,386,073.2. A CPU fp32 emulation in the same scan order gave the same errors.
- **Mitigations:** (1) **subtract the mean** (or 0.5) before scanning, so entries stay small and signed: the same fp32 emulation dropped to **3.5 × 10⁻⁵** at the bottom-right (COMPUTED). Atanasov et al. 2018 attribute this offset idea to Hensley et al. 2005 and note it "is usually insufficient for higher-resolution images" (I did not read the 2005 paper's text: UNVERIFIED detail). (2) **Integer SAT** for 8-bit input: `uint32` entries with wrap-around arithmetic give exact box sums as long as 255 × box area < 2³² (COMPUTED; true for any box up to 16.8 M pixels). (3) Tile-local tables. (4) fp64 is not an option: Metal GPU code has no `double`.
- **Apple's version:** `MPSImageIntegral` (iOS 9+) computes the same table; its header recommends a 32-bit float destination for normalized or half inputs and a 32-bit integer destination for integer inputs.

### 3.5 Mipmaps via blit `generateMipmaps`

`MTLBlitCommandEncoder.generateMipmaps(for:)` fills every mip level from level 0. The texture needs `mipmapLevelCount > 1` and a color-renderable, color-filterable format. Apple's documentation says "The image filtering that GPU drivers use to generate the mipmaps may vary by the feature families" it supports, so the filter is not specified. MEASURED on the M1 Max (Apple7): an impulse of 1.0 becomes exactly one texel of 0.25 at level 1 and 0.0625 at level 2, so the filter there is a **2 × 2 box** per level. The app should run the same impulse probe on the phone and show the result as MEASURED.

A mip chain is the cheapest wide blur: sampling level L is a 2ᴸ × 2ᴸ box average, and `mip_filter::linear` blends two levels for a continuous radius. It is also the worst-looking: Bjørge's comparison shows the naive mip method is blocky and unstable when the image moves by sub-pixel amounts. Apple's own QuartzCore ships `variable_blur_copy_base_mip_compute` and `variable_blur_downsample_compute`, which suggests its variable (progressive) blur samples a mip pyramid with a per-pixel level (INFERRED from names).

### 3.6 Kawase and dual-Kawase (dual filter)

- **Kawase blur** (Masaki Kawase, "Frame Buffer Postprocessing Effects in DOUBLE-S.T.E.A.L (Wreckless)", GDC 2003): each pass takes 4 bilinear samples at the diagonal corners, at a distance that grows with each pass, ping-ponging between two textures of the same size, usually at reduced resolution. Bjørge describes it as "sampling four corners at increasing distance from the current pixel".
- **Dual filter** (Marius Bjørge, ARM, "Bandwidth-Efficient Rendering", in the SIGGRAPH 2015 course "Moving Mobile Graphics"; speaker notes PDF on community.arm.com). It replaces same-size ping-pong with a **downsample chain and an upsample chain**: down = 5 fetches (centre × 4 plus 4 diagonal half-pixel taps, ÷ 8), up = 8 fetches (4 axis taps at 2 half-pixels, 4 diagonal taps × 2, ÷ 12). The sketch's sample patterns and weights match the GLSL in the notes exactly. The notes do not define `halfpixel`; KWin's implementation uses 0.5 / (size of the render target being drawn), and the sketch follows KWin.
- Bjørge's results (1080p, 97 × 97-equivalent blur, Mali-T760 MP8): dual filter fastest, Kawase close; dual filter needed 7% of the bandwidth of the linear-sampling Gaussian and less than half of Kawase's; quality (PSNR against a true Gaussian) slightly below Kawase but "very minor".
- **MEASURED effective σ** of the sketch's chain (impulse response, second moment, M1 Max; the Simulator gave identical numbers): offset 1: L = 1 → **1.29 px**, L = 2 → **2.89**, L = 3 → **5.92**, L = 4 → **11.90**; at L = 3, offset 2 → 9.53 and offset 3 → 13.23. σ roughly doubles per level, and the offset gives continuous control between levels. Mass stays 1.000 (± 0.0003). The chain matches a CPU emulation with exact bilinear weights to 9.8 × 10⁻⁴ (2 fp16 ulps after 6 rounded passes).
- **Cost:** L = 4 (8 passes, σ ≈ 12) took **0.44 ms** at 2796 × 1290 on the M1 Max (minimum of 6 runs), against 0.67–1.02 ms for a true separable Gaussian at σ = 8. Modeled traffic for L levels is about 2 × 1.25 × (1 + 1/4 + 1/16 + …) ≈ 3.3 image-sizes of reads plus writes, almost independent of σ (COMPUTED).

### 3.7 Metal Performance Shaders kernels

The iOS 27.0 SDK's `MPSImage` headers declare these blur-relevant kernels: `MPSImageGaussianBlur` (σ), `MPSImageBox`, `MPSImageTent` (two boxes), `MPSImageConvolution` (any kernel), `MPSImageAreaMax`/`AreaMin`, `MPSImageDilate`/`Erode`, `MPSImageMedian`, `MPSImageIntegral` and `MPSImageIntegralOfSquares` (SATs), `MPSImageGaussianPyramid`, `MPSImageLaplacianPyramid`, `MPSImageGuidedFilter`, `MPSImageBilinearScale`, `MPSImageLanczosScale`, `MPSImageSobel`, `MPSImageLaplacian`. `MPSImageMedian.maxKernelDiameter()` returned **127** on both the M1 Max and the Simulator (MEASURED).

MEASURED behaviour of `MPSImageGaussianBlur` (M1 Max; the Simulator was identical):

| σ requested | σ measured (impulse) | mass | support on centre row |
|---|---|---|---|
| 2 | 2.010 | 0.9993 | ±6 px |
| 8 | 7.942 | 0.9972 | ±28 px |
| 32 | 31.80 | 0.9944 | ±117 px |

Against an exact Gaussian at σ = 8 (edge clamp) the maximum error was **2.4 × 10⁻³** (0.6 of an 8-bit step). The header itself says it is "Mathematically… an approximate gaussian" (`sdk-feasibility.md` §9). Time at 2796 × 1290 (minimum of 6 runs): **0.28 ms** at σ = 8 and **0.21 ms** at σ = 32, so cost does not grow with σ (a downsampling or recursive scheme, INFERRED), and it is 2–3× faster than the teaching sketches. In the app, MPS is a useful "vendor reference" lane, but it is a black box at this layer: no source, no dispatch geometry, no per-pass timeline.

### 3.8 fp16 vs fp32 accumulation error

MEASURED with harness kernels that differ only in accumulator type (M1 Max; Simulator identical). Errors are maximum absolute differences from a double-precision CPU reference, on values in [0, 1]. The output itself is stored as `half`, so 2.4 × 10⁻⁴ (half an ulp in [0.5, 1)) is the floor.

| Kernel | `float` accumulator | `half` accumulator |
|---|---|---|
| Gaussian H, σ = 2 (13 taps) | 2.4 × 10⁻⁴ | 1.2 × 10⁻³ |
| Gaussian H, σ = 8 (49 taps) | 2.4 × 10⁻⁴ | 2.1 × 10⁻³ |
| Gaussian H, σ = 21 (127 taps) | 2.4 × 10⁻⁴ | 3.9 × 10⁻³ (one 8-bit step) |
| Running-sum box, 4096-px rows, r = 8 | 2.4 × 10⁻⁴ | 2.35 × 10⁻² |
| Running-sum box, 4096-px rows, r = 32 | 2.5 × 10⁻⁴ | 2.4 × 10⁻² |
| SAT box (fp32 table), 4096², far corner | 7.5 × 10⁻² | n/a |

Why (COMPUTED): a Gaussian sum stays below 1, so each `half` addition rounds by at most 2⁻¹² to 2⁻¹¹ and the error grows with the number of taps. A running sum holds 2r + 1 values (about 8.5 for r = 8), where the `half` spacing is 2⁻⁷ ≈ 0.0078; each of the 4,096 steps adds a rounding error of that size, and the errors random-walk (√4096 = 64 steps' worth), giving a few × 10⁻² after normalization. The SAT case is the same effect in fp32 at a larger magnitude. Rule for Blur2ool: **`half` for storage and fetched values, `float` for every accumulator, running sum and table, and mean-centred or integer SATs.**

## 4. Cost models and measurement

### 4.1 Per-pass byte, fetch and ALU counts

Notation: N = W·H pixels, B = bytes per pixel of the image format (4 for `rgba8Unorm`, 8 for `rgba16Float`, 16 for `rgba32Float`), r = kernel radius in pixels, n = samples for gather kernels. "DRAM bytes" assumes an ideal cache: every texel comes from memory once per pass, and neighbours share it. All entries COMPUTED (MODELED where they depend on that cache assumption).

| Algorithm | Passes | Fetches / px (total) | DRAM bytes / px (ideal cache) | FMAs / px (RGBA, ×4 lanes) | Depends on r? |
|---|---|---|---|---|---|
| Direct 2-D convolution | 1 | (2r+1)² | 2B | 4(2r+1)² | quadratic |
| Separable, discrete taps | 2 | 2(2r+1) | 4B | 8(2r+1) | linear |
| Separable, linear-sampled | 2 | 2(1 + 2⌈r/2⌉) | 4B | ≈ 4(2r+1) + filtering in the texture unit | linear, half the fetches |
| Separable, compute tile (TG wide) | 2 | 2(1 + 2r/TG) texture + 2(2r+1) threadgroup | 4B | 8(2r+1) | linear (ALU) |
| Running-sum box | 2 | 6 (2 reads + seed) | 4B | 16 | none (plus seed cost per segment) |
| Box via SAT (RGBA fp32 table) | 3 | 1 + 2 + 4 | ≈ 2B + 16 + 32 + 32 ≈ 96 B at B = 8 | ~16 | none |
| Dual-Kawase, L levels | 2L | 5 per down-pixel, 8 per up-pixel | ≈ 3.3B (sum over the pyramid) | ~13 per level-pixel | σ set by L and offset |
| Mip chain + 1 lookup | 1 blit + 1 | 1 (or 2 trilinear) | ≈ 1.33B + 2B | ~4 | none |
| Radial / bokeh gather | 1 | n | 2B ideal, up to nB if the cache misses | 4n (+ weight math) | n, and footprint area |

How to read it: separable and box methods are **bandwidth-shaped** (bytes per pixel do not change with r) but their ALU and fetch counts grow with r until they become **fetch- or ALU-bound**; downsampling methods (dual-Kawase, mips, MPS) cut both; gathers are **fetch-bound** with a cache hit rate that falls as the footprint grows.

### 4.2 Bandwidth-bound estimates on A17 Pro

Inputs: a full-screen image on the iPhone 15 Pro Max is 2796 × 1290 = 3,606,840 px, 28.86 MB in `rgba16Float` and 14.43 MB in `rgba8Unorm` (COMPUTED). Peak DRAM bandwidth **51.2 GB/s**, from third-party LPDDR5-6400 × 64-bit figures (UNVERIFIED, §2.5). A frame at 120 Hz lasts 8.33 ms; it must also hold everything else the app and the render server draw.

| Algorithm (full screen, `rgba16Float`) | Modeled DRAM bytes | Floor at 51.2 GB/s | Floor at 70% of peak (assumed) |
|---|---|---|---|
| One read + one write (copy) | 57.7 MB | 1.13 ms | 1.61 ms |
| Separable Gaussian or running-sum box (2 passes) | 115.4 MB | 2.25 ms | 3.22 ms |
| Same, `rgba8Unorm` storage | 57.7 MB | 1.13 ms | 1.61 ms |
| Dual-Kawase, L = 4 | 95.8 MB | 1.87 ms | 2.67 ms |
| SAT box, RGBA fp32 table | ≈ 346 MB | 6.8 ms | 9.7 ms |
| SAT box, single-channel fp32 table | ≈ 130 MB | 2.5 ms | 3.6 ms |

All MODELED. Two corrections pull in opposite directions. **Lossless compression** and the **system-level cache** (24 MB if the uncited figure is right; a 14.4 MB `rgba8` frame would fit) can make real traffic lower than the model (on the M1 Max a compressible 28.9 MB blit copy reached an "effective" 704 GB/s in its best run, above the 400 GB/s DRAM peak). **Fetch and ALU limits** can make time higher than the floor.

For fetch- and ALU-bound kernels, a rough scale factor from the M1 Max measurements: the M1 Max GPU has 32 cores with 128 FP32 ALUs each (4,096; Apple quotes 10.4 TFLOPS), and the A17 Pro has 6 cores (768 ALUs per the Wikipedia comparison table). Assuming similar clocks (A17 Pro GPU clock UNVERIFIED) and ignoring Apple9's new shader core, an A17 Pro needs roughly **5×** the M1 Max time. MODELED A17 Pro estimates, full screen, `rgba16Float`, to be replaced by MEASURED numbers from the app:

| Kernel | M1 Max MEASURED (min of 6 runs) | A17 Pro MODELED (max of 5× compute, bandwidth floor at 70%) |
|---|---|---|
| Linear-sampled Gaussian σ = 8, compressible textures | 0.67 ms | ≈ 3.4 ms |
| Compute-tile Gaussian σ = 8 | 0.92 ms | ≈ 4.6 ms |
| Compute-tile Gaussian σ = 21 | 2.23 ms | ≈ 11 ms |
| Dual-Kawase L = 4 (σ ≈ 12) | 0.44 ms | ≈ 2.7 ms (bandwidth floor) |
| `MPSImageGaussianBlur` σ = 8 | 0.28 ms | ≈ 1.6 ms (bandwidth floor) |
| SAT box (RGBA fp32) | 1.54 ms | ≈ 9.7 ms (bandwidth floor) |
| Golden-angle bokeh, 64 samples, r = 24 px | 2.96 ms | ≈ 15 ms |

Design consequences (MODELED, to be confirmed on the phone): a full-resolution, live, 120 Hz preview fits only the cheap methods (dual-Kawase, MPS, small-σ separable). Wide separable Gaussians, SATs and bokeh gathers should run at half resolution while a slider is moving, then at full resolution when it stops, and the UI should say which resolution it is showing.

### 4.3 Measuring: command buffer timestamps, counter sample buffers, Metal System Trace

**1. `MTLCommandBuffer.gpuStartTime` / `gpuEndTime`** (seconds, host time base). Coarse but always available on device. Protocol the app should use: one command buffer per measured algorithm; 3 warm-up runs (the first run includes pipeline and cache warm-up: in the harness the first counter-sampled run of the H pass took 1.58 ms, the warmed run 0.46 ms); then 15–30 runs; report the **median** and the spread; record `ProcessInfo.thermalState` and Low Power Mode with each result, because a hot phone throttles. The time includes gaps between encoders.

**2. `MTLCounterSampleBuffer` with the `timestamp` counter set.** Sampling points (REFERENCE, `MTLCounterSamplingPoint` docs): `atStageBoundary` ("at the start and end of a render pass's vertex and fragment stages, and at the start and end of compute and blit passes"), `atDrawBoundary`, `atDispatchBoundary`, `atTileDispatchBoundary`, `atBlitBoundary`. Apple's Tech Talk 10001 ("Optimize Metal apps and games with GPU counters", 2020) says to check stage-boundary support for TBDR GPUs and draw-boundary support for immediate-mode GPUs. MEASURED: the M1 Max supports **only `atStageBoundary`** (draw, dispatch, tile-dispatch and blit boundaries all false), with one counter set, `timestamp`. The A17 Pro is expected to behave the same (INFERRED, both are TBDR Apple GPUs; the app should log `supportsCounterSampling` for each point). Consequences:

- Timestamps are **per encoder**, not per dispatch or draw. To time each blur pass separately, give each pass its own compute or render encoder and attach the sample buffer through `MTLComputePassDescriptor.sampleBufferAttachments` (start/end of encoder) or `MTLRenderPassDescriptor.sampleBufferAttachments` (start/end of the vertex stage and of the fragment stage).
- Read results with `resolveCounterRange(_:)` as `MTLCounterResultTimestamp`; skip entries equal to `MTLCounterErrorValue`. Convert GPU ticks to time with two `device.sampleTimestamps()` calls (Swift returns `(cpu, gpu)`) bracketing the work. On the M1 Max the CPU and GPU deltas were identical (7,448,917 each), so GPU ticks were nanoseconds there; the app should compute the ratio at runtime rather than assume it.
- Limits (Feature Set Tables): counter sample buffers up to 32 KB each, at most 32 per device.

MEASURED example (M1 Max, warmed, 2796 × 1290): Gaussian H encoder 0.457 ms, V encoder 0.470 ms, then a render pass whose vertex stage took 0.011 ms and fragment stage 0.477 ms. The render pass's **vertex stage was timestamped before the two compute passes started**, and its fragment stage started 33 µs after the V pass ended. This matches Apple's TBDR description ("While the GPU runs the final stages of a render pass to tile memory, it can start the vertex stage of a future render pass") and is exactly the kind of overlap a pass timeline should show. The command buffer's `gpuEndTime − gpuStartTime` (2.55 ms) was longer than the sum of the passes (1.42 ms); the roughly 1 ms gap before the first compute pass is unexplained (UNVERIFIED cause; possibly GPU power-state ramp after an idle wait).

**2b. Metal 4 counter heaps (iOS 26+, Apple7+; the A17 Pro qualifies).** The Feature Set Tables list "Performance counter heaps" as a Metal 4 feature from Apple7, with at most 32 heaps per process. The iOS 27.0 SDK headers (`MTL4Counters.h`, `MTL4ComputeCommandEncoder.h`, `MTL4RenderCommandEncoder.h`, `MTLDevice.h`) define this API (REFERENCE):

- `MTL4CounterHeap` of type `.timestamp`, created with `device.makeCounterHeap(descriptor:)` and read with `resolveCounterRange(_:)`. Each entry is a `UInt64` (`MTL4TimestampHeapEntry`).
- `MTL4ComputeCommandEncoder.writeTimestamp(granularity:counterHeap:index:)`, and on render encoders the same call with an extra `afterStage:` argument. Timestamps can be written **anywhere in an encoder**, not only at its boundaries.
- `MTL4TimestampGranularity.relaxed` is "minimally-invasive", and the header warns that it "may group all timestamps for a pass together". `.precise` is "as precise as possible" but "may cause splitting of command encoders".
- `device.queryTimestampFrequency()` returns the timestamp rate in ticks per second.

MEASURED on the M1 Max (`m4probe.swift`). The probe ran one Metal 4 compute encoder containing a timestamp, dispatch A (2,000 dependent FMAs per thread × 2²⁰ threads), a barrier, a timestamp, dispatch B (4,000 FMAs) and a final timestamp, four times at each granularity:

- `queryTimestampFrequency()` = **24,000,000 ticks/s**. Heap timestamps run on a 24 MHz clock (41.7 ns per tick). The classic counter sample buffer counts in nanoseconds on the same machine (above), so the conversion must be looked up at runtime, never assumed.
- **`.relaxed`**: in all four runs the timestamps before and after dispatch B were **identical**, and the first interval swung between 0.06 and 10.7 ms. Relaxed timestamps inside one encoder carry no per-dispatch information.
- **`.precise`**: all three timestamps were distinct. Dispatch A measured 3.39–3.48 ms and B 7.61–7.84 ms (B/A ≈ 2.2–2.3 in three runs, 4.05 in one noisy run), consistent with B doing twice the work. **Per-dispatch GPU timing inside a single encoder works on an Apple GPU through Metal 4.** It was impossible with the stage-boundary-only `MTLCounterSampleBuffer`.
- The host was heavily loaded (load average about 430), so absolute times are only indicative. I did not measure the overhead of `.precise` encoder splitting.
- **Not available in the Simulator at all.** The iOS 27.0 *Simulator* SDK's `MTLDevice.h` (1,121 lines, against 1,450 in the device SDK) omits `MTLGPUFamilyMetal4`, `makeMTL4CommandQueue`, `makeCommandAllocator` and `queryTimestampFrequency`, so the probe did not even compile for the Simulator target. Blur2ool must put its Metal 4 timing path behind `#if !targetEnvironment(simulator)` and keep the classic path (one encoder per pass + `gpuStartTime`/`gpuEndTime`) as the fallback.

Recommendation for the pass timeline in §5: on the phone, use a Metal 4 counter heap with `.precise` timestamps between passes, and label the bars MEASURED. Show the classic per-encoder counters as a cross-check. That the A17 Pro behaves like the M1 Max here is INFERRED (both are Metal 4 Apple GPUs), and the app should confirm it.

**3. Simulator.** It reports draw, dispatch and blit sampling points as supported but **exposes no counter sets**, so nothing can be sampled. Its command-buffer GPU times are not GPU execution times at all: an 8192 × 8192 `rgba16Float` blit copy (1.07 GB moved) "took" 0.055 ms, an impossible 19.5 TB/s (MEASURED). The app must hide or flag every timing taken in the Simulator.

**4. Tools outside the app.** Instruments' **Metal System Trace** shows the per-encoder GPU timeline with vertex/fragment/compute channels and can be aligned with `os_signpost` intervals emitted by the app. Xcode's GPU frame capture (or `MTLCaptureManager` from code, writing a `.gputrace`) gives per-pipeline costs; on Apple9 GPUs Xcode adds shader cost graphs, performance heat maps and occupancy/L1/last-level-cache counters (Tech Talk 111374). None of this is visible inside the app, but the app can emit signposts named after each pass so a capture lines up with what the screen shows.

## 5. What Blur2ool can show at the GPU layer

Everything below is buildable with public API on iOS 27. Each view says which honesty label its numbers carry.

1. **The kernel source.** Ship each blur's `.metal` source as a text resource, compile it at runtime with `makeLibrary(source:options:)`, and show the same string on screen with syntax colouring. What the user reads is then provably what runs. Tapping a line could explain it ("cooperative load of the apron", "barrier", "bilinear pair"). The GPU↔CPU parity CLI on the Mac loads the same files (§6.3). Label: REFERENCE (it is the code).
2. **Dispatch geometry over the image.** Overlay the grid on the picture: threadgroups as rectangles (256 × 1 strips for the H pass, 1 × 256 columns for the V pass, 16 × 16 tiles for gathers), each SIMD-group as a 32-thread band in a second colour, and the **apron** of a tile shaded to show the extra loads. Numbers beside it: threadgroups, threads, SIMD-groups, `staticThreadgroupMemoryLength`, apron overhead 2r/TG. Sources: COMPUTED from parameters; `threadExecutionWidth`, `maxTotalThreadsPerThreadgroup` and `staticThreadgroupMemoryLength` read from the pipeline (MEASURED).
3. **One pixel's footprint.** Pick an output pixel and draw what it reads: the 2r + 1 discrete taps; the bilinear pair positions sitting between texels with their merged weights; the dual-Kawase cascade (5 taps on each down level, 8 on each up level, drawn on the pyramid); the 4 SAT corners; the radial line; the golden-angle spiral. Counter: fetches per pixel (COMPUTED). This is the GPU-layer stop of the "follow one pixel" guide in the brief.
4. **Pass timeline.** One bar per pass, from Metal 4 counter-heap timestamps with `.precise` granularity. These resolve individual dispatches inside one encoder (§4.3, item 2b). Per-encoder `MTLCounterSampleBuffer` timestamps, with vertex and fragment stages split for render passes, serve as the fallback and the cross-check. Gaps are shown (MEASURED on device). Beside each bar, a ghost bar from the cost model (MODELED). The overlap in §4.3 (a render pass's vertex stage running before earlier compute passes) is a good first thing to see.
5. **Bytes and roofline.** Per pass: modeled bytes moved, measured time, effective GB/s. A roofline plot with two ceilings measured on the device by microbenchmarks: copy bandwidth (blit and compute copy of a large noise texture) and ALU throughput (an FMA loop kernel). Each blur appears as a point. Labels: MODELED bytes, MEASURED times and ceilings.
6. **Precision panel.** GPU result vs the `BlurCore` CPU reference on a crop (LIVE), with the max and RMS error; toggles for `half` vs `float` accumulators; an SAT error heat map that grows toward the bottom-right corner, and a "mean-centre" toggle that removes it (§3.4, §3.8).
7. **Device card.** GPU family, `maxThreadgroupMemoryLength`, `maxThreadsPerThreadgroup`, `threadExecutionWidth`, read-write texture tier, 32-bit float filtering, counter sampling points, **bilinear sub-texel bits** (from the `probe_bilinear` kernel), the `generateMipmaps` impulse response, and measured copy bandwidth. All MEASURED on the phone, with the Feature Set Tables value alongside as REFERENCE.
8. **Compression A/B.** Run the same fragment blur with intermediates created with and without `.shaderWrite` usage and show both times (MEASURED; on the M1 Max the difference was 1.3–1.5×).
9. **Tile view.** A 32 × 32 tile grid over the image and the kernel footprint of the selected pixel: once the footprint leaves the tile, the blur cannot stay in tile memory and needs an offscreen pass. This is the visual answer to "why do blurs cost so much on a phone" (§1.2, §2.1).
10. **The system's own blur (INFERRED lane).** The five-pass diagram from WWDC 2014, the list of QuartzCore kernel names with the OS build they were read from, the measured σ of SwiftUI `.blur` from `ImageRenderer`, and a stress test that stacks `Material` layers over a scrolling field and counts missed frames with `CADisplayLink`.

## 6. Metal Shading Language sketches (compiler-verified)

### 6.1 Compiler result

All seven sketches live in one file, reproduced in full in 6.2 (scratch copy: `$TMPDIR/blur2ool-gpu-pipeline/sketches.metal`, 346 lines). Toolchain: Xcode 27.0 (27A5194q), Metal Toolchain cryptex v27.1.5194.15, `Apple metal version 32023.917 (metalfe-32023.917)`, host macOS 27.2 on an Apple M1 Max. Re-run on 13 October 2026 after the two fixes noted below.

| Command | Result |
|---|---|
| `xcrun -sdk iphoneos metal -c sketches.metal -o /dev/null` | exit 0, no diagnostics |
| `xcrun -sdk iphonesimulator metal -c sketches.metal -o /dev/null` | exit 0, no diagnostics |
| same with `-Wall -Wextra` (both SDKs) | exit 0, no warnings |
| `-std=metal3.1`, `-std=metal3.2`, `-std=metal4.0` (iphoneos) | exit 0 |
| `metal -c` then `metallib` | 61,071-byte `.metallib` |
| `harness.metal` (probe kernels for §6.3) | exit 0 |

**Final re-run (13 October 2026, 23:24, after a host reboot purged `$TMPDIR`).** The code block in §6.2 was extracted from this document with `awk` into a fresh `$TMPDIR/blur2ool-gpu-pipeline/sketches.metal` (346 lines) and compiled again with the same toolchain: `iphoneos` and `iphonesimulator`, each plain and with `-Wall -Wextra`, and `iphoneos` with `-std=metal3.1`, `metal3.2` and `metal4.0`, all exit 0 with no diagnostics; `metal -c` + `metallib` again produced a 61,071-byte library. So the source printed below is exactly the source that was compiled.

Changes from the first draft: (1) `sat_scan_rows` now derives its chunk size from `[[threads_per_threadgroup]]` and its last lane from `[[threads_per_simdgroup]]`, so it is correct at the Simulator's 512-thread limit (the first draft assumed 1024 and would have skipped half of each row there); (2) the dual-Kawase comment now states the KWin `halfTexel` convention. Compiling proves syntax and types; §6.3 checks the results.

### 6.2 Source (all sketches)

Index: (1) separable Gaussian compute with threadgroup tile (`gauss_tile_h`, `gauss_tile_v`); (2) linear-sampled Gaussian fragment shader (`gauss_linear_fs`); (3) dual-Kawase down/up (`dual_kawase_down_fs`, `dual_kawase_up_fs`); (4) SAT box (`sat_scan_rows`, `sat_scan_cols_serial`, `sat_box`); (5) sliding-window running-sum box (`box_running_rows`); (6) radial zoom/spin gather (`radial_blur`); (7) golden-angle bokeh gather (`bokeh_golden`). The fragment passes share `fullscreen_vs`.

Dispatch summary (as used by the harness): `gauss_tile_h` threadgroups (⌈W/256⌉, H) × (256, 1); `gauss_tile_v` (W, ⌈H/256⌉) × (1, 256); `sat_scan_rows` threadgroups (H, 1) × (T, 1) with T = min(1024, maxTotalThreadsPerThreadgroup) rounded down to a multiple of 32; `sat_scan_cols_serial` and `box_running_rows` one thread per column/row; `sat_box`, `radial_blur`, `bokeh_golden` `dispatchThreads(W, H)` with 16 × 16 threadgroups; fragment passes draw 3 vertices into a render target of the output size.

```metal
// Blur2ool GPU-layer sketches. Teaching code: correct and compilable, not tuned.
// Conventions: textures are RGBA (premultiplied if they carry alpha), edges clamp,
// weights are normalized on the CPU, accumulation is fp32 even when storage is fp16.
#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Shared: full-screen triangle for the fragment-shader passes
// ---------------------------------------------------------------------------
struct FSOut {
    float4 position [[position]];
    float2 uv;
};

vertex FSOut fullscreen_vs(uint vid [[vertex_id]]) {
    // vid 0,1,2 -> (0,0) (2,0) (0,2): one triangle that covers the viewport.
    float2 p = float2(float((vid << 1) & 2u), float(vid & 2u));
    FSOut o;
    o.position = float4(p * 2.0f - 1.0f, 0.0f, 1.0f);
    o.uv = float2(p.x, 1.0f - p.y);            // Metal NDC is y-up, texture space is y-down
    return o;
}

// ---------------------------------------------------------------------------
// 1. Separable Gaussian, compute, threadgroup tile + apron
//    One threadgroup = TG consecutive pixels on one line (row or column).
//    It loads TG + 2r texels into threadgroup memory once, then every thread
//    convolves from that cache. Dispatch with dispatchThreadgroups so every
//    threadgroup is full: grid = (ceil(W/TG), H) for H, (W, ceil(H/TG)) for V,
//    threadsPerThreadgroup = (TG,1) for H and (1,TG) for V.
// ---------------------------------------------------------------------------
constant int TG    = 256;   // threads per threadgroup along the blur axis
constant int MAX_R = 64;    // largest radius the tile holds; apron = 2*MAX_R texels

inline void gauss_line(texture2d<half, access::read>  src,
                       texture2d<half, access::write> dst,
                       constant float *w,             // w[0..r], w[0] is the centre tap
                       int r, bool vertical,
                       uint2 gid, int lid, int groupStart,
                       threadgroup half4 *tile)
{
    const int W = int(src.get_width()), H = int(src.get_height());
    const int lineLen = vertical ? H : W;
    const int across  = vertical ? int(gid.x) : int(gid.y);
    const int span    = TG + 2 * r;

    // Cooperative load: each thread fetches ceil(span/TG) texels (1 + 2r/TG).
    for (int i = lid; i < span; i += TG) {
        int a = clamp(groupStart - r + i, 0, lineLen - 1);       // clamp-to-edge
        uint2 p = vertical ? uint2(across, a) : uint2(a, across);
        tile[i] = src.read(p);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (gid.x >= uint(W) || gid.y >= uint(H)) return;           // after the barrier
    float4 acc = float4(tile[lid + r]) * w[0];
    for (int k = 1; k <= r; ++k) {
        acc += (float4(tile[lid + r - k]) + float4(tile[lid + r + k])) * w[k];
    }
    dst.write(half4(acc), gid);
}

kernel void gauss_tile_h(texture2d<half, access::read>  src [[texture(0)]],
                         texture2d<half, access::write> dst [[texture(1)]],
                         constant float *w       [[buffer(0)]],
                         constant uint  &radius  [[buffer(1)]],
                         uint2 gid  [[thread_position_in_grid]],
                         uint2 tid  [[thread_position_in_threadgroup]],
                         uint2 tgid [[threadgroup_position_in_grid]])
{
    threadgroup half4 tile[TG + 2 * MAX_R];                     // (256+128)*8 B = 3 KB
    gauss_line(src, dst, w, min(int(radius), MAX_R), false,
               gid, int(tid.x), int(tgid.x) * TG, tile);
}

kernel void gauss_tile_v(texture2d<half, access::read>  src [[texture(0)]],
                         texture2d<half, access::write> dst [[texture(1)]],
                         constant float *w       [[buffer(0)]],
                         constant uint  &radius  [[buffer(1)]],
                         uint2 gid  [[thread_position_in_grid]],
                         uint2 tid  [[thread_position_in_threadgroup]],
                         uint2 tgid [[threadgroup_position_in_grid]])
{
    threadgroup half4 tile[TG + 2 * MAX_R];
    gauss_line(src, dst, w, min(int(radius), MAX_R), true,
               gid, int(tid.y), int(tgid.y) * TG, tile);
}

// ---------------------------------------------------------------------------
// 2. Linear-sampled Gaussian, fragment shader (one axis per pass, ping-pong)
//    Pairs of discrete taps (k, k+1) with weights (a, b) become ONE bilinear
//    fetch at offset (k*a + (k+1)*b)/(a+b) with weight a+b. CPU prepares
//    offsets[] in texels (offsets[0] = 0) and weights[]; count = 1 + ceil(r/2).
// ---------------------------------------------------------------------------
struct LinearBlurParams {
    float2 texelStep;      // (1/W, 0) for the horizontal pass, (0, 1/H) for vertical
    uint   count;          // number of entries in offsets[] / weights[]
};

fragment half4 gauss_linear_fs(FSOut in [[stage_in]],
                               texture2d<half> src [[texture(0)]],
                               constant float *offsets [[buffer(0)]],
                               constant float *weights [[buffer(1)]],
                               constant LinearBlurParams &p [[buffer(2)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge, coord::normalized);
    float4 acc = float4(src.sample(s, in.uv)) * weights[0];
    for (uint i = 1; i < p.count; ++i) {
        float2 d = p.texelStep * offsets[i];
        acc += (float4(src.sample(s, in.uv + d)) + float4(src.sample(s, in.uv - d))) * weights[i];
    }
    return half4(acc);
}

// ---------------------------------------------------------------------------
// 3. Dual-Kawase ("dual filter", Bjorge, SIGGRAPH 2015): down chain then up chain.
//    halfTexel = 0.5 / size of the render target this pass WRITES (the KWin
//    convention; the original notes leave it unstated). Down: 5 fetches, output
//    is half size. Up: 8 fetches, output is double size.
// ---------------------------------------------------------------------------
struct DualParams {
    float2 halfTexel;
    float  offset;         // spread, typically 1.0 .. 4.0
};

fragment half4 dual_kawase_down_fs(FSOut in [[stage_in]],
                                   texture2d<half> src [[texture(0)]],
                                   constant DualParams &p [[buffer(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 o = p.halfTexel * p.offset;
    float4 sum = float4(src.sample(s, in.uv)) * 4.0f;
    sum += float4(src.sample(s, in.uv - o));
    sum += float4(src.sample(s, in.uv + o));
    sum += float4(src.sample(s, in.uv + float2(o.x, -o.y)));
    sum += float4(src.sample(s, in.uv - float2(o.x, -o.y)));
    return half4(sum / 8.0f);
}

fragment half4 dual_kawase_up_fs(FSOut in [[stage_in]],
                                 texture2d<half> src [[texture(0)]],
                                 constant DualParams &p [[buffer(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 o = p.halfTexel * p.offset;
    float4 sum = float4(src.sample(s, in.uv + float2(-2.0f * o.x, 0.0f)));
    sum += float4(src.sample(s, in.uv + float2(-o.x,  o.y))) * 2.0f;
    sum += float4(src.sample(s, in.uv + float2( 0.0f, 2.0f * o.y)));
    sum += float4(src.sample(s, in.uv + float2( o.x,  o.y))) * 2.0f;
    sum += float4(src.sample(s, in.uv + float2( 2.0f * o.x, 0.0f)));
    sum += float4(src.sample(s, in.uv + float2( o.x, -o.y))) * 2.0f;
    sum += float4(src.sample(s, in.uv + float2( 0.0f, -2.0f * o.y)));
    sum += float4(src.sample(s, in.uv + float2(-o.x, -o.y))) * 2.0f;
    return half4(sum / 12.0f);
}

// ---------------------------------------------------------------------------
// 4. Box blur from a summed-area table (SAT)
//    4a. Row scan: one threadgroup per row, reduce-then-scan with SIMD prefix
//        sums (the hardware-friendly form of Blelloch's up-sweep/down-sweep).
//    4b. Column scan: same kernel run on the transposed problem, or the serial
//        one-thread-per-column kernel below.
//    4c. Box lookup: 4 SAT reads per pixel regardless of radius.
//    The SAT is float4 here; see the precision notes (fp32 runs out of mantissa
//    on large images; uint32 with wrap-around is exact for 8-bit input).
// ---------------------------------------------------------------------------
// Dispatch: threadgroups = (H, 1, 1), threadsPerThreadgroup = (T, 1, 1) with T a
// multiple of the SIMD width and T <= pipeline.maxTotalThreadsPerThreadgroup
// (1024 on device, 512 in the Simulator). Needs SIMD-scoped reductions (Apple7+).
kernel void sat_scan_rows(texture2d<float, access::read>  src [[texture(0)]],
                          texture2d<float, access::write> sat [[texture(1)]],
                          uint  row   [[threadgroup_position_in_grid]],
                          uint  lid   [[thread_index_in_threadgroup]],
                          uint  ntg   [[threads_per_threadgroup]],
                          uint  lane  [[thread_index_in_simdgroup]],
                          uint  simdW [[threads_per_simdgroup]],
                          uint  sg    [[simdgroup_index_in_threadgroup]],
                          uint  nsg   [[simdgroups_per_threadgroup]])
{
    threadgroup float4 sgTotals[32];                  // up to 32 SIMD-groups (1024 threads)
    const uint W = src.get_width();
    const uint chunk = (W + ntg - 1) / ntg;           // texels per thread
    const uint x0 = lid * chunk;

    // (1) each thread reduces its own contiguous chunk
    float4 local = 0.0f;
    for (uint i = 0; i < chunk; ++i) {
        uint x = x0 + i;
        if (x < W) local += src.read(uint2(x, row));
    }
    // (2) exclusive scan of the chunk totals across the threadgroup
    float4 sgPrefix = simd_prefix_exclusive_sum(local);
    if (lane == simdW - 1) sgTotals[sg] = sgPrefix + local;   // last lane holds the SIMD total
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (sg == 0) {
        float4 t = (lane < nsg) ? sgTotals[lane] : float4(0.0f);
        sgTotals[lane] = simd_prefix_exclusive_sum(t);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    float4 running = sgTotals[sg] + sgPrefix;
    // (3) re-walk the chunk writing inclusive sums
    for (uint i = 0; i < chunk; ++i) {
        uint x = x0 + i;
        if (x < W) {
            running += src.read(uint2(x, row));
            sat.write(running, uint2(x, row));
        }
    }
}

// Serial column scan: one thread per column, a running sum down the column.
kernel void sat_scan_cols_serial(texture2d<float, access::read_write> sat [[texture(0)]],
                                 uint col [[thread_position_in_grid]])
{
    const uint W = sat.get_width(), H = sat.get_height();
    if (col >= W) return;
    float4 running = 0.0f;
    for (uint y = 0; y < H; ++y) {
        running += sat.read(uint2(col, y));
        sat.write(running, uint2(col, y));
    }
}

inline float4 sat_at(texture2d<float, access::read> sat, int x, int y) {
    if (x < 0 || y < 0) return 0.0f;                 // S(-1, .) = S(., -1) = 0
    return sat.read(uint2(x, y));
}

kernel void sat_box(texture2d<float, access::read>  sat [[texture(0)]],
                    texture2d<half,  access::write> dst [[texture(1)]],
                    constant uint &radius [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]])
{
    const int W = int(sat.get_width()), H = int(sat.get_height());
    if (int(gid.x) >= W || int(gid.y) >= H) return;
    const int r = int(radius);
    // Shrink the box at the edges (renormalize by the true area).
    int x0 = max(int(gid.x) - r, 0) - 1, x1 = min(int(gid.x) + r, W - 1);
    int y0 = max(int(gid.y) - r, 0) - 1, y1 = min(int(gid.y) + r, H - 1);
    float4 s = sat_at(sat, x1, y1) - sat_at(sat, x0, y1)
             - sat_at(sat, x1, y0) + sat_at(sat, x0, y0);
    float area = float((x1 - x0) * (y1 - y0));
    dst.write(half4(s / area), gid);
}

// ---------------------------------------------------------------------------
// 5. Sliding-window box, one thread per row: O(1) work per pixel for any r.
//    Each step adds the texel entering the window and subtracts the one leaving.
//    fp32 running sums drift on long rows; re-seed periodically if that matters.
// ---------------------------------------------------------------------------
kernel void box_running_rows(texture2d<half, access::read>  src [[texture(0)]],
                             texture2d<half, access::write> dst [[texture(1)]],
                             constant uint &radius [[buffer(0)]],
                             uint row [[thread_position_in_grid]])
{
    const int W = int(src.get_width());
    if (row >= src.get_height()) return;
    const int r = int(radius);
    const float inv = 1.0f / float(2 * r + 1);
    float4 sum = 0.0f;
    for (int k = -r; k <= r; ++k) sum += float4(src.read(uint2(clamp(k, 0, W - 1), row)));
    for (int x = 0; x < W; ++x) {
        dst.write(half4(sum * inv), uint2(x, row));
        int enter = clamp(x + r + 1, 0, W - 1);
        int leave = clamp(x - r, 0, W - 1);
        sum += float4(src.read(uint2(enter, row))) - float4(src.read(uint2(leave, row)));
    }
}

// ---------------------------------------------------------------------------
// 6. Radial blurs (gather): zoom toward a centre, or spin around it.
// ---------------------------------------------------------------------------
struct RadialParams {
    float2 center;         // normalized uv
    float  strength;       // zoom: fraction of the distance to the centre; spin: radians
    uint   samples;        // 8 .. 64
    uint   mode;           // 0 = zoom, 1 = spin
};

kernel void radial_blur(texture2d<half, access::sample> src [[texture(0)]],
                        texture2d<half, access::write>  dst [[texture(1)]],
                        constant RadialParams &p [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    const float2 size = float2(dst.get_width(), dst.get_height());
    const float2 uv = (float2(gid) + 0.5f) / size;
    const float aspect = size.x / size.y;
    float2 d = uv - p.center;
    d.x *= aspect;                                   // work in square units
    const uint n = max(p.samples, 2u);
    float4 acc = 0.0f;
    for (uint i = 0; i < n; ++i) {
        float t = float(i) / float(n - 1) - 0.5f;   // centred: -0.5 .. +0.5
        float2 q;
        if (p.mode == 0) {
            q = d * (1.0f - p.strength * t);
        } else {
            float a = p.strength * t, c = cos(a), sn = sin(a);
            q = float2(c * d.x - sn * d.y, sn * d.x + c * d.y);
        }
        q.x /= aspect;
        acc += float4(src.sample(s, p.center + q, level(0)));
    }
    dst.write(half4(acc / float(n)), gid);
}

// ---------------------------------------------------------------------------
// 7. Golden-angle (Vogel spiral) bokeh gather: a disc PSF sampled with N
//    well-spread taps. Optional highlight weighting makes bright points bloom
//    into discs the way a lens does. A gather cannot model occlusion; real DoF
//    also needs per-pixel circle-of-confusion from depth.
// ---------------------------------------------------------------------------
struct BokehParams {
    float radiusPx;        // disc radius in pixels
    uint  samples;         // 16 .. 256
    float highlightGain;   // 0 = plain disc average
    float highlightPower;  // e.g. 4
};

kernel void bokeh_golden(texture2d<half, access::sample> src [[texture(0)]],
                         texture2d<half, access::write>  dst [[texture(1)]],
                         constant BokehParams &p [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    const float2 invSize = 1.0f / float2(src.get_width(), src.get_height());
    const float2 uv = (float2(gid) + 0.5f) * invSize;
    const float GOLDEN = 2.39996323f;                // pi * (3 - sqrt(5))
    const uint n = max(p.samples, 1u);
    float4 acc = 0.0f;
    float wsum = 0.0f;
    for (uint i = 0; i < n; ++i) {
        float r = sqrt((float(i) + 0.5f) / float(n)) * p.radiusPx;   // equal-area rings
        float theta = float(i) * GOLDEN;
        float2 o = float2(cos(theta), sin(theta)) * r;
        float4 c = float4(src.sample(s, uv + o * invSize, level(0)));
        float luma = dot(c.rgb, float3(0.2126f, 0.7152f, 0.0722f));
        float w = 1.0f + p.highlightGain * pow(max(luma, 0.0f), p.highlightPower);
        acc += c * w;
        wsum += w;
    }
    dst.write(half4(acc / wsum), gid);
}
```

### 6.3 GPU-vs-CPU check on the Mac

Harness: `$TMPDIR/blur2ool-gpu-pipeline/parity.swift` (Swift CLI, `swiftc -O -swift-version 5`) plus `harness.metal` (probe kernels: `probe_bilinear`, `gauss_h_halfacc`, `box_running_rows_halfacc`, `copy_tex`). It compiles `sketches.metal` at runtime with `makeLibrary(source:)`, the same route the brief proposes for the parity CLI, runs each kernel on a 512 × 384 procedural image (zone plate in R, step edge in G, checkerboard in B, a grid of white impulses), and compares against double-precision CPU references written independently in Swift (clamp-to-edge, the same weights, exact bilinear interpolation where the kernel samples). The same binary, rebuilt with `-target arm64-apple-ios27.0-simulator`, ran inside the iOS 27.0 Simulator via `xcrun simctl spawn` on the simulator "Blur2ool gpu-pipeline" (shut down afterwards). Logs: `run1.log`, `run2.log`, `run3.log`, `sim1.log` in the same folder.

Correctness (MEASURED; M1 Max and Simulator gave **identical** numbers). One fp16 ulp in [0.5, 1) is 4.9 × 10⁻⁴; output textures are `rgba16Float`, so that is the floor for any kernel.

| Kernel | Reference | Max abs error | RMS error | Verdict |
|---|---|---|---|---|
| `gauss_tile_h` + `gauss_tile_v`, σ = 8, r = 24 | separable Gaussian, intermediate rounded to fp16 | 4.9 × 10⁻⁴ | 2.3 × 10⁻⁶ | matches to output rounding |
| `gauss_linear_fs` × 2 passes, σ = 8 (13 fetch positions per side incl. centre, 25 fetches/pass) | same | 4.9 × 10⁻⁴ | 9.5 × 10⁻⁵ | matches; RMS shows the 8-bit bilinear weights |
| dual-Kawase, 3 down + 3 up, offset 1 | CPU emulation with exact bilinear, fp16 rounding per pass | 9.8 × 10⁻⁴ | 2.7 × 10⁻⁴ | matches to 2 ulps after 6 passes |
| `sat_scan_rows` + `sat_scan_cols_serial` + `sat_box`, r = 8 | box with shrinking edge window | 4.9 × 10⁻⁴ | 7.0 × 10⁻⁵ | matches (small image; see §3.4 for 4096²) |
| `box_running_rows`, r = 8 | 1-D box, clamp-to-edge | 4.9 × 10⁻⁴ | 3.0 × 10⁻⁶ | matches |
| `radial_blur` zoom 0.2, 32 samples | CPU gather with exact bilinear | 7.3 × 10⁻⁴ | 1.1 × 10⁻⁴ | matches (fast-math trig + 8-bit weights) |
| `radial_blur` spin 0.3 rad, 32 samples | same | 7.3 × 10⁻⁴ | 1.1 × 10⁻⁴ | matches |
| `bokeh_golden` r = 12 px, 64 samples, highlight gain 4, power 4 | same | 4.9 × 10⁻⁴ | 1.0 × 10⁻⁴ | matches |
| `MPSImageGaussianBlur` σ = 8, clamp | exact Gaussian (r = 40) | 2.4 × 10⁻³ | 6.9 × 10⁻⁴ | approximate, as its header says |

Probes (MEASURED, M1 Max; Simulator identical where it applies):

- **Bilinear sub-texel precision:** 257 distinct outputs, 8 bits, max |error| 1/512, for `rgba32Float`, `rgba16Float`, `rgba8Unorm` (the Simulator has no 32-bit float filtering, so only the last two there).
- **Dual-Kawase effective σ:** 1.29 / 2.89 / 5.92 / 11.90 px for L = 1–4 at offset 1; 9.53 and 13.23 px at L = 3 with offsets 2 and 3.
- **`MPSImageGaussianBlur` effective σ:** 2.010, 7.942, 31.80 for 2, 8, 32; mass 0.9993, 0.9972, 0.9944.
- **`generateMipmaps`:** 2 × 2 box per level on the M1 Max (impulse 1.0 → 0.25 → 0.0625).
- **fp16 accumulation, SAT precision:** tables in §3.8 and §3.4.
- **Per-pipeline limits:** every compute pipeline reported `threadExecutionWidth` 32 and `maxTotalThreadsPerThreadgroup` 1024 (Mac) or 512 (Simulator); `gauss_tile_*` use 3,072 B of static threadgroup memory and `sat_scan_rows` 512 B.
- **Threadgroup limit enforcement** (`tgprobe.swift`): the Simulator built and ran 24 KB and 32 KB threadgroup kernels despite reporting 16 KB.
- **`RB_EXACT_BLUR`:** re-running the `sdk-feasibility` `ImageRenderer` PSF probe on macOS with `RB_EXACT_BLUR=1` produced a byte-identical table (σ = 7.270 at radius 8, same truncation). Either the variable is read differently, is ignored in release builds, or does not affect this path (UNVERIFIED which).

Timings (MEASURED on the **M1 Max**, 2796 × 1290 `rgba16Float`, private textures filled with image content; each run reports the median of 15 command buffers after 3 warm-ups, and the harness was run 6 times). **The host was heavily loaded by other parallel agents during these runs (load average 287–846)**, so individual runs varied by up to 2×; the minimum across runs is the best estimate of uncontended GPU time and the median shows the spread. These are Mac numbers, not phone numbers.

| Workload | Min of 6 runs | Median of 6 runs | Modeled bytes | Effective GB/s (at min) |
|---|---|---|---|---|
| Blit copy, texture with `.shaderWrite` usage | 0.167 ms | 0.170 ms | 57.7 MB | 346 |
| Blit copy, texture without `.shaderWrite` | 0.082 ms | 0.155 ms | 57.7 MB | 704 (above DRAM peak: compression and/or system cache) |
| Blit copy, cleared texture (`.shaderWrite`) | 0.160 ms | 0.173 ms | 57.7 MB | 361 |
| Blit copy, 5592 × 2580 noise (115 MB) | 0.654 ms | 0.678 ms | 231 MB | 353 |
| Blit copy, 8192 × 8192 noise (537 MB) | 2.97 ms | 3.11 ms | 1,074 MB | 362 (≈ 90% of the 400 GB/s spec) |
| Blit copy, 256 MiB buffer | 1.47 ms | 1.56 ms | 537 MB | 364 |
| Compute copy kernel (`.shaderWrite`) | 0.133 ms | 0.151 ms | 57.7 MB | 434 |
| `gauss_tile` H+V σ = 8 / σ = 21 | 0.92 / 2.23 ms | 1.23 / 2.24 ms | 115 MB | 125 / 52 |
| `gauss_linear_fs` H+V σ = 8 / σ = 21 (`.shaderWrite` textures) | 1.02 / 2.58 ms | 1.03–1.08 / 2.59 ms | 115 MB | 113 / 45 |
| `gauss_linear_fs` H+V σ = 8, compressible textures | 0.67 ms | 0.78 ms | 115 MB | 173 |
| Dual-Kawase L = 4 | 0.44 ms | 0.55 ms | 96 MB | 217 |
| SAT rows / cols / box r = 32 / total | 0.55 / 0.65 / 0.31 / 1.54 ms | 0.74 / 0.80 / 0.42 / 1.91 ms | 490 MB (model) | n/a |
| `box_running_rows` r = 32 (rows only) | 0.96 ms | 1.34 ms | 87 MB | 90 |
| `radial_blur` zoom, 32 samples | 1.08 ms | 1.28 ms | 58 MB | 53 |
| `bokeh_golden` r = 24 px, 64 samples | 2.96 ms | 2.97 ms | 58 MB | 19 |
| `MPSImageGaussianBlur` σ = 8 / σ = 32 | 0.28 / 0.21 ms | 0.29 / 0.23 ms | 58 MB | 206 / 277 |

Robust conclusions from these runs: the compressible-texture fragment blur beat the same blur with `.shaderWrite` textures in every run (1.3× at the median, 1.5× at the minimum); the blit-copy compression gap was bimodal (2× in some runs, 1.1× in others); large copies settle at about 350–365 GB/s, about 90% of the M1 Max's 400 GB/s; MPS and dual-Kawase are the cheapest wide blurs; gathers are the most expensive per pixel.

The Simulator's timings for the same table were all 0.03–0.16 ms, including the 1 GB copy, and are excluded (§2.7).

**Re-verification after the probe folder was lost.** The Mac rebooted at about 23:20 on 13 October 2026 and `$TMPDIR` was purged, taking `parity.swift`, `harness.metal`, `tgprobe.swift` and the `run*.log`/`sim1.log` files with it. The numbers above were recorded from those runs before the loss. To check that the most load-bearing ones still hold, I rebuilt a smaller probe, `verify.swift` + `probe.metal`, which compiles the §6.2 text at runtime with `makeLibrary(source:)` and checks it against a fresh double-precision CPU reference written for this probe (512 × 384 image: zone plate, step edge, checkerboard and impulses, clamp-to-edge, fp16 rounding of the intermediate). I ran it on the M1 Max and, through `simctl spawn`, in the iOS 27.0 Simulator on "Blur2ool gpu-pipeline", which I shut down afterwards. Logs: `verify-mac.log`, `verify-sim.log`, `verify-mac-mip.log`, `verify-sim-mip.log`. MEASURED, with the M1 Max and the Simulator giving identical numbers unless noted:

| Check | M1 Max | iOS 27.0 Simulator | Agrees with the earlier run? |
|---|---|---|---|
| `gauss_tile_h` + `gauss_tile_v`, σ = 8, r = 24, vs CPU | max 4.88 × 10⁻⁴, RMS 2.46 × 10⁻⁶ | identical | yes (the RMS differs slightly because the test image differs) |
| `gauss_linear_fs` × 2, σ = 8 (13 entries, 25 fetches per pass), vs CPU | max 4.88 × 10⁻⁴, RMS 9.0 × 10⁻⁵ | identical | yes |
| Bilinear sub-texel precision (`rgba32Float` / `rgba16Float` / `rgba8Unorm`) | 257 distinct values = 8 bits; max error 1.95 × 10⁻³ (2.08 × 10⁻³ for `rgba8Unorm`) | the same for the two formats it can filter; no 32-bit float filtering | yes |
| `generateMipmaps` impulse (private texture, blit readback) | level 1: one texel of 0.25; level 2: one texel of 0.0625 (2 × 2 box) | identical | yes |
| Counter sampling points | stage boundary only; counter set `timestamp` | draw, dispatch and blit reported, stage not; no counter sets | yes |
| Device limits | Apple7 family, 32,768 B threadgroup memory, 1024 threads, read-write tier 2 | Apple2 only, 16,384 B, 512 threads, read-write tier 0 | yes |
| `gauss_tile_h` pipeline | SIMD width 32, 1024 max threads, 3,072 B static threadgroup memory | SIMD width 32, 512 max threads, 3,072 B | yes |

The SAT, dual-Kawase, running-sum, radial, bokeh and MPS parity rows, the fp16-accumulation and SAT-precision tables, and all timings were **not** re-run after the loss. They stand as recorded. The parity CLI planned in §9 will reproduce them.

One new Simulator finding came out of the re-run (MEASURED). With a **`.shared`-storage** mipmapped texture, `getBytes(_:bytesPerRow:from:mipmapLevel:)` for level 1 returned the **level-0** texels in the Simulator: one texel of 1.0 at (4, 4), the impulse's level-0 position. Level 2 came back empty. The same code on the Mac returned the correct 2 × 2-box levels. With a **`.private`** texture read back through a blit copy, the Simulator's levels were correct. So `generateMipmaps` works in the Simulator, and the readback of a shared texture's mip level is what fails. Whether this is a bug or an undocumented limit is UNVERIFIED. Rule for Blur2ool: read back any mip level, in the Simulator and everywhere else, by blitting from a private texture into a buffer.

What this establishes: the seven sketches are correct to fp16 output precision on an Apple GPU and in the Simulator, the CPU-reference method in the brief works, and the harness can be the seed of the brief's Mac parity CLI. What it does not establish: anything about A17 Pro timing, A17 Pro bilinear precision or A17 Pro `generateMipmaps` behaviour. Those need the on-device run.

## 7. Sources

Apple documentation, talks and specifications (REFERENCE):

1. Tech Talk 10855, "Explore UI animation hitches and the render loop" (2020). https://developer.apple.com/videos/play/tech-talks/10855
2. Tech Talk 10857, "Demystify and eliminate hitches in the render phase" (2020). https://developer.apple.com/videos/play/tech-talks/10857
3. WWDC 2014 session 419, "Advanced Graphics and Animations for iOS Apps" (Michael Ingrassia, Axel Wefers). Read through the machine transcript at https://nonstrict.eu/wwdcindex/wwdc2014/419/ (transcript errors possible).
4. Metal Feature Set Tables, PDF dated 21 May 2026. https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf (sections "Metal GPUs", "Metal feature availability by GPU family", "GPU implementation limits by family", pixel-format capability tables and footnotes 1–10). Downloaded again and text-extracted with PDFKit on 13 October 2026 at 23:30 for the final check. These rows were re-confirmed word for word: A17 Pro = Apple9; threadgroup memory 16,352 B / 16 KB / 32 KB (Apple2 / Apple3 / Apple4–10); threads per threadgroup 512 / 512 / 1024; explicit imageblock 32 KB; implicit imageblock 128 KB (Apple4–8) and 256 KB (Apple9–10); tile 32 × 32 without MSAA; SIMD permute Apple6, SIMD reduction Apple7; lossy compression Apple8; counter sample buffer 32 KB, 32 sample buffers; performance counter heaps (Metal 4) Apple7, 32 per process; universal texture compression Apple10.
5. "Tailor your apps for Apple GPUs and tile-based deferred rendering". https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering
6. "Optimizing texture data" (lossless compression conditions). https://developer.apple.com/documentation/metal/optimizing-texture-data
7. Tech Talk 10876, "Discover advances in Metal for A15 Bionic" (2021; lossless and lossy compression, SIMD width). https://developer.apple.com/videos/play/tech-talks/10876
8. WWDC 2020 session 10632, "Optimize Metal Performance for Apple silicon Macs" (16-bit types, load/store actions, memoryless). https://developer.apple.com/videos/play/wwdc2020/10632/
9. Tech Talk 111374, "Discover new Metal profiling tools for M3 and A17 Pro" (2023; dynamic L1 allocation, occupancy manager). https://developer.apple.com/videos/play/tech-talks/111374
10. Tech Talk 10001, "Optimize Metal apps and games with GPU counters" (2020; stage vs draw boundary by GPU type). https://developer.apple.com/videos/play/tech-talks/10001/
10a. Tech Talk 111431, "Boost your graphics performance with the M5 and A19 GPUs" (2026; the `.shaderWrite` compression rule before Apple10, and universal texture compression on M5). https://developer.apple.com/videos/play/tech-talks/111431/
10b. iOS 27.0 SDK headers `MTL4Counters.h`, `MTL4ComputeCommandEncoder.h` and `MTL4RenderCommandEncoder.h` (`MTL4CounterHeap`, `writeTimestamp(granularity:…)`, `MTL4TimestampGranularity`), and `MTLDevice.h` (`queryTimestampFrequency`). Read from Xcode 27.0 (27A5194q); the Simulator SDK's `MTLDevice.h` lacks these entry points.
11. `MTLCounterSamplingPoint` reference. https://developer.apple.com/documentation/metal/mtlcountersamplingpoint
12. "Sampling GPU data into counter sample buffers". https://developer.apple.com/documentation/metal/sampling-gpu-data-into-counter-sample-buffers
13. `MTLBlitCommandEncoder.generateMipmaps(for:)`. https://developer.apple.com/documentation/metal/mtlblitcommandencoder/generatemipmaps(for:)
14. `CALayer.filters` ("This property is not supported on layers in iOS"). https://developer.apple.com/documentation/quartzcore/calayer/filters
15. `View.drawingGroup(opaque:colorMode:)`. https://developer.apple.com/documentation/swiftui/view/drawinggroup(opaque:colormode:)
16. "Developing Metal apps that run in Simulator". https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator
17. iOS 27.0 and macOS 27.0 SDK headers in Xcode 27.0 (27A5194q): `MPSImage` headers (`MPSImageConvolution.h`, `MPSImageIntegral.h`, `MPSImageMedian.h`), `Metal/MTLDevice.h` (`sampleTimestamps`), the Metal Swift overlay (`sampleTimestamps() -> (cpu:, gpu:)`).

Papers, talks and code (REFERENCE unless marked):

18. Daniel Rákos, "Efficient Gaussian blur with linear sampling", RasterGrid blog, 7 September 2010. https://www.rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/
19. Marius Bjørge (ARM), "Bandwidth-Efficient Rendering", SIGGRAPH 2015 course "Moving Mobile Graphics", speaker notes PDF (36 pages; read in full for §3.6). https://community.arm.com/cfs-file/__key/communityserver-blogs-components-weblogfiles/00-00-00-20-66/siggraph2015_2D00_mmg_2D00_marius_2D00_notes.pdf
20. KWin blur effect, `effects/blur/blur.cpp` and `blurshader.cpp` at commit 0179f741 (dual-Kawase `halfpixel` = 0.5 / render-target size). https://invent.kde.org/plasma/kwin/-/blob/0179f741bbd4cc01da5866fdf7b6a302869a099b/effects/blur/blurshader.cpp
21. Masaki Kawase, "Frame Buffer Postprocessing Effects in DOUBLE-S.T.E.A.L (Wreckless)", GDC 2003. Not fetched; cited as it is commonly cited (exact title UNVERIFIED).
22. Franklin C. Crow, "Summed-area tables for texture mapping", SIGGRAPH 1984.
23. Guy E. Blelloch, "Prefix Sums and Their Applications", Carnegie Mellon technical report CMU-CS-90-190, 1990.
24. Mark Harris, Shubhabrata Sengupta, John D. Owens, "Parallel Prefix Sum (Scan) with CUDA", GPU Gems 3, chapter 39, 2007.
25. Justin Hensley, Thorsten Scheuermann, Greg Coombe, Montek Singh, Anselmo Lastra, "Fast Summed-Area Table Generation and its Applications", Computer Graphics Forum 24(3), 547–555, 2005. https://diglib.eg.org/handle/10.2312/CGF.v24i3pp547-555 (abstract page only; full text not read).
26. Atanasov et al., "Adaptive Environment Sampling on CPU and GPU", supplemental material, 2018 (describes Hensley's offset and its limits). https://cgg.mff.cuni.cz/~jaroslav/papers/2018-adaptiveibl/2018-atanasov-adaptiveibl-supplemental.pdf
27. William M. Wells III, "Efficient synthesis of Gaussian filters by cascaded uniform filters", IEEE Transactions on Pattern Analysis and Machine Intelligence 8(2), 1986.
28. Helmut Vogel, "A better way to construct the sunflower head", Mathematical Biosciences 44, 1979 (golden-angle spiral used by `bokeh_golden`; not fetched).
29. Philip Turner, `metal-benchmarks` (community microbenchmarks of Apple GPUs; not Apple data). https://github.com/philipturner/metal-benchmarks
30. Wikipedia, "Apple A17" (8 GB LPDDR5, 6-core GPU, 768 ALUs, 24 MB SLC uncited). https://en.wikipedia.org/wiki/Apple_A17
31. Third-party chip databases listing A17 Pro LPDDR5-6400 and 51.2 GB/s: Geektopia (https://www.geektopia.es/es/product/apple/a17-pro/) and AskGeek (https://askgeek.io/pt/cpus/Apple/A17-Pro). Seen through search summaries; page bodies not readable by my fetch tool (UNVERIFIED).
31a. Applesfera, "iPhone 15 Pro: filtrados muchos detalles de su chip A17 Bionic y nuevo tipo de RAM", 10 August 2023 (pre-launch leak from @URedditor: LPDDR5, 6400 Mbps, 51.2 GB/s, 6 GB). https://www.applesfera.com/rumores/iphone-15-pro-filtrados-muchos-detalles-su-chip-a17-bionic-nuevo-tipo-ram
32. The Apple Wiki, "backboardd" (community; iOS 6-era description). https://theapplewiki.com/wiki/Dev:Backboardd

Local evidence gathered for this document (INFERRED or MEASURED as marked in the text):

33. iOS 26.5 Simulator runtime 23F73 (`/Library/Developer/CoreSimulator/Volumes/iOS_23F73/.../RuntimeRoot`): `System/Library/LaunchDaemons/com.apple.backboardd.plist` (Mach service `com.apple.CARenderServer`), `usr/libexec/backboardd` (`nm -u`), `QuartzCore.framework/QuartzCore` and `default.metallib`, `SwiftUICore.framework/SwiftUICore`, `PrivateFrameworks/RenderBox.framework` (strings). The iOS 27.0 runtime image was not mounted ("Cryptex Mount Preferred"), so these were not re-read from 27.0.
34. macOS 27.2: `/System/Library/Frameworks/QuartzCore.framework/Versions/A/Resources/default.metallib` (strings).
35. Probe code and logs: `$TMPDIR/blur2ool-gpu-pipeline/`, where `$TMPDIR` is `/var/folders/ww/m595r7m942g0h7w9c016dj6w0000gn/T/`. The original harness (`harness.metal`, `parity.swift`, `tgprobe.swift`, `tools/pdftext.swift`, `run*.log`, `sim1.log`, `timing_runs.txt`, `NOTES.txt`) was **lost** when the host rebooted on 13 October 2026 at about 23:20 and `$TMPDIR` was purged. The folder now holds the re-verification set: `sketches.metal` (extracted from §6.2), `sketches.metallib`, `probe.metal`, `verify.swift`, `verify-mac.log`, `verify-sim.log`, `verify-mac-mip.log` and `verify-sim-mip.log` (§6.3); `m4probe.swift` and `m4probe-mac.log` (Metal 4 counter heaps, §4.3); and `tools/pdftext.swift` with `fst/fst.pdf` and `fst/fst.txt` (the Feature Set Tables and their extracted text). Because `$TMPDIR` is not durable, the build should copy whatever it needs into the project.

## 8. UNVERIFIED list

Claims in this document that I could not verify, with what would settle them:

1. **A17 Pro memory: LPDDR5-6400, 64-bit, 51.2 GB/s peak.** The figure traces back to a pre-launch leak (Applesfera, 10 August 2023, citing @URedditor), and the same leak got the RAM capacity wrong. Third-party databases repeat it. Apple publishes none of it. To settle it, measure copy bandwidth on the phone.
2. **A17 Pro system-level cache of 24 MB.** Wikipedia, no citation.
3. **A17 Pro GPU clock**, and therefore the "≈ 5× the M1 Max time" scale factor in §4.2.
4. **The render server is `backboardd` on device.** Shown for the iOS 26.5 Simulator runtime only (launchd plist), not on a device image or iOS 27.
5. **SwiftUI's on-screen `.blur` uses the private `CAFilter` `gaussianBlur`.** Inferred from strings in `SwiftUICore`; not observed in a running layer tree.
6. **Apple's current blur pipeline is downsample → separable blur (5–27 taps) → upsample, partly in tile shaders.** Inferred from kernel names in QuartzCore's metallib; the code and the selection logic were not inspected.
7. **`fc_memoryless_backdrop` means backdrop captures sometimes stay in memoryless/tile memory.** Name only.
8. **Whether on-screen SwiftUI `.blur` matches the `ImageRenderer` (RenderBox) PSF**, and what `RB_EXACT_BLUR` does (setting it to 1 changed nothing on macOS).
9. **Bilinear sub-texel precision on the A17 Pro.** 8 bits measured on the M1 Max and in the Simulator only.
10. **`generateMipmaps` filter on the A17 Pro.** 2 × 2 box measured on the M1 Max; Apple says it may vary by family.
11. **Counter sampling on the A17 Pro supports only `atStageBoundary`.** Measured on the M1 Max; inferred for the phone.
12. *(Settled.)* **The `.shaderWrite` lossless-compression rule on Apple7–Apple9.** Tech Talk 111431 (2026) says that compression "was disabled for textures with MTLTextureUsageShaderWrite" before M5/A19 (§2.6). Still unmeasured: how large the resulting cost is on the A17 Pro.
13. **Texture-unit throughput and FP16 vs FP32 ALU rates on the A17 Pro.** Not published; community data covers older chips only.
14. **Render-pass tile size used by the render server**, and whether `.blur` passes use tile shaders on device.
15. **The ~1 ms gap before the first compute pass** in the counter-sampled command buffer on the M1 Max (cause unknown; host was heavily loaded).
16. **Hensley et al. 2005's exact offset method** for SAT precision (described second-hand by Atanasov et al. 2018).
17. **Kawase's GDC 2003 talk title and pass schedule** (not fetched).
18. **Whether the iOS 27.0 Simulator will keep running Apple7-only features** (SIMD reductions, read-write textures) despite reporting Apple2; observed on 24A5355p only.
19. **Metal 4 `.precise` timestamps on the A17 Pro**: per-dispatch resolution and their overhead. Measured on the M1 Max only, and only qualitatively, because the host was loaded.
20. **Why the Simulator returns level-0 texels for `getBytes` on a mip level of a `.shared` texture** (bug or undocumented limit).
21. **Universal texture compression on A19-family phones.** Tech Talk 111431 says it "works by default on M5". I did not find an equally explicit statement for the A19 and A19 Pro, although the Feature Set Tables list the feature for all of Apple10, which includes the A19 series. It does not apply to the A17 Pro (Apple9).

## 9. Open items for the build

- Build the brief's Mac parity CLI. The original `parity.swift`, which had CPU references for all seven sketches, was lost in the `$TMPDIR` purge (§7, item 35). `verify.swift` is the surviving seed: it loads the `.metal` text with `makeLibrary(source:)` and checks both Gaussian sketches, and it runs unchanged in the Simulator. The CLI needs CPU references for the other five sketches, and for each one it should re-measure the numbers in §6.3 that were not re-run.
- Add an on-device "GPU probe" screen that measures and records: copy bandwidth, FMA throughput, bilinear sub-texel bits, `generateMipmaps` impulse response, counter sampling points, threadgroup limits, and the compression A/B. These replace every UNVERIFIED hardware number above with a MEASURED one for his phone.
- Implement the pass timeline with a Metal 4 `MTL4CounterHeap` (`.precise` timestamps between passes, ticks converted with `queryTimestampFrequency()`), behind `#if !targetEnvironment(simulator)`, with the classic per-encoder `MTLCounterSampleBuffer` path as the fallback. Copy the probe sources (`verify.swift`, `m4probe.swift`, `probe.metal`) into the project's `Tools/` folder before `$TMPDIR` is purged again.

<!-- STATUS: COMPLETE -->
