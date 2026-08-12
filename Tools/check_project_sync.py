#!/usr/bin/env python3
"""Check that Dates.xcodeproj references every Swift source on disk.

Dates.xcodeproj is generated from project.yml but committed so the repository opens
without tooling. XcodeGen resolves its source globs when it generates, so a new file
added without re-running `xcodegen generate` is invisible to the build — it compiles
locally for whoever added it through Xcode's UI, and vanishes for everyone else.

Comparing file references rather than diffing the whole pbxproj keeps this independent
of which XcodeGen version produced the committed project.
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
PBXPROJ = REPO / "Dates.xcodeproj" / "project.pbxproj"
SOURCE_ROOTS = ["Dates", "DatesTests"]


def main() -> int:
    if not PBXPROJ.exists():
        print(f"error: {PBXPROJ} not found")
        return 1

    project = PBXPROJ.read_text(encoding="utf-8")

    on_disk = {
        path.relative_to(REPO)
        for root in SOURCE_ROOTS
        for path in (REPO / root).rglob("*.swift")
    }

    missing = sorted(str(path) for path in on_disk if path.name not in project)

    # The reverse direction: a reference left behind after a file was deleted or moved.
    referenced = set(re.findall(r'path = "?([\w+\-.]+\.swift)"?;', project))
    names_on_disk = {path.name for path in on_disk}
    dangling = sorted(referenced - names_on_disk)

    if missing:
        print("error: these Swift files exist but are not in Dates.xcodeproj:")
        for path in missing:
            print(f"  {path}")

    if dangling:
        print("error: Dates.xcodeproj references files that no longer exist:")
        for name in dangling:
            print(f"  {name}")

    if missing or dangling:
        print("\nRun 'xcodegen generate' and commit the regenerated project.")
        return 1

    print(f"Dates.xcodeproj references all {len(on_disk)} Swift sources.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
