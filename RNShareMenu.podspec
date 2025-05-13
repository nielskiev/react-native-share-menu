require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RNShareMenu"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "12.0" }
#   s.source       = { :git => "https://github.com/nielskiev/react-native-share-menu.git", :tag  => "#{s.version}" }
  s.source = {
    :git    => "https://github.com/nielskiev/react-native-share-menu.git",
    :branch => "master"
  }
  s.swift_version = "5.2"


  s.exclude_files = [
    "ios/ShareViewController.swift",
    "ios/ReactShareViewController.swift"
  ]

  s.source_files = "ios/**/*.{h,m,mm,swift}"
#   s.dependency "React"

  s.dependency 'React-Core'
  s.dependency 'React-RCTBridge'
  s.dependency 'React-RCTEventEmitter'
  s.dependency 'React-RCTLinking'

#   s.dependency "React-Core"
#   s.dependency "React-RCTBridge"
#   s.dependency "React-RCTEventEmitter"
end
