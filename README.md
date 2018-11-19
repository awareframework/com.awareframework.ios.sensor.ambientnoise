# com.awareframework.ios.sensor.ambientnoise

[![CI Status](https://img.shields.io/travis/tetujin/com.awareframework.ios.sensor.ambientnoise.svg?style=flat)](https://travis-ci.org/tetujin/com.awareframework.ios.sensor.ambientnoise)
[![Version](https://img.shields.io/cocoapods/v/com.awareframework.ios.sensor.ambientnoise.svg?style=flat)](https://cocoapods.org/pods/com.awareframework.ios.sensor.ambientnoise)
[![License](https://img.shields.io/cocoapods/l/com.awareframework.ios.sensor.ambientnoise.svg?style=flat)](https://cocoapods.org/pods/com.awareframework.ios.sensor.ambientnoise)
[![Platform](https://img.shields.io/cocoapods/p/com.awareframework.ios.sensor.ambientnoise.svg?style=flat)](https://cocoapods.org/pods/com.awareframework.ios.sensor.ambientnoise)


## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

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

Yuuki Nishiyama, tetujin@ht.sfc.keio.ac.jp

## Dependency Library
Audio sensing and processing modules are based on EZAudio ( https://github.com/syedhali/EZAudio )  which are released by MIT License.

## License

Copyright (c) 2018 AWARE Mobile Context Instrumentation Middleware/Framework (http://www.awareframework.com)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

