# Limitations, round 1b

- One host, Docker bridge, no real latency; short runs (about 430 blocks on Net-A, 125 on Net-T).
- Besu cannot advance time: every 72 h+ timer is NOT-RUN except the Net-T overlay (probation 120 s, cooldown 60 s).
- Founder seat collateral is 0, so Net-A cannot show collateral movement; BH-06B does it with one paid entrant on an overlay net.
- BH-03 does not cover the two-step node-key change and tested only the old immediate swap with the new node running.
- The board's `_impartialAuthorityCount` change (Probation members not counted in the recovery quorum) was not isolated by a live referral test.
- Block attribution used the miner field and `ownerOfOperator`; no RewardRouter. No Shanghai/Cancun, rewards, lottery, treasury, slashing or appeals in this round.
- The Hardhat suite was not re-run, so there is no side-by-side comparison.
- Not production-readiness evidence.
