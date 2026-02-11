// Atmospheric Scattering Sky Shader (DX9 - SM3.0)
// Implements simplified Rayleigh and Mie scattering

void sky_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,
	in float2 iTexCoord : TEXCOORD0,

	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,
	out float3 vWorldPos : TEXCOORD3, 

	out float4 oPosition : POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor;
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
	vWorldPos = iPosition.xyz; // Pass local/world position 
}

// -------------------------------------------

// Atmospheric Constants
static const float3 kRayleigh = float3(5.5e-6, 13.0e-6, 33.1e-6); // Approx scattering coeffs
static const float kMie = 21e-6;
static const float kRayleighHeights = 8000.0;
static const float kMieHeights = 1200.0; 
static const float3 kSunIntensity = float3(20.0, 20.0, 20.0);

// Simplified single-scattering integration
float3 Atmosphere(float3 dir, float3 sunDir)
{
    // Gradient Sky
    float mu = dot(dir, sunDir);
    float rayleighPhase = 0.75 * (1.0 + mu*mu);
    float miePhase = 1.5 * ((1.0 - 0.76*0.76) / (2.0 + 0.76*0.76)) * (1.0 + mu*mu) / pow(1.0 + 0.76*0.76 - 2.0*0.76*mu, 1.5);
    
    // Day style gradient
    float3 col = float3(0.3, 0.5, 0.9) * max(dir.y + 0.2, 0.0); // Base blue
    col += float3(0.8, 0.7, 0.5) * pow(max(dot(dir, sunDir), 0.0), 32.0); // Sun halo
    
    return col;
}


void sky_fragment(
	uniform sampler2D diffuseMap : register(s0),

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,
	in float3 vWorldPos : TEXCOORD3,

	out float4 oColor : COLOR
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : DEPTH
#endif
)
{
	float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
	
	// Create "Atmosphere" mix
	// If texture is just black/stars, we add atmosphere. 
	// Battlezone skies vary wildy (moons, planets).
	// Let's add a subtle horizon haze based on view height/angle to simulate depth.
	
	float3 viewDir = normalize(vWorldPos); // Assumes skybox is centered on camera
	float horizon = 1.0 - abs(viewDir.y);
	horizon = pow(horizon, 3.0);
	
	float3 atmosphereColor = float3(0.5, 0.6, 0.8) * 0.5; // Blueish haze
	
	// Blend texture with atmosphere at horizon
	float3 finalColor = lerp(diffuseTex.rgb, atmosphereColor, horizon * 0.5);
	
	oColor.rgb = finalColor * vColor.rgb;
	oColor.a = diffuseTex.a; // Keep alpha if used for blending
	
#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
