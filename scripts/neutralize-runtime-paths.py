#!/usr/bin/env python3
"""Neutralize absolute build roots in a bundled Python runtime.

The release build runs in Bash on every platform. On GitHub's Windows runner,
Bash names the staging directory ``/d/a/...`` while native Python records the
same directory as ``D:\\a\\...``. Replacing only the Bash spelling leaves the
venv tied to the CI machine. This helper replaces every explicitly supplied
spelling in text files and writes the exact relocation manifest consumed by
the CLI and IDE installers.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def neutralize_runtime(
    runtime: Path,
    install_root: Path,
    manifest: Path,
    placeholder: str,
    build_roots: list[str],
) -> int:
    runtime = runtime.absolute()
    install_root = install_root.absolute()
    manifest = manifest.absolute()
    if not runtime.is_dir():
        raise ValueError(f"runtime directory does not exist: {runtime}")
    try:
        manifest.relative_to(runtime)
    except ValueError as error:
        raise ValueError("relocation manifest must live inside the runtime") from error

    needles = sorted(
        {root.encode("utf-8") for root in build_roots if root},
        key=len,
        reverse=True,
    )
    if not needles:
        raise ValueError("at least one build root is required")
    replacement = placeholder.encode("utf-8")
    patched: list[str] = []

    for path in sorted(runtime.rglob("*")):
        if path == manifest or path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        # Match grep -I's safety contract: native executables, wheels and shared
        # libraries contain NUL bytes and must never be length-changing patched.
        if b"\0" in data[:8192]:
            continue
        updated = data
        for needle in needles:
            updated = updated.replace(needle, replacement)
        if updated == data:
            continue
        path.write_bytes(updated)
        patched.append(path.relative_to(install_root).as_posix())

    manifest.write_text("".join(f"{entry}\n" for entry in patched), encoding="utf-8")
    return len(patched)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--install-root", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--placeholder", required=True)
    parser.add_argument("--build-root", action="append", required=True, dest="build_roots")
    args = parser.parse_args()
    count = neutralize_runtime(
        runtime=args.runtime,
        install_root=args.install_root,
        manifest=args.manifest,
        placeholder=args.placeholder,
        build_roots=args.build_roots,
    )
    print(count)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
