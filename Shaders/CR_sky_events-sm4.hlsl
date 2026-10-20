// Campaign Reimagined sky events: shooting stars and satellites (DX11, SM4).
// Keep the math identical to CR_sky_events.hlsl.
//
// Both effects are procedural [Stars] entries drawn with additive blend.
// Every quad shares the same UVs, so each entry derives its own seed from the
// TRN Color%02d value (vertex colour): give each entry a distinct colour.
//
// skyTime is time_0_x 3600. Every period below divides 3600, so the wrap
// lands on a slot/cycle boundary where nothing is visible.
// skyControl is the pass emissive colour: x enables the effect (Lua sets it
// to 0 to switch effects off), y forces every slot to fire (testing only).

float SkyEventHash(float p)
{
	p = frac(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return frac(p);
}

float SkyEventSeed(float3 color)
{
	float3 c = floor(color * 255.0 + 0.5);
	return dot(c, float3(1.0, 7.13, 31.7));
}

// Converts a UV offset into screen pixels using the quad's UV derivatives,
// so points and streak widths stay a fixed pixel size at any quad aspect.
float2 SkyEventUvToPixels(float2 duv, float2 dx, float2 dy)
{
	float det = dx.x * dy.y - dx.y * dy.x;
	det = det >= 0.0 ? max(det, 1e-12) : min(det, -1e-12);
	return float2(duv.x * dy.y - duv.y * dy.x, dx.x * duv.y - dx.y * duv.x) / det;
}

float3 SkyMeteor(float2 uv, float2 dx, float2 dy, float seed, float t, float force)
{
	const float period = 25.0;   // 144 slots per 3600 s wrap
	float slot = floor(t / period);
	float local = t - slot * period;
	float k = slot + seed * 157.0;

	float rate = lerp(0.17, 1.0, saturate(force));
	if (SkyEventHash(k + 0.11) >= rate)
		return float3(0.0, 0.0, 0.0);

	float dur = 0.3 + 0.5 * SkyEventHash(k + 1.73);
	float t0 = 0.5 + SkyEventHash(k + 2.39) * (period - dur - 1.0);
	float u = (local - t0) / dur;
	if (u <= 0.0 || u >= 1.0)
		return float3(0.0, 0.0, 0.0);

	float ang = SkyEventHash(k + 3.97) * 6.2831853;
	float2 dir = float2(cos(ang), sin(ang));
	float2 perp = float2(-dir.y, dir.x);
	float pathLen = 0.45 + 0.35 * SkyEventHash(k + 4.51);
	float2 mid = 0.5 + perp * ((SkyEventHash(k + 5.27) - 0.5) * 0.4);
	float2 start = mid - dir * (pathLen * 0.5);
	float2 head = start + dir * (pathLen * u);
	float tailLen = min(pathLen * (0.18 + 0.12 * SkyEventHash(k + 6.83)), pathLen * u);
	float2 tail = head - dir * tailLen;

	float s = saturate(dot(uv - tail, dir) / max(tailLen, 1e-5));
	float2 corePx = SkyEventUvToPixels(uv - (tail + dir * (tailLen * s)), dx, dy);
	float core = exp(-dot(corePx, corePx) * 0.62) * s * s;
	float2 headPx = SkyEventUvToPixels(uv - head, dx, dy);
	float hd2 = dot(headPx, headPx);
	float glow = exp(-hd2 * 0.6) + 0.35 * exp(-hd2 * 0.1);

	float env = smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.65, 1.0, u));
	float bright = (0.8 + 0.7 * SkyEventHash(k + 7.19)) * env;
	float3 tint = lerp(float3(1.0, 0.78, 0.55), float3(0.88, 1.0, 0.96), s);
	return tint * (bright * (1.3 * core + glow));
}

float3 SkySatellite(float2 uv, float2 dx, float2 dy, float seed, float t, float force)
{
	const float cycle = 300.0;   // 12 cycles per 3600 s wrap
	float tt = t + SkyEventHash(seed * 3.1 + 0.37) * cycle;
	float cyc = floor(tt / cycle);
	float ph = tt - cyc * cycle;
	float k = cyc + seed * 91.0;

	float chance = lerp(0.75, 1.0, saturate(force));
	if (SkyEventHash(k + 0.71) >= chance)
		return float3(0.0, 0.0, 0.0);

	float passDur = 70.0 + 110.0 * SkyEventHash(k + 5.13);
	float ts = SkyEventHash(k + 9.21) * (cycle - passDur);
	float s = (ph - ts) / passDur;
	if (s <= 0.0 || s >= 1.0)
		return float3(0.0, 0.0, 0.0);

	float x = lerp(0.02, 0.98, s);
	if (SkyEventHash(k + 1.91) > 0.5)
		x = 1.0 - x;
	float y = 0.3 + 0.4 * SkyEventHash(k + 2.93)
		+ (SkyEventHash(k + 4.47) - 0.5) * 0.3 * (s - 0.5);
	float2 px = SkyEventUvToPixels(uv - float2(x, y), dx, dy);
	float spot = exp(-dot(px, px) * 0.9);

	float bright = 0.32 + 0.28 * SkyEventHash(k + 6.61);
	bright *= 1.0 + 0.2 * sin(ph * (0.5 + SkyEventHash(k + 3.33)));
	if (SkyEventHash(k + 8.83) < 0.4)
	{
		float g = (s - (0.25 + 0.5 * SkyEventHash(k + 7.77))) / 0.025;
		bright += 2.6 * exp(-g * g);
	}
	float fade = smoothstep(0.0, 0.06, s) * smoothstep(0.0, 0.06, 1.0 - s);
	return float3(0.95, 0.97, 1.0) * (spot * bright * fade);
}

void sky_meteor_fragment(
	uniform float skyTime,
	uniform float4 skyControl,

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : SV_DEPTH
#endif
)
{
	float2 dx = ddx(vTexCoord);
	float2 dy = ddy(vTexCoord);
	float enable = saturate(skyControl.x);
	float3 c = float3(0.0, 0.0, 0.0);
	if (enable > 0.0)
		c = SkyMeteor(vTexCoord, dx, dy, SkyEventSeed(vColor.rgb), skyTime, skyControl.y);
	c *= vColor.rgb * enable;
	oColor = float4(c, saturate(max(c.r, max(c.g, c.b))));

#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}

void sky_satellite_fragment(
	uniform float skyTime,
	uniform float4 skyControl,

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : SV_DEPTH
#endif
)
{
	float2 dx = ddx(vTexCoord);
	float2 dy = ddy(vTexCoord);
	float enable = saturate(skyControl.x);
	float3 c = float3(0.0, 0.0, 0.0);
	if (enable > 0.0)
		c = SkySatellite(vTexCoord, dx, dy, SkyEventSeed(vColor.rgb), skyTime, skyControl.y);
	c *= vColor.rgb * enable;
	oColor = float4(c, saturate(max(c.r, max(c.g, c.b))));

#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
