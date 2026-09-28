// Cross-contract check (Board.clearStaleVotes -> Registry.getValidatorInfo, 6-output ABI after the off-chain-verification redesign).
const hre = require("hardhat"); const fs = require("fs");
const REGISTRY_ADDR="0x3333333333333333333333333333333333333333", BOARD_ADDR="0x4444444444444444444444444444444444444444";
(async () => {
  const reg = JSON.parse(fs.readFileSync("artifacts3.json","utf8")), brd = JSON.parse(fs.readFileSync("board_artifact.json","utf8"));
  const [deployer, subject] = await hre.ethers.getSigners();
  for (const [art, addr] of [[reg.registry ?? reg, REGISTRY_ADDR],[brd, BOARD_ADDR]]) {
    const f = new hre.ethers.ContractFactory(art.abi, art.bytecode, deployer); const t = await f.deploy(); await t.waitForDeployment();
    await hre.network.provider.send("hardhat_setCode",[addr, await hre.network.provider.send("eth_getCode",[await t.getAddress(),"latest"])]);
  }
  const registry = new hre.ethers.Contract(REGISTRY_ADDR, reg.registry.abi, deployer), board = new hre.ethers.Contract(BOARD_ADDR, brd.abi, deployer);
  const L = n => reg.layout.storage.find(s=>s.label===n).slot;
  const setAt = (slotHex, v) => hre.network.provider.send("hardhat_setStorageAt",[REGISTRY_ADDR, slotHex, hre.ethers.zeroPadValue(hre.ethers.toBeHex(v),32)]);
  await setAt(hre.ethers.toBeHex(BigInt(L("recoveryPeriod"))), 172800);
  const base = BigInt(hre.ethers.solidityPackedKeccak256(["uint256","uint256"],[subject.address,0]));
  const now = (await hre.ethers.provider.getBlock("latest")).timestamp;
  await setAt(hre.ethers.toBeHex(base), 3);                // status = Demoted
  await setAt(hre.ethers.toBeHex(base + 4n), now);         // demotedAt = 5th struct field (slot +4) after the redesign
  const info = await registry.getValidatorInfo(subject.address);
  console.log("getValidatorInfo: status =", info[0].toString(), "| demotedAt(index 3) =", info[3].toString(), "| now =", now);
  if (info[3].toString() !== String(now)) { console.log("❌ ABI/slot mismatch"); process.exit(1); }
  let early=false; try { await board.clearStaleVotes.staticCall(subject.address); } catch(e){ early=true; }
  console.log(early ? "✅ clearStaleVotes زودهنگام رد شد" : "❌ زودهنگام موفق شد (باگ)");
  await hre.network.provider.send("evm_increaseTime",[172800 + 30*24*3600 + 10]); await hre.network.provider.send("evm_mine");
  let late=true; try { await (await board.clearStaleVotes(subject.address)).wait(); } catch(e){ late=false; console.log(e.shortMessage||e.message); }
  console.log(late ? "✅ بعد از recoveryPeriod + 30 روز موفق شد" : "❌ بعد از گذشت زمان هم شکست خورد");
  process.exit(early && late ? 0 : 1);
})().catch(e=>{console.error(e.message);process.exit(1);});
