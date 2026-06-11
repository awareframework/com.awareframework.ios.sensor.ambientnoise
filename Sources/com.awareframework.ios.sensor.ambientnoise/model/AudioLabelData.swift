//
//  AudioLabelData.swift
//  com.awareframework.ios.sensor.ambientnoise
//

import Foundation
import com_awareframework_ios_core
import GRDB

public struct AudioLabelData: BaseDbModelSQLite {
    public var timezone: Int = AwareUtils.getTimeZone()
    public var os: String = "iOS"
    public var jsonVersion: Int = 1

    public var id: Int64?
    public var timestamp: Int64
    public var deviceId: String = AwareUtils.getCommonDeviceId()
    public var label: String

    public static let databaseTableName = "audio_label"

    public var audioLabel: String = ""
    public var confidence: Double = 0.0

    public init(timestamp: Int64, audioLabel: String, confidence: Double, label: String = "") {
        self.timestamp = timestamp
        self.audioLabel = audioLabel
        self.confidence = confidence
        self.label = label
    }

    public init(_ dict: Dictionary<String, Any>) {
        self.timestamp = dict["timestamp"] as? Int64 ?? 0
        self.deviceId = dict["deviceId"] as? String ?? ""
        self.audioLabel = dict["audioLabel"] as? String ?? ""
        self.confidence = dict["confidence"] as? Double ?? 0
        self.label = dict["label"] as? String ?? ""
    }

    public static func createTable(queue: GRDB.DatabaseQueue) throws {
        try queue.write { db in
            try db.create(table: AudioLabelData.databaseTableName, ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceId", .text).notNull()
                t.column("timestamp", .integer).notNull()
                t.column("audioLabel", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("os", .text).notNull()
                t.column("timezone", .integer).notNull()
                t.column("jsonVersion", .integer).notNull()
                t.column("label", .text).notNull()
            }
        }
    }

    public func toDictionary() -> Dictionary<String, Any> {
        return [
            "id": self.id ?? -1,
            "timestamp": timestamp,
            "deviceId": deviceId,
            "audioLabel": audioLabel,
            "confidence": confidence,
            "label": label,
        ]
    }
}
