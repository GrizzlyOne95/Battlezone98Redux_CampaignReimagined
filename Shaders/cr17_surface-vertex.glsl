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

#if defined(WIND)
// Foliage wind: see WindDisplace in cr17_surface.hlsl.
uniform mat4 worldMat;
uniform mat4 invWorldMat;
uniform float windTime;
uniform vec4 windParams;
uniform vec4 windShape;
attribute vec4 uv1;

vec4 WindDisplace(vec4 objPos, vec2 weight)
{
	float speed = length(windParams.xz);
	if (speed < 0.01 || windParams.w <= 0.0)
		return objPos;
	vec3 worldPos = (worldMat * objPos).xyz;
	vec2 dir = windParams.xz / speed;
	float amp = clamp(speed / 20.0, 0.0, 1.0) * (1.0 + 0.6 * windParams.y) * windParams.w;
	float phase = dot(worldPos.xz, vec2(0.083, 0.061));
	float sway = 0.6 + 0.4 * sin(windTime * windShape.y + phase);
	vec3 offset = vec3(dir.x, 0.0, dir.y) * (windShape.x * weight.x * amp * sway);
	float f = windTime * windShape.w;
	offset += (windShape.z * weight.y * amp) * vec3(
		sin(f + phase * 5.3 + worldPos.y * 0.9),
		0.5 * sin(f * 1.37 + phase * 3.1),
		cos(f * 0.83 + phase * 4.7 + worldPos.x * 0.7));
	objPos.xyz += mat3(invWorldMat) * offset;
	return objPos;
}
#endif

void main()
{
#if defined(WIND)
	vec4 position = WindDisplace(vertex, uv1.xy);
#else
	vec4 position = vertex;
#endif
	gl_Position = wvpMat * position;
	vTexCoord = uv0;

#if defined(CASTER)
	gl_Position.xy += texelOffsets.zw * gl_Position.w;
	vCasterDepth = gl_Position.zw;
#else
	vViewPos.xyz = (worldViewMat * vec4(position.xyz, 1.0)).xyz;
	vViewPos.w = gl_Position.z;
#if defined(PARTICLE_COLOUR)
	vTexCoord = (texMatrix * vec4(uv0, 0.0, 1.0)).xy;
	vViewNormal = vec3(0.0, 0.0, 1.0);
	vParticleColour = colour.bgra;
#else
	vViewNormal = (worldViewMat * vec4(normal, 0.0)).xyz;
#endif
	vObjPos = position.xyz;
#if defined(SHADOWRECEIVER)
	vLightSpacePos1 = texWorldViewProj1 * position;
#if defined(PSSM_ENABLED)
	vLightSpacePos2 = texWorldViewProj2 * position;
	vLightSpacePos3 = texWorldViewProj3 * position;
#endif
#endif
#endif
}
