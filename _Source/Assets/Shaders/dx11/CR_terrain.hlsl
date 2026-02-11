// ... [Identical preamble to terrain-pbr.hlsl until Fragment Shader] ...
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

// ===============================================================================================
// PBR Helper Functions (Cook-Torrance BRDF) - SM3.0 Compatible
// ===============================================================================================
static const float PI = 3.14159265359;

float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness*roughness;
    float a2 = a*a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / max(denom, 0.0000001);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}
// ===============================================================================================

void terrain_vertex(
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

	in float4 iPosition : POSITION0,
	in float4 iBlendIndices : BLENDINDICES, 
	in float4 iColor : COLOR0,
	in float heightOffset : TEXCOORD1,

	out float4 vColor : COLOR0,
#if defined (VERTEX_LIGHTING)
	out float3 vLightResult : COLOR1,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	out float3 vSpecularResult : COLOR2,
#endif
#endif
	out float2 vTexCoord : TEXCOORD0,
#if !defined(VERTEX_LIGHTING)
	out float3 vViewNormal : TEXCOORD2,
	out float3 vViewTangent : TEXCOORD3, 
	out float3 vViewPosition : TEXCOORD4,
#endif
	out float vDepth : TEXCOORD5,
#if defined(SHADOWRECEIVER)
	out float4 vLightSpacePos1 : TEXCOORD6,
#if defined(PSSM_ENABLED)
	out float4 vLightSpacePos2 : TEXCOORD7,
	out float4 vLightSpacePos3 : TEXCOORD8,
#endif
#endif

	out float4 oPosition : POSITION
)
{
	iPosition.y = heightOffset;
	float2 nNormal = (iBlendIndices.zw - 127.0) / 127.0; 
	float3 iNormal = float3(nNormal.x, sqrt(1.0 - nNormal.x*nNormal.x - nNormal.y*nNormal.y), nNormal.y);

	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iBlendIndices.xy / 160.0;

#if defined(VERTEX_LIGHTING)
	float3 vViewPosition, vViewNormal;
#endif
	vViewPosition = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
	vViewNormal = mul(worldViewMat, float4(iNormal.xyz, 0.0)).xyz;

    float3 worldTangent = normalize(cross(iNormal, float3(0,0,1)));
    if (abs(dot(iNormal, float3(0,0,1))) > 0.99)
         worldTangent = float3(1,0,0);
         
#if !defined(VERTEX_LIGHTING)
	vViewTangent = mul(worldViewMat, float4(worldTangent, 0.0)).xyz;
#endif

	vDepth = oPosition.z;
	vColor = iColor; 
	
#if defined(SHADOWRECEIVER)
	vLightSpacePos1 = mul(texWorldViewProj1, iPosition);
#if defined(PSSM_ENABLED)
	vLightSpacePos2 = mul(texWorldViewProj2, iPosition);
	vLightSpacePos3 = mul(texWorldViewProj3, iPosition);
#endif
#endif

#if defined(VERTEX_LIGHTING)
	float3 pixelToLight = normalize(lightPosition[0].xyz - (vViewPosition * lightPosition[0].w));
	float attenuation = max(dot(vViewNormal, pixelToLight.xyz), 0.0);
	vLightResult = lightDiffuse[0].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 viewReflect = reflect(normalize(vViewPosition), vViewNormal);
	attenuation *= pow(max(dot(viewReflect, pixelToLight), 0.0), materialShininess);
	vSpecularResult = lightSpecular[0].xyz * attenuation;
#endif
#endif
}

// -------------------------------------------

// Parallax Mapping Function
float2 ParallaxMapping(float2 texCoords, float3 viewDir, float scale, sampler2D heightMap)
{
    const float minLayers = 8.0; // Optimized for SM3.0
    const float maxLayers = 16.0;
    float numLayers = lerp(maxLayers, minLayers, abs(dot(float3(0, 0, 1), viewDir))); 
    float layerDepth = 1.0 / numLayers;
    float currentLayerDepth = 0.0;
    
    // Shift texture coordinates along V
    // P = V * scale * height
    float2 P = viewDir.xy * scale; 
    float2 deltaTexCoords = P / numLayers;
    
    float2 currentTexCoords = texCoords;
    float currentDepthMapValue = tex2D(heightMap, currentTexCoords).a; // Assuming Height in Alpha
    
    [unroll(16)] // Explicit loop hint for SM3
    for(int i = 0; i < 16; i++) {
        if(currentLayerDepth >= currentDepthMapValue) break;
        currentTexCoords -= deltaTexCoords;
        currentDepthMapValue = tex2D(heightMap, currentTexCoords).a;  
        currentLayerDepth += layerDepth;  
    }

    // Parallax Occlusion (Interpolate between last two steps)
    float2 prevTexCoords = currentTexCoords + deltaTexCoords;
    float afterDepth  = currentDepthMapValue - currentLayerDepth;
    float beforeDepth = tex2D(heightMap, prevTexCoords).a - currentLayerDepth + layerDepth;
    float weight = afterDepth / (afterDepth - beforeDepth);
    float2 finalTexCoords = prevTexCoords * weight + currentTexCoords * (1.0 - weight);

    return finalTexCoords; 
}


void terrain_fragment(
	uniform sampler2D diffuseMap : register(s0),
#if defined(DETAILMAP_ENABLED)
	uniform sampler2D detailMap : register(s1),
#endif
#if defined(NORMALMAP_ENABLED)
	uniform sampler2D normalMap : register(s2),
#endif
#if defined(SPECULARMAP_ENABLED)
	uniform sampler2D specularMap : register(s3),
#endif
#if defined(EMISSIVEMAP_ENABLED)
	uniform sampler2D emissiveMap : register(s4),
#endif
#if defined(SHADOWRECEIVER)
	uniform sampler2D shadowMap1 : register(s5),
#if defined(PSSM_ENABLED)
	uniform sampler2D shadowMap2 : register(s6),
	uniform sampler2D shadowMap3 : register(s7),
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
	uniform float blendPower,

	in float4 vColor : COLOR0,
#if defined(VERTEX_LIGHTING)
	in float3 vLightResult : COLOR1,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	in float3 vSpecularResult : COLOR2,
#endif
#endif
	in float2 vTexCoord : TEXCOORD0,
#if !defined(VERTEX_LIGHTING)
	in float3 vViewNormal : TEXCOORD2,
	in float3 vViewTangent : TEXCOORD3,
	in float3 vViewPosition : TEXCOORD4,
#endif
	in float vDepth : TEXCOORD5,
#if defined(SHADOWRECEIVER)
	in float4 vLightSpacePos1 : TEXCOORD6,
#if defined(PSSM_ENABLED)
	in float4 vLightSpacePos2 : TEXCOORD7,
	in float4 vLightSpacePos3 : TEXCOORD8,
#endif
#endif

	out float4 oColor : COLOR
#if defined(LOGDEPTH_ENABLE)	
	, out float oDepth : DEPTH
#endif
)
{
	float shadow = 1.0;
#if defined(SHADOWRECEIVER)
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
	shadow = shadow * 0.7 + 0.3;
#endif


#if defined(VERTEX_LIGHTING)

     // Vertex Fallback: Standard Texture Sample
    float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
	float3 lightResult = vLightResult;
#if defined(SHADOWRECEIVER)
	lightResult *= shadow;
#endif
	lightResult += sceneAmbient.xyz;
	oColor.xyz = lightResult.xyz * vColor.xyz * diffuseTex.xyz; 
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	oColor.xyz += vSpecularResult;
#endif

#else
    // ================= PBR + POM LIGHTING =================
	float3 viewPos = vViewPosition;
    
    // TBN Calculation (Moved up for POM)
    float3 V = normalize(-viewPos);
    float3 N = normalize(vViewNormal);
    float3 T = normalize(vViewTangent);
    float3 B = cross(T, N);
	float3x3 tbn = float3x3(T, B, N);
    
    // Compute Tangent Space View Direction for POM
    float3 tangentViewDir = mul(tbn, V); // Transpose mul for inverse rotation
    
    float2 finalTexCoords = vTexCoord;
    
    // Apply POM if NormalMap is enabled (assuming Height is in diffuse/normal alpha)
    // Actually standard: Use diffuse alpha? Or Normal alpha?
    // Using NormalMap Alpha (s2) is common. If defined.
#if defined(NORMALMAP_ENABLED)
     // POM SCALE 
     float pomHeightScale = 0.05; 
     
     // IMPORTANT: We need heightmap. Let's assume it's in Normal Map Alpha
     finalTexCoords = ParallaxMapping(vTexCoord, tangentViewDir, pomHeightScale, normalMap);
#endif

	float4 diffuseTex = tex2D(diffuseMap, finalTexCoords);
	float3 albedo = pow(diffuseTex.rgb, 2.2);
	
	float ao = 1.0;
	float roughness = 0.9;
	float metallic = 0.0;

#if defined(SPECULARMAP_ENABLED)
	float4 ormTex = tex2D(specularMap, finalTexCoords);
	ao = ormTex.r;
	roughness = ormTex.g;
	metallic = ormTex.b;
#endif

#if defined(NORMALMAP_ENABLED)
	float3 normalTex = tex2D(normalMap, finalTexCoords).xyz * 2.0 - 1.0;
	N = normalize(mul(normalTex, tbn));
#endif

	float3 F0 = float3(0.04, 0.04, 0.04); 
	F0 = lerp(F0, albedo, metallic);

	float3 Lo = float3(0.0, 0.0, 0.0);

#if MAX_LIGHTS > 1
	[unroll] for (int i = 0; i < MAX_LIGHTS; ++i)
	{
		if (i >= int(lightCount))
			break;
#else
	{
		const int i = 0;
#endif
		float3 L = lightPosition[i].xyz - (viewPos * lightPosition[i].w);
		float d = length(L);
		L = normalize(L);
        float3 H = normalize(V + L);

        float attenuation = 1.0;
        if (lightPosition[i].w > 0.0) 
        {
			attenuation = saturate(1.0 / 
				(lightAttenuation[i].y + d * (lightAttenuation[i].z + d * lightAttenuation[i].w)));

			attenuation *= pow(clamp(
				(dot(L, normalize(-lightDirection[i].xyz)) - spotLightParams[i].y) /
				(spotLightParams[i].x - spotLightParams[i].y), 1e-30, 1.0), spotLightParams[i].z);
        }

        if (i == 0) attenuation *= shadow;

        float3 radiance = lightDiffuse[i].rgb * attenuation;

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
    
	float3 ambient = float3(0.03, 0.03, 0.03) * albedo * ao;
	ambient += sceneAmbient.rgb * albedo * ao;

    float3 color = ambient + Lo;
    color *= vColor.rgb;

#if defined(EMISSIVEMAP_ENABLED)
	float3 emissiveTex = tex2D(emissiveMap, finalTexCoords).xyz;
	color += emissiveTex;
#endif

#if defined(DETAILMAP_ENABLED)
	float3 detailTex = tex2D(detailMap, frac(finalTexCoords * 8)).xyz * 2;
	float3 fullbrightDetail = float3(1, 1, 1);
	float detailDistance = saturate(vDepth * 0.025);
	float3 detailColor = lerp(detailTex, fullbrightDetail, detailDistance);
	color = lerp(color, color * detailColor, diffuseTex.a); 
#endif

	color = pow(color, 1.0/2.2);
	oColor.xyz = color;

#endif 

	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, fogColour.xyz, fogValue);

	oColor.a = pow(vColor.a, blendPower);

#if defined(LOGDEPTH_ENABLE)
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
