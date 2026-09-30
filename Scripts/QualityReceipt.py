#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Usage:
#   Scripts/QualityReceipt.py lint-index
#   Scripts/QualityReceipt.py lint-head
#   Scripts/QualityReceipt.py verify-clean-head
#   Scripts/QualityReceipt.py verify-push
#
# Cache successful local lint runs for exact Git trees and toolchains.
# Receipts are a local speed optimization, never a CI attestation.

from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import stat
import subprocess
import sys
import tempfile


RECEIPT_SCHEMA = 1
RECEIPT_CHECK = "Scripts/lint.sh"
RECEIPT_FILE_MODE = 0o600
CACHE_DIRECTORY_MODE = 0o700
EXECUTABLE_FILE_MODE = 0o755
REGULAR_FILE_MODE = 0o644
PRIVATE_PERMISSION_MASK = 0o077
SHARED_WRITE_PERMISSION_MASK = 0o022
FILE_HASH_BLOCK_SIZE = 1_048_576
RECEIPT_READ_LIMIT = 4096
GIT_BLOB_HEADER_FIELD_COUNT = 3
GIT_BLOB_TYPE = b"blob"
GIT_REGULAR_FILE_MODE = "100644"
GIT_EXECUTABLE_FILE_MODE = "100755"
GIT_HEADER_SEPARATOR_SIZE = 1
GIT_BLOB_SEPARATOR_SIZE = 1
EXPECTED_ARGUMENT_COUNTS = (2, 4)
VERIFY_HEAD_ARGUMENT_COUNT = 4
TOOLCHAIN_ENVIRONMENT = (
    "DEVELOPER_DIR",
    "BASH_ENV",
    "PYTHONHOME",
    "PYTHONPATH",
    "SDKROOT",
    "SOURCEKIT_TOOLCHAIN_PATH",
    "SWIFT_EXEC",
    "TOOLCHAINS",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_CEILING_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_CONFIG",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_NOSYSTEM",
    "GIT_CONFIG_PARAMETERS",
    "GIT_CONFIG_SYSTEM",
    "GIT_DIR",
    "GIT_DISCOVERY_ACROSS_FILESYSTEM",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_WORK_TREE",
)


class GateError(Exception):
    pass


def git(root: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["git", *arguments], cwd=root, text=True, stderr=subprocess.PIPE
    ).strip()


def lint_environment() -> dict[str, str]:
    return {
        name: value
        for name, value in os.environ.items()
        if not name.startswith("GIT_")
    }


def tree_for(root: Path, mode: str) -> str:
    if mode == "index":
        return git(root, "write-tree")
    if mode == "head":
        return git(root, "rev-parse", "HEAD^{tree}")
    raise GateError("unknown tree source")


def executable_identity(name: str) -> dict[str, str] | None:
    found = shutil.which(name)
    if found is None:
        return None
    path = Path(found).resolve(strict=True)
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as binary:
        for block in iter(lambda: binary.read(FILE_HASH_BLOCK_SIZE), b""):
            digest.update(block)
    return {"path": str(path), "sha256": digest.hexdigest()}


def command_output(arguments: list[str]) -> str | None:
    try:
        result = subprocess.run(
            arguments,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return result.stdout.strip()


def toolchain_fingerprint() -> str | None:
    tools = {}
    for name in (
        "bash",
        "git",
        "python3",
        "swift",
        "swiftlint",
        "xcrun",
        "xcode-select",
    ):
        identity = executable_identity(name)
        if identity is None:
            return None
        tools[name] = identity
    tools["python"] = executable_identity(sys.executable)
    tools["quality-receipt"] = executable_identity(str(Path(__file__).resolve()))

    swift_format_path = command_output(["xcrun", "--find", "swift-format"])
    xcodebuild_path = command_output(["xcrun", "--find", "xcodebuild"])
    if swift_format_path is None or xcodebuild_path is None:
        return None
    tools["swift-format"] = executable_identity(swift_format_path)
    tools["xcodebuild"] = executable_identity(xcodebuild_path)
    if any(identity is None for identity in tools.values()):
        return None

    versions = {
        "git": command_output(["git", "--version"]),
        "swift": command_output(["swift", "--version"]),
        "swift-format": command_output([swift_format_path, "--version"]),
        "swiftlint": command_output(["swiftlint", "version"]),
        "python": command_output([sys.executable, "--version"]),
        "xcodebuild": command_output([xcodebuild_path, "-version"]),
        "developer-directory": command_output(["xcode-select", "-p"]),
        "macos-sdk-path": command_output(
            ["xcrun", "--sdk", "macosx", "--show-sdk-path"]
        ),
        "macos-sdk-version": command_output(
            ["xcrun", "--sdk", "macosx", "--show-sdk-version"]
        ),
    }
    if any(value is None for value in versions.values()):
        return None

    material = {
        "platform": platform.platform(),
        "tools": tools,
        "versions": versions,
        "environment": {
            name: os.environ.get(name, "") for name in TOOLCHAIN_ENVIRONMENT
        },
    }
    canonical = json.dumps(material, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def cache_directory() -> Path | None:
    home = Path.home()
    if not home.is_absolute():
        return None

    directory = home / "Library" / "Caches" / "RefineID" / "QualityReceipts"
    current = home
    try:
        home_metadata = home.lstat()
        if (
            not stat.S_ISDIR(home_metadata.st_mode)
            or home_metadata.st_uid != os.getuid()
            or home_metadata.st_mode & SHARED_WRITE_PERMISSION_MASK
        ):
            return None
        for component in directory.relative_to(home).parts:
            current = current / component
            try:
                current.mkdir(mode=CACHE_DIRECTORY_MODE)
            except FileExistsError:
                pass
            metadata = current.lstat()
            if not stat.S_ISDIR(metadata.st_mode):
                return None
            if metadata.st_uid != os.getuid():
                return None
            if current in (directory.parent, directory) and metadata.st_mode & PRIVATE_PERMISSION_MASK:
                return None
            if current not in (directory.parent, directory) and metadata.st_mode & SHARED_WRITE_PERMISSION_MASK:
                return None
    except OSError:
        return None
    return directory


def expected_receipt(tree: str, fingerprint: str) -> dict[str, object]:
    return {
        "schema": RECEIPT_SCHEMA,
        "check": RECEIPT_CHECK,
        "tree": tree,
        "toolchain": fingerprint,
        "success": True,
    }


def receipt_is_valid(path: Path, expected: dict[str, object]) -> bool:
    descriptor = None
    try:
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(path, flags)
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_mode & PRIVATE_PERMISSION_MASK:
            return False
        contents = os.read(descriptor, RECEIPT_READ_LIMIT)
        canonical = (json.dumps(expected, sort_keys=True) + "\n").encode("utf-8")
        return contents == canonical
    except (OSError, ValueError):
        return False
    finally:
        if descriptor is not None:
            os.close(descriptor)


def install_receipt(path: Path, expected: dict[str, object]) -> None:
    payload = (json.dumps(expected, sort_keys=True) + "\n").encode("utf-8")
    descriptor, temporary_name = tempfile.mkstemp(prefix=".receipt-", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, RECEIPT_FILE_MODE)
        with os.fdopen(descriptor, "wb") as receipt_file:
            receipt_file.write(payload)
            receipt_file.flush()
            os.fsync(receipt_file.fileno())
        os.replace(temporary_path, path)
    finally:
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass


def extract_snapshot(root: Path, tree: str, destination: Path) -> None:
    entries = subprocess.check_output(
        ["git", "ls-tree", "--full-tree", "-r", "-z", tree], cwd=root
    )
    blobs = []
    for entry in entries.split(b"\0"):
        if not entry:
            continue
        header, raw_path = entry.split(b"\t", 1)
        mode, object_type, object_id = header.decode("ascii").split()
        if object_type != "blob" or mode not in (
            GIT_REGULAR_FILE_MODE,
            GIT_EXECUTABLE_FILE_MODE,
        ):
            raise GateError("lint snapshot contains a symlink or submodule")
        relative = PurePosixPath(os.fsdecode(raw_path))
        if relative.is_absolute() or any(
            part in ("", ".", "..") for part in relative.parts
        ):
            raise GateError("unsafe path in staged tree")
        blobs.append((relative, mode, object_id))

    object_ids = b"".join(
        object_id.encode("ascii") + b"\n" for _, _, object_id in blobs
    )
    contents = subprocess.check_output(
        ["git", "cat-file", "--batch"], cwd=root, input=object_ids
    )
    offset = 0
    for relative, mode, object_id in blobs:
        header_end = contents.find(b"\n", offset)
        if header_end < 0:
            raise GateError("incomplete staged tree blob stream")
        header = contents[offset:header_end].split()
        if (
            len(header) != GIT_BLOB_HEADER_FIELD_COUNT
            or header[0].decode("ascii") != object_id
            or header[1] != GIT_BLOB_TYPE
        ):
            raise GateError("unexpected staged tree blob")
        size = int(header[2])
        content_start = header_end + GIT_HEADER_SEPARATOR_SIZE
        content_end = content_start + size
        if (
            content_end + GIT_BLOB_SEPARATOR_SIZE > len(contents)
            or contents[content_end : content_end + GIT_BLOB_SEPARATOR_SIZE] != b"\n"
        ):
            raise GateError("incomplete staged tree blob contents")

        target = destination.joinpath(*relative.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as output:
            output.write(contents[content_start:content_end])
        os.chmod(
            target,
            EXECUTABLE_FILE_MODE
            if mode == GIT_EXECUTABLE_FILE_MODE
            else REGULAR_FILE_MODE,
        )
        offset = content_end + GIT_BLOB_SEPARATOR_SIZE
    if offset != len(contents):
        raise GateError("unexpected trailing staged tree blob data")


def index_still_matches(root: Path, tree: str) -> bool:
    try:
        return tree_for(root, "index") == tree
    except (OSError, subprocess.CalledProcessError):
        return False


def head_still_matches(root: Path, tree: str) -> bool:
    try:
        return tree_for(root, "head") == tree
    except (OSError, subprocess.CalledProcessError):
        return False


def tree_still_matches(root: Path, tree: str, guard: str | None) -> bool:
    if guard == "index":
        return index_still_matches(root, tree)
    if guard == "head":
        return head_still_matches(root, tree)
    return True


def run_lint(
    root: Path,
    tree: str,
    fingerprint: str | None,
    tree_guard: str | None = None,
    fingerprint_supplier=None,
) -> int:
    cache = cache_directory() if fingerprint is not None else None
    receipt = None
    lock_descriptor = None

    def fingerprint_matches() -> bool:
        if fingerprint is None or fingerprint_supplier is None:
            return True
        try:
            return fingerprint_supplier() == fingerprint
        except Exception:
            return False

    if cache is not None and fingerprint is not None:
        expected = expected_receipt(tree, fingerprint)
        key = hashlib.sha256(
            json.dumps(expected, sort_keys=True, separators=(",", ":")).encode(
                "utf-8"
            )
        ).hexdigest()
        receipt = cache / f"{key}.json"
        lock_path = cache / f"{key}.lock"
        try:
            flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
            lock_descriptor = os.open(lock_path, flags, RECEIPT_FILE_MODE)
            metadata = os.fstat(lock_descriptor)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_mode & PRIVATE_PERMISSION_MASK:
                os.close(lock_descriptor)
                lock_descriptor = None
                receipt = None
            else:
                fcntl.flock(lock_descriptor, fcntl.LOCK_EX)
                if receipt_is_valid(receipt, expected):
                    if not tree_still_matches(root, tree, tree_guard) or not fingerprint_matches():
                        fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
                        os.close(lock_descriptor)
                        lock_descriptor = None
                        print("Checked tree or toolchain changed during lint.", file=sys.stderr)
                        return 1
                    fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
                    os.close(lock_descriptor)
                    lock_descriptor = None
                    print("Lint receipt hit for exact tree and toolchain.")
                    return 0
        except OSError:
            if lock_descriptor is not None:
                os.close(lock_descriptor)
                lock_descriptor = None
            receipt = None

    if not fingerprint_matches():
        print("Toolchain changed during lint.", file=sys.stderr)
        return 1

    try:
        with tempfile.TemporaryDirectory(prefix="refineid-quality-") as temporary:
            snapshot = Path(temporary)
            extract_snapshot(root, tree, snapshot)
            result = subprocess.run(
                ["Scripts/lint.sh"],
                cwd=snapshot,
                env=lint_environment(),
                check=False,
            )
        if result.returncode != 0:
            return result.returncode
        if not tree_still_matches(root, tree, tree_guard) or not fingerprint_matches():
            print("Checked tree or toolchain changed while lint was running.", file=sys.stderr)
            return 1
        if receipt is not None and fingerprint is not None:
            try:
                install_receipt(receipt, expected_receipt(tree, fingerprint))
            except OSError:
                pass
        return 0
    except (OSError, subprocess.CalledProcessError, GateError) as error:
        if isinstance(error, GateError):
            print(f"Quality receipt lint failed: {error}", file=sys.stderr)
        else:
            print("Quality receipt could not snapshot or run lint.", file=sys.stderr)
        return 1
    finally:
        if lock_descriptor is not None:
            fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
            os.close(lock_descriptor)


def require_clean_head(root: Path) -> None:
    indexed = subprocess.check_output(
        ["git", "ls-files", "--cached", "--stage", "-v", "-z"],
        cwd=root,
    )
    for entry in indexed.split(b"\0"):
        if not entry:
            continue
        header, separator, _ = entry.partition(b" ")
        if not separator or header in (b"S", b"s") or header[:1].islower():
            raise GateError("push checks reject assume-unchanged and skip-worktree flags")
    status = git(root, "status", "--porcelain", "--untracked-files=all")
    if status:
        raise GateError("push checks require a clean tracked and untracked tree")


def verify_head(root: Path, commit: str, tree: str) -> None:
    if git(root, "rev-parse", "HEAD") != commit or tree_for(root, "head") != tree:
        raise GateError("checked-out commit changed while quality checks were running")
    require_clean_head(root)


def verify_push(root: Path) -> None:
    head = git(root, "rev-parse", "HEAD")
    zero = "0" * len(head)
    for line in sys.stdin:
        fields = line.split()
        if len(fields) != 4:
            raise GateError("invalid pre-push update")
        _, local_sha, _, _ = fields
        if local_sha == zero:
            continue
        resolved = git(root, "rev-parse", f"{local_sha}^{{commit}}")
        if resolved != head:
            raise GateError("push each branch tip from its own clean checkout")
    require_clean_head(root)


def command() -> int:
    if len(sys.argv) not in EXPECTED_ARGUMENT_COUNTS:
        raise GateError(
            "usage: Scripts/QualityReceipt.py "
            "[lint-index|lint-head|verify-clean-head|verify-head COMMIT TREE|verify-push]"
        )

    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel"))
    operation = sys.argv[1]
    if operation == "verify-clean-head" and len(sys.argv) == 2:
        require_clean_head(root)
        return 0
    if operation == "verify-head" and len(sys.argv) == VERIFY_HEAD_ARGUMENT_COUNT:
        verify_head(root, sys.argv[2], sys.argv[3])
        return 0
    if operation == "verify-push":
        verify_push(root)
        return 0
    if operation == "lint-index":
        tree = tree_for(root, "index")
    elif operation == "lint-head":
        tree = tree_for(root, "head")
    else:
        raise GateError("unknown quality receipt operation")

    fingerprint = toolchain_fingerprint()
    guard = "index" if operation == "lint-index" else "head"
    return run_lint(
        root,
        tree,
        fingerprint,
        tree_guard=guard,
        fingerprint_supplier=toolchain_fingerprint,
    )


if __name__ == "__main__":
    try:
        sys.exit(command())
    except (GateError, OSError, subprocess.CalledProcessError) as error:
        print(f"Quality receipt check failed: {error}", file=sys.stderr)
        sys.exit(1)
