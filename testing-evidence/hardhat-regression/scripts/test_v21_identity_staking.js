// v2.1.0: IdentityRegistry (burned addresses report nothing and cannot be re-registered or re-verified; migration guards)
// and ServiceStaking (a stake with a pending withdrawal does not count).
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
let results = [];
function ok(name, c, extra = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + name + (c === true ? "" : " → " + c) + (extra ? "  " + extra : "")); }
async function reverts(fn, expected) { try { await (await fn()).wait(); return false; } catch (e) { return (e.message || "").includes(expected) ? true : "wrong reason: " + (e.message || "").slice(0, 200); } }
const imp = (p) => { const f = "contracts_src_" + p.replace("./", ""); return fs.existsSync(f) ? { contents: fs.readFileSync(f, "utf8") } : { error: "nf " + p }; };
function compile(file, name) { const input = { language: "Solidity", sources: { [name + ".sol"]: { content: fs.readFileSync(file, "utf8") } }, settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { "*": { "*": ["abi", "evm.bytecode.object", "storageLayout"] } } } };
  const o = JSON.parse(solc.compile(JSON.stringify(input), { import: imp })); const e = (o.errors || []).filter(x => x.severity === "error"); if (e.length) throw new Error(e[0].formattedMessage); const c = o.contracts[name + ".sol"][name]; return { abi: c.abi, bytecode: "0x" + c.evm.bytecode.object, layout: c.storageLayout }; }
(async () => {
  const [deployer, oracle, u1, u2, u3, u4] = await hre.ethers.getSigners();
  // ---------- IdentityRegistry at its fixed address ----------
  fs.copyFileSync("../../contracts/IdentityRegistry.sol", "contracts_src_IdentityRegistry.sol");
  const idc = compile("contracts_src_IdentityRegistry.sol", "IdentityRegistry"); const IDR = "0x6666666666666666666666666666666666666666";
  const tmp = await new hre.ethers.ContractFactory(idc.abi, idc.bytecode, deployer).deploy(); await tmp.waitForDeployment();
  await hre.network.provider.send("hardhat_setCode", [IDR, await hre.network.provider.send("eth_getCode", [await tmp.getAddress(), "latest"])]);
  const slotO = idc.layout.storage.find(s => s.label === "identityOracle").slot;
  await hre.network.provider.send("hardhat_setStorageAt", [IDR, hre.ethers.toBeHex(BigInt(slotO)), hre.ethers.zeroPadValue(oracle.address, 32)]);
  const idr = new hre.ethers.Contract(IDR, idc.abi, deployer);
  await (await idr.connect(u1).registerIdentity(0, "Alice")).wait();
  await (await idr.connect(oracle).setPhoneVerified(u1.address, true)).wait(); await (await idr.connect(oracle).setKycVerified(u1.address, true, hre.ethers.id("c"))).wait();
  let st = await idr.getVerificationStatus(u1.address);
  ok("I1) before migration the status is reported (registered, phone, kyc)", st[0] && st[1] && !st[2] && st[3] && (await idr.hasIdentity(u1.address)));
  await (await idr.connect(oracle).migrateIdentity(u1.address, u2.address)).wait();
  st = await idr.getVerificationStatus(u1.address);
  ok("I2) after migration the burned address reports nothing: getVerificationStatus is all false", !st[0] && !st[1] && !st[2] && !st[3]);
  ok("I3) hasIdentity is false for the burned address", (await idr.hasIdentity(u1.address)) === false);
  st = await idr.getVerificationStatus(u2.address);
  ok("I4) the new address carries the status (registered, phone, kyc)", st[0] && st[1] && !st[2] && st[3] && (await idr.hasIdentity(u2.address)));
  ok("I5) the oracle cannot verify the burned address again (phone)", await reverts(() => idr.connect(oracle).setPhoneVerified(u1.address, true), "burned"));
  ok("I6) ... nor telegram", await reverts(() => idr.connect(oracle).setTelegramVerified(u1.address, true), "burned"));
  ok("I7) ... nor KYC", await reverts(() => idr.connect(oracle).setKycVerified(u1.address, true, hre.ethers.id("x")), "burned"));
  ok("I8) the burned address cannot register an identity again", await reverts(() => idr.connect(u1).registerIdentity(0, "Alice2"), "burned"));
  ok("I9) a burned address cannot be migrated again", await reverts(() => idr.connect(oracle).migrateIdentity(u1.address, u3.address), "already migrated"));
  await (await idr.connect(u3).registerIdentity(1, "Corp")).wait();
  ok("I10) migrating to the same address is refused", await reverts(() => idr.connect(oracle).migrateIdentity(u3.address, u3.address), "equals old address"));
  ok("I11) migrating onto an address that was itself migrated is refused", await reverts(() => idr.connect(oracle).migrateIdentity(u3.address, u1.address), "itself migrated"));
  ok("I12) the raw record of the burned address is kept (liability not erased): migratedTo is set", (await idr.identities(u1.address)).migratedTo === u2.address);
  ok("I13) verification setters still work for a normal address", (await reverts(() => idr.connect(oracle).setTelegramVerified(u2.address, true), "NONE")) === false && (await idr.getVerificationStatus(u2.address))[2] === true);
  ok("I14) a non-oracle caller is still refused", await reverts(() => idr.connect(u4).setPhoneVerified(u2.address, true), "not the identity oracle"));

  // ---------- ServiceStaking ----------
  const sc = compile("../../contracts/ServiceStaking.sol", "ServiceStaking");
  const ss = await new hre.ethers.ContractFactory(sc.abi, sc.bytecode, deployer).deploy(); await ss.waitForDeployment();
  const E = hre.ethers.parseEther("100");
  const NAMING = 0, CRED = 2;
  await (await ss.connect(u1).stake(CRED, { value: E })).wait();
  ok("S1) a stake counts: hasMinimumStake true at the exact amount", (await ss.hasMinimumStake(u1.address, CRED, E)) === true && (await ss.stakeOf(u1.address, CRED)) === E);
  ok("S2) it does not count for a higher minimum", (await ss.hasMinimumStake(u1.address, CRED, E + 1n)) === false);
  await (await ss.connect(u1).requestWithdrawal(CRED)).wait();
  ok("S3) with a withdrawal pending, hasMinimumStake is false (stakeOf still shows the amount)", (await ss.hasMinimumStake(u1.address, CRED, E)) === false && (await ss.stakeOf(u1.address, CRED)) === E);
  await (await ss.connect(u1).stake(CRED, { value: 1n })).wait();
  ok("S4) staking more cancels the pending request and the stake counts again", (await ss.hasMinimumStake(u1.address, CRED, E)) === true);
  await (await ss.connect(u2).stake(NAMING, { value: E })).wait();
  ok("S5) a zero-cooldown service: the stake counts while held", (await ss.hasMinimumStake(u2.address, NAMING, E)) === true);
  await (await ss.connect(u2).withdraw(NAMING)).wait();
  ok("S6) after withdrawal it no longer counts (a zero-cooldown stake is a point-in-time proof only)", (await ss.hasMinimumStake(u2.address, NAMING, 1n)) === false);
  const pass = results.filter(Boolean).length; console.log("\nresult: " + pass + "/" + results.length + " passed"); process.exit(pass === results.length ? 0 : 1);
})().catch(e => { console.error("error:", e.message); process.exit(1); });
