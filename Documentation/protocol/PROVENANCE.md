# Vendored RAPP protocol documents

`rapp-v26.9.13.md` and `rapp-state-machine-v26.9.13.yaml` are copied
verbatim from the RefineID project's canonical protocol tree, document version
26.9.13, wire version 26.9.13.

They are the specification this repository's Swift RAPP engine implements, and
the state model its transition tables are transcribed from. The conformance
corpus in `../rapp-conformance/` is generated from the same revision and is
replayed by the test suite, so a change here that the engine does not follow
fails the build rather than drifting silently.

The RefineID product is the change controller for this protocol. Amend
these files here when product behaviour needs a wire event the draft
does not name, regenerate the corpus that the change touches, and keep
the engine on the same revision. A silent workaround is not a substitute.

`../rapp-conformance/rapp-transport-v26.9.7.70.json` records post-handshake
frames generated from the canonical Rust engine at wire version 26.9, using the
same fixed keys as the conformance corpus's handshake transcripts. The corpus
proves the handshake but stops there, so without these the framing that carries
every operation would have no golden vectors: sixteen frames per suite, both
directions, with counters running well past their first value.

`../rapp-conformance/rapp-flow-v26.9.7.70.json` and
`../rapp-conformance/rapp-operation-v26.9.7.70.json` record message bodies
generated from the canonical Rust engine at wire version 26.9, with every input
fixed and recorded beside the bytes so the Swift engine can build the same
values. The conformance corpus covers the envelope and the handshake but no
message body above them, so without these the pairing, session, and operation
bodies would be checked only for round-trip: an encoding both sides of one
implementation agree on can still be one no peer accepts.

