// BG-02 founders join (setOperator + Verifier recordActivation, nodes already synced) and BG-12 (several list changes in ONE block)
const { Net, Checks, writeResult, ethers, send, sendNoWait, sleep, sealSigners } = require("./lib");
const { execSync } = require("child_process");
const ev = (s) => ethers.keccak256(ethers.toUtf8Bytes(s));
const ctl = (a, n) => execSync(`bash ${__dirname}/netctl.sh ${a} A ${n}`, { stdio: "pipe" });
(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG");
  const stages = [];
  const c2 = new Checks();   // BG-02
  const c12 = new Checks();  // BG-12
  const op = (i) => net.addr("op" + i), own = (i) => net.addr("owner" + i);
  const lower = (a) => a.map((x) => x.toLowerCase()).sort();
  const sameSet = (a, b) => JSON.stringify(lower(a)) === JSON.stringify(lower(b));

  async function observe(label, txBlock, expectedOps, extra = {}) {
    await net.waitForBlock(txBlock + 6);
    const contractNow = Array.from(await reg.getValidators());
    const qbft = {};
    for (const n of [txBlock - 1, txBlock, txBlock + 1, txBlock + 2, txBlock + 3]) { try { qbft[n] = (await net.qbftValidators(n)).map(ethers.getAddress); } catch (e) { qbft[n] = "ERR " + e.message.slice(0, 80); } }
    let firstBlock = null;
    for (const n of [txBlock, txBlock + 1, txBlock + 2, txBlock + 3]) if (Array.isArray(qbft[n]) && sameSet(qbft[n], expectedOps)) { firstBlock = n; break; }
    const miners = {}; const ts = [];
    for (let n = txBlock + 1; n <= txBlock + 6; n++) { const b = await net.block(n); miners[n] = ethers.getAddress(b.miner); ts.push(Number(BigInt(b.timestamp))); }
    const gaps = ts.slice(1).map((t, i) => t - ts[i]);
    const o = { label, txBlock, contractList: contractNow, qbftSetsByBlock: qbft, firstBlockWithExpectedSet: firstBlock, minersTxBlockPlus1to6: miners, blockTimestampGaps: gaps, ...extra };
    stages.push(o);
    return o;
  }

  const heads = {};
  for (const n of ["n1", "n2", "n3", "n4", "n5", "n6", "n7"]) heads[n] = await net.at(n).head();
  c2.ok("all 7 founder nodes running and in sync before the first activation", Math.max(...Object.values(heads)) - Math.min(...Object.values(heads)) <= 2, heads);

  const active = [op(1)];
  for (const i of [2, 3, 4]) {
    const st0 = Number((await reg.validators(own(i))).status);
    c2.ok(`owner${i} in Probation before`, st0 === 1, st0);
    const r1 = await send(net, "owner" + i, "REG", "setOperator", [op(i)]);
    c2.ok(`owner${i}.setOperator(op${i}) does not change the validator list yet`, sameSet(Array.from(await reg.getValidators()), active), { opSetBlock: r1.block });
    const r2 = await send(net, "verifier", "REG", "recordActivation", [own(i), ev("activation owner" + i)]);
    active.push(op(i));
    const o = await observe(`activate owner${i} (n=${active.length})`, r2.block, active, { setOperatorTx: r1.hash, activationTx: r2.hash });
    c2.ok(`n=${active.length}: contract list == ${active.length} operator keys and equals the QBFT set`, sameSet(o.contractList, active) && o.firstBlockWithExpectedSet !== null, { firstBlockWithExpectedSet: o.firstBlockWithExpectedSet, activationBlock: r2.block });
    c2.ok(`n=${active.length}: blocks keep being produced at ~2s`, o.blockTimestampGaps.every((g) => g >= 1 && g <= 4), o.blockTimestampGaps);
    const owners = Array.from(await reg.getActiveOwners());
    c2.ok(`n=${active.length}: getActiveOwners() returns owner keys, getValidators() operator keys`, owners.length === active.length && owners.includes(own(i)) && !o.contractList.includes(own(i)), owners);
  }
  await net.waitBlocks(24);
  const h4 = await net.head();
  const hist4 = {}; for (let n = h4 - 23; n <= h4; n++) { const m = ethers.getAddress((await net.block(n)).miner); hist4[m] = (hist4[m] || 0) + 1; }
  c2.ok("n=4: the last 24 blocks were mined by all four OPERATOR keys and by no owner key", Object.keys(hist4).length === 4 && Object.keys(hist4).every((m) => active.includes(m)), hist4);
  const seal4 = []; for (const n of [h4 - 1, h4 - 2, h4 - 3]) seal4.push(await sealSigners(net, n, active));
  c2.ok("n=4: committed-seal signers recovered from the header (>=3 = quorum, all operator keys)", seal4.every((s) => s.signers && s.signers.length >= 3), seal4.map((s) => ({ block: s.block, miner: s.miner, signers: s.signers })));

  // f=1 tolerance at n=4
  const hStop = await net.head();
  const tStop = Date.now();
  ctl("stop", "n4");
  await net.waitBlocks(14);
  const hAfter = await net.head();
  const gaps = []; let prev = null;
  for (let n = hStop + 1; n <= hAfter; n++) { const b = await net.block(n); const t = Number(BigInt(b.timestamp)); if (prev !== null) gaps.push(t - prev); prev = t; }
  const minersDown = {}; for (let n = hStop + 1; n <= hAfter; n++) { const m = ethers.getAddress((await net.block(n)).miner); minersDown[m] = (minersDown[m] || 0) + 1; }
  c2.ok("n=4, node n4 stopped (f=1): chain keeps producing blocks", hAfter >= hStop + 14, { hStop, hAfter, seconds: Math.round((Date.now() - tStop) / 1000) });
  stages.push({ label: "n=4 with n4 stopped", headAtStop: hStop, headAfter: hAfter, blockTimestampGaps: gaps, minersWhileDown: minersDown, note: "gaps > 2 s are rounds where the stopped node was the proposer (round change)" });
  c2.ok("n=4, one node down: contract list unchanged (4 operators)", (await reg.getValidators()).length === 4);
  ctl("start", "n4");
  await sleep(15000);
  const hN4 = await net.at("n4").head(); const hN1 = await net.head();
  c2.ok("n4 restarted and caught up (head within 3 blocks of n1)", Math.abs(hN1 - hN4) <= 3, { hN1, hN4 });

  // BG-12: owners 5,6,7 set operators, then ONE block carries three activations (4 -> 7 validators)
  for (const i of [5, 6, 7]) await send(net, "owner" + i, "REG", "setOperator", [op(i)]);
  const txs = [];
  for (const i of [5, 6, 7]) txs.push(await sendNoWait(net, "verifier", "REG", "recordActivation", [own(i), ev("activation owner" + i)]));
  const rcs = []; for (const t of txs) rcs.push(await t.wait());
  const blocks = rcs.map((r) => r.blockNumber);
  const sameBlock = blocks.every((b) => b === blocks[0]);
  c12.ok("three recordActivation txs mined in the SAME block", sameBlock, blocks);
  const all7 = [1, 2, 3, 4, 5, 6, 7].map(op);
  const o7 = await observe(sameBlock ? "activate owners 5,6,7 in one block (n 4 -> 7)" : "activate owners 5,6,7 (different blocks)", Math.max(...blocks), all7, { txs: txs.map((t) => t.hash), blocks });
  c12.ok("list grows by +3 in one block: contract list == QBFT set from the following blocks, 7 operator keys", sameSet(o7.contractList, all7) && o7.firstBlockWithExpectedSet !== null, { firstBlockWithExpectedSet: o7.firstBlockWithExpectedSet, qbftSets: o7.qbftSetsByBlock });
  c12.ok("blocks continue after the +3 change (no halt; gaps <= 4 s in the window)", o7.blockTimestampGaps.every((g) => g >= 1 && g <= 4), o7.blockTimestampGaps);
  c2.ok("n=7: contract list == QBFT set == 7 operator keys", sameSet(o7.contractList, all7) && sameSet((await net.qbftValidators("latest")).map(ethers.getAddress), all7));
  await net.waitBlocks(30);
  const h7 = await net.head();
  const hist7 = {}; for (let n = h7 - 27; n <= h7; n++) { const m = ethers.getAddress((await net.block(n)).miner); hist7[m] = (hist7[m] || 0) + 1; }
  c2.ok("n=7: the last 28 blocks were mined by the seven OPERATOR keys only", Object.keys(hist7).every((m) => all7.includes(m)) && Object.keys(hist7).length >= 6, hist7);
  const seal7 = []; for (const n of [h7 - 1, h7 - 2, h7 - 3, h7 - 4]) seal7.push(await sealSigners(net, n, all7));
  c2.ok("n=7: committed seals recovered, >=5 distinct operator signers (quorum 5 of 7)", seal7.every((s) => s.signers && new Set(s.signers).size >= 5), seal7.map((s) => ({ block: s.block, miner: s.miner, sealCount: s.sealCount, signers: s.signers })));
  const metrics = await net.provider.send("qbft_getSignerMetrics", []);
  const peers = {}; for (const n of ["n1", "n2", "n3", "n4", "n5", "n6", "n7"]) peers[n] = parseInt(await net.at(n).provider.send("net_peerCount", []), 16);

  writeResult("BG-02", { verdict: c2.verdict, summary: "founders 2..7 joined; validator set 1 -> 2 -> 3 -> 4 -> 7; f=1 tolerance at n=4 observed", checks: c2.items, stages, hist4, hist7, signerMetrics: metrics, peers });
  writeResult("BG-12", { verdict: c12.verdict, summary: "three activations in one block (n 4 -> 7)", checks: c12.items, blocks, stage: o7 });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
