# Phase 3 — 4-node Besu/QBFT network verification

## Genesis injection bug found and fixed: missing EVM hard-fork blocks

First launch attempt of node1 crashed at startup:
```
Caused by: java.lang.IllegalStateException: Failed validator smart contract call:
ValidationResult{invalidReason=Optional[EXECUTION_HALTED], errorMessage=Optional[Invalid opcode: 0x1c]}
	at org.hyperledger.besu.consensus.qbft.validator.ValidatorContractController.decodeResult(...)
```
Root cause: our `genesis.json`'s `config` object had no hard-fork activation blocks at all, so Besu
defaulted to a pre-Constantinople ruleset when calling `ValidatorsRegistry.getValidators()` —
opcode `0x1c` (SHR, added in Constantinople/EIP-145) was rejected as invalid. Fixed by adding
`homesteadBlock` through `londonBlock` (all `0`) plus `zeroBaseFee: true` to `config`. Confirmed in
node1's log after the fix: `Protocol schedule created with milestones: [London:0]`.

## Genuine Besu-on-Windows bug found: `--bootnodes` / TOML `bootnodes` rejects any enode URL

Both the CLI flag `--bootnodes="enode://...@127.0.0.1:30301"` and the equivalent TOML
`bootnodes=["enode://...@127.0.0.1:30301"]` failed identically on all 3 non-bootnode nodes:
```
Failed to start Besu: Illegal char <:> at index 5: enode://452c...@127.0.0.1:30301
```
Isolated the cause with two follow-up tests: (1) a fabricated enode with a dummy 64-byte all-`a`
key produced the *identical* error, and (2) a plain string `"aaaaa:bbbb..."` (colon at index 5,
no `enode` scheme at all) produced the exact same error. This proves Besu 26.9.0's `--bootnodes`
option is, on this Windows build, running the value through a `java.nio.file.Path`-style validator
(Windows paths only permit a colon at index 1, e.g. `C:\...`) instead of URI parsing — a real
Besu/Windows compatibility bug, not a mistake in our enode string. `besu --help` confirms
`--bootnodes` is documented to take `enode://id@host:port` directly, so this isn't a
wrong-flag-name issue either.

**Workaround used** (not a viaIR-style hidden fix — a standard, documented Besu alternative):
placed a `static-nodes.json` (`["enode://...@127.0.0.1:30301"]`) directly in each of node2/3/4's
data directory instead of using `--bootnodes`/`bootnodes=`. Besu reads this file directly at
startup, bypassing the broken CLI/TOML converter entirely. Worked immediately.

## Verification: all 4 nodes agree on genesis + injected contract code

```
eth_getBlockByNumber(0) .hash  — identical on all 4 nodes: 0xe73bc939e927a38cd8ae19273a3fa553e911dcbf0f34b0c73880a5107c17ae9f
eth_getBlockByNumber(0) .timestamp — 0x6ab97802 (= 1790539778, our chosen genesis timestamp) on all 4
eth_getCode(0x3333...3333) — identical 37,218-char bytecode (sha256 5e39eb51ab25464ee4f5a6207750bff67bbef7d674c96550fc60f8cc95968a59) on all 4 nodes
```
This is the first real confirmation the runbook asked for: genesis-injected code+storage (no
constructor) produces an identical, working contract from block 0 across every node.

## Verification: QBFT proposer rotation is driven by ValidatorsRegistry.getValidators()

Blocks 1-8 `miner` field, read from node1's RPC:
```
block 1 miner 0x6a7d42ba3ed8d8ab61923428ebe9df874b154166  (validator2)
block 2 miner 0xec23c853f1b1bd277dccd8d74ffd12a4130170af  (validator3)
block 3 miner 0xf660689a2766880790b2d10a8bd7ea0ff13ad50b  (validator4)
block 4 miner 0xf852e60f86de01320bbc66794e8b17bcf5843053  (validator1)
block 5 miner 0x6a7d42ba3ed8d8ab61923428ebe9df874b154166  (validator2)
block 6 miner 0xec23c853f1b1bd277dccd8d74ffd12a4130170af  (validator3)
block 7 miner 0xf660689a2766880790b2d10a8bd7ea0ff13ad50b  (validator4)
block 8 miner 0xf852e60f86de01320bbc66794e8b17bcf5843053  (validator1)
```
Clean round-robin across exactly our 4 registry-seeded validators, confirming
`qbft.validatorcontractaddress` really is reading `ValidatorsRegistry.getValidators()` for real
consensus proposer selection — the runbook's second core question, confirmed on a real network.

## Node endpoints
- node1: http://127.0.0.1:8541 (bootnode, p2p 30301)
- node2: http://127.0.0.1:8542 (p2p 30302)
- node3: http://127.0.0.1:8543 (p2p 30303)
- node4: http://127.0.0.1:8544 (p2p 30304)
