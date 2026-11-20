#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
"""Run UI tests in an existing stopped Tart VM without a host graphics window.

Usage: Scripts/test-ui-tart.py [VM_NAME] [all|macos-mvp]

The VM needs macOS 26 or later, the project's current Xcode SDK/toolchain,
Python 3, and the Tart guest agent. Provisioning is explicit. The runner stops
only processes it launches; it does not stop an existing VM by name.
"""

from __future__ import annotations

from collections.abc import Sequence
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

import RunAppleTests as runner

DEFAULT_VM_NAME = "macos-ci"
DEFAULT_TEST_SCOPE = "all"
TEST_SCOPES = frozenset({DEFAULT_TEST_SCOPE, "macos-mvp"})
VM_READY_TIMEOUT_SECONDS = 120
TART_COMMAND_TIMEOUT_SECONDS = 30
TART_COMMAND_ALLOWANCE_SECONDS = 5
GUEST_CLEANUP_ALLOWANCE_SECONDS = 30
VM_STOP_TIMEOUT_SECONDS = 10
READINESS_OUTPUT_LIMIT = 1024
MAXIMUM_ARGUMENT_COUNT = 2
VM_ARGUMENT_INDEX = 0
SCOPE_ARGUMENT_INDEX = 1
PROGRAM_ARGUMENT_START = 1
GUEST_DRIVER = """
import os, runpy, sys
os.chdir('/Volumes/My Shared Files/refineid-apple')
sys.path.insert(0, 'Scripts')
scope = sys.argv.pop()
if scope == 'macos-mvp':
    script = 'Scripts/test.py'
    sys.argv = [script, scope]
else:
    script = 'Scripts/RunAppleTests.py'
    sys.argv = [script, '-derivedDataPath', 'build/DerivedData', '-scheme', 'RefineID',
        '-testPlan', 'RefineIDUITests', '-destination', 'platform=macOS']
runpy.run_path(script, run_name='__main__')
"""


def stopped_vm(tart: str, vm_name: str, root: Path) -> bool:
    # Tart's List and VMDirectory commands define Name and State:
    # https://github.com/cirruslabs/tart/tree/main/Sources/tart
    result = subprocess.run(
        [tart, "list", "--source", "local", "--format", "json"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=TART_COMMAND_TIMEOUT_SECONDS,
        check=False,
    )
    if result.returncode != runner.SUCCESS_EXIT_STATUS:
        return False
    try:
        matches = [vm for vm in json.loads(result.stdout) if vm.get("Name") == vm_name]
        return bool(matches) and all(vm.get("State") == "stopped" for vm in matches)
    except (ValueError, TypeError, AttributeError):
        return False


def run_tart_tests(vm_name: str, scope: str, root: Path) -> int:
    tart = shutil.which("tart")
    if tart is None:
        print("UI test setup failed: Tart is not installed.", file=sys.stderr)
        return runner.FAILURE_EXIT_STATUS
    processes: list[subprocess.Popen[bytes]] = []
    exited: set[int] = set()
    status = runner.FAILURE_EXIT_STATUS
    with runner.SignalEvents() as cancellation:
        try:
            if not stopped_vm(tart, vm_name, root):
                print("UI test setup failed: an existing stopped VM is required.", file=sys.stderr)
                return runner.FAILURE_EXIT_STATUS
            cancellation.raise_if_requested()
            with runner.ProcessEvents(cancellation) as events:
                vm = subprocess.Popen(
                    [tart, "run", vm_name, "--no-graphics", "--dir", f"refineid-apple:{root}"],
                    cwd=root,
                    start_new_session=True,
                )
                processes.append(vm)
                events.add(vm.pid)
                ready = subprocess.Popen(
                    [
                        tart,
                        "ip",
                        vm_name,
                        "--resolver",
                        "agent",
                        "--wait",
                        str(VM_READY_TIMEOUT_SECONDS),
                    ],
                    cwd=root,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
                processes.append(ready)
                events.add(ready.pid)
                print("Waiting for the UI test guest agent.", flush=True)
                if (
                    events.wait_for(
                        ready.pid, VM_READY_TIMEOUT_SECONDS + TART_COMMAND_ALLOWANCE_SECONDS
                    )
                    is not runner.ProcessOutcome.EXITED
                ):
                    print(
                        "UI test setup failed: the guest agent exceeded its readiness deadline.",
                        file=sys.stderr,
                    )
                    return runner.FAILURE_EXIT_STATUS
                exited.add(ready.pid)
                if vm.pid not in events.pending:
                    exited.add(vm.pid)
                    print(
                        "UI test setup failed: the owned VM process stopped before testing.",
                        file=sys.stderr,
                    )
                    return runner.FAILURE_EXIT_STATUS
                # Readiness output is an address. Consume it without displaying or
                # storing it; only readiness and the exit status affect the run.
                assert ready.stdout is not None
                os.set_blocking(ready.stdout.fileno(), False)
                try:
                    address = os.read(ready.stdout.fileno(), READINESS_OUTPUT_LIMIT)
                except BlockingIOError:
                    address = b""
                ready.stdout.close()
                ready_clean = runner.cleanup(ready, None, {}, VM_STOP_TIMEOUT_SECONDS, True)
                processes.remove(ready)
                if (
                    not ready_clean
                    or ready.returncode != runner.SUCCESS_EXIT_STATUS
                    or not address.strip()
                ):
                    print(
                        "UI test setup failed: the guest agent did not become ready.",
                        file=sys.stderr,
                    )
                    return runner.FAILURE_EXIT_STATUS
                print("Running UI tests inside the headless guest.", flush=True)
                tests = subprocess.Popen(
                    [
                        tart,
                        "exec",
                        vm_name,
                        "/usr/bin/env",
                        "REFINEID_UI_TEST_GUEST=tart",
                        "python3",
                        "-c",
                        GUEST_DRIVER,
                        scope,
                    ],
                    cwd=root,
                    start_new_session=True,
                )
                processes.append(tests)
                events.add(tests.pid)
                if (
                    events.wait_for(
                        tests.pid, runner.DEFAULT_TIMEOUT_SECONDS + GUEST_CLEANUP_ALLOWANCE_SECONDS
                    )
                    is not runner.ProcessOutcome.EXITED
                ):
                    print(
                        "UI test runner failed: guest invocation exceeded its deadline.",
                        file=sys.stderr,
                    )
                    return runner.TIMEOUT_EXIT_STATUS
                exited.add(tests.pid)
                tests_clean = runner.cleanup(tests, None, {}, VM_STOP_TIMEOUT_SECONDS, True)
                processes.remove(tests)
                status = (
                    runner.exit_status(tests.returncode)
                    if tests.returncode is not None
                    else runner.FAILURE_EXIT_STATUS
                )
                if not tests_clean and status == runner.SUCCESS_EXIT_STATUS:
                    status = runner.FAILURE_EXIT_STATUS
                if vm.pid not in events.pending:
                    exited.add(vm.pid)
        except runner.TestInterruption as interruption:
            print("UI test runner cancelled: interruption requested.", file=sys.stderr)
            status = runner.SIGNAL_EXIT_STATUS_BASE + interruption.signum
        except (OSError, subprocess.SubprocessError):
            print("UI test setup failed: could not supervise the guest workflow.", file=sys.stderr)
            status = runner.FAILURE_EXIT_STATUS
        finally:
            previous = {
                signum: signal.signal(signum, signal.SIG_IGN)
                for signum in (signal.SIGINT, signal.SIGTERM)
            }
            try:
                for process in reversed(processes):
                    if not runner.cleanup(
                        process, None, {}, VM_STOP_TIMEOUT_SECONDS, process.pid in exited
                    ):
                        print(
                            "UI test cleanup failed: an owned process did not finish.",
                            file=sys.stderr,
                        )
                        status = runner.FAILURE_EXIT_STATUS
                    if process.stdout is not None:
                        process.stdout.close()
            finally:
                for signum, handler in previous.items():
                    signal.signal(signum, handler)
    return status


def main(arguments: Sequence[str]) -> int:
    if len(arguments) > MAXIMUM_ARGUMENT_COUNT:
        print("Usage: Scripts/test-ui-tart.py [VM_NAME] [all|macos-mvp]", file=sys.stderr)
        return runner.USAGE_EXIT_STATUS
    vm_name = arguments[VM_ARGUMENT_INDEX] if arguments else DEFAULT_VM_NAME
    scope = (
        arguments[SCOPE_ARGUMENT_INDEX]
        if len(arguments) == MAXIMUM_ARGUMENT_COUNT
        else DEFAULT_TEST_SCOPE
    )
    if scope not in TEST_SCOPES:
        print("UI test setup failed: unknown test scope.", file=sys.stderr)
        return runner.USAGE_EXIT_STATUS
    return run_tart_tests(vm_name, scope, Path(__file__).resolve().parent.parent)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[PROGRAM_ARGUMENT_START:]))
