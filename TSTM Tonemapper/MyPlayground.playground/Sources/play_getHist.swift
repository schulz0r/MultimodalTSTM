//
//  getHist.swift
//  
//
//  Created by Philipp Waxweiler on 12.04.26.
//
import CoreImage
import CoreImage.CIFilterBuiltins

public func getHistogram(image: CIImage, bins: Int, scale: Float) -> (Histogram, Histogram)
{
    let context = CIContext(options: nil)
    
    let colorMonochromeFilter = CIFilter.colorMonochrome()
    colorMonochromeFilter.inputImage = image
    colorMonochromeFilter.color = CIColor(red: 0.334, green: 0.334, blue: 0.334)
    colorMonochromeFilter.intensity = 1
    
    let minMaxFilter = CIFilter.areaMinMax()
    minMaxFilter.inputImage = colorMonochromeFilter.outputImage!
    minMaxFilter.extent = colorMonochromeFilter.outputImage!.extent
    
    var minMax:[SIMD4<Float32>] = [SIMD4<Float32>](repeating: .zero, count: Int(minMaxFilter.outputImage!.extent.width))
    context.render(minMaxFilter.outputImage!,
                   toBitmap: &minMax,
                   rowBytes: MemoryLayout<SIMD4<Float32>>.size * minMax.count,
                   bounds: minMaxFilter.outputImage!.extent,
                   format: .RGBAf,
                   colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
    
    let lumMin = minMax.first!.x
    let lumMax = minMax.last!.x

    // log hist
    let logHistogramFilter = CIFilter.areaLogarithmicHistogram()
    logHistogramFilter.inputImage = colorMonochromeFilter.outputImage!
    logHistogramFilter.count = bins
    logHistogramFilter.scale = scale
    logHistogramFilter.minimumStop = log2(lumMin + 1e-6)
    logHistogramFilter.maximumStop = log2(lumMax + 1e-6)
    logHistogramFilter.extent = image.extent

    var loghistogramValues = [SIMD4<Float32>](repeating: .zero, count: bins)
    context.render(logHistogramFilter.outputImage!,
                   toBitmap: &loghistogramValues,
                   rowBytes: MemoryLayout<SIMD4<Float32>>.size * bins,
                   bounds: logHistogramFilter.outputImage!.extent,
                   format: .RGBAf,
                   colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)

    let retLogHistogram = loghistogramValues.map({$0.x}) // only extract one component (they are all equal anyway)
    
    // linear histogram
    let filter = CIFilter.areaHistogram()
    filter.inputImage = colorMonochromeFilter.outputImage!
    filter.count = bins
    filter.scale = 1.0
    filter.extent = image.extent
    
    var linhistogramValues = [SIMD4<Float32>](repeating: .zero, count: bins)
    context.render(filter.outputImage!,
                   toBitmap: &linhistogramValues,
                   rowBytes: MemoryLayout<SIMD4<Float32>>.size * bins,
                   bounds: logHistogramFilter.outputImage!.extent,
                   format: .RGBAf,
                   colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
    
    let retLinHistogram = linhistogramValues.map({$0.x}) // only extract one component (they are all equal anyway)

    return (Histogram(measures: retLogHistogram, minVal: log2(lumMin + 1e-6), maxVal: log2(lumMax + 1e-6)), Histogram(measures: retLinHistogram, minVal: lumMin, maxVal: lumMax))
}
