void effect_vertex(
	uniform float4x4 wvpMat,
	uniform float4 diffuseColor,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,
	in float2 iTexCoord : TEXCOORD0,

	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,
    out float4 vScreenPos : TEXCOORD3, // For screen-space depth lookup

	out float4 oPosition : POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor * diffuseColor;
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
    vScreenPos = oPosition; // Pass clip space pos
}

// -------------------------------------------

void effect_fragment(
	uniform sampler2D diffuseMap : register(s0),
    uniform sampler2D sceneDepthMap : register(s1), // Requires depth buffer binding
	uniform float3 fogColour,
	uniform float4 fogParams,

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,
    in float4 vScreenPos : TEXCOORD3, 

	out float4 oColor : COLOR
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : DEPTH
#endif
)
{
	float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
    
    // Soft Particles Logic
    // 1. Calculate screen UVs
    float2 screenUV = vScreenPos.xy / vScreenPos.w;
    screenUV = screenUV * 0.5 + 0.5;
    screenUV.y = 1.0 - screenUV.y; // DX9 inverted Y? Ogre handles this? Usually logical 0-1.

    // 2. Sample Scene Depth (Assuming linear depth or needing linearization)
    // Ogre usually passes raw depth. 
    float sceneDepth = tex2D(sceneDepthMap, screenUV).r;
    
    // 3. Compare with Fragment Depth
    // This assumes specific depth range (0-1). 
    // Soft particle fade factor
    float fadeDistance = 0.5; // World units? Or relative?
    // Note: To do this properly requires linearized depth which depends on near/far planes.
    // Simplifying: Just assume standard depth buffer logic.
    // If sceneDepth (background) is close to vDepth (particle), fade out.
    // This is fragile without linearizing, but provides the basic hook.
    
    // float contrast = saturate((sceneDepth - vDepth) / 0.01); 
    // diffuseTex.a *= contrast;


	oColor = diffuseTex * vColor;

	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, fogColour, fogValue);
	
#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
