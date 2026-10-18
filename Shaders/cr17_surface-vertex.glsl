#version 120

// ISDF Chronicles: OpenGL twin of surface_vertex / surface_caster_vertex in
// cr17_surface.hlsl. See that file for what each output carries.

uniform mat4 wvpMat;

#if defined(CASTER)
uniform vec4 texelOffsets;
#else
uniform mat4 worldViewMat;
#if defined(PARTICLE_COLOUR)
uniform mat4 texMatrix;
#endif
#if defined(SHADOWRECEIVER)
uniform mat4 texWorldViewProj1;
#if defined(PSSM_ENABLED)
uniform mat4 texWorldViewProj2;
uniform mat4 texWorldViewProj3;
#endif
#endif
#endif

attribute vec4 vertex;
attribute vec2 uv0;
#if defined(PARTICLE_COLOUR)
attribute vec4 colour;
#elif !defined(CASTER)
attribute vec3 normal;
#endif

varying vec2 vTexCoord;
#if defined(CASTER)
varying vec2 vCasterDepth;
#else
varying vec4 vViewPos;      // xyz view-space position, w fog depth
varying vec3 vViewNormal;
varying vec3 vObjPos;
#if defined(PARTICLE_COLOUR)
varying vec4 vParticleColour;
#endif
#if defined(SHADOWRECEIVER)
varying vec4 vLightSpacePos1;
#if defined(PSSM_ENABLED)
varying vec4 vLightSpacePos2;
varying vec4 vLightSpacePos3;
#endif
#endif
#endif

void main()
{
	gl_Position = wvpMat * vertex;
	vTexCoord = uv0;

#if defined(CASTER)
	gl_Position.xy += texelOffsets.zw * gl_Position.w;
	vCasterDepth = gl_Position.zw;
#else
	vViewPos.xyz = (worldViewMat * vec4(vertex.xyz, 1.0)).xyz;
	vViewPos.w = gl_Position.z;
#if defined(PARTICLE_COLOUR)
	vTexCoord = (texMatrix * vec4(uv0, 0.0, 1.0)).xy;
	vViewNormal = vec3(0.0, 0.0, 1.0);
	vParticleColour = colour.bgra;
#else
	vViewNormal = (worldViewMat * vec4(normal, 0.0)).xyz;
#endif
	vObjPos = vertex.xyz;
#if defined(SHADOWRECEIVER)
	vLightSpacePos1 = texWorldViewProj1 * vertex;
#if defined(PSSM_ENABLED)
	vLightSpacePos2 = texWorldViewProj2 * vertex;
	vLightSpacePos3 = texWorldViewProj3 * vertex;
#endif
#endif
#endif
}
