# Hardhat regression / reproduction scripts (local EVM — NOT Besu)

Setup: `npm i hardhat@^2.22 @nomicfoundation/hardhat-toolbox@hh2 ethers solc`, then copy the current contracts next to the scripts as
`contracts_src_ValidatorsRegistry.sol`, `contracts_src_ValidatorsBoard.sol`, `contracts_src_ValidatorsTreasury.sol`, `contracts_src_SurAddresses.sol`,
run `node compile3.js` (Registry) and `node compile_board_treasury.js` (Board/Treasury), then `npx hardhat run scripts/<name>.js`.

| script | what it proves |
|---|---|
| test_verification_flow.js | the 6 core verification/appeal/slash paths (10 validators) |
| reproduce_bug1_mass_failure_bypass.js | case cannot advance before its mass-failure check |
| reproduce_bug2_delivery_conflict.js | validator self-confirmation closes an open delivery dispute |
| reproduce_bug3_stale_board_votes.js | stale votes of former board members cannot execute a payment (boardVersion) |
| reproduce_bug4_partial_exemption.js | per-decision (not per-epoch) mass-failure check |
| reproduce_bug5_refresh_griefing.js | refreshBoard() with an identical member set does not bump boardVersion |
| reproduce_N01_stale_lock_wipe.js | a closed (exempt) case cannot be reopened via assertDeliveryDisputed |
| test_N01_layer2_lock_binding.js | a resolver may clear the pending-slash lock only if it belongs to its own epoch |
| test_recovery_period_bound.js | recoveryPeriod must exceed MASS_DEMOTION_WINDOW (proposal-time check) |
| test_stale_votes.js | cross-contract: Board.clearStaleVotes reads demotedAt through the 6-output getValidatorInfo ABI correctly (early call reverts; succeeds after recoveryPeriod+30d) |
| layout_compare.js | genesis helpers match the real contracts' storage layout (shared variables) |

Limits: Hardhat, not Besu/QBFT. Scripts print results; they are not a packaged test framework. Scripts named reproduce_* were written to fail before the
corresponding fix; on current code they show the fixed behaviour.
