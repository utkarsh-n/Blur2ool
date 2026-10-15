import SwiftUI
import BlurCore

// OWNER: CONTENT-VIEWS (frozen initialiser, ARCHITECTURE §5.11 / AppContract/Content). One floor page (SPEC §5.0):
// eyebrow and dominant badges, the floor's one question, the catalog signature, the Shader · Silicon tabs (floor 6), the
// governing rule, ONE figure (or the honest empty state engraved in its slot), at most six badged numbers, `All … details`
// (the only element that grows: the figure's data table first, then the page's blocks), and the closing IN THIS APP line.
// Every slot has a fixed height for the floor at the current Dynamic Type size (FloorSlots), never one taken from the
// current blur, so switching blurs moves nothing (SPEC §5.0 rule 7). At accessibility sizes the slots grow with the text
// and the page grows in place; there is no nested vertical scroll.
public struct FloorPageView: View {
    private let page: FloorPage
    @Binding private var selectedTab: String?
    private let onPassSelected: (Int?) -> Void
    @State private var localTab: String?
    @Environment(\.dynamicTypeSize) private var size

    public init(_ page: FloorPage, selectedTab: Binding<String?> = .constant(nil), onPassSelected: @escaping (Int?) -> Void = { _ in }) {
        self.page = page; self._selectedTab = selectedTab; self.onPassSelected = onPassSelected
    }

    private var tabs: [FloorTab] { page.tabs ?? [] }
    private var activeTab: FloorTab? {
        guard !tabs.isEmpty else { return nil }
        let id = selectedTab ?? localTab
        return tabs.first { $0.id == id } ?? tabs.first
    }
    private var figure: FigureSpec? { activeTab?.figure ?? page.figure }
    private var numbers: [LabeledValue] {
        if let t = activeTab, !t.numbers.isEmpty { return t.numbers }
        return page.numbers
    }
    private var details: [ContentBlock] { (activeTab?.details ?? []) + page.details }
    private var badges: [Provenance] {
        if let t = activeTab, !t.dominantBadges.isEmpty { return t.dominantBadges }
        return page.dominantBadges
    }

    public var body: some View {
        InstrumentContentPanel {
            VStack(alignment: .leading, spacing: ContentSpacing.section) {
                if size.isAccessibilitySize {
                    // At accessibility sizes the sections grow with their text (SPEC §4.1.10); the header reserves nothing.
                    FloorHeaderContent(eyebrow: page.eyebrow, badges: badges)
                } else {
                    ContentReservedSlot { FloorHeaderContent(eyebrow: page.eyebrow, badges: badges) }
                        reserve: { FloorHeaderReserve(eyebrow: page.eyebrow) }
                }
                FloorQuestionContent(question: page.question)
                ContentReservedSlot { FloorSignatureContent(signature: page.signature) } reserve: { FloorSignatureReserve() }
                if !tabs.isEmpty || page.floor == .gpu { tabPicker }
                ContentReservedSlot { FloorRuleContent(rule: page.governingRule) } reserve: { FloorRuleReserve() }
                figureSlot
                VStack(alignment: .leading, spacing: ContentValueRow.spacing) {
                    // Six fixed channels; at accessibility sizes only the rows that exist (the section grows instead).
                    ForEach(0..<(size.isAccessibilitySize ? numbers.count : FloorSlots.numberSlots), id: \.self) { i in
                        FloorNumberSlot(row: i < numbers.count ? numbers[i] : nil)
                    }
                }
                if hasDetails { detailsDisclosure }
                ContentReservedSlot { FloorInThisAppContent(text: page.inThisApp) } reserve: { FloorInThisAppReserve() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floor \(page.floor.rawValue) of 7, \(page.floor.title)")
    }

    // MARK: Tabs (floor 6: Shader · Silicon)

    @ViewBuilder private var tabPicker: some View {
        if tabs.isEmpty {
            // Floor 6 without tabs still reserves the picker's height (fixed geometry across blurs).
            Picker("", selection: .constant(0)) { Text("Shader").tag(0) }.pickerStyle(.segmented).hidden().accessibilityHidden(true)
        } else {
            Picker("Floor 6 view", selection: Binding(get: { activeTab?.id ?? "" }, set: { localTab = $0; selectedTab = $0 })) {
                ForEach(tabs) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .instrumentControlOwnsTouches(identifier: "floorTabs")
        }
    }

    // MARK: Figure slot

    private var figureHeight: CGFloat { FloorSlots.figureHeight(page.floor, size) }

    @ViewBuilder private var figureSlot: some View {
        if page.floor == .slide {
            // The SLIDE floor's figure is rows of text: its slot is as tall as the exemplar nine-tool figure at this size.
            ContentReservedSlot { figureContent } reserve: { ToolBarsFigure(spec: FloorSlots.toolBarsExemplar) }
        } else {
            figureContent
        }
    }

    @ViewBuilder private var figureContent: some View {
        Group {
            if let figure {
                FigureView(figure, height: figureHeight, onPassSelected: onPassSelected)
                    .environment(\.figureDataTableInline, false)
            } else if let empty = page.emptyState {
                ContentEngravedLine(text: empty).frame(height: figureHeight).contentPlotInset()
            } else {
                Color.clear.frame(height: figureHeight).contentPlotInset().accessibilityHidden(true)
            }
        }
        .frame(minHeight: figureHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)   // rigid: a stack never squeezes the slot below its content
    }

    // MARK: All … details

    private var hasDetails: Bool { !details.isEmpty || figure.map(FigureDataTable.hasTable) == true }

    private var detailsDisclosure: some View {
        ContentDisclosure {
            Text(ContentLogic.detailsTitle(page.floor, tabTitle: activeTab?.title))
                .contentFont(.label)
                .foregroundStyle(InstrumentPalette.actionCyan)
        } content: {
            VStack(alignment: .leading, spacing: ContentSpacing.block) {
                if let figure, FigureDataTable.hasTable(figure) { FigureDataTable(figure: figure) }
                ForEach(Array(details.enumerated()), id: \.offset) { ContentBlockView($0.element) }
            }
        }
    }
}
