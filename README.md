# AWARE: Ambient Noise

[![CI Status](https://img.shields.io/travis/awareframework/com.awareframework.ios.sensor.ambientnoise.svg?style=flat)](https://travis-ci.org/awareframework/com.awareframework.ios.sensor.ambientnoise)
[![Version](https://img.shields.io/cocoapods/v/com.awareframework.ios.sensor.ambientnoise.svg?style=flat)](https://cocoapods.org/pods/com.awareframework.ios.sensor.ambientnoise)
[![License](https://img.shields.io/cocoapods/l/com.awareframework.ios.sensor.ambientnoise.svg?style=flat)](https://cocoapods.org/pods/com.awareframework.ios.sensor.ambientnoise)
[![Platform](https://img.shields.io/cocoapods/p/com.awareframework.ios.sensor.ambientnoise.svg?style=flat)](https://cocoapods.org/pods/com.awareframework.ios.sensor.ambientnoise)

Ambient Noise sensor allows us to collect ambient noise information by each period using a phone's microphone. The data contains RMS, frequency (Hz), and decibels(dB). As an audio processing unit, this sensor uses [EZAudio](https://github.com/syedhali/EZAudio) which is an open-source audio sensing framework (MIT License).

## Requirements
iOS 10 or later

## Installation

com.aware.ios.sensor.ambientnoise is available through [CocoaPods](https://cocoapods.org). 

1. To install it, simply add the following line to your Podfile:
```ruby
pod 'com.awareframework.ios.sensor.ambientnoise'
```

2. com_aware_ios_sensor_ambientnoise  library into your source code.
```swift
import com_awareframework_ios_sensor_ambientnoise
```

3. Add `NSMicrophoneUsageDescription` into Info.plist

## Public functions

### AmbientNoiseSensor

+ `init(config:AmbientNoiseSensor.Config?)` : Initializes the ambient noise sensor with the optional configuration.
+ `start()`: Starts the ambient noise sensor with the optional configuration.
+ `stop()`: Stops the service.

### AmbientNoiseSensor.Config

Class to hold the configuration of the sensor.

#### Fields
+ `sensorObserver: AmbientNoiseObserver`: Callback for live data updates.
+ `interval: Int`: Sampling interval in minute. (default = 5) 
+ `samples: Int` : Data samples to collect per minute. (default = 30)
+ `silenceThreshold: Double`: A threshold of RMS for determining silence or not. (default = 50)
+ `enabled: Boolean` Sensor is enabled or not. (default = `false`)
+ `debug: Boolean` enable/disable logging to Xcode console. (default = `false`)
+ `label: String` Label for the data. (default = "")
+ `deviceId: String` Id of the device that will be associated with the events and the sensor. (default = "")
+ `dbEncryptionKey` Encryption key for the database. (default = `null`)
+ `dbType: Engine` Which db engine to use for saving data. (default = `Engine.DatabaseType.NONE`)
+ `dbPath: String` Path of the database. (default = "aware_gyroscope")
+ `dbHost: String` Host for syncing the database. (default = `null`)

## Broadcasts

### Fired Broadcasts

+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE` fired when ambient noise saved data to db after the period ends.

### Received Broadcasts

+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE_START`: received broadcast to start the sensor.
+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE_STOP`: received broadcast to stop the sensor.
+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE_SYNC`: received broadcast to send sync attempt to the host.
+ `AmbientNoiseSensor.ACTION_AWARE_AMBIENTNOISE_SET_LABEL`: received broadcast to set the data label. Label is expected in the `AmbientNoiseSensor.EXTRA_LABEL` field of the intent extras.

## Data Representations

### AmbientNoise Data

Contains the raw sensor data.

| Field     | Type   | Description                                                     |
| --------- | ------ | --------------------------------------------------------------- |
| frequency | Double  | Sound frequency in Hz   |
| decibels  | Double  | Sound decibels in dB    |
| rms       | Double  | Sound RMS                                              |
| isSilent  | Boolean | 0 = not silent 1 = is silent |
| silenceThreshold | Double | The used threshold when classifying between silent vs not silent |
| label     | String | Customizable label. Useful for data calibration or traceability |
| deviceId  | String | AWARE device UUID                                               |
| label     | String | Customizable label. Useful for data calibration or traceability |
| timestamp | Int64  | unixtime milliseconds since 1970                                |
| timezone  | Int    | Timezone of the device                          |
| os        | String | Operating system of the device (ex. ios)                    |


## Example usage
```swift
var sensor = AmbientNoiseSensor(AmbientNoiseSensor.Config().apply{config in
    config.debug = true
    config.dbType = .REALM
    config.sensorObserver = Observer()
})
sensor.start()
```
```swift
class Observer:AmbientNoiseObserver{
    func onAmbientNoiseChanged(data: AmbientNoiseData) {
        // code here..
    }
}
```

## Author

Yuuki Nishiyama, yuuki.nishiyama@oulu.fi

## Dependency Library
Audio sensing and processing modules are based on [EZAudio](https://github.com/syedhali/EZAudio) which is released by MIT License.

## License

Copyright (c) 2018 AWARE Mobile Context Instrumentation Middleware/Framework (http://www.awareframework.com)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

