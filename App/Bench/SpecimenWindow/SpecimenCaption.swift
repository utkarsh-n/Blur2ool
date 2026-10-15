import Foundation
import SwiftUI
import BlurCore

// OWNER: UI-SPECIMEN (SPEC §4.1 caption row, §4.1.3 zoom/pan captions, §4.1.9 f–g, §4.1.10). What the housing's caption
// row says about the image: the PROVENANCE (right-aligned, never truncated, also the first phrase of the image's VoiceOver
// value) and the labels (left: split labels or blur name, then the specimen or the pan; the specimen truncates first).
// Every number in a caption is an input (zoom factor, pan offset, pass index): `.literal` or `BadgedValue.input`, no badge.

public struct SpecimenCaption: Sendable, Equatable {
    /// Right side: `LIVE · METAL`, `PREVIEW ½`, `PREVIEW ¼`, `ZOOM 4× · NEAREST`, `PASS 1 OF 2 · INTERMEDIATE`,
    /// `SYSTEM · ON SCREEN` / `MODELED · METAL`, `INFERRED · NATIVE GLASS` / `MODELED · STRUCTURE INFERRED`.
    public var provenance: BadgedLine
    /// For Tier S: the right half's provenance (the left half's is `provenance`).
    public var secondProvenance: BadgedLine?
    /// Left side, before the specimen: `◀ INPUT │ GAUSSIAN ▶`, `GAUSSIAN`, `B · BOX │ A · GAUSSIAN`.
    public var subject: String
    /// The specimen name, or `PAN +36, −12 PX` while the pan is non-zero (truncates first).
    public var detail: BadgedLine
    /// "Live, Metal" — the provenance as VoiceOver starts the image's value.
    public var spokenProvenance: String

    /// The caption for the Bench's current state (requested view state; image quality from the acknowledged Run).
    @MainActor public static func make(bench: BenchModel) -> SpecimenCaption {
        let entry = bench.entry
        let blur = entry?.displayName.uppercased() ?? bench.configuration.blur.rawValue.uppercased()
        let specimen = SpecimenRegistry.generator(bench.configuration.specimen)?.descriptor.menuName.uppercased()
            ?? bench.configuration.specimen.rawValue.uppercased()
        var caption = SpecimenCaption(provenance: .words("LIVE · METAL"), secondProvenance: nil, subject: blur,
                                      detail: .words(specimen), spokenProvenance: "Live, Metal")
        if entry?.tier == .system {
            let glass = ["liquid-glass", "apple-uiblureffect"].contains(bench.configuration.blur.rawValue)
            caption.provenance = .words(glass ? "INFERRED · NATIVE GLASS" : "SYSTEM · ON SCREEN")
            caption.secondProvenance = .words(glass ? "MODELED · STRUCTURE INFERRED" : "MODELED · METAL")
            caption.spokenProvenance = glass ? "Inferred, native glass, left; modeled, structure inferred, right"
                                             : "System, on screen, not read back, left; modeled, Metal, right"
        } else if let pass = bench.view.shownPass {
            let total = bench.lastFull[.a]?.kernel.passNames.count ?? 0
            caption.provenance = BadgedLine([.text("PASS"), .literal("\(pass + 1)"), .text("OF"), .literal("\(Swift.max(total, pass + 1))"),
                                             .text("· INTERMEDIATE")])
            caption.spokenProvenance = "Pass \(pass + 1) of \(Swift.max(total, pass + 1)), intermediate"
        } else if bench.view.zoom > 1.001 {
            let z = BadgedValue.input(bench.view.zoom.rounded(), .integer())
            caption.provenance = BadgedLine([.text("ZOOM"), .literal("\(z.text)×"), .text("· NEAREST")])
            caption.spokenProvenance = "Zoom \(z.text) times, nearest"
        } else if let quality = bench.acknowledged[.a]?.quality, quality != .full {
            caption.provenance = .words(quality == .half ? "PREVIEW ½" : "PREVIEW ¼")
            caption.spokenProvenance = quality == .half ? "Preview, half resolution" : "Preview, quarter resolution"
        }
        if let compare = bench.compare {
            let b = BlurRegistry.entry(compare.b.blur)?.displayName.uppercased() ?? compare.b.blur.rawValue.uppercased()
            caption.subject = compare.view == .wipe ? "B · \(b) │ A · \(blur)" : "A · \(blur) · B · \(b)"
        } else if bench.view.split != nil {
            caption.subject = "◀ INPUT │ \(blur) ▶"
        }
        let pan = bench.configuration.pan
        if pan != .zero {
            let style = NumberStyle(precision: .decimals(0), unit: nil, explicitPlus: true)
            caption.detail = BadgedLine([.text("PAN"), .value(.input(Double(pan.x), style)), .literal(","),
                                         .value(.input(Double(pan.y), style)), .text("PX")])
        }
        return caption
    }
}

/// The caption row (11-pt mono, scaled up to 15 pt between default and AX1, in the housing's 24-pt top margin): the labels
/// on the left truncate (specimen first, then the subject); the provenance on the right never truncates. UI-BENCH places it;
/// at accessibility sizes the provenance moves below the housing (SPEC §4.1.10) and this row shows only the provenance.
public struct SpecimenCaptionRow: View {
    @Environment(BenchModel.self) private var bench
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var fontSize = 11.0
    public init() {}

    public var body: some View {
        let caption = SpecimenCaption.make(bench: bench)
        let size = Swift.min(fontSize, 15)
        HStack(spacing: 6) {
            if !typeSize.isAccessibilitySize {
                Text(caption.subject).lineLimit(1).truncationMode(.tail).layoutPriority(1)
                Text("· " + caption.detail.text).lineLimit(1).truncationMode(.tail)   // truncates first
                Spacer(minLength: 6)
            }
            Text(caption.provenance.text).lineLimit(1).fixedSize().layoutPriority(2)
            if let second = caption.secondProvenance {
                Text("│ " + second.text).lineLimit(1).fixedSize().layoutPriority(2)
            }
        }
        .font(.system(size: size, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.68))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.spokenProvenance + ". " + caption.subject.lowercased() + ", " + caption.detail.spoken)
    }
}
