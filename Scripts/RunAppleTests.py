#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
"""Run xcodebuild test with a deadline and cleanup restricted to its own jobs.

Usage: python3 Scripts/RunAppleTests.py <xcodebuild test arguments>

The command is always xcodebuild test. Derived data must remain inside this
checkout. Test output is streamed to stdout/stderr unchanged and scanned for
compiler or linker warnings so downgraded warnings fail like errors; supervisor
errors contain no arguments, process identifiers, device identifiers, or
captured test output.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
import contextlib
from dataclasses import dataclass
from enum import Enum
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import threading
import time
from typing import IO

SUCCESS_EXIT_STATUS = 0
FAILURE_EXIT_STATUS = 1
USAGE_EXIT_STATUS = 2
TIMEOUT_EXIT_STATUS = 124
SIGNAL_EXIT_STATUS_BASE = 128
SECONDS_PER_MINUTE = 60
DEFAULT_TIMEOUT_MINUTES = 15
DEFAULT_TIMEOUT_SECONDS = DEFAULT_TIMEOUT_MINUTES * SECONDS_PER_MINUTE
TERMINATION_GRACE_SECONDS = 10
PROGRAM_ARGUMENT_START = 1
SIGNAL_READ_BUFFER_BYTES = 4096
STREAM_READ_BUFFER_BYTES = 8192
NO_EVENTS = 0
NO_WAIT_SECONDS = 0
PROCESS_ROW_SPLIT_LIMIT = 3
PROCESS_SNAPSHOT_TIMEOUT_SECONDS = 5
MINIMUM_PROCESS_IDENTIFIER = 1
SLEEPING_PROCESS_STATE = "S"
ZOMBIE_PROCESS_STATE_PREFIX = "Z"
XCODEBUILD = "/usr/bin/xcodebuild"
PS = "/bin/ps"
DEFAULT_DERIVED_DATA = "build/DerivedData"
DERIVED_DATA_OPTION = "-derivedDataPath"
TEST_ACTION = "test"
COMPILER_WARNING_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^[^:\n]+\.(?:swift|c|m|mm|h|hpp):\d+:\d+:\s+warning:"),
    re.compile(r"^<unknown>:\d+:\s+warning:"),
    re.compile(r"^macro expansion [^:]+:\d+:\d+:\s+warning:"),
    re.compile(r"^(?:clang|swiftc?|ld):\s+warning:"),
)
OTHER_ACTIONS = frozenset(
    {
        "build",
        "build-for-testing",
        "test-without-building",
        "analyze",
        "archive",
        "clean",
        "install",
        "installsrc",
        "exportArchive",
        "-exportArchive",
        "-exportNotarizedApp",
    }
)


@dataclass(frozen=True)
class ProcessRecord:
    pid: int
    group: int
    executable: Path
    state: str = SLEEPING_PROCESS_STATE

    def __post_init__(self) -> None:
        if self.pid < MINIMUM_PROCESS_IDENTIFIER or self.group < MINIMUM_PROCESS_IDENTIFIER:
            raise ValueError("process identifiers must be positive")
        if not self.executable.is_absolute():
            raise ValueError("process executables must use absolute paths")


class TestInterruption(Exception):
    def __init__(self, signum: int) -> None:
        self.signum = signum


class SignalEvents:
    """Queue cancellation signals without interrupting child creation."""

    def __enter__(self) -> SignalEvents:
        self.requested: list[int] = []
        self.reader, self.writer = os.pipe()
        os.set_blocking(self.reader, False)
        os.set_blocking(self.writer, False)
        self.previous_wakeup = signal.set_wakeup_fd(self.writer)
        self.previous_handlers = {
            signum: signal.signal(signum, self.receive)
            for signum in (signal.SIGINT, signal.SIGTERM)
        }
        return self

    def receive(self, signum: int, _frame: object) -> None:
        self.requested.append(signum)

    def raise_if_requested(self) -> None:
        if self.requested:
            raise TestInterruption(self.requested.pop())

    def __exit__(self, *_: object) -> None:
        for signum, handler in self.previous_handlers.items():
            signal.signal(signum, handler)
        signal.set_wakeup_fd(self.previous_wakeup)
        os.close(self.reader)
        os.close(self.writer)


class ProcessOutcome(Enum):
    """What waiting on tracked processes concluded."""

    EXITED = "exited"
    TIMED_OUT = "timed_out"
    NOT_TRACKED = "not_tracked"


class ProcessEvents:
    """Track process exit notifications without sampling process state."""

    def __init__(self, cancellation: SignalEvents | None = None) -> None:
        self.queue = select.kqueue()
        self.pending: set[int] = set()
        self.exited: set[int] = set()
        self.cancellation = cancellation
        if cancellation is not None:
            event = select.kevent(
                cancellation.reader, filter=select.KQ_FILTER_READ, flags=select.KQ_EV_ADD
            )
            self.queue.control([event], NO_EVENTS, NO_WAIT_SECONDS)

    def __enter__(self) -> ProcessEvents:
        return self

    def __exit__(self, *_: object) -> None:
        self.queue.close()

    def add(self, pid: int) -> None:
        if pid in self.pending:
            return
        self.exited.discard(pid)
        event = select.kevent(
            pid,
            filter=select.KQ_FILTER_PROC,
            flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
            fflags=select.KQ_NOTE_EXIT,
        )
        try:
            self.queue.control([event], NO_EVENTS, NO_WAIT_SECONDS)
        except ProcessLookupError:
            self.exited.add(pid)
            return
        self.pending.add(pid)

    def wait(self, timeout: float) -> ProcessOutcome:
        return self.wait_for(None, timeout)

    def wait_for(self, pid: int | None, timeout: float) -> ProcessOutcome:
        if pid is not None and pid not in self.pending:
            return ProcessOutcome.EXITED if pid in self.exited else ProcessOutcome.NOT_TRACKED
        deadline = time.monotonic() + timeout
        if self.cancellation is not None:
            self.cancellation.raise_if_requested()
        while self.pending and (pid is None or pid in self.pending):
            remaining = max(NO_WAIT_SECONDS, deadline - time.monotonic())
            events = self.queue.control(None, len(self.pending), remaining)
            if not events:
                return ProcessOutcome.TIMED_OUT
            for event in events:
                if event.filter == select.KQ_FILTER_PROC:
                    self.pending.discard(event.ident)
                    self.exited.add(event.ident)
                elif self.cancellation is not None:
                    os.read(self.cancellation.reader, SIGNAL_READ_BUFFER_BYTES)
                    self.cancellation.raise_if_requested()
        return ProcessOutcome.EXITED


def process_snapshot() -> tuple[ProcessRecord, ...]:
    result = subprocess.run(
        [PS, "-axo", "pid=,pgid=,stat=,comm="],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=PROCESS_SNAPSHOT_TIMEOUT_SECONDS,
    )
    records = []
    for row in result.stdout.splitlines():
        fields = row.strip().split(maxsplit=PROCESS_ROW_SPLIT_LIMIT)
        try:
            pid, group, state, executable = fields
            records.append(ProcessRecord(int(pid), int(group), Path(executable).resolve(), state))
        except ValueError:
            continue
    return tuple(records)


def owned_records(
    records: Sequence[ProcessRecord],
    group: int,
    products: Path | None,
    preexisting: Mapping[int, Path],
) -> tuple[ProcessRecord, ...]:
    # A baseline identifier reused by another executable is new work, not
    # preexisting state, so only an unchanged executable keeps its exemption.
    return tuple(
        record
        for record in records
        if not record.state.startswith(ZOMBIE_PROCESS_STATE_PREFIX)
        and (
            record.group == group
            or (
                products is not None
                and preexisting.get(record.pid) != record.executable
                and record.executable.is_relative_to(products)
            )
        )
    )


def signal_group(group: int, signum: int) -> None:
    with contextlib.suppress(ProcessLookupError, PermissionError):
        os.killpg(group, signum)


def signal_external_records(records: Sequence[ProcessRecord], group: int, signum: int) -> bool:
    # Recheck executable and group before signaling a reparented process.
    requested = {record.pid: record for record in records if record.group != group}
    if not requested:
        return True
    try:
        current = process_snapshot()
    except (OSError, subprocess.SubprocessError):
        return False
    for record in current:
        original = requested.get(record.pid)
        if (
            original is not None
            and record.executable == original.executable
            and record.group == original.group
            and not record.state.startswith(ZOMBIE_PROCESS_STATE_PREFIX)
        ):
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.kill(record.pid, signum)
    return True


def ownership_is_clear(group: int, products: Path | None, preexisting: Mapping[int, Path]) -> bool:
    try:
        return not owned_records(process_snapshot(), group, products, preexisting)
    except (OSError, subprocess.SubprocessError):
        return False


def cleanup(
    process: subprocess.Popen[bytes],
    products: Path | None,
    preexisting: Mapping[int, Path],
    grace: float,
    leader_exited: bool = False,
) -> bool:
    """Stop the private group and new executables from this products tree only."""
    with ProcessEvents() as events:
        if not leader_exited:
            events.add(process.pid)
        survey_succeeded = True
        try:
            records = owned_records(process_snapshot(), process.pid, products, preexisting)
        except (OSError, subprocess.SubprocessError):
            records = ()
            survey_succeeded = False
        for record in records:
            events.add(record.pid)
        if not leader_exited or any(record.group == process.pid for record in records):
            signal_group(process.pid, signal.SIGTERM)
        survey_succeeded = (
            signal_external_records(records, process.pid, signal.SIGTERM) and survey_succeeded
        )
        if events.wait(grace) is ProcessOutcome.EXITED:
            process.wait()
            return survey_succeeded and ownership_is_clear(process.pid, products, preexisting)
        try:
            remaining = owned_records(process_snapshot(), process.pid, products, preexisting)
        except (OSError, subprocess.SubprocessError):
            remaining = ()
            survey_succeeded = False
        for record in remaining:
            events.add(record.pid)
        # A dissolved group identifier may be reused, so signal the group
        # only while the survey still places members in it.
        if any(record.group == process.pid for record in remaining):
            signal_group(process.pid, signal.SIGKILL)
        survey_succeeded = (
            signal_external_records(remaining, process.pid, signal.SIGKILL) and survey_succeeded
        )
        complete = events.wait(grace) is ProcessOutcome.EXITED
        if process.pid not in events.pending:
            process.wait()
        return (
            complete and survey_succeeded and ownership_is_clear(process.pid, products, preexisting)
        )


def exit_status(status: int) -> int:
    return SIGNAL_EXIT_STATUS_BASE - status if status < SUCCESS_EXIT_STATUS else status


def has_compiler_warning(line: str) -> bool:
    """Return True if a build/test output line is a compiler or linker warning."""
    return any(pattern.search(line) is not None for pattern in COMPILER_WARNING_PATTERNS)


def forward_and_scan(
    source: IO[bytes], target: IO[bytes], warning_detected: threading.Event
) -> None:
    """Stream bytes live from `source` to `target` while scanning complete lines."""
    fd = source.fileno()
    pending = bytearray()
    try:
        while True:
            try:
                chunk = os.read(fd, STREAM_READ_BUFFER_BYTES)
            except OSError:
                break
            if not chunk:
                break
            with contextlib.suppress(OSError):
                target.write(chunk)
                target.flush()
            pending.extend(chunk)
            while True:
                newline = pending.find(b"\n")
                if newline < 0:
                    break
                line = bytes(pending[:newline]).decode("utf-8", errors="replace").rstrip("\r")
                del pending[: newline + 1]
                if has_compiler_warning(line):
                    warning_detected.set()
        if pending:
            line = bytes(pending).decode("utf-8", errors="replace").rstrip("\r")
            if has_compiler_warning(line):
                warning_detected.set()
    finally:
        with contextlib.suppress(OSError):
            source.close()


def supervise(
    command: Sequence[str],
    derived_data: Path,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    grace: float = TERMINATION_GRACE_SECONDS,
) -> int:
    derived_data = derived_data.resolve()
    products = (derived_data / "Build" / "Products").resolve()
    if not products.is_relative_to(derived_data):
        raise ValueError("build products must remain inside derived data")
    process = None
    stream_threads: list[threading.Thread] = []
    warning_detected = threading.Event()
    status = FAILURE_EXIT_STATUS
    completed_normally = False
    cleaned_up = True
    with SignalEvents() as cancellation:
        try:
            baseline = {record.pid: record.executable for record in process_snapshot()}
            cancellation.raise_if_requested()
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
            if process.stdout is not None:
                out_thread = threading.Thread(
                    target=forward_and_scan,
                    args=(process.stdout, sys.stdout.buffer, warning_detected),
                    daemon=True,
                )
                out_thread.start()
                stream_threads.append(out_thread)
            if process.stderr is not None:
                err_thread = threading.Thread(
                    target=forward_and_scan,
                    args=(process.stderr, sys.stderr.buffer, warning_detected),
                    daemon=True,
                )
                err_thread.start()
                stream_threads.append(err_thread)
            with ProcessEvents(cancellation) as events:
                events.add(process.pid)
                if events.wait(timeout) is ProcessOutcome.EXITED:
                    completed_normally = True
                else:
                    print(
                        "Apple test runner failed: invocation exceeded its deadline.",
                        file=sys.stderr,
                    )
                    status = TIMEOUT_EXIT_STATUS
        except TestInterruption as interruption:
            print("Apple test runner cancelled: interruption requested.", file=sys.stderr)
            status = SIGNAL_EXIT_STATUS_BASE + interruption.signum
        finally:
            previous = {
                signum: signal.signal(signum, signal.SIG_IGN)
                for signum in (signal.SIGINT, signal.SIGTERM)
            }
            try:
                if process is not None:
                    cleaned_up = cleanup(process, products, baseline, grace, completed_normally)
                    if not cleaned_up:
                        print(
                            "Apple test runner failed: owned process cleanup did not finish.",
                            file=sys.stderr,
                        )
            finally:
                for thread in stream_threads:
                    thread.join(timeout=grace)
                for signum, handler in previous.items():
                    signal.signal(signum, handler)
    if completed_normally and process is not None:
        status = (
            exit_status(process.returncode)
            if process.returncode is not None
            else FAILURE_EXIT_STATUS
        )
        if not cleaned_up and status == SUCCESS_EXIT_STATUS:
            status = FAILURE_EXIT_STATUS
        if warning_detected.is_set() and status == SUCCESS_EXIT_STATUS:
            print(
                "Apple test runner failed: compiler warning detected.",
                file=sys.stderr,
            )
            status = FAILURE_EXIT_STATUS
    return status


def command_for_arguments(arguments: Sequence[str], root: Path) -> tuple[list[str], Path]:
    if not arguments or any(argument in OTHER_ACTIONS for argument in arguments):
        raise ValueError("provide xcodebuild test options only")
    ui_selected = any(
        argument.startswith("-only-testing:RefineIDUITests") for argument in arguments
    )
    option_values = iter(arguments)
    ui_selected = ui_selected or any(
        argument == "-testPlan" and next(option_values, "") == "RefineIDUITests"
        for argument in option_values
    )
    if ui_selected and os.environ.get("REFINEID_UI_TEST_GUEST") != "tart":
        raise ValueError("UI tests require the headless guest workflow")
    if any(argument.startswith(f"{DERIVED_DATA_OPTION}=") for argument in arguments):
        raise ValueError("provide the derived-data directory as a separate argument")
    options = iter(arguments)
    derived_data = None
    for argument in options:
        if argument == DERIVED_DATA_OPTION:
            if derived_data is not None:
                raise ValueError("provide one derived-data directory")
            derived_data = Path(next(options, ""))
            if not str(derived_data) or str(derived_data) == ".":
                raise ValueError("provide a derived-data directory")
    derived_data = (root / (derived_data or Path(DEFAULT_DERIVED_DATA))).resolve()
    if not derived_data.is_relative_to(root.resolve()) or derived_data == root.resolve():
        raise ValueError("derived data must be inside this checkout")
    command = [XCODEBUILD, TEST_ACTION, *arguments]
    if DERIVED_DATA_OPTION not in arguments:
        command.extend([DERIVED_DATA_OPTION, str(derived_data)])
    return command, derived_data


def main(arguments: Sequence[str]) -> int:
    if not hasattr(select, "kqueue"):
        print(
            "Apple test runner failed: macOS process notifications are required.", file=sys.stderr
        )
        return FAILURE_EXIT_STATUS
    try:
        command, derived_data = command_for_arguments(arguments, Path.cwd())
    except ValueError as error:
        print(f"Apple test runner: {error}.", file=sys.stderr)
        return USAGE_EXIT_STATUS

    try:
        return supervise(command, derived_data)
    except (OSError, ValueError, subprocess.SubprocessError):
        print("Apple test runner failed: could not supervise the test process.", file=sys.stderr)
        return FAILURE_EXIT_STATUS


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[PROGRAM_ARGUMENT_START:]))
