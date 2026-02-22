# Unicorn Makefile

# Variables
APP_NAME = unicorn
BUILD_DIR = build
CONFIG = Release
SYMROOT = $(CURDIR)/$(BUILD_DIR)
OBJROOT = $(SYMROOT)/obj
# Actual built product path from xcodebuild output
APP_BUNDLE = $(SYMROOT)/$(CONFIG)/$(APP_NAME).app
INSTALL_DIR = $(HOME)/Library/Input Methods

# Automatically detect the GitHub repository name (e.g., owner/repo)
GITHUB_REPO = $(shell git remote get-url origin 2>/dev/null | sed -E 's/.*github.com[:/](.*)(\.git)?/\1/' | sed 's/\.git$$//')

.PHONY: all build install build-debug install-debug clean test lint format coverage test-release clean-test-releases

all: build

# --- Release Management Helpers ---

# Internal helper to wipe a release and tag (usage: make _wipe_release TAG=v0.1.2)
_wipe_release:
	@echo "Wiping release and tag: $(TAG)"
	-gh release delete $(TAG) --yes --repo $(GITHUB_REPO) 2>/dev/null || true
	-git push origin :refs/tags/$(TAG) 2>/dev/null || true
	-git tag -d $(TAG) 2>/dev/null || true

# Public: Trigger a release (usage: make release TAG=v0.1.2)
# Automatically cleans up test releases first to save resources
release:
	@if [ -z "$(TAG)" ]; then echo "Error: TAG is required. Usage: make release TAG=v0.1.2"; exit 1; fi
	-$(MAKE) clean-test-releases
	@echo "Triggering release with tag: $(TAG)"
	git tag $(TAG)
	git push origin $(TAG)

# Public: Test release with a unique timestamped tag
TEST_TAG = test-$(shell date +%Y%m%d%H%M%S)
test-release:
	$(MAKE) release TAG=$(TEST_TAG)
	@echo "Done. Monitor progress on GitHub Actions."

# Public: Clean up all local and remote test tags and releases
clean-test-releases:
	@echo "Cleaning up all test-* tags and releases..."
	@for tag in $$(git tag -l "test-*"); do \
		$(MAKE) _wipe_release TAG=$$tag; \
	done
	@echo "Cleanup complete."

# Public: Re-release a version (usage: make re-release TAG=v0.1.2)
re-release:
	@if [ -z "$(TAG)" ]; then echo "Error: TAG is required. Usage: make re-release TAG=v0.1.2"; exit 1; fi
	$(MAKE) _wipe_release TAG=$(TAG)
	$(MAKE) release TAG=$(TAG)
	@echo "Re-release of $(TAG) triggered. Monitor progress on GitHub Actions."

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
		-destination 'platform=macOS' \
		SYMROOT=$(SYMROOT) \
		OBJROOT=$(OBJROOT) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES

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

# Run Engine tests
test:
	@echo "Running Engine Unit Tests..."
	@cat unicorn/FunctionalHelpers.swift > EngineTestsCombined.swift
	@echo "" >> EngineTestsCombined.swift
	@cat unicorn/KeyCode.swift >> EngineTestsCombined.swift
	@echo "" >> EngineTestsCombined.swift
	@cat unicorn/Trie.swift >> EngineTestsCombined.swift
	@echo "" >> EngineTestsCombined.swift
	@cat unicorn/EngineTypes.swift >> EngineTestsCombined.swift
	@echo "" >> EngineTestsCombined.swift
	@cat unicorn/Engine.swift >> EngineTestsCombined.swift
	@echo "" >> EngineTestsCombined.swift
	@cat unicornTests/EngineTests.swift >> EngineTestsCombined.swift
	@swift EngineTestsCombined.swift
	@rm EngineTestsCombined.swift

# Check test coverage
coverage:
	@echo "Generating Test Coverage Report..."
	@(cat unicorn/FunctionalHelpers.swift; echo ""; cat unicorn/KeyCode.swift; echo ""; cat unicorn/Trie.swift; echo ""; cat unicorn/EngineTypes.swift; echo ""; cat unicorn/Engine.swift; echo ""; cat unicornTests/EngineTests.swift) > CoverageCombined.swift
	@swiftc -profile-generate -profile-coverage-mapping CoverageCombined.swift -o CoverageRunner
	@./CoverageRunner > /dev/null
	@xcrun llvm-profdata merge -sparse default.profraw -o default.profdata
	@xcrun llvm-cov report ./CoverageRunner -instr-profile=default.profdata
	@rm CoverageCombined.swift CoverageRunner default.profraw default.profdata
