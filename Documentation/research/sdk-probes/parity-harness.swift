// Blur2ool parity-harness probe: compile .metal SOURCE at runtime, run 2D convolution on a 256x256 r32Float
// texture, read back, compare with CPU loops. Runs on macOS (swiftc) and inside the iOS simulator (simctl spawn).
import Foundation
import Metal

let W = 256, H = 256
let source = #"""
#include <metal_stdlib>
using namespace metal;

// Naive 2D convolution, float, clamp-to-edge, weights (2R+1)^2 row-major.
kernel void conv2d_f32(texture2d<float, access::read>  src [[texture(0)]],
                       texture2d<float, access::write> dst [[texture(1)]],
                       constant float *w [[buffer(0)]],
                       constant int &R   [[buffer(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    int Wd = src.get_width(), Hd = src.get_height();
    if (gid.x >= uint(Wd) || gid.y >= uint(Hd)) return;
    float acc = 0.0f;
    int n = 2 * R + 1;
    for (int j = -R; j <= R; ++j) {
        int y = clamp(int(gid.y) + j, 0, Hd - 1);
        for (int i = -R; i <= R; ++i) {
            int x = clamp(int(gid.x) + i, 0, Wd - 1);
            acc += w[(j + R) * n + (i + R)] * src.read(uint2(x, y)).r;
        }
    }
    dst.write(float4(acc, 0, 0, 1), gid);
}

// Separable 1D pass (dir = (1,0) or (0,1)).
kernel void sep_f32(texture2d<float, access::read>  src [[texture(0)]],
                    texture2d<float, access::write> dst [[texture(1)]],
                    constant float *w [[buffer(0)]],
                    constant int &R   [[buffer(1)]],
                    constant int2 &dir [[buffer(2)]],
                    uint2 gid [[thread_position_in_grid]]) {
    int Wd = src.get_width(), Hd = src.get_height();
    if (gid.x >= uint(Wd) || gid.y >= uint(Hd)) return;
    float acc = 0.0f;
    for (int k = -R; k <= R; ++k) {
        int x = clamp(int(gid.x) + k * dir.x, 0, Wd - 1);
        int y = clamp(int(gid.y) + k * dir.y, 0, Hd - 1);
        acc += w[k + R] * src.read(uint2(x, y)).r;
    }
    dst.write(float4(acc, 0, 0, 1), gid);
}

// Same separable pass, but Gaussian weights evaluated IN THE SHADER with exp() (fast-math sensitivity test).
kernel void sep_exp_f32(texture2d<float, access::read>  src [[texture(0)]],
                        texture2d<float, access::write> dst [[texture(1)]],
                        constant float &sigma [[buffer(0)]],
                        constant int &R   [[buffer(1)]],
                        constant int2 &dir [[buffer(2)]],
                        uint2 gid [[thread_position_in_grid]]) {
    int Wd = src.get_width(), Hd = src.get_height();
    if (gid.x >= uint(Wd) || gid.y >= uint(Hd)) return;
    float acc = 0.0f, norm = 0.0f;
    for (int k = -R; k <= R; ++k) {
        float wk = exp(-0.5f * float(k * k) / (sigma * sigma));
        int x = clamp(int(gid.x) + k * dir.x, 0, Wd - 1);
        int y = clamp(int(gid.y) + k * dir.y, 0, Hd - 1);
        acc += wk * src.read(uint2(x, y)).r;
        norm += wk;
    }
    dst.write(float4(acc / norm, 0, 0, 1), gid);
}

// Threadgroup-tiled horizontal pass in half precision (probe 1 kernel).
constant int TILE = 16;
constant int MAXR = 16;
kernel void gaussH_tg(texture2d<half, access::read>  src [[texture(0)]],
                      texture2d<half, access::write> dst [[texture(1)]],
                      constant float *weights [[buffer(0)]],
                      constant int   &radius  [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]],
                      uint2 lid [[thread_position_in_threadgroup]],
                      uint2 tgid [[threadgroup_position_in_grid]]) {
    threadgroup half4 tile[TILE][TILE + 2 * MAXR];
    int w = src.get_width(), h = src.get_height();
    int y = min(int(gid.y), h - 1);
    int x0 = int(tgid.x) * TILE - MAXR;
    for (int i = int(lid.x); i < TILE + 2 * MAXR; i += TILE) {
        int sx = clamp(x0 + i, 0, w - 1);
        tile[lid.y][i] = src.read(uint2(sx, y));
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (gid.x >= uint(w) || gid.y >= uint(h)) return;
    half4 acc = half4(0);
    for (int k = -radius; k <= radius; ++k)
        acc += tile[lid.y][int(lid.x) + MAXR + k] * half(weights[k + radius]);
    dst.write(acc, gid);
}
"""#

func gaussian1D(sigma: Double, R: Int) -> [Float] {
    var w = (-R...R).map { exp(-0.5 * Double($0 * $0) / (sigma * sigma)) }
    let s = w.reduce(0, +); w = w.map { $0 / s }
    return w.map(Float.init)
}

// ---- CPU references ----
func cpuConv2D(_ img: [Float], _ w: [Float], R: Int, double: Bool) -> [Float] {
    var out = [Float](repeating: 0, count: W * H)
    let n = 2 * R + 1
    for y in 0..<H { for x in 0..<W {
        if double {
            var acc = 0.0
            for j in -R...R { let yy = min(max(y + j, 0), H - 1)
                for i in -R...R { let xx = min(max(x + i, 0), W - 1)
                    acc += Double(w[(j + R) * n + (i + R)]) * Double(img[yy * W + xx]) } }
            out[y * W + x] = Float(acc)
        } else {
            var acc: Float = 0
            for j in -R...R { let yy = min(max(y + j, 0), H - 1)
                for i in -R...R { let xx = min(max(x + i, 0), W - 1)
                    acc += w[(j + R) * n + (i + R)] * img[yy * W + xx] } }
            out[y * W + x] = acc
        }
    } }
    return out
}
func cpuSep(_ img: [Float], _ w: [Float], R: Int, dx: Int, dy: Int) -> [Float] {
    var out = [Float](repeating: 0, count: W * H)
    for y in 0..<H { for x in 0..<W {
        var acc = 0.0
        for k in -R...R {
            let xx = min(max(x + k * dx, 0), W - 1), yy = min(max(y + k * dy, 0), H - 1)
            acc += Double(w[k + R]) * Double(img[yy * W + xx])
        }
        out[y * W + x] = Float(acc)
    } }
    return out
}

// ---- GPU setup ----
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("no Metal device") }
print("device: \(device.name)")
print("maxThreadsPerThreadgroup: \(device.maxThreadsPerThreadgroup.width)x\(device.maxThreadsPerThreadgroup.height)x\(device.maxThreadsPerThreadgroup.depth)")
print("maxThreadgroupMemoryLength: \(device.maxThreadgroupMemoryLength) B")
for (name, fam) in [("apple7", MTLGPUFamily.apple7), ("apple8", .apple8), ("apple9", .apple9), ("metal3", .metal3)] {
    print("supportsFamily(.\(name)): \(device.supportsFamily(fam))")
}
print("readWriteTextureSupport: \(device.readWriteTextureSupport.rawValue)  argumentBuffersSupport: \(device.argumentBuffersSupport.rawValue)")
print("supportsNonuniformThreadgroups (apple4+ proxy): \(device.supportsFamily(.apple4))")

func makeLib(_ mode: MTLMathMode, _ fns: MTLMathFloatingPointFunctions) throws -> (any MTLLibrary, Double) {
    let opts = MTLCompileOptions()
    opts.mathMode = mode
    opts.mathFloatingPointFunctions = fns
    let t0 = Date()
    let lib = try device.makeLibrary(source: source, options: opts)
    return (lib, Date().timeIntervalSince(t0) * 1000)
}
let (libFast, msFast) = try makeLib(.fast, .fast)
let (libSafe, msSafe) = try makeLib(.safe, .precise)
print(String(format: "makeLibrary(source:) compile: fast %.1f ms, safe %.1f ms", msFast, msSafe))
print("default MTLCompileOptions(): languageVersion=0x\(String(MTLCompileOptions().languageVersion.rawValue, radix: 16)) mathMode=\(MTLCompileOptions().mathMode.rawValue) fpFunctions=\(MTLCompileOptions().mathFloatingPointFunctions.rawValue)")

func pso(_ lib: any MTLLibrary, _ name: String) throws -> any MTLComputePipelineState {
    try device.makeComputePipelineState(function: lib.makeFunction(name: name)!)
}
func makeTex(_ fmt: MTLPixelFormat = .r32Float) -> any MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: W, height: H, mipmapped: false)
    d.usage = [.shaderRead, .shaderWrite]
    d.storageMode = .shared
    return device.makeTexture(descriptor: d)!
}
func upload(_ t: any MTLTexture, _ a: [Float]) {
    a.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: W * 4) }
}
func download(_ t: any MTLTexture) -> [Float] {
    var a = [Float](repeating: 0, count: W * H)
    a.withUnsafeMutableBytes { t.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
    return a
}
func maxAbs(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).map { abs($0 - $1) }.max()! }

// Deterministic test image: LCG noise in [0,1] plus an impulse and a step edge.
var seed: UInt32 = 12345
var img = [Float](repeating: 0, count: W * H)
for i in 0..<(W * H) { seed = seed &* 1664525 &+ 1013904223; img[i] = Float(seed >> 8) / Float(1 << 24) }
for y in 0..<H { for x in 200..<W { img[y * W + x] = 1 } }
img[128 * W + 64] = 50   // impulse

func dispatch(_ p: any MTLComputePipelineState, _ enc: any MTLComputeCommandEncoder, tg: MTLSize? = nil) {
    // dispatchThreadgroups (+ bounds checks in every kernel) instead of dispatchThreads: the iOS simulator
    // GPU (Apple2 family) does not support non-uniform threadgroups and Metal API validation aborts on dispatchThreads.
    let w = p.threadExecutionWidth, h = max(1, min(p.maxTotalThreadsPerThreadgroup / w, 16))
    let t = tg ?? MTLSize(width: w, height: h, depth: 1)
    enc.dispatchThreadgroups(MTLSize(width: (W + t.width - 1) / t.width, height: (H + t.height - 1) / t.height, depth: 1), threadsPerThreadgroup: t)
}
func timeGPU(runs: Int = 21, _ encode: (any MTLCommandBuffer) -> Void) -> (median: Double, min: Double) {
    var ts: [Double] = []
    for _ in 0..<runs {
        let cb = queue.makeCommandBuffer()!
        encode(cb); cb.commit(); cb.waitUntilCompleted()
        ts.append((cb.gpuEndTime - cb.gpuStartTime) * 1000)
    }
    let s = ts.sorted(); return (s[s.count / 2], s[0])
}

let src = makeTex(), dst = makeTex(), tmp = makeTex()
upload(src, img)

// ---- Test 1: 2D convolution, R = 4 and R = 8 (Gaussian outer product) ----
for (R, sigma) in [(4, 1.5), (8, 3.0)] {
    let g = gaussian1D(sigma: sigma, R: R)
    var w2 = [Float](); for j in 0..<(2 * R + 1) { for i in 0..<(2 * R + 1) { w2.append(g[j] * g[i]) } }
    let p = try pso(libFast, "conv2d_f32")
    var Rv = Int32(R)
    let t = timeGPU { cb in
        let e = cb.makeComputeCommandEncoder()!
        e.setComputePipelineState(p); e.setTexture(src, index: 0); e.setTexture(dst, index: 1)
        e.setBytes(w2, length: w2.count * 4, index: 0); e.setBytes(&Rv, length: 4, index: 1)
        dispatch(p, e); e.endEncoding()
    }
    let gpu = download(dst)
    let c0 = ContinuousClock.now
    let cpuD = cpuConv2D(img, w2, R: R, double: true)
    let cpuMs = Double((ContinuousClock.now - c0).components.attoseconds) / 1e15 + Double((ContinuousClock.now - c0).components.seconds) * 1000
    let cpuF = cpuConv2D(img, w2, R: R, double: false)
    print(String(format: "conv2d R=%d (%dx%d taps): maxAbs vs CPU-double %.3e, vs CPU-float %.3e | GPU median %.4f ms (min %.4f) | CPU-double loop %.1f ms",
                 R, 2*R+1, 2*R+1, maxAbs(gpu, cpuD), maxAbs(gpu, cpuF), t.median, t.min, cpuMs))
}

// ---- Test 2: separable H+V, R = 12, sigma 4; precomputed weights vs in-shader exp (fast vs safe) ----
do {
    let R = 12, sigma = 4.0
    let g = gaussian1D(sigma: sigma, R: R)
    let cpu = cpuSep(cpuSep(img, g, R: R, dx: 1, dy: 0), g, R: R, dx: 0, dy: 1)
    var Rv = Int32(R)
    for (label, lib) in [("fast", libFast), ("safe", libSafe)] {
        let p = try pso(lib, "sep_f32"), pe = try pso(lib, "sep_exp_f32")
        let t = timeGPU { cb in
            for (a, b, d) in [(src, tmp, SIMD2<Int32>(1, 0)), (tmp, dst, SIMD2<Int32>(0, 1))] {
                var dir = d
                let e = cb.makeComputeCommandEncoder()!
                e.setComputePipelineState(p); e.setTexture(a, index: 0); e.setTexture(b, index: 1)
                e.setBytes(g, length: g.count * 4, index: 0); e.setBytes(&Rv, length: 4, index: 1); e.setBytes(&dir, length: 8, index: 2)
                dispatch(p, e); e.endEncoding()
            }
        }
        let gpuW = download(dst)
        var sg = Float(sigma)
        let cb = queue.makeCommandBuffer()!
        for (a, b, d) in [(src, tmp, SIMD2<Int32>(1, 0)), (tmp, dst, SIMD2<Int32>(0, 1))] {
            var dir = d
            let e = cb.makeComputeCommandEncoder()!
            e.setComputePipelineState(pe); e.setTexture(a, index: 0); e.setTexture(b, index: 1)
            e.setBytes(&sg, length: 4, index: 0); e.setBytes(&Rv, length: 4, index: 1); e.setBytes(&dir, length: 8, index: 2)
            dispatch(pe, e); e.endEncoding()
        }
        cb.commit(); cb.waitUntilCompleted()
        let gpuE = download(dst)
        print(String(format: "separable R=12 σ=4 [%@ math]: weights-in-buffer maxAbs %.3e | in-shader exp() maxAbs %.3e | GPU H+V median %.4f ms (min %.4f)",
                     label, maxAbs(gpuW, cpu), maxAbs(gpuE, cpu), t.median, t.min))
    }
}

// ---- Test 3: threadgroup-tiled half-precision H pass, R = 8 ----
do {
    let R = 8, g = gaussian1D(sigma: 3.0, R: R)
    let cpu = cpuSep(img, g, R: R, dx: 1, dy: 0)
    let p = try pso(libFast, "gaussH_tg")
    var Rv = Int32(R)
    let t = timeGPU { cb in
        let e = cb.makeComputeCommandEncoder()!
        e.setComputePipelineState(p); e.setTexture(src, index: 0); e.setTexture(dst, index: 1)
        e.setBytes(g, length: g.count * 4, index: 0); e.setBytes(&Rv, length: 4, index: 1)
        e.dispatchThreadgroups(MTLSize(width: (W + 15) / 16, height: (H + 15) / 16, depth: 1),
                               threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        e.endEncoding()
    }
    let gpu = download(dst)
    // relative error matters for half: compare on the [0,1] noise region only (exclude the 50.0 impulse row)
    var mx: Float = 0
    for y in 0..<H where y != 128 { for x in 0..<W { mx = max(mx, abs(gpu[y * W + x] - cpu[y * W + x])) } }
    print(String(format: "threadgroup half H-pass R=8: staticTGmem=%d B, maxAbs (rows without impulse) %.3e, impulse row maxAbs %.3e | GPU median %.4f ms",
                 p.staticThreadgroupMemoryLength, mx, maxAbs(Array(gpu[(128*W)..<(129*W)]), Array(cpu[(128*W)..<(129*W)])), t.median))
    print("gaussH_tg pipeline: threadExecutionWidth=\(p.threadExecutionWidth) maxTotalThreadsPerThreadgroup=\(p.maxTotalThreadsPerThreadgroup)")
}
for name in ["conv2d_f32", "sep_f32"] {
    let p = try pso(libFast, name)
    print("\(name) pipeline: threadExecutionWidth=\(p.threadExecutionWidth) maxTotalThreadsPerThreadgroup=\(p.maxTotalThreadsPerThreadgroup)")
}

// ---- Test 4: threadgroup memory limit probe: request dynamic threadgroup memory of increasing size ----
let tgSrc = """
#include <metal_stdlib>
using namespace metal;
kernel void tgprobe(device float *out [[buffer(0)]], threadgroup float *scratch [[threadgroup(0)]],
                    uint lid [[thread_position_in_threadgroup]], uint n [[threads_per_threadgroup]]) {
    scratch[lid] = float(lid);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    out[lid] = scratch[(lid + 1) % n];
}
"""
let tgLib = try device.makeLibrary(source: tgSrc, options: nil)
let tgP = try device.makeComputePipelineState(function: tgLib.makeFunction(name: "tgprobe")!)
print("tgprobe pipeline maxTotalThreadsPerThreadgroup=\(tgP.maxTotalThreadsPerThreadgroup)")
let outB = device.makeBuffer(length: 4096 * 4, options: .storageModeShared)!
for (threads, bytes) in [(256, 16384), (512, 16384), (1024, 16384), (256, 32768), (1024, 32768)] {
    guard threads <= tgP.maxTotalThreadsPerThreadgroup, bytes <= device.maxThreadgroupMemoryLength else {
        print("tg \(threads) threads / \(bytes) B: SKIPPED (exceeds reported limit)"); continue
    }
    let cb = queue.makeCommandBuffer()!
    let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(tgP); e.setBuffer(outB, offset: 0, index: 0)
    e.setThreadgroupMemoryLength(bytes, index: 0)
    e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    let o = outB.contents().bindMemory(to: Float.self, capacity: threads)
    print("tg \(threads) threads / \(bytes) B: status=\(cb.status.rawValue) err=\(cb.error?.localizedDescription ?? "none") out[0]=\(o[0]) out[last]=\(o[threads-1])")
}
