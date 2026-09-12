# Annotated references

Companion to [`references.bib`](references.bib). The `.bib` file is the
machine-parseable citation list; this file explains what each entry is
cited *for*, and what it does **not** prove.

Three kinds of source appear here, and they carry very different weight:

- **Normative specifications** decide behaviour. When the code and a
  specification disagree, the code is wrong. `AGENTS.md` puts it as
  "verify from specifications, don't wild guess" — this file is the
  index that makes that possible.
- **Apple's platform documentation** is normative in the same sense, but
  with a caveat worth stating: it describes intent, and CryptoTokenKit's
  observed behaviour has not always matched it. `AGENTS.md` is explicit
  that an "impossible/blocked" claim needs exchange-level evidence from
  a clean-slate repro — the documentation alone is not that evidence,
  in either direction.
- **Engineering literature** informs design. It never decides anything
  on its own, and citing it is not an argument from authority.

## How to use this file

Cite by BibTeX key, e.g. `[saltzer1975protection](Documentation/references.md#saltzer1975protection)`.
Grep `references.bib` for `@saltzer1975protection` to recover the
bibliographic data, and this file for the same anchor to recover the
interpretation. A `###` heading here is always a BibTeX key; `####`
headings are only grouping, so the anchors stay machine-checkable.

Keys for the card and PKI documents match the Unix tree's, so a citation
means the same thing in either repository.

## Citation hygiene rules

1. **Every citation answers three questions:** what it supports, what
   it does NOT prove, and what its `source_quality` tag means.
2. **`source_quality` is honest, not aspirational.** A blog post is
   `industry-published`, not `peer-reviewed`.
3. **Stale-citation guard.** If `last_verified` is more than twelve
   months old, re-check the URL and the claim before reusing the entry.
4. **Counter-evidence is required for non-trivial decisions.** Four
   sources that agree and none that challenge means the bibliography is
   an echo chamber, not the literature. Say so — see
   [§ evidence we do not have](#evidence-we-do-not-have).
5. **Normative beats persuasive.** Never cite a paper for a claim a
   specification settles.
6. **Observed beats documented, when they conflict.** Record the
   exchange that proved it, and cite the observation as `observation`
   rather than dressing it as specification.

## Normative specifications

Counts are how often each is cited across this tree.

#### The card

- **FINEID S1** (`fineid_specifications`, 44 citations) — the electronic
  ID application. **S4-1** (20) and **S4-2** (22) are the current card
  model profiles; where behaviour differs between models, these say why.
- **ISO/IEC 7816-4** (`iso7816_4`) — APDU structure and security
  architecture. FINEID is a profile on top of it; when S1 is silent,
  7816-4 is the fallback rather than invention.
- **BSI TR-03110** (`bsi_tr03110`, 12) — PACE and the secure messaging
  that follows, which is how the contactless interface opens.
- **ICAO Doc 9303** (`icao9303`, 10) — machine-readable travel
  documents; Part 11 carries the security mechanisms.

#### Vendor card behavior

### thales_multiapp_v5_security_target

- **Supports:** the MultiApp v5.0.A FIA_AFL.1/PACE rule. One failed
  MRZ/CAN authentication exponentially increases the delay before a
  new attempt; the CAN refinement defines a presentation-count
  parameter in the range 0 to 255 and an increasing wait before the
  card sends its PACE response.
- **Does NOT prove:** the numeric delay schedule, counter persistence,
  recovery rule, or that every interrupted exchange increments it. A
  slow exchange still needs a command-level trace before it is assigned
  to this defense.
- **Source quality:** industry-published vendor security target,
  evaluated under Common Criteria. It describes product behavior but
  leaves recovery parameters undisclosed.

#### Certificates, revocation, signatures

- **RFC 5280** (`rfc5280`, 43) — X.509 certificate and CRL profile.
- **RFC 3161** (`rfc3161`, 33) — Time-Stamp Protocol.
- **RFC 6960** (`rfc6960`, 15) — OCSP.
- **RFC 5652** (`rfc5652`, 10) — Cryptographic Message Syntax.
- **ETSI EN 319 162** and siblings (`etsi_aades`) — ASiC and the AdES
  format family. **eIDAS** (`eidas910_2014`) — what "qualified" means in
  law; cite it for the definition, never as proof that an
  implementation achieves it.

#### The interface

- **PKCS#11 v2.40** (`pkcs11_v240`) and **v3.2** (`pkcs11_v32`) — the
  bridge publishes 3.2, 3.0 and legacy 2.40 interfaces. The 2.40
  function list reports 2.40 whatever the newer interfaces say, because
  the specification fixes that field.

#### Apple platform

- **CryptoTokenKit** (`apple_cryptotokenkit`, 107 mentions) — the token
  extension and the keychain token items. The bridge never touches the
  card: identities come from the keychain and signatures from
  `SecKeyCreateSignature`, so the system token daemon owns all card
  communication and PIN handling.
- **Security.framework** (`apple_security_framework`, 20) —
  `SecKeyCreateSignature`, `SecItemCopyMatching`, and the shared
  keychain access group.
- **CoreNFC** (`apple_corenfc`, 26) — the iOS contactless path and its
  platform limits on APDU exchange.

## Engineering literature

### saltzer1975protection

- **Supports:** least privilege, and the separation of privilege that
  follows from it. The reason one binary is installed under two names
  with disjoint profiles: the default name exposes only identities
  without the contentCommitment key usage, and the signing name exposes
  only the contentCommitment ones. A qualified signing key is legally
  weighty and does not belong to every process that loads a PKCS#11
  module, nor to an ssh-agent's PIN cache. The profile follows the file
  name it was loaded under, so the choice is always explicit in the
  consumer's configuration rather than implicit in a default.
- **Also supports:** the protected authentication path. PIN entry
  through the system dialog rather than through the consumer is a
  trusted-path argument, which this paper is the origin of.
- **Does NOT prove:** that two profiles is the right number, or that
  file-name selection is the right mechanism. The principle argues for
  separation; the shape is a design choice.
- **Source quality:** peer-reviewed (Proceedings of the IEEE 1975).
  Foundational security literature.

### parnas1972decomposing

- **Supports:** modules defined by the decisions they hide. The bridge
  hides "how a signature is obtained" behind CryptoTokenKit, which is
  why it can be true that it never touches the card.
- **Does NOT prove:** any specific boundary. The paper is a criterion,
  not a recipe.
- **Source quality:** peer-reviewed (CACM 1972).

### bainbridge1983ironies

- **Supports:** automation that changes behaviour without saying so
  leaves the operator confidently wrong. Applies wherever a fallback
  would be invisible — a weaker signature, a silently different key, a
  PIN prompt that came from somewhere other than the system.
- **Does NOT prove:** that failing is always right. Where a fallback is
  visible and reversible, degrading can be kinder than refusing.
- **Source quality:** peer-reviewed (Automatica 1983).

### norman1988design

- **Supports:** affordances and signifiers. In an app where the
  expensive mistake — a spent PIN retry, a signature with the wrong key
  — is not undoable, the card's state has to be legible before the PIN
  is asked for, not after it fails.
- **Does NOT prove:** the form those cues should take.
- **Source quality:** industry-published (textbook, foundational HCI).

## Evidence we do not have

Listing what cannot be cited is part of avoiding echo-chamber
reasoning. Add to this section whenever a decision rests on judgement
rather than evidence.

### On CryptoTokenKit behaviour

- **No specification** covers several behaviours this tree depends on;
  Apple's documentation describes intent and is in places thinner than
  the implementation. Where behaviour was established by experiment, the
  citation is the recorded exchange, not the documentation, and it is
  `observation` rather than `normative`.
- Consequently, an upgrade of macOS or iOS can invalidate an
  observation in a way it cannot invalidate a specification. Treat
  observations as perishable.

### On the two-profile split

- **No study** shows that consumers configure PKCS#11 modules correctly
  often enough for a name-selected profile to be safer in practice than
  a single module with per-key policy. The argument is least privilege
  plus the explicitness of a path in a config file, not measurement.

## Formal application-flow specification and model-based testing

### w3c_scxml_2015

**W3C, State Chart XML (SCXML): State Machine Notation for Control Abstraction 1.0**

The canonical card-setup grammar uses SCXML's standard representation of explicit states, events, targets, and an initial state. A transition omitted from a state is treated by RefineID as a rejected event rather than an implicit self-transition.

- Supports: the machine-readable syntax and execution vocabulary used by `card-setup-state-machine.scxml`.
- Does NOT prove: that RefineID's chosen product states or card-policy decisions are correct; those remain project requirements verified by model and UI tests.
- Source quality: normative.

### harel_statecharts_1987

**Harel, Statecharts: A Visual Formalism for Complex Systems**

Harel's statechart work provides the formal engineering basis for representing reactive behavior as explicit states and event-driven transitions instead of timing-dependent UI branches.

- Supports: the explicit event/state modeling approach and the separation of behavior from rendering.
- Does NOT prove: protocol correctness, NFC reliability, or any RefineID-specific transition.
- Source quality: peer-reviewed.

### utting_legeard_model_based_testing_2007

**Utting and Legeard, Practical Model-Based Testing**

The model tests apply model-based testing principles by treating the transition relation as an executable oracle, enumerating the finite State x Event space, and checking implementation parity, rejection behavior, reachability, and routing invariants.

- Supports: deriving systematic tests from a behavioral model and checking implementation conformance against that model.
- Does NOT prove: complete correctness of platform frameworks, card firmware, or UI rendering outside the modeled scenarios.
- Source quality: industry-published.
