APP_NAME := Claude Code Status Light
EXECUTABLE := ClaudeCodeStatusLight
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
CLI_OUTPUT := $(DIST_DIR)/cc-statusctl
CLI_INSTALL_DIR := $(HOME)/bin
CLI_INSTALL_PATH := $(CLI_INSTALL_DIR)/cc-statusctl
# 稳定的自签名身份：让 app 跨重装保持同一签名，从而保留 macOS 自动化(TCC)授权。
# 缺失时跳过签名（退回 ad-hoc，重装后需重新授权控制终端）。
CODESIGN_IDENTITY := cc-status-codesign

.PHONY: build test run bundle install install-cli codesign-cert clean

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
	@if security find-identity -p codesigning 2>/dev/null | grep -q "$(CODESIGN_IDENTITY)"; then \
		codesign --force --timestamp=none --sign "$(CODESIGN_IDENTITY)" "$(APP_DIR)" && \
		echo "Signed $(APP_DIR) with $(CODESIGN_IDENTITY)"; \
	else \
		echo "⚠️  未找到签名身份 $(CODESIGN_IDENTITY)，退回 ad-hoc（重装后需重新授权自动化）。"; \
	fi
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

# 一次性创建本地自签名代码签名证书（已存在则跳过）。
# 用于让 app 跨重装保持同一签名身份，从而保留 macOS 自动化(TCC)授权。
codesign-cert:
	@if security find-identity -p codesigning 2>/dev/null | grep -q "$(CODESIGN_IDENTITY)"; then \
		echo "签名身份 $(CODESIGN_IDENTITY) 已存在。"; \
	else \
		work=$$(mktemp -d); \
		openssl req -x509 -newkey rsa:2048 -keyout "$$work/key.pem" -out "$$work/cert.pem" -days 3650 -nodes \
			-subj "/CN=$(CODESIGN_IDENTITY)" \
			-addext "basicConstraints=critical,CA:false" \
			-addext "keyUsage=critical,digitalSignature" \
			-addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null; \
		openssl pkcs12 -export -legacy -inkey "$$work/key.pem" -in "$$work/cert.pem" \
			-out "$$work/cert.p12" -passout pass:temp123 -name "$(CODESIGN_IDENTITY)" 2>/dev/null; \
		security import "$$work/cert.p12" -k "$$HOME/Library/Keychains/login.keychain-db" -P "temp123" -T /usr/bin/codesign; \
		rm -rf "$$work"; \
		echo "已创建签名身份 $(CODESIGN_IDENTITY)。首次 codesign 时若弹钥匙串提示，点「始终允许」。"; \
	fi

clean:
	rm -rf .build "$(DIST_DIR)"
