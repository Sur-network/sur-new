// L05 (owner decision 2026-09-30) — totalRewards <= sum of the approved per-block reward rate over the settled range.
// Rate history entries are written directly into storage here (the governance path that appends them is pending the owner's
// decision on delay/lead time and is NOT part of this test). Hardhat, not Besu.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const DIST = "0x2222222222222222222222222222222222222222", FOUND = "0x1111111111111111111111111111111111111111",
      REG = "0x3333333333333333333333333333333333333333", TRES = "0x5555555555555555555555555555555555555555";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const msgOf = e => { const m = e.reason || e.shortMessage || e.message || ""; const r = m.match(/reason string '([^']*)'/); return r ? r[1] : m; };
async function reverts(fn, expected) { try { await (await fn()).wait(); return "did NOT revert"; } catch (e) { return msgOf(e).includes(expected) ? true : "wrong reason: " + msgOf(e).slice(0, 160); } }
const E = hre.ethers.parseEther; const CAP_ERR = "totalRewards exceed approved reward for range";
const MOCK = `pragma solidity ^0.8.24;
contract AllValid { function isValidator(address) external pure returns (bool) { return true; } function everActivated(address) external pure returns (bool) { return true; } }
contract Sink { receive() external payable {} }`;
(async () => {
  const [deployer, oracle, v1, payer] = await hre.ethers.getSigners();
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const put = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  const M = out.contracts["M.sol"];
  await put(REG, M.AllValid.abi, "0x" + M.AllValid.evm.bytecode.object); await put(FOUND, M.Sink.abi, "0x" + M.Sink.evm.bytecode.object); await put(TRES, M.Sink.abi, "0x" + M.Sink.evm.bytecode.object);
  const art = JSON.parse(fs.readFileSync("distributor_artifact.json")); await put(DIST, art.abi, art.bytecode);
  const L = art.layout.storage; const slot = n => BigInt(L.find(x => x.label === n).slot);
  const setU = (s, v) => hre.network.provider.send("hardhat_setStorageAt", [DIST, hre.ethers.toBeHex(s), hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
  await setU(slot("distributionOracle"), BigInt(oracle.address)); await setU(slot("validatorDirectShareBps"), 5000n);
  await hre.network.provider.send("hardhat_setBalance", [DIST, "0x" + (10n ** 27n).toString(16)]);
  await hre.network.provider.send("hardhat_mine", ["0x" + (5000).toString(16)]);
  const d = new hre.ethers.Contract(DIST, art.abi, oracle);
  const RS = slot("rewardRateChanges"), base = BigInt(hre.ethers.keccak256(hre.ethers.zeroPadValue(hre.ethers.toBeHex(RS), 32)));
  const setSchedule = async entries => { await setU(RS, BigInt(entries.length)); for (let i = 0; i < entries.length; i++) await setU(base + BigInt(i), BigInt(entries[i][0]) + (entries[i][1] << 128n)); };
  const brute = (sched, a, b) => { let t = 0n; for (let h = a; h <= b; h++) { let r = E("2"); for (const [s, rr] of sched) if (s <= h) r = rr; t += r; } return t; };
  // Hardhat snapshots are single-use: re-take one after every revert so each section starts from the same clean state
  let snap = await hre.network.provider.send("evm_snapshot");
  const fresh = async () => { await hre.network.provider.send("evm_revert", [snap]); snap = await hre.network.provider.send("evm_snapshot"); };

  console.log("=== A — base rate 2 SUR, share from the existing variable ===");
  ok("A0) INITIAL_REWARD_PER_BLOCK = 2 SUR (wei); empty history; rewardRateAt(1) = 2 SUR", (await d.INITIAL_REWARD_PER_BLOCK()) === E("2") && (await d.rewardRateChangeCount()) === 0n && (await d.rewardRateAt(1)) === E("2"));
  ok("A1) 1000-block range: maximum gross reward = 2000 SUR", (await d.maxRewardsForRange(1, 1000)) === E("2000"));
  { const b0 = await hre.ethers.provider.getBalance(v1.address);
    const rc = await (await d.distributeRewards({ fromBlock: 1, toBlock: 1000 }, [v1.address], [1000], E("2000"), 0)).wait();
    ok("A2) exact cap (2000 SUR) accepted; with share 50% the direct validator share is exactly 1000 SUR", rc.status === 1 && (await hre.ethers.provider.getBalance(v1.address)) - b0 === E("1000")); }
  await fresh();
  { const ls0 = await d.lastSettledBlock(), ep0 = await d.epochCount(), b0 = await hre.ethers.provider.getBalance(v1.address), bt0 = await hre.ethers.provider.getBalance(TRES), bf0 = await hre.ethers.provider.getBalance(FOUND);
    ok("A3) one wei above the cap is rejected", await reverts(() => d.distributeRewards({ fromBlock: 1, toBlock: 1000 }, [v1.address], [1000], E("2000") + 1n, 0), CAP_ERR));
    ok("A4) the rejection left no state change and no payment", (await d.lastSettledBlock()) === ls0 && (await d.epochCount()) === ep0 && (await hre.ethers.provider.getBalance(v1.address)) === b0 && (await hre.ethers.provider.getBalance(TRES)) === bt0 && (await hre.ethers.provider.getBalance(FOUND)) === bf0); }
  for (const [bps, expDirect] of [[4000n, E("800")], [6500n, E("1300")]]) {
    await fresh(); await setU(slot("validatorDirectShareBps"), bps);
    const b0 = await hre.ethers.provider.getBalance(v1.address);
    await (await d.distributeRewards({ fromBlock: 1, toBlock: 1000 }, [v1.address], [1000], E("2000"), 0)).wait();
    ok(`A5.${bps}) share ${Number(bps) / 100}% (existing variable): direct share of the capped reward = ${hre.ethers.formatEther(expDirect)} SUR`, (await hre.ethers.provider.getBalance(v1.address)) - b0 === expDirect);
  }

  console.log("\n=== B — rate history: mid-range change, exact boundaries, several changes, historical settlement ===");
  await fresh();
  const S1 = [[501n, E("3")]]; await setSchedule(S1);
  ok("B1) change at 501 to 3 SUR: [1,1000] = 500·2 + 500·3 = 2500 SUR", (await d.maxRewardsForRange(1, 1000)) === E("2500"));
  ok("B2) boundaries: [500,500] = 2, [501,501] = 3, [500,501] = 5, [1,500] = 1000, [501,1000] = 1500",
    (await d.maxRewardsForRange(500, 500)) === E("2") && (await d.maxRewardsForRange(501, 501)) === E("3") && (await d.maxRewardsForRange(500, 501)) === E("5") && (await d.maxRewardsForRange(1, 500)) === E("1000") && (await d.maxRewardsForRange(501, 1000)) === E("1500"));
  ok("B3) mid-range change: exact cap accepted", (await (await d.distributeRewards({ fromBlock: 1, toBlock: 1000 }, [v1.address], [1000], E("2500"), 0)).wait()).status === 1);
  await fresh(); await setSchedule(S1);
  ok("B4) mid-range change: cap + 1 wei rejected", await reverts(() => d.distributeRewards({ fromBlock: 1, toBlock: 1000 }, [v1.address], [1000], E("2500") + 1n, 0), CAP_ERR));
  const S3 = [[101n, E("1")], [201n, 0n], [301n, E("5")], [1001n, E("4")]]; await setSchedule(S3);
  let allMatch = true, cases = 0;
  const probes = [[1, 100], [1, 101], [100, 101], [101, 200], [150, 250], [200, 201], [201, 300], [250, 350], [300, 301], [1, 1000], [999, 1002], [1000, 1001], [1001, 1001], [1, 2000], [777, 1500]];
  for (const [a, b] of probes) { cases++; const got = await d.maxRewardsForRange(a, b), exp = brute(S3, a, b); if (got !== exp) allMatch = `[${a},${b}] got ${got} exp ${exp}`; }
  for (let i = 0; i < 25; i++) { const a = 1 + Math.floor(Math.random() * 1400), b = a + Math.floor(Math.random() * 600); cases++; const got = await d.maxRewardsForRange(a, b), exp = brute(S3, a, b); if (got !== exp) allMatch = `[${a},${b}] got ${got} exp ${exp}`; }
  ok(`B5) four changes (incl. a 0-reward segment): contract equals per-block brute force on ${cases} ranges`, allMatch);
  ok("B6) rewardRateAt at each boundary", (await d.rewardRateAt(100)) === E("2") && (await d.rewardRateAt(101)) === E("1") && (await d.rewardRateAt(201)) === 0n && (await d.rewardRateAt(300)) === 0n && (await d.rewardRateAt(301)) === E("5") && (await d.rewardRateAt(1001)) === E("4"));
  { const exp = brute(S3, 1, 350); // late settlement long after the changes, at head ~5000: historical rates of THESE blocks apply
    ok("B7) late settlement of [1,350] at head ≈5000 uses the historical rates of those blocks (exact cap accepted)", (await (await d.distributeRewards({ fromBlock: 1, toBlock: 350 }, [v1.address], [350], exp, 0)).wait()).status === 1, `cap=${hre.ethers.formatEther(exp)} SUR`); }
  ok("B8) a change starting after toBlock does not affect the range ([1,1000] ignores the change at 1001)", (await d.maxRewardsForRange(1, 1000)) === brute(S3, 1, 1000));
  ok("B9) invalid range (from > to) rejected by the view", await (async () => { try { await d.maxRewardsForRange(10, 9); return "did NOT revert"; } catch (e) { return msgOf(e).includes("invalid range") ? true : msgOf(e); } })());

  console.log("\n=== C — fees and membership fees are outside the cap ===");
  await fresh();
  // only ValidatorsRegistry may forward membership fees -> impersonate its fixed address, as the real flow would call it
  await hre.network.provider.send("hardhat_impersonateAccount", [REG]); await hre.network.provider.send("hardhat_setBalance", [REG, "0x" + E("1000").toString(16)]);
  const regSigner = await hre.ethers.getSigner(REG);
  await (await d.connect(regSigner).receiveMembershipFee({ value: E("500") })).wait();
  { const bt0 = await hre.ethers.provider.getBalance(TRES), b0 = await hre.ethers.provider.getBalance(v1.address);
    const rc = await (await d.distributeRewards({ fromBlock: 1, toBlock: 1000 }, [v1.address], [1000], E("2000"), E("1000"))).wait();
    const ev = rc.logs.map(l => { try { return d.interface.parseLog(l); } catch (e) { return null; } }).filter(e => e && /Burn|burn/.test(e.name));
    ok("C1) reward at the cap + 1000 SUR fees + 500 SUR membership fee: accepted (fees not counted in the cap)", rc.status === 1);
    ok("C2) burn applies only to ordinary fees: totalFeesBurned = 30% of 1000 = 300 SUR", (await d.totalFeesBurned()) === E("300"));
    ok("C3) validator received 50%·2000 + (1000 − 300 + 500) = 2200 SUR", (await hre.ethers.provider.getBalance(v1.address)) - b0 === E("2200")); }

  console.log("\n=== D — cost grows with the number of rate changes, not with blocks ===");
  await fresh(); await setSchedule(S3);
  // both ranges cross the same 4 changes; only their length differs (2,000 vs 10,000,000 blocks)
  const gSmall = await d.maxRewardsForRange.estimateGas(1, 2000), gHuge = await d.maxRewardsForRange.estimateGas(1, 10_000_000);
  ok("D1) same changes crossed: a 10,000,000-block range costs about the same as a 2,000-block range (≤ +2%)", gHuge <= gSmall * 102n / 100n, `2k=${gSmall} 10M=${gHuge}`);
  const many = []; for (let i = 0; i < 40; i++) many.push([BigInt(100 + i * 10), E("2")]); await setSchedule(many);
  const gMany = await d.maxRewardsForRange.estimateGas(1, 10_000_000);
  ok("D2) 40 changes cost more than 4 (cost scales with changes)", gMany > gHuge, `4 changes=${gHuge} 40 changes=${gMany}`);

  // D3: cost must not grow with the amount of OLD history either — short range after every entry, no change inside it
  await fresh(); const gH = {};
  for (const n of [4, 40, 400]) { const ent = []; for (let i = 0; i < n; i++) ent.push([BigInt(100 + i * 10), E("2")]); await setSchedule(ent); const last = 100 + n * 10; gH[n] = await d.maxRewardsForRange.estimateGas(last + 1000, last + 1999); }
  ok("D3) history length 4 -> 400 entries: short range without a change inside costs < 2x (binary search; was 31x with a linear scan)", gH[400] < gH[4] * 2n && gH[400] < 100000n, `4=${gH[4]} 40=${gH[40]} 400=${gH[400]}`);
  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
