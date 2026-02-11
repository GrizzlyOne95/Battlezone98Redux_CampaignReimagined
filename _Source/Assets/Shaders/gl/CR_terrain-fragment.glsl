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

uniform sampler2D diffuseMap;
#if defined(DETAILMAP_ENABLED)
uniform sampler2D detailMap;
#endif
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
uniform float blendPower;

varying vec4 vColor;
#if defined (VERTEX_LIGHTING)
varying vec3 vLightResult;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
varying vec3 vSpecularResult;
#endif
#endif
varying vec2 vTexCoord;
#if !defined(VERTEX_LIGHTING)
varying vec3 vViewPosition;
varying vec3 vViewNormal;
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
varying vec3 vViewTangent;
#endif
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
#endif

#if defined(VERTEX_LIGHTING)

	// combine ambient and shadowed light result
	vec3 lightResult = vLightResult;
#if defined(SHADOWRECEIVER)
	lightResult *= shadow;
#endif
	lightResult += sceneAmbient.xyz;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	vec3 specularResult = vSpecularResult;
#endif
	
#else

	// per-pixel view position
	vec3 viewPos = vViewPosition;

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
	vec3 viewNormal = normalize(normalTex * tbn);
#else
	vec3 viewNormal = normalize(vViewNormal);
#endif

	// per-pixel direction to the eyepoint
	vec3 eyeDir = normalize(-viewPos.xyz);

	// start with ambient light and no specular
	vec3 lightResult = sceneAmbient.xyz;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	vec3 specularResult = vec3(0.0, 0.0, 0.0);
#endif

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// per-pixel view reflection
	vec3 viewReflect = reflect(-eyeDir, viewNormal);
#endif

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

		// get the direction from the pixel to the light source
		vec3 pixelToLight = (lightPosition[i].xyz - (viewPos * lightPosition[i].w));
		float d = length(pixelToLight);
		pixelToLight /= d;
		
			//compute distance attenuation
			float attenuation = clamp(1.0 / 
				(lightAttenuation[i].y + (d * (lightAttenuation[i].z + (d * lightAttenuation[i].w)))),
				0.0, 1.0);

			// compute spotlight attenuation
			// it's much faster to just do the math than have a branch on low-end GPUs
			// non-spotlights have falloff power 0 which yields a constant output
			attenuation *= pow(clamp(
				(dot(pixelToLight, normalize(-lightDirection[i].xyz)) - spotLightParams[i].y) /
				(spotLightParams[i].x - spotLightParams[i].y), 1e-30, 1.0), spotLightParams[i].z);
	
#if defined(SHADOWRECEIVER)
			// apply shadow attenuation
			attenuation *= shadow;
#endif

			// accumulate diffuse lighting
			attenuation *= max(dot(viewNormal, pixelToLight), 0.0);
			lightResult.xyz += lightDiffuse[i].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
			// accumulate specular lighting
			attenuation *= pow(max(dot(viewReflect, pixelToLight), 0.0), materialShininess);
			specularResult.xyz += lightSpecular[i].xyz * attenuation;
#endif

#if defined(SHADOWRECEIVER)
		// clear shadow attenuation
		shadow = 1.0;
#endif
	}

#endif

	// diffuse texture 
	vec4 diffuseTex = texture2D(diffuseMap, vTexCoord);
	oColor.xyz = lightResult.xyz * vColor.xyz * diffuseTex.xyz;
   
#if defined(SPECULARMAP_ENABLED)
   	// specular texture
	vec3 specularTex = texture2D(specularMap, vTexCoord).xyz;
	oColor.xyz += specularResult.xyz * specularTex.xyz;
#elif defined(SPECULAR_ENABLED)
	oColor.xyz += specularResult.xyz;
#endif

#if defined(EMISSIVEMAP_ENABLED)
	// emissive texture
	vec3 emissiveTex = texture2D(emissiveMap, vTexCoord).xyz;
	oColor.xyz += emissiveTex.xyz;
#endif
   
#if defined(DETAILMAP_ENABLED)
	// detail texture   
	vec3 detailTex = texture2D(detailMap, fract(vTexCoord * 8.0)).xyz * 2.0;
	vec3 fullbrightDetail = vec3(1.0, 1.0, 1.0);
	float detailDistance = clamp(vDepth * 0.025, 0.0, 1.0);
	vec3 detailColor = mix(detailTex, fullbrightDetail, detailDistance);
	oColor.xyz = mix(oColor.xyz, oColor.xyz * detailColor, diffuseTex.w);
#endif

	// fog
	float fogValue = clamp((vDepth - fogParams.y) * fogParams.w, 0.0, 1.0);
	oColor.xyz = mix(oColor.xyz, fogColour.xyz, fogValue);

	// output alpha
	oColor.a = pow(vColor.a, blendPower);

	gl_FragData[0] = oColor;

#if defined(LOGDEPTH_ENABLE)
	// logarithmic depth
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	gl_FragDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
