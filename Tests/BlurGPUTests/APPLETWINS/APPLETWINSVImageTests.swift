import Foundation
import Metal
import Testing
import BlurCore
@testable import BlurGPU

// OWNER: APPLE-TWINS. vImage twins (CAL §5.4): box and tent convolve with kernel 2r + 1 are the exact 8-bit box and tent,
// under each edge flag; blending happens in whatever the 8-bit buffer holds.

@Suite struct APPLETWINS_VImage {
    typealias S = APPLETWINS_Support

    /// vImage against the exact rational result of the same kernel and edge flag on random 8-bit pixels: every output
    /// is that value rounded to the nearest code (|vImage − exact| ≤ ½ LSB).
    @Test func boxAndTentAreExactIn8Bit() throws {
        let w = 41, h = 29
        let pixels = (0..<(w * h)).map { UInt8(truncatingIfNeeded: NoiseHash.pcg(UInt32($0) &* 2_654_435_761) >> 7) }
        let stamp = APPLETWINS_Support.macStamp(gpuName: MTLCreateSystemDefaultDevice()?.name ?? "Apple silicon", gpuFamily: "CPU · Accelerate")
        for tent in [false, true] {
            for r in [1, 2, 4, 7] {
                for edge in AppleTwinVImageEdge.allCases {
                    let job = AppleTwinVImage.Job(tent: tent, kernel: 2 * r + 1, edge: edge, storage: .linear8)
                    let got = try AppleTwinVImage.convolvePlanar(pixels, width: w, height: h, job: job)
                    let weights = tent ? APPLETWINS_Reference.tent(halfWidth: r) : APPLETWINS_Reference.box(halfWidth: r)
                    let want = APPLETWINS_VImageReference.planar(pixels, width: w, height: h, weights: weights, edge: edge)
                    var worst = 0.0, notNearest = 0
                    for i in 0..<(w * h) {
                        let e = abs(Double(got[i]) - want[i])
                        worst = Swift.max(worst, e)
                        if e > 0.5 + 1e-9 { notNearest += 1 }
                    }
                    let name = "\(tent ? "vImageTentConvolve" : "vImageBoxConvolve")_Planar8 r \(r) \(AppleTwinVImage.flagName(edge))"
                    #expect(notNearest == 0, "\(name): \(notNearest) outputs not the nearest code to the exact value (worst \(worst) LSB)")
                    S.record(name, [("max |vImage − exact|", worst, NumberStyle.decimals(3, unit: "LSB", spokenUnit: "codes"))], stamp: stamp)
                    // The four-channel path the runner uses treats every channel like the plane.
                    var rgba = [UInt8](repeating: 255, count: 4 * w * h)
                    for i in 0..<(w * h) { rgba[4 * i] = pixels[i]; rgba[4 * i + 1] = pixels[i]; rgba[4 * i + 2] = pixels[i] }
                    let got4 = try AppleTwinVImage.convolve4(rgba, width: w, height: h, job: job)
                    var mismatches = 0
                    for i in 0..<(w * h) where got4[4 * i] != got[i] || got4[4 * i + 2] != got[i] { mismatches += 1 }
                    #expect(mismatches == 0, "\(name): ARGB8888 differs from Planar8 at \(mismatches) pixels")
                }
            }
        }
    }

    /// σ of the step response equals the closed form (CAL: the same as MPS to 3 decimals); support is 2r + 1 samples.
    @MainActor @Test func stepSigmaIsExact() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        for subject in [CalibrationSubject.vImageBox, .vImageTent] {
            for r in [2, 8, 16] {
                let e = try await S.edge(runner, subject, Double(r), colourMode: .nonLinear, context: context)
                let exact = subject == .vImageBox ? AppleTwinAnalysis.boxSigma(width: 2 * r + 1) : AppleTwinAnalysis.tentSigma(halfWidth: r)
                #expect(abs(e.fit.sigma - exact) < 0.005 * exact, "\(subject.title) r \(r): σ \(e.fit.sigma) vs exact \(exact)")
                #expect(e.fit.supportSamples <= 2 * r + 1, "\(subject.title) r \(r): support \(e.fit.supportSamples)")
                S.record("\(subject.title) r \(r) step", [("σ", e.fit.sigma, NumberStyle.decimals(4, unit: "px", spokenUnit: "pixels")),
                                                          ("exact", exact, NumberStyle.decimals(4, unit: "px", spokenUnit: "pixels")),
                                                          ("kurtosis", e.fit.excessKurtosis, S.two),
                                                          ("kurtosis 45°", e.fit45?.excessKurtosis ?? .nan, S.two)], stamp: stamp)
            }
        }
    }

    /// CAL §5.4 edge flags at r = 8, in 8-bit encoded values: kvImageEdgeExtend clamps (black first column → 0.47),
    /// kvImageTruncateKernel renormalises (white border 1.0, black first column → 0.89), kvImageBackgroundColorFill with 0
    /// pads with transparent black (white border → 0.53).
    @MainActor @Test func edgeFlags() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        let expected: [AppleTwinVImageEdge: (verdict: AppleTwinEdgeVerdict, white: Double, blackColumn: Double?)] = [
            .extend: (.clamp, 1.0, 0.47), .truncateKernel: (.renormalised, 1.0, 0.89), .backgroundFill: (.transparent, 0.53, nil)]
        for (edge, cal) in expected.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let probe = try await runner.edgePolicy(.vImageBox, parameter: 8, options: AppleTwinOptions(vImageEdge: edge), context: context)
            #expect(probe.verdict == cal.verdict, "vImage \(edge): \(probe)")
            #expect(abs(probe.whiteBorderValue - cal.white) < 0.02, "vImage \(edge): white border \(probe.whiteBorderValue) vs CAL \(cal.white)")
            if let b = cal.blackColumn {
                #expect(abs(probe.blackColumnBorderValue - b) < 0.02, "vImage \(edge): black column \(probe.blackColumnBorderValue) vs CAL \(b)")
            }
            S.record("vImage box r 8 \(AppleTwinVImage.flagName(edge))", [("white border", probe.whiteBorderValue, S.three),
                                                                          ("alpha", probe.whiteBorderAlpha, S.three),
                                                                          ("black column border", probe.blackColumnBorderValue, S.three)],
                     stamp: stamp, note: "8-bit sRGB-encoded values; verdict \(probe.verdict.rawValue)")
        }
    }

    /// vImage averages the numbers in its buffer: sRGB-encoded storage gives the gamma-space midpoint (0.5 encoded),
    /// linear storage the linear-light one (≈ 0.735 encoded).
    @MainActor @Test func blendSpaceFollowsStorage() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner(), stamp = S.stamp(context)
        let encoded = try await runner.edgeSamples(S.request(.vImageBox, 4, colourMode: .nonLinear), context: context)
        let linear = try await runner.edgeSamples(S.request(.vImageBox, 4, colourMode: .linear), context: context)
        let e = try #require(encoded.first?.encodedMidpoint), l = try #require(linear.first?.encodedMidpoint)
        #expect(abs(e - 0.5) < 0.01, "sRGB 8-bit storage midpoint \(e)")
        #expect(abs(l - 0.7354) < 0.01, "linear 8-bit storage midpoint \(l)")
        S.record("vImage box r 4 edge midpoint", [("sRGB storage", e, S.three), ("linear storage", l, S.three)], stamp: stamp)
    }

    /// The runner's texture path: 8-bit clipping is counted, never hidden.
    @MainActor @Test func clippingIsReported() async throws {
        guard let context = try S.context() else { return }
        let runner = AppleTwinRunner()
        let size = ImageSize.square(16)
        var texels = S.pattern(width: 16, height: 16)
        texels[0] = SIMD4(4, 4, 4, 1)       // an HDR highlight: vImage's 8-bit buffer cannot hold it
        let input = try await runner.makeTexture(texels, size: size, format: .rgba16Float, context: context)
        let output = try runner.makeOutput(size: size, format: .rgba16Float, context: context)
        let report = try await runner.run(.vImageBox, parameter: 1, options: AppleTwinOptions(), input: input, output: output, context: context)
        #expect(report.clippedTexels == 1)
        #expect(report.notes.contains { $0.contains("clipped") })
        #expect(report.cpuMilliseconds != nil && report.gpuMilliseconds == nil)
    }
}

enum APPLETWINS_VImageReference {
    /// Exact (rational) 2-D separable convolution of 8-bit pixels under a vImage edge flag.
    static func planar(_ src: [UInt8], width w: Int, height h: Int, weights: [Double], edge: AppleTwinVImageEdge) -> [Double] {
        let r = weights.count / 2
        var out = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0.0, norm = 0.0
                for j in -r...r {
                    for i in -r...r {
                        var sx = x + i, sy = y + j
                        let inside = sx >= 0 && sy >= 0 && sx < w && sy < h
                        let weight = weights[i + r] * weights[j + r]
                        switch edge {
                        case .extend:
                            sx = Swift.min(Swift.max(sx, 0), w - 1); sy = Swift.min(Swift.max(sy, 0), h - 1)
                            sum += weight * Double(src[sy * w + sx]); norm += weight
                        case .truncateKernel:
                            if inside { sum += weight * Double(src[sy * w + sx]); norm += weight }
                        case .backgroundFill:
                            if inside { sum += weight * Double(src[sy * w + sx]) }
                            norm += weight
                        }
                    }
                }
                out[y * w + x] = sum / norm
            }
        }
        return out
    }
}
