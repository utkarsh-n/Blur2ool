import SwiftUI
import CoreGraphics
import BlurCore

// OWNER: FAM-F10 (minimal seed written by SKEL; frozen API, ARCHITECTURE §5.9). Offscreen renders of the REAL Apple effect
// for Tier S entries (review fixes P-31, P-39). Values from here are MEASURED · OFFSCREEN; on-screen equivalence is
// UNVERIFIED. Seed: nothing is rendered yet, so callers show NOT YET MEASURED (nil), never a number.
// TODO(FAM-F10): ImageRenderer on the real modifier/material at σ_equiv 4 px (PSF / STAR / EDGE) and the probe texel.
public enum SystemOffscreen {
    /// PSF / STAR / EDGE at σ_equiv 4 px through ImageRenderer on the real modifier/material; nil when the entry cannot
    /// be rendered offscreen (glass), and the card then reads NOT YET MEASURED.
    @MainActor public static func renderStrip(entry: CatalogEntry, displayScale: CGFloat) -> [ImageBuffer]? { nil }
    /// The Tier S PIXEL chip: renders the same specimen view through ImageRenderer and reads the probe texel; nil (chip
    /// shows "—" with the spoken reason) when the effect is not capturable offscreen.
    @MainActor public static func probeTexel(entry: CatalogEntry, configuration: RenderConfiguration, specimenImage: CGImage,
                                             displayScale: CGFloat) -> SIMD4<Float>? { nil }
}
