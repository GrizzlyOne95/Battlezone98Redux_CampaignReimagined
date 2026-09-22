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

void textured_fragment(
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
