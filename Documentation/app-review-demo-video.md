# App Review demo video, 26.8.16 (114)

What App Review asked for on 2026-08-16, what to film, and the exact text
to send back. Submission `48f4b685-f48a-4a48-9c4b-d2478e42e586`, reviewed
on an iPad Air 11-inch (M3).

## What was asked

Guideline 2.1, Information Needed. Not a rejection of the build: a
request for evidence. App Review wants one video that shows

- the current version of the app running on a physical Apple device,
  not a simulator;
- the initial pairing between the app and the designated hardware;
- the entire app workflow with that hardware, including every NFC
  interaction;
- both the hardware and the Apple device in the same frame.

The link goes in App Review Information, and the Resolution Center
message is then answered.

## Why it arrived now

The previous rejection (26.8.12, 2.1(a), 2026-08-12) asked for a demo
account or a demonstration mode and said a video was not sufficient.
That was about reviewer access to the app, and it was answered with the
Virtual ID Card demonstration mode. This request is a different thing:
evidence that the hardware interaction exists. Demonstration mode cannot
supply it, because it deliberately touches no card.

The review device explains the emphasis. An iPad has no NFC antenna, so
on an iPad the app can never open a scan sheet. A reviewer holding only
an iPad cannot see the NFC path at any setting, and nothing in the app
can change that. The video is the only way to show it.

## Which binary to film

App Review asks for "the current version of the app in use on a physical
Apple device, not on a simulator". The contrast is the device, not a
caption: nothing in the request asks for a version number to appear on
screen, and the shipping build displays none anyway - `BundledVersions`
is read only by the Debug diagnostics screen, which the TestFlight and
Release configurations exclude. Do not add a version label for the
video. That means a new build, and the video would then show a build
that is not the one under review.

What does matter is which binary runs. Install 26.8.16 (114) from
TestFlight and film that, not a build installed from Xcode: the
development build is a different configuration, carries diagnostics the
submitted binary does not, and is not the artifact under review. The
internal tester group takes every build, so 114 is already installable
with no distribution step.

Opening TestFlight on camera first, so the entry reads `26.8.16 (114)`
before the app launches, is optional. It costs five seconds and makes
the claim self-evident rather than asserted, which is worth having if a
follow-up question is cheaper to prevent than to answer. Skip it if it
complicates the shoot.

## Shot list

One continuous take is best; cuts are acceptable at the marked points.
Landscape, 1080p or better, three minutes or less. Narrate or caption in
English. Keep the card and the phone screen in frame together whenever
the card is being read.

1. **Version.** TestFlight showing `RefineID 26.8.16 (114)`, then open
   the app from there.
2. **The hardware.** Hold up the identity card, masked as below, and say
   what it is: a Finnish identity card issued by the Police, whose
   certificates are issued by the Digital and Population Data Services
   Agency. It is a contactless smart card under ISO/IEC 14443, read over
   the phone's NFC antenna.
3. **Initial pairing.** The card setup flow: entering the card access
   number printed on the card, then presenting the card to the top of
   the phone. Show the system scan sheet appearing, the card being read,
   and the screen reporting that the card is registered for Safari. This
   is the pairing App Review asked to see; the app has no other pairing
   step.
4. **Workflow, authentication.** Open Safari, go to a Finnish public
   e-service that asks for a certificate, choose the RefineID identity,
   present the card again when the system asks, enter PIN 1 off camera,
   and show the service reporting a completed sign-in.
5. **Workflow, signing.** Back in the app, pick a PDF, sign it with
   PIN 2 entered off camera, and show the finished signed document.
6. **The reader alternative, filmed on iPad.** Switch devices for the
   last minute: connect a USB-C smart-card reader to the iPad, insert
   the card, and show the same identity signing in. Filming this part on
   the iPad answers the review device in its own terms - the hardware
   the reviewer held has no NFC antenna, and this is what it does
   instead.

## What must stay off camera, and what need not

The video is credential-free, which is a narrower rule than it first
looks. Three values are genuinely secret, and the rest are not.

**Never filmed.** PIN 1, PIN 2, and the PUK. Enter them with the keypad
out of frame: the fields are masked on screen, fingers on a keypad are
not. These are the only values on the card with retry counters, and the
only ones whose exposure costs the holder anything on its own.

**Not a secret, and not treated as one.** The card access number is
printed on the card face, has no retry counter, and is holder-visible by
decision (`decisions.md`, 2026-07-28). It authorizes reading the card in
a field; it does not authorize a signature, which PIN 1 still gates. The
electronic client identifier is likewise public by construction: it sits
in the authentication certificate that the card hands to every service
the holder signs in to. Blurring either one would be ceremony.

**The one real consideration.** The access number exists to stop remote
skimming. Publishing this particular card's number removes the barrier
that keeps a stranger's reader from opening a PACE channel to it while
it sits in a pocket. That costs an attacker who has the card nothing -
they can read the number off its face - but it does matter for a card
carried in public. So it is the card owner's call, not a rule:

- keep it simple and film the number freely, accepting that this card is
  then skimmable at contactless range by anyone who saw the video; or
- cover the printed number and film its entry from behind the phone,
  keeping the barrier for this card intact.

Either way the demonstration is complete: nothing in the review depends
on the number being legible.

**Worth covering anyway.** The personal identity code printed on the
card. It is not secret either, but the electronic client identifier
exists precisely so services need not handle it, and a public video is
no reason to spread it. The photograph and holder name are the owner's
choice; the name is already public as the developer of record.

**Afterwards.** If the raw take shows a credential, the raw take is
deleted once the sanitized export exists.

## Hosting

The link must open without a login, from anywhere, and stay up while the
version is in review. `refineid.fi` is preferable to a video platform
because the file stays under our control and carries no recommendations
or comments beside it. An unlisted upload is acceptable if it needs no
account to view.

Record the exact URL in the release record for 26.8.16.

## Text to add to App Review Information

Append to `review.notes.ios` in `Metadata/appstore.json`, then push it
with the release manager's `review-contact` command. Fill the URL first;
do not push a placeholder.

```text
NFC AND THE DEMONSTRATION VIDEO

This app uses NFC. The designated hardware is the Finnish identity card
itself: a contactless smart card under ISO/IEC 14443, read over the
iPhone's NFC antenna through CryptoTokenKit. It is not an NDEF tag and
carries no writable payload; the app opens a PACE secure channel to it
and reads a certificate.

Demonstration video, no login required: <URL>

Filmed on a physical iPhone running exactly this build, 26.8.16 (114),
the video shows the version in TestFlight, the initial setup with the
card over NFC, a completed sign-in to a Finnish public e-service in
Safari, a signed PDF, and the same card working through a USB-C reader.
No PIN or PUK is visible at any point.

One note on review devices: iPad has no NFC antenna, so the NFC path
cannot run on the iPad Air used for the previous review. On iPad the
same card is used through a USB-C smart-card reader, which the video
also shows.
```

## Resolution Center reply

Send after the link is live and the notes are pushed.

```text
Thank you for the guidance, and for naming the review device - that
detail explains what could not be reproduced.

Yes, the app includes NFC functionality. The designated hardware is a
Finnish identity card: a contactless smart card under ISO/IEC 14443,
read over the iPhone's NFC antenna. It is not an NDEF tag. The app
establishes a PACE secure channel with the card and reads the
certificate the operating system then offers to Safari.

A demonstration video is now linked in App Review Information. It is
filmed on a physical iPhone running build 26.8.16 (114), the build under
review, and shows the version in TestFlight, the initial setup with the
card over NFC including the system scan sheet, a completed
certificate-based sign-in to a Finnish public e-service in Safari, a
signed PDF, and the same card used through a USB-C smart-card reader.
The card and the phone are in frame together throughout.

The review was performed on an iPad Air 11-inch (M3). iPad has no NFC
antenna, so the NFC path cannot execute there in hardware; on iPad the
card is used through a USB-C reader instead. That is why the video is
filmed on iPhone.

There is no demo account to supply: the app has no login, no server, and
no registration. The identity card is a legal identity document issued
to one citizen and cannot be duplicated or issued for testing, which is
why the build also carries the Virtual ID Card demonstration mode
described in the review notes. That mode exercises the app's screens
without a card; the video covers what only physical hardware can show.
```

## After approval of this step

The macOS submission of the same version is independent and unaffected;
it was still awaiting review when this arrived. Keep the video linked
for later versions: the requirement recurs whenever hardware interaction
cannot be reproduced by a reviewer.
