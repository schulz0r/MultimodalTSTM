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
    @objc dynamic var stepSize: Float = 0.2
    @objc dynamic var alpha: Float = 255.0 / 253.0
    @objc dynamic var beta: Float = 1.0
    

    private let context = CIContext(options:
                                        [.workingColorSpace: CGColorSpace(name: CGColorSpace.genericRGBLinear)!,
                                         .outputColorSpace: CGColorSpace(name: CGColorSpace.genericRGBLinear)!])

    
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
        stepSize = 0.2
        alpha = 255.0 / 253.0
        beta = 1.0
    }

    override var outputImage: CIImage?
    {
        // input image comes in floating point representation. For SDR images that means pixel range [0.0...1.0]
        guard let input = inputImage else { return nil }
        let dt:Float = stepSize
        let alpha:Float = self.alpha
        let beta:Float = self.beta
        
        var contrastEnhanced:CIImage? = nil
        
        for _ in (0..<2)
        {
            let contrastTerm = calcContrastFunctional(image: contrastEnhanced ?? input)
            
            contrastEnhanced = Self.contrastKernel.apply(extent: input.extent,
                                                        roiCallback: { _, rect in rect },
                                                        arguments: [input,  // I_0
                                                                    contrastEnhanced ?? input,  // I_k
                                                                    contrastTerm,
                                                                    dt, alpha, beta
                                                                   ]
                                                         )!
        }
        return contrastEnhanced
    } // override var outputImage: CIImage?
    
    private func calcContrastFunctional(image: CIImage) -> CIImage
    {
        let K = 9
        let gaussKernelSize:Float = 200.0
        
        let w:[Float] = (0...K).map({2.0 * Float.pi * Float($0)})
        
        var contrastTerm = CIImage(color: CIColor(red: 0.0, green: 0.0, blue: 0.0)).cropped(to: image.extent)
        
        for m in (0...K)
        {
            let sineImg = Self.sineImageKernel.apply(extent: image.extent,
                                                     roiCallback: { _, rect in rect },
                                                     arguments: [image,
                                                                 w[m] ])
            
            let cosineImg = Self.cosineImageKernel.apply(extent: image.extent,
                                                         roiCallback: { _, rect in rect },
                                                         arguments: [image,
                                                                     w[m] ])
            // Gauss
            let S_m = CIFilter.gaussianBlur()
            S_m.inputImage = sineImg
            S_m.radius = gaussKernelSize
            
            let C_m = CIFilter.gaussianBlur()
            C_m.inputImage = cosineImg
            C_m.radius = gaussKernelSize
            
            // add to ACE
            contrastTerm = Self.contrastTermKernel.apply(extent: image.extent,
                                                         roiCallback: { _, rect in rect },
                                                         arguments: [image,
                                                                      S_m.outputImage!,
                                                                      C_m.outputImage!,
                                                                      contrastTerm,
                                                                      Data(bytes: w, count: MemoryLayout<Float>.stride * w.count) as NSData,
                                                                      Data(bytes: alpha_n[m], count: MemoryLayout<Float>.stride * alpha_n[m].count) as NSData,
                                                                      Data(bytes: beta_n[m], count: MemoryLayout<Float>.stride * beta_n[m].count) as NSData,
                                                                      Data(bytes: gamma_n[m], count: MemoryLayout<Float>.stride * gamma_n[m].count) as NSData,
                                                                      Data(bytes: delta_n[m], count: MemoryLayout<Float>.stride * delta_n[m].count) as NSData,
                                                                      K ])!
        } // contrast term approximation
        
        return contrastTerm
    }
    
    private let alpha_n:[[Float]] = [[ 0.00000000e+00,  1.09466075e-01,  4.38294190e-02,  2.51860710e-02,
                              1.69097316e-02,  1.23909838e-02,  9.60525216e-03,  7.74426699e-03,
                              6.42785808e-03,  5.45587759e-03],
                            [-1.09466075e-01, -3.81639165e-17,  1.04693329e-02,  7.55215074e-03,
                              5.59844590e-03,  4.34643679e-03,  3.50207399e-03,  2.90382518e-03,
                              2.46244579e-03,  2.12598761e-03],
                            [-4.38294190e-02, -1.04693329e-02,  5.20417043e-18,  2.93387489e-03,
                              2.69952492e-03,  2.29330959e-03,  1.94442629e-03,  1.66697791e-03,
                              1.44766333e-03,  1.27254574e-03],
                            [-2.51860710e-02, -7.55215074e-03, -2.93387489e-03, -8.67361738e-19,
                              1.24921379e-03,  1.31386788e-03,  1.21497409e-03,  1.09296364e-03,
                              9.79057105e-04,  8.79626316e-04],
                            [-1.69097316e-02, -5.59844590e-03, -2.69952492e-03, -1.24921379e-03,
                              1.30104261e-18,  6.54269870e-04,  7.49687218e-04,  7.35060886e-04,
                              6.90304286e-04,  6.39173901e-04],
                            [-1.23909838e-02, -4.34643679e-03, -2.29330959e-03, -1.31386788e-03,
                             -6.54269870e-04,  1.30104261e-18,  3.88359284e-04,  4.72546785e-04,
                              4.83740087e-04,  4.69457415e-04],
                            [-9.60525216e-03, -3.50207399e-03, -1.94442629e-03, -1.21497409e-03,
                             -7.49687218e-04, -3.88359284e-04, -8.67361738e-19,  2.50772477e-04,
                              3.19088401e-04,  3.37679371e-04],
                            [-7.74426699e-03, -2.90382518e-03, -1.66697791e-03, -1.09296364e-03,
                             -7.35060886e-04, -4.72546785e-04, -2.50772477e-04, -2.16840434e-19,
                              1.72055150e-04,  2.26667376e-04],
                            [-6.42785808e-03, -2.46244579e-03, -1.44766333e-03, -9.79057105e-04,
                             -6.90304286e-04, -4.83740087e-04, -3.19088401e-04, -1.72055150e-04,
                              2.16840434e-19,  1.23582782e-04],
                            [-5.45587759e-03, -2.12598761e-03, -1.27254574e-03, -8.79626316e-04,
                             -6.39173901e-04, -4.69457415e-04, -3.37679371e-04, -2.26667376e-04,
                             -1.23582782e-04, -8.67361738e-19]];
    
    private let beta_n:[[Float]] = [[ 0.0       ,  0.0       ,  0.0       ,  0.0       ,  0.0       ,
                             0.0       ,  0.0       ,  0.0       ,  0.0       ,  0.0       ],
                           [ 0.36764631, -0.57980561,  0.02086   ,  0.01125728,  0.00728074,
                             0.00520174,  0.00395806,  0.00314565,  0.00258094,  0.00216984],
                           [ 0.16188543,  0.01883058, -0.30242648,  0.00881677,  0.00571938,
                             0.0040935 ,  0.00311884,  0.0024812 ,  0.00203745,  0.00171409],
                           [ 0.10120707,  0.00921274,  0.00846139, -0.20473534,  0.00487755,
                             0.00349487,  0.00266433,  0.00212053,  0.00174188,  0.00146585],
                           [ 0.07285935,  0.00541319,  0.00527864,  0.00476044, -0.15475324,
                             0.00310439,  0.00236807,  0.00188527,  0.00154894,  0.00130369],
                           [ 0.05660711,  0.00351496,  0.00363923,  0.00333232,  0.00305247,
                            -0.12436881,  0.00215447,  0.00171589,  0.00141   ,  0.00118687],
                           [ 0.04612809,  0.00242853,  0.00267415,  0.00248376,  0.00229062,
                             0.00212701, -0.1039361 ,  0.00158595,  0.00130358,  0.0010974 ],
                           [ 0.03883431,  0.00174894,  0.00205374,  0.00193393,  0.00179463,
                             0.00167278,  0.00156958, -0.0892487 ,  0.00121843,  0.00102593],
                           [ 0.03347657,  0.00129632,  0.00162923,  0.00155491,  0.00145147,
                             0.00135755,  0.0012769 ,  0.0012078 , -0.07817855,  0.00096696],
                           [ 0.02938028,  0.00098051,  0.00132493,  0.00128127,  0.00120287,
                             0.0011287 ,  0.00106395,  0.00100808,  0.00095959, -0.06953324]];
    
    private let gamma_n:[[Float]] = [[ 0.0        , -0.36764631, -0.16188543, -0.10120707, -0.07285935,
                              -0.05660711, -0.04612809, -0.03883431, -0.03347657, -0.02938028],
                             [ 0.0       ,  0.57980561, -0.01883058, -0.00921274, -0.00541319,
                              -0.00351496, -0.00242853, -0.00174894, -0.00129632, -0.00098051],
                             [ 0.0       , -0.02086   ,  0.30242648, -0.00846139, -0.00527864,
                              -0.00363923, -0.00267415, -0.00205374, -0.00162923, -0.00132493],
                             [ 0.0       , -0.01125728, -0.00881677,  0.20473534, -0.00476044,
                              -0.00333232, -0.00248376, -0.00193393, -0.00155491, -0.00128127],
                             [ 0.0       , -0.00728074, -0.00571938, -0.00487755,  0.15475324,
                              -0.00305247, -0.00229062, -0.00179463, -0.00145147, -0.00120287],
                             [ 0.0       , -0.00520174, -0.0040935 , -0.00349487, -0.00310439,
                               0.12436881, -0.00212701, -0.00167278, -0.00135755, -0.0011287 ],
                             [ 0.0       , -0.00395806, -0.00311884, -0.00266433, -0.00236807,
                              -0.00215447,  0.1039361 , -0.00156958, -0.0012769 , -0.00106395],
                             [ 0.0       , -0.00314565, -0.0024812 , -0.00212053, -0.00188527,
                              -0.00171589, -0.00158595,  0.0892487 , -0.0012078 , -0.00100808],
                             [ 0.0       , -0.00258094, -0.00203745, -0.00174188, -0.00154894,
                              -0.00141   , -0.00130358, -0.00121843,  0.07817855, -0.00095959],
                             [ 0.0       , -0.00216984, -0.00171409, -0.00146585, -0.00130369,
                              -0.00118687, -0.0010974 , -0.00102593, -0.00096696,  0.06953324]];
    
    private let delta_n:[[Float]] = [[ 0.00000000e+00,  0.00000000e+00,  0.00000000e+00,  0.00000000e+00,
                              0.00000000e+00,  0.00000000e+00,  0.00000000e+00,  0.00000000e+00,
                              0.00000000e+00,  0.00000000e+00],
                            [ 0.00000000e+00, -2.77555756e-17,  1.69504757e-02,  1.44282880e-02,
                              1.20628100e-02,  1.02899905e-02,  8.95428961e-03,  7.92072037e-03,
                              7.09956696e-03,  6.43208476e-03],
                            [ 0.00000000e+00, -1.69504757e-02,  1.73472348e-18,  4.34361355e-03,
                              4.51654256e-03,  4.21106863e-03,  3.85015610e-03,  3.51621834e-03,
                              3.22353103e-03,  2.97020268e-03],
                            [ 0.00000000e+00, -1.44282880e-02, -4.34361355e-03,  0.00000000e+00,
                              1.77335502e-03,  2.06083597e-03,  2.05829427e-03,  1.97278427e-03,
                              1.86494820e-03,  1.75550047e-03],
                            [ 0.00000000e+00, -1.20628100e-02, -4.51654256e-03, -1.77335502e-03,
                              6.50521303e-19,  9.04281023e-04,  1.12872471e-03,  1.18251798e-03,
                              1.17320289e-03,  1.13853070e-03],
                            [ 0.00000000e+00, -1.02899905e-02, -4.21106863e-03, -2.06083597e-03,
                             -9.04281023e-04, -1.73472348e-18,  5.26328183e-04,  6.90690277e-04,
                              7.49585864e-04,  7.63625107e-04],
                            [ 0.00000000e+00, -8.95428961e-03, -3.85015610e-03, -2.05829427e-03,
                             -1.12872471e-03, -5.26328183e-04, -2.98155597e-19,  3.34578851e-04,
                              4.55678897e-04,  5.08152734e-04],
                            [ 0.00000000e+00, -7.92072037e-03, -3.51621834e-03, -1.97278427e-03,
                             -1.18251798e-03, -6.90690277e-04, -3.34578851e-04,  1.40946282e-18,
                              2.26540605e-04,  3.17529039e-04],
                            [ 0.00000000e+00, -7.09956696e-03, -3.22353103e-03, -1.86494820e-03,
                             -1.17320289e-03, -7.49585864e-04, -4.55678897e-04, -2.26540605e-04,
                              3.93023288e-19,  1.60842952e-04],
                            [ 0.00000000e+00, -6.43208476e-03, -2.97020268e-03, -1.75550047e-03,
                             -1.13853070e-03, -7.63625107e-04, -5.08152734e-04, -3.17529039e-04,
                             -1.60842952e-04, -1.62630326e-19]];
}

