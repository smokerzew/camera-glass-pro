#!/usr/bin/env bash
# One-time setup for building Camera Glass Pro on Windows (inside WSL Ubuntu) or Linux.
# Installs: build deps, Swift (via swiftly), xtool. It does NOT log in to Apple or touch Xcode.xip:
# run `xtool setup` yourself afterwards (it asks for your Apple ID and the Xcode.xip path).
set -euo pipefail

echo "==> Installing system packages (sudo password may be asked)"
sudo apt-get update
sudo apt-get install -y curl ca-certificates tar gzip unzip zip git \
  usbmuxd libimobiledevice-utils \
  build-essential binutils gnupg2 pkg-config tzdata libcurl4-openssl-dev libxml2-dev \
  libsqlite3-dev libncurses-dev libz3-dev zlib1g-dev libpython3-dev
# xtool ships as an AppImage, which needs FUSE 2 (package name differs between Ubuntu releases).
sudo apt-get install -y libfuse2t64 2>/dev/null || sudo apt-get install -y libfuse2

if ! command -v swift >/dev/null 2>&1; then
  echo "==> Installing Swift with swiftly (official swift.org installer)"
  tmp=$(mktemp -d)
  (cd "$tmp" && curl -fsSLO "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" \
    && tar zxf "swiftly-$(uname -m).tar.gz" && ./swiftly init --quiet-shell-followup --assume-yes)
  rm -rf "$tmp"
fi
# shellcheck disable=SC1091
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" 2>/dev/null || true
hash -r
swift --version

if ! command -v xtool >/dev/null 2>&1; then
  echo "==> Installing xtool"
  curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o /tmp/xtool
  chmod +x /tmp/xtool
  sudo mv /tmp/xtool /usr/local/bin/xtool
fi
xtool --help | head -3

cat <<'NEXT'

Setup done. Two manual steps remain (they need YOUR Apple ID, so this script can't do them):
  1. In a Windows browser, download Xcode 27 (.xip) from https://developer.apple.com/download/all/?q=Xcode
  2. In this WSL terminal run:   xtool setup
     - login mode 1 (Password) works with a free Apple ID; 0 (API Key) needs a paid membership
     - when asked "Path to Xcode.xip", give the WSL path, e.g. /mnt/c/Users/<you>/Downloads/Xcode_27.0.xip
Then build with:  ./scripts/build-ipa.sh
NEXT
