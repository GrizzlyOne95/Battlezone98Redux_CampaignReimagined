#version 120
// GLSL twin of cr17_cloud-sm4.hlsl's fragment stage.
uniform sampler2D diffuseMap;
uniform vec4 tint;
uniform vec3 fogColour;
uniform vec4 horizonBlend;
varying vec2 vTexCoord;
varying vec3 vView;

void main()
{
	vec4 c = texture2D(diffuseMap, vTexCoord);
	gl_FragColor = vec4(mix(c.rgb * tint.rgb, fogColour, tint.a), c.a);
	float elev = vView.y / max(length(vView), 1e-4);
	float horizon = 1.0 - smoothstep(horizonBlend.x, horizonBlend.y, elev);
	gl_FragColor.rgb = mix(gl_FragColor.rgb, fogColour, horizon);
	gl_FragColor.a = mix(gl_FragColor.a, 1.0, horizon);
}
