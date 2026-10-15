import Foundation
import Testing
@testable import BlurCore

// OWNER: SEMANTICS. SPEC §5.3 A floor 1 (σ 4 px at display scale 3), the SwiftUI law, P27 drop-shadow conventions,
// reverse mode and "not offered" — the CORE acceptance of ARCHITECTURE §8.2 SEMANTICS.

enum SEMANTICS_Fixture {
    static let tools = ToolConventions()
    static func typed(_ tool: String, _ blur: BlurID = "gaussian-blur", sigma: Double = 4, scale: Double = 3,
                      law: CalibrationLaw? = nil) -> BadgedValue {
        tools.typedValue(toolID: tool, blur: blur, sigmaPx: sigma, displayScale: scale, measuredLaw: law)
    }
    static func reverse(_ tool: String, _ blur: BlurID = "gaussian-blur", typed: Double = 10, scale: Double = 1,
                        law: CalibrationLaw? = nil) -> BadgedValue {
        tools.sigmaPx(toolID: tool, blur: blur, typed: typed, displayScale: scale, measuredLaw: law)
    }
    static let phone = DeviceStamp(deviceModel: "iPhone 15 Pro Max", gpuName: "Apple A17 Pro GPU", gpuFamily: "Apple9", osVersion: "iOS 27.0",
                                   osBuild: "24A5355p", isSimulator: false, date: Date(timeIntervalSince1970: 1_791_979_200),
                                   thermal: .nominal, lowPowerMode: false)
    static func phoneLaw(_ subject: CalibrationSubject, small: Double? = nil, large: Double, switchAt: Double? = nil,
                         device: DeviceStamp = phone) -> CalibrationLaw {
        CalibrationLaw(subject: subject, smallRatio: small, largeRatio: large, switchParameter: switchAt,
                       points: [CalibrationPoint(parameter: 1, sigmaPx: 3, centreSpreadPx: 0)], device: device)
    }
    static func hasDigits(_ s: String) -> Bool { s.contains(where: \.isNumber) }
}

@Suite struct SEMANTICS_FloorOneFixture {
    typealias F = SEMANTICS_Fixture

    @Test func swiftUISmallRegimeIsOnePointThirtyThree() {
        let v = F.typed("swiftui")
        #expect(v.text == "1.33" && v.unit == "pt")
        #expect(abs((v.value ?? 0) - 4.0 / 3) < 1e-9)
        #expect(v.provenance == .measured && v.device == SemanticsCatalog.researchMac)
        #expect(v.qualifiers.contains(.offscreen) && v.qualifiers.contains(.notThisDevice))
        #expect((v.caption ?? "").contains("OFFSCREEN") && v.spoken.contains("offscreen"))
        #expect(!v.text.hasPrefix("≈"), "below the switch SwiftUI is a sampled Gaussian: not σ-only")
        #expect(v.honestyViolations.isEmpty, "\(v.honestyViolations)")
    }

    @Test func cssIsOnePointThirtyThreeCSSPixels() {
        let v = F.typed("css")
        #expect(v.text == "1.33" && v.unit == "CSS px" && v.provenance == .reference && v.source != nil)
        #expect(v.honestyViolations.isEmpty)
    }

    @Test func figmaIsTwoPointSixSevenInferred() {
        let v = F.typed("figma")
        #expect(v.text == "2.67" && v.provenance == .inferred)
        #expect(v.honestyViolations.isEmpty)
    }

    @Test func coreImageAndMPSAreFourMeasured() {
        for tool in ["coreimage", "mps"] {
            let v = F.typed(tool)
            #expect(v.value == 4 && v.text == "4.00" && v.unit == "px", "\(tool)")
            #expect(v.provenance == .measured && v.device != nil && v.qualifiers.contains(.notThisDevice), "\(tool)")
            #expect(v.honestyViolations.isEmpty, "\(tool)")
        }
    }

    @Test func androidIsSixPointZeroSixReference() {
        let v = F.typed("android")
        #expect(v.text == "6.06" && v.provenance == .reference && v.source != nil)
        #expect(abs((v.value ?? 0) - (4 - 0.5) / 0.57735) < 1e-9)
    }

    @Test func gimp28IsTwelvePointThreeAndGimp210IsSigma() {
        let old = F.typed("gimp-2.8")
        #expect(old.text == "12.3" && old.provenance == .reference)
        #expect(abs((old.value ?? 0) - (4 * 3.3290429691 - 1)) < 1e-6)
        let new = F.typed("gimp")
        #expect(new.value == 4 && new.provenance == .reference)
    }

    @Test func imageMagickTypesZeroXFour() {
        let v = F.typed("imagemagick")
        #expect(v.value == 4 && v.provenance == .reference)
    }

    @Test func photoshopIsUnverifiedWithNoNumber() {
        let v = F.typed("photoshop")
        #expect(v.value == nil && v.text == "UNVERIFIED" && v.qualifiers.contains(.unverified))
        #expect(!F.hasDigits(v.text) && !F.hasDigits(v.spoken))
        #expect(v.provenance == nil && v.source != nil)
        #expect(v.honestyViolations.isEmpty)
        let chip = ToolConventions.slideChipValue(toolID: "photoshop", blur: "gaussian-blur", sigmaPx: 4, displayScale: 3, measuredLaw: nil)
        #expect(chip.text == "UNVER." && chip.value == nil && chip.honestyViolations.isEmpty)
        for tool in ["aftereffects", "affinity"] {
            let w = F.typed(tool)
            #expect(w.value == nil && w.text == "UNVERIFIED", "\(tool)")
        }
    }

    @Test func floorOneBarsPutTheHomeToolFirst() {
        let bars = ToolConventions.toolBars(blur: "gaussian-blur", sigmaPx: 4, displayScale: 3, homeToolID: "figma")
        #expect(bars.rows.first?.id == "figma" && bars.homeToolID == "figma" && !bars.reverseMode)
        let ids = bars.rows.map(\.id)
        for t in ["swiftui", "css", "coreimage", "mps", "android", "gimp-2.8", "photoshop"] { #expect(ids.contains(t), "\(t)") }
        #expect(!ids.contains("vimage"), "vImage has no Gaussian convenience")
        for row in bars.rows { #expect(row.value.honestyViolations.isEmpty, "\(row.id): \(row.value.honestyViolations)") }
        let numbers = ToolConventions.primaryNumbers(bars)
        #expect(numbers.count <= 6 && numbers.count >= 4 && numbers.first?.id == "figma")
    }
}

@Suite struct SEMANTICS_SwiftUILaw {
    typealias F = SEMANTICS_Fixture

    @Test func benchDefaultSigma12IsAboutFourPointFour() {
        let v = F.typed("swiftui", sigma: 12)
        #expect(v.text == "≈4.44" && abs((v.value ?? 0) - 12 / 2.7) < 1e-9)
        #expect((v.caption ?? "").contains("SAME σ, DIFFERENT KERNEL") && (v.caption ?? "").contains("OFFSCREEN"))
        #expect(v.spoken.hasPrefix("about 4.44 points in SwiftUI") && v.spoken.contains("sigma-matched; SwiftUI's kernel shape differs"))
        let chip = ToolConventions.slideChipValue(toolID: "swiftui", blur: "gaussian-blur", sigmaPx: 12, displayScale: 3, measuredLaw: nil)
        #expect(chip.text == "≈4.4" && chip.text.count <= 6 && chip.qualifiers.contains(.offscreen))
        #expect(chip.spoken.hasPrefix("about 4.4 points"))
        #expect(chip.honestyViolations.isEmpty)
    }

    @Test func switchIsFivePixelsSoOnePointSevenPoints() {
        let law = ToolConventions.macSwiftUIBlurLaw(displayScale: 3)
        #expect(abs((law.switchParameter ?? 0) - 5.0 / 3) < 1e-12 && law.largeRatio == 0.90 && law.smallRatio == 1.0)
        let stop = ToolConventions.swiftUISwitchRadius(displayScale: 3, measuredLaw: nil)
        #expect(stop.text == "1.7" && stop.provenance == .measured && stop.qualifiers.contains(.offscreen) && stop.qualifiers.contains(.notThisDevice))
        #expect(stop.honestyViolations.isEmpty)
        // σ exactly at the switch stays in the small regime; just above uses 0.90.
        #expect(ToolConventions.swiftUIRadiusPt(sigmaPx: 5, displayScale: 3, measuredLaw: nil).typed == 5.0 / 3)
        #expect(abs((ToolConventions.swiftUIRadiusPt(sigmaPx: 6, displayScale: 3, measuredLaw: nil).typed ?? 0) - 6 / 2.7) < 1e-12)
    }

    @Test func sigmaHoldRoundTrips() {
        for s in [0.5, 1, 2, 4, 4.8, 5, 5.2, 8, 12, 30, 90] {
            let r = ToolConventions.swiftUIRadiusPt(sigmaPx: s, displayScale: 3, measuredLaw: nil)
            #expect(r.status == .exact, "σ \(s)")
            #expect(abs(ToolConventions.swiftUISigmaPx(radiusPt: r.typed ?? -1, displayScale: 3, measuredLaw: nil) - s) < 1e-9, "σ \(s)")
        }
    }

    @Test func phoneLawReplacesTheMacLaw() {
        let law = F.phoneLaw(.swiftUIBlur, small: 0.98, large: 0.91, switchAt: 1.8)
        let v = F.typed("swiftui", sigma: 12, law: law)
        #expect(abs((v.value ?? 0) - 12 / (0.91 * 3)) < 1e-9 && v.text == "≈4.40")
        #expect(v.provenance == .measured && v.device == F.phone)
        #expect(v.qualifiers.contains(.offscreen) && !v.qualifiers.contains(.notThisDevice))
        #expect((v.caption ?? "").contains("OFFSCREEN") && !(v.caption ?? "").contains("NOT THIS PHONE"))
        #expect(v.spoken.contains("measured on iPhone 15 Pro Max") && v.spoken.contains("offscreen"))
        #expect(v.honestyViolations.isEmpty)
        let small = F.typed("swiftui", sigma: 4, law: law)
        #expect(abs((small.value ?? 0) - 4 / (0.98 * 3)) < 1e-9 && !small.text.hasPrefix("≈"))
        let stop = ToolConventions.swiftUISwitchRadius(displayScale: 3, measuredLaw: law)
        #expect(stop.text == "1.8" && !stop.qualifiers.contains(.notThisDevice) && stop.device == F.phone)
        // A law for another subject leaves SwiftUI on the Mac law.
        let other = F.typed("swiftui", sigma: 12, law: F.phoneLaw(.ciGaussianBlur, large: 1.0))
        #expect(other.device == SemanticsCatalog.researchMac && other.text == "≈4.44")
    }

    @Test func simulatorLawIsFlagged() {
        var sim = F.phone; sim.isSimulator = true
        let v = F.typed("swiftui", sigma: 12, law: F.phoneLaw(.swiftUIBlur, small: 1, large: 0.9, switchAt: 1.67, device: sim))
        #expect(v.qualifiers.contains(.simulator) && (v.caption ?? "").contains("SIMULATOR") && v.honestyViolations.isEmpty)
    }

    @Test func swiftUILayerBlurIsTheSameKernel() {
        let v = F.typed("swiftui", "swiftui-layer-blur", sigma: 12)
        #expect(v.text == "4.44" && v.qualifiers.contains(.offscreen))
    }
}

@Suite struct SEMANTICS_ShadowConventionsP27 {
    typealias F = SEMANTICS_Fixture

    @Test func theSameTenInEveryShadowConvention() {
        let box = F.reverse("css-box-shadow", "drop-shadow")
        #expect(box.value == 5 && box.text == "5.00" && box.provenance == .reference)
        let drop = F.reverse("css-drop-shadow", "drop-shadow")
        #expect(drop.value == 10 && drop.provenance == .reference)
        let figma = F.reverse("figma-shadow", "drop-shadow")
        #expect(figma.text == "4.40" && figma.provenance == .reference && figma.qualifiers.contains(.weakSource))
        #expect(figma.caption == "THIRD-PARTY MEASUREMENT")
        let cg = F.reverse("cgcontext-shadow", "drop-shadow")
        #expect(cg.text == "4.50" && cg.provenance == .measured && cg.device != nil)
        let swiftUI = F.reverse("swiftui-shadow", "drop-shadow")
        #expect(swiftUI.text == "9.60" && swiftUI.qualifiers.contains(.offscreen) && (swiftUI.caption ?? "").contains("OFFSCREEN"))
        #expect(F.reverse("sketch-shadow", "drop-shadow").text == "4.80")
        #expect(F.reverse("photoshop-shadow", "drop-shadow").text == "4.40")
        #expect(F.reverse("flutter", "drop-shadow").text == "6.27")
        for v in [box, drop, figma, cg, swiftUI] { #expect(v.honestyViolations.isEmpty, "\(v.text): \(v.honestyViolations)") }
    }

    @Test func caLayerSourcesDisagree() {
        let rs = ToolConventions.reverseReadings(toolID: "calayer-shadow", blur: "drop-shadow", typed: 10, displayScale: 1, measuredLaw: nil)
        #expect(rs.count == 2)
        #expect(rs[0].value.value == 5 && rs[1].value.text == "9.00")
        for r in rs {
            #expect(r.value.qualifiers.contains(.sourcesDisagree) && (r.value.caption ?? "").contains("SOURCES DISAGREE"))
            #expect(r.value.provenance == .measured && r.value.device == SemanticsCatalog.researchMac)
            #expect(r.value.honestyViolations.isEmpty)
        }
        // The protocol answer is the first reading (σ = r/2, the law P27 renders), still flagged.
        let first = F.reverse("calayer-shadow", "drop-shadow")
        #expect(first.value == 5 && first.qualifiers.contains(.sourcesDisagree))
        // Forward: σ 5 px → typed 10 by STACK, ≈ 5.56 by CAL.
        let fw = ToolConventions.readings(toolID: "calayer-shadow", blur: "drop-shadow", sigmaPx: 5, displayScale: 1, measuredLaw: nil)
        #expect(fw.count == 2 && fw[0].value.text == "10.0" && fw[1].value.text == "5.56")
    }

    @Test func aPhoneMeasurementSettlesCALayer() {
        let law = F.phoneLaw(.caLayerShadow, large: 0.88)
        let rs = ToolConventions.reverseReadings(toolID: "calayer-shadow", blur: "drop-shadow", typed: 10, displayScale: 3, measuredLaw: law)
        #expect(rs.count == 1 && abs((rs[0].value.value ?? 0) - 26.4) < 1e-9)
        #expect(!rs[0].value.qualifiers.contains(.sourcesDisagree) && rs[0].value.device == F.phone)
        #expect(!(rs[0].value.caption ?? "").contains("SOURCES DISAGREE"))
    }

    @Test func conventionMenuOrder() {
        #expect(ToolConventions.shadowConventions.map(\.id) == ["css-box-shadow", "css-drop-shadow", "calayer-shadow", "cgcontext-shadow",
                                                                  "swiftui-shadow", "figma-shadow", "sketch-shadow", "photoshop-shadow"])
        for id in SemanticsCatalog.shadowConventionIDs {
            #expect(ToolConventions.offers(toolID: id, blur: "drop-shadow"), "\(id)")
            #expect(!ToolConventions.offers(toolID: id, blur: "gaussian-blur"), "\(id)")
        }
    }

    @Test func dropShadowBarsCarryBothCALayerRows() {
        let bars = ToolConventions.toolBars(blur: "drop-shadow", sigmaPx: 15, displayScale: 3, homeToolID: "swiftui")
        let ids = bars.rows.map(\.id)
        #expect(ids.first == "swiftui" && !ids.contains("swiftui-shadow"))
        #expect(ids.contains("calayer-shadow") && ids.contains("calayer-shadow-alt") && ids.contains("css-box-shadow"))
        let box = bars.rows.first { $0.id == "css-box-shadow" }?.value
        #expect(box?.text == "10.0", "σ 15 px at scale 3 is a CSS box-shadow blur of 10")
    }
}

@Suite struct SEMANTICS_NotOffered {
    typealias F = SEMANTICS_Fixture

    @Test func swiftUIHasNoBoxBlur() {
        let v = F.typed("swiftui", "box-blur")
        #expect(v.text == "—" && v.value == nil && v.provenance == nil)
        #expect(v.caption == "NOT IN SWIFTUI" && v.spoken == "not offered in SwiftUI")
        #expect(v.honestyViolations.isEmpty)
        let chip = ToolConventions.slideChipValue(toolID: "swiftui", blur: "box-blur", sigmaPx: 4, displayScale: 3, measuredLaw: nil)
        #expect(chip.text == "—")
        #expect(!F.tools.offers(toolID: "swiftui", blur: "box-blur") && F.tools.offers(toolID: "coreimage", blur: "box-blur"))
        #expect(ToolConventions.notInToolCaption(toolID: "swiftui") == "NOT IN SWIFTUI")
        let reverse = F.reverse("swiftui", "box-blur")
        #expect(reverse.text == "—" && reverse.value == nil)
    }

    @Test func unknownToolIsUnverified() {
        let v = F.typed("not-a-tool")
        #expect(v.value == nil && v.qualifiers.contains(.unverified) && v.honestyViolations.isEmpty)
    }

    @Test func textbookBlursLiveNowhere() {
        for blur: BlurID in ["exponential-blur", "lorentzian-blur", "heat-equation", "kuwahara"] {
            for tool in SemanticsCatalog.homeToolIDs { #expect(F.typed(tool, blur).text == "—", "\(tool) \(blur)") }
            let facts = ToolConventions.slideFloorFacts(blur: blur, sigmaPx: 4, displayScale: 3, homeToolID: "swiftui")
            #expect(facts.emptyReason != nil)
        }
    }

    @Test func blursWithoutSigmaSayWhy() {
        let material = F.typed("swiftui", "apple-uiblureffect")
        #expect(material.value == nil && material.text == "STYLE, NO RADIUS" && material.provenance == .reference && material.source != nil)
        let chip = ToolConventions.slideChipValue(toolID: "swiftui", blur: "liquid-glass", sigmaPx: nil, displayScale: 3, measuredLaw: nil)
        #expect(chip.text == "STYLE" && chip.text.count <= 6)
        let median = ToolConventions.slideChipValue(toolID: "coreimage", blur: "median", sigmaPx: nil, displayScale: 3, measuredLaw: nil)
        #expect(median.text == "FIXED" && median.honestyViolations.isEmpty)
        let noSigma = ToolConventions.slideChipValue(toolID: "coreimage", blur: "gaussian-blur", sigmaPx: nil, displayScale: 3, measuredLaw: nil)
        #expect(noSigma.text == "NO σ" && noSigma.value == nil)
        let zoom = F.typed("coreimage", "radial-zoom-blur")
        #expect(zoom.text == "UNVERIFIED" && zoom.qualifiers.contains(.sourcesDisagree) && zoom.caption == "SOURCES DISAGREE")
    }
}

@Suite struct SEMANTICS_ReverseMode {
    typealias F = SEMANTICS_Fixture

    @Test func youTypedTenAtScaleOne() {
        #expect(F.reverse("css").text == "10.0")
        #expect(F.reverse("swiftui").text == "9.00")
        #expect(F.reverse("android").text == "6.27")
        #expect(F.reverse("gimp-2.8").text == "3.30")
        #expect(F.reverse("coreimage", "box-blur").text == "2.58")
        #expect(F.reverse("coreimage", "disc-blur").text == "5.00")
        #expect(F.reverse("mps", "box-blur", typed: 21).text == "6.06")
        #expect(F.reverse("mps", "tent-blur", typed: 21).text == "4.47")
        #expect(F.reverse("imagemagick").text == "10.0")
        #expect(F.reverse("figma").text == "5.00")
        let odd = F.reverse("mps", "box-blur", typed: 10)
        #expect(odd.value == nil && odd.text == "ODD WIDTHS ONLY" && odd.honestyViolations.isEmpty)
    }

    @Test func youTypedTenOnThisPhone() {
        #expect(F.reverse("css", scale: 3).text == "30.0")
        let s = F.reverse("swiftui", scale: 3)
        #expect(s.text == "27.0" && s.qualifiers.contains(.offscreen) && (s.caption ?? "").contains("BOX-CUBED-LIKE"))
        #expect(F.reverse("coreimage", scale: 3).text == "10.0", "Core Image radius is in image pixels")
        let bars = ToolConventions.reverseToolBars(blur: "gaussian-blur", typed: 10, displayScale: 3, homeToolID: "swiftui")
        #expect(bars.reverseMode && bars.rows.first?.value.text == "27.0")
    }

    @Test func forwardThenReverseRoundTrips() {
        for c in SemanticsCatalog.controls where c.isOfferedWithLaw {
            for sigma in [0.8, 2.0, 4.0, 12.0, 40.0] {
                for scale in [1.0, 3.0] {
                    let typed = F.typed(c.toolID, c.blur, sigma: sigma, scale: scale)
                    guard let t = typed.value else { continue }
                    let back = F.reverse(c.toolID, c.blur, typed: t, scale: scale)
                    guard let b = back.value else { Issue.record("\(c.id) σ \(sigma): no reverse value"); continue }
                    let nearest = (typed.caption ?? "").contains("NEAREST")
                    #expect(nearest || abs(b - sigma) < 1e-6 * max(1, sigma), "\(c.id) σ \(sigma) scale \(scale): \(b)")
                    if nearest { #expect(abs(b - sigma) / sigma < 0.35, "\(c.id) σ \(sigma): nearest \(b)") }
                }
            }
        }
    }

    @Test func measuredLawsNeedASweep() {
        let fit = PSFFit(sigmaPx: 3, sigmaPerParameterPixel: 1, lsqSigmaPx: 3, excessKurtosis: 0, excessKurtosis45: nil, extentPx: 8,
                         supportPx: 9, centreSpreadPx: 0, sigmaSpreadPercent: 0, encodedMidpoint: nil, shapeName: "gaussian", models: [], lsf: [])
        let one = CalibrationResult(request: CalibrationRequest(subject: .swiftUIBlur, path: .imageRendererCGImage, parameter: 1, displayScale: 3),
                                    fit: fit, device: F.phone, durationMilliseconds: 4)
        #expect(ToolConventions.measuredLaws(from: [one, one]).isEmpty, "fewer than three results: the Mac law stays")
    }

    @Test func unitChainForSwiftUI() {
        guard let line = ToolConventions.unitChain(toolID: "swiftui", blur: "gaussian-blur", typed: 4, displayScale: 3, measuredLaw: nil) else {
            Issue.record("no chain"); return
        }
        #expect(line.text == "4.00 pt × 3 = 12.0 px → σ 10.8 px")
        #expect(line.honestyViolations.isEmpty, "\(line.honestyViolations)")
        #expect(line.values.first?.isInput == true && line.values.last?.qualifiers.contains(.offscreen) == true)
        #expect(line.values.last?.spoken.hasPrefix("10.8 pixels, measured on Mac (Apple M1 Max), offscreen") == true, "\(line.spoken)")
        let ci = ToolConventions.unitChain(toolID: "coreimage", blur: "gaussian-blur", typed: 4, displayScale: 3, measuredLaw: nil)
        #expect(ci?.text == "4.00 px → σ 4.00 px")
        #expect(ToolConventions.unitChain(toolID: "photoshop", blur: "gaussian-blur", typed: 4, displayScale: 3, measuredLaw: nil) == nil)
    }
}
