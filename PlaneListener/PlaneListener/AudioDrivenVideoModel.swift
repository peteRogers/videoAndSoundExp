//
//  AudioDrivenVideoModel.swift
//

import Foundation
import Observation
@preconcurrency import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AudioKit
import QuartzCore
import UIKit
import SoundpipeAudioKit
import DunneAudioKit

@MainActor
@Observable
final class AudioDrivenVideoModel {

    enum PlaybackState: String {
        case idle
        case loading
        case ready
        case playing
        case paused
        case finished
        case failed
    }

    // MARK: - Public state

    var state: PlaybackState = .idle
    var statusText: String = "Idle"
    var rate: Float = 1.0
    var loopingEnabled: Bool = true
    var currentFrame: CGImage? = nil
    var videoSize: CGSize = .zero
    var flangeDepth: Float = 0.0

    var distanceMeters: Double = 0
    var normalizedDistance: Double = 0
    var distanceControlsPlaybackRate: Bool = true
    var minimumControlledRate: Float = 0.0
    var maximumControlledRate: Float = 2.0

    // MARK: - AudioKit

    private let engine = AudioEngine()
    private let player = AudioPlayer()
    private let flanger: Flanger
    private let sharedState: SharedFlightAudioState

    // MARK: - Asset / Video

    private var asset: AVURLAsset?
    private var videoTrack: AVAssetTrack?
    private var assetDuration: Double = 0

    private let ciContext = CIContext()

    // MARK: - Timing

    private var pausedMediaTime: Double = 0
    private var lastAudioPlayerTime: Double = 0

    // MARK: - Display

    private var displayLink: CADisplayLink?

    // MARK: - Decoding

    private let decodeQueue = DispatchQueue(label: "audioDrivenVideo.decode", qos: .userInitiated)
    private let frameStore = FrameStore()

    private var isDecoding = false
    private let decodeAheadSeconds: Double = 1.0
// MARK: SETUP OF AUDIOKIT ETC
    init(sharedState: SharedFlightAudioState) {
        self.sharedState = sharedState

        flanger = Flanger(player)
        engine.output = flanger

        player.isLooping = loopingEnabled
    }

    deinit {
        MainActor.assumeIsolated {
            displayLink?.invalidate()
        }
    }

    // MARK: - Public API

    func load(url: URL) async {
        stop()

        state = .loading
        statusText = "Loading..."

        do {
            let asset = AVURLAsset(url: url)
            self.asset = asset

            let playable = try await asset.load(.isPlayable)
            guard playable else {
                throw NSError(
                    domain: "AudioDrivenVideoModel",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Asset is not playable"]
                )
            }

            let duration = try await asset.load(.duration)
            assetDuration = duration.seconds

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw NSError(
                    domain: "AudioDrivenVideoModel",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "No video track found"]
                )
            }
            self.videoTrack = videoTrack

            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            videoSize = naturalSize.applying(preferredTransform).absoluteSize

            try player.load(url: url, buffered: true)
            player.isLooping = loopingEnabled

            if !engine.avEngine.isRunning {
                try engine.start()
            }

            await frameStore.clear()

            pausedMediaTime = 0
            lastAudioPlayerTime = 0
            currentFrame = nil
            isDecoding = false

            applyDistanceControlIfNeeded()
            startDecoding(from: 0)
            startDisplayLink()

            state = .ready
            statusText = loopingEnabled ? "Ready (looping)" : "Ready"

        } catch {
            state = .failed
            statusText = "Load failed: \(error.localizedDescription)"
        }
    }

    func play() {
        guard state == .ready || state == .paused else { return }

        do {
            if !engine.avEngine.isRunning {
                try engine.start()
            }

            player.isLooping = loopingEnabled
            applyDistanceControlIfNeeded()

            if state == .ready {
                lastAudioPlayerTime = 0
            } else {
                lastAudioPlayerTime = pausedMediaTime
            }

            player.play()

            state = .playing
            statusText = loopingEnabled ? "Playing (looping)" : "Playing"

        } catch {
            state = .failed
            statusText = "Play failed: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard state == .playing else { return }

        pausedMediaTime = currentMediaTime()
        player.pause()

        state = .paused
        statusText = "Paused"
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil

        player.stop()
        engine.stop()

        pausedMediaTime = 0
        lastAudioPlayerTime = 0

        isDecoding = false
        currentFrame = nil
        distanceMeters = 0
        normalizedDistance = 0

        asset = nil
        videoTrack = nil
        assetDuration = 0
        videoSize = .zero

        Task {
            await frameStore.clear()
        }

        state = .idle
        statusText = "Stopped"
    }

    // MARK: - Filters !!!!!

    func setFilter(_ effect: Float) {
        print(distanceMeters)
        let depth = 1.0 - mapRange(value: Float(distanceMeters), inMin: 0.0, inMax: 5000, outMin: 0.0, outMax: 1.0)

        flanger.depth = 0.0
        flanger.frequency = depth
        flangeDepth = depth // just for the visual slider
        flanger.feedback = depth
        flanger.dryWetMix = depth
    }

    func mapRange(value: Float, inMin: Float, inMax: Float, outMin: Float, outMax: Float) -> Float {
        let clampedValue = min(max(value, inMin), inMax)
        let inRange = inMax - inMin
        let outRange = outMax - outMin
        let scaled = (clampedValue - inMin) / inRange
        return outMin + (scaled * outRange)
    }

    func setLooping(_ enabled: Bool) {
        loopingEnabled = enabled
        player.isLooping = enabled

        statusText = switch state {
        case .playing:
            enabled ? "Playing (looping)" : "Playing"
        case .ready, .paused:
            enabled ? "Ready (looping)" : "Ready"
        default:
            statusText
        }
    }

    func setDistanceControlEnabled(_ enabled: Bool) {
        distanceControlsPlaybackRate = enabled
        if enabled {
            applyDistanceControlIfNeeded()
        }
    }

    private func applyDistanceControlIfNeeded() {
        distanceMeters = sharedState.distanceMeters
        normalizedDistance = sharedState.normalizedDistance

        guard distanceControlsPlaybackRate else { return }

        let nearDistance: Double = 1_000.0
        let farDistance: Double = 10_000.0

        let mappedRate: Float
        if distanceMeters <= nearDistance {
            mappedRate = maximumControlledRate
        } else if distanceMeters >= farDistance {
            mappedRate = minimumControlledRate
        } else {
            let t = Float((farDistance - distanceMeters) / (farDistance - nearDistance))
            mappedRate = minimumControlledRate + t * (maximumControlledRate - minimumControlledRate)
        }

        _ = mappedRate
        setFilter(Float(distanceMeters))
    }

    // MARK: - Display / Sync

    private func startDisplayLink() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(displayTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc
    private func displayTick() {
        guard assetDuration > 0 else { return }
        guard state == .playing || state == .paused else { return }

        applyDistanceControlIfNeeded()

        let audioTime = currentMediaTime()

        let didWrap =
            state == .playing &&
            loopingEnabled &&
            lastAudioPlayerTime > max(assetDuration - 0.25, assetDuration * 0.8) &&
            audioTime < 0.25

        lastAudioPlayerTime = audioTime

        Task {
            if didWrap {
                await frameStore.clear()
                currentFrame = nil
                startDecoding(from: 0)
            }

            let bufferedMax = await frameStore.maxBufferedTime ?? 0
            if audioTime + decodeAheadSeconds > bufferedMax, !isDecoding {
                startDecoding(from: bufferedMax)
            }

            await frameStore.discardFrames(olderThan: audioTime - 0.2)

            if let frame = await frameStore.bestFrame(for: audioTime) {
                currentFrame = frame.image
            }

            if !loopingEnabled, state == .playing, audioTime >= assetDuration {
                player.stop()
                pausedMediaTime = assetDuration
                state = .finished
                statusText = "Finished"
            }
        }
    }

    private func currentMediaTime() -> Double {
        guard assetDuration > 0 else { return 0 }

        switch state {
        case .playing:
            // If your AudioKit version exposes a slightly different name,
            // replace this with that property.
            let t = player.currentTime
            return min(max(t, 0), assetDuration)

        case .paused:
            return min(max(pausedMediaTime, 0), assetDuration)

        case .finished:
            return assetDuration

        default:
            return 0
        }
    }

    // MARK: - Decoding

    private func startDecoding(from startTime: Double) {
        guard !isDecoding else { return }
        guard let asset, let videoTrack else { return }
        guard assetDuration > 0 else { return }

        isDecoding = true

        decodeQueue.async { [weak self] in
            guard let self else { return }

            do {
                let reader = try AVAssetReader(asset: asset)

                let settings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]

                let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: settings)
                output.alwaysCopiesSampleData = false

                guard reader.canAdd(output) else {
                    throw NSError(
                        domain: "AudioDrivenVideoModel",
                        code: -10,
                        userInfo: [NSLocalizedDescriptionKey: "Could not add video output"]
                    )
                }

                reader.add(output)

                let safeStart = max(0, min(startTime, self.assetDuration))
                let safeEnd = min(safeStart + self.decodeAheadSeconds, self.assetDuration)

                reader.timeRange = CMTimeRange(
                    start: CMTime(seconds: safeStart, preferredTimescale: 600),
                    end: CMTime(seconds: safeEnd, preferredTimescale: 600)
                )

                guard reader.startReading() else {
                    throw reader.error ?? NSError(
                        domain: "AudioDrivenVideoModel",
                        code: -11,
                        userInfo: [NSLocalizedDescriptionKey: "Reader failed to start"]
                    )
                }

                while reader.status == .reading {
                    guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                    let cgImage = self.makeFilteredFrame(from: imageBuffer)

                    Task { @MainActor in
                        await self.frameStore.append(
                            DecodedFrame(time: pts, image: cgImage)
                        )
                    }
                }

                Task { @MainActor in
                    self.isDecoding = false
                }

            } catch {
                Task { @MainActor in
                    self.isDecoding = false
                    self.state = .failed
                    self.statusText = "Decode failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func makeFilteredFrame(from pixelBuffer: CVPixelBuffer) -> CGImage {
        let input = CIImage(cvPixelBuffer: pixelBuffer)

        let color = CIFilter.colorControls()
        color.inputImage = input
        color.saturation = 1.1
        color.contrast = 1.05
        color.brightness = 0.0

        let bloom = CIFilter.bloom()
        bloom.inputImage = color.outputImage
        bloom.intensity = 0.2
        bloom.radius = 2.0

        let vignette = CIFilter.vignette()
        vignette.inputImage = bloom.outputImage
        vignette.intensity = 0.4
        vignette.radius = 1.2

        let output = (vignette.outputImage ?? input).cropped(to: input.extent)

        if let cg = ciContext.createCGImage(output, from: output.extent) {
            return cg
        }

        if let fallback = ciContext.createCGImage(input, from: input.extent) {
            return fallback
        }

        fatalError("Failed to create CGImage from CIImage")
    }
}

// MARK: - Frame types

struct DecodedFrame {
    let time: Double
    let image: CGImage
}

actor FrameStore {
    private var frames: [DecodedFrame] = []

    var maxBufferedTime: Double? {
        frames.last?.time
    }

    func clear() {
        frames.removeAll()
    }

    func append(_ frame: DecodedFrame) {
        frames.append(frame)
        frames.sort { $0.time < $1.time }
    }

    func discardFrames(olderThan time: Double) {
        frames.removeAll { $0.time < time }
    }

    func bestFrame(for targetTime: Double) -> DecodedFrame? {
        guard !frames.isEmpty else { return nil }

        if let next = frames.first(where: { $0.time >= targetTime }) {
            return next
        } else {
            return frames.last
        }
    }
}

// MARK: - Helpers

private extension CGSize {
    var absoluteSize: CGSize {
        CGSize(width: abs(width), height: abs(height))
    }
}
