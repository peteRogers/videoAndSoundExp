//
//  AudioDrivenView.swift
//  PlaneListener
//
//  Created by student on 09/03/2026.
//

import SwiftUI

struct AudioDrivenView: View {
    @State var model: AudioDrivenModel

    let url: URL

    var body: some View {
        VStack(spacing: 16) {
            Text(model.statusText)
                .font(.headline)

            HStack(spacing: 12) {
                Button("Play") {
                    model.play()
                }

                Button("Pause") {
                    model.pause()
                }

                Button("Stop") {
                    model.stop()
                }
            }
        }
        .padding()
        .task {
            await model.load(url: url)
            model.play()
        }
        .onDisappear {
            model.stop()
        }
    }
}
