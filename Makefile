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

XCODEBUILD ?= xcodebuild
XCODEBUILD_FLAGS = $(if $(filter 1,$(VERBOSE)),,-quiet)
XCODEBUILD_COMMAND = $(strip $(XCODEBUILD) $(XCODEBUILD_FLAGS))
XCODE_PROJECT_ARGS = -project "$(XCODE_PROJECT)" -scheme "$(XCODE_SCHEME)"
XCODE_SIGNING_ARGS = \
	CODE_SIGN_IDENTITY="-" \
	CODE_SIGNING_REQUIRED=YES \
	CODE_SIGNING_ALLOWED=YES

PASS_LABEL = $(if $(filter 1,$(NO_COLOR)),[PASS],\033[1;32m[PASS]\033[0m)
FAIL_LABEL = $(if $(filter 1,$(NO_COLOR)),[FAIL],\033[1;31m[FAIL]\033[0m)
RESULT_LABEL = $(if $(filter 1,$(NO_COLOR)),[RESULT],\033[1;36m[RESULT]\033[0m)

define BENCHMARK_FAILURE
if [ -t 1 ] && [ -z "$${CI+x}" ] && [ -z "$${NO_COLOR+x}" ]; then \
	printf '\033[1;31m[FAIL]\033[0m %s\n' "$(1)"; \
else \
	printf '[FAIL] %s\n' "$(1)"; \
fi
endef

SYMROOT ?= $(abspath $(BUILD_DIR))
OBJROOT ?= $(SYMROOT)/obj
NATIVE_ARCH ?= $(shell uname -m)
TEST_ROOT ?= $(SYMROOT)/Test
TEST_DERIVED_DATA ?= $(TEST_ROOT)/DerivedData
TEST_RESULT_BUNDLE ?= $(TEST_ROOT)/Results/UnicornCoreTests.xcresult
TEST_APP_SYMROOT ?= $(TEST_ROOT)/UniversalBuildProducts
TEST_APP_OBJROOT ?= $(TEST_ROOT)/UniversalBuildIntermediates
BENCHMARK_SCHEME ?= UnicornCorePerformanceTests
BENCHMARK_ROOT ?= $(SYMROOT)/Benchmark
BENCHMARK_DERIVED_DATA ?= $(BENCHMARK_ROOT)/DerivedData
BENCHMARK_RESULT_BUNDLE ?= $(BENCHMARK_ROOT)/Results/UnicornCorePerformanceTests.xcresult
BENCHMARK_SUMMARY_DIR ?= $(BENCHMARK_ROOT)/Summary
BENCHMARK_XCODE_SUMMARY ?= $(BENCHMARK_SUMMARY_DIR)/xcode-test-summary.json
BENCHMARK_XCODE_METRICS ?= $(BENCHMARK_SUMMARY_DIR)/xcode-performance-metrics.json
BENCHMARK_SUMMARY ?= $(BENCHMARK_SUMMARY_DIR)/benchmark-summary.json
APP_BUNDLE ?= $(SYMROOT)/$(CONFIG)/$(APP_NAME).app
APP_EXECUTABLE ?= $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
INSTALL_DIR ?= $(HOME)/Library/Input Methods

# Automatically detect the GitHub repository name (e.g., owner/repo)
GITHUB_REPO = $(shell git remote get-url origin 2>/dev/null | sed -E 's/.*github.com[:/](.*)(\.git)?/\1/' | sed 's/\.git$$//')

.PHONY: all build build-universal build-debug install install-debug clean
.PHONY: test test-native test-summary benchmark benchmark-native benchmark-summary benchmark-report-test
.PHONY: coverage coverage-report lint format
.PHONY: release test-release clean-test-releases re-release _wipe_release

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

build: build-universal

build-universal:
	@if $(XCODEBUILD_COMMAND) $(XCODE_PROJECT_ARGS) \
		-configuration "$(CONFIG)" \
		-destination 'generic/platform=macOS' \
		SYMROOT="$(SYMROOT)" \
		OBJROOT="$(OBJROOT)" \
		ARCHS="$(ARCHS)" \
		ONLY_ACTIVE_ARCH=NO \
		$(XCODE_SIGNING_ARGS); then \
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
	rm -rf "$(BUILD_DIR)"

test: test-native
	+@$(MAKE) --no-print-directory build-universal \
		CONFIG=Debug \
		ARCHS="$(ARCHS)" \
		SYMROOT="$(TEST_APP_SYMROOT)" \
		OBJROOT="$(TEST_APP_OBJROOT)"

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

benchmark: benchmark-native

benchmark-native:
	@echo "Running UnicornCore benchmarks in Release on $(NATIVE_ARCH)..."
	@rm -rf "$(BENCHMARK_ROOT)"
	@rm -f "$(BENCHMARK_XCODE_SUMMARY)" "$(BENCHMARK_XCODE_METRICS)" "$(BENCHMARK_SUMMARY)"
	@mkdir -p "$(dir $(BENCHMARK_RESULT_BUNDLE))" "$(BENCHMARK_SUMMARY_DIR)"
	@test ! -e "$(BENCHMARK_RESULT_BUNDLE)" || \
		{ $(call BENCHMARK_FAILURE,Refusing stale benchmark result: path=$(BENCHMARK_RESULT_BUNDLE)); exit 1; }
	@build_log="$$(mktemp)" || \
		{ $(call BENCHMARK_FAILURE,Core benchmarks: unable to create temporary build log); exit 1; }; \
	trap 'rm -f "$$build_log"' EXIT; \
	if $(XCODEBUILD_COMMAND) test \
		-project "$(XCODE_PROJECT)" \
		-scheme "$(BENCHMARK_SCHEME)" \
		-configuration Release \
		-destination 'platform=macOS,arch=$(NATIVE_ARCH)' \
		-derivedDataPath "$(BENCHMARK_DERIVED_DATA)" \
		-resultBundlePath "$(BENCHMARK_RESULT_BUNDLE)" \
		-only-testing:UnicornCorePerformanceTests \
		-parallel-testing-enabled NO \
		-enableCodeCoverage NO \
		SYMROOT="$(BENCHMARK_ROOT)/BuildProducts" \
		OBJROOT="$(BENCHMARK_ROOT)/Intermediates" \
		ARCHS="$(NATIVE_ARCH)" \
		ONLY_ACTIVE_ARCH=YES \
		$(XCODE_SIGNING_ARGS) > "$$build_log" 2>&1; then \
		:; \
	else \
		status=$$?; \
		cat "$$build_log" >&2; \
		$(call BENCHMARK_FAILURE,Core benchmarks: configuration=Release arch=$(NATIVE_ARCH) exit=$$status); \
		if [ -e "$(BENCHMARK_RESULT_BUNDLE)" ]; then \
			$(MAKE) --no-print-directory benchmark-summary || :; \
		fi; \
		exit "$$status"; \
	fi
	+@$(MAKE) --no-print-directory benchmark-summary

benchmark-summary:
	@mkdir -p "$(dir $(BENCHMARK_XCODE_SUMMARY))" \
		"$(dir $(BENCHMARK_XCODE_METRICS))" \
		"$(dir $(BENCHMARK_SUMMARY))"
	@summary_tmp="$(BENCHMARK_XCODE_SUMMARY).tmp"; \
	metrics_tmp="$(BENCHMARK_XCODE_METRICS).tmp"; \
	trap 'rm -f "$$summary_tmp" "$$metrics_tmp"' EXIT; \
	if xcrun xcresulttool get test-results summary \
		--path "$(BENCHMARK_RESULT_BUNDLE)" --compact > "$$summary_tmp" && \
		xcrun xcresulttool get test-results metrics \
		--path "$(BENCHMARK_RESULT_BUNDLE)" --compact > "$$metrics_tmp"; then \
		mv "$$summary_tmp" "$(BENCHMARK_XCODE_SUMMARY)"; \
		mv "$$metrics_tmp" "$(BENCHMARK_XCODE_METRICS)"; \
	else \
		status=$$?; \
		$(call BENCHMARK_FAILURE,Benchmark summary export: xcresult=$(BENCHMARK_RESULT_BUNDLE) exit=$$status); \
		exit "$$status"; \
	fi
	@report_tmp="$(BENCHMARK_SUMMARY).tmp"; \
	trap 'rm -f "$$report_tmp"' EXIT; \
	rm -f "$$report_tmp" "$(BENCHMARK_SUMMARY)"; \
	if python3 scripts/benchmark_report.py \
		--keymap unicorn/keymap.json \
		--test-summary "$(BENCHMARK_XCODE_SUMMARY)" \
		--metrics "$(BENCHMARK_XCODE_METRICS)" \
		--output "$$report_tmp" \
		--artifact-path "$(BENCHMARK_ROOT)" && \
		mv "$$report_tmp" "$(BENCHMARK_SUMMARY)"; then \
		:; \
	else \
		status=$$?; \
		$(call BENCHMARK_FAILURE,Benchmark report: output=$(BENCHMARK_SUMMARY) exit=$$status); \
		exit "$$status"; \
	fi

benchmark-report-test:
	@python3 scripts/test_benchmark_report.py

coverage: test
	+@$(MAKE) --no-print-directory coverage-report

coverage-report:
	@printf '%b%s\n' "$(RESULT_LABEL)" " UnicornCore coverage: xcresult=$(TEST_RESULT_BUNDLE)"
	@xcrun xccov view --report --only-targets "$(TEST_RESULT_BUNDLE)"
