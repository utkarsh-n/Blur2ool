import SwiftUI
import CoreGraphics
import BlurCore

// OWNER: FAM-F10 (minimal seed written by SKEL; frozen initialiser, ARCHITECTURE §5.9 / AppContract/System). The Tier S
// window content. Seed: shows the supplied model view and engraves that the Apple half is not built yet.
// TODO(FAM-F10): for `swiftui-layer-blur` a real SwiftUI Image with Apple's `.blur(radius:opaque:)` left of a wipe and our
// MODELED Metal model right; for `liquid-glass` / `apple-uiblureffect` the SwiftUI-drawn material-backdrop specimen with
// native glass or a Material over it, draggable by its 44-pt grip.
public struct SystemExhibitView<Model: View>: View {
    private let entry: CatalogEntry
    private let model: Model
    public init(entry: CatalogEntry, configuration: RenderConfiguration, specimenImage: CGImage?, displayScale: CGFloat,
                split: Double, @ViewBuilder model: () -> Model) {
        self.entry = entry; self.model = model()
    }
    public var body: some View {
        ZStack(alignment: .bottom) {
            model
            Text("\(entry.displayName.uppercased()) · APPLE HALF NOT YET BUILT").font(.system(.caption2, design: .monospaced))
                .foregroundStyle(InstrumentPalette.secondaryInk).padding(6)
        }
    }
}
