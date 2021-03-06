#
# Be sure to run `pod lib lint com.awareframework.ios.sensor.ambientnoise.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
s.name             = 'com.awareframework.ios.sensor.ambientnoise'
  s.version       = '0.4.1'
s.summary          = 'An Ambient Noise Sensor Module for AWARE Framework'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

s.description      = <<-DESC
Ambient Noise sensor allows us to collect ambient noise information by each period using a phone's microphone. The data contains RMS, frequency (Hz), and decibels(dB). As an audio processing unit, this sensor uses [EZAudio](https://github.com/syedhali/EZAudio) which is an open-source audio sensing framework (MIT License).
DESC

s.homepage         = 'https://github.com/awareframework/com.awareframework.ios.sensor.ambientnoise'
# s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
s.license          = { :type => 'Apache2', :file => 'LICENSE' }
s.author           = { 'tetujin' => 'tetujin@ht.sfc.keio.ac.jp' }
s.source           = { :git => 'https://github.com/awareframework/com.awareframework.ios.sensor.ambientnoise.git', :tag => s.version.to_s }
# s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

s.ios.deployment_target = '10.0'

s.swift_version = '4.2'

s.source_files = 'com.awareframework.ios.sensor.ambientnoise/Classes/**/*'

# s.resource_bundles = {
#   'com.awareframework.ios.sensor.ambientnoise' => ['com.awareframework.ios.sensor.ambientnoise/Assets/*.png']
# }

### for AudioKit (https://blog.cocoapods.org/CocoaPods-1.4.0/)
# s.static_framework = true

s.public_header_files = 'com.awareframework.ios.sensor.ambientnoise/Classes/**/*.h'
# s.frameworks = 'UIKit', 'MapKit'
# s.dependency 'AFNetworking', '~> 2.3'
s.dependency 'com.awareframework.ios.sensor.core', '~>0.4.1'

end
