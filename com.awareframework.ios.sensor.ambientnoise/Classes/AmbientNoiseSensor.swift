//
//  AmbientNoiseSensor.swift
//  com.aware.ios.sensor.ambientnoise
//
//  Created by Yuuki Nishiyama on 2018/11/13.
//

import UIKit
import SwiftyJSON
import com_awareframework_ios_sensor_core

public class AmbientNoiseSensor: AwareSensor {
    var ambientNoiseMonitor:ANMonitor?
    public var CONFIG = Config()
    
    public class Config:SensorConfig {
        public var frequencyMin = 5;
        public var sampleSize   = 30;
        public var silenceThreshold = 50;
        public var sensorObserver:AmbientNoiseObserver?
        
        public override init() {
            super.init()
            dbPath = "aware_ambientnoise"
        }
        
        public convenience init(_ json:JSON){
            self.init()
        }
        
        public func apply(closure:(_ config: AmbientNoiseSensor.Config) -> Void) -> Self {
            closure(self)
            return self
        }
    }
    
    public override convenience init() {
        self.init(Config())
    }
    
    public init(_ config: Config) {
        super.init()
        CONFIG = config
        initializeDbEngine(config: config)
    }
    
    public override func start() {
        if self.ambientNoiseMonitor == nil {
            self.ambientNoiseMonitor = ANMonitor()
            if let monitor = self.ambientNoiseMonitor {
                // analyzer.delegate = self
                monitor.frequencyMin = Int32(self.CONFIG.frequencyMin)
                monitor.sampleSize = Int32(self.CONFIG.sampleSize)
                monitor.silenceThreshold = Int32(self.CONFIG.silenceThreshold)
                monitor.setANMonitorOutputHadler { (mf, db, rms, rawData, url, audioId) in
                    // callback
                    if self.CONFIG.debug {
                        print("[\(audioId)] MaxFrequency:\(mf), Decobel:\(db), RMS:\(rms)")
                    }
                    let data = AmbientNoiseData()
                    data.soundDecibels = db
                    data.soundRMS = rms
                    data.soundFrequency = Double(mf)
                    if Int(rms) > self.CONFIG.silenceThreshold {
                        data.isSilent = false
                    }
                    if let engine = self.dbEngine {
                        engine.save(data, AmbientNoiseData.TABLE_NAME)
                    }
                    if let observer = self.CONFIG.sensorObserver {
                        observer.onAmbientNoiseChanged(data: data)
                    }
                    self.notificationCenter.post(name: .actionAwareAmbientNoise, object: nil)
                }
                monitor.start()
                self.notificationCenter.post(name: .actionAwareAmbientNoiseStart, object: nil)
            }
        }
    }

    public override func stop() {
        if let monitor = self.ambientNoiseMonitor {
            monitor.stop()
            self.ambientNoiseMonitor = nil
            self.notificationCenter.post(name: .actionAwareAmbientNoiseStop, object: nil)
        }
    }
    
    public override func sync(force: Bool = false) {
        if let engine = self.dbEngine {
            engine.startSync(AmbientNoiseData.TABLE_NAME, DbSyncConfig.init().apply{config in
                config.debug = self.CONFIG.debug
            })
            self.notificationCenter.post(name: .actionAwareAmbientNoiseSync, object: nil)
        }
    }
}

public protocol AmbientNoiseObserver{
    func onAmbientNoiseChanged(data:AmbientNoiseData)
}

extension Notification.Name {
    public static let actionAwareAmbientNoise         = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE)
    public static let actionAwareAmbientNoiseStart    = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE_START)
    public static let actionAwareAmbientNoiseStop     = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE_STOP)
    public static let actionAwareAmbientNoiseSync     = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE_SYNC)
    public static let actionAwareAmbientNoiseSetLabel = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE_SET_LABEL)
}

extension AmbientNoiseSensor{
    public static let ACTION_AWARE_AMBIENTNOISE       = "ACTION_AWARE_AMBIENTNOISE"
    public static let ACTION_AWARE_AMBIENTNOISE_START = "ACTION_AWARE_AMBIENTNOISESENSOR_START"
    public static let ACTION_AWARE_AMBIENTNOISE_STOP  = "ACTION_AWARE_AMBIENTNOISESENSOR_STOP"
    public static let ACTION_AWARE_AMBIENTNOISE_SET_LABEL = "ACTION_AWARE_AMBIENTNOISESET_LABEL"
    public static let ACTION_AWARE_AMBIENTNOISE_SYNC  = "ACTION_AWARE_AMBIENTNOISESENSOR_SYNC"
}
