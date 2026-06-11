//
//  SignalProcessing.swift
//  com.awareframework.ios.sensor.ambientnoise
//

import Accelerate
import AVFoundation

class SignalProcessing {

    static func rms(data: UnsafeMutablePointer<Float>, frameLength: UInt) -> Float {
        var val: Float = 0
        vDSP_rmsqv(data, 1, &val, frameLength)
        return val
    }

    static func db(from rms: Float, base: Float = 1) -> Float {
        return 20 * log10f(rms / base)
    }
}
