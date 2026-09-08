# The Mergn iOS SDK, as its own pod.
#
# This lives in a directory containing ONLY the podspec and the framework, which
# matters twice over:
#   - CocoaPods resolves vendored_frameworks relative to the podspec and
#     silently ignores paths that escape it
#   - `pod 'MergnSDK', :path => '<dir>'` matches the podspec filename to the pod
#     name, so a second podspec in the same directory breaks resolution
#
# Declared as a separate pod rather than folded into mergn-react-native.podspec
# because a vendored framework on an autolinked pod does not produce link flags
# (the app builds without -framework "mergn_ios" and then fails with
# "Unable to resolve module dependency: 'mergn_ios'").
Pod::Spec.new do |s|
  s.name         = 'MergnSDK'
  s.version      = '19.0.0'
  s.summary      = 'Mergn iOS SDK (binary distribution)'
  s.description  = 'Closed-source Mergn iOS SDK, vendored as an xcframework.'
  s.homepage     = 'https://mergn.com'
  s.license      = { :type => 'Commercial' }
  s.author       = 'Mergn'
  s.source       = { :path => '.' }

  # Must match the framework's own minimum (see its .swiftinterface flags).
  s.platforms    = { :ios => '14.0' }

  s.vendored_frameworks = 'mergn_ios.xcframework'
end
