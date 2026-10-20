.PHONY: check build package dmg install run

check:
	swift build -Xswiftc -warnings-as-errors
	swift test

build:
	swift build -c release -Xswiftc -warnings-as-errors -Xswiftc -file-prefix-map -Xswiftc $(CURDIR)=.

package: build
	python3 Scripts/package.py

dmg:
	python3 Scripts/dmg.py

install: package
	./install.sh --skip-build

run: install
	open -a FokusBar
