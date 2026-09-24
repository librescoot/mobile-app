#!/usr/bin/env python3
"""Build front-view blinker overlays from the exported SVG."""

from __future__ import annotations

import argparse
import copy
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

SVG_NS = "http://www.w3.org/2000/svg"
FRONT_SIZE = (866, 1800)
FRONT_SCALE = FRONT_SIZE[0] / 1135
FRONT_TOP = 86

ET.register_namespace("", SVG_NS)


def local_name(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def write_overlay(output: Path, group: ET.Element, definitions: ET.Element) -> None:
    root = ET.Element(
        f"{{{SVG_NS}}}svg",
        {
            "width": str(FRONT_SIZE[0]),
            "height": str(FRONT_SIZE[1]),
            "viewBox": f"0 0 {FRONT_SIZE[0]} {FRONT_SIZE[1]}",
            "fill": "none",
        },
    )
    master = ET.SubElement(
        root,
        f"{{{SVG_NS}}}g",
        {"transform": f"translate(0 {FRONT_TOP}) scale({FRONT_SCALE})"},
    )
    blinker = ET.SubElement(
        master,
        f"{{{SVG_NS}}}g",
        {"transform": "translate(243.451 983.375)"},
    )
    blinker.append(copy.deepcopy(group))
    root.append(copy.deepcopy(definitions))

    with tempfile.TemporaryDirectory() as temp_dir:
        svg_path = Path(temp_dir) / "blinker.svg"
        png_path = Path(temp_dir) / "blinker.png"
        ET.ElementTree(root).write(svg_path, encoding="utf-8", xml_declaration=True)
        subprocess.run(["rsvg-convert", "-o", png_path, svg_path], check=True)
        with Image.open(png_path) as image:
            image.save(output, "WEBP", lossless=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Blinker.svg export")
    parser.add_argument("output", type=Path, help="Runtime artwork directory")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    root = ET.parse(args.source).getroot()
    groups = [child for child in root if local_name(child) == "g"]
    definitions = next(child for child in root if local_name(child) == "defs")
    for group, name in zip(groups, ("blinker_r.webp", "blinker_l.webp")):
        write_overlay(args.output / name, group, definitions)


if __name__ == "__main__":
    main()
