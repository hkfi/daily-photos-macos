.PHONY: build install run uninstall clean

APP_NAME   := DailyPhotos
BUILD_DIR  := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications

build:
	@./build.sh

install: build
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "✅ Installed to $(INSTALL_DIR)/$(APP_NAME).app"
	@echo ""
	@echo "Launch from Spotlight or run:  open ~/Applications/DailyPhotos.app"
	@echo "Auto-start: System Settings → General → Login Items → add DailyPhotos"

run: build
	@open "$(APP_BUNDLE)"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "🗑  Removed $(APP_NAME) from $(INSTALL_DIR)"

clean:
	@rm -rf $(BUILD_DIR) $(APP_NAME).xcodeproj
	@echo "🧹 Cleaned build artifacts"
