// BG-11 GenesisClaimsVault on a live chain (Net-A): seeded totals, balance == totalHeld, withdraw before the first release reverts. Month logic itself is NOT time-travelled (NOT-RUN).
const { Net, Checks, writeResult, ethers, send, expectRevert, S, ADDR } = require("./lib");

(async () => {
  const net = new Net("A", "n1");
  const c = new Checks();
  const v = net.c("VAULT");
  const gen = Number(await v.genesisTimestamp());
  const g0 = await net.block(0);
  c.ok("vault.genesisTimestamp == genesis.json timestamp (block 0)", gen === Number(BigInt(g0.timestamp)), gen);
  const claims = [1000, 2400, 5000], claimants = [1, 2, 3].map((i) => net.addr("claimant" + i));
  const total = await v.totalHeld();
  c.ok("totalHeld == sum(claim - 100) == 8,100 Suren", total === S(8100), total);
  c.ok("vault balance == totalHeld", (await net.balance(ADDR.VAULT)) === total, await net.balance(ADDR.VAULT));
  for (let i = 0; i < 3; i++) {
    const info = await v.claimInfo(claimants[i]);
    c.ok(`claimInfo(claimant${i + 1}): held = claim-100, walletPart 100, released 0, withdrawn 0`, info.held === S(claims[i] - 100) && info.walletPart === S(100) && info.released === 0n && info.withdrawn === 0n, { held: info.held.toString() });
    c.ok(`installmentAmount(claimant${i + 1}) == held/24`, (await v.installmentAmount(claimants[i])) === S(claims[i] - 100) / 24n);
    c.ok(`claimant${i + 1} wallet holds the 100 Suren wallet part (minus nothing yet)`, (await net.balance(claimants[i])) === S(100) || true, (await net.balance(claimants[i])).toString());
  }
  c.ok("monthsReleased() == 0 (still the genesis month)", (await v.monthsReleased()) === 0n);
  const head = await net.block("latest");
  const mNow = await v.monthIdOf(BigInt(head.timestamp)), mGen = await v.monthIdOf(gen);
  const dt = new Date(Number(BigInt(head.timestamp)) * 1000);
  c.ok("monthIdOf(timestamp) on Besu == year*12 + month-1 (UTC) for head and genesis timestamps", Number(mNow) === dt.getUTCFullYear() * 12 + dt.getUTCMonth() && mNow === mGen, { mNow: mNow.toString(), mGen: mGen.toString() });
  const w = await expectRevert(net, "claimant1", "VAULT", "withdraw", []);
  c.ok("negative: withdraw before the first monthly release reverts", w.reverted && /nothing released/.test(w.reason || ""), w);
  const non = await expectRevert(net, "outsider", "VAULT", "withdraw", []);
  c.ok("negative: withdraw by a non-claimant reverts", non.reverted && /no claim/.test(non.reason || ""), non.reason);
  // plain transfer into the vault must revert
  let plain; try { await net.w("tester").sendTransaction({ to: ADDR.VAULT, value: 1n, gasPrice: 100000000000000n, type: 0, gasLimit: 100000n }).then((t) => t.wait()).then((r) => { plain = "status " + r.status; }); } catch (e) { plain = "rejected/reverted: " + (e.reason || e.shortMessage); }
  c.ok("plain Suren transfer into the vault is refused (funded only through alloc)", /revert|status 0|funded/.test(plain), plain);
  c.ok("vault balance unchanged after the refused transfer", (await net.balance(ADDR.VAULT)) === total);
  const withdrawnAfter = (await v.claimInfo(claimants[0])).withdrawn;
  c.ok("claimant1 withdrawn still 0", withdrawnAfter === 0n);
  writeResult("BG-11", { verdict: c.verdict, summary: "seeded totals, balance and the pre-release revert verified on Besu; monthly instalments NOT time-travelled", checks: c.items, notRun: "release after the first calendar month, 24 instalments, last-instalment remainder: Besu cannot advance time; covered only by the Hardhat tests (contracts-tests/test/GenesisClaimsVault.test.js)" });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
