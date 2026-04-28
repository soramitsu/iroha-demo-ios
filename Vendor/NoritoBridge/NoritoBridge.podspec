Pod::Spec.new do |s|
  s.name             = 'NoritoBridge'
  s.version          = '0.1.0'
  s.summary          = 'Binary bridge for encoding Iroha Norito transactions.'
  s.description      = 'Bundles the NoritoBridge.xcframework built from the iroha repo.'
  s.homepage         = 'https://github.com/hyperledger-iroha/iroha'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'Hyperledger Iroha' => 'info@soramitsu.co.jp' }
  s.platform         = :ios, '15.0'
  s.swift_version    = '6.0'
  s.vendored_frameworks = 'NoritoBridge.xcframework'
  s.source           = { :path => '.' }
end
