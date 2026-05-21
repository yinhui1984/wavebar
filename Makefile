.PHONY: all build run clean

all: build

build:
	swift build -c release

run:
	swift run

clean:
	swift package clean
	rm -rf .build
