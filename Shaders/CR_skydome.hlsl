// Shader model 3 twin of CR_skydome-sm4.hlsl.
void skydome_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 inverseProjection,
	uniform float4x4 inverseView,
	uniform float4x4 texMat,
	uniform float4 diffuseColor,
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,
	out float3 vView : TEXCOORD1,
	out float4 oPosition : POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	float4 viewPosition = mul(inverseProjection, oPosition);
	vView = mul((float3x3)inverseView, viewPosition.xyz / viewPosition.w);
	vColor = diffuseColor;
	vTexCoord = mul(texMat, float4(iTexCoord, 0, 1)).xy;
	oPosition.z = oPosition.w * 0.9999;
}

void skydome_fragment(
	uniform sampler2D diffuseMap : register(s0),
	uniform float3 fogColour,
	uniform float4 fogParams,
	uniform float4 horizonBlend,
	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float3 vView : TEXCOORD1,
	out float4 oColor : COLOR)
{
	oColor = tex2D(diffuseMap, vTexCoord) * vColor;
	float elevation = vView.y / max(length(vView), 1e-4);
	float fogValue = (1-smoothstep(horizonBlend.x, horizonBlend.y, elevation)) * horizonBlend.z * step(1e-8, fogParams.w);
	oColor.rgb = lerp(oColor.rgb, fogColour, fogValue);
}
