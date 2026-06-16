require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

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

  # This podspec sits at the package root so its pod root spans both halves of the
  # module: the thin Expo adapter in ios/, and the pure core from the standalone
  # LiveLocationKit package (the same sources swift test runs). One canonical copy,
  # compiled into one module, nothing to keep in sync. CocoaPods only globs files
  # under the podspec's own directory, which is why this lives here and not in ios/.
  s.source_files = 'ios/*.{h,m,swift}', 'LiveLocationKit/Sources/LiveLocationKit/**/*.swift'
end
