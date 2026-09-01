#!/usr/bin/env python3
"""Extract exact PyInstaller CArchive members for App Control hash admission.

This is an offline build-time evidence tool.  It does not execute the input EXE.
The extracted tree is used only to generate release-specific App Control hash rules
for immutable historical onefile baselines that must participate in upgrade tests.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil

from PyInstaller.archive.readers import CArchiveReader


EXECUTABLE_EXTENSIONS = {".exe", ".dll", ".pyd", ".ocx", ".sys"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_member_path(name: str) -> Path:
    normalized = name.replace("\\", "/")
    pure = PurePosixPath(normalized)
    if pure.is_absolute() or not pure.parts or any(part in ("", ".", "..") for part in pure.parts):
        raise ValueError(f"unsafe CArchive member path: {name!r}")
    # A drive prefix is not absolute in PurePosixPath; reject it explicitly.
    if ":" in pure.parts[0]:
        raise ValueError(f"unsafe drive-qualified CArchive member path: {name!r}")
    return Path(*pure.parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    source = args.input.resolve(strict=True)
    output = args.output.resolve()
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    archive = CArchiveReader(str(source))
    rows: list[dict[str, object]] = []
    native_count = 0

    for name in sorted(archive.toc):
        relative = safe_member_path(name)
        data = archive.extract(name)
        if data is None:
            continue
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        extension = target.suffix.lower()
        executable = extension in EXECUTABLE_EXTENSIONS
        if executable:
            native_count += 1
        entry = archive.toc[name]
        typecode = entry[-1]
        if isinstance(typecode, bytes):
            typecode = typecode.decode("ascii", errors="replace")
        rows.append(
            {
                "archive_name": name,
                "relative_path": relative.as_posix(),
                "size": target.stat().st_size,
                "sha256": sha256(target),
                "typecode": str(typecode),
                "executable": executable,
            }
        )

    if native_count < 2:
        raise RuntimeError(
            f"historical CArchive extraction produced only {native_count} native executable members"
        )

    manifest = {
        "schema": "arvectum.proxy.pyinstaller-onefile-runtime-inventory.v1",
        "result": "PASS",
        "input_name": source.name,
        "input_sha256": sha256(source),
        "member_count": len(rows),
        "executable_member_count": native_count,
        "executed_input": False,
        "members": rows,
    }
    (output / "onefile-runtime.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("PyInstaller onefile runtime extraction: PASS")
    print(f"Input SHA256: {manifest['input_sha256']}")
    print(f"Members: {len(rows)}")
    print(f"Native executable members: {native_count}")
    print("Input execution: NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
