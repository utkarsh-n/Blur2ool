# Blur2ool — brief

Date: 13 October 2026. Status: **binding input for research, design and build**.

## The ask (user's words)

> Lets build "Blur2ool" a play on "Blur 2" to build a blur simulator and mathematical visualizer that shows how various graphical blurs work at each layer from WYSISYG to the GPU and what makes each blur unique. like gaussian, box, radial, and all the dozens i am not mentioning. SwiftUI app with Metro design.

Read this as four requirements:

1. **Blur simulator.** It runs real blurs on real pixels, on the GPU, live, with parameters you can change.
2. **Mathematical visualizer.** It shows the math: continuous definitions, kernels/PSFs, frequency responses, discretization, approximation error, complexity.
3. **Every layer from WYSIWYG to the GPU.** For each blur, you can descend from the designer's slider (Figma/Photoshop/CSS/SwiftUI `.blur(radius:)`), through the API call and what its parameter means, the math, the discrete kernel, the algorithm and its passes, the Metal shader and dispatch, down to the pixels that come out. You can follow one pixel through it.
4. **What makes each blur unique, across dozens of blurs.** He named Gaussian, box and radial, "and all the dozens I am not mentioning". The catalog should be broad (aim for 30+ distinct blurs and blur-like filters, grouped into families). Each needs a fingerprint: PSF shape, frequency response, edge behaviour, cost class, artifacts, and where it is used in practice.

## Identity

- Name **Blur2ool**: display name `Blur2ool`, Xcode project/target/module `Blur2ool`, bundle `com.utkarsh.blur2ool`, folder `/path/to/developer/Documents/AI Stuff/Blur2ool`.
- Native SwiftUI **iPhone** app. iOS 27.0 minimum, Swift 6, XcodeGen (`project.yml`), team `YOUR_TEAM_ID`, dark appearance, iPhone only. His phone is an iPhone 15 Pro Max (A17 Pro, iOS 27.x). It is connected to this Mac.
- Toolchain: `/Applications/Xcode-beta.app` (Xcode 27.0, 27A5194q); `xcodegen` at `/opt/homebrew/bin/xcodegen`.

## Design system: Metro Station (his default)

"Metro design" means his **Metro Station design system**. Read the skill first, then the spec sections it routes you to:

- `/path/to/developer/Documents/AI Stuff/Metro Station/Skills/metro-station-design-system/SKILL.md`
- `references/design-system-spec.md` (814 lines; sections 1–7 foundations, 8–12 components, 13–14 optics, 17 accessibility, 18 SwiftUI recipes, 19 adaptation, 20 verification)
- `references/swiftui-integration.md`, `assets/design-tokens.json`, `assets/visual-reference.png`, `assets/swiftui-starter/*`

Adopt the smallest useful component set, adapted to the blur domain. Copy the starter into `App/DesignSystem` as the adopters do. Adopters to learn from:

- `AI Stuff/AssemblerToy`: the closest analogue. It has a "Layers" atlas of 14 abstractions, a "Guide" that walks one real instruction through Assembly → CPU → Registers → Memory → OS, and a rectangular display instrument as the hero.
- `AI Stuff/ClassicalMLSimulator`: plots, a model library, a field guide, and a Foundation-only core with `swift test`.
- `AI Stuff/Metro Station/App`: the source app.

## Engineering shape (expected; the design phase may refine)

- **`BlurCore`**: a Foundation-only Swift package, portable to macOS so `swift test` works. It holds the blur catalog and metadata, kernel generation, **CPU reference implementations** of every blur, analytic and DFT frequency responses, parameter-semantics conversions between tools and APIs, cost models, and the per-layer content.
- **GPU path**: Metal compute and render kernels in the app target. Every GPU blur has a CPU reference, and **GPU↔CPU parity** must be checkable on the Mac. One way is a CLI that loads the same `.metal` sources with `makeLibrary(source:)` on the Mac GPU and compares against `BlurCore`. GPU time comes from `MTLCommandBuffer.gpuStartTime/gpuEndTime`.
- Built-in test images are **procedural**: Siemens star, zone plate, checkerboard, step edges, impulse grid, text, and a "night city" of point lights for bokeh. This avoids copyright and suits the math better. `PhotosPicker` can be added for the user's own photos (no permission prompt).
- No third-party runtime dependencies, accounts or network.

## Honesty rules

Every number on screen is one of the following, and the app labels which. This follows the badges in `AI Stuff/Loom`.

- **LIVE**: computed now from the current image and parameters.
- **MEASURED**: timed or fitted on this device, such as GPU milliseconds or a fitted σ.
- **COMPUTED**: an exact consequence of the math.
- **MODELED**: an estimate from a cost or bandwidth model.
- **REFERENCE**: documented by a spec or vendor, cited.
- **INFERRED**: proprietary internals we cannot see, such as what SwiftUI `.blur` does inside Core Animation or the render server. These must be labeled as inferred, and **measured live where possible**. For example, the app can render an impulse through SwiftUI `.blur(radius:)` with `ImageRenderer` on the device and fit the PSF to report the effective σ.

## Build and process rules

- **SIMULATOR HOLD — check `Documentation/HOLD-SIMULATOR.md` first.** While its status is ACTIVE: no `simctl` of any kind, no simulator-destination builds or tests, and leave CoreSimulator and other projects alone. Use Mac-side checks, generic iOS device builds and the physical iPhone instead. This overrides the simulator mentions below until an explicit release arrives from the Time Machine recovery chat.

- **Never run xcodebuild on the iCloud folder.** It hangs in NSFileCoordinator. Mirror the folder to `$TMPDIR` with `Tools/build.sh`, as `AI Stuff/Toothpaste Toy/Tools/build.sh` does. `swiftc`, `swift test` (with an explicit `--scratch-path` outside iCloud) and `xcodegen` are fine.
- Parallel agents each use their own build directory and their own simulator. Wrap `simctl` calls in a timeout, because they hang when the host is loaded. Never uninstall or modify his other apps, other projects or other simulators.
- Prefer headless checks: unit tests, offscreen PNG renders, `simctl io screenshot`.
- Don't throttle for host load. He prefers maximum parallel throughput.
