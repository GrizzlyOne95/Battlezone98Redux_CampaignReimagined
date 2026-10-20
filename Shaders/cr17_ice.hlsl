// Campaign Reimagined: misn17 (Achilles) shore ice (Shaders/cr17_ice.program,
// Materials/cr17_ice.material).
//
// The render-only shelves cr17_islab1-6 (Tools/Build-Misn17Forest.py) lie flat at the
// waterline. This shader fakes half-melted, wet, semi-transparent ice without any
// refraction or scene read-back:
//
//   - thickness: the builder bakes it into vertex colour alpha (1 in the middle of a
//     slab, 0 at its plan outline). Only alpha is read, and alpha sits in the same
//     byte of a packed ARGB or ABGR colour, so no per-backend swizzle is needed. The
//     slab meshes carry that colour element; nothing else may use this program, since
//     D3D11 rejects a shader input the vertex data lacks;
//   - melt: an alpha test erodes the thin outer band where a world-space noise (two
//     octaves of the ice texture's luminance) is high, so every slab gets its own
//     ragged edge, and a darker, glossier wet rim runs just inside the cut;
//   - Fresnel: looking straight down, thin ice shows mostly the dark water colour
//     beneath it (iceDeep) and is partly transparent; at grazing angles it turns to a
//     reflection of the map's sky and to full opacity;
//   - wet film: a slowly scrolling, low-amplitude world-space normal on top of the
//     ice's own normal map, under a sharp, strong sun specular;
//   - tint: cool blue-white, with a subsurface glow when looking toward the sun
//     through thin ice.
//
// Blending stays thin: the core is opaque (alpha 1), only the eroded edge band is
// partly transparent, and the pass writes depth, so the transparent water sheet
// (sorted with it in the main render queue) never draws over the ice and the ice
// never vanishes behind it. Under the thin rim the water may be hidden or blended
// depending on sort order; the rim is a few centimetres to decimetres wide.
//
// Conventions follow cr17_surface.hlsl: the stock per-pixel light loop over
// light_position_view_space_array (light 0 is the sun and the only one the shadow
// map attenuates), the stock linear fog on clip-space depth, the stock PSSM layout
// with the 0.7/0.3 shadow floor, and the cotangent frame for the normal map.
//
// One source for both D3D paths: the HLSL4 delegates compile it with SM4=1 for
// vs_4_0/ps_4_0 (DX11), the HLSL delegates without it for vs_3_0/ps_3_0 (DX9).
// There is no GLSL twin: on OpenGL, or wherever these programs fail to compile, the
// material falls through to an opaque lit-ice technique built from cr17_surface.
// Tools/Test-IceShader.ps1 compiles every delegate and checks the parameters.

#if defined(SM4)
#define DECLARE_MAP(name, reg) Texture2D name : register(t##reg); SamplerState name##Sam : register(s##reg);
#define SAMPLE(name, uv) name.Sample(name##Sam, uv)
#define SAMPLE_LOD0(name, uv) name.SampleLevel(name##Sam, uv, 0)
#define POSITION_OUT SV_POSITION
#define COLOUR_OUT SV_TARGET
#else
#define DECLARE_MAP(name, reg) sampler2D name : register(s##reg);
#define SAMPLE(name, uv) tex2D(name, uv)
#define SAMPLE_LOD0(name, uv) tex2Dlod(name, float4(uv, 0.0, 0.0))
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
float4x4 worldMat;
#if defined(SHADOWRECEIVER)
float4x4 texWorldViewProj1;
float4x4 texWorldViewProj2;
float4x4 texWorldViewProj3;
#endif

struct IceV2F
{
	float2 uv : TEXCOORD0;
	float4 viewPos : TEXCOORD1;    // xyz view-space position, w fog depth
	float3 viewNormal : TEXCOORD2;
	float4 worldPos : TEXCOORD3;   // xyz world position (noise, film), w thickness
#if defined(SHADOWRECEIVER)
	float4 lightSpacePos1 : TEXCOORD4;
	float4 lightSpacePos2 : TEXCOORD5;
	float4 lightSpacePos3 : TEXCOORD6;
#endif
};

void ice_vertex(
	in float4 iPosition : POSITION,
	in float3 iNormal : NORMAL,
	in float4 iColour : COLOR0,
	in float2 iTexCoord : TEXCOORD0,

	out IceV2F o,
	out float4 oPosition : POSITION_OUT
)
{
	oPosition = mul(wvpMat, iPosition);
	o.uv = iTexCoord;
	o.viewPos.xyz = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
	o.viewPos.w = oPosition.z;
	o.viewNormal = mul(worldViewMat, float4(iNormal, 0.0)).xyz;
	// StaticGeometry vertices are in region space; worldMat is the region's, so
	// this is the world position either way.
	o.worldPos.xyz = mul(worldMat, iPosition).xyz;
	o.worldPos.w = iColour.a;
#if defined(SHADOWRECEIVER)
	o.lightSpacePos1 = mul(texWorldViewProj1, iPosition);
	o.lightSpacePos2 = mul(texWorldViewProj2, iPosition);
	o.lightSpacePos3 = mul(texWorldViewProj3, iPosition);
#endif
}

// ---------------------------------------------------------------------------
// Fragment

// Units: 0 diffuse, 1 normal, 2 specular, 3-5 shadow maps.
DECLARE_MAP(diffuseMap, 0)
DECLARE_MAP(normalMap, 1)
DECLARE_MAP(specularMap, 2)
#if defined(SHADOWRECEIVER)
DECLARE_MAP(shadowMap1, 3)
DECLARE_MAP(shadowMap2, 4)
DECLARE_MAP(shadowMap3, 5)
float4 invShadowMapSize1;
float4 pssmSplitPoints;
#endif

float4 fogColour;
float4 fogParams;
float4x4 viewMat;
float time;

float4 sceneAmbient;
float materialShininess;
float4 lightDiffuse[MAX_LIGHTS];
float4 lightSpecular[MAX_LIGHTS];
float4 lightPosition[MAX_LIGHTS];
float4 lightAttenuation[MAX_LIGHTS];
float4 spotLightParams[MAX_LIGHTS];
float4 lightDirection[MAX_LIGHTS];
float lightCount;

float4 iceTint;     // rgb: body tint on the texture, a: how far thin ice shows what lies under it
float4 iceDeep;     // rgb: colour seen through the ice (the water beneath), a: normal-map strength
float4 iceOptics;   // x: Fresnel F0, y: specular strength, z: sky reflection, w: subsurface glow
float4 iceSky;      // rgb: reflected zenith colour, a: unused
float4 iceNoise;    // x: mean ice-texture luminance, y: noise contrast about it
float4 iceMelt;     // x: noise tiling (1/m), y: erosion depth (thickness units), z: wet rim width, w: rim brightness
float4 iceFilm;     // xy: film drift (m/s), z: film tiling (1/m), w: film slope
float4 iceAlpha;    // x: alpha of the thinnest ice facing the camera, y: grazing gain, z: thickness of full opacity, w: clip level

float3 safe_normalize(float3 v)
{
	return v * rsqrt(max(dot(v, v), 1e-12));
}

float luminance(float3 c)
{
	return dot(c, float3(0.299, 0.587, 0.114));
}

float fresnel(float nDotV, float f0)
{
	float k = 1.0 - saturate(nDotV);
	float k2 = k * k;
	return f0 + (1.0 - f0) * k2 * k2 * k;
}

// As cr17_surface.hlsl: derivative cotangent frame with the determinant sign kept.
float3x3 cotangent_frame(float3 N, float3 p, float2 uv)
{
	float3 dp1 = ddx(p);
	float3 dp2 = ddy(p);
	float2 duv1 = ddx(uv);
	float2 duv2 = ddy(uv);

	float3 dp2perp = cross(N, dp2);
	float3 dp1perp = cross(dp1, N);
	float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	float3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	float invmax = rsqrt(max(dot(T, T), dot(B, B)) + 1e-30);
	invmax = dot(dp1, dp2perp) < 0.0 ? -invmax : invmax;
	return float3x3(T * invmax, B * invmax, N);
}

float3 facing_normal(float3 n, float3 V)
{
	n = safe_normalize(n);
	return dot(n, V) < 0.0 ? -n : n;
}

// The map's sky in a reflection: the fog colour at the horizon rising to iceSky
// overhead, a darkened fog colour below it (cr17_surface's sky_reflection).
float3 sky_reflection(float3 R)
{
	float3 up = safe_normalize(mul(viewMat, float4(0.0, 1.0, 0.0, 0.0)).xyz);
	float h = dot(R, up);
	return h >= 0.0 ? lerp(fogColour.rgb, iceSky.rgb, sqrt(h))
	                : fogColour.rgb * lerp(1.0, 0.3, saturate(-h * 4.0));
}

#if defined(SHADOWRECEIVER)
float shadow_sample1(float4 uv)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
	float2 pixel = uv.xy / invShadowMapSize1.xy - 0.5;
	float2 c = floor(pixel);
	float2 f = frac(pixel);
	float s00 = step(uv.z, SAMPLE_LOD0(shadowMap1, (c + float2(0.0, 0.0)) * invShadowMapSize1.xy).x);
	float s10 = step(uv.z, SAMPLE_LOD0(shadowMap1, (c + float2(1.0, 0.0)) * invShadowMapSize1.xy).x);
	float s01 = step(uv.z, SAMPLE_LOD0(shadowMap1, (c + float2(0.0, 1.0)) * invShadowMapSize1.xy).x);
	float s11 = step(uv.z, SAMPLE_LOD0(shadowMap1, (c + float2(1.0, 1.0)) * invShadowMapSize1.xy).x);
	return lerp(lerp(s00, s10, f.x), lerp(s01, s11, f.x), f.y);
}
float shadow_sample2(float4 uv)
{
	uv /= uv.w;
	return step(min(uv.z, 1.0), SAMPLE_LOD0(shadowMap2, uv.xy).x);
}
float shadow_sample3(float4 uv)
{
	uv /= uv.w;
	return step(min(uv.z, 1.0), SAMPLE_LOD0(shadowMap3, uv.xy).x);
}
float shadow_term(IceV2F i)
{
	float shadow;
	if (i.viewPos.w <= pssmSplitPoints.y)
		shadow = shadow_sample1(i.lightSpacePos1);
	else if (i.viewPos.w <= pssmSplitPoints.z)
		shadow = shadow_sample2(i.lightSpacePos2);
	else
		shadow = shadow_sample3(i.lightSpacePos3);
	return shadow * 0.7 + 0.3;
}
#endif

// The stock light loop (cr17_surface's accumulate_lights): wrapped diffuse, Phong
// specular, and light arriving from behind the ice along the view ray.
void accumulate_lights(float3 viewPos, float3 N, float3 V, float shadow,
	float wrap, float transPower,
	out float3 diffuse, out float3 specular, out float3 transmitted)
{
	diffuse = float3(0.0, 0.0, 0.0);
	specular = float3(0.0, 0.0, 0.0);
	transmitted = float3(0.0, 0.0, 0.0);
	float3 R = reflect(-V, N);

	for (int l = 0; l < MAX_LIGHTS; ++l)
	{
		if (l >= int(lightCount))
			break;

		float3 toLight = lightPosition[l].xyz - viewPos * lightPosition[l].w;
		float d = max(length(toLight), 1e-6);
		toLight /= d;

		float attenuation = saturate(1.0 /
			max(lightAttenuation[l].y + d * (lightAttenuation[l].z + d * lightAttenuation[l].w), 1e-6));
		attenuation *= pow(clamp(
			(dot(toLight, safe_normalize(-lightDirection[l].xyz)) - spotLightParams[l].y) /
			max(spotLightParams[l].x - spotLightParams[l].y, 1e-6), 1e-30, 1.0), spotLightParams[l].z);
		attenuation *= (l == 0) ? shadow : 1.0;

		float nDotL = dot(N, toLight);
		diffuse += lightDiffuse[l].rgb * attenuation * saturate((nDotL + wrap) / (1.0 + wrap));
		specular += lightSpecular[l].rgb * attenuation * saturate(nDotL * 4.0) *
			pow(saturate(dot(R, toLight)), materialShininess);
		transmitted += lightDiffuse[l].rgb * attenuation *
			pow(saturate(dot(-V, toLight)), transPower);
	}
}

void ice_fragment(
	in IceV2F i,
	out float4 oColor : COLOUR_OUT
)
{
	float thick = saturate(i.worldPos.w);
	float2 wxz = i.worldPos.xz;

	// Melt: erode the thin band where the noise is high, keep the middle whole.
	// The ice texture is pale and flat (luminance about 0.83 +- 0.07), so stretch it.
	float n = 0.65 * luminance(SAMPLE(diffuseMap, wxz * iceMelt.x).rgb)
	        + 0.35 * luminance(SAMPLE(diffuseMap, wxz * (iceMelt.x * 2.7) + float2(0.37, 0.61)).rgb);
	n = saturate((n - iceNoise.x) * iceNoise.y + 0.5);
	float melt = thick - iceMelt.y * n;
	clip(melt - iceAlpha.w);
	float rim = 1.0 - smoothstep(0.0, iceMelt.z, melt - iceAlpha.w);

	float fog = saturate((i.viewPos.w - fogParams.y) * fogParams.w);
	float3 V = safe_normalize(-i.viewPos.xyz);
	float shadow = 1.0;
#if defined(SHADOWRECEIVER)
	shadow = shadow_term(i);
#endif

	// Normal: the ice's own map, then a drifting wet film in world space.
	float3 Ng = facing_normal(i.viewNormal, V);
	float3x3 tbn = cotangent_frame(Ng, i.viewPos.xyz, i.uv);
	float3 nTS = SAMPLE(normalMap, i.uv).xyz * 2.0 - 1.0;
	nTS.xy *= iceDeep.a;
	float3 N = safe_normalize(mul(nTS, tbn));
	float2 fa = SAMPLE(normalMap, wxz * iceFilm.z + frac(iceFilm.xy * time)).xy * 2.0 - 1.0;
	float2 fb = SAMPLE(normalMap, wxz.yx * (iceFilm.z * 1.31) - frac(iceFilm.yx * time * 0.7)).xy * 2.0 - 1.0;
	float2 film = (fa + fb) * iceFilm.w * (1.0 + rim);
	N = safe_normalize(N + mul((float3x3)viewMat, float3(film.x, 0.0, film.y)));

	float nDotV = saturate(dot(N, V));
	float F = fresnel(nDotV, iceOptics.x);

	float3 diffuse, specular, transmitted;
	accumulate_lights(i.viewPos.xyz, N, V, shadow, 0.35, 6.0, diffuse, specular, transmitted);

	float4 tex = SAMPLE(diffuseMap, i.uv);
	float3 lit = sceneAmbient.rgb + diffuse;
	float3 body = tex.rgb * iceTint.rgb * lit;
	// Looking down through thin ice: the dark water under it, lit dimly.
	float thin = 1.0 - smoothstep(0.0, iceAlpha.z, thick);
	float3 under = iceDeep.rgb * (sceneAmbient.rgb + diffuse * 0.4);
	float3 colour = lerp(body, under, saturate((1.0 - F) * iceTint.a * (0.35 + 0.65 * thin)));
	// Wet rim: darker meltwater over the edge.
	colour *= lerp(1.0, iceMelt.w, rim);
	colour += transmitted * iceTint.rgb * iceOptics.w * (0.35 + 0.65 * thin) * tex.rgb;
	colour += sky_reflection(reflect(-V, N)) * F * iceOptics.z;
	float3 spec = specular * iceOptics.y * (0.6 + 0.4 * SAMPLE(specularMap, i.uv).r) * (1.0 + rim);
	colour += spec;

	float alpha = lerp(iceAlpha.x, 1.0, 1.0 - thin);
	alpha = lerp(alpha, 1.0, saturate(F * iceAlpha.y)) + luminance(spec);
	alpha *= lerp(1.0, 0.8, rim);

	oColor = float4(lerp(colour, fogColour.rgb, fog), saturate(alpha));
}
