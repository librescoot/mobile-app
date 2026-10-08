Pod::Spec.new do |s|
  s.name             = 'wearable_bridge'
  s.version          = '0.1.0'
  s.summary          = 'Wearable companion transport.'
  s.description      = 'Bounded WatchConnectivity commands for the scooter app.'
  s.homepage         = 'https://github.com/librescoot/mobile-app'
  s.license          = { :type => 'CC-BY-NC-SA-4.0' }
  s.author           = { 'Librescoot' => '' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.swift_version = '5.0'
  s.frameworks = 'WatchConnectivity'
end
