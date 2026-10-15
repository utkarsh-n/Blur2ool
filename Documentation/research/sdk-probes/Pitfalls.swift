import Metal
// Pitfall A: capture a non-Sendable MTLTexture in the @Sendable completion handler.
func readbackA(queue: any MTLCommandQueue, tex: any MTLTexture) {
    let cb = queue.makeCommandBuffer()!
    cb.addCompletedHandler { _ in
        var px = [Float](repeating: 0, count: tex.width * tex.height)
        px.withUnsafeMutableBytes { tex.getBytes($0.baseAddress!, bytesPerRow: tex.width * 4, from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0) }
    }
    cb.commit()
}
// Fix B: await completion with async API, then read back in the same isolation domain.
func readbackB(queue: any MTLCommandQueue, tex: any MTLTexture) async -> [Float] {
    let cb = queue.makeCommandBuffer()!
    cb.commit()
    await cb.completed()
    var px = [Float](repeating: 0, count: tex.width * tex.height)
    px.withUnsafeMutableBytes { tex.getBytes($0.baseAddress!, bytesPerRow: tex.width * 4, from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0) }
    return px
}
