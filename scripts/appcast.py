#!/usr/bin/env python3
"""Adds a release to SameKeys's Sparkle appcast (KB-101).

    scripts/appcast.py --appcast site/appcast.xml --version 1.0.0 --build 5 \\
        --url https://github.com/lynnjeans/samekeys/releases/download/v1.0.0/SameKeys-1.0.0.dmg \\
        --length 4194304 --signature <edSignature from sign_update> \\
        --notes release-notes/1.0.0 [--critical]

The release notes are three short HTML fragments, en.html, zh-Hans.html and
ja.html, in the --notes folder; Sparkle shows the one matching the app's
language. The newest item goes first and only the last three are kept: Sparkle
needs just the newest one, the others help anyone reading the feed.

Refuses a build number that is not higher than the newest one already in the
appcast, since Sparkle compares build numbers (CFBundleVersion), and refuses
missing notes. Uses only the standard library, so it runs on any Mac.
"""

import argparse
import email.utils
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"
LANGUAGES = ["en", "zh-Hans", "ja"]
MINIMUM_SYSTEM = "14.0"
KEEP = 3

ET.register_namespace("sparkle", SPARKLE)


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def sparkle(tag):
    return f"{{{SPARKLE}}}{tag}"


def load(path):
    if path.exists():
        tree = ET.parse(path)
        channel = tree.getroot().find("channel")
        if channel is None:
            fail(f"{path} has no <channel>")
        return tree, channel
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "SameKeys"
    ET.SubElement(channel, "link").text = "https://samekeys.com/"
    ET.SubElement(channel, "description").text = "SameKeys updates"
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(rss), channel


def main():
    parser = argparse.ArgumentParser(description="Add a release to the appcast.")
    parser.add_argument("--appcast", type=Path, required=True)
    parser.add_argument("--version", required=True, help="MARKETING_VERSION, shown to the user")
    parser.add_argument("--build", required=True, type=int, help="CURRENT_PROJECT_VERSION, compared by Sparkle")
    parser.add_argument("--url", required=True, help="where the DMG is downloaded from")
    parser.add_argument("--length", required=True, type=int, help="the DMG's size in bytes")
    parser.add_argument("--signature", required=True, help="sparkle:edSignature from sign_update")
    parser.add_argument("--notes", required=True, type=Path, help="folder with en.html, zh-Hans.html, ja.html")
    parser.add_argument("--critical", action="store_true", help="show at once and do not allow skipping")
    args = parser.parse_args()

    notes = {}
    for language in LANGUAGES:
        file = args.notes / f"{language}.html"
        if not file.is_file() or not file.read_text(encoding="utf-8").strip():
            fail(f"release notes missing: {file}")
        notes[language] = file.read_text(encoding="utf-8").strip()

    tree, channel = load(args.appcast)
    items = channel.findall("item")
    builds = [int(item.findtext(sparkle("version"), "0")) for item in items]
    if builds and args.build <= max(builds):
        fail(f"build {args.build} is not newer than build {max(builds)} already in {args.appcast}; "
             "raise CURRENT_PROJECT_VERSION in project.yml")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"SameKeys {args.version}"
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, sparkle("version")).text = str(args.build)
    ET.SubElement(item, sparkle("shortVersionString")).text = args.version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = MINIMUM_SYSTEM
    if args.critical:
        ET.SubElement(item, sparkle("criticalUpdate"))
    for language in LANGUAGES:
        description = ET.SubElement(item, "description", {XML_LANG: language})
        description.text = notes[language]
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        "length": str(args.length),
        "type": "application/octet-stream",
        sparkle("edSignature"): args.signature,
    })

    # Newest first, after the channel's own elements.
    first = items[0] if items else None
    index = list(channel).index(first) if first is not None else len(channel)
    channel.insert(index, item)
    for old in channel.findall("item")[KEEP:]:
        channel.remove(old)

    ET.indent(tree, space="  ")
    args.appcast.parent.mkdir(parents=True, exist_ok=True)
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)
    print(f"Added SameKeys {args.version} ({args.build}) to {args.appcast}")


if __name__ == "__main__":
    main()
