#!/usr/bin/env python3
"""Build runtime-colourable scooter layers from semantic SVG masters."""

from __future__ import annotations

import argparse
import copy
import json
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


def blend_mode(element: ET.Element) -> str:
    for declaration in element.get("style", "").split(";"):
        name, separator, value = declaration.partition(":")
        if separator and name.strip() == "mix-blend-mode":
            return {
                "soft-light": "softLight",
            }.get(value.strip(), value.strip())
    return "srcOver"


def remove_blend_modes(root: ET.Element) -> None:
    for element in root.iter():
        declarations = [
            declaration.strip()
            for declaration in element.get("style", "").split(";")
            if declaration.strip()
            and declaration.partition(":")[0].strip() != "mix-blend-mode"
        ]
        if declarations:
            element.set("style", ";".join(declarations))
        else:
            element.attrib.pop("style", None)


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


def render_cropped(root: ET.Element, destination: Path) -> dict[str, object]:
    with tempfile.TemporaryDirectory() as temp_dir:
        full_path = Path(temp_dir) / "full.png"
        render(root, full_path)
        with Image.open(full_path) as source:
            image = source.convert("RGBA")
            bounds = image.getchannel("A").getbbox()
            if bounds is None:
                bounds = (0, 0, 1, 1)
            image.crop(bounds).save(destination, "PNG", optimize=True)
    left, top, right, bottom = bounds
    return {
        "asset": f"images/scooter/{destination.name}",
        "x": left,
        "y": top,
        "width": right - left,
        "height": bottom - top,
    }


def effect_groups(leaves: list[ET.Element], start: int, end: int) -> list[tuple[set[int], str, bool]]:
    groups: list[tuple[set[int], str, bool]] = []
    for index in range(start, end):
        leaf = leaves[index]
        mode = blend_mode(leaf)
        matte_only = "url(#pattern" in leaf.get("fill", "")
        if groups and mode == "srcOver" and groups[-1][1:] == (mode, matte_only):
            groups[-1][0].add(index)
        else:
            groups.append(({index}, mode, matte_only))
    return groups


def build_layers(source_file: Path, output: Path, view: str) -> dict[str, object]:
    root = wrap_source(source_file, view)
    leaves = drawing_leaves(root)
    paint_indices = [index for index, leaf in enumerate(leaves) if leaf.get("fill", "").upper() == PLACEHOLDER]
    if len(paint_indices) != 3:
        raise ValueError(f"expected three {view} paint paths, found {len(paint_indices)}")

    shadow = ground_shadow(next(child for child in root if local_name(child) != "defs"))
    shadow_index = next(index for index, leaf in enumerate(leaves) if leaf in set(shadow.iter()))
    manifest: dict[str, object] = {
        "width": SIZES[view][0],
        "height": SIZES[view][1],
        "shadow": render_cropped(
            select_leaves(root, {shadow_index}), output / f"custom_{view}_shadow.png"
        ),
    }

    under_indices = set(range(paint_indices[0])) - {shadow_index}
    manifest["under"] = render_cropped(
        select_leaves(root, under_indices), output / f"custom_{view}_under.png"
    )

    paint_layers: list[dict[str, object]] = []
    for layer, paint_index in enumerate(paint_indices):
        next_paint = paint_indices[layer + 1] if layer + 1 < len(paint_indices) else len(leaves)
        paint = render_cropped(
            select_leaves(root, {paint_index}, mask=True),
            output / f"custom_{view}_paint_{layer}.png",
        )
        effects: list[dict[str, object]] = []
        for effect, (indices, mode, matte_only) in enumerate(
            effect_groups(leaves, paint_index + 1, next_paint)
        ):
            effect_root = select_leaves(root, indices)
            remove_blend_modes(effect_root)
            effect_data = render_cropped(
                effect_root,
                output / f"custom_{view}_effect_{layer}_{effect}.png",
            )
            effect_data["blendMode"] = mode
            if matte_only:
                effect_data["matteOnly"] = True
            effects.append(effect_data)
        paint_layers.append({"paint": paint, "effects": effects})
    manifest["paintLayers"] = paint_layers
    return manifest


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
    for pattern in ("custom_*_effect_*.png", "custom_*_over_*.png"):
        for stale in args.output.glob(pattern):
            stale.unlink()
    manifest = {
        "version": 1,
        "views": {
            "front": build_layers(args.source / "mode=scooter.svg", args.output, "front"),
            "side": build_layers(args.source / "side_master.svg", args.output, "side"),
        },
    }
    (args.output / "custom_artwork_layers.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    build_hover(args.source, args.output)


if __name__ == "__main__":
    main()
