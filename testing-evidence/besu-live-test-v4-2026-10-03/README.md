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

**Third follow-up pass (2026-10-03/04):** C-L04-6 on the fresh seeded Net-L04f (31/31), Group A (A01-A15) per network and test for the follow-up networks via fresh twin networks (Net-T-F1/F2/F3/F4/F6/L05/D3/E15/E30/E60) with proven genesis equivalence (15/15), the A09-spec finding (`lastBoardRefreshAt`), and the plan for the real-time path L (`PLAN-path-L-real-time.md`, **not started**). New scripts: `hardhat/scripts/testonly-a-live.js`, `testonly-twin-equivalence.js`, `make-a-coverage.js`, `testonly-cl04-6.js`; `evidence/03-commands/v6-build-twins.sh`; per-network coverage table in `evidence/06-coverage/`; raw results `evidence/04-results/A-live-*.json`, `A-twin-equivalence.json`, `Net-L04f-CL04-6.json`; hashes of the new result files in `evidence/06-coverage/new-results-sha256.txt`.

**Fourth pass (2026-10-04):** A09 fixed in the test builder (`testonly-build-one-v5.js`, `testonly-build-one.js`; pre-fix copies `*.pre-A09-fix`) and verified on Net-BR / Net-L04g with a negative control Net-BR0 (`testonly-board-refresh.js`, `04-results/Net-BR-board-refresh.json`, `Net-BR0-board-refresh.json`, `A-live-Net-BR*.json`, `A-live-Net-L04g.json`, `A09-fix-genesis-diff.json`, `A09-fix-genesis-scope.json`, `A14-*-A09fix*.json`); C-L04-6b (`testonly-cl04-6b.js`, `Net-L04g-CL04-6b.json`, superseded run 1 `Net-BR-CL04-6b-run1-14of15.json`). Hashes of the new files of this pass: `evidence/06-coverage/new-results-sha256-pass4.txt`.

```
REPORT.md                    <- full result table + summary
FINDINGS.md                  <- unexpected results, raw evidence
DEVIATIONS.md                <- deviations from the brief, with reasoning
LIMITATIONS.md               <- open items
QUESTIONS.md                 <- for the owner
PLAN-path-L-real-time.md     <- execution plan for the real-time path L (NOT executed; awaits separate authorisation)
baseline/                    <- read-only copy of contracts/ + contracts-fa/ as tested
hardhat/                     <- baseline-code tooling (testonly-* scripts, compiled artifacts)
hardhat-fork/                <- TEST-FORK-only tooling (3 compressed constants, see REPORT.md)
nets/<network>/               <- genesis.json + per-node key/config.toml/static-nodes.json
evidence/
  00-baseline/                <- sha256 tables, bytecode/storageLayout fingerprint, fork diff+hash
  01-environment/              <- env.json (Besu/Java/Node/solc/OS versions)
  02-genesis/<network>/         <- genesis.json + seed summary per network
  04-results/<ID or network>.json <- raw per-scenario evidence
  06-coverage/                 <- Group A coverage table per network and test (third pass) + hashes of the new result files
logs/<network>/<node>.log      <- raw Besu node logs
TEST-KEYS-DO-NOT-REUSE.json    <- all test account keys (local dev-chain only, never reused anywhere real)
```

> این بسته نتیجهٔ آزمون روی Besu با تنظیمات آزمایشی و ابزارهای آزمایشی است. موفقیت یا شکست این
> آزمون‌ها به‌معنای آمادگی یا عدم آمادگی production نیست. RewardRouter و ابزار genesis production
> پیاده‌سازی نشده‌اند و این بسته آن‌ها را آزمون نکرده است. داده‌های گروه E فقط benchmark مصنوعی هزینه‌اند
> و gasLimit تولیدی را تعیین نمی‌کنند. gasLimit تولیدی، مسیر رفع «پاداش واقعی بیش از سقف» برای بازهٔ گذشته،
> صفحهٔ حکمرانی نرخ در داشبورد، و اجرای زمان‌واقعیِ مسیر L (مرحلهٔ L4) همچنان باز هستند. C-L04-6 و C-L04-6b اجرا و پاس شده‌اند؛ شکست A09-spec (lastBoardRefreshAt) با اصلاح ابزار genesis آزمایشی رفع شد و در دور چهارم تأیید شد (۳۳ شبکهٔ قدیمی مقدار صفر را نگه می‌دارند).
> توضیح اصلاحی (۲۰۲۶-۱۰-۰۴): نوشتن و assert کردن `lastBoardRefreshAt` برابر timestamp genesis در ابزار genesis production تصمیم باز نیست؛ الزام موجود پروژه و بخشی از پیاده‌سازی باقی‌ماندهٔ T02 است.
