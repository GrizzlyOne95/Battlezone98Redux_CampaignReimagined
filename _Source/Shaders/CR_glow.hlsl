static const half gaussSamples13[13] =
{
   0.002216,
   0.008764,
   0.026995,
   0.064759,
   0.120985,
   0.176033,
   0.199471,
   0.176033,
   0.120985,
   0.064759,
   0.026995,
   0.008764,
   0.002216
};

#if defined(GLOW_TAPS_7)
static const int kGlowTapCount = 7;
static const int kGlowTapStart = 3;
#elif defined(GLOW_TAPS_9)
static const int kGlowTapCount = 9;
static const int kGlowTapStart = 2;
#else
static const int kGlowTapCount = 13;
static const int kGlowTapStart = 0;
#endif

float4 downsample(
		uniform sampler2D  rt : register(s0),

		uniform float4 invMapSize,

		float2 uv: TEXCOORD0
	) : COLOR
{
	half4 colOut = tex2D(rt, uv + invMapSize.xy);
	const half3 lumaW = half3(0.299, 0.587, 0.114);
	const half glowThreshold = 0.62;
	const half glowKnee = 0.28;
	half luma = dot(colOut.rgb, lumaW);
	half glowMask = saturate((luma - glowThreshold) / glowKnee);
	glowMask = glowMask * glowMask * (3.0 - 2.0 * glowMask);
	colOut.rgb *= colOut.rgb;
	colOut.rgb *= glowMask;
	return colOut;
}

float4 blurH(
		uniform sampler2D  rt : register(s0),

		uniform float4 invMapSize,
		uniform float scaleGlowOffset,

		float2 uv: TEXCOORD0
	) : COLOR
{
   half4 colOut = half4(0, 0, 0, 0);
   for (int i = 0; i < kGlowTapCount; i++)
   {
      int tap = i + kGlowTapStart;
      colOut += tex2D(rt, uv + float2(float(tap - 6) * scaleGlowOffset, 0.5) * invMapSize.xy) * gaussSamples13[tap];
   }
   return colOut;
}

float4 blurV(
		uniform sampler2D  rt : register(s0),

		uniform float4 invMapSize,
		uniform float scaleGlowOffset,

		float2 uv: TEXCOORD0
	) : COLOR
{
   half4 colOut = half4(0, 0, 0, 0);
   for (int i = 0; i < kGlowTapCount; i++)
   {
      int tap = i + kGlowTapStart;
      colOut += tex2D(rt, uv + float2(0.5, float(tap - 6) * scaleGlowOffset) * invMapSize.xy) * gaussSamples13[tap];
   }
   return colOut;
}

float4 main_ps(
		uniform sampler2D scene: register(s0),
		uniform sampler2D blurX: register(s1),

		uniform float glowPower,

		float2 uv: TEXCOORD0
	) : COLOR
{
	float4 sceneTex = tex2D(scene, uv);
	float3 blurTex = tex2D(blurX, uv).rgb;
	blurTex = blurTex / (1.0 + blurTex * 0.8);
	return float4(sceneTex.rgb + blurTex * glowPower, sceneTex.a);
}
