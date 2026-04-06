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
        
        let numHistBins = 32
        
        // 1. we need to fit gaussians into the image histogram of the luminance
        // According to Ferradans, fitting works better when using a log histogram
        
        let colorMonochromeFilter = CIFilter.colorMonochrome()
        colorMonochromeFilter.inputImage = input
        colorMonochromeFilter.color = CIColor(red: 0.33, green: 0.33, blue: 0.33)
        colorMonochromeFilter.intensity = 1
        
        // 1.1 get a log histogram (log2 space)
        let logLumHistogram = getLogHistogram(InputImage: colorMonochromeFilter.outputImage!,
                                              logLumHistWidth: numHistBins)
        
        let lambda_min = pow(2.0, logLumHistogram.labels.first!)
        let lambda_max = pow(2.0, logLumHistogram.labels.last!)
        
        // 1.2 fit a GMM into the histogram data
        let nGaussians:UInt = 2 //UInt((logLumHistogram.labels.last! - logLumHistogram.labels.first!).rounded())
        
        let log_gmm:[Gaussian]
        do
        {
            log_gmm = try fitGaussianMixtureModel(histogram: logLumHistogram, numGaussians: nGaussians, numIterations: 20)
        }
        catch
        {
            print("GMM fitting failed: \(error)")
            return nil
        }
        
        // 2. calculate input values for the tonemapper
        // 2.1 calculate value ranges
        let mu_minus_log = log_gmm.map{$0.mean - (2 * $0.sigma)} // log2 space
        let mu_plus_log = log_gmm.map{$0.mean + (2 * $0.sigma)} // log2 space
        
        let luminance_min:[Float] = [lambda_min] + (1..<log_gmm.count).map // linear space
        {   j in
            max( pow(2.0, (mu_plus_log[j - 1] + mu_minus_log[j]) / 2.0), pow(2.0, mu_plus_log[j - 1]) )
        }
        
        let luminance_max:[Float] = (0..<(log_gmm.count - 1)).map // linear space
        {   j in
            min( pow(2.0, (mu_plus_log[j] + mu_minus_log[j + 1]) / 2.0), pow(2.0, mu_minus_log[j + 1]) )
        } + [lambda_max]
        
        // 2.1 calculate m from the luminance average
        let mu_avg: Float = logLumHistogram.getLinAverageFromLogData() * Float(UInt16.max) // lin space
        
        let m = (pow(mu_avg, 2.0) - (lambda_max * lambda_min)) / (lambda_max + lambda_min - (2 * mu_avg)) // linear space
        
        // h_j
        let h_array = zip(mu_minus_log, mu_plus_log).map
        { (luMin, LuMax) in
            log( (m + pow(2.0, LuMax)) / (m + pow(2.0, luMin)) )
        }
        let h_sum = h_array.reduce(0, +)
        let h_j:[Float] = h_array.map{$0 / h_sum}
        
        // c_j
        var c_j = [Float](repeating: 0.0, count: 1)
        for j in (1..<h_j.endIndex)
        {
            c_j.append(h_j[0...(j-1)].reduce(0, +))
        }
        
        let gmm_means_lin = log_gmm.map({pow(2.0, $0.mean)})
        let numClusters = log_gmm.count
        
        // 3. Apply Naka-Rushton equation
        
        let result = Self.kernel1.apply(
            extent: input.extent,
            roiCallback: { _, rect in rect },
            arguments: [input,
                        colorMonochromeFilter.outputImage!,
                        Data(bytes: gmm_means_lin, count: MemoryLayout<Float>.stride * gmm_means_lin.count) as NSData,
                        Data(bytes: luminance_min, count: MemoryLayout<Float>.stride * luminance_min.count) as NSData,
                        Data(bytes: luminance_max, count: MemoryLayout<Float>.stride * luminance_max.count) as NSData,
                        Data(bytes: h_j, count: MemoryLayout<Float>.stride * h_j.count) as NSData,
                        Data(bytes: c_j, count: MemoryLayout<Float>.stride * c_j.count) as NSData,
                        m,
                        mu_avg,
                        numClusters
                       ]
        )!
        
        // 4. Apply local contrast enhancement
        
        // 5. Done! Return resultS

        return result
    }
    
    // This function generates a LogHistogram of the image's Luminance values, where outliers are removed
    private func getLogHistogram(InputImage: CIImage, logLumHistWidth: Int) -> Histogram
    {
        let linHistogramWidth = 100
        let cullPercentOutliers:Float = 3.0
        var retLogHistogram = [UInt](repeating: .zero, count: logLumHistWidth)
        
        let fullImageArea = CGRect(
            x: 0,
            y: 0,
            width: InputImage.extent.width,
            height: InputImage.extent.height)
        
        // 1. calculate luminance image
        
        // TODO: remove this
        
        // 2. get linear histogram
        
        let histogramFilter = CIFilter.areaHistogram()
        histogramFilter.inputImage = InputImage
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
        
        // 3.1 find lower x% of values
        
        var sum: Float = 0.0
        
        var minVal: Float = log2(1e-6)
        for (i, binValue) in histogramValues.enumerated() {
            sum += binValue.x // x is enough as the other color channels are the same in a monochrome image
            if(sum <= cullPercentOutliers)
            {
                minVal = (Float(i) / Float(linHistogramWidth)) * Float(UInt16.max)
                minVal = log2(max(minVal, 1e-6))
            }
            else // sum exceeds x%
            {
                sum = 0.0 // reset sum for next run
                break // we don't need to go beyond x%
            }
        }
        
        // 3.2 find upper x% of values
        
        var maxVal: Float = log2(Float(UInt16.max))
        for (i, binValue) in histogramValues.reversed().enumerated() {
            sum += binValue.x // x is enough as the other color channels are the same in a monochrome image
            if(sum <= cullPercentOutliers)
            {
                maxVal = (Float(histogramValues.count - 1 - i) / Float(linHistogramWidth)) * Float(UInt16.max)
                maxVal = log2(max(maxVal, 1e-6))
            }
            else // sum exceeds x%
            {
                break // we don't need to go beyond x%
            }
        }
        
        // 4. calculate log histogram of luminance between cutoff values
        
        let logHistogramFilter = CIFilter.areaLogarithmicHistogram()
        logHistogramFilter.inputImage = InputImage
        logHistogramFilter.count = logLumHistWidth
        logHistogramFilter.scale = 100
        logHistogramFilter.minimumStop = minVal // convert from 0..100 bins to actual cutoff value
        logHistogramFilter.maximumStop = maxVal // same with maxValue
        logHistogramFilter.extent = fullImageArea
        
        let filter = CIFilter.histogramDisplay()
        filter.inputImage = logHistogramFilter.outputImage!
            filter.highLimit = 1
            filter.height = 100
            filter.lowLimit = 0
            let histImg = filter.outputImage!
        
        // 5. read and return logHistogram for CPU usage
        
        var loghistogramValues = [SIMD4<Float32>](repeating: .zero, count: logLumHistWidth)
        context.render(logHistogramFilter.outputImage!,
                       toBitmap: &loghistogramValues,
                       rowBytes: MemoryLayout<SIMD4<Float32>>.stride * loghistogramValues.count,
                       bounds: logHistogramFilter.outputImage!.extent,
                       format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        
        retLogHistogram = loghistogramValues.map({UInt($0.x * 100)})
        
        return Histogram(measures: retLogHistogram, minVal: minVal, maxVal: maxVal)
    }
}
