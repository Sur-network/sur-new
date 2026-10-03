// (v2: adds per-block conservation for every block incl. non-empty ones, and STATIC_ONLY simulation mode; the v1 tool testonly-settle.js is kept unchanged for the earlier runs)
// TESTONLY settlement tool — implements the v4 §D "independent extraction of inputs" methodology, then (optionally) sends ONE
// distributeRewards. This is test tooling for observing the CONTRACT; it is not the RewardRouter and proves nothing about the Router.
//
// For the range [S+1, L] it independently extracts, from chain data only (never from the contract's own cap getter):
//   * per-block producer from `miner`; aggregation per address; ascending numeric sort
//   * R  = sum of trace_block `reward` entries, cross-checked per block with the empty-block balance-delta method
//   * F  = sum over every tx receipt in the range of gasUsed * effectiveGasPrice (zeroBaseFee => full gas price reaches the coinbase 0x2222)
//   * M  = sum of MembershipFeeReceived events; X = other inflows (value-carrying calls into 0x2222 not from the Registry); P = outflows
// and closes   B(L) - B(S) == R + F + M + X - P   for the balance of 0x2222.
// Gates (v4 §D): totalRewards/totalFees submitted MUST equal independent R/F, the equation MUST close, sum(blocksMined) MUST equal the range
// length, and R MUST NOT exceed maxRewardsForRange(S+1,L); otherwise the tool refuses to send (INCONCLUSIVE / WARN) and lastSettledBlock stays put.
// Contract-rejection tests (F03) pass FORCE_SEND_CAP_EXCEEDED=1: the cap gate is bypassed on purpose, to observe the CONTRACT's own rejection.
//
// env: NET_NAME, NET_RPC, ID, FOUNDERS (G5|G6), SEND (1|0), TO (default: head at start), FROM (default: lastSettled+1),
//      SHORT_BY (D06: report this many fewer blocks than really mined), FORCE_SEND_CAP_EXCEEDED, LABEL_OVERRIDE_TOTAL_REWARDS (never used by default)
const { ethers, ADDR, DIST_ABI, accounts, rpc, hex, sortAsc, sleep, saveEvidence, SUR } = require("./v5-lib");

async function main() {
  const NET = process.env.NET_NAME, URL = process.env.NET_RPC, ID = process.env.ID || "settle";
  const FOUNDERS = process.env.FOUNDERS || "G5";
  const SEND = process.env.SEND === "1";
  const SHORT_BY = Number(process.env.SHORT_BY || 0);
  const FORCE_CAP = process.env.FORCE_SEND_CAP_EXCEEDED === "1";
  const provider = new ethers.JsonRpcProvider(URL);
  const call = rpc(URL);
  const oracle = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const dist = new ethers.Contract(ADDR.DISTRIBUTOR, DIST_ABI, oracle);
  const founders = (FOUNDERS === "G5" ? [1, 2, 3, 4, 5].map((i) => accounts[`g5_v${i}`]) : [1, 2, 3, 4, 5, 6].map((i) => accounts[`g6_v${i}`])).map((a) => a.address);
  const out = { ID, NET, startedAt: new Date().toISOString(), gates: {}, warnings: [] };

  // ---- range ----
  const S = Number(await dist.lastSettledBlock());
  const head = await provider.getBlockNumber();
  const from = Number(process.env.FROM || S + 1);
  const L = Number(process.env.TO || head);
  const len = L - from + 1;
  out.range = { S, from, L, head, length: len };
  out.preState = { epochCount: (await dist.epochCount()).toString(), lastSettledBlock: S, pendingMembershipFees: (await dist.pendingMembershipFees()).toString(), shareBps: (await dist.validatorDirectShareBps()).toString(), foundationBps: (await dist.FOUNDATION_SHARE_BPS()).toString(), feeBurnBps: (await dist.FEE_BURN_BPS()).toString() };
  console.log(`[${ID}] range [${from}, ${L}] (len ${len}), S=${S}, head=${head}`);

  // ---- per-block extraction ----
  const counts = Object.fromEntries(founders.map((a) => [a.toLowerCase(), 0]));
  let R = 0n, F = 0n, Mtrace = 0n, Xother = 0n, P = 0n, nonEmpty = 0, emptyBlocks = 0, emptyCrossChecked = 0, emptyMismatch = [], perBlockChecked = 0, perBlockMismatch = [];
  const traceRewardAuthors = new Set();
  const unknownMiners = {};
  const perBlock = [];
  let traceMissing = 0;
  for (let n = from; n <= L; n++) {
    const blk = await provider.send("eth_getBlockByNumber", [hex(n), false]);
    const m = blk.miner.toLowerCase();
    if (m in counts) counts[m]++; else unknownMiners[m] = (unknownMiners[m] || 0) + 1;
    // trace_block: reward entries + value-carrying calls into/out of the distributor
    let traces = [];
    try { traces = await call("trace_block", [hex(n)]); } catch (e) { traceMissing++; out.warnings.push(`trace_block(${n}) failed: ${e.message}`); }
    let rewardHere = 0n, inHere = 0n, outHere = 0n;
    for (const t of traces) {
      if (t.type === "reward") { rewardHere += BigInt(t.action.value); traceRewardAuthors.add(t.action.author.toLowerCase()); }
      else if (t.type === "call" && !t.error && t.action && BigInt(t.action.value || 0) > 0n) {
        const to = (t.action.to || "").toLowerCase(), fr = (t.action.from || "").toLowerCase(), v = BigInt(t.action.value);
        if (to === ADDR.DISTRIBUTOR) { inHere += v; if (fr === ADDR.REGISTRY) Mtrace += v; else Xother += v; }
        if (fr === ADDR.DISTRIBUTOR) { outHere += v; P += v; }
      }
    }
    R += rewardHere;
    // fees from receipts
    let feesHere = 0n;
    if (blk.transactions.length > 0) {
      nonEmpty++;
      const receipts = await call("eth_getBlockReceipts", [hex(n)]);
      for (const r of receipts) feesHere += BigInt(r.gasUsed) * BigInt(r.effectiveGasPrice);
    } else emptyBlocks++;
    // v2: independent PER-BLOCK conservation for EVERY block (empty or not):  balance delta of 0x2222 == reward(trace) + fees(receipts) + value-in(calls) - value-out(calls)
    // (for an empty block this reduces to the document's empty-block method: delta == reward)
    try {
      const b1 = BigInt(await call("eth_getBalance", [ADDR.DISTRIBUTOR, hex(n)]));
      const b0 = BigInt(await call("eth_getBalance", [ADDR.DISTRIBUTOR, hex(n - 1)]));
      if (b1 === null || b0 === null) throw new Error("null balance");
      const expectDelta = rewardHere + feesHere + inHere - outHere;
      if (blk.transactions.length === 0) emptyCrossChecked++;
      perBlockChecked++;
      if (b1 - b0 !== expectDelta) { perBlockMismatch.push({ n, txs: blk.transactions.length, delta: (b1 - b0).toString(), expected: expectDelta.toString(), reward: rewardHere.toString(), fees: feesHere.toString(), inflow: inHere.toString(), outflow: outHere.toString() }); if (blk.transactions.length === 0) emptyMismatch.push({ n, delta: (b1 - b0).toString(), trace: rewardHere.toString() }); }
    } catch (e) { out.warnings.push(`per-block check at ${n} unavailable: ${e.message}`); }
    F += feesHere;
    perBlock.push({ n, miner: m, txs: blk.transactions.length, reward: rewardHere.toString(), fees: feesHere.toString(), inflowCalls: inHere.toString(), outflowCalls: outHere.toString() });
  }
  out.extraction = {
    R: R.toString(), F: F.toString(), M_traceRegistryForward: Mtrace.toString(), X_otherInflows: Xother.toString(), P_outflowsInRange: P.toString(),
    nonEmptyBlocks: nonEmpty, emptyBlocks, emptyBlocksCrossChecked: emptyCrossChecked, emptyBlockMethodMismatches: emptyMismatch.slice(0, 10), emptyBlockMismatchCount: emptyMismatch.length, perBlockConservation: { checked: perBlockChecked, rangeLength: len, mismatchCount: perBlockMismatch.length, mismatches: perBlockMismatch.slice(0, 10) }, nonEmptyBlocksDetail: perBlock.filter((x) => x.txs > 0 || BigInt(x.inflowCalls) > 0n).map((x) => ({ n: x.n, txs: x.txs, fees: x.fees, inflowCalls: x.inflowCalls })),
    traceRewardAuthors: [...traceRewardAuthors], traceMissingBlocks: traceMissing, unknownMiners,
  };
  // M from events (independent of trace)
  const logs = await provider.getLogs({ address: ADDR.DISTRIBUTOR, fromBlock: from, toBlock: L, topics: [ethers.id("MembershipFeeReceived(uint256,uint256)")] });
  const Mevents = logs.reduce((a, l) => a + BigInt(ethers.AbiCoder.defaultAbiCoder().decode(["uint256", "uint256"], l.data)[0]), 0n);
  out.extraction.M_events = Mevents.toString();
  out.extraction.M_eventCount = logs.length;
  const M = Mevents;
  if (Mtrace !== Mevents) out.warnings.push(`M mismatch: trace=${Mtrace} events=${Mevents}`);

  // ---- conservation equation B(L)-B(S) = R+F+M+X-P ----
  let eq = { available: false };
  try {
    const BL = BigInt(await call("eth_getBalance", [ADDR.DISTRIBUTOR, hex(L)]));
    const BS = from === 1 ? 0n : BigInt(await call("eth_getBalance", [ADDR.DISTRIBUTOR, hex(from - 1)]));
    const rhs = R + F + M + Xother - P;
    eq = { available: true, B_L: BL.toString(), B_S: BS.toString(), lhs: (BL - BS).toString(), rhs: rhs.toString(), closes: BL - BS === rhs, residual: (BL - BS - rhs).toString() };
    if (from === 1) eq.note = "B(S)=B(0): the distributor has no genesis balance in this network's alloc (0)";
  } catch (e) { eq = { available: false, error: e.message }; }
  out.conservationEquation = eq;
  console.log(`[${ID}] R=${SUR(R)} F=${SUR(F)} M=${SUR(M)} X=${SUR(Xother)} P=${SUR(P)} | equation:`, JSON.stringify(eq));

  // ---- blocks mined (what the Router would report) ----
  const addrs = sortAsc(founders);
  let blocksMined = addrs.map((a) => counts[a.toLowerCase()]);
  if (SHORT_BY > 0) { blocksMined[blocksMined.findIndex((c) => c > 0)] -= SHORT_BY; out.warnings.push(`D06: deliberately reporting ${SHORT_BY} fewer blocks than mined`); }
  const totalBlocks = blocksMined.reduce((a, b) => a + b, 0);
  out.submission = { addresses: addrs, blocksMined, totalBlocks, rangeLength: len };

  // ---- gates ----
  const cap = BigInt(await dist.maxRewardsForRange(from, L));
  const totalRewards = R, totalFees = F;
  out.gates = {
    equationCloses: eq.available && eq.closes,
    countComplete: totalBlocks === len,
    noUnknownMiners: Object.keys(unknownMiners).length === 0,
    emptyBlockMethodAgreesWithTrace: emptyMismatch.length === 0 && (emptyCrossChecked > 0 || nonEmpty === len),
    perBlockConservationAgrees: perBlockMismatch.length === 0 && perBlockChecked === len,
    rewardAtOrBelowCap: R <= cap,
    contractCap: cap.toString(),
    independentR: R.toString(),
    independentF: F.toString(),
    submittedTotalRewardsEqualsIndependentR: totalRewards === R,
    submittedTotalFeesEqualsIndependentF: totalFees === F,
  };
  const blockers = [];
  if (!out.gates.equationCloses) blockers.push("INCONCLUSIVE: conservation equation did not close (or state unavailable)");
  if (!out.gates.countComplete) blockers.push(`WARN: incomplete count (sum ${totalBlocks} != range ${len})`);
  if (!out.gates.noUnknownMiners) blockers.push("WARN: blocks produced by addresses outside the supplied validator list");
  if (!out.gates.perBlockConservationAgrees) blockers.push(`INCONCLUSIVE: per-block conservation failed or incomplete (${perBlockMismatch.length} mismatches, ${perBlockChecked}/${len} checked)`);
  if (!out.gates.emptyBlockMethodAgreesWithTrace) blockers.push("INCONCLUSIVE: empty-block method disagrees with (or could not cross-check) trace_block rewards");
  if (!out.gates.rewardAtOrBelowCap) { if (FORCE_CAP) out.warnings.push(`R (${R}) exceeds contract cap (${cap}) -- sending anyway ONLY because FORCE_SEND_CAP_EXCEEDED=1 (F03: observing the contract's own rejection)`); else blockers.push(`WARN: independent R ${R} exceeds contract cap ${cap}`); }
  out.blockers = blockers;
  out.capComparison = { independentR: R.toString(), contractCap: cap.toString(), capMinusR: (cap - R).toString(), rEqualsCap: R === cap };
  if (R < cap) out.warnings.push(`MISMATCH WARNING: actual reward ${SUR(R)} is BELOW the contract cap ${SUR(cap)} (cap - R = ${SUR(cap - R)}): the contract's approved rate history is ahead of what Besu actually paid`);
  console.log(`[${ID}] gates:`, JSON.stringify(out.gates), "blockers:", JSON.stringify(blockers));

  if (!SEND || blockers.length) {
    out.sent = false;
    out.reason = !SEND ? "SEND=0 (dry run)" : "gate(s) failed -- not sent";
    out.lastSettledBlockAfter = (await dist.lastSettledBlock()).toString();
    saveEvidence(`${ID}-reconcile.json`, out);
    return;
  }

  // ---- expected amounts, independently, BigInt ----
  const share = BigInt(out.preState.shareBps), fBps = BigInt(out.preState.foundationBps), burnBps = BigInt(out.preState.feeBurnBps), pendingM = BigInt(out.preState.pendingMembershipFees);
  const validatorDirect = (totalRewards * share) / 10000n;
  const foundation = (totalRewards * fBps) / 10000n;
  const burn = (totalFees * burnBps) / 10000n;
  const feePool = totalFees + pendingM;
  const feesToDistribute = feePool - burn;
  const perVal = addrs.map((a, i) => ({ a, blocks: blocksMined[i], reward: blocksMined[i] === 0 ? 0n : (validatorDirect * BigInt(blocksMined[i])) / BigInt(totalBlocks), fee: blocksMined[i] === 0 ? 0n : (feesToDistribute * BigInt(blocksMined[i])) / BigInt(totalBlocks) }));
  const distReward = perVal.reduce((s, v) => s + v.reward, 0n), distFee = perVal.reduce((s, v) => s + v.fee, 0n);
  const treasury = totalRewards - foundation - validatorDirect + (validatorDirect - distReward) + (feePool - burn - distFee);
  out.expected = { shareBps: share.toString(), validatorDirect: validatorDirect.toString(), foundation: foundation.toString(), feeBurn: burn.toString(), feePool: feePool.toString(), feesToDistribute: feesToDistribute.toString(), treasury: treasury.toString(), perValidator: perVal.map((v) => ({ a: v.a, blocks: v.blocks, reward: v.reward.toString(), fee: v.fee.toString() })), membershipFeeFoldedIn: pendingM.toString() };

  // ---- v2: STATIC_ONLY=1 => simulate with eth_call only (does not consume the network's single pre-lock epoch) ----
  if (process.env.STATIC_ONLY === "1") {
    try { await dist.distributeRewards.staticCall({ fromBlock: from, toBlock: L }, addrs, blocksMined, totalRewards, totalFees); out.simulation = { result: "SUCCESS (eth_call; nothing mined)" }; }
    catch (e) { out.simulation = { result: "REVERT", reason: e.reason || e.shortMessage || e.message }; }
    out.sent = false; out.reason = "STATIC_ONLY simulation"; out.lastSettledBlockAfter = (await dist.lastSettledBlock()).toString();
    console.log(`[${ID}] simulation:`, JSON.stringify(out.simulation));
    saveEvidence(`${ID}-reconcile.json`, out);
    return;
  }
  // ---- send ----
  const stateBefore = { epochCount: (await dist.epochCount()).toString(), lastSettledBlock: (await dist.lastSettledBlock()).toString(), pendingMembershipFees: (await dist.pendingMembershipFees()).toString(), lastDistributionTime: (await dist.lastDistributionTime()).toString() };
  out.stateBefore = stateBefore;
  if (FORCE_CAP) {
    try { await dist.distributeRewards.staticCall({ fromBlock: from, toBlock: L }, addrs, blocksMined, totalRewards, totalFees); out.contractStaticCall = "UNEXPECTED_SUCCESS"; }
    catch (e) { out.contractStaticCall = { revertReason: e.reason || e.shortMessage || e.message }; }
    console.log(`[${ID}] staticCall:`, JSON.stringify(out.contractStaticCall));
  }
  const tx = await dist.distributeRewards({ fromBlock: from, toBlock: L }, addrs, blocksMined, totalRewards, totalFees, { gasLimit: 5_000_000 });
  let receipt;
  try { receipt = await tx.wait(); } catch (e) { receipt = e.receipt || (await provider.getTransactionReceipt(tx.hash)); out.txWaitError = e.shortMessage || e.message; }
  const rb = receipt.blockNumber;
  out.tx = { hash: tx.hash, status: receipt.status, gasUsed: receipt.gasUsed.toString(), block: rb, effectiveGasPrice: receipt.gasPrice ? receipt.gasPrice.toString() : null };
  console.log(`[${ID}] tx ${tx.hash} status=${receipt.status} block=${rb}`);

  const watch = [...addrs, ADDR.FOUNDATION, ADDR.TREASURY, ADDR.BURN, ADDR.DISTRIBUTOR, oracle.address];
  const before = {}, after = {};
  for (const a of watch) { before[a] = BigInt(await call("eth_getBalance", [a, hex(rb - 1)])); after[a] = BigInt(await call("eth_getBalance", [a, hex(rb)])); }
  const delta = Object.fromEntries(watch.map((a) => [a, (after[a] - before[a]).toString()]));
  out.balanceDeltasAtBlock = delta;
  out.postState = { epochCount: (await dist.epochCount()).toString(), lastSettledBlock: (await dist.lastSettledBlock()).toString(), totalFeesBurned: (await dist.totalFeesBurned()).toString(), pendingMembershipFees: (await dist.pendingMembershipFees()).toString() };

  if (receipt.status !== 1) {
    const same = out.postState.epochCount === stateBefore.epochCount && out.postState.lastSettledBlock === stateBefore.lastSettledBlock && out.postState.pendingMembershipFees === stateBefore.pendingMembershipFees && (await dist.lastDistributionTime()).toString() === stateBefore.lastDistributionTime;
    out.rejectedTxStateUnchanged = { unchanged: same, before: stateBefore, after: { ...out.postState, lastDistributionTime: (await dist.lastDistributionTime()).toString() } };
    const payoutMoved = [...addrs, ADDR.FOUNDATION, ADDR.TREASURY, ADDR.BURN].filter((a) => BigInt(delta[a]) !== 0n);
    out.rejectedTxNoPayouts = { addressesWhoseBalanceChanged: payoutMoved };
  }
  if (receipt.status === 1) {
    // per-validator verification: contract's recorded shares vs independent expectation; balance deltas vs payout (validators sent no txs in block rb is checked)
    const epochId = Number(out.postState.epochCount);
    const blkRb = await provider.send("eth_getBlockByNumber", [hex(rb), true]);
    const senders = new Set(blkRb.transactions.map((t) => t.from.toLowerCase()));
    out.perValidatorCheck = [];
    for (const v of perVal) {
      const rs = (await dist.epochValidatorRewardShare(epochId, v.a)).toString(), fs_ = (await dist.epochValidatorFeeShare(epochId, v.a)).toString(), bl = (await dist.epochValidatorBlocks(epochId, v.a)).toString();
      const expectedPayout = v.reward + v.fee;
      const d = BigInt(delta[v.a]);
      out.perValidatorCheck.push({ validator: v.a, blocks: v.blocks, recordedBlocks: bl, recordedRewardShare: rs, expectedRewardShare: v.reward.toString(), recordedFeeShare: fs_, expectedFeeShare: v.fee.toString(), balanceDelta: d.toString(), expectedPayout: expectedPayout.toString(), balanceDeltaEqualsPayout: d === expectedPayout, sharesMatch: rs === v.reward.toString() && fs_ === v.fee.toString() && bl === v.blocks.toString(), validatorSentTxInSameBlock: senders.has(v.a.toLowerCase()) });
    }
    const O = perVal.reduce((s, v) => s + v.reward + v.fee, 0n) + BigInt(delta[ADDR.TREASURY]) + BigInt(delta[ADDR.FOUNDATION]) + BigInt(delta[ADDR.BURN]);
    const blockRewardAtRb = BigInt(await (async () => { const tr = await call("trace_block", [hex(rb)]); return tr.filter((t) => t.type === "reward").reduce((s, t) => s + BigInt(t.action.value), 0n).toString(); })());
    const txFee = BigInt(receipt.gasUsed) * BigInt(receipt.gasPrice || receipt.effectiveGasPrice || 0);
    out.postDistributionConservation = {
      totalOutflowFromContract: O.toString(),
      expectedOutflow_R_plus_F_plus_pendingM: (totalRewards + totalFees + pendingM).toString(),
      outflowEqualsRFM: O === totalRewards + totalFees + pendingM,
      contractBalanceDelta: delta[ADDR.DISTRIBUTOR],
      blockRewardInThatBlock: blockRewardAtRb.toString(), distributionTxOwnFee: txFee.toString(),
      expectedContractDelta: (blockRewardAtRb + txFee - O).toString(),
      contractDeltaEqualsExpected: BigInt(delta[ADDR.DISTRIBUTOR]) === blockRewardAtRb + txFee - O,
      feeBurnedDeltaAtZeroAddress: delta[ADDR.BURN], expectedBurn: burn.toString(), burnMatches: BigInt(delta[ADDR.BURN]) === burn,
      foundationMatches: BigInt(delta[ADDR.FOUNDATION]) === foundation, treasuryMatches: BigInt(delta[ADDR.TREASURY]) === treasury,
      membershipFeeNotBurned: M === 0n ? "n/a (M=0 in this range)" : (burn === (totalFees * burnBps) / 10000n),
    };
  }
  saveEvidence(`${ID}-reconcile.json`, out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
