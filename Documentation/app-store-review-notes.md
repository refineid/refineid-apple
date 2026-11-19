# App Review notes

What goes into App Store Connect's "Notes" field for the iOS and macOS
reviews, and the evidence kept ready for reviewer questions. Reviewers
have no Finnish identity card, so the notes must explain what the app
is and what they can exercise without one.

Review proceeds without hardware. No card, reader, or review PIN is
provided to Apple, so the Virtual ID Card is the review path on both
platforms.

## What the first submission taught

The iOS submission of 26.8.12 (135) was rejected under guideline
2.1(a), Information Needed, on 2026-08-12. The reply asked for a demo
account or a demonstration mode and said in terms that a video of the
app in use is not sufficient.

The notes at the time offered exactly that video, so the offer is
removed. What replaced it says the two things the guideline turns on:
there is no account to supply because the app has none, and the
hardware is a legal identity document issued to one citizen, which
cannot be duplicated or lent. The notes then list what does run
without a card.

Beta App Review approved the same binary on both platforms the same
day. The rejection is about reviewer access, not about the build.

## The answer to it

The demonstration mode the notes offered to add was added, on iOS
only, on 2026-08-13, and grew into the Virtual ID Card: an explicit,
fictional identity card whose state a reviewer edits through a
floating editor, driving the production screens through PIN changes
and resets, retry refusal, fault injection, and qualified signing of a
fictional PDF. The demonstration starts from the scenario the build
offers: with card activation shipping (`FEATURE_CARD_ACTIVATION` on in
TestFlight and Release, `Config/Features.xcconfig`), the card arrives
factory fresh so the activation form is the first thing a reviewer
walks through; with activation gated out, it arrives already
activated.
`Documentation/virtual-id-card.md` owns the design; the iOS notes walk
a reviewer through it, fictional numbers included, so no step depends
on guessing a value.

The macOS notes walk through the same Virtual ID Card the Mac way.
The mode is a toggle in the View menu, Demo Mode (Option-Command-D),
with Edit Virtual Card... (Option-Command-E) below it while the mode
is on. Nothing in the window enters the mode, and the app has no Help
menu (`Documentation/design/macos.md`). While it runs, the window
shows the red DEMO MODE bar at its foot and a red floating Virtual ID
Card button that opens the editor as a sheet. The Mac card sits in a
fictional contact reader, so no card access number is asked for; the
notes give the activation PIN for the factory-fresh start, example
PIN 1 and PIN 2 values with their digit counts, and the PIN 1, PIN 2
and PUK of the activated states. A reviewer can exercise activation,
PIN changes and resets, retry floor refusal, and qualified signing of
a dropped or supplied PDF with fictional credentials and no hardware.

The macOS notes describe local authentication, activation, PIN management,
and document signing only: with the remote card gated off, the Mac
declares no Bluetooth, no local-network prompt, and no Bonjour service,
and never listens. SCS is excluded. Outbound timestamp and revocation
requests support archival document signatures.

## Where the notes live

`Metadata/appstore.json`, under `review.notes`, and they reach App
Store Connect with
`Scripts/apple-app-store-connect-release-manager.swift review-contact
<ios|macos> <version>`. They were duplicated here once and the copy
went stale, so the text is not repeated: read it there.

## Evidence held ready

- Export compliance rationale: `Documentation/export-compliance.md`.
- Sandbox and entitlements: `Config/RefineID-Store.entitlements`, the
  macOS app's entitlements in every configuration. With the remote card
  gated off for the MVP the Mac carries no Bluetooth; it never listens,
  so no server entitlement.
- ATS rationale: the text App Review reads is `review.notes` in
  `Metadata/appstore.json`, and the macOS notes carry it. The comments
  above `NSAppTransportSecurity` in both application plists
  (`Config/RefineID-Store-Info.plist`,
  `Config/RefineID-iOS-Info.plist`) hold the same rationale inside the
  repository; comments do not survive plist compilation, so they are
  not part of what the reviewer receives. Every binary makes network
  requests when signing a document: the time-stamp authority and
  revocation endpoints an archival signature needs.

## Open decisions

- The iPhone `review.notes` do not yet carry the ATS justification; the
  macOS notes carry the MVP's. Add the iPhone text before an iPhone
  submission.
