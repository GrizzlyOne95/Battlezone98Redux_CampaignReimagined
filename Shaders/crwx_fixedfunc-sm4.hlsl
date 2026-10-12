// ISDF Chronicles: DX11 stand-ins for fixed-function material passes.
//
// D3D11 has no fixed pipeline, so a pass without both a vertex and a fragment
// program throws "Attempted to render to a D3D11 device without both vertex
// and fragment shaders" on every draw. The affected CRWX materials carry a
// technique that binds these programs ahead of their original fixed-function
// technique. They are SM4-only: DX9 cannot use vs_4_0/ps_4_0, marks that
// technique unsupported and keeps drawing the original, so DX9 is unchanged.
//
// Programs are declared in crwx_fixedfunc.program. Variants (defines):
//
//   LIT           fixed-function vertex lighting (lighting on, the default):
//                 saturate(emissive + ambient * sceneAmbient
//                          + diffuse * light0 * N.L), alpha = diffuse alpha.
//                 Vertex colour is ignored, as the fixed pipeline ignores it
//                 while lighting is on.
//   LIT_FLAT      LIT without NORMAL, for geometry the engine draws itself
//                 (draw_sprite / draw_sphere): the light counts as facing.
//   VERTEX_COLOUR lighting off on engine geometry: colour = vertex colour.
//                 Native BZR vertex colours reach D3D11 in BGRA order.
//   (neither)     lighting off on a mesh: colour = white.
//   TWO_STAGE     second texture unit on UV set 0, own texture matrix.
//
//   STAGE0_* / STAGE1_*  colour_op of each texture unit (MODULATE, ADD,
//                 REPLACE, ALPHABLEND). Alpha is the default modulate on
//                 every stage: texture alpha times current alpha.
//   NO_FOG        pass has `fog_override true` with no fog: skip fog.
//
// Every vertex input is one the fixed pipeline also needed or that the
// geometry is known to carry: D3D11 throws "Unable to set D3D11 vertex
// declaration" on any shader input the mesh lacks.

// Uniforms are globals, one set per compiled variant; each is declared only
// where that variant reads it, so every default_params entry resolves.
float4x4 wvpMat;
float4x4 texMatrix0;
#ifdef TWO_STAGE
float4x4 texMatrix1;
#endif
#ifdef LIT
float4 surfaceDiffuse;
float4 surfaceEmissive;
float4 derivedAmbient;
float4 lightDiffuse;
#ifndef LIT_FLAT
float4 lightPosition;
float4 lightAttenuation;
#endif
#endif

Texture2D map0 : register(t0);
SamplerState sam0 : register(s0);
#ifdef TWO_STAGE
Texture2D map1 : register(t1);
SamplerState sam1 : register(s1);
#endif
#ifndef NO_FOG
float4 fogColour;
float4 fogParams;
#endif

void ff_vertex(
    in float4 iPosition : POSITION,
#if defined(LIT) && !defined(LIT_FLAT)
    in float3 iNormal : NORMAL,
#endif
#ifdef VERTEX_COLOUR
    in float4 iColor : COLOR0,
#endif
    in float2 iTexCoord : TEXCOORD0,

    out float4 oPosition : SV_POSITION,
    out float4 vColor : COLOR0,
    out float4 vTexCoord : TEXCOORD0,
    out float vDepth : TEXCOORD1
)
{
    oPosition = mul(wvpMat, iPosition);
    // Fog depth as the stock SM4 programs measure it (effect-sm4.hlsl etc.).
    vDepth = oPosition.z;

    vTexCoord.xy = mul(texMatrix0, float4(iTexCoord, 0.0, 1.0)).xy;
#ifdef TWO_STAGE
    vTexCoord.zw = mul(texMatrix1, float4(iTexCoord, 0.0, 1.0)).xy;
#else
    vTexCoord.zw = float2(0.0, 0.0);
#endif

#if defined(LIT)
    float lightTerm = 1.0;
#ifndef LIT_FLAT
    float3 toLight = lightPosition.xyz - iPosition.xyz * lightPosition.w;
    float dist = length(toLight);
    toLight = toLight / max(dist, 1e-5);
    lightTerm = saturate(dot(normalize(iNormal), toLight));
    if (lightPosition.w != 0.0)
    {
        // Point/spot light: range cut-off and constant/linear/quadratic
        // attenuation, as the fixed pipeline applies them.
        float atten = 1.0 / max(lightAttenuation.y + lightAttenuation.z * dist +
                                lightAttenuation.w * dist * dist, 1e-5);
        lightTerm *= (dist <= lightAttenuation.x) ? atten : 0.0;
    }
#endif
    float3 lit = surfaceEmissive.rgb + derivedAmbient.rgb +
                 surfaceDiffuse.rgb * lightDiffuse.rgb * lightTerm;
    vColor = float4(saturate(lit), surfaceDiffuse.a);
#elif defined(VERTEX_COLOUR)
    vColor = iColor.bgra;
#else
    vColor = float4(1.0, 1.0, 1.0, 1.0);
#endif
}

float3 ff_combine_modulate(float3 current, float4 tex) { return current * tex.rgb; }
float3 ff_combine_add(float3 current, float4 tex) { return current + tex.rgb; }
float3 ff_combine_replace(float3 current, float4 tex) { return tex.rgb; }
// colour_op alpha_blend: texture * texture.a + current * (1 - texture.a).
float3 ff_combine_alphablend(float3 current, float4 tex) { return lerp(current, tex.rgb, tex.a); }

void ff_fragment(
    in float4 iPosition : SV_POSITION,
    in float4 vColor : COLOR0,
    in float4 vTexCoord : TEXCOORD0,
    in float vDepth : TEXCOORD1,

    out float4 oColor : SV_TARGET
)
{
    float4 tex0 = map0.Sample(sam0, vTexCoord.xy);
#if defined(STAGE0_ADD)
    float3 current = ff_combine_add(vColor.rgb, tex0);
#elif defined(STAGE0_REPLACE)
    float3 current = ff_combine_replace(vColor.rgb, tex0);
#elif defined(STAGE0_ALPHABLEND)
    float3 current = ff_combine_alphablend(vColor.rgb, tex0);
#else
    float3 current = ff_combine_modulate(vColor.rgb, tex0);
#endif
    float alpha = vColor.a * tex0.a;

#ifdef TWO_STAGE
    float4 tex1 = map1.Sample(sam1, vTexCoord.zw);
#if defined(STAGE1_ADD)
    current = ff_combine_add(current, tex1);
#elif defined(STAGE1_REPLACE)
    current = ff_combine_replace(current, tex1);
#elif defined(STAGE1_ALPHABLEND)
    current = ff_combine_alphablend(current, tex1);
#else
    current = ff_combine_modulate(current, tex1);
#endif
    alpha *= tex1.a;
#endif

    // The fixed pipeline clamps every stage result to [0, 1].
    current = saturate(current);

#ifndef NO_FOG
    float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
    current = lerp(current, fogColour.rgb, fogValue);
#endif

    oColor = float4(current, saturate(alpha));
}
