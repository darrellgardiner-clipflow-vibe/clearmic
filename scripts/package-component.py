#!/usr/bin/env python3
"""Build fixed-location packages; never relocate into a developer's build folder."""
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
mode = sys.argv[1]
if mode not in {"driver", "all"}:
    raise SystemExit("Expected driver or all")
version = os.environ.get("CLEARMIC_VERSION", "0.1.0")
output = (root / "build/ClearMic.app/Contents/Resources/ClearMicDriver.pkg" if mode == "driver"
          else root / f"build/ClearMic-{version}.pkg")
with tempfile.TemporaryDirectory(prefix="clearmic-package-") as temporary:
    stage = pathlib.Path(temporary)
    payload = stage / "payload"
    targets = [("ClearMic.driver", "Library/Audio/Plug-Ins/HAL")]
    if mode == "all":
        targets.append(("ClearMic.app", "Applications"))
    for name, destination in targets:
        parent = payload / destination
        parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ditto", str(root / "build" / name), str(parent / name)], check=True)
    components = stage / "components.plist"
    subprocess.run(["pkgbuild", "--analyze", "--root", str(payload), str(components)], check=True)
    with components.open("rb") as stream:
        info = plistlib.load(stream)
    for component in info:
        component["BundleIsRelocatable"] = False
        component["BundleHasStrictIdentifier"] = True
    with components.open("wb") as stream:
        plistlib.dump(info, stream)
    subprocess.run(["pkgbuild", "--root", str(payload), "--component-plist", str(components),
                    "--identifier", "org.clearmic.driver" if mode == "driver" else "org.clearmic.installer",
                    "--version", version, "--install-location", "/", "--ownership", "recommended",
                    str(output)], check=True)
