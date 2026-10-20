#!/usr/bin/env python3
"""Publish only full archives, preserving each release's URL and signature."""
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
path = sys.argv[1]
feed = ET.parse(path)
for item in feed.findall("./channel/item"):
    version = item.findtext(f"{{{SPARKLE}}}shortVersionString")
    enclosure = item.find("enclosure")
    if not version or enclosure is None:
        raise ValueError("An update is missing its version or full archive")
    enclosure.set("url", f"https://github.com/darrellgardiner-clipflow-vibe/clearmic/releases/download/v{version}/ClearMic-{version}.zip")
    deltas = item.find(f"{{{SPARKLE}}}deltas")
    if deltas is not None:
        item.remove(deltas)
ET.indent(feed, space="    ")
feed.write(path, encoding="utf-8", xml_declaration=True)
