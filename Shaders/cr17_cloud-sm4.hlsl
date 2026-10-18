// Storm cloud deck for Ogre's generated sky plane, which carries position,
// normal and one UV set but no vertex colour: the stock Effect and Sky programs
// read COLOR0 and cannot bind to it on Direct3D 11.
void cloud_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 texMat,
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float2 vTexCoord : TEXCOORD0,
	out float4 oPosition : SV_POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = mul(texMat, float4(iTexCoord, 0, 1)).xy;
}

void cloud_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),
	uniform float4 tint,
	uniform float3 fogColour,
	in float2 vTexCoord : TEXCOORD0,
	out float4 oColor : SV_TARGET)
{
	float4 c = diffuseMap.Sample(diffuseSam, vTexCoord);
	// tint.rgb darkens the cloud art; tint.a is how far it sinks into the fog.
	oColor = float4(lerp(c.rgb * tint.rgb, fogColour, tint.a), c.a);
}
