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

// Noise reduction. Brightness: averaged with a lightly blurred copy except where the difference is big
// enough to be a real edge (judged on display values). Color: taken from a wider blur, which removes the
// red/green/blue speckle of night shots. Average brightness is unchanged.
[[stitchable]] float4 denoise(coreimage::sample_t s, coreimage::sample_t fine, coreimage::sample_t wide, float amount) {
    float3 w = float3(0.2126, 0.7152, 0.0722);
    float y = dot(s.rgb, w);
    float yf = dot(fine.rgb, w);
    float gap = abs(pow(max(y, 0.0), 1.0 / 2.2) - pow(max(yf, 0.0), 1.0 / 2.2));
    float edge = smoothstep(0.03 + 0.09 * amount, 0.08 + 0.2 * amount, gap);
    float yOut = mix(y, yf, amount * (1.0 - edge));
    float3 color = mix(s.rgb - y, wide.rgb - dot(wide.rgb, w), amount);
    return float4(yOut + color, s.a);
}

// How sky-like each pixel is (0...1): blue sky, bright overcast or dark night sky, smooth (no texture),
// and toward the top of the frame (`top` is a vertical gradient). `texture` is local detail in display values.
[[stitchable]] float4 skyLikelihood(coreimage::sample_t s, coreimage::sample_t texture, coreimage::sample_t top) {
    float3 c = pow(clamp(s.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float y = dot(c, float3(0.2126, 0.7152, 0.0722));
    float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    float blue = smoothstep(0.03, 0.12, c.b - c.r) * smoothstep(0.15, 0.3, y);
    float overcast = smoothstep(0.62, 0.82, y) * (1.0 - smoothstep(0.08, 0.2, sat));
    float night = 1.0 - smoothstep(0.05, 0.14, y);
    float smooth = 1.0 - smoothstep(0.012, 0.045, texture.r);
    float m = max(blue, max(overcast, night)) * smooth * top.r;
    return float4(m, m, m, 1.0);
}

// Match Look: per-channel scale/offset in YCbCr (display values), blended by `amount`.
[[stitchable]] float4 matchLook(coreimage::sample_t s, float3 scale, float3 offset, float amount) {
    float3 c = pow(clamp(s.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float y = dot(c, float3(0.299, 0.587, 0.114));
    float3 t = float3(y, (c.b - y) * 0.564 + 0.5, (c.r - y) * 0.713 + 0.5) * scale + offset;
    float r = t.x + 1.403 * (t.z - 0.5);
    float b = t.x + 1.773 * (t.y - 0.5);
    float g = (t.x - 0.299 * r - 0.114 * b) / 0.587;
    float3 matched = pow(clamp(float3(r, g, b), 0.0, 1.0), float3(2.2));
    return float4(mix(s.rgb, matched, amount), s.a);
}

// Dispersion: a cell breaks off when its random value is below the chance at that spot (`zone`, 0 deep
// inside the subject, 1 at the leading edge), scaled by `density`. Gives an organic, eroding edge.
[[stitchable]] float4 dispersionHoles(coreimage::sample_t noise, coreimage::sample_t zone, float density) {
    float h = noise.r < zone.r * density ? 1.0 : 0.0;
    return float4(h, h, h, 1.0);
}
