#version 120
// GLSL twin of cr17_cloud-sm4.hlsl's fragment stage.
uniform sampler2D diffuseMap;
uniform vec4 tint;
uniform vec3 fogColour;
varying vec2 vTexCoord;

void main()
{
	vec4 c = texture2D(diffuseMap, vTexCoord);
	gl_FragColor = vec4(mix(c.rgb * tint.rgb, fogColour, tint.a), c.a);
}
