import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS. The `content-gallery` launch scenario (CONTENT-VIEWS' screenshot target; frozen name and initialiser
// `ContentGallery()`, RootView shows it): every fixture floor page (ContentFixtures: every FigureSpec and ContentBlock kind,
// built from real math), then the seven Gaussian pages the app's FloorPageBuilder produces, each under the line that says
// which set-up it shows. Launch arguments: `-B2Param page=<fixture id>` starts scrolled to that page (for screenshots of
// one page; `-B2Param align=bottom` puts the page's bottom on screen instead of its top), `-B2Param details=open` opens
// every `All … details` and nested disclosure, `-B2Param tables=open` also opens the figures' data tables, and
// `-B2Param tab=silicon` selects that floor 6 tab.
public struct ContentGallery: View {
    @State private var items: [ContentFixtures.Item] = []
    @State private var builderPages: [FloorPage] = []
    @State private var selectedTabs: [String: String] = [:]
    private let launch = ContentGallery.launchParameters()

    public init() {}

    public var body: some View {
        ZStack {
            InstrumentDesignBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ContentSpacing.block) {
                        header
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                ContentBadgedLineText(line: item.context)
                                    .padding(.horizontal, 4)
                                FloorPageView(item.page, selectedTab: tabBinding(item.id))
                            }
                            .id(item.id)
                        }
                        if !builderPages.isEmpty {
                            Text("GAUSSIAN · NIGHT CITY · THE APP'S OWN FLOOR PAGE BUILDER")
                                .contentFont(.engraving).foregroundStyle(ContentInk.secondary)
                                .padding(.top, ContentSpacing.section).padding(.horizontal, 4)
                                .id("builder")
                            ForEach(builderPages) { page in
                                FloorPageView(page).id("builder-\(page.floor.rawValue)")
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .task {
                    let built = await Task.detached(priority: .userInitiated) { () -> ([ContentFixtures.Item], [FloorPage]) in
                        (ContentFixtures.items, ContentGallery.builderPages())
                    }.value
                    items = built.0
                    builderPages = built.1
                    if let tab = launch["tab"] { for item in built.0 where item.page.tabs != nil { selectedTabs[item.id] = tab } }
                    if let page = launch["page"] {
                        try? await Task.sleep(for: .milliseconds(150))
                        proxy.scrollTo(page, anchor: launch["align"] == "bottom" ? .bottom : .top)
                    }
                }
            }
        }
        .environment(\.contentDisclosuresOpen, launch["details"] == "open")
        .environment(\.contentDataTablesOpen, launch["tables"] == "open")
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Content gallery").font(.system(.title2, design: .rounded, weight: .semibold)).foregroundStyle(ContentInk.display)
            Text("Every figure and block the floors use, from fixture pages built with BlurCore's own math.")
                .contentFont(.caption).foregroundStyle(ContentInk.secondary)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func tabBinding(_ id: String) -> Binding<String?> {
        Binding(get: { selectedTabs[id] }, set: { selectedTabs[id] = $0 })
    }

    /// `-B2Param key=value` pairs from the launch arguments (LaunchScenario's own parser, so the forms match).
    static func launchParameters() -> [String: String] {
        LaunchScenario.parse(ProcessInfo.processInfo.arguments)?.parameters ?? [:]
    }

    /// The Gaussian's seven pages from the registered FloorPageBuilder (CONTENT-LAYERS), on Night City at its default probe.
    nonisolated static func builderPages() -> [FloorPage] {
        guard let op = BlurRegistry.op(GaussianOperator.id) else { return [] }
        let entry = op.entry
        let config = RenderConfiguration(blur: entry.id, variant: entry.defaultVariant, parameters: entry.defaultParameters, settings: .standard,
                                         specimen: entry.defaultSpecimen, specimenOptions: .standard, pan: .zero,
                                         probe: PixelPoint(x: 447, y: 455), windowSize: 894)
        return BlurServices.floors.pages(for: op, context: FloorContext(configuration: config, homeToolID: "swiftui", displayScale: 3, live: LiveFacts()))
    }
}
