#include "B2Shared.h"
// B2Common.metal — owner: SKEL (then frozen). Full-screen triangle and the colour/alpha pre- and post-pass
// (ARCHITECTURE §4.2), mirroring BlurCore ColourTransform exactly.

vertex B2VertexOut b2_common_fullscreen_vs(uint vid [[vertex_id]]) {
    float2 uv = float2(float((vid << 1) & 2), float(vid & 2));
    B2VertexOut out;
    out.position = float4(uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    out.uv = uv;
    return out;
}

// One pass, specialised by B2_COLOUR_SRGB, B2_ALPHA_STRAIGHT and B2_COLOUR_POST (indices 4–6).
fragment float4 b2_common_colour_fs(B2VertexOut in [[stage_in]],
                                    texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]]) {
    float4 c = src.read(uint2(in.position.xy));
    if (!B2_COLOUR_POST) {
        if (B2_COLOUR_SRGB || B2_ALPHA_STRAIGHT) c = b2_unpremultiply(c);
        if (B2_COLOUR_SRGB) c = float4(b2_srgb_encode(c.r), b2_srgb_encode(c.g), b2_srgb_encode(c.b), c.a);
        if (B2_COLOUR_SRGB && !B2_ALPHA_STRAIGHT) c = b2_premultiply(c);
    } else {
        if (B2_COLOUR_SRGB && !B2_ALPHA_STRAIGHT) c = b2_unpremultiply(c);
        if (B2_COLOUR_SRGB) c = float4(b2_srgb_decode(c.r), b2_srgb_decode(c.g), b2_srgb_decode(c.b), c.a);
        if (B2_COLOUR_SRGB || B2_ALPHA_STRAIGHT) c = b2_premultiply(c);
    }
    return c;
}

// The window pass with exposure (ARCHITECTURE §4.1): canvas texel at origin + pixel, × 2^EV. 0 EV uses a blit instead.
struct B2CommonWindowParams { int2 origin; float gain; float pad; };
fragment float4 b2_common_window_fs(B2VertexOut in [[stage_in]],
                                    texture2d<float, access::sample> canvas [[texture(B2_TEX_SRC)]],
                                    constant B2CommonWindowParams &P [[buffer(B2_BUF_PARAMS)]]) {
    return canvas.read(uint2(int2(in.position.xy) + P.origin)) * P.gain;
}

// The frozen preview input (review fix E-4): 2 × 2 mean, edge-clamped, ((a + b) + (c + d)) × 0.25 as ImageBuffer.downsampled2x.
fragment float4 b2_common_downsample2x_fs(B2VertexOut in [[stage_in]],
                                          texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]]) {
    int2 p = int2(in.position.xy) * 2;
    float4 a = b2_fetch(src, p, 0u), b = b2_fetch(src, p + int2(1, 0), 0u);
    float4 c = b2_fetch(src, p + int2(0, 1), 0u), d = b2_fetch(src, p + int2(1, 1), 0u);
    return ((a + b) + (c + d)) * 0.25f;
}

// Plain copy (nearest), used for crops and the periscope.
fragment float4 b2_common_copy_fs(B2VertexOut in [[stage_in]], texture2d<float, access::sample> src [[texture(B2_TEX_SRC)]]) {
    return src.read(uint2(in.position.xy));
}
