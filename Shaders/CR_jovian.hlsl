// Campaign Reimagined: Jupiter and the other Galilean moons seen from Io
// (CRJOVIAN.MAP, CREUROPA.MAP, CRGANYME.MAP, CRCALLIS.MAP;
// Materials/cr_jovian.material). One source for DX11 (SM4=1) and DX9 (SM3);
// there is no GLSL twin, so OpenGL falls through to each material's stock
// technique.
//
// As in CR_earth.hlsl, the TRN [Stars] entry draws a flat quad and the shader
// treats the disc on it as a sphere lit by the TRN sun, so every body shows the
// phase Io would see. Io and the other moons orbit in Jupiter's equator plane,
// so the pole (bodyPole) lies across the disc and each body is seen equator-on.
// It draws:
//   - the map (Tools/Build-JupiterSky.py bakes them), turned about the pole by
//     bodySpin.x, which Scripts/CRWorldArt.lua advances with the orbit;
//   - Minnaert limb darkening and a soft terminator;
//   - a thin lit haze at Jupiter's limb that brightens as the sun goes behind
//     the planet: the thin crescent either side of the eclipse;
//   - while the sun is behind the disc, a ring of sunlight bent and reddened
//     through Jupiter's upper atmosphere (bodyRing).
// The disc is opaque, so the night side hides the stars behind it.
// CRWorldArt writes sunDirection (toward the sun, w = 1) and bodyPole.

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

DECLARE_MAP(bodyMap, 0)

static const float PI = 3.14159265;
static const float3 HAZE_COLOUR = float3(1.00, 0.86, 0.66);

void jovian_vertex(
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

// bodyPole: xyz the body's north pole in world space, w 1 once Lua has set it
//           (until then north is world up as seen on the quad).
// bodyLook: x disc radius in UV, y halo width over the radius,
//           z day gain, w night side brightness
// bodySpin: x longitude facing the camera (radians), y unused,
//           z Minnaert exponent (1 Lambert; lower flattens the disc),
//           w limb haze gain
// bodyRing: rgb the eclipse ring's colour and gain, w its width over the radius
void jovian_fragment(
	uniform float4 sunDirection,
	uniform float4 bodyPole,
	uniform float4 bodyLook,
	uniform float4 bodySpin,
	uniform float4 bodyRing,
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

	float2 d = (vTexCoord - 0.5) / bodyLook.x;
	float r = length(d);
	float z = sqrt(saturate(1 - r * r));
	float3 n = normalize(d.x * T + d.y * B + z * N);

	float3 up = float3(0, 1, 0) - dot(float3(0, 1, 0), N) * N;
	up = dot(up, up) > 1e-4 ? normalize(up) : -B;
	float3 axis = bodyPole.w > 0.5 ? normalize(bodyPole.xyz) : up;
	float3 e0 = N - dot(N, axis) * axis;
	e0 = dot(e0, e0) > 1e-4 ? normalize(e0) : T;
	float3 e1 = cross(axis, e0);

	float lat = asin(clamp(dot(n, axis), -1, 1));
	float lon = atan2(dot(n, e1), dot(n, e0)) + bodySpin.x;
	float2 uv = float2(frac(lon / (2 * PI) + 0.5), 0.5 - lat / PI);
	// Take the u gradient from whichever side of the seam is continuous.
	float2 uvSeam = float2(frac(uv.x + 0.5), uv.y);
	float2 gx = ddx(uv), gy = ddy(uv), sx = ddx(uvSeam), sy = ddy(uvSeam);
	gx.x = abs(sx.x) < abs(gx.x) ? sx.x : gx.x;
	gy.x = abs(sy.x) < abs(gy.x) ? sy.x : gy.x;
	float3 albedo = sky_decode(SAMPLE_GRAD(bodyMap, uv, gx, gy).rgb);

	float3 side = cross(up, N);
	float3 L = sunDirection.w > 0.5 ? normalize(sunDirection.xyz) : normalize(side + 0.3 * up + 0.4 * N);
	float nl = dot(n, L);
	float nv = max(dot(n, V), 0.05);
	// Minnaert: mu0^k mu^(k-1). Below k 1 it darkens the full disc toward the
	// limb less than Lambert and lifts a thin crescent's limb.
	float k = bodySpin.z;
	float lit = pow(saturate(nl), k) * pow(nv, k - 1) * smoothstep(-0.03, 0.08, nl);
	float3 colour = albedo * (lit * bodyLook.z + bodyLook.w);

	// How far the sun is behind the body: 1 dead behind, 0.986 at Jupiter's
	// limb seen from Io.
	float behind = dot(L, -N);
	float3 rim = r > 1e-4 ? normalize(d.x * T + d.y * B) : T;
	float forward = 1 + 6 * pow(saturate(behind), 12);
	float limbHaze = pow(1 - z, 4) * saturate(nl + 0.2) * forward;
	colour += HAZE_COLOUR * limbHaze * bodySpin.w;

	// Eclipse ring: sunlight refracted around the limb, strongest on the side
	// nearest the sun.
	float eclipse = smoothstep(0.975, 0.995, behind);
	float ringSide = 0.35 + 0.65 * saturate(dot(rim, L) * 6 + 0.5);
	float ring = exp(-abs(r - 1) / max(bodyRing.w, 1e-4)) * eclipse * ringSide;
	float3 glow = bodyRing.rgb * ring;
	colour += glow;

	float halo = pow(saturate(1 - (r - 1) / bodyLook.y), 2) * step(1, r) * saturate(dot(rim, L) + 0.25);
	glow += HAZE_COLOUR * halo * bodySpin.w * 0.3 * forward;

	float aa = max(fwidth(r), 1e-4);
	float disc = saturate((1 - r) / aa + 0.5);
	float glowAlpha = saturate(max(glow.r, max(glow.g, glow.b)));
	float3 rgb = lerp(glow / max(glowAlpha, 1e-4), colour, disc);
	oColour = float4(sky_encode(rgb), max(disc, glowAlpha));
}
