#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("neutralize-runtime-paths.py")


class NeutralizeRuntimePathsTest(unittest.TestCase):
    def test_neutralizes_posix_native_and_mixed_windows_roots(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            install_root = Path(temporary) / "package"
            runtime = install_root / "runtime"
            scripts = runtime / "parallax-venv" / "Scripts"
            scripts.mkdir(parents=True)
            posix_root = "/d/a/fabi/fabi/dist/package"
            native_root = r"D:\a\fabi\fabi\dist\package"
            mixed_root = "D:/a/fabi/fabi/dist/package"

            (runtime / "pyvenv.cfg").write_text(f"home={native_root}\\python-base\n")
            (scripts / "parallax-script.py").write_text(f"root={mixed_root}\n")
            (runtime / "record.txt").write_text(f"source={posix_root}/runtime\n")
            binary = runtime / "native.exe"
            binary.write_bytes(b"MZ\0" + native_root.encode())
            manifest = runtime / "relocation-manifest.txt"

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--runtime",
                    str(runtime),
                    "--install-root",
                    str(install_root),
                    "--manifest",
                    str(manifest),
                    "--placeholder",
                    "__FABI_INSTALL_ROOT__",
                    "--build-root",
                    posix_root,
                    "--build-root",
                    native_root,
                    "--build-root",
                    mixed_root,
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.stdout.strip(), "3")
            self.assertEqual(
                manifest.read_text().splitlines(),
                [
                    "runtime/parallax-venv/Scripts/parallax-script.py",
                    "runtime/pyvenv.cfg",
                    "runtime/record.txt",
                ],
            )
            self.assertIn("__FABI_INSTALL_ROOT__", (runtime / "pyvenv.cfg").read_text())
            self.assertEqual(binary.read_bytes(), b"MZ\0" + native_root.encode())


if __name__ == "__main__":
    unittest.main()
