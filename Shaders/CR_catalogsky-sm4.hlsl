// Catalog sky box: real star positions drawn as fixed-size points over a
// low-frequency Milky Way map. Tools/Build-CatalogSky.py bakes the star index:
// six 512x512 faces stacked vertically, one star per texel as
// (offset u, offset v, magnitude code, colour code). One texel lookup per pixel
// finds the only star that can reach it, so stars stay sharp at any resolution
// and the index costs a few hundred KB, not a multi-megapixel cubemap.
// Ogre's generated box has position and UV only; the direction is the box
// vertex itself because the box is centred on the camera.

static const float CELLS = 512.0;
static const float OFFSET_RANGE = 2.0;
static const float MAG_LIMIT = 8.0;
static const float MAG_STEP = 24.0;
static const float BV_MIN = -0.5;
static const float BV_SPAN = 2.5;
static const float PI = 3.14159265;

// With a sun direction, the star sphere is turned so the sun sits at the March
// equinox (RA 0, Dec 0, galactic latitude -60) and the galactic centre lies
// toward the zenith on the far side of the sky. The Milky Way then stays at
// least 60 degrees from the sun at any sun angle.
static const float3 SUN_EQ = float3(1, 0, 0);
static const float3 GC_EQ = float3(0, -0.874755, -0.484565);
static const float3 POLE_EQ = float3(0, 0.484565, -0.874755);
static const float3 SUN_COLOUR = float3(1.00, 0.97, 0.92);
static const float3 GLARE_COLOUR = float3(1.00, 0.90, 0.78);

void catalogsky_vertex(
	uniform float4x4 wvpMat,
	in float4 iPosition : POSITION,
	out float3 vDir : TEXCOORD0,
	out float4 oPosition : SV_POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	oPosition.z = oPosition.w * 0.9999;
	vDir = iPosition.xyz;
}

float3 sky_decode(float3 c)
{
	c = max(c, 0); return lerp(c / 12.92, pow((c + .055) / 1.055, 2.4), step(.04045, c));
}
float3 sky_encode(float3 c)
{
	c = max(c, 0); return lerp(c * 12.92, 1.055 * pow(max(c, 1e-8), 1.0 / 2.4) - .055, step(.0031308, c));
}

// Linear star colour from B-V: hot blue-white through solar white to deep orange.
float3 star_colour(float bv)
{
	const float3 c0 = float3(0.62, 0.72, 1.00); // B-V -0.3
	const float3 c1 = float3(0.92, 0.95, 1.00); // 0.0
	const float3 c2 = float3(1.00, 0.96, 0.88); // 0.6
	const float3 c3 = float3(1.00, 0.80, 0.58); // 1.0
	const float3 c4 = float3(1.00, 0.58, 0.32); // 1.6
	float3 c = lerp(c0, c1, saturate((bv + 0.3) / 0.3));
	c = lerp(c, c2, saturate(bv / 0.6));
	c = lerp(c, c3, saturate((bv - 0.6) / 0.4));
	return lerp(c, c4, saturate((bv - 1.0) / 0.6));
}

// World to J2000. The world frame is built from the sun and a pole (the
// zenith unless skyOrbit says otherwise) the same way the celestial frame is
// built from SUN_EQ and GC_EQ. A sun that circles the pole turns the stars
// with it as one rigid sphere.
float3 sky_direction(float3 p, float4x4 skyRotation, float4 sunDirection, float4 skyOrbit)
{
	if (sunDirection.w <= 0.5) return mul((float3x3)skyRotation, p);
	float3 w1 = normalize(sunDirection.xyz);
	float3 pole = normalize(skyOrbit.xyz);
	float3 up = abs(dot(w1, pole)) > 0.999 ? (abs(pole.y) < 0.9 ? float3(0, 1, 0) : float3(0, 0, 1)) : pole;
	float3 w2 = normalize(up - dot(up, w1) * w1);
	float3 w3 = cross(w1, w2);
	return SUN_EQ * dot(p, w1) + GC_EQ * dot(p, w2) + POLE_EQ * dot(p, w3);
}

// starParams: x gain, y core sigma (pixels), z halo gain, w reference magnitude.
// starShape:  x brightness exponent (1 = physical), y halo radius (pixels).
// milkyParams: x gain, y RA direction (+1/-1), z RA of the map's left edge (turns).
// sunDirection: xyz toward the sun in world space, w 1 once Lua has set it.
//               At w 0 the sky keeps skyRotation and draws no sun.
// sunLook:  x disc radius (image plane, about radians at the screen centre),
//           y disc gain, z/w the stars fade in from z to w (radians).
// sunGlow:  x glare gain at the limb, y glare falloff power,
//           z halo gain, w halo radius (radians).
// skyOrbit: xyz the pole the sun circles (world up on the Moon), w how much
//           of the sun shows: 0 hides the disc and glare (Io in Jupiter's
//           shadow) and brings the stars back around it.
void catalogsky_fragment(
	uniform Texture2D starIndex : register(t0),
	uniform SamplerState starSam : register(s0),
	uniform Texture2D milkyWay : register(t1),
	uniform SamplerState milkySam : register(s1),
	uniform float4x4 skyRotation,
	uniform float4 starParams,
	uniform float4 starShape,
	uniform float4 milkyParams,
	uniform float4 sunDirection,
	uniform float4 sunLook,
	uniform float4 sunGlow,
	uniform float4 skyOrbit,
	uniform float4x4 inverseView,
	in float3 vDir : TEXCOORD0,
	out float4 oColor : SV_TARGET)
{
	float3 p = normalize(vDir);
	float3 d = normalize(sky_direction(p, skyRotation, sunDirection, skyOrbit));
	float pixelAngle = max(max(length(ddx(d)), length(ddy(d))), 1e-6);

	// Face selection; must match Build-CatalogSky.py.
	float3 ad = abs(d);
	float3 n, u, v;
	float face;
	if (ad.x >= ad.y && ad.x >= ad.z) { n = float3(sign(d.x), 0, 0); u = float3(0, 1, 0); v = float3(0, 0, 1); face = d.x < 0 ? 1 : 0; }
	else if (ad.y >= ad.z)            { n = float3(0, sign(d.y), 0); u = float3(0, 0, 1); v = float3(1, 0, 0); face = d.y < 0 ? 3 : 2; }
	else                              { n = float3(0, 0, sign(d.z)); u = float3(1, 0, 0); v = float3(0, 1, 0); face = d.z < 0 ? 5 : 4; }
	float major = dot(d, n);
	float2 uv = float2(dot(d, u), dot(d, v)) / major;
	float2 cell = clamp(floor((uv * 0.5 + 0.5) * CELLS), 0, CELLS - 1);
	float4 texel = starIndex.Load(int3(cell.x, face * CELLS + cell.y, 0));

	float3 stars = 0;
	if (texel.b > 0)
	{
		float2 starCell = cell + 0.5 + (texel.rg * 2 - 1) * OFFSET_RANGE;
		float2 starUv = starCell / CELLS * 2 - 1;
		float3 starDir = normalize(n + starUv.x * u + starUv.y * v);
		float r = length(d - starDir) / pixelAngle;
		float mag = MAG_LIMIT - (texel.b * 255 - 1) / MAG_STEP;
		float flux = pow(10.0, -0.4 * starShape.x * (mag - starParams.w));
		float sigma = starParams.y;
		float core = exp(-0.5 * r * r / (sigma * sigma)) / (2 * PI * sigma * sigma);
		float halo = starParams.z * exp(-r / starShape.y);
		stars = star_colour(texel.a * BV_SPAN + BV_MIN) * flux * starParams.x * (core + halo);
	}

	// Equirectangular Milky Way, J2000. Explicit gradients keep the RA seam
	// from selecting the smallest mip in a one-pixel column.
	float ra = atan2(d.y, d.x) / (2 * PI);
	float dec = asin(clamp(d.z, -1, 1)) / PI;
	float2 mwUv = float2(frac(milkyParams.z + milkyParams.y * ra), 0.5 - dec);
	float2 gx = ddx(mwUv), gy = ddy(mwUv);
	gx.x -= round(gx.x); gy.x -= round(gy.x);
	float3 milky = sky_decode(milkyWay.SampleGrad(milkySam, mwUv, gx, gy).rgb) * milkyParams.x;

	float3 sky = milky + stars;
	if (sunDirection.w > 0.5)
	{
		// Sun: a limb-darkened disc with a one-pixel edge, a power-law glare and
		// a wide faint halo. There is no air to scatter it, so the sky stays
		// black, but the stars and the Milky Way fade out close to the sun.
		// The disc and glare are measured on the image plane, so the sun stays
		// round and one size anywhere on screen, like the engine sprite did.
		float3 s = normalize(sunDirection.xyz);
		float3 f = normalize(mul((float3x3)inverseView, float3(0, 0, -1)));
		float3 q = p / max(dot(p, f), 1e-3);
		float pixelPlane = max(max(length(ddx(q)), length(ddy(q))), 1e-6);
		float theta = 2 * asin(saturate(0.5 * length(p - s)));
		float t = dot(s, f) > 0.01 ? length(q - s / dot(s, f)) / sunLook.x : 1e3;
		float disc = saturate((1 - t) * sunLook.x / pixelPlane + 0.5);
		float limb = 0.4 + 0.6 * sqrt(saturate(1 - t * t));
		float glare = sunGlow.x * pow(saturate(1 / max(t, 1)), sunGlow.y) + sunGlow.z * exp(-theta / sunGlow.w);
		float fade = smoothstep(sunLook.z, sunLook.w, theta);
		sky = sky * lerp(1, fade, skyOrbit.w) + (SUN_COLOUR * (sunLook.y * disc * limb) + GLARE_COLOUR * glare) * skyOrbit.w;
	}

	oColor = float4(sky_encode(sky), 1);
}
