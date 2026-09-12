# macOS App Store release runbook

This is the operational procedure for producing, testing, submitting, and
releasing RefineID for macOS through the App Store. It is written for a human
release operator or an automation agent.

The policy and product gates remain in [release-plan.md](release-plan.md) and
[`TASKS.md`](../TASKS.md). If this runbook conflicts with either, stop and
resolve the conflict before releasing.

## What counts as a release

There are three different artifacts. Do not confuse them.

| Artifact | Command | Purpose |
| --- | --- | --- |
| Local macOS build | `Scripts/install-macos.sh --configuration Release` | Install an optimized development-signed build on this Mac. |
| App Store candidate | `Scripts/apple-app-store-connect-release-manager.swift candidate macos --upload` | Archive, inspect, export, and upload the production candidate to App Store Connect. |
| Direct download | No supported command | Developer ID signing, notarization, and stapling are not currently a release path for this product. |

The App Store candidate uses the `TestFlight` configuration, not `Release`.
`TestFlight` excludes diagnostics and is inspected before export. A local
`Release` build is useful for development, but it is not release evidence and
must not be uploaded or described as an App Store production artifact.

App Store distribution does not use `notarytool` or `stapler`. Apple performs
the Store trust and distribution processing.

## Authoritative entry points

- `Scripts/apple-app-store-connect-release-manager.swift` is the sole public
  release CLI. Release shell entry points are not supported.
- Its `candidate` command owns archive, inspection, export, and optional upload.
- Its `inspect-archive` command is the executable archive gate. `candidate`
  always invokes it before export.
- `Scripts/apple-app-store-connect-release-manager.swift` owns App Store
  Connect metadata, tester distribution, build attachment, and review
  submission.
- `Metadata/appstore.json` owns reviewed App Store metadata.
- `Documentation/app-store-review-notes.md` explains the hardware-dependent
  product to App Review.
- `Documentation/export-compliance.md` records the export-compliance position.

Do not replace the release script with raw `xcodebuild`, Xcode Organizer, or a
handwritten sequence. Doing so can skip archive inspection, use the wrong
configuration, retain diagnostics, or publish mismatched app and extension
versions.

## Actions that require release-owner approval

Stop immediately before each of these actions unless the release owner has
explicitly approved that exact action and candidate:

- Uploading a build to App Store Connect.
- Distributing a build to a TestFlight group.
- Creating a `dev`, `beta`, `rc`, or final release tag.
- Attaching a build to an App Store version.
- Submitting a version to App Review.

Approval for one action does not authorize later actions. In particular,
approval to upload does not authorize submission. Approval to submit does
authorize the public release: versions release automatically on App Review
approval (owner decision 2026-08-22, first applied by 26.8.21).

Never display, copy into a report, commit, or transmit an App Store Connect
private key. Check only whether the expected key file exists.

## Preconditions

Before cutting a candidate, confirm all of the following:

- The intended source commit is reviewed and the working tree is clean.
- The release gates applicable to this candidate in `TASKS.md` are complete.
- Required real-card testing is recorded against the exact source candidate.
- No test deliberately risks a card's last PIN or PUK attempt.
- Apple Developer Program membership and App Store agreements are current.
- Xcode has access to team `4ZJC3SFJR2` and can manage provisioning updates.
- The macOS App Store record and bundle identifiers already exist.
- Public metadata and review notes are reviewed in the repository.
- Export-compliance answers and any required documentation are current.
- A release owner has named the intended channel: internal, beta, or release
  candidate.

The release script refuses a dirty tree. Do not work around that check. A
release must identify an exact commit that can be reproduced and reviewed.

## App Store Connect credentials

Uploading and App Store Connect management use an API key created under App
Store Connect > Integrations > Keys.

The machine-local environment file may define:

```sh
ASC_KEY_ID=<key-id>
ASC_ISSUER_ID=<issuer-uuid>
```

Its path is:

```text
~/.appstoreconnect/env
```

The private key must be at:

```text
~/.appstoreconnect/private_keys/AuthKey_<key-id>.p8
```

These files are machine-owned secrets and must never enter the repository.

## 1. Inspect App Store Connect without changing it

Use the release manager to understand the current state before choosing a
version or build:

```sh
Scripts/apple-app-store-connect-release-manager.swift state
Scripts/apple-app-store-connect-release-manager.swift builds macos
Scripts/apple-app-store-connect-release-manager.swift submissions
```

The release version is `YY.M.D` in UTC. The build number is the ten-minute UTC
bucket `hour * 10 + minute / 10`. Capture the version and build printed by the
release script and use that exact pair for every later command. Do not
recompute it after the clock enters another bucket.

App Store Connect will not accept the same build number twice for one version.
If the intended pair already exists, do not upload another artifact with that
pair and do not invent a manual number outside the documented policy.

## 2. Produce an archive without uploading

This is the safe rehearsal and archive gate:

```sh
Scripts/apple-app-store-connect-release-manager.swift candidate macos
```

The command must:

1. Confirm the working tree is clean.
2. Compute the UTC version and build.
3. Record the source commit in its output.
4. Archive with the `TestFlight` configuration.
5. Pass the Swift manager's built-in `inspect-archive` gates.
6. Export to `build/testflight/export-macos`.

The inspected archive is:

```text
build/testflight/RefineID-macos.xcarchive
```

Do not manually stamp `Version.xcconfig` before this workflow. The release
script supplies `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` to the
archive without dirtying the source tree. `Scripts/stamp-version.sh` serves
local installation and separate module-version work; it is not a substitute
for the App Store candidate command.

If inspection fails, stop. Fix the source or release configuration, review the
change, commit it, and start again from a clean tree. Never bypass or weaken an
archive check to make a release continue.

## 3. Upload the macOS candidate

After explicit upload approval, run:

```sh
Scripts/apple-app-store-connect-release-manager.swift candidate macos --upload
```

This repeats archive and inspection before exporting with destination
`upload`. Record these values from its final output:

- Version.
- Build number.
- Source commit.
- Archive inspection result.
- Upload completion result.

An upload is immutable. If the artifact is wrong, fix the source and upload a
new, higher build. Never claim that an existing App Store Connect build was
replaced.

App Store Connect processes uploads asynchronously. Do not use an arbitrary
sleep as evidence that processing completed. Query the actual build state:

```sh
Scripts/apple-app-store-connect-release-manager.swift builds macos
```

Continue only when App Store Connect reports the exact uploaded build as ready
for the intended next action.

## 4. Distribute through TestFlight

After explicit approval for the named tester group:

```sh
Scripts/apple-app-store-connect-release-manager.swift distribute macos <group>
```

Test the exact uploaded build. At minimum, retain evidence for:

- Installation and first launch on a clean Mac.
- Upgrade from the previous public build.
- Removal and driver disappearance.
- Apple Silicon and Intel when both remain supported.
- Reader insertion, removal, contention, sleep, wake, extension restart, app
  restart, and Mac restart.
- Activated-card identity publication and signing.
- Pairing with an iPhone, iPhone-backed identity publication, Safari
  authentication, relay rejection, peer removal, and reconnection.
- Factory-fresh card detection without activation unless that specific test is
  separately approved.
- Retry counters before and after any credential operation.
- The absence of diagnostics, unexpected entitlements, secrets, and personal
  information in retained evidence.

Do not substitute a locally installed `Release` build for TestFlight evidence.

## 5. Prepare the App Store version

Let `VERSION` and `BUILD` be the exact pair printed during upload. After
approval for each mutating step, use:

```sh
Scripts/apple-app-store-connect-release-manager.swift ensure-version macos "$VERSION"
Scripts/apple-app-store-connect-release-manager.swift metadata macos "$VERSION"
Scripts/apple-app-store-connect-release-manager.swift app-info
Scripts/apple-app-store-connect-release-manager.swift review-contact macos "$VERSION"
# Generate/refresh screenshots if needed:
# Scripts/apple-app-store-connect-release-manager.swift capture-screenshots --all
Scripts/apple-app-store-connect-release-manager.swift screenshots macos "$VERSION"
Scripts/apple-app-store-connect-release-manager.swift age-rating
Scripts/apple-app-store-connect-release-manager.swift export-compliance macos
Scripts/apple-app-store-connect-release-manager.swift pricing
Scripts/apple-app-store-connect-release-manager.swift attach-build macos "$VERSION" "$BUILD"
```

Review App Store Connect after these commands. Confirm the exact build,
localizations, screenshots, privacy information, age rating, pricing,
availability, export compliance, and review contact. An API call succeeding is
not evidence that the resulting public presentation is correct.

## 6. Submit for review

Before submission, confirm:

- The attached build is the exact TestFlight-tested candidate.
- All required metadata is complete and reviewed.
- Review notes explain the CryptoTokenKit extension and hardware requirements.
- Screenshots contain only synthetic or approved redacted data.
- The release owner has explicitly approved App Review submission.

Then submit:

```sh
Scripts/apple-app-store-connect-release-manager.swift submit macos "$VERSION"
```

Record the submission identifier and resulting state:

```sh
Scripts/apple-app-store-connect-release-manager.swift submissions
Scripts/apple-app-store-connect-release-manager.swift state
```

If submission fails or creates an empty submission container, do not improvise
with undocumented API calls. The release manager identifies cases that must be
cleaned up in the App Store Connect web interface.

## 7. Approve and release

Versions release automatically on App Review approval (owner decision
2026-08-22): submitting to review is the last human gate. After approval:

1. Confirm the released build matches the recorded source commit, version,
   build, and hardware evidence.
2. Create the final release tag with owner approval. Do not use
   `stamp-version.sh --tag`; its current tag command is for the iOS channel
   naming scheme.
3. Record the release outcome and UTC time in `Documentation/releases/`.
4. Monitor review messages, crash reports, TestFlight/App Store feedback, and
   security reports.

If a submitted build must not ship, remove it from review before approval.
If a defect is found after public release, do not replace the shipped binary:
cut a new reviewed version and follow this runbook again.

## Local Release installation

For an optimized build installed only on the current development Mac:

```sh
Scripts/install-macos.sh --configuration Release
Scripts/install-macos.sh --check
```

The install script stamps the current UTC version/build, verifies the
signature, installs only under `/Applications`, and manages competing local
CryptoTokenKit bundle registrations. Do not replace it with raw `xcodebuild`
and a manual copy.

This local build is normally Apple Development signed. Call it a "local
Release build", not a notarized build, App Store candidate, or production
distribution.

## Direct Developer ID distribution

This repository does not currently define an authoritative Developer ID
archive, packaging, notarization, stapling, and publication workflow. Do not
invent one during an App Store release.

If direct distribution becomes a product requirement, add a reviewed script
that performs Developer ID signing, packaging, `notarytool` submission,
`stapler` attachment and validation, Gatekeeper assessment, checksumming, and
artifact publication. Keep that workflow separate from App Store export.

## Release evidence record

Retain a release record containing at least:

```text
Platform: macOS
Channel: internal | beta | rc | App Store
Source commit:
Version:
Build:
UTC cut time:
Archive path or Xcode Cloud build:
Archive inspection result:
App Store Connect build identifier and processing state:
TestFlight group and validation result:
Hardware evidence reference:
Metadata revision:
Export-compliance evidence reference:
Approver for upload:
Approver for submission:
Review submission identifier:
Approval result:
Approver for public release:
Public release UTC time:
Known limitations or rollback decision:
```

Never put credentials, PINs, PUKs, cardholder data, private certificates, or
App Store Connect private keys in the release record.

## Copyable instruction for an automation agent

Use this wording when delegating a candidate build:

> Follow `Documentation/release-runbook.md` for a macOS App Store candidate.
> Use only the repository's authoritative release scripts. Do not substitute
> raw `xcodebuild`, do not use the local Release install as release evidence,
> and do not activate or mutate a card. Stop for explicit approval immediately
> before upload, TestFlight distribution, tagging, build attachment, App Review
> submission, and public release. Report the source commit, version, build,
> archive inspection result, and App Store Connect state.
