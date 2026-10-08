# NFC card timing

A one-screen iOS app that measures how long a contactless identity card
takes to answer the opening rounds of PACE inside an NFC field the app
holds through CryptoTokenKit. It exists to compare iOS versions on the
same phone and card.

The probe opens the system NFC slot, waits for the card, takes its
session and sends four commands: MSE:Set AT, then the first three
GENERAL AUTHENTICATE rounds of PACE-ECDH-GM over brainpoolP384r1. The
card performs its two elliptic-curve computations in the mapping and
key-agreement rounds for any valid terminal point, so the probe sends
fixed multiples of the curve's base point and stops before the
authentication token.
Nothing is authenticated, no password is used, and no retry counter is
touched.

Build with Xcode 27 and run on an iPhone with iOS 26 or later. Tap
"Time the Card", hold the card to the top back of the phone, and read
the per-command times. "Copy Report" puts every run on the pasteboard.

The project file is generated from `project.yml` with xcodegen; edit the
YAML, not the project.
