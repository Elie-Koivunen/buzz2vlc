#!/usr/bin/env bash
# buzz2vlc @VERSION@ - installer for Linux (x86_64)
#
# Installs buzz2vlc for the current user (system-wide when run as root),
# checks the prerequisites -- VLC media player, wmctrl (window control) and
# access to the Buzz receiver -- and offers to install what is missing with
# the system's package manager (apt, dnf, zypper or pacman). The program
# itself is appended to this script as a tar.gz archive.
#
# Usage: ./buzz2vlc-@VERSION@-linux-x86_64-setup.sh [options]
#   --yes                answer yes to every question (unattended install)
#   --no-prerequisites   install buzz2vlc only; just report what is missing
#   --prerequisites-only install only what buzz2vlc needs (VLC, wmctrl, the
#                        Buzz receiver rule), e.g. with sudo before a user install
#   --prefix DIR        install folder (default: ~/.local/opt/buzz2vlc,
#                        or /opt/buzz2vlc as root)
#   --bindir DIR         where the buzz2vlc commands go (default: ~/.local/bin,
#                        or /usr/local/bin as root)
#   --uninstall          remove an installation made by this installer
#   -h, --help           this help
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -u

VERSION="@VERSION@"
MARKER=.buzz2vlc-install
UDEV_RULE=/etc/udev/rules.d/70-buzz2vlc.rules
VLC_DOWNLOAD="https://www.videolan.org/vlc/#download"

if [ "$(id -u)" -eq 0 ]; then
  PREFIX=/opt/buzz2vlc
  BINDIR=/usr/local/bin
  APPDIR=/usr/local/share/applications
else
  PREFIX="$HOME/.local/opt/buzz2vlc"
  BINDIR="$HOME/.local/bin"
  APPDIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
fi
YES=0
PREREQS=1
PREREQS_ONLY=0
UNINSTALL=0

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^if \[ -z/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --no-prerequisites) PREREQS=0 ;;
    --prerequisites-only) PREREQS_ONLY=1 ;;
    --prefix) [ $# -ge 2 ] || die "--prefix needs a folder"; PREFIX="$2"; shift ;;
    --bindir) [ $# -ge 2 ] || die "--bindir needs a folder"; BINDIR="$2"; shift ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
  shift
done
case "$PREFIX" in /*) ;; *) PREFIX="$PWD/$PREFIX" ;; esac
case "$BINDIR" in /*) ;; *) BINDIR="$PWD/$BINDIR" ;; esac

# ask QUESTION DEFAULT(y|n): yes -> 0. --yes answers yes; without a terminal
# the default is taken.
ask() {
  local reply hint="[y/N]"
  [ "$2" = y ] && hint="[Y/n]"
  if [ "$YES" = 1 ]; then say "$1 $hint yes"; return 0; fi
  if [ ! -t 0 ]; then say "$1 $hint $2 (no terminal: default)"; [ "$2" = y ]; return; fi
  read -r -p "$1 $hint " reply || reply=""
  case "${reply:-$2}" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac
}

# Commands that need root: run directly as root, otherwise through sudo
# (which asks for the password on a terminal).
can_root() {
  [ "$(id -u)" -eq 0 ] && return 0
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true 2>/dev/null && return 0
  [ -t 0 ]
}
as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

PM=""
for candidate in apt-get dnf zypper pacman; do
  if command -v "$candidate" >/dev/null 2>&1; then PM="$candidate"; break; fi
done
APT_UPDATED=0
pm_command() {  # the command line that installs the given packages (for messages)
  case "$PM" in
    apt-get) printf 'sudo apt-get install %s' "$*" ;;
    dnf) printf 'sudo dnf install %s' "$*" ;;
    zypper) printf 'sudo zypper install %s' "$*" ;;
    pacman) printf 'sudo pacman -S %s' "$*" ;;
  esac
}
pm_install() {
  case "$PM" in
    apt-get)
      if [ "$APT_UPDATED" = 0 ]; then as_root apt-get update -qq || true; APT_UPDATED=1; fi
      as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) as_root dnf install -y "$@" ;;
    zypper) as_root zypper --non-interactive install "$@" ;;
    pacman) as_root pacman -S --needed --noconfirm "$@" ;;
    *) return 1 ;;
  esac
}

# --- uninstall ---------------------------------------------------------------
if [ "$UNINSTALL" = 1 ]; then
  [ -f "$PREFIX/$MARKER" ] || die "no buzz2vlc installation in $PREFIX (use --prefix)"
  ask "Remove buzz2vlc from $PREFIX?" y || exit 1
  exec bash "$PREFIX/uninstall.sh"
fi

# --- unpack ------------------------------------------------------------------
[ "$(uname -m)" = x86_64 ] || die "this package is for x86_64 Linux; this machine is $(uname -m)"
for tool in tar gzip awk tail; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is needed to unpack the installer"
done
TMP=$(mktemp -d "${TMPDIR:-/tmp}/buzz2vlc-setup.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$TMP"' EXIT
payload_line=$(awk '/^__BUZZ2VLC_PAYLOAD__$/ { print NR + 1; exit }' "$0")
[ -n "$payload_line" ] || die "the installer is incomplete (no program inside)"
tail -n +"$payload_line" "$0" | tar -xzf - -C "$TMP" || die "the installer is damaged (unpacking failed)"
SOURCE="$TMP/buzz2vlc-$VERSION"
[ -x "$SOURCE/buzz2vlc" ] || die "the installer is damaged (no program inside)"

if [ "$PREREQS_ONLY" = 1 ]; then
  say "buzz2vlc $VERSION installer: prerequisites only (buzz2vlc itself is not installed)"
  say ""
  PREREQS=1
else
  say "buzz2vlc $VERSION installer"
  say "  install folder: $PREFIX"
  say "  commands:       $BINDIR/buzz2vlc, $BINDIR/buzz2vlc-cli"
  say ""

  # --- license ---------------------------------------------------------------
  say "buzz2vlc is licensed under the PolyForm Noncommercial License 1.0.0:"
  say "free for any noncommercial use; commercial use needs separate permission."
  say "Full text: https://polyformproject.org/licenses/noncommercial/1.0.0 (also LICENSE in the install folder)."
  ask "Do you accept the license terms?" n || die "the license was not accepted; nothing was installed"
  say ""
fi

# --- prerequisites -----------------------------------------------------------
have_vlc() { command -v vlc >/dev/null 2>&1; }
have_wmctrl() { command -v wmctrl >/dev/null 2>&1; }
udev_in_use() { command -v udevadm >/dev/null 2>&1; }
have_rule() { [ -f "$UDEV_RULE" ] || [ -f /usr/lib/udev/rules.d/70-buzz2vlc.rules ] || [ -f /lib/udev/rules.d/70-buzz2vlc.rules ]; }

report() {
  say "Prerequisites:"
  if have_vlc; then say "  [ok]      VLC media player: $(command -v vlc)"
  else say "  [missing] VLC media player (required: buzz2vlc plays your playlists in VLC)"; fi
  if have_wmctrl; then say "  [ok]      wmctrl (window focus, identify and tiling)"
  else say "  [missing] wmctrl (optional: window focus, identify and tiling on X11)"; fi
  if ! udev_in_use; then say "  [n/a]     Buzz receiver access (no udev on this system)"
  elif have_rule; then say "  [ok]      Buzz receiver access ($UDEV_RULE)"
  else say "  [missing] Buzz receiver access for your user (a udev rule)"; fi
}
report
say ""

install_rule() {
  local rule
  rule='# buzz2vlc: lets the signed-in user read the PlayStation Buzz! receiver
# (wired 054c:0002, wireless 054c:1000) without root.
SUBSYSTEM=="usb", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0002", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="1000", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0002", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="1000", TAG+="uaccess"'
  printf '%s\n' "$rule" | as_root tee "$UDEV_RULE" >/dev/null || return 1
  as_root udevadm control --reload-rules 2>/dev/null || true
  as_root udevadm trigger --subsystem-match=usb --subsystem-match=hidraw 2>/dev/null || true
}

if [ "$PREREQS" = 1 ]; then
  if ! have_vlc || ! have_wmctrl || { udev_in_use && ! have_rule; }; then
    if ! can_root; then
      warn "installing prerequisites needs root (sudo), which is not available here; to do it yourself:"
      missing=""
      have_vlc || missing="vlc"
      have_wmctrl || missing="$missing wmctrl"
      if [ -n "$missing" ]; then
        if [ -n "$PM" ]; then say "  $(pm_command $missing)"; else say "  install$missing with your package manager ($VLC_DOWNLOAD)"; fi
      fi
      say "  or everything at once (VLC, wmctrl and the Buzz receiver rule): sudo bash $0 --prerequisites-only"
    else
      if ! have_vlc; then
        if [ -z "$PM" ]; then
          warn "no supported package manager found; install VLC yourself: $VLC_DOWNLOAD"
        elif ask "Install VLC media player now ($(pm_command vlc))?" y; then
          pm_install vlc || warn "VLC could not be installed with $PM (on Fedora, VLC may need the RPM Fusion repository); see $VLC_DOWNLOAD"
        fi
      fi
      if ! have_wmctrl && [ -n "$PM" ] && ask "Install wmctrl for window focus and tiling ($(pm_command wmctrl))?" y; then
        pm_install wmctrl || warn "wmctrl could not be installed with $PM"
      fi
      if udev_in_use && ! have_rule && ask "Let your user read the Buzz receiver (adds $UDEV_RULE)?" y; then
        install_rule || warn "the udev rule could not be written"
      fi
    fi
    say ""
  fi
fi
if [ "$PREREQS_ONLY" = 1 ]; then
  report
  have_vlc  # exit status: 0 once VLC, the one required prerequisite, is there
  exit $?
fi

# --- install -----------------------------------------------------------------
if [ -e "$PREFIX" ]; then
  if [ -f "$PREFIX/$MARKER" ]; then
    say "Replacing the installed buzz2vlc $(sed -n 's/^version=//p' "$PREFIX/$MARKER") with $VERSION."
  elif [ -d "$PREFIX" ] && [ -z "$(ls -A "$PREFIX")" ]; then
    :
  else
    die "$PREFIX exists and is not a buzz2vlc installation; choose another folder with --prefix"
  fi
fi
mkdir -p "$(dirname "$PREFIX")" || die "cannot create $(dirname "$PREFIX")"
STAGING="$PREFIX.new.$$"
cp -a "$SOURCE" "$STAGING" || die "cannot copy the program to $(dirname "$PREFIX")"
if [ -d "$PREFIX" ]; then rm -rf "$PREFIX"; fi
mv "$STAGING" "$PREFIX" || die "cannot create $PREFIX"

DESKTOP="$APPDIR/buzz2vlc.desktop"
{
  printf 'version=%s\nprefix=%s\nbindir=%s\ndesktop=%s\ninstalled=%s\n' \
    "$VERSION" "$PREFIX" "$BINDIR" "$DESKTOP" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$PREFIX/$MARKER"

# The uninstaller, with this installation's paths written into it.
{
  printf '#!/usr/bin/env bash\n'
  printf '# Removes buzz2vlc %s. Your settings (~/.buzz2vlc.json) are kept.\n' "$VERSION"
  printf 'PREFIX=%q\nBINDIR=%q\nDESKTOP=%q\nUDEV_RULE=%q\n' "$PREFIX" "$BINDIR" "$DESKTOP" "$UDEV_RULE"
  cat <<'UNINSTALL'
[ -f "$PREFIX/.buzz2vlc-install" ] || { echo "not a buzz2vlc installation: $PREFIX" >&2; exit 1; }
for exe in buzz2vlc buzz2vlc-cli; do
  if [ -L "$BINDIR/$exe" ] && [ "$(readlink "$BINDIR/$exe")" = "$PREFIX/$exe" ]; then rm -f "$BINDIR/$exe"; fi
done
rm -f "$DESKTOP"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null
rm -rf "$PREFIX"
echo "buzz2vlc was removed. Your settings (~/.buzz2vlc.json) were kept."
if [ -f "$UDEV_RULE" ]; then
  echo "The Buzz receiver rule stays in place; to remove it too: sudo rm $UDEV_RULE"
fi
UNINSTALL
} > "$PREFIX/uninstall.sh"
chmod 755 "$PREFIX/uninstall.sh"

mkdir -p "$BINDIR" || die "cannot create $BINDIR"
for exe in buzz2vlc buzz2vlc-cli; do
  if [ -e "$BINDIR/$exe" ] && [ ! -L "$BINDIR/$exe" ]; then
    warn "$BINDIR/$exe exists and is not a link; left as it is"
  else
    ln -sfn "$PREFIX/$exe" "$BINDIR/$exe"
  fi
done

mkdir -p "$APPDIR" && cat > "$DESKTOP" <<DESKTOPENTRY
[Desktop Entry]
Type=Application
Name=buzz2vlc
GenericName=Buzz controller for VLC
Comment=Control several VLC players, each with its own playlist, with a PS2/PS3 Buzz controller
Exec="$PREFIX/buzz2vlc"
Icon=$PREFIX/buzz2vlc.png
Terminal=false
Categories=AudioVideo;Player;
Keywords=VLC;Buzz;controller;quiz;playlist;
DESKTOPENTRY
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPDIR" 2>/dev/null

# --- check -------------------------------------------------------------------
say ""
say "Installed buzz2vlc $VERSION in $PREFIX."
if CHECK=$("$PREFIX/buzz2vlc-cli" --version 2>&1); then
  printf '%s\n' "$CHECK" | sed 's/^/  /'
else
  warn "the installed program did not start:"
  printf '%s\n' "$CHECK" | sed 's/^/  /' >&2
  exit 1
fi
case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) warn "$BINDIR is not on your PATH; start buzz2vlc from the applications menu or as $PREFIX/buzz2vlc" ;;
esac
say ""
say "Start it from the applications menu (buzz2vlc) or with: buzz2vlc"
say "Remove it with: $PREFIX/uninstall.sh"
have_vlc || say "Remember to install VLC media player: $VLC_DOWNLOAD"
exit 0
__BUZZ2VLC_PAYLOAD__
