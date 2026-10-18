// ISDF Chronicles: surface shaders for materials the stock BZBase program
// cannot express - water, ice, glass, energy shields, holograms, alpha-tested
// fences and foliage, and lava. Generated bindings: tools/surfacegen.py writes
// cr17_surface.program and cr17_surface.material from this file's variants.
//
// One source for both D3D paths: the HLSL4 delegates compile it with SM4=1 for
// vs_4_0/ps_4_0 (DX11), the HLSL delegates without it for vs_3_0/ps_3_0 (DX9).
// cr17_surface-vertex.glsl / cr17_surface-fragment.glsl are the OpenGL twin
// and must stay in step with this file.
//
// Conventions follow the stock base-sm4.hlsl / base.hlsl programs so these
// surfaces sit in the same scene as BZBase meshes:
//   - lighting is the stock per-pixel loop over light_position_view_space_array
//     (distance and spotlight attenuation, derived light colours, light_count);
//   - fog is saturate((depth - fogParams.y) * fogParams.w) on clip-space z;
//   - shadow receiving uses the stock PSSM layout: shadow maps in units 4-6,
//     the same split points and the same 0.7/0.3 shadow floor;
//   - normal maps use the stock cotangent frame, since CR17 meshes carry no
//     tangents (every mesh has POSITION, NORMAL, TEXCOORD0 - nothing more is
//     read, as D3D11 rejects a shader input the vertex data lacks).
//
// Kinds (fragment defines), each with its own uniforms below:
//   WATER   two scrolling layers of the diffuse map, a normal derived from
//           their luminance, Fresnel reflection of the sky, sun glints,
//           Fresnel-driven opacity, optional foam and self-illumination.
//   ICE     lit ice: normal and specular maps, a parallax-offset inner layer
//           for depth, wrapped diffuse and back-light transmission for
//           scattering, a Fresnel sky rim. TRANSLUCENT makes it alpha-blended.
//   GLASS   lit tinted glass: Fresnel sky reflection over the diffuse tint,
//           tight specular. TRANSLUCENT makes it see-through.
//   SHIELD  unlit additive energy field: two scrolling layers, Fresnel rim,
//           pulse and a sweeping band in object space.
//   HOLO    unlit additive hologram: texture alpha as the mask, object-space
//           scanlines, flicker, rim and a rising sweep.
//   CUTOUT  lit alpha-tested surface (fences, foliage): stock lighting plus
//           clip() on texture alpha, mip-compensated so thin wires and leaves
//           survive at distance, two-sided, optional wrap/back-light.
//   LAVA    flowing emissive lava: warped scrolling layers, heat pulse, and a
//           cooled crust that takes scene lighting.
// Modifiers: SHADOWRECEIVER, PSSM_ENABLED, PCF_SIZE, GLOW (the glow-scheme
// pass: emissive contribution only, fog fades to black), TRANSLUCENT.

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

// Which inputs each kind reads. Uniforms are declared only where a variant
// reads them: the compiler strips unread ones, and a default_params entry for
// a stripped uniform is an error.
#if defined(ICE) || defined(GLASS) || defined(CUTOUT) || defined(LAVA) || defined(WATER) || defined(CHROME) || defined(CRYSTAL)
#if !defined(GLOW)
#define LIT_SURFACE
#endif
#endif
#if defined(ICE) || defined(GLASS) || defined(CUTOUT)
#define NORMAL_MAPPED
#endif
#if defined(ICE) || defined(GLASS) || defined(WATER) || defined(CRYSTAL)
#define SKY_REFLECTION
#endif

// ---------------------------------------------------------------------------
// Vertex

float4x4 wvpMat;
float4x4 worldViewMat;
#if defined(PARTICLE_COLOUR)
float4x4 texMatrix;
#endif
#if defined(SHADOWRECEIVER)
float4x4 texWorldViewProj1;
#if defined(PSSM_ENABLED)
float4x4 texWorldViewProj2;
float4x4 texWorldViewProj3;
#endif
#endif

struct SurfaceV2F
{
	float2 uv : TEXCOORD0;
	float4 viewPos : TEXCOORD1;    // xyz view-space position, w fog depth
	float3 viewNormal : TEXCOORD2;
	float3 objPos : TEXCOORD3;     // object-space position (scanlines, bands)
#if defined(PARTICLE_COLOUR)
	float4 particleColour : COLOR0;
#endif
#if defined(SHADOWRECEIVER)
	float4 lightSpacePos1 : TEXCOORD4;
#if defined(PSSM_ENABLED)
	float4 lightSpacePos2 : TEXCOORD5;
	float4 lightSpacePos3 : TEXCOORD6;
#endif
#endif
};

void surface_vertex(
	in float4 iPosition : POSITION,
#if defined(PARTICLE_COLOUR)
	in float4 iColour : COLOR0,
#else
	in float3 iNormal : NORMAL,
#endif
	in float2 iTexCoord : TEXCOORD0,

	out SurfaceV2F o,
	out float4 oPosition : POSITION_OUT
)
{
	oPosition = mul(wvpMat, iPosition);
	o.uv = iTexCoord;
	o.viewPos.xyz = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
	o.viewPos.w = oPosition.z;
#if defined(PARTICLE_COLOUR)
	// Engine draw_sphere/draw_planar have colour and UVs, but no normals.
	o.uv = mul(texMatrix, float4(iTexCoord, 0.0, 1.0)).xy;
	o.viewNormal = float3(0.0, 0.0, 1.0);
#if defined(SM4)
	o.particleColour = iColour.bgra;
#else
	o.particleColour = iColour;
#endif
#else
	o.viewNormal = mul(worldViewMat, float4(iNormal, 0.0)).xyz;
#endif
	o.objPos = iPosition.xyz;
#if defined(SHADOWRECEIVER)
	o.lightSpacePos1 = mul(texWorldViewProj1, iPosition);
#if defined(PSSM_ENABLED)
	o.lightSpacePos2 = mul(texWorldViewProj2, iPosition);
	o.lightSpacePos3 = mul(texWorldViewProj3, iPosition);
#endif
#endif
}

// Shadow caster for alpha-tested surfaces: the stock caster
// (DepthShadowmap-sm4.hlsl casterVP/casterFP) plus the diffuse-alpha test,
// so fences and leaves cast their shape rather than their quads.
float4 texelOffsets;

void surface_caster_vertex(
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,

	out float2 vTexCoord : TEXCOORD0,
	out float2 vDepth : TEXCOORD1,
	out float4 oPosition : POSITION_OUT
)
{
	oPosition = mul(wvpMat, iPosition);
	oPosition.xy += texelOffsets.zw * oPosition.w;
	vTexCoord = iTexCoord;
	vDepth = oPosition.zw;
}

// ---------------------------------------------------------------------------
// Fragment: shared inputs

// Texture units: the lit kinds keep the stock BZBase layout (0 diffuse,
// 1 normal, 2 specular, 3 emissive, 4-6 shadow maps); hologram and the
// cutout glow pass read an emissive map from unit 1; the rest read unit 0.
DECLARE_MAP(diffuseMap, 0)
#if defined(NORMAL_MAPPED) && !defined(GLOW)
DECLARE_MAP(normalMap, 1)
DECLARE_MAP(specularMap, 2)
DECLARE_MAP(emissiveMap, 3)
#elif defined(HOLO) || (defined(CUTOUT) && defined(GLOW))
DECLARE_MAP(emissiveMap, 1)
#elif defined(VOLUME)
DECLARE_MAP(emissiveMap, 1)
#elif defined(CRYSTAL)
DECLARE_MAP(emissiveMap, 3)
#endif
#if defined(SHADOWRECEIVER)
DECLARE_MAP(shadowMap1, 4)
float4 invShadowMapSize1;
#if defined(PSSM_ENABLED)
DECLARE_MAP(shadowMap2, 5)
DECLARE_MAP(shadowMap3, 6)
float4 invShadowMapSize2;
float4 invShadowMapSize3;
float4 pssmSplitPoints;
#endif
#endif

float4 fogColour;
float4 fogParams;

#if defined(CHROME)
float4 chromeTint;      // rgb: metal tint, a: reflection strength
float4 chromeSurface;   // x: metal Fresnel F0, y: diffuse weight, z: reflection black point, w: contrast
float4 chromeFlow;      // reflection drift XY, ripple frequency, ripple amplitude (zero on metal)
#endif

#if defined(LIT_SURFACE)
float4 sceneAmbient;
float materialShininess;
float4 lightDiffuse[MAX_LIGHTS];
float4 lightSpecular[MAX_LIGHTS];
float4 lightPosition[MAX_LIGHTS];
float4 lightAttenuation[MAX_LIGHTS];
float4 spotLightParams[MAX_LIGHTS];
float4 lightDirection[MAX_LIGHTS];
float lightCount;
#endif

#if defined(SKY_REFLECTION) && !defined(GLOW)
float4x4 viewMat;
float4 skyColour;       // rgb: zenith colour of the reflected sky, a: reflection strength
#endif

#if defined(WATER) || defined(SHIELD) || defined(HOLO) || defined(LAVA) || defined(SHAFT) || defined(VOLUME) || defined(CRYSTAL) || defined(BUILD) || defined(MOLTEN) || defined(CHROME)
float time;
#endif

#if defined(SHIELD) || defined(HOLO) || defined(LAVA) || defined(SHAFT) || defined(VOLUME) || (defined(CRYSTAL) && defined(GLOW)) || defined(BUILD) || defined(MOLTEN)
float intensity;        // 1 in the colour pass, $glow in the glow pass
#endif

#if defined(SHAFT)
float4 shaftColour;     // RGB tint, emission strength
float4 shaftShape;      // pulse rate, pulse depth, grazing softness, alpha exponent
#endif
#if defined(VOLUME)
float4 volumeColour;    // RGB tint, emission strength
float4 volumeMotion;    // pulse rate, pulse depth, object-space wave frequency, speed
float4 volumeShape;     // edge exponent, alpha exponent, emissive weight, UV drift
#endif
#if defined(CRYSTAL)
float4 coreBody;        // RGB crystal body, diffuse weight
float4 coreGlow;        // RGB crack tint, emission strength
float4 coreMotion;      // UV drift XY, pulse rate, pulse depth
float4 coreOptics;      // parallax depth, Fresnel F0, specular strength, inner-layer tiling
#endif
#if defined(BUILD)
float4 buildColour;     // RGB scan tint, intensity
float4 buildScan;       // scan spacing per object unit, speed, pulse depth, edge boost
float4 buildScroll;     // UV drift XY, pulse rate, opacity
float4 materialColour;  // surface_diffuse_colour: preserves engine construction fade
#endif
#if defined(MOLTEN)
float4 moltenFlow;      // UV flow XY, secondary tiling, distortion strength
float4 moltenHeat;      // emission, pulse rate, pulse depth, crust threshold
float4 moltenShape;     // opacity, mask exponent, edge softness, cool-crust weight
#endif

#if defined(WATER)
float4 waterScroll;     // xy: layer A scroll (UV/s), zw: layer B scroll
float4 waterScale;      // x: layer A tiling, y: layer B tiling, z: bump strength, w: bump sample offset (UV)
float4 waterColour;     // rgb: tint on the texture, a: self-illumination
float4 waterSurface;    // x: alpha facing the camera, y: alpha at grazing angles, z: Fresnel F0, w: foam
#endif

#if defined(ICE)
float4 iceDeep;         // rgb: tint of the inner layer, a: its parallax depth (UV)
float4 iceScatter;      // x: diffuse wrap, y: back-light transmission, z: transmission tightness, w: surface layer weight
float4 iceRim;          // rgb: rim tint, a: Fresnel F0
#if defined(TRANSLUCENT)
float4 iceAlpha;        // x: alpha facing the camera, y: alpha at grazing angles
#endif
#endif

#if defined(GLASS)
float4 glassTint;       // rgb: tint multiplied into the diffuse map, a: Fresnel F0
#if defined(TRANSLUCENT)
float4 glassAlpha;      // x: alpha facing the camera, y: alpha at grazing angles
#endif
#endif

#if defined(SHIELD)
float4 shieldColour;    // rgb: tint, a: facing (core) strength
float4 shieldScroll;    // xy: layer A scroll (UV/s), zw: layer B scroll
float4 shieldRim;       // x: rim power, y: rim strength, z: layer B tiling, w: texture alpha as mask (0-1)
float4 shieldPulse;     // x: pulse rate (rad/s), y: pulse depth, z: band frequency (per object unit), w: band speed
float4 shieldBand;      // x: band strength, y: band sharpness
#endif

#if defined(HOLO)
float4 holoColour;      // rgb: tint, a: emissive-map weight
float4 holoScan;        // x: scanlines per object unit, y: scan speed, z: scanline depth, w: flicker depth
float4 holoRim;         // x: rim power, y: rim strength, z: sweep frequency (per object unit), w: sweep strength
#endif

#if defined(CUTOUT)
float4 cutoutParams;    // x: alpha cutoff, y: diffuse wrap, z: back-light transmission, w: diffuse map size (texels)
#if defined(GLOW)
float4 glowColour;      // surface_diffuse_colour of the glow pass ($glow)
#endif
#endif

#if defined(LAVA)
float4 lavaFlow;        // xy: layer A scroll (UV/s), zw: layer B scroll
float4 lavaHeat;        // x: emissive strength, y: pulse rate (rad/s), z: pulse depth, w: crust threshold (luminance)
float4 lavaCrust;       // rgb: crust colour, a: crust darkening (0-1)
float4 lavaWarp;        // x: warp strength (UV), y: layer B tiling
#endif

// ---------------------------------------------------------------------------
// Fragment: helpers

float3 safe_normalize(float3 v)
{
	float lenSq = dot(v, v);
	return lenSq > 1e-8 ? v * rsqrt(lenSq) : float3(0.0, 0.0, 1.0);
}

float luminance(float3 c)
{
	return dot(c, float3(0.299, 0.587, 0.114));
}

float fog_amount(float depth)
{
	return saturate((depth - fogParams.y) * fogParams.w);
}

float fresnel(float nDotV, float f0)
{
	float k = 1.0 - saturate(nDotV);
	float k2 = k * k;
	return f0 + (1.0 - f0) * k2 * k2 * k;
}

// Cotangent frame from derivatives, as the stock base program builds it, but
// with the sign of the screen-space determinant restored: the stock form
// drops it, so its frame flips wherever screen y runs the other way (GL
// window vs. render target). With the sign kept, every path lights normal
// maps the way stock D3D does.
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

// Geometric normal turned toward the viewer, so double-sided surfaces
// (water sheets, fences, leaves, shields) light and reflect correctly from
// behind. Uses the view vector rather than VFACE, whose sign convention
// differs between the D3D9, D3D11 and GL paths.
float3 facing_normal(float3 n, float3 V)
{
	n = safe_normalize(n);
	return dot(n, V) < 0.0 ? -n : n;
}

#if defined(SKY_REFLECTION) && !defined(GLOW)
// Sky seen in a reflection: the fog colour at the horizon (BZ98R skies fade
// into the fog colour) rising to skyColour overhead, and below the horizon
// the ground, a darkened fog colour, so curved glass and ice show a horizon.
float3 sky_reflection(float3 R)
{
	float3 up = safe_normalize(mul(viewMat, float4(0.0, 1.0, 0.0, 0.0)).xyz);
	float h = dot(R, up);
	return h >= 0.0 ? lerp(fogColour.rgb, skyColour.rgb, sqrt(h))
	                : fogColour.rgb * lerp(1.0, 0.3, saturate(-h * 4.0));
}

#if defined(GLASS)
// Glass mirrors the map's own sky: the horizon is the fog colour, and
// skyColour.rgb tints it toward the zenith, so a canopy reflects a dark orange
// dome on Titan and a deeper blue one on an Earth-like map, not a fixed sky.
float3 glass_sky(float3 R)
{
	float3 up = safe_normalize(mul(viewMat, float4(0.0, 1.0, 0.0, 0.0)).xyz);
	float h = dot(R, up);
	return h >= 0.0 ? fogColour.rgb * lerp(float3(1.15, 1.15, 1.15), skyColour.rgb, sqrt(h))
	                : fogColour.rgb * lerp(0.6, 0.15, saturate(-h * 3.0));
}
#endif
#endif

#if defined(SHADOWRECEIVER)
float PCF_Filter_1(float4 uv, float2 invMapSize)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
#if PCF_SIZE > 1
	float2 pixel = uv.xy / invMapSize - 0.5;
	float2 c = floor(pixel);
	float2 f = frac(pixel);
	float s00 = step(uv.z, SAMPLE_LOD0(shadowMap1, (c + float2(0.0, 0.0)) * invMapSize).x);
	float s10 = step(uv.z, SAMPLE_LOD0(shadowMap1, (c + float2(1.0, 0.0)) * invMapSize).x);
	float s01 = step(uv.z, SAMPLE_LOD0(shadowMap1, (c + float2(0.0, 1.0)) * invMapSize).x);
	float s11 = step(uv.z, SAMPLE_LOD0(shadowMap1, (c + float2(1.0, 1.0)) * invMapSize).x);
	return lerp(lerp(s00, s10, f.x), lerp(s01, s11, f.x), f.y);
#else
	return step(uv.z, SAMPLE_LOD0(shadowMap1, uv.xy).x);
#endif
}
#if defined(PSSM_ENABLED)
float PCF_Filter_2(float4 uv, float2 invMapSize)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
	return step(uv.z, SAMPLE_LOD0(shadowMap2, uv.xy).x);
}
float PCF_Filter_3(float4 uv, float2 invMapSize)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
	return step(uv.z, SAMPLE_LOD0(shadowMap3, uv.xy).x);
}
#endif

float shadow_term(SurfaceV2F i)
{
	float shadow;
#if defined(PSSM_ENABLED)
	if (i.viewPos.w <= pssmSplitPoints.y)
		shadow = PCF_Filter_1(i.lightSpacePos1, invShadowMapSize1.xy);
	else if (i.viewPos.w <= pssmSplitPoints.z)
		shadow = PCF_Filter_2(i.lightSpacePos2, invShadowMapSize2.xy);
	else
		shadow = PCF_Filter_3(i.lightSpacePos3, invShadowMapSize3.xy);
#else
	shadow = PCF_Filter_1(i.lightSpacePos1, invShadowMapSize1.xy);
#endif
	return shadow * 0.7 + 0.3;
}
#endif

#if defined(LIT_SURFACE)
// The stock per-pixel light loop. wrap > 0 softens the terminator (ice,
// leaves); transmission adds light arriving from behind the surface along the
// view direction, raised to transPower. Light 0 is the sun and the only one
// the shadow map attenuates, as in the stock program.
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
		float lit = saturate((nDotL + wrap) / (1.0 + wrap));
		diffuse += lightDiffuse[l].rgb * attenuation * lit;
		specular += lightSpecular[l].rgb * attenuation * saturate(nDotL) *
			pow(saturate(dot(R, toLight)), materialShininess);
		transmitted += lightDiffuse[l].rgb * attenuation *
			pow(saturate(dot(-V, toLight)), transPower);
	}
}
#endif

// ---------------------------------------------------------------------------
// Fragment: kinds

void surface_fragment(
	in SurfaceV2F i,
	out float4 oColor : COLOUR_OUT
)
{
	float fog = fog_amount(i.viewPos.w);
	float3 V = safe_normalize(-i.viewPos.xyz);
	float shadow = 1.0;
#if defined(SHADOWRECEIVER)
	shadow = shadow_term(i);
#endif

#if defined(SHAFT)
	float4 t = SAMPLE(diffuseMap, i.uv);
	float face = abs(dot(safe_normalize(i.viewNormal), V));
	float soft = lerp(1.0, sqrt(saturate(face)), shaftShape.z);
	float pulse = 1.0 + shaftShape.y * sin(time * shaftShape.x);
	float mask = pow(saturate(t.a), shaftShape.w) * soft;
	float3 colour = t.rgb * shaftColour.rgb * shaftColour.a * mask * pulse * intensity;
	oColor = float4(colour * (1.0 - fog), 0.0);

#elif defined(VOLUME)
	float4 t = SAMPLE(diffuseMap, i.uv + frac(float2(0.17, 0.11) * time * volumeShape.w));
	float3 e = SAMPLE(emissiveMap, i.uv).rgb;
	float face = abs(dot(safe_normalize(i.viewNormal), V));
	float edge = pow(saturate(face), volumeShape.x);
	float mask = pow(saturate(t.a), volumeShape.y) * edge;
	float wave = sin(time * volumeMotion.x + i.objPos.y * volumeMotion.z - time * volumeMotion.w);
	float pulse = 1.0 + wave * volumeMotion.y;
	float3 colour = (t.rgb + e * volumeShape.z) * volumeColour.rgb * volumeColour.a * mask * pulse * intensity;
	oColor = float4(colour * (1.0 - fog), 0.0);

#elif defined(CRYSTAL)
	float3 N = facing_normal(i.viewNormal, V);
	float3x3 tbn = cotangent_frame(N, i.viewPos.xyz, i.uv);
	float3 vt = mul(tbn, V);
	float2 innerUV = i.uv * coreOptics.w - vt.xy / max(abs(vt.z), 0.35) * coreOptics.x
		+ frac(coreMotion.xy * time);
	float4 outer = SAMPLE(diffuseMap, i.uv);
	float4 inner = SAMPLE(diffuseMap, innerUV);
	float pulse = 1.0 + coreMotion.w * sin(time * coreMotion.z + i.objPos.y * 0.7);
	float3 emission = (outer.rgb * outer.a + inner.rgb * inner.a * 0.45
		+ SAMPLE(emissiveMap, i.uv).rgb * outer.a) * coreGlow.rgb * coreGlow.a * pulse;
#if defined(GLOW)
	oColor = float4(emission * intensity * (1.0 - fog), 1.0);
#else
	float F = fresnel(saturate(dot(N, V)), coreOptics.y);
	float3 diffuse, specular, transmitted;
	accumulate_lights(i.viewPos.xyz, N, V, shadow, 0.15, 1.0, diffuse, specular, transmitted);
	float3 colour = coreBody.rgb * (sceneAmbient.rgb + diffuse) * coreBody.a
		+ sky_reflection(reflect(-V, N)) * F * skyColour.a
		+ specular * coreOptics.z + emission;
	oColor = float4(lerp(colour, fogColour.rgb, fog), 1.0);
#endif

#elif defined(BUILD)
	float2 uv = i.uv + frac(buildScroll.xy * time);
	float4 t = SAMPLE(diffuseMap, uv);
	float sweep = pow(0.5 + 0.5 * sin((i.objPos.y * buildScan.x - time * buildScan.y) * 6.2831853), 12.0);
	float pulse = 1.0 + buildScan.z * sin(time * buildScroll.z);
	float rim = pow(1.0 - abs(dot(safe_normalize(i.viewNormal), V)), 2.0);
	float mask = t.a * buildScroll.w * materialColour.a;
	float3 colour = t.rgb * buildColour.rgb * buildColour.a * mask * pulse
		* (0.5 + sweep + rim * buildScan.w) * intensity;
	oColor = float4(colour * (1.0 - fog), 0.0);

#elif defined(MOLTEN)
	float2 flow = frac(moltenFlow.xy * time);
	float2 warp = (SAMPLE(diffuseMap, i.uv * 0.5 - flow).rg - 0.5) * moltenFlow.w;
	float4 a = SAMPLE(diffuseMap, i.uv + flow + warp);
	float4 b = SAMPLE(diffuseMap, i.uv * moltenFlow.z - flow.yx);
	float3 hot = max(a.rgb, b.rgb);
	float crust = 1.0 - smoothstep(moltenHeat.w - 0.08, moltenHeat.w + 0.08, luminance(hot));
	float pulse = 1.0 + moltenHeat.z * sin(time * moltenHeat.y + i.objPos.y * 0.3);
	// Fragment derivatives supply the normal missing from engine particles.
	float3 N = facing_normal(cross(ddx(i.viewPos.xyz), ddy(i.viewPos.xyz)), V);
	float face = saturate(abs(dot(N, V)));
	float mask = pow(saturate(SAMPLE(diffuseMap, i.uv).a), moltenShape.y);
	float opacity = mask * moltenShape.x * i.particleColour.a * lerp(1.0, sqrt(face), moltenShape.z);
	float3 colour = hot * moltenHeat.x * pulse * (1.0 - crust * moltenShape.w) * i.particleColour.rgb * intensity;
	// Premultiplied: puddles use one/inv_src_alpha, droplets use one/one.
	oColor = float4(colour * opacity * (1.0 - fog), opacity * (1.0 - fog));

#elif defined(CHROME)
	// The CC chrome texture is a baked environment, not a diffuse UV texture.
	// Interpolated mesh normals keep the metal smooth; a black normal map
	// would instead tilt every normal. No tangents or normal map are needed.
	float3 N = facing_normal(i.viewNormal, V);
	float3 R = reflect(-V, N);
	float3 sphere = R + float3(0.0, 0.0, 1.0);
	float2 envUV = float2(0.5, 0.5) + float2(R.x, -R.y) /
		max(2.0 * length(sphere), 1e-4);
	envUV += sin(i.objPos.xz * chromeFlow.z + time * float2(0.8, 1.1)) * chromeFlow.w
		+ sin(chromeFlow.xy * time * 6.2831853) * 0.025;
	float3 env = 0.04 + saturate((SAMPLE(diffuseMap, envUV).rgb - chromeSurface.z) * chromeSurface.w);
	float F = fresnel(saturate(dot(N, V)), chromeSurface.x);
	float3 diffuse, specular, transmitted;
	accumulate_lights(i.viewPos.xyz, N, V, shadow, 0.0, 1.0, diffuse, specular, transmitted);
	float3 colour = chromeTint.rgb * ((sceneAmbient.rgb + diffuse) * chromeSurface.y
		+ env * F * chromeTint.a * (0.65 + 0.35 * shadow)) + specular * F;
	oColor = float4(lerp(colour, fogColour.rgb, fog), 1.0);

#elif defined(WATER)
	float2 uvA = i.uv * waterScale.x + frac(waterScroll.xy * time);
	float2 uvB = i.uv.yx * waterScale.y + frac(waterScroll.zw * time);
	float4 tA = SAMPLE(diffuseMap, uvA);
	float4 tB = SAMPLE(diffuseMap, uvB);
	float3 albedo = (tA.rgb + tB.rgb) * 0.5 * waterColour.rgb;
	float hA = luminance(tA.rgb);
	float hB = luminance(tB.rgb);
	float foam = smoothstep(0.55, 0.9, (hA + hB) * 0.5) * waterSurface.w;

#if defined(GLOW)
	oColor = float4(albedo * waterColour.a * (1.0 - fog), 1.0);
#else
	// Height from luminance: brighter water texels read as crests.
	float o = waterScale.w;
	float2 gA = float2(luminance(SAMPLE(diffuseMap, uvA + float2(o, 0.0)).rgb) - hA,
	                   luminance(SAMPLE(diffuseMap, uvA + float2(0.0, o)).rgb) - hA);
	float2 gB = float2(luminance(SAMPLE(diffuseMap, uvB + float2(o, 0.0)).rgb) - hB,
	                   luminance(SAMPLE(diffuseMap, uvB + float2(0.0, o)).rgb) - hB);
	float3 bumpTS = safe_normalize(float3(-(gA + gB.yx) * waterScale.z, 1.0));

	float3 Ng = facing_normal(i.viewNormal, V);
	float3x3 tbn = cotangent_frame(Ng, i.viewPos.xyz, i.uv);
	float3 N = safe_normalize(mul(bumpTS, tbn));
	float nDotV = saturate(dot(N, V));
	float F = fresnel(nDotV, waterSurface.z);

	float3 diffuse, specular, transmitted;
	accumulate_lights(i.viewPos.xyz, N, V, shadow, 0.3, 1.0, diffuse, specular, transmitted);

	float3 body = albedo * (sceneAmbient.rgb + diffuse) + albedo * waterColour.a;
	float3 sky = sky_reflection(reflect(-V, N));
	float3 colour = lerp(body, sky, F * skyColour.a) + specular;
	colour = lerp(colour, sceneAmbient.rgb + diffuse, foam);

	float alpha = lerp(waterSurface.x, waterSurface.y, F) + luminance(specular) + foam;
	oColor = float4(lerp(colour, fogColour.rgb, fog), saturate(alpha));
#endif

#elif defined(ICE)
	float3 Ng = facing_normal(i.viewNormal, V);
	float3x3 tbn = cotangent_frame(Ng, i.viewPos.xyz, i.uv);
	float3 N = safe_normalize(mul(SAMPLE(normalMap, i.uv).xyz * 2.0 - 1.0, tbn));
	float nDotV = saturate(dot(N, V));
	float F = fresnel(nDotV, iceRim.a);

	// Inner layer: the same texture seen deeper along the view ray, tinted.
	float3 viewTS = mul(tbn, V);
	float2 parallax = -viewTS.xy / max(viewTS.z, 0.25) * iceDeep.a;
	float3 inner = SAMPLE(diffuseMap, i.uv + parallax).rgb * iceDeep.rgb;
	float3 surface = SAMPLE(diffuseMap, i.uv).rgb;
	float3 albedo = lerp(inner, surface, saturate(iceScatter.w + F));

	float3 diffuse, specular, transmitted;
	accumulate_lights(i.viewPos.xyz, N, V, shadow, iceScatter.x, iceScatter.z,
		diffuse, specular, transmitted);

	float3 colour = albedo * (sceneAmbient.rgb + diffuse)
		+ transmitted * iceScatter.y * iceDeep.rgb * surface
		+ specular * SAMPLE(specularMap, i.uv).rgb
		+ sky_reflection(reflect(-V, N)) * iceRim.rgb * F * skyColour.a
		+ SAMPLE(emissiveMap, i.uv).rgb;

#if defined(TRANSLUCENT)
	float alpha = saturate(lerp(iceAlpha.x, iceAlpha.y, F) + luminance(specular));
#else
	float alpha = 1.0;
#endif
	oColor = float4(lerp(colour, fogColour.rgb, fog), alpha);

#elif defined(GLASS)
	float3 Ng = facing_normal(i.viewNormal, V);
	float3x3 tbn = cotangent_frame(Ng, i.viewPos.xyz, i.uv);
	float3 N = safe_normalize(mul(SAMPLE(normalMap, i.uv).xyz * 2.0 - 1.0, tbn));
	float F = fresnel(saturate(dot(N, V)), glassTint.a);

	float3 diffuse, specular, transmitted;
	accumulate_lights(i.viewPos.xyz, N, V, shadow, 0.0, 1.0, diffuse, specular, transmitted);

	float4 tint = SAMPLE(diffuseMap, i.uv);
	float3 specularTex = SAMPLE(specularMap, i.uv).rgb;
	// The specular map shades the glint but never removes it: glass always
	// catches the sun.
	float3 colour = tint.rgb * glassTint.rgb * (sceneAmbient.rgb + diffuse)
		+ glass_sky(reflect(-V, N)) * F * skyColour.a
		+ specular * (0.5 + specularTex)
		+ SAMPLE(emissiveMap, i.uv).rgb;

#if defined(TRANSLUCENT)
	float alpha = saturate(lerp(glassAlpha.x, glassAlpha.y, F) + luminance(specular));
#else
	float alpha = 1.0;
#endif
	oColor = float4(lerp(colour, fogColour.rgb, fog), alpha);

#elif defined(SHIELD)
	float4 a = SAMPLE(diffuseMap, i.uv + frac(shieldScroll.xy * time));
	float4 b = SAMPLE(diffuseMap, i.uv * shieldRim.z + frac(shieldScroll.zw * time));
	float3 pattern = (a.rgb * lerp(1.0, a.a, shieldRim.w) + b.rgb * lerp(1.0, b.a, shieldRim.w)) * 0.5;

	float nDotV = abs(dot(safe_normalize(i.viewNormal), V));
	float rim = pow(1.0 - nDotV, shieldRim.x) * shieldRim.y;
	float band = pow(0.5 + 0.5 * sin(i.objPos.y * shieldPulse.z - time * shieldPulse.w), shieldBand.y);
	float pulse = 1.0 + shieldPulse.y * sin(time * shieldPulse.x);

	float3 colour = shieldColour.rgb * (pattern * (shieldColour.a + rim) +
		band * shieldBand.x * (0.25 + pattern)) * pulse * intensity;
	oColor = float4(colour * (1.0 - fog), 1.0);

#elif defined(HOLO)
	float4 t = SAMPLE(diffuseMap, i.uv);
	float3 e = SAMPLE(emissiveMap, i.uv).rgb;
	float3 base = (t.rgb + e * holoColour.a) * holoColour.rgb;

	const float TWO_PI = 6.2831853;
	float scan = 1.0 - holoScan.z * (0.5 + 0.5 * sin((i.objPos.y * holoScan.x - time * holoScan.y) * TWO_PI));
	float flicker = 1.0 - holoScan.w * (0.5 + 0.5 * sin(time * 41.0) * sin(time * 13.7));
	float sweep = smoothstep(0.92, 1.0, frac(i.objPos.y * holoRim.z - time * 0.35)) * holoRim.w;
	float rim = pow(1.0 - abs(dot(safe_normalize(i.viewNormal), V)), holoRim.x) * holoRim.y;

	float3 colour = base * t.a * scan * flicker * (1.0 + rim + sweep) * intensity;
	oColor = float4(colour * (1.0 - fog), 1.0);

#elif defined(CUTOUT)
	float4 diffuseTex = SAMPLE(diffuseMap, i.uv);
	// Mip-compensated alpha: coarser mips average wire and leaf alpha toward
	// zero, so scale it up with the mip level to keep coverage at distance.
	float2 texel = i.uv * cutoutParams.w;
	float2 dx = ddx(texel);
	float2 dy = ddy(texel);
	float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	clip(diffuseTex.a * (1.0 + mip * 0.25) - cutoutParams.x);

#if defined(GLOW)
	oColor = float4(SAMPLE(emissiveMap, i.uv).rgb * glowColour.rgb * (1.0 - fog), 1.0);
#else
	float3 Ng = facing_normal(i.viewNormal, V);
	float3x3 tbn = cotangent_frame(Ng, i.viewPos.xyz, i.uv);
	float3 N = safe_normalize(mul(SAMPLE(normalMap, i.uv).xyz * 2.0 - 1.0, tbn));

	float3 diffuse, specular, transmitted;
	accumulate_lights(i.viewPos.xyz, N, V, shadow, cutoutParams.y, 4.0, diffuse, specular, transmitted);

	float3 colour = diffuseTex.rgb * (sceneAmbient.rgb + diffuse + transmitted * cutoutParams.z)
		+ specular * SAMPLE(specularMap, i.uv).rgb
		+ SAMPLE(emissiveMap, i.uv).rgb;
	oColor = float4(lerp(colour, fogColour.rgb, fog), 1.0);
#endif

#elif defined(LAVA)
	float2 flowB = frac(lavaFlow.zw * time);
	float2 warp = (SAMPLE(diffuseMap, i.uv * 0.5 + flowB).rg - 0.5) * lavaWarp.x;
	float3 a = SAMPLE(diffuseMap, i.uv + frac(lavaFlow.xy * time) + warp).rgb;
	float3 b = SAMPLE(diffuseMap, i.uv * lavaWarp.y + flowB).rgb;
	float3 hot = max(a, b);
	float heat = luminance(hot);
	float crust = 1.0 - smoothstep(lavaHeat.w - 0.08, lavaHeat.w + 0.08, heat);
	float pulse = 1.0 + lavaHeat.z * sin(time * lavaHeat.y + heat * 6.0);
	float3 emissive = hot * lavaHeat.x * pulse * (1.0 - crust * lavaCrust.a);

#if defined(GLOW)
	oColor = float4(emissive * intensity * (1.0 - fog), 1.0);
#else
	float3 N = facing_normal(i.viewNormal, V);
	float3 diffuse, specular, transmitted;
	accumulate_lights(i.viewPos.xyz, N, V, shadow, 0.0, 1.0, diffuse, specular, transmitted);
	float3 colour = emissive * intensity + lavaCrust.rgb * crust * (sceneAmbient.rgb + diffuse);
	oColor = float4(lerp(colour, fogColour.rgb, fog), 1.0);
#endif
#endif
}

// Alpha-tested shadow caster (see surface_caster_vertex).
#if defined(CUTOUT)
void surface_caster_fragment(
	in float2 vTexCoord : TEXCOORD0,
	in float2 vDepth : TEXCOORD1,
	out float4 oColor : COLOUR_OUT
)
{
	clip(SAMPLE(diffuseMap, vTexCoord).a - cutoutParams.x);
	float depth = vDepth.x / max(abs(vDepth.y), 1e-6);
	oColor = float4(depth, depth, depth, 1.0);
}
#endif
