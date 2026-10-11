"""Source receipts: what was read, from where, when, and its checksum."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import urllib.request
from pathlib import Path

from . import paths


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def sha256_file(path: Path, chunk: int = 1 << 22) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(chunk)
            if not block:
                break
            h.update(block)
    return h.hexdigest()


def http_head(url: str) -> dict:
    """ETag / size / Last-Modified of a remote object (identifies the exact version read)."""
    request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "Hoarbound-KW-Reality/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        h = response.headers
        return {
            "etag": (h.get("ETag") or "").strip('"'),
            "bytes": int(h.get("Content-Length") or 0),
            "last_modified": h.get("Last-Modified"),
        }


def load(source_id: str) -> dict:
    path = paths.RECEIPTS / f"{source_id}.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"source_id": source_id, "artifacts": []}


def save(receipt: dict) -> Path:
    paths.RECEIPTS.mkdir(parents=True, exist_ok=True)
    receipt["artifacts"] = sorted(receipt.get("artifacts", []), key=lambda a: a.get("name", ""))
    path = paths.RECEIPTS / f"{receipt['source_id']}.json"
    path.write_text(json.dumps(receipt, indent=1, sort_keys=False) + "\n", encoding="utf-8")
    return path


def upsert_artifact(receipt: dict, artifact: dict) -> None:
    items = [a for a in receipt.get("artifacts", []) if a.get("name") != artifact["name"]]
    items.append(artifact)
    receipt["artifacts"] = items
