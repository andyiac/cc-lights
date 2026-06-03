APP_NAME := Claude Code Status Light
EXECUTABLE := ClaudeCodeStatusLight
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
CLI_OUTPUT := $(DIST_DIR)/cc-statusctl
CLI_INSTALL_DIR := $(HOME)/bin
CLI_INSTALL_PATH := $(CLI_INSTALL_DIR)/cc-statusctl

.PHONY: build test run bundle install install-cli clean

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
	cp Resources/Info.plist "$(CONTENTS_DIR)/Info.plist"
	cp .build/release/$(EXECUTABLE) "$(MACOS_DIR)/$(EXECUTABLE)"
	if [ -f .build/release/cc-statusctl ]; then cp .build/release/cc-statusctl "$(CLI_OUTPUT)"; else cp .build/release/CCStatusCtl "$(CLI_OUTPUT)"; fi
	chmod +x "$(MACOS_DIR)/$(EXECUTABLE)" "$(CLI_OUTPUT)"
	@echo "Built $(APP_DIR)"
	@echo "Built $(CLI_OUTPUT)"

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
