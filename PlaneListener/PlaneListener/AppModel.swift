//
//  AppModel.swift
//  PlaneListener
//
//  Created by Peter Rogers on 09/03/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class SharedFlightAudioState {
    var distanceMeters: Double = 0
    var normalizedDistance: Double = 0
}
