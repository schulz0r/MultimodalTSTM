//
//  TSTM.metal
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 30.03.26.
//

#include <metal_stdlib>
using namespace metal;
#include <CoreImage/CoreImage.h>

float getLightness(const float luminance, const float minLuminance, const float maxLuminance, constant float * lightnessLUT, const unsigned lutSize)
{
    const float scaled = ((luminance - minLuminance) / (maxLuminance - minLuminance)) * float(lutSize - 1u);
    const unsigned u = (unsigned)floor(scaled);
    const float frac = scaled - float(u);
    
    float f_G = lightnessLUT[u];
    if (u < lutSize)
    {
        // Interpolate between neighbors
        f_G = mix(lightnessLUT[u], lightnessLUT[u + 1u], frac);
    }
    
    return f_G;
}

extern "C"
{
    namespace coreimage
    {
        float4 tonemap(coreimage::sample_t color,       // primary image
                       coreimage::sample_t luminance,   // luminance helper (read-only)
                       const float minLuminance,
                       const float maxLuminance,
                       constant float * lightnessLUT,
                       const unsigned lutSize)
        {
            float f_G = getLightness(luminance.r, minLuminance, maxLuminance, lightnessLUT, lutSize);
            
            float3 rgb = color.rgb;
            float3 toneMapped = rgb / (rgb + f_G + 1e-8);
            
            return float4(toneMapped, color.a);
        }
    } // namespace coreimage
} // extern "C"
