#!/usr/bin/env bash
# Print which part of Herdr this machine gets, one word:
#   app   the desktop app (macOS, and Linux that boots to a desktop); its installer
#         also installs herdr-core, and the app keeps both up to date
#   core  herdr-core (hc) only: headless Linux, driven from another machine over SSH
#   none  nothing
# Linux counts as a desktop when a display manager is enabled (gdm, sddm and lightdm
# all provide display-manager.service) or this shell runs in a graphical login
# (XDG_SESSION_TYPE x11/wayland; SSH logins are "tty").
# Not used: graphical.target (Ubuntu cloud images and Lima VMs default to it too) and
# DISPLAY (ssh -X sets it on headless hosts).
# Override with HERDR_MODE=app|core|none.
# Usage: scripts/herdr-mode.sh
set -euo pipefail

if [[ -n ${HERDR_MODE:-} ]]; then
  case $HERDR_MODE in
    app | core | none) echo "$HERDR_MODE"; exit 0 ;;
    *) echo "HERDR_MODE must be app, core or none" >&2; exit 2 ;;
  esac
fi

case $(uname -s) in
  Darwin) echo app ;;
  Linux)
    if systemctl is-enabled --quiet display-manager.service 2>/dev/null ||
      [[ ${XDG_SESSION_TYPE:-} == x11 || ${XDG_SESSION_TYPE:-} == wayland ]]; then
      echo app
    else
      echo core
    fi
    ;;
  *) echo none ;;
esac
