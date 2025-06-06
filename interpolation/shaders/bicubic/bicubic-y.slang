#version 450

/*
   bicubic-y Shader

   Copyright (C) 2011-2025 Hyllian - sergiogdb@gmail.com

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.

*/

layout(push_constant) uniform Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
    float Bicubic_InputGamma;
    float B_ANTI_RINGING;
    float B_LINEAR_GAMMA;
} params;

#pragma parameter BI_NONONO           "BICUBIC:"                                  0.0  0.0   1.0 1.0
#pragma parameter B_LINEAR_GAMMA      "    Use Linear Gamma [ YES | NO ]"         0.0 0.0 1.0 1.0
#pragma parameter Bicubic_InputGamma  "    Input Gamma"                           2.4 1.0 3.0 0.05
#pragma parameter Bicubic_OutputGamma "    Output Gamma"                          2.2 1.0 3.0 0.05
#pragma parameter B_ANTI_RINGING      "    Bicubic Anti-Ringing [ OFF | ON ]"     0.0 0.0 1.0 1.0

#define InputGamma     params.Bicubic_InputGamma
#define ANTI_RINGING   params.B_ANTI_RINGING
#define LINEAR_GAMMA   params.B_LINEAR_GAMMA

#define GAMMA_IN(color)     pow(color, vec3(InputGamma, InputGamma, InputGamma))

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
} global;

// Classic Mitchell-Netravali bicubic parameters
const float  B =  1.0/3.0; 
const float  C =  1.0/3.0;

const mat4 INV  = mat4(            (-B - 6.0*C)/6.0,         (3.0*B + 12.0*C)/6.0,     (-3.0*B - 6.0*C)/6.0,             B/6.0,
                                        (12.0 - 9.0*B - 6.0*C)/6.0, (-18.0 + 12.0*B + 6.0*C)/6.0,                      0.0, (6.0 - 2.0*B)/6.0,
                                       -(12.0 - 9.0*B - 6.0*C)/6.0, (18.0 - 15.0*B - 12.0*C)/6.0,      (3.0*B + 6.0*C)/6.0,             B/6.0,
                                                   (B + 6.0*C)/6.0,                           -C,                      0.0,               0.0);

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) out vec4 t1;
layout(location = 2) out vec4 t2;

void main()
{
    gl_Position = global.MVP * Position;
   
    vec2 ps = vec2(params.SourceSize.z, params.SourceSize.w);
    float dx = ps.x;
    float dy = ps.y;

    vTexCoord = (TexCoord  - vec2(0.0, 0.5)*ps) * 1.0001;

    t1 = vTexCoord.xyxy + vec4( 0.0, -dy, 0.0,    0.0); 
    t2 = vTexCoord.xyxy + vec4( 0.0,  dy, 0.0, 2.0*dy);
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in vec4 t1;
layout(location = 2) in vec4 t2;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

void main()
{
    vec2 fp = fract(vTexCoord*params.SourceSize.xy);

    vec3 C0 = texture(Source, t1.xy).xyz;
    vec3 C1 = texture(Source, t1.zw).xyz;
    vec3 C2 = texture(Source, t2.xy).xyz;
    vec3 C3 = texture(Source, t2.zw).xyz;

    vec4 Py    = vec4(fp.y*fp.y*fp.y, fp.y*fp.y, fp.y, 1.0) * INV;
    vec3 color = mat4x3(C0, C1, C2, C3) * Py;

    // Anti-ringing
    if (ANTI_RINGING == 1.0)
    {
        vec3 aux = color;
        vec3 min_sample = min(min(C0, C1), min(C2, C3));
        vec3 max_sample = max(max(C0, C1), max(C2, C3));
        color = clamp(color, min_sample, max_sample);
        color = mix(aux, color, step(0.0, (C0-C1)*(C2-C3)));
    }

    color = mix(color, GAMMA_IN(color), LINEAR_GAMMA);

    FragColor = vec4(color, 1.0);
}
