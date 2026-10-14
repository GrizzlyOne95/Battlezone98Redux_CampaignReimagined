// Campaign Reimagined: liquid methane surface for Titan's lakes (Materials/cr_methane.material).
//
// A flat, alpha-blended sheet laid just above a map's flat methane sea floor by
// CRTitanWeather through EXU StaticGeometry (Scripts/CRTitanWeather.lua). Where the
// liquid lies comes from a generated wet-mask texture (Tools/Build-MethaneSurface.py,
// from the same MAT/HG2 rule as Scripts/CRTitanSites<NN>.lua); everything else on the
// sheet is clipped. Ported from the WATER kind of ISDF Chronicles'
// isdfc_surface.hlsl, with these differences:
//
//   - the ripple normal comes from a tileable normal map (two scrolling layers) plus
//     procedural drizzle rings, not from the diffuse map's luminance;
//   - the tangent frame is the sheet's own axes (it is a flat plane with known UV
//     directions), so no derivatives and no mesh tangents are needed;
//   - the reflected sky is the fog colour at the horizon rising to a zenith colour,
//     brightened by forward scattering round the low sun (Titan's haze), and the sun
//     itself leaves a warm, wide glare lobe and sharp glints;
//   - four controls arrive in the pass diffuse colour (surface_diffuse_colour), which
//     the director sets with exu.SetMaterialPassColors:
//         x  drizzle rings (0..1)      y  glare strength (0..~1.5)
//         z  wetness / opacity (0..1)  w  wind chop (0..1)
//
// Conventions follow the stock base programs and isdfc_surface.hlsl: the stock
// per-pixel light loop over light_position_view_space_array (light 0 is the sun),
// the stock linear fog on clip-space depth on every path (Tools/Validate-DX11Shaders.ps1
// keeps distance-based fog to the two DX11 Enhanced world shaders; under Enhanced the
// liquid therefore fogs a little less than the floor toward the screen edges, and it
// fades its own opacity with fog so the floor's fog shows through), and
// POSITION/NORMAL/TEXCOORD0 inputs only.
//
// One source for both D3D paths: the HLSL4 delegates compile it with SM4=1 for
// vs_4_0/ps_4_0 (DX11), the HLSL delegates without it for vs_3_0/ps_3_0 (DX9).
// There is no GLSL twin: on OpenGL the material falls through to an invisible
// technique and the director's particle sheen remains the liquid look.
// Tools/Test-MethaneShader.ps1 compiles every delegate.

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

#ifndef MAX_LIGHTS
#define MAX_LIGHTS 8
#endif

// ---------------------------------------------------------------------------
// Vertex

float4x4 wvpMat;
float4x4 worldViewMat;

struct MethaneV2F
{
	float2 uv : TEXCOORD0;
	float4 viewPos : TEXCOORD1;   // xyz view-space position, w clip-space depth
	float3 viewNormal : TEXCOORD2;
	float3 viewU : TEXCOORD3;     // the sheet's +u axis in view space
	float3 viewV : TEXCOORD4;     // the sheet's +v axis in view space
};

void methane_vertex(
	in float4 iPosition : POSITION,
	in float3 iNormal : NORMAL,
	in float2 iTexCoord : TEXCOORD0,

	out MethaneV2F o,
	out float4 oPosition : POSITION_OUT
)
{
	oPosition = mul(wvpMat, iPosition);
	o.uv = iTexCoord;
	o.viewPos.xyz = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
	o.viewPos.w = oPosition.z;
	o.viewNormal = mul(worldViewMat, float4(iNormal, 0.0)).xyz;
	// The sheet mesh (cr_methane_plane.mesh) runs u along local +x and v along
	// local +z; StaticGeometry bakes the instance transform into the vertices.
	o.viewU = mul(worldViewMat, float4(1.0, 0.0, 0.0, 0.0)).xyz;
	o.viewV = mul(worldViewMat, float4(0.0, 0.0, 1.0, 0.0)).xyz;
}

// ---------------------------------------------------------------------------
// Fragment

DECLARE_MAP(rippleMap, 0)   // tileable ripple normal map (cr_methane_ripple.png)
DECLARE_MAP(wetMask, 1)     // per-map wet mask, R = liquid coverage

float4 fogColour;
float4 fogParams;
float4 sceneAmbient;
float4 lightDiffuse[MAX_LIGHTS];
float4 lightSpecular[MAX_LIGHTS];
float4 lightPosition[MAX_LIGHTS];
float4 lightAttenuation[MAX_LIGHTS];
float4 spotLightParams[MAX_LIGHTS];
float4 lightDirection[MAX_LIGHTS];
float lightCount;
float4x4 viewMat;
float time;

float4 methaneControl;  // surface_diffuse_colour: x drizzle rings, y glare, z wetness, w wind chop
float4 methaneSun;      // surface_specular_colour: xyz the haze sun's light direction (world, travelling
                        // away from the sun), w 0..1 how far to use it instead of light 0's direction
float4 methaneExtent;   // xy: metres per UV unit (sheet size), z/w: wet-mask smoothstep edges
float4 methaneBody;     // rgb: colour the liquid scatters back (lit by ambient + diffuse), a: absorption per path
float4 methaneSky;      // rgb: zenith colour of the reflected sky, a: reflection strength
float4 methaneSurface;  // x: how much a glint hides the floor, y: shortest path cosine, z: Fresnel F0, w: ripple fade distance
float4 methaneWaves;    // x: layer A tile (m), y: layer B tile (m), z: ripple slope, w: wind drift (m/s)
float4 methaneGlare;    // rgb: glare tint, a: glare lobe exponent (wide, haze-softened)
float4 methaneGlint;    // x: glint exponent, y: glint strength, z: drizzle ring cell (m), w: ring rate (1/s)

float3 safe_normalize(float3 v)
{
	float lenSq = dot(v, v);
	return lenSq > 1e-8 ? v * rsqrt(lenSq) : float3(0.0, 0.0, 1.0);
}

float luminance(float3 c)
{
	return dot(c, float3(0.299, 0.587, 0.114));
}

float fog_amount(float4 viewPos)
{
	return saturate((viewPos.w - fogParams.y) * fogParams.w);
}

float hash12(float2 p)
{
	float3 p3 = frac(float3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return frac((p3.x + p3.y) * p3.z);
}

// One layer of drizzle rings: every cell of a grid holds one ring that expands
// and fades on its own phase. Returns the surface slope (d height / d metre).
float2 ring_slope(float2 p, float cell, float rate, float salt)
{
	float2 g = p / cell;
	float2 id = floor(g);
	float2 jitter = float2(hash12(id + salt), hash12(id + salt + 17.0)) - 0.5;
	float2 d = frac(g) - 0.5 - jitter * 0.35;
	float r = length(d);
	float phase = frac(time * rate + hash12(id + salt + 41.0));
	float x = (r - phase * 0.42) / 0.055;
	float amp = (1.0 - phase) * (1.0 - phase);
	float slope = -2.0 * x * exp(-x * x) * amp;
	return d / max(r, 1e-4) * slope;
}

void methane_fragment(
	in MethaneV2F i,
	out float4 oColor : COLOUR_OUT
)
{
	float coverage = smoothstep(methaneExtent.z, methaneExtent.w, SAMPLE(wetMask, i.uv).r)
		* saturate(methaneControl.z);
	clip(coverage - 0.004);

	float3 V = safe_normalize(-i.viewPos.xyz);
	float distance = length(i.viewPos.xyz);
	float3 Ng = safe_normalize(i.viewNormal);
	Ng = dot(Ng, V) < 0.0 ? -Ng : Ng;
	float3 U = safe_normalize(i.viewU);
	float3 W = safe_normalize(i.viewV);

	// Ripples: two scrolling layers of the normal map, faded with distance so the
	// far liquid settles into a clean mirror instead of shimmering.
	float2 metres = i.uv * methaneExtent.xy;
	float drift = methaneWaves.w * time;
	float2 uvA = metres / methaneWaves.x + frac(float2(0.81, 0.59) * drift / methaneWaves.x);
	float2 uvB = metres.yx / methaneWaves.y + frac(float2(-0.47, 0.88) * drift / methaneWaves.y);
	float2 nA = SAMPLE(rippleMap, uvA).xy * 2.0 - 1.0;
	float2 nB = SAMPLE(rippleMap, uvB).yx * 2.0 - 1.0;
	float nearFade = saturate(1.0 - distance / max(methaneSurface.w, 1.0));
	float2 slope = (nA + nB) * (0.5 * methaneWaves.z * saturate(methaneControl.w) * (0.25 + 0.75 * nearFade));
	float rings = saturate(methaneControl.x) * nearFade * nearFade;
	slope += (ring_slope(metres, methaneGlint.z, methaneGlint.w, 3.0)
		+ ring_slope(metres + 0.37 * methaneGlint.z, methaneGlint.z * 1.37, methaneGlint.w * 0.83, 11.0)) * rings;
	float3 N = safe_normalize(Ng - U * slope.x - W * slope.y);

	float nDotV = saturate(dot(N, V));
	float k = 1.0 - nDotV;
	float F = methaneSurface.z + (1.0 - methaneSurface.z) * k * k * k * k * k;
	float3 R = reflect(-V, N);

	// The sun as the liquid sees it: light 0, or (methaneSun.w) the low haze sun the
	// director names, so a map lit from overhead still shows the Titan glare.
	float3 hazeSun = safe_normalize(-mul(viewMat, float4(methaneSun.xyz, 0.0)).xyz);
	float3 sunDir = safe_normalize(lerp(safe_normalize(lightPosition[0].xyz), hazeSun, saturate(methaneSun.w)));
	float sunLit = lightCount > 0.5 ? 1.0 : 0.0;

	// Lights: the body takes flat diffuse (the geometric normal), the ripples carry
	// the glints. Light 0 is the sun; its glint follows sunDir.
	float3 diffuse = float3(0.0, 0.0, 0.0);
	float3 glint = float3(0.0, 0.0, 0.0);
	for (int l = 0; l < MAX_LIGHTS; ++l)
	{
		if (l >= int(lightCount))
			break;
		float3 toLight = lightPosition[l].xyz - i.viewPos.xyz * lightPosition[l].w;
		float d = max(length(toLight), 1e-6);
		toLight /= d;
		float attenuation = saturate(1.0 /
			max(lightAttenuation[l].y + d * (lightAttenuation[l].z + d * lightAttenuation[l].w), 1e-6));
		attenuation *= pow(clamp(
			(dot(toLight, safe_normalize(-lightDirection[l].xyz)) - spotLightParams[l].y) /
			max(spotLightParams[l].x - spotLightParams[l].y, 1e-6), 1e-30, 1.0), spotLightParams[l].z);
		diffuse += lightDiffuse[l].rgb * attenuation * saturate(dot(Ng, toLight));
		float3 glintDir = (l == 0) ? sunDir : toLight;
		glint += lightSpecular[l].rgb * attenuation * pow(saturate(dot(R, glintDir)), methaneGlint.x);
	}
	// Warmed like the glare: a glint is the sun seen through the same haze.
	glint *= methaneGlare.rgb * (methaneGlint.y * saturate(F * 8.0));

	// The reflected sky: the fog colour at the horizon rising to the zenith colour,
	// darker below the horizon (ripples can tip a reflection under it), plus the
	// sun's glow through the haze: a wide lobe and a brighter core round sunDir.
	float3 up = safe_normalize(mul(viewMat, float4(0.0, 1.0, 0.0, 0.0)).xyz);
	float h = dot(R, up);
	float3 sky = h >= 0.0 ? lerp(fogColour.rgb * 1.06, methaneSky.rgb, sqrt(h))
	                      : fogColour.rgb * lerp(1.0, 0.55, saturate(-h * 4.0));
	float c = saturate(dot(R, sunDir));
	float glow = pow(c, methaneGlare.a) * 0.7 + pow(c, methaneGlare.a * 6.0) * 1.3;
	sky += lightDiffuse[0].rgb * methaneGlare.rgb * (glow * saturate(methaneControl.y) * sunLit);

	// Premultiplied output (scene_blend one one_minus_src_alpha): rgb is the light the
	// liquid sends to the eye, alpha how much of the sea floor's light it removes.
	// The floor shows through the liquid, darkened along the path (longer at grazing
	// angles, where the reflection takes over anyway).
	float path = 1.0 / max(saturate(dot(Ng, V)), methaneSurface.y);
	float transmit = exp(-methaneBody.a * path);
	float3 scatter = methaneBody.rgb * (sceneAmbient.rgb + diffuse) * (1.0 - transmit);
	float3 colour = (sky * F * methaneSky.a) + scatter * (1.0 - F) + glint;
	float alpha = saturate(1.0 - (1.0 - F) * transmit + luminance(glint) * methaneSurface.x);

	colour *= coverage;
	alpha *= coverage;
	// Fogging a premultiplied layer: lerp toward fogColour * alpha, which with the
	// (already fogged) floor behind it gives exactly lerp(liquid result, fog, f).
	// Fading the whole layer with fog as well lets the floor's own fog (Enhanced's
	// atmosphere included) carry the distance.
	float fog = fog_amount(i.viewPos);
	float keep = 1.0 - 0.5 * fog;
	oColor = float4(lerp(colour, fogColour.rgb * alpha, fog), alpha) * keep;
}
