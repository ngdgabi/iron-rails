#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export TEAM_ID="${TEAM_ID:-KFDG3WVG6N}"
export ASC_KEY_ID="${ASC_KEY_ID:-Z992GJ553V}"
export ASC_ISSUER_ID="${ASC_ISSUER_ID:-b66d4183-4ecf-491d-992b-ce246240199b}"
export ASC_KEY_PATH="${ASC_KEY_PATH:-/Users/gabordanielnagy/.gemini/antigravity/brain/75a1d5cc-1b15-43a1-a775-3011de888b88/.user_uploaded/media_1794641558319_e343185e.p8}"

echo "==> [1/4] Configuring Universal App Store Metadata, 18 Retina Screenshots & Guideline 2.1 Review Notes..."
python3 "$PROJECT_DIR/scripts/configure_appstore_all.py" --key-path "$ASC_KEY_PATH"

echo "==> [2/4] Archiving & Uploading macOS Universal 2 Build..."
zsh "$PROJECT_DIR/scripts/publish_macos_appstore.sh"

echo "==> [3/4] Archiving, Cloud-Signing & Uploading Universal iOS & iPadOS Build..."
zsh "$PROJECT_DIR/scripts/publish_ios_appstore.sh"

echo "==> [4/4] Setting Age Rating, Attaching Processed Builds & Submitting to App Review..."
python3 "$PROJECT_DIR/scripts/finalize_and_submit_review.py"

echo ""
echo "=============================================================================="
echo "COMPLETE! Iron Rails: Blue & Gray (macOS + iOS + iPadOS) is SUBMITTED!"
echo "=============================================================================="
