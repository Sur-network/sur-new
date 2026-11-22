# آزمون زندهٔ رفع تکه‌کردن `eth_getLogs` روی Besu واقعی در ارتفاع بیش از ۵۰۰۰ بلوک (دور ۳، «v26-r3-getlogs»)

**تاریخ:** ۲۰۲۶-۱۱-۲۲ · **هدف:** اثبات این‌که رفع‌ها روی Besu واقعی بالای ۵۰۰۰ بلوک کار می‌کنند: ValidatorApp commit `09dba98` (`src/lib/events.ts`) و GovernanceDashboard commit `d7fee51` (`src/lib/gov/common.ts`، `recovery.ts`).
**محل اجرا: سرور** (`192.168.1.210`، Docker، `hyperledger/besu:26.9.0`، همان ایمیج دور ۱ و ۲، بدون pull)؛ فقط اشیای `sur25l-*`؛ RPC فقط روی `127.0.0.1` و با تونل SSH. کلیدها آزمایشی؛ سه کلید سرویس از SurKMS دور ۲ (همان آدرس‌ها در ژنسیس). **هیچ کدی تغییر نکرد؛ push انجام نشد.**

## شبکه
یک نود Besu (`sur25l-n1`: اولین ولیدیتور = مالک ۱ (owner1)، archive/FOREST)، QBFT، **بلوک ۱ ثانیه‌ای**، ژنسیس **واقعی و بدون هیچ تغییر آزمایشی** با ۱۲ قرارداد (ساخته‌شده با CLI فعلی GenesisBuilder؛ `genesis-config.json`، `genesis-build.log`)، زنجیرهٔ ۲۶۲۰۲۵. ابزار: `BesuLive/gen-netL.mjs`، `server-l/`، `sync-l.sh`، `ui-live/l/`. نخست ۱۵۶ بلوک: owner1 یک پیشنهاد `proposeKmsFreeze(1,true)` باز کرد (رأی ۱ از ۳؛ رویداد `ActionVoted`، اجرا نمی‌شود)؛ سپس **Router واقعی + SurKMS** یک توزیع کامل روی بلوک‌ها انجام داد (۳ گام: open، page، close؛ `0-router-distribution.out`) ⇒ رویداد واقعی `ValidatorRewarded` برای owner1 (۱۵۸ بلوک، ۱۸۴٫۰۱ Suren؛ `6-events-sanity.txt`: `DistributionOpened, ValidatorRewarded, DistributionPage, …, RewardsDistributed`). سپس انتظار تا بلوک بالاتر از ۵۲۰۰؛ آزمون‌ها در ارتفاع **۵۲۷۹–۵۳۰۶**.

## ۱) خط پایه: خودِ Besu چه می‌گوید (`1-baseline-probe.txt`، ارتفاع ۵۲۷۹)
| بازه | نتیجه |
|---|---|
| `0..4998`، `0..4999`، `1..5000`، `1..5001` (تا ۵۰۰۱ بلوک) | **پذیرفته** (۱۰ لاگ) |
| `0..latest` (۵۲۷۹ بلوک) | **رد**: `-32005 Requested range exceeds maximum RPC range limit` |
| ۲۰۰۰ / ۴۹۹۹ / ۵۰۰۰ بلوک آخر | پذیرفته (۰ لاگ) |

یعنی سقف روی «`toBlock - fromBlock > 5000`» می‌افتد (بازهٔ ۵۰۰۱ بلوکی هنوز می‌گذرد)؛ پیام خطا همان `-32005` است و viem آن را «Request exceeds defined limit.» نشان می‌دهد. (در دور ۲ روی شبکهٔ دیگر `-32602 Invalid params` را برای بازهٔ شامل بلوک‌های بعد از سر دیده بودم؛ آن خطا مربوط به `toBlock` بالاتر از ارتفاع بود، نه سقف.)

## ۲) ValidatorApp، کد رفع‌شده (`2-val-new.txt`) ✅
`DEFAULT_LOG_CHUNK = 2000`؛ ارتفاع ۵۲۸۳: `readOwnerSnapshot` OK؛ **`fetchRewardHistory(owner1)` OK** با یک ردیف `paid` (دور ۱، ۱۵۸ بلوک، ۱۸۴٫۰۱ Suren)، دور ۱ `closed` با ۱ page، جمع پرداخت برابر؛ `fetchOperatorEvents` OK (۰ رویداد). نتیجه: PASS.

## ۳) GovernanceDashboard، کد رفع‌شده (`3-gov-new.txt`) ✅
کاربر owner1 (رأی داده). ارتفاع ۵۳۰۴: `board(user)` OK (اقدام ۱: ۱ رأی، `votedByUser true`)، `recovery`، `treasury`، `registry` OK؛ `board` بدون کاربر و `overview` OK. نتیجه: PASS.

## ۴) مقایسه با کد قدیم (پدر کامیت رفع، صادرشده با `git archive`؛ فقط همان فایل‌ها فرق دارند) — آزمون معنادار است
- ValidatorApp `09dba98^` (`DEFAULT_LOG_CHUNK = 100000`) در ارتفاع ۵۲۸۶: `readOwnerSnapshot` OK ولی **`fetchRewardHistory` FAILED** و **`fetchOperatorEvents` FAILED** («Request exceeds defined limit.»)؛ نتیجه FAIL (`4-val-old.txt`).
- GovernanceDashboard `d7fee51^` در ارتفاع ۵۳۰۶: **`board(user)`، `recovery`، `treasury`، `registry` هر چهار FAILED** با همان خطا؛ `board` بدون کاربر و `overview` OK (`5-gov-old.txt`). این دقیقاً همان الگوی یافتهٔ دور ۲ است و با تحلیل «تابع `votesCastBy` + `getLogs` مستقیم» می‌خواند.

## آنچه آزموده نشد
- رفتار «نصف‌کردن در برابر رد» (`halve on refusal`) روی Besu واقعی: چون تکهٔ پیش‌فرض ۲۰۰۰ همیشه زیر سقف است، مسیر نصف‌کردن اجرا نشد (آزمون واحد همان کامیت‌ها آن را پوشش می‌دهد؛ این‌جا اجرا نکردم).
- نودی با `--rpc-max-logs-range` غیرپیش‌فرض یا RPC عمومی/پروکسی؛ شبکهٔ چندنودی؛ تعداد بسیار زیاد لاگ در یک بازهٔ ۲۰۰۰ بلوکی؛ زمان‌بندی/کارایی خواندن از بلوک ۰ در ارتفاع‌های خیلی بالا (از بلوک ۰ با تکهٔ ۲۰۰۰ در ارتفاع‌های خیلی بالا تعداد درخواست‌ها زیاد می‌شود؛ اندازه‌گیری نشد).
- ValidatorApp/Governance فقط خواندن؛ مسیر نوشتن در دور ۲ آزموده شد؛ SaleDashboard (تکه‌های ۱۰٬۰۰۰ با نصف‌کردن) در این دور دوباره اجرا نشد.
- مرورگر و کیف‌پول واقعی نبود؛ این‌ها فراخوانی مستقیم مدل‌های خواندن همان کد رابط هستند.

## اجرا و پاک‌سازی
ساخته‌شده روی سرور: `~/sur25l-live`، شبکهٔ `sur25l-net` (۱۷۲٫۲۹٫۷۶٫۰/۲۴)، حجم `sur25l-n1-data`، کانتینر `sur25l-n1`. حذف با `cleanup.sh` (فقط پیشوند `sur25l-`) و `rm -rf ~/sur25l-live`؛ وضعیت نهایی: ۰ شیء `sur25*`، کانتینرهای دیگر سرور ۳۲ (برابر با پیش از شروع) — `server-cleanup.txt`. روی PC: SurKMS آزمایشی و تونل SSH این دور متوقف شد؛ نسخهٔ قدیم رابط‌ها در پوشهٔ موقت خارج از مخزن بود.

> این نتایج فقط دربارهٔ Besu `26.9.0` با پیکربندی همین آزمون‌اند و بیانیهٔ آمادگی production نیستند.
