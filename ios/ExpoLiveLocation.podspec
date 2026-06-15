require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'ExpoLiveLocation'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.platforms      = { :ios => '16.0' }
  s.swift_version  = '5.9'
  s.source         = { git: 'https://github.com/sanjay/expo-live-location.git', tag: "#{s.version}" }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    # The Kit is developed and unit-tested under Swift 6 strict concurrency
    # (see Package.swift); enforce the same checking in the app build so the
    # @unchecked Sendable / locking guarantees are verified where it ships.
    'SWIFT_STRICT_CONCURRENCY' => 'complete'
  }

  # The thin Expo adapter (this directory) plus the pure LiveLocationKit sources,
  # referenced in place rather than copied. There is exactly one canonical, unit-
  # tested copy of the core; the Kit keeps its own folder so the decoupling stays
  # visible in the project navigator.
  s.source_files = '*.{h,m,swift}', '../LiveLocationKit/Sources/LiveLocationKit/**/*.swift'
end
