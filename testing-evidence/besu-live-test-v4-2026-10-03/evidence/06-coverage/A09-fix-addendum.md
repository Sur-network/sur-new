# Addendum to the Group A coverage table — A09 after the test-builder fix (2026-10-04)

`A-coverage-followup-networks.md` (third pass) records, for the 15 follow-up networks, A09 = PASS+DISC: members and `boardVersion` pass, `lastBoardRefreshAt` is 0 while the genesis-builder spec asserts the genesis timestamp. That table is **kept unchanged** (it describes the pre-fix genesis).

The test builder was fixed afterwards (`lastBoardRefreshAt` = genesis timestamp when the board is seeded). Live Group A on the networks built by the fixed builder, each checked before any transaction:

| Network | Builder | Group A live | A09 `lastBoardRefreshAt` | Notes |
|---|---|---|---|---|
| Net-BR | fixed | 65/65 (`A-live-Net-BR.json`) | equals the genesis timestamp (1791056279) | also used for the board-refresh behaviour test (21/21, `Net-BR-board-refresh.json`) and C-L04-6b run 1 |
| Net-L04g | fixed | 65/65 (`A-live-Net-L04g.json`) | equals the genesis timestamp | C-L04-6b run 2 (15/15, `Net-L04g-CL04-6b.json`) |
| Net-BR0 | **negative control** (old behaviour, `BUILDER_BOARD_REFRESH_ZERO=1`) | 64/65 (`A-live-Net-BR0.json`) | 0 — the single failing assertion | genesis identical to the pre-fix Net-L04f (`A09-fix-genesis-diff.json`); read-only |

The earlier networks (33 of them, listed in `04-results/A09-fix-genesis-scope.json`) were **not rebuilt**; they keep the value 0. A09's other assertions (members, version) and all other Group A cells of the third-pass table are unaffected by the fix.
