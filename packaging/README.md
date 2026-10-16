# Packaging and releases

Every buzz2vlc release ships the same four packages, built and tested by
[`.github/workflows/release.yml`](../.github/workflows/release.yml):

| File | What it is |
|---|---|
| `buzz2vlc-<v>-windows-x64-setup.exe` | Windows installer (Inno Setup 6, [`windows/buzz2vlc.iss`](windows/buzz2vlc.iss)) |
| `buzz2vlc-<v>-windows-x64-portable.zip` | Windows portable folder |
| `buzz2vlc-<v>-linux-x86_64-setup.sh` | Linux installer ([`linux/setup.sh`](linux/setup.sh) with the portable tar.gz appended) |
| `buzz2vlc-<v>-linux-x86_64-portable.tar.gz` | Linux portable folder |
| `SHA256SUMS.txt` | Checksums of the four |

## What's inside

The program is frozen with PyInstaller ([`buzz2vlc.spec`](buzz2vlc.spec)) into one folder with
two executables that share it ([`entry.py`](entry.py)): `buzz2vlc` (the GUI; no console window
on Windows) and `buzz2vlc-cli` (the command line, the same as `python buzz2vlc.py`). Python,
tkinter, hidapi and requests are inside; README, LICENSE and CONTACT.txt sit next to the
executables and inside (Help -> Manual / About read them). The icon, a red buzzer button, is
drawn by `build.py`.

**VLC media player is not bundled.** buzz2vlc starts the user's VLC as separate processes, so
VLC is a prerequisite that the installers check for and offer to install:

- **Windows** ([`windows/buzz2vlc.iss`](windows/buzz2vlc.iss)): looks for VLC's registry key
  and Program Files folders. If it's missing, a wizard page offers to download
  `vlc-<VLC_VERSION>-win64.exe` from download.videolan.org (only the pinned SHA-256 is
  accepted) and runs it; VLC's own installer asks for administrator rights. Silent installs do
  this with `/INSTALLVLC=1`. buzz2vlc itself installs per user by default
  (`PrivilegesRequired=lowest`); "all users" is offered. The AppId stays the same across
  versions, so a new version replaces the old one in place.
- **Linux** ([`linux/setup.sh`](linux/setup.sh)): checks `vlc`, `wmctrl` and the udev rule
  `/etc/udev/rules.d/70-buzz2vlc.rules` (Buzz receiver access for the signed-in user, both the
  usb and hidraw devices, wired 054c:0002 and wireless 054c:1000), and installs what's missing
  with apt, dnf, zypper or pacman through sudo. It installs into `~/.local/opt/buzz2vlc` (as root
  `/opt/buzz2vlc`), links the commands into `~/.local/bin` (`/usr/local/bin`), adds a desktop
  entry and writes `uninstall.sh` plus a `.buzz2vlc-install` marker. It only ever replaces or
  removes a folder that holds that marker.

The VLC version and its SHA-256 are set in `release.yml` (`VLC_VERSION`, `VLC_SHA256`);
`build.py` checks them against videolan.org's published checksum before it builds the
installer. To offer a newer VLC, update both values from
`https://download.videolan.org/pub/videolan/vlc/<version>/win64/vlc-<version>-win64.exe.sha256`.

## Building locally

```bash
python -m pip install -r packaging/requirements.txt
python packaging/build.py --out /absolute/path/to/out          # Linux, or Windows without the installer
python packaging/build.py --out C:/out --iscc "C:/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    --vlc-version 3.0.24 --vlc-sha256 <hex>                    # Windows with the installer
```

`build.py` builds for the platform it runs on, with 64-bit Python 3.12 (the version CI uses).
It checks every package before writing it: the built program must report its version with
hidapi and requests available and pass `--selftest`; on Linux the installer also installs into
a temporary folder, starts the installed program and uninstalls it.

## Release routine

1. **Version:** set `__version__` in `buzz2vlc.py` and add a `## <version> – <date>` section to
   `CHANGELOG.md` (it becomes the release notes).
2. **Archive the version being replaced** in the vibe repository's `buzz2vlc/archive/`, as its
   README there describes (`git archive` of the current release tag). Nothing there is removed.
3. **Check:** `python buzz2vlc.py --selftest` (CI's `selftest.yml` runs it on every push), and
   optionally a manual run of the release workflow (*Actions -> release -> Run workflow*): it
   builds and tests all four packages without publishing and keeps them as workflow artifacts
   for 14 days.
4. **Commit, push, and check the commit is on GitHub; only then tag:**
   `git tag buzz2vlc-v<version>` and `git push origin buzz2vlc-v<version>`.
5. The tag runs `release.yml`: it checks that the tag matches `__version__`, builds and tests
   the packages (Windows: GUI start, silent install with VLC download, uninstall; Linux: GUI
   start under a virtual display, install with prerequisites, reinstall, uninstall; the
   installer again in fresh Debian, Ubuntu, Fedora, openSUSE and Arch containers) and only
   then publishes the GitHub Release with the four packages and `SHA256SUMS.txt`.
