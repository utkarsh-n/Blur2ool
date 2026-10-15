import Foundation
import Testing
@testable import BlurCore

// OWNER: SEMANTICS. HONEST (ARCHITECTURE §8.1) over everything SEMANTICS produces, the conventions table, the laws'
// arithmetic against the research tables (STACK §1.2, §2.4, §6.1, §8; CAL §5.2), and STACK §8 for "radius 10".

enum SEMANTICS_Catalog {
    /// Every canonical id of CATALOG.md §2 and §4 (typos in the conventions would otherwise pass silently).
    static let catalogIDs: Set<BlurID> = [
        "box-blur", "tent-blur", "iterated-box", "average-blur", "gaussian-blur", "binomial-blur", "iir-gaussian", "kawase-blur",
        "dual-kawase", "pyramid-blur", "exponential-blur", "lorentzian-blur", "frequency-lowpass", "fft-convolution",
        "linear-motion-blur", "anisotropic-gaussian", "kawase-streak", "camera-shake-blur", "velocity-buffer-motion-blur",
        "temporal-accumulation", "radial-zoom-blur", "spin-blur", "path-blur", "disc-blur", "polygonal-bokeh", "cats-eye-swirl-bokeh",
        "diffraction-airy", "anamorphic-bokeh", "depth-of-field-coc", "tilt-shift", "variable-progressive-blur", "frosted-glass-noise",
        "median", "bilateral", "joint-bilateral", "guided", "domain-transform", "kuwahara", "surface-blur", "nonlocal-means",
        "mean-shift", "tv-denoise", "heat-equation", "perona-malik", "coherence-enhancing-diffusion", "swiftui-layer-blur",
        "apple-uiblureffect", "liquid-glass", "css-backdrop-filter", "windows-acrylic", "windows-mica", "android-renderEffect",
        "drop-shadow", "bloom", "god-rays", "unsharp-mask", "difference-of-gaussians", "lanczos", "wiener-deconvolution",
        "morphology", "pixelate",
    ]
    static let sigmas: [Double] = [0, 0.3, 0.8, 4, 12, 60, 400]
    static let scales: [Double] = [1, 2, 3]
    static func swiftUIDerived(_ toolID: String) -> Bool { toolID == "swiftui" || toolID == "swiftui-shadow" }
}

@Suite struct SEMANTICS_Honesty {
    typealias C = SEMANTICS_Catalog
    typealias F = SEMANTICS_Fixture

    static let laws: [CalibrationLaw?] = [nil, F.phoneLaw(.swiftUIBlur, small: 0.98, large: 0.91, switchAt: 1.8),
                                          F.phoneLaw(.caLayerShadow, large: 0.9), F.phoneLaw(.ciGaussianBlur, large: 1.002)]

    @Test func everyValueEveryToolEveryBlurIsHonest() {
        var checked = 0
        for tool in SemanticsCatalog.tools {
            for blur in C.catalogIDs.sorted() {
                for scale in C.scales {
                    for law in Self.laws {
                        for sigma in C.sigmas {
                            let values = ToolConventions.readings(toolID: tool.id, blur: blur, sigmaPx: sigma, displayScale: scale, measuredLaw: law).map(\.value)
                                + [ToolConventions.slideChipValue(toolID: tool.id, blur: blur, sigmaPx: sigma, displayScale: scale, measuredLaw: law)]
                            for v in values { check(v, tool: tool.id, blur: blur, what: "σ \(sigma) @\(scale)"); checked += 1 }
                        }
                        for typed in [0.0, 1, 10, 21, 64] {
                            for r in ToolConventions.reverseReadings(toolID: tool.id, blur: blur, typed: typed, displayScale: scale, measuredLaw: law) {
                                check(r.value, tool: tool.id, blur: blur, what: "typed \(typed) @\(scale)"); checked += 1
                            }
                        }
                    }
                }
            }
        }
        #expect(checked > 100_000)
    }

    private func check(_ v: BadgedValue, tool: String, blur: BlurID, what: String) {
        #expect(v.honestyViolations.isEmpty, "\(tool) \(blur) \(what): \(v.honestyViolations)")
        #expect(!v.spoken.isEmpty)
        if v.qualifiers.contains(.unverified) { #expect(v.value == nil && !SEMANTICS_Fixture.hasDigits(v.text), "\(tool) \(blur) \(what)") }
        if v.value == nil && v.text != "—" && !v.qualifiers.contains(.unverified) { #expect(!SEMANTICS_Fixture.hasDigits(v.text), "\(tool) \(blur) \(what): \(v.text)") }
        if v.text == "—" { #expect(v.value == nil && !ToolConventions.offers(toolID: tool, blur: blur) || v.caption == "NOTHING TYPED") }
        // Every SwiftUI-derived number carries OFFSCREEN on its qualifiers, caption and spoken text (review fix P-34).
        if C.swiftUIDerived(tool), v.value != nil {
            #expect(v.qualifiers.contains(.offscreen), "\(tool) \(blur) \(what)")
            #expect((v.caption ?? "").contains("OFFSCREEN") && v.spoken.contains("offscreen"), "\(tool) \(blur) \(what)")
        }
        if v.provenance == .measured, v.value != nil { #expect(v.device != nil) }
        if v.qualifiers.contains(.notThisDevice) { #expect(v.device == SemanticsCatalog.researchMac) }
    }

    @Test func slideChipFitsSixCharacters() {
        for tool in SemanticsCatalog.homeToolIDs {
            for blur in C.catalogIDs.sorted() {
                for sigma in C.sigmas + [1_000, 12_345] {
                    let chip = ToolConventions.slideChipValue(toolID: tool, blur: blur, sigmaPx: sigma, displayScale: 3, measuredLaw: nil)
                    #expect(chip.text.count <= 6, "\(tool) \(blur) σ \(sigma): \(chip.text)")
                }
                let none = ToolConventions.slideChipValue(toolID: tool, blur: blur, sigmaPx: nil, displayScale: 3, measuredLaw: nil)
                #expect(none.text.count <= 6 && none.honestyViolations.isEmpty, "\(tool) \(blur): \(none.text)")
            }
        }
    }

    @Test func floorFactsAndBarsAreHonest() {
        // Every blur with two home tools, and every home tool with the blurs whose rows differ most.
        let pairs = C.catalogIDs.sorted().flatMap { [("swiftui", $0), ("photoshop", $0)] }
            + SemanticsCatalog.homeToolIDs.flatMap { h in (["gaussian-blur", "drop-shadow", "box-blur", "median", "kuwahara"] as [BlurID]).map { (h, $0) } }
        for (home, blur) in pairs {
            do {
                for (sigma, reverse) in [(Optional(4.0), Optional<Double>.none), (12, nil), (nil, nil), (4, 10)] {
                    let facts = ToolConventions.slideFloorFacts(blur: blur, sigmaPx: sigma, displayScale: 3, homeToolID: home, reverseTyped: reverse)
                    #expect(facts.numbers.count <= 6, "\(home) \(blur)")
                    #expect(facts.numbers.first?.id.hasPrefix(home) == true, "\(home) \(blur): home tool first")
                    var values = facts.numbers.map(\.value)
                    if case .toolBars(let bars)? = facts.figure { values += bars.rows.map(\.value); #expect(bars.homeToolID == home) }
                    func walk(_ blocks: [ContentBlock]) {
                        for b in blocks {
                            switch b {
                            case .values(let rows): values += rows.map(\.value)
                            case .disclosure(_, let inner): walk(inner)
                            case .paragraph(let p): #expect(!SEMANTICS_Fixture.hasDigits(p), "paragraph digits: \(p)")
                            default: break
                            }
                        }
                    }
                    walk(facts.details)
                    for v in values { #expect(v.honestyViolations.isEmpty, "\(home) \(blur): \(v.text) \(v.honestyViolations)") }
                }
            }
        }
    }

    @Test func unitChainsAreHonestLines() {
        for c in SemanticsCatalog.controls where c.isOfferedWithLaw {
            for typed in [0.5, 4, 10, 21] {
                guard let line = ToolConventions.unitChain(toolID: c.toolID, blur: c.blur, typed: typed, displayScale: 3, measuredLaw: nil) else { continue }
                #expect(line.honestyViolations.isEmpty, "\(c.id) \(typed): \(line.honestyViolations)")
            }
        }
    }

    @Test func throughTheServiceLocator() {
        let a = BlurServices.tools.typedValue(toolID: "css", blur: "gaussian-blur", sigmaPx: 4, displayScale: 3, measuredLaw: nil)
        #expect(a == ToolConventions.typedValue(toolID: "css", blur: "gaussian-blur", sigmaPx: 4, displayScale: 3, measuredLaw: nil))
        #expect(BlurServices.tools.all.count == SemanticsCatalog.tools.count)
        let chip = BlurServices.tools.slideChipValue(toolID: "swiftui", blur: "gaussian-blur", sigmaPx: 12, displayScale: 3, measuredLaw: nil)
        #expect(chip.text == "≈4.4")
        #expect(!BlurServices.tools.offers(toolID: "swiftui", blur: "median"))
    }
}

@Suite struct SEMANTICS_Conventions {
    typealias C = SEMANTICS_Catalog

    @Test func idsAreUniqueAndKnown() {
        let ids = SemanticsCatalog.tools.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ToolConventions().all.map(\.id)) == Set(ids))
        var pairs = Set<String>()
        for c in SemanticsCatalog.controls {
            #expect(pairs.insert(c.id).inserted, "duplicate control \(c.id)")
            #expect(C.catalogIDs.contains(c.blur), "unknown blur id \(c.blur) in \(c.id)")
            #expect(SemanticsCatalog.tool(c.toolID) != nil, "unknown tool \(c.toolID)")
        }
    }

    @Test func homeToolMenuMatchesTheSpec() {
        #expect(ToolConventions.homeToolOptions.map(\.toolName)
                == ["SwiftUI", "CSS", "Figma", "Sketch", "Photoshop", "Core Image", "Android", "Flutter", "GIMP", "OpenCV"])
        for t in SemanticsCatalog.homeToolIDs { #expect(ToolConventions.offers(toolID: t, blur: "gaussian-blur"), "\(t)") }
    }

    @Test func everyControlCarriesItsEvidence() {
        for c in SemanticsCatalog.controls {
            switch c.mapping {
            case .law:
                #expect(c.provenance != nil && c.lawDescription != nil, "\(c.id)")
                if c.provenance == .measured { #expect(c.measuredOn != nil && c.qualifiers.contains(.notThisDevice), "\(c.id)") }
                if c.qualifiers.contains(.weakSource) { #expect(c.provenance == .reference || c.provenance == .modeled, "\(c.id)") }
            case .unverified:
                #expect(c.provenance == nil && c.lawDescription == nil, "\(c.id)")
            case .noSigma(let words, let chip, let spoken):
                #expect(c.provenance != nil && chip.count <= 6 && !spoken.isEmpty, "\(c.id)")
                #expect(!SEMANTICS_Fixture.hasDigits(words) && !SEMANTICS_Fixture.hasDigits(chip), "\(c.id)")
            }
            #expect(!c.source.citation.isEmpty, "\(c.id)")
            if let cap = c.caption { #expect(!SEMANTICS_Fixture.hasDigits(cap), "caption digits in \(c.id)") }
            if C.swiftUIDerived(c.toolID) && c.isOfferedWithLaw { #expect(c.qualifiers.contains(.offscreen), "\(c.id)") }
        }
        let byID = Dictionary(uniqueKeysWithValues: ToolConventions().all.map { ($0.id, $0) })
        #expect(byID["photoshop"]?.lawDescription == nil, "UNVERIFIED mappings have no law")
        #expect(byID["swiftui"]?.provenance == .measured && byID["swiftui"]?.unit == .pt)
        #expect(byID["css"]?.provenance == .reference && byID["css"]?.unit == .cssPx)
        #expect(byID["figma"]?.provenance == .inferred)
        #expect(byID["android"]?.lawDescription?.contains("0.57735") == true)
    }

    @Test func researchMacStamp() {
        let mac = SemanticsCatalog.researchMac
        #expect(mac.label == "Mac (Apple M1 Max) · macOS 27.2 · 13 Oct" && !mac.isSimulator)
    }
}

@Suite struct SEMANTICS_LawMath {
    @Test func svgThreeBoxMatchesStackTable() {
        // STACK §1.2: s → d → effective σ.
        let table: [(Double, Double, Double)] = [(2, 4, 2.121), (3, 6, 3.136), (5, 9, 4.472), (8, 15, 7.483), (10, 19, 9.487),
                                                 (20, 38, 19.162), (50, 94, 47.165), (100, 188, 94.166)]
        for (s, d, sigma) in table {
            #expect(SemanticsMath.svgThreeBoxWidth(stdDeviation: s) == d, "s \(s)")
            #expect(abs(SemanticsMath.svgThreeBoxSigma(d: d) - sigma) < 5e-4, "s \(s)")
        }
    }

    @Test func impellerMatchesStackTable() {
        // STACK §2.4 (integer taps): 10 → 7.51; 100 → 56.3; 200 → 74.2; 500 → 61.0. Non-monotonic above σ ≈ 219.
        #expect(abs(SemanticsMath.impellerEffectiveSigma(10) - 7.51) < 0.01)
        #expect(abs(SemanticsMath.impellerEffectiveSigma(100) - 56.3) < 0.05)
        #expect(abs(SemanticsMath.impellerEffectiveSigma(200) - 74.2) < 0.05)
        #expect(abs(SemanticsMath.impellerEffectiveSigma(500) - 61.0) < 0.05)
        #expect(SemanticsMath.impellerEffectiveSigma(219) > SemanticsMath.impellerEffectiveSigma(400))
    }

    @Test func discreteWidths() {
        #expect([0.5, 2, 2.5, 4, 9, 10, 10.5, 16, 25].map(SemanticsMath.ciBoxWidth) == [1, 1, 3, 3, 9, 9, 11, 15, 25])  // CAL §5.2
        #expect(abs(SemanticsMath.boxSigma(width: 21) - 6.055) < 5e-4 && abs(SemanticsMath.tentSigma(width: 21) - 4.472) < 5e-4)
        #expect(abs(SemanticsMath.opencvSigma(kernelRadius: 10) - 3.5) < 1e-12)          // ksize 21
        #expect(abs(SemanticsMath.opencvSigma(kernelRadius: 1) - 0.5.squareRoot()) < 1e-12) // ksize 3: ¼ ½ ¼
        #expect(abs(SemanticsMath.gimp28Divisor - 3.32904) < 1e-5)
        let inv = SemanticsMath.typed(.ciBoxWidth, sigmaPx: 2.6, unitScale: 1)
        #expect(inv.typed == 9 && inv.status == .nearest)
    }

    @Test func edgeWidthsMatchStackSection8() {
        #expect(abs(SemanticsMath.edgeWidth(.gaussian(sigma: 10)) - 25.63) < 0.01)
        #expect(abs(SemanticsMath.edgeWidth(.boxes([21])) - 16.8) < 0.02)
        #expect(abs(SemanticsMath.edgeWidth(.disc(radius: 10)) - 13.74) < 0.02)
        #expect(abs(SemanticsMath.edgeWidth(.boxes([11, 11])) - 12.16) < 0.02)
        #expect(abs(SemanticsMath.edgeWidth(.boxes([9])) - 7.2) < 0.02)
        #expect(abs(SemanticsMath.edgeWidth(.boxes([19, 19, 19])) - 19 * (3 - 2 * pow(0.6, 1.0 / 3))) < 0.01)   // Irwin–Hall: 24.95
        let sketch = SemanticsMath.truncatedGaussian(effectiveSigma: 10, cutInSigmas: 2.5)
        #expect(abs(SemanticsMath.sigma(of: sketch) - 10) < 1e-6)
    }

    @Test func piecewiseInverseCoversTheGap() {
        // A law whose large ratio exceeds the small one leaves σ values no radius reaches: the switch is the nearest.
        let law = CalibrationLaw(subject: .swiftUIBlur, smallRatio: 0.8, largeRatio: 1.0, switchParameter: 2, points: [],
                                 device: SemanticsCatalog.researchMac)
        let inv = SemanticsMath.inverse(law, sigmaPx: 1.7, unitScale: 1)
        #expect(inv.typed == 2 && inv.status == .nearest && inv.achievedSigmaPx == 1.6)
        #expect(abs((SemanticsMath.inverse(law, sigmaPx: 1.2, unitScale: 1).typed ?? 0) - 1.5) < 1e-12)
        #expect(SemanticsMath.inverse(law, sigmaPx: 3, unitScale: 1).typed == 3)
    }
}

@Suite struct SEMANTICS_RadiusMeanings {
    @Test func radiusTenAtScaleOneIsStackSection8() {
        let rows = ToolConventions.radiusMeanings(typed: 10, displayScale: 1)
        #expect(rows.count >= 16)
        let sigmas = rows.compactMap(\.sigma.value)
        #expect(sigmas.count == rows.count && sigmas == sigmas.sorted(by: >), "sorted by σ, largest first")
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let expected: [(String, String)] = [("css", "10.0"), ("coreimage", "10.0"), ("gimp", "10.0"), ("sketch", "10.0"), ("swiftui", "9.00"),
                                            ("svg-three-box", "9.49"), ("impeller", "7.51"), ("android", "6.27"), ("box-radius", "6.06"),
                                            ("android-window", "5.77"), ("box-shadow", "5.00"), ("figma", "5.00"), ("calayer", "5.00"),
                                            ("calayer-alt", "9.00"), ("disc", "5.00"), ("tent", "4.47"), ("hwui-legacy", "3.60"),
                                            ("opencv-ksize", "3.50"), ("three-sigma", "3.33"), ("gimp-2.8", "3.30"), ("ciboxblur", "2.58"),
                                            ("imagemagick-bare", "1.00")]
        for (id, text) in expected { #expect(byID[id]?.sigma.text == text, "\(id): \(byID[id]?.sigma.text ?? "missing")") }
        let edges: [(String, String)] = [("css", "25.6"), ("box-radius", "16.8"), ("disc", "13.7"), ("tent", "12.2"), ("ciboxblur", "7.20"),
                                         ("box-shadow", "12.8"), ("android", "16.1"), ("svg-three-box", "24.9")]   // STACK rounds 24.95 to 25.0
        for (id, text) in edges { #expect(byID[id]?.edgeWidth.text == text, "\(id) edge: \(byID[id]?.edgeWidth.text ?? "missing")") }
        #expect(byID["swiftui"]?.sigma.qualifiers.contains(.offscreen) == true)
        #expect(byID["swiftui"]?.edgeWidth.provenance == .modeled, "the box-cubed edge is a model")
        #expect(byID["calayer"]?.sigma.qualifiers.contains(.sourcesDisagree) == true)
        #expect(byID["calayer-alt"]?.edgeWidth.provenance == .modeled && byID["calayer-alt"]?.kernel == "tent-like")
        for r in rows {
            #expect(r.sigma.honestyViolations.isEmpty && r.edgeWidth.honestyViolations.isEmpty, "\(r.id)")
            #expect(!SEMANTICS_Fixture.hasDigits(r.label) || r.label == "GIMP 2.8", "\(r.id) label")
        }
        let spread = (sigmas.first ?? 0) / max(sigmas.last ?? 1, 1e-9)
        #expect(abs(spread - 10) < 1e-9, "a factor of ten in σ for the same typed number")
    }

    @Test func radiusTenOnThisPhone() {
        let rows = ToolConventions.radiusMeanings(typed: 10, displayScale: 3)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        #expect(byID["css"]?.sigma.text == "30.0" && byID["swiftui"]?.sigma.text == "27.0" && byID["coreimage"]?.sigma.text == "10.0")
        let law = SEMANTICS_Fixture.phoneLaw(.swiftUIBlur, small: 0.98, large: 0.91, switchAt: 1.8)
        let measured = Dictionary(uniqueKeysWithValues: ToolConventions.radiusMeanings(typed: 10, displayScale: 3, measuredLaws: [law]).map { ($0.id, $0) })
        #expect(measured["swiftui"]?.sigma.text == "27.3" && measured["swiftui"]?.sigma.device == SEMANTICS_Fixture.phone)
    }
}

