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
    float normNakaRushtonEquation(const float luminance,
                                  const float mean_j,
                                  const float lambda_min,
                                  const float lambda_max,
                                  const float m,
                                  const float mu_avg);
    
    namespace coreimage
    {
        float4 tonemap(coreimage::sample_t color,       // primary image
                       coreimage::sample_t luminance,   // luminance helper (read-only)
                       constant float* gmm_means,       // read-only buffer (length = numSegments)
                       constant float* mu_minus,        // read-only buffer (length = numSegments)
                       constant float* mu_plus,         // read-only buffer (length = numSegments)
                       constant float* h_j,             // read-only buffer (length = numSegments )
                       constant float* c_j,             // read-only buffer (length = numSegments)
                       const float m,
                       const float mu_avg,
                       const unsigned numSegments,      // constant scalar
                       coreimage::destination dest)     // output
        {
            float r_G = 0.f;
            
            for(unsigned j = 0; j < numSegments; j++)
            {
                if( (luminance.r >= mu_minus[j]) && (luminance.r <= mu_plus[j]) )
                {
                    const float nakaRushton_r = normNakaRushtonEquation(luminance.r,
                                                                        gmm_means[j],
                                                                        mu_minus[j],
                                                                        mu_plus[j],
                                                                        m,
                                                                        mu_avg);
                    
                    r_G += c_j[j] + (h_j[j] * nakaRushton_r);
                } // else: nothing
            }
            
            float f_G = (luminance.r / r_G) - luminance.r;
            
            return color / (color + f_G);
        }
        
        float normNakaRushtonEquation(const float lambda,
                                      const float mean_j,
                                      const float lambda_min,
                                      const float lambda_max,
                                      const float m,
                                      const float mu_avg)
        {
            float m_j = metal::min(0.f, (metal::pow(mean_j, 2.0) - (lambda_max * lambda_min) ) / (lambda_max + lambda_min - (2 * mean_j)) );
            float k_j = 1.f / log( (m_j + lambda_max) / (m_j + lambda_min) );
            float C = 0.5 * k_j * log(m * mu_avg);
            
            float r_luminance = C + (k_j * metal::log(m + lambda));
            float r_luminance_min = C + (k_j * metal::log(m + lambda_min));
            float r_luminance_max = C + (k_j * metal::log(m + lambda_max));
            
            return (r_luminance - r_luminance_min) / (r_luminance_max - r_luminance_min);
        }
    } // namespace coreimage
} // extern "C"
