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
        float4 tonemap(coreimage::sample_t color,       // primary image
                       coreimage::sample_t luminance,   // luminance helper (read-only)
                       constant float * lightnessLUT,   // luminance helper (read-only)
                       const float minLuminance,
                       const float maxLuminance,
                       const unsigned toneCurveLength)
        {
            float4 toneMappedRGB = 1.f;
            
            const float normedPos = ((luminance.r - minLuminance) / (maxLuminance - minLuminance));
            const unsigned short u = floor(normedPos) * toneCurveLength;
            
            const float f_G = (u < toneCurveLength)? mix(lightnessLUT[u], lightnessLUT[u + 1u], (normedPos * toneCurveLength) - float(u)) : lightnessLUT[u];
            
            toneMappedRGB.rgb = color.rgb / (color.rgb + f_G);   // equation (17)
            
            //return toneMappedRGB;
            return toneMappedRGB;
        }
    } // namespace coreimage
} // extern "C"
