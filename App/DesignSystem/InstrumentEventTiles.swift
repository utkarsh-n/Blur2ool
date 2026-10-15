import SwiftUI

// OWNER: METRO-COMPONENTS (frozen initialiser, ARCHITECTURE §5.14; Metro §12 "Event or beat tiles"; METRO §C.7; SPEC §9.1
// arrangement E, §14). The event-tile row in Metro's beat-strip grammar, for staged processing: pass tiles (H · V), Kawase
// offsets (0 1 2 2 3), dual-Kawase levels (↓1 ↓2 ↑2 ↑1), the Trace floor selector.
//   • Drawn tiles are `height` (37) tall, radius 8, gap 7. Current: cyan fill 0.08 + border 0.35 + a 2-pt underline
//     capsule; done: amber ink + a 2-pt amber mark (Trace: completed amber, next cyan); idle: white 0.025 fill + 0.06
//     border. State is carried by shape and the selected trait as well as colour (Metro §12, SPEC §14).
//   • Each tile is a real Button whose hit area is at least 44 pt tall (SPEC §14 Motor), centred on the drawn tile.
//   • More than six tiles wrap into balanced rows (METRO §C.7), so the height stays bounded.
//   • Titles and captions scale with Dynamic Type up to AX1; tiles grow taller instead of truncating.
public enum EventTileState: Sendable, Hashable { case idle, current, done }

public struct EventTile: Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var caption: String?
    public var state: EventTileState
    public var accessibilityLabel: String
    public init(id: Int, title: String, caption: String?, state: EventTileState, accessibilityLabel: String) {
        self.id = id; self.title = title; self.caption = caption; self.state = state; self.accessibilityLabel = accessibilityLabel
    }
}

public struct InstrumentEventTiles: View {
    private let tiles: [EventTile]
    private let height: CGFloat
    private let onSelect: (Int) -> Void

    public init(_ tiles: [EventTile], height: CGFloat = 37, onSelect: @escaping (Int) -> Void) {
        self.tiles = tiles; self.height = height; self.onSelect = onSelect
    }

    /// Rows for `count` tiles: one row up to six, else the fewest balanced rows of at most six (13 → 5 · 4 · 4).
    nonisolated public static func rows(count: Int) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let rowCount = (count + InstrumentMetrics.tileRowsBreak - 1) / InstrumentMetrics.tileRowsBreak
        var out: [Range<Int>] = []
        var start = 0
        for row in 0..<rowCount {
            let size = count / rowCount + (row < count % rowCount ? 1 : 0)
            out.append(start..<(start + size))
            start += size
        }
        return out
    }

    /// Vertical padding that brings a drawn tile's button up to the 44-pt minimum touch target.
    private var touchPad: CGFloat { Swift.max(0, (InstrumentMetrics.controlTarget - height) / 2) }

    public var body: some View {
        let rows = InstrumentEventTiles.rows(count: tiles.count)
        VStack(spacing: Swift.max(0, InstrumentMetrics.tileGap - 2 * touchPad)) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: InstrumentMetrics.tileGap) {
                    ForEach(tiles[rows[r]]) { tile in
                        EventTileButton(tile: tile, height: height, touchPad: touchPad) { onSelect(tile.id) }
                    }
                    if rows.count > 1, rows[r].count < rows[0].count {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
        .instrumentControlOwnsTouches(identifier: "eventTiles")
    }
}

private struct EventTileButton: View {
    let tile: EventTile
    let height: CGFloat
    let touchPad: CGFloat
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    private var ink: Color {
        switch tile.state {
        case .current: InstrumentPalette.actionCyan
        case .done: InstrumentPalette.actionAmber
        case .idle: InstrumentPalette.secondaryInk
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(tile.title)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let caption = tile.caption {
                    Text(caption)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 3)
            .padding(.top, 3)
            .padding(.bottom, 4 + InstrumentMetrics.subdivisionMark + 2)   // room for the state mark: it never crosses text
            .frame(maxWidth: .infinity, minHeight: height)
            .background(tile.state == .current ? InstrumentPalette.actionCyan.opacity(InstrumentOpacity.tileActiveFill)
                                               : .white.opacity(InstrumentOpacity.tileIdleFill),
                        in: .rect(cornerRadius: InstrumentMetrics.tileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: InstrumentMetrics.tileRadius)
                    .strokeBorder(border, lineWidth: InstrumentMetrics.panelStroke)
            }
            .overlay(alignment: .bottom) { mark }
            .padding(.vertical, touchPad)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(tile.accessibilityLabel)
        .accessibilityValue(tile.state == .current ? "current" : tile.state == .done ? "done" : "")
        .accessibilityAddTraits(tile.state == .current ? .isSelected : [])
        .accessibilityIdentifier("eventTile.\(tile.id)")
    }

    private var border: Color {
        switch tile.state {
        case .current: InstrumentPalette.actionCyan.opacity(InstrumentOpacity.tileActiveBorder)
        case .done: InstrumentPalette.actionAmber.opacity(contrast == .increased ? 0.5 : 0.22)
        case .idle: .white.opacity(contrast == .increased ? InstrumentOpacity.panelBorderIncreasedContrast : InstrumentOpacity.tileIdleBorder)
        }
    }

    /// The shape cue: a centred underline capsule for the current tile, a short leading capsule for a done tile.
    @ViewBuilder private var mark: some View {
        switch tile.state {
        case .current:
            Capsule().fill(InstrumentPalette.actionCyan)
                .frame(width: 14, height: InstrumentMetrics.subdivisionMark)
                .padding(.bottom, 4)
        case .done:
            Capsule().fill(InstrumentPalette.actionAmber.opacity(0.85))
                .frame(width: 6, height: InstrumentMetrics.subdivisionMark)
                .padding(.bottom, 4)
        case .idle:
            EmptyView()
        }
    }
}
