// DX11 SM4 terrain shader path for Campaign Reimagined.
// Enhanced mode uses the experimental legacy-compatible GGX direct-lighting model.
// IBL_ENABLED layers static split-sum image-based lighting onto that DX11 path.
// Keep shared PBR helpers synchronized with CR_base-sm4.hlsl.

// Force OG retro mode to ignore modern map contributions even if a program
// variant accidentally leaves those feature defines enabled.
#if defined(OG_RETRO_MODE)
#undef NORMALMAP_ENABLED
#undef SPECULARMAP_ENABLED
#undef SPECULAR_ENABLED
#undef EMISSIVEMAP_ENABLED
#undef IBL_ENABLED
#endif

// IBL is intentionally an Enhanced DX11 extension, never a standalone mode.
#if defined(IBL_ENABLED) && !defined(ENHANCED_MODE)
#undef IBL_ENABLED
#endif

#if defined(SHADOWRECEIVER)
float PCF_Filter(
    in Texture2D map,
    in SamplerState sam,
    in float4 uv,
    in float2 invMapSize)
{
    if (abs(uv.w) <= 1e-6)
        return 1.0;

    uv.xyz *= rcp(uv.w);
    uv.w = 1.0;
    uv.z = min(uv.z, 1.0);
    invMapSize = max(invMapSize, float2(1e-8, 1e-8));

#if PCF_SIZE > 1
    float2 pixel = uv.xy / invMapSize - float2(float(PCF_SIZE - 1) * 0.5, float(PCF_SIZE - 1) * 0.5);
    float2 c = floor(pixel);
    float2 f = frac(pixel);

    float kernel[PCF_SIZE * PCF_SIZE];
    {
        [unroll] for (int y = 0; y < PCF_SIZE; ++y)
        {
            [unroll] for (int x = 0; x < PCF_SIZE; ++x)
            {
                int i = y * PCF_SIZE + x;
                kernel[i] = step(uv.z, map.Sample(sam, (c + float2(x, y)) * invMapSize).x);
            }
        }
    }

    float4 sum = float4(0.0, 0.0, 0.0, 0.0);
    {
        [unroll] for (int y = 0; y < PCF_SIZE - 1; ++y)
        {
            [unroll] for (int x = 0; x < PCF_SIZE - 1; ++x)
            {
                int i = y * PCF_SIZE + x;
                sum += float4(kernel[i], kernel[i + 1], kernel[i + PCF_SIZE], kernel[i + PCF_SIZE + 1]);
            }
        }
    }

    return lerp(lerp(sum.x, sum.y, f.x), lerp(sum.z, sum.w, f.x), f.y)
        / float((PCF_SIZE - 1) * (PCF_SIZE - 1));
#else
    return step(uv.z, map.Sample(sam, uv.xy).x);
#endif
}
#endif

#if defined(NORMALMAP_ENABLED) && !defined(VERTEX_TANGENTS)
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

    float invmax = rsqrt(max(max(dot(T, T), dot(B, B)), 1e-20));
    T *= invmax;
    B *= invmax;
    return float3x3(T, B, N);
}
#endif

float3 safe_normalize(float3 v)
{
    float lenSq = dot(v, v);
    return (lenSq > 1e-8) ? v * rsqrt(lenSq) : float3(0.0, 0.0, 0.0);
}

float luminance_legacy(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

#if defined(ENHANCED_MODE)
float3 sharpen_normal_map(float3 normalTex)
{
    float2 sharpenedXY = normalTex.xy * 1.85;
    float sharpenedZ = max(normalTex.z, 0.20);
    return safe_normalize(float3(sharpenedXY, sharpenedZ));
}

// -----------------------------------------------------------------------------
// Legacy-PBR calibration. Keep synchronized with CR_base-sm4.hlsl.
// -----------------------------------------------------------------------------
static const float CR_PI = 3.14159265359;
static const float CR_PBR_MIN_ROUGHNESS = 0.12;
static const float CR_PBR_MAX_ROUGHNESS = 0.92;
static const float CR_PBR_SHININESS_SCALE = 1.00;
static const float CR_PBR_SPECULAR_ROUGHNESS_INFLUENCE = 0.10;
static const float CR_PBR_NORMAL_VARIANCE_SCALE = 0.30;
static const float CR_PBR_MAX_VARIANCE_ROUGHNESS = 0.35;
static const float CR_PBR_DEFAULT_F0 = 0.04;
static const float CR_PBR_MAX_LEGACY_F0 = 0.45;
static const float CR_PBR_DIFFUSE_COMPENSATION = 2.70;
static const float CR_PBR_SPECULAR_COMPENSATION = 1.00;

// Static IBL calibration. Keep synchronized with CR_base-sm4.hlsl.
static const float CR_IBL_DIFFUSE_INTENSITY = 0.62;
static const float CR_IBL_SPECULAR_INTENSITY = 0.82;
static const float CR_IBL_LEGACY_AMBIENT_RETAIN = 0.20;
static const float CR_IBL_SCENE_TINT_STRENGTH = 0.18;
static const float CR_IBL_MAX_SPECULAR_MIP = 7.0;

float legacy_shininess_to_roughness(float shininess)
{
    float scaledShininess = max(shininess * CR_PBR_SHININESS_SCALE, 0.0);
    float roughness = sqrt(2.0 / (scaledShininess + 2.0));
    return clamp(roughness, CR_PBR_MIN_ROUGHNESS, CR_PBR_MAX_ROUGHNESS);
}

float3 legacy_specular_to_f0(float3 specularTex)
{
    specularTex = saturate(specularTex);
    float peak = max(max(specularTex.r, specularTex.g), specularTex.b);
    float3 tint = (peak > 1e-4) ? specularTex / peak : float3(1.0, 1.0, 1.0);
    float strength = lerp(CR_PBR_DEFAULT_F0, CR_PBR_MAX_LEGACY_F0, pow(peak, 1.35));
    return saturate(lerp(float3(CR_PBR_DEFAULT_F0, CR_PBR_DEFAULT_F0, CR_PBR_DEFAULT_F0),
                         tint * strength,
                         saturate(peak * 0.90)));
}

float derive_legacy_roughness(float materialShininess, float specularMask)
{
    float roughness = legacy_shininess_to_roughness(materialShininess);
    float smoothnessBias = (specularMask - 0.5) * 2.0;
    roughness *= 1.0 - smoothnessBias * CR_PBR_SPECULAR_ROUGHNESS_INFLUENCE;
    return clamp(roughness, CR_PBR_MIN_ROUGHNESS, CR_PBR_MAX_ROUGHNESS);
}

float filter_roughness_from_normal_variance(float3 N, float roughness)
{
    float3 dNdx = ddx(N);
    float3 dNdy = ddy(N);
    float variance = max(dot(dNdx, dNdx), dot(dNdy, dNdy));
    variance = min(variance * CR_PBR_NORMAL_VARIANCE_SCALE, CR_PBR_MAX_VARIANCE_ROUGHNESS);
    float filtered = sqrt(max(roughness * roughness + variance, 0.0));
    return clamp(filtered, CR_PBR_MIN_ROUGHNESS, CR_PBR_MAX_ROUGHNESS);
}

float distribution_ggx(float NdotH, float roughness)
{
    float a = max(roughness * roughness, 1e-4);
    float a2 = a * a;
    float n2 = NdotH * NdotH;
    float denom = n2 * (a2 - 1.0) + 1.0;
    return a2 / max(CR_PI * denom * denom, 1e-6);
}

float geometry_schlick_ggx(float NdotX, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) * 0.125;
    return NdotX / max(NdotX * (1.0 - k) + k, 1e-6);
}

float geometry_smith(float NdotV, float NdotL, float roughness)
{
    return geometry_schlick_ggx(NdotV, roughness)
         * geometry_schlick_ggx(NdotL, roughness);
}

float3 fresnel_schlick(float cosTheta, float3 F0)
{
    float m = saturate(1.0 - cosTheta);
    float m2 = m * m;
    float m5 = m2 * m2 * m;
    return F0 + (1.0 - F0) * m5;
}

float3 fresnel_schlick_roughness(float cosTheta, float3 F0, float roughness)
{
    float m = saturate(1.0 - cosTheta);
    float m2 = m * m;
    float m5 = m2 * m2 * m;
    float3 grazing = max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0);
    return F0 + (grazing - F0) * m5;
}

float3 ibl_scene_tint(float3 sceneAmbient, float3 fogColour)
{
    float3 sceneTint = saturate(sceneAmbient + fogColour * 0.35);
    return lerp(float3(1.0, 1.0, 1.0), sceneTint, CR_IBL_SCENE_TINT_STRENGTH);
}

void evaluate_legacy_pbr(
    float3 N,
    float3 V,
    float3 L,
    float3 F0,
    float roughness,
    out float3 diffuseWeight,
    out float3 specularBRDF,
    out float NdotL)
{
    NdotL = saturate(dot(N, L));
    float NdotV = saturate(dot(N, V));
    diffuseWeight = float3(0.0, 0.0, 0.0);
    specularBRDF = float3(0.0, 0.0, 0.0);

    if (NdotL <= 0.0 || NdotV <= 0.0)
        return;

    float3 H = safe_normalize(V + L);
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    float D = distribution_ggx(NdotH, roughness);
    float G = geometry_smith(NdotV, NdotL, roughness);
    float3 F = fresnel_schlick(VdotH, F0);

    specularBRDF = (D * G * F) / max(4.0 * NdotV * NdotL, 1e-5);
    diffuseWeight = (1.0 - F) * (CR_PBR_DIFFUSE_COMPENSATION / CR_PI);
}
#endif

void ComputeSpotlightTerms(
    float3 pixelToLight,
    float3 lightDir,
    float4 spotParams,
    out float diffuseSpotAttenuation,
    out float specularSpotAttenuation)
{
    float spotRange = max(spotParams.x - spotParams.y, 1e-6);
    float cone = dot(pixelToLight, safe_normalize(-lightDir));
    float spotMask = saturate((cone - spotParams.y) / spotRange);
    float spotEnabled = (spotParams.z > 1e-4) ? 1.0 : 0.0;
    float spotPower = max(spotParams.z, 1.0);
    diffuseSpotAttenuation = lerp(1.0, pow(max(spotMask, 1e-4), spotPower), spotEnabled);
    specularSpotAttenuation = lerp(1.0, pow(max(spotMask, 1e-4), max(spotPower * 1.5, 1.0)), spotEnabled);
}

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
    in uint4 iBlendIndices : BLENDINDICES,
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
    in float3 iTangent : TANGENT0,
#endif
    in float4 iColor : COLOR0,
    in float heightOffset : TEXCOORD1,

    out float4 vColor : COLOR0,
#if defined(VERTEX_LIGHTING)
    out float3 vLightResult : COLOR1,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
    out float3 vSpecularResult : COLOR2,
#endif
#endif

    out float2 vTexCoord : TEXCOORD0,
#if !defined(VERTEX_LIGHTING)
    out float3 vViewNormal : TEXCOORD2,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
    out float3 vViewTangent : TEXCOORD3,
#endif
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

    out float4 oPosition : SV_POSITION
)
{
    iPosition.y = heightOffset;
    float2 nNormal = (float2(iBlendIndices.zw) - float2(127.0, 127.0)) / float2(127.0, 127.0);
    float3 iNormal = float3(nNormal.x, sqrt(saturate(1.0 - dot(nNormal, nNormal))), nNormal.y);

    oPosition = mul(wvpMat, iPosition);
    vTexCoord = (float2(iBlendIndices.xy) + 0.5) / 160.0;

#if defined(VERTEX_LIGHTING)
    float3 vViewPosition, vViewNormal;
#endif
    vViewPosition = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
    vViewNormal = mul(worldViewMat, float4(iNormal.xyz, 0.0)).xyz;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
    vViewTangent = mul(worldViewMat, float4(iTangent.xyz, 0.0)).xyz;
#endif

    vDepth = oPosition.z;
    vColor = iColor.bgra;

#if defined(SHADOWRECEIVER)
    vLightSpacePos1 = mul(texWorldViewProj1, iPosition);
#if defined(PSSM_ENABLED)
    vLightSpacePos2 = mul(texWorldViewProj2, iPosition);
    vLightSpacePos3 = mul(texWorldViewProj3, iPosition);
#endif
#endif

#if defined(VERTEX_LIGHTING)
    float3 vertexNormal = safe_normalize(vViewNormal);
    float3 pixelToLight = safe_normalize(lightPosition[0].xyz - (vViewPosition * lightPosition[0].w));

    float attenuation = max(dot(vertexNormal, pixelToLight.xyz), 0.0);
#if defined(OG_RETRO_MODE)
    attenuation = saturate(attenuation * 0.55 + 0.20);
#endif
    vLightResult = lightDiffuse[0].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
    float3 viewReflect = reflect(safe_normalize(vViewPosition), vertexNormal);
    attenuation *= pow(max(dot(viewReflect, pixelToLight), 0.0), materialShininess);
    vSpecularResult = lightSpecular[0].xyz * attenuation;
#endif
#endif
}

void terrain_fragment(
    uniform Texture2D diffuseMap : register(t0),
    uniform SamplerState diffuseSam : register(s0),
#if defined(DETAILMAP_ENABLED)
    uniform Texture2D detailMap : register(t1),
    uniform SamplerState detailSam : register(s1),
#endif
#if defined(NORMALMAP_ENABLED)
    uniform Texture2D normalMap : register(t2),
    uniform SamplerState normalSam : register(s2),
#endif
#if defined(SPECULARMAP_ENABLED)
    uniform Texture2D specularMap : register(t3),
    uniform SamplerState specularSam : register(s3),
#endif
#if defined(EMISSIVEMAP_ENABLED)
    uniform Texture2D emissiveMap : register(t4),
    uniform SamplerState emissiveSam : register(s4),
#endif
#if defined(SHADOWRECEIVER)
    uniform Texture2D shadowMap1 : register(t5),
    uniform SamplerState shadowSam1 : register(s5),
#if defined(PSSM_ENABLED)
    uniform Texture2D shadowMap2 : register(t6),
    uniform SamplerState shadowSam2 : register(s6),
    uniform Texture2D shadowMap3 : register(t7),
    uniform SamplerState shadowSam3 : register(s7),
#endif

    uniform float4 invShadowMapSize1,
#if defined(PSSM_ENABLED)
    uniform float4 invShadowMapSize2,
    uniform float4 invShadowMapSize3,
    uniform float4 pssmSplitPoints,
#endif
#endif

#if defined(IBL_ENABLED)
#if defined(PSSM_ENABLED)
    uniform TextureCube irradianceMap : register(t8),
    uniform SamplerState irradianceSam : register(s8),
    uniform TextureCube prefilteredEnvMap : register(t9),
    uniform SamplerState prefilteredEnvSam : register(s9),
    uniform Texture2D brdfLut : register(t10),
    uniform SamplerState brdfLutSam : register(s10),
#elif defined(SHADOWRECEIVER)
    uniform TextureCube irradianceMap : register(t6),
    uniform SamplerState irradianceSam : register(s6),
    uniform TextureCube prefilteredEnvMap : register(t7),
    uniform SamplerState prefilteredEnvSam : register(s7),
    uniform Texture2D brdfLut : register(t8),
    uniform SamplerState brdfLutSam : register(s8),
#else
    uniform TextureCube irradianceMap : register(t5),
    uniform SamplerState irradianceSam : register(s5),
    uniform TextureCube prefilteredEnvMap : register(t6),
    uniform SamplerState prefilteredEnvSam : register(s6),
    uniform Texture2D brdfLut : register(t7),
    uniform SamplerState brdfLutSam : register(s7),
#endif
    uniform float4x4 inverseViewMatrix,
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
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
    in float3 vViewTangent : TEXCOORD3,
#endif
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

    out float4 oColor : SV_TARGET
#if defined(LOGDEPTH_ENABLE)
    , out float oDepth : SV_DEPTH
#endif
)
{
#if defined(SHADOWRECEIVER)
    float shadow;
#if defined(PSSM_ENABLED)
    if (vDepth <= pssmSplitPoints.y)
    {
#endif
        shadow = PCF_Filter(shadowMap1, shadowSam1, vLightSpacePos1, invShadowMapSize1.xy);
#if defined(PSSM_ENABLED)
    }
    else if (vDepth <= pssmSplitPoints.z)
    {
        shadow = PCF_Filter(shadowMap2, shadowSam2, vLightSpacePos2, invShadowMapSize2.xy);
    }
    else
    {
        shadow = PCF_Filter(shadowMap3, shadowSam3, vLightSpacePos3, invShadowMapSize3.xy);
    }
#endif
#if defined(ENHANCED_MODE)
    shadow = shadow * 0.78 + 0.22;
#else
    shadow = shadow * 0.7 + 0.3;
#endif
#if defined(OG_RETRO_MODE)
    shadow = shadow * 0.5 + 0.5;
#endif
#endif

#if defined(VERTEX_LIGHTING)

#if defined(RETRO_UNLIT_MODE)
    float3 lightResult = vLightResult;
#if defined(SHADOWRECEIVER)
    lightResult *= shadow;
#endif
#if defined(OG_RETRO_MODE)
    lightResult += max(sceneAmbient.xyz * 1.10, float3(0.22, 0.22, 0.22));
#else
    lightResult += sceneAmbient.xyz;
#endif
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
    float3 specularResult = float3(0.0, 0.0, 0.0);
#endif
#else
    float3 lightResult = vLightResult;
#if defined(SHADOWRECEIVER)
    lightResult *= shadow;
#endif
#if defined(OG_RETRO_MODE)
    lightResult += max(sceneAmbient.xyz * 1.10, float3(0.22, 0.22, 0.22));
#else
    lightResult += sceneAmbient.xyz;
#endif
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
    float3 specularResult = vSpecularResult;
#endif
#endif

#else

    float3 viewPos = vViewPosition;

#if defined(NORMALMAP_ENABLED)
#if defined(VERTEX_TANGENTS)
    float3 baseNormal = safe_normalize(vViewNormal);
    float3 baseTangent = safe_normalize(vViewTangent);
    float3 binormal = safe_normalize(cross(baseTangent, baseNormal));
    float3x3 tbn = float3x3(baseTangent, binormal, baseNormal);
#else
    float3x3 tbn = cotangent_frame(safe_normalize(vViewNormal), vViewPosition.xyz, vTexCoord);
#endif

    float3 normalTex = normalMap.Sample(normalSam, vTexCoord).xyz * 2.0 - 1.0;
#if defined(ENHANCED_MODE)
    normalTex = lerp(sharpen_normal_map(normalTex), normalTex, saturate(vDepth * 0.005));
#endif
    float3 viewNormal = safe_normalize(mul(normalTex, tbn));
#else
    float3 viewNormal = safe_normalize(vViewNormal);
#endif

#if defined(SPECULARMAP_ENABLED)
    float3 specularTex = specularMap.Sample(specularSam, vTexCoord).xyz;
    float specularMask = saturate(luminance_legacy(specularTex));
#if defined(ENHANCED_MODE)
    float3 surfaceF0 = legacy_specular_to_f0(specularTex);
#else
    float3 specularTint = lerp(float3(0.04, 0.04, 0.04), specularTex, specularMask);
#endif
#elif defined(ENHANCED_MODE)
    float specularMask = 0.5;
    float3 surfaceF0 = float3(CR_PBR_DEFAULT_F0, CR_PBR_DEFAULT_F0, CR_PBR_DEFAULT_F0);
#endif

#if defined(ENHANCED_MODE)
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
    float surfaceRoughness = derive_legacy_roughness(materialShininess, specularMask);
#if defined(NORMALMAP_ENABLED)
    surfaceRoughness = filter_roughness_from_normal_variance(viewNormal, surfaceRoughness);
#endif
#endif
#endif

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED) || defined(ENHANCED_MODE)
    float3 eyeDir = safe_normalize(-viewPos);
#endif

#if defined(OG_RETRO_MODE)
    float3 lightResult = max(sceneAmbient.xyz * 1.10, float3(0.22, 0.22, 0.22));
#elif defined(IBL_ENABLED)
    float3 lightResult = sceneAmbient.xyz * CR_IBL_LEGACY_AMBIENT_RETAIN;
#else
    float3 lightResult = sceneAmbient.xyz;
#endif
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
    float3 specularResult = float3(0.0, 0.0, 0.0);
#endif

#if defined(RETRO_UNLIT_MODE)
    if (lightCount > 0.0)
    {
        const int i = 0;
        float3 pixelToLight = lightPosition[i].xyz - (viewPos * lightPosition[i].w);
        float d = max(length(pixelToLight), 1e-6);
        pixelToLight *= rcp(d);

#if defined(SHADOWRECEIVER)
        float attenuation = shadow;
#else
        float attenuation = 1.0;
#endif

        float diffuseTerm = max(dot(viewNormal, pixelToLight), 0.0);
#if defined(OG_RETRO_MODE)
        diffuseTerm = saturate(diffuseTerm * 0.55 + 0.20);
#endif
        lightResult.xyz += lightDiffuse[i].xyz * (attenuation * diffuseTerm);
    }
#else

#if MAX_LIGHTS > 1
    for (int i = 0; i < MAX_LIGHTS; ++i)
    {
        if (i >= int(lightCount))
            break;
#else
    {
        const int i = 0;
#endif
        float3 pixelToLight = lightPosition[i].xyz - (viewPos * lightPosition[i].w);
        float d = max(length(pixelToLight), 1e-6);
        pixelToLight *= rcp(d);

        float attenuationDenom = lightAttenuation[i].y
                               + d * (lightAttenuation[i].z + d * lightAttenuation[i].w);
        float distanceAttenuation = saturate(rcp(max(attenuationDenom, 1e-6)));

        float diffuseSpotAttenuation = 1.0;
        float specularSpotAttenuation = 1.0;
        ComputeSpotlightTerms(
            pixelToLight,
            lightDirection[i].xyz,
            spotLightParams[i],
            diffuseSpotAttenuation,
            specularSpotAttenuation);

        float attenuation = distanceAttenuation * diffuseSpotAttenuation;
        float specularAttenuation = distanceAttenuation * specularSpotAttenuation;

#if defined(SHADOWRECEIVER)
        attenuation *= shadow;
        specularAttenuation *= shadow;
#endif

#if defined(ENHANCED_MODE) && (defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED))
        float3 diffuseWeight;
        float3 specularBRDF;
        float NdotL;
        evaluate_legacy_pbr(
            viewNormal,
            eyeDir,
            pixelToLight,
            surfaceF0,
            surfaceRoughness,
            diffuseWeight,
            specularBRDF,
            NdotL);

        lightResult.xyz += lightDiffuse[i].xyz * attenuation * NdotL * diffuseWeight;
        specularResult.xyz += lightSpecular[i].xyz
                            * specularAttenuation
                            * NdotL
                            * specularBRDF
                            * CR_PBR_SPECULAR_COMPENSATION;
#elif defined(ENHANCED_MODE)
        float NdotL = saturate(dot(viewNormal, pixelToLight));
        lightResult.xyz += lightDiffuse[i].xyz
                         * attenuation
                         * NdotL
                         * (CR_PBR_DIFFUSE_COMPENSATION / CR_PI);
#else
        float diffuseTerm = max(dot(viewNormal, pixelToLight), 0.0);
#if defined(OG_RETRO_MODE)
        diffuseTerm = saturate(diffuseTerm * 0.55 + 0.20);
#endif
        attenuation *= diffuseTerm;
        lightResult.xyz += lightDiffuse[i].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
        if (diffuseTerm > 0.0)
        {
            float3 halfVector = safe_normalize(pixelToLight + eyeDir);
            float ndotv = max(dot(viewNormal, eyeDir), 0.0);
            float ndoth = max(dot(viewNormal, halfVector), 0.0);
#if defined(SPECULARMAP_ENABLED)
            float specularPower = lerp(
                max(materialShininess * 0.9 + 6.0, 8.0),
                max(materialShininess * 2.25 + 24.0, 24.0),
                specularMask);
            float3 specularColor = lerp(specularTint * 0.65, specularTint, pow(1.0 - ndotv, 5.0));
#else
            float specularPower = max(materialShininess * 1.5 + 12.0, 16.0);
            float3 specularColor = lerp(float3(0.025, 0.025, 0.025), float3(0.04, 0.04, 0.04), pow(1.0 - ndotv, 5.0));
#endif
            float specularLobe = pow(ndoth, specularPower);
            specularResult.xyz += lightSpecular[i].xyz
                                * specularAttenuation
                                * diffuseTerm
                                * specularLobe
                                * specularColor;
        }
#endif
#endif

#if defined(SHADOWRECEIVER)
        shadow = 1.0;
#endif
    }

#endif

#if defined(IBL_ENABLED) && (defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED))
    float NdotVForIBL = saturate(dot(viewNormal, eyeDir));
    float3 ambientFresnel = fresnel_schlick_roughness(NdotVForIBL, surfaceF0, surfaceRoughness);
    float3 diffuseEnergy = 1.0 - ambientFresnel;

    float3 worldNormal = safe_normalize(mul(inverseViewMatrix, float4(viewNormal, 0.0)).xyz);
    float3 viewReflection = reflect(-eyeDir, viewNormal);
    float3 worldReflection = safe_normalize(mul(inverseViewMatrix, float4(viewReflection, 0.0)).xyz);

    float3 environmentTint = ibl_scene_tint(sceneAmbient.xyz, fogColour.xyz);
    float3 irradiance = irradianceMap.Sample(irradianceSam, worldNormal).xyz * environmentTint;
    lightResult.xyz += irradiance * diffuseEnergy * CR_IBL_DIFFUSE_INTENSITY;

    float specularMip = saturate(surfaceRoughness) * CR_IBL_MAX_SPECULAR_MIP;
    float3 prefilteredEnvironment = prefilteredEnvMap.SampleLevel(
        prefilteredEnvSam,
        worldReflection,
        specularMip).xyz * environmentTint;
    float2 environmentBRDF = brdfLut.Sample(
        brdfLutSam,
        float2(NdotVForIBL, saturate(surfaceRoughness))).rg;

    specularResult.xyz += prefilteredEnvironment
                        * (surfaceF0 * environmentBRDF.x + environmentBRDF.y)
                        * CR_IBL_SPECULAR_INTENSITY;
#elif defined(ENHANCED_MODE)
    float NdotVForFill = saturate(dot(viewNormal, eyeDir));
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
    float3 grazingFresnel = fresnel_schlick(NdotVForFill, surfaceF0);
    lightResult.xyz += sceneAmbient.xyz * grazingFresnel * (1.0 - surfaceRoughness) * 0.15;
#else
    lightResult.xyz += sceneAmbient.xyz * pow(1.0 - NdotVForFill, 4.0) * 0.10;
#endif
#endif
#endif

    float4 diffuseTex = diffuseMap.Sample(diffuseSam, vTexCoord);
    oColor.xyz = lightResult.xyz * vColor.xyz * diffuseTex.xyz;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
    oColor.xyz += specularResult.xyz;
#endif

#if defined(EMISSIVEMAP_ENABLED)
    float3 emissiveTex = emissiveMap.Sample(emissiveSam, vTexCoord).xyz;
    oColor.xyz += emissiveTex.xyz;
#endif

#if defined(DETAILMAP_ENABLED)
    float3 detailTex = detailMap.Sample(detailSam, frac(vTexCoord * 8.0)).xyz * 2.0;
    float3 fullbrightDetail = float3(1.0, 1.0, 1.0);
#if defined(ENHANCED_MODE)
    float detailDistance = saturate(vDepth * 0.015);
    float3 detailColor = lerp(detailTex, fullbrightDetail, detailDistance);
    float3 detailTexNear = detailMap.Sample(detailSam, frac(vTexCoord * 32.0)).xyz * 2.0;
    float detailNearFade = saturate(vDepth * 0.08);
    detailColor *= lerp(lerp(detailTexNear, fullbrightDetail, 0.5), fullbrightDetail, detailNearFade);
#else
    float detailDistance = saturate(vDepth * 0.025);
    float3 detailColor = lerp(detailTex, fullbrightDetail, detailDistance);
#endif
#if defined(OG_RETRO_MODE)
    oColor.xyz = lerp(oColor.xyz, oColor.xyz * detailColor, diffuseTex.a * 0.35);
#else
    oColor.xyz = lerp(oColor.xyz, oColor.xyz * detailColor, diffuseTex.a);
#endif
#endif

    float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
    oColor.xyz = lerp(oColor.xyz, fogColour.xyz, fogValue);
    oColor.a = vColor.a;

#if defined(LOGDEPTH_ENABLE)
    const float C = 0.1;
    const float far = 1e+09;
    const float offset = 1.0;
    oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
