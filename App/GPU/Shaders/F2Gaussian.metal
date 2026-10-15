#include "B2Shared.h"
// F2Gaussian.metal — OWNER: FAM-F2 (seeds written by SKEL). Prefix b2_f2_, function constants 24–31 (ARCHITECTURE §6.2).
// TODO(FAM-F2): 2-D direct, binomial, IIR (Young–van Vliet, Deriche), unsharp mask, DoG/XDoG kernels.

struct B2F2GaussParams { uint entries; uint width; uint height; uint pad; };

// Linear-sampled separable Gaussian, one direction per pass (B2_DIRECTION 0 = H, 1 = V).
// Table from BlurCore KernelMath.linearSampledTable: weights[0] centre, then one bilinear pair per entry.
// Tap order (binding for traces and CPU reconstructions): centre, +o1, −o1, +o2, −o2, …
fragment float4 b2_f2_gauss_linear_fs(B2VertexOut in [[stage_in]],
                                      texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]],
                                      constant B2F2GaussParams &P [[buffer(B2_BUF_PARAMS)]],
                                      constant float *weights [[buffer(B2_BUF_WEIGHTS)]],
                                      constant float *offsets [[buffer(B2_BUF_OFFSETS)]],
                                      device B2TraceHeader *trace [[buffer(B2_BUF_TRACE), function_constant(B2_TRACE_PROBE)]]) {
    uint2 pixel = uint2(in.position.xy);
    float2 dir = B2_DIRECTION == 0 ? float2(1.0f, 0.0f) : float2(0.0f, 1.0f);
    float2 centre = float2(pixel) + 0.5f;
    float4 c = b2_sample(src, centre, B2_EDGE_MODE);
    float4 sum = c * weights[0];                                   // @explain: the centre tap
    if (B2_TRACE_PROBE) b2_trace_tap(trace, pixel, centre, weights[0], 0.0f, c, sum, float4(0.0f));
    for (uint i = 1; i < P.entries; ++i) {
        float2 o = dir * offsets[i];
        float4 a = b2_sample(src, centre + o, B2_EDGE_MODE);       // @explain: one bilinear fetch blends two taps
        sum = fma(a, float4(weights[i]), sum);                     // @explain: explicit fma keeps traced = untraced
        if (B2_TRACE_PROBE) b2_trace_tap(trace, pixel, centre + o, weights[i], 0.0f, a, sum, float4(0.0f));
        float4 b = b2_sample(src, centre - o, B2_EDGE_MODE);
        sum = fma(b, float4(weights[i]), sum);
        if (B2_TRACE_PROBE) b2_trace_tap(trace, pixel, centre - o, weights[i], 0.0f, b, sum, float4(0.0f));
    }
    if (B2_TRACE_PROBE) b2_trace_final(trace, pixel, centre, sum);  // @explain: the value this pass stores
    return sum;
}

// Integer-tap separable Gaussian, one direction per pass (B2_DIRECTION 0 = H, 1 = V); renormalise-capable.
// Shared with other groups through BlurGPU GaussianPassEncoder (bindings frozen, ARCHITECTURE §6.1).
// weights[0 … 2r] for offsets −r … +r. Tap order (binding for traces): −r … +r.
fragment float4 b2_f2_gauss_separable_fs(B2VertexOut in [[stage_in]],
                                         texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]],
                                         constant B2F2GaussParams &P [[buffer(B2_BUF_PARAMS)]],
                                         constant float *weights [[buffer(B2_BUF_WEIGHTS)]],
                                         device B2TraceHeader *trace [[buffer(B2_BUF_TRACE), function_constant(B2_TRACE_PROBE)]]) {
    uint2 pixel = uint2(in.position.xy);
    int2 step = B2_DIRECTION == 0 ? int2(1, 0) : int2(0, 1);
    int n = B2_DIRECTION == 0 ? int(P.width) : int(P.height);
    int r = int(P.entries) / 2;
    float4 sum = float4(0.0f);
    float used = 0.0f;
    for (int i = 0; i <= 2 * r; ++i) {
        int2 p = int2(pixel) + step * (i - r);
        int along = B2_DIRECTION == 0 ? p.x : p.y;
        bool dropped = B2_EDGE_MODE == 4 && (along < 0 || along >= n);
        float4 v = dropped ? float4(0.0f) : b2_fetch(src, p, B2_EDGE_MODE == 4 ? 0u : B2_EDGE_MODE);
        float w = dropped ? 0.0f : weights[i];
        sum = (i == 0) ? v * w : fma(v, float4(w), sum);          // @explain: explicit fma keeps traced = untraced
        used += w;
        if (B2_TRACE_PROBE) b2_trace_tap(trace, pixel, float2(p) + 0.5f, w, dropped ? 1.0f : 0.0f, v, sum, float4(0.0f));
    }
    if (B2_EDGE_MODE == 4 && used > 0.0f) sum = sum / used;       // @explain: renormalise divides by the kept weight
    if (B2_TRACE_PROBE) b2_trace_final(trace, pixel, float2(pixel) + 0.5f, sum);
    return sum;
}

// Compute-tile separable Gaussian (gaussian-compute-tile, review fix E-15), one direction per dispatch: B2_DIRECTION 0 =
// rows (256 × 1 threadgroups), 1 = columns (1 × 256). Each threadgroup loads its segment of the line plus an apron of r
// texels on both sides into DYNAMIC threadgroup memory, (tile + 2r) × half4 = (256 + 2r) × 8 B
// (GaussianOperator.computeTileBytes; bound with GPUContext.dispatch2D(threadgroupMemory:) at index 0), then every thread
// sums 2r + 1 integer taps from the tile. The input is rgba16Float, so half4 holds every texel exactly. Accumulation and
// tap order (−r … +r) are those of b2_f2_gauss_separable_fs, so both variants store identical values; renormalise drops
// out-of-range taps and divides by the kept weight. Output needs .shaderWrite (not compressible on Apple9, REFERENCE).
struct B2F2TileParams { uint taps; uint width; uint height; uint pad; };

kernel void b2_f2_gauss_tile_k(texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]],
                               texture2d<float, access::write> dst [[texture(B2_TEX_DST)]],
                               constant B2F2TileParams &P [[buffer(B2_BUF_PARAMS)]],
                               constant float *weights [[buffer(B2_BUF_WEIGHTS)]],
                               device B2TraceHeader *trace [[buffer(B2_BUF_TRACE), function_constant(B2_TRACE_PROBE)]],
                               threadgroup half4 *tile [[threadgroup(0)]],
                               uint2 gid [[thread_position_in_grid]],
                               uint2 lid [[thread_position_in_threadgroup]],
                               uint2 tgSize [[threads_per_threadgroup]],
                               uint2 group [[threadgroup_position_in_grid]]) {
    const bool rows = B2_DIRECTION == 0;
    const int r = int(P.taps) / 2;
    const int n = rows ? int(P.width) : int(P.height);            // texels along the line
    const int lineSize = rows ? int(tgSize.x) : int(tgSize.y);    // threads along the line
    const int local = rows ? int(lid.x) : int(lid.y);
    const int start = (rows ? int(group.x) : int(group.y)) * lineSize;
    const int line = rows ? int(gid.y) : int(gid.x);
    const uint fetchMode = B2_EDGE_MODE == 4 ? 0u : B2_EDGE_MODE;
    for (int i = local; i < lineSize + 2 * r; i += lineSize) {     // @explain: cooperative load of the tile and its apron
        int along = start + i - r;
        int2 p = rows ? int2(along, line) : int2(line, along);
        bool outside = B2_EDGE_MODE == 4 && (along < 0 || along >= n);
        tile[i] = outside ? half4(0.0h) : half4(b2_fetch(src, p, fetchMode));
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);               // @explain: every load lands before any thread reads
    if (gid.x >= P.width || gid.y >= P.height) return;             // @explain: bounds check after the barrier (§4.4)
    const int me = start + local;
    float4 sum = float4(0.0f);
    float used = 0.0f;
    for (int i = 0; i <= 2 * r; ++i) {
        int along = me + i - r;
        bool dropped = B2_EDGE_MODE == 4 && (along < 0 || along >= n);
        float4 v = dropped ? float4(0.0f) : float4(tile[local + i]);
        float w = dropped ? 0.0f : weights[i];
        sum = (i == 0) ? v * w : fma(v, float4(w), sum);           // @explain: explicit fma keeps traced = untraced
        used += w;
        if (B2_TRACE_PROBE) {
            float2 at = rows ? float2(float(along), float(line)) : float2(float(line), float(along));
            b2_trace_tap(trace, gid, at + 0.5f, w, dropped ? 1.0f : 0.0f, v, sum, float4(0.0f));
        }
    }
    if (B2_EDGE_MODE == 4 && used > 0.0f) sum = sum / used;        // @explain: renormalise divides by the kept weight
    if (B2_TRACE_PROBE) b2_trace_final(trace, gid, float2(gid) + 0.5f, sum);
    dst.write(sum, gid);
}
