# SUR Besu live test — v4 (2026-10-02, follow-up passes 2026-10-03)

Executed per `sur-besu-live-test-brief-v4.md` (revision 1), with an explicit owner-authorized
scope decision for this session (see `REPORT.md`'s header and `DEVIATIONS.md`).

**Start here:** `REPORT.md` for the full per-ID result table, `FINDINGS.md` for unexpected results,
`DEVIATIONS.md` for every deviation from the brief (with reasoning), `LIMITATIONS.md` for open
items, `QUESTIONS.md` for items needing the owner's decision.

**Follow-up pass (2026-10-03):** L05 re-runs on fresh networks, independent D02 accounting (Net-D3), D06,
Group F (Net-F1..F5) and Group E (Net-E15/E30/E60) — all on the unmodified baseline contracts. New items are
labelled in the result table; superseded first-attempt rows are kept and marked SUPERSEDED. `evidence/03-commands/
count-results.js` recomputes the summary counts from the table. Helper shell scripts for building/launching/stopping
networks are in `evidence/03-commands/` (`v5-*.sh`); the follow-up test scripts are in `hardhat/scripts/`
(`v5-lib.js`, `testonly-settle.js`, `testonly-f*.js`, `testonly-l05-rerun.js`, `testonly-e.js`, ...).
`evidence/05-raw/E-ratio.csv` is the Group E block-ratio record.

**Second follow-up pass (2026-10-03):** combined F6 test (non-empty blocks across the reward transition with fees, a membership fee and a direct inflow, full §D accounting; F03 mined rejection; F04 simulation), A14 (static scan + live block-0 state-root leg + negative control) and the F07 re-run with the default Besu heap (Net-F5b). New scripts: `hardhat/scripts/testonly-settle-v2.js`, `testonly-f6-activity.js`, `testonly-a14.js`, `testonly-a14-live.js`, `v5-mpt.js`, `testonly-f07b-monitor.js`; `evidence/03-commands/v5-launch-node-nocap.sh`. `nets/Net-F6-attempt1` is a discarded first attempt kept for transparency (DEVIATIONS.md item 19). Each node directory now also contains its `data/static-nodes.json` (only the chain database in `data/` is excluded from the package).

```
REPORT.md                    <- full result table + summary
FINDINGS.md                  <- unexpected results, raw evidence
DEVIATIONS.md                <- deviations from the brief, with reasoning
LIMITATIONS.md               <- open items
QUESTIONS.md                 <- for the owner
baseline/                    <- read-only copy of contracts/ + contracts-fa/ as tested
hardhat/                     <- baseline-code tooling (testonly-* scripts, compiled artifacts)
hardhat-fork/                <- TEST-FORK-only tooling (3 compressed constants, see REPORT.md)
nets/<network>/               <- genesis.json + per-node key/config.toml/static-nodes.json
evidence/
  00-baseline/                <- sha256 tables, bytecode/storageLayout fingerprint, fork diff+hash
  01-environment/              <- env.json (Besu/Java/Node/solc/OS versions)
  02-genesis/<network>/         <- genesis.json + seed summary per network
  04-results/<ID or network>.json <- raw per-scenario evidence
logs/<network>/<node>.log      <- raw Besu node logs
TEST-KEYS-DO-NOT-REUSE.json    <- all test account keys (local dev-chain only, never reused anywhere real)
```

> این بسته نتیجهٔ آزمون روی Besu با تنظیمات آزمایشی و ابزارهای آزمایشی است. موفقیت یا شکست این
> آزمون‌ها به‌معنای آمادگی یا عدم آمادگی production نیست. RewardRouter و ابزار genesis production
> پیاده‌سازی نشده‌اند و این بسته آن‌ها را آزمون نکرده است. داده‌های گروه E فقط benchmark مصنوعی هزینه‌اند
> و gasLimit تولیدی را تعیین نمی‌کنند. gasLimit تولیدی، مسیر رفع «پاداش واقعی بیش از سقف» برای بازهٔ گذشته،
> صفحهٔ حکمرانی نرخ در داشبورد، و اجرای زمان‌واقعیِ مسیر L (مرحلهٔ L4) همچنان باز هستند.
