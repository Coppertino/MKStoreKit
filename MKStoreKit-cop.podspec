Pod::Spec.new do |s|
  s.name     = 'MKStoreKit-cop'
  s.version  = '5.1.3'
  s.license  = { :type => 'MIT',
                 :text => 'MKStoreKit uses MIT Licensing And so all of my source code can
                           be used royalty-free into your app. Just make sure that you don’t
                           remove the copyright notice from the source code if you make your
                           app open source and in the about page.' }
  s.summary  = 'In-App Purchases StoreKit for iOS devices.'
  s.homepage = 'https://github.com/Coppertino/MKStoreKit'
  s.author   = { 'Mugunth Kumar' => 'mugunth@steinlogic.com' }
  s.source   = { :git => 'https://github.com/Coppertino/MKStoreKit.git', :tag => "5.1.3" }
  
  s.platform = :osx, '10.8'
  s.source_files = '*.{h,m}', 'Externals/*.{h,m}'
  s.requires_arc = true

  s.frameworks = 'StoreKit', 'Security', 'IOKit', 'SystemConfiguration'
  s.dependency 'SSKeychain'
  s.dependency 'AFNetworking', '1.3.3'

end

