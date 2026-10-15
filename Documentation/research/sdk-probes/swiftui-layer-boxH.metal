#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Horizontal box blur of radius R (2R+1 taps, one bilinear fetch per tap at texel centres).
[[ stitchable ]] half4 boxH(float2 position, SwiftUI::Layer layer, float R) {
    half4 acc = 0;
    int r = int(R);
    for (int k = -r; k <= r; ++k) acc += layer.sample(position + float2(k, 0));
    return acc / half(2 * r + 1);
}
