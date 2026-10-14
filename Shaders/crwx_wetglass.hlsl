// Campaign Reimagined (ported from ISDF Chronicles): wet-glass rain overlay, masked to the cockpit glass.
//
// Drops (unit 0) keep the size and drift CRWetGlass.lua gives each panel's UVs,
// but are laid on the canopy instead of the screen: each pixel's view ray, in
// the cockpit frame, is mapped onto a dome around the eye (canopy.y = 1), a
// flat pane (0), or a tighter wrap still (above 1: the ray is widened by the
// curvature before its angles are taken, which stays monotonic at any FOV).
// On the dome the drops stay put on the glass when the camera
// tips, and swell and bend toward the edges of the view the way drops on a
// curved canopy do. The cockpit mask (unit 1, ISDFC tools/wetmaskgen.py) is looked
// up by the same ray: each
// pixel's view tangents come from its overlay NDC and the camera's live FOV and
// viewport aspect, then map onto the mask's tangent extents. White = glass.
//
// The camera is not bolted to the cockpit: it pitches and rolls against it as
// the craft moves. CRWetGlass.lua measures the camera's rotation in the craft's
// frame each frame and parks it in the mask unit's texture transform (scroll
// u = yaw, scroll v = pitch, rotate = roll); maskXform is that transform, and
// the vertex program turns each view ray into the cockpit frame with it.
//
// SM4 (DX11) by default; SM3 (DX9) with SM3 defined.

float4x4 wvpMat;
float fovY;              // camera vertical FOV, radians
float4 viewportSize;     // w, h, 1/w, 1/h
float4 maskExtent;       // tan x, tan y the mask spans (xy)
float4x4 maskXform;      // texture_matrix of unit 1: camera yaw, pitch, roll
float opacity;
float4 canopy;           // x: tan of the half vertical FOV the drops are sized for, y: curvature

#ifdef SM3
sampler2D drops : register(s0);
sampler2D glassMask : register(s1);
#define SAMPLE(t, s, uv) tex2D(t, uv)
#define POS_OUT POSITION
#define COLOUR_OUT COLOR
#else
Texture2D drops : register(t0);
SamplerState dropsSampler : register(s0);
Texture2D glassMask : register(t1);
SamplerState maskSampler : register(s1);
#define SAMPLE(t, s, uv) t.Sample(s, uv)
#define POS_OUT SV_Position
#define COLOUR_OUT SV_Target
#endif

// Ogre builds a texture matrix as rotate(roll) * translate(u, v), the rotation
// centred on (0.5, 0.5). Undo that to get the three angles back.
float3 camera_angles()
{
	float c = maskXform[0][0], s = maskXform[1][0];
	float2 t = float2(maskXform[0][3], maskXform[1][3])
	         - float2(0.5 - 0.5 * c + 0.5 * s, 0.5 - 0.5 * s - 0.5 * c);
	return float3(c * t.x + s * t.y, -s * t.x + c * t.y, atan2(s, c));
}

// Camera-frame ray to cockpit frame: yaw(y) * pitch(x) * roll(z), x right,
// y up, z forward, the order CRWetGlass.lua decomposes in.
float3 to_cockpit(float3 d)
{
	float3 a = camera_angles();
	float sy = sin(a.x), cy = cos(a.x), sp = sin(a.y), cp = cos(a.y), sr = sin(a.z), cr = cos(a.z);
	d = float3(cr * d.x - sr * d.y, sr * d.x + cr * d.y, d.z);
	d = float3(d.x, cp * d.y + sp * d.z, -sp * d.y + cp * d.z);
	return float3(cy * d.x + sy * d.z, d.y, -sy * d.x + cy * d.z);
}

void wet_vertex(float4 position : POSITION, float2 uv : TEXCOORD0,
                out float4 oPosition : POS_OUT, out float2 oUv : TEXCOORD0, out float3 oRay : TEXCOORD1,
                out float3 oScreen : TEXCOORD2)
{
	oPosition = mul(wvpMat, position);
	float2 ndc = oPosition.xy / oPosition.w;
	float ty = tan(fovY * 0.5);
	float tx = ty * viewportSize.x * viewportSize.w;
	// Linear across the quad, so the fragment divides after interpolation.
	oRay = to_cockpit(float3(ndc.x * tx, ndc.y * ty, 1.0));
	oUv = uv;
	oScreen = float3(0.5 + 0.5 * ndc.x, 0.5 - 0.5 * ndc.y, viewportSize.x * viewportSize.w);
}

// The panel's UVs run linearly across the screen, uv = origin + screen * span;
// recover origin and span, then feed the canopy position through the same map.
float2 canopy_uv(float2 uv, float3 screen, float3 ray)
{
	float2 span = float2(ddx(uv.x) / ddx(screen.x), ddy(uv.y) / ddy(screen.y));
	float2 origin = uv - screen.xy * span;
	float k = max(canopy.y, 0.01);
	float3 r = float3(ray.xy * k, max(ray.z, 1e-3));
	float2 g = float2(atan2(r.x, r.z), atan2(r.y, length(r.xz))) / k;
	return origin + float2(0.5 + 0.5 * g.x / (canopy.x * screen.z), 0.5 - 0.5 * g.y / canopy.x) * span;
}

#ifdef SM3
float4 wet_fragment(float2 uv : TEXCOORD0, float3 ray : TEXCOORD1, float3 screen : TEXCOORD2) : COLOUR_OUT
#else
float4 wet_fragment(float4 pos : SV_Position, float2 uv : TEXCOORD0, float3 ray : TEXCOORD1,
                    float3 screen : TEXCOORD2) : COLOUR_OUT
#endif
{
	float4 c = SAMPLE(drops, dropsSampler, canopy_uv(uv, screen, ray));
	float2 view = ray.xy / max(ray.z, 1e-3);
	float2 maskUv = float2(0.5 + 0.5 * view.x / maskExtent.x, 0.5 - 0.5 * view.y / maskExtent.y);
	float glass = SAMPLE(glassMask, maskSampler, maskUv).r;
	return float4(c.rgb, c.a * opacity * glass);
}
