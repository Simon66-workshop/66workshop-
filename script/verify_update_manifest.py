#!/usr/bin/env python3
"""Verify a TaskLight Ed25519 update manifest before installation."""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import tempfile
import os
import shutil
from pathlib import Path

from sign_update_manifest import canonical_payload


def verify(manifest: Path, public_key: Path) -> bool:
    payload = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or payload.get("signature_algorithm") != "ed25519" or not payload.get("signature"):
        return False
    with tempfile.TemporaryDirectory() as tmp:
        data_path = Path(tmp) / "manifest.bin"
        signature_path = Path(tmp) / "signature.bin"
        data_path.write_bytes(canonical_payload(payload))
        signature_path.write_bytes(base64.b64decode(str(payload["signature"]), validate=True))
        openssl = os.environ.get("TASKLIGHT_OPENSSL_PATH") or shutil.which("openssl") or "/usr/bin/openssl"
        completed = subprocess.run(
            [openssl, "pkeyutl", "-verify", "-rawin", "-pubin", "-inkey", str(public_key), "-in", str(data_path), "-sigfile", str(signature_path)],
            capture_output=True,
        )
        return completed.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify a TaskLight update manifest")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--public-key", required=True)
    args = parser.parse_args()
    valid = verify(Path(args.manifest), Path(args.public_key))
    print(json.dumps({"status": "valid" if valid else "invalid", "signature_valid": valid}, sort_keys=True))
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
