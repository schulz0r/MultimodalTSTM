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
                                  coreimage::sample_t S_m,
                                  coreimage::sample_t C_m,
                                  coreimage::sample_t sum,
                                  constant float * w,
                                  constant float * alpha,
                                  constant float * beta,
                                  constant float * gamma,
                                  constant float * delta,
                                  const int degree)
        {
            float4 returnVal = 0.f;
            
            float4 sineSum = 0.0;
            float4 cosineSum = 0.0;
            
            for(unsigned char n = 0u; n <= degree; n++)
            {
                const float4 img_cos = cos(w[n] * I_x);
                const float4 img_sin = sin(w[n] * I_x);
                
                sineSum += (beta[n] * img_cos) + (delta[n] * img_sin);
                cosineSum += (alpha[n] * img_cos) + (gamma[n] * img_sin);
            }
            
            sineSum *= S_m;
            cosineSum *= C_m;
            
            returnVal = sum + sineSum + cosineSum;
            returnVal.a = 1.0;
            
            return returnVal;
        }
        
        float4 contrastEnhance(coreimage::sample_t I_0,
                               coreimage::sample_t I_k,
                               coreimage::sample_t R_ace,
                               const float stepSize,
                               const float alpha,
                               const float beta)
        {
            float3 colorNext = 0.f;
            
            colorNext.rgb = I_k.rgb + (stepSize * ( (0.5f * alpha) + (beta * I_0.rgb) + (0.5 * R_ace.rgb) ));
            colorNext.rgb /=  1.f + (stepSize * (alpha + beta));
            
            return float4(saturate(colorNext), I_0.a);
        }
    } // namespace coreimage
} // extern "C"
