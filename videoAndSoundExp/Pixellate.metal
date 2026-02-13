//
//  Pixellate.metal
//  videoAndSoundExp
//
//  Created by Peter Rogers on 13/02/2026.
//
#include <metal_stdlib>
using namespace metal;

#include <SwiftUI/SwiftUI_Metal.h>

[[ stitchable ]] half4 pixellate(float2 position, SwiftUI::Layer layer, float strength) {
    float min_strength = max(strength, 0.0001);
    float coord_x = min_strength * round(position.x / min_strength);
    float coord_y = min_strength * round(position.y / min_strength);
    return layer.sample(float2(coord_x, coord_y));
}
