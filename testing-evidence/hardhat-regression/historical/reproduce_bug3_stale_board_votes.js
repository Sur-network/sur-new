const hre = require("hardhat");
const fs = require("fs");

const BOARD_ADDR = "0x4444444444444444444444444444444444444444";
const TREASURY_ADDR = "0x5555555555555555555555555555555555555555";

async function main() {
  console.log("=== بازتولید باگ ۳: رأی اعضای سابق هیأت‌مدیره همچنان شمرده می‌شه ===\n");

  const boardArt = JSON.parse(fs.readFileSync("board_artifact.json", "utf8"));
  const treasuryArt = JSON.parse(fs.readFileSync("treasury_artifact.json", "utf8"));
  const [deployer, b1, b2, b3, b4, b5, recipient] = await hre.ethers.getSigners();

  // دیپلوی Board
  const boardFactory = new hre.ethers.ContractFactory(boardArt.abi, boardArt.bytecode, deployer);
  const tempBoard = await boardFactory.deploy();
  await tempBoard.waitForDeployment();
  const boardCode = await hre.network.provider.send("eth_getCode", [await tempBoard.getAddress(), "latest"]);
  await hre.network.provider.send("hardhat_setCode", [BOARD_ADDR, boardCode]);
  const board = new hre.ethers.Contract(BOARD_ADDR, boardArt.abi, deployer);

  // دیپلوی Treasury
  const treasuryFactory = new hre.ethers.ContractFactory(treasuryArt.abi, treasuryArt.bytecode, deployer);
  const tempTreasury = await treasuryFactory.deploy();
  await tempTreasury.waitForDeployment();
  const treasuryCode = await hre.network.provider.send("eth_getCode", [await tempTreasury.getAddress(), "latest"]);
  await hre.network.provider.send("hardhat_setCode", [TREASURY_ADDR, treasuryCode]);
  const treasury = new hre.ethers.Contract(TREASURY_ADDR, treasuryArt.abi, deployer);

  // ست‌کردن سقف‌های خزانه (وگرنه boardApproveExpenditure رد می‌شه)
  await hre.network.provider.send("hardhat_setStorageAt", [TREASURY_ADDR, "0x3", hre.ethers.zeroPadValue(hre.ethers.toBeHex(hre.ethers.parseEther("1000")), 32)]);
  await hre.network.provider.send("hardhat_setStorageAt", [TREASURY_ADDR, "0x4", hre.ethers.zeroPadValue(hre.ethers.toBeHex(hre.ethers.parseEther("10000")), 32)]);
  await deployer.sendTransaction({ to: TREASURY_ADDR, value: hre.ethers.parseEther("500") });

  // مستقیم boardMembers رو با ۵ عضو اولیه (b1..b5) پر می‌کنیم — بدون نیاز به رأی‌گیری refreshBoard
  const bmSlot = boardArt.layout.storage.find(s => s.label === 'boardMembers').slot;
  const isBMSlot = boardArt.layout.storage.find(s => s.label === 'isBoardMember').slot;

  // طول آرایه‌ی boardMembers رو ۵ می‌ذاریم
  await hre.network.provider.send("hardhat_setStorageAt", [BOARD_ADDR, "0x" + BigInt(bmSlot).toString(16), hre.ethers.zeroPadValue("0x05", 32)]);
  // محتوای آرایه توی keccak256(slot) شروع می‌شه
  const arrayBase = BigInt(hre.ethers.keccak256(hre.ethers.zeroPadValue(hre.ethers.toBeHex(bmSlot), 32)));
  const initialMembers = [b1, b2, b3, b4, b5];
  for (let i = 0; i < 5; i++) {
    const slot = "0x" + (arrayBase + BigInt(i)).toString(16);
    await hre.network.provider.send("hardhat_setStorageAt", [BOARD_ADDR, slot, hre.ethers.zeroPadValue(initialMembers[i].address, 32)]);
    const mapSlot = hre.ethers.keccak256(hre.ethers.concat([hre.ethers.zeroPadValue(initialMembers[i].address, 32), hre.ethers.zeroPadValue(hre.ethers.toBeHex(isBMSlot), 32)]));
    await hre.network.provider.send("hardhat_setStorageAt", [BOARD_ADDR, mapSlot, hre.ethers.zeroPadValue("0x01", 32)]);
  }
  console.log("✅ هیأت‌مدیره‌ی اولیه (b1..b5) مستقیم ست شد");

  // ست‌کردن boardVersion=1 (چون فقط deployedBytecode کپی شد، نه storage اولیه)
  const bvSlot = boardArt.layout.storage.find(s => s.label === 'boardVersion').slot;
  await hre.network.provider.send("hardhat_setStorageAt", [BOARD_ADDR, "0x" + BigInt(bvSlot).toString(16), hre.ethers.zeroPadValue("0x01", 32)]);

  for (const s of [b1, b2, b3, b4, b5]) {
    await hre.network.provider.send("hardhat_setBalance", [s.address, "0x84595161401484A000000"]);
  }

  // b1 پیشنهاد می‌ده (خودکار ۱ رأی می‌زنه)
  const tx1 = await board.connect(b1).proposeApproveBudget(recipient.address, hre.ethers.parseEther("100"), "test payment");
  const receipt1 = await tx1.wait();
  let actionId;
  for (const log of receipt1.logs) {
    try {
      const parsed = board.interface.parseLog(log);
      if (parsed.name === "ActionProposed") actionId = parsed.args.id;
    } catch (e) {}
  }
  console.log("✅ b1 پیشنهاد داد و خودکار رأی داد (رأی ۱ از ۳ لازم)، actionId:", actionId.toString());

  // b2 رأی می‌ده
  await (await board.connect(b2).voteAction(actionId)).wait();
  console.log("✅ b2 هم رأی داد (رأی ۲ از ۳ لازم)");

  // حالا b1 و b2 رو از هیأت‌مدیره خارج می‌کنیم (isBoardMember=false) - دقیقاً معادل اثر یه refreshBoard که این دو رو کنار گذاشته
  const mapSlotB1 = hre.ethers.keccak256(hre.ethers.concat([hre.ethers.zeroPadValue(b1.address, 32), hre.ethers.zeroPadValue(hre.ethers.toBeHex(isBMSlot), 32)]));
  const mapSlotB2 = hre.ethers.keccak256(hre.ethers.concat([hre.ethers.zeroPadValue(b2.address, 32), hre.ethers.zeroPadValue(hre.ethers.toBeHex(isBMSlot), 32)]));
  await hre.network.provider.send("hardhat_setStorageAt", [BOARD_ADDR, mapSlotB1, hre.ethers.zeroPadValue("0x00", 32)]);
  await hre.network.provider.send("hardhat_setStorageAt", [BOARD_ADDR, mapSlotB2, hre.ethers.zeroPadValue("0x00", 32)]);
  // ✅ معادل اثر واقعی refreshBoard() بعد از اصلاح: نسخه‌ی هیأت‌مدیره افزایش پیدا می‌کنه
  await hre.network.provider.send("hardhat_setStorageAt", [BOARD_ADDR, "0x" + BigInt(bvSlot).toString(16), hre.ethers.zeroPadValue("0x02", 32)]);
  console.log("✅ b1 و b2 از هیأت‌مدیره خارج شدند + boardVersion از ۱ به ۲ افزایش یافت (معادل refreshBoard واقعی)");

  const isB1Member = await board.isBoardMember(b1.address);
  const isB2Member = await board.isBoardMember(b2.address);
  console.log("تأیید خروج: b1 عضوه؟", isB1Member, "| b2 عضوه؟", isB2Member);

  // فقط b3 (که واقعاً عضو فعلیه) رأی سوم رو می‌زنه
  console.log("\n🔍 حالا فقط b3 (یه عضو *فعلی* هیأت‌مدیره) رأی سوم رو می‌زنه...");
  const balBefore = await hre.ethers.provider.getBalance(recipient.address);
  try {
    await (await board.connect(b3).voteAction(actionId)).wait();
    console.log("رأی b3 پذیرفته شد!");
  } catch (e) {
    console.log("✅✅✅ اصلاح تأیید شد: رأی b3 رد شد —", e.reason || e.shortMessage);
    console.log("(چون این پیشنهاد با نسخه‌ی قدیمی هیأت‌مدیره ساخته شده بود؛ حالا باید از نو پیشنهاد داده بشه)");
    return;
  }
  const balAfter = await hre.ethers.provider.getBalance(recipient.address);
  const paid = balAfter - balBefore;
  console.log("مبلغ پرداخت‌شده به recipient:", hre.ethers.formatEther(paid), "سورن");

  if (paid > 0n) {
    console.log("\n❌❌❌ هنوز باگ باقیه: پرداخت با نصاب ۳ رأی اجرا شد، درحالی‌که فقط ۱ رأی (b3) از اعضای *فعلی* هیأت‌مدیره بود!");
  } else {
    console.log("\n✅ پرداخت اجرا نشد — رفتار درست بود.");
  }
}

main().catch((e) => { console.error("خطای غیرمنتظره:", e.message); process.exit(1); });
