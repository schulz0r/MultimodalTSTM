//
//  TSTM.metal
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 30.03.26.
//

#include <metal_stdlib>
using namespace metal;
#include <CoreImage/CoreImage.h>

float normNakaRushtonEquation(const float lambda,
                              const float m_j,
                              const float k_j,
                              const float C,
                              const float minLum,
                              const float maxLum)
{
    const float r_luminance = C + (k_j * log(m_j + lambda)); // equation (12)
    const float r_luminance_min = C + (k_j * log(m_j + minLum));
    const float r_luminance_max = C + (k_j * log(m_j + maxLum));
    
    return (r_luminance - r_luminance_min) / (r_luminance_max - r_luminance_min); // equation (18)
}

bool contains(const float value, const float lowerBorder, const float upperBorder)
{
    return ( (lowerBorder <= value) && (value <= upperBorder) );
}

extern "C"
{
    namespace coreimage
    {
        float4 tonemap(coreimage::sample_t color,       // primary RGB image
                       coreimage::sample_t luminance,   // luminance image
                       constant float * lowerSegmentBorders,
                       constant float * upperSegmentBorders,
                       constant float * m_,
                       constant float * k_,
                       constant float * C_,
                       constant float * c,
                       constant float * h,
                       const unsigned numSegments)
        {
            float r_G = 0.f;
            
            for (unsigned j = 0; j < numSegments; j++)
            {
                if( contains(luminance.r, lowerSegmentBorders[j], upperSegmentBorders[j]) )
                {
                    const float nakaRushton_r = normNakaRushtonEquation(luminance.r,
                                                                        m_[j],
                                                                        k_[j],
                                                                        C_[j],
                                                                        lowerSegmentBorders[j],
                                                                        upperSegmentBorders[j]);
                    
                    r_G += c[j] + (h[j] * nakaRushton_r); // equation (21)
                } // else: nothing
            }
            const float f_G = (luminance.r / (r_G + 1e-12)) - luminance.r; // equation (24)
            
            const float3 toneMapped = color.rgb / (color.rgb + f_G + 1e-12);
            
            return float4(toneMapped, color.a);
        }
    } // namespace coreimage
} // extern "C"
