void textured_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,

	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : SV_POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------
// Wind-swayed variant for foliage cards (CR_grasswind.program, CR/GrassWind).
// TEXCOORD1 holds per-vertex (bend, flutter) weights baked by
// Tools/Bake-FoliageSway.py. windParams arrives in the pass specular colour,
// which the textured fragment does not read: xz wind velocity (m/s, world),
// y gust 0..1, w overall scale. windShape: x bend (m), y sway rate (rad/s),
// z flutter (m), w flutter rate (rad/s). Same displacement as WindDisplace in
// cr17_surface.hlsl; keep them in step.

void textured_wind_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 worldMat,
	uniform float4x4 invWorldMat,
	uniform float windTime,
	uniform float4 windParams,
	uniform float4 windShape,

	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	in float2 iSway : TEXCOORD1,

	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : SV_POSITION
)
{
	float speed = length(windParams.xz);
	if (speed >= 0.01 && windParams.w > 0.0)
	{
		float3 worldPos = mul(worldMat, iPosition).xyz;
		float2 dir = windParams.xz / speed;
		float amp = saturate(speed / 20.0) * (1.0 + 0.6 * windParams.y) * windParams.w;
		float phase = dot(worldPos.xz, float2(0.083, 0.061));
		float sway = 0.6 + 0.4 * sin(windTime * windShape.y + phase);
		float3 offset = float3(dir.x, 0.0, dir.y) * (windShape.x * iSway.x * amp * sway);
		float f = windTime * windShape.w;
		offset += (windShape.z * iSway.y * amp) * float3(
			sin(f + phase * 5.3 + worldPos.y * 0.9),
			0.5 * sin(f * 1.37 + phase * 3.1),
			cos(f * 0.83 + phase * 4.7 + worldPos.x * 0.7));
		iPosition.xyz += mul((float3x3)invWorldMat, offset);
	}
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------

void textured_fragment(
#ifdef ENHANCED_MODE
    uniform float4 surfaceState,
    uniform float4 surfaceMode,
#endif
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),

	uniform float4 diffuseColor,
	uniform float4 materialEmissive,

	uniform float3 fogColour,
	uniform float4 fogParams,

	// Cutout threshold in 0..1, matching the material's `alpha_rejection
	// greater_equal N` with N/255. Direct3D 11 has no fixed-function alpha
	// test, so `alpha_rejection` alone is silently inert there and a cutout
	// material renders its transparent pixels as fully shaded ones. Defaults
	// to 0, which discards nothing and leaves every existing consumer alone.
	uniform float alphaRejection,

	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : SV_DEPTH
#endif
)
{
	float4 diffuseTex = diffuseMap.Sample(diffuseSam, vTexCoord);
	oColor = diffuseTex * diffuseColor;
	oColor.rgb *= materialEmissive.rgb;
#ifdef ENHANCED_MODE
	// Enhanced only (Default/Retro DXBC must stay identical): match the lit
	// cockpit warning pulse and tower power state.
	float warning = saturate(surfaceState.y) * saturate(surfaceMode.y);
	float pulse = 0.5 + 0.5 * sin(surfaceMode.z * 7.0);
	oColor.rgb *= (1.0-saturate(surfaceState.w)) * (1.0-warning*(0.12+pulse*0.58));
#endif

	// Before fog and before any depth write: a discarded pixel must not reach
	// the depth buffer, or a nearer card's empty space masks the cards behind
	// it.
	clip(oColor.a - alphaRejection);

	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, fogColour, fogValue);
	
#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
