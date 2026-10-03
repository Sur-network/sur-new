# Questions for the owner

1. **Groups E and F — answered.** They were not attempted in the first pass of this round; they were run in the follow-up passes of 2026-10-03 and their results are in the result table (E01–E05, F01–F07, plus the combined F6 test and the F07 re-run). No statement in this package that "Group F was not run" is current. What remains open from that area is listed in items 2 and 5-11 below.
2. **Path L's real-time execution** (the actual ~14-day governed rate-change path, at real
   constant values) — this round exercised the full governance path end-to-end only on the
   compressed test-fork (owner-authorized), proving the mechanism works, but this is explicitly
   not equivalent to running it for real. Do you want the real-time version scheduled separately,
   given its ~14-day minimum duration?
3. **§5.1's "never let active validators drop below 4" rule vs C-L04's own literal step sequence**
   (DEVIATIONS.md item 4) — the document's own C-L04 steps mechanically produce a dip to 3 active
   validators on a 6-validator network. This round ran it exactly as specified and observed no
   instability (3-of-3 quorum, all 3 nodes stayed up), but flagging the inconsistency in the source
   document itself in case a future revision should resolve it.
4. **BlockRewardDistributor runtime bytecode size** (18,519 vs the document's stated reference of
   18,177 bytes, FINDINGS.md item 3) — source hash matches exactly and no behavioral difference was
   found; is the reference figure itself simply stale (from a different solc patch version), or
   should this be investigated further?

---

## Added in the follow-up pass (2026-10-03)

5. **Item 1 above is now answered by this pass** (Groups E and F were run); item 2 (path L real time) is
   unchanged — not started, per your instruction. Both halves of L4 are now separately evidenced (governance
   L1-L3 on the fork; Besu transition + cap coordination at X on Net-F1), only the combined ~14-day run remains.
6. **Operational runbook for a reward-rate rollout** (FINDINGS.md items 9-10): edit-the-file-and-restart-every-node
   is both sufficient and necessary, and one node left behind (or a late joiner with the old genesis) is rejected at
   X with a state-root mismatch. Should the rollout procedure (including "every node, including future joiners,
   must carry the transition before X") be written into the operations documentation, and who owns the check?
7. **Silent under-payment** (F04, FINDINGS.md item 13): the cap only bounds Besu's reward from above. Do you want an
   off-chain alarm (RewardRouter or monitoring) for "Besu paid less than the approved rate", or is it acceptable?
8. **State window for the Router** (FINDINGS.md item 11): independent accounting of a 27,600-block daily range is not
   possible from a ~512-block Bonsai window (Besu answers `null`/`[]`, not an error). Will the Router run on an
   archive/FOREST node, or collect per block as it is produced? This is a design decision, not a test result.
9. **The distribution transaction's own fee** (FINDINGS.md item 12): 94–136 SUR per `distributeRewards` at the
   current minimum gas price, returned to the distributor and counted in the *next* epoch. Intended?
10. **Wrong-genesis node behaviour** (FINDINGS.md items 10 and 18): a node whose genesis lacks the transition keeps retrying the invalid block (1,111 repeated rejections within about 36 minutes) and stays at the old height. With a default heap its process memory grew to about 7.5 GB and no `OutOfMemoryError` was observed in that window; with a 512 MB cap the same scenario ended with an `OutOfMemoryError` about 90 s after block 300 (cause not established). Should the operations guidance state a heap recommendation and an alarm for "node stuck at height N with repeated state-root mismatches"? (Options not chosen here.)
11. **Which network recipe should the long-lived L01/L02/L04/L05 genesis follow?** They were built without the FoundationDAO seed (A14 passes against that recipe). **Update (third pass): C-L04-6 was run on a fresh seeded network, Net-L04f; the question remains only for any future long-lived network.**
12. **A09 / `lastBoardRefreshAt`** (FINDINGS.md item 19): the genesis-builder spec asserts it equals the genesis timestamp for a seeded board; the test builder leaves it 0 (so `refreshBoard()` is callable at once). **Update (fourth pass): the test builder was fixed (FINDINGS.md item 22).** What remains is only the production tool: the spec already requires `lastBoardRefreshAt == genesisTimestamp` for a seeded board; the production genesis tool must implement and assert it (or the spec must be changed) — not decided here.
13. **Unaffordable transactions stay pending silently** (FINDINGS.md item 20): a transaction whose upfront cost (`gasLimit × gasPrice`) exceeds the sender's balance was accepted into the pool and never mined or rejected. Should the oracle/Router design include a pre-send balance check and a "pending too long" alarm? (Options not chosen here.)
14. **Path L** (`PLAN-path-L-real-time.md`): the plan is ready for separate authorisation; the decisions in its section 9 (margin, transition rollout method, data insurance, restart style, maximum tolerated interruption, host/disk backup, alert channel) and the four authorisations in its section 10 are yours.
