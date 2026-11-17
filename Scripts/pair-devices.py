#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
import time


def find_booted_ipad_udid() -> str:
    if env_udid := os.environ.get("IPAD_UDID"):
        return env_udid
    try:
        res = subprocess.run(
            ["xcrun", "simctl", "list", "devices"],
            capture_output=True,
            text=True,
            check=False,
        )
        for line in res.stdout.splitlines():
            if "ipad" in line.lower() and "booted" in line.lower():
                match = re.search(r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", line, re.I)
                if match:
                    return match.group(0)
    except OSError:
        pass
    return ""


def find_physical_iphone_udid() -> str:
    if env_udid := os.environ.get("IPHONE_UDID"):
        return env_udid
    try:
        res = subprocess.run(
            ["xcrun", "devicectl", "list", "devices"],
            capture_output=True,
            text=True,
            check=False,
        )
        for line in res.stdout.splitlines():
            if ("iPhone" in line or "iPad" in line) and "physical" in line:
                tokens = line.split()
                for i, tok in enumerate(tokens):
                    if tok == "(UDID)" and i > 0:
                        return tokens[i - 1]
    except OSError:
        pass
    return ""


def main() -> None:
    ipad_udid = find_booted_ipad_udid()
    iphone_udid = find_physical_iphone_udid()
    offer_log = Path("/tmp/ipad_pairing_offer.log")

    if not ipad_udid:
        print(
            "Error: No booted iPad simulator found. Start an iPad simulator first or set IPAD_UDID.",
            file=sys.stderr,
        )
        sys.exit(1)

    if not iphone_udid:
        print(
            "Error: No connected physical iOS device found. Connect a device or set IPHONE_UDID.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"==> Driving automated pairing between iPhone ({iphone_udid}) and iPad simulator ({ipad_udid})...")
    offer_log.unlink(missing_ok=True)

    # 1. Terminate running instances
    subprocess.run(["xcrun", "simctl", "terminate", ipad_udid, "fi.refineid.ReFineID"], check=False)

    # 2. The iPhone holds the card, so it shows the code (RAPP v26.11.8 section 3).
    print("==> Showing a pairing code on the iPhone...")
    log_file = open(offer_log, "w", encoding="utf-8")
    devicectl_cmd = [
        "xcrun",
        "devicectl",
        "device",
        "process",
        "launch",
        "--device",
        iphone_udid,
        "--terminate-existing",
        "--console",
        "fi.refineid.ReFineID",
        "--offer-remote-reader",
    ]
    custodian_proc = subprocess.Popen(
        devicectl_cmd,
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )

    code = ""
    for _ in range(60):
        if offer_log.is_file():
            content = offer_log.read_text(encoding="utf-8", errors="replace")
            for line in content.splitlines():
                if "offer-remote-reader: offer " in line:
                    tokens = line.split()
                    if len(tokens) >= 3:
                        code = tokens[2]
                        break
            if code:
                break
        time.sleep(0.5)

    if not code:
        print("Error: Failed to obtain the pairing code from the iPhone.", file=sys.stderr)
        if offer_log.is_file():
            print(offer_log.read_text(encoding="utf-8", errors="replace"), file=sys.stderr)
        custodian_proc.kill()
        sys.exit(1)

    # 3. The iPad requester types the code.
    print("==> Typing the pairing code on the iPad simulator...")
    env = os.environ.copy()
    env["SIMCTL_CHILD_REFINEID_PAIR_OFFER"] = code
    subprocess.run(
        [
            "xcrun",
            "simctl",
            "launch",
            "--console",
            ipad_udid,
            "fi.refineid.ReFineID",
            "--pair-with-offer",
        ],
        env=env,
        check=False,
    )

    custodian_proc.wait()
    log_file.close()
    print("==> Pairing ceremony completed between iPhone and iPad.")


if __name__ == "__main__":
    main()
