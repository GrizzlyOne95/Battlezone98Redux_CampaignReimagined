#version 120
// GLSL twin of CR_catalogsky-sm4.hlsl's vertex stage.
uniform mat4 wvpMat;
attribute vec4 vertex;
varying vec3 vDir;

void main()
{
	gl_Position = wvpMat * vertex;
	gl_Position.z = gl_Position.w * 0.9999;
	vDir = vertex.xyz;
}
