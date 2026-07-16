#version 120

uniform sampler2D diffuseMap;
uniform float twinkleTime;
uniform vec4 twinkleControl;

varying vec4 vColor;
varying vec2 vTexCoord;
#ifdef LOGDEPTH_ENABLE
varying float vDepth;
#endif

void main()
{
	vec4 diffuseTex = texture2D(diffuseMap, vTexCoord);
	vec4 oColor = diffuseTex * vColor;

	// STARS.MAP enables this through its otherwise-unused emissive pass color.
	// Quantized UVs give nearby star pixels a stable phase without shimmering
	// when the camera moves.
	vec2 starCell = floor(vTexCoord * 512.0);
	float starSeed = fract(sin(dot(starCell, vec2(12.9898, 78.233))) * 43758.5453);
	float twinkleWave = 0.5 + 0.5 * sin(twinkleTime * (0.9 + starSeed * 1.7) + starSeed * 6.2831853);
	float twinkleStrength = clamp(max(max(twinkleControl.x, twinkleControl.y), twinkleControl.z), 0.0, 1.0);
	float twinkle = mix(1.0, mix(0.72, 1.12, twinkleWave), twinkleStrength);
	oColor.rgb *= twinkle;

	gl_FragData[0] = oColor;

#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	gl_FragDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
