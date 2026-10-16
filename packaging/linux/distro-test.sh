#!/bin/sh
# Runs as root inside a fresh container of a Linux distribution (see
# .github/workflows/release.yml): installs buzz2vlc with its Linux installer,
# letting it install the prerequisites, then checks the result and uninstalls.
#   distro-test.sh /path/to/buzz2vlc-<version>-linux-x86_64-setup.sh
set -eu
setup="$1"

# Minimal container images lack a few tools that every desktop system has.
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq bash tar gzip >/dev/null
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q bash tar gzip >/dev/null
elif command -v zypper >/dev/null 2>&1; then
  zypper --non-interactive --quiet install bash tar gzip gawk >/dev/null
elif command -v pacman >/dev/null 2>&1; then
  pacman -Sy --noconfirm --needed --quiet bash tar gzip >/dev/null
fi

bash "$setup" --yes
echo "--- checks"
/opt/buzz2vlc/buzz2vlc-cli --version > /tmp/version.txt 2>&1 || { cat /tmp/version.txt; exit 1; }
cat /tmp/version.txt
grep -q "^VLC: /" /tmp/version.txt || { echo "VLC was not installed"; exit 1; }
/opt/buzz2vlc/buzz2vlc-cli --selftest > /tmp/selftest.txt 2>&1 || { cat /tmp/selftest.txt; exit 1; }
tail -n 3 /tmp/selftest.txt
test -L /usr/local/bin/buzz2vlc
test -f /usr/local/share/applications/buzz2vlc.desktop
bash "$setup" --yes --no-prerequisites >/dev/null   # a second run replaces the installation
bash "$setup" --uninstall --yes
test ! -e /opt/buzz2vlc
test ! -e /usr/local/bin/buzz2vlc
echo "OK: installed, checked and uninstalled"
