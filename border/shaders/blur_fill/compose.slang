#version 450

/*
    Blur fill v1.9 by fishku
    Copyright (C) 2023-2024
    Public domain license (CC0)

    This shader preset allows cropping the image on any side, and filling the
    cropped area with a blurred version of the input image borders.
    This is useful for certain games that do not render a full image to maintain
    the overall aspect ratio and to avoid burn-in.

    The preset also allows you to extend the original content to a larger
    screen. It's recommended to set the video scaling options as follows:
    - Turn integer scaling OFF
    - Set aspect ratio to FULL
    The shader will then take over and handle the proper scaling and aspect
    ratio of the input.

    The preset comes in three variants which differ only in the strength of the
    blur.
    Since the blur strength in the dual filter blur depends on the input
    resolution, and because there is currently no mechanism to set resolution
    based on user parameters, the three variants provide different sampling
    resolutions which affect the strength of the blur.
    Additionally to the resolution, a blur radius parameter controls the
    strength of the blur.

    Changelog:
    v1.10: Update input transform library.
    v1.9: Add shift option from input transform library.
    v1.8: Add overscale option from crop and scale library.
    v1.7: Refactor for new scaling library. Add rotation support.
    v1.6: Optimize. Update to new Pixel AA version. Tune default blur strength.
    v1.5: Add anti-aliased interpolation for non-integer scaling.
    v1.4: Fix scaling bugs.
    v1.3: Reduce shimmering artifacts.
    v1.2: Fix scaling bugs.
    v1.1: Fix bug with glcore driver.
    v1.0: Initial release.
*/

// clang-format off
#include "parameters.inc"
#include "../../../blurs/shaders/dual_filter/parameters.inc"
#include "../../../pixel-art-scaling/shaders/pixel_aa/parameters.inc"
// clang-format on

#include "../../../misc/shaders/input_transform/input_transform.inc"
#include "../../../pixel-art-scaling/shaders/pixel_aa/shared.inc"

layout(push_constant) uniform Push {
    vec4 InputSize;
    vec4 TiledSize;
    vec4 OutputSize;
    uint Rotation;
    // Own settings
    float FILL_GAMMA;
    float SAMPLE_SIZE;
    // From input transform library, scaling section
    float FORCE_ASPECT_RATIO;
    float ASPECT_H;
    float ASPECT_V;
    float FORCE_INTEGER_SCALING_H;
    float FORCE_INTEGER_SCALING_V;
    float OVERSCALE;
    // From input transform library, cropping section
    float OS_CROP_TOP;
    float OS_CROP_BOTTOM;
    float OS_CROP_LEFT;
    float OS_CROP_RIGHT;
    // From input transform library, moving section
    float SHIFT_H;
    float SHIFT_V;
    float CENTER_AFTER_CROPPING;
    // From dual filter blur
    float BLUR_RADIUS;
    // From pixel AA
    float PIX_AA_SHARP;
    float PIX_AA_SUBPX;
    float PIX_AA_SUBPX_ORIENTATION;
}
param;

layout(std140, set = 0, binding = 0) uniform UBO { mat4 MVP; }
global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec4 input_corners;
layout(location = 1) out vec2 vTexCoord;
layout(location = 2) out vec2 tx_coord;
layout(location = 3) out vec2 sub_tx_offset;
layout(location = 4) out vec2 trans_lb;
layout(location = 5) out vec2 trans_ub;
layout(location = 6) out float trans_slope;

void main() {
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
    const vec4 crop =
        vec4(param.OS_CROP_TOP, param.OS_CROP_LEFT, param.OS_CROP_BOTTOM, param.OS_CROP_RIGHT);
    const vec2 scale_i2o = get_scale_i2o(
        param.InputSize.xy, param.OutputSize.xy, crop, param.Rotation, param.CENTER_AFTER_CROPPING,
        param.FORCE_ASPECT_RATIO, vec2(param.ASPECT_H, param.ASPECT_V),
        vec2(param.FORCE_INTEGER_SCALING_H, param.FORCE_INTEGER_SCALING_V), param.OVERSCALE);
    const vec2 shift = vec2(param.SHIFT_H, param.SHIFT_V);
    const vec2 input_center =
        get_input_center(param.InputSize.xy, param.OutputSize.xy, scale_i2o, crop, shift,
                         param.Rotation, param.CENTER_AFTER_CROPPING);
    tx_coord = transform(TexCoord, vec2(0.5), param.OutputSize.xy / scale_i2o, input_center);
    const vec2 tx_per_px = 1.0 / scale_i2o;
    input_corners = get_input_corners(param.InputSize.xy, crop, param.Rotation);

    calculate_pixel_aa_params(tx_per_px, param.PIX_AA_SHARP, uint(param.PIX_AA_SUBPX_ORIENTATION),
                              param.Rotation, trans_lb, trans_ub, trans_slope, sub_tx_offset);
}

#pragma stage fragment
layout(location = 0) in vec4 input_corners;
layout(location = 1) in vec2 vTexCoord;
layout(location = 2) in vec2 tx_coord;
layout(location = 3) in vec2 sub_tx_offset;
layout(location = 4) in vec2 trans_lb;
layout(location = 5) in vec2 trans_ub;
layout(location = 6) in float trans_slope;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Input;
layout(set = 0, binding = 3) uniform sampler2D Tiled;
layout(set = 0, binding = 4) uniform sampler2D Blurred;

void main() {
    if (any(lessThan(tx_coord, input_corners.xy)) ||
        any(greaterThanEqual(tx_coord, input_corners.zw))) {
        if (param.BLUR_RADIUS > 0.0) {
            // Sample blur.
            FragColor = vec4(pow(texture(Blurred, vTexCoord).rgb, vec3(param.FILL_GAMMA)), 1.0);
        } else {
            // Sample tiled pattern.
            // Do a perfectly sharp (nearest neighbor) resampling.
            FragColor = vec4(pow(texture(Tiled, (floor(vTexCoord * param.TiledSize.xy) + 0.5) *
                                                    param.TiledSize.zw)
                                     .rgb,
                                 vec3(param.FILL_GAMMA)),
                             1.0);
        }
    } else {
        // Sample original.
        if (param.FORCE_INTEGER_SCALING_H > 0.5 && param.FORCE_INTEGER_SCALING_V > 0.5) {
            // Do a perfectly sharp (nearest neighbor) sampling.
            FragColor = vec4(texture(Input, (floor(tx_coord) + 0.5) * param.InputSize.zw).rgb, 1.0);
        } else {
            // Do a sharp anti-aliased interpolation.
            FragColor.rgb =
                param.PIX_AA_SUBPX < 0.5
                    ? pixel_aa(Input, tx_coord, param.InputSize.zw, trans_lb, trans_ub, trans_slope)
                    : pixel_aa_subpx(Input, tx_coord, sub_tx_offset, param.InputSize.zw, trans_lb,
                                     trans_ub, trans_slope);
        }
    }
}
