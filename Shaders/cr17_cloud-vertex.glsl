#version 120
// GLSL twin of cr17_cloud-sm4.hlsl's vertex stage.
uniform mat4 wvpMat;
uniform mat4 texMat;
attribute vec4 vertex;
attribute vec4 uv0;
varying vec2 vTexCoord;

void main()
{
	gl_Position = wvpMat * vertex;
	vTexCoord = (texMat * vec4(uv0.xy, 0.0, 1.0)).xy;
}
