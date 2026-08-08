// Campaign Reimagined - DX11 overlay compatibility helper.
//
// Ogre overlay renderables do not all share one vertex declaration. Panel and
// BorderPanel geometry exposes POSITION + TEXCOORD, while TextArea geometry also
// carries per-vertex colour. Keep the panel path separate from CR_UI so D3D11 can
// build an input layout that exactly matches Panel/BorderPanel vertices.

void overlay_panel_vertex(
    uniform float4x4 wvpMat,

    in float4 iPosition : POSITION,
    in float2 iTexCoord : TEXCOORD0,

    out float2 vTexCoord : TEXCOORD0,
    out float4 oPosition : SV_POSITION
)
{
    oPosition = mul(wvpMat, iPosition);
    vTexCoord = iTexCoord;
}

// -------------------------------------------

void overlay_tint_fragment(
    uniform Texture2D diffuseMap : register(t0),
    uniform SamplerState diffuseSam : register(s0),
    uniform float4 overlayColor,

    in float2 vTexCoord : TEXCOORD0,

    out float4 oColor : SV_TARGET
)
{
    float4 texel = diffuseMap.Sample(diffuseSam, vTexCoord);
    oColor = texel * overlayColor;
}
