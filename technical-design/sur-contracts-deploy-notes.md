# یادداشت دیپلوی — مجموعه‌ی قراردادهای سور (مدل دیپلوی در بلاک genesis)

> **وضعیت پیاده‌سازی (۲۰۲۶-۱۱-۱۹):** از طرح ۲.۵ این بخش‌ها اکنون در `contracts/` نوشته و با ۹۷ آزمون Hardhat در ۱۰ فایل (روی EVM درون‌فرایندی Hardhat، نه Besu/QBFT) آزموده شده‌اند: `FoundationDAO` (با نوع آزاد `Execute` و `EndSale`)، `FoundationMembers`، `SurenSale` (مدل صرافی، بدون اوراکل پرداخت)، `ValidatorLottery`، `GenesisClaimsVault` (صندوق طلب‌ها؛ ۲۴ قسط ماهانه)، حذف ولیدیتور در بازیابی شبکه (`RemovedInRecovery`)، تغییرات `IdentityRegistry` (بله/ایمیل، `isFullyVerified`)، `ValidatorSeatNFT` (صندلی ERC-721 با انتقال و قواعد خریدار)، هستهٔ بازطراحی `ValidatorsRegistry`/`ValidatorsBoard` (وثیقهٔ ثابت، کلید مالک/اپراتور، جریان مؤسسان، `SelfSuspended`، سوزاندن ۱۰۰٪ جریمه، قواعد فاصلهٔ ورود) و سوزاندن مازاد پاداش در `BlockRewardDistributor`. ⚠️ **دامنهٔ صادقانه (جایگزین‌شده ۲۰۲۶-۱۱-۲۳؛ فهرست «هنوز نوشته نشده» این بند کهنه بود):** سرویس‌های آف‌چین `RewardRouter` (قرارداد نیست)، Verifier، SurKMS، Identity Service، `GenesisBuilder`، NodeCheck و EventIndexer ساخته و روی Besu آزموده شده‌اند؛ ساخته نشده‌اند: ابزار بازیابی، گزارش عرضه، یکپارچگی صرافی و رابط لاتاری. حدود تغییر ریوارد (±۱۰٪ نسبی، ۱۸۰ روز فاصله، ۱۸۰ روز اول ممنوع) از ۲۰۲۶-۱۱-۲۳ در کد است. پوشه‌های `contracts/` و `contracts-fa/` فقط نسخهٔ جاری را نگه می‌دارند؛ نسخه‌های قدیمی در git هستند (برچسب [`v2.2.0`](https://github.com/Sur-network/sur-new/releases/tag/v2.2.0)). نام تابع‌ها هر جا از کد گرفته شده همان نام کد است. ✅ دور اول آزمون زندهٔ Besu برای قراردادهای ۲٫۵ انجام شد (۲۰۲۶-۱۱-۱۹؛ Besu 26.9.0 در Docker، QBFT، فورک London، یک میزبان، اجراهای کوتاه؛ ۲۲ فایل نتیجه؛ دو اجرای اول به‌علت اشکال اسکریپت ناموفق ثبت و نگه داشته شده‌اند، بقیه گذشتند): `testing-evidence/besu-live-test-v25-2026-11-19/REPORT.md`. 🔶 هنوز روی Besu اجرا نشده: هر تایمر ۷۲ ساعت و بیشتر (قفل ۹۰ روزه، انقضا و ارجاع ۷روزه، دورهٔ آزمایشی و مهلت ورود با مقدار واقعی)، آزادسازی ماهانهٔ صندوق طلب‌ها، `recordSuspension`/رخداد جمعی/جریمه/اعتراض/`recordRecovery`، لاتاری دوم، تازه‌سازی ماهانهٔ هیأت، حکمرانی نرخ ریوارد، گذار Shanghai/Cancun، `SurenSale`، `ServiceStaking` و خرج خزانه؛ یافته‌های باز F-1 تا F-7 در `sur-master-open-items.md` بخش ۵. حسابرسی امنیتی هم انجام نشده است؛ این نتیجه آمادگی تولید نیست.

> ✅ **همترازی با قراردادها (۲۰۲۶-۱۱-۲۳):** این سند پس از commitهای `11ff741` و `187c7dd` با `contracts/` هم‌تراز شد (۱۸۶ آزمون Hardhat در ۲۱ فایل). عددهای ۹۷/۱۰ و ۱۳۶/۱۴ در بند بالا و در بخش «آزمون‌های Hardhat» شمارش‌های تاریخ‌دار همان روزند.

> **وضعیت سند:** مرجع استقرار genesis برای نسخهٔ ۲.۵. ✅ دور اول آزمون Besu برای ۲.۵ انجام شد (۲۰۲۶-۱۱-۱۹؛ بخش «نتایج دور اول آزمون Besu برای ۲.۵» در انتهای سند)؛ 🔶 بخشی از ویژگی‌ها هنوز روی Besu اجرا نشده است. نتایج بخش «نتایج آزمون Besu روی کد پایه‌ی ۲.۲» فقط به کد ۲.۲ مربوط‌اند.

طرح ۲.۵ **دوازده قرارداد ساختاری** دارد: شش قرارداد پایه (`FoundationDAO`، `BlockRewardDistributor`، `ValidatorsRegistry`، `ValidatorsBoard`، `ValidatorsTreasury`، `IdentityRegistry`) و شش قرارداد تازه (`ValidatorSeatNFT`، `GenesisClaimsVault`، `FoundationMembers`، `ValidatorLottery`، `KmsDirectives`، و `StandbyValidators` در `0xCcCC…cCcC` بدون constructor و بدون seed ذخیره در سورس؛ GenesisBuilder آن را با `StandbyValidators_GenesisSeed` فقط با اولین ولیدیتور پر می‌کند؛ ✅ ۲۰۲۶-۱۱-۲۳: هر عضو فهرست باید کلید اپراتور فعلیِ یک صندلی **زنده** باشد (`Probation`، `Active`, `Demoted` یا `SelfSuspended`)، و مالکِ خارج‌شده/برداشت‌کرده/حذف‌شده در بازیابی عضو را کهنه می‌کند (فروش یا مهاجرت صندلی کلید اپراتور را با صندلی می‌برد و عضو را کهنه نمی‌کند؛ فقط تعویض کلید توسط خودِ مالک یا خروج او کهنه‌اش می‌کند) (`staleMembers`، `isReady`، `setStandby` ریورت می‌کند)). هیچ‌کدام با تراکنش عادی دیپلوی نمی‌شوند و به `wire()` نیاز ندارند؛ همگی مستقیماً در `alloc` بلاک genesis، با آدرس‌های ثابت و از‌پیش‌توافق‌شده، تزریق می‌شوند. این باعث می‌شود مشکل وابستگی دوطرفه‌ی آدرس‌ها (circular dependency) اصلاً پیش نیاید: چون آدرس هر قرارداد از قبل معلوم است، هرکدام آدرس بقیه را مستقیماً به‌صورت `constant` در سورس هاردکد می‌کنند.

## آدرس‌ها (`SurAddresses.sol`)

| آدرس | قرارداد |
|---|---|
| `0x1111111111111111111111111111111111111111` | `FoundationDAO` |
| `0x2222222222222222222222222222222222222222` | `BlockRewardDistributor` |
| `0x3333333333333333333333333333333333333333` | `ValidatorsRegistry` |
| `0x4444444444444444444444444444444444444444` | `ValidatorsBoard` |
| `0x5555555555555555555555555555555555555555` | `ValidatorsTreasury` |
| `0x6666666666666666666666666666666666666666` | `IdentityRegistry` |
| `0x8888888888888888888888888888888888888888` (پیشنهادی) | `ValidatorSeatNFT` (✅ کد و آزمون Hardhat) |
| `0x9999999999999999999999999999999999999999` (پیشنهادی) | `GenesisClaimsVault` (✅ کد و آزمون Hardhat) |
| `0x7777777777777777777777777777777777777777` (پیشنهادی) | `FoundationMembers` |
| `0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa` (پیشنهادی؛ checksum به‌صورت کد) | `ValidatorLottery` |
| `0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB` (پیشنهادی؛ checksum به‌صورت کد؛ ۲۰۲۶-۱۱-۲۱) | `KmsDirectives` (کلید قطع سرویس امضای SurKMS؛ ✅ کد و آزمون Hardhat) |

🔶 آدرس پنج قرارداد تازه در `SurAddresses.sol` **پیشنهاد** شده است (همان الگوی `0xNNNN…NNNN`؛ برای لاتاری `0xaAaA…aAaA` و برای `KmsDirectives` `0xbBbB…bBbB`)؛ تثبیت نهایی بخشی از طراحی genesis است. `ValidatorSeatNFT` و `GenesisClaimsVault` نوشته و با Hardhat آزموده شده‌اند. ✅ `PAYMENT_ORACLE` از `SurAddresses.sol` حذف شده است: ۲.۵ دقیقاً **سه اوراکل** دارد (`verifier`، `distributionOracle`، `identityOracle`) و `SurenSale` اوراکل ندارد.

## چرا این مسیر ممکن است: دیپلوی مستقیم در `alloc`

Besu (مثل بقیه‌ی کلاینت‌های اتریوم) اجازه می‌دهد در بخش `alloc` فایل `genesis.json`، برای هر آدرس، مستقیماً `code` (بایت‌کد deploy-شده) و `storage` (مقدار اولیه‌ی هر storage slot) تعیین شود — بدون اجرای واقعی هیچ تراکنشی.

⚠️ **هیچ‌یک از قراردادهای ساختاری `constructor` ندارند.** دلیلش صرفاً نظری نیست — با شواهد واقعی: قراردادهایی که در genesis تزریق می‌شوند ولی سورسشان `constructor` دارد، در چندین گزارش باگ مستند Blockscout (هم قدیمی هم در مستندات فعلی سرویس تأیید هویتش) در فرآیند وریفای‌شدن روی اکسپلورر مشکل داشته‌اند — چون ابزار وریفای ذاتاً دنبال یک «تراکنش ایجاد قرارداد» می‌گردد که برای آدرس‌های genesis اصلاً وجود ندارد. قراردادهای بدون `constructor` این مشکل را کلاً ندارند. برای همین، مقداردهی اولیه به‌جای `constructor`، مستقیم در بدنه‌ی قرارداد (خارج از هر تابع) انجام می‌شود — با علامت `🔶 FILL_IN` کنار هر مقداری که هنوز نهایی نشده.

### مشکل: مقادیر ساده در مقابل mapping/آرایه‌ی پویا

برای متغیرهای ساده (یک `address` یا `uint256`)، مقداردهی مستقیم در بدنه‌ی قرارداد کاملاً کافی است:
```solidity
address public verifier = 0x0000000000000000000000000000000000000000; // 🔶 FILL_IN
```

ولی برای `mapping` یا آرایه‌ی پویا (مثلاً لیست ۱۵ عضو اولیه‌ی بنیاد، فهرست طلبکاران، مالک هر NFT، یا لیست ولیدیتورهای اولیه)، **زبان Solidity اصلاً syntax ندارد** که بشود خارج از یک تابع، با حلقه، این‌ها را پر کرد. این محدودیت زبانی است، نه سلیقه‌ای.

### چرا: محل ذخیره‌ی mapping/آرایه با فرمول محاسبه می‌شود، نه یک slot ثابت

هر متغیر ساده در EVM یک شماره‌ی storage slot ثابت دارد (بر اساس ترتیب اعلانش در سورس). ولی `mapping` و آرایه‌ی پویا این‌طور نیستند:

| نوع داده | فرمول محل ذخیره |
|---|---|
| `mapping(K => V) at slot p`، برای کلید `k` (وقتی `V` یک مقدار ساده است) | `slot = keccak256(abi.encode(k, p))` |
| `mapping(K => Struct) at slot p`، برای کلید `k` | پایه = `keccak256(abi.encode(k, p))`؛ فیلدهای struct پشت‌سرهم از همان پایه (`base`, `base+1`, ...) |
| آرایه‌ی پویا `T[] at slot p` | خودِ `p` طول آرایه را نگه می‌دارد؛ عنصر `i`اُم در `keccak256(p) + i` |
| `string` کوتاه (≤۳۱ بایت) داخل یک slot | مستقیم در همان slot، با یک بایت آخر که طولش را کد می‌کند |
| `string` بلند (≥۳۲ بایت) | خودِ slot فقط طول را نگه می‌دارد؛ محتوا از `keccak256(slot)` به بعد |

مثلاً `FoundationMembers` (آرایه‌ی پویا `_list` از آدرس‌ها، `mapping(address => Member)` با `struct Member { string name; PersonType personType; address representative; uint256 shares; }` و نگاشت اندیس) چند لایه‌ی تودرتوی همین قوانین را همزمان دارد — دقیقاً همان چیزی که دستی‌محاسبه‌کردنش را پرخطا می‌کند.

### راه‌حل توصیه‌شده: یک قرارداد کمکی موقت، نه محاسبه‌ی دستی

ابزار ساخت genesis باید این‌طور عمل کند:

1. برای هر قراردادی که `mapping`/آرایه‌ی پویا نیاز به مقداردهی دارد، یک **نسخه‌ی موقت (seed helper)** بسازد که یک `constructor` واقعی دارد. ✅ **از ۲.۵ برای شش قرارداد `FoundationDAO`، `FoundationMembers`، `ValidatorsRegistry`، `ValidatorsBoard`، `ValidatorSeatNFT` و `GenesisClaimsVault` این نسخه‌ی موقت خودِ قرارداد واقعی را ارث می‌برد** (`contract X_GenesisSeed is X`، در `contracts/genesis-seed-helpers/`) و فقط یک `constructor` به آن اضافه می‌کند؛ پس **چینش storage به‌ساختار با قرارداد واقعی یکی است** و هیچ نسخه‌ی کپی‌شده‌ای وجود ندارد که باید دستی هم‌گام نگه داشته شود.
2. این نسخه‌ی موقت را روی یک زنجیره‌ی محلی (Anvil/Hardhat) دیپلوی کند — `constructor` واقعاً و کامل اجرا می‌شود (آزمون‌های `contracts-tests/` همین روش را برای شش قرارداد بالا به‌کار می‌برند)، خودِ EVM تمام محاسبات `keccak256` بالا را درست انجام می‌دهد.
3. از این زنجیره‌ی محلی، تمام storage slotهای واقعاً نوشته‌شده را بخواند (`eth_getStorageAt` روی هر slot لمس‌شده، یا با ابزار state-dump آن شبکه — مثل `anvil_dumpState`).
4. این slotها را — همراه با بایت‌کد قرارداد **واقعی و نهایی** (بدون constructor) — زیر همان آدرس ثابت در `alloc` genesis بنویسد.

⚠️ نکته‌ی مهم: بایت‌کدی که در `alloc.code` می‌رود باید از قرارداد **واقعی و بدون constructor** باشد، نه از نسخه‌ی موقتِ دارای constructor — نسخه‌ی موقت فقط برای محاسبه‌ی storage استفاده می‌شود، نه برای گرفتن بایت‌کد (چون helper ارث‌بر است، runtime آن هم‌شکل است ولی باز هم باید runtime قرارداد واقعی نوشته شود).

✅ **قاعدهٔ قدیمی `__gap` و `check_genesis_helper_layout.js` برای این شش قرارداد دیگر لازم نیست:** در ۲.۲ نسخه‌ی موقت کپی دستی با جای‌گذارهای `__gap` بود و چینش با اسکریپت `check_genesis_helper_layout.js` مقایسه می‌شد. در ۲.۵ ارث‌بری یکسانی چینش را «به‌ساختار» تضمین می‌کند. 🔶 هر قرارداد دیگری که در آینده helper کپی‌شده بخواهد، همان قاعدهٔ قدیمی و بررسی چینش را می‌خواهد؛ در حال حاضر چنین قراردادی نیست (`BlockRewardDistributor`، `ValidatorsTreasury`، `IdentityRegistry` فقط مقدار ساده دارند و `ValidatorLottery`/`SurenSale` وضعیت اولیهٔ غیرصفر ندارند).

### جایگزین (فقط برای اعتبارسنجی، نه مسیر اصلی): محاسبه‌ی دستی

اگر خواستی نتیجه‌ی مرحله‌ی بالا را صحت‌سنجی کنی، می‌توانی برای موارد ساده (مثل یک `mapping(address => bool)`) با فرمول جدول بالا دستی هم محاسبه کنی و با خروجی ابزار مقایسه کنی. برای `Member.name` (string داخل struct داخل آرایه) این کار عملاً غیرعملی است — همان‌جا باید به نتیجه‌ی شبیه‌سازی اعتماد کرد.

**دستورالعمل عملی کامل:**
1. همه‌ی قراردادهای **نهایی** (بدون constructor) را کامپایل کن تا بایت‌کد واقعی `alloc.code` به دست بیاید.
2. برای هر قراردادی که `mapping`/آرایه‌ی پویا دارد (جدول «کدام قراردادها نیاز به شبیه‌سازی دارند» پایین)، نسخه‌ی موقتِ ارث‌بر (`*_GenesisSeed`) را با آرگومان‌های نهایی (بخش «قراردادهای کمکی seed» پایین) روی Anvil/Hardhat دیپلوی کن و کل storage نهایی را استخراج کن.
3. برای قراردادهای ساده‌ای که فقط مقدار ساده دارند، دیگر نیازی به شبیه‌سازی نیست — مقادیر `🔶 FILL_IN` را مستقیم در سورس جایگزین کن و storage اولیه را از یک دیپلوی واقعی/overlay صریح بخوان (بخش «کامپایل به‌تنهایی کافی نیست» پایین).
4. این دو مقدار (`code` از مرحله‌ی ۱، `storage` از مرحله‌ی ۲ یا ۳) را زیر همان آدرس ثابت (جدول بالا) در بخش `alloc` genesis.json بگذار.
5. `qbft.validatorcontractaddress` را برابر `0x3333...3333` بگذار.
6. `qbft.miningbeneficiary` را برابر `0x2222...2222` بگذار.
7. ✅ `blockreward` را برابر `"2000000000000000000"` بگذار (= ۲ سورن؛ تصمیم قطعی — به `sur-blockchain-design-doc.md` بخش ۳ مراجعه کن). این مقدار پیش‌فرضش صفر است؛ اگر صریح تنظیم نشود هیچ ولیدیتوری هیچ ریواردی نمی‌گیرد، بدون هیچ خطای هشداردهنده. مقدار مصوب اولیه‌ی `BlockRewardDistributor` باید دقیقاً همین ۲ سورن باشد، وگرنه از همان بلاک اول مازاد (یا کسری) ثبت می‌شود.
8. ✅ `qbft.blockperiodseconds` را برابر `3` بگذار (تصمیم قطعی). `BlockRewardDistributor` ثابت `MIN_BLOCK_PERIOD_SECONDS` و سقف زمان‌محور تعداد بلاک ندارد (تعداد بلاک با کنترل بازه‌ی P05 محدود می‌شود)؛ تغییر بعدی `blockperiodseconds` نیازی به تغییر یا دیپلوی مجدد قرارداد ندارد. ✅ **مکانیزم رسمی تغییر بعدی (تأییدشده):** بخش `transitions.qbft` در genesis Besu — یک hard fork هماهنگ‌شده با توقف/به‌روزرسانی/راه‌اندازی مجدد هم‌زمان همه‌ی نودها، نه رأی‌گیری on-chain. همین مکانیزم برای اعمال تغییر مصوب `blockreward` هم استفاده می‌شود — جزئیات کامل در `sur-blockchain-design-doc.md`، بخش «سیاست انتشار».
9. ✅ `min-gas-price` (تنظیمات سطح Besu، نه فیلد genesis.json خودش — در `config.toml` یا آرگومان راه‌اندازی نود) را برابر `100000000000000` (`10^14` wei) بگذار — تصمیم قطعی؛ جزئیات کامل محاسبه‌اش در `sur-blockchain-design-doc.md`، بخش «gasPrice و اقتصاد فی». ⚠️ این عدد **هیچ مسیر حکمرانی on-chain** ندارد — بعداً فقط با آپدیت پیکربندی نودها (نه رأی‌گیری) قابل‌تغییر است. ⏸️ ابزار عملیاتی تنظیم قیمت گس برای اپراتور نود فعلاً اجرا نمی‌شود، ولی زیرساخت نباید مانع آن در آینده شود.

## ⚠️ نکته‌ی فنی مهم: `block.timestamp` داخل شبیه‌سازی قابل‌اتکا نیست

چون قرارداد اصلی `constructor` ندارد، این نکته فقط برای همان **نسخه‌ی موقتِ شبیه‌سازی** (بخش بالا) صدق می‌کند: هر جا منطق مقداردهی اولیه (چه در `constructor` نسخه‌ی موقت، چه به‌عنوان مرجع برای محاسبه‌ی دستی) به `block.timestamp` نیاز دارد، مقداری که واقعاً باید استفاده شود، زمان **واقعی بلاک genesis شبکه‌ی سور** است، نه زمان اجرای شبیه‌سازی روی ماشین توسعه‌دهنده.

- **`ValidatorsRegistry`**: `genesisTime` را کمکی seed از آرگومان `genesisTimestamp` می‌نویسد و باید دقیقاً برابر timestamp واقعی بلاک genesis باشد؛ `periodStartedAt` هر مؤسس هم همان مقدار می‌شود. «۶ ماه اول از genesis» برای تغییر `EntryWindowSeconds` از `genesisTime` شمرده می‌شود؛ ✅ همین `genesisTime` را `BlockRewardDistributor` هم برای ممنوعیت ۱۸۰ روزهٔ تغییر ریوارد می‌خواند (`ValidatorsRegistry.genesisTime()`؛ اگر seed نشده باشد هیچ تغییر نرخی ممکن نیست: بسته می‌ماند، پس seed درست `genesisTimestamp` برای ریوارد هم لازم است). `lastPaidActivationAt` را کمکی نمی‌نویسد و ۰ می‌ماند (جای `windowStart` که حذف شده): اولین فعال‌سازی ورودی پولی هرگز به تأخیر نمی‌افتد و همان زمان آغاز فاصلهٔ ورود را می‌گذارد (✅ ۲۰۲۶-۱۱-۲۳: شمارش در `recordActivation` است، نه در `requestMembership`).
- **`ValidatorsBoard`**: `boardMonthId` برابر ماه میلادی UTC زمان genesis (بخش «مقادیر پیش از genesis» پایین).
- **`GenesisClaimsVault`**: `genesisTimestamp` (باید برابر `timestamp` فایل `genesis.json` باشد؛ seed آن را در storage می‌نویسد)؛ شناسه‌ی ماه میلادی genesis از آن محاسبه می‌شود؛ اولین قسط در ابتدای **اولین ماه میلادی پس از genesis** است (در ماه genesis قسطی آزاد نیست)، پس مبنای آزادسازی باید با timestamp واقعی genesis محاسبه شود.
- **`BlockRewardDistributor`**: هیچ مقدار وابسته به timestamp genesis و هیچ immutableی در storage خودش ندارد؛ ✅ ممنوعیت ۱۸۰ روز اول تغییر ریوارد از `ValidatorsRegistry.genesisTime()` خوانده می‌شود (تایمر در این قرارداد نگه‌داری نمی‌شود) و `lastRateChangeTime` از ۰ شروع می‌شود و seed نمی‌خواهد.

## کدام قراردادها نیاز به شبیه‌سازی دارند، کدام‌ها نه

| قرارداد | نیاز به قرارداد کمکی موقت؟ | چرا |
|---|---|---|
| `FoundationDAO` | ✅ بله (`FoundationDAO_GenesisSeed`) | اولین هیأت‌مدیره (۵ اصلی + حداکثر ۲ علی‌البدل)، بازرس، رئیس، خزانه‌دار، مدیرعامل، پایان دوره (آرایه/mapping) |
| `FoundationMembers` | ✅ بله (`FoundationMembers_GenesisSeed`) | فهرست اعضا، `mapping` به `struct Member` با `string`، اندیس و نمایندهٔ شخص حقوقی، `totalShares` |
| `ValidatorsRegistry` | ✅ بله (`ValidatorsRegistry_GenesisSeed`) | `validators` (mapping به `struct`: وضعیت، وثیقه، زمان‌ها)، `activeValidators`/`activeIndex`، `operatorOf`/`ownerOfOperator`، `isFounder`، `everActivated`/`activationSeq`، `genesisTime`، checkpoint فعال‌بودن |
| `ValidatorsBoard` | ✅ بله (`ValidatorsBoard_GenesisSeed`) | `boardMembers` (آرایه‌ی پویا)، `isBoardMember` (mapping) |
| `GenesisClaimsVault` | ✅ بله (`GenesisClaimsVault_GenesisSeed`) | `mapping` طلب هر آدرس (`held`، `withdrawn`)، `totalHeld`، `genesisTimestamp` |
| `ValidatorSeatNFT` | ✅ بله (`ValidatorSeatNFT_GenesisSeed`) | مالک و موجودی هر توکن، `seatOf`، `totalMinted` و `baseURI` اولیه (رشته)؛ `tokenURI` ذخیره نمی‌شود و از `baseURI` + شناسه ساخته می‌شود |
| `BlockRewardDistributor` | ❌ خیر | فقط `distributionOracle`، `validatorDirectShareBps` و مقدار مصوب ریوارد — مقادیر ساده، باید overlay شوند؛ immutable ندارد |
| `ValidatorsTreasury` | ❌ خیر | فقط `perPaymentCap`/`periodCap` — مقادیر ساده |
| `IdentityRegistry` | ❌ خیر | فقط `identityOracle` — مقدار ساده |
| `ValidatorLottery` | ❌ خیر | ساختاری، بدون constructor؛ وضعیت اولیه همه‌چیز صفر است؛ مجری و مدیرعامل از `FoundationDAO` خوانده می‌شوند |
| `KmsDirectives` | ❌ خیر | ساختاری، بدون constructor و بدون هیچ storage اولیه (همهٔ پرچم‌ها `false`)؛ فقط بایت‌کد اجرایی در `alloc` و موجودی صفر. **ابزار GenesisBuilder باید این قرارداد و آدرسش را بشناسد** (`D:\Amir\Business\SUR\NewSur\Deployments\GenesisBuilder`؛ هنوز تغییر نکرده) |

⚠️ **کامپایل به‌تنهایی storage اولیه‌ی درست تولید نمی‌کند:** کامپایل فقط `storageLayout` و creation code را می‌دهد؛ کپی‌کردن `deployedBytecode` به `alloc.code` دستورهای مقداردهی اولیه‌ی متغیرهای غیرconstant را اجرا نمی‌کند (آدرس اوراکل‌ها، سهم‌های قابل‌تغییر، سقف‌ها، پارامترهای زمانی…). برای هر قراردادی — از جمله قراردادهای ستون «خیر» — وضعیت اولیه باید یا از **اجرای واقعی creation code** (دیپلوی روی زنجیره‌ی موقت و خواندن `code` با `eth_getCode` و هر storage slot لمس‌شده) استخراج شود، یا با overlay صریح slotها نوشته شود. دو نکته‌ی اجباری: (۱) متغیرهای `immutable` (در قراردادهای genesis هیچ immutableی نیست؛ تنها immutable پروژه `SurenSale.saleStartTime` است) داخل runtime code جایگزین می‌شوند، پس runtime نهایی باید از یک دیپلوی واقعی روی زنجیره‌ی موقتی که timestamp بلاکش برابر timestamp genesis تنظیم شده استخراج شود (یا محل‌های immutable با `immutableReferences` شناسایی و patch و آزموده شوند) — برداشتن خام `evm.deployedBytecode.object` کافی نیست؛ (۲) درستی باید با assertion از **بلاک صفر** روی همه‌ی scalarهای غیرصفر، اعضا، طلبکاران، مالکان NFT و آدرس اوراکل‌ها تأیید شود؛ برابری `eth_getCode` روی چند نود، درستی مقداردهی را ثابت نمی‌کند.

## ترتیب دیپلوی

چون constructor وجود ندارد، «ترتیب دیپلوی» معنا ندارد — هر دوازده قرارداد فقط باید کامپایل شوند (و آن‌هایی که ستون «بله» دارند، علاوه‌براین شبیه‌سازی هم بشوند، طبق بالا). ترتیب کامپایل/شبیه‌سازی هیچ اهمیتی ندارد، چون این قراردادها در حین محاسبه‌ی state اولیه، اصلاً به همدیگر call نمی‌زنند — فقط آدرس همدیگر را به‌صورت `constant` در سورس دارند.

## تخصیص سورن در `alloc` (عرضه‌ی کل genesis: ۵۳٬۳۱۱٬۰۰۰ سورن)

| ردیف | مقصد | مبلغ |
|---|---|---|
| ۱ | آدرس `FoundationDAO` (`0x1111...1111`) — توسعه/آموزش/اکوسیستم (موضوع فعالیت بنیاد، ماده ۳ اساسنامه، و تصمیم پروژه برای تخصیص ۲۰ میلیون سورن) | ۲۰٬۰۰۰٬۰۰۰ سورن |
| ۲ | طلب‌های ولیدیتورهای اولیه (۷ نود مؤسس) — **به `GenesisClaimsVault`** | ۱۱٬۹۸۴٬۰۰۰ سورن (مبلغ هر نود: `sur-tokenomics.md` بخش ۲.۲) |
| ۳ | طلب‌های ۱۵ عضو بنیاد — **به `GenesisClaimsVault`** | ۲۱٬۳۲۷٬۰۰۰ سورن (مبلغ هر عضو: `sur-tokenomics.md` بخش ۲.۱) |

- ردیف ۲ و ۳ مجموعاً ۳۳٬۳۱۱٬۰۰۰ سورن‌اند و به کیف‌پول افراد نمی‌روند؛ در `GenesisClaimsVault` قفل می‌شوند.
- **ذخیره‌ی گس:** هر طلبکار (به‌ازای هر آدرس یک طلب جمع‌شده؛ حتی اگر آدرس هم در ردیف ۲ و هم در ردیف ۳ باشد) **۱۰۰ سورن** از طلبش را از ابتدا مستقیم در `alloc` کیف‌پول خودش دارد. این مبلغ از طلب او کسر می‌شود؛ پس موجودی `GenesisClaimsVault` در بلاک صفر برابر `۳۳٬۳۱۱٬۰۰۰ − ۱۰۰ × (تعداد آدرس‌های طلبکار)` است و جمع کل همچنان ۵۳٬۳۱۱٬۰۰۰ سورن می‌ماند. تعداد آدرس‌های یکتا را ابزار genesis از فهرست نهایی می‌شمارد.
- **آزادسازی:** باقیمانده‌ی هر طلبکار، `(طلب − ۱۰۰)`، در ۲۴ قسط مساوی `(طلب − ۱۰۰) / ۲۴` در ابتدای هر ماه میلادی آزاد می‌شود. اولین قسط در ابتدای اولین ماه میلادی پس از genesis است (در خودِ genesis قسطی آزاد نیست). قسط برداشت‌نشده منقضی نمی‌شود و انباشته می‌ماند؛ هر زمان فقط مبلغ آزادشده قابل برداشت است. ✅ باقیمانده‌ی تقسیم (اگر `(طلب − ۱۰۰)` بر ۲۴ بخش‌پذیر نباشد) در **قسط آخر** قرار می‌گیرد؛ پیش‌فرض کد است و اگر مالک رفتار دیگری بخواهد 🔶 باید تغییر کند.
- **seed و موجودی `alloc` صندوق:** `GenesisClaimsVault_GenesisSeed(address[] claimants, uint256[] claims, uint256 genesisTimestamp)` ارث‌بر از قرارداد واقعی است و در constructor خودش طلب‌ها را ثبت می‌کند؛ هر `claims[i]` طلب **کامل** آدرس است (شامل همان ۱۰۰ سورنی که مستقیم به کیف‌پول می‌رود؛ باید بیش از ۱۰۰ سورن باشد؛ آدرس صفر یا تکراری ممنوع). موجودی `alloc` آدرس صندوق باید دقیقاً برابر `totalHeld()` باشد (مجموع `claim − ۱۰۰` همهٔ آدرس‌ها). انتقال ساده به صندوق revert می‌کند، پس صندوق فقط از راه `alloc` شارژ می‌شود.
- **آدرس‌ها:** پیش از genesis مشخص و در قرارداد ثبت می‌شوند؛ تعویض آدرس مجاز نیست؛ مبلغ مطالبه‌نشده در قرارداد می‌ماند تا خود طلبکار برداشت کند. طلب ولیدیتورهای مؤسس مشروط به ولیدیتور ماندن نیست و قابل‌جریمه نیست.
- عرضه‌ی در گردش اولیه کمتر از ۵۳٬۳۱۱٬۰۰۰ است و در طول ۲۴ ماه به‌تدریج زیاد می‌شود.
- هیچ‌کدام از این‌ها از طریق constructor نیست — همگی `balance` مستقیم در genesis‌اند.

## مقادیری که باید قبل از تولید genesis نهایی پر شوند

(لیست کامل هرکدام در خودِ سورس با علامت `🔶 FILL_IN` مشخص است.) هر سه آدرس اوراکل (`verifier`، `distributionOracle`، `identityOracle`) مستقیم در سورس هاردکد شده‌اند. جزئیات کامل آدرس‌ها در `sur-contracts-oracles-accounts-report.md`.

1. `ValidatorsRegistry` — فهرست ۷ ولیدیتور مؤسس با `ValidatorsRegistry_GenesisSeed(address firstOwner, address firstOperator, address[] otherFounders, uint256 genesisTimestamp)` (نیازمند شبیه‌سازی): هرکدام با آدرس اتریومی **مالک** مشخص، وثیقه‌ی صفر، `isFounder = true` و غیرپرداخت‌کننده؛ **فقط اولین ولیدیتور** (`firstOwner`، راه‌انداز genesis) `Active` است و کلید اپراتورش (`firstOperator`، همان کلیدی که در QBFT genesis می‌آید) از ابتدا ثبت است؛ شش مؤسس دیگر (`otherFounders`) با وضعیت `Probation` و بدون اپراتور ثبت می‌شوند و پس از `setOperator` و `recordActivation` (✅ بدون انتظار دورهٔ آزمایشی؛ فقط تأیید روشن‌بودن نود توسط Verifier) `Active` می‌شوند. پارامترهای امنیتی (✅ نهایی؛ مقدار اولیه در سورس: `entryWindowSeconds=604800` (۷ روز)، `recoveryPeriod=172800`, `exitCooldown=604800`؛ ✅ ۲۰۲۶-۱۱-۲۳: `maxEntriesPerWindow=1`، `probationPeriod=604800` و `slashBps=100` اکنون **ثابت‌های** قرارداد‌اند و در storage نیستند؛ ابزار genesis باید همین ۱ / ۶۰۴۸۰۰ / ۱۰۰ را از طریق getterها بخواند و بررسی کند)؛ وثیقه‌ی ثابت `entryCollateral = 500_000 ether` و `membershipFeeBps = 400`. چون helper ارث‌بر است، مقدارهای اولیهٔ scalarهای سورس (از جمله `verifier`) همراه storage استخراج می‌شوند؛ `genesisTime` را helper از آرگومان می‌نویسد و `lastPaidActivationAt` ۰ می‌ماند (جای `windowStart` که حذف شده). کل مکانیزم liveness آف‌چین است (تصمیم/تحویل/اعتراض/رأی)؛ به یادداشت معماری بالای `recordSuspension()` در `ValidatorsRegistry.sol` و `sur-tokenomics.md`/`sur-verifier-service-spec.md` مراجعه کن. **بدون** آدرس توکن — سورن ارز بومی شبکه است.
2. `ValidatorsBoard` — فهرست **دقیقاً ۵** عضو اولیه‌ی هیأت (نیازمند شبیه‌سازی با `ValidatorsBoard_GenesisSeed`). 🔶 تا زمانی که شش مؤسس دیگر فعال نشده‌اند فقط یک ولیدیتور فعال وجود دارد. ✅ تصمیم مالک ۲۰۲۶-۱۱-۱۹: عضو اولیهٔ هیأت که هنوز `Probation` است کرسی دارد ولی عمل نمی‌کند (`ValidatorsBoard._canAct` = `_hasAuthority` و وضعیت غیر از `Probation`؛ `syncBoard()` حذفش نمی‌کند)؛ پس در genesis فقط ولیدیتور اول می‌تواند عمل کند و برای اقدام هیأت (دست‌کم ۳ رأی) باید دست‌کم ۲ مؤسس دیگر را زود فعال کرد؛ `voteFor` و انتخاب ماهانه هم فقط ولیدیتور `Active` را می‌پذیرند.
3. `ValidatorsTreasury` — ✅ `perPaymentCap = 50_000 ether`، `periodCap = 200_000 ether` (مبلغ ثابت)، و `CAP_CHANGE_TIMELOCK_DELAY = 7 days` (ثابت). چون genesis فقط runtime code تزریق می‌کند، این دو slot **باید overlay شوند** (مقداردهی سورس هنگام تزریق اجرا نمی‌شود). خزانه در genesis موجودی ندارد.
4. `ValidatorsBoard` — ✅ `boardMonthId` را **حتماً** برابر ماه میلادی UTC زمان genesis (`monthIdOf(genesisTimestamp)`) و `boardVersion` را برابر ۱ نوشته و assert کن (هر دو را `ValidatorsBoard_GenesisSeed` می‌نویسد). ⚠️ بدون آن، هیأت مؤسس از لحظهٔ اول بی‌اختیار است و تا نخستین `refreshBoard` هیچ اقدامی نمی‌تواند بزند. در `ValidatorsRegistry` فقط ولیدیتور اول در seed `activationSeq = 1` می‌گیرد؛ مؤسسان بعدی هنگام `recordActivation` به ترتیب فعال‌شدن شماره می‌گیرند (شکستن تساوی هیأت با `activationSeq` است)؛ پس ترتیب ۱ تا ۷ دیگر ترتیب genesis نیست بلکه ترتیب فعال‌سازی است.
5. `BlockRewardDistributor` — ✅ `lastSettledBlock = 0` (پیش‌فرض)؛ اولین `openDistribution` (توزیع صفحه‌بندی‌شده، RD-18) باید بازه‌ی `{1, …}` بدهد. overlay لازم: `distributionOracle`، `validatorDirectShareBps` و مقدار مصوب بلاک‌ریوارد (۲ سورن).
6. `FoundationDAO` و `FoundationMembers` — نام و آدرس ۱۵ عضو اولیه‌ی بنیاد (در `FoundationMembers` با `FoundationMembers_GenesisSeed`، نیازمند شبیه‌سازی)، وزن سهم‌الشرکه‌ی هر عضو، اولین هیأت‌مدیره (۵ اصلی + ۲ علی‌البدل) و بازرس. مقدار اولیه (طبق صورت‌جلسهٔ مجمع ۱۴۰۵/۰۷/۰۱): هیأت‌مدیرهٔ اصلی: سیده مهکامه شریف‌زاد، میرسهیل نیک‌زاد کلورزی، سیاوش تفضلی، محمدحسن محمدی اردهالی، علیرضا زجاجی قمی؛ علی‌البدل: حجت عباسی، کاوه مشتاق؛ بازرس: امیرعباس امامی کورعباسلو؛ وزن سهم‌الشرکهٔ هر یک از ۱۵ عضو برابر ۵۰ میلیون ریال.
7. `GenesisClaimsVault` — فهرست طلبکاران، طلب جمع‌شده‌ی هر آدرس (کامل، شامل ۱۰۰ سورن کیف‌پول)، `genesisTimestamp` (نیازمند شبیه‌سازی با `GenesisClaimsVault_GenesisSeed`)؛ و موجودی `alloc` صندوق = `totalHeld()`.
8. `ValidatorSeatNFT` — هفت توکن صندلی مؤسسان (شناسه‌های ۱ تا ۷) با `ValidatorSeatNFT_GenesisSeed(address[] founderOwners)` (نیازمند شبیه‌سازی) **به همان ترتیب seed کردن مؤسسان در Registry** (ولیدیتور اول اول)؛ `baseURI` اولیه `https://validator-nft.surnet.org/` است (میزبان را مالک داده؛ 🔶 مسئول نگه‌داری آن مشخص نیست) و در همان storage استخراج می‌شود.
9. `IdentityRegistry` — جزئیات کامل در `sur-identity-registry-spec.md`.

## قراردادهای کمکی seed (`contracts/genesis-seed-helpers/`) — v2.5

هر شش helper خودِ قرارداد واقعی را **ارث می‌برند** و در `constructor` وضعیت بنیادین را می‌نویسند؛ ابزار genesis storage لمس‌شده را استخراج می‌کند (simulate-and-extract) و آن را همراه با runtime **قرارداد واقعی** زیر آدرس ثابت می‌گذارد:

| helper | امضای `constructor` | آنچه seed می‌شود |
|---|---|---|
| `FoundationDAO_GenesisSeed` | `(address[] principalsAndAlternates, address inspector_, address chair_, address treasurer_, address ceo_, uint256 termEnd)` | ۵ تا ۷ آدرس (۵ اصلی، سپس حداکثر ۲ علی‌البدل)؛ بازرس؛ رئیس؛ خزانه‌دار؛ مدیرعامل؛ پایان دوره؛ `boardVersion = 0` |
| `FoundationMembers_GenesisSeed` | `(address[] accounts, string[] names, PersonType[] types, address[] representatives, uint256[] shares)` | اعضای اولیه با نام، نوع شخص، نماینده و سهم‌الشرکه |
| `ValidatorsRegistry_GenesisSeed` | `(address firstOwner, address firstOperator, address[] otherFounders, uint256 genesisTimestamp)` | `genesisTime`؛ ولیدیتور اول: `Active`، اپراتور `firstOperator`، `everActivated`، `activationSeq = 1`، checkpoint فعال؛ مؤسسان دیگر: `Probation`، بدون اپراتور؛ همه `isFounder = true`، وثیقهٔ صفر، غیرپرداخت‌کننده، `periodStartedAt = genesisTimestamp` |
| `ValidatorSeatNFT_GenesisSeed` | `(address[] founderOwners)` | صندلی‌های ۱ تا n به مالکان داده‌شده؛ **همان ترتیب مؤسسان در Registry** (ولیدیتور اول اول)؛ `baseURI` اولیه هم در storage می‌آید |
| `ValidatorsBoard_GenesisSeed` | `(address[] members, uint256 genesisTimestamp)` | دقیقاً ۵ عضو اولیه؛ `boardMonthId` ماه genesis؛ `boardVersion = 1` |
| `GenesisClaimsVault_GenesisSeed` | `(address[] claimants, uint256[] claims, uint256 genesisTimestamp)` | `genesisTimestamp`؛ برای هر آدرس `held = claim − ۱۰۰ سورن`؛ `totalHeld` = مجموع `held`؛ موجودی `alloc` صندوق باید برابر `totalHeld()` باشد |

- `genesisTimestamp` باید برابر `timestamp` فایل `genesis.json` باشد.
- ✅ ورود پله‌ای در کد است: فقط اولین ولیدیتور `Active` است و شش مؤسس دیگر `Probation`اند تا `setOperator` و `recordActivation` بزنند. ترتیب `otherFounders` در Registry باید با ترتیب `founderOwners` در helper صندلی‌ها یکی باشد (ولیدیتور اول، سپس همان ترتیب).
- ✅ آزمون‌های `contracts-tests/` قراردادهای واقعی را با همین روش در آدرس‌های ثابتشان می‌گذارند.

## 🔶 اندازهٔ قراردادها: سقف ۲۴٬۵۷۶ بایت

سقف ۲۴٬۵۷۶ بایت (EIP-170) فقط برای **CREATE** اعمال می‌شود. runtime `FoundationDAO` حدود ۲۷٫۹ کیلوبایت و runtime `ValidatorsRegistry` حدود ۳۶٬۸۷۹ بایت (اندازهٔ فعلی؛ در دور اول Besu با ۳۴٬۶۰۵ بایت آزموده شد؛ از artifact آزمون Hardhat با solc 0.8.24 و optimizer 200؛ `ValidatorSeatNFT` ۵٬۷۴۵ و `BlockRewardDistributor` ۲۰٬۶۷۱ بایت و زیر سقف) است و دو قرارداد اول از این سقف گذشته‌اند. (به‌روز ۲۰۲۶-۱۱-۲۳: `ValidatorsBoard` پس از مهاجرت کرسی ۲۴٬۵۳۷ بایت است، یعنی ۳۹ بایت زیر سقف؛ در genesis تزریق می‌شود پس دیپلوی را نمی‌بندد، ولی ویرایش‌های بعدی را محدود می‌کند.) helperهای seed هم با CREATE دیپلوی می‌شوند، پس زنجیرهٔ موقتِ شبیه‌سازی باید این سقف را بردارد (مثل `allowUnlimitedContractSize` در آزمون‌ها). چون هر دو در `alloc` بلاک genesis تزریق می‌شوند (نه با CREATE)، **این سقف روی زنجیرهٔ واقعی اعمال نمی‌شود**؛ آزمون‌های Hardhat برای شبکهٔ درون‌فرایندی آن را برمی‌دارند (`allowUnlimitedContractSize` در `contracts-tests/hardhat.config.js`، چون helper با CREATE دیپلوی می‌شود). ✅ روی Besu واقعی تأیید شد (دور اول آزمون ۲.۵، ۲۰۲۶-۱۱-۱۹، BR-SIZE؛ مشتق از BG-01/02/09): `FoundationDAO` با ۲۸٬۳۶۵ بایت و `ValidatorsRegistry` با ۳۴٬۶۰۵ بایت (اندازهٔ آن دور؛ اکنون حدود ۳۶٬۸۷۹ بایت و دوباره تأیید شود) در `alloc` پذیرفته شدند و برای `eth_getCode`، فراخوانی و تراکنش‌های تغییر وضعیت کار کردند. 🔶 در ساخت production با ابزار genesis تولیدی باید دوباره تأیید شود. `SurenSale` با تراکنش عادی (CREATE) دیپلوی می‌شود و مشمول این سقف است.

### اندازهٔ runtime پس از بستهٔ تغییرهای پیش از genesis (۲۰۲۶-۱۱-۲۱؛ solc 0.8.24، optimizer 200، artifact Hardhat)

| قرارداد | پیش از | پس از |
|---|---|---|
| `ValidatorsRegistry` | ۳۶٬۸۷۹ | ۳۷٬۳۴۶ (بالای سقف CREATE از پیش؛ در `alloc` اثر ندارد) |
| `ValidatorsBoard` | ۲۰٬۳۹۷ | ۲۱٬۱۶۰ |
| `BlockRewardDistributor` | ۲۰٬۶۷۱ | ۲۳٬۰۴۶ (با صفحه‌بندی RD-18) |
| `ValidatorSeatNFT` | ۵٬۷۴۵ | ۵٬۸۷۱ |
| `KmsDirectives` (تازه) | — | ۹۵۲ |

## آزمون‌های Hardhat (v2.5)

پوشهٔ `contracts-tests/` (Hardhat 2.29.1، `solc 0.8.24`، `evmVersion paris`): `npm install` سپس `npm test`؛ هر فایل آزمون در فرایند جدا اجرا می‌شود (`run-tests.js`)؛ mockها در `contracts-tests/mocks`. **نتیجهٔ فعلی (۲۰۲۶-۱۱-۲۳): ۱۸۶ آزمون در ۲۱ فایل:** `Abort` ۸، `BlockRewardDistributor` ۴، `DeferredClaim` ۶، `EntryWindowAndFixedParams` ۶، `FoundationDAO` ۱۶، `GasPerPayee` ۱، `GenesisClaimsVault` ۵، `IdentityRegistry` ۵، `KmsDirectives` ۶، `LotteryRegistry` ۳، `OwnerEoaRule` ۴، `Pagination` ۱۲، `RateChangeGenesisFreeze` ۲، `RateChangeLimits` ۱۰، `RecoveryRemoval` ۱۴، `SeatMigration` ۸، `StandbyValidators` ۸، `SurenSale` ۱۵، `ValidatorLottery` ۱۰، `ValidatorSeatNFT` ۲۲، `ValidatorsRegistry` ۲۱ (شمارش از تعداد `it(` هر فایل). شمارش‌های تاریخ‌دار پیشین: ۱۳۶ در ۱۴ فایل (شمارش بستهٔ ۲۰۲۶-۱۱-۲۱)؛ پیش از بستهٔ تغییرها ۹۷ آزمون در ۱۰ فایل؛ ۱۳۶ در ۱۶ فایل. ⚠️ این آزمون‌ها روی EVM درون‌فرایندی Hardhat اجرا می‌شوند، **نه** روی Besu/QBFT؛ آزمون زندهٔ Besu برای ۲.۵ جدا انجام شده است (دور اول ۲۰۲۶-۱۱-۱۹؛ بخش پایان سند).

## پارامترهای قابل‌تغییر با رأی

### پارامترهای امنیتی — با رأی کامل ولیدیتورها قابل‌تغییرند
✅ **از ۲۰۲۶-۱۱-۲۳ (تصمیم مالک؛ کد `187c7dd`) فقط سه پارامتر قابل‌تغییرند:** `entryWindowSeconds`، `recoveryPeriod`، `exitCooldown` (اکثریت ولیدیتورهای `Active` هنگام ساخت پیشنهاد). `maxEntriesPerWindow` (= ۱)، `probationPeriod` (= ۷ روز) و `slashBps` (= ۱۰۰ = ۱٪) **ثابت‌اند** و کلیدهای `ParamKey` آن‌ها (۰، ۲، ۴) هنگام پیشنهاد و اعمال با «this parameter is fixed and cannot be changed» رد می‌شوند:
- ~~`maxEntriesPerWindow`~~ ثابت = ۱ — در `ValidatorsRegistry`
- ~~`probationPeriod`~~ ثابت = ۷ روز — در `ValidatorsRegistry`
- liveness روی زنجیره پارامتر ندارد: سرویس Verifier آف‌چین آن را می‌سنجد؛ فقط تصمیمات نهایی وضعیت (فعال‌سازی/تعلیق/بازگشت)، هرکدام با هش شواهد، on-chain ثبت می‌شوند.
- `recoveryPeriod` ✅ **۴۸ ساعت** (چک زمانی ساده‌ی on-chain قبل از تلاش بازگشت) — در `ValidatorsRegistry` (قابل‌تغییر)
- ~~`slashBps`~~ ثابت = ۱۰۰ (۱٪؛ مبلغ جریمه ۱۰۰٪ سوزانده می‌شود) — در `ValidatorsRegistry`
- `exitCooldown` — در `ValidatorsRegistry` (قابل‌تغییر)
- لیست دقیق ۷ ولیدیتور اولیه، **۵ عضو اولیه‌ی هیأت‌مدیره‌ی ولیدیتورها**، و ۱۵ عضو اولیه‌ی بنیاد
- آدرس اولیه‌ی کلید `verifier` (مقدار ساده، مستقیم در سورس `ValidatorsRegistry.sol` با علامت `🔶 FILL_IN`، **نه** آرگومان constructor)

### فاصله‌ی ورود (`entryWindowSeconds`) — فقط با رأی مجمع ولیدیتورها
مقدار genesis ۷ روز (حداکثر **یک** ورود پولی در هر پنجره، ثابت؛ ✅ ۲۰۲۶-۱۱-۲۳: شمارش در **فعال‌سازی** است، نه در درخواست: `requestMembership` محدودیت نرخ ندارد و متقاضی در `Probation` منتظر می‌ماند؛ `recordActivation` از Verifier با «entry window used - only one new paid validator per window» رد می‌شود اگر آخرین فعال‌سازی پولی کمتر از `entryWindowSeconds` پیش بوده؛ وضعیت: `lastPaidActivationAt` و `nextPaidActivationAllowedAt()`؛ اولین فعال‌سازی پولی هرگز به تأخیر نمی‌افتد). هر تغییر حداکثر ±۱ روز، بازه‌ی ۱ تا ۳۰ روز، حداقل ۶ ماه بین دو تغییر، و ۶ ماه اول از genesis ممنوع است. ورود شش مؤسس پس از اولین ولیدیتور و ورود برندگان لاتاری از این فاصله مستثناست.

### پارامترهای اقتصادی ورود — با رأی ۳ از ۵ هیأت‌مدیره‌ی ولیدیتورها
`entryCollateral` و `membershipFeeBps` مقدار اولیه‌ی ثابت دارند (۵۰۰٬۰۰۰ سورن / ۴٪ = ۲۰٬۰۰۰ سورن) و فقط با رأی **۳ از ۵** هیأت‌مدیره‌ی ولیدیتورها (`ValidatorsBoard.proposeSetEntryCollateral` / `proposeSetMembershipFeeBps`؛ نام‌ها همان نام کد است؛ اجرا با `Registry.setEntryCollateral` / `setMembershipFeeBps` فقط از `ValidatorsBoard`) قابل‌تغییرند:
- هر تصمیم حداکثر ±۱۰٪ نسبی؛ حدود مطلق وثیقه ۱۰۰٬۰۰۰ تا ۲٬۰۰۰٬۰۰۰ سورن؛ بازه‌ی کارمزد عضویت ۱٪ تا ۱۰٪.
- حداقل ۱۸۰ روز فاصله با تغییر قبلی؛ تایمر میان تغییر مبلغ وثیقه و تغییر درصد کارمزد مشترک است.
- فقط روی ورودی‌های بعدی اثر می‌گذارد.
دلیل: رسیدن به اجماع/اکثریت کامل بین همه‌ی ولیدیتورها هرچه شبکه بزرگ‌تر شود عملاً سخت‌تر می‌شود، در حالی که این دو پارامتر ممکن است با تغییر قیمت سورن نیاز به تعدیل داشته باشند. جزئیات کامل در `sur-blockchain-design-doc.md` بخش ۶ و `sur-smart-contracts-reference.md`.

### تغییر مقدار مصوب بلاک‌ریوارد — رأی دومجلسی
هیأت‌مدیره + دوسوم مجمع ولیدیتورها. هر تصمیم حداکثر ±۱۰٪ نسبی به **نرخ جاری مصوب** (آخرین ورودی تاریخچه حتی اگر هنوز فعال نشده؛ تا وقتی تاریخچه خالی است ۲ سورن)؛ حداقل ۱۸۰ روز بین دو تصمیم موفق (بین بلاک‌های اجرا)؛ ۱۸۰ روز اول از genesis ممنوع؛ زمان اثر یک هفته پس از تصمیم؛ کف و سقف مطلق ندارد؛ در `proposeRateChange` و دوباره در `executeRateChange` سنجیده می‌شود. اگر پاداش واقعی (پیکربندی Besu) از مقدار مصوب بیشتر باشد، `BlockRewardDistributor` فقط مقدار مصوب را تقسیم می‌کند و مازاد را فوراً می‌سوزاند (رویداد `RewardExcessBurned`، بدون سقف در هر epoch)؛ این شامل کاهش مصوبِ اعمال‌نشده هم می‌شود. ✅ سوزاندن مازاد در کد و با ۴ آزمون Hardhat آزموده شده است (Router پاداش واقعی را گزارش می‌کند و قرارداد مصوب را از `maxRewardsForRange` حساب می‌کند؛ `RewardExcessBurned`، `totalExcessBurned`)؛ ✅ روی Besu هم آزموده شد (دور اول، BG-08b: مازاد ۳۹۱ سورن فوراً به `address(0)` سوزانده شد و رویداد دقیق بود). ✅ حدود ±۱۰٪، فاصلهٔ ۱۸۰ روز و ممنوعیت ۱۸۰ روز اول تغییر ریوارد از ۲۰۲۶-۱۱-۲۳ در کد است و با آزمون Hardhat آزموده شده (`RateChangeLimits`، `RateChangeGenesisFreeze`)؛ (⟵ جایگزین‌شده؛ پیش‌تر «هنوز در `proposeRateChange` نیست» بود). کدهای `problem` ۶ (درون ۱۸۰ روز اول، یا genesis seed نشده)، ۷ (کمتر از ۱۸۰ روز از آخرین تغییر) و ۸ (بیش از ±۱۰٪) را `rateChangeStatus(id)` می‌دهد؛ ۶ و ۷ با زمان برطرف می‌شوند. خواندنی‌ها: `lastRateChangeTime`، `currentApprovedRatePerBlock()`، `earliestRateChangeTime()`.

## مدل ترکیبی استیک

هر ولیدیتور تازه‌وارد، هنگام `requestMembership()` (تابعی `payable`)، با `msg.value` دو مبلغ را هم‌زمان به‌صورت **سورن** (ارز بومی زنجیره‌ی سور، دقیقاً مثل ETH روی اتریوم — نه یک قرارداد ERC20) می‌فرستد:

1. **وثیقه (`entryCollateral`، ثابت)** — در خودِ `ValidatorsRegistry` قفل می‌ماند؛ در خروج داوطلبانه برمی‌گردد؛ در جریمه، بخش جریمه (طبق `slashBps`) سوزانده می‌شود. مال مالک صندلی (مالک NFT) است — مجمع هیچ اختیاری روی خرجش ندارد. وثیقه‌ی جریمه‌شده بازپر نمی‌شود و اخراجی بر این پایه نیست.
2. **کارمزد عضویت (`currentMembershipFee()` = وثیقه × `membershipFeeBps`)** — همان لحظه، مستقیم و غیرقابل‌برگشت به `BlockRewardDistributor` (نه `ValidatorsTreasury`) می‌رود، جایی که در epoch فی بعدی، ۱۰۰٪-به‌نسبت-بلاک (بدون سوزاندن) بین ولیدیتورهای فعال تقسیم می‌شود.

مدل ترکیبی دو هدف را همزمان می‌دهد: وثیقه‌ی شخصی معنادار برای جریمه + تزریق فوری وجه به ولیدیتورهای فعال با هر عضویت جدید.

**ورودی‌های `ValidatorsTreasury`:** تنها منبع، سهم باقی‌مانده‌ی بلاک‌ریوارد از `BlockRewardDistributor` است؛ جریمه‌ها به خزانه نمی‌آیند (سوزانده می‌شوند) و کارمزد عضویت هم نمی‌آید. چون همه‌چیز به سورن (ارز بومی) است، خزانه هیچ منطق دوگانه‌ای برای «نوع دارایی» لازم ندارد — همه‌چیز از یک منبع (`.call{value:...}`) وارد `receive()` قرارداد می‌شود.

**جریمه:** ۱۰۰٪ سوزانده می‌شود (ارسال به `address(0)`)، و فقط وقتی که مهلت اعتراض ۷۲ ساعته بدون اعتراض بگذرد یا اعتراض رد شود/مجمع جریمه را تأیید کند؛ در لحظه‌ی ثبت پرونده چیزی سوزانده نمی‌شود.

## ولیدیتورها: مالک و اپراتور

هر ولیدیتور دو کلید دارد (مالک و اپراتور؛ جزئیات در `sur-blockchain-design-doc.md` بخش ۶.۱):
- **مالک (`owner`):** ریوارد، وثیقه، برداشت، رأی در مجمع و هیأت‌مدیره، هویت، درخواست خروج، NFT، تعویض اپراتور.
- **اپراتور (`operator`):** فقط امضای بلاک؛ `getValidators()` آدرس اپراتور را برمی‌گرداند.
- تعویض اپراتور: برای ولیدیتور `Active` **دومرحله‌ای** است (✅ تصمیم ۱۱۰، ۲۰۲۶-۱۱-۱۹): مالک `proposeOperator(newOperator)` می‌زند و Verifier پس از بررسی سلامت نود تازه `confirmOperatorReady(owner, newOperator, evidenceHash)` را می‌زند (انقضای پیشنهاد ۷ روز `OPERATOR_PROPOSAL_EXPIRY`؛ لغو با `cancelOperatorChange()`؛ `setOperator` برای `Active` ریورت می‌کند)؛ `setOperator(newOperator)` فقط برای مالکِ بیرون از مجموعهٔ اجماع (`Probation`، `Demoted`، `SelfSuspended`) فوری است. نود جدید در هر دو حالت وارد چرخه‌ی بررسی سلامت آف‌چین می‌شود (معافیتی از liveness نیست). ⚠️ برای genesis: کلید `verifier` باید در genesis تنظیم و شارژ باشد، چون تعویض کلید نودِ هر ولیدیتور `Active` به تراکنش Verifier نیاز دارد؛ ثابت‌های جدید مقدار genesis ندارند (`OPERATOR_PROPOSAL_EXPIRY` ثابت کد است) و `genesis-seed-helpers` تغییری لازم ندارد. یک اپراتور برای چند مالک مجاز نیست. گم‌شدن کلید مالک (✅ ۲۰۲۶-۱۱-۲۳): `migrateIdentity` (اوراکل هویت، پس از تأیید هویت) و سپس `ValidatorsRegistry.migrateSeat(old, new)` (فقط Verifier) که کل صندلی (رکورد، وثیقه، وضعیت، اپراتور، NFT و `claimable`) را به آدرس تازهٔ همان شخص می‌برد؛ دو کلید مستقل لازم است و هیچ‌کدام به‌تنهایی صندلی را جابه‌جا نمی‌کند. آنچه آف‌چین می‌ماند: Verifier باید پس از گزارش `migrateIdentity` از Identity Service خودش `migrateSeat` را بزند؛ مؤسسِ بدون رکورد هویت از این مسیر استفاده نمی‌کند (`migratedTo` به هویت نیاز دارد).
- **ورود مؤسسان:** فقط اولین ولیدیتور در مجموعه‌ی اولیه‌ی genesis است. هر یک از شش مؤسس دیگر (وضعیت `Probation`، `isFounder`) با آدرس اتریومی خودش `setOperator` را صدا می‌زند و به شرط تأیید روشن‌بودن نود توسط Verifier (`recordActivation`، بدون انتظار دوره) وارد فهرست ولیدیتورها می‌شود (از فاصله‌ی ورود مستثناست).
- تعلیق داوطلبانه: وضعیت `SelfSuspended` با `selfSuspend()`، `requestResume()` و `recordResume` (Verifier)؛ جزئیات در سند طراحی بخش ۶.۳.

## NFT صندلی (`ValidatorSeatNFT`)

هر صندلی ولیدیتوری (از جمله ۷ مؤسس) یک توکن ERC-721 است؛ مالک توکن = مالک وثیقه. توکن‌ها در genesis برای هفت مؤسس ایجاد می‌شوند؛ ورودی‌های بعدی هنگام ورود، توکن می‌گیرند. شرایط انتقال (✅ در کد: `isFullyVerified` خریدار، نبودن سابقه‌ی ولیدیتوری، اپراتور نبودن و صندلی نداشتن خریدار، ممنوعیت انتقال در حال درخواست خروج یا با پروندهٔ جریمه‌ی باز؛ صندلیِ `Active` پس از انتقال `Active` می‌ماند (تصمیم ۲۰۲۶-۱۱-۱۹)؛ ✅ ۲۰۲۶-۱۱-۲۳: خریدار باید **پیش از انتقال** `ValidatorsRegistry.acceptSeatAgreement(seatId, agreementHash)` را با کلید خودش بزند، وگرنه انتقال ریورت می‌کند؛ پذیرش به همان صندلی بسته است و با انتقال مصرف می‌شود، هش در `seatAgreementHash(seatId)` می‌ماند و `revokeSeatAcceptance()` آن را لغو می‌کند؛ بنیاد پس از انتقال امضای جداگانه نمی‌زند (هر نسخه را یک‌بار امضا می‌کند؛ تصمیم ۱۱۱، ۲۰۲۶-۱۱-۲۴) و هیچ چیز روی زنجیره منتظر بنیاد نیست؛ `acceptSeatTransfer` و مهلت ۳ روزهٔ پیشین حذف شده‌اند)، `tokenURI` = `baseURI` + شناسه (پیشوند اولیه `https://validator-nft.surnet.org/`)، و قابلیت افزودن بازار در آینده در سند طراحی بخش ۶.۴ آمده است. چون قرارداد `constructor` ندارد، مالکان اولیه از طریق `ValidatorSeatNFT_GenesisSeed(founderOwners)` و شبیه‌سازی (بالا) seed می‌شوند.

## هیأت‌مدیره‌ی ولیدیتورها

مدل `ValidatorsBoard`:

- **۵ صندلی ثابت** (`BOARD_SIZE=5`).
- **رأی‌گیری تأییدی مستمر:** هر ولیدیتور فعالِ **هویت‌ثبت‌شده** (مالک، با کلید مالک) می‌تواند هر لحظه به حداکثر ۵ ولیدیتور فعال دیگر رأی بدهد (`voteFor`) و هر رأی را هر لحظه پس بگیرد (`unvoteFor`). بدون کاندیداتوری رسمی، بدون پنجره‌ی زمانی، بدون نصاب مشارکت.
- **`refreshBoard(address[] votersToSync)`** (permissionless) هیأت ماه میلادی جاری را می‌نشاند: در هر ماه یک‌بار موفق می‌شود (هیأت خالی: هر زمان)؛ پنج ولیدیتور فعال با بیشترین رأی هیأت می‌شوند، در تساوی ولیدیتور قدیمی‌تر (`activationSeq`)، و عضو قبلی امتیازی ندارد. هیأت ماه قبل تا نخستین `refreshBoard` ماه جدید هیچ اختیاری ندارد. اختیار عضو با درخواست خروج فوراً قطع می‌شود و جانشین (`syncBoard`/`fillVacancies`) بدون انتظار ماه بعد می‌آید؛ تعلیق ناشی از جریمه/غیرفعالی به‌تنهایی اختیار را در همان ماه قطع نمی‌کند ولی عضو معلق (از جمله در تعلیق داوطلبانه) در انتخاب ماه بعد واجد شرایط نیست؛ کمتر از ۳ عضو دارای اختیار = توقف پرداخت خزانه و چرخش کلید. عضو هیأت نمی‌تواند تعلیق داوطلبانه کند.
- **شمارنده‌های رأی:** هر نامزد یک `voteCount` افزایشی دارد که `voteFor`/`unvoteFor` و `syncVoter` به‌روزش می‌کنند؛ `ValidatorsRegistry` در هر تغییر فعال‌بودن (فعال‌سازی، تعلیق، بازگشت، تعلیق داوطلبانه، ازسرگیری، درخواست خروج) `syncVoter` را با سقف گس ۶۰۰٬۰۰۰ و بی‌صدا در صورت شکست صدا می‌زند.
- **پاک‌سازی رأی‌های کهنه:** اگر ولیدیتوری بیش از `recoveryPeriod + ۳۰ روز` پیوسته `Demoted` بماند، یا `SelfSuspended` باشد و ۳۰ روز از شروع تعلیق داوطلبانه‌اش گذشته باشد (تصمیم ۲۰۲۶-۱۱-۱۹؛ دورهٔ بازیابی ندارد چون تخلف نیست)، `clearStaleVotes(validator)` (permissionless) رأی‌های داده‌شده و گرفته‌شده‌اش را کامل پاک می‌کند تا جای رأی سایرین آزاد شود.

### چرا این مدل
رأی‌گیری تأییدی مستمر مفهوم «نصاب» یا «عزل» جدا ندارد؛ پس به نصاب اکثریتِ کل (که با بزرگ‌ترشدن شبکه سخت می‌شود) نیاز ندارد؛ همچنین مسیر عزل یک‌طرفه‌ای وجود ندارد که یک گروه کوچک هماهنگ بتواند بی‌مقاومت از آن استفاده کند.

**Trade-off:** هزینهٔ `refreshBoard` به تعداد نامزدهایی بسته است که دست‌کم یک رأی شمرده‌شده دارند، نه کل ولیدیتورها؛ هماهنگ‌سازی رأی‌ها در هر تغییر وضعیت انجام می‌شود و اگر جا نیامد، هر کسی می‌تواند با `syncVoter`/`syncVoters` یا ورودی `refreshBoard` ترمیم کند؛ اگر تعداد نامزدهای رأی‌دار به مقیاسی رسید که هزینهٔ گس این حلقه مشکل‌ساز شد، نیاز به نسخهٔ صفحه‌بندی‌شده پیدا می‌کند.

## مکانیزم liveness

liveness کاملاً آف‌چین بررسی می‌شود؛ فقط تصمیمات تغییر وضعیت روی زنجیره ثبت می‌شوند: `recordActivation` / `recordSuspension` / `recordRecovery`، هرسه فقط توسط `verifier`. کلید `verifier` **کاملاً جدا** از `identityOracle` است.
- برای `Probation`/`Demoted`/`SelfSuspended` (پس از درخواست ازسرگیری): `verifier` نود خودِ کاندیدا (کلید اپراتور) را چک می‌کند (sync-بودن). ازسرگیری از تعلیق داوطلبانه بدون دوره‌ی آزمایشی است.
- برای `Active`: `verifier` تولید واقعی بلاک (فیلد `miner`/`coinbase`، که آدرس اپراتور است) را چک می‌کند.
- پس از هر تعویض اپراتور (`setOperator`، یا `confirmOperatorReady` پس از تأیید Verifier)، نود جدید وارد همین چرخه می‌شود و از ارزیابی معاف نیست.
- آدرس/IP نودها **هرگز on-chain ثبت نمی‌شود** — فقط در همان اپ همراهِ هویت، در اختیار `verifier` (ریسک DDoS در صورت انتشار عمومی).
- ⚠️ **پیامد عملیاتی:** `verifier` هزینه‌ی گس همه‌ی تصمیم‌های وضعیت را می‌پردازد — یعنی این حساب باید همیشه موجودی کافی داشته باشد. این یک هزینه‌ی عملیاتی تازه است که در برآورد بودجه باید لحاظ شود.
- ✅ مشخصات کامل سرویس آف‌چین `verifier` (معماری، افزونگی، جداول دیتابیس، سیاست نگه‌داری داده، مانیتورینگ) در سند جداگانه‌ی `sur-verifier-service-spec.md` نوشته شده — فقط پیاده‌سازی واقعی و انتخاب سرویس‌دهنده‌ی پیامک/تلگرام باقی مانده.

## هویت — قرارداد مستقل (`IdentityRegistry`)

هویت (خوداظهاری + وریفای تلفن/تلگرام/بله/ایمیل + KYC) در قرارداد کاملاً جدا، `IdentityRegistry.sol` (آدرس `0x6666...6666`) است، چون جمعیت هدفش (کل کاربران شبکه) از جمعیت ولیدیتورها جداست. جزئیات کامل در `sur-identity-registry-spec.md`.

- **الزام ولیدیتوری:** هر ولیدیتور غیرمؤسس باید `kycVerified` باشد (فقط هنگام ورود چک می‌شود) و `Individual` (شخص حقیقی ایرانی). علاوه بر هویت، شماره تلفن، حساب تلگرام، حساب بله و ایمیل هم باید احراز شده باشد. مؤسسان اولیه (از جمله شرکت دارای دو نود) مستثنی‌اند. کل سیستم KYC فعلاً فقط برای اشخاص حقیقی ایرانی است و ممکن است بعداً توسعه یابد.
- **یکتایی:** هر شخص یک صندلی. `personKey` (HMAC کد ملی) **فقط آف‌چین** در Verifier نگه‌داری می‌شود؛ کلید HMAC فقط داخل SurKMS است (متد `kms_hmac`؛ تصمیم مالک ۲۰۲۶-۱۱-۲۱). کسی که خودش خارج شود یا در بازیابی شبکه حذف شود برای همیشه نمی‌تواند ولیدیتور شود (تنها استثنا گم‌شدن کلید مالک: `migrateIdentity` + `migrateSeat`؛ آدرس تازه خارج‌شده شمرده نمی‌شود).
- `IdentityRegistry.registerIdentity(personType, name)` — خوداظهاری؛ پیش‌نیاز رأی‌دادن در `ValidatorsBoard` (که `IdentityRegistry.hasIdentity(...)` را چک می‌کند).
- `setPhoneVerified`/`setTelegramVerified`/`setBaleVerified`/`setEmailVerified`/`setKycVerified` — فقط `identityOracle` (مقدار اولیه مستقیم در سورس `IdentityRegistry.sol` با علامت `🔶 FILL_IN`).
- **تفاوت با `verifier`:** چرخش `identityOracle` دست **`FoundationDAO`** است (از طریق پیشنهاد تایپ‌شدهٔ `RotateIdentityOracle`)، نه هیأت‌مدیره‌ی ولیدیتورها — چون احراز هویت یک مسئولیت بنیاد است، نه امنیت شبکه. سیستم eKYC را کمیته‌ی فنی بنیاد راه می‌برد ولی در عمل مستقل عمل می‌کند؛ هزینه‌ی KYC با متقاضی است.
- ✅ (کد و آزمون Hardhat) `getVerificationStatus(who)` شش مقدار بولی به این ترتیب برمی‌گرداند: ثبت‌شده، تلفن، تلگرام، بله، ایمیل، KYC؛ و `isFullyVerified(who)` فقط برای شخص **حقیقی** ثبت‌شده با هر پنج احراز (KYC، تلفن، تلگرام، بله، ایمیل) `true` است. همهٔ توابع ثبت احراز (تلفن، تلگرام، بله، ایمیل، KYC) برای شخص حقوقی (`Legal`) revert می‌کنند (🔶 نهایی‌بودن این سیاست باز است)؛ `migrateIdentity` پرچم‌های بله/ایمیل را هم منتقل می‌کند.
- `setKycVerified` نتیجه‌ی eKYC کامل (تصویر+کارت‌ملی+تطبیق چهره، جایگزین دفترخانه‌ی اسناد رسمی طبق استاندارد SIP001) را ثبت می‌کند؛ داده‌ی خام هرگز on-chain نمی‌رود، فقط یک فلگ بولی + یک commitment برای اثبات عدم‌دستکاری در دعاوی حقوقی.
- نام (نه شماره/آیدی/مدارک KYC) روی زنجیره‌ی عمومی و دائمی باقی می‌ماند — عمداً پذیرفته‌شده (شفافیت مدنظر است).
- نسخهٔ اولیهٔ سامانهٔ احراز هویت باید از روز اول (پیش از ورود اولین ولیدیتور غیرمؤسس) آماده باشد.
- فیلتر تراکنش بر پایه‌ی احراز هویت در لایهٔ شبکه یا ماینر وجود ندارد؛ کنترل در سطح دپ‌ها اعمال می‌شود.

⚠️ `ValidatorsRegistry.verifier` فقط تصمیمات نهایی تغییر وضعیت را گزارش می‌کند: `recordActivation`/`recordSuspension`/`recordRecovery`؛ کاملاً جدا از `identityOracle`.

## آنچه روی زنجیره برای liveness باقی مانده

جزئیات معماری (بسته‌ی شواهد، هش on-chain، مکانیزم تحویل/اعتراض/رأی) در یادداشت معماری بالای `recordSuspension()` در `ValidatorsRegistry.sol`، و در `sur-tokenomics.md`/`sur-verifier-service-spec.md`. خلاصه:

- `probationPeriod = 1 هفته` و `recoveryPeriod = 48 ساعت` — هردو صرفاً چک زمانی ساده‌ی on-chain قبل از این‌که Verifier بتواند `recordActivation`/`recordRecovery` را با موفقیت صدا بزند.
- نسبت موفقیت ۹۵٪ کاملاً آف‌چین محاسبه می‌شود و فقط هش نتیجه‌اش روی زنجیره می‌رود.
- تعلیق (`recordSuspension`) بلافاصله و بدون‌قید از لیست فعال حذف می‌کند؛ تصمیم جریمه از یک زنجیره‌ی جداگانه (چک رخداد جمعی → تحویل → پنجره‌ی اعتراض ۷۲ساعته → رأی مجمع در صورت اعتراض → سوزاندن) می‌گذرد.
- `STALE_VOTE_CLEAR_DELAY = 30 روز` (در `ValidatorsBoard`، `constant`) — پاک‌سازی رأی‌های یک ولیدیتور معلق فقط بعد از `demotedAt + 48 ساعت + 30 روز` ممکن است.
- 🔶 چند پارامتر زمانی هنوز placeholder‌اند، نه تصمیم نهایی: `DELIVERY_DISPUTE_GRACE_PERIOD`, `APPEAL_FILING_WINDOW`, `APPEAL_VOTING_PERIOD`.

## حکمرانی بنیاد — `FoundationDAO` و `FoundationMembers`

- ✅ **موجودی اولیه‌ی genesis:** ردیف‌های جدول «تخصیص سورن در alloc» بالا. موجودی `FoundationDAO` (`0x1111...1111`) ۲۰٬۰۰۰٬۰۰۰ سورن است (توسعه/اکوسیستم، موضوع فعالیت بنیاد، ماده ۳ اساسنامه، و تصمیم پروژه برای تخصیص ۲۰ میلیون سورن)؛ طلب‌های ردیف ۲ و ۳ در `GenesisClaimsVault`اند، نه در کیف‌پول افراد و نه در `FoundationDAO`.
- ✅ **`FoundationDAO` مطابق اساس‌نامه:** مجمع عمومی (وزن رأی = سهم‌الشرکه)، هیأت‌مدیره (۵ اصلی + ۲ علی‌البدل، دوره‌ی ۲ سال، تا انتخاب هیأت جدید مأموریت دارد)، بازرس (۱ نفر، دوره‌ی ۲ سال، می‌تواند خارج از بنیاد باشد). هر رأی‌دهنده برای هیأت‌مدیره به ۵ نفر و برای بازرس به ۱ نفر رأی می‌دهد؛ ۵ نفر پررأی اصلی، دو نفر بعدی علی‌البدل. مجمع عادی با حضور بیش از نصف سهم‌الشرکه رسمیت می‌یابد و اگر بار اول نصاب نرسید، بار دوم با نصاب اساس‌نامه (بیش از یک‌سوم)؛ مجمع فوق‌العاده (انتقال سهم، خروج یا ورود عضو) هم همین نصاب‌ها را دارد، ولی تصمیم آن سه‌چهارم **کل** سهم‌الشرکه **و** اکثریت عددی **همهٔ** اعضا را می‌خواهد (🔶 خوانش سخت‌گیرانهٔ ماده ۱۸ اساس‌نامه: در برابر همهٔ سهم‌ها و همهٔ اعضا سنجیده می‌شود، نه فقط حاضران). دعوت مجمع (`callAssembly(kind, meetingTime, agendaURI)`) با رئیس هیأت‌مدیره یا بازرس، ۱۰ تا ۴۰ روز قبل از جلسه؛ سهم‌ها در لحظهٔ دعوت منجمد می‌شوند؛ مجمع دوم برای نصاب پایین‌تر با `callSecondSession(prevId, …)` و فقط یک بار برای هر مجمع ناموفق. رأی‌گیری تا ۳ روز پس از زمان جلسه باز است (🔶 `VOTING_PERIOD`؛ اساس‌نامه آن را نگفته). انتخابات با شناسهٔ مجمع (`proposeBoardElection`، `voteBoard(id, address[5])`، `voteInspector`، `finalizeElection`)؛ بازرس نمی‌تواند عضو جدید هیأت یا مدیرعامل باشد؛ با تغییر هیأت، رئیس/خزانه‌دار که دیگر عضو هیأت نیستند صفر می‌شوند. تغییر دفتر اعضا با `proposeMembersResolution`/`voteResolution`/`executeResolution` فقط در مجمع فوق‌العاده است، نه با رأی هیأت. هیأت‌مدیره هر زمان با اکثریت آرای اعضای اصلی، رئیس هیأت‌مدیره و خزانه‌دار (از اعضای هیأت) و مدیرعامل (می‌تواند خارج از هیأت و بنیاد باشد) را انتخاب می‌کند (`proposeElectOfficers`).
- ✅ **خرج خزانه:** سورن و ERC20، با تصویب اکثریت عددی اعضای هیأت‌مدیره (۳ از ۵) در هر زمان، **بدون هیچ سقفی** (`proposeSpend`؛ رأی با `vote(id, paramsHash)`؛ تابع `voteSpend` دیگر وجود ندارد). همه‌ی مراحل انتخاب و پرداخت در قرارداد پیاده شده است.
- ✅ **پیشنهادهای هیأت (تصمیم ۱۰۴، اصلاح‌شده با تصمیم ۱۰۸):** هر تصمیم هیأت یکی از **۱۴ نوع** ثابت است: `Spend`، `ElectOfficers`، `RegisterExchange`، `SetExchangeQuota`، `ChangeExchangeKey`، `ResumeExchange`، `RemoveExchange`، `SetSaleTotalCap`، `SweepUnsold`، `RotateIdentityOracle`، `StartLottery`، `SetSaleContract`، `Execute`، `EndSale` (توابع `proposeSpend`، `proposeElectOfficers`، … `proposeExecute`). اجرای **پنهان یا بی‌نوع** وجود ندارد؛ اجرای آزاد فقط همان نوع `Execute` است (`target`، `value`، `data`، `description` به‌صورت آشکار ذخیره و با `getProposal` خواندنی؛ هدف‌های ممنوع: خود `FoundationDAO` و `FoundationMembers`؛ همان نصاب ۳ از ۵؛ ارسال `value` مجاز). رأی‌دهنده `paramsHash` را می‌دهد؛ رأی پیشنهاددهنده خودکار شمرده می‌شود (✅)؛ انقضا ۳۰ روز؛ تغییر ترکیب هیأت (`boardVersion`) پیشنهادهای باز را باطل می‌کند. افزودن نوع تازه نسخهٔ تازهٔ قرارداد می‌خواهد. اولین هیأت‌مدیره و اعضای بنیاد در مقدار اولیه‌ی قرارداد (genesis) هستند.
- ✅ **`FoundationMembers`:** حساب اعضای بنیاد را نگه می‌دارد و قراردادهای دیگر از آن می‌خوانند؛ فقط `FoundationDAO` (با تصمیم مجمع فوق‌العاده) آن را عوض می‌کند. (کد و آزمون Hardhat)
- ✅ **هیأت‌مدیره‌ی بنیاد** سهمیه‌ی هر صرافی و سقف کل فروش، بودجه‌ی هر کمیته و مجری لاتاری (`ValidatorLottery`) را تعیین می‌کند. مسیر بودجه‌ی مستقیم از `ValidatorsTreasury` به بنیاد وجود ندارد؛ در `ValidatorsTreasury` تنها مسیر خرج `boardApproveExpenditure` از ValidatorsBoard است، محدود به `perPaymentCap` و `periodCap`؛ هیأت می‌تواند به هر گیرنده‌ای (از جمله آدرس بنیاد) در همین سقف‌ها پرداخت کند. برای هزینه‌ی جاری بنیاد، کانال خودکار ۱۵٪ ثابت از **کل** بلاک‌ریوارد در `BlockRewardDistributor.sol` وجود دارد.
- ✅ **هم‌پوشانی عضویت صریحاً مجاز است:** یک نفر می‌تواند هم‌زمان عضو بنیاد، ولیدیتور شبکه، و عضو هیأت‌مدیره‌ی ولیدیتورها باشد. هیچ‌جای کد این هم‌پوشانی را چک نمی‌کند.
- ✅ این بازطراحی در `contracts/` پیاده و با ۱۶ آزمون Hardhat (`FoundationDAO.test.js`؛ روی EVM درون‌فرایندی) آزموده شده است؛ روی Besu فقط `Spend` و `Execute` با ۳ از ۵ در دور اول ۲.۵ آزموده شد (BG-09)؛ seed آن (اعضا، وزن‌ها، هیأت اولیه) با helperهای ارث‌بر انجام می‌شود (بخش «قراردادهای کمکی seed»). 🔶 runtime این قرارداد حدود ۲۷٫۹ کیلوبایت است (بخش «اندازهٔ قراردادها»).

## لاتاری ولیدیتور (`ValidatorLottery`)

مجری: هیأت‌مدیره‌ی بنیاد؛ حداقل یک سال فاصله بین دو لاتاری؛ مبلغ بلیط و تعداد برندگان با مجری؛ مجری می‌تواند برگزار نکند؛ اجرا توسط قرارداد هوشمند با commit–reveal مدیرعامل و `blockhash`؛ ۵ عضو اصلی هیأت و مدیرعامل نمی‌توانند بلیط بخرند؛ آغاز با پیشنهاد تایپ‌شدهٔ `StartLottery`؛ شرکت‌کنندگان باید در سیستم احراز هویت تأیید شده باشند؛ مبلغ بلیط تا پایان قرعه‌کشی در قرارداد و سپس یک‌جا به خزانهٔ بنیاد (`FoundationDAO`؛ در لغو بازپرداخت با `claimRefund`)؛ برندگان وثیقه نمی‌دهند؛ رأی برندگان فوری اعمال می‌شود ولی نودها و شرایط نودشان باید راستی‌آزمایی و توافق‌نامه امضا شود؛ ورودشان تابع فاصله‌ی ورود نیست. ✅ طراحی قرعه‌کشی نهایی است (تصمیم ۱۰۷). ✅ کد نوشته و با ۱۰ آزمون Hardhat (`ValidatorLottery.test.js`، به‌علاوهٔ ۳ آزمون یکپارچگی با Registry در `LotteryRegistry.test.js`؛ روی EVM درون‌فرایندی) آزموده شده است؛ روی Besu با بلاک واقعی هم گذشت (دور اول ۲.۵: BG-10، BG-10b، BG-10-BH). هر آدرس یک بلیط می‌خرد و سقفی برای تعداد شرکت‌کنندگان نیست؛ ورود برنده با `try/catch` به `ValidatorsRegistry.enterAsLotteryWinner` انجام می‌شود، پس رد شدن توسط Registry هرگز قرعه را متوقف نمی‌کند و در `entryFailed` ثبت می‌شود؛ برنده صندلی `Probation` بدون وثیقه و کارمزد می‌گیرد و جزو نرخ ورود پرداخت‌کننده‌ها شمرده نمی‌شود.

## توکن استیک: سورن، ارز بومی شبکه (نه یک قرارداد)

طبق تصمیم پروژه (در چارچوب موضوع فعالیت بنیاد، ماده ۳ اساسنامه)، توکن پایه‌ی شبکه‌ی سور «**سورن**» نام دارد — **ارز بومی/native خودِ زنجیره است، دقیقاً مثل ETH روی اتریوم**، نه یک قرارداد ERC20. بنابراین:
- `ValidatorsRegistry` هیچ آدرس توکنی ندارد؛ `requestMembership()` تابعی `payable` است و مستقیماً با `msg.value` سورن می‌گیرد.
- `ValidatorsTreasury` هم فقط سورن نگه می‌دارد، بدون هیچ منطق دوگانه‌ای برای «نوع دارایی».
- هیچ قرارداد جداگانه‌ای برای «توکن سورن» لازم نیست و نباید در `SurAddresses.sol` یا هرجای دیگر آدرسی برایش رزرو شود.
- توزیع اولیه‌ی سورن توسط بنیاد (موضوع فعالیت بنیاد، ماده ۳، و تصمیم پروژه) از طریق تخصیص موجودی سورن به آدرس `FoundationDAO` در genesis alloc انجام می‌شود.

## فروش سورن

فروش در دوره‌ی قیمت ثابت و دوره‌ی گذار فقط از طریق صرافی‌های رمزارزی مجاز (دارای مجوز و مشتری مستقیم) انجام می‌شود: صرافی ریال/تومان را به قیمتی که قرارداد هوشمند (`SurenSale`) تعیین می‌کند از مشتری می‌گیرد و دستور واریز سورن به حساب مشتری را به قرارداد می‌دهد؛ صرافی کارمزد خودش را برمی‌دارد. سهمیه‌ی هر صرافی و سقف کل را هیأت‌مدیره‌ی بنیاد با پیشنهادهای نوع‌دار (۳ از ۵) تعیین می‌کند؛ سقف کل (`totalCap`) در ابتدا **صفر** است، پس تا تعیین آن توسط هیأت **هیچ فروشی انجام نمی‌شود**. ثبت صرافی (`registerExchange`) ۱۰۰ سورن «سپردهٔ گس» از موجودی خودِ قرارداد برای حساب صرافی می‌فرستد (خارج از سهمیه؛ موجودی قرارداد باید دست‌کم ۱۰۰ باشد) و سهمیه کل سورن مجاز صرافی است، شامل آنچه پیش‌تر فروخته. فروش فقط با `sellTo(customer, tomanAmount, minSurenOut, orderRef)`؛ شناسهٔ سفارش (`orderRef`) برای هر صرافی یکتاست. دوره‌ی قیمت ثابت ۹۰ روز (۱۰۰، ۱۰۵ و ۱۱۰ تومان در هر ۳۰ روز) و سپس دوره‌ی گذار ۴۵ روزه (±۰٫۵٪ روزانه، کف ۹۰ و سقف ۱۵۰ تومان؛ قیمت شروع گذار آخرین قیمت دورهٔ ثابت است؛ ✅ ۲۰۲۶-۱۱-۲۳: قیمت گذار **همیشه** در بازهٔ ۹۰ تا ۱۵۰ قید می‌شود: مقدار آغازین (اگر قیمت تمدید مدیرعامل بیرون بازه باشد، از نزدیک‌ترین سر بازه) و پس از هر گام روزانه، از جمله روز صفر و روزهای خنثی؛ `currentPriceMilliToman()` مقدار آغازین را هم قید می‌کند). مدیرعامل بدون سقف تعداد می‌تواند دورهٔ ثابت را با `extendFixedPeriod(extraDays, priceToman)` (قیمت تومان کامل دقیقاً برای روزهای افزوده؛ فقط پیش از پایان دورهٔ ثابت؛ سپر اشتباه تایپی ۳۶۵۰ روز در هر فراخوان) و دورهٔ گذار را با `extendTransition(extraDays)` (فقط پیش از پایان گذار؛ همان قاعدهٔ حجم روزانه ادامه می‌یابد) تمدید کند. فروش را با نوع `EndSale` هیأت برای همیشه می‌توان متوقف کرد؛ `sweepUnsold(to)` فقط وقتی `isSaleOver()` برقرار است (پایان با تصمیم بنیاد، یا گذشتن پایان دورهٔ گذار)، و این تعریف «پایان رسمی» را می‌بندد. `SurenSale` در genesis نیست و با تراکنش عادی دیپلوی می‌شود و آدرسش با نوع `SetSaleContract` به `FoundationDAO` معرفی می‌شود؛ جزئیات در `sur-smart-contracts-reference.md` و `sur-tokenomics.md`. اوراکل پرداخت وجود ندارد (`paymentOracle`/`reportPayment` حذف شده‌اند). ✅ کد و ۱۵ آزمون Hardhat (`SurenSale.test.js`؛ شمارش ۲۰۲۶-۱۱-۲۳؛ روی EVM درون‌فرایندی، نه Besu).

## چیزی که عمداً پیاده‌سازی نشد

«هماهنگی واکنش اضطراری برای اقدامات فاجعه‌بار» به‌صورت یک تابع on-chain در `ValidatorsBoard` پیاده نشده — چون باید نیازمند رأی بالاتر از ولیدیتورها باشد، نه یک اختیار هیأت. اگر منظور یک مکانیزم مشخص‌تر (مثلاً pause کردن توزیع پاداش) باشد، باید جداگانه طراحی و اضافه شود. ⏸️ بلوکه‌کردن یک حساب در نودهای ولیدیتوری هم فعلاً تأیید نشده است ولی زیرساخت نباید مانع آن در آینده شود.

## ✅ تصمیم کامپایل: بدون `viaIR`

- **چرا مهمه:** `viaIR` مشکل خطای کامپایل «Stack too deep» را حل می‌کند، ولی بایت‌کدی که تولید می‌کند با بایت‌کد پایپ‌لاین پیش‌فرض کاملاً متفاوت است.
- ⚠️ طبق گزارش باگ رسمی Blockscout (GitHub issue #631، «Blockscout can not verify contracts which require via-ir»)، این اکسپلورر (و حتی Etherscan/Foundry در برخی موارد) نمی‌تواند قراردادهایی را که به `viaIR` نیاز دارند وریفای کند.
- ✅ همه‌ی قراردادهای genesis و `SurenSale.sol` باید با پایپ‌لاین پیش‌فرض (بدون `viaIR`) و با `solc 0.8.24` و optimizer فعال (تنظیمات production) کامپایل شوند. «Stack too deep» فقط با کامپایل واقعی قابل راستی‌آزمایی است، نه استدلال نظری: توابع بزرگ (مثل توزیع پاداش که اکنون به `openDistribution` و `payPage` و `closeDistribution` تقسیم شده است) باید با ساختارهای حافظه (`struct` مثل `EpochPrep`) و توابع کمکی تقسیم شوند. هر نسخه‌ی تازه (از جمله قراردادهای ۲.۵) باید هم بدون optimizer و هم با آن کامپایل تمیز بدهد.
- 📎 گس: طبق مستندات رسمی Solidity، `viaIR` معمولاً گس را **کاهش** می‌دهد؛ پس این تصمیم صرفاً برای سازگاری وریفای است.

## نتایج دور اول آزمون Besu برای ۲.۵ (۲۰۲۶-۱۱-۱۹)

✅ شواهد: `testing-evidence/besu-live-test-v25-2026-11-19/` (REPORT، FINDINGS، DEVIATIONS، LIMITATIONS؛ ۲۲ فایل نتیجه). Besu 26.9.0 در Docker، QBFT حالت قرارداد، بلاک ۲ ثانیه، فورک‌ها تا London از بلاک ۰ با `zeroBaseFee`، یک میزبان، اجراهای کوتاه. **آمادگی production اعلام نمی‌شود.**

- ✅ genesis با قراردادهای ساختاری تزریق‌شده از بلاک ۱ بالا آمد؛ `getValidators()` کلیدهای **اپراتور** را داد و با `qbft_getValidatorsByBlockNumber` برابر بود (BG-01)؛ ورود مؤسسان تا ۷ ولیدیتور با `setOperator` و `recordActivation` (مؤسس در `Probation` است و `setOperator` برایش فوری می‌ماند)؛ حتی چند ولیدیتور در یک بلاک (BG-02، BG-12). ⚠️ BG-03 (تعویض فوریِ اپراتور، از جمله به نود خاموش) قاعدهٔ قدیمی برای ولیدیتور `Active` را آزمود؛ تعویض دومرحله‌ای (`proposeOperator`/`confirmOperatorReady`) باید روی Besu دوباره اجرا شود (نتیجه‌ای هنوز ثبت نشده).
- ✅ `FoundationDAO` (۲۸٬۳۶۵ بایت) و `ValidatorsRegistry` (۳۴٬۶۰۵ بایت در دور اول؛ اندازهٔ فعلی حدود ۳۶٬۸۷۹) در `alloc` کار کردند (BR-SIZE؛ مشتق).
- ⚠️ تفاوت‌های آزمایشی که ابزار production نباید ببرد: سه آدرس اوراکل (`verifier`، `distributionOracle`، `identityOracle`) در storage با آدرس کلید آزمایشی جایگزین شدند چون کلید آدرس‌های `SurAddresses` معلوم نیست (D-2)؛ در یک شبکهٔ جدا چهار متغیر زمانی Registry کوتاه شد (D-3)؛ یک شبکه پاداش ۳ سورن در برابر مصوب ۲ داشت تا «واقعی > مصوب» ساخته شود (D-4)؛ bytecode با `evmVersion` paris و فورک London (D-6)؛ heap نودها در Docker کوچک بود (D-1).
- ✅ F-4 (انتساب بلاک‌های پیش از انتقال صندلی): تصمیم مالک ۲۰۲۶-۱۱-۱۹ = بازپخش رویدادهای `SeatTransferred`، `OperatorSet` و `OperatorChangeConfirmed` در RewardRouter از genesis (بدون رکورد تاریخچهٔ مالک روی زنجیره)؛ ✅ BG-06 قاعدهٔ قبلی انتقال را آزمود و دور 1b (BH-06A/BH-06B) قاعدهٔ فعلی را دوباره اجرا کرد و گذشت.
- 🔶 F-2: در حالت `contract` فهرست ولیدیتور در `extraData` سرایند خالی است؛ ابزارها از `qbft_getValidatorsByBlockNumber` یا قرارداد بخوانند.
- 🔶 F-1: لاگ Besu گاهی `IllegalStateException: Failed validator smart contract call` ثبت کرد (۸ بار در حدود ۱٬۱۰۰ بلاک روی شبکهٔ چندولیدیتوری؛ احتمالاً رقابت بین import بلاک و پردازشگر پیام BFT؛ هر بار یک پیام BFT از دست رفت و فاصلهٔ بلاک‌ها بیش از ۲ ثانیه نشد). پایش لاگ و بررسی یا ثبت مسئله در Besu پیش از mainnet لازم است.
- ⚠️ F-5: یک نود خاموش نوبت خودش را ۱۲ ثانیه دور تغییر می‌کند (`requesttimeoutseconds=10`)؛ `setOperator` به نودی که روشن نیست پذیرفته می‌شد و زمان بلاک را بی‌صدا کند می‌کرد؛ ✅ برای ولیدیتور `Active` اکنون دومرحله‌ای است (`proposeOperator` و تأیید Verifier با `confirmOperatorReady`؛ تصمیم ۱۱۰؛ در کد و آزمون Hardhat) و مسیر جدید باید روی Besu دوباره آزموده شود؛ خاموشیِ بعد از تأیید همچنان همین اثر را دارد. F-6: بازیابی پس از توقف زیر نصاب ۸۳ ثانیه طول کشید. F-7: `reveal` لاتاری باید در بلاکی تا `target+250` استخراج شود. F-8: `--sync-min-peers` در حالت FULL sync نادیده گرفته می‌شود و نود تک‌ولیدیتوری «Waiting for 5 peers» را لاگ می‌کند ولی عادی بلاک می‌زند.
- 🔶 اجرانشده: هر تایمر ۷۲ ساعت و بیشتر (قفل ۹۰ روزهٔ وثیقه و `requestExit` پس از آن، انقضای ۷روزه و ارجاع به ولیدیتورها، دورهٔ آزمایشی ۷ روزه و مهلت ورود ۷ روزه با مقدار واقعی)، آزادسازی ماهانهٔ صندوق طلب‌ها (۲۴ قسط و باقی‌ماندهٔ قسط آخر)، `recordSuspension`، رخداد جمعی، جریمه، اعتراض و `recordRecovery`، لاتاری دوم (قاعدهٔ ۳۶۵ روز)، تازه‌سازی ماهانهٔ هیأت، حکمرانی نرخ ریوارد، گذار Shanghai/Cancun (این دور فقط London بود؛ توقف دور ششم روی آن ژنزیس در `governance/sur-emergency-consensus-recovery.md` همچنان ❌🔶 باز است)، `SurenSale`، `ServiceStaking` و خرج خزانه.

## نتایج آزمون Besu روی کد پایه‌ی ۲.۲ (سپتامبر و اکتبر ۲۰۲۶)

🔶 **این بخش فقط به کد پایه‌ی ۲.۲ مربوط است؛ نتایج ۲.۵ در بخش «نتایج دور اول آزمون Besu برای ۲.۵» بالاتر آمده‌اند.** شواهد: `testing-evidence/besu-live-test-v4-2026-10-03/`؛ دامنه و تفکیک انواع شاهد در بخش «نتایج آزمون Besu دور v4» در `technical-design/sur-audit-2026-09-30-final-status.md`. **آمادگی production اعلام نمی‌شود.**

- ✅ **تزریق genesis واقعاً کار می‌کند:** هر شش قرارداد پایه با code و storage مستقیم در `alloc` روی Besu ۲۶.۹.۰ (شبکه‌ی ۴+۱ نود، ساخته‌شده روی ویندوز) کار کرد؛ هش `eth_getCode` با خروجی کامپایل برابر بود. **A14:** در ۲۰ genesis هیچ حساب یا slot ناخواسته‌ای نبود و ریشهٔ state بلاک ۰ در ۲۱ شبکه با ریشهٔ محاسبه‌شده از alloc برابر بود.
- ✅ **`qbft.validatorcontractaddress` واقعاً `getValidators()` را برای انتخاب پیشنهاددهنده‌ی بلاک می‌خواند:** چرخش round-robin بین ولیدیتورهای seed‌شده، بلوک‌به‌بلوک تأیید شد.
- ✅ **فعال‌سازی on-chain یک پیشنهاددهنده‌ی QBFT واقعی می‌سازد** و **تعلیق بلافاصله نصاب QBFT را تطبیق می‌دهد.** ⚠️ تعداد ولیدیتور هرگز به زیر نصاب BFT نرسید؛ رفتار شبکه در زیر نصاب در این دور آزموده نشده بود (برای ۲.۵ در دور اول، BG-13، آزموده شد).
- ✅ **جریان کامل تحویل→بی‌اعتراض→جریمه‌ی خودکار با زمان واقعی کار کرد.** ⚠️ ولیدیتورِ جریمه‌شده یک مؤسس با وثیقه‌ی صفر بود؛ اثر مالی جریمه روی یک عضو پرداخت‌کننده‌ی واقعی (و سوزاندن آن) آزموده نشده است.
- ✅ رأی‌گیری هیأت‌مدیره و پرداخت خزانه با تراکنش‌های واقعی تأیید شد.
- **`transitions.qbft` برای پاداش:** در genesis حالت Shanghai/Cancun کلید `block` یک timestamp (ثانیه‌ی یونیکس) است و باید دقیقاً برابر «زمان اثر» مصوب باشد؛ تغییر فایل genesis فقط با ری‌استارت اثر دارد؛ همهٔ نودها (از جمله تازه‌وارد) باید پیش از آن زمان transition را داشته باشند، وگرنه در بلاک گذار با `World State Root does not match expected value` رد می‌شوند (حالت London با شماره بلاک و Shanghai/Cancun با timestamp در دور ششم روی Besu ۲۶.۹.۰ تأیید شد؛ پاداش دقیقاً در نخستین بلاکِ `timestamp ≥ کلید` عوض می‌شود). پس از رسیدن به زمان اثر، اوراکل ارتفاع واقعی شروع را گواهی می‌کند (`certifyRateStart`؛ 🔶 نیاز به آن در ۲٫۵؟). رویهٔ اپراتوری **تصمیم باز** است (Router بخش ۱۰.۳).
- **نود با genesis ناهماهنگ:** همان بلاک نامعتبر را مدام تکرار می‌کند (۱٬۱۱۱ بار در حدود ۳۶ دقیقه) و روی ارتفاع قبلی می‌ماند. با heap پیش‌فرض (۷٫۹۴ گیگابایت) حافظهٔ فرایند ظرف حدود ۲ دقیقه به ≈۷٫۵ گیگابایت رسید و در حدود ۳۶ دقیقه OOM مشاهده نشد؛ عدم نشت اثبات‌شده نیست. اسکریپت راه‌انداز Besu گزینهٔ `-XX:+ExitOnOutOfMemoryError` را دارد. توصیهٔ heap و هشدار «نود روی ارتفاع N گیر کرده» **تصمیم باز** است.
- **پنجرهٔ state:** خارج از حدود ۵۱۲ بلاک اخیر، پرس‌وجوی state یا `trace_block` بی‌خطا `null` / `[]` برمی‌گرداند (Router بخش ۱۰.۴).
- **ابزار:** `debug_storageRangeAt` و `debug_accountRange` روی نود Bonsai خروجی خالی دادند.
- **`boardMonthId` و `boardVersion`:** ابزار production باید آن را برابر ماه میلادی زمان genesis بنویسد و assert کند (الزام موجود)؛ ابزار production هنوز پیاده نشده.
- **تراکنش با موجودی ناکافی برای هزینهٔ پیش‌پرداخت (`gasLimit × gasPrice`):** در آزمون یک بار بی‌صدا در pool ماند؛ برای اوراکل بررسی موجودی پیش از ارسال و هشدار «تراکنش مدت‌ها pending» لازم است (تصمیم باز).
- 🔶 **باگ زیرساختی مستقل از قرارداد:** روی Besu ۲۶.۹.۰ نسخه‌ی ویندوز، `--bootnodes` (هم CLI هم TOML) با هر enode URL خطای `Illegal char <:> at index 5` می‌دهد؛ راه‌حل: `static-nodes.json` به‌جای `--bootnodes`.

## موارد باز مخصوص نسخهٔ ۲.۵

- ✅🔶 آزمون Besu برای نسخهٔ ۲.۵: دور اول انجام شد؛ ورود پله‌ای شش مؤسس با `getValidators` روی کلید اپراتور، seed چهار قرارداد تازه، سوزاندن مازاد پاداش و انتقال NFT صندلی (BG-06 با قاعدهٔ قبلی؛ «صندلی فعال فعال می‌ماند» در دور 1b با BH-06A/BH-06B دوباره اجرا شد و گذشت) گذشتند (بخش «نتایج دور اول آزمون Besu برای ۲.۵»). 🔶 آزادسازی ماهانهٔ صندوق طلب‌ها و سوزاندن جریمه (اعتراض/جریمه) روی Besu اجرا نشد.
- 🔶 تثبیت آدرس پنج قرارداد تازه (در `SurAddresses.sol` پیشنهاد شده‌اند: `0x7777…7777`، `0x8888…8888`، `0x9999…9999`، `0xaAaA…aAaA`، `0xbBbB…bBbB`)؛ به‌روزرسانی ابزار genesis برای seed آن‌ها و تخصیص ۱۰۰ سورن گس به هر طلبکار.
- 🔶 اندازهٔ runtime بزرگ‌تر از ۲۴٬۵۷۶ بایت برای `FoundationDAO` (~۲۷٫۹ KB) و `ValidatorsRegistry` (اندازهٔ فعلی حدود ۳۶٬۸۷۹ بایت؛ ۳۴٬۶۰۵ بایت در دور اول) در `alloc`: ✅ روی Besu واقعی تأیید شد (دور اول ۲۰۲۶-۱۱-۱۹، BR-SIZE؛ `FoundationDAO` ۲۸٬۳۶۵ بایت)؛ 🔶 در ساخت production دوباره تأیید شود.
- ✅ وضعیت جاری (۲۰۲۶-۱۱-۲۳؛ جایگزین بند «هنوز نوشته نشده‌اند: RewardRouter، ابزار genesis و حدود تغییر ریوارد»): `RewardRouter`، Verifier، SurKMS، Identity Service، `GenesisBuilder`، NodeCheck و EventIndexer ساخته و روی Besu آزموده شده‌اند؛ حدود تغییر ریوارد (±۱۰٪ نسبی، ۱۸۰ روز فاصله، ۱۸۰ روز اول ممنوع) در کد و آزمون Hardhat است. ساخته نشده‌اند: ابزار بازیابی، گزارش عرضه، یکپارچگی صرافی و رابط لاتاری. هستهٔ Registry/Board، `ValidatorSeatNFT` و سوزاندن مازاد پاداش روی Hardhat و در دور اول آزمون Besu آزموده شده‌اند.
- 🔶 کار باقی در پایین‌دست (کد، نه این سند): `GenesisBuilder` — بررسی‌ها باید `windowStart` را به `lastPaidActivationAt` تغییر دهند و پیکربندی را `maxEntriesPerWindow` = ۱، `probationPeriod` = ۶۰۴۸۰۰ و `slashBps` = ۱۰۰ بخواند (ثابت‌اند)، و `contracts:sync` و `SOURCES.json` تازه شوند؛ ABI/کپی قراردادها در همهٔ سرویس‌ها؛ Verifier (یک فعال‌سازی پولی در هر پنجره؛ بازپخش `SeatMigrated`/`SeatAgreementBound`؛ گام `migrateSeat` پس از `migrateIdentity`)؛ RewardRouter (`SeatMigrated` مثل `SeatTransferred`)؛ ValidatorApp (پذیرش با هش پیش از انتقال، پیام‌های ریورت تازه)؛ GovernanceDashboard (کلیدهای ۰/۲/۴ فقط‌خواندنی؛ قاعدهٔ صندلی زنده برای Standby).
- 🔶 ثابت‌های پیشنهادی کد که اساس‌نامه/تصمیم تعیین نکرده: `VOTING_PERIOD = 3 days` در `FoundationDAO`، `RECOVERY_RECORD_MAX_AGE = 30 days` در `ValidatorsRegistry`.
- 🔶 آدرس‌ها و مبلغ‌های واقعی طلبکاران صندوق طلب‌ها (فهرست پیش از genesis) و ارزیابی مستقل مبالغ. (رفتار باقیمانده‌ی تقسیم اقساط — قسط آخر — در کد تعیین شده است ✅.)
- ✅ اختیار اعضای اولیه‌ی هیأت‌مدیره‌ی ولیدیتورها پیش از فعال‌شدن شش مؤسس دیگر (تصمیم مالک ۲۰۲۶-۱۱-۱۹): عضو `Probation` کرسی دارد ولی عمل نمی‌کند (بند ۲ بالا)؛ دست‌کم ۲ مؤسس دیگر را زود فعال کنید تا هیأت ۳ رأی بیاورد.
- ✅ رفتار انتقال NFT (صندلی `Active` فعال می‌ماند؛ تصمیم مالک ۲۰۲۶-۱۱-۱۹، تصمیم ۱۰۹ در `sur-detailed-plan-and-rationale.md`؛ ⟵ «پذیرش خریدار فقط ثبت است» منسوخ شد ۲۰۲۶-۱۱-۲۳: پذیرش `acceptSeatAgreement` اکنون گیت پیش از انتقال است)؛ 🔶 میزبان `tokenURI`: تأیید مالک لازم است.
- ✅ commit–reveal در `ValidatorLottery` نوشته و با Hardhat آزموده شده است؛ ✅ روی Besu واقعی هم گذشت (دور اول ۲۰۲۶-۱۱-۱۹: BG-10، BG-10b، BG-10-BH؛ بلاک ۲ ثانیه)؛ `REVEAL_WINDOW` شمار **بلاک** است، پس مدت زمانی‌اش به `blockperiodseconds` وابسته است؛ ⚠️ F-7: reveal باید در بلاکی تا `target+250` استخراج شود، و `blockhash` برای ۱ تا ۲۵۶ بلاک واقعی و از ۲۵۷ صفر است.
- ⏸️ ابزار عملیاتی `min-gas-price` برای اپراتور و بلوکه‌کردن حساب در نودهای ولیدیتوری (زیرساخت نباید مانع آینده شود).
