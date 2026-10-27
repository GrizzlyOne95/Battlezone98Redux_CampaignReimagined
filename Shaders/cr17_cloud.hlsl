// Shader model 3 twin of cr17_cloud-sm4.hlsl.
void cloud_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 texMat,
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float2 vTexCoord : TEXCOORD0,
	out float3 vView : TEXCOORD1,
	out float4 oPosition : POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	oPosition.z = oPosition.w * 0.9999;
	vView = iPosition.xyz;
	vTexCoord = mul(texMat, float4(iTexCoord, 0, 1)).xy;
}

void cloud_fragment(
	uniform sampler2D diffuseMap : register(s0),
	uniform float4 tint,
	uniform float3 fogColour,
	uniform float4 horizonBlend,
	in float2 vTexCoord : TEXCOORD0,
	in float3 vView : TEXCOORD1,
	out float4 oColor : COLOR)
{
	float4 c = tex2D(diffuseMap, vTexCoord);
	oColor = float4(lerp(c.rgb * tint.rgb, fogColour, tint.a), c.a);
	float elev = vView.y / max(length(vView), 1e-4);
	float horizon = 1.0 - smoothstep(horizonBlend.x, horizonBlend.y, elev);
	oColor.rgb = lerp(oColor.rgb, fogColour, horizon);
	oColor.a = lerp(oColor.a, 1.0, horizon);
}
