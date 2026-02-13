#include <metal_stdlib>
using namespace metal;

#include <SwiftUI/SwiftUI_Metal.h>

// SwiftUI layer-effect shader.
// - position is in the layer's pixel coordinate space.
// - layer.sample(pos) expects pixel-space coordinates.
// - maxSampleOffset in SwiftUI must cover your largest offset.
half4 videoWarp(float2 position,
                SwiftUI::Layer layer,
                float time,
                float strength,
                float rgbSplit)
{
    // Wavy offsets in *pixels*
    float waveX = sin(position.y * 0.02 + time * 2.0);
    float waveY = cos(position.x * 0.02 + time * 1.7);

    float2 warp = float2(waveX, waveY) * (6.0 * strength); // up to ~6px * strength

    // Chromatic aberration in pixels
    float2 ca = float2(4.0 * rgbSplit, 0.0); // up to ~4px

    half4 base = layer.sample(position + warp);
    half r = layer.sample(position + warp + ca).r;
    half g = base.g;
    half b = layer.sample(position + warp - ca).b;

    return half4(r, g, b, base.a);
}
