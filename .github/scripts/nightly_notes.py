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


def rev(spec):
    return subprocess.run(
        ["git", "rev-parse", spec], capture_output=True, text=True, check=True
    ).stdout.strip()


def previous_nightly(head):
    """Newest nightly-* tag that is an ancestor of head but is not head itself.

    The release job in the same workflow run tags the commit currently being
    built, so the newest nightly tag can point at head and yield an empty range,
    which reads as "no notable changes" for a build that has some.
    """
    listed = subprocess.run(
        ["git", "tag", "--list", "nightly-*", "--sort=-creatordate", "--merged", head],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    head_sha = rev(head)
    for name in listed.split():
        if rev(f"{name}^{{commit}}") != head_sha:
            return name
    return None


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
    parser.add_argument(
        "--base",
        help="previous nightly tag, or 'auto' to pick the newest one before HEAD; "
        "omit to use recent commits",
    )
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--max-commits", type=int, default=20)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    base = args.base
    if base == "auto":
        base = previous_nightly(args.head)
        print(f"base tag: {base or '(none found)'}")
    subjects = git_log(base, args.head, args.max_commits)
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
