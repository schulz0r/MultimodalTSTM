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
        float4 tonemap(coreimage::sample_t color,          // primary image
                       coreimage::sample_t luminance,      // luminance helper (read-only)
                       constant float* gmm_means,                    // read-only buffer (length = numSegments)
                       constant float* mu_minus,                    // read-only buffer (length = numSegments)
                       constant float* mu_plus,                    // read-only buffer (length = numSegments)
                       constant float* h_j,                    // read-only buffer (length = numSegments )
                       constant float* c_j,                    // read-only buffer (length = numSegments)
                       float m,
                       float mu_avg,
                       int numSegments,                        // constant scalar
                       coreimage::destination dest)            // output                        // example scalar argument
        {
            unsigned segment_j = 0;
            
            for(segment_j = 0; (luminance.r >= mu_minus[segment_j]) && (luminance.r <= mu_plus[segment_j]); segment_j++) {}
            
            const float nakaRushton_r = normNakaRushtonEquation(luminance.r,
                                                                gmm_means[segment_j],
                                                                mu_minus[segment_j],
                                                                mu_plus[segment_j],
                                                                m,
                                                                mu_avg);
            
            float r_G = c_j[segment_j] + (h_j[segment_j] * nakaRushton_r);
            
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
