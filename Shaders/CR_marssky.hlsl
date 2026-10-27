// Campaign Reimagined: Mars sky dome (CRSKYMA.MAP, Materials/crart_mars.material).
// One source for DX11 (SM4=1) and DX9 (SM3); there is no GLSL twin, so OpenGL
// falls through to the material's CR_SkyDome technique (the flat stock look).
//
// Everything is coloured from the composed fog colour, so the horizon always
// meets the terrain fog and the sky follows the Environment day cycle and the
// weather without a palette of its own:
//   - a butterscotch gradient, darker toward the zenith;
//   - the Martian aureole: a tight glow round the sun that turns blue as the
//     sun sinks, over a broad brightening on the sun side;
//   - a small sun disc;
//   - water-ice cirrus and dust veils from crsky_mars_clouds.png
//     (Tools/Build-MarsSkyClouds.py) on a flat cloud deck, lit by the sun by
//     day and dark against the sky at night;
//   - at night, the catalog stars and Milky Way of CR_catalogsky.
// CRWorldArt.UpdateSky feeds the frame state through the pass colours:
// specular = (Enhanced profile flag, direction toward the sun),
// emissive = (night blend, clarity, cloud cover, unused).

#if defined(SM4)
#define DECLARE_MAP(name, reg) Texture2D name : register(t##reg); SamplerState name##Sam : register(s##reg);
#define SAMPLE(name, uv) name.Sample(name##Sam, uv)
#define SAMPLE_GRAD(name, uv, gx, gy) name.SampleGrad(name##Sam, uv, gx, gy)
#define POSITION_OUT SV_POSITION
#define COLOUR_OUT SV_TARGET
#else
#define DECLARE_MAP(name, reg) sampler2D name : register(s##reg);
#define SAMPLE(name, uv) tex2D(name, uv)
#define SAMPLE_GRAD(name, uv, gx, gy) tex2Dgrad(name, uv, gx, gy)
#define POSITION_OUT POSITION
#define COLOUR_OUT COLOR
#endif

// Unit 0 is mars.tga, used only by the fallback technique.
DECLARE_MAP(cloudMap, 1)
DECLARE_MAP(starIndex, 2)
DECLARE_MAP(milkyWay, 3)

static const float CELLS = 512.0;
static const float OFFSET_RANGE = 2.0;
static const float MAG_LIMIT = 8.0;
static const float MAG_STEP = 24.0;
static const float BV_MIN = -0.5;
static const float BV_SPAN = 2.5;
static const float PI = 3.14159265;

void marssky_vertex(
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

// As CR_catalogsky: linear star colour from B-V.
float3 star_colour(float bv)
{
	const float3 c0 = float3(0.62, 0.72, 1.00);
	const float3 c1 = float3(0.92, 0.95, 1.00);
	const float3 c2 = float3(1.00, 0.96, 0.88);
	const float3 c3 = float3(1.00, 0.80, 0.58);
	const float3 c4 = float3(1.00, 0.58, 0.32);
	float3 c = lerp(c0, c1, saturate((bv + 0.3) / 0.3));
	c = lerp(c, c2, saturate(bv / 0.6));
	c = lerp(c, c3, saturate((bv - 0.6) / 0.4));
	return lerp(c, c4, saturate((bv - 1.0) / 0.6));
}

// The CR_catalogsky star field and Milky Way for one (rotated) direction.
// Must match Tools/Build-CatalogSky.py; see CR_catalogsky-sm4.hlsl.
float3 catalog_stars(float3 d, float4 starParams, float4 starShape, float4 milkyParams)
{
	float pixelAngle = max(max(length(ddx(d)), length(ddy(d))), 1e-6);
	float3 ad = abs(d);
	float3 n, u, v;
	float face;
	if (ad.x >= ad.y && ad.x >= ad.z) { n = float3(sign(d.x), 0, 0); u = float3(0, 1, 0); v = float3(0, 0, 1); face = d.x < 0 ? 1 : 0; }
	else if (ad.y >= ad.z)            { n = float3(0, sign(d.y), 0); u = float3(0, 0, 1); v = float3(1, 0, 0); face = d.y < 0 ? 3 : 2; }
	else                              { n = float3(0, 0, sign(d.z)); u = float3(1, 0, 0); v = float3(0, 1, 0); face = d.z < 0 ? 5 : 4; }
	float2 uv = float2(dot(d, u), dot(d, v)) / dot(d, n);
	float2 cell = clamp(floor((uv * 0.5 + 0.5) * CELLS), 0, CELLS - 1);
#if defined(SM4)
	float4 texel = starIndex.Load(int3(cell.x, face * CELLS + cell.y, 0));
#else
	float4 texel = tex2Dlod(starIndex, float4((cell.x + 0.5) / CELLS, (face * CELLS + cell.y + 0.5) / (6 * CELLS), 0, 0));
#endif
	float3 stars = 0;
	if (texel.b > 0)
	{
		float2 starUv = (cell + 0.5 + (texel.rg * 2 - 1) * OFFSET_RANGE) / CELLS * 2 - 1;
		float3 starDir = normalize(n + starUv.x * u + starUv.y * v);
		float r = length(d - starDir) / pixelAngle;
		float mag = MAG_LIMIT - (texel.b * 255 - 1) / MAG_STEP;
		float flux = pow(10.0, -0.4 * starShape.x * (mag - starParams.w));
		float sigma = starParams.y;
		float core = exp(-0.5 * r * r / (sigma * sigma)) / (2 * PI * sigma * sigma);
		float halo = starParams.z * exp(-r / starShape.y);
		stars = star_colour(texel.a * BV_SPAN + BV_MIN) * flux * starParams.x * (core + halo);
	}
	float ra = atan2(d.y, d.x) / (2 * PI);
	float dec = asin(clamp(d.z, -1, 1)) / PI;
	float2 mwUv = float2(frac(milkyParams.z + milkyParams.y * ra), 0.5 - dec);
	float2 gx = ddx(mwUv), gy = ddy(mwUv);
	gx.x -= round(gx.x); gy.x -= round(gy.x);
	return stars + sky_decode(SAMPLE_GRAD(milkyWay, mwUv, gx, gy).rgb) * milkyParams.x;
}

// zenithTint:  rgb day zenith as a multiple of the horizon, w gradient exponent.
// nightTint:   rgb night zenith as a multiple of the horizon, w how far the
//              visible sun sinks at full night (the Environment night sun is moonlight).
// aureole:     x tight glow gain, y wide glow gain, z tight exponent, w wide exponent.
// aureoleBlue: rgb low-sun aureole colour, w its share of the tight glow at a high sun.
// sunDisc:     x angular radius (radians), y linear gain.
// twilight:    x share of the sky the low-sun aureole replaces (Mars sunsets are
//              blue round the sun, not orange), y anti-sun dimming at a low sun,
//              z how far the low-sun aureole shows through the horizon fog band.
// cloudScale:  x cirrus UV per deck unit, y dust UV per deck unit, z wind (UV/s),
//              w deck horizon lift (flattens the projection near the horizon).
// cloudLook:   x cirrus gain, y dust gain, z lit cirrus brightness, w forward-scatter gain.
// starParams/starShape/milkyParams: as CR_catalogsky.
void marssky_fragment(
	uniform float3 fogColour,
	uniform float4 fogParams,
	uniform float4 horizonBlend,
	uniform float4 sceneAmbient,
	uniform float4 skyProfile,
	uniform float4 marsState,
	uniform float4 fogAmbient,
	uniform float skyTime,
	uniform float4 zenithTint,
	uniform float4 nightTint,
	uniform float4 aureole,
	uniform float4 aureoleBlue,
	uniform float4 sunDisc,
	uniform float4 twilight,
	uniform float4 cloudScale,
	uniform float4 cloudLook,
	uniform float4x4 skyRotation,
	uniform float4 starParams,
	uniform float4 starShape,
	uniform float4 milkyParams,
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
	float skyLevel = max(dot(H, float3(0.2126, 0.7152, 0.0722)), 0.01);

	float night = saturate(marsState.r);
	float clarity = saturate(marsState.g);
	float day = 1 - night;

	float3 S = skyProfile.gba;
	S = normalize((dot(S, S) > 1e-6 ? S : float3(0, 1, 0)) - float3(0, nightTint.w * night, 0));
	float sunUp = smoothstep(-0.06, 0.04, S.y) * day;
	float lowSun = 1 - smoothstep(0.08, 0.55, S.y);
	float c = dot(V, S);

	// Gradient: the horizon is the fog; the zenith darker, much darker at night.
	float3 zenith = H * lerp(zenithTint.rgb, nightTint.rgb, night);
	float3 sky = lerp(H, zenith, pow(saturate(elevation), zenithTint.w));

	// Aureole: fine dust forward-scatters blue light into a tight cone round the sun.
	float3 tightColour = lerp(lerp(float3(1, 0.9, 0.78), aureoleBlue.rgb, aureoleBlue.w), aureoleBlue.rgb, lowSun);
	float tight = pow(saturate(c), aureole.z);
	float wide = pow(saturate(c * 0.5 + 0.5), aureole.w);
	float glow = sunUp * clarity;
	sky *= 1 - (saturate(tight * aureole.x) * twilight.x + (1 - wide) * twilight.y) * lowSun * glow;
	float3 wideColour = lerp(H, tightColour * skyLevel, 0.5 * lowSun);
	sky += (tightColour * skyLevel * tight * aureole.x + wideColour * wide * aureole.y * (0.4 + lowSun)) * glow;

	// Sun disc, anti-aliased over its own pixel footprint.
	float angle = sqrt(max(2 - 2 * c, 0));
	float aa = max(fwidth(angle), 1e-5);
	sky += float3(1, 0.96, 0.9) * (1 - smoothstep(sunDisc.x - aa, sunDisc.x + aa, angle)) * sunDisc.y * glow;

	// Stars, behind the clouds.
	float starFade = night * clarity * smoothstep(0.02, 0.3, elevation);
	if (starFade > 0.001)
		sky += catalog_stars(normalize(mul((float3x3)skyRotation, V)), starParams, starShape, milkyParams) * starFade;

	// Cloud deck: a flat layer seen from below, fading into the horizon haze.
	float2 deck = V.xz / (max(elevation, 0) + cloudScale.w);
	float2 wind = float2(1, 0.35) * skyTime * cloudScale.z;
	float ice = SAMPLE(cloudMap, deck * cloudScale.x + wind).r;
	float breakup = SAMPLE(cloudMap, deck * cloudScale.x * 2.3 + wind * 1.3).b;
	float veil = SAMPLE(cloudMap, deck * cloudScale.y + wind * 0.4 + 0.37).g;
	float deckFade = smoothstep(0.0, 0.22, elevation) * saturate(marsState.b);
	float cirrus = saturate(ice * (0.75 + 0.5 * breakup) * cloudLook.x) * deckFade;
	float dust = saturate(veil * cloudLook.y) * deckFade;

	float forward = pow(saturate(c), 6) * cloudLook.w * glow;
	float3 dayCirrus = lerp(H * 1.25, float3(1, 0.93, 0.86) * skyLevel * cloudLook.z, 0.5);
	dayCirrus = lerp(dayCirrus, tightColour * skyLevel * cloudLook.z, 0.6 * lowSun) * (1 + forward);
	float3 cirrusColour = lerp(H * 0.7, dayCirrus, day);
	float3 dustColour = H * lerp(0.75, 1.12, day) * (1 + 0.5 * forward);
	sky = lerp(sky, dustColour, dust);
	sky = lerp(sky, cirrusColour, cirrus);

	oColor = float4(sky_encode(sky), 1);
	float fogValue = (1 - smoothstep(horizonBlend.x, horizonBlend.y, elevation)) * horizonBlend.z * step(1e-8, fogParams.w);
	fogValue *= 1 - saturate(tight * aureole.x) * lowSun * glow * twilight.z * smoothstep(0.0, horizonBlend.x * 2, elevation);
	oColor.rgb = lerp(oColor.rgb, edgeColour, fogValue);
}
