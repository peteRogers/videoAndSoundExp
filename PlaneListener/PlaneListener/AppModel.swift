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
    var bearing: Double = 0
    var height: Double = 0
    var speed: Double = 0
    var nilState = true
    
    func setNilState(){
        
        distanceMeters = 0
        normalizedDistance = 0
        bearing = 0
        height = 0
        speed = 0
        nilState = true
    }
   
}
