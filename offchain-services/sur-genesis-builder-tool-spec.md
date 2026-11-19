# مشخصات فنی کامل — ابزار ساخت genesis.json

> **وضعیت پیاده‌سازی (۲۰۲۶-۱۱-۱۹):** از طرح ۲٫۵ این بخش‌ها اکنون در `contracts/` نوشته و با ۹۷ آزمون Hardhat در ۱۰ فایل (روی EVM درون‌فرایندی Hardhat، نه Besu/QBFT) آزموده شده‌اند: `FoundationDAO` (با نوع آزاد `Execute` و `EndSale`)، `FoundationMembers`، `SurenSale` (مدل صرافی، بدون اوراکل پرداخت)، `ValidatorLottery`، `GenesisClaimsVault` (صندوق طلب‌ها؛ ۲۴ قسط ماهانه)، حذف ولیدیتور در بازیابی شبکه (`RemovedInRecovery`)، تغییرات `IdentityRegistry` (بله/ایمیل، `isFullyVerified`)، `ValidatorSeatNFT` (صندلی ERC-721 با انتقال و قواعد خریدار)، هستهٔ بازطراحی `ValidatorsRegistry`/`ValidatorsBoard` (وثیقهٔ ثابت، کلید مالک/اپراتور، جریان مؤسسان، `SelfSuspended`، سوزاندن ۱۰۰٪ جریمه، قواعد فاصلهٔ ورود) و سوزاندن مازاد پاداش در `BlockRewardDistributor`. هنوز نوشته نشده‌اند: `RewardRouter` (سرویس آف‌چین، نه قرارداد)، سرویس‌های Verifier و Identity، ابزار genesis، بررسی‌های آف‌چین Verifier برای تعلیق داوطلبانه و ازسرگیری، و حدود تغییر ریوارد (±۱۰٪ و ۶ ماه فاصله؛ در `proposeRateChange` هنوز نیست). پوشه‌های `contracts/` و `contracts-fa/` فقط نسخهٔ جاری را نگه می‌دارند؛ نسخه‌های قدیمی در git هستند (برچسب `v2.2.0`). خودِ ابزار genesis هنوز نوشته نشده است؛ ✅ دور اول آزمون زندهٔ Besu برای قراردادهای ۲٫۵ انجام شد (۲۰۲۶-۱۱-۱۹؛ Besu 26.9.0 در Docker، QBFT، فورک London، یک میزبان، اجراهای کوتاه؛ ۲۲ فایل نتیجه؛ دو اجرای اول به‌علت اشکال اسکریپت ناموفق ثبت و نگه داشته شده‌اند، بقیه گذشتند): `testing-evidence/besu-live-test-v25-2026-11-19/REPORT.md`. 🔶 هنوز روی Besu اجرا نشده: هر تایمر ۷۲ ساعت و بیشتر (قفل ۹۰ روزه، انقضا و ارجاع ۷روزه، دورهٔ آزمایشی و مهلت ورود با مقدار واقعی)، آزادسازی ماهانهٔ صندوق طلب‌ها، `recordSuspension`/رخداد جمعی/جریمه/اعتراض/`recordRecovery`، لاتاری دوم، تازه‌سازی ماهانهٔ هیأت، حکمرانی نرخ ریوارد، گذار Shanghai/Cancun، `SurenSale`، `ServiceStaking` و خرج خزانه؛ یافته‌های باز F-1 تا F-7 در `sur-master-open-items.md` بخش ۵. حسابرسی امنیتی هم انجام نشده است؛ این نتیجه آمادگی تولید نیست.

> این سند به‌تنهایی برای پیاده‌سازی کافی است. هر ورودی، الگوریتم، و تصمیم فنی‌ای که لازم است، همین‌جا مشخص شده. ✅ نام تابع‌ها، متغیرها و فایل‌های کمکی قراردادهای ساختاری (`FoundationDAO`، `FoundationMembers`، `ValidatorLottery`، `GenesisClaimsVault`، `ValidatorSeatNFT`، `ValidatorsRegistry`/`ValidatorsBoard`) همان نام کد است و کمکی‌های seed شش قرارداد نوشته شده‌اند؛ خودِ ابزار genesis هنوز نوشته نشده است.

## ۱. نقش کلی — این ابزار دقیقاً چه مشکلی را حل می‌کند

ده قرارداد ساختاری سور (`FoundationDAO`, `FoundationMembers`, `BlockRewardDistributor`, `ValidatorsRegistry`, `ValidatorsBoard`, `ValidatorsTreasury`, `IdentityRegistry`, `ValidatorSeatNFT`, `GenesisClaimsVault`, `ValidatorLottery`؛ آدرس‌های پیشنهادی چهار قرارداد تازه: `0x7777…7777`، `0x8888…8888`، `0x9999…9999`، `0xAaAa…AaAa`) هیچ‌کدام `constructor` ندارند — چون مستقیم در بخش `alloc` بلاک genesis تزریق می‌شوند (بایت‌کد + storage نهایی، نه یک تراکنش دیپلوی). دلیل این تصمیم: قراردادهای دارای `constructor` که به این روش genesis می‌شوند، در عمل نمی‌توانند روی اکسپلوررهایی مثل Blockscout وریفای شوند (گزارش باگ رسمی Blockscout، GitHub issue #631).

این ابزار یک برنامه‌ی خط‌فرمان (CLI) اجراشونده **یک‌بار** است که:
1. مقادیر واقعی (آدرس اوراکل‌ها، پارامترهای امنیتی، فهرست ولیدیتور اولیه و صندلی‌های مؤسسان، اعضا و هیأت‌مدیرهٔ بنیاد، فهرست طلبکاران) را از یک فایل پیکربندی می‌خواند.
2. بایت‌کد نهایی و storage اولیه‌ی هر ده قرارداد را (به دو روش متفاوت، بسته به پیچیدگی قرارداد — بخش ۴ را ببین) تولید می‌کند.
3. این‌ها را، همراه با تنظیمات شبکه و موجودی کیف‌پول‌های اولیه، در یک فایل `genesis.json` نهایی برای Besu می‌نویسد.
4. یک حالت «تأیید» دارد که genesis تولیدشده را مستقل دوباره چک می‌کند.

## ۲. کاربر هدف

تیم فنی مستقر‌کننده‌ی شبکه — یک ابزار توسعه‌دهنده، نه یک محصول کاربرمحور. انتظار می‌رود فقط چندبار در طول عمر پروژه (احتمالاً فقط یک‌بار برای راه‌اندازی نهایی، شاید چندبار برای تست‌نت‌های محلی) اجرا شود. ابزار را کمیتهٔ فنی بنیاد توسعه می‌دهد؛ اجرای نهایی و بازبینی خروجی طبق بخش ۹ است.

## ۳. ورودی‌های لازم — فایل پیکربندی (`genesis-config.json`)

✅ هر سه آدرس اوراکل زیر (`distributionOracle`, `verifier`, `identityOracle`) نهایی شده و مستقیماً هاردکد شده‌اند — هم در قراردادها، هم در مثال پیکربندی زیر. هر سه آدرس با استاندارد چک‌سام EIP-55 (حروف بزرگ/کوچک صحیح) نوشته شده‌اند. فروش از طریق صرافی‌های مجاز انجام می‌شود (`sur-suren-sale-spec.md`) و اوراکل پرداخت ندارد.

این فایل باید قبل از اجرای ابزار توسط تیم پروژه (نه توسط خودِ ابزار) تکمیل شود. فرمت دقیق:

```json
{
  "network": {
    "chainId": 262,
    "genesisTimestamp": 1735689600,
    "blockPeriodSeconds": 3,
    "blockRewardWei": "2000000000000000000",
    "minGasPriceWei": "100000000000000"
  },
  "oracles": {
    "distributionOracle": "0xbCBAc7d286eA11EC57fb4e0f5D16d960D6d202b6",
    "verifier": "0x1A5E86f3333291B3332C0f9Eddb04269940566bc",
    "identityOracle": "0xbE7e65512Eada6F4c6a9DEDDf2eFb75547A065e9"
  },
  "validatorsRegistry": {
    "firstValidator": { "owner": "0x....", "operator": "0x...." },   // فقط اولین ولیدیتور (راه‌انداز genesis) در مجموعهٔ اولیه `Active` است؛ owner = `firstOwner` و operator = `firstOperator` در `ValidatorsRegistry_GenesisSeed`؛ صندلی شمارهٔ ۱ همین مالک است
    "otherFounders": ["0x....", "0x....", "0x....", "0x....", "0x....", "0x...."],   // شش مؤسس دیگر (آدرس مالک)؛ `Probation`، بدون وثیقه و بدون کلید نود تا `setOperator` و `recordActivation`
    "seatBaseURI": "https://validator-nft.surnet.org/",              // فقط برای assert: مقدار اولیهٔ `baseURI` در سورس `ValidatorSeatNFT` است (کمکی آرگومانی برایش ندارد)؛ مالک داده؛ 🔶 مسئول نگه‌داری مشخص نیست. صندلی‌های ۱ تا ۷ به ترتیب [firstValidator.owner، ...otherFounders] ساخته می‌شود
    "entryCollateral": "500000000000000000000000",                  // ۵۰۰٬۰۰۰ سورن؛ وثیقهٔ ثابت ورود (حدود مطلق ۱۰۰٬۰۰۰ تا ۲٬۰۰۰٬۰۰۰ سورن)
    "membershipFeeBps": 400,                                        // ۴٪ وثیقه = ۲۰٬۰۰۰ سورن (بازهٔ ۱٪ تا ۱۰٪)
    "maxEntriesPerWindow": 1,
    "entryWindowSeconds": 604800,                                   // فاصلهٔ ورود: ۷ روز (بازه ۱ تا ۳۰ روز)
    "probationPeriod": 604800,
    "recoveryPeriod": 172800,
    "slashBps": 100,
    "exitCooldown": 604800
  },
  "validatorsBoard": {
    "initialBoardMembers": ["0x....", "0x....", "0x....", "0x....", "0x...."]   // ترکیب هیأت‌مدیرهٔ اولیهٔ ولیدیتورها از میان مؤسسان؛ ✅ تصمیم مالک ۲۰۲۶-۱۱-۱۹: عضو `Probation` کرسی دارد ولی تا فعال‌شدن توسط Verifier عمل نمی‌کند (`hasBoardAuthority` برایش `false` است؛ `syncBoard()` حذفش نمی‌کند)؛ پس در شروع فقط اولین ولیدیتور (فعال) عمل می‌کند و اقدام هیأت دست‌کم ۳ رأی می‌خواهد: دست‌کم ۲ مؤسس دیگر را زود فعال کنید
  },
  "validatorsTreasury": {
    "perPaymentCap": "50000000000000000000000",   // ✅ ۵۰٬۰۰۰ سورن (wei). مقدار 0 یعنی هیچ پرداختی ممکن نیست؛ ابزار باید با 0 عمداً متوقف شود مگر پرچم صریح --allow-zero-caps
    "periodCap": "200000000000000000000000"        // ✅ ۲۰۰٬۰۰۰ سورن (wei)؛ همان قاعده‌ی بالا
  },
  "foundationMembers": {
    "members": [                                    // ۱۵ عضو بنیاد؛ حساب اعضا در این قرارداد نگه‌داری می‌شود و FoundationDAO و ValidatorLottery از آن می‌خوانند
      { "name": "...", "account": "0x....", "shareWeight": "..." }   // shareWeight: سهم‌الشرکهٔ عضو طبق اساس‌نامه (وزن رأی در مجمع)
    ]
  },
  "foundationDAO": {
    "treasuryBalanceWei": "20000000000000000000000000",   // ۲۰ میلیون سورن، موجودی خودِ FoundationDAO
    "initialBoard": {
      "principal": ["0x....", "0x....", "0x....", "0x....", "0x...."],   // ۵ عضو اصلی هیأت‌مدیرهٔ اولیهٔ بنیاد
      "alternates": ["0x....", "0x...."]                                // ۲ علی‌البدل
    },
    "initialInspector": "0x...."                    // بازرس اولیه (می‌تواند خارج از بنیاد باشد)
    // 🔶 رئیس هیأت‌مدیره، خزانه‌دار و مدیرعامل را هیأت‌مدیره پس از راه‌اندازی انتخاب می‌کند؛ اینکه در genesis مقدار اولیه داشته باشند تصمیم باز است
  },
  "genesisClaimsVault": {
    "installments": 24,
    "gasReserveWei": "100000000000000000000",       // ۱۰۰ سورن برای هر طلبکار، مستقیم در کیف‌پول او و کسرشده از طلبش
    "claims": [                                      // به‌ازای هر آدرس دقیقاً یک طلب جمع‌شده (ردیف ۲ + ردیف ۳ برای آدرسی که در هر دو هست)
      { "to": "0x....", "totalClaimWei": "0" }
    ],
    "rowTotals": {                                   // فقط برای اعتبارسنجی ابزار
      "initialValidatorClaims": "11984000000000000000000000",   // ردیف ۲: ۱۱٬۹۸۴٬۰۰۰ سورن، ۷ نود
      "foundationMemberClaims": "21327000000000000000000000"    // ردیف ۳: ۲۱٬۳۲۷٬۰۰۰ سورن، ۱۵ عضو
    }
  }
}
```

⚠️ این ابزار خودش **هیچ تصمیم بیزینسی یا امنیتی نمی‌گیرد** — همه‌ی مقادیر بالا باید از قبل، توسط تیم پروژه، طبق `sur-master-open-items.md` نهایی شده باشند. اگر هر مقداری در این فایل با مقدار پیش‌فرض (صفر/آدرس صفر) باقی بماند، ابزار باید در همان ابتدا با خطا متوقف شود (بخش ۷ را ببین).

**قواعد محتوای پیکربندی:**
- **ولیدیتورهای اولیه:** ۷ مؤسس هرکدام یک صندلی (NFT) با آدرس اتریومی مشخص دارند (صندلی‌های ۱ تا ۷ به ترتیب: اولین ولیدیتور، سپس `otherFounders`)، ولی فقط **اولین ولیدیتور** (راه‌انداز genesis) در مجموعهٔ اولیه `Active` است. شش نفر دیگر در Registry با وضعیت `Probation` (و `isFounder = true`) ثبت‌اند و پس از genesis با آدرس اتریومی خودشان کلید نودشان (اپراتور) را با `setOperator` تعریف می‌کنند (در `Probation` هنوز در مجموعهٔ اجماع نیستند، پس همین فوری است؛ پس از `Active` شدن، تعویض کلید نود دومرحله‌ای است: `proposeOperator` و `confirmOperatorReady`؛ تصمیم ۱۱۰؛ ابزار genesis برای این تغییری لازم ندارد) و به شرط تأیید روشن‌بودن نود توسط Verifier (`recordActivation`، بدون انتظار دورهٔ آزمایشی) وارد فهرست ولیدیتورها می‌شوند؛ ورود آن‌ها از فاصلهٔ ورود مستثناست. ✅ تا فعال‌شدن، مؤسسِ `Probation` در هیأت اولیه کرسی دارد ولی عمل نمی‌کند (تصمیم ۲۰۲۶-۱۱-۱۹)؛ هیأت در بلاک ۱ کامل کار نمی‌کند و برای هر اقدام هیأت (دست‌کم ۳ رأی) دست‌کم ۳ عضو فعال‌شدهٔ هیأت لازم است؛ پس رویهٔ راه‌اندازی باید دست‌کم ۲ مؤسس دیگر را زود فعال کند. مؤسسان وثیقهٔ صفر دارند و احراز هویت لازم ندارند.
- **مالک و اپراتور:** هر ولیدیتور دو کلید دارد؛ مالک (وثیقه، پاداش، رأی، هویت، NFT) و اپراتور (فقط امضای بلاک). برای اولین ولیدیتور هر دو در پیکربندی داده می‌شوند و یک اپراتور برای چند مالک مجاز نیست.
- **طلب‌ها:** آدرس طلبکاران پیش از genesis مشخص و در `GenesisClaimsVault` ثبت می‌شود و تعویض آدرس مجاز نیست. هر طلبکار ۱۰۰ سورن از طلبش را از ابتدا در کیف‌پول خودش دارد (برای گس)؛ باقی‌مانده `(طلب − ۱۰۰)` در ۲۴ قسط مساوی در ابتدای هر ماه میلادی آزاد می‌شود (اولین قسط: ابتدای اولین ماه میلادی پس از genesis؛ در ماه genesis قسطی آزاد نیست؛ باقی‌ماندهٔ تقسیم بر ۲۴ در قسط آخر می‌آید ✅؛ قسط برداشت‌نشده منقضی نمی‌شود). طلب مؤسسان مشروط به ماندن ولیدیتور نیست و جریمه‌پذیر نیست.
- **بنیاد:** اولین هیأت‌مدیره، بازرس و اعضا در مقدار اولیهٔ قرارداد (genesis) قرار می‌گیرند. مقدار اولیه (طبق صورت‌جلسهٔ مجمع ۱۴۰۵/۰۷/۰۱): هیأت‌مدیرهٔ اصلی: سیده مهکامه شریف‌زاد، میرسهیل نیک‌زاد کلورزی، سیاوش تفضلی، محمدحسن محمدی اردهالی، علیرضا زجاجی قمی؛ علی‌البدل: حجت عباسی، کاوه مشتاق؛ بازرس: امیرعباس امامی کورعباسلو؛ وزن سهم‌الشرکهٔ هر یک از ۱۵ عضو برابر ۵۰ میلیون ریال. اساس‌نامه تغییر نمی‌کند و قواعد پیاده‌شده در قرارداد (انتخابات، نصاب‌ها، خرج بدون سقف) از `FoundationDAO` می‌آید، نه از پیکربندی.

## ۴. معماری اجرا — دو روش متفاوت، بسته به نوع قرارداد

### ۴.۱ روش ساده (بدون نیاز به شبیه‌سازی) — برای `BlockRewardDistributor`, `ValidatorsTreasury`, `IdentityRegistry`, `ValidatorLottery`

این قراردادها فقط مقادیر مقیاسی ساده (address/uint256) دارند که مستقیم در بدنه‌شان مقداردهی شده‌اند (نه mapping/آرایه)؛ `ValidatorLottery` وضعیت اولیهٔ خاصی ندارد (مجری را از `FoundationDAO` می‌خواند). برای این‌ها:

1. (در کد جاری مقدار اولیهٔ اوراکل‌ها از `SurAddresses.sol` می‌آید و `ValidatorLottery` وضعیت اولیه ندارد؛ جایگزینی سورس فقط وقتی لازم است که پیکربندی با مقدار داخل کد فرق کند.) یک نسخه‌ی موقت از سورس قرارداد بساز که در آن، هر مقدار `🔶 FILL_IN` با مقدار واقعی از فایل پیکربندی جایگزین شده باشد (مثلاً `address public identityOracle = address(0);` بشود `address public identityOracle = 0xABCD...;`).
2. این سورس را با `solc` کامپایل کن. ⚠️ برداشتن خام `evm.deployedBytecode.object` فقط وقتی درست است که قرارداد **هیچ متغیر `immutable` نداشته باشد**؛ در خروجی solc محل immutableها خالی/صفر است و creation code آن‌ها را هنگام دیپلوی پر می‌کند. `BlockRewardDistributor` immutable ندارد؛ ابزار باید خالی‌بودن `immutableReferences` آن را assert کند. تنها immutable پروژه `SurenSale.saleStartTime` است (که genesis نیست)؛ اگر قرارداد genesis دارای immutable شود، دو راه زیر الزامی است. مشخصات کامل: `technical-design/sur-audit-2026-09-30-stage1-report.md` بخش ۶. دو راه مجاز: **(الف، ترجیحی)** creation code را روی یک زنجیره‌ی موقت که timestamp بلاکش برابر `network.genesisTimestamp` تنظیم شده واقعاً اجرا کن و `code` را با `eth_getCode` بخوان (immutable درست جایگزین شده)؛ یا **(ب)** محل‌های immutable را از `immutableReferences` خروجی solc بخوان، با `genesisTimestamp` patch کن، و آزمون کن.
3. با `solc --storage-layout` (یا فیلد `storageLayout` در خروجی JSON استاندارد) شماره‌ی دقیق slot هر متغیر ساده را بگیر.
4. مقدار واقعی هرکدام را مستقیم در همان slot در بخش `alloc.storage` genesis بنویس.

⚠️ نکته‌ی فنی حیاتی: بایت‌کد deploy‌شده (runtime) هرگز شامل منطق «مقداردهی اولیه» نیست — آن منطق فقط بخشی از creation bytecode است. برای همین **هر** scalar غیرconstant با مقدار غیرپیش‌فرض (آدرس اوراکل‌ها، سقف‌ها، پارامترهای زمانی و…) باید با overlay صریح slot نوشته شود — نوشتن نشدنش یعنی مقدار صفر. حذف constructor صریح از سورس به‌معنای بی‌نیازی از این مرحله نیست. و طبق تصحیح بالا، immutableها را جداگانه مدیریت کن.

### ۴.۲ روش شبیه‌سازی-و-استخراج (simulate-and-extract؛ نیازمند زنجیره‌ی محلی موقت) — برای `FoundationDAO`, `FoundationMembers`, `ValidatorsRegistry`, `ValidatorsBoard`, `ValidatorSeatNFT`, `GenesisClaimsVault`

این قراردادها `mapping` یا آرایه‌ی پویا دارند (فهرست اعضا، ولیدیتورها، صندلی‌ها و توکن‌ها، طلبکاران و زمان‌بندی طلب‌ها) که هیچ syntax سطح-قرارداد Solidity برای پرکردنشان خارج از یک تابع وجود ندارد. برای این‌ها از قراردادهای کمکی `contracts/genesis-seed-helpers/` استفاده کن:

- `FoundationDAO_GenesisSeed.sol` ✅ نوشته‌شده — `constructor(address[] principalsAndAlternates, address inspector_, address chair_, address treasurer_, address ceo_, uint256 termEnd)`؛ ۵ تا ۷ آدرس (۵ اصلی، سپس حداکثر ۲ علی‌البدل)؛ نسخهٔ هیأت seed‌شده ۰ است.
- `FoundationMembers_GenesisSeed.sol` ✅ نوشته‌شده — `constructor(address[] accounts, string[] names, PersonType[] types, address[] representatives, uint256[] shares)` (پنج آرایهٔ هم‌طول).
- `ValidatorsRegistry_GenesisSeed.sol` ✅ نوشته‌شده — `constructor(address firstOwner, address firstOperator, address[] otherFounders, uint256 genesisTimestamp)`؛ `genesisTime` را می‌نویسد؛ **ولیدیتور اول** را `Active` با اپراتور `firstOperator` می‌گذارد (`everActivated`، `activationSeq = 1`، checkpoint `{0, true}`، در `getValidators()` و `getActiveOwners()`)؛ **مؤسسان دیگر** را با آدرس مالک، وضعیت `Probation`، `isFounder = true`، وثیقهٔ صفر و بدون اپراتور ثبت می‌کند (نه `Active`؛ `everActivated` و `activationSeq` تا `recordActivation` صفرند). `windowStart` را نمی‌نویسد.
- `ValidatorsBoard_GenesisSeed.sol` ✅ نوشته‌شده — `constructor(address[] members, uint256 genesisTimestamp)`؛ دقیقاً ۵ عضو؛ `boardMonthId` را برابر ماهِ `genesisTimestamp` و `boardVersion` را ۱ می‌گذارد.
- `GenesisClaimsVault_GenesisSeed.sol` ✅ نوشته‌شده — `constructor(address[] claimants, uint256[] claims, uint256 genesisTimestamp)`؛ هر `claims[i]` طلب **کامل** آدرس است و شامل همان ۱۰۰ سورنی است که مستقیم به کیف‌پول می‌رود (صندوق `claim − ۱۰۰` را نگه می‌دارد)؛ هر طلب باید بیش از ۱۰۰ سورن باشد، آدرس صفر یا تکراری ممنوع است؛ `genesisTimestamp` باید برابر `timestamp` فایل `genesis.json` باشد. **قاعدهٔ موجودی:** موجودی `alloc` آدرس صندوق باید دقیقاً برابر `totalHeld()` (مجموع `claim − ۱۰۰`) باشد.
- `ValidatorSeatNFT_GenesisSeed.sol` ✅ نوشته‌شده — `constructor(address[] founderOwners)`؛ صندلی‌های ۱ تا n را به مالکان داده‌شده می‌دهد؛ **ترتیب آرایه باید همان ترتیب مؤسسان در Registry باشد** (`[firstOwner, ...otherFounders]`). `baseURI` اولیه (`https://validator-nft.surnet.org/`) initializer خود قرارداد است و در dump می‌آید.

✅ هر شش کمکیِ نوشته‌شده، قرارداد اصلی را **ارث می‌برند** (`contract X_GenesisSeed is X`) و فقط در constructor‌شان وضعیت اولیه را seed می‌کنند؛ پس ساختار storage با قرارداد اصلی **به‌ساخت یکی است**. قاعدهٔ قدیمی «کپی کمکی با placeholder/`__gap` که باید دستی با اصلی هم‌ترازش کرد» و اسکریپت `check_genesis_helper_layout.js` برای این شش دیگر کاربرد ندارد. به‌علاوه چون initializerهای متغیرهای state قرارداد اصلی (مثلاً `verifier = SurAddresses.VERIFIER`، `slashBps = 100`) در constructor کمکی هم اجرا می‌شوند، در خروجی dump خودبه‌خود می‌آیند.

✅ **وابستگی بین‌قراردادی هنگام seed:** constructor کمکی‌های نوشته‌شده هیچ قراردادی را فراخوانی نمی‌کنند (فقط state خودشان را می‌نویسند)، پس کافی است هرکدام روی زنجیره‌ی موقت جداگانه deploy شود و ترتیب یا آدرس نهایی اهمیتی ندارد (آدرس‌های ثابت `SurAddresses` در بایت‌کد‌اند و در storage ذخیره نمی‌شوند). ✅ `ValidatorsRegistry_GenesisSeed` صندلی نمی‌سازد و `ValidatorSeatNFT` را فراخوانی نمی‌کند: صندلی مؤسسان را `ValidatorSeatNFT_GenesisSeed` جدا و روی زنجیرهٔ موقتِ خودش می‌سازد؛ پس وابستگی بین‌قراردادی هنگام seed برنمی‌گردد و تنها قید، یکی‌بودن ترتیب مؤسسان در دو helper است (شناسهٔ توکن ۱ = ولیدیتور اول).

⚠️ **محدودیت اندازهٔ کد (🔶 ثبت‌شده):** بایت‌کد runtime قرارداد `FoundationDAO` حدود ۲۷٫۹ کیلوبایت و `ValidatorsRegistry` حدود ۳۶٬۸۷۹ بایت (اندازهٔ فعلی کامپایل‌شده؛ artifact آزمون Hardhat با solc 0.8.24، optimizer 200؛ ۳۴٬۶۰۵ بایت در دور اول Besu اندازه‌گیری شد، BR-SIZE) است، یعنی بالاتر از سقف ۲۴٬۵۷۶ بایتی که فقط برای `CREATE` اعمال می‌شود. روی زنجیره‌ی واقعی مشکلی نیست، چون این قراردادها مستقیم در `alloc` genesis تزریق می‌شوند (CREATE در کار نیست). ولی دیپلوی کمکی‌هایشان روی زنجیره‌ی موقت (Anvil) با CREATE است و باید سقف اندازه برداشته شود (در Anvil پرچم `--disable-code-size-limit` یا `--code-size-limit`؛ 🔶 نام دقیق پرچم با نسخهٔ نصب‌شده تأیید شود)؛ آزمون‌های Hardhat هم همین کار را فقط برای شبکهٔ درون‌فرایندی می‌کنند (`allowUnlimitedContractSize`). ✅ روی Besu واقعی تأیید شد (دور اول ۲۰۲۶-۱۱-۱۹، BR-SIZE؛ مشتق از BG-01/02/09): `FoundationDAO` (۲۸٬۳۶۵ بایت) و `ValidatorsRegistry` (۳۴٬۶۰۵ بایت در آن دور؛ اندازهٔ فعلی حدود ۳۶٬۸۷۹ بایت است و در دور بعد دوباره تأیید شود)، هر دو بالاتر از ۲۴٬۵۷۶، در `alloc` تزریق شدند و برای `eth_getCode`، فراخوانی و تراکنش‌های تغییر وضعیت کار کردند.

**الگوریتم دقیق (کمکی‌ها آرگومان constructor می‌گیرند؛ جایگزینی سورس لازم نیست):**

1. از فایل `genesis-config.json` (بخش ۳ بالا)، مقادیر `foundationMembers.members`، `foundationDAO.initialBoard`/`initialInspector`، `validatorsRegistry.firstValidator`، `validatorsRegistry.otherFounders` و `validatorsBoard.initialBoardMembers` (و `genesisClaimsVault.claims`) را بخوان.
2. قراردادهای اصلی و کمکی‌ها را با همان نسخهٔ `solc` و همان تنظیمات بهینه‌سازی که برای بایت‌کد نهایی استفاده می‌شود (فعلاً `0.8.24`، `evmVersion: paris`) کامپایل کن. ⚠️ این‌ها یک مرحلهٔ «جایگزینی سورس» ندارند: مقدار اولیه با آرگومان constructor داده می‌شود.
3. روی یک نمونه‌ی Anvil محلی (`anvil --silent`، با سقف اندازهٔ کد برداشته‌شده طبق بالا) هر کمکی را با آرگومان‌های بند ۱ (ABI-encode‌شده) deploy کن. `ValidatorsBoard_GenesisSeed` و `ValidatorsRegistry_GenesisSeed` باید `genesisTimestamp` را برابر `network.genesisTimestamp` بگیرند. `ValidatorsRegistry_GenesisSeed` با `(firstValidator.owner, firstValidator.operator, otherFounders, genesisTimestamp)` و `ValidatorSeatNFT_GenesisSeed` با `[firstValidator.owner, ...otherFounders]` (همان ترتیب) deploy می‌شود.
4. آدرس‌های روی Anvil را نگه دار.
5. با `anvil_dumpState` (متد RPC اختصاصی Anvil) کل state زنجیره را بگیر — این شامل کد و **تمام** storage slotهای هر قرارداد می‌شود، دقیقاً محاسبه‌شده توسط خودِ EVM (شامل هر `keccak256` لازم برای mapping/آرایه و شامل مقدارهای initializer، بدون محاسبهٔ دستی).
6. از خروجی `anvil_dumpState`، **همهٔ** `storage` مربوط به آدرس هر کمکی را استخراج کن.
7. ⚠️ برای `code` هر قرارداد در genesis نهایی، **از بایت‌کد deploy‌شده‌ی قرارداد اصلی** (مثلاً `FoundationDAO.sol`، نه `FoundationDAO_GenesisSeed.sol`) استفاده کن — کمکی فقط برای محاسبه‌ی storage است و نباید روی زنجیره‌ی واقعی برود. بایت‌کد قرارداد اصلی را طبق روش ۴.۱ (کامپایل استاتیک) به دست بیاور؛ ابزار باید خالی‌بودن `immutableReferences` هر یک را assert کند (در کد فعلی هیچ‌کدام immutable ندارند).
8. Anvil را متوقف و state موقتش را کاملاً دور بینداز. (دیگر نسخهٔ «جایگزینی‌شده»ای از سورس وجود ندارد که نگه‌داری/دورانداختنش لازم باشد.)


### ✅ ۴.۲.۱ مرحله‌ی Overlay اسکالرهای `ValidatorsRegistry`

چون `ValidatorsRegistry_GenesisSeed` قرارداد اصلی را ارث می‌برد، initializerهای اسکالرهای اصلی (مثلاً `verifier`، `membershipFeeBps`، `slashBps`، `exitCooldown`) هنگام اجرای constructor کمکی نوشته می‌شوند و در dump هستند. بنابراین overlay فقط برای مقدارهایی لازم است که در `genesis-config.json` با **مقدار اولیهٔ داخل کد** فرق دارند (اکنون همهٔ مقدارهای زیر در کد هستند و مقدار اولیه‌شان همان مقدار طرح است). این مرحله (بعد از بند ۶، قبل از نوشتن نهایی storage در genesis) اجرا می‌شود:

1. **الگوریتم سه‌مرحله‌ای برای storage نهایی `ValidatorsRegistry`:**
   - **(الف)** بایت‌کد deploy‌شده‌ی قرارداد اصلی — طبق روش ۴.۱.
   - **(ب)** storage کامل (mapping/آرایه و initializerها) از خروجی `anvil_dumpState` روی `ValidatorsRegistry_GenesisSeed` — طبق مراحل ۱ تا ۶ بالا.
   - **(پ)** ✅ **overlay اسکالرهای متفاوت:** با `solc --storage-layout` روی خودِ `ValidatorsRegistry.sol` (نه فایل کمکی)، شماره‌ی دقیق slot هر متغیری را که مقدارش در `genesis-config.json` با مقدار اولیهٔ کد فرق دارد پیدا کن و مقدار پیکربندی را مستقیم در همان slot بنویس — به‌عنوان یک لایه‌ی *اضافه* روی storage مرحله‌ی (ب). ✅ **فهرست مقادیر مرجع طرح ۲٫۵ (کد جاری `ValidatorsRegistry` بازطراحی را دارد):** `entryCollateral` اولیه `500_000 ether`، `membershipFeeBps` اولیه ۴۰۰ و `entryWindowSeconds` اولیه ۷ روز است (منحنی رشد قدیمی حذف شده)؛ پس این مقدارها بدون overlay از constructor کمکی می‌آیند و overlay فقط اگر پیکربندی فرق کند لازم است.
     - `verifier` (از `genesis-config.json`، آدرس کلید عملیاتی وریفای)
     - `entryCollateral` (۵۰۰٬۰۰۰ سورن؛ وثیقهٔ ثابت برای همهٔ ورودی‌های پرداخت‌کننده)
     - `membershipFeeBps` (۴۰۰)
     - `maxEntriesPerWindow` (۱)
     - `entryWindowSeconds` (۶۰۴۸۰۰ — ۷ روز)
     - `probationPeriod` (۶۰۴۸۰۰ — ۱ هفته)
     - `recoveryPeriod` (۱۷۲۸۰۰ — ۴۸ ساعت)
     - `slashBps` (۱۰۰ — ۱٪)
     - `exitCooldown` (۶۰۴۸۰۰ — ۱ هفته)
     - ✅ `genesisTime` (مبدأ ممنوعیت تغییر `entryWindowSeconds` در ۶ ماه اول): کمکی از آرگومان `genesisTimestamp` می‌نویسد؛ باید دقیقاً برابر `network.genesisTimestamp` باشد. `windowStart` ۰ می‌ماند (اولین `requestMembership` پنجره را شروع می‌کند).
     - مقادیر مرجع این فهرست: `sur-tokenomics.md` بخش ۶.
2. ✅ **Post-build assertions — این‌ها از خودِ روش ساخت مهم‌ترند:** بعد از تولید genesis نهایی، ابزار باید (روی یک Anvil موقت دیگر، با genesis تولیدشده بالا آمده) این چک‌ها را خودکار اجرا و **در صورت شکست، کل فرآیند build را متوقف کند** (✅ نام getterها همان نام کد است؛ آزمون Besu در دور اول ۲۰۲۶-۱۱-۱۹ با یک ابزار ساخت آزمایشی انجام شد، نه با ابزار production):
   ```
   # ValidatorsRegistry
   ValidatorsRegistry.getActiveValidatorCount() == 1            # فقط اولین ولیدیتور
   ValidatorsRegistry.verifier() == (آدرس verifier در config)
   ValidatorsRegistry.entryCollateral() == 500000 ether
   ValidatorsRegistry.membershipFeeBps() == 400
   ValidatorsRegistry.maxEntriesPerWindow() == 1
   ValidatorsRegistry.entryWindowSeconds() == 604800
   ValidatorsRegistry.probationPeriod() == (مقدار config)
   ValidatorsRegistry.recoveryPeriod() == (مقدار config)
   ValidatorsRegistry.slashBps() == (مقدار config)
   ValidatorsRegistry.exitCooldown() == (مقدار config)
   ValidatorsRegistry.isValidator(firstValidator.owner) == true      # مالک، نه اپراتور
   ValidatorsRegistry.operatorOf(firstValidator.owner) == firstValidator.operator
   getValidators() == [firstValidator.operator]                       # فهرست اجماع آدرس اپراتور است
   ValidatorsRegistry.everActivated(firstValidator.owner) == true     # بدون این پرچم اولین distributeRewards() برای پرداخت به او revert می‌کند
   ValidatorsRegistry.wasActiveAt(firstValidator.owner, 0) == true    # checkpoint مؤسس؛ بدون آن در رأی‌های مجمع واجد نیست
   validators(firstValidator.owner).isPaidEntrant == false            # مؤسس وثیقهٔ صفر دارد
   ValidatorsRegistry.getActiveOwners() == [firstValidator.owner]
   ValidatorsRegistry.ownerOfOperator(firstValidator.operator) == firstValidator.owner
   ValidatorsRegistry.isFounder(firstValidator.owner) == true
   برای هر یک از شش مؤسس دیگر: validators(owner).status == 1 (Probation) و isFounder(owner) == true و operatorOf(owner) == address(0) و isValidator(owner) == false و everActivated(owner) == false   # تا setOperator و recordActivation وارد مجموعه نمی‌شوند
   ValidatorsRegistry.statusNonce() == 0
   ValidatorsRegistry.wasActiveAt(<هر آدرس غیرمؤسس>, 0) == false
   ValidatorsRegistry.genesisTime() == network.genesisTimestamp

   # ValidatorSeatNFT
   ValidatorSeatNFT.totalMinted() == 7
   برای هر صندلی i (۱ تا ۷): ownerOf(i) == [firstValidator.owner، ...otherFounders][i−1] و seatOf(ownerOf(i)) == i   # همان ترتیب Registry
   ValidatorSeatNFT.baseURI() == seatBaseURI و tokenURI(i) == baseURI + i

   # ValidatorsBoard
   ValidatorsBoard.boardVersion() == 1
   ValidatorsBoard.boardMonthId() == monthIdOf(network.genesisTimestamp)   # بدون آن، هیأت مؤسس تا نخستین refreshBoard بی‌اختیار است
   ValidatorsBoard.getBoardMembers() == initialBoardMembers            # ✅ کرسی دارند؛ عمل فقط برای ولیدیتور غیر-Probation (تصمیم ۲۰۲۶-۱۱-۱۹)
    برای هر آدرس a در initialBoardMembers: hasBoardAuthority(a) == (a == firstValidator.owner)   # مؤسس Probation کرسی دارد ولی عمل نمی‌کند تا recordActivation

   # ValidatorsTreasury
   ValidatorsTreasury.perPaymentCap() == 50000 ether ; periodCap() == 200000 ether   # overlay اجباری — مقداردهی‌ها هنگام تزریق اجرا نمی‌شوند
   (اگر مقدار config برابر 0 است ابزار باید صریحاً اعلام کند «پرداخت هیأت ممکن نیست»)

   # BlockRewardDistributor
   BlockRewardDistributor: immutableReferences == {}                   # هیچ immutable ندارد
   BlockRewardDistributor.validatorDirectShareBps() == (مقدار config، پیش‌فرض 5000)   # overlay
   BlockRewardDistributor.lastSettledBlock() == 0                      # اولین بازه از بلاک ۱ شروع می‌شود
   BlockRewardDistributor.INITIAL_REWARD_PER_BLOCK() == 2000000000000000000   # ثابت کد، wei
   BlockRewardDistributor.rewardRateChangeCount() == 0                 # تاریخچهٔ نرخ مصوب خالی است؛ نرخ اولیه (۲ SUR) ثابت در کد است
   BlockRewardDistributor.rateProposalCount() == 0                     # بدون پیشنهاد نرخ
   BlockRewardDistributor.maxRewardsForRange(1, 1000) == 2000000000000000000000   # مقدار مصوب ۲٬۰۰۰ سورن برای ۱۰۰۰ بلاک
   BlockRewardDistributor.totalExcessBurned() == 0 و RewardExcessBurned: هیچ رویدادی در genesis وجود ندارد
   (ممنوعیت ۶ ماه اول تغییر نرخ هنوز در کد نیست؛ 🔶 اگر پیاده شود مبدأ زمان باید با genesis assert شود)

   # FoundationMembers / FoundationDAO
   FoundationMembers.getMemberCount() == 15 و حساب و shareWeight هر عضو مطابق config
   FoundationDAO.getBoard() == initialBoard (۵ اصلی + ۲ علی‌البدل) و getInspector() == initialInspector
   FoundationDAO.boardVersion() == 0 و saleContract() == address(0)   # SurenSale بعد از genesis با پیشنهاد SetSaleContract معرفی می‌شود
   FoundationDAO.getEthBalance() == 20000000 ether
   FoundationDAO از FoundationMembers می‌خواند: مرجع آدرس ثابت و برابر آدرس genesis

   # GenesisClaimsVault
   GenesisClaimsVault.INSTALLMENTS() == 24
   GenesisClaimsVault.genesisTimestamp() == network.genesisTimestamp
   address(GenesisClaimsVault).balance == GenesisClaimsVault.totalHeld() == (جمع همهٔ totalClaimWei) − (۱۰۰ سورن × تعداد طلبکاران)
   برای هر طلبکار: claimInfo(to) == (totalClaimWei − ۱۰۰ سورن, ۱۰۰ سورن, 0, 0) یعنی held ، walletPart ، released ، withdrawn   # در لحظهٔ genesis چیزی آزاد نیست
   برای هر طلبکار: releasedOf(to) == 0 ؛ withdrawableOf(to) == 0 ؛ installmentAmount(to) == (totalClaimWei − ۱۰۰ سورن) / ۲۴
   balanceOf(to) در alloc == ۱۰۰ سورن (+ هر موجودی دیگر همان آدرس)

   # IdentityRegistry
   IdentityRegistry.identityOracle() == (مقدار config) ؛ کنترل کلید در دست FoundationDAO
   ```
   این چک‌ها دقیقاً همان کلاس خطایی را می‌گیرند که یک storage layout به‌هم‌ریخته (مثلاً اگر آفست بین فایل کمکی و قرارداد اصلی جابه‌جا شده باشد) یا یک اسکالر جامانده در overlay تولید می‌کند — بدون این‌ها، چنین خطایی فقط زمانی کشف می‌شود که شبکه‌ی واقعی با یک genesis state خراب یا ناقص بالا بیاید.

### ۴.۳ تخصیص موجودی‌ها در `alloc` (سورن، ارز بومی)

جدا از storage قراردادها (بخش ۴.۲)، موجودی‌های زیر باید مستقیم در `alloc` (نه storage) نوشته شوند — این‌ها موجودی سورن (ارز بومی) هر آدرس‌اند:
- آدرس `0x1111...1111` (خودِ `FoundationDAO`): `foundationDAO.treasuryBalanceWei` (۲۰٬۰۰۰٬۰۰۰ سورن).
- آدرس `GenesisClaimsVault`: جمع همهٔ `totalClaimWei` منهای (`gasReserveWei` × تعداد طلبکاران) — دقیقاً برابر `totalHeld()` که از seed می‌آید (ابزار باید این برابری را assert کند). طلب‌های ردیف ۲ (۱۱٬۹۸۴٬۰۰۰) و ردیف ۳ (۲۱٬۳۲۷٬۰۰۰) به کیف‌پول طلبکاران نمی‌رود و در این قرارداد قفل می‌شود.
- هر طلبکار: دقیقاً `gasReserveWei` (۱۰۰ سورن) در کیف‌پول خودش (برای گس)، که از طلبش کسر شده است. برای آدرسی که هم در ردیف ۲ و هم ۳ است، یک طلب جمع‌شده و یک ذخیرهٔ ۱۰۰ سورنی در نظر گرفته می‌شود.
- جدول مبلغ هر نود (ردیف ۲): `sur-tokenomics.md` بخش ۲.۲؛ جدول مبلغ هر عضو (ردیف ۳): بخش ۲.۱ همان سند.
- **عرضهٔ کل genesis دقیقاً ۵۳٬۳۱۱٬۰۰۰ سورن** است: `FoundationDAO` (۲۰٬۰۰۰٬۰۰۰) + `GenesisClaimsVault` + ذخیره‌های ۱۰۰ سورنی = ۲۰٬۰۰۰٬۰۰۰ + ۳۳٬۳۱۱٬۰۰۰. ابزار باید در مرحله‌ی تأیید این جمع را بسنجد. عرضهٔ در گردش اولیه کمتر از آن است (طلب‌های قفل‌شده) و در طول ۲۴ ماه به‌تدریج بیشتر می‌شود.

اگر یک آدرس هم به‌عنوان ولیدیتور/عضو هیأت/عضو بنیاد و هم به‌عنوان طلبکار ظاهر شود، موجودی‌اش باید جمع منابع باشد (نه جایگزین یکدیگر)؛ ولی طلب او همچنان فقط در `GenesisClaimsVault` است، نه کیف‌پول.

## ۵. ابزارها و پشته‌ی فنی

| ابزار | نسخه/جزئیات |
|---|---|
| Node.js | ≥ ۲۰ |
| زبان | TypeScript |
| کامپایلر Solidity | `solc` نسخه‌ی ۰.۸.۲۴ — دقیقاً همان که تمام قراردادها با آن نوشته و تست شده‌اند |
| کتابخانه‌ی تعامل با زنجیره | `viem` (هماهنگ با پشته‌ی فنی مشترک پروژه — به `sur-reward-router-spec.md`/`sur-verifier-service-spec.md` مراجعه کن) |
| زنجیره‌ی محلی موقت | Anvil (بخشی از Foundry) |
| ⚠️ اکیداً **بدون** `viaIR` | کامپایل باید همیشه بدون `viaIR` انجام شود — طبق تصمیم مستند در `sur-contracts-deploy-notes.md`، برای حفظ سازگاری با وریفای Blockscout. اگر کامپایل بدون `viaIR` خطا داد، این یک باگ در قرارداد است که باید با تفکیک تابع رفع شود (دقیقاً مثل `BlockRewardDistributor.distributeRewards`)، نه با فعال‌کردن `viaIR`. |

## ۶. خروجی — ساختار دقیق `genesis.json`

فایل خروجی باید شامل فیلدهای زیر باشد (فرمت استاندارد genesis Besu با پسوند QBFT):

```json
{
  "config": {
    "chainId": 262,
    "qbft": {
      "blockperiodseconds": 3,
      "epochlength": 30000,
      "requesttimeoutseconds": 10,
      "validatorcontractaddress": "0x3333333333333333333333333333333333333333"
    }
  },
  "nonce": "0x0",
  "timestamp": "<هگزادسیمال genesisTimestamp>",
  "gasLimit": "0x1fffffffffffff",
  "difficulty": "0x1",
  "miningbeneficiary": "0x2222222222222222222222222222222222222222",
  "blockreward": "2000000000000000000",
  "alloc": {
    "0x1111111111111111111111111111111111111111": { "balance": "...", "code": "0x...", "storage": { "0x...": "0x..." } },
    "0x2222222222222222222222222222222222222222": { "code": "0x...", "storage": { "...": "..." } },
    "0x3333333333333333333333333333333333333333": { "code": "0x...", "storage": { "...": "..." } },
    "0x4444444444444444444444444444444444444444": { "code": "0x...", "storage": { "...": "..." } },
    "0x5555555555555555555555555555555555555555": { "code": "0x...", "storage": { "...": "..." } },
    "0x6666666666666666666666666666666666666666": { "code": "0x...", "storage": { "...": "..." } },
    "0x8888888888888888888888888888888888888888": { "code": "0x...", "storage": { "...": "..." } },
    "0x9999999999999999999999999999999999999999": { "balance": "...", "code": "0x...", "storage": { "...": "..." } },
    "0x7777777777777777777777777777777777777777": { "code": "0x...", "storage": { "...": "..." } },
    "0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa": { "code": "0x..." },
    "<هر طلبکار>": { "balance": "100000000000000000000" }
  }
}
```

🔶 آدرس چهار قرارداد تازه در `SurAddresses.sol` پیشنهاد شده است (هنوز نهایی نشده): `FoundationMembers` = `0x7777…7777`، `ValidatorSeatNFT` = `0x8888…8888` (قرارداد نوشته و آزموده شده)، `GenesisClaimsVault` = `0x9999…9999` (قرارداد نوشته و آزموده شده)، `ValidatorLottery` = `0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa` (با چک‌سام EIP-55). `PAYMENT_ORACLE` از `SurAddresses` حذف شده است: فقط سه اوراکل (`verifier`، `distributionOracle`، `identityOracle`) مانده‌اند. `validatorcontractaddress` همان `ValidatorsRegistry` است و در لحظهٔ genesis فقط آدرس اپراتور اولین ولیدیتور را برمی‌گرداند.

`min-gas-price` جزو `genesis.json` نیست — این تنظیمات سطح Besu است (`config.toml` هر نود یا آرگومان خط‌فرمان `--min-gas-price`)، باید جدا از این فایل، در پیکربندی هر نود اعمال شود. 🔶 ابزار عملیاتی تنظیم قیمت گس برای اپراتور نود فعلاً اجرا نمی‌شود (ظرفیت آینده؛ `sur-master-open-items.md`)؛ ساختار genesis نباید مانع آن شود.

## ۷. مدیریت خطا — اعتبارسنجی قبل از تولید

ابزار باید قبل از هر گونه کامپایل/دیپلوی، فایل پیکربندی را چک کند و در صورت هرکدام از موارد زیر با پیام خطای واضح متوقف شود (نه یک genesis ناقص تولید کند):

- هر آدرسی برابر `0x000...000` (یعنی هنوز FILL_IN نشده).
- `firstValidator` تعریف نشده، یا مالک و اپراتور یکی باشند، یا اپراتور با مالک یا اپراتور دیگری تکراری باشد (یک اپراتور برای چند مالک مجاز نیست)؛ مالک اولین ولیدیتور همان صندلی ۱ است (در ساخت، `firstValidator.owner` اول آرایهٔ `founderOwners` می‌آید).
- `otherFounders` دقیقاً ۶ ورودی نداشته باشد، یا آدرس تکراری داشته باشد (با `firstValidator.owner` و `firstValidator.operator` هم)، یا آدرس صفر باشد.
- `initialBoardMembers` دقیقاً ۵ عضو نداشته باشد.
- `foundationMembers.members` کمتر از ۱ عضو داشته باشد (مقدار مورد انتظار ۱۵)، یا `shareWeight` ناقص/صفر باشد.
- `foundationDAO.initialBoard` دقیقاً ۵ اصلی و ۲ علی‌البدل نداشته باشد، یا شامل آدرس تکراری باشد، یا عضوی از آن در `foundationMembers` نباشد (هیأت‌مدیره باید از اعضای بنیاد یا نمایندهٔ عضو حقوقی باشد). بازرس می‌تواند خارج از بنیاد باشد.
- هر آدرس تکراری در `initialBoardMembers` یا `foundationMembers`.
- `genesisClaimsVault`: آدرس تکراری در `claims`؛ طلبی که از `gasReserveWei` (۱۰۰ سورن) بیشتر نباشد؛ جمع طلب‌های ردیف ۲ برابر ۱۱٬۹۸۴٬۰۰۰ یا جمع ردیف ۳ برابر ۲۱٬۳۲۷٬۰۰۰ سورن نباشد؛ `installments` برابر ۲۴ نباشد؛ طلب مؤسسان ولیدیتور مشروط یا جریمه‌پذیر تعریف شده باشد.
- `entryCollateral` خارج از بازهٔ ۱۰۰٬۰۰۰ تا ۲٬۰۰۰٬۰۰۰ سورن، `membershipFeeBps` خارج از ۱۰۰ تا ۱۰۰۰، یا `entryWindowSeconds` خارج از ۱ تا ۳۰ روز.
- `slashBps` بزرگ‌تر از ۱۰۰۰۰.
- `genesisTimestamp` در گذشته یا بیش از حد در آینده (پیشنهاد: باید بین «الان» و «الان + ۷۲ ساعت» باشد).
- جمع موجودی‌های تخصیص‌یافته (بخش ۴.۳) برابر ۵۳٬۳۱۱٬۰۰۰ سورن نباشد.

## ۸. حالت تأیید (Verify Mode)

بعد از تولید `genesis.json`، ابزار باید یک فلگ `--verify` داشته باشد که:
1. یک نمونه‌ی Besu محلی را با همین `genesis.json` واقعاً بالا بیاورد (نه شبیه‌سازی مجدد — از خودِ فایل خروجی نهایی).
2. با `eth_call`، مقادیر کلیدی هر قرارداد را بخواند (مثلاً `ValidatorsRegistry.getValidators()`, `FoundationMembers.getMemberCount()`, `FoundationDAO.getBoard()`, `ValidatorsBoard.getBoardMembers()`, `GenesisClaimsVault.totalHeld()`, `ValidatorSeatNFT.ownerOf(...)`, `BlockRewardDistributor.distributionOracle()`) و با مقادیر فایل پیکربندی مقایسه کند.
3. تأیید کند بلاک اول واقعاً تولید می‌شود (یعنی `getValidators()` از بلاک صفر غیرخالی است و فقط آدرس اپراتور اولین ولیدیتور را برمی‌گرداند — این دقیقاً همان ریسکی است که این حالت باید رد کند).
4. اگر هرکدام مطابقت نداشت، با کد خروج غیرصفر و پیام دقیق (کدام مقدار، کدام قرارداد) متوقف شود.

✅ آزموده شد (دور اول آزمون Besu، ۲۰۲۶-۱۱-۱۹؛ BG-01، BG-02، BG-12؛ با ابزار ساخت آزمایشیِ همان دور، نه ابزار production T02): genesis یک‌ولیدیتوری با قراردادهای ساختاری تزریق‌شده از بلاک ۱ بلاک تولید کرد، `getValidators()` کلید **اپراتور** را برگرداند و برابر مجموعهٔ QBFT بود، و شش ولیدیتور بعدی با `setOperator` و `recordActivation` اضافه شدند (حتی چند ولیدیتور در یک بلاک)؛ مجموعهٔ قرارداد و QBFT از بلاک فعال‌سازی یکی بود. نکته‌های لازم برای ابزار production: (۱) سه آدرس اوراکل `SurAddresses` در genesis آزمایشی با آدرس کلید آزمایشی جایگزین شد (storage، نه bytecode؛ D-2) — ابزار production باید آدرس‌های واقعی اوراکل را بگذارد؛ (۲) 🔶 F-2: در حالت `contract` فهرست ولیدیتور در `extraData` سرایند بلاک خالی است، پس `--verify` و هر ابزار خواندن نباید فهرست را از سرایند بخواند؛ از `qbft_getValidatorsByBlockNumber` یا قرارداد استفاده شود. 🔶 اجرانشده: genesis حالت Shanghai/Cancun برای ۲٫۵ (آزمون London بود) و خودِ ابزار production T02.

## ۹. امنیت

- فایل پیکربندی حاوی آدرس‌های واقعی است، نه کلید خصوصی — هیچ کلید خصوصی واقعی نباید وارد این ابزار شود (کلید امضای Anvil برای دیپلوی روی زنجیره‌ی موقت، کلید تستی پیش‌فرض و عمومی Anvil است، بی‌خطر).
- خروجی نهایی (`genesis.json`) باید قبل از استفاده‌ی واقعی، توسط حداقل دو نفر جدا از سازنده‌ی ابزار بازبینی شود (بخش «سؤالات باز» را ببین). فهرست طلبکاران و مبالغ آن‌ها پس از genesis قابل تغییر نیست و تعویض آدرس مجاز نیست؛ بازبینی دقیق آن الزامی است.
- زنجیره‌ی موقت Anvil نباید هرگز به هیچ شبکه‌ی خارجی متصل باشد (`--silent`, بدون `--fork-url`).

## ۱۰. سؤالات باز

تنها پیش‌نیاز، تکمیل واقعی فایل پیکربندی (بخش ۳) با مقادیر نهایی تصمیم‌گیری‌شده است، طبق `sur-master-open-items.md`. موارد باز:

| # | مورد |
|---|---|
| ۱ | 🔶 تأیید نهایی آدرس‌های پیشنهادیِ `FoundationMembers` (`0x7777…7777`)، `ValidatorSeatNFT` (`0x8888…8888`)، `GenesisClaimsVault` (`0x9999…9999`) و `ValidatorLottery` (`0xaAaA…aAaa`) در `SurAddresses`. |
| ۲ | ✅ تصمیم مالک ۲۰۲۶-۱۱-۱۹: ترکیب هیأت‌مدیرهٔ اولیهٔ ولیدیتورها در لحظهٔ genesis، وقتی فقط یک ولیدیتور فعال است، کرسی دارد ولی عضو `Probation` عمل نمی‌کند تا Verifier فعالش کند (`hasBoardAuthority` برایش `false`؛ `syncBoard()` حذفش نمی‌کند، پس هیأت در genesis فرو نمی‌پاشد). پیامد: هیأت در بلاک ۱ کامل کار نمی‌کند؛ اقدام هیأت دست‌کم ۳ رأی می‌خواهد، پس دست‌کم ۲ مؤسس دیگر را زود فعال کنید. |
| ۳ | 🔶 اینکه رئیس هیأت‌مدیره، خزانه‌دار و مدیرعامل بنیاد در genesis مقدار اولیه داشته باشند یا پس از راه‌اندازی انتخاب شوند. |
| ۴ | ✅ گرد کردن قسط ماهانهٔ طلب وقتی `(طلب − ۱۰۰)` بر ۲۴ بخش‌پذیر نیست: باقی‌مانده در قسط آخر می‌آید (پیش‌فرض کد؛ 🔶 فقط اگر مالک رفتار دیگری بخواهد). 🔶 مرز ماه میلادی (UTC) روی Besu واقعی آزموده نشده (در BG-11 فقط `genesisTimestamp` برابر زمان بلاک صفر و `monthIdOf` و `monthsReleased() == 0` درست بودند؛ آزادسازی ماهانه اجرا نشد). |
| ۵ | ✅ بسته شد: seed Registry صندلی نمی‌سازد؛ صندلی‌ها را `ValidatorSeatNFT_GenesisSeed` جدا می‌سازد و تنها قید، یکی‌بودن ترتیب مؤسسان در دو helper است. |
| ۵-ب | 🔶 برداشتن سقف اندازهٔ کد برای deploy کمکی‌های `FoundationDAO` و `ValidatorsRegistry` (حدود ۳۶٬۸۷۹ بایت) روی Anvil (بخش ۴.۲). |
| ۶ | ✅ در کد: شش مؤسس `Probation` می‌مانند تا `setOperator` و `recordActivation` (بدون انتظار دوره) بزنند؛ `everActivated` و `activationSeq` هنگام `recordActivation` و به ترتیب فعال‌شدن ثبت می‌شود (نه ترتیب genesis). 🔶 اثر آن بر شکستن تساوی هیأت (ترتیب فعال‌سازی) تأیید مالک می‌خواهد؛ آزمون Besu نشده. |

🔶 **تصمیم باز (آزمون Besu v4، ۲۰۲۶-۱۰-۰۳):** فایل پیکربندی بخش ۳ و خروجی ابزار هیچ ورودی یا خروجی برای `transitions.qbft` ندارد. آزمون v4 نشان داد همهٔ نودها، از جمله نودهای تازه‌وارد، باید همان transition پاداش را در genesis خود داشته باشند (وگرنه در بلاک گذار رد می‌شوند؛ در حالت Shanghai/Cancun مقدار `block` یک timestamp است). اینکه ابزار genesis این را تولید کند یا رویهٔ جداگانه‌ای انجام دهد، **انتخاب نشده است** (`sur-reward-router-spec.md` بخش ۱۰.۳). دور ششم Besu (۲۰۲۶-۱۰-۰۷، release ۲۶.۹.۰، Shanghai/Cancun) نشان داد گذار `blockreward` با کلید timestamp پاداش را دقیقاً در نخستین بلاکِ `timestamp ≥ کلید` عوض می‌کند؛ ولی گذار `validatorselectionmode: blockheader` با کلید timestamp (فهرست صریح ۵ از ۷) زنجیره را متوقف کرد (`governance/sur-emergency-consensus-recovery.md` بخش ۳). پس هر تصمیم برای تولید `transitions.qbft` باید گذار پاداش را از گذار انتخاب ولیدیتور جدا کند و هیچ گذار `blockheader`ای را قبل از آزمودن یک پیکربندی کارکننده تولید نکند.
