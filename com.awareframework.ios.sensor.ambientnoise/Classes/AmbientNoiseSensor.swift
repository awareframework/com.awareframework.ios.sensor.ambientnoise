//
//  AmbientNoiseSensor.swift
//  com.aware.ios.sensor.ambientnoise
//
//  Created by Yuuki Nishiyama on 2018/11/13.
//

import UIKit
import com_awareframework_ios_sensor_core

public class AmbientNoiseSensor: AwareSensor {
    var ambientNoiseMonitor:ANMonitor?
    public var CONFIG = Config()
    
    public class Config:SensorConfig {
        // Sampling interval in minute. (default = 5)
        public var interval:Int            = 5;
        
        // samples: Int : Data samples to collect per minute. (default = 30)
        public var samples:Int             = 30;
        
        // silenceThreshold: Double: A threshold of RMS for determining silence or not. (default = 50)
        public var silenceThreshold:Double = 50.0;
        
        public var sensorObserver:AmbientNoiseObserver?
        
        public override init() {
            super.init()
            dbPath = "aware_ambientnoise"
        }
        
        public override func set(config: Dictionary<String, Any>) {
            super.set(config: config)
            if let interval = config["interval"] as? Int {
                self.interval = interval
            }
            
            if let samples = config["samples"] as? Int {
                self.samples = samples
            }
            
            if let silenceThreshold = config["silenceThreshold"] as? Double {
                self.silenceThreshold = silenceThreshold
            }
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
                monitor.frequencyMin = Int32(self.CONFIG.interval)
                monitor.sampleSize = Int32(self.CONFIG.samples)
                monitor.silenceThreshold = Int32(self.CONFIG.silenceThreshold)
                monitor.setANMonitorOutputHadler { (mf, db, rms, rawData, url, audioId) in
                    // callback
                    if self.CONFIG.debug {
                        print("[\(audioId)] MaxFrequency:\(mf), Decobel:\(db), RMS:\(rms)")
                    }
                    let data = AmbientNoiseData()
                    data.decibels = db
                    data.rms = rms
                    data.frequency = Double(mf)
                    if rms > self.CONFIG.silenceThreshold {
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
            engine.startSync(AmbientNoiseData.TABLE_NAME, AmbientNoiseData.self, DbSyncConfig.init().apply{config in
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
