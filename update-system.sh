#!/usr/bin/env bash
# update-system.sh — Full Arch update: out-of-tree module check, news check, snapshot,
# pacman + AUR, Flatpak, NVIDIA Flatpak runtime check, and reboot reminder.
#
# Usage:
#   update-system            full update (also checks kernel modules first)
#   update-system --modules  only check/rebuild out-of-tree kernel modules
#                            (run this after rebooting into a new kernel)
set -euo pipefail

bold=$'\e[1m'; green=$'\e[32m'; yellow=$'\e[33m'; red=$'\e[31m'; reset=$'\e[0m'
step() { echo; echo "${bold}${green}==>${reset}${bold} $*${reset}"; }
warn() { echo "${yellow}  ! $*${reset}"; }
fail() { echo "${red}  ✗ $*${reset}"; }

# Packages whose update means a reboot (and possibly game issues) is coming
WATCH_PKGS="linux linux-lts nvidia-open-dkms nvidia-utils lib32-nvidia-utils mesa lib32-mesa linux-firmware"

# Non-DKMS AUR packages that ship kernel modules built for ONE kernel version.
# Format: "package:module" — module is checked for the running kernel and the
# package is rebuilt when it's missing.
MODULE_PKGS=("linux-switch2:hid-switch2")

pkg_versions() {
  for p in $WATCH_PKGS; do pacman -Q "$p" 2>/dev/null || true; done
}

# Rebuild out-of-tree modules that are missing for the running kernel.
# These packages build against the RUNNING kernel, so this only works
# after you've rebooted into the new one.
check_kernel_modules() {
  local kver; kver=$(uname -r)
  step "Checking out-of-tree kernel modules for ${kver}"

  if [[ ! -d "/usr/lib/modules/${kver}" ]]; then
    warn "Running kernel ${kver} was replaced by an update — reboot first,"
    warn "then run: update-system --modules"
    return 0
  fi

  local entry pkg mod
  for entry in "${MODULE_PKGS[@]}"; do
    pkg=${entry%%:*}; mod=${entry##*:}
    pacman -Q "$pkg" >/dev/null 2>&1 || continue

    if modinfo -k "$kver" "$mod" >/dev/null 2>&1; then
      echo "  ✓ ${pkg}: ${mod} present for ${kver}"
    else
      warn "${pkg}: ${mod} missing for ${kver} — rebuilding"
      if paru -S --rebuild --noconfirm "$pkg"; then
        sudo depmod -a "$kver"
        sudo modprobe "$mod" || warn "modprobe ${mod} failed — check dmesg"
        echo "  ✓ ${pkg} rebuilt — replug the device"
      else
        fail "Rebuild of ${pkg} failed"
      fi
    fi
  done
}

# --modules: only the module check
if [[ "${1:-}" == "--modules" ]]; then
  check_kernel_modules
  exit 0
fi

# 0. Catch modules missing since the last kernel update + reboot
check_kernel_modules

# 1. Arch news — manual intervention notices show up here
step "Checking Arch Linux news"
if command -v paru >/dev/null; then
  paru -Pw || true
  read -rp "Read the news above? Continue with the update? [Y/n] " ans
  [[ "${ans,,}" == "n" ]] && { echo "Aborted."; exit 0; }
else
  warn "paru not found — check https://archlinux.org/news/ manually"
fi

# 2. Snapshot before touching anything
step "Creating Timeshift snapshot"
if command -v timeshift >/dev/null; then
  sudo timeshift --create --comments "pre-update $(date +%F_%H%M)" --tags O \
    || warn "Snapshot failed — continuing anyway"
else
  warn "Timeshift not installed — no snapshot taken"
fi

before=$(pkg_versions)

# 3. Repo + AUR packages
step "Updating repo and AUR packages"
if command -v paru >/dev/null; then
  paru -Syu
else
  sudo pacman -Syu
fi

after=$(pkg_versions)

# 4. Flatpak apps and runtimes
step "Updating Flatpaks"
flatpak update -y

# 5. Make sure Flatpak has the NVIDIA runtime matching the system driver
step "Checking NVIDIA Flatpak runtime"
if pacman -Q nvidia-utils >/dev/null 2>&1; then
  drv=$(pacman -Q nvidia-utils | awk '{print $2}' | cut -d- -f1)   # e.g. 620.73.04
  tag=${drv//./-}                                                    # e.g. 620-73-04
  missing=()
  for rt in GL GL32; do
    flatpak list --runtime --columns=application | grep -qx "org.freedesktop.Platform.${rt}.nvidia-${tag}" \
      || missing+=("org.freedesktop.Platform.${rt}.nvidia-${tag}")
  done
  if ((${#missing[@]})); then
    warn "Missing Flatpak NVIDIA runtime(s) for driver ${drv} — installing"
    flatpak install -y flathub "${missing[@]}" || fail "Install failed — Flatpak games will use software rendering!"
  else
    echo "  ✓ Flatpak NVIDIA runtimes match driver ${drv}"
  fi
else
  echo "  (no nvidia-utils installed, skipping)"
fi

# 6. Leftover config files
step "Checking for .pacnew files"
pacnew=$(find /etc -name "*.pacnew" 2>/dev/null || true)
if [[ -n "$pacnew" ]]; then
  warn "Found .pacnew files — review with: sudo DIFFPROG='diff -u' pacdiff"
  echo "$pacnew" | sed 's/^/    /'
else
  echo "  ✓ None"
fi

# 7. Summary + reboot reminder
step "Summary"
changed=$(diff <(echo "$before") <(echo "$after") | grep '^>' | sed 's/^> /    /' || true)
if [[ -n "$changed" ]]; then
  warn "Kernel/GPU-related packages changed:"
  echo "$changed"
  warn "Reboot before gaming. Expect some shader recompilation stutter on first launch."
  if echo "$changed" | grep -qE '^\s*linux(-lts)? '; then
    warn "Kernel changed — after rebooting, run: ${bold}update-system --modules${reset}${yellow}"
    warn "(rebuilds linux-switch2 so the Switch 2 controller works again)"
  fi
else
  echo "  ✓ No kernel/driver changes — no reboot needed"
fi
