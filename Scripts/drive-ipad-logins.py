#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

# Drives iPad Safari card authentication logins to card.refineid.fi, suomi.fi, and posti.fi/omaposti.
#
# Usage:
#   Scripts/drive-ipad-logins.py [--site <card|suomi|omaposti|all>] [--direct] [--udid <simulator-udid>]

from __future__ import annotations

import argparse
from datetime import datetime
import glob
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def find_ipad_udid() -> str | None:
    try:
        res = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(res.stdout)
        for runtime, devices in data.get("devices", {}).items():
            if "iOS" not in runtime:
                continue
            for dev in devices:
                if "iPad" in dev.get("name", ""):
                    return str(dev.get("udid"))
    except Exception:
        pass
    return None


def clean_safari(udid: str) -> None:
    print("==> Clearing Safari tabs and state on iPad simulator...")
    subprocess.run(["xcrun", "simctl", "terminate", udid, "com.apple.mobilesafari"], check=False)

    device_safari = Path.home() / f"Library/Developer/CoreSimulator/Devices/{udid}/data/Library/Safari"
    if device_safari.is_dir():
        for pattern in ["SafariTabs.db*", "BrowserState.db*", "CloudTabs.db*"]:
            for match in device_safari.glob(pattern):
                try:
                    match.unlink(missing_ok=True)
                except OSError:
                    pass

    container_res = subprocess.run(
        ["xcrun", "simctl", "get_app_container", udid, "com.apple.mobilesafari", "data"],
        capture_output=True,
        text=True,
        check=False,
    )
    if container_res.returncode == 0 and container_res.stdout.strip():
        data_container = Path(container_res.stdout.strip())
        if data_container.is_dir():
            for sub in ["Library/Safari", "Library/Saved Application State", "Library/Caches"]:
                target_dir = data_container / sub
                if target_dir.is_dir():
                    for item in target_dir.iterdir():
                        if item.is_dir():
                            shutil.rmtree(item, ignore_errors=True)
                        else:
                            item.unlink(missing_ok=True)


def run_direct_login(udid: str, target_url: str, site_name: str) -> None:
    clean_safari(udid)
    print(f"==> Direct opening Safari on iPad simulator to: {target_url} ({site_name})")
    subprocess.run(["xcrun", "simctl", "openurl", udid, target_url], check=False)
    time.sleep(4)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    screenshot_path = f"/tmp/ipad_login_{site_name}_{timestamp}.png"
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", screenshot_path], check=False)
    print(f"==> Captured screenshot: {screenshot_path}")


def run_uitest_login(udid: str, repo_root: Path, test_method: str, site_name: str) -> None:
    clean_safari(udid)
    print(f"==> Running XCUITest driver for {site_name} ({test_method})...")
    env = os.environ.copy()
    env["TEST_RUNNER_REFINEID_REAL_CARD_TESTS"] = "1"
    env["TEST_RUNNER_REFINEID_SAFARI_OPEN_VIA_APP"] = "1"
    cmd = [
        "xcodebuild",
        "test",
        "-project",
        str(repo_root / "RefineID.xcodeproj"),
        "-scheme",
        "RefineID",
        "-testPlan",
        "RefineIDUITests",
        "-destination",
        f"platform=iOS Simulator,id={udid}",
        f"-only-testing:RefineIDUITests/SafariCardLoginUITests/{test_method}",
        "CODE_SIGNING_ALLOWED=NO",
        "CODE_SIGN_IDENTITY=",
    ]
    subprocess.run(cmd, env=env, check=False)


def drive_site(target: str, udid: str, repo_root: Path, direct: bool) -> None:
    if target == "card":
        if direct:
            run_direct_login(udid, "https://card.refineid.fi", "card_refineid")
        else:
            run_uitest_login(udid, repo_root, "testLoginCardRefineID", "card.refineid.fi")
    elif target == "suomi":
        if direct:
            run_direct_login(udid, "https://www.suomi.fi", "suomi_fi")
        else:
            run_uitest_login(udid, repo_root, "testLoginSuomiFi", "suomi.fi")
    elif target == "omaposti":
        if direct:
            run_direct_login(udid, "https://www.posti.fi/omaposti", "omaposti")
        else:
            run_uitest_login(udid, repo_root, "testLoginOmaPosti", "posti.fi/omaposti")
    elif target == "all":
        drive_site("card", udid, repo_root, direct)
        drive_site("suomi", udid, repo_root, direct)
        drive_site("omaposti", udid, repo_root, direct)
    else:
        print(f"Unknown site: {target}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent

    parser = argparse.ArgumentParser(
        description="Drives iPad Safari card authentication logins to card.refineid.fi, suomi.fi, and posti.fi/omaposti."
    )
    parser.add_argument(
        "--site",
        choices=["card", "suomi", "omaposti", "all"],
        default="all",
        help="Site to log into (default: all)",
    )
    parser.add_argument(
        "--direct",
        action="store_true",
        help="Open URLs directly in Safari instead of running XCUITest driver",
    )
    parser.add_argument(
        "--udid",
        type=str,
        default="",
        help="Simulator UDID (default: auto-detected iPad simulator)",
    )
    args = parser.parse_args()

    udid = args.udid or find_ipad_udid()
    if not udid:
        print("Error: No available iPad simulator found.", file=sys.stderr)
        sys.exit(1)

    print(f"==> Using iPad simulator: {udid}")

    booted_res = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "booted"],
        capture_output=True,
        text=True,
        check=False,
    )
    if booted_res.returncode == 0:
        for line in booted_res.stdout.splitlines():
            if "iPad" not in line:
                match = re.search(r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", line, re.I)
                if match:
                    subprocess.run(["xcrun", "simctl", "shutdown", match.group(0)], check=False)

    subprocess.run(["xcrun", "simctl", "boot", udid], check=False)

    drive_site(args.site, udid, repo_root, args.direct)
    print("==> Login driver runs completed.")


if __name__ == "__main__":
    main()
