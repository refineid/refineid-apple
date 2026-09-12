# Export compliance

What RefineID declares to Apple about its cryptography, what it actually
implements, and the exact text submitted. Written so a later submission
says the same thing as this one, and so a reviewer asking "why did you
answer that" gets an answer rather than a shrug.

The declaration itself is recorded in `Documentation/decisions.md`
("Export compliance is declared as non-exempt"). This file is the
supporting detail.

## What is declared

`Config/RefineID-Info.plist` (macOS) and
`Config/RefineID-iOS-Info.plist` (iOS) both carry:

    ITSAppUsesNonExemptEncryption = false

until the ANSSI attestation exists, and then `true` together with the
`ITSEncryptionExportComplianceCode` Apple issues against the filed
documentation.

The key does not record the EAR analysis; it records whether Apple
holds export compliance documentation for the app. Apple's definition
(Information Property List > ITSAppUsesNonExemptEncryption) makes
`false` the statement that the app "only uses forms of encryption
that are exempt from export compliance documentation requirements",
and both halves of this app's position were verified against App Store
Connect itself on 2026-08-07:

  - Creating App Encryption Documentation is refused: "Cannot create
    appEncryptionDeclarations unless either
    containsProprietaryCryptography is True or
    containsThirdPartyCryptography and availableOnFrenchStore are both
    True". Standard published algorithms outside the French store are
    not a document Apple accepts, so no filing and no code can exist
    today.
  - Uploading with `true` and no code is rejected during upload with
    error 90592, "Invalid Export Compliance Code" -- at upload, not at
    submission as an earlier revision of this file said.

So `false` is the accurate answer for now, and it is a statement about
documentation, not the EAR claim the next section weighs. The EAR
obligation that accompanies it is the year-end self-classification
report to BIS, which Apple's guidance names for exactly this case.

## App Purpose, as submitted

App Store Connect asks for this in step 1 of App Encryption
Documentation, capped at 300 characters. Submitted verbatim:

> RefineID is middleware for the Finnish national identity card. It
> reads the card over NFC or a smart-card reader, opens a PACE secure
> channel with the card access number, and publishes the card's
> certificate and key to the system keychain so Safari and other apps
> can sign in with the card.

290 characters. It names the three things a reviewer needs: what the app
is for, how it reaches the card, and what it hands to the system.

## What the app actually implements

This is the part that decides the answer. RefineID does not merely call
the platform's cryptography -- it implements the card-side protocols in
Swift, in `CardCore`, because no Apple framework speaks them:

| Primitive | Where | Why it exists |
|---|---|---|
| ECDH on brainpoolP384r1 | `BrainpoolP384r1Values`, `PaceEstablishment` | The PACE key agreement. The curve is fixed by the card. |
| AES-256 CBC | `SecureMessagingChannel` | Confidentiality of every APDU after PACE. |
| AES-CMAC | `AesCmacValues`, `SecureMessagingChannel` | Integrity of every APDU after PACE. |
| SHA-256 | `PaceKeyDerivation`, via CryptoKit | Deriving the PACE session keys. |
| SHA-224, SHA-256, SHA-384, SHA-512 | `SigningHash`, `SigningAlgorithmResolver` | Digests for the signatures the card makes; which one is the calling service's choice. |
| ECDSA P-384 | `EcdsaSignature` | Verifying what the card signed; the card holds the private key. |
| RSA-2048/3072 PKCS#1 v1.5 | `CardKeyProfile`, `SignRequest`, `QualifiedDocumentCms`, `RsaPkcs1Sha256EncodedMessage` | Authentication and SHA-384 qualified document signatures for RSA card generations. |
| RSA-2048/3072 PSS | `SigningAlgorithmResolver` | The shape TLS 1.3 asks for from an RSA card; the card computes it. |

The suite PACE runs is
`id-PACE-ECDH-GM-AES-CBC-CMAC-256` over brainpoolP384r1, which the card
advertises in EF.CardAccess and which this build sends without
negotiating (`Documentation/decisions.md`, "The PACE suite stays fixed").

None of it is proprietary. Every algorithm is published: PACE and secure
messaging in ICAO 9303-11 and BSI TR-03110, brainpoolP384r1 in RFC 5639,
AES in FIPS 197, CMAC in NIST SP 800-38B, ECDSA in FIPS 186, RSA PKCS#1
in RFC 8017.

## Why non-exempt rather than exempt

The exemption most nearly available is the one for cryptography limited
to authentication. It was considered and not taken.

PACE does authenticate -- it proves the terminal knows the card access
number and that the card is present -- but what it leaves behind is a
confidentiality channel: every APDU afterwards is AES-encrypted, and
that includes the certificate and the card serial read across it. An
exemption argued on "authentication only" would have to describe that
channel as incidental, which it is not; it is the reason the card
answers at all on the contactless interface.

There is a plainer reason too, and it settles the question before the
argument starts. The point of filing is the attestation, and the
attestation is what App Store Connect wants. An exemption produces no
attestation: a ruling that no formality is required leaves nothing to
hand Apple. So the exemption is not a prize to be argued for -- winning
it would be the worst outcome available. The declaration claims what the
means does and asks the agency to acknowledge it; it does not invite the
agency to consider whether the claim was necessary.

Declaring non-exempt costs a self-classification or CCATS filing and a
French declaration. The French one is not annual: it is made once for
the means, and again only when what was declared changes. Declaring exempt on a judgement call costs
credibility, in a product whose entire subject is identity. The cost was
accepted deliberately rather than by default.

## The publicly available source route

`RefineID-Apple` is a public repository, so the source-code question is
separate from the App Store binary question. The current EAR provision
to check for publicly available encryption source code is 15 CFR
742.15(b), not the old 740.13(e) text. The 2026-08-03 email that cited
740.13(e) is kept as an audit trail only; do not rely on it as the
operative notice.

Do not re-send mechanically. 742.15(b) is framed around publicly
available encryption source code, and RefineID implements published
standard algorithms rather than non-standard cryptography. Confirm
whether any source-code notice is actually owed before sending another
one. If one is sent, it should cite the current provision and keep the
scope to the public source repository, for example:

    Subject: TSU notification - publicly available encryption source code

    Under 15 CFR 742.15(b), notice is given that the following publicly
    available encryption source code is available at no cost:

    RefineID - Finnish identity card middleware for Apple platforms
    https://github.com/refineid/refineid-apple

    The software implements PACE (ICAO 9303-11, BSI TR-03110) with ECDH on
    brainpoolP384r1, AES-256 CBC and AES-CMAC secure messaging, and ECDSA
    and RSA PKCS#1 v1.5 signature verification. All algorithms are published
    by international standard bodies; none are proprietary.

    Petri Koistinen
    RefineID
    Finland
    petri.koistinen@refineid.fi

What this does not settle, and what a qualified answer is worth getting
before relying on it: whether the exception reaches the App Store
binary, or only the source in the repository. If only the source, the
binary falls back to the mass-market route -- an Encryption
Registration Number, which is a free SNAP-R submission usually answered
in about a business day, not a CCATS. The French declaration is a
separate regime either way.

## France

The app is to be available in France, so the French declaration applies:
supplying a cryptographic means that provides confidentiality requires a
declaration to ANSSI, and PACE's channel is exactly that. The technical
dossier is `Documentation/anssi-declaration.md`, in French.

Excluding France was the alternative and was considered: it would have
removed this step entirely and shipped sooner. It was not taken. A
Finnish cardholder living in France has a French App Store account, and
an identity product that quietly does not exist where its holder lives
is a worse answer than a filing.

That dossier is a document for a regulator to read, not a page of our
notes, so it carries no repository cross-references and no task list.
Everything about *doing* the filing lives here instead. The exact
pipeline that produced the filed artifact:

    pandoc Documentation/anssi-declaration.md --pdf-engine=typst \
      --pdf-engine-opt=--pdf-standard=a-2b \
      -V papersize=a4 -M lang=fr-FR \
      -M "title=RefineID — déclaration d'un moyen de cryptologie" \
      -o "RefineID - ANSSI declaration dossier.pdf"

    refineid card sign-document --format pades \
      --in  "RefineID - ANSSI declaration dossier.pdf" \
      --out "RefineID - ANSSI declaration dossier - signed.pdf" \
      --reason "Declaration d'un moyen de cryptologie -- decret 2007-663" \
      --location "Helsinki, Finlande" \
      --timestamp eu-qualified \
      --archive

    curl -s -X POST https://dvv.fineid.fi/api/v1/validate \
      -F locale=en -F includeDetails=true \
      -F "file=@RefineID - ANSSI declaration dossier - signed.pdf"

`eu-qualified` is the three authorities below, asked in that order. It
is a name rather than a default because a signing tool that reaches
foreign servers unasked has made that choice for you, and because a
name is safer to type than three URLs: a mistyped URL is now survivable
and quietly costs an authority, a mistyped name stops before the card
is touched.

Three qualified authorities in two countries, so the proven time
survives any one of them losing its standing. A refusal is survivable:
each is asked in turn, one that is down or rate limiting is named on
stderr and skipped, and only silence from all three stops the signing.

The order matters twice. It decides who carries the archive timestamp,
which is a single token rather than a set -- the first to answer wins
-- and it is the order to reach for anywhere else. Measured 2026-08-03:
Sectigo signs RSA-4096 under a unit whose certificate is signed with
SHA-384 and runs to 2034, longest of the three, and republishes
revocation weekly. Greece is RSA-4096 to 2030 under a certificate
minted this year, with revocation minted per request. ACCV is RSA-4096
to 2029 and last on the evidence rather than on the token: its
responder and its list both run a 180-day cycle, so what a signature
freezes from it can be weeks old before the signature exists.

Both Spain and Greece grant the issuing CA rather than individual
units, so a rotation cannot silently cost the qualification. That is
worth having: a list that names units instead opens a window where the
endpoint answers with a unit its own list does not name, and the token
verifies, looks right, and is not qualified. Worth re-checking on the
day rather than assumed -- not whether the endpoints answer, but
whether the unit answering is still named as granted.

### Two qualified authorities deliberately not used

Both answer, both are granted, and neither is a bad service. They are
absent for reasons that have nothing to do with the tokens.

Belgium (`http://tsa.belgium.be/connect`) is run by the federal
government for the Belgian eID. A Finnish card's signature is not what
it is offered for, and using a state's service outside the public it
was provided for is not a thing to do in a filing to another state's
regulator. It also rate limits hard enough to be unreliable for anyone
outside that public, which is consistent with the same reading.

Izenpe (`http://tsa.izenpe.com`) is qualified and its tokens validate
as QTSA. But Spain registers it at the unit rather than at the CA, so
`ROOT CA QC IZENPE` -- which signs its revocation lists -- is not a
trust anchor anywhere a validator looks. Embedding one of those lists
earns `INDETERMINATE / NO_CERTIFICATE_CHAIN_FOUND` in a detailed
report, against evidence whose signature is otherwise intact and whose
cryptography passes. Nothing is wrong with the token; the file simply
reads better without a line that invites a question with no good
answer.

RFC 3161 sends a digest rather than the document. RefineID accepts a
reply only after checking its message-imprint algorithm, digest, nonce,
CMS signature, timestamp-signing certificate chain, and the signer's
identity against the EU trusted lists. Some qualified authorities still
publish HTTP timestamp or revocation endpoints in those lists, so the
cryptographic checks cannot be delegated to the transport.

`--archive` is what makes it PAdES-B-LTA, the top of the ETSI ladder.
The validator must answer QESig, PAdES-BASELINE-LTA, TOTAL_PASSED;
anything else means stop and look.

The language and title are not decoration. Typst tags its PDF output,
so the file already carries a structure tree; without `lang` the
document declared itself `en-US` and a screen reader would have read it
in an English voice, and without `title` the viewer showed a heading it
had picked up by accident. With both set the document announces
`fr-FR`, and the title bar shows the document rather than the filename.

A4, because the reader is French and Letter is a North American size;
pandoc's default is Letter, so the flag is not optional. The French
render is exactly three pages, numbered `Page X sur 3`, including the
first, so the dossier's completeness is visible before its signature is
checked. The text also carries the narrow no-break space French
typography puts before `: ; ! ?` -- it is in the markdown, not applied
at render time, so it survives whatever renders the file next.

Sign in the Helsinki working day, not late at night.

The attestation carries "Fait à Helsinki, le ..." and every timestamp in
the file is UTC. Between midnight and 03:00 EEST those disagree: a
document made on the 4th in Helsinki is signed at 21:xx UTC on the 3rd,
and a reader comparing the attestation against a validation report sees
two dates. Render with the date you will sign on, sign the same day
while Helsinki and UTC agree, and the question never arises.

Sign once, when the document is finished and about to be sent.

While the text is still being edited, render and read -- rendering costs
nothing and needs neither the card nor the network. Signing a draft
attests a document that will not be the one filed, spends a card
operation and a PIN verification on it, and asks three timestamp
authorities for tokens over something disposable. That last part has a
cost you can measure: tsa.belgium.be began answering HTTP 429 after
enough draft signings in one day.

It also destroys evidence. A signed PDF cannot be reproduced -- a fresh
signature has a different instant, different tokens, different
revocation answers -- so every re-sign discards an artifact that cannot
be recovered. That is harmless for a draft and unrecoverable if it was
the copy that went to ANSSI.

Verifying the signer is a separate job from signing the dossier: sign a
throwaway file for that.

The markdown is the source of truth; the PDF is a rendering. Regenerate
rather than editing the PDF, or the two drift and the filed one wins.
Any edit to the markdown means render, sign and validate again -- the
signature covers the bytes, not the intent.

Before filing, have the French read by somebody who files these. It is
written to be accurate rather than idiomatic, and a regulator's form is
a poor place to find a translation error.

The dossier gives 1 November 2026 as the date placed on the market, and
the signature block keeps its own date. The gap is deliberate.

One month or two depends on what is declared. Article 4 sets one month;
article 8 doubles it "lorsque la déclaration concerne l'exportation de
moyens de cryptologie vers des Etats non membres de la Communaute
europeenne". The declaration no longer concerns that -- see below -- so
one month is the applicable delay and the November date leaves a wide
margin. Two months was assumed while the scope still claimed an export
leg, and moving the date is the one change from that period worth
keeping: there is no hurry toward the French market, and a date with
air in it survives a filing that slips.

### What is actually declared, and what is not

Article 30 governs French operations. *Fourniture* is supply into the
French market and is what a supplier established anywhere owes a
declaration for -- ANSSI is explicit that the obligation falls on the
supplier or first importer regardless of where they are established.
*Exportation* means export **from France** to a third state, and
*transfert vers un Etat membre* means transfer **from France** onward.
A supplier in Helsinki performs neither.

So the declared operations are fourniture in France and transfert
depuis un Etat membre, both under chapter II. No chapter III request accompanies it, and category 3 -- which matters
only for the two operations article 30 IV reserves to authorisation --
is declared without being leaned on.

The dossier does not say those two operations are not the declarant's.
It said so for a while. A denial invites the question it answers: a
reader who was not wondering whether this supplier exports cryptology
from France is wondering once the sentence raises it, and the title
already makes the positive claim -- fourniture, and transfert depuis un
Etat membre. Scope is better set by what is claimed than by what is
disclaimed.

An earlier draft claimed the export leg. It should not have: it asserted
a scope that only existed if category 3 were already granted, in a
document that says in the same breath that it is not.

The clock runs from the date the dossier is sent, not from the date it
is signed.

Parentheses stay out of the filename. They are legal on every platform
and a nuisance on most: a shell needs them quoted, a URL turns them
into %28 and %29, and a mail client or an upload form is free to mangle
them on the way. The file is going to be attached to an email, saved by
somebody else, and very likely re-uploaded to a validator, so it is
named with a dash and nothing that needs escaping.

### Where it goes

Checked against ANSSI rather than recalled. The dossier is not filed on
its own: it is the technical documentation attached to ANSSI's own form.

1. The declaration is `Documentation/anssi-declaration.md`, rendered and
   signed. It is drawn up according to annexe I: sections A to F in
   ANSSI's order, under ANSSI's own headings, carrying the attestation
   from section F of the form and the box-two statement from its first
   page.

   ANSSI's annexe I is a template -- a dynamic XFA PDF that only Adobe
   Reader can fill, and that carries no AcroForm fields, so no other
   tool can put a value in it. Filling a template is how you obtain a
   document; the document is what the decree asks for, and this one has
   the same content in the same order.

   The template is at
   https://cyber.gouv.fr/documents/330/crypto_declaration-demande_autorisation_operations_annexe1_v2.pdf
   if it is ever wanted. Do not take annexe 2 instead: it is titled
   *Déclaration de fourniture d'une prestation de cryptologie*, and a
   prestation is a service, not a moyen.

2. Render and sign with `--timestamp eu-qualified --archive`, as
   above. Nothing is printed and nothing is scanned: a
   qualified electronic signature has the legal effect of a handwritten
   one under Article 25(2) of Regulation (EU) No 910/2014, and the
   attestation requires the declaration to be "datée et signée", not
   inked.
3. Email `controle@ssi.gouv.fr`, subject `[formalités] RefineID – RefineID`,
   attaching the signed declaration. The covering text is in
   `Documentation/anssi-submission-email.txt`.

   The validation address is already in the PDF. If ANSSI wants their
   own template back instead, they will say so, and that answer is worth
   keeping.

The form's own sections are A declarant, B the means, C category 3,
D renewal of a transfer or export authorisation, E documents attached,
F attestation. D applies only where a transfer or export authorisation
was granted before, so it is out of scope for a first declaration.

By post instead, if preferred:

    Secretariat general de la defense et de la securite nationale
    ANSSI / SDE / PSS / Bureau Controles Reglementaires
    51, boulevard de La Tour-Maubourg
    75700 PARIS 07 SP
    France

What comes back is an *attestation de déclaration*. That attestation is
what proves the obligation was met and what App Store Connect wants at
step 3. Ask for the *grand public* classification at declaration time rather
than afterwards; ANSSI rules on it within two months of the date of
receipt shown on the attestation. Until that ruling arrives the
classification is requested, not held: do not lean on category 3 for
exports outside the Union in the meantime, and treat the declaration
timetable as the one that applies.

A real one is public, and worth reading before the waiting starts:
https://www.debian.org/legal/debian-lenny-crypto-attestation-export.pdf
-- Debian 5.0 (Lenny), n° 143 ANSSI/SR, 20 January 2011, the declaration
registered as 1101027 (year, month, sequence). Premier ministre / SGDSN
letterhead, from the directeur général, signed by the chargé de mission
responsable des contrôles de la cryptologie.

Its Objet is *Classement d'un moyen de cryptologie*, not *attestation*.
The act ANSSI performs is the classification; the letter attests it.
Section C is therefore the section that produces the document App Store
Connect wants, and the rest of the dossier is there to support it. The
consequence follows in the next sentence -- transfer within the Union
and export to a third country may be carried out freely -- and the
sentence after that disclaims any judgement of quality or any
recommendation.

Two things it settles that are otherwise worth worrying about. It is
addressed to a natural person, so an individual declarant with no legal
entity behind him is unremarkable. And Debian is source-available and
rebuildable by anyone, which is the strongest case anyone could make
against "the user cannot easily modify the cryptographic
functionality" -- and it was classified category 3 regardless. The
criterion is about the means as supplied, not about whether a fork
could exist, so the public repository named in section C is not a
liability there.

## What is still needed

1. ~~The ANSSI declaration filed~~ -- sent 2026-08-07 by email to
   controle@ssi.gouv.fr, signed the same day the attestation is dated.
   Receipt confirmed by the Bureau des controles reglementaires the
   same day, stamped 14:33:49. The attestation is what remains, due
   within one month of receipt -- the two-month extension applies only
   to prestations or export outside the Union, neither of which is
   declared. Silence works too: after the month, the declared
   operations may proceed freely and an attestation confirming the
   obligation was met can be requested. Either path produces the
   document for step 2 by early September 2026.
2. That attestation attached to App Encryption Documentation in App
   Store Connect.
3. The code Apple issues in return, added to both
   `Config/RefineID-Info.plist` and `Config/RefineID-iOS-Info.plist`
   as `ITSEncryptionExportComplianceCode`, with
   `ITSAppUsesNonExemptEncryption` flipped to `true` in both files in
   the same commit.
4. The year-end self-classification report to BIS for the exempt
   period, unless the ANSSI-backed filing lands first and replaces it.

Until step 3 the app does not go to France: the French App Store
territory stays off, and no TestFlight tester is in France. TestFlight
and App Store distribution everywhere else proceed on the exempt
declaration.
