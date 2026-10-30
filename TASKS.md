# Apple release task list

Last reviewed: 2026-10-23. This file holds only outcomes still required for
the next App Store submission or protocol milestone; completed work is
removed. Release history is in [Documentation/releases](Documentation/releases).

## Before the next App Store submission

- [ ] Smoke-check the exact submitted candidate on hardware for the paths
  changed since the last verification.
- [ ] Review the localized screenshots, `Metadata/appstore.json`,
  [reviewer instructions](Documentation/app-store-review-notes.md), and the
  human-approved What's New for that candidate.
- [ ] Record which accessibility journeys have passed and resolve any actual
  failures. See the
  [September 30 assessment](Documentation/macos-accessibility-assessment-2026-09-30.md)
  for recorded failures, findings, and unverified journeys.

## Optional delivery infrastructure

Xcode Cloud onboarding and tag-driven distribution are infrastructure work,
not prerequisites for a release produced and inspected by the existing release
manager. Retain release evidence regardless of the build provider.

## Engineering references

The [release plan](Documentation/release-plan.md#release-evidence-reconciliation)
records established release evidence. The
[RAPP handoff](Documentation/rapp-implementation-handoff.md) retains protocol
architecture and verification details.
