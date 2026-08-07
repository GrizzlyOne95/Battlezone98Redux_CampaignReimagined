// Campaign Reimagined - DX11 overlay compatibility helper.
//
// Panels use the existing CR_UI SM4 vertex shader. This fragment stage restores
// the fixed-function "manual texture colour" behavior that DX9 materials used,
// but in a D3D11-compatible programmable path.

void overlay_tint_fragment(
    uniform Texture2D diffuseMap : register(t0),
    uniform SamplerState diffuseSam : register(s0),
    uniform float4 overlayColor,

    in float4 vColor : COLOR,
    in float2 vTexCoord : TEXCOORD0,

    out float4 oColor : SV_TARGET
)
{
    float4 texel = diffuseMap.Sample(diffuseSam, vTexCoord);
    oColor = texel * vColor * overlayColor;
}
