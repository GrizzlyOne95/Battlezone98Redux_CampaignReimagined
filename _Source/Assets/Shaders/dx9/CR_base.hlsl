
#if defined(SHADOWRECEIVER) 
float PCF_Filter(in sampler2D map,
					in float4 uv,
					in float2 invMapSize)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
#if PCF_SIZE > 1
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
#else
	return step(uv.z, tex2D(map, uv.xy).x);
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

// ===============================================================================================
// PBR Helper Functions (Cook-Torrance BRDF) - Adapted for SM3.0
// ===============================================================================================
static const float PI = 3.14159265359;

// Normal Distribution Function (GGX)
float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness*roughness;
    float a2 = a*a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / max(denom, 0.0000001); // avoid divide by zero
}

// Geometry Function (Schlick-GGX)
float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}

// Geometry Function (Smith)
float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// Fresnel Equation (Schlick)
float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}
// ===============================================================================================

void base_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 worldViewMat,
	uniform float4x4 texMatrix, // Added for UV animations

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

	vTexCoord = mul(texMatrix, float4(iTexCoord, 0.0, 1.0)).xy;

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
	// Vertex lighting fallback (keeping original logic for low LODs/fallback if needed)
	// assume light 0 is the sun directional light
	// get the direction from the pixel to the light source
	float3 pixelToLight = normalize(lightPosition[0].xyz - (vViewPosition * lightPosition[0].w));
	
	// accumulate diffuse lighting
	float attenuation = max(dot(vViewNormal, pixelToLight.xyz), 0.0);
	vLightResult = lightDiffuse[0].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// per-pixel view reflection
	float3 viewReflect = reflect(normalize(vViewPosition), vViewNormal);

	// accumulate specular lighting
	attenuation *= pow(max(dot(viewReflect, pixelToLight), 0.0), materialShininess);
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
#if defined(SPECULARMAP_ENABLED) || defined(SPECULAR_ENABLED)
	uniform sampler2D specularMap : register(s2),
#endif
#if defined(EMISSIVEMAP_ENABLED)
	uniform sampler2D emissiveMap : register(s3),
#endif
#if defined(SHADOWRECEIVER) 
	uniform sampler2D shadowMap1 : register(s4),
#if defined(PSSM_ENABLED)
	uniform sampler2D shadowMap2 : register(s5),
	uniform sampler2D shadowMap3 : register(s6),
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
	// Shadow Calculation
#if defined(SHADOWRECEIVER) 
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
	shadow = shadow * 0.7 + 0.3; // Shadow intensity
#else
	float shadow = 1.0;
#endif

	// Sample Diffuse (Albedo)
	float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
	float3 albedo = pow(diffuseTex.rgb, 2.2); // Simple Gamma -> Linear approximation

	// Sample ORM Map (Occlusion, Roughness, Metallic) via Specular Map slot
	// Default values if no map
	float ao = 1.0;
	float roughness = 0.5;
	float metallic = 0.0;

#if defined(SPECULARMAP_ENABLED)
	float4 ormTex = tex2D(specularMap, vTexCoord);
	// Assumption: R=AO, G=Roughness, B=Metallic
	ao = ormTex.r;
	roughness = ormTex.g;
	metallic = ormTex.b;
#endif

#if defined(VERTEX_LIGHTING)
	// Fallback for Vertex Lighting (just use standard output)
	float3 lightResult = vLightResult * shadow + sceneAmbient.xyz;
	float3 finalColor = lightResult * diffuseTex.rgb;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	finalColor += vSpecularResult;
#endif
	oColor.xyz = finalColor; // Non-PBR fallback

#else
	
	// PBR Lighting Calculation
	float3 N = normalize(vViewNormal);
#if defined(NORMALMAP_ENABLED) 
	// ... (existing TBN calculation) ...
#if defined(VERTEX_TANGENTS)
	float3 binormal = cross(vViewTangent, vViewNormal);
	float3x3 tbn = float3x3(vViewTangent, binormal, vViewNormal);
#else
	float3x3 tbn = cotangent_frame(vViewNormal, vViewPosition.xyz, vTexCoord);
#endif
	float3 normalTex = tex2D(normalMap, vTexCoord).xyz * 2.0 - 1.0;
	N = normalize(mul(normalTex.xyz, tbn));
#endif

	float3 V = normalize(-vViewPosition); // View vector

	float3 F0 = float3(0.04, 0.04, 0.04); 
	F0 = lerp(F0, albedo, metallic);

	float3 Lo = float3(0.0, 0.0, 0.0);

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
		// Light Direction & Attenuation
		float3 L = lightPosition[i].xyz - (vViewPosition * lightPosition[i].w);
		float distance = length(L);
		L = normalize(L);
		float3 H = normalize(V + L);

		// Attenuation
		float attenuation = 1.0;
		if (lightPosition[i].w > 0.0) // Point/Spot light
		{
			attenuation = saturate(1.0 / (lightAttenuation[i].y + distance * (lightAttenuation[i].z + distance * lightAttenuation[i].w)));
			
			// Spotlight
			attenuation *= pow(clamp(
				(dot(L, normalize(-lightDirection[i].xyz)) - spotLightParams[i].y) /
				(spotLightParams[i].x - spotLightParams[i].y), 1e-30, 1.0), spotLightParams[i].z);
		}

		if (i == 0) attenuation *= shadow; // Apply shadow to sun/first light

		float3 radiance = lightDiffuse[i].rgb * attenuation; 

		// Cook-Torrance BRDF
		float NDF = DistributionGGX(N, H, roughness);
		float G   = GeometrySmith(N, V, L, roughness);
		float3 F  = FresnelSchlick(max(dot(H, V), 0.0), F0);

		float3 numerator    = NDF * G * F;
		float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
		float3 specular = numerator / denominator;

		float3 kS = F;
		float3 kD = float3(1.0, 1.0, 1.0) - kS;
		kD *= 1.0 - metallic;

		float NdotL = max(dot(N, L), 0.0);
		Lo += (kD * albedo / PI + specular) * radiance * NdotL;
	}
#if MAX_LIGHTS == 1
	}
#endif

	// Ambient Lighting (Simplified IBL approximation)
	float3 ambient = float3(0.03, 0.03, 0.03) * albedo * ao; // Basic ambient
	ambient += sceneAmbient.rgb * albedo * ao; // Add Engine Ambient

	float3 color = ambient + Lo;

	// Emissive
#if defined(EMISSIVEMAP_ENABLED)
	float3 emissive = tex2D(emissiveMap, vTexCoord).rgb;
	color += emissive;
#endif

	// Tonemapping & Gamma Correction
	color = pow(color, 1.0/2.2); // Gamma Correction back to sRGB

	oColor.rgb = color;

#endif // !VERTEX_LIGHTING

	// Fog
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, fogColour.xyz, fogValue);

	// Transparency
	oColor.a = saturate(transparency);

#if defined(LOGDEPTH_ENABLE)
	// logarithmic depth
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
