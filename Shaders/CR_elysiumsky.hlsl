// Campaign Reimagined: Elysium sky dome (CRSKYEL.MAP, Materials/crart_elysium.material).
// One source for DX11 (SM4=1) and DX9 (SM3); there is no GLSL twin, so OpenGL
// falls through to the material's CR_SkyDome technique (the stock elysium.tga).
//
// CR treats Elysium as a dead, apocalyptic Earth-like world under a thin
// remnant atmosphere (-194 C, ruins of the Chthonian city). Every colour comes
// from the composed fog, so the horizon always meets the terrain fog:
//   - a gradient from the cool grey-violet fog at the horizon to a bruised,
//     desaturated violet-grey overhead (never a saturated purple);
//   - thin, torn high cloud from crsky_elysium_clouds.png
//     (Tools/Build-ElysiumSky.py): ragged strands that thicken as the weather
//     does, with dust and ash veils over them;
//   - a small, pale sun disc with a little glow, hidden by cloud, storm and bank;
//   - a few faint stars at the zenith by day, the whole night sky after dark;
//   - storms darken the sky and close the cloud; dry lightning lights the
//     cloud from inside, round the strike; a fog bank (dust front) flattens
//     the sky into murk.
// CRWorldArt.UpdateSky feeds the frame state through the pass colours:
// specular = (Enhanced profile flag, direction toward the sun),
// emissive = (night blend, clarity, storm gloom, fog bank),
// diffuse  = (direction toward the lightning, flash strength).
// CRElysiumWeather (CRVenusWeather's engine) publishes the storm, bank and
// flash; Environment forwards them.

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

// Unit 0 is elysium.tga, used only by the fallback technique.
DECLARE_MAP(cloudMap, 1)

void elysiumsky_vertex(
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

float hash13(float3 p)
{
	p = frac(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return frac((p.x + p.y) * p.z);
}

// zenithTint:  rgb the bruised sky overhead (linear, as a multiple of the
//              horizon's luminance), w gradient exponent.
// stormTint:   rgb sky overhead at full storm as a multiple of the calm sky,
//              w extra cloud contrast at full storm.
// sunDisc:     x disc radius (radians), y edge softness (radians), z disc gain.
// sunGlow:     x core gain, y wide gain, z core exponent, w wide exponent.
// cloudScale:  x strand UV per deck unit, y veil UV per deck unit, z wind (UV/s),
//              w deck horizon lift (flattens the projection near the horizon).
// cloudLook:   x clear-day cover (share of the sky), y cover at full storm,
//              z edge softness, w how much thick cloud hides the sun.
// cloudColour: rgb thin cloud as a multiple of the horizon, w cloud opacity.
// dustLook:    x dust veil strength in fair weather, y at full storm.
// dustColour:  rgb dust and ash as a multiple of the horizon.
// starLook:    x cells per radian, y share of cells that hold a star, z night
//              gain, w gain at the zenith by day.
// flashLook:   x gain round the strike, y falloff exponent, z share lit everywhere,
//              w how much the cloud shows in the flash.
// flashColour: rgb linear colour of the lit cloud.
// bankLook:    x share of the sky the bank flattens, y flat sky brightness as a
//              multiple of the fog, z wide glow exponent, w wide glow gain.
void elysiumsky_fragment(
	uniform float3 fogColour,
	uniform float4 fogParams,
	uniform float4 horizonBlend,
	uniform float4 sceneAmbient,
	uniform float4 skyProfile,
	uniform float4 elysiumState,
	uniform float4 elysiumFlash,
	uniform float4 fogAmbient,
	uniform float skyTime,
	uniform float4 zenithTint,
	uniform float4 stormTint,
	uniform float4 sunDisc,
	uniform float4 sunGlow,
	uniform float4 cloudScale,
	uniform float4 cloudLook,
	uniform float4 cloudColour,
	uniform float4 dustLook,
	uniform float4 dustColour,
	uniform float4 starLook,
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
	float level = max(dot(H, float3(0.2126, 0.7152, 0.0722)), 0.01);

	float night = saturate(elysiumState.r);
	float clarity = saturate(elysiumState.g);
	float storm = saturate(elysiumState.b);
	float bank = saturate(elysiumState.a);

	float3 S = skyProfile.gba;
	S = normalize(dot(S, S) > 1e-6 ? S : float3(0, 1, 0));
	float c = dot(V, S);
	float up = saturate(elevation);

	// Gradient: the fog at the horizon, a bruised violet-grey overhead (a fixed
	// hue scaled to the fog's brightness, so it stays desaturated and cold);
	// a storm darkens it from above.
	float3 zenith = level * zenithTint.rgb * lerp(float3(1, 1, 1), stormTint.rgb, storm);
	float3 sky = lerp(H, zenith, pow(up, zenithTint.w));

	// Thin high cloud: torn strands in a flat layer seen from below, mostly
	// open sky. The strands race with the wind; the dust veils drift slower,
	// a little across it. Storms close the cover.
	float2 deck = V.xz / (max(elevation, 0) + cloudScale.w);
	float2 wind = float2(1, 0.10) * skyTime * cloudScale.z;
	float strands = SAMPLE(cloudMap, deck * cloudScale.x + wind).r;
	float veil = SAMPLE(cloudMap, deck * cloudScale.y + float2(wind.x * 0.5, -wind.y * 2) + 0.27).g;
	float breakup = SAMPLE(cloudMap, deck * cloudScale.x * 3.1 + wind * 1.3 + 0.61).b;
	// A finer tap of the same breakup frays the edges below one map texel, so the
	// threshold never shows the map's texel grid where the dome magnifies it.
	breakup = lerp(breakup, SAMPLE(cloudMap, deck * cloudScale.x * 11.3 + wind * 1.7 + 0.13).b, 0.45);
	float deckFade = smoothstep(0.0, 0.25, elevation);
	float cover = lerp(cloudLook.x, cloudLook.y, storm);
	float edge = max(cloudLook.z * (1 + 0.8 * storm), 0.01);
	float density = smoothstep(1 - cover - edge, 1 - cover + edge, strands + (breakup - 0.5) * 0.25) * deckFade;
	// Thin cloud is a little paler than the sky it hides; a storm turns it to dark rags.
	float3 cloud = H * cloudColour.rgb * lerp(float3(1, 1, 1), stormTint.rgb * 0.8, storm);
	sky = lerp(sky, cloud, density * cloudColour.w);
	sky *= 1 - density * storm * stormTint.w * 0.25;

	// Dust and ash veils: a grey-warm cast over everything but the zenith, thicker in a front.
	float dust = veil * lerp(dustLook.x, dustLook.y, storm) * deckFade;
	sky = lerp(sky, H * dustColour.rgb, saturate(dust));

	// The sun: a small pale disc with a little glow, dimmed by cloud, storm and bank.
	float sunVis = (1 - 0.9 * storm) * (0.45 + 0.55 * clarity) * (1 - night) * (1 - cloudLook.w * density * (1 - bank));
	float angle = acos(saturate(c));
	float disc = 1 - smoothstep(sunDisc.x, sunDisc.x + sunDisc.y, angle);
	float core = pow(saturate(c), lerp(sunGlow.z, sunGlow.z * 0.2, bank));
	float wide = pow(saturate(c * 0.5 + 0.5), sunGlow.w);
	float3 sunColour = float3(1.0, 0.94, 0.88);
	sky += sunColour * level * (disc * sunDisc.z + core * sunGlow.x) * sunVis;
	sky *= 1 + wide * sunGlow.y * sunVis;

	// A dust front: the sky vanishes into murk, the sun a wide blur in it.
	float3 murk = H * dustColour.rgb * bankLook.y * (1 + pow(saturate(c * 0.5 + 0.5), bankLook.z) * bankLook.w);
	sky = lerp(sky, murk, bank * bankLook.x);

	sky *= lerp(1, 0.25, night);

	// Stars: a few at the zenith by day, the whole sky after dark, behind cloud.
	float3 cell = floor(V * starLook.x);
	float chance = hash13(cell);
	float3 centre = cell + 0.5 + (float3(hash13(cell + 7.1), hash13(cell + 13.7), hash13(cell + 29.3)) - 0.5) * 0.5;
	float spot = saturate(1 - length(V * starLook.x - centre) / 0.3);
	float star = step(1 - starLook.y, chance) * spot * spot * (0.4 + 0.6 * hash13(cell + 3.3));
	float starSky = lerp(starLook.w * smoothstep(0.55, 0.95, elevation), starLook.z * smoothstep(0.06, 0.5, elevation), night);
	starSky *= (1 - density) * (1 - bank) * (1 - 0.8 * storm) * clarity;
	sky += float3(0.82, 0.86, 1.0) * star * starSky;

	oColor = float4(sky_encode(sky), 1);
	float fogValue = (1 - smoothstep(horizonBlend.x, horizonBlend.y, elevation)) * horizonBlend.z * step(1e-8, fogParams.w);
	oColor.rgb = lerp(oColor.rgb, edgeColour, fogValue);

	// Dry lightning lights the cloud from inside round the strike, and the
	// haze below it at half strength.
	float flash = saturate(elysiumFlash.a);
	if (flash > 0.001) {
		float3 F = elysiumFlash.rgb;
		F = normalize(dot(F, F) > 1e-6 ? F : float3(0, 1, 0));
		float near = pow(saturate(dot(V, F) * 0.5 + 0.5), flashLook.y);
		float lit = flash * (near * flashLook.x + flashLook.z) * lerp(1, 0.4 + 1.2 * density, flashLook.w * (1 - fogValue));
		oColor.rgb = sky_encode(sky_decode(oColor.rgb) + flashColour.rgb * lit * lerp(1, 0.5, fogValue) * smoothstep(-0.1, 0.05, elevation));
	}
}
