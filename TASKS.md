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

## Optional delivery infrastructure

Xcode Cloud onboarding and tag-driven distribution are infrastructure work,
not prerequisites for a release produced and inspected by the existing release
manager. Retain release evidence regardless of the build provider.

## Engineering references

The [release plan](Documentation/release-plan.md#release-evidence-reconciliation)
records established release evidence. The
[RAPP handoff](Documentation/rapp-implementation-handoff.md) and
[same-Apple-ID pairing design](Documentation/same-apple-id-automatic-pairing.md)
retain protocol architecture and verification details. Completed phases are
not repeated here as tasks.
