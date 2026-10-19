// Mission 18 storm sky for Ogre's generated sky plane. Like cr17_cloud it reads
// POSITION and one UV set only: the stock Effect and Sky programs want COLOR0,
// which a sky plane does not have, and D3D11 rejects the input layout.
//
// The plane's raw UV runs 0..tiling (CRStorm18 builds it with tiling 24), so the
// zenith is UV (12, 12) and q = (uv - plane.xx) / plane.y is 0 overhead and
// about 1 at the fogged horizon. Two copies of the cloud art turn about the
// zenith in opposite directions and a third drifts with the material's own
// texture matrix (CRStorm18 drives that with SetMaterialTextureScrollAnimation /
// SetMaterialTextureRotateAnimation), so the deck visibly churns. Cloud
// density is the art's alpha channel (the RGB is flat white).
//
// Palette and glow come from pass colours so Lua can ramp them with the storm:
//   ambient   rgb  clear-sky base (near black red)
//   diffuse   rgb  cloud colour where dense   a  density gain (0..1)
//   emissive  rgb  glow from below            a  glow strength (0..1)
//   specular  r    twist of the spiral (radians at the zenith)
// time_0_x wraps at 1000 s; every spin below is a whole number of turns per
// 1000 s, so the wrap is seamless.
void swirl_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 texMat,
	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float4 vTex : TEXCOORD0,
	out float3 vView : TEXCOORD1,
	out float4 oPosition : SV_POSITION)
{
	oPosition = mul(wvpMat, iPosition);
	// Pinned just inside the far plane: the deck is never far-clipped, so it
	// runs down to its own edge (under a degree above the horizon) instead of
	// ending in a hard line wherever it crosses the far clip.
	oPosition.z = oPosition.w * 0.9999;
	// The sky node sits at the camera, so the object-space position is the
	// view ray; the fragment stage reads its elevation.
	vView = iPosition.xyz;
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
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),
	uniform float time,
	uniform float4 skyDark,
	uniform float4 skyHot,
	uniform float4 glow,
	uniform float4 swirl,
	uniform float3 fogColour,
	uniform float4 plane,
	in float4 vTex : TEXCOORD0,
	in float3 vView : TEXCOORD1,
	out float4 oColor : SV_TARGET)
{
	float2 q = (vTex.zw - plane.xx) / plane.y;
	float r = length(q);
	float w = 1.0 - saturate(r);
	float phase = time * 6.2831853 / 1000.0;
	// Inner cloud turns further than the outer: a spiral, not a spinning disc.
	float a1 = phase * 8.0 + swirl.x * w * w + 0.35 * sin(phase * 8.0 + r * 5.0);
	float a2 = -phase * 5.0 - 0.6 * swirl.x * w + 0.25 * sin(phase * 4.0 - r * 3.0);
	float d1 = diffuseMap.Sample(diffuseSam, turn(q, a1) * 1.15 + 0.5).a;
	float d2 = diffuseMap.Sample(diffuseSam, turn(q, a2) * 1.85 + 0.37).a;
	float d3 = diffuseMap.Sample(diffuseSam, vTex.xy).a;
	float dens = saturate((d1 + 0.75 * d2 + 0.5 * d3) * (1.5 + 3.5 * skyHot.a));
	float3 col = lerp(skyDark.rgb, skyHot.rgb, dens);
	// Fire under the deck: breathes slowly, strongest toward the horizon and
	// inside the dense cloud.
	float pulse = 0.60 + 0.25 * sin(phase * 130.0) + 0.15 * sin(phase * 53.0 + r * 4.0);
	float rim = smoothstep(0.20, 1.05, r);
	col += glow.rgb * glow.a * pulse * (0.35 * rim + 0.85 * dens * (0.4 + 0.6 * rim));
	col = lerp(col, fogColour * 0.8 + glow.rgb * 0.15, smoothstep(0.85, 1.35, r) * 0.65);
	// Sink into the fog colour at the horizon, where the terrain's fog ends, so
	// hills and sky meet without a seam.
	float elev = vView.y / max(length(vView), 1e-4);
	col = lerp(col, fogColour, 1.0 - smoothstep(0.015, 0.14, elev));
	oColor = float4(col, 1.0);
}
