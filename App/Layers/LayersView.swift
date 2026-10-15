import SwiftUI
import BlurCore

// OWNER: UI-LAYERS (entry view seed written by SKEL; frozen name and initialiser `LayersView(floor:)`, PLAN S14; SPEC §4.3).
// Seed: one plain vertical ScrollView of FloorPageView sections for the current blur and probe, opened at `floor`. The seed
// FloorPageBuilder already puts real COMPUTED Gaussian numbers on the Math and Kernel floors; the other floors engrave
// their honest empty state.
// TODO(UI-LAYERS): the pinned periscope (second MTKView, PresentRenderer crop mode, pass intermediates), scrollPosition
// snapping, the 44-pt floor rail with its rotor, floor 6 Shader · Silicon tabs with the bundled sources and combined SHA,
// returning to the Bench with the chip focused.
public struct LayersView: View {
    public let floor: Floor
    @Environment(BenchModel.self) private var bench
    @State private var pages: [FloorPage] = []
    @State private var position: Floor?

    public init(floor: Floor) { self.floor = floor }

    public var body: some View {
        ZStack {
            InstrumentDesignBackground()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(pages) { page in FloorPageView(page).id(page.floor) }
                }
                .scrollTargetLayout()
                .padding(12)
            }
            .scrollPosition(id: $position, anchor: .top)
            .task(id: bench.lastFull[.a]?.id) {
                let loaded = await bench.floorPages()
                let first = pages.isEmpty
                pages = loaded
                if first { position = floor }      // open at the requested floor once; later reloads keep his position
            }
        }
        .navigationTitle("\(bench.entry?.displayName ?? "") · Floor \(floor.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
