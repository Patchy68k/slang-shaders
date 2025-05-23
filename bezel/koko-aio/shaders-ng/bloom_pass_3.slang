#version 450

// This is one of several passes needed to cheaply emulate the bloom effect.

#include "config.inc"
#include "includes/functions.include.slang"

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 5) out vec2 blur_radius_adpt;

void main() {
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
    blur_radius_adpt = radius_blur_adapt(BLOOM_SIZE);
}

#pragma stage fragment

layout(location = 0) in vec2 vTexCoord;
layout(location = 5) in vec2 blur_radius_adpt;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

#include "includes/blooms.include.slang"

#define offset 0.3926990816987242 //TAU/8.0/4.0*2.0

void main() {
    if (DO_BLOOM == 0.0) return;
    
    vec3 bloomed = bloom(
        Source,
        vTexCoord,
        params.SourceSize,
        blur_radius_adpt,
        BLOOM_QUALITY,
        offset,
        0.0
    );

    FragColor.rgb = bloomed; //FragColor = texture(Source,vTexCoord);

}
