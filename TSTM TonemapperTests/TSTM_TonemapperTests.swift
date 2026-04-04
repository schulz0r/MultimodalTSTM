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

    @Test func GmmWorks() async throws {
        var gaussianMixture = [Gaussian]()
        gaussianMixture.append(Gaussian(mean: 3, sigma: 1.0, weight: 0.6))
        gaussianMixture.append(Gaussian(mean: 7, sigma: 1.0, weight: 0.4))
        
        let histogram: [UInt] = (0..<10).map { i in
            let contributions: [UInt] = gaussianMixture.map { g in
                UInt((100.0 * g.weight * g.probability(x: Float(i))).rounded())
            }
            return contributions.reduce(0, +)
        }
        
        let gmm = fitGaussianMixtureModel(histogram: histogram, numGaussians: 2, numIterations: 30)
        
        #expect(abs(gmm[0].mean - gaussianMixture[0].mean) < 1e-1)
        #expect(abs(gmm[0].sigma - gaussianMixture[0].sigma) < 1e-1)
        #expect(abs(gmm[0].weight - gaussianMixture[0].weight) < 1e-1)
    }
    
    @Test func CanToneMap() async throws {
        let context = CIContext()

        // 🔹 Input laden (PNG/JPG aus Bundle oder Pfad)
        let url = URL(fileURLWithPath: "/Users/phiilppwaxweiler.de/Code/TSTM Tonemapper/input.tiff")
        let inputImage = CIImage(contentsOf: url)!

        // 🔹 Dein Custom Filter
        let filter = TSTMTonemapper()
        filter.inputImage = inputImage

        guard let outputImage = filter.outputImage else {
            throw NSError(domain: "FilterError", code: -1)
        }

        // 🔹 Rendern → CGImage
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw NSError(domain: "RenderError", code: -2)
        }

        // 🔹 Speichern
        let outputURL = URL(fileURLWithPath: "/Users/phiilppwaxweiler.de/Code/TSTM Tonemapper/output.jpg")

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
