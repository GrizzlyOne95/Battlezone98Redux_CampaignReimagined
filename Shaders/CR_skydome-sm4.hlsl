// Sky dome/plane twin of the stock Effect program with no COLOR0 input: Ogre's
// generated sky geometry has position, normal and UV0 only. The material's
// diffuse stands in for the missing vertex colour, as the vertex colour of a
// D3D9 stream without one reads white.
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
	out float4 oPosition : SV_POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	float4 viewPosition = mul(inverseProjection, oPosition);
	vView = mul((float3x3)inverseView, viewPosition.xyz / viewPosition.w);
	vColor = diffuseColor;
	vTexCoord = mul(texMat, float4(iTexCoord, 0, 1)).xy;
	oPosition.z = oPosition.w * 0.9999;
}

// Display-referred sky art stays unchanged. Only the fully fogged edge uses
// the Enhanced ambient-haze calibration, selected by the runtime profile.
float3 sky_decode(float3 c)
{
 c=max(c,0);return lerp(c/12.92,pow((c+.055)/1.055,2.4),step(.04045,c));
}
float3 sky_encode(float3 c)
{
 c=max(c,0);return lerp(c*12.92,1.055*pow(max(c,1e-8),1.0/2.4)-.055,step(.0031308,c));
}
void skydome_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),
	uniform float3 fogColour,
	uniform float4 fogParams,
	uniform float4 horizonBlend,
	uniform float4 sceneAmbient,
	uniform float4 skyProfile,
	uniform float4 fogAmbient,
	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float3 vView : TEXCOORD1,
	out float4 oColor : SV_TARGET)
{
	oColor = diffuseMap.Sample(diffuseSam, vTexCoord) * vColor;
	// Match only the low sky to the composed fog. Depth fog on a distant
	// dome erased the overhead cloud art and left a flat coloured lid.
	float elevation = vView.y / max(length(vView), 1e-4);
	float fogValue = (1-smoothstep(horizonBlend.x, horizonBlend.y, elevation)) * horizonBlend.z * step(1e-8, fogParams.w);
	float3 edgeColour=fogColour;
#if defined(CR_WORLD_SKY)
	if(skyProfile.r>.5) {
	 float3 authored=sky_decode(fogColour);
	 edgeColour=sky_encode(lerp(authored,saturate(authored+sceneAmbient.rgb*fogAmbient.x),fogAmbient.y));
	}
#endif
	oColor.rgb = lerp(oColor.rgb, edgeColour, fogValue);
}
