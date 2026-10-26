// Campaign Reimagined: Venus sky dome (CRSKYVE.MAP, Materials/crart_venus.material).
// One source for DX11 (SM4=1) and DX9 (SM3); there is no GLSL twin, so OpenGL
// falls through to the material's CR_SkyDome technique (the flat stock look).
//
// Venus has no sky, only the underside of a sulphuric-acid cloud deck. Every
// colour comes from the composed fog, so the horizon always meets the terrain
// fog and the deck follows the weather:
//   - a gradient from the fog at the horizon to a brighter, yellower deck overhead;
//   - the sun as a smeared glow with no disc, dimmed where the cloud is thick,
//     with soft rays round it;
//   - cloud bands and convective cells from crsky_venus_clouds.png
//     (Tools/Build-VenusSkyClouds.py), drifting fast (the deck super-rotates);
//   - storms darken and green the deck overhead and roughen it with fast scud;
//   - lightning lights the deck from inside, round the strike;
//   - a fog bank flattens the sky into bright murk round a wide sun glow.
// CRWorldArt.UpdateSky feeds the frame state through the pass colours:
// specular = (Enhanced profile flag, direction toward the sun),
// emissive = (night blend, clarity, storm gloom, fog bank),
// diffuse  = (direction toward the lightning, flash strength).
// CRVenusWeather publishes the storm, bank and flash (Environment forwards them).

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

// Unit 0 is venus.tga, used only by the fallback technique.
DECLARE_MAP(cloudMap, 1)

static const float PI = 3.14159265;

void venussky_vertex(
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

// zenithTint:  rgb deck overhead as a multiple of the horizon, w gradient exponent.
// stormTint:   rgb deck overhead at full storm as a multiple of the calm deck,
//              w extra band contrast at full storm.
// sunGlow:     x core gain, y wide gain, z core exponent, w wide exponent.
// sunRays:     x gain, y exponent (how far round the sun they reach), z drift (rad/s).
// cloudScale:  x band UV per deck unit, y cell UV per deck unit, z wind (UV/s),
//              w deck horizon lift (flattens the projection near the horizon).
// cloudLook:   x band contrast, y cell contrast, z how much thick cloud hides
//              the sun core, w scud contrast at full storm.
// flashLook:   x gain round the strike, y falloff exponent, z share lit everywhere,
//              w how much the cloud texture shows in the flash.
// flashColour: rgb linear colour of the lit deck.
// bankLook:    x share of the sky the bank flattens, y flat sky brightness as a
//              multiple of the fog, z wide glow exponent, w wide glow gain.
void venussky_fragment(
	uniform float3 fogColour,
	uniform float4 fogParams,
	uniform float4 horizonBlend,
	uniform float4 sceneAmbient,
	uniform float4 skyProfile,
	uniform float4 venusState,
	uniform float4 venusFlash,
	uniform float4 fogAmbient,
	uniform float skyTime,
	uniform float4 zenithTint,
	uniform float4 stormTint,
	uniform float4 sunGlow,
	uniform float4 sunRays,
	uniform float4 cloudScale,
	uniform float4 cloudLook,
	uniform float4 flashLook,
	uniform float4 flashColour,
	uniform float4 bankLook,
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

	float night = saturate(venusState.r);
	float clarity = saturate(venusState.g);
	float storm = saturate(venusState.b);
	float bank = saturate(venusState.a);

	float3 S = skyProfile.gba;
	S = normalize(dot(S, S) > 1e-6 ? S : float3(0, 1, 0));
	float c = dot(V, S);
	float up = saturate(elevation);

	// Gradient: the fog at the horizon, the brighter, yellower deck overhead;
	// a storm darkens and greens the deck from above.
	float3 zenith = H * zenithTint.rgb * lerp(float3(1, 1, 1), stormTint.rgb, storm);
	float3 sky = lerp(H, zenith, pow(up, zenithTint.w));

	// The deck: a flat layer seen from below, fading into the horizon haze. The
	// bands run with the wind; the cells drift slower, a little across it, and
	// the storm scud races under both.
	float2 deck = V.xz / (max(elevation, 0) + cloudScale.w);
	float2 wind = float2(1, 0.12) * skyTime * cloudScale.z;
	float bands = SAMPLE(cloudMap, deck * cloudScale.x + wind).r;
	float cells = SAMPLE(cloudMap, deck * cloudScale.y + float2(wind.x * 0.6, -wind.y * 2) + 0.31).g;
	float breakup = SAMPLE(cloudMap, deck * cloudScale.y * 2.7 + wind * 1.4).b;
	float scud = SAMPLE(cloudMap, deck * cloudScale.y * 1.6 + wind * 3.2 + 0.57).g;
	float deckFade = smoothstep(0.0, 0.25, elevation);
	// Density about its mean (zero = average deck), heavier and rougher in a storm.
	float bandShade = (bands - 0.46) * cloudLook.x * (1 + stormTint.w * storm);
	float cellShade = (cells - 0.57) * (0.7 + 0.6 * breakup) * cloudLook.y;
	float scudShade = (scud - 0.57) * cloudLook.w * storm;
	float density = saturate(0.5 + bandShade + cellShade + scudShade);
	// Thick cloud is darker below and a touch browner; thin cloud lets light through.
	float shade = (bandShade + cellShade + scudShade) * deckFade;
	sky *= 1 - shade * float3(1, 1.05, 1.3);

	// The sun: no disc, only a glow smeared by the cloud in front of it, over a
	// wide brightening of the whole sun side. Rays fan out through the thin spots.
	float sunLift = (1 - 0.85 * storm) * (0.45 + 0.55 * clarity) * (1 - night);
	float coreExponent = lerp(sunGlow.z, sunGlow.z * 0.2, bank);
	float core = pow(saturate(c), coreExponent) * (1 - cloudLook.z * density * (1 - bank));
	float wide = pow(saturate(c * 0.5 + 0.5), sunGlow.w);
	float3 T = normalize(cross(S, abs(S.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
	float3 B = cross(S, T);
	float a = atan2(dot(V, B), dot(V, T)) + skyTime * sunRays.z;
	float fan = 0.5 + 0.25 * sin(a * 7) + 0.15 * sin(a * 13 + 1.7) + 0.1 * sin(a * 23 + 4.1);
	float rays = pow(saturate(c), sunRays.y) * (1 - pow(saturate(c), sunRays.y * 8)) * fan * (1 - density);
	float3 sunColour = float3(1.0, 0.92, 0.66);
	float level = max(dot(H, float3(0.2126, 0.7152, 0.0722)), 0.01);
	sky += sunColour * level * (core * sunGlow.x + rays * sunRays.x) * sunLift;
	sky *= 1 + wide * sunGlow.y * sunLift;

	// A fog bank: the deck vanishes into bright murk, the sun a wide blur in it.
	float3 murk = H * bankLook.y * (1 + pow(saturate(c * 0.5 + 0.5), bankLook.z) * bankLook.w);
	sky = lerp(sky, murk, bank * bankLook.x);

	sky *= lerp(1, 0.25, night);

	oColor = float4(sky_encode(sky), 1);
	float fogValue = (1 - smoothstep(horizonBlend.x, horizonBlend.y, elevation)) * horizonBlend.z * step(1e-8, fogParams.w);
	oColor.rgb = lerp(oColor.rgb, edgeColour, fogValue);

	// Lightning lights the deck from inside round the strike, the cells first,
	// and the haze below it at half strength.
	float flash = saturate(venusFlash.a);
	if (flash > 0.001) {
		float3 F = venusFlash.rgb;
		F = normalize(dot(F, F) > 1e-6 ? F : float3(0, 1, 0));
		float near = pow(saturate(dot(V, F) * 0.5 + 0.5), flashLook.y);
		float lit = flash * (near * flashLook.x + flashLook.z) * lerp(1, 0.4 + 1.2 * density, flashLook.w * (1 - fogValue));
		oColor.rgb = sky_encode(sky_decode(oColor.rgb) + flashColour.rgb * lit * lerp(1, 0.5, fogValue) * smoothstep(-0.1, 0.05, elevation));
	}
}
