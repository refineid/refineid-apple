# When the card reads but nothing offers it

Faults whose symptoms impersonate other faults. Each one here cost an
evening at least once, and each is recognisable in a single log line
once you know what to look for.

## The system holds an old copy of the driver

**Symptom.** The app reads the card perfectly -- name, counters, card
type -- but no identity is published, `security list-smartcards` says
`No smartcards found`, and Safari offers nothing. Sites that worked an
hour ago fail, and they fail differently from each other, which invites
theories about TLS versions, readers and server configuration.

**Cause.** Replacing `RefineIDTokenExtension.appex` while `ctkd` is
running leaves PlugInKit holding the previous copy. `ctkd` says so:

    Token driver extension fi.refineid.ReFineID.token failed to start:
      Error Domain=PlugInKit Code=16 "other version in use", useCount = 1
    [CryptoTokenKit:slotwtch] No token driver found for card <TKSmartCardATR ...>

**Why `killall ctkd` does not fix it.** macOS runs more than one `ctkd`,
and the instance holding the slot watcher may belong to another user
account -- `afwd` on the development Mac, running since the previous
login. A kill from your own shell cannot touch it. Worse, killing
`ctkd` alone strands the reader daemons on dead XPC endpoints: the
reader stays enumerated on USB while the card stops reporting at the
PC/SC layer entirely, zero ATRs.

**What does fix it without a logout.** Take the whole family down in
one command and let the stack respawn coherently:

    sudo killall -9 ctkd ctkbind ctkahp com.apple.ctkpcscd

The four together include the PC/SC daemon, so the reader daemons
restart with the token daemons instead of being orphaned by them. The
next card insertion rebuilds everything. A reboot or logout still
clears every case, including the cross-account one above.

**Confirmed 2026-08-10.** After a day of extension replacements and
one stranding `killall ctkd`, the card had vanished at the PC/SC
layer while the reader sat enumerated on USB. Recovery took the
four-process kill together with unplugging and replugging the reader
-- and in the end a different reader -- before an insertion rebuilt
the card, the published identity and Safari logins, with no logout.
A reader that was powered through the stranding may need the replug
before it reports cards again; swap readers before concluding
anything about the card.

**Convicting a failing reader.** The kernel says so directly. Watch
the USB host log while replugging the suspect:

    /usr/bin/log show --last 10m --style compact \
      --predicate 'subsystem == "com.apple.iokit.IOUSBHostFamily"'

A healthy reader enumerates and stays. A failing one enumerates,
stalls an endpoint ("pipe stalled" on endpoint 0x00), and minutes or
seconds later the port logs "terminateDevice: destroying ... hardware
connection lost" with no unplug. That is the device dropping the bus
on its own. A reader doing this intermittently reproduces the whole
vanished-card pattern: reader listed, zero cards, everything above
this line innocent. The same card minting promptly in another reader
completes the conviction.

**Confirmed 2026-07-27.** After an evening of the appex being replaced
about fifteen times, four sites -- card.refineid.fi, admin.iki.fi,
suomi.fi and posti.fi -- all failed in different ways. A reboot restored
every one of them at once, with no code change. In that same evening the
driver signed 28 of 28 requests correctly, TLS 1.2 and TLS 1.3 alike.

**What to do.** During development, do not hot-swap the extension under a
running `ctkd` and then believe a failed login. Quit the app, install,
and reboot or log out before any test whose result you intend to trust.
When a card reads fine but publishes nothing, check for the PlugInKit
line above before looking at the wire or the server:

    log show --predicate 'process == "ctkd"' --last 10m --style compact \
      | grep -iE "no token driver|failed to start|other version"

## The system asks about a card only when it arrives

**Symptom.** A card access number is entered while the card is already in
the reader, and nothing happens. The status screen still says no identity
is available.

**Cause.** `ctkd` offers a card to a driver when the card *arrives*. A
card that was already present when the driver refused it -- because the
access number was not yet stored -- is never asked about again, and no
call from inside a sandbox makes the system look a second time.

**What to do.** Remove the card and put it back. The status screen says
this itself when it sees a readable card, stored credentials, and no
published identity.

## The app was taking the card away from Safari

**Fixed on 2026-07-27, recorded because the symptom was so misleading.**
The status screen's refresh dropped "stale" token configurations, which
included the configuration the system keeps for the *live* token -- so
opening the app unregistered the working card and then reported it
missing. Any login attempted after looking at the app failed. See the
commit "Stop the status screen unregistering the card it reports on".

## Sites ask for the certificate in different ways

Not a fault, but the reason results differ between sites with one card:

- **suomi.fi** asks during the initial handshake (TLS 1.2).
- **admin.iki.fi** asks by renegotiating after the page loads (TLS 1.2).
  If the renegotiation does not happen there is no prompt and no
  signature -- nothing reaches the driver to fail.
- **card.refineid.fi** and Telia certap are TLS 1.3, where the request is
  `ecdsa_secp384r1_sha384` and the signed content is 130 bytes: 64 bytes
  of padding, the 33-byte context string, a separator, and the transcript
  hash. A `sign: entry input=130B algo=msgX962SHA384` line in the driver
  log is a TLS 1.3 CertificateVerify and nothing else.
- **oma.posti.fi** authenticates through a single-use SAML conversation;
  a correct signature is not sufficient there by itself.

When a login fails, the first question is not which site or which reader,
but whether the driver was asked at all:

    log show --predicate 'subsystem == "fi.refineid.ReFineID"' --last 5m \
      --style compact | grep -E "supports:|sign: entry|sign: exit"

Asked and failed is ours. Never asked is not.

## Safari can retain a dead client-identity path

**Symptom.** The same live token signs in to one site, while another site
fails, hangs, or has a login button that appears to do nothing. No new
`createSession`, `supports`, or `sign` line appears in the extension
trace for the failed attempt.

**Confirmed on iOS 2026-07-29.** The connected-reader token had just
completed a TLS 1.3 signature for `card.refineid.fi`, but the DVV TLS 1.2
test page failed without invoking the token extension. Terminating only
Safari and reopening the same DVV page made it request
`ecdsaMessageSHA256`; two card signatures then passed local verification
and the page succeeded. No card, token, or RefineID state changed.

This evidence establishes stale Safari process state, not the internal
form or lifetime of that state. Do not reset the card identity in
response. Recreate the site's login conversation first; if the driver is
still never asked, force-quit Safari, reopen it, and retry. Once a
`supports` or `sign` line appears, diagnose that exchange instead.

**Confirmed on macOS 2026-08-22, production build.** The same token
signed in to three TLS 1.2 sites while `card.refineid.fi` (TLS 1.3)
failed, and a direct `SecKeyCreateSignature` probe through `ctkd`
completed the exact `ecdsaMessageSHA384` signature the site needs. A
Release extension writes no trace, but the failure is still observable
from outside: `log show --info --debug` with
`process == "ctkd"` recorded Safari evaluating token access dozens of
times in one second, each connection cancelled within milliseconds and
no signature ever requested. Safari sent no certificate, and the server
answered its no-certificate page (here HTTP 403). TLS 1.3 makes the
state stickier than TLS 1.2: a resumed session ticket skips the
certificate request entirely, so reloading the page cannot recover.
## Unsolicited "Ready to Scan" (`Valmis etsimään`) NFC prompts on iOS

**Symptom.** On iOS, the system presents the "Ready to Scan / Present your identity card" NFC modal sheet unexpectedly—even when sitting on a blank Private Browsing tab, when opening Apple Mail, or with zero websites open.

**Cause.** `TKSmartCardTokenRegistrationManager.registerSmartCard` registers the smartcard token globally with iOS `ctkd`. On iOS, `ctkd` treats *any* passive Keychain identity evaluation (`SecItemCopyMatching` for `kSecClassIdentity`) as an active request requiring a hardware smartcard scan:
- **Safari / WebKit:** Opening a new tab or switching to Private Browsing initializes `WKWebsiteDataStore`, which queries the Keychain for available client identities.
- **Apple Mail & S/MIME:** Apple Mail regularly scans for email signing identities (`emailProtection` EKU, which Finnish citizen certificates carry).
- **System Services:** Background daemons (`securityd`, `trustd`, `authkitd`) query Keychain identities on network changes and device unlock.

**What to do.**
1. In Safari, close inactive mTLS tabs when finished and turn off **"Preload Top Hit"** in iOS Settings > Safari.
2. In Mail, ensure S/MIME Signing is turned off unless actively needed.
3. If you only use RefineID for Mac pairing (RAPP) or in-app signing, tap **Reset / Unregister Safari Identities** in the app to remove the global `ctkd` hook without deleting your stored card data (`PrimeStore`).

## Uninstalling, and what a trashed app leaves behind

Moving `RefineID.app` to the Trash removes the app and deregisters the
CryptoTokenKit driver with it: once the bundle is gone the smart-card
system no longer lists the extension, so the card stops being offered
system-wide. That much a trash is enough for.

It is not a complete removal. macOS provisions two kinds of sandbox
directory per app and per extension, outside the bundle, and they
stay:

- `~/Library/Containers/fi.refineid.ReFineID`
- `~/Library/Containers/fi.refineid.ReFineID.token`
- `~/Library/Application Scripts/fi.refineid.ReFineID`
- `~/Library/Application Scripts/fi.refineid.ReFineID.token`

The containers hold preferences and the extension's working area; the
Application Scripts directories are where a sandboxed app may keep
user automation scripts, and stay empty because this app ships none.
None is a stored secret, but a complete removal deletes all four:

    rm -rf ~/Library/Containers/fi.refineid.ReFineID \
           ~/Library/Containers/fi.refineid.ReFineID.token \
           ~/Library/Application\ Scripts/fi.refineid.ReFineID \
           ~/Library/Application\ Scripts/fi.refineid.ReFineID.token

The shipped MVP creates nothing under `~/Library/Group Containers` or
a `4ZJC3SFJR2.fi.refineid` group directory: those belong to the
contactless access-number channel, and contactless reading
(`FEATURE_CONTACTLESS`) is out of the first release with its
`application-groups` entitlement removed, so macOS creates neither the
group container nor its Application Scripts directory. A build with
contactless enabled would also leave
`~/Library/Group Containers/4ZJC3SFJR2.fi.refineid` and
`~/Library/Application Scripts/4ZJC3SFJR2.fi.refineid` to delete.

To confirm the driver is gone, either of these should name nothing:

    system_profiler SPSmartCardsDataType | grep -i refineid
    pluginkit -m | grep -i refineid

LaunchServices keeps its own cached record of the removed bundle - the
app name, its document types, the paths it used - and current macOS
offers no command to flush a single stale entry. The record points at
paths that no longer exist, loads nothing, and is garbage-collected by
the system in time. It is not a driver registration; `pluginkit` and
the smart-card system above are the authorities on that.

**A build with the SCS enabled leaves one more thing.** The Signature
Creation Service, which the first App Store release does not ship
(`Documentation/decisions.md`, 2026-08-11), trusts a `127.0.0.1`
certificate so the browser can reach its loopback server. A removal of
such a build should also delete that certificate in Keychain Access
(search `127.0.0.1`), which clears its trust with it. The shipped MVP
creates no such certificate, so its uninstall is the three directories
above and nothing more.
