//
//  CoreImage-ContrastEnhancement.swift
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 13.04.26.
//

import CoreImage

final class ContrastEnhancement: CIFilter {

    @objc dynamic var inputImage: CIImage?
    // parameters
    @objc dynamic var stepSize: Float = 0.1
    @objc dynamic var alpha: Float = 0.5
    @objc dynamic var beta: Float = 1.0
    
    private let context = CIContext()
    
    private static let raceKernel: CIKernel = {
        let url = Bundle(for: TSTMTonemapper.self).url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIKernel(functionName: "rACE", fromMetalLibraryData: data)
    }()
    private static let contrastKernel: CIKernel = {
        let url = Bundle(for: TSTMTonemapper.self).url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIKernel(functionName: "contrastEnhance", fromMetalLibraryData: data)
    }()
    
    override func setDefaults()
    {
        stepSize = 0.1
        alpha = 0.5
        beta = 1.0
    }

    override var outputImage: CIImage?
    {
        // input image comes in floating point representation. For SDR images that means pixel range [0.0...1.0]
        guard let input = inputImage else { return nil }
        let dt = stepSize
        let alpha = self.alpha
        let beta = self.beta
        
        var contrastEnhanced:CIImage? = nil
        var rACE:CIImage? = nil
        
        for _ in (0..<1)
        {
            rACE = Self.raceKernel.apply(extent: input.extent,
                                         roiCallback: { _, rect in rect },
                                         arguments: [contrastEnhanced ?? input]) // I_k
            
            contrastEnhanced = Self.contrastKernel.apply(
                extent: input.extent,
                roiCallback: { _, rect in rect },
                arguments: [input,  // I_0
                            contrastEnhanced ?? input,  // I_k
                            rACE!,
                            dt, alpha, beta
                           ]
            )!
             
        }
        return contrastEnhanced
    }
}

