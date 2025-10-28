#!/bin/bash

# Minimal Debian installation script + Suckless Setup
# Author: KillChips
# Github:

set -e

# Global variables of the paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#LOCAL_DIR="$HOME/.local/src"  #do I want to install it in .local and make a symlink file in .config for the dwm config file 
CONFIG_DIR="$HOME/.config/suckless"
PATCHES_DIR="$CONFIG_DIR/patches"
TEMP_DIR="/tmp/dwm-setup"
LOG_FILE="$HOME/dwm-install.log"

DWM_REPO="https://git.suckless.org/dwm"
ST_REPO="https://git.suckless.org/st"
DMENU_REPO="https://git.suckless.org/dmenu"
DWMBLOCKS_REPO="https://github.com/UtkarshVerma/dwmblocks-async"

# Logging and cleanup
exec > >(tee -a "$LOG_FILE") 2>&1
trap "rm -rf $TEMP_DIR" EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

die() { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }
msg() { echo -e "${CYAN}$*${NC}"; }

mkdir -p "$CONFIG_DIR" "$PATCHES_DIR" "$TEMP_DIR"

# List of packages to install
PKGS_CORE=(
  build-essential git curl wget patch
  xorg xorg-dev xinput xdotool
  dbus-x11 libusb-0.1-4 libnotify-bin libnotify-dev
  network-manager-gnome make cmake
  ninja-build pkg-config picom
  #libx11-dev libxft-dev libxinerama-dev libxcb1-dev libxcb-randr0-dev libxcb-icccm4-dev libxcb-ewmh-dev pkg-config
  libxcb-util-dev pkg-config
)

PKGS_AUDIO=(
  pavucontrol pulsemixer pamixer pipewire-audio
  pipewire-pulse wireplumber 
)

PKGS_UTILITIES=(
  avahi-daemon acpi acpid xfce4-power-manager
  flameshot qimgv xdg-user-dirs-gtk fd-find
  powertop laptop-mode-tools btop
)

PKGS_UI=(
  rofi dunst feh lxappearance network-manager-gnome lxpolkit
)

PKGS_FILE_MANAGER=(
  thunar thunar-archive-plugin thunar-volman
  gvfs-backends dialog mtools smbclient cifs-utils unzip
)

PKGS_FONTS=(
  fonts-recommended fonts-font-awesome fonts-terminus fonts-dejavu fonts-noto-core
)

PKGS_BUILD=(
  make cmake ninja-build curl pkg-config
)

PKGS_MISC=(
  brightnessctl
  xterm libavcodec-extra
  firefox-esr ntfs-3g
  suckless-tools eza
  nala fastfetch
)

# Curated dwm patches (vanilla dwm patches from suckless)
# NOTE: these filenames correspond to the upstream patch pages; the script will try to download them.
DWM_PATCHES=(
  # [Patch Name]                     [URL]
  "systray systray/dwm-systray-20230922-9f88553.diff"
  "pertag pertag/dwm-pertag-20200914-61bb8b2.diff"
  "attachside attachaside/dwm-attachaside-6.4.diff"
  "movestack movestack/dwm-movestack-20211115-a786211.diff"
  "focusmaster focusmaster/dwm-focusmaster-20210804-138b405.diff"
  "restartsig restartsig/dwm-restartsig-20180523-6.2.diff"
  "uselessgap uselessgap/dwm-uselessgap-20211119-58414bee958f2.diff"
  "actualfullscreen actualfullscreen/dwm-actualfullscreen-20211013-cb3f58a.diff"
  "scratchpads scratchpads/dwm-scratchpads-20200414-728d397b.diff"
  "autostart autostart/dwm-autostart-20210120-cb3f58a.diff"
  "hide_vacant_tags hide_vacant_tags/dwm-hide_vacant_tags-6.4.diff"
)


# ==================
# INSTALL PACKAGES
# ==================
msg "Updating APT and installing packages (may prompt for sudo password)..."
sudo apt update && sudo apt full-upgrade -y

# Install packages
msg "Installing curated packages"
sudo apt install -y "${PKGS_CORE[@]}" || die "Failed to install core packages"
sudo apt install -y "${PKGS_AUDIO[@]}" || die "Failed to install audio packages"
sudo apt install -y "${PKGS_UTILITIES[@]}" || die "Failed to install utility packages"
sudo apt install -y "${PKGS_UI[@]}" || die "Failed to install UI packages"
sudo apt install -y "${PKGS_FILE_MANAGER[@]}" || die "Failed to install file manager packages"
sudo apt install -y "${PKGS_FONTS[@]}" || die "Failed to install font packages"
sudo apt install -y "${PKGS_BUILD[@]}" || die "Failed to install build packages"
sudo apt install -y "${PKGS_MISC[@]}" || die "Failed to install misc packages"

# Enable NetworkManager service
msg "Enabling NetworkManager..."
sudo systemctl enable --now NetworkManager || true

# Enable PipeWire user services (may fail if systemd --user not available in current session)
msg "Enabling PipeWire user services (best-effort)..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

# Enable services
sudo systemctl enable avahi-daemon acpid

# ============
#  FUNCTIONS:
# ============

# Download and apply dwm patches
# Optionally pass the repo directory as first arg to apply patches immediately:
# download_and_apply_patches /path/to/dwm
download_and_apply_patches() {
  local repo_dir="${1:-}"
  mkdir -p "$PATCHES_DIR/dwm"

  for entry in "${DWM_PATCHES[@]}"; do
    # entry format: "<name> <relative/path/to/patch.diff>"
    local name="${entry%% *}"
    local relpath="${entry#* }"
    local url="https://dwm.suckless.org/patches/$relpath"
    local dest="$PATCHES_DIR/dwm/${name}.diff"

    if [ -f "$dest" ]; then
      msg "Patch $name already downloaded -> $dest"
    else
      msg "Downloading patch '$name' from $url -> $dest"
      curl -fsSL -o "$dest" "$url" || die "Failed to download patch $url"
    fi

    # If a repo dir was provided, attempt to apply the patch there.
    if [ -n "$repo_dir" ] && [ -d "$repo_dir" ]; then
      msg "Applying patch '$name' to $(basename "$repo_dir")"
      if ! (cd "$repo_dir" && patch -p1 < "$dest"); then
        die "Warning: applying patch '$name' failed — skipping (check for version mismatch)"
      else
        msg "Applied patch '$name' successfully"
      fi
    fi
  done
}

# Clone or update suckless repos 
clone_or_update_repo() {
  local repo_url=$1
  local dest=$2
  # Checks to see if the directory already exists
  #if it does it updates it, if not it clones it
  if [ -d "$dest/.git" ]; then
    msg "Pulling latest for $(basename "$dest")"
    git -C "$dest" pull --ff-only || true
  else
    msg "Cloning $(basename "$dest")"
    git clone "$repo_url" "$dest"
  fi
}

# Build and install suckless tools
build_and_install() {
  local name=$1
  local repo=$2
  local path="$CONFIG_DIR/$name"

  clone_or_update_repo "$repo" "$path"
  cd "$path"

  msg "Building and installing $name"
  sudo make clean install || die "make install failed for $name"

}

# Build order: st, dmenu, slstatus, dwm (dwm last or after dependencies)
build_and_install "st" "$ST_REPO"
build_and_install "dmenu" "$DMENU_REPO"
build_and_install "dwmblocks-async" "$DWMBLOCKS_REPO"
build_and_install "dwm" "$DWM_REPO"

# Download and apply patches to dwm after building/installing
download_and_apply_patches "$CONFIG_DIR/dwm"

# =====================================
# USER CONFIG: .xinitrc and autostart
# =====================================
XINIT="$HOME/.xinitrc"
if [ -f "$XINIT" ]; then
  msg "$XINIT already exists — creating a backup at ${XINIT}.bak"
  cp "$XINIT" "${XINIT}.bak"
fi

msg "Writing a minimal ~/.xinitrc that autostarts nm-applet, slstatus, and picom"
cat > "$XINIT" <<'EOF'
# ~/.xinitrc — minimal dwm autostart
# Start background services and programs
# Network tray
nm-applet &
# polkit
lxpolkit &
# Status bar (dwmblocks-async)
dwmblocks &
# Compositor
picom --daemon &
dunst &
# Start dwm
exec dwm
EOF

chmod +x "$XINIT"

# =============================
# FINISH
# =============================
msg "Installation finished."
