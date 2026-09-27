# Apple release task list

Last reviewed: 2026-09-27. Completed work is removed; this file holds only
outcomes still required for a beta, an App Store release, or the next
protocol milestone.

## Status

- First release: iPhone MVP on iOS 26. RELEASED: 26.8.21 (200), commit
  `cbd4b4a`, approved overnight and READY_FOR_SALE 2026-08-22 - the
  version auto-released on approval (Documentation/releases/26.8.21.md).
  Tagged `ios-v26.8.21-release.200`, GitHub release published. Automatic
  release on approval is the standing policy (runbook section 7).
- Version 26.9.5: Physical smart card reader web authentication from Mac via
  iPhone RAPP proxy verified live on `https://card.refineid.fi/` with native
  PIN 1 prompts on iOS, reader priority over wireless presence, and PIN 2
  excluded from macOS browser identities. In-band encrypted card departure
  signaling specified in `Documentation/card-departure-privacy-and-signaling-plan.md`.
  Experimental iOS 16 backport dropped; platform floor is firmly 26.0 for iOS/macOS.
- Ships: one-step NFC priming, Safari login, document signing and checking,
  PIN changes, USB-C reader signing, demo mode (virtual card starts activated).
- First full version (owner decision 2026-09-10): every configuration
  ships the remote card (`REFINEID_REMOTE_CARD`), card activation
  (`FEATURE_CARD_ACTIVATION`), macOS contactless (`FEATURE_CONTACTLESS`),
  the visible PDF stamp (`FEATURE_PDF_STAMP`), and the SCS loopback
  server (`FEATURE_SCS`). All configurations point at the development
  Info.plists and entitlements; the `Config/*-Store-*` files stay as the
  retired gated reference. Shipping configs: floor 26, iPhone-only,
  `nfc` required capability. Enforced by the archive inspector and
  `RappShippingConfigurationTests`.

- SCS macOS release work is complete and accepted for this release on
  2026-09-27: default-off opt-in, listener lifecycle, concise localized prompts,
  and shared credential labels. Tests, CI, and device installs passed; see
  [release status and evidence](Documentation/release-plan.md#scs-release-status).

## Remaining macOS release decisions and checks

Established functionality is not an open implementation gate. The owner-recorded
real-card testing in [26.8.16](Documentation/releases/26.8.16.md), the live Mac/iPhone
verification above, and the [2026-09-11 cross-platform qualification decision](Documentation/decisions.md#2026-09-11-6-digit-pairing-standard-cross-platform-qualification-and-macos-store-gates)
remain valid evidence. Do not require the whole product to be proven again merely
because an older checklist was left unchecked.

- [ ] Inspect the exact candidate through the release manager: signing,
  entitlements, both CTK extensions, version/provenance, and exclusion of the
  debug harness. Existing inspection automation is implemented; retain this
  candidate's result.
- [ ] Review the changes since the last hardware verification and perform a
  focused candidate smoke check for affected paths. Reuse established RAPP and
  direct-reader evidence; expand only where changes or failures justify it.
- [ ] Review current localized screenshots, `Metadata/appstore.json`,
  [reviewer instructions](Documentation/app-store-review-notes.md), and
  human-approved What's New for this candidate. The Mac screenshot pipeline
  and metadata synchronization already exist.
- [ ] Record which current accessibility journeys have passed and resolve any
  actual failures. Keyboard, localization, and accessibility audit suites exist;
  their existence alone does not prove every shipping state was audited.
- [ ] Resolve the independent RAPP security-review requirement with the release
  owner: the handoff records no completed independent review. Cross-platform
  interoperability is already qualified and must not be listed as missing.

## Established implementation and evidence

- Virtual ID Card is available on macOS; activation, editor, signing, credential,
  localization, keyboard, and accessibility UI test suites exist.
- Mac marketing capture/generation is documented in
  [App Store screenshots](Documentation/app-store-screenshots.md) and implemented
  by `Scripts/store-screenshot.sh` and `Scripts/generate-store-screenshots.swift`.
- A blocked PIN remains eligible for PUK recovery; it does not spend another
  PIN attempt. The release owner confirmed this policy on 2026-09-27.
- Retry-policy tests cover unreadable, low, healthy, verified, and blocked
  states. The reader probe and the measured system-NFC deadline exception are
  documented in the release plan and the 2026-07-28 decision. These are not
  missing implementations. A complete per-path command-count audit is not
  established by this document review.
- RAPP pairing, authorization, operation lifecycle, refusal, failure, and
  revocation have automated coverage and recorded cross-platform qualification.
- Archive inspection and release distribution run through
  `Scripts/apple-app-store-connect-release-manager.swift`.

## Optional delivery infrastructure

Xcode Cloud onboarding and tag-driven distribution are infrastructure work,
not prerequisites for a release produced and inspected by the existing release
manager. Retain release evidence regardless of the build provider.

## Automatic & Secure Same-AppleID Device Pairing

Read `Documentation/same-apple-id-automatic-pairing.md` for architecture and cryptographic specification.

- [x] Phase 1: Cloud synchronization layer (`RappCloudSyncCoordinator`) backed by `NSUbiquitousKeyValueStore` to securely distribute public keys, device metadata, and rendezvous seeds across user's devices without syncing private keys.
- [x] Phase 2: Noise IK / KK (`Noise_KK_25519_ChaChaPoly_SHA256`) pre-authenticated mutual handshake derivation (`RappSameAccountPairBuilder`, `RappDeviceIdentity`) for zero-interaction pairing between devices on the same Apple ID.
- [x] Phase 3: Hardware-first priority arbitration (`CardSourceArbitrator`) and automatic background service sync (`RappAutoPairingService`) when a Mac or iPad opens RefineID and requests smart card operations from the card-holding iPhone.
- [x] Phase 4: Full test coverage and end-to-end integration test (`RappAutoPairingIntegrationTests`) verifying multi-device 1:N reconciliation across iPhone, iPad, and Mac.

## RAPP

Cross-platform pairing and card proxying are qualified in the 2026-09-11
decision. Further independent-peer development is future protocol work.

## RAPP handoff

Read `Documentation/rapp-implementation-handoff.md` before changing RAPP.

The protocol engine is implemented in 100% native Swift in
`CardCore/Sources/RappEngine`; its authority is the vendored spec, formal
state model, and conformance corpus, and its tests fail on disagreement.

Done: pairing, authenticated transport, explicit phone-holder authorization,
browser auth, document signing, acknowledgements, durable
selection/revocation, one-violation durable fail-stop. macOS ships separate
reader and RAPP CTK extensions (smart-card vs network entitlements, never
both). CardCore test suites (`CardCoreTests`, `RappEngineTests`) green.
Activation and PIN management are deliberately not RAPP operations.

Concept and cross-platform verification: 6-digit numeric code pairing and
operations are qualified and verified across Android - Mac, Android - Linux,
Mac - iPhone, Mac - Android, Linux - Android, and Windows. Formal Phase E
archive qualification runs against the exact candidate artifact without dev-only crutches.

The phase descriptions below preserve the engineering acceptance criteria.
They are not a list of unimplemented features. Reconcile an individual criterion
with current tests and recorded qualification before opening new work.

### RAPP plan

Phases in order; a later phase may start early only if it does not weaken or
bypass the production protocol path.

- A, reproducible baseline: change spec and formal model first, regenerate
  and re-vendor corpus/vectors, then the engine; push Rust before the Apple
  commit that pins it. Accept: clean checkout builds with Xcode alone; the
  release manager rejects mismatched provenance; both RAPP suites green.
- B, hardware-free seam: narrow seams for peer transport and card effects,
  production defaults unchanged; an in-memory duplex transport between two
  real coordinators carrying real frames (may drop, duplicate, reorder,
  corrupt, expire; never synthesizes success); Virtual ID Card as the card
  effects; injectable time/entropy at the test boundary only; tests reach no
  real reader, NFC, Keychain, or credential store without opt-in. Accept: one
  process runs pair→session→operation→authorize→execute→acknowledge with real
  peers; frame mutation produces production fail-stop; no test branch assigns
  UI state.
- C, Debug-only UI driver: launch controls for isolated vault, in-memory
  transport, fixtures, scenarios, rejected outside Debug; pairing driven
  through the visible controls (scanner replaceable, the URI must be a real
  offer); editor and sheets localized fi/sv/en and fully accessible; no
  secrets in accessibility text; shards below the device timeout. Accept:
  VoiceOver-only walkthrough works; the release manager proves the driver
  absent from store archives.
- D, behavior matrix: pairing (offer, review, approval, persistence,
  reconnect; denial, malformed/expired offer, transport loss per phase,
  removal, durable revocation, re-pair with new keys); operations (status,
  browser auth, signing with PIN 2 on the phone only, busy, cancel, expiry,
  card removal, completion ambiguity, safe reconnect); fail-stop (bad
  credentials, corruption, replay, sequence violation, identity mismatch —
  first authenticated violation durably revokes, no retry or silent re-pair;
  credential rejection clears local state; activation/PIN management always
  rejected). Accept: every formal transition tested both ways; exact
  card-command counts proven, retry-floor refusal proves zero; durable state
  asserted after restart.
- E, physical qualification: record hashes, versions, devices, card, reader,
  sanitized start state; 6-digit code pairing, status, Safari auth, signing, denial,
  card removal, relay loss, app/extension restart, one synthetic fail-stop,
  durable revocation, re-pairing; extensions never claim each other's
  capability; never spend a real credential retry. Accept: the exact archived
  candidate passes the whole recorded matrix without dev-only crutches.
- F, independent interop and review: a minimal independent peer from the
  published spec and corpus (no shared Rust); cross-run the vectors; external
  review of crypto, pairing ceremony, transcript binding, replay, privacy,
  DoS, local-network exposure, teardown; high-severity findings resolved
  before TestFlight, accepted risks recorded with owner and date. Accept:
  interop without Apple-private assumptions; docs match code and corpus.
- G, freeze and distribute: all gates through the release manager; notes from
  the exact diff, human-reviewed before upload; never rebuild between
  qualification and upload; record identifiers, provenance, tester groups,
  rollback decision. Accept: uploads hash-match the qualified exports;
  archives carry no debug harness.
