# دستور آزمون Besu برای Claude Code — نسخهٔ ۴ (کد پس از L01 تا L07)

**تاریخ تدوین:** ۲۰۲۶-۱۰-۰۲ · **مخاطب:** Claude Code (اجراکننده) · **وضعیت:** دستور اجرا — هنوز اجرا نشده
**مبنای کد:** بستهٔ `sur-L05-incremental-package-v2` (قراردادها و آزمون‌های Hardhat) + بستهٔ متنی v3. جدول وضعیت: `technical-design/sur-audit-2026-09-30-final-status.md`.
**این سند جایگزین `sur-besu-test-status.md` (دستور نسخهٔ ۳، اجراشده) است؛ آن سند اکنون تاریخی است و فقط برای دانش عملیاتی Besu (بخش ۵) به کار می‌رود.**

---

## ۰. هدف، دامنه و آنچه این آزمون «نیست»

**هدف:** روی یک شبکهٔ Besu/QBFT واقعی، با genesis ساخته‌شده از کد فعلی، رفتار قراردادها پس از اصلاحات L01، L02، L04، L05 و L07 را بسنج و شواهد خام قابل‌بازتولید بساز. تا امروز این اصلاحات فقط روی Hardhat آزموده شده‌اند.

**دامنهٔ آزمون (شش گروه):**

| گروه | موضوع |
|---|---|
| A | invariantهای genesis، storage و checkpoint مؤسسان |
| B | تغییر مجموعهٔ ولیدیتورها در بلاک K؛ تطبیق مجموعهٔ مؤثر، تولیدکننده، امضاکنندگان و وضعیت Registry در N−1 |
| C | اصلاحات L01، L02، L04، L05، L07 و رگرسیون‌های مرتبط |
| D | تسویهٔ چند بازهٔ پیوسته و عقب‌مانده با اسکریپت **آزمایشی** |
| E | هزینهٔ پرداخت با تعداد ولیدیتور و تعداد تغییر نرخ متفاوت، در برابر gasLimit مشخص |
| F | رفتار تغییر پاداش Besu و هماهنگی آن با سقف تاریخی قرارداد |

**این آزمون چه چیزی نیست (صریح):**
1. آزمون RewardRouter عملیاتی نیست. اسکریپت تسویهٔ این آزمون یک ابزار آزمایشی است (بخش ۳).
2. آزمون ابزار genesis production (T02) نیست. ابزار ساخت genesis این آزمون یک ابزار آزمایشی است (بخش ۳).
3. تأیید آمادگی production نیست؛ نه موفقیت و نه شکست آن چنین معنایی دارد.
4. تصمیم‌گیری دربارهٔ gasLimit تولیدی، نرخ، حکمرانی یا سیاست اقتصادی نیست.
5. جایگزین آزمون Hardhat نیست و شواهد Hardhat هم جایگزین شواهد Besu نیست.

**نتایج دورهای قبل:** نتایج دور ۲ و ۳ برای قراردادهایی که L01–L07 تغییرشان داده‌اند (Distributor، Registry، Treasury، FoundationDAO و helperهای genesis) دیگر معتبر نیست. آن‌ها را به‌عنوان نتیجه نقل نکن؛ فقط راهنمای عملیاتی‌اند.

---

## ۱. قواعد غیرقابل‌مذاکره

1. **قرارداد را تغییر نده.** هیچ خطی از `contracts/` یا `contracts-fa/` عوض نمی‌شود. اگر باگ دیدی گزارش کن (بخش ۸)، وصله نکن.
2. **هیچ مسیر دورزدن سقف اضافه نکن**، حتی آزمایشی: نه تابع جدید، نه تغییر نرخ از مسیر غیر از ثبت‌شده، نه کاهش `totalRewards` برای گذراندن گزارش.
3. **سیاست اقتصادی و حکمرانی را عوض نکن.** تنها مقدارهای مجاز، همان overlayهای genesis در بخش ۴ هستند و هر تفاوت با پیشنهاد production باید در گزارش بیاید.
4. **هر نتیجه به نسخهٔ دقیق مقید است:** هر فایل نتیجه با یک سرصفحهٔ مبنا شروع شود (hash مبنا + hash genesis همان شبکه + نسخهٔ Besu).
5. **Hardhat را شاهد Besu معرفی نکن.** هر ادعا باید خروجی خام Besu داشته باشد (tx hash، رسید، خروجی RPC).
6. **اسکریپت آزمایشی را RewardRouter و ابزار ساخت genesis را T02 نام نبر** و فایل‌هایشان را با پیشوند `testonly-` بساز.
7. **از کلید production استفاده نکن.** همهٔ کلیدها آزمایشی‌اند، با فایل مشخص `TEST-KEYS-DO-NOT-REUSE`.
8. **ادعا را به آنچه دیده‌ای محدود کن.** هر چیز تأییدنشده «فرض/تأییدنشده» برچسب بخورد؛ علت شکست را حدس‌زده به‌عنوان حقیقت ننویس.
9. **در ابهام متوقف شو و بپرس** (فایل `QUESTIONS.md`)، حدس نزن. سؤال‌ها مانع آزمون‌های مستقل نیستند.
10. **در Plan فقط پوشهٔ شواهد را بنویس:** `testing-evidence/besu-live-test-v4-<تاریخ اجرا>/`. هیچ سند دیگری را ویرایش نکن.
11. **شبکهٔ قفل‌شده را مطابق بخش ۵ ری‌استارت کن** و هر ری‌استارت را در لاگ ثبت کن.
12. **موفقیت این مرحله را «آمادگی production» ننویس.** قالب جملهٔ پایانی در بخش ۹ آمده است.

---

## ۲. فاز ۰ — تثبیت نسخهٔ مبنا (پیش از هر اجرا)

### ۲.۱ جدول fingerprint مبنا (sha256 سورس‌ها)

این جدول باید دقیقاً با `testing-evidence/hardhat-regression/contracts-tested.sha256` و `contracts-fa.sha256` از بستهٔ v2 یکی باشد.

**انگلیسی (`contracts/`):**
```
850a13fdd11480bc7e554db3c0ecd42be378445a5b4326109c2f45f35046e21c  BlockRewardDistributor.sol
97b79a603c861bb0d66dae58bf555663713a5e13cd821b118ed7561ec96a0ae4  FoundationDAO.sol
038145ba314840660fc06b29ad6394b390efe53d27fe964fd785aba4cfc103cc  IdentityRegistry.sol
224efe619356978b4bc1b897b6af900019ace54b69209519acf35466ca80e6bf  ServiceStaking.sol
e1159fc11434cde06efca3d89cf72ce1435fe9c46998089c1e0d9b1de990d4d6  SurAddresses.sol
ee93f621b56b7344d4e96e879dd5c17822e7816271c8a188ecd3752986c82803  SurenSale.sol
6eb5d5092b666c57f1875aa9b935ab2e1d30f7c7ba1608ff4dabc4e6b3855be1  ValidatorsBoard.sol
8ca2eeef8edc2615175fc8d59a72811f97f4d93e10a1add306dfabcdc86de7cf  ValidatorsRegistry.sol
908387912c3dc3428bea5639eb032745005357a4bd611f39a41c2dd90e0c1c1f  ValidatorsTreasury.sol
42a026fb6e2eaade2d02d3cf0381822107ea7226b76c7852c48f651871868417  genesis-seed-helpers/FoundationDAO_GenesisSeed.sol
818b8bcad43f5cee211d27a74e0e69d6f7d178275e78c57ad72da139c1e8386a  genesis-seed-helpers/ValidatorsBoard_GenesisSeed.sol
d21b9f52bdabde8b647ea7df5efad0be63c7ec4e38f0761fb051ec009aacaad2  genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol
e96a5d373fb9a918771501913738f169c18cff271fd8487045f9e5f74740a3a3  reference-dapps/SurZether.sol
```
**فارسی (`contracts-fa/`):**
```
032de8ff29ac779caf31ea9c119a2253a6653d6fe95a69905d1b0b343fde1f88  BlockRewardDistributor.sol
9cbb4e02fe9819e234cec31bc692e78f258d288415bef5da9b1dd9e50b17eb03  FoundationDAO.sol
003738abb63af1920bdc3a17818f3ddc63d402df9d63d5a878177eb5e92c533b  IdentityRegistry.sol
c3f54301fc3760964a43a75ebf4f66c8105f21bc77d8dd93c706560ba2638256  ServiceStaking.sol
d69a54a35ac424c2b49e7c952360545b39359ea2878faa0a8e2f7b3afe97687d  SurAddresses.sol
16cceb7b34896a153e72084ea6cd019df292c8ea45d8b2cb9ea85017d3ae0657  SurenSale.sol
104347af8e56254e9f60e2a36474f290ad0f41cb8f81c49cf59c098b92823931  ValidatorsBoard.sol
eb3e2a5aa9d8a399b9e0fcdf9b3548558dd0c840bad1fabd956d3473550c4363  ValidatorsRegistry.sol
298a73af96174271143a41bf77271abcf00946e0ff1224e170ddc5228c2c4053  ValidatorsTreasury.sol
9c014f76ca8953bc8e80ffadaf05e58c1565b5302326819d34916d66bd234c0c  genesis-seed-helpers/FoundationDAO_GenesisSeed.sol
9761c05fd25b20c86c237b7e7ae7a1b28753f2cc85079afcf7dcac109eaed60b  genesis-seed-helpers/ValidatorsBoard_GenesisSeed.sol
d8c0c523157faa67780e287faf416cbbac58825df4f66611083d54d6571dfa3f  genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol
9e7d4958177b7703691d1be9cdabb6f16c25b591ca4472ae1b66aa0414ee65c3  reference-dapps/SurZether.sol
```
قرارداد قابل‌استقرار برای genesis از `contracts/` (انگلیسی) است. نسخهٔ فارسی فقط برای هم‌ارزی منطقی ثبت می‌شود (در بستهٔ v2، parity جفت‌فایل‌ها ۱۳ از ۱۳ بود؛ این را دوباره اجرا نکن، فقط hash فارسی را ثبت کن).

### ۲.۲ مراحل تثبیت

1. فایل‌های مبنا را از Plan (یا بستهٔ v2 اعمال‌شده) در `besu-test/baseline/` کپی کن و **فقط‌خواندنی** کن.
2. `sha256sum -c` را روی جدول بالا اجرا کن. **هر ناهمخوانی = توقف کامل** و گزارش (علت احتمالی: Plan دورتر تغییر کرده است).
3. کامپایل با پیکربندی ثابت: `solc 0.8.24`، optimizer فعال با `runs=200`، **بدون viaIR**، و `evmVersion` پیش‌فرض آن solc. تنظیمات دقیق را در `compile-settings.json` ثبت کن. اگر روی `solc 0.8.24` کامپایل شکست خورد، متوقف شو (در بستهٔ v2 هر دو نسخهٔ 0.8.24 و 0.8.37 بدون warning کامپایل شدند).
4. برای هر شش قرارداد genesis (`ValidatorsRegistry`، `ValidatorsBoard`، `ValidatorsTreasury`، `BlockRewardDistributor`، `FoundationDAO`، `IdentityRegistry`) این‌ها را ثبت کن: keccak256 بایت‌کد مستقرشده (`deployedBytecode`)، اندازهٔ runtime، و `storageLayout` کامل. اندازهٔ runtime توزیع‌کننده در بستهٔ v2 برابر ۱۸٬۱۷۷ بایت است؛ اگر فرق کرد گزارش بده.
5. **نسخه‌های ابزار و محیط (در `01-environment/env.json`):** Besu (مرجع این پروژه: ۲۶.۹.۰، tarball با sha256 برابر `172b29069837f13436a20bd7c8234aeca67917d8a378e81e2bd4a205c57540ea`)، Java (Besu ۲۶.۹.۰ به Java ۲۵ نیاز دارد؛ با Java ۲۱ اجرا نمی‌شود)، Node، نسخهٔ `ethers`/`solc`، سیستم‌عامل، CPU/RAM. اگر نسخهٔ دیگری از Besu به کار می‌رود، دلیل و hash را بنویس و آن را «انحراف از مرجع» بزن.
6. پس از ساخت هر genesis: sha256 خود `genesis.json`، پیکربندی هر نود (`config.toml`)، `static-nodes.json` و همهٔ اسکریپت‌های `testonly-*` را ثبت کن. پس از استقرار شبکه: `keccak256(eth_getCode(addr))` هر آدرس را با hash کامپایل مقایسه کن.
7. هر تغییر در سورس، اسکریپت‌ها یا پارامترهای genesis یعنی **مبنای تازه**: نتایج قبلی دیگر به آن نسخه تعلق ندارند و باید برچسب «نسخهٔ قبلی» بگیرند.

---

## ۳. تفکیک ابزار آزمایشی از ابزار production

| ابزار آزمایشی (در این آزمون ساخته می‌شود) | چه می‌کند | چرا production نیست |
|---|---|---|
| `testonly-genesis-builder` | ساخت genesis آزمایشی، شامل seedهای مخصوص آزمون | seed مستقیم `everActivated` برای payeeهای آزمون هزینه و seed تاریخچهٔ نرخ **در ابزار production مجاز نیست**؛ ۵ مؤسس (نه ۷) و کلیدهای آزمایشی؛ overlayهای زمانی کوتاه |
| `testonly-settle` | ساخت و ارسال `distributeRewards` برای آزمون | یک اسکریپت یک‌بارمصرف است؛ recovery، idempotency، ماشین حالت تراکنش، Vault و هشدار عملیاتی ندارد؛ **RewardRouter نیست** |
| `testonly-collector` | جمع‌آوری ردیف‌های بلاک (مجموعهٔ مؤثر، تولیدکننده، امضاکنندگان، Registry در N−1) | فقط برای شواهد |
| `testonly-network` | راه‌اندازی/ری‌استارت نودها | فقط محیط آزمون |

**پیاده‌سازی production ابزار genesis (T02) و RewardRouter کار جداگانه است و در این آزمون ساخته یا ادعا نمی‌شود.** پیشنهاد: ابزار آزمایشی از اسکریپت‌های `v3` (`01-generate-accounts` تا `04-generate-nodes`) شروع شود، ولی هر فایل کپی‌شده با پیشوند `testonly-` و یک سرصفحهٔ «ابزار آزمایشی» نام‌گذاری شود.

---

## ۴. تنظیمات آزمایشی در برابر پیشنهاد production (جدول صریح)

ستون «پیشنهاد/منبع» یعنی مقداری که اسناد یا سورس پروژه پیشنهاد می‌کنند. «تعیین‌نشده» یعنی هنوز تصمیمی ثبت نشده و این آزمون آن را تعیین نمی‌کند.

| پارامتر | مقدار آزمون | پیشنهاد / منبع | توضیح |
|---|---|---|---|
| `gasLimit` بلاک (کار اصلی) | **۳۰٬۰۰۰٬۰۰۰** | **تعیین‌نشده** | v3 مقدار تقریباً نامحدود `0x1fffffffffffff` داشت؛ **دیگر استفاده نشود** |
| `gasLimit` (شبکه‌های هزینه، گروه E) | ۱۵٬۰۰۰٬۰۰۰ و ۳۰٬۰۰۰٬۰۰۰ و ۶۰٬۰۰۰٬۰۰۰ | تعیین‌نشده | سه سناریوی صریح؛ هیچ‌کدام «انتخاب production» نیست |
| `chainId` | عددی یکتا برای هر شبکه (مثلاً ۴۲۴۲۴۵ به بعد) | تعیین‌نشده | هر شبکه chainId جدا |
| `blockperiodseconds` | ۳ | ۳ (تصمیم قطعی) | سرعت واقعی ممکن است کمی سریع‌تر باشد (~۲٫۹۵ ثانیه) |
| `epochlength` / `requesttimeoutseconds` | ۳۰۰۰۰ / ۱۰ | تعیین‌نشده | همان v3 |
| `zeroBaseFee`، `londonBlock` و همهٔ hard-forkها | `true`، همه صفر | طبق دانش عملیاتی v2 | الزامی |
| `miningbeneficiary` | `0x2222…2222` (Distributor) | همین | پاداش و کارمزد هر دو به این آدرس می‌رسد |
| `qbft.blockreward` | ۲×۱۰¹⁸ wei | ۲ SUR هر بلاک | برابر `INITIAL_REWARD_PER_BLOCK` |
| `validatorcontractaddress` | `0x3333…3333` (Registry) | همین | `extraData` با ۰ ولیدیتور |
| قیمت گاز (`min-gas-price`) | ۱۰¹⁴ wei | ۱۰¹⁴ wei (طبق اسناد) | |
| تعداد مؤسسان genesis | **۵** (هر کدام نود واقعی) | helper production هفت مؤسس دارد | آزمون نباید ولیدیتور فعالِ بدون نود داشته باشد |
| تعداد اعضای FoundationDAO | ۱۵ حساب آزمایشی (بدون نود) | ۱۵ | فقط برای سناریوی اختیاری L04-F |
| `probationPeriod` | **۳۰۰ ثانیه** | ۶۰۴٬۸۰۰ (سورس) | کوتاه‌شده برای آزمون؛ overlay |
| `recoveryPeriod` | **۳۷۰۰ ثانیه** | ۱۷۲٬۸۰۰ (سورس) | باید `> MASS_DEMOTION_WINDOW = ۳۶۰۰` بماند |
| `exitCooldown` | ۶۰۰ ثانیه | ۶۰۴٬۸۰۰ (سورس) | فقط اگر `withdrawStake` آزموده شود |
| `maxEntriesPerWindow` | ۱۰ | ۱ (سورس) | با صفر، `requestMembership` رد می‌شود؛ initializer در genesis اجرا نمی‌شود |
| `entryWindowSeconds` | ۸۶۴۰۰ | ۸۶۴۰۰ | |
| `entryThresholdBase`، `membershipFeeBps` و منحنی ورود | مقدار سورس | مقدار سورس (۵۰۰٬۰۰۰ SUR، ۴۰۰ bps، …) | داوطلب باید بیش از وثیقه + کارمزد موجودی داشته باشد |
| `slashBps` | ۱۰۰ | ۱۰۰ (سورس) | |
| `perPaymentCap` / `periodCap` (Treasury) | ۵۰٬۰۰۰ / ۲۰۰٬۰۰۰ SUR | همین (سورس) | overlay الزامی |
| `distributionOracle`، `verifier` | کلیدهای آزمایشی | تعیین‌نشده | |
| `validatorDirectShareBps` | ۵۰۰۰ | ۵۰۰۰ | overlay |
| ماشین‌ها | یک میزبان، چند فرایند | production چندمیزبانه | محدودیتِ آزمون؛ در گزارش بیاید |
| seed مستقیم storage (فقط آزمایشی) | `everActivated` payeeها؛ تاریخچهٔ نرخ | **در production وجود ندارد** | فقط در گروه‌های E و F؛ برچسب `TEST-ONLY-SEED` |

**قاعده:** هر overlay باید با فهرست `offchain-services/sur-genesis-builder-tool-spec.md` سنجیده شود؛ اگر مقداری آنجا هست و در این جدول نیست، یا برعکس، آن را در گزارش به‌عنوان ناسازگاری سند بنویس.

---

## ۵. معماری شبکه و نکات عملیاتی Besu

### ۵.۱ نقش‌ها
- **V1 تا V5:** پنج مؤسس genesis؛ هر کدام یک نود Besu با همان کلید خصوصی ولیدیتور (کلید نود = کلید حساب). Board هم با همین پنج نفر seed می‌شود.
- **C6:** داوطلب؛ از ابتدا به‌صورت نود همگام‌شدهٔ **غیرولیدیتور** اجرا می‌شود و پس از فعال‌سازی عضو مجموعه می‌شود.
- **X7:** نود با تنظیم عمداً متفاوت؛ فقط در آزمون F4 و **فقط روی شبکهٔ آزمایشی**.
- حساب‌ها: `verifier`، `distributionOracle`، حساب تأمین‌کنندهٔ بودجه، ۱۵ حساب FoundationDAO، و یک مجموعهٔ ۱۵۰ آدرس payee برای گروه E (کلید لازم ندارند).
- **قاعده‌ٔ حیاتی:** تعداد نود واقعیِ در حال اجرا همیشه ≥ تعداد ولیدیتور فعال. فعال‌سازی ولیدیتور بدون نود، نصاب QBFT را می‌شکند و زنجیره قفل می‌شود. هیچ‌وقت کمتر از ۴ ولیدیتور فعال باقی نگذار (تحمل خطای ۱).

### ۵.۲ پیکربندی نود (الگو؛ ریشه‌اش `testonly-generate-nodes` از v3)
```toml
data-path="nodeN/data"
genesis-file="genesis.json"
node-private-key-file="nodeN/key"
p2p-host="127.0.0.1"
p2p-port=3240N
rpc-http-enabled=true
rpc-http-host="127.0.0.1"
rpc-http-port=865N
rpc-http-api=["ETH","NET","QBFT","ADMIN","WEB3","DEBUG","TRACE","TXPOOL"]
rpc-http-cors-origins=["*"]
host-allowlist=["*"]
min-gas-price=100000000000000
discovery-enabled=true
```
- **`TRACE` الزامی است** (برای `trace_block`).
- **اتصال نودها:** `static-nodes.json` به‌جای `--bootnodes` (مشکل مشاهده‌شده در v2).
- **تاریخچهٔ state برای `eth_call` روی N−1:** تا جایی که نسخهٔ Besu اجازه می‌دهد از `data-storage-format="FOREST"` استفاده کن؛ اگر رد شد، از BONSAI با بالابردن `bonsai-historical-block-limit` استفاده کن و محدودیت را در گزارش بنویس. **مستقل از این، ردیف‌های گروه B را در لحظه جمع کن** (collector روی هر بلاک جدید بخواند)، نه بعداً.
- **RPC caps:** هر سقف RPC فعال (مثلاً `--rpc-gas-cap`) را ثبت کن؛ ممکن است نتیجهٔ `eth_estimateGas` را در گروه E تحت تأثیر بگذارد.
- **تله‌ٔ timestamp:** genesis با timestamp آینده تولید بلاک را معطل می‌کند؛ timestamp را کمی در گذشته بگذار.
- **ری‌استارت پس از قفل:** **همهٔ نودها را هم‌زمان** ری‌استارت کن، نه فقط نودهای خاموش‌شده. (استثنا: آزمون F4 که عمداً ری‌استارت پی‌درپی را می‌سنجد.)
- فرایندها را با `systemd` یا `tmux` اجرا کن و لاگ هر نود را جدا ذخیره کن؛ آزمون‌های چندروزه به آن نیاز دارند.

### ۵.۳ شبکه‌ها
| شبکه | مصرف | عمر |
|---|---|---|
| **Net-1 (اصلی)** | گروه‌های A، B، C، D | تا پایان مسیر M (حداقل ~۴۷ ساعت) |
| **Net-E15 / Net-E30 / Net-E60** | گروه E (هر کدام با gasLimit خودش) | کوتاه، یک‌بارمصرف |
| **Net-F1، F2، F3** | گروه F (هر کدام genesis جدا) | کوتاه، یک‌بارمصرف |
| **Net-L** (اختیاری) | مسیر L | حداقل ۸ روز |

---

## ۶. محدودیت‌های زمانی قرارداد و سه مسیر اجرا

بعضی کنترل‌های قرارداد زمان‌محورند و روی Besu نمی‌شود با `evm_increaseTime` (که وجود ندارد) سرعتشان داد. **زمان‌ها را کوتاه نکن؛ مسیرها را جدا کن.**

| ثابت | مقدار | اثر روی آزمون |
|---|---|---|
| `MIN_DISTRIBUTION_INTERVAL` | ۲۳ ساعت | دو توزیع پیاپی روی یک شبکه حداقل ۲۳ ساعت فاصله دارند (جز اولین توزیع) |
| `SHARE_CHANGE_MIN_INTERVAL` | ۱۸۰ روز | رفع‌شدنِ قفل تغییر دوم سهم قابل‌آزمون نیست |
| `PROPOSAL_EXPIRY` / `RATE_VOTING_EXPIRY` | ۳۰ روز | انقضا قابل‌آزمون نیست |
| `RATE_CHANGE_DELAY` | ۷ روز | اجرای تغییر نرخ فقط در مسیر L |
| `MIN_RATE_CHANGE_LEAD_BLOCKS` | ۲۰۱٬۶۰۰ بلاک | فاصلهٔ ارتفاع شروع تا بلاک اجرا؛ در آهنگ ۳ ثانیه تقریباً ۷ روز |
| `CAP_CHANGE_TIMELOCK_DELAY`، `BOARD_REFRESH_INTERVAL` | ۷ روز، ۳۰ روز | خارج از دامنه |

**مسیر S (کوتاه، حدود یک روز):** گروه‌های A، B، C (بدون بندهای زمانی)، D01–D03، E، F. همه با ساعت دیواری واقعی.
**مسیر M (میان‌مدت):** توزیع‌های D04 و D05 روی Net-1، به‌ترتیب حداقل ۲۳ و ۴۶ ساعت پس از اولین توزیع. Net-1 را تا آن زمان روشن نگه دار و آن را برای آزمون‌های مخرب دیگر استفاده نکن.
**مسیر L (بلندمدت، اختیاری):** اجرای واقعی تغییر نرخ از مسیر حکمرانی (بند C-L05-4) و عبور از ارتفاع شروع با transition هماهنگ‌شدهٔ Besu. حداقل ~۸ روز. **اجرای مسیر L تصمیم مالک است؛ اگر اجرا نشد، «اجرانشده» ثبت شود.**

**آنچه روی Besu قابل‌آزمون نیست (باید «اجرانشده؛ علت زمان» ثبت شود، نه «موفق»):** رفع قفل ۱۸۰ روزهٔ تغییر سهم، انقضای ۳۰روزه، تأخیر ۷روزهٔ اجرا (جز مسیر L)، فاصلهٔ ۳۰روزهٔ refresh هیأت.

---

## ۷. آزمون‌ها

برای هر آزمون یک فایل `04-results/<ID>.md` (و در صورت نیاز `.json`) بساز: سرصفحهٔ مبنا، گام‌ها، خروجی خام، نتیجه (**PASS / FAIL / NOT-RUN / BLOCKED / INCONCLUSIVE**)، و ارجاع به tx hashها.
انتظارها در ستون «انتظار» آمده‌اند؛ **اگر خروجی فرق داشت، همان خروجی را گزارش کن، انتظار را تغییر نده.**

### گروه A — genesis، storage و checkpoint مؤسسان (شبکهٔ Net-1، پیش از هر تراکنش)

| ID | بررسی | انتظار |
|---|---|---|
| A01 | `sha256sum -c` جدول مبنا؛ hash کامپایل | یکسان |
| A02 | ساختار genesis: `chainId`، `qbft` (period، epoch، timeout، `validatorcontractaddress`، `miningbeneficiary`، `blockreward`)، `zeroBaseFee`، hard-forkها، `gasLimit` اعلام‌شده | طبق بخش ۴ |
| A03 | `extraData` | `RLP([vanity ۳۲ بایت، [] ولیدیتور، [] رأی، round ۰، [] seal])` |
| A04 | `keccak256(eth_getCode)` هر شش آدرس + helperها | برابر hash کامپایل همان اجرا |
| A05 | `immutableReferences` توزیع‌کننده در خروجی کامپایل | `{}` |
| A06 | Registry: `getValidators()` | دقیقاً ۵ مؤسس، به‌ترتیب seed |
| A07 | برای هر مؤسس: `isValidator`، `everActivated` (getter **و** slot خام) | `true`؛ مقدار خام از `storageLayout` همان کامپایل (در بستهٔ v2 اسلات ۲۰) با `keccak256(abi.encode(addr, slot))` |
| A08 | **checkpoint مؤسسان:** `statusNonce()`؛ `wasActiveAt(founder, 0)`؛ `wasActiveAt(غیرمؤسس, 0)`؛ slot خام `activeCheckpoints` | `statusNonce==0`؛ `true`؛ `false`؛ طول آرایه ۱ و عنصر اول `{nonce:0, active:true}` که در یک slot به‌صورت `1<<64` بسته می‌شود (`statusNonce` اسلات ۳۶، `activeCheckpoints` اسلات ۳۷ در v2؛ از `storageLayout` بخوان) |
| A09 | Board: `getBoardMembers()`، `boardVersion()`، `lastBoardRefreshAt` | ۵ عضو؛ مقدار طبق helper/overlay؛ با spec ابزار genesis مقایسه شود |
| A10 | FoundationDAO: ۱۵ عضو، `membershipNonce()`، `memberSinceNonce(m)` برای هر عضو | `membershipNonce==0`؛ همه ۰ |
| A11 | Distributor: `INITIAL_REWARD_PER_BLOCK()`، `rewardRateChangeCount()`، `rateProposalCount()`، `lastSettledBlock()`، `epochCount()`، `distributionOracle()`، `validatorDirectShareBps()`، `maxRewardsForRange(1,1000)`، constantها (`RATE_CHANGE_BOARD_APPROVALS`، `RATE_VOTING_EXPIRY`، `RATE_CHANGE_DELAY`، `MIN_RATE_CHANGE_LEAD_BLOCKS`) | به‌ترتیب: ۲×۱۰¹⁸؛ ۰؛ ۰؛ ۰؛ ۰؛ oracle آزمایشی؛ ۵۰۰۰؛ ۲۰۰۰×۱۰¹⁸ (وقتی تاریخچه خالی است)؛ ۳، ۳۰ روز، ۷ روز، ۲۰۱٬۶۰۰ |
| A12 | اسلات‌های ۲۴ تا ۲۸ Distributor | همه صفر (در شبکه‌های بدون seed نرخ) |
| A13 | overlayها: Registry، Treasury، Board | مقدارها = بخش ۴؛ اختلاف با spec ابزار genesis گزارش شود |
| A14 | **اسکن storage ناخواسته:** همهٔ اسلات‌های نوشته‌شده در `alloc` در فهرست مورد انتظار seed باشند | هیچ اسلات یا حساب اضافه‌ای وجود نداشته باشد |
| A15 | پایداری ۱۰۰ بلاک اول: میانگین، کمینه، بیشینه و صدک ۹۵ فاصلهٔ بلاک؛ `qbft_getValidatorsByBlockNumber("latest")` در برابر `getValidators()` | زنجیره پیش می‌رود؛ مجموعه‌ها یکی‌اند |

اگر A07 یا A08 شکست خورد، آن را **یافتهٔ بحرانی** گزارش کن و کل اجرا را متوقف کن (بخش ۸).

### گروه B — تغییر مجموعهٔ ولیدیتورها در بلاک K (Net-1)

**روش جمع‌آوری (`testonly-collector`)، برای هر بلاک N در پنجرهٔ K−3 تا K+8 و برای ≥ ۵۰ بلاک پیش از اولین تغییر:**

| فیلد ردیف | منبع |
|---|---|
| N، hash بلاک، timestamp | `eth_getBlockByNumber` |
| تولیدکننده | فیلد `miner` (در v2/v3 مشاهده شد که برابر پراپوزر واقعی است؛ دوباره راستی‌آزمایی کن) |
| مجموعهٔ مؤثر QBFT | `qbft_getValidatorsByBlockNumber(N)` |
| مجموعهٔ Registry | `getValidators()` با `eth_call` روی N−2، N−1 و N |
| `isValidator(x)` برای همهٔ نامزدها | همان سه ارتفاع |
| `statusNonce()`، `wasActiveAt(x, nonce)` | همان سه ارتفاع |
| امضاکنندگان | seals درون `extraData`؛ آدرس‌ها با بازیابی امضا |

**امضاکنندگان:** الگوریتم بازیابی را خودت از مستند Besu و کد نسخهٔ مرجع پیاده کن و **پیش از اتکا، اعتبارسنجی کن**: روی ≥ ۵۰ بلاک متوالی همهٔ آدرس‌های بازیابی‌شده باید عضو مجموعهٔ مؤثر باشند و تعدادشان ≥ نصاب (⌈۲N/۳⌉ برای N ولیدیتور). اگر بازیابی ممکن نشد یا اعتبارسنجی شکست خورد، «شواهد سطح امضاکننده: به‌دست نیامد» بنویس و علت را بیاور؛ ادعای امضاکننده نکن.

| ID | سناریو | انتظار / سنجه |
|---|---|---|
| B01 | **کشف قاعدهٔ تأخیر:** برای ۵۰ بلاک اول و بلاک‌های نزدیک هر تغییر، مجموعهٔ QBFT(N) را با Registry@(N−2)، @(N−1) و @N مقایسه کن | گزارش کن کدام ارتفاع **دقیقاً** مجموعهٔ مؤثر را می‌دهد؛ **فرض اولیه N−1 است و باید اثبات شود، نه فرض** |
| B02 | تعلیق V5 با `recordSuspension` (verifier) در بلاک K | مجموعه از ۵ به ۴؛ V5 پس از بلاک مؤثر نه تولید می‌کند و نه امضا؛ ردیف‌ها را بیاور |
| B03 | فعال‌سازی C6: `requestMembership()` با مبلغ `currentEntryThreshold()+currentMembershipFee()`؛ انتظار واقعی `probationPeriod`؛ `recordActivation` | مجموعه ۴ → ۵؛ C6 پس از بلاک مؤثر امضا و تولید می‌کند |
| B04 | بازگشت V5: پس از `recoveryPeriod` (۳۷۰۰ ث) با `recordRecovery` | مجموعه ۵ → ۶ (قبل از آن نود V5 باید روشن بماند) |
| B05 | **دو تغییر در یک بلاک** (مثلاً تعلیق V4 و V5): دو تراکنش با nonceهای متوالی از یک فرستنده؛ تا ۲۰ بار تلاش | رسیدها بلاک یکسان؛ اگر هرگز هم‌بلاک نشدند، «به‌دست نیامد» بنویس. پس از آن حداقل ۴ ولیدیتور فعال بماند |
| B06 | **هم‌ارزی `isValidator ⇔ getValidators`** روی ≥ ۲۰۰ بلاک نمونه (همهٔ بلاک‌های اطراف تغییرها + نمونهٔ تصادفی) برای همهٔ نامزدها | شمار ناهمخوانی. این مورد در سند وضعیت (`sur-audit-2026-09-30-final-status.md`) اکنون «تأیید در بررسی سورس؛ نیازمند آزمون runtime و genesis» است؛ نتیجه را همان‌طور بنویس و آن را «اثبات‌شده» نخوان مگر هر دو پوشش (genesis و همهٔ مسیرهای انتقال) دیده شده باشد |
| B07 | **شاهد L08:** برای هر بلاک، `miner(N)` عضو Registry@(N−1) بوده؟ (و مجموعهٔ امضاکنندگان ⊆ مجموعهٔ مؤثر) | فهرست نقض‌ها. **هر نقض را جدا گزارش کن؛ هیچ پاداشی حذف یا بازتوزیع نشود.** اگر نقضی نبود، فقط همین را بنویس؛ «غیرممکن است» ننویس |

یادداشت: تعلیق چند ولیدیتور در یک ساعت ممکن است سازوکار معافیت جمعی (`MASS_DEMOTION_*`) را فعال کند؛ رفتار دقیق را از سورس Registry بخوان و در صورت فعال‌شدن، آن را در ردیف ثبت کن.

### گروه C — اصلاحات L01، L02، L04، L05، L07 و رگرسیون‌ها

**ترتیب روی Net-1:** B → C-L04 → C-L05 → C-L01 → C-L07 (منفی‌ها) → گروه D (منفی‌ها و توزیع اول) → C-L02 (آخر، چون تغییر هیأت دائمی است). مرجع رفتار مورد انتظار: آزمون‌های Hardhat (`test_L01_L02_share_change`، `test_L02_real_board_integration`، `test_L04_*`، `test_L05_*`، `test_L07_strict_ascending`، `test_P01_P02_board`، `test_P05_distributor_ranges`، `test_L03_settlement_backlog`، `test_D05_proposal_read_paths`، `verify_everActivated_policy`). **این‌ها فقط مرجع‌اند؛ اسکریپت‌های Besu را مستقل بنویس.**

| ID | سناریو | انتظار |
|---|---|---|
| C-L01-1 | اولین تغییر سهم (`proposeShareChange(5500)`): ۳ رأی هیأت + دوسوم ولیدیتورها | اجرا می‌شود؛ `validatorDirectShareBps==5500`، `lastShareChangeTime` تنظیم |
| C-L01-2 | پیشنهاد دوم بلافاصله، با همهٔ رأی‌ها | آخرین رأی موفق، ولی `validatorDirectShareBps` بدون تغییر و `executed==false` (قفل ۱۸۰ روزه در نقطهٔ اجرا)؛ رفع قفل **قابل‌آزمون نیست** — «اجرانشده؛ علت زمان» |
| C-L02-1 | یکی از اعضای هیأت `requestExit()` می‌زند (بدون `syncBoard`) | `hasBoardAuthority` او `false`؛ رأی او رد با `caller has no live board authority`؛ `isBoardMember` هنوز `true` |
| C-L02-2 | `syncBoard()` (افزایش `boardVersion`) | پیشنهادهای پیشین (سهم و نرخ) رأی هیأت را با `board membership changed since this proposal was created - propose again` رد می‌کنند |
| C-L04-1 | پیشنهاد پارامتر Registry (پارامتر کم‌خطر، مثلاً مقداری نزدیک به مقدار فعلی `probationPeriod`)؛ سپس C6 فعال می‌شود | C6 نمی‌تواند رأی دهد: `not eligible - not Active when this proposal was created`؛ نصاب ثابت‌شده با فرمول همان مسیر |
| C-L04-2 | ولیدیتور هنگام ساخت **معلق** بوده و بعد بازگشته | رأی رد (همان پیام) |
| C-L04-3 | ولیدیتور واجد، پس از ساخت معلق و برگشته، هنوز رأی نداده | یک‌بار رأی می‌دهد؛ دوباره: `already voted` |
| C-L04-4 | ولیدیتور پس از رأی خروج می‌زند | رأی ثبت‌شده می‌ماند؛ رأی تازه ممکن نیست |
| C-L04-5 | همان سناریوها برای سقف Treasury (`proposeCapChange`/`voteCapChange`) و مجلس ولیدیتورهای Distributor | همان رفتارها (پیام‌های `ValidatorsTreasury:`/`BlockRewardDistributor:` مربوط) |
| C-L04-6 *(اختیاری، P2)* | FoundationDAO با ۱۵ عضو: عضو افزوده‌شدهٔ بعدی به پیشنهاد قدیمی رأی نمی‌دهد؛ عضو حذف‌شده رأی ثبت‌شده‌اش می‌ماند | `not eligible - not a member when this proposal was created`؛ `not a member` |
| C-L05-1 | **سقف تاریخی روی زنجیرهٔ واقعی (پیش از اولین توزیع):** `maxRewardsForRange(1, L)` | `۲×۱۰¹⁸ × طول` (تاریخچه خالی) |
| C-L05-2 | حکمرانی نرخ تا مرحلهٔ انتظار: `proposeRateChange(startBlock ≥ بلاک جاری + ۲۰۱٬۶۰۰ + حاشیه، نرخ)` توسط ولیدیتور فعال؛ ۳ رأی هیأت؛ دوسوم ولیدیتورها (برای ۵ ولیدیتور: ۴ رأی؛ طبق `(2n+2)/3`) | `rateChangeStatus` → `(4,0)` پس از تصویب؛ `executeRateChange` پیش از تأخیر: `execution delay has not elapsed` |
| C-L05-3 | تغییر هیأت پس از تکمیل مجلس هیأت و پیش از رأی آخر ولیدیتورها | رأی آخر با `board membership changed …` رد؛ `approvedAt==0`؛ `rateChangeStatus → (7,1)` |
| C-L05-4 *(فقط مسیر L)* | اجرای واقعی `executeRateChange` پس از ≥ ۷ روز؛ بلاک اجرا ≤ startBlock − ۲۰۱٬۶۰۰ | تاریخچه یک ورودی می‌گیرد؛ `rewardRateAt` در مرز درست؛ سقف از `startBlock` نرخ جدید را اعمال می‌کند |
| C-L05-5 | توضیح: **پیش از عبور از سقف، هیچ مسیر دورزدنی نیست.** دور زدن آزموده نمی‌شود؛ فقط ردهای سقف در گروه‌های D و F | — |
| C-L07-1 | `distributeRewards` با آدرس تکراری و با ترتیب نزولی (قبل از اولین توزیع موفق) | رد با `validators must be strictly ascending`؛ بدون تغییر state |
| C-L07-2 | همان داده مرتب و تجمیع‌شده | موفق (به‌عنوان D02) |
| C-REG-1 | رگرسیون P05: بازه‌ٔ ناپیوسته، وارونه، آینده، و جمع بلاک‌ها بیش از اندازهٔ بازه (قبل از اولین توزیع) | پیام‌های `range must start right after the last settled block`، `empty or inverted block range`، `range includes blocks that are not yet produced`، `reported blocks exceed the range size` |
| C-REG-2 | رگرسیون سیاست `everActivated`: تولیدکنندهٔ بعداً خارج‌شده/معلق پرداخت کامل می‌گیرد؛ آدرس هرگز-فعال‌نشده رد می‌شود؛ `everActivated` پس از `withdrawStake` می‌ماند | `address was never a legitimate validator` برای آدرس ساختگی |
| C-REG-3 | رگرسیون D05 (مسیرهای خواندن پیشنهاد؛ مرجع `test_D05_proposal_read_paths`): `paramProposals(id)` (۸ خروجی)، `capChangeProposals(id)` (۸)، `shareProposals(id)` (۱۱)، `rateProposals(id)` (۱۱) و `rateChangeStatus(id)`؛ برای FoundationDAO مقدار `createdAtNonce` از getter قابل خواندن نیست و با شبیه‌سازی `vote(id)` با `eth_call` سنجیده می‌شود | شمار خروجی‌ها و مقدارها با رویدادها و state یکی؛ در شبیه‌سازی `vote` چهار دستهٔ خطا جدا دیده شود |
| C-REG-4 | رگرسیون هیأت ۳ از ۵: دو رأی هیأت + همهٔ ولیدیتورها تصویب نمی‌کند؛ رأی سوم می‌کند | دو رأی هیأت کافی نیست؛ با رأی سوم (و تکمیل رأی ولیدیتورها) اجرا می‌شود (`required = BOARD_SIZE/2 + 1 = 3` در سورس) |

### گروه D — تسویهٔ چند بازه با اسکریپت آزمایشی (`testonly-settle`)

> این گروه **آزمون RewardRouter نیست.** فقط رفتار قرارداد و درستی حساب‌ها را با یک اسکریپت یک‌بارمصرف می‌سنجد.

**قاعدهٔ ترتیب (مهم):** در `distributeRewards` ترتیب چک‌ها این است: فهرست خالی → طول نابرابر → **فاصلهٔ ۲۳ ساعته (فقط وقتی `epochCount>0`)** → پیش‌محاسبه و موجودی → چک بازهٔ P05 → سقف L05 → ترتیب و اهلیت آدرس‌ها. پس **همهٔ آزمون‌های منفی بازه/سقف/ترتیب را پیش از اولین توزیع موفق اجرا کن**؛ پس از آن، تا ۲۳ ساعت، همه با `too soon since last distribution` رد می‌شوند.

**اسکریپت `testonly-settle` برای هر بازه:** `L = eth_blockNumber` (آخرین بلاک مهرشده)؛ `S = lastSettledBlock()`؛ بازه `[S+1, L]`؛ تولیدکنندهٔ هر بلاک از `miner`؛ تجمیع به‌ازای هر آدرس؛ **مرتب‌سازی صعودی عددی**؛ پاداش از `trace_block` (entryهای `type:"reward"`) و راستی‌آزمایی مستقل با روش «بلاک خالی» (در بلاک بدون تراکنش، تغییر موجودی `0x2222` برابر پاداش است)؛ کارمزد از رسید تراکنش‌ها (با `zeroBaseFee`: `gasUsed × effectiveGasPrice`)؛ مقایسه با `maxRewardsForRange(S+1, L)`؛ **اگر پاداش واقعی از سقف بیشتر بود یا شمارش ناقص بود، اسکریپت نمی‌فرستد و هشدار می‌دهد** (رفتار اسکریپت آزمایشی، نه ادعای Router).

| ID | سناریو | انتظار |
|---|---|---|
| D01 | منفی‌ها پیش از توزیع اول (هر کدام جدا؛ پس از هر رد state و موجودی تغییری نکرده): فهرست خالی؛ طول نابرابر؛ `nothing to distribute`/`insufficient contract balance` (مبلغ بیش از موجودی)؛ بازه از غیر `S+1`؛ بازهٔ وارونه؛ `toBlock ≥ block.number`؛ جمع بلاک‌ها > طول بازه؛ **سقف + ۱ wei**؛ آدرس تکراری؛ ترتیب نزولی؛ آدرس صفر؛ آدرس هرگز-فعال‌نشده؛ فرستندهٔ غیر oracle | پیام‌های دقیق بخش پیوست؛ `lastSettledBlock`، `epochCount` و موجودی‌ها بدون تغییر |
| D02 | **اولین توزیع موفق** با بازهٔ `[1, L]` و `totalRewards` = سقف **دقیق** | `status=1`؛ `lastSettledBlock==L`؛ `epochCount==1`؛ `epochBlockRanges(1)`؛ پرداخت هر ولیدیتور = `rewardShare + feeShare` طبق فرمول قرارداد؛ ۱۵٪ پاداش به Foundation؛ باقی‌ماندهٔ پاداش و خردهٔ گردکردن به Treasury؛ ۳۰٪ **کارمزد عادی** سوزانده؛ معادلهٔ بقای موجودی `0x2222` بسته شود |
| D03 | توزیع بلافاصله بعد از D02 | رد با `too soon since last distribution` |
| D04 *(مسیر M)* | بازهٔ پیوستهٔ دوم `[L₁+1, L₂]` پس از ≥ ۲۳ ساعت | موفق؛ `from == lastSettledBlock+1` بدون شکاف؛ بقای موجودی |
| D05 *(مسیر M)* | **تسویهٔ عقب‌مانده:** یک پنجرهٔ مجاز را عمداً رد کن، سپس یک بازهٔ ≥ ۲×۲۷٬۶۰۰ بلاک را یک‌جا تسویه کن | موفق؛ تعداد بلاک هر تولیدکننده درست؛ تولیدکنندهٔ بعداً معلق‌شده سهمش را می‌گیرد |
| D06 | رفتار اسکریپت آزمایشی در شمارش ناقص (مجموع بلاک‌ها ≠ طول بازه) | اسکریپت **نمی‌فرستد** و هشدار می‌دهد؛ `lastSettledBlock` تکان نمی‌خورد. این **اثبات رفتار Router نیست** |

### گروه E — هزینهٔ پرداخت در برابر تعداد ولیدیتور، تعداد تغییر نرخ و gasLimit

**روش:** برای هر `gasLimit` در {۱۵M، ۳۰M، ۶۰M} یک شبکهٔ جدا (فقط ۵ نود) با seed آزمایشی `TEST-ONLY-SEED` بساز:
- **۱۵۰ آدرس payee** با `everActivated=true` که **ولیدیتور فعال نیستند** (QBFT را تغییر نمی‌دهند). موقعیت اسلات از `storageLayout` همان کامپایل خوانده شود.
- **تاریخچهٔ نرخ با ۳۹۹ ورودی** با `startBlock = ۱۵۱ + i` برای `i=0..398` (بلاک‌های ۱۵۱ تا ۵۴۹) و نرخ همه ۲×۱۰¹⁸. (قرارداد این تاریخچه را در genesis نمی‌پذیرد مگر با seed مستقیم storage؛ همین دلیل برچسب آزمایشی است.)
- برای حالت `(N, k)`: بازهٔ `[1, toBlock]` با `toBlock = ۱۵۰ + k`، هر payee با ۱ بلاک (`N ≤ ۱۵۰`)، `totalRewards = min(سقف, موجودی − totalFees)`.
- **قبل از اولین توزیع** (`epochCount==0`، پس بدون قفل ۲۳ ساعته) برای همهٔ ترکیب‌ها `eth_estimateGas` بگیر؛ سپس **یک توزیع واقعی** با سنگین‌ترین ترکیبِ جاشونده بفرست و `gasUsed` واقعی را با تخمین مقایسه کن.

| ID | ماتریس | ثبت |
|---|---|---|
| E01 | `N ∈ {5, 25, 50, 100, 150}` × `k ∈ {0, 1, 20, 100, 399}` برای هر gasLimit | تخمین گاز، یا خطای خام «بیش از gasLimit» (نشانهٔ جانشدن نیست) |
| E02 | هزینهٔ marginal هر payee و هر تغییر نرخ (برازش خطی روی ماتریس) | اعداد؛ مقایسه با ~۲٬۸۰۰ گس به‌ازای هر تغییر در `maxRewardsForRange` (مرجع Hardhat، فقط برای مقایسه) |
| E03 | `eth_estimateGas` خودِ `maxRewardsForRange(1, toBlock)` برای هر k | مقایسه با مرجع Hardhat |
| E04 | بزرگ‌ترین `N` در `k=۰` و بزرگ‌ترین `k` در `N=۵` و `N=۱۰۰` که برای هر gasLimit جا می‌شود | دو معیار: «جا می‌شود» (`≤ gasLimit`) و «با حاشیه» (`≤ ۵۰٪ gasLimit`) |
| E05 | توزیع واقعی سنگین‌ترین ترکیب جاشونده | `gasUsed` واقعی، نسبت به تخمین، و رسید |

**این آزمون gasLimit production را تعیین نمی‌کند.** اگر ترکیبی (مثلاً `N=۱۵۰` یا `k=۳۹۹`) در gasLimit فرضی جا نشد، فقط همین را با عدد گزارش کن؛ تصمیم عدد production با مالک است. در گزارش صریح بنویس هر تعداد ولیدیتور بیش از ۱۰۰ «بالاتر از هدف مستندشدهٔ ۵۰–۱۰۰ عضو» است.

### گروه F — تغییر پاداش Besu و هماهنگی با سقف تاریخی

**ابزار اندازه‌گیری:** پاداش هر بلاک را در بلاک‌های **بدون تراکنش** از تغییر موجودی `0x2222` (و با `trace_block`) بخوان. اگر `trace_block` ورودی `reward` برنگرداند یا با روش بلاک خالی نخواند، آن را یافتهٔ جدا گزارش کن.

**قالب transition (باید روی نسخهٔ واقعی راستی‌آزمایی شود، نه مسلم فرض شود):** `config.transitions.qbft = [{ "block": X, "blockreward": "<wei به‌صورت رشتهٔ دهدهی>" }]`. اگر Besu آن را نپذیرفت، خطای خام را ثبت کن و فرمت جایگزین را خودسرانه ننویس؛ سؤال بپرس.

| ID | شبکه | ساخت | آزمون | انتظار |
|---|---|---|---|---|
| F01 | Net-F1 (هماهنگ) | transition در بلاک `X=۳۰۰` به ۳×۱۰¹⁸؛ تاریخچهٔ قرارداد `[(۳۰۰, ۳×۱۰¹⁸)]` (seed آزمایشی) | **مرز دقیق:** پاداش بلاک‌های X−۱، X، X+۱ | بلاک X−۱ با ۲ SUR؛ از کدام بلاک ۳ SUR می‌شود را **گزارش کن**. قرارداد نرخ جدید را از `startBlock` (شاملِ خودِ آن) اعمال می‌کند؛ هر اختلاف یک‌بلاکی **یافتهٔ بحرانی هماهنگی** است |
| F02 | همان | بازهٔ `[1, L]` عبوری از X، با `totalRewards` = مجموع واقعی | سقف و توزیع | پاداش واقعی = سقف دقیقاً؛ توزیع موفق |
| F03 | Net-F2 (ناهماهنگ، پاداش واقعی > سقف) | transition در X؛ تاریخچهٔ قرارداد **خالی** | `distributeRewards` با مجموع واقعی | رد با `totalRewards exceed approved reward for range`؛ **state بدون تغییر؛ `lastSettledBlock` عبور نمی‌کند؛ `totalRewards` را کاهش نده** |
| F04 | Net-F3 (ناهماهنگ، پاداش واقعی < سقف) | تاریخچه `[(۳۰۰, ۳×۱۰¹⁸)]` ولی **بدون** transition در Besu | توزیع | موفق (کنترل مبلغ عبور می‌کند)؛ اسکریپت آزمایشی ناهماهنگی را ثبت و هشدار می‌دهد |
| F05 | Net-F1 | **رفتار تنظیمات:** transition جدید برای بلاک آینده (مثلاً X′ = بلاک جاری + ۳۰۰) به فایل genesis همهٔ نودها اضافه و نودها **یکی‌یکی** ری‌استارت شوند (۵ ولیدیتور؛ تحمل خطای ۱) | آیا زنجیره ادامه می‌دهد؟ آیا Besu فایل تغییریافته را می‌پذیرد؟ آیا پاداش در X′ تغییر می‌کند؟ | **فرض عملیاتی «تغییر فایل + ری‌استارت لازم است» را تأیید یا رد کن** و خروجی خام بیاور |
| F06 | Net-F1 + X7 | نود تازه‌ای با genesis **بدون** transition پس از عبور زنجیره از X راه بیفتد | همگام‌سازی | رفتار را ثبت کن (انتظار فرضی: شکست در بلاک X به‌خاطر اختلاف state؛ **تأییدنشده**). لاگ خام الزامی |
| F07 *(اختیاری، P2)* | Net-F1 | یکی از پنج ولیدیتور با پیکربندی بدون transition اجرا شود | رفتار شبکه | حداکثر یک نود (f=۱)؛ رفتار (round change/توقف/انشعاب) با لاگ ثبت شود |

**مسیر L (اختیاری):** هماهنگی کامل «ثبت در قرارداد → اجرا → اعمال transition روی همهٔ نودها پیش از startBlock → عبور از startBlock» را روی Net-L اجرا کن؛ ترتیب و زمان هر گام ثبت شود.

---

## ۸. پروتکل شکست و ناسازگاری

1. **ثبت شواهد:** شناسهٔ آزمون، انتظار، خروجی واقعی، tx hash و رسید، بلوک، خروجی خام RPC، بریدهٔ لاگ نود، نسخهٔ مبنا.
2. **طبقه‌بندی (فقط برچسب):** باگ قرارداد · باگ ابزار آزمایشی · محیط/زیرساخت · رفتار Besu · ابهام مشخصات. علت را «احتمالی» بنویس مگر مدرک مستقیم داشته باشی.
3. **توقف وابسته‌ها:** آزمون‌هایی که به نتیجهٔ شکست‌خورده تکیه دارند `BLOCKED` شوند؛ مستقل‌ها ادامه یابند.
4. **توقف کامل و گزارش فوری** (یافتهٔ بحرانی) در این موارد: ناهمخوانی hash مبنا؛ شکست A07 یا A08؛ **هر مسیری که سقف را دور بزند** (توزیعی با مجموع بیش از سقف پذیرفته شود)؛ پرداخت به آدرس هرگز-فعال‌نشده؛ ناهماهنگی مرز transition (F01).
5. **ممنوع:** وصلهٔ قرارداد؛ تغییر پارامتر اقتصادی/حکمرانی برای «سبز شدن» آزمون؛ حذف یا کاهش مبلغ برای گذراندن سقف؛ بازتوزیع خودسرانه؛ نوشتن «باگ نیست» بدون مدرک.
6. اگر نتیجه به **تصمیم مالک** بسته است (gasLimit تولیدی، مسیر رفع «پاداش واقعی > سقف»، سرنوشت پاداش بلاک تولیدشده توسط فاقد صلاحیتِ اثبات‌شده)، آن را در `QUESTIONS.md` بیاور، نه در اصلاح.

---

## ۹. بستهٔ شواهد

مسیر: `testing-evidence/besu-live-test-v4-<تاریخ اجرا>/`

```
README.md                    ← راهنمای بسته و جملهٔ پایانی
MANIFEST.sha256              ← hash همهٔ فایل‌های بسته
00-baseline/                 ← جدول hash، خروجی sha256sum -c، compile-settings.json، hash بایت‌کدها، storageLayoutها
01-environment/              ← env.json (Besu/Java/Node/OS/CPU/RAM)، hash tarball Besu
02-genesis/<شبکه>/           ← genesis.json، sha256، config.toml هر نود، static-nodes.json، TEST-KEYS-DO-NOT-REUSE، فهرست seed و overlay
03-commands/commands.log     ← همهٔ فرمان‌ها با زمان؛ run-all.md با ترتیب اجرا
04-results/<ID>.md|json      ← نتیجهٔ هر آزمون (PASS/FAIL/NOT-RUN/BLOCKED/INCONCLUSIVE)
05-raw/                      ← خروجی خام RPC، ردیف‌های collector، رسیدها (tx.csv)
06-logs/<شبکه>/<نود>.log.gz  ← لاگ نودها
REPORT.md                    ← جدول نتیجهٔ همهٔ ID ها + خلاصه
FINDINGS.md                  ← یافته‌های غیرمنتظره با خطای خام
LIMITATIONS.md               ← محدودیت‌ها (بخش ۱۰)
QUESTIONS.md                 ← پرسش‌ها برای مالک
DEVIATIONS.md                ← انحراف از این دستور، با استدلال
```

**برای هر تراکنش (بدون استثنا):** hash، شمارهٔ بلاک، `status`، `gasUsed`، `effectiveGasPrice`، پیام revert کامل و کلمه‌به‌کلمه، مقدار state **قبل و بعد**، زمان دیواری ارسال، و شبکهٔ مربوط.

**`REPORT.md`:** سرصفحه با hash مبنا، نسخه‌ها و فهرست شبکه‌ها؛ سپس جدول: `ID | عنوان | مسیر (S/M/L) | نتیجه | ارجاع شواهد | یادداشت`؛ جمع تعداد هر نتیجه؛ سپس فهرست `NOT-RUN` با علت. **هیچ ردیفی بدون ارجاع به شواهد خام نباشد.**

**جملهٔ پایانی الزامی در `README.md` و `REPORT.md` (بدون تغییر در معنا):**
> این بسته نتیجهٔ آزمون روی Besu با تنظیمات آزمایشی و ابزارهای آزمایشی است. موفقیت یا شکست این آزمون‌ها به‌معنای آمادگی یا عدم آمادگی production نیست. RewardRouter و ابزار genesis production پیاده‌سازی نشده‌اند و این بسته آن‌ها را آزمون نکرده است. gasLimit تولیدی، مسیر رفع «پاداش واقعی بیش از سقف» برای بازهٔ گذشته، و صفحهٔ حکمرانی نرخ در داشبورد همچنان باز هستند.

---

## ۱۰. محدودیت‌ها و موارد باز (در `LIMITATIONS.md` بیاید)

- شواهد این آزمون شبکه‌های آزمایشی تک‌میزبانی‌اند؛ رفتار شبکهٔ چندمیزبانه، تأخیر شبکه و بار واقعی را نمی‌سنجند.
- کنترل‌های زمان‌محور بلندمدت (۱۸۰ روز، ۳۰ روز، تأخیر ۷ روزه) جز مسیر L روی Besu آزموده نمی‌شوند؛ پوشش آن‌ها فقط Hardhat است.
- seed مستقیم storage در گروه‌های E و F آزمایشی است و مسیر production نیست؛ مسیر حکمرانی ثبت نرخ فقط تا مرحلهٔ انتظار (و در مسیر L تا اجرا) روی Besu دیده می‌شود.
- امضاکنندگان فقط اگر الگوریتم بازیابی اعتبارسنجی شد گزارش می‌شوند.
- تأیید پیاده‌سازی T02، RewardRouter، صفحهٔ حکمرانی نرخ و gasLimit تولیدی در دامنهٔ این آزمون نیست.
- بستن مورد T01 («genesis.json و خروجی خام همهٔ فازهای Besu در بسته نیست») تصمیم جدا است؛ این بسته فقط می‌تواند شاهدش را بدهد و هیچ ردیف وضعیتی را خودش بسته اعلام نمی‌کند.
- **چهار مورد باز اعلام‌شده در جدول وضعیت همچنان باز می‌مانند:** (۱) مسیر رفع «پاداش واقعی > سقف» برای بازهٔ گذشته؛ (۲) بررسی gasLimit عملیاتی (این آزمون فقط داده می‌دهد، تصمیم نمی‌گیرد)؛ (۳) پیاده‌سازی و آزمون RewardRouter؛ (۴) صفحهٔ حکمرانی نرخ در داشبورد. همچنین اجرای transition روی Besu واقعی تا پایان مسیر F/L «فرض عملیاتی تأییدنشده» است و بعد از آن فقط به‌اندازهٔ شواهد خام ثبت می‌شود.

---

## پیوست الف — فرمان‌های اجرا (اسکلت؛ مسیرها را با محیط خودت تنظیم کن)

```bash
# فاز ۰
mkdir -p besu-test/{baseline,tools,nets,evidence}; cp -r <Plan>/contracts <Plan>/contracts-fa besu-test/baseline/ && chmod -R a-w besu-test/baseline
(cd besu-test/baseline/contracts && sha256sum -c ../../../sha256-en.txt)      # جدول بخش ۲.۱
(cd besu-test/baseline/contracts-fa && sha256sum -c ../../../sha256-fa.txt)
node tools/testonly-compile.js        # solc 0.8.24، runs=200، بدون viaIR → bytecode/storageLayout/hash
besu --version; java -version; sha256sum besu-26.9.0.tar.gz

# ساخت شبکه
node tools/testonly-genesis-builder.js --net Net-1 --gas-limit 30000000 --founders 5
node tools/testonly-generate-nodes.js --net Net-1
for n in 1 2 3 4 5 6; do besu --config-file=nets/Net-1/node$n/config.toml > nets/Net-1/node$n/node.log 2>&1 & done

# مشاهده
curl -s -X POST localhost:8651 -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"qbft_getValidatorsByBlockNumber","params":["latest"]}'
curl -s -X POST localhost:8651 -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"trace_block","params":["0x64"]}'
curl -s -X POST localhost:8651 -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[{"to":"0x3333333333333333333333333333333333333333","data":"0x…getValidators()"},"0x63"]}'
```

**متدهای RPC مورد نیاز:** `eth_blockNumber`، `eth_getBlockByNumber`، `eth_getCode`، `eth_getStorageAt`، `eth_call` (با پارامتر بلاک)، `eth_estimateGas`، `eth_getTransactionReceipt`، `eth_getBalance`، `qbft_getValidatorsByBlockNumber`، `qbft_getSignerMetrics`، `trace_block`، `admin_peers`، `txpool_besuTransactions`.

## پیوست ب — پیام‌های revert مورد انتظار (از سورس Distributor)

| وضعیت | پیام |
|---|---|
| فرستندهٔ غیر oracle | `BlockRewardDistributor: caller is not the distribution oracle` |
| فهرست خالی | `BlockRewardDistributor: empty validator list` |
| طول نابرابر | `BlockRewardDistributor: length mismatch` |
| فاصلهٔ ۲۳ ساعته | `BlockRewardDistributor: too soon since last distribution` |
| موجودی/مبلغ | `BlockRewardDistributor: nothing to distribute`، `BlockRewardDistributor: insufficient contract balance` |
| بازه | `range must start right after the last settled block`، `empty or inverted block range`، `range includes blocks that are not yet produced`، `reported blocks exceed the range size` (همه با پیشوند `BlockRewardDistributor: `) |
| سقف (L05) | `BlockRewardDistributor: totalRewards exceed approved reward for range` |
| ترتیب (L07) | `BlockRewardDistributor: validators must be strictly ascending` |
| آدرس | `BlockRewardDistributor: zero validator address`، `BlockRewardDistributor: address was never a legitimate validator` |
| تغییر نرخ | `only an active validator may propose a rate change`، `start block is not in the future`، `start block is closer than MIN_RATE_CHANGE_LEAD_BLOCKS`، `start block must be after the last approved rate change`، `not approved by both chambers`، `execution delay has not elapsed`، `voting closed - already approved by both chambers`، `voting period has expired` |
| هیأت/واجدان | `caller has no live board authority`، `board membership changed since this proposal was created - propose again`، `not eligible - not Active when this proposal was created` |

## پیوست پ — مرجع عددی Hardhat (فقط برای مقایسه؛ شاهد Besu نیست)

- هزینهٔ `maxRewardsForRange`، تاریخچهٔ ۴۰۰ ورودی: k=۰: ۴۵٬۶۸۹؛ ۱: ۴۹٬۰۳۳؛ ۵: ۵۶٬۱۷۳؛ ۲۰: ۹۶٬۴۸۴؛ ۴۰: ۱۵۲٬۴۹۷؛ ۱۰۰: ۳۲۶٬۲۸۹؛ ۳۹۹: ۱٬۱۶۰٬۴۵۴ گس (حدود ۲٬۸۰۰ گس به‌ازای هر تغییر برای k ≥ ۲۰).
- نصاب‌ها: هیأت ۳ از ۵؛ مجلس ولیدیتورها `⌈2n/3⌉ = (2n+2)/3` (برای n=۵: ۴، n=۶: ۵، n=۴: ۳)؛ رأی‌دهندهٔ واجد = Active هنگام ساخت پیشنهاد.
- حاصل توزیع: Foundation ۱۵٪ پاداش؛ سهم مستقیم ولیدیتورها `validatorDirectShareBps` (۵۰٪)؛ باقی‌مانده و خردهٔ گردکردن به Treasury؛ ۳۰٪ کارمزد عادی سوزانده؛ کارمزد عضویت معاف از سوزاندن.
- ارتفاع ۲۰۱٬۶۰۰ بلاک ≈ ۷ روز فقط در آهنگ اسمی ۳ ثانیه.
