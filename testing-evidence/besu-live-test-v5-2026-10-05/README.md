# Besu round 5 — contracts v2.1.0 (5 October 2026)

This folder holds the parts of the round-5 results that the Plan documents rely on. The complete package (raw node logs, genesis files, node configs and keys, tool sources, all result JSON) is kept outside the Plan:

- Package: `D:\Amir\Business\SUR\Test\final-package-work\round5\sur-besu-round5-v2.1.0-results.zip` (1,311,990 bytes)
- sha256: `3aab4ee3aea0471f60788f95dec9c437bdf74bdf7fe129840c176ee7af1aaa5a` (file `...zip.sha256` next to it)
- Inside the package: `MANIFEST.sha256` with 198 files; verified after extraction with `sha256sum -c`, no failures.

## What is in this folder
| File | Content |
|---|---|
| `REPORT.md` | the 28-row result table: **24 PASS, 4 NOT-RUN** (counted again by hand when the Plan copy was made) |
| `FINDINGS.md` | measurements and observations |
| `DEVIATIONS.md` | what exactly was tested, the test-fork, the back-dated genesis, disclosed faults |
| `LIMITATIONS.md` | what the results do not show |
| `evidence/00-baseline/r5-plan-contracts-sha256.txt`, `r5-plan-head.txt` | sha256 of the tested `contracts/` and `contracts-fa/` files and the Plan HEAD |
| `evidence/00-baseline/r5-testfork-sha256.txt`, `r5-testfork.diff` | the test-fork sources and their exact difference from the tested contracts |
| `evidence/05-raw/count-results.txt` | output of the counting script |

Every file above is a byte-for-byte copy of the package file; each was compared after copying.

## Only in the package (not copied here)
Result JSON (`A-live-*`, `Net-R5-A-board-hook-floor`, `Net-R5-B-month-refresh`, `Net-R5-F-dispute`, `R5-A14-live-stateroot`, `R5-F-partM-chain-record`), console output of every script (`logs/r5-scripts/`, including the Part M run of the fork and the negative control), raw Besu node logs, genesis and seed sources of every network, tool scripts, test-only keys. The assertion counts in those JSON files were checked against the report: 32, 20 and 25 behaviour assertions (all pass), Group A 58, 58 and 59 (all pass).

## How to read the results
- Three evidence classes that must not be merged: **baseline** (Net-R5-A, Net-R5-B), **test-fork** (Net-R5-F; compressed month and Registry time constants), **back-dated genesis** (Net-R5-B).
- No real calendar-month boundary was crossed on the real contracts. The boundary was crossed three times live on the test-fork only.
- The results describe the contract hashes in `r5-plan-contracts-sha256.txt`. If those files change, the results no longer apply to the new files.
- IdentityRegistry and ServiceStaking changes, the static unexpected-storage scan, the mass-failure and expiry paths, and the real-time path L were not run (rows R5-X1 to R5-X4).
- This is not a production-readiness statement.
