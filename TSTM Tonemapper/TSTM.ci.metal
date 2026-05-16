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
                       constant float * f_G,
                       const unsigned toneCurveLength)
        {
            const float i = luminance.r * toneCurveLength;
            const unsigned baseIdx = floor(i);
            
            float f_intpl = 0.f;
            if(baseIdx < toneCurveLength)
            {
                const float frac = i - floor(i);
                f_intpl = mix(f_G[baseIdx], f_G[baseIdx + 1u], frac);
            }
            else
            {
                f_intpl = f_G[baseIdx];
            }
            
            float4 toneMappedRGB = 1.f;
            toneMappedRGB.rgb = color.rgb / (color.rgb + f_intpl);   // equation (17)
            
            return toneMappedRGB;
        }
    } // namespace coreimage
} // extern "C"
