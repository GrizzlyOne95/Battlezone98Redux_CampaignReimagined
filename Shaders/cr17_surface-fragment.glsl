#version 120

// ISDF Chronicles: OpenGL twin of surface_fragment / surface_caster_fragment
// in cr17_surface.hlsl. Kinds, modifiers, uniforms and texture units are
// documented there; keep the two files in step.

#ifndef MAX_LIGHTS
#define MAX_LIGHTS 8
#endif

#if defined(ICE) || defined(GLASS) || defined(CUTOUT) || defined(LAVA) || defined(WATER) || defined(CHROME) || defined(CRYSTAL)
#if !defined(GLOW) && !defined(CASTER)
#define LIT_SURFACE
#endif
#endif
#if defined(ICE) || defined(GLASS) || defined(CUTOUT)
#define NORMAL_MAPPED
#endif
#if defined(ICE) || defined(GLASS) || defined(WATER) || defined(CRYSTAL)
#define SKY_REFLECTION
#endif

uniform sampler2D diffuseMap;
#if defined(NORMAL_MAPPED) && !defined(GLOW) && !defined(CASTER)
uniform sampler2D normalMap;
uniform sampler2D specularMap;
uniform sampler2D emissiveMap;
#elif defined(HOLO) || (defined(CUTOUT) && defined(GLOW))
uniform sampler2D emissiveMap;
#elif defined(VOLUME) || defined(CRYSTAL)
uniform sampler2D emissiveMap;
#endif
#if defined(SHADOWRECEIVER)
uniform sampler2D shadowMap1;
uniform vec4 invShadowMapSize1;
#if defined(PSSM_ENABLED)
uniform sampler2D shadowMap2;
uniform sampler2D shadowMap3;
uniform vec4 invShadowMapSize2;
uniform vec4 invShadowMapSize3;
uniform vec4 pssmSplitPoints;
#endif
#endif

#if !defined(CASTER)
uniform vec4 fogColour;
uniform vec4 fogParams;
#endif

#if defined(CHROME)
uniform vec4 chromeTint;
uniform vec4 chromeSurface;
uniform vec4 chromeFlow;
#endif

#if defined(LIT_SURFACE)
uniform vec4 sceneAmbient;
uniform float materialShininess;
uniform vec4 lightDiffuse[MAX_LIGHTS];
uniform vec4 lightSpecular[MAX_LIGHTS];
uniform vec4 lightPosition[MAX_LIGHTS];
uniform vec4 lightAttenuation[MAX_LIGHTS];
uniform vec4 spotLightParams[MAX_LIGHTS];
uniform vec4 lightDirection[MAX_LIGHTS];
uniform float lightCount;
#endif

#if defined(SKY_REFLECTION) && !defined(GLOW)
uniform mat4 viewMat;
uniform vec4 skyColour;
#endif

#if defined(WATER) || defined(SHIELD) || defined(HOLO) || defined(LAVA) || defined(SHAFT) || defined(VOLUME) || defined(CRYSTAL) || defined(BUILD) || defined(MOLTEN) || defined(CHROME)
uniform float time;
#endif

#if defined(SHIELD) || defined(HOLO) || defined(LAVA) || defined(SHAFT) || defined(VOLUME) || (defined(CRYSTAL) && defined(GLOW)) || defined(BUILD) || defined(MOLTEN)
uniform float intensity;
#endif

#if defined(SHAFT)
uniform vec4 shaftColour;
uniform vec4 shaftShape;
#endif
#if defined(VOLUME)
uniform vec4 volumeColour;
uniform vec4 volumeMotion;
uniform vec4 volumeShape;
#endif
#if defined(CRYSTAL)
uniform vec4 coreBody;
uniform vec4 coreGlow;
uniform vec4 coreMotion;
uniform vec4 coreOptics;
#endif
#if defined(BUILD)
uniform vec4 buildColour;
uniform vec4 buildScan;
uniform vec4 buildScroll;
uniform vec4 materialColour;
#endif
#if defined(MOLTEN)
uniform vec4 moltenFlow;
uniform vec4 moltenHeat;
uniform vec4 moltenShape;
#endif

#if defined(WATER)
uniform vec4 waterScroll;
uniform vec4 waterScale;
uniform vec4 waterColour;
uniform vec4 waterSurface;
#if defined(STORMWATER)
uniform vec4 stormMud;
uniform vec4 stormFlow;
#endif
#endif

#if defined(ICE)
uniform vec4 iceDeep;
uniform vec4 iceScatter;
uniform vec4 iceRim;
#if defined(TRANSLUCENT)
uniform vec4 iceAlpha;
#endif
#endif

#if defined(GLASS)
uniform vec4 glassTint;
#if defined(TRANSLUCENT)
uniform vec4 glassAlpha;
#endif
#endif

#if defined(SHIELD)
uniform vec4 shieldColour;
uniform vec4 shieldScroll;
uniform vec4 shieldRim;
uniform vec4 shieldPulse;
uniform vec4 shieldBand;
#endif

#if defined(HOLO)
uniform vec4 holoColour;
uniform vec4 holoScan;
uniform vec4 holoRim;
#endif

#if defined(CUTOUT)
uniform vec4 cutoutParams;
#if defined(GLOW)
uniform vec4 glowColour;
#endif
#endif

#if defined(LAVA)
uniform vec4 lavaFlow;
uniform vec4 lavaHeat;
uniform vec4 lavaCrust;
uniform vec4 lavaWarp;
#endif

varying vec2 vTexCoord;
#if defined(CASTER)
varying vec2 vCasterDepth;
#else
varying vec4 vViewPos;
varying vec3 vViewNormal;
varying vec3 vObjPos;
#if defined(PARTICLE_COLOUR)
varying vec4 vParticleColour;
#endif
#if defined(SHADOWRECEIVER)
varying vec4 vLightSpacePos1;
#if defined(PSSM_ENABLED)
varying vec4 vLightSpacePos2;
varying vec4 vLightSpacePos3;
#endif
#endif
#endif

vec3 safe_normalize(vec3 v)
{
	float lenSq = dot(v, v);
	return lenSq > 1e-8 ? v * inversesqrt(lenSq) : vec3(0.0, 0.0, 1.0);
}

float clamp01(float x) { return clamp(x, 0.0, 1.0); }

float luminance(vec3 c)
{
	return dot(c, vec3(0.299, 0.587, 0.114));
}

#if !defined(CASTER)
float fog_amount(float depth)
{
	return clamp((depth - fogParams.y) * fogParams.w, 0.0, 1.0);
}
#endif

float fresnel(float nDotV, float f0)
{
	float k = 1.0 - clamp(nDotV, 0.0, 1.0);
	float k2 = k * k;
	return f0 + (1.0 - f0) * k2 * k2 * k;
}

// Columns T, B, N: tbn * v maps tangent space to view space.
mat3 cotangent_frame(vec3 N, vec3 p, vec2 uv)
{
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);

	vec3 dp2perp = cross(N, dp2);
	vec3 dp1perp = cross(dp1, N);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	float invmax = inversesqrt(max(dot(T, T), dot(B, B)) + 1e-30);
	invmax = dot(dp1, dp2perp) < 0.0 ? -invmax : invmax;
	return mat3(T * invmax, B * invmax, N);
}

vec3 facing_normal(vec3 n, vec3 V)
{
	n = safe_normalize(n);
	return dot(n, V) < 0.0 ? -n : n;
}

#if defined(SKY_REFLECTION) && !defined(GLOW)
vec3 sky_reflection(vec3 R)
{
	vec3 up = safe_normalize((viewMat * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float h = dot(R, up);
	return h >= 0.0 ? mix(fogColour.rgb, skyColour.rgb, sqrt(h))
	                : fogColour.rgb * mix(1.0, 0.3, clamp(-h * 4.0, 0.0, 1.0));
}

#if defined(GLASS)
// See cr17_surface.hlsl glass_sky: the map's sky, darkened toward the zenith.
vec3 glass_sky(vec3 R)
{
	vec3 up = safe_normalize((viewMat * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float h = dot(R, up);
	return h >= 0.0 ? fogColour.rgb * mix(vec3(1.15), skyColour.rgb, sqrt(h))
	                : fogColour.rgb * mix(0.6, 0.15, clamp(-h * 3.0, 0.0, 1.0));
}
#endif
#endif

#if defined(SHADOWRECEIVER)
float PCF_Filter_1(vec4 uv, vec2 invMapSize)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
#if PCF_SIZE > 1
	vec2 pixel = uv.xy / invMapSize - 0.5;
	vec2 c = floor(pixel);
	vec2 f = fract(pixel);
	float s00 = step(uv.z, texture2D(shadowMap1, (c + vec2(0.0, 0.0)) * invMapSize).x);
	float s10 = step(uv.z, texture2D(shadowMap1, (c + vec2(1.0, 0.0)) * invMapSize).x);
	float s01 = step(uv.z, texture2D(shadowMap1, (c + vec2(0.0, 1.0)) * invMapSize).x);
	float s11 = step(uv.z, texture2D(shadowMap1, (c + vec2(1.0, 1.0)) * invMapSize).x);
	return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
#else
	return step(uv.z, texture2D(shadowMap1, uv.xy).x);
#endif
}
#if defined(PSSM_ENABLED)
float PCF_Filter_2(vec4 uv)
{
	uv /= uv.w;
	return step(min(uv.z, 1.0), texture2D(shadowMap2, uv.xy).x);
}
float PCF_Filter_3(vec4 uv)
{
	uv /= uv.w;
	return step(min(uv.z, 1.0), texture2D(shadowMap3, uv.xy).x);
}
#endif

float shadow_term()
{
	float shadow;
#if defined(PSSM_ENABLED)
	if (vViewPos.w <= pssmSplitPoints.y)
		shadow = PCF_Filter_1(vLightSpacePos1, invShadowMapSize1.xy);
	else if (vViewPos.w <= pssmSplitPoints.z)
		shadow = PCF_Filter_2(vLightSpacePos2);
	else
		shadow = PCF_Filter_3(vLightSpacePos3);
#else
	shadow = PCF_Filter_1(vLightSpacePos1, invShadowMapSize1.xy);
#endif
	return shadow * 0.7 + 0.3;
}
#endif

#if defined(LIT_SURFACE)
void accumulate_lights(vec3 viewPos, vec3 N, vec3 V, float shadow,
	float wrap, float transPower,
	out vec3 diffuse, out vec3 specular, out vec3 transmitted)
{
	diffuse = vec3(0.0);
	specular = vec3(0.0);
	transmitted = vec3(0.0);
	vec3 R = reflect(-V, N);

	for (int l = 0; l < MAX_LIGHTS; ++l)
	{
		if (l >= int(lightCount))
			break;

		vec3 toLight = lightPosition[l].xyz - viewPos * lightPosition[l].w;
		float d = max(length(toLight), 1e-6);
		toLight /= d;

		float attenuation = clamp(1.0 /
			max(lightAttenuation[l].y + d * (lightAttenuation[l].z + d * lightAttenuation[l].w), 1e-6), 0.0, 1.0);
		attenuation *= pow(clamp(
			(dot(toLight, safe_normalize(-lightDirection[l].xyz)) - spotLightParams[l].y) /
			max(spotLightParams[l].x - spotLightParams[l].y, 1e-6), 1e-30, 1.0), spotLightParams[l].z);
		attenuation *= (l == 0) ? shadow : 1.0;

		float nDotL = dot(N, toLight);
		float lit = clamp((nDotL + wrap) / (1.0 + wrap), 0.0, 1.0);
		diffuse += lightDiffuse[l].rgb * attenuation * lit;
		specular += lightSpecular[l].rgb * attenuation * clamp(nDotL, 0.0, 1.0) *
			pow(clamp(dot(R, toLight), 0.0, 1.0), materialShininess);
		transmitted += lightDiffuse[l].rgb * attenuation *
			pow(clamp(dot(-V, toLight), 0.0, 1.0), transPower);
	}
}
#endif

void main()
{
#if defined(CASTER)
	if (texture2D(diffuseMap, vTexCoord).a < cutoutParams.x)
		discard;
	float depth = vCasterDepth.x / max(abs(vCasterDepth.y), 1e-6);
	gl_FragData[0] = vec4(depth, depth, depth, 1.0);
#else
	vec2 uv = vTexCoord;
	float fog = fog_amount(vViewPos.w);
	vec3 V = safe_normalize(-vViewPos.xyz);
	float shadow = 1.0;
#if defined(SHADOWRECEIVER)
	shadow = shadow_term();
#endif
	vec4 oColor;

#if defined(SHAFT)
	vec4 t = texture2D(diffuseMap, uv);
	float face = abs(dot(safe_normalize(vViewNormal), V));
	float soft = mix(1.0, sqrt(clamp01(face)), shaftShape.z);
	float pulse = 1.0 + shaftShape.y * sin(time * shaftShape.x);
	float mask = pow(clamp01(t.a), shaftShape.w) * soft;
	vec3 colour = t.rgb * shaftColour.rgb * shaftColour.a * mask * pulse * intensity;
	oColor = vec4(colour * (1.0 - fog), 0.0);

#elif defined(VOLUME)
	vec4 t = texture2D(diffuseMap, uv + fract(vec2(0.17, 0.11) * time * volumeShape.w));
	vec3 e = texture2D(emissiveMap, uv).rgb;
	float face = abs(dot(safe_normalize(vViewNormal), V));
	float edge = pow(clamp01(face), volumeShape.x);
	float mask = pow(clamp01(t.a), volumeShape.y) * edge;
	float wave = sin(time * volumeMotion.x + vObjPos.y * volumeMotion.z - time * volumeMotion.w);
	float pulse = 1.0 + wave * volumeMotion.y;
	vec3 colour = (t.rgb + e * volumeShape.z) * volumeColour.rgb * volumeColour.a * mask * pulse * intensity;
	oColor = vec4(colour * (1.0 - fog), 0.0);

#elif defined(CRYSTAL)
	vec3 N = facing_normal(vViewNormal, V);
	mat3 tbn = cotangent_frame(N, vViewPos.xyz, uv);
	vec3 vt = vec3(dot(tbn[0], V), dot(tbn[1], V), dot(tbn[2], V));
	vec2 innerUV = uv * coreOptics.w - vt.xy / max(abs(vt.z), 0.35) * coreOptics.x
		+ fract(coreMotion.xy * time);
	vec4 outer = texture2D(diffuseMap, uv);
	vec4 inner = texture2D(diffuseMap, innerUV);
	float pulse = 1.0 + coreMotion.w * sin(time * coreMotion.z + vObjPos.y * 0.7);
	vec3 emission = (outer.rgb * outer.a + inner.rgb * inner.a * 0.45
		+ texture2D(emissiveMap, uv).rgb * outer.a) * coreGlow.rgb * coreGlow.a * pulse;
#if defined(GLOW)
	oColor = vec4(emission * intensity * (1.0 - fog), 1.0);
#else
	float F = fresnel(clamp01(dot(N, V)), coreOptics.y);
	vec3 diffuse, specular, transmitted;
	accumulate_lights(vViewPos.xyz, N, V, shadow, 0.15, 1.0, diffuse, specular, transmitted);
	vec3 colour = coreBody.rgb * (sceneAmbient.rgb + diffuse) * coreBody.a
		+ sky_reflection(reflect(-V, N)) * F * skyColour.a
		+ specular * coreOptics.z + emission;
	oColor = vec4(mix(colour, fogColour.rgb, fog), 1.0);
#endif

#elif defined(BUILD)
	vec2 buildUV = uv + fract(buildScroll.xy * time);
	vec4 t = texture2D(diffuseMap, buildUV);
	float sweep = pow(0.5 + 0.5 * sin((vObjPos.y * buildScan.x - time * buildScan.y) * 6.2831853), 12.0);
	float pulse = 1.0 + buildScan.z * sin(time * buildScroll.z);
	float rim = pow(1.0 - abs(dot(safe_normalize(vViewNormal), V)), 2.0);
	float mask = t.a * buildScroll.w * materialColour.a;
	vec3 colour = t.rgb * buildColour.rgb * buildColour.a * mask * pulse
		* (0.5 + sweep + rim * buildScan.w) * intensity;
	oColor = vec4(colour * (1.0 - fog), 0.0);

#elif defined(MOLTEN)
	vec2 flow = fract(moltenFlow.xy * time);
	vec2 warp = (texture2D(diffuseMap, uv * 0.5 - flow).rg - 0.5) * moltenFlow.w;
	vec4 a = texture2D(diffuseMap, uv + flow + warp);
	vec4 b = texture2D(diffuseMap, uv * moltenFlow.z - flow.yx);
	vec3 hot = max(a.rgb, b.rgb);
	float crust = 1.0 - smoothstep(moltenHeat.w - 0.08, moltenHeat.w + 0.08, luminance(hot));
	float pulse = 1.0 + moltenHeat.z * sin(time * moltenHeat.y + vObjPos.y * 0.3);
	// Fragment derivatives supply the normal missing from engine particles.
	vec3 N = facing_normal(cross(dFdx(vViewPos.xyz), dFdy(vViewPos.xyz)), V);
	float face = clamp01(abs(dot(N, V)));
	float mask = pow(clamp01(texture2D(diffuseMap, uv).a), moltenShape.y);
	float opacity = mask * moltenShape.x * vParticleColour.a * mix(1.0, sqrt(face), moltenShape.z);
	vec3 colour = hot * moltenHeat.x * pulse * (1.0 - crust * moltenShape.w) * vParticleColour.rgb * intensity;
	// Premultiplied: puddles use one/inv_src_alpha, droplets use one/one.
	oColor = vec4(colour * opacity * (1.0 - fog), opacity * (1.0 - fog));

#elif defined(CHROME)
	// Spherical baked-environment lookup; keep the mesh's smooth normals.
	vec3 N = facing_normal(vViewNormal, V);
	vec3 R = reflect(-V, N);
	vec3 sphere = R + vec3(0.0, 0.0, 1.0);
	vec2 envUV = vec2(0.5) + vec2(R.x, -R.y) / max(2.0 * length(sphere), 1e-4);
	envUV += sin(vObjPos.xz * chromeFlow.z + time * vec2(0.8, 1.1)) * chromeFlow.w
		+ sin(chromeFlow.xy * time * 6.2831853) * 0.025;
	vec3 env = vec3(0.04) + clamp((texture2D(diffuseMap, envUV).rgb - chromeSurface.z) * chromeSurface.w, 0.0, 1.0);
	float F = fresnel(clamp(dot(N, V), 0.0, 1.0), chromeSurface.x);
	vec3 diffuse, specular, transmitted;
	accumulate_lights(vViewPos.xyz, N, V, shadow, 0.0, 1.0, diffuse, specular, transmitted);
	vec3 colour = chromeTint.rgb * ((sceneAmbient.rgb + diffuse) * chromeSurface.y
		+ env * F * chromeTint.a * (0.65 + 0.35 * shadow)) + specular * F;
	oColor = vec4(mix(colour, fogColour.rgb, fog), 1.0);

#elif defined(WATER)
#if defined(STORMWATER)
	vec2 uvA = uv * waterScale.x + fract(waterScroll.xy * time) + fract(waterScroll.xy * stormFlow.x);
	vec2 uvB = uv.yx * waterScale.y + fract(waterScroll.zw * time) + fract(waterScroll.zw * stormFlow.x);
#else
	vec2 uvA = uv * waterScale.x + fract(waterScroll.xy * time);
	vec2 uvB = uv.yx * waterScale.y + fract(waterScroll.zw * time);
#endif
	vec4 tA = texture2D(diffuseMap, uvA);
	vec4 tB = texture2D(diffuseMap, uvB);
	vec3 albedo = (tA.rgb + tB.rgb) * 0.5 * waterColour.rgb;
	float hA = luminance(tA.rgb);
	float hB = luminance(tB.rgb);
	float foam = smoothstep(0.55, 0.9, (hA + hB) * 0.5) * waterSurface.w;
#if defined(STORMWATER)
	albedo = mix(albedo, stormMud.rgb * (0.65 + 0.7 * (hA + hB) * 0.5), clamp(stormMud.a, 0.0, 1.0));
#endif

#if defined(GLOW)
	oColor = vec4(albedo * waterColour.a * (1.0 - fog), 1.0);
#else
	float o = waterScale.w;
	vec2 gA = vec2(luminance(texture2D(diffuseMap, uvA + vec2(o, 0.0)).rgb) - hA,
	               luminance(texture2D(diffuseMap, uvA + vec2(0.0, o)).rgb) - hA);
	vec2 gB = vec2(luminance(texture2D(diffuseMap, uvB + vec2(o, 0.0)).rgb) - hB,
	               luminance(texture2D(diffuseMap, uvB + vec2(0.0, o)).rgb) - hB);
	vec3 bumpTS = safe_normalize(vec3(-(gA + gB.yx) * waterScale.z, 1.0));

	vec3 Ng = facing_normal(vViewNormal, V);
	mat3 tbn = cotangent_frame(Ng, vViewPos.xyz, uv);
	vec3 N = safe_normalize(tbn * bumpTS);
	float F = fresnel(clamp(dot(N, V), 0.0, 1.0), waterSurface.z);

	vec3 diffuse, specular, transmitted;
	accumulate_lights(vViewPos.xyz, N, V, shadow, 0.3, 1.0, diffuse, specular, transmitted);

	vec3 body = albedo * (sceneAmbient.rgb + diffuse) + albedo * waterColour.a;
	vec3 sky = sky_reflection(reflect(-V, N));
	vec3 colour = mix(body, sky, F * skyColour.a) + specular;
	colour = mix(colour, sceneAmbient.rgb + diffuse, foam);

	float alpha = mix(waterSurface.x, waterSurface.y, F) + luminance(specular) + foam;
#if defined(STORMWATER)
	alpha = mix(alpha, max(alpha, 0.92), clamp(stormMud.a, 0.0, 1.0) * 0.85);
#endif
	oColor = vec4(mix(colour, fogColour.rgb, fog), clamp(alpha, 0.0, 1.0));
#endif

#elif defined(ICE)
	vec3 Ng = facing_normal(vViewNormal, V);
	mat3 tbn = cotangent_frame(Ng, vViewPos.xyz, uv);
	vec3 N = safe_normalize(tbn * (texture2D(normalMap, uv).xyz * 2.0 - 1.0));
	float F = fresnel(clamp(dot(N, V), 0.0, 1.0), iceRim.a);

	vec3 viewTS = vec3(dot(tbn[0], V), dot(tbn[1], V), dot(tbn[2], V));
	vec2 parallax = -viewTS.xy / max(viewTS.z, 0.25) * iceDeep.a;
	vec3 inner = texture2D(diffuseMap, uv + parallax).rgb * iceDeep.rgb;
	vec3 surface = texture2D(diffuseMap, uv).rgb;
	vec3 albedo = mix(inner, surface, clamp(iceScatter.w + F, 0.0, 1.0));

	vec3 diffuse, specular, transmitted;
	accumulate_lights(vViewPos.xyz, N, V, shadow, iceScatter.x, iceScatter.z,
		diffuse, specular, transmitted);

	vec3 colour = albedo * (sceneAmbient.rgb + diffuse)
		+ transmitted * iceScatter.y * iceDeep.rgb * surface
		+ specular * texture2D(specularMap, uv).rgb
		+ sky_reflection(reflect(-V, N)) * iceRim.rgb * F * skyColour.a
		+ texture2D(emissiveMap, uv).rgb;

#if defined(TRANSLUCENT)
	float alpha = clamp(mix(iceAlpha.x, iceAlpha.y, F) + luminance(specular), 0.0, 1.0);
#else
	float alpha = 1.0;
#endif
	oColor = vec4(mix(colour, fogColour.rgb, fog), alpha);

#elif defined(GLASS)
	vec3 Ng = facing_normal(vViewNormal, V);
	mat3 tbn = cotangent_frame(Ng, vViewPos.xyz, uv);
	vec3 N = safe_normalize(tbn * (texture2D(normalMap, uv).xyz * 2.0 - 1.0));
	float F = fresnel(clamp(dot(N, V), 0.0, 1.0), glassTint.a);

	vec3 diffuse, specular, transmitted;
	accumulate_lights(vViewPos.xyz, N, V, shadow, 0.0, 1.0, diffuse, specular, transmitted);

	vec4 tint = texture2D(diffuseMap, uv);
	vec3 specularTex = texture2D(specularMap, uv).rgb;
	vec3 colour = tint.rgb * glassTint.rgb * (sceneAmbient.rgb + diffuse)
		+ glass_sky(reflect(-V, N)) * F * skyColour.a
		+ specular * (0.5 + specularTex)
		+ texture2D(emissiveMap, uv).rgb;

#if defined(TRANSLUCENT)
	float alpha = clamp(mix(glassAlpha.x, glassAlpha.y, F) + luminance(specular), 0.0, 1.0);
#else
	float alpha = 1.0;
#endif
	oColor = vec4(mix(colour, fogColour.rgb, fog), alpha);

#elif defined(SHIELD)
	vec4 a = texture2D(diffuseMap, uv + fract(shieldScroll.xy * time));
	vec4 b = texture2D(diffuseMap, uv * shieldRim.z + fract(shieldScroll.zw * time));
	vec3 pattern = (a.rgb * mix(1.0, a.a, shieldRim.w) + b.rgb * mix(1.0, b.a, shieldRim.w)) * 0.5;

	float nDotV = abs(dot(safe_normalize(vViewNormal), V));
	float rim = pow(1.0 - nDotV, shieldRim.x) * shieldRim.y;
	float band = pow(0.5 + 0.5 * sin(vObjPos.y * shieldPulse.z - time * shieldPulse.w), shieldBand.y);
	float pulse = 1.0 + shieldPulse.y * sin(time * shieldPulse.x);

	vec3 colour = shieldColour.rgb * (pattern * (shieldColour.a + rim) +
		band * shieldBand.x * (0.25 + pattern)) * pulse * intensity;
	oColor = vec4(colour * (1.0 - fog), 1.0);

#elif defined(HOLO)
	vec4 t = texture2D(diffuseMap, uv);
	vec3 e = texture2D(emissiveMap, uv).rgb;
	vec3 base = (t.rgb + e * holoColour.a) * holoColour.rgb;

	const float TWO_PI = 6.2831853;
	float scan = 1.0 - holoScan.z * (0.5 + 0.5 * sin((vObjPos.y * holoScan.x - time * holoScan.y) * TWO_PI));
	float flicker = 1.0 - holoScan.w * (0.5 + 0.5 * sin(time * 41.0) * sin(time * 13.7));
	float sweep = smoothstep(0.92, 1.0, fract(vObjPos.y * holoRim.z - time * 0.35)) * holoRim.w;
	float rim = pow(1.0 - abs(dot(safe_normalize(vViewNormal), V)), holoRim.x) * holoRim.y;

	vec3 colour = base * t.a * scan * flicker * (1.0 + rim + sweep) * intensity;
	oColor = vec4(colour * (1.0 - fog), 1.0);

#elif defined(CUTOUT)
	vec4 diffuseTex = texture2D(diffuseMap, uv);
	vec2 texel = uv * cutoutParams.w;
	vec2 dx = dFdx(texel);
	vec2 dy = dFdy(texel);
	float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	if (diffuseTex.a * (1.0 + mip * 0.25) < cutoutParams.x)
		discard;

#if defined(GLOW)
	oColor = vec4(texture2D(emissiveMap, uv).rgb * glowColour.rgb * (1.0 - fog), 1.0);
#else
	vec3 Ng = facing_normal(vViewNormal, V);
	mat3 tbn = cotangent_frame(Ng, vViewPos.xyz, uv);
	vec3 N = safe_normalize(tbn * (texture2D(normalMap, uv).xyz * 2.0 - 1.0));

	vec3 diffuse, specular, transmitted;
	accumulate_lights(vViewPos.xyz, N, V, shadow, cutoutParams.y, 4.0, diffuse, specular, transmitted);

	vec3 colour = diffuseTex.rgb * (sceneAmbient.rgb + diffuse + transmitted * cutoutParams.z)
		+ specular * texture2D(specularMap, uv).rgb
		+ texture2D(emissiveMap, uv).rgb;
	oColor = vec4(mix(colour, fogColour.rgb, fog), 1.0);
#endif

#elif defined(LAVA)
	vec2 flowB = fract(lavaFlow.zw * time);
	vec2 warp = (texture2D(diffuseMap, uv * 0.5 + flowB).rg - 0.5) * lavaWarp.x;
	vec3 a = texture2D(diffuseMap, uv + fract(lavaFlow.xy * time) + warp).rgb;
	vec3 b = texture2D(diffuseMap, uv * lavaWarp.y + flowB).rgb;
	vec3 hot = max(a, b);
	float heat = luminance(hot);
	float crust = 1.0 - smoothstep(lavaHeat.w - 0.08, lavaHeat.w + 0.08, heat);
	float pulse = 1.0 + lavaHeat.z * sin(time * lavaHeat.y + heat * 6.0);
	vec3 emissive = hot * lavaHeat.x * pulse * (1.0 - crust * lavaCrust.a);

#if defined(GLOW)
	oColor = vec4(emissive * intensity * (1.0 - fog), 1.0);
#else
	vec3 N = facing_normal(vViewNormal, V);
	vec3 diffuse, specular, transmitted;
	accumulate_lights(vViewPos.xyz, N, V, shadow, 0.0, 1.0, diffuse, specular, transmitted);
	vec3 colour = emissive * intensity + lavaCrust.rgb * crust * (sceneAmbient.rgb + diffuse);
	oColor = vec4(mix(colour, fogColour.rgb, fog), 1.0);
#endif
#endif

	gl_FragData[0] = oColor;
#endif
}
