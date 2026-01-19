# Unicorn Makefile

# Variables
APP_NAME = unicorn
BUILD_DIR = build
CONFIG = Release
# Actual built product path from xcodebuild output
APP_BUNDLE = $(PWD)/Library/Input Methods/$(CONFIG)/$(APP_NAME).app
INSTALL_DIR = $(HOME)/Library/Input Methods

.PHONY: all build install build-debug install-debug clean test lint format

all: build

# Build the project in Debug mode
build-debug:
	$(MAKE) build CONFIG=Debug

# Install the project in Debug mode
install-debug:
	$(MAKE) install CONFIG=Debug

# Run SwiftLint to check for code style issues
lint:
	swiftlint lint --strict

# Run SwiftLint to automatically fix code style issues
format:
	swiftlint --fix

# Build the project using xcodebuild
build:
	xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

# Install the Input Method to the user's Library
install: build
	pkill -f $(APP_NAME) || true
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app" || true
	cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	# Notify the system to look for new input methods (macOS specific)
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(INSTALL_DIR)/$(APP_NAME).app"
	sleep 1

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -rf "$(PWD)/Library/Input Methods"

# Run Engine tests
test:
	@echo "Running Engine Unit Tests..."
	@cat unicorn/KeyCode.swift > EngineTestsCombined.swift
	@echo "" >> EngineTestsCombined.swift
	@cat unicorn/Engine.swift >> EngineTestsCombined.swift
	@echo "" >> EngineTestsCombined.swift
	@cat unicornTests/EngineTests.swift >> EngineTestsCombined.swift
	@swift EngineTestsCombined.swift
	@rm EngineTestsCombined.swift