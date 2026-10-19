#version 120
// GLSL twin of cr18_swirl-sm4.hlsl's fragment stage.
uniform sampler2D diffuseMap;
uniform float time;
uniform vec4 skyDark;
uniform vec4 skyHot;
uniform vec4 glow;
uniform vec4 swirl;
uniform vec3 fogColour;
uniform vec4 plane;
varying vec4 vTex;
varying vec3 vView;

vec2 turn(vec2 p, float a)
{
	float s = sin(a);
	float c = cos(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void main()
{
	vec2 q = (vTex.zw - plane.xx) / plane.y;
	float r = length(q);
	float w = 1.0 - clamp(r, 0.0, 1.0);
	float phase = time * 6.2831853 / 1000.0;
	float a1 = phase * 8.0 + swirl.x * w * w + 0.35 * sin(phase * 8.0 + r * 5.0);
	float a2 = -phase * 5.0 - 0.6 * swirl.x * w + 0.25 * sin(phase * 4.0 - r * 3.0);
	float d1 = texture2D(diffuseMap, turn(q, a1) * 1.15 + 0.5).a;
	float d2 = texture2D(diffuseMap, turn(q, a2) * 1.85 + 0.37).a;
	float d3 = texture2D(diffuseMap, vTex.xy).a;
	float dens = clamp((d1 + 0.75 * d2 + 0.5 * d3) * (1.5 + 3.5 * skyHot.a), 0.0, 1.0);
	vec3 col = mix(skyDark.rgb, skyHot.rgb, dens);
	float pulse = 0.60 + 0.25 * sin(phase * 130.0) + 0.15 * sin(phase * 53.0 + r * 4.0);
	float rim = smoothstep(0.20, 1.05, r);
	col += glow.rgb * glow.a * pulse * (0.35 * rim + 0.85 * dens * (0.4 + 0.6 * rim));
	col = mix(col, fogColour * 0.8 + glow.rgb * 0.15, smoothstep(0.85, 1.35, r) * 0.65);
	float elev = vView.y / max(length(vView), 1e-4);
	col = mix(col, fogColour, 1.0 - smoothstep(0.015, 0.14, elev));
	gl_FragColor = vec4(col, 1.0);
}
