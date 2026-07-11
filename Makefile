APP_NAME := CC Lights
EXECUTABLE := ClaudeCodeStatusLight
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
CLI_OUTPUT := $(DIST_DIR)/cc-lights
CLI_INSTALL_DIR := $(HOME)/bin
CLI_INSTALL_PATH := $(CLI_INSTALL_DIR)/cc-lights

.PHONY: build test run bundle dmg install install-cli clean

build:
	swift build

test:
	swift test

run:
	swift run $(EXECUTABLE)

bundle:
	swift build -c release
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)"
	mkdir -p "$(RESOURCES_DIR)"
	cp Resources/Info.plist "$(CONTENTS_DIR)/Info.plist"
	cp Resources/AppIcon.icns "$(RESOURCES_DIR)/AppIcon.icns"
	cp .build/release/$(EXECUTABLE) "$(MACOS_DIR)/$(EXECUTABLE)"
	if [ -f .build/release/cc-lights ]; then cp .build/release/cc-lights "$(CLI_OUTPUT)"; else cp .build/release/CCLights "$(CLI_OUTPUT)"; fi
	cp "$(CLI_OUTPUT)" "$(RESOURCES_DIR)/cc-lights"
	chmod +x "$(MACOS_DIR)/$(EXECUTABLE)" "$(CLI_OUTPUT)" "$(RESOURCES_DIR)/cc-lights"
	codesign --force --sign - "$(APP_DIR)"
	@echo "Signed $(APP_DIR) (ad-hoc)"
	@echo "Built $(APP_DIR)"
	@echo "Built $(CLI_OUTPUT)"

dmg: bundle
	./scripts/make-dmg.sh

install-cli: bundle
	mkdir -p "$(CLI_INSTALL_DIR)"
	cp "$(CLI_OUTPUT)" "$(CLI_INSTALL_PATH)"
	chmod +x "$(CLI_INSTALL_PATH)"
	@echo "Installed $(CLI_INSTALL_PATH)"

install: bundle install-cli
	cp -R "$(APP_DIR)" /Applications/
	@echo "Installed /Applications/$(APP_NAME).app"

clean:
	rm -rf .build "$(DIST_DIR)"
