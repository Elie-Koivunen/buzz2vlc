# Changelog

## 1.0.0 – 2026-10-16

The first numbered release, and the first with ready-to-run packages for Windows and Linux.

- **Installers.** `buzz2vlc-1.0.0-windows-x64-setup.exe` installs for your user without
  administrator rights, with a Start menu entry, an optional desktop icon and an uninstaller.
  When VLC media player is missing it offers to download VLC 3.0.24's official 64-bit
  installer package (MSI) from videolan.org, accepted only with the expected SHA-256 checksum,
  and installs it.
  `buzz2vlc-1.0.0-linux-x86_64-setup.sh` checks for VLC, wmctrl and access to the Buzz receiver
  (a udev rule), offers to install what's missing with apt, dnf, zypper or pacman, and installs
  buzz2vlc with a menu entry and an uninstaller.
- **Portable packages.** `buzz2vlc-1.0.0-windows-x64-portable.zip` and
  `buzz2vlc-1.0.0-linux-x86_64-portable.tar.gz`: unpack and run, nothing is installed.
- **No Python needed** for the packages: they contain the program, hidapi and requests.
  `buzz2vlc` opens the GUI and `buzz2vlc-cli` is the command line.
- **`--version`** prints the version and what the installation can use: hidapi, requests, the
  VLC it would start, and window control. The GUI shows the version in its title and in
  Help -> About.
- **Release workflow.** Every version tag builds the four packages, tests each one (the
  self-test, the GUI opening, a full install and uninstall on Windows and on five Linux
  distributions) and publishes them as a GitHub Release.

Earlier, unnumbered versions are archived in the
[vibe repository](https://github.com/Elie-Koivunen/vibe/tree/main/buzz2vlc/archive).
