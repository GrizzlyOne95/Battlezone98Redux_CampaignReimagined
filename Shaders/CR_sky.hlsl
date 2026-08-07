void sky_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,
	in float2 iTexCoord : TEXCOORD0,

	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor;
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------

void sky_fragment(
	uniform sampler2D diffuseMap : register(s0),
	uniform float twinkleTime,
	uniform float4 twinkleControl,

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : COLOR
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : DEPTH
#endif
)
{
	float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
	oColor = diffuseTex * vColor;

	// STARS.MAP enables this through its otherwise-unused emissive pass color.
	// Quantized UVs give nearby star pixels a stable phase without shimmering
	// when the camera moves.
	float2 starCell = floor(vTexCoord * 512.0);
	float starSeed = frac(sin(dot(starCell, float2(12.9898, 78.233))) * 43758.5453);
	float twinkleWave = 0.5 + 0.5 * sin(twinkleTime * (0.9 + starSeed * 1.7) + starSeed * 6.2831853);
	float twinkleStrength = saturate(max(twinkleControl.x, max(twinkleControl.y, twinkleControl.z)));
	float twinkle = lerp(1.0, lerp(0.72, 1.12, twinkleWave), twinkleStrength);
	oColor.rgb *= twinkle;
	
#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
