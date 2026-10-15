import XCTest
import SwiftUI
import Accessibility
@testable import Blur2ool
import BlurCore

// OWNER: CONTENT-VIEWS. Every renderer draws on the phone: every fixture page at the default and AX5 sizes, every figure kind in
// its slot, the plots' AXChartDescriptor carries the same series and points, and the data tables hold the same numbers.
@MainActor
final class CONTENTVIEWS_RenderTests: XCTestCase {
    private func render<V: View>(_ view: V, width: CGFloat, size: DynamicTypeSize = .large) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: width).environment(\.dynamicTypeSize, size).preferredColorScheme(.dark))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.cgImage
    }

    func testEveryFixturePageRendersAtDefaultAndAX5() throws {
        for item in ContentFixtures.items {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let image = try XCTUnwrap(render(FloorPageView(item.page), width: 406, size: size), "\(item.id) \(size)")
                XCTAssertEqual(image.width, 812, "\(item.id)")
                XCTAssertGreaterThan(image.height, 1_000, "\(item.id) \(size): a page is taller than 500 pt")
            }
        }
    }

    func testEveryFigureKindDrawsInItsSlot() throws {
        var kinds = Set<String>()
        for item in ContentFixtures.items {
            for figure in ContentLogic.figures(in: item.page) {
                kinds.insert(ContentLogic.figureKind(figure))
                let image = try XCTUnwrap(render(FigureView(figure, height: 220), width: 374), "\(item.id) \(ContentLogic.figureKind(figure))")
                XCTAssertGreaterThanOrEqual(image.height, 440, "\(item.id) \(ContentLogic.figureKind(figure)) fills its 220 pt slot")
            }
        }
        XCTAssertEqual(kinds, ContentLogic.allFigureKinds)
    }

    func testEveryBlockKindDraws() throws {
        var kinds = Set<String>()
        for item in ContentFixtures.items {
            for block in ContentLogic.blocks(in: item.page) {
                kinds.insert(ContentLogic.blockKind(block))
                let image = try XCTUnwrap(render(ContentBlockView(block).environment(\.contentDisclosuresOpen, true), width: 374))
                XCTAssertGreaterThan(image.height, 0)
            }
        }
        XCTAssertEqual(kinds, ContentLogic.allBlockKinds)
    }

    func testPlotDescriptorsCarryTheSameNumbers() {
        for item in ContentFixtures.items {
            for case .plot(let plot) in ContentLogic.figures(in: item.page) {
                let descriptor = PlotChartDescriptor(plot: plot).makeChartDescriptor()
                XCTAssertEqual(descriptor.series.count, plot.series.count, item.id)
                for (s, d) in zip(plot.series, descriptor.series) {
                    XCTAssertEqual(d.dataPoints.count, s.xs.count, "\(item.id) \(s.name)")
                    XCTAssertTrue((d.name ?? "").contains(s.provenance.spokenPhrase(device: nil)), "series names say their badge")
                }
                XCTAssertEqual(descriptor.summary, plot.accessibilitySummary)
                let table = FigureDataTable.table(.plot(plot))
                XCTAssertEqual(table.rows.count, Set(plot.series.map(\.xs)).reduce(0) { $0 + $1.count }, "\(item.id): one row per sample")
                XCTAssertEqual(table.spoken.count, table.rows.count)
            }
        }
    }

    func testTexelGridTablesListEveryValue() {
        for item in ContentFixtures.items {
            for case .texelGrid(let grid) in ContentLogic.figures(in: item.page) {
                let table = FigureDataTable.table(.texelGrid(grid))
                XCTAssertEqual(table.rows.count, grid.size)
                XCTAssertEqual(table.columns.count, grid.size + 1)
            }
        }
    }

    func testValueRowsNeverBreakABadgeWord() {
        // The longest badge word must lay out on one line inside every number row at 375 pt, default and xxxLarge.
        for size in [DynamicTypeSize.large, .xxxLarge] {
            let badge = ContentTextFit.lineWidth(HonestyBadge(.reference), size: size)
            let row = ContentTextFit.renderedSize(ContentValueText(value: FloorSlots.numberExemplar.value).fixedSize(), width: nil, size: size)
            XCTAssertGreaterThan(row.width, badge, "\(size)")
        }
    }

    func testContentGalleryBuilds() {
        let gallery = ContentGallery()
        _ = gallery.body
        XCTAssertEqual(ContentFixtures.items.count, 15)
    }
}
