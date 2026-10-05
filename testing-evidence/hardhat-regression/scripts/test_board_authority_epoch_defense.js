// لایه‌ی دوم دفاع مستقل: حتی اگر permanentlyExited (لایه‌ی اول) به‌هر دلیلی دور زده شود،
// membershipEpoch باید به‌تنهایی جلوی زنده‌شدن اختیار کرسی کهنه را بگیرد.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const REG = "0x3333333333333333333333333333333333333333", BOARD = "0x4444444444444444444444444444444444444444", IDR = "0x6666666666666666666666666666666666666666";
const inc = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };
(async () => {
  const art = JSON.parse(fs.readFileSync("artifacts3.json", "utf8")), b = JSON.parse(fs.readFileSync("board_artifact.json", "utf8"));
  const signers = await hre.ethers.getSigners(); const deployer = signers[0]; const A = signers.slice(2, 14);
  const put = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  await put(REG, art.registry.abi, art.registry.bytecode); await put(BOARD, b.abi, b.bytecode);
  await put("0x2222222222222222222222222222222222222222", art.mock.abi, art.mock.bytecode);
  const MOCK_ID = `pragma solidity ^0.8.24; contract MockID { function hasIdentity(address) external pure returns (bool) { return true; } }`;
  const outId = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "I.sol": { content: MOCK_ID } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  await put(IDR, outId.contracts["I.sol"].MockID.abi, "0x" + outId.contracts["I.sol"].MockID.evm.bytecode.object);
  const registry = new hre.ethers.Contract(REG, art.registry.abi, deployer); const board = new hre.ethers.Contract(BOARD, b.abi, deployer);
  const S = n => hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === n).slot));
  const setR = (n, v) => hre.network.provider.send("hardhat_setStorageAt", [REG, S(n), hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
  await setR('entryThresholdBase', hre.ethers.parseEther("500000")); await setR('growthFactorPerValidator', 1_017479692102686336n);
  await setR('membershipFeeBps', 400); await setR('maxEntriesPerWindow', 20); await setR('entryWindowSeconds', 86400);
  await setR('probationPeriod', 604800); await setR('recoveryPeriod', 172800); await setR('slashBps', 100); await setR('exitCooldown', 604800);
  await setR('verifier', deployer.address);
  for (const s of signers) await hre.network.provider.send("hardhat_setBalance", [s.address, "0x84595161401484A000000"]);
  const bS = n => hre.ethers.toBeHex(BigInt(b.layout.storage.find(s => s.label === n).slot));
  await hre.network.provider.send("hardhat_setStorageAt", [BOARD, bS('boardVersion'), hre.ethers.zeroPadValue("0x01", 32)]);

  const join = async (s) => { const th = await registry.currentEntryThreshold(), fee = await registry.currentMembershipFee(); await (await registry.connect(s).requestMembership({ value: th + fee })).wait(); };
  const activate = async (s) => { await inc(604800 + 1); await (await registry.connect(deployer).recordActivation(s.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("a" + s.address)))).wait(); };
  for (const v of A) await join(v);
  for (const v of A) await activate(v);
  for (const v of A) for (const c of A.slice(0, 5)) await (await board.connect(v).voteFor(c.address)).wait();
  await (await board.refreshBoard([])).wait();
  const v2 = A[2];
  console.log("v2 عضو هیأت، اپوک ثبت‌شده روی کرسی:", await board.seatMembershipEpoch(v2.address));

  await (await registry.connect(v2).requestExit()).wait();
  console.log("membershipEpoch(v2) بعد از خروج:", await registry.membershipEpoch(v2.address), "(باید ۱ باشد؛ کرسی هنوز ۰ دارد)");
  await inc(604800 + 1);
  await (await registry.connect(v2).withdrawStake()).wait();

  console.log("\n--- شبیه‌سازی دور زدن لایه‌ی اول: permanentlyExited را مستقیم روی storage false می‌کنیم (فرض یک باگ فرضی دیگر) ---");
  const permSlot = hre.ethers.keccak256(hre.ethers.concat([hre.ethers.zeroPadValue(v2.address, 32), hre.ethers.zeroPadValue(S('permanentlyExited'), 32)]));
  await hre.network.provider.send("hardhat_setStorageAt", [REG, permSlot, hre.ethers.zeroPadValue("0x00", 32)]);
  console.log("permanentlyExited(v2) بعد از دستکاری:", await registry.permanentlyExited(v2.address), "(false — یعنی لایه‌ی اول را نادیده گرفتیم)");

  await join(v2); // حالا باید موفق شود چون لایه‌ی اول را دور زدیم
  console.log("وضعیت v2 بعد از ثبت‌نام دوباره:", (await registry.getValidatorInfo(v2.address))[0].toString(), "(1=Probation)");
  console.log("membershipEpoch(v2):", await registry.membershipEpoch(v2.address), "vs seatMembershipEpoch(v2) کرسی کهنه:", await board.seatMembershipEpoch(v2.address));

  const auth = await board.hasBoardAuthority(v2.address);
  console.log("\n🔍 hasBoardAuthority(v2) با وجود دور زدن لایه‌ی اول:", auth);
  if (auth) { console.log("❌❌❌ لایه‌ی دوم هم شکست خورد."); process.exit(1); }
  console.log("✅✅✅ لایه‌ی دوم (membershipEpoch) مستقلاً جلوی زنده‌شدن اختیار کرسی کهنه را گرفت.");
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
