//
//  AudioDrivenVideoModel.swift
//

import Foundation
import Observation
@preconcurrency import AVFoundation
import AudioKit
import SoundpipeAudioKit
import DunneAudioKit

@MainActor
@Observable
final class AudioDrivenModel {

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

    // MARK: - Audio asset

    private var assetDuration: Double = 0

    // MARK: - Timing

    private var pausedMediaTime: Double = 0
    private var lastAudioPlayerTime: Double = 0

// MARK: SETUP OF AUDIOKIT ETC
    init(sharedState: SharedFlightAudioState) {
        self.sharedState = sharedState

        flanger = Flanger(player)
        engine.output = flanger

        player.isLooping = loopingEnabled
    }

    // MARK: - Public API

    func load(url: URL) async {
        stop()

        state = .loading
        statusText = "Loading..."

        do {
            let asset = AVURLAsset(url: url)

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

            try player.load(url: url, buffered: true)
            player.isLooping = loopingEnabled

            if !engine.avEngine.isRunning {
                try engine.start()
            }

            pausedMediaTime = 0
            lastAudioPlayerTime = 0

            applyDistanceControlIfNeeded()

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
                player.seek(time: pausedMediaTime)
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
        player.stop()
        engine.stop()

        pausedMediaTime = 0
        lastAudioPlayerTime = 0

        distanceMeters = 0
        normalizedDistance = 0

        assetDuration = 0

        state = .idle
        statusText = "Stopped"
    }

    // MARK: - Filters !!!!!

    func setFilter(_ effect: Float) {
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

        rate = mappedRate
        //player.rate = mappedRate
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
}
