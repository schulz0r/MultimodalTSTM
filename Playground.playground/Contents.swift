import SwiftUI
import PlaygroundSupport
import Charts
@testable import Histogram

let histogramValues: [Float] = [0.00028944016, 0.0006709099, 0.00248909, 0.0073242188, 0.022445679, 0.0736084, 0.125, 0.15478516, 0.13122559, 0.10736084, 0.20324707, 0.06933594, 0.013648987, 0.0069999695, 0.07659912, 0.004837036]

let histogram = Histogram(measures: histogramValues, minVal: 0.0, maxVal: 1.0)

var gmm: [Gaussian]
do
{
    gmm = try fitGaussianMixtureModel(histogram: Histogram, numGaussians: 2, numIterations: 20)
}
catch
{
    
}

// Combine into a simple model for Chart
struct Sample: Identifiable {
    let id = UUID()
    let x: Double // label
    let y: Double // histogram value
}

let samples: [Sample] = zip(labels, histogramValues).map { Sample(x: $0.0, y: $0.1) }

struct ContentView: View {
    var body: some View {
        Chart {
            ForEach(samples, id: \.x)
            { item in
                LineMark(
                    x: .value("Value", item.x),
                    y: .value("Label", item.y),
                    series: .value("Company", "A")
                )
                .foregroundStyle(.blue)
            }
        }.frame(width: CGFloat(histogramValues.count) * 20.0, height: 500)
    }
}

PlaygroundPage.current.setLiveView(ContentView())
