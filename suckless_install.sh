#!/bin/bash

# Minimal Debian installation script + Suckless Setup
# Author: KillChips
# Github:

set -e

# Global variables of the paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#LOCAL_DIR="$HOME/.local/src"  #do I want to install it in .local and make a symlink file in .config for the dwm config file 
CONFIG_DIR="$HOME/.config/.suckless"
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

# List of packages to install
PKGS_CORE=(
  build-essential git curl wget patch
  xorg xorg-dev xinput xdotool
  dbus-x11 libusb-0.1-4 libnotify-bin libnotify-dev
  network-manager-gnome make cmake
  ninja-build pkg-config picom
  #libx11-dev libxft-dev libxinerama-dev libxcb1-dev libxcb-randr0-dev libxcb-icccm4-dev libxcb-ewmh-dev pkg-config
  libxcb-util-dev
)

PKGS_AUDIO=(
  pavucontrol pulsemixer pamixer pipewire-audio
  pipewire-pulse wireplumber 
)

PKGS_UTILITIES=(
  avahi-daemon acpi acpid xfce4-power-manager
  flameshot qimgv xdg-user-dirs-gtk fd-find
)

PACKAGES_UI=(
  rofi dunst feh lxappearance network-manager-gnome 
)

PACKAGES_FILE_MANAGER=(
  thunar thunar-archive-plugin thunar-volman
  gvfs-backends dialog mtools smbclient cifs-utils unzip
)

PPKGS_FONTS=(
  fonts-recommended fonts-font-awesome fonts-terminus fonts-dejavu fonts-noto-core
)

PACKAGES_BUILD=(
  make cmake ninja-build curl pkg-config
)

PKGS_MISC=(
  brightnessctl
  xterm libavcodec-extra
  firefox-esr ntfs-3g
  suckless-tools exa
)

# Curated dwm patches (vanilla dwm patches from suckless)
# NOTE: these filenames correspond to the upstream patch pages; the script will try to download them.
DWM_PATCHES=(
  "systray/dwm-systray-6.4.diff"
  "pertag/dwm-pertag-6.4.diff"
  "viewontag/dwm-viewontag-6.4.diff"
  "fakefullscreen/dwm-fakefullscreen-6.4.diff"
  "alwayscenter/dwm-alwayscenter-6.4.diff"
  "savefloats/dwm-savefloats-6.4.diff"
  "swallow/dwm-swallow-6.4.diff"
  "scratchpads/dwm-scratchpads-6.4.diff"
  "xresources/dwm-xresources-6.4.diff"
)

# ==================
# INSTALL PACKAGES
# ==================
info "Updating APT and installing packages (may prompt for sudo password)..."
sudo apt update && sudo apt full-upgrade -y

# Install packages
msg "Installing curated packages"
sudo apt install -y "${PKGS_CORE[@]}" || die "Failed to install core packages"
sudo apt install -y "${PKGS_AUDIO[@]}" || die "Failed to install audio packages"
sudo apt install -y "${PKGS_UTILITIES[@]}" || die "Failed to install utility packages"
sudo apt install -y "${PACKAGES_UI[@]}" || die "Failed to install UI packages"
sudo apt install -y "${PACKAGES_FILE_MANAGER[@]}" || die "Failed to install file manager packages"
sudo apt install -y "${PPKGS_FONTS[@]}" || die "Failed to install font packages"
sudo apt install -y "${PACKAGES_BUILD[@]}" || die "Failed to install build packages"
sudo apt install -y "${PKGS_MISC[@]}" || die "Failed to install misc packages"

# Enable NetworkManager service
info "Enabling NetworkManager..."
sudo systemctl enable --now NetworkManager || true

# Enable PipeWire user services (may fail if systemd --user not available in current session)
info "Enabling PipeWire user services (best-effort)..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

# Enable services
sudo systemctl enable avahi-daemon acpid

# ============
#  FUNCTIONS:
# ============

# Package Installation
install_packages() {

}

# Clone or update suckless repos 
clone_or_update_repo() {
  local repo_url=$1
  local dest=$2
  # Checks to see if the directory already exists
  #if it does it updates it, if not it clones it
  if [ -d "$dest/.git" ]; then
    info "Pulling latest for $(basename "$dest")"
    git -C "$dest" pull --ff-only || true
  else
    info "Cloning $(basename "$dest")"
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

  # Apply patches from PATCHES_DIR/dwm if building dwm
  if [ "$name" = "dwm" ]; then
    info "Applying dwm patches from $PATCHES_DIR/dwm (if any)..."
    for patchfile in "$PATCHES_DIR/dwm"/*.diff; do
      [ -e "$patchfile" ] || break
      info "Applying $(basename "$patchfile")"
      # Try to apply; allow failure and continue so user can inspect
      if ! patch -p1 < "$patchfile"; then
        warn "Patch $(basename "$patchfile") failed — you may need to apply manually or check for version mismatch"
      fi
    done
  fi

  info "Building and installing $name"
  sudo make clean install || error "make install failed for $name"

}

# Build order: st, dmenu, slstatus, dwm (dwm last or after dependencies)
build_and_install "st" "$ST_REPO"
build_and_install "dmenu" "$DMENU_REPO"
build_and_install "dwmblocks-async" "$DWMBLOCKS_REPO"
build_and_install "dwm" "$DWM_REPO"

# =====================================
# USER CONFIG: .xinitrc and autostart
# =====================================
XINIT="$HOME/.xinitrc"
if [ -f "$XINIT" ]; then
  info "$XINIT already exists — creating a backup at ${XINIT}.bak"
  cp "$XINIT" "${XINIT}.bak"
fi

info "Writing a minimal ~/.xinitrc that autostarts nm-applet, slstatus, and picom"
cat > "$XINIT" <<'EOF'
# ~/.xinitrc — minimal dwm autostart
# Start background services and programs
# Network tray
nm-applet &
# Status bar (slstatus)
slstatus &
# Compositor
picom --daemon &
# Start dwm
exec dwm
EOF

chmod +x "$XINIT"

# =============================
# FINISH
# =============================
info "Installation finished."