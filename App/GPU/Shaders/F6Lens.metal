#include "B2Shared.h"
// F6Lens.metal — OWNER: FAM-F6 (MRT seed written by SKEL, review fix E-15). Prefix b2_f6_, function constants 64–71.
// TODO(FAM-F6): disc (gather, row-span SAT, complex separable, stochastic), polygonal bokeh (both MRT line passes,
// 2-D gather), cat's-eye, anamorphic.

// Seed: the polygonal bokeh's pass 1 as a two-attachment (MRT) fragment pass (SPEC §5.3 D):
//   T1 = blur(src, ↑)     T2 = ½·[blur(src, ↑) + blur(src, ↘)]
// Each blur is a one-sided line of `taps` bilinear samples, weight 1/taps, first tap half a step out. `offsets` holds
// the ↑ taps, then the ↘ taps, as float2 texel offsets from BlurCore (F6HexLineSeedReference.offsets). Tap order
// (binding for the CPU reference): ↑ tap i, then ↘ tap i, for i = 0 … taps − 1.
struct B2F6HexLineParams { uint taps; uint pad0; uint pad1; uint pad2; };
struct B2F6HexLinePair { float4 t1 [[color(0)]]; float4 t2 [[color(1)]]; };

fragment B2F6HexLinePair b2_f6_hexlines_mrt_fs(B2VertexOut in [[stage_in]],
                                               texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]],
                                               constant B2F6HexLineParams &P [[buffer(B2_BUF_PARAMS)]],
                                               constant float2 *offsets [[buffer(B2_BUF_OFFSETS)]]) {
    float2 centre = float2(uint2(in.position.xy)) + 0.5f;
    float w = 1.0f / float(P.taps);
    float4 up = float4(0.0f), diag = float4(0.0f);
    for (uint i = 0; i < P.taps; ++i) {
        float4 a = b2_sample(src, centre + offsets[i], B2_EDGE_MODE);           // @explain: ↑ line, one bilinear fetch
        up = (i == 0) ? a * w : fma(a, float4(w), up);
        float4 b = b2_sample(src, centre + offsets[P.taps + i], B2_EDGE_MODE);  // @explain: ↘ line, one bilinear fetch
        diag = (i == 0) ? b * w : fma(b, float4(w), diag);
    }
    B2F6HexLinePair out;
    out.t1 = up;                                                                 // @explain: attachment 0
    out.t2 = 0.5f * (up + diag);                                                 // @explain: attachment 1
    return out;
}
