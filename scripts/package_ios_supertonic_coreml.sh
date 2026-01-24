#!/bin/bash
# Package and upload iOS Supertonic CoreML models to GitHub releases
# These are downloaded at runtime by the app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_ROOT/packages/platform_ios_tts/ios/Assets/supertonic_coreml"

# GitHub release info
REPO="williamomeara/audiobook_flutter_assets"
RELEASE_TAG="ai-cores-int8-v1"

ARCHIVE_NAME="supertonic_coreml.tar.gz"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "📦 Packaging iOS Supertonic CoreML models..."
echo "   Source: $ASSETS_DIR"
echo ""

# Check if source exists
if [ ! -d "$ASSETS_DIR" ]; then
    echo "Error: Assets directory not found: $ASSETS_DIR"
    exit 1
fi

# List contents
echo "📋 Contents to package:"
du -sh "$ASSETS_DIR"/* 2>/dev/null | while read line; do
    echo "   $line"
done
echo ""

# Create archive with proper structure for extraction
# Archive should extract as: supertonic_coreml/{contents}
cd "$(dirname "$ASSETS_DIR")"
tar -czvf "$TEMP_DIR/$ARCHIVE_NAME" "$(basename "$ASSETS_DIR")"

# Show archive size
ARCHIVE_SIZE=$(ls -lh "$TEMP_DIR/$ARCHIVE_NAME" | awk '{print $5}')
echo ""
echo "📦 Created archive: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
echo ""

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "Archive created but cannot upload: GitHub CLI (gh) not installed."
    echo "Archive location: $TEMP_DIR/$ARCHIVE_NAME"
    echo ""
    echo "To upload manually:"
    echo "  gh release upload $RELEASE_TAG $TEMP_DIR/$ARCHIVE_NAME --repo $REPO"
    exit 0
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "Archive created but cannot upload: Not authenticated with GitHub CLI."
    echo "Archive location: $TEMP_DIR/$ARCHIVE_NAME"
    exit 0
fi

# Upload to release
echo "🚀 Uploading to GitHub release..."
if gh release upload "$RELEASE_TAG" "$TEMP_DIR/$ARCHIVE_NAME" --repo "$REPO" --clobber; then
    echo ""
    echo "✅ Successfully uploaded to release $RELEASE_TAG"
    echo "   https://github.com/$REPO/releases/tag/$RELEASE_TAG"
else
    echo ""
    echo "Failed to upload. You may need to create the release first:"
    echo "  gh release create $RELEASE_TAG --repo $REPO --title 'AI TTS Cores (int8)'"
    exit 1
fi
