#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>

using namespace metal;

/// GPU Liquid Gel (Metaball) + Emissive Bloom Shader.
///
/// Design:
///   1. Gaussian blur (11x11, sigma=2.5) creates a soft halo around every bar.
///   2. Original bar pixels are ALWAYS preserved via max(center.a, metaballAlpha).
///   3. In the gaps between bars where blurred alpha exceeds the gelTension threshold,
///      the gap is filled with blurred color — creating the metaball "melting" effect.
///   4. An additive emissive bloom is overlaid, pulsing with low-frequency beat energy.
///
/// Parameters:
///   - position:     Screen pixel coordinate of the output fragment.
///   - layer:        The input SwiftUI Canvas layer (the visualizer bars).
///   - size:         View dimensions (width, height) in points.
///   - pulseGlow:        pulseGlow value [0, 1.5] — scales beat-reactive bloom.
///   - liquidIntensity:  master FX amount [0, 1]. Higher = softer, brighter, more fused.
[[stitchable]] half4 liquidGelShader(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float pulseGlow,
    float liquidIntensity
) {
    float intensity = clamp(liquidIntensity, 0.0, 1.0);

    // 1. 11x11 Gaussian Blur (radius=5, sigma=2.5)
    half4 blurSum = half4(0.0);
    float totalWeight = 0.0;
    int radius = 5;
    float sigma = mix(1.6, 3.2, intensity);
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            float2 offset = float2(dx, dy);
            float weight = exp(-dot(offset, offset) / (2.0 * sigma * sigma));
            blurSum += layer.sample(position + offset) * weight;
            totalWeight += weight;
        }
    }
    half4 blurred = blurSum / totalWeight;

    // 2. Original unblurred center pixel
    half4 center = layer.sample(position);

    // 3. Metaball gap-fill via alpha thresholding on the blurred layer.
    //    Higher intensity lowers tension and widens the soft edge, so gaps fuse earlier.
    //    This causes adjacent bars to visually "melt" together in the gaps between them.
    half threshold = half(mix(0.58, 0.16, intensity));
    half edgeWidth = half(mix(0.025, 0.09, intensity));
    half metaballAlpha = smoothstep(threshold - edgeWidth, threshold + edgeWidth, blurred.a);

    // 4. Final body: preserve the original bar pixels exactly, then only add
    //    blurred color where the metaball threshold fills gaps between bars.
    half finalAlpha = max(center.a, metaballAlpha);
    half3 gelFill = blurred.rgb * metaballAlpha;
    half3 finalRGB = max(center.rgb, gelFill);

    // 6. Emissive neon bloom (additive).
    //    The blurred layer acts as a soft light emitter whose brightness pulses with bass hits.
    half baseBloom = half(mix(0.10, 0.70, intensity));
    half pulseBloom = half(pulseGlow) * half(mix(0.25, 1.20, intensity));
    half3 bloom = blurred.rgb * blurred.a * (baseBloom + pulseBloom);

    // Combine solid body with additive bloom. Layer samples are already suitable
    // for direct compositing here, so avoid multiplying the preserved bar color
    // by finalAlpha a second time.
    half4 result = half4(finalRGB + bloom, finalAlpha);
    return clamp(result, 0.0h, 1.0h);
}
