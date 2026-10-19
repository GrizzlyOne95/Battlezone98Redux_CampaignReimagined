// Shader model 3 twin of cr18_swirl-sm4.hlsl.
void swirl_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 texMat,
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float4 vTex : TEXCOORD0,
	out float4 oPosition : POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	vTex.xy = mul(texMat, float4(iTexCoord, 0, 1)).xy;
	vTex.zw = iTexCoord;
}

float2 turn(float2 p, float a)
{
	float s, c;
	sincos(a, s, c);
	return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void swirl_fragment(
	uniform sampler2D diffuseMap : register(s0),
	uniform float time,
	uniform float4 skyDark,
	uniform float4 skyHot,
	uniform float4 glow,
	uniform float4 swirl,
	uniform float3 fogColour,
	uniform float4 plane,
	in float4 vTex : TEXCOORD0,
	out float4 oColor : COLOR)
{
	float2 q = (vTex.zw - plane.xx) / plane.y;
	float r = length(q);
	float w = 1.0 - saturate(r);
	float phase = time * 6.2831853 / 1000.0;
	float a1 = phase * 8.0 + swirl.x * w * w + 0.35 * sin(phase * 8.0 + r * 5.0);
	float a2 = -phase * 5.0 - 0.6 * swirl.x * w + 0.25 * sin(phase * 4.0 - r * 3.0);
	float d1 = tex2D(diffuseMap, turn(q, a1) * 1.15 + 0.5).a;
	float d2 = tex2D(diffuseMap, turn(q, a2) * 1.85 + 0.37).a;
	float d3 = tex2D(diffuseMap, vTex.xy).a;
	float dens = saturate((d1 + 0.75 * d2 + 0.5 * d3) * (1.5 + 3.5 * skyHot.a));
	float3 col = lerp(skyDark.rgb, skyHot.rgb, dens);
	float pulse = 0.60 + 0.25 * sin(phase * 130.0) + 0.15 * sin(phase * 53.0 + r * 4.0);
	float rim = smoothstep(0.20, 1.05, r);
	col += glow.rgb * glow.a * pulse * (0.35 * rim + 0.85 * dens * (0.4 + 0.6 * rim));
	col = lerp(col, fogColour * 0.8 + glow.rgb * 0.15, smoothstep(0.85, 1.35, r) * 0.65);
	oColor = float4(col, 1.0);
}
