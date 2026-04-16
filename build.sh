#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
#  build.sh — One-command build for DailyPhotos.app
#
#  Usage:
#    ./build.sh          Build the app
#    ./build.sh install   Build + copy to ~/Applications
#    ./build.sh run       Build + launch immediately
# ──────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DailyPhotos"
BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
MODULE_CACHE_DIR="$(pwd)/$BUILD_DIR/module-cache"
ARCH="$(uname -m)"

echo "🔧 Building $APP_NAME..."

# ── Step 1: Check for Xcode command-line tools ──
if ! xcode-select -p &>/dev/null; then
    echo "❌ Xcode Command Line Tools required."
    echo "   Run: xcode-select --install"
    exit 1
fi

# ── Step 2: Generate .xcodeproj if xcodegen is available,
#    otherwise fall back to manual swiftc build ──
if command -v xcodegen &>/dev/null; then
    echo "📦 Generating Xcode project with xcodegen..."
    xcodegen generate --quiet

    echo "🏗️  Building with xcodebuild..."
    xcodebuild \
        -project "$APP_NAME.xcodeproj" \
        -scheme "$APP_NAME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/derived" \
        -quiet \
        CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_ALLOWED=YES

    # Find the built .app
    BUILT_APP=$(find "$BUILD_DIR/derived" -name "$APP_NAME.app" -type d | head -1)
    mkdir -p "$BUILD_DIR"
    rm -rf "$APP_BUNDLE"
    cp -R "$BUILT_APP" "$APP_BUNDLE"

else
    echo "📦 Building with swiftc (no xcodegen found)..."
    echo "   Tip: brew install xcodegen for a cleaner build"
    echo ""

    # Compile all Swift sources
    SOURCES=(Sources/*.swift)
    BINARY="$BUILD_DIR/$APP_NAME"

    mkdir -p "$BUILD_DIR"

    case "$ARCH" in
        arm64) TARGET_TRIPLE="arm64-apple-macos14.0" ;;
        x86_64) TARGET_TRIPLE="x86_64-apple-macos14.0" ;;
        *)
            echo "❌ Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    swiftc \
        "${SOURCES[@]}" \
        -o "$BINARY" \
        -target "$TARGET_TRIPLE" \
        -sdk "$(xcrun --show-sdk-path)" \
        -module-cache-path "$MODULE_CACHE_DIR" \
        -framework SwiftUI \
        -framework Photos \
        -framework AppKit \
        -O \
        -parse-as-library

    # ── Step 3: Assemble .app bundle ──
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    cp Resources/Info.plist "$APP_BUNDLE/Contents/"

    # Ad-hoc code sign (required on Apple Silicon)
    codesign --force --sign - \
        --entitlements Resources/DailyPhotos.entitlements \
        "$APP_BUNDLE"
fi

echo ""
echo "✅ Built: $APP_BUNDLE"

# ── Optional: install or run ──
case "${1:-}" in
    install)
        mkdir -p "$INSTALL_DIR"
        rm -rf "$INSTALL_DIR/$APP_NAME.app"
        cp -R "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"
        echo "📂 Installed to $INSTALL_DIR/$APP_NAME.app"
        echo ""
        echo "   To launch: open ~/'Applications/DailyPhotos.app'"
        echo "   To auto-start: System Settings → General → Login Items → add DailyPhotos"
        ;;
    run)
        echo "🚀 Launching..."
        open "$APP_BUNDLE"
        ;;
    *)
        echo ""
        echo "   ./build.sh install   → Copy to ~/Applications"
        echo "   ./build.sh run       → Launch now"
        ;;
esac
