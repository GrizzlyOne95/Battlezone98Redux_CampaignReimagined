#version 120
// GLSL twin of CR_skydome-sm4.hlsl's fragment stage.
uniform sampler2D diffuseMap;
uniform vec3 fogColour;
uniform vec4 fogParams;
uniform vec4 horizonBlend;
varying vec4 vColor;
varying vec2 vTexCoord;
varying vec3 vView;

void main()
{
	vec4 c = texture2D(diffuseMap, vTexCoord) * vColor;
	float elevation = vView.y / max(length(vView), 1e-4);
	float fogValue = (1.0-smoothstep(horizonBlend.x, horizonBlend.y, elevation)) * horizonBlend.z * step(1e-8, fogParams.w);
	gl_FragColor = vec4(mix(c.rgb, fogColour, fogValue), c.a);
}
