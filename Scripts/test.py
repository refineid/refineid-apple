#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Tiered test and quality gate runner for RefineID.
#
# Usage:
#   Scripts/test.py           # default: runs PR tier (lint, package tests, iOS build, app and core unit tests)
#   Scripts/test.py commit    # fast pre-commit tier (whitespace check + lint)
#   Scripts/test.py pr        # PR / pre-push tier (lint, package tests, iOS build, RefineIDTests on macOS and iOS, CardCoreTests, DSS gate)
#   Scripts/test.py nfc-signing # retained-field lifecycle and PACE regression tests
#   Scripts/test.py macos-mvp # localized local-card UI checks

from __future__ import annotations

import atexit
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys


def step(title: str) -> None:
    print(f"\n=== {title} ===")


def fail(message: str) -> None:
    print(f"\nTEST GATE FAILED: {message}", file=sys.stderr)
    sys.exit(1)


def find_first_iphone_simulator() -> str:
    try:
        res = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode != 0:
            fail(f"simctl failed with exit code {res.returncode}")
        data = json.loads(res.stdout)
        for runtime in data.get("devices", {}).values():
            for device in runtime:
                name = device.get("name", "")
                if "iPhone" in name:
                    return str(name)
    except Exception as e:
        fail(f"failed to query simulator devices: {e}")

    fail(
        "No iPhone simulator is available to run RefineIDTests. "
        "Install one in Xcode's Settings > Platforms, or run this tier on a Mac that has one."
    )
    return ""


derived_data = Path("build/DerivedData")
lsregister = Path(
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
)


def unregister_gate_builds() -> None:
    products = derived_data / "Build" / "Products"
    if not products.is_dir() or not lsregister.is_file():
        return
    for root, dirs, _ in os.walk(products):
        rel_depth = len(Path(root).relative_to(products).parts)
        if rel_depth >= 2:
            dirs.clear()
            continue
        for d in dirs:
            if d.endswith(".app"):
                app_path = Path(root) / d
                subprocess.run(
                    [str(lsregister), "-u", str(app_path)],
                    capture_output=True,
                    check=False,
                )


atexit.register(unregister_gate_builds)


def run_command(cmd: list[str], err_msg: str, env: dict[str, str] | None = None) -> None:
    res = subprocess.run(cmd, env=env, check=False)
    if res.returncode != 0:
        fail(err_msg)


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    os.chdir(repo_root)

    mode = sys.argv[1] if len(sys.argv) > 1 else "pr"

    if mode == "commit":
        run_command(
            [sys.executable, "-B", "Scripts/TestDocumentationGate.py"],
            "Documentation gate tests failed.",
        )

        diff_res = subprocess.run(
            [
                "git",
                "diff",
                "--cached",
                "--quiet",
                "--",
                "Scripts/QualityReceipt.py",
                "Scripts/TestQualityReceipt.py",
            ],
            check=False,
        )
        if diff_res.returncode != 0:
            step("Checking quality receipt gate behavior")
            run_command(
                [sys.executable, "-B", "Scripts/TestQualityReceipt.py"],
                "Quality receipt gate tests failed.",
            )

        step("Checking for whitespace errors in staged changes")
        run_command(
            ["git", "diff", "--cached", "--check"],
            "Staged changes contain trailing whitespace or whitespace errors.",
        )

        step("Running lint and layout gate (Scripts/lint.py)")
        run_command(
            [sys.executable, "Scripts/QualityReceipt.py", "lint-index"],
            "Lint gate failed.",
        )
        print("Commit gate passed.")

    elif mode == "pr":
        run_command(
            [sys.executable, "-B", "Scripts/TestDocumentationGate.py"],
            "Documentation gate tests failed.",
        )

        run_command(
            [sys.executable, "Scripts/QualityReceipt.py", "verify-clean-head"],
            "Push checks require a clean checkout.",
        )

        head_res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
        if head_res.returncode != 0:
            fail("failed to resolve HEAD")
        checked_head = head_res.stdout.strip()

        tree_res = subprocess.run(
            ["git", "rev-parse", "HEAD^{tree}"],
            capture_output=True,
            text=True,
            check=False,
        )
        if tree_res.returncode != 0:
            fail("failed to resolve HEAD tree")
        checked_tree = tree_res.stdout.strip()

        step("1. Testing exact-tree lint receipts")
        run_command(
            [sys.executable, "-B", "Scripts/TestQualityReceipt.py"],
            "Quality receipt gate tests failed.",
        )

        step("2. Running lint and layout gate for HEAD")
        run_command(
            [sys.executable, "Scripts/QualityReceipt.py", "lint-head"],
            "Lint gate failed.",
        )

        step("3. Running CardCore package tests")
        run_command(
            ["swift", "test", "--package-path", "CardCore"],
            "CardCore package tests failed.",
        )

        step("4. Running PKCS11Bridge package tests")
        run_command(
            ["swift", "test", "--package-path", "PKCS11Bridge"],
            "PKCS11Bridge package tests failed.",
        )

        step("5. Verifying iOS compilation")
        run_command(
            [
                "xcodebuild",
                "-derivedDataPath",
                str(derived_data),
                "-scheme",
                "RefineID",
                "-destination",
                "generic/platform=iOS",
                "-quiet",
                "build",
                "CODE_SIGNING_ALLOWED=NO",
            ],
            "iOS build failed. Check for platform-conditional compilation issues.",
        )

        step("6. Running unit test suite (RefineIDTests on macOS)")
        run_command(
            [
                "xcodebuild",
                "test",
                "-derivedDataPath",
                str(derived_data),
                "-scheme",
                "RefineID",
                "-destination",
                "platform=macOS",
                "-only-testing:RefineIDTests",
                "-quiet",
            ],
            "Unit tests failed.",
        )

        step("7. Running unit test suite (RefineIDTests on the iOS simulator)")
        sim_name = find_first_iphone_simulator()
        run_command(
            [
                "xcodebuild",
                "test",
                "-derivedDataPath",
                str(derived_data),
                "-scheme",
                "RefineID",
                "-destination",
                f"platform=iOS Simulator,name={sim_name}",
                "-only-testing:RefineIDTests",
                "-quiet",
            ],
            "Unit tests failed on the iOS simulator.",
        )

        step("8. Running core test suite (CardCoreTests on macOS, without RAPP integration)")
        run_command(
            [
                "xcodebuild",
                "test",
                "-derivedDataPath",
                str(derived_data),
                "-scheme",
                "RefineID",
                "-destination",
                "platform=macOS",
                "-only-testing:CardCoreTests",
                "-skip-testing:CardCoreTests/RappIntegrationTests",
                "-quiet",
            ],
            "CardCore tests failed.",
        )

        step("9. Running RAPP integration tests (CardCoreTests/RappIntegrationTests on macOS)")
        run_command(
            [
                "xcodebuild",
                "test",
                "-derivedDataPath",
                str(derived_data),
                "-scheme",
                "RefineID",
                "-destination",
                "platform=macOS",
                "-only-testing:CardCoreTests/RappIntegrationTests",
                "-quiet",
            ],
            "RAPP integration tests failed.",
        )

        step("10. Running simulator-only engine tests on iOS (Bluetooth-gated, offer handoff)")
        run_command(
            [
                "xcodebuild",
                "test",
                "-derivedDataPath",
                str(derived_data),
                "-scheme",
                "RefineID",
                "-destination",
                f"platform=iOS Simulator,name={sim_name}",
                "-only-testing:CardCoreTests/RappBleAppearanceWatcherTests",
                "-only-testing:CardCoreTests/CardCanOfferTests",
                "-quiet",
            ],
            "Simulator-only engine tests failed.",
        )

        step("11. Judging the Swift signers' documents with EU DSS (Scripts/dss-gate.py)")
        run_command(
            [sys.executable, "Scripts/dss-gate.py"],
            "A Swift signer's document is below the release level in DSS.",
        )

        step("12. Running the direct-download DMG builder and release manager command-line tests")
        run_command(
            ["swift", "Scripts/TestMacosNotarizedDmgBuilder.swift"],
            "The direct-download DMG builder command-line tests failed.",
        )
        run_command(
            ["swift", "Scripts/TestAppleAppStoreConnectReleaseManager.swift"],
            "The App Store Connect release manager command-line tests failed.",
        )

        run_command(
            [
                sys.executable,
                "Scripts/QualityReceipt.py",
                "verify-head",
                checked_head,
                checked_tree,
            ],
            "The checked-out commit changed during push checks.",
        )

        print(
            "\nPR gate passed: gate tests, lint, DMG builder tests, CardCore and PKCS11Bridge "
            "package tests, iOS build, RefineIDTests on macOS and iOS, CardCoreTests, "
            "RappIntegrationTests, simulator Bluetooth and offer-handoff tests, and the DSS gate."
        )

    elif mode == "nfc-signing":
        step("Testing retained NFC field lifecycle and PACE")
        run_command(
            [
                "xcodebuild",
                "test",
                "-derivedDataPath",
                str(derived_data),
                "-scheme",
                "RefineID",
                "-destination",
                "platform=macOS",
                "-only-testing:CardCoreTests/HeldCardSessionTests",
                "-only-testing:CardCoreTests/PaceEstablishmentTests",
                "-only-testing:CardCoreTests/CommandApduTests",
                "-only-testing:CardCoreTests/CardExchangeTraceTests",
                "-only-testing:CardCoreTests/CardExchangeProgressTests",
                "-only-testing:CardCoreTests/OnDemandPinExperimentTests",
                "-only-testing:CardCoreTests/OnDemandPinPublicationTests",
                "-only-testing:CardCoreTests/SecureMessagingChannelTests",
                "-only-testing:RefineIDTests/SmartCardTransmitTests",
                "-quiet",
            ],
            "NFC signing regression tests failed.",
        )

    elif mode == "macos-mvp":
        step("Checking the macOS MVP user interface")
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        result_path = f"build/macos-mvp-ui-{timestamp}.xcresult"
        run_command(
            [
                "xcodebuild",
                "test",
                "-derivedDataPath",
                str(derived_data),
                "-scheme",
                "RefineID",
                "-testPlan",
                "RefineIDUITests",
                "-destination",
                "platform=macOS",
                "-only-testing:RefineIDUITests/MacMvpUITests",
                "-resultBundlePath",
                result_path,
                "-quiet",
            ],
            "macOS MVP UI checks failed.",
        )

    else:
        print(f"Usage: {sys.argv[0]} [commit|pr|nfc-signing|macos-mvp]", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
