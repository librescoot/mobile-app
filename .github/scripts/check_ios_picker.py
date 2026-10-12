#!/usr/bin/env python3
"""Verify the resolved iOS picker uses document-only CocoaPods support."""

import argparse
from pathlib import Path
import re


def check_picker(ios_root: Path) -> None:
    lock = (ios_root / "Podfile.lock").read_text()
    if re.search(r"DK(?:Camera|ImagePickerController)", lock):
        raise ValueError("Camera/photo picker dependencies are present in Podfile.lock")
    if not re.search(r"^  - file_picker \(", lock, re.MULTILINE):
        raise ValueError("file_picker was not resolved through CocoaPods")
    support = ios_root / "Pods/Target Support Files/file_picker"
    configs = sorted(support.glob("file_picker.*.xcconfig"))
    if not configs:
        raise ValueError("Missing generated file_picker build configurations")
    for config in configs:
        contents = config.read_text()
        if re.search(r"\bPICKER_(?:MEDIA|AUDIO)\b", contents):
            raise ValueError(f"Unused media/audio picker compiled in: {config}")
        if not re.search(r"\bPICKER_DOCUMENT=1\b", contents):
            raise ValueError(f"Document picker is not enabled: {config}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios-root", type=Path, default=Path("ios"))
    args = parser.parse_args()
    try:
        check_picker(args.ios_root)
    except (OSError, ValueError) as error:
        parser.exit(1, f"iOS picker validation failed: {error}\n")
    print("Verified document-only CocoaPods picker; no camera/photo-gallery/audio modules")


if __name__ == "__main__":
    main()
