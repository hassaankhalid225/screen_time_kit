#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint screen_time_kit.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'screen_time_kit'
  s.version          = '0.1.0'
  s.summary          = 'Unified screen time, app usage, and app-limit API for Flutter.'
  s.description      = <<-DESC
One Dart API for screen time, app usage, and app limits on Android and iOS.
The iOS implementation is backed by FamilyControls, DeviceActivity, and
ManagedSettings and requires the Family Controls capability. See the README for
the required Xcode capability and App Store distribution entitlement steps.
                       DESC
  s.homepage         = 'https://github.com/hassaan/screen_time_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hassaan' => 'ghthtghfhf@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'

  # Family Controls / DeviceActivity / ManagedSettings require iOS 16.0+.
  s.platform = :ios, '16.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'screen_time_kit_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
