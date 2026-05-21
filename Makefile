.PHONY: all build run clean

all: build

build:
	./script/build_and_run.sh --configuration release --build-only

run:
	./script/build_and_run.sh

clean:
	swift package clean
	rm -rf .build
	rm -rf dist
