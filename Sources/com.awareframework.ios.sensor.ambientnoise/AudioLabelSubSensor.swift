//
//  AudioLabelSubSensor.swift
//  com.awareframework.ios.sensor.ambientnoise
//

import Foundation
import com_awareframework_ios_core

public class AudioLabelSubSensor: AwareSensor {

    public var CONFIG = AmbientNoiseSensor.Config()

    public init(_ config: AmbientNoiseSensor.Config) {
        super.init()
        self.CONFIG = Self.makeConfig(from: config)
        self.CONFIG.dbTableName = AudioLabelData.databaseTableName
        self.CONFIG.dbPath = AudioLabelData.databaseTableName
        self.initializeDbEngine(config: self.CONFIG)
        super.syncConfig = DbSyncConfig().apply(closure: { config in
            config.serverType = self.CONFIG.serverType
            config.debug = self.CONFIG.debug
            config.batchSize = 1000
            config.dispatchQueue = DispatchQueue(label: "com.awareframework.ios.sensor.ambientnoise.audiolabel.sync.queue")
        })

        if let sqliteEngine = self.dbEngine as? SQLiteEngine,
           let instance = sqliteEngine.getSQLiteInstance() {
            do {
                try AudioLabelData.createTable(queue: instance)
            } catch {
                if CONFIG.debug {
                    print(error)
                }
            }
        }
    }

    public func applySyncSettings(
        from parentConfig: AmbientNoiseSensor.Config,
        parentSyncConfig: DbSyncConfig?,
        completionHandler: DbSyncCompletionHandler?
    ) {
        CONFIG.dbHost = parentConfig.dbHost
        CONFIG.dbType = parentConfig.dbType
        CONFIG.dbEncryptionKey = parentConfig.dbEncryptionKey
        CONFIG.serverType = parentConfig.serverType
        CONFIG.studyNumber = parentConfig.studyNumber
        CONFIG.studyKey = parentConfig.studyKey
        CONFIG.debug = parentConfig.debug
        CONFIG.label = parentConfig.label
        CONFIG.dbPath = AudioLabelData.databaseTableName
        CONFIG.dbTableName = AudioLabelData.databaseTableName
        initializeDbEngine(config: CONFIG)

        let config = syncConfig ?? DbSyncConfig()
        if let parentSyncConfig {
            config.removeAfterSync = parentSyncConfig.removeAfterSync
            config.batchSize = parentSyncConfig.batchSize
            config.markAsSynced = parentSyncConfig.markAsSynced
            config.skipSyncedData = parentSyncConfig.skipSyncedData
            config.keepLastData = parentSyncConfig.keepLastData
            config.deviceId = parentSyncConfig.deviceId
            config.debugLevel = parentSyncConfig.debugLevel
            config.progressHandler = parentSyncConfig.progressHandler
            config.backgroundSession = parentSyncConfig.backgroundSession
            config.compactDataFormat = parentSyncConfig.compactDataFormat
            config.test = parentSyncConfig.test
        }
        config.serverType = CONFIG.serverType
        config.studyNumber = CONFIG.studyNumber
        config.studyKey = CONFIG.studyKey
        config.debug = CONFIG.debug
        config.completionHandler = completionHandler
        config.dispatchQueue = DispatchQueue(label: "com.awareframework.ios.sensor.ambientnoise.audiolabel.sync.queue")
        syncConfig = config
    }

    public override func start() {}

    public override func stop() {}

    public override func sync(force: Bool = false) {
        if let engine = self.dbEngine, let syncConfig = super.syncConfig {
            engine.startSync(syncConfig)
        }
    }

    public override func set(label: String) {}

    private static func makeConfig(from source: AmbientNoiseSensor.Config) -> AmbientNoiseSensor.Config {
        AmbientNoiseSensor.Config().apply { config in
            config.enabled = source.enabled
            config.debug = source.debug
            config.label = source.label
            config.deviceId = source.deviceId
            config.dbEncryptionKey = source.dbEncryptionKey
            config.dbType = source.dbType
            config.serverType = source.serverType
            config.studyNumber = source.studyNumber
            config.studyKey = source.studyKey
            config.dbHost = source.dbHost
            config.onBus = source.onBus
            config.bufferSize = source.bufferSize
            config.audioClassifierModel = source.audioClassifierModel
            config.activateAmbientNoiseSensor = source.activateAmbientNoiseSensor
            config.activateAudioClassificationSensor = source.activateAudioClassificationSensor
            config.storeOnlyTopK = source.storeOnlyTopK
            config.preferredInputUID = source.preferredInputUID
            config.currentInputUID = source.currentInputUID
            config.currentInputName = source.currentInputName
            config.currentInputPortType = source.currentInputPortType
            config.sensorObserver = source.sensorObserver
        }
    }
}
