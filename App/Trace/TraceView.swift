import SwiftUI
import BlurCore

// OWNER: UI-TRACE (entry view seed written by SKEL; frozen name and initialiser `TraceView()`, PLAN S14; SPEC §4.4, §6).
// Seed: the context card (probe, IN and OUT from the newest full-resolution Run, LIVE), the CPU reconstruction's taps of
// the first pass (COMPUTED, never LIVE), and the steps the TraceScripter produces (none yet: an engraved empty state).
// TODO(UI-TRACE): the 9 × 9 / 17 × 17 context grid, floor selector tiles, the floor panel, Back · Restart · Next unit,
// long-press Finish pass, the Jump menu, Play, VoiceOver announcements, PREPARING TRACED BUILD and the TRACED BUILD engraving.
public struct TraceView: View {
    @Environment(BenchModel.self) private var bench
    @State private var session: TraceSession?

    public init() {}

    public var body: some View {
        ZStack {
            InstrumentDesignBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    InstrumentContentPanel {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PIXEL (\(bench.configuration.probe.x), \(bench.configuration.probe.y))")
                                .font(.system(.headline, design: .monospaced))
                            if let probe = bench.lastFull[.a]?.probe {
                                LabeledValuesView([
                                    LabeledValue(id: "in", label: "IN", value: .number(probe.input.x, .significant(3), .live)),
                                    LabeledValue(id: "out", label: "OUT", value: .number(probe.output.x, .significant(3), .live)),
                                ])
                            } else {
                                Text("RENDERING…").font(.system(.caption, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                            }
                        }
                    }
                    if let session, let record = session.record {
                        InstrumentContentPanel {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("PASS 1 · CPU RECONSTRUCTION").font(.system(.caption, design: .monospaced))
                                    Spacer()
                                    HonestyBadge(.computed)
                                }
                                ForEach(record.passes.first?.taps.prefix(13) ?? []) { tap in
                                    HStack {
                                        Text(NumberStyle(precision: .decimals(4), explicitPlus: true).text(tap.offset.x))
                                        Spacer()
                                        Text(NumberStyle.decimals(5).text(tap.weight))
                                        Spacer()
                                        Text(NumberStyle.significant(3).text(tap.runningSum.x))
                                    }
                                    .font(.system(.caption2, design: .monospaced)).monospacedDigit()
                                }
                            }
                        }
                    }
                    if session?.steps.isEmpty ?? true {
                        Text("TRACE STEPS ARE BEING BUILT").font(.system(.caption, design: .monospaced)).tracking(1.2)
                            .foregroundStyle(InstrumentPalette.secondaryInk).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle("Trace")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let made = bench.makeTraceSession()
            session = made
            await made.start()
        }
        .onDisappear { session?.close() }
    }
}
