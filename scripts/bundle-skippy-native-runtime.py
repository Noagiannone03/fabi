#!/usr/bin/env python3
"""Install one immutable Mesh/Skippy native runtime into a Fabi product tree."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path, PurePosixPath
from typing import Any


DEFAULT_LOCK = Path(__file__).with_name("skippy-native-runtime-lock.json")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_lock(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError("unsupported Skippy runtime lock schema")
    return payload


def select_artifact(lock: dict[str, Any], target: str, accelerator: str) -> dict[str, str]:
    key = f"{target.strip().lower()}:{accelerator.strip().lower()}"
    try:
        artifact = lock["artifacts"][key]
    except KeyError as error:
        raise ValueError(f"no qualified Skippy native runtime for {key}") from error
    required = {"asset", "runtime_id", "backend", "execution_device", "sha256"}
    missing = sorted(required.difference(artifact))
    if missing:
        raise ValueError(f"Skippy runtime lock entry {key} misses {', '.join(missing)}")
    return {name: str(artifact[name]) for name in required}


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "Fabi-release-builder/1"})
    with urllib.request.urlopen(request, timeout=60) as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)


def validate_member(member: tarfile.TarInfo) -> None:
    path = PurePosixPath(member.name)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe path in Skippy runtime archive: {member.name}")
    if member.issym() or member.islnk() or member.isdev() or member.isfifo():
        raise ValueError(f"unsupported entry in Skippy runtime archive: {member.name}")
    if not (member.isdir() or member.isfile()):
        raise ValueError(f"unsupported entry type in Skippy runtime archive: {member.name}")


def extract_verified_archive(archive: Path, destination: Path) -> Path:
    if destination.exists() and any(destination.iterdir()):
        raise ValueError(f"Skippy runtime destination is not empty: {destination}")
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, mode="r:gz") as bundle:
        members = bundle.getmembers()
        if not members:
            raise ValueError("Skippy runtime archive is empty")
        for member in members:
            validate_member(member)
        bundle.extractall(destination, members=members, filter="data")
    manifests = tuple(destination.glob("*/manifest.json"))
    if len(manifests) != 1:
        raise ValueError(f"expected one Skippy runtime manifest, found {len(manifests)}")
    return manifests[0].parent


def validate_runtime(
    runtime_root: Path,
    *,
    lock: dict[str, Any],
    artifact: dict[str, str],
    target: str,
) -> dict[str, Any]:
    manifest_path = runtime_root / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    runtime = manifest.get("runtime")
    if not isinstance(runtime, dict):
        raise ValueError("Skippy runtime manifest has no runtime object")
    backend = runtime.get("backend")
    backend_kind = backend.get("kind") if isinstance(backend, dict) else None
    expected = {
        "id": artifact["runtime_id"],
        "mesh_version": str(lock["mesh_release"]),
        "skippy_abi": str(lock["skippy_abi"]),
    }
    for field, value in expected.items():
        if runtime.get(field) != value:
            raise ValueError(
                f"Skippy runtime {field} mismatch: expected {value}, got {runtime.get(field)}"
            )
    if backend_kind != artifact["backend"]:
        raise ValueError(
            f"Skippy runtime backend mismatch: expected {artifact['backend']}, got {backend_kind}"
        )
    platform = runtime.get("platform")
    if not isinstance(platform, dict) or platform.get("target") != target:
        raise ValueError(f"Skippy runtime target mismatch: expected {target}")
    libraries = runtime.get("libraries")
    if not isinstance(libraries, list) or not libraries:
        raise ValueError("Skippy runtime declares no libraries")

    integrity_files = ["manifest.json"]
    for raw_path in libraries:
        if not isinstance(raw_path, str):
            raise ValueError("Skippy runtime library path is not a string")
        relative = PurePosixPath(raw_path)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"unsafe Skippy runtime library path: {raw_path}")
        library = runtime_root.joinpath(*relative.parts)
        if not library.is_file():
            raise ValueError(f"Skippy runtime library is missing: {raw_path}")
        integrity_files.append(relative.as_posix())

    integrity = {
        "schema_version": 1,
        "mesh_release": lock["mesh_release"],
        "mesh_revision": lock["mesh_revision"],
        "skippy_abi": lock["skippy_abi"],
        "runtime_id": artifact["runtime_id"],
        "backend": artifact["backend"],
        "execution_device": artifact["execution_device"],
        "files": [
            {"path": relative, "sha256": sha256_file(runtime_root / relative)}
            for relative in dict.fromkeys(integrity_files)
        ],
    }
    (runtime_root / "fabi-integrity.json").write_text(
        json.dumps(integrity, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return integrity


def bundle(args: argparse.Namespace) -> dict[str, Any]:
    lock = read_lock(args.lock)
    artifact = select_artifact(lock, args.target, args.accelerator)
    if args.archive:
        archive = args.archive
        temporary = None
    else:
        temporary = tempfile.TemporaryDirectory(prefix="fabi-skippy-runtime-")
        archive = Path(temporary.name) / artifact["asset"]
        url = (
            f"{args.base_url.rstrip('/')}/v{lock['mesh_release']}/{artifact['asset']}"
        )
        download(url, archive)
    try:
        actual_hash = sha256_file(archive)
        if actual_hash != artifact["sha256"]:
            raise ValueError(
                f"Skippy runtime archive hash mismatch: expected {artifact['sha256']}, "
                f"got {actual_hash}"
            )
        runtime_root = extract_verified_archive(archive, args.out)
        integrity = validate_runtime(
            runtime_root,
            lock=lock,
            artifact=artifact,
            target=args.target,
        )
        return {
            "runtime_root": str(runtime_root),
            "asset": artifact["asset"],
            **integrity,
        }
    finally:
        if temporary is not None:
            temporary.cleanup()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True)
    parser.add_argument("--accelerator", required=True)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--archive", type=Path)
    parser.add_argument(
        "--base-url",
        default="https://github.com/Mesh-LLM/mesh-llm/releases/download",
    )
    return parser.parse_args()


if __name__ == "__main__":
    print(json.dumps(bundle(parse_args()), sort_keys=True))
