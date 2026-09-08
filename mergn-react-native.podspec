require 'json'
package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

# React Native autolinking finds this podspec automatically, so the client never
# edits their Podfile: `npm install` + `pod install` is enough.
Pod::Spec.new do |s|
  s.name         = 'mergn-react-native'
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = package['homepage']
  s.license      = { :type => 'Commercial' }
  s.author       = package['author']
  s.source       = { :git => 'https://mergn.com', :tag => s.version.to_s }

  # mergn_ios.xcframework is built for iOS 14 (see its .swiftinterface flags).
  # Setting it here means the client's Podfile inherits the floor automatically.
  s.platforms    = { :ios => '14.0' }
  s.swift_version = '5.0'

  s.source_files = 'ios/*.{h,m,mm,swift}'

  s.dependency 'MergnSDK', '~> 19.0'
  s.dependency 'React-Core'

  # The Mergn iOS SDK ships inside this package rather than being downloaded at
  # install time. That keeps `pod install` offline-safe and avoids depending on
  # CocoaPods' local-vs-remote pod semantics, which silently fail to link a
  # vendored framework fetched by prepare_command.
  #
  # vendored_frameworks is resolved relative to this podspec, so the framework
  # must stay in ios/ alongside it.
end
