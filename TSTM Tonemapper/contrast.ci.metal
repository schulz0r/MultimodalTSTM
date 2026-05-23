//
//  contrast.ci
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 20.04.26.
//

#include <metal_stdlib>
using namespace metal;
#include <CoreImage/CoreImage.h>

extern "C"
{
    float4 sigmoid(const float4 x)
    {
        return tanh(20.f * x) / tanh(20.f);
    }
    
    namespace coreimage
    {
        float4 sineImage(coreimage::sample_t I_x,
                           const float w_k)
        {
            return sin(w_k * I_x);
        }
        
        float4 cosineImage(coreimage::sample_t I_x,
                           const float w_k)
        {
            return cos(w_k * I_x);
        }
        
        float4 contrastTermApprox(coreimage::sample_t I_x,
                                  coreimage::sample_t sineImage,
                                  coreimage::sample_t cosineImage,
                                  coreimage::sample_t sum,
                                  const float w_k,
                                  const float beta_k)
        {
            float4 nextSum = sum;
            nextSum += 2 * beta_k * ((sin(w_k * I_x) * cosineImage) - (cos(w_k * I_x) * sineImage));
            return nextSum;
        }
        
        float4 contrastEnhance(coreimage::sample_t I_0,
                               coreimage::sample_t I_k,
                               coreimage::sample_t R_ace,
                               const float stepSize,
                               const float alpha,
                               const float beta)
        {
            float4 colorNext = I_k + (stepSize * ( (0.5f * alpha) + (beta * I_0) + (0.5f * R_ace) ));
            colorNext /=  1.f + (stepSize * (alpha + beta));
            
            colorNext.a = 1.f;
            
            return saturate(colorNext);
        }
    } // namespace coreimage
} // extern "C"
