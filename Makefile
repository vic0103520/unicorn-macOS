# Unicorn Makefile

# Variables
APP_NAME = unicorn
BUILD_DIR = build
CONFIG = Release
XCODEBUILD = xcodebuild$(if $(filter 1,$(VERBOSE)),, -quiet)
PASS_LABEL = $(if $(filter 1,$(NO_COLOR)),[PASS],\033[1;32m[PASS]\033[0m)
FAIL_LABEL = $(if $(filter 1,$(NO_COLOR)),[FAIL],\033[1;31m[FAIL]\033[0m)
RESULT_LABEL = $(if $(filter 1,$(NO_COLOR)),[RESULT],\033[1;36m[RESULT]\033[0m)
SYMROOT = $(CURDIR)/$(BUILD_DIR)
OBJROOT = $(SYMROOT)/obj
NATIVE_ARCH = $(shell uname -m)
OTHER_SUPPORTED_ARCH = $(if $(filter arm64,$(NATIVE_ARCH)),x86_64,arm64)
TEST_ROOT = $(SYMROOT)/Test
TEST_DERIVED_DATA = $(TEST_ROOT)/DerivedData
TEST_RESULT_BUNDLE = $(TEST_ROOT)/Results/UnicornCoreTests.xcresult
ARCH_VALIDATION_DERIVED_DATA = $(TEST_ROOT)/OtherArchitectureDerivedData
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
	@if $(XCODEBUILD) -project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration $(CONFIG) \
		-destination 'platform=macOS' \
		SYMROOT=$(SYMROOT) \
		OBJROOT=$(OBJROOT) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES; then \
		printf '%b\n' "$(PASS_LABEL) App build: configuration=$(CONFIG) path=$(APP_BUNDLE)"; \
	else \
		status=$$?; \
		printf '%b\n' "$(FAIL_LABEL) App build: configuration=$(CONFIG) exit=$$status"; \
		exit "$$status"; \
	fi

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

# Run hostless core tests on the current architecture, then cross-compile the app.
test:
	@echo "Running UnicornCore tests on $(NATIVE_ARCH)..."
	@rm -rf "$(TEST_ROOT)"
	@if $(XCODEBUILD) clean test \
		-project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination 'platform=macOS,arch=$(NATIVE_ARCH)' \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		-resultBundlePath "$(TEST_RESULT_BUNDLE)" \
		-enableCodeCoverage YES \
		SYMROOT="$(TEST_ROOT)/BuildProducts" \
		OBJROOT="$(TEST_ROOT)/Intermediates" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES; then \
		:; \
	else \
		status=$$?; \
		printf '%b\n' "$(FAIL_LABEL) Tests: arch=$(NATIVE_ARCH) exit=$$status"; \
		exit "$$status"; \
	fi
	@summary_file="$$(mktemp)" || { printf '%b\n' "$(FAIL_LABEL) Test summary: unable to create temporary file"; exit 1; }; \
	trap 'rm -f "$$summary_file"' EXIT; \
	if xcrun xcresulttool get test-results summary --path "$(TEST_RESULT_BUNDLE)" > "$$summary_file" && \
		result="$$(/usr/bin/plutil -extract result raw -o - "$$summary_file")" && \
		passed="$$(/usr/bin/plutil -extract passedTests raw -o - "$$summary_file")" && \
		failed="$$(/usr/bin/plutil -extract failedTests raw -o - "$$summary_file")" && \
		skipped="$$(/usr/bin/plutil -extract skippedTests raw -o - "$$summary_file")"; then \
		if [ "$$result" = "Passed" ] && [ "$$failed" -eq 0 ]; then \
			printf '%b\n' "$(PASS_LABEL) Tests: result=$$result passed=$$passed failed=$$failed skipped=$$skipped"; \
		else \
			printf '%b\n' "$(FAIL_LABEL) Tests: result=$$result passed=$$passed failed=$$failed skipped=$$skipped"; \
			exit 1; \
		fi; \
	else \
		status=$$?; \
		printf '%b\n' "$(FAIL_LABEL) Test summary: xcresult=$(TEST_RESULT_BUNDLE) exit=$$status"; \
		exit "$$status"; \
	fi
	@printf '%b\n' "$(RESULT_LABEL) xcresult: path=$(TEST_RESULT_BUNDLE)"
	@echo "Cross-compiling unicorn.app for $(OTHER_SUPPORTED_ARCH) (compile validation only)..."
	@if $(XCODEBUILD) clean build \
		-project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination 'generic/platform=macOS' \
		-derivedDataPath "$(ARCH_VALIDATION_DERIVED_DATA)" \
		SYMROOT="$(TEST_ROOT)/OtherArchitectureBuildProducts" \
		OBJROOT="$(TEST_ROOT)/OtherArchitectureIntermediates" \
		ARCHS=$(OTHER_SUPPORTED_ARCH) \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES; then \
		printf '%b\n' "$(PASS_LABEL) Cross-architecture build: arch=$(OTHER_SUPPORTED_ARCH)"; \
	else \
		status=$$?; \
		printf '%b\n' "$(FAIL_LABEL) Cross-architecture build: arch=$(OTHER_SUPPORTED_ARCH) exit=$$status"; \
		exit "$$status"; \
	fi

# Produce a readable coverage report from the standard test result bundle.
coverage: test
	@echo "UnicornCore coverage from $(TEST_RESULT_BUNDLE):"
	xcrun xccov view --report --only-targets "$(TEST_RESULT_BUNDLE)"
