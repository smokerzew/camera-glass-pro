#!/usr/bin/env bash
# Builds Camera Glass Pro into an .ipa with xtool (Windows/WSL or Linux, no Mac).
#   ./scripts/build-ipa.sh            unsigned .ipa  -> dist/CameraGlassPro.ipa (sign later, e.g. Sideloadly)
#   ./scripts/build-ipa.sh --sign     signed with the Apple ID from `xtool setup`
#   ./scripts/build-ipa.sh --install  build, sign and install on a USB-connected iPhone (xtool dev)
set -euo pipefail
cd "$(dirname "$0")/.."
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" 2>/dev/null || true

case "${1:-}" in
  --install)
    exec xtool dev run --configuration release
    ;;
  --sign)
    xtool dev build --configuration release --ipa --sign
    ;;
  "")
    xtool dev build --configuration release --ipa
    ;;
  *)
    echo "usage: $0 [--sign | --install]" >&2; exit 2
    ;;
esac

mkdir -p dist
cp -f xtool/CameraGlassPro.ipa dist/CameraGlassPro.ipa
echo "IPA: $(pwd)/dist/CameraGlassPro.ipa"
