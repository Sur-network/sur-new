# دستور جامع آزمون اجرایی روی Besu — نسخه‌ی ۲ (۲۰۲۶-۰۹-۲۹)

> ## ⚠️ وضعیت: **هیچ‌چیز در این سند برای نسخه‌ی فعلی قراردادها آزموده نشده است.**
>
> یک آزمون واقعی روی Besu در ۲۷–۲۸ سپتامبر ۲۰۲۶ انجام شد، ولی روی نسخه‌ی **قدیمی‌تر** کد — پیش از این تصمیم‌ها: اصلاح باگ N01 (تداخل پرونده‌ی قدیمی/جدید)، تصمیم‌های نهایی P01 تا P06 (هیأت‌مدیره، Verifier، خروج، توزیع پاداش، سقف خزانه)، آستانه‌ی C01، سیاست بازیابی اضطراری N04، اصلاح باگ امنیتیِ «بازگشت اختیار هیأتِ کهنه»، بازطراحی کامل `refreshBoard()`، و تغییر مرز سقف پرداخت به `<=`. آن شبکه دیگر معتبر نیست و نباید ادامه داده شود — قراردادهای رویش genesis‌شده نسخه‌ی امروز کد را ندارند.
>
> **این سند یک آزمون کاملاً تازه است، از صفر.** هیچ فاز یا موردی «قبلاً انجام‌شده» نیست. جایی که از آزمون قبلی دانش عملیاتیِ ارزشمند درباره‌ی خودِ Besu (نه رفتار این قراردادها) باقی مانده، در پیوست ب آمده — با تأکید صریح که این‌ها فقط راهنمای فنی‌اند، نه نتیجه‌ی تست.

---

## خلاصه‌ی اجرایی

| | |
|---|---|
| هدف این دور | ساخت یک شبکه‌ی Besu/QBFT تازه با **کد فعلی** هر ۶ قرارداد genesis‌شونده، و آزمون کامل هر ۷ قرارداد پروژه |
| وضعیت قبل از این دور | صفر. هیچ قراردادی با نسخه‌ی فعلی روی Besu اجرا نشده |
| بزرگ‌ترین ریسک اگر عجله شود | استفاده‌ی ناخواسته از یک genesis/شبکه‌ی قدیمی که کد کهنه دارد — نتیجه‌ی هر آزمونی روی آن **بی‌اعتبار** است |
| قراردادهای genesis‌شونده | `ValidatorsRegistry`, `ValidatorsBoard`, `ValidatorsTreasury`, `BlockRewardDistributor`, `FoundationDAO`, `IdentityRegistry` |
| قراردادهای دیگر (دیپلوی عادی، نه genesis) | `SurenSale`, `ServiceStaking` (کتابخانه‌ی `SurAddresses` هم genesis نمی‌شود، فقط لینک می‌شود) |

---

# پیوست ب — دانش عملیاتی از آزمون قبلی (فقط راهنمای فنی Besu؛ نه نتیجه‌ی تست این نسخه)

این‌ها یافته‌های زیرساختیِ خودِ Besu بودند، مستقل از منطق قراردادها، و به‌احتمال زیاد هنوز صادق‌اند — ولی **حتماً خودت دوباره راستی‌آزمایی کن**، چون نسخه‌ی Besu یا محیط ممکن است فرق کرده باشد:

1. **`extraData` در حالت contract-validator:** طبق مستند رسمی Besu، در این حالت `extraData` باید شامل **۰ ولیدیتور** باشد (`RLP([vanity 32 بایت, 0 validators, no vote, round 0, 0 seals])`)؛ فهرست ولیدیتورها فقط در `alloc.storage` قرارداد می‌نشیند. `extraData` مبتنی‌بر فهرست را با `validatorcontractaddress` قاطی نکن.
2. **Hard-forkها اجباری‌اند:** بدون `homesteadBlock` تا `londonBlock` (همه صفر) + `zeroBaseFee: true` در `config`، نود هنگام فراخوان `getValidators()` با `Invalid opcode: 0x1c` کرش می‌کند.
3. **رفتار مشاهده‌شده (نه ادعای قطعی باگ Besu):** روی Besu ۲۶.۹.۰ نسخه‌ی ویندوز، `--bootnodes` (CLI و TOML) با enode URLهای دارای دونقطه خطای `Illegal char <:> at index 5` داد. راه‌حل: `static-nodes.json` به‌جای `--bootnodes`.
4. **نود پنجم/اضافه واقعی لازم است:** صرفِ فعال‌کردن یک EOA در Registry نودِ پیشنهاددهنده نمی‌سازد. برای هر ولیدیتور تازه، یک نود Besu واقعی با **همان کلید خصوصی** آن آدرس لازم است؛ وگرنه شبکه هر نوبت را با round-change (~۱۳ ثانیه) رد می‌کند.
5. **روش استخراج genesis:** دیپلوی واقعی هر قرارداد روی یک زنجیره‌ی موقت (که constructor واقعی/implicit را اجرا می‌کند)، خواندن `code` با `eth_getCode` و هر storage slot لمس‌شده، به‌علاوه‌ی محاسبه‌ی تحلیلی slotهای mapping/آرایه برای هر seedِ اولیه (فرمول استاندارد `keccak256`)، با round-trip verification قبل از تزریق واقعی.
6. **متغیرهای `immutable` (مثل `BlockRewardDistributor.deployTime`):** solc محل این‌ها را در `deployedBytecode` خام خالی می‌گذارد. راه درست: زنجیره‌ی موقت را با `timestamp` بلاک برابر `genesisTimestamp` بساز و از **اجرای واقعی** آن `code` را بگیر (نه خواندن مستقیم `evm.deployedBytecode.object`).
7. **round-robin پیشنهاددهی** بین ولیدیتورهای عضو `getValidators()` تمیز کار می‌کند وقتی `qbft.validatorcontractaddress` درست تنظیم شده باشد.

هیچ‌کدام از این‌ها ادعا نمی‌کند رفتار **منطق تجاری** قراردادها (جریمه، حکمرانی، توزیع پاداش) درست است — آن فقط با آزمون‌های فازهای پایین اثبات می‌شود.

---

## پارامترهای آزمایشی — یک‌جا، بدون ابهام

مقادیر واقعی (سمت راست) خیلی طولانی‌اند برای آزمون wall-clock؛ مقادیر آزمایشی (سمت چپ، فقط در test-fork کد) را استفاده کن و **هر عددی که خودت هم کوچک می‌کنی را در گزارش اضافه کن**.

| پارامتر | مقدار واقعی | مقدار آزمون پیشنهادی |
|---|---:|---:|
| `probationPeriod` | ۱ هفته | ۳۰۰ ث |
| `recoveryPeriod` | ۴۸ ساعت | ۱۲۰ ث |
| `exitCooldown` | ۱ هفته | ۱۲۰ ث (باید > `PRE_EXIT_CLAIM_WINDOW` آزمون بماند) |
| `MASS_DEMOTION_WINDOW` | ۱ ساعت | ۶۰ ث |
| `APPEAL_FILING_WINDOW` | ۷۲ ساعت | ۱۲۰ ث |
| `APPEAL_VOTING_PERIOD` | ۷ روز | ۱۸۰ ث |
| `DELIVERY_DISPUTE_GRACE_PERIOD` | ۷ روز | ۱۲۰ ث |
| `DELIVERY_DISPUTE_VOTING_PERIOD` | ۷ روز | ۱۸۰ ث |
| `PRE_EXIT_CLAIM_WINDOW` (ثابت، P04) | ۷۲ ساعت | ۶۰ ث (باید < `exitCooldown` آزمون بماند) |
| `BOARD_REFRESH_INTERVAL` (ثابت، P01) | ۳۰ روز | ۱۸۰ ث |
| `BOARD_ACTION_EXPIRY` (ثابت) | ۱۴ روز | خودت تصمیم بگیر و بنویس (باید > `BOARD_REFRESH_INTERVAL` آزمون بماند تا اکشن قبل از بازتعیین منقضی نشود) |
| `STALE_VOTE_CLEAR_DELAY` | ۳۰ روز | ۶۰ ث |
| `CAP_CHANGE_TIMELOCK_DELAY` (ثابت، P06) | ۷ روز | ۶۰ ث |
| `ROLLING_WINDOW_DAYS`/سطل‌بندی روزانه‌ی `periodCap` | ۳۰ × ۱ روز | ۳۰ × ۱ دقیقه (`1 days`→`1 minutes` فقط در test-fork) |
| `perPaymentCap` / `periodCap` (✅ تصمیم نهایی P06) | ۵۰٬۰۰۰ / ۲۰۰٬۰۰۰ سورن | همان مقدار واقعی — کوچک‌کردن لازم نیست؛ overlay اجباری در genesis |
| بررسی ساعتیِ Verifier و آستانه‌های C01 | ساعتی؛ ۱۵د/۱س/۴س | **پارامتر سرویس آف‌چین است، نه قرارداد** — چون Verifier نوشته نشده، در این سند آزموده نمی‌شود |

---

## دستور ساخت شبکه‌ی تازه، از صفر، با کد فعلی

۱. **شمار و نقش فایل‌ها:** ۱۳ فایل Solidity هر زبان (`contracts/` و `contracts-fa/`). فقط ۶ قرارداد genesis می‌شوند (بالا). `SurAddresses` کتابخانه است (لینک، نه genesis مستقل). `SurenSale`/`ServiceStaking` بعد از راه‌اندازی شبکه با تراکنش عادی دیپلوی می‌شوند. `SurZether` یک دپ مرجع است، به این آزمون ربطی ندارد.

۲. **helperهای `_GenesisSeed`:** سه‌گانه (`ValidatorsRegistry_GenesisSeed`, `ValidatorsBoard_GenesisSeed`, `FoundationDAO_GenesisSeed`) constructor بدون آرگومان دارند و آدرس‌های placeholder داخلشان hardcode است. یا یک test-fork از هرکدام بساز که فهرست‌های آزمونت (ولیدیتورها = آدرس نودهای واقعی‌ات، اعضای هیأت، اعضای بنیاد) را بگیرد، یا یک ابزار genesis کوچک بنویس. **فهرست ولیدیتورهای Registry باید دقیقاً با نودهایی که واقعاً روشن می‌کنی یکی باشد.**

۳. **استخراج وضعیت اولیه:** برای هر یک از ۶ قرارداد genesis‌شونده، `code` و تمام storage اولیه را از **اجرای واقعی creation code** روی یک زنجیره‌ی موقت بگیر (نه از خواندن مستقیم بایت‌کد کامپایل‌شده). برای `BlockRewardDistributor`، زنجیره‌ی موقت را با `timestamp` بلاک برابر `genesisTimestamp` نهایی بساز (به‌خاطر `deployTime immutable`). `windowStart` در `ValidatorsRegistry` و `lastBoardRefreshAt` در `ValidatorsBoard` (اگر هیأت را seed می‌کنی) را هم برابر `genesisTimestamp` بگذار — وگرنه اولین `refreshBoard()` فوراً مجاز می‌شود. **بعد از تزریق، از بلاک صفر assertion بزن** روی هر scalar غیرصفر، `deployTime`، اعضای هیأت/بنیاد، آدرس اوراکل‌ها، `perPaymentCap`، `periodCap`. برابری `eth_getCode` بین نودها کافی نیست؛ باید مقدار واقعی storage را بخوانی.

۴. **`extraData` و `config`:** طبق پیوست ب، بندهای ۱ و ۲.

۵. **اتصال نودها:** `static-nodes.json` (پیوست ب، بند ۳).

۶. **هر ولیدیتور تازه = یک نود واقعی** (پیوست ب، بند ۴).

۷. **پیش‌نیازهای سناریوهای هیأت/خزانه:**
   - هر رأی‌دهنده‌ی `voteFor` باید قبلاً `IdentityRegistry.registerIdentity()` زده باشد.
   - `ValidatorsTreasury` در genesis موجودی صفر دارد — قبل از هر پرداخت با یک انتقال ساده‌ی سورن تأمینش کن.
   - `perPaymentCap`/`periodCap` باید غیرصفر باشند (طبق بند ۳، overlay شده‌اند).
   - رأی پیشنهاددهنده‌ی یک اکشن هیأت خودکار شمرده می‌شود (`_createAction` داخلاً `_voteAction` می‌زند).
   - `verifier` پیش‌فرض یک آدرس تولیدی بدون کلید در دسترس توست — آن را در test-fork به یک آدرس تازه که کلیدش را داری overlay کن.
   - `distributionOracle` هم همین‌طور — برای فاز توزیع پاداش باید کلیدش را داشته باشی.

---

## چک‌لیست کامل — نقطه‌ی شروع (همه‌چیز ❌)

هیچ ردیفی در این جدول از قبل ✅ نیست. در پایان کار، هر ردیف باید یکی از این سه علامت را بگیرد: ✅ تست‌شده (با ارجاع تراکنش) / ❌ رد شد با دلیل فنی مشخص / 🔶 جزئی (با توضیح دقیق چه‌بخشی).

### `ValidatorsRegistry.sol`
`requestMembership`→`recordActivation` · `recordSuspension`+تطبیق نصاب · `resolveMassFailureCheck` (هر دو حالت: رخداد جمعی و غیر آن) · `recordRecovery` · `confirmDelivery` · `assertDeliveryDisputed`+`voteOnDelivery` · `resolveDeliveryDisputeIfExpired` · `fileAppeal`+`confirmSlash` (رأی موفق) · `resolveAppealIfExpired` (بدون نصاب) · `executeUncontestedSlash` · جریمه‌ی مالی واقعی روی عضو پرداخت‌کننده · `requestExit`→`withdrawStake` بدون پرونده · `recordPreExitViolation` (پنجره‌ی ۷۲ساعته، هر رد‌شدن) · `withdrawStake` با پرونده‌ی معلق (برداشت جزئی) · باگ N01 (پرونده‌ی بسته دوباره باز نمی‌شود؛ قفل پرونده‌ی جدید پاک نمی‌شود) · `proposeParameterChange`/`voteParameterChange` (هر ۶ `ParamKey`) · کف `RecoveryPeriod`/`ExitCooldown` · سقوط شبکه زیر نصاب BFT

### `ValidatorsBoard.sol`
`voteFor`/`unvoteFor` (رأی آزاد) · `refreshBoard` تشکیل اولیه · `refreshBoard` با صفر رأی (هیأت خالی نمی‌شود) · `refreshBoard` با رأی ناکافی برای پرکردن همه‌ی کرسی‌ها · `refreshBoard` با نامزد قوی‌تر (جایگزینی ضعیف‌ترین عضو) · `refreshBoard` با تساوی رأی (عضو فعلی می‌ماند) · `refreshBoard` با عضو `Demoted` در موعد ماهانه · `refreshBoard` با/بدون تغییر واقعی (`boardVersion`) · ابطال اکشن باز با تغییر واقعی (`voteAction` باید revert شود) · **باگ اختیار هیأتِ کهنه — بازتولید و تأیید هر دو لایه‌ی اصلاح** · `proposeApproveBudget`+حداقل ۳ رأی · توقف خرج با <۳ عضو دارای اختیار · `proposeRotateOracle` · `proposeSetEntryThresholdBase`/`proposeSetGrowthFactorPerValidator`/`proposeSetMembershipFeeBps` · `proposeRotateVerifier` · `clearStaleVotes` · جانشینی فوری ناشی از خروج (`syncBoard`/`fillVacancies`، مسیر جدا از بازتعیین ماهانه) · نبود مسیر عزل اضطراری در ABI

### `ValidatorsTreasury.sol`
`boardApproveExpenditure` موفق · مرز دقیق `perPaymentCap` (کمتر/دقیقاً‌برابر[باید مجاز]/بیشتر[باید رد]) · مرز دقیق `periodCap` (دقیقاً‌برابر مجاز/یک‌واحد‌بیشتر رد) · `proposeCapChange`+رأی+`CAP_CHANGE_TIMELOCK_DELAY`+`applyPendingCapChange` · بدون تأخیر برای پرداخت عادی

### `BlockRewardDistributor.sol`
تأیید `qbft.miningbeneficiary` می‌رسد به این آدرس · **اولین اجرای واقعی `distributeRewards()`** (این همان تابعی است که باگ Stack-too-deep در آن پیدا و اصلاح شد — این اجرا تأیید نهایی همان اصلاح روی زنجیره‌ی واقعی هم هست) · کنترل بازه‌ی بلوک P05 (شروع دقیق، تکراری/هم‌پوشان/جاافتاده/وارونه/آینده رد شود) · کارمزد عضویت تاخورده و توزیع بدون سوزاندن · `MIN_DISTRIBUTION_INTERVAL`

### `FoundationDAO.sol`
مشکل bootstrap با صفر عضو (`proposeAddMember`/`vote` هر دو `onlyMember`) · `proposeAddMember`+دوسوم · `proposeRemoveMember`+دوسوم · `proposeSendETH`+اکثریت ساده · `proposeExecute` با `value!=0` باید رد شود · رد پیشنهاد منقضی‌شده

### `IdentityRegistry.sol`
`registerIdentity` · `setPhoneVerified`/`setTelegramVerified`/`setKycVerified` · `migrateIdentity` · `setIdentityOracle` (چرخش دست `FoundationDAO`)

### `ServiceStaking.sol`
`stake` · `requestWithdrawal` · `withdraw` بعد از دوره‌ی انتظار · `withdraw` قبل از پایان دوره (رد)

### بازیابی اضطراری (N04)
مرحله‌ی ۱ (احیای نودها) · مرحله‌ی ۲ (`transitions.qbft` به `blockheader`) · بازگشت به `contract` بدون پرونده‌ی تنبیهی · اثبات محدودشدن گذار فقط به انتخاب ولیدیتور

---

## فاز ۱ — کامپایل، genesis، راه‌اندازی شبکه

از «دستور ساخت شبکه‌ی تازه» بالا پیروی کن. حداقل ۴ نود واقعی (برای امکان فاز‌های بعدی که ولیدیتور تازه اضافه می‌کنند، نود پنجم را هم از الان آماده نگه‌دار). **گزارش بده:** فهرست دقیق ولیدیتورهای genesis، `code` هر ۶ قرارداد از هر نود (باید یکسان باشند)، و نتیجه‌ی assertionهای بند ۳ بالا (مقدار واقعی هر scalar مهم، نه فقط «درست بود»).

## فاز ۲ — چرخه‌ی کامل عضویت و اعتبارسنجی (`ValidatorsRegistry`)

با یک ولیدیتور تازه (نه از genesis): `requestMembership()` → صبر `probationPeriod` → `recordActivation()` (با کلید `verifier`) → تأیید کن `isValidator()`/`getValidators()` بلافاصله به‌روز شدند و اگر نود واقعی پشتش هست، وارد چرخش پیشنهاددهی QBFT شد.

## فاز ۳ — تعلیق، معافیت جمعی، اعتراض، تحویل، بازگشت، خروج

هرکدام از این‌ها را **جدا** (نه لزوماً همان ولیدیتور) آزمون کن، با گزارش دقیق state قبل/بعد هر مرحله:

1. **تعلیق تنها (بدون رخداد جمعی):** `recordSuspension` → `resolveMassFailureCheck` (نباید exempt شود) → `confirmDelivery` → بدون اعتراض تا پایان `APPEAL_FILING_WINDOW` → `executeUncontestedSlash`.
2. **رخداد جمعی واقعی:** ۲+ ولیدیتور را در همان پنجره‌ی `MASS_DEMOTION_WINDOW` تعلیق کن (باید >۲۰٪ مجموعه‌ی فعال باشد) → `resolveMassFailureCheck` برای هرکدام جدا → باید `ExemptMassFailure` بدهد.
3. **بازگشت کامل:** یک ولیدیتور معاف/جریمه‌شده صبر کند `recoveryPeriod`، `recordRecovery` بزن → `isValidator()` دوباره true.
4. **اعتراض با رأی موفق:** تعلیق تنها → `confirmDelivery` → `fileAppeal` → با اکثریت `confirmSlash` رأی بده تا نصاب برسد → `SlashResolved(Confirmed)`.
5. **اعتراض بدون نصاب:** مثل بالا ولی بدون رأی کافی، صبر کن `APPEAL_VOTING_PERIOD` تمام شود، `resolveAppealIfExpired` → `RejectedNoQuorum`؛ `isValidator()` باید همچنان `false` بماند (تعلیق لغو نمی‌شود، فقط جریمه رد می‌شود).
6. **اختلاف تحویل:** تعلیق کن، ولیدیتور خودش `confirmDelivery` نزند → صبر `DELIVERY_DISPUTE_GRACE_PERIOD` → یک حساب دیگر `assertDeliveryDisputed` بزند → اکثریت `voteOnDelivery(true)` رأی بدهند → `deliveryConfirmed=true`.
7. **جریمه‌ی مالی واقعی:** یک ولیدیتور **دارای وثیقه** (`requestMembership` واقعی، نه از genesis) را جریمه کن — موجودی خزانه‌ی قبل/بعد را با عدد دقیق مقایسه کن (باید دقیقاً `slashBps` از `lockedStake` باشد).
8. **خروج بدون پرونده:** `requestExit` → صبر `exitCooldown` → `withdrawStake` → کل وثیقه برگردد، `status=None`.
9. **پرونده‌ی پیش‌ازخروج (P04):** ولیدیتور `Active` خروج بدهد → Verifier ظرف `PRE_EXIT_CLAIM_WINDOW` `recordPreExitViolation` بزند (با `violationAt` قبل از زمان خروج) → `resolveMassFailureCheck` → `confirmDelivery` → بعد از `exitCooldown` و **قبل از** اجرای جریمه، `withdrawStake`: فقط مبلغ درگیر محفوظ بماند و بقیه پرداخت شود → `executeUncontestedSlash` → مبلغ محفوظ دقیقاً به خزانه برود → برداشت دوم صفر بدهد. همچنین رد‌شدن‌ها: `violationAt` بعد از خروج (رد)، بعد از پایان پنجره (رد)، خروج‌نکرده (رد)، Probation (رد)، پرونده‌ی دوم هم‌زمان (رد)، غیر Verifier (رد).
10. **باگ N01 (رگرسیون امنیتی):** با یک عضو دارای وثیقه: رخداد جمعی → معافیت پرونده‌ی A → `recordRecovery` → بعد از `DELIVERY_DISPUTE_GRACE_PERIOD` تلاش `assertDeliveryDisputed(A)` — **باید revert شود** با `"case already resolved"` → همان ولیدیتور دوباره تنها تعلیق شود (پرونده‌ی B) → `pendingSlashEpoch` باید غیرصفر بماند → `requestExit`+`withdrawStake` پیش از حل B باید revert شود.
11. **تغییر پارامتر:** `proposeParameterChange` برای هر ۶ `ParamKey` (`MaxEntriesPerWindow`=۰, `EntryWindowSeconds`=۱, `ProbationPeriod`=۲, `RecoveryPeriod`=۳, `SlashBps`=۴, `ExitCooldown`=۵) با اکثریت رأی بده. **گزارش بده:** کف `RecoveryPeriod` (باید > `MASS_DEMOTION_WINDOW`) و کف `ExitCooldown` (باید > `PRE_EXIT_CLAIM_WINDOW`) هم رد می‌شوند.
12. **سقوط زیر نصاب BFT:** با `recordSuspension` پی‌درپی، مجموعه‌ی ثبت‌شده را کم‌کم کوچک کن و بعد از هر مرحله تولید بلاک را بسنج. حداقل اندازه‌ی مجموعه‌ای که هنوز بلاک می‌سازد چیست؟ جدا از این، چند نود را (بدون کم‌کردن مجموعه‌ی ثبت‌شده) خاموش کن تا بیش از یک‌سوم مشارکت‌کنندگان از دست برود — بلاک‌سازی متوقف می‌شود؟ این دو آزمون را با هم قاطی نکن (یکی «کوچک‌شدن مجموعه»، دیگری «آفلاین‌شدن نود در مجموعه‌ی ثابت»).

## فاز ۴ — `ValidatorsBoard`

هیأت را با رأی‌گیری واقعی (بعد از `registerIdentity` برای هر رأی‌دهنده) تشکیل بده، سپس هرکدام از این‌ها را جدا آزمون کن:

1. **صفر رأی معتبر:** همه‌ی رأی‌ها را `unvoteFor` کن، صبر `BOARD_REFRESH_INTERVAL`، `refreshBoard()` بزن. اعضای `Active` فعلی باید کرسی‌شان را حفظ کنند؛ `boardVersion` نباید تغییر کند.
2. **رأی ناکافی برای پرکردن همه‌ی کرسی‌ها:** یک عضو خروج بدهد، فقط یک کاندیدای تازه رأی داشته باشد. فقط همان یک نفر وارد شود؛ کرسی‌های بدون کاندیدای واجد خالی بمانند.
3. **نامزد قوی‌تر:** با هیأت پر، رأی یک عضو را صفر کن و به یک کاندیدای بیرونی حداقل ۱ رأی بده. نامزد تازه باید جای عضو ضعیف را بگیرد؛ `boardVersion` بالا برود.
4. **تساوی رأی:** مثل بالا ولی کاندیدای بیرونی هم صفر رأی. عضو فعلی باید بماند؛ `boardVersion` بدون تغییر.
5. **تعلیق در موعد ماهانه:** عضوی را `recordSuspension` کن. بلافاصله باید هنوز `hasBoardAuthority`=true باشد. بعد از `BOARD_REFRESH_INTERVAL` و `refreshBoard()`، دیگر عضو نباشد.
6. **ابطال اکشن باز:** قبل از یکی از سناریوهای بالا که ترکیب را واقعاً عوض می‌کند، یک `proposeApproveBudget` باز با رأی ناقص بگذار. بعد از تغییر واقعی، رأی باقی‌مانده باید با `"board membership changed since this action was proposed"` **revert** شود (نه موفقیت بی‌اثر).
7. **باگ اختیار هیأتِ کهنه (آزمون امنیتی):** یک عضو هیأت `requestExit` بزند → بعد از `exitCooldown`، `withdrawStake()` بزند → همان آدرس دوباره `requestMembership()` بزند — باید با `"this address has exited before and may not rejoin"` رد شود (لایه‌ی اول). اگر Besu اجازه‌ی دستکاری مستقیم storage (`debug_setStorageAt`) را روی یک شبکه‌ی آزمایشیِ **جدا** می‌دهد، لایه‌ی دوم را هم جدا آزمون کن: `permanentlyExited` را دستی `false` کن، `requestMembership` این‌بار موفق شود، ولی `hasBoardAuthority` همچنان `false` بماند (چون `membershipEpoch` عوض شده و با `seatMembershipEpoch` کرسی کهنه هم‌خوان نیست). اگر Besu این را اجازه نمی‌دهد، فقط لایه‌ی اول را با دلیل مشخص گزارش بده.
8. **توقف خرج:** هیأت را به کمتر از ۳ عضو دارای اختیار برسان (بدون جانشین واجد). `proposeApproveBudget` باید با `"fewer than 3 board members - spending halted"` رد شود.
9. **بقیه‌ی اکشن‌ها:** `proposeRotateOracle`، `proposeSetEntryThresholdBase`/`proposeSetGrowthFactorPerValidator`/`proposeSetMembershipFeeBps`، `proposeRotateVerifier` — هرکدام با نصاب معمولی رأی و نتیجه‌ی on-chain متناظرش تأیید شود.
10. **`clearStaleVotes`:** یک ولیدیتورِ رأی‌داده را برای مدت طولانی `Demoted` نگه‌دار (`recoveryPeriod` + `STALE_VOTE_CLEAR_DELAY`، در test-fork کوچک‌شده)، سپس `clearStaleVotes` بزن.
11. **جانشینی فوری (مسیر جدا از بازتعیین ماهانه):** عضوی خروج بدهد → اختیارش فوراً قطع شود → `syncBoard()` (تراکنش جدا) کرسی را آزاد و جانشین کند، بدون انتظار `BOARD_REFRESH_INTERVAL`.
12. **بدون مسیر عزل اضطراری:** ABI روی زنجیره را بخوان — نباید تابعی با نام remove/emergency/kick/dismiss باشد.

## فاز ۵ — `ValidatorsTreasury`

1. **مرز `perPaymentCap` (`<=`):** پرداخت ۴۹٬۹۹۹ (اجرا شود)، دقیقاً ۵۰٬۰۰۰ (**باید اجرا شود** — اگر رد شد یعنی کد قدیمی deploy شده، فوراً متوقف کن و گزارش بده)، ۵۰٬۰۰۰+۱wei (رد شود).
2. **مرز `periodCap` (`<=`):** با چند پرداخت به دقیقاً ۲۰۰٬۰۰۰ برس (باید مجاز باشد)، سپس ۱ واحد بیشتر (باید رد شود با `"30-day period cap exceeded"`).
3. **تغییر سقف با رأی + timelock:** `proposeCapChange` → رأی اکثریت → تلاش فوری `applyPendingCapChange` (رد شود) → صبر `CAP_CHANGE_TIMELOCK_DELAY` → دوباره (موفق شود). تأیید کن پرداخت عادی هیچ تأخیری ندارد.

## فاز ۶ — `BlockRewardDistributor`

1. چک کن `qbft.miningbeneficiary` واقعاً به این آدرس بلاک‌ریوارد می‌رساند (موجودی قبل/بعد چند بلاک).
2. **اولین اجرای واقعی `distributeRewards()`:** با کلید `distributionOracle` (overlay‌شده)، `{fromBlock, toBlock}` را از بلاک ۱ شروع کن، فهرست ولیدیتورها و تعداد بلاک واقعی‌شان (از چرخش round-robینی که دیدی) را بده. **گزارش بده:** موفقیت تراکنش، `gasUsed`، موجودی هر ولیدیتور/`FoundationDAO`/`ValidatorsTreasury` قبل و بعد، رویداد نهایی.
3. **کنترل بازه‌ی P05:** بازه‌ی دوم را امتحان کن با شروع اشتباه (رد شود)، هم‌پوشان (رد شود)، جاافتاده (رد شود)، درست (قبول شود).
4. کارمزد عضویت تاخورده (`pendingMembershipFees`) در epoch بعدی بدون سوزاندن توزیع شود.
5. `MIN_DISTRIBUTION_INTERVAL` — فراخوان فوری دوم رد شود.

## فاز ۷ — `FoundationDAO`

genesis این قرارداد را با چند عضو seed‌شده بساز (چون با صفر عضو، `proposeAddMember`/`vote` هر دو `onlyMember` قفل می‌شوند — اگر امتحان کردی و واقعاً قفل بود، همین را به‌عنوان یافته گزارش بده). با ۲-۳ عضو: `proposeAddMember`+دوسوم، `proposeRemoveMember`+دوسوم، `proposeSendETH`+اکثریت ساده، `proposeExecute` با `value!=0` (باید رد شود — این تأیید نهایی یک اصلاح قدیمی‌تر است)، رأی روی پیشنهاد منقضی (رد شود).

## فاز ۸ — `IdentityRegistry`

`setPhoneVerified`/`setTelegramVerified`/`setKycVerified`، `migrateIdentity`، و چرخش `setIdentityOracle` از طریق `FoundationDAO` (اگر فاز ۷ را انجام دادی).

## فاز ۹ — `ServiceStaking`

`stake`، `requestWithdrawal`، `withdraw` بعد/قبل از دوره‌ی انتظار (دوره را هم در test-fork کوچک کن و در گزارش بگو).

## فاز ۱۰ — بازیابی اضطراری اجماع (N04)

سیاست کامل: `governance/sur-emergency-consensus-recovery.md`. ⚠️ **ابزار برنامه‌ی بازیابی (شورای ۵ از ۷) هنوز نوشته نشده** — این فاز فقط لایه‌ی فنی Besu را می‌آزماید، نه رویه‌ی امضا.

1. **احیای مجموعه‌ی موجود:** چند نود را خاموش کن تا بیش از یک‌سوم مشارکت‌کنندگان بروند → بلاک‌سازی متوقف شود → همه را دوباره روشن کن → آیا بدون تغییر دیگری برمی‌گردد؟
2. **نودهای برگشت‌ناپذیر:** ۲ نود را برای همیشه از دست‌رفته فرض کن. به genesis نودهای زنده یک `transitions.qbft` با `validatorselectionmode: blockheader` در یک بلاک **آینده** اضافه کن. آیا زنجیره‌ی متوقف از آن بلاک بلاک می‌سازد؟
3. **بازگشت به `contract`:** ⚠️ **هیچ `recordSuspension` برای هماهنگ‌کردن نزن** (قطعی عمومی تخلف فردی نیست). فقط وقتی نصاب مشارکت‌کنندگان `Registry` برقرار است (`d ≤ ⌊(n−1)/3⌋`) گذار بازگشت را اضافه کن. تأیید کن state قراردادها (وثیقه‌ها، رأی‌ها، پرونده‌ها، `boardVersion`) قبل/بعد دست‌نخورده است، و `alloc`/`extraData`/بقیه‌ی `config` genesis بایت‌به‌بایت یکسان مانده جز `transitions.qbft`.

---

## بسته‌ی خروجی الزامی

### ۱. فایل‌ها
`REPORT.md` (به ترتیب فازهای ۱ تا ۱۰) + `logs/phase-N.md` جدا برای یافته‌های غنی‌تر + `genesis.json` نهایی + جدول «پارامترهای آزمایشیِ نهایی استفاده‌شده» (هر عددی که از جدول بالا فرق کرد یا اضافه شد).

### ۲. برای هر تراکنش (بدون استثنا)
| فیلد | الزامی |
|---|---|
| هش تراکنش | بله |
| `status` از `eth_getTransactionReceipt` | بله |
| `gasUsed` | بله |
| پیام revert کامل و کلمه‌به‌کلمه (اگر شکست خورد) | بله |
| مقدار state قبل و بعد (نه فقط «موفق شد») | بله |
| زمان دیوار لحظه‌ی ارسال | بله |

### ۳. جدول نهایی
همان چک‌لیست بالا، هر ردیف با ✅ (+ارجاع تراکنش) / ❌ (+دلیل فنی مشخص) / 🔶 (+توضیح دقیق بخش انجام‌شده).

### ۴. یافته‌های غیرمنتظره
هر باگ یا رفتار غیرمنتظره، با خطای خام، بدون حدس‌زدن علت. اگر رفتار `refreshBoard`، مرز `perPaymentCap`، یا هر بخش دیگری از این سند با قرارداد deploy‌شده یکی نبود، این را **یافته‌ی بحرانی** گزارش بده (یعنی کد اشتباه genesis شده)، نه صرفاً «انحراف».

### ۵. زمان صرف‌شده برای هر فاز

### ۶. انحرافات از این دستورالعمل
اگر جایی این سند اشتباه یا غیرممکن بود، با استدلال کامل مستند کن — حدس نزن که نوشته‌ی من حتماً درست‌ترین راه است.

## چیزی که در این دور نباید تلاش شود
پروتکل بررسی نود جدید (`SUR_NODE_CHECK_V1`، در `offchain-services/sur-node-check-protocol-spec.md`) هنوز پیاده‌سازی نشده — سرویس همراه نودی که به چالش پاسخ بدهد وجود ندارد. فاز ۲ (فعال‌سازی) با هر روشی که برایت عملی است (حتی صرفاً از طریق زمان و رأی Verifier شبیه‌سازی‌شده، بدون پروتکل چالش واقعی) پیش برو.
