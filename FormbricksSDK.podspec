Pod::Spec.new do |s|
  s.name             = "FormbricksSDK"
  s.version          = "1.1.0"                              
  s.summary          = "iOS SDK for Formbricks" 
  s.homepage         = "https://github.com/formbricks/ios"   
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Formbricks" => "hola@formbricks.com" }
  s.platform         = :ios, "16.6"
  s.source           = { :git => "https://github.com/formbricks/ios.git", :tag => s.version }
  s.swift_version    = "5.7"                                
  s.requires_arc     = true
  s.source_files     = "Sources/FormbricksSDK/**/*.{swift}"
end
