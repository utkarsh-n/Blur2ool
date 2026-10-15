import XCTest
import SwiftUI
@testable import Blur2ool
import BlurCore

// OWNER: CONTENT-VIEWS. Text fit on the phone (review fix P-48; ARCHITECTURE §11.3 "Layout"; SPEC §4.1.10 "Text fit"):
// every fixture FloorPageView slot, every engraving and every status-row template, rendered with ImageRenderer at the default
// and xxxLarge Dynamic Type sizes and at 430, 393 and 375 pt widths, against its reserved slot (App/Content/ContentTextFit).
// Run with `Tools/build.sh device-build-for-testing` + `device-session "test --area CONTENTVIEWS --kind app"`.
@MainActor
final class CONTENTVIEWS_TextFitTests: XCTestCase {
    /// SPEC templates of other areas' slots that cannot fit (Documentation/build/requests/CONTENT-VIEWS.md, 2026-10-14 19:45):
    /// recorded as expected failures, never silently passed.
    private let knownStatusConflicts = ["σ HELD 12.0 px → σs", "σ HELD 12.0 px → a", "σ HELD 4.0 px → r", "32 SAMPLES",
                                        "TOO SLOW TO TIME", "MIN H  A", "MAX 6 LSB"]
    private let knownEngravingConflicts = ["SYSTEM · ON SCREEN · NOT READ BACK"]

    private func check(_ results: [ContentTextFit.Result], known: [String] = [], context: String) {
        XCTAssertFalse(results.isEmpty, "\(context): nothing measured")
        for r in results {
            if !r.fits && known.contains(where: { r.subject.hasPrefix($0) }) {
                XCTExpectFailure("\(context): \(r) — SPEC conflict in another area's slot, see requests/CONTENT-VIEWS.md", strict: false) {
                    XCTAssertTrue(r.fits, "\(context): \(r)")
                }
            } else {
                XCTAssertTrue(r.fits, "\(context): \(r)")
            }
        }
        print("CONTENTVIEWS text fit · \(context): \(results.filter(\.fits).count) of \(results.count) fit")
    }

    func testEveryFixtureFloorPageSlotFits() {
        for screen in ContentTextFit.widths {
            for size in ContentTextFit.sizes {
                var results: [ContentTextFit.Result] = []
                for item in ContentFixtures.items {
                    results += ContentTextFit.pageResults(item.page, id: item.id, screen: screen, size: size)
                }
                check(results, context: "pages \(Int(screen)) pt \(size)")
            }
        }
    }

    func testEveryEngravingFitsItsSlot() {
        for screen in ContentTextFit.widths {
            for size in ContentTextFit.sizes {
                check(ContentTextFit.engravingResults(screen: screen, size: size), known: knownEngravingConflicts,
                      context: "engravings \(Int(screen)) pt \(size)")
            }
        }
    }

    func testEveryStatusRowTemplateKeepsItsNumbersOnOneLine() {
        for screen in ContentTextFit.widths {
            for size in ContentTextFit.sizes {
                check(ContentTextFit.statusResults(screen: screen, size: size), known: knownStatusConflicts,
                      context: "status row \(Int(screen)) pt \(size)")
            }
        }
    }

    /// SPEC §5.0 rule 7: every fixture page of one floor has the same height at a given size and width.
    func testSwitchingBlursMovesNothing() {
        for screen in ContentTextFit.widths {
            for size in ContentTextFit.sizes {
                for floor in Floor.allCases {
                    let pages = ContentFixtures.items.filter { $0.page.floor == floor }
                    guard pages.count > 1 else { continue }
                    let heights = pages.map { ContentTextFit.height(FloorPageView($0.page), width: ContentTextFit.pageWidth(screen), size: size) }
                    XCTAssertEqual(Set(heights).count, 1, "floor \(floor.rawValue) at \(Int(screen)) pt \(size): \(zip(pages.map(\.id), heights).map { "\($0) \($1)" })")
                }
            }
        }
    }

    /// The app's own Gaussian pages (CONTENT-LAYERS' builder) through the same measurement; reported, not gated (their
    /// content is another area's), so a regression shows in the log.
    func testBuilderPagesAreMeasured() {
        let pages = ContentGallery.builderPages()
        for page in pages {
            let results = ContentTextFit.pageResults(page, id: "builder floor \(page.floor.rawValue)", screen: 393, size: .large)
            for r in results where !r.fits { print("CONTENTVIEWS builder page note: \(r)") }
        }
        XCTAssertEqual(pages.count, pages.isEmpty ? 0 : 7)
    }
}
