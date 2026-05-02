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
        // calc the non linearity with a local average instead of each pixel
        float4 rACE(coreimage::sampler Ik,
                    coreimage::destination dest)
        {
            const float2 centerPos = dest.coord();
            const float4 I_x = Ik.sample(Ik.transform(centerPos));
            const int kernelDim = 41;
            
            float4 r_ace = 0.f;
            float normFactor = 0.f;
            
            for(int y = -kernelDim; y < kernelDim; y++)
            {
                for(int x = -kernelDim; x < kernelDim; x++)
                {
                    if( (0 == x) && (0 == y) )
                    {
                        continue;
                    }
                    
                    float2 offset = centerPos + float2(x, y);
                    float4 I_y = Ik.sample(Ik.transform(offset));
                    
                    // euclidean distance
                    float euclideanDist = 1.f / (sqrt(pow(x, 2.f) + pow(y, 2.f)) + 1e-3);
                    
                    r_ace += euclideanDist * sigmoid(I_x - I_y);
                    normFactor += euclideanDist;
                }
            }
             
            r_ace /= (normFactor + 1e-3);
            r_ace.a = 1.0;
            
            return r_ace;
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
            
            return colorNext;
        }
    } // namespace coreimage
} // extern "C"
