# Phase 10, Stage 1 — deliberate revival rehearsal

A clean, *deliberate* version of Stage 1 (distinct from the accidental deadlock in Phase 2, which
this closely mirrors and independently confirms).

## Setup
Active validator set at test time: 4 (validator1, validator2, validator3, candidateA), quorum =
`floor(2*4/3)+1 = 3`.

## Steps and results
1. Stopped the real Besu nodes backing validator2 and candidateA (2 of 4 = 50% > 1/3) via
   `taskkill` on their PIDs (found via their P2P listening ports).
2. **Confirmed halt**: `eth_blockNumber` stayed at `0x864` for over a minute; node1's log showed
   `BFT round summary (quorum = 3)` with only 2 of 4 validator addresses present in round-change
   gossip — exactly the deadlock signature from Phase 2, this time deliberately induced.
3. **First recovery attempt — restarted only the 2 down nodes**: did **not** resume. Same
   round-timer mismatch as Phase 2: the 2 nodes that stayed up had already advanced to a higher
   round (with a doubled timeout) than the 2 rejoining nodes (starting fresh at round 1) — they
   never converged.
4. **Second recovery attempt — restarted all 4 relevant nodes together**: **resumed cleanly**,
   producing new blocks within ~20-40 seconds of the joint restart.

## Conclusion
This is the second independent confirmation (after Phase 2's accidental one) that Besu's
documented Stage-1 technique — restart **all** validators together, not just the ones that went
down — is what actually resets `requesttimeoutseconds` and restores liveness. A partial restart is
not sufficient once the round timer has doubled past the surviving nodes' current round.
