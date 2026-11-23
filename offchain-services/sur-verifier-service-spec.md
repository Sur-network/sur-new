# مشخصات فنی سرویس آف‌چین Verifier

> **بررسی توافق‌نامه پیش از فعال‌سازی (تصمیم مالک ۲۰۲۶-۱۱-۲۳):** Verifier پیش از `recordActivation` امضای متقاضی را از آرشیو توافق‌نامه (سرویس ۱۹) می‌گیرد، EIP-712 را خودش بازیابی می‌کند و برای ورود مستقیم هش را با `seatAgreementHash`/`EntryAgreementRecorded` تطبیق می‌دهد؛ برای لاتاری و مؤسسان فقط آرشیو. امضای بنیاد شرط نیست. آرشیو در دسترس نباشد: فعال نمی‌کند. مشخصات: `sur-agreement-archive-spec.md`.

> **هم‌ترازی با قراردادها (۲۰۲۶-۱۱-۲۳):** این مشخصات پس از کامیت‌های `11ff741` و `187c7dd` با `contracts/` هم‌تراز شد (۱۸۶ آزمون Hardhat در ۲۱ فایل). تغییرهای مؤثر بر Verifier: (۱) هر پنجرهٔ ورود حداکثر **یک** ورودی پرداخت‌کننده دارد و ثابت است؛ شمارش در **فعال‌سازی** است و `recordActivation` برای ورودی پرداخت‌کننده با «entry window used - only one new paid validator per window» رد می‌شود (`lastPaidActivationAt`، `nextPaidActivationAllowedAt()`)؛ (۲) خریدار پیش از انتقال NFT باید `acceptSeatAgreement(seatId, hash)` را بزند؛ `acceptSeatTransfer`، `seatTransferPending`، `seatAcceptDeadline` و رویداد `SeatTransferAccepted` حذف شدند و جایشان `SeatAgreementAccepted`، `SeatAcceptanceRevoked`، `SeatAgreementBound` است؛ (۳) برای گم‌شدن کلید مالک مسیر قراردادی `ValidatorsRegistry.migrateSeat(old, new)` (فقط Verifier، پس از `migrateIdentity` اوراکل هویت) و رویداد `SeatMigrated` وجود دارد؛ (۴) `slashBps` (۱٪) و `probationPeriod` (۷ روز) ثابت‌اند و رأی‌پذیر نیستند. بندهای «هنوز نوشته نشده» و «هیچ کد سرویسی نوشته نشده» در دو بند بعدی (۲۰۲۶-۱۱-۱۹ و ۲۰۲۶-۱۱-۲۰) تاریخی‌اند و **منسوخ شده‌اند (۲۰۲۶-۱۱-۲۳)**: Verifier و `RewardRouter`، `SurKMS`، Identity Service، GenesisBuilder، NodeCheck و EventIndexer ساخته و روی Besu آزموده شده‌اند؛ حدود نرخ پاداش اکنون در کد اعمال و آزموده می‌شود. **کار کدی باقی‌مانده در Verifier:** یک ورودی پرداخت‌کننده در هر پنجره هنگام `recordActivation`؛ بازپخش `SeatAgreementBound`/`SeatMigrated`؛ گام `migrateSeat` پس از گزارش Identity Service دربارهٔ `migrateIdentity`.
>
> **وضعیت پیاده‌سازی (۲۰۲۶-۱۱-۱۹):** از طرح ۲٫۵ این بخش‌ها اکنون در `contracts/` نوشته و با ۹۷ آزمون Hardhat در ۱۰ فایل (روی EVM درون‌فرایندی Hardhat، نه Besu/QBFT) آزموده شده‌اند: `FoundationDAO` (با نوع آزاد `Execute` و `EndSale`)، `FoundationMembers`، `SurenSale` (مدل صرافی، بدون اوراکل پرداخت)، `ValidatorLottery`، `GenesisClaimsVault` (صندوق طلب‌ها؛ ۲۴ قسط ماهانه)، حذف ولیدیتور در بازیابی شبکه (`RemovedInRecovery`)، تغییرات `IdentityRegistry` (بله/ایمیل، `isFullyVerified`)، `ValidatorSeatNFT` (صندلی ERC-721 با انتقال و قواعد خریدار)، هستهٔ بازطراحی `ValidatorsRegistry`/`ValidatorsBoard` (وثیقهٔ ثابت، کلید مالک/اپراتور، جریان مؤسسان، `SelfSuspended`، سوزاندن ۱۰۰٪ جریمه، قواعد فاصلهٔ ورود) و سوزاندن مازاد پاداش در `BlockRewardDistributor`. هنوز نوشته نشده‌اند: `RewardRouter` (سرویس آف‌چین، نه قرارداد)، سرویس‌های Verifier و Identity، ابزار genesis، بررسی‌های آف‌چین Verifier برای تعلیق داوطلبانه و ازسرگیری، و حدود تغییر ریوارد (±۱۰٪ و ۶ ماه فاصله؛ در `proposeRateChange` هنوز نیست). پوشه‌های `contracts/` و `contracts-fa/` فقط نسخهٔ جاری را نگه می‌دارند؛ نسخه‌های قدیمی در git هستند (برچسب `v2.2.0`). سرویس Verifier خودش هنوز نوشته نشده است؛ تابع `recordRecoveryRemoval` و مسیر اعتراض/رسیدگی آن در `ValidatorsRegistry`/`ValidatorsBoard` پیاده و با آزمون Hardhat آزموده شده‌اند. ✅ دور اول آزمون زندهٔ Besu برای قراردادهای ۲٫۵ انجام شد (۲۰۲۶-۱۱-۱۹؛ Besu 26.9.0 در Docker، QBFT، فورک London، یک میزبان، اجراهای کوتاه؛ ۲۲ فایل نتیجه؛ دو اجرای اول به‌علت اشکال اسکریپت ناموفق ثبت و نگه داشته شده‌اند، بقیه گذشتند): `testing-evidence/besu-live-test-v25-2026-11-19/REPORT.md`. 🔶 هنوز روی Besu اجرا نشده: هر تایمر ۷۲ ساعت و بیشتر (قفل ۹۰ روزه، انقضا و ارجاع ۷روزه، دورهٔ آزمایشی و مهلت ورود با مقدار واقعی)، آزادسازی ماهانهٔ صندوق طلب‌ها، `recordSuspension`/رخداد جمعی/جریمه/اعتراض/`recordRecovery`، لاتاری دوم، تازه‌سازی ماهانهٔ هیأت، حکمرانی نرخ ریوارد، گذار Shanghai/Cancun، `SurenSale`، `ServiceStaking` و خرج خزانه؛ یافته‌های باز F-1 تا F-7 در `sur-master-open-items.md` بخش ۵. حسابرسی امنیتی هم انجام نشده است؛ این نتیجه آمادگی تولید نیست.

> **هم‌ترازی با قراردادهای ۲٫۵ (۲۰۲۶-۱۱-۲۰، فاز A ساخت):** این مشخصات بندبه‌بند با `ValidatorsRegistry`، `ValidatorsBoard`، `IdentityRegistry`، `ValidatorSeatNFT` و `ValidatorLottery` در `contracts/` مقایسه و اصلاح شد (نام توابع، شرط‌های `require`، رویدادها، کلیدها، ثابت‌های زمانی). قرارداد مرجع است؛ جایی که انتخاب با مالک است با 🔶 و شناسهٔ `VD-n` علامت خورده و فهرست کامل در بخش ۱۰.۱۱ است؛ جدول ناهمخوانی‌ها در بخش ۱۰.۱۰؛ طرح ساخت (ماژول‌ها، داده‌ها، پیکربندی، خطاها، آزمون، ترتیب) در بخش ۱۰. ✅ هنوز هیچ کد سرویسی نوشته نشده و برای خودِ سرویس هیچ ادعای «آزموده‌شده» وجود ندارد.

> این سند رفتار دقیق سرویس آف‌چین `verifier` را توصیف می‌کند — همان سرویسی که کلید on-chain `verifier` (در `ValidatorsRegistry`) را برای ثبت تصمیم‌های مبتنی بر شواهد (liveness، تعلیق، بازگشت، فعال‌سازی، تأیید ازسرگیری از تعلیق داوطلبانه) و اجرای تصمیمات هیأت‌مدیره‌ی ولیدیتورها درباره‌ی چرخش همین کلید در اختیار دارد. **اجرای** سرویس زیر نظر هیأت‌مدیره‌ی مجمع ولیدیتورها است؛ **توسعهٔ** نرم‌افزار آن با کمیتهٔ فنی بنیاد است و کمیتهٔ فنی نه کلید `verifier` را نگه می‌دارد و نه خود سرویس را اجرا می‌کند. احراز تلفن/تلگرام/بله/ایمیل (setterهای هویت در `IdentityRegistry`) اختیار مستقل دیگری است و کلید جدای `identityOracle` می‌خواهد؛ این دو وظیفه هرگز در یک فرایند و یک فایل تنظیمات نمی‌آیند (فهرست جامع ۷٫۴؛ 🔶 VD-1 در بخش ۱). چرخش کلید `verifier` فقط با `ValidatorsBoard.proposeRotateVerifier` (دست‌کم ۳ رأی هیأت) ← `ValidatorsRegistry.setVerifier` انجام می‌شود (رویدادهای `VerifierRotated` و `VerifierUpdated`) و چرخش `identityOracle` با `FoundationDAO` (`setIdentityOracle`). برای منطق on-chain مرتبط به `sur-smart-contracts-reference.md` و برای تصمیمات معماری به `sur-blockchain-design-doc.md` مراجعه کن.

---

## ۱. نقش کلی — این سرویس دقیقاً چه مشکلی را حل می‌کند

چند وظیفه‌ی کاملاً متفاوت دارد که اختیار on-chain هرکدام جدا است: ثبت تصمیم‌های مبتنی بر شواهد با کلید `verifier`، و setterهای هویت (تلفن، تلگرام، بله، ایمیل) با کلید جدای `identityOracle`. در طرح ۲.۵ هر ولیدیتور دو کلید دارد: **مالک** (`owner`: وثیقه، ریوارد، رأی، هویت، درخواست خروج، NFT صندلی، تعویض اپراتور) و **اپراتور** (`operator`، کلید نود: فقط امضای بلاک). همهٔ بررسی‌های سلامت نود روی کلید/نود **اپراتور** انجام می‌شود و همهٔ بررسی‌های هویتی روی **مالک**.

1. **احراز هویت ولیدیتوری** (کلید `identityOracle`) — فقط **هنگام ورود**: تأیید این‌که شمارهٔ تلفن، حساب تلگرام، حساب بله و ایمیل اعلام‌شدهٔ متقاضی واقعاً متعلق به خودش است، و (در کنار `kycVerified` در `IdentityRegistry`) یکتایی شخص (`personKey`، بخش ۵.۱). پس از ورود، دوباره چک نمی‌شود. فقط شخص حقیقی ایرانی (`Individual`) پذیرفته می‌شود؛ مؤسسان اولیه مستثنی‌اند. ⚠️ **تفکیک فرایند (🔶 VD-1، فهرست جامع ۷٫۴):** فرایند Verifier فقط کلید `verifier` را دارد. OTP و `setPhoneVerified`/`setTelegramVerified`/`setBaleVerified`/`setEmailVerified` با `identityOracle` کار **Identity Service** است (که OTP تلفن و تلگرام را از پیش دارد و برای بله و ایمیل گسترش می‌یابد؛ `sur-identity-registry-spec.md`)؛ Verifier وضعیت احراز را فقط از `IdentityRegistry` می‌خواند. اگر مالک بخواهد این جریان‌ها در پروژهٔ Verifier ساخته شوند، باید فرایند و فایل تنظیمات جدا با کلید جدا باشد (ماژول اختیاری `M-OTP`، بخش ۱۰.۱)؛ در متن این سند آن حالت «حالت الف» نام دارد و پیش‌فرض «حالت ب» (Identity Service) است.
2. **گزارش liveness و بررسی سلامت** (کلید `verifier`) — تأیید این‌که نودِ اپراتورِ یک ولیدیتور (در `Probation` یا `Active`) واقعاً سالم است، نه فقط یک کیف‌پول که می‌تواند امضا کند. همین بررسی برای موارد زیر هم به‌کار می‌رود (بخش ۶.۸): فعال‌سازی شش مؤسس پس از تعریف کلید نودشان، ازسرگیری از تعلیق داوطلبانه، ورود صاحب جدید NFT صندلی و دورهٔ آزمایشی تغییر نود، و بررسی سلامت نودِ تازه پیش از تأیید تعویض اپراتور ولیدیتور `Active` (`proposeOperator` ← `confirmOperatorReady`، بخش ۶.۸.۱)؛ برای مالکی که در مجموعهٔ اجماع نیست (`Probation`، `Demoted`، `SelfSuspended`) و `setOperator` فوری است، بررسی همچنان در چرخهٔ عادی و پیش از ورود یا ازسرگیری انجام می‌شود.
3. **نگه‌داری داده‌ی حساس آف‌چین** — تلفن، تلگرام، بله، ایمیل، `personKey` و آدرس/`nodeID` نودها، که عمداً هرگز روی زنجیره‌ی عمومی ثبت نمی‌شوند.
4. **✅ احراز مداوم محل جغرافیایی نود:** طبق شرط عضویت (بخش ۶ سند طراحی بلاک‌چین («الزام حضور فیزیکی نود»))، نود یک ولیدیتور باید **همیشه، بدون استثنا**، از لحاظ فیزیکی داخل مرزهای جغرافیایی ایران باشد. این سرویس، در همان چرخه‌ی liveness (نه یک چرخه‌ی جدا)، این شرط را به‌طور مداوم احراز می‌کند — جزئیات کامل در بخش ۶.۵ پایین.
5. **یکتایی شخص و ممنوعیت بازگشت** — هر شخص فقط یک صندلی دارد و هر کس خودش خارج شود یا در بازیابی شبکه از فهرست حذف شود برای همیشه نمی‌تواند دوباره ولیدیتور شود (فقط `migrateIdentity` برای گم‌شدن کلید مالک). این قاعده را `personKey` آف‌چین (HMAC کد ملی) در همین سرویس اجرا می‌کند (بخش ۵.۱).
6. **گزارش‌ها و هشدارهای آف‌چین** — هشدار به ولیدیتور و هیأت‌ها دربارهٔ سلامت نود و نقض شرط محل (هشدار مازاد پاداش با RewardRouter است، بخش ۶.۹).

---

## ۲. ورودی‌ها

### ۲.۱ ورودی از کاربر (از طریق اپلیکیشن همراه)
| فیلد | نوع | اجباری؟ |
|---|---|---|
| آدرس اتریومی مالک ولیدیتور | `address` | بله (کلید اصلی هر رکورد) |
| شماره تلفن | رشته | بله (برای مسیر وریفای تلفن) |
| آیدی تلگرام | رشته | بله (برای مسیر وریفای تلگرام) |
| آیدی بله | رشته | بله (برای مسیر وریفای بله) |
| ایمیل | رشته | بله (برای مسیر وریفای ایمیل) |
| `nodeID` نودِ اپراتور (بخش کلید عمومی enode، **نه کل enode**) | رشته‌ی هگزادسیمال ۱۲۸ کاراکتری | بله (برای liveness) |
| کد تأیید (پیامکی/تلگرامی/بله/ایمیلی، هنگام فرآیند وریفای) | رشته‌ی کوتاه | بله، فقط در لحظه‌ی وریفای |

✅ **مقصد فیلدها (VD-1، حالت ب = پیش‌فرض):** `nodeID` و آدرس مالک (با امضا) به Verifier می‌رسند؛ شماره تلفن، آیدی تلگرام، آیدی بله، ایمیل و کدهای تأیید به Identity Service می‌روند و در پایگاه Verifier نگه‌داری نمی‌شوند (کمینه‌سازی داده). جدول و ستون‌های تماس در بخش ۵ و مسیرهای `/phone/*` تا `/email/*` در بخش ۸.۱ فقط برای «حالت الف» نگه داشته شده‌اند.

🔶 نام و نوع شخصیت لازم نیست از این اپ عبور کند — کاربر می‌تواند مستقیم `IdentityRegistry.registerIdentity` (روی قرارداد مستقل `IdentityRegistry` — `sur-identity-registry-spec.md`) را خودش صدا بزند (فقط `Individual`)؛ ولی اگر بخواهید تجربه‌ی کاربری یکپارچه بسازید، این اپ می‌تواند یک دکمه/فرم برای ارسال همان تراکنش هم داشته باشد. فرایند eKYC (هویت) در خود اپ همراه یا Identity Service انجام می‌شود و هزینهٔ آن با متقاضی است.

### ۲.۲ ورودی از شبکه‌ی P2P
- خروجی دوره‌ای `admin_peers` از نود مانیتورینگ خودِ سرویس — شامل `id` (nodeID) و `network.remoteAddress` (IP:پورت فعلی) هر peer متصل.
- ✅ همین `remoteAddress` منبع ورودی احراز جغرافیایی هم هست — نیازی به هیچ داده‌ی اضافه‌ای از کاربر یا از خودِ نود نیست؛ فقط یک پردازش (IP-geolocation) روی همین IP.

### ۲.۴ ✅ ورودی — پایگاه‌داده/سرویس IP-geolocation
| داده | منبع | هدف |
|---|---|---|
| کد کشور متناظر با یک IP | یک سرویس/پایگاه‌داده‌ی IP-geolocation (مثلاً MaxMind GeoLite2 آفلاین، یا یک API تجاری) | تشخیص این‌که آیا `remoteAddress` هر peer از داخل ایران است یا نه |

🔶 **سؤال باز:** انتخاب دقیق سرویس/پایگاه‌داده (آفلاین رایگان در برابر API تجاری با دقت بالاتر) و دوره‌ی به‌روزرسانی‌اش هنوز مشخص نشده — به بخش ۹ (سؤالات باز) مراجعه کن.

### ۲.۳ ورودی از زنجیره (RPC)
| داده | متد RPC | هدف |
|---|---|---|
| لیست ولیدیتورهای فعال | `ValidatorsRegistry.getValidators()` (✅ کلید **اپراتور**ها؛ همان‌ها در `miner` بلاک می‌آیند) و `getActiveOwners()` (آدرس **مالک**ها) | فهرست کسانی که باید چک تولید بلاک بشوند؛ نگاشت اپراتور ↔ مالک با `operatorOf(owner)` / `ownerOfOperator(operator)` (کلید اپراتور قدیمی برای تعویض اپراتور (`setOperator` یا `confirmOperatorReady`) به همان مالک پیوسته می‌ماند؛ پس از انتقال صندلی `ownerOfOperator` به خریدار اشاره می‌کند — یافتهٔ F-4، ✅ تصمیم مالک ۲۰۲۶-۱۱-۱۹: انتساب با بازپخش رویدادهای `OperatorSet`، `OperatorChangeConfirmed` و `SeatTransferred` از genesis؛ `sur-reward-router-spec.md` بخش ۳ و ۱۰.۵) |
| وضعیت هر ولیدیتور | `ValidatorsRegistry.getValidatorInfo(address)` | تشخیص `Probation`/`Active`/`Demoted`/`SelfSuspended` برای انتخاب روش چک (✅ `getValidatorInfo` ۶ خروجی دارد: `status`، `lockedStake`، `periodStartedAt`، `demotedAt`، `pendingSlashEpoch`، `isPaidEntrant`؛ آدرس اپراتور از `operatorOf(owner)` و مؤسس‌بودن از `isFounder(owner)` خوانده می‌شود) |
| رویدادهای تعریف/تعویض اپراتور (`OperatorSet`، `OperatorChangeProposed`، `OperatorChangeConfirmed`، `OperatorChangeCancelled`)، درخواست ازسرگیری (`ResumeRequested` از `requestResume()`)، انتقال NFT صندلی (`SeatTransferred`، به‌همراه `SeatAgreementBound` که هش توافق‌نامهٔ خریدار را به صندلی می‌بندد، و پیش‌تر `SeatAgreementAccepted`/`SeatAcceptanceRevoked` از خریدار)، مهاجرت صندلی پس از گم‌شدن کلید مالک (`SeatMigrated`) و درخواست ورود (`MembershipRequested`) | لاگ‌های رویداد قراردادها | آغاز بررسی‌های بخش ۶.۸ |
| فهرست KYC شده‌ها | `IdentityRegistry.isFullyVerified(address)` / `getVerificationStatus(address)` (شش بولی: ثبت، تلفن، تلگرام، بله، ایمیل، KYC) / `hasIdentity` | شرط ورود (فقط هنگام ورود چک می‌شود) |
| `miner`/`coinbase` هر بلاک اخیر | `eth_getBlockByNumber` (حلقه روی بلاک‌های اخیر) | چک واقعی تولید بلاک برای ولیدیتورهای `Active` |
| ارتفاع فعلی زنجیره | `eth_blockNumber` | مبنای مقایسه برای چک sync-بودن نود کاندیدای `Probation` |

### ۲.۵ ✅ خواندنی‌ها، رویدادها و شکاف بازپخش از genesis (هم‌ترازی فاز A)

**توابع خواندنی (ABI از کامپایل قرارداد تولید می‌شود، نه دستی؛ بخش ۱۰.۶):**
- `ValidatorsRegistry`: `verifier()`، `probationPeriod()` (ثابت ۷ روز) و `slashBps()` (ثابت ۱۰۰ = ۱٪) که **ثابت قراردادی‌اند و رأی‌پذیر نیستند** (کلیدهای `ProbationPeriod`، `SlashBps` و `MaxEntriesPerWindow` هنگام پیشنهاد و اجرا رد می‌شوند: «this parameter is fixed and cannot be changed»)، پارامترهای حکمرانی‌شدهٔ `recoveryPeriod()`، `exitCooldown()` و `entryWindowSeconds()` (مجمع با `proposeParameterChange` عوضشان می‌کند؛ `entryWindowSeconds` فقط ۱ تا ۳۰ روز، ±۱ روز در هر تغییر)، `lastPaidActivationAt()` و `nextPaidActivationAllowedAt()` (فاصلهٔ ورود، بخش ۶.۸)، `getActiveValidatorCount()`، `statusBeforeExit(owner)`، `pendingSlashDecisionId(owner)`، `pendingOperator(owner)`، `pendingOperatorExpiresAt(owner)`، `resumeRequested(owner)`، `recoveryRemovals(owner)` / `recoveryCaseInfo(owner)`، `isFounder`، `everActivated`، `permanentlyExited`، `membershipEpoch`، `statusDecisions(id)`.
- `ValidatorsBoard`: `getBoardMembers()`، `seatMembershipEpoch(member)`، `boardMonthId()`، `refreshDue()`، `pendingVacancies()`. `ValidatorSeatNFT`: `seatOf(owner)`، `ownerOf(id)`.

**رویدادها (نام دقیق در کد):**

| گروه | رویدادها |
|---|---|
| ورود و وضعیت | `MembershipRequested`، `LotteryWinnerEntered`، `ValidatorActivated`، `ValidatorDemoted(validator, pendingSlashEpoch)`، `ValidatorReactivated`، `SelfSuspendedEvent` (نه `SelfSuspended`)، `ResumeRequested`، `ResumeRecorded`، `ExitRequested(validator, cooldownEnd)`، `StakeWithdrawn` |
| اپراتور | `OperatorSet`، `OperatorChangeProposed(owner, newOperator, expiresAt)`، `OperatorChangeConfirmed`، `OperatorChangeCancelled` |
| تصمیم و پرونده | `StatusDecisionRecorded(decisionId, validator, decisionType, evidenceHash)` (**منبع `decisionId`**)، `PreExitCaseRecorded`، `DeliveryConfirmed`، `DeliveryDisputeFiled`، `DeliveryDisputeResolved`، `AppealFiled`، `SlashResolved` |
| حذف در بازیابی | `RecoveryRemovalRecorded`، `RecoveryRemovalObjected`، `RecoveryCaseReferredToAssembly`، `RecoveryRemovalUpheld`، `RecoveryRemovalCancelled(validator, expired)` (Registry)؛ `RecoveryRemovalVote`، `RecoveryAssemblyVote`، `RecoveryCaseDecided` (Board) |
| صندلی | `SeatTransferred(seatId, from, to, statusAfter)`، `SeatAgreementAccepted(buyer, seatId, agreementHash)`، `SeatAcceptanceRevoked(buyer, seatId)`، `SeatAgreementBound(seatId, owner, agreementHash)`، `SeatMigrated(seatId, from, to, statusAfter)` (مهاجرت پس از گم‌شدن کلید مالک)، `Transfer` (ERC-721)؛ رویداد `SeatTransferAccepted` و تابع `acceptSeatTransfer` دیگر وجود ندارند |
| هیأت و کلید | `BoardRefreshed`، `BoardMemberAuthorityEnded`، `BoardSuccession`، `VerifierRotated` (Board)، `VerifierUpdated` (Registry) |
| لاتاری | `WinnerDrawn`، `WinnerEntryFailed` (و `LotteryWinnerEntered` در Registry) |

**شکاف بازپخش از genesis (یافتهٔ فاز A؛ F-4 را کامل می‌کند):** state ساختاری با تزریق در genesis نوشته می‌شود و هیچ رویدادی ندارد. `_seedFirstValidator` کلید اپراتور ولیدیتور اول را بی‌رویداد می‌نویسد و مالکیت صندلی‌های ۱ تا ۷ هم رویداد `SeatTransferred` ندارد؛ پس بازپخش «از genesis» به‌تنهایی کلید اپراتور ولیدیتور اول را گم می‌کند. **پایهٔ بازپخش** باید state بلاک ۰ باشد (`eth_call` روی `ownerOfOperator`/`operatorOf` با `blockNumber = 0` برای آدرس‌های مؤسس، یا فهرست genesis-config) و رویدادها روی آن اعمال شوند. همین الزام برای RewardRouter هم هست (`sur-reward-router-spec.md` بخش ۱۰.۵).

**نود پایش:** RPC باید APIهای `ETH`، `NET`، `ADMIN` و `QBFT` را فعال داشته باشد (`admin_peers`، `qbft_getValidatorsByBlockNumber`، `qbft_getSignerMetrics`) و فقط روی شبکهٔ داخلی در دسترس باشد.

---

## ۳. خروجی‌ها

### ۳.۱ تراکنش‌های on-chain (امضاشده با کلید `verifier`)

✅ **معماری:** هیچ تراکنش روتینِ «هر ساعت، برای هر ولیدیتور» وجود نداره. سرویس هر ۶۰ دقیقه همه‌ی نودها رو **آف‌چین** چک می‌کنه، ولی فقط وقتی **وضعیت واقعاً عوض بشه**، یکی از سه تابع زیر رو صدا می‌زنه — هرکدوم با یه `evidenceHash` (هش کل بسته‌ی شواهد آف‌چینی که تصمیم رو توجیه کرده):

| تابع | چه زمانی صدا زده می‌شود |
|---|---|
| `ValidatorsRegistry.recordActivation(address candidate, bytes32 evidenceHash)` | فقط وقتی یه ولیدیتور probation، `probationPeriod` (۱ هفته) گذشته باشه، **و** محاسبه‌ی آف‌چین سرویس نشون بده نسبت موفقیتش ≥۹۵٪ بوده. ✅ **پیش‌شرط ایمنی (یافته‌ی آزمون واقعی Besu، ۲۰۲۶-۰۹-۲۹):** قبل از این فراخوان، سرویس باید مطمئن شود نود Besu واقعیِ این ولیدیتور واقعاً روشن و در حال همگامی است (همان بررسی حضور در `admin_peers` که برای دوره‌ی Probation استفاده می‌شود، بخش ۶ همین سند). فعال‌کردن یک ولیدیتور بدون نود واقعیِ پشتش («phantom») اگر مجموعه‌ی فعال به‌اندازه‌ای برسد که نصاب QBFT (`⌊2n/3⌋+1`) از تعداد نودهای واقعیِ روشن بیشتر شود، **می‌تواند کل زنجیره را قفل کند** (نه فقط نوبت آن ولیدیتور را رد کند) — در آزمون واقعی این اتفاق افتاد و ~۵۴ دقیقه طول کشید تا رفع شود. سرویس باید این بررسی را هرگز نادیده نگیرد، حتی وقتی `probationPeriod` و نسبت موفقیت هر دو برقرارند. همین پیش‌شرط برای **هر مسیر ورود به مجموعهٔ اجماع** برقرار است: `recordRecovery`، `recordResume` و `confirmOperatorReady` هم (بخش ۳.۱.۱). قرارداد خودش هیچ بررسی نودی نمی‌کند؛ سرویس تنها سد است. ✅ (۲۰۲۶-۱۱-۲۳) برای ورودیِ **پرداخت‌کننده** (`isPaidEntrant`) شرط سوم هم هست: حداکثر یک فعال‌سازی پرداخت‌کننده در هر `entryWindowSeconds` (مقدار genesis ۷ روز)؛ قبل از ارسال `nextPaidActivationAllowedAt()` خوانده می‌شود و اگر هنوز نرسیده، فعال‌سازی عقب می‌افتد (ارسال نمی‌شود)، و `recordActivation` در آن پنجره revert می‌کند («entry window used - only one new paid validator per window»). فعال‌سازی مؤسسان و برندگان لاتاری مستثناست؛ اولین فعال‌سازی پرداخت‌کننده هرگز به تأخیر نمی‌افتد. |
| `ValidatorsRegistry.recordSuspension(address validator, bytes32 evidenceHash)` | فقط وقتی سرویس آف‌چین **۴ ساعت غیرفعالیِ تأییدشده** (بخش ۶.۶) برای یک ولیدیتور Active تشخیص بده — این آستانه پارامتر پیکربندی سرویس است، روی زنجیره نیست |
| `ValidatorsRegistry.recordRecovery(address validator, bytes32 evidenceHash)` | فقط وقتی یه ولیدیتور Demoted، `recoveryPeriod` (۴۸ ساعت) گذشته باشه، **و** نسبت موفقیت آف‌چینش دوباره ≥۹۵٪ باشه، **و** پرونده‌ی جریمه‌ی معلق همان تنزل‌رتبه بسته شده باشه (`pendingSlashEpoch == 0`؛ وگرنه قرارداد با «resolve the pending slash first» رد می‌کنه) |
| `ValidatorsRegistry.recordPreExitViolation(address validator, bytes32 evidenceHash, uint256 violationAt)` | ✅ **تصمیم نهایی P04:** فقط وقتی یک ولیدیتور که پیش از خروج **Active** بود درخواست خروج داده و ظرف **۷۲ ساعت** از آن درخواست، سرویس شواهد کافی دارد که **پیش از** درخواست، غیرفعالیِ تأییدشده (۴ ساعت) رخ داده. `violationAt` = لحظه‌ای که آستانه‌ی ۴ساعته عبور کرد و باید **قبل از** زمان درخواست خروج باشد؛ غیرفعالی پس از درخواست خروج هرگز تخلف نیست. صرف ادعای Verifier کافی نیست: بسته‌ی شواهد + زمان تخلف روی زنجیره ثبت می‌شود و همان مسیر معافیت جمعی، تحویل شواهد، اعتراض و رأی مجمع اجرا می‌شود |
| `recordActivation` برای مؤسس (✅ همان تابع عادی؛ در کد مؤسسِ `isFounder` بدون انتظار `probationPeriod` فعال می‌شود) | وقتی هر یک از شش مؤسس دیگر (به‌جز اولین ولیدیتور که در مجموعهٔ اولیهٔ genesis است) با آدرس اتریومی خودش کلید نودش را در قرارداد تعریف کرده و بررسی سلامت نود (بخش ۶.۸) موفق بوده؛ آنگاه نود او وارد فهرست ولیدیتورها می‌شود. مؤسسان `kycVerified` لازم ندارند و تابع فاصلهٔ ورود (`entryWindowSeconds`) شامل آن‌ها نیست. وضعیت مؤسس تا آن زمان `Probation` است و قرارداد بدون اپراتور ثبت‌شده revert می‌کند (`operator key not set`) |
| `ValidatorsRegistry.recordResume(address validator, bytes32 evidenceHash)` — تأیید ازسرگیری از تعلیق داوطلبانه (✅ نام کد) | وقتی ولیدیتور `SelfSuspended` طبق `requestResume()` درخواست ازسرگیری داده و بررسی سلامت نود اپراتورش (بخش ۶.۸) موفق است؛ بدون دورهٔ آزمایشی. بدون تأیید Verifier ازسرگیری ممکن نیست. قرارداد درخواست مالک (`requestResume`) و اپراتور ثبت‌شده را می‌خواهد (پذیرش انتقال صندلی دیگر شرط نیست؛ تصمیم ۲۰۲۶-۱۱-۱۹) و نوع تصمیم را `Resume` ثبت می‌کند |
| `ValidatorsRegistry.confirmOperatorReady(address owner, address newOperator, bytes32 evidenceHash)` — تأیید تعویض کلید نودِ ولیدیتور `Active` (✅ نام کد؛ تصمیم ۱۱۰؛ وظیفهٔ تازه) | فقط وقتی مالکِ `Active` با `proposeOperator` کلید تازه را پیشنهاد داده، پیشنهاد باز و منقضی‌نشده است و بررسی سلامت نودِ تازه (بخش ۶.۸.۱: دسترس‌پذیر، همگام، کلید درست با چالش امضاشده، توان امضا تا جای ممکن) **کاملاً موفق** است؛ جایگزینی در همان تراکنش اعمال می‌شود. اگر بررسی ناموفق یا نامشخص است هیچ تراکنشی زده نمی‌شود و پیشنهاد پس از ۷ روز خودبه‌خود منقضی می‌شود. قرارداد هش شواهد غیرتهی می‌خواهد و اگر مالک دیگر `Active` نباشد رد می‌کند؛ `decisionId` برنمی‌گرداند |
| پیگیری صاحب جدید NFT صندلی و نود او (✅ در کد تابع تأیید جداگانه ندارد؛ صندلی `Active` تصمیم تازه نمی‌خواهد و فقط صندلی `Probation` با همان `recordActivation` عادی فعال می‌شود) | پس از انتقال NFT: Verifier `kycVerified` و `Individual`‌بودن خریدار، یکتایی `personKey` و نبودن او در فهرست ولیدیتورهای فعلی/گذشته را کنترل می‌کند (بخش ۶.۸)؛ قرارداد خودش `isFullyVerified` و سابقهٔ آدرس را هنگام انتقال می‌سنجد؛ صندلیِ `Active` پس از انتقال `Active` می‌ماند (تصمیم مالک ۲۰۲۶-۱۱-۱۹): همان نود و همان جایگاه، بدون `recordResume`؛ نود در چرخهٔ عادی liveness می‌ماند و اگر خریدار نود تازه معرفی کند (صندلی `Active`: `proposeOperator` و تأیید Verifier، بخش ۶.۸.۱؛ بیرون از مجموعه: `setOperator`) همان بررسی تعویض اپراتور اجرا می‌شود (F-5)؛ خریدار پیش از انتقال خودش با `acceptSeatAgreement(seatId, hash)` پذیرش توافق‌نامه را ثبت کرده است (انتقال بدون آن revert می‌کند؛ پذیرش در انتقال مصرف می‌شود و هش با `SeatAgreementBound` به صندلی می‌ماند)؛ این ثبت شرط هیچ تصمیمی از Verifier نیست و امضای مقابل بنیاد پس از انتقال، آف‌چین است و روی زنجیره چیزی منتظرش نمی‌ماند؛ صندلی `Probation` پس از انتظار دورهٔ آزمایشی عادی با `recordActivation` فعال می‌شود (و اگر صندلی ورودی پرداخت‌کننده بوده، خریدارش هم یک اسلات پنجرهٔ ورود را هنگام فعال‌سازی مصرف می‌کند) |
| `ValidatorsRegistry.migrateSeat(address oldOwner, address newOwner)` — گم‌شدن کلید مالک (✅ نام و امضای کد؛ فقط `verifier`؛ ۲۰۲۶-۱۱-۲۳؛ 🔶 گام سرویس هنوز پیاده نشده است) | فقط وقتی `identityOracle` پیش‌تر `IdentityRegistry.migrateIdentity(old, new)` را اجرا کرده باشد (Identity Service این را به Verifier گزارش می‌کند)، Verifier خودش `IdentityRegistry.migratedTo(old) == new` را از زنجیره بخواند و با `eth_call` شبیه‌سازی کند. شرط‌های قرارداد در بخش ۳.۱.۱؛ بدون این دو کلید مستقل صندلی جابه‌جا نمی‌شود |

⚠️ **پیامد اقتصادی مستقیم:** چون این توابع فقط موقع **تغییر واقعی** صدا زده می‌شن (نه هر چرخه‌ی polling، صرف‌نظر از این‌که چیزی عوض شده یا نه)، هزینه‌ی گس این سرویس بسیار کم است — چون اکثر چرخه‌ها اصلاً هیچ تراکنشی تولید نمی‌کنن.

**توابع تکمیلی on-chain که سرویس (یا هرکس دیگه‌ای) ممکنه نیاز به صدازدنشون داشته باشه، بعد از یه `recordSuspension`:**

| تابع | چه زمانی |
|---|---|
| `resolveMassFailureCheck(decisionId)` | بدون نیاز به مجوز، بعد از بسته‌شدن پنجره‌ی ۱ساعته‌ی رخداد جمعی |
| `assertDeliveryDisputed(decisionId)` | اگه ولیدیتور ظرف `DELIVERY_DISPUTE_GRACE_PERIOD` خودش بسته‌ی شواهد رو تأیید نکنه |
| `executeUncontestedSlash(decisionId)` | بدون نیاز به مجوز، اگه تحویل ثابت شده و ۷۲ ساعت گذشته بدون اعتراض؛ در این لحظه جریمه ۱۰۰٪ سوزانده می‌شود (ارسال به `address(0)`، نه خزانه). در لحظهٔ ثبت پرونده چیزی سوزانده نمی‌شود |
| `resolveAppealIfExpired(decisionId)` | بدون نیاز به مجوز، اگه مهلت رأی‌گیری اعتراض (۷ روز) بدون نصاب تموم بشه |
| `resolveDeliveryDisputeIfExpired(decisionId)` | بدون نیاز به مجوز، اگه رأی‌گیری اختلاف تحویل (۷ روز) بدون نصاب تموم بشه (تحویل اثبات‌نشده حساب می‌شود و جریمه باطل می‌شود؛ تعلیق می‌ماند) |
| `expireRecoveryRemoval(validator)` | بدون نیاز به مجوز، پس از `resolutionDeadline` پروندهٔ اعتراض به حذف در بازیابی بدون تصمیم؛ حذف لغو می‌شود (بخش ۶.۹.۱ و VD-4) |

این توابع **بدون نیاز به مجوز**ن (permissionless) — یعنی سرویس Verifier می‌تونه به‌عنوان یه راحتی عملیاتی صداشون بزنه (تا پرونده‌ها معطل نمونن)، ولی هرکس دیگه‌ای هم می‌تونه، پس سرویس نباید تنها مسیر پیش‌روندگی این پرونده‌ها فرض بشه. جریمه فقط وقتی سوزانده می‌شود که مهلت اعتراض (۷۲ ساعته) بدون اعتراض بگذرد، اعتراض رد شود، یا مجمع جریمه را تأیید کند؛ وثیقهٔ جریمه‌شده بازپر نمی‌شود.

**توابع وریفای هویت (روی `IdentityRegistry`، با کلید `identityOracle`، نه `verifier`):**

| تابع | چه زمانی |
|---|---|
| `IdentityRegistry.setPhoneVerified(address, bool)` | بلافاصله بعد از موفقیت/شکست فرآیند وریفای پیامکی |
| `IdentityRegistry.setTelegramVerified(address, bool)` | بلافاصله بعد از موفقیت/شکست فرآیند وریفای تلگرامی |
| وریفای بله و ایمیل (`setBaleVerified`، `setEmailVerified`؛ ✅ نام کد، هم‌خانوادهٔ دو تابع بالا) | بلافاصله بعد از موفقیت/شکست فرآیند وریفای بله و ایمیل |

این توابع در `IdentityRegistry` هستند و با `onlyIdentityOracle` محافظت می‌شوند (کلید `identityOracle`)، نه در `ValidatorsRegistry` با کلید `verifier`. کلید `verifier` فقط برای توابع وریفای خود `ValidatorsRegistry` (تصمیم/تحویل/اعتراض) است. ✅ **پیش‌فرض (VD-1، حالت ب):** فرایند Verifier این توابع را **صدا نمی‌زند** و کلید `identityOracle` را ندارد؛ این فراخوانی‌ها کار Identity Service است (`sur-identity-registry-spec.md`). فقط اگر مالک «حالت الف» را بخواهد، ماژول `M-OTP` در فرایند جدا، با کلید `identityOracle` جدا و فایل تنظیمات جدا ساخته می‌شود (فهرست جامع ۷٫۴: سه کلید هرگز در یک فرایند یا یک فایل نمی‌آیند). setterها فقط برای آدرس ثبت‌شده با `PersonType.Individual` و مهاجرت‌نشده کار می‌کنند (در غیر این صورت ریورت).

### ۳.۱.۱ ✅ شرط‌های قرارداد، شبیه‌سازی پیش از ارسال و ثبت `decisionId` (هم‌ترازی فاز A)

| تابع (فقط `verifier`) | شرط‌های `require` در قرارداد | رویداد / خروجی |
|---|---|---|
| `recordActivation(candidate, hash)` | وضعیت `Probation`؛ `operatorOf(candidate) ≠ 0`؛ `isFounder` **یا** `now ≥ periodStartedAt + probationPeriod()`؛ اگر `isPaidEntrant` باشد: آخرین فعال‌سازی پرداخت‌کننده دست‌کم `entryWindowSeconds` پیش بوده یا هنوز هیچ‌کدام نبوده («entry window used - only one new paid validator per window»؛ مؤسسان و برندگان لاتاری مستثنا) | `ValidatorActivated`، `StatusDecisionRecorded`؛ `decisionId` برمی‌گرداند. هویت را دوباره نمی‌سنجد |
| `migrateSeat(oldOwner, newOwner)` (۲۰۲۶-۱۱-۲۳) | وضعیت قدیم `Probation`/`Active`/`Demoted`/`SelfSuspended`؛ بدون پروندهٔ جریمهٔ باز؛ `IdentityRegistry.migratedTo(old) == new`؛ `new` کاملاً احرازشده (`isFullyVerified`) و EOA؛ هرگز ولیدیتور/`everActivated`/`permanentlyExited`/کلید اپراتور نبوده و صندلی ندارد؛ `new ≠ old` و غیرصفر | `SeatMigrated(seatId, from, to, statusAfter)` و `ClaimableMigrated(from, to, amount)`؛ تصمیمی (`decisionId`) ثبت نمی‌شود. کل صندلی (رکورد، وثیقه، وضعیت، پیوند اپراتور، پرچم مؤسس، سابقهٔ فعال‌سازی، جای مجموعهٔ فعال، NFT، طلب پاداش) به آدرس جدید می‌رود؛ آدرس قدیم `permanentlyExited` می‌شود و اختیار هیأتش تمام؛ آدرس جدید رأی‌دهندهٔ تازه است؛ هش توافق‌نامهٔ صندلی می‌ماند |
| `recordRecovery(validator, hash)` | وضعیت `Demoted`؛ `pendingSlashEpoch == 0`؛ `now ≥ periodStartedAt + recoveryPeriod()` | `ValidatorReactivated`؛ `decisionId` |
| `recordSuspension(validator, hash)` | وضعیت `Active`؛ `getActiveValidatorCount() > MIN_ACTIVE_VALIDATORS` (= ۱) | `ValidatorDemoted`؛ `decisionId`. آخرین ولیدیتور فعال هرگز تعلیق نمی‌شود |
| `recordPreExitViolation(validator, hash, violationAt)` | وضعیت `Exiting` و `statusBeforeExit == Active`؛ `now ≤ periodStartedAt + 72h` (`periodStartedAt` = لحظهٔ `requestExit`)؛ `violationAt < periodStartedAt` و `violationAt > demotedAt` (آخرین تعلیق)؛ `pendingSlashEpoch == 0` | `PreExitCaseRecorded`؛ `decisionId` (نوع ثبت‌شده `Suspension` است) |
| `recordResume(validator, hash)` | وضعیت `SelfSuspended`؛ `resumeRequested`؛ `operatorOf ≠ 0` | `ResumeRecorded`؛ `decisionId` |
| `confirmOperatorReady(owner, newOperator, hash)` | `pendingOperator[owner] == newOperator` (VD-13؛ کلیدی که سنجیده شده باید همان باشد که روی زنجیره پیشنهاد باز است)، `pendingOperator ≠ 0`، منقضی‌نشده؛ مالک `Active`؛ **هش غیرتهی**؛ در لحظهٔ اجرا کلید تازه نباید در این فاصله خودش مالک ولیدیتور دیگری شده باشد (`operator is another owner`) | `OperatorSet` + `OperatorChangeConfirmed`؛ چیزی برنمی‌گرداند |
| `recordRecoveryRemoval(validator, recoveryTimestamp, hash)` | وضعیت `Active`؛ **هش غیرتهی**؛ `recoveryTimestamp ≤ now` و حداکثر ۳۰ روز قدیمی؛ `getActiveValidatorCount() > 1`؛ پروندهٔ حذف قبلی در وضعیت «ثبت‌نشده» یا «لغوشده» | `RecoveryRemovalRecorded`؛ چیزی برنمی‌گرداند |

قواعد عمومی سرویس:
1. **شبیه‌سازی اول:** پیش از هر ارسال `eth_call` (`simulateContract`) با همان آرگومان‌ها؛ ریورت یعنی «اجرا نمی‌شود» و تراکنشی (و گسی) هدر نمی‌رود؛ پیام ریورت در لاگ ثبت می‌شود.
2. **`decisionId` از رسید:** مقدار برگشتیِ تابع از تراکنش در دسترس نیست؛ `decisionId` از لاگ `StatusDecisionRecorded` همان رسید خوانده می‌شود (برای `confirmOperatorReady` و `recordRecoveryRemoval` شناسه‌ای نیست؛ شناسهٔ داخلی و `tx_hash` ثبت می‌شود).
3. **هش همیشه غیرتهی** است (حتی جایی که قرارداد تهی را رد نمی‌کند) و **پیش از ارسال** بستهٔ شواهد نزد دست‌کم دو نگهدارنده ذخیره شده است (بخش ۱۰.۳).
4. **آستانه‌های زمانی از زنجیره** خوانده می‌شوند (`probationPeriod`، `recoveryPeriod`، `exitCooldown`)، نه عدد ثابت.
5. **مسیرهای ورود به مجموعه بدون تأیید Verifier:** فقط لغو حذف در بازیابی (`RecoveryRemovalCancelled`) ولیدیتور را بدون هیچ بررسی نودی به `Active` برمی‌گرداند (🔶 VD-4)؛ انتقال صندلیِ `Active` نود را عوض نمی‌کند.
6. **چرخش کلید:** اگر `verifier()` با آدرس کلید امضای سرویس برابر نباشد، همهٔ تراکنش‌ها متوقف می‌شود (فقط مشاهده و هشدار؛ بخش ۶ گام ۱۱).

### ۳.۲ اعلان‌ها (به کاربر، از طریق همان اپ)
- هشدار پیشگیرانه وقتی `nodeID` ثبت‌شده‌ی یک ولیدیتور دیگر در `admin_peers` دیده نمی‌شود (قبل از رسیدن به آستانه‌ی داخلی تشخیص غیرفعالی سرویس).
- ⚠️ اعلان به ولیدیتور وقتی یه `recordSuspension` براش ثبت می‌شه — شامل لینک/راه دسترسی به بسته‌ی شواهد رمزگذاری‌شده، تا بتونه در اسرع وقت `confirmDelivery` بزنه و پنجره‌ی ۷۲ساعته‌ی اعتراضش رو از دست نده.

### ۳.۳ لاگ داخلی
هر polling، هر تصمیم، و هر تراکنش، با timestamp کامل لاگ می‌شود — برای حسابرسی بعدی و دیباگ اختلاف‌نظر احتمالی («چرا فلان ولیدیتور دموت شد؟»).

---

## ۴. معماری اجرا

```
+------------------------------------------------+  
|           Verifier Service (Node.js)           |  
|                                                |  
| +-----------+   +--------------+   +---------+ |  
| | Scheduler |-->|  Liveness &  |-->|Tx Signer| |  
| |(60 min)   |   |Identity Logic|   |         | |  
| +-----------+   +--------------+   +---------+ |  
|                         |               |      |  
|                     +------+            |      |  
|                     |SQLite|            |      |  
|                     +------+            |      |  
+------------------------------------------------+  
                          |               |         
                +------------------+ +-------------+
                | Monitoring Node  | |  RPC Node   |
                |(Besu, static peer| |(chain reads)|
                |to all validators)| |             |
                +------------------+ +-------------+
```

### اجزا
1. **یک نود Besu اختصاصی برای مانیتورینگ** — به‌عنوان `static peer` به تمام ولیدیتورها وصل می‌شود (نه صرفاً از discovery معمولی) تا `admin_peers` همیشه کامل باشد. نیازی نیست full validator باشد؛ فقط باید peer معتبر شبکه باشد.
2. **دسترسی RPC به یک full node** — می‌تواند همان نود مانیتورینگ باشد یا یک نود جدا؛ برای خواندن state قراردادها و بلاک‌های اخیر.
3. **یک کلید امضاکننده (`verifier` hot wallet)** — باید همیشه موجودی سورن کافی برای گس داشته باشد (بخش «پیامد اقتصادی» در سند طراحی).
4. **پایگاه‌داده** — `SQLite` (همان الگوی سرویس RewardRouter در سند طراحی؛ کافی برای یک سرویس تک‌پردازشی با اجرای زمان‌بندی‌شده).
5. **Scheduler** — یک حلقه/cron داخلی، نه یک سرویس وب عمومی (حلقهٔ بررسی و تصمیم‌گیری هیچ API عمومی ندارد؛ تنها سطح عمومی سرویس، رابط `/api/v1/*` بخش ۸.۱ برای اپ همراه است که پشت یک دروازهٔ HTTPS عمومی قرار می‌گیرد، با امضای اتریومی و بدون هیچ مسیری برای فرمان‌دادن به Verifier یا ثبت تصمیم on-chain؛ `status` آن فقط‌خواندنی و غیرحساس است؛ سرویس با زنجیره هم حرف می‌زند).
6. **سرویس دسترسی کلید (Key Access Service)** — کلید HMAC که از کد ملی `personKey` می‌سازد (بخش ۵.۱) هرگز مستقیم در اختیار پردازهٔ Verifier یا پایگاه‌داده نیست؛ پشت یک سرویس دسترسی کلید نگه‌داری می‌شود که فقط یک عملیات محدود می‌دهد («HMAC این ورودی را حساب کن») و کلید خام را بیرون نمی‌دهد **[تصمیم مالک ۲۰۲۶-۱۱-۲۱] این سرویس اکنون خود سرور مدیریت کلید SurKMS است:** کلید `personKey` یک کلید HMAC ۳۲ بایتی داخل SurKMS است (ساخته‌شده داخل آن، بدون import و export) و Verifier فقط متد `kms_hmac("personKey", ورودیHex)` را روی همان mTLS با گواهی سنجاق‌شده صدا می‌زند (`offchain-services/sur-kms-spec.md` بخش ۸٫۳). HashiCorp Vault دیگر برای هیچ کلیدی لازم نیست. 🔶 **تغییر کوچکی در Verifier لازم است** (کلاینت سرویس دسترسی کلید باید `kms_hmac` را صدا بزند)؛ **هنوز انجام نشده**. ⚠️ این کلید را نمی‌شود بدون باطل‌شدن همهٔ `personKey`های ذخیره‌شده عوض کرد (کد ملی ذخیره نمی‌شود)؛ از دست رفتنش یعنی از دست رفتن سابقهٔ یکتایی اشخاص. **پشتیبان رمزشدهٔ آفلاین آن تصمیم‌شده است (۲۰۲۶-۱۱-۲۱؛ فایل نزد مدیرعامل، عبارت نزد فرد دیگر؛ `hmac backup` و `hmac restore` در SurKMS).**

**الزام‌ها و محدودیت‌های اجزا (هم‌ترازی فاز A):**
- **دسترسی نود پایش به نود کاندیدا:** کاندیدا فقط `nodeID` می‌دهد، نه IP؛ ولی `admin_addPeer` به enode کامل (با IP) نیاز دارد. پس اتصال یا با کشف شبکه (discovery و bootnode شامل نود پایش) برقرار می‌شود یا کاندیدا خودش به نود پایش وصل می‌شود؛ «static peer به همهٔ ولیدیتورها» به‌تنهایی از `nodeID` ممکن نیست. 🔶 روش دقیق باید در دور Besu اجرا و ثبت شود (VD-8).
- ⚠️ **ناهم‌خوانی بخش ۸.۳ با Vault:** موتور Transit در Vault از secp256k1 پشتیبانی نمی‌کند (راستی‌آزمایی از مستند رسمی Transit، ۲۰۲۶-۱۱-۲۰: فقط `ed25519`، `ecdsa-p256/384/521` و `rsa`؛ ولی HMAC پشتیبانی می‌شود). پس **HMAC `personKey` روی Transit ممکن است ✅**، ولی **امضای تراکنش Ethereum روی Transit ممکن نیست**. راه‌ها: KMS/HSM با secp256k1، افزونهٔ Vault برای Ethereum، یا کلید در Vault KV که فقط سرویس امضا در حافظه بارگذاری کند (🔶 VD-11). [اصلاح ۲۰۲۶-۱۱-۲۱: کلیدهای سرویس اکنون در سرور مدیریت کلید SurKMS نگه‌داری می‌شوند؛ ← offchain-services/sur-kms-spec.md] [اصلاح ۲۰۲۶-۱۱-۲۱ (۲): کلید HMAC `personKey` هم در SurKMS است؛ Vault برای هیچ کلید پروژه لازم نیست]
- **سیاست سرویس امضا:** امضاکننده نباید هر «نتیجهٔ isLive»ی را کورکورانه امضا کند (poller آلوده می‌تواند ولیدیتور دلخواه را تعلیق کند). حداقل: بررسی وضعیت روی زنجیره پیش از امضا (شبیه‌سازی)؛ نیاز به بستهٔ شواهد ذخیره‌شده و هش منطبق؛ سقف تعلیق در بازهٔ لغزان یک‌ساعته (هم‌راستا با آستانهٔ رخداد جمعی ۲۰٪؛ عدد 🔶) که پس از آن توقف و هشدار انسانی است؛ دفتر ثبت هر امضا. چگونگی HA: 🔶 VD-11.

### ✅ مالکیت و اجرا
- **اجرا:** سرویس Verifier و RewardRouter زیر نظر **هیأت‌مدیرهٔ مجمع ولیدیتورها** اجرا می‌شوند (سرور، کلید `verifier`، on-call، پاسخ‌گویی به هشدارها). هیأت‌مدیره می‌تواند اجرا را به یک پیمانکار/اپراتور بسپارد ولی مسئولیت با هیأت‌مدیره است.
- **توسعه:** نرم‌افزار را **کمیتهٔ فنی بنیاد** توسعه می‌دهد؛ کمیتهٔ فنی کلید شبکه نگه نمی‌دارد و Verifier را اجرا نمی‌کند. بودجهٔ کمیتهٔ فنی را هیأت‌مدیرهٔ بنیاد تعیین می‌کند.
- **استقلال سامانهٔ احراز هویت:** سیستم eKYC و Identity Service را کمیتهٔ فنی بنیاد راه می‌برد ولی در عمل باید مستقل عمل کند (بخش ۵.۱ و `sur-identity-registry-spec.md`).

### ✅ افزونگی
✅ **تصمیم نهایی P03: یک Verifier کافی است** — یعنی یک **مرجع تصمیم** (یک کلید `verifier`)؛ چندناظری یا تأیید «دو از سه» اضافه **نمی‌شود**. آنچه در ادامه می‌آید فقط **دسترس‌پذیری (HA) همین یک Verifier** است، نه چند ناظرِ تصمیم‌گیر: چون توقف سرویس فقط تصمیم‌ها را متوقف می‌کند (طبق C01، حفره‌ی مشاهده تخلف فردی نیست و به تعلیق نادرست منجر نمی‌شود)، حداقل ۲ تا ۳ نمونه‌ی polling جانشین (سرورهای جدا) برای جلوگیری از توقف طولانی پیشنهاد می‌شود؛ همه‌ی آن‌ها یک منطق و یک مرجع امضا دارند.

**معماری پیشنهادی — تفکیک «چک‌کردن» از «امضاکردن»:**
این دو نگرانی جنس متفاوتی دارند و بهتر است جدا طراحی شوند:
- **چک‌کردن (polling، خواندن `admin_peers`/بلاک‌ها، تصمیم `isLive`):** ارزان و بی‌خطر برای تکرار — می‌توان ۲ تا ۳ نمونه‌ی جانشین از همین منطق (برای HA) را هم‌زمان اجرا کرد، بدون هیچ هماهنگی بین‌شان؛ چک‌های آف‌چین فقط توی `liveness_log` محلی ثبت می‌شن و هیچ اثر on-chain ای ندارن مگر وقتی محاسبه‌ی نسبت واقعاً به یه **تغییر وضعیت** برسه. ✅ **قاعدهٔ معماری:** فراخوانی توابع on-chain (`recordActivation`/`recordSuspension`/`recordRecovery`) دیگه هر چرخه اتفاق نمی‌افته — فقط وقتی وضعیت واقعاً عوض بشه. اگه دو نمونه‌ی موازی هردو تشخیص بدن یه تغییر وضعیت لازمه و هردو تراکنش بفرستن، دومی به‌سادگی روی زنجیره revert می‌شه (چون قرارداد شرط وضعیت فعلی رو چک می‌کنه — مثلاً `recordSuspension` نیاز به `status == Active` داره که بعد از تراکنش اول دیگه برقرار نیست) — بی‌خطره، فقط یه گس هدررفته برای نمونه‌ی دوم.
- **امضاکردن (نگه‌داری کلید `verifier` و ارسال واقعی تراکنش):** این بخش باید **متمرکز و امن** بماند — نه یک فایل کلید خام کپی‌شده روی هر سرور. پیشنهاد: یک سرویس امضای کوچک و جدا (remote signer)، که خودش می‌تواند با تمرکز کمتر روی گنجایش و بیشتر روی در‌دسترس‌بودن (HA) طراحی شود (مثلاً پشت یک load balancer با چند نمونه‌ی خودش که به سرور مدیریت کلید SurKMS مشترک متصل‌اند؛ SurKMS خودش تک‌نمونه و بدون HA است)، که هر سه نمونه‌ی polling بالا فقط نتیجه‌ی `isLive` محاسبه‌شده‌شان را برایش می‌فرستند و او تراکنش را امضا و ارسال می‌کند.

این تفکیک باعث می‌شود افزونگی در بخش پرهزینه‌تر (polling/چک‌کردن نودها) ساده و ارزان باشد، در حالی که سطح حمله‌ی کلید خصوصی (بخش حساس امنیتی) کوچک و متمرکز می‌ماند.

✅ **تصمیم P03:** بازطراحی قرارداد برای چند آدرس `verifier` هم‌زمان یا تأیید «دو از سه» **انجام نمی‌شود**.

### زبان و پشته‌ی فنی
- **Node.js / TypeScript** — برای هماهنگی با سرویس RewardRouter که با همین پشته طراحی شده (استفاده از `better-sqlite3`).
- کتابخانه‌ی تعامل با زنجیره: `viem` (برای یکسان‌سازی با RewardRouter).
- تعامل با `admin_peers`: یک فراخوانی JSON-RPC خام (`admin_peers`) روی همان نود مانیتورینگ — نیازی به کتابخانه‌ی خاص نیست.
- آزمون: `vitest`؛ بررسی نوع با `tsc --noEmit` (مثل سرویس‌های همجوار)؛ ABI از کامپایل قراردادها (بخش ۱۰.۶).
- ارسال پیامک/پیام تلگرام/پیام بله/ایمیل برای فرآیند وریفای: در حالت ب (پیش‌فرض VD-1) کار Identity Service است؛ در حالت الف 🔶 وابسته به سرویس‌دهنده‌ی انتخابی (باز) و با رابط قابل‌تعویض.

---

## ۵. داده‌های ذخیره‌شده و طرح جداول

⚠️ **اصل حاکم: هیچ داده‌ی خام حساسی (شماره‌موبایل خام، آیدی تلگرام خام، IP خام) هرگز روی زنجیره نمی‌رود — فقط همین‌جا.**

⚠️ **(VD-1، حالت ب = پیش‌فرض)** ستون‌های `phone_raw`، `telegram_raw`، `bale_raw`، `email_raw` و `*_verified_onchain` جدول زیر در پایگاه Verifier **نیستند**؛ این داده‌ها و سیاست نگه‌داری‌شان در Identity Service است (`sur-identity-registry-spec.md` بخش ۳.۵). ستون‌ها فقط برای «حالت الف» نگه داشته شده‌اند. طرح کامل جدول‌های ساخت: بخش ۱۰.۳.

### جدول `validators`
| ستون | نوع | توضیح |
|---|---|---|
| `eth_address` | TEXT PRIMARY KEY | آدرس اتریومی **مالک** ولیدیتور |
| `operator_address` | TEXT | آدرس اپراتور (کلید نود) فعلی؛ هر تعویض (`setOperator`، یا `confirmOperatorReady` پس از تأیید) این ستون را به‌روز می‌کند؛ در پیشنهاد باز (`proposeOperator`) تا تأیید تغییر نمی‌کند (کلید پیشنهادی جدا نگه‌داری می‌شود). یک اپراتور برای چند مالک مجاز نیست |
| `node_id` | TEXT | بخش کلید عمومی enode نودِ اپراتور (ثابت، نه IP) |
| `phone_raw` | TEXT | شماره تلفن خام (رمزنگاری‌شده در حالت سکون توصیه می‌شود) |
| `telegram_raw` | TEXT | آیدی تلگرام خام |
| `bale_raw` | TEXT | آیدی بله خام |
| `email_raw` | TEXT | ایمیل خام |
| `phone_verified_onchain` | BOOLEAN | آخرین وضعیت ارسال‌شده به زنجیره (کش محلی) |
| `telegram_verified_onchain` | BOOLEAN | همان‌طور |
| `bale_verified_onchain` / `email_verified_onchain` | BOOLEAN | همان‌طور |
| `person_key` | TEXT | `HMAC(کد ملی)` از طریق سرویس دسترسی کلید (بخش ۵.۱)؛ کد ملی خام در این جدول نیست |
| `registered_at` | TIMESTAMP | |
| `updated_at` | TIMESTAMP | |
| `seat_id` | INTEGER | شناسهٔ NFT صندلی (`ValidatorSeatNFT.seatOf(owner)`). رکورد ولیدیتور با صندلی جابه‌جا می‌شود: پس از `SeatTransferred` آدرس مالک به خریدار می‌رود و تاریخچهٔ مالکان از بازپخش رویدادها می‌آید (بخش ۱۰.۳) |
| `genesis_founder` | BOOLEAN | از فهرست آدرس‌های مؤسس genesis (پیکربندی) تعیین می‌شود، **نه** از `isFounder(owner)`؛ چون پرچم قرارداد همراه صندلی به خریدار می‌رود (VD-6) |
| `exit_requested_at` | TIMESTAMP NULL | از `ExitRequested` (و `periodStartedAt` در وضعیت `Exiting`). ممنوعیت بازگشت از **درخواست خروج** شروع می‌شود (`permanentlyExited`)، نه از `withdrawStake` |
| `exited_at` | TIMESTAMP NULL | پر می‌شود وقتی `ValidatorsRegistry.withdrawStake()` این آدرس را کامل می‌بیند (یعنی چرخه‌ی خروج تمام شده)؛ مبنای شمارش سیاست نگه‌داری زیر است. برای خارج‌شده یا حذف‌شده، `person_key` همچنان نگه‌داری می‌شود (ممنوعیت بازگشت، بخش ۵.۱) |

### ✅ ۵.۱ یکتایی شخص (`personKey`) و ممنوعیت بازگشت

- **هدف:** هر شخص حقیقی فقط یک صندلی ولیدیتوری داشته باشد؛ هر کس خودش خارج شود یا در بازیابی شبکه از فهرست حذف شود، برای همیشه نتواند دوباره ولیدیتور شود. مؤسسان اولیه (از جمله شرکتی با دو نود) مستثنی‌اند. تنها استثنای بازگشت: `migrateIdentity` برای گم‌شدن کلید مالک (همان شخص، آدرس تازه).
- **فقط آف‌چین:** `personKey` روی زنجیره نمی‌رود و فقط در همین سرویس نگه‌داری می‌شود. محاسبه: `personKey = HMAC(کلید محرمانه، کد ملی)`؛ کلید محرمانه داخل SurKMS است (سرویس دسترسی کلید = متد `kms_hmac`؛ بخش ۴، جزء ۶) و هرگز در پایگاه‌داده یا لاگ نمی‌آید.
- **زمان اعمال:** فقط **هنگام ورود** (درخواست عضویت، خرید NFT صندلی، و ورود برندگان لاتاری): Verifier `personKey` متقاضی را با جدول مقایسه می‌کند؛ اگر این `personKey` قبلاً صندلی فعال دارد یا ولیدیتورِ خارج‌شده/حذف‌شده بوده، فعال‌سازی/تأیید ورود را **نمی‌دهد**. پس از ورود دوباره چک نمی‌شود.
- **منبع کد ملی:** کد ملی از نتیجهٔ eKYC همان متقاضی در Identity Service (`sur-identity-registry-spec.md`) می‌آید؛ هزینهٔ KYC با متقاضی است.
- **پیوند آدرس ↔ `personKey` (🔶 VD-2):** کد ملی در Identity Service (eKYC) است. پیشنهاد: Identity Service برای آدرسِ KYC‌شده از سرویس دسترسی کلید `personKey` می‌گیرد (فقط عملیات HMAC) و `(owner, personKey)` را از مسیر داخلی احرازشده به Verifier می‌دهد؛ **Verifier هرگز کد ملی خام نمی‌بیند** و کلید HMAC را ندارد. تا پیوند نرسیده، فعال‌سازی صندلی غیرمؤسس انجام نمی‌شود (شکست بسته: «نامشخص»، نه تأیید). `migrateIdentity(old, new)` را Identity Service به Verifier خبر می‌دهد تا همان `personKey` به آدرس تازه برود.
- **چه رویدادی ممنوعیت می‌آورد (برگرفته از `permanentlyExited` و `membershipEpoch`):** `ExitRequested` ← ممنوعیت دائم؛ `SeatTransferred` ← **فروشنده** هم ممنوع می‌شود (قرارداد او را «خارج‌شده» می‌شمارد)؛ `SeatMigrated` ← **آدرس قدیم** (کلید گم‌شده) برای همیشه ممنوع می‌شود ولی آدرس جدید همان شخص «خارج‌شده» شمرده نمی‌شود (تنها استثنای ممنوعیت، چون شخص همان است)؛ `RecoveryRemovalRecorded` ← ممنوعیت **موقت**؛ `RecoveryRemovalUpheld` یا گذشتن مهلت اعتراض ۷۲ ساعته بدون اعتراض ← قطعی؛ `RecoveryRemovalCancelled` ← برداشته می‌شود (قرارداد `permanentlyExited` را `false` می‌کند). نتیجه: «برای همیشه» فقط پس از قطعی‌شدن درست است (بخش ۶.۹.۱).
- **مؤسسان:** استثنا بر پایهٔ فهرست آدرس‌های genesis است (پیکربندی)، نه پرچم `isFounder`؛ خریدار صندلی مؤسس `personKey` و `isFullyVerified` دارد و مشمول همین بخش است (VD-6).
- **قرارداد هیچ‌یک از ورودی‌ها را بر پایهٔ `personKey` نمی‌بندد:** `requestMembership`، `enterAsLotteryWinner` و خرید صندلی بدون چک یکتایی شخص انجام می‌شوند؛ تنها ابزار Verifier خودداری از `recordActivation` است و پیامدهای آن (وثیقهٔ قفل؛ اسلات هفتگی از ۲۰۲۶-۱۱-۲۳ در فعال‌سازی مصرف می‌شود، پس خودداری آن را مصرف نمی‌کند) در بخش ۶.۸ (VD-5) آمده است.
- **گم‌شدن کلید مالک (✅ مسیر قراردادی، ۲۰۲۶-۱۱-۲۳؛ جایگزین «مسیری وجود ندارد» در VD-2):** `migrateIdentity` (اوراکل هویت) فقط وضعیت احراز را به آدرس تازه می‌برد؛ صندلی (رکورد، وثیقه، NFT، پاداش پرداخت‌نشده) را `ValidatorsRegistry.migrateSeat(old, new)` می‌برد که فقط Verifier می‌تواند بزند و فقط وقتی `IdentityRegistry.migratedTo(old) == new` باشد؛ هیچ‌یک از دو کلید به‌تنهایی کافی نیست و مالک قدیم نمی‌تواند آن را صدا بزند. آدرس قدیم برای همیشه ممنوع و آدرس جدید خارج‌شده شمرده نمی‌شود؛ پس `personKey` به آدرس جدید منتقل می‌شود (`migratedFrom` در مسیر داخلی بخش ۸.۱). مؤسس بدون رکورد هویتی نمی‌تواند از این مسیر استفاده کند (`migrateIdentity` رکورد می‌خواهد). 🔶 آنچه می‌ماند آف‌چین است: Verifier باید پس از گزارش Identity Service دربارهٔ `migrateIdentity`، خودش `migrateSeat` را بزند (گام سرویس هنوز پیاده نشده است؛ بخش ۳.۱ و ۱۰.۱۱).
- 🔶 نقطهٔ دقیق اعمال روی زنجیره (Verifier فقط تأیید نمی‌دهد یا قرارداد هم چیزی ثبت می‌کند) و مدت نگه‌داری `person_key` برای خارج‌شدگان (ممنوعیت «برای همیشه» نگه‌داری دائم می‌خواهد) باید با مشاور حقوقی و طرح قرارداد نهایی شود.

### جدول `liveness_log`
⚠️ **نکته‌ی مهم:** این جدول مستقیم به تراکنش on-chain وصل نیست — هر ردیفش فقط یه **مشاهده‌ی خام آف‌چین** (هر ۶۰ دقیقه، برای هر ولیدیتور) رو ثبت می‌کنه. اکثریت این ردیف‌ها **هرگز** به یه تراکنش منجر نمی‌شن — فقط وقتی جمع‌بندی چند تای پشت‌سرهم از این ردیف‌ها به یه تصمیم تغییر وضعیت برسه (یا نسبت ۹۵٪ probation/recovery حساب بشه)، یه `status_decisions` تازه (پایین) ساخته می‌شه که به بازه‌ی مشخصی از این ردیف‌ها ارجاع می‌ده.

| ستون | نوع | توضیح |
|---|---|---|
| `id` | INTEGER PRIMARY KEY AUTOINCREMENT | |
| `eth_address` | TEXT | |
| `checked_at` | TIMESTAMP | |
| `method` | TEXT | `'node_sync'` یا `'block_production'` |
| `is_live` | BOOLEAN | نتیجه‌ی چک |
| `detail` | TEXT | جزئیات خام (مثلاً ارتفاع بلاک مشاهده‌شده، یا تعداد بلاک تولیدشده، یا نتیجه‌ی تشخیص جغرافیایی) |
| `decision_id` | INTEGER NULL | اگه این ردیف بخشی از بازه‌ی زمانیِ توجیه‌کننده‌ی یه `status_decisions` بشه، اینجا پر می‌شه — برای بازسازی سریع بسته‌ی شواهد وقتی لازم شد |

### ✅ جدول `status_decisions`
هر ردیف معادل یک تصمیم یا اقدام ثبت‌شدهٔ Verifier روی زنجیره است (`recordActivation`/`recordSuspension`/`recordRecovery`/`recordResume`/`recordPreExitViolation`/`recordRecoveryRemoval`/`confirmOperatorReady`؛ فعال‌سازی مؤسس همان `recordActivation` است). بررسی صندلی منتقل‌شده تراکنش ندارد و فقط ردیف داخلی (`seat_check`) می‌سازد — شامل **کل بسته‌ی شواهدی** که هشش روی زنجیره ثبت شده. این بسته‌ی کامل، **هرگز عمومی منتشر نمی‌شه** — رمزگذاری‌شده، نزد حداقل دو نگهدارنده‌ی مستقل از اپراتور این سرویس نگه‌داری می‌شه (بخش ۸.۳ دربارهٔ نگهدارنده‌ها چیزی ندارد؛ پیشنهاد پیاده‌سازی: بخش ۱۰.۳؛ 🔶 VD-9)، با دسترسی کنترل‌شده برای ولیدیتور موضوع و مرجع رسیدگی (مجمع ولیدیتورها، از طریق نماینده/رابط قابل‌اعتماد).

| ستون | نوع | توضیح |
|---|---|---|
| `internal_id` | INTEGER PRIMARY KEY | شناسهٔ داخلی سرویس |
| `decision_id` | INTEGER NULL | `decisionId` از لاگ `StatusDecisionRecorded` در رسید تراکنش (نه مقدار برگشتیِ تابع). NULL برای `operator_change`، `recovery_removal` و `seat_check` که `decisionId` ندارند |
| `eth_address` | TEXT | ولیدیتور موضوع تصمیم |
| `decision_type` | TEXT | `'activation'`، `'founder_activation'` (همان `recordActivation` برای مؤسس)، `'suspension'`، `'pre_exit'` (`recordPreExitViolation`؛ نوع ثبت‌شده در قرارداد `Suspension` است؛ ستون `violation_at` هم پر می‌شود)، `'recovery'`، `'resume'`، `'operator_change'` (`confirmOperatorReady`)، `'recovery_removal'` (`recordRecoveryRemoval`) یا `'seat_check'` (فقط داخلی، بدون تراکنش: بررسی خریدار صندلی و نود پیوست‌شده) |
| `decided_at` | TIMESTAMP | باید با `block.timestamp` تراکنش on-chain یکی باشه |
| `time_range_start` / `time_range_end` | TIMESTAMP | بازه‌ی زمانی که این تصمیم بر اساسش گرفته شده |
| `rules_version` | TEXT | نسخه‌ی قواعد/آستانه‌ها در لحظه‌ی تصمیم (مثلاً «نسبت ۹۵٪، پوشش ۵۰٪، چرخه‌ی ۶۰دقیقه‌ای») — برای این‌که یه تغییر بعدی پارامترها، بازخوانی تصمیمات قدیمی رو گیج‌کننده نکنه |
| `total_checks` / `positive_checks` | INTEGER | فقط برای `activation`/`recovery` — جمع کل و مثبت که نسبت ۹۵٪ ازش محاسبه شده |
| `evidence_hash` | TEXT | باید دقیقاً با `evidenceHash` ثبت‌شده روی زنجیره یکی باشه (برای تأیید بعدی که بسته دستکاری نشده) |
| `evidence_package_encrypted_ref` | TEXT | اشاره‌گر (نه خودِ داده) به محل نگهداری رمزگذاری‌شده‌ی کامل بسته |
| `tx_hash` | TEXT | هش تراکنش on-chain مربوطه |
| `retention_until` | TIMESTAMP | ✅ پیش‌فرض ۹۰ روز بعد از `decided_at`، ولی اگه پرونده باز بمونه (اعتراض/اختلاف تحویل حل‌نشده)، تا زمان بسته‌شدن پرونده تمدید می‌شه |

### جدول `node_discovery_cache`
| ستون | نوع | توضیح |
|---|---|---|
| `node_id` | TEXT PRIMARY KEY | nodeID نودِ اپراتور |
| `last_seen_ip` | TEXT | آخرین IP دیده‌شده در `admin_peers` |
| `last_seen_at` | TIMESTAMP | |
| `country_code` | TEXT | نتیجه‌ی IP-geolocation روی `last_seen_ip` (مثلاً `IR`) |
| `geo_status` | TEXT | `'iran'`، `'non_iran'` یا `'unknown'` (IP خصوصی/loopback/CGNAT، بی‌نگاشت، یا بانک geo ناموجود). **`unknown` «نامشخص» است و هرگز `non_iran` نیست** |
| `is_iran` | BOOLEAN NULL | `country_code == 'IR'`؛ NULL وقتی `geo_status = 'unknown'`. در گام ۶ جریان کاری (بخش ۶) فقط `false` قطعی `isLive=false` اجباری می‌کند |
| `geo_db_version` | TEXT | نسخه/هش بانک IP-geolocation که نتیجه را داد (در بستهٔ شواهد هم ثبت می‌شود) |

### ✅ سیاست نگه‌داری و حذف داده‌ی خام

**قاعده‌ی کلی (در حالت ب، VD-1، فقط `node_id` در پایگاه Verifier است؛ بقیه سیاست Identity Service است):** داده‌ی حساس خام (`phone_raw`, `telegram_raw`, `bale_raw`, `email_raw`, `node_id`) تا **۱ سال پس از خروج** ولیدیتور از شبکه نگه‌داری می‌شود، سپس حذف می‌شود. استثنا: `person_key` (یک مقدار HMAC یک‌طرفه، نه داده‌ی خام) برای اجرای ممنوعیت بازگشت نگه‌داری می‌ماند (بخش ۵.۱).

**چرا مبنای شمارش «خروج» است، نه «ثبت‌نام»:** اگر شمارش از تاریخ ثبت‌نام باشد، داده‌ی یک ولیدیتوری که سال‌هاست فعال است وسط راه پاک می‌شود — که غلط است، چون تا وقتی فعال است همچنان باید verify شود. پس در واقع دو حالت داریم:
1. **تا وقتی ولیدیتور فعال است (`exited_at IS NULL`):** نگه‌داری بدون هیچ محدودیت زمانی ادامه دارد — چون سرویس هنوز به این داده برای liveness/احراز نیاز دارد.
2. **از لحظه‌ای که `exited_at` پر می‌شود (خروج کامل، یعنی `withdrawStake()` موفق روی زنجیره دیده شود):** یک شمارش‌معکوس ۱ساله شروع می‌شود. یک job دوره‌ای (مثلاً روزانه) رکوردهایی با `exited_at` بیش از ۳۶۵ روز قبل را پیدا می‌کند و فیلدهای `phone_raw`، `telegram_raw`، `bale_raw`، `email_raw`، `node_id` را (نه کل ردیف را) پاک/بی‌نام می‌کند.

**تفکیک مهم — چه چیزی حذف می‌شود، چه چیزی نه:**
- فیلدهای **حساس شخصی** (`phone_raw`, `telegram_raw`, `bale_raw`, `email_raw`, `node_id`) در جدول `validators` بعد از این بازه پاک می‌شوند؛ `person_key` و ستون‌های آدرس باقی می‌مانند.
- رکوردهای جدول `liveness_log` **حذف نمی‌شوند** — چون این جدول از ابتدا هیچ داده‌ی شخصی‌ای ندارد (فقط آدرس اتریومی، timestamp، و نتیجه‌ی بولی)، و آدرس اتریومی به‌هرحال از قبل و برای همیشه روی خودِ زنجیره‌ی عمومی قابل‌مشاهده است — حذفش از دیتابیس داخلی ما هیچ حریم خصوصی‌ای اضافه نمی‌کند، فقط تاریخچه‌ی عملیاتی/حسابرسی را از بین می‌برد که ارزش نگه‌داری دارد.

🔶 این یک تصمیم عملیاتیِ منطقی است، نه یک نظر حقوقی قطعی — پیشنهاد می‌شود همین سیاست در متن Validator Agreement/سپیدنامه هم صریح نوشته شود و نهایتاً توسط مشاور حقوقی تأیید شود.

---

## ۶. جریان کاری — هر دوره‌ی polling (✅ تصمیم قطعی: هر ۶۰ دقیقه)

1. از `ValidatorsRegistry.getValidators()` + جدول داخلی، فهرست کامل ولیدیتورهای تحت پایش را بساز (`Probation` + `Active` + `Demoted` در حال بازگشت + درخواست‌های بخش ۶.۸ که منتظر بررسی سلامت‌اند). ولیدیتور در حال `SelfSuspended` از مجموعهٔ اجماع خارج است و **هیچ چک liveness، هشدار یا تعلیق** برایش انجام نمی‌شود؛ فقط وقتی `requestResume()` بزند بررسی سلامت (بخش ۶.۸) برایش اجرا می‌شود. `Demoted` فقط برای تعلیق ناشی از تخلف/غیرفعالی است. همچنین `Exiting` و `RemovedInRecovery` هرگز چک نمی‌شوند؛ ولیدیتور `Probation` بدون اپراتور ثبت‌شده (`operatorOf = 0`: مؤسسان پیش از `setOperator` و برندگان لاتاری) فقط «منتظر کلید» نشان داده می‌شود و ردیف `liveness_log` نمی‌گیرد.
2. `admin_peers` را از نود مانیتورینگ بخوان؛ جدول `node_discovery_cache` را به‌روزرسانی کن.
3. ✅ **احراز جغرافیایی، پیش‌نیاز هر liveness مثبت:** برای هر peer در `admin_peers`، `remoteAddress` را از طریق پایگاه‌داده/سرویس IP-geolocation (بخش ۲.۴) چک کن. نتیجه (کد کشور، `is_iran: bool`) را در `node_discovery_cache` ذخیره کن. جزئیات کامل قانون و پیامدش در بخش ۶.۵ زیر.
4. برای هر ولیدیتور `Probation`/`Demoted` (و هر درخواست بخش ۶.۸) — چک sync-بودن **نودِ اپراتور** **فقط از طریق حضور در `admin_peers`** انجام می‌شود — یعنی آیا `node_id`ش الان به‌عنوان یک peer متصل به نود مانیتورینگ دیده می‌شود یا نه. عمداً به RPC خودِ نود کاندیدا وصل نمی‌شویم — نه لازم است کاندیدا پورت RPC‌اش را عمومی کند، نه ما نیاز به آن داریم.
   
   🔶 **طراحی‌شده، هنوز پیاده‌سازی/آزموده نشده:** یک پروتکل چالش-و-پاسخِ فعال (`SUR_NODE_CHECK_V1`) که پاسخ‌گویی، اتصال به شبکه‌ی درست، همگامی و دسترس‌پذیری P2P نود را — نه صرفاً حضور منفعل در `admin_peers` — می‌سنجد. مشخصات کامل: `sur-node-check-protocol-spec.md`. هیچ سندی نباید پروتکل را «در حال اجرا» معرفی کند.
5. برای هر ولیدیتور `Active`: ✅ **الگوریتم (تصمیم نهایی C01):** مشاهده‌ی خام «چند وقت است این ولیدیتور بلاکی پیشنهاد نداده» ثبت می‌شود. با `blockperiodseconds=3`، پنجره‌ی ۴ساعته حدود ۴۸۰۰ بلاک است. **صرف پیشنهادنکردن بلاک دلیل کافی برای غیرفعالی نیست** — پیش از هر نتیجه‌گیری باید (الف) **فرصت مشارکت** بررسی شود (با اندازه‌ی مجموعه‌ی ولیدیتور در هر بلاک و چرخش round-robin، ولیدیتور در آن بازه حداقل یک نوبت مورد انتظار داشته است)، و (ب) **سلامت شبکه و پایش** بررسی شود (بخش ۶.۶). اگر یکی از این‌ها برقرار نبود، نتیجه «نامشخص» است، نه «غیرفعال»، و هیچ رویدادی به‌عنوان تخلف ثبت نمی‌شود.
6. ✅ **ترکیب نهایی isLive با نتیجه‌ی گام ۳:** اگر `is_iran == false` برای `node_id` یک ولیدیتور، `isLive` برای آن ولیدیتور **به‌طور اجباری `false` گزارش می‌شود** — صرف‌نظر از این‌که چک sync/تولید بلاک (گام ۴/۵) چه نتیجه‌ای داده باشد. یعنی یک نود می‌تواند کاملاً سالم و درحال‌تولید-بلاک باشد و بازهم `isLive=false` بگیرد، فقط به‌خاطر این‌که خارج از ایران دیده شده. ⚠️ این `isLive=false` برای `Probation`/`Demoted` در نسبت ۹۵٪ اثر مستقیم دارد؛ ولی برای `Active` در `c01-rules-v1` (بخش ۶.۷) قاعدهٔ ۴ می‌گوید «بلاک پیشنهاد داده ⇒ `OK`»، پس نقض جغرافیایی به‌تنهایی تعلیقی نمی‌سازد؛ تناقض در بخش ۶.۵ و 🔶 VD-3 است. `geo_status = unknown` «نامشخص» است، نه `is_iran = false`.
7. نتیجه‌ی این چرخه (`isLive` برای هر ولیدیتور، و کد کشور تشخیص‌داده‌شده) رو در `liveness_log` ثبت کن — **بدون** هیچ تراکنش on-chain ای، مگر این‌که یکی از سه حالت زیر رخ بده:

   **الف) یه ولیدیتور `Probation` به شرط فعال‌سازی رسیده باشه:**
   - `probationPeriod` (۱ هفته) از `periodStartedAt`ش گذشته باشه، **و**
   - نسبت `positive_checks / total_checks` روی کل بازه‌ی probation‌ش ≥۹۵٪ باشه (هردو از `liveness_log` محاسبه می‌شن)
   
   اگه هردو برقرار بود: یه بسته‌ی شواهد کامل بساز (آدرس، نوع=activation، بازه‌ی زمانی کامل probation، نسخه‌ی قواعد فعلی، `total_checks`/`positive_checks`، منبع مشاهده، امضای این سرویس)، یه ردیف در `status_decisions` بساز، `evidenceHash = keccak256(بسته)` رو حساب کن، و `recordActivation(candidate, evidenceHash)` رو صدا بزن.

   **ب) یه ولیدیتور `Active` غیرفعالیِ «تأییدشده» داشته باشه (تصمیم نهایی C01):**
   - **آستانه‌ی تعلیق: ۴ ساعت غیرفعالیِ تأییدشده.** «تأییدشده» یعنی: (۱) در تمام پنجره‌ی ۴ساعته هیچ بلاکی توسط او پیشنهاد نشده، (۲) در همین پنجره فرصت مشارکت داشته، (۳) شبکه در همین پنجره سالم بوده و (۴) داده‌ی مشاهده‌ی خودِ سرویس کامل بوده (بخش ۶.۶). این آستانه یک پارامتر پیکربندی همین سرویس است (روی زنجیره چنین چیزی نیست).
   - ⚠️ **محدودیت زمان تشخیص:** چون بررسی فقط هر ۶۰ دقیقه انجام می‌شود، عبور از آستانه‌ی ۴ساعته در **اولین بررسیِ پس از عبور** تشخیص داده می‌شود؛ یعنی تعلیق عملاً بین ۴ تا ۵ ساعت پس از آخرین بلاک ولیدیتور ثبت می‌شود، نه دقیقاً در ساعت چهارم.
   
   یه بسته‌ی شواهد بساز (آدرس، نوع=suspension، آخرین بلاک ولیدیتور، بازه‌ی مشاهده، فرصت‌های مشارکت‌شده، شاخص‌های سلامت شبکه و کامل‌بودن داده‌ی پایش، منبع مشاهده، داده‌ی اتصال‌peer، نتیجه‌ی تشخیص جغرافیایی اگه اثرگذار بوده، امضای سرویس)، ردیف `status_decisions` بساز، و `recordSuspension(validator, evidenceHash)` رو صدا بزن.

   **ج) یه ولیدیتور `Demoted` به شرط بازگشت رسیده باشه:**
   - `recoveryPeriod` (۴۸ ساعت) از `periodStartedAt`ش گذشته باشه، **و**
   - نسبت موفقیت روی بازه‌ی recovery‌ش ≥۹۵٪ باشه، **و**
   - پرونده‌ی جریمه‌ی معلق همین تنزل‌رتبه بسته شده باشه (`pendingSlashEpoch == 0`؛ وگرنه قرارداد با «resolve the pending slash first» رد می‌کنه). رسیدن زمان به‌تنهایی پرونده رو نمی‌بنده؛ سرویس باید وضعیتش رو بخونه و مسیر تعیین‌شده‌ی پرونده رو دنبال کنه.
   
   همون الگوی (الف)، با نوع=recovery و `recordRecovery(validator, evidenceHash)`.

8. ✅ **پیگیری پرونده‌های باز (جدا از چرخه‌ی polling ساعتی، ولی توسط همین سرویس قابل‌اجراست):** برای هر `suspension` که هنوز `slashOutcome` نهایی نگرفته:
   - اگه `resolveMassFailureCheck` هنوز صدا زده نشده و پنجره‌ی ۱ساعته‌ی رخداد جمعی بسته شده → صداش بزن (permissionless، برای جلوگیری از معطلی پرونده).
   - اگه ولیدیتور ظرف `DELIVERY_DISPUTE_GRACE_PERIOD` خودش `confirmDelivery` نزده → `assertDeliveryDisputed` رو صدا بزن.
   - اگه تحویل ثابت شده، ۷۲ ساعت گذشته، و هیچ اعتراضی ثبت نشده → `executeUncontestedSlash` رو صدا بزن.
   - اگه اعتراضی ثبت شده و ۷ روز رأی‌گیری بدون نصاب گذشته → `resolveAppealIfExpired` رو صدا بزن.

   ✅ **نکته‌ی طراحی:** همهٔ توابع بالا و توابع جدول ۳.۱.۱ `require` صریح دارن — اگه شرطشون برقرار نباشه، کل تراکنش **revert** می‌شه، نه این‌که بی‌اثر و بی‌صدا موفق بشه. پس سرویس صرفاً با چک‌کردن موفقیت/شکست خودِ تراکنش (بدون نیاز به مقایسه‌ی state قبل/بعد) می‌تونه مطمئن بشه اثرش واقعاً اعمال شده.

8-ب. اگر یک `node_id` ثبت‌شده در `admin_peers` پیدا نشد، یک اعلان هشدار برای همان ولیدیتور صف کن (بخش ۳.۲؛ آستانه‌ها و زمان‌بندی در بخش ۶.۶). ✅ اگر `is_iran == false` تشخیص داده شد، یک اعلان هشدار **فوری و جداگانه** (نه فقط هشدار غیبت معمولی) برای همان ولیدیتور و برای هیأت‌مدیره‌ی ولیدیتورها صف کن.

9. ✅ **درخواست خروج (تصمیم نهایی P04):** هر بار که یک ولیدیتور `requestExit` می‌زند: (الف) از همان لحظه دیگر برای او هیچ چک liveness/هشدار/تعلیق جدیدی انجام نده — غیرفعالی پس از درخواست خروج تخلف نیست؛ (ب) ظرف **۷۲ ساعت** از زمان درخواست، رفتار او را **قبل از** آن زمان بررسی کن؛ اگر غیرفعالیِ تأییدشده‌ی ۴ساعته‌ای پیش از درخواست کامل شده بود، `recordPreExitViolation(validator, evidenceHash, violationAt)` را صدا بزن؛ (ج) اگر نشد، هیچ کاری لازم نیست — بعد از ۷ روز برداشت وثیقه آزاد است؛ (د) پس از ثبت پرونده، همه‌ی مراحل بعدی (بررسی رخداد جمعی، تحویل شواهد، اعتراض، رأی مجمع) عیناً مثل تعلیق عادی است.
10. **کارهای دوره‌ای بدون‌مجوز (housekeeping — هر کسی می‌تواند بزند؛ سرویس برای معطل‌نماندن پرونده‌ها می‌زند):** `resolveMassFailureCheck` (پس از بسته‌شدن پنجره‌ی یک‌ساعته)، `assertDeliveryDisputed`، `executeUncontestedSlash`، `resolveAppealIfExpired`، `resolveDeliveryDisputeIfExpired`، `expireRecoveryRemoval` (پس از `resolutionDeadline`). برای هیأت همهٔ کارها **view‌محور** هستند (به رویداد وابسته نیستند) و هر بررسی ساعتی انجام می‌شوند:
    - **تازه‌سازی ماهانه (اولویت اول):** `ValidatorsBoard.refreshDue()` را بخوان؛ اگر `true` بود `refreshBoard([])` بزن (ماه میلادی UTC؛ در هر ماه فقط یک‌بار پذیرفته می‌شود و اگر کس دیگری زده باشد ریورت عادی است، نه خطا). ⚠️ تا آن زمان `hasBoardAuthority` برای همهٔ اعضا `false` است و `syncBoard`، `fillVacancies` و همهٔ اقدام‌های هیأت با «board term ended» ریورت می‌کنند. `votersToSync` معمولاً خالی است: `ValidatorsRegistry` در هر تغییر وضعیت خودش `syncVoter` را صدا می‌زند؛ فهرست فقط وقتی پر می‌شود که سرویس شمارندهٔ رأی یک ولیدیتور را با وضعیتش ناهماهنگ ببیند (`syncVoters`).
    - **پاک‌سازی کرسی‌ها:** برای هر عضو `getBoardMembers()`: اگر `Registry.membershipEpoch(m) != Board.seatMembershipEpoch(m)` یا وضعیتش یکی از `None`، `Exiting`، `RemovedInRecovery` است ⇒ `syncBoard()` و سپس `fillVacancies()` تا وقتی `pendingVacancies() > 0` و کاندیدای واجد شرایط هست. ⚠️ تا آن موقع همهٔ اقدامات هیأت با `call syncBoard() first` ریورت می‌شوند، پس معطل‌نماندنی است. محرک‌ها: `ExitRequested`، **`SeatTransferred` (فروشنده)**، `RecoveryRemovalRecorded` و `StakeWithdrawn`؛ تعلیق (`Demoted`/`SelfSuspended`) اختیار را پایان نمی‌دهد و `syncBoard` لازم نمی‌کند؛ لغو حذف (`RecoveryRemovalCancelled`) کرسی را برنمی‌گرداند (`membershipEpoch` کم نمی‌شود).
    - **اختیاری و بی‌خطر:** `referRecoveryRemovalToAssembly(validator)` وقتی پروندهٔ اعتراض باز (`Objected`) است و کمتر از ۳ عضو بی‌طرف اختیار دارند (قرارداد خودش شرط را می‌سنجد؛ ریورت عادی است)؛ `clearStaleVotes(validator)` برای `Demoted`/`SelfSuspended` پس از آستانه (`recoveryPeriod() + ۳۰ روز`، یا ۳۰ روز برای `SelfSuspended`).
11. **نگهبان کلید:** در هر دوره `Registry.verifier()` با آدرس کلید امضای سرویس مقایسه می‌شود؛ ناهمخوانی (چرخش یا نشت) ⇒ توقف همهٔ تراکنش‌ها (فقط مشاهده و هشدار) تا پیکربندی با کلید تازه (بخش ۷).
12. **بازگشت بی‌نظارت به مجموعه (🔶 VD-4):** با رویداد `RecoveryRemovalCancelled` (لغو حذف در بازیابی که ولیدیتور را بدون تأیید Verifier `Active` می‌کند) فوراً نود (`operatorOf`) سنجیده می‌شود و هشدار فوری به هیأت و ولیدیتور می‌رود؛ ابزار قراردادی دیگری در اختیار Verifier نیست جز `recordSuspension` پس از ۴ ساعت غیرفعالیِ تأییدشده.

### ۶.۵ ✅ شرط الزام حضور فیزیکی نود در ایران

طبق تصمیم پروژه (بخش ۶ سند طراحی بلاک‌چین («الزام حضور فیزیکی نود»)، بخش ۶.۷ سند توکنومیکس)، نود یک ولیدیتور باید **همیشه و بدون استثنا** از لحاظ فیزیکی داخل مرزهای جغرافیایی ایران باشد. این سرویس این شرط را در **همان چرخه‌ی liveness موجود** (نه یک مکانیزم جدا) احراز می‌کند — دلیل ادغام: زیرساخت لازم (خواندن دوره‌ای `remoteAddress` از `admin_peers`) از قبل برای liveness وجود دارد؛ ساختن یک چرخه‌ی جدا فقط برای همین یک چک، تکرار بی‌دلیل زیرساخت است.

**مکانیزم دقیق:**
- منبع IP: همان `network.remoteAddress` که در `admin_peers` برای liveness هم استفاده می‌شود — نه یک ورودی جدا از کاربر یا نود.
- تشخیص کشور: از طریق پایگاه‌داده/سرویس IP-geolocation (بخش ۲.۴).
- پیامد: طبق گام ۶ بالا، هر تشخیص `is_iran == false` باعث `isLive=false` اجباری می‌شود — یعنی این شرط از طریق **همان مسیر پیامدی liveness موجود** (غیبت پیوسته‌ی گزارش مثبت → دموت بعد از آستانه‌ی ۴ساعتِ تأییدشده) اثر می‌گذارد، نه یک مسیر پیامدی جدا.

⚠️ **تناقض شناخته‌شده (🔶 VD-3، یافتهٔ فاز A):** پاراگراف بالا می‌گوید نقض جغرافیایی از مسیر «غیرفعالیِ تأییدشده ۴ساعته» پیامد می‌گیرد؛ ولی در `c01-rules-v1` (بخش ۶.۷) ولیدیتور `Active` که بلاک پیشنهاد داده `OK` است (قاعدهٔ ۴) و فقط `proposed(v) = 0` به `INACTIVE_CONFIRMED` می‌رسد. پس نودِ سالمِ تولیدکنندهٔ بلاک در خارج از ایران **هیچ تعلیقی نمی‌گیرد**؛ پیامد جغرافیایی فقط برای `Probation`/`Demoted` (جلوگیری از فعال‌سازی/بازگشت) واقعی است. برای `Active` سه راه هست: (الف) هیچ پیامد روی زنجیره، فقط هشدار فوری به ولیدیتور و هیأت؛ (ب) قاعدهٔ تازهٔ `NON_IRAN_CONFIRMED` در `c01-rules-v1` که پس از پنجرهٔ مشخصِ پیوستهٔ `non_iran` به `recordSuspension` و مسیر جریمهٔ ۱٪ می‌رسد (خطر: IP-geolocation خطاپذیر است و جریمه سوزانده می‌شود)؛ (ج) تابع قراردادی جدا (`reportGeoViolation()`، تغییر قرارداد). **پیش‌فرض ساخت تا تصمیم مالک: (الف).**

⚠️ **محدودیت صادقانه‌ای که باید صریح گفته شود:** چون پیامد از طریق مسیر liveness موجود اعمال می‌شود، یک نود که به‌تازگی از ایران خارج شده، تا رسیدن به آستانه‌ی ۴ساعتِ تأییدشده (۴ ساعت — تصمیم نهایی C01؛ و چون بررسی هر ساعت است، تعلیق بین ۴ تا ۵ ساعت پس از آخرین بلاک ثبت می‌شود) **دموت نمی‌شود**، نه فوری. اگر هدف پروژه صفر-تحمل و فوری‌بودن پیامد است (نه فقط «مثل هر غیبت دیگه‌ای رفتار کن»)، باید یک مسیر پیامدی جدا و سریع‌تر (مثلاً یک تابع جداگانه در `ValidatorsRegistry.sol` مثل `reportGeoViolation()` که فوری و بدون‌انتظار دموت می‌کند) طراحی شود — این یک 🔶 سؤال باز و تصمیم فنی جداست که هنوز گرفته نشده (به بخش ۹ مراجعه کن).

**دقت و محدودیت IP-geolocation:** تشخیص کشور از روی IP کامل و بی‌خطا نیست — VPN/پروکسی می‌تواند IP را جعل کند. این سرویس فقط می‌تواند «IP گزارش‌شده از کجاست» را احراز کند، نه «کجای فیزیکی واقعی سرور». اجرای این شرط تا حد زیادی متکی به این است که ولیدیتورها آگاهانه همکاری کنند (مثلاً امضای یک تعهدنامه‌ی خارج از زنجیره در کنار این چک فنی) — این محدودیت باید صریحاً به ولیدیتورها اعلام شود.



---

### ۶.۶ ✅ تصمیم نهایی C01/P03 — آستانه‌ها، هشدارها و محدودیت زمان تشخیص

**یک Verifier کافی است** (تصمیم P03). چندناظری یا تأیید «دو از سه» اضافه **نمی‌شود**. هرجا در مستندات «تأیید مستقل ناظران» آمده، به «تصمیم Verifier» تغییر می‌کند؛ استقلال و شفافیت از مسیر بسته‌ی شواهد، اعتراض و رأی مجمع تأمین می‌شود، نه از چندناظری.

| مورد | مقدار |
|---|---|
| دوره‌ی بررسی | هر ۶۰ دقیقه |
| هشدار اولیه | ۱۵ دقیقه غیرفعالی |
| هشدار جدی | ۱ ساعت غیرفعالی |
| آستانه‌ی تعلیق | ۴ ساعت غیرفعالیِ تأییدشده |

**قاعده‌ی زمان‌بندی (به‌خاطر بررسی ساعتی):** هیچ‌یک از این آستانه‌ها در «دقیقه‌ی دقیق» تشخیص داده نمی‌شود؛ هر عبور از آستانه در **اولین بررسیِ بعدی** دیده می‌شود. پس: (الف) به ولیدیتورها **وعده‌ی ارسال هشدار دقیقاً در دقیقه‌ی پانزدهم داده نمی‌شود**؛ متن رسمی: «هشدار پس از عبور از ۱۵ دقیقه، در اولین بررسی بعدی (حداکثر تا ۶۰ دقیقه بعد) ارسال می‌شود»؛ (ب) اگر در یک بررسی هر دو آستانه‌ی ۱۵دقیقه و ۱ساعت عبور شده بود، فقط هشدار **جدی** فرستاده می‌شود؛ (ج) همین محدودیت برای آستانه‌ی ۴ساعته هم صادق است: تعلیق بین ۴ تا ۵ ساعت پس از آخرین بلاک ثبت می‌شود.

**غیرفعالی «تأییدشده» فقط وقتی اعلام می‌شود که همه‌ی این‌ها برقرار باشد:**
۱. در کل بازه هیچ بلاکی پیشنهاد نشده — و ولیدیتور در آن بازه **فرصت مشارکت** داشته (حداقل یک نوبت مورد انتظار با توجه به اندازه‌ی مجموعه در هر بلاک).
۲. **سلامت شبکه:** تولید بلاک در بازه پیوسته بوده (بدون توقف یا تغییر دور غیرعادی که نوبت را برای همه از بین برده باشد)، و مجموعه‌ی ولیدیتورها در بازه به‌طور غیرعادی تغییر نکرده است.
۳. **سلامت پایش:** نود مانیتورینگ همگام و در دسترس بوده، داده‌ی مشاهده‌ی همین سرویس در آن بازه بدون حفره است، و سرویس در بازه بدون قطعی کار کرده است.
۴. **قطعی عمومی ≠ تخلف فردی:** اگر هم‌زمان تعداد زیادی ولیدیتور ساکت شده‌اند یا مشکل عمومی شبکه/زیرساخت یا خرابی خودِ سامانه‌ی پایش دیده می‌شود، هیچ‌کدام تخلف فردی محسوب نمی‌شوند و تعلیقی ثبت نمی‌شود. (اگر با وجود این‌ها پرونده‌ای ثبت شد و در یک پنجره‌ی یک‌ساعته بیش از ۲۰٪ مجموعه را گرفت، معافیت رخداد جمعی قرارداد آخرین سد امنیتی است، نه جایگزین این بررسی‌ها.)

**پس از خرابی خودِ سرویس:** حفره‌ی مشاهده‌ی خود سرویس هرگز به‌عنوان غیرفعالیِ ولیدیتور تعبیر نمی‌شود؛ شمارش ۴ساعته از داده‌ی کامل بعد از رفع خرابی دوباره شروع می‌شود.

🔶 **تعریف عددی «فرصت مشارکت» و «سلامت شبکه»** اکنون در بخش ۶.۷ (`c01-rules-v1`) به‌صورت پیش‌نویس نسخه‌دار و قابل‌بازبینی تعریف شده؛ اعداد آن پیشنهادی‌اند و پیش از راه‌اندازی باید تأیید شوند.

---

### ۶.۷ قاعده‌نامه‌ی نسخه‌دار `c01-rules-v1` — تعریف «بررسی موفق» و «نامشخص» (پیش‌نویس برای بازبینی)

> **وضعیت:** ساختار (چه چیزی سنجیده می‌شود و چه زمانی نتیجه «نامشخص» است) پیشنهاد کامل من است؛ **اعداد داخل [ ] پیشنهادی‌اند و تصمیم نهایی نیستند.** این قاعده‌نامه باید پیش از راه‌اندازی بازبینی و منتشر شود؛ «فقط پیکربندی سرویس» بودن برای نسخه‌ی نهایی کافی نیست، چون بدون این تعریف، دو پیاده‌سازی مختلف از «۴ ساعت غیرفعالی» نتیجه‌ی متفاوت می‌دهند.

هر بررسی ساعتی در لحظه‌ی `t`، برای هر ولیدیتور `Active` مثل `v`، بازه‌ی `W = [t−4h, t]` را (بر پایه‌ی `timestamp` **بلاک‌ها**، نه ساعت سرویس) ارزیابی می‌کند و دقیقاً یکی از سه نتیجه را می‌دهد: `OK`، `INACTIVE_CONFIRMED`، یا `UNKNOWN(کد)`.

**الف) داده‌هایی که هر بررسی می‌سنجد و در `liveness_log.detail` و بسته‌ی شواهد ثبت می‌کند:**
۱. `head_number`، `head_ts` از نود پایش؛ سن سر زنجیره `age = زمان_دیوار − head_ts`.
۲. برای هر بلاک در `W`: `number`، `timestamp`، `miner`، `round` (شماره‌ی دور در `extraData` بلاک) و مجموعه‌ی ولیدیتور **همان بلاک** (`qbft_getValidatorsByBlockNumber` یا `getValidators()` با شماره‌ی بلاک؛ هر دو کلید اپراتورند و برای انتساب به ولیدیتور با `ownerOfOperator` به مالک نگاشت می‌شوند؛ اگر مالک اپراتور را در میانهٔ بازه عوض کرده (`setOperator`، یا `confirmOperatorReady` پس از تأیید Verifier)، بلاک‌های هر دو کلید به همان مالک می‌رسند؛ برای انتقال صندلی با بازپخش رویدادهای `SeatTransferred`، `OperatorSet` و `OperatorChangeConfirmed` از genesis — ✅ F-4، تصمیم مالک ۲۰۲۶-۱۱-۱۹؛ Verifier باید همین منطق را تکرار کند: `sur-reward-router-spec.md` بخش ۱۰.۵). ✅ یافتهٔ F-2 (دور اول Besu ۲۰۲۶-۱۱-۱۹): در حالت `contract` فهرست ولیدیتور در `extraData` سرایند بلاک خالی است؛ فهرست را فقط از `qbft_getValidatorsByBlockNumber` یا قرارداد بخوانید (`round` همچنان در `extraData` هست).
۳. `proposed(v)` = تعداد بلاک‌هایی که `miner = v`.
۴. `expected_turns(v)` = تعداد ارتفاع‌هایی که `v` پیشنهاددهنده‌ی **دور صفر** بوده (از ترتیب round-robin روی مجموعه‌ی همان بلاک و پیشنهاددهنده‌ی بلاک قبلی)؛ `missed_turns(v)` = از آن‌ها، ارتفاع‌هایی که بلاک در دور > ۰ و توسط دیگری ساخته شده. ⚠️ **این قاعده‌ی انتخاب پیشنهاددهنده وابسته به نسخه‌ی Besu است و باید روی شبکه‌ی واقعی راستی‌آزمایی شود پیش از آن‌که تصمیمی بر آن استوار شود.**
۵. `set_size` ابتدا و انتهای `W` و تغییرات مجموعه.
۶. `max_gap` = بیشینه‌ی فاصله‌ی زمانی دو بلاک متوالی در `W`؛ `round_change_share` = سهم ارتفاع‌های با دور > ۰.
۷. `silent_share` = سهم ولیدیتورهای `Active` با `proposed = 0` و `expected_turns ≥ 1`.
۸. **سلامت پایش:** نود پایش همگام (`age ≤ [۳۰ ثانیه]`)، همه‌ی RPCهای لازم موفق، داده‌ی `W` بدون حفره، و فاصله‌ی این بررسی با بررسی قبلیِ خودِ سرویس `≤ [۹۰ دقیقه]`.

**ب) قواعد نتیجه — به ترتیب؛ اولین قاعده‌ی برقرار تعیین‌کننده است:**

| ترتیب | نتیجه | شرط |
|---|---|---|
| ۱ | `UNKNOWN(MONITOR_UNHEALTHY)` | نود پایش همگام نیست، یا RPC لازم شکست خورده، یا داده‌ی `W` ناکامل است |
| ۲ | `UNKNOWN(OBSERVATION_GAP)` | فاصله‌ی دو بررسی متوالی سرویس بیش از حد مجاز، یا سرویس در `W` قطعی داشته |
| ۳ | `UNKNOWN(EMERGENCY_WINDOW)` | `W` با «بازه‌ی استثنای اضطراری» بازیابی اجماع (N04) هم‌پوشان است |
| ۴ | `OK` | `proposed(v) ≥ 1` |
| ۵ | `UNKNOWN(NETWORK_UNHEALTHY)` | `max_gap > [۱۲۰ ثانیه]` یا `round_change_share > [۲۰٪]` |
| ۶ | `UNKNOWN(GENERAL_OUTAGE)` | `silent_share ≥ [۲۰٪]` — قطعی عمومی؛ **هیچ‌کدام تخلف فردی نیست** (هم‌راستا با آستانه‌ی معافیت جمعی، ولی این بررسی پیش از آن و به‌جای آن است) |
| ۷ | `UNKNOWN(NO_OPPORTUNITY)` | `expected_turns(v) < [۳]` — فرصت کافی نبوده (مثلاً مجموعه‌ی بزرگ یا ولیدیتور تازه‌فعال) |
| ۸ | `INACTIVE_CONFIRMED` | `proposed(v) = 0`، `expected_turns(v) ≥ [۳]` و `missed_turns(v) = expected_turns(v)`، و هیچ‌یک از قواعد ۱ تا ۷ برقرار نیست |

⚠️ **انحراف‌های ایمن‌ساز پیاده‌سازی فاز B (۲۰۲۶-۱۱-۲۱؛ `Deployments/Verifier/README.md`):** (۱) `silent_share` ولیدیتوری را هم می‌شمارد که کل پنجره در مجموعه بوده و چیزی پیشنهاد نداده، حتی اگر نوبت دور صفر نداشته (ولیدیتور ساکتِ پشت ولیدیتور ساکت دیگر هرگز پیشنهاددهندهٔ دور صفر نیست و با «`expected_turns ≥ 1`» دو ساکت مجاور یکی شمرده می‌شدند)؛ (۲) قاعدهٔ ۷ برای ولیدیتوری که کل پنجره در مجموعه نبوده هم برقرار است؛ (۳) دو نتیجهٔ `UNKNOWN` تازه: `REPLAY_UNVERIFIED` و `PROPOSER_RULE_MISMATCH`. هر سه فقط می‌توانند اتهام را به «نامشخص» بدل کنند. ⚠️ **یافتهٔ F-V1:** با اعداد پیشنهادی، در مجموعهٔ ۵ ولیدیتور یا کمتر هیچ‌کس هرگز تعلیق نمی‌شود (قاعدهٔ ۵ یا ۶ زودتر برقرار می‌شود)؛ نخستین تعلیق ممکن از ۶ ولیدیتور فعال است؛ این را هنگام تأیید `VD-7` در نظر بگیرید.

**پ) اثر بر هشدارها:** هشدار ۱۵ دقیقه و ۱ ساعت فقط وقتی به ولیدیتور فرستاده می‌شود که قواعد ۱ تا ۳ و ۵ تا ۶ برقرار نباشند و در همان پنجره حداقل یک نوبت مورد انتظار بوده (`expected_turns ≥ 1`)؛ در غیر این صورت هشدار **عملیاتی** به تیم پایش می‌رود («شبکه/پایش مشکوک»)، نه هشداری به ولیدیتور. در اولین بررسیِ بعدی بعد از عبور از آستانه، نه در دقیقه‌ی دقیق.

**ت) نسخه‌بندی و بازبینی:** `rules_version = "c01-rules-v1"` در هر ردیف `liveness_log` و `status_decisions` و بسته‌ی شواهد ثبت می‌شود؛ هر تغییر عدد یا قاعده نسخه‌ی جدید است و نسخه‌ی قبلی قابل‌بازخوانی می‌ماند (تا هر تصمیم قدیمی با قاعده‌ی زمان خودش قابل‌بازبینی باشد). **آزمون پذیرش:** بازپخش داده‌ی واقعی بلاک‌های شبکه‌ی آزمایشی با این سناریوها — ولیدیتور خاموش، قطع نود پایش، توقف شبکه، ۲۰٪ ساکت، ولیدیتور تازه‌فعال — و ثبت اینکه هر سناریو به کدام نتیجه رسید.

**ث) نسبت ۹۵٪ برای `Probation` و `Demoted` (در نسخهٔ قبل تعریف نشده بود؛ پیشنهاد، اعداد داخل [ ] تصمیم نیستند):** هر بررسی ساعتیِ نود اپراتور یکی از سه نتیجه است: `OK` (در `admin_peers` دیده شد، همگام، `geo_status` برابر `iran`)، `FAIL` (نود پایش سالم است ولی نود دیده نشد، ناهمگام است یا `non_iran` قطعی) یا `UNKNOWN` (نود پایش ناسالم، حفرهٔ مشاهده، `geo_status = unknown`). `UNKNOWN` نه در صورت و نه در مخرج می‌آید. `total_checks = OK + FAIL` و نسبت = `OK / total_checks`؛ **پوشش** = `(OK + FAIL) / بررسی‌های مورد انتظار در بازه`. شرط فعال‌سازی یا بازگشت: نسبت ≥ ۹۵٪ **و** پوشش ≥ [۵۰٪]؛ وگرنه «هنوز نه» (قرارداد فقط حداقل زمان می‌گذارد، سقف ندارد؛ دوره ادامه می‌یابد). اگر اپراتور در `Probation`/`Demoted`/`SelfSuspended` عوض شد (`OperatorSet` از `setOperator`)، مشاهدات کلید قدیمی شمرده نمی‌شوند و پنجرهٔ تازه دست‌کم [۴۸ ساعت] با نسبت ≥ ۹۵٪ لازم دارد (قرارداد `periodStartedAt` را بازنشانی نمی‌کند، پس این قاعده را فقط سرویس اعمال می‌کند). مؤسسان: [۶] بررسی `OK` پیاپی، بدون نسبت.

---

### ۶.۸ ✅ بررسی سلامت نود اپراتور در فرایندهای ورود، ازسرگیری و تعویض

همهٔ این فرایندها از **همان بررسی سلامت** (حضور و همگامی نودِ اپراتور در `admin_peers`؛ در آینده پروتکل `SUR_NODE_CHECK_V1`) و **همان شرط حضور فیزیکی در ایران** (بخش ۶.۵) استفاده می‌کنند و فقط شرط شروع و دورهٔ آزمایششان فرق دارد. نتیجه همیشه با بستهٔ شواهد و `evidenceHash` ثبت می‌شود (بخش ۵). نتیجهٔ «نامشخص» هرگز شکست نود نیست.

| فرایند | شرط شروع | چه چیزی بررسی می‌شود | دورهٔ آزمایشی |
|---|---|---|---|
| **ورود عادی** (درخواست عضویت با وثیقهٔ ثابت `entryCollateral`) | درخواست عضویت روی زنجیره | `kycVerified` و `Individual`؛ تلفن، تلگرام، بله و ایمیل احرازشده؛ `personKey` یکتا و بی‌سابقهٔ خروج (بخش ۵.۱)؛ سپس سلامت نود | `probationPeriod` (۱ هفته) و نسبت موفقیت ≥۹۵٪ (بخش ۶ گام ۷-الف) |
| **مؤسسان** (شش نفر پس از اولین؛ `Probation`، `isFounder`) | تعریف کلید نود توسط مؤسس (`setOperator` با آدرس اتریومی خودش؛ فوری، چون مؤسسِ `Probation` در مجموعهٔ اجماع نیست و Verifier پیش از `recordActivation` نود را می‌سنجد) در قرارداد | فقط روشن‌بودن/سلامت نود اپراتور؛ `kycVerified`، احراز تلفن/تلگرام/بله/ایمیل و `personKey` لازم نیست | به شرط تأیید روشن‌بودن نود توسط Verifier وارد فهرست ولیدیتورها می‌شود (🔶 مدت و شدت دقیق بررسی هنوز تعیین نشده؛ پیشنهاد بخش ۶.۷-ث). مؤسس‌بودن از فهرست آدرس‌های genesis (پیکربندی) تعیین می‌شود، نه از `isFounder(owner)`؛ چون پرچم با صندلی به خریدار می‌رود (🔶 VD-6) |
| **ازسرگیری از تعلیق داوطلبانه** | `requestResume()` توسط مالک | سلامت نود اپراتور | **بدون** دورهٔ آزمایشی؛ فقط تأیید Verifier (`recordResume`) |
| **تعویض اپراتور — ولیدیتور `Active`** (`proposeOperator(newOperator)` توسط مالک ← `confirmOperatorReady` توسط Verifier؛ ✅ تصمیم ۱۱۰) | رویداد `OperatorChangeProposed`؛ جایگزینی فوری نیست و فقط با تأیید Verifier اعمال می‌شود | **پیش از** هر تغییر در اجماع: دسترس‌پذیری، همگامی، هویت کلید با چالش امضاشده و توان امضا تا جای ممکن (بخش ۶.۸.۱)؛ ناموفق/نامشخص ⇒ هیچ تراکنشی؛ پیشنهاد پس از ۷ روز منقضی می‌شود | ندارد؛ پس از تأیید همان چرخهٔ عادی `Active` و بدون معافیت از liveness |
| **تعویض اپراتور — بیرون از مجموعهٔ اجماع** (`setOperator(newOperator)` برای `Probation`/`Demoted`/`SelfSuspended`) | رویداد `OperatorSet`؛ تعویض فوری است | نود جدید پیش از ورود یا ازسرگیری (`recordActivation`/`recordRecovery`/`recordResume`) و در چرخهٔ عادی سنجیده می‌شود؛ چون نود هنوز در مجموعه نیست، نود خاموش اجماع را کند نمی‌کند (✅ F-5 فقط ولیدیتور `Active` را تهدید می‌کرد) | بدون معافیت؛ همان مسیر ورود/ازسرگیری |
| **انتقال NFT صندلی** (`ValidatorSeatNFT`) به خریدار | رویداد انتقال | خریدار: یکتایی `personKey` و اینکه قبلاً یا اکنون ولیدیتور نبوده و نیست (`isFullyVerified` و سابقهٔ آدرس را خود قرارداد هنگام انتقال می‌سنجد)؛ صندلیِ `Active` پس از انتقال `Active` می‌ماند (تصمیم مالک ۲۰۲۶-۱۱-۱۹) و پذیرش توافق‌نامه پیش از انتقال با `acceptSeatAgreement(seatId, hash)` ثبت می‌شود (بدون آن انتقال revert می‌کند: «buyer has not accepted the validators' agreement for this seat»؛ پذیرش در همان انتقال مصرف می‌شود و `SeatAgreementBound` هش را به صندلی می‌بندد؛ امضای مقابل بنیاد پس از انتقال، آف‌چین است و روی زنجیره چیزی منتظرش نمی‌ماند؛ پیگیری امضا با بنیاد/هیأت‌مدیره است نه Verifier؛ `SeatTransferAccepted` و مهلت ۳ روزه حذف شده‌اند، ۲۰۲۶-۱۱-۲۳)؛ بازپخش رویدادها باید `SeatAgreementBound` و `SeatMigrated` را هم بخواند (🔶 هنوز پیاده نشده)؛ `onSeatTransferred` پیشنهاد باز تعویض کلید فروشنده و رزرو آن را پاک می‌کند، پس پس از انتقال پیشنهادی از فروشنده برای تأیید `confirmOperatorReady` باقی نمی‌ماند و خریدار پاک شروع می‌کند (commit `0bf7e75`) | هیچ دورهٔ آزمایشی تازه و هیچ `recordResume`ی لازم نیست: نود در چرخهٔ عادی liveness می‌ماند (نود پیوست‌شده به صندلی، یا نود جدید خریدار اگر تعویض اپراتور بزند، دومرحله‌ای برای صندلی `Active`؛ F-5)؛ رأی خریدار از لحظهٔ انتقال شروع می‌شود و به پیشنهادهای پیش از آن رأی ندارد (تصمیم ۱۰۹) |
| **برندگان لاتاری** (`ValidatorLottery`) | رأی/اعلام برنده | نود و شرایط نود راستی‌آزمایی می‌شود؛ شرکت‌کنندگان از پیش `isFullyVerified` شده‌اند (برای خرید بلیط)؛ برندگان با `enterAsLotteryWinner` در حالت `Probation` و بدون وثیقه و کارمزد وارد می‌شوند، ورودشان تابع فاصلهٔ ورود نیست و «ورودیِ پرداخت‌کننده» شمرده نمی‌شوند (اگر Registry رد کند، قرعه‌کشی متوقف نمی‌شود و `entryFailed` ثبت می‌شود) | `probationPeriod` را خودِ قرارداد اعمال می‌کند (برنده با `periodStartedAt` = لحظهٔ ورود در `Probation` می‌ماند و `recordActivation` همان یک هفته را می‌خواهد) و سپس نسبت ≥۹۵٪ (۶.۷-ث). ورود لاتاری اپراتور ندارد؛ برنده باید خودش `setOperator` بزند، تا آن موقع «منتظر کلید» است. ⚠️ قرارداد `isFullyVerified` را هنگام ورود برنده نمی‌سنجد (فقط هنگام خرید بلیط)؛ پس Verifier پیش از `recordActivation` آن را دوباره می‌خواند و `personKey` را هم می‌سنجد (🔶 VD-1). 🔶 امضای توافق‌نامه آف‌چین و بی‌اثر روی قرارداد است |

**فاصلهٔ ورود (✅ تصمیم مالک، در کد از ۲۰۲۶-۱۱-۲۳):** حداکثر **یک** ورودی پرداخت‌کننده در هر `entryWindowSeconds` (مقدار genesis: ۷ روز؛ `maxEntriesPerWindow` اکنون ثابت قراردادی = ۱ است و کلیدش رأی‌پذیر نیست؛ خودِ `entryWindowSeconds` را مجمع ولیدیتورها می‌تواند ۱ تا ۳۰ روز و با گام ±۱ روز عوض کند). شمارش در **فعال‌سازی** است، نه در درخواست: `requestMembership` محدودیت زمانی ندارد و متقاضی در `Probation` منتظر می‌ماند، و `recordActivation` برای ورودی پرداخت‌کننده با «entry window used - only one new paid validator per window» revert می‌کند اگر آخرین فعال‌سازی پرداخت‌کننده (`lastPaidActivationAt`) کمتر از `entryWindowSeconds` پیش بوده باشد؛ اولین فعال‌سازی پرداخت‌کننده هرگز به تأخیر نمی‌افتد. پس **Verifier این قاعده را باید رعایت کند**: پیش از هر `recordActivation` برای ورودی پرداخت‌کننده `nextPaidActivationAllowedAt()` را می‌خواند، اگر فعال‌سازی‌های پرداخت‌کننده هم‌زمان آماده‌اند یکی را در هر پنجره می‌فرستد، به ترتیب زمان درخواست عضویت (`requestMembership`): از میان کاندیداهای آماده و واجد شرایط، آن‌که زودتر درخواست داده اول فعال می‌شود (✅ تصمیم مالک ۲۰۲۶-۱۱-۲۳؛ ترتیب روی زنجیره اجباری نیست و Verifier آن را رعایت می‌کند)، و ورود مؤسسان (شش نفر پس از اولین) و برندگان لاتاری مستثناست (فقط `isPaidEntrant` اسلات مصرف می‌کند، حتی پس از فروش صندلی). 🔶 سرویس هنوز این منطق را ندارد.

**انتقال NFT در شرایط ممنوع:** انتقال صندلی در حال درخواست خروج یا با پروندهٔ جریمهٔ باز ممکن نیست؛ این را خود قرارداد اعمال می‌کند و Verifier فقط وضعیت را می‌خواند.

**خریدار یا متقاضی ناقض یکتایی (🔶 VD-5):** برای خریدار صندلیِ `Active` که `personKey`اش با ولیدیتور دیگر یا ممنوع‌شده‌ای یکی است، Verifier **هیچ ابزار قراردادی ندارد** (`recordSuspension` فقط برای غیرفعالیِ تأییدشده است و برای این کار به‌کار نمی‌رود)؛ فقط هشدار به هیأت و بنیاد. برای صندلی `Probation`، برندهٔ لاتاری و متقاضی ورود فقط `recordActivation` را نمی‌زند؛ ⚠️ پیامد: وثیقه و کارمزد عضویت (۴٪ در مقدار genesis؛ غیرقابل‌بازگشت) قفل است و متقاضی فقط با `requestExit()` از `Probation` بیرون می‌رود. (از ۲۰۲۶-۱۱-۲۳ اسلات پنجرهٔ ورود در فعال‌سازی مصرف می‌شود، نه در درخواست؛ پس خودداریِ Verifier از `recordActivation` اسلات هفتگی را مصرف نمی‌کند و ورودی پرداخت‌کنندهٔ بعدی را معطل نمی‌کند.)

**اپراتور یکتا:** یک اپراتور برای چند مالک مجاز نیست؛ Verifier در جدول `validators` ستون `operator_address` را کنترل می‌کند و در صورت تکرار هشدار به هیأت‌مدیرهٔ ولیدیتورها می‌دهد (اعمال اصلی با قرارداد است).

### ۶.۸.۱ ✅ تأیید تعویض اپراتور ولیدیتور `Active` — `confirmOperatorReady` (تصمیم ۱۱۰، ۲۰۲۶-۱۱-۱۹؛ در کد و آزمون Hardhat؛ سرویس: ✅ فاز C ۲۰۲۶-۱۱-۲۱ نوشته شد، **بازبینی مستقل نشده**، بی‌اثر تا سرویس همراه نود B2 وجود نداشته باشد)

**چرا:** ولیدیتور `Active` نمی‌تواند کلید نودش را فوری عوض کند (`setOperator` برایش ریورت می‌کند)؛ مالک `proposeOperator(newOperator)` می‌زند، کلید رزرو می‌شود و اجماع دست‌نخورده می‌ماند، و **فقط Verifier** پس از بررسی سلامت نود تازه می‌تواند `confirmOperatorReady(owner, newOperator, evidenceHash)` را بزند که جایگزینی را در همان تراکنش اعمال می‌کند. این وظیفهٔ **تازه** است و یافتهٔ F-5 را می‌بندد: نودِ خاموش یا ناهمگام هرگز به مجموعهٔ اجماع نمی‌رسد (هر نوبت چنین نودی ۱۲ ثانیه دور تغییر می‌گرفت و تعداد کافی از آن‌ها زنجیره را می‌ایستاند).

**شروع:** رویداد `OperatorChangeProposed(owner, newOperator, expiresAt)` از لاگ‌های `ValidatorsRegistry` (همان خواندن رویدادهای تعریف/تعویض اپراتور). پیشنهاد باز تا `expiresAt` (۷ روز، `OPERATOR_PROPOSAL_EXPIRY`) معتبر است؛ حالت پیشنهاد از `pendingOperator(owner)` و `pendingOperatorExpiresAt(owner)` خوانده می‌شود. `nodeID` نود تازه را مالک از اپ (`PUT /api/v1/node-id`، بخش ۸.۱) می‌دهد؛ تا آن نرسیده بررسی انجام نمی‌شود («نامشخص»، نه شکست).

**معیارهای بررسی** (همان سبک بررسی‌های بخش ۶.۸ و پروتکل `SUR_NODE_CHECK_V1`؛ همهٔ بررسی‌ها روی نودِ **تازه** و کلید `newOperator` است، و بررسی هر بار تازه انجام می‌شود، نه با نتیجهٔ قدیمی):

1. **دسترس‌پذیری:** نود تازه از بیرون در دسترس است: اتصال P2P با `nodeID` اعلام‌شده در `admin_peers` نود مانیتورینگ دیده می‌شود و سرویس همراه نود به چالش پاسخ می‌دهد (بازبودن پورت یا پاسخ HTTP به‌تنهایی کافی نیست).
2. **همگامی با سر زنجیره:** ارتفاع نود تازه از سر زنجیره (مرجع Verifier) بیش از آستانه عقب نیست و بلاک اخیر انتخاب‌شده را با هش یکسان با مرجع Verifier ارائه می‌کند (🔶 آستانهٔ عقب‌ماندگی عددی تعیین نشده؛ در `rules_version` ثبت می‌شود).
3. **هویت درست کلید (چالش امضاشده):** چالش تازهٔ `SUR_NODE_CHECK_V1` (بخش ۱ تا ۳ آن سند) با کلید پایشِ متصل به (مالک، `newOperator`، `nodeID`) امضا و تأیید می‌شود و آدرس مشتق از کلید عمومی `nodeID` با `newOperator` برابر است؛ یعنی نودی که پاسخ می‌دهد واقعاً صاحب همان کلیدی است که قرارداد جایگزین می‌کند، نه نود دیگری. (🔶 مسیر ثبت کلید پایش برای اپراتور تازه هنوز طراحی نشده: بخش ۶ پروتکل.)
4. **توان تولید commit seal معتبر — تا جایی که قابل آزمون است:** نودِ تازه تا پیش از تأیید در مجموعهٔ اجماع نیست و بلاک امضا نمی‌کند، و کلید امضای بلاک هرگز به سرویس همراه داده نمی‌شود؛ پس این معیار فقط وقتی اعمال می‌شود که روشی امن برای آزمونش باشد (🔶 روش طراحی نشده). اگر آزمون‌پذیر نبود، در بسته ثبت می‌شود «قابل آزمون نبود» و معیار نه رد می‌شود نه جعل؛ ضعف شناخته‌شدهٔ این روش در بخش ۵ پروتکل آمده است.
5. **شرط حضور فیزیکی در ایران** (بخش ۶.۵) برای نود تازه برقرار است.
6. **وضعیت روی زنجیره درست است (پیش از ارسال تراکنش):** `getValidatorInfo(owner).status` هنوز `Active` است، `pendingOperator(owner)` برابر `newOperator` است و `pendingOperatorExpiresAt(owner)` با حاشیهٔ ایمنی هنوز نگذشته (تا تراکنش ریورت و گس هدر نرود). اگر صندلی در این فاصله منتقل شده باشد پیشنهاد فروشنده پاک شده است (`pendingOperator(owner)` صفر)؛ آن‌گاه تأیید نمی‌شود و خریدار باید خودش پیشنهاد بدهد.

**۷. شبیه‌سازی پیش از ارسال (بخش ۳.۱.۱):** `eth_call` روی `confirmOperatorReady` ریورت می‌شود اگر در فاصلهٔ پیشنهاد، کلید تازه خودش مالک ولیدیتور دیگری شده باشد (`requestMembership` با همان آدرس؛ رزرو آن را نمی‌بندد)؛ آن‌گاه تأیید نمی‌شود و مالک باید پیشنهاد تازه بدهد.

**نتیجه:** «موفق» فقط وقتی همهٔ معیارها (جز معیار ۴ در صورت آزمون‌ناپذیری) گذشته باشد؛ «ناموفق» وقتی شکست مشخص و قابل‌انتساب به نود تازه باشد؛ «نامشخص» وقتی مرجع/Verifier مختل بوده یا `nodeID` هنوز نرسیده. بستهٔ شواهد (چالش، پاسخ امضاشده، مرجع مقایسه، نتیجهٔ P2P، علت) نزد دو نگهدارندهٔ مستقل می‌ماند (بخش ۵) و `evidenceHash` آن (غیرتهی؛ قرارداد هش تهی را رد می‌کند) به‌عنوان آرگومان ثبت می‌شود.

**در صورت موفقیت:** Verifier `confirmOperatorReady(owner, newOperator, evidenceHash)` را با کلید `verifier` می‌زند (`newOperator` همان کلیدی است که سنجیده شد؛ پیش از ارسال دوباره از زنجیره خوانده می‌شود)؛ کلید تازه در همان بلاک در `getValidators()` و در مجموعهٔ QBFT می‌آید و رویدادهای `OperatorSet` و `OperatorChangeConfirmed` ثبت می‌شوند. پس از آن `operator_address` در جدول `validators` به‌روز می‌شود و نود تازه در چرخهٔ عادی liveness `Active` می‌ماند (معافیتی از liveness ندارد).

**در صورت شکست (یا نامشخص):** هیچ تراکنشی زده نمی‌شود. پیشنهاد باز می‌ماند: Verifier در دورهٔ بعدی (هر ۶۰ دقیقه) تا پیش از `expiresAt` دوباره می‌سنجد، چون مالک ممکن است نود را درست کرده باشد؛ به مالک (اپ ولیدیتور) علت اعلام می‌شود. اگر تا انقضا (۷ روز) موفق نشد، پیشنهاد خودبه‌خود منقضی و کلید رزروشده آزاد می‌شود (یا مالک زودتر با `cancelOperatorChange()` لغو می‌کند)؛ مالک می‌تواند پیشنهاد تازه بدهد. **هرگز** نباید `confirmOperatorReady` را به‌امید درست‌شدن نود یا با نتیجهٔ ناموفق/نامشخص زد، چون جایگزینی فوری و بی‌بازگشت از سوی Verifier است و همان خطر F-5 را برمی‌گرداند. تا تأیید، کلید قدیمی در مجموعه می‌ماند و نود قدیمی باید روشن بماند؛ شکست بررسی نودِ تازه به‌هیچ‌وجه شکست liveness نودِ قدیمی نیست و با آن شمرده نمی‌شود.

**ثبت:** ردیف در `status_decisions` با `decision_type = 'operator_change'` (`confirmOperatorReady` `decisionId` برنمی‌گرداند؛ شناسهٔ داخلی سرویس و `tx_hash` ثبت می‌شود).

🔶 **باز:** مهلت (SLA) تأیید Verifier از لحظهٔ پیشنهاد (برای تعویض عادی و برای تعویض اضطراری پس از نشت کلید؛ تا تأیید، کلید لو رفته در مجموعه می‌ماند)؛ مقدارهای عددی بالا؛ اینکه چه کسی در ساعات نبودن Verifier رسیدگی کند (پیشنهاد منقضی می‌شود و مالک دوباره پیشنهاد می‌دهد). ⚠️ مسیر دومرحله‌ای روی Besu هنوز آزموده نشده است (دور ۱b/۱c باید BG-03 را روی بایت‌کد جدید دوباره اجرا کند).

### ۶.۹ ✅ هشدار سوزاندن مازاد پاداش در این سرویس نیست

سوزاندن مازاد پاداش را خودِ قرارداد انجام می‌دهد و رویداد `RewardExcessBurned` (هشدار آن‌چین) را می‌زند. هشدار آف‌چین آن را سرویس RewardRouter (توزیع‌کننده) می‌دهد، مثلاً با ایمیل؛ Verifier کاری به توزیع و پاداش ندارد و در این هشدار نقشی ندارد (`sur-reward-router-spec.md` بخش ۱.۱ و ۳.۱).

### ۶.۹.۱ ✅ ثبت حذف در بازیابی شبکه (تصمیم ۲۰۲۶-۱۱-۱۹؛ در کد پیاده شده)

پس از بازگشت شبکه به حالت `contract` (رویهٔ `sur-emergency-consensus-recovery.md`، بخش ۴-ب)، Verifier برای هر ولیدیتوری که در بازهٔ اضطراری امضا نکرده و نودش را خاموش کرده، `recordRecoveryRemoval(validator, recoveryTimestamp, evidenceHash)` را ثبت می‌کند (فقط `verifier`؛ چیزی برنمی‌گرداند و رویداد `RecoveryRemovalRecorded` می‌زند). قرارداد این شرط‌ها را اعمال می‌کند: ولیدیتور باید `Active` باشد؛ `evidenceHash` خالی نباشد؛ `recoveryTimestamp` از اکنون جلوتر نباشد و بیش از ۳۰ روز قدیمی نباشد (🔶 ثابت `RECOVERY_RECORD_MAX_AGE`، در تصمیم نیامده)؛ مجموعهٔ فعال بالای `MIN_ACTIVE_VALIDATORS` بماند؛ پروندهٔ حذف قبلیِ او در وضعیتی جز «ثبت‌نشده» یا «لغوشده» نباشد (پروندهٔ جریمهٔ معلق مانع نیست). وضعیت او `RemovedInRecovery` می‌شود (از `getValidators()` و اختیار هیأت بیرون؛ جریمه ندارد). شاهد: `qbft_getSignerMetrics` برای بازهٔ اضطراری و حضور یا غیبت `nodeID` در `admin_peers`؛ بسته رمزگذاری و هشش ثبت می‌شود. ولیدیتور اعلان می‌گیرد و ۷۲ ساعت مهلت اعتراض دارد (`objectRecoveryRemoval()` بدون ورودی، فقط خودِ او). رسیدگی با `ValidatorsBoard.voteRecoveryRemoval(validator, uphold)` است: ۳ رأی به تأیید یا ۳ رأی به لغو، و موضوع پرونده رأی نمی‌دهد؛ ظرف ۷ روز. اگر کمتر از ۳ عضو هیأت (غیر از موضوع) اختیار داشته باشند، هرکسی `referRecoveryRemovalToAssembly(validator)` را صدا می‌زند و ولیدیتورهای `Active` لحظهٔ ارجاع با `voteRecoveryAssembly(validator, uphold)` رأی می‌دهند (برای تأیید `ceil(2n/3)` رأی لازم است؛ وقتی دیگر ممکن نباشد به آن برسد، لغو تصمیم می‌شود؛ پنجرهٔ ۷ روزهٔ تازه از لحظهٔ ارجاع). نبودِ تصمیم در مهلت = لغو: هرکسی `expireRecoveryRemoval(validator)` را صدا می‌زند، ولیدیتور برمی‌گردد و ممنوعیت دائم برداشته می‌شود. حذف جریمه نیست: وثیقه تا ۹۰ روز پس از `recoveryTimestamp` قفل می‌ماند (`requestExit()` فقط پس از تعیین تکلیف پرونده و گذشتن این ۹۰ روز ممکن است) و ممنوعیت دائم در `personKey` ثبت می‌شود (بخش ۵.۱). 🔶 معیار دقیق تفکیک خاموشی عمدی از گم‌شدن نود بی‌تقصیر. ⚠️ «ممنوعیت دائم» تا قطعی‌شدن موقت است: با `RecoveryRemovalRecorded` در `personKey` «موقت» ثبت می‌شود، با `RecoveryRemovalUpheld` یا گذشتن مهلت اعتراض ۷۲ ساعته بدون اعتراض قطعی می‌شود و با `RecoveryRemovalCancelled` برداشته می‌شود. لغو (با رأی هیأت یا ولیدیتورها، یا انقضا) ولیدیتور را **بدون هیچ تأیید Verifier** به `Active` برمی‌گرداند، حتی اگر نودش عمداً خاموش مانده باشد؛ این تنها مسیر ورود بی‌نظارت به مجموعهٔ اجماع است (🔶 VD-4؛ گام ۱۲ بخش ۶). هنگام ثبت، پیش‌شرط `recordRecoveryRemoval` در جدول ۳.۱.۱ است (پروندهٔ حذف قبلی در وضعیت «ثبت‌نشده» یا «لغوشده»).

### ۶.۱۰ گزارش‌های دورهٔ آزادسازی (مرجع)

گزارش عرضه (روزانه، خودکار از زنجیره، با روش و کد عمومی و امضای هش) و نمای مجموع وثیقهٔ قفل‌شده در Registry و سند تحلیلی هفتگی در دورهٔ آزادسازی (از پایان دورهٔ گذار تا ۶ ماه بعد) منتشر می‌شوند. مسئول: کمیتهٔ توسعهٔ کسب‌وکار (نظارت بازرس)؛ تولید خودکار گزارش‌ها کار نرم‌افزار جدا (`sur-software-inventory.md` آیتم ۱۳) است، نه بخشی از Verifier و بدون هیچ کلید زنجیره‌ای.

---

## ۷. امنیت

- کلید خصوصی `verifier` باید در یک secret manager (نه فایل متنی ساده) نگه‌داری شود.
- `node_id` (و در حالت الف شماره‌موبایل/آیدی تلگرام/آیدی بله/ایمیل) در دیتابیس باید در حالت سکون رمزنگاری شوند؛ دسترسی به دیتابیس باید محدود باشد.
- **تفکیک کلیدها با خودآزمون راه‌اندازی:** بارگذار پیکربندی فقط متغیرهای کلید `verifier` را می‌خواند؛ هنگام شروع، آدرس کلید امضا با `Registry.verifier()` مقایسه می‌شود و اگر با `IdentityRegistry.identityOracle()` یا `BlockRewardDistributor.distributionOracle()` برابر باشد سرویس بالا نمی‌آید (سه کلید هرگز یکی نیستند).
- **چرخش یا نشت کلید `verifier`:** چرخش با ۳ رأی هیأت است و تا اجرا کلید قدیمی معتبر می‌ماند؛ پس سرویس «کلید اضطراری توقف» (فایل/فرمان) دارد که همهٔ ارسال‌ها را می‌بندد و فقط مشاهده می‌کند. پس از `VerifierUpdated` سرویس با کلید تازه راه‌اندازی می‌شود.
- این سرویس یک **نقطه‌ی تمرکز اعتماد واقعی** است — اگر از کار بیفتد، هیچ ولیدیتوری نمی‌تواند از `Probation` عبور کند و هیچ گزارش liveness تازه‌ای ثبت نمی‌شود (ولی طبق تصمیم C01 حفره‌ی مشاهده‌ی خودِ سرویس یا خرابی پایش **تخلف فردی نیست** و هیچ تعلیقی به‌خاطرش ثبت نمی‌شود — پس خرابی سرویس به تعلیق نادرست دسته‌جمعی منجر نمی‌شود، بلکه فقط تصمیم‌ها و فعال‌سازی‌ها متوقف می‌مانند).

### ✅ مانیتورینگ سلامت خودِ سرویس
- **Dead-man's-switch**: هر نمونه از سرویس هر ۵ دقیقه یک پینگ «زنده‌ام» به یک ابزار مانیتورینگ بیرونی (مثل Healthchecks.io) می‌فرستد.
- **آستانه‌ی هشدار: ۲۰ تا ۳۰ دقیقه** بدون پینگ — عمداً خیلی زودتر از آستانه‌ی ۴ساعته‌ی تعلیق، تا فرصت واقعی برای واکنش انسانی قبل از دموت/اسلش نادرست باقی بماند.
- **کانال هشدار باید پیجینگ واقعی باشد** (تماس/پیامک به فرد/تیم مسئول)، نه فقط ایمیل — با توجه به شدت و برگشت‌ناپذیری نسبی عواقب (اسلش).
- **چه کسی پیجر می‌شود — پیشنهاد مشخص:** یک چرخه‌ی on-call بین چند نفر از اعضا یا اپراتورهای منصوب هیأت‌مدیره‌ی ولیدیتورها (چون اجرای سرویس با هیأت‌مدیره است و این‌ها افرادی هستند که از قبل با زیرساخت شبکه درگیرند)؛ کمیتهٔ فنی می‌تواند در رفع اشکال نرم‌افزاری کمک کند ولی خودش سرویس را اجرا نمی‌کند و کلیدی نگه نمی‌دارد. **قاعده‌ی escalation:** اگر نفر اول ظرف ۱۰ دقیقه پاسخ ندهد، هشدار خودکار به نفر دوم چرخه ارسال شود؛ اگر تا ۲۰ دقیقه هیچ‌کدام پاسخ ندادند، به کل چرخه هم‌زمان ارسال شود. مشخص‌کردن اسامی دقیق افراد این چرخه هنوز یک تصمیم عملیاتی جداست (بخش ۹، سؤال باقی‌مانده).
- **لایه‌ی شفافیت اضافه:** چون تراکنش‌های `recordActivation`/`recordSuspension`/`recordRecovery` (وقتی اتفاق می‌افتن) خودشان on-chain و timestamp‌دار هستند، یک دیده‌بان/بات عمومی و مستقل می‌تواند این‌ها را رصد کند. ⚠️ **نکته:** چون تراکنش هر ساعت نیست (فقط موقع تغییر وضعیت)، «آخرین تراکنش X دقیقه پیش» به‌تنهایی نشونه‌ی سلامت سرویس نیست — ممکنه ساعت‌ها هیچ تصمیمی لازم نباشه و این کاملاً طبیعیه. سیگنال سلامت واقعی سرویس باید جدا، از طریق یه heartbeat مستقل (نه تراکنش on-chain) تأمین بشه — به بخش «مانیتورینگ سلامت خودِ سرویس» زیر مراجعه کن.

---

## ۸. پیوست پیاده‌سازی (برای کفایت جهت واگذاری به یک ابزار کدنویسی)

### ۸.۱ رابط API بین اپ همراه و سرویس

احراز هویت با **امضای اتریومی** (الگوی Sign-In-with-Ethereum)، نه رمز عبور — چون کاربر از قبل یک کیف‌پول دارد:

```
GET  /api/v1/challenge?ethAddress=0x...
     → { message: "Sur Verifier — Sign to authenticate — nonce: <random> — expires: <ts>" }

POST /api/v1/register
     body: { ethAddress, signature, nodeId }       (حالت ب؛ در حالت الف: + phone, telegramId, baleId, email)
     → ثبت/به‌روزرسانی رکورد در جدول validators (ethAddress = کلید مالک؛ nodeId = نود اپراتور)

POST /api/v1/phone/request-otp
     body: { ethAddress, signature }
     → ارسال کد به شماره‌ی ثبت‌شده

POST /api/v1/phone/verify-otp
     body: { ethAddress, signature, code }
     → در صورت تطابق: setPhoneVerified(ethAddress, true) روی زنجیره

POST /api/v1/telegram/request-otp   (مشابه بالا)
POST /api/v1/telegram/verify-otp    (مشابه بالا)
POST /api/v1/bale/request-otp       (مشابه بالا)
POST /api/v1/bale/verify-otp        (مشابه بالا)
POST /api/v1/email/request-otp      (مشابه بالا؛ کد به ایمیل)
POST /api/v1/email/verify-otp       (مشابه بالا)

PUT  /api/v1/node-id
     body: { ethAddress, signature, nodeId }
     → به‌روزرسانی nodeId نود اپراتور (پس از setOperator یا proposeOperator روی زنجیره یا نصب مجدد نود؛ برای ولیدیتور `Active` nodeId نودِ پیشنهادی را می‌دهد و تا تأیید Verifier، نود قدیمی در مجموعه است)؛
       بلافاصله وارد چرخهٔ بررسی سلامت (بخش ۶.۸) می‌شود

GET  /api/v1/status/:ethAddress   (بدون نیاز به امضا — فقط خواندنی و غیرحساس)
     → { phoneVerified, telegramVerified, baleVerified, emailVerified, lastLivenessConfirmation, isCurrentlyLive }
```

⚠️ **(VD-1)** مسیرهای `/phone/*`، `/telegram/*`، `/bale/*` و `/email/*` فقط برای «حالت الف» (ماژول `M-OTP` در فرایند جدا) هستند؛ در پیش‌فرض (حالت ب) اپ همان‌ها را به Identity Service می‌زند و Verifier نه این مسیرها را دارد و نه کلید `identityOracle`. `GET /status` وضعیت احراز را از `IdentityRegistry` می‌خواند.

**مسیر داخلی (فقط سرویس‌به‌سرویس، نه عمومی؛ 🔶 VD-2):** `POST /internal/v1/person-bindings` با بدنهٔ `{ ethAddress, personKey, source, migratedFrom? }` از Identity Service، با احراز متقابل (mTLS یا کلید سرویس جدا)؛ فقط `personKey` می‌گیرد، نه کد ملی. هیچ مسیری برای فرمان‌دادن به Verifier یا ثبت تصمیم on-chain نیست.

هر امضا باید یک `message` تازه از `/challenge` (با `expires` کوتاه، مثلاً ۵ دقیقه) امضا کند — جلوگیری از replay.

### ۸.۲ مدیریت خطا و جلوگیری از تراکنش‌های تکراری بین نمونه‌ها

- هر نمونه‌ی polling (بخش ۴، افزونگی) مستقل کار می‌کند و نتیجه‌ی `isLive` محاسبه‌شده‌اش را به سرویس امضای مشترک می‌فرستد؛ **دیدوپلیکیشن در همان سرویس امضای مشترک انجام می‌شود** (نه بین نمونه‌های polling): اگر برای یک آدرس مشخص با همان نتیجه ظرف ۵ دقیقه‌ی اخیر تراکنشی ارسال شده، درخواست تازه نادیده گرفته می‌شود — این هم هزینه‌ی گس اضافی را کنترل می‌کند، هم چون فقط **یک** سرویس امضا nonce را مدیریت می‌کند، هیچ تداخل nonce‌ای بین چند «کیف‌پول» پیش نمی‌آید.
- خطای RPC (نود مانیتورینگ یا نود RPC در دسترس نیست): تا ۳ بار با backoff نمایی (۲، ۴، ۸ ثانیه) تلاش مجدد؛ اگر باز هم ناموفق بود، همان دور polling را رد کن (نه crash کردن کل سرویس) و در لاگ ثبت کن.
- خطای ارتباط با سرویس امضا: نتیجه به‌سادگی رها می‌شود (نیازی به صف نیست، چون دور polling بعدی به‌زودی دوباره محاسبه می‌کند)؛ اگر این وضعیت ادامه‌دار شود، dead-man's-switch (بخش ۷) به‌طور طبیعی آن را می‌گیرد چون هیچ گزارشی موفق نمی‌شود.

### ۸.۳ زیرساخت — سرور مدیریت کلید SurKMS + Docker Compose

**نگه‌داری کلید:** کلید خصوصی `verifier` فقط در **سرور مدیریت کلید SurKMS (A4)** نگه‌داری می‌شود (`offchain-services/sur-kms-spec.md`)؛ سرویس امضا (remote signer) با JSON-RPC (`eth_signTransaction` / `eth_sign`) و گواهی کلاینت mTLS با SurKMS صحبت می‌کند و هیچ کلیدی در پیکربندی یا فایل محلی نیست. (HashiCorp Vault و HSM کنار گذاشته شدند: Transit از secp256k1 پشتیبانی نمی‌کند.)

**اسکلت `docker-compose.yml` (سطح مفهومی، نه نهایی):**
```yaml
services:
  # (سرویس vault حذف شد: [تصمیم مالک ۲۰۲۶-۱۱-۲۱] کلید HMAC `personKey` هم در SurKMS است و کلید `verifier` هم)

  besu-monitor:
    image: hyperledger/besu:26.9.0   # نسخهٔ آزموده‌شده؛ نه latest
    # static-nodes.json شامل enode همه‌ی ولیدیتورها
    volumes:
      - ./besu-data:/data

  # سرویس دسترسی کلید جدا ندارد: Verifier متد kms_hmac("personKey", ورودی) را روی SurKMS صدا می‌زند (فقط HMAC می‌دهد؛ کلید بیرون نمی‌آید)

  verifier-signer:
    build: ./signer
    environment:
      - SIGNER_URL
      - SIGNER_ADDRESS
      - RPC_URL
    # تنها جزئی که با SurKMS (امضاکنندهٔ راه‌دور) حرف می‌زند؛ گواهی کلاینت mTLS؛ هیچ کلیدی در پیکربندی نیست

  verifier-poller-1:
    build: ./poller
    depends_on: [besu-monitor, verifier-signer]
    environment:
      - MONITOR_NODE_RPC
      - CHAIN_RPC_URL
      - SIGNER_SERVICE_URL
      - DB_PATH=/data/verifier.sqlite
    volumes:
      - ./data:/data

  verifier-poller-2:
    # نمونه‌ی دوم، همان تنظیمات، برای افزونگی (بخش ۴)

  api-gateway:
    build: ./api
    depends_on: [verifier-poller-1]
    ports:
      - "443:443"
    environment:
      # (VD-1، حالت ب) کلیدهای ارائه‌دهندهٔ OTP در Identity Service‌اند، نه اینجا؛
      # api-gateway هیچ کلید زنجیره‌ای ندارد
```

⚠️ دو نمونهٔ poller نباید یک فایل SQLite را به‌اشتراک بگذارند (SQLite تک‌نویسنده است؛ بخش ۴): هر نمونه پایگاه خودش را دارد و تصمیم و بستهٔ شواهد فقط از یک نمونهٔ فعال (قفل رهبر) ساخته می‌شود. نسخهٔ اول ساخت تک‌نمونه است (بخش ۱۰.۷).

**فهرست env varهای اصلی:**
| متغیر | توضیح |
|---|---|
| `SIGNER_URL`, `SIGNER_ADDRESS` | آدرس JSON-RPC سرور مدیریت کلید SurKMS و آدرس کلید `verifier` (بدون کلید در پیکربندی؛ گواهی کلاینت mTLS) |
| `CHAIN_RPC_URL` | آدرس RPC نود برای خواندن state/بلاک |
| `MONITOR_NODE_RPC` | آدرس RPC نود مانیتورینگ (برای `admin_peers`) |
| `DB_PATH` | مسیر فایل SQLite |
| `HEALTHCHECK_URL` | آدرس ابزار dead-man's-switch |
| `SMS_PROVIDER_API_KEY`, `TELEGRAM_BOT_TOKEN`, `BALE_BOT_TOKEN`, `EMAIL_PROVIDER_API_KEY` | فقط «حالت الف» (فرایند `M-OTP`)؛ در پیش‌فرض در Identity Service‌اند. 🔶 هنوز باز (سؤال باقی‌مانده #۱، VD-1) |
| `KEY_ACCESS_URL` | آدرس سرویس دسترسی کلید (برای HMAC `personKey`) |

---

## ۹. سؤالات باز

جواب کامل و مشروح موارد حل‌شده در متن اصلی سند آمده (افزونگی: بخش ۴؛ سیاست نگه‌داری داده: بخش ۵؛ مانیتورینگ سلامت: بخش ۷؛ API/الگوریتم/زیرساخت: بخش ۸). فقط موارد واقعاً باقی‌مانده:

| # | مورد |
|---|---|
| ۱ | سرویس‌دهنده‌ی پیامک/تلگرام/بله/ایمیل برای فرآیند وریفای کدام است؟ (VD-1: پیش‌فرض این کار با Identity Service است، نه Verifier) |
| ۲ | اسامی دقیق افراد چرخه‌ی on-call برای پیجینگ (بخش ۷) |
| ۳ | 🔶 انتخاب دقیق سرویس/پایگاه‌داده‌ی IP-geolocation (آفلاین رایگان مثل MaxMind GeoLite2 در برابر API تجاری با دقت بالاتر) و دوره‌ی به‌روزرسانی‌اش — بخش ۲.۴. |
| ۴ | 🔶 آیا پیامد نقض شرط جغرافیایی باید از همان مسیر liveness موجود (دموت بعد از آستانه‌ی ۴ساعتِ تأییدشده) بگذرد، یا نیاز به یک مسیر پیامدی جدا و فوری‌تر (مثلاً تابع `reportGeoViolation()` در `ValidatorsRegistry.sol`) دارد؟ بخش ۶.۵ برای جزئیات. |
| ۵ | 🔶 آیا در کنار این چک فنی (که با VPN/پروکسی قابل‌دورزدن است)، یک تعهدنامه‌ی خارج از زنجیره هم از ولیدیتورها گرفته شود؟ |
| ۶ | 🔶 رویهٔ نشت/چرخش کلید HMAC `personKey` (اکنون داخل SurKMS؛ چرخش‌ناپذیر مگر با باطل‌شدن همهٔ personKeyها؛ **پشتیبان رمزشدهٔ آفلاین تصمیم‌شده (فایل نزد مدیرعامل، عبارت نزد فرد دیگر)**)، و نقطهٔ دقیق اعمال ممنوعیت بازگشت روی زنجیره (بخش ۵.۱) |
| ۷ | 🔶 مدت و شدت دقیق بررسی سلامت نود برای مؤسسان، برندگان لاتاری و خریداران صندلی (بخش ۳.۱ و ۶.۸)؛ ✅ نام توابع تأیید Verifier نهایی است (`recordActivation`، `recordResume`) |
| ۸ | 🔶 مسئول نگهداری کلید امضای هش گزارش‌های دورهٔ آزادسازی (بخش ۶.۱۰) |
| ۹ | ✅ دور اول آزمون Besu برای نسخهٔ ۲.۵ (تعریف کلید نود/اپراتور، تعلیق داوطلبانه، انتقال صندلی با قاعدهٔ قبلی — BG-06؛ دور 1b با BH-06A/BH-06B آن را برای قاعدهٔ «صندلی فعال فعال می‌ماند» دوباره اجرا کرد و گذشت، سوزاندن مازاد پاداش) انجام شد (۲۰۲۶-۱۱-۱۹؛ `testing-evidence/besu-live-test-v25-2026-11-19/`)؛ نقش Verifier در آن آزمون را اسکریپت‌های آزمایشی بازی کردند (آدرس `verifier` در genesis آزمایشی با کلید آزمایشی جایگزین شد)؛ خودِ سرویس هنوز نوشته و آزموده نشده است |
| ۱۰ | ✅ یافتهٔ F-5 بسته شد (تصمیم مالک ۲۰۲۶-۱۱-۱۹ = تعویض دومرحله‌ای؛ در کد و آزمون Hardhat): ولیدیتور `Active` با `proposeOperator` پیشنهاد می‌دهد و Verifier پس از بررسی سلامت نود تازه `confirmOperatorReady` را می‌زند (بخش ۶.۸.۱)؛ `setOperator` فقط بیرون از مجموعهٔ اجماع فوری است. 🔶 باقی: مهلت (SLA) تأیید Verifier؛ آستانه‌های عددی بررسی؛ روش آزمون توان امضا؛ اجرای دوبارهٔ BG-03 روی بایت‌کد جدید در دور ۱b/۱c آزمون Besu (دور ۱b روی بایت‌کد پیش از تعویض دومرحله‌ای ساخته شد؛ نتیجهٔ مسیر جدید هنوز ثبت نشده) |
| ۱۱ | 🔶 یافتهٔ F-1: لاگ Besu در حالت `contract` گاهی `IllegalStateException: Failed validator smart contract call` ثبت کرد (۸ بار در حدود ۱٬۱۰۰ بلاک روی شبکهٔ چندولیدیتوری؛ احتمالاً رقابت بین import بلاک و پردازشگر پیام BFT؛ هر بار یک پیام BFT از دست رفت و فاصلهٔ بلاک‌ها بیش از ۲ ثانیه نشد). پایش این خطا در لاگ نودها و بررسی یا ثبت مسئله در Besu پیش از mainnet لازم است؛ صاحب پایش تعیین نشده. همچنین F-6: بازیابی پس از توقف زیر نصاب ۸۳ ثانیه طول کشید و F-7: `reveal` لاتاری باید در بلاکی تا `target+250` استخراج شود |
| ۱۲ | 🔶 تصمیم‌های مالک `VD-1` تا `VD-12` که هم‌ترازی فاز A (۲۰۲۶-۱۱-۲۰) پیدا کرد: محل OTP، خط لولهٔ `personKey`، پیامد جغرافیایی برای `Active`، بازگشت بی‌نظارت پس از لغو حذف، پیامد ناقض یکتایی، مؤسس‌بودن خریدار، اعداد، پیش‌نیاز پروتکل نود، نگهدارنده‌های شواهد، بانک geo، نگه‌داری کلید و HA، چرخش کلید — جدول کامل در بخش ۱۰.۱۱ |


---

## ۱۰. طرح ساخت v2.5 (فاز A؛ فاز B و فاز C ساخته شد: وضعیت در بلوک پایین)

> **وضعیت ساخت (۲۰۲۶-۱۱-۲۱):** ✅ فاز B: M0..M8، M10، M11، M13..M15 در `Deployments/Verifier` نوشته و روی anvil آزموده شد؛ بازبینی مستقل دور ۱ و ۲ انجام و یافته‌ها رفع شد (`verifier-review-record.md`). ✅ **فاز C: M9 (`confirmOperatorReady`) و M12 (`recordRecoveryRemoval`) نوشته شد؛ کد تازه و بازبینی مستقل نشده** (هر دو خاموش؛ `VERIFIER_ENABLE_OPCHANGE` و `_REMOVAL` اکنون تنظیم معتبرند). M9: سمت Verifier پروتکل `SUR_NODE_CHECK_V1` با قالب سیمیِ پیشنهادیِ این ساخت، مسیر ثبت کلید پایش `PUT /api/v1/node-check-key`، پیش‌فرض VD-8 (فقط پروتکل چالش؛ تنزل‌یافته پذیرفته نیست)؛ **بی‌اثر تا سرویس همراه نود (B2) وجود نداشته باشد**. M12: انسان *پروندهٔ بازیابی* را ثبت می‌کند و سرویس هرگز کسی را معرفی نمی‌کند؛ معیار خاموشی عمدی باز می‌ماند (۶.۹.۱)؛ پیش‌شرط‌های عینی و سقف f = ⌊(n−1)/3⌋؛ برای VD-4 پس از لغو برای همان پرونده دوباره حذف ثبت نمی‌شود. M-OTP: **در Verifier نیست** (VD-1 حالت ب؛ سطر ⚠️ بخش ۸.۱ مسیرهای OTP را فقط حالت الف و فرایند جدا می‌داند؛ رابط Identity Service با Verifier همان `POST /internal/v1/person-bindings` با HMAC است). یافته‌های تازه F-C1 (قرارداد: `confirmOperatorReady` کلیدی را که اعمال می‌کند نام نمی‌برد؛ پیشنهاد `confirmOperatorReady(owner, newOperator, evidenceHash)`)، F-C2، F-C3، F-C4: README سرویس و `verifier-review-record.md` بخش «فاز C». هنوز ساخته نشده: M16 (Besu زنده). تصمیم‌های مالک ۲۰۲۶-۱۱-۲۱ (`sur-offchain-decisions.md`): VD-8 پیش‌فرض پذیرفته (آنچه پروتکل باز می‌گذارد: ثبت کلید پایش، آزمون commit seal، دسترسی نود پایش به کاندیدا، هنوز پیشنهاد این ساخت است)، VD-4 تغییر قرارداد پیش از genesis (انجام‌نشده)، VD-7 اعداد با داده پس از مشاهده.
>
> **وضعیت پس از قرارداد نهایی و SurKMS (۲۰۲۶-۱۱-۲۲):** ✅ قراردادهای سنجاق‌شده از `GenesisBuilder/contracts` دوباره همگام شدند (VD-4، VD-13، RD-12، RD-18، KmsDirectives). ✅ **VD-13:** `confirmOperatorReady(owner, newOperator, evidenceHash)`؛ سرویس همان کلید سنجیده‌شده را می‌فرستد، هش شواهد آرگومان ۲ است، سیاست امضا کلید داخل calldata را با پیوند ذخیره‌شده می‌سنجد و پیش از هر ارسال زنجیره را دوباره می‌خواند؛ ریورت «operator differs» نتیجهٔ عادی است و هشدار `OPERATOR_PROPOSAL_CHANGED` می‌دهد؛ یافتهٔ F-C1 بسته شد؛ پرچم `ENABLE_OPCHANGE` همچنان خاموش. ✅ **VD-4:** پس از لغو حذف (رأی هیأت، انقضا، رأی ولیدیتورها) ولیدیتور `SelfSuspended` با درخواست ازسرگیری باز است و فقط پس از سنجش نود با `recordResume` برمی‌گردد (هر سه مسیر روی anvil آزموده شد)؛ هشدار `UNSUPERVISED_RETURN_TO_SET` حذف و `RECOVERY_REMOVAL_CANCELLED` جایگزین شد. ✅ **mTLS به SurKMS:** گواهی کلاینت، کلید، CA و توکن اختیاری از فایل (همنام RewardRouter با پیشوند `VERIFIER_`)؛ `eth_signTransaction` و `eth_sign` بدون تغییر. ✅ **`kms_hmac`:** کلاینت `KmsKeyAccessClient` پشت رابط `KeyAccessClient` (بدون Vault). ✅ **امضاکنندهٔ یگانه** (کلید `verifier` برای کارهای بدون مجوز هم) پیش‌فرض مستند است و امضاکنندهٔ دوم اختیاری همچنان کار می‌کند. ✅ **بازبینی مستقل دور ۳** (فاز C و این تغییرها) انجام شد (`verifier-review-record.md`): یافتهٔ شدت بالا نبود، یک یافتهٔ متوسط رفع شد. آزمون: ۲۴ فایل، ۴۲۱ آزمون (۲۱۹ واحد، ۲۰۲ anvil)، `tsc` و `eslint` پاک. **هنوز نشده (به‌روز ۲۰۲۶-۱۱-۲۲: اجرای اول M16 روی Besu 26.9.0 با SurKMS واقعی انجام شد؛ بخش بعد):** سرور واقعی SurKMS در تولید، بازبین انسانی و حسابرسی بیرونی؛ سرویس همراه نود B2 هنوز نیست پس M9 بی‌اثر است. SurKMS باید فقط `Verifier/src/signer/remote.ts` را دوباره vendor کند.
>
> **وضعیت طرح (فاز A):** طرح ساخت پیشنهادی برای `Deployments/Verifier` (شاخهٔ `v2.5-dev`)، هم‌سبک با `GenesisBuilder`، `RewardRouter` و `IdentityRegistry` (TypeScript، ESM، `viem`، `better-sqlite3`، `pino`، `vitest`، `tsc --noEmit`؛ README فارسی و انگلیسی). 🔶 = تصمیم مالک (فهرست در ۱۰.۱۱). همهٔ اعداد داخل [ ] پیشنهادند.

### ۱۰.۱ ماژول‌ها، فراخوان‌های on-chain و کلید هر کدام

| ماژول | کار | فراخوان on-chain (کلید) | اندازه / ریسک |
|---|---|---|---|
| `M0 scaffold` | بسته، `contracts/` همگام‌شده با هش (مثل GenesisBuilder `contracts:sync` و `SOURCES.json`)، تولید ABI از کامپایل، بارگذار پیکربندی و خودآزمون جداسازی کلید | — | S / متوسط |
| `M1 chain` | خواننده‌های Registry، Board، IdentityRegistry، SeatNFT، Lottery؛ نشانگر لاگ؛ **بازپخش رویداد** (`OperatorSet`، `OperatorChangeConfirmed`، `SeatTransferred`، و از ۲۰۲۶-۱۱-۲۳ `SeatAgreementBound` و `SeatMigrated`؛ 🔶 هنوز پیاده نشده) روی پایهٔ state بلاک ۰ و نگاشت بلاک←مالک | فقط خواندن | M / **بالا** (F-4) |
| `M2 state` | SQLite، مهاجرت‌ها، `tx_outbox` (قصد تراکنش پیش از broadcast)، تنظیمات | — | M / متوسط |
| `M3 monitor` | `admin_peers`، `qbft_*`، کش کشف نود، `GeoIpProvider` | فقط RPC نود پایش | M / متوسط |
| `M4 rules` | ارزیاب `c01-rules-v1` برای `Active`؛ نسبت ۹۵٪ برای `Probation`/`Demoted` (۶.۷-ث) | — | L / **بالا** (تعلیق نادرست) |
| `M5 evidence` | ساخت بسته (JSON متعارف)، `keccak256`، امضا، ذخیرهٔ رمزشده نزد ≥۲ نگهدارنده، نگه‌داری و تمدید | — | M / بالا |
| `M6 signer` | رابط `TxSigner` (کلید آزمایشی در آزمون؛ تولید: بسته به VD-11)، سیاست امضا، اجراکنندهٔ `tx_outbox` با «شبیه‌سازی اول» | همهٔ تراکنش‌ها (`verifier`) | M / بالا |
| `M7 entry` | `recordActivation` (عادی، مؤسس؛ برای ورودی پرداخت‌کننده با رعایت `nextPaidActivationAllowedAt()`: یک فعال‌سازی در هر پنجره؛ 🔶 هنوز پیاده نشده)، `recordRecovery`، `recordResume`؛ و گام `migrateSeat` پس از گزارش Identity Service (🔶 هنوز پیاده نشده)؛ پیش‌شرط ایمنی نود؛ کنترل `personKey` و `isFullyVerified` پیش از ارسال | `Registry.recordActivation/recordRecovery/recordResume` (`verifier`) | M / **بالا** (قفل اجماع) |
| `M8 enforce` | `recordSuspension`، `recordPreExitViolation`، پیگیری پرونده‌ها (`housekeeping` پرونده) | `Registry.recordSuspension/recordPreExitViolation` (`verifier`)؛ `resolveMassFailureCheck`، `assertDeliveryDisputed`، `executeUncontestedSlash`، `resolveAppealIfExpired`، `resolveDeliveryDisputeIfExpired` (بدون‌مجوز) | L / **بالا** |
| `M9 opchange` | `confirmOperatorReady` با معیارهای ۶.۸.۱؛ وابسته به پروتکل `SUR_NODE_CHECK_V1` | `Registry.confirmOperatorReady` (`verifier`) | M / بالا؛ ✅ فاز C ساخته شد (بازبینی‌نشده؛ بی‌اثر تا سرویس همراه B2)؛ پیش‌فرض VD-8 پذیرفته |
| `M10 person` | رابط `KeyAccessClient`، پیوند آدرس↔`personKey`، چرخهٔ ممنوعیت، مسیر داخلی Identity Service | — | M / بالا (حریم خصوصی) |
| `M11 board` | `refreshBoard`، `syncBoard`، `fillVacancies`، `syncVoters`، `referRecoveryRemovalToAssembly`، `clearStaleVotes` | `Board.*` بدون‌مجوز (آدرس سرویس برای گس) | S / کم |
| `M12 removal` | تشخیص ولیدیتور خاموش‌کنندهٔ بازیابی و `recordRecoveryRemoval`؛ `expireRecoveryRemoval` | `Registry.recordRecoveryRemoval` (`verifier`)؛ `expireRecoveryRemoval` (بدون‌مجوز) | M / متوسط (اضطراری؛ طراحی ابزار بازیابی هنوز نیست)؛ ✅ فاز C ساخته شد (بازبینی‌نشده): پرونده را انسان ثبت می‌کند، سرویس کسی را معرفی نمی‌کند |
| `M13 api` | `node:http`: challenge/register/node-id/status و مسیر داخلی؛ احراز با امضای EIP-191 | فقط خواندن | S–M / متوسط |
| `M14 ops` | هشدار (ایمیل/پیجر؛ رابط `AlertSink`)، dead-man's-switch، قفل تک‌نمونه، کلید توقف اضطراری، `status` | — | S / متوسط |
| `M15 cli/docker` | `serve`، `run-once`، `dry-run`، `status`؛ Dockerfile، compose، README فارسی و انگلیسی | — | S / کم |
| `M16 live-scenarios` | اسکریپت‌های سناریو برای Besu واقعی (اجرا جداگانه و با تأیید مالک) | **اجرای اول ۲۰۲۶-۱۱-۲۲:** `Deployments/BesuLive` و `testing-evidence/besu-live-v26/stage4/RESULT-verifier-fa.md` (قالب `admin_peers`/`extraData`/`qbft_*` تأیید، ترتیب پیشنهاددهنده هم‌خوان با QBFT واقعی، تعلیق واقعی یک ولیدیتور خاموش با امضای SurKMS روی Besu؛ M9 و M12 و ورود آزموده نشد) | M / کم |
| `M-OTP` (اختیاری) | فقط «حالت الف»: OTP و `setXVerified`؛ **فرایند و پکیج جدا با کلید `identityOracle`** | `IdentityRegistry.set*Verified` (`identityOracle`) | M / بالا؛ **در Verifier ساخته نمی‌شود** (VD-1 حالت ب = کار Identity Service)؛ در فاز C مستند شد و آزمونی آن را قفل می‌کند |

**جداسازی کلید:** فرایند Verifier هیچ‌وقت `identityOracle` یا `distributionOracle` را نمی‌خواند. فراخوان‌های بدون‌مجوز با همان آدرس سرویس (برای گس) فرستاده می‌شوند؛ 🔶 گزینهٔ جدا کردن آن‌ها روی آدرس بی‌اختیار دیگر (کاهش سطح حمله) در VD-11 است.

### ۱۰.۲ جریان داده در یک چرخهٔ ساعتی (خلاصه)

`M1` رویدادهای تازه را می‌خواند و state را به‌روز می‌کند ← `M3` `admin_peers` و بلاک‌های بازه را می‌گیرد و geo را می‌سنجد ← `M4` برای هر ولیدیتور یک نتیجه می‌دهد (`OK`/`INACTIVE_CONFIRMED`/`UNKNOWN(کد)` یا برای `Probation`: `OK`/`FAIL`/`UNKNOWN`) ← فقط اگر **تغییر وضعیت** لازم بود: `M5` بسته می‌سازد و نزد نگهدارنده‌ها می‌گذارد ← `M6` قصد را در `tx_outbox` می‌نویسد، شبیه‌سازی می‌کند، می‌فرستد و رسید را (با `decisionId` از لاگ) ثبت می‌کند ← `M11`/housekeeping ← heartbeat. هر مرحله‌ای که شکست بخورد نتیجه‌اش «نامشخص» است و تراکنشی نمی‌زند.

### ۱۰.۳ داده‌های آف‌چین و جای نگه‌داری

| داده | کجا | حساسیت / نکته |
|---|---|---|
| `personKey` = `HMAC-SHA256(کلید محرمانه، کد ملی ۱۰رقمی با صفر پیشرو، برچسب sur-personkey-v1)` | HMAC فقط داخل SurKMS (`kms_hmac`؛ تصمیم مالک ۲۰۲۶-۱۱-۲۱؛ پیش‌تر Vault Transit `hmac`)؛ نتیجه در جدول `person_bindings` Verifier | کد ملی خام در Verifier نیست؛ Identity Service آن را از eKYC دارد و از KAS HMAC می‌گیرد (🔶 VD-2) |
| `person_bindings`، `person_status` | SQLite Verifier | آدرس↔`personKey`؛ وضعیت `active`/`provisional_ban`/`final_ban`/`lifted` با ارجاع به رویداد |
| `seats`، `registry_events` | SQLite | صندلی، مالک جاری، اپراتور، نود، پایهٔ بلاک ۰ و رویدادهای بازپخش‌شده با کلید `(block_number, log_index)` و اعمال idempotent |
| `node_registrations` | SQLite | `(owner, operator, node_id, source)`؛ `node_id` رمزشدهٔ فیلدی؛ پیشنهادی در برابر جاری جدا |
| `liveness_log`، `node_discovery_cache` | SQLite | بخش ۵؛ IP خام فقط در کش کوتاه‌مدت و با سیاست نگه‌داری |
| `status_decisions`، `evidence_packages` (فقط نمایه) | SQLite | بخش ۵ |
| **بستهٔ شواهد** | فایل رمزشده (AES-256-GCM با کلید داده‌ی بسته‌شده برای دست‌کم ۲ گیرنده؛ نگهدارنده‌ها مستقل از اپراتور) و کپی در ≥۲ مخزن مستقل؛ تراکنش فقط پس از ذخیرهٔ موفق در هر دو | JSON متعارف (RFC 8785)؛ `evidenceHash = keccak256(بایت‌های JSON پاکت)`؛ پاکت = `{body, sig}` و `sig` امضای هش `body` با کلید سرویس (RFC 6979 قطعی). فهرست محتوا: بخش ۵ و ۶. 🔶 هویت نگهدارنده‌ها: VD-9 |
| `tx_outbox` | SQLite | حالت‌ها `prepared → submitted ⇄ unknown → confirmed/reverted` مثل `epoch_txs` در RewardRouter؛ پیش از broadcast نوشته می‌شود |
| `api_challenges` | SQLite | nonce با TTL ≈ ۵ دقیقه، یک‌بارمصرف |
| `service_state` | SQLite | آخرین چرخهٔ کامل، heartbeat، آخرین بلاک پردازش‌شده |

**ژئولوکیشن:** `remoteAddress` هر peer از `admin_peers` (قالب `ip:port`، IPv6 با `[ ]`) تجزیه می‌شود؛ IP خصوصی، loopback و CGNAT ⇒ `unknown`. رابط `GeoIpProvider.lookup(ip) → { country | null, dbVersion }`؛ پیاده‌سازی تولیدی (پایگاه آفلاین مثل GeoLite2) و ساختگی (برای آزمون) قابل‌تعویض؛ نسخه/هش بانک در بسته می‌آید. 🔶 انتخاب بانک (VD-10). **liveness:** `Probation`/`Demoted` از حضور `id` در `admin_peers` (و، اگر در Besu 26.9 راستی‌آزمایی شد، هش سر زنجیرهٔ peer برای همگامی)؛ `Active` از `miner` بلاک‌ها و `qbft_getSignerMetrics`.

### ۱۰.۴ پیکربندی

متغیرهای `VERIFIER_*` فقط: `CHAIN_RPC_URL`، `MONITOR_RPC_URL`، `DB_PATH`، `EVIDENCE_DIR` و فهرست نگهدارنده‌ها (کلیدهای عمومی)، `SIGNER_*` (نوع و نشانی؛ بدون کلید خام در فایل)، `GENESIS_OWNERS_FILE` (آدرس مالک مؤسسان و کلید اپراتور ولیدیتور اول برای پایهٔ بازپخش)، `GEOIP_DB_PATH`، `KEY_ACCESS_URL`، `IDENTITY_SERVICE_*` (تأیید متقابل مسیر داخلی)، `HEALTHCHECK_URL`، `ALERT_*`، `API_*`، `RULES_VERSION`، و **کلید روشن/خاموش هر نوع تصمیم** (`ENABLE_ACTIVATION`، `ENABLE_SUSPENSION`، `ENABLE_PRE_EXIT`، `ENABLE_OPCHANGE`، `ENABLE_REMOVAL`، `ENABLE_HOUSEKEEPING`؛ همه پیش‌فرض خاموش؛ حالت `OBSERVE_ONLY` فقط مشاهده و ثبت می‌کند و تراکنش نمی‌زند). آستانه‌های `c01-rules-v1` در پیکربندی نسخه‌دار با `rules_version` می‌آیند. بارگذار فقط متغیرهای خودش را می‌خواهد و وجود متغیر کلید نقش دیگر (`IDENTITY_ORACLE_*`، `DISTRIBUTION_ORACLE_*`) را خطای شروع می‌داند؛ آزمونی همین را قفل می‌کند.

### ۱۰.۵ حالت‌های خطا

| خطا | رفتار |
|---|---|
| RPC زنجیره/پایش قطع یا کند | چرخه رد می‌شود؛ نتیجهٔ `UNKNOWN(MONITOR_UNHEALTHY)`؛ هیچ تراکنشی؛ هشدار پس از آستانه |
| نود پایش ناهمگام | `UNKNOWN`؛ شمارش ۴ساعته از داده‌ی کامل بعدی دوباره شروع می‌شود |
| ریست سرویس وسط ارسال | `tx_outbox` پس از بازگشت وضعیت را از رسید/nonce تطبیق می‌دهد؛ ارسال تکراری بی‌خطر است (ریورت روی زنجیره) |
| گس ناکافی | توقف ارسال، هشدار فوری؛ مشاهده ادامه دارد |
| SurKMS/امضاکننده در دسترس نیست (یا SurKMS قفل است) | هیچ تراکنشی؛ هشدار؛ مشاهده ادامه دارد |
| ذخیرهٔ بسته نزد یکی از نگهدارنده‌ها شکست خورد | تراکنش زده نمی‌شود |
| Identity Service یا KAS در دسترس نیست | پیوند `personKey` نمی‌رسد ⇒ فعال‌سازی غیرمؤسس انجام نمی‌شود (شکست بسته) |
| بانک geo ناموجود/کهنه | `geo_status = unknown` ⇒ `UNKNOWN`، نه `non_iran` |
| `verifier()` ≠ کلید سرویس | توقف ارسال و هشدار (گام ۱۱) |
| تعلیق‌های هم‌زمان بیش از سقف لغزان | توقف و هشدار انسانی (سیاست سرویس امضا، بخش ۴) |
| حفره در لاگ رویدادهای قدیمی | بازپخش متوقف و هشدار؛ هرگز جایگزینی با نگاشت جاری (همان قاعدهٔ Router) |
| QBFT نهایی است (بدون reorg) | نیازی به منطق reorg نیست؛ ولی نشانگر لاگ با ارتفاع نهایی‌شده پیش می‌رود |

### ۱۰.۶ راهبرد آزمون در برابر قراردادهای واقعی

**ابزار موجود (بررسی‌شده):** `Plan/contracts-tests` آزمون Hardhat درون‌فرایندی با روش «شبیه‌سازی و استخراج» است؛ `Deployments/GenesisBuilder` از Foundry `anvil` (آزموده با ۱٫۸٫۵؛ روی این ماشین ۱٫۸٫۵ است) و `solc` ۰٫۸٫۲۴ و برای راستی‌آزمایی Besu زندهٔ Docker (`hyperledger/besu:26.9.0`) استفاده می‌کند.

**راهبرد پیشنهادی (سه لایه):**
1. **واحد (بدون زنجیره):** `c01-rules-v1`، نسبت ۹۵٪، JSON متعارف و هش، چرخهٔ ممنوعیت `personKey`، تجزیهٔ `remoteAddress`، بارگذار پیکربندی و جداسازی کلید.
2. **یکپارچه روی EVM واقعی (لایهٔ اصلی):** `globalSetup` یک `genesis.json` با **CLI خودِ GenesisBuilder** از قراردادهای همگام‌شده می‌سازد (پیکربندی `examples/genesis-config.local-test.json`؛ نتیجه با هش `SOURCES.json` کش می‌شود) و `anvil --init` آن را بالا می‌آورد؛ یعنی دقیقاً همان بایت‌کد و state seed شده که به Besu می‌رود. **راستی‌آزمایی در همین جلسه (نه بخشی از کد):** ساخت genesis ≈ ۲۶ ثانیه و ۳۱۱ کیلوبایت؛ `anvil --init` آن را پذیرفت؛ `getValidators()` ولیدیتور اول را برگرداند؛ `anvil_setCoinbase` + `anvil_mine` فیلد `miner` بلاک را کنترل می‌کند؛ `evm_increaseTime` زمان ۷ روز را می‌پرد (برای دورهٔ آزمایشی)؛ ولی `admin_peers` و `qbft_*` در anvil **نیستند**. هر فایل آزمون با `evm_snapshot`/`evm_revert` ایزوله می‌شود. نبودِ anvil یا GenesisBuilder ⇒ آزمون‌های این لایه با پیام «skipped» رد می‌شوند (مثل e2e GenesisBuilder)، نه شکست بی‌صدا. جایگزین ردشده: کپی روش `contracts-tests/test/helpers.js` (Hardhat) چون زنجیرهٔ ابزار دوم و کد تکراری می‌آورد.
3. **Besu زنده (اختیاری، پیش از راه‌اندازی):** اسکریپت‌های سناریو با `hyperledger/besu:26.9.0` چندنودی QBFT حالت قرارداد؛ منابع Docker با پیشوند `sur25v-` و حذف پایان‌کار؛ موارد: قالب واقعی `admin_peers`، `qbft_getSignerMetrics`، ترتیب پیشنهاددهنده برای `expected_turns`، BG-03 دوباره روی مسیر دومرحله‌ای، فعال‌سازی «phantom».

**ABI:** از کامپایل قراردادهای همگام‌شده تولید می‌شود (`abi:gen`) و آزمونی شکست می‌خورد اگر ABI کامیت‌شده با کامپایل فرق کند؛ هر تغییر قرارداد را کامپایل برنامه می‌گیرد (فهرست جامع ۸.۴).

| بخش | در آزمون |
|---|---|
| قراردادها، EVM، رویدادها، `eth_call` و ریورت‌ها | **واقعی** (بایت‌کد GenesisBuilder روی anvil) |
| viem، SQLite، API HTTP، JSON متعارف، outbox و ریست وسط کار، شبیه‌سازی اول | **واقعی** |
| زمان | ساعت قابل‌تزریق + `evm_increaseTime` |
| `admin_peers`، `admin_nodeInfo`، `qbft_*` | **ساختگی** (`MockMonitorRpc` مثل `MockRpcServer` در RewardRouter) تا Besu زنده؛ قالب پاسخ در لایهٔ ۳ راستی‌آزمایی می‌شود |
| IP-geolocation | **ساختگی** (`FakeGeoIpProvider`) پشت `GeoIpProvider` |
| ارائه‌دهندگان OTP/SMS/تلگرام/بله/ایمیل | **ساختگی** (`MockOtpDeliveryProvider`؛ فقط اگر `M-OTP`) |
| سرویس دسترسی کلید | **ساختگی** (HMAC محلی با کلید آزمایشی) پشت `KeyAccessClient` |
| امضاکننده | کلید عمومی‌شدهٔ anvil (هرگز کلید واقعی)؛ `TxSigner` واقعی بسته به VD-11 جدا آزموده می‌شود |
| نگهدارنده‌های شواهد | دو پوشهٔ محلی پشت رابط `CustodianSink` |
| پروتکل `SUR_NODE_CHECK_V1` | **ساختگی** تا نوشته شود (`NodeCheckClient`: پیاده‌سازی حضور در `admin_peers` + ساختگی چالش) |

**آزمون‌های منفی الزامی:** هیچ تراکنشی برای `UNKNOWN`؛ هیچ `recordActivation` بدون نود زنده یا بدون `personKey`؛ هیچ `confirmOperatorReady` با نتیجهٔ ناموفق/نامشخص؛ شکست بسته با Identity Service قطع؛ ارسال متوقف با `verifier()` عوض‌شده؛ سناریوهای ۱ تا ۹ بازپخش `sur-reward-router-spec.md` بخش ۱۰.۵ به‌علاوهٔ پایهٔ بلاک ۰؛ تکرار تراکنش پس از ریست.

### ۱۰.۷ ترتیب پیشنهادی ساخت

| فاز | ماژول‌ها | چرا این‌جا |
|---|---|---|
| ۱ پایه | M0، M2، M1 | ABI و state و بازپخش رویداد؛ بقیه به این‌ها تکیه دارند و F-4 بالاترین خطر داده را دارد |
| ۲ مشاهده | M3، M4 | بدون هیچ تراکنش؛ حالت `OBSERVE_ONLY` برای سنجش قاعده‌ها روی داده‌ی واقعی/بازپخش |
| ۳ تصمیم | M5، M6، M7 | شواهد و امضا و سپس ورود (مسدودکنندهٔ ورود غیرمؤسس و فعال‌سازی مؤسسان) |
| ۴ هویت و API | M10، M13 | پیوند `personKey`، API اپ؛ ورود غیرمؤسس کامل می‌شود |
| ۵ اجرا | M8، M9، M12 | ریسک‌دارترین تصمیم‌ها (تعلیق، جریمه، تعویض اپراتور، حذف) آخر و پس از آزمون مشاهده؛ M9 به VD-8 و M12 به ابزار بازیابی وابسته است |
| ۶ عملیات | M11، M14، M15، M16 | هیأت، هشدار، Docker، سناریوهای Besu |

**قواعد کار (فهرست جامع ۸.۴):** سازنده و بازبین یک مدل نباشند؛ بازبینی مستقل پیش از هر فعال‌سازی `ENABLE_*`؛ حسابرسی امنیتی جدا؛ هیچ کلید یا کد ملی واقعی به مدل داده نشود. نسخهٔ اول تک‌نمونه با امضاکنندهٔ درون‌فرایند؛ HA چندنمونه و امضاکنندهٔ راه‌دور بعد از آن (VD-11). 🔶 lint: سرویس‌های همجوار eslint ندارند؛ برای Verifier افزودن `typescript-eslint` با `no-floating-promises` پیشنهاد می‌شود.

### ۱۰.۸ معیار «انجام‌شده» و پیش‌نیازهای بیرونی

برای هر فاز: `tsc --noEmit`، آزمون واحد و یکپارچه روی anvil سبز، آزمون‌های منفی بالا، و گزارش اینکه چه چیزی روی Besu اجرا **نشده**. موانع شروع **کد**: هیچ؛ موانع **راه‌اندازی تولید**: VD-1 تا VD-3، VD-8، VD-11 و اعداد `c01-rules-v1`؛ پیش‌نیازهای بیرونی: Identity Service (مسیر `person-bindings` و بله/ایمیل)، سرویس همراه نود و مسیر ثبت کلید پایش (فقط برای M9)، ابزار بازیابی (فقط برای M12)، نگهدارنده‌های شواهد.

### ۱۰.۹ حدود هم‌ترازی (چه چیزی بررسی شد)

بندبه‌بند با کد خوانده شد: `ValidatorsRegistry` (همهٔ توابع `onlyVerifier`، `requestMembership`، `selfSuspend`/`requestResume`، `onSeatTransferred`، حذف در بازیابی، ثابت‌ها)، `ValidatorsBoard` (`refreshBoard`، `syncBoard`، `fillVacancies`، `_canAct`، رأی حذف در بازیابی، چرخش `verifier`)، `IdentityRegistry`، `ValidatorSeatNFT`، `ValidatorLottery` (ورود برنده). اجرا یا آزمایش سرویس انجام نشد. جدول ناهمخوانی‌ها در ۱۰.۱۰ است.

### ۱۰.۱۰ ثبت ناهمخوانی‌ها و اقدام

| # | ادعای مشخصات | واقعیت قرارداد یا ابزار | اقدام |
|---|---|---|---|
| ۱ | `decision_id` سرویس = مقدار برگشتی تابع | مقدار برگشتیِ تراکنش در دسترس نیست؛ `decisionId` در لاگ `StatusDecisionRecorded` است؛ `confirmOperatorReady` و `recordRecoveryRemoval` شناسه ندارند | اصلاح (۳.۱.۱، ۵) |
| ۲ | `status_decisions` برای مؤسس و انتقال صندلی هم «تصمیم on-chain» است | برای انتقال صندلی تراکنشی نیست؛ مؤسس همان `recordActivation`؛ `recordPreExitViolation` نوع `Suspension` ثبت می‌کند؛ `recordRecoveryRemoval` نوع جدا | اصلاح (انواع ۹گانه) |
| ۳ | تابع‌های بدون‌مجوز: چهار تا؛ «هر هفت تابع `require` دارد» | پنج تابع به‌علاوهٔ `expireRecoveryRemoval`؛ هفت تابع `onlyVerifier` | اصلاح |
| ۴ | شرط `recordPreExitViolation`: فقط ۷۲ ساعت و `violationAt` پیش از درخواست | همچنین `violationAt > demotedAt`، `pendingSlashEpoch == 0`، `statusBeforeExit == Active`؛ مبدأ زمان `periodStartedAt` | اضافه (۳.۱.۱) |
| ۵ | `recordSuspension` بدون سقف | آخرین ولیدیتور فعال (`MIN_ACTIVE_VALIDATORS = 1`) تعلیق نمی‌شود | اضافه |
| ۶ | `syncBoard` پس از خروج عضو هیأت | کرسی با `membershipEpoch` (خروج، فروش صندلی، حذف در بازیابی) یا وضعیت `None/Exiting/RemovedInRecovery` می‌افتد؛ تعلیق نه؛ پس از ماه جدید همه‌چیز تا `refreshBoard` ریورت می‌شود | اصلاح (گام ۱۰) |
| ۷ | بازپخش رویداد از genesis کافی است (F-4) | ولیدیتور اول و صندلی‌های ۱ تا ۷ در genesis بی‌رویداد نوشته می‌شوند | پایهٔ بلاک ۰ (۲.۵)؛ هشدار برای Router |
| ۸ | ممنوعیت بازگشت «برای همیشه» (حذف در بازیابی) | `RecoveryRemovalCancelled` ممنوعیت را برمی‌دارد؛ فروشندهٔ صندلی هم `permanentlyExited` می‌شود | اصلاح (۵.۱، ۶.۹.۱) |
| ۹ | پیامد جغرافیایی برای `Active` از مسیر غیرفعالی | `c01-rules-v1` قاعدهٔ ۴: بلاک‌زن = `OK`؛ پیامدی نیست | 🔶 VD-3؛ پیش‌فرض فقط هشدار |
| ۱۰ | مؤسس = `isFounder(owner)` | پرچم با صندلی به خریدار می‌رود | فهرست genesis؛ 🔶 VD-6 |
| ۱۱ | برنده لاتاری: «مدت بررسی تعیین نشده» | قرارداد `Probation` و `probationPeriod` را اعمال می‌کند؛ اپراتور ندارد؛ `isFullyVerified` را هنگام ورود نمی‌سنجد | اصلاح (۶.۸) |
| ۱۲ | ستون `exited_at` مبنای ممنوعیت | ممنوعیت از `requestExit` است | ستون `exit_requested_at` |
| ۱۳ | نسبت ۹۵٪ و «پوشش ۵۰٪» | پوشش و رفتار `UNKNOWN` تعریف نشده بود؛ قرارداد `periodStartedAt` را با تعویض اپراتور بازنشانی نمی‌کند | تعریف (۶.۷-ث؛ اعداد 🔶) |
| ۱۴ | OTP و `setXVerified` در Verifier؛ «یا یک فرایند با دو کلید» | تناقض با فهرست جامع ۷٫۴؛ Identity Service OTP تلفن و تلگرام را دارد | 🔶 VD-1؛ پیش‌فرض Identity Service |
| ۱۵ | `personKey` از eKYC Identity Service و کلید HMAC فقط در Verifier | Identity Service کد ملی را دارد و کلید را ندارد؛ پیوند آدرس↔`personKey` مسیری نداشت | 🔶 VD-2؛ مسیر داخلی پیشنهادی |
| ۱۶ | استثنای `migrateIdentity` برای گم‌شدن کلید مالک | (تاریخی، ۲۰۲۶-۱۱-۲۰: قرارداد مسیر انتقال صندلی از آدرس گم‌شده نداشت؛ **منسوخ ۲۰۲۶-۱۱-۲۳**: اکنون `migrateSeat` وجود دارد) | ✅ مسیر قراردادی؛ 🔶 VD-2 فقط برای خط لولهٔ `personKey` و گام آف‌چین Verifier |
| ۱۷ | ورود: Verifier «تأیید ورود نمی‌دهد» | ورود (`requestMembership`، لاتاری، خرید NFT) بدون تأیید Verifier انجام می‌شود؛ خودداری فقط `recordActivation` را می‌گیرد؛ وثیقه قفل می‌ماند (اسلات هفتگی از ۲۰۲۶-۱۱-۲۳ در فعال‌سازی مصرف می‌شود، پس مصرف نمی‌شود)؛ علیه خریدار صندلی `Active` هیچ ابزاری نیست | 🔶 VD-5 |
| ۱۸ | همهٔ ورودهای مجموعه با Verifier است | `RecoveryRemovalCancelled` ولیدیتور را بدون تأیید `Active` می‌کند | 🔶 VD-4؛ هشدار فوری |
| ۱۹ | امضای تراکنش با Vault Transit | Transit از secp256k1 پشتیبانی نمی‌کند (HMAC بله) | 🔶 VD-11 [اصلاح ۲۰۲۶-۱۱-۲۱: کلیدهای سرویس اکنون در سرور مدیریت کلید SurKMS نگه‌داری می‌شوند؛ ← offchain-services/sur-kms-spec.md؛ کلید HMAC هم همان‌جا، پس Transit حتی برای HMAC لازم نیست] |
| ۲۰ | static peer به همهٔ ولیدیتورها با `nodeID` | `admin_addPeer` به enode کامل (IP) نیاز دارد | 🔶 VD-8 |
| ۲۱ | نگهدارندگان شواهد «در ۸.۳» | ۸.۳ چیزی دربارهٔ آن‌ها ندارد | ارجاع به ۱۰.۳؛ 🔶 VD-9 |
| ۲۲ | compose: `latest` و دو poller روی یک SQLite | بی‌ثبات و ناسازگار با SQLite | اصلاح (۸.۳) |
| ۲۳ | گام ۸ دوبار شماره خورده | — | `8-ب` |
| ۲۴ | `SelfSuspended` به‌عنوان نام رویداد | نام رویداد در کد `SelfSuspendedEvent` است | اصلاح (۲.۵) |
| ۲۵ | `recordActivation` رویداد/هش | هش تهی در `recordActivation` رد نمی‌شود (برخلاف `confirmOperatorReady`/`recordRecoveryRemoval`) | سرویس همیشه غیرتهی می‌فرستد |
| ۲۶ | `recordRecoveryRemoval`: «پروندهٔ باز دیگری نباشد» | شرط پروندهٔ حذف قبلی است، نه پروندهٔ جریمه | اصلاح (۶.۹.۱) |

**تأییدشده بدون تغییر:** نام و امضای `recordActivation`/`recordSuspension`/`recordRecovery`/`recordResume`/`recordPreExitViolation`/`confirmOperatorReady`/`recordRecoveryRemoval`؛ `getValidatorInfo` با ۶ خروجی؛ `getValidators`/`getActiveOwners`/`operatorOf`/`ownerOfOperator`؛ ثابت‌های ۷۲ ساعت، ۷ روز، ۹۰ روز، ۳۰ روز؛ ترتیب شش بولی `getVerificationStatus`؛ تصمیم ۱۱۰ (دو مرحله، انقضای ۷ روز، هش غیرتهی)؛ سوزاندن ۱۰۰٪ جریمه؛ «بررسی سلامت پیش از `recordActivation`»؛ `setVerifier` فقط با هیأت.

### ۱۰.۱۱ تصمیم‌های مالک (🔶 VD-n)

| # | سؤال | پیشنهاد سازنده (پیش‌فرض ساخت) |
|---|---|---|
| VD-1 | OTP و `setPhone/Telegram/Bale/EmailVerified` کجا ساخته شود: Identity Service (حالت ب) یا فرایند جدای پروژهٔ Verifier با کلید `identityOracle` (حالت الف)؟ | ب (کد OTP تلفن/تلگرام موجود است؛ بله و ایمیل افزوده شود). Verifier فقط `verifier` دارد |
| VD-2 | خط لولهٔ `personKey`: چه کسی HMAC را از KAS می‌گیرد و Verifier آن را چگونه می‌گیرد؟ مسیر گم‌شدن کلید مالک (انتقال صندلی) چیست؟ | Identity Service از KAS می‌گیرد و `(owner, personKey)` را از مسیر داخلی احرازشده می‌دهد؛ Verifier کد ملی نمی‌بیند. ✅ (۲۰۲۶-۱۱-۲۳) برای گم‌شدن کلید مالک مسیر قراردادی وجود دارد: `migrateIdentity` (اوراکل هویت) و سپس `migrateSeat` (Verifier)؛ 🔶 آنچه باز است، گام سرویس است: Identity Service پس از `migrateIdentity` به Verifier گزارش دهد و Verifier `migrateSeat` را بزند |
| VD-3 | پیامد نقض جغرافیایی برای `Active`: فقط هشدار، قاعدهٔ `NON_IRAN_CONFIRMED` با جریمهٔ ۱٪، یا تابع قراردادی؟ | فقط هشدار تا تصمیم؛ برای `Probation`/`Demoted` مانع فعال‌سازی است |
| VD-4 | لغو حذف در بازیابی ولیدیتور را بدون تأیید Verifier `Active` می‌کند: تغییر قرارداد (بازگشت به `SelfSuspended` و `recordResume`) یا فقط عملیات؟ | تغییر قرارداد؛ تا آن موقع هشدار فوری و بررسی نود |
| VD-5 | علیه خریدار صندلی `Active` ناقض یکتایی یا متقاضی ردشده (وثیقه قفل؛ اسلات پنجرهٔ ورود از ۲۰۲۶-۱۱-۲۳ مصرف نمی‌شود) چه پیامد/چاره‌ای؟ | هشدار به هیأت/بنیاد؛ متقاضی با `requestExit` خارج شود؛ بررسی چاره قراردادی |
| VD-6 | خریدار صندلی مؤسس `isFounder` می‌گیرد و فعال‌سازی بدون یک هفته انتظار دارد؛ مؤسس‌بودن از فهرست genesis تعیین شود و خریدار مشمول `personKey` و آزمون عادی باشد؟ | بله (فهرست genesis) |
| VD-7 | اعداد: `c01-rules-v1` (۶.۷)، نسبت/پوشش/پنجرهٔ پس از تعویض اپراتور (۶.۷-ث)، آستانهٔ همگامی و SLA تأیید `confirmOperatorReady`، سقف تعلیق لغزان | مقادیر [ ] پیشنهادی؛ تأیید پیش از `ENABLE_*` |
| VD-8 | پیش‌نیاز M9: پروتکل `SUR_NODE_CHECK_V1`، مسیر ثبت کلید پایش، آزمون commit seal؛ و روش دسترسی نود پایش به کاندیدا (کشف شبکه یا enode کامل). تا آن موقع آیا بررسی تنزل‌یافته (حضور در `admin_peers` و هش سر peer) برای `confirmOperatorReady` پذیرفته است؟ | تنزل‌یافته پذیرفته نشود برای `Active`؛ M9 پس از پروتکل |
| VD-9 | هویت دو نگهدارندهٔ مستقل شواهد، کلیدهای رمزگذاری و مراسم کلید | دو نهاد مستقل از اپراتور؛ رمزگذاری چندگیرنده |
| VD-10 | بانک IP-geolocation و دورهٔ به‌روزرسانی (سؤال ۳) | GeoLite2 آفلاین سنجاق‌شده، تا انتخاب |
| VD-11 | نگه‌داری کلید `verifier` (Transit secp256k1 ندارد: KMS/HSM، افزونه، یا KV)؛ HA و امضاکنندهٔ راه‌دور؛ آیا فراخوان‌های بدون‌مجوز با آدرس بی‌اختیار جدا بروند؟ | ✅ نسخهٔ اول تک‌نمونه؛ کلید در سرور مدیریت کلید SurKMS (secp256k1)؛ همان کلید `verifier` برای فراخوان‌های بدون‌مجوز هم (تصمیم مالک ۲۰۲۶-۱۱-۲۱؛ `sur-kms-spec.md` بخش ۸.۲) |
| VD-12 | رویهٔ چرخش و نشت کلید `verifier` (تا ۳ رأی هیأت کلید قدیمی معتبر می‌ماند) و SLA هیأت | کلید توقف اضطراری در سرویس؛ SLA با هیأت |
