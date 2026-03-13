//
//  AudioDrivenVideoView.swift
//  PlaneListener
//
//  Created by student on 09/03/2026.
//

import SwiftUI

struct AudioDrivenVideoView: View {
    @State var model: AudioDrivenVideoModel

    let url: URL

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black)

                if let frame = model.currentFrame {
                    GeometryReader { geo in
                        Image(decorative: frame, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                } else {
                    Text("No frame")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .aspectRatio(
                model.videoSize == .zero
                ? (16.0 / 9.0)
                : (model.videoSize.width / max(model.videoSize.height, 1)),
                contentMode: .fit
            )

            
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
