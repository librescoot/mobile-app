#!/usr/bin/env python3
"""Build runtime-colourable scooter layers from semantic SVG masters."""

from __future__ import annotations

import argparse
import copy
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
PLACEHOLDER = "#FF00DD"
SIZES = {"front": (866, 1800), "side": (2110, 1738)}
FRONT_SOURCE_WIDTH = 1135
FRONT_TOP = 86
SIDE_SOURCE_WIDTH = 1095
SIDE_HOVER_TOP = 889

ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", XLINK_NS)


def local_name(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def definitions(root: ET.Element) -> ET.Element:
    return next(child for child in root if local_name(child) == "defs")


def remove_artboard(root: ET.Element) -> None:
    for child in list(root):
        if child.get("stroke", "").upper() == "#9747FF":
            root.remove(child)


def ground_shadow(root: ET.Element) -> ET.Element:
    return next(
        child
        for child in root
        if local_name(child) == "g" and "filter0_" in child.get("filter", "")
    )


def wrap_source(source: Path, view: str, *, hover: bool = False) -> ET.Element:
    source_root = ET.parse(source).getroot()
    remove_artboard(source_root)
    source_defs = copy.deepcopy(definitions(source_root))

    if view == "side":
        children = [
            copy.deepcopy(child)
            for index, child in enumerate(source_root)
            if local_name(child) != "defs" and (hover or index < 42)
        ]
        translate_y = -SIDE_HOVER_TOP * (SIZES[view][0] / SIDE_SOURCE_WIDTH) if hover else 0
        scale = SIZES[view][0] / SIDE_SOURCE_WIDTH
    else:
        children = [copy.deepcopy(child) for child in source_root if local_name(child) != "defs"]
        translate_y = FRONT_TOP
        scale = SIZES[view][0] / FRONT_SOURCE_WIDTH

    width, height = SIZES[view]
    output_root = ET.Element(
        f"{{{SVG_NS}}}svg",
        {
            "width": str(width),
            "height": str(height),
            "viewBox": f"0 0 {width} {height}",
            "fill": "none",
        },
    )
    transform = ET.SubElement(
        output_root,
        f"{{{SVG_NS}}}g",
        {"transform": f"translate(0 {translate_y}) scale({scale})"},
    )
    transform.extend(children)
    output_root.append(source_defs)
    return output_root


def drawing_leaves(root: ET.Element) -> list[ET.Element]:
    leaves: list[ET.Element] = []

    def visit(element: ET.Element) -> None:
        if local_name(element) == "defs":
            return
        children = list(element)
        if not children:
            leaves.append(element)
            return
        for child in children:
            visit(child)

    visit(root)
    return leaves


def select_leaves(root: ET.Element, selected: set[int], *, mask: bool = False) -> ET.Element:
    result = copy.deepcopy(root)
    index = 0

    def prune(parent: ET.Element) -> None:
        nonlocal index
        for child in list(parent):
            if local_name(child) == "defs":
                continue
            if not list(child):
                keep = index in selected
                index += 1
                if not keep:
                    parent.remove(child)
                elif mask:
                    child.set("fill", "white")
                    for attribute in ("fill-opacity", "opacity", "filter", "style"):
                        child.attrib.pop(attribute, None)
            else:
                prune(child)
                if not list(child):
                    parent.remove(child)
                elif mask:
                    child.attrib.pop("filter", None)
                    child.attrib.pop("style", None)

    prune(result)
    return result


def remove_texture_overlays(root: ET.Element) -> None:
    for parent in root.iter():
        for child in list(parent):
            if "url(#pattern" in child.get("fill", ""):
                parent.remove(child)


def replace_placeholder(root: ET.Element, colour: str) -> None:
    for element in root.iter():
        if element.get("fill", "").upper() == PLACEHOLDER:
            element.set("fill", colour)


def render(root: ET.Element, destination: Path, *, webp: bool = False) -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        svg_path = Path(temp_dir) / "layer.svg"
        png_path = Path(temp_dir) / "layer.png"
        ET.ElementTree(root).write(svg_path, encoding="utf-8", xml_declaration=True)
        subprocess.run(["rsvg-convert", "-o", png_path, svg_path], check=True)
        if webp:
            subprocess.run(
                ["cwebp", "-lossless", "-exact", "-quiet", png_path, "-o", destination],
                check=True,
            )
        else:
            with Image.open(png_path) as image:
                image.save(destination, "PNG", optimize=True)


def build_layers(source_file: Path, output: Path, view: str) -> None:
    root = wrap_source(source_file, view)
    leaves = drawing_leaves(root)
    paint_indices = [index for index, leaf in enumerate(leaves) if leaf.get("fill", "").upper() == PLACEHOLDER]
    if len(paint_indices) != 3:
        raise ValueError(f"expected three {view} paint paths, found {len(paint_indices)}")

    shadow = ground_shadow(next(child for child in root if local_name(child) != "defs"))
    shadow_index = next(index for index, leaf in enumerate(leaves) if leaf in set(shadow.iter()))
    render(select_leaves(root, {shadow_index}), output / f"custom_{view}_shadow.png")

    under_indices = set(range(paint_indices[0])) - {shadow_index}
    render(select_leaves(root, under_indices), output / f"custom_{view}_under.png")

    for layer, paint_index in enumerate(paint_indices):
        next_paint = paint_indices[layer + 1] if layer + 1 < len(paint_indices) else len(leaves)
        render(
            select_leaves(root, {paint_index}, mask=True),
            output / f"custom_{view}_paint_{layer}.png",
        )
        overlay_indices = set(range(paint_index + 1, next_paint))
        matte = select_leaves(root, overlay_indices)
        render(matte, output / f"custom_{view}_over_{layer}_matte.png")
        gloss = copy.deepcopy(matte)
        remove_texture_overlays(gloss)
        render(gloss, output / f"custom_{view}_over_{layer}_gloss.png")


def build_hover(source: Path, output: Path) -> None:
    front = wrap_source(source / "mode=hover.svg", "front", hover=True)
    replace_placeholder(front, "#C8F8FA")
    render(front, output / "base_9.webp", webp=True)

    side = wrap_source(source / "side_master.svg", "side", hover=True)
    replace_placeholder(side, "#C8F8FA")
    render(side, output / "side_9.webp", webp=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Directory containing the exported SVG masters")
    parser.add_argument("output", type=Path, help="Runtime artwork directory")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    build_layers(args.source / "mode=scooter.svg", args.output, "front")
    build_layers(args.source / "side_master.svg", args.output, "side")
    build_hover(args.source, args.output)


if __name__ == "__main__":
    main()
