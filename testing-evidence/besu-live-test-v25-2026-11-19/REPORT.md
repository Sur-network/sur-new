# Besu live test, round 1, v2.5 contracts: report

Date: 2026-11-19. Besu `hyperledger/besu:26.9.0` (Docker image already present locally; nothing was pulled). QBFT contract mode, block period 2 s, forks through London at block 0 with `zeroBaseFee` (same genesis style as the v2.2 campaign). Contracts: `contracts/` at the repo state `c10ff59` (read only, solc 0.8.24, optimizer 200, evmVersion paris).

**Scope and honesty.** The Hardhat in-process suite (91 tests) was not re-run here and no Hardhat result is cited as a Besu result. This is a first round on one host with Docker bridge networking and short runs. It says nothing about production readiness. Results below were verified against the raw JSON files in `evidence/04-results/` by the orchestrating session (verdict and failed-check counts match this table).

| Net | Chain id | Genesis | Used for |
|---|---|---|---|
| Net-A | 425025 | 7 founders, block reward 2 Suren | BG-01..07, 09, 11, 12, 13, 08a, BR-SIZE |
| Net-S | 425026 | 1 founder, block reward 3 Suren (test only, to create "actual above approved") | BG-10, 10-BH, 08b |
| Net-L2 | 425027 | 1 founder, block reward 2 Suren | BG-10b |
| Net-T | 425028 | 1 founder plus a TEST-ONLY overlay of four Registry time variables | BG-05b |

Net-S and Net-L2 were each built twice because the first lottery script runs died (script defects, see DEVIATIONS.md D-8). First-run logs are kept as `*.run1-superseded.log`.

## Result table

| ID | Result | Checks | What was shown |
|---|---|---|---|
| BG-01 genesis boots | PASS | 17/17 | Blocks from #1. `getValidators()` equals [operator1], not owner1. `qbft_getValidatorsByBlockNumber` at block 1 and latest equals the same. The miner of the last 5 blocks and the committed-seal signature recovered from the header are operator1. |
| BG-02 founders join | PASS | 24/24 | `setOperator` plus Verifier `recordActivation` for owners 2,3,4 then 5,6,7. The set grows 1,2,3,4 then 7 and the QBFT set equals the contract list at the activation block. Last 24 blocks at n=4 mined only by the 4 operator keys, 28 blocks at n=7 by the 7 operator keys, at least 5 distinct operator seal signers at n=7. f=1 at n=4: one node stopped, 14 more blocks, every 4th block takes 12 s (round change), the node restarted and caught up. |
| BG-03 `setOperator` swap | PASS | 22/22 | A: owner2 to op2b with node n2b running: the list and QBFT set switch at the tx block, old operator mines no more, no gap above 2 s, stopping the old node changes nothing. B: owner3 to op3b with node NOT running: contract accepts it, no halt (6 of 7 live), op3b's turns cost 12 s, the node started later syncs and mines. |
| BG-04 selfSuspend and resume | PASS | 17/17 | `selfSuspend` leaves the QBFT set at once with no halt; a board member is refused; `requestResume` then `recordResume`, mines again on the same node, no probation. |
| BG-05 paying entry | PASS | 26/26 | `requestMembership(op)` with 520,000 Suren: Registry +500,000 exactly, Distributor `pendingMembershipFees` +20,000, Distributor balance reconciles to the wei, seat NFT minted, Probation, operator mapped; rate-limit and "probation not elapsed" refusals. |
| BG-05-neg | PASS | 3/3 | Redo of two BG-05 negatives that were inconclusive (D-8). |
| BG-05b entry cycle (Net-T, overlay) | PASS | 17/17 | Activation refused before 120 s then accepted; QBFT set goes 1 to 2 with the entrant's operator key; `requestExit` removes it and burns the seat; `withdrawStake` after 60 s returns the full 500,000; permanent ban. Uses short TEST-ONLY storage values (D-3). |
| BG-06 seat NFT transfer | PASS | 24/24 | Transfer plus `SeatTransferred(statusAfter=SelfSuspended)`; record, operator, founder flag and everActivated move; seller permanently exited; operator leaves the set at once; resume refused until `acceptSeatTransfer`; then `requestResume` and `recordResume`, mines again on the same node; `tokenURI` works; transfers to an unverified address, a seat holder and an operator key refused. |
| BG-07 recovery removal | PASS for case 1 (29/30; first run FAIL 1 check) | 30 | Node stopped; `recordRecoveryRemoval` with the hash of `qbft_getSignerMetrics`; operator leaves the list and QBFT set with no stall; objection; 3 board votes uphold; refusals: referral, early expiry, direct resolve, non-board vote, exit before 90 days. The one failed check was a bug in the script's expected value (op7 duplicated in the expected list); the chain was right. |
| BG-07b | PASS | 6/6 | Case 2 on a bought seat: removed, objected, 3 board votes cancel, reinstated. Redo of the failed check in a clean run. |
| BG-08a distributeRewards, actual == approved | PASS | 22/22 | Range [1,816] over 8 owner addresses. Before the call, Distributor balance equals 2 x height + all tx fees + 20,000 pending exactly. Validator payouts, Foundation 15%, Treasury remainder, 30% fee burn (membership fee exempt), balance deltas and events recomputed in BigInt and equal. 8 negatives revert. A second call inside 23 h refused. |
| BG-08b actual > approved | PASS (re-run 16/16; run1 FAIL 1 of 27) | 16 | Range [1,391], reported 1173, approved 782, excess 391 burned to address(0) at once, `RewardExcessBurned(1,1,391,782,391)` exact, only the approved amount split, balances close to the wei. Run 1 failed one check because of a script defect (D-8/D-9); kept next to the re-run. |
| BG-09 FoundationDAO | PASS | 25/25 | Typed `Spend` (600,000 Suren) and `Execute` (the DAO calls `setBaseURI` on the seat NFT) with 3 of 5 votes; proposer's vote automatic; wrong hash, non-board and repeat votes refused; `getProposal` returns all typed fields, expiry +30 d, `computeParamsHash` equals the stored hash. |
| BG-10 lottery commit-reveal | PASS | 15/15 (+41 PASS lines in the interactive log) | DAO `StartLottery`, 6 tickets, CEO commit, close, reveal, 2 draw batches, 3 winners. Seed equals keccak(secret, hash of the target block read over RPC); winners equal an off-chain Fisher-Yates replica; winners are Probation with seats; the 60 Suren pot goes to the DAO. |
| BG-10b no reveal | PASS | 11/11 | CEO commits and never reveals; reveal after target+250 refused; cancel inside the window refused; `cancelLottery` after the window; 3 refunds of exactly the ticket price; about 630 s real time. |
| BG-10-BH blockhash | PASS | 8/8 | Probe in transactions: real hash for offsets 1..256 (256 inclusive), 0 for 257..260, for a future block and for block 1. QBFT `mixHash` is a constant marker, not random. |
| BG-11 claims vault | PASS (partial) | 19/19 | `genesisTimestamp` equals block 0 time, `totalHeld` 8,100, vault balance equals it, `claimInfo` and `installmentAmount` correct, `monthsReleased()` 0, `monthIdOf` correct on Besu, `withdraw` before month 1 reverts as do a non-claimant and a plain transfer. |
| BG-12 list change in one block | PASS | 3/3 | Three `recordActivation` in one block: the set goes 4 to 7 in that block, contract list equals QBFT set from then on, no halt. |
| BG-12b `getValidators()` size | PASS (limited) | 2/2 | `eth_estimateGas` 28,910 (n=1) and 53,204 (n=6), about 4.9k gas per validator, about 15 ms per `eth_call`. |
| BR-SIZE oversized contracts | PASS (derived) | 5/5 | FoundationDAO 28,365 B and ValidatorsRegistry 34,605 B (both above 24,576) work through `eth_getCode`, calls and state-changing txs. Derived from BG-01/02/09 (`scripts/br-size.js`) because the nets were already destroyed. |
| BG-13 halt and resume (extra) | PASS | 9/9 | 3 of 6 validators stopped: no block for 40+ s, a pending tx stays pending, `getValidators()` readable; after restart the first block at 83 s (round 3), the pending tx is mined, the set unchanged, blocks 2 s again. |

## Not run (never faked)
- BG-07: the 90-day collateral lock elapsing, `requestExit` after it, the 7-day expiry and referral to the validators (Besu cannot advance time). Only the early refusals were checked.
- BG-11: monthly release, 24 instalments and the last-instalment remainder.
- Probation of 7 days and an entry window of 7 days with real values (Net-T uses short TEST-ONLY storage values).
- `recordSuspension`, the mass-failure window, slash, appeal and `recordRecovery`.
- A second lottery (365-day rule), board monthly refresh, rate-change governance.
- Shanghai/Cancun transitions.
- SurenSale, ServiceStaking and Treasury spending.

## Cleanup
`docker ps -a` is empty. Volumes are only the four that existed before. Networks are only the defaults plus the pre-existing `e4_isolated`. All `sur25-*` containers, data volumes and bridge networks were removed; no image was pulled or removed (confirmed again by the orchestrating session after the run).

Findings are in FINDINGS.md, deviations in DEVIATIONS.md, limits in LIMITATIONS.md.
