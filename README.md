# AWARE: Ambient Noise

[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)

This sensor module captures ambient sound levels (decibels) and classifies audio using Apple's SoundAnalysis framework with either a custom Core ML classifier or the audio classification model built into iOS. It provides two concurrent data streams: continuous decibel measurements and sound classification labels with confidence scores.

## Requirements
iOS 15 or later

## Installation

1. Open Package Manager Windows
    * Open `Xcode` -> Select `Menu Bar` -> `File` -> `App Package Dependencies...`

2. Find the package using the manager
    * Select `Search Package URL` and type `https://github.com/awareframework/com.awareframework.ios.sensor.ambientnoise.git`

3. Import the package into your target.

4. Add `NSMicrophoneUsageDescription` to your `Info.plist`.

## Public functions

### AmbientNoiseSensor

+ `init(_ config: AmbientNoiseSensor.Config)`: Initializes the sensor with the given configuration.
+ `start()`: Starts audio recording and analysis.
+ `stop()`: Stops audio processing and releases the audio engine.
+ `sync(force:)`: Syncs stored data to the configured host.
+ `set(label:)`: Sets a custom label applied to all subsequent data points.
+ `availableMicrophoneInputs() -> [AmbientNoiseMicrophoneInput]`: Returns the list of available microphone inputs.
+ `refreshCurrentMicrophone()`: Updates the current microphone info in the config.
+ `applyRuntimeAudioConfiguration()`: Resets the duty cycle and rebuilds the stream analyzer with the current config without restarting the audio engine. Call this after changing config fields such as `activateAudioClassificationSensor` or `audioClassifierModelURL` while the sensor is running.
+ `currentDutyCycleStatus(now:) -> DutyCycleStatus?`: Returns the current duty cycle phase and timing information, or `nil` when duty cycle is disabled.

### AmbientNoiseSensor.Config

Class to hold the configuration of the sensor.

#### Fields

+ `sensorObserver: AmbientNoiseSensorObserver?`: Callback for live data updates.
+ `activateAmbientNoiseSensor: Bool`: Enable decibel measurement. (default = `true`)
+ `activateAudioClassificationSensor: Bool`: Enable sound classification via SoundAnalysis. (default = `false`)
+ `audioClassifierModel: MLModel?`: Custom Core ML classifier. If provided directly, load it with `MLModelConfiguration.computeUnits = .cpuOnly` when background classification is required. (default = `nil`)
+ `audioClassifierModelURL: URL?`: Custom Core ML classifier URL. When this is set, the sensor loads the model with `audioClassifierComputeUnits`. (default = `nil`)
+ `audioClassifierComputeUnits: MLComputeUnits`: Compute units used when loading `audioClassifierModelURL`. Defaults to `.cpuOnly`.
+ `useBuiltInAudioClassifier: Bool`: Use the audio classification model built into iOS when no custom model is configured. This mode is foreground-only. (default = `true`)
+ `storeOnlyTopK: Int?`: If set, only the top-K classifications by confidence are stored per analysis window. (default = `nil` = store all)
+ `dutyCycleEnabled: Bool`: Enable duty cycle processing control while keeping microphone recording active. (default = `true`)
+ `activeDuration: TimeInterval`: Processing duration for each duty cycle active phase, in seconds. (default = `60`)
+ `restDuration: TimeInterval`: Pause duration for each duty cycle rest phase, in seconds. Audio capture continues during rest. (default = `60`)
+ `dutyCycleExtensionEnabled: Bool`: Allow detected audio events to extend the active phase of the duty cycle. (default = `false`)
+ `extensionLabels: [String]`: Audio classification labels that trigger a duty cycle extension (case-insensitive, substring match). (default = `["speech", "conversation"]`)
+ `extensionConfidenceThreshold: Double`: Minimum confidence score [0.0–1.0] required for a label to trigger an extension. (default = `0.5`)
+ `noiseLevelExtensionEnabled: Bool`: Allow high ambient noise levels to extend the active phase of the duty cycle. (default = `false`)
+ `noiseLevelThreshold: Double`: Decibel threshold (dBFS) above which the duty cycle active phase is extended. (default = `-30.0`)
+ `extensionDuration: TimeInterval`: Duration in seconds by which the active phase is extended when a trigger condition is met. (default = `60`)
+ `processingFailureNotificationsEnabled: Bool`: Post a local user notification when audio processing fails. Notifications are rate-limited to at most one per minute. (default = `false`)
+ `preferredInputUID: String`: UID of the preferred microphone input. Leave empty to use the system default.
+ `bufferSize: UInt32`: AVAudioEngine tap buffer size. (default = `16384`)
+ `onBus: Int`: Audio engine input bus. (default = `0`)
+ `enabled: Bool`: Sensor is enabled or not. (default = `false`)
+ `debug: Bool`: Enable/disable logging. (default = `false`)
+ `label: String`: Label for the data. (default = "")
+ `deviceId: String`: Id of the device associated with the events. (default = "")
+ `dbEncryptionKey`: Encryption key for the database. (default = `nil`)
+ `dbType: Engine`: Which db engine to use for saving data. (default = `Engine.DatabaseType.NONE`)
+ `dbPath: String`: Path of the database.
+ `dbHost: String`: Host for syncing the database. (default = `nil`)

### Audio classifier model policy

Audio label classification can use either a custom Core ML sound classifier or the audio classification model built into iOS.

The audio classification model built into iOS can work while the app is in the foreground, but it may submit Metal/GPU work internally. iOS does not permit background apps to submit GPU work, so this classifier can fail in the background with errors such as:

```text
IOGPUMetalError: Insufficient Permission (to submit GPU work from background)
CoreML prediction failed ... Failed to evaluate model ... in pipeline
```

For this reason, the sensor skips the audio classification model built into iOS while the app is not active. For background audio event detection, provide a custom classifier and load it with CPU-only compute units. This avoids the Metal background execution restriction, at the cost of higher CPU and battery usage.

## Broadcasts

### Fired Broadcasts

+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE`: fired when a new decibel measurement is recorded.
+ `AmbientNoiseSensor.ACTION_AWARE_AUDIO_LABEL`: fired when a new audio classification result is available.
+ `AmbientNoiseSensor.ACTION_AWARE_AUDIO_PROCESSING_ERROR`: fired when audio processing encounters an error. The error description is available in the `AmbientNoiseSensor.EXTRA_ERROR` field of the notification `userInfo`.

### Received Broadcasts

+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_START`: received broadcast to start the sensor.
+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_STOP`: received broadcast to stop the sensor.
+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_SYNC`: received broadcast to send sync attempt to the host.
+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_SET_LABEL`: received broadcast to set the data label. Label is expected in the `AmbientNoiseSensor.EXTRA_LABEL` field of the notification userInfo.

## Data Representations

### AmbientNoiseData

Contains the decibel measurement.

| Field     | Type   | Description                                                     |
| --------- | ------ | --------------------------------------------------------------- |
| db        | Double | Sound level in decibels (dBFS)                                  |
| label     | String | Customizable label. Useful for data calibration or traceability |
| deviceId  | String | AWARE device UUID                                               |
| timestamp | Int64  | Unixtime milliseconds since 1970                                |
| timezone  | Int    | Timezone of the device                                          |
| os        | String | Operating system of the device (iOS)                            |

### AudioLabelData

Contains a sound classification result.

| Field      | Type   | Description                                                     |
| ---------- | ------ | --------------------------------------------------------------- |
| audioLabel | String | Sound classification label (e.g., "music", "speech", "silence") |
| confidence | Double | Confidence score of the classification [0.0–1.0]                |
| label      | String | Customizable label. Useful for data calibration or traceability |
| deviceId   | String | AWARE device UUID                                               |
| timestamp  | Int64  | Unixtime milliseconds since 1970                                |
| timezone   | Int    | Timezone of the device                                          |
| os         | String | Operating system of the device (iOS)                            |

## Example usage

```swift
import com_awareframework_ios_sensor_ambientnoise
```

```swift
let sensor = AmbientNoiseSensor(AmbientNoiseSensor.Config().apply { config in
    config.sensorObserver = Observer()
    config.activateAmbientNoiseSensor = true
    config.activateAudioClassificationSensor = false
    config.audioClassifierModelURL = Bundle.main.url(
        forResource: "ConversationEventClassifier",
        withExtension: "mlmodelc"
    )
    config.audioClassifierComputeUnits = .cpuOnly
    config.storeOnlyTopK = 3
    config.debug = true
})

sensor.start()

// Later...
sensor.stop()
```

```swift
class Observer: AmbientNoiseSensorObserver {
    func onAmbientNoiseChanged(data: AmbientNoiseData) {
        print("Decibels:", data.db)
    }

    func onAudioLabelChanged(data: AudioLabelData) {
        print("Label:", data.audioLabel, "Confidence:", data.confidence)
    }
}
```

## Author
Yuuki Nishiyama (The University of Tokyo), nishiyama@csis.u-tokyo.ac.jp

## Related Links
* [Apple | SoundAnalysis](https://developer.apple.com/documentation/soundanalysis)
* [Apple | AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)

## License
Copyright (c) 2018 AWARE Mobile Context Instrumentation Middleware/Framework (http://www.awareframework.com)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
