require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = 'RSPlayer'
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = 'https://github.com/Platinum-Web-Studio/react-native-rsplayer'
  s.license      = package['license']
  s.authors      = { 'Visionaria' => 'hello@visionariaapp.com' }
  s.platforms    = { :ios => '15.1' }
  s.source       = { :git => 'https://github.com/Platinum-Web-Studio/react-native-rsplayer.git', :tag => "#{s.version}" }
  s.source_files = 'ios/**/*.{h,m,mm,swift}'
  s.dependency 'React-Core'
end
