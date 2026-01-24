#!/bin/bash
# Download iOS ONNX Runtime binaries from GitHub releases
# These are too large for git (61-128MB each) so they're stored in releases

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FRAMEWORKS_DIR="$PROJECT_ROOT/packages/platform_ios_tts/ios/Frameworks/onnxruntime.xcframework"

# GitHub release info
REPO="williamomeara/audiobook_flutter_v2"
RELEASE_TAG="onnxruntime-ios-v1.0.0"

# Expected files (local_path:asset_name format)
FILES=(
    "ios-arm64/onnxruntime.a:ios-arm64-onnxruntime.a"
    "ios-arm64_x86_64-simulator/onnxruntime.a:ios-arm64_x86_64-simulator-onnxruntime.a"
    "macos-arm64_x86_64/onnxruntime.a:macos-arm64_x86_64-onnxruntime.a"
)

echo "📦 Checking ONNX Runtime iOS binaries..."

all_present=true
for entry in "${FILES[@]}"; do
    local_path="${entry%%:*}"
    full_path="$FRAMEWORKS_DIR/$local_path"
    if [ ! -f "$full_path" ]; then
        echo "   Missing: $local_path"
        all_present=false
    fi
done

if [ "$all_present" = true ]; then
    echo "✅ All ONNX Runtime binaries are present"
    exit 0
fi

echo "📥 Downloading ONNX Runtime iOS binaries from release $RELEASE_TAG..."

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed. Please install it first."
    echo "  brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub CLI. Please run: gh auth login"
    exit 1
fi

# Download each missing file
for entry in "${FILES[@]}"; do
    local_path="${entry%%:*}"
    asset_name="${entry##*:}"
    full_path="$FRAMEWORKS_DIR/$local_path"
    
    if [ -f "$full_path" ]; then
        echo "   ✓ $local_path (already present)"
        continue
    fi
    
    echo "   Downloading $asset_name..."
    
    # Ensure directory exists
    mkdir -p "$(dirname "$full_path")"
    
    # Download using gh CLI
    if gh release download "$RELEASE_TAG" \
        --repo "$REPO" \
        --pattern "$asset_name" \
        --output "$full_path" 2>/dev/null; then
        echo "   ✓ Downloaded $local_path"
    else
        echo "   ✗ Failed to download $asset_name"
        echo ""
        echo "The release '$RELEASE_TAG' may not exist yet."
        echo "To create it, run: scripts/create_onnx_release.sh"
        exit 1
    fi
done

echo ""
echo "✅ All ONNX Runtime binaries downloaded successfully!"
