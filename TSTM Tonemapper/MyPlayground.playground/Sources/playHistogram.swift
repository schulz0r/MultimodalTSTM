//
//  Histogram.swift
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 05.04.26.
//

import Foundation
import Accelerate

enum HistogramError: Error {
    case invalidArgument(String)
}

public struct Histogram
{
    public let measures:[Float]
    public var labels:[Float]
    
    public init(measures: [Float], minVal: Float, maxVal: Float) {
        self.measures = measures
        
        let start = minVal
        let step = (maxVal - minVal) / Float(measures.count - 1)
        
        self.labels = (0..<measures.count).map { start + Float($0) * step }
    }
    
    // A histogram uses binning, so the GMM fit algorithm calculates over which bin the gaussian lies.
    // We need to scale it back to the real data
    public func getValue(dataPoint: Float) -> Float
    {
        var result:Float = 0.0
        let pointWithoutDigits = Int(floor(dataPoint))
        let interpolation = vDSP.linearInterpolate(values: labels[pointWithoutDigits...(pointWithoutDigits + 1)],
                                            atIndices: [dataPoint])
        result = interpolation[0]
        
        return result
    }
    
    // get the average of the data
    public func getLinAverageFromLogData() -> Float
    {
        return zip(measures, labels).map({Float($0) * pow(2.0, $1)}).reduce(0, +) / Float(measures.reduce(0, +))
    }
    
    public func getMin() -> Float
    {
        return labels.first!
    }
    
    public func getRange() -> Float
    {
        return labels.last! - labels.first!
    }
}
