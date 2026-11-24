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
    uint column = uint(max(position.x, 0.0f) / cell);
    uint row = uint(max(position.y, 0.0f) / cell);
    uint h = column * 73856093u;
    h ^= row * 19349663u;
    h ^= uint(seed) * 83492791u;
    h ^= h >> 13;
    h *= 0x5bd1e995u;
    h ^= h >> 15;
    return float(h % 10000u) / 10000.0f;
}

/// The dissolve mask. Incoming (`outgoing` 0): a cell is opaque once
/// `progress` is past its threshold and it has left the edge band.
/// Outgoing (`outgoing` 1): a cell is opaque until `progress` reaches its
/// threshold. Use on a filled rectangle with `.colorEffect`, as a `.mask`.
[[ stitchable ]] half4 pixelDissolveMask(float2 position, half4 color, float progress, float cell, float seed, float outgoing, float edgeBand) {
    float rank = pixelDissolveRank(position, cell, seed);
    float p = clamp(progress, 0.0f, 1.0f);
    if (outgoing > 0.5f) {
        return rank >= p ? color : half4(0.0h);
    }
    if (rank >= p) {
        return half4(0.0h);
    }
    bool isEdge = p < 1.0f && rank >= p - edgeBand;
    return isEdge ? half4(0.0h) : color;
}

/// The phosphor edge: in the cells within `edgeBand` behind the threshold,
/// a rounded-square dot (78 % of the cell) with a 2 pt glow. Use on a
/// rectangle filled with the phosphor colour, with `.colorEffect`.
[[ stitchable ]] half4 pixelDissolveEdge(float2 position, half4 color, float progress, float cell, float seed, float edgeBand) {
    float p = clamp(progress, 0.0f, 1.0f);
    if (p <= 0.0f || p >= 1.0f) {
        return half4(0.0h);
    }
    float rank = pixelDissolveRank(position, cell, seed);
    if (rank >= p || rank < p - edgeBand) {
        return half4(0.0h);
    }
    // Rounded-square distance from the cell centre.
    float2 local = fmod(max(position, float2(0.0f)), float2(cell)) - cell * 0.5f;
    float half_side = cell * 0.39f;
    float radius = half_side * 0.6f;
    float2 q = abs(local) - (half_side - radius);
    float d = length(max(q, float2(0.0f))) + min(max(q.x, q.y), 0.0f) - radius;
    // Newest cells (nearest the threshold) burn brightest.
    float heat = 1.0f - (p - rank) / max(edgeBand, 0.0001f);
    float alpha = d <= 0.0f ? 1.0f : 0.5f * (1.0f - smoothstep(0.0f, 2.0f, d));
    alpha *= mix(0.55f, 1.0f, heat);
    return color * half(alpha);
}
