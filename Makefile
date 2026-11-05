.PHONY: build test app run install release selftest neural-voice icon clean

build:
	@scripts/swift.sh build

test:
	@scripts/swift.sh test

app:
	@scripts/build-app.sh

run: app
	@open build/Readout.app

install:
	@scripts/build-app.sh --install

release:
	@scripts/release.sh

icon:
	@swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

neural-voice:
	@scripts/fetch-neural-voice.sh

selftest: app
	@build/Readout.app/Contents/MacOS/Readout --self-test

clean:
	rm -rf .build build dist
