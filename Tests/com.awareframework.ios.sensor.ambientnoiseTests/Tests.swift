import XCTest
@testable import com_awareframework_ios_sensor_ambientnoise

final class AmbientNoiseSensorTests: XCTestCase {

    func testConfigDefaults() {
        let config = AmbientNoiseSensor.Config()
        XCTAssertTrue(config.activateAmbientNoiseSensor)
        XCTAssertFalse(config.activateAudioClassificationSensor)
        XCTAssertTrue(config.dutyCycleEnabled)
        XCTAssertNil(config.storeOnlyTopK)
    }

    func testConfigApply() {
        let config = AmbientNoiseSensor.Config().apply { c in
            c.activateAmbientNoiseSensor = true
            c.activateAudioClassificationSensor = false
            c.storeOnlyTopK = 5
            c.debug = true
        }
        XCTAssertTrue(config.activateAmbientNoiseSensor)
        XCTAssertFalse(config.activateAudioClassificationSensor)
        XCTAssertEqual(config.storeOnlyTopK, 5)
        XCTAssertTrue(config.debug)
    }

    func testAmbientNoiseDataInit() {
        let data = AmbientNoiseData(timestamp: 1000, db: -42.5, label: "test")
        XCTAssertEqual(data.timestamp, 1000)
        XCTAssertEqual(data.db, -42.5)
        XCTAssertEqual(data.label, "test")
        XCTAssertEqual(data.os, "iOS")
    }

    func testAmbientNoiseDataToDictionary() {
        let data = AmbientNoiseData(timestamp: 2000, db: -30.0, label: "")
        let dict = data.toDictionary()
        XCTAssertEqual(dict["timestamp"] as? Int64, 2000)
        XCTAssertEqual(dict["db"] as? Double, -30.0)
    }

    func testAudioLabelDataInit() {
        let data = AudioLabelData(timestamp: 3000, audioLabel: "music", confidence: 0.95, label: "")
        XCTAssertEqual(data.timestamp, 3000)
        XCTAssertEqual(data.audioLabel, "music")
        XCTAssertEqual(data.confidence, 0.95)
        XCTAssertEqual(data.os, "iOS")
    }

    func testAudioLabelDataToDictionary() {
        let data = AudioLabelData(timestamp: 4000, audioLabel: "speech", confidence: 0.8)
        let dict = data.toDictionary()
        XCTAssertEqual(dict["audioLabel"] as? String, "speech")
        XCTAssertEqual(dict["confidence"] as? Double, 0.8)
    }

    func testAmbientNoiseDataTableName() {
        XCTAssertEqual(AmbientNoiseData.databaseTableName, "ios_ambient_noise")
    }

    func testAudioLabelDataTableName() {
        XCTAssertEqual(AudioLabelData.databaseTableName, "ios_audio_label")
    }
}
