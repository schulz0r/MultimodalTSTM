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
            // sampler extent (x, y, width, height)
            float4 extent = samplerExtent(lightnessLUT);

            // luminance is in range [0,1] like the sampler coordinate system
            const float lutPos = ((luminance.r - minLuminance) / (maxLuminance - minLuminance)) * extent.z;
                        
            // y=0.5 so we are dead center on the LUT's y axis
            float f_G = lightnessLUT.sample(lightnessLUT.transform(float2(lutPos, 0.5f * extent.w) + extent.xy)).r;
            
            float3 rgb = color.rgb;
            float3 toneMapped = rgb / (rgb + f_G + 1e-8);
            
            return float4(toneMapped, color.a);
        }
    } // namespace coreimage
} // extern "C"
