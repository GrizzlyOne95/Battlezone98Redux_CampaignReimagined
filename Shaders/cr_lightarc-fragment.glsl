#version 120

uniform sampler2D diffuseMap;
uniform sampler2D emissiveMap;
uniform float time;
uniform vec3 fogColour;
uniform vec4 fogParams;
uniform vec3 sceneAmbient;
uniform vec3 lightDiffuse;

varying vec2 vTex;
varying float vDepth;

float hash21(vec2 p)
{
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p)
{
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float ridge(vec2 p, float seed)
{
	vec2 q = p + vec2(seed * 17.31, seed * 9.77);
	float n = vnoise(q) * 0.65 + vnoise(q * 2.3 + 5.2) * 0.35;
	float r = 1.0 - abs(n * 2.0 - 1.0);
	float r2 = r * r;
	return r2 * r2 * r2;
}

float strike(vec2 p, float t, float rate, float layer)
{
	float s = t * rate;
	float k = floor(s);
	float w = smoothstep(0.55, 1.0, fract(s));
	vec2 drift = vec2(t * 0.35 * (layer + 1.0), -t * 0.5);
	return mix(ridge(p + drift, k + layer * 31.0), ridge(p + drift, k + 1.0 + layer * 31.0), w);
}

void main()
{
	vec3 dif = texture2D(diffuseMap, vTex).rgb;
	vec3 emi = texture2D(emissiveMap, vTex).rgb;
	float peak = max(max(emi.r, emi.g), max(emi.b, 0.02));
	vec3 tint = emi / peak;
	float mask = clamp((dot(emi, vec3(0.3, 0.5, 0.2)) - 0.08) * 5.0, 0.0, 1.0);

	vec2 p = vTex * vec2(2.0, 1.0) * 46.0;
	float bolt = strike(p, time, 7.0, 0.0) + strike(p * 1.9, time, 11.0, 1.0) * 0.65;
	float flick = 0.70 + 0.30 * hash21(vec2(floor(time * 23.0), 3.0));
	float slow = 0.85 + 0.15 * sin(time * 4.3982297);
	vec3 core = mix(tint, vec3(1.0), 0.55);

	vec3 lit = clamp(sceneAmbient + lightDiffuse * 0.6, 0.0, 1.0);
	lit = max(lit, vec3(0.28));
	vec3 col = dif * lit * 0.8;
	col += emi * (0.55 + 0.45 * flick) * slow;
	col += core * bolt * mask * flick * 1.6;

	float fogValue = clamp((vDepth - fogParams.y) * fogParams.w, 0.0, 1.0);
	gl_FragData[0] = vec4(mix(col, fogColour, fogValue), 1.0);
}
