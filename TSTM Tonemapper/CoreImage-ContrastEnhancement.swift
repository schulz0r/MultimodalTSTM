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
    
    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, .outputColorSpace: NSNull()])
    
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
        let dt = stepSize
        let alpha = self.alpha
        let beta = self.beta
        
        var contrastEnhanced:CIImage? = nil
        
        let K = 9
        
        let w:[Float] = [0.0, 6.28318531, 12.56637061, 18.84955592, 25.13274123, 31.41592654, 37.69911184, 43.98229715, 50.26548246, 56.54866776]
        let alpha_nm = getAlphaCoeffs()
        let beta_nm = getBetaCoeffs()
        let gamma_nm = getGammaCoeffs()
        let delta_nm = getDeltaCoeffs()
        
        let gaussKernelSize:Float = 50.0
        
        for _ in (0..<1)
        {
            var R_ACE = CIImage(color: CIColor(red: 0.0, green: 0.0, blue: 0.0)).cropped(to: input.extent)
            
            for m in (0...K)
            {
                let sineImg = Self.sineImageKernel.apply(extent: input.extent,
                                                         roiCallback: { _, rect in rect },
                                                         arguments: [contrastEnhanced ?? input,
                                                                     w[m]
                                                                     ])
                
                let cosineImg = Self.cosineImageKernel.apply(extent: input.extent,
                                                           roiCallback: { _, rect in rect },
                                                           arguments: [contrastEnhanced ?? input,
                                                                       w[m]
                                                                      ])
                // Gauss
                let blurSineFilter = CIFilter.gaussianBlur()
                blurSineFilter.inputImage = sineImg
                blurSineFilter.radius = gaussKernelSize
                
                let blurCosineFilter = CIFilter.gaussianBlur()
                blurCosineFilter.inputImage = cosineImg
                blurCosineFilter.radius = gaussKernelSize
                
                // add to ACE
                R_ACE = Self.contrastTermKernel.apply(extent: input.extent,
                                                      roiCallback: { _, rect in rect },
                                                      arguments: [contrastEnhanced ?? input,
                                                                  blurSineFilter.outputImage!,
                                                                  blurCosineFilter.outputImage!,
                                                                  R_ACE,
                                                                  Data(bytes: w, count: MemoryLayout<Float>.stride * w.count) as NSData,
                                                                  Data(bytes: alpha_nm[m], count: MemoryLayout<Float>.stride * alpha_nm[m].count) as NSData,
                                                                  Data(bytes: beta_nm[m], count: MemoryLayout<Float>.stride * beta_nm[m].count) as NSData,
                                                                  Data(bytes: gamma_nm[m], count: MemoryLayout<Float>.stride * gamma_nm[m].count) as NSData,
                                                                  Data(bytes: delta_nm[m], count: MemoryLayout<Float>.stride * delta_nm[m].count) as NSData,
                                                                  K
                                                                 ])!
            } // contrast term approximation
            
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
    } // override var outputImage: CIImage?
    
    private func getAlphaCoeffs() -> [[Float]]
    {
        return [[ 8.31001387e-12,  1.09312653e-01,  4.36618531e-02,  2.50120750e-02,
                  1.67318263e-02,  1.22103543e-02,  9.42262506e-03,  7.56006940e-03,
                  6.24238351e-03,  5.26933534e-03],
                [-1.09312607e-01,  9.20632732e-08,  1.04411472e-02,  7.51111864e-03,
                  5.54963689e-03,  4.29220743e-03,  3.44388436e-03,  2.84255130e-03,
                  2.39867323e-03,  2.06014355e-03],
                [-4.36618479e-02, -1.04410556e-02,  3.03326524e-10,  2.92103019e-03,
                  2.67889393e-03,  2.26726656e-03,  1.91443107e-03,  1.63390455e-03,
                  1.41209736e-03,  1.23475319e-03],
                [-2.50120354e-02, -7.51095779e-03, -2.92095927e-03,  7.42855916e-08,
                  1.23301382e-03,  1.30074264e-03,  1.19789906e-03,  1.07280884e-03,
                  9.55398902e-04,  8.54915812e-04],
                [-1.67317901e-02, -5.55897865e-03, -2.67882768e-03, -1.24983582e-03,
                  8.38318957e-08,  6.48930223e-04,  7.40396076e-04,  7.21868288e-04,
                  6.75447777e-04,  6.20977079e-04],
                [-1.22147679e-02, -4.29211137e-03, -2.27629639e-03, -1.30064677e-03,
                 -6.57539275e-04, -7.95930820e-12,  3.83408969e-04,  4.65598032e-04,
                  4.73007099e-04,  4.56653347e-04],
                [-9.42261870e-03, -3.45284891e-03, -1.91443025e-03, -1.20679625e-03,
                 -7.40312004e-04, -3.85422180e-04,  7.12577760e-08,  2.46702568e-04,
                  3.11224328e-04,  3.29006505e-04],
                [-7.56427499e-03, -2.84247861e-03, -1.64291523e-03, -1.07271296e-03,
                 -7.30710798e-04, -4.65439942e-04, -2.48687160e-04, -8.84102042e-07,
                  1.68553250e-04,  2.22122714e-04],
                [-6.24232287e-03, -2.40699675e-03, -1.41209360e-03, -9.64499138e-04,
                 -6.75349810e-04, -4.75427907e-04, -3.15197723e-04, -1.70553780e-04,
                 -4.26632986e-10,  1.20610865e-04],
                [-5.27363616e-03, -2.06003987e-03, -1.24281480e-03, -8.54825952e-04,
                 -6.30054488e-04, -4.58949128e-04, -3.31051788e-04, -2.22046857e-04,
                 -1.22586903e-04, -9.57881506e-07]];
    }
    
    private func getBetaCoeffs() -> [[Float]]
    {
        return [[ 0.0        ,  0.0        ,  0.0        ,  0.0        ,  0.0        ,
                  0.0        ,  0.0        ,  0.0        ,  0.0        ,  0.0],
                [ 0.36762247, -0.57990876,  0.0207895 ,  0.01118688,  0.00721038,
                  0.00513137,  0.00388771,  0.00307529,  0.00251057,  0.00209946],
                [ 0.16188011,  0.01877337, -0.30254723,  0.00876066,  0.00566335,
                  0.00403751,  0.00306287,  0.00242522,  0.00198146,  0.0016581 ],
                [ 0.10121711,  0.00916296,  0.00841293, -0.20488011,  0.00482955,
                  0.00344683,  0.00261641,  0.00207262,  0.00169333,  0.00141793],
                [ 0.07288339,  0.00536812,  0.00523536,  0.00471758, -0.15492457,
                  0.00306177,  0.0023255 ,  0.00184271,  0.00150639,  0.00126113],
                [ 0.05664439,  0.00347319,  0.00359965,  0.00329327,  0.00301364,
                 -0.12456868,  0.00211471,  0.00167723,  0.00137262,  0.00114824],
                [ 0.04617847,  0.00238913,  0.00263764,  0.00244767,  0.0022548 ,
                  0.00209129, -0.10416505,  0.00155032,  0.00126799,  0.00106179],
                [ 0.038897  ,  0.00171169,  0.00201924,  0.00190035,  0.00176003,
                  0.00163948,  0.00153746, -0.08950743,  0.00118421,  0.00099281],
                [ 0.03355178,  0.00126007,  0.00159692,  0.00152317,  0.00142043,
                  0.00132632,  0.00124575,  0.00117669, -0.0784674 ,  0.00093587],
                [ 0.02946761,  0.00094572,  0.00129265,  0.00125172,  0.00117429,
                  0.00109986,  0.00103347,  0.00097858,  0.0009313 , -0.0698527 ]];
    }
    
    private func getGammaCoeffs() -> [[Float]]
    {
        return [[ 0.0        , -0.36762247, -0.1618801 , -0.10121711, -0.07288339,
                  -0.05664444, -0.04617827, -0.03889706, -0.03355168, -0.02946761],
                 [ 0.0        ,  0.57990877, -0.01877337, -0.00916294, -0.00536811,
                  -0.00347315, -0.00238914, -0.00171136, -0.00126015, -0.00094543],
                 [ 0.0        , -0.02078949,  0.30254722, -0.00841293, -0.00523534,
                  -0.00359965, -0.00263741, -0.00201927, -0.00159661, -0.00129354],
                 [ 0.0        , -0.01118687, -0.00876066,  0.20488009, -0.00471758,
                  -0.00329329, -0.00244768, -0.00190023, -0.00152317, -0.00125102],
                 [ 0.0        , -0.00721038, -0.00566333, -0.00482955,  0.1549248 ,
                  -0.00301366, -0.00225481, -0.00176261, -0.00142008, -0.00117188],
                 [ 0.0        , -0.00513138, -0.00403751, -0.00344702, -0.00306178,
                   0.12456861, -0.00209109, -0.00163917, -0.00132633, -0.0010992 ],
                 [ 0.0        , -0.00388771, -0.00306285, -0.00261641, -0.0023255 ,
                  -0.0021169 ,  0.10416506, -0.00153531, -0.00124575, -0.00103561],
                 [ 0.0        , -0.00307527, -0.00242524, -0.00207232, -0.00184272,
                  -0.00167763, -0.00155062,  0.08950743, -0.00117668, -0.00097869],
                 [ 0.0        , -0.00251057, -0.00198144, -0.00169657, -0.00150636,
                  -0.00137005, -0.00126798, -0.00118637,  0.0784675 , -0.00092931],
                 [ 0.0        , -0.00209944, -0.0016581 , -0.00141752, -0.00126114,
                  -0.00114823, -0.00106193, -0.00099289, -0.00093586,  0.06985287]];
    }
    
    private func getDeltaCoeffs() -> [[Float]]
    {
        return [[ 0.00000000e+00,  0.00000000e+00,  0.00000000e+00,  0.00000000e+00,
                  0.00000000e+00,  0.00000000e+00,  0.00000000e+00,  0.00000000e+00,
                  0.00000000e+00,  0.00000000e+00],
                [ 0.00000000e+00,  9.33824970e-10,  1.69558515e-02,  1.44379577e-02,
                  1.20764725e-02,  1.03075164e-02,  8.97561704e-03,  7.94581438e-03,
                  7.12840120e-03,  6.46464806e-03],
                [ 0.00000000e+00, -1.69558681e-02, -1.64779950e-10,  4.34681446e-03,
                  4.52233756e-03,  4.21920772e-03,  3.86051364e-03,  3.52871824e-03,
                  3.23812455e-03,  2.98685764e-03],
                [ 0.00000000e+00, -1.44379625e-02, -4.34681370e-03,  3.67124331e-11,
                  1.77565107e-03,  2.06504805e-03,  2.06423260e-03,  1.98033251e-03,
                  1.87403794e-03,  1.76607981e-03],
                [ 0.00000000e+00, -1.20764598e-02, -4.52234110e-03, -1.77565150e-03,
                  3.95585668e-11,  9.06070998e-04,  1.13204548e-03,  1.18723686e-03,
                  1.17919736e-03,  1.14573598e-03],
                [ 0.00000000e+00, -1.03075182e-02, -4.21921199e-03, -2.06505085e-03,
                 -9.06075438e-04, -4.18799770e-10,  5.27804042e-04,  6.93439406e-04,
                  7.53494531e-04,  7.69870005e-04],
                [ 0.00000000e+00, -8.97563035e-03, -3.86051324e-03, -2.06423177e-03,
                 -1.13205265e-03, -5.27779867e-04,  3.82839017e-11,  3.35807785e-04,
                  4.58020184e-04,  5.11509526e-04],
                [ 0.00000000e+00, -7.94581131e-03, -3.52871706e-03, -1.98033227e-03,
                 -1.18721800e-03, -6.93435918e-04, -3.35836708e-04,  9.64686802e-07,
                  2.27617752e-04,  3.19567645e-04],
                [ 0.00000000e+00, -7.12840076e-03, -3.23812074e-03, -1.87403242e-03,
                 -1.17919507e-03, -7.53493596e-04, -4.58019233e-04, -2.27611191e-04,
                 -1.15697167e-10,  1.61786181e-04],
                [ 0.00000000e+00, -6.46464675e-03, -2.98685549e-03, -1.76608080e-03,
                 -1.14575203e-03, -7.67355510e-04, -5.11487208e-04, -3.19566343e-04,
                 -1.61801500e-04,  9.82415563e-07]];
    }
}

