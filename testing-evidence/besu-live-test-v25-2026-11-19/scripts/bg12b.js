// BG-12b getValidators() gas/size sanity: eth_estimateGas and eth_call latency of getValidators() at the validator counts available on the live nets
// (Net-S n=1, Net-T n=1/2 earlier, Net-A n=6). No large list can be built on Besu without many activations: extrapolation is arithmetic only.
const { Net, Checks, writeResult, ethers, ADDR } = require("./lib");
(async () => {
  const c = new Checks();
  const rows = [];
  for (const k of ["S", "A"]) {
    const net = new Net(k, "n1");
    const reg = net.c("REG");
    const n = (await reg.getValidators()).length;
    const data = reg.interface.encodeFunctionData("getValidators");
    const gas = Number(BigInt(await net.provider.send("eth_estimateGas", [{ to: ADDR.REG, data }])));
    const t0 = process.hrtime.bigint();
    for (let i = 0; i < 20; i++) await net.provider.call({ to: ADDR.REG, data });
    const ms = Number(process.hrtime.bigint() - t0) / 1e6 / 20;
    rows.push({ net: net.def.name, validators: n, estimateGas: gas, avgEthCallMs: Math.round(ms * 10) / 10, returnBytes: 64 + 32 * n });
  }
  const slope = (rows[1].estimateGas - rows[0].estimateGas) / (rows[1].validators - rows[0].validators);
  const proj = { perValidatorGasApprox: Math.round(slope), n7: Math.round(rows[0].estimateGas + slope * 6), n100: Math.round(rows[0].estimateGas + slope * 99), n1000: Math.round(rows[0].estimateGas + slope * 999) };
  c.ok("getValidators() works through eth_call/eth_estimateGas on Besu for n=1 and n=6", rows.every((r) => r.estimateGas > 21000 && r.validators >= 1), rows);
  c.ok("cost is linear and small (~" + proj.perValidatorGasApprox + " gas per validator; n=100 ~" + proj.n100 + " gas) - far below the 30M block gas limit", proj.n100 < 30_000_000 && slope > 0, proj);
  writeResult("BG-12b", { verdict: c.verdict, summary: `getValidators() gas ${rows.map((r) => r.validators + " validators: " + r.estimateGas).join("; ")}`, checks: c.items, rows, projection: proj, limitation: "measured only for n=1 and n=6; larger lists are an arithmetic extrapolation, and the gas Besu itself grants to the contract-mode system call was not observed" });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
