# Issue states

Issues hold confirmed defects and gaps that are not fixed yet
(`Documentation/process/working-method.md`). An issue with no state label
is actionable: someone can start on it now.

Two labels record the reasons an issue is not actionable. Both are
labels on the GitHub repository, not states in the text of the issue, so
the open list can be filtered by them.

## `deferred`

The finding is valid and correct as written, and it is outside what the
software currently ships. It leaves the state when the shipping scope or
a feature gate changes and puts the affected code on a path a user can
reach.

Deferring is not the same as `wontfix`. A deferred issue is expected to
be worked on; `wontfix` says the project will not do it.

## `blocked`

Someone else owes the next input: a platform behaviour that cannot be
changed from this code, a vendor answer, a wire change in
refineid-core, or a release process outside our control. It leaves the
state when that input arrives.

Where a change is possible but the acceptance cannot be met as written,
the issue records the measured evidence for that and the alternative
that meets the intent, so a decision can be made instead of a guess.

## What every labeled issue carries

A comment naming the trigger: the gate that must be turned on, the scope
change, the core issue, the exchange with the vendor, the decision
needed. A state label without a named trigger is a way to forget an
issue politely, which is what these labels exist to prevent.

Tagging is a statement about today. When the trigger arrives, remove the
label; the issue becomes actionable without further ceremony.
