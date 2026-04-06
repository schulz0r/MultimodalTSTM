//
//  GaussianMixtureModel.swift
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 31.03.26.
//

import Foundation

enum GmmFitError: Error {
    case noGaussiansLeft(String)
}


let invSqrt2pi = 1.0 / (2 * Float.pi).squareRoot();

struct Gaussian
{
    var mean: Float = 0
    var sigma: Float = 0
    var weight: Float = 0
    
    public init(mean: Float, sigma: Float, weight: Float) {
        self.mean = mean
        self.sigma = sigma
        self.weight = weight
    }
    
    public func probability(x: Float) -> Float
    {
        let invSigma = (1.0 / sigma).squareRoot();
        return invSqrt2pi * invSigma * exp( -0.5 * pow( (x - mean) * invSigma , 2.0) );
    }
}

func fitGaussianMixtureModel(histogram: [UInt], numGaussians: UInt, numIterations: UInt) -> [Gaussian]
{
    precondition(numIterations >= 1, "numIterations must be at least 1.")
    precondition(numGaussians >= 1, "numGaussians must be at least 1.")
    
    // get equally spaced gaussians
    var gaussians = (0..<Int(numGaussians)).map { i in Gaussian(
        mean: (Float(i) + 0.5) * (Float(histogram.count) / Float(numGaussians)),
        sigma: Float(histogram.count) / Float(numGaussians),
        weight: 1.0 / Float(numGaussians)
    ) }
    
    for _ in (0..<numIterations)
    {
        var nextGaussians = [Gaussian](repeating: Gaussian(mean: 0.0, sigma: 0.0, weight: 0.0), count: Int(gaussians.count))
        var N = [Float](repeating: 0, count: Int(gaussians.count))
        
        for (x, bin) in histogram.enumerated()
        {
            let amountOfPixels = Float(bin)
            
            // E-Step
            let r_nk_j = gaussians.map({$0.weight * $0.probability(x: Float(x))})
            let r_nk_j_sum = r_nk_j.reduce(1e-6, +)
            let r_nk = r_nk_j.map({$0 / r_nk_j_sum})
            
            // M-Step
            for k in (0..<nextGaussians.count)
            {
                N[k] += r_nk[k] * amountOfPixels
                nextGaussians[k].mean += r_nk[k] * Float(x) * amountOfPixels
                nextGaussians[k].sigma += r_nk[k] * pow(Float(x) - gaussians[k].mean , 2.0) * amountOfPixels
            }
        }
        
        let N_sum = N.reduce(0, +)
        
        for k in (0..<gaussians.count)
        {
            nextGaussians[k].weight = N[k] / N_sum
            nextGaussians[k].mean /= N[k]
            nextGaussians[k].sigma /= N[k]
        }
        
        // kick defective gaussians
        nextGaussians.removeAll{($0.sigma < 1e-6) || ($0.weight < 1e-3)}
        
        if(nextGaussians.isEmpty)
        {
            throw GmmFitError.noGaussiansLeft("All Gaussians where canceled during fit.")
        }
        
        gaussians = nextGaussians
    }
    
    return gaussians
}

func logLikelihood()
{
    
}
