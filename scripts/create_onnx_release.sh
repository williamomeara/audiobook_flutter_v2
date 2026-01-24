#!/bin/bash
# Create a GitHub release with the iOS ONNX Runtime binaries
# Run this once after cleaning git history to make binaries available for download

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FRAMEWORKS_DIR="$PROJECT_ROOT/packages/platform_ios_tts/ios/Frameworks/onnxruntime.xcframework"

# GitHub release info
REPO="williamomeara/audiobook_flutter_v2"
RELEASE_TAG="onnxruntime-ios-v1.0.0"
RELEASE_TITLE="ONNX Runtime iOS Binaries v1.0.0"

# Files to upload (local_path:asset_name format)
FILES=(
    "ios-arm64/onnxruntime.a:ios-arm64-onnxruntime.a"
    "ios-arm64_x86_64-simulator/onnxruntime.a:ios-arm64_x86_64-simulator-onnxruntime.a"
    "macos-arm64_x86_64/onnxruntime.a:macos-arm64_x86_64-onnxruntime.a"
)

echo "📦 Creating GitHub release for iOS ONNX Runtime binaries..."
echo "   Repository: $REPO"
echo "   Tag: $RELEASE_TAG"
echo ""

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "  brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub CLI. Please run: gh auth login"
    exit 1
fi

# Check all files exist
echo "🔍 Checking for local binaries..."
all_present=true
for entry in "${FILES[@]}"; do
    local_path="${entry%%:*}"
    full_path="$FRAMEWORKS_DIR/$local_path"
    if [ ! -f "$full_path" ]; then
        echo "   ✗ Missing: $local_path"
        all_present=false
    else
        size=$(ls -lh "$full_path" | awk '{print $5}')
        echo "   ✓ Found: $local_path ($size)"
    fi
done

if [ "$all_present" = false ]; then
    echo ""
    echo "Error: Some binaries are missing. Cannot create release."
    exit 1
fi

echo ""

# Check if release already exists
if gh release view "$RELEASE_TAG" --repo "$REPO" &> /dev/null; then
    echo "⚠️  Release $RELEASE_TAG already exists."
    read -p "Do you want to delete it and create a new one? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Deleting existing release..."
        gh release delete "$RELEASE_TAG" --repo "$REPO" --yes
    else
        echo "Aborted."
        exit 0
    fi
fi

# Create a temp directory for renamed files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy files with release-friendly names
echo "📋 Preparing files for upload..."
for entry in "${FILES[@]}"; do
    local_path="${entry%%:*}"
    asset_name="${entry##*:}"
    full_path="$FRAMEWORKS_DIR/$local_path"
    cp "$full_path" "$TEMP_DIR/$asset_name"
    echo "   ✓ Prepared $asset_name"
done

# Create release with files
echo ""
echo "🚀 Creating release..."
gh release create "$RELEASE_TAG" \
    --repo "$REPO" \
    --title "$RELEASE_TITLE" \
    --notes "iOS ONNX Runtime static libraries for platform_ios_tts.

These binaries are required to build the iOS app. They are not included in the git repository due to size limits.

**Files included:**
- \`ios-arm64-onnxruntime.a\` - iOS device (arm64)
- \`ios-arm64_x86_64-simulator-onnxruntime.a\` - iOS Simulator (arm64 + x86_64)
- \`macos-arm64_x86_64-onnxruntime.a\` - macOS (arm64 + x86_64)

**To download:**
\`\`\`bash
./scripts/download_onnx_ios_binaries.sh
\`\`\`

Or manually:
\`\`\`bash
gh release download $RELEASE_TAG --repo $REPO
\`\`\`" \
    "$TEMP_DIR"/*

echo ""
echo "✅ Release created successfully!"
echo "   View at: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
echo ""
echo "Other developers can now run:"
echo "   ./scripts/download_onnx_ios_binaries.sh"
