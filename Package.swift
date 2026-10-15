// swift-tools-version: 6.0
// Blur2ool — SwiftPM manifest (ARCHITECTURE.md §3.1). FROZEN: change only through a request in Documentation/build/requests/<AREA>.md.
// Swift 6 language mode for every target. BlurCore is Foundation-only and nonisolated; BlurGPU adds Metal but no UI.
// The Xcode project (project.yml) compiles the same Sources/BlurCore and Sources/BlurGPU folders as iOS frameworks.
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
