// Campaign Reimagined: Achilles sky dome (CRSKYAC.MAP, Materials/crart_achilles.material).
// One source for DX11 (SM4=1) and DX9 (SM3); there is no GLSL twin, so OpenGL
// falls through to the material's CR_SkyDome technique (the flat stock look).
//
// Achilles is a small, cold, wooded moon of Uranus with a breathable blue sky
// and rain off the forest. Every colour comes from the composed fog, so the
// horizon always meets the terrain fog and the sky follows the weather:
//   - a gradient from the fog at the horizon to a deeper blue overhead;
//   - the sun as a small bright disc with a glow, hidden where cloud covers it;
//   - cumulus from crsky_achilles_clouds.png (Tools/Build-AchillesSky.py): the
//     storm grows them from scattered fair-weather cloud to a closed, dark
//     deck; lit tops, grey bases and silver edges round the sun;
//   - rain flattens the sky into murk and hangs curtains on the horizon;
//   - lightning lights the deck from inside, round the strike;
//   - in the tempest the overloaded core lights the cloud base red from below;
//   - Uranus, huge and close, where the TRN puts it: a pale cyan, faintly
//     banded globe with a bright polar cap, lit by the sun with real phases,
//     and its narrow rings, the epsilon ring brightest, the dusty nu and mu
//     rings faint red and blue (crsky_uranus.png, crsky_uranus_rings.png),
//     with the globe's shadow on the rings. It shows where the cloud breaks
//     and vanishes in rain, so a clearing reveals it.
// Uranus lies on its side, so the rings stand almost upright in the sky, and
// its moons orbit in the ring plane, so from Achilles the real rings are edge-on.
// uranusShape.z opens them so they read; 0 gives the true view.
// CRWorldArt.UpdateSky feeds the frame state through the pass colours:
// specular = (Enhanced profile flag, direction toward the sun),
// emissive = (night blend, clarity, storm (cloud cover), rain),
// diffuse  = (direction toward the lightning, flash strength),
// ambient  = (direction toward Uranus, 1 when the map has a Uranus).
// CRJungle17.SkyState publishes the storm, rain and flash (Environment forwards them).

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

// Unit 0 is achilles.tga, used only by the fallback technique.
DECLARE_MAP(cloudMap, 1)
DECLARE_MAP(uranusMap, 2)
DECLARE_MAP(ringMap, 3)

// The ring map runs from 1.45 to 4.10 Uranus equatorial radii.
static const float RING_INNER = 1.45;
static const float RING_SPAN = 2.65;

void achillessky_vertex(
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
// sunDisc:     x angular radius (radians), y disc brightness as a multiple of the
//              horizon, z share of the disc thin cloud lets through.
// cloudScale:  x cumulus UV per deck unit, y detail UV per deck unit, z wind
//              (UV/s), w deck horizon lift (flattens the projection near the horizon).
// cloudCover:  x cover in fair weather, y cover at full storm, z edge softness,
//              w detail share in the edges.
// cloudLook:   x lit-top brightness as a multiple of the horizon, y base
//              brightness, z silver edge gain, w base darkening at full storm.
// rainLook:    x share of the sky rain flattens, y murk brightness as a multiple
//              of the fog, z curtain strength on the horizon, w curtain height.
// flashLook:   x gain round the strike, y falloff exponent, z share lit everywhere,
//              w how much the cloud shows in the flash.
// flashColour: rgb linear colour of the lit deck.
// coreGlow:    rgb linear red light from below in the tempest, w the storm it
//              starts at.
// uranusShape: x distance in Uranus equatorial radii (the TRN's Size 450 at
//              Radius 1000, 25 degrees across, is 4.55), y polar / equatorial
//              radius, z ring opening (radians), w roll of the pole from
//              straight up (radians).
// uranusLook:  x brightness (linear), y share seen through clear air, z share
//              a full rain hides, w how much cloud in front hides it.
// ringLook:    x brightness, y forward-scatter gain toward the sun, z its
//              exponent, w the halo round a lit Uranus.
void achillessky_fragment(
	uniform float3 fogColour,
	uniform float4 fogParams,
	uniform float4 horizonBlend,
	uniform float4 sceneAmbient,
	uniform float4 skyProfile,
	uniform float4 achillesState,
	uniform float4 achillesFlash,
	uniform float4 uranusDir,
	uniform float4 fogAmbient,
	uniform float skyTime,
	uniform float4 zenithTint,
	uniform float4 sunGlow,
	uniform float4 sunDisc,
	uniform float4 cloudScale,
	uniform float4 cloudCover,
	uniform float4 cloudLook,
	uniform float4 rainLook,
	uniform float4 flashLook,
	uniform float4 flashColour,
	uniform float4 coreGlow,
	uniform float4 uranusShape,
	uniform float4 uranusLook,
	uniform float4 ringLook,
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

	float night = saturate(achillesState.r);
	float clarity = saturate(achillesState.g);
	float storm = saturate(achillesState.b);
	float rain = saturate(achillesState.a);

	float3 S = skyProfile.gba;
	S = normalize(dot(S, S) > 1e-6 ? S : float3(0, 1, 0));
	float c = dot(V, S);
	float up = saturate(elevation);
	float day = 1 - night;
	float level = max(dot(H, float3(0.2126, 0.7152, 0.0722)), 0.01);

	// Clear air: the fog at the horizon, a deeper blue overhead.
	float3 sky = lerp(H, H * zenithTint.rgb, pow(up, zenithTint.w));

	// The sun: a small disc and a glow round it, over a wide brightening of the
	// sun side. Cloud covers the disc below.
	float sunLift = (0.5 + 0.5 * clarity) * day;
	float core = pow(saturate(c), sunGlow.z);
	float wide = pow(saturate(c * 0.5 + 0.5), sunGlow.w);
	float3 sunColour = float3(1.0, 0.95, 0.86);
	float discCos = cos(sunDisc.x);
	float discEdge = max(fwidth(c), 1e-6);
	float disc = smoothstep(discCos - discEdge, discCos + discEdge, c);
	sky += sunColour * level * core * sunGlow.x * sunLift;
	sky *= 1 + wide * sunGlow.y * sunLift;

	// Uranus. Camera at the origin, Uranus's centre at D * distance, lengths in
	// its equatorial radius. N is the ring plane's normal (and the pole): the
	// pole leans toward the viewer by the ring opening. W points from Uranus
	// toward the viewer in its equator plane, X across the sky.
	float3 D = uranusDir.xyz;
	D = normalize(dot(D, D) > 1e-6 ? D : float3(0, 0, 1));
	float3 P0 = normalize(float3(0, 1, 0) - D * D.y + float3(1e-4, 0, 0));
	float3 P = P0 * cos(uranusShape.w) + cross(D, P0) * sin(uranusShape.w);
	float3 N = normalize(P * cos(uranusShape.z) - D * sin(uranusShape.z));
	float3 W = normalize(-D - N * dot(-D, N));
	float3 X = cross(N, W);
	float3 C = D * uranusShape.x;
	float f = uranusShape.y;

	// The globe, an oblate spheroid: a unit sphere once the pole axis is
	// stretched by 1 / f. Outside the disc the nearest point stands in, so the
	// texture coordinates stay smooth for the mip choice.
	float3 v1 = float3(dot(V, X), dot(V, W), dot(V, N) / f);
	float3 c1 = float3(dot(C, X), dot(C, W), dot(C, N) / f);
	float qa = dot(v1, v1);
	float qb = dot(v1, c1);
	float discQ = qb * qb - qa * (dot(c1, c1) - 1);
	float tPlanet = (qb - sqrt(max(discQ, 0))) / qa;
	float cover = saturate(discQ / max(fwidth(discQ) * 1.5, 1e-7));
	float3 q = v1 * tPlanet - c1;
	float3 normal = normalize(X * q.x + W * q.y + N * (q.z / f));
	// Achilles keeps one face to Uranus, so only that face is mapped: the map is
	// the globe seen square on (x across, z up the pole), and its bands are
	// zonal, so Uranus's own spin would not show.
	float3 globe = SAMPLE(uranusMap, float2(0.5 + 0.5 * q.x, 0.5 - 0.5 * q.z)).rgb;
	globe *= globe;
	// Minnaert limb darkening; Uranus's limb darkens strongly in methane light.
	float mu0 = saturate(dot(normal, S));
	float mu = saturate(dot(normal, -V));
	float lit = pow(mu0, 0.95) * pow(max(mu, 1e-3), -0.05) * saturate(mu0 * 8);
	float3 planet = globe * lit;

	// The rings: where the view ray crosses the ring plane. Narrow and dark, so
	// they read mostly by the sunlight their dust throws forward.
	float vn = dot(V, N);
	float tRing = dot(C, N) / (abs(vn) > 1e-5 ? vn : 1e-5);
	float3 R = V * tRing - C;
	float r = length(R);
	float u = (r - RING_INNER) / RING_SPAN;
	float4 ring = SAMPLE(ringMap, float2(saturate(u), 0.5));
	float ringA = ring.a * step(0, tRing) * step(0, u) * step(u, 1);
	float sn = dot(S, N);
	float forward = 1 + ringLook.y * pow(saturate(c * 0.5 + 0.5), ringLook.z);
	float3 ringLight = ring.rgb * ring.rgb * ringLook.x * saturate(abs(sn) * 3 + 0.2) * forward;
	// The globe's shadow on the rings.
	float rb = dot(R, S);
	float rc = dot(R, R) - 1;
	ringLight *= 1 - step(rb, 0) * smoothstep(-0.02, 0.02, rb * rb - rc);
	// Front to back: a ring in front of the globe dims it by its opacity, a ring
	// behind it is hidden where the globe covers it.
	float ringFront = step(tRing, tPlanet);
	float3 body = lerp(planet * cover * (1 - ringA) + ringLight * ringA,
		planet * cover + ringLight * ringA * (1 - cover), 1 - ringFront);
	float phase = (1 - dot(S, D)) * 0.5;
	float halo = pow(saturate(dot(V, D) * 0.5 + 0.5), 60) * phase * ringLook.w;

	// The cumulus: a flat layer seen from below, fading into the horizon haze.
	// The storm raises the cover until the gaps close; the detail frays the edges.
	float2 deck = V.xz / (max(elevation, 0) + cloudScale.w);
	float2 wind = float2(0.5, -0.86) * skyTime * cloudScale.z;
	float4 cl = SAMPLE(cloudMap, deck * cloudScale.x + wind);
	float detail = SAMPLE(cloudMap, deck * cloudScale.y + wind * 1.6 + 0.43).g;
	float deckFade = smoothstep(0.0, 0.2, elevation);
	float amount = lerp(cloudCover.x, cloudCover.y, storm);
	float field = cl.r + (detail - 0.5) * cloudCover.w;
	float density = smoothstep(1 - amount - cloudCover.z, 1 - amount + cloudCover.z, field) * deckFade;
	density = max(density, smoothstep(0.75, 1.0, storm) * deckFade);
	float thick = saturate((field - (1 - amount)) * 2.5 + storm * 0.6);
	// Thin cloud is lit through, thick cloud is a grey base; the edges toward the
	// sun glow silver. The storm darkens the base.
	float3 cloudTop = lerp(float3(1, 1, 1) * level, H, 0.35) * cloudLook.x;
	float3 cloudBase = H * cloudLook.y * lerp(1, cloudLook.w, storm);
	float3 cloud = lerp(cloudTop, cloudBase, thick);
	float edge = saturate(density * (1 - density) * 4) * (1 - storm);
	cloud += sunColour * level * cloudLook.z * edge * pow(saturate(c * 0.5 + 0.5), 12) * sunLift;
	cloud *= lerp(1, 0.3, night);
	// At night Uranus is the light: the cloud round it takes a cold silver edge.
	float3 uranusLight = float3(0.55, 0.85, 1.0) * phase * uranusDir.w;
	cloud += uranusLight * night * (0.04 + 0.3 * edge) * pow(saturate(dot(V, D) * 0.5 + 0.5), 6);

	// Uranus and the sun disc behind the air and between the clouds. Night
	// darkens the air, not the sunlit planet.
	sky *= lerp(1, 0.25, night);
	float through = lerp(uranusLook.y, uranusLook.z, rain) * sqrt(clarity) * smoothstep(0.0, 0.15, elevation);
	sky += (body * uranusLook.x * through + halo * float3(0.55, 0.85, 1.0) * (level + 0.1 * night) * (0.3 + 0.7 * through)) * uranusDir.w;
	sky += sunColour * level * disc * sunDisc.y * sunLift * (1 - rain);
	float hidden = density * uranusLook.w;
	sky = lerp(sky, cloud, hidden);
	// The disc through thin cloud.
	sky += sunColour * level * disc * sunDisc.y * sunDisc.z * sunLift * density * (1 - thick);

	// Rain: the sky flattens into murk; curtains hang under the cloud base.
	float3 murk = H * rainLook.y * (1 + pow(saturate(c * 0.5 + 0.5), 6) * 0.4 * day);
	sky = lerp(sky, murk, rain * rainLook.x);
	float az = atan2(V.x, V.z);
	float curtain = SAMPLE(cloudMap, float2(az * 1.6 + wind.x * 2, elevation * 3 - skyTime * 0.05)).b;
	float low = 1 - smoothstep(0.0, rainLook.w, elevation);
	sky = lerp(sky, H * 0.85, rain * rainLook.z * curtain * low * step(0, elevation));

	// The tempest: the overloaded core lights the cloud base red from below,
	// strongest low in the sky, breathing slowly.
	float tempest = smoothstep(coreGlow.w, 1.0, storm);
	float breathe = 0.75 + 0.25 * sin(skyTime * 0.9) * sin(skyTime * 0.37 + 1.3);
	sky += coreGlow.rgb * tempest * breathe * density * (0.35 + 0.65 * (1 - up)) * (0.6 + 0.4 * thick);

	float fogValue = (1 - smoothstep(horizonBlend.x, horizonBlend.y, elevation)) * horizonBlend.z * step(1e-8, fogParams.w);
	sky = lerp(sky, H, fogValue);

	// Lightning lights the deck from inside round the strike, the thick cloud
	// first, and the haze below it at half strength.
	float flash = saturate(achillesFlash.a);
	float3 F = achillesFlash.rgb;
	F = normalize(dot(F, F) > 1e-6 ? F : float3(0, 1, 0));
	float near = pow(saturate(dot(V, F) * 0.5 + 0.5), flashLook.y);
	float bolt = flash * (near * flashLook.x + flashLook.z) * lerp(1, 0.4 + 1.2 * density, flashLook.w * (1 - fogValue));
	sky += flashColour.rgb * bolt * lerp(1, 0.5, fogValue) * smoothstep(-0.1, 0.05, elevation);

	oColor = float4(sky_encode(sky), 1);
}
