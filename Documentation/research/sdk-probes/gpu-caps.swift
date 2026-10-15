import Foundation
import Metal
guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { fatalError() }
print("device: \(d.name)")
var fams: [String] = []
for i in 1...10 { if let f = MTLGPUFamily(rawValue: 1000 + i), d.supportsFamily(f) { fams.append("apple\(i)") } }
if d.supportsFamily(.metal3) { fams.append("metal3") }
if let m4 = MTLGPUFamily(rawValue: 5002), d.supportsFamily(m4) { fams.append("metal4(5002)") }
print("families: \(fams.joined(separator: " "))")
print("hasUnifiedMemory=\(d.hasUnifiedMemory) maxBufferLength=\(d.maxBufferLength / (1 << 20)) MiB recommendedMaxWorkingSetSize=\(d.recommendedMaxWorkingSetSize / (1 << 20)) MiB")
print("supports32BitFloatFiltering=\(d.supports32BitFloatFiltering) readWriteTextureSupport(tier)=\(d.readWriteTextureSupport.rawValue) supportsQueryTextureLOD=\(d.supportsQueryTextureLOD)")
print("supportsFunctionPointers=\(d.supportsFunctionPointers) supportsDynamicLibraries=\(d.supportsDynamicLibraries) supportsShaderBarycentricCoordinates=\(d.supportsShaderBarycentricCoordinates)")
print("maxThreadsPerThreadgroup=\(d.maxThreadsPerThreadgroup.width) maxThreadgroupMemoryLength=\(d.maxThreadgroupMemoryLength) maxTextureWidth2D? (check family tables)")

let src = """
#include <metal_stdlib>
using namespace metal;
kernel void fill(texture2d<float, access::write> dst [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    // deliberately NO bounds check: with non-uniform dispatchThreads the grid is exact
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    dst.write(float4(1.0), gid);
}
kernel void rw(texture2d<float, access::read_write> t [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= t.get_width() || gid.y >= t.get_height()) return;
    t.write(t.read(gid) * 2.0, gid);
}
kernel void simdsum(device float *out [[buffer(0)]], uint tid [[thread_position_in_grid]], uint lane [[thread_index_in_simdgroup]]) {
    float s = simd_sum(float(lane));
    if (lane == 0) out[tid / 32] = s;
}
kernel void samp(texture2d<float> t [[texture(0)]], device float *out [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge, coord::pixel);
    out[0] = t.sample(s, float2(1.0, 0.5)).r;   // halfway between texel 0 (0.0) and texel 1 (1.0) centres -> 0.5 if filtered
}
"""
let lib = try d.makeLibrary(source: src, options: nil)
func p(_ n: String) throws -> any MTLComputePipelineState { try d.makeComputePipelineState(function: lib.makeFunction(name: n)!) }

// 1. non-uniform dispatchThreads 250x250 with 32x16 groups
do {
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 250, height: 250, mipmapped: false)
    td.usage = [.shaderWrite, .shaderRead]; td.storageMode = .shared
    let t = d.makeTexture(descriptor: td)!
    let cb = q.makeCommandBuffer()!; let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(try p("fill")); e.setTexture(t, index: 0)
    if ProcessInfo.processInfo.environment["USE_TG"] != nil { e.dispatchThreadgroups(MTLSize(width: 8, height: 16, depth: 1), threadsPerThreadgroup: MTLSize(width: 32, height: 16, depth: 1)) } else { e.dispatchThreads(MTLSize(width: 250, height: 250, depth: 1), threadsPerThreadgroup: MTLSize(width: 32, height: 16, depth: 1)) }
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    var a = [Float](repeating: 0, count: 250 * 250)
    a.withUnsafeMutableBytes { t.getBytes($0.baseAddress!, bytesPerRow: 1000, from: MTLRegionMake2D(0, 0, 250, 250), mipmapLevel: 0) }
    print("non-uniform dispatchThreads 250x250 (32x16): status=\(cb.status.rawValue) error=\(cb.error.map { "\($0)" } ?? "none") filled=\(a.filter { $0 == 1 }.count)/62500")
}
// 2. read_write texture
if ProcessInfo.processInfo.environment["SKIP_RW"] == nil {
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 64, height: 64, mipmapped: false)
    td.usage = [.shaderWrite, .shaderRead]; td.storageMode = .shared
    let t = d.makeTexture(descriptor: td)!
    let ones = [Float](repeating: 1.5, count: 64 * 64)
    ones.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 256) }
    let cb = q.makeCommandBuffer()!; let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(try p("rw")); e.setTexture(t, index: 0)
    e.dispatchThreadgroups(MTLSize(width: 2, height: 4, depth: 1), threadsPerThreadgroup: MTLSize(width: 32, height: 16, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    var a = [Float](repeating: 0, count: 64 * 64)
    a.withUnsafeMutableBytes { t.getBytes($0.baseAddress!, bytesPerRow: 256, from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0) }
    print("read_write r32Float: status=\(cb.status.rawValue) error=\(cb.error.map { "\($0)" } ?? "none") value=\(a[0]) (expect 3.0)")
}
// 3. simd_sum
do {
    let b = d.makeBuffer(length: 64, options: .storageModeShared)!
    let cb = q.makeCommandBuffer()!; let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(try p("simdsum")); e.setBuffer(b, offset: 0, index: 0)
    e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    let o = b.contents().bindMemory(to: Float.self, capacity: 2)
    print("simd_sum over 32 lanes: \(o[0]) \(o[1]) (expect 496)")
}
// 4. linear filtering of r32Float / rgba16Float
for fmt in (ProcessInfo.processInfo.environment["SKIP_F32"] == nil ? [MTLPixelFormat.r32Float, .r16Float] : [.r16Float]) {
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: 2, height: 1, mipmapped: false)
    td.usage = [.shaderRead]; td.storageMode = .shared
    let t = d.makeTexture(descriptor: td)!
    if fmt == .r32Float { let v: [Float] = [0, 1]; v.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) } }
    else { let v: [Float16] = [0, 1]; v.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4) } }
    let b = d.makeBuffer(length: 16, options: .storageModeShared)!
    let cb = q.makeCommandBuffer()!; let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(try p("samp")); e.setTexture(t, index: 0); e.setBuffer(b, offset: 0, index: 0)
    e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    print("linear sample \(fmt == .r32Float ? "r32Float" : "r16Float") at midpoint: \(b.contents().load(as: Float.self)) (0.5 = filtered, 0 or 1 = nearest)")
}
