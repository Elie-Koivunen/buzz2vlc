"""Entry point of the packaged program.

Both executables are built from this one script and share the same files:
- buzz2vlc-cli: the command line, exactly like `python buzz2vlc.py ...`
- buzz2vlc: the GUI (`python buzz2vlc_gui.py`); given any command-line
  argument it acts as the command line too, so `buzz2vlc --version` works
  on Linux, where both are console programs anyway.
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    cli = Path(sys.executable).stem.lower().endswith("-cli") or len(sys.argv) > 1
    if cli:
        import buzz2vlc

        return buzz2vlc.main()
    import buzz2vlc_gui

    return buzz2vlc_gui.main()


if __name__ == "__main__":
    raise SystemExit(main())
