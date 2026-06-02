#!/usr/bin/env bash
# sign-release.sh — sign a CI-built ring_eye_sim release with a local self-signed
# identity so macOS 26 will OFFER the Local Network prompt (ad-hoc is NOT enough).
#
# Usage:
#   ci/sign-release.sh <ring_eye_sim-vX.Y.Z-macos-aarch64.zip | *.app>
#
# Produces, next to the input:
#   <name>-signed.zip      signed app, ready to hand to colleagues
#   RingEyeSim-Local.cer   public cert (only needed as a fallback if a colleague's
#                          Mac refuses to show the Local Network prompt — see README)
#
# Requires the "RingEyeSim Local" code-signing identity in your login keychain
# (see README -> Distributing for one-time setup).

set -euo pipefail

IDENTITY="RingEyeSim Local"
IN="${1:?usage: sign-release.sh <zip-or-app>}"

# find-identity -v hides untrusted self-signed certs, so check the plain list too.
if ! security find-identity -p codesigning | grep -q "$IDENTITY" \
&& ! security find-identity              | grep -q "$IDENTITY"; then
    echo "ERROR: code-signing identity '$IDENTITY' not found in your keychain." >&2
    echo "Create it once (README -> Distributing), then re-run." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

case "$IN" in
    *.zip)
        ditto -x -k "$IN" "$WORK"
        APP="$(/usr/bin/find "$WORK" -maxdepth 2 -name '*.app' -type d | head -1)"
    OUTDIR="$(cd "$(dirname "$IN")" && pwd)"; BASE="$(basename "${IN%.zip}")" ;;
    *.app)
        APP="$IN"
    OUTDIR="$(cd "$(dirname "$IN")" && pwd)"; BASE="$(basename "${IN%.app}")" ;;
    *)
    echo "ERROR: pass a .zip or .app" >&2; exit 1 ;;
esac

[ -n "${APP:-}" ] && [ -d "$APP" ] || { echo "ERROR: no .app found in $IN" >&2; exit 1; }

echo "Signing: $APP"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Authority|Identifier' || true
codesign --verify --deep --strict --verbose=2 "$APP"

OUT_ZIP="$OUTDIR/${BASE}-signed.zip"
rm -f "$OUT_ZIP"
ditto -c -k --keepParent "$APP" "$OUT_ZIP"   # macOS-correct zip (preserves symlinks)
echo "Wrote: $OUT_ZIP"

security find-certificate -c "$IDENTITY" -p > "$OUTDIR/RingEyeSim-Local.cer" 2>/dev/null \
&& echo "Wrote: $OUTDIR/RingEyeSim-Local.cer (fallback only — see README)"

echo "Done. Hand '$OUT_ZIP' to colleagues."
