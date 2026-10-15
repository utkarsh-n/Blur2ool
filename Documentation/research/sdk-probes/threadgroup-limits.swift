import Foundation
import Metal
let d = MTLCreateSystemDefaultDevice()!, q = d.makeCommandQueue()!
let lib = try d.makeLibrary(source: """
#include <metal_stdlib>
using namespace metal;
kernel void k(device float *out [[buffer(0)]], threadgroup float *s [[threadgroup(0)]],
              uint lid [[thread_position_in_threadgroup]], uint n [[threads_per_threadgroup]]) {
    s[lid] = float(lid); threadgroup_barrier(mem_flags::mem_threadgroup); out[lid] = s[(lid + 1) % n] + 1.0;
}
// static threadgroup array of 24 KB (exceeds 16 KB)
kernel void big(device float *out [[buffer(0)]], uint lid [[thread_position_in_threadgroup]]) {
    threadgroup float s[6144];
    s[lid] = float(lid); threadgroup_barrier(mem_flags::mem_threadgroup); out[lid] = s[6143 - lid];
}
""", options: nil)
let p = try d.makeComputePipelineState(function: lib.makeFunction(name: "k")!)
let b = d.makeBuffer(length: 8192, options: .storageModeShared)!
for (threads, bytes) in [(1024, 4096), (512, 32768)] {
    let cb = q.makeCommandBuffer()!, e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(p); e.setBuffer(b, offset: 0, index: 0); e.setThreadgroupMemoryLength(bytes, index: 0)
    e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    print("\(threads) threads, \(bytes) B dynamic tg mem: status=\(cb.status.rawValue) error=\(cb.error.map { "\($0.localizedDescription)" } ?? "none") out[1]=\(b.contents().load(fromByteOffset: 4, as: Float.self))")
}
do {
    let pb = try d.makeComputePipelineState(function: lib.makeFunction(name: "big")!)
    print("static 24 KB tg array: pipeline created, staticThreadgroupMemoryLength=\(pb.staticThreadgroupMemoryLength) maxTotalThreadsPerThreadgroup=\(pb.maxTotalThreadsPerThreadgroup)")
} catch { print("static 24 KB tg array: pipeline creation FAILED: \(error.localizedDescription)") }
