import Foundation

// OWNER: TESTIMAGES. `photo` · Your photo… (SPEC §11 #22). The app decodes the PhotosPicker data through the image's colour
// profile into linear premultiplied RGBA (App/Specimens/SpecimenPlatform.swift, ImageIO + Core Graphics) and hands the rows
// of the centre-cropped square to `PhotoSpecimen.canvas`, which AREA-AVERAGES them to the canvas size here, in BlurCore, so
// the resampling is plain, testable arithmetic. The resample is itself a box blur, so the caption engraves it:
// `PHOTO · RESAMPLED ×s (BOX)`. Every number on a photo is LIVE only (no ground truth), and lessons are disabled.

public enum PhotoSpecimen {
    /// The centre crop of a w × h image: the largest centred square (origin, side).
    public static func centreCrop(width w: Int, height h: Int) -> (x: Int, y: Int, side: Int) {
        let s = Swift.min(w, h)
        return ((w - s) / 2, (h - s) / 2, s)
    }

    /// The caption for a resample from `sourceSide` to `targetSide` pixels (scale = target/source).
    public static func caption(sourceSide: Int, targetSide: Int) -> String {
        let scale = Double(targetSide) / Double(Swift.max(1, sourceSide))
        return "PHOTO · RESAMPLED ×" + NumberStyle.decimals(2).text(scale) + " (BOX)"
    }

    /// Area-weighted (box) resampling of a square image of side `sourceSide` to `targetSide`: each output pixel is the
    /// average of the source treated as piecewise constant over the output pixel's footprint (exact overlap weights, so it
    /// works for shrinking and enlarging alike). `row(j)` returns source row j (linear premultiplied, `sourceSide` long);
    /// rows are requested once each, in order, so the caller can stream them.
    public static func areaAverage(sourceSide: Int, targetSide: Int, row: (Int) -> [SIMD4<Float>]) -> ImageBuffer {
        precondition(sourceSide > 0 && targetSide > 0)
        let weights = overlapWeights(sourceSide: sourceSide, targetSide: targetSide)   // per output index: (source index, w)
        // Horizontal pass per source row, then accumulate into output rows with the vertical weights (Double).
        var verticalBySource = [[(Int, Double)]](repeating: [], count: sourceSide)
        for (o, list) in weights.enumerated() { for (s, w) in list { verticalBySource[s].append((o, w)) } }
        var accum = [SIMD4<Double>](repeating: .zero, count: targetSide * targetSide)
        for j in 0..<sourceSide {
            let src = row(j)
            precondition(src.count == sourceSide)
            var horizontal = [SIMD4<Double>](repeating: .zero, count: targetSide)
            for (o, list) in weights.enumerated() {
                var sum = SIMD4<Double>.zero
                for (s, w) in list { sum += SIMD4<Double>(src[s]) * w }
                horizontal[o] = sum
            }
            for (o, w) in verticalBySource[j] {
                let base = o * targetSide
                for i in 0..<targetSide { accum[base + i] += horizontal[i] * w }
            }
        }
        return ImageBuffer(width: targetSide, height: targetSide, pixels: accum.map { SIMD4<Float>($0) })
    }

    /// For each output index, the source indices it overlaps and the normalised overlap weights (summing to 1).
    public static func overlapWeights(sourceSide: Int, targetSide: Int) -> [[(Int, Double)]] {
        let ratio = Double(sourceSide) / Double(targetSide)            // source pixels per output pixel
        return (0..<targetSide).map { o in
            let a = Double(o) * ratio, b = Double(o + 1) * ratio
            var list: [(Int, Double)] = []
            var s = Int(a.rounded(.down))
            while Double(s) < b && s < sourceSide {
                let overlap = Swift.min(b, Double(s + 1)) - Swift.max(a, Double(s))
                if overlap > 0 { list.append((s, overlap / ratio)) }
                s += 1
            }
            return list
        }
    }

    /// The photo canvas for a window size: the centre-cropped square, area-averaged to (N + 512)², default probe at c.
    public static func canvas(cropSide: Int, windowSize n: Int, margin m: Int = SpecimenGeometry.margin,
                              row: (Int) -> [SIMD4<Float>]) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m)
        let image = areaAverage(sourceSide: cropSide, targetSide: frame.side, row: row)
        return makeSpecimenCanvas(PhotoGenerator.id, frame, .standard, image: image, probe: frame.c,
                                  caption: caption(sourceSide: cropSide, targetSide: frame.side))
    }
}

/// The registry entry for `photo`. Without a chosen photo it returns an honest empty state (a uniform mid-grey canvas
/// engraved `NO PHOTO CHOSEN`); the app replaces it with `SpecimenPlatform.photoCanvas(from:windowSize:)`.
public struct PhotoGenerator: SpecimenGenerating {
    public init() {}
    public static let id: SpecimenID = "photo"
    public var descriptor: SpecimenDescriptor {
        SpecimenDescriptor(id: Self.id, menuName: "Your photo…",
                           reveals: "real content; every number is LIVE only, and lessons are disabled",
                           isHDR: false, isHighContrastPattern: false, supportsExposure: false, needsTextCoverage: false,
                           animated: false, options: [])
    }
    public func canvas(windowSize n: Int, margin m: Int, options: SpecimenOptions, text: TextCoverage?) -> SpecimenCanvas {
        let frame = SpecimenFrame(windowSize: n, margin: m)
        let image = ImageBuffer(width: frame.side, height: frame.side, fill: SIMD4(0.18, 0.18, 0.18, 1))
        return makeSpecimenCanvas(Self.id, frame, options, image: image, probe: frame.c, caption: "NO PHOTO CHOSEN")
    }
}
