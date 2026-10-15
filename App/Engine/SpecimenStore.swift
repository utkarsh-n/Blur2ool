import Foundation
import BlurCore

// OWNER: ENGINE (frozen public API, ARCHITECTURE §5.9). Generates specimen canvases off the main actor (a detached task
// on Sendable values) and caches them per id, options (always at 0 EV: exposure is applied at render time, review fix
// E-10) and window size. Concurrent requests for the same canvas share one generation. A canvas is (N + 512)² × 16 B of
// Float (31.6 MB at N = 894), so the cache keeps `byteBudget` bytes (least recently used dropped first, never the newest)
// and a memory warning drops all but the one in use. Text coverage comes from the app (SpecimenPlatform, Core Text); photos are
// installed as canvases of the window's size.

@MainActor
public final class SpecimenStore {
    public struct Key: Hashable, Sendable {
        public var id: SpecimenID
        public var options: SpecimenOptions
        public var windowSize: Int
    }
    /// Bytes of Float canvases kept in memory: about three full-size canvases (31.6 MB each at N = 894), or one plus the
    /// small 128-px canvases of a fingerprint strip (6.6 MB each), so opening a card never evicts the Bench's canvas.
    public static let byteBudget = 110_000_000

    private var cache: [Key: SpecimenCanvas] = [:]
    private var recency: [Key] = []
    private var inFlight: [Key: Task<SpecimenCanvas, Never>] = [:]
    private var photo: SpecimenCanvas?
    public init() {}

    public static func key(_ id: SpecimenID, options: SpecimenOptions, windowSize: Int) -> Key {
        Key(id: id, options: options.canvasOptions, windowSize: windowSize)
    }

    public func canvas(_ id: SpecimenID, options: SpecimenOptions, windowSize: Int) async -> SpecimenCanvas? {
        if id == "photo" { return photo.flatMap { $0.windowSize == windowSize ? $0 : nil } }
        let key = Self.key(id, options: options, windowSize: windowSize)
        if let cached = cache[key] { touch(key); return cached }
        if let pending = inFlight[key] { return await pending.value }
        guard let generator = SpecimenRegistry.generator(id) else { return nil }
        let text: TextCoverage? = generator.descriptor.needsTextCoverage
            ? SpecimenPlatform.textCoverage(canvasSide: SpecimenGeometry.canvasSide(windowSize: windowSize), margin: SpecimenGeometry.margin,
                                            options: key.options)
            : nil
        let canvasOptions = key.options
        let task = Task.detached(priority: .userInitiated) {
            generator.canvas(windowSize: windowSize, margin: SpecimenGeometry.margin, options: canvasOptions, text: text)
        }
        inFlight[key] = task
        let canvas = await task.value
        inFlight[key] = nil
        cache[key] = canvas
        touch(key)
        while recency.count > 1, cachedBytes > Self.byteBudget, let oldest = recency.first {
            recency.removeFirst()
            cache[oldest] = nil
        }
        return canvas
    }

    /// The cached canvas, without generating one.
    public func cached(_ id: SpecimenID, options: SpecimenOptions, windowSize: Int) -> SpecimenCanvas? {
        if id == "photo" { return photo.flatMap { $0.windowSize == windowSize ? $0 : nil } }
        return cache[Self.key(id, options: options, windowSize: windowSize)]
    }

    public func install(photo canvas: SpecimenCanvas) { photo = canvas }

    /// Memory warning: keep only the most recently used canvas (the one on screen).
    public func evict(keeping keep: Int = 1) {
        while recency.count > Swift.max(0, keep), let oldest = recency.first {
            recency.removeFirst()
            cache[oldest] = nil
        }
    }

    private var cachedBytes: Int { cache.values.reduce(0) { $0 + $1.image.pixels.count * MemoryLayout<SIMD4<Float>>.stride } }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
