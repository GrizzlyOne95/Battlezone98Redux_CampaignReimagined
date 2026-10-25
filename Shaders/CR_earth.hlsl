// Campaign Reimagined: the Earth seen from the Moon (CREARTH.MAP,
// Materials/cr_earth.material). One source for DX11 (SM4=1) and DX9 (SM3);
// there is no GLSL twin, so OpenGL falls through to the material's stock
// technique (the flat earth.dds disc).
//
// The TRN [Stars] entry draws a flat quad. The shader treats the disc on it
// as a sphere and lights it from the TRN sun, so the phase is the one the Moon
// would see: the Sun is far enough away that the angle between it and the
// Earth fixes the terminator. It draws:
//   - the Blue Marble surface with its cloud cover (crsky_earth.png, A clouds),
//     turning once a real day;
//   - a soft terminator, reddened where the light grazes;
//   - city lights on the night side, dimmed under cloud
//     (crsky_earth_night.png R; Tools/Build-EarthSky.py bakes both maps);
//   - the Sun's glint on open water (crsky_earth_night.png G);
//   - a thin blue atmosphere at the lit limb.
// The disc is opaque, so the night side hides the stars behind it.
// CRWorldArt.InstallStarBox writes sunDirection (toward the sun, w = 1).

#if defined(SM4)
#define DECLARE_MAP(name, reg) Texture2D name : register(t##reg); SamplerState name##Sam : register(s##reg);
#define SAMPLE_GRAD(name, uv, gx, gy) name.SampleGrad(name##Sam, uv, gx, gy)
#define POSITION_OUT SV_POSITION
#define COLOUR_OUT SV_TARGET
#else
#define DECLARE_MAP(name, reg) sampler2D name : register(s##reg);
#define SAMPLE_GRAD(name, uv, gx, gy) tex2Dgrad(name, uv, gx, gy)
#define POSITION_OUT POSITION
#define COLOUR_OUT COLOR
#endif

DECLARE_MAP(earthMap, 0)
DECLARE_MAP(nightMap, 1)

static const float PI = 3.14159265;
static const float3 CLOUD_COLOUR = float3(0.92, 0.93, 0.95);
static const float3 LIGHTS_COLOUR = float3(1.00, 0.72, 0.40);
static const float3 AIR_COLOUR = float3(0.30, 0.52, 1.00);
static const float3 DUSK_COLOUR = float3(1.00, 0.55, 0.30);

void earth_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 worldMat,
	uniform float4 cameraPosition,
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float2 vTexCoord : TEXCOORD0,
	out float3 vView : TEXCOORD1,
	out float4 oPosition : POSITION_OUT)
{
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iTexCoord;
	// Camera relative, so it stays precise at 0.9x far.
	vView = mul(worldMat, iPosition).xyz - cameraPosition.xyz;
}

float3 sky_decode(float3 c)
{
	c = max(c, 0); return lerp(c / 12.92, pow((c + .055) / 1.055, 2.4), step(.04045, c));
}
float3 sky_encode(float3 c)
{
	c = max(c, 0); return lerp(c * 12.92, 1.055 * pow(max(c, 1e-8), 1.0 / 2.4) - .055, step(.0031308, c));
}

// earthLook: x disc radius in UV, y halo width over the radius,
//            z day gain, w night side brightness
// earthLights: x city light gain, y cloud dimming, z glint gain, w glint power
// earthSpin: x longitude facing the camera at time 0 (radians),
//            y radians a second (negative: the Earth turns east),
//            zw axis tilt across and toward the camera
void earth_fragment(
	uniform float4 sunDirection,
	uniform float4 earthLook,
	uniform float4 earthLights,
	uniform float4 earthSpin,
	uniform float earthTime,
	in float2 vTexCoord : TEXCOORD0,
	in float3 vView : TEXCOORD1,
	out float4 oColour : COLOUR_OUT)
{
	// The quad's frame in the world: T along u, B along v, N toward the camera.
	float3 dpx = ddx(vView), dpy = ddy(vView);
	float2 dux = ddx(vTexCoord), duy = ddy(vTexCoord);
	float3 face = normalize(cross(dpx, dpy));
	float3 px = cross(face, dpx), py = cross(dpy, face);
	float3 T = normalize(py * dux.x + px * duy.x);
	float3 B = normalize(py * dux.y + px * duy.y);
	float3 N = cross(T, B);
	float3 V = -normalize(vView);
	N *= dot(N, V) < 0 ? -1 : 1;

	float2 d = (vTexCoord - 0.5) / earthLook.x;
	float r = length(d);
	float z = sqrt(saturate(1 - r * r));
	float3 n = normalize(d.x * T + d.y * B + z * N);

	// North is world up as seen on the quad, leaned by the tilt.
	float3 up = float3(0, 1, 0) - dot(float3(0, 1, 0), N) * N;
	up = dot(up, up) > 1e-4 ? normalize(up) : -B;
	float3 side = cross(up, N);
	float3 axis = normalize(up + earthSpin.z * side + earthSpin.w * N);
	float3 e0 = normalize(N - dot(N, axis) * axis);
	float3 e1 = cross(axis, e0);

	float lat = asin(clamp(dot(n, axis), -1, 1));
	float lon = atan2(dot(n, e1), dot(n, e0)) + earthSpin.x + earthSpin.y * earthTime;
	float2 uv = float2(frac(lon / (2 * PI) + 0.5), 0.5 - lat / PI);
	// Take the u gradient from whichever side of the seam is continuous.
	float2 uvSeam = float2(frac(uv.x + 0.5), uv.y);
	float2 gx = ddx(uv), gy = ddy(uv), sx = ddx(uvSeam), sy = ddy(uvSeam);
	gx.x = abs(sx.x) < abs(gx.x) ? sx.x : gx.x;
	gy.x = abs(sy.x) < abs(gy.x) ? sy.x : gy.x;
	float4 surface = SAMPLE_GRAD(earthMap, uv, gx, gy);
	float4 night = SAMPLE_GRAD(nightMap, uv, gx, gy);

	float3 L = sunDirection.w > 0.5 ? normalize(sunDirection.xyz) : normalize(side + 0.3 * up + 0.4 * N);
	float nl = dot(n, L);
	float cloud = surface.a;
	float3 albedo = lerp(sky_decode(surface.rgb), CLOUD_COLOUR, cloud * 0.9);

	float lit = saturate(nl) * smoothstep(-0.05, 0.1, nl);
	float graze = smoothstep(0.25, 0.0, nl) * smoothstep(-0.08, 0.02, nl);
	float3 colour = albedo * lerp(1, DUSK_COLOUR, graze * 0.6) * (lit * earthLook.z + earthLook.w);

	float dark = smoothstep(0.05, -0.12, nl);
	colour += LIGHTS_COLOUR * night.r * dark * (1 - cloud * earthLights.y) * earthLights.x;

	float3 H = normalize(L + V);
	float glint = pow(saturate(dot(n, H)), earthLights.w) * night.g * (1 - cloud) * saturate(nl * 4);
	colour += glint * earthLights.z;

	// Air: brightest at the limb, lit from the sun side and wrapping a little
	// past the terminator.
	float limb = pow(1 - z, 3);
	float airLit = saturate(nl + 0.25);
	colour += AIR_COLOUR * limb * airLit * 0.7;

	float aa = max(fwidth(r), 1e-4);
	float disc = saturate((1 - r) / aa + 0.5);
	float3 rim = normalize(d.x * T + d.y * B);
	float halo = pow(saturate(1 - (r - 1) / earthLook.y), 2) * step(1, r) * saturate(dot(rim, L) + 0.25);
	float3 rgb = lerp(AIR_COLOUR * 0.8, colour, disc);
	oColour = float4(sky_encode(rgb), max(disc, halo * 0.6));
}
