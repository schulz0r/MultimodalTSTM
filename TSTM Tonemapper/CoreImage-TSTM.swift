//
//  CoreImage-TSTM.swift
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 29.03.26.
//
import CoreImage
import CoreImage.CIFilterBuiltins

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
        // According to S. Ferradans, fitting works better when using a log histogram
        
        let colorMonochromeFilter = CIFilter.colorMonochrome() // this calculates a log2 histogram
        colorMonochromeFilter.inputImage = input
        colorMonochromeFilter.color = CIColor(red: 0.334, green: 0.334, blue: 0.334)
        colorMonochromeFilter.intensity = 1
        
        // get basic luminance image parameters
        let globLuminance = GlobalLuminanceParameters(luminanceImage: colorMonochromeFilter.outputImage!, context: self.context)
        
        // 1.1 get a log histogram (log2 space)
        let logLumHistogram = getLogHistogram(InputImage: colorMonochromeFilter.outputImage!,
                                              logLumHistWidth: numHistBins,
                                              globLuminance: globLuminance)
        
        // 1.2 fit a GMM into the histogram data
        var log_gmm:[Gaussian]
        do
        {
            // try different number of gaussians for best model fit
            let gmm_attempts = try (1..<5).map({
                try fitGaussianMixtureModel(histogram: logLumHistogram, numGaussians: $0, numIterations: 20)
            })
            // find the GMM which with the maximal log likelihood (measure for how well the GMM fits into the data)
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
        var segmentationBorders = calcBayesianSegmentBorders(from: log_gmm, globLuminance: globLuminance)
        
        // 2.2 tiny irrelevant segments destabilize the tone mapping and therefore must be culled
        // the corresponding gaussians will disappear
        cullMicroscopicSegments(gmm: &log_gmm,
                                segBorders: &segmentationBorders,
                                globLuminance: globLuminance)
        
        // save final number of segments
        let gmm_means_lin = log_gmm.map({pow(2.0, $0.mean)}) // pow2 instead of exp() because histogram is log2 space, not log10
        let numClusters = log_gmm.count
        
        // 3. calculate all input parameters for the tone mapping algorithm
        let parameters = TstmParameters(globLuminance: globLuminance,
                                        segBorder: segmentationBorders)
        
        // 3. Apply Naka-Rushton equation
        let result = Self.kernel1.apply(
            extent: input.extent,
            roiCallback: { _, rect in rect },
            arguments: [input,
                        colorMonochromeFilter.outputImage!,
                        Data(bytes: gmm_means_lin, count: MemoryLayout<Float>.stride * gmm_means_lin.count) as NSData,
                        Data(bytes: segmentationBorders.lower, count: MemoryLayout<Float>.stride * segmentationBorders.lower.count) as NSData,
                        Data(bytes: segmentationBorders.upper, count: MemoryLayout<Float>.stride * segmentationBorders.upper.count) as NSData,
                        Data(bytes: parameters.h_j, count: MemoryLayout<Float>.stride * parameters.h_j.count) as NSData,
                        Data(bytes: parameters.c_j, count: MemoryLayout<Float>.stride * parameters.c_j.count) as NSData,
                        parameters.m,
                        globLuminance.µ,
                        numClusters
                       ]
        )!
        
        // 4. Done! Return result. Next Step would be using the ContrastEnhancement CIFilter

        return result
    }
    
    // This function generates a LogHistogram of the image's Luminance values, where outliers are removed
    private func getLogHistogram(InputImage: CIImage, logLumHistWidth: Int, globLuminance: GlobalLuminanceParameters) -> Histogram
    {
        var retLogHistogram = [Float]()
        
        let fullImageArea = CGRect(
            x: 0,
            y: 0,
            width: InputImage.extent.width,
            height: InputImage.extent.height)
        
        // 4. calculate log histogram of luminance between cutoff values
        
        let minVal = log2(max(globLuminance.min, 1e-6))
        let maxVal = log2(max(globLuminance.max, 1e-6))
        
        let logHistogramFilter = CIFilter.areaLogarithmicHistogram()
        logHistogramFilter.inputImage = InputImage
        logHistogramFilter.count = logLumHistWidth
        logHistogramFilter.scale = 1.0  // pixels need to add up to 1.0 like the GMM
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
        
        retLogHistogram = loghistogramValues.map({$0.x}) // only extract one component (they are all equal anyway)
        
        return Histogram(measures: retLogHistogram, minVal: minVal, maxVal: maxVal)
    }
}

// parameter structs

struct GlobalLuminanceParameters
{
    let min:Float
    let max:Float
    let µ:Float
    
    init(luminanceImage: CIImage, context: CIContext)
    {
        let minMaxFilter = CIFilter.areaMinMax()
        minMaxFilter.inputImage = luminanceImage
        minMaxFilter.extent = luminanceImage.extent
        
        let avgFilter = CIFilter.areaAverage()
        avgFilter.inputImage = luminanceImage
        avgFilter.extent = luminanceImage.extent
        
        var minMax:[SIMD4<Float32>] = [SIMD4<Float32>](repeating: .zero, count: Int(minMaxFilter.outputImage!.extent.width))
        context.render(minMaxFilter.outputImage!,
                       toBitmap: &minMax,
                       rowBytes: MemoryLayout<SIMD4<Float32>>.size * minMax.count,
                       bounds: minMaxFilter.outputImage!.extent,
                       format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        
        var avg:SIMD4<Float32> = .zero
        context.render(avgFilter.outputImage!,
                       toBitmap: &avg,
                       rowBytes: MemoryLayout<SIMD4<Float32>>.size,
                       bounds: avgFilter.outputImage!.extent,
                       format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        
        self.min = minMax.first!.x
        self.max = minMax.last!.x
        self.µ = avg.x
    }
}

private struct TstmParameters
{
    let h_j:[Float]
    let c_j:[Float]
    let m:Float
    
    public init(globLuminance: GlobalLuminanceParameters, segBorder: SegmentationBorders)
    {
        
        // calculate m from the luminance average
        let _m = (pow(globLuminance.µ, 2.0) - (globLuminance.max * globLuminance.min)) / (globLuminance.max + globLuminance.min - (2 * globLuminance.µ)) // linear space
        
        // h_j
        let h_array:[Float] = zip(segBorder.lower, segBorder.upper).map
        { (luMin, LuMax) in
            log( (_m + LuMax) / (_m + luMin) )
        }
        let h_sum = h_array.reduce(0, +)
        let _h_j = h_array.map{$0 / h_sum}
        
        // c_j
        let _c_j = [0.0] + (1..<_h_j.endIndex).map{ j in _h_j[0...(j-1)].reduce(0, +) }
        
        self.m = _m
        self.h_j = _h_j
        self.c_j = _c_j
    }
}
