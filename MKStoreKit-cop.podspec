Pod::Spec.new do |s|
  s.name     = 'MKStoreKit-cop'
  s.version  = '4.99'
  s.license  = { :type => 'MIT',
                 :text => 'MKStoreKit uses MIT Licensing And so all of my source code can
                           be used royalty-free into your app. Just make sure that you don’t
                           remove the copyright notice from the source code if you make your
                           app open source and in the about page.' }
  s.summary  = 'In-App Purchases StoreKit for iOS devices.'
  s.homepage = 'https://github.com/Coppertino/MKStoreKit'
  s.author   = { 'Mugunth Kumar' => 'mugunth@steinlogic.com' }
  s.source   = { :git => 'https://github.com/Coppertino/MKStoreKit.git', :branch => "master" }
  s.platform = :osx, '10.7'
  s.source_files = '*.{h,m}', 'Externals/*.{h,m}'
  s.requires_arc = true

  s.frameworks = 'StoreKit', 'Security'
  s.dependency 'SSKeychain'
  s.dependency 'AFNetworking'

  def s.post_install(target) 
    puts <<-TEXT
      * MKStoreKit note *
          Don't forget to create and add MKStoreKitConfigs.plist file to you project.
          You can find an example here: https://github.com/Coppertino/MKStoreKit/blob/22223c77962179497038322b94d01277506570cc/MKStoreKitConfigs.plist
    TEXT
  end
end

