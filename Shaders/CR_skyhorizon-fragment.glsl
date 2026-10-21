#version 120
uniform sampler2D diffuseMap;
uniform vec3 fogColour;
uniform vec4 fogParams;
uniform vec4 horizonBlend;
varying vec4 vColor;
varying vec2 vTexCoord;
varying vec3 vRay;
void main()
{
    vec4 c = texture2D(diffuseMap, vTexCoord) * vColor;
    float elevation = vRay.y / max(length(vRay), 1e-4);
    float blend = (1.0 - smoothstep(horizonBlend.x, horizonBlend.y, elevation)) * horizonBlend.z;
    blend *= step(1e-8, fogParams.w);
    gl_FragColor = vec4(mix(c.rgb, fogColour, blend), c.a);
}
