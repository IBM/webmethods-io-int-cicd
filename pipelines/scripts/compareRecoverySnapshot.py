#!/usr/bin/env python3

"""Compare two Git trees while ignoring known export-container volatility."""

import io
import hashlib
import json
import subprocess
import sys
import zipfile


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args])


def tree(ref: str) -> dict[str, tuple[str, str]]:
    output = git("ls-tree", "-r", "-z", ref)
    entries: dict[str, tuple[str, str]] = {}
    for record in output.split(b"\0"):
        if not record:
            continue
        metadata, path = record.split(b"\t", 1)
        mode, object_type, object_id = metadata.decode().split()
        if object_type == "blob":
            entries[path.decode("utf-8", "surrogateescape")] = (mode, object_id)
    return entries


def remove_generated_on(value):
    if isinstance(value, dict):
        return {
            key: remove_generated_on(child)
            for key, child in value.items()
            if key != "generatedOn"
        }
    if isinstance(value, list):
        return [remove_generated_on(child) for child in value]
    return value


def digest(parts) -> str:
    checksum = hashlib.sha256()
    for part in parts:
        if isinstance(part, str):
            part = part.encode("utf-8", "surrogateescape")
        checksum.update(len(part).to_bytes(8, "big"))
        checksum.update(part)
    return checksum.hexdigest()


def semantic_checksum(path: str, content: bytes) -> str:
    if path.lower().endswith(".json"):
        try:
            parsed = json.loads(content.decode("utf-8"))
            normalized = json.dumps(
                remove_generated_on(parsed),
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
            return digest(["json", normalized])
        except (UnicodeDecodeError, json.JSONDecodeError):
            return digest(["bytes", content])

    if path.lower().endswith(".zip") or content.startswith(b"PK\x03\x04"):
        try:
            with zipfile.ZipFile(io.BytesIO(content)) as archive:
                members = []
                for info in archive.infolist():
                    if info.is_dir():
                        continue
                    members.append(
                        (
                            info.filename,
                            semantic_checksum(info.filename, archive.read(info)),
                        )
                    )
                # ZIP entry timestamps, compression, order and other container
                # metadata are intentionally excluded from this representation.
                checksum_parts = ["zip"]
                for member_name, member_checksum in sorted(members):
                    checksum_parts.extend([member_name, member_checksum])
                return digest(checksum_parts)
        except (OSError, RuntimeError, zipfile.BadZipFile):
            return digest(["bytes", content])

    return digest(["bytes", content])


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <expected-ref> <actual-ref>", file=sys.stderr)
        return 2

    expected_ref, actual_ref = sys.argv[1:]
    expected_tree = tree(expected_ref)
    actual_tree = tree(actual_ref)
    differences = []

    for path in sorted(set(expected_tree) | set(actual_tree)):
        expected = expected_tree.get(path)
        actual = actual_tree.get(path)
        if expected is None:
            differences.append(("A", path))
            continue
        if actual is None:
            differences.append(("D", path))
            continue
        if expected[0] != actual[0]:
            differences.append(("T", path))
            continue

        expected_content = git("show", f"{expected_ref}:{path}")
        actual_content = git("show", f"{actual_ref}:{path}")
        if semantic_checksum(path, expected_content) != semantic_checksum(path, actual_content):
            differences.append(("M", path))

    for status, path in differences:
        print(f"{status}\t{path}")
    return 1 if differences else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Recovery snapshot comparison error: {error}", file=sys.stderr)
        sys.exit(2)
