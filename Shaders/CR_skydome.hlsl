// Shader model 3 twin of CR_skydome-sm4.hlsl.
void skydome_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 texMat,
	uniform float4 diffuseColor,
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,
	out float4 oPosition : POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = diffuseColor;
	vTexCoord = mul(texMat, float4(iTexCoord, 0, 1)).xy;
	vDepth = oPosition.z;
}

void skydome_fragment(
	uniform sampler2D diffuseMap : register(s0),
	uniform float3 fogColour,
	uniform float4 fogParams,
	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,
	out float4 oColor : COLOR)
{
	oColor = tex2D(diffuseMap, vTexCoord) * vColor;
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.rgb = lerp(oColor.rgb, fogColour, fogValue);
}
