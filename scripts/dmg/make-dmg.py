"""Packs KeyBridge.app into a DMG that opens as a laid-out window (KB-233):
KeyBridge alone, the "Double-click KeyBridge to install" hint from
background.swift under it, and KeyBridge's icon on the volume. There is no
Applications shortcut to drag to: opened from its disk image, KeyBridge
installs itself there and opens (MoveToApplications.swift).

    make-dmg.py <KeyBridge.app> <background.tiff> <volume name> <out.dmg>

Finder's window settings are written straight into the volume's .DS_Store,
so this needs no Finder scripting and runs unattended. It uses the ds_store
and mac_alias packages (release.sh installs them into build/dmg-venv), the
same ones dmgbuild is built on. dmgbuild itself puts the background at the
volume's root as .background.tiff, which Finder in macOS 26 no longer shows;
in a .background folder, as Finder itself would put it, it does.
"""
import os
import subprocess
import sys
import tempfile

from ds_store import DSStore
from mac_alias import Alias

# The window's content size and the icon's centre, in points from its top
# left. background.swift draws for the same numbers.
WIDTH, HEIGHT = 520, 380
TITLE_BAR = 28
APP_CENTRE = (260, 150)
ICON_SIZE = 128


def run(*command):
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)


def main(app, background, volume_name, output):
    app_name = os.path.basename(app)
    with tempfile.TemporaryDirectory() as work:
        image = os.path.join(work, "rw.dmg")
        size_mb = int(subprocess.check_output(["du", "-sm", app]).split()[0]) + 20
        run("hdiutil", "create", "-quiet", "-size", f"{size_mb}m", "-fs", "HFS+",
            "-volname", volume_name, "-type", "UDIF", image)
        # Mounted by its own name: the background's alias records the volume
        # name, and a second volume of the same name would get " 1" added.
        mount = os.path.join("/Volumes", volume_name)
        if os.path.exists(mount):
            sys.exit(f"error: {mount} is already mounted; eject it first")
        run("hdiutil", "attach", "-quiet", "-nobrowse", "-noautoopen", image)
        try:
            # ditto keeps the app exactly as signed and stapled.
            run("ditto", app, os.path.join(mount, app_name))
            os.mkdir(os.path.join(mount, ".background"))
            picture = os.path.join(mount, ".background", "background.tiff")
            run("ditto", background, picture)

            icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
            if os.path.exists(icon):
                run("ditto", icon, os.path.join(mount, ".VolumeIcon.icns"))
                run("SetFile", "-a", "C", mount)

            write_view(mount, app_name, picture)
            # Opens the window when the DMG is mounted. Not every Mac allows
            # it; the DMG still works without.
            subprocess.run(["bless", "--folder", mount, "--openfolder", mount],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        finally:
            run("hdiutil", "detach", "-quiet", mount)
        if os.path.exists(output):
            os.remove(output)
        run("hdiutil", "convert", "-quiet", image, "-format", "UDZO",
            "-imagekey", "zlib-level=9", "-o", output)


def write_view(mount, app_name, picture):
    left, top = 200, 120
    with DSStore.open(os.path.join(mount, ".DS_Store"), "w+") as store:
        store["."]["bwsp"] = {
            "WindowBounds": f"{{{{{left}, {top}}}, {{{WIDTH}, {HEIGHT + TITLE_BAR}}}}}",
            "ShowToolbar": False, "ShowTabView": False, "ShowStatusBar": False,
            "ShowPathbar": False, "ShowSidebar": False, "ContainerShowSidebar": False,
            "PreviewPaneVisibility": False, "SidebarWidth": 180,
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1,
            "backgroundType": 2,  # a picture
            "backgroundImageAlias": Alias.for_file(picture).to_bytes(),
            "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
            "arrangeBy": "none", "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
            "iconSize": float(ICON_SIZE), "textSize": 13.0, "labelOnBottom": True,
            "showIconPreview": False, "showItemInfo": False,
            "scrollPositionX": 0.0, "scrollPositionY": 0.0,
        }
        store["."]["vSrn"] = ("long", 1)
        store["."]["icvl"] = ("type", b"icnv")
        store[app_name]["Iloc"] = APP_CENTRE


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
