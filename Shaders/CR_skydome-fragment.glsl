#version 120
// GLSL twin of CR_skydome-sm4.hlsl's fragment stage.
uniform sampler2D diffuseMap;
uniform vec3 fogColour;
uniform vec4 fogParams;
varying vec4 vColor;
varying vec2 vTexCoord;
varying float vDepth;

void main()
{
	vec4 c = texture2D(diffuseMap, vTexCoord) * vColor;
	float fogValue = clamp((vDepth - fogParams.y) * fogParams.w, 0.0, 1.0);
	gl_FragColor = vec4(mix(c.rgb, fogColour, fogValue), c.a);
}
