# گزارش تحلیلی قراردادهای هوشمند شبکه Sur
### اوراکل‌ها و حساب‌های دارای اختیار — کاربرد، اختیارات و روابط بین‌قراردادی

منبع: پوشه `contracts` از مخزن `Alireza-Zojaji/sur-new` — ۸ فایل Solidity

> ✅ **یادداشت بازبینی:** این سند بازبینی و با یک تصحیح واقعی (تناقض داخلی درباره‌ی `paymentOracle`) و چند نکته‌ی تکمیلی (وضعیت فعلی قراردادهای کمکی genesis، و ارجاع به سیاست نگه‌داری کلید) به‌روزرسانی شده. متن اصلی از نظر کیفیت و دقت فنی در سطح بسیار خوبی بود؛ تغییرات این نسخه پایین با علامت ✅/🔶 مشخص شده‌اند.

---

## ۱. معماری کلی و فایل‌های بررسی‌شده

این مجموعه از ۸ قرارداد، زیرساخت یک شبکه بلاکچین با کنسنسوس QBFT (بر پایه Hyperledger Besu) به نام Sur را تشکیل می‌دهد. شش قرارداد آن «ساختاری» هستند و مستقیماً در بلاک genesis تزریق می‌شوند (کد + storage نهایی، بدون تراکنش deploy و بدون constructor)، به همین دلیل آدرس هر شش‌تا از پیش و به‌صورت ثابت در فایل `SurAddresses.sol` تعریف شده و در بقیه‌ی قراردادها به‌صورت constant هارد-کد می‌شود. یک قرارداد (`SurenSale`) ساختاری نیست و بعداً با یک تراکنش عادی دیپلوی می‌شود.

| ثابت (Constant) | آدرس | قرارداد | نقش خلاصه |
|---|---|---|---|
| `FOUNDATION_DAO` | `0x1111...1111` | FoundationDAO.sol | حکمرانی بنیاد Sur (۱۵ عضو) |
| `BLOCK_REWARD_DISTRIBUTOR` | `0x2222...2222` | BlockRewardDistributor.sol | دریافت پاداش بلاک/کارمزد و توزیع بین ولیدیتورها و خزانه |
| `VALIDATORS_REGISTRY` | `0x3333...3333` | ValidatorsRegistry.sol | منبع حقیقت کنسنسوس (`getValidators`) و واجدشرایطی پرداخت (`isValidator`) |
| `VALIDATORS_BOARD` | `0x4444...4444` | ValidatorsBoard.sol | هیئت‌مدیره‌ی کوچک منتخب ولیدیتورها با اختیارات محدود تفویضی |
| `VALIDATORS_TREASURY` | `0x5555...5555` | ValidatorsTreasury.sol | خزانه‌ی سهم ۵۰٪ ولیدیتورها از پاداش + کارمزد عضویت/جریمه |
| `IDENTITY_REGISTRY` | `0x6666...6666` | IdentityRegistry.sol | منبع حقیقت هویت خوداظهاری و وضعیت احراز (تلفن/تلگرام/KYC) برای همه‌ی کاربران شبکه |

قرارداد هفتم، `SurenSale.sol`، جزو شش قرارداد ساختاری نیست؛ قرارداد فروش قسطی/زمان‌بندی‌شده‌ی Suren (۶ ماهه، با رشد ماهانه ۳٪ قیمت) به تومان است که بنیاد هر زمان آماده بود، آن را با یک تراکنش معمولی دیپلوی می‌کند.

✅ **به‌روزرسانی معماری تازه:** هر چهار آدرس اوراکل عملیاتی (`distributionOracle`, `verifier`, `identityOracle`, `paymentOracle`) هم اکنون **متمرکز در همین `SurAddresses.sol`** تعریف شده‌اند (به‌عنوان ثابت‌های `DISTRIBUTION_ORACLE`, `VERIFIER`, `IDENTITY_ORACLE`, `PAYMENT_ORACLE`)، و هر چهار قرارداد مصرف‌کننده — حتی `SurenSale` که genesis-injected نیست — مقدار اولیه‌شان را از همین‌جا می‌خوانند، نه این‌که آدرس را دوباره در خودشان هاردکد کنند. تفاوت مهم با شش آدرس ساختاری بالا: آدرس‌های ساختاری واقعاً تغییرناپذیرند (چون در بایت‌کد genesis جاسازی‌شده‌اند)، ولی هر چهار اوراکل همچنان در state معمولی و **قابل‌چرخش** (`setDistributionOracle`, `setVerifier`, `setIdentityOracle`, `setPaymentOracle`) قرار دارند — `SurAddresses.sol` فقط مقدار *اولیه*شان را یک‌جا نگه می‌دارد، برای این‌که به‌روزرسانی قبل از genesis/دیپلوی فقط نیازمند ویرایش یک خط باشد، نه گشتن در چهار فایل جدا.

---

## ۲. اوراکل‌ها (کلیدهای عملیاتی گزارش‌دهنده)

در این پروژه «اوراکل» به یک آدرس عملیاتی (نه یک قرارداد جداگانه‌ی Chainlink-مانند) گفته می‌شود: یک کلید که مسئول گزارش دادن داده‌های خارج از زنجیره یا خارج از دسترس مستقیم قرارداد است، و می‌تواند توسط نهاد بالادستی (Board یا Foundation) چرخانده (rotate) شود.

| نام | قرارداد میزبان | کاربرد اصلی | چرخش توسط |
|---|---|---|---|
| `distributionOracle` | BlockRewardDistributor | گزارش تعداد بلاک هر ولیدیتور و مجموع reward/fee هر epoch؛ فراخوانی `distributeRewards` | ValidatorsBoard (رأی اکثریت داخلی board) |
| `verifier` | ValidatorsRegistry | گزارش زنده‌بودن (liveness) ولیدیتورها؛ `reportLiveness` | ValidatorsBoard (رأی اکثریت داخلی board) |
| `identityOracle` | IdentityRegistry | ثبت نتیجه احراز تلفن/تلگرام/KYC و مهاجرت هویت | فقط FoundationDAO |
| `paymentOracle` | SurenSale | گزارش پرداخت‌های تومانی تأییدشده و واریز Suren معادل | فقط FoundationDAO (اکثریت ساده) |

### ۲.۱ `distributionOracle` — در BlockRewardDistributor
- **کاربرد:** تنها فراخوان‌کننده‌ی مجاز تابع `distributeRewards` است؛ لیست ولیدیتورها، تعداد بلاک هر کدام، و مجموع reward/fee هر epoch را گزارش می‌دهد (حداقل فاصله بین دو فراخوانی: ۲۳ ساعت).
- **اختیارات:** می‌تواند زمان‌بندی و مقدار توزیع را تعیین کند، اما نمی‌تواند به آدرسی که در ValidatorsRegistry واجد شرایط (`isValidator`) نیست پرداخت کند — این بررسی مستقیماً روی زنجیره انجام می‌شود، بدون واسطه.
- **محدودیت طراحی حذف‌شده:** نسخه‌ی قدیمی یک «`validatorSyncOracle`» جداگانه هم داشت که کاملاً حذف شده؛ ValidatorsRegistry اکنون تنها منبع حقیقت است.
- ✅ **به‌روزرسانی:** مقدار `distributionOracle` دیگر placeholder نیست — نهایی و هاردکد شده: `0xbCBAc7d286eA11EC57fb4e0f5D16d960D6d202b6` (چک‌سام‌شده طبق EIP-55).

### ۲.۲ `verifier` — در ValidatorsRegistry
- **کاربرد دوگانه:** هم گزارش وضعیت آنلاین/سینک‌بودن نود در دوره Probation/Demoted (recovery)، و هم گزارش تولید واقعی بلاک (فیلد miner/coinbase) برای ولیدیتورهای Active — از طریق تابع `reportLiveness`.
- **جایگزین طرح قدیمی:** این نقش، مکانیزم قبلیِ `heartbeat()` خوداظهاری (که فقط ثابت می‌کرد یک کیف‌پول می‌تواند امضا کند، نه اینکه نود واقعاً بالا و در حال کار است) را کاملاً جایگزین کرده است.
- **اختیارات:** فقط می‌تواند true/false ثبت کند؛ گزارش منفی صرفاً لاگ (رویداد) می‌شود و شمارنده‌ای را تغییر نمی‌دهد — چون تشخیص غیرفعالی بر پایه‌ی «نبودِ» تأییدهای مثبت در طول زمان است، نه یک پرچم مستقیم.
- کاملاً مستقل از `identityOracle` در IdentityRegistry است — با اینکه هر دو «کلید تأیید» هستند، عمداً از هم جدا نگه داشته شده‌اند.
- ✅ **به‌روزرسانی:** آدرس نهایی `verifier`: `0x1A5E86f3333291B3332C0f9Eddb04269940566bc` (چک‌سام‌شده طبق EIP-55).

### ۲.۳ `identityOracle` — در IdentityRegistry
- **کاربرد:** نتیجه‌ی سرویس‌های احراز هویت آفلاین (تأیید شماره موبایل، تلگرام، و eKYC کامل شامل تطبیق چهره) را روی زنجیره ثبت می‌کند: `setPhoneVerified`، `setTelegramVerified`، `setKycVerified`.
- **اختیار ویژه‌ی مهاجرت هویت:** تابع `migrateIdentity` نیز فقط توسط این اوراکل قابل فراخوانی است — انتقال کامل وضعیت هویت از یک آدرس گم‌شده/مختل‌شده به آدرس جدید، پس از یک فرایند احراز مستقل آفلاین.
- هیچ داده خام (کدملی/تصویر/شماره واقعی) هرگز روی زنجیره ذخیره نمی‌شود؛ فقط پرچم‌های boolean و یک commitment هش‌شده (فقط برای اثبات عدم دستکاری در دعاوی حقوقی احتمالی، هرگز برای matching استفاده نمی‌شود).
- تنها اوراکلی است که زیر کنترل ValidatorsBoard نیست — چون احراز هویت مسئولیت بنیاد است، نه هیئت‌مدیره‌ی ولیدیتورها؛ چرخش آن (`setIdentityOracle`) فقط با `onlyFoundation` ممکن است.
- ✅ **به‌روزرسانی:** آدرس نهایی `identityOracle`: `0xbE7e65512Eada6F4c6a9DEDDf2eFb75547A065e9` (چک‌سام‌شده طبق EIP-55).

### ۲.۴ `paymentOracle` — در SurenSale
- **کاربرد:** چون پرداخت تومانی یک دارایی on-chain نیست، این اوراکل (با نام PaymentReporter در کامنت‌ها) پرداخت‌های تأییدشده‌ی درگاه بانکی را با شناسه یکتا گزارش می‌کند (`reportPayment`) و باعث واریز خودکار Suren معادل به خریدار می‌شود.
- **طراحی امنیتی مهم:** قیمت هر ماه (جدول ۶ عضوی `monthlyPriceToman`) کاملاً و مستقل از `block.timestamp` محاسبه می‌شود، نه از گزارش اوراکل — یعنی حتی اگر کلید `paymentOracle` کاملاً به خطر بیفتد، مهاجم فقط می‌تواند «ادعای پرداخت دروغین» کند (خالی‌کردن موجودی فعلی قرارداد)، هرگز نمی‌تواند خودِ قیمت را دستکاری کند.
- **توصیه‌ی امنیتی درج‌شده در کد:** بنیاد نباید کل ۲۰ میلیون Suren را یک‌جا به این قرارداد واریز کند؛ باید تنها بخشی (مثلاً ماهانه) واریز شود تا سقف زیانِ ممکنِ ناشی از افشای کلید محدود بماند.
- **چرخش:** از طریق `FoundationDAO.proposeExecute` با اکثریت ساده (نه دو-سوم) — چون حداکثر زیان ممکن با تزریق دوره‌ای (نه یک‌جا) محدود نگه داشته می‌شود.
- ✅ **به‌روزرسانی مهم (تغییر معماری):** برخلاف توضیح قبلی این سند، `paymentOracle` دیگر آرگومان `constructor` نیست — طبق تصمیم صریح پروژه، مستقیم و هاردکد در سورس نوشته شده، دقیقاً مثل سه اوراکل دیگر: `0xc1fF1F40F665404fbf7DaAD26153357C544C35A0` (چک‌سام‌شده طبق EIP-55). `constructor` این قرارداد دیگر هیچ پارامتری نمی‌گیرد (فقط `saleStartTime = block.timestamp` را تنظیم می‌کند). این یعنی برای دیپلوی این قرارداد در محیط دیگری (مثلاً تست‌نت) با اوراکل متفاوت، باید سورس ویرایش و دوباره کامپایل شود — یک تبادل آگاهانه‌ی انعطاف‌پذیری در برابر یکدستی الگوی چهار اوراکل.

---

## ۳. حساب‌ها و نهادهای دارای اختیار (غیر اوراکل)

علاوه بر اوراکل‌ها، چند «حساب/نقش» جمعی یا نهادی در این قراردادها اختیارات مشخصی دارند: مجموعه‌ای از آدرس‌ها که با شرط‌های modifier (`onlyMember`، `onlyActiveValidator`، `onlyBoardMember` و…) شناسایی می‌شوند، نه یک کلید تکی.

### ۳.۱ اعضای FoundationDAO (۱۵ نفر، در genesis تزریق می‌شوند)
- **قرارداد میزبان:** FoundationDAO.sol — بدون constructor؛ ۱۵ عضو اولیه توسط ابزار ساخت genesis (شبیه‌سازی یا نوشتن مستقیم storage) تزریق می‌شوند.
- **انواع پیشنهاد (Proposal):** `AddMember`، `RemoveMember`، `SendETH` (نیازمند اکثریت دوسوم — `ceil(2n/3)`) و `SendERC20`، `Execute` (اکثریت ساده — `floor(n/2)+1`).
- `SendETH` در واقع همان مسیر توزیع ۲۰,۰۰۰,۰۰۰ Suren تخصیص‌یافته در genesis به این قرارداد است (ماده ۳-۶ منشور بنیاد) — چون Suren ارز بومی است نه توکن، نیازی به قرارداد توزیع جداگانه نیست.
- **محدودیت صریح حکمرانی:** این قرارداد هیچ کنترلی روی شبکه، ولیدیتورها یا هیچ اوراکلِ مرتبط با اجماع ندارد؛ مسیر قدیمی `proposeRequestTreasuryBudget` (درخواست بودجه از ValidatorsTreasury) و اختیار `setDistributionOracle`/`setValidatorSyncOracle` که قبلاً تحت نام MemberDAO داشت، به‌طور کامل حذف شده‌اند.
- عضویت در این DAO منافاتی با ولیدیتور بودن یا عضویت در ValidatorsBoard ندارد — هیچ کدام از قراردادها این هم‌پوشانی را بررسی یا محدود نمی‌کنند.
- ✅ **وضعیت فعلی (تکمیل این بخش):** نام و اسکلت آدرس هر ۱۵ عضو مؤسس از قبل در قرارداد کمکی موقت `contracts/genesis-seed-helpers/FoundationDAO_GenesisSeed.sol` هاردکد شده (Abbas Ashtiani، Alireza Zojaji، Amirabbas Emami، Citex Corp.، Hojjat Abbasi، Kamyar Sharafi، Kaveh Moshtagh، Mahdi Noori، Mahkameh Sharifzad، Maryam Nemati، Mostafa Naghipoorfar، Sepehr Mohammadi، Siavash Tafazzoli، Soheil Nikzad، Yashar Rashedi) — فقط خودِ آدرس‌های `0x0000...` هنوز placeholder‌اند و باید پیش از اجرای واقعی ابزار genesis با آدرس‌های واقعی جایگزین شوند.

### ۳.۲ ولیدیتورهای فعال (Active Validators)
- **قرارداد میزبان اصلی:** ValidatorsRegistry.sol — چرخه‌ی وضعیت:
  `None → Probation (قفل سپرده، تأیید سینک نود) → Active (در getValidators، واجد پرداخت) → [غیرفعالی مداوم] → Demoted (سپرده تا حدی slash می‌شود) → [بازیابی] → Active`، یا در هر مرحله `→ Exiting (خروج داوطلبانه با cooldown)`.
- **ورود:** `requestMembership` با پرداخت مجموع دو مبلغ — collateral (`currentEntryThreshold`، رشد پیوسته/ترکیبی با هر ولیدیتور جدید) که در همین قرارداد قفل و قابل استرداد می‌ماند، و membership fee (درصدی از collateral) که بلافاصله و غیرقابل‌بازگشت به ValidatorsTreasury می‌رود.
- **اختیار حکمرانی امنیتی (Full Validator Vote):** `proposeParameterChange`/`voteParameterChange` در ValidatorsRegistry — پارامترهایی مثل نرخ محدودیت ورود، طول دوره probation، آستانه‌های liveness/غیرفعالی، دوره بازیابی، درصد slash، و cooldown خروج، فقط با اکثریت کامل ولیدیتورهای فعال قابل تغییرند (نه بنیاد، نه board).
- **اختیار در ValidatorsTreasury:** `proposeExpenditure`/`voteExpenditure` (مسیر ۱ — رأی اکثریت کامل ولیدیتورهای فعال) و `proposeSmallBudgetCap` برای تغییر سقف بودجه‌ی قابل‌تصویب board.
- **اختیار در ValidatorsBoard:** `voteFor`/`unvoteFor` — رأی تأییدی برای عضویت در board (پیش‌نیاز: ثبت هویت خوداظهاری در IdentityRegistry از طریق `registerIdentity`).
- **دریافت‌کننده‌ی پرداخت در BlockRewardDistributor:** بررسی واجدشرایطی مستقیماً با `REGISTRY.isValidator` انجام می‌شود.
- ✅ **وضعیت فعلی (تکمیل این بخش):** فهرست ۷ ولیدیتور مؤسس از قبل در قرارداد کمکی `ValidatorsRegistry_GenesisSeed.sol` هاردکد شده (Alireza Zojaji، Citex Corp. ۱، Citex Corp. ۲، Mahkameh Sharifzad، Mostafa Naghipoorfar، Sepehr Mohammadi، Siavash Tafazzoli) — فقط آدرس‌ها و genesis timestamp هنوز placeholder‌اند.

### ۳.۳ اعضای ValidatorsBoard (۵ نفر، بدون فرآیند عزل مستقیم)
- **قرارداد میزبان:** ValidatorsBoard.sol — عضویت با رأی تأییدی (approval voting) از سوی ولیدیتورهای فعال تعیین می‌شود؛ هر ولیدیتور فعال می‌تواند تا ۵ نامزد را رأی دهد و هر زمان پس بگیرد؛ بدون کوروم یا بازه‌ی زمانی.
- **بازآوری (`refreshBoard`):** permissionless، هر کسی می‌تواند فراخوانی کند؛ ۵ نامزد با بیشترین رأیِ فعلاً معتبر (فقط رأی‌دهنده و نامزدِ هر دو فعال) جایگزین ترکیب فعلی می‌شوند — بدون مرحله‌ی جداگانه‌ی «عزل»؛ کافی است حمایت کافی از دست برود یا فرد دیگر فعال نباشد.
- **پاک‌سازی رأی‌های راکد (`clearStaleVotes`):** permissionless، وقتی ولیدیتوری بیش از (دوره بازیابی + ۳۰ روز) پیوسته Demoted بماند، هر کسی می‌تواند رأی‌های داده‌شده و دریافتی او را حذف کند.
- **اختیارات تفویضی board** (نیازمند رأی اکثریت داخلی اعضای board، نه یک نفر):
  1. `proposeRotateOracle` → چرخش `distributionOracle` در BlockRewardDistributor (برای موارد اضطراری/افشای کلید).
  2. `proposeApproveBudget` → تصویب هزینه‌های کوچک روتین در ValidatorsTreasury (زیر سقف `smallBudgetCap`).
  3. `proposeSetEntryThresholdBase` / `proposeSetGrowthFactorPerValidator` / `proposeSetMembershipFeeBps` → تنظیم پارامترهای اقتصادی ورود در ValidatorsRegistry.
  4. `proposeRotateVerifier` → چرخش `verifier` در ValidatorsRegistry.
- **محدودیت صریح:** board نمی‌تواند پارامترهای امنیتی سطح‌بالاتر (نرخ محدودیت ورود، probation، liveness، slashing، cooldown) یا سقف بودجه‌ی خودش را تغییر دهد؛ آن‌ها فقط با رأی کامل ولیدیتورها ممکن‌اند. board همچنین نمی‌تواند آدرس هیچ قرارداد ساختاری را تغییر دهد (این آدرس‌ها constant در زمان کامپایل‌اند).
- ✅ **وضعیت فعلی (تکمیل این بخش):** ۵ عضو مؤسس هیأت از قبل در قرارداد کمکی `ValidatorsBoard_GenesisSeed.sol` هاردکد شده (Alireza Zojaji، Citex Corp.، Mahkameh Sharifzad، Sepehr Mohammadi، Siavash Tafazzoli).

### ۳.۴ خودِ قراردادهای ساختاری، به‌عنوان «حساب» فراخوان‌کننده
چون اختیارات `onlyFoundation` و `onlyBoard` در عمل یعنی «فقط زمانی که msg.sender برابر آدرس ثابت قرارداد FoundationDAO یا ValidatorsBoard باشد»، این دو قرارداد خودشان هم به‌عنوان یک «حساب واحد» در قراردادهای دیگر عمل می‌کنند — فراخوانی همیشه از داخل منطق رأی‌گیری خودشان (Execute proposal برای Foundation، یا `_voteAction` برای Board) صادر می‌شود، هرگز مستقیماً توسط یک عضو منفرد.

---

## ۴. جدول تقاطع — هر اوراکل/حساب در کدام قرارداد به کار رفته

| اوراکل / حساب | قراردادهای مرتبط | نوع ارتباط |
|---|---|---|
| `distributionOracle` | BlockRewardDistributor، ValidatorsBoard | تعریف/استفاده در BlockRewardDistributor؛ چرخش توسط ValidatorsBoard |
| `verifier` | ValidatorsRegistry، ValidatorsBoard | تعریف/استفاده در ValidatorsRegistry؛ چرخش توسط ValidatorsBoard |
| `identityOracle` | IdentityRegistry، FoundationDAO | تعریف/استفاده در IdentityRegistry؛ چرخش توسط FoundationDAO |
| `paymentOracle` | SurenSale، FoundationDAO | تعریف/استفاده در SurenSale؛ چرخش توسط FoundationDAO |
| اعضای FoundationDAO | FoundationDAO، IdentityRegistry، SurenSale | حکمرانی مستقیم در FoundationDAO؛ کنترل اوراکل‌های identityOracle و paymentOracle |
| ولیدیتورهای فعال | ValidatorsRegistry، BlockRewardDistributor، ValidatorsBoard، ValidatorsTreasury | عضویت/حکمرانی امنیتی در Registry؛ دریافت پرداخت از Distributor؛ رأی عضویت board؛ رأی هزینه‌ی خزانه |
| اعضای ValidatorsBoard | ValidatorsBoard، BlockRewardDistributor، ValidatorsTreasury، ValidatorsRegistry | حکمرانی داخلی در Board؛ چرخش اوراکل توزیع؛ تصویب بودجه کوچک؛ پارامترهای اقتصادی و چرخش verifier |
| `FOUNDATION_DAO` (آدرس) | IdentityRegistry، SurenSale | ثابت `FOUNDATION` در هر دو، برای اعمال modifier `onlyFoundation` |
| `BLOCK_REWARD_DISTRIBUTOR` (آدرس) | ValidatorsBoard | ثابت `DISTRIBUTOR` برای چرخش اوراکل |
| `VALIDATORS_REGISTRY` (آدرس) | BlockRewardDistributor، ValidatorsBoard، ValidatorsTreasury | ثابت `REGISTRY` برای بررسی `isValidator`/`getValidators` |
| `VALIDATORS_BOARD` (آدرس) | BlockRewardDistributor، ValidatorsRegistry، ValidatorsTreasury | ثابت `BOARD` برای اعمال modifier `onlyBoard` |
| `VALIDATORS_TREASURY` (آدرس) | BlockRewardDistributor، ValidatorsRegistry، ValidatorsBoard | ثابت `TREASURY`، مقصد سهم پاداش/کارمزد عضویت/جریمه/بودجه‌ی تصویب‌شده |
| `IDENTITY_REGISTRY` (آدرس) | ValidatorsBoard | ثابت `IDENTITY_REGISTRY`، بررسی `hasIdentity` پیش از `voteFor` |

---

## ۵. جریان مالی بین قراردادها (Suren، ارز بومی شبکه)

- پاداش بلاک + کارمزد تراکنش‌ها (سطح پروتکل، بدون فراخوانی EVM) → BlockRewardDistributor به‌عنوان `miningbeneficiary`.
- از مجموع پاداش‌ها (Rewards): ۵۰٪ (`TREASURY_SHARE_BPS`) → ValidatorsTreasury؛ باقی‌مانده متناسب با تعداد بلاک تولیدی بین ولیدیتورها.
- از مجموع کارمزدها (Fees): ۱۰۰٪ متناسب با تعداد بلاک تولیدی بین ولیدیتورها — بدون هیچ سهمی برای خزانه.
- در ValidatorsRegistry: کارمزد عضویت (membership fee) هر ولیدیتور جدید + سپرده‌ی جریمه‌شده (slashed) در غیرفعالی → مستقیماً به ValidatorsTreasury.
- در FoundationDAO: ۲۰,۰۰۰,۰۰۰ Suren تخصیص‌یافته در genesis، فقط از طریق `proposeSendETH` (دوسوم رأی) قابل خروج است — از جمله برای تأمین دوره‌ای SurenSale.
- ValidatorsTreasury دو مسیر خرج دارد: ۱) رأی کامل ولیدیتورهای فعال (بدون سقف)، ۲) تصویب board برای مبالغ کوچک زیر `smallBudgetCap` (که خودش فقط با رأی کامل ولیدیتورها قابل تغییر است، نه توسط board).

---

## ۶. نکات مهم دیگر برای مستندسازی/ممیزی

- **استقرار genesis:** شش قرارداد ساختاری constructor ندارند (چون هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود) — مقادیر اولیه (اعضای بنیاد، ولیدیتورهای اولیه، اعضای board، پارامترهای امنیتی، و آدرس‌های اولیه‌ی هر چهار اوراکل) باید توسط یک ابزار آفلاین genesis-building یا با شبیه‌سازی روی یک chain موقت، یا با محاسبه‌ی مستقیم storage slots، تزریق شوند.
- ✅ **به‌روزرسانی نهایی — هر چهار آدرس اوراکل تعیین و هاردکد شدند:**

| اوراکل | آدرس نهایی (چک‌سام‌شده EIP-55) |
|---|---|
| `distributionOracle` | `0xbCBAc7d286eA11EC57fb4e0f5D16d960D6d202b6` |
| `verifier` | `0x1A5E86f3333291B3332C0f9Eddb04269940566bc` |
| `identityOracle` | `0xbE7e65512Eada6F4c6a9DEDDf2eFb75547A065e9` |
| `paymentOracle` | `0xc1fF1F40F665404fbf7DaAD26153357C544C35A0` |

هر چهارتا اکنون مستقیم در سورس هاردکد شده‌اند — از جمله `paymentOracle`، که طبق یک تصمیم تازه‌ی پروژه، از حالت آرگومان `constructor` (توضیح‌داده‌شده در نسخه‌ی قبلی این بند) به همان الگوی سه اوراکل دیگر (هاردکد مستقیم) تغییر کرد؛ `constructor` قرارداد `SurenSale` دیگر هیچ پارامتری نمی‌گیرد.
- ✅ **تکمیل — وضعیت فعلی داده‌های genesis:** برخلاف زمان نگارش اولیه‌ی این سند، اسامی (نه آدرس‌ها) هر ۱۵ عضو بنیاد، هر ۷ ولیدیتور مؤسس، و هر ۵ عضو هیأت از قبل در قراردادهای کمکی موقت (`contracts/genesis-seed-helpers/*_GenesisSeed.sol`) هاردکد شده‌اند؛ این قراردادهای کمکی هم دیگر آرگومان constructor نمی‌گیرند — مقادیر مستقیم در بدنه‌شان با علامت `🔶 FILL_IN` نوشته شده‌اند. فقط خودِ آدرس‌های `0x0000...0000` (و genesis timestamp) هنوز باید با مقادیر واقعی جایگزین شوند. جزئیات کامل در `sur-genesis-builder-tool-spec.md`.
- 🔶 **نکته‌ی عملیاتی تکمیلی (خارج از اسکوپ تحلیل سورس، ولی مرتبط):** طبق سیاست کلی پروژه (`sur-software-inventory.md`)، کلیدهای عملیاتی `distributionOracle` و `verifier` — تنها دو اوراکلی که یک سرویس آف‌چین واقعی (به ترتیب RewardRouter و Verifier) پشت‌شان کلید خصوصی نگه می‌دارد — باید در HashiCorp Vault ذخیره شوند، هرکدام با policy/token کاملاً مستقل از هم. `identityOracle` و `paymentOracle` هم به همین شکل باید نگه‌داری شوند اگر سرویس‌های Identity Service/PaymentReporter پشتشان کلید خصوصی مستقل دارند.
- ✅ **وضعیت به‌روز‌شده:** آدرس اولیه‌ی هر چهار اوراکل دیگر placeholder نیست (بند بالا را ببین) — پارامترهای امنیتی دیگر `ValidatorsRegistry` (`probationPeriod`، `slashBps`، `exitCooldown` و…) هنوز placeholder صفر/`0x0` هستند (علامت‌گذاری‌شده با 🔶 FILL_IN) و پیش از استقرار واقعی باید با مقادیر نهایی جایگزین شوند.
- **طرح‌های حذف‌شده (Retired):** `validatorSyncOracle` جداگانه، `heartbeat()` خوداظهاری، `proposeRequestTreasuryBudget` در FoundationDAO، و کنترل قدیمی MemberDAO بر `setDistributionOracle`/`setValidatorSyncOracle` — همگی به‌طور کامل از کد حذف شده‌اند، نه صرفاً deprecated.
- **جداسازی عمدی حکمرانی در ValidatorsRegistry:** پارامترهای اقتصادی ورود (`entryThresholdBase`، `growthFactorPerValidator`، `membershipFeeBps`) فقط زیر کنترل board هستند (چون نیاز به تنظیم مکرر دارند)؛ بقیه‌ی پارامترهای امنیتی فقط با رأی کامل ولیدیتورهای فعال قابل تغییرند.
- محافظ reentrancy (`nonReentrant`) در BlockRewardDistributor، ValidatorsRegistry و ValidatorsTreasury پیاده‌سازی شده است.
- IdentityRegistry برای همه‌ی کاربران شبکه است، نه فقط ولیدیتورها — و عمداً از ValidatorsRegistry جدا نگه داشته شده تا یک باگ در منطق ولیدیتورها هرگز روی داده‌ی هویتی کل شبکه اثر نگذارد.
- BlockRewardDistributor به دلیل محدودیت عمق پشته‌ی EVM (Stack too deep) به سه تابع داخلی (`_sumBlocks`، `_payValidators`/`_payOneValidator`، `_finalizeEpoch`) شکسته شده — بدون تغییر در رفتار یا ترتیب رویدادها — تا نیازی به فعال‌سازی viaIR نباشد (که برخی سرویس‌های verify مانند Blockscout از آن پشتیبانی نمی‌کنند).
- SurenSale تنها قراردادی است که constructor واقعی دارد و بعد از genesis، با یک تراکنش معمولی دیپلوی می‌شود؛ ✅ اما `constructor`ش دیگر هیچ پارامتری نمی‌گیرد — `paymentOracle` هم مثل سه اوراکل دیگر مستقیم در سورس هاردکد شده (بند بالا را ببین)، نه آرگومان سازنده.
