#include <CoreImage/CoreImage.h>

// Core Image kernels (built with -fcikernel / -cikernel, see the target's build settings).
extern "C" {
namespace coreimage {

// `s` is display (sRGB) encoded. `fine`/`coarse` are blurred random noise whose RGB average has
// std ≈ 0.068 around 0.5, so `n` has unit std. Grain is added equally to R, G and B (never tints)
// and weighted like film: strongest in midtones, lighter in shadows, gone in bright highlights.
float4 filmGrain(sample_t s, sample_t fine, sample_t coarse, float strength) {
    float n = ((dot(fine.rgb, float3(1.0 / 3.0)) - 0.5) + 0.6 * (dot(coarse.rgb, float3(1.0 / 3.0)) - 0.5)) * 12.6;
    float y = clamp(dot(s.rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
    float w = (0.35 + 2.6 * y * (1.0 - y)) * (1.0 - y * y * y * y);
    return float4(clamp(s.rgb + strength * n * w, 0.0, 1.0), s.a);
}

}
}
