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
        // input image comes in floating point representation. For SDR images that means pixel range [0.0...1.0]
        guard let input = inputImage else { return nil }
        
        let numHistBins = 32
        
        // 1. we need to fit gaussians into the image histogram of the luminance
        // According to Ferradans, fitting works better when using a log histogram
        
        let colorMonochromeFilter = CIFilter.colorMonochrome()
        colorMonochromeFilter.inputImage = input
        colorMonochromeFilter.color = CIColor(red: 0.334, green: 0.334, blue: 0.334)
        colorMonochromeFilter.intensity = 1
        
        // 1.1 get a log histogram (log2 space)
        let logLumHistogram = getLogHistogram(InputImage: colorMonochromeFilter.outputImage!,
                                              logLumHistWidth: numHistBins)
        
        let lambda_min = pow(2.0, logLumHistogram.labels.first!)
        let lambda_max = pow(2.0, logLumHistogram.labels.last!)
        
        // 1.2 fit a GMM into the histogram data
        let nGaussians:UInt = UInt( (lambda_max - lambda_min) * 2.0 )
        
        let log_gmm:[Gaussian]
        do
        {
            let gmm_attempts = try (1..<5).map({
                try fitGaussianMixtureModel(histogram: logLumHistogram, numGaussians: $0, numIterations: 20)
            })
            log_gmm = gmm_attempts.max(by: { mix1, mix2 in
                return logLikelihood(model: mix1, histogram: logLumHistogram) < logLikelihood(model: mix2, histogram: logLumHistogram)
            })!
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
            max( ( pow(2.0, mu_plus_log[j - 1]) + pow(2.0, mu_minus_log[j])) / 2.0, pow(2.0, mu_plus_log[j - 1]) )
        }
        
        let luminance_max:[Float] = (0..<(log_gmm.count - 1)).map // linear space
        {   j in
            min( (pow(2.0, mu_plus_log[j]) + pow(2.0, mu_minus_log[j + 1])) / 2.0, pow(2.0, mu_minus_log[j + 1]) )
        } + [lambda_max]
        
        // 2.1 calculate m from the luminance average
        let mu_avg: Float = logLumHistogram.getLinAverageFromLogData()
        
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
        
        // 1. get min and max value
        
        let minMaxFilter = CIFilter.areaMinMax()
        minMaxFilter.inputImage = InputImage
        minMaxFilter.extent = fullImageArea
        
        var minMax:[SIMD4<Float32>] = [SIMD4<Float32>](repeating: .zero, count: Int(minMaxFilter.outputImage!.extent.width))
        context.render(minMaxFilter.outputImage!,
                       toBitmap: &minMax,
                       rowBytes: MemoryLayout<SIMD4<Float32>>.size * minMax.count,
                       bounds: minMaxFilter.outputImage!.extent,
                       format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        
        let minVal = log2(max(minMax.first!.x - 1e-3, 1e-12))
        let maxVal = log2(max(minMax.last!.x + 1e-3, 1e-6))
        
        // 4. calculate log histogram of luminance between cutoff values
        
        let logHistogramFilter = CIFilter.areaLogarithmicHistogram()
        logHistogramFilter.inputImage = InputImage
        logHistogramFilter.count = logLumHistWidth
        logHistogramFilter.scale = 100
        logHistogramFilter.minimumStop = minVal
        logHistogramFilter.maximumStop = maxVal
        logHistogramFilter.extent = fullImageArea
        
        // 5. read and return logHistogram for CPU usage
        
        var loghistogramValues = [SIMD4<Float32>](repeating: .zero, count: logLumHistWidth)
        context.render(logHistogramFilter.outputImage!,
                       toBitmap: &loghistogramValues,
                       rowBytes: MemoryLayout<SIMD4<Float32>>.size * loghistogramValues.count,
                       bounds: logHistogramFilter.outputImage!.extent,
                       format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        
        retLogHistogram = loghistogramValues.map({UInt($0.x * 100)})
        
        return Histogram(measures: retLogHistogram, minVal: minVal, maxVal: maxVal)
    }
}
