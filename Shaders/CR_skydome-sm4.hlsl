// Sky dome/plane twin of the stock Effect program with no COLOR0 input: Ogre's
// generated sky geometry has position, normal and UV0 only. The material's
// diffuse stands in for the missing vertex colour, as the vertex colour of a
// D3D9 stream without one reads white.
void skydome_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 texMat,
	uniform float4 diffuseColor,
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,
	out float4 oPosition : SV_POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = diffuseColor;
	vTexCoord = mul(texMat, float4(iTexCoord, 0, 1)).xy;
	vDepth = oPosition.z;
}

void skydome_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),
	uniform float3 fogColour,
	uniform float4 fogParams,
	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,
	out float4 oColor : SV_TARGET)
{
	oColor = diffuseMap.Sample(diffuseSam, vTexCoord) * vColor;
	// Same depth fog as Effect: a dome past fogEnd takes the fog colour, which
	// is what lets a weather sky meet the fogged horizon.
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.rgb = lerp(oColor.rgb, fogColour, fogValue);
}
