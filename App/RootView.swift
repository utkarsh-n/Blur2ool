import SwiftUI
import BlurCore

// OWNER: SKEL (frozen; ARCHITECTURE §5.9, SPEC §3). One spine: NavigationStack(path:) whose root is the Bench, pushes for
// Layers and Trace, and ONE .sheet(item:) for every sheet (Catalog, Fingerprint, Field guide, Calibrate; METRO §F.5 item 3).
// The entry views have frozen names and initialisers (PLAN S14): BenchView(), LayersView(floor:), TraceView(),
// CatalogSheet(tab:), FieldGuideSheet(tab:blur:), CalibrateSheet(subject:), FingerprintCardView(model:style:…); the
// `gallery` and `content-gallery` scenarios show ComponentGallery() and ContentGallery(). Entry views read the BenchModel
// and the AppEnvironment from the SwiftUI environment.
struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        Group {
            if environment.launch?.scenario == .gallery {
                ComponentGallery()
            } else if environment.launch?.scenario == .contentGallery {
                ContentGallery()
            } else if let bench = environment.bench {
                RootStack(bench: bench)
            } else {
                StartupFailureView(message: environment.startupFailure ?? "the GPU could not be prepared")
            }
        }
        .environment(environment)
    }
}

private struct RootStack: View {
    @Bindable var bench: BenchModel
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack(path: $bench.path) {
            BenchView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .layers(let floor): LayersView(floor: floor)
                    case .trace: TraceView()
                    }
                }
        }
        .sheet(item: $bench.sheet) { destination in
            Group {
                switch destination {
                case .catalog(let tab): CatalogSheet(tab: tab)
                case .fingerprint(let blur): FingerprintSheetHost(blur: blur)
                case .fieldGuide(let tab, let blur): FieldGuideSheet(tab: tab, blur: blur)
                case .calibrate(let subject): CalibrateSheet(subject: subject)
                }
            }
            .environment(bench)
            .environment(environment)
            .preferredColorScheme(.dark)
        }
        .environment(bench)
    }
}

/// The Fingerprint sheet: the full card (UI-ATLAS's frozen FingerprintCardView) for one blur, built by BenchModel.
private struct FingerprintSheetHost: View {
    let blur: BlurID
    @Environment(BenchModel.self) private var bench
    @State private var model: FingerprintCardModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                FingerprintCardView(model: model, style: .full,
                                    onNeighbour: { bench.sheet = .fingerprint($0) },
                                    onFloor: { floor in bench.sheet = nil; bench.path.append(.layers(floor)) },
                                    onFieldGuide: { bench.sheet = .fieldGuide(.guide, blur) })
                    .padding(12)
            }
            .background(InstrumentDesignBackground())
            .navigationTitle(BlurRegistry.entry(blur)?.displayName ?? blur.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { bench.sheet = nil } } }
        }
        .task(id: blur) { model = await bench.fingerprintCard(for: blur) }
    }
}

private struct StartupFailureView: View {
    let message: String
    var body: some View {
        ZStack {
            InstrumentDesignBackground()
            VStack(spacing: 8) {
                Text("Blur2ool").font(.system(.title, design: .rounded, weight: .semibold))
                Text("GPU NOT AVAILABLE").font(.system(.caption, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(InstrumentPalette.secondaryInk)
                Text(message).font(.footnote).foregroundStyle(InstrumentPalette.secondaryInk).multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }
}
