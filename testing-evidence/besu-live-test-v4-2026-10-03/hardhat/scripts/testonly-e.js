// Group E — SYNTHETIC payment-cost benchmark (NOT operational evidence; NOT a statement about production capacity, Router capacity or a production gasLimit).
// payees are TEST-ONLY-SEED addresses (everActivated written directly into storage, never validators, never produced a block); the 399-entry rate history is
// a TEST-ONLY-SEED too. Runs BEFORE the first distribution (epochCount==0, so no 23h lock), takes eth_estimateGas for the whole matrix, then sends ONE real
// distribution with the heaviest combination that fits.
// env: NET_NAME (Net-E15|Net-E30|Net-E60), NET_RPC, GAS_LABEL (15M|30M|60M)
const { ethers, ADDR, DIST_ABI, accounts, ROOT, fs, path, rpc, hex, SUR, saveEvidence } = require("./v5-lib");

const NS = [5, 25, 50, 100, 150], KS = [0, 1, 20, 100, 399];
const reason = (e) => (e.rpcError ? `${e.rpcError.code}: ${e.rpcError.message}` : e.shortMessage || e.message);

function lstsq(rows, ys) { // ordinary least squares via normal equations (small systems)
  const p = rows[0].length;
  const A = Array.from({ length: p }, () => new Array(p).fill(0)), b = new Array(p).fill(0);
  rows.forEach((r, i) => { for (let a = 0; a < p; a++) { b[a] += r[a] * ys[i]; for (let c = 0; c < p; c++) A[a][c] += r[a] * r[c]; } });
  for (let i = 0; i < p; i++) { let m = i; for (let r = i + 1; r < p; r++) if (Math.abs(A[r][i]) > Math.abs(A[m][i])) m = r; [A[i], A[m]] = [A[m], A[i]]; [b[i], b[m]] = [b[m], b[i]]; for (let r = i + 1; r < p; r++) { const f = A[r][i] / A[i][i]; for (let c = i; c < p; c++) A[r][c] -= f * A[i][c]; b[r] -= f * b[i]; } }
  const x = new Array(p).fill(0);
  for (let i = p - 1; i >= 0; i--) { let s = b[i]; for (let c = i + 1; c < p; c++) s -= A[i][c] * x[c]; x[i] = s / A[i][i]; }
  return x;
}

async function main() {
  const NET = process.env.NET_NAME, URL = process.env.NET_RPC, LABEL = process.env.GAS_LABEL;
  const provider = new ethers.JsonRpcProvider(URL);
  const call = rpc(URL);
  const oracle = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const dist = new ethers.Contract(ADDR.DISTRIBUTOR, DIST_ABI, oracle);
  const iface = dist.interface;
  const payees = JSON.parse(fs.readFileSync(`${ROOT}/nets/${NET}/payees.json`, "utf8"));
  const out = { NET, LABEL, label: "SYNTHETIC BENCHMARK -- TEST-ONLY-SEED; not operational evidence, not production capacity", startedAt: new Date().toISOString() };

  const head = await provider.getBlockNumber();
  const blk = await provider.send("eth_getBlockByNumber", ["latest", false]);
  const reg = new ethers.Contract(ADDR.REGISTRY, ["function everActivated(address) view returns (bool)", "function isValidator(address) view returns (bool)"], provider);
  let allEver = true, anyVal = false; for (const a of payees) { if (!(await reg.everActivated(a))) allEver = false; if (await reg.isValidator(a)) anyVal = true; }
  out.preconditions = { head, blockGasLimit: Number(blk.gasLimit), epochCount: (await dist.epochCount()).toString(), lastSettledBlock: (await dist.lastSettledBlock()).toString(), rewardRateChangeCount: (await dist.rewardRateChangeCount()).toString(),
    firstEntry: (await dist.rewardRateChange(0)).map(String), lastEntry: (await dist.rewardRateChange(398)).map(String), distributorBalance: (await provider.getBalance(ADDR.DISTRIBUTOR)).toString(), payeesTotal: payees.length, payeesAllEverActivated: allEver, anyPayeeIsValidator: anyVal,
    rpcGasCapDefault_note: "Besu 26.9.0 --rpc-gas-cap default 100000000 (read from `besu --help`); not overridden in config.toml. --rpc-tx-feecap default 1e18 wei." };
  console.log("preconditions:", JSON.stringify(out.preconditions));
  if (out.preconditions.epochCount !== "0" || head < 550 || !allEver || anyVal) { out.result = "BLOCKED"; saveEvidence(`${NET}-E.json`, out); return; }

  const balance = BigInt(out.preconditions.distributorBalance);
  const matrix = [], csv = ["label,N,k,toBlock,rangeLen,sumBlocksMined,ratio,classification"];
  for (const N of NS) for (const k of KS) {
    const toBlock = 150 + k, len = toBlock; // range [1, toBlock]
    const base = Math.floor(len / N), rem = len % N;
    const blocksMined = payees.slice(0, N).map((_, i) => base + (i < rem ? 1 : 0));
    const sum = blocksMined.reduce((a, b) => a + b, 0);
    const ratio = sum / len;
    const cap = BigInt(await dist.maxRewardsForRange(1, toBlock));
    const totalFees = 0n;
    const totalRewards = cap < balance - totalFees ? cap : balance - totalFees;
    const data = iface.encodeFunctionData("distributeRewards", [{ fromBlock: 1, toBlock }, payees.slice(0, N), blocksMined, totalRewards, totalFees]);
    const row = { N, k, toBlock, rangeLen: len, sumBlocksMined: sum, ratio, classification: ratio < 1 ? "under-reported" : "complete", totalRewards: totalRewards.toString(), capForRange: cap.toString(), calldataBytes: (data.length - 2) / 2 };
    try { row.estimateGas = Number(BigInt(await call("eth_estimateGas", [{ from: oracle.address, to: ADDR.DISTRIBUTOR, data }]))); }
    catch (e) { row.estimateError = reason(e); }
    matrix.push(row);
    csv.push(`${LABEL},${N},${k},${toBlock},${len},${sum},${ratio},${row.classification}`);
    console.log(`N=${N} k=${k}:`, row.estimateGas ?? row.estimateError);
  }
  out.matrix = matrix;
  fs.mkdirSync(`${ROOT}/evidence/05-raw`, { recursive: true });
  fs.appendFileSync(`${ROOT}/evidence/05-raw/E-ratio.csv`, (fs.existsSync(`${ROOT}/evidence/05-raw/E-ratio.csv`) && fs.readFileSync(`${ROOT}/evidence/05-raw/E-ratio.csv`, "utf8").length ? csv.slice(1) : csv).join("\n") + "\n");

  // E03: estimateGas of maxRewardsForRange(1,toBlock)
  out.E03 = [];
  for (const k of KS) {
    const toBlock = 150 + k;
    const data = iface.encodeFunctionData("maxRewardsForRange", [1, toBlock]);
    const r = { k, toBlock, rateChangesInRange: Math.max(0, Math.min(399, toBlock - 150)) };
    try { r.estimateGas = Number(BigInt(await call("eth_estimateGas", [{ from: oracle.address, to: ADDR.DISTRIBUTOR, data }]))); } catch (e) { r.estimateError = reason(e); }
    out.E03.push(r);
  }
  // E02: linear fit gas = g0 + p*N + r*k over the matrix points that returned an estimate; plus per-N slope in k and per-k slope in N
  const ok = matrix.filter((m) => m.estimateGas);
  out.E02 = { points: ok.length };
  if (ok.length >= 4) {
    const [g0, perPayee, perRateChange] = lstsq(ok.map((m) => [1, m.N, m.k]), ok.map((m) => m.estimateGas));
    const resid = ok.map((m) => m.estimateGas - (g0 + perPayee * m.N + perRateChange * m.k));
    out.E02.fit = { model: "gas = g0 + perPayee*N + perRateChange*k   (k = number of rate entries inside the range, equal to the matrix k)", g0, perPayee, perRateChange, maxAbsResidual: Math.max(...resid.map(Math.abs)) };
    out.E02.perPayeeSlopeAtEachK = KS.map((k) => { const pts = ok.filter((m) => m.k === k); if (pts.length < 2) return { k, slope: null }; const a = pts[0], b = pts[pts.length - 1]; return { k, slope: (b.estimateGas - a.estimateGas) / (b.N - a.N) }; });
    out.E02.perRateChangeSlopeAtEachN = NS.map((N) => { const pts = ok.filter((m) => m.N === N); if (pts.length < 2) return { N, slope: null }; const a = pts[0], b = pts[pts.length - 1]; return { N, slope: (b.estimateGas - a.estimateGas) / (b.k - a.k) }; });
    out.E02.hardhatReference_note = "document's reference: ~2,800 gas per rate change inside maxRewardsForRange (Hardhat; comparison only)";
  }
  // E04: largest fits
  const gl = out.preconditions.blockGasLimit;
  const fits = (m, frac) => m.estimateGas && m.estimateGas <= gl * frac;
  out.E04 = {
    blockGasLimit: gl,
    largestN_at_k0: { fits: Math.max(0, ...matrix.filter((m) => m.k === 0 && fits(m, 1)).map((m) => m.N)), withMargin50pct: Math.max(0, ...matrix.filter((m) => m.k === 0 && fits(m, 0.5)).map((m) => m.N)) },
    largestK_at_N5: { fits: Math.max(-1, ...matrix.filter((m) => m.N === 5 && fits(m, 1)).map((m) => m.k)), withMargin50pct: Math.max(-1, ...matrix.filter((m) => m.N === 5 && fits(m, 0.5)).map((m) => m.k)) },
    largestK_at_N100: { fits: Math.max(-1, ...matrix.filter((m) => m.N === 100 && fits(m, 1)).map((m) => m.k)), withMargin50pct: Math.max(-1, ...matrix.filter((m) => m.N === 100 && fits(m, 0.5)).map((m) => m.k)) },
    note: "values are from the tested grid only (N in {5,25,50,100,150}, k in {0,1,20,100,399}); -1/0 = none of the tested values fits",
  };
  // E05: one real distribution with the heaviest fitting combination
  const fitting = matrix.filter((m) => m.estimateGas && m.estimateGas <= gl).sort((a, b) => b.estimateGas - a.estimateGas);
  if (fitting.length) {
    const h = fitting[0];
    const base = Math.floor(h.rangeLen / h.N), rem = h.rangeLen % h.N;
    const blocksMined = payees.slice(0, h.N).map((_, i) => base + (i < rem ? 1 : 0));
    const e5 = { combination: { N: h.N, k: h.k, toBlock: h.toBlock }, estimateGas: h.estimateGas };
    try {
      const txGas = Math.min(gl, Math.ceil(h.estimateGas * 1.25));
      const t = await dist.distributeRewards({ fromBlock: 1, toBlock: h.toBlock }, payees.slice(0, h.N), blocksMined, BigInt(h.totalRewards), 0n, { gasLimit: txGas });
      const r = await t.wait();
      e5.txGasLimit = txGas; e5.txHash = r.hash; e5.status = r.status; e5.gasUsed = r.gasUsed.toString(); e5.gasUsedOverEstimate = Number(r.gasUsed) / h.estimateGas; e5.block = r.blockNumber;
      e5.epochCountAfter = (await dist.epochCount()).toString(); e5.lastSettledAfter = (await dist.lastSettledBlock()).toString();
    } catch (e) { e5.sendError = reason(e); }
    out.E05 = e5;
    console.log("E05:", JSON.stringify(e5));
  } else out.E05 = { note: "no tested combination fit within the block gas limit; no real distribution sent" };
  out.finishedAt = new Date().toISOString();
  saveEvidence(`${NET}-E.json`, out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
