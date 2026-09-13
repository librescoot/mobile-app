#!/usr/bin/env python3
"""Synthesize nightly release notes from git commits since the last nightly."""

import argparse
import subprocess
import sys

LIMIT = 500


def git_log(base, head, max_count):
    range_ = f"{base}..{head}" if base else f"-{max_count}"
    out = subprocess.run(
        ["git", "log", "--no-merges", "--pretty=format:%s", range_],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    subjects = []
    for line in out.splitlines():
        line = line.strip()
        if line and line not in subjects:
            subjects.append(line)
    return subjects[:max_count]


def render(subjects):
    lines = [f"• {s}" for s in subjects]
    dropped = 0
    while len("\n".join(lines)) > LIMIT and len(lines) > 1:
        lines.pop()
        dropped += 1
    text = "\n".join(lines)
    if len(text) > LIMIT:
        text = text[: LIMIT - 2].rstrip() + "…"
    elif dropped:
        summary = f"(+{dropped} more)"
        if len(text) + len(summary) + 1 <= LIMIT:
            text += "\n" + summary
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", help="previous nightly tag; omit to use recent commits")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--max-commits", type=int, default=20)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    subjects = git_log(args.base, args.head, args.max_commits)
    if not subjects:
        subjects = ["Nightly build; no notable changes since the previous nightly"]
    text = render(subjects)
    with open(args.output, "w", encoding="utf-8") as file:
        file.write(text)
    print(f"{len(subjects)} commit(s) -> {args.output} ({len(text)} chars)")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(f"nightly notes failed: {error.stderr}", file=sys.stderr)
        sys.exit(1)
