const hre = require("hardhat");
const fs = require("fs");
const solc = require('solc');

const BOARD_ADDR = "0x4444444444444444444444444444444444444444";
const REGISTRY_ADDR = "0x3333333333333333333333333333333333333333";
const IDENTITY_ADDR = "0x6666666666666666666666666666666666666666";

async function main() {
  console.log("=== بررسی مورد ۵: آیا refreshBoard بدون تغییر عضویت، boardVersion رو افزایش می‌ده؟ ===\n");

  const boardArt = JSON.parse(fs.readFileSync("board_artifact.json", "utf8"));
  const [deployer, b1, b2, b3, b4, b5, v1, v2, v3, v4, v5] = await hre.ethers.getSigners();

  // Registry mock: getValidators() پنج ولیدیتور رو برمی‌گردونه، isValidator هم برای همه‌ی
  // ۵ ولیدیتور رأی‌دهنده و ۵ کاندید هیأت‌مدیره true برمی‌گردونه
  const voterAddrs = [v1, v2, v3, v4, v5].map(s => s.address);
  const candidateAddrs = [b1, b2, b3, b4, b5].map(s => s.address);
  const allActive = [...voterAddrs, ...candidateAddrs];
  const mockSrc = `
    pragma solidity ^0.8.24;
    contract MockRegistry {
        address[] public voters;
        mapping(address => bool) public activeMap;
        constructor(address[] memory _voters, address[] memory _allActive) {
            for (uint i = 0; i < _voters.length; i++) voters.push(_voters[i]);
            for (uint i = 0; i < _allActive.length; i++) activeMap[_allActive[i]] = true;
        }
        function getValidators() external view returns (address[] memory) { return voters; }
        function isValidator(address who) external view returns (bool) { return activeMap[who]; }
    }
    contract MockIdentity {
        function hasIdentity(address) external pure returns (bool) { return true; }
    }
  `;
  const input = { language: 'Solidity', sources: { 'Mock.sol': { content: mockSrc } }, settings: { outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } } } };
  const out = JSON.parse(solc.compile(JSON.stringify(input)));
  const regMock = out.contracts['Mock.sol']['MockRegistry'];
  const idMock = out.contracts['Mock.sol']['MockIdentity'];

  const regFactory = new hre.ethers.ContractFactory(regMock.abi, '0x' + regMock.evm.bytecode.object, deployer);
  const tempReg = await regFactory.deploy(voterAddrs, allActive);
  await tempReg.waitForDeployment();
  const regCode = await hre.network.provider.send("eth_getCode", [await tempReg.getAddress(), "latest"]);
  await hre.network.provider.send("hardhat_setCode", [REGISTRY_ADDR, regCode]);
  // چون constructor آرگومان داره، باید storage واقعی (نه فقط code) رو هم کپی کنیم — با خوندن slotها
  // ساده‌تر: مستقیم از tempReg بخونیم storage رو (چون آرایه/mapping پیچیده‌ست، به‌جاش یه راه ساده‌تر:
  // دوباره با همون آرگومان، ولی این‌بار مستقیم روی آدرس ثابت با یه روش متفاوت دیپلوی کنیم)
  // راه ساده: از hardhat_setStorageAt برای هر slot لازم استفاده کنیم — ولی چون آرایه‌ی دینامیک و
  // mapping داریم، به‌جاش directly از eth_call روی tempReg برای مقداردهی به‌عنوان reference استفاده
  // نمی‌کنیم؛ در عوض یه رویکرد ساده‌تر: قرارداد رو با یه selfdestruct-free proxy مجدد در آدرس مقصد
  // دیپلوی می‌کنیم. برای سادگی، از impersonation + مستقیم فراخوانی سازنده معادل استفاده می‌کنیم:
  const registryAtFixed = new hre.ethers.Contract(REGISTRY_ADDR, regMock.abi, deployer);
  // چک کنیم آیا واقعا کار می‌کنه (اگه storage منتقل نشده باشه، این خالی برمی‌گرده)
  let testVoters;
  try { testVoters = await registryAtFixed.getValidators(); } catch(e) { testVoters = []; }
  if (testVoters.length === 0) {
    console.log("⚠️ storage منتقل نشد (طبق انتظار — فقط deployedBytecode کپی شده)، از روش جایگزین استفاده می‌کنیم...");
    // روش جایگزین: به‌جای Registry واقعی، یه نسخه‌ی "بدون constructor" با state از پیش hardcode شده می‌سازیم
    const mockSrc2 = `
      pragma solidity ^0.8.24;
      contract MockRegistry2 {
          function getValidators() external pure returns (address[] memory) {
              address[] memory a = new address[](5);
              a[0] = ${voterAddrs[0]};
              a[1] = ${voterAddrs[1]};
              a[2] = ${voterAddrs[2]};
              a[3] = ${voterAddrs[3]};
              a[4] = ${voterAddrs[4]};
              return a;
          }
          function isValidator(address who) external pure returns (bool) {
              return ${allActive.map(a => `who == ${a}`).join(' || ')};
          }
      }
    `;
    const input2 = { language: 'Solidity', sources: { 'Mock2.sol': { content: mockSrc2 } }, settings: { outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } } } };
    const out2 = JSON.parse(solc.compile(JSON.stringify(input2)));
    const regMock2 = out2.contracts['Mock2.sol']['MockRegistry2'];
    const regFactory2 = new hre.ethers.ContractFactory(regMock2.abi, '0x' + regMock2.evm.bytecode.object, deployer);
    const tempReg2 = await regFactory2.deploy();
    await tempReg2.waitForDeployment();
    const regCode2 = await hre.network.provider.send("eth_getCode", [await tempReg2.getAddress(), "latest"]);
    await hre.network.provider.send("hardhat_setCode", [REGISTRY_ADDR, regCode2]);
  }

  // Identity mock (پابرجا، بدون state)
  const idFactory = new hre.ethers.ContractFactory(idMock.abi, '0x' + idMock.evm.bytecode.object, deployer);
  const tempId = await idFactory.deploy();
  await tempId.waitForDeployment();
  const idCode = await hre.network.provider.send("eth_getCode", [await tempId.getAddress(), "latest"]);
  await hre.network.provider.send("hardhat_setCode", [IDENTITY_ADDR, idCode]);

  // دیپلوی Board
  const boardFactory = new hre.ethers.ContractFactory(boardArt.abi, boardArt.bytecode, deployer);
  const tempBoard = await boardFactory.deploy();
  await tempBoard.waitForDeployment();
  const boardCode = await hre.network.provider.send("eth_getCode", [await tempBoard.getAddress(), "latest"]);
  await hre.network.provider.send("hardhat_setCode", [BOARD_ADDR, boardCode]);
  const board = new hre.ethers.Contract(BOARD_ADDR, boardArt.abi, deployer);

  const bvSlot = boardArt.layout.storage.find(s => s.label === 'boardVersion').slot;
  await hre.network.provider.send("hardhat_setStorageAt", [BOARD_ADDR, "0x" + BigInt(bvSlot).toString(16), hre.ethers.zeroPadValue("0x01", 32)]);

  for (const s of [v1, v2, v3, v4, v5]) {
    await hre.network.provider.send("hardhat_setBalance", [s.address, "0x84595161401484A000000"]);
  }

  // هر ۵ ولیدیتور به هر ۵ کاندیدا رأی می‌دن (تا نتیجه یه هیأت‌مدیره‌ی پایدار و مساوی باشه)
  for (const voter of [v1, v2, v3, v4, v5]) {
    for (const cand of candidateAddrs) {
      await (await board.connect(voter).voteFor(cand)).wait();
    }
  }
  console.log("✅ همه‌ی ۵ ولیدیتور به همه‌ی ۵ کاندیدا رأی دادند");

  await (await board.refreshBoard()).wait();
  const versionAfterFirst = await board.boardVersion();
  console.log("boardVersion بعد از اولین refreshBoard واقعی (نصب اولیه‌ی هیأت‌مدیره):", versionAfterFirst.toString());

  const membersAfterFirst = [];
  for (const c of candidateAddrs) membersAfterFirst.push(await board.isBoardMember(c));
  console.log("همه‌ی ۵ کاندید عضو شدند؟", membersAfterFirst.every(x => x));

  // حالا دوباره refreshBoard رو صدا می‌زنیم — چون هیچ رأی جدیدی نیومده، باید همون ۵ عضو دقیقاً برگرده
  await (await board.refreshBoard()).wait();
  const versionAfterSecond = await board.boardVersion();
  console.log("boardVersion بعد از دومین refreshBoard (بدون هیچ رأی تازه، عضویت باید عیناً تکرار بشه):", versionAfterSecond.toString());

  if (versionAfterSecond.toString() === versionAfterFirst.toString()) {
    console.log("\n✅✅✅ اصلاح تأیید شد: refreshBoard وقتی عضویت واقعاً عوض نشده، boardVersion رو افزایش نمی‌ده.");
    console.log("(دیگه نمی‌شه با صدازدن مکرر و رایگان refreshBoard، پیشنهادهای باز رو بی‌دلیل باطل کرد)");
  } else {
    console.log("\n❌❌❌ باگ هنوز پابرجاست: boardVersion از", versionAfterFirst.toString(), "به", versionAfterSecond.toString(), "افزایش پیدا کرد، بدون تغییر واقعی عضویت!");
  }
}

main().catch((e) => { console.error("خطای غیرمنتظره:", e.message); process.exit(1); });
