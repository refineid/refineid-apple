#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Runs RefineID macOS UI tests headlessly inside an isolated Tart macOS VM.
#
# Because macOS XCUITest requires an active WindowServer session with Accessibility
# (AXUIElement) event synthesis, running UI tests on a developer's workstation steals
# keyboard/mouse focus and pops up windows. Running them inside a headless Tart VM
# completely isolates WindowServer and prevents desktop disruption.
#
# Usage:
#   Scripts/test-ui-tart.py [VM_NAME]
#
# Default VM_NAME: "macos-ci"
#
# Prerequisites:
#   brew install cirruslabs/cli/tart
#   tart pull ghcr.io/cirruslabs/macos-sonoma-xcode:latest macos-ci
#   (or any macOS VM with Xcode installed)

from __future__ import annotations

import atexit
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    os.chdir(repo_root)

    vm_name = sys.argv[1] if len(sys.argv) > 1 else "macos-ci"

    if not shutil.which("tart"):
        print(
            "Error: tart is not installed. Install it with: brew install cirruslabs/cli/tart",
            file=sys.stderr,
        )
        sys.exit(1)

    list_res = subprocess.run(["tart", "list"], capture_output=True, text=True, check=False)
    vms = [line.strip().split()[0] for line in list_res.stdout.splitlines() if line.strip()]
    if vm_name not in vms:
        print(f'Tart VM "{vm_name}" not found.\n', file=sys.stderr)
        print("Available Tart VMs:", file=sys.stderr)
        if list_res.stdout:
            print(list_res.stdout, file=sys.stderr)
        print("\nTo pull a pre-configured macOS VM with Xcode:", file=sys.stderr)
        print(
            f"  tart pull ghcr.io/cirruslabs/macos-sonoma-xcode:latest {vm_name}\n", file=sys.stderr
        )
        print("Or clone an existing VM:", file=sys.stderr)
        print(f"  tart clone <source-vm> {vm_name}", file=sys.stderr)
        sys.exit(1)

    vm_runner_dir = "/Volumes/My Shared Files/refineid-apple"
    print(f'==> Running RefineID macOS UI tests in headless Tart VM "{vm_name}"...')

    vm_proc = subprocess.Popen(
        ["tart", "run", vm_name, "--no-gui", "--dir", f"refineid-apple:{repo_root}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    def cleanup() -> None:
        print("\n==> Stopping Tart VM...")
        subprocess.run(["tart", "stop", vm_name], capture_output=True, check=False)
        if vm_proc.poll() is None:
            vm_proc.kill()

    atexit.register(cleanup)

    print("==> Waiting for VM IP...")
    vm_ip = ""
    for _ in range(30):
        ip_res = subprocess.run(
            ["tart", "ip", vm_name], capture_output=True, text=True, check=False
        )
        if ip_res.returncode == 0 and ip_res.stdout.strip():
            vm_ip = ip_res.stdout.strip()
            break
        time.sleep(2)

    if not vm_ip:
        print(f'Error: Could not retrieve IP for VM "{vm_name}".', file=sys.stderr)
        sys.exit(1)

    print(f"==> Tart VM online at {vm_ip}. Running UI tests...")
    guest_command = (
        f"cd '{vm_runner_dir}' && "
        "xcodebuild test -scheme RefineID -testPlan RefineIDUITests -destination 'platform=macOS'"
    )
    exec_res = subprocess.run(
        ["tart", "exec", vm_name, "/bin/sh", "-lc", guest_command],
        check=False,
    )

    if exec_res.returncode != 0:
        sys.exit(exec_res.returncode)

    print("\n==> Headless UI tests in Tart VM completed successfully!")


if __name__ == "__main__":
    main()
