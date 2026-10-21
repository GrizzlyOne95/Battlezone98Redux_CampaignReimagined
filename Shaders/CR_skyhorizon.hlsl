// Native atmospheric sky: preserve map art/vertex palette, meet fog smoothly.
void horizon_vertex(
 uniform float4x4 wvpMat, uniform float4x4 worldMat, uniform float3 cameraPosition,
 in float4 iPosition : POSITION, in float4 iColor : COLOR0, in float2 iTexCoord : TEXCOORD0,
 out float4 vColor : COLOR0, out float2 vTexCoord : TEXCOORD0, out float3 vRay : TEXCOORD1,
 out float4 oPosition : POSITION)
{
 oPosition=mul(wvpMat,iPosition);
 oPosition.z=oPosition.w*0.9999;
 vColor=iColor;
 vTexCoord=iTexCoord;
 vRay=mul((float3x3)worldMat,iPosition.xyz-cameraPosition);
}
void horizon_fragment(
 uniform sampler2D diffuseMap : register(s0),
 uniform float3 fogColour, uniform float4 fogParams, uniform float4 horizonBlend,
 in float4 vColor : COLOR0, in float2 vTexCoord : TEXCOORD0, in float3 vRay : TEXCOORD1,
 out float4 oColor : COLOR)
{
 oColor=tex2D(diffuseMap,vTexCoord)*vColor;
 float elevation=vRay.y/max(length(vRay),1e-4);
 float blend=(1-smoothstep(horizonBlend.x,horizonBlend.y,elevation))*horizonBlend.z;
 blend*=step(1e-8,fogParams.w);
 oColor.rgb=lerp(oColor.rgb,fogColour,blend);
}
