//
//  PixelTransitions.metal
//  DeckHandiOS – Design system
//
//  Stitchable shaders for the pixel dissolve (`06-Pixel-Identity.md` §7,
//  UX-017). They draw the dissolve's mask and its phosphor edge, not the
//  content itself, so surfaces backed by UIKit views (the trackpad, the
//  mirror's video layer) dissolve too instead of rasterising to a
//  placeholder. The cell hash matches `PixelTransitionPlan.rank` in Core.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Seeded threshold in 0..<1 for the cell at `position`.
static float pixelDissolveRank(float2 position, float cell, float seed) {
    uint column = uint(max(position.x, 0.0) / cell);
    uint row = uint(max(position.y, 0.0) / cell);
    uint h = column * 73856093u;
    h ^= row * 19349663u;
    h ^= uint(seed) * 83492791u;
    h ^= h >> 13;
    h *= 0x5bd1e995u;
    h ^= h >> 15;
    return float(h % 10000u) / 10000.0;
}

/// The dissolve mask. Incoming (`outgoing` 0): a cell is opaque once
/// `progress` is past its threshold and it has left the edge band.
/// Outgoing (`outgoing` 1): a cell is opaque until `progress` reaches its
/// threshold. Use on a filled rectangle with `.colorEffect`, as a `.mask`.
[[ stitchable ]] half4 pixelDissolveMask(float2 position, half4 color, float progress, float cell, float seed, float outgoing, float edgeBand) {
    float rank = pixelDissolveRank(position, cell, seed);
    float p = clamp(progress, 0.0, 1.0);
    if (outgoing > 0.5) {
        return rank >= p ? color : half4(0.0);
    }
    if (rank >= p) {
        return half4(0.0);
    }
    bool isEdge = p < 1.0 && rank >= p - edgeBand;
    return isEdge ? half4(0.0) : color;
}

/// The phosphor edge: in the cells within `edgeBand` behind the threshold,
/// a rounded-square dot (78 % of the cell) with a 2 pt glow. Use on a
/// rectangle filled with the phosphor colour, with `.colorEffect`.
[[ stitchable ]] half4 pixelDissolveEdge(float2 position, half4 color, float progress, float cell, float seed, float edgeBand) {
    float p = clamp(progress, 0.0, 1.0);
    if (p <= 0.0 || p >= 1.0) {
        return half4(0.0);
    }
    float rank = pixelDissolveRank(position, cell, seed);
    if (rank >= p || rank < p - edgeBand) {
        return half4(0.0);
    }
    // Rounded-square distance from the cell centre.
    float2 local = fmod(max(position, 0.0), cell) - cell * 0.5;
    float half_side = cell * 0.39;
    float radius = half_side * 0.6;
    float2 q = abs(local) - (half_side - radius);
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    // Newest cells (nearest the threshold) burn brightest.
    float heat = 1.0 - (p - rank) / max(edgeBand, 0.0001);
    float alpha = distance <= 0.0 ? 1.0 : 0.5 * (1.0 - smoothstep(0.0, 2.0, distance));
    alpha *= mix(0.55, 1.0, heat);
    return color * half(alpha);
}
