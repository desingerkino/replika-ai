Pod::Spec.new do |s|
  s.name             = 'replika_recorder'
  s.version          = '0.1.0'
  s.summary          = 'Screen recording of a call and saving to Photos.'
  s.description      = 'ReplayKit screen recording and saving the video to the Photos library.'
  s.homepage         = 'https://example.invalid'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Replika' => 'noreply@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'ReplayKit', 'Photos'
end
