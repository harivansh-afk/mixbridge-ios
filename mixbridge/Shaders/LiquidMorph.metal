//
//  LiquidMorph.metal
//  mixbridge
//
//  Liquid Glass Peel shader for crossfade artwork transitions.
//  The "from" artwork peels away along a noisy curved front, revealing the "to" artwork beneath.
//  A subtle refraction field and edge highlight make it feel like thin liquid glass (not a wipe).
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Shader

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Fullscreen triangle vertex shader (more efficient than quad)
vertex VertexOut liquidMorphVertex(uint vid [[vertex_id]]) {
    // Fullscreen triangle positions
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    // Corresponding UV coordinates
    float2 uvs[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0)
    };

    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.texCoord = uvs[vid];
    return out;
}

// MARK: - Noise Functions

// Hash function for noise generation
float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Value noise
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);

    // Smooth interpolation (quintic for smoother glass-like curves)
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion - layered noise for organic glass-like patterns
float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return value;
}

// Simplex-like gradient for smoother caustics - temporally stable
float2 gradientNoise(float2 p, float time) {
    float2 i = floor(p);
    float2 f = fract(p);

    // Quintic interpolation for smoother results
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    // Static noise base - no time jitter
    float n1 = hash21(i + float2(0.0, 0.0));
    float n2 = hash21(i + float2(1.0, 0.0));
    float n3 = hash21(i + float2(0.0, 1.0));
    float n4 = hash21(i + float2(1.0, 1.0));

    float nx = mix(mix(n1, n2, u.x), mix(n3, n4, u.x), u.y);
    float ny = mix(mix(n3, n1, u.x), mix(n4, n2, u.x), u.y);

    // Gentle time-based modulation instead of position shift
    float timeWave = sin(time * 0.3) * 0.15;
    return (float2(nx, ny) * 2.0 - 1.0) * (0.85 + timeWave);
}

// Viscous drip stripe pattern - creates multiple defined drip channels
float dripStripes(float x, float y, float time, float stripeCount) {
    // Base stripe pattern
    float stripes = sin(x * M_PI_F * stripeCount) * 0.5 + 0.5;

    // Add variation to stripe widths using noise
    float variation = noise(float2(x * stripeCount * 0.5, 0.0)) * 0.3;
    stripes = pow(stripes + variation, 1.5);

    // Drip speed varies per stripe - some drip faster (viscosity)
    float dripPhase = noise(float2(x * stripeCount, 1.0)) * 0.4;
    float dripLength = y + sin(x * stripeCount * M_PI_F + time * 0.5) * 0.08 + dripPhase;

    // Combine for viscous drip shape
    return stripes * smoothstep(0.0, 0.15, dripLength);
}

// Depth shading for viscous liquid - darker at edges, lighter at center
float viscosityDepth(float stripe, float edgeDist) {
    // Thicker at center of drip, thinner at edges
    float thickness = pow(stripe, 0.7);
    // Shadow at the edges of each drip
    float edgeShadow = 1.0 - pow(abs(stripe - 0.5) * 2.0, 2.0) * 0.3;
    return thickness * edgeShadow;
}

// MARK: - Uniforms

struct LiquidMorphUniforms {
    float progress;     // Crossfade progress 0.0 to 1.0
    float time;         // Time for animation
    float amplitude;    // Max displacement strength
    float frequency;    // Noise pattern density
};

// MARK: - Fragment Shader: Liquid Glass Peel

fragment float4 liquidMorphFragment(
    VertexOut in [[stage_in]],
    texture2d<float> fromTexture [[texture(0)]],
    texture2d<float> toTexture [[texture(1)]],
    constant LiquidMorphUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    float2 uv = in.texCoord;
    float progress = clamp(uniforms.progress, 0.0, 1.0);
    float time = uniforms.time;

    float2 center = float2(0.5, 0.5);

    // Direction the peel travels: top -> bottom.
    // Our UV space is (0,0) at top-left and (1,1) at bottom-right.
    float2 peelDir = float2(0.0, 1.0);
    float2 peelNormal = float2(-peelDir.y, peelDir.x);

    float2 p = uv - center;
    float along = dot(p, peelDir);
    float across = dot(p, peelNormal);

    // Boundary moves from off-screen to off-screen.
    // along ranges roughly [-0.5, 0.5] (centered UV), so a little padding avoids early reveal.
    float boundary = mix(-0.65, 0.65, progress);

    // Add a subtle curve + noise so it feels like a physical peel, not a straight wipe.
    float curve = across * across * 0.22;

    // Organic multi-layered noise for uneven drip pattern (not pointy stripes)
    float edgeNoise = fbm(uv * (uniforms.frequency * 3.5), 4) - 0.5;
    float dripNoise = fbm(uv * float2(uniforms.frequency * 6.0, uniforms.frequency * 1.5), 3) - 0.5;

    // Combine for organic uneven drips
    float organicDrip = edgeNoise * 0.08 + dripNoise * 0.06;
    float d = along - (boundary + curve + organicDrip);

    // Reveal mask: 0 = from, 1 = to.
    // Tighter edge for less color diffusion between artworks
    float edgeSoft = 0.012;
    float reveal = 1.0 - smoothstep(-edgeSoft, edgeSoft, d);

    // Edge band for refraction/highlights - wider for viscous depth
    float bandWidth = 0.08;
    float edgeBand = 1.0 - smoothstep(0.0, bandWidth, abs(d));

    // Depth factor based on noise intensity - organic thickness variation
    float depthFactor = smoothstep(-0.1, 0.1, dripNoise) * edgeBand;

    // Peak the distortion in the middle of the transition.
    float peak = sin(progress * M_PI_F);

    // Refraction field for liquid glass distortion
    float2 flow = gradientNoise(uv * (uniforms.frequency * 1.4), time);
    float glassThickness = edgeBand * (0.6 + depthFactor * 0.4);
    float2 refract = flow * uniforms.amplitude * 0.8 * peak * glassThickness;

    // Chromatic aberration - RGB channels refract slightly differently through glass
    float chromaStrength = 0.012 * peak * glassThickness;
    float2 refractR = refract * 1.0;
    float2 refractG = refract * 1.05;
    float2 refractB = refract * 1.10;

    // Sample from artwork with chromatic separation (liquid glass effect)
    float2 fromUV_R = clamp(uv + refractR, float2(0.002), float2(0.998));
    float2 fromUV_G = clamp(uv + refractG + float2(chromaStrength, 0.0), float2(0.002), float2(0.998));
    float2 fromUV_B = clamp(uv + refractB + float2(chromaStrength * 2.0, 0.0), float2(0.002), float2(0.998));

    // Clean destination - no distortion
    float2 toUV = uv;

    // Chromatic sampling for glass-like color separation
    float4 fromColor;
    fromColor.r = fromTexture.sample(textureSampler, fromUV_R).r;
    fromColor.g = fromTexture.sample(textureSampler, fromUV_G).g;
    fromColor.b = fromTexture.sample(textureSampler, fromUV_B).b;
    fromColor.a = 1.0;

    float4 toColor = toTexture.sample(textureSampler, toUV);

    // Fresnel effect - glass edges catch more light than center
    float fresnel = pow(1.0 - abs(dot(float2(0.0, 1.0), normalize(flow + 0.001))), 2.0);
    fresnel *= edgeBand * peak * 0.15;

    // Base reveal: from artwork transitions to to artwork
    // reveal=0 means show from, reveal=1 means show to
    float4 base = mix(fromColor, toColor, reveal);

    // At the glass edge, blend in the refracted from-color (dripping glass effect)
    // This creates translucent glass showing the from artwork dripping
    float glassBlend = edgeBand * peak * 0.6;
    base = mix(base, fromColor, glassBlend * (1.0 - reveal));

    // Add fresnel highlight on glass surface
    base.rgb += fresnel;

    // "Peel lip": a curled strip of the old artwork that rides on top of the new one.
    float lipWidth = 0.11;
    float lipFeather = 0.015;
    float lip = smoothstep(-lipWidth, 0.0, d) * (1.0 - smoothstep(0.0, lipFeather, d));

    float curl = sin(lip * M_PI_F) * lip * peak;
    float2 curlUV = uv + peelNormal * (curl * 0.055) + refract * 0.55;
    curlUV = clamp(curlUV, float2(0.002), float2(0.998));

    float4 lipColor = fromTexture.sample(textureSampler, curlUV);

    // Glass depth shading - thicker glass is slightly darker
    float ridge = pow(edgeBand, 2.0) * peak;
    float shadow = lip * reveal * 0.08;

    // Glass internal reflection - brighter highlights on curved surfaces
    float glassHighlight = ridge * 0.12 + fresnel * 0.5;

    base.rgb *= (1.0 - shadow);
    lipColor.rgb = clamp(lipColor.rgb * 0.94 + float3(glassHighlight), 0.0, 1.0);

    float lipAlpha = lip * 0.8;
    float4 result = mix(base, lipColor, lipAlpha);

    // Primary specular - sharp highlight at glass edge
    float edgeLine = (1.0 - smoothstep(0.0, edgeSoft * 0.8, abs(d))) * peak;
    result.rgb = clamp(result.rgb + edgeLine * 0.12, 0.0, 1.0);

    // Secondary specular - softer glow along the glass surface
    float softGlow = (1.0 - smoothstep(0.0, bandWidth * 0.6, abs(d))) * peak * 0.06;
    result.rgb = clamp(result.rgb + softGlow, 0.0, 1.0);

    // Glass caustic shimmer - subtle light pattern through glass
    float caustic = noise(uv * uniforms.frequency * 8.0 + float2(time * 0.2, 0.0));
    caustic = pow(caustic, 3.0) * edgeBand * peak * 0.08;
    result.rgb = clamp(result.rgb + caustic, 0.0, 1.0);

    return float4(result.rgb, 1.0);
}
