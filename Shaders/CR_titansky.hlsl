// Campaign Reimagined: Titan sky dome (CRSKYTI.MAP, Materials/crart_titan.material).
// One source for DX11 (SM4=1) and DX9 (SM3); there is no GLSL twin, so OpenGL
// falls through to the material's CR_SkyDome technique (the flat stock look).
//
// Titan's sky is a thick orange photochemical haze. Every colour comes from the
// composed fog, so the horizon always meets the terrain fog and the sky follows
// the weather:
//   - a gradient from the fog at the horizon to a duller, browner zenith;
//   - the sun as a soft glow with no disc, fading as the haze thickens;
//   - broad haze bands, billowing banks and rare methane streaks from
//     crsky_titan_haze.png (Tools/Build-TitanSky.py), drifting slowly with the
//     weak wind;
//   - a haze roll flattens the sky toward the fog and thickens the banks;
//   - Saturn, faint through the haze: an oblate, banded globe lit by the sun
//     with its rings (crsky_saturn.png, crsky_saturn_rings.png), the rings'
//     shadow on the globe and the globe's shadow on the rings. The haze in
//     front of it (the rung, the roll and the drifting banks) decides how much
//     shows, so the rings fade in and out as the banks pass. At night a full
//     Saturn lights the haze round it.
// Titan keeps one face to Saturn and orbits in the ring plane, so from the
// ground Saturn hangs still and the real rings are almost edge-on (0.3 deg).
// saturnShape.z opens them a little so they read at a glance; set it to
// 0.006 for the true view.
// CRWorldArt.UpdateSky feeds the frame state through the pass colours:
// specular = (Enhanced profile flag, direction toward the sun),
// emissive = (night blend, clarity, haze (the weather rung), haze roll),
// ambient  = (direction toward Saturn, 1 when the map has a Saturn).
// CRTitanWeather.SkyState publishes the haze and the roll (Environment forwards them).

#if defined(SM4)
#define DECLARE_MAP(name, reg) Texture2D name : register(t##reg); SamplerState name##Sam : register(s##reg);
#define SAMPLE(name, uv) name.Sample(name##Sam, uv)
#define POSITION_OUT SV_POSITION
#define COLOUR_OUT SV_TARGET
#else
#define DECLARE_MAP(name, reg) sampler2D name : register(s##reg);
#define SAMPLE(name, uv) tex2D(name, uv)
#define POSITION_OUT POSITION
#define COLOUR_OUT COLOR
#endif

// Unit 0 is titan.tga, used only by the fallback technique.
DECLARE_MAP(hazeMap, 1)
DECLARE_MAP(saturnMap, 2)
DECLARE_MAP(ringMap, 3)

static const float PI = 3.14159265;
// The ring map runs from 1.110 to 2.331 Saturn equatorial radii.
static const float RING_INNER = 1.110;
static const float RING_SPAN = 1.221;

void titansky_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 inverseProjection,
	uniform float4x4 inverseView,
	in float4 iPosition : POSITION,
	out float3 vView : TEXCOORD0,
	out float4 oPosition : POSITION_OUT)
{
	oPosition = mul(wvpMat, iPosition);
	float4 viewPosition = mul(inverseProjection, oPosition);
	vView = mul((float3x3)inverseView, viewPosition.xyz / viewPosition.w);
	oPosition.z = oPosition.w * 0.9999;
}

float3 sky_decode(float3 c)
{
	c = max(c, 0); return lerp(c / 12.92, pow((c + .055) / 1.055, 2.4), step(.04045, c));
}
float3 sky_encode(float3 c)
{
	c = max(c, 0); return lerp(c * 12.92, 1.055 * pow(max(c, 1e-8), 1.0 / 2.4) - .055, step(.0031308, c));
}

// zenithTint:  rgb sky overhead as a multiple of the horizon, w gradient exponent.
// sunGlow:     x core gain, y wide gain, z core exponent, w wide exponent.
// hazeScale:   x band UV per deck unit, y bank UV per deck unit, z wind (UV/s),
//              w deck horizon lift (flattens the projection near the horizon).
// hazeLook:    x band contrast, y bank contrast, z streak brightness, w extra
//              bank contrast at full roll.
// rollLook:    x share of the sky a full roll flattens, y flat sky brightness
//              as a multiple of the fog.
// saturnShape: x distance in Saturn equatorial radii (Titan's orbit, 20.3),
//              y polar / equatorial radius, z ring opening (radians), w roll of
//              the pole from straight up (radians).
// saturnLook:  x brightness (linear), y share seen through a clear sky, z share
//              at full haze, w share a full roll hides.
// ringLook:    x lit-face brightness, y unlit-face brightness, z bank share
//              that hides it (how much the drifting haze matters), w ring
//              shadow strength on the globe.
// saturnGlow:  x halo gain round a lit Saturn at night, y halo exponent,
//              z halo gain by day.
// hazeTint:    rgb what the haze lets through from Saturn.
void titansky_fragment(
	uniform float3 fogColour,
	uniform float4 fogParams,
	uniform float4 horizonBlend,
	uniform float4 sceneAmbient,
	uniform float4 skyProfile,
	uniform float4 titanState,
	uniform float4 saturnDir,
	uniform float4 fogAmbient,
	uniform float skyTime,
	uniform float4 zenithTint,
	uniform float4 sunGlow,
	uniform float4 hazeScale,
	uniform float4 hazeLook,
	uniform float4 rollLook,
	uniform float4 saturnShape,
	uniform float4 saturnLook,
	uniform float4 ringLook,
	uniform float4 saturnGlow,
	uniform float4 hazeTint,
	in float3 vView : TEXCOORD0,
	out float4 oColor : COLOUR_OUT)
{
	float3 V = normalize(vView);
	float elevation = V.y;

	// Horizon colour: the composed fog, with the Enhanced ambient-haze match of CR_skydome.
	float3 edgeColour = fogColour;
	if (skyProfile.r > .5) {
		float3 authored = sky_decode(fogColour);
		edgeColour = sky_encode(lerp(authored, saturate(authored + sceneAmbient.rgb * fogAmbient.x), fogAmbient.y));
	}
	float3 H = sky_decode(edgeColour);

	float night = saturate(titanState.r);
	float clarity = saturate(titanState.g);
	float haze = saturate(titanState.b);
	float roll = saturate(titanState.a);

	float3 S = skyProfile.gba;
	S = normalize(dot(S, S) > 1e-6 ? S : float3(0, 1, 0));
	float c = dot(V, S);
	float up = saturate(elevation);
	float day = 1 - night;

	// Gradient: the fog at the horizon, a duller, browner zenith.
	float3 sky = lerp(H, H * zenithTint.rgb, pow(up, zenithTint.w));

	// The haze seen from below as a flat layer: broad bands roll with the wind,
	// the banks drift slower and a little across it, rare streaks race ahead.
	float2 deck = V.xz / (max(elevation, 0) + hazeScale.w);
	float2 wind = float2(1, 0.3) * skyTime * hazeScale.z;
	float bands = SAMPLE(hazeMap, deck * hazeScale.x + wind).r;
	float banks = SAMPLE(hazeMap, deck * hazeScale.y + float2(wind.x * 0.7, -wind.y) + 0.37).g;
	float streaks = SAMPLE(hazeMap, deck * hazeScale.y * 1.8 + wind * 1.3 + 0.61).b;
	float deckFade = smoothstep(0.0, 0.3, elevation);
	float bandShade = (bands - 0.5) * hazeLook.x;
	float bankShade = (banks - 0.45) * hazeLook.y * (1 + hazeLook.w * roll);
	// Thicker haze is darker and browner below.
	sky *= 1 - (bandShade + bankShade) * deckFade * float3(1, 1.1, 1.25);
	sky += H * float3(1, 0.92, 0.8) * streaks * hazeLook.z * deckFade * (1 - 0.6 * night);
	float thick = saturate(0.5 + bandShade + bankShade);

	// The sun: no disc, only a soft glow that the haze smothers as it thickens,
	// over a wide brightening of the whole sun side.
	float sunLift = (1 - 0.6 * haze) * (1 - 0.7 * roll) * (0.5 + 0.5 * clarity) * day;
	float core = pow(saturate(c), sunGlow.z) * (1 - 0.5 * thick);
	float wide = pow(saturate(c * 0.5 + 0.5), sunGlow.w);
	float level = max(dot(H, float3(0.2126, 0.7152, 0.0722)), 0.01);
	sky += float3(1.0, 0.86, 0.58) * level * core * sunGlow.x * sunLift;
	sky *= 1 + wide * sunGlow.y * sunLift;

	// A roll: the sky flattens into the fog colour.
	sky = lerp(sky, H * rollLook.y, roll * rollLook.x);

	// Saturn. Camera at the origin, Saturn's centre at D * distance, lengths in
	// its equatorial radius. N is the ring plane's normal (and the globe's pole):
	// the pole leans toward the viewer by the ring opening. W points from Saturn
	// toward the viewer in its equator plane, X across the sky.
	float3 D = saturnDir.xyz;
	D = normalize(dot(D, D) > 1e-6 ? D : float3(0, 0, 1));
	float3 P0 = normalize(float3(0, 1, 0) - D * D.y + float3(1e-4, 0, 0));
	float3 P = P0 * cos(saturnShape.w) + cross(D, P0) * sin(saturnShape.w);
	float3 N = normalize(P * cos(saturnShape.z) - D * sin(saturnShape.z));
	float3 W = normalize(-D - N * dot(-D, N));
	float3 X = cross(N, W);
	float3 C = D * saturnShape.x;
	float f = saturnShape.y;

	// The globe, an oblate spheroid: a unit sphere once the pole axis is
	// stretched by 1 / f. Outside the disc the nearest point stands in, so the
	// texture coordinates stay smooth for the mip choice.
	float3 v1 = float3(dot(V, X), dot(V, W), dot(V, N) / f);
	float3 c1 = float3(dot(C, X), dot(C, W), dot(C, N) / f);
	float qa = dot(v1, v1);
	float qb = dot(v1, c1);
	float disc = qb * qb - qa * (dot(c1, c1) - 1);
	float tPlanet = (qb - sqrt(max(disc, 0))) / qa;
	float cover = saturate(disc / max(fwidth(disc) * 1.5, 1e-7));
	float3 q = v1 * tPlanet - c1;
	float3 Hp = V * tPlanet - C;
	float3 normal = normalize(X * q.x + W * q.y + N * (q.z / f));
	float lat = asin(clamp(q.z / max(length(q), 1e-4), -1, 1));
	float lon = atan2(q.x, q.y);
	float3 globe = sky_decode(SAMPLE(saturnMap, float2(0.5 + lon / (2 * PI), 0.5 - lat / PI)).rgb);
	// Minnaert limb darkening, as CR_jovian.
	float mu0 = saturate(dot(normal, S));
	float mu = saturate(dot(normal, -V));
	float lit = pow(mu0, 0.9) * pow(max(mu, 1e-3), -0.1) * saturate(mu0 * 8);
	// The rings' shadow on the globe.
	float sn = dot(S, N);
	float sToRing = -dot(Hp, N) / (abs(sn) > 1e-4 ? sn : 1e-4);
	float rShadow = length(Hp + S * sToRing);
	float shadowOpacity = SAMPLE(ringMap, float2(saturate((rShadow - RING_INNER) / RING_SPAN), 0.5)).a;
	shadowOpacity *= step(0, sToRing) * step(RING_INNER, rShadow) * step(rShadow, RING_INNER + RING_SPAN);
	float3 planet = globe * lit * (1 - ringLook.w * shadowOpacity);

	// The rings: where the view ray crosses the ring plane.
	float vn = dot(V, N);
	float tRing = dot(C, N) / (abs(vn) > 1e-5 ? vn : 1e-5);
	float3 R = V * tRing - C;
	float r = length(R);
	float u = (r - RING_INNER) / RING_SPAN;
	float4 ring = SAMPLE(ringMap, float2(saturate(u), 0.5));
	float ringA = ring.a * step(0, tRing) * step(0, u) * step(u, 1);
	ring.rgb = sky_decode(ring.rgb);
	// The lit face shows the sun's light; from the dark face only what filters
	// through, so the thin C ring and the Cassini Division glow and the B ring
	// goes dark.
	float sunOnRing = saturate(abs(sn) * 3 + 0.15);
	float litFace = step(0, sn * dot(-V, N));
	float3 ringLight = ring.rgb * sunOnRing * lerp(ringLook.y * (1 - ring.a) * 2, ringLook.x, litFace);
	// The globe's shadow on the rings.
	float rb = dot(R, S);
	float rc = dot(R, R) - 1;
	ringLight *= 1 - step(rb, 0) * smoothstep(-0.02, 0.02, rb * rb - rc);

	// Front to back: a ring in front of the globe covers it by its opacity, a
	// ring behind it is hidden where the globe covers it.
	float ringFront = step(tRing, tPlanet);
	float3 body = lerp(planet * cover * (1 - ringA) + ringLight * ringA,
		planet * cover + ringLight * ringA * (1 - cover), 1 - ringFront);

	// How much of Saturn the haze lets through: the weather rung, the roll, the
	// thinning view near the horizon and the banks drifting in front.
	float through = lerp(saturnLook.y, saturnLook.z, haze) * (1 - saturnLook.w * roll) * sqrt(clarity);
	through *= smoothstep(0.0, 0.2, elevation) * (1 - ringLook.z * saturate(thick * 1.4 - 0.2));
	float phase = (1 - dot(S, D)) * 0.5;
	float near = pow(saturate(dot(V, D) * 0.5 + 0.5), saturnGlow.y);
	// A lit Saturn brightens the haze round it, mostly at night when nothing else does.
	float3 halo = hazeTint.rgb * near * phase * lerp(saturnGlow.z, saturnGlow.x, night) * saturnLook.x;
	sky += (body * saturnLook.x * through + halo * (0.4 + 0.6 * through)) * hazeTint.rgb * saturnDir.w;

	oColor = float4(sky_encode(sky), 1);
	float fogValue = (1 - smoothstep(horizonBlend.x, horizonBlend.y, elevation)) * horizonBlend.z * step(1e-8, fogParams.w);
	oColor.rgb = lerp(oColor.rgb, edgeColour, fogValue);
}
