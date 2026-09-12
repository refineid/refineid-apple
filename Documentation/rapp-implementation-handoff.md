# RAPP Apple implementation handoff

Status date: 2026-08-17

This document is the implementation handoff for Remote Authorization Proxy
Protocol (RAPP) support in RefineID on Apple platforms. It describes what is
present in this repository, where the protocol authority lives, what has been
measured, and what the next agent must do. It is not a security approval or a
claim that RAPP is production-ready.

## Protocol authority

The vendored documents are the authority, and the Swift engine in
`CardCore/Sources/RappEngine` implements them. There is no compiled protocol
artifact in this repository.

- Specification: `Documentation/protocol/rapp-v26.9.7.70.md`
- Formal state model: `Documentation/protocol/rapp-state-machine-v26.9.7.70.yaml`
- Conformance corpus: `Documentation/rapp-conformance/rapp-v26.9.7.70.json`
  (`SHA-256 25b9379ac2baa1a0ea83c4746247426a061b76f180b03c30fd2d5295112fb36b`)
- Vectors generated from the reference engine, covering what the corpus does
  not reach: `rapp-transport-v26.9.7.70.json` (post-handshake framing),
  `rapp-flow-v26.9.7.70.json` (ceremony bodies), and
  `rapp-operation-v26.9.7.70.json` (operation bodies)

The engine is held to those documents by its tests rather than by anyone
remembering to follow them. The state tables are transcribed from the model
and checked against it in both directions at test time: every rule in the
model is implemented, and no implemented rule is absent from the model. Every
encoding is compared byte for byte against the vectors, which is what catches
an ordinary refactor that silently rewrites a wire key.

Change the specification and the model first, regenerate the corpus and the
vectors, re-vendor all of them together, and then make the engine follow. A
change to the documents that the engine does not follow fails the build, so
the two cannot drift apart quietly.

Important invariants already represented in the implementation are:

- The phone is the authorizer and retains CAN, PIN 1, and PIN 2.
- The requester receives operation results, not card credentials.
- Every operation requires an explicit authorizer decision.
- One authenticated protocol violation revokes the pairing immediately. There
  is no two-strike policy.
- Invalid card credentials, authenticated protocol anomalies, and ambiguous
  card completion are fail-stop events.
- Card activation and PIN management are not remotely exposed in RAPP 0.1.

The presently supported remote operation families are card status, browser
authentication, and qualified document signing.

## The Swift engine

`CardCore/Sources/RappEngine` is the protocol engine. It depends on Foundation
and CryptoKit only, and is organised as:

- `Noise/` the Noise framework, with the two patterns this protocol uses
- `Wire/` deterministic CBOR, the envelope, and the message registry
- `Rapp/` the prologues, the derivations, and the transport channel
- `State/` the formal model transcribed as tables
- `Storage/` the offer, the pair record, and the operation journal
- `Flow/` the pairing and session ceremonies
- `Runtime/` liveness, the failure policy, and framing
- `Operation/` typed operations and their authorization
- `Engine/` the proxy and requester operation engines
- `API/` the interface `CardCore` calls

There is nothing to regenerate and no toolchain beyond Xcode. What was a
166 MB committed binary and a Rust build step is now Swift that the same
tests, linters, and reviewers see as any other source in this repository.

## CardCore RAPP layer

The handwritten Swift integration is under `CardCore/Sources/CardCore/`:

- `RappPlatformPrimitives.swift` provides Apple cryptographic and persistence
  primitives required by the generated core.
- `RappDeviceVault.swift` and `RappDeviceVault+Bindings.swift` store device and
  pairing material using the Apple security boundary.
- `RappPairCatalog.swift` tracks paired peers and the selected pair.
- `RappPairingCoordinator.swift` drives the pairing ceremony.
- `RappClosureFrameTransport.swift` adapts framed RAPP traffic to an Apple
  transport without moving protocol logic out of `RappEngine`.
- `RappConnectionCoordinator.swift` owns connection-level lifecycle.
- `RappSessionDriver.swift` drives one authenticated RAPP session.
- `RappOperationDriver.swift` drives operation request/authorization/result
  lifecycle.
- `RappCardOperationMapping.swift` maps Apple card operations to RAPP operation
  kinds and results.
- `RappPersistentRequesterClient.swift` provides the requester-facing client
  used by persistent token operations.

`PersistentCardRelay.swift` is connected to this layer. Keep transport and
card-operation effects outside the `RappEngine` state machine, but let `RappEngine`
decide which transition and output are legal.

## Stream transport

`fi.refineid.stream.v1` (protocol document section 16.1) lets a non-Apple
requester participate without MultipeerConnectivity. The underlay is plain
TCP. Every frame is a 2-byte big-endian length prefix plus payload; a zero
length is malformed and the prefix bounds every allocation. The requester
lists and the proxy dials, for pairing and for sessions. Immediately
after connecting, before any Noise byte, the proxy sends one plaintext
preamble frame whose bytes come from `RappEngine`
(`rappStreamPairingPreamble` / `rappStreamSessionPreamble`); the transport
layer never constructs those bytes.

- `CardCore/Sources/CardCore/StreamRelaySession.swift` is the TCP dialer:
  ordered endpoint attempts, preamble-first send, bounded frames, a
  generation-guarded event surface, and clean cancel.
  `StreamRelayFraming.swift`, `StreamRelayEndpoint.swift`,
  `StreamRelayEvent.swift`, and `StreamRelayTransportError.swift` complete
  the profile's Swift surface.
- When the selected pair's transport profile is the stream profile,
  `PhonePersistentTokenRelay` dials the pair's stored `streamEndpoints`
  with the session preamble built from the pair's `rendezvousToken`
  instead of advertising MultipeerConnectivity. The relisten policy acts
  as the redial policy with the same explicit-user-action fail-stops;
  automatic redials pause between attempts. MultipeerConnectivity pairs
  keep today's behavior.
- Pairing over the stream profile is wired through the scan flow. The
  bridge's `offerCandidates()` lists the scanned offer's
  transport candidates with stream endpoints decoded in `RappEngine`;
  `RappScannedOffer.candidates` wraps it in CardCore. The phone selects the
  Apple-peer candidate when the offer carries one, else the first stream
  candidate with endpoints; for stream it dials those endpoints with
  `rappStreamPairingPreamble()` over `StreamRelaySession` and runs the
  unchanged pairing coordinator across that connection. An offer with
  neither usable candidate fails visibly.

Stored pair records are format v2: they carry the pair's rendezvous token
and, for stream pairs, the listener endpoint list. Format v1 records fail
to load; the pair catalog and the phone relay treat an unloadable record
as no usable pair, so existing holders pair again. That is intended.

## Application wiring

The application layer is under `Sources/App/`:

- `RappPairingUI.swift` presents 6-digit code pairing and visible paired status.
- `RappAuthorizationInbox.swift` serializes holder-visible authorization
  decisions on the phone.
- `RappNfcCardExecutor.swift` and attached physical smart card reader execution
  perform authorized card work through the phone's card code paths, prioritizing
  an attached physical CCID reader over wireless NFC presence.
- `RappPhoneProxyDispatcher.swift` dispatches authenticated remote requests to
  the phone authorizer.
- `PhonePersistentTokenRelay.swift` carries the phone side of persistent token
  requests and now enters RAPP rather than a credential-bearing shortcut.
- `MacPersistentTokenRegistry.swift` connects macOS requester registration to
  the selected RAPP pair.
- `Sources/RappTokenExtension/PersistentTokenDriver.swift` connects macOS
  CryptoTokenKit requester work to the RAPP client.
- `RefineIDApp.swift`, `ReaderIdentityRootView.swift`, and `StatusView.swift`
  expose pairing and RAPP state in the existing application UI.

Remote document signing is wired through `DocumentSigner.swift`,
`AsicSigner.swift`, and `DocumentSigningView.swift`. The requester does not ask
for or retain PIN 2. The phone authorizer collects PIN 2, performs the card
operation, and returns the operation result. The Mac verifies the returned PDF
or ASiC-E result locally before presenting it as successful.

Pairing selection is persisted device-only. Pairing teardown is durable and is
not automatically repaired after a fail-stop event. A holder must pair again.

### CryptoTokenKit shipping topology

The macOS application embeds two deliberately separate CryptoTokenKit
extensions:

- `RefineIDTokenExtension.appex` remains the direct smart-card reader driver.
  It uses the existing smart-card token identity and has no RAPP network
  entitlement.
- `RefineIDRappTokenExtension.appex` is the persistent-token requester on
  macOS and iOS. Its CryptoTokenKit class identifier is
  `fi.refineid.ReFineID.rapp-token`, and its driver class is
  `PersistentTokenDriver`. It is the only token extension that owns the RAPP
  requester transport.

The iOS application embeds the reader token extension, the discovery
extension, and the RAPP persistent-token extension (2026-08-17; the
extension was macOS-only before the iOS requester role existed). The
containing applications declare the local-network usage text and
`_refineid-rly._tcp` Bonjour service; the RAPP extension's Info.plist
carries the same declarations for its own iOS process. macOS publishes
the delegated identity at launch through `PersistentTokenRegistry`; iOS
publishes it from the explicit remote connect, which already holds the
holder-approved certificate. The reader/RAPP separation is unchanged:
neither extension may claim the other's token class or capability.

## Verified evidence

The following was measured before this handoff:

- `cargo test -p refineid-lib-core` passes in the Rust repository, including
  RAPP formal-state, interoperability, and operation-lifecycle tests.
- The formal transition tests prove state, event, and role legality and exact
  ordered emitted-action equality against every role-qualified YAML rule.
- `swift build --package-path CardCore` passes.
- The RefineID Xcode scheme builds for macOS and generic iOS arm64.
- The current macOS Debug application graph builds with both
  `RefineIDTokenExtension.appex` and `RefineIDRappTokenExtension.appex`
  embedded. The current arm64 iOS device application graph builds with the
  reader and discovery extensions and without the macOS-only RAPP extension.
- `RappShippingConfigurationTests` passes and checks the distinct
  CryptoTokenKit class identifiers and drivers, macOS-only product filtering,
  local-network declarations, and network-entitlement separation.
- 510 Apple unit tests in 82 suites pass on macOS. The focused RAPP adapter
  suite drives requester and proxy pairing through the generated Rust bridge,
  persists both pair records, verifies transport closure, selects the requester
  pair, and proves that one revocation durably removes it from active and
  selected state. It also drives browser authentication through explicit
  prerequisite inspection and approval, proves exactly one card command,
  verifies durable result erasure after the authenticated acknowledgment, and
  proves that a credential rejection durably revokes both peers without another
  card execution. It also proves document signing executes exactly once and
  erases its retained result only after the authenticated acknowledgment. Its
  terminal-path matrix covers user denial, retry-policy refusal, card removal
  before transmit, and ambiguous card completion with exact prerequisite,
  approval, card-command, and transport-close counts. It exhaustively
  round-trips supported card profiles and signature algorithms through the
  Apple mapping layer.
- The RAPP vault's macOS listing path is measured against the file keychain:
  macOS rejects a bulk `match all` query that requests both attributes and
  secret data with `errSecParam`. The vault therefore enumerates account
  attributes and loads each record through the supported single-item query.
  The same 510-test run covers this persistence and enumeration path.
- All 40 `VirtualIDCardUITests` GUI cases passed on an iPhone 17 Pro iOS 26.5
  Simulator in bounded batches. They cover card-state routing, factory and
  partial activation UI, all PIN operations, retry recovery, signing success,
  signing rejection, retry-floor refusal, ambiguous/lost responses, card
  removal, injected faults, localization, and accessibility.
- The Finnish and Swedish localization smoke tests establish a registered
  Virtual ID Card through the reviewer-visible GUI and pass. The Finnish text
  clipping audit also passes after making the shared Sign action grow with its
  localized, Dynamic Type-sized label.
- Real-card setup, priming, and Safari UI-test classes now require
  `TEST_RUNNER_REFINEID_REAL_CARD_TESTS=1`. Default simulator and Xcode Cloud
  runs skip them instead of waiting for hardware or consuming a retry.
- A current Debug application was installed and launched on the cabled
  development iPhone.
- A manual alpha path from macOS Safari through the iPhone and its NFC identity
  card succeeded earlier. Treat that as useful integration evidence, not a
  repeatable release qualification for the current commits.
- 2026-08-17: a manual iPad-requester path succeeded end to end on the
  ported persistent-token extension. An iPad Pro 13-inch (M5) iOS 26.5
  Simulator paired with the physical development iPhone over the 6-digit code
  pairing ceremony, read the holder identity onto the Person row with one
  authorization, published the delegated CryptoTokenKit identity, and
  completed a Safari suomi.fi client-certificate login whose signature
  the phone executed against the physical card. Simulator ctkd loaded
  the extension, simulator Safari offered the persistent token, and the
  extension ran its MultipeerConnectivity requester transport from the
  extension process. Treat as integration evidence, not release
  qualification; the recorded physical matrix remains open.

The Virtual ID Card uses the real UI and operation orchestration while
substituting card effects. It is not proof of Core NFC, physical card, local
network permission, CryptoTokenKit, or Safari system-sheet behavior.

## Known gaps and blockers

- The latest physical-device XCUITest preflight reached the cabled iPhone but
  stopped because the phone was locked. The device must be unlocked in person;
  if macOS subsequently asks for Enable UI Automation authorization, Petri must
  also clear that Touch ID dialog. Neither condition is an application failure.
- The latest committed RAPP consolidation has not had a fresh, recorded,
  end-to-end pair/status/browser-auth/signing run on two physical devices.
- `test-without-building` is unreliable with the current CoreSimulator because
  its temporary UI-test bundle is removed between invocations. Normal
  incremental `xcodebuild ... test` works.
- Irreversible credential and signing journeys should run as individual CI
  shards. Two signing fault journeys took 123.7 seconds together; each stays
  under the 120-second window when run separately.
- No independent cryptographic or protocol security review has approved RAPP
  for production.
- Cross-platform interoperability has been qualified and verified working across
  all supported combinations: Android - Mac, Android - Linux, Mac - iPhone,
  Mac - Android, Linux - Android, and Windows.
- The Simulator restriction that a compiled arm64-only artifact imposed is
  gone: the engine is Swift and builds for whatever slice the toolchain asks
  for.

## Exact next step

1. Petri unlocks the cabled iPhone and clears an Enable UI Automation Touch ID
   dialog if macOS presents one.
2. Build and install the committed Debug app on the cabled iPhone. Physical
   iOS UI-test shards use the dedicated `RefineID-iOS-UI` scheme so they do not
   build unrelated macOS unit-test products:

   ```sh
   xcodebuild test -project RefineID.xcodeproj \
     -scheme RefineID-iOS-UI \
     -destination 'platform=iOS,id=<device-identifier>' \
     -only-testing:RefineIDUITests/<test-class>/<test-method>
   ```

   The project declares macOS `arm64` in every configuration. The engine no
   longer constrains this; the declaration is now the project's own choice.
3. Pair macOS and iPhone from a clean pairing state using the 6-digit code pairing UI.
4. With a known activated card and correct CAN/PIN values, record one card
   status read, one Safari browser-authentication operation, and one harmless
   document signature. Verify that macOS never asks for PIN 1 or PIN 2 and that
   the phone asks for explicit authorization.
5. Repeat one operation after intentionally removing the card, not after
   intentionally entering a wrong credential. Confirm fail-stop teardown and
   manual re-pairing. Do not spend a real credential retry without Petri's
   explicit approval.
6. Archive the result bundle and update this document with exact build, device,
   OS, and commit identifiers before making a TestFlight or production-readiness
   claim.

## Commit boundary

The initial Apple RAPP implementation was committed on `main` as:

- `cf02443` - Add RAPP Swift protocol runtime
- `f05c4d8` - Integrate RAPP authorizer and requester flows
- `d987e71` - Make hardware UI tests explicit opt-in

All three were pushed to `origin/main` before this handoff was written.

### 2026-08-17 monotonic offer-expiry ABI refresh

- Checked-in `RefineIDRappFFI.xcframework` and generated Swift bindings were rebuilt from Rust revision `c745bb0cbab18b82877ddfa1143690c9fb4ce0ab` using the Swift release manager's `rapp-bindings` command.
- The shared Rust bridge now enforces the one-use offer's monotonic deadline before transport selection, throughout Noise XXpsk3, and before authenticated confirmation. Apple keeps its visible expiry task active over the same phases and maps core expiry to `offerExpired`.
- The shared Rust bridge retains the requester's original live offer and deadline after unauthenticated handshake garbage, while proxy candidates and authenticated or cancelled attempts remain terminal. Apple rebuilds the candidate transport around that retained offer and ignores stale transport callbacks.
- Apple commit `746f45a` contains the regenerated artifact, requester recovery coordinator/UI integration, and dedicated recovery tests. Commit `7fc1ff5` updates the integration harness for the restored-offer event.
- `cargo test -p refineid-lib-core rapp` passes 15 focused Rust tests. Independent macOS runs of `RappPairingRecoveryTests`, `RappOfferExpiryTests`, and `RappIntegrationTests` all pass. A combined Apple invocation can stall while Xcode finalizes its test record, so these suites are intentionally recorded from separate successful runs.
- The complete `refineid-lib-core` Rust test suite and the complete non-UI Apple `CardCoreTests` plus `RefineIDTests` suites pass on the source-pinned revisions.

### 2026-08-17 separate persistent-token shipping topology

- Rust RAPP ABI source revision:
  `c745bb0cbab18b82877ddfa1143690c9fb4ce0ab`, pushed to the Rust repository's
  `origin/main`. The tracked source includes
  `crates/refineid-lib-core/src/rapp/`, the Cargo manifests and lockfile, the
  library export, and the formal RAPP state-machine YAML used by conformance
  tests.
- Apple implementation revision:
  `14b1c715d2ae13f5ca45246d7c7a649d9a9701ae`, pushed to the Apple repository's
  `origin/main`.
- That Apple revision adds a separate macOS-only
  `RefineIDRappTokenExtension`, keeps `RefineIDTokenExtension` as the direct
  smart-card reader driver, declares the containing app's local-network and
  Bonjour metadata, and adds static shipping-configuration regression tests.
- Standalone RAPP-extension Debug, full macOS Debug, and full arm64 iOS-device
  Debug builds pass. Physical macOS-to-iPhone pairing and fail-stop
  qualification remain the exact next step and are not implied by these build
  results.

### 2026-08-17 production archive qualification

- Apple release-engineering revision `a27825f` is pushed to `origin/main`.
  It makes archive inspection require the separate macOS RAPP persistent-token
  extension, reject that extension from iOS, and validate both CryptoTokenKit
  driver identities and role-specific entitlements.
- The RAPP requester extension has local-network client and server access but
  no smart-card entitlement. The direct-reader extension has smart-card access
  but no network entitlement. The containing macOS app owns the required local
  network and Bonjour declarations.
- The sole public Swift release CLI produced and inspected local, non-uploaded
  TestFlight-configuration candidates for both platforms from commit
  `a27825f`: version `26.8.17 (60)`.
- The macOS archive passed with one app, the direct-reader extension, and the
  RAPP persistent-token extension. The iOS archive passed with one app, the
  reader and discovery extensions, and no macOS RAPP extension. Both archives
  passed architecture, diagnostic-string, coverage, entitlement, signing-team,
  version, privacy, quarantine, and strict code-signing gates and exported
  successfully.
- This proves the production artifact topology and static security boundary.
  It does not replace the still-pending physical Mac-to-iPhone pairing,
  authorization, browser-authentication, signing, and fail-stop run.

### 2026-08-17 stream transport and protocol 26.8.17.233

- The checked-in `RefineIDRappFFI.xcframework` and generated Swift binding
  were rebuilt from crate `refineid-rapp` version `26.8.5`, whose clippy
  and `--features bindings` test gates passed before regeneration. The
  binding adds `rendezvousToken` and `streamEndpoints` to
  `RappPairMetadata` and the free functions `rappStreamPairingPreamble`,
  `rappStreamSessionPreamble`, and `rappStreamProfileName`.
- The stored pair record format is v2. Format v1 records fail to load and
  surface as no usable pair; affected holders pair again.
- The vendored conformance corpus is
  `Documentation/rapp-conformance/rapp-v26.8.17.233.json`. The Swift corpus
  suites additionally derive the rendezvous token and independently encode
  the accepted stream rendezvous preambles.
- `StreamRelaySession` and its framing, endpoint, event, and error types
  implement the `fi.refineid.stream.v1` dialer in CardCore, proven by
  macOS unit tests against a localhost listener double.
- `PhonePersistentTokenRelay` dials stream pairs for sessions, and the
  scan flow pairs over the stream profile through the bridge's
  scanned-offer candidate listing, as recorded in the stream transport
  section above.
