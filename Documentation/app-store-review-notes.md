# App Review notes

What goes into App Store Connect's "Notes" field for the iOS and macOS
reviews, and the evidence kept ready for reviewer questions. Reviewers
have no Finnish identity card, so the notes must explain what the app
is and what they can exercise without one.

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
and document signing, and the remote card: pairing with a phone that holds
the card by typing the code the phone shows, then signing and Safari
sign-in through the phone. The Mac only dials out to the paired phone on
the local network, which is what the local-network prompt and the Bonjour
declaration are for; it never listens. SCS is excluded. Outbound timestamp
and revocation requests support archival document signatures.

## Where the notes live

`Metadata/appstore.json`, under `review.notes`, and they reach App
Store Connect with
`Scripts/apple-app-store-connect-release-manager.swift review-contact
<ios|macos> <version>`. They were duplicated here once and the copy
went stale, so the text is not repeated: read it there.

## Evidence held ready

- Export compliance rationale: `Documentation/export-compliance.md`.
- Sandbox and entitlement rationale: comments in
  `Config/RefineID.entitlements`.
- ATS rationale: comments above `NSAppTransportSecurity` in all four
  application plists (`Config/RefineID-Info.plist`,
  `Config/RefineID-Store-Info.plist`,
  `Config/RefineID-iOS-Info.plist`,
  `Config/RefineID-iOS-Store-Info.plist`). Every binary makes network
  requests when signing a document: the time-stamp authority and
  revocation endpoints an archival signature needs.

## Open decisions

- Whether to provision a dedicated non-production card and reader
  for the review team; any review PIN stays out of source, issues,
  logs, and recordings.
