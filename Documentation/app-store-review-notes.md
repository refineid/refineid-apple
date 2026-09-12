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
fictional PDF. Since activation was gated out of the shipping
configurations (Documentation/decisions.md, 2026-08-21), the
demonstration card arrives already activated, and a factory-fresh
state chosen in the editor shows the version's activation refusal
rather than the form. `Documentation/virtual-id-card.md` owns the
design; the iOS notes walk a reviewer through it, fictional numbers
included, so no step depends on guessing a value.

The macOS notes provide an explicit walkthrough of the Virtual ID Card, matching
the iOS submission pattern. When no physical smart-card reader or card is
attached, the main window offers an "Explore with a Virtual Demo Card" action.
This allows App Reviewers to exercise the complete card lifecycle: status
display, PIN changes and resets, retry floor refusal, and qualified document
signing of sample PDFs with fictional credentials without physical hardware.

The macOS notes also document the network behavior and state that the SCS
loopback signing server (127.0.0.1) is disabled by default and requires
explicit holder opt-in in Settings before initializing local certificate trust.

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
- ATS rationale: comments in both `Config/RefineID-Info.plist` and
  `Config/RefineID-iOS-Info.plist`. Both binaries make network
  requests when signing a document: the time-stamp authority and
  revocation endpoints an archival signature needs.

## Open decisions

- Whether to provision a dedicated non-production card and reader
  for the review team; any review PIN stays out of source, issues,
  logs, and recordings.
