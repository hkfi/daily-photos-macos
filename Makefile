.PHONY: build install test run uninstall clean release

APP_NAME   := DailyPhotos
BUILD_DIR  := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications

build:
	@./build.sh

install: build
	@./build.sh install

test:
	@if ! command -v xcodegen >/dev/null 2>&1; then \
		echo "❌ xcodegen is required to run tests."; \
		echo "   Install with: brew install xcodegen"; \
		exit 1; \
	fi
	@xcodegen generate --quiet
	@xcodebuild \
		-project "$(APP_NAME).xcodeproj" \
		-scheme "$(APP_NAME)" \
		-destination "platform=macOS" \
		-derivedDataPath "$(BUILD_DIR)/derived-tests" \
		CLANG_MODULE_CACHE_PATH="$(BUILD_DIR)/module-cache-tests" \
		test \
		-quiet

run: build
	@open "$(APP_BUNDLE)"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "🗑  Removed $(APP_NAME) from $(INSTALL_DIR)"

clean:
	@rm -rf $(BUILD_DIR) $(APP_NAME).xcodeproj
	@echo "🧹 Cleaned build artifacts"

release:
	@if [ -z "$(VERSION)" ]; then \
		echo "Usage: make release VERSION=0.2.0"; \
		exit 1; \
	fi
	@echo "🏷  Tagging v$(VERSION)..."
	@git tag "v$(VERSION)"
	@git push origin "v$(VERSION)"
	@echo "✅ Pushed tag v$(VERSION) — GitHub Actions will build and create the release"
