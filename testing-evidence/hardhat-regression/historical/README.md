# Historical tests (NOT part of the current suite)

`reproduce_bug3_stale_board_votes.js` and `reproduce_bug5_refresh_griefing.js` were written for an earlier ValidatorsBoard
(before the final decisions P01/P02 of 2026-09-28). They do not run against the current contract because behaviour changed
intentionally:

* bug3 built a board by writing storage directly and called voteAction without a Registry. The current board asks
  ValidatorsRegistry for every member's status, so a mock Registry is required, and an invalidated action now REVERTS.
* bug5 called refreshBoard() twice in a row to prove the board version does not move. refreshBoard() is now accepted once every
  30 days, so the second call reverts by design.

Their intent is covered by the current suite:
* stale votes of former members / invalidated actions -> test_P01_P02_board.js  (P01-e, P01-f, P01-g, P02-d..g)
* refresh without a real composition change does not bump the version -> test_P01_P02_board.js (P01-c)

They are kept only so an old finding can be traced. Do not treat a failure of these two files as a defect.
