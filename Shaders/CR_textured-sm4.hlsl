void textured_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,

	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : SV_POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------
// Wind-swayed variant for foliage cards (CR_grasswind.program, CR/GrassWind).
// TEXCOORD1 holds per-vertex (bend, flutter) weights baked by
// Tools/Bake-FoliageSway.py. windParams arrives in the pass specular colour,
// which the textured fragment does not read: xz wind velocity (m/s, world),
// y gust 0..1, w overall scale. windShape: x bend (m), y sway rate (rad/s),
// z flutter (m), w flutter rate (rad/s). Same displacement as WindDisplace in
// cr17_surface.hlsl; keep them in step.

void textured_wind_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 worldMat,
	uniform float4x4 invWorldMat,
	uniform float windTime,
	uniform float4 windParams,
	uniform float4 windShape,

	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	in float2 iSway : TEXCOORD1,

	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : SV_POSITION
)
{
	float speed = length(windParams.xz);
	if (speed >= 0.01 && windParams.w > 0.0)
	{
		float3 worldPos = mul(worldMat, iPosition).xyz;
		float2 dir = windParams.xz / speed;
		float amp = saturate(speed / 20.0) * (1.0 + 0.6 * windParams.y) * windParams.w;
		float phase = dot(worldPos.xz, float2(0.083, 0.061));
		float sway = 0.6 + 0.4 * sin(windTime * windShape.y + phase);
		float3 offset = float3(dir.x, 0.0, dir.y) * (windShape.x * iSway.x * amp * sway);
		float f = windTime * windShape.w;
		offset += (windShape.z * iSway.y * amp) * float3(
			sin(f + phase * 5.3 + worldPos.y * 0.9),
			0.5 * sin(f * 1.37 + phase * 3.1),
			cos(f * 0.83 + phase * 4.7 + worldPos.x * 0.7));
		iPosition.xyz += mul((float3x3)invWorldMat, offset);
	}
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------

#ifdef COCKPIT_SPARK_PASS
float SparkSegmentDistance(float2 p, float2 a, float2 b)
{
	float2 ab = b - a;
	float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-5));
	return distance(p, a + ab * t);
}
#endif

void textured_fragment(
#ifdef ENHANCED_MODE
    uniform float4 surfaceState,
    uniform float4 surfaceMode,
#endif
#ifdef COCKPIT_SPARK_PASS
    uniform float4 surfaceSpark,
#endif
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),

	uniform float4 diffuseColor,
	uniform float4 materialEmissive,

	uniform float3 fogColour,
	uniform float4 fogParams,

	// Cutout threshold in 0..1, matching the material's `alpha_rejection
	// greater_equal N` with N/255. Direct3D 11 has no fixed-function alpha
	// test, so `alpha_rejection` alone is silently inert there and a cutout
	// material renders its transparent pixels as fully shaded ones. Defaults
	// to 0, which discards nothing and leaves every existing consumer alone.
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
#if defined(ENHANCED_MODE) && !defined(COCKPIT_SPARK_PASS)
	// Enhanced only (Default/Retro DXBC must stay identical): begin cockpit
	// warning flicker below half hull, then cycle a critical blackout and brief
	// red alarm flash below the 25% health stage. surfaceMode.w is critical;
	// surfaceState.w remains the separate hit-triggered brownout.
	float damage = saturate(surfaceState.y);
	float warning = smoothstep(0.50, 0.80, damage) * saturate(surfaceMode.y);
	float critical = saturate(surfaceMode.w);
	float pulse = 0.5 + 0.5 * sin(surfaceMode.z * lerp(7.0, 12.0, critical));
	float brownout = saturate(surfaceState.w);
	float flicker = warning * (0.12 + pulse * 0.58);
	float blackout = critical * (1.0 - smoothstep(0.30, 0.52, pulse));
	float3 unpoweredGlow = oColor.rgb;
	float glowPeak = max(unpoweredGlow.r, max(unpoweredGlow.g, unpoweredGlow.b));
	oColor.rgb *= (1.0 - brownout) * (1.0 - flicker) * (1.0 - blackout);
	float alarmFlash = critical * smoothstep(0.75, 0.95, pulse);
	float3 warningRed = float3(glowPeak * 1.25, glowPeak * 0.08, glowPeak * 0.025);
	oColor.rgb = lerp(oColor.rgb, warningRed, alarmFlash);
#endif

#ifdef COCKPIT_SPARK_PASS
	// The CPU chooses a brief burst cell and seed; this second pass draws a
	// jagged arc on the cockpit submesh's UV-mapped surface.
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
#endif
	// Before fog and before any depth write: a discarded pixel must not reach
	// the depth buffer, or a nearer card's empty space masks the cards behind
	// it.
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
