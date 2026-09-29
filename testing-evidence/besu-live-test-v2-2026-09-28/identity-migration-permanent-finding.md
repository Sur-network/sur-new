# Finding: `migrateIdentity` permanently blocks `hasIdentity()` on the old address, even after re-registering

Discovered accidentally by reusing `candidateG` as both Phase 8's `migrateIdentity` subject and a
Phase 4 board voter. After `IdentityRegistry.migrateIdentity(candidateG, boardOutside1)` (Phase 8),
`candidateG.voteFor(...)` in Phase 4 reverted with `"ValidatorsBoard: register identity before
voting"` — confirmed via `eth_call` simulation for the exact reason string.

**Tested whether re-registering fixes it**: called `candidateG.registerIdentity(...)` again. The
transaction succeeds (`status: 1`, no revert) — but `hasIdentity(candidateG)` **still returns
`false`** immediately afterward. This confirms `hasIdentity()`'s `migratedTo == address(0)` check
is not cleared by `registerIdentity()`, which only touches `registered`/`personType`/`name`. Once
an address is the source of a `migrateIdentity` call, it is **permanently** excluded from
`hasIdentity()` — there is no on-chain path back to `true` for that specific address, even though
`registerIdentity()` itself doesn't reject the call or signal anything is wrong.

**Real-world implication**: if `migrateIdentity` is ever used on an address that is also an active
validator relying on `hasIdentity()` for `ValidatorsBoard.voteFor()` eligibility, that validator
permanently loses board-voting eligibility under that address — the only recovery would be
migrating to a *different* address, which isn't meaningful for an already-registered validator
whose identity is tied to their existing validator address. Whether this is intended behavior
(identity migration is meant to be terminal for the old address, full stop) or an oversight
(re-registration should perhaps be allowed to "re-claim" `hasIdentity` on an old, no-longer-in-use
migration source) is a product decision, not something this test can resolve — flagged here as an
observed fact, not a verdict.
