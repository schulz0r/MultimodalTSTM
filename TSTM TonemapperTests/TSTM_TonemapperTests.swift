//
//  TSTM_TonemapperTests.swift
//  TSTM TonemapperTests
//
//  Created by Philipp Waxweiler on 29.03.26.
//

import Testing
import CoreImage
import UniformTypeIdentifiers
import MetalKit

@testable import TSTM_Tonemapper

struct TSTM_TonemapperTests {
    
    @Test func CanToneMap() async throws {
        let context = CIContext()

        // 🔹 Input laden (PNG/JPG aus Bundle oder Pfad)
        let url = URL(fileURLWithPath: "/Users/phiilppwaxweiler.de/Code/TSTM Tonemapper/input3.tiff")
        let inputImage = CIImage(contentsOf: url)!

        // 🔹 Dein Custom Filter
        let filter = TSTMTonemapper()
        filter.inputImage = inputImage

        #expect(nil != filter.outputImage)
        
        let outputImage = filter.outputImage!

        // 🔹 Rendern → CGImage
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw NSError(domain: "RenderError", code: -2)
        }

        // 🔹 Speichern
        let outputURL = URL(fileURLWithPath: "/Users/phiilppwaxweiler.de/Code/TSTM Tonemapper/output2_nakaRushton.tiff")

        let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.tiff.identifier as CFString,
            1,
            nil
        )!

        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
    }

    @Test func CanToneMapAndEnhaceContrast() async throws {
        let context = CIContext()

        // 🔹 Input laden (PNG/JPG aus Bundle oder Pfad)
        let url = URL(fileURLWithPath: "/Users/phiilppwaxweiler.de/Code/TSTM Tonemapper/output1_nakaRushton.tiff")
        let inputImage = CIImage(contentsOf: url)!
        
        let contrastFilter = ContrastEnhancement()
        contrastFilter.inputImage = inputImage
        contrastFilter.alpha = 0.05

        guard let outputImage = contrastFilter.outputImage else {
            throw NSError(domain: "FilterError", code: -1)
        }
        
        // check if NaN happened
        var testValue = SIMD4<Float32>.zero;
        context.render(outputImage,
                       toBitmap: &testValue,
                       rowBytes: MemoryLayout<SIMD4<Float32>>.size,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        
        #expect(!testValue.sum().isNaN) // can not be Nan
        #expect(!testValue.sum().isInfinite) // can not be inf
        #expect(all(testValue .>= 0.0))

        // 🔹 Rendern → CGImage
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw NSError(domain: "RenderError", code: -2)
        }

        // 🔹 Speichern
        let outputURL = URL(fileURLWithPath: "/Users/phiilppwaxweiler.de/Code/TSTM Tonemapper/output_contrast.jpg")

        let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        )!

        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
    }
}

struct TSTM_HistogramTests {
    
    @Test func GmmWorks() async throws {
        var gaussianMixture = [Gaussian]()
        gaussianMixture.append(Gaussian(mean: 3, sigma: 1.0, weight: 0.6))
        gaussianMixture.append(Gaussian(mean: 7, sigma: 1.0, weight: 0.4))
        
        let histogramValues: [Float] = stride(from: Float(0.0), to: 9.0, by: 1.0).map { i in
            let contributions: [Float] = gaussianMixture.map { g in
                g.weight * g.probability(x: i)
            }
            return contributions.reduce(0, +)
        }
        
        let testHist = Histogram(measures: histogramValues, minVal: Float(histogramValues.startIndex), maxVal: Float(histogramValues.endIndex - 1))
        
        let gmm = try fitGaussianMixtureModel(histogram: testHist, numGaussians: 2, numIterations: 30)
        
        #expect(abs(gmm[0].mean - gaussianMixture[0].mean) < 1e-1)
        #expect(abs(gmm[0].variance - gaussianMixture[0].variance) < 1e-1)
        #expect(abs(gmm[0].weight - gaussianMixture[0].weight) < 1e-1)
    }
}
