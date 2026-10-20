ROOT := $(abspath ..)
.PHONY: test build ios-archive ios-export ios-upload ios-status ios-register ios-enable-testing
test:
	python3 ../scripts/test-ios-release.py
	swift test --package-path RouteCore
build:
	xcodebuild -project ClearMic.xcodeproj -scheme ClearMic-iOS -destination 'generic/platform=iOS Simulator' -configuration Debug -derivedDataPath ../build/ios-simulator CODE_SIGNING_ALLOWED=NO build
ios-archive:
	python3 ../scripts/ios-release.py archive
ios-export:
	python3 ../scripts/ios-release.py export
ios-upload:
	python3 ../scripts/ios-release.py upload
ios-status:
	python3 ../scripts/ios-release.py status
ios-register:
	python3 ../scripts/ios-release.py register
ios-enable-testing:
	python3 ../scripts/ios-release.py enable-testing
