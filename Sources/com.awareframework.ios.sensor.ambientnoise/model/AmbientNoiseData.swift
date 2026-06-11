//
//  AmbientNoiseData.swift
//  com.awareframework.ios.sensor.ambientnoise
//

import Foundation
import GRDB
import com_awareframework_ios_core

public struct AmbientNoiseData: BaseDbModelSQLite {
    public var timezone: Int = AwareUtils.getTimeZone()
    public var os: String = "iOS"
    public var jsonVersion: Int = 1

    public var id: Int64?
    public var timestamp: Int64
    public var deviceId: String = AwareUtils.getCommonDeviceId()
    public var label: String

    public static let databaseTableName = "ambient_noise"

    public var db: Double = 0.0

    public init(timestamp: Int64, db: Double, label: String = "") {
        self.db = db
        self.timestamp = timestamp
        self.label = label
    }

    public init(_ dict: [String: Any]) {
        self.timestamp = dict["timestamp"] as? Int64 ?? 0
        self.deviceId = dict["deviceId"] as? String ?? ""
        self.db = dict["db"] as? Double ?? 0
        self.label = dict["label"] as? String ?? ""
    }

    public static func createTable(queue: GRDB.DatabaseQueue) {
        do {
            try queue.write { db in
                try db.create(table: AmbientNoiseData.databaseTableName, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("deviceId", .text).notNull()
                    t.column("timestamp", .integer).notNull()
                    t.column("db", .double).notNull()
                    t.column("os", .text).notNull()
                    t.column("timezone", .integer).notNull()
                    t.column("jsonVersion", .integer).notNull()
                    t.column("label", .text).notNull()
                }
            }
        } catch {
            print(error)
        }
    }

    public func toDictionary() -> [String: Any] {
        return [
            "id": self.id ?? -1,
            "timestamp": timestamp,
            "deviceId": deviceId,
            "db": db,
            "label": label,
        ]
    }
}
