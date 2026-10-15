# Blur2ool — Engineering Architecture (binding contract)

Date: 14 October 2026. Author: lead designer-architect (synthesis pass; second run, written under the SIMULATOR HOLD). Status: complete (the completion marker is the last line).

This is the engineering contract for a team of parallel AI agents. `SPEC.md` says *what* the product is; this file says *how* it is built: files and their owners, the frozen Swift and Metal interfaces, the colour pipeline, parity tolerances, the walking skeleton, build waves, verification, and the simulator-hold mode. The workflow `Tools/workflows/build.js` reads this file (build areas §8, walking skeleton §9, waves §10, verification §11) and runs Plan → Skeleton → Gate → area waves → Integrate → QA → Device.

**What was verified while writing this file** (MEASURED on this Mac on 14 October 2026: MacBookPro18,2, Apple M1 Max, macOS 27.2, Xcode 27.0 (27A5194q), Swift 6.4; no simulator was used):

- Every frozen declaration in §5 exists as compiling Swift in `Documentation/interfaces/` (a SwiftPM package plus app-side API files). It builds for macOS with Swift 6 language mode and `-warnings-as-errors`, and its BlurCore, BlurGPU and app-side API files typecheck for `arm64-apple-ios27.0` (device SDK) with `-strict-concurrency=complete -warnings-as-errors`.
- 22 tests pass: 19 BlurCore tests (the SPEC §5.3 A Gaussian fixtures: weights, discrete σ 3.963, minimum H −0.0010, H(0.5) = 7.1·10⁻⁴, the linear-sampled offsets and weights, OUT 0.4500 → 179/255 and the 115/255 sRGB branch; the Bench σ 12 numbers; Nyquist values at σ 1; formatting, honesty, stepping, gesture, scheduler and crown rules) and 3 BlurGPU tests on the Mac GPU.
- The shared Metal header and two shader files compile with `-Wall -Wextra` and no diagnostics for `iphoneos` and `macosx`, as separate translation units linked into one `metallib`, and as the single translation unit `blur-gpucheck` builds at runtime.
- The seed `blur-gpucheck` runs the six Gaussian parity cases at the real 894 × 894 window in 5.1 s (release build). All pass. The maximum |GPU − CPU| is 9.77·10⁻⁴ (at most 3 fp16 ulps, at most 1 eight-bit step), and the traced specialization is bit-identical to the untraced one, with the trace's final running sum equal to the output at the probe (§7).
- **After design review round 1** (same Mac, same day; Review log at the end): the amended contract builds with `-warnings-as-errors`, **32 tests pass** (27 BlurCore, 5 BlurGPU on the Mac GPU), `blur-gpucheck` passes **20/20 cases** (linear-sampled and separable Gaussian seeds, sizes 256 and 894, with and without `--apple2-limits`; 8.9 s for both sizes), every traced pass ends with its `flags = 2` final record, the shaders compile for `iphoneos` with `-Wall -Wextra` and no diagnostics, and BlurCore, BlurGPU and `AppContract` typecheck for `arm64-apple-ios27.0` under Swift 6 strict concurrency. No simulator was used.

**Binding rules for every agent** (BRIEF and build.js, made concrete):

0. **Check `Documentation/HOLD-SIMULATOR.md` first.** While it says `Status: **ACTIVE**`, §12 overrides every simulator mention in this file: no `simctl` of any kind, no simulator destination or `iphonesimulator` SDK, and CoreSimulator is left alone.
1. Never run `xcodebuild` inside `~/Documents` (iCloud hangs in `NSFileCoordinator`). Build only through `Tools/build.sh`, which mirrors the tree to `$B2_BUILD_DIR` (default `$TMPDIR/Blur2oolBuild`). Run `swift build` and `swift test` only through `build.sh`, or with `--scratch-path` under `$TMPDIR`.
2. Edit only files your area owns (§8). A change to a frozen file (§5.0) or to another area's file goes to **your own** request file `Documentation/build/requests/<AREA>.md` (area, file, change, why); INTEGRATE reads the folder and applies requests.
3. **Build against stable neighbours.** Always set `B2_AREA=<AREA>`: `build.sh` then mirrors **your** paths live and every other area's paths from their last green snapshot (§11.1 rule 2), so another agent's half-finished edit never breaks your checks. After your own CORE and TYPECHECK pass, run `Tools/build.sh publish-green`. Before saving Swift or Metal, run the fast pre-flight: `Tools/build.sh typecheck-ios` (device SDK, about 15 s) and `Tools/build.sh metal-check`.
4. Honesty is a compile-time concern. Every number that reaches the UI travels as a `BadgedValue` built with the factories of §5.1, and every view-bound line that mixes words and numbers is a `BadgedLine` (§5.1). Tests run `honestyViolations` over all generated content, including the digits-in-plain-text lint (§11.3).
4a. **Name prefixes.** Every non-private top-level symbol in `Sources/BlurCore/Operators/<G>/`, `Sources/BlurGPU/Pipelines/<G>/` and `Tests/*/<AREA>/` starts with the group or area tag (`F6RowSpanSAT`, `FAMF6_DiscFixtures`) or is nested in the group's namespace enum (`enum F6 { … }`); the frozen type names (`<G>Catalog`, `<G>Pipelines`, the seeds) are the exceptions. `Tools/build.sh lint-names` enforces it in every gate.
5. Write progress to `Documentation/build/progress-<AREA>.md` as you go. Append the exact line `<!-- STATUS: COMPLETE -->` only when your acceptance checks pass, or when you have recorded exactly why one cannot run (for example `DEFERRED-BY-HOLD`, §12.3).

## 1. Folder layout

Everything lives under `/path/to/developer/Documents/AI Stuff/Blur2ool`. The owner of each path is given (§8). `SKEL (frozen)` means the walking skeleton creates the file and nobody edits it afterwards except INTEGRATE through the request files (`Documentation/build/requests/`). Green snapshots (§11.1 rule 2) live outside the repo in `$B2_GREEN_DIR` (default `$TMPDIR/b2-green/<AREA>/`). `SKEL then X` means the skeleton creates the file with its frozen public signatures, and area X owns the body from wave 1 on.

```
Blur2ool/
├─ project.yml                               SKEL (frozen)    XcodeGen spec (§2)
├─ Package.swift                             SKEL (frozen)    SwiftPM: BlurCore, BlurGPU, blur-gpucheck, tests (§3)
├─ .gitignore                                SKEL
├─ README.md                                 INTEGRATE
├─ App/                                                        the iOS app target "Blur2ool" (SwiftUI + MetalKit + UIKit)
│  ├─ Blur2oolApp.swift                      SKEL (frozen)    @main; builds AppEnvironment; passes launch arguments
│  ├─ AppEnvironment.swift                   SKEL then ENGINE GPUContext, coordinator, stores, service installation
│  ├─ RootView.swift                         SKEL (frozen)    NavigationStack(path:) + ONE .sheet(item:) (§5.9)
│  ├─ DesignSystem/
│  │  ├─ InstrumentDesignSystem.swift        SKEL (verbatim)  AssemblerToy's hardened starter copy (METRO §E.1)
│  │  ├─ InstrumentControlTouchBoundary.swift SKEL (verbatim) starter
│  │  ├─ LensRefraction.swift                SKEL (verbatim)  starter
│  │  ├─ InstrumentLensOptics.metal          SKEL (verbatim)  starter SwiftUI shader (never loaded by blur-gpucheck)
│  │  └─ <Blur2ool components>.swift         SKEL then METRO-COMPONENTS  (§5.14 list, one file each)
│  ├─ Engine/                                ENGINE           EngineTypes.swift is SKEL (frozen); the rest §5.9
│  ├─ Render/                                UI-SPECIMEN      PresentRenderer, MetalSpecimenView, touch layer
│  ├─ Bench/                                 UI-BENCH         the Bench screen (except the two folders below)
│  │  ├─ SpecimenWindow/                     UI-SPECIMEN      image window, probe, handles, loupe, zoom, split, Tier S slot
│  │  └─ Compare/                            UI-COMPARE       compare bar, views, Δ telemetry
│  ├─ Content/                               CONTENT-VIEWS    renderers for FloorPage / ContentBlock / FigureSpec (§5.11)
│  ├─ Layers/                                UI-LAYERS
│  ├─ Trace/                                 UI-TRACE
│  ├─ Atlas/                                 UI-ATLAS         Catalog sheet (4 tabs), Tier 3 atlas pages
│  ├─ Fingerprint/                           UI-ATLAS         FingerprintCardView (full and compact)
│  ├─ FieldGuide/                            UI-FIELDGUIDE    Guide · This phone · Runs · Settings
│  ├─ Calibration/                           CALIBRATION      measureEdges, CalibrationService, Calibrate sheet
│  ├─ System/                                FAM-F10          SystemExhibitView: SwiftUI .blur half, glass/material exhibit
│  ├─ Specimens/                             TESTIMAGES       Core Text coverage, photo import, CGImage conversion
│  ├─ GPU/Shaders/                           per file (§6.1)  compiled into the app's default.metallib
│  └─ Resources/Assets.xcassets              SKEL             AppIcon (generated by Tools/GenerateIcon.swift)
├─ Sources/
│  ├─ BlurCore/                                               Foundation-only, nonisolated, macOS + iOS
│  │  ├─ Core/                               SKEL (frozen)    §5.1–§5.7, §5.11–§5.13
│  │  ├─ Math/                               SKEL (frozen)    KernelMath (§5.4)
│  │  ├─ Interaction/                        SKEL then ENGINE gesture arbiter, crown detents, schedulers (§5.10)
│  │  ├─ Operators/<G>/                      FAM-<G>          one folder per implementation group (§8)
│  │  ├─ Specimens/                          TESTIMAGES
│  │  ├─ Semantics/                          SEMANTICS        tool conventions (STACK)
│  │  ├─ Content/                            CONTENT-LAYERS   floor templates, rail, pills, trace scripts, lessons, field guide
│  │  ├─ Analysis/                           ANALYSIS         divergence, fingerprint vectors, cost model
│  │  └─ Calibration/                        CALIBRATION      PSFFitter
│  ├─ BlurGPU/                                                Metal + BlurCore; no UIKit, SwiftUI or MetalKit
│  │  ├─ Core/                               SKEL (frozen)    §5.8 (incl. GaussianPassEncoder, the shared Gaussian stage)
│  │  ├─ Pipelines/<G>/                      FAM-<G>
│  │  ├─ Measure/                            GPU-MEASURE      timing, counters, device probes, shape measurement
│  │  └─ AppleTwins/                         APPLE-TWINS      Core Image / MPS / vImage runners
│  └─ blur-gpucheck/                         SKEL then GPUCHECK  the Mac parity CLI (§3.2)
├─ Tests/
│  ├─ BlurCoreTests/<AREA>/                                   each area its own folder (Mac, swift test)
│  ├─ BlurGPUTests/<AREA>/                                    each area its own folder (Mac GPU)
│  └─ AppTests/<AREA>/                                        each area its own folder (Xcode unit tests; §12 under the hold)
├─ UITests/<AREA>/                                            smoke tests only; never the gesture gate (SPEC §16)
├─ Tools/
│  ├─ build.sh                               SKEL (frozen)    mirror + commands + hold guard (§11.1)
│  ├─ ownership.tsv                          SKEL (frozen)    path-glob → owning area (§8), read by build.sh's B2_AREA mirror
│  ├─ shader-manifest.sh                     SKEL (frozen)    copies shader sources into the bundle, writes ShaderManifest.json
│  ├─ GenerateIcon.swift                     SKEL             app icon generator (AppKit, as LosAlamosSimulator)
│  ├─ calibrate/                             read-only        research tools (MeasurePSF.swift, calibrate.swift)
│  └─ workflows/                             nobody           orchestration scripts
└─ Documentation/
   ├─ BRIEF.md · SPEC.md · ARCHITECTURE.md · HOLD-SIMULATOR.md · research/ · design/
   ├─ interfaces/                            read-only        the verified frozen contract (§5.0)
   ├─ build/                                 PLAN.md, requests/<AREA>.md (one file per area), progress-<AREA>.md, verify-<AREA>.md, gate-*.md, qa-*.md
   ├─ screenshots/                           <AREA>-*.png (each area writes only its own prefix)
   └─ metro-station-design-tokens.json       SKEL             reference copy of the Metro token manifest (METRO §E.1)
```

Implementation groups `<G>` are `F1, F2, F3, F4, F5A, F5B, F6, F7, F8A, F8B, F9, F10, F11` (§8 lists their entries). Naming rules: SwiftUI views end in `View` or name the component (`DescentRail`, `SpecimenHousing`); BlurCore model names are plain (`CatalogEntry`, `Kernel1D`); no bare `Kernel`, `Pass`, `Blur` or `Specimen` types (METRO §E.2). Metro starter names stay unchanged (`Instrument*`, `instrumentLensOptics`, `instrumentControlOwnsTouches`).

## 2. `project.yml` outline (XcodeGen)

Modelled on `AI Stuff/AssemblerToy/project.yml`. Binding values: iOS 27.0, Swift 6, team `YOUR_TEAM_ID`, bundle `com.utkarsh.blur2ool`, display name `Blur2ool`, iPhone only, portrait only, dark.

```yaml
name: Blur2ool
options:
  bundleIdPrefix: com.utkarsh
  deploymentTarget: { iOS: '27.0' }
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: '6.0'                     # Swift 6 language mode (complete strict concurrency)
    SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated   # explicit (the Xcode default); isolation is written in code (§5.15)
    MARKETING_VERSION: '1.0'
    CURRENT_PROJECT_VERSION: '1'
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Automatic
    MTL_FAST_MATH: YES                       # explicit; blur-gpucheck compiles with MTLMathMode.fast to match
    MTL_MATH_MODE: FAST                      # explicit (valid values: UseLanguageDefault, RELAXED, FAST, SAFE)
    ENABLE_USER_SCRIPT_SANDBOXING: NO        # Tools/shader-manifest.sh reads App/GPU/Shaders and writes into the bundle
    ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS: NO   # tokens live in code; swiftc typecheck-ios cannot see asset symbols (E-29)
    B2_BUILD_STAMP: dev                      # build.sh passes B2_BUILD_STAMP=<AREA>-<uuid> for every phone build (E-2)
targets:
  BlurCore:                                  # Foundation-only framework (same sources as the SwiftPM target)
    type: framework
    platform: iOS
    sources: [Sources/BlurCore]
    settings: { base: { GENERATE_INFOPLIST_FILE: YES, PRODUCT_BUNDLE_IDENTIFIER: com.utkarsh.blur2ool.core,
                        SWIFT_OPTIMIZATION_LEVEL: '-O' } }   # every configuration: references and canvases at -O (E-9)
  BlurGPU:                                   # Metal encoding shared with blur-gpucheck; contains no .metal files
    type: framework
    platform: iOS
    sources: [Sources/BlurGPU]
    dependencies: [{ target: BlurCore }]
    settings: { base: { GENERATE_INFOPLIST_FILE: YES, PRODUCT_BUNDLE_IDENTIFIER: com.utkarsh.blur2ool.gpu,
                        SWIFT_OPTIMIZATION_LEVEL: '-O' } }
  Blur2ool:
    type: application
    platform: iOS
    sources:
      - path: App                            # includes App/GPU/Shaders/*.metal and the lens shader → default.metallib
    dependencies: [{ target: BlurCore }, { target: BlurGPU }]
    postCompileScripts:
      - name: Shader sources and manifest
        script: '"${SRCROOT}/Tools/shader-manifest.sh"'
        basedOnDependencyAnalysis: false
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Blur2ool
        CFBundleName: Blur2ool
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        UILaunchScreen: {}
        UIUserInterfaceStyle: Dark
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        UIApplicationSceneManifest: { UIApplicationSupportsMultipleScenes: false }
        ITSAppUsesNonExemptEncryption: false
        LSApplicationCategoryType: public.app-category.education
        B2BuildStamp: $(B2_BUILD_STAMP)       # which area's build is installed; device-session checks it before every capture
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.utkarsh.blur2ool
        TARGETED_DEVICE_FAMILY: '1'
        SUPPORTS_MACCATALYST: NO
        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
        SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
  Blur2oolTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests/AppTests]
    dependencies: [{ target: Blur2ool }, { target: BlurCore }, { target: BlurGPU }]
    settings: { base: { GENERATE_INFOPLIST_FILE: YES, PRODUCT_BUNDLE_IDENTIFIER: com.utkarsh.blur2ool.tests, TARGETED_DEVICE_FAMILY: '1' } }
  Blur2oolUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies: [{ target: Blur2ool }]
    settings: { base: { GENERATE_INFOPLIST_FILE: YES, PRODUCT_BUNDLE_IDENTIFIER: com.utkarsh.blur2ool.uitests, TARGETED_DEVICE_FAMILY: '1' } }
schemes:
  Blur2ool:
    build: { targets: { Blur2ool: all } }
    run:
      config: Debug
      environmentVariables: { MTL_DEBUG_LAYER: '1' }   # Metal API validation in debug runs (SDK §15 rule 8)
    test:
      gatherCoverageData: false
      targets: [Blur2oolTests, Blur2oolUITests]
```

Notes. (0) **Review round 1.** `SWIFT_OPTIMIZATION_LEVEL -O` on BlurCore and BlurGPU in every configuration: converting a 1406² canvas to fp16 takes 444.6 ms at `-Onone` and 3.5 ms at `-O` (MEASURED by the engineering reviewer, M1 Max), and the Debug builds the phone judges must behave like the shipped app. The app target stays at the configuration default. `B2BuildStamp` is drawn nowhere in the UI; ENGINE logs it at launch and `device-session` compares it with the stamp it built (§11.1). (1) `MTL_LANGUAGE_REVISION` is deliberately **not** set. The first draft set `Metal41`, but this Xcode's `MetalCompiler.xcspec` enumeration stops at `Metal40` (MEASURED by reading the spec file), so the value would be invalid. The default `UseDeploymentTarget` gives MSL 4.1 for an iOS 27 target (`__METAL_VERSION__ 410`, SDK §13), and `blur-gpucheck` sets `languageVersion = .version4_1` to match. (2) There is no motion usage string: tilt optics are off in v1 (`motionActive: false`, SPEC §16). (3) There is no photo-library usage string: `PhotosPicker` runs out of process (SDK §10). (4) Scheme environment variables do not reach apps launched by `devicectl`. On the phone, pass `--environment-variables '{"MTL_DEBUG_LAYER":"1"}'` to `devicectl device process launch` for validation runs (`Tools/build.sh device-launch --validate`). (5) `Tools/shader-manifest.sh` copies `App/GPU/Shaders/*.metal` and `B2Shared.h` byte for byte into `<bundle>/ShaderSources/` and writes `ShaderSources/ShaderManifest.json` as `{"files": {"<name>": "<sha256>"}}` (`shasum -a 256`). The combined SHA-256 is always computed in Swift by `ShaderManifest.assemble` (§6.6), so the app and `blur-gpucheck` agree by construction.

## 3. `Package.swift`, BlurCore, BlurGPU and the `blur-gpucheck` CLI

### 3.1 Package.swift (root of the repo; `Documentation/interfaces/Package.swift` verbatim)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blur2ool",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "BlurCore", targets: ["BlurCore"]),
        .library(name: "BlurGPU", targets: ["BlurGPU"]),
        .executable(name: "blur-gpucheck", targets: ["blur-gpucheck"]),
    ],
    targets: [
        .target(name: "BlurCore", path: "Sources/BlurCore"),
        .target(name: "BlurGPU", dependencies: ["BlurCore"], path: "Sources/BlurGPU"),
        .executableTarget(name: "blur-gpucheck", dependencies: ["BlurCore", "BlurGPU"], path: "Sources/blur-gpucheck"),
        .testTarget(name: "BlurCoreTests", dependencies: ["BlurCore"], path: "Tests/BlurCoreTests"),
        .testTarget(name: "BlurGPUTests", dependencies: ["BlurCore", "BlurGPU"], path: "Tests/BlurGPUTests"),
    ]
)
```

- Tools version 6.0 means Swift 6 language mode for every target. Platform versions are strings (`"27.0"`) because `MTLLanguageVersion.version4_1` and the iOS 27 APIs need them and tools 6.0 has no `.v27` constants.
- **BlurCore** imports only `Foundation`. It uses no CoreGraphics, CoreText, Metal, SwiftUI or UIKit. It stays **nonisolated** (no default MainActor isolation), so references run on background tasks and in `swift test` (SDK §5 item 4). It uses `Float16`, so the Mac side requires Apple silicon (this Mac is arm64).
- **BlurGPU** imports `Metal`, `CryptoKit`, BlurCore and, for APPLE-TWINS, `MetalPerformanceShaders`, `CoreImage` and `Accelerate`. It never imports MetalKit, UIKit or SwiftUI. It contains **no `.metal` files**: its host passes an `MTLLibrary` (the app passes `device.makeDefaultLibrary()`; `blur-gpucheck` and the tests pass a library compiled from `App/GPU/Shaders` with `ParityRunner.compileLibrary`). One encoding implementation therefore serves both the app and the parity CLI.
- Tests: `Tools/build.sh core-test` runs `swift test --scratch-path "$B2_BUILD_DIR/spm"` in the mirror. It runs BlurCoreTests and BlurGPUTests on the Mac, including the GPU tests on the Mac GPU.

### 3.2 `blur-gpucheck` (Mac GPU↔CPU parity CLI)

```
blur-gpucheck [--shaders App/GPU/Shaders] [--metallib <file.metallib>] [--filter <text>] [--size <n>] [--safe-math]
              [--apple2-limits] [--regions full|crops] [--json <out.json>] [--list] [--print-sha] [--manifest <ShaderManifest.json>]
```

1. **Load and compile** (`ParityRunner.compileLibrary`, frozen). Read `B2Shared.h` and every `*.metal` in `--shaders`, skipping any file that contains `SwiftUI/SwiftUI.h` (none live there: the lens shader stays in `App/DesignSystem`). Remove each file's exact line `#include "B2Shared.h"`, prepend the header text once, concatenate in byte-wise file-name order (`ShaderManifest.assemble`), and compile with `device.makeLibrary(source:options:)`. Use `mathMode = .fast` and `mathFloatingPointFunctions = .fast` (or `.safe`/`.precise` with `--safe-math`), and `languageVersion = .version4_1`. Runtime compilation cannot resolve quoted includes (METRO §E.4 item 3), which is why the header is prepended. Print the compile time and the combined SHA-256. With `--manifest`, compare the per-file hashes with a bundle's `ShaderManifest.json`. **`--metallib`** (review fix E-23) instead loads a library that `Tools/build.sh metal-check` built per file with `xcrun -sdk macosx metal -c` using the flags Xcode passes for `MTL_FAST_MATH YES` / `MTL_MATH_MODE FAST` (SKEL copies them from a `device` build log into `build.sh`), linked with `metallib`. This is the app's offline, per-file compile; GATE and INTEGRATE run both modes, because single-TU runtime and per-file offline compiles could treat fast math or traced = untraced differently (UNVERIFIED).
2. **Enumerate** every `GPUPipelineRegistry.factories` entry × sizes (default 256 and 894) × its `parityCases(size)` (§5.8).
3. **Run** each case with `ParityRunner.run`, exactly as the app renders. Generate the specimen canvas (at 0 EV) with BlurCore in a detached task and crop the window at the case's pan; convert it to `HalfImageData` off the main actor and upload it as `rgba16Float`. Encode the window pass (× 2^EV when the case sets exposure, `b2_common_window_fs`), then `GPUContext.encodeFullBlur` (colour pre-pass, pipeline, colour post-pass) through a `GPUCommandRecorder`. Read back with a blit into a shared buffer. In a **detached task**, run `BlurReference.run(…, exposureEV:)` over the whole window at sizes ≤ 256, and `BlurReference.runCrop` on **128 × 128 crops at the case's probes** at 894 (`ParityRegionPolicy.standard`; review fix E-8), and evaluate with `ParityEvaluation.evaluate` at the case's tolerance, adjusted for colour passes, with the **local scale** of §7 rule 1. For cases with `checkTraced`, encode again with `TraceRequest.sized(probe:plan:)` at every probe and assert: the outputs are bit-identical (zero differing fp16 words); no block overflowed; every traced pass wrote a `flags = 2` final record; and the last traced pass's final record, rounded to fp16, equals the output at the probe in every channel (review fix E-13).
4. **Limits.** `--apple2-limits` builds the context with `forceApple2Limits: true`: 512 threads per threadgroup and 16,384 B of threadgroup memory. `GPUContext.dispatch2D` then clamps threadgroups and throws `budgetExceeded` for oversized tiles. The CLI builds its context with `recordsDispatches: true`, fails any case that throws, and fails any compute pass that did not go through `dispatch2D` (it checks `dispatchLog` against the encoded compute passes in `GPUCommandRecorder.encodeLog`). This is the hold-safe replacement for running in the Simulator, whose Apple2 family enforces those limits only under API validation (GPU §2.7 items 2–3).
5. **Mutation cases** (review fix E-5; GPUCHECK). For every tolerance class in use, test-only factories wrap a real pipeline with one deliberate defect — σ × 1.01 (wrong weights), the last tap dropped (or, for fixed-tap kernels, the plan's smallest-weight tap), one pass skipped (identity copy) — and run on Night City at +4 EV and on step edges. Each must FAIL; a mutation that passes is a gate failure (the class is too loose there). `SKEL_ReviewFixes.localScaleCatchesDroppedTapsOnHDR` already proves the evaluator half on the CPU: a kernel with every second tap dropped passes `bilinear` under the old global scale and fails under the local one.
6. **Report.** One line per case: `PASS|FAIL <blur>/<variant> @<size>: <case> maxAbs · rms · lsb8 · ulp16 · traced=untraced · final=out`. Write a JSON array of `ParityOutcome` when asked. Exit status is 0 only if every case passes, 1 if any fails, and 2 for a compile or setup error. `--print-sha` prints the combined SHA and exits; `Tools/build.sh verify-shaders` compares it with the app bundle (§6.6).

Full gate runs at 894 now check crops, not the whole window, so a complete INTEGRATE run stays in minutes rather than hours (MEASURED for the two Gaussian seeds: 20 cases at 256 and 894 in 8.9 s, release, M1 Max).

`Tools/build.sh gpucheck [args]` builds the CLI with `swift build -c release --product blur-gpucheck --scratch-path "$B2_BUILD_DIR/spm-release"` in the mirror and runs it from the mirror root. While the hold is active, no simulator copy of the CLI is run (§12). After release, running the same binary in a simulator with `simctl spawn` is optional and adds nothing that `--apple2-limits` does not already check.

## 4. Colour pipeline, texture formats, edge modes

### 4.1 Values and formats

| Stage | Format / space | Rule |
|---|---|---|
| Specimen canvas (CPU) | `ImageBuffer`: `SIMD4<Float>` per pixel, **linear light, premultiplied alpha**, row-major, y down; HDR values > 1 allowed; **always at 0 EV** | generated by BlurCore (§5.6) in a detached task; photos decoded through their colour profile to linear, then area-averaged |
| Specimen texture (GPU) | `rgba16Float`, `.private`, usage `.shaderRead` | converted to fp16 bytes off the main actor (`HalfImageData`, BlurCore), then uploaded once per canvas through a shared staging buffer and a blit (`GPUContext.upload`) |
| Window input | `rgba16Float` N × N, `.private`, usage `[.shaderRead, .renderTarget]` | the pan: a **blit copy** of the N × N region at an integer offset at 0 EV; otherwise the render pass `b2_common_window_fs`, which multiplies by 2^EV (exposure at render time, so an EXPOSURE detent never regenerates the 31.6 MB canvas; review fix E-10) |
| Preview input | `rgba16Float` ⌊N/2⌋² (or ⌊N/4⌋²) | the frozen 2 × 2 mean `b2_common_downsample2x_fs` of the window (applied twice for quarter); CPU twin `ImageBuffer.downsampled2x` (§5.5 previews) |
| CPU reference input | the window, **rounded to fp16** (`ImageBuffer.roundedToHalf`), × 2^EV, rounded again | exactly what the GPU sampled; `BlurReference.run(…, exposureEV:)` does this when `emulateHalfStorage` is set. Power-of-two gains commute with fp16 rounding away from subnormals, so exposure leaves parity unchanged (`SKEL_ReviewFixes.exposureCommutesWithHalfRounding`) |
| Intermediates and outputs | `rgba16Float` (`rgba8Unorm` only on the Compare › Precision axis) | fragment passes write render targets **without** `.shaderWrite`, so Apple9 keeps lossless compression; compute outputs need `.shaderWrite` and lose it (Tech Talk 111431, REFERENCE) |
| Accumulation | `float` (fp32) in every kernel; `half` only when `B2_HALF_ACCUM` is true (the Precision lesson) | accumulate with explicit `fma()` (§6.3) |
| Measurement readback | a blit of a region into a `.shared` `MTLBuffer`, decoded to `Float` | the probe texel is encoded into the render's own recorder (`encodeReadTexels`, no extra command buffer; review fix E-26); 9 × 9 for Trace and 14 × 14 for the loupe are read before the slot's next encode; 128 × 128 for in-app parity (`readTexels`) |
| Drawable | `MTKView.colorPixelFormat = .bgra8Unorm` (not `_srgb`: the Simulator forbids sRGB writes, SDK §15 rule 7), with the layer's `colorspace` set to sRGB; the present shader applies the sRGB transfer function and clips to [0, 1] | optional EDR on the device (Settings › Display): an `rgba16Float` drawable with extended linear sRGB and `wantsExtendedDynamicRangeContent` |
| 32-bit float textures | only for CPU-side analysis, FFT planes and measurement; never filtered on the GPU | `supports32BitFloatFiltering` is not guaranteed on the A17 Pro (SDK §15) |

### 4.2 Colour-space and alpha modes (SPEC §9.3)

Blur kernels never know the colour space or the alpha mode. `B2Common.metal` has one specialised fragment pass, `b2_common_colour_fs` (function constants 4–6), which `GPUContext.encodeFullBlur` inserts before and after every blur. BlurCore `ColourTransform` implements the identical math for the CPU references, and `BlurReference.run` applies it, so parity covers it.

- **Linear light, premultiplied** (default): no pre- or post-pass.
- **sRGB-encoded**: pre-pass un-premultiply → encode (IEC 61966-2-1, formula continued above 1, linear segment continued below 0) → premultiply. The post-pass is the exact inverse. This reproduces "blurring encoded values" as gamma-space renderers do (STACK §7).
- **Straight alpha**: the pre-pass un-premultiplies (the colour of a fully transparent pixel is 0), the blur runs on straight values, and the post-pass premultiplies. This produces SPEC P19's dark fringes.
- Both: un-premultiply → encode (stays straight) before; decode → premultiply after.
- Parity for sRGB-encoded runs compares **encoded** values, the domain the blur ran in. The decode post-pass amplifies encoded-space differences by up to 2.3×, which is MEASURED in §7.

### 4.3 Edge modes (identical index mapping on CPU and GPU)

`EdgeMode` (§5.2) and `b2_map_index` in `B2Shared.h` implement exactly this mapping. `EdgeMode.shaderIndex` gives the value of function constant 2.

| Mode | Index i outside [0, n) maps to | Sampler for filtered (bilinear) fetches |
|---|---|---|
| `clamp` (0) | min(max(i, 0), n − 1) | `address::clamp_to_edge` |
| `mirror` (1) | symmetric reflection with the edge texel repeated: j = i mod 2n (non-negative); j < n ? j : 2n − 1 − j | `address::mirrored_repeat` |
| `wrap` (2) | i mod n (non-negative) | `address::repeat` |
| `zero` (3) | contributes (0, 0, 0, 0) | `address::clamp_to_zero` |
| `renormalise` (4) | the tap is dropped and the remaining weights are renormalised (integer-tap FIR variants only, `VariantDescriptor.supportsRenormalise`) | none. Bilinear variants resolve to an integer-tap variant with a stated reason (`resolveVariant`); `ImageBuffer.bilinear` and `b2_sample` treat it as `clamp` |

Renormalising kernels record dropped taps in traces with weight 0 and `flags = 1`. **Every** traced pass ends with one `flags = 2` final record (`b2_trace_final`) whose running sum is the value the pass stores (after normalisation or selection); parity compares the output with it (§7 rule 5). Bilinear fetches on the CPU are emulated with the hardware's sub-texel quantization: `subTexelBits` and `subTexelRounding` in `ReferenceOptions`. The Mac rule (8 bits, round to nearest) is MEASURED on the **M1 Max only**: the Simulator forwards to the Mac GPU (research §2.7 item 2), so its agreement is not independent evidence (review fix E-6). In this synthesis, the emulation cut the worst Gaussian parity error from 3–15 fp16 ulps (exact fractions) to 2–3 ulps (8-bit, round to nearest) on the M1 Max. The app uses `ReferenceOptions.forDevice(probes)`: until This phone's sub-texel probe has run (automatically once, in the background, after the idle gate of §5.10; it is a ~1 ms dispatch), in-app parity of classes with a bilinear term is `reportOnly` with the caption `SUB-TEXEL RULE NOT YET MEASURED`.

**Mip chains** are built with an explicit 2 × 2 shader in the owning group's file (the CPU reference mirrors it), never with `generateMipmaps`, whose filter "may vary by feature family" (Apple docs, research §3.5). `generateMipmaps` remains only as a This phone probe.

### 4.4 Safe-dispatch rules (all GPU code; JF G-5, SDK §15)

1. `dispatchThreadgroups` only, and only through `GPUContext.dispatch2D`. Never `dispatchThreads`. Put a bounds check in every compute kernel **after** any threadgroup loads and barriers.
2. 2-D image kernels use 16 × 16 threadgroups; row and column tiles use 256 × 1 and 1 × 256 (passed as `preferred` to `dispatch2D`, recorded in `PassDispatch`). Both are halved by `threadgroupSize(for:)` until they fit `min(pso.maxTotalThreadsPerThreadgroup, facts.maxThreadsPerThreadgroup)`.
3. Threadgroup memory must stay ≤ `facts.maxThreadgroupMemoryLength` and ≤ 16 KB, unless a pipeline declares a device-only fast path gated on the runtime limit. Sizes are rounded up to 16 B. Tile memory is **dynamic** (`dispatch2D(threadgroupMemory:)`), sized from the actual radius, never a static `MAX_R` array. Tile budgets are computed by BlurCore functions with unit tests (the Simulator does not enforce them, GPU §2.7 item 3); example: the Gaussian compute tile is (256 + 2r) × 8 B (`GaussianOperator.computeTileBytes`; σ 4 → 2,240 B; fits 16 KB up to r = 896, so every σ in range). `dispatch2D` throws `budgetExceeded`.
4. No `access::read_write` textures: ping-pong instead. No filtered sampling of 32-bit float textures. Constant buffers ≤ 64 KB with 256-byte-aligned offsets; `setBytes` ≤ 4 KB.
5. SIMD-group reductions and scans (Apple7+) only behind `facts.supportsApple7`, with a threadgroup-memory fallback that `blur-gpucheck --apple2-limits` forces and tests.
6. Read mip levels back by blitting from a private texture (GPU §2.7 item 7). Never `getBytes` on a mip of a shared texture.
7. Debug runs on the phone use Metal API validation (`device-launch --validate`, §2 note 4). While the hold is active, Apple2 enforcement comes from `blur-gpucheck --apple2-limits`.

## 5. Frozen Swift interfaces

### 5.0 How the contract is delivered

The frozen interfaces are real, compiled, tested Swift in **`Documentation/interfaces/`**. Its paths mirror the repo. Appendix A is the same declarations generated body-free from those files (comments and signatures kept, bodies collapsed). **Where this prose and the files differ, the files win**: they are what compiles. The walking skeleton copies them as follows:

| Snapshot path | Status | Goes to | Owner after the skeleton |
|---|---|---|---|
| `Package.swift` | frozen | repo root, verbatim | SKEL (frozen) |
| `Sources/BlurCore/Core/*.swift`, `Sources/BlurCore/Math/KernelMath.swift`, `Sources/BlurGPU/Core/*.swift` | **frozen**, verbatim | same paths | SKEL (frozen) |
| `Sources/BlurCore/Interaction/*.swift` | public API frozen; bodies working | same paths | ENGINE (bodies and tests) |
| `Metal/B2Shared.h` | **frozen**, verbatim | `App/GPU/Shaders/B2Shared.h` | SKEL (frozen) |
| `Metal/B2Common.metal` | SKEL's file, verbatim | `App/GPU/Shaders/B2Common.metal` | SKEL (frozen) |
| `Metal/F2Gaussian.metal`, `Sources/BlurCore/Operators/F2/GaussianOperator.swift`, `Sources/BlurGPU/Pipelines/F2/GaussianLinearPipeline.swift`, `Sources/BlurGPU/Pipelines/F2/GaussianSeparablePipeline.swift` | working seeds (the two shared functions `b2_f2_gauss_linear_fs` and `b2_f2_gauss_separable_fs` keep their names and bindings) | same paths (`App/GPU/Shaders/F2Gaussian.metal`) | FAM-F2 |
| `Sources/BlurCore/Operators/<G>/<G>Catalog.swift`, `Sources/BlurGPU/Pipelines/<G>/<G>Pipelines.swift` | stubs; the **type names are frozen** | same paths | FAM-<G> |
| `Sources/BlurCore/{Specimens,Semantics,Content,Analysis,Calibration}/*`, `Sources/BlurGPU/{Measure,AppleTwins}/*` | seeds behind frozen type names (§5.5, §5.8) | same paths | TESTIMAGES, SEMANTICS, CONTENT-LAYERS, ANALYSIS, CALIBRATION, GPU-MEASURE, APPLE-TWINS |
| `Sources/blur-gpucheck/main.swift` | working seed | same path | GPUCHECK |
| `Tests/BlurCoreTests/SKEL/`, `Tests/BlurGPUTests/SKEL/` | SKEL's contract tests | same paths | SKEL (frozen; must keep passing) |
| `AppContract/**` | **frozen public signatures**; bodies are placeholders | split into the App files listed in §5.9 with working bodies | per §5.9 table |
| `Tools/ios-typecheck.sh` | verifies the snapshot itself | not copied | — |

Gate rule: the frozen files in the repo must be byte-identical to the snapshot (`diff -r`). The only exceptions are requests that INTEGRATE has applied, and INTEGRATE then updates the snapshot, regenerates Appendix A and logs the change in §14. Build the snapshot only from a copy outside iCloud: `rsync` it to `$TMPDIR`, then run `swift test --scratch-path …` and `Tools/ios-typecheck.sh <copy>`.

### 5.1 Identifiers, honesty labels, number formatting (`Core/Identifiers`, `Honesty`, `Formatting`)

- **Identifiers** are string-backed and `CodingKeyRepresentable`, so `[ParameterKey: …]` encodes as a JSON object in the Run log: `BlurID`, `VariantID`, `SpecimenID`, `ParameterKey`. Geometry: `PixelPoint` is a window pixel whose `centre` is (x + 0.5, y + 0.5); `ImageSize`; `PixelRegion.centred(on:side:inside:)` for the 128 × 128 parity crop. `Floor` carries `railLabel` (≤ 5 characters: `KERNL`), `tileLabel`, `title`, `eyebrow` (`FLOOR 4 · KERNEL`) and the floor's one `question` (SPEC §5.1). No screen re-types these strings.
- **Honesty.** `Provenance` has the six words. `Qualifiers` are `.unverified` (the value itself is words; `value` must be nil), `.weakSource` (a MODELED or REFERENCE number with a caption such as `UNVERIFIED PEAK`), `.sourcesDisagree`, `.simulator`, `.notThisDevice`, `.offscreen`, `.experimental` and `.cpu` (`LIVE · CPU`). `DeviceStamp.label` is the engraving that travels with MEASURED (`iPhone 15 Pro Max · iOS 27.0 · 14 Oct`; Simulator: `SIMULATOR (APPLE2 LIMITS) · …`). `BadgedValue` is the only way a number reaches the UI: value, text, unit, provenance, qualifiers, source, device, caption, `isInput` (inputs carry no badge) and the full spoken phrase.
- **`honestyViolations`** (tested on all generated content, §11.3) flags: a MEASURED number without a device; an UNVERIFIED value shown as a number; Simulator milliseconds; REFERENCE without a source; a number without a badge that is not an input; `weakSource` on a badge other than MODELED or REFERENCE; placeholder words (`todo`, `lorem`, `placeholder`, `tbd`, `fixme`); empty spoken text.
- **`BadgedLine`** (review fix E-51) is the type of every view-bound line that mixes words and numbers: the status row (`StatusLine` cases), σ-hold notices (`SigmaHoldResult.statusLine`), lesson look-for lines, MIN H lines, Difference MAX/RMS, captions. Its segments are `.text` (words), `.value(BadgedValue)` and `.literal` (deliberate digits: equations, coordinates such as `(447, 455)`, identifiers such as `3×3`, `F2`). `BadgedLine.honestyViolations` adds a lint: digits inside a `.text` segment. `NearestMatch.distance` and `LoupeReading.centreCode8` are `BadgedValue`s. Plain `String` view content with digits is allowed only in the CONTENT-LAYERS allow-list (equations in `ContentBlock.equation`, code), checked by its lint test.
- **SwiftUI-derived values** carry `.offscreen` on every surface (chip mark, VoiceOver, caption): anything from ImageRenderer or a Calibrate result for a SwiftUI subject. SEMANTICS and CONTENT-LAYERS test it (review fix P-34).
- **Formatting.** `NumberStyle` (decimals or significant digits, unit, spoken unit, count noun, grouping, explicit plus) is the one formatter. It prints U+2212 minus, groups thousands (`2,401`), switches to `7.1·10⁻⁴` outside 10⁻³…10⁶, prints `∞`, and speaks the same precision ("7.1 times 10 to the minus 4", "32 samples"). Factories: `BadgedValue.number(_:_:_:…)`, `.input`, `.words`, `.unverified`, `.notYetMeasured` (`–.––`). **No area formats a displayed number with its own code.**

### 5.2 Parameters, silent settings, deck (`Core/Parameters`)

- `ParameterSpec` has key, ALL-CAPS label, spoken label, `ParameterUnit`, `ParameterKind`, default, `ParameterScope` (`.blur`, or `.specimenExposure` for the EXPOSURE crown, which is applied at render time by the window pass, §4.1) and an optional one-line note. `unitLine` gives the readout's unit line (`SIGMA · PX`). `numberStyle` sets display precision = spoken precision = the fine step (Metro contract A.6).
- Kinds: `.continuous(ContinuousSpec)` with range, fine step, decimals, `StepScale` (`linear`, `oneTwoFive` for ε and K, `thirdStops` for f-numbers), `semanticStops` and meaning `bands`; `.integer(IntegerSpec)` with step, parity and a count noun; `.choice(ChoiceSpec)` (`prefersMenu` at 5+ options); `.toggle`; `.sequence(SequenceSpec)` (Kawase offsets); `.position` (handles).
- **Stepping is implemented once**: `ContinuousSpec.stepped(from:by:)` is one FINE detent or Stepper press (snapped to the grid, clamped; turning past an end returns the end value). `semanticStepped(from:by:stops:)` moves one named stop per call. `band(for:)` gives the serif meaning word, and `nominalLabel(for:)` the marked f-number (`f/2.8`). `IntegerSpec.stepped` honours parity. Crowns, Steppers, adjustable actions and VoiceOver all call these. A `SemanticStop` with an `id` (`"swiftui-regime-switch"`) is replaced at runtime by the measured value and drawn hollow while its provenance is INFERRED (SPEC §9.2).
- `SilentSettings` holds the five silent parameters (colour space, edges, alpha, accumulator precision, preview) plus the Compare › Precision axis fields (intermediate format; `SATCentring`, default `.plain`, the fp32 trap the lesson shows). `EdgeMode.map` and `shaderIndex` are the CPU half of §4.3.
- `DeckArrangement` A–E (and `.none(message:)`) is declared per entry (SPEC §9.1). The 98-pt slot never collapses.

### 5.3 Catalog entries (`Core/Catalog`)

`CatalogEntry` is everything static about one entry. It is built in the family's operator from CATALOG.md and SPEC §9.4/§10:

| Field | Feeds |
|---|---|
| `id`, `displayName`, `family` (title, question, eyebrow), `tier` (chip, `runsLive`) | strip membership (Tier 3 never on the Bench), Catalog rows and sections |
| `verdict`, `linearity`, `separability`, `properties`, `costClass`, `algorithmClass` | fingerprint chips and matrix, floor templates (SPEC §5.2), preview policy (`CostClass.isHeavyByDefault`, `FetchBudget`) |
| `signature` (verbatim CATALOG §2 with SPEC §17 fixes), `mathSymbol` (MATH chip) | card, floor headers, rail |
| `glyph` (`GlyphSpec`) | strip glyph, kernel-well face, catalog rows (drawn by `FootprintGlyph`) |
| `parameters`, `primary`, `deck` | hero, crowns, Steppers, Parameters panel |
| `variants` (`VariantDescriptor`: tier, class, cost, `runsOnGPU`, `supportsRenormalise`), `defaultVariant` | algorithm picker, GPU registry keys |
| `defaultSpecimen`, `handles`, `appleTwins` (`AppleTwinSpec`, with a Calibrate `subject` when runnable) | Bench defaults, handle overlay, floor 2 and Compare › Apple |
| `tell`, `neighbours`, `card` (`CardRows`: the six rows, each with its own badge) | fingerprint card TELL, NEAREST and six rows |
| `traceDepth`, `heroOrder` (0…11 in SPEC §4.1.2 order), `unverified`, `detailReference`, `sources` | Trace depth, strip order, Field guide |

The Gaussian seed shows a complete entry. `gaussian-integrated` and `discrete-gaussian-lindeberg` (CATALOG variant ids) are realised as the DISCRETISATION parameter of `gaussian-blur`, as SPEC §9.4 specifies, not as separate algorithm variants.

### 5.4 Images, colour, kernels, responses, pass plans (`Core/ImageBuffer`, `ColourTransform`, `Kernels`, `Math/KernelMath`)

- `ImageBuffer` holds linear premultiplied `SIMD4<Float>`. `fetch(_:_:edge:)` is the CPU `b2_fetch`. `bilinear(_:_:edge:subTexelBits:)` is the CPU `b2_sample` (Double, texel centres at i + 0.5). `roundedToHalf()` emulates `rgba16Float`. `crop`, `map`. `ScalarBuffer`, `VectorBuffer`, `AuxiliaryInputs` (depth, velocity, guide, mask, sub-frames, noise seed). `DifferenceStats.compare` gives max/RMS/argmax/8-bit steps/fp16 ulps.
- `SRGB`, `HalfFloat`, `Luma.rec709`, `ColourTransform.pre/post` (the §4.2 passes) and `NoiseHash` (PCG, bit-identical to `b2_pcg`/`b2_uniform`).
- `Kernel1D` (weights, origin, optional fractional offsets; `sigma`, `excessKurtosis`), `Kernel2D` (separable outer product, marginals), `PSF` (local or global; COMPUTED, or LIVE · CPU for adaptive blurs). `ResponseCurve` is the **signed** H(ν) (SPEC §17 item 3), with `minimum`, `nyquistValue` and `firstCrossing(of:)` (0.5 half amplitude, 1/√2 for −3 dB, 0 for the first zero). `ResponseQuery` selects axis, samples, maximum frequency, local point, amplitude, and continuous vs discrete. `ProfileCurve` is the quiet trace. `PassDescriptor` covers name, kind, fetches and taps per pixel, output scale and `traceable`. `PassPlan.phaseLine` is the status-row phase line (`74 FETCHES · 2 PASSES · LINEAR-SAMPLED`).
- `KernelMath` (frozen; the skeleton copies it): radius = max(3, ⌈k·σ⌉); `gaussianSampled`, `gaussianIntegrated`, `gaussianLindeberg` (e^(−t)·I_n(t) by Miller's recurrence), `box`, `tent` (σ² = r(r + 2)/6), `binomial`, `convolve`, `linearSampledTable` (Rákos pairing (1,2), (3,4)…; tap order centre, +o₁, −o₁, +o₂, …), `response` (phase-centred real part; equals H for symmetric kernels), `gaussianResponse`, `gaussianMassBeyond` (continuous erfc(r/(σ√2)) = 0.27 % at r = 3σ; the Kernel floor prints the **discrete** per-axis and 2-D mass the finite kernel drops, with the continuous value in details, review fix P-63), `normalCDF`. All SPEC §5.3 A Gaussian fixtures pass against it (§11.3).

### 5.5 Operators, registries, service seams (`Core/Operator`, `Registry`, `Services`)

`BlurOperator` is the behaviour of one entry: a Sendable value type in `Sources/BlurCore/Operators/<G>/`, listed in `<G>Catalog.operators`. Its requirements, and who calls them:

| Requirement | Purpose | Callers |
|---|---|---|
| `entry` | static facts (§5.3) | everything |
| `passPlan(_:)` | passes and fetch counts of the **resolved** variant (COMPUTED) | ALGO chip, phase line, Algorithm floor, cost model, pass tiles, Trace |
| `psf(at:_:content:)` | PSF at a pixel (global, local, or LIVE weight map); nil for rank and global filters | KERNEL pill, Kernel floor, PSF field, fingerprint |
| `response(_:_:content:)` | signed H, local H, or T(ν, A); nil for rank filters | FREQ pill, Math floor, fingerprint H glyph |
| `continuousProfile(_:)` (default nil) | quiet reference trace | pills, Math floor |
| `sigma(_:)` | per-axis second moment of the discrete PSF, or nil | σ EFF, σ-hold source, SLIDE chip |
| `holdingSigma(_:current:)` | σ-hold conversion: achieved σ, `isClamped` when a range limit binds, and a `BadgedLine` built with `SigmaHoldResult.standardLine` (`σ HELD 12.0 px → σs 8.0 px (MAX) · Δσ −4.0 px`; review fix P-38) | blur strip, Catalog, Compare MATCH σ |
| `reference(_:_:auxiliary:options:)` | the CPU reference of the resolved variant, in Double, on **pre-transformed** values (never applies colour or alpha) | `BlurReference.run` → gpucheck, in-app parity, Compare › Implementation (CPU), Tier 3 floor 7 |
| `referenceCrop(…)` (default: full reference cropped) | the 128 × 128 parity crop with an apron of `passPlan.supportRadius`. **Required** override for every entry whose cost class `isHeavyByDefault` (O(r²), ITER, SEARCH), except global operators (FFT, IIR); each such area adds a CORE test that `referenceCrop` equals the full reference cropped at 256 for every edge mode (review fix E-8). Operators may parallelise over row bands with `DispatchQueue.concurrentPerform`; results must be bit-identical | in-app PARITY telemetry, `blur-gpucheck` at 894 |
| `traceReconstruction(…)` | COMPUTED tap rows beside GPU records, and the trace itself where no GPU record exists | Trace |
| `facts(_:_:)` (default `.empty`) | blur-specific floor content; generic templates fill the rest | page builder |
| `uniqueNumber(_:)` | the card's UNIQUE row (SPEC §7.2) | fingerprint |
| `floorKey(_:_:)` | per-floor comparison key (SPEC §8.4) | divergence, Compare rail `= / ≠` |
| `resolveVariant(_:)` (default: as requested) | automatic fallbacks with a reason (`2-D DIRECT ABOVE σ 8 · USING SEPARABLE`, `GATHER ABOVE BUDGET · USING ROW-SPAN SAT`) | engine, status row, GPU registry lookup |
| `disabledReason(_:_:)` (default nil) | disabled option captions (`2-D direct: disabled above σ 8 · 2,401 taps per pixel`) | Parameters panel |
| `statusWarning(_:)` (default nil) | sampling or budget warning for the status row | Bench |
| `isHeavy(_:)` (default from the cost class) | reduced-resolution preview while moving | RenderScheduler |
| `previewRequest(_:scale:)` (default below) | the request at preview scale, or nil = no honest preview (render full, `RENDERING…`) | RenderCoordinator |
| `previewScale(_:)` (extension, not overridable) | nil (full), 0.5, or 0.25 from `isHeavy` and `FetchBudget.preview` | RenderScheduler |

`BlurReference.run(op, input:, request, auxiliary:, options:, exposureEV:)` and `BlurReference.runCrop(…, region:, …)` are the only ways references are run. They round the input to fp16 (when `emulateHalfStorage`), apply 2^EV and round again, apply `ColourTransform.pre`, call the operator (`reference` or `referenceCrop`), apply `post`, and round the output. `ReferenceOptions.parity` is the Mac rule (`emulateHalfStorage: true, subTexelBits: 8, subTexelRounding: .nearest`); `ReferenceOptions.forDevice(probes)` is this phone's MEASURED rule or nil; `.exact` turns both off (the Precision lesson's truth). Operators are pure and deterministic: no global mutable state, safe to call from any thread.

**Previews** (review fixes E-4, P-36; frozen in `Operator.swift`). While a control moves, `previewScale` picks 0.5 for heavy entries or plans above `FetchBudget.preview` (2·10⁸ fetches per frame, MODELED ≈ 13 ms on the A17 Pro, UNVERIFIED), and 0.25 when even the half plan exceeds it. The input is the frozen 2 × 2 mean of the window (§4.1). `previewRequest`'s default scales `px`, `texels` and position values by the scale; integers become max(1, round(x·s)) (0 stays 0 in lists); `px²` (diffusion time) scales by s²; counts, ratios, angles and choices are unchanged; selection (rank) filters, system entries and atlas pages return nil (no preview). Probes and integer handles map by `PixelPoint.previewMapped` (⌊p·s⌋). Operators override where the default would change the blur's character (Kawase offset sequences, pixelate cells, NLM patches). Previews are never timed, traced or parity-checked, never publish PIXEL, loupe, pills, telemetry or Trace (those hold their last full values, marked `HELD`), and the caption reads `PREVIEW ½` or `PREVIEW ¼`.

**Budgets** (review fix E-7; `FetchBudget`). `PassPlan.fetchesPerFrame(size)` is COMPUTED for every request. Above `FetchBudget.full` (2·10⁹), `resolveVariant` switches to a cheaper variant with its reason (disc gather → row-span SAT; 2-D Gaussian → separable; NLM search capped at 11), or the parameter's range ends where the budget does (`disabledReason` says so); timing is skipped (`TOO SLOW TO TIME · ≈ x ms MODELED`). Full renders whose MODELED time (fetches ÷ `FetchBudget.modeledFetchesPerSecond`) exceeds 50 ms are encoded as horizontal bands, one command buffer each, so the compositor keeps getting GPU time. Whether iOS 27 kills a ≥ 1 s command buffer is UNVERIFIED; the budget keeps every command buffer far below it.

**Registries (frozen names; owners fill their own types):** `BlurRegistry.operators` is the concatenation of `F1Catalog … F11Catalog`, with `byID`, `op`, `entry` and `stripOrder` (hero dozen by `heroOrder`, then families F1…F11, then contrast). `SpecimenRegistry.generators = SpecimenCatalog.generators`. `BlurServices`: `floors = FloorPageBuilder()`, `traceScripts = TraceScripter()`, `fieldGuide = FieldGuideLibrary()`, `lessons = LessonLibrary.all` (CONTENT-LAYERS); `divergence = DivergenceEngine()`, `fingerprints = FingerprintEngine()`, `costModel = CostModel()` (ANALYSIS); `tools = ToolConventions()` (SEMANTICS); `psfFitter = PSFFitter()` (CALIBRATION).

**Service protocols:** `FloorPageBuilding` (pages, page, railChips, pills), `TraceScripting` (steps), `DivergenceComputing` (seven `FloorComparison`s; the first difference is `.partsWays`), `FingerprintComputing` (vector at σ_equiv = 4 px, vector from a measured shape, nearest), `ToolConventionProviding` (typed value per tool for a σ and its reverse; a measured `CalibrationLaw` replaces the macOS law; unknown mappings return `.unverified`), `CostModeling` (bytes, floors, cost curves) and `FieldGuideProviding` (page, honesty legend, lens note). Compare vocabulary: `CompareAxis`, `MatchRule`, `CompareView` (`differenceGain`), `Lesson`/`LessonKind`.

### 5.6 Test images (`Core/Specimens`)

`SpecimenGenerating.canvas(windowSize:margin:options:text:)` is deterministic: the same arguments give a bit-identical canvas on every platform (generators use only +, −, ×, ÷, √ and BlurCore's own transcendental functions, and a phone AppTest compares canvas hashes with the Mac hashes, review fix E-22). Canvases are generated and cached at 0 EV (`SpecimenOptions.canvasOptions`). `SpecimenGeometry.margin` is 256 and the centre pixel is c = (⌊N/2⌋, ⌊N/2⌋); geometry is evaluated at **pixel centres** (x + 0.5, y + 0.5) in window coordinates, y down, with angles θ measured from +x towards +y (screen-clockwise); the continuous centre of radial images is c + (0.5, 0.5) (SPEC §11 rule 2). `SpecimenCanvas.window(pan:)` returns the N × N window **and** its cropped auxiliary buffers as `OperatorContent`, exactly as the GPU blit copies them. Default probes are defined relative to features, not coordinates (SPEC §11 rule 3). Text coverage comes from the app (`SpecimenPlatform.textCoverage`, Core Text), so BlurCore stays Foundation-only. Photos become canvases through `SpecimenPlatform.photoCanvas`.

### 5.7 The Run record (`Core/Run`, `Core/Parity`)

One immutable `Run` (Sendable, Codable) per acknowledged render or measurement. Screens only read Runs (SPEC §3 state model; JF G-1):

| Field | Badge | Read by |
|---|---|---|
| `kind` (display, timing, trace, fingerprint, parity, calibration, probe), `generation`, `slot` (A–D), `configuration`, `resolvedVariant`, `quality` | inputs | engine, status row (`RENDERING…` while requested ≠ acknowledged), Run log |
| `device: DeviceStamp`, `gpu: GPUFacts` (limits read from the device, or forced Apple2) | MEASURED | every MEASURED engraving; floor 6 limits |
| `kernel: KernelSummary` (σ_eff, kurtosis, fetches, taps, pass names, the **uploaded** Float tables) | COMPUTED | σ EFF, Kernel floor "the exact numbers the GPU receives" |
| `dispatch: [PassDispatch]` (encoder kind, functions, threadgroup geometry, static and dynamic threadgroup memory, SIMD width, pipeline max threads, output size, `.shaderWrite`, modeled bytes) | COMPUTED / MEASURED / MODELED | floor 6 Silicon, Trace GPU steps |
| `timing: TimingSummary?` (method, warm-ups, samples, stop reason, median and IQR of the **blur passes only**, per-pass, colour/copy overhead separately, fused overhead, ABAB, thermal at start and end, Low Power Mode); **nil in the Simulator** | MEASURED | GPU chip, telemetry, pass timeline, ΔGPU, Run log |
| `cost: CostSummary?` with its `BandwidthAssumption` (`a17ProLeak` is 51.2 GB/s, `weakSource`) | MODELED | bytes, floors, ghost bars |
| `parity: ParitySummary?` (stats, region, tolerance, passed) | MEASURED | PARITY telemetry, floor 7 |
| `probe: ProbeReadout?` (input, output, per-pass values; full-quality Runs only) | LIVE | PIXEL chip, loupe, floor 7, periscope line |
| `shape: ShapeMeasurement?` | MEASURED | ON THIS PHONE, LOOKS MOST LIKE |
| `shader: ShaderProvenance?` (combined and file SHA-256, functions, math mode, language version, traced) | REFERENCE | Shader tab |
| `trace: TraceRecord?`, `calibration: CalibrationResult?`, `deviceProbe: DeviceProbeResult?` | per §5.12, §5.13 | Trace, Calibrate, This phone |

`ParityTolerance`, `ParityDomain`, `ParityEvaluation` and `ParityCase` are the data of §7.

### 5.8 The GPU contract (`Sources/BlurGPU/Core`)

- **`GPUContext`** (`@MainActor final class`, one per process) owns the device, queue, library, `ShaderManifest`, math mode and `facts: GPUFacts`. It specialises pipelines from the precompiled library, never from source on the device. **Pipeline compiles never run on the main actor** (review fix E-3; 59–417 ms per specialisation MEASURED by JF on the M1 Max): `computePipeline` and `renderPipeline` are `async`, compile in a detached task (only Sendable values cross: library, device, `FunctionConstants`, the pipeline state; this SDK has no async overloads of `makeFunction(name:constantValues:)` or `make…PipelineState`, MEASURED by the compiler's "no async operations" diagnostic) and coalesce in-flight compiles per cache key. `preparedComputePipeline` / `preparedRenderPipeline` are cache-only lookups that throw `GPUError.notPrepared`; `encode` uses only these. `prepareCommonPipelines()` builds the eight colour-pass specialisations, the window pass and the preview downsample once at launch. Also: the texture pool (`texture(_:)`, `recycle(_:spec:)`, `recycle(_ encoded:)` for an encode's transient textures, review fix E-27); `buffer(_:)`; `traceBuffer(passes:capacity:probe:)`; `threadgroupSize(for:)` and `dispatch2D` (§4.4; `dispatchLog` only when built with `recordsDispatches: true`, i.e. gpucheck and tests, so the app's log cannot grow, review fix E-17); `upload(_ HalfImageData)`; `encodeWindowCopy(…, exposureEV:)`; `encodeDownsample2x`; `encodeColourPass`; `encodeFullBlur` (pre-pass → pipeline → post-pass); `encodeReadTexels` (readback inside a render's recorder); `commit(_:)`, which awaits a completion as a Sendable `GPUCompletion` through a continuation; `readTexels(_:region:level:)` (stand-alone blit readback); and `decodeRGBA`.
- **`GPUCommandRecorder`** (`@MainActor`) hands out **one encoder per pass**: `computeEncoder(pass:label:)`, `renderEncoder(pass:descriptor:label:)`, `blitEncoder(pass:label:)`, and `noteExternalPass` for MPS and Core Image. `PassIsolation` maps passes to command buffers: `.singleCommandBuffer` for display and parity; `.commandBufferPerPass` for per-pass times without counters; `.stageBoundaryCounters`, which attaches a `PassTimestampSampling` (implemented by GPU-MEASURE) to every pass descriptor. Pass indices below 0 (`prePass`, `postPass`) are untimed preamble work; under `.commandBufferPerPass` they get their own command buffers, so the post-pass never inflates the last blur pass's time (review fix E-19). `commitAndWait()` commits in order and returns every completion. `passMilliseconds(_:)` maps them to passes. `encodeLog` records (pass, kind, label) for gpucheck.
- **`GPUBlurPipeline`** (`@MainActor` protocol, one class per (blur, variant)) declares `blur`, `variant`, `shaderFile`, `functionNames` and `writesDestinationFromCompute`, and implements `prepare(_:request:) async throws` and `encode(_:_:trace:recorder:) -> EncodedBlur`. **Encode rules:**
  1. One encoder per plan pass, obtained from the recorder with the plan's pass index.
  2. Never commit, wait or read back.
  3. Never handle colour space or alpha.
  4. Weights and offsets come from the operator (BlurCore Double → Float). Return them in `EncodedBlur.uploadedWeights/Offsets` (for merged-tap variants these are the pair tables, not the stems).
  5. Scratch textures are owned by the pipeline instance and reused; intermediates stay valid until the **next encode on that instance**. **Instance cardinality** (review fix E-11): the RenderCoordinator keeps one display instance per (slot, blur, variant) and separate instances for timing and for parity, so the 18 timing runs and Compare's other slots never overwrite the intermediates the periscope, Algorithm floor and Trace show; Trace and periscope readbacks happen before the slot's next display encode.
  6. `prepare` builds, asynchronously, **both** TRACE_PROBE specializations of every traceable pass for the request's edge mode (pre-warm, JF G-7). It runs when the variant, edge mode or window size changes and when Trace is pushed; the RenderCoordinator awaits it and keeps the previous Run on screen with `RENDERING…`. After the idle gate (§5.10) the coordinator pre-warms the hero dozen's default variants × {clamp} × {untraced, traced} in the background; other edge modes compile on first use. Persisting an `MTLBinaryArchive` is optional (not frozen).
  7. `encode` never compiles: it uses `context.prepared…Pipeline`, which throws `notPrepared` on a cache miss.
  8. With a `TraceRequest` (always `TraceRequest.sized(probe:plan:)`: capacity = the largest traced `tapsPerPixel` + 1, review fix E-13), bind block `p` of the trace buffer at offset `p × TraceLayout.passStride(capacity:)` for pass `p`, set the block's probe to the pixel that pass computes for the probe, end every traced pass with one `b2_trace_final` record (`flags = 2`, the stored value), and return `tracedPassIndices` and `traceCapacity`.
  9. Return one `PassDispatch` per pass.
- **`GPUPipelineFactory`** (Sendable: `make` is a `@MainActor @Sendable` closure; `parityCases(windowSize)` is a nonisolated static function) and **`GPUPipelineRegistry`** (`F1Pipelines … F11Pipelines`; `factory(blur, variant)`). Every factory publishes parity cases: every SPEC fixture its entry touches; at least one `checkTraced` case per Tier 1 traceable variant; at least two edge modes; the sRGB-encoded and straight-alpha paths at least once per group (rank classes are evaluated with `ParityTolerance.adjusted(for:)`, which turns a bit-exact class into `fastMath` when a colour pass runs, review fix E-18); and at least one HDR case (Night City or an impulse ×100 at +4 or +6 EV).
- **`GaussianPassEncoder`** (frozen, review fix E-14): the one shared Gaussian stage, `prepare(_:form:edgeMode:)` and `encodePass(_:form:kernel:direction:edgeMode:source:destination:passIndex:label:trace:recorder:)`, with forms `.integerTaps` (`b2_f2_gauss_separable_fs`, renormalise-capable) and `.linearSampled` (`b2_f2_gauss_linear_fs`). SKEL wrote both functions and the helper, and both F2 seeds use it, so F4, F10, F11 and DoG depend on proven code, not on FAM-F2's wave-1 internals.
- **`TraceLayout`**: a 32-byte header (probe, tap count, pass index, capacity, overflow) and 64-byte taps (position, weight, flags, fetched, running sum, extra), identical to `B2TraceHeader`/`B2TraceTap`. `decode(_:passes:capacity:)` with `EncodedBlur.traceCapacity`.
- **Value types:** `FunctionConstants` (shared indices 0–3 always set; `family` constants in the file's block, §6.2; `cacheKey`), `TextureFormat`, `TextureRole`, `TextureSpec`, `TraceRequest`, `GPUCompletion`, `GPUAuxiliaryTextures`, `GPUBlurInputs`, `EncodedBlur` (with `traceCapacity` and `transientTextures`), `PendingReadback`, `GPUError` (with `notPrepared`).
- **Services** (`@MainActor` protocols, installed in `GPUServices` at launch): `GPUTimingMeasuring` (`TimingService`; **budgeted and cancellable**, review fix E-7: `TimingRequest` stops at 15 samples or 1 s of summed GPU time with at least 3, checks `Task.isCancelled` between command buffers, times the blur passes only and the colour/copy overhead separately, and is never called above `FetchBudget.full`), `DeviceProbing` (`DeviceProbeService`), `ShapeMeasuring` (`ShapeService`), all GPU-MEASURE; `AppleTwinRunning` (`AppleTwinRunner`, APPLE-TWINS).
- **`ParityRunner`** (§3.2, §7): `compileLibrary(device:shaderDirectory:safeMath:)` and `run(_:factory:context:text:regions:referenceOptions:) -> ParityOutcome` (`ParityEvaluation` + `TracedComparison`). The GPU half runs on the main actor; canvas generation, fp16 conversion, the reference and the local scale run in detached tasks (review fix E-8).
- **`ShaderManifest`**: `assemble` (the single translation unit), `make`, `load(from:)` (verifies every bundled file's SHA-256 and computes the combined one), `sha256`.

### 5.9 App state ownership (`App/Engine` and cross-area views)

The `AppContract/` files freeze public signatures. The skeleton splits them into these files with working bodies:

| Contract file | Repo file(s) | Owner after the skeleton |
|---|---|---|
| `Engine/EngineTypes.swift` | `App/Engine/EngineTypes.swift`: `Route`, `CatalogRoute`, `FieldGuideRoute`, `CatalogTab`, `FieldGuideTab`, `SheetDestination`, `CompareState`, `CompareChoice`, `WindowViewState`, `RenderPhase`, `StatusLine`, `BenchSnapshot`, `ProbeJump`, `LaunchScenario`, `LoupeReading`, `NearestMatch`, `FingerprintCardModel`, `RenderRequest` | SKEL (frozen) |
| `Engine/EngineAPI.swift` | `App/Engine/{AppSettings, TelemetryModel, RunLogStore, SpecimenStore, RenderCoordinator, TraceSession, BenchModel}.swift` | ENGINE |
| `Render/PresentAPI.swift` | `App/Render/PresentRenderer.swift`, `App/Bench/SpecimenWindow/MetalSpecimenView.swift` (+ `PresentMode`, `PresentOptions`) | UI-SPECIMEN |
| `DesignSystem/ComponentAPIs.swift` | `App/DesignSystem/<Component>.swift` (§5.14) | METRO-COMPONENTS |
| `Content/ContentViewsAPI.swift` | `App/Content/{FloorPageView, ContentBlockView, FigureView, LabeledValuesView, ShaderSourceView}.swift` | CONTENT-VIEWS |
| `Fingerprint/FingerprintAPI.swift` | `App/Fingerprint/FingerprintCardView.swift` | UI-ATLAS |
| `System/SystemAPIs.swift` | `App/System/{SystemExhibitView, SystemOffscreen}.swift`; `App/Specimens/SpecimenPlatform.swift` | FAM-F10; TESTIMAGES |
| `Calibration/CalibrationAPI.swift` | `App/Calibration/{CalibrationService, MeasureEdges, CalibrationEdgeView}.swift` | CALIBRATION |

**Who owns which state:**

- `BenchModel` (`@MainActor @Observable`) is the single source of truth for **requested** state: configuration, view state, compare state and navigation (`path: [Route]`, `sheet: SheetDestination?`). Controls write it and show requested values at once. The **image** follows `acknowledged[slot]`, the newest completed Run of any quality. Every **measurement-derived** value (PIXEL chip, loupe, pills, telemetry, Trace, pass intermediates, the kernel-well face and ±3σ bracket) follows `lastFull[slot]`, the newest full-resolution Run, and is marked `HELD` while a preview is on screen (review fix P-36, P-66). Its intents are listed in Appendix A (`selectBlur` with σ-hold, `step(_:by:semantic:)` for crowns, `setProbe`, `jumpProbe`, `setPan`, `setZoom`, `setSplit`, `showPass`, `setLoupe`, `moveHandle`, the compare intents, `apply(lesson)`, `floorPages`, `makeTraceSession`, `fingerprintCard`, `divergence`, `fieldGuidePage`, `handleLaunch`, `snapshot`, `tick`).
- `RenderCoordinator` (`@MainActor`) owns all GPU work for the app. It renders a `RenderRequest` (latest wins, one render in flight per slot), times, checks parity, renders the fingerprint strip, and holds the display textures and pass intermediates per slot. Textures never leave it, and it returns Runs.
- `TelemetryModel` is observed **only** by the telemetry leaf views (Toothpaste lesson). `AppSettings` holds the Settings values with `load`/`save` in UserDefaults. `RunLogStore` is the persisted, exportable Run log (`deviceProbes` and `calibrations` feed `LiveFacts`). `SpecimenStore` caches canvases generated off the main actor. `TraceSession` is the walk; while it is open the slot renders with the traced specialization (§5.12).
- **The render loop.** A control changes → `BenchModel` intent → `RenderScheduler.requestChanged(at:preview:interacting:)` (cancelling measurements in flight) → `RenderCoordinator.render` (at `op.previewScale` while interacting) → `Run` → `RenderScheduler.acknowledge` → publish the image (and, for full Runs only, rail, pills, probe and telemetry). Then `tick`: after 300 ms settled, a full-resolution render, then **budgeted** timing (3 warm-ups, up to 15 samples or 1 s of GPU time, skipped above `FetchBudget.full`), then parity on the 128² crop at background priority with `ReferenceOptions.forDevice`, then Runs into the log. Every touch cancels timing and parity between command buffers (`RenderScheduler.touchBegan`). No timing per detent (JF M-4); nothing measures in the first 10 s (SPEC §2). After the idle gate (§5.10) the coordinator, once per launch and in the background: runs the sub-texel probe (§4.3) and pre-warms the hero dozen's pipelines (§5.8 rule 6).
- **First frame.** Rendering is asynchronous and launch never blocks the main thread: until the first Run arrives the housing shows the sharp INPUT window (a real image, uploaded as soon as the canvas exists), with `RENDERING…` in the status row and no spinner (review fix E-25).
- **Navigation.** `RootView` is `NavigationStack(path: $bench.path) { BenchView() }` with `.navigationDestination(for: Route.self)` and ONE `.sheet(item: $bench.sheet)` (METRO §F.5 item 3). The Catalog and Field guide sheets have their own `NavigationStack` with `CatalogRoute` / `FieldGuideRoute`. Calibrate from This phone is a push, not a second sheet.
- **Launch scenarios** (`-B2Scenario <name> [-B2Blur id] [-B2Specimen id] [-B2Floor n] [-B2Param k=v]`) put the app into a SPEC screen for screenshots on the phone (§11.4). They are parsed by `LaunchScenario.parse` and applied by `BenchModel.handleLaunch`.

### 5.10 Interaction logic (`Sources/BlurCore/Interaction`)

- `SpecimenGestureArbiter` (pure state machine, unit-tested): priority **handle drag > pinch > long-press loupe (0.35 s within 8 pt) > one-finger drag (pan, > 8 pt) > tap (probe)**. After a pinch it ignores the remaining finger until every touch has lifted (`.draining`), and a loupe lifted outside the window is cancelled. The UIKit touch layer forwards raw touches and a 30 Hz `tick` while one finger rests, then performs the returned `GestureIntent`s.
- `CrownDetentTracker` (verbatim Metro Station port: at most one step per update, 18 % reversal hysteresis, the first touch never changes the value) and `DetentRateLimiter` (≤ 20 accepted detents per second). The 7-pt centre exclusion is applied by `InstrumentCrown` before the angle reaches the tracker.
- `RenderScheduler`: every accepted change renders at once, at the operator's preview quality while interacting; after `settleSeconds` (0.3) a full render, then `startTiming`, once per generation; `cancelMeasurements` on every later change or touch (`touchBegan`); `acknowledge` is monotonic (a stale render never overwrites a newer one); `isRendering` drives the status row.
- `CalibrationIdleScheduler`: automatic SwiftUI calibration only at ≥ 10 s since launch **and** ≥ 3 s since the last touch, with no control active and thermal state nominal or fair (SPEC §2, §13.2; JF M-3). The same gate releases the one-time sub-texel probe and the pipeline pre-warm.

### 5.11 Layer content model (`Core/Content`; renderers in `App/Content`)

Pages are data: `FloorPage` (eyebrow, question, signature, dominant badges, governing rule, one `FigureSpec`, **at most six** `LabeledValue`s, `details: [ContentBlock]` behind `All … details`, optional `FloorTab`s, the `IN THIS APP` line and an honest empty state). `FloorFacts` is an operator's contribution; `FloorPageBuilder` merges it with the class templates of SPEC §5.2 and live Runs (`LiveFacts`). The figures are `.plot(PlotSpec)` (axes with units and "normalized", typed series roles and styles, markers, zero line, accessibility summary), `.heatmap`, `.texelGrid`, `.dispatchOverlay` (drawn over a **copy**), `.passTiles`, `.psfField`, `.toolBars`, `.code`, and `.pair`. The blocks are paragraph, equation, values, table, code, figure, note, chips, sources and disclosure. `RailChip` (≤ 6 characters, glyph badge, Compare comparison), `PillPlot`/`PillContent` (KERNEL wave, FREQ spectrum, `emptyText` engraved when there is no honest plot) and `FieldGuidePage` complete the model. One model feeds the rail, pills, floors, Trace panels, Divergence rows and Field guide (JF M-12). `CONTENT-VIEWS` renders it with the frozen views `FloorPageView`, `ContentBlockView`, `FigureView` (Swift Charts + `AXChartDescriptor` + a data-table disclosure), `LabeledValuesView` and `ShaderSourceView`.

### 5.12 Pixel-trace model (`Core/Trace`)

`TraceRecord` (input, passes, GPU output, CPU reference, ulp difference, traced = untraced) → `TracePass` (descriptor, `TraceSource`, the pixel that pass computed, taps, truncated count, output at the probe, 9 × 9 neighbourhoods read from the **real intermediates**) → `TraceTap` (position in texel coordinates, offset, contributing texels and fractions, requested and quantized bilinear `t`, weight, fetched value, contribution, running sum, `dropped`, extras). `TraceSource.gpuRecord` is LIVE, because the GPU wrote it for the frame on screen; `.cpuReconstruction` is COMPUTED and is never labelled LIVE (JF M-6). `TraceScripter` turns a record into `TraceStep`s (floor, completed/next lines, primary label, `TraceSubStep`s with running sums and announcements, branch values, phase line, closing lesson). `TraceSession` walks them. While it is open, the Bench slot and periscope render the **traced** specialization, so the recorded taps and the displayed pixel come from one execution (JF G-7). The traced pipeline is prepared (asynchronously) when the Trace is pushed. Trace buffers are sized from the plan (`TraceRequest.sized`), so passes with more than 1,024 taps (2-D Gaussian above σ 5, disc gathers from R 19, NLM) record every fetch; each traced pass ends with its `flags = 2` final record (review fix E-13).

### 5.13 Calibration API (`Core/Calibration`; `App/Calibration`)

`CalibrationSubject` (16 subjects with titles; `isMainActorRendered` for the SwiftUI, Core Animation and Core Graphics ones), `CalibrationPath` (ImageRenderer `.cgImage` by default, `render(into:)`, the experimental `drawHierarchy`, and the Core Image, MPS, vImage, CG and CA paths), `CalibrationColourMode`, `CalibrationRequest` (the API's own parameter in its own unit, display scale, phases), `EdgeSamples` (normalised ESF in the working space, edge position, phase, encoded midpoint, optional 45° ESF), `PSFModel` (Gaussian, truncated Gaussian, box³), `ModelFit`, `PSFFit` (moment and least-squares σ, σ/(parameter·scale), excess kurtosis on the axis and at 45°, extent, support, centre spread over phases, encoded midpoint, shape name labelled INFERRED, model competition sorted by residual, LSF), `CalibrationResult` (with `DeviceStamp`), `CalibrationLaw` (small and large ratios, switch parameter, points; `sigmaPx(parameter:displayScale:)`) and `PSFFitting` (`fit`, `law`; `PSFFitter`, CALIBRATION). The app half: `measureEdges(_:blur:)` (`@MainActor`, ImageRenderer, 16 centre rows read in the working space) and `CalibrationService` (`@Observable`: `state`, `measure`, `runBasicSet`, `runSweep`, `pause`, `cancel`, `latest`, `law`, and the idle-gate hooks). A single ImageRenderer render is synchronous and cannot be pre-empted (the first one also compiles RenderBox pipelines), so the rule is: **one render per run-loop turn**, each timed; when a render exceeds 16 ms the gap before the next doubles (× 2 back-off, reset after a render under 16 ms); no render while any control is active; any touch pauses the queue (review fix E-21). Every result is a Run of kind `.calibration`.

### 5.14 Design-system component APIs (`App/DesignSystem`, METRO-COMPONENTS)

Frozen initialisers (Appendix A): `HonestyBadge(_:qualifiers:style:)` (`.word`; `.glyph` only on rail chips), `BadgedValueText(_:layout:)`, `DecimalParameterStepper(_:value:in:step:decimals:unit:spokenUnit:onAcceptedChange:)`, `InstrumentCrown(caption:subcaption:role:detentDegrees:isEnabled:accessibilityLabel:accessibilityValue:onStep:)`, `InstrumentSignalPill(_:family:comparisons:)`, `InstrumentEventTiles(_:height:onSelect:)` with `EventTile`, `InstrumentFloatingActionGroup(leading:primary:trailing:)` with `FloatingGroupHeightKey`, `SpecimenHousing(content:)`, `FootprintGlyph(_:size:isSelected:)`. METRO-COMPONENTS also owns `InstrumentPalette+Blur2ool.swift` (tokens from METRO §B, named from the manifest, never re-typed literals) and `ComponentGallery.swift` (the `gallery` launch scenario). The starter files are copied verbatim and never edited.

### 5.15 Swift 6 concurrency rules (binding)

1. Swift 6 language mode in every target. `SWIFT_DEFAULT_ACTOR_ISOLATION` stays `nonisolated`, and isolation is written explicitly.
2. **BlurCore is nonisolated and every public type is `Sendable`.** No global mutable state (registries are `static let` of Sendable values).
3. **GPU objects live on the main actor.** `GPUContext`, `GPUCommandRecorder`, pipelines, `RenderCoordinator`, `PresentRenderer`, `BenchModel` and the services are `@MainActor`. `MTLTexture`, `MTLBuffer`, `MTLCommandBuffer` and encoders never cross an actor boundary. Encoding is microseconds, so there is no actor-hopping engine (SDK §5). **Pipeline-state compilation is the exception**: it runs in a detached task on Sendable values (`MTLDevice`, `MTLLibrary`, pipeline states are `NS_SWIFT_SENDABLE`, READ from the iPhoneOS 27.0 SDK by the engineering reviewer), §5.8.
4. **Completion pattern** (frozen in `GPUContext.commit`): `withCheckedContinuation` + `addCompletedHandler`, capturing only Sendable values (`GPUCompletion`). Readback happens back on the main actor after the await. `waitUntilCompleted()` is unavailable from async code. `await commandBuffer.completed()` also typechecks (SPEC §17 item 19), but the continuation pattern is the one used, because it returns the timestamps and the error as one Sendable value.
5. **CPU-heavy work** (canvas generation, the fp16 conversion `HalfImageData`, references, floor pages, fingerprint vectors, fits, PSF fields) runs in `Task.detached(priority: .userInitiated)` (in-app parity: `.utility`) on Sendable inputs and returns through `await … .value`. Never rely on the default executor of a nonisolated async function to leave the main actor.
6. No `nonisolated(unsafe)` and no `@unchecked Sendable` on anything that holds a Metal resource or mutable state. A justified exception goes to the area's request file first.
7. `ImageRenderer` and the calibration renders are `@MainActor`, one render per run-loop turn with back-off (§5.13). Crowns and Steppers live outside every `TimelineView` (Metro contract A.7).

## 6. Metal shader layout and naming

### 6.1 Files, owners, prefixes, function-constant blocks

One `.metal` file per implementation group, all in `App/GPU/Shaders/`, all compiled by Xcode into the app's `default.metallib` and all loaded by `blur-gpucheck` as one translation unit. Contrast entries live in the file of the group that owns them (§8).

| File | Owner | Symbol prefix | Function constants | Contents |
|---|---|---|---|---|
| `B2Shared.h` | SKEL (frozen) | `b2_`, `B2_` | 0–6 shared (7–15 reserved) | §6.2, verbatim below |
| `B2Common.metal` | SKEL (frozen) | `b2_common_` | uses 4–6 | full-screen triangle, colour pre/post pass, copy |
| `B2Present.metal` | UI-SPECIMEN | `b2_present_` | 128–135 | present (1 : 1 nearest, zoom, split, wipe, flip, difference × gain, Line-up, periscope crop, loupe), SDR clip and EDR |
| `F1BoxTent.metal` | FAM-F1 | `b2_f1_` | 16–23 | box (separable, sliding sum, SAT scan and query), tent, stack blur, iterated box |
| `F2Gaussian.metal` | SKEL seed, then FAM-F2 | `b2_f2_` | 24–31 | Gaussian (2-D, separable, linear-sampled, compute tile), binomial, IIR (YvV, Deriche), unsharp mask, DoG/XDoG |
| `F3Pyramid.metal` | FAM-F3 | `b2_f3_` | 32–39 | Kawase, dual Kawase, mip chain, CoD and Unity 13-tap |
| `F4Frequency.metal` | FAM-F4 | `b2_f4_` | 40–47 | FFT engine (§6.4), exponential, Lorentzian, low-pass, FFT convolution, Airy, Wiener |
| `F5Motion.metal` | FAM-F5A | `b2_f5_` | 48–55 | line, anisotropic Gaussian, zoom, spin, path, streak |
| `F5Temporal.metal` | FAM-F5B | `b2_f5t_` | 56–63 | camera shake, velocity buffer (tile max, neighbour max, reconstruction), accumulation |
| `F6Lens.metal` | FAM-F6 | `b2_f6_` | 64–71 | disc (gather, row-span SAT, complex separable, stochastic), polygonal (MRT line passes, 2-D gather), cat's-eye, anamorphic |
| `F7Varying.metal` | FAM-F7 | `b2_f7_` | 72–79 | depth of field, tilt-shift and iris, variable blur, frosted glass |
| `F8EdgeA.metal` | FAM-F8A | `b2_f8a_` | 80–87 | median networks, bilateral (brute, separable, grid), joint bilateral, guided |
| `F8EdgeB.metal` | FAM-F8B | `b2_f8b_` | 88–95 | Kuwahara (classic, generalized, anisotropic), domain transform, surface blur, NLM |
| `F9Diffusion.metal` | FAM-F9 | `b2_f9_` | 96–103 | heat (explicit), Perona–Malik, morphology (van Herk), pixelate (square, hex) |
| `F10Materials.metal` | FAM-F10 | `b2_f10_` | 104–111 | material, Liquid Glass and CSS backdrop models (downsample, blur, colour stage, SDF refraction band) |
| `F11Uses.metal` | FAM-F11 | `b2_f11_` | 112–119 | drop shadow, bloom chain, god rays |
| `Probes.metal` | GPU-MEASURE | `b2_probe_` | 120–127 | device probes (sub-texel bits, copy, FMA throughput, compression A/B) |
| `../DesignSystem/InstrumentLensOptics.metal` | SKEL (verbatim) | `instrumentLensOptics` | — | Metro's SwiftUI lens shader; never in `App/GPU/Shaders` |

Groups may use the two shared Gaussian functions in `F2Gaussian.metal` from their own pipelines (bloom, drop shadow, materials, Lorentzian sum of Gaussians, DoG), **only through the frozen Swift helper `GaussianPassEncoder`** (§5.8): `b2_f2_gauss_linear_fs` and `b2_f2_gauss_separable_fs` (integer taps, renormalise-capable). Both were written by SKEL and are proven by the two F2 seeds' parity cases (review fix E-14); FAM-F2 may change their bodies only if those cases keep passing, never their names or bindings. No other cross-file function use is allowed: a group that needs another group's kernel copies it into its own file under its own prefix.

### 6.2 `B2Shared.h` (FROZEN, verbatim)

```metal
// B2Shared.h — Blur2ool shared Metal header. FROZEN (ARCHITECTURE.md §6.2); change only through build/requests/.
// Every App/GPU/Shaders/*.metal starts with exactly the line   #include "B2Shared.h"
// blur-gpucheck removes that line and prepends this file once (runtime compilation cannot resolve quoted includes),
// so this header uses include guards and every file-scope symbol in a family file carries that file's prefix.
#ifndef B2_SHARED_H
#define B2_SHARED_H
#include <metal_stdlib>
using namespace metal;

// ---- Function constants 0–15 are shared (Swift: FunctionConstants.metalValues() always sets 0–3) ----
constant bool B2_TRACE_PROBE    [[function_constant(0)]];  // record the probe's taps (traced specialization)
constant bool B2_HALF_ACCUM     [[function_constant(1)]];  // fp16 accumulation: the Compare › Precision lesson only
constant uint B2_EDGE_MODE      [[function_constant(2)]];  // 0 clamp, 1 mirror, 2 wrap, 3 zero, 4 renormalise
constant uint B2_DIRECTION      [[function_constant(3)]];  // 0 horizontal, 1 vertical, 2+ family-defined
constant bool B2_COLOUR_SRGB    [[function_constant(4)]];  // B2Common colour pass only
constant bool B2_ALPHA_STRAIGHT [[function_constant(5)]];  // B2Common colour pass only
constant bool B2_COLOUR_POST    [[function_constant(6)]];  // B2Common colour pass only
// 7–15 reserved. Family files own blocks of 8 from 16 upward (ARCHITECTURE §6.2 table); never declare them here.

// ---- Binding indices ----
#define B2_BUF_PARAMS   0   // per-pass parameter struct (setBytes ≤ 4 KB)
#define B2_BUF_WEIGHTS  1   // float weights (BlurCore Double → Float, the exact numbers the Kernel floor shows)
#define B2_BUF_OFFSETS  2   // float offsets (linear-sampled and fractional taps)
#define B2_BUF_AUX0     3   // family-specific
#define B2_BUF_AUX1     4   // family-specific
#define B2_BUF_TRACE    5   // trace block of this pass (only when B2_TRACE_PROBE)
#define B2_TEX_SRC      0
#define B2_TEX_DST      1   // compute passes only (fragment passes return their colour)
#define B2_TEX_AUX0     2
#define B2_TEX_AUX1     3
#define B2_TEX_AUX2     4

// ---- Edge index mapping: identical to BlurCore EdgeMode.map(_:count:). -1 = contributes zero / dropped. ----
static inline int b2_map_index(int i, int n, uint mode) {
    if (i >= 0 && i < n) return i;
    switch (mode) {
        case 0: return clamp(i, 0, n - 1);
        case 1: { int p = 2 * n; int j = ((i % p) + p) % p; return j < n ? j : p - 1 - j; }
        case 2: return ((i % n) + n) % n;
        default: return -1;
    }
}

// Integer fetch with the edge mapping (no filtering; any float format, including 32-bit).
static inline float4 b2_fetch(texture2d<float, access::sample> t, int2 p, uint mode) {
    int x = b2_map_index(p.x, int(t.get_width()), mode);
    int y = b2_map_index(p.y, int(t.get_height()), mode);
    if (x < 0 || y < 0) return float4(0.0f);
    return t.read(uint2(x, y));
}

// Filtered fetch at texel coordinates (centres at i + 0.5, as BlurCore ImageBuffer.bilinear). rgba16Float only, never
// 32-bit float. coord::pixel allows only clamp modes, so samplers use normalized coordinates. renormalise → clamp.
constexpr sampler b2_sampler_clamp (coord::normalized, address::clamp_to_edge,   filter::linear);
constexpr sampler b2_sampler_mirror(coord::normalized, address::mirrored_repeat, filter::linear);
constexpr sampler b2_sampler_wrap  (coord::normalized, address::repeat,          filter::linear);
constexpr sampler b2_sampler_zero  (coord::normalized, address::clamp_to_zero,   filter::linear);
static inline float4 b2_sample(texture2d<float, access::sample> t, float2 p, uint mode) {
    float2 uv = p / float2(t.get_width(), t.get_height());
    switch (mode) {
        case 1: return t.sample(b2_sampler_mirror, uv);
        case 2: return t.sample(b2_sampler_wrap, uv);
        case 3: return t.sample(b2_sampler_zero, uv);
        default: return t.sample(b2_sampler_clamp, uv);
    }
}

// ---- sRGB transfer (IEC 61966-2-1), identical to BlurCore SRGB (formula continued above 1, linear below 0) ----
static inline float b2_srgb_encode(float l) { return l <= 0.0031308f ? 12.92f * l : 1.055f * powr(l, 1.0f / 2.4f) - 0.055f; }
static inline float b2_srgb_decode(float e) { return e <= 0.04045f ? e / 12.92f : powr((e + 0.055f) / 1.055f, 2.4f); }
static inline float4 b2_unpremultiply(float4 c) { return c.a > 0.0f ? float4(c.rgb / c.a, c.a) : float4(0.0f); }
static inline float4 b2_premultiply(float4 c) { return float4(c.rgb * c.a, c.a); }

// ---- Trace records: layout identical to Swift TraceLayout (strides 32 and 64) ----
struct B2TraceHeader { uint2 probe; uint tapCount; uint passIndex; uint capacity; uint overflow; uint2 reserved; };
struct B2TraceTap { float2 position; float weight; float flags; float4 fetched; float4 runningSum; float4 extra; };

// Records one tap for the probe pixel only (`block` = this pass's header). flags: 1 = dropped by renormalise,
// 2 = the final record (b2_trace_final). Capacity = PassPlan.traceCapacity (largest tapsPerPixel + 1).
static inline void b2_trace_tap(device B2TraceHeader *block, uint2 pixel, float2 position, float weight, float flags,
                                float4 fetched, float4 runningSum, float4 extra) {
    if (pixel.x != block->probe.x || pixel.y != block->probe.y) return;
    uint i = block->tapCount;
    if (i >= block->capacity) { block->overflow += 1; return; }
    device B2TraceTap *taps = (device B2TraceTap *)(block + 1);
    taps[i].position = position; taps[i].weight = weight; taps[i].flags = flags;
    taps[i].fetched = fetched; taps[i].runningSum = runningSum; taps[i].extra = extra;
    block->tapCount = i + 1;
}

// Every traced pass ends with exactly one final record holding the value the pass stores for the probe pixel
// (after any normalisation or selection). Parity compares the output with this record (ARCHITECTURE §7 rule 5).
static inline void b2_trace_final(device B2TraceHeader *block, uint2 pixel, float2 position, float4 stored) {
    b2_trace_tap(block, pixel, position, 0.0f, 2.0f, float4(0.0f), stored, float4(0.0f));
}

// ---- Deterministic noise: PCG hash, bit-identical to BlurCore NoiseHash ----
static inline uint b2_pcg(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
static inline float b2_uniform(uint2 p, uint seed) { return float(b2_pcg(p.x ^ b2_pcg(p.y ^ b2_pcg(seed)))) * (1.0f / 4294967296.0f); }

// ---- Full-screen triangle output (vertex function b2_common_fullscreen_vs lives in B2Common.metal) ----
struct B2VertexOut { float4 position [[position]]; float2 uv; };

#endif // B2_SHARED_H
```

### 6.3 Kernel rules (every file except the verbatim starter)

1. The first line is exactly `#include "B2Shared.h"`. No other includes, and never `<SwiftUI/SwiftUI.h>`.
2. Every file-scope symbol carries the file's prefix: functions, structs (`B2F2GaussParams`), constants, samplers. No file-scope mutable state.
3. Function names are `b2_<prefix>_<entry>_<stage>_<kind>`, with kind `_fs` (fragment), `_vs` (vertex) or `_k` (compute). Examples: `b2_f2_gauss_linear_fs`, `b2_f1_box_satscan_rows_k`. Every name a pipeline uses appears in its `functionNames`.
4. Function constants: the shared ones (0–6) come from the header. Family constants are declared in the family file inside its block (§6.1) as `B2_<PREFIX>_<NAME>`, and the pipeline always sets them through `FunctionConstants.family`.
5. **Accumulate in `float` with explicit `fma()`**: `sum = fma(value, float4(w), sum)`. Only the first term may be a plain product. `half` accumulation exists only under `B2_HALF_ACCUM`, also with `fma`. This is what makes traced = untraced bit-exact under fast math. It was MEASURED by the feasibility judge on the M1 Max (JF §3.1) and again in this synthesis (§7.6).
6. **TRACE_PROBE.** Every traceable pass (all Tier 1 passes; the declared stage of Tier 2) takes `device B2TraceHeader *trace [[buffer(B2_BUF_TRACE), function_constant(B2_TRACE_PROBE)]]` and calls `b2_trace_tap` inside `if (B2_TRACE_PROBE)`, **after** updating the running sum. The kernel's tap order is written in a comment and mirrored by its operator's `traceReconstruction`. What `extra` carries is documented per kernel (bilateral: spatial weight, range weight; Kuwahara: sector mean and variance; median: rank). Flags: 1 = dropped by `renormalise`, 2 = the final record. **Every traced pass ends with exactly one `b2_trace_final(trace, pixel, position, stored)`** holding the value the pass stores (after normalisation, selection or division), so parity compares it with the output for every class, including bilateral, median and Kuwahara (review fix E-13).
7. Fragment passes draw the full-screen triangle `b2_common_fullscreen_vs` and use `pixel = uint2(in.position.xy)`. They return the colour into render targets created without `.shaderWrite` (lossless compression stays on, Apple9).
8. Compute passes are dispatched only through `GPUContext.dispatch2D` and bounds-check after barriers. Tile sizes come from BlurCore budget functions and `GPUFacts`, never a hard-coded 1024 or a static `MAX_R` array. Dynamic threadgroup memory is set through `dispatch2D(threadgroupMemory:)` at index 0. Row tiles are 256 × 1 and column tiles 1 × 256 (§4.4 rule 2).
9. Per-pass parameters are one prefixed struct passed with `setBytes` (≤ 4 KB) at `B2_BUF_PARAMS`. Tables go at `B2_BUF_WEIGHTS` / `B2_BUF_OFFSETS` as `constant float*` (≤ 64 KB); larger tables use `device const float*`.
10. Integer fetches use `b2_fetch` and filtered fetches use `b2_sample` (rgba16Float only). Stochastic kernels draw randomness only from `b2_uniform(pixel, seed)`.
11. Forbidden: `access::read_write`, `dispatchThreads`, filtering 32-bit float textures, the Metal 4 API, and `half` in buffers whose values reach a number on screen.
12. `// @explain: <one line>` on a line makes the Shader tab annotate it (SPEC §4.3).
13. `Tools/build.sh metal-check` compiles every file for `iphoneos` with `-Wall -Wextra` and links them into one `metallib`; there must be zero diagnostics. `blur-gpucheck` compiles them all as one translation unit.

### 6.4 FFT passes (FAM-F4; SPEC §5.2 "Global (FFT)")

- **Own radix-2 Stockham FFT** in `F4Frequency.metal`, so floor 6 can show the code that ran (MPSGraph would be a black box). P = 1024 at N = 894; 512 for the half-resolution preview at N = 447; 256 for the quarter preview at N = 223.
- **Packing.** Two complex planes share one `float4` element: (R + iG, B + iA). This is exact for real kernels, because the spectrum of x·h + i·y·h separates into the two real convolutions. The planes live in `device float4*` buffers: 16 MB per plane at P = 1024, ping-ponged.
- **Rows** run in threadgroup memory when P × 16 B ≤ `facts.maxThreadgroupMemoryLength` (on the A17 Pro, 32 KB holds P = 1024). Otherwise they use the multi-pass Stockham form through device memory, which `--apple2-limits` forces and tests. Columns use the same kernel with a strided layout.
- **Extension.** The P × P plane is filled from the N × N window, centred, with a 65-pixel margin at N = 894, by the case's padding: `zero`, `mirror` or `wrap` (periodic extension). For kernels with support beyond 65 px (Lorentzian tails, Airy), what spills is FFT wrap-around. That is the lesson, and the floor text says so (MODELED truncation of infinite kernels at P/2).
- **Spectra.** H(ν) (low-pass shapes, kernel spectra, Wiener conj(H)/(|H|² + K)) is computed by BlurCore in Double on the P grid and uploaded as Float. The inverse is scaled by 1/P². The result is cropped back to N × N.
- **CPU reference:** FAM-F4's `FFT2D.swift` (Double) on the same P grid with the same extension. Tolerance class `fft` (§7). Trace: spectrum steps over the probe's row (SPEC §6.5), never per-tap.
- `diffraction-airy` (family F6) is implemented by FAM-F4 because both of its variants (small gather, FFT) share this engine.

### 6.5 Common and present passes

- `B2Common.metal` (SKEL): `b2_common_fullscreen_vs`; `b2_common_colour_fs` (pre/post by constants 4–6, §4.2); `b2_common_window_fs` (the window pass × 2^EV, §4.1); `b2_common_downsample2x_fs` (the frozen preview input, a 2 × 2 mean); `b2_common_copy_fs`.
- `B2Present.metal` (UI-SPECIMEN) draws only from textures the `RenderCoordinator` publishes: output, input, pass intermediates, B/C/D slots. It handles 1 : 1 nearest at zoom 1×, nearest magnification up to 8×, the before/after split, Wipe, Flip, Difference |A − B| × 1/16/256 as a luminance ramp, Line-up 2 × 2 (each quadrant the central N/2 crop of one slot), the periscope crop and the loupe's 14 × 14 texel copy. In SDR it encodes to sRGB and clips to [0, 1]; in EDR it writes extended linear values. It never blurs, never filters for display, and never draws on the specimen texture (overlays are SwiftUI).

### 6.6 Shader manifest and the shown source (JF G-8; SPEC §5.1 floor 6)

1. At build time `Tools/shader-manifest.sh` copies `App/GPU/Shaders/*.metal` and `B2Shared.h` into `<bundle>/ShaderSources/` and writes `ShaderManifest.json` with each file's SHA-256.
2. At launch `ShaderManifest.load(from:)` re-hashes every bundled copy, rejects any mismatch, and computes the **combined SHA-256** with `ShaderManifest.assemble`, the exact text `blur-gpucheck` compiles. The value is stamped into every Run (`ShaderProvenance`) and shown on the Shader tab. If loading fails, the Shader tab engraves `SOURCE CHECK FAILED` with the reason, and no SHA is shown.
3. `Tools/build.sh verify-shaders` (after `Tools/build.sh device`) compares the built app's `ShaderSources/*` with the repo's `App/GPU/Shaders/*` byte for byte. It then compares the combined SHA computed from the bundle with `blur-gpucheck --print-sha` from the repo. Both must match.
4. An AppTests test (on the phone under the hold) asserts that `device.makeDefaultLibrary()!.functionNames` contains every registered pipeline's `functionNames`, the B2Common functions and `instrumentLensOptics` (METRO §E.4 item 5).
5. There is no on-device recompilation of shown sources (JF M-5).

## 7. Numeric parity tolerances

1. **Per channel.** `|gpu − cpu| ≤ ulp16 · ulp₁₆(max(|cpu|, 2⁻¹⁴)) + (absolute + perBilinearPass · passes) · scale(p)`, where **`scale(p) = max(1, max |input| over p's support)`**: a separable van Herk running max (`ParityEvaluation.localScale`) over the Chebyshev radius `PassPlan.supportRadius` declares. Global operators (`supportRadius` nil: FFT, IIR, unbounded iterations) and `wrap` edges use the window maximum. Review fix E-5: with the old global scale, the first draft's Night City lights of 100 (6,400 at +6 EV; the amended image goes to 1,000 and 64,000) granted 0.195–12.5 linear units on **every** pixel under `bilinear`, so a kernel that drops half its taps passed at the 0.02–0.06 buildings; with the local scale it fails there (`SKEL_ReviewFixes.localScaleCatchesDroppedTapsOnHDR`, COMPUTED on the CPU). Implemented once in `ParityTolerance.allowance` and `ParityEvaluation.evaluate`; there are no private tolerance formulas.
2. **Reference options.** The CPU input is the window rounded to fp16 (what the GPU sampled), × 2^EV and rounded again. Every intermediate and the output are rounded to fp16 (what the GPU stored). Bilinear fractions are quantized by `subTexelBits` and `subTexelRounding`: `.parity` (8 bits, nearest; MEASURED on the M1 Max) in `blur-gpucheck`, `ReferenceOptions.forDevice(probes)` in the app (§4.3; nil → classes with a bilinear term are `reportOnly` until the probe runs).
3. **Domain.** sRGB-encoded runs are compared after encoding both outputs (`ParityDomain.encoded`). All others compare linear values.
4. **Classes** (frozen presets; `plus` combines two):

| Class | ulp16 | absolute (× scale) | per bilinear pass | Used for | Evidence |
|---|---|---|---|---|---|
| `exactF32` | **2** | 2⁻²⁰ | 0 | integer-tap FIR with fp32 `fma` and fp16 storage: box separable, tent FIR, Gaussian separable / 2-D / compute tile, binomial, USM | review round 1: the separable seed (`b2_f2_gauss_separable_fs`) reaches **2 ulp16** on step edges, mirror and renormalise (MEASURED M1 Max, 256 and 894), because an fp16 intermediate that fp32 and Double round differently adds an ulp to the final rounding; GPU §6.3's "1 ulp" was a single-pass measurement. The first draft's 1-ulp class failed 768–6,144 channels per case |
| `bilinear` | 2 | 2⁻²⁰ | 2⁻¹⁰ | merged taps through the hardware sampler: linear-sampled Gaussian, Kawase, dual Kawase, gathers | this synthesis: linear-sampled Gaussian max 9.77·10⁻⁴, ≤ 3 ulp16, ≤ 1 LSB8 at 894² (MEASURED M1 Max) |
| `fastMath` | 2 | 2⁻¹¹ | 0 | in-shader `exp`/`pow`/trig under fast math: bilateral range weights, radial/spin trig, sRGB passes | GPU §6.3: radial zoom 7.3·10⁻⁴ (MEASURED) |
| `recursiveF32` | 2 | 2⁻¹² | 0 | fp32 recursions and running sums: IIR, exponential, stack blur, sliding box, PDE iterations | GPU §3.8: running sum fp32 2.4·10⁻⁴ over 4,096-px rows (MEASURED) |
| `sat(cornerMagnitude:boxArea:)` | 2 | 8 · ulp32(S_max) / A | 0 | plain fp32 SATs (box SAT, row-span disc, Kuwahara) | CAT E11, GPU §3.4 |
| `fft` | 2 | 2⁻¹³ | 0 | FFT paths (P ≤ 1024) | fp32 round-off over 40 butterfly stages (COMPUTED bound) |
| `rankExact` | 0 | 0 (bit-exact) | 0 | median, min/max morphology, Kuwahara selection, one frosted-glass realization; **with a colour or alpha pre-pass it becomes `fastMath` automatically** (`adjusted(for:)`: the pre-pass differs from the CPU by up to 1 fp16 ulp, so selection may pick a neighbouring value; review fix E-18) | selection returns an input texel |
| `reportOnly` | — | — | — | models (materials, glass, CSS, SwiftUI model), fp16 accumulation and `rgba8Unorm` intermediates (the Precision lessons), Apple twins | shown, never judged |

5. **Traced specializations.** For every `checkTraced` case: (a) zero differing fp16 words between the traced and untraced outputs over the whole window; (b) no block overflowed (capacity is sized from the plan, `PassPlan.traceCapacity`, so an overflow means the plan understates the taps); (c) every traced pass wrote a `flags = 2` final record; (d) the last traced pass's final record, rounded to fp16, equals the output texel at each probe, bit for bit (skipped only when a colour post-pass follows the blur). Review fix E-13: the first draft compared `taps.last` with a fixed 1,024-tap capacity, which failed on partial sums for 2-D passes above σ 5 and did not cover normalising or selecting kernels.
6. **MEASURED baseline** (this synthesis; `blur-gpucheck --size 894`, release, Apple M1 Max, macOS 27.2):

| Case (gaussian-blur / gaussian-linear-sampling) | max abs | RMS | 8-bit steps | ulp16 | traced = untraced | final sum = output |
|---|---|---|---|---|---|---|
| σ 4, step edges (SPEC §5.3 A) | 9.77·10⁻⁴ | 3.87·10⁻⁴ | 1 | 2 | yes | yes |
| σ 12, impulse (Bench default σ) | 4.88·10⁻⁴ | 2.44·10⁻⁴ | 1 | 3 | yes | yes |
| σ 6, mirror / wrap / zero | 9.77·10⁻⁴ | ≤ 1.01·10⁻⁴ | 1 | 2–3 | — | — |
| σ 4, sRGB-encoded (encoded domain) | 2.93·10⁻³ linear | 4.17·10⁻⁴ | 1 | 6 (linear) | — | — |

   Review round 1 added (same Mac, `blur-gpucheck`, release): `gaussian-separable` σ 4 step edges max 4.88·10⁻⁴ (2 ulp16); σ 12 impulse ×100 at +6 EV (input 6,400, exposure at render time) max 7.81·10⁻³ (3 ulp16 at values near 3–4, within `exactF32` at local scale); σ 6 renormalise and mirror max 9.77·10⁻⁴ (2 ulp16); traced = untraced and final record = output on every traced case. All 20 cases also pass with `--apple2-limits`.

   The sRGB case fails a linear-domain `fastMath` check (MEASURED in this synthesis: 0.0029 linear at the bright side of the edge, where decoding amplifies encoded errors) and passes in the encoded domain with `bilinear.plus(.fastMath)`. Hence rule 3.
7. **In-app PARITY telemetry**: every settled full-resolution Run checks a 128 × 128 crop centred on the probe with the entry's own tolerance class, **after timing completes**, at background priority (`.utility`), through `referenceCrop`, cancellable by the next generation or any touch (review fix E-8). It uses `ReferenceOptions.forDevice`; until the sub-texel probe has run, classes with a bilinear term report `SUB-TEXEL RULE NOT YET MEASURED` instead of pass/fail. It reports `≤ 1 LSB` / `3 LSB` (8-bit steps) with the fp16 ulps in the accessibility value, MEASURED with the device stamp. A failure reads "GPU differs from the math by …" with a symbol (SPEC §15).
8. **BlurCore fixtures** (no GPU): a printed fixture value matches to half a unit of its last printed digit (0.4500 → ±0.00005; 179/255 exactly).
9. **Mutation tests** (GPUCHECK, §3.2 item 5): per tolerance class in use, σ × 1.01, a dropped tap and a skipped pass on Night City at +4 EV and on step edges must each FAIL. A class that lets a mutation pass is tightened (with a MEASURED justification) before INTEGRATE.

## 8. Build areas (disjoint ownership)

Thirty-one areas build in parallel after the skeleton: 25 in wave 1 and 6 screen areas in wave 2 (§10). File ownership is **disjoint**: every path in the repo has exactly one owner, either an area below, SKEL (frozen files) or INTEGRATE (README and applying requests). Every area also owns `Tests/BlurCoreTests/<AREA>/`, `Tests/BlurGPUTests/<AREA>/`, `Tests/AppTests/<AREA>/`, `UITests/<AREA>/` (UI areas only), `Documentation/build/progress-<AREA>.md` and `Documentation/screenshots/<AREA>-*.png`. Test suite types are named `<TAG>_<Name>`, where TAG is the area id without hyphens (`FAMF2_GaussianFixtures`, `CONTENTLAYERS_FloorRules`). `Tools/build.sh core-test --area <TAG>` runs exactly one area's tests: it passes the anchored filter `'\.<TAG>_'` to `swift test` (whose `--filter` is an unanchored regex, so a bare `FAMF1` would also run `FAMF10_*` and `FAMF11_*`; review fix E-16). `device-test --area <TAG>` lists the area's `<TAG>_` test classes in `Tests/AppTests/<AREA>/` and `UITests/<AREA>/` and passes one `-only-testing:Blur2oolTests/<Class>` per class (xcodebuild needs exact Target/Class identifiers); it fails on an empty list or when zero tests executed.

### 8.0 Summary

| Area | Wave | Owns (besides its test folders) | Goal |
|---|---|---|---|
| ENGINE | 1 | `App/Engine/**` (not `EngineTypes.swift`), `App/AppEnvironment.swift`, `Sources/BlurCore/Interaction/**` | the requested/acknowledged hub, render loop, Runs, sessions, settings, Run log, launch scenarios, interaction logic |
| METRO-COMPONENTS | 1 | the Blur2ool component files in `App/DesignSystem/` (§5.14), `InstrumentPalette+Blur2ool.swift`, `ComponentGallery.swift` | Metro-faithful components behind the frozen initialisers |
| CONTENT-VIEWS | 1 | `App/Content/**` | renderers for pages, blocks, figures (Swift Charts + AX), shader source |
| UI-SPECIMEN | 1 | `App/Render/**`, `App/Bench/SpecimenWindow/**`, `App/GPU/Shaders/B2Present.metal` | the image window: present, gestures, probe, handles, loupe, zoom, split, Tier S slot, VoiceOver image element |
| TESTIMAGES | 1 | `Sources/BlurCore/Specimens/**`, `App/Specimens/**` | all 22 test images of SPEC §11, deterministic, with feature probes; Core Text; photos |
| CONTENT-LAYERS | 1 | `Sources/BlurCore/Content/**` | floor templates per class, rail, pills, trace scripts, lessons, field guide text |
| ANALYSIS | 1 | `Sources/BlurCore/Analysis/**` | divergence, fingerprint vectors, nearest, cost model |
| SEMANTICS | 1 | `Sources/BlurCore/Semantics/**` | tool conventions (what each tool's number means) |
| CALIBRATION | 1 | `Sources/BlurCore/Calibration/**`, `App/Calibration/**` | PSF fitter, on-device measurement, Calibrate sheet |
| APPLE-TWINS | 1 | `Sources/BlurGPU/AppleTwins/**` | Core Image / MPS / vImage twins in-process |
| GPU-MEASURE | 1 | `Sources/BlurGPU/Measure/**`, `App/GPU/Shaders/Probes.metal` | timing protocol, per-pass counters, device probes, shape measurement |
| GPUCHECK | 1 | `Sources/blur-gpucheck/**` | the Mac parity CLI, complete |
| FAM-F1 … FAM-F11 (13 areas: F1, F2, F3, F4, F5A, F5B, F6, F7, F8A, F8B, F9, F10, F11) | 1 | `Sources/BlurCore/Operators/<G>/**`, `Sources/BlurGPU/Pipelines/<G>/**`, the group's `.metal` file (§6.1); FAM-F10 also `App/System/**` | every entry of the group: catalog data, operator, CPU references, GPU pipelines, parity cases, floor facts, traces |
| UI-BENCH | 2 | `App/Bench/**` except `SpecimenWindow/` and `Compare/` | the Bench screen of SPEC §4.1 |
| UI-COMPARE | 2 | `App/Bench/Compare/**` | Compare mode (SPEC §4.2, §8) |
| UI-LAYERS | 2 | `App/Layers/**` | the Layers screen (SPEC §4.3) |
| UI-TRACE | 2 | `App/Trace/**` | the Trace screen (SPEC §4.4, §6) |
| UI-ATLAS | 2 | `App/Atlas/**`, `App/Fingerprint/**` | Catalog sheet, Tier 3 atlas pages, fingerprint card |
| UI-FIELDGUIDE | 2 | `App/FieldGuide/**` | Field guide sheet: Guide, This phone, Runs, Settings |

Implementation groups and their entries (CATALOG ids; Tier per SPEC §10.1):

| Group | Area | Entries (variants) | Shader file |
|---|---|---|---|
| F1 | FAM-F1 | `box-blur` (`sat-box`, `box-sliding-window`), `tent-blur` (`stack-blur`), `iterated-box` (`svg-three-box`, `extended-box` plot, `cubic-b-spline` plot), `average-blur` (T3) | `F1BoxTent.metal` |
| F2 | FAM-F2 | `gaussian-blur` (2-D, separable, linear-sampled, compute tile; discretisations), `binomial-blur`, `iir-gaussian`; contrast `unsharp-mask` (`high-pass`), `difference-of-gaussians` (`xdog`), `lanczos` (T3) | `F2Gaussian.metal` |
| F3 | FAM-F3 | `kawase-blur`, `dual-kawase`, `pyramid-blur` (`mip-chain`, `cod-13tap`, `unity-13tap`) | `F3Pyramid.metal` |
| F4 | FAM-F4 | `exponential-blur`, `lorentzian-blur` (`sum-of-gaussians`), `frequency-lowpass` (ideal, Butterworth, Gaussian), `fft-convolution`, `diffraction-airy` (family F6, FFT engine here); contrast `wiener-deconvolution` (`richardson-lucy`) | `F4Frequency.metal` |
| F5A | FAM-F5A | `linear-motion-blur` (`shutter-function-blur`), `anisotropic-gaussian`, `radial-zoom-blur`, `spin-blur`, `path-blur`, `kawase-streak` | `F5Motion.metal` |
| F5B | FAM-F5B | `camera-shake-blur`, `velocity-buffer-motion-blur`, `temporal-accumulation` | `F5Temporal.metal` |
| F6 | FAM-F6 | `disc-blur` (`circular-separable-bokeh`, `stochastic-bokeh`, `defocus-wave-optics` plot), `polygonal-bokeh`, `cats-eye-swirl-bokeh`, `anamorphic-bokeh` | `F6Lens.metal` |
| F7 | FAM-F7 | `depth-of-field-coc`, `tilt-shift` (`iris-blur`), `variable-progressive-blur`, `frosted-glass-noise` | `F7Varying.metal` |
| F8A | FAM-F8A | `median`, `bilateral` (`bilateral-grid`, `bilateral-separable`), `joint-bilateral`, `guided` | `F8EdgeA.metal` |
| F8B | FAM-F8B | `kuwahara` (`kuwahara-generalized`, `kuwahara-anisotropic`), `domain-transform`, `surface-blur` (`smart-blur`, `sigma-filter`), `nonlocal-means`, `mean-shift` (T3), `tv-denoise` (T3) | `F8EdgeB.metal` |
| F9 | FAM-F9 | `heat-equation` (`heat-equation-explicit`), `perona-malik`, `coherence-enhancing-diffusion` (T3); contrast `morphology` (dilate, erode, open, close), `pixelate` (`pixelate-hex`, `crystallize`, `pointillize`) | `F9Diffusion.metal` |
| F10 | FAM-F10 | `swiftui-layer-blur` (S), `apple-uiblureffect` (S + model), `liquid-glass` (S + model), `css-backdrop-filter`, `windows-acrylic` (T3), `windows-mica` (T3), `android-renderEffect` (T3); contrast `apple-vibrancy` (T3) | `F10Materials.metal` |
| F11 | FAM-F11 | `drop-shadow` (`inner-shadow`, `outer-glow`), `bloom`, `god-rays` | `F11Uses.metal` |

### 8.1 Acceptance vocabulary (used by every area)

Every command runs with `B2_BUILD_DIR=$TMPDIR/b2-<AREA>`.

- **CORE**: `Tools/build.sh core-test --area <TAG>` passes with zero failures, and the SKEL suites still pass (`--area SKEL`). `Tools/build.sh lint-names` reports nothing for the area's paths.
- **PARITY(ids)**: `Tools/build.sh gpucheck --filter <id>,<id>,…` passes every case at sizes 256 and 894. For Tier 1 variants, `traced=untraced yes` and `final=out yes` on every `checkTraced` case. **APPLE2(ids)**: the same with `--apple2-limits`.
- **METAL**: `Tools/build.sh metal-check` reports zero diagnostics.
- **TYPECHECK**: `Tools/build.sh typecheck-ios` succeeds.
- **DEVICE-BUILD**: `Tools/build.sh device` succeeds, and its log has no `warning:` line under the area's owned paths.
- **PHONE(scenarios)**: if `Tools/build.sh device-status` says CONNECTED: `device-build` (outside the lock), then **one** `device-session` that installs that build, checks its `B2BuildStamp`, and for each scenario launches `-B2Scenario …` and captures `Documentation/screenshots/<AREA>-<name>.png` (§11.4). Look at every PNG (Read tool) and record what it shows. If the phone is unavailable or locked, record `PHONE-UNAVAILABLE` (not a failure) **and** the simulator equivalent as `DEFERRED-BY-HOLD` (§12.3).
- **HONEST**: tests run `honestyViolations` over every `BadgedValue` and `BadgedLine` the area produces (pages, chips, pills, rows, status lines, Runs). The result is empty.

### 8.2 Per-area contracts

#### ENGINE (wave 1)
- **Owns:** `App/Engine/{AppSettings, TelemetryModel, RunLogStore, SpecimenStore, RenderCoordinator, TraceSession, BenchModel}.swift` and any new `App/Engine/*.swift` except `EngineTypes.swift`; `App/AppEnvironment.swift`; `Sources/BlurCore/Interaction/**`.
- **Implements:** §5.9 (all Engine APIs), §5.10, the render loop and timing policy of SPEC §4.1.6, σ-hold on switch (§8.1), the Compare state rules (§8.2: legal B choices per axis, MATCH σ, driving B, swap, ABAB timing), `apply(lesson)`, the Trace session with the traced frame (§5.12), probe jumps (SPEC §6.1), loupe readings, snapshots and restoration, `LaunchScenario` handling for every case, the first-launch focus pull and coaching line state (SPEC §2), calibration idle hooks, and service installation in `AppEnvironment` (`GPUServices.timing = TimingService()` etc.).
- **Also implements (review round 1):** the preview path (`op.previewScale`, `previewRequest`, the 2 × 2-mean input, `lastFull` and `HELD` readouts), budgeted and cancellable timing and parity (after timing, `.utility`, cancelled by `touchBegan`), separate pipeline instances per (slot, blur, variant) for display, timing and parity, async `prepare` with the previous Run kept on screen, the post-idle-gate sub-texel probe and hero-dozen pre-warm, the first frame as the sharp input, `GPUContext.recycle(_:)` of transient textures, and the build-stamp log line.
- **Acceptance:** CORE: an arbiter matrix of at least 25 cases (every priority conflict, slop and long-press boundaries, draining after a pinch, a loupe lifted outside), Metro's crown tests ported, the rate limiter, the scheduler (preview → full → timing once per generation; `cancelMeasurements` on change and touch; monotonic acknowledge), the idle gate, `LaunchScenario.parse`, and `BenchSnapshot` / `Run` JSON round trips; a test that a preview Run never updates PIXEL, loupe or telemetry. TYPECHECK. DEVICE-BUILD. PHONE(`first-launch`, `bench`, `compare`, `trace`): the image renders, the status row shows `RENDERING…` only while a render is in flight, the GPU chip turns MEASURED after settle, and no timing happens during the first 10 s.

#### METRO-COMPONENTS (wave 1)
- **Owns:** `App/DesignSystem/{InstrumentPalette+Blur2ool, HonestyBadge, BadgedValueText, DecimalParameterStepper, InstrumentCrown, InstrumentSignalPill, InstrumentEventTiles, InstrumentFloatingActionGroup, SpecimenHousing, FootprintGlyph, ComponentGallery}.swift`. The verbatim starter files are SKEL's and are never edited.
- **Implements:** §5.14. The crown is ported from `Metro Station/App/Views/TempoCrownsView.swift` with `CrownDetentTracker` + `DetentRateLimiter`, 7-pt centre exclusion, haptics per role, ± glass buttons and adjustable actions. The pill is ported from `MetroStationPillView.swift`: static outline, interior easing ≤ 150 ms, signed responses with dashed negative lobes, comparison styles. Also: the event tiles; the floating group with `FloatingGroupHeightKey`; the housing from tokens (METRO §B.5); every `GlyphKind`; badges with dashed INFERRED borders and Increased Contrast borders. All tokens come from METRO §B, named from the manifest.
- **Acceptance:** CORE where pure (a token parity test against `metro-station-design-tokens.json` values; lens opacity 0.48 / 1.0 unchanged, JF G-21). TYPECHECK. DEVICE-BUILD. PHONE(`gallery`, and `gallery` with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`).

#### CONTENT-VIEWS (wave 1)
- **Owns:** `App/Content/**` (including `ContentGallery.swift`, the `content-gallery` scenario).
- **Implements:** §5.11 renderers with fixed slot heights per floor (SPEC §5.0 rule 7). Plots are Swift Charts with explicit stem widths, signed zero lines, shaded and dashed negatives, markers, an `AXChartDescriptor` and a `DisclosureGroup` data table. Also: heat maps (never colour alone), texel grids (tables for VoiceOver), dispatch overlays on a copy, pass tiles (via `InstrumentEventTiles`), PSF fields, tool bars, the code view with `@explain:` annotations and TRACE_PROBE highlights, and tables.
- **Acceptance:** CORE (fixture pages for every `FigureSpec` and `ContentBlock` case build without placeholders). TYPECHECK. DEVICE-BUILD. PHONE(`content-gallery`, default and AX5).

#### UI-SPECIMEN (wave 1)
- **Owns:** `App/Render/**`, `App/Bench/SpecimenWindow/**`, `App/GPU/Shaders/B2Present.metal`.
- **Implements:** `PresentRenderer` and `MetalSpecimenView` (§5.9). An on-demand MTKView whose drawable is exactly N × N device pixels. The UIKit touch layer feeds `SpecimenGestureArbiter`. Present modes per §6.5. Overlays in SwiftUI: the probe crosshair (amber, 13-pt arms, 3-pt gap), handles (centre ⊕, focus band, iris ellipse, ramp ends, glass grip; 44-pt targets; adjustable actions; `Centre on probe`), the opaque Metal loupe (112 × 112 pt, 14 × 14 texels, value line), the zoom caption, the split divider (44-pt handle, ±10 %), pan rubber-banding at ±256 px. The Tier S slot hosts `SystemExhibitView` (SPEC §4.1.9 f–g). The VoiceOver image element, rotors and custom actions follow SPEC §14.
- **Acceptance:** CORE in `BlurGPUTests/UISPECIMEN` on the Mac GPU: a 1 : 1 present of a known texture gives `SRGB.code8` per pixel; nearest zoom; split; Difference × 16 gain. METAL. TYPECHECK. DEVICE-BUILD. An AppTest on the phone asserts the MTKView's drawable is exactly N × N, `autoResizeDrawable == false`, `contentScaleFactor == displayScale` and the layer colorspace is sRGB (review fix E-20). PHONE(`bench`, `loupe`, `bench` with `-B2Blur radial-zoom-blur`).

#### TESTIMAGES (wave 1)
- **Owns:** `Sources/BlurCore/Specimens/**`, `App/Specimens/**`.
- **Implements:** all 22 images of SPEC §11 (Night City exactly as specified: 160 lights, Poisson-disc seed 7, 120 of 1 × 1 with intensities log-uniform 20–1,000 and 40 of 3 × 3 log-uniform 2–100, three colour temperatures, the reference light of 100 at c, the pair 20 px apart, three lights near the border), feature-relative probes, exposure 2^EV for light images, `HIGH-CONTRAST PATTERN` flags, auxiliary buffers (depth, velocity, guide, mask, sub-frames), and determinism. On the app side: `SpecimenPlatform` (Core Text coverage, CGImage in extended linear sRGB, PhotosPicker data → area-averaged linear canvas with its caption).
- **Acceptance:** CORE: every generator registered; SHA-256 of canvas bytes identical across two runs at N = 894 and 810, with the hashes recorded; canvases ignore exposure (generated at 0 EV); the SPEC §11 coordinate convention, with tests asserting every default probe's IN value (star (747, 460) = 1.000, zone plate (747, 460) = 0.224, star edge (404, 288) = 0.875); Night City statistics and the **launch fixture** (at σ 12, 0 EV, at least 40 lights with blurred peak ≥ 0.25 linear, computed with `GaussianOperator`'s reference). An AppTest compares the phone's canvas hashes with the Mac hashes (review fix E-22). TYPECHECK. DEVICE-BUILD.

#### CONTENT-LAYERS (wave 1)
- **Owns:** `Sources/BlurCore/Content/**`.
- **Implements:** `FloorPageBuilder` (SPEC §5.0 rules, §5.1 floors, §5.2 per-class content, IN THIS APP lines, honest empty states, floor 6 Shader/Silicon tabs from `LiveFacts.run.dispatch` and `shader`), rail chips (SPEC §4.1.4, including Compare `= / ≠ / ≈`), pills (SPEC §4.1.3 table: LOCAL @ PROBE, T(ν, A), `N/A · RANK`, `INFERRED — NOT EXPOSED`), `TraceScripter` (SPEC §6.3 grammar, §6.5 per-class sub-steps, branches not forks, generated closing lines), `LessonLibrary` (four guided descents and P1–P30 as data, with SPEC §17 fixes) and `FieldGuideLibrary` (pages with sources, the honesty legend, the lens note).
- **Also implements (review round 1):** the per-variant `IN THIS APP` line (pair tables and the MODELED effective-tap error for merged-tap variants), the discrete MASS CUT (per axis and 2-D), the `ERROR VS <reference>` slot for approximating entries, the signed 2-D H heat map as the MATH figure of non-separable entries, floor 1's `YOU TYPE` input, qualified response chips (`H ≥ 0 (CONTINUOUS)`, `TRUNCATED: RIPPLE`), `BadgedLine` status and lesson lines, the digits-in-plain-strings lint with its allow-list, and `.offscreen` on every SwiftUI-derived value.
- **Acceptance:** CORE: (1) for every registered entry × 7 floors: page builds, ≤ 6 numbers, HONEST (including the lint), eyebrow and question from `Floor`; (2) the Gaussian walk has exactly 15 steps with SPEC §6.3 wording and 13 fetch sub-steps in steps 10 and 12; (3) Gaussian rail on Night City σ 12: SLIDE `≈4.4`, API `12.0`, MATH `G`, KERNL `73`, ALGO `2×`, GPU `–.––` before timing; Kernel floor MASS CUT 0.235 % per axis and 0.47 % 2-D; (4) every lesson resolves to registered ids (missing ones listed and skipped, re-checked by INTEGRATE); (5) pills per class. TYPECHECK.

#### ANALYSIS (wave 1)
- **Owns:** `Sources/BlurCore/Analysis/**`.
- **Implements:** `DivergenceEngine` (SPEC §8.4 keys: floor 1 `NOT IN <TOOL>` and skipped for PARTS WAYS when either blur is absent from the home tool; floor 2 the API tuple normalised to per-axis σ within 3 % plus colour, edges and alpha; floor 7 rule max |A − B| ≤ 1 fp16 ulp → `≈ same`; reasons; Compare's MIN H from the kernels each slot runs), `FingerprintEngine` (vectors at σ_equiv = 4 px; nearest by a normalised distance with blank cells skipped), `CostModel` (GPU §4.1 table; MODELED bytes; bandwidth assumption with `weakSource`; cost curves).
- **Acceptance:** CORE: the 16 reference rows of SPEC §8.4 (rows whose operators are not registered yet are listed and skipped); fingerprint kurtosis values (Gaussian 0, box −1.2, tent −0.6, disc −1.0, box³ −0.4, Laplace +3); cost-model bytes for the Gaussian at 894² match GPU §4.1. TYPECHECK.

#### SEMANTICS (wave 1)
- **Owns:** `Sources/BlurCore/Semantics/**`.
- **Implements:** `ToolConventions` from STACK §0, §1–§6 and §8. The SwiftUI law is σ ≈ r·scale below ≈ 5 px and 0.90·r·scale above (MEASURED macOS 27.2, shown with `.notThisDevice` until a `CalibrationLaw` from this phone replaces it). Also: CSS σ = value (REFERENCE); Figma σ = value/2 (INFERRED); Sketch; Photoshop and After Effects mappings that stay UNVERIFIED (words); Core Image and MPS (MEASURED); Android `RenderEffect` σ = 0.57735·r + 0.5 (REFERENCE); Flutter; GIMP 2.8 σ = (r + 1)/3.329; OpenCV; ImageMagick; Unity; Unreal. Drop-shadow conventions (P27), with `SOURCES DISAGREE` for `CALayer.shadowRadius`. Reverse mode.
- **Acceptance:** CORE: SPEC §5.3 A floor 1 at σ 4 px, scale 3: SwiftUI 1.33 pt, CSS 1.33 px, Figma 2.67, `CIGaussianBlur` 4, `MPSImageGaussianBlur` 4, Android 6.06, GIMP 12.3, Photoshop `UNVERIFIED` (no number); P27 values; every SwiftUI-derived value carries `.offscreen`; tools that do not offer a blur return "not offered" (the SLIDE chip's `—`); HONEST. TYPECHECK.

#### CALIBRATION (wave 1)
- **Owns:** `Sources/BlurCore/Calibration/**`, `App/Calibration/**`.
- **Implements:** `PSFFitter`: the estimators of `Tools/calibrate/MeasurePSF.swift` (two-pass moment σ within ±6σ, erf least squares as sampled-equivalent σ, excess kurtosis on the axis and at 45°, extent at 1/255, support at 10⁻³, centre spread over phases), model competition (Gaussian, truncated Gaussian, box³) and laws. Also: `measureEdges` (ImageRenderer at `displayScale`, 16 centre rows, working space per colour mode; CAL §7), `CalibrationService` (basic set, sweep, one render per run-loop turn with × 2 back-off over 16 ms, no render while a control is active, pause on touch, Runs of kind `.calibration`; the `drawHierarchy` path stays EXPERIMENTAL until its objective capture test passes), and the Calibrate sheet (SPEC §4.8, §13.3).
- **Acceptance:** CORE: synthetic sampled Gaussians σ 1, 4, 16 recovered to 4 decimal places; box excess kurtosis −1.2, box³ −0.4; shape names; the law from a synthetic sweep finds the switch. A Mac cross-check: run `Tools/calibrate/MeasurePSF.swift` (swiftc, macOS) and the new fitter on the same edges and agree within 1 % (record both). TYPECHECK. DEVICE-BUILD. PHONE(`calibrate`, plus a SwiftUI basic set on the phone with its MEASURED σ/r values recorded in the progress file).

#### APPLE-TWINS (wave 1)
- **Owns:** `Sources/BlurGPU/AppleTwins/**`.
- **Implements:** `AppleTwinRunner` for `CIGaussianBlur`, `CIBoxBlur`, `CIDiscBlur`, `CIBokehBlur`, `CIMotionBlur`, `CIZoomBlur`, `CIMaskedVariableBlur` (CIContext rendering into Metal textures, clamped or transparent edges as the API does), `MPSImageGaussianBlur`, `MPSImageBox`, `MPSImageTent` and vImage box/tent. Plus `edgeSamples` for Calibrate.
- **Acceptance:** CORE (`BlurGPUTests/APPLETWINS`, Mac GPU), reproducing CAL §5.2–§5.4 on this Mac: `CIGaussianBlur` σ/r within 1.5 %; `CIBoxBlur` width 2⌈r/2⌉ − 1; `CIDiscBlur` σ = R/2; `CIMotionBlur` Gaussian (|kurtosis| < 0.15); `CIZoomBlur` outward streak ratios 0.079 at 4 and 0.357 at 16 (± 10 %); MPS Gaussian σ within 1 %; MPS and vImage box/tent exact. Each result is recorded as MEASURED (Mac). TYPECHECK.

#### GPU-MEASURE (wave 1)
- **Owns:** `Sources/BlurGPU/Measure/**`, `App/GPU/Shaders/Probes.metal`.
- **Implements:** `TimingService` (3 warm-ups, up to 15 timed or 1 s of summed GPU time with at least 3, `stopReason`; cancellable between command buffers; blur passes only, with the window copy and colour passes timed once into `overheadMilliseconds`; per-pass times through a stage-boundary `PassTimestampSampling` where supported, otherwise `commandBufferPerPass`; the fused measurement and MEASUREMENT OVERHEAD; ABAB interleaving; thermal state at both ends; nil in the Simulator). `DeviceProbeService` for every `DeviceProbeKind` (sub-texel bits **and rounding mode**, reported as numbers `subTexelBits` and `roundsToNearest` for `ReferenceOptions.forDevice`, `generateMipmaps` impulse, blit and compute copy bandwidth, compression A/B with and without `.shaderWrite`, FMA throughput, counter sampling points, traced = untraced). `ShapeService` (impulse grid, 4-phase step edge, stripes, star crop → σ, kurtosis on the axis and at 45°, shift spread, minimum H, ms/MP).
- **Acceptance:** CORE (`BlurGPUTests/GPUMEASURE`, Mac GPU): sub-texel bits = 8 and round-to-nearest on this Mac; timing stops at the GPU-time budget and throws `CancellationError` when cancelled; mip impulse 0.25 then 0.0625; copy bandwidth > 0 with its label; the stage-boundary sampler returns per-pass ms on this Mac; the Gaussian σ 4 shape measurement gives σ 4.00 ± 0.03 and |kurtosis| < 0.05. METAL. TYPECHECK. PHONE(`this-phone`, with the probes run and their MEASURED values recorded).

#### GPUCHECK (wave 1)
- **Owns:** `Sources/blur-gpucheck/**`.
- **Implements:** §3.2 in full: options, the report table, JSON, `--print-sha`, `--manifest`, `--metallib` (per-file offline compile with Xcode's flags), `--regions`, the `--apple2-limits` dispatch-log assertions, the mutation cases (§3.2 item 5, §7 rule 9), and exit codes 0/1/2.
- **Acceptance:** `Tools/build.sh gpucheck` runs every registered case, in both the runtime single-TU and `--metallib` modes. `--apple2-limits` runs. A test-only factory with a deliberately wrong reference fails with exit code 1 (`Tests/BlurGPUTests/GPUCHECK`), and every mutation case (σ × 1.01, dropped tap, skipped pass) fails for every tolerance class in use, on Night City at +4 EV and on step edges. `--print-sha` equals the SHA that `verify-shaders` computes. CORE.

#### FAM-F1 … FAM-F11 (wave 1; one area per group)
- **Owns:** the group's `Sources/BlurCore/Operators/<G>/**`, `Sources/BlurGPU/Pipelines/<G>/**` and shader file (§6.1). FAM-F10 also owns `App/System/**`. FAM-F2 inherits SKEL's Gaussian seeds.
- **Implements, for every entry of the group:**
  1. `CatalogEntry` from CATALOG.md and SPEC §9.4 / §10.1 (ids, tier, verdict, properties, signature with §17 fixes, glyph, parameters with ranges, steps, defaults and bands, deck, variants, default specimen, handles, Apple twins, tell, neighbours, card rows with CHECKED values, unverified list, sources).
  2. A complete `BlurOperator`, with references for every live variant and Tier 3 plots on a 128 × 128 crop.
  3. A `GPUBlurPipeline` per live variant, following the §5.8 encode rules and §6.3 kernel rules.
  4. Parity cases (§5.8 rule).
  5. Floor facts per class (SPEC §5.2), so every floor has honest content or a stated empty reason.
  6. Traces: Tier 1 full GPU records; Tier 2 the declared stage.
- **Also, for every entry (review round 1):** `previewRequest` overridden where the default would change the blur's character (or nil); `passPlan.supportRadius` declared (nil only for global operators); `referenceCrop` overridden for heavy cost classes, with a CORE test that it equals the full reference cropped at 256 for every edge mode; ranges or automatic variant switches that keep every configuration within `FetchBudget.full`, with `disabledReason` text; σ-hold with `isClamped` and CORE tests at σ 12 and σ 64; every traced pass ends with `b2_trace_final`; every non-private top-level symbol prefixed with the group tag (§0 rule 4a); groups that need a Gaussian stage use `GaussianPassEncoder` only.
- **Acceptance:** CORE (catalog data equals SPEC §9.4 rows; σ-hold per SPEC §8.1; UNIQUE per §7.2; the group's fixtures below; HONEST on all facts). PARITY and APPLE2 for the group's ids (including the §3.2 mutation cases for the group's tolerance classes). METAL. TYPECHECK. DEVICE-BUILD. PHONE(`bench` with `-B2Blur` for two representative entries). Group fixtures (all from SPEC; COMPUTED):
  - **F1:** box σ-hold σ 12 → w 41, r 20, σ 11.83; minimum H −0.217 continuous, −0.333 at w 3 … −0.219 at w 21; tent σ² = r(r + 2)/6 (σ 12 → r 28); iterated box n = 3 inversion −1.0 % (−1.03 % continuous, −1.16 % for three w 9); P3 shape error as the relative L2 distance of the continuous n-fold box from the equal-variance Gaussian, 38 → 8.8 → 4.8 → 3.4 % (and max-abs over peak 50 / 7.8 / 6.0 / 3.5 %; both COMPUTED in review round 1; the discrete values at the lesson's widths are computed by this area); the SAT plain-fp32 tolerance per §7.
  - **F2:** all SPEC §5.3 A floors including the compute-tile fixture (256 × 1 row tile; probe = thread 190 of threadgroup (1, 300), SIMD-group 5, lane 30, **2,240 B** dynamic threadgroup memory = (256 + 2·12) × 8 B, `GaussianOperator.computeTileBytes`); the Bench default's discrete MASS CUT 0.235 % per axis / 0.47 % 2-D and linear-sampled effective-tap error 1.1·10⁻⁴; `iir-gaussian` Young–van Vliet σ 5.56 at nominal 5; binomial H(0.5) = 0 and P8 1.41 %; P9 (sampled σ 0.3 → 0.088, Lindeberg 0.300); P4 at σ 8 (2,401 vs 98 taps); unsharp-mask gain 1.35 at Nyquist (σ 0.5, k 0.5). FAM-F2 inherits both Gaussian seeds and may change the two shared functions' bodies only while their parity cases pass.
  - **F3:** Kawase {0, 1, 2, 2, 3}: σ 5.34, centre 0.0645 < 0.0674, minimum H −0.047, 20 fetches; dual Kawase ≈ 12.3 fetches/px and shift variance 3.7–8.5 % at offset 2; mip-chain centroid snap ±7.5 px at L = 4; CoD 13-tap ≤ 2.3 % shift variance.
  - **F4:** exponential excess kurtosis +3; Lorentzian 1.3 % of the light beyond 50γ and FWHM-hold; ideal low-pass Gibbs overshoot 8.9 %; deconvolution gain at Nyquist for a σ 1 blur: inverse filter (K = 0, offered as the first detent) 139, Wiener K = 10⁻² 0.72, K = 10⁻⁴ 47 (continuous H; 71 / 1.38 / 47 with the sampled r = 3 kernel); FFT wrap-around on `edge-bar`.
  - **F5A:** SPEC §5.3 B in full at the corrected probe (747, 460) (streak 30 px, σ along the ray 8.66, taps at radii 315.3 … 285.3 px spaced 0.969, corner spacing 2.04 px, N ≥ 65, dispatch 56 × 56 groups with the probe = thread (11, 12) of threadgroup (46, 28), star 1.000 → 1.000, zone plate 0.224 → 0.499, modulation along the ray 0.970 → 0.042); the Bench zoom default (streak 60 px, σ 17.32, spacing 1.94 and 4.08 px, N ≥ 128); spin grey at 10° on the 36-cycle star (continuous minimum −0.2172 at 1.430 periods; this area computes the discrete 32-sample value, which SPEC marks UNVERIFIED until then); motion zero lines every 1/L.
  - **F5B:** accumulation leaves static parts pixel-identical; P22 under-blur where motions conflict.
  - **F6:** disc first zero 0.6098/R and deepest lobe −0.1323 at 0.8174/R; SPEC §5.3 D in full (area 665.1 px², σ 7.30, 4 line passes × 16 = 64 fetches, OUT 0.1504 → 108/255, sRGB plateau ≈ 0.55 %, 5 blades → ≈ 609-tap gather); complex-separable ripple ±23 % / ±7.6 %.
  - **F7:** frosted glass σ² = a(a + 1)/3 and P24 (8.4 % vs 2.0 % above 0.25 c/px); variable blur mip mix 11.8 % too wide at t = 0.5, variance-matched excess kurtosis +1.5; tilt-shift band geometry.
  - **F8A:** SPEC §5.3 C in full (OpenCV row labelled "same parameters, different range metric"; range weights 0.61/0.135/0.011; T(0.1, A) = 0.178, 0.214, 0.524, 0.930 vs 0.168; 9.4 % vs 43.3 %; 40.3 % at the 0.05 step; OUT 0.581 vs 0.513; 289 taps; 8,192 B tile; probe = thread (15, 12) of threadgroup (27, 18)); median impulse error 0.000 on 10 % salt-and-pepper (P14); guided without gradient reversal (P15).
  - **F8B:** Kuwahara sector selection, `rankExact` parity; domain-transform leak along rows; surface blur labelled INFERRED; TV disc contrast loss 2λ/R on the atlas page.
  - **F9:** heat default λ = ⅛ (G(π, π) = 1 − 8λ = 0; σ = √(2t); 64 iterations for σ 4); the explicit kernel stays non-negative up to λ = ¼ while H ≥ 0 needs λ ≤ ⅛; above 500 iterations the variant switches to Exact Gaussian (budget); λ = ¼ flips a 1-px checkerboard every step (P16); Perona–Malik keeps the step and terraces the ramp; morphology `rankExact`; pixelate cell means.
  - **F10:** models are `reportOnly`; the CSS backdrop model (σ = typed CSS px in pt, sRGB, mirrored edges, REFERENCE); materials and glass reconstructions `MODELED · STRUCTURE INFERRED`; Tier S rows INFERRED until MEASURED · OFFSCREEN; `SystemOffscreen.renderStrip` and `probeTexel` (ImageRenderer on the real modifier, review fixes P-31, P-39) and a CORE/AppTest that no Tier S fingerprint field is LIVE (`FingerprintCardModel.tierSViolations`); the T3 pages (Acrylic, Mica, Android, vibrancy). PHONE(`bench` with `-B2Blur swiftui-layer-blur` and `-B2Blur liquid-glass`).
  - **F11:** P27 drop-shadow σ per convention (while `CALayer.shadowRadius` has `SOURCES DISAGREE`, the image renders σ = r/2 engraved `MODELED · σ = r/2 (ONE OF TWO SOURCES)`); bloom halo tail slope −2.0; god-ray sample counts and decay names (GPU Gems 3 ch. 13).

#### UI-BENCH (wave 2)
- **Owns:** `App/Bench/**` except `SpecimenWindow/` and `Compare/`.
- **Implements:** SPEC §4.1 in full: the header, the blur strip (order, glyphs, σ-hold notice, context menu, `All`), the housing, the caption row with provenance engravings, rulers with the support bracket, both pills, the readout band (hero, meaning band, status row), the kernel well (unmodified `InstrumentLensSurface`), the rail (`DescentRail`), deck arrangements A–E, the floating group with its measured bottom reserve, and below the fold the telemetry row, the Parameters panel (native twins first, then EVERY BLUR) and the compact fingerprint card. Also the AX layout (§4.1.10), the first-launch focus pull and coaching line, and Reduce Motion / Transparency / Increased Contrast.
- **Acceptance:** TYPECHECK. DEVICE-BUILD. PHONE(`first-launch`, `bench`, `bench` at AX5, `bench` with `-B2Blur` set to `box-blur`, `kawase-blur`, `median` and `bilateral` for decks B–E). Record a line-by-line checklist of the SPEC §4.1 element table against the screenshots. UITests smoke on the phone (strip tap switches blur, rail chip pushes Layers) or DEFERRED-BY-HOLD.

#### UI-COMPARE (wave 2)
- **Owns:** `App/Bench/Compare/**`.
- **Implements:** SPEC §4.2 and §8.2–§8.3: the compare bar (AXIS, B with legal choices only, VIEW, and the `DRIVE A · B` segmented control), engravings, the divider, Flip hold-to-show and its optional 2 Hz flicker (off under Reduce Motion), Difference gains, Line-up for triads, the Δ telemetry row, `DRIVING B`, Swap and Done.
- **Acceptance:** TYPECHECK. DEVICE-BUILD. PHONE(`compare` for each view; a Line-up lesson).

#### UI-LAYERS (wave 2)
- **Owns:** `App/Layers/**`.
- **Implements:** SPEC §4.3: the periscope (a second MTKView through `PresentRenderer` crop mode, ± buttons, pass intermediates), one plain vertical `ScrollView` of `FloorPageView` sections with `scrollPosition` snapping (no paging, no nested same-axis scroll), the 44-pt floor rail overlaid inside the column with its rotor, floor 6 Shader · Silicon tabs (`ShaderSourceView` from the bundled sources with the combined SHA), and returning to the Bench with the chip focused.
- **Acceptance:** TYPECHECK. DEVICE-BUILD. PHONE(`layers` at floors 1, 4, 6 and 7 for Gaussian and for `radial-zoom-blur`).

#### UI-TRACE (wave 2)
- **Owns:** `App/Trace/**`.
- **Implements:** SPEC §4.4 and §6: the context card (9 × 9 copy, Magnify 17 × 17, IN/Σ/OUT rows, Completed/Next), the floor selector tiles, the floor panel, bottom controls (Back, Restart, the primary naming the next unit, long-press Finish pass), the Jump menu, `Play` (per-floor announcements only under VoiceOver), VoiceOver announcements, `PREPARING TRACED BUILD` while the traced pipeline compiles, and the `TRACED BUILD` engraving.
- **Acceptance:** TYPECHECK. DEVICE-BUILD. PHONE(`trace` for guided descents A–D; a Gaussian step-10 screenshot showing the fetch rows).

#### UI-ATLAS (wave 2)
- **Owns:** `App/Atlas/**`, `App/Fingerprint/**`.
- **Implements:** the Catalog sheet (SPEC §4.5: three-line Blurs rows ≥ 72 pt with search, tier and capability chips; the Fingerprints matrix `Grid` with spoken rows and sorting, one card per row at AX sizes; Divergence with two-line wrapping rows; Lessons), Tier 3 atlas pages (§10.4) pushed inside the sheet, and `FingerprintCardView` full and compact (SPEC §7.1 fixed slot heights, strip at σ 4 px with its evidence badge, qualified response chips, kurtosis axis, TELL, NEAREST, PARTS WAYS, two-line ON THIS PHONE, LOOKS MOST LIKE).
- **Acceptance:** TYPECHECK. DEVICE-BUILD. PHONE(`catalog`, `fingerprints`, `divergence`, `lessons`, `fingerprint` for `gaussian-blur` and `box-blur`, one Tier 3 page).

#### UI-FIELDGUIDE (wave 2)
- **Owns:** `App/FieldGuide/**`.
- **Implements:** SPEC §4.7: Guide (`FieldGuidePage` through `ContentBlockView`, the legend, the lens note, opening on a badge from its context menu), This phone (limits with MEASURED beside REFERENCE, a Measure button per probe through `GPUServices.probes`, `Measure everything`, calibration status, push to Calibrate), Runs (list, swipe to delete, `Export JSON` through `ShareLink`, simulator runs marked), and Settings (a `Form` bound to `AppSettings`).
- **Acceptance:** TYPECHECK. DEVICE-BUILD. PHONE(`field-guide`, `this-phone`, `runs`, `settings`).

## 9. Walking skeleton (SKEL, wave 0)

One agent builds the skeleton so that all 31 areas can start in parallel against real, compiling, frozen interfaces and a working Gaussian path. Progress file: `Documentation/build/progress-SKELETON.md`.

### 9.1 Deliverables

1. **Infrastructure.** `project.yml` (§2), `Package.swift` (§3.1), `.gitignore` (`.build/`, `*.xcodeproj`, `DerivedData/`, `.swiftpm/`), `Tools/build.sh` (§11.1, including the hold guard), `Tools/shader-manifest.sh` (§6.6), `Tools/GenerateIcon.swift` and the generated `AppIcon` (a Metro-styled glyph: the Gaussian rings in instrument cyan on recessed metal, drawn with AppKit as in `LosAlamosSimulator/Tools/GenerateIcon.swift`), `Documentation/metro-station-design-tokens.json`, and the folder `Documentation/build/requests/` with a `README.md` stating the request format (one file per area, review fix E-24).
2. **The contract, copied** per the §5.0 table. Frozen files are copied verbatim. Seeds and stubs go in place with their `OWNER:` headers. The `AppContract` signatures are distributed into the App files of §5.9 with **working minimal bodies**. Every shader file of §6.1 is created: the ones without seeds contain only the include line and a comment naming their owner, so Xcode and `blur-gpucheck` compile them. `B2Present.metal` gets a minimal 1 : 1 nearest SDR present that UI-SPECIMEN completes.
3. **Design system.** Copy AssemblerToy's hardened `InstrumentDesignSystem.swift` (restoring the two starter doc comments, METRO §E.1), the starter's `InstrumentControlTouchBoundary.swift`, `LensRefraction.swift` and `InstrumentLensOptics.metal` verbatim. Then create every Blur2ool component file (§5.14) with its frozen initialiser and a minimal Metro-coloured body.
4. **Gaussian end to end:**
   - `GaussianOperator`, `GaussianLinearPipeline` and `GaussianSeparablePipeline` (seeds) registered, both pipelines through the frozen `GaussianPassEncoder`, with `b2_f2_gauss_separable_fs` and `b2_f2_gauss_linear_fs` in `F2Gaussian.metal` (review fix E-14).
   - A v0 Night City generator in `Sources/BlurCore/Specimens/` (a few HDR point lights and the reference light at c; header `OWNER: TESTIMAGES — v0 by SKEL`) registered next to step edges and impulse.
   - `AppEnvironment`: `GPUContext(device:library: makeDefaultLibrary(), manifest: ShaderManifest.load(...))`, the seed services installed in `GPUServices`.
   - `RenderCoordinator`: canvas at 0 EV converted to `HalfImageData` off the main actor and uploaded, `prepareCommonPipelines`, async `prepare`, window pass (× 2^EV), `encodeFullBlur`, the probe texel through `encodeReadTexels` in the same recorder, commit, Run; the sharp input shown until the first Run.
   - `BenchModel`: σ changes → `RenderScheduler` → render → acknowledge → rail chips and phase line.
   - `PresentRenderer` 1 : 1.
   - A minimal Bench: header; housing with the live window; the σ hero with a `DecimalParameterStepper` and a minimal `InstrumentCrown`; the rail, whose chips push Layers.
   - A minimal Layers screen showing `FloorPageView` for the **Math** and **Kernel** floors (the generic builder seed produces real Gaussian numbers there).
5. **More GPU seeds** (review fix E-15), each with parity cases run under `--apple2-limits`, so the GPU patterns ten or more areas use first are proven once before wave 1:
   - `gaussian-compute-tile`: a 256 × 1 row / 1 × 256 column tile with **dynamic** threadgroup memory (256 + 2r) × 8 B through `dispatch2D`, `.shaderWrite` output, compute `TRACE_PROBE` with `b2_trace_final`, `checkTraced` cases;
   - a two-attachment **MRT** fragment pass (the polygonal bokeh's pass 1, `T1`/`T2` of SPEC §5.3 D) as a test-only pipeline with a CPU reference, proving `GPUCommandRecorder.renderEncoder` with two colour attachments and parity on both;
   - a `commandBufferPerPass` timing smoke test (`BlurGPUTests/SKEL`): per-pass milliseconds exist for every blur pass and exclude the pre- and post-passes.
6. **Tests.** The SKEL suites (copied; 32 tests: 27 BlurCore including `SKEL_ReviewFixes`, 5 BlurGPU) plus `Tests/AppTests/SKEL/` (the library contains every registered pipeline's functions, the B2Common functions and `instrumentLensOptics`; `ShaderManifest.load` succeeds; a Gaussian render's probe value matches `BlurReference` within `bilinear`; the MTKView drawable checks of §8.2 UI-SPECIMEN's seed). These run on the phone under the hold.
7. **Build infrastructure of §11.1**: `B2_AREA` green mirroring and `publish-green`, `lint-names`, `core-test --area`, `device-build`, `device-build-for-testing`, `device-session` with the build stamp, `device-test --area`, and `metal-check` building the macOS per-file `metallib` for `gpucheck --metallib`.

### 9.2 Skeleton acceptance (hold mode; real output recorded in the progress file)

| # | Check | Expected |
|---|---|---|
| S1 | `Tools/build.sh hold-status`; `Tools/build.sh sim` | `ACTIVE`; `sim` exits **3** and names `Documentation/HOLD-SIMULATOR.md`; `grep -n simctl Tools/build.sh` shows simctl only inside the post-release branches |
| S2 | `Tools/build.sh core-test` | all SKEL suites pass (32 tests in the snapshot, plus SKEL's new seed tests) |
| S3 | `Tools/build.sh gpucheck`, `gpucheck --apple2-limits` and `gpucheck --metallib …` | every seed case passes at 256 and 894 (the snapshot's 20 Gaussian cases plus the compute-tile and MRT seeds); `traced=untraced yes`, `final=out yes`, no overflow, every traced pass has its final record |
| S4 | `Tools/build.sh metal-check`; `Tools/build.sh typecheck-ios` | zero diagnostics; typecheck OK |
| S5 | `diff -r` of every frozen path against `Documentation/interfaces/` | identical |
| S6 | `Tools/build.sh device` | BUILD SUCCEEDED; no warnings in SKEL-written files |
| S7 | `Tools/build.sh verify-shaders` | bundle copies identical to `App/GPU/Shaders`; combined SHA = `blur-gpucheck --print-sha` |
| S8 | phone: `device-status`, `device-install`, `device-launch`, `device-shot Documentation/screenshots/skeleton.png`; `device-test -only-testing:Blur2oolTests` | the screenshot shows the Metro housing with a visibly blurred Night City v0 and the rail; AppTests pass. If the phone is unavailable or locked: `PHONE-UNAVAILABLE`, with S8 and the simulator build/screenshot recorded as `DEFERRED-BY-HOLD` |
| S9 | review of stubs | every stub has `OWNER: <AREA>`; nothing shows a fabricated number (unbuilt values read `–.––`, `UNVERIFIED` or an engraved empty state) |
| S10 | `Tools/build.sh lint-names`; `B2_AREA=FAMF1 Tools/build.sh typecheck-ios` after a deliberately broken file under another area's path | lint clean; the area's typecheck still passes because the broken path is mirrored from its green snapshot (or the frozen stub) |
| S11 | `device-build`, then `device-session` with two scenarios | the session installs once, checks `B2BuildStamp`, captures both screenshots, and holds `lockf` only for install → launch → capture; or `PHONE-UNAVAILABLE` |

The gate (build.js GATE-BUILD and GATE-INTERFACES) re-runs S1–S7 in a fresh build directory and checks S5 and S9 line by line.

## 10. Build waves

| Wave | Areas (parallel within a wave) | Starts when |
|---|---|---|
| 0 | SKEL, then GATE (GATE-BUILD + GATE-INTERFACES, up to 3 fix rounds) | design complete (now) |
| 1 | ENGINE, METRO-COMPONENTS, CONTENT-VIEWS, UI-SPECIMEN, TESTIMAGES, CONTENT-LAYERS, ANALYSIS, SEMANTICS, CALIBRATION, APPLE-TWINS, GPU-MEASURE, GPUCHECK, FAM-F1, FAM-F2, FAM-F3, FAM-F4, FAM-F5A, FAM-F5B, FAM-F6, FAM-F7, FAM-F8A, FAM-F8B, FAM-F9, FAM-F10, FAM-F11 (25) | the gate passes |
| 2 | UI-BENCH, UI-COMPARE, UI-LAYERS, UI-TRACE, UI-ATLAS, UI-FIELDGUIDE (6) | wave 1 is complete (each area verified) |
| — | INTEGRATE → QA (math, GPU, Metro, honesty; up to 3 rounds) → DEVICE | wave 2 is complete |

- **Why two waves.** Everything a screen composes is frozen after the skeleton, so wave-1 areas never wait on each other: they program against frozen interfaces and seeds. The six screen areas could also start against seeds, but their acceptance is screenshots against SPEC wireframes, and those are only meaningful with real components (METRO-COMPONENTS), renderers (CONTENT-VIEWS), engine behaviour (ENGINE), content (CONTENT-LAYERS) and family data. Building them earlier would mean rework and unverifiable screenshots.
- **Critical path:** SKEL → (ENGINE ‖ FAM-F2 ‖ CONTENT-LAYERS ‖ METRO-COMPONENTS) → UI-BENCH → INTEGRATE. SKEL is the largest single job; its seeds (Gaussian, Run loop, generic floors) exist so that wave 1 never blocks.
- **Cut order** (SPEC §10.3, D9): if time runs short, a FAM area cuts its Tier 2 entries from the bottom of SPEC §10.3 and records the cut. It never cuts a Tier 1 entry.
- **Parallel load.** 25 concurrent agents running `swift build`, `xcodebuild` and Mac GPU tests will load this Mac heavily. Per the user's standing preference, nothing is throttled, except that phone sessions serialise on a lock (§13). Compile checks are unsigned (`CODE_SIGNING_ALLOWED=NO`), so 25 concurrent builds do not contend for the keychain or provisioning.

## 11. Verification plan

### 11.1 `Tools/build.sh` (SKEL, frozen)

Modelled on `AI Stuff/Toothpaste Toy/Tools/build.sh`, written in zsh with `set -e`. Environment: `B2_BUILD_DIR` (default `$TMPDIR/Blur2oolBuild`; every agent sets its own), **`B2_AREA`** (the calling area's id; required for every command except `hold-status`, and `INTEGRATE` means "the live tree"), `B2_GREEN_DIR` (default `$TMPDIR/b2-green`), `B2_DEVICE_ID` (default `YOUR_DEVICE_ID`), `B2_CONFIG` (`Debug`|`Release`), `B2_SIM_UDID` (post-release only).

1. **Hold guard (first, before mirroring).** The guard keys **only on simulator destinations and SDKs, never on command names** (review fix E-2): if any argument, or the destination/SDK a command would use, contains `iphonesimulator`, `platform=iOS Simulator` or `simctl`, or the command is `sim` or `screenshot` (simulator-only by definition), and `Documentation/HOLD-SIMULATOR.md` contains the exact text `Status: **ACTIVE**`, print `REFUSED: simulator work is on hold — see Documentation/HOLD-SIMULATOR.md` and `exit 3`. `build-for-testing` and `test-without-building` with a device destination are allowed. The script calls `simctl` only inside the post-release branches.
2. **Mirror against stable neighbours** (review fix E-1). `rsync -a --delete` into `$B2_BUILD_DIR/src`, excluding `Documentation/` (except `Documentation/interfaces/`, which the stub fallback reads), `.build`, `.swiftpm`, `*.xcodeproj`, `DerivedData`, `* 2` and `* 2.*` (iCloud duplicates). Paths owned by `$B2_AREA` (the §8 ownership table, which SKEL encodes in `Tools/ownership.tsv`) and frozen SKEL files come from the live repo; **every other area's paths come from that area's last green snapshot** `$B2_GREEN_DIR/<OWNER>/`, or, when none exists yet, from the frozen stub or seed in `Documentation/interfaces/` (the files SKEL copied). With `B2_AREA=INTEGRATE` the live tree is mirrored unchanged. `cd` there. Run `xcodegen generate --quiet` for Xcode commands.
3. **Commands:**

| Command | Does | Hold |
|---|---|---|
| `hold-status` | prints `ACTIVE` or `RELEASED` from the hold file | — |
| `publish-green` | after the caller's own CORE and TYPECHECK pass in this mirror: copies the caller's owned paths to `$B2_GREEN_DIR/$B2_AREA/` atomically (write to a temp dir, then `mv`), with a `GREEN.txt` (time, checks run) | allowed |
| `lint-names [--area X]` | greps every non-private top-level `struct/class/enum/protocol/actor/func/let/var` in `Operators/<G>`, `Pipelines/<G>`, `Tests/*/<AREA>` and fails unless it starts with the group or area tag or sits inside the group's namespace enum (frozen names exempt) (§0 rule 4a) | allowed |
| `core-test [--area TAG] [--filter X]` | `swift test --scratch-path $B2_BUILD_DIR/spm`; `--area TAG` becomes `--filter '\.TAG_'` (anchored; review fix E-16) | allowed |
| `gpucheck [args]` | `swift build -c release --product blur-gpucheck --scratch-path $B2_BUILD_DIR/spm-release`, then runs it from the mirror root with `--shaders App/GPU/Shaders` (or `--metallib $B2_BUILD_DIR/metal/macos.metallib`) | allowed |
| `typecheck-ios` | emits BlurCore and BlurGPU modules, then typechecks `App/**/*.swift` for `arm64-apple-ios27.0` against the iPhoneOS SDK (`-swift-version 6 -strict-concurrency=complete`) | allowed |
| `metal-check` | `xcrun -sdk iphoneos metal -Wall -Wextra -c` for every `App/GPU/Shaders/*.metal` and `App/DesignSystem/*.metal`, then `metallib`; also builds `$B2_BUILD_DIR/metal/macos.metallib` per file with `xcrun -sdk macosx metal` and Xcode's fast-math flags for `gpucheck --metallib` | allowed |
| `device` | `xcodebuild -scheme Blur2ool -configuration ${B2_CONFIG:-Release} -destination 'generic/platform=iOS' -derivedDataPath $B2_BUILD_DIR/dd CODE_SIGNING_ALLOWED=NO build` (an unsigned compile check, MEASURED to succeed by the engineering reviewer; review fix E-30) | allowed (build only) |
| `verify-shaders` | after `device`: compares `<app>/ShaderSources/*` with `App/GPU/Shaders/*` (byte for byte) and the combined SHA with `blur-gpucheck --print-sha` | allowed |
| `device-status` | `xcrun devicectl list devices` (with a timeout); prints `CONNECTED` or `UNAVAILABLE` for `$B2_DEVICE_ID` | allowed |
| `device-build` | **outside the lock**: a signed `xcodebuild build` (Debug unless `B2_CONFIG`) for `platform=iOS,id=$B2_DEVICE_ID` with `-allowProvisioningUpdates` and `B2_BUILD_STAMP=$B2_AREA-<uuid>`; writes the stamp to `$B2_BUILD_DIR/stamp` | allowed |
| `device-build-for-testing` | outside the lock: `xcodebuild build-for-testing` for the same destination, stamped likewise | allowed |
| `device-session <script>` | takes `lockf -t 900 $TMPDIR/b2-device.lock` **once** and, inside it, runs the script's steps: `install` (the stamped `.app` from `device-build`), `check-stamp` (`devicectl device info apps` must report the stamp; otherwise abort with `STAMP MISMATCH`), any number of `launch [--validate] [args…]` and `shot <png>` (each `shot` re-checks the stamp), and `test --area TAG` (`xcodebuild test-without-building` on the products of `device-build-for-testing`, one `-only-testing` per `TAG_` class; fails on an empty list or zero executed tests). Nothing is compiled inside the lock | allowed |
| `device-install`, `device-launch`, `device-shot`, `device-test` | one-step `device-session` wrappers kept for convenience (each takes the lock for its own step; agents use `device-session` for anything that judges a screenshot) | allowed |
| `sim`, `screenshot <png> [args]`, and any simulator destination | the Toothpaste equivalents on `B2_SIM_UDID` (`simctl` wrapped in `perl -e 'alarm 180; exec @ARGV'`) | **refused (exit 3) while ACTIVE** |

4. Only `device-session` (and its wrappers) holds `lockf -t 900 $TMPDIR/b2-device.lock`, and it never builds inside it, so one area's install → launch → capture → test sequence cannot interleave with another's and nobody waits behind a compile (review fix E-2). Every `devicectl` call is wrapped in `perl -e 'alarm 300; exec @ARGV'`. A launch failure whose message mentions a locked or unavailable device is printed as `PHONE-LOCKED` or `PHONE-UNAVAILABLE` with exit 4: not a build failure, and callers record it.
5. The script never uninstalls anything and never touches another bundle id. It installs only `com.utkarsh.blur2ool` and its test runners.

### 11.2 Levels

| Level | What | Where | While the hold is ACTIVE |
|---|---|---|---|
| L0 | BlurCore logic, fixtures, honesty, determinism, interaction logic | Mac, `core-test` | runs |
| L1 | GPU↔CPU parity, traced = untraced, Apple2 limits, present shader, twins, probes | Mac GPU, `gpucheck`, `core-test` (BlurGPUTests) | runs |
| L2 | iOS compile: `typecheck-ios`, `metal-check`, `device` (generic), `verify-shaders` | Mac | runs |
| L3 | on the phone: install, launch scenarios, screenshots, `device-test` (AppTests and UITests), A17 Pro timings and probes | iPhone 15 Pro Max | runs when connected and unlocked; otherwise `PHONE-UNAVAILABLE` |
| L4 | Simulator: `sim` build, simulator unit and UI tests, simulator screenshots | Simulator | **DEFERRED-BY-HOLD** (§12.3) |
| L5 | hands-on: gesture feel, held and edge touches during redraw, Metro's validation list (native glass rendering, Dynamic Type, Reduce Motion/Transparency, Increased Contrast, VoiceOver) | the user's phone | recorded separately; never claimed by an agent (SPEC §16, JF M-17) |

### 11.3 Test catalogue (who writes what)

- **Fixtures** (CORE, per area): every COMPUTED number in SPEC §5.3, §7.2, §8.1 and §8.4 has a test in the area that owns the entry. They are COMPUTED at the printed precision (§7 rule 8).
- **Honesty** (CONTENT-LAYERS, plus every FAM area for its `facts`): for every registered entry × 7 floors × {Night City, step edges} the following hold. `honestyViolations` is empty. No page has more than 6 numbers. No placeholder words. No UNVERIFIED number. MEASURED values only with a `DeviceStamp`. Inputs carry no badge.
- **Determinism** (TESTIMAGES): canvas hashes are stable across runs and at two window sizes.
- **Shader identity** (§6.6): `verify-shaders` (L2) and the AppTests library check (L3).
- **Interaction** (ENGINE): the arbiter matrix, crown, rate limiter, scheduler and idle gate (L0). Gestures are never gated by XCUITest (SPEC §16).
- **Layout** (UI areas): fixed geometry when switching blurs, and AX layouts, through UITests on the phone (L3) and screenshot review. Text fit is checked on the phone by AppTests that render each `FloorPageView`, every engraving and every status-row template with `ImageRenderer` at the default and xxxLarge Dynamic Type sizes and at 430, 393 and 375 pt widths, and compare the measured size with the reserved slot (CONTENT-VIEWS; review fix P-48).
- **Lint** (CONTENT-LAYERS, every area for its own strings): no digits in view-bound plain `String`s outside the allow-list (§5.1); `lint-names` for symbol prefixes.
- **Mutation** (GPUCHECK): §3.2 item 5, §7 rule 9.
- **Platform identity** (TESTIMAGES): phone canvas hashes equal the Mac hashes (AppTest).

### 11.4 Screenshots on the phone (the hold-mode replacement for simulator screenshots)

1. `Tools/build.sh device-status`. If it is not `CONNECTED`, record `PHONE-UNAVAILABLE` and the deferred checks, then continue with L0–L2.
2. `Tools/build.sh device-build` (Debug, stamped, outside the lock).
3. One `Tools/build.sh device-session` whose script installs that build, checks the stamp, and for each scenario launches `-B2Scenario <name> [-B2Blur …] [-B2Specimen …] [-B2Floor …]`, waits about 3 s (or uses `-B2Param settle=1`, which ENGINE honours by waiting for the settled Run before drawing the scenario's final state), and captures `Documentation/screenshots/<AREA>-<name>.png`. A `STAMP MISMATCH` means another area's build is installed: rebuild and retry, never judge that screenshot.
4. For accessibility sizes, add `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` to the launch arguments.
5. **Look at every PNG** (Read tool) and write what it shows against the SPEC wireframe: element present, frame roughly right, badges visible, nothing truncated, no glass over the image. Screenshots are 1290 × 2796 px (scale 3).
6. A locked phone fails the launch with `PHONE-LOCKED`. Record it and continue (the user may unlock the phone later; INTEGRATE retries).

### 11.5 Integration, QA and device under the hold

INTEGRATE runs with `B2_AREA=INTEGRATE` (the live tree, never green snapshots), in a fresh build directory: `lint-names`; `core-test`; `gpucheck` (all cases, including the mutation cases) in both the runtime and `--metallib` modes, and `gpucheck --apple2-limits`; `metal-check`; `typecheck-ios`; `device`; `verify-shaders`; then the phone sequence (§11.4) for every scenario of SPEC's screens and `device-session … test`. It applies the request files in `Documentation/build/requests/` first. It consolidates every `DEFERRED-BY-HOLD` line from the progress files into `Documentation/build/deferred-by-hold.md` (one line per check with its exact post-release command). QA lenses use the same commands and look at phone screenshots instead of simulator ones. DEVICE installs the Release build with `Tools/build.sh device-install` (`B2_CONFIG=Release`) and launches it once.

### 11.6 Device facts the build must produce (replacing research's Mac numbers)

On the phone, through This phone and Calibrate, record in `progress-INTEGRATE.md` and the Run log JSON: sub-texel bits and rounding mode (which feed `ReferenceOptions.forDevice` and in-app parity); `generateMipmaps` impulse; copy bandwidth (which replaces the UNVERIFIED 51.2 GB/s in cost floors); compression A/B; stage-boundary counter support; traced = untraced on Apple9 (JF §9 #9); the SwiftUI `.blur` law and regime switch at scale 3; and timings for the Gaussian at σ 4/12, `radial-zoom-blur`, `bilateral` and `polygonal-bokeh`. Each one replaces a REFERENCE, INFERRED or Mac-MEASURED label in the app only through the normal label lifecycle (SPEC §13.4).

## 12. Simulator hold mode (`Documentation/HOLD-SIMULATOR.md`)

### 12.1 What it is

On 14 October 2026 the user paused all iOS Simulator work on this shared Mac. Repeated kernel-panic reports identify `simctl`, and Time Machine has no verified completed backup. The single source of truth is `Documentation/HOLD-SIMULATOR.md`: while it contains `Status: **ACTIVE**`, the hold applies to every session, workflow and agent, and it overrides every simulator mention in this file, in SPEC.md, and in the build workflow's prompts (`build.js` sets `SIM_HOLD` on by default).

### 12.2 Forbidden and allowed while ACTIVE

- **Forbidden:**
  - any `simctl` command, including `list`, `boot`, `shutdown`, `install`, `launch`, `spawn` and `io … screenshot`, whether run directly or through the iOS Simulator MCP or xcodebuildmcp simulator tools;
  - any simulator destination or the `iphonesimulator` SDK, including `swiftc -sdk iphonesimulator` typechecks;
  - touching CoreSimulator services, simulator runtimes, or other projects' simulators and processes.
- **Allowed and preferred:** L0–L2 of §11.2 (`core-test`, `gpucheck` on the Mac GPU, `typecheck-ios` and `metal-check` against the iPhoneOS SDK, `device` generic builds from the `$TMPDIR` mirror, `verify-shaders`), and L3 on the physical iPhone 15 Pro Max `YOUR_DEVICE_ID` through `xcrun devicectl` and `xcodebuild -destination 'platform=iOS,id=…'`.

### 12.3 Substitutions

| Normally | While the hold is ACTIVE | If impossible |
|---|---|---|
| `Tools/build.sh sim` (compile check) | `Tools/build.sh typecheck-ios` + `metal-check` + `device` | — |
| simulator unit tests (AppTests) | `device-build-for-testing`, then `device-session` with `test --area <TAG>` on the phone | `DEFERRED-BY-HOLD` |
| UI smoke tests (UITests) | the same, for the area's `UITests/<AREA>/` classes | `DEFERRED-BY-HOLD` |
| simulator screenshots | `device-build` + one `device-session` (install, stamp check, launch, shot; §11.4) | `DEFERRED-BY-HOLD` |
| `blur-gpucheck` inside the Simulator (Apple2 limits) | `blur-gpucheck --apple2-limits` on the Mac (§3.2 item 4) | — |
| Metal API validation in the Simulator | `device-launch --validate` on the phone; `--apple2-limits` dispatch-log checks | `DEFERRED-BY-HOLD` |
| "Simulator honesty" behaviour (SPEC §12.2 item 7: `SIM`, no timings) | unit tests of the branches (`GPUFacts.isSimulator`, `TimingService` returning nil) on the Mac | the on-simulator check is `DEFERRED-BY-HOLD` |

**Recording.** In the progress file, one line per check: `DEFERRED-BY-HOLD: <check> — after release run: <exact command>`. Add `PHONE-UNAVAILABLE` or `PHONE-LOCKED` with the time when the phone could not be used. **An area's acceptance is met when every non-deferred check passes**; it then appends the COMPLETE marker as usual. INTEGRATE consolidates every deferred line into `Documentation/build/deferred-by-hold.md`.

**Simulator-only breakage cannot be compiled while the hold is active.** So no area may add simulator-specific code paths. The rules that keep the simulator build safe without compiling it: no Metal 4 (`MTL4*`) API (stubbed out of the simulator SDK, SDK §7); no `#if targetEnvironment(simulator)` block without a working branch for both sides; no sRGB render targets (SDK §15 rule 7); limits from `GPUFacts` only. After release, the first command is `Tools/build.sh sim`.

### 12.4 Enforcement

`Tools/build.sh` refuses the simulator commands with exit 3 while the hold file says ACTIVE (§11.1 rule 1). The skeleton's acceptance proves it (§9.2 S1), and the gate re-checks it.

### 12.5 Release

Only an **explicit release message from the Time Machine recovery chat**, sent after a completed backup and a sample restore have both been verified, lifts the hold. That chat (or the user) changes the status line to `RELEASED <date/time> by <source>`. No agent in this project edits the status on its own judgement. After release:

1. `Tools/build.sh hold-status` prints `RELEASED`.
2. Run every line of `Documentation/build/deferred-by-hold.md`: `Tools/build.sh sim` first, then simulator tests and screenshots. The first simulator check after `sim` is a **traced fragment pass** (the Gaussian seed's `checkTraced` case through the app in the Simulator), because fragment-stage device-buffer writes are UNVERIFIED in the Simulator's Apple2 family and cannot be tested under the hold (review fix E-28). If it fails, INTEGRATE decides then whether the Simulator gets a compute-traced fallback; no area adds simulator-only code paths before that (§12.3).
3. Clean up only `Blur2ool *` simulators (list, shut down, delete), including the research-era "Blur2ool SDK Probe". Touch nothing else.
4. Workflows may then run with `args.simHold === false`.

## 13. Agent isolation rules

1. **Build directories.** Every agent sets `B2_BUILD_DIR=$TMPDIR/b2-<AREA>` (verifiers `…-verify`, fixers `…-fix`, QA `b2-qa-<lens>`, gate `b2-gate-<kind>-r<n>`). SwiftPM scratch (`spm`, `spm-release`) and DerivedData (`dd`) live inside it. Never share a build directory, never build inside the repo or `Documentation`, and never run `swift build`/`swift test` without a scratch path under `$TMPDIR`.
2. **Files.** Edit only paths you own (§8). Frozen files are never edited. Requests go to **your own** file `Documentation/build/requests/<AREA>.md` (append-only, one file per area, so 25 concurrent writers never lose an update; review fix E-24) as `## <date> — <file>: <change>, because <why>` with the minimal diff. INTEGRATE reads the folder, applies them, updates `Documentation/interfaces/`, regenerates Appendix A with `Documentation/interfaces/Tools/strip_bodies.py`, and logs the change in §14.
3. **Other areas' half-finished work never breaks your checks**: always set `B2_AREA`, so their paths come from their green snapshots (§11.1 rule 2); publish your own with `publish-green` after CORE and TYPECHECK pass. If a green neighbour is genuinely incompatible with the frozen contract, record it in your request file and continue with the checks that do not depend on it.
3a. **Names.** Prefix every non-private top-level symbol in your group or test folders with your tag or nest it in your namespace enum (§0 rule 4a); `lint-names` fails otherwise.
4. **The phone** is shared and personal. Use it only through `Tools/build.sh device-session` (or its one-step wrappers), serialised by `lockf`, never building inside the lock, and judge a screenshot only after the stamp check passed. Install only `com.utkarsh.blur2ool` and its test runners. Never uninstall, change settings, or touch other apps. Keep sessions short.
5. **Simulators** (only after release): one per agent, named `Blur2ool <AREA>` (iPhone 17 Pro or 15 Pro Max, iOS 27). Wrap every `simctl` call in a 180-s timeout and shut the simulator down when finished. Never touch other simulators, CoreSimulator or other projects.
6. **Processes.** Never kill a process you did not start; use `ps` only to look.
7. **Progress.** Write `progress-<AREA>.md` as you go: what was built, files, every check with its real output, open issues. If the file exists from an interrupted attempt, continue it. The final line `<!-- STATUS: COMPLETE -->` is appended only when acceptance is met (§12.3 for deferred checks).
8. **Load.** Do not throttle for host load (the user prefers maximum throughput), but reuse your own build directory instead of rebuilding from scratch.

## 14. Review log

**Run history.** The first synthesis run wrote SPEC.md in full and §1–§4 of this file, then was stopped at 09:24 on 14 October when the simulator hold was placed (HOLD-SIMULATOR.md log). Its draft interfaces in `$TMPDIR/blur2ool-synth/ifaces/` were reviewed and replaced in this run by the verified snapshot `Documentation/interfaces/`.

**Changes from the first run's drafts (decided in this run):**
1. Pipelines get every encoder from `GPUCommandRecorder`, so one encode path serves display, per-pass-isolated timing and stage-boundary counters (honest per-pass GPU ms; GPU-MEASURE plugs in a sampler without touching frozen files).
2. The Sendable value records (`GPUFacts`, `PassDispatch`, `ParityTolerance`, `ParityCase`, `DeviceProbeResult`, `ShaderProvenance`) moved into BlurCore, so floors and the Run log can read them without importing Metal.
3. The interaction logic is concrete frozen structs, not protocols. The crown tracker is Metro Station's, verbatim. Render acknowledgement is latest-wins and monotonic: the draft's "only the newest may publish" would freeze the image whenever a render takes longer than the gap between crown detents.
4. One formatter (`NumberStyle` + `BadgedValue` factories). Stricter honesty checks: unbadged numbers, misuse of `weakSource`, placeholder words.
5. Parameters gained a sequence kind, a scope (the EXPOSURE crown), the shared stepping functions, semantic-stop ids (the SwiftUI regime switch) and SAT centring.
6. Catalog entries gained `CardRows`, an `unverified` list, `supportsRenormalise` and the chip vocabulary.
7. `BlurReference.run` applies the colour pre- and post-passes outside operators, mirroring `encodeFullBlur`.
8. Parity gained the domain rule (sRGB-encoded runs compared encoded), `plus` and `sat(…)` presets, and a MEASURED baseline.
9. Metal: include guards instead of `#pragma once` (the header is prepended for runtime compilation); shared constants 0–6 including the colour pass; per-file blocks of 8; one specialised colour pass `b2_common_colour_fs`; vertex function renamed `b2_common_fullscreen_vs`.
10. `project.yml`: removed `MTL_LANGUAGE_REVISION: Metal41` (not a valid value in this Xcode's `MetalCompiler.xcspec`, whose enumeration stops at `Metal40`); added `MTL_MATH_MODE: FAST` and `SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated`. `Package.swift` platforms are `"27.0"` strings.
11. Build areas re-cut for disjointness and parallelism: FAM-LSI-A/B → FAM-F1…F4; FAM-MOTION-A/B → FAM-F5A/F5B; FAM-EDGE-A/B → FAM-F8A/F8B; FAM-DIFFUSION-USES → FAM-F9 + FAM-F11; FAM-SYSTEM → FAM-F10 + SEMANTICS + APPLE-TWINS. New: CONTENT-VIEWS (shared renderers, wave 1) and METRO-COMPONENTS. Persistence moved into ENGINE, `App/System` to FAM-F10, the PSF fitter to CALIBRATION. `diffraction-airy` is implemented by FAM-F4 (shared FFT engine).
12. Simulator-hold mode added (§12), with device-* commands in `build.sh` and phone screenshots as the L3 replacement.

**Engineering readings of SPEC** (binding for the build; SPEC still decides the product, and INTEGRATE raises any disagreement):
- (a) **Median deck.** SPEC §4.1.9 (d) shows deck E (segmented `3×3 · 5×5` above a NOISE Stepper). §9.4, the per-entry table, gives deck D (RADIUS crown 1–3, SHAPE, NOISE DENSITY in the Parameters panel). **§9.4 governs**; §4.1.9 (d) is read as illustrative. Listed for the user (SPEC §18 D10; U4 below).
- (b) **Gaussian radius** = max(3, ⌈kσ⌉) taps per side. This is identical to SPEC's ⌈3σ⌉ for σ ≥ 1, and needed for SPEC P9's "Lindeberg 0.300" at σ 0.3 (r = 1 gives 0.287; COMPUTED here). The Kernel floor prints the max form.
- (c) **MASS CUT** (amended in review round 1, P-63): the Kernel floor prints the **discrete** mass the finite kernel drops, per axis and of the 2-D kernel (σ 12: 0.235 % and 0.47 %; σ 4: 0.173 % and 0.346 %; COMPUTED), with the continuous erfc(r/(σ√2)) = 0.27 % in details. SPEC now prints these values.
- (d) SPEC §17 item 8's **pixel-integrated 0.92 %** at Nyquist (σ 1) holds for truncation k ≥ 4. At the default k = 3 it is 0.87 % (COMPUTED here). The Field guide states k.
- (e) `gaussian-integrated` and `discrete-gaussian-lindeberg` are the DISCRETISATION parameter (SPEC §9.4), not algorithm variants.
- (f) FFT entries use P = 1024 with 65-px margins at N = 894. Wider kernels wrap, and the floor says so (§6.4).
- (g) SAT default is plain fp32 (the lesson's trap); mean-centred is on the Compare › Precision axis.

**MEASURED in this run** (Apple M1 Max, macOS 27.2, Xcode 27.0): the contract builds and typechecks as stated at the top of this file. 22/22 tests pass. Metal compiles with `-Wall -Wextra` and no diagnostics (iphoneos, macosx; two TUs linked; single-TU runtime compile in 0.42 s). `blur-gpucheck` passes 6/6 Gaussian cases at 894² in 5.1 s (§7.6). The 8-bit sub-texel emulation lowers the worst parity error from 3–15 to 2–3 fp16 ulps. An sRGB-encoded comparison in the linear domain fails at 2.9·10⁻³ and passes in the encoded domain. No simulator was used.

**Handed to the build** (UNVERIFIED until the phone measures them): every item of §11.6, SDK §17 items 1–9, and JF §9 risks 1–9.

**Decisions that need the user** (the build proceeds with the default in each case):
- **U1. Phone availability during the build.** While the hold is active, the phone is the only place the app can run, so screenshots, on-device tests and A17 Pro measurements need it **connected, unlocked and with auto-lock off** during waves 1–2 and INTEGRATE. Default: agents use it when they find it unlocked and otherwise record `PHONE-UNAVAILABLE`. Visual checks then wait for INTEGRATE or for the release.
- **U2. SPEC §18 D1–D9** (scrolling root, five gestures, Night City first, deferred automatic SwiftUI calibration, SDR, no camera, SwiftUI as home tool, no badge on inputs, everything in scope). The defaults are taken; confirm or overrule after the first device build.
- **U3. Releasing the simulator hold** happens only through the Time Machine recovery chat (§12.5). No build agent lifts it.
- **U4. Median controls** (SPEC §18 D10). Deck D per SPEC §9.4 (default), or deck E as sketched in SPEC §4.1.9 (d).
- **U5. Night City's light energies** (SPEC §18 D11, review round 1). Default: 1-px lights log-uniform 20–1,000 so the first screen shows bright glows and crisp hexagons at 0 EV; alternative: keep 2–100 and launch at +3 EV.

## Appendix A. Frozen declarations (generated)

Generated on 14 October 2026 (regenerated after design review round 1) from `Documentation/interfaces/` by `Documentation/interfaces/Tools/strip_bodies.py`. The listing keeps comments, type declarations, stored properties, enum cases and every public signature; function and computed-property bodies are collapsed (computed properties read `{ get }`) and private members are omitted. A.1 lists the protocol and cross-area API files in full. A.2 lists the value-type files compactly: memberwise initialisers are omitted (each type's public `init` takes its stored properties in declaration order, with the defaults shown in the source), and only the first line of each doc comment is kept. **The source files are binding**; regenerate this appendix after any applied interface request (§13 rule 2).

### A.1 Protocols and cross-area APIs

##### `Sources/BlurCore/Core/Operator.swift`

```swift
// entry, in Sources/BlurCore/Operators/<Group>/ and listed in that group's `<Group>Catalog.operators`.

/// Everything an operator needs to answer a question about one configuration.
public struct OperatorRequest: Sendable, Codable, Hashable {
    public var parameters: ParameterValues
    public var variant: VariantID
    public var settings: SilentSettings
    /// Size in pixels of the image being rendered: the window (894 × 894 on the 15 Pro Max), or ⌊N·pixelScale⌋ for a
    /// preview (447 × 447 half, 223 × 223 quarter).
    public var size: ImageSize
    /// Render resolution relative to the full window: 1 (full), 0.5 (half preview) or 0.25 (quarter preview). Pixel-unit
    /// parameters in `parameters` are already expressed at this scale (`BlurOperator.previewRequest`, review fix E-4).
    public var pixelScale: Double
    public init(parameters: ParameterValues, variant: VariantID, settings: SilentSettings = .standard, size: ImageSize,
                pixelScale: Double = 1)
}

public extension PixelPoint {
    /// A full-resolution window pixel mapped into a preview of scale `s` (0.5 → ⌊p/2⌋). Probes and integer handles.
    func previewMapped(_ scale: Double) -> PixelPoint
}

/// The current image (window-sized, linear premultiplied, half-rounded) and auxiliary buffers, for data-dependent answers.
public struct OperatorContent: Sendable, Equatable {
    public var image: ImageBuffer
    public var auxiliary: AuxiliaryInputs
    public init(image: ImageBuffer, auxiliary: AuxiliaryInputs = .none)
}

/// How the hardware turns a bilinear fraction into its fixed-point weight (review fix E-6).
public enum SubTexelRounding: String, Sendable, Codable, Hashable {
    /// Round to the nearest 1/2^bits (MEASURED on the M1 Max, GPU §2.3).
    case nearest
    /// Truncate toward zero.
    case truncate
}

public struct ReferenceOptions: Sendable, Hashable {
    /// Round every intermediate and the output to fp16 exactly as the GPU stores rgba16Float (parity mode).
    public var emulateHalfStorage: Bool
    /// Quantize bilinear fractions like the hardware (8 bits MEASURED on M1 Max only; the Simulator forwards to the Mac
    /// GPU, so it is not independent evidence; This phone measures the A17 Pro). nil = exact fractions.
    public var subTexelBits: Int?
    public var subTexelRounding: SubTexelRounding
    public init(emulateHalfStorage: Bool = true, subTexelBits: Int? = nil, subTexelRounding: SubTexelRounding = .nearest)
    /// The Mac rule (blur-gpucheck on the M1 Max): 8 bits, round to nearest.
    public static let parity = ReferenceOptions(emulateHalfStorage: true, subTexelBits: 8, subTexelRounding: .nearest)
    public static let exact = ReferenceOptions(emulateHalfStorage: false, subTexelBits: nil)
    /// The rule this device's sub-texel probe MEASURED (`DeviceProbeKind.bilinearSubTexelBits`, numbers "subTexelBits"
    /// and "roundsToNearest" 1/0). nil until the probe has run: in-app parity of bilinear classes is then reportOnly
    /// with the caption `SUB-TEXEL RULE NOT YET MEASURED`.
    public static func forDevice(_ probes: [DeviceProbeResult]) -> ReferenceOptions?
}

public struct ReferenceResult: Sendable, Equatable {
    /// Full window-sized output, still in the blur's working space (BlurReference applies the post-pass).
    public var output: ImageBuffer
    /// One image per pass of the plan, in order (sizes may differ for pyramid levels); the last equals `output`.
    public var intermediates: [ImageBuffer]
    public init(output: ImageBuffer, intermediates: [ImageBuffer])
}

public enum ReferenceError: Error, Sendable, Equatable {
    case unsupportedVariant(VariantID)
    case missingAuxiliary(String)
    case parameterOutOfRange(ParameterKey)
    case notImplemented(String)
}

/// The result of σ-hold (SPEC §8.1).
public struct SigmaHoldResult: Sendable, Codable, Hashable {
    public var parameters: ParameterValues
    /// The σ that was held (px, per axis).
    public var requestedSigma: Double
    /// The σ actually achieved (integer parameters leave a residual; a range limit leaves more), or nil when undefined.
    public var achievedSigma: Double?
    /// True when a parameter hit its range limit, so the achieved σ is not the held σ (review fix P-38).
    public var isClamped: Bool
    /// Status-row line with every number badged: "σ HELD 12.0 px → R 26.3 px", "σ HELD 12.0 px → r 20 (w 41, σ 11.83)",
    /// "σ HELD 12.0 px → σs 8.0 px (MAX) · Δσ −4.0 px", "σ NOT DEFINED · RANK FILTER".
    public var statusLine: BadgedLine
    public init(parameters: ParameterValues, requestedSigma: Double, achievedSigma: Double?, isClamped: Bool = false,
                statusLine: BadgedLine)

    /// The standard line: "σ HELD <σ> px → <label> <value> [(MAX)] [· σ <achieved> px | · Δσ <Δ> px]".
    /// The held σ is an input (no badge); converted values and the achieved σ are COMPUTED.
    public static func standardLine(held: Double, converted: [LabeledValue], achieved: Double?, isClamped: Bool) -> BadgedLine
}

/// The variant that will actually run, and why it differs from the requested one ("2-D DIRECT ABOVE σ 8 · USING SEPARABLE").
public struct VariantResolution: Sendable, Codable, Hashable {
    public var variant: VariantID
    public var reason: String?
    public init(variant: VariantID, reason: String? = nil)
}

/// The comparison key of one floor (SPEC §8.4). Two configurations are "same" on a floor when their keys match.
public struct FloorKey: Sendable, Codable, Hashable {
    public var identity: [String]
    public var numbers: [Double]
    /// Absolute tolerance for `numbers` (1e-9 for kernels; display precision for typed values).
    public var tolerance: Double
    /// One line used when this floor is the first difference ("rect vs bell").
    public var description: String
    public init(identity: [String], numbers: [Double] = [], tolerance: Double = 1e-9, description: String)
    public func matches(_ other: FloorKey) -> Bool
}

public enum FloorVerdict: String, Sendable, Codable, Hashable {
    case same, approximatelySame, differs, partsWays
    /// Rail glyph in Compare mode (SPEC §4.1.4).
    public var railSymbol: String { get }
}

public struct FloorComparison: Sendable, Codable, Hashable {
    public var floor: Floor
    public var verdict: FloorVerdict
    public var reason: String
    public init(floor: Floor, verdict: FloorVerdict, reason: String)
}

/// Live and device facts the floors may show. Built by the app from the newest acknowledged Runs and stored measurements.
public struct LiveFacts: Sendable, Codable, Hashable {
    /// The newest acknowledged Run for the configuration on screen (LIVE probe values, dispatch, shader provenance).
    public var run: Run?
    /// The newest settled timing Run (MEASURED GPU ms), if any.
    public var timedRun: Run?
    /// This phone's device-probe results (sub-texel bits, copy bandwidth, limits …), newest per kind.
    public var deviceProbes: [DeviceProbeResult]
    /// Calibrate results (SwiftUI law, shadows, Core Image twins), newest per subject.
    public var calibrations: [CalibrationResult]
    public init(run: Run? = nil, timedRun: Run? = nil, deviceProbes: [DeviceProbeResult] = [], calibrations: [CalibrationResult] = [])
    public func probe(_ kind: DeviceProbeKind) -> DeviceProbeResult?
    public func calibration(_ subject: CalibrationSubject) -> CalibrationResult?
}

/// Everything a floor page, a rail chip, a pill or a trace step needs.
public struct FloorContext: Sendable, Equatable {
    public var configuration: RenderConfiguration
    /// Settings › Home tool ("swiftui", "css", "figma" …; ToolConventionProviding ids).
    public var homeToolID: String
    /// Display scale (3 on the 15 Pro Max) for pt ↔ px.
    public var displayScale: Double
    public var live: LiveFacts
    /// The current window image after the pre-pass, for LIVE CPU weight maps (adaptive blurs); nil when not loaded.
    public var content: OperatorContent?
    /// The other configuration in Compare mode.
    public var compareB: RenderConfiguration?
    public init(configuration: RenderConfiguration, homeToolID: String, displayScale: Double, live: LiveFacts,
                content: OperatorContent? = nil, compareB: RenderConfiguration? = nil)
    public var request: OperatorRequest { get }
    public var probe: PixelPoint { get }
}

public protocol BlurOperator: Sendable {
    var entry: CatalogEntry { get }

    /// The passes the (resolved) variant runs, with fetch counts (COMPUTED).
    func passPlan(_ request: OperatorRequest) -> PassPlan

    /// The PSF at a window pixel. LSI: the same everywhere. LSV: local. Adaptive: needs `content` (LIVE · CPU).
    /// nil for rank filters and global operators without a pixel footprint.
    func psf(at point: PixelPoint, _ request: OperatorRequest, content: OperatorContent?) -> PSF?

    /// Signed H(ν) along an axis (LSI), local H at `query.point` (LSV), T(ν, A) (adaptive); nil for rank filters.
    func response(_ query: ResponseQuery, _ request: OperatorRequest, content: OperatorContent?) -> ResponseCurve?

    /// The continuous counterpart for the quiet trace, where one exists.
    func continuousProfile(_ request: OperatorRequest) -> ProfileCurve?

    /// Per-axis second moment σ in px of the discrete PSF, or nil when undefined (rank, space-variant, system materials).
    func sigma(_ request: OperatorRequest) -> Double?

    /// σ-hold conversion (SPEC §8.1): new parameters for this entry that give per-axis σ = `sigma` px.
    func holdingSigma(_ sigma: Double, current: ParameterValues) -> SigmaHoldResult

    /// The CPU reference: the exact algorithm of the resolved variant (same passes, same weights, same edge mapping,
    /// same sample positions), accumulated in Double, on values ALREADY transformed by the colour pre-pass.
    /// It never applies colour-space or alpha transforms: `BlurReference.run` does (ARCHITECTURE §4.2).
    func reference(_ input: ImageBuffer, _ request: OperatorRequest, auxiliary: AuxiliaryInputs,
                   options: ReferenceOptions) throws -> ReferenceResult

    /// The reference output for one region only (in-app parity and blur-gpucheck at 894 on 128 × 128 crops).
    /// Default: full reference, cropped. REQUIRED override (with an apron of `passPlan.supportRadius`) for every entry
    /// whose cost class `isHeavyByDefault`, except global operators (FFT, IIR) (review fix E-8; ARCHITECTURE §5.5).
    func referenceCrop(_ input: ImageBuffer, _ request: OperatorRequest, auxiliary: AuxiliaryInputs,
                       region: PixelRegion, options: ReferenceOptions) throws -> ImageBuffer

    /// A CPU reconstruction of the probe's taps per pass (source `.cpuReconstruction`, COMPUTED). Shown beside GPU
    /// records, and as the trace itself for stages without GPU records.
    func traceReconstruction(probe: PixelPoint, input: ImageBuffer, _ request: OperatorRequest,
                             auxiliary: AuxiliaryInputs) -> TraceRecord

    /// Blur-specific content for one floor; the page builder fills what is left empty with generic content.
    func facts(_ floor: Floor, _ context: FloorContext) -> FloorFacts

    /// The fingerprint card's UNIQUE row (SPEC §7.2).
    func uniqueNumber(_ request: OperatorRequest) -> LabeledValue

    /// The divergence key of one floor (SPEC §8.4).
    func floorKey(_ floor: Floor, _ request: OperatorRequest) -> FloorKey

    /// The variant that will run for this request (automatic fallbacks with their reason).
    func resolveVariant(_ request: OperatorRequest) -> VariantResolution

    /// Why a variant is disabled for this request ("2-D direct: disabled above σ 8 · 2,401 taps per pixel"), or nil.
    func disabledReason(_ variant: VariantID, _ request: OperatorRequest) -> String?

    /// A sampling or budget warning for the status row ("32 SAMPLES · CORNER GAP 4.08 PX · GHOSTS"), or nil.
    func statusWarning(_ request: OperatorRequest) -> String?

    /// True when this request renders a reduced-resolution preview while a control moves (SPEC §4.1.6).
    func isHeavy(_ request: OperatorRequest) -> Bool

    /// The request at preview scale `scale` (0.5 or 0.25), or nil when this operator has no honest preview (it then
    /// renders at full resolution and shows RENDERING…). Default (review fixes E-4, P-36): `px`, `texels` and
    /// position values × scale; integers max(1, round(x·scale)) (0 stays 0 in lists); `px²` (diffusion time) × scale²;
    /// counts, ratios, angles and choices unchanged; nil for selection (rank) filters, system entries and atlas pages.
    func previewRequest(_ request: OperatorRequest, scale: Double) -> OperatorRequest?
}

public extension BlurOperator {
    func continuousProfile(_ request: OperatorRequest) -> ProfileCurve?
    func facts(_ floor: Floor, _ context: FloorContext) -> FloorFacts
    func resolveVariant(_ request: OperatorRequest) -> VariantResolution
    func disabledReason(_ variant: VariantID, _ request: OperatorRequest) -> String?
    func statusWarning(_ request: OperatorRequest) -> String?
    func isHeavy(_ request: OperatorRequest) -> Bool
    func previewRequest(_ request: OperatorRequest, scale: Double) -> OperatorRequest?
    /// The preview scale while a control moves (review fix E-7): nil = render at full resolution; 0.5 for heavy entries
    /// or plans above `FetchBudget.preview`; 0.25 when even the half-resolution plan exceeds the preview budget.
    func previewScale(_ request: OperatorRequest) -> Double?
    func referenceCrop(_ input: ImageBuffer, _ request: OperatorRequest, auxiliary: AuxiliaryInputs,
                       region: PixelRegion, options: ReferenceOptions) throws -> ImageBuffer
}

/// Runs a reference exactly as the GPU path runs a blur: half-rounded input → exposure 2^EV (the window pass) →
/// colour pre-pass → operator → post-pass. `input` is the window at 0 EV, as the canvas texture holds it (review fix E-10).
public enum BlurReference {
    public static func run(_ op: any BlurOperator, input: ImageBuffer, _ request: OperatorRequest,
                           auxiliary: AuxiliaryInputs = .none, options: ReferenceOptions = .parity,
                           exposureEV: Int = 0) throws -> ReferenceResult

    /// The same transforms as `run`, but the operator computes only `region` (`referenceCrop`): in-app parity and
    /// blur-gpucheck at 894 (review fix E-8). Per-pixel transforms run on the whole window; they are cheap.
    public static func runCrop(_ op: any BlurOperator, input: ImageBuffer, _ request: OperatorRequest, region: PixelRegion,
                               auxiliary: AuxiliaryInputs = .none, options: ReferenceOptions = .parity,
                               exposureEV: Int = 0) throws -> ImageBuffer
}
```

##### `Sources/BlurCore/Core/Services.swift`

```swift
// under the type names listed in Registry.swift; the owning area replaces the implementation behind the same name.

/// SPEC §5: builds the seven pages, the rail chips and the pills from operator facts, generic templates and live Runs.
/// Owner: CONTENT-LAYERS (`FloorPageBuilder`).
public protocol FloorPageBuilding: Sendable {
    func pages(for op: any BlurOperator, context: FloorContext) -> [FloorPage]
    func page(_ floor: Floor, for op: any BlurOperator, context: FloorContext) -> FloorPage
    func railChips(for op: any BlurOperator, context: FloorContext) -> [RailChip]
    func pills(for op: any BlurOperator, context: FloorContext) -> PillContent
}

/// SPEC §6.3: turns a TraceRecord into steps with sub-steps. Owner: CONTENT-LAYERS (`TraceScripter`).
public protocol TraceScripting: Sendable {
    func steps(for record: TraceRecord, op: any BlurOperator, context: FloorContext) -> [TraceStep]
}

/// SPEC §8.4: the first floor where two configurations part ways. Owner: ANALYSIS (`DivergenceEngine`).
public protocol DivergenceComputing: Sendable {
    /// Seven rows, one per floor; the first `.differs` is reported as `.partsWays`.
    func compare(_ a: RenderConfiguration, _ b: RenderConfiguration, homeToolID: String, displayScale: Double) -> [FloorComparison]
}

/// SPEC §7.4: what the matrix sorts by and LOOKS MOST LIKE compares. Blank cells stay nil ("— NOT YET COMPUTED").
public struct FingerprintVector: Sendable, Codable, Hashable {
    public var excessKurtosisAxis: Double?
    public var excessKurtosis45: Double?
    public var minResponse: Double?
    public var firstZero: Double?
    /// Support radius at 10⁻⁴ of peak, divided by σ.
    public var supportOverSigma: Double?
    public var linearity: LinearityClass
    /// Fetches ∝ r^p.
    public var costExponent: Double?
    /// Edge-centre spread over 4 phases, px.
    public var shiftVariancePx: Double?
    public init(excessKurtosisAxis: Double?, excessKurtosis45: Double?, minResponse: Double?, firstZero: Double?,
                supportOverSigma: Double?, linearity: LinearityClass, costExponent: Double?, shiftVariancePx: Double?)
}

/// Owner: ANALYSIS (`FingerprintEngine`).
public protocol FingerprintComputing: Sendable {
    /// COMPUTED at the reference size σ_equiv = 4 px (equal second moment; CATALOG §7 convention).
    func vector(for op: any BlurOperator) -> FingerprintVector
    /// The same statistics from a measured shape (ON THIS PHONE).
    func vector(measured: ShapeMeasurement, linearity: LinearityClass) -> FingerprintVector
    /// LOOKS MOST LIKE: nearest catalog entry to a vector, with its distance.
    func nearest(to vector: FingerprintVector, among ops: [any BlurOperator]) -> (blur: BlurID, distance: Double)?
}

/// One tool's meaning of its blur number (STACK §8: the 16 meanings of "radius"). Owner: SEMANTICS (`ToolConventions`).
public struct ToolConvention: Sendable, Codable, Hashable, Identifiable {
    public var id: String                  // "swiftui", "css", "figma", "photoshop", "coreimage", "android", "flutter", …
    public var toolName: String            // "SwiftUI"
    public var controlName: String         // ".blur(radius:)"
    public var unit: ParameterUnit
    public var provenance: Provenance
    public var source: SourceRef
    /// "σ = r·scale below ≈ 5 px, 0.90·r·scale above"; nil when the mapping is UNVERIFIED (shown as words).
    public var lawDescription: String?
    public init(id: String, toolName: String, controlName: String, unit: ParameterUnit, provenance: Provenance,
                source: SourceRef, lawDescription: String?)
}

public protocol ToolConventionProviding: Sendable {
    var all: [ToolConvention] { get }
    /// What a person would type in `toolID` to get per-axis σ = `sigmaPx` for `blur` at `displayScale`. A measured
    /// SwiftUI law from this phone replaces the macOS law; unknown mappings return `.unverified`.
    func typedValue(toolID: String, blur: BlurID, sigmaPx: Double, displayScale: Double,
                    measuredLaw: CalibrationLaw?) -> BadgedValue
    /// Reverse mode ("you typed 10"): the σ in px produced by typing `value` in `toolID`.
    func sigmaPx(toolID: String, blur: BlurID, typed value: Double, displayScale: Double,
                 measuredLaw: CalibrationLaw?) -> BadgedValue
}

/// MODELED bytes and bandwidth floors (GPU §4.1–§4.2). Owner: ANALYSIS (`CostModel`).
public protocol CostModeling: Sendable {
    func cost(for plan: PassPlan, size: ImageSize, intermediate: IntermediateFormat, bandwidth: BandwidthAssumption) -> CostSummary
    /// Fetches per pixel against size for the family's algorithms (the Algorithm floor's cost plot).
    func costCurve(for op: any BlurOperator, request: OperatorRequest, sizes: [Double]) -> [PlotSeries]
}

/// Field guide pages with citations (SPEC §4.7 Guide tab). Owner: CONTENT-LAYERS (`FieldGuideLibrary`).
public protocol FieldGuideProviding: Sendable {
    func page(for op: any BlurOperator, context: FloorContext) -> FieldGuidePage
    /// HONESTY LABELS legend and THE LENS ON THIS INSTRUMENT (SPEC §12.4–§12.5).
    var honestyLegend: [ContentBlock] { get }
    var lensNote: [ContentBlock] { get }
}

// MARK: - Compare vocabulary and lessons (SPEC §8.2–§8.5). Lesson data is owned by CONTENT-LAYERS (`LessonLibrary`).

public enum CompareAxis: String, Sendable, Codable, Hashable, CaseIterable { case `operator`, implementation, precision, space, apple }
public enum MatchRule: String, Sendable, Codable, Hashable, CaseIterable { case sigma, fwhm, edgeWidth, cost, none }
public enum CompareView: String, Sendable, Codable, Hashable, CaseIterable {
    case wipe, flip, difference1, difference16, difference256, lineUp
    public var differenceGain: Double? { get }
}

public enum LessonKind: String, Sendable, Codable, Hashable { case pair, guidedDescent }

public struct Lesson: Sendable, Codable, Hashable, Identifiable {
    public var id: String                  // "P1" … "P30", "descent-A" … "descent-D"
    public var kind: LessonKind
    /// Hook title ("Why zoom blur spares a star").
    public var title: String
    public var setupLine: String
    /// A, then B (and C, D for Line-up). Guided descents use only A.
    public var configurations: [RenderConfiguration]
    public var axis: CompareAxis
    public var match: MatchRule
    public var view: CompareView?
    /// The "Look for" numbers with their badges.
    public var lookFor: [LabeledValue]
    /// Written into the status row until any control changes (numbers badged, review fix E-51).
    public var statusLine: BadgedLine
    public init(id: String, kind: LessonKind, title: String, setupLine: String, configurations: [RenderConfiguration],
                axis: CompareAxis, match: MatchRule, view: CompareView?, lookFor: [LabeledValue], statusLine: BadgedLine)
}
```

##### `Sources/BlurCore/Core/Registry.swift`

```swift
// their own types; they never edit this file (build/requests/<AREA>.md → INTEGRATE).

public enum BlurRegistry {
    /// Every catalog entry's operator, by implementation group (ARCHITECTURE §8 owners in comments).
    public static let operators: [any BlurOperator] =
        F1Catalog.operators          // FAM-F1: box, tent, iterated box, average (T3)
        + F2Catalog.operators        // FAM-F2: Gaussian (SKEL first), binomial, IIR; unsharp mask, DoG, Lanczos (T3)
        + F3Catalog.operators        // FAM-F3: Kawase, dual Kawase, pyramid
        + F4Catalog.operators        // FAM-F4: exponential, Lorentzian, low-pass, FFT convolution, Airy, Wiener
        + F5ACatalog.operators       // FAM-F5A: linear motion, anisotropic Gaussian, zoom, spin, path, streak
        + F5BCatalog.operators       // FAM-F5B: camera shake, velocity buffer, frame accumulation
        + F6Catalog.operators        // FAM-F6: disc (+ variants, defocus plot), polygonal, cat's-eye, anamorphic
        + F7Catalog.operators        // FAM-F7: depth of field, tilt-shift, variable blur, frosted glass
        + F8ACatalog.operators       // FAM-F8A: median, bilateral (+ variants), joint bilateral, guided
        + F8BCatalog.operators       // FAM-F8B: Kuwahara, domain transform, surface blur, NLM, mean-shift (T3), TV (T3)
        + F9Catalog.operators        // FAM-F9: heat equation, Perona–Malik, CED (T3); morphology, pixelate
        + F10Catalog.operators       // FAM-F10: SwiftUI blur, materials, Liquid Glass, CSS backdrop; Fluent/Android/vibrancy (T3)
        + F11Catalog.operators       // FAM-F11: drop shadow, bloom, god rays

    public static let byID: [BlurID: any BlurOperator] =
        Dictionary(operators.map { ($0.entry.id, $0) }, uniquingKeysWith: { first, _ in first })

    public static func op(_ id: BlurID) -> (any BlurOperator)?
    public static func entry(_ id: BlurID) -> CatalogEntry?

    /// Blur-strip order (SPEC §4.1.2): the hero dozen, then every other live entry by family F1…F11, then contrast.
    public static var stripOrder: [BlurID] { get }
}

public enum SpecimenRegistry {
    /// Owner: TESTIMAGES (`SpecimenCatalog.generators` in Sources/BlurCore/Specimens/).
    public static let generators: [any SpecimenGenerating] = SpecimenCatalog.generators
    public static func generator(_ id: SpecimenID) -> (any SpecimenGenerating)?
}

/// Service locator for BlurCore seams (owners in ARCHITECTURE §8).
public enum BlurServices {
    public static let floors: any FloorPageBuilding = FloorPageBuilder()          // CONTENT-LAYERS
    public static let traceScripts: any TraceScripting = TraceScripter()          // CONTENT-LAYERS
    public static let fieldGuide: any FieldGuideProviding = FieldGuideLibrary()   // CONTENT-LAYERS
    public static let lessons: [Lesson] = LessonLibrary.all                       // CONTENT-LAYERS
    public static let divergence: any DivergenceComputing = DivergenceEngine()    // ANALYSIS
    public static let fingerprints: any FingerprintComputing = FingerprintEngine() // ANALYSIS
    public static let costModel: any CostModeling = CostModel()                   // ANALYSIS
    public static let tools: any ToolConventionProviding = ToolConventions()      // SEMANTICS
    public static let psfFitter: any PSFFitting = PSFFitter()                     // CALIBRATION
}
```

##### `Sources/BlurCore/Core/Specimens.swift`

```swift
// Procedural, deterministic, linear light, premultiplied; bit-identical on the Mac, the Simulator and the phone
// (except `text`, whose coverage mask the app renders with Core Text and hands in).

public struct SpecimenOptions: Sendable, Codable, Hashable {
    /// −2 … +6 EV, applied to light-carrying images before the blur AT RENDER TIME: the window pass multiplies by 2^EV
    /// (GPUContext.encodeWindowCopy) and BlurReference.run does the same before rounding. Canvases are always generated
    /// at 0 EV, so an EXPOSURE detent never regenerates or re-uploads a canvas (review fix E-10).
    public var exposureEV: Int
    /// Per-image choices by option key ("height": "0.20", "noise": "saltAndPepper", "period": "2", "orientation": "45").
    public var choices: [String: String]
    /// Overrides the image's fixed seed (photos and stochastic options only; built-ins keep their documented seed).
    public var seed: UInt32?
    public init(exposureEV: Int = 0, choices: [String: String] = [:], seed: UInt32? = nil)
    public static let standard = SpecimenOptions()
    /// The options a canvas is generated and cached with: these options at 0 EV.
    public var canvasOptions: SpecimenOptions { get }
}

public struct SpecimenDescriptor: Sendable, Codable, Hashable, Identifiable {
    public var id: SpecimenID
    /// Menu name under "Test image" ("Night City").
    public var menuName: String
    /// What it reveals (one line, the menu's secondary text).
    public var reveals: String
    public var isHDR: Bool
    /// Marked "HIGH-CONTRAST PATTERN" in the menu (WCAG 2.3.1, SPEC §11 rule 4).
    public var isHighContrastPattern: Bool
    public var supportsExposure: Bool
    /// Text is rendered by the app (Core Text) and handed in as a coverage mask.
    public var needsTextCoverage: Bool
    /// Moves only after an explicit Play (scene-motion, diffusion over time).
    public var animated: Bool
    /// Per-image options (menu items), keys used in `SpecimenOptions.choices`.
    public var options: [ParameterSpec]
    public init(id: SpecimenID, menuName: String, reveals: String, isHDR: Bool, isHighContrastPattern: Bool,
                supportsExposure: Bool, needsTextCoverage: Bool, animated: Bool, options: [ParameterSpec])
}

/// Coverage mask of the text lines (0…1), canvas-sized, rendered by the app with Core Text.
public struct TextCoverage: Sendable, Equatable {
    public var mask: ScalarBuffer
    public init(mask: ScalarBuffer)
}

/// The geometry every specimen shares (SPEC §11 rule 2).
public enum SpecimenGeometry {
    /// Pan margin on every side of the window, in pixels.
    public static let margin = 256
    public static func canvasSide(windowSize n: Int) -> Int
    /// The window centre c = (⌊N/2⌋, ⌊N/2⌋) (447, 447) at N = 894.
    public static func centre(windowSize n: Int) -> PixelPoint
}

/// A generated canvas: the window plus a pan margin on every side.
public struct SpecimenCanvas: Sendable, Equatable {
    public var id: SpecimenID
    public var options: SpecimenOptions
    public var windowSize: Int
    public var margin: Int
    /// (windowSize + 2·margin)², linear light, premultiplied.
    public var image: ImageBuffer
    /// Canvas-sized auxiliary buffers (depth, velocity, guide, mask, sub-frames), cropped together with the image.
    public var auxiliary: AuxiliaryInputs
    /// Default probe in window pixels, on the image's most informative feature.
    public var defaultProbe: PixelPoint
    /// Colour shown behind transparent pixels when presenting (linear, premultiplied).
    public var backdrop: SIMD4<Float>
    /// Engraved in the caption when not empty ("PHOTO · RESAMPLED ×0.31 (BOX)").
    public var caption: String?
    public init(id: SpecimenID, options: SpecimenOptions, windowSize: Int, margin: Int, image: ImageBuffer,
                auxiliary: AuxiliaryInputs, defaultProbe: PixelPoint, backdrop: SIMD4<Float>, caption: String? = nil)

    /// The N × N window at an integer pan offset (±margin), exactly as the GPU blit copies it, with cropped auxiliaries.
    public func window(pan: PixelPoint) -> OperatorContent
}

public protocol SpecimenGenerating: Sendable {
    var descriptor: SpecimenDescriptor { get }
    /// Deterministic: the same arguments give a bit-identical canvas on every platform. `text` is required when
    /// `descriptor.needsTextCoverage` (the app supplies it); generators must not import CoreText.
    func canvas(windowSize: Int, margin: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas
}
```

##### `Sources/BlurGPU/Core/GPUBlurPipeline.swift`

```swift
// Sources/BlurGPU/Pipelines/<Group>/, published through `<Group>Pipelines.factories`.

@MainActor
public protocol GPUBlurPipeline: AnyObject {
    var blur: BlurID { get }
    var variant: VariantID { get }
    /// The family shader file ("F2Gaussian.metal") and every Metal function this pipeline may use (provenance, §6.6).
    var shaderFile: String { get }
    var functionNames: [String] { get }
    /// True when the last pass writes the destination from a compute kernel (destination needs `.shaderWrite`).
    var writesDestinationFromCompute: Bool { get }
    /// Builds pipeline states asynchronously (`await context.computePipeline / renderPipeline`; BOTH TRACE_PROBE
    /// specializations for traceable passes, for the request's edge mode) and sizes scratch textures. Called when the
    /// variant, edge mode or window size changes and before Trace opens, never per frame (review fix E-3).
    func prepare(_ context: GPUContext, request: OperatorRequest) async throws
    /// Encodes every pass, one encoder per pass obtained from `recorder` with the pass's plan index. With `trace`, uses
    /// the TRACE_PROBE specialization for traceable passes and writes the probe's taps, then one flags = 2 record holding
    /// the stored value, into the returned trace buffer. Uses only `context.prepared…Pipeline` (never compiles; a miss
    /// throws `GPUError.notPrepared`). Must not commit, wait, read back, or touch colour space/alpha.
    /// Intermediates and scratch stay valid until the next `encode` on this instance (§5.8 rule 5).
    func encode(_ context: GPUContext, _ inputs: GPUBlurInputs, trace: TraceRequest?, recorder: GPUCommandRecorder) throws -> EncodedBlur
}

/// How the registry makes a pipeline and which parity cases it publishes.
public struct GPUPipelineFactory: Sendable {
    public var blur: BlurID
    public var variant: VariantID
    public var make: @MainActor @Sendable () -> any GPUBlurPipeline
    /// Parity cases for a window size (blur-gpucheck runs them at 256 and 894; ARCHITECTURE §7).
    public var parityCases: @Sendable (_ windowSize: Int) -> [ParityCase]
    public init(blur: BlurID, variant: VariantID, make: @escaping @MainActor @Sendable () -> any GPUBlurPipeline,
                parityCases: @escaping @Sendable (_ windowSize: Int) -> [ParityCase])
}

public enum GPUPipelineRegistry {
    public static let factories: [GPUPipelineFactory] =
        F1Pipelines.factories + F2Pipelines.factories + F3Pipelines.factories + F4Pipelines.factories
        + F5APipelines.factories + F5BPipelines.factories + F6Pipelines.factories + F7Pipelines.factories
        + F8APipelines.factories + F8BPipelines.factories + F9Pipelines.factories + F10Pipelines.factories
        + F11Pipelines.factories

    public static func factory(_ blur: BlurID, _ variant: VariantID) -> GPUPipelineFactory?
}

/// Trace buffer layout shared with B2Shared.h (`B2TraceHeader` 32 B, `B2TraceTap` 64 B). One block per traced pass:
/// header followed by `capacity` taps. The pipeline sets each block's probe to the pixel that pass computes for the probe.
public enum TraceLayout {
    public struct Header: Sendable {
        public var probe: SIMD2<UInt32>
        public var tapCount: UInt32
        public var passIndex: UInt32
        public var capacity: UInt32
        public var overflow: UInt32
        public var reserved: SIMD2<UInt32>
        public init(probe: SIMD2<UInt32>, tapCount: UInt32, passIndex: UInt32, capacity: UInt32, overflow: UInt32, reserved: SIMD2<UInt32>)
    }
    public struct Tap: Sendable {
        /// Sample position in source texel coordinates (centres at i + 0.5).
        public var position: SIMD2<Float>
        public var weight: Float
        /// 1 when the tap was dropped by `renormalise`.
        public var flags: Float
        public var fetched: SIMD4<Float>
        public var runningSum: SIMD4<Float>
        /// Class-specific: spatial weight, range weight, sector variance, rank … (documented per pipeline).
        public var extra: SIMD4<Float>
    }
    public static let headerStride = 32
    public static let tapStride = 64
    public static func passStride(capacity: Int) -> Int

    /// Decodes one block per traced pass from a completed shared buffer.
    public static func decode(_ buffer: any MTLBuffer, passes: Int, capacity: Int) -> [(header: Header, taps: [Tap])]
}
```

##### `Sources/BlurGPU/Core/GaussianPassEncoder.swift`

```swift
// materials, Lorentzian sum of Gaussians, DoG) call this instead of FAM-F2's internals. SKEL wrote both Metal functions
// (`b2_f2_gauss_linear_fs`, `b2_f2_gauss_separable_fs`) and this helper; their names and bindings never change.

@MainActor
public enum GaussianPassEncoder {
    public enum Form: String, Sendable, Hashable {
        /// Integer taps −r … +r (`b2_f2_gauss_separable_fs`); renormalise-capable; parity class exactF32.
        case integerTaps
        /// Merged bilinear pairs (`b2_f2_gauss_linear_fs`, Rákos 2010); parity class bilinear; renormalise → clamp.
        case linearSampled
    }

    public static func functionName(_ form: Form) -> String

    /// Builds both directions × {untraced, traced} for one edge mode.
    public static func prepare(_ context: GPUContext, form: Form, edgeMode: EdgeMode) async throws

    /// The table the GPU receives for a kernel: integer weights, or the linear-sampled pair table.
    public static func tables(_ form: Form, kernel: Kernel1D) -> (weights: [Float], offsets: [Float])

    /// Encodes one pass (direction 0 = H, 1 = V) from `source` into `destination` (rgba16Float render target, no
    /// .shaderWrite). `trace` is this pass's block in a trace buffer (TraceLayout.passStride × block index).
    @discardableResult
    public static func encodePass(_ context: GPUContext, form: Form, kernel: Kernel1D, direction: UInt32, edgeMode: EdgeMode,
                                  source: any MTLTexture, destination: any MTLTexture, passIndex: Int, label: String,
                                  trace: (buffer: any MTLBuffer, offset: Int)?, recorder: GPUCommandRecorder) throws -> PassDispatch
}
```

##### `Sources/BlurGPU/Core/GPUCommandRecorder.swift`

```swift
// ONE encoder per pass. The recorder decides how passes map to command buffers (display: one buffer; per-pass timing:
// one buffer per pass) and lets GPU-MEASURE attach stage-boundary counter samples, without pipeline changes.

public enum PassIsolation: String, Sendable, Hashable {
    /// Display renders and parity: every pass in one command buffer (one encoder per pass).
    case singleCommandBuffer
    /// Per-pass timing without counters: one command buffer per pass, committed in order on one queue.
    case commandBufferPerPass
    /// Per-pass timing with `supportsCounterSampling(.atStageBoundary)`: one buffer, sampler attached to every pass.
    case stageBoundaryCounters
}

/// Attaches counter sample buffers to pass descriptors and resolves per-pass GPU ms. Implemented by GPU-MEASURE.
@MainActor
public protocol PassTimestampSampling: AnyObject {
    func attach(_ descriptor: MTLComputePassDescriptor, pass index: Int)
    func attach(_ descriptor: MTLRenderPassDescriptor, pass index: Int)
    func attach(_ descriptor: MTLBlitPassDescriptor, pass index: Int)
    /// Per-pass milliseconds after completion (nil when the device returned no valid samples).
    func resolve() -> [Int: Double]?
}

@MainActor
public final class GPUCommandRecorder {
    /// Pass indices below 0 are untimed preamble/postamble work (window copy, colour pre/post passes).
    public static let prePass = -2
    public static let postPass = -1

    public let context: GPUContext
    public let isolation: PassIsolation
    public let label: String
    public private(set) var commandBuffers: [any MTLCommandBuffer] = []
    /// (pass index, encoder kind, label) in encode order — blur-gpucheck asserts on it.
    public private(set) var encodeLog: [(pass: Int, kind: PassEncoderKind, label: String)] = []
    public var sampler: (any PassTimestampSampling)?

    public init(context: GPUContext, isolation: PassIsolation = .singleCommandBuffer, label: String,
                sampler: (any PassTimestampSampling)? = nil)

    /// The command buffer for a pass: the single buffer, or, when isolating, a new one whenever the pass index changes.
    /// Negative indices get their own (untimed) buffers too, so the post-pass never inflates the last blur pass's
    /// time (review fix E-19).
    public func commandBuffer(forPass index: Int) throws -> any MTLCommandBuffer
    /// The pass index each command buffer was created for (preamble buffers have negative indices).
    public private(set) var bufferPasses: [Int] = []

    public func computeEncoder(pass index: Int, label: String) throws -> any MTLComputeCommandEncoder

    public func renderEncoder(pass index: Int, descriptor: MTLRenderPassDescriptor, label: String) throws -> any MTLRenderCommandEncoder

    public func blitEncoder(pass index: Int, label: String) throws -> any MTLBlitCommandEncoder

    /// Records a pass encoded by a framework (MPS, Core Image) into `commandBuffer(forPass:)`.
    public func noteExternalPass(_ index: Int, kind: PassEncoderKind, label: String)

    /// Commits every command buffer in order and awaits all completions (continuation + completion handler, §5.15).
    public func commitAndWait() async -> [GPUCompletion]

    /// Per-pass GPU ms: from the sampler (stage-boundary counters) or from per-pass command buffers.
    public func passMilliseconds(_ completions: [GPUCompletion]) -> [Int: Double]?
}
```

##### `Sources/BlurGPU/Core/GPUContext.swift`

```swift
// Swift 6 rules (binding, §5.15):
// • MTLTexture, MTLBuffer, MTLCommandBuffer and encoders are not Sendable: they never leave the main actor.
// • Completion handlers capture only Sendable values (GPUCompletion); results return through a continuation.
// • No nonisolated(unsafe), no @unchecked Sendable on anything that holds a Metal resource.
// • BlurCore work (references, kernels, floors) runs off the main actor on Sendable values.

/// The shader sources and their hashes (ARCHITECTURE §6.6). Per-file SHA-256 from Tools/shader-manifest.sh;
/// the combined SHA-256 is always computed in Swift by `assemble`, so the app and blur-gpucheck agree by construction.
public struct ShaderManifest: Sendable, Codable, Hashable {
    public var files: [String: String]
    public var combinedSHA256: String
    public var mathMode: String
    public var languageVersion: String
    public init(files: [String: String], combinedSHA256: String, mathMode: String = "fast", languageVersion: String = "4.1")

    /// The exact include line every shader file starts with.
    public static let includeLine = "#include \"B2Shared.h\""

    /// The single translation unit blur-gpucheck compiles: the header once, then every `.metal` file in byte-wise
    /// file-name order with its include line removed, separated by "\n".
    public static func assemble(header: String, files: [(name: String, text: String)]) -> String

    public static func sha256(_ text: String) -> String
    public static func sha256(_ data: Data) -> String

    /// Builds a manifest from source texts (header named "B2Shared.h").
    public static func make(header: String, files: [(name: String, text: String)]) -> ShaderManifest

    /// Loads `<bundle>/ShaderSources/` (copies made by Tools/shader-manifest.sh), verifies every per-file hash, and
    /// computes the combined hash. Returns nil when a file is missing or a hash differs (the app then shows the failure).
    public static func load(from directory: URL) -> (manifest: ShaderManifest, texts: [String: String])?
}

@MainActor
public final class GPUContext {
    public let device: any MTLDevice
    public let queue: any MTLCommandQueue
    public let library: any MTLLibrary
    public let manifest: ShaderManifest
    public let mathMode: String
    public private(set) var facts: GPUFacts
    /// Every compute dispatch made through `dispatch2D`, recorded only when `recordsDispatches` (blur-gpucheck and
    /// tests); the app leaves it off so the log cannot grow without bound (review fix E-17).
    public private(set) var dispatchLog: [String] = []
    public let recordsDispatches: Bool
    /// Dispatches made so far (always counted).
    public private(set) var dispatchCount = 0

    public init(device: any MTLDevice, library: any MTLLibrary, manifest: ShaderManifest, mathMode: String = "fast",
                forceApple2Limits: Bool = false, recordsDispatches: Bool = false) throws

    public static func familyName(_ device: any MTLDevice) -> String

    // MARK: Pipelines (specialised from the precompiled library; never compiled from source on device)
    //
    // Review fix E-3: specialisation + backend compile take 59–417 ms (MEASURED, M1 Max), so it never runs on the main
    // actor. `computePipeline` / `renderPipeline` compile in a detached task (only Sendable values cross: the library,
    // the device, FunctionConstants and the resulting pipeline state) and coalesce in-flight compiles per key; `prepare`
    // awaits them. `encode` uses only the `prepared…` lookups, which throw `GPUError.notPrepared` on a cache miss.
    // (Note: this SDK imports `makeFunction(name:constantValues:)` and `make…PipelineState` without async overloads —
    // MEASURED by the "no async operations" diagnostic — so an `await` on them would still compile on the caller's actor.)

    public static func computeKey(_ function: String, _ constants: FunctionConstants) -> String
    public static func renderKey(fragment: String, vertex: String, colorFormats: [TextureFormat], _ constants: FunctionConstants) -> String

    public func computePipeline(_ function: String, constants: FunctionConstants) async throws -> any MTLComputePipelineState

    public func renderPipeline(fragment: String, vertex: String = "b2_common_fullscreen_vs", colorFormats: [TextureFormat],
                               constants: FunctionConstants) async throws -> any MTLRenderPipelineState

    /// A pipeline state `prepare` already built. Never compiles.
    public func preparedComputePipeline(_ function: String, constants: FunctionConstants) throws -> any MTLComputePipelineState

    /// A pipeline state `prepare` already built. Never compiles.
    public func preparedRenderPipeline(fragment: String, vertex: String = "b2_common_fullscreen_vs", colorFormats: [TextureFormat],
                                       constants: FunctionConstants) throws -> any MTLRenderPipelineState

    /// Builds the B2Common pipelines every render may use: the 8 colour-pass specialisations, the exposure window pass
    /// and the preview downsample. Called once at launch (and by ParityRunner); cheap after the first call.
    public func prepareCommonPipelines() async throws

    static func colourConstants(srgb: Bool, straight: Bool, post: Bool) -> FunctionConstants

    // MARK: Textures and buffers

    public func texture(_ spec: TextureSpec) throws -> any MTLTexture

    public func recycle(_ texture: any MTLTexture, spec: TextureSpec)

    /// Returns an encode's transient textures to the pool. Call only after its command buffers completed and nothing
    /// shows its intermediates any more (the next encode on the same pipeline instance, §5.8 rule 5).
    public func recycle(_ encoded: EncodedBlur)

    /// A shared buffer holding `values` (weights, offsets, tap lists). ≤ 4 KB may use setBytes instead.
    public func buffer(_ values: [Float]) throws -> any MTLBuffer

    /// A zero-filled shared buffer for trace records: `passes` blocks of TraceLayout.passStride(capacity:).
    public func traceBuffer(passes: Int, capacity: Int, probe: PixelPoint) throws -> any MTLBuffer

    // MARK: Safe dispatch (ARCHITECTURE §4.4)

    /// The preferred size (16 × 16 for 2-D tiles; 256 × 1 or 1 × 256 for row and column tiles) halved until it fits
    /// min(pipeline limit, device or forced-Apple2 limit).
    public func threadgroupSize(for pso: any MTLComputePipelineState, preferred: MTLSize = MTLSize(width: 16, height: 16, depth: 1)) -> MTLSize

    /// The only way compute work is dispatched: dispatchThreadgroups over a grid covering width × height.
    /// Kernels bounds-check AFTER their threadgroup loads and barriers.
    @discardableResult
    public func dispatch2D(_ encoder: any MTLComputeCommandEncoder, pso: any MTLComputePipelineState, width: Int, height: Int,
                           preferred: MTLSize = MTLSize(width: 16, height: 16, depth: 1), threadgroupMemory: Int = 0,
                           label: String) throws -> (threadgroups: MTLSize, threadsPerThreadgroup: MTLSize)

    // MARK: Specimens and the full blur (pre/post passes of ARCHITECTURE §4.2)

    /// Uploads fp16 texel bytes once (shared staging buffer → private rgba16Float texture via a blit), and waits.
    /// The Float → Float16 conversion happens before, off the main actor (`HalfImageData`, review fix E-9).
    public func upload(_ image: HalfImageData, roles: TextureRole = [.read]) async throws -> any MTLTexture

    /// The pan: the N × N window at an integer offset from the canvas texture (SPEC §4.1.3). At 0 EV a blit copy; otherwise
    /// the render pass `b2_common_window_fs`, which also multiplies by 2^EV (exposure at render time, review fix E-10).
    /// `destination` needs `.renderTarget` when `exposureEV != 0`.
    public func encodeWindowCopy(canvas: any MTLTexture, margin: Int, pan: PixelPoint, size: Int, exposureEV: Int = 0,
                                 destination: any MTLTexture, recorder: GPUCommandRecorder) throws
    /// Layout of `B2CommonWindowParams` in B2Common.metal.
    struct WindowParams { var originX: Int32; var originY: Int32; var gain: Float; var pad: Float }

    /// The frozen preview input (review fix E-4): `destination` (⌊w/2⌋ × ⌊h/2⌋) = 2 × 2 mean of `source`
    /// (`b2_common_downsample2x_fs`; CPU twin `ImageBuffer.downsampled2x`). Quarter previews apply it twice.
    public func encodeDownsample2x(source: any MTLTexture, destination: any MTLTexture, recorder: GPUCommandRecorder) throws

    /// The colour/alpha pre- or post-pass (B2Common.metal `b2_common_colour_fs`, function constants 4–6).
    public func encodeColourPass(post: Bool, settings: SilentSettings, source: any MTLTexture, destination: any MTLTexture,
                                 recorder: GPUCommandRecorder) throws

    /// Runs one blur exactly as the app and blur-gpucheck must: colour pre-pass → pipeline → colour post-pass.
    /// Pipelines never implement colour-space or alpha handling themselves.
    public func encodeFullBlur(_ pipeline: any GPUBlurPipeline, window: any MTLTexture, output: any MTLTexture,
                               request: OperatorRequest, auxiliary: GPUAuxiliaryTextures = GPUAuxiliaryTextures(),
                               quality: RenderQuality = .full, trace: TraceRequest?, recorder: GPUCommandRecorder) throws -> EncodedBlur

    /// Encodes a region readback into `recorder` (by default with the post-pass work), so a render's probe texel costs
    /// no extra command buffer (review fix E-26). Decode the result after `recorder.commitAndWait()`.
    public func encodeReadTexels(_ texture: any MTLTexture, region: PixelRegion, level: Int = 0, recorder: GPUCommandRecorder,
                                 pass: Int = GPUCommandRecorder.postPass) throws -> PendingReadback

    // MARK: Running and reading back (frozen pattern: continuation + completion handler, Sendable payload)

    public func commit(_ commandBuffer: any MTLCommandBuffer) async -> GPUCompletion

    /// Reads a region as Float RGBA through a blit into a shared buffer (never getBytes on a mip level, GPU §2.7 item 7).
    public func readTexels(_ texture: any MTLTexture, region: PixelRegion, level: Int = 0) async throws -> [SIMD4<Float>]

    public nonisolated static func decodeRGBA(buffer: any MTLBuffer, count: Int, format: MTLPixelFormat) -> [SIMD4<Float>]
}
```

##### `Sources/BlurGPU/Core/GPUServices.swift`

```swift
// Sources/BlurGPU/Measure/ and Sources/BlurGPU/AppleTwins/). The app installs the implementations at launch.

public struct TimingRequest: Sendable, Hashable {
    public var warmups: Int
    /// Maximum timed samples (15).
    public var samples: Int
    /// Stop early once this many samples exist and summed GPU time reached `maxGPUSeconds` (review fix E-7).
    public var minSamples: Int
    public var maxGPUSeconds: Double
    public var isolation: PassIsolation
    /// Also time the fused form (fewest encoders) to report MEASUREMENT OVERHEAD.
    public var measureFused: Bool
    public init(warmups: Int = 3, samples: Int = 15, minSamples: Int = 3, maxGPUSeconds: Double = 1.0,
                isolation: PassIsolation = .singleCommandBuffer, measureFused: Bool = false)
}

/// SPEC §4.1.6: timing only after settle, at full resolution; returns nil in the Simulator (never a number).
/// Times the BLUR PASSES only (the pipeline's encode on an already pre-passed input); colour passes and the window copy
/// are timed once separately into `overheadMilliseconds` (review fix E-57). Budgeted and cancellable (E-7): it checks
/// `Task.isCancelled` between command buffers and throws `CancellationError` (every touch cancels it), stops at
/// `request.samples` or `maxGPUSeconds`, and is never called when the plan exceeds `FetchBudget.full`.
@MainActor
public protocol GPUTimingMeasuring: AnyObject {
    func measure(_ pipeline: any GPUBlurPipeline, inputs: GPUBlurInputs, request: TimingRequest,
                 context: GPUContext) async throws -> TimingSummary?
    /// ABAB interleaving for Compare's ΔGPU (thermal state recorded at both ends).
    func measureInterleaved(_ a: (any GPUBlurPipeline, GPUBlurInputs), _ b: (any GPUBlurPipeline, GPUBlurInputs),
                            request: TimingRequest, context: GPUContext) async throws -> (TimingSummary, TimingSummary)?
    /// A stage-boundary sampler for one recorder, or nil when the device has no stage-boundary counters.
    func makeSampler(passes: Int, context: GPUContext) -> (any PassTimestampSampling)?
}

/// SPEC §4.7 This phone; on demand only (JF G-17), never at launch.
@MainActor
public protocol DeviceProbing: AnyObject {
    func run(_ kind: DeviceProbeKind, context: GPUContext, device: DeviceStamp) async throws -> DeviceProbeResult
}

/// Core Image / MPS / vImage twins run in-process on this device (SPEC §8.2 Apple axis, §13.1).
@MainActor
public protocol AppleTwinRunning: AnyObject {
    func supports(_ subject: CalibrationSubject) -> Bool
    /// Runs the Apple API with its own parameter on `input` (window-sized rgba16Float, linear) into `output`.
    func run(_ subject: CalibrationSubject, parameter: Double, input: any MTLTexture, output: any MTLTexture,
             context: GPUContext) async throws
    /// Renders a step edge (and its 45° twin) through the API at `phases` whole-pixel offsets and returns edge samples
    /// for the PSF fitter (Calibrate for Core Image / MPS / vImage subjects).
    func edgeSamples(_ request: CalibrationRequest, context: GPUContext) async throws -> [EdgeSamples]
}

/// GPU-side fingerprint measurement from impulse grid, 4-phase step edge, 1-px stripes and a star crop (SPEC §7.1 item 10).
@MainActor
public protocol ShapeMeasuring: AnyObject {
    func measure(_ pipeline: any GPUBlurPipeline, request: OperatorRequest, context: GPUContext) async throws -> ShapeMeasurement
}

/// Main-actor service locator; the skeleton installs placeholder conformers that report "not available yet" honestly,
/// the owning areas replace them (their concrete type names are fixed in ARCHITECTURE §8).
@MainActor
public enum GPUServices {
    public static var timing: (any GPUTimingMeasuring)?
    public static var probes: (any DeviceProbing)?
    public static var appleTwins: (any AppleTwinRunning)?
    public static var shapes: (any ShapeMeasuring)?
}
```

##### `Sources/BlurGPU/Core/ParityRunner.swift`

```swift
// pre/post passes, half-rounded input) and compares with BlurReference. Used by blur-gpucheck (all cases) and by the
// app's PARITY telemetry (a 128 × 128 crop). Implementation by SKEL; GPUCHECK extends reporting, not semantics.

public struct TracedComparison: Sendable, Hashable, Codable {
    /// Output words (fp16 channels) that differ between the traced and the untraced specialization.
    public var differingWords: Int
    /// The last traced pass's final record (flags = 2), rounded to fp16, equals the output at the probe (every channel).
    /// Compared only when that block did not overflow (review fix E-13).
    public var finalSumMatchesOutput: Bool
    public var tapsPerTracedPass: [Int]
    public var overflow: Int
    /// Set when a traced pass wrote no flags = 2 record.
    public var missingFinalRecord: Bool
    public var passed: Bool { get }
}

public struct ParityOutcome: Sendable, Codable {
    public var caseName: String
    public var evaluation: ParityEvaluation?
    public var traced: TracedComparison?
    /// Mac/phone GPU time of the untraced command buffer (MEASURED, informational; never from the Simulator).
    public var gpuMilliseconds: Double?
    /// What was compared: "full 256 × 256" or "3 crops of 128 × 128 at the probes".
    public var comparedRegions: String?
    public var failure: String?
    public var passed: Bool { get }
}

/// Which pixels the CPU reference computes (review fix E-8): the whole window at small sizes, 128 × 128 crops around
/// the case's probes (or the centre) at full size.
public enum ParityRegionPolicy: Sendable, Hashable {
    case fullWindow
    case crops(side: Int)
    public static func standard(windowSize: Int) -> ParityRegionPolicy
}

@MainActor
public enum ParityRunner {
    /// Compiles `B2Shared.h` + every `*.metal` in `directory` as ONE translation unit (ShaderManifest.assemble).
    public static func compileLibrary(device: any MTLDevice, shaderDirectory directory: URL, safeMath: Bool = false) throws
        -> (library: any MTLLibrary, manifest: ShaderManifest, source: String)

    /// The GPU half runs on the main actor; canvas generation, fp16 conversion and the CPU reference run in detached
    /// tasks on Sendable values (review fix E-8). `referenceOptions` is `.parity` on the Mac and
    /// `ReferenceOptions.forDevice(probes)` in the app.
    public static func run(_ parityCase: ParityCase, factory: GPUPipelineFactory, context: GPUContext,
                           text: TextCoverage? = nil, regions: ParityRegionPolicy? = nil,
                           referenceOptions: ReferenceOptions = .parity) async -> ParityOutcome
}
```

##### `AppContract/Engine/EngineAPI.swift`

```swift
// here are placeholders that only prove the signatures compile. The skeleton writes working bodies in
// App/Engine/{AppSettings,TelemetryModel,RunLogStore,SpecimenStore,RenderCoordinator,TraceSession,BenchModel}.swift;
// ENGINE owns those files afterwards. Everything is @MainActor; heavy CPU work (canvases, references, floor pages,
// fingerprint vectors) runs in Task.detached on Sendable values and returns to the main actor (§5.15).

public enum DisplayMode: String, Sendable, Codable, CaseIterable { case sdr, edr }
public enum BadgeStyle: String, Sendable, Codable, CaseIterable { case words, compactGlyphsOnChips }

/// Settings › (SPEC §4.7). Persisted in UserDefaults by `load`/`save`. Owner: ENGINE (UI-FIELDGUIDE builds the form).
@MainActor @Observable
public final class AppSettings {
    public var homeToolID: String = "swiftui"
    public var matchSigmaOnSwitch: Bool = true
    public var hapticsEnabled: Bool = true
    public var displayMode: DisplayMode = .sdr
    public var badgeStyle: BadgeStyle = .compactGlyphsOnChips
    public var silentDefaults: SilentSettings = .standard
    public var coachingLineArmed: Bool = true
    public init()
    public func load(from defaults: UserDefaults = .standard)
    public func save(to defaults: UserDefaults = .standard)
}

/// Live numbers observed only by the telemetry leaf views (Toothpaste lesson, METRO §F.5 item 4). Written by ENGINE.
@MainActor @Observable
public final class TelemetryModel {
    public var sigmaEff: BadgedValue?
    public var gpu: BadgedValue?
    public var parity: BadgedValue?
    /// Compare mode: ΔGPU (A − B), the axis-specific column, MAX |A−B| with its position.
    public var deltaGPU: BadgedValue?
    public var axisColumn: LabeledValue?
    public var maxDifference: BadgedValue?
    public var maxDifferenceAt: PixelPoint?
    public init()
}

/// The Run log (SPEC §4.7 Runs; JF G-19): persisted JSON in Application Support, exportable through ShareLink.
@MainActor @Observable
public final class RunLogStore {
    public private(set) var runs: [Run] = []
    public init(directory: URL? = nil)
    public func append(_ run: Run)
    public func delete(_ ids: Set<UUID>)
    public func eraseMeasurements()
    public func exportJSON() throws -> Data
    /// Newest per kind / subject, for LiveFacts.
    public var deviceProbes: [DeviceProbeResult] { get }
    public var calibrations: [CalibrationResult] { get }
    public func latestTimed(for configuration: RenderConfiguration) -> Run?
}

/// Generates and caches specimen canvases off the main actor (cached per id, options and window size).
@MainActor
public final class SpecimenStore {
    public init()
    public func canvas(_ id: SpecimenID, options: SpecimenOptions, windowSize: Int) async -> SpecimenCanvas?
    public func install(photo canvas: SpecimenCanvas)
}

/// Owns all GPU work for the app. Textures never leave it; it returns Runs (Sendable values).
/// At most one render per slot is in flight; newer requests coalesce (latest wins; RenderScheduler.acknowledge).
@MainActor
public final class RenderCoordinator {
    public let gpu: GPUContext
    public let specimens: SpecimenStore
    /// Bumped whenever a display texture changes; the PresentRenderer redraws on change.
    public private(set) var displayGeneration: UInt64 = 0
    public var onDisplayChanged: (@MainActor () -> Void)?
    public init(gpu: GPUContext, specimens: SpecimenStore)

    /// Encodes, commits and awaits one render; the probe texel is read back inside the same recorder
    /// (`encodeReadTexels`). Previews (`.half`, `.quarter`) render `op.previewRequest` from the 2 × 2-mean input and are
    /// never timed, traced or parity-checked. Throws `GPUError.notPrepared` (the previous Run stays) until `prepare`
    /// finished. Returns nil when the result was superseded (an equal-or-newer generation was already published).
    /// Pipeline instances: one per (slot, blur, variant) for display, separate ones for timing and parity, so later
    /// encodes never overwrite the intermediates the periscope, Algorithm floor and Trace show (review fix E-11).
    public func render(_ request: RenderRequest) async throws -> Run?
    /// Budgeted timing (TimingRequest: 3 warm-ups, up to 15 samples or 1 s of GPU time, minimum 3), ABAB with `other`
    /// in Compare; skipped above FetchBudget.full (`TOO SLOW TO TIME`). Cancelled by `cancelMeasurements` (any touch).
    /// Never in the Simulator.
    public func time(_ configuration: RenderConfiguration, slot: RunSlot, interleavedWith other: RenderConfiguration?) async throws -> [Run]
    /// GPU vs BlurCore on a 128 × 128 crop around the probe (ParityRunner semantics, `referenceCrop`), with
    /// `ReferenceOptions.forDevice(probes)`; runs after timing at background priority; cancellable.
    public func parity(_ configuration: RenderConfiguration, slot: RunSlot) async throws -> ParitySummary?
    /// Cancels timing and parity in flight for a slot (between command buffers); called on every touch.
    public func cancelMeasurements(slot: RunSlot?)
    /// The newest output for a slot, or a pass intermediate (Algorithm floor, periscope), or the input window. Valid until
    /// the next display encode of that slot's pipeline instance (readbacks for Trace and periscope happen before it).
    public func displayTexture(slot: RunSlot, pass: Int?) -> (any MTLTexture)?
    public func inputTexture(slot: RunSlot) -> (any MTLTexture)?
    /// Blit readback of a region of a slot's output or pass intermediate (Float RGBA, linear).
    public func readTexels(slot: RunSlot, pass: Int?, region: PixelRegion) async throws -> [SIMD4<Float>]
    /// 128 × 128 renders for the fingerprint strip (PSF / STAR / EDGE inputs) at σ_equiv 4 px, LIVE from our Metal
    /// implementation. Never called for Tier S entries (their strip comes from `SystemOffscreen.renderStrip`).
    public func renderStrip(_ configuration: RenderConfiguration) async throws -> [ImageBuffer]
}

/// The pixel walk (SPEC §6). While a session is open, the Bench and periscope render the TRACED specialization.
@MainActor @Observable
public final class TraceSession {
    public private(set) var record: TraceRecord?
    public private(set) var steps: [TraceStep] = []
    public private(set) var stepIndex: Int = 0
    public private(set) var subStepIndex: Int = 0
    public private(set) var isPlaying: Bool = false
    /// The 9 × 9 (or 17 × 17 Magnify) copy of the probe's neighbourhood for the context card.
    public private(set) var contextGrid: TexelGridSpec?
    public init()
    public var current: TraceStep? { get }
    public func start() async
    public func next()
    public func back()
    public func restart()
    public func finishPass()
    public func jump(to floor: Floor)
    public func play()
    public func pause()
    public func setMagnified(_ on: Bool)
    public func close()
}

/// The Bench: one source of truth for requested state; everything output-derived follows the newest acknowledged Run.
@MainActor @Observable
public final class BenchModel {
    // Requested state (controls write it; shown immediately).
    public private(set) var configuration: RenderConfiguration
    public private(set) var view: WindowViewState
    public private(set) var compare: CompareState?
    // Acknowledged state (from Runs).
    public private(set) var acknowledged: [RunSlot: Run] = [:]
    public private(set) var lastTimed: [RunSlot: Run] = [:]
    public private(set) var phase: RenderPhase = .idle
    public private(set) var status: StatusLine = .phase(.empty)
    /// The newest FULL-resolution acknowledged Run per slot: PIXEL, loupe, pills, telemetry and Trace read this, never a
    /// preview (`RenderQuality.publishesMeasurements`); while a preview is on screen they show these values marked HELD.
    public private(set) var lastFull: [RunSlot: Run] = [:]
    public private(set) var railChips: [RailChip] = []
    public private(set) var pills: PillContent?
    public private(set) var loupe: LoupeReading?
    public private(set) var isInteracting: Bool = false
    public private(set) var isFirstLaunch: Bool = false
    // Navigation (one NavigationStack path, one sheet).
    public var path: [Route] = []
    public var sheet: SheetDestination?
    // Collaborators.
    public let settings: AppSettings
    public let telemetry: TelemetryModel
    public let runLog: RunLogStore
    public let renderer: RenderCoordinator

    public init(renderer: RenderCoordinator, settings: AppSettings, telemetry: TelemetryModel, runLog: RunLogStore,
                restoring snapshot: BenchSnapshot)

    public var entry: CatalogEntry? { get }
    public var op: (any BlurOperator)? { get }

    // Blur and parameters.
    /// Switches blur with σ-hold (SPEC §8.1) when MATCH σ is on; the previous blur becomes Compare's default B.
    public func selectBlur(_ id: BlurID)
    public func selectVariant(_ id: VariantID)
    public func setParameter(_ key: ParameterKey, _ value: ParameterValue)
    /// Crown detents: one FINE or SEMANTIC step on a parameter (drives B when `compare.drivingB`).
    public func step(_ key: ParameterKey, by detents: Int, semantic: Bool)
    public func setSilent(_ settings: SilentSettings)
    // Test image, probe and view.
    public func setSpecimen(_ id: SpecimenID, options: SpecimenOptions)
    public func setPhoto(_ canvas: SpecimenCanvas)
    public func setProbe(_ probe: PixelPoint)
    public func availableJumps() -> [ProbeJump]
    public func jumpProbe(_ jump: ProbeJump) async
    public func setPan(_ pan: PixelPoint)
    public func setZoom(_ zoom: Double, centre: SIMD2<Double>)
    public func setSplit(_ split: Double?)
    public func showPass(_ index: Int?)
    public func setLoupe(_ centre: PixelPoint?) async
    public func beginInteraction()
    public func endInteraction()
    /// Handle drags write their parameters (window pixels) through here.
    public func moveHandle(_ handle: HandleKind, parameter: ParameterKey, to value: ParameterValue)
    // Compare.
    public func startCompare(_ state: CompareState?)
    public func updateCompare(_ state: CompareState)
    public func legalChoices(axis: CompareAxis) -> [CompareChoice]
    public func swapCompare()
    public func setDrivingB(_ on: Bool)
    public func endCompare()
    // Lessons.
    public func apply(_ lesson: Lesson)
    // Content (computed off the main actor from Sendable inputs).
    public func floorContext(slot: RunSlot) -> FloorContext?
    public func floorPages() async -> [FloorPage]
    public func makeTraceSession() -> TraceSession
    public func fingerprintCard(for id: BlurID) async -> FingerprintCardModel?
    public func divergence(_ a: RenderConfiguration, _ b: RenderConfiguration) -> [FloorComparison]
    public func fieldGuidePage(for id: BlurID) async -> FieldGuidePage?
    // Lifecycle.
    public func handleLaunch(_ launch: LaunchScenario.Launch?)
    public func snapshot() -> BenchSnapshot
    /// The scheduler clock (CADisplayLink or a 30 Hz timer while needed): settle, timing, idle calibration.
    public func tick(now: Double)
}
```

##### `AppContract/Render/PresentAPI.swift`

```swift
// the window in device pixels, presenting the newest output 1 : 1 (nearest) or a magnified copy, the before/after split,
// the compare views and Line-up. Shaders: B2Present.metal. Used by the Bench window and the Layers periscope.

public enum PresentMode: Sendable, Hashable {
    /// Output only, or the before/after split when `split` is set.
    case output
    /// Compare views (Wipe, Flip, Difference × gain, Line-up 2 × 2).
    case compare(CompareView)
    /// Periscope: a crop of the same output texture (or a pass intermediate) around the probe.
    case crop(PixelRegion)
}

public struct PresentOptions: Sendable, Hashable {
    public var mode: PresentMode
    /// Before/after split 0…1 (input left of the divider), nil = off.
    public var split: Double?
    public var zoom: Double
    public var zoomCentre: SIMD2<Double>
    /// Show a pass intermediate instead of the final output.
    public var pass: Int?
    /// Flip view: true while B is held.
    public var showingB: Bool
    public var displayMode: DisplayMode
    public init(mode: PresentMode = .output, split: Double? = 0.5, zoom: Double = 1, zoomCentre: SIMD2<Double> = SIMD2(447, 447),
                pass: Int? = nil, showingB: Bool = false, displayMode: DisplayMode = .sdr)
}

/// The MTKView delegate. Draws only when asked (isPaused = true, enableSetNeedsDisplay = true) and while a gesture or
/// crown is active. The drawable is bgra8Unorm with an sRGB-tagged layer; the present shader encodes and clips (SDR).
@MainActor
public final class PresentRenderer: NSObject, MTKViewDelegate {
    public let coordinator: RenderCoordinator
    public var options: PresentOptions
    public init(coordinator: RenderCoordinator, options: PresentOptions = PresentOptions())
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    public func draw(in view: MTKView)
}

/// SwiftUI host of the MTKView plus the UIKit touch layer that feeds SpecimenGestureArbiter (BlurCore/Interaction).
/// The whole frame is wrapped in `instrumentControlOwnsTouches(identifier: "specimen")` by the Bench (Metro A.16).
public struct MetalSpecimenView: UIViewRepresentable {
    public let renderer: PresentRenderer
    /// Handle hit targets in window points (44-pt targets); empty for the periscope.
    public var handles: [HandleTarget]
    /// Gesture intents from the arbiter, already prioritised (handle > pinch > loupe > pan > tap).
    public var onIntent: @MainActor (GestureIntent) -> Void
    /// Window side in device pixels (894 on the 15 Pro Max): the drawable is exactly this, never auto-resized.
    public var windowPixels: Int
    public init(renderer: PresentRenderer, windowPixels: Int = 894, handles: [HandleTarget] = [],
                onIntent: @escaping @MainActor (GestureIntent) -> Void = { _ in })
    /// Review fix E-20: a fixed N × N drawable (no autoResizeDrawable, so fractional layout cannot make it 893 px and
    /// silently resample the 1 : 1 present), the screen's scale, and an sRGB-tagged layer. A phone AppTest asserts it.
    public func makeUIView(context: Context) -> MTKView
    public func updateUIView(_ view: MTKView, context: Context)
}
```

##### `AppContract/DesignSystem/ComponentAPIs.swift`

```swift
// App/DesignSystem/. The initialisers are frozen; bodies here are placeholders. Starter files (InstrumentDesignSystem,
// InstrumentControlTouchBoundary, LensRefraction, InstrumentLensOptics.metal) are copied verbatim and never edited.

public enum HonestyBadgeStyle: Sendable { case word, glyph }

/// The capsule badge (SPEC §12.1): the WORD is primary; glyph and ink are redundant; INFERRED has a dashed border.
/// `.glyph` is used only on rail chips (9 pt), with the word spoken.
public struct HonestyBadge: View {
    public let provenance: Provenance
    public let qualifiers: Qualifiers
    public let style: HonestyBadgeStyle
    public init(_ provenance: Provenance, qualifiers: Qualifiers = [], style: HonestyBadgeStyle = .word)
    public var body: some View { get }
}

public enum BadgedValueLayout: Sendable { case row, telemetry, chip, inline }

/// A number (or its words) with its unit, badge, caption and VoiceOver phrase, in reserved monospaced width.
public struct BadgedValueText: View {
    public let value: BadgedValue
    public let layout: BadgedValueLayout
    public init(_ value: BadgedValue, layout: BadgedValueLayout = .row)
    public var body: some View { get }
}

/// A native Stepper over Int tenths (or the spec's step), labelled in the domain unit; Binding written before the callback.
public struct DecimalParameterStepper: View {
    public init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, decimals: Int,
                unit: String, spokenUnit: String, onAcceptedChange: @escaping (Double) -> Void = { _ in })
    public var body: some View { get }
}

public enum CrownRole: Sendable { case fine, semantic, angle, second }

/// The metal crown (Metro §10; port of TempoCrownsView): 62 pt between real 44 × 44 glass ± Buttons, CrownDetentTracker +
/// DetentRateLimiter, 7-pt centre exclusion, haptics per role, adjustable action with the same step. Never in a TimelineView.
public struct InstrumentCrown: View {
    public init(caption: String, subcaption: String, role: CrownRole, detentDegrees: Double, isEnabled: Bool = true,
                accessibilityLabel: String, accessibilityValue: String, onStep: @escaping (Int) -> Void)
    public var body: some View { get }
}

public enum PillFamily: Sendable { case wave, spectrum }

/// A vertical signal pill (Metro §11), 36 × 212.5: static 0.8-pt outline and title; only the interior eases (≤ 150 ms).
/// KERNEL runs downward (−extent … +extent); FREQ runs upward (DC … Nyquist); B dashed, C dotted, D dash-dot.
public struct InstrumentSignalPill: View {
    public init(_ content: PillPlot, family: PillFamily, comparisons: [PillPlot] = [])
    public var body: some View { get }
}

public enum EventTileState: Sendable, Hashable { case idle, current, done }
public struct EventTile: Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var caption: String?
    public var state: EventTileState
    public var accessibilityLabel: String
    public init(id: Int, title: String, caption: String?, state: EventTileState, accessibilityLabel: String)
}
/// The event-tile row (Metro §12 beat strip): pass tiles, Kawase offsets, Trace floor selector. 37 pt tall, radius 8, gap 7.
public struct InstrumentEventTiles: View {
    public init(_ tiles: [EventTile], height: CGFloat = 37, onSelect: @escaping (Int) -> Void)
    public var body: some View { get }
}

/// Reports the floating group's measured glass height (the scroll content's bottom reserve = height + 28).
public struct FloatingGroupHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat)
}

/// Three native glass controls in a GlassEffectContainer(spacing: 14), no backing strip (Metro §12; SPEC §4.1.7).
public struct InstrumentFloatingActionGroup<Leading: View, Primary: View, Trailing: View>: View {
    public init(@ViewBuilder leading: () -> Leading, @ViewBuilder primary: () -> Primary, @ViewBuilder trailing: () -> Trailing)
    public var body: some View { get }
}

/// The rectangular metal housing (radius 30, metalLight → metalDark, four-stop rim, shadow) around the image window.
public struct SpecimenHousing<Content: View>: View {
    public init(@ViewBuilder content: () -> Content)
    public var body: some View { get }
}

/// A blur's 2-D footprint drawn from its GlyphSpec in instrument cyan on recessed metal (strip, kernel well, catalog).
public struct FootprintGlyph: View {
    public init(_ glyph: GlyphSpec, size: CGFloat = 44, isSelected: Bool = false)
    public var body: some View { get }
}
```

##### `AppContract/Content/ContentViewsAPI.swift`

```swift
// App/Content/). Every screen that shows BlurCore content uses these: Layers, Trace, Field guide, Fingerprint, Atlas,
// Calibrate. Plots are Swift Charts with an AXChartDescriptor and a DisclosureGroup data table (SPEC §14).

/// One floor page: eyebrow + badges, question, signature, governing rule, figure, ≤ 6 numbers, `All … details`,
/// the IN THIS APP line, tabs (floor 6) and honest empty states. Slot heights come from the Dynamic Type size and the
/// largest content any blur puts on that floor, never from the current blur.
public struct FloorPageView: View {
    public init(_ page: FloorPage, selectedTab: Binding<String?> = .constant(nil), onPassSelected: @escaping (Int?) -> Void = { _ in })
    public var body: some View { get }
}

/// Any content block (paragraph, equation, values, table, code, figure, note, chips, sources, disclosure).
public struct ContentBlockView: View {
    public init(_ block: ContentBlock)
    public var body: some View { get }
}

/// Any figure; `height` is the reserved slot (plot inset 374 × 140 by default on floor pages).
public struct FigureView: View {
    public init(_ figure: FigureSpec, height: CGFloat = 140, onPassSelected: @escaping (Int?) -> Void = { _ in })
    public var body: some View { get }
}

/// A row of LabeledValues with badges at the trailing edge (one badge per number, at the number).
public struct LabeledValuesView: View {
    public init(_ rows: [LabeledValue])
    public var body: some View { get }
}

/// A Metal source listing with syntax colour, `@explain:` annotations, TRACE_PROBE lines highlighted and its SHA-256.
public struct ShaderSourceView: View {
    public init(_ code: CodeBlock)
    public var body: some View { get }
}
```

##### `AppContract/Fingerprint/FingerprintAPI.swift`

```swift
// Fingerprint sheet and compact below the fold on the Bench (UI-BENCH) — SPEC §7.1, §7.3.

public enum FingerprintCardStyle: Sendable { case full, compact }

public struct FingerprintCardView: View {
    /// `model` nil shows the fixed-height card skeleton with engraved "— NOT YET COMPUTED" cells (never a spinner).
    public init(model: FingerprintCardModel?, style: FingerprintCardStyle,
                onShowMe: @escaping (TellSpec) -> Void = { _ in },
                onNeighbour: @escaping (BlurID) -> Void = { _ in },
                onFloor: @escaping (Floor) -> Void = { _ in },
                onFullCard: @escaping () -> Void = {},
                onFieldGuide: @escaping () -> Void = {})
    public var body: some View { get }
}
```

##### `AppContract/Calibration/CalibrationAPI.swift`

```swift
// SwiftUI subjects render through ImageRenderer on the main actor, ONE render per run-loop turn (a render cannot be
// pre-empted), each measured: when one exceeds 16 ms the gap before the next doubles (× 2 back-off, reset after a render
// under 16 ms); no render while any control is active, and any touch pauses the queue (review fix E-21).
// Core Image / MPS / vImage subjects go through AppleTwinRunning.

public enum CalibrationState: Sendable, Hashable {
    case idle
    case running(done: Int, total: Int, subject: CalibrationSubject)
    case paused(done: Int, total: Int)
    case failed(String)
}

/// The black | white step that is blurred and fitted (CAL §7). Built by CALIBRATION.
public struct CalibrationEdgeView: View {
    public init(size: CGSize, edgeX: CGFloat, angleDegrees: Double = 0)
    public var body: some View { get }
}

/// Renders `blur(CalibrationEdgeView)` at `scale` and `colourMode` and reads the 16 centre rows in the blur's working
/// space (CAL §7 steps 1–3). Returns one EdgeSamples per phase; the fit is BlurServices.psfFitter's job.
@MainActor
public func measureEdges<Content: View>(_ request: CalibrationRequest,
                                       blur: @escaping (CalibrationEdgeView) -> Content) async -> [EdgeSamples]

@MainActor @Observable
public final class CalibrationService {
    public private(set) var state: CalibrationState = .idle
    public init(runLog: RunLogStore, gpu: GPUContext?)
    /// One measurement → a Run of kind .calibration appended to the log.
    public func measure(_ request: CalibrationRequest) async throws -> CalibrationResult?
    /// SwiftUI basic set: radii 0.5, 1, 2, 3, 4, 8 pt × 4 phases (SPEC §13.2); automatic only through the idle gate.
    public func runBasicSet() async
    /// The full sweep (34 radii × 4 phases, ≈ 12 s) on demand in Calibrate.
    public func runSweep(_ subject: CalibrationSubject) async
    public func pause()
    public func cancel()
    public func latest(_ subject: CalibrationSubject) -> CalibrationResult?
    /// The law fitted from this phone's sweep (nil until measured; the macOS law stays INFERRED until then).
    public func law(_ subject: CalibrationSubject) -> CalibrationLaw?
    /// Idle-gate hooks from the Bench (CalibrationIdleScheduler).
    public func noteTouch(at time: Double)
    public func setControlActive(_ active: Bool)
    public func tick(now: Double, thermal: ThermalLevel)
}
```

##### `AppContract/System/SystemAPIs.swift`

```swift
/// FAM-F10 (App/System/): the Tier S window content. For `swiftui-layer-blur`: a real SwiftUI Image with Apple's
/// `.blur(radius:opaque:)` left of a wipe, our MODELED Metal model right (`model` view supplied by UI-SPECIMEN).
/// For `liquid-glass` / `apple-uiblureffect`: the SwiftUI-drawn material-backdrop specimen with native glass or a
/// Material over it, draggable by its 44-pt grip. The only place glass sits over a specimen (SPEC §4.1.9 g).
public struct SystemExhibitView<Model: View>: View {
    public init(entry: CatalogEntry, configuration: RenderConfiguration, specimenImage: CGImage?, displayScale: CGFloat,
                split: Double, @ViewBuilder model: () -> Model)
    public var body: some View { get }
}

/// FAM-F10 (App/System/): offscreen renders of the REAL Apple effect for Tier S entries (review fixes P-31, P-39).
/// Values from here are MEASURED · OFFSCREEN (`Qualifiers.offscreen`); on-screen equivalence is UNVERIFIED.
public enum SystemOffscreen {
    /// PSF / STAR / EDGE at σ_equiv 4 px through ImageRenderer on the real modifier/material; nil when the entry cannot
    /// be rendered offscreen (glass), and the card then reads NOT YET MEASURED.
    @MainActor public static func renderStrip(entry: CatalogEntry, displayScale: CGFloat) -> [ImageBuffer]?
    /// The Tier S PIXEL chip: renders the same specimen view through ImageRenderer and reads the probe texel; nil (chip
    /// shows "—" with the spoken reason) when the effect is not capturable offscreen.
    @MainActor public static func probeTexel(entry: CatalogEntry, configuration: RenderConfiguration, specimenImage: CGImage,
                                             displayScale: CGFloat) -> SIMD4<Float>?
}

/// TESTIMAGES (App/Specimens/): the platform half of the test images.
public enum SpecimenPlatform {
    /// Core Text coverage of the four text lines at canvas size (SPEC §11 #10); BlurCore stays Foundation-only.
    @MainActor public static func textCoverage(canvasSide: Int, margin: Int, options: SpecimenOptions) -> TextCoverage
    /// A CGImage of a linear premultiplied buffer in extended linear sRGB (for SwiftUI views and exhibits).
    public static func cgImage(_ buffer: ImageBuffer) -> CGImage?
    /// PhotosPicker data → linear rgba16Float canvas, centre-cropped and area-averaged (caption `PHOTO · RESAMPLED ×s (BOX)`).
    public static func photoCanvas(from data: Data, windowSize: Int) async throws -> SpecimenCanvas?
}
```

### A.2 Value types (compact)

##### `Sources/BlurCore/Core/Identifiers.swift`

```swift
/// Shared string coding key so that dictionaries keyed by these identifiers encode as JSON objects.
public struct StringCodingKey: CodingKey, Sendable {
    public var stringValue: String
    public var intValue: Int? { get }
    public init?(stringValue: String)
    public init?(intValue: Int)
}

/// A canonical catalog id ("gaussian-blur"). Never shown on screen; the display name is.
public struct BlurID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable,
                      ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public var description: String { get }
    public var codingKey: any CodingKey { get }
    public init?<T: CodingKey>(codingKey: T)
    public static func < (a: BlurID, b: BlurID) -> Bool
}

/// A variant id ("gaussian-linear-sampling"): an implementation strategy of a catalog entry.
public struct VariantID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable,
                         ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public var description: String { get }
    public var codingKey: any CodingKey { get }
    public init?<T: CodingKey>(codingKey: T)
    public static func < (a: VariantID, b: VariantID) -> Bool
}

/// A test-image id ("night-city"). SPEC §11.
public struct SpecimenID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable,
                          ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public var description: String { get }
    public var codingKey: any CodingKey { get }
    public init?<T: CodingKey>(codingKey: T)
    public static func < (a: SpecimenID, b: SpecimenID) -> Bool
}

/// A parameter key inside one catalog entry ("sigma", "radius", "samples", "centreX").
public struct ParameterKey: RawRepresentable, Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable,
                            ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public var description: String { get }
    public var codingKey: any CodingKey { get }
    public init?<T: CodingKey>(codingKey: T)
    public static func < (a: ParameterKey, b: ParameterKey) -> Bool
}

/// A pixel of the image window (0…N−1), y down. Its centre is at (x + 0.5, y + 0.5) in texel coordinates.
public struct PixelPoint: Sendable, Codable, Hashable {
    public var x: Int
    public var y: Int
    public static let zero = PixelPoint(x: 0, y: 0)
    /// Texel-centre coordinates of this pixel.
    public var centre: SIMD2<Double> { get }
}

public struct ImageSize: Sendable, Codable, Hashable {
    public var width: Int
    public var height: Int
    public static func square(_ n: Int) -> ImageSize
    public var pixelCount: Int { get }
    public func contains(_ p: PixelPoint) -> Bool
}

/// An axis-aligned pixel rectangle (origin = top-left pixel).
public struct PixelRegion: Sendable, Codable, Hashable {
    public var origin: PixelPoint
    public var size: ImageSize
    /// A `side` × `side` square centred on `centre`, shifted to lie inside `bounds` when possible.
    public static func centred(on centre: PixelPoint, side: Int, inside bounds: ImageSize) -> PixelRegion
    public func contains(_ p: PixelPoint) -> Bool
}

/// The seven floors (SPEC §5). Raw values are the floor numbers shown on screen.
public enum Floor: Int, Sendable, Codable, CaseIterable, Comparable, Hashable {
    case slide = 1, api, math, kernel, algorithm, gpu, pixels
    public static func < (a: Floor, b: Floor) -> Bool

    /// Rail chip label on the Bench, at most 5 characters (SPEC §4.1.4).
    public var railLabel: String { get }
    /// Trace floor-selector tile label (SPEC §4.4).
    public var tileLabel: String { get }
    /// Title word: "Floor 4 · Kernel".
    public var title: String { get }
    /// Page eyebrow: "FLOOR 4 · KERNEL".
    public var eyebrow: String { get }
    /// The floor's one question, the same for every blur (SPEC §5.1).
    public var question: String { get }
}
```

##### `Sources/BlurCore/Core/Honesty.swift`

```swift
/// The six provenance labels. On screen the WORD is primary; glyph and ink are redundant cues (SPEC §12.1).
public enum Provenance: String, Sendable, Codable, CaseIterable, Hashable {
    case live = "LIVE"
    case measured = "MEASURED"
    case computed = "COMPUTED"
    case modeled = "MODELED"
    case reference = "REFERENCE"
    case inferred = "INFERRED"

    /// The word printed in the badge capsule.
    public var word: String { get }
    /// The word VoiceOver speaks after the value ("computed", "measured on iPhone 15 Pro Max").
    public func spokenPhrase(device: DeviceStamp?) -> String
}

/// Qualifiers that travel with a value. None of them is a seventh badge (SPEC §12.1).
public struct Qualifiers: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: UInt16
    /// The value itself is unknown: `text` holds words ("UNVERIFIED"), `value` must be nil.
    public static let unverified = Qualifiers(rawValue: 1 << 0)
    /// A number whose input is weak; `caption` says why ("UNVERIFIED PEAK"). Allowed only on MODELED or REFERENCE.
    public static let weakSource = Qualifiers(rawValue: 1 << 1)
    /// Two sources conflict; the UI shows the `SOURCES DISAGREE` caption under both rows.
    public static let sourcesDisagree = Qualifiers(rawValue: 1 << 2)
    /// Obtained in the iOS Simulator (Apple2-class GPU). Never a timing.
    public static let simulator = Qualifiers(rawValue: 1 << 3)
    /// Measured on another device (the research Mac) and shown on this one with that device's label.
    public static let notThisDevice = Qualifiers(rawValue: 1 << 4)
    /// Measured offscreen through `ImageRenderer`, not on screen.
    public static let offscreen = Qualifiers(rawValue: 1 << 5)
    /// An experimental path whose meaning is not yet confirmed (`ON-SCREEN · EXPERIMENTAL`).
    public static let experimental = Qualifiers(rawValue: 1 << 6)
    /// LIVE values computed on the CPU from the current image (adaptive weight maps): `LIVE · CPU`.
    public static let cpu = Qualifiers(rawValue: 1 << 7)
}

/// A citation: spec section, paper with year, vendor document, research file section, or URL.
public struct SourceRef: Sendable, Codable, Hashable {
    public var citation: String
    public var url: String?
}

/// ProcessInfo.ThermalState as a portable value.
public enum ThermalLevel: String, Sendable, Codable, Hashable, CaseIterable {
    case nominal, fair, serious, critical, unknown
}

/// Where and when a MEASURED value was obtained. Required on every MEASURED number.
public struct DeviceStamp: Sendable, Codable, Hashable {
    public var deviceModel: String      // "iPhone 15 Pro Max", "Mac (Apple M1 Max)"
    public var gpuName: String          // MTLDevice.name
    public var gpuFamily: String        // "Apple9"
    public var osVersion: String        // "iOS 27.0"
    public var osBuild: String          // "24A5355p"
    public var isSimulator: Bool
    public var date: Date
    public var thermal: ThermalLevel    // at the start of the measurement
    public var lowPowerMode: Bool

    /// "14 Oct" in the Gregorian calendar, UTC, independent of locale.
    public var dayLabel: String { get }
    /// The engraving that travels with MEASURED (SPEC §12.2 item 5): "iPhone 15 Pro Max · iOS 27.0 · 14 Oct".
    public var label: String { get }
    public var spokenDevice: String { get }
}

/// Every number that reaches the UI travels as a BadgedValue (build it with the factories in Formatting.swift).
public struct BadgedValue: Sendable, Codable, Hashable {
    /// The numeric value, or nil when only words are honest (UNVERIFIED, not yet measured).
    public var value: Double?
    /// The display text at the declared precision ("0.61", "UNVERIFIED", "–.––"), without the unit.
    public var text: String
    /// Unit symbol printed after the text ("ms", "px", "c/px"), or nil.
    public var unit: String?
    /// nil only for user inputs (`isInput`) and for pure words that make no claim.
    public var provenance: Provenance?
    public var qualifiers: Qualifiers
    public var source: SourceRef?
    /// Required when `provenance == .measured` and `value != nil`.
    public var device: DeviceStamp?
    /// Trailing caption in secondary ink ("UNVERIFIED PEAK", "SOURCES DISAGREE", "OFFSCREEN").
    public var caption: String?
    /// True for values the user set (hero, Stepper, typed): they carry no badge (SPEC §12.1).
    public var isInput: Bool
    /// The full VoiceOver phrase including the badge word ("0.61 milliseconds, measured on iPhone 15 Pro Max").
    public var spoken: String

    /// Text with its unit ("0.61 ms").
    public var textWithUnit: String { get }

    /// The honesty invariants of SPEC §12, checked by unit tests on all generated content (ARCHITECTURE §11.3).
    public var honestyViolations: [String] { get }
}

/// A labelled row: "TAPS · 73 · = COMPUTED".
public struct LabeledValue: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    /// ALL-CAPS mono label ("CENTRE WEIGHT").
    public var label: String
    public var value: BadgedValue
}

/// One piece of a status or caption line (review fix E-51): plain words, a literal that may contain digits
public enum BadgedSegment: Sendable, Codable, Hashable {
    case text(String)
    case literal(String)
    case value(BadgedValue)
    public var text: String { get }
    public var spoken: String { get }
}

/// A line of view-bound text in which every number travels as a BadgedValue (status row, σ-hold notice, captions,
public struct BadgedLine: Sendable, Codable, Hashable {
    public var segments: [BadgedSegment]
    /// A line of words only (digits in it are a lint violation).
    public static func words(_ text: String) -> BadgedLine
    public static let empty = BadgedLine([])
    public var text: String { get }
    public var spoken: String { get }
    public var values: [BadgedValue] { get }
    public var honestyViolations: [String] { get }
}
```

##### `Sources/BlurCore/Core/Formatting.swift`

```swift
/// "32 samples", "1 pass".
public struct CountNoun: Sendable, Codable, Hashable {
    public var singular: String
    public var plural: String
    public func word(for value: Double) -> String
}

public struct NumberStyle: Sendable, Codable, Hashable {
    public enum Precision: Sendable, Codable, Hashable {
        /// Fixed decimals (0 = integer).
        case decimals(Int)
        /// Significant digits; scientific notation outside 10⁻³ … 10⁶.
        case significant(Int)
    }
    public var precision: Precision
    /// Unit symbol printed after the number ("px", "ms", "%", "c/px").
    public var unit: String?
    /// Unit as spoken ("pixels", "milliseconds"); falls back to `unit`.
    public var spokenUnit: String?
    /// For counts: the noun replaces the unit ("32 samples").
    public var noun: CountNoun?
    /// Thousands separators ("2,401").
    public var grouping: Bool
    /// Print "+" on positive values ("PAN +36 PX").
    public var explicitPlus: Bool

    public static func decimals(_ d: Int, unit: String? = nil, spokenUnit: String? = nil) -> NumberStyle
    public static func integer(noun: CountNoun? = nil, unit: String? = nil, spokenUnit: String? = nil) -> NumberStyle
    public static func significant(_ n: Int, unit: String? = nil, spokenUnit: String? = nil) -> NumberStyle

    /// The unit or noun printed after the number, for `value`.
    public func unitText(for value: Double) -> String?

    /// The number alone ("0.03332", "2,401", "−0.217", "7.1·10⁻⁴", "∞").
    public func text(_ value: Double) -> String

    /// The spoken form, including the unit or noun ("minus 0.217", "32 samples", "7.1 times 10 to the minus 4").
    public func spoken(_ value: Double) -> String

}

public extension BadgedValue {
    /// A badged number. MEASURED numbers must pass `device`.
    static func number(_ value: Double, _ style: NumberStyle, _ provenance: Provenance, qualifiers: Qualifiers = [],
                       source: SourceRef? = nil, device: DeviceStamp? = nil, caption: String? = nil) -> BadgedValue
    /// A value the user set (hero, Stepper, typed value): no badge.
    static func input(_ value: Double, _ style: NumberStyle) -> BadgedValue
    /// Words in place of a number ("N/A · RANK", "LINEAR-SAMPLED", "SOURCES DISAGREE").
    static func words(_ text: String, spoken: String? = nil, _ provenance: Provenance? = nil, qualifiers: Qualifiers = [],
                      source: SourceRef? = nil, device: DeviceStamp? = nil, caption: String? = nil) -> BadgedValue
    /// The value itself is unknown (SPEC §12.1): never a number.
    static func unverified(_ subject: String? = nil) -> BadgedValue
    /// A MEASURED slot that has no measurement yet ("–.––").
    static func notYetMeasured(_ placeholder: String = "–.––", unit: String? = nil) -> BadgedValue
}
```

##### `Sources/BlurCore/Core/Parameters.swift`

```swift
public enum ParameterUnit: String, Sendable, Codable, Hashable, CaseIterable {
    case px, pt, cssPx, percent, degrees, cyclesPerPixel, fractionOfFullScale, ev, fNumber, nanometres,
         micrometres, millimetres, sceneUnits, timesWhite, ratio, texels, pixelsSquared, levels, intensityPerPixel, none

    /// Symbol printed after the value ("px", "%", "°", "c/px"); nil when none.
    public var symbol: String? { get }
    /// Unit as VoiceOver speaks it.
    public var spokenName: String? { get }
}

/// How the FINE crown and the Stepper move a continuous value.
public enum StepScale: String, Sendable, Codable, Hashable {
    /// value ± fineStep, snapped to the fineStep grid.
    case linear
    /// Three detents per decade: … 0.01 · 0.02 · 0.05 · 0.1 … (log quantities: ε, noise-to-signal K).
    case oneTwoFive
    /// Photographic third stops: f = 2^(n/6); labels are the nominal markings (f/2.8).
    case thirdStops
}

/// A named stop of the SEMANTIC crown (20° detents). `id` marks stops whose value is replaced at runtime by a
public struct SemanticStop: Sendable, Codable, Hashable {
    public var value: Double
    public var label: String?
    public var id: String?
    public var provenance: Provenance?
}

/// A named meaning band ("Frosted" from 4 px). Blur2ool's own descriptive words, not a standard (SPEC §4.1.3).
public struct MeaningBand: Sendable, Codable, Hashable {
    public var lowerBound: Double
    public var name: String
}

public struct ContinuousSpec: Sendable, Codable, Hashable {
    public var range: ClosedRange<Double>
    /// One FINE crown detent (8°) and one Stepper step; also the display and spoken precision (Metro contract A.6).
    public var fineStep: Double
    public var decimals: Int
    public var scale: StepScale
    public var semanticStops: [SemanticStop]
    public var bands: [MeaningBand]

    public func clamped(_ v: Double) -> Double

    /// One FINE detent per `detents` (sign = direction). Clamped; turning past an end returns the end value.
    public func stepped(from v: Double, by detents: Int) -> Double

    /// One SEMANTIC detent: the next named stop strictly beyond `v` in the direction of `detents` (one stop per call).
    public func semanticStepped(from v: Double, by detents: Int, stops override: [SemanticStop]? = nil) -> Double

    /// The meaning band containing `v` (highest lower bound ≤ v).
    public func band(for v: Double) -> MeaningBand?

    /// The nominal label for third-stop values ("f/2.8"), nil for other scales.
    public func nominalLabel(for v: Double) -> String?

}

public enum IntegerParity: String, Sendable, Codable, Hashable { case any, odd, even }

public struct IntegerSpec: Sendable, Codable, Hashable {
    public var range: ClosedRange<Int>
    public var step: Int
    public var parity: IntegerParity
    /// Counts carry their noun ("32 samples"); magnitudes carry a unit instead (ParameterSpec.unit).
    public var noun: CountNoun?
    public var semanticStops: [Int]
    public func clamped(_ v: Int) -> Int
    /// One detent or Stepper press; respects `step` and parity; clamped.
    public func stepped(from v: Int, by detents: Int) -> Int
    public func semanticStepped(from v: Int, by detents: Int) -> Int
}

public struct ChoiceOption: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    /// A disabled option stays visible; this is its accessibility hint and one-line caption.
    public var disabledReason: String?
}

public struct ChoiceSpec: Sendable, Codable, Hashable {
    public var options: [ChoiceOption]
    /// 2–4 options → segmented picker (32 pt); 5 or more → Menu (44 pt) (SPEC §9.1).
    public var prefersMenu: Bool { get }
}

/// A per-pass integer sequence edited with event tiles (Kawase offsets "0 1 2 2 3"); its length is another parameter.
public struct SequenceSpec: Sendable, Codable, Hashable {
    public var elementRange: ClosedRange<Int>
    public var lengthKey: ParameterKey
}

public enum ParameterKind: Sendable, Codable, Hashable {
    case continuous(ContinuousSpec)
    case integer(IntegerSpec)
    case choice(ChoiceSpec)
    case toggle
    case sequence(SequenceSpec)
    /// A window position in window pixels, driven by an on-image handle with Stepper twins.
    case position
}

public enum ParameterValue: Sendable, Codable, Hashable {
    case double(Double)
    case int(Int)
    case choice(String)
    case bool(Bool)
    case intList([Int])
    case point(x: Double, y: Double)
}

/// Where a value applies: to the blur (default) or to the test image (the EXPOSURE crown of exponential-blur).
public enum ParameterScope: Sendable, Codable, Hashable {
    case blur
    case specimenExposure
}

public struct ParameterSpec: Sendable, Codable, Hashable, Identifiable {
    public var key: ParameterKey
    public var id: ParameterKey { get }
    /// ALL-CAPS label ("SIGMA", "RADIUS", "SAMPLES").
    public var label: String
    public var spokenLabel: String
    public var unit: ParameterUnit
    public var kind: ParameterKind
    public var defaultValue: ParameterValue
    public var scope: ParameterScope
    /// One line shown in the Parameters panel under the control, when needed ("σ = √(r(r+2)/6)").
    public var note: String?
    /// The readout unit line ("SIGMA · PX").
    public var unitLine: String { get }
    /// How the value is printed and spoken (display precision = fine step).
    public var numberStyle: NumberStyle { get }
}

/// A full set of parameter values for one blur.
public struct ParameterValues: Sendable, Codable, Hashable {
    public var storage: [ParameterKey: ParameterValue]
    public subscript(key: ParameterKey) -> ParameterValue?
    public func double(_ key: ParameterKey) -> Double?
    public func int(_ key: ParameterKey) -> Int?
    public func choice(_ key: ParameterKey) -> String?
    public func bool(_ key: ParameterKey) -> Bool?
    public func intList(_ key: ParameterKey) -> [Int]?
    public func point(_ key: ParameterKey) -> SIMD2<Double>?
}

// MARK: - Silent parameters shared by every blur (SPEC §9.3; ARCHITECTURE §4.2–§4.3)

public enum ColourSpace: String, Sendable, Codable, Hashable, CaseIterable { case linearLight, srgbEncoded }

/// Index mapping is identical on CPU and GPU (`b2_map_index` in B2Shared.h; ARCHITECTURE §4.3).
public enum EdgeMode: String, Sendable, Codable, Hashable, CaseIterable {
    case clamp, mirror, wrap, zero, renormalise

    /// The value of the function constant B2_EDGE_MODE (index 2).
    public var shaderIndex: UInt32 { get }
    /// Maps an index into [0, n); nil means "contributes zero" (zero) or "dropped" (renormalise).
    public func map(_ i: Int, count n: Int) -> Int?
}

public enum AlphaMode: String, Sendable, Codable, Hashable, CaseIterable { case premultiplied, straight }
public enum AccumulatorPrecision: String, Sendable, Codable, Hashable, CaseIterable { case fp32, fp16 }
/// `rgba8Unorm` intermediates appear only on the Compare › Precision axis.
public enum IntermediateFormat: String, Sendable, Codable, Hashable, CaseIterable { case rgba16Float, rgba8Unorm }
/// Summed-area tables: plain fp32 (the precision trap, default) or mean-centred (the fix); Compare › Precision axis.
public enum SATCentring: String, Sendable, Codable, Hashable, CaseIterable { case plain, meanCentred }
public enum PreviewPolicy: String, Sendable, Codable, Hashable, CaseIterable { case halfWhileMoving, alwaysFull }

public struct SilentSettings: Sendable, Codable, Hashable {
    public var colourSpace: ColourSpace
    public var edgeMode: EdgeMode
    public var alphaMode: AlphaMode
    public var accumulator: AccumulatorPrecision
    public var intermediate: IntermediateFormat
    public var satCentring: SATCentring
    public var preview: PreviewPolicy
    public static let standard = SilentSettings()
}

// MARK: - Deck arrangements (SPEC §9.1). Declared per entry in BlurCore, never inferred from live values.

public enum DeckArrangement: Sendable, Codable, Hashable {
    /// A: FINE (cyan, 8°) + SEMANTIC (amber, 20°) crowns on the same parameter.
    case crownPair(ParameterKey)
    /// B: FINE crown (magnitude) + ANGLE crown (cyan, 8° = 1°, semantic snaps at the symmetry stops).
    case fineAndAngle(fine: ParameterKey, angle: ParameterKey)
    /// C: two crowns, two continuous parameters (the second one amber, with its own name and detents).
    case twoCrowns(first: ParameterKey, second: ParameterKey)
    /// D: FINE crown on the left; a column of Stepper (48 pt) above a segmented picker or Menu (32–44 pt).
    case crownAndColumn(fine: ParameterKey, stepper: ParameterKey?, picker: ParameterKey?)
    /// E: no crown: event tiles or a segmented picker (and/or) above a Stepper.
    case tilesAndStepper(tiles: ParameterKey?, picker: ParameterKey?, stepper: ParameterKey?)
    /// The slot stays reserved and shows one engraved line.
    case none(message: String)
}
```

##### `Sources/BlurCore/Core/Catalog.swift`

```swift
public enum Family: String, Sendable, Codable, Hashable, CaseIterable {
    case f1 = "F1", f2 = "F2", f3 = "F3", f4 = "F4", f5 = "F5", f6 = "F6", f7 = "F7", f8 = "F8", f9 = "F9",
         f10 = "F10", f11 = "F11", contrast = "C"

    public var title: String { get }
    /// The family's question (CATALOG §1), shown beside the Catalog section eyebrow.
    public var question: String { get }
    /// "F1 · BOX, TENT & RUNNING SUMS".
    public var eyebrow: String { get }
}

public enum Tier: String, Sendable, Codable, Hashable, CaseIterable {
    case tier1, tier2, tier3, system
    /// Catalog chip text (SPEC §4.5).
    public var chip: String { get }
    /// Tier 3 entries are never on the blur strip and never on the Bench (SPEC §4.1.2, §10.4).
    public var runsLive: Bool { get }
}

/// CATALOG §1 verdict vocabulary.
public enum Verdict: String, Sendable, Codable, Hashable, CaseIterable {
    case trueBlur, adaptiveBlur, rankFilter, blurInExpectation, lsvBlur, composite, blurDerived, notABlur
    public var chip: String { get }
}

public enum LinearityClass: String, Sendable, Codable, Hashable, CaseIterable {
    /// Linear shift-invariant.
    case lsi
    /// Linear shift-variant (zoom, spin, motion fields, variable blur, depth of field).
    case lsv
    /// Nonlinear (adaptive weights, rank, PDE with edge stopping).
    case nonlinear
    /// Blur in expectation (stochastic).
    case expectation
    /// Apple system implementation: internals not exposed.
    case system
    public var chip: String { get }
}

public enum Separability: String, Sendable, Codable, Hashable {
    case yes, no, skew, approximate, notApplicable
}

public struct PropertyFlags: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: UInt16
    public static let linear = PropertyFlags(rawValue: 1 << 0)
    public static let shiftInvariant = PropertyFlags(rawValue: 1 << 1)
    public static let separable = PropertyFlags(rawValue: 1 << 2)
    public static let isotropic = PropertyFlags(rawValue: 1 << 3)
    /// Every kernel weight ≥ 0.
    public static let positiveKernel = PropertyFlags(rawValue: 1 << 4)
    /// Blurring twice equals blurring once with a larger parameter.
    public static let semigroup = PropertyFlags(rawValue: 1 << 5)
    /// H(ν) ≥ 0 everywhere: no contrast inversion.
    public static let nonNegativeResponse = PropertyFlags(rawValue: 1 << 6)
    public static let edgePreserving = PropertyFlags(rawValue: 1 << 7)
    public static let dataDependent = PropertyFlags(rawValue: 1 << 8)
}

public enum CostClass: String, Sendable, Codable, Hashable, CaseIterable {
    case constant = "O(1)", linearR = "O(r)", quadraticR = "O(r²)", logN = "O(log N)", samples = "O(S)",
         iterative = "ITER", search = "SEARCH", global = "FFT", capture = "CAPTURE", alu = "ALU"
    /// Classes that render a reduced-resolution preview while a control moves (SPEC §4.1.6), before parameter checks.
    public var isHeavyByDefault: Bool { get }
}

/// Decides how floors and traces are shaped (SPEC §5.2, §6.5).
public enum AlgorithmClass: String, Sendable, Codable, Hashable, CaseIterable {
    case separableFIR, gather2D, skewSeparable, recursive, runningSum, sparseIterated, spaceVariantGather,
         adaptiveWeighted, selection, iterativePDE, globalFFT, stochastic, temporal, system, derived, atlasOnly
}

public enum TraceDepth: Sendable, Codable, Hashable {
    /// Every fetch, tap or iteration, from TRACE_PROBE records (Tier 1).
    case full
    /// One declared stage with GPU records (Tier 2); the string names the stage ("blur stage").
    case stage(String)
    /// Frequency steps instead of fetches (FFT-based entries).
    case spectrum
    /// No GPU trace; floors 3–6 are the INFERRED lane (Tier S).
    case inferredLane
    /// Floors 1–4 and a CPU floor 7 only (Tier 3).
    case atlasOnly
}

/// How the footprint glyph is drawn (blur strip, kernel well, catalog rows). Pure data; the app draws it.
public enum GlyphKind: String, Sendable, Codable, Hashable, CaseIterable {
    case rings, square, squareCorners, tent, disc, polygon, rays, arcs, segment, ellipse, diagonalTaps, pyramid,
         notchedRing, dashedCircle, cross, wave, grid, comet, squiggle, dots, sun, spectrum, diamond, none
}

public struct GlyphSpec: Sendable, Codable, Hashable {
    public var kind: GlyphKind
    /// Kind-specific numbers: polygon sides, segment angle in degrees, ring count, ellipse aspect …
    public var values: [Double]
}

public enum HandleKind: String, Sendable, Codable, Hashable {
    /// ⊕ centre (zoom, spin, god rays' sun, cat's-eye swirl).
    case centre
    /// Two parallel focus lines (tilt-shift).
    case focusBand
    /// Ellipse centre plus one radius knob (iris blur).
    case irisEllipse
    /// Ramp start/end lines (variable blur).
    case rampEnds
    /// The Liquid Glass exhibit's shape grip.
    case glassGrip
}

public struct HandleSpec: Sendable, Codable, Hashable {
    public var kind: HandleKind
    /// Parameters the handle writes (positions in window pixels, widths in px).
    public var parameters: [ParameterKey]
}

/// An Apple implementation of (nearly) the same operator, for the Apple axis, floor 2 twins and Tier S.
public struct AppleTwinSpec: Sendable, Codable, Hashable {
    public var id: String                      // "CIGaussianBlur", "MPSImageGaussianBlur", "SwiftUI.blur"
    public var call: String                    // code text shown on floor 2
    public var mapping: String                 // "σ = inputRadius", "W = 2⌈r/2⌉ − 1"
    public var provenance: Provenance          // MEASURED / REFERENCE / INFERRED
    public var source: SourceRef
    /// The measurement subject in Calibrate, when the app can run it on this phone.
    public var subject: CalibrationSubject?
}

public struct VariantDescriptor: Sendable, Codable, Hashable, Identifiable {
    public var id: VariantID
    public var displayName: String             // "Linear-sampled"
    public var tier: Tier
    public var algorithmClass: AlgorithmClass
    public var costClass: CostClass
    /// False for CPU-only plots (Tier 3 variants such as `cubic-b-spline`).
    public var runsOnGPU: Bool
    /// True only for integer-tap FIR variants (SPEC §9.3 "Renormalise (FIR blurs only)").
    public var supportsRenormalise: Bool
    public var note: String?
}

/// The fingerprint card's TELL box (SPEC §7.1 item 7): the one test that gives the blur away.
public struct TellSpec: Sendable, Codable, Hashable {
    public var specimen: SpecimenID
    public var text: String
    /// Parameters that `Show me` applies (σ-held when nil).
    public var parameters: ParameterValues?
    public var probe: PixelPoint?
}

/// One of the card's six fixed rows; the numbers in `text` are CATALOG's CHECKED values (SPEC §7.1 item 4).
public struct CardRow: Sendable, Codable, Hashable {
    public var text: String
    public var provenance: Provenance
    public var source: SourceRef?
    public var disclosure: String?
}

/// PSF SHAPE · RESPONSE · EDGES · COST · ARTIFACTS · USED IN, in this order, for every entry.
public struct CardRows: Sendable, Codable, Hashable {
    public var psfShape: CardRow
    public var response: CardRow
    public var edges: CardRow
    public var cost: CardRow
    public var artifacts: CardRow
    public var usedIn: CardRow
    public var ordered: [(label: String, row: CardRow)] { get }
}

/// Everything static about one catalog entry.
public struct CatalogEntry: Sendable, Codable, Hashable, Identifiable {
    public var id: BlurID
    public var displayName: String
    public var family: Family
    public var tier: Tier
    public var verdict: Verdict
    public var linearity: LinearityClass
    public var separability: Separability
    public var properties: PropertyFlags
    public var costClass: CostClass
    public var algorithmClass: AlgorithmClass
    /// Verbatim from CATALOG §2 with the SPEC §17 truth fixes applied.
    public var signature: String
    /// Rail MATH chip text, ≤ 5 characters ("G", "rect", "tent", "disc", "hex", "exp", "ray", "arc", "rank", "w·f", "PDE", "FFT", "sys").
    public var mathSymbol: String
    public var glyph: GlyphSpec
    public var parameters: [ParameterSpec]
    /// The hero's parameter (requested value, no badge).
    public var primary: ParameterKey
    public var deck: DeckArrangement
    public var variants: [VariantDescriptor]
    public var defaultVariant: VariantID
    public var defaultSpecimen: SpecimenID
    public var handles: [HandleSpec]
    public var appleTwins: [AppleTwinSpec]
    public var tell: TellSpec
    /// NEAREST: two or three entries it is most often confused with (CATALOG §7).
    public var neighbours: [BlurID]
    public var traceDepth: TraceDepth
    /// Position in the blur strip's hero dozen (0…11), or nil.
    public var heroOrder: Int?
    public var card: CardRows
    /// Claims about this entry that stay UNVERIFIED, in words (Field guide).
    public var unverified: [String]
    /// Research file and sections holding the full entry ("LSI §2, §3, §4").
    public var detailReference: String
    public var sources: [SourceRef]

    /// Tier 3 entries never appear on the blur strip (SPEC §4.1.2).
    public var isOnStrip: Bool { get }
    public func spec(_ key: ParameterKey) -> ParameterSpec?
    public var primarySpec: ParameterSpec? { get }
    public func variant(_ id: VariantID) -> VariantDescriptor?
    public var defaultParameters: ParameterValues { get }
}
```

##### `Sources/BlurCore/Core/ImageBuffer.swift`

```swift
/// Linear light, premultiplied RGBA, row-major, y down. Values above 1 are allowed (HDR lights).
public struct ImageBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [SIMD4<Float>]

    public var size: ImageSize { get }

    public subscript(x: Int, y: Int) -> SIMD4<Float>

    /// Integer fetch with the shared edge mapping (`b2_fetch`). `renormalise` and `zero` return transparent black here;
    public func fetch(_ x: Int, _ y: Int, edge: EdgeMode) -> SIMD4<Float>

    /// Bilinear sample at texel coordinates (texel centres at i + 0.5), computed in Double, matching `b2_sample`.
    public func bilinear(_ u: Double, _ v: Double, edge: EdgeMode, subTexelBits: Int? = nil,
                         rounding: SubTexelRounding = .nearest) -> SIMD4<Double>

    /// Emulates `rgba16Float` storage: every channel rounded to the nearest half (what the GPU stores and samples).
    public func roundedToHalf() -> ImageBuffer

    /// A region copied with the given edge mapping for out-of-range pixels.
    public func crop(_ region: PixelRegion, edge: EdgeMode = .clamp) -> ImageBuffer

    public func map(_ transform: (SIMD4<Float>) -> SIMD4<Float>) -> ImageBuffer

    /// Every channel × `gain` (exposure 2^EV at render time; exact in fp16 for powers of two away from subnormals).
    public func scaled(by gain: Float) -> ImageBuffer

    /// The CPU twin of the frozen preview downsample `b2_common_downsample2x_fs`: output (x, y) = mean of input
    public func downsampled2x() -> ImageBuffer

    /// Largest channel magnitude of each pixel (for the local parity scale, ARCHITECTURE §7 rule 1).
    public var magnitudes: [Float] { get }
}

/// fp16 RGBA texel bytes ready for upload (review fix E-9): the conversion runs in BlurCore, off the main actor
public struct HalfImageData: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// width × height × 4 Float16 values, row-major (8 bytes per texel).
    public let bytes: Data
    public var bytesPerRow: Int { get }
}

/// Single-channel buffers for masks, depth and text coverage.
public struct ScalarBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [Float]
    public subscript(x: Int, y: Int) -> Float
}

/// Two-channel buffers for velocity fields (px per frame).
public struct VectorBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [SIMD2<Float>]
}

/// Extra inputs some blurs need (depth, velocity, guide image, mask, sub-frames, noise seed). Window-sized.
public struct AuxiliaryInputs: Sendable, Equatable {
    public var depth: ScalarBuffer?
    public var velocity: VectorBuffer?
    public var guide: ImageBuffer?
    public var mask: ScalarBuffer?
    public var subFrames: [ImageBuffer]?
    public var noiseSeed: UInt32
    public static let none = AuxiliaryInputs()
}

/// GPU-vs-CPU and A-vs-B difference statistics over all four channels.
public struct DifferenceStats: Sendable, Codable, Hashable {
    public var maxAbs: Double
    public var rms: Double
    /// Pixel (in the compared region's own coordinates) where |a − b| is largest.
    public var argmax: PixelPoint
    /// The largest difference in 8-bit sRGB code steps (both values clipped to 0…1 and encoded).
    public var maxLSB8: Double
    /// The largest difference in fp16 ulps of the reference value (ulp floor at 2⁻¹⁴).
    public var maxULP16: Double
    public var count: Int

    /// Compares `measured` against `reference` (same size) over the whole image.
    public static func compare(_ measured: ImageBuffer, _ reference: ImageBuffer) -> DifferenceStats
}
```

##### `Sources/BlurCore/Core/ColourTransform.swift`

```swift
public enum SRGB {
    /// IEC 61966-2-1 encode (linear → encoded). The formula continues above 1 (HDR) and its linear segment continues
    public static func encode(_ l: Double) -> Double
    public static func decode(_ e: Double) -> Double
    /// 8-bit code value of a linear value, clipped to 0…255.
    public static func code8(linear l: Double) -> Int
}

public enum HalfFloat {
    public static func round(_ x: Float) -> Float
    /// Spacing of fp16 values at |x|: the "1 ulp16" of the parity tolerances (ARCHITECTURE §7).
    public static func ulp(_ x: Float) -> Float
}

/// Rec. 709 luma on whatever values it is given (linear light or encoded, per the active colour space).
public enum Luma {
    public static func rec709(_ p: SIMD4<Float>) -> Float
}

/// The pre- and post-passes around every blur (ARCHITECTURE §4.2). Blur kernels never know the colour space or alpha mode.
public enum ColourTransform {
    public static func needsPasses(_ s: SilentSettings) -> Bool

    /// Before the blur: un-premultiply when straight alpha or sRGB-encoded; encode RGB when sRGB-encoded;
    public static func pre(_ p: SIMD4<Float>, _ s: SilentSettings) -> SIMD4<Float>
    /// After the blur: the exact inverse of `pre`.
    public static func post(_ p: SIMD4<Float>, _ s: SilentSettings) -> SIMD4<Float>
    public static func pre(_ image: ImageBuffer, _ s: SilentSettings) -> ImageBuffer
    public static func post(_ image: ImageBuffer, _ s: SilentSettings) -> ImageBuffer
    /// Colour of a fully transparent pixel is 0 (SPEC P19).
    public static func unpremultiply(_ p: SIMD4<Float>) -> SIMD4<Float>
    public static func premultiply(_ p: SIMD4<Float>) -> SIMD4<Float>
}

/// PCG hash, bit-identical to `b2_pcg` / `b2_uniform` in B2Shared.h (stochastic blurs, procedural noise).
public enum NoiseHash {
    public static func pcg(_ v: UInt32) -> UInt32
    /// Uniform in [0, 1] for pixel (x, y) and a seed.
    public static func uniform(x: UInt32, y: UInt32, seed: UInt32) -> Float
}
```

##### `Sources/BlurCore/Core/Kernels.swift`

```swift
/// A 1-D kernel. Weights are normalised to sum 1 unless the operator says otherwise.
public struct Kernel1D: Sendable, Codable, Hashable {
    public var weights: [Double]
    /// Index of offset 0 in `weights` (integer-offset kernels).
    public var origin: Int
    /// Fractional sample offsets in texels (linear-sampled kernels); nil for integer offsets `i − origin`.
    public var offsets: [Double]?
    /// Offset of tap i in texels.
    public func offset(_ i: Int) -> Double
    public var tapCount: Int { get }
    public var sum: Double { get }
    public var mean: Double { get }
    public var variance: Double { get }
    /// Second-moment σ in px (the "σ of the discrete kernel").
    public var sigma: Double { get }
    /// Excess kurtosis (Gaussian 0, box −1.2 continuous; SPEC §17 item 4).
    public var excessKurtosis: Double { get }
    public var normalised: Kernel1D { get }
}

/// A 2-D kernel sampled on the pixel grid, row-major, y down.
public struct Kernel2D: Sendable, Codable, Hashable {
    public var width: Int
    public var height: Int
    public var originX: Int
    public var originY: Int
    public var weights: [Double]
    /// Outer product of two integer-offset 1-D kernels.
    public subscript(x: Int, y: Int) -> Double
    public var sum: Double { get }
    /// The x marginal (column sums): the line-spread function along x.
    public var marginalX: Kernel1D { get }
    public var marginalY: Kernel1D { get }
}

/// The point-spread function at a point. For LSI blurs it is the same everywhere.
public struct PSF: Sendable, Codable, Hashable {
    public var kernel: Kernel2D
    /// True for LSV and adaptive blurs: valid only at `point`.
    public var isLocal: Bool
    public var point: PixelPoint?
    /// COMPUTED for analytic kernels; LIVE (with `.cpu`) when it depends on the current image (adaptive blurs).
    public var provenance: Provenance
}

public enum ResponseKind: Sendable, Codable, Hashable {
    /// Signed transfer function H(ν) of an LSI kernel along an axis (continuous or of the discrete taps).
    case signedTransfer
    /// Local signed transfer at a point (LSV blurs), along the local PSF's axis.
    case local(PixelPoint)
    /// Amplitude-dependent transfer T(ν, A) of an adaptive blur (NL §0).
    case amplitudeTransfer(amplitude: Double)
}

public struct ResponseQuery: Sendable, Codable, Hashable {
    /// Direction of the frequency axis in degrees (0 = horizontal).
    public var axisDegrees: Double
    public var samples: Int
    /// Highest frequency in cycles per pixel (Nyquist = 0.5).
    public var maxFrequency: Double
    /// For `.local`: the probe; for adaptive blurs: where the local contrast is measured.
    public var point: PixelPoint?
    /// For adaptive blurs: the amplitude A of T(ν, A).
    public var amplitude: Double?
    /// The continuous response (quiet trace) instead of the discrete taps' DFT (primary trace).
    public var continuous: Bool
    /// The evenly spaced frequencies 0 … maxFrequency.
    public var frequencies: [Double] { get }
}

public struct ResponseCurve: Sendable, Codable, Hashable {
    public var kind: ResponseKind
    /// Spatial frequency in cycles per pixel.
    public var frequencies: [Double]
    /// Signed H(ν) (or T(ν, A)); 1 at DC for a normalised blur.
    public var values: [Double]
    public var provenance: Provenance
    public var minimum: (frequency: Double, value: Double)? { get }
    public var nyquistValue: Double? { get }
    /// First frequency where the curve falls to `level` (linear interpolation): 0.5 → half amplitude,
    public func firstCrossing(of level: Double) -> Double?
}

/// A continuous profile (the pills' and floors' quiet reference trace).
public struct ProfileCurve: Sendable, Codable, Hashable {
    public var label: String
    public var xs: [Double]
    public var ys: [Double]
}

public enum PassKind: String, Sendable, Codable, Hashable, CaseIterable {
    case fragment, compute, blit, fft, mps, coreImage, cpu
}

/// One pass as the floors, the rail and the cost model describe it (COMPUTED from the operator).
public struct PassDescriptor: Sendable, Codable, Hashable, Identifiable {
    /// Index in the plan (0-based); equals the index of the GPU pass that implements it.
    public var id: Int
    /// Tile label: "H", "V", "↓1", "↑2", "SCAN ROWS", "FFT ROWS".
    public var name: String
    public var kind: PassKind
    /// Texture reads per output pixel after merging (COMPUTED).
    public var fetchesPerPixel: Double
    /// Logical taps per output pixel before merging.
    public var tapsPerPixel: Double
    /// Output resolution relative to the window (1, 0.5, 0.25 …).
    public var outputScale: Double
    /// True when the GPU pass writes TRACE_PROBE records.
    public var traceable: Bool
    public var summary: String
}

public struct PassPlan: Sendable, Codable, Hashable {
    /// The running variant's display name ("Linear-sampled").
    public var algorithmName: String
    public var passes: [PassDescriptor]
    public var notes: [String]
    /// Chebyshev radius in window pixels of everything the whole chain reads for one output pixel (bilinear fetches
    public var supportRadius: Int?
    /// Texture fetches for one frame at `size` (COMPUTED; the budget of review fix E-7).
    public func fetchesPerFrame(_ size: ImageSize) -> Double
    /// Logical taps one traced pass can record for one pixel, plus the final (flags = 2) record: the trace capacity.
    public var traceCapacity: Int { get }
    /// The status-row phase line with badged numbers ("74 FETCHES · 2 PASSES · LINEAR-SAMPLED").
    public var phase: BadgedLine { get }
    /// Σ over passes of fetches per output pixel, weighted by each pass's pixel count relative to the window.
    public var fetchesPerPixel: Double { get }
    /// The status-row phase line: "74 FETCHES · 2 PASSES · LINEAR-SAMPLED".
    public var phaseLine: String { get }
}

/// Fetches-per-frame budgets (review fix E-7; MODELED from research's M1 Max gather rate scaled to the A17 Pro,
public enum FetchBudget {
    public static let preview: Double = 2e8
    public static let full: Double = 2e9
    public static let bandMilliseconds: Double = 50
    /// MODELED A17 Pro gather rate (fetches per second), `weakSource`.
    public static let modeledFetchesPerSecond: Double = 15e9
}
```

##### `Sources/BlurCore/Core/Run.swift`

```swift
public enum RunKind: String, Sendable, Codable, Hashable, CaseIterable {
    case display, timing, trace, fingerprint, parity, calibration, probe
}

public enum RenderQuality: String, Sendable, Codable, Hashable {
    case full
    /// Half resolution while a control moves (SPEC §4.1.6); never timed, traced or parity-checked.
    case half
    /// Quarter resolution when even the half-resolution plan exceeds FetchBudget.preview (review fix E-7).
    case quarter
    public var scale: Double { get }
    /// Only full-resolution Runs publish PIXEL, loupe, pills, telemetry, Trace and parity (review fix P-36); previews
    public var publishesMeasurements: Bool { get }
}

/// Which image of the Bench a Run belongs to: A (crowns drive it), B, and C/D for Line-up.
public enum RunSlot: String, Sendable, Codable, Hashable, CaseIterable { case a, b, c, d }

/// The requested configuration of one image.
public struct RenderConfiguration: Sendable, Codable, Hashable {
    public var blur: BlurID
    /// The requested variant (the operator may resolve another one; see Run.resolvedVariant).
    public var variant: VariantID
    public var parameters: ParameterValues
    public var settings: SilentSettings
    public var specimen: SpecimenID
    public var specimenOptions: SpecimenOptions
    /// Integer pan of the canvas under the window (±margin, SPEC §4.1.3).
    public var pan: PixelPoint
    public var probe: PixelPoint
    /// Window side in device pixels (894 on the 15 Pro Max).
    public var windowSize: Int
    public var operatorRequest: OperatorRequest { get }
}

/// Runtime GPU limits (MEASURED from the device, or forced to Apple2 values by `blur-gpucheck --apple2-limits`).
public struct GPUFacts: Sendable, Codable, Hashable {
    public var deviceName: String
    public var familyName: String                  // "Apple9", "Apple7", "Apple2"
    public var maxThreadsPerThreadgroup: Int
    public var maxThreadgroupMemoryLength: Int
    public var supportsApple7: Bool                // SIMD-group reductions and scans allowed
    public var supports32BitFloatFiltering: Bool
    public var readWriteTextureTier: Int
    public var supportsStageBoundaryCounters: Bool
    public var isSimulator: Bool
    public var forcedApple2Limits: Bool
    /// The Simulator's Apple2 limits (SDK §15): 512 threads, 16 KB threadgroup memory, no Apple7 features.
    public static func apple2(deviceName: String) -> GPUFacts
}

public enum PassEncoderKind: String, Sendable, Codable, Hashable { case render, compute, blit, mps, coreImage }

/// What one GPU pass actually dispatched (COMPUTED geometry; limits read from the pipeline are MEASURED).
public struct PassDispatch: Sendable, Codable, Hashable {
    public var passIndex: Int
    public var name: String
    public var encoder: PassEncoderKind
    /// Metal function names used by this pass ("b2_f2_gauss_linear_fs").
    public var functionNames: [String]
    /// [x, y, z]; [0, 0, 0] for render, blit and MPS passes.
    public var threadsPerThreadgroup: [Int]
    public var threadgroups: [Int]
    public var staticThreadgroupMemoryBytes: Int
    public var dynamicThreadgroupMemoryBytes: Int
    /// `threadExecutionWidth` of the pipeline (SIMD width).
    public var threadExecutionWidth: Int
    /// `maxTotalThreadsPerThreadgroup` of the pipeline.
    public var pipelineMaxThreads: Int
    public var outputSize: ImageSize
    /// True when the output texture carries `.shaderWrite` (no lossless compression on Apple9, REFERENCE TT 111431).
    public var outputHasShaderWrite: Bool
    /// MODELED bytes read + written by this pass.
    public var modeledBytes: Double
}

public struct PassTiming: Sendable, Codable, Hashable {
    public var passIndex: Int
    public var passName: String
    public var medianMilliseconds: Double
    public var iqrMilliseconds: Double
    public var samples: Int
}

public enum TimingMethod: String, Sendable, Codable, Hashable {
    /// gpuEndTime − gpuStartTime of whole command buffers (one blur per command buffer).
    case commandBuffer
    /// Per-encoder timestamps where supportsCounterSampling(.atStageBoundary) (one encoder per pass).
    case stageBoundaryCounters
    /// One command buffer per pass (fallback for per-pass times without counters).
    case passIsolatedCommandBuffers
}

/// MEASURED on a named device; nil in the Simulator (its GPU times are meaningless, GPU §2.7 item 4).
public enum TimingStopReason: String, Sendable, Codable, Hashable {
    /// The requested number of samples was reached (15 by default).
    case samplesReached
    /// Summed GPU time reached TimingRequest.maxGPUSeconds (at least `minSamples` were taken).
    case gpuTimeBudget
}

public struct TimingSummary: Sendable, Codable, Hashable {
    public var method: TimingMethod
    public var warmups: Int
    public var samples: Int
    /// Median of whole-blur command-buffer times, one encoder per pass.
    public var medianMilliseconds: Double
    public var iqrMilliseconds: Double
    public var perPass: [PassTiming]
    /// Median with all passes fused into the fewest encoders; the difference is shown as MEASUREMENT OVERHEAD.
    public var fusedMedianMilliseconds: Double?
    /// True when A and B were timed in interleaved ABAB order (Compare's ΔGPU).
    public var interleaved: Bool
    public var thermalAtStart: ThermalLevel
    public var thermalAtEnd: ThermalLevel
    public var lowPowerMode: Bool
    /// Median of the colour pre/post passes and window copy, timed separately; `medianMilliseconds` covers the blur
    public var overheadMilliseconds: Double?
    public var stopReason: TimingStopReason
    public var thermalChanged: Bool { get }
}

/// COMPUTED from the operator for the resolved variant.
public struct KernelSummary: Sendable, Codable, Hashable {
    public var sigmaEff: Double?
    public var excessKurtosis: Double?
    public var fetchesPerPixel: Double
    public var tapsPerAxis: Int?
    public var passNames: [String]
    /// The exact 1-D weights and offsets uploaded to the GPU (Float of BlurCore's Double), when the variant uses tables.
    public var uploadedWeights: [Float]?
    public var uploadedOffsets: [Float]?
}

/// The bandwidth a cost model assumes, with its own honesty.
public struct BandwidthAssumption: Sendable, Codable, Hashable {
    public var gigabytesPerSecond: Double
    /// "51.2 GB/s (leak-derived)" or "copy bandwidth measured on this phone".
    public var label: String
    public var provenance: Provenance
    public var qualifiers: Qualifiers
    /// gpu-pipeline §2.5: third-party LPDDR5-6400 × 64-bit figure; UNVERIFIED.
    public static let a17ProLeak = BandwidthAssumption(gigabytesPerSecond: 51.2, label: "51.2 GB/s (leak-derived)",
                                                       provenance: .modeled, qualifiers: .weakSource)
}

/// MODELED; the assumption travels with it.
public struct CostSummary: Sendable, Codable, Hashable {
    public var bytesMoved: Double
    public var perPassBytes: [Double]
    public var bandwidth: BandwidthAssumption
    public var floorMilliseconds: Double
}

/// MEASURED: GPU output vs the BlurCore reference on a crop around the probe.
public struct ParitySummary: Sendable, Codable, Hashable {
    public var stats: DifferenceStats
    public var region: PixelRegion
    public var tolerance: ParityTolerance
    public var passed: Bool
}

/// LIVE: the probe's input and output read back from the GPU for this frame (linear light).
public struct ProbeReadout: Sendable, Codable, Hashable {
    public var probe: PixelPoint
    public var input: SIMD4<Double>
    public var output: SIMD4<Double>
    /// The probe's value after each pass (from the real intermediates), when read.
    public var perPass: [SIMD4<Double>]
}

/// MEASURED from GPU output (the fingerprint's ON THIS PHONE row, SPEC §7.1 item 10).
public struct ShapeMeasurement: Sendable, Codable, Hashable {
    public var sigmaPx: Double
    public var excessKurtosisAxis: Double
    public var excessKurtosis45: Double
    /// Edge-centre spread over 4 whole-pixel phases (shift-variance detector, CAL §3.3).
    public var shiftSpreadPx: Double
    public var minResponse: Double
    public var millisecondsPerMegapixel: Double?
}

/// REFERENCE ("it is the code"): which compiled source produced the Run (ARCHITECTURE §6.6).
public struct ShaderProvenance: Sendable, Codable, Hashable {
    /// SHA-256 of the concatenated shader source (B2Shared.h + all App/GPU/Shaders/*.metal; §6.6 rule).
    public var combinedSHA256: String
    /// The family file of the running variant ("F2Gaussian.metal") and its own SHA-256.
    public var fileName: String
    public var fileSHA256: String
    public var functionNames: [String]
    public var mathMode: String                    // "fast"
    public var languageVersion: String             // "4.1"
    public var traced: Bool
}

public enum DeviceProbeKind: String, Sendable, Codable, Hashable, CaseIterable {
    case limits, bilinearSubTexelBits, mipmapImpulse, copyBandwidthBlit, copyBandwidthCompute, compressionAB,
         fmaThroughput, counterSamplingPoints, tracedEqualsUntraced
}

/// One This-phone probe result (SPEC §4.7), cached with OS build and date.
public struct DeviceProbeResult: Sendable, Codable, Hashable {
    public var kind: DeviceProbeKind
    public var rows: [LabeledValue]
    /// Machine-readable numbers ("subTexelBits": 8, "gigabytesPerSecond": 31.2, "equal": 1).
    public var numbers: [String: Double]
    public var device: DeviceStamp
}

public struct Run: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let kind: RunKind
    /// Monotonic request generation; only the newest generation may publish (METRO §F.2 item 3).
    public let generation: UInt64
    public let slot: RunSlot
    public let configuration: RenderConfiguration
    public let resolvedVariant: VariantResolution
    public let quality: RenderQuality
    public let device: DeviceStamp
    public let gpu: GPUFacts?
    public let kernel: KernelSummary
    public let dispatch: [PassDispatch]
    public let timing: TimingSummary?
    public let cost: CostSummary?
    public let parity: ParitySummary?
    public let probe: ProbeReadout?
    public let shape: ShapeMeasurement?
    public let shader: ShaderProvenance?
    public let trace: TraceRecord?
    public let calibration: CalibrationResult?
    public let deviceProbe: DeviceProbeResult?
    public let createdAt: Date
    public let notes: [String]
}
```

##### `Sources/BlurCore/Core/Parity.swift`

```swift
public struct ParityTolerance: Sendable, Codable, Hashable {
    public var name: String
    /// Allowed fp16 ulps of the reference value.
    public var ulp16: Double
    /// Absolute allowance in linear units, multiplied by `scale`.
    public var absolute: Double
    /// Extra absolute allowance per pass that uses hardware bilinear filtering (8-bit sub-texel weights), × `scale`.
    public var perBilinearPass: Double
    /// Rank and selection filters: outputs must equal the reference bit for bit.
    public var bitExact: Bool
    /// Lessons and models: difference is shown, never pass/fail.
    public var reportOnly: Bool

    /// Integer-tap FIR with fp32 fma accumulation and fp16 storage (box, tent, Gaussian separable/2-D, binomial, USM).
    public static let exactF32 = ParityTolerance(name: "exactF32", ulp16: 2, absolute: 0x1p-20)
    /// Kernels that merge taps with hardware bilinear fetches (linear-sampled Gaussian, Kawase, dual Kawase, gathers).
    public static let bilinear = ParityTolerance(name: "bilinear", ulp16: 2, absolute: 0x1p-20, perBilinearPass: 0x1p-10)
    /// In-shader transcendentals under fast math (bilateral range weights, radial/spin trig, sRGB pre/post).
    public static let fastMath = ParityTolerance(name: "fastMath", ulp16: 2, absolute: 0x1p-11)
    /// Recursions and running sums in fp32 (IIR, exponential, stack blur, sliding-window box, PDE iterations).
    public static let recursiveF32 = ParityTolerance(name: "recursiveF32", ulp16: 2, absolute: 0x1p-12)
    /// fp32 FFT round-off (P ≤ 1024).
    public static let fft = ParityTolerance(name: "fft", ulp16: 2, absolute: 0x1p-13)
    /// Median, min/max morphology, Kuwahara sector choice, frosted-glass single realization.
    public static let rankExact = ParityTolerance(name: "rankExact", ulp16: 0, absolute: 0, bitExact: true)
    /// Models, fp16-accumulation lessons, rgba8Unorm intermediates, Apple twins: shown, not judged.
    public static let reportOnly = ParityTolerance(name: "reportOnly", ulp16: .infinity, absolute: .infinity, reportOnly: true)
    /// Plain fp32 summed-area tables: four corner reads, each rounded by two scans (CAT E11, GPU §3.4).
    public static func sat(cornerMagnitude: Double, boxArea: Double) -> ParityTolerance

    /// The sum of two tolerances (a bilinear kernel with in-shader transcendentals: `.bilinear.plus(.fastMath)`).
    public func plus(_ other: ParityTolerance) -> ParityTolerance

    /// True for classes whose allowance depends on the hardware sub-texel rule (in-app parity reports them as
    public var dependsOnSubTexelRule: Bool { get }

    /// The class actually applied for these settings (review fix E-18): with a colour or alpha pre-pass, a bit-exact
    public func adjusted(for settings: SilentSettings) -> ParityTolerance

    /// The allowance for one channel value.
    public func allowance(reference c: Double, scale: Double, bilinearPasses: Int) -> Double
}

/// Where values are compared: the domain the blur ran in. sRGB-encoded blurs are compared after encoding both outputs,
public enum ParityDomain: String, Sendable, Codable, Hashable { case linear, encoded }

/// The result of one parity evaluation.
public struct ParityEvaluation: Sendable, Codable, Hashable {
    public var stats: DifferenceStats
    /// max over channels of |gpu − cpu| − allowance (≤ 0 means pass).
    public var worstExcess: Double
    public var failingChannels: Int
    public var passed: Bool

    /// Per-pixel scale for the absolute terms: max(1, max channel magnitude of `input` over the (2r + 1)² square around
    public static func localScale(_ input: ImageBuffer, radius: Int) -> [Float]

    /// `localScale` (one value per pixel of the compared images) replaces `inputScale` when given.
    public static func evaluate(gpu rawGPU: ImageBuffer, cpu rawCPU: ImageBuffer, tolerance: ParityTolerance, inputScale: Double,
                                localScale: [Float]? = nil, bilinearPasses: Int, domain: ParityDomain = .linear) -> ParityEvaluation
}

/// One GPU↔CPU parity case, published next to its pipeline factory and run by blur-gpucheck (ARCHITECTURE §3.2).
public struct ParityCase: Sendable, Hashable {
    public var name: String
    public var configuration: RenderConfiguration
    public var tolerance: ParityTolerance
    /// Passes that sample with hardware bilinear filtering (for the tolerance's per-pass term).
    public var bilinearPasses: Int
    /// Assert traced == untraced bit for bit and trace final sum == output at each probe (all Tier 1 kernels).
    public var checkTraced: Bool
    public var probes: [PixelPoint]
    /// Why this case exists / which SPEC fixture it reproduces ("SPEC §5.3 A").
    public var note: String
}
```

##### `Sources/BlurCore/Core/Content.swift`

```swift
public enum SeriesStyle: String, Sendable, Codable, Hashable { case solid, dashed, dotted, dashDot, stems, points, quiet }

public enum SeriesRole: String, Sendable, Codable, Hashable {
    /// Primary data (discrete taps, DFT of the taps).
    case primary
    /// Quiet reference (continuous kernel or response).
    case reference
    /// Depth trace: the effective kernel after all passes (wave secondary ink).
    case depth
    /// Compare series B, C, D (dashed, dotted, dash-dot).
    case comparisonB, comparisonC, comparisonD
    /// Measured points (this phone), filled; `reference` dashed for the Mac.
    case measured
}

public struct PlotAxis: Sendable, Codable, Hashable {
    public var label: String
    public var unit: String?
    /// Spoken and printed as "normalized" when true (Metro contract A.21).
    public var normalized: Bool
    public var range: ClosedRange<Double>?
    public var logarithmic: Bool
}

public struct PlotSeries: Sendable, Codable, Hashable {
    public var name: String
    public var xs: [Double]
    public var ys: [Double]
    public var style: SeriesStyle
    public var role: SeriesRole
    public var provenance: Provenance
}

public enum MarkerKind: String, Sendable, Codable, Hashable {
    /// −3 dB tick (carrier ink).
    case minus3dB
    case halfAmplitude, firstZero, probe, supportBracket
    /// The SwiftUI regime switch: hollow while INFERRED, filled when MEASURED.
    case regimeSwitch
    case custom
}

public struct PlotMarker: Sendable, Codable, Hashable {
    public var x: Double
    public var label: String
    public var kind: MarkerKind
    public var provenance: Provenance?
}

public struct PlotSpec: Sendable, Codable, Hashable {
    public var xAxis: PlotAxis
    public var yAxis: PlotAxis
    public var series: [PlotSeries]
    public var markers: [PlotMarker]
    /// Draw y = 0 and shade values below it (signed responses: negative lobes shaded AND dashed, SPEC §4.1.3).
    public var showsZeroLine: Bool
    /// One-sentence summary for VoiceOver and the AXChartDescriptor.
    public var accessibilitySummary: String
}

public struct HeatmapSpec: Sendable, Codable, Hashable {
    public var width: Int
    public var height: Int
    public var values: [Double]
    public var signed: Bool
    public var centre: PixelPoint?
    public var caption: String
    public var provenance: Provenance
}

public enum TexelChannel: String, Sendable, Codable, Hashable { case luma, red, green, blue, alpha }

/// A copy of texel values around the probe (never drawn on the specimen itself).
public struct TexelGridSpec: Sendable, Codable, Hashable {
    public var size: Int                 // 9 or 17
    public var origin: PixelPoint        // top-left texel in window pixels
    public var channel: TexelChannel
    public var values: [Double]          // size × size, linear light
    public var weights: [Double]?        // per-texel weights of the current pass (amber bars)
    public var highlighted: [PixelPoint] // probe, fetch positions
    public var provenance: Provenance
}

/// Dispatch geometry drawn over a COPY of the output (floor 6 Silicon).
public struct DispatchOverlaySpec: Sendable, Codable, Hashable {
    public var dispatch: PassDispatch
    public var apronTexels: Int
    public var probeThreadgroup: [Int]
    public var probeThreadInGroup: [Int]
    public var probeSIMDGroup: Int
    public var probeLane: Int
}

/// Event-tile row of passes (Algorithm floor); tapping a tile shows that pass's intermediate in the periscope.
public struct PassTilesSpec: Sendable, Codable, Hashable {
    public var passes: [PassDescriptor]
    /// MEASURED per-pass ms when a settled timing Run exists.
    public var timings: [PassTiming]
    public var selected: Int?
}

/// 7 × 7 grid of local PSFs drawn at their positions (space-variant blurs: a lens spot diagram).
public struct PSFFieldSpec: Sendable, Codable, Hashable {
    public var gridSize: Int
    public var points: [PixelPoint]
    public var kernels: [Kernel2D]
}

/// Floor 1 bars: the typed value per tool for the current blur, home tool first.
public struct ToolBarsSpec: Sendable, Codable, Hashable {
    public var rows: [LabeledValue]
    public var homeToolID: String
    /// `You typed ⇄ What you get` (SPEC §5.1 floor 1).
    public var reverseMode: Bool
}

public struct CodeBlock: Sendable, Codable, Hashable {
    public var language: String          // "metal", "swift", "css"
    public var text: String
    public var highlightedLines: [Int]
    /// 1-based line → one-line explanation ("cooperative load of the apron").
    public var annotations: [Int: String]
    public var sha256: String?
}

public struct TableBlock: Sendable, Codable, Hashable {
    public var columns: [String]
    public var rows: [[String]]
    public var caption: String?
    public var provenance: Provenance?
}

public enum FigureSpec: Sendable, Codable, Hashable {
    case plot(PlotSpec)
    case heatmap(HeatmapSpec)
    case texelGrid(TexelGridSpec)
    case dispatchOverlay(DispatchOverlaySpec)
    case passTiles(PassTilesSpec)
    case psfField(PSFFieldSpec)
    case toolBars(ToolBarsSpec)
    case code(CodeBlock)
    /// Two figures side by side (IN | OUT texel grids on floor 7).
    indirect case pair(FigureSpec, FigureSpec)
}

public indirect enum ContentBlock: Sendable, Codable, Hashable {
    case paragraph(String)
    /// An equation in Unicode (callout mono, instrument cyan, units next to it).
    case equation(String)
    case values([LabeledValue])
    case table(TableBlock)
    case code(CodeBlock)
    case figure(FigureSpec)
    /// A one-line engraved note with its badge ("IN THIS APP …", "SOURCES DISAGREE").
    case note(String, Provenance?)
    case chips([String])
    case sources([SourceRef])
    case disclosure(title: String, blocks: [ContentBlock])
}

/// A tab inside a floor page (floor 6: Shader · Silicon).
public struct FloorTab: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var dominantBadges: [Provenance]
    public var figure: FigureSpec?
    public var numbers: [LabeledValue]
    public var details: [ContentBlock]
}

/// What an operator contributes to one floor. The page builder (CONTENT-LAYERS) merges it with generic facts and live
public struct FloorFacts: Sendable, Codable, Hashable {
    public var numbers: [LabeledValue]
    public var figure: FigureSpec?
    public var governingRule: String?
    public var details: [ContentBlock]
    public var tabs: [FloorTab]?
    /// Engraved reason when the floor has nothing honest to show ("N/A · NONLINEAR").
    public var emptyReason: String?
    public static let empty = FloorFacts()
}

/// One floor page, fully resolved, ready to render (SPEC §5.0 rules).
public struct FloorPage: Sendable, Codable, Hashable, Identifiable {
    public var id: Floor { get }
    public var floor: Floor
    public var eyebrow: String              // "FLOOR 4 · KERNEL"
    public var question: String
    /// The catalog signature line shown in the page header (SPEC §7.3).
    public var signature: String
    public var dominantBadges: [Provenance]
    public var governingRule: String?
    public var figure: FigureSpec?
    /// At most six (SPEC §5.0 rule 2); the builder enforces it and tests check it.
    public var numbers: [LabeledValue]
    /// Everything else, inside `All … details` (the only element that grows).
    public var details: [ContentBlock]
    public var tabs: [FloorTab]?
    /// The closing `IN THIS APP` line: what on this page is LIVE / MEASURED / COMPUTED / MODELED / REFERENCE / INFERRED.
    public var inThisApp: String
    public var emptyState: String?
}

/// A rail chip value (SPEC §4.1.4): text ≤ 6 characters, badge shown as a glyph only.
public struct RailChip: Sendable, Codable, Hashable, Identifiable {
    public var id: Floor { get }
    public var floor: Floor
    public var value: BadgedValue
    /// Compare mode only: the floor comparison (first ≠ is `.partsWays`).
    public var comparison: FloorComparison?
}

/// One flanking pill's content (SPEC §4.1.3 "Pills"). Outline and title stay static; only the interior changes.
public struct PillPlot: Sendable, Codable, Hashable {
    /// "KERNEL", "FREQ", "LOCAL @ PROBE", "T(ν, A 0.20)".
    public var title: String
    /// nil → `emptyText` is engraved instead ("N/A · RANK", "INFERRED — NOT EXPOSED").
    public var plot: PlotSpec?
    public var emptyText: String?
    public var badge: BadgedValue?
}

public struct PillContent: Sendable, Codable, Hashable {
    /// Wave family (left): taps running downward from −extent to +extent.
    public var kernel: PillPlot
    /// Spectrum family (right): signed H from DC (bottom) to Nyquist (top).
    public var freq: PillPlot
}

/// The Field guide page of one entry (SPEC §4.7 Guide tab).
public struct FieldGuidePage: Sendable, Codable, Hashable {
    public var blur: BlurID
    public var title: String
    public var blocks: [ContentBlock]
}
```

##### `Sources/BlurCore/Core/Trace.swift`

```swift
public enum TraceSource: String, Sendable, Codable, Hashable {
    /// Recorded by the GPU's TRACE_PROBE specialization for the frame on screen: LIVE.
    case gpuRecord
    /// Recomputed by BlurCore on the CPU: COMPUTED.
    case cpuReconstruction
    public var provenance: Provenance { get }
}

/// One texel blended by a fetch, with its bilinear weight.
public struct TexelContribution: Sendable, Codable, Hashable {
    public var texel: PixelPoint
    public var fraction: Double
}

/// One tap (fetch, sample, compare-exchange, iteration) of one pass for the probe pixel.
public struct TraceTap: Sendable, Codable, Hashable, Identifiable {
    public var id: Int
    /// Sample position in source texel coordinates (texel centres at i + 0.5), in the pass's input texture.
    public var position: SIMD2<Double>
    /// Offset from the output pixel's centre, in input texels.
    public var offset: SIMD2<Double>
    /// 1 texel for integer fetches, up to 4 for bilinear fetches.
    public var texels: [TexelContribution]
    /// Bilinear fraction as requested (COMPUTED).
    public var requestedFraction: SIMD2<Double>?
    /// Bilinear fraction as the hardware quantizes it (MODELED from the measured sub-texel bits).
    public var quantizedFraction: SIMD2<Double>?
    public var weight: Double
    public var fetched: SIMD4<Double>
    public var contribution: SIMD4<Double>
    public var runningSum: SIMD4<Double>
    /// Dropped by `renormalise` at the border (recorded with weight 0).
    public var dropped: Bool
    /// Class-specific extras: "spatialWeight", "rangeWeight", "sectorVariance", "rank", "iteration" …
    public var extras: [String: Double]
}

public struct TracePass: Sendable, Codable, Hashable, Identifiable {
    public var id: Int
    public var descriptor: PassDescriptor
    public var source: TraceSource
    /// The output pixel this pass computed for the probe (differs from the probe on pyramid levels).
    public var pixel: PixelPoint
    public var taps: [TraceTap]
    /// Taps beyond the record capacity, summarised in one row.
    public var truncatedTapCount: Int
    public var outputAtProbe: SIMD4<Double>
    /// 9 × 9 neighbourhoods before and after this pass, read from the real intermediate textures (gpuRecord) or computed.
    public var neighbourhoodIn: [SIMD4<Float>]?
    public var neighbourhoodOut: [SIMD4<Float>]?
}

public struct TraceRecord: Sendable, Codable, Hashable {
    public var blur: BlurID
    public var variant: VariantID
    public var parameters: ParameterValues
    public var settings: SilentSettings
    public var probe: PixelPoint
    /// The probe's input value (after the colour pre-pass), linear.
    public var input: SIMD4<Double>
    public var passes: [TracePass]
    /// The GPU's output at the probe for the frame on screen (LIVE); nil for CPU-only traces.
    public var gpuOutput: SIMD4<Double>?
    /// BlurCore's reference value (COMPUTED, Double).
    public var cpuReference: SIMD4<Double>
    public var differenceULP16: Double?
    /// Result of the traced-vs-untraced bit-exactness check for this frame, when it ran.
    public var tracedEqualsUntraced: Bool?
}

/// One unit of `Next …` inside a step (a fetch, a tap, an iteration, a compare-exchange).
public struct TraceSubStep: Sendable, Codable, Hashable, Identifiable {
    public var id: Int
    /// Instrument-amber line: what this tap did ("fetch 7 of 13: w 0.07818 · v 0.000").
    public var completed: String
    /// Action-cyan line: what the next tap will do ("fetch 8 at +7.38 px").
    public var next: String
    /// The running partial result after this sub-step (Σ row), when it applies.
    public var runningSum: SIMD4<Double>?
    public var highlighted: [PixelPoint]
    /// Index into the current pass's `taps`, when the sub-step is a tap.
    public var tapIndex: Int?
    /// Spoken after the sub-step, fixed order (SPEC §6.6).
    public var announcement: String
}

/// One step of the walk (SPEC §6.3). Generated by CONTENT-LAYERS' TraceScripter from the pass graph and the record.
public struct TraceStep: Sendable, Codable, Hashable, Identifiable {
    public var id: Int
    public var floor: Floor
    public var completed: String
    public var next: String
    /// "Next floor", "Next pass", "Next fetch", "Next iteration", "Next tap", "Finish".
    public var primaryLabel: String
    public var subSteps: [TraceSubStep]
    public var passIndex: Int?
    /// The floor panel's content for this step only.
    public var panel: FloorFacts
    /// Branches, not forks: "if sRGB-encoded: 115/255" (COMPUTED).
    public var branchValues: [LabeledValue]
    /// "Step 10 / 15 · fragment (446, 300) · pass 1 of 2 · horizontal".
    public var phaseLine: String
    /// The one-sentence lesson on the last step.
    public var closingLesson: String?
    public var announcement: String
}
```

##### `Sources/BlurCore/Core/Calibration.swift`

```swift
public enum CalibrationSubject: String, Sendable, Codable, Hashable, CaseIterable {
    case swiftUIBlur, swiftUIShadow, caLayerShadow, cgContextShadow,
         ciGaussianBlur, ciBoxBlur, ciDiscBlur, ciBokehBlur, ciMotionBlur, ciZoomBlur, ciMaskedVariableBlur,
         mpsGaussianBlur, mpsBox, mpsTent, vImageBox, vImageTent
    /// Calibrate's API menu title ("SwiftUI .blur(radius:)").
    public var title: String { get }
    /// Subjects measured through SwiftUI/Core Animation on the main actor (ImageRenderer, render(in:), CG).
    public var isMainActorRendered: Bool { get }
}

public enum CalibrationPath: String, Sendable, Codable, Hashable, CaseIterable {
    /// ImageRenderer.cgImage — default for SwiftUI subjects (CAL §5.1 item 7).
    case imageRendererCGImage
    /// ImageRenderer.render(rasterizationScale:renderer:) — a different blur (σ ≈ 0.98·r on the Mac).
    case imageRendererRenderInto
    /// UIView.drawHierarchy(afterScreenUpdates: true) — EXPERIMENTAL; results labelled as such.
    case drawHierarchyOnScreen
    case coreImageContext, metalPerformanceShaders, vImage, coreGraphics, coreAnimationRenderInContext
}

public enum CalibrationColourMode: String, Sendable, Codable, Hashable, CaseIterable { case nonLinear, linear, extendedLinear }

public struct CalibrationRequest: Sendable, Codable, Hashable {
    public var subject: CalibrationSubject
    public var path: CalibrationPath
    /// The API's own parameter in its own unit (pt for SwiftUI and CALayer, px for Core Image/MPS/vImage).
    public var parameter: Double
    public var displayScale: Double
    public var colourMode: CalibrationColourMode
    /// Whole-device-pixel edge phases; > 1 detects resampling (CAL §3.3).
    public var phases: Int
    public var opaque: Bool?
}

/// Edge-spread samples read back from one rendered edge, in the blur's working space.
public struct EdgeSamples: Sendable, Codable, Hashable {
    /// One value per device pixel along the edge normal (normalised so the dark plateau is 0 and the bright one 1).
    public var esf: [Double]
    /// Position of the unblurred edge in device pixels from esf[0].
    public var edgePosition: Double
    public var phase: Int
    /// sRGB-encoded value at the edge centre (0.5 gamma-space blend, ≈ 0.735 linear-light blend).
    public var encodedMidpoint: Double?
    /// The same edge at 45° (separable vs isotropic), when rendered.
    public var esf45: [Double]?
}

public enum PSFModel: String, Sendable, Codable, Hashable, CaseIterable {
    case gaussian
    /// Gaussian hard-truncated at ±2.3σ (SDK §4's reading of SwiftUI's large-radius kernel).
    case truncatedGaussian
    /// Three equal boxes (CAL §5.1's reading).
    case boxCubed
}

public struct ModelFit: Sendable, Codable, Hashable {
    public var model: PSFModel
    public var sigmaPx: Double
    /// RMS residual in % of the step.
    public var rmsResidualPercent: Double
}

/// The fit of one measured edge set (CAL §3.3 estimators, ported from Tools/calibrate/MeasurePSF.swift).
public struct PSFFit: Sendable, Codable, Hashable {
    /// Moment σ of the LSF in device pixels.
    public var sigmaPx: Double
    /// σ / (parameter · displayScale): the law (SwiftUI ≈ 1.0 small, ≈ 0.90 large on macOS 27.2).
    public var sigmaPerParameterPixel: Double
    /// Least-squares erf σ as a sampled-equivalent σ.
    public var lsqSigmaPx: Double
    public var excessKurtosis: Double
    public var excessKurtosis45: Double?
    /// Visible extent at 1/255 (device px).
    public var extentPx: Double
    /// Support at 10⁻³ of the LSF peak (device px).
    public var supportPx: Double
    /// Spread of the edge centre over phases (the resampling detector; 0 = shift-invariant).
    public var centreSpreadPx: Double
    public var sigmaSpreadPercent: Double
    public var encodedMidpoint: Double?
    /// "gaussian", "box³-like", "tent-like", "box", "disc": an interpretation, labelled INFERRED on screen.
    public var shapeName: String
    /// Model competition (SPEC §13.3), sorted by residual (lowest first; the app marks it ✓).
    public var models: [ModelFit]
    /// The fitted line-spread function, for plotting beside the theory.
    public var lsf: [Double]
}

public struct CalibrationResult: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var request: CalibrationRequest
    public var fit: PSFFit
    public var device: DeviceStamp
    public var durationMilliseconds: Double
}

/// A parameter → σ law fitted from a sweep (SwiftUI `.blur`: σ ≈ r·s below the switch, ≈ 0.90·r·s above).
public struct CalibrationLaw: Sendable, Codable, Hashable {
    public var subject: CalibrationSubject
    /// σ / (parameter · scale) below the regime switch, if one exists.
    public var smallRatio: Double?
    /// σ / (parameter · scale) above the regime switch.
    public var largeRatio: Double
    /// Parameter (API unit) where the regime switches, or nil.
    public var switchParameter: Double?
    public var points: [CalibrationPoint]
    public var device: DeviceStamp
    /// σ in device pixels for a parameter, by this law.
    public func sigmaPx(parameter: Double, displayScale: Double) -> Double
}

public struct CalibrationPoint: Sendable, Codable, Hashable {
    public var parameter: Double
    public var sigmaPx: Double
    public var centreSpreadPx: Double
}

/// Pure fitting math (CAL §3.3), implemented by CALIBRATION in Sources/BlurCore/Calibration/, unit-tested on the Mac
public protocol PSFFitting: Sendable {
    func fit(_ samples: [EdgeSamples], request: CalibrationRequest) -> PSFFit
    /// A law from a sweep of results for one subject (nil when there are fewer than 3 points).
    func law(_ sweep: [CalibrationResult]) -> CalibrationLaw?
}
```

##### `Sources/BlurCore/Math/KernelMath.swift`

```swift
/// One side of a symmetric linear-sampled table (Rákos 2010): index 0 is the centre tap, then one entry per merged pair.
public struct LinearSampledTable: Sendable, Codable, Hashable {
    public var offsets: [Double]
    public var weights: [Double]
    /// Texture fetches per output pixel per pass: the centre plus two per entry.
    public var fetchesPerPass: Int { get }
}

public enum KernelMath {
    /// Radius of a truncated Gaussian: max(3, ⌈k·σ⌉) taps on each side (k = truncation, default 3).
    public static func gaussianRadius(sigma: Double, truncation k: Double = 3) -> Int

    /// Sampled Gaussian exp(−n²/2σ²), cut at the radius and renormalised to sum 1 (SPEC §5.3 A, `Sampled`).
    public static func gaussianSampled(sigma: Double, truncation k: Double = 3) -> Kernel1D

    /// Pixel-integrated Gaussian Φ((n+½)/σ) − Φ((n−½)/σ), cut and renormalised (`Integrated`).
    public static func gaussianIntegrated(sigma: Double, truncation k: Double = 3) -> Kernel1D

    /// Lindeberg's discrete Gaussian e^(−t)·I_n(t) with t = σ² (its variance is exactly t before the cut),
    public static func gaussianLindeberg(sigma: Double, truncation k: Double = 3) -> Kernel1D

    /// Box of 2r + 1 equal taps.
    public static func box(radius r: Int) -> Kernel1D

    /// Tent (triangle) of half-width r + 1: weights ∝ (r + 1 − |n|), |n| ≤ r; σ² = r(r + 2)/6 (SPEC §8.1).
    public static func tent(radius r: Int) -> Kernel1D

    /// Binomial (Pascal) kernel of order n (n + 1 taps, σ² = n/4); n must be even for a centred kernel.
    public static func binomial(order n: Int) -> Kernel1D

    /// Discrete convolution of two integer-offset kernels.
    public static func convolve(_ a: Kernel1D, _ b: Kernel1D) -> Kernel1D

    /// Rákos pairing of a symmetric, integer-offset kernel: taps (1,2), (3,4), … merge into one bilinear fetch each at
    public static func linearSampledTable(_ k: Kernel1D) -> LinearSampledTable

    /// Signed response of a 1-D kernel, phase-centred on its centroid: Re Σ wᵢ e^(−2πiν(xᵢ − x̄)).
    public static func response(_ k: Kernel1D, frequencies: [Double]) -> [Double]

    /// Signed response of a 2-D kernel along an axis (degrees), phase-centred on the centroid.
    public static func response(_ k: Kernel2D, axisDegrees: Double, frequencies: [Double]) -> [Double]

    /// "MASS CUT" on the Kernel floor: the continuous Gaussian's mass outside the window ±r, erfc(r / (σ√2))
    public static func gaussianMassBeyond(radius r: Int, sigma: Double) -> Double

    /// Continuous Gaussian response e^(−2π²σ²ν²).
    public static func gaussianResponse(sigma: Double, frequency nu: Double) -> Double

    public static func normalCDF(_ x: Double) -> Double

    /// e^(−t)·I_n(t) for n = 0…upTo (Miller's backward recurrence, normalised by I₀ + 2ΣIₙ = e^t).
}
```

##### `Sources/BlurCore/Interaction/GestureArbiter.swift`

```swift
/// One active touch, in points of the window's coordinate space (origin top-left).
public struct TouchPoint: Sendable, Hashable {
    public var id: Int
    public var location: SIMD2<Double>
}

public enum TouchPhase: String, Sendable, Hashable { case began, moved, ended, cancelled }

public struct TouchEvent: Sendable, Hashable {
    public var phase: TouchPhase
    /// The touches this event is about (began: the new ones; moved: all moving; ended/cancelled: the lifted ones).
    public var touches: [TouchPoint]
    /// Seconds (CACurrentMediaTime or any monotonic clock).
    public var time: Double
}

/// A draggable handle's hit target (44-pt square → 22-pt radius).
public struct HandleTarget: Sendable, Hashable {
    public var id: String
    public var centre: SIMD2<Double>
    public var hitRadius: Double
}

public enum GestureIntent: Sendable, Hashable {
    case placeProbe(SIMD2<Double>)
    case handleBegan(String), handleMoved(String, SIMD2<Double>), handleEnded(String)
    case panBegan, panMoved(delta: SIMD2<Double>), panEnded
    case zoomBegan(centre: SIMD2<Double>), zoomChanged(scale: Double, centre: SIMD2<Double>), zoomEnded
    case loupeBegan(SIMD2<Double>), loupeMoved(SIMD2<Double>), loupeEnded(placeProbeAt: SIMD2<Double>?)
    case cancelled
}

public struct SpecimenGestureArbiter: Sendable {
    public enum State: Sendable, Hashable {
        case idle
        case pending(touch: Int, start: SIMD2<Double>, startTime: Double, last: SIMD2<Double>)
        case handle(touch: Int, id: String)
        case pan(touch: Int, last: SIMD2<Double>)
        case loupe(touch: Int, last: SIMD2<Double>)
        case pinch(a: Int, b: Int, startDistance: Double)
        /// After a pinch: ignore the remaining finger until every touch has lifted.
        case draining
    }

    public let longPressSeconds: Double
    public let slopPoints: Double
    /// The window's size in points; a loupe lifted outside it is cancelled.
    public var bounds: SIMD2<Double>
    public private(set) var state: State = .idle

    public mutating func reset()

    public mutating func handle(_ event: TouchEvent, handles: [HandleTarget]) -> [GestureIntent]

    /// Called by a timer while one touch is down and still, so the long press fires without movement.
    public mutating func tick(time: Double) -> [GestureIntent]

}
```

##### `Sources/BlurCore/Interaction/CrownDetentTracker.swift`

```swift
/// Relative angular detents for a touch crown. Clockwise screen angles are positive.
public struct CrownDetentTracker: Sendable {
    public let detentDegrees: Double
    public let hysteresisDegrees: Double
    public private(set) var residualDegrees: Double = 0
    public private(set) var lastDirection: Int = 0

    /// The first touch never changes the value (Metro §10).
    public mutating func begin(angleDegrees: Double)

    public mutating func reset()

    /// Accumulates relative motion, preserves fractional travel, and damps direction reversals.
    public mutating func update(angleDegrees: Double) -> Int

}

/// At most `maxEventsPerSecond` accepted detents (crowns: 20 per second, Metro §10).
public struct DetentRateLimiter: Sendable {
    public let minimumInterval: Double
    public mutating func admit(at time: Double) -> Bool
    public mutating func reset()
}
```

##### `Sources/BlurCore/Interaction/Schedulers.swift`

```swift
public enum RenderAction: Sendable, Hashable {
    /// Render the newest requested configuration now.
    case render(quality: RenderQuality, generation: UInt64)
    /// 300 ms after the last change, at full resolution: budgeted timing (3 warm-ups, ≤ 15 samples or 1 s of GPU time),
    case startTiming(generation: UInt64)
    /// A change or touch arrived while timing/parity ran: cancel them between command buffers (review fix E-7).
    case cancelMeasurements
}

public struct RenderScheduler: Sendable {
    public let settleSeconds: Double
    public private(set) var currentGeneration: UInt64 = 0
    public private(set) var lastAcknowledged: UInt64 = 0

    /// Every accepted change renders at once: at `preview` quality (`BlurOperator.previewScale`: half or quarter) while
    public mutating func requestChanged(at time: Double, preview: RenderQuality?, interacting: Bool) -> [RenderAction]

    /// A touch began anywhere (crown, handle, specimen): measurements in flight stop.
    public mutating func touchBegan() -> [RenderAction]

    /// A crown, handle or pan was released.
    public mutating func interactionEnded(at time: Double)

    /// After `settleSeconds` without a change and without interaction: re-render at full resolution if the last render
    public mutating func tick(at time: Double) -> [RenderAction]

    /// A Run for `generation` completed. Returns false (drop it) when an equal-or-newer generation has already been
    public mutating func acknowledge(_ generation: UInt64) -> Bool
    public func isStale(_ generation: UInt64) -> Bool
    /// True while the requested state differs from the acknowledged one (status row: RENDERING…).
    public var isRendering: Bool { get }
}

/// Automatic SwiftUI calibration may run only when ≥ 10 s since launch, ≥ 3 s since the last touch, no crown or handle
public struct CalibrationIdleScheduler: Sendable {
    public let launchTime: Double
    public let minimumSinceLaunch: Double
    public let minimumIdle: Double
    public private(set) var lastTouch: Double
    public private(set) var controlActive = false

    public mutating func noteTouch(at time: Double)
    public mutating func setControlActive(_ active: Bool)
    public func mayRun(at time: Double, thermal: ThermalLevel) -> Bool
}
```

##### `Sources/BlurGPU/Core/GPUTypes.swift`

```swift
/// A typed function-constant value at a fixed index (indices: B2Shared.h and ARCHITECTURE §6.2).
public enum FunctionConstantValue: Sendable, Hashable {
    case bool(Bool), uint(UInt32), int(Int32), float(Float)
}

public struct FunctionConstant: Sendable, Hashable {
    public var index: Int
    public var value: FunctionConstantValue
}

/// Function-constant values for one specialization. Shared indices 0–3 are fixed in B2Shared.h; each family file owns
public struct FunctionConstants: Sendable, Hashable {
    public var traceProbe: Bool          // B2_TRACE_PROBE, index 0
    public var halfAccumulate: Bool      // B2_HALF_ACCUM, index 1
    public var edgeMode: EdgeMode        // B2_EDGE_MODE, index 2
    public var direction: UInt32         // B2_DIRECTION, index 3 (0 horizontal, 1 vertical, 2+ family-defined)
    public var family: [FunctionConstant]
    public var cacheKey: String { get }
    /// The Metal values object (indices 0–3 always set, so every shared declaration is defined).
    public func metalValues() -> MTLFunctionConstantValues
}

public enum TextureFormat: String, Sendable, Codable, Hashable {
    case rgba16Float, rgba8Unorm, r16Float, r32Float, rg16Float, rg32Float, rgba32Float
    public var metal: MTLPixelFormat { get }
    public var bytesPerPixel: Int { get }
    /// 32-bit float formats are never sampled with a linear filter (ARCHITECTURE §4.4 rule 4).
    public var filterable: Bool { get }
}

public struct TextureRole: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public static let read = TextureRole(rawValue: 1 << 0)
    /// Only for compute outputs: removes lossless compression on Apple9 (REFERENCE, Tech Talk 111431).
    public static let computeWrite = TextureRole(rawValue: 1 << 1)
    public static let renderTarget = TextureRole(rawValue: 1 << 2)
}

public struct TextureSpec: Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var format: TextureFormat
    public var roles: TextureRole
    public var mipmapped: Bool
    /// `.shared` storage; default `.private` (readback always goes through a blit, ARCHITECTURE §4.1).
    public var shared: Bool
}

public struct TraceRequest: Sendable, Hashable {
    /// The probe in window pixels.
    public var probe: PixelPoint
    /// Capacity per pass (taps + the final flags = 2 record); extra taps increment the header's overflow count.
    public var maxTapsPerPass: Int
    /// Capacity sized from the plan (`PassPlan.traceCapacity`: the largest traced tapsPerPixel + 1), so a correct
    public static func sized(probe: PixelPoint, plan: PassPlan) -> TraceRequest
}

/// What the GPU reports when a command buffer finishes. Sendable: it is all a completion handler may capture.
public struct GPUCompletion: Sendable, Hashable {
    public var gpuStartTime: Double
    public var gpuEndTime: Double
    public var error: String?
    public var milliseconds: Double { get }
}

/// Auxiliary textures some blurs need (depth, velocity, guide, mask, sub-frames). Window-sized. Main actor only.
public struct GPUAuxiliaryTextures {
    public var depth: (any MTLTexture)?
    public var velocity: (any MTLTexture)?
    public var guide: (any MTLTexture)?
    public var mask: (any MTLTexture)?
    public var subFrames: [any MTLTexture]
    public var noiseSeed: UInt32
}

/// Inputs to one blur encode (after the colour pre-pass). Main actor only.
public struct GPUBlurInputs {
    /// N × N rgba16Float, linear (or encoded, per the pre-pass), premultiplied (or straight).
    public var source: any MTLTexture
    /// Same size and format; render target or compute-writable as the pipeline declares.
    public var destination: any MTLTexture
    public var request: OperatorRequest
    public var auxiliary: GPUAuxiliaryTextures
    public var quality: RenderQuality
}

/// What an encode produced. Intermediates are kept so the Algorithm floor and Trace can show each pass. Main actor only.
public struct EncodedBlur {
    public var dispatch: [PassDispatch]
    /// One texture per pass output, in order; the last is the destination. Owned by the context's pool until recycled.
    public var intermediates: [any MTLTexture]
    /// Present when a TraceRequest was given: one header + taps block per traced pass (layout: TraceLayout).
    public var traceBuffer: (any MTLBuffer)?
    public var tracedPassIndices: [Int]
    /// The tables uploaded for this encode. For merged-tap variants these are pair weights and offsets, not the stems
    public var uploadedWeights: [Float]?
    public var uploadedOffsets: [Float]?
    /// The trace capacity per pass used for `traceBuffer` (TraceLayout.decode needs it).
    public var traceCapacity: Int
    /// Pool textures this encode allocated (colour pre/post intermediates). The caller hands the EncodedBlur back with
    public var transientTextures: [(texture: any MTLTexture, spec: TextureSpec)]
}

/// A readback encoded into a render's own recorder (review fix E-26): decode after the recorder's completions.
public struct PendingReadback {
    public let buffer: any MTLBuffer
    public let region: PixelRegion
    public let format: MTLPixelFormat
    public func decode() -> [SIMD4<Float>]
}

public enum GPUError: Error, Sendable, Equatable {
    case noDevice
    case noCommandQueue
    case missingFunction(String)
    case textureAllocationFailed(String)
    case bufferAllocationFailed
    case encoderUnavailable(String)
    case commandBufferFailed(String)
    case readbackFailed
    case unsupported(String)
    case budgetExceeded(String)
    /// `encode` found no prepared pipeline state for this key: it never compiles (review fix E-3). The coordinator keeps
    case notPrepared(String)
}
```

##### `AppContract/Engine/EngineTypes.swift`

```swift
/// Root NavigationStack pushes (SPEC §3).
public enum Route: Hashable, Sendable {
    case layers(Floor)
    case trace
}
/// Pushes inside the Catalog sheet's own NavigationStack (Tier 3 atlas pages are never on the Bench).
public enum CatalogRoute: Hashable, Sendable { case atlasPage(BlurID) }
/// Pushes inside the Field guide sheet's own NavigationStack (Calibrate from This phone is a push, not a second sheet).
public enum FieldGuideRoute: Hashable, Sendable { case calibrate(CalibrationSubject), honestyLegend(Provenance?), lensNote }

public enum CatalogTab: String, Sendable, Hashable, CaseIterable { case blurs, fingerprints, divergence, lessons }
public enum FieldGuideTab: String, Sendable, Hashable, CaseIterable { case guide, thisPhone, runs, settings }

/// Every sheet comes from ONE `.sheet(item:)` driven by this enum (METRO §F.5 item 3). Sheets never stack.
public enum SheetDestination: Identifiable, Hashable, Sendable {
    case catalog(CatalogTab)
    case fingerprint(BlurID)
    case fieldGuide(FieldGuideTab, BlurID?)
    case calibrate(CalibrationSubject)
    public var id: String { get }
}

/// Compare holds A (the Bench configuration) and B (and C, D for Line-up) over one specimen and one probe (SPEC §8.2).
public struct CompareState: Sendable, Codable, Hashable {
    public var b: RenderConfiguration
    /// C and D for Line-up (empty otherwise).
    public var extra: [RenderConfiguration]
    public var axis: CompareAxis
    public var match: MatchRule
    public var view: CompareView
    /// Divider position 0…1 (B left of it, A right).
    public var split: Double
    /// Crowns drive B while true (status row: DRIVING B).
    public var drivingB: Bool
}

/// One legal B choice for the current axis (the B menu lists only these).
public struct CompareChoice: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var configuration: RenderConfiguration
    public var disabledReason: String?
}

/// Presentation-only state of the image window (never changes the blur).
public struct WindowViewState: Sendable, Codable, Hashable {
    /// 1, 2, 4 or 8 after a pinch settles (live values in between while pinching).
    public var zoom: Double
    /// Centre of the magnified view, in window pixels.
    public var zoomCentre: SIMD2<Double>
    /// Before/after split position 0…1, or nil when the split is off.
    public var split: Double?
    /// A pass tile is selected: show that pass's intermediate (`PASS 1 OF 2 · INTERMEDIATE`).
    public var shownPass: Int?
    /// The Metal loupe's centre in window pixels while it is open.
    public var loupe: PixelPoint?
}

/// Requested vs acknowledged (Metro contract A.13).
public enum RenderPhase: Sendable, Hashable {
    case idle
    case rendering(pass: Int, of: Int)
    case preview
    case timing
}

/// The fixed-height status row (SPEC §4.1.3): exactly one line, highest priority first. Readout only (JF M-14).
public enum StatusLine: Sendable, Hashable {
    case rendering(BadgedLine)  // "RENDERING… PASS 2/2" (pass counter as a .literal)
    case notice(BadgedLine)     // σ-hold and switch notices; the σ-hold line stays in the readout's accessibility value
    case warning(BadgedLine)    // sampling and budget warnings ("TOO SLOW TO TIME · ≈ 700 ms MODELED")
    case lesson(BadgedLine)     // a lesson's look-for line, until a control changes
    case coaching(BadgedLine)   // first launch only
    case phase(BadgedLine)      // "74 FETCHES · 2 PASSES · LINEAR-SAMPLED" (PassPlan.phase)
    public var line: BadgedLine { get }
    public var text: String { get }
}

/// Restorable per-device state (UserDefaults / @SceneStorage): later launches show it immediately (SPEC §2).
public struct BenchSnapshot: Sendable, Codable, Hashable {
    public var configuration: RenderConfiguration
    public var view: WindowViewState
    public var compare: CompareState?
    public var firstLaunchDone: Bool
}

/// The Trace's Jump menu (SPEC §6.1). Items that do not apply are hidden, not disabled.
public enum ProbeJump: String, Sendable, Hashable, CaseIterable {
    case featureProbe, brightestOutput, worstParity, inversionRing, edge, impulsePeak, corner, tileBoundary
    public var title: String { get }
}

/// Launch arguments for headless and on-device screenshots: `-B2Scenario <name> [-B2Blur <id>] [-B2Specimen <id>]
public enum LaunchScenario: String, Sendable, CaseIterable {
    case bench, firstLaunch = "first-launch", compare, layers, trace, catalog, fingerprints, divergence, lessons, fingerprint,
         fieldGuide = "field-guide", thisPhone = "this-phone", runs, settings, calibrate, loupe, accessibility,
         /// Every Metro component on one scrolling page (METRO-COMPONENTS' screenshot target).
         gallery,
         /// Every figure and block kind rendered from fixtures (CONTENT-VIEWS' screenshot target).
         contentGallery = "content-gallery"

    public struct Launch: Sendable, Hashable {
        public var scenario: LaunchScenario
        public var blur: BlurID?
        public var specimen: SpecimenID?
        public var floor: Floor?
        public var parameters: [String: String]
    }
    public static func parse(_ arguments: [String]) -> Launch?
}

/// The loupe's reading (SPEC §4.1.3): 14 × 14 output texels around its centre, LIVE, from a full-resolution Run only.
public struct LoupeReading: Sendable, Hashable {
    public var centre: PixelPoint
    public var texels: [SIMD4<Float>]
    /// 3 significant digits, the one probe-value precision used everywhere (review fix P-62).
    public var centreLinear: BadgedValue
    /// The sRGB 8-bit code of the centre (COMPUTED from the LIVE value).
    public var centreCode8: BadgedValue
}

/// LOOKS MOST LIKE (SPEC §7.1): the nearest catalog entry to a MEASURED shape, its distance badged (review fix E-51).
public struct NearestMatch: Sendable, Hashable {
    public var blur: BlurID
    public var distance: BadgedValue
}

/// Where the fingerprint strip and ON THIS PHONE come from (review fix P-31). Tier S entries never use `.metalModel`:
public enum FingerprintEvidence: Sendable, Hashable {
    /// Our Metal implementation of this entry, rendered now (LIVE). Tier 1/2 only.
    case metalModel
    /// The real Apple API rendered by ImageRenderer (MEASURED · OFFSCREEN) or a Calibrate result for this subject.
    case offscreenRender(DeviceStamp)
    /// Tier S before a calibration exists: the slots read NOT YET MEASURED.
    case notYetMeasured
}

/// Everything the fingerprint card shows (SPEC §7.1), assembled by ENGINE, drawn by UI-ATLAS.
public struct FingerprintCardModel: Sendable, Equatable {
    public var entry: CatalogEntry
    /// The UNIQUE row (SPEC §7.2).
    public var unique: LabeledValue
    /// Excess kurtosis of the LSF at the current parameters (COMPUTED) on the shared −1.2 … +3 axis.
    public var excessKurtosis: BadgedValue
    /// PSF (log intensity), STAR (36-cycle crop), EDGE (step profile): 128 × 128 renders at σ_equiv 4 px (engraved
    public var strip: [ImageBuffer]?
    public var stripEvidence: FingerprintEvidence
    /// H for LSI, local H for LSV, T(ν, A) at A = 0.05 and 0.5 for adaptive; nil for rank filters.
    public var responses: [ResponseCurve]
    public var partsWays: [BlurID: FloorComparison]
    /// ON THIS PHONE (MEASURED on demand: GPU output for Tier 1/2, the CalibrationResult for Tier S); nil until measured.
    public var onThisPhone: ShapeMeasurement?
    public var onThisPhoneEvidence: FingerprintEvidence
    public var looksMostLike: NearestMatch?
    /// The honesty rule of review fix P-31: no Tier S field is LIVE.
    public var tierSViolations: [String] { get }
}

/// One render request (ENGINE → RenderCoordinator).
public struct RenderRequest: Sendable, Hashable {
    public var configuration: RenderConfiguration
    public var slot: RunSlot
    public var quality: RenderQuality
    public var generation: UInt64
    public var kind: RunKind
    /// Render with the TRACE_PROBE specialization (the frame on screen while Trace is open IS the traced frame).
    public var traced: Bool
}
```

## Review log (design review round 1, 14 October 2026)

Inputs: `design/review-engineering.md` (items 1–30 of the orchestrator's list, cited here and in the text as **E-1 … E-30**) and `design/review-product.md` (items 31–75, cited as **P-31 … P-75**). Every blocker and major item and every minor item was applied, except where noted below. Changes touch SPEC.md, this file and the frozen contract in `Documentation/interfaces/` (Appendix A regenerated from it).

**Verification of the amended contract** (MEASURED, this Mac, 14 October 2026, no simulator): `swift build` with `-warnings-as-errors`; 32/32 tests (27 BlurCore incl. the new `SKEL_ReviewFixes`, 5 BlurGPU on the M1 Max GPU); `blur-gpucheck` 20/20 cases (two Gaussian seeds × 256 and 894), also with `--apple2-limits`; Metal compiled for `iphoneos` with `-Wall -Wextra`, no diagnostics; BlurCore, BlurGPU and `AppContract` typecheck for `arm64-apple-ios27.0` with `-strict-concurrency=complete -warnings-as-errors`. Probe scripts: `$TMPDIR/blur2ool-review-apply/`.

### Applied

| Item | Where | Change |
|---|---|---|
| E-1 | §0 rules 3–4a, §11.1 rules 2–3, §13 rules 2–3a, §9.2 S10 | `B2_AREA` mirroring of other areas' last green snapshots (`publish-green`, `$B2_GREEN_DIR`, `Tools/ownership.tsv`; frozen stub fallback); symbol prefixes or namespace enums enforced by `lint-names` |
| E-2 | §11.1, §11.4, §8.1 PHONE, §9.2 S11 | `device-session` holds the lock once for install → stamp check → launch → shot → test-without-building; `device-build` / `device-build-for-testing` outside the lock; `B2BuildStamp` in Info.plist; hold guard keys only on simulator destinations/SDKs |
| E-3 | `GPUContext`, `GPUBlurPipeline`, §5.8 rules 6–7, §5.15 rule 3 | async `prepare` and pipeline getters (detached compile; the SDK has no async overloads of `makeFunction(name:constantValues:)`/`make…PipelineState`, MEASURED by the compiler), coalesced per key; `prepared…Pipeline` lookups and `GPUError.notPrepared`; post-idle pre-warm; `MTLBinaryArchive` optional |
| E-4, P-36 | `OperatorRequest.pixelScale`, `previewRequest`, `previewScale`, `PixelPoint.previewMapped`, `b2_common_downsample2x_fs` + `ImageBuffer.downsampled2x`, `RenderQuality.quarter/publishesMeasurements`, `BenchModel.lastFull`; SPEC §4.1.6 | one frozen preview rule; rank/selection, system and atlas entries have no preview; previews publish the image only (`HELD` readouts) |
| E-5 | `ParityEvaluation.localScale`, `PassPlan.supportRadius`, §7 rules 1 and 9, §3.2 item 5 | local scale; mutation cases per tolerance class in GPUCHECK; CPU proof test |
| E-6 | `SubTexelRounding`, `ReferenceOptions.forDevice`, `ParityTolerance.dependsOnSubTexelRule`, §4.3, §7 rules 2 and 7 | M1 Max only (Simulator not independent); automatic one-time phone probe; bilinear classes reportOnly until it runs; explicit 2 × 2 mip shaders |
| E-7 | `FetchBudget`, `PassPlan.fetchesPerFrame`, `TimingRequest`, `TimingStopReason`, `RenderScheduler.touchBegan`/`.cancelMeasurements`; SPEC §4.1.6, §9.1, §9.4 | preview ≤ 2·10⁸ and full ≤ 2·10⁹ fetches (MODELED); quarter previews; automatic switches or range ends (disc, polygon, NLM, heat; COMPUTED per entry); budgeted, cancellable timing; banded full renders |
| E-8 | `BlurReference.runCrop`, `ParityRunner` (detached CPU half, `ParityRegionPolicy`), §5.5, §7 rule 7 | `referenceCrop` required for heavy classes (with a CORE test); gpucheck 894 = 128² crops; in-app parity after timing, background, cancellable |
| E-9 | §2 project.yml, `HalfImageData`, `GPUContext.upload` | `-O` for BlurCore/BlurGPU in all configurations; fp16 conversion off the main actor |
| E-10 | `SpecimenOptions.canvasOptions`, `BlurReference.run(exposureEV:)`, `encodeWindowCopy(exposureEV:)`, `b2_common_window_fs`; SPEC §11 rule 5 | exposure at render time; canvases at 0 EV; test that 2^EV commutes with fp16 rounding |
| E-11 | §5.8 rule 5, `RenderCoordinator` docs | one display instance per (slot, blur, variant), separate timing and parity instances; readbacks before the next encode |
| E-12 | `GaussianOperator.computeTileBytes`, §4.4 rules 2–3, SPEC §5.3 A, §9.4 | dynamic (256 + 2r) × 8 B row tile (σ 4 → 2,240 B; fits up to r 896); 256 × 1 allowed; P4 moved to σ 8 |
| E-13 | `PassPlan.traceCapacity`, `TraceRequest.sized`, `b2_trace_final`, `TracedComparison`, §7 rule 5 | plan-sized capacity; mandatory flags = 2 final record in every traced pass (seeds updated, MEASURED passing); overflow fails |
| E-14 | `GaussianPassEncoder`, `b2_f2_gauss_separable_fs`, `GaussianSeparablePipeline`, §6.1 | SKEL-written shared Gaussian stage with its own parity cases (incl. renormalise and HDR +6 EV) |
| E-15 | §9.1 item 5 | SKEL seeds: compute tile (dynamic memory, traced), MRT pass, commandBufferPerPass timing smoke test |
| E-16 | §8 intro, §11.1 | `core-test --area` (anchored `\.TAG_`), `device-test --area` with one `-only-testing` per class, failing on zero tests |
| E-17 | `GPUContext.recordsDispatches` | dispatch log only in gpucheck/tests |
| E-18 | `ParityTolerance.adjusted(for:)`, §7 table | bit-exact classes become fastMath when a colour pass runs |
| E-19 | `GPUCommandRecorder.commandBuffer(forPass:)` | negative indices get their own command buffers (test added) |
| E-20 | `MetalSpecimenView.makeUIView(windowPixels:)`, UI-SPECIMEN acceptance | fixed N × N drawable, display scale, sRGB layer, phone AppTest |
| E-21 | `CalibrationAPI` comment, §5.13, SPEC §2/§13.2 | one render per run-loop turn, timed, × 2 back-off, none while a control is active |
| E-22 | §5.6, TESTIMAGES, SPEC §11 rule 2 | phone-vs-Mac canvas hash AppTest; generators restricted to +, −, ×, ÷, √ and BlurCore's own transcendental functions |
| E-23 | §3.2, §11.1, §11.5 | `gpucheck --metallib` (per-file offline compile with Xcode's flags); both modes in GATE and INTEGRATE |
| E-24 | §0 rule 2, §13 rule 2, §9.1 | `Documentation/build/requests/<AREA>.md` |
| E-25 | §5.9, SPEC §2 | the sharp INPUT until the first Run |
| E-26 | `GPUContext.encodeReadTexels`, `PendingReadback` | probe texel read inside the render's own recorder |
| E-27 | `EncodedBlur.transientTextures`, `GPUContext.recycle(_:)` | pre/post textures recycled after completion |
| E-29 | §2 project.yml | `ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS: NO` |
| E-30 | §11.1 `device` | `CODE_SIGNING_ALLOWED=NO`; signing only in `device-build*` |
| P-31 | `FingerprintEvidence`, `FingerprintCardModel.tierSViolations`, `SystemOffscreen.renderStrip`; SPEC §7.1 | Tier S strip, ON THIS PHONE and LOOKS MOST LIKE from offscreen renders / CalibrationResult; NOT YET MEASURED before; no Tier S field LIVE (tested) |
| P-32 | SPEC §5.3 B, §11 rule 2 and rows 2–3; §5.6; TESTIMAGES and F5A fixtures | coordinate convention stated; descent B probe (747, 460) mid-wedge, star 1.000 → 1.000, zone plate 0.224 → 0.499 (COMPUTED, `py/zoom.py`, method validated against the old 0.508); star edge probe (404, 288) |
| P-33 | SPEC §8.4, §4.1.4, §4.2; seed `floorKey(.api)`; ANALYSIS | floor-2 key normalised to per-axis σ (3 %); floor 1 `NOT IN <TOOL>` and skipped for PARTS WAYS; CSS-vs-SwiftUI row parts at API |
| P-34 | SPEC §4.1.4, §5.1, §12.2 item 9 | `≈4.4`, "sigma-matched; kernel shape differs", `SAME σ, DIFFERENT KERNEL`, `.offscreen` everywhere |
| P-35 | SPEC §7.1, §4.2, §8.3, §17 item 21; seed card rows | `H ≥ 0 (CONTINUOUS)`, `TRUNCATED: RIPPLE`, as-run MIN H in Compare |
| P-37 | SPEC §4.3; CONTENT-LAYERS | per-variant IN THIS APP line; pair table; MODELED effective-tap error 1.1·10⁻⁴ (COMPUTED, `py/kern.py`) |
| P-38 | `SigmaHoldResult` (`requestedSigma`, `isClamped`, `standardLine`); SPEC §8.1 | domain-limit lines; tests at σ 12 and 64 |
| P-39 | `SystemOffscreen.probeTexel`; SPEC §4.1.9 (f) | Tier S PIXEL from an offscreen render of the same view, else `—` |
| P-40 | SPEC P25, §9.4; F4 fixture | inverse filter 139 vs Wiener 0.72 / 47 (COMPUTED); `K = 0` detent |
| P-41 | SPEC §5.1 floor 6, §8.4, P26, P28, §10.1, §11 row 16, §13.1 | box³ as INFERRED closest model; gamma-space offscreen MEASURED / on screen INFERRED; materials claims INFERRED |
| P-42 | SPEC §5.1 floors 3–4, §5.2 | `ERROR VS <reference>` slot; signed 2-D H heat map for non-separable entries |
| P-43 | SPEC §4.1.3 caption row, §4.1.10, §14 | provenance never hidden at AX sizes |
| P-44 | SPEC §4.3; UI-LAYERS | plain ScrollView with snapping and rail jumps |
| P-45 | SPEC §4.1.3, §12.2, §14 | `@ScaledMetric` with caps and truncation order; badges ≥ 11 pt; dashed INFERRED chip border |
| P-46 | SPEC §8.2, §4.2, §14; UI-COMPARE | `DRIVE A · B` segmented control plus accessibility actions |
| P-47 | SPEC §4.1.2, §14 | switch announcement with name, held σ, conversion, PSF SHAPE, RESPONSE; σ-hold line in the accessibility value |
| P-48 | SPEC §4.1.10, §4.2, §4.3, §7.1; §11.3 | two-line LabeledValues, one badge per number, `Descend both`, no abbreviated badge words; text-fit AppTests at 430/393/375 pt and xxxLarge |
| P-49 | SPEC §4.5 | three-line Blurs rows ≥ 72 pt; wrapping Divergence rows |
| P-50 | SPEC §2, §11 row 1, §18 D11, §19; TESTIMAGES | brighter 1-px lights (20–1,000; MODELED ≈ 60 lights ≥ 0.25 linear, fixture ≥ 40); hexagon claim reworded |
| P-51 | `StatusLine(BadgedLine)`, `BadgedLine`, `Lesson.statusLine`, `NearestMatch.distance`, `LoupeReading.centreCode8`, `PassPlan.phase`; SPEC §12.2 item 8 | numbers in lines are badged; lint for digits in plain strings |
| P-52 | SPEC §5.1 floor 1 | `YOU TYPE [10] in [tool ▾]` drives the Bench |
| P-53 | SPEC §6.4 item 6, §12.1 | "a CPU re-computation of a GPU value is never LIVE" |
| P-54 | SPEC §12.5 | "Metal textures or offscreen renders, never the screen" |
| P-55 | SPEC §13.3 | objective capture test for drawHierarchy |
| P-56 | SPEC P27; F11 fixture | `MODELED · σ = r/2 (ONE OF TWO SOURCES)` |
| P-57 | `TimingSummary.overheadMilliseconds`; SPEC §4.1.6, §4.1.8, §4.3 | GPU ms = blur passes only; overhead separate |
| P-58 | SPEC §7.1, §7.2, §17 item 22; seed `uniqueNumber` | separable and isotropic at once (Herschel–Maxwell) |
| P-59 | SPEC §5.2, §17 item 23; F9 fixture | H ≥ 0 for λ ≤ ⅛; kernel non-negative to ¼ |
| P-60 | SPEC P3, P21; F1/F5A fixtures | P3 defined as relative L2: 38 / 8.8 / 4.8 / 3.4 % (COMPUTED, `py/p3.py`); P21 continuous −0.2172 at 1.430, discrete UNVERIFIED until FAM-F5A |
| P-61 | SPEC §5.3 C floor 1 | "same parameters, different range metric" plus the matching linear-float call |
| P-62 | SPEC §4.1.3, §4.1.4, §4.3, §14; `LoupeReading` | 84/255; 3 significant digits everywhere (`0.0885`) |
| P-63 | SPEC §4.3, §5.1, §5.3 A; §14 reading (c) | discrete MASS CUT per axis and 2-D (σ 12: 0.235 % / 0.47 %; σ 4: 0.173 % / 0.346 %; COMPUTED) |
| P-64 | SPEC §5.1 floor 6, §4.8, §13.3 | `NAMES FROM iOS 26.5 SIM / macOS 27.2 · NOT RE-READ FOR iOS 27 · NOT OBSERVED RUNNING` |
| P-65 | SPEC §4.1.9 (g), P28 | `MODELED · STRUCTURE INFERRED` |
| P-66 | SPEC §3, §4.1.3; §5.9 | kernel-well face and ±3σ bracket follow the acknowledged full Run |
| P-67 | SPEC §4.1.3 rulers, §18 D1 | `SCALE 1 PX = 0.33 PT`; D1 cites METRO §C.1 and why it is reversed |
| P-68, P-70 | SPEC §4.3, §9.4 | floor rail overlaid inside the column, 44 pt wide; Kawase presets ≤ 8 passes |
| P-69 | SPEC §6.6 | Play announces per floor under VoiceOver |
| P-71 | SPEC §4.5 | AX layout of the Fingerprints matrix |
| P-72 | SPEC §8.3 | Line-up pills: tapped quadrant vs A only |
| P-73 | SPEC §4.1.4 | `UNVER.` and `—` with full spoken forms; no units on chips |
| P-74 | SPEC §7.1; `FingerprintCardModel.strip` doc | strip at σ_equiv 4 px, engraved |
| P-75 | SPEC §1, §10.1, §4.1.9 (e), P19 | 53 live glyphs (50 GPU + 3 system); bilateral crowns as §9.4; P19 in both compositing spaces (COMPUTED) |

**Found while applying (MEASURED):** the separable integer-tap seed reaches **2 ulp16**, not 1, against the Double reference (an fp16 intermediate rounded differently by fp32 and Double adds an ulp), so `exactF32` is now 2 ulp16 (§7 table). The first draft's 1-ulp class failed 768–6,144 channels per case.

### Rejected, changed or deferred, with reasons

- **P-36, "point-sampled downsampling" for previews: changed to the engineering review's 2 × 2 mean.** Point sampling aliases the periodic test images (zone plate, stripes, checkerboard, star) far more than a 2 × 2 mean, which is a σ 0.5 px box (stated in the Field guide), deterministic and mirrored on the CPU. The rest of P-36 (parameters × ½, time × ¼, probe ⌊p/2⌋, HELD readouts, rank exemption) is applied.
- **E-5, "weights × 1.01 must fail for every class": kept as a gate rule, not promised.** Under `bilinear`, the per-pass 2⁻¹⁰ term (×local scale) is larger than 1 % of dim outputs, so a 1 % weight error in dark regions is within the class by construction. The local scale fixes the review's actual failure (a kernel dropping half its taps passing at the buildings; proven by `SKEL_ReviewFixes`). GPUCHECK runs the full mutation set; any class that lets a mutation pass is tightened with a MEASURED justification before INTEGRATE (§7 rule 9).
- **E-3, "use the async Metal APIs": changed to a detached compile.** This SDK exposes no async overloads of `makeFunction(name:constantValues:)` or `make…PipelineState` (MEASURED: the compiler reports "no async operations" on `await`), so an `await` on them would still compile on the main actor. A detached task with only Sendable values crossing does the job and typechecks under Swift 6 strict.
- **E-28, a compute-traced fallback for the Simulator: deferred.** Adding simulator-only code that cannot be compiled or tested under the hold contradicts §12.3. The traced fragment pass is the first post-release simulator check (§12.5); INTEGRATE decides on a fallback only if it fails.
- **E-9 for `swift test`**: the `-O` setting applies to the Xcode targets (the builds the phone judges). SwiftPM `core-test` stays a debug build (unsafe optimisation flags would break `@testable`); its reference tests use small images, and `gpucheck` is already a release build.
- **P-70, "let Kawase tiles scroll"**: the 17-pass preset was dropped instead, so PASSES 1–8 and the tiles always agree.
- **P-73, "units on all chips or none"**: none (six characters cannot hold honest units); units live in the spoken value, the floor header and the new ruler scale engraving.
- **P-50, "launch at +3 EV"**: the light energies were changed instead (buildings would read 0.16–0.48 at +3 EV); the +3 EV alternative is SPEC §18 D11 / U5 for the user.
- **Additions beyond the reviews:** PARTS WAYS skips floor 1 when a blur is absent from the home tool (otherwise every Gaussian-vs-box lesson would "part ways" at SLIDE); NLM budget combinations were recomputed (search² × patch²: search 21 exceeds the budget for every patch, and patch 5 or 7 with search 11 do too).

<!-- STATUS: COMPLETE -->
<!-- REVIEW APPLIED -->
