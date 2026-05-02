//
//  segmentation.swift
//  
//
//  Created by Philipp Waxweiler on 12.04.26.
//

import Foundation

struct SegmentationBorders
{
    let lower:[Float]
    let upper:[Float]
}

// Solve for t where w1*N(t | μ1, σ1) == w2*N(t | μ2, σ2)
// Here σ is variance (not stddev). If your model stores stddev, square it before passing in.
func crossoverTBetween(_ g1: Gaussian, _ g2: Gaussian) -> Float? {
    let mu1 = g1.mean
    let mu2 = g2.mean
    let s1 = g1.variance   // variance
    let s2 = g2.variance   // variance
    let w1 = max(g1.weight, 1e-12)
    let w2 = max(g2.weight, 1e-12)

    // If variances are equal, the crossover is at the midpoint shifted by log-weight ratio.
    if abs(s1 - s2) < 1e-9 {
        let sigma = s1
        // Derived from linearizing the equality with same variance:
        // t = (μ1 + μ2)/2 + (σ / (μ2 - μ1)) * ln(w1/w2)
        // Guard μ1 != μ2; if equal and weights equal, any t; pick midpoint.
        if abs(mu1 - mu2) < 1e-9 {
            return (mu1 + mu2) * 0.5
        } else {
            let shift = (sigma / (mu2 - mu1)) * log(w1 / w2)
            return (mu1 + mu2) * 0.5 + shift
        }
    }

    // General case: solve quadratic a t^2 + b t + c = 0
    // Derived from setting log-likelihoods equal.
    let a = 0.5 * (1.0 / s1 - 1.0 / s2)
    let b = (-mu1 / s1 + mu2 / s2)
    let c = 0.5 * (mu1 * mu1 / s1 - mu2 * mu2 / s2) - log(w1 / w2)

    let discriminant = b * b - 4 * a * c
    if discriminant < 0 {
        return nil // no real intersection; fall back to a midpoint in log space
    }
    let sqrtD = sqrt(discriminant)
    // There are two solutions; for unimodal neighbors, choose the one between means if possible.
    let t1 = (-b + sqrtD) / (2 * a)
    let t2 = (-b - sqrtD) / (2 * a)

    // Prefer the solution between μ1 and μ2, else pick the one closer to that interval.
    let lo = min(mu1, mu2)
    let hi = max(mu1, mu2)
    let candidates = [t1, t2]
    if let between = candidates.first(where: { $0 >= lo && $0 <= hi }) {
        return between
    }
    // If neither lies in between (can happen with skewed weights/variances), pick the one nearer the interval.
    let d1 = max(lo - t1, t1 - hi, 0)
    let d2 = max(lo - t2, t2 - hi, 0)
    return d1 < d2 ? t1 : t2
}

// Build touching segments in linear space [0, 1]
func calcBayesianSegmentBorders(from gmm: [Gaussian], minLuminance: Float, maxLuminance: Float) -> SegmentationBorders {
    guard !gmm.isEmpty else { return SegmentationBorders(lower: [], upper: []) }
    
    if gmm.count == 1
    {
        return SegmentationBorders(lower: [minLuminance], upper: [maxLuminance])
    }

    // Compute crossover boundaries in log2 domain
    var tBoundaries: [Float] = []
    for j in 0..<(gmm.count - 1)
    {
        if let t = crossoverTBetween(gmm[j], gmm[j + 1])
        {
            tBoundaries.append(t)
        }
        else
        {
            // Fallback: simple midpoint in log space
            tBoundaries.append(0.5 * (gmm[j].mean + gmm[j + 1].mean))
        }
    }
    
    // sort boundaries ascending to avoid reversed bounds
    tBoundaries.sort()

    // Convert from log2 to linear domain
    let xBoundaries = tBoundaries.map { pow(2.0, $0) }

    // Assemble segments [0, x1], [x1, x2], ..., [x_{k-1}, 1]
    return SegmentationBorders(lower: [minLuminance] + xBoundaries,
                               upper: xBoundaries + [maxLuminance])
}

func cullMicroscopicSegments(gmm: inout [Gaussian], segBorders: inout SegmentationBorders, minLuminance: Float, maxLuminance: Float)
{
    // get range lengths
    let ranges = zip(segBorders.lower, segBorders.upper).map({luMin, luMax in (luMax - luMin)})
    // get array indicating if a cull is due (segment is less than 5% of value range)
    let indicesToKick = ranges.enumerated().compactMap({ (idx, segRange) in
        (segRange < ((maxLuminance - minLuminance) * 0.05))
    })
    
    // go through array in reverse order and cull gmm
    for (idx, isKick) in indicesToKick.enumerated().reversed()
    {
        if(isKick)
        {
            gmm.remove(at: idx)
        }
    }
    
    // if cull happened, recalculate borders
    if( indicesToKick.contains(where: {$0 == true}) )
    {
        segBorders = calcBayesianSegmentBorders(from: gmm, minLuminance: minLuminance, maxLuminance: maxLuminance)
    }
}
