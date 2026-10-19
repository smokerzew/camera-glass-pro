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

// Thermal camera (mode 0: dark blue -> purple -> red -> orange -> yellow -> white by brightness) or
// night-vision goggles (mode 1: boosted green phosphor), blended by `amount`.
[[stitchable]] float4 visionLook(coreimage::sample_t s, float mode, float amount) {
    float3 c = pow(clamp(s.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float y = dot(c, float3(0.299, 0.587, 0.114));
    float3 v;
    if (mode < 0.5) {
        float3 p0 = float3(0.02, 0.0, 0.12), p1 = float3(0.35, 0.0, 0.55), p2 = float3(0.85, 0.05, 0.25);
        float3 p3 = float3(1.0, 0.45, 0.0), p4 = float3(1.0, 0.85, 0.1), p5 = float3(1.0, 1.0, 0.92);
        float t = y * 5.0;
        if (t < 1.0) v = mix(p0, p1, t);
        else if (t < 2.0) v = mix(p1, p2, t - 1.0);
        else if (t < 3.0) v = mix(p2, p3, t - 2.0);
        else if (t < 4.0) v = mix(p3, p4, t - 3.0);
        else v = mix(p4, p5, min(t - 4.0, 1.0));
    } else {
        float g = pow(clamp(y * 1.6, 0.0, 1.0), 0.8);
        v = float3(0.12 * g, g, 0.18 * g);
    }
    return float4(mix(s.rgb, pow(v, float3(2.2)), amount), s.a);
}

// VHS tape: sharp-ish brightness, colors from a horizontally smeared copy (bleed), scan lines,
// a warm-magenta tape cast and lifted blacks, blended by `amount`.
[[stitchable]] float4 vhsLook(coreimage::sample_t s, coreimage::sample_t smear, coreimage::sample_t lines, float amount) {
    float3 w = float3(0.2126, 0.7152, 0.0722);
    float y = dot(s.rgb, w);
    float3 color = (smear.rgb - dot(smear.rgb, w)) * 1.25;
    float3 v = max(y + color, 0.0) * mix(1.0, lines.r, 0.45);
    v = v * float3(1.04, 0.97, 1.03) + float3(0.012, 0.006, 0.02);
    return float4(mix(s.rgb, v, amount), s.a);
}

// Takes red from one image, green from a second and blue from a third (chromatic fringe).
[[stitchable]] float4 combineChannels(coreimage::sample_t r, coreimage::sample_t g, coreimage::sample_t b) {
    return float4(r.r, g.g, b.b, g.a);
}

// Webcam sensor noise: colored speckle, strongest in the shadows (cheap sensors in low light).
[[stitchable]] float4 webcamNoise(coreimage::sample_t s, coreimage::sample_t noise, float amount) {
    float y = clamp(dot(s.rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
    float3 speckle = (noise.rgb - 0.5) * 0.09 * amount * (1.0 - y) * (1.0 - y);
    return float4(max(s.rgb + speckle, 0.0), s.a);
}

// Panorama: maps each output point on a cylinder (radius `focal`, centered on cx, cy) back to the flat
// photo, so photos taken by turning in place line up with a simple sideways shift.
[[stitchable]] float2 cylinderWarp(float cx, float cy, float focal, coreimage::destination dest) {
    float2 d = dest.coord();
    float theta = (d.x - cx) / focal;
    return float2(focal * tan(theta) + cx, (d.y - cy) / cos(theta) + cy);
}

// Smooth slow motion: an in-between frame at `t` (0 = a, 1 = b). `flow` holds each pixel's motion from a
// to b; `scale` turns its values into output pixels (and fixes the direction convention).
[[stitchable]] float4 interpolateFrames(coreimage::sampler a, coreimage::sampler b, coreimage::sampler flow,
                                        float t, float2 scale, coreimage::destination dest) {
    float2 p = dest.coord();
    float2 f = flow.sample(flow.transform(p)).rg * scale;
    float4 ca = a.sample(a.transform(p - t * f));
    float4 cb = b.sample(b.transform(p + (1.0 - t) * f));
    return mix(ca, cb, t);
}

// Remove brush: the smooth fill plus the fine detail (texture) of a matching nearby patch, inside the mask.
[[stitchable]] float4 addDetail(coreimage::sample_t base, coreimage::sample_t patch, coreimage::sample_t patchBlur,
                                coreimage::sample_t mask) {
    return float4(base.rgb + (patch.rgb - patchBlur.rgb) * mask.r, base.a);
}

// Sky edge refinement: `region` is the (dilated) smooth-sky area; `local` is the average sky color nearby
// (premultiplied by how much sky it saw). Pixels close to the local sky color stay sky, so the edge follows
// rooftops and ridges pixel by pixel instead of a blurred band.
[[stitchable]] float4 skyRefine(coreimage::sample_t s, coreimage::sample_t local, coreimage::sample_t region) {
    float3 c = pow(clamp(s.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float3 sky = pow(clamp(local.rgb / max(local.a, 0.001), 0.0, 1.0), float3(1.0 / 2.2));
    float d = length(c - sky);
    float m = region.r * (1.0 - smoothstep(0.07, 0.2, d));
    return float4(m, m, m, 1.0);
}

// Sky Replace: the new sky with the original sky's fine detail (clouds, haze) as relative brightness, in display
// space, so clouds take on the new sky's color (pink at sunset) instead of staying white specks.
[[stitchable]] float4 skyDetail(coreimage::sample_t sky, coreimage::sample_t original, coreimage::sample_t originalBlur,
                                float amount) {
    float3 o = pow(clamp(original.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float3 b = pow(clamp(originalBlur.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float3 n = pow(clamp(sky.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float3 w = float3(0.2126, 0.7152, 0.0722);
    float ratio = clamp(dot(o, w) / max(dot(b, w), 0.02), 0.6, 1.8);
    return float4(pow(clamp(n * mix(1.0, ratio, amount), 0.0, 1.0), float3(2.2)), 1.0);
}
