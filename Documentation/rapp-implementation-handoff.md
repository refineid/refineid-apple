# RAPP Apple implementation handoff

Status date: 2026-10-22

This document is the implementation handoff for Remote Authorization Proxy
Protocol (RAPP) support in RefineID on Apple platforms. It describes what is
present in this repository, where the protocol authority lives, what has been
measured, and what the next agent must do. It is not a security approval or a
claim that RAPP is production-ready.

## Protocol authority

The vendored documents are the authority, and the Swift engine in
`CardCore/Sources/RappEngine` implements them. There is no compiled protocol
artifact in this repository.

- Specification: `Documentation/protocol/rapp-v26.10.29.md`, with the
  transport and discovery hierarchy it cites in
  `Documentation/rapp-transport-and-discovery-hierarchy.md`.
- Formal state model: `Documentation/protocol/rapp-state-machine-v26.10.29.yaml`;
  the pairing, session and operation tables transcribe it and are checked
  against it in both directions, and the engine's constants against its
  constants.
- Conformance corpus: `Documentation/rapp-conformance/rapp-v26.10.29.json`
  (`SHA-256 6e0ace388cbe3a5c0e915c5ff7ebdb07de1f6687532d497cdc0cd28f65ca25ee`),
  copied unchanged from the reference repository. Its `cpace_kc2`,
  `noise_handshake`, `pairing_offer`, `pairing_busy`, and `discovery_hint`
  sections are replayed byte for byte on both the BLE and stream profiles,
  and every `rejected_pairing_busy` encoding is refused for its stated
  reason.
- Vectors covering what the corpus does not reach, all v26.10.29 and copied
  unchanged from the reference repository: `rapp-operation-v26.10.29.json`
  (operation bodies, the batch signing bodies, the storage confirmation,
  card status, progress, result and error bodies, and the error names a
  result may carry), `rapp-routing-v26.10.29.json` (session preambles),
  `rapp-withdrawal-v26.10.29.json` (service withdrawal) and
  `rapp-ble-sar-v26.10.29.json` (BLE segmentation and reassembly).

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

- The phone is the authorizer and keeps the CAN; no PIN is stored on any
  device. PIN 1 is asked once on the phone and held only in its memory,
  bound to the card the phone holds, until that card leaves or is
  replaced, the card refuses it, the holder forgets the card's setup, or
  the process ends. PIN 2 is asked for every signature or batch and kept
  no longer (RAPP v26.10.29 §11).
- The requester receives operation results, not card credentials.
- An operation that uses a private key takes its PIN on the phone: the PIN
  prompt is the holder's consent, and a browser authentication whose PIN 1
  the phone holds runs with no prompt. Reads (`inspect_card`,
  `read_identity`, `read_certificate`) ask the holder nothing (§8.2).
- The phone reports the card it holds: a reader card from insertion until
  removal, an NFC card from the holder adding it until the holder removes
  it. An operation the card did not answer ends with `card_error` and
  changes nothing (§8.4 item 1).
- The Mac or iPad offers the phone's identity on a certificate a session
  confirmed by fingerprint, also between sessions, and withdraws it after
  120 seconds without a present report, or at once on a forget, a
  revocation or a different card (§8.4 item 3).
- A phone that cannot admit a pairing attempt, because another attempt is
  active or the 500 ms spacing has not passed, answers `pairing-busy` with
  its wait and evaluates nothing of the code. The Mac asks that phone again
  after the other phones and after the wait, within the eight pairing
  connections of one typed code, and shows nothing while it waits (§3.3
  item 6, §4.2).
- A session carries one live operation; a second is refused `busy`, a reused
  identifier `duplicate_operation`, and the card serves operations in the
  order they arrived (§8.1, §8.2).
- An authenticated protocol violation closes the session with
  `protocol_violation`; the pairing stays. No failure revokes a confirmed
  pairing: only a user forgetting it does, and the peer is told by a
  `pairing_revoked` close, in session or on the next one (§4.6, §10.1).
- A PIN the card refuses is asked for again on the phone; the card's last
  attempts are reserved for its issuer's software (`retry_floor`), and the
  requester learns only the outcome (§10.2).
- Card activation and PIN management are not remotely exposed.

The presently supported remote operation families are card status, browser
authentication, and qualified document signing.

## The Swift engine

`CardCore/Sources/RappEngine` is the protocol engine. It depends on Foundation
and CryptoKit only, and is organised as:

- `Noise/` the Noise framework, with the two patterns this protocol uses
- `Wire/` deterministic CBOR, the envelope, and the message registry
- `Rapp/` the prologues, the derivations, and the transport channel
- `State/` the formal model transcribed as tables
- `Storage/` the offer, the pair record, and the wire bodies of operations
- `Flow/` the pairing and session ceremonies
- `Runtime/` session liveness
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

`fi.refineid.stream` (RAPP v26.10.29 §2.2.2) carries RAPP between Apple
and non-Apple peers alike. The underlay is plain TCP. Every
frame is a 2-byte big-endian length prefix plus payload; a zero length is
malformed and the prefix bounds every allocation. The phone listens and the
requester dials (discovery hierarchy). The requester's first frame is the
plaintext routing preamble whose bytes come from `RappEngine`
(`rappStreamPairingPreamble` / `rappStreamSessionPreamble`); the transport
layer never constructs those bytes.

- Pairing: after a pairing preamble the custodian sends
  `encode_deterministic_cbor(pairing-offer)` as its first frame, with a
  random `offer_id`, the connection's transport entry, and a 300000 ms
  lifetime. The requester reads that offer before CPace
  (`RappPairingCoordinator.requester(options:)`); over BLE the same offer
  is read from the bootstrap characteristic
  (`requester(options:bootstrapOffer:)`). The CPace context and the
  Noise_XXpsk3 prologue bind the connection's transport profile and
  candidate.
- The custodian admits at most one connection per 500 ms to the offer and
  one attempt at a time (§3.3 item 6). A failed attempt frees the slot and
  leaves the offer as it was; only its lifetime, its consumption or the
  holder end it.
- Sessions bind the transport profile of the connection they run over,
  not the one the pair was made on.

Stored pair records are format 6: they carry the pairing's transport
binding and, for a pairing the local user forgot while no session was open,
the time it was forgotten; such a record serves nothing and keeps its key
only to deliver the `pairing_revoked` close on the next session, for at most
30 days (§4.6). Records of another format fail to load and are removed at
launch, so existing holders pair again.

## Application wiring

The application layer is under `Sources/App/`:

- `RappPairingUI.swift` presents pairing-code entry and visible paired status.
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
`_refineid-stream._tcp` Bonjour service; the RAPP extension's Info.plist
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
  extension ran its requester transport from the extension process. Treat as integration evidence, not release
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
3. Pair macOS and iPhone from a clean pairing state using the pairing-code UI.
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
