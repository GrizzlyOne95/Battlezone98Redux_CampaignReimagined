#version 120
#extension GL_ARB_shader_texture_lod : enable
// GLSL twin of CR_catalogsky-sm4.hlsl's fragment stage. The star index is
// point-sampled without mip filtering, so a plain lookup reads level 0.
uniform sampler2D starIndex;
uniform sampler2D milkyWay;
uniform mat4 skyRotation;
uniform vec4 starParams;
uniform vec4 starShape;
uniform vec4 milkyParams;
varying vec3 vDir;

const float CELLS = 512.0;
const float OFFSET_RANGE = 2.0;
const float MAG_LIMIT = 8.0;
const float MAG_STEP = 24.0;
const float BV_MIN = -0.5;
const float BV_SPAN = 2.5;
const float PI = 3.14159265;

vec3 sky_decode(vec3 c)
{
	c = max(c, 0.0); return mix(c / 12.92, pow((c + .055) / 1.055, vec3(2.4)), step(.04045, c));
}
vec3 sky_encode(vec3 c)
{
	c = max(c, 0.0); return mix(c * 12.92, 1.055 * pow(max(c, 1e-8), vec3(1.0 / 2.4)) - .055, step(.0031308, c));
}

vec3 star_colour(float bv)
{
	vec3 c = mix(vec3(0.62, 0.72, 1.00), vec3(0.92, 0.95, 1.00), clamp((bv + 0.3) / 0.3, 0.0, 1.0));
	c = mix(c, vec3(1.00, 0.96, 0.88), clamp(bv / 0.6, 0.0, 1.0));
	c = mix(c, vec3(1.00, 0.80, 0.58), clamp((bv - 0.6) / 0.4, 0.0, 1.0));
	return mix(c, vec3(1.00, 0.58, 0.32), clamp((bv - 1.0) / 0.6, 0.0, 1.0));
}

void main()
{
	vec3 d = normalize(mat3(skyRotation) * vDir);
	float pixelAngle = max(max(length(dFdx(d)), length(dFdy(d))), 1e-6);

	vec3 ad = abs(d);
	vec3 n, u, v;
	float face;
	if (ad.x >= ad.y && ad.x >= ad.z) { n = vec3(sign(d.x), 0.0, 0.0); u = vec3(0.0, 1.0, 0.0); v = vec3(0.0, 0.0, 1.0); face = d.x < 0.0 ? 1.0 : 0.0; }
	else if (ad.y >= ad.z)            { n = vec3(0.0, sign(d.y), 0.0); u = vec3(0.0, 0.0, 1.0); v = vec3(1.0, 0.0, 0.0); face = d.y < 0.0 ? 3.0 : 2.0; }
	else                              { n = vec3(0.0, 0.0, sign(d.z)); u = vec3(1.0, 0.0, 0.0); v = vec3(0.0, 1.0, 0.0); face = d.z < 0.0 ? 5.0 : 4.0; }
	float major = dot(d, n);
	vec2 uv = vec2(dot(d, u), dot(d, v)) / major;
	vec2 cell = clamp(floor((uv * 0.5 + 0.5) * CELLS), 0.0, CELLS - 1.0);
	vec4 texel = texture2D(starIndex, vec2((cell.x + 0.5) / CELLS, (face * CELLS + cell.y + 0.5) / (6.0 * CELLS)));

	vec3 stars = vec3(0.0);
	if (texel.b > 0.0)
	{
		vec2 starCell = cell + 0.5 + (texel.rg * 2.0 - 1.0) * OFFSET_RANGE;
		vec2 starUv = starCell / CELLS * 2.0 - 1.0;
		vec3 starDir = normalize(n + starUv.x * u + starUv.y * v);
		float r = length(d - starDir) / pixelAngle;
		float mag = MAG_LIMIT - (texel.b * 255.0 - 1.0) / MAG_STEP;
		float flux = pow(10.0, -0.4 * starShape.x * (mag - starParams.w));
		float sigma = starParams.y;
		float core = exp(-0.5 * r * r / (sigma * sigma)) / (2.0 * PI * sigma * sigma);
		float halo = starParams.z * exp(-r / starShape.y);
		stars = star_colour(texel.a * BV_SPAN + BV_MIN) * flux * starParams.x * (core + halo);
	}

	float ra = atan(d.y, d.x) / (2.0 * PI);
	float dec = asin(clamp(d.z, -1.0, 1.0)) / PI;
	vec2 mwUv = vec2(fract(milkyParams.z + milkyParams.y * ra), 0.5 - dec);
#ifdef GL_ARB_shader_texture_lod
	vec2 gx = dFdx(mwUv), gy = dFdy(mwUv);
	gx.x -= floor(gx.x + 0.5); gy.x -= floor(gy.x + 0.5);
	vec3 milky = sky_decode(texture2DGradARB(milkyWay, mwUv, gx, gy).rgb) * milkyParams.x;
#else
	vec3 milky = sky_decode(texture2D(milkyWay, mwUv).rgb) * milkyParams.x;
#endif

	gl_FragColor = vec4(sky_encode(milky + stars), 1.0);
}
