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
        float4 tonemap(coreimage::sample_t pixelColor)
        {
            float threshold = 0.5;
            float3 pixelRGB = pixelColor.rgb;
            
            float luma = (pixelRGB.r * 0.2126) + (pixelRGB.g * 0.7152) + (pixelRGB.b * 0.0722);
            
            return (luma > threshold) ? float4(1.0, 1.0, 1.0, 1.0) : float4(0.0, 0.0, 0.0, 0.0);
        }
    }
}
