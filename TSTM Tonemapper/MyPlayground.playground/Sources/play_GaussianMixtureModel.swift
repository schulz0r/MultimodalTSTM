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

public struct Gaussian
{
    public var mean: Float = 0
    public var sigma: Float = 0
    public var weight: Float = 0
    
    public init(mean: Float, sigma: Float, weight: Float) {
        self.mean = mean
        self.sigma = sigma
        self.weight = weight
    }
    
    // school book definition of the posterior probability of the normal distribution
    public func probability(x: Float) -> Float
    {
        let invSigma = 1.0 / sigma.squareRoot();
        return invSqrt2pi * invSigma * exp( -0.5 * pow( (x - mean) * invSigma , 2.0) );
    }
}

// The EM algorithm for fitting a GMM into data with little modification to make it work with Histograms
public func fitGaussianMixtureModel(histogram: Histogram, numGaussians: UInt, numIterations: UInt) throws -> [Gaussian]
{
    precondition(numIterations >= 1, "numIterations must be at least 1.")
    precondition(numGaussians >= 1, "numGaussians must be at least 1.")
    
    // get equally spaced gaussians
    var gaussians = (1...Int(numGaussians)).map
    { i in
        Gaussian(
        mean: histogram.getMin() + ( Float(i) * (histogram.getRange() / Float(numGaussians + 1)) ),
        sigma: histogram.getRange() / (2.0 * Float(numGaussians)), // * 2.0 because mean + 2 * sigma is the true width
        weight: 1.0 / Float(numGaussians)
    ) }
    
    for _ in (0..<numIterations)
    {
        var nextGaussians = [Gaussian](repeating: Gaussian(mean: 0.0, sigma: 0.0, weight: 0.0), count: Int(gaussians.count))
        var N = [Float](repeating: 0, count: Int(gaussians.count))
        
        for (amount, x) in zip(histogram.measures, histogram.labels)
        {
            if(amount > 0.0)
            {
                // E-Step
                let r_nk_j = gaussians.map({$0.weight * $0.probability(x: Float(x))})
                let r_nk_j_sum = r_nk_j.reduce(1e-6, +)
                let r_nk = r_nk_j.map({$0 / r_nk_j_sum})
                
                // M-Step
                for k in (0..<nextGaussians.count)
                {
                    N[k] += r_nk[k] * amount
                    nextGaussians[k].mean += r_nk[k] * Float(x) * amount
                    nextGaussians[k].sigma += ((r_nk[k] * pow(Float(x) - gaussians[k].mean , 2.0)) + 0.1) * amount
                }
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
        nextGaussians.removeAll{($0.sigma < 1e-3) || ($0.weight < 1e-2)}
        
        if(nextGaussians.isEmpty)
        {
            throw GmmFitError.noGaussiansLeft("All Gaussians where canceled during fit.")
        }
        
        nextGaussians.sort(by: { gausA, gausB in
            gausA.mean < gausB.mean
        })
        
        gaussians = nextGaussians
    }
    
    return gaussians
}

public func logLikelihood(model: [Gaussian], histogram: Histogram) -> Float
{
    let logLikelihood = zip(histogram.measures, histogram.labels).map({ n, x in
        n * log( model.map({$0.weight * $0.probability(x: x)}).reduce(0, +) )
    }).reduce(0, +)
    
    print("Log likelihood for \(model.count): \(logLikelihood)")
    
    return logLikelihood
}
