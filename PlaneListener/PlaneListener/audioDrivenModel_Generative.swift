//
//  audioDrivenModel_Generative.swift
//  PlaneListener
//
//  Created by Peter Rogers on 17/03/2026.
//

import Foundation
import Observation

import AudioKit
import SoundpipeAudioKit
import DunneAudioKit
import AudioKitEX


@MainActor
@Observable
final class AudioDrivenModel_Generative {
    private let engine = AudioEngine()
    private var mixer:Mixer
    private var p:PluckedString
    private let sharedState: SharedFlightAudioState
    private let osc: Oscillator
    init(sharedState: SharedFlightAudioState) {
        self.sharedState = sharedState
        mixer = Mixer()
        p = PluckedString()
        osc = Oscillator()
        osc.start()
        mixer.addInput(osc)
       
        engine.output = mixer
        
        do{
            try engine.start()
        }catch{
            
        }
        p.trigger()
    }
    
    func play(){
        osc.frequency = AUValue(sharedState.distanceMeters/10.0)
       
       // osc.
        //p.trigger()
        
       
        
    }
    
    func stop(){
        //p.trigger()
        
    }
}


