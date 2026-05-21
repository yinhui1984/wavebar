.PHONY: all build run install clean

all: build

build:
	./script/build_and_run.sh --configuration release --build-only

run:
	./script/build_and_run.sh

install:
	./script/build_and_run.sh --configuration release --build-only
	rm -rf /Applications/Wavebar.app
	cp -R dist/Wavebar.app /Applications/Wavebar.app

clean:
	swift package clean
	rm -rf .build
	rm -rf dist
