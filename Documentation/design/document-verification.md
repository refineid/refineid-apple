# Document verification

How the Apple apps verify a signed document, and where the verifier's
trust anchors come from. The verifier is the Swift implementation of
refineid-core's design
([document-verification.md](https://github.com/refineid/refineid-core/blob/main/doc/architecture/document-verification.md));
that document is canonical for the scope, the per-signature judgement
and the failure taxonomy. This file records what the Swift
implementation and the Apple platform decide: the shipped list signers,
the trusted-list store and its cache, the SecTrust path, the report the
screens render, and the tests that pin them.

## Scope

The verifier judges one file: a PDF carrying PAdES signatures, or an
ASiC-E or BDOC container carrying XAdES signatures. A standalone CMS
SignedData file (CAdES, `.p7m`, `.p7s` or `.p7c`) is recognised and
reported unsupported. A CAdES signature inside a container is not
enumerated: only `META-INF/*.xml` signature files become rows, so a
container with no XML signatures reports no signatures even when it
carries `.p7s` entries. Core judges CAdES in containers; the Swift
verifier does not yet. A ZIP archive that is not an ASiC-E or BDOC container, such as
an office document, is reported as carrying no signatures. The
baseline levels and the validation process are core's.

## Where the code lives

| Piece | Code |
|---|---|
| Entry point and report | `CardCore/Sources/CardCore/DocumentVerification.swift` |
| PDF and PAdES reader | `CardCore/Sources/CardCore/DocumentVerification+Pdf.swift` |
| ASiC-E and BDOC reader | `CardCore/Sources/CardCore/AsicVerification*.swift` |
| PDF CMS signature and timestamp verification | `CardCore/Sources/CardCore/CmsSignerVerification*.swift`, `TimestampTokenVerifier.swift` |
| Certificate path | `CardCore/Sources/CardCore/CertificatePath.swift` |
| Anchors and lists | `CardCore/Sources/CardCore/TrustAnchors.swift`, `TrustedLists.swift`, `TrustedList*.swift` |
| List signers | `CardCore/Sources/CardCore/EuListOfTheListsSigners.swift`, `TrustedListSigners/` |
| List reader | `Sources/App/TrustedListReader.swift`, `ShippedSignerTrustedListReader.swift` |
| Card-read path candidates | `CardCore/Sources/CardCore/TrustRootsCache.swift`, `ValidationEvidence.swift` |
| Fetch and cache | `Sources/App/TrustedListStore.swift`, `TrustedListStore+Fetch.swift`, `TrustedListStore+Cache.swift` |
| Verify model and screens | `Sources/App/VerifyDocumentModel.swift`, `VerifyDocumentView.swift`, `VerifyQueuedDocumentsView.swift`, `VerifyTrustedListsSection.swift` |

The Swift verifier keeps core's four borders. The file enters through
`DocumentVerification.verify`; the anchors enter through `TrustAnchors`;
the clock enters as the `now` argument; the evidence the file carries
and the card-read path candidates enter through `ValidationEvidence`. A certificate in the evidence pool
can only extend a path to an anchor; an OCSP response or CRL counts only
once it verifies under the issuer or an authorised responder.

## Anchors

Verification has one anchor source: the EU trusted lists. The software
ships the six certificates the Official Journal publishes as entitled
to sign the EU list of the lists (OJ C, C/2026/1944), in
`CardCore/Sources/CardCore/TrustedListSigners/`; `EuListOfTheListsSigners`
checks each DER file against its pinned SHA-256 fingerprint and leaves
out one that does not match. They are end-entity signing certificates
that no operating-system root store carries, so they bootstrap the
lists and anchor nothing themselves. No CA root is shipped.

`TrustAnchors` is the border. It carries, for each anchor, the
certificate, its role (certificate issuing or time-stamping) and the
periods the trusted list grants; beside them it carries the lists'
fetch time and the earliest `NextUpdate` of the list of the lists
and the national lists. `certificates(for:at:)` returns the anchors
trusted for a role at
an instant, and `isStale(at:)` says whether that earliest next update
has passed. A certificate the document carries, or one this device has
read from a card, is a path candidate in `ValidationEvidence`; it never
becomes an anchor.

### Why no CA root is shipped

The Finnish trusted list names DVV's services by their issuing CA
certificates ("DVV Citizen Certificates - G4E" and "- G4R", "VRK Gov.
CA for Citizen Certificates - G3", the organisational and service CAs),
the certificates a card's own chain starts at. The Spanish list names
Sectigo (Europe) SL's qualified time-stamping service by "Sectigo
Qualified Time Stamping CA R35", the CA that signs its time-stamp
units. A shipped DVV Gov. Root CA G3 or Sectigo Qualified Time Stamping
Root R45 would therefore anchor nothing a list does not, so neither is
shipped.

A fresh install has no anchor and verifies a signature only
after it has fetched the lists once; from then on it works offline from
the cache. The same evidence is recorded in refineid-core's
[`crates/doc-sign/src/trust.rs`](https://github.com/refineid/refineid-core/blob/main/crates/doc-sign/src/trust.rs),
which is the canonical record for the shared policy.

## Trusted lists

`TrustedLists` and `TrustedList` are the Swift implementation of
refineid-core's `trusted_list.rs`. `TrustedLists.read` fetches nothing
itself: the shell gives it the list of the lists and the bytes of the
national lists, and it returns the lists that read plus one cache record
per list. The list of the lists is read under
`EuListOfTheListsSigners.certificates`; each national list is read under
the certificates the list of the lists carries in the pointer to it.
Pointers are followed one level: a national list's own pointers are read
and never fetched. Only pointers that declare the EU member state list
type and the machine-processable media type are followed.

A list is read only when its enveloped XAdES signature verifies. The
`ds:SignedInfo` carries exactly two references; any other count is
refused before anything is computed. The `ds:KeyInfo` certificate the
`SigningCertificate` property names is one of the entitled certificates,
byte for byte, and the signature over `ds:SignedInfo` verifies before
any reference digest is computed. A reference the verifier cannot
recompute, or a digest or signature value that does not match, refuses
the list. The signer certificate's own validity and revocation are not
consulted: issuing a new list deprecates the old one. Core's document
gives the full profile and the status rules.

A service of type `CA/QC` yields certificate-issuing anchors, one of
type `TSA/QTST` time-stamping anchors; one anchor per certificate of its
digital identity. `TrustService.grantedPeriods` derives the periods from
the current status and the whole status history, in time order, and
follows core's full status rules, including the Directive 1999/93/EC
statuses and the 1 July 2016 cut-off. A service no period grants yields
no anchor.

A list past its `NextUpdate` is stale. `TrustedLists.validUntil` is the
earliest next update of the list of the lists and the national lists
that read; `TrustAnchors.isStale(at:)` compares it with the verifier's
clock. Anchors from a stale list still count: a stale list is the last
one its operator published, and un-anchoring every qualified signature
of a territory because a cache aged is a loss no relying party expects.
The anchors carry the fetch time and the earliest next update; the
shell fetches again when they are stale. When that fetch fails, the
trusted-lists section appears with the fetch time and the failure,
because the stored stale lists are why it appears. A closed list
contributes no next update, so it never makes the anchors stale.

## Fetching and caching

`TrustedListStore` is the shell's one store. It is `@MainActor` and
takes its network, cache directory, reader and clock as injected
dependencies.

- `verificationAnchors()` loads the cache and, only when no list has
  been read, fetches. It returns the anchors or a typed
  `RefreshFailure` (`.offline` when the list of the lists could not be
  fetched for want of a connection, `.unavailable` otherwise).
- `refreshIfNeeded()` runs when either Verify screen appears. It fetches
  when nothing is cached, when a cached list is past its `NextUpdate`,
  or when the fetch is older than `maximumAge` (seven days,
  `604_800` seconds).
- `refreshNow()` fetches as the holder asked, from the trusted-lists
  section's refresh button. One refresh runs at a time.

The fetch is a GET of the list of the lists from
`TrustedLists.listOfTheListsLocation`
(`https://ec.europa.eu/tools/lotl/eu-lotl.xml`) and a GET of each
national list the list of the lists names. Both use `SigningNetwork.get`
with `.certificateMaterial`, the app's outbound network policy for
public certificate material: public addresses, two redirects, and a body
cap of `TrustedList.maximumBytes` (16 MiB). Up to four national lists
are fetched at once. The lists travel as GETs of public documents under
the certificate-material endpoint; no other traffic-capable API is
involved. A pointer may name HTTP; that is safe for
the same reason a CRL is: the signature, not the transport, proves the
list. A national list that does not arrive or does not read is carried
in the reading with its territory and reason and yields no anchor; the
lists that read still do. A refresh rewrites the whole cache from the
lists that read: a territory whose list fails this refresh loses its
cached list and its anchors until the list reads again.

The cache is `Application Support/TrustedLists/`: an `index.json` of
records and one `<sha256-of-location>.xml` file per list. A record
carries the location, fetch time, `NextUpdate` and file name; the file
holds the raw bytes. The directory is outside the keychain and excluded
from backups, because the lists are public and fetched again at will.
Every read verifies every list signature again through
`TrustedLists.fromCache`; the bytes on disk are never trusted as a list
without that verification.

A failed fetch keeps the cache: the store publishes the failure and
leaves the anchors it had. A stale list still anchors; when that
refresh fails, the Verify screen shows the fetch time and the failed
refresh. With no cache and no network the screen says no lists are stored
and the device is offline; it never renders a verdict under empty
anchors. A fetch that fails for another reason gives the same refusal,
with the generic no-trusted-lists message.

## The SecTrust path

`CertificatePath.anchored` builds one path per signature under the
anchors granted at the validation time. It creates a basic X.509
policy, sets the anchors as the exclusive anchor set, forbids network
fetch, sets the verification date, and evaluates offline. Name
chaining, signatures, validity, basic constraints, key usage, path
length, name constraints and critical extensions are checked on every
certificate below the anchor.

The Swift path differs from core's in four ways:

- An anchor is handed to SecTrust as a certificate. SecTrust checks the
  anchor's own validity at the validation time, so that time must lie
  inside the anchor certificate's validity as well as inside the period
  the trusted list grants.
- A path ends at the exact anchor certificate. A certificate with the
  anchor's subject name and key but other bytes is not a path of one,
  although RFC 5280's name-and-key anchor model would accept it.
- A CA certificate whose SubjectPublicKeyInfo algorithm is
  `id-RSASSA-PSS` does not chain: the platform loads no such key from a
  certificate.
- SecTrust evaluates one path. Core judges every anchored path and, when
  a compromise revocation names a certificate on one, revokes every path
  that carries the same subject public key. The Swift verifier judges
  the path SecTrust returns; it does not apply core's cross-path
  compromise rule to an alternative anchored path.

An anchor need not be a root: the lists name issuing CAs and
time-stamping units. A certificate byte-identical to an anchor is a
path of one; otherwise the path ends at the anchor certificate that
issued the certificate below it.

`CertificatePath.isFitToSign` refuses a signer that is not an end
entity, whose Key Usage permits certificate or CRL signing, or that
carries a critical extension this verifier does not process.
`CertificatePath.directIssuer` supplies the certificate that directly
issued an unanchored signer, for the report.

## Report and screens

`DocumentVerification.verify` returns a `DocumentReport`, or throws a
typed failure. The report carries every signature in document order,
every PDF document timestamp, and `isValid`, which is true only when a
signature exists, every signature is judged valid, and none is
unsupported. A `SignatureReport` carries the signer's common
name and electronic identifier, the signer certificate, whether the
document is intact, whether the signature verifies, the chain status,
every signature timestamp, every archive timestamp, the archive valid
until date, the baseline level, the validation time, the revocation
state and whether the signature covers the whole document. Coverage
is recorded but affects neither the rows nor `isValid`. Revocation is
judged at the proof of existence; `withLiveRevocation` fills a path
certificate still unavailable with a live answer judged at the time of
the check.

`VerifyDocumentModel` verifies offline under the store's anchors, then
asks live revocation only for path certificates the document left
unavailable. Each verification carries a generation, and a result or
answer from an earlier one is dropped. When no anchors can be read, the
model first checks under `TrustAnchors.empty` whether the document
carries signatures at all, so an unsigned or unreadable document says
that first; a signed one says why no trusted list could be read. It
never presents a verdict from empty anchors.

The iPhone and iPad Verify screen and the Mac verification sheet render
these facts in the cards and rows described in [ios.md](ios.md#verify)
and [macos.md](macos.md#document-verification). The trusted-lists
section appears only when a fetch failed and the stored lists are
missing or stale, with the fetch time or "Not fetched", the failure
text, and the retry button.

### Validation status and wording

ETSI EN 319 102-1 gives the signature validation status three values:
`TOTAL-PASSED`, `TOTAL-FAILED` and `INDETERMINATE` (clause 5.1.3,
Table 5); the two non-passing values carry a reason or sub-indication.
Clause 5.2.9 asks a presentation to show the overall status, the reason
a signature failed, the step that could make an indeterminate result
determinate, the validation policy and the validation time.

The Verify screens deliberately do not show one overall status.
They show the facts that decide one, as rows: "Document intact", "Signature", "Certificate
chain", "Revocation", "Signed at", the archive timestamp when it needs
attention, and "Long-term validity". A row's mark says whether that
check holds; the revocation row shows a bare mark when good, says
"Revoked" when revoked, and reuses "Not checked" when the checks ran
but no usable answer arrived (in the table below it means validation
did not run). A timestamp can say "Unproven", and an unsupported
signature says its
profile is not supported. The person row's mark reflects
`SignatureReport.isValid`, a Boolean over document intactness, the
signature, the chain and a revocation that invalidates. It is not a
fourth standard status, and it does not summarise the timestamps or the
level.

No screen shows one today; when a screen does, it uses these words:

| Shown as | EN 319 102-1 | What it means |
|---|---|---|
| Signature validates | `TOTAL-PASSED` | The format, cryptographic, chain and revocation checks the policy requires passed. |
| Signature does not validate | `TOTAL-FAILED` | A required check failed: the document was altered, the signature does not verify, or the signing certificate was revoked before the proof of existence. |
| Cannot validate signature | `INDETERMINATE` | Validation ran, but the evidence does not establish either result: for example no path to an anchor, or no revocation answer the policy accepts. |
| Not checked | none | Validation did not run. This is not a validation result. |

"Signature validates with concerns" may only be a secondary phrase
above a `TOTAL-PASSED` result, naming a caveat the policy treats as
non-material. It never carries a failure or an indeterminate condition.
"Warning" is not a validation status; EN 319 102-1 uses warnings only as
auxiliary signals, such as a signature over a document that already
carries a failing signature. "Undecided" and "Unknown" are not two
states: "Cannot validate signature" is what validation returned when it
could not decide, and "Not checked" is what the screen says when no
validation ran.

A status belongs to a validation policy and a validation time. It says
what the verifier established under this app's policy, not that the
signature has legal effect. Qualification is a separate fact, and the
verification report does not state it. eIDAS Article 25(1) forbids
denying legal effect solely because a signature is electronic or is not
qualified; Article 32(2) requires the system used for validation
to give the correct result and to let the relying party detect
security-relevant issues.

`SignatureReport.isValid` treats an unavailable revocation answer as
not invalidating. It is therefore not by itself the `TOTAL-PASSED` test:
a summary status must follow the stated policy, including whether
missing revocation evidence makes the result `INDETERMINATE`. The rows
stay visible under any summary, so a caveat is not hidden by a label.

## Tests

| Test | What it pins |
|---|---|
| `EuListOfTheListsSignersTests` | Six certificates; each DER hashes to the Official Journal notice's SHA-256. |
| `TrustedListTests`, `TrustedListTests+Anchoring`, `TrustedListTests+Refusals` | List signatures, pointers, granted periods, bounds, refusals and anchoring. |
| `DocumentVerificationTrustTests` | Chain to an anchor, an unanchored root, timestamp proof, revocation before and after the proof of existence. |
| `DocumentVerificationProfilesTests`, `DocumentVerificationRevisionTests`, `DocumentVerificationRowsTests`, `DocumentVerificationReviewTests` | Profiles, revisions, report rows and review fixtures. |
| `AsicVerificationTests`, `TimestampTokenVerifierTests` | ASiC-E and BDOC containers, XAdES references, timestamps and timestamp tokens. |
| `TrustedListStoreTests` | Cache first, offline, stale and aged refresh, failed fetch keeps the cache, explicit refresh, missing-list messages. |
| `VerifyDocumentModelTests`, `VerifyTrustedListsSectionTests`, `VerifyWordingTests` | Model phases, live revocation, the trusted-lists section and UI wording. |

## STPA

Core's document-verification record names the loss L-6 and the hazard
H-8: a relying party acts on a document as validly signed when it is
not, or rejects one that is; the verifier reports a fact it has not
established, or hides a signature or timestamp it has not judged. The
Swift verifier adds no loss and no hazard.

Control structure: the relying party reads the report the Verify screen
renders. The shell supplies the file, the anchors from
`TrustedListStore`, the clock, the live revocation answers and the
card-read path candidates. The
trusted lists are a trust input: the store fetches them, the reader
verifies them, and their forgery or age reaches every verdict. Feedback
the relying party needs: which facts hold, at which time they were
judged, how fresh the anchors are, and which signatures were not
judged.

Core's record remains the full table. The rows below are the controls
this implementation restates and the ones the Apple shell and list
reader add; the verifier's timestamp and intactness controls are core's
UCA-105/CC-109 and UCA-108/CC-112.

| Id | Controller | Unsafe control action | Hazard | Constraint |
|---|---|---|---|---|
| UCA-106 | Verifier | Omits a signature or document timestamp it could not read. | H-8 | CC-110: an unread signature is an `unsupported` row that blocks `DocumentReport.isValid`; an unread document timestamp is still reported in `documentTimestamps` and decides nothing; every other signature is still judged. |
| UCA-107 | Verifier | Reports revocation good from a live answer while the chain is not verified. | H-8 | CC-111: `withLiveRevocation` returns the report unchanged unless `chainVerified`; a live answer only fills a pending link. |
| UCA-109 | Shell | Renders a verdict from anchors or lists that are stale without saying so. | H-8 | CC-113: `TrustAnchors.fetchedAt` is carried; when a refresh fails, the trusted-lists section shows the fetch time or "Not fetched", and retry. |
| UCA-110 | Verifier | Judges under an anchor outside its granted period. | H-8 | CC-114: `TrustAnchors.certificates(for:at:)` filters by role and granted period at the validation time; `CertificatePath` evaluates at that time. |
| UCA-111 | Shell | Renders a claimed time or an unjudged signer as established. | H-8 | CC-115: `TimestampState` and `ValidationTime` type claims apart from proofs; the UI labels a claimed time "Unproven" and an unsupported row as unsupported. |
| UCA-112 | Trusted-list reader | Takes anchors from a list not signed by an entitled certificate. | H-8 | CC-116: `EuListOfTheListsSigners` ships the six fingerprints; `TrustedList.read` verifies the signature over `ds:SignedInfo` under the entitled certificate before any reference digest; `TrustedLists.fromCache` repeats it for every cached list. |
| UCA-113 | Shell | Renders a verdict from anchors past `NextUpdate` without saying so. | H-8 | CC-117: `TrustAnchors.isStale(at:)`; a failed refresh with stale stored lists brings up the trusted-lists section with the fetch time and the failure. The screen attempts a refresh when it appears; a list that turns stale while it stays open is shown from the next failed refresh. |
| UCA-114 | Trusted-list reader | Anchors a service at a time its status did not grant. | H-8 | CC-118: `TrustService.grantedPeriods` walks the status history; `TrustAnchors` carries the periods. |
| UCA-115 | Trusted-list reader | Follows pointers without bound or reads a list without bound. | H-8 | CC-119: `TrustedLists.read` follows one level; `TrustedList.maximumBytes` caps a list at 16 MiB; pointer, service, history and identity counts are named bounds. |

The Swift shell adds these constraints:

- Every cache read verifies every list signature again, so an edited
  cache file yields no anchor from that list (CC-116).
- A failed fetch leaves the anchors and the cache in place; when no
  current lists are stored, the screen shows the failure and either the
  fetch time or "Not fetched" (CC-113, CC-117).
- With no cache and no network, the screen refuses; it never presents a
  verdict under empty anchors.

Loss scenario: a national list is substituted on the wire for one that
lists an attacker's CA as a qualified certificate service. Without
CC-116 the attacker's CA would anchor every signature it issues; with
it the substituted list is not signed by a pointer certificate, is
reported unreadable, and yields no anchor.

Loss scenario: a cache file is edited on disk to add an attacker's CA.
The next read runs `TrustedLists.fromCache`, the list signature fails,
and no anchor comes from that list.

A cached list is past its `NextUpdate` but still the last one its
operator published. The anchors still count, the screen shows the fetch
time and the failed refresh, and the holder can refresh. A fresh install
with no cache and no network refuses, because there is nothing to
anchor to; the screen says so.

## References

- refineid-core, `doc/architecture/document-verification.md`, the
  canonical shared design.
- refineid-core, `crates/doc-sign/src/trust.rs`, the record of the
  shipped list signers and the reason no CA root is shipped.
- OJ C, C/2026/1944, the Official Journal notice that names the six
  list-of-the-lists signers.
- ETSI TS 119 612, trust lists; ETSI EN 319 102-1, validation;
  EN 319 122-1, CAdES; EN 319 132-1, XAdES; EN 319 142-1 and 142-2,
  PAdES; EN 319 162-1, ASiC.
- RFC 5280, certificate paths; RFC 3161, time-stamp protocol;
  RFC 6960, OCSP.
- ISO 32000-1, the PDF format.
- [references.md](../references.md), the index of which source governs
  what.
