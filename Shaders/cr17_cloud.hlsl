// Shader model 3 twin of cr17_cloud-sm4.hlsl.
void cloud_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 texMat,
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float2 vTexCoord : TEXCOORD0,
	out float4 oPosition : POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = mul(texMat, float4(iTexCoord, 0, 1)).xy;
}

void cloud_fragment(
	uniform sampler2D diffuseMap : register(s0),
	uniform float4 tint,
	uniform float3 fogColour,
	in float2 vTexCoord : TEXCOORD0,
	out float4 oColor : COLOR)
{
	float4 c = tex2D(diffuseMap, vTexCoord);
	oColor = float4(lerp(c.rgb * tint.rgb, fogColour, tint.a), c.a);
}
