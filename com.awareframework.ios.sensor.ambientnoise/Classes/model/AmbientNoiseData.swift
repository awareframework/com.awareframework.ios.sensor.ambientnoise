//
//  AmbientNoiseData.swift
//  com.aware.ios.sensor.ambientnoise
//
//  Created by Yuuki Nishiyama on 2018/11/13.
//

import UIKit
import com_awareframework_ios_sensor_core

public class AmbientNoiseData: AwareObject {

    public static let TABLE_NAME = "ambientNoiseData"
    
    @objc dynamic public var frequency:Double = 0
    @objc dynamic public var decibels:Double  = 0
    @objc dynamic public var rms:Double = 0
    @objc dynamic public var isSilent:Bool = true
    
    
    public override func toDictionary() -> Dictionary<String, Any> {
        var dict = super.toDictionary()
        dict["frequency"] = frequency
        dict["decibels"] = decibels
        dict["rms"] = rms
        dict["isSilent"] = isSilent
        return dict;
    }
}
