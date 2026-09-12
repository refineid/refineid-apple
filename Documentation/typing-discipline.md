# Typing discipline (Swift)

RefineID uses Swift's type system as a security control, following the
discipline proven in the Rust reference implementation. The goal is not
"more types" for their own sake; the goal is to make invalid protocol
states and trust transitions unrepresentable where that is practical.

The useful question for every new type is:

```text
What mistake does this type make impossible?
```

If the answer is "none", do not add the type. If the answer is "passing a
value from the wrong role, origin, trust state, or wire shape", add the
type and make the compiler enforce it.

## Core rule

External data is parsed once at the boundary, then carried as a domain
type. Downstream code takes the domain type, not the raw bytes that
happened to produce it.

Bad shape:

```swift
func validateRetryCounter(_ byte: UInt8) -> Bool
func admitToCache(counter: UInt8)
```

Good shape (in tree today):

```swift
public struct RetryCount {
  public init?(attemptsRemaining: UInt8)  // refuses implausible values
}

func evaluate(probeOutcome: RetryProbeOutcome) -> RetryFloorVerdict
```

The second form gives later code compile-time evidence that validation
happened. The first form only gives later code a byte and a hope.

## The decision test: when does a type pay?

A type pays for itself if *any one* axis fires. If none fires, the type is
ceremony.

1. **Lookalikes.** Is there a different value with the same representation
   that could be swapped at this site or any caller's site? PIN1 and PIN2
   are both short digit strings - the type distinction is what stops the
   swap.
2. **Invariants.** Does the type carry a promise the caller would
   otherwise re-validate or re-document? `RetryCount` says "plausible,
   checked at construction"; code taking `UInt8` re-checks or trusts a
   comment.
3. **Cross-scope travel.** Does the value flow across many functions,
   modules, or actors? Each crossing is a place meaning can get muddled.
4. **Vocabulary collision.** Does the function name commit to a domain
   term the types elide? `readSerial() -> Data` promises "serial" in the
   name while the types say "bytes"; an honest signature beats a comment.

The test runs both ways: name the firing axis when adding a type, and
check no axis is silently load-bearing when removing one.

**Banned: the pass-through wrapper.** A type whose initializer accepts any
value of the base representation unchecked is a costume, not a gate. Every
refined type validates in its initializer or it does not exist.

## Swift rules, mechanically enforced

Enforcement is `Scripts/lint.sh` (pre-commit and pre-push). Run that
script. `swiftlint lint --enable-all-rules` and SwiftLint `--format` are
not the gate: the first ignores the carve register, the second fights
swift-format. swift-format owns layout, SwiftLint (strict, all rules
minus the justified carve register in `.swiftlint.yml`) owns defects,
and two custom rules encode this document:

- **`raw_byte_array_in_api`** - no `func`/`init` carries a raw `[UInt8]`
  across an API boundary. `Data`/`String` are too broadly legitimate to
  ban; the raw byte bag is not. The only sanctioned raw boundary is a
  domain type's own validating initializer / byte accessor, registered in
  the rule's exception list.
- **`unexplained_hex`** - every protocol value has a meaningful named
  definition (release plan section 4.4). No unexplained hex literal in
  production or test source. Wire fixtures live in dedicated,
  provenance-marked test-vector files.

Suppression comments (`swiftlint:disable`, `swift-format-ignore`) are
locked to `Scripts/lint-suppression-register.json`. Adding or removing
one without editing that register fails the gate.
`swiftlint:disable all` and `swift-format-ignore-file` are errors.

Compiler settings are part of the same gate: Swift 6 strict concurrency,
warnings as errors, and the static analyzer are on in every configuration.

## PIN secrecy in types

Credential values get the strictest treatment the language allows:

- A PIN type is never `Codable`, never `CustomStringConvertible` with its
  value, never `Sendable`-by-copy into logs; its description redacts.
- One-operation PIN ownership uses a non-copyable type (`~Copyable`) that
  is consumed exactly once; the compiler, not review, enforces
  at-most-once handoff to the card command.
- No PIN, PUK, serial, certificate, or APDU payload reaches a formatting
  or logging API. Data is classified before it reaches one.
- PIN1 enters reusable token memory only after the card accepts it. That
  memory is bound to the complete card serial, zeroizing, cleared on the
  first confirmed rejection, and gone when the token is. PIN2 and PUK
  never enter it.

## Unknown data stays unknown

Unknown enum values and malformed input remain representable as typed
errors. No `default:` case converts unknown card data into a valid known
state; parsers construct trusted domain values once or fail with a typed
error naming what was wrong.

## FINEID invariants to encode

These distinctions are security relevant and belong in types, not
comments:

- PIN role: PIN1, PIN2, PUK.
- Certificate purpose: authentication, non-repudiation signing, issuer
  chain roles.
- Certificate trust state: raw, parsed, path-validated, purpose-bound.
- Card model/profile and contact/contactless transport.
- APDU target identifiers: AID, SFI, FID, key reference.
- Protocol status: status words and retry counters.
- Token serial: the complete long hardware serial, a distinct type from
  any display string (the short visual serial is never an identity).
- Time role: signing time, validation time, certificate validity time.

When a review asks "can X be confused with Y?", the target answer is
"no, the types differ."

## Hardware evidence

No local experiment or unrecorded successful card operation is completion
evidence (TASKS.md preamble). A task involving card behavior is checked
only when the repository records the evidence: commands, environment,
retry state before and after, and what was deliberately not claimed.
Release tests never intentionally risk a card's last attempt.

## Review checklist

For every function signature changed or added:

- Does each parameter name a domain role, provenance, or trust state?
- Could two same-representation values be accidentally swapped?
- Is parsing done once at the external boundary?
- Does an API accept raw `[UInt8]`, or a `Data`/`String` where a domain
  type exists?
- Is a struct only a bag of unvalidated primitives?
- Would changing a protocol state order cause a compile error?

For every "yes" to a risk question, add or improve a type.

Prefer compile errors to review discipline. Reviewers get tired. The
compiler runs the same checks every time.
