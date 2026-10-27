#version 120

uniform mat4 wvpMat;

attribute vec4 vertex;
attribute vec2 uv0;

#if defined(WIND)
// Wind-swayed foliage cards: see textured_wind_vertex in CR_textured-sm4.hlsl.
uniform mat4 worldMat;
uniform mat4 invWorldMat;
uniform float windTime;
uniform vec4 windParams;
uniform vec4 windShape;
attribute vec4 uv1;
#endif

varying vec2 vTexCoord;
varying float vDepth;

void main()
{
	vec4 position = vertex;
#if defined(WIND)
	float speed = length(windParams.xz);
	if (speed >= 0.01 && windParams.w > 0.0)
	{
		vec3 worldPos = (worldMat * position).xyz;
		vec2 dir = windParams.xz / speed;
		float amp = clamp(speed / 20.0, 0.0, 1.0) * (1.0 + 0.6 * windParams.y) * windParams.w;
		float phase = dot(worldPos.xz, vec2(0.083, 0.061));
		float sway = 0.6 + 0.4 * sin(windTime * windShape.y + phase);
		vec3 offset = vec3(dir.x, 0.0, dir.y) * (windShape.x * uv1.x * amp * sway);
		float f = windTime * windShape.w;
		offset += (windShape.z * uv1.y * amp) * vec3(
			sin(f + phase * 5.3 + worldPos.y * 0.9),
			0.5 * sin(f * 1.37 + phase * 3.1),
			cos(f * 0.83 + phase * 4.7 + worldPos.x * 0.7));
		position.xyz += mat3(invWorldMat) * offset;
	}
#endif
	gl_Position = wvpMat * position;
	vTexCoord = uv0;
	vDepth = gl_Position.z;
}
