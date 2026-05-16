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
        
        
        // 1. we need to fit gaussians into the image histogram of the luminance
        // According to S. Ferradans, fitting works better when using a log histogram
        
        let colorMonochromeFilter = CIFilter.colorMonochrome() // this calculates a log2 histogram
        colorMonochromeFilter.inputImage = input
        colorMonochromeFilter.color = CIColor(red: 0.334, green: 0.334, blue: 0.334)
        colorMonochromeFilter.intensity = 1
        
        // get basic luminance image parameters
        let globLuminance = GlobalLuminanceParameters(luminanceImage: colorMonochromeFilter.outputImage!, context: self.context)
        
        let (segmentationBorders, means) = segmentImage(lumImage: colorMonochromeFilter.outputImage!, luminanceParams: globLuminance)
        
        // 3. calculate all input parameters for the tone mapping algorithm
        let f_G = calcToneCurve(globLuminance: globLuminance, segBorders: segmentationBorders, means: means)
        
        // 3. Apply Naka-Rushton equation
        let result = Self.kernel1.apply(
            extent: input.extent,
            roiCallback: { _, rect in rect },
            arguments: [input,
                        colorMonochromeFilter.outputImage!,
                        Data(bytes: f_G, count: MemoryLayout<Float>.stride * f_G.count) as NSData,
                        f_G.count // length of the tone curve
                       ]
        )!
        
        // 4. Done! Return result. Next Step would be using the ContrastEnhancement CIFilter
        return result
    }
    
    // This function generates a LogHistogram of the image's Luminance values, where outliers are removed
    private func getLogHistogram(InputImage: CIImage, logLumHistWidth: Int, globLuminance: GlobalLuminanceParameters) -> Histogram
    {
        var retLogHistogram = [Float]()
        
        // calculate log histogram of luminance between cutoff values
        
        let minVal = log2(max(globLuminance.min, 1e-6))
        let maxVal = log2(max(globLuminance.max, 1e-6))
        
        let logHistogramFilter = CIFilter.areaLogarithmicHistogram()
        logHistogramFilter.inputImage = InputImage
        logHistogramFilter.count = logLumHistWidth
        logHistogramFilter.scale = 1.0  // pixels need to add up to 1.0 like the GMM
        logHistogramFilter.minimumStop = minVal
        logHistogramFilter.maximumStop = maxVal
        logHistogramFilter.extent = InputImage.extent
        
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
    
    private func segmentImage(lumImage: CIImage, luminanceParams: GlobalLuminanceParameters) -> ([SegmentationBorder], [Float])
    {
        let numHistBins = 32
        
        // 1. get a log histogram (log2 space)
        let logLumHistogram = getLogHistogram(InputImage: lumImage,
                                              logLumHistWidth: numHistBins,
                                              globLuminance: luminanceParams)
        
        // 2. fit a GMM into the histogram data
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
            return ([], [])
        }
        
        // 3. calculate input values for the tonemapper
        // 3.1 calculate value ranges
        var segmentationBorders = calcBayesianSegmentBorders(from: log_gmm, globLuminance: luminanceParams)
        
        // 3.2 tiny irrelevant segments destabilize the tone mapping and therefore must be culled
        // the corresponding gaussians will disappear
        cullMicroscopicSegments(gmm: &log_gmm,
                                segBorders: &segmentationBorders,
                                globLuminance: luminanceParams)
        
        let gmm_means_lin = log_gmm.map({pow(2.0, $0.mean)}) // pow2 instead of exp() because histogram is log2 space, not log10
        
        return (segmentationBorders, gmm_means_lin)
    }
    
    private func calcToneCurve(globLuminance: GlobalLuminanceParameters, segBorders: [SegmentationBorder], means: [Float]) -> [Float]
    {
        
        // calculate m from the luminance average
        let m = (pow(globLuminance.µ, 2.0) - (globLuminance.max * globLuminance.min)) / (globLuminance.max + globLuminance.min - (2 * globLuminance.µ)) // linear space
        
        // h_j
        let h_array:[Float] = segBorders.map
        { border in
            log( (m + border.upper) / (m + border.lower) )
        }
        let h_sum = h_array.reduce(0, +)
        let h_j = h_array.map{$0 / h_sum}
        
        // c_j
        let c_j = [0.0] + (1..<h_j.endIndex).map{ j in h_j[0...(j-1)].reduce(0, +) }

        let lumVals = stride(from: globLuminance.min, through: globLuminance.max, by: (globLuminance.max - globLuminance.min) / 256.0)
        
        let f_G:[Float] = lumVals.map({ luminance in
            var r_G: Float = 0.0
            for (j, segment) in segBorders.enumerated()
            {
                if( segment.contains(x: luminance) )
                {
                    let nakaRushton_r = normNakaRushtonEquation(lambda: luminance,
                                                                mean: means[j],
                                                                segment: segment,
                                                                mu_avg: globLuminance.µ);
                    
                    r_G += c_j[j] + (h_j[j] * nakaRushton_r); // equation (21)
                } // else: nothing
            }
            return (luminance / (r_G + 1e-8)) - luminance; // equation (24)
        })
        
        return f_G;
    }
    
    private func normNakaRushtonEquation(lambda: Float,
                                         mean: Float,
                                         segment: SegmentationBorder,
                                         mu_avg: Float) -> Float
    {
        var m_j: Float = ((pow(mu_avg, 2.0) - (segment.upper * segment.lower)) ) / (segment.upper + segment.lower - (2 * mean)); // equation (20)
        m_j = max(1e-8,  m_j); // equation (20) part 2. Cannot be 0 because equation (12) contains a log(x) where x cannot be 0
        
        let k_j: Float = 1.0 / log( (m_j + segment.upper) / (m_j + segment.lower) );   // equation (19)
        let C: Float = 0.5 - (k_j * log(m_j * mean));  // equation (13)
        
        let r_luminance = C + (k_j * log(m_j + lambda)); // equation (12)
        let r_luminance_min = C + (k_j * log(m_j + segment.lower));
        let r_luminance_max = C + (k_j * log(m_j + segment.upper));
        
        return (r_luminance - r_luminance_min) / (r_luminance_max - r_luminance_min); // equation (18)
    }
}

// parameter structs

extension GlobalLuminanceParameters
{    
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
