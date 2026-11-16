# Feature gates

How a feature is turned on or off, and what each feature needs from
the platform. A gated-off feature leaves no trace a reviewer could
ask about: no UI, no entitlement, no usage prompt, no declaration,
no embedded extension, no linkage.

## The three layers

A feature is the flag, the packaging, and the inspection together.
Changing one without the others is a broken gate.

1. Compile flag. `Config/Features.xcconfig` feeds
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. A flag absent there
   defines its feature away: everything the feature exclusively
   uses — UI, logic, storage, and driver code alike — compiles
   out, so none of it ships; shared transports stay. The code
   stays in the tree behind the switch, and re-enabling is the
   flag back, never resuscitated dead code. Targets outside Xcode
   (SwiftPM packages) cannot see these flags and gate the same
   split by platform instead. `CardCore` keeps the Bluetooth-driven
   remote-card types off macOS for that reason, and the consequence is
   recorded: a macOS build with `REFINEID_REMOTE_CARD` on does not
   compile, so the Mac requester is verified through the package's
   decisions rather than a Mac binary. `RappRequester` carries the phone's
   decisions on every platform, because leaving them out of macOS is what
   would make a flag-on macOS build fail there too.
2. Packaging. `RefineID.xcodeproj/project.pbxproj` assigns
   per-SDK entitlements and Info.plist files and embeds the
   extensions, with platform filters where an extension ships on
   one platform only.
3. Inspection. `inspect-archive` in
   `Scripts/apple-app-store-connect-release-manager.swift` holds
   every shipping candidate to the reviewed shape: exact
   extension set, per-bundle entitlement allowlists with required
   keys, cross-bundle separation rules, plist declarations, and
   linkage checks. It fails the candidate, it never warns.

A developer's own flags live in `Config/LocalFeatures.xcconfig`,
which git ignores: an assignment there replaces the default on
that machine only. There is no other override mechanism.

## Current flags

| Flag | State | What it gates |
|---|---|---|
| `REFINEID_LOCAL_CARD` | On everywhere | Local card authentication, management, document signing |
| `REFINEID_REMOTE_CARD` | On except macOS, in every macOS configuration | Pairing over RAPP and everything a pairing enables |
| `FEATURE_CARD_ACTIVATION` | On everywhere | The activation form for factory-fresh cards |
| `FEATURE_CONTACTLESS` | On | The CAN entry for contactless cards on macOS (iPhone NFC is not gated) |
| `FEATURE_TIMESTAMP_CONFIG` | Off on macOS in every configuration; iOS Settings app keeps the address | The Time Stamp Settings pane on macOS |
| `FEATURE_PDF_STAMP` | Off on macOS in every configuration; on for iPhone and iPad | The visible stamp; off means invisible signatures |
| `FEATURE_SCS` | Off, set by no configuration | The loopback HTTPS signing service and its Settings pane |
| `FEATURE_ORGANIZATION_CARD` | Off, set by no configuration | Organization cards end to end |

The macOS MVP compiles out every Settings pane, so the app has no
Settings window and no Settings item in its application menu. Its
signatures ask `http://timestamp.sectigo.com/qualified` and carry no
visible stamp.

## What each feature needs

Capabilities nothing else uses must go when their feature goes.
Shared transports stay: outbound network access (timestamps,
revocation checks), the app-group container (app to token driver),
and the keychain groups serve every configuration.

| Feature | Entitlements | Plist keys | Embeds |
|---|---|---|---|
| Remote card | `device.bluetooth` (Mac app, only when on), time-sensitive notifications (iOS app) | `NSBonjourServices` (`_refineid-stream._tcp`), `NSLocalNetworkUsageDescription`, `NSBluetoothAlwaysUsageDescription` | RAPP extension, iOS only |
| Local card | `smartcard` (Mac app and token extension), NFC `readersession.formats` (iOS app) | `NFCReaderUsageDescription` (iOS) | Token extension, both platforms; discovery extension, iOS only and ungated |
| SCS | `network.server` when enabled, granted nowhere in shipping configurations | None | None |
| Contactless macOS | None beyond shared infrastructure | None | None |
| Stamp, timestamp pane, activation, organization | None | None | None |

`network.client` stays with every configuration for timestamps and
revocation checks; RAPP additionally requires it on the Mac app and
the RAPP extension, and requires the RAPP extension carry no
smartcard access. The discovery extension advertises the card
application identifier for polling; it mints nothing and carries
only keychain access on iOS.

Only RAPP uses Bluetooth, so Bluetooth follows the remote-card
gate including linkage: a build without it must not link
CoreBluetooth anywhere (ITMS-90683). The Mac is always the
requester — it dials the paired phone and accepts nothing — so no
macOS bundle carries the server side while nothing listens.

## Platform packaging

The app target uses the iOS files as the base in every
configuration, with `sdk=macosx*` overrides:

| Bundle | iOS | macOS |
|---|---|---|
| App entitlements | `Config/RefineID-iOS.entitlements` (NFC TAG, time-sensitive notifications, keychain) | `Config/RefineID-Store.entitlements` (sandbox, user-selected files, network client, smartcard, app group, keychain; no Bluetooth, no server) |
| App plist | `Config/RefineID-iOS-Info.plist` (NFC, Bluetooth, Bonjour, local-network declarations) | `Config/RefineID-Store-Info.plist` (none of the RAPP keys) |
| Token extension entitlements | `Config/TokenExtension-iOS.entitlements` (keychain) | `Config/TokenExtension.entitlements` (sandbox, smartcard, app group, keychain; no network) |
| RAPP extension entitlements | `Config/RappTokenExtension-iOS.entitlements` (keychain) | `Config/RappTokenExtension.entitlements` (sandbox, network client, app group, keychain; no smartcard) — unused while the embed is iOS-only |
| Discovery extension entitlements | `Config/DiscoveryExtension-iOS.entitlements` (keychain) | `Config/DiscoveryExtension.entitlements` — unused while the embed is iOS-only |
| Embeds | Token, RAPP, discovery | Token only |

Only the files above take part in the build. Other files under
`Config/` that no configuration references are not read; do not
edit them expecting a behavior change.

## Gating a feature off

1. Empty the flag for the target SDK and configurations in
   `Config/Features.xcconfig`. Keep the code beneath built and
   tested.
2. Drop what only the feature needed: the embed (platform filter
   or removal), the per-SDK entitlements, the plist declarations
   and usage strings. Shared transports stay.
3. Extend `inspect-archive`: the expected layout and plugin
   count, the entitlement allowlists, and the
   declaration-or-linkage rules for the gated capability.
4. Verify: build every configuration on both SDKs, archive, run
   `inspect-archive` on the archive, and run the PR gate.

## Verification

- `Scripts/test.sh pr` — lint, package tests, iOS build,
  RefineIDTests on macOS and the iOS simulator, CardCoreTests,
  simulator Bluetooth tests, DSS gate.
- `Scripts/apple-app-store-connect-release-manager.swift
  inspect-archive <path-to-xcarchive>` — every reviewed archive
  gate without uploading or changing App Store state.
