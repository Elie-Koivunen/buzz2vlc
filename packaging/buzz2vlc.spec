# PyInstaller spec for buzz2vlc. Run it through packaging/build.py, which sets
# BUZZ2VLC_ICON and turns the result into the release packages.
#
# One folder ("onedir"), not one file: starts fast and needs no unpacking to a
# temp folder. Two executables share it: buzz2vlc (the GUI; no console window
# on Windows) and buzz2vlc-cli (the command line). See entry.py.
import os
import sys
from pathlib import Path

HERE = Path(SPECPATH)
ROOT = HERE.parent
ICON = os.environ.get("BUZZ2VLC_ICON") or None

# Help -> Manual and Help -> About read these next to the program's modules.
datas = [(str(ROOT / name), ".") for name in ("README.md", "CONTACT.txt", "LICENSE")]

a = Analysis(
    [str(HERE / "entry.py")],
    pathex=[str(ROOT)],
    datas=datas,
    # entry.py imports them inside main(); hid is imported in a try block
    hiddenimports=["buzz2vlc", "buzz2vlc_gui", "hid"],
    excludes=["pytest", "setuptools", "pip"],
    noarchive=False,
)
pyz = PYZ(a.pure)

gui = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name="buzz2vlc",
    console=sys.platform != "win32",
    icon=ICON,
)
cli = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name="buzz2vlc-cli",
    console=True,
    icon=ICON,
)

COLLECT(gui, cli, a.binaries, a.datas, name="buzz2vlc")
