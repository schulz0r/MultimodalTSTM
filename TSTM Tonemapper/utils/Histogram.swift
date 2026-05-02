//
//  Histogram.swift
//  TSTM Tonemapper
//
//  Created by Philipp Waxweiler on 05.04.26.
//

import Foundation

struct Histogram
{
    let measures:[Float]
    var labels:[Float]
    
    init(measures: [Float], minVal: Float, maxVal: Float) {
        self.measures = measures
        
        let start = minVal
        let step = (maxVal - minVal) / Float(measures.count - 1)
        
        self.labels = (0..<measures.count).map { start + Float($0) * step }
    }
    
    func getMin() -> Float
    {
        return labels.first!
    }
    
    func getRange() -> Float
    {
        return labels.last! - labels.first!
    }
}
