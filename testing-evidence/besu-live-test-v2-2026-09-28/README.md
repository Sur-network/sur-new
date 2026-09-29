# Live Besu/QBFT test, round 2 — 2026-09-28/29 — ALL 10 phases complete

Full report: `REPORT.md`. Ran against a from-scratch 15-node Besu 26.9.0 QBFT network built with the
**current** contract source (post N01/P01–P06/C01/refreshBoard-redesign/`<=`-cap-fix), per
`sur-besu-test-status.md` v2. This is the first real-network confirmation of all of that.

Only a subset of the test scripts and finding write-ups were provided to Claude (the ones with
genuinely new content worth preserving); many more existed during the actual test run (per the
`logs/phase*-raw.json` references throughout `REPORT.md`) but were not uploaded and are not in this
folder — this is a partial evidence set, not the complete raw output. `accounts.json` (the funded
test-account keypairs) was also not provided.

## What's here
- `REPORT.md` — the full test report (18 sections, master pass/fail table in §15).
- `phase10-stage1-revival.md`, `phase10-stage2-3-transitions.md` — first-ever real-Besu confirmation of the N04 emergency-recovery technical mechanism.
- `identity-migration-permanent-finding.md` — unplanned finding: `migrateIdentity` permanently blocks `hasIdentity()` on the old address (confirmed intentional by the contract's own doc comments, referencing SIP001/SIP002 §3.4/7/8 — see `sur-master-open-items.md` for the product-decision flag this raises for `ValidatorsBoard.voteFor` eligibility).
- `scripts/` — 6 of the test's own driver scripts (Phase 4 continuation scenarios, Phase 7, Phase 8). Illustrative of method (explicit `nonce`/`gasPrice`/`gasLimit`/`type:0` on every send, per the report's §4 finding), not a runnable suite (missing `accounts.json`, `hardhat.config.js`, and most other phase scripts).

## Verified against current contract source (by Claude, not re-run)
Spot-checked the report's specific claims against `contracts/`: `permanentlyExited` revert string, `RecoveryPeriod`/`ExitCooldown` floor messages, `perPaymentCap`/`periodCap` using `<=`, `FOUNDATION_SHARE_BPS=1500`, `_tryChallenge`'s strict `>`, `FoundationDAO.proposeExecute`'s `value==0` requirement and `PROPOSAL_EXPIRY`, and `IdentityRegistry`'s `hasIdentity`/`registerIdentity`/`migrateIdentity` interaction — all match exactly what the report describes.

## Honest gaps this round left open (all disclosed in the report itself)
- Phase 3 scenario 8 (exit with no pending case) — not run as a dedicated case.
- Phase 4 scenario 4 (challenger-vs-incumbent exact tie) — not run as a dedicated case; inferred from scenario 1.
- Phase 4 scenario 7 layer 2 (direct storage-write bypass of `permanentlyExited`) — confirmed **not testable** on production Besu (no `debug_setStorageAt`-equivalent JSON-RPC method).
- Phase 6 P05 overlap/gap checks — not isolated from the (deliberately un-shrunk) 23h `MIN_DISTRIBUTION_INTERVAL` gate.
- Phase 10 — same validator set reused across the `blockheader` window (not a substituted emergency set); the human 5-of-7 custodian signature process has no code to test.
