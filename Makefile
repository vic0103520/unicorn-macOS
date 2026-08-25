# Unicorn Makefile

# Variables
APP_NAME = unicorn
XCODE_PROJECT ?= $(APP_NAME).xcodeproj
XCODE_SCHEME ?= $(APP_NAME)
BUILD_DIR ?= build
CONFIG ?= Release
ARCHS ?= arm64 x86_64
VERBOSE ?= 0
NO_COLOR ?= 0
MARKETING_VERSION ?=
BUILD_NUMBER ?=
DIST_DIR ?= dist

XCODEBUILD ?= xcodebuild
XCODEBUILD_FLAGS = $(if $(filter 1,$(VERBOSE)),,-quiet)
XCODEBUILD_COMMAND = $(strip $(XCODEBUILD) $(XCODEBUILD_FLAGS))
XCODE_PROJECT_ARGS = -project "$(XCODE_PROJECT)" -scheme "$(XCODE_SCHEME)"
XCODE_SIGNING_ARGS = \
	CODE_SIGN_IDENTITY="-" \
	CODE_SIGNING_REQUIRED=YES \
	CODE_SIGNING_ALLOWED=YES
XCODE_VERSION_ARGS = \
	$(if $(MARKETING_VERSION),MARKETING_VERSION="$(MARKETING_VERSION)") \
	$(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)")

PASS_LABEL = $(if $(filter 1,$(NO_COLOR)),[PASS],\033[1;32m[PASS]\033[0m)
FAIL_LABEL = $(if $(filter 1,$(NO_COLOR)),[FAIL],\033[1;31m[FAIL]\033[0m)
RESULT_LABEL = $(if $(filter 1,$(NO_COLOR)),[RESULT],\033[1;36m[RESULT]\033[0m)

SYMROOT ?= $(abspath $(BUILD_DIR))
OBJROOT ?= $(SYMROOT)/obj
NATIVE_ARCH ?= $(shell uname -m)
TEST_ROOT ?= $(SYMROOT)/Test
TEST_DERIVED_DATA ?= $(TEST_ROOT)/DerivedData
TEST_RESULT_BUNDLE ?= $(TEST_ROOT)/Results/UnicornCoreTests.xcresult
TEST_APP_SYMROOT ?= $(TEST_ROOT)/UniversalBuildProducts
TEST_APP_OBJROOT ?= $(TEST_ROOT)/UniversalBuildIntermediates
APP_BUNDLE ?= $(SYMROOT)/$(CONFIG)/$(APP_NAME).app
APP_EXECUTABLE ?= $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
INSTALL_DIR ?= $(HOME)/Library/Input Methods

# Automatically detect the GitHub repository name (e.g., owner/repo)
GITHUB_REPO = $(shell git remote get-url origin 2>/dev/null | sed -E 's/.*github.com[:/](.*)(\.git)?/\1/' | sed 's/\.git$$//')

.PHONY: all build build-universal build-debug install install-debug clean
.PHONY: test test-native test-summary test-scripts coverage coverage-report lint format
.PHONY: release-artifacts verify-release-artifacts
.PHONY: release test-release clean-test-releases _push_release_tag _wipe_test_release

all: build

# --- Release Management Helpers ---

# Internal: Push one new, validated release tag. Existing tag names are never reused.
_push_release_tag:
	@if [ -z "$(TAG)" ]; then echo "Error: TAG is required"; exit 1; fi
	@./scripts/release-version.sh "$(TAG)" >/dev/null
	@if git show-ref --verify --quiet "refs/tags/$(TAG)"; then \
		echo "Error: local tag already exists and will not be reused: $(TAG)"; exit 1; \
	fi
	@if git ls-remote --exit-code --tags origin "refs/tags/$(TAG)" >/dev/null 2>&1; then \
		echo "Error: remote tag already exists and will not be reused: $(TAG)"; exit 1; \
	else \
		status=$$?; [ "$$status" -eq 2 ] || { echo "Error: unable to check remote tag $(TAG)"; exit "$$status"; }; \
	fi
	git tag "$(TAG)"
	git push origin "refs/tags/$(TAG)"
	@echo "Release workflow triggered for new tag: $(TAG)"

# Public: Trigger a production release (usage: make release TAG=v0.1.3).
release:
	@case "$(TAG)" in v*) ;; *) echo "Error: production TAG must start with v"; exit 1 ;; esac
	+@$(MAKE) --no-print-directory _push_release_tag TAG="$(TAG)"

# Public: Trigger an unpublished test draft for a marketing version.
TEST_TAG = test-v$(VERSION)-$(shell date -u +%Y%m%d%H%M%S)
test-release:
	@if [ -z "$(VERSION)" ]; then echo "Error: VERSION is required. Usage: make test-release VERSION=0.1.3"; exit 1; fi
	+@$(MAKE) --no-print-directory _push_release_tag TAG="$(TEST_TAG)"

# Internal: Remove only an unpublished test release and its test tag.
_wipe_test_release:
	@case "$(TAG)" in test-v*) ;; *) echo "Error: refusing to remove non-test tag: $(TAG)"; exit 1 ;; esac
	@./scripts/release-version.sh "$(TAG)" >/dev/null
	@error_file="$$(mktemp)" || exit 1; \
	if is_draft="$$(gh api "/repos/$(GITHUB_REPO)/releases/tags/$(TAG)" --jq .draft 2>"$$error_file")"; then \
		[ "$$is_draft" = true ] || { echo "Error: refusing to delete a published test release"; rm -f "$$error_file"; exit 1; }; \
		gh release delete "$(TAG)" --yes --repo "$(GITHUB_REPO)" || { rm -f "$$error_file"; exit 1; }; \
	elif ! grep -Fq '(HTTP 404)' "$$error_file"; then \
		cat "$$error_file" >&2; rm -f "$$error_file"; exit 1; \
	fi; \
	rm -f "$$error_file"
	@if git ls-remote --exit-code --tags origin "refs/tags/$(TAG)" >/dev/null 2>&1; then \
		git push origin ":refs/tags/$(TAG)"; \
	else \
		status=$$?; [ "$$status" -eq 2 ] || { echo "Error: unable to check remote test tag $(TAG)"; exit "$$status"; }; \
	fi
	@if git show-ref --verify --quiet "refs/tags/$(TAG)"; then git tag -d "$(TAG)"; fi
	@echo "Test release and tag are absent: $(TAG)"

# Public: Clean local unpublished test releases. Remote cleanup occurs for those tags.
clean-test-releases:
	@for tag in $$(git tag -l 'test-v*'); do \
		$(MAKE) --no-print-directory _wipe_test_release TAG="$$tag" || exit $$?; \
	done
	@echo "Test release cleanup complete."

release-artifacts: build
	@if [ -z "$(TAG)" ] || [ -z "$(BUILD_NUMBER)" ]; then \
		echo "Error: TAG and BUILD_NUMBER are required"; exit 1; \
	fi
	./scripts/package-release.sh "$(TAG)" "$(BUILD_NUMBER)" "$(APP_BUNDLE)" "$(DIST_DIR)"

verify-release-artifacts:
	@if [ -z "$(TAG)" ] || [ -z "$(BUILD_NUMBER)" ]; then \
		echo "Error: TAG and BUILD_NUMBER are required"; exit 1; \
	fi
	./scripts/verify-release.sh "$(TAG)" "$(BUILD_NUMBER)" "$(DIST_DIR)"

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

build: build-universal

build-universal:
	@if $(XCODEBUILD_COMMAND) $(XCODE_PROJECT_ARGS) \
		-configuration "$(CONFIG)" \
		-destination 'generic/platform=macOS' \
		SYMROOT="$(SYMROOT)" \
		OBJROOT="$(OBJROOT)" \
		ARCHS="$(ARCHS)" \
		ONLY_ACTIVE_ARCH=NO \
		$(XCODE_SIGNING_ARGS) \
		$(XCODE_VERSION_ARGS); then \
		:; \
	else \
		status=$$?; \
		printf '%b%s\n' "$(FAIL_LABEL)" " App build: configuration=$(CONFIG) archs=$(ARCHS) exit=$$status"; \
		exit "$$status"; \
	fi
	@if /usr/bin/lipo "$(APP_EXECUTABLE)" -verify_arch $(ARCHS); then \
		printf '%b%s\n' "$(PASS_LABEL)" " App build: configuration=$(CONFIG) archs=$(ARCHS) path=$(APP_BUNDLE)"; \
	else \
		status=$$?; \
		printf '%b%s\n' "$(FAIL_LABEL)" " App architecture verification: archs=$(ARCHS) path=$(APP_EXECUTABLE) exit=$$status"; \
		exit "$$status"; \
	fi

# Install a source build through the same transactional installer as a release.
install: build
	@work_dir="$$(mktemp -d "$${TMPDIR:-/tmp}/unicorn-source-install.XXXXXX")" || exit 1; \
	trap 'rm -rf "$$work_dir"' EXIT HUP INT TERM; \
	version="$$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$(APP_BUNDLE)/Contents/Info.plist")"; \
	build_number="$$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$(APP_BUNDLE)/Contents/Info.plist")"; \
	./scripts/package-release.sh "test-v$$version-$$build_number" "$$build_number" "$(APP_BUNDLE)" "$$work_dir/assets"; \
	/usr/bin/unzip -q "$$work_dir/assets/unicorn-macos.zip" -d "$$work_dir/distribution"; \
	UNICORN_ASSUME_YES=1 UNICORN_INSTALL_DIR="$(INSTALL_DIR)" /bin/sh "$$work_dir/distribution/install.sh"

# Clean build artifacts
clean:
	rm -rf "$(BUILD_DIR)"

test: test-scripts test-native
	+@$(MAKE) --no-print-directory build-universal \
		CONFIG=Debug \
		ARCHS="$(ARCHS)" \
		SYMROOT="$(TEST_APP_SYMROOT)" \
		OBJROOT="$(TEST_APP_OBJROOT)"

test-scripts:
	@./tests/release-scripts-tests.sh
	@./tests/installer-tests.sh

test-native:
	@echo "Running UnicornCore tests on $(NATIVE_ARCH)..."
	@rm -rf "$(TEST_ROOT)"
	@if $(XCODEBUILD_COMMAND) clean test $(XCODE_PROJECT_ARGS) \
		-configuration Debug \
		-destination 'platform=macOS,arch=$(NATIVE_ARCH)' \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		-resultBundlePath "$(TEST_RESULT_BUNDLE)" \
		-enableCodeCoverage YES \
		SYMROOT="$(TEST_ROOT)/BuildProducts" \
		OBJROOT="$(TEST_ROOT)/Intermediates" \
		$(XCODE_SIGNING_ARGS); then \
		:; \
	else \
		status=$$?; \
		printf '%b%s\n' "$(FAIL_LABEL)" " Native tests: arch=$(NATIVE_ARCH) exit=$$status"; \
		exit "$$status"; \
	fi
	+@$(MAKE) --no-print-directory test-summary

test-summary:
	@summary_file="$$(mktemp)" || { printf '%b%s\n' "$(FAIL_LABEL)" " Test summary: unable to create temporary file"; exit 1; }; \
	trap 'rm -f "$$summary_file"' EXIT; \
	if xcrun xcresulttool get test-results summary --path "$(TEST_RESULT_BUNDLE)" > "$$summary_file" && \
		result="$$(/usr/bin/plutil -extract result raw -o - "$$summary_file")" && \
		passed="$$(/usr/bin/plutil -extract passedTests raw -o - "$$summary_file")" && \
		failed="$$(/usr/bin/plutil -extract failedTests raw -o - "$$summary_file")" && \
		skipped="$$(/usr/bin/plutil -extract skippedTests raw -o - "$$summary_file")"; then \
		if [ "$$result" = "Passed" ] && [ "$$failed" -eq 0 ]; then \
			printf '%b%s\n' "$(PASS_LABEL)" " Tests: result=$$result passed=$$passed failed=$$failed skipped=$$skipped"; \
		else \
			printf '%b%s\n' "$(FAIL_LABEL)" " Tests: result=$$result passed=$$passed failed=$$failed skipped=$$skipped"; \
			exit 1; \
		fi; \
	else \
		status=$$?; \
		printf '%b%s\n' "$(FAIL_LABEL)" " Test summary: xcresult=$(TEST_RESULT_BUNDLE) exit=$$status"; \
		exit "$$status"; \
	fi
	@printf '%b%s\n' "$(RESULT_LABEL)" " xcresult: path=$(TEST_RESULT_BUNDLE)"

coverage: test
	+@$(MAKE) --no-print-directory coverage-report

coverage-report:
	@printf '%b%s\n' "$(RESULT_LABEL)" " UnicornCore coverage: xcresult=$(TEST_RESULT_BUNDLE)"
	@xcrun xccov view --report --only-targets "$(TEST_RESULT_BUNDLE)"
