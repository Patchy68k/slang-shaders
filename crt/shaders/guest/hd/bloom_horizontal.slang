#version 450

/*
   Gaussian blur - horizontal pass, dynamic range, resizable
   
   Copyright (C) 2020 - 2025 guest(r)

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
   
*/ 

layout(push_constant) uniform Push
{
	vec4 LinearizePassSize;
	vec4 OriginalSize;
	vec4 OutputSize;
	uint FrameCount;
	float SIZEHB;
	float SIGMA_HB;
	float FINE_BLOOM;
	float auto_res;
	float GLOW_MAX;
} params;

#pragma parameter bogus_bloom "[ BLOOM/HALATION/(GLOW) PASS SETTINGS ]:" 0.0 0.0 1.0 1.0

#pragma parameter auto_res "          SNES/Amiga Hi-Res Auto Mode" 0.0 0.0 1.0 1.0
float auto_rez = mix(1.0, 2.0, clamp(params.auto_res * round(params.OriginalSize.x/300.0)-1.0, 0.0,1.0));

#pragma parameter FINE_BLOOM "          Fine Bloom/Halation Sampling" 1.0 -1.0 5.0 1.0 
float FINE_BLOOM = (params.FINE_BLOOM > 0.5) ? params.FINE_BLOOM : mix(0.75, 0.5, -params.FINE_BLOOM);

#pragma parameter SIZEHB "          Horizontal Bloom/Halation Radius" 3.0 1.0 50.0 1.0 
#define SIZEHB params.SIZEHB

#pragma parameter SIGMA_HB "          Horizontal Bloom/Halation Sigma" 0.75 0.25 15.0 0.025
#define SIGMA_HB params.SIGMA_HB

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
layout(set = 0, binding = 2) uniform sampler2D LinearizePass;

#define COMPAT_TEXTURE(c,d) texture(c,d)

float invsqrsigma = 1.0/(2.0*SIGMA_HB*SIGMA_HB*auto_rez*auto_rez);

float gaussian(float x)
{
	return exp(-x*x*invsqrsigma);
}

void main()
{
	vec4 SourceSize1 = params.OriginalSize * vec4(FINE_BLOOM, FINE_BLOOM, 1.0/FINE_BLOOM, 1.0/FINE_BLOOM);
	float f = fract(SourceSize1.x * vTexCoord.x);
	f = 0.5 - f;
	vec2 tex = floor(SourceSize1.xy * vTexCoord)*SourceSize1.zw + 0.5*SourceSize1.zw;
	vec4 color = vec4(0.0);
	vec2 dx  = vec2(SourceSize1.z, 0.0);

	float w;
	float wsum = 0.0;
	vec4 pixel;
	float n = -SIZEHB * auto_rez;

	do
	{
		pixel  = COMPAT_TEXTURE(LinearizePass, tex + n*dx);
		w = gaussian(n+f);
		pixel.a = max(max(pixel.r, pixel.g),pixel.b);
		pixel.a*=pixel.a*pixel.a;
		color  = color + w * pixel;
		wsum   = wsum + w;
		n = n + 1.0;
		
	} while (n <= SIZEHB * auto_rez);

	color = color / wsum;
	
	FragColor = vec4(color.rgb, pow(color.a, 0.333333));
}