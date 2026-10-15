#include "B2Shared.h"
// Probes.metal — OWNER: GPU-MEASURE. Prefix b2_probe_, function constants 120–127 (ARCHITECTURE §6.1; none used yet).
// The This-phone device probes (SPEC §4.7, §13.1; research gpu-pipeline §2.3, §2.6, §3.5, §4.3). Swift side:
// Sources/BlurGPU/Measure/DeviceProbeService.swift. Every kernel is dispatched through GPUContext.dispatch2D and
// bounds-checks its thread; nothing here reaches the screen except through a MEASURED DeviceProbeResult.

// ---- Bilinear sub-texel precision ----------------------------------------------------------------------------------
// A ramp texture holds 0 up to texel `base` and 1 from texel base + 1 on, along `axis` (0 = x, 1 = y). Thread i samples
// at the texel coordinate base + 0.5 + i / count, i.e. at the exact fraction t = i / count between the two texel
// centres, through b2_sample: the same coordinate arithmetic and sampler every linear-sampled blur uses. The filtered
// value IS the hardware's quantized t, so the number of distinct outputs gives the sub-texel bits and comparing them
// with round(t·2^bits) and floor(t·2^bits) gives the rounding mode (ReferenceOptions.forDevice).
struct B2ProbeSubTexelParams { uint count; uint axis; float base; float pad; };

kernel void b2_probe_subtexel_k(texture2d<float, access::sample> ramp [[texture(B2_TEX_SRC)]],
                                constant B2ProbeSubTexelParams &P [[buffer(B2_BUF_PARAMS)]],
                                device float *out [[buffer(B2_BUF_AUX0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= P.count || gid.y > 0u) return;
    float t = float(gid.x) / float(P.count);                  // @explain: exact — count is a power of two
    float along = P.base + 0.5f + t;                           // @explain: between the centres of texels base and base + 1
    float2 p = P.axis == 0u ? float2(along, 0.5f) : float2(0.5f, along);
    out[gid.x] = b2_sample(ramp, p, 0u).r;                     // @explain: (1 − t)·0 + t·1 = the hardware's t
}

// ---- Copy bandwidth --------------------------------------------------------------------------------------------------
// Fills a texture with PCG noise (incompressible, so lossless compression cannot inflate the measured rate).
struct B2ProbeFillParams { uint seed; uint pad0; uint pad1; uint pad2; };

kernel void b2_probe_noise_k(texture2d<float, access::write> dst [[texture(B2_TEX_DST)]],
                             constant B2ProbeFillParams &P [[buffer(B2_BUF_PARAMS)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float4 v = float4(b2_uniform(gid, P.seed), b2_uniform(gid, P.seed + 1u), b2_uniform(gid, P.seed + 2u), b2_uniform(gid, P.seed + 3u));
    dst.write(v, gid);
}

// The compute copy: one read and one write per texel (the destination carries .shaderWrite).
kernel void b2_probe_copy_k(texture2d<float, access::read> src [[texture(B2_TEX_SRC)]],
                            texture2d<float, access::write> dst [[texture(B2_TEX_DST)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    dst.write(src.read(gid), gid);                             // @explain: 8 B read + 8 B written per rgba16Float texel
}

// ---- Compression A/B -------------------------------------------------------------------------------------------------
// Smooth, highly compressible content, written as a render target (so it is stored compressed when the usage allows).
fragment float4 b2_probe_gradient_fs(B2VertexOut in [[stage_in]]) {
    float2 uv = in.uv;
    return float4(uv.x, uv.y, 0.5f * (uv.x + uv.y), 1.0f);
}

// A 9-tap box along B2_DIRECTION (0 = H, 1 = V): a blur-shaped fragment pass for the A/B. The same pass runs on textures
// with and without .shaderWrite; only the usage flag differs, so the time ratio is the cost of losing lossless
// compression on this GPU (Tech Talk 111431 says Apple9 disables it for .shaderWrite textures).
fragment float4 b2_probe_box_fs(B2VertexOut in [[stage_in]],
                                texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]]) {
    int2 p = int2(in.position.xy);
    int2 d = B2_DIRECTION == 0u ? int2(1, 0) : int2(0, 1);
    const float w = 1.0f / 9.0f;
    float4 sum = b2_fetch(src, p - 4 * d, 0u) * w;
    for (int i = -3; i <= 4; ++i) sum = fma(b2_fetch(src, p + i * d, 0u), float4(w), sum);   // @explain: fp32 fma chain
    return sum;
}

// ---- ALU throughput --------------------------------------------------------------------------------------------------
// Four independent float4 chains of dependent fma per thread: 16 scalar FMAs (32 FLOP) per iteration, no memory traffic.
struct B2ProbeFMAParams { uint iterations; uint width; float a; float b; };

kernel void b2_probe_fma_k(constant B2ProbeFMAParams &P [[buffer(B2_BUF_PARAMS)]],
                           device float *out [[buffer(B2_BUF_AUX0)]],
                           uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= P.width) return;
    float4 x0 = float4(float(gid.x & 255u), float(gid.y & 255u), 1.0f, 2.0f) * 1.0e-3f;
    float4 x1 = x0 + 0.25f, x2 = x0 + 0.5f, x3 = x0 + 0.75f;
    float4 a = float4(P.a), b = float4(P.b);
    for (uint i = 0u; i < P.iterations; ++i) {
        x0 = fma(x0, a, b); x1 = fma(x1, a, b); x2 = fma(x2, a, b); x3 = fma(x3, a, b);
    }
    out[gid.y * P.width + gid.x] = dot(x0 + x1 + x2 + x3, float4(1.0f));   // @explain: keeps every chain alive
}

// The same in half precision (the A17 Pro runs fp16 at a different rate; the result is stored as float).
kernel void b2_probe_fma_half_k(constant B2ProbeFMAParams &P [[buffer(B2_BUF_PARAMS)]],
                                device float *out [[buffer(B2_BUF_AUX0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= P.width) return;
    half4 x0 = half4(half(gid.x & 255u), half(gid.y & 255u), 1.0h, 2.0h) * 1.0e-3h;
    half4 x1 = x0 + 0.25h, x2 = x0 + 0.5h, x3 = x0 + 0.75h;
    half4 a = half4(half(P.a)), b = half4(half(P.b));
    for (uint i = 0u; i < P.iterations; ++i) {
        x0 = fma(x0, a, b); x1 = fma(x1, a, b); x2 = fma(x2, a, b); x3 = fma(x3, a, b);
    }
    out[gid.y * P.width + gid.x] = float(dot(x0 + x1 + x2 + x3, half4(1.0h)));
}
