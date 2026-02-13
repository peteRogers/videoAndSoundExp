//
//  SerialModel.swift
//  SerialTemplate
//
//  Created by Peter Rogers on 05/11/2025.
//

import Observation

@Observable class SerialModel {
    var serial: SerialManager?
    var val0:Float = 0.0
    var val1:Float = 0.0
    
    
    func startSerial(){
        serial = SerialManager()
        observeSerial()
    }
    
    //MARK: work on arduino values to create logic based on values.
    
    func receiveArduinoValues(values: [Int:Float]){
        if let v0 = values[0] {
           // val0 = v0 / 1024.0
            val0 = v0
            //print(val0)
        }
        if let v1 = values[1] {
            val1 = v1 / 1024.0
        }
    }
    
    func sendArduinoValue(val: Float){
        let s = "0:\(val)"
        serial?.send(s)
    }
    
    
 //MARK: leave alone
    func observeSerial() {
        guard let serial else { return }
        Task { @MainActor in
            for await values in serial.updates {
                self.receiveArduinoValues(values: values)
            }
        }
    }
}
