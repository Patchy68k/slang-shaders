#version 450

/*
	Bicubic Catmull-Rom 5-taps (Fast) - ported by Hyllian - 2024

	Samples a texture with B-Spline filtering, using only 4 texture fetches instead of 16.
	See http://vec3.ca/bicubic-filtering-in-fewer-taps/ for more details
	Source: https://www.shadertoy.com/view/styXDh
	http://www.profhua.com/Sub/Article/BicubicFiltering/BicubicFiltering.html

	ATENTION: This code only work using LINEAR filter sampling set on Retroarch!

*/

layout(push_constant) uniform Push
{
	vec4 SourceSize;
	vec4 OriginalSize;
	vec4 OutputSize;
	uint FrameCount;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
   gl_Position = global.MVP * Position;
   vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

void main()
{
    // We're going to sample a a 4x4 grid of texels surrounding the target UV coordinate. We'll do this by rounding
    // down the sample location to get the exact center of our "starting" texel. The starting texel will be at
    // location [1, 1] in the grid, where [0, 0] is the top left corner.
    vec2 texSize = params.SourceSize.xy;
    vec2 invTexSize = 1.0 / texSize;
    vec2 iTc = vTexCoord * texSize;

    vec2 tc = floor(iTc - vec2(0.5)) + vec2(0.5);

    // Compute the fractional offset from our starting texel to our original sample location, which we'll
    // feed into the B-Spline function to get our filter weights.
    vec2 f  = iTc - tc;
    vec2 f2 = f * f;
    vec2 f3 = f2 * f;

    vec2 of = vec2(1.)-f;
    vec2 of2 = of*of;
    vec2 of3 = of2*of;
    
    vec2 w0 = f2 - 0.5 * (f3 + f);
    vec2 w1 = 1.5 * f3 - 2.5 * f2 + vec2(1.);
    vec2 w3 = 0.5 * (f3 - f2);
    vec2 w2 = vec2(1.) - w0 - w1 - w3;

    vec2 Weight[3];
    vec2 Sample[3];

    Weight[0] = w0;
    Weight[1] = w1 + w2;
    Weight[2] = w3;

    Sample[0] = tc - vec2(1.);
    Sample[1] = tc + w2 / Weight[1];
    Sample[2] = tc + vec2(2.);

    Sample[0] *= invTexSize;
    Sample[1] *= invTexSize;
    Sample[2] *= invTexSize;

    float sampleWeight[5];
    sampleWeight[0] = Weight[1].x * Weight[0].y;
    sampleWeight[1] = Weight[0].x * Weight[1].y;
    sampleWeight[2] = Weight[1].x * Weight[1].y;
    sampleWeight[3] = Weight[2].x * Weight[1].y;
    sampleWeight[4] = Weight[1].x * Weight[2].y;

    vec3 CT = texture(Source, vec2(Sample[1].x, Sample[0].y)).rgb;    
    vec3 CL = texture(Source, vec2(Sample[0].x, Sample[1].y)).rgb;    
    vec3 CC = texture(Source, vec2(Sample[1].x, Sample[1].y)).rgb;    
    vec3 CR = texture(Source, vec2(Sample[2].x, Sample[1].y)).rgb;    
    vec3 CB = texture(Source, vec2(Sample[1].x, Sample[2].y)).rgb;

    vec3 Ct = CT * sampleWeight[0];    
    vec3 Cl = CL * sampleWeight[1];    
    vec3 Cc = CC * sampleWeight[2];    
    vec3 Cr = CR * sampleWeight[3];    
    vec3 Cb = CB * sampleWeight[4];
    
    float WeightMultiplier = 1./(sampleWeight[0]+sampleWeight[1]+sampleWeight[2]+sampleWeight[3]+sampleWeight[4]);

    vec3 color = (Ct+Cl+Cc+Cr+Cb)*WeightMultiplier;

    // Anti-ringing
    vec3 aux = color;
    vec3 min_sample = min(min(min(CC,CT), CL), min(CR, CB));
    vec3 max_sample = max(max(max(CC,CT), CL), max(CR, CB));
    color = clamp(color, min_sample, max_sample);
    color = mix(aux, color, step(0.0, (CL-CC)*(CC-CR)+(CB-CC)*(CC-CT)));

    FragColor = vec4(color, 1.0);
}
