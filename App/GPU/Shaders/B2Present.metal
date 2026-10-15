#include "B2Shared.h"
// B2Present.metal — OWNER: UI-SPECIMEN. Prefix b2_present_, function-constant block 128–135 (unused: every switch is a
// uniform, so makeFunction(name:) works without specialisation and one pipeline per drawable format serves every view).
// The present pass (ARCHITECTURE §4.1, §6.5; SPEC §4.1.3, §8.3): draws only from textures the RenderCoordinator publishes
// (output, input, pass intermediates, B/C/D slots) or the loupe's 14 × 14 copy, into the MTKView's drawable. It never
// blurs, never filters (every fetch is `read` of the nearest texel), and never draws overlays (those are SwiftUI).
//
// Geometry (App/Render/PresentGeometry.swift is the single source of truth; this shader only maps):
//   drawable pixel d (centre d + 0.5)  →  content c = d − shift (rubber band; outside the drawable is black)
//   window coordinate s = origin + c · texelsPerPixel            (1 : 1 at zoom 1: s = d + 0.5; zoom z: 1/z; crop: w/D)
//   texel t = floor(s · ratio), ratio = texture side / window side (1 for full outputs, ½ and ≈¼ for previews)
// Colour: premultiplied linear light composited over the specimen's backdrop, then
//   SDR: sRGB-encoded (IEC 61966-2-1, b2_srgb_encode) and clipped to [0, 1] into a bgra8Unorm drawable (sRGB-tagged layer);
//   EDR: extended linear values, unclipped, into an rgba16Float drawable (extended linear sRGB layer).

#define B2_PRESENT_MODE_OUTPUT 0u   // A (or a pass intermediate); the INPUT left of splitColumn when splitColumn ≥ 0
#define B2_PRESENT_MODE_WIPE   1u   // B left of splitColumn, A right of it (SPEC §8.3)
#define B2_PRESENT_MODE_FLIP   2u   // A, or B while it is held
#define B2_PRESENT_MODE_DIFF   3u   // |A − B| × gain as a luminance ramp with contours
#define B2_PRESENT_MODE_LINEUP 4u   // 2 × 2: quadrant q shows the central crop of slot q (A B / C D)
#define B2_PRESENT_MODE_CROP   5u   // periscope and loupe: a window region of A, magnified nearest

#define B2_PRESENT_HAS_A 1u
#define B2_PRESENT_HAS_B 2u        // the INPUT in output mode, slot B in the compare views
#define B2_PRESENT_HAS_C 4u
#define B2_PRESENT_HAS_D 8u

// Mirrored field for field by `PresentShaderParams` (App/Render/PresentGeometry.swift) and the Mac tests
// (Tests/BlurGPUTests/UISPECIMEN). 144 bytes; scalars only after the vectors, so Swift and Metal agree on every offset.
struct B2PresentParams {
    float4 backdrop;        //   0  linear premultiplied colour behind transparent pixels (SpecimenCanvas.backdrop)
    float4 contour;         //  16  Difference contour colour, display-encoded RGB; a > 0 draws contours
    float4 ratioAB;         //  32  texture texels per window pixel: (A.x, A.y, B.x, B.y)
    float4 ratioCD;         //  48  (C.x, C.y, D.x, D.y)
    float2 origin;          //  64  window coordinate of the drawable's top-left corner (zoom or crop origin)
    float2 texelsPerPixel;  //  72  window pixels per drawable pixel
    float2 lineUpOrigin;    //  80  window origin of the central crop each Line-up quadrant shows
    float2 drawableSize;    //  88  drawable width and height in pixels
    int2   shift;           //  96  rubber-band display shift in drawable pixels (content moves; the gap is black)
    int    splitColumn;     // 104  first drawable column right of the divider; < 0 = no divider
    uint   mode;            // 108  B2_PRESENT_MODE_*
    uint   edr;             // 112  1 = extended linear (EDR), 0 = sRGB-encoded and clipped (SDR)
    uint   available;       // 116  B2_PRESENT_HAS_* bits; a missing texture is drawn black
    float  gain;            // 120  Difference gain (1, 16, 256)
    float  contourStep;     // 124  Difference contour spacing in encoded units (k LSB / 255); 0 = none
    uint   showB;           // 128  Flip: 1 while B is held
    uint   reserved0;       // 132
    uint   reserved1;       // 136
    uint   reserved2;       // 140
};
static_assert(sizeof(B2PresentParams) == 144, "B2PresentParams must stay 144 bytes (PresentShaderParams mirrors it)");

constant float4 b2_present_black = float4(0.0f, 0.0f, 0.0f, 1.0f);   // opaque black: outside the window or not rendered yet

// The nearest texel of window coordinate `s` (no filtering). Outside the texture: opaque black, never a clamped edge.
static inline float4 b2_present_fetch(texture2d<float, access::sample> t, float2 s, float2 ratio) {
    // @explain: nearest texel: floor of the window coordinate scaled to this texture (1 : 1 for full-size outputs)
    float2 p = floor(s * ratio);
    if (p.x < 0.0f || p.y < 0.0f || p.x >= float(t.get_width()) || p.y >= float(t.get_height())) return b2_present_black;
    return t.read(uint2(p));
}

static inline bool b2_present_inside(texture2d<float, access::sample> t, float2 s, float2 ratio) {
    float2 p = floor(s * ratio);
    return p.x >= 0.0f && p.y >= 0.0f && p.x < float(t.get_width()) && p.y < float(t.get_height());
}

// Premultiplied linear light over the specimen's backdrop (premultiplied, normally opaque black).
static inline float3 b2_present_over(float4 c, float4 backdrop) { return c.rgb + backdrop.rgb * (1.0f - c.a); }

// SDR: the sRGB transfer function, then the clip to the display's [0, 1].
static inline float3 b2_present_encode(float3 l) {
    // @explain: sRGB encode (formula continued above 1, linear below 0), then clip: what an 8-bit SDR display can show
    return clamp(float3(b2_srgb_encode(l.r), b2_srgb_encode(l.g), b2_srgb_encode(l.b)), 0.0f, 1.0f);
}

static inline float4 b2_present_pixel(float4 c, constant B2PresentParams &P) {
    float3 linear = b2_present_over(c, P.backdrop);
    return P.edr != 0u ? float4(linear, 1.0f) : float4(b2_present_encode(linear), 1.0f);
}

// A display-space grey or colour (already encoded): SDR writes it as is, EDR decodes it so the display shows the same.
static inline float4 b2_present_display(float3 e, uint edr) {
    return edr != 0u ? float4(b2_srgb_decode(e.r), b2_srgb_decode(e.g), b2_srgb_decode(e.b), 1.0f) : float4(e, 1.0f);
}

// The encoded, clipped difference the eye could see between A and B at window coordinate s (max over R, G, B).
static inline float b2_present_difference(texture2d<float, access::sample> a, texture2d<float, access::sample> b, float2 s,
                                          constant B2PresentParams &P) {
    float3 ea = b2_present_encode(b2_present_over(b2_present_fetch(a, s, P.ratioAB.xy), P.backdrop));
    float3 eb = b2_present_encode(b2_present_over(b2_present_fetch(b, s, P.ratioAB.zw), P.backdrop));
    float3 d = abs(ea - eb);
    return max(d.r, max(d.g, d.b));
}

fragment float4 b2_present_fs(B2VertexOut in [[stage_in]],
                              texture2d<float, access::sample> slotA [[texture(B2_TEX_SRC)]],    // A output / pass / crop source
                              texture2d<float, access::sample> slotB [[texture(B2_TEX_DST)]],    // INPUT (split) or B (compare)
                              texture2d<float, access::sample> slotC [[texture(B2_TEX_AUX0)]],   // Line-up C
                              texture2d<float, access::sample> slotD [[texture(B2_TEX_AUX1)]],   // Line-up D
                              constant B2PresentParams &P [[buffer(B2_BUF_PARAMS)]]) {
    float2 frag = in.position.xy;                                   // drawable pixel centre d + 0.5
    // @explain: rubber band: the content moves by whole drawable pixels; the strip it uncovers lies outside the canvas
    float2 content = frag - float2(P.shift);
    if (content.x < 0.0f || content.y < 0.0f || content.x >= P.drawableSize.x || content.y >= P.drawableSize.y) {
        return b2_present_display(float3(0.0f), P.edr);
    }

    if (P.mode == B2_PRESENT_MODE_LINEUP) {
        // @explain: Line-up 2 × 2: each quadrant is the central crop of one slot's full-size output, 1 : 1, nearest
        float q = max(floor(P.drawableSize.x * 0.5f), 1.0f);
        uint qx = content.x >= q ? 1u : 0u, qy = content.y >= q ? 1u : 0u;
        if (content.x >= 2.0f * q || content.y >= 2.0f * q) return b2_present_display(float3(0.0f), P.edr);
        float2 s = P.lineUpOrigin + (content - float2(float(qx), float(qy)) * q) * P.texelsPerPixel;
        uint index = qy * 2u + qx;
        if ((P.available & (1u << index)) == 0u) return b2_present_display(float3(0.0f), P.edr);
        float4 c = index == 0u ? b2_present_fetch(slotA, s, P.ratioAB.xy)
                 : index == 1u ? b2_present_fetch(slotB, s, P.ratioAB.zw)
                 : index == 2u ? b2_present_fetch(slotC, s, P.ratioCD.xy)
                 :               b2_present_fetch(slotD, s, P.ratioCD.zw);
        return b2_present_pixel(c, P);
    }

    float2 s = P.origin + content * P.texelsPerPixel;
    bool hasA = (P.available & B2_PRESENT_HAS_A) != 0u, hasB = (P.available & B2_PRESENT_HAS_B) != 0u;

    if (P.mode == B2_PRESENT_MODE_DIFF) {
        if (!hasA || !hasB) return b2_present_display(float3(0.0f), P.edr);
        float d = b2_present_difference(slotA, slotB, s, P);
        // @explain: Difference: |A − B| of the encoded, clipped values (8-bit steps are 1/255) × gain, as a grey ramp
        float g = clamp(P.gain * d, 0.0f, 1.0f);
        if (P.contour.a > 0.0f && P.contourStep > 0.0f) {
            // @explain: contours where the difference crosses a multiple of the step (k LSB): shape, not colour alone
            // (a neighbour outside the window is not a crossing, so the window's edge never draws a false contour)
            float level = floor(d / P.contourStep);
            float2 sr = s + float2(P.texelsPerPixel.x, 0.0f), sb = s + float2(0.0f, P.texelsPerPixel.y);
            float right = b2_present_inside(slotA, sr, P.ratioAB.xy) ? floor(b2_present_difference(slotA, slotB, sr, P) / P.contourStep) : level;
            float below = b2_present_inside(slotA, sb, P.ratioAB.xy) ? floor(b2_present_difference(slotA, slotB, sb, P) / P.contourStep) : level;
            if (level != right || level != below) return b2_present_display(P.contour.rgb, P.edr);
        }
        return b2_present_display(float3(g), P.edr);
    }

    bool left = P.splitColumn >= 0 && frag.x < float(P.splitColumn);
    if (P.mode == B2_PRESENT_MODE_WIPE) {
        // @explain: Wipe: B left of the divider column, A right of it
        if (left) return hasB ? b2_present_pixel(b2_present_fetch(slotB, s, P.ratioAB.zw), P) : b2_present_display(float3(0.0f), P.edr);
        return hasA ? b2_present_pixel(b2_present_fetch(slotA, s, P.ratioAB.xy), P) : b2_present_display(float3(0.0f), P.edr);
    }
    if (P.mode == B2_PRESENT_MODE_FLIP) {
        if (P.showB != 0u) return hasB ? b2_present_pixel(b2_present_fetch(slotB, s, P.ratioAB.zw), P) : b2_present_display(float3(0.0f), P.edr);
        return hasA ? b2_present_pixel(b2_present_fetch(slotA, s, P.ratioAB.xy), P) : b2_present_display(float3(0.0f), P.edr);
    }
    if (P.mode == B2_PRESENT_MODE_CROP) {
        // @explain: periscope / loupe: a region of the same texture, each texel an integer block of drawable pixels
        return hasA ? b2_present_pixel(b2_present_fetch(slotA, s, P.ratioAB.xy), P) : b2_present_display(float3(0.0f), P.edr);
    }
    // Output: the INPUT left of the divider, the output (or the selected pass intermediate) right of it.
    // @explain: before/after split: the specimen INPUT left of the divider column, the blurred output right of it
    if (left && hasB) return b2_present_pixel(b2_present_fetch(slotB, s, P.ratioAB.zw), P);
    return hasA ? b2_present_pixel(b2_present_fetch(slotA, s, P.ratioAB.xy), P) : b2_present_display(float3(0.0f), P.edr);
}
