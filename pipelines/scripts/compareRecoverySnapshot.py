#!/usr/bin/env python3

"""Compare two Git trees while ignoring known export-container volatility."""

import io
import hashlib
import json
import re
import subprocess
import sys
import zipfile


GENERATED_EXPORT_ID = re.compile(rb"(?:pkg|fld)_[0-9a-fA-F]{32}_exported")
MANIFEST_TIME = re.compile(
    rb'(<value name="(?:time|created_date)">)[^<]*(</value>)'
)
NODE_EXPORT_TIME = re.compile(
    rb'<(?:value|number)\s+name="(createdDate|lastModifiedDate)"'
    rb'(?:\s+type="[^"]*")?>[^<]*</(?:value|number)>'
)


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


def canonical_archive_name(name: str) -> str:
    return GENERATED_EXPORT_ID.sub(
        b"generated_export_package", name.encode("utf-8", "surrogateescape")
    ).decode("utf-8", "surrogateescape")


def normalize_archive_content(path: str, content: bytes) -> bytes:
    normalized = GENERATED_EXPORT_ID.sub(b"generated_export_package", content)
    if path.lower().endswith(("manifest.rel", "manifest.v3")):
        normalized = MANIFEST_TIME.sub(rb"\1generated-export-time\2", normalized)
    if path.lower().endswith("node.ndf"):
        # FlowService exports regenerate these audit timestamps. The API may
        # also serialize lastModifiedDate as either <value> or <number>, even
        # when the service implementation itself has not changed.
        normalized = NODE_EXPORT_TIME.sub(
            rb'<value name="\1">generated-export-time</value>', normalized
        )
    return normalized


def semantic_checksum(path: str, content: bytes, inside_archive: bool = False) -> str:
    if path.lower().endswith(".zip") or content.startswith(b"PK\x03\x04"):
        try:
            with zipfile.ZipFile(io.BytesIO(content)) as archive:
                members = []
                for info in archive.infolist():
                    if info.is_dir():
                        continue
                    # The signature covers the generated package container and
                    # therefore changes with its random ID and export timestamp.
                    # Actual archive members remain independently checksummed.
                    if info.filename.rsplit("/", 1)[-1] == "sig.txt":
                        continue
                    members.append(
                        (
                            canonical_archive_name(info.filename),
                            semantic_checksum(info.filename, archive.read(info), True),
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

    if inside_archive:
        content = normalize_archive_content(path, content)

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
        if expected[1] == actual[1]:
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
