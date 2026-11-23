#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
"""Usage: python3 -B Scripts/TestRunAppleTests.py. Uses synthetic processes only."""

from contextlib import closing, suppress
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import tempfile
from typing import IO
import unittest
from unittest.mock import patch

import RunAppleTests as runner

FIXTURE_FAILURE_STATUS = 7
HOST_WAIT_SOURCE = "import signal; signal.pause()"
STALL_TIMEOUT_SECONDS = 1.0
TEST_GRACE_SECONDS = 0.2
EVENT_TIMEOUT_SECONDS = 10.0
OUTPUT_READ_LIMIT = 65536
SIGNAL_EXISTENCE_CHECK = 0
ONE_EVENT = 1
NO_EVENTS = 0
NO_WAIT_SECONDS = 0
READY_MESSAGE = "synthetic fixture ready"
SCRIPTS = Path(__file__).resolve().parent
DRIVER = """
from pathlib import Path
import sys
SCRIPT_PATH_POSITION = 1
PROGRAM_ARGUMENT_START = 1
MODULE_PATH_POSITION = 0
sys.path.insert(MODULE_PATH_POSITION, sys.argv.pop(SCRIPT_PATH_POSITION))
import RunAppleTests
root, fixture, timeout, grace = sys.argv[PROGRAM_ARGUMENT_START:]
raise SystemExit(RunAppleTests.supervise(
    [sys.executable, fixture], Path(root) / 'build' / 'DerivedData',
    timeout=float(timeout), grace=float(grace)))
"""
STALL_FIXTURE = """
import os
import signal
import subprocess
import sys
signal.signal(signal.SIGTERM, signal.SIG_IGN)
subprocess.Popen([sys.executable, '-c',
    'import signal; signal.signal(signal.SIGTERM, signal.SIG_IGN); signal.pause()'])
print('synthetic fixture ready', os.getpgrp(), flush=True)
signal.pause()
"""


def read_available(stream: IO[bytes] | None) -> str:
    assert stream is not None
    os.set_blocking(stream.fileno(), False)
    try:
        return os.read(stream.fileno(), OUTPUT_READ_LIMIT).decode()
    except BlockingIOError:
        return ""


class RunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="test-supervisor-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()

    def start(self, source: str, timeout: float = STALL_TIMEOUT_SECONDS) -> subprocess.Popen[bytes]:
        fixture = self.root / "fixture.py"
        fixture.write_text(source, encoding="ascii")
        process = subprocess.Popen(
            [
                sys.executable,
                "-c",
                DRIVER,
                str(SCRIPTS),
                str(self.root),
                str(fixture),
                str(timeout),
                str(TEST_GRACE_SECONDS),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        self.addCleanup(self.reap, process)
        return process

    def reap(self, process: subprocess.Popen[bytes]) -> None:
        if process.returncode is None:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        assert process.stdout is not None
        assert process.stderr is not None
        process.stdout.close()
        process.stderr.close()

    def finish(self, process: subprocess.Popen[bytes]) -> tuple[int, str, str]:
        with runner.ProcessEvents() as events:
            events.add(process.pid)
            self.assertIs(
                events.wait(EVENT_TIMEOUT_SECONDS),
                runner.ProcessOutcome.EXITED,
                "synthetic supervisor did not finish",
            )
        status = process.wait()
        return status, read_available(process.stdout), read_available(process.stderr)

    def ready(self, process: subprocess.Popen[bytes]) -> int:
        assert process.stdout is not None
        with closing(select.kqueue()) as events:
            notification = select.kevent(
                process.stdout.fileno(), filter=select.KQ_FILTER_READ, flags=select.KQ_EV_ADD
            )
            events.control([notification], NO_EVENTS, NO_WAIT_SECONDS)
            self.assertTrue(
                events.control(None, ONE_EVENT, EVENT_TIMEOUT_SECONDS),
                "synthetic fixture did not become ready",
            )
            line = process.stdout.readline().decode().strip()
            self.assertIn(READY_MESSAGE, line)
            return int(line.rpartition(" ")[-ONE_EVENT])

    def watch_group(self, group: int) -> runner.ProcessEvents:
        events = runner.ProcessEvents()
        for record in runner.process_snapshot():
            if record.group == group:
                events.add(record.pid)
        self.assertTrue(events.pending, "synthetic process group was not found")
        self.addCleanup(events.queue.close)
        return events

    def test_inherits_both_streams_and_preserves_success(self) -> None:
        source = "import sys; print('synthetic stdout'); print('synthetic stderr', file=sys.stderr)"
        status, stdout, stderr = self.finish(self.start(source))
        self.assertEqual(status, runner.SUCCESS_EXIT_STATUS)
        self.assertIn("synthetic stdout", stdout)
        self.assertIn("synthetic stderr", stderr)

    def test_preserves_nonzero_status(self) -> None:
        source = f"raise SystemExit({FIXTURE_FAILURE_STATUS})"
        status, _, _ = self.finish(self.start(source))
        self.assertEqual(status, FIXTURE_FAILURE_STATUS)

    def test_timeout_kills_ignoring_parent_and_descendant(self) -> None:
        process = self.start(STALL_FIXTURE)
        group = self.ready(process)
        descendants = self.watch_group(group)
        status, _, stderr = self.finish(process)
        self.assertEqual(status, runner.TIMEOUT_EXIT_STATUS)
        self.assertIn("exceeded its deadline", stderr)
        self.assertNotIn(str(self.root), stderr)
        self.assertNotIn("fixture.py", stderr)
        self.assertIs(
            descendants.wait(EVENT_TIMEOUT_SECONDS),
            runner.ProcessOutcome.EXITED,
            "owned descendants survived timeout",
        )

    def test_cancellation_reaps_owned_processes(self) -> None:
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum):
                process = self.start(STALL_FIXTURE, timeout=EVENT_TIMEOUT_SECONDS)
                group = self.ready(process)
                descendants = self.watch_group(group)
                os.kill(process.pid, signum)
                status, _, stderr = self.finish(process)
                self.assertEqual(status, runner.SIGNAL_EXIT_STATUS_BASE + signum)
                self.assertIn("interruption requested", stderr)
                self.assertIs(
                    descendants.wait(EVENT_TIMEOUT_SECONDS),
                    runner.ProcessOutcome.EXITED,
                    "owned descendants survived cancellation",
                )

    def test_wait_reports_a_watched_process_that_exits(self) -> None:
        process = subprocess.Popen([sys.executable, "-c", HOST_WAIT_SOURCE])
        try:
            with runner.ProcessEvents() as events:
                events.add(process.pid)
                process.kill()
                self.assertIs(
                    events.wait_for(process.pid, EVENT_TIMEOUT_SECONDS),
                    runner.ProcessOutcome.EXITED,
                    "a watched process that exits is not reported as exited",
                )
        finally:
            process.kill()
            process.wait()

    def test_wait_reports_a_process_that_ended_before_the_watch(self) -> None:
        process = subprocess.Popen([sys.executable, "-c", "pass"])
        process.wait()
        with runner.ProcessEvents() as events:
            events.add(process.pid)
            self.assertIs(
                events.wait_for(process.pid, EVENT_TIMEOUT_SECONDS),
                runner.ProcessOutcome.EXITED,
                "a process that had ended is not reported as exited",
            )

    def test_wait_reports_a_process_that_outlives_the_wait(self) -> None:
        process = subprocess.Popen([sys.executable, "-c", HOST_WAIT_SOURCE])
        try:
            with runner.ProcessEvents() as events:
                events.add(process.pid)
                self.assertIs(
                    events.wait_for(process.pid, TEST_GRACE_SECONDS),
                    runner.ProcessOutcome.TIMED_OUT,
                    "a process that outlived the wait is not reported as timed out",
                )
        finally:
            process.kill()
            process.wait()

    def test_wait_reports_a_process_it_never_tracked(self) -> None:
        with runner.ProcessEvents() as events:
            self.assertIs(
                events.wait_for(os.getpid(), TEST_GRACE_SECONDS),
                runner.ProcessOutcome.NOT_TRACKED,
                "a process the watch never added is not reported as untracked",
            )

    def test_preserves_unrelated_process(self) -> None:
        sleeper = subprocess.Popen([sys.executable, "-c", "import signal; signal.pause()"])
        try:
            self.finish(self.start(STALL_FIXTURE))
            os.kill(sleeper.pid, SIGNAL_EXISTENCE_CHECK)
        finally:
            sleeper.terminate()
            sleeper.wait()

    def test_reparented_products_host_is_cleaned_without_touching_preexisting_host(self) -> None:
        host = self.root / "build" / "DerivedData" / "Build" / "Products" / "Host"
        host.parent.mkdir(parents=True)
        original = next(
            record.executable for record in runner.process_snapshot() if record.pid == os.getpid()
        )
        shutil.copyfile(original, host)
        shutil.copymode(original, host)
        existing = subprocess.Popen([str(host), "-c", HOST_WAIT_SOURCE], start_new_session=True)
        try:
            source = (
                "import os, signal, subprocess\n"
                f"subprocess.Popen([{str(host)!r}, '-c', {HOST_WAIT_SOURCE!r}], "
                "start_new_session=True)\n"
                f"print({READY_MESSAGE!r}, os.getpgrp(), flush=True)\n"
                "signal.pause()\n"
            )
            process = self.start(source)
            self.ready(process)
            with runner.ProcessEvents() as events:
                owned = [
                    record
                    for record in runner.process_snapshot()
                    if record.executable == host and record.pid != existing.pid
                ]
                self.assertTrue(owned, "synthetic reparented host was not found")
                for record in owned:
                    events.add(record.pid)
                status, _, _ = self.finish(process)
                self.assertEqual(status, runner.TIMEOUT_EXIT_STATUS)
                self.assertIs(
                    events.wait(EVENT_TIMEOUT_SECONDS),
                    runner.ProcessOutcome.EXITED,
                    "owned products host survived",
                )
            os.kill(existing.pid, SIGNAL_EXISTENCE_CHECK)
        finally:
            existing.terminate()
            existing.wait()

    def test_ownership_uses_group_and_new_executable_location(self) -> None:
        owned_group = 100
        other_group = 200
        leader_pid = 101
        new_host_pid = 102
        existing_host_pid = 103
        other_host_pid = 104
        products = self.root / "build" / "DerivedData" / "Build" / "Products"
        host = products / "Debug" / "Host.app" / "Contents" / "MacOS" / "Host"
        records = (
            runner.ProcessRecord(leader_pid, owned_group, Path("/usr/bin/xcodebuild")),
            runner.ProcessRecord(new_host_pid, other_group, host),
            runner.ProcessRecord(existing_host_pid, other_group, host),
            runner.ProcessRecord(
                other_host_pid, other_group, self.root / "other-checkout" / "Host"
            ),
        )
        result = runner.owned_records(records, owned_group, products, {existing_host_pid: host})
        self.assertEqual({record.pid for record in result}, {leader_pid, new_host_pid})

    def test_ownership_treats_recycled_baseline_pid_as_new(self) -> None:
        owned_group = 100
        other_group = 200
        recycled_pid = 105
        products = self.root / "build" / "DerivedData" / "Build" / "Products"
        stale = products / "Host"
        fresh = products / "Helper"
        records = (runner.ProcessRecord(recycled_pid, other_group, fresh),)
        result = runner.owned_records(records, owned_group, products, {recycled_pid: stale})
        self.assertEqual({record.pid for record in result}, {recycled_pid})

    def test_external_signal_rechecks_identity_before_kill(self) -> None:
        group = 100
        foreign_group = 200
        recycled_pid = 105
        original = runner.ProcessRecord(recycled_pid, foreign_group, Path("/tmp/original/app"))
        current = runner.ProcessRecord(recycled_pid, foreign_group, Path("/tmp/recycled/other"))
        with (
            patch.object(runner, "process_snapshot", return_value=(current,)),
            patch.object(os, "kill") as kill,
        ):
            self.assertTrue(runner.signal_external_records([original], group, signal.SIGTERM))
        kill.assert_not_called()

    def test_external_signal_kills_matching_record_only(self) -> None:
        group = 100
        foreign_group = 200
        external_pid = 105
        member_pid = 106
        record = runner.ProcessRecord(external_pid, foreign_group, Path("/tmp/original/app"))
        member = runner.ProcessRecord(member_pid, group, Path("/tmp/original/app"))
        with (
            patch.object(runner, "process_snapshot", return_value=(record, member)),
            patch.object(os, "kill") as kill,
        ):
            self.assertTrue(runner.signal_external_records([record, member], group, signal.SIGTERM))
        kill.assert_called_once_with(external_pid, signal.SIGTERM)

    def test_force_kill_skips_group_without_surveyed_members(self) -> None:
        sleeper = subprocess.Popen([sys.executable, "-c", "import signal; signal.pause()"])
        try:
            with (
                patch.object(runner, "process_snapshot", return_value=()),
                patch.object(runner, "signal_group") as signal_group,
            ):
                cleaned = runner.cleanup(sleeper, None, {}, TEST_GRACE_SECONDS)
            self.assertFalse(cleaned)
            for call in signal_group.call_args_list:
                self.assertNotEqual(call.args[1], signal.SIGKILL)
        finally:
            sleeper.terminate()
            sleeper.wait()

    def test_force_kill_signals_surveyed_group(self) -> None:
        sleeper = subprocess.Popen([sys.executable, "-c", "import signal; signal.pause()"])
        try:
            records = (runner.ProcessRecord(sleeper.pid, sleeper.pid, Path(sys.executable)),)
            with (
                patch.object(runner, "process_snapshot", return_value=records),
                patch.object(runner, "signal_group") as signal_group,
            ):
                runner.cleanup(sleeper, None, {}, TEST_GRACE_SECONDS)
            kill_calls = [
                call for call in signal_group.call_args_list if call.args[1] == signal.SIGKILL
            ]
            self.assertTrue(kill_calls, "surveyed group was not force-killed")
        finally:
            sleeper.terminate()
            sleeper.wait()

    def test_command_preserves_test_options(self) -> None:
        options = [
            "-scheme",
            "RefineID",
            "-derivedDataPath",
            "build/DerivedData",
            "-only-testing:ExampleTests",
        ]
        command, directory = runner.command_for_arguments(options, self.root)
        self.assertEqual(command, [runner.XCODEBUILD, runner.TEST_ACTION, *options])
        self.assertEqual(directory, self.root / "build" / "DerivedData")

    def test_rejects_ui_selection_outside_guest(self) -> None:
        with patch.dict(os.environ, {"REFINEID_UI_TEST_GUEST": ""}), self.assertRaises(ValueError):
            runner.command_for_arguments(["-testPlan", "RefineIDUITests"], self.root)
        with patch.dict(os.environ, {"REFINEID_UI_TEST_GUEST": "tart"}):
            command, _ = runner.command_for_arguments(["-testPlan", "RefineIDUITests"], self.root)
            self.assertIn("RefineIDUITests", command)

    def test_rejects_products_symlink_outside_derived_data(self) -> None:
        derived = self.root / "build" / "DerivedData"
        derived.mkdir(parents=True)
        outside = self.root / "outside"
        outside.mkdir()
        (derived / "Build").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            runner.supervise([sys.executable, "-c", "pass"], derived)

    def test_command_rejects_build_actions_and_external_derived_data(self) -> None:
        invalid = (["archive"], ["build"], ["-derivedDataPath", str(self.root.parent)])
        for options in invalid:
            with self.subTest(options=options), self.assertRaises(ValueError):
                runner.command_for_arguments(options, self.root)

    def test_compiler_warnings_fail_even_when_process_exits_zero(self) -> None:
        samples = (
            (
                "Tests/CardCoreTests/Example.swift:32:32: warning: "
                "capture of non-Sendable [#SendableClosureCaptures]"
            ),
            (
                "macro expansion #expect:2:6: warning: "
                "call to main actor-isolated static method [#ActorIsolatedCall]"
            ),
            "<unknown>:0: warning: compiler driver warning",
            "clang: warning: unused argument",
            "ld: warning: ignoring duplicate libraries",
        )
        for sample in samples:
            with self.subTest(warning=sample):
                source = f"import sys; print({sample!r}, file=sys.stderr)"
                status, _, stderr = self.finish(self.start(source))
                self.assertEqual(status, runner.FAILURE_EXIT_STATUS)
                self.assertIn("compiler warning detected", stderr)

    def test_xcode_runtime_dvt_assertion_warning_is_not_treated_as_compiler_warning(self) -> None:
        source = (
            "import sys; print('2026-11-23 xcodebuild: DVTAssertions: "
            "Warning in IDEFrameworks/IDELaunchSession.m:395', file=sys.stderr)"
        )
        status, _, _ = self.finish(self.start(source))
        self.assertEqual(status, runner.SUCCESS_EXIT_STATUS)


if __name__ == "__main__":
    unittest.main()
