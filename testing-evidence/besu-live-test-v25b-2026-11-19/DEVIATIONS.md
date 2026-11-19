# Deviations, round 1b

- **D-1** Same harness as round 1 (Docker, fixed-IP bridge per net, named volumes, `JAVA_OPTS -Xms128m -Xmx640m`), copied to a new folder and renamed (prefix `sur25b-`, subnets 172.29.61.0/24 and 172.29.64.0/24, RPC ports 195xx and 196xx, chain ids 425035 and 425038). The old folder was not touched.
- **D-2** Oracle slots overlaid with throw-away keys in genesis storage as in round 1 (Registry.verifier, Distributor.distributionOracle, IdentityRegistry.identityOracle); runtime bytecode unchanged. Values in `evidence/02-genesis/*/build-summary.json`.
- **D-3** Net-T (extra net): TEST-ONLY overlay of probationPeriod 120 s, exitCooldown 60 s, entryWindowSeconds 30 s, recoveryPeriod 60 s, as round-1 Net-T. Needed because "buyer Active with the collateral" and "a Probation seat sold then activated" need a paid entrant and a 7-day probation cannot elapse on Besu. BH-06 is split: BH-06A (Net-A, founder seat, collateral 0) and BH-06B (Net-T, paid entrant, 500,000). Constants are real.
- **D-4** "Probation seat sold then activated without accepting" was done on a paid entrant (Net-T), because on Net-A all founders were activated in BH-02 as specified.
- **D-5** Only one 7-founder net (Net-A) was used; nodes n1..n7 plus n2b.
- **D-6** BH-02 also includes the f=1 stop/restart of round-1 BG-02 and the three-in-one-block activation of BG-12. entryCollateral (550,000) and one open board action (membership fee 450, 1 of 3) remain on the throw-away chain.
- **D-7** In BH-06A two Registry parameter proposals (SlashBps 1000 and 1001) were created to test voter eligibility; both stay open. In BH-14 owners 1 and 7 registered identities to cast votes.
- **D-8** BH-06A checks "no gap above the block period" strictly (max gap <= 2 s); other tests use the round-1 tolerance (<= 4 s). All measured gaps were 2 s outside round-change windows.
- **D-9** `bh01.js` was run twice: the first run's check "7 founder seats" only compared `totalMinted`; the script was corrected to check the seat owners and re-run (the first output was overwritten; both passed all other checks). `syncBoard()` was therefore called twice by the stranger (harmless).
- **D-10** The narrative files could not be written by the test agent (harness rule); they were written afterwards by the orchestrating session from its final report and checked against the raw result JSON files.
- **D-11** `contracts/` changed under the run (`07d61fd`, `a673ff3`); the baseline hash file (`evidence/00-baseline/contracts-sha256.txt`) is from 16:09 and `ValidatorsRegistry.sol` hashes differently now.
- **D-12** Besu node logs of the 7-node net were taken after `destroy` (saved before removal); BH-03 and BH-07b started and stopped nodes with `docker`, so the logs show restarts and stops.
