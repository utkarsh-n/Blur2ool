import Foundation
import Metal
import MetalPerformanceShaders
let d = MTLCreateSystemDefaultDevice()!, q = d.makeCommandQueue()!
print("device: \(d.name)")
print("counterSets: \((d.counterSets ?? []).map { "\($0.name)[\($0.counters.map(\.name).joined(separator: ","))]" })")
let pts: [(String, MTLCounterSamplingPoint)] = [("stage", .atStageBoundary), ("draw", .atDrawBoundary), ("dispatch", .atDispatchBoundary), ("tileDispatch", .atTileDispatchBoundary), ("blit", .atBlitBoundary)]
print("supportsCounterSampling: " + pts.map { "\($0.0)=\(d.supportsCounterSampling($0.1))" }.joined(separator: " "))
print("MPSSupportsMTLDevice: \(MPSSupportsMTLDevice(d))")
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1024, height: 1024, mipmapped: false)
td.usage = [.shaderRead, .shaderWrite]; td.storageMode = .private
let a = d.makeTexture(descriptor: td)!, b = d.makeTexture(descriptor: td)!
for sigma: Float in [2, 8, 32] {
    let g = MPSImageGaussianBlur(device: d, sigma: sigma); g.edgeMode = .clamp
    var ts: [Double] = []
    for _ in 0..<9 {
        let cb = q.makeCommandBuffer()!; g.encode(commandBuffer: cb, sourceTexture: a, destinationTexture: b)
        cb.commit(); cb.waitUntilCompleted(); ts.append((cb.gpuEndTime - cb.gpuStartTime) * 1000)
    }
    print(String(format: "MPSImageGaussianBlur σ=%.0f 1024² rgba16Float: best %.3f ms, median %.3f ms (n=9)", sigma, ts.min()!, ts.sorted()[4]))
}
// stage-boundary timestamps on a compute pass
if d.supportsCounterSampling(.atStageBoundary), let ts = d.counterSets?.first(where: { $0.name == MTLCommonCounterSet.timestamp.rawValue }) {
    let sd = MTLCounterSampleBufferDescriptor(); sd.counterSet = ts; sd.sampleCount = 2; sd.storageMode = .shared
    let sb = try d.makeCounterSampleBuffer(descriptor: sd)
    let pd = MTLComputePassDescriptor()
    pd.sampleBufferAttachments[0].sampleBuffer = sb
    pd.sampleBufferAttachments[0].startOfEncoderSampleIndex = 0
    pd.sampleBufferAttachments[0].endOfEncoderSampleIndex = 1
    let cb = q.makeCommandBuffer()!
    let g = MPSImageGaussianBlur(device: d, sigma: 8)
    let e = cb.makeComputeCommandEncoder(descriptor: pd)!; e.endEncoding()   // empty pass just to sample
    g.encode(commandBuffer: cb, sourceTexture: a, destinationTexture: b)
    cb.commit(); cb.waitUntilCompleted()
    let data = try sb.resolveCounterRange(0..<2)
    print("stage-boundary sample buffer resolved \(data?.count ?? 0) bytes")
} else { print("stage-boundary timestamp sampling: not available") }
