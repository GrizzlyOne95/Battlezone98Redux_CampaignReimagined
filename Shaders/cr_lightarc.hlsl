// Campaign Reimagined: moving electric bolts for the L-Power plants' lightning panels
// (Materials/cr_lightarc.material; Tools/Build-LightningPlants.py splits the panel faces into
// their own submesh). Procedural bolts and flicker over the baked diffuse/emissive art:
//
//   - the emissive map is both the glow and the mask: bolts only appear where the baked art
//     already shows lightning, and take its hue (blue for NSDF, yellow for Black Dog);
//   - two ridged-noise layers draw thin bright lines. Each layer jumps to a new random seed
//     several times a second and cross-fades between seeds, so the bolts crawl and
//     re-strike instead of scrolling like a texture;
//   - a global flicker breathes the whole panel.
// Unlit and opaque: the panels are glowing glass in a recess, and Ogre texture scrolling
// cannot animate the stock lit path (CR_BZBase has no texture matrix).
//
// Reads POSITION and TEXCOORD0 only (never COLOR0 or NORMAL). One source for both D3D paths:
// the HLSL4 delegates compile with SM4=1 (vs_4_0/ps_4_0), the HLSL delegates without (SM3).

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

float4x4 wvpMat;

void lightarc_vertex(
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float2 vTex : TEXCOORD0,
	out float vDepth : TEXCOORD1,
	out float4 oPosition : POSITION_OUT)
{
	oPosition = mul(wvpMat, iPosition);
	vTex = iTexCoord;
	vDepth = oPosition.z;
}

float hash21(float2 p)
{
	return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float vnoise(float2 p)
{
	float2 i = floor(p);
	float2 f = frac(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + float2(1.0, 0.0));
	float c = hash21(i + float2(0.0, 1.0));
	float d = hash21(i + float2(1.0, 1.0));
	return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

// One ridged-noise field: thin bright lines wherever the smooth noise crosses 0.5.
float ridge(float2 p, float seed)
{
	float2 q = p + float2(seed * 17.31, seed * 9.77);
	float n = vnoise(q) * 0.65 + vnoise(q * 2.3 + 5.2) * 0.35;
	float r = 1.0 - abs(n * 2.0 - 1.0);
	float r2 = r * r;
	return r2 * r2 * r2;
}

// Cross-fade between this strike's field and the next one's.
float strike(float2 p, float t, float rate, float layer)
{
	float s = t * rate;
	float k = floor(s);
	float w = smoothstep(0.55, 1.0, frac(s));
	float2 drift = float2(t * 0.35 * (layer + 1.0), -t * 0.5);
	return lerp(ridge(p + drift, k + layer * 31.0), ridge(p + drift, k + 1.0 + layer * 31.0), w);
}

DECLARE_MAP(diffuseMap, 0)
DECLARE_MAP(emissiveMap, 1)

float time;
float3 fogColour;
float4 fogParams;
float3 sceneAmbient;
float3 lightDiffuse;

void lightarc_fragment(
	in float2 vTex : TEXCOORD0,
	in float vDepth : TEXCOORD1,
	out float4 oColor : COLOUR_OUT)
{
	float3 dif = SAMPLE(diffuseMap, vTex).rgb;
	float3 emi = SAMPLE(emissiveMap, vTex).rgb;
	float peak = max(max(emi.r, emi.g), max(emi.b, 0.02));
	float3 tint = emi / peak;
	float mask = saturate((dot(emi, float3(0.3, 0.5, 0.2)) - 0.08) * 5.0);

	// The art is square in texels but the atlas is 2:1.
	float2 p = vTex * float2(2.0, 1.0) * 46.0;
	float bolt = strike(p, time, 7.0, 0.0) + strike(p * 1.9, time, 11.0, 1.0) * 0.65;
	float flick = 0.70 + 0.30 * hash21(float2(floor(time * 23.0), 3.0));
	float slow = 0.85 + 0.15 * sin(time * 4.3982297);
	float3 core = lerp(tint, float3(1.0, 1.0, 1.0), 0.55);

	float3 lit = saturate(sceneAmbient + lightDiffuse * 0.6);
	lit = max(lit, float3(0.28, 0.28, 0.28));
	float3 col = dif * lit * 0.8;
	col += emi * (0.55 + 0.45 * flick) * slow;
	col += core * bolt * mask * flick * 1.6;

	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor = float4(lerp(col, fogColour, fogValue), 1.0);
}
