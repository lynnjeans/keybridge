#!/usr/bin/env python3
"""Writes an example clipboard history for the website's screenshots.

Usage: sample-clipboard.py <folder> <en|zh-Hans|ja>

The folder gets the layout ClipboardStore reads (index.json plus one binary
plist per item), so a Debug build launched with KB_DEBUG_CLIPBOARD_FOLDER
pointing at it shows these copies instead of the user's own.
"""
import json
import os
import plistlib
import struct
import sys
import time
import uuid
import zlib

STRING = "public.utf8-plain-text"
FILE_URL = "public.file-url"
PNG = "public.png"

TEXTS = {
    "en": [
        ("com.apple.mail", "Meeting moved to Thursday, 3 pm — same room."),
        ("com.apple.Safari", "https://github.com/lynnjeans/keybridge"),
        ("com.apple.Notes", "Flight KL 1234 · seat 14A · confirmation QX7P2L"),
        ("com.apple.TextEdit", "Thanks for the quick reply! I'll send the draft tonight."),
    ],
    "zh-Hans": [
        ("com.apple.mail", "会议改到周四下午 3 点，地点不变。"),
        ("com.apple.Safari", "https://github.com/lynnjeans/keybridge"),
        ("com.apple.Notes", "航班 CA 1234 · 座位 14A · 预订号 QX7P2L"),
        ("com.apple.TextEdit", "谢谢你这么快回复！今晚把初稿发给你。"),
    ],
    "ja": [
        ("com.apple.mail", "会議は木曜日の15時に変更になりました。場所は同じです。"),
        ("com.apple.Safari", "https://github.com/lynnjeans/keybridge"),
        ("com.apple.Notes", "JL 1234 便 · 座席 14A · 予約番号 QX7P2L"),
        ("com.apple.TextEdit", "早速のご返信ありがとうございます。今夜ドラフトをお送りします。"),
    ],
}

FILES = {
    "en": "Quarterly Report.pdf",
    "zh-Hans": "季度报告.pdf",
    "ja": "四半期レポート.pdf",
}


def png(width=240, height=150):
    """A small bar chart, drawn here so no picture of anyone else's ends up on the site."""
    bars = [0.45, 0.7, 0.55, 0.9, 0.75]
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            colour = (246, 247, 249)
            slot = x * len(bars) // width
            inside = 12 < x % (width // len(bars)) < width // len(bars) - 12
            if inside and height - y < bars[slot] * (height - 20):
                colour = (10, 132, 255)
            row += bytes(colour)
        rows.append(bytes(row))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))


def main():
    folder, language = sys.argv[1], sys.argv[2]
    items_folder = os.path.join(folder, "items")
    os.makedirs(items_folder, exist_ok=True)

    texts = TEXTS[language]
    file_url = "file:///Users/Shared/" + FILES[language].replace(" ", "%20")
    items = [
        (texts[0][0], {STRING: texts[0][1].encode()}),
        ("com.apple.Preview", {PNG: png()}),
        (texts[1][0], {STRING: texts[1][1].encode()}),
        ("com.apple.finder", {FILE_URL: file_url.encode(), STRING: FILES[language].encode()}),
        (texts[2][0], {STRING: texts[2][1].encode()}),
        (texts[3][0], {STRING: texts[3][1].encode()}),
    ]

    # Foundation dates count seconds from 2001-01-01.
    now = time.time() - 978307200
    entries = []
    for number, (source, contents) in enumerate(items):
        item_id = str(uuid.uuid4()).upper()
        with open(os.path.join(items_folder, item_id + ".plist"), "wb") as out:
            plistlib.dump(contents, out, fmt=plistlib.FMT_BINARY)
        entries.append({
            "id": item_id,
            "date": now - 90 - number * 600,
            "sourceBundleID": source,
            "isPinned": number == 4,
        })
    with open(os.path.join(folder, "index.json"), "w") as out:
        json.dump({"version": 1, "items": entries}, out)


main()
