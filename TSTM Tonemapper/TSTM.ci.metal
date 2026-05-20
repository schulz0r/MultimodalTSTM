//
//  TSTM.metal
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 30.03.26.
//

#include <metal_stdlib>
using namespace metal;
#include <CoreImage/CoreImage.h>

extern "C"
{
    namespace coreimage
    {
        float4 tonemap(coreimage::sample_t color,       // primary RGB image
                       coreimage::sample_t luminance,   // luminance image
                       coreimage::sampler lightnessLUT, // a 256 x 1 image
                       const float minLuminance,
                       const float maxLuminance)
        {
            const float lutPos = (luminance.r - minLuminance) / minLuminance; // in range [0,1] like the sampler coordinate system
            
            float f_G = lightnessLUT.sample({lutPos, 0.5f}).r;    // 0.5 so we are dead center on the LUT's y axis
            
            float3 rgb = color.rgb;
            float3 toneMapped = rgb / (rgb + f_G + 1e-8);
            
            return float4(toneMapped, color.a);
        }
    } // namespace coreimage
} // extern "C"
