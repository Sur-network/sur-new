# Execution order (summary — not a literal terminal transcript)

This is a reconstructed summary of the actual execution order, not a captured raw shell log
(no `script`/`tee` transcript was running from the start of the session). Every script listed
below is present verbatim in `hardhat/scripts/` or `hardhat-fork/scripts/` and was run with
`node <script>.js` (env-var-configured) or `npx hardhat run <script>.js --network hardhat`.

1. `00-baseline-fingerprint.js` — bytecode hash + storageLayout for the 6 fixed contracts (baseline compile)
2. `testonly-generate-accounts.js` — all test accounts (`TEST-KEYS-DO-NOT-REUSE.json`)
3. `testonly-build-one.js` (baseline, ×6: Net-B, Net-L01, Net-L02, Net-L04, Net-L05, Net-D) — genesis.json per network
4. `testonly-build-one.js` (fork, ×1: Net-Fork) — same, against the compressed-constants fork
5. `testonly-generate-nodes.js` (×7) — node key/config.toml/static-nodes.json per network
6. Launch all 38 Besu nodes (two waves, `-Xmx512m -Xms256m` after the first wave's memory failure — see FINDINGS.md item 2)
7. `testonly-groupA.js` (×7 networks, re-run once more after sufficient blocks for A15)
8. `testonly-b01-timing-rule.js` (Net-B)
9. `testonly-b02-suspend-v5.js` (Net-B)
10. `testonly-net-l01-cl01.js` (Net-L01) + manual staticCall follow-up to decode exact revert reasons
11. `testonly-net-l02-cl02.js` (Net-L02)
12. `testonly-net-d-d01-d02.js` (Net-D) — D01/D02/D03
13. `testonly-fork-sequence.js` (Net-Fork) — corrected D01 edge cases, D02'/D04'/D05'
14. `testonly-fork-ratepath.js` then `testonly-fork-ratepath-v2.js` (Net-Fork) — L1-L3 rate-change path (first attempt had 2 script bugs, see FINDINGS.md item 5; corrected run via inline follow-up confirmed execution)
15. `testonly-net-l04-cl04.js` (Net-L04) — C-L04 part 1 (C6 join/activate, P1/T1/D1, suspensions, V3 exit)
16. `testonly-net-l05-cl05.js` (Net-L05) — C-L05-2/3a/3b (first run had the same struct-ordering bug; corrected inline follow-up)
17. `testonly-b03-activate-c6.js` (Net-B) — B03
18. `testonly-b04-b05-recover-v5.js` (Net-B) — B04 + time-bounded single-attempt B05
19. `testonly-net-l04-cl04-part2.js` (Net-L04) — recovery + C-L04-2/3(part2)/5
20. `testonly-b06-equivalence.js` (Net-B) — B06, adjusted for Besu's historical-state limit (FINDINGS.md item 7)
21. Ad-hoc inline `node -e '...'` diagnostics (A04 code-hash sweep, A12, C-REG-3, Besu tarball hash check, struct-field verification) — not saved as standalone files, each run's output is in this report/evidence
22. (post-review correction pass) Single read-only node restart (no mining, no transactions) on Net-B to query already-mined historical block headers for B01/B07 (`miner`, `extraData` size) — not saved as a standalone file, raw inputs/outputs reproduced in `evidence/04-results/B01-B07-signer-authorization.json`
23. (post-review correction pass) Brief restart of Net-B's 4 active-set nodes to send one real `distributeRewards()` transaction for fresh C-REG-2 evidence — ad-hoc inline command, output saved to `evidence/04-results/C-REG-2-fresh-evidence.json`
24. (post-review correction pass) `testonly-fork-ratepath-FINAL.js` added to `hardhat-fork/scripts/` — a single consolidated, corrected script reproducing the L1-L3 rate-change sequence that succeeded in step 14 (both the struct-field-order fix and the startBlock-margin fix applied together). **Not executed as part of this correction pass** — added for reproducibility only, per the instruction to deliver corrections without running further tests.

All raw per-scenario JSON output is in `evidence/04-results/`. All Besu node logs are in
`logs/<network>/<node>.log`.

## Follow-up pass (2026-10-03) — reconstructed order (same caveat: a summary, not a raw terminal transcript)

Helper scripts: `evidence/03-commands/v5-build-net.sh` (genesis + nodes for one network),
`v5-launch-net.sh` (start nodes, JVM heap capped), `v5-nodectl.sh` (find/stop a node by RPC port),
`count-results.js` (computes the REPORT.md summary counts from the table). Test scripts are in
`hardhat/scripts/` (`testonly-build-one-v5.js`, `v5-lib.js`, `testonly-settle.js`, `testonly-f01.js`,
`testonly-f05.js`, `testonly-f05b-control.js`, `testonly-f06-setup.js`, `testonly-f07.js`,
`testonly-l05-rerun.js`, `testonly-d3-activity.js`, `testonly-e.js`).

25. Build Net-F1…F5, Net-L05a, Net-L05b, Net-D3 (`v5-build-net.sh`); F5's node5 gets a no-transition genesis copy.
26. Launch Net-F1..F4 (20 nodes), then Net-F5 — `v5-launch-net.sh`.
27. `testonly-f05.js` on Net-F4 (rolling restart, X′ = head+300) — started at head 83, finished ≈ block 398.
28. `testonly-f07.js` on Net-F5 (observer; node5 had been started without the transition).
29. After Net-F1 passed block 312: `testonly-f01.js` (Net-F1) → `testonly-settle.js` ID=F02 (Net-F1, SEND=1);
    in parallel F03 (Net-F2, `FORCE_SEND_CAP_EXCEEDED=1`) and F04 (Net-F3).
30. F06: `testonly-f06-setup.js` + launch node7x (original no-transition genesis) after the chain passed X′; evidence saved by an ad-hoc inline script.
31. Net-F4 and then F1/F2/F3 stopped; Net-L05a launched → `testonly-l05-rerun.js` MODE=2; Net-L05b launched → MODE=3.
32. Net-D3 launched → `testonly-d3-activity.js` → `testonly-settle.js` ID=D06 (SHORT_BY=1) → ID=D02-acct (SEND=1).
33. F05 control: Net-F3 restarted, `testonly-f05b-control.js` (genesis edited, no restart); original genesis restored; Net-F3 stopped.
34. Ad-hoc inline probes (not saved as files): trace_block / eth_getBalance far outside the state window on Net-F3 (FINDINGS.md item 11); `besu --help` for the RPC cap defaults.
35. Build and launch Net-E15/E30/E60 (150 payees + 399-entry history seeded) → `testonly-e.js` on each.
36. `v5-genesis-code-check.js` (static check of the injected bytecode in the 11 follow-up genesis files) and the pairwise source-hash comparison saved in `evidence/00-baseline/followup-source-integrity.txt`.
37. Documentation pass: REPORT/FINDINGS/DEVIATIONS/LIMITATIONS/QUESTIONS/README updated; summary counts recomputed with `count-results.js`.

## Second follow-up pass (2026-10-03) — reconstructed order

38. Build Net-F6, Net-F5b, Net-A14 (`v5-build-net.sh`); launch F6 and A14 (all nodes), F5b nodes 1-4 capped (`v5-launch-net.sh`) and F5b node5 **without** the heap cap (`v5-launch-node-nocap.sh`).
39. First F6 activity attempt (script bug, see DEVIATIONS.md item 19) → stop, archive as Net-F6-attempt1, rebuild + relaunch Net-F6; corrected `testonly-f6-activity.js`.
40. `testonly-f07b-monitor.js` on Net-F5b (process memory every 15 s) and a background `jcmd GC.heap_info`/`jstat -gcutil` sampler every 60 s on node5 (`logs/v5-scripts/F07b-jcmd.log`); `testonly-f07.js` with `NET_NAME=Net-F5b`.
41. A14: probes of `debug_storageRangeAt`/`debug_accountRange` (empty results); `v5-mpt.js` validated against block-0 `stateRoot` on three live networks; `testonly-a14.js` (first run with a wrong expectation for four networks → fixed to follow the build recipe, then re-run; negative control on a tampered genesis copy; final run over 20 networks); `testonly-a14-live.js` (21 networks).
42. On Net-F6 once the head passed 262: `testonly-settle-v2.js` ID=F6-F03 (TO=260, FORCE) and ID=F6-F04 (TO=180, STATIC_ONLY) in parallel, then ID=F6-combined (TO=149, SEND=1).
43. Documentation pass; summary counts recomputed with `count-results.js`.
