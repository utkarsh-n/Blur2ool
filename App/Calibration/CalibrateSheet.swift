import SwiftUI
import BlurCore

// OWNER: CALIBRATION (entry view, frozen name and initialiser `CalibrateSheet(subject:)`, PLAN S14; SPEC §4.8, §13.3).
// The Calibrate sheet: pick an Apple API (and, for SwiftUI, its render path, working space and border), set its own
// parameter with the native Stepper, measure it on this phone, and read the RESULT (σ, σ/(r·scale), kurtosis on the axis
// and at 45°, the three-model competition with the winner marked, wobble, extent, blend, border, the Mac reference kept
// beside it), the SWEEP (σ/(r·scale) against r on a log axis, this phone filled, macOS 27.2 dashed, the regime switch
// hollow and INFERRED until this phone measures it), the on-screen EXPERIMENT and what Apple's internals are INFERRED to be.
// Every number arrives as a BadgedValue from BlurCore's CalibrationReadout; this file lays them out.
//
// `CalibrateView(subject:)` is the same content without its own NavigationStack, for the push from Field guide › This
// phone (ARCHITECTURE §5.9: Calibrate from This phone is a push, not a second sheet).
//
// Launch parameters for the `calibrate` scenario (screenshots on the phone): `-B2Param subject=<CalibrationSubject>`
// (ENGINE), and `cal.run=basic|sweep|measure|capture`, `cal.parameter=<value>`, `cal.path=<CalibrationPath>`,
// `cal.space=<CalibrationColourMode>`, `cal.opaque=true`, `cal.scroll=result|sweep|experiment`.
public struct CalibrateSheet: View {
    private let subject: CalibrationSubject
    @Environment(BenchModel.self) private var bench
    public init(subject: CalibrationSubject) { self.subject = subject }

    public var body: some View {
        NavigationStack {
            CalibrateView(subject: subject)
                .navigationTitle("Calibrate")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { bench.sheet = nil } } }
        }
    }
}

public struct CalibrateView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.displayScale) private var displayScale
    @State private var subject: CalibrationSubject
    @State private var path: CalibrationPath
    @State private var colourMode: CalibrationColourMode = .nonLinear
    @State private var opaque = false
    @State private var parameter: Double
    @State private var launchHandled = false

    public init(subject: CalibrationSubject) {
        _subject = State(initialValue: subject)
        _path = State(initialValue: subject.defaultPath)
        _parameter = State(initialValue: subject.defaultParameter)
    }

    private var service: CalibrationService { environment.calibration }
    private var scale: Double { subject.parameterIsPoints ? Double(displayScale) : 1 }
    private var request: CalibrationRequest {
        CalibrationRequest(subject: subject, path: path, parameter: parameter, displayScale: scale,
                           colourMode: subject == .swiftUIBlur ? colourMode : .nonLinear, phases: CalibrationPlan.phases,
                           opaque: subject == .swiftUIBlur ? opaque : nil)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: CalibrationLayout.mainStack) {
                    CalibrationIntro(subject: subject)
                    controls
                    CalibrationResultPanel(request: request, result: service.result(matching: request), service: service)
                        .id("result")
                    CalibrationSweepPanel(subject: subject, path: path, colourMode: request.colourMode, opaque: opaque,
                                          displayScale: Double(displayScale), service: service)
                        .id("sweep")
                    if subject == .swiftUIBlur || subject == .swiftUIShadow {
                        CalibrationOnScreenPanel(service: service, pathIsOnScreen: path == .drawHierarchyOnScreen).id("experiment")
                    }
                    CalibrationInsideApplePanel(subject: subject)
                }
                .padding(.horizontal, CalibrationLayout.screenInset)
                .padding(.vertical, CalibrationLayout.screenInset)
                .frame(maxWidth: CalibrationLayout.portraitContentMax)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(InstrumentDesignBackground())
            .task {
                service.displayScale = Double(displayScale)
                await handleLaunch(proxy)
            }
        }
        .onChange(of: subject) { _, s in
            path = s.defaultPath
            parameter = s.defaultParameter
        }
    }

    // MARK: Controls (SPEC §4.8: API and PATH menus, the parameter Stepper, its device-pixel equivalent, Measure)

    private var controls: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: 8) {
                CalibrationMenuRow(label: "API") {
                    Picker("API", selection: $subject) {
                        ForEach(CalibrationSubject.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                if subject.paths.count > 1 {
                    CalibrationMenuRow(label: "PATH") {
                        Picker("Path", selection: $path) {
                            ForEach(subject.paths, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                } else {
                    CalibrationMenuRow(label: "PATH") {
                        Text(subject.defaultPath.title).font(.callout).foregroundStyle(InstrumentPalette.secondaryInk)
                    }
                }
                if subject == .swiftUIBlur {
                    CalibrationMenuRow(label: "SPACE") {
                        Picker("Working space", selection: $colourMode) {
                            ForEach(CalibrationColourMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    Toggle(isOn: $opaque) {
                        Text("OPAQUE").font(.system(.caption2, design: .monospaced)).tracking(CalibrationLayout.labelTracking)
                            .foregroundStyle(InstrumentPalette.secondaryInk)
                    }
                    .tint(InstrumentPalette.actionCyan)
                    .accessibilityLabel("Opaque blur")
                }
                DecimalParameterStepper(subject.parameterLabel, value: $parameter, in: subject.parameterRange, step: subject.parameterStep,
                                        decimals: subject.parameterDecimals, unit: subject.parameterUnit,
                                        spokenUnit: subject.parameterSpokenUnit)
                CalibrationLineText(line: pixelLine, font: .footnote)
                measureButton
            }
        }
    }

    /// `= 6.00 px at @3x`: the parameter in device pixels (COMPUTED from the input and this screen's scale).
    private var pixelLine: BadgedLine {
        let px = subject.parameterIsPoints ? parameter * scale : parameter
        var segments: [BadgedSegment] = [.text("="), .value(.number(px, CalibrationReadout.sigmaStyle, .computed)), .text("in device pixels")]
        if subject.parameterIsPoints { segments += [.text("at display scale"), .literal("@\(Int(scale.rounded()))x")] }
        else { segments += [.text("(this API counts pixels)")] }
        return BadgedLine(segments)
    }

    private var measureButton: some View {
        let busy = service.isBusy
        return Button {
            Task { _ = try? await service.measure(request) }
        } label: {
            Label(busy ? "Measuring…" : "Measure on this phone", systemImage: busy ? "hourglass" : "scope")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: InstrumentMetrics.controlTarget)
        }
        .buttonStyle(.glassProminent)
        .tint(busy ? InstrumentPalette.actionAmber : InstrumentPalette.actionCyan)
        .disabled(busy)
        .accessibilityHint("Renders the API's blur of a black and white edge on this phone and fits its spread.")
    }

    // MARK: Launch scenario

    private func handleLaunch(_ proxy: ScrollViewProxy) async {
        guard !launchHandled, let launch = environment.launch, launch.scenario == .calibrate else { return }
        launchHandled = true
        let p = launch.parameters
        if let raw = p["cal.path"], let value = CalibrationPath(rawValue: raw), subject.paths.contains(value) { path = value }
        if let raw = p["cal.space"], let value = CalibrationColourMode(rawValue: raw) { colourMode = value }
        if p["cal.opaque"] == "true" { opaque = true }
        if let raw = p["cal.parameter"], let value = Double(raw), subject.parameterRange.contains(value) { parameter = value }
        switch p["cal.run"] {
        case "basic": Task { await service.runBasicSet() }
        case "sweep": Task { await service.runSweep(subject, path: path, colourMode: request.colourMode, opaque: opaque) }
        case "measure": Task { _ = try? await service.measure(request) }
        case "capture": Task { await service.runCaptureTest() }
        default: break
        }
        if let target = p["cal.scroll"] {
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(nil) { proxy.scrollTo(target, anchor: .top) }
        }
    }
}

/// A Metro label column with a native control trailing (menus keep their system look and accessibility).
struct CalibrationMenuRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                     : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .tracking(CalibrationLayout.labelTracking)
                .foregroundStyle(InstrumentPalette.secondaryInk)
                .frame(minWidth: 54, alignment: .leading)
                .accessibilityHidden(true)
            if !dynamicType.isAccessibilitySize { Spacer(minLength: 0) }
            control
                .pickerStyle(.menu)
                .tint(InstrumentPalette.actionCyan)
        }
        .frame(minHeight: InstrumentMetrics.controlTarget)
    }
}

struct CalibrationIntro: View {
    let subject: CalibrationSubject
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE CALIBRATION · MEASURED ON THIS PHONE")
                .font(.system(.caption, design: .monospaced))
                .tracking(CalibrationLayout.labelTracking)
                .foregroundStyle(InstrumentPalette.actionCyan)
            Text("Apple does not say what \(subject.title) does inside. Blur2ool renders a black and white edge through it on this phone, reads the pixels back and fits the spread: what the API does, measured from outside.")
                .font(.subheadline)
                .foregroundStyle(InstrumentPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}
