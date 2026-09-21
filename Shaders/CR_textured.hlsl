void textured_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,

	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------

void textured_fragment(
	uniform sampler2D diffuseMap : register(s0),

	uniform float4 diffuseColor,
	uniform float4 materialEmissive,

	uniform float3 fogColour,
	uniform float4 fogParams,

	// Cutout threshold in 0..1. Direct3D 9 does have a fixed-function alpha
	// test, so this is redundant here -- it exists so the SM3 and SM4 paths
	// cut at the same place rather than only agreeing by coincidence.
	// Defaults to 0, which discards nothing.
	uniform float alphaRejection,

	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : COLOR
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : DEPTH
#endif
)
{
	float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
	oColor = diffuseTex * diffuseColor;
	oColor.rgb *= materialEmissive.rgb;

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
