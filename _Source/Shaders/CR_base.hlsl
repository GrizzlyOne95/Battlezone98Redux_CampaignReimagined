#if defined(SHADOWRECEIVER) 
float PCF_Filter(in sampler2D map,
					in float4 uv,
					in float2 invMapSize)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
	float2 texel = invMapSize;
	float compareDepth = uv.z - (0.0012 + max(texel.x, texel.y) * 1.4);
#if PCF_SIZE == 3
#if defined(HIGH_SHADOW_QUALITY)
	float2 poisson[12] = {
		float2(-0.326, -0.406), float2(-0.840, -0.074), float2(-0.696, 0.457), float2(-0.203, 0.621),
		float2(0.962, -0.195), float2(0.473, -0.480), float2(0.519, 0.767), float2(0.185, -0.893),
		float2(0.507, 0.064), float2(0.896, 0.412), float2(-0.322, -0.933), float2(-0.792, -0.598)
	};
	float sum = 0.0;
	[unroll] for (int i = 0; i < 12; ++i)
	{
		float2 offset = poisson[i] * texel * 1.35;
		sum += step(compareDepth, tex2D(map, uv.xy + offset).x);
	}
	return sum / 12.0;
#else
	float2 pixel = uv.xy / invMapSize - float2(float(PCF_SIZE-1)*0.5, float(PCF_SIZE-1)*0.5);
	float2 c = floor(pixel);
	float2 f = frac(pixel);

	float kernel[PCF_SIZE*PCF_SIZE];
	for (int y = 0; y < PCF_SIZE; ++y)
	{
		for (int x = 0; x < PCF_SIZE; ++x)
		{
			int i = y * PCF_SIZE + x;
			kernel[i] = step(uv.z, tex2D(map, (c + float2(x, y)) * invMapSize).x);
		}
	}

	float4 sum = float4(0.0, 0.0, 0.0, 0.0);
	for (int y = 0; y < PCF_SIZE-1; ++y)
	{
		for (int x = 0; x < PCF_SIZE-1; ++x)
		{
			int i = y * PCF_SIZE + x;
			sum += float4(kernel[i], kernel[i+1], kernel[i+PCF_SIZE], kernel[i+PCF_SIZE+1]);
		}
	}

	return lerp(lerp(sum.x, sum.y, f.x), lerp(sum.z, sum.w, f.x), f.y) / float((PCF_SIZE-1)*(PCF_SIZE-1));
#endif
#elif PCF_SIZE == 2
	float2 pixel = uv.xy / invMapSize - float2(0.5, 0.5);
	float2 c = floor(pixel);
	float2 f = frac(pixel);
	float k00 = step(compareDepth, tex2D(map, (c + float2(0.0, 0.0)) * invMapSize).x);
	float k10 = step(compareDepth, tex2D(map, (c + float2(1.0, 0.0)) * invMapSize).x);
	float k01 = step(compareDepth, tex2D(map, (c + float2(0.0, 1.0)) * invMapSize).x);
	float k11 = step(compareDepth, tex2D(map, (c + float2(1.0, 1.0)) * invMapSize).x);
	return lerp(lerp(k00, k10, f.x), lerp(k01, k11, f.x), f.y);
#else
	return step(compareDepth, tex2D(map, uv.xy).x);
#endif
}
#endif

#if defined(NORMALMAP_ENABLED) && !defined(VERTEX_TANGENTS)
// compute cotangent frame from normal, position, and texcoord
// http://www.thetenthplanet.de/archives/1180
float3x3 cotangent_frame(float3 N, float3 p, float2 uv)
{
	// get edge vectors of the pixel triangle
	float3 dp1 = ddx(p);
	float3 dp2 = ddy(p);
	float2 duv1 = ddx(uv);
	float2 duv2 = ddy(uv);

	// solve the linear system
	float3 dp2perp = cross(N, dp2);
	float3 dp1perp = cross(dp1, N);
	float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	float3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	// construct a scale-invariant frame
	float invmax = rsqrt(max(dot(T, T), dot(B, B)) + 1e-30);
	T *= invmax;
	B *= invmax;
	return float3x3(T, B, N);
}
#endif

float3 subtle_tonemap(float3 c)
{
	// Very light filmic shaping to recover midtones without changing art style.
	float3 t = (c * (1.0 + c / 1.8)) / (1.0 + c);
	return lerp(c, t, 0.10);
}

float3 ibl_sky_from_ambient(float3 ambient)
{
	// View-independent fallback keeps low vertex-lighting permutations stable.
	return ambient * 0.92;
}

float3 fresnel_schlick(float cosTheta, float3 F0)
{
	return F0 + (1.0 - F0) * pow(1.0 - saturate(cosTheta), 5.0);
}

float hash12(float2 p)
{
	return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float smooth_rand_1d(float x, float seed)
{
	float i = floor(x);
	float f = frac(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(float2(i, seed));
	float b = hash12(float2(i + 1.0, seed));
	return lerp(a, b, f);
}

float emissive_anim_factor(
	float2 uv,
	float t,
	float mask,
	float emissiveAnimStrength,
	float emissiveAnimScale)
{
	float strength = saturate(emissiveAnimStrength) * saturate(mask);
	float scale = max(emissiveAnimScale, 0.1);
	float2 gridUv = uv * scale * 2.2;
	float2 cell = floor(gridUv);
	float2 local = frac(gridUv) - 0.5;
	float cellSeed = hash12(cell + float2(19.1, 73.7));
	float cellPhase = hash12(cell + float2(11.7, 5.3)) * 6.2831853;
	float cellSpeed = lerp(0.30, 1.35, hash12(cell + float2(37.2, 29.8)));
	float slowPulse = 0.5 + 0.5 * sin(t * cellSpeed + cellPhase);
	float drift = smooth_rand_1d(t * (0.24 + cellSpeed * 0.18) + cellPhase, 91.0 + cellSeed * 211.0);
	float flicker = smooth_rand_1d(t * (0.75 + cellSpeed * 0.55) + cellPhase * 1.7, 173.0 + cellSeed * 307.0);
	float cellCore = smoothstep(0.72, 0.06, length(local));
	float mod = slowPulse * 0.58 + drift * 0.27 + flicker * 0.15;
	float anim = lerp(0.42, 1.36, mod) * lerp(0.88, 1.10, cellCore);
	anim = saturate(anim);
	return lerp(1.0, anim, strength);
}

void base_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 worldViewMat,

#if defined(SHADOWRECEIVER) 
	uniform float4x4 texWorldViewProj1,
#if defined(PSSM_ENABLED)
	uniform float4x4 texWorldViewProj2,
	uniform float4x4 texWorldViewProj3,
#endif
#endif

#if defined(VERTEX_LIGHTING)
	uniform float4 lightPosition[MAX_LIGHTS],
	uniform float4 lightDiffuse[MAX_LIGHTS],
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	uniform float4 lightSpecular[MAX_LIGHTS],
	uniform float materialShininess,
#endif
#endif

	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	in float3 iNormal : NORMAL,
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 iTangent : TANGENT,
#endif

#if defined (VERTEX_LIGHTING)
	out float3 vLightResult : COLOR0,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	out float3 vSpecularResult : COLOR1,
#endif
#endif

	out float2 vTexCoord : TEXCOORD0,

#if !defined(VERTEX_LIGHTING)
	out float3 vViewNormal : TEXCOORD1,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	out float3 vViewTangent : TEXCOORD2,
#endif
	out float3 vViewPosition : TEXCOORD3,
#endif

	out float vDepth : TEXCOORD4,
#if defined(SHADOWRECEIVER) 
	out float4 vLightSpacePos1 : TEXCOORD5,
#if defined(PSSM_ENABLED)
	out float4 vLightSpacePos2 : TEXCOORD6,
	out float4 vLightSpacePos3 : TEXCOORD7,
#endif
#endif

	out float4 oPosition : POSITION
)
{
	oPosition = mul(wvpMat, iPosition);

	vTexCoord = iTexCoord;

#if defined(VERTEX_LIGHTING)
	float3 vViewPosition, vViewNormal;
#endif
	vViewPosition = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
	vViewNormal = mul(worldViewMat, float4(iNormal.xyz, 0.0)).xyz;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	vViewTangent = mul(worldViewMat, float4(iTangent.xyz, 0.0)).xyz;
#endif

	vDepth = oPosition.z;

#if defined(SHADOWRECEIVER) 
	// calculate vertex position in light space
	vLightSpacePos1 = mul(texWorldViewProj1, iPosition);
#if defined(PSSM_ENABLED)
	vLightSpacePos2 = mul(texWorldViewProj2, iPosition);
	vLightSpacePos3 = mul(texWorldViewProj3, iPosition);
#endif
#endif

#if defined(VERTEX_LIGHTING)
	// assume light 0 is the sun directional light
	// get the direction from the pixel to the light source
	float3 pixelToLight = normalize(lightPosition[0].xyz - (vViewPosition * lightPosition[0].w));
	
	// accumulate diffuse lighting
	float attenuation = max(dot(vViewNormal, pixelToLight.xyz), 0.0);
	vLightResult = lightDiffuse[0].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// accumulate specular lighting
	float3 viewDir = normalize(-vViewPosition);
	float3 halfVec = normalize(pixelToLight + viewDir);
	attenuation *= pow(saturate(dot(vViewNormal, halfVec)), materialShininess);
	vSpecularResult = lightSpecular[0].xyz * attenuation;
#endif
#endif
}

// -------------------------------------------

void base_fragment(
	uniform sampler2D diffuseMap : register(s0),
#if defined(NORMALMAP_ENABLED) 
	uniform sampler2D normalMap : register(s1),
#endif
#if defined(SPECULARMAP_ENABLED)
	uniform sampler2D specularMap : register(s2),
#endif
#if defined(EMISSIVEMAP_ENABLED)
	uniform sampler2D emissiveMap : register(s3),
#endif
	uniform sampler2D glossMap : register(s4),
	uniform sampler2D metallicMap : register(s5),
#if defined(SHADOWRECEIVER) 
	uniform sampler2D shadowMap1 : register(s6),
#if defined(PSSM_ENABLED)
	uniform sampler2D shadowMap2 : register(s7),
	uniform sampler2D shadowMap3 : register(s8),
#endif

	uniform float4 invShadowMapSize1,
#if defined(PSSM_ENABLED)
	uniform float4 invShadowMapSize2,
	uniform float4 invShadowMapSize3,
	uniform float4 pssmSplitPoints,
#endif
#endif

	uniform float4 sceneAmbient,

#if !defined(VERTEX_LIGHTING)
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	uniform float materialShininess,
#endif
	uniform float4 lightDiffuse[MAX_LIGHTS],
	uniform float4 lightPosition[MAX_LIGHTS],
	uniform float4 lightSpecular[MAX_LIGHTS],
	uniform float4 lightAttenuation[MAX_LIGHTS],
	uniform float4 spotLightParams[MAX_LIGHTS],
	uniform float4 lightDirection[MAX_LIGHTS],
	uniform float lightCount,
#endif

	uniform float4 fogColour,
	uniform float4 fogParams,
	uniform float transparency,
	uniform float glossStrength,
	uniform float glossBias,
	uniform float metallicStrength,
	uniform float metallicBias,
	uniform float objectSpecPower,
	uniform float objectAmbientStrength,
	uniform float objectIBLDiffuseStrength,
	uniform float objectIBLSpecStrength,
	uniform float objectNormalStrength,
	uniform float objectDiffuseBoost,
	uniform float objectDiffuseDetailStrength,
	uniform float specAAStrength,
	uniform float wrapDiffuse,
	uniform float rimStrength,
	uniform float rimPower,
	uniform float baseTime,
	uniform float emissiveAnimStrength,
	uniform float emissiveAnimSpeed,
	uniform float emissiveAnimScale,

#if defined (VERTEX_LIGHTING)
	in float3 vLightResult : COLOR0,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	in float3 vSpecularResult : COLOR1,
#endif
#endif
	in float2 vTexCoord : TEXCOORD0,
#if !defined(VERTEX_LIGHTING)
	in float3 vViewNormal : TEXCOORD1,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 vViewTangent : TEXCOORD2,
#endif
	in float3 vViewPosition : TEXCOORD3,
#endif
	in float vDepth : TEXCOORD4,
#if defined(SHADOWRECEIVER) 
	in float4 vLightSpacePos1 : TEXCOORD5,
#if defined(PSSM_ENABLED)
	in float4 vLightSpacePos2 : TEXCOORD6,
	in float4 vLightSpacePos3 : TEXCOORD7,
#endif
#endif

	out float4 oColor : COLOR
#if defined(LOGDEPTH_ENABLE)	
	, out float oDepth : DEPTH
#endif
)
{
	const float kSpecularStrength = 0.50;
	const float kNormalStrength = 3.2;
	const float kDiffuseBoost = 1.32;
	const float kAlbedoDetailStrength = 0.62;
	const float kDarkLift = 0.04;
	const float kFresnelSpecBoost = 0.22;
	const float kSpotDiffuseBoost = 1.12;
	const float kSpotSpecularBoost = 1.22;
	const float kSpotHotspotRolloff = 0.10;
	const float kAOStrength = 0.25;
	const float kAOPower = 1.35;
	const float kIBLDiffuseStrength = 0.34;
	const float kIBLSpecStrength = 0.42;
	const float kExposure = 1.12;
	const float kToneStrength = 0.55;
	const float kRoughnessBias = 0.02;
	const float kMetalnessBias = -0.12;
	const float kSpecularClamp = 1.18;

#if defined(SHADOWRECEIVER)
	// shadow texture
	float shadow;
#if defined(PSSM_ENABLED)
	if (vDepth <= pssmSplitPoints.y)
	{
#endif
		shadow = PCF_Filter(shadowMap1, vLightSpacePos1, invShadowMapSize1.xy);
#if defined(PSSM_ENABLED)
	}
	else if (vDepth <= pssmSplitPoints.z)
	{
		shadow = PCF_Filter(shadowMap2, vLightSpacePos2, invShadowMapSize2.xy);
	}
	else
	{
		shadow = PCF_Filter(shadowMap3, vLightSpacePos3, invShadowMapSize3.xy);
	}
#endif
	shadow = shadow * 0.76 + 0.24;
#endif

#if defined(VERTEX_LIGHTING)

	// combine ambient and shadowed light result
	float3 lightResult = vLightResult;
#if defined(SHADOWRECEIVER)
	lightResult *= shadow;
#endif
	lightResult += sceneAmbient.xyz * objectAmbientStrength;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 specularResult = vSpecularResult;
#endif
	
#else

	// per-pixel view position
	float3 viewPos = vViewPosition;
	float3 viewNormal;

#if defined(NORMALMAP_ENABLED) 
	// tangent basis
#if defined(VERTEX_TANGENTS)
	float3 binormal = cross(vViewTangent, vViewNormal);
	float3x3 tbn = float3x3(vViewTangent, binormal, vViewNormal);
#else
	float3x3 tbn = cotangent_frame(vViewNormal, vViewPosition.xyz, vTexCoord);
#endif

	// per-pixel view normal
	float3 normalTex = tex2D(normalMap, vTexCoord).xyz * 2.0 - 1.0;
	normalTex.xy *= (kNormalStrength * objectNormalStrength);
	normalTex.z = sqrt(saturate(1.0 - dot(normalTex.xy, normalTex.xy)));
	viewNormal = normalize(mul(normalTex.xyz, tbn));
#else
	viewNormal = normalize(vViewNormal);
#endif

	float3 viewDir = normalize(-viewPos);
	float viewFacing = saturate(dot(viewNormal, viewDir));
	float specAAFactor = 1.0;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 dndx = ddx(viewNormal);
	float3 dndy = ddy(viewNormal);
	float normalVariance = saturate((dot(dndx, dndx) + dot(dndy, dndy)) * 0.5);
	specAAFactor = rcp(1.0 + normalVariance * specAAStrength * 8.0);
	float glossForSpec = saturate(tex2D(glossMap, vTexCoord).x * glossStrength + glossBias);
#endif

	// start with ambient light and no specular
	float3 lightResult = sceneAmbient.xyz * objectAmbientStrength;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 specularResult = float3(0,0,0);
#endif

#if MAX_LIGHTS > 1
	// for each possible light source...
	[unroll] for (int i = 0; i < MAX_LIGHTS; ++i)
	{
		if (i >= int(lightCount))
			break;
#else
	{
		const int i = 0;
#endif

		// get the direction from the pixel to the light source
		float3 pixelToLight = lightPosition[i].xyz - (viewPos * lightPosition[i].w);
		float d = length(pixelToLight);
		pixelToLight /= d;

			// compute distance attentuation
			float attenuation = saturate(1.0 / 
				(lightAttenuation[i].y + d * (lightAttenuation[i].z + d * lightAttenuation[i].w)));

			// compute spotlight attenuation
			// it's much faster to just do the math than have a branch on low-end GPUs
			// non-spotlights have falloff power 0 which yields a constant output
			float spotConeAtten = pow(clamp(
				(dot(pixelToLight, -lightDirection[i].xyz) - spotLightParams[i].y) /
				(spotLightParams[i].x - spotLightParams[i].y), 1e-30, 1.0), spotLightParams[i].z);
			float hotspotRolloff = lerp(1.0, 1.0 - kSpotHotspotRolloff, saturate(spotConeAtten * spotConeAtten));
			attenuation *= spotConeAtten * hotspotRolloff;

#if defined(SHADOWRECEIVER) 
			// apply shadow attenuation
			attenuation *= shadow;
#endif

			// accumulate diffuse lighting
			float NdotL = dot(viewNormal, pixelToLight);
			float wrappedNdotL = saturate((NdotL + wrapDiffuse) / max(1.0 + wrapDiffuse, 1e-3));
			wrappedNdotL = saturate(wrappedNdotL * lerp(1.0, kSpotDiffuseBoost, spotConeAtten));
			attenuation *= wrappedNdotL;
			lightResult.xyz += lightDiffuse[i].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
			// accumulate specular lighting
			float3 halfVec = normalize(pixelToLight + viewDir);
			float specNdotH = saturate(dot(viewNormal, halfVec));
			float specPower = max(materialShininess * max(objectSpecPower, 0.2) * lerp(0.65, 1.80, glossForSpec), 1.0);
			attenuation *= pow(specNdotH, specPower) * specAAFactor * lerp(1.0, kSpotSpecularBoost, spotConeAtten);
			specularResult.xyz += lightSpecular[i].xyz * attenuation;
#endif

	}

#endif

	// diffuse texture
	float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
	float diffuseLuma = dot(diffuseTex.xyz, float3(0.299, 0.587, 0.114));
	float3 liftedDiffuse = diffuseTex.xyz + (1.0 - diffuseTex.xyz) * (kDarkLift * (1.0 - diffuseLuma));
	float3 detailedDiffuse = saturate(liftedDiffuse + (liftedDiffuse - diffuseLuma.xxx) * (kAlbedoDetailStrength * objectDiffuseDetailStrength));
	float3 diffuseColor = lerp(liftedDiffuse, detailedDiffuse, 0.65) * (kDiffuseBoost * objectDiffuseBoost);
	oColor.xyz = lightResult.xyz * diffuseColor;

#if defined(EMISSIVEMAP_ENABLED)
	// emissive texture
	float3 emissiveTex = tex2D(emissiveMap, vTexCoord).xyz;
	float emissiveMask = saturate(dot(emissiveTex, float3(0.299, 0.587, 0.114)) * 3.2);
	float emissiveAnim = emissive_anim_factor(vTexCoord, baseTime * emissiveAnimSpeed, emissiveMask, emissiveAnimStrength, max(emissiveAnimScale, 0.1));
	emissiveTex *= emissiveAnim;
#else
	float3 emissiveTex = float3(0, 0, 0);
#endif

#if defined(SPECULARMAP_ENABLED)
	// specular texture
	float3 specularTex = tex2D(specularMap, vTexCoord).xyz;
#else
	float3 specularTex = float3(1, 1, 1);
#endif
	float glossTex = tex2D(glossMap, vTexCoord).x;
	float metallicTex = tex2D(metallicMap, vTexCoord).x;
	float specLuma = dot(specularTex, float3(0.299, 0.587, 0.114));
	float emissiveLuma = dot(emissiveTex, float3(0.299, 0.587, 0.114));
	float derivedGloss = saturate(specLuma * 0.52 + emissiveLuma * 0.03 + diffuseLuma * 0.08);
	float derivedMetallic = saturate(specLuma * 0.22 - emissiveLuma * 0.10 - diffuseLuma * 0.28);
	float glossMapPresence = saturate(glossTex * 4.0);
	float glossBase = lerp(derivedGloss * 0.80, glossTex, glossMapPresence);
	float gloss = saturate(glossBase * glossStrength + glossBias - kRoughnessBias);
	float roughness = saturate(1.0 - gloss);
	roughness = saturate(roughness * roughness);
	float metallicMapPresence = saturate(metallicTex * 4.0);
	float metallicBase = lerp(derivedMetallic * 0.40, metallicTex, metallicMapPresence);
	float metallic = saturate(metallicBase * metallicStrength + metallicBias + kMetalnessBias);
	float ao = lerp(1.0, pow(saturate(diffuseTex.a), kAOPower), kAOStrength);
	float specScale = lerp(0.45, 1.05, gloss);
	float metallicSpecScale = lerp(0.82, 1.12, metallic);
	float fresnelTerm = 0.0;
	float3 fresnelColor = float3(1.0, 1.0, 1.0);
	float rimTerm = 0.0;
	float3 baseF0 = float3(0.04, 0.04, 0.04);
#if !defined(VERTEX_LIGHTING)
	float3 dielectricF0 = float3(0.04, 0.04, 0.04);
	float3 metalTint = saturate(lerp(diffuseColor, specularTex, 0.75));
	baseF0 = lerp(dielectricF0, metalTint, metallic);
	baseF0 = saturate(min(baseF0, 0.92));
	fresnelColor = fresnel_schlick(viewFacing, baseF0);
	fresnelTerm = max(max(fresnelColor.r, fresnelColor.g), fresnelColor.b);
	rimTerm = pow(1.0 - viewFacing, max(rimPower, 0.01)) * rimStrength;
#endif
	float3 diffuseEnergy = saturate((1.0 - fresnelColor) * lerp(1.0, 0.55, metallic));
	diffuseEnergy = max(diffuseEnergy, 0.18.xxx);
	oColor.xyz *= diffuseEnergy * lerp(1.0, 0.84, metallic) * ao;
	oColor.xyz += diffuseColor * rimTerm * 0.18;
	float3 iblDiffuse = sceneAmbient.xyz * diffuseColor * diffuseEnergy * (kIBLDiffuseStrength * objectIBLDiffuseStrength * ao);
	float3 iblSky = ibl_sky_from_ambient(sceneAmbient.xyz);
	float3 iblSpec = iblSky * fresnelColor * lerp(0.15, 1.0, 1.0 - roughness) * (kIBLSpecStrength * objectIBLSpecStrength * ao);
	oColor.xyz += iblDiffuse + iblSpec * specularTex;
	// Keep gloss uniforms active for low-feature permutations where specular is compiled out.
	oColor.xyz *= (1.0 + (gloss + objectSpecPower + objectAmbientStrength + objectIBLDiffuseStrength + objectIBLSpecStrength + objectNormalStrength + objectDiffuseBoost + objectDiffuseDetailStrength + specAAStrength + wrapDiffuse + rimStrength + rimPower + emissiveAnimStrength + emissiveAnimSpeed + emissiveAnimScale) * 1e-6);

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	oColor.xyz += specularResult.xyz * saturate(specularTex.xyz) * kSpecularStrength * specScale * metallicSpecScale * (1.0 + fresnelTerm * kFresnelSpecBoost) * fresnelColor;
#endif
	oColor.xyz = min(oColor.xyz, kSpecularClamp.xxx);

#if defined(EMISSIVEMAP_ENABLED)
	oColor.xyz += emissiveTex.xyz;
#endif

	float3 exposedColor = oColor.xyz * kExposure;
	oColor.xyz = lerp(exposedColor, subtle_tonemap(exposedColor), kToneStrength);

	// fog
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, fogColour.xyz, fogValue);

	// output alpha
	//oColor.a = diffuseTex.a;
	oColor.a = saturate(transparency);

#if defined(LOGDEPTH_ENABLE)
	// logarithmic depth
	const float C = 0.1;
	const float offset = 1.0;
	const float kInvLogDepthDenom = 0.054286812;
	oDepth = log(C * vDepth + offset) * kInvLogDepthDenom;
#endif
}
