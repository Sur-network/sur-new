# DEVIATIONS from `sur-besu-live-test-brief-v4.md`, with reasoning

**Not all deviations below were individually pre-authorized by name.** Only item 1 (building and
using a test-fork at all) was the subject of an explicit owner decision in chat (2026-10-02),
in response to a scope question about the document's three time tiers (S/M/L), given a ~5-6 hour
session budget. The owner's instructions for that decision, summarized: attempt all three tiers,
but via a clearly-separated, minimally-invasive test-fork for the genuinely long real-time gates;
present the compressed-constants table before building; keep the original `Plan/contracts` source
completely untouched; record fork source/diff/hashes/genesis/evidence separately from the
baseline; never report fork results as baseline-code results; mark untested real-time paths
explicitly NOT-RUN; and do not force every scenario to a "pass" if time runs out. Items 2-9 below
are judgment calls made during (or, for item 8, after) execution, within that broad authorization,
but were **not** individually cleared with the owner in advance — each item's heading states
whether it was specifically authorized or is this session's own call, so "owner-authorized" is
never used as a blanket label for everything in this file.

## 1. A test-fork was built and used (document's own rule 2/§6 forbids this by default) — [explicitly owner-authorized]

The document's own text says real-time constants must not be shortened this round ("این‌ها کوتاه
نمی‌شوند"). The owner explicitly overrode this for this session only, authorizing a narrowly
-scoped fork that changes exactly three `constant` values in `BlockRewardDistributor.sol`
(`MIN_DISTRIBUTION_INTERVAL` 23h→90s, `RATE_CHANGE_DELAY` 7d→180s, `MIN_RATE_CHANGE_LEAD_BLOCKS`
201,600→80 blocks) and nothing else — no logic, quorum formula, or economic-policy value was
touched. The exact diff, hash, and genesis evidence for the fork are kept in a fully separate
directory tree from the baseline (`hardhat-fork/` vs `hardhat/`, `nets/Net-Fork/` vs the baseline
nets), and every fork result is labeled with a trailing `'` (D02', D04', D05') or an explicit
"TEST-FORK" / "Net-Fork" tag in this report — never presented as a baseline-code result. See
`evidence/00-baseline/testfork-BlockRewardDistributor.diff` and `testfork-sha256.txt`.

## 2. `Net-L05a` and `Net-L05b` were combined into a single network (`Net-L05`) — [this session's own judgment call, not individually pre-cleared with the owner] — **UPDATE 2026-10-03: superseded for the re-run rows by item 10 (separate fresh networks); the combined-network rows remain only as history**

The document specifies two separate networks so the two sub-scenarios' board-composition
mutations don't interfere. To save setup time within the session budget, both were run
sequentially on one network (C-L05-2 first, while the board was still intact; C-L05-3a/3b after,
which deliberately mutate the board). This introduced one real complication: a test-script bug
(see FINDINGS.md item 5) was discovered partway through C-L05-2/3a, by which point two board
members had already exited on this shared network — the corrected re-run of the vote-threshold
check therefore ran with 3 active validators instead of a fresh 5-member board, which is disclosed
directly in that evidence file rather than presented as if it were the originally-planned
clean-board scenario.

## 3. Groups E and F were not attempted this round — [this session's own prioritization call, not individually pre-cleared with the owner] — **UPDATE 2026-10-03: both groups were run in the follow-up pass, see items 10-16 and the result table**

Both are explicitly framed by the document itself as auxiliary to this round's actual purpose
(E: "یک benchmark مصنوعی هزینه است، نه شاهد رفتار عملیاتی"; F: Besu-side reward-change
coordination, a separate concern from the L01/L02/L04/L05/L07 contract-logic fixes this round
targets). Given the session budget, priority was given to Groups A, B, C, and D — the groups that
directly exercise this round's actual code changes. Recorded as NOT-RUN, not as failed or skipped
silently.

## 4. `Net-L04`'s C-L04 sequence allowed the active-validator count to drop to 3 — [following the document's own literal step sequence, not a deviation this session introduced]

Section 5.1's general operating rule says never let the active count drop below 4. Step 5 of the
C-L04 sequence as specified (V5 suspended, V4 suspended, then V3 votes and exits) mechanically
drops the active count on a 6-validator network (5 founders + C6) to 3. This was executed exactly
as the document's own C-L04 step sequence describes; the general "≥4" rule in §5.1 and this
specific scenario's literal steps are in tension in the document itself. No chain instability
resulted: all 3 remaining validators' nodes stayed online throughout (the quorum for 3 active
validators is 3-of-3, exactly matching the 3 running nodes), so this is noted as an observation
about the document's own internal consistency, not a deviation I chose unprompted.

## 5. Besu binary and `node_modules` were reused via directory junction, not freshly downloaded/verified — [this session's own judgment call, not individually pre-cleared with the owner]

Both were already present and hash-verified in round-1/round-2 test artifacts on this machine. No
fresh download occurred this round, so the document's stated Besu tarball SHA-256 reference was not
independently re-verified this session (see `evidence/01-environment/env.json`).

## 7. Recovery from suspension was resolved via the appeal+vote path, not the 72-hour uncontested wait — [this session's own judgment call, not individually pre-cleared with the owner]

Discovered mid-session (FINDINGS.md item 8): `recordRecovery` is blocked by an independent slash
case that `recordSuspension` always opens, which the document's Group B description does not
mention. Resolving it the way the document's own machinery supports without a real-time wait
requires a contested appeal: the subject validator files an appeal and a simple majority of active
validators vote to confirm the slash, which resolves the case immediately. This session used that
path on Net-B (single suspension, not mass-failure-exempt) and relied on an automatic mass-failure
exemption on Net-L04 (two suspensions within the same window, crossing the 20% threshold) — see
FINDINGS.md item 8 for both paths in full, with transaction evidence for each. Neither required
any code change or real 72-hour wait; both are real, on-chain paths this contract already supports
for closing a slash case quickly when a majority agrees, not a workaround invented for this test.

## 8. Two Net-B nodes were briefly restarted twice after the networks were stopped, to complete fresh evidence requested in review — [this session's own judgment call, in response to explicit review feedback, not the original scope]

After the initial three-file report was delivered and all 38 nodes were stopped per the owner's
instruction, review feedback asked for (a) real signer/producer data at the two validator-set
transitions (B01/B07, FINDINGS.md item 1) and (b) fresh, this-round evidence of a suspended
validator still being paid (C-REG-2, FINDINGS.md item 2) — neither of which existing evidence
covered precisely enough. Both were answered with short, targeted restarts: a single read-only
node (no mining, no transactions) to query already-mined historical block headers for (a), and a
brief restart of Net-B's 4 active-set nodes to send exactly one real `distributeRewards()`
transaction for (b). Both are bounded, targeted actions completing specific evidence gaps flagged
in review — not a fresh long campaign and not a code change, consistent with the reviewer's
explicit instruction. All nodes were stopped again immediately after each.

## 9. Two genesis founder sets (G5, G6) use a parameterized-by-copy variant of the genesis-seed helpers — [this session's own judgment call, consistent with technique already used in rounds 2-3]

The production `ValidatorsRegistry_GenesisSeed.sol` / `ValidatorsBoard_GenesisSeed.sol` /
`FoundationDAO_GenesisSeed.sol` hardcode addresses in a no-argument constructor (mirroring genesis
injection semantics). Since this round needs multiple differently-sized founder sets (G5 across
five networks, G6 for Net-D), the real helper files were copied verbatim (same hash-verified field
layout) into per-network variants (`testonly-ValidatorsRegistry-GenesisSeed-G5.sol` /
`-G6.sol`, etc.) with only the hardcoded address list and genesis-timestamp literal changed — the
constructor logic, field layout, and `__gap` reservations are byte-for-byte identical to the real
helper. This is the same technique already used (and disclosed) in rounds 2 and 3.

---

# Follow-up pass (2026-10-03) — owner instruction: re-run inconclusive L05, D02 accounting, Groups E/F (F first); no contract/policy change; path L not started

Authorization status of each item below, in the same convention as above. **No contract or policy
was changed; no test-fork was used in this pass (all of it ran on the unmodified baseline);
the path-L real-time run was not started.**

## 10. New networks for the follow-up; TEST-ONLY-SEED used for Groups E/F — [within the owner's instruction and the document's own method]
Net-L05a and Net-L05b are now **separate fresh networks** (this supersedes item 2 for the re-run
rows; the old combined Net-L05 rows are kept and marked SUPERSEDED). Net-D3 (G6, 30M gas, plus a
funded-but-never-activated candidate C6, no node for it) was added for the D02/D06 re-execution.
Net-F1…F5 and Net-E15/E30/E60 follow the document's §5.3 table. For F1/F3 the contract's rate history
(`[(300, 3e18)]`) and for E the 399-entry history and 150 payees' `everActivated` flags were written
**directly into genesis storage** — this is the document's own `TEST-ONLY-SEED` method (round-tripped on
a fresh deploy of the real contract before use). The seeded results are labelled as such and the E group
is, per the document, a synthetic benchmark only.

## 11. C-L05-3b's second composition change leaves 3 active validators — [following the document's own literal step sequence]
See FINDINGS.md item 14. All node processes were kept running and liveness was re-checked.

## 12. Hard process kills for node restarts; 512 MB JVM heap cap on every node — [this session's own judgment call]
F05's "restart nodes one at a time" and the F05 control used `taskkill /F` + relaunch, not a graceful
shutdown. Every node ran with `-Xmx512m -Xms256m` (the host-capacity workaround from FINDINGS.md item 2),
which is a possible confounder in F07's node5 `OutOfMemoryError` (FINDINGS.md item 10; not established — see item 23 and FINDINGS.md item 18).

## 13. F03 used the test tool's FORCE mode — [the document's F03 requires observing the contract's own rejection]
`testonly-settle.js` normally refuses to send when the independent R exceeds the contract cap (document
§D). For F03 the cap gate was bypassed on purpose (`FORCE_SEND_CAP_EXCEEDED=1`, recorded in the evidence
JSON's `warnings`), so that the **contract's** own rejection (`totalRewards exceed approved reward for
range`) could be observed in a mined transaction. `totalRewards` was NOT reduced.

## 14. D02 accounting was re-executed on a fresh network, not reconciled retroactively on Net-D — [this session's own judgment call]
The original Net-D already consumed its first distribution, and its early-block state is outside Besu's
~512-block window, so a retroactive reconciliation was not possible. The full methodology was therefore
applied to a **new first distribution on Net-D3** (G6, baseline). The M term was produced by a real
`requestMembership` from a candidate that is never activated; the X term by a plain transfer; the F term
by 8 plain fee-paying transfers — all from `hardhat/scripts/testonly-d3-activity.js`.

## 15. Net-F3 was reused for the F05 no-restart control after F04 — [this session's own judgment call]
Its state was already consumed by F04 (a distribution is not relevant to the control). The control edited
its genesis file; the original file was restored afterwards and both versions are kept
(`genesis-before-F05b-control.json`, `genesis-after-F05b-control-edit.json`).

## 16. Extraction ran concurrently on several networks and the chains kept moving — [this session's own judgment call]
Several `testonly-settle.js` runs executed in parallel on a loaded host. The range end L is the head at
the tool's start, while the real transaction was mined later (e.g. F02: L=330, tx in block 540); this is
harmless to the accounting because every term is computed for the fixed range `[1,L]`, but it means the
"distribution block" differs from L. The tool's balances for the post-distribution check are read at the
distribution block itself, not at L.

**Update to item 3:** Groups E and F are no longer "not attempted" — see the result table for each ID.

## 17. Group E was run on three networks in parallel; one transient RPC failure forced a re-run of Net-E60 — [this session's own judgment call]
See FINDINGS.md item 15. E15/E30/E60 benchmarks ran concurrently to save wall-clock time; Net-E60's first
run aborted in its precondition phase on one transient `Internal error` from `eth_call` (before anything was
sent) and was repeated alone; Besu's `--rpc-gas-cap` default (100,000,000) was left unchanged and recorded.

## 18. The Group A start-of-network checks were NOT repeated on the follow-up networks — [this session's own judgment call] — **UPDATE (second follow-up pass): A14 was executed for 20 baseline networks (static, with a negative control) and 21 networks (live block-0 state root), see item 22; A01–A13 were still not repeated live on the follow-up networks**
The document asks for A01–A05/A11–A14 on every network before any transaction. For the 11 follow-up networks only a
**static** check was done afterwards: the bytecode injected into each `genesis.json` for the 6 fixed addresses hashes
to the compiled runtime hashes (`04-results/followup-genesis-code-check.json`, all 66 comparisons match), and the
contract sources used (baseline copy, the Hardhat build inputs, and the owner's original `NewSur/Plan` tree) are
byte-identical (`evidence/00-baseline/followup-source-integrity.txt`). A live read of `eth_getCode`, `getValidators`,
`everActivated`, `statusNonce` etc. at the start of each follow-up network was not performed; the same builder produced
the earlier networks whose A-group results are in the table, and every follow-up test that depended on that state
(founders active, board seeded, history seeded) behaved accordingly.

---

# Second follow-up pass (2026-10-03): combined F6 test, A14, F07 with the default heap

Same rules as before: no contract or policy change, no fork, path L not started, SUPERSEDED rows kept. Items below are this session's own
judgment calls unless stated.

## 19. The first Net-F6 attempt was discarded; its activity script had two bugs — [this session's own judgment call]
The first activity script sent a transaction only on every other block (so the membership and direct-inflow transactions, keyed to
specific even block numbers, were never sent) and crashed reading a not-yet-mined block before saving its evidence. The transition
at block 100 had already passed, so M and X could no longer be placed at X. The network was stopped and archived as `nets/Net-F6-attempt1`
(`logs/Net-F6-attempt1`, `logs/v5-scripts/F6-activity-attempt1.out`), and **Net-F6 was rebuilt from scratch with a corrected script**
(a transaction in every block; membership and inflow timed to block 99/100). Only the rebuilt network is used in the report. The
attempt-1 genesis is not part of the A14 scan.

## 20. Design of the combined test differs from the document's F-network recipe, and F04 was only simulated — [this session's own judgment call, forced by a contract property]
- The document's F networks use one transition at X=300; this follow-up used X=100 and **three staged transitions** (100→3, 150→2,
  200→4 SUR) plus one seeded history entry `[(100, 3 SUR)]` (TEST-ONLY-SEED), so that three ranges of one network give R=cap, R<cap and R>cap.
- A network has exactly **one successful distribution before the 23 h lock**. The combined accounting (range `[1,149]`, R=cap) used it.
  F03 (a rejection) does not consume it and was mined; **F04 was therefore run as an `eth_call` simulation, not as a mined transaction**
  (a mined F04 success would have needed a second distribution ≥ 23 h later). The earlier mined F04 (Net-F3) stands as the real-transaction evidence.
- The coordinated range ends at 149, so the later staged transitions (150, 200) are only exercised through F03/F04's ranges.

## 21. `testonly-settle-v2.js` replaces v1 for this pass; v1 is unchanged and was used for all earlier runs — [this session's own judgment call]
v2 adds per-block conservation for **every** block (including non-empty ones) and a `STATIC_ONLY` simulation mode. The earlier D02/D06/F02–F04 evidence
was produced by v1 (which cross-checked only empty blocks per block and the range total via the equation); both tools are in `hardhat/scripts/`.

## 22. A14 method and its judgments — [this session's own judgment call]
- **Expectation follows each network's build recipe.** The four networks Net-L01, L02, L04, L05 were built with `SEED_FOUNDATION=0` (recovered from the
  original build commands in the session transcript); their FoundationDAO is therefore expected to be empty. My first scan did not know this and reported
  61 deviations on each; that was an error in my expectation, not in the genesis, and is disclosed here and in FINDINGS.md item 16.
- **Independence:** the expected alloc is derived from a fresh deploy of each real contract plus analytically computed seed slots, not read from the builder's
  output; two slot kinds are checked by presence only (`validators[a].status`, FoundationDAO name strings), see FINDINGS.md item 16.
- **Assumption:** contract constructors write only plain (sequential-slot) variables.
- **Live leg without enumeration:** `debug_storageRangeAt`/`debug_accountRange` returned empty results, so the node's block-0 `stateRoot` was compared with a
  Merkle-Patricia root computed in-house (`v5-mpt.js`, validated by the comparison itself). For 18 stopped networks **one node was started read-only
  (no mining, no transactions) and stopped again** purely to read block 0.
- A tampered-genesis **negative control** was run to prove the scan can fail (evidence: `A14-negative-control.json`, `A14-negative-control-tampered-genesis.json`).
- Net-F6-attempt1 and the fork are outside the expected-alloc scan (see items 19 and the A14 row).

## 23. F07 re-run: only node5 had its heap cap removed — [as requested; details are this session's choices]
Net-F5b mirrors Net-F5 (transition at 300 on nodes 1–4; node5's config without it). **Node5 alone** was started without `JAVA_OPTS` (Besu reports
`Maximum heap size: 7.94 GB`, 25% of RAM); nodes 1–4 kept `-Xmx512m` (as in every other test; they had never failed). Heap usage was sampled with `jcmd`/`jstat`
from the installed Temurin JDK (not a Besu feature) every 60 s, process memory every 15 s. The observation window is finite (see FINDINGS.md item 18); "no
OutOfMemoryError" means *not within that window*.
