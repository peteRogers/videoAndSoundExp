////
////  backup.swift
////  videoAndSoundExp
////
////  Created by Peter Rogers on 13/02/2026.
////
//
//import SwiftUI
//import AVFoundation
//import AVKit
//import AudioKit
//import SoundpipeAudioKit
//import Combine
//import MetalKit
//import UIKit
//
//// MARK: - SwiftUI View
//
//struct VideoAudioKitView: View {
//    @StateObject private var model = VideoAudioKitModel()
//
//    var body: some View {
//        VStack(spacing: 16) {
//
//            // VIDEO
//            Group {
//                if let player = model.videoPlayer {
//                    MetalVideoPlayerView(
//                        player: player,
//                        strength: 0.65
//                    )
//                    .frame(height: 260)
//                    .clipShape(RoundedRectangle(cornerRadius: 16))
//                } else {
//                    RoundedRectangle(cornerRadius: 16)
//                        .fill(.secondary.opacity(0.2))
//                        .frame(height: 260)
//                        .overlay(Text("Loading video…"))
//                }
//            }
//
//            // CONTROLS
//            HStack {
//                Button(model.isPlaying ? "Pause" : "Play") {
//                    model.togglePlay()
//                }
//                .buttonStyle(.borderedProminent)
//
//                Button("Restart") {
//                    model.restart()
//                }
//                .buttonStyle(.bordered)
//            }
//
//            // AUDIOKIT CONTROLS
//            VStack(alignment: .leading, spacing: 12) {
//                Text("AudioKit (processing extracted audio)")
//                    .font(.headline)
//
//                HStack {
//                    Text("Pitch (semitones)")
//                    Slider(value: $model.pitchSemitones, in: -12...12, step: 0.01)
//                    Text("\(model.pitchSemitones, specifier: "%.2f")")
//                        .monospacedDigit()
//                        .frame(width: 70, alignment: .trailing)
//                }
//
//                HStack {
//                    Text("Lowpass (Hz)")
//                    Slider(value: $model.lowpassHz, in: 200...20000, step: 1)
//                    Text("\(Int(model.lowpassHz))")
//                        .monospacedDigit()
//                        .frame(width: 70, alignment: .trailing)
//                }
//
//                HStack {
//                    Text("Reverb")
//                    Slider(value: $model.reverbMix, in: 0...1, step: 0.001)
//                    Text("\(model.reverbMix, specifier: "%.2f")")
//                        .monospacedDigit()
//                        .frame(width: 70, alignment: .trailing)
//                }
//            }
//            .padding()
//            .background(.thinMaterial)
//            .clipShape(RoundedRectangle(cornerRadius: 16))
//
//            Spacer()
//        }
//        .padding()
//        .task {
//            // Put your video in the app bundle as: video.mp4
//            await model.loadVideoFromBundle(named: "Birds on a wire", ext: "mp4")
//        }
//        .onChange(of: model.pitchSemitones) { _, newValue in
//            model.setPitch(newValue)
//        }
//        .onChange(of: model.lowpassHz) { _, newValue in
//            model.setLowpass(newValue)
//        }
//        .onChange(of: model.reverbMix) { _, newValue in
//            model.setReverbMix(newValue)
//        }
//        .alert("Error", isPresented: $model.showError) {
//            Button("OK", role: .cancel) {}
//        } message: {
//            Text(model.errorMessage)
//        }
//    }
//}
//
//// MARK: - Model (AVPlayer video + extracted audio -> AudioKit)
//
//@MainActor
//final class VideoAudioKitModel: ObservableObject {
//    // Video
//    @Published var videoPlayer: AVPlayer?
//
//    // Playback
//    @Published var isPlaying: Bool = false
//
//    // AudioKit params
//    @Published var pitchSemitones: Double = 0
//    @Published var lowpassHz: Double = 20000
//    @Published var reverbMix: Double = 0.1
//
//    // Error UI
//    @Published var showError: Bool = false
//    var errorMessage: String = ""
//
//    // Internal
//    private var videoURL: URL?
//    private var extractedAudioURL: URL?
//
//    // AudioKit graph
//    private let engine = AudioEngine()
//    private let player = AudioPlayer()
//
//    // Effects chain you can expand later
//    private var timePitch: TimePitch?
//    private var lowpass: LowPassFilter?
//    private var reverb: ZitaReverb?
//    // MARK: Public API
//
//    func loadVideoFromBundle(named name: String, ext: String) async {
//        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
//            fail("Couldn’t find \(name).\(ext) in app bundle.")
//            return
//        }
//
//        self.videoURL = url
//        self.videoPlayer = AVPlayer(url: url)
//
//        do {
//            // 1) Extract audio track to a standalone .m4a in tmp (cached)
//            let audioURL = try await extractAudioToM4A(videoURL: url)
//            self.extractedAudioURL = audioURL
//
//            // 2) Build AudioKit graph and load extracted audio
//            try buildAudioGraphIfNeeded()
//            try loadAudioFile(url: audioURL)
//
//        } catch {
//            fail(error.localizedDescription)
//        }
//    }
//
//    func togglePlay() {
//        guard videoPlayer != nil else { return }
//
//        if isPlaying {
//            pause()
//        } else {
//            play()
//        }
//    }
//
//    func restart() {
//        guard let vp = videoPlayer else { return }
//        vp.seek(to: .zero)
//        player.stop()
//        player.play(from: 0)
//        if isPlaying {
//            vp.play()
//        }
//    }
//
//    func setPitch(_ semitones: Double) {
//        // TimePitch uses cents for pitchShift:
//        // 100 cents = 1 semitone
//        timePitch?.pitch = Float(semitones * 100.0)
//    }
//
//    func setLowpass(_ hz: Double) {
//        lowpass?.cutoffFrequency = Float(hz)
//    }
//
//    func setReverbMix(_ mix: Double) {
//        reverb?.dryWetMix = Float(mix)
//    }
//
//    // MARK: Playback
//
//    private func play() {
//        guard let vp = videoPlayer else { return }
//        do {
//            if !engine.avEngine.isRunning {
//                try engine.start()
//            }
//            // Start both as close together as we can.
//            // (If you need tighter sync, we can drive audio time from the video player time.)
//            player.play()
//            vp.play()
//            isPlaying = true
//        } catch {
//            fail("Audio engine failed to start: \(error.localizedDescription)")
//        }
//    }
//
//    private func pause() {
//        videoPlayer?.pause()
//        player.pause()
//        isPlaying = false
//    }
//
//    // MARK: AudioKit setup
//
//    private func buildAudioGraphIfNeeded() throws {
//        guard engine.output == nil else { return } // already built
//
//        let tp = TimePitch(player)
//        let lp = LowPassFilter(tp)
//        let rv = ZitaReverb(lp)
//
//        self.timePitch = tp
//        self.lowpass = lp
//        self.reverb = rv
//
//        engine.output = rv
//        try engine.start()
//        
//        setPitch(pitchSemitones)
//        setLowpass(lowpassHz)
//        setReverbMix(reverbMix)
//    }
//
//    private func loadAudioFile(url: URL) throws {
//        let file = try AVAudioFile(forReading: url)
//        try player.load(file: file)
//        player.isLooping = false
//    }
//
//    // MARK: Audio extraction
//
//    /// Extracts the *audio track* from a video file and exports it as .m4a into tmp, cached by name.
//    private func extractAudioToM4A(videoURL: URL) async throws -> URL {
//        let asset = AVAsset(url: videoURL)
//
//        guard asset.tracks(withMediaType: .audio).isEmpty == false else {
//            throw NSError(domain: "VideoAudioKitModel", code: 1, userInfo: [
//                NSLocalizedDescriptionKey: "Video has no audio track."
//            ])
//        }
//
//        let tmp = FileManager.default.temporaryDirectory
//        let base = videoURL.deletingPathExtension().lastPathComponent
//        let outURL = tmp.appendingPathComponent("\(base)_extracted.m4a")
//
//        // Cache: if it already exists, reuse it
//        if FileManager.default.fileExists(atPath: outURL.path) {
//            return outURL
//        }
//
//        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
//            throw NSError(domain: "VideoAudioKitModel", code: 2, userInfo: [
//                NSLocalizedDescriptionKey: "Couldn’t create AVAssetExportSession."
//            ])
//        }
//
//        exporter.outputURL = outURL
//        exporter.outputFileType = .m4a
//        exporter.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
//
//        // Remove if partially exists
//        try? FileManager.default.removeItem(at: outURL)
//
//        await exporter.export()
//
//        if exporter.status == .completed {
//            return outURL
//        } else {
//            let msg = exporter.error?.localizedDescription ?? "Unknown export error."
//            throw NSError(domain: "VideoAudioKitModel", code: 3, userInfo: [
//                NSLocalizedDescriptionKey: "Audio export failed: \(msg)"
//            ])
//        }
//    }
//
//    // MARK: Helpers
//
//    private func fail(_ message: String) {
//        errorMessage = message
//        showError = true
//    }
//}
//
//// MARK: - Metal video view (Option 1: AVPlayerItemVideoOutput -> MTKView)
//
//struct MetalVideoPlayerView: UIViewRepresentable {
//    let player: AVPlayer
//    var strength: Float = 0.5
//
//    func makeUIView(context: Context) -> MTKView {
//        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
//        view.isPaused = true
//        view.enableSetNeedsDisplay = false
//        view.framebufferOnly = false
//        view.drawableSize = CGSize(width: 1920, height: 1080)
//
//        context.coordinator.attach(to: view)
//        context.coordinator.setPlayer(player)
//        context.coordinator.setStrength(strength)
//
//        return view
//    }
//
//    func updateUIView(_ uiView: MTKView, context: Context) {
//        context.coordinator.setPlayer(player)
//        context.coordinator.setStrength(strength)
//        // drawable size tracks view size
//        uiView.drawableSize = uiView.bounds.size
//    }
//
//    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
//        coordinator.stop()
//    }
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator()
//    }
//
//    final class Coordinator: NSObject {
//        private weak var mtkView: MTKView?
//        private var ciContext: CIContext?
//        private var displayLink: CADisplayLink?
//
//        private var player: AVPlayer?
//        private var videoOutput: AVPlayerItemVideoOutput?
//
//        private var time: Float = 0
//        private var strength: Float = 0.5
//
//        // Core Image warp “shader” (runs on GPU). This gives you a shader-like pipeline without needing a .metal file.
//        private let warpKernel: CIWarpKernel = {
//            let source = """
//            kernel vec2 warp(float t, float s) {
//                vec2 dc = destCoord();
//                // Wavy offsets in pixels. Keep small and scale by `s`.
//                float wx = sin(dc.y * 0.02 + t * 2.0);
//                float wy = cos(dc.x * 0.02 + t * 1.7);
//                return dc + vec2(wx, wy) * (6.0 * s);
//            }
//            """
//            return CIWarpKernel(source: source)!
//        }()
//
//        func attach(to view: MTKView) {
//            self.mtkView = view
//            if let device = view.device {
//                self.ciContext = CIContext(mtlDevice: device)
//            }
//            startDisplayLink()
//        }
//
//        func setStrength(_ v: Float) {
//            self.strength = max(0, min(1, v))
//        }
//
//        func setPlayer(_ p: AVPlayer) {
//            if self.player === p { return }
//            self.player = p
//            attachVideoOutputIfNeeded()
//        }
//
//        private func attachVideoOutputIfNeeded() {
//            guard let player = player else { return }
//            guard let item = player.currentItem else { return }
//
//            // If we already have an output attached to this item, keep it.
//            if let existing = videoOutput, item.outputs.contains(existing) {
//                return
//            }
//
//            // Create a new output requesting BGRA buffers (easy for CI / Metal).
//            let attrs: [String: Any] = [
//                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
//            ]
//            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
//            output.suppressesPlayerRendering = true // we render ourselves
//
//            // Remove any previous output from prior item.
//            if let old = videoOutput {
//                player.currentItem?.remove(old)
//            }
//
//            item.add(output)
//            self.videoOutput = output
//        }
//
//        private func startDisplayLink() {
//            stop()
//            let link = CADisplayLink(target: self, selector: #selector(tick))
//            link.add(to: .main, forMode: .common)
//            self.displayLink = link
//        }
//
//        func stop() {
//            displayLink?.invalidate()
//            displayLink = nil
//        }
//
//        @objc private func tick() {
//            time += 1.0 / 60.0
//            mtkView?.draw()
//            drawFrame()
//        }
//
//        private func drawFrame() {
//            guard let view = mtkView,
//                  let drawable = view.currentDrawable,
//                  let ciContext = ciContext,
//                  let output = videoOutput,
//                  let player = player
//            else { return }
//
//            attachVideoOutputIfNeeded()
//
//            // Ask for the pixel buffer corresponding to the player’s current time.
//            let hostTime = CACurrentMediaTime()
//            let itemTime = output.itemTime(forHostTime: hostTime)
//            guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return }
//
//            var displayTime = CMTime.zero
//            guard let pb = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) else { return }
//
//            // Build CIImage
//            var image = CIImage(cvPixelBuffer: pb)
//
//            // Fit/center-crop to the MTKView drawable.
//            let targetSize = view.drawableSize
//            let targetRect = CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
//
//            // Apply warp kernel (shader-like effect)
//            if let warped = warpKernel.apply(extent: image.extent, roiCallback: { _, rect in rect }, image: image, arguments: [time, strength]) {
//                image = warped
//            }
//
//            // Render to drawable texture
//            ciContext.render(
//                image,
//                to: drawable.texture,
//                commandBuffer: nil,
//                bounds: targetRect,
//                colorSpace: CGColorSpaceCreateDeviceRGB()
//            )
//
//            drawable.present()
//
//            // Keep AudioKit extraction / playback separate; video remains driven by AVPlayer.
//            _ = player // silence unused warning if you remove other references later
//        }
//    }
//}
//
//// MARK: - Preview
//
//#Preview {
//    VideoAudioKitView()
//}
//
//
//
