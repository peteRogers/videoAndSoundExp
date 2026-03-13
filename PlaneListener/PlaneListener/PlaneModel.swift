//
//  PlaneModel.swift
//  PlaneListener
//

import Foundation
import Observation

@MainActor
@Observable
final class PlaneModel {

    var selected: Plane? = nil
    var statusText: String = "Idle"
    var lastUpdated: Date? = nil
    var selectedDistanceMeters: Double? = nil
    

    // Your location
    var myLatitude: Double = 51.474144
    var myLongitude: Double =  -0.035375

    private let endpoint = URL(string: "http://127.0.0.1:8080/data/aircraft.json")!

    @ObservationIgnored
    private var refreshTask: Task<Void, Never>? = nil

    @ObservationIgnored
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        return URLSession(configuration: config)
    }()
    
    private let sharedState: SharedFlightAudioState

    init(sharedState: SharedFlightAudioState) {
        self.sharedState = sharedState
    }

    func startRefreshing() {
        guard refreshTask == nil else { return }

        statusText = "Starting…"

        refreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.refreshOnce()

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
        statusText = "Stopped"
    }

    func refreshOnce() async {
        statusText = "Fetching…"

        do {
            let (data, response) = try await session.data(from: endpoint)

            guard let httpResponse = response as? HTTPURLResponse else {
                statusText = "Error: Invalid response"
                sharedState.distanceMeters = 0
                sharedState.normalizedDistance = 0
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                statusText = "HTTP \(httpResponse.statusCode)"
                sharedState.distanceMeters = 0
                sharedState.normalizedDistance = 0
                return
            }

            let decoded = try JSONDecoder().decode(AircraftResponse.self, from: data)

            let closest = decoded.aircraft
                .compactMap { plane -> (plane: Plane, distance: Double)? in
                    guard let lat = plane.lat, let lon = plane.lon else { return nil }

                    let distance = distanceMeters(
                        fromLat: myLatitude,
                        lon: myLongitude,
                        toLat: lat,
                        lon: lon
                    )

                    return (plane, distance)
                }
                .min(by: { $0.distance < $1.distance })

            selected = closest?.plane
            selectedDistanceMeters = closest?.distance
            lastUpdated = Date()
            statusText = closest == nil ? "No aircraft with position found" : "OK"

            if let distance = closest?.distance {
                sharedState.distanceMeters = distance

                let maxDistance = 10_000.0
                let clamped = min(max(distance, 0), maxDistance)
                sharedState.normalizedDistance = 1.0 - (clamped / maxDistance)
            } else {
                sharedState.distanceMeters = 0
                sharedState.normalizedDistance = 0
            }
        } catch is CancellationError {
            statusText = "Stopped"
            sharedState.distanceMeters = 0
            sharedState.normalizedDistance = 0
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                statusText = "Error: Request timed out"
            case .notConnectedToInternet:
                statusText = "Error: Not connected"
            case .cannotConnectToHost:
                statusText = "Error: Cannot connect to host"
            case .networkConnectionLost:
                statusText = "Error: Connection lost"
            default:
                statusText = "Network error: \(error.localizedDescription)"
            }
            sharedState.distanceMeters = 0
            sharedState.normalizedDistance = 0
        } catch let decodingError as DecodingError {
            statusText = "Decode error: \(decodingError.localizedDescription)"
            sharedState.distanceMeters = 0
            sharedState.normalizedDistance = 0
        } catch {
            statusText = "Error: \(error.localizedDescription)"
            sharedState.distanceMeters = 0
            sharedState.normalizedDistance = 0
        }
    }

    deinit {
        MainActor.assumeIsolated {
            refreshTask?.cancel()
        }
    }
}

struct AircraftResponse: Codable {
    let aircraft: [Plane]
}

struct Plane: Codable, Identifiable {
    var id: String { hex ?? "unknown-plane" }

    let hex: String?
    let flight: String?
    let lat: Double?
    let lon: Double?
    let alt_baro: Double?
    let gs: Double?
    let track: Double?
}
