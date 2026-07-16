#!/bin/bash
set -e

# =============================================================================
# KillPort Build Script
# =============================================================================
# Builds the Swift package and packages it into a .app bundle with ad-hoc
# code signing.
# =============================================================================

# Determine project root from script location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🔨 Building KillPort (release)..."
swift build -c release --disable-sandbox

# Get the build output directory.
BIN_DIR=$(swift build -c release --disable-sandbox --show-bin-path)
BINARY="$BIN_DIR/KillPort"

if [ ! -f "$BINARY" ]; then
    echo "❌ Error: Compiled binary not found at $BINARY"
    exit 1
fi

echo "📦 Creating .app bundle..."

APP_DIR="$PROJECT_ROOT/KillPort.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Remove any previous build of the .app bundle.
rm -rf "$APP_DIR"

# Create the bundle directory structure.
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy the compiled binary into the bundle.
cp "$BINARY" "$MACOS_DIR/KillPort"

# Copy the Info.plist into the bundle's Resources directory.
cp "$PROJECT_ROOT/Resources/Info.plist" "$RESOURCES_DIR/Info.plist"

# Make the binary executable.
chmod +x "$MACOS_DIR/KillPort"

# Ad-hoc code sign the entire .app bundle.
echo "🔐 Ad-hoc signing KillPort.app..."
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅ Build complete!"
echo "   App bundle: $APP_DIR"
echo ""
echo "   To run: open $APP_DIR"
