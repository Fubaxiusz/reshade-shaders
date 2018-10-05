*
Copyright (c) 2018 Jacob Maximilian Fober

This work is licensed under the Creative Commons 
Attribution-ShareAlike 4.0 International License. 
To view a copy of this license, visit 
http://creativecommons.org/licenses/by-sa/4.0/.
*/

// Perfect Perspective PS ver. 2.3.3

  ////////////////////
 /////// MENU ///////
////////////////////

#ifndef ShaderAnalyzer
uniform int FOV <
	ui_label = "Field of View";
	ui_tooltip = "Match in-game Field of View";
	ui_type = "drag";
	ui_min = 1; ui_max = 150;
	ui_category = "Distortion";
> = 120;

uniform int Type <
	ui_label = "Type of FOV";
	ui_tooltip = "If the image bulges in movement (too high FOV), change it to 'Diagonal' \n"
		"When proportions are distorted at the periphery (too low FOV), choose 'Vertical'";
	ui_type = "combo";
	ui_items = "Horizontal FOV\0Diagonal FOV\0Vertical FOV\0";
	ui_category = "Distortion";
> = 0;

uniform float Vertical <
	ui_label = "Vertical Amount";
	ui_tooltip = "Use for minimise horisontal distorsion";
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.0;
	ui_category = "Distortion";
> = 0.8;

uniform bool Debug <
	ui_label = "Display Resolution Map";
	ui_tooltip = "Color map of the Resolution Scale \n"
		" Red    -  Undersampling \n"
		" Green  -  Supersampling \n"
		" Blue   -  Neutral sampling";
	ui_category = "Debug Tools";
> = false;

uniform float ResScale <
	ui_label = "DSR scale factor";
	ui_tooltip = "(DSR) Dynamic Super Resolution... \n"
		"Simulate application running beyond-native screen resolution";
	ui_type = "drag";
	ui_min = 1.0; ui_max = 8.0; ui_step = 0.02;
	ui_category = "Debug Tools";
> = 1.0;
#endif

  //////////////////////
 /////// SHADER ///////
//////////////////////

#include "ReShade.fxh"

// Define screen texture with mirror tiles
sampler SamplerColor
{
	Texture = ReShade::BackBufferTex;
	AddressU = MIRROR;
	AddressV = MIRROR;
};

// Stereographic-Gnomonic lookup function by Jacob Max Fober
// Input data:
	// FOV >> Camera Field of View in degrees
	// Coordinates >> UV coordinates (from -1, to 1), where (0,0) is at the center of the screen
// Shader pass
float3 PerfectPerspectivePS(float4 vois : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	// Get Aspect Ratio
	float AspectR = 1.0 / ReShade::AspectRatio;

	// Convert FOV type..
	float FovType = (Type == 1) ? sqrt(AspectR * AspectR + 1.0) : Type == 2 ? AspectR : 1.0;
	
	// Horizontal FOV 		FovType = 1.0
	// Diagonal FOV			FovType = sqrt(AspectR * AspectR + 1.0)
	// Vertical FOV			FovType = AspectR
	
	// Cjrrect to fov type
	FovType = FOV/FovType;
	// Convert UV to Radial Coordinates 
	float2 SphCoord = texcoord * 2.0 - 1.0;
	
	// Zoom in image and adjust FOV type (pass 1 of 2)
	//SphCoord *= Zooming;
	
	// Stereographic-Gnomonic lookup, vertical distortion amount and FOV type (pass 2 of 2)
	float2 TempSphCoord = SphCoord;
	
	// Stereographic-Gnomonic lookup function by Jacob Max Fober
	// Input data:
	// FOV >> Camera Field of View in degrees
	// Coordinates >> UV coordinates (from -1, to 1), where (0,0) is at the center of the screen
	
	//Horisontal disrorsion
	float SqrTanFOVq = tan(radians(float (FovType) * AspectR * 0.25));
	SqrTanFOVq *= SqrTanFOVq;
	SphCoord.y *= (1.0 - SqrTanFOVq) / (1.0 - SqrTanFOVq * (SphCoord.y * SphCoord.y));
	
	//Vertical disrorsion
	SqrTanFOVq = tan(radians(float (FovType) * 0.25 * Vertical));
	SqrTanFOVq *= SqrTanFOVq;
	SphCoord.x *= (1.0 - SqrTanFOVq) / (1.0 - SqrTanFOVq * (SphCoord.x * SphCoord.x));
	
	// Get Pixel Size in stereographic coordinates
	float2 PixelSize = fwidth(SphCoord);
	
	// Back to UV Coordinates
	SphCoord = SphCoord * 0.5 + 0.5;

	// Sample display image
	float3 Display = tex2D(SamplerColor, SphCoord).rgb;

	// Output type choice
	if (Debug)
	{
		// Calculate radial screen coordinates before and after perspective transformation
		float4 RadialCoord = float4(texcoord, SphCoord) * 2 - 1;
		// Correct vertical aspect ratio
		RadialCoord.yw *= AspectR;

		// Define Mapping color
		float3 UnderSmpl = float3(1, 0, 0.2); // Red
		float3 SuperSmpl = float3(0, 1, 0.5); // Green
		float3 NeutralSmpl = float3(0, 0.5, 1); // Blue

		// Calculate Pixel Size difference...
		float PixelScale = fwidth( length(RadialCoord.xy) );
		// ...and simulate Dynamic Super Resolution (DSR) scalar
		PixelScale /= ResScale * fwidth( length(RadialCoord.zw) );
		PixelScale -= 1;

		// Generate supersampled-undersampled color map
		float3 ResMap = lerp(
			SuperSmpl,
			UnderSmpl,
			saturate(ceil(PixelScale))
		);

		// Create black-white gradient mask of scale-neutral pixels
		PixelScale = 1 - abs(PixelScale);
		PixelScale = saturate(PixelScale * 4 - 3); // Clamp to more representative values

		// Color neutral scale pixels
		ResMap = lerp(ResMap, NeutralSmpl, PixelScale);

		// Blend color map with display image
		Display = normalize(ResMap) * (0.8 * max( max(Display.r, Display.g), Display.b ) + 0.2);
	}

	return Display;
}

technique PerfectPerspective
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PerfectPerspectivePS;
	}
}

