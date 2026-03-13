//
//  GeoHelpers.swift
//  PlaneListener
//
//  Created by student on 09/03/2026.
//

import Foundation

func degreesToRadians(_ degrees: Double) -> Double {
    degrees * .pi / 180
}

func radiansToDegrees(_ radians: Double) -> Double {
    radians * 180 / .pi
}

/// Bearing in degrees from point A to point B.
/// 0 = north, 90 = east, 180 = south, 270 = west
func bearingDegrees(
    fromLat lat1: Double,
    lon lon1: Double,
    toLat lat2: Double,
    lon lon2: Double
) -> Double {
    let φ1 = degreesToRadians(lat1)
    let φ2 = degreesToRadians(lat2)
    let Δλ = degreesToRadians(lon2 - lon1)

    let y = sin(Δλ) * cos(φ2)
    let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)

    let θ = atan2(y, x)
    let bearing = radiansToDegrees(θ)

    return (bearing + 360).truncatingRemainder(dividingBy: 360)
}

/// Simple haversine distance in metres
func distanceMeters(
    fromLat lat1: Double,
    lon lon1: Double,
    toLat lat2: Double,
    lon lon2: Double
) -> Double {
    let earthRadius = 6_371_000.0

    let φ1 = degreesToRadians(lat1)
    let φ2 = degreesToRadians(lat2)
    let Δφ = degreesToRadians(lat2 - lat1)
    let Δλ = degreesToRadians(lon2 - lon1)

    let a = sin(Δφ / 2) * sin(Δφ / 2)
        + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)

    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadius * c
}

extension Float {
    func mapped(from inMin: Float, _ inMax: Float, to outMin: Float, _ outMax: Float) -> Float {
        let clamped = min(max(self, inMin), inMax)
        let inRange = inMax - inMin
        let outRange = outMax - outMin
        let scaled = (clamped - inMin) / inRange
        return outMin + (scaled * outRange)
    }
}
