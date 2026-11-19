// BG-05-neg: redo the two negatives of bg05.js that were INCONCLUSIVE (the caller could not afford the 520,000 Suren payment, so Besu answered
// "missing revert data" = insufficient balance instead of the contract's own revert). The DAO funds the callers first (typed Spend proposals, 3 of 5).
const { Net, Checks, writeResult, ethers, send, expectRevert, S, ADDR } = require("./lib");

async function spend(net, to, amount, text) {
  const dao = net.c("DAO");
  await send(net, "dao1", "DAO", "proposeSpend", [ethers.ZeroAddress, to, amount, text]);
  const id = Number(await dao.proposalCount());
  const h = (await dao.getProposal(id)).paramsHash;
  await send(net, "dao2", "DAO", "vote", [id, h]);
  await send(net, "dao3", "DAO", "vote", [id, h]);
  return id;
}
(async () => {
  const net = new Net("A", "n1");
  const c = new Checks();
  const value = S(520000);
  const id1 = await spend(net, net.addr("outsider"), S(600000), "BG-05-neg fund outsider");
  const id2 = await spend(net, net.addr("cand"), S(400000), "BG-05-neg fund cand");
  c.ok("outsider and cand now hold >= 520,000 Suren", (await net.balance(net.addr("outsider"))) >= value && (await net.balance(net.addr("cand"))) >= value);
  const un = await expectRevert(net, "outsider", "REG", "requestMembership", [net.addr("op3b")], { value });
  c.ok("negative: unverified outsider (funded) -> 'identity not fully verified'", un.reverted && /identity not fully verified/.test(un.reason || ""), un);
  const again = await expectRevert(net, "cand", "REG", "requestMembership", [net.addr("opC")], { value });
  c.ok("negative: cand (funded) requesting membership again -> 'already registered'", again.reverted && /already registered/.test(again.reason || ""), again);
  writeResult("BG-05-neg", { verdict: c.verdict, summary: "the two negatives that were inconclusive in BG-05 re-run with funded callers", checks: c.items, spends: [id1, id2] });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
