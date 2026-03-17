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
    @State private var audioModel: AudioDrivenModel_Generative

    init() {
        let sharedState = SharedFlightAudioState()
        _sharedState = State(initialValue: sharedState)
        _planeModel = State(initialValue: PlaneModel(sharedState: sharedState))
        _audioModel = State(initialValue: AudioDrivenModel_Generative(sharedState: sharedState))
    }

    var body: some View {
        VStack {
           // if let url = Bundle.main.url(forResource: "tropBird", withExtension: "wav") {
                AudioDrivenView(model: audioModel)
           

            PlaneView(model: planeModel)
            VStack(spacing: 8) {
//                Gauge(value: Double(videoModel.flangeDepth), in: 0.0...1.0) {
//                    Text("Flange depth")
//                } currentValueLabel: {
//                    Text("\(videoModel.flangeDepth, specifier: "%.05f")x")
//                }.padding(20)
            }
        }.onChange(of: sharedState.distanceMeters) { oldValue, newValue in
            print("count changed from \(oldValue) to \(newValue)")
            audioModel.play()
        }
    }
}

#Preview {
    ContentView()
}
