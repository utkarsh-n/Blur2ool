import SwiftUI
import BlurCore
import BlurGPU

// OWNER: UI-FIELDGUIDE (entry view seed written by SKEL; frozen name and initialiser `FieldGuideSheet(tab:blur:)`, PLAN
// S14; SPEC §4.7). The Field guide sheet with its own NavigationStack (FieldGuideRoute) and four tabs. Seed: Guide shows the
// FieldGuideLibrary page and the honesty legend; This phone shows the GPU limits read from this device (MEASURED, stamped)
// and pushes Calibrate; Runs lists the Run log; Settings is a Form bound to AppSettings.
// TODO(UI-FIELDGUIDE): the lens note, opening on a badge, MEASURED beside REFERENCE, Measure buttons per probe, Export JSON
// through ShareLink, swipe to delete, simulator runs marked, every Settings row.
public struct FieldGuideSheet: View {
    @Environment(BenchModel.self) private var bench
    @Environment(AppEnvironment.self) private var app
    @State private var tab: FieldGuideTab
    @State private var path: [FieldGuideRoute] = []
    @State private var page: FieldGuidePage?
    private let blur: BlurID?

    public init(tab: FieldGuideTab, blur: BlurID?) { _tab = State(initialValue: tab); self.blur = blur }

    public var body: some View {
        @Bindable var settings = bench.settings
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Field guide", selection: $tab) {
                    Text("Guide").tag(FieldGuideTab.guide)
                    Text("This phone").tag(FieldGuideTab.thisPhone)
                    Text("Runs").tag(FieldGuideTab.runs)
                    Text("Settings").tag(FieldGuideTab.settings)
                }
                .pickerStyle(.segmented)
                .padding(12)
                switch tab {
                case .guide:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if let page {
                                Text(page.title).font(.system(.title2, design: .rounded, weight: .semibold))
                                ForEach(Array(page.blocks.enumerated()), id: \.offset) { ContentBlockView($0.element) }
                            }
                            Text("HONESTY LABELS").font(.system(.caption, design: .monospaced)).padding(.top, 8)
                            ForEach(Array(BlurServices.fieldGuide.honestyLegend.enumerated()), id: \.offset) { ContentBlockView($0.element) }
                        }
                        .padding(16)
                    }
                    .task(id: blur) { page = await bench.fieldGuidePage(for: blur ?? bench.configuration.blur) }
                case .thisPhone:
                    List {
                        if let gpu = app.gpu, let device = app.renderer?.deviceStamp() {
                            let facts = gpu.facts
                            Section("GPU (MEASURED · \(device.label))") {
                                LabeledValuesView([
                                    LabeledValue(id: "threads", label: "MAX THREADS / THREADGROUP",
                                                 value: .number(Double(facts.maxThreadsPerThreadgroup), .integer(), .measured, device: device)),
                                    LabeledValue(id: "tgmem", label: "THREADGROUP MEMORY",
                                                 value: .number(Double(facts.maxThreadgroupMemoryLength), .integer(unit: "B"), .measured, device: device)),
                                ])
                                Text("\(facts.deviceName) · \(facts.familyName)").font(.system(.caption, design: .monospaced))
                            }
                            Section("Shader sources") { Text(app.shaderSourceCheck).font(.system(.caption2, design: .monospaced)) }
                        }
                        Section { NavigationLink("Calibrate SwiftUI .blur", value: FieldGuideRoute.calibrate(.swiftUIBlur)) }
                    }
                    .scrollContentBackground(.hidden)
                case .runs:
                    List(bench.runLog.runs.reversed()) { run in
                        Text("\(run.kind.rawValue.uppercased()) · \(run.configuration.blur.rawValue)").font(.system(.caption, design: .monospaced))
                    }
                    .scrollContentBackground(.hidden)
                    .overlay { if bench.runLog.runs.isEmpty { Text("NO RUNS YET").font(.system(.caption, design: .monospaced)) } }
                case .settings:
                    Form {
                        Toggle("Match σ when switching blurs", isOn: $settings.matchSigmaOnSwitch)
                        Toggle("Haptics", isOn: $settings.hapticsEnabled)
                        Toggle("Coaching line", isOn: $settings.coachingLineArmed)
                    }
                    .scrollContentBackground(.hidden)
                    .onDisappear { bench.settings.save() }
                }
            }
            .background(InstrumentDesignBackground())
            .navigationTitle("Field guide")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FieldGuideRoute.self) { route in
                switch route {
                case .calibrate(let subject): CalibrateSheet(subject: subject)
                case .honestyLegend, .lensNote:
                    ScrollView { VStack(alignment: .leading) { ForEach(Array(BlurServices.fieldGuide.honestyLegend.enumerated()), id: \.offset) { ContentBlockView($0.element) } }.padding() }
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { bench.sheet = nil } } }
        }
    }
}
