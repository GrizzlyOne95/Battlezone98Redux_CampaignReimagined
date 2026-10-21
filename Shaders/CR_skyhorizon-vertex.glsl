#version 120
// Native sky shares the map's vertex palette; only its low edge meets fog.
uniform mat4 wvpMat;
uniform mat4 worldMat;
uniform vec3 cameraPosition;
attribute vec4 vertex;
attribute vec4 colour;
attribute vec4 uv0;
varying vec4 vColor;
varying vec2 vTexCoord;
varying vec3 vRay;
void main()
{
    gl_Position = wvpMat * vertex;
    gl_Position.z = gl_Position.w * 0.9999;
    vColor = colour;
    vTexCoord = uv0.xy;
    vRay = mat3(worldMat) * (vertex.xyz - cameraPosition);
}
