#!/bin/bash
# =============================================================================
# setup.sh — one-time machine prep for Ring Eye Sim (macOS, Apple Silicon)
#
# Installs what the released app needs but does NOT bundle:
#   • a Java 17+ runtime (the app is native arm64; Java is not bundled)
#   • mosquitto (optional MQTT broker for the preview tester) — installed but
#     NOT run as a background service, so the app owns its own broker on :1883
#
# Usage (once per Mac):
#   curl -fsSL https://raw.githubusercontent.com/dattazigzag/ring_eye_sim/main/setup.sh | bash
#
# Then download the app from Releases, unzip, clear quarantine, and launch:
#   xattr -dr com.apple.quarantine ring_eye_sim_artnet_sender.app
#   open ring_eye_sim_artnet_sender.app
#
# It does NOT install Homebrew (its installer wants to own the terminal) — if
# brew is missing this prints the official one-liner and stops. Re-runnable.
# =============================================================================

# Wrap the whole script in braces so bash reads it fully before executing —
# prevents partial execution when piped via curl | bash.
{

set -e

# ---- colors -----------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

print_header()  { echo ""; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}$1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_step()    { echo -e "${YELLOW}▶${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_info()    { echo -e "${CYAN}ℹ${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

# Allow interactive prompts (e.g. the sudo password a JDK cask needs) to reach
# the terminal even when this script is piped via curl | bash.
if [ -t 0 ] || [ -e /dev/tty ]; then
    exec < /dev/tty
fi

# ---- 0 · platform guard -----------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
    print_error "This setup is macOS-only (the app is Apple-Silicon native)."
    exit 1
fi

print_header "RING EYE SIM — MACHINE SETUP (macOS)"

# ---- 1 · Homebrew (check + instruct; never auto-install) --------------------
print_step "Checking Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    # brew may be installed but not yet on PATH (common right after install)
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
fi
if ! command -v brew >/dev/null 2>&1; then
    print_error "Homebrew not found."
    print_info "Install it once with the official one-liner, then re-run this script:"
    echo ""
    echo -e "  ${DIM}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
    echo ""
    exit 1
fi
print_success "Homebrew present: $(brew --version | head -n1)"

# ---- 2 · Java 17+ runtime ---------------------------------------------------
print_step "Checking for a Java 17+ runtime..."
JHOME="$(/usr/libexec/java_home 2>/dev/null || true)"
JV=""
[ -n "$JHOME" ] && JV="$("$JHOME/bin/java" -version 2>&1 | awk -F'"' '/version/{print $2}')"
MAJOR="${JV%%.*}"
case "$MAJOR" in (''|*[!0-9]*) MAJOR=0 ;; esac
if [ "$MAJOR" -ge 17 ]; then
    print_success "Java $JV found"
else
    print_warning "No Java 17+ found — installing the latest Temurin LTS (may ask for your password)..."
    brew install --cask temurin
    print_success "Temurin (latest LTS) installed"
fi

# ---- 3 · mosquitto (optional broker; install but DON'T autostart) -----------
print_step "Checking mosquitto (optional — for the preview tester)..."
if brew list mosquitto >/dev/null 2>&1; then
    print_success "mosquitto already installed"
else
    print_warning "Installing mosquitto..."
    brew install mosquitto
    print_success "mosquitto installed"
fi
# Keep it OFF as a background service — the app spawns/owns its own broker on
# :1883 and won't touch one it didn't start; a brew service would hold the port.
brew services stop mosquitto >/dev/null 2>&1 || true
print_info "mosquitto will NOT autostart (the app manages its own on :1883)."

# ---- done -------------------------------------------------------------------
print_header "SETUP COMPLETE"
echo ""
echo -e "  ${GREEN}✓${NC} Java 17+ runtime ready"
echo -e "  ${GREEN}✓${NC} mosquitto installed, not autostarting"
echo ""
echo -e "${YELLOW}NEXT STEPS${NC}"
echo ""
echo "  1. Download the latest app zip from:"
echo -e "     ${DIM}https://github.com/dattazigzag/ring_eye_sim/releases${NC}"
echo "  2. Unzip, then from that folder clear the download quarantine:"
echo -e "     ${DIM}xattr -dr com.apple.quarantine ring_eye_sim_artnet_sender.app${NC}"
echo "  3. Launch it (or just double-click the .app):"
echo -e "     ${DIM}open ring_eye_sim_artnet_sender.app${NC}"
echo "  4. In the app: press A to enable Art-Net, then click Allow on the"
echo "     \"find devices on your local network\" prompt (required for DMX)."
echo ""

} # End of wrapper — bash reads the whole script before running.
