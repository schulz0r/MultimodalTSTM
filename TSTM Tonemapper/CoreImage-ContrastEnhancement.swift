//
//  CoreImage-ContrastEnhancement.swift
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 13.04.26.
//

import CoreImage
import UniformTypeIdentifiers

final class ContrastEnhancement: CIFilter {

    @objc dynamic var inputImage: CIImage?
    // parameters
    @objc dynamic var stepSize: Float = 0.1
    @objc dynamic var alpha: Float = 0.5
    @objc dynamic var beta: Float = 1.0
    
    private let context = CIContext()
    
    private static let sineImageKernel: CIKernel = {
        let url = Bundle(for: TSTMTonemapper.self).url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIKernel(functionName: "sineImage", fromMetalLibraryData: data)
    }()
    
    private static let cosineImageKernel: CIKernel = {
        let url = Bundle(for: TSTMTonemapper.self).url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIKernel(functionName: "cosineImage", fromMetalLibraryData: data)
    }()
    
    private static let contrastTermKernel: CIKernel = {
        let url = Bundle(for: TSTMTonemapper.self).url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIKernel(functionName: "contrastTermApprox", fromMetalLibraryData: data)
    }()
    
    private static let contrastKernel: CIKernel = {
        let url = Bundle(for: TSTMTonemapper.self).url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIKernel(functionName: "contrastEnhance", fromMetalLibraryData: data)
    }()
    
    override func setDefaults()
    {
        stepSize = 0.15
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
        
        let T:Float = 2.0
        let K = 9
        var w_k:Float = 0.0
        var beta_k:Float = 0.0
        
        for _ in (0..<1)
        {
            var R_ACE = CIImage(color: CIColor(red: 0.0, green: 0.0, blue: 0.0)).cropped(to: input.extent)
            
            for k in (1...K)
            {
                w_k = (2.0 * Float.pi * Float(k)) / T
                beta_k = (2.0 / (T * w_k)) * (1.0 - pow(-1.0, Float(k)))
                
                let sineImg = Self.sineImageKernel.apply(extent: input.extent,
                                                         roiCallback: { _, rect in rect },
                                                         arguments: [contrastEnhanced ?? input,
                                                                     w_k])
                let cosineImg = Self.cosineImageKernel.apply(extent: input.extent,
                                                           roiCallback: { _, rect in rect },
                                                           arguments: [contrastEnhanced ?? input,
                                                                       w_k])
                // Gauss
                let blurSineFilter = CIFilter.gaussianBlur()
                blurSineFilter.inputImage = sineImg
                blurSineFilter.radius = 200
                
                let blurCosineFilter = CIFilter.gaussianBlur()
                blurCosineFilter.inputImage = cosineImg
                blurCosineFilter.radius = 200
                
                // add to ACE
                R_ACE = Self.contrastTermKernel.apply(extent: input.extent,
                                                      roiCallback: { _, rect in rect },
                                                      arguments: [contrastEnhanced ?? input,
                                                                  blurSineFilter.outputImage!,
                                                                  blurCosineFilter.outputImage!,
                                                                  R_ACE,
                                                                  w_k,
                                                                  beta_k
                                                                 ])!
            }
            
            contrastEnhanced = Self.contrastKernel.apply(extent: input.extent,
                                                        roiCallback: { _, rect in rect },
                                                        arguments: [input,  // I_0
                                                                    contrastEnhanced ?? input,  // I_k
                                                                    R_ACE,
                                                                    dt, alpha, beta
                                                                   ]
            )!
        }
        return contrastEnhanced
    }
}

