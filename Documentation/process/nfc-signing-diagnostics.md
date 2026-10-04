# NFC signing diagnostics

The token extension retains one powered field per hold. PACE keys and secure
messaging counters never cross field loss. A replacement field establishes PACE
again. Discovery holds remain passive until signing claims them; pending-sign
mints start preparation immediately.

Run `Scripts/test.sh nfc-signing` for the deterministic retained-field and PACE
suite. The tests cover slot loss during early and sign-triggered preparation,
waiter notification before transport completion, exactly-once cleanup, late
worker completion, fresh preparation on replacement, stale timers, and rejection
of commands from an invalidated active lease. They do not simulate Apple's NFC
sheet, radio, Safari, or CryptoTokenKit scheduling.

In development builds, collect the extension trace from the app's Diagnostics
screen after reproduction. Token-to-hold-to-channel links use ephemeral random
identifiers. Held events carry monotonic age; PACE phase events carry elapsed
time from establishment. Release events distinguish activity timeout, slot
missing, card removal, sign failure, revocation, and token destruction. Pending
recovery events show recording, expiry, and clearing. APDU completion lines name
the channel, so an old timeout cannot be mistaken for a successful replacement.
These added events stay in the in-memory trace during field work. They contain
no credential values, candidate lengths, access numbers, or card identifiers.

Interpret the sequence before assigning a cause:

- `activityTimeout` preceding slot loss means the app released an unclaimed hold.
- `slotMissing` or `cardRemoved` during PACE invalidates preparation immediately;
  transport cleanup may follow later, after an outstanding command finishes.
- `PACE discarded` means an old worker completed after invalidation or replacement.
- An absent-field sign returns token-not-found and records pending recovery.
- A gap before the next mint has no demonstrated in-extension wait unless a
  correlated operation remains outstanding. Record when the scan sheet appeared
  and when the card was presented to distinguish system scheduling from user time.

Physical acceptance requires Safari certificate authentication with the real
card on the target iOS build: normal and private browsing, immediate signing,
certificate approval after the discovery hold ends, card removal during PACE,
and a fresh scan afterward. Confirm fresh PACE, successful verification and
signature output, prompt failure on loss, and absence of old-channel commands
after invalidation. Do not call radio behavior or Safari recovery verified from
synthetic tests alone. A slow exchange does not by itself prove a card penalty
delay or an OS-imposed field deadline.

Protected maximum-response RSA signatures use CryptoTokenKit's structured send
operation. Its protocol handling collects continuation before completing the
operation. The development trace records `mode=ctkContinuation` before that send;
the final APDU line reports the assembled response and total elapsed time. PACE
and exact-length ECDSA commands use raw transmission. Assume only two seconds of
usable NFC field; a longer observed hold is not a promised budget.

The focused suite also exercises the actual transmission dispatcher with a
modulus-wide response, transport failure, and byte-exact PACE/ECDSA routing,
alongside secure-messaging and command-framing tests. Physical RSA acceptance
must collect the complete signature without an extension-level GET RESPONSE
between the protected signature send and its completion. This does not prove
that CryptoTokenKit can complete every card calculation within the field budget.

`publish` records the experiment setting, stored-credential presence, and actual
password constraint for each minted identity. With a stored credential,
contactless publication has no native password constraint in either mode.
`sign: authorization elapsedMs` measures credential resolution before PACE or
signature work. Compare those events alongside credential-source events when
experiment settings appear to change site behavior; the setting alone does not
identify whether a native prompt occurred or whether Safari reused an identity.
