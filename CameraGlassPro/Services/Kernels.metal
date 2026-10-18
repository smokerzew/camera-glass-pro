#include <CoreImage/CoreImage.h>
using namespace metal;

// Core Image kernels, compiled into the app's default.metallib at build time ([[stitchable]] needs no
// special build flags) and loaded by name in ImageProcessingService. iOS can't compile Metal source at runtime.

// Film grain. `s` is sRGB encoded; `fine`/`coarse` are blurred random noise whose RGB average has
// std ≈ 0.068 around 0.5, so `n` has unit std. Added equally to R, G and B; strongest in midtones.
[[stitchable]] float4 filmGrain(coreimage::sample_t s, coreimage::sample_t fine,
                                coreimage::sample_t coarse, float strength) {
    float n = ((dot(fine.rgb, float3(1.0 / 3.0)) - 0.5) + 0.6 * (dot(coarse.rgb, float3(1.0 / 3.0)) - 0.5)) * 12.6;
    float y = clamp(dot(s.rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
    float w = (0.35 + 2.6 * y * (1.0 - y)) * (1.0 - y * y * y * y);
    return float4(clamp(s.rgb + strength * n * w, 0.0, 1.0), s.a);
}

// Halation glow source: linear luminance above ~0.45 (about 70% on screen) ramps to full at 0.8,
// tinted red-orange. Darker pixels give exactly nothing.
[[stitchable]] float4 halationSource(coreimage::sample_t s) {
    float y = dot(s.rgb, float3(0.2126, 0.7152, 0.0722));
    float h = clamp((y - 0.45) / 0.35, 0.0, 1.0);
    return float4(h, h * 0.28, h * 0.06, 1.0);
}

// Photo + blurred glow, keeping the photo's alpha.
[[stitchable]] float4 halationAdd(coreimage::sample_t s, coreimage::sample_t wide,
                                  coreimage::sample_t tight, float strength) {
    return float4(s.rgb + (wide.rgb + tight.rgb) * strength, s.a);
}

// Skin smoothing: blends toward the blurred photo only where `area` (soft face regions) is white,
// the pixel is skin-colored (YCbCr range) and there is no edge (big gap between photo and blur).
[[stitchable]] float4 skinSmooth(coreimage::sample_t s, coreimage::sample_t blurred,
                                 coreimage::sample_t area, float amount) {
    float3 c = pow(clamp(s.rgb, 0.0, 1.0), float3(1.0 / 2.2)); // judge color on display values
    float cb = 0.5 - 0.1687 * c.r - 0.3313 * c.g + 0.5 * c.b;
    float cr = 0.5 + 0.5 * c.r - 0.4187 * c.g - 0.0813 * c.b;
    float skin = smoothstep(0.26, 0.31, cb) * (1.0 - smoothstep(0.49, 0.54, cb))
               * smoothstep(0.51, 0.55, cr) * (1.0 - smoothstep(0.68, 0.72, cr));
    float3 b = pow(clamp(blurred.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float edge = 1.0 - smoothstep(0.04, 0.12, length(c - b));
    float w = area.r * skin * edge * amount * 0.85; // keep a little texture so skin never looks plastic
    return float4(mix(s.rgb, blurred.rgb, w), s.a);
}

// Split toning for the recipe filters: tints shadows and highlights by luminance. The shadow tint fades
// out toward pure black, so night skies and deep shadows stay neutral instead of turning a color.
[[stitchable]] float4 lookSplitTone(coreimage::sample_t s, float3 shadows, float3 highlights) {
    float m = clamp(dot(s.rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
    return float4(s.rgb + shadows * (1.0 - m) * min(1.0, m * 12.0) + highlights * m, s.a);
}
