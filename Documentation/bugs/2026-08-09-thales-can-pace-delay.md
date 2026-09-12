# Thales MultiApp v5 CAN-PACE progressive delay

Status: vendor requirement confirmed; recovery parameters undisclosed.

A Thales MultiApp v5 card can deliberately delay a CAN-PACE response
after unsuccessful attempts. Repeated interrupted attempts are a
plausible trigger. Reinstalling the app, changing source revisions,
restarting the phone, or moving the card to another phone does not
necessarily remove card state.

## Published behavior

BSI TR-03110 Part 1 section 2.3 defines CAN as non-blocking: the chip
must not block it after failed authentication. When a non-blocking
password has insufficient entropy, the same section requires an
additional brute-force countermeasure and explicitly permits delays.

The Thales security target makes the countermeasure concrete for
Digital Identity 1.0.A on MultiApp v5.0.A. FIA_AFL.1/PACE, Table 20 on
page 56, says:

- one unsuccessful MRZ/CAN PACE authentication exponentially increases
  the delay before another attempt is possible; and
- the CAN-specific rule defines a presentation-count parameter in the
  range 0 to 255 and an increasing wait between the terminal challenge
  and the card's PACE response.

See [`thales_multiapp_v5_security_target`](../references.md#thales_multiapp_v5_security_target)
and [`bsi_tr03110`](../references.md#the-card).

The sources do **not** publish the delay values, the counter's storage
lifetime, its decay or reset rule, or whether every interrupted exchange
increments it. Do not invent a fixed cooldown or promise that a power
cycle clears it.

## Recorded exchange

Observed 2026-08-09 on a production Thales MultiApp v5 FINEID card:

1. `SELECT MF` returned `SW=9000` in 9--18 ms.
2. PACE `MSE:Set AT` returned `SW=9000` in 14--28 ms.
3. The first `GENERAL AUTHENTICATE`, which requests the encrypted nonce,
   received no response before the iPhone dropped the tag at
   45.304--45.317 seconds.
4. One earlier run received the structurally valid 22-byte response at
   42.47 seconds. This excludes a malformed APDU as the general cause.
5. An exact clean RefineID-Apple `origin/main` build reproduced the
   timeout.
6. The same card then failed registration on a second phone.

The successful `MSE:Set AT` only proves that PACE initialization was
accepted. It does not authenticate the CAN. The stall location and
duration match the Thales delay rule: the card remains responsive to
the setup commands and withholds the PACE response.

An earlier uncontrolled observation found that the state disappeared
after a few hours. That is observation, not a specified recovery rule.

## iPhone failure loop

Once the card's delay approaches the iPhone tag timeout, a phone cannot
finish PACE:

    increasing card delay
      -> outstanding GENERAL AUTHENTICATE
      -> iPhone drops the tag before the response
      -> PACE remains incomplete
      -> another attempt may meet a still longer delay

The system NFC sheet remains visible while the transmit is outstanding.
`TKSmartCard.endSession()` and `TKSmartCardSlotNFCSession.end()` wait
behind that transmit; they do not cancel it. An application timeout
followed by an automatic retry therefore produces another NFC sheet and
another card attempt, not recovery.

## Diagnostic and test rules

1. Do not automatically retry CAN-PACE.
2. On a delayed encrypted-nonce response, stop testing that card. Do not
   use repeated phone or source-revision A/B attempts as diagnostics.
3. Record the source revision, each command duration, final status word
   or transport timeout, and whether the exchange completed.
4. Distinguish this progressive delay from PIN1/PIN2 retry state and
   from a formally suspended password. Registration has not reached a
   PIN VERIFY when it stalls at the encrypted nonce.
5. Preserve code changes before comparison. A source rollback cannot
   roll back card state.
6. If recovery must be tested, use one controlled attempt. A long-lived
   PC/SC reader can observe a response beyond the iPhone deadline, but
   whether a completed PACE resets this card's delay remains a hardware
   hypothesis until a before/after exchange records it.

This finding explains the 2026-08-09 registration jam. It does not
explain or excuse an ordinary fast-path NFC sheet that outlives
certificate discovery; that separate Safari/CTK timeline still requires
instrumentation when the card is back in its normal state.
