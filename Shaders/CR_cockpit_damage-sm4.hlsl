// Dedicated fragment shader for the player's UV-mapped cockpit damage pass.
// It draws the soot texture everywhere selected by diffuse alpha, then adds a
// brief CPU-selected arc cell on top. The material owns UV layout; no screen
// coordinates or cockpit-specific mesh data are assumed here.

float SparkSegmentDistance(float2 p, float2 a, float2 b)
{
	float2 ab = b - a;
	float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-5));
	return distance(p, a + ab * t);
}

void cockpit_damage_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),

	uniform float4 diffuseColor,
	uniform float4 materialEmissive,
	uniform float4 surfaceSpark,

	uniform float3 fogColour,
	uniform float4 fogParams,
	uniform float alphaRejection,

	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : SV_DEPTH
#endif
)
{
	float4 diffuseTex = diffuseMap.Sample(diffuseSam, vTexCoord);
	oColor = diffuseTex * diffuseColor;
	oColor.rgb *= materialEmissive.rgb;

	// Lua picks a short-lived UV cell and seed. The shader draws a jagged
	// polyline inside that cell so the flash follows cockpit geometry and UVs.
	if (surfaceSpark.x > 0.001)
	{
		float2 grid = float2(12.0, 8.0);
		float2 wrappedUv = frac(vTexCoord);
		float2 cell = floor(wrappedUv * grid);
		float selected = step(abs(cell.x - surfaceSpark.y), 0.1)
			* step(abs(cell.y - surfaceSpark.z), 0.1);
		float2 localUv = frac(wrappedUv * grid);
		float seed = frac(surfaceSpark.w);
		if (seed > 0.5) localUv = localUv.yx;
		float x0 = 0.18 + frac(seed * 13.37) * 0.64;
		float x1 = 0.12 + frac(seed * 37.11 + 0.31) * 0.76;
		float x2 = 0.15 + frac(seed * 71.93 + 0.17) * 0.70;
		float x3 = 0.24 + frac(seed * 19.73 + 0.59) * 0.58;
		float2 a = float2(x0, 0.08);
		float2 b = float2(x1, 0.36);
		float2 c = float2(x2, 0.64);
		float2 d = float2(x3, 0.92);
		float arcDistance = min(SparkSegmentDistance(localUv, a, b),
			min(SparkSegmentDistance(localUv, b, c), SparkSegmentDistance(localUv, c, d)));
		float core = 1.0 - smoothstep(0.006, 0.024, arcDistance);
		float halo = 1.0 - smoothstep(0.02, 0.13, arcDistance);
		float arc = max(core, halo * 0.28) * selected * saturate(surfaceSpark.x);
		float sparkAlpha = saturate(arc * 0.94);
		oColor.rgb = lerp(oColor.rgb, float3(0.55, 0.82, 1.15), saturate(arc * 1.35));
		oColor.a = max(oColor.a, sparkAlpha);
	}

	// Preserve the textured fragment's cutout and fog behavior for the overlay.
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
