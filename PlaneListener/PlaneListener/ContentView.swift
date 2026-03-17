//
//  ContentView.swift
//  PlaneListener
//
//  Created by student on 05/03/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var sharedState = SharedFlightAudioState()
    @State private var planeModel: PlaneModel
    @State private var videoModel: AudioDrivenModel

    init() {
        let sharedState = SharedFlightAudioState()
        _sharedState = State(initialValue: sharedState)
        _planeModel = State(initialValue: PlaneModel(sharedState: sharedState))
        _videoModel = State(initialValue: AudioDrivenModel(sharedState: sharedState))
    }

    var body: some View {
        VStack {
            if let url = Bundle.main.url(forResource: "tropBird", withExtension: "wav") {
                AudioDrivenView(model: videoModel, url: url)
            } else {
                Text("Movie file not found")
            }

            PlaneView(model: planeModel)
            VStack(spacing: 8) {
                Gauge(value: Double(videoModel.flangeDepth), in: 0.0...1.0) {
                    Text("Flange depth")
                } currentValueLabel: {
                    Text("\(videoModel.flangeDepth, specifier: "%.05f")x")
                }.padding(20)
            }
        }
    }
}

#Preview {
    ContentView()
}
