"""Offline publication guard. Reports locations/categories, never matched values.

This is a focused safety net, not a general-purpose secret/security audit.
It scans current publishable files (or the index) and optionally reachable Git
history, including deleted files. Ignored files are never added or modified.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
from dataclasses import dataclass


PATTERNS = {
    "jwt_or_session_token": rb"eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}",
    "private_key": rb"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----",
    "supabase_secret_key": rb"sb_secret_[A-Za-z0-9_-]{20,}",
    "github_token": rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})",
    "google_api_key": rb"AIza[0-9A-Za-z_-]{30,}",
    "credential_url": rb"[a-zA-Z][a-zA-Z0-9+.-]*://[^\s/:@]+:[^\s/@]{8,}@",
}
PERSONAL_EMAIL = rb"[A-Za-z0-9._%+-]+@(?:gmail\.com|hotmail\.com|outlook\.com|yahoo\.[a-z]+)"
DEVICE_SERIAL = rb"\bR58[A-Z0-9]{8}\b"
PRIVATE_SUFFIXES = {
    ".apk", ".aab", ".ipa", ".har", ".jks", ".keystore", ".pem", ".key",
    ".p12", ".pfx", ".db", ".sqlite", ".sqlite3",
}
ALLOWED_DATA = {"assets/data/legacy_route_models.sqlite"}


@dataclass(frozen=True, order=True)
class Finding:
    severity: str
    location: str
    kind: str


def private_path(path: str) -> bool:
    p = PurePosixPath(path.lower())
    if path in ALLOWED_DATA or path == "tools/bicimad_probe/private/.gitkeep":
        return False
    return (
        "private" in p.parts
        or p.suffix in PRIVATE_SUFFIXES
        or (p.name.startswith(".env") and p.name != ".env.example")
        or ("secrets" in p.name and p.suffix == ".json"
            and p.name != "local_secrets.example.json")
        or p.name in {"key.properties", "trips_raw.json", "trips_normalized.json"}
        or p.name.endswith(("-wal", "-shm", "-journal"))
    )


def scan(data: bytes, location: str, known_values: list[bytes]) -> set[Finding]:
    findings = set()
    # Binary assets are also checked, so embedding configuration in an asset
    # cannot silently bypass the guard. No snippets or matched values escape.
    for value in known_values:
        if value in data:
            findings.add(Finding("ERROR", location, "local_configuration_value"))
    for kind, pattern in PATTERNS.items():
        if re.search(pattern, data):
            findings.add(Finding("ERROR", location, kind))
    if b"\0" not in data[:8192]:
        for kind, pattern in (("personal_email", PERSONAL_EMAIL), ("device_serial", DEVICE_SERIAL)):
            if re.search(pattern, data):
                findings.add(Finding("WARNING", location, kind))
    return findings


def git(root: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.PIPE)


def read_objects(root: Path, objects: list[tuple[str, str]]):
    # Stream cat-file output; never retain the complete historical asset set.
    with subprocess.Popen(
        ["git", "-C", str(root), "cat-file", "--batch"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    ) as process:
        try:
            for oid, location in objects:
                process.stdin.write(oid.encode("ascii") + b"\n")
                process.stdin.flush()
                header = process.stdout.readline().split()
                if len(header) != 3:
                    raise ValueError("unreadable_git_object")
                size = int(header[2])
                data = process.stdout.read(size)
                if len(data) != size or process.stdout.read(1) != b"\n":
                    raise ValueError("truncated_git_object")
                yield header[1], location, data
        finally:
            process.stdin.close()
            if process.poll() is None:
                process.terminate()
            process.wait()


def audit(root: Path, *, staged: bool, history: bool) -> set[Finding]:
    known = []
    config = root / "local_secrets.json"
    if config.exists():
        values = json.loads(config.read_text(encoding="utf-8-sig"))
        if not isinstance(values, dict):
            raise ValueError("invalid_local_configuration")
        known = [v.encode() for v in values.values() if isinstance(v, str) and len(v) >= 8]
    findings = set()

    def inspect(path: str, data: bytes, location: str):
        if private_path(path):
            findings.add(Finding("ERROR", location, "private_artifact"))
        findings.update(scan(data, location, known))

    if staged:
        objects = []
        for record in git(root, "ls-files", "--stage", "-z").split(b"\0"):
            if record:
                metadata, path = record.split(b"\t", 1)
                objects.append((metadata.split()[1].decode(), path.decode("utf-8")))
        for _, path, data in read_objects(root, objects):
            inspect(path, data, "INDEX:" + path)
    else:
        paths = set(git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0"))
        for raw in paths:
            if not raw:
                continue
            path = raw.decode("utf-8")
            file = root / path
            if file.is_symlink():
                # Do not follow links into private files outside the repository.
                findings.add(Finding("WARNING", path, "symlink_requires_review"))
            elif file.is_file():
                inspect(path, file.read_bytes(), "WORKTREE:" + path)
    if history:
        objects = []
        for row in git(root, "rev-list", "--objects", "--all").splitlines():
            oid, _, path = row.partition(b" ")
            objects.append((oid.decode(), oid[:8].decode() + ":" + path.decode("utf-8")))
        for kind, location, data in read_objects(root, objects):
            if kind == b"blob":
                inspect(location.partition(":")[2], data, "HISTORY:" + location)
            elif kind in (b"commit", b"tag"):
                findings.update(scan(data, "HISTORY_METADATA:" + location, known))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="Scan index contents instead of working files")
    parser.add_argument("--history", action="store_true", help="Also scan all locally reachable Git history")
    args = parser.parse_args()
    try:
        root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").decode().strip())
        findings = audit(root, staged=args.staged, history=args.history)
    except (OSError, ValueError, subprocess.SubprocessError):
        print("ERROR publication_check_failed (no exception details logged)")
        return 2
    for finding in sorted(findings):
        print(f"{finding.severity} {finding.kind} {json.dumps(finding.location, ensure_ascii=True)}")
    errors = sum(f.severity == "ERROR" for f in findings)
    warnings = sum(f.severity == "WARNING" for f in findings)
    print(f"PUBLICATION_CHECK errors={errors} warnings={warnings}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
