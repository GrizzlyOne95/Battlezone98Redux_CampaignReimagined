#version 120
// GLSL twin of cr18_swirl-sm4.hlsl's vertex stage.
uniform mat4 wvpMat;
uniform mat4 texMat;
attribute vec4 vertex;
attribute vec4 uv0;
varying vec4 vTex;
varying vec3 vView;

void main()
{
	gl_Position = wvpMat * vertex;
	gl_Position.z = gl_Position.w * 0.9999;
	vView = vertex.xyz;
	vTex.xy = (texMat * vec4(uv0.xy, 0.0, 1.0)).xy;
	vTex.zw = uv0.xy;
}
