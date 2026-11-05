.PHONY: build test app run install selftest neural-voice clean

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

neural-voice:
	@scripts/fetch-neural-voice.sh

selftest: app
	@build/Readout.app/Contents/MacOS/Readout --self-test

clean:
	rm -rf .build build
