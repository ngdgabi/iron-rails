XCODEBUILD=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild

.PHONY: all macos ios release run clean

all: release

macos:
	$(XCODEBUILD) -project IronRails.xcodeproj -scheme IronRails -configuration Release -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build

ios:
	$(XCODEBUILD) -project IronRails.xcodeproj -scheme IronRailsMobile -configuration Release -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build

release:
	chmod +x package_release.sh
	./package_release.sh

run: release
	open "dist/Iron Rails.app"

clean:
	rm -rf build/universal_pkg build/DerivedData
