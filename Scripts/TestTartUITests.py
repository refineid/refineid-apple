#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
"""Usage: python3 -B Scripts/TestTartUITests.py. Exercises a synthetic Tart CLI."""

from contextlib import closing, suppress
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
from typing import IO, TypedDict
import unittest

import RunAppleTests as runner

SCRIPTS = Path(__file__).resolve().parent
RUNNER = SCRIPTS / "test-ui-tart.py"
EVENT_TIMEOUT_SECONDS = 10.0
OUTPUT_READ_LIMIT = 65536
FIXTURE_FAILURE_STATUS = 7
EXECUTABLE_MODE_BITS = 0o111
ONE_EVENT = 1
NO_EVENTS = 0
NO_WAIT_SECONDS = 0
SIGNAL_EXISTENCE_CHECK = 0
VM_NAME = "synthetic-vm"
FAKE_TART = r"""
import json, os, signal, sys
SUCCESS_EXIT_STATUS = 0
FAILURE_EXIT_STATUS = 7
ARGUMENT_START = 1
COMMAND_INDEX = 0
arguments = sys.argv[ARGUMENT_START:]
command = arguments[COMMAND_INDEX]
record = json.dumps({'command': command, 'arguments': arguments, 'pid': os.getpid()}) + '\n'
with open(os.environ['FAKE_TART_LOG'], 'a') as log:
    log.write(record)
mode = os.environ.get('FAKE_TART_MODE', 'success')
if command == 'list':
    items = [] if mode == 'missing' else [
        {'Name': 'synthetic-vm', 'State': 'running' if mode == 'running' else 'stopped'}]
    print(json.dumps(items))
elif command == 'run':
    if mode == 'run-failure':
        raise SystemExit(FAILURE_EXIT_STATUS)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(SUCCESS_EXIT_STATUS))
    signal.pause()
elif command == 'ip':
    if mode == 'readiness-failure':
        raise SystemExit(FAILURE_EXIT_STATUS)
    if mode == 'cancel-readiness':
        signal.pause()
    else:
        print('synthetic-guest-address')
elif command == 'exec':
    if mode == 'cancel-exec':
        signal.pause()
    elif mode == 'test-failure':
        raise SystemExit(FAILURE_EXIT_STATUS)
else:
    raise SystemExit(FAILURE_EXIT_STATUS)
"""


class TartCommand(TypedDict):
    command: str
    arguments: list[str]
    pid: int


def available_output(stream: IO[bytes] | None) -> str:
    assert stream is not None
    os.set_blocking(stream.fileno(), False)
    try:
        return os.read(stream.fileno(), OUTPUT_READ_LIMIT).decode()
    except BlockingIOError:
        return ""


class TartLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="fake-tart-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.log = self.root / "commands.jsonl"
        self.log.touch()
        self.fake = self.root / "tart"
        self.fake.write_text(f"#!{sys.executable}\n" + FAKE_TART, encoding="ascii")
        self.fake.chmod(self.fake.stat().st_mode | EXECUTABLE_MODE_BITS)

    def records(self) -> list[TartCommand]:
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def start(self, mode: str = "success", scope: str = "all") -> subprocess.Popen[bytes]:
        environment = os.environ.copy()
        environment["PATH"] = str(self.root) + os.pathsep + environment["PATH"]
        environment["FAKE_TART_LOG"] = str(self.log)
        environment["FAKE_TART_MODE"] = mode
        process = subprocess.Popen(
            [sys.executable, str(RUNNER), VM_NAME, scope],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
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

    def wait_command(self, command: str) -> TartCommand:
        deadline = time.monotonic() + EVENT_TIMEOUT_SECONDS
        with self.log.open() as log, closing(select.kqueue()) as events:
            notification = select.kevent(
                log.fileno(),
                filter=select.KQ_FILTER_VNODE,
                flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                fflags=select.KQ_NOTE_WRITE,
            )
            events.control([notification], NO_EVENTS, NO_WAIT_SECONDS)
            while True:
                for record in self.records():
                    if record["command"] == command:
                        return record
                remaining = max(NO_WAIT_SECONDS, deadline - time.monotonic())
                self.assertTrue(
                    events.control(None, ONE_EVENT, remaining),
                    "synthetic Tart did not reach the requested stage",
                )

    def finish(self, process: subprocess.Popen[bytes]) -> tuple[int, str, str]:
        with runner.ProcessEvents() as events:
            events.add(process.pid)
            self.assertIs(
                events.wait(EVENT_TIMEOUT_SECONDS),
                runner.ProcessOutcome.EXITED,
                "synthetic Tart workflow did not finish",
            )
        status = process.wait()
        return status, available_output(process.stdout), available_output(process.stderr)

    def watch_owned(self) -> runner.ProcessEvents:
        events = runner.ProcessEvents()
        for record in self.records():
            if record["command"] in {"run", "ip", "exec"}:
                events.add(record["pid"])
        self.addCleanup(events.queue.close)
        return events

    def test_supported_headless_flags_and_bounded_agent_readiness(self) -> None:
        status, stdout, stderr = self.finish(self.start())
        self.assertEqual(status, runner.SUCCESS_EXIT_STATUS, stderr)
        records = self.records()
        run = next(record["arguments"] for record in records if record["command"] == "run")
        readiness = next(record["arguments"] for record in records if record["command"] == "ip")
        execute = next(record["arguments"] for record in records if record["command"] == "exec")
        self.assertIn("--no-graphics", run)
        self.assertNotIn("--no-gui", run)
        self.assertIn("--wait", readiness)
        self.assertIn("agent", readiness)
        self.assertIn("REFINEID_UI_TEST_GUEST=tart", execute)
        self.assertIn("all", execute)
        self.assertNotIn("synthetic-guest-address", stdout + stderr)
        self.assertNotIn("stop", {record["command"] for record in records})

    def test_mvp_scope_stays_inside_guest(self) -> None:
        status, _, stderr = self.finish(self.start(scope="macos-mvp"))
        self.assertEqual(status, runner.SUCCESS_EXIT_STATUS, stderr)
        execute = next(
            record["arguments"] for record in self.records() if record["command"] == "exec"
        )
        self.assertIn("macos-mvp", execute)

    def test_missing_or_running_vm_is_not_started_or_stopped(self) -> None:
        for mode in ("missing", "running"):
            with self.subTest(mode=mode):
                self.log.write_text("")
                status, _, stderr = self.finish(self.start(mode))
                self.assertEqual(status, runner.FAILURE_EXIT_STATUS)
                self.assertIn("existing stopped VM", stderr)
                self.assertEqual({record["command"] for record in self.records()}, {"list"})

    def test_failed_guest_agent_stops_owned_vm_without_starting_tests(self) -> None:
        process = self.start("readiness-failure")
        self.wait_command("run")
        owned = self.watch_owned()
        status, _, stderr = self.finish(process)
        self.assertEqual(status, runner.FAILURE_EXIT_STATUS)
        self.assertIn("did not become ready", stderr)
        self.assertNotIn("exec", {record["command"] for record in self.records()})
        self.assertIs(
            owned.wait(EVENT_TIMEOUT_SECONDS),
            runner.ProcessOutcome.EXITED,
            "owned VM survived readiness failure",
        )

    def test_guest_test_failure_preserves_exit_status(self) -> None:
        status, _, _ = self.finish(self.start("test-failure"))
        self.assertEqual(status, FIXTURE_FAILURE_STATUS)

    def test_cancellation_during_readiness_and_execution_cleans_owned_processes(self) -> None:
        cases = ((signal.SIGINT, "cancel-readiness", "ip"), (signal.SIGTERM, "cancel-exec", "exec"))
        for signum, mode, stage in cases:
            with self.subTest(stage=stage):
                self.log.write_text("")
                process = self.start(mode)
                self.wait_command(stage)
                owned = self.watch_owned()
                os.kill(process.pid, signum)
                status, _, stderr = self.finish(process)
                self.assertEqual(status, runner.SIGNAL_EXIT_STATUS_BASE + signum)
                self.assertIn("interruption requested", stderr)
                self.assertIs(
                    owned.wait(EVENT_TIMEOUT_SECONDS),
                    runner.ProcessOutcome.EXITED,
                    "owned Tart process survived cancellation",
                )

    def test_unrelated_process_survives_cleanup(self) -> None:
        unrelated = subprocess.Popen([sys.executable, "-c", "import signal; signal.pause()"])
        try:
            status, _, _ = self.finish(self.start("readiness-failure"))
            self.assertEqual(status, runner.FAILURE_EXIT_STATUS)
            os.kill(unrelated.pid, SIGNAL_EXISTENCE_CHECK)
        finally:
            unrelated.terminate()
            unrelated.wait()


if __name__ == "__main__":
    unittest.main()
