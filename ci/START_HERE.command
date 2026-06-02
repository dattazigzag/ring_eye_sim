#!/usr/bin/env bash
# START HERE — double-click to set up and launch ring_eye_sim on macOS.
# It resolves its OWN folder, so it works wherever you unzip the release.
#
# First time only: macOS may say "unidentified developer" — then
#   right-click this file -> Open  (you only do that once).

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/ring_eye_sim_artnet_sender.app"

echo "=== ring_eye_sim — setup ==="
echo "Folder: $DIR"
echo

if [ ! -d "$APP" ]; then
  echo "ERROR: ring_eye_sim_artnet_sender.app was not found next to this file."
  echo "Keep 'START HERE.command' in the SAME folder as the app, then try again."
  echo
  read -n 1 -s -r -p "Press any key to close."
  exit 1
fi

# 1) Clear the download quarantine so macOS won't block the app.
echo "1/3  Clearing download quarantine..."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# 2) Check for a Java 17+ runtime (the app is native arm64; Java is NOT bundled).
echo "2/3  Checking for Java 17+..."
JHOME="$(/usr/libexec/java_home 2>/dev/null || true)"
JV=""
[ -n "$JHOME" ] && JV="$("$JHOME/bin/java" -version 2>&1 | awk -F'"' '/version/{print $2}')"
MAJOR="${JV%%.*}"
case "$MAJOR" in (''|*[!0-9]*) MAJOR=0 ;; esac
if [ "$MAJOR" -lt 17 ]; then
  echo
  echo "    Java 17+ was not found. Install it once, then run this again:"
  echo "      brew install --cask temurin@17"
  echo "    (No Homebrew? Grab a JDK 17+ from https://adoptium.net )"
  echo
  read -n 1 -s -r -p "Press any key to close."
  exit 1
fi
echo "    Found Java $JV."

# 3) Launch.
echo "3/3  Launching..."
open "$APP"
echo
echo "Done. In the app: press  A  to enable Art-Net, then click ALLOW on the"
echo "\"find devices on your local network\" prompt — that grant is required for DMX."
echo
read -n 1 -s -r -p "Press any key to close."
