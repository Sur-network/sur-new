const hre = require("hardhat"); const fs = require("fs");
const REGISTRY_ADDR = "0x3333333333333333333333333333333333333333";
(async () => {
  const art = JSON.parse(fs.readFileSync("artifacts3.json","utf8"));
  const signers = await hre.ethers.getSigners(); const deployer = signers[0];
  const f = new hre.ethers.ContractFactory(art.registry.abi, art.registry.bytecode, deployer);
  const tmp = await f.deploy(); await tmp.waitForDeployment();
  const code = await hre.network.provider.send("eth_getCode",[await tmp.getAddress(),"latest"]);
  await hre.network.provider.send("hardhat_setCode",[REGISTRY_ADDR, code]);
  const reg = new hre.ethers.Contract(REGISTRY_ADDR, art.registry.abi, deployer);
  // یک ولیدیتور فعال با ذخیره‌ی مستقیم: status=Active(2) و activeValidators=[addr]
  const me = signers[2].address;
  const base = BigInt(hre.ethers.solidityPackedKeccak256(["uint256","uint256"],[me,0]));
  await hre.network.provider.send("hardhat_setStorageAt",[REGISTRY_ADDR,hre.ethers.toBeHex(base),hre.ethers.zeroPadValue("0x02",32)]);
  const L = (n)=>art.layout.storage.find(s=>s.label===n);
  // activeValidators (dynamic array): length=1, element0=me ; activeIndex[me]=1
  const avSlot = BigInt(L("activeValidators").slot);
  await hre.network.provider.send("hardhat_setStorageAt",[REGISTRY_ADDR,hre.ethers.toBeHex(avSlot),hre.ethers.zeroPadValue("0x01",32)]);
  const arrBase = BigInt(hre.ethers.keccak256(hre.ethers.zeroPadValue(hre.ethers.toBeHex(avSlot),32)));
  await hre.network.provider.send("hardhat_setStorageAt",[REGISTRY_ADDR,hre.ethers.toBeHex(arrBase),hre.ethers.zeroPadValue(me,32)]);
  const aiSlot = hre.ethers.keccak256(hre.ethers.concat([hre.ethers.zeroPadValue(me,32),hre.ethers.zeroPadValue(hre.ethers.toBeHex(BigInt(L("activeIndex").slot)),32)]));
  await hre.network.provider.send("hardhat_setStorageAt",[REGISTRY_ADDR,aiSlot,hre.ethers.zeroPadValue("0x01",32)]);
  const r = reg.connect(signers[2]);
  let ok=true;
  for (const [v,expectRevert] of [[3600,true],[60,true],[3601,false]]) {
    try { await (await r.proposeParameterChange(4 === 4 ? 3 : 3, v)).wait(); // ParamKey.RecoveryPeriod = 3
      console.log(`recoveryPeriod=${v}:`, expectRevert ? "❌ نباید پذیرفته می‌شد" : "✅ پذیرفته شد"); if(expectRevert) ok=false;
    } catch(e){ console.log(`recoveryPeriod=${v}:`, expectRevert ? "✅ درست رد شد" : "❌ نباید رد می‌شد", "|", (e.reason||e.shortMessage||"").slice(0,80)); if(!expectRevert) ok=false; }
  }
  console.log(ok ? "\n✅✅✅ حد پایین recoveryPeriod در زمان پیشنهاد اعمال می‌شود" : "\n❌ شکست"); process.exit(ok?0:1);
})().catch(e=>{console.error(e.message);process.exit(1);});
