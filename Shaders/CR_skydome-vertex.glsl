#version 120
// GLSL twin of CR_skydome-sm4.hlsl's vertex stage.
uniform mat4 wvpMat;
uniform mat4 inverseProjection;
uniform mat4 inverseView;
uniform mat4 texMat;
uniform vec4 diffuseColor;
attribute vec4 vertex;
attribute vec4 uv0;
varying vec4 vColor;
varying vec2 vTexCoord;
varying vec3 vView;

void main()
{
	gl_Position = wvpMat * vertex;
	vec4 viewPosition = inverseProjection * gl_Position;
	vView = mat3(inverseView) * (viewPosition.xyz / viewPosition.w);
	vColor = diffuseColor;
	vTexCoord = (texMat * vec4(uv0.xy, 0.0, 1.0)).xy;
	gl_Position.z = gl_Position.w * 0.9999;
}
