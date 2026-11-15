# PIN Codes and Credential Management

Rules and architecture governing cardholder PIN codes, card access numbers,
retry counters, and credential storage across macOS and iOS.

## Core rules

The rules below reflect the project rules in [AGENTS.md](../../AGENTS.md)
(Rule #1, Rule #2, and Rule #4; Rule #3 governs commit comments rather
than security, and Rule #5 governs error visibility in development builds).

1. **PIN codes never travel over any network (Rule #1).**
   - PIN 1 and PIN 2 never leave the device where the card or reader is
     physically connected.
   - When accessed via Remote Access (served over RAPP), the remote card
     protocol absolutely denies any attempt to transport PIN codes.
   - PIN 1 is supplied locally to the card on the custodian device; verification
     is performed on-card. PIN 2 prompts for qualified document signatures
     appear strictly on the custodian device's physical screen (the phone
     display during RAPP).
2. **Zero PIN and PIN-length logging across all environments (Rule #2).**
   - Never log, trace, display, or format PIN bytes, candidate PIN lengths
     (e.g. `\(pin.count)`), or development PIN role identifiers in log sinks,
     audit records, test attachments, or error strings. Standard role names
     ("PIN 1", "PIN 2") may appear in UI copy and error events, but never values
     or lengths.
   - Never commit test PINs or card secrets.
3. **Keychain storage namespace (Rule #4).**
   - Every keychain service created by the app or its extensions begins with
     `fi.refineid`.
   - Wiping `fi.refineid` cleanly forgets all software-generated state (pairings,
     stored card access numbers, cached certificates) and leaves human-owned
     state untouched.

## PIN 1: Authentication and login

PIN 1 authorizes client authentication (TLS client certificates in Safari
and third-party apps via CryptoTokenKit).

- **Token custody.** PIN 1 is held in memory by the minting token extension
  to allow seamless Safari authentication.
- **Supplied to card.** PIN 1 is supplied locally to the card on the custodian
  device; verification is performed on-card.
- **Five-try limit rule.** PIN 1 custody starts and continues *only* while
  the card reports the maximum try limit (5 tries remaining). If the card
  reports fewer than 5 tries remaining (indicating a prior failed verification
  attempt or degraded retry counter), PIN 1 custody is immediately dropped.
- **Recovery of custody.** A subsequent successful interactive PIN 1
  presentation against the card resets the card's native hardware counter back
  to 5, at which point token extension custody can be re-established.
- **Keychain protection.** Stored PIN 1 data is saved with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, non-synchronizable, never
  displayed, and never in iCloud or backups. No biometric prompt gates storing
  PIN 1 (possession of the unlocked device plus card authorizes authentication).

## PIN 2: Qualified electronic signatures

PIN 2 authorizes qualified electronic signatures (PAdES and XAdES QES) with
the card's non-repudiation key.

- **On-device entry only.** A PIN 2 prompt is presented strictly on the
  physical screen of the card-holding custodian device (e.g. the phone's
  display when accessed via RAPP). PIN 2 is never entered on or transmitted
  to a remote computer (Rule #1).
- **Volatile memory caching for document piles.** When a cardholder drops a
  pile of documents to be signed together, PIN 2 is entered once and held
  in volatile memory only for the duration of that signing pile.
- **No persistent storage.** PIN 2 is never written to disk, keychain,
  user defaults, or extension shared storage. As soon as the signing pile
  completes, fails, or is cancelled, or if the app is backgrounded or the
  device locked, PIN 2 bytes are zeroed from memory.

## Retry floors and PUK handling

- **Hardware source of truth.** Under FINEID S1 v4.0 section 2.1, the physical
  smart card's internal security environment maintains the authoritative retry
  counters. Software never fakes or predicts retry exhaustion locally.
- **Safety floors.** A command that could spend a verification attempt (VERIFY)
  is refused locally when the counter is at 1 or 2 tries remaining or
  unreadable, protecting the cardholder from accidentally locking the card.
- **Blocked PINs and PUK submission.** At 0 tries remaining (blocked), the
  command is sent to the card so the card answers truthfully for itself (and
  spends nothing); software cannot know whether the code in the holder's hand
  is a PUK or an activation code, so it must not pre-emptively close a recovery
  the card would allow. On PACE channels floored on `MSE:Set AT`, `69 83` is
  itself the answer, while `63 C0` continues to the card.

## Card Access Number (CAN) and card families

- **Holder-visible access number.** The Card Access Number (CAN) is printed on
  the physical card. On iOS, the camera scanner reads it via OCR so the user
  does not have to type it manually, with manual typing entry always available.
- **Retention across activation.** Once PACE establishes a secure messaging
  channel with the CAN, the number is stored in the keychain under service
  `fi.refineid.credentials` (account `can`), even if the card is awaiting
  activation.
- **Candidate management and PACE refusal.** A contactless card reveals no
  chip serial or identifier before PACE, so software cannot determine which card
  is present on the antenna prior to establishing secure messaging. When a card
  is tapped, the driver tries candidate numbers (the unbound CAN in keychain
  service `fi.refineid.credentials` / account `can`, plus any per-card candidate
  managed by `CardCanOffer` on macOS). If PACE rejects the offered number, all
  candidate numbers in memory and keychain are wiped immediately
  (`CardCredentialStore.forgetEveryCardAccessNumber`) to stop repeated failed
  attempts from locking the card.
- **Activation guard.** A stored CAN does not mean a published identity. Storing
  the CAN allows re-trying PACE across NFC reconnects during setup and
  activation without re-prompting. However, authentication certificates,
  registered identities, and TokenExtension / Safari token publication remain
  strictly withheld until activation succeeds; an unactivated card is never
  offered to a browser or over RAPP.
- **Personal cards only.** Organization cards (FINEID Organization Card,
  AIDs `A0000000181002030000000000000000` and `A000000018434D00`) are
  explicitly gated off in all builds (`FEATURE_ORGANIZATION_CARD`). The software
  operates exclusively on personal citizen identity cards.
