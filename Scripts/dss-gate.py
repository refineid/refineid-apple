#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Usage: Scripts/dss-gate.py
#
# The independent validation gate for the Swift signers. Runs
# RefineIDTests/DssGateExportTests, which signs a PDF and an ASiC-E
# container through the app's own timestamp, evidence and archive stages
# against synthetic authorities, then has the EU DSS validator judge both:
#
#   swift-pades.pdf      PAdES-BASELINE-LTA, TOTAL_PASSED
#   swift-asic-e.asice   XAdES-BASELINE-LTA, TOTAL_PASSED, ASiC-E
#
# A release build saves only these levels, so anything less fails.
# Documentation/testing-strategy.md describes the gate.
#
# DSS 6.5.1 is pinned in Scripts/dss-gate/dss.lock: each jar is fetched
# once from Maven Central into the cache and refused unless its SHA-256
# matches. After that nothing here uses a network: the test answers its
# requests in memory and DSS runs with no online source.
#
# Environment:
#   REFINEID_DSS_CACHE  jar cache (default ~/.cache/refineid/dss-gate)
#   JAVA_HOME           a JDK 17 or later; otherwise found automatically

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request


def fail(message: str) -> None:
    print(f"dss-gate: {message}", file=sys.stderr)
    sys.exit(1)


def find_jdk_bin() -> Path | None:
    candidates: list[str] = []
    if env_java_home := os.environ.get("JAVA_HOME"):
        candidates.append(env_java_home)

    try:
        res = subprocess.run(
            ["/usr/libexec/java_home"],
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode == 0 and res.stdout.strip():
            candidates.append(res.stdout.strip())
    except OSError:
        pass

    try:
        res = subprocess.run(
            ["brew", "--prefix", "openjdk"],
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode == 0 and res.stdout.strip():
            candidates.append(res.stdout.strip())
    except OSError:
        pass

    for candidate_str in candidates:
        candidate = Path(candidate_str)
        java = candidate / "bin" / "java"
        javac = candidate / "bin" / "javac"
        if java.is_file() and javac.is_file():
            try:
                res1 = subprocess.run([str(java), "-version"], capture_output=True, check=False)
                res2 = subprocess.run([str(javac), "-version"], capture_output=True, check=False)
                if res1.returncode == 0 and res2.returncode == 0:
                    return candidate / "bin"
            except OSError:
                continue

    return None


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    os.chdir(repo_root)

    lock_file = repo_root / "Scripts" / "dss-gate" / "dss.lock"
    source_file = repo_root / "Scripts" / "dss-gate" / "DssGate.java"

    if cache_env := os.environ.get("REFINEID_DSS_CACHE"):
        cache_dir = Path(cache_env)
    elif xdg_cache := os.environ.get("XDG_CACHE_HOME"):
        cache_dir = Path(xdg_cache) / "refineid" / "dss-gate"
    else:
        cache_dir = Path.home() / ".cache" / "refineid" / "dss-gate"

    central_url = "https://repo1.maven.org/maven2"
    derived_data = repo_root / "build" / "DerivedData"
    test_host_bundle = "fi.refineid.ReFineID.testhost"
    export_name = "RefineIDDssGate"

    jdk_bin = find_jdk_bin()
    if not jdk_bin:
        fail("no JDK found: install a JDK 17 or later or set JAVA_HOME")

    cache_dir.mkdir(parents=True, exist_ok=True)
    jars: list[Path] = []

    with open(lock_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) != 2:
                continue
            digest, coordinates = parts
            coord_parts = coordinates.split(":")
            if len(coord_parts) != 3:
                continue
            group, artifact, version = coord_parts
            jar_path = cache_dir / f"{artifact}-{version}.jar"
            if not jar_path.is_file() or sha256_of_file(jar_path) != digest:
                group_path = group.replace(".", "/")
                url = f"{central_url}/{group_path}/{artifact}/{version}/{artifact}-{version}.jar"
                print(f"dss-gate: fetching {coordinates}")
                part_path = cache_dir / f"{artifact}-{version}.jar.part"
                try:
                    urllib.request.urlretrieve(url, part_path)
                except Exception as e:
                    part_path.unlink(missing_ok=True)
                    fail(f"cannot fetch {url}: {e}")

                if sha256_of_file(part_path) != digest:
                    part_path.unlink(missing_ok=True)
                    fail(f"{coordinates} does not match its SHA-256 in {lock_file}")
                part_path.rename(jar_path)

            jars.append(jar_path)

    classpath = os.pathsep.join(str(jar) for jar in jars)

    classes_dir = repo_root / "build" / "dss-gate" / "classes"
    if classes_dir.exists():
        shutil.rmtree(classes_dir)
    classes_dir.mkdir(parents=True, exist_ok=True)

    javac_cmd = [
        str(jdk_bin / "javac"),
        "-nowarn",
        "-d",
        str(classes_dir),
        "-cp",
        classpath,
        str(source_file),
    ]
    javac_res = subprocess.run(javac_cmd, check=False)
    if javac_res.returncode != 0:
        fail("compilation of DssGate.java failed")

    darwin_tmp = ""
    try:
        conf_res = subprocess.run(
            ["getconf", "DARWIN_USER_TEMP_DIR"],
            capture_output=True,
            text=True,
            check=False,
        )
        if conf_res.returncode == 0:
            darwin_tmp = conf_res.stdout.strip()
    except OSError:
        pass

    candidates: list[Path] = [
        Path.home() / "Library" / "Containers" / test_host_bundle / "Data" / "tmp" / export_name,
    ]
    if darwin_tmp:
        candidates.append(Path(darwin_tmp) / export_name)

    for candidate in candidates:
        if candidate.exists():
            shutil.rmtree(candidate, ignore_errors=True)

    print("=== Exporting the Swift signers' documents ===")
    xcode_cmd = [
        "xcodebuild",
        "test",
        "-derivedDataPath",
        str(derived_data),
        "-scheme",
        "RefineID",
        "-destination",
        "platform=macOS",
        "-only-testing:RefineIDTests/DssGateExportTests",
        "-quiet",
    ]
    xcode_res = subprocess.run(xcode_cmd, check=False)
    if xcode_res.returncode != 0:
        fail("the export test failed: the Swift signers did not finish a document")

    exported: Path | None = None
    for candidate in candidates:
        if (candidate / "anchor-ca.der").is_file():
            exported = candidate
            break

    if not exported:
        fail("the export test wrote no documents")

    failed = False

    def judge(file_name: str, expected: str, container: str) -> None:
        nonlocal failed
        java_cmd = [
            str(jdk_bin / "java"),
            "-cp",
            f"{classes_dir}{os.pathsep}{classpath}",
            "DssGate",
            "--anchor",
            str(exported / "anchor-ca.der"),
            "--anchor",
            str(exported / "anchor-tsa.der"),
            str(exported / file_name),
        ]
        res = subprocess.run(java_cmd, capture_output=True, text=True, check=False)
        report = res.stdout + res.stderr
        if res.returncode != 0:
            print(f"{file_name}: DSS failed\n{report}", file=sys.stderr)
            failed = True
            return

        lines = [line for line in report.splitlines() if line.startswith("signature ")]
        has_expected_sig = any(
            f" format={expected} indication=TOTAL_PASSED " in line for line in lines
        )
        has_expected_container = f"container={container}" in report.splitlines()

        if len(lines) == 1 and has_expected_sig and has_expected_container:
            print(f"{file_name}: {expected} TOTAL_PASSED, container {container}")
        else:
            print(
                f"{file_name}: required {expected} TOTAL_PASSED in container {container}; DSS reports\n{report}",
                file=sys.stderr,
            )
            failed = True

    print("=== Judging them with EU DSS 6.5.1 ===")
    judge("swift-pades.pdf", "PAdES-BASELINE-LTA", "-")
    judge("swift-asic-e.asice", "XAdES-BASELINE-LTA", "ASiC-E")

    if failed:
        fail("a Swift signer's document is below the release level")

    print("dss-gate: the Swift signers reached B-LTA in DSS")


if __name__ == "__main__":
    main()
