// Campaign Reimagined: procedural rain that runs over the cockpit glass.
//
// Drawn as the last pass of CRWX_CockpitGlass_R_W<a>C<b> on the generated glass
// submesh (Tools/cockpitglass.py). That glass's UVs are view angles in the
// eye frame (u = 0.5 + yaw / 96 deg, v = 0.5 - pitch / 64 deg; x right, y up,
// z forward), so the vertex program rebuilds each vertex's view ray from its
// UV and never needs the mesh's own axes.
//
// Flow, per vertex (smooth, so no seams at glass triangle edges):
//   the glass is modelled as a raked windshield whose outward normal is
//   normalize(ray + rake * up). Air (airflow, the craft's air-relative
//   velocity in the craft frame) and gravity are projected onto that surface.
//   Drops cling until the tangential air speed passes a threshold, then run
//   with it; below the stagnation point (about 27 deg under the nose at rake
//   0.5) they run down and out, above it up and out, so streaks diverge
//   from the travel direction instead of all scrolling the same way.
// Drops, per pixel (flow-map advection, as water flow maps do):
//   two copies of a hashed drop field, offset by half a period and
//   crossfaded, are advected along the flow. Each period re-seeds the hash, so
//   the pattern never repeats. Drops stretch and leave trails with speed and
//   stick-slip along the flow. A second, finer field runs faster.
// Beads: still drops that form and evaporate cell by cell, stripped off where
//   the air drags drops along. Density follows how squarely rain hits the glass.
// Shading: dark body, bright refracted rim from the height field's screen-space
//   gradient. Pass diffuse alpha (set by CRWetGlass.lua) is the rain intensity.
//
// SM4 (DX11) by default; SM3 (DX9) with SM3 defined.

#ifdef SM3
#define POS_OUT POSITION
#define COLOUR_OUT COLOR
#else
#define POS_OUT SV_Position
#define COLOUR_OUT SV_Target
#endif

static const float DEG = 0.0174532925;
static const float CELLS = 14.0;     // main drop cells per 64 deg of view
static const float PERIOD = 1.6;     // seconds per advection phase

float4x4 wvpMat;
float4 airflow;      // xyz: air velocity past the craft, craft frame (x right, y up, z front), m/s
float4 gravity;      // xyz: gravity direction, craft frame; w: rain fall speed, m/s
float4 flowParams;   // x: rake, y/z: tangential air speed drops start/finish breaking loose, w: top speed, cells/s
float4 surfaceDiffuse;  // a: rain intensity (pass diffuse alpha)
float time;
float4 rainTint;     // rgb: water colour (clear or acid), a: overall opacity

struct VOut
{
	float4 pos : POS_OUT;
	float2 p : TEXCOORD0;      // drop space: main cells, isotropic in view angle
	float2 flow : TEXCOORD1;   // drop velocity, main cells per second
	float2 misc : TEXCOORD2;   // x: impact (0..1), y: cling broken (0..1)
};

VOut flow_vertex(float4 position : POSITION, float2 uv : TEXCOORD0)
{
	VOut o;
	o.pos = mul(wvpMat, position);
	o.p = uv * float2(96.0 / 64.0, 1.0) * CELLS;

	float yaw = (uv.x - 0.5) * 96.0 * DEG;
	float pit = (0.5 - uv.y) * 64.0 * DEG;
	float cy = cos(yaw), sy = sin(yaw), cp = cos(pit), sp = sin(pit);
	float3 d = float3(cp * sy, sp, cp * cy);
	float3 eYaw = float3(cy, 0.0, -sy);
	float3 ePitch = float3(-sp * sy, cp, -sp * cy);
	float3 n = normalize(d + float3(0.0, flowParams.x, 0.0));

	float3 a = airflow.xyz;
	float3 at = a - n * dot(a, n);
	float aSpeed = length(at);
	float broken = smoothstep(flowParams.y, flowParams.z, aSpeed);
	float3 g = gravity.xyz;
	float3 gt = g - n * dot(g, n);
	float3 F = gt * 0.3 + at / max(aSpeed, 0.001) * broken * flowParams.w * saturate(aSpeed / 60.0 + 0.35);

	// Glass-surface motion to view-angle motion: +x is +yaw, +y is -pitch.
	o.flow = float2(dot(F, eYaw) / max(cp, 0.2), -dot(F, ePitch));

	float3 rain = a + g * gravity.w;
	o.misc = float2(saturate(-dot(rain, n) / max(length(rain), 0.001)), broken);
	return o;
}

float4 hash4(float2 p)
{
	float4 p4 = frac(p.xyxy * float4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return frac((p4.xxyz + p4.yzzw) * p4.zywx);
}

float2 rot(float2 v, float a)
{
	float c = cos(a), s = sin(a);
	return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// One hashed drop per cell, kept inside its cell. dir: unit flow direction;
// mv: 0 still .. 1 running.
float drop_field(float2 q, float2 dir, float mv, float2 seed, float dens, float t)
{
	float2 cell = floor(q);
	float2 f = frac(q) - 0.5;
	float4 h = hash4(cell + seed);
	float on = saturate((dens - h.x) * 12.0);

	float s = t * (0.5 + 1.5 * h.y) + h.z * 7.0;
	float lag = floor(s) + smoothstep(0.7, 1.0, frac(s)) - s;   // -0.7..0: hang, then slip
	float2 l = f - (h.zw - 0.5) * 0.2 - dir * (lag * 0.13 * mv);
	float along = dot(l, dir);
	float across = dot(l, float2(-dir.y, dir.x));

	float r = lerp(0.07, 0.13, h.y);
	float stretch = 1.0 + mv;
	float body = 1.0 - smoothstep(r * 0.55, r, length(float2(across, along / stretch)));

	float tail = 0.2 * mv;
	float k = saturate(-along / max(tail, 0.001));               // 0 at the drop, 1 at the tail end
	float w = r * 0.35 * (1.0 - k) + 0.002;
	float trail = step(along, 0.0) * (1.0 - k) * (1.0 - smoothstep(w * 0.5, w, abs(across)));
	return on * max(body, trail * 0.6 * mv);
}

float4 flow_fragment(
#ifndef SM3
	float4 pos : SV_Position,
#endif
	float2 p : TEXCOORD0, float2 flow : TEXCOORD1, float2 misc : TEXCOORD2) : COLOUR_OUT
{
	float intensity = surfaceDiffuse.a;
	float spd = length(flow);
	float2 dir = flow / max(spd, 0.0001);
	float mv = saturate(spd / 1.5);
	float dens = intensity * (0.3 + 0.7 * misc.x);

	float H = 0.0;
	[unroll] for (int i = 0; i < 2; i++)
	{
		float ph = time / PERIOD + 0.5 * i;
		float cyc = floor(ph);
		ph = frac(ph);
		float w = 1.0 - abs(2.0 * ph - 1.0);
		float2 seed = frac(float2(cyc * 0.6180, cyc * 0.4142 + 0.37 * i)) * 997.0;
		float2 q1 = rot(p, 0.31) - rot(flow, 0.31) * (ph - 0.5) * PERIOD;
		float2 q2 = rot(p * 2.3, -0.47) - rot(flow, -0.47) * (2.3 * 1.4) * (ph - 0.5) * PERIOD;
		float d1 = drop_field(q1, rot(dir, 0.31), mv, seed, dens, time);
		float d2 = drop_field(q2, rot(dir, -0.47), mv, seed + 113.0, dens * 0.8, time * 1.4);
		H += w * max(d1, 0.7 * d2);
	}
	H *= lerp(0.45, 1.0, mv);

	// Beads: still drops with their own life, blown away once the air breaks them loose.
	float2 qb = rot(p * 1.6, 0.9);
	float2 cb = floor(qb);
	float4 hb = hash4(cb + 57.0);
	float life = time * lerp(0.07, 0.18, hb.y) + hb.x * 13.0;
	float4 hl = hash4(cb + floor(life) * 3.17);
	float fade = smoothstep(0.0, 0.12, frac(life)) * (1.0 - smoothstep(0.7, 1.0, frac(life)));
	float rb = lerp(0.06, 0.17, hl.y);
	float bead = 1.0 - smoothstep(rb * 0.5, rb, length(frac(qb) - 0.5 - (hl.zw - 0.5) * 0.4));
	H = max(H, bead * fade * saturate((dens - hl.x) * 12.0) * (1.0 - misc.y));

	// Refraction look: drops darken what is behind them; the edge that faces down catches the sky.
	float rim = saturate(-ddy(H) * 3.0 + abs(ddx(H)) * 0.8);
	float3 col = lerp(rainTint.rgb * 0.3, rainTint.rgb * 1.2 + 0.25, rim);
	float alpha = saturate(H * 0.4 + rim * 0.7) * rainTint.a;
	return float4(col, alpha);
}
