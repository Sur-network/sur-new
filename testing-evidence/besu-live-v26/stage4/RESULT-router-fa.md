# مرحلهٔ ۴ (بخش Router، RM12) — RewardRouter روی Besu زنده

**اجرا:** ۲۰۲۶-۱۱-۲۲، شبکهٔ A (۹ نود، ۷ ولیدیتور، ثابت‌های تولیدی)، Besu 26.9.0؛ Router واقعی (`serve`/`run-once` از `Deployments/RewardRouter`)، امضا از **SurKMS مستقل** (کلید `distributionOracle` چرخیده‌شده، mTLS با گواهی سنجاق‌شده)؛ هیچ کلیدی در Router نیست.

## نتیجه‌ها

| # | آزمایش | نتیجه |
|---|---|---|
| R1 | **شکل `trace_block`**: ورودی reward با `author` = `miningbeneficiary` (Distributor)، `rewardType: "block"`، `value` = ۲ Suren (`0x1bc16d674ec80000`)، یک ورودی به‌ازای هر بلوک؛ Router آن را بی‌خطا می‌خواند | ✅ |
| R2 | **هویت موجودی هر بلوک** با پاداش و کارمزد واقعی: روی نود archive همهٔ ۱٬۴۵۹ بلوک و بعد ۲٬۱۲۱ بلوک کامل، `incompleteBlocks: 0` | ✅ |
| R3 | **نود BONSAI معمولی (بدون archive) در شروع سرد:** از ۱٬۳۷۹ بلوک، **۸۸۷ بلوک ناقص** (`NO_REWARD_ENTRY; BALANCE_UNAVAILABLE`) و `block-0 state unavailable: replay base taken from the genesis owners file` (`eth_call` به state قدیمی «Internal error»)؛ Router به‌درستی هیچ‌چیز نفرستاد (`DATA_UNAVAILABLE`) | ✅ رفتار ایمن؛ **الزام استقرار ↓** |
| R4 | همان پایگاه‌داده بعد از شروع روی archive، با نود BONSAI **افزایشی** ادامه داد: ۲۰۲ بلوک تازه، `incompleteBlocks: 0` | ✅ |
| R5 | **چرخهٔ کامل ارسال با SurKMS:** `openDistribution` (۳۸۵٬۶۷۵ گاز) ← ۷ صفحه (`ROUTER_PAGE_SIZE=1`، ۲۴۳٬۱۲۳ و ۶×۱۵۷٬۶۲۳) ← `closeDistribution` (۳۴۲٬۲۳۶)؛ هر ۹ گام با `check_status: ok` (تطبیق گام با لاگ‌های قرارداد، wei به wei)؛ ۲٬۱۲۰ بلوک؛ epoch ‏`confirmed` | ✅ |
| R6 | **کرش و ازسرگیری:** Router **و** SurKMS با kill سخت وسط توزیع کشته شدند (بعد از صفحهٔ ۲)؛ توزیع روی زنجیره باز ماند (۶۰۲ بلوک پرداخت‌شده)؛ مرحلهٔ بعد: `SIGNER_FAILED` (KMS پایین) و **هیچ‌چیز فرستاده نشد**؛ KMS بالا آمد و unlock شد؛ Router **بدون open دوم و بدون تکرار صفحه** از `lastPayee` ادامه داد و صفحه‌های ۳ تا ۷ و close را فرستاد (`events-after-resume.txt`) | ✅ |
| R7 | **زمین‌ماندهٔ lease:** پس از kill سخت، نمونهٔ تازه تا انقضای TTL lease شروع نمی‌شود (`fatal: another instance holds the lease`)؛ بعد از انقضا بالا آمد | ✅ (طراحی‌شده؛ زمان رفتن حدود ۲–۳ دقیقه) |
| R8 | **`eth_getLogs`:** بازهٔ بیش از ۵٬۰۰۰ بلوک روی Besu رد می‌شود با پیام عمومی `-32602 Invalid params` (نه پیام مخصوص بازه)؛ پیش‌فرض `ROUTER_LOG_CHUNK=2000` امن است و در Router چندین چرخه بدون خطا کار کرد | ✅ |
| R9 | **تراکنش جایگزین روی txpool واقعی (در سطح Besu):** دو تراکنش هم‌nonce پشت‌سرهم: با **همان قیمت گاز** جایگزین پذیرفته شد (پیام لاگ: «price bump forced to 0, zero-basefee network»)، با قیمت دوبرابر هم پذیرفته شد و همان ماین شد، با قیمت **کمتر** رد (`-32602`). | ✅ مشاهده (`besu-probes.json`) |
| R10 | `--rpc-max-logs-range` پیش‌فرض ۵٬۰۰۰ تأیید شد؛ گاز واقعی صفحه در مرحلهٔ ۲ آمده؛ `ABORT_DELAY` واقعی (۳ روز) دیده شد در `distribution status`: `abortPossibleAt = openedAt + 259200` | ✅ |

## الزام استقرار (ثبت‌شده به درخواست جلسهٔ هماهنگ‌کننده)
**Router به یک نود Besu با تاریخچهٔ کامل (archive) نیاز دارد:** نود پیش‌فرض (BONSAI با ≈۵۱۲ بلوک تاریخچه) برای هر بلوک قدیمی‌تر `trace_block` بدون ورودی reward و موجودی تاریخی `eth_getBalance` نمی‌دهد (در آزمون: ۶۴٪ بلوک‌ها ناقص)، و `eth_call` روی state بلوک ۰ هم شکست می‌خورد. دو راه:
۱. **توصیه:** نود Router با `--data-storage-format=FOREST` (در آزمون ما: نود `a1`؛ همهٔ بلوک‌ها از بلوک ۱ کامل) یا حالت archive دیگر Besu؛
۲. حداقل: Router همیشه روشن و عقب‌نماندن بیش از ≈۵۱۲ بلوک (حدود ۱۷ دقیقه در بلوک ۲ ثانیه؛ پیش‌فرض poll = ۶۰۰ ثانیه = ۳۰۰ بلوک، حاشیه فقط ≈۱٫۷ برابر) و پایگاه‌دادهٔ اولیه باید روی archive ساخته شود؛ با خاموشی بیش از ≈۱۷ دقیقه، بلوک‌های از دست‌رفته فقط با `blocks backfill` از `ROUTER_ARCHIVE_RPC_URL` پر می‌شوند.
توصیهٔ ما: **archive، نه حالت دوم.** این باید در README Router و runbook نوشته شود.
در این آزمون Verifier هم روی نود archive بلوک ۰ را خواند (`replay base: block-0-state`).

## آزموده‌نشده
- تراکنش جایگزین **توسط خود Router** (`ROUTER_MAX_REPLACEMENTS>0`، `REPLACE_AFTER_SEC`) روی txpool زنده: تراکنش روی شبکهٔ ۲ ثانیه‌ای ماین می‌شود پیش از آنکه معلق بماند و ما نود جدا/مسدود نساختیم؛ فقط رفتار خود Besu آزموده شد (R9).
- موارد RD-5/RD-16 (تولیدکنندهٔ بدون مالک / هرگز-فعال‌نشده): روی QBFT واقعی نمی‌توان بلوکی با چنین پیشنهاددهنده‌ای تولید کرد (پیشنهاددهنده همیشه از فهرست Registry است)؛ فقط روی anvil آزموده شده‌اند.
- دو نمونهٔ همزمان/HA، `certifyRateStart`، گیرندهٔ مؤجل از طریق Router (در مرحلهٔ ۲ مستقیم با قرارداد آزموده شد؛ ولی Router با مالک دارای کد روی Besu نه).
- هشدار وب‌هوک و ایمیل، نگه‌داری کلید، حسابرسی.
