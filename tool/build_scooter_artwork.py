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
from PIL import Image, ImageFilter

SIZES = {"front": (866, 1800), "side": (2110, 1738)}
SOURCE_COLORS = {"matte": "#A4A4A4", "gloss": "#F9F9F9"}
FRONT_MASTER_SIZE = (866, 1668)
FRONT_MASTER_TOP = 86


def rgba(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32)


def pad_front_master(image: np.ndarray) -> np.ndarray:
    padded = np.zeros((SIZES["front"][1], SIZES["front"][0], 4), dtype=image.dtype)
    padded[FRONT_MASTER_TOP : FRONT_MASTER_TOP + FRONT_MASTER_SIZE[1]] = image
    return padded


def render_svg_elements(
    tree: ET.ElementTree,
    elements: list[ET.Element],
    size: tuple[int, int],
) -> np.ndarray:
    root = copy.deepcopy(tree.getroot())
    definitions = next(child for child in root if child.tag.rsplit("}", 1)[-1] == "defs")
    for child in list(root):
        root.remove(child)
    for element in elements:
        root.append(copy.deepcopy(element))
    root.append(definitions)

    with tempfile.TemporaryDirectory() as temporary:
        svg = Path(temporary) / "selection.svg"
        png = Path(temporary) / "selection.png"
        ET.ElementTree(root).write(svg, encoding="utf-8", xml_declaration=True)
        subprocess.run(
            ["rsvg-convert", "-w", str(size[0]), "-h", str(size[1]), "-o", str(png), str(svg)],
            check=True,
        )
        return rgba(png)


def front_master_gloss(source: Path) -> np.ndarray:
    tree = ET.parse(source / "front_master.svg")
    root = tree.getroot()
    for parent in root.iter():
        for child in list(parent):
            if "url(#pattern" in child.get("fill", ""):
                parent.remove(child)
    for element in root.iter():
        if element.get("fill", "").upper() == "#0F0F0F":
            element.set("fill", "white")
    elements = [child for child in root if child.tag.rsplit("}", 1)[-1] != "defs"]
    return pad_front_master(render_svg_elements(tree, elements, FRONT_MASTER_SIZE))


def front_master_masks(source: Path) -> tuple[np.ndarray, np.ndarray]:
    tree = ET.parse(source / "front_master.svg")
    children = list(tree.getroot())
    body = copy.deepcopy(
        next(
            element
            for element in children
            if element.tag.rsplit("}", 1)[-1] == "path"
            and element.get("fill", "").upper() == "#0F0F0F"
        )
    )
    body.set("fill", "white")
    body.attrib.pop("style", None)
    fender_group = next(
        element
        for element in children
        if element.tag.rsplit("}", 1)[-1] == "g"
        and any(child.get("fill", "").upper() == "#0F0F0F" for child in element)
    )
    fender = copy.deepcopy(
        next(child for child in fender_group if child.get("fill", "").upper() == "#0F0F0F")
    )
    fender.set("fill", "white")
    headlight_index = next(
        index
        for index, element in enumerate(children)
        if any(child.get("fill", "").upper() == "#1F1F1F" for child in element)
    )
    paint = render_svg_elements(tree, [body, fender], FRONT_MASTER_SIZE)
    foreground = render_svg_elements(tree, children[headlight_index:-1], FRONT_MASTER_SIZE)
    return pad_front_master(paint)[:, :, 3] / 255, pad_front_master(foreground)[:, :, 3] / 255


def paint_alpha(source: Path, view: str) -> np.ndarray:
    if view == "front" and (source / "front_master.svg").exists():
        return front_master_masks(source)[0]

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
    use_master = view == "front" and (source / "front_master.svg").exists()
    tree = ET.parse(source / ("front_master.svg" if use_master else f"{view}_6.svg"))
    root = tree.getroot()
    children = list(root)
    for child in children:
        if child is not children[0] and child.tag.rsplit("}", 1)[-1] != "defs":
            root.remove(child)

    width, height = FRONT_MASTER_SIZE if use_master else SIZES[view]
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

    if use_master:
        rendered = pad_front_master(rendered)
        reference = pad_front_master(rgba(source / "front_master@2x.png"))
    else:
        reference = rgba(source / f"{view}_6.png")
    visible = (reference[:, :, 3] <= rendered[:, :, 3] + 5) & (rendered[:, :, 3] > 0)
    shadow = np.zeros_like(reference)
    shadow[visible] = reference[visible]
    Image.fromarray(np.rint(shadow).astype(np.uint8), "RGBA").save(destination, optimize=True)
    return shadow


def tone_layer(source: Path, view: str, finish: str, alpha: np.ndarray) -> np.ndarray:
    use_master_matte = view == "front" and finish == "matte" and (source / "front_master@2x.png").exists()
    use_master_gloss = view == "front" and finish == "gloss" and (source / "front_master.svg").exists()
    if use_master_matte:
        image = pad_front_master(rgba(source / "front_master@2x.png"))
        color = "#2F2F2F"
    elif use_master_gloss:
        image = front_master_gloss(source)
        color = "#F9F9F9"
    else:
        source_id = 3 if finish == "matte" else 1
        image = rgba(source / f"{view}_{source_id}.png")
        color = SOURCE_COLORS[finish]
    rgb = np.array([int(color[index : index + 2], 16) for index in (1, 3, 5)], dtype=np.float32)
    reference_luminance = np.dot(rgb, [0.2126, 0.7152, 0.0722])
    luminance = np.dot(image[:, :, :3], [0.2126, 0.7152, 0.0722])
    tone = np.clip(luminance / reference_luminance, 0, 1)
    if use_master_matte:
        smoothed = np.asarray(
            Image.fromarray(np.rint(tone * 255).astype(np.uint8), "L").filter(
                ImageFilter.GaussianBlur(18)
            ),
            dtype=np.float32,
        ) / 255
        tone = 0.5 + 0.5 * smoothed + 0.1 * (tone - smoothed)
        tone = np.clip(tone, 0, 1)

    output = np.empty_like(image, dtype=np.uint8)
    output[:, :, :3] = np.rint(tone[:, :, None] * 255).astype(np.uint8)
    output[:, :, 3] = np.rint(alpha * 255).astype(np.uint8)
    return output


def build_view(source: Path, output: Path, view: str) -> None:
    alpha = paint_alpha(source, view)
    shadow_path = output / f"custom_{view}_shadow.png"
    shadow = shadow_layer(source, view, shadow_path)

    use_master = view == "front" and (source / "front_master@2x.png").exists()
    if use_master:
        base = pad_front_master(rgba(source / "front_master@2x.png"))
        foreground_alpha = front_master_masks(source)[1]
        base[:, :, 3] *= 1 - alpha * (1 - foreground_alpha)
    else:
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
