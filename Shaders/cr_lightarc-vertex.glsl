#version 120

uniform mat4 wvpMat;

attribute vec4 vertex;
attribute vec2 uv0;

varying vec2 vTex;
varying float vDepth;

void main()
{
	gl_Position = wvpMat * vertex;
	vTex = uv0;
	vDepth = gl_Position.z;
}
