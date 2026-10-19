#version 120
// GLSL twin of cr18_swirl-sm4.hlsl's vertex stage.
uniform mat4 wvpMat;
uniform mat4 texMat;
attribute vec4 vertex;
attribute vec4 uv0;
varying vec4 vTex;

void main()
{
	gl_Position = wvpMat * vertex;
	vTex.xy = (texMat * vec4(uv0.xy, 0.0, 1.0)).xy;
	vTex.zw = uv0.xy;
}
