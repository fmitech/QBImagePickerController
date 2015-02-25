Pod::Spec.new do |s|
  s.name             = "QBImagePickerController"
  s.version          = "3.1.1"
  s.summary          = "A clone of UIImagePickerController with multiple selection support and several extra features."
  s.homepage         = "https://github.com/fmitech/QBImagePickerController"
  s.license          = 'MIT'
  s.author           = { "fluidmedia" => "fluidmedia@gmail.com" }
  s.source           = { :git => "https://github.com/fmitech/QBImagePickerController.git", :tag => s.version.to_s }
  s.social_media_url = 'http://fluidmedia.ca'
  s.source_files     = 'Pod/Classes/*.{h,m}'
  s.resources        = 'Pod/Assets/*.lproj'
  s.platform         = :ios, '7.0'
  s.requires_arc     = true
  s.frameworks       = 'AssetsLibrary'
end
