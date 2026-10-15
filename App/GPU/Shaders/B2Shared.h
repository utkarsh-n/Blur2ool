// B2Shared.h — Blur2ool shared Metal header. FROZEN (ARCHITECTURE.md §6.2); change only through build/requests/.
// Every App/GPU/Shaders/*.metal starts with exactly the line   #include "B2Shared.h"
// blur-gpucheck removes that line and prepends this file once (runtime compilation cannot resolve quoted includes),
// so this header uses include guards and every file-scope symbol in a family file carries that file's prefix.
#ifndef B2_SHARED_H
#define B2_SHARED_H
#include <metal_stdlib>
using namespace metal;

// ---- Function constants 0–15 are shared (Swift: FunctionConstants.metalValues() always sets 0–3) ----
constant bool B2_TRACE_PROBE    [[function_constant(0)]];  // record the probe's taps (traced specialization)
constant bool B2_HALF_ACCUM     [[function_constant(1)]];  // fp16 accumulation: the Compare › Precision lesson only
constant uint B2_EDGE_MODE      [[function_constant(2)]];  // 0 clamp, 1 mirror, 2 wrap, 3 zero, 4 renormalise
constant uint B2_DIRECTION      [[function_constant(3)]];  // 0 horizontal, 1 vertical, 2+ family-defined
constant bool B2_COLOUR_SRGB    [[function_constant(4)]];  // B2Common colour pass only
constant bool B2_ALPHA_STRAIGHT [[function_constant(5)]];  // B2Common colour pass only
constant bool B2_COLOUR_POST    [[function_constant(6)]];  // B2Common colour pass only
// 7–15 reserved. Family files own blocks of 8 from 16 upward (ARCHITECTURE §6.2 table); never declare them here.

// ---- Binding indices ----
#define B2_BUF_PARAMS   0   // per-pass parameter struct (setBytes ≤ 4 KB)
#define B2_BUF_WEIGHTS  1   // float weights (BlurCore Double → Float, the exact numbers the Kernel floor shows)
#define B2_BUF_OFFSETS  2   // float offsets (linear-sampled and fractional taps)
#define B2_BUF_AUX0     3   // family-specific
#define B2_BUF_AUX1     4   // family-specific
#define B2_BUF_TRACE    5   // trace block of this pass (only when B2_TRACE_PROBE)
#define B2_TEX_SRC      0
#define B2_TEX_DST      1   // compute passes only (fragment passes return their colour)
#define B2_TEX_AUX0     2
#define B2_TEX_AUX1     3
#define B2_TEX_AUX2     4

// ---- Edge index mapping: identical to BlurCore EdgeMode.map(_:count:). -1 = contributes zero / dropped. ----
static inline int b2_map_index(int i, int n, uint mode) {
    if (i >= 0 && i < n) return i;
    switch (mode) {
        case 0: return clamp(i, 0, n - 1);
        case 1: { int p = 2 * n; int j = ((i % p) + p) % p; return j < n ? j : p - 1 - j; }
        case 2: return ((i % n) + n) % n;
        default: return -1;
    }
}

// Integer fetch with the edge mapping (no filtering; any float format, including 32-bit).
static inline float4 b2_fetch(texture2d<float, access::sample> t, int2 p, uint mode) {
    int x = b2_map_index(p.x, int(t.get_width()), mode);
    int y = b2_map_index(p.y, int(t.get_height()), mode);
    if (x < 0 || y < 0) return float4(0.0f);
    return t.read(uint2(x, y));
}

// Filtered fetch at texel coordinates (centres at i + 0.5, as BlurCore ImageBuffer.bilinear). rgba16Float only, never
// 32-bit float. coord::pixel allows only clamp modes, so samplers use normalized coordinates. renormalise → clamp.
constexpr sampler b2_sampler_clamp (coord::normalized, address::clamp_to_edge,   filter::linear);
constexpr sampler b2_sampler_mirror(coord::normalized, address::mirrored_repeat, filter::linear);
constexpr sampler b2_sampler_wrap  (coord::normalized, address::repeat,          filter::linear);
constexpr sampler b2_sampler_zero  (coord::normalized, address::clamp_to_zero,   filter::linear);
static inline float4 b2_sample(texture2d<float, access::sample> t, float2 p, uint mode) {
    float2 uv = p / float2(t.get_width(), t.get_height());
    switch (mode) {
        case 1: return t.sample(b2_sampler_mirror, uv);
        case 2: return t.sample(b2_sampler_wrap, uv);
        case 3: return t.sample(b2_sampler_zero, uv);
        default: return t.sample(b2_sampler_clamp, uv);
    }
}

// ---- sRGB transfer (IEC 61966-2-1), identical to BlurCore SRGB (formula continued above 1, linear below 0) ----
static inline float b2_srgb_encode(float l) { return l <= 0.0031308f ? 12.92f * l : 1.055f * powr(l, 1.0f / 2.4f) - 0.055f; }
static inline float b2_srgb_decode(float e) { return e <= 0.04045f ? e / 12.92f : powr((e + 0.055f) / 1.055f, 2.4f); }
static inline float4 b2_unpremultiply(float4 c) { return c.a > 0.0f ? float4(c.rgb / c.a, c.a) : float4(0.0f); }
static inline float4 b2_premultiply(float4 c) { return float4(c.rgb * c.a, c.a); }

// ---- Trace records: layout identical to Swift TraceLayout (strides 32 and 64) ----
struct B2TraceHeader { uint2 probe; uint tapCount; uint passIndex; uint capacity; uint overflow; uint2 reserved; };
struct B2TraceTap { float2 position; float weight; float flags; float4 fetched; float4 runningSum; float4 extra; };

// Records one tap for the probe pixel only (`block` = this pass's header). flags: 1 = dropped by renormalise,
// 2 = the final record (b2_trace_final). Capacity = PassPlan.traceCapacity (largest tapsPerPixel + 1).
static inline void b2_trace_tap(device B2TraceHeader *block, uint2 pixel, float2 position, float weight, float flags,
                                float4 fetched, float4 runningSum, float4 extra) {
    if (pixel.x != block->probe.x || pixel.y != block->probe.y) return;
    uint i = block->tapCount;
    if (i >= block->capacity) { block->overflow += 1; return; }
    device B2TraceTap *taps = (device B2TraceTap *)(block + 1);
    taps[i].position = position; taps[i].weight = weight; taps[i].flags = flags;
    taps[i].fetched = fetched; taps[i].runningSum = runningSum; taps[i].extra = extra;
    block->tapCount = i + 1;
}

// Every traced pass ends with exactly one final record holding the value the pass stores for the probe pixel
// (after any normalisation or selection). Parity compares the output with this record (ARCHITECTURE §7 rule 5).
static inline void b2_trace_final(device B2TraceHeader *block, uint2 pixel, float2 position, float4 stored) {
    b2_trace_tap(block, pixel, position, 0.0f, 2.0f, float4(0.0f), stored, float4(0.0f));
}

// ---- Deterministic noise: PCG hash, bit-identical to BlurCore NoiseHash ----
static inline uint b2_pcg(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
static inline float b2_uniform(uint2 p, uint seed) { return float(b2_pcg(p.x ^ b2_pcg(p.y ^ b2_pcg(seed)))) * (1.0f / 4294967296.0f); }

// ---- Full-screen triangle output (vertex function b2_common_fullscreen_vs lives in B2Common.metal) ----
struct B2VertexOut { float4 position [[position]]; float2 uv; };

#endif // B2_SHARED_H
