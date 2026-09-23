#!/usr/bin/env python3
"""Build locally tintable scooter artwork layers from design exports."""

from __future__ import annotations

import argparse
import copy
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np
from PIL import Image

SIZES = {"front": (866, 1800), "side": (2110, 1738)}
SOURCE_COLORS = {"matte": "#A4A4A4", "gloss": "#F9F9F9"}


def rgba(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32)


def paint_alpha(source: Path, view: str) -> np.ndarray:
    tree = ET.parse(source / f"{view}_6.svg")
    root = tree.getroot()
    definitions = next(child for child in root if child.tag.rsplit("}", 1)[-1] == "defs")
    painted = [
        copy.deepcopy(element)
        for element in root.iter()
        if element.get("fill", "").upper() == "#11255A"
    ]
    for child in list(root):
        root.remove(child)
    for element in painted:
        element.set("fill", "white")
        element.attrib.pop("filter", None)
        element.attrib.pop("style", None)
        root.append(element)
    root.append(definitions)

    width, height = SIZES[view]
    with tempfile.TemporaryDirectory() as temporary:
        mask_svg = Path(temporary) / "mask.svg"
        mask_png = Path(temporary) / "mask.png"
        tree.write(mask_svg, encoding="utf-8", xml_declaration=True)
        subprocess.run(
            ["rsvg-convert", "-w", str(width), "-h", str(height), "-o", str(mask_png), str(mask_svg)],
            check=True,
        )
        geometry_alpha = rgba(mask_png)[:, :, 3] / 255

    matte_difference = np.max(
        np.abs(rgba(source / f"{view}_2.png")[:, :, :3] - rgba(source / f"{view}_4.png")[:, :, :3]),
        axis=2,
    )
    gloss_difference = np.max(
        np.abs(rgba(source / f"{view}_1.png")[:, :, :3] - rgba(source / f"{view}_6.png")[:, :, :3]),
        axis=2,
    )
    visible_paint = np.clip((np.maximum(matte_difference, gloss_difference) - 1) / 6, 0, 1)
    return geometry_alpha * visible_paint


def shadow_layer(source: Path, view: str, destination: Path) -> np.ndarray:
    tree = ET.parse(source / f"{view}_6.svg")
    root = tree.getroot()
    children = list(root)
    for child in children:
        if child is not children[0] and child.tag.rsplit("}", 1)[-1] != "defs":
            root.remove(child)

    width, height = SIZES[view]
    with tempfile.TemporaryDirectory() as temporary:
        shadow_svg = Path(temporary) / "shadow.svg"
        tree.write(shadow_svg, encoding="utf-8", xml_declaration=True)
        rendered_shadow = Path(temporary) / "rendered-shadow.png"
        subprocess.run(
            [
                "rsvg-convert",
                "-w",
                str(width),
                "-h",
                str(height),
                "-o",
                str(rendered_shadow),
                str(shadow_svg),
            ],
            check=True,
        )
        rendered = rgba(rendered_shadow)

    reference = rgba(source / f"{view}_6.png")
    visible = (reference[:, :, 3] <= rendered[:, :, 3] + 5) & (rendered[:, :, 3] > 0)
    shadow = np.zeros_like(reference)
    shadow[visible] = reference[visible]
    Image.fromarray(np.rint(shadow).astype(np.uint8), "RGBA").save(destination, optimize=True)
    return shadow


def tone_layer(source: Path, view: str, finish: str, alpha: np.ndarray) -> np.ndarray:
    source_id = 3 if finish == "matte" else 1
    image = rgba(source / f"{view}_{source_id}.png")
    color = SOURCE_COLORS[finish]
    rgb = np.array([int(color[index : index + 2], 16) for index in (1, 3, 5)], dtype=np.float32)
    reference_luminance = np.dot(rgb, [0.2126, 0.7152, 0.0722])
    luminance = np.dot(image[:, :, :3], [0.2126, 0.7152, 0.0722])
    tone = np.clip(luminance / reference_luminance, 0, 1)

    output = np.empty_like(image, dtype=np.uint8)
    output[:, :, :3] = np.rint(tone[:, :, None] * 255).astype(np.uint8)
    output[:, :, 3] = np.rint(alpha * 255).astype(np.uint8)
    return output


def build_view(source: Path, output: Path, view: str) -> None:
    alpha = paint_alpha(source, view)
    shadow_path = output / f"custom_{view}_shadow.png"
    shadow = shadow_layer(source, view, shadow_path)

    base = rgba(source / f"{view}_1.png")
    base[:, :, 3] *= 1 - alpha
    visible_shadow = (base[:, :, 3] <= shadow[:, :, 3] + 5) & (shadow[:, :, 3] > 0)
    base[visible_shadow] = 0
    Image.fromarray(np.rint(base).astype(np.uint8), "RGBA").save(
        output / f"custom_{view}_base.png", optimize=True
    )

    for finish in ("matte", "gloss"):
        Image.fromarray(tone_layer(source, view, finish, alpha), "RGBA").save(
            output / f"custom_{view}_{finish}.png", optimize=True
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Directory containing front_N and side_N SVG/PNG exports")
    parser.add_argument("output", type=Path, help="Runtime artwork directory")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for view in SIZES:
        build_view(args.source, args.output, view)


if __name__ == "__main__":
    main()
