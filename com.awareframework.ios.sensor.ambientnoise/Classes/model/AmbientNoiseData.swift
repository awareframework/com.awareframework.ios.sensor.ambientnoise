//
//  AmbientNoiseData.swift
//  com.aware.ios.sensor.ambientnoise
//
//  Created by Yuuki Nishiyama on 2018/11/13.
//

import UIKit
import com_awareframework_ios_sensor_core

public class AmbientNoiseData: AwareObject {

    public static let TABLE_NAME = "ambientNoiseTable"
    
    @objc dynamic public var soundFrequency:Double = 0
    @objc dynamic public var soundDecibels:Double  = 0
    @objc dynamic public var soundRMS:Double = 0
    @objc dynamic public var isSilent:Bool = true
    
    
    public override func toDictionary() -> Dictionary<String, Any> {
        var dict = super.toDictionary()
        dict["soundFrequency"] = soundFrequency
        dict["soundDecibels"] = soundDecibels
        dict["soundRMS"] = soundRMS
        dict["isSilent"] = isSilent
        return dict;
    }
}
