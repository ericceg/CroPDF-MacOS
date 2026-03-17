APP_NAME := CroPDF
EXECUTABLE := CroPDFMacOS
CONFIGURATION ?= release
DIST_DIR := $(CURDIR)/dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
DMG_PATH := $(DIST_DIR)/$(APP_NAME).dmg
CREATE_DMG_VERSION ?= 8.0.0
APP_SIGN_IDENTITY ?= -

.PHONY: dmg clean

dmg:
	@set -euo pipefail; \
	swift build --disable-sandbox -c "$(CONFIGURATION)"; \
	BIN_DIR="$$(swift build --disable-sandbox -c "$(CONFIGURATION)" --show-bin-path)"; \
	rm -rf "$(APP_DIR)"; \
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"; \
	cp "$$BIN_DIR/$(EXECUTABLE)" "$(MACOS_DIR)/$(EXECUTABLE)"; \
	cp -R "$$BIN_DIR/$(EXECUTABLE)_$(EXECUTABLE).bundle" "$(RESOURCES_DIR)/$(EXECUTABLE)_$(EXECUTABLE).bundle"; \
	cp "$(CURDIR)/src/Resources/$(APP_NAME).icns" "$(RESOURCES_DIR)/$(APP_NAME).icns"; \
	cp "$(CURDIR)/scripts/Info.plist" "$(CONTENTS_DIR)/Info.plist"; \
	codesign --force --deep --sign "$(APP_SIGN_IDENTITY)" "$(APP_DIR)"; \
	codesign --verify --deep --strict --verbose=2 "$(APP_DIR)"; \
	rm -f "$(DMG_PATH)"; \
	npx --yes "create-dmg@$(CREATE_DMG_VERSION)" --overwrite --no-version-in-filename --no-code-sign "$(APP_DIR)" "$(DIST_DIR)"; \
	rm -rf "$(APP_DIR)"; \
	echo "Built $(DMG_PATH)"

clean:
	rm -rf "$(DIST_DIR)"
