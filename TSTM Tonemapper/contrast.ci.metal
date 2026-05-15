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
                                  constant float * w,
                                  constant float * alpha,
                                  constant float * beta,
                                  constant float * gamma,
                                  constant float * delta,
                                  const int degree)
        {
            float4 nextSum = sum;
            
            float4 sineSum = 0.0;
            float4 cosineSum = 0.0;
            
            float4 img_cos = 0.f;
            float4 img_sin = 0.f;
            
            for(unsigned char n = 0; n <= degree; n++)
            {
                img_cos = cos(w[n] * I_x);
                img_sin = sin(w[n] * I_x);
                
                sineSum += (beta[n] * img_cos) + (delta[n] * img_sin);
                cosineSum += (alpha[n] * img_cos) + (gamma[n] * img_sin);
            }
            
            sineSum *= sineImage;
            cosineSum *= cosineImage;
            
            nextSum += sineSum + cosineSum;
            
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
