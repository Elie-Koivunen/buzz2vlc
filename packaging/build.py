"""Builds buzz2vlc's release packages on the platform it runs on.

Windows:  buzz2vlc-<version>-windows-x64-portable.zip
          buzz2vlc-<version>-windows-x64-setup.exe     (with --iscc: Inno Setup 6)
Linux:    buzz2vlc-<version>-linux-x86_64-portable.tar.gz
          buzz2vlc-<version>-linux-x86_64-setup.sh

    python packaging/build.py --out DIR [--work DIR]
    python packaging/build.py --out DIR --iscc ISCC.exe --vlc-version 3.0.24 --vlc-sha256 HEX

Needs the packages in packaging/requirements.txt. Every package is checked before it is
written: the built program must report its version with hidapi and requests available
and pass --selftest; on Linux the installer also installs into a temporary folder,
starts the installed program and uninstalls it again.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
IS_WINDOWS = sys.platform == "win32"
sys.path.insert(0, str(ROOT))
from buzz2vlc import __version__  # noqa: E402

DOCS = ("README.md", "LICENSE", "CONTACT.txt")
EXE = ".exe" if IS_WINDOWS else ""


def log(message: str) -> None:
    print(f"[build] {message}", flush=True)


def platform_tag() -> str:
    if struct.calcsize("P") != 8:
        raise SystemExit("build with a 64-bit Python")
    if IS_WINDOWS:
        return "windows-x64"
    if sys.platform.startswith("linux"):
        return f"linux-{platform.machine()}"
    raise SystemExit(f"no packages are made for {sys.platform}")


def render_icon(work: Path) -> tuple[Path, Path]:
    """The program's icon, a red buzzer button: a 256 px PNG (Linux menu entry)
    and a multi-size .ico (Windows executables, shortcuts and installer)."""
    from PIL import Image, ImageDraw

    def draw(size: int) -> Image.Image:
        s = size * 4  # drawn large, then scaled down: smooth edges
        image = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        pen = ImageDraw.Draw(image)
        pen.ellipse([s * 0.03, s * 0.03, s * 0.97, s * 0.97], fill=(64, 64, 70, 255))  # housing
        pen.ellipse([s * 0.12, s * 0.12, s * 0.88, s * 0.88], fill=(150, 20, 24, 255))  # button rim
        pen.ellipse([s * 0.16, s * 0.14, s * 0.84, s * 0.82], fill=(224, 40, 44, 255))  # button
        pen.ellipse([s * 0.30, s * 0.22, s * 0.62, s * 0.42], fill=(255, 255, 255, 80))  # shine
        return image.resize((size, size), Image.LANCZOS)

    png = work / "buzz2vlc.png"
    draw(256).save(png)
    ico = work / "buzz2vlc.ico"
    draw(256).save(ico, format="ICO", sizes=[(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 128, 256)])
    return png, ico


def run_pyinstaller(work: Path, ico: Path) -> Path:
    env = dict(os.environ, BUZZ2VLC_ICON=str(ico) if IS_WINDOWS else "")
    subprocess.run(
        [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--log-level", "WARN",
         "--distpath", str(work / "dist"), "--workpath", str(work / "pyi"), str(HERE / "buzz2vlc.spec")],
        check=True, env=env, cwd=ROOT,
    )
    return work / "dist" / "buzz2vlc"


def run_program(exe: Path, *args: str, config: Path) -> str:
    """Runs the built command line with a config file of its own (never the
    build machine's ~/.buzz2vlc.json) and returns its output."""
    env = dict(os.environ, BUZZ2VLC_CONFIG=str(config))
    done = subprocess.run([str(exe), *args], capture_output=True, text=True, env=env, timeout=300)
    output = done.stdout + done.stderr
    if done.returncode != 0:
        raise SystemExit(f"{exe.name} {' '.join(args)} failed ({done.returncode}):\n{output}")
    return output


def check_program(app_dir: Path, work: Path) -> None:
    config = work / "check-config.json"  # not created: the program uses its defaults
    report = run_program(app_dir / f"buzz2vlc-cli{EXE}", "--version", config=config)
    log("built program reports:\n  " + report.strip().replace("\n", "\n  "))
    for expected in (f"buzz2vlc {__version__}", "hidapi: available", "requests: available"):
        if expected not in report:
            raise SystemExit(f"the built program's --version lacks {expected!r}")
    if not IS_WINDOWS:  # the GUI executable answers command-line arguments too (see entry.py)
        run_program(app_dir / "buzz2vlc", "--version", config=config)
    selftest = run_program(app_dir / f"buzz2vlc-cli{EXE}", "--selftest", config=config)
    log("built program's self-test: " + [line for line in selftest.splitlines() if line.startswith("Ran ")][-1])


def portable_zip(app_dir: Path, out: Path, tag: str) -> Path:
    path = out / f"buzz2vlc-{__version__}-{tag}-portable.zip"
    top = f"buzz2vlc-{__version__}"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for file in sorted(app_dir.rglob("*")):
            if file.is_file():
                archive.write(file, f"{top}/{file.relative_to(app_dir).as_posix()}")
    return path


def portable_tar(app_dir: Path, out: Path, tag: str) -> Path:
    path = out / f"buzz2vlc-{__version__}-{tag}-portable.tar.gz"

    def owner_neutral(info: tarfile.TarInfo) -> tarfile.TarInfo:
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        return info

    with tarfile.open(path, "w:gz", compresslevel=9) as archive:
        archive.add(app_dir, arcname=f"buzz2vlc-{__version__}", filter=owner_neutral)
    return path


def linux_setup(portable: Path, out: Path, tag: str, work: Path) -> Path:
    """The Linux installer: packaging/linux/setup.sh with the portable tar.gz appended."""
    script = (HERE / "linux" / "setup.sh").read_bytes().replace(b"\r\n", b"\n")
    script = script.replace(b"@VERSION@", __version__.encode()).rstrip(b"\n")
    if not script.endswith(b"\n__BUZZ2VLC_PAYLOAD__"):
        raise SystemExit("packaging/linux/setup.sh must end with the __BUZZ2VLC_PAYLOAD__ line")
    path = out / f"buzz2vlc-{__version__}-{tag}-setup.sh"
    path.write_bytes(script + b"\n" + portable.read_bytes())
    path.chmod(0o755)
    trial_install(path, work)
    return path


def trial_install(setup: Path, work: Path) -> None:
    """Installs into a temporary folder (prerequisites only reported, nothing
    system-wide), runs the installed program, then uninstalls."""
    trial = work / "trial"
    shutil.rmtree(trial, ignore_errors=True)
    env = dict(os.environ, XDG_DATA_HOME=str(trial / "share"), BUZZ2VLC_CONFIG=str(trial / "config.json"))
    prefix, bindir = trial / "opt" / "buzz2vlc", trial / "bin"
    done = subprocess.run(["bash", str(setup), "--yes", "--no-prerequisites", "--prefix", str(prefix),
                           "--bindir", str(bindir)], capture_output=True, text=True, env=env, timeout=300)
    if done.returncode != 0:
        raise SystemExit(f"the installer failed ({done.returncode}):\n{done.stdout}{done.stderr}")
    for needed in (bindir / "buzz2vlc", bindir / "buzz2vlc-cli", trial / "share" / "applications" / "buzz2vlc.desktop",
                   prefix / "uninstall.sh", prefix / ".buzz2vlc-install"):
        if not needed.exists():
            raise SystemExit(f"the installer did not create {needed}")
    run_program(bindir / "buzz2vlc-cli", "--version", config=trial / "config.json")
    done = subprocess.run(["bash", str(prefix / "uninstall.sh")], capture_output=True, text=True, env=env)
    if done.returncode != 0 or prefix.exists() or (bindir / "buzz2vlc").is_symlink():
        raise SystemExit(f"the uninstaller left buzz2vlc behind:\n{done.stdout}{done.stderr}")
    log("installer: trial install, start and uninstall passed")


def check_vlc_download(version: str, sha256: str) -> None:
    """The VLC installer the Windows setup offers must exist on videolan.org with
    exactly the pinned SHA-256 (the setup refuses any other file)."""
    url = f"https://download.videolan.org/pub/videolan/vlc/{version}/win64/vlc-{version}-win64.exe.sha256"
    with urllib.request.urlopen(url, timeout=60) as response:
        published = response.read().decode().split()[0].lower()
    if published != sha256.lower():
        raise SystemExit(f"VLC {version}: videolan.org publishes SHA-256 {published}, not {sha256}")
    log(f"VLC {version} installer on videolan.org matches the pinned SHA-256")


def windows_setup(app_dir: Path, out: Path, ico: Path, iscc: Path, vlc_version: str, vlc_sha256: str) -> Path:
    check_vlc_download(vlc_version, vlc_sha256)
    subprocess.run(
        [str(iscc), "/Q", f"/DAppVersion={__version__}", f"/DSourceDir={app_dir}", f"/DRepoDir={ROOT}",
         f"/DIconFile={ico}", f"/DOutputDir={out}", f"/DVlcVersion={vlc_version}",
         f"/DVlcSha256={vlc_sha256.lower()}", str(HERE / "windows" / "buzz2vlc.iss")],
        check=True,
    )
    path = out / f"buzz2vlc-{__version__}-windows-x64-setup.exe"
    if not path.exists():
        raise SystemExit(f"Inno Setup did not write {path.name}")
    return path


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, required=True, help="folder for the packages (absolute)")
    parser.add_argument("--work", type=Path, help="scratch folder (default: a new temporary folder)")
    parser.add_argument("--iscc", type=Path, help="Windows: Inno Setup 6's ISCC.exe, to build the installer too")
    parser.add_argument("--vlc-version", help="Windows installer: the VLC version it offers to download")
    parser.add_argument("--vlc-sha256", help="Windows installer: SHA-256 of that VLC installer")
    args = parser.parse_args()
    if not args.out.is_absolute() or (args.work and not args.work.is_absolute()):
        parser.error("--out and --work must be absolute paths")
    if args.iscc and not (IS_WINDOWS and args.vlc_version and args.vlc_sha256):
        parser.error("--iscc is for Windows and needs --vlc-version and --vlc-sha256")

    tag = platform_tag()
    work = args.work or Path(tempfile.mkdtemp(prefix="buzz2vlc-build-"))
    work.mkdir(parents=True, exist_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    log(f"buzz2vlc {__version__} for {tag}; work folder {work}")

    png, ico = render_icon(work)
    app_dir = run_pyinstaller(work, ico)
    for name in DOCS:
        shutil.copy2(ROOT / name, app_dir / name)
    shutil.copy2(png, app_dir / "buzz2vlc.png")
    check_program(app_dir, work)

    made = []
    if IS_WINDOWS:
        made.append(portable_zip(app_dir, args.out, tag))
        if args.iscc:
            made.append(windows_setup(app_dir, args.out, ico, args.iscc, args.vlc_version, args.vlc_sha256))
    else:
        portable = portable_tar(app_dir, args.out, tag)
        made += [portable, linux_setup(portable, args.out, tag, work)]
    for path in made:
        log(f"{path.name}  {path.stat().st_size / 1e6:.1f} MB  sha256 {sha256_of(path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
