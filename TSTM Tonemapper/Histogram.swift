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

struct Histogram
{
    let measures:[UInt]
    var labels:[Float]
    
    init(measures: [UInt], minVal: Float, maxVal: Float) {
        self.measures = measures
        
        var start = minVal
        var end = maxVal
        let stride = Float(measures.count) / (maxVal - minVal)
        
        self.labels = [Float](unsafeUninitializedCapacity: measures.count) {
                buffer, initializedCount in
                
                vDSP_vgen(&start,
                          &end,
                          buffer.baseAddress!,
                          vDSP_Stride(stride),
                          vDSP_Length(measures.count))
                
                initializedCount = measures.count
            }
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
    public func getAverage() -> Float
    {
        return zip(measures, labels).map({Float(Float($0) * $1)}).reduce(0, +) / Float(measures.reduce(0, +))
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
