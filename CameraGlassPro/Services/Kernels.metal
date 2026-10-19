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

// Whiten Teeth: inside the mouth, bright low-saturation pixels (teeth) lose their yellow and brighten a little;
// lips and gums (saturated reds) and the dark inside of the mouth are left alone.
[[stitchable]] float4 teethWhiten(coreimage::sample_t s, coreimage::sample_t mask, float amount) {
    float3 c = pow(clamp(s.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float y = dot(c, float3(0.2126, 0.7152, 0.0722));
    float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    float teeth = smoothstep(0.28, 0.5, y) * (1.0 - smoothstep(0.3, 0.52, sat)) * mask.r * amount; // yellowed teeth reach ~0.35
    float3 white = mix(float3(y), c, 0.35) + 0.06;
    return float4(pow(clamp(mix(c, white, teeth), 0.0, 1.0), float3(2.2)), s.a);
}

// Subject mask refinement (guided filter, He et al.): fits a rough mask to the photo's real edges.
// Pack: brightness I (display), mask p, I*p, and I*I for the local averages.
[[stitchable]] float4 guidedPackA(coreimage::sample_t s, coreimage::sample_t m) {
    float i = dot(pow(clamp(s.rgb, 0.0, 1.0), float3(1.0 / 2.2)), float3(0.299, 0.587, 0.114));
    float p = clamp(m.r, 0.0, 1.0);
    return float4(i, p, i * p, 1.0);
}

[[stitchable]] float4 guidedPackB(coreimage::sample_t s) {
    float i = dot(pow(clamp(s.rgb, 0.0, 1.0), float3(1.0 / 2.2)), float3(0.299, 0.587, 0.114));
    return float4(i * i, 0.0, 0.0, 1.0);
}

// Local linear model q = a*I + b from the box-averaged packs.
[[stitchable]] float4 guidedCoeffs(coreimage::sample_t x, coreimage::sample_t y, float eps) {
    float meanI = x.r, meanP = x.g;
    float variance = max(y.r - meanI * meanI, 0.0);
    float covariance = x.b - meanI * meanP;
    float a = covariance / (variance + eps);
    return float4(a, meanP - a * meanI, 0.0, 1.0);
}

[[stitchable]] float4 guidedApply(coreimage::sample_t s, coreimage::sample_t ab) {
    float i = dot(pow(clamp(s.rgb, 0.0, 1.0), float3(1.0 / 2.2)), float3(0.299, 0.587, 0.114));
    float q = clamp(ab.r * i + ab.g, 0.0, 1.0);
    return float4(q, q, q, 1.0);
}

// Edge color clean-up: along the subject's edge, pixels are a mix of subject and old background. Remove the
// background's share (estimated from nearby background, premultiplied by how much background it saw), so a new
// background doesn't show a fringe of the old one.
[[stitchable]] float4 decontaminate(coreimage::sample_t s, coreimage::sample_t bg, coreimage::sample_t m) {
    float a = clamp(m.r, 0.0, 1.0);
    float edge = smoothstep(0.02, 0.2, a) * (1.0 - smoothstep(0.8, 0.98, a));
    float3 b = bg.rgb / max(bg.a, 0.001);
    float3 f = clamp((s.rgb - (1.0 - a) * b) / max(a, 0.15), 0.0, 1.0);
    return float4(mix(s.rgb, f, edge * step(0.01, bg.a)), s.a);
}

// MARK: Particle Dissolve
// The subject breaks into fine, irregular particles along a direction. `dir` is the unit direction, `span` =
// (start, length) of the subject along it, `edge` where dissolving begins (0...1 along the subject, lower =
// more dissolved), `soft` how gradual the change is, `cell` particle size in pixels, `density` how many
// particles fly off, `travel` the farthest flight in pixels, `seed` keeps the pattern stable.

static uint pdHash(int x, int y, int k) {
    uint h = uint(x) * 73856093u ^ uint(y) * 19349663u ^ uint(k) * 83492791u;
    h ^= h >> 13; h *= 1274126177u; h ^= h >> 16;
    return h;
}
static float pdRand(int x, int y, int k) { return float(pdHash(x, y, k) & 0xFFFFFFu) / 16777216.0; }

// Smooth value noise, for an organic, uneven dissolving edge.
static float pdNoise(float2 p, int k) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    int x = int(i.x), y = int(i.y);
    float a = pdRand(x, y, k), b = pdRand(x + 1, y, k), c = pdRand(x, y + 1, k), d = pdRand(x + 1, y + 1, k);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// How dissolved a point is (0 intact ... 1 fully particles).
static float pdDissolve(float2 p, float2 dir, float2 span, float edge, float soft, float noiseScale) {
    float s = (dot(p, dir) - span.x) / max(span.y, 1.0);
    float wobble = (pdNoise(p / noiseScale, 7) - 0.5) * 0.35 + (pdNoise(p / (noiseScale * 0.35), 9) - 0.5) * 0.15;
    return smoothstep(edge - soft, edge + soft, s + wobble);
}

[[stitchable]] float4 particleDissolve(coreimage::sampler image, coreimage::sampler plate, coreimage::sampler mask,
                                       float2 dir, float2 span, float edge, float soft, float cell, float density,
                                       float travel, float noiseScale, coreimage::destination dest) {
    float2 q = dest.coord();
    float4 here = image.sample(image.transform(q));
    float4 behind = plate.sample(plate.transform(q));
    float m = mask.sample(mask.transform(q)).r;
    float2 side = float2(-dir.y, dir.x);

    // 1. In place: the subject crumbles into particles where it dissolves; gaps show what's behind it.
    float2 cq = floor(q / cell);
    int cx = int(cq.x), cy = int(cq.y);
    float d = pdDissolve(q, dir, span, edge, soft, noiseScale);
    float4 base = here;
    if (m > 0.02 && d > 0.0) {
        float2 jitter = float2(pdRand(cx, cy, 1), pdRand(cx, cy, 2)) - 0.5;
        float2 center = (cq + 0.5 + jitter * 0.5) * cell;
        float radius = cell * (0.35 + 0.35 * pdRand(cx, cy, 3)) * mix(2.2, 1.0, d); // fill the cell when barely dissolved
        bool inside = distance(q, center) < radius;
        bool stays = pdRand(cx, cy, 4) >= d * d * 0.97 + d * 0.03; // fewer particles remain the more it dissolves
        float gone = (inside && stays) ? 0.0 : 1.0;          // 1 where this spot's particle has left
        float show = 1.0 - m * gone * smoothstep(0.1, 0.35, d); // gaps open gradually: no hard line
        base = mix(behind, here, show);
    }

    // 2. In flight: particles carried from dissolving parts of the subject, densest near where they left.
    for (int k = 0; k < 8; k++) {
        float2 c2 = floor(q / cell);
        int gx = int(c2.x), gy = int(c2.y);
        float t = pdRand(gx, gy, 20 + k);
        t = t * t;                                        // most travel a short way
        float along = travel * t;
        float across = (pdRand(gx, gy, 40 + k) - 0.5) * along * 0.35;
        float2 center = (c2 + 0.5) * cell;
        float2 from = center - dir * along - side * across;
        float ms = mask.sample(mask.transform(from)).r;
        if (ms < 0.5) { continue; }
        float df = pdDissolve(from, dir, span, edge, soft, noiseScale);
        if (pdRand(gx, gy, 60 + k) > df * density) { continue; }
        float size = cell * (0.25 + 0.4 * pdRand(gx, gy, 80 + k)) * (1.0 - 0.45 * t);
        float2 offset = q - center;
        if (length(offset) > size) { continue; }
        float4 color = image.sample(image.transform(from + offset));
        float alpha = (1.0 - 0.6 * t) * smoothstep(size, size * 0.6, length(offset));
        return float4(mix(base.rgb, color.rgb, alpha), 1.0);
    }
    return float4(base.rgb, 1.0);
}
