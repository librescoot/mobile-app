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

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, gaussian_filter

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


def full_layer_alpha(output: Path, layer: dict[str, object], size: tuple[int, int]) -> np.ndarray:
    alpha = np.zeros((size[1], size[0]), dtype=np.float32)
    with Image.open(output / Path(str(layer["asset"])).name) as source:
        cropped = np.array(source.convert("RGBA"), dtype=np.uint8)[..., 3] / 255
    x, y = int(layer["x"]), int(layer["y"])
    width, height = int(layer["width"]), int(layer["height"])
    alpha[y : y + height, x : x + width] = cropped
    return alpha


def save_alpha_layer(
    destination: Path,
    alpha: np.ndarray,
    colour: tuple[int, int, int],
) -> dict[str, object]:
    alpha_image = Image.fromarray(np.clip(alpha * 255, 0, 255).astype(np.uint8), "L")
    bounds = alpha_image.getbbox() or (0, 0, 1, 1)
    rgba = Image.new("RGBA", alpha_image.size, (*colour, 0))
    rgba.putalpha(alpha_image)
    rgba.crop(bounds).save(destination, "PNG", optimize=True)
    left, top, right, bottom = bounds
    return {
        "asset": f"images/scooter/{destination.name}",
        "x": left,
        "y": top,
        "width": right - left,
        "height": bottom - top,
        "blendMode": "screen",
    }


def build_gloss(
    output: Path,
    manifest: dict[str, object],
    view: str,
) -> None:
    width, height = SIZES[view]
    paint_layers = manifest["paintLayers"]
    assert isinstance(paint_layers, list)
    masks = [
        full_layer_alpha(output, paint_layer["paint"], (width, height))
        for paint_layer in paint_layers
    ]
    combined = np.maximum.reduce(masks)
    surfaces = (
        [masks[0], np.maximum(masks[1], masks[2])]
        if view == "front"
        else masks
    )
    contour = np.zeros((height, width), dtype=np.float32)
    sweep = np.zeros_like(contour)
    y_grid, x_grid = np.mgrid[:height, :width]

    for index, mask in enumerate(surfaces):
        inside = mask > 0.02
        ys, xs = np.nonzero(inside)
        x0, x1 = xs.min(), xs.max()
        y0, y1 = ys.min(), ys.max()
        distance = distance_transform_edt(inside)
        distance_scale = np.percentile(distance[inside], 97) or 1
        bulge = np.clip(distance / distance_scale, 0, 1) ** 0.58
        if view == "front":
            surface_blur = 7 if index == 0 else 3
            normal_strength = 22 if index == 0 else 11
        else:
            surface_blur = max(3, round(min(x1 - x0, y1 - y0) / 90))
            normal_strength = 18
        surface = gaussian_filter(bulge * mask, surface_blur)

        gradient_y, gradient_x = np.gradient(surface)
        normal_x = -gradient_x * normal_strength
        normal_y = -gradient_y * normal_strength
        normal_z = np.ones_like(normal_x)
        normal_length = np.sqrt(
            normal_x * normal_x + normal_y * normal_y + normal_z * normal_z
        )
        normal_x /= normal_length
        normal_y /= normal_length
        normal_z /= normal_length

        normal_half = np.clip(
            normal_x * -0.30 + normal_y * -0.40 + normal_z * 0.865,
            0,
            1,
        )
        sharp = normal_half**30
        broad = normal_half**7
        if view == "front":
            inset = 15 if index == 0 else 6
        else:
            inset = max(6, round(min(x1 - x0, y1 - y0) * 0.026))
        inset_width = max(3, round(inset * 0.52))
        edge_gate = np.clip((distance - 3) / inset, 0, 1) ** 0.8
        inset_rim = np.exp(-((distance - inset) / inset_width) ** 2) * inside
        slope = np.sqrt(normal_x * normal_x + normal_y * normal_y)
        light_facing = np.clip(
            (-0.66 * normal_x - 0.75 * normal_y) / (slope + 1e-6),
            0,
            1,
        ) ** 0.7
        local_x = (x_grid - x0) / max(x1 - x0, 1)
        local_y = (y_grid - y0) / max(y1 - y0, 1)
        lit_side = np.clip((0.82 - local_x) / 0.58, 0, 1)
        lit_height = np.clip((0.90 - local_y) / 0.58, 0, 1)
        local = np.clip(0.72 * sharp + 0.20 * broad + 0.12 * inset_rim, 0, 1)
        local *= light_facing * lit_side * lit_height * edge_gate * mask
        contour = np.maximum(contour, local)

        reflected_center = x0 + (x1 - x0) * (0.28 + 0.12 * (local_y - 0.25))
        if view == "front" and index == 0:
            nose_y = np.exp(-((y_grid - 731) / 185) ** 2)
            reflected_center -= 86 * nose_y
            nose_core = np.exp(
                -(
                    ((x_grid - 433) / 145) ** 2
                    + ((y_grid - 731) / 164) ** 2
                )
                * 2.2
            )
            stripe_width = 43
        else:
            nose_core = 0
            stripe_width = max(
                10 if view == "front" else 14,
                (x1 - x0) * (0.09 if view == "front" else 0.075),
            )
        stripe = np.exp(-((x_grid - reflected_center) / stripe_width) ** 2)
        taper = np.sin(np.clip(local_y, 0, 1) * np.pi) ** 0.7
        stripe *= taper * np.clip(bulge * 1.5, 0, 1) * edge_gate * mask
        stripe *= 1 - 0.92 * nose_core
        sweep = np.maximum(sweep, stripe)

    bloom = gaussian_filter(np.clip(contour * 0.75 + sweep * 0.65, 0, 1), 7)
    bloom *= combined
    gloss_layers = [
        save_alpha_layer(
            output / f"custom_{view}_gloss_bloom.png",
            np.clip(bloom * 0.32, 0, 0.30),
            (225, 238, 255),
        ),
        save_alpha_layer(
            output / f"custom_{view}_gloss_contour.png",
            np.clip(contour * 0.92, 0, 0.88),
            (255, 255, 255),
        ),
        save_alpha_layer(
            output / f"custom_{view}_gloss_sweep.png",
            np.clip(sweep * 0.70, 0, 0.70),
            (245, 250, 255),
        ),
    ]
    final_effects = paint_layers[-1]["effects"]
    assert isinstance(final_effects, list) and final_effects
    manifest["glossBefore"] = final_effects[-1]["asset"]
    manifest["glossLayers"] = gloss_layers


def replace_front_tire(
    reference: Path,
    destination: Path,
    layer: dict[str, object],
) -> None:
    with Image.open(reference) as source:
        target_height = round(source.height * SIZES["front"][0] / source.width)
        scaled = source.convert("RGBA").resize(
            (SIZES["front"][0], target_height), Image.Resampling.LANCZOS
        )
    aligned = Image.new("RGBA", SIZES["front"])
    aligned.alpha_composite(scaled, (0, FRONT_TOP))
    with Image.open(destination) as tire:
        alpha = tire.convert("RGBA").getchannel("A")
    x, y = int(layer["x"]), int(layer["y"])
    bounds = (x, y, x + int(layer["width"]), y + int(layer["height"]))
    replacement = aligned.crop(bounds).convert("L").convert("RGBA")
    replacement.putalpha(alpha)
    replacement.save(destination, "PNG", optimize=True)


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
        effect_number = 0
        for indices, mode, matte_only in effect_groups(
            leaves, paint_index + 1, next_paint
        ):
            fills = {leaves[index].get("fill", "") for index in indices}
            if view == "front" and any("paint30_radial" in fill for fill in fills):
                continue
            effect_root = select_leaves(root, indices)
            remove_blend_modes(effect_root)
            destination = output / f"custom_{view}_effect_{layer}_{effect_number}.png"
            effect_data = render_cropped(effect_root, destination)
            if view == "front" and any("paint29_radial" in fill for fill in fills):
                replace_front_tire(
                    source_file.parent / "coral" / "mode=scooter@2x.png",
                    destination,
                    effect_data,
                )
            effect_data["blendMode"] = mode
            if matte_only:
                effect_data["matteOnly"] = True
            effects.append(effect_data)
            effect_number += 1
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
    for pattern in (
        "custom_*_effect_*.png",
        "custom_*_gloss_*.png",
        "custom_*_over_*.png",
    ):
        for stale in args.output.glob(pattern):
            stale.unlink()
    front = build_layers(args.source / "mode=scooter.svg", args.output, "front")
    side = build_layers(args.source / "side_master.svg", args.output, "side")
    build_gloss(args.output, front, "front")
    build_gloss(args.output, side, "side")
    manifest = {
        "version": 1,
        "views": {
            "front": front,
            "side": side,
        },
    }
    (args.output / "custom_artwork_layers.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    build_hover(args.source, args.output)


if __name__ == "__main__":
    main()
