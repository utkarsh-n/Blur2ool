#include <metal_stdlib>
using namespace metal;

constant int TILE = 16;
constant int MAXR = 16;   // max kernel radius supported by the tiled path

// Horizontal pass of a separable Gaussian using threadgroup memory and half precision.
// Threadgroup: 16x16 threads. Tile in threadgroup memory: 16 rows x (16 + 2*MAXR) half4 = 16*48*8 B = 6144 B.
kernel void gaussH_tg(texture2d<half, access::read>  src [[texture(0)]],
                      texture2d<half, access::write> dst [[texture(1)]],
                      constant float *weights [[buffer(0)]],
                      constant int   &radius  [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]],
                      uint2 lid [[thread_position_in_threadgroup]],
                      uint2 tgid [[threadgroup_position_in_grid]])
{
    threadgroup half4 tile[TILE][TILE + 2 * MAXR];
    int w = src.get_width(), h = src.get_height();
    int y = min(int(gid.y), h - 1);
    int x0 = int(tgid.x) * TILE - MAXR;
    for (int i = int(lid.x); i < TILE + 2 * MAXR; i += TILE) {
        int sx = clamp(x0 + i, 0, w - 1);                    // clamp-to-edge
        tile[lid.y][i] = src.read(uint2(sx, y));
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (gid.x >= uint(w) || gid.y >= uint(h)) return;
    half4 acc = half4(0);
    for (int k = -radius; k <= radius; ++k)
        acc += tile[lid.y][int(lid.x) + MAXR + k] * half(weights[k + radius]);
    dst.write(acc, gid);
}
