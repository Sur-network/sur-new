# FINDINGS — round 5 (contracts v2.1.0). Measurements and observations; no contract or policy change is proposed here.

## 1. The Registry→Board hook works on every status change tested, inside the same transaction
`recordSuspension`, `requestExit`, `recordActivation` and `recordRecovery` each emitted `VoterSynced(validator, counted)` from the Board **in their own receipt**; no one called `syncVoter`. Counters (`voteCount`, candidate list) followed at once: suspension of a voter with one vote took the candidate from 3 to 2; recovery put v1's two votes back (+1 each). Suspended/exited validators' own vote records are kept (`getVotesOf`), so recovery restores them. A manual `syncVoter` afterwards was a no-op (no event). The event is emitted on every real status change, also for a validator that has cast no votes (cand2/cand1 activation). Evidence: `Net-R5-A-board-hook-floor.json` T2, `Net-R5-F-dispute.json` D0.1, D3.1, D5.2.

## 2. Board authority is a pure function of `block.timestamp`: it ends at the first block of a new month without any transaction
On the test-fork (900 s months) the same five addresses had `hasBoardAuthority` true at the last block of a month and false at the next block, three times (blocks 291/292, 591/592, 891/892). Flags (`isBoardMember`) stay set until `refreshBoard`. Before the refresh every board action, `syncBoard()` and `fillVacancies()` revert with `board term ended - call refreshBoard for the new month` (the baseline Net-R5-B shows the same on real calendar months with a back-dated genesis). Voting remains possible before the refresh.

## 3. `refreshBoard(address[])`: permissionless, no incumbency, tie to the older validator
Called by a non-validator account it seated the five most-voted active validators; two founding members lost their seats; at a tie for the fifth seat (2 votes each) the validator with the lower `activationSeq` won (seq 2 over seq 4). A candidate with no counted votes cannot be seated (the founding members v1, v2 with 0 votes were out in month G+1). A second call in the same month reverts (`this month's board is already set`). A refresh whose result equals the seated board does **not** bump `boardVersion` (only `boardMonthId` moves); a composition change bumps it and invalidates open board actions (`board membership changed since this action was proposed - propose again`).

## 4. Floor of one active validator
At two active validators a suspension is allowed (→1); at one, `requestExit` and `recordSuspension` of the last active validator revert (`at the minimum validator count - exit blocked / - suspension blocked`), mined with status 0 and no state change. A **Demoted** validator may still exit at the floor (the floor protects only the Active set). QBFT with a single validator (6 of 7 nodes running as non-validators) produced 6 blocks in 18 s, validator set = [v1]. Evidence: T6.

## 5. Dispute and appeal votes are bound to the status snapshot
Delivery dispute: `requiredVotes` and the eligibility nonce are fixed at filing; a validator activated **after** the filing (cand1) is rejected although active now; a validator suspended after the filing and the subject are rejected as not active. Appeal: a validator **recovered after** the appeal was filed (v1) is rejected, a validator activated **before** it (cand1) votes. 4 votes (4 = 7/2+1 at filing) confirmed the slash: 5,000 SUR (1% of 500,000) moved from the subject's locked stake to the Treasury. Recovery is refused while a case is unsettled (`resolve the pending slash first`) and allowed after the case was closed (uncontested slash of a zero-stake founder). Evidence: D1–D6.

## 6. Size
`ValidatorsRegistry` runtime code is 23,005 bytes: 1,571 bytes below the EIP-170 limit of 24,576 (genesis injection is not subject to the limit, a deployment by `CREATE` would be). `ValidatorsBoard` 17,035 bytes.

## 7. Process finding (my fault, disclosed)
The first full run of the fork script crashed in Part D on a typo before writing its JSON; Part M's raw record is the console log plus a read-only chain record taken afterwards. Part D was then re-run alone. The two results are not from one uninterrupted run, but from the same network and the same uninterrupted chain.
