# Live Besu/QBFT test, round 3 — 2026-09-30 — everActivated reward policy, ALL 5 phases pass

Full report: `REPORT.md`. Scope: per `sur-besu-test-status.md` v3 — ONLY the "pay the real
block-producer directly regardless of later exit/suspension" reward policy (`everActivated` in
`ValidatorsRegistry.sol`, its use in `BlockRewardDistributor.sol`, and the genesis-seed-helper fix
in `ValidatorsRegistry_GenesisSeed.sol`). Everything proven in round 2 was correctly NOT repeated.

## Verified by Claude (not re-run) before accepting this report
- Diffed all 3 uploaded contract files against the canonical `contracts/` versions: every
  difference is an expected test-fork substitution (test keys, shortened timers, 3-founder array)
  — no unauthorized logic change.
- Confirmed `everActivated` sits at storage slot 20 (matches independent enumeration in `REPORT.md`
  and matches this project's own earlier direct-solc verification).
- Confirmed the exact revert string at `BlockRewardDistributor.sol:705`.
- Independently recomputed Phase E's numbers (the most complex — reward + folded membership fee,
  split 95/95/4 of 194 blocks) from raw contract constants: matches the report **to the wei**
  (founder1/2: 9888.814432989690721649 ether; newValidator1: 416.371134020618556701 ether;
  foundation: 58.2; treasury: 135.8).

## Result
All 5 phases (A–E) passed on a real, fresh Besu 26.9.0 QBFT network (chain ID 424244):
- **Phase A**: founders get `everActivated=true` from block zero (getter + independent manual
  slot-20 computation).
- **Phase B**: first-ever real `distributeRewards()` succeeds, pays founders exactly per formula.
- **Phase C**: founder3 exits mid-range (`isValidator` flips to `false` immediately, P04 semantics
  confirmed live) and still receives its exact proportional share in the next distribution — no
  windfall to founder1/founder2.
- **Phase D**: a never-activated address is rejected with the exact revert string
  `"address was never a legitimate validator"`.
- **Phase E**: a non-founder validator's `everActivated` survives a real `withdrawStake()`
  (`ValidatorInfo` fully deleted, `status=None`), and a later distribution still pays it correctly.

Priority-2 optional items (exit-without-case, board tie, P05/MIN_DISTRIBUTION_INTERVAL isolation)
were explicitly not attempted this round — disclosed, not a gap in the mandatory scope.

## Real findings worth acting on (not bugs — genuine operational notes)
1. `BlockRewardDistributor`'s physical-maximum sanity check tripped in Phase E because this
   network's actual block cadence ran slightly faster than the nominal `blockperiodseconds`. The
   real off-chain RewardRouter oracle should defensively cap its declared range size the same way
   the test script did — see `sur-reward-router-spec.md` update.
2. A genesis timestamp accidentally set ~30 minutes in the future stalled block production for
   ~15 minutes with no error logged (QBFT block timestamps must be ≥ parent's) — purely a test-setup
   mistake, not a Besu or contract bug, but worth noting as an easy-to-hit operational trap.
