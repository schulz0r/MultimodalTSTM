//
//  Plotter.swift
//  
//
//  Created by Philipp Waxweiler on 12.04.26.
//
import SwiftUI
import Charts

// Combine into a simple model for Chart
public struct Sample: Identifiable {
    public let id = UUID()
    public let x: Float // label
    public let y: Float // histogram value
}

public func segmentationBorders(boundaries: [[Float]]) -> some ChartContent {
    ForEach(boundaries.indices, id: \.self) { idx in
        let bounds = boundaries[idx]
        RuleMark(xStart: .value("Boundary", bounds.first!),
                 xEnd: .value("Boundary", bounds.last!),
                 y: .value("placement", 0.0)
        )
            .lineStyle(StrokeStyle(lineWidth: 2))
            .foregroundStyle(by: .value("Component", "Gauss\(idx+1)"))
    }
}

public func drawSegmentMeans(means: [Float]) -> some ChartContent
{
    ForEach(means.indices, id: \.self) { idx in
        RuleMark(x: .value("Boundary", means[idx]))
        .lineStyle(StrokeStyle(lineWidth: 2))
        .foregroundStyle(by: .value("Component", "µ\(idx+1)"))
    }
}
