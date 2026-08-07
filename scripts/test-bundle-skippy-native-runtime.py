#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import tarfile
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path


SCRIPT = Path(__file__).with_name("bundle-skippy-native-runtime.py")
SPEC = importlib.util.spec_from_file_location("bundle_skippy_runtime", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BundleSkippyRuntimeTests(unittest.TestCase):
    def fixture(self, root: Path, *, unsafe: bool = False) -> tuple[Path, Path]:
        archive = root / "runtime.tar.gz"
        manifest = {
            "runtime": {
                "id": "fixture-runtime",
                "mesh_version": "0.74.0",
                "skippy_abi": "0.1.32",
                "platform": {"target": "fixture-target"},
                "backend": {"kind": "vulkan"},
                "libraries": ["../escape.dll" if unsafe else "lib/runtime.dll"],
            }
        }
        with tarfile.open(archive, "w:gz") as bundle:
            for name, data in (
                ("fixture-runtime/manifest.json", json.dumps(manifest).encode()),
                ("fixture-runtime/lib/runtime.dll", b"native"),
            ):
                info = tarfile.TarInfo(name)
                info.size = len(data)
                bundle.addfile(info, io.BytesIO(data))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        lock = root / "lock.json"
        lock.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "mesh_release": "0.74.0",
                    "mesh_revision": "stable-revision",
                    "skippy_abi": "0.1.32",
                    "artifacts": {
                        "fixture-target:directml": {
                            "asset": archive.name,
                            "runtime_id": "fixture-runtime",
                            "backend": "vulkan",
                            "execution_device": "vulkan",
                            "sha256": digest,
                        }
                    },
                }
            )
        )
        return archive, lock

    def test_bundles_exact_runtime_and_writes_per_file_integrity(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive, lock = self.fixture(root)
            result = MODULE.bundle(
                Namespace(
                    target="fixture-target",
                    accelerator="directml",
                    out=root / "out",
                    lock=lock,
                    archive=archive,
                    base_url="unused",
                )
            )
            integrity_path = Path(result["runtime_root"]) / "fabi-integrity.json"
            integrity = json.loads(integrity_path.read_text())
            self.assertEqual(integrity["backend"], "vulkan")
            self.assertEqual(
                [entry["path"] for entry in integrity["files"]],
                ["manifest.json", "lib/runtime.dll"],
            )

    def test_rejects_manifest_library_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive, lock = self.fixture(root, unsafe=True)
            with self.assertRaisesRegex(ValueError, "unsafe Skippy runtime library path"):
                MODULE.bundle(
                    Namespace(
                        target="fixture-target",
                        accelerator="directml",
                        out=root / "out",
                        lock=lock,
                        archive=archive,
                        base_url="unused",
                    )
                )

    def test_rejects_archive_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive, lock = self.fixture(root)
            payload = json.loads(lock.read_text())
            payload["artifacts"]["fixture-target:directml"]["sha256"] = "0" * 64
            lock.write_text(json.dumps(payload))
            with self.assertRaisesRegex(ValueError, "archive hash mismatch"):
                MODULE.bundle(
                    Namespace(
                        target="fixture-target",
                        accelerator="directml",
                        out=root / "out",
                        lock=lock,
                        archive=archive,
                        base_url="unused",
                    )
                )


if __name__ == "__main__":
    unittest.main()
