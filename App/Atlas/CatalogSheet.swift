import SwiftUI
import BlurCore

// OWNER: UI-ATLAS (entry view seed written by SKEL; frozen name and initialiser `CatalogSheet(tab:)`, PLAN S14; SPEC §4.5).
// The Catalog sheet with its own NavigationStack (CatalogRoute) and four tabs. Seed: Blurs lists every registered entry by
// family (tap = switch blur with σ-hold); the other tabs engrave that they are not built yet.
// TODO(UI-ATLAS): three-line rows ≥ 72 pt with search, tier and capability chips; the Fingerprints matrix Grid with spoken
// rows and sorting; Divergence; Lessons; Tier 3 atlas pages pushed inside the sheet.
public struct CatalogSheet: View {
    @Environment(BenchModel.self) private var bench
    @State private var tab: CatalogTab
    @State private var path: [CatalogRoute] = []

    public init(tab: CatalogTab) { _tab = State(initialValue: tab) }

    public var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Catalog", selection: $tab) {
                    Text("Blurs").tag(CatalogTab.blurs)
                    Text("Fingerprints").tag(CatalogTab.fingerprints)
                    Text("Divergence").tag(CatalogTab.divergence)
                    Text("Lessons").tag(CatalogTab.lessons)
                }
                .pickerStyle(.segmented)
                .padding(12)
                switch tab {
                case .blurs:
                    List {
                        ForEach(Family.allCases, id: \.self) { family in
                            let entries = BlurRegistry.operators.map(\.entry).filter { $0.family == family }
                            if !entries.isEmpty {
                                Section(family.eyebrow) {
                                    ForEach(entries) { entry in
                                        Button {
                                            if entry.tier.runsLive { bench.selectBlur(entry.id); bench.sheet = nil } else { path.append(.atlasPage(entry.id)) }
                                        } label: {
                                            HStack(spacing: 12) {
                                                FootprintGlyph(entry.glyph, size: 40, isSelected: entry.id == bench.configuration.blur)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(entry.displayName).font(.body.weight(.semibold))
                                                    Text(entry.tier.chip).font(.system(.caption2, design: .monospaced)).foregroundStyle(InstrumentPalette.secondaryInk)
                                                }
                                            }
                                            .frame(minHeight: 64)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                default:
                    Text("\(tab.rawValue.uppercased()) · NOT YET BUILT").font(.system(.caption, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(InstrumentPalette.secondaryInk).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(InstrumentDesignBackground())
            .navigationTitle("Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CatalogRoute.self) { route in
                switch route {
                case .atlasPage(let id):
                    Text("\(BlurRegistry.entry(id)?.displayName ?? id.rawValue) · ATLAS PAGE NOT YET BUILT")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { bench.sheet = nil } } }
        }
    }
}
