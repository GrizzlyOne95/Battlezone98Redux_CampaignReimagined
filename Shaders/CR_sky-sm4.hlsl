void sky_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,
	in float2 iTexCoord : TEXCOORD0,

	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : SV_POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor.bgra;
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------

void sky_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),
	uniform float twinkleTime,
	uniform float4 twinkleControl,

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : SV_DEPTH
#endif
)
{
	float4 diffuseTex = diffuseMap.Sample(diffuseSam, vTexCoord);
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


// URANUS.MAP haze: the planet seen through the overcast. The disc is thinned
// (hazeParams.x opacity), tinted toward the fog colour (hazeTint, mixed by
// hazeParams.y) and faded by a slowly drifting cloud mask taken from the map's
// own cloud alpha (second texture unit, acloud2). hazeParams.z is the drift in
// UV per second; time_0_x wraps at 1000 s, so pick z so z*1000 is a whole number.
// hazeParams.w is how hard the cloud mask covers the disc.
void sky_haze_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),
	uniform Texture2D maskMap : register(t1),
	uniform SamplerState maskSam : register(s1),
	uniform float hazeTime,
	uniform float4 hazeParams,
	uniform float4 hazeTint,

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : SV_DEPTH
#endif
)
{
	float4 tex = diffuseMap.Sample(diffuseSam, vTexCoord) * vColor;
	float2 drift = float2(frac(hazeTime * hazeParams.z), frac(hazeTime * hazeParams.z * 0.37));
	float m = maskMap.Sample(maskSam, vTexCoord * 2.5 + drift).a * 0.6
	        + maskMap.Sample(maskSam, vTexCoord * 1.3 - drift * 0.6 + 0.37).a * 0.4;
	float cover = saturate(m * hazeParams.w);
	oColor.rgb = lerp(tex.rgb, hazeTint.rgb, hazeParams.y);
	oColor.a = tex.a * hazeParams.x * lerp(1.0, 0.15, cover);

#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}

