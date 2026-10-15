import Foundation
@testable import BlurCore

// OWNER: CONTENT-VIEWS. GENERATED MIRROR of App/Content/ContentFixtures.swift (namespace renamed) so `core-test --area CONTENTVIEWS` covers the
// app's pure content logic on the Mac. Do not edit here: edit the App file and regenerate; CONTENTVIEWS_MirrorDrift
// fails when the two copies differ.

// BEGIN MIRRORED
public enum CONTENTVIEWS_Fixtures {

    /// One gallery entry: the page and a context line that says which set-up it shows.
    public struct Item: Sendable, Hashable, Identifiable {
        public var id: String
        public var context: BadgedLine
        public var page: FloorPage
    }

    /// Every fixture page, in gallery order (built once; pure and deterministic).
    public static let items: [Item] = [
        gaussianSlide(), gaussianAPI(), swiftUISweep(), gaussianMath(), boxMath(), hexagonMath(), medianMath(),
        gaussianKernel(), discKernel(), zoomKernel(), gaussianAlgorithm(), dualKawaseAlgorithm(), gaussianGPU(), zoomGPU(),
        gaussianPixels(),
    ]

    public static func item(_ id: String) -> Item? { items.first { $0.id == id } }

    // MARK: - Shared set-up (SPEC §5.3 A: step edges, probe (446, 300), σ 4.0 px, k 3, sampled, clamp, linear light)

    static let sigma = 4.0
    static let kernel = KernelMath.gaussianSampled(sigma: 4)                      // 25 taps, r = 12
    static let probeX = 446, probeY = 300, edgeX = 447                            // IN = 1 for x ≥ 447

    /// The Mac the research measured on (research/live-calibration.md §4: macOS 27.2 (26B5101f), MacBookPro18,2).
    static let researchMac: DeviceStamp = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 4, minute: 8, second: 34)) ?? Date(timeIntervalSince1970: 0)
        return DeviceStamp(deviceModel: "Mac (Apple M1 Max)", gpuName: "Apple M1 Max", gpuFamily: "Apple7", osVersion: "macOS 27.2",
                           osBuild: "26B5101f", isSimulator: false, date: date, thermal: .nominal, lowPowerMode: false)
    }()

    static let px1 = NumberStyle.decimals(1, unit: "px", spokenUnit: "pixels")
    static let px2 = NumberStyle.decimals(2, unit: "px", spokenUnit: "pixels")
    static let pt2 = NumberStyle.decimals(2, unit: "pt", spokenUnit: "points")
    static let cpx = NumberStyle.decimals(4, unit: "c/px", spokenUnit: "cycles per pixel")
    static let percent3 = NumberStyle.decimals(3, unit: "%", spokenUnit: "percent")

    static func row(_ id: String, _ label: String, _ value: BadgedValue) -> LabeledValue { LabeledValue(id: id, label: label, value: value) }

    static func page(_ floor: Floor, _ signature: String, badges: [Provenance], rule: String?, figure: FigureSpec?,
                     numbers: [LabeledValue], details: [ContentBlock], tabs: [FloorTab]? = nil, inThisApp: String,
                     empty: String? = nil) -> FloorPage {
        FloorPage(floor: floor, eyebrow: floor.eyebrow, question: floor.question, signature: signature, dominantBadges: badges,
                  governingRule: rule, figure: figure, numbers: numbers, details: details, tabs: tabs, inThisApp: inThisApp,
                  emptyState: empty)
    }

    static func context(_ words: String, sigma: Double? = nil, unit: String = "px", tail: String? = nil) -> BadgedLine {
        var segments: [BadgedSegment] = [.text(words)]
        if let sigma {
            segments.append(.value(.input(sigma, NumberStyle.decimals(1, unit: unit, spokenUnit: unit == "px" ? "pixels" : "points"))))
        }
        if let tail { segments.append(.text(tail)) }
        return BadgedLine(segments)
    }

    // Catalog signatures (research/CATALOG.md §2, with the SPEC §17 vocabulary fixes: "minimum response", not "MTF").
    static let gaussianSignature = "The only blur that is both round and separable; its continuous response fades every detail smoothly and never inverts phase."
    static let boxSignature = "The honest average: flat and square, and it turns fine stripes inside out (minimum response −0.217)."
    static let discSignature = "Every point becomes a flat coin with a hard rim; between its circular zero rings detail comes back inverted (minimum response −0.132)."
    static let hexagonSignature = "A hexagon is three rhombi and a rhombus is two line blurs: four 1-D passes buy aperture-shaped highlights, but only for shapes with parallel opposite sides."
    static let zoomSignature = "Everything streaks toward one point and the streak grows with distance; in log-polar space it is an ordinary 1-D box."
    static let dualKawaseSignature = "Shrink and blur a little, grow and blur a little: a huge glow for about 12 fetches per pixel, slightly flat-topped and slightly shimmery."
    static let medianSignature = "It votes instead of averaging: a lone bright pixel loses the vote and vanishes, while an edge wins on both sides and stays sharp."
    static let swiftUISignature = "Apple calls it Gaussian; measured, it is a true Gaussian below ~5 device px and a cheaper box³-like resampled blur above, with σ ≈ 0.90·r."

    /// The catalog signatures the fixtures quote (FloorSlots reserves the signature slot for the longest of these and the
    /// registry's own).
    public static let catalogSignatures = [gaussianSignature, boxSignature, discSignature, hexagonSignature, zoomSignature,
                                           dualKawaseSignature, medianSignature, swiftUISignature]

    // MARK: - Floor 1 · SLIDE (tool bars)

    static func gaussianSlide() -> Item {
        let macLaw = SourceRef("research/live-calibration.md §4 (macOS 27.2, M1 Max, offscreen)")
        let rows: [LabeledValue] = [
            row("swiftui", "SwiftUI .blur", .number(sigma / 3, pt2, .inferred, qualifiers: .offscreen, caption: "OFFSCREEN · MAC LAW")),
            row("css", "CSS blur()", .number(sigma / 3, NumberStyle.decimals(2, unit: "px", spokenUnit: "CSS pixels"), .reference,
                                         source: SourceRef("W3C Filter Effects Module Level 1, blur()", url: "https://www.w3.org/TR/filter-effects-1/#funcdef-filter-blur"))),
            row("figma", "Figma layer blur", .number(2 * sigma / 3, NumberStyle.decimals(2, unit: "pt", spokenUnit: "points"), .inferred,
                                                caption: "INTERNALS INFERRED")),
            row("coreimage", "CIGaussianBlur", .number(sigma, px1, .measured, qualifiers: .notThisDevice, source: macLaw,
                                                                  device: researchMac, caption: "MEASURED ON A MAC")),
            row("mps", "MPSImageGaussianBlur", .number(sigma, px1, .measured, qualifiers: .notThisDevice, source: macLaw,
                                                            device: researchMac, caption: "MEASURED ON A MAC")),
            row("android", "Android RenderEffect", .number((sigma - 0.5) / 0.57735, px2, .reference,
                                                                  source: SourceRef("Skia SkBlurMask, ConvertRadiusToSigma"))),
            row("gimp", "GIMP legacy blur", .number(sigma * 3.329 - 1, px1, .reference,
                                                          source: SourceRef("GIMP 2.8 gaussian-blur plug-in source"))),
            row("photoshop", "Photoshop Gaussian", .unverified("Photoshop Gaussian radius")),
        ]
        let figure = FigureSpec.toolBars(ToolBarsSpec(rows: rows, homeToolID: "swiftui", reverseMode: false))
        let numbers = [rows[0], rows[1], rows[3], rows[5], rows[7]]
        let details: [ContentBlock] = [
            .table(TableBlock(columns: ["TOOL", "THEIR NUMBER", "WHAT IT MEANS"],
                              rows: [["SwiftUI .blur", "radius r (pt)", "σ ≈ r·scale below the regime switch"],
                                     ["CSS blur()", "σ (CSS px)", "σ = value"],
                                     ["Figma layer blur", "blur value", "σ = value ÷ 2 (inferred)"],
                                     ["Android RenderEffect", "radius r", "σ = 0.57735·r + 0.5"],
                                     ["GIMP legacy blur", "radius r", "σ = (r + 1) ÷ 3.329"],
                                     ["Photoshop Gaussian", "Radius", "unverified"]],
                              caption: "WHAT EACH TOOL CALLS RADIUS", provenance: .reference)),
            .note("SAME σ, DIFFERENT KERNEL · SWIFTUI ABOVE ITS REGIME SWITCH", .inferred),
            .sources([SourceRef("W3C Filter Effects Module Level 1, blur()", url: "https://www.w3.org/TR/filter-effects-1/#funcdef-filter-blur"),
                      macLaw, SourceRef("Skia SkBlurMask, ConvertRadiusToSigma"), SourceRef("GIMP 2.8 gaussian-blur plug-in source")]),
        ]
        return Item(id: "gaussian-slide", context: context("GAUSSIAN · STEP EDGES · σ", sigma: sigma),
                    page: page(.slide, gaussianSignature, badges: [.reference, .measured, .inferred],
                               rule: "σ px = law(typed) × scale,  scale 3 px/pt", figure: figure, numbers: numbers, details: details,
                               inThisApp: "IN THIS APP  Tool laws come from vendor documents (REFERENCE) and from offscreen measurements on a Mac (MEASURED, not on this phone yet); Figma's and Photoshop's internals stay INFERRED or UNVERIFIED."))
    }

    // MARK: - Floor 2 · API (code, and the Calibrate sweep plot)

    static func gaussianAPI() -> Item {
        let code = CodeBlock(language: "swift", text: """
        // Blur2ool's own call: pixels, linear light
        b2ool_gaussian(sigma: 4.0, truncation: 3, edges: .clamp)
        // SwiftUI: radius in points, blended gamma-encoded by default
        Image(.stepEdges).blur(radius: 1.33)
        // Core Image: inputRadius is sigma in pixels
        CIFilter.gaussianBlur(inputRadius: 4.0)
        """, annotations: [2: "sigma in pixels: the unit every floor below uses",
                           4: "points times the display scale gives pixels",
                           6: "measured on a Mac: sigma equals inputRadius"])
        let macLaw = SourceRef("research/live-calibration.md §4.1 (macOS 27.2, M1 Max, offscreen)")
        let numbers = [
            row("sigma", "SIGMA", .number(sigma, px1, .computed)),
            row("space", "COLOUR SPACE", .words("LINEAR LIGHT")),
            row("edges", "EDGES", .words("CLAMP")),
            row("alpha", "ALPHA", .words("PREMULTIPLIED")),
            row("law", "SWIFTUI σ ÷ (r·scale)", .number(0.985, .decimals(3), .measured, qualifiers: [.notThisDevice, .offscreen],
                                                         source: macLaw, device: researchMac, caption: "OFFSCREEN · MAC")),
        ]
        let details: [ContentBlock] = [
            .chips(["LINEAR LIGHT", "CLAMP", "PREMULTIPLIED", "FP32 ACCUMULATE", "RGBA16FLOAT STORE"]),
            .disclosure(title: "Apple twins at this probe", blocks: [
                .table(TableBlock(columns: ["API", "PARAMETER", "BLENDS IN", "EDGES"],
                                  rows: [["CIGaussianBlur", "σ = inputRadius px", "linear light", "transparent unless clamped"],
                                         ["MPSImageGaussianBlur", "σ = sigma px", "stored values", "zero by default"],
                                         ["SwiftUI .blur", "radius pt", "gamma-encoded (nonLinear)", "fades to transparent"]],
                                  caption: "MEASURED OFFSCREEN ON A MAC", provenance: .measured)),
                .paragraph("Same sigma, different pixel: SwiftUI averages gamma-encoded values by default, so a black and white edge lands on a different grey than Blur2ool's linear-light blur."),
            ]),
        ]
        return Item(id: "gaussian-api", context: context("GAUSSIAN · STEP EDGES · σ", sigma: sigma),
                    page: page(.api, gaussianSignature, badges: [.computed, .measured, .reference], rule: "1.33 pt × 3 = 4.0 px",
                               figure: .code(code), numbers: numbers, details: details,
                               inThisApp: "IN THIS APP  The unit chain is COMPUTED; the Apple twins' laws are MEASURED offscreen on a Mac and keep that Mac's label until this phone measures them."))
    }

    static func swiftUISweep() -> Item {
        // research/live-calibration.md §4.1: σ ÷ parameter at r = 1, 2, 4, 8, 16, 32, 64 (scale 1, ImageRenderer.cgImage)
        let radii = [1.0, 2, 4, 8, 16, 32, 64]
        let ratios = [0.994, 1.001, 0.985, 0.906, 0.901, 0.906, 0.901]
        let sigmas = ["0.994", "2.002", "3.940", "7.245", "14.417", "28.982", "57.685"]
        let shapes = ["gaussian", "gaussian", "gaussian", "tent", "box³", "tent", "box³"]
        let plot = PlotSpec(xAxis: PlotAxis(label: "radius r", unit: "pt", range: 0.8...80, logarithmic: true),
                            yAxis: PlotAxis(label: "σ ÷ (r·scale)", range: 0.8...1.05),
                            series: [PlotSeries(name: "macOS 27.2 (M1 Max)", xs: radii, ys: ratios, style: .dashed, role: .reference, provenance: .measured)],
                            markers: [PlotMarker(x: 5, label: "SWITCH ≈ 5 PX", kind: .regimeSwitch, provenance: .inferred)],
                            accessibilitySummary: "SwiftUI blur law measured offscreen on a Mac: sigma over radius stays near 1.00 up to about 5 pixels, then drops to about 0.90 for every larger radius.")
        let source = SourceRef("research/live-calibration.md §4.1")
        let numbers = [
            row("small", "SMALL-RADIUS LAW", .number(1.00, .decimals(2), .measured, qualifiers: [.notThisDevice, .offscreen], source: source,
                                                     device: researchMac, caption: "OFFSCREEN · MAC")),
            row("large", "LARGE-RADIUS LAW", .number(0.90, .decimals(2), .measured, qualifiers: [.notThisDevice, .offscreen], source: source,
                                                     device: researchMac, caption: "OFFSCREEN · MAC")),
            row("switch", "REGIME SWITCH", .number(5, NumberStyle.integer(unit: "px", spokenUnit: "pixels"), .inferred, caption: "BETWEEN MEASURED RADII")),
            row("phone", "THIS PHONE", .notYetMeasured()),
        ]
        let table = TableBlock(columns: ["r · PT", "σ · PX", "σ ÷ r", "SHAPE"],
                               rows: radii.indices.map { i in
                                   [NumberStyle.integer().text(radii[i]), sigmas[i], NumberStyle.decimals(3).text(ratios[i]), shapes[i]]
                               },
                               caption: "MEASURED · macOS 27.2 (M1 Max) · OFFSCREEN", provenance: .measured)
        return Item(id: "swiftui-sweep", context: BadgedLine([.text("SWIFTUI .blur · CALIBRATE SWEEP · STEP EDGE")]),
                    page: page(.api, swiftUISignature, badges: [.measured, .inferred],
                               rule: "σ = 1.00·r·scale below the switch,  σ = 0.90·r·scale above", figure: .plot(plot), numbers: numbers,
                               details: [.table(table), .sources([source])],
                               inThisApp: "IN THIS APP  Every point is MEASURED offscreen on a Mac with ImageRenderer; this phone's points appear filled beside them once Calibrate runs, and the switch stays INFERRED until then."))
    }

    // MARK: - Floor 3 · MATH (signed plots, signed 2-D map, an honest empty state)

    static func gaussianMath() -> Item {
        let nus = (0...100).map { Double($0) * 0.005 }
        let continuous = nus.map { KernelMath.gaussianResponse(sigma: sigma, frequency: $0) }
        let discrete = KernelMath.response(kernel, frequencies: nus)
        let minus3dB = (log(2.0) / 4).squareRoot() / (.pi * sigma)
        let half = (log(2.0) / 2).squareRoot() / (.pi * sigma)
        let plot = PlotSpec(xAxis: PlotAxis(label: "frequency ν", unit: "c/px", range: 0...0.5),
                            yAxis: PlotAxis(label: "H(ν)", normalized: true),
                            series: [PlotSeries(name: "continuous", xs: nus, ys: continuous, style: .solid, role: .reference, provenance: .computed),
                                     PlotSeries(name: "discrete taps", xs: nus, ys: discrete, style: .solid, role: .primary, provenance: .computed)],
                            markers: [PlotMarker(x: minus3dB, label: "−3 dB", kind: .minus3dB, provenance: .computed),
                                      PlotMarker(x: half, label: "HALF", kind: .halfAmplitude, provenance: .computed)],
                            showsZeroLine: true,
                            accessibilitySummary: "Signed frequency response of the Gaussian, falling smoothly from 1 at DC to almost 0 by 0.15 cycles per pixel; the discrete taps dip a hair below zero near Nyquist.")
        let numbers = [
            row("peak", "PEAK", .number(1 / (sigma * (2 * Double.pi).squareRoot()), .decimals(4), .computed)),
            row("fwhm", "FWHM", .number(2 * (2 * log(2.0)).squareRoot() * sigma, px2, .computed)),
            row("half", "HALF-AMPLITUDE", .number(half, cpx, .computed)),
            row("db3", "−3 dB", .number(minus3dB, cpx, .computed)),
            row("edge", "EDGE 10–90 %", .number(2 * 1.2815515655446004 * sigma, px2, .computed)),
            row("minH", "MIN H (TAPS)", .number(discreteMinimum(kernel), .decimals(4), .computed)),
        ]
        let details: [ContentBlock] = [
            .chips(["LINEAR", "LSI", "SEPARABLE", "ISOTROPIC", "SEMIGROUP", "POSITIVE", "H ≥ 0 (CONTINUOUS)", "TRUNCATED: RIPPLE"]),
            .paragraph("Only a Gaussian is both round and separable: a product of a function of x and a function of y that depends only on the distance from the centre must be a Gaussian (the Herschel–Maxwell argument)."),
            .equation("f(x)·f(y) = F(x² + y²)  ⇒  log f is quadratic  ⇒  f is a Gaussian"),
        ]
        return Item(id: "gaussian-math", context: context("GAUSSIAN · STEP EDGES · σ", sigma: sigma),
                    page: page(.math, gaussianSignature, badges: [.computed],
                               rule: "G(x) = e^(−x²/2σ²) ÷ (σ√2π),   H(ν) = e^(−2π²σ²ν²)", figure: .plot(plot), numbers: numbers,
                               details: details,
                               inThisApp: "IN THIS APP  Every number on this page is COMPUTED by BlurCore in Double; the curve labelled discrete taps is the DFT of the weights the GPU receives."))
    }

    static func boxMath() -> Item {
        let box = KernelMath.box(radius: 5)                                     // w = 11
        let nus = (0...200).map { Double($0) * 0.0025 }
        let h = KernelMath.response(box, frequencies: nus)
        let boxSigma = box.sigma                                                // √((w² − 1)/12) = √10
        let gauss = nus.map { KernelMath.gaussianResponse(sigma: boxSigma, frequency: $0) }
        let minIndex = h.indices.min { h[$0] < h[$1] } ?? 0
        let plot = PlotSpec(xAxis: PlotAxis(label: "frequency ν", unit: "c/px", range: 0...0.5),
                            yAxis: PlotAxis(label: "H(ν)", normalized: true),
                            series: [PlotSeries(name: "box w 11", xs: nus, ys: h, style: .solid, role: .primary, provenance: .computed),
                                     PlotSeries(name: "Gaussian, same σ", xs: nus, ys: gauss, style: .dashed, role: .comparisonB, provenance: .computed)],
                            markers: [PlotMarker(x: 1.0 / 11, label: "FIRST ZERO", kind: .firstZero, provenance: .computed),
                                      PlotMarker(x: nus[minIndex], label: "MIN H", kind: .custom, provenance: .computed)],
                            showsZeroLine: true,
                            accessibilitySummary: "Signed response of an 11-tap box: it reaches zero at 0.091 cycles per pixel, then goes negative, inverting stripes, with its deepest lobe near 0.13; the Gaussian of the same sigma never goes negative.")
        let numbers = [
            row("zero", "FIRST ZERO", .number(1.0 / 11, cpx, .computed)),
            row("min", "MIN H", .number(h[minIndex], .decimals(3), .computed)),
            row("at", "MIN H AT", .number(nus[minIndex], cpx, .computed)),
            row("sigma", "σ OF THE BOX", .number(boxSigma, px2, .computed)),
        ]
        var lobeRows: [[String]] = []
        for k in 0..<5 {
            let from: Double = Double(k) / 11, to: Double = Swift.min(0.5, Double(k + 1) / 11)
            let sign: String = k % 2 == 0 ? "positive" : "negative (inverts)"
            lobeRows.append([NumberStyle.integer().text(Double(k)), NumberStyle.decimals(4).text(from), NumberStyle.decimals(4).text(to), sign])
        }
        let lobes = TableBlock(columns: ["LOBE", "FROM · c/px", "TO · c/px", "SIGN"], rows: lobeRows,
                               caption: "LOBES OF sin(πwν) ÷ (w·sin πν)", provenance: .computed)
        return Item(id: "box-math", context: BadgedLine([.text("BOX · WIDTH"), .value(.input(11, .integer(unit: "px", spokenUnit: "pixels"))), .text("· B: GAUSSIAN AT THE SAME σ")]),
                    page: page(.math, boxSignature, badges: [.computed], rule: "H(ν) = sin(πwν) ÷ (w·sin πν),  w = 11",
                               figure: .plot(plot), numbers: numbers,
                               details: [.table(lobes), .note("NEGATIVE LOBES INVERT FINE STRIPES · SHADED AND DASHED", .computed)],
                               inThisApp: "IN THIS APP  Both curves are COMPUTED: the box's response from its own eleven taps, the Gaussian at the same σ from its formula."))
    }

    static func hexagonMath() -> Item {
        let r = 8.0
        let k = hexagonKernel(circumradius: r)
        let n = 41
        let freqs = (0..<n).map { -0.5 + Double($0) / Double(n - 1) }
        var map = [Double](repeating: 0, count: n * n)
        let total = k.sum
        for (j, vy) in freqs.enumerated() {
            for (i, vx) in freqs.enumerated() {
                var acc = 0.0
                for y in 0..<k.height { for x in 0..<k.width {
                    let w = k[x, y]
                    if w == 0 { continue }
                    acc += w * cos(2 * .pi * (vx * Double(x - k.originX) + vy * Double(y - k.originY)))
                } }
                map[j * n + i] = acc / total
            }
        }
        let spec = HeatmapSpec(width: n, height: n, values: map, signed: true, centre: PixelPoint(x: n / 2, y: n / 2),
                               caption: "SIGNED H(νx, νy) · DC AT THE CENTRE · ν FROM −0.5 TO 0.5 c/px", provenance: .computed)
        let numbers = [
            row("area", "AREA", .number(3 * 3.0.squareRoot() / 2 * r * r, NumberStyle.decimals(1, unit: "px²", spokenUnit: "square pixels"), .computed)),
            row("sigma", "σ PER AXIS", .number((5.0 / 24).squareRoot() * r, px2, .computed)),
            row("min", "MIN H", .number(map.min() ?? 0, .decimals(3), .computed)),
            row("taps", "COVERED PIXELS", .number(Double(k.weights.filter { $0 > 0 }.count), .integer(noun: CountNoun("pixel", "pixels")), .computed)),
        ]
        return Item(id: "hexagon-math", context: context("POLYGONAL BOKEH · SIX BLADES · CIRCUMRADIUS", sigma: r),
                    page: page(.math, hexagonSignature, badges: [.computed],
                               rule: "hexagon = 3 rhombi;  rhombus = segment ∗ segment", figure: .heatmap(spec),
                               numbers: numbers,
                               details: [.paragraph("A hexagon's response does not fall off in rings: it decays slowly along six spokes at right angles to its edges, and between them it turns negative, so some stripe directions come back inverted.")],
                               inThisApp: "IN THIS APP  The map is COMPUTED as the DFT of the area-weighted hexagon kernel, at every frequency pair from DC to Nyquist."))
    }

    static func medianMath() -> Item {
        let numbers = [
            row("window", "WINDOW", .number(9, .integer(noun: CountNoun("value", "values")), .computed)),
            row("rank", "RANK KEPT", .number(5, NumberStyle(precision: .decimals(0), unit: "of 9", spokenUnit: "of 9"), .computed)),
        ]
        return Item(id: "median-math", context: BadgedLine([.text("MEDIAN · WINDOW"), .literal("3×3"), .text("· IMPULSE GRID")]),
                    page: page(.math, medianSignature, badges: [.computed], rule: "out = sort(window)[⌊n ÷ 2⌋],  n = 9", figure: nil,
                               numbers: numbers,
                               details: [.paragraph("A rank filter has no frequency response: the same window keeps or deletes a detail depending on its neighbours, so no single curve describes what it does to each frequency.")],
                               inThisApp: "IN THIS APP  The window and the rank are COMPUTED; this floor draws no response because a rank filter has none.",
                               empty: "N/A · RANK"))
    }

    // MARK: - Floor 4 · KERNEL (stems, a 2-D weight map, a PSF field)

    static func gaussianKernel() -> Item {
        let r = kernel.origin
        let stemsX = kernel.weights.indices.map { Double($0 - r) }
        let fine = stride(from: -Double(r), through: Double(r), by: 0.25).map { $0 }
        let curve = fine.map { exp(-$0 * $0 / (2 * sigma * sigma)) / (sigma * (2 * Double.pi).squareRoot()) }
        let plot = PlotSpec(xAxis: PlotAxis(label: "tap offset", unit: "px", range: -13...13), yAxis: PlotAxis(label: "weight"),
                            series: [PlotSeries(name: "continuous", xs: fine, ys: curve, style: .solid, role: .reference, provenance: .computed),
                                     PlotSeries(name: "taps", xs: stemsX, ys: kernel.weights, style: .stems, role: .primary, provenance: .computed)],
                            markers: [PlotMarker(x: -Double(r), label: "−12", kind: .supportBracket), PlotMarker(x: Double(r), label: "+12", kind: .supportBracket)],
                            accessibilitySummary: "25 tap weights from offset minus 12 to plus 12 pixels, peaking at 0.0999 in the centre, drawn over the continuous Gaussian.")
        let nus = (0...100).map { Double($0) * 0.005 }
        let dft = PlotSpec(xAxis: PlotAxis(label: "frequency ν", unit: "c/px", range: 0...0.5), yAxis: PlotAxis(label: "H of the taps", normalized: true),
                           series: [PlotSeries(name: "DFT of the taps", xs: nus, ys: KernelMath.response(kernel, frequencies: nus), style: .solid,
                                               role: .primary, provenance: .computed)],
                           showsZeroLine: true, accessibilitySummary: "Response of the 25 taps: smooth fall from 1 to a minimum of minus 0.0010 near Nyquist.")
        let numbers = [
            row("taps", "TAPS", .number(Double(kernel.tapCount), .integer(noun: CountNoun("per axis", "per axis")), .computed)),
            row("centre", "CENTRE WEIGHT", .number(kernel.weights[r], .decimals(5), .computed)),
            row("cut", "MASS CUT", .number(100 * discreteMassCut(sigma: sigma, radius: r), percent3, .computed, caption: "PER AXIS · DISCRETE")),
            row("sigma", "σ OF KERNEL", .number(kernel.sigma, NumberStyle.decimals(3, unit: "px", spokenUnit: "pixels"), .computed)),
            row("minH", "MIN H (RIPPLE)", .number(discreteMinimum(kernel), .decimals(4), .computed)),
            row("error", "ERROR VS SAMPLED", .number(linearSampledError(kernel, fractionBits: 8), .significant(2), .modeled,
                                                     caption: "PER TAP · EIGHT-BIT FRACTIONS")),
        ]
        let weights = TableBlock(columns: ["k", "w[k]"],
                                 rows: (0...r).map { [NumberStyle(precision: .decimals(0), explicitPlus: false).text(Double($0)),
                                                      NumberStyle.decimals(5).text(kernel.weights[r + $0])] },
                                 caption: "WEIGHTS k = 0 … 12 (SYMMETRIC)", provenance: .computed)
        let discretisations: [LabeledValue] = [
            row("sampled", "σ · SAMPLED", .number(kernel.sigma, NumberStyle.decimals(3, unit: "px"), .computed)),
            row("integrated", "σ · INTEGRATED", .number(KernelMath.gaussianIntegrated(sigma: sigma).sigma, NumberStyle.decimals(3, unit: "px"), .computed)),
            row("lindeberg", "σ · LINDEBERG", .number(KernelMath.gaussianLindeberg(sigma: sigma).sigma, NumberStyle.decimals(3, unit: "px"), .computed)),
        ]
        let details: [ContentBlock] = [
            .table(weights),
            .figure(.plot(dft)),
            .disclosure(title: "Discretisation", blocks: [
                .paragraph("Sampled takes the curve's value at each pixel centre; integrated takes its area over each pixel; Lindeberg's kernel is the exact discrete heat kernel. All three are cut at the same radius and renormalised."),
                .values(discretisations),
            ]),
        ]
        return Item(id: "gaussian-kernel", context: context("GAUSSIAN · STEP EDGES · σ", sigma: sigma),
                    page: page(.kernel, gaussianSignature, badges: [.computed, .modeled],
                               rule: "g[n] = e^(−n²/2σ²) ÷ Σ,   |n| ≤ ⌈3σ⌉ = 12", figure: .plot(plot), numbers: numbers, details: details,
                               inThisApp: "IN THIS APP  Weights are COMPUTED by BlurCore in Double. The linear-sampled variant sends pair weights and offsets, and the hardware rounds each pair's fraction to its sub-texel precision; the error row is MODELED for that rounding."))
    }

    static func discKernel() -> Item {
        let radius = 6.0
        let k = discKernel(radius: radius)
        let peak = k.weights.max() ?? 0
        let spec = HeatmapSpec(width: k.width, height: k.height, values: k.weights, signed: false,
                               centre: PixelPoint(x: k.originX, y: k.originY),
                               caption: "WEIGHT MAP · AREA COVERAGE OF THE DISC", provenance: .computed)
        let numbers = [
            row("taps", "TAPS", .number(Double(k.weights.filter { $0 > 0 }.count), .integer(noun: CountNoun("per pixel", "per pixel")), .computed)),
            row("centre", "CENTRE WEIGHT", .number(peak, .decimals(5), .computed)),
            row("sigma", "σ PER AXIS", .number(k.marginalX.sigma, px2, .computed)),
            row("area", "AREA", .number(Double.pi * radius * radius, NumberStyle.decimals(1, unit: "px²", spokenUnit: "square pixels"), .computed)),
        ]
        return Item(id: "disc-kernel", context: context("DISC · RADIUS", sigma: radius),
                    page: page(.kernel, discSignature, badges: [.computed], rule: "w(x, y) = area(pixel ∩ disc) ÷ πR²,  R = 6 px",
                               figure: .heatmap(spec), numbers: numbers,
                               details: [.note("RIM PIXELS CARRY FRACTIONAL WEIGHT", .computed)],
                               inThisApp: "IN THIS APP  The weights are COMPUTED from the exact overlap of each pixel with the disc, supersampled, and sum to one."))
    }

    static func zoomKernel() -> Item {
        let n = 894, grid = 7, a = 0.10, samples = 32
        let centre = SIMD2(447.5, 447.5)
        var points: [PixelPoint] = [], kernels: [Kernel2D] = []
        for gy in 0..<grid {
            for gx in 0..<grid {
                let p = PixelPoint(x: Int((Double(gx) + 0.5) * Double(n) / Double(grid)), y: Int((Double(gy) + 0.5) * Double(n) / Double(grid)))
                points.append(p)
                kernels.append(zoomLocalPSF(at: p, centre: centre, strength: a, samples: samples))
            }
        }
        let probe = SIMD2(747.5, 460.5) - centre
        let rProbe = (probe * probe).sum().squareRoot()
        let rMax = (2 * 447.0 * 447.0).squareRoot()
        let numbers = [
            row("streak", "STREAK AT PROBE", .number(a * rProbe, px1, .computed)),
            row("sigma", "σ ALONG THE RAY", .number(a * rProbe / 12.0.squareRoot(), px2, .computed)),
            row("spacing", "TAP SPACING", .number(a * rProbe / Double(samples - 1), NumberStyle.decimals(3, unit: "px", spokenUnit: "pixels"), .computed)),
            row("ghost", "GHOST-FREE SAMPLES", .number((a * rMax + 1).rounded(.up), .integer(noun: CountNoun("sample", "samples")), .computed, caption: "AT THE CORNERS")),
            row("corner", "CORNER SPACING", .number(a * rMax / Double(samples - 1), px2, .computed)),
        ]
        return Item(id: "zoom-kernel", context: BadgedLine([.text("ZOOM · STRENGTH"), .value(.input(a, .decimals(2))), .text("· CENTRED ·"), .value(.input(Double(samples), .integer(noun: CountNoun("sample", "samples")))), .text("· STAR")]),
                    page: page(.kernel, zoomSignature, badges: [.computed],
                               rule: "taps at c + (p − c)·s,   s = 1.05 … 0.95 in 32 steps",
                               figure: .psfField(PSFFieldSpec(gridSize: grid, points: points, kernels: kernels)), numbers: numbers,
                               details: [.paragraph("In log-polar coordinates around the centre the streak is an ordinary box along ln r, which is why a star centred on the zoom point survives untouched."),
                                         .equation("ln r′ = ln r + ln s,   ln(1.05 ÷ 0.95) = 0.100")],
                               inThisApp: "IN THIS APP  Each spot is the local PSF COMPUTED from the sample positions the shader uses at that pixel; no single response exists for the whole image."))
    }

    // MARK: - Floor 5 · ALGORITHM (pass tiles, a cost plot, a wrapping row of eight passes)

    static func gaussianAlgorithm() -> Item {
        let table = KernelMath.linearSampledTable(kernel)
        let fetches = Double(table.fetchesPerPass)
        let passes = [PassDescriptor(id: 0, name: "H", kind: .fragment, fetchesPerPixel: fetches, tapsPerPixel: 25, traceable: true,
                                     summary: "horizontal pass, bilinear pairs"),
                      PassDescriptor(id: 1, name: "V", kind: .fragment, fetchesPerPixel: fetches, tapsPerPixel: 25, traceable: true,
                                     summary: "vertical pass, bilinear pairs")]
        let sigmas = [0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32]
        func r(_ s: Double) -> Double { Double(KernelMath.gaussianRadius(sigma: s)) }
        let cost = PlotSpec(xAxis: PlotAxis(label: "σ", unit: "px", range: 0.5...32, logarithmic: true),
                            yAxis: PlotAxis(label: "fetches per pixel", range: 1...1e5, logarithmic: true),
                            series: [PlotSeries(name: "2-D direct", xs: sigmas, ys: sigmas.map { pow(2 * r($0) + 1, 2) }, style: .dotted,
                                                role: .comparisonC, provenance: .computed),
                                     PlotSeries(name: "separable", xs: sigmas, ys: sigmas.map { 2 * (2 * r($0) + 1) }, style: .dashed,
                                                role: .comparisonB, provenance: .computed),
                                     PlotSeries(name: "linear-sampled", xs: sigmas,
                                                ys: sigmas.map { 2 * Double(KernelMath.linearSampledTable(KernelMath.gaussianSampled(sigma: $0)).fetchesPerPass) },
                                                style: .solid, role: .primary, provenance: .computed)],
                            markers: [PlotMarker(x: sigma, label: "σ 4.0", kind: .probe)],
                            accessibilitySummary: "Fetches per pixel against sigma on log axes: 2-D direct grows with the square of sigma, separable and linear-sampled grow linearly, linear-sampled about half of separable.")
        let afterH = outAfterH(x: probeX)
        let numbers = [
            row("passes", "PASSES", .number(2, .integer(noun: CountNoun("pass", "passes")), .computed)),
            row("fetches", "FETCHES PER PIXEL", .number(2 * fetches, .integer(), .computed)),
            row("separable", "SEPARABLE TAPS", .number(50, .integer(), .computed)),
            row("direct", "2-D DIRECT TAPS", .number(625, .integer(), .computed)),
            row("afterH", "PROBE AFTER H", .number(afterH, .decimals(4), .computed, caption: "CPU REFERENCE")),
            row("format", "INTERMEDIATE", .words("RGBA16FLOAT", spoken: "r g b a 16 float", .reference,
                                                 source: SourceRef("ARCHITECTURE.md §4.1, texture formats"))),
        ]
        let passTable = TableBlock(columns: ["PASS", "KIND", "FETCHES", "TAPS"],
                                   rows: passes.map { [$0.name, $0.kind.rawValue, NumberStyle.integer().text($0.fetchesPerPixel), NumberStyle.integer().text($0.tapsPerPixel)] },
                                   caption: "PER PASS · PER OUTPUT PIXEL", provenance: .computed)
        return Item(id: "gaussian-algorithm", context: context("GAUSSIAN · LINEAR-SAMPLED · σ", sigma: sigma),
                    page: page(.algorithm, gaussianSignature, badges: [.computed],
                               rule: "625 taps → 25 + 25 → 13 + 13 bilinear fetches",
                               figure: .pair(.passTiles(PassTilesSpec(passes: passes, timings: [], selected: 0)), .plot(cost)),
                               numbers: numbers, details: [.table(passTable)],
                               inThisApp: "IN THIS APP  Counts are COMPUTED from the pass plan. Per-pass times appear as MEASURED bars only after a settled timing run on this phone; there is none in a fixture."))
    }

    static func dualKawaseAlgorithm() -> Item {
        var passes: [PassDescriptor] = []
        for level in 1...4 {
            passes.append(PassDescriptor(id: level - 1, name: "↓\(level)", kind: .fragment, fetchesPerPixel: 5, tapsPerPixel: 5,
                                         outputScale: pow(0.5, Double(level)), traceable: true, summary: "downsample and blur"))
        }
        for level in stride(from: 4, through: 1, by: -1) {
            passes.append(PassDescriptor(id: passes.count, name: "↑\(level)", kind: .fragment, fetchesPerPixel: 8, tapsPerPixel: 8,
                                         outputScale: pow(0.5, Double(level - 1)), traceable: true, summary: "upsample and blur"))
        }
        let plan = PassPlan(algorithmName: "Dual filtering", passes: passes)
        let numbers = [
            row("passes", "PASSES", .number(Double(passes.count), .integer(noun: CountNoun("pass", "passes")), .computed)),
            row("fetches", "FETCHES PER PIXEL", .number(plan.fetchesPerPixel, .decimals(1), .computed, caption: "ANY BLUR SIZE")),
            row("levels", "LEVELS", .number(4, .integer(), .computed)),
            row("smallest", "SMALLEST LEVEL", .number((894.0 / 16).rounded(.up), NumberStyle.integer(unit: "px", spokenUnit: "pixels"), .computed)),
        ]
        return Item(id: "dual-kawase-algorithm", context: BadgedLine([.text("DUAL KAWASE · FOUR LEVELS · NIGHT CITY")]),
                    page: page(.algorithm, dualKawaseSignature, badges: [.computed],
                               rule: "fetches ≈ 5·(¼ + ¹⁄₁₆ + …) + 8·(… + ¼ + 1) ≈ 12.3 per pixel",
                               figure: .passTiles(PassTilesSpec(passes: passes, timings: [], selected: 4)), numbers: numbers,
                               details: [.paragraph("Each level halves the image, so the deep passes are nearly free; the cost is dominated by the last upsample at full size. Moving the image by one pixel moves the coarse levels by a fraction of a texel, which is the shimmer."),
                                         .note("SHIFT VARIANT · THE PROBE'S PHASE WITHIN THE LEVEL GRID MATTERS", .computed)],
                               inThisApp: "IN THIS APP  Fetch counts are COMPUTED per pass and weighted by each level's share of the window's pixels."))
    }

    // MARK: - Floor 6 · GPU (Shader · Silicon tabs; a tab-less dispatch page)

    /// Lines 5–33 of App/GPU/Shaders/F2Gaussian.metal as of 14 Oct 2026 (FAM-F2's seed), verbatim: the linear-sampled pass.
    static let shaderExcerpt = """
    struct B2F2GaussParams { uint entries; uint width; uint height; uint pad; };

    // Linear-sampled separable Gaussian, one direction per pass (B2_DIRECTION 0 = H, 1 = V).
    // Table from BlurCore KernelMath.linearSampledTable: weights[0] centre, then one bilinear pair per entry.
    // Tap order (binding for traces and CPU reconstructions): centre, +o1, −o1, +o2, −o2, …
    fragment float4 b2_f2_gauss_linear_fs(B2VertexOut in [[stage_in]],
                                          texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]],
                                          constant B2F2GaussParams &P [[buffer(B2_BUF_PARAMS)]],
                                          constant float *weights [[buffer(B2_BUF_WEIGHTS)]],
                                          constant float *offsets [[buffer(B2_BUF_OFFSETS)]],
                                          device B2TraceHeader *trace [[buffer(B2_BUF_TRACE), function_constant(B2_TRACE_PROBE)]]) {
        uint2 pixel = uint2(in.position.xy);
        float2 dir = B2_DIRECTION == 0 ? float2(1.0f, 0.0f) : float2(0.0f, 1.0f);
        float2 centre = float2(pixel) + 0.5f;
        float4 c = b2_sample(src, centre, B2_EDGE_MODE);
        float4 sum = c * weights[0];                                   // @explain: the centre tap
        if (B2_TRACE_PROBE) b2_trace_tap(trace, pixel, centre, weights[0], 0.0f, c, sum, float4(0.0f));
        for (uint i = 1; i < P.entries; ++i) {
            float2 o = dir * offsets[i];
            float4 a = b2_sample(src, centre + o, B2_EDGE_MODE);       // @explain: one bilinear fetch blends two taps
            sum = fma(a, float4(weights[i]), sum);                     // @explain: explicit fma keeps traced = untraced
            if (B2_TRACE_PROBE) b2_trace_tap(trace, pixel, centre + o, weights[i], 0.0f, a, sum, float4(0.0f));
            float4 b = b2_sample(src, centre - o, B2_EDGE_MODE);
            sum = fma(b, float4(weights[i]), sum);
            if (B2_TRACE_PROBE) b2_trace_tap(trace, pixel, centre - o, weights[i], 0.0f, b, sum, float4(0.0f));
        }
        if (B2_TRACE_PROBE) b2_trace_final(trace, pixel, centre, sum);  // @explain: the value this pass stores
        return sum;
    }
    """

    static func gaussianGPU() -> Item {
        let code = CodeBlock(language: "metal", text: shaderExcerpt,
                             annotations: [6: "one fragment per output pixel; the full-screen triangle covers the window"])
        let lines = shaderExcerpt.components(separatedBy: "\n").count
        let shader = FloorTab(id: "shader", title: "Shader", dominantBadges: [.reference], figure: .code(code),
                              numbers: [row("function", "FUNCTION", .words("b2_f2_gauss_linear_fs", spoken: "b 2 f 2 gauss linear f s", .reference,
                                                                           source: SourceRef("App/GPU/Shaders/F2Gaussian.metal"))),
                                        row("math", "MATH MODE", .words("FAST", .reference, source: SourceRef("project.yml MTL_MATH_MODE"))),
                                        row("lines", "LINES SHOWN", .number(Double(lines), .integer(noun: CountNoun("line", "lines")), .computed))],
                              details: [.code(code),
                                        .sources([SourceRef("App/GPU/Shaders/F2Gaussian.metal, lines 5 to 33 (excerpt)")])])
        let dispatch = PassDispatch(passIndex: 0, name: "H", encoder: .compute, functionNames: ["b2_f2_gauss_tile_k"],
                                    threadsPerThreadgroup: [256, 1, 1], threadgroups: [4, 894, 1], staticThreadgroupMemoryBytes: 0,
                                    dynamicThreadgroupMemoryBytes: (256 + 2 * 12) * 8, threadExecutionWidth: 32, pipelineMaxThreads: 1024,
                                    outputSize: .square(894), outputHasShaderWrite: true, modeledBytes: 2 * 894 * 894 * 8)
        let overlay = DispatchOverlaySpec(dispatch: dispatch, apronTexels: 12, probeThreadgroup: [1, 300], probeThreadInGroup: [190, 0],
                                          probeSIMDGroup: 5, probeLane: 30)
        let silicon = FloorTab(id: "silicon", title: "Silicon", dominantBadges: [.computed, .modeled, .reference], figure: .dispatchOverlay(overlay),
                               numbers: [row("groups", "THREADGROUPS", .number(4 * 894, .integer(), .computed, caption: "4 × 894")),
                                         row("threads", "THREADS PER GROUP", .number(256, .integer(), .computed)),
                                         row("thread", "PROBE THREAD", .number(190, .integer(), .computed, caption: "OF THREADGROUP (1, 300)")),
                                         row("lane", "SIMD LANE", .number(30, .integer(), .computed, caption: "SIMD-GROUP 5")),
                                         row("tgmem", "THREADGROUP MEMORY", .number(Double((256 + 2 * 12) * 8), NumberStyle.integer(unit: "B", spokenUnit: "bytes"), .computed,
                                                                                   caption: "DYNAMIC · (TILE + 2r) × 8 B")),
                                         row("bytes", "BYTES MOVED", .number(4 * 894 * 894 * 8 / 1e6, NumberStyle.decimals(1, unit: "MB", spokenUnit: "megabytes"), .modeled,
                                                                            caption: "TWO PASSES · READ ONCE, WRITE ONCE"))],
                               details: [.table(TableBlock(columns: ["PASS", "GRID", "GROUP", "TG MEMORY"],
                                                           rows: [["H", "4 × 894", "256 × 1", "2,240 B"], ["V", "894 × 4", "1 × 256", "2,240 B"]],
                                                           caption: "DISPATCH PER PASS", provenance: .computed)),
                                         .values([row("limit", "THREADGROUP MEMORY LIMIT", .number(32_768, NumberStyle.integer(unit: "B", spokenUnit: "bytes"), .reference,
                                                                                                   source: SourceRef("Apple Metal feature set tables, Apple9")))]),
                                         .note("32 × 32 IS THE APPLE9 MAXIMUM TILE IN APPLE'S TABLES · THE TILE THIS PASS USES IS NOT PUBLISHED", .reference)])
        return Item(id: "gaussian-gpu", context: BadgedLine([.text("GAUSSIAN · COMPUTE TILE · PROBE"), .literal("(446, 300)")]),
                    page: page(.gpu, gaussianSignature, badges: [.reference], rule: "thread = probe − threadgroup × 256,   lane = thread mod 32",
                               figure: nil, numbers: [], details: [], tabs: [shader, silicon],
                               inThisApp: "IN THIS APP  The source is the shipped text (REFERENCE: it is the code); dispatch geometry is COMPUTED; bytes are MODELED; nothing here is timed in a fixture."))
    }

    static func zoomGPU() -> Item {
        let dispatch = PassDispatch(passIndex: 0, name: "GATHER", encoder: .compute, functionNames: ["b2_f5_zoom_k"],
                                    threadsPerThreadgroup: [16, 16, 1], threadgroups: [56, 56, 1], staticThreadgroupMemoryBytes: 0,
                                    dynamicThreadgroupMemoryBytes: 0, threadExecutionWidth: 32, pipelineMaxThreads: 1024,
                                    outputSize: .square(894), outputHasShaderWrite: true, modeledBytes: 894 * 894 * 8 * 2)
        let overlay = DispatchOverlaySpec(dispatch: dispatch, apronTexels: 0, probeThreadgroup: [46, 28], probeThreadInGroup: [11, 12],
                                          probeSIMDGroup: 6, probeLane: 11)
        let numbers = [
            row("groups", "THREADGROUPS", .number(56 * 56, .integer(), .computed, caption: "56 × 56")),
            row("threads", "THREADS PER GROUP", .number(256, .integer(), .computed, caption: "16 × 16")),
            row("surplus", "SURPLUS ROWS AND COLUMNS", .number(2, .integer(), .computed, caption: "RETURN AT THE BOUNDS CHECK")),
            row("thread", "PROBE THREAD", .words("(11, 12)", spoken: "thread 11, 12", .computed, caption: "OF THREADGROUP (46, 28)")),
            row("lane", "SIMD LANE", .number(11, .integer(), .computed, caption: "SIMD-GROUP 6")),
            row("compress", "OUTPUT COMPRESSIBLE", .words("NO · SHADER WRITE", spoken: "no, shader write", .reference,
                                                          source: SourceRef("Apple Tech Talk 111431"))),
        ]
        return Item(id: "zoom-gpu", context: BadgedLine([.text("ZOOM ·"), .literal("16 × 16"), .text("THREADGROUPS · PROBE"), .literal("(747, 460)")]),
                    page: page(.gpu, zoomSignature, badges: [.computed, .reference], rule: "group = ⌊p ÷ 16⌋,   thread = p − 16·group",
                               figure: .dispatchOverlay(overlay), numbers: numbers,
                               details: [.paragraph("Every thread gathers its own samples along its ray; there is no shared tile, so the threads of one group read pixels that can be far apart near the corners.")],
                               inThisApp: "IN THIS APP  Dispatch geometry is COMPUTED from the recorded dispatch; compressibility is REFERENCE from Apple's documentation."))
    }

    // MARK: - Floor 7 · PIXELS (IN | OUT texel grids)

    static func gaussianPixels() -> Item {
        let size = 9, half = size / 2
        let origin = PixelPoint(x: probeX - half, y: probeY - half)
        var input = [Double](repeating: 0, count: size * size), output = input, weights = input
        for j in 0..<size {
            for i in 0..<size {
                let x = origin.x + i
                input[j * size + i] = x >= edgeX ? 1 : 0
                output[j * size + i] = outAfterH(x: x)
                if j == half, abs(x - probeX) <= kernel.origin { weights[j * size + i] = kernel.weights[kernel.origin + x - probeX] }
            }
        }
        let probe = PixelPoint(x: probeX, y: probeY)
        let inGrid = TexelGridSpec(size: size, origin: origin, channel: .luma, values: input, weights: weights, highlighted: [probe], provenance: .computed)
        let outGrid = TexelGridSpec(size: size, origin: origin, channel: .luma, values: output, weights: nil, highlighted: [probe], provenance: .computed)
        let out = outAfterH(x: probeX)
        let byte = NumberStyle(precision: .decimals(0), unit: "of 255", spokenUnit: "of 255")
        let numbers = [
            row("in", "IN · LINEAR", .number(0, .decimals(3), .computed)),
            row("out", "OUT · LINEAR", .number(out, .decimals(4), .computed)),
            row("encoded", "OUT · sRGB CODE", .number(Double(SRGB.code8(linear: out)), byte, .computed)),
            row("branch", "IF BLURRED ENCODED", .number((out * 255).rounded(), byte, .computed, caption: "BRANCH · COLOUR SPACE")),
            row("cpu", "CPU REFERENCE", .number(out, .decimals(5), .computed)),
            row("parity", "|GPU − CPU|", .notYetMeasured(unit: "steps")),
        ]
        let neighbours = (445...450).map { x in row("x\(x)", "x \(x)", .number(outAfterH(x: x), .decimals(3), .computed)) }
        let chain = TableBlock(columns: ["STAGE", "VALUE", "FORMAT"],
                               rows: [["accumulate", NumberStyle.decimals(5).text(out), "fp32"],
                                      ["store", NumberStyle.decimals(5).text(Double(HalfFloat.round(Float(out)))), "fp16"],
                                      ["encode", NumberStyle.decimals(4).text(SRGB.encode(out)), "sRGB"],
                                      ["display", NumberStyle.integer().text(Double(SRGB.code8(linear: out))), "8-bit code"]],
                               caption: "ROUNDING CHAIN AT THE PROBE", provenance: .computed)
        return Item(id: "gaussian-pixels", context: BadgedLine([.text("GAUSSIAN · STEP EDGES · PROBE"), .literal("(446, 300)"), .text("· σ"), .value(.input(sigma, px1))]),
                    page: page(.pixels, gaussianSignature, badges: [.computed, .measured],
                               rule: "OUT = Σ w[k]·IN[x + k],  code = 255·encode(OUT)",
                               figure: .pair(.texelGrid(inGrid), .texelGrid(outGrid)), numbers: numbers,
                               details: [.values(neighbours),
                                         .disclosure(title: "Rounding chain", blocks: [
                                            .paragraph("The GPU accumulates in single precision, stores half floats between passes, and the display path encodes to sRGB eight-bit codes."),
                                            .table(chain)])],
                               inThisApp: "IN THIS APP  In a fixture IN and OUT are COMPUTED on the CPU; on the Bench they are LIVE values read back from the GPU, and the parity row is MEASURED on this phone."))
    }

    // MARK: - Math helpers (COMPUTED in Double)

    /// The minimum of the taps' response over 0…0.5 c/px, sampled finely.
    static func discreteMinimum(_ k: Kernel1D) -> Double {
        KernelMath.response(k, frequencies: ResponseQuery(samples: 2001).frequencies).min() ?? 0
    }

    /// The share of the infinite sampled Gaussian's mass beyond ±radius (per axis, discrete).
    static func discreteMassCut(sigma: Double, radius: Int) -> Double {
        let limit = Int((20 * sigma).rounded(.up))
        var all = 0.0, cut = 0.0
        for n in -limit...limit {
            let w = exp(-Double(n * n) / (2 * sigma * sigma))
            all += w
            if abs(n) > radius { cut += w }
        }
        return cut / all
    }

    /// The largest per-tap difference between the stems and the effective taps of linear-sampled pairs whose fraction
    /// t = b ÷ (a + b) is rounded to `fractionBits` bits (MODELED: round to nearest, as the M1 Max measured).
    static func linearSampledError(_ k: Kernel1D, fractionBits: Int) -> Double {
        let r = k.origin, steps = Double(1 << fractionBits)
        var worst = 0.0, n = 1
        while n <= r {
            let a = k.weights[r + n], b = n + 1 <= r ? k.weights[r + n + 1] : 0
            let s = a + b, t = s > 0 ? b / s : 0
            let q = (t * steps).rounded() / steps
            worst = Swift.max(worst, abs(s * (1 - q) - a), abs(s * q - b))
            n += 2
        }
        return worst
    }

    /// The probe row after pass H on step edges (IN = 1 for x ≥ 447): Σ of the weights that land on the bright side.
    static func outAfterH(x: Int) -> Double {
        let r = kernel.origin
        return (-r...r).reduce(0) { $0 + (x + $1 >= edgeX ? kernel.weights[r + $1] : 0) }
    }

    /// Area coverage of a disc of `radius` px per pixel (16 × 16 supersamples), normalised to sum 1.
    static func discKernel(radius: Double) -> Kernel2D {
        let half = Int(radius.rounded(.up)), size = 2 * half + 1, ss = 16
        var w = [Double](repeating: 0, count: size * size)
        for j in 0..<size { for i in 0..<size {
            var hit = 0
            for sy in 0..<ss { for sx in 0..<ss {
                let x = Double(i - half) - 0.5 + (Double(sx) + 0.5) / Double(ss)
                let y = Double(j - half) - 0.5 + (Double(sy) + 0.5) / Double(ss)
                if x * x + y * y <= radius * radius { hit += 1 }
            } }
            w[j * size + i] = Double(hit) / Double(ss * ss)
        } }
        let total = w.reduce(0, +)
        return Kernel2D(width: size, height: size, originX: half, originY: half, weights: w.map { $0 / total })
    }

    /// A flat regular hexagon (a vertex on +x) of `circumradius` px, area-weighted by 8 × 8 supersamples, sum 1.
    static func hexagonKernel(circumradius r: Double) -> Kernel2D {
        let half = Int(r.rounded(.up)), size = 2 * half + 1, ss = 8
        let apothem = r * 3.0.squareRoot() / 2
        let normals = [30.0, 90.0, 150.0].map { SIMD2(cos($0 * .pi / 180), sin($0 * .pi / 180)) }
        var w = [Double](repeating: 0, count: size * size)
        for j in 0..<size { for i in 0..<size {
            var hit = 0
            for sy in 0..<ss { for sx in 0..<ss {
                let p = SIMD2(Double(i - half) - 0.5 + (Double(sx) + 0.5) / Double(ss), Double(j - half) - 0.5 + (Double(sy) + 0.5) / Double(ss))
                if normals.allSatisfy({ abs(($0 * p).sum()) <= apothem }) { hit += 1 }
            } }
            w[j * size + i] = Double(hit) / Double(ss * ss)
        } }
        let total = w.reduce(0, +)
        return Kernel2D(width: size, height: size, originX: half, originY: half, weights: w.map { $0 / total })
    }

    /// The zoom blur's local PSF at pixel `p`: `samples` taps at c + (pc − c)·s, s from 1 + a/2 down to 1 − a/2, each of
    /// weight 1/samples, splatted bilinearly around the pixel centre pc.
    static func zoomLocalPSF(at p: PixelPoint, centre c: SIMD2<Double>, strength a: Double, samples: Int) -> Kernel2D {
        let pc = p.centre
        let offsets = (0..<samples).map { i -> SIMD2<Double> in
            let s = 1 + a * (0.5 - Double(i) / Double(samples - 1))
            return (pc - c) * (s - 1)
        }
        let reach = offsets.map { Swift.max(abs($0.x), abs($0.y)) }.max() ?? 0
        let half = Int(reach.rounded(.up)) + 1, size = 2 * half + 1
        var w = [Double](repeating: 0, count: size * size)
        for o in offsets {
            let gx = o.x + Double(half), gy = o.y + Double(half)
            let x0 = Int(floor(gx)), y0 = Int(floor(gy)), fx = gx - floor(gx), fy = gy - floor(gy)
            for (dx, dy, f) in [(0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)] where f > 0 {
                let x = x0 + dx, y = y0 + dy
                if x >= 0, y >= 0, x < size, y < size { w[y * size + x] += f / Double(samples) }
            }
        }
        return Kernel2D(width: size, height: size, originX: half, originY: half, weights: w)
    }
}
// END MIRRORED
