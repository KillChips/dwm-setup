#!/bin/bash
# Minimal Debian 13 + Suckless Installer (Enhanced)
# - Installs required packages (Xorg, PipeWire, NetworkManager with nm-applet)
# - Builds dwm, st, dmenu, and slstatus from source
# - Downloads and applies a curated set of dwm patches (vanilla dwm)
# - Creates a simple, usable ~/.xinitrc that auto-starts nm-applet, slstatus, and picom
# - Idempotent: safe to run multiple times

set -euo pipefail

# =============================
# CONFIG
# =============================
REPO_DIR="$HOME/.local/src"
PATCHES_DIR="$REPO_DIR/patches"
DWM_REPO="https://git.suckless.org/dwm"
ST_REPO="https://git.suckless.org/st"
DMENU_REPO="https://git.suckless.org/dmenu"
SLSTATUS_REPO="https://git.suckless.org/slstatus"

# List of packages to install (kept minimal but usable for a laptop)
PKGS=(
  build-essential git curl wget patch
  xorg xorg-dev x11-xserver-utils xinput
  libx11-dev libxft-dev libxinerama-dev
  xserver-xorg-video-intel
  network-manager-gnome
  pipewire pipewire-audio pipewire-pulse wireplumber pavucontrol
  brightnessctl acpi
  feh dunst picom xterm
  fonts-dejavu fonts-font-awesome
  firefox-esr neovim
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

# =============================
# HELPERS
# =============================
info() { printf "[INFO] %s\n" "$1"; }
warn() { printf "[WARN] %s\n" "$1"; }
error() { printf "[ERROR] %s\n" "$1"; exit 1; }

# Ensure directories
mkdir -p "$REPO_DIR"
mkdir -p "$PATCHES_DIR/dwm"

# =============================
# INSTALL PACKAGES
# =============================
info "Updating APT and installing packages (may prompt for sudo password)..."
sudo apt update && sudo apt full-upgrade -y

# Install packages in a single apt call
sudo apt install -y "${PKGS[@]}"

# Enable NetworkManager service
info "Enabling NetworkManager..."
sudo systemctl enable --now NetworkManager || true

# Enable PipeWire user services (may fail if systemd --user not available in current session)
info "Enabling PipeWire user services (best-effort)..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

# =============================
# FETCH DWm PATCHES (if not already present)
# =============================
info "Downloading dwm patches into $PATCHES_DIR/dwm (if missing)..."
BASE_PATCH_URL="https://dwm.suckless.org/patches"
for p in "${DWM_PATCHES[@]}"; do
  dest="$PATCHES_DIR/dwm/$(basename "$p")"
  if [ -f "$dest" ]; then
    info "Patch $(basename "$p") already present, skipping download"
    continue
  fi
  url="$BASE_PATCH_URL/$(dirname "$p")/$(basename "$p")"
  info "Downloading $url"
  if ! curl -fsSL "$url" -o "$dest"; then
    warn "Failed to download $url — continuing (you can add the patch manually in $PATCHES_DIR/dwm)"
    rm -f "$dest" || true
  fi
done

# =============================
# FUNCTION: clone or update a repo
# =============================
clone_or_update() {
  local repo_url=$1
  local dest=$2
  if [ -d "$dest/.git" ]; then
    info "Pulling latest for $(basename "$dest")"
    git -C "$dest" pull --ff-only || true
  else
    info "Cloning $(basename "$dest")"
    git clone "$repo_url" "$dest"
  fi
}

# =============================
# BUILD & INSTALL SUCKLESS TOOLS
# =============================
build_and_install() {
  local name=$1
  local repo=$2
  local path="$REPO_DIR/$name"

  clone_or_update "$repo" "$path"
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
build_and_install "slstatus" "$SLSTATUS_REPO"
build_and_install "dwm" "$DWM_REPO"

# =============================
# USER CONFIG: .xinitrc and autostart
# =============================
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
cat <<EOF

Next steps:
  1) If you installed nm-applet and want the tray to show, ensure dwm has the systray patch applied (this script attempts to apply it).
  2) Start X with: startx
  3) Configure slstatus: edit $REPO_DIR/slstatus/config.h and recompile (sudo make clean install) to set what shows on the bar.
  4) If any dwm patch failed to apply because of version mismatch, put the correct patch file into:
       $PATCHES_DIR/dwm/
     and re-run this script to attempt applying again.

If you want, I can now:
  - Add a curated set of patch files bundled into the installer (so it never depends on remote patch versions).
  - Add default slstatus config (battery, cpu, ram, wifi, volume, date/time).
  - Add keybindings and a sample config.h for dwm (including scratchpad + pertag settings).

Tell me which of those you'd like me to add next and I'll update the script.
EOF
#!/bin/bash
# Minimal Debian 13 + Suckless Installer (Enhanced)
# - Installs required packages (Xorg, PipeWire, NetworkManager with nm-applet)
# - Builds dwm, st, dmenu, and slstatus from source
# - Downloads and applies a curated set of dwm patches (vanilla dwm)
# - Creates a simple, usable ~/.xinitrc that auto-starts nm-applet, slstatus, and picom
# - Idempotent: safe to run multiple times

set -euo pipefail

# =============================
# CONFIG
# =============================
REPO_DIR="$HOME/.local/src"
PATCHES_DIR="$REPO_DIR/patches"
DWM_REPO="https://git.suckless.org/dwm"
ST_REPO="https://git.suckless.org/st"
DMENU_REPO="https://git.suckless.org/dmenu"
SLSTATUS_REPO="https://git.suckless.org/slstatus"

# List of packages to install (kept minimal but usable for a laptop)
PKGS=(
  build-essential git curl wget patch
  xorg xorg-dev x11-xserver-utils xinput
  libx11-dev libxft-dev libxinerama-dev
  xserver-xorg-video-intel
  network-manager-gnome
  pipewire pipewire-audio pipewire-pulse wireplumber pavucontrol
  brightnessctl acpi
  feh dunst picom xterm
  fonts-dejavu fonts-font-awesome
  firefox-esr neovim
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

# =============================
# HELPERS
# =============================
info() { printf "[INFO] %s\n" "$1"; }
warn() { printf "[WARN] %s\n" "$1"; }
error() { printf "[ERROR] %s\n" "$1"; exit 1; }

# Ensure directories
mkdir -p "$REPO_DIR"
mkdir -p "$PATCHES_DIR/dwm"

# =============================
# INSTALL PACKAGES
# =============================
info "Updating APT and installing packages (may prompt for sudo password)..."
sudo apt update && sudo apt full-upgrade -y

# Install packages in a single apt call
sudo apt install -y "${PKGS[@]}"

# Enable NetworkManager service
info "Enabling NetworkManager..."
sudo systemctl enable --now NetworkManager || true

# Enable PipeWire user services (may fail if systemd --user not available in current session)
info "Enabling PipeWire user services (best-effort)..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

# =============================
# FETCH DWm PATCHES (if not already present)
# =============================
info "Downloading dwm patches into $PATCHES_DIR/dwm (if missing)..."
BASE_PATCH_URL="https://dwm.suckless.org/patches"
for p in "${DWM_PATCHES[@]}"; do
  dest="$PATCHES_DIR/dwm/$(basename "$p")"
  if [ -f "$dest" ]; then
    info "Patch $(basename "$p") already present, skipping download"
    continue
  fi
  url="$BASE_PATCH_URL/$(dirname "$p")/$(basename "$p")"
  info "Downloading $url"
  if ! curl -fsSL "$url" -o "$dest"; then
    warn "Failed to download $url — continuing (you can add the patch manually in $PATCHES_DIR/dwm)"
    rm -f "$dest" || true
  fi
done

# =============================
# FUNCTION: clone or update a repo
# =============================
clone_or_update() {
  local repo_url=$1
  local dest=$2
  if [ -d "$dest/.git" ]; then
    info "Pulling latest for $(basename "$dest")"
    git -C "$dest" pull --ff-only || true
  else
    info "Cloning $(basename "$dest")"
    git clone "$repo_url" "$dest"
  fi
}

# =============================
# BUILD & INSTALL SUCKLESS TOOLS
# =============================
build_and_install() {
  local name=$1
  local repo=$2
  local path="$REPO_DIR/$name"

  clone_or_update "$repo" "$path"
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
build_and_install "slstatus" "$SLSTATUS_REPO"
build_and_install "dwm" "$DWM_REPO"

# =============================
# USER CONFIG: .xinitrc and autostart
# =============================
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
cat <<EOF

Next steps:
  1) If you installed nm-applet and want the tray to show, ensure dwm has the systray patch applied (this script attempts to apply it).
  2) Start X with: startx
  3) Configure slstatus: edit $REPO_DIR/slstatus/config.h and recompile (sudo make clean install) to set what shows on the bar.
  4) If any dwm patch failed to apply because of version mismatch, put the correct patch file into:
       $PATCHES_DIR/dwm/
     and re-run this script to attempt applying again.

If you want, I can now:
  - Add a curated set of patch files bundled into the installer (so it never depends on remote patch versions).
  - Add default slstatus config (battery, cpu, ram, wifi, volume, date/time).
  - Add keybindings and a sample config.h for dwm (including scratchpad + pertag settings).

Tell me which of those you'd like me to add next and I'll update the script.
EOF
#!/bin/bash
# Minimal Debian 13 + Suckless Installer (Enhanced)
# - Installs required packages (Xorg, PipeWire, NetworkManager with nm-applet)
# - Builds dwm, st, dmenu, and slstatus from source
# - Downloads and applies a curated set of dwm patches (vanilla dwm)
# - Creates a simple, usable ~/.xinitrc that auto-starts nm-applet, slstatus, and picom
# - Idempotent: safe to run multiple times

set -euo pipefail

# =============================
# CONFIG
# =============================
REPO_DIR="$HOME/.local/src"
PATCHES_DIR="$REPO_DIR/patches"
DWM_REPO="https://git.suckless.org/dwm"
ST_REPO="https://git.suckless.org/st"
DMENU_REPO="https://git.suckless.org/dmenu"
SLSTATUS_REPO="https://git.suckless.org/slstatus"

# List of packages to install (kept minimal but usable for a laptop)
PKGS=(
  build-essential git curl wget patch
  xorg xorg-dev x11-xserver-utils xinput
  libx11-dev libxft-dev libxinerama-dev
  xserver-xorg-video-intel
  network-manager-gnome
  pipewire pipewire-audio pipewire-pulse wireplumber pavucontrol
  brightnessctl acpi
  feh dunst picom xterm
  fonts-dejavu fonts-font-awesome
  firefox-esr neovim
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

# =============================
# HELPERS
# =============================
info() { printf "[INFO] %s\n" "$1"; }
warn() { printf "[WARN] %s\n" "$1"; }
error() { printf "[ERROR] %s\n" "$1"; exit 1; }

# Ensure directories
mkdir -p "$REPO_DIR"
mkdir -p "$PATCHES_DIR/dwm"

# =============================
# INSTALL PACKAGES
# =============================
info "Updating APT and installing packages (may prompt for sudo password)..."
sudo apt update && sudo apt full-upgrade -y

# Install packages in a single apt call
sudo apt install -y "${PKGS[@]}"

# Enable NetworkManager service
info "Enabling NetworkManager..."
sudo systemctl enable --now NetworkManager || true

# Enable PipeWire user services (may fail if systemd --user not available in current session)
info "Enabling PipeWire user services (best-effort)..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

# =============================
# FETCH DWm PATCHES (if not already present)
# =============================
info "Downloading dwm patches into $PATCHES_DIR/dwm (if missing)..."
BASE_PATCH_URL="https://dwm.suckless.org/patches"
for p in "${DWM_PATCHES[@]}"; do
  dest="$PATCHES_DIR/dwm/$(basename "$p")"
  if [ -f "$dest" ]; then
    info "Patch $(basename "$p") already present, skipping download"
    continue
  fi
  url="$BASE_PATCH_URL/$(dirname "$p")/$(basename "$p")"
  info "Downloading $url"
  if ! curl -fsSL "$url" -o "$dest"; then
    warn "Failed to download $url — continuing (you can add the patch manually in $PATCHES_DIR/dwm)"
    rm -f "$dest" || true
  fi
done

# =============================
# FUNCTION: clone or update a repo
# =============================
clone_or_update() {
  local repo_url=$1
  local dest=$2
  if [ -d "$dest/.git" ]; then
    info "Pulling latest for $(basename "$dest")"
    git -C "$dest" pull --ff-only || true
  else
    info "Cloning $(basename "$dest")"
    git clone "$repo_url" "$dest"
  fi
}

# =============================
# BUILD & INSTALL SUCKLESS TOOLS
# =============================
build_and_install() {
  local name=$1
  local repo=$2
  local path="$REPO_DIR/$name"

  clone_or_update "$repo" "$path"
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
build_and_install "slstatus" "$SLSTATUS_REPO"
build_and_install "dwm" "$DWM_REPO"

# =============================
# USER CONFIG: .xinitrc and autostart
# =============================
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

