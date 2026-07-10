#!/usr/bin/env python3
"""Sign a TaskLight update manifest with an external Ed25519 private key."""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import tempfile
import shutil
from pathlib import Path
from typing import Any


def canonical_payload(payload: dict[str, Any]) -> bytes:
    unsigned = {key: value for key, value in payload.items() if key not in {"signature", "signature_algorithm"}}
    return json.dumps(unsigned, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode()


def sign(manifest: Path, private_key: Path, output: Path) -> dict[str, Any]:
    payload = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("manifest must be an object")
    key_mode = private_key.stat().st_mode & 0o777
    if key_mode & 0o077:
        raise PermissionError("private key permissions must be 0600 or stricter")
    with tempfile.TemporaryDirectory() as tmp:
        data_path = Path(tmp) / "manifest.bin"
        signature_path = Path(tmp) / "signature.bin"
        data_path.write_bytes(canonical_payload(payload))
        openssl = os.environ.get("TASKLIGHT_OPENSSL_PATH") or shutil.which("openssl") or "/usr/bin/openssl"
        subprocess.run(
            [openssl, "pkeyutl", "-sign", "-rawin", "-inkey", str(private_key), "-in", str(data_path), "-out", str(signature_path)],
            check=True,
            capture_output=True,
        )
        payload["signature_algorithm"] = "ed25519"
        payload["signature"] = base64.b64encode(signature_path.read_bytes()).decode("ascii")
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp_output = output.with_suffix(output.suffix + ".tmp")
    tmp_output.write_text(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp_output, output)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Sign a TaskLight update manifest")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--private-key", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    payload = sign(Path(args.manifest), Path(args.private_key), Path(args.output))
    print(json.dumps({"status": "signed", "algorithm": payload["signature_algorithm"], "output": args.output}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
