//
//  AmbientNoiseSubSensor.swift
//  com.awareframework.ios.sensor.ambientnoise
//

import Foundation
import com_awareframework_ios_core

public class AmbientNoiseSubSensor: AwareSensor {

    public var CONFIG = AmbientNoiseSensor.Config()

    public init(_ config: AmbientNoiseSensor.Config) {
        super.init()
        self.CONFIG = config
        self.CONFIG.dbPath = AmbientNoiseData.databaseTableName
        self.CONFIG.dbTableName = AmbientNoiseData.databaseTableName
        self.initializeDbEngine(config: self.CONFIG)
        super.syncConfig = DbSyncConfig().apply(closure: { config in
            config.serverType = self.CONFIG.serverType
            config.debug = self.CONFIG.debug
            config.batchSize = 1000
            config.dispatchQueue = DispatchQueue(label: "com.awareframework.ios.sensor.ambientnoise.ambientnoise.sync.queue")
        })

        if let sqliteEngine = self.dbEngine as? SQLiteEngine,
           let instance = sqliteEngine.getSQLiteInstance() {
            AmbientNoiseData.createTable(queue: instance)
        }
    }

    public override func start() {}

    public override func stop() {}

    public override func sync(force: Bool = false) {
        if let engine = self.dbEngine, let syncConfig = super.syncConfig {
            engine.startSync(syncConfig)
        }
    }

    public override func set(label: String) {}
}
