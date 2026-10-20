#version 120

// URANUS.MAP haze: the planet seen through the overcast. The disc is thinned
// (hazeParams.x opacity), tinted toward the fog colour (hazeTint, mixed by
// hazeParams.y) and faded by a slowly drifting cloud mask taken from the map's
// own cloud alpha (second texture unit, acloud2). hazeParams.z is the drift in
// UV per second; time_0_x wraps at 1000 s, so pick z so z*1000 is a whole number.
// hazeParams.w is how hard the cloud mask covers the disc.

uniform sampler2D diffuseMap;
uniform sampler2D maskMap;
uniform float hazeTime;
uniform vec4 hazeParams;
uniform vec4 hazeTint;

varying vec4 vColor;
varying vec2 vTexCoord;
#ifdef LOGDEPTH_ENABLE
varying float vDepth;
#endif

void main()
{
	vec4 tex = texture2D(diffuseMap, vTexCoord) * vColor;
	vec2 drift = vec2(fract(hazeTime * hazeParams.z), fract(hazeTime * hazeParams.z * 0.37));
	float m = texture2D(maskMap, vTexCoord * 2.5 + drift).a * 0.6
	        + texture2D(maskMap, vTexCoord * 1.3 - drift * 0.6 + 0.37).a * 0.4;
	float cover = clamp(m * hazeParams.w, 0.0, 1.0);
	vec4 oColor;
	oColor.rgb = mix(tex.rgb, hazeTint.rgb, hazeParams.y);
	oColor.a = tex.a * hazeParams.x * mix(1.0, 0.15, cover);
	gl_FragData[0] = oColor;

#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	gl_FragDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
