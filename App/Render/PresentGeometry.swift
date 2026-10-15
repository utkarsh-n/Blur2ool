import Foundation
import BlurCore

// OWNER: UI-SPECIMEN (ARCHITECTURE §5.9, §6.5; SPEC §4.1.3, §8.3). The single source of truth for where a window pixel is
// drawn: the present shader (App/GPU/Shaders/B2Present.metal) only applies the origin and scale computed here, and the
// SwiftUI overlays (probe crosshair, handles, divider, loupe) and the touch layer use the same numbers, so a tap lands
// on the pixel the crosshair then marks, at every zoom.
//
// Coordinates: window pixels 0…N−1 (the specimen texture at full resolution, y down; a pixel's centre is +0.5); drawable
// pixels 0…D−1 (D = N for the Bench window, so zoom 1 is exactly 1 : 1); view points 0…side (the SwiftUI frame).
// window coordinate s = origin + d_px · texelsPerPixel, d_px = point · pixelsPerPoint.

/// Window ↔ drawable ↔ view-point mapping of one present view (Bench window, periscope or loupe).
public struct PresentGeometry: Sendable, Hashable {
    /// Window side N in device pixels (the full-resolution specimen texture).
    public var windowPixels: Int
    /// Drawable side D in pixels (N for the Bench window, 360 for a 120-pt periscope, 336 for the loupe at scale 3).
    public var drawablePixels: Int
    /// View side in points (the SwiftUI frame; 298 at 430 pt).
    public var viewPoints: Double
    /// Nearest magnification 1…8 (snapped to 1 · 2 · 4 · 8 after a pinch; live values in between while pinching).
    public var zoom: Double
    /// Centre of the magnified view in window pixels.
    public var zoomCentre: SIMD2<Double>
    /// A crop (periscope, loupe) replaces zoom: this window region fills the drawable.
    public var crop: PixelRegion?

    public static let zoomStops: [Double] = [1, 2, 4, 8]
    public static let maximumZoom = 8.0

    public init(windowPixels: Int, drawablePixels: Int, viewPoints: Double, zoom: Double = 1,
                zoomCentre: SIMD2<Double>? = nil, crop: PixelRegion? = nil) {
        self.windowPixels = Swift.max(1, windowPixels)
        self.drawablePixels = Swift.max(1, drawablePixels)
        self.viewPoints = viewPoints
        self.zoom = PresentGeometry.clampedZoom(zoom)
        self.zoomCentre = zoomCentre ?? SIMD2(repeating: Double(Swift.max(1, windowPixels)) / 2)
        self.crop = crop
    }

    /// Drawable pixels per view point (3 on the 15 Pro Max Bench window: 894 px in 298 pt).
    public var pixelsPerPoint: Double { Double(drawablePixels) / Swift.max(viewPoints, 1e-9) }

    /// Window pixels per drawable pixel: 1/zoom for the window (exactly 1 at zoom 1), crop side / D for a crop.
    public var texelsPerPixel: Double {
        if let crop { return Double(crop.size.width) / Double(drawablePixels) }
        return Double(windowPixels) / Double(drawablePixels) / zoom
    }

    /// How many window pixels the view shows along each axis.
    public var visibleWindowPixels: Double { Double(drawablePixels) * texelsPerPixel }

    /// Window coordinate of the drawable's top-left corner. Whole pixels, so every texel covers whole drawable pixels at
    /// integer zooms (nearest, never resampled); clamped so the view never shows outside the window.
    public var origin: SIMD2<Double> {
        if let crop { return SIMD2(Double(crop.origin.x), Double(crop.origin.y)) }
        let visible = visibleWindowPixels
        let maximum = Swift.max(0, (Double(windowPixels) - visible).rounded(.down))
        func axis(_ c: Double) -> Double { Swift.min(Swift.max((c - visible / 2).rounded(), 0), maximum) }
        return SIMD2(axis(zoomCentre.x), axis(zoomCentre.y))
    }

    /// The window coordinate (continuous) under a view point.
    public func windowCoordinate(atPoint p: SIMD2<Double>) -> SIMD2<Double> { origin + p * pixelsPerPoint * texelsPerPixel }

    /// The window pixel under a view point: the nearest output pixel centre a tap selects (clamped into the window).
    public func windowPixel(atPoint p: SIMD2<Double>) -> PixelPoint {
        let s = windowCoordinate(atPoint: p)
        let n = windowPixels - 1
        return PixelPoint(x: Swift.min(Swift.max(Int(s.x.rounded(.down)), 0), n), y: Swift.min(Swift.max(Int(s.y.rounded(.down)), 0), n))
    }

    /// The view point of a window coordinate (a pixel's centre is `PixelPoint.centre`).
    public func point(ofWindowCoordinate s: SIMD2<Double>) -> SIMD2<Double> { (s - origin) / texelsPerPixel / pixelsPerPoint }
    public func point(ofPixelCentre p: PixelPoint) -> SIMD2<Double> { point(ofWindowCoordinate: p.centre) }

    /// True when a view point lies inside the view (overlays hide what the zoom has scrolled away).
    public func contains(_ p: SIMD2<Double>) -> Bool { p.x >= 0 && p.y >= 0 && p.x <= viewPoints && p.y <= viewPoints }

    /// The zoom centre that keeps window coordinate `s` under view point `p` at zoom `z` (pinch about the fingers).
    public func zoomCentre(keeping s: SIMD2<Double>, under p: SIMD2<Double>, zoom z: Double) -> SIMD2<Double> {
        let zz = PresentGeometry.clampedZoom(z)
        let tpp = Double(windowPixels) / Double(drawablePixels) / zz
        let o = s - p * pixelsPerPoint * tpp
        return o + SIMD2(repeating: Double(drawablePixels) * tpp / 2)
    }

    /// The drawable column of the divider for a split 0…1 (nil = no divider): the input is strictly left of it.
    public func splitColumn(_ split: Double?) -> Int? {
        split.map { Int((Swift.min(Swift.max($0, 0), 1) * Double(drawablePixels)).rounded()) }
    }
    /// The divider's x in view points (where the hairline is drawn, exactly on the column boundary).
    public func splitPoint(_ split: Double?) -> Double? { splitColumn(split).map { Double($0) / pixelsPerPoint } }

    /// Line-up: each quadrant is ⌊D/2⌋ drawable pixels and shows the central crop of its slot's full-size output.
    public var lineUpQuadrantPixels: Int { drawablePixels / 2 }
    public var lineUpCropSide: Int { Int((Double(lineUpQuadrantPixels) * Double(windowPixels) / Double(drawablePixels)).rounded(.down)) }
    public var lineUpCropOrigin: Int { (windowPixels - lineUpCropSide) / 2 }
    /// The slot (0 A, 1 B, 2 C, 3 D) and window pixel under a view point in Line-up.
    public func lineUpPixel(atPoint p: SIMD2<Double>) -> (slot: Int, pixel: PixelPoint) {
        let d = p * pixelsPerPoint, q = Double(lineUpQuadrantPixels)
        let qx = d.x >= q ? 1 : 0, qy = d.y >= q ? 1 : 0
        let tpp = Double(windowPixels) / Double(drawablePixels)
        let s = SIMD2(Double(lineUpCropOrigin), Double(lineUpCropOrigin)) + (d - SIMD2(Double(qx), Double(qy)) * q) * tpp
        let n = windowPixels - 1
        return (qy * 2 + qx, PixelPoint(x: Swift.min(Swift.max(Int(s.x.rounded(.down)), 0), n), y: Swift.min(Swift.max(Int(s.y.rounded(.down)), 0), n)))
    }

    public static func clampedZoom(_ z: Double) -> Double { z.isFinite ? Swift.min(Swift.max(z, 1), maximumZoom) : 1 }
    /// The zoom a pinch settles on: the nearest of 1 · 2 · 4 · 8 in log₂ (SPEC §4.1.3).
    public static func snappedZoom(_ z: Double) -> Double {
        let l = log2(clampedZoom(z))
        return zoomStops.min { abs(log2($0) - l) < abs(log2($1) - l) } ?? 1
    }
}

/// The pan's rubber band (SPEC §4.1.3: ±256 px, rubber-banded): a request beyond the canvas margin moves the image by a
/// damped, whole-pixel amount (UIScrollView's curve), and springs back on release. Display only: the blur never sees it.
public enum PresentRubberBand {
    /// Pan range in specimen pixels (the canvas margin, SPEC §11 rule 2).
    public static var limit: Int { SpecimenGeometry.margin }
    /// The farthest the image can be dragged past the edge, in drawable pixels.
    public static let reach = 96.0
    /// Damped offset for an overflow (signed, in pixels): (1 − 1/(0.55·|x|/reach + 1)) · reach, never beyond `reach`.
    public static func offset(_ overflow: Double) -> Double {
        guard overflow != 0, overflow.isFinite else { return 0 }
        let magnitude = (1 - 1 / (0.55 * abs(overflow) / reach + 1)) * reach
        return overflow < 0 ? -magnitude : magnitude
    }
    /// The clamped pan and the display shift for a requested (unclamped) pan in specimen pixels. Panning content right
    /// lowers the pan, so the shift that shows the overflow has the opposite sign.
    public static func resolve(requested: SIMD2<Double>) -> (pan: PixelPoint, shift: SIMD2<Int32>) {
        let m = Double(limit)
        let clamped = SIMD2(Swift.min(Swift.max(requested.x.rounded(), -m), m), Swift.min(Swift.max(requested.y.rounded(), -m), m))
        let over = requested - clamped
        return (PixelPoint(x: Int(clamped.x), y: Int(clamped.y)),
                SIMD2(Int32(-offset(over.x).rounded()), Int32(-offset(over.y).rounded())))
    }
}

/// Field-for-field mirror of `B2PresentParams` in B2Present.metal (144 bytes; the shader static_asserts the size and the
/// phone AppTest checks this stride). Vectors first, then 32-bit scalars, so Swift and Metal agree on every offset.
struct PresentShaderParams {
    var backdrop = SIMD4<Float>(0, 0, 0, 1)
    var contour = SIMD4<Float>(0, 0, 0, 0)
    var ratioAB = SIMD4<Float>(1, 1, 1, 1)
    var ratioCD = SIMD4<Float>(1, 1, 1, 1)
    var origin = SIMD2<Float>(0, 0)
    var texelsPerPixel = SIMD2<Float>(1, 1)
    var lineUpOrigin = SIMD2<Float>(0, 0)
    var drawableSize = SIMD2<Float>(0, 0)
    var shift = SIMD2<Int32>(0, 0)
    var splitColumn: Int32 = -1
    var mode: UInt32 = 0
    var edr: UInt32 = 0
    var available: UInt32 = 0
    var gain: Float = 1
    var contourStep: Float = 0
    var showB: UInt32 = 0
    var reserved0: UInt32 = 0
    var reserved1: UInt32 = 0
    var reserved2: UInt32 = 0

    static let expectedStride = 144

    enum Mode: UInt32 { case output = 0, wipe, flip, difference, lineUp, crop }
    static let hasA: UInt32 = 1, hasB: UInt32 = 2, hasC: UInt32 = 4, hasD: UInt32 = 8
}
