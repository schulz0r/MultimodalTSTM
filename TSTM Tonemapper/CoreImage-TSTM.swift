//
//  CoreImage-TSTM.swift
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 29.03.26.
//
import CoreImage
import CoreImage.CIFilterBuiltins

enum TstmFilterError: Error {
    case invalidArgument(String)
}

final class TSTMTonemapper: CIFilter {

    @objc dynamic var inputImage: CIImage?
    
    private let context = CIContext()

    private static let kernel1: CIKernel = {
        let url = Bundle(for: TSTMTonemapper.self).url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIKernel(functionName: "tonemap", fromMetalLibraryData: data)
    }()

    override var outputImage: CIImage?
    {
        guard let input = inputImage else { return nil }
        
        // 1. we need to fit gaussians into the image histogram of the luminance
        // According to Ferradans, fitting works better when using a log histogram
        
        // 1.1 get a log histogram
        let (logLumHistogram, minVal, maxVal) = getLogLuminanceHistogram(InputImage: input)
        
        // 1.2 fit a GMM into the histogram data
        let log_gmm = fitGaussianMixtureModel(histogram: logLumHistogram, numGaussians: 3, numIterations: 20)
        
        // 2. calculate input values for the tonemapper
        // 2.1 calculate value ranges
        let mu_minus = log_gmm.map{$0.mean - (2 * $0.sigma)}
        let mu_plus = log_gmm.map{$0.mean + (2 * $0.sigma)}
        
        let luminance_min:[Float] = (0..<log_gmm.count).map
        {   j in
            var retVal: Float = 0.0
            
            if(0 == j)
            {
                retVal = minVal
            }
            else
            {
                retVal = max( pow(2.0, (mu_plus[j - 1] + mu_minus[j]) / 2), pow(2.0, mu_plus[j - 1]) )
            }
            return retVal
        }
        
        let luminance_max:[Float] = (0..<log_gmm.count).map
        {   j in
            var retVal: Float = 0.0
            
            if((log_gmm.count - 1) == j) // -1 because range is 0..count-1, not 1...count
            {
                retVal = minVal
            }
            else
            {
                retVal = min( pow(2.0, (mu_plus[j] + mu_minus[j + 1]) / 2), pow(2.0, mu_minus[j + 1]) )
            }
            return retVal
        }
        
        // 2.1 calculate m from the luminance average
        let mu_avg: Float = logLumHistogram.enumerated().map({Float(UInt($0) * $1)}).reduce(0, +)
        let m = (pow(mu_avg, 2.0) * Float(minVal * maxVal)) / (maxVal - minVal - (2 * mu_avg)) // TODO: mu_avg is in log domain, min/max in linear
        
        let h_array = zip(luminance_min, luminance_max).map
        { (luMin, LuMax) in
            log10( (m + LuMax) / (m + luMin) )
        }
        let h_sum = h_array.reduce(0, +)
        let h_j:[Float] = h_array.map{$0 / h_sum}
        
        var c_j = [Float](repeating: 0.0, count: 1)
        for h_val in h_j[1..<h_j.endIndex]
        {
            c_j.append(c_j.last! + h_val)
        }
        
        // 3. Apply Naka-Rushton equation
        
        let c_parameters = c_j.withUnsafeBytes { raw -> CIImage in
            CIImage(
                bitmapData: Data(raw),
                bytesPerRow: log_gmm.count * MemoryLayout<Float>.size,
                size: CGSize(width: log_gmm.count, height: 1),
                format: .Rf,                               // CIFormat
                colorSpace: CGColorSpace(name: CGColorSpace.linearGray)!
            )
        }
        
        let h_parameters = h_j.withUnsafeBytes { raw -> CIImage in
            CIImage(
                bitmapData: Data(raw),
                bytesPerRow: log_gmm.count * MemoryLayout<Float>.size,
                size: CGSize(width: log_gmm.count, height: 1),
                format: .Rf,                               // CIFormat
                colorSpace: CGColorSpace(name: CGColorSpace.linearGray)!
            )
        }
        
        let param_num_mixtures = [log_gmm.count].withUnsafeBytes { raw -> CIImage in
            CIImage(
                bitmapData: Data(raw),
                bytesPerRow: MemoryLayout<UInt>.size,
                size: CGSize(width: 1, height: 1),
                format: .Rf,                               // CIFormat
                colorSpace: CGColorSpace(name: CGColorSpace.linearGray)!
            )
        }
        
        let result = Self.kernel1.apply(
            extent: input.extent,
            roiCallback: { _, rect in rect },
            arguments: [input]
        )!
        
        // 4. Apply local contrast enhancement
        
        // 5. Done! Return resultS

        return result
    }
    
    // This function generates a LogHistogram of the image's Luminance values, where outliers are removed
    private func getLogLuminanceHistogram(InputImage: CIImage) -> ([UInt], Float, Float)
    {
        let linHistogramWidth = 100
        let logLumHistWidth = 10
        var retLogHistogram = [UInt](repeating: .zero, count: logLumHistWidth)
        
        let fullImageArea = CGRect(
            x: 0,
            y: 0,
            width: InputImage.extent.width,
            height: InputImage.extent.height)
        
        // 1. calculate luminance image
        
        let colorMonochromeFilter = CIFilter.colorMonochrome()
        colorMonochromeFilter.inputImage = InputImage
        colorMonochromeFilter.color = CIColor(red: 0.33, green: 0.33, blue: 0.33)
        colorMonochromeFilter.intensity = 1
        
        // 2. get linear histogram
        
        let histogramFilter = CIFilter.areaHistogram()
        histogramFilter.inputImage = colorMonochromeFilter.outputImage
        histogramFilter.count = linHistogramWidth
        histogramFilter.scale = 100
        histogramFilter.extent = fullImageArea
        
        // 3. read histogram and cut off upper and lower 5% of image in order to ignore outliers
        
        var histogramValues = [SIMD4<Float32>](repeating: .zero, count: linHistogramWidth)
        context.render(histogramFilter.outputImage!,
                       toBitmap: &histogramValues,
                       rowBytes: MemoryLayout<SIMD4<Float32>>.stride * histogramValues.count,
                       bounds: histogramFilter.outputImage!.extent,
                       format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        
        // 3.1 find lower 5% of values
        
        var sum: Float = 0.0
        
        var minVal: Float = 0.0
        for (i, binValue) in histogramValues.enumerated() {
            sum += binValue.x // x is enough as the other color channels are the same in a monochrome image
            if(sum <= 5.0)
            {
                minVal = (Float(i) / 100.0) * Float(UInt16.max)
            }
            else // sum exceeds 5%
            {
                sum = 0.0 // reset sum for next run
                break // we don't need to go beyond 5%
            }
        }
        
        // 3.2 find upper 5% of values
        
        var maxVal: Float = 0.0
        for (i, binValue) in histogramValues.reversed().enumerated() {
            sum += binValue.x // x is enough as the other color channels are the same in a monochrome image
            if(sum <= 5.0)
            {
                maxVal = (Float(i) / 100.0) * Float(UInt16.max)
            }
            else // sum exceeds 5%
            {
                break // we don't need to go beyond 5%
            }
        }
        
        // 4. calculate log histogram of luminance between cutoff values
        
        let logHistogramFilter = CIFilter.areaLogarithmicHistogram()
        logHistogramFilter.inputImage = colorMonochromeFilter.outputImage!
        logHistogramFilter.count = logLumHistWidth
        logHistogramFilter.scale = 100
        logHistogramFilter.minimumStop = log2(max(minVal, 1e-6))   // convert from 0..100 bins to actual cutoff value
        logHistogramFilter.maximumStop = log2(max(maxVal, 1e-6))   // same with maxValue
        logHistogramFilter.extent = fullImageArea
        
        // 5. read and return logHistogram for CPU usage
        
        var loghistogramValues = [SIMD4<Float32>](repeating: .zero, count: logLumHistWidth)
        context.render(logHistogramFilter.outputImage!,
                       toBitmap: &loghistogramValues,
                       rowBytes: MemoryLayout<SIMD4<Float32>>.stride * loghistogramValues.count,
                       bounds: logHistogramFilter.outputImage!.extent,
                       format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        
        retLogHistogram = loghistogramValues.map({UInt($0.x * 100)})
        
        return (retLogHistogram, minVal, maxVal)
    }
}
