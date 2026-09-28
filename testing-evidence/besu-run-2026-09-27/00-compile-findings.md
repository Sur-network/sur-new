# Compile-phase findings

## Stack-too-deep in BlockRewardDistributor.distributeRewards (real bug, contradicts deploy-notes)

`sur-contracts-deploy-notes.md` (lines 221-230) claims all 8 contracts compile clean with
`viaIR: false`. Against the actual current source (both languages, per the earlier research
agent), this is false: `hardhat compile` (solc 0.8.24, `viaIR: false`, optimizer runs=200) failed
with:

```
CompilerError: Stack too deep. Try compiling with `--via-ir` (cli) or the equivalent `viaIR: true`
(standard JSON) while enabling the optimizer. Otherwise, try removing local variables.
 --> contracts-test-fork/BlockRewardDistributor.sol:537:17:
    |
537 |                 validators,
    |                 ^^^^^^^^^^
```

File: `BlockRewardDistributor.sol`. Function: `distributeRewards` (external, line 478), at the
call site to the internal `_payValidators(...)` helper. Root cause: too many simultaneously-live
local variables in `distributeRewards` at that call site (4 calldata/value params + ~9 locals
computed inline before the call).

Per the runbook's explicit instruction, this was **not** worked around with `viaIR`. Fix applied
(test-fork only, behavior-preserving):
1. Reordered `foundationAmount`/`treasuryAmount` computation to after the `_payValidators` call
   (they don't feed into it and don't depend on its result) — insufficient alone, error persisted
   at the same call site.
2. Extracted the epoch pre-computation block (membership-fee folding, fee-burn math, `_sumBlocks`/
   `_checkPhysicalMaximum` calls) into a new private helper `_prepareEpoch(...)` returning a new
   `EpochPrep` memory struct — bundling 4 result scalars into 1 struct pointer. This resolved it:
   `Compiled 13 Solidity files successfully (evm target: paris).`

No `require()` conditions, event emissions, or execution order changed — only *where* each value
is computed, and that 4 scalars now live in one memory struct instead of 4 separate stack locals.
