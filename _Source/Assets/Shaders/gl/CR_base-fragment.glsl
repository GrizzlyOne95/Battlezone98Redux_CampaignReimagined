#version 120

#if defined(SHADOWRECEIVER)
float PCF_Filter(in sampler2D map,
					in vec4 uv,
					in vec2 invMapSize)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
#if PCF_SIZE > 1
	vec2 pixel = uv.xy / invMapSize - vec2(float(PCF_SIZE-1)*0.5, float(PCF_SIZE-1)*0.5);
	vec2 c = floor(pixel);
	vec2 f = fract(pixel);

	float kernel[PCF_SIZE*PCF_SIZE];
	for (int y = 0; y < PCF_SIZE; ++y)
	{
		for (int x = 0; x < PCF_SIZE; ++x)
		{
			int i = y * PCF_SIZE + x;
			kernel[i] = step(uv.z, texture2D(map, (c + vec2(x, y)) * invMapSize).x);
		}
	}

	vec4 sum = vec4(0.0, 0.0, 0.0, 0.0);
	for (int y = 0; y < PCF_SIZE-1; ++y)
	{
		for (int x = 0; x < PCF_SIZE-1; ++x)
		{
			int i = y * PCF_SIZE + x;
			sum += vec4(kernel[i], kernel[i+1], kernel[i+PCF_SIZE], kernel[i+PCF_SIZE+1]);
		}
	}

	return mix(mix(sum.x, sum.y, f.x), mix(sum.z, sum.w, f.x), f.y) / float((PCF_SIZE-1)*(PCF_SIZE-1));
#else
	return step(uv.z, texture2D(map, uv.xy).x);
#endif
}
#endif

#if defined(NORMALMAP_ENABLED) && !defined(VERTEX_TANGENTS)
// compute cotangent frame from normal, position, and texcoord
// http://www.thetenthplanet.de/archives/1180
mat3 cotangent_frame(in vec3 N, in vec3 p, in vec2 uv)
{
	// get edge vectors of the pixel triangle
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);

	// solve the linear system
	vec3 dp2perp = cross(N, dp2);
	vec3 dp1perp = cross(dp1, N);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
	
	// construct a scale-invariant frame
	float invmax = inversesqrt(max(dot(T, T), dot(B, B)) + 1e-30);
	T *= invmax;
	B *= invmax;
	return mat3(
		T.x, B.x, N.x,
		T.y, B.y, N.y,
		T.z, B.z, N.z
	);
}
#endif 

// ===============================================================================================
// PBR Helper Functions (Cook-Torrance BRDF) - Adapted for GLSL 120
// ===============================================================================================
const float PI = 3.14159265359;

// Normal Distribution Function (GGX)
float DistributionGGX(vec3 N, vec3 H, float roughness)
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
float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// Fresnel Equation (Schlick)
vec3 FresnelSchlick(float cosTheta, vec3 F0)
{
    // pow(x, 5.0) manually
    float val = clamp(1.0 - cosTheta, 0.0, 1.0);
    float val2 = val * val;
    float val5 = val2 * val2 * val;
    return F0 + (1.0 - F0) * val5;
}
// ===============================================================================================

uniform sampler2D diffuseMap;
#if defined(NORMALMAP_ENABLED) 
uniform sampler2D normalMap;
#endif
#if defined(SPECULARMAP_ENABLED)
uniform sampler2D specularMap;
#endif
#if defined(EMISSIVEMAP_ENABLED)
uniform sampler2D emissiveMap;
#endif

#if defined(SHADOWRECEIVER)
uniform sampler2D shadowMap1;
#if defined(PSSM_ENABLED)
uniform sampler2D shadowMap2;
uniform sampler2D shadowMap3;
#endif

uniform vec4 invShadowMapSize1;
#if defined(PSSM_ENABLED)
uniform vec4 invShadowMapSize2;
uniform vec4 invShadowMapSize3;
	
uniform vec4 pssmSplitPoints;
#endif
#endif

uniform vec4 sceneAmbient;
#if !defined(VERTEX_LIGHTING)
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
uniform float materialShininess;
#endif
uniform vec4 lightDiffuse[MAX_LIGHTS];
uniform vec4 lightPosition[MAX_LIGHTS];
uniform vec4 lightSpecular[MAX_LIGHTS];
uniform vec4 lightAttenuation[MAX_LIGHTS];
uniform vec4 spotLightParams[MAX_LIGHTS];
uniform vec4 lightDirection[MAX_LIGHTS];
uniform float lightCount;
#endif
uniform vec4 fogColour;
uniform vec4 fogParams;
uniform float transparency;

#if defined(VERTEX_LIGHTING)
varying vec3 vLightResult;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
varying vec3 vSpecularResult;
#endif
#endif

varying vec2 vTexCoord;

#if !defined(VERTEX_LIGHTING)
varying vec3 vViewNormal;
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
varying vec3 vViewTangent;
#endif
varying vec3 vViewPosition;
#endif

varying float vDepth;
#if defined(SHADOWRECEIVER)
varying vec4 vLightSpacePos1;
#if defined(PSSM_ENABLED)
varying vec4 vLightSpacePos2;
varying vec4 vLightSpacePos3;
#endif
#endif

void main()
{
	// outputs
	vec4 oColor;

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
	shadow = shadow * 0.7 + 0.3;
#else
    float shadow = 1.0;
#endif

	// Sample Diffuse (Albedo)
	vec4 diffuseTex = texture2D(diffuseMap, vTexCoord);
	vec3 albedo = pow(diffuseTex.rgb, vec3(2.2)); // Simple Gamma -> Linear approximation

	// Sample ORM Map (Occlusion, Roughness, Metallic) via Specular Map slot
	// Default values if no map
	float ao = 1.0;
	float roughness = 0.5;
	float metallic = 0.0;

#if defined(SPECULARMAP_ENABLED)
	vec4 ormTex = texture2D(specularMap, vTexCoord);
	// Assumption: R=AO, G=Roughness, B=Metallic
	ao = ormTex.r;
	roughness = ormTex.g;
	metallic = ormTex.b;
#endif

#if defined(VERTEX_LIGHTING)

	// combine ambient and shadowed light result
	vec3 lightResult = vLightResult * shadow + sceneAmbient.xyz;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	vec3 finalColor = lightResult * diffuseTex.rgb + vSpecularResult;
#else
    vec3 finalColor = lightResult * diffuseTex.rgb;
#endif
    
    oColor.xyz = finalColor;

#else

	// per-pixel view position
	vec3 viewPos = vViewPosition;
    vec3 N = normalize(vViewNormal);

#if defined(NORMALMAP_ENABLED)
	// tangent basis
#if defined(VERTEX_TANGENTS)
	vec3 binormal = cross(vViewTangent, vViewNormal);
	mat3 tbn = mat3(
		vViewTangent.x, binormal.x, vViewNormal.x,
		vViewTangent.y, binormal.y, vViewNormal.y,
		vViewTangent.z, binormal.z, vViewNormal.z
	);
#else
	mat3 tbn = cotangent_frame(vViewNormal, vViewPosition, vTexCoord);
#endif

	// per-pixel view normal
	vec3 normalTex = texture2D(normalMap, vTexCoord).xyz * 2.0 - 1.0;
	N = normalize(normalTex.xyz * tbn); // GL logic often pre-multiplies, check order if issues arise
#endif

    vec3 V = normalize(-viewPos); // View vector

	vec3 F0 = vec3(0.04, 0.04, 0.04); 
	F0 = mix(F0, albedo, metallic);

	vec3 Lo = vec3(0.0, 0.0, 0.0);

#if MAX_LIGHTS > 1
	// for each possible light source...
	for (int i = 0; i < MAX_LIGHTS; ++i)
	{
		if (i >= int(lightCount))
			break;
#else
	{
		const int i = 0;
#endif

		// get the direction from the pixel to the light source.
		vec3 pixelToLight = lightPosition[i].xyz - (viewPos * lightPosition[i].w);
		float d = length(pixelToLight);
		vec3 L = normalize(pixelToLight);

        vec3 H = normalize(V + L);
		
        // compute distance attenuation
        float attenuation = clamp(1.0 / 
            (lightAttenuation[i].y + (d * (lightAttenuation[i].z + (d * lightAttenuation[i].w)))),
            0.0, 1.0);

        // compute spotlight attenuation
        attenuation *= pow(clamp(
            (dot(L, normalize(-lightDirection[i].xyz)) - spotLightParams[i].y) /
            (spotLightParams[i].x - spotLightParams[i].y), 1e-30, 1.0), spotLightParams[i].z);

        if (i == 0) attenuation *= shadow;

        vec3 radiance = lightDiffuse[i].rgb * attenuation;

		// Cook-Torrance BRDF
		float NDF = DistributionGGX(N, H, roughness);
		float G   = GeometrySmith(N, V, L, roughness);
		vec3 F  = FresnelSchlick(max(dot(H, V), 0.0), F0);

		vec3 numerator    = NDF * G * F;
		float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
		vec3 specular = numerator / denominator;

		vec3 kS = F;
		vec3 kD = vec3(1.0, 1.0, 1.0) - kS;
		kD *= 1.0 - metallic;

		float NdotL = max(dot(N, L), 0.0);
		Lo += (kD * albedo / PI + specular) * radiance * NdotL;
	}
#if MAX_LIGHTS == 1
    } // end block
#endif

	// Ambient Lighting (Simplified IBL approximation)
	vec3 ambient = vec3(0.03, 0.03, 0.03) * albedo * ao; // Basic ambient
	ambient += sceneAmbient.rgb * albedo * ao; // Add Engine Ambient

	vec3 color = ambient + Lo;

#if defined(EMISSIVEMAP_ENABLED)
	//emissive texture
	vec3 emissiveTex = texture2D(emissiveMap, vTexCoord).xyz;
	color += emissiveTex;
#endif

    // Tonemapping & Gamma Correction
	color = pow(color, vec3(1.0/2.2)); // Gamma Correction back to sRGB

	oColor.xyz = color;

#endif // !VERTEX_LIGHTING

    // fog
	float fogValue = clamp((vDepth - fogParams.y) * fogParams.w, 0.0, 1.0);
	oColor.xyz = mix(oColor.xyz, fogColour.xyz, fogValue);

	// output alpha
	oColor.w = clamp(transparency, 0.0, 1.0);

	gl_FragData[0] = vec4(oColor);

#if defined(LOGDEPTH_ENABLE)	
	// logarithmic depth
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	gl_FragDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
