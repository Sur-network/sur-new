# آزمون Besu روی سامانهٔ نهایی v2.5 — دور دوم («v26-r2»، گزارش یکپارچه)

**تاریخ:** ۲۰۲۶-۱۱-۲۲ · **Besu:** `hyperledger/besu:26.9.0` روی سرور Ubuntu `192.168.1.210` در Docker؛ فقط اشیای `sur25c-*`، RPC فقط روی `127.0.0.1` و با تونل SSH؛ شبکهٔ آزمایشی ۲۶۲۰۲۵.
**مبنا:** قراردادهای `GenesisBuilder/contracts` (بدون تغییر)؛ ژنسیس با خودِ CLI ساخته شد و سپس **برچسب‌خورده** تغییر کرد (همهٔ تفاوت‌ها در [network/TESTONLY-NOTES.txt](network/TESTONLY-NOTES.txt)). **کلیدها:** همه آزمایشی؛ سه کلید سرویس را SurKMS (init تازه) ساخت و بیرون نیامد ([network/TEST-KEYS-DO-NOT-REUSE.json](network/TEST-KEYS-DO-NOT-REUSE.json)).
**کد:** هیچ کدی از قراردادها، GenesisBuilder، SurKMS، Verifier، Router، NodeCheck و رابط‌ها **تغییر نکرد**. فقط اسکریپت و مستند افزوده شد (`Deployments/BesuLive`، فایل‌های `*-c*`/`c-*.mts`، `ui-live/`، `server-c/`).
**ادعای آمادگی production نمی‌شود.** مرورگر و کیف‌پول واقعی در دسترس نبود.

## نتیجه به‌تفکیک بخش
| بخش | نتیجه | گزارش |
|---|---|---|
| **A** NodeCheck روی Besu واقعی + M9 از برنامه‌ریز Verifier | ✅ آزمون مستقیم ۲۰/۲۰؛ مسیر کامل ۲۱/۲۱: `confirmOperatorReady` دو بار روی Besu نشست و مجموعهٔ QBFT عوض شد؛ امتناع‌ها (کلید اشتباه، چالش کهنه، نود آماده نیست، نود نیست) درست | [A-nodecheck](A-nodecheck/RESULT-fa.md) |
| **B** Verifier با تایمر واقعی | ✅ دو خاموش همزمان ⇒ بدون تعلیق؛ تعلیق واقعی؛ سقف لغزان (`held`)؛ housekeeping؛ `recordRecovery` (۲)؛ `recordResume` (۲)؛ `recordPreExitViolation`؛ M12 `recordRecoveryRemoval` + مسیر VD-4. (دو ردیف FAIL در خروجی خام B5 از خطای اسکریپت آزمون‌اند و توضیح داده شده) | [B-verifier](B-verifier/RESULT-fa.md) |
| **C** Router با مالک دارای کد | ✅ ۷/۷: توزیع کامل، `ValidatorRewardDeferred`، claim ردشده تا باز شدن `receive()`، سپس claim دقیق | [C-router](C-router/RESULT-fa.md) |
| **D** سه رابط روی RPC Besu | ✅ Governance ۱۳/۱۳، ValidatorApp ۱۱/۱۱، SaleDashboard ۹/۹ + ۱ مشاهده؛ یافتهٔ `getLogs` (زیر) | [D-uis](D-uis/RESULT-fa.md) |
| **E** موردهای زمان واقعی | فهرست ۱۳ مورد و پیشنهاد آزمون؛ هیچ کانتینری روزها روشن نماند | [E-realtime](E-realtime/RESULT-fa.md) |

## چیدمان شبکه و برچسب‌های آزمایشی (همه روشن)
۹ نود Besu در شبکهٔ `sur25c-net` (۱۹۸٫۲۰.۷۷.۰/۲۴): n1..n7 (۷ ولیدیتور بنیان‌گذار)، x1 (نودِ کلید جایگزین)، a1 (archive/FOREST)؛ هر نود ۰٫۵ CPU، ۱ GiB، `-Xmx512m`؛ چهار کانتینر NodeCheck (۱۲۸ MiB). سرور شامل سرویس‌های تولیدی دیگر بود؛ بار هنگام آزمون ≈۱٫۵ ماند. تفاوت‌های ژنسیس با تولید: (۱) کد اجرایی Distributor با `MIN_DISTRIBUTION_INTERVAL` ۶۰ ثانیه و `ABORT_DELAY` ۱۲۰ ثانیه؛ (۲) `recoveryPeriod` اولیهٔ Registry ۳۷۰۰ ثانیه؛ (۳) founder شمارهٔ ۶ یک **قرارداد** (`TestOnlyToggleOwner`) است؛ (۴) زیرشبکهٔ داکر «عمومی‌طبقه‌بندی‌شده» + جدول ژئوی آزمایشی (فقط برای قواعد آدرسِ M9)؛ (۵) قواعد Verifier نسخهٔ `c01-rules-v1-besu-live-test-r2`؛ (۶) fixture تعلیق مستقیم owner4.

## یافته‌ها (با شاهد؛ هیچ‌کدام نیاز به تغییر کد در دامنهٔ این دور نداشت)
1. **(عملیاتی) قاعدهٔ SurKMS برای `confirmOperatorReady` و `recordRecoveryRemoval` پیش‌فرض خاموش است.** تا روشن‌شدن، ردیف outbox با `POLICY_DENIED: function-disabled` در `prepared` می‌ماند و پس از `rule enable` همان ردیف تأیید می‌شود. باید در runbook بیاید. (A)
2. **(استقرار) M9 فقط با آدرس عمومیِ دیده‌شده توسط نود پایش و ژئوی IR کار می‌کند** و پورت NodeCheck باید از Verifier در همان آدرس در دسترس باشد؛ آدرس خصوصی/NAT ⇒ `UNKNOWN`. NodeCheck روی Besu واقعی بدون مشکل اجرا شد. (A)
3. **(رابط، مهم، به‌شرط تأیید در ارتفاع بالا) `getLogs` از بلوک ۰ در GovernanceDashboard** (`gov/common.ts`، `gov/recovery.ts`) و **تکهٔ پیش‌فرض ۱۰۰٬۰۰۰ بلوکی در ValidatorApp** با سقف ۵۰۰۰ بلوکی Besu ناسازگارند؛ نتیجهٔ اجرای دیرهنگام در بخش بعد. (D)
4. **(Besu) با ۲ از ۷ ولیدیتور خاموش زنجیره می‌ماند ولی کند می‌شود** (≈۱۰ ثانیه/بلوک)؛ حد نصاب دقیقاً ۵ است. (B)
5. **(طراحی‌شده) پس از هر خاموشی چندنفره تعلیق بعدی تا لغزیدن پنجره از روی آن دوران عقب می‌افتد** (`NETWORK_UNHEALTHY`، ۱۳ دقیقه با پنجرهٔ ۹۰۰ ث؛ با ۴ ساعت واقعی تا ۴ ساعت). (B)
6. **(کد) مالک قراردادی نمی‌تواند شناسهٔ نود را با API Verifier ثبت کند** (امضای EOA)؛ در نتیجه بازیابی/ازسرگیری برنامه‌ریز برای او ممکن نیست (از روی کد؛ اجرا نشد). (B)
7. **(مشاهده) گاز صریح × کمینهٔ قیمت گاز:** Besu `gasLimit × gasPrice` را از موجودی طلب می‌کند؛ ValidatorApp برای `selfSuspend`/`requestExit`/`transferSeat` ۳٬۰۰۰٬۰۰۰ گاز صریح می‌گذارد (با `10^14` ⇒ ۳۰۰ Suren). به قیمت کمینهٔ گاز واقعی وابسته است. (D)
8. kill سخت Verifier ⇒ lease ≈۵ دقیقه (تکرار دور اول). (B)
9. گاز واقعی Besu: `confirmOperatorReady` ۶۴٬۴۳۲؛ `recordSuspension` ۳۸۳٬۶۳۱؛ `recordRecovery` ≈۲۴۸٬۸۴۰؛ `recordResume` ۲۴۵٬۳۵۵؛ `recordPreExitViolation` ۳۲۲٬۸۱۱؛ `recordRecoveryRemoval` ۲۷۳٬۷۰۹؛ `resolveMassFailureCheck` ۱۰۲٬۹۷۱.

اشتباه‌های خودِ اجرا (ثبت‌شده، رفع‌شده): تراکنش‌های صرافی با گاز ۵ میلیون تا موجودی کافی نبود در صف ماندند (D)؛ یک بررسی B5 مجموعهٔ ۶ به‌جای ۵ انتظار داشت و یکی ردیف قدیمی را خواند (B)؛ دور اول اسکریپت A2 به‌خاطر قاعدهٔ خاموش SurKMS مهلت گرفت و ادامه‌اش جدا اجرا شد (`c-a2-run1.out` + `c-a2b.out`).

## اجرای دیرهنگام (سقف `getLogs` در ارتفاع بالای ۵۰۰۰)
در ارتفاع ۵۰۶۱–۵۰۷۵ (≈۳٫۵ ساعت پس از ژنسیس؛ فایل‌ها: [D-uis/c-d-gov-late.txt](D-uis/c-d-gov-late.txt)، [D-uis/c-d-val-late-default.json](D-uis/c-d-val-late-default.json)):
- **ValidatorApp** با تکهٔ پیش‌فرض خودش (۱۰۰٬۰۰۰ بلوک): بازسازی سابقهٔ پاداش **شکست خورد** با «Request exceeds defined limit»؛ با تکهٔ ۲۰۰۰ بلوکی همان خوانش **موفق** شد (مالک قراردادی: ۱ ردیف مؤجل، ۱ claim). پیش‌تر در ارتفاع ۹۱۱ با پیش‌فرض پاس شده بود.
- **GovernanceDashboard** (بدون تغییر کد): `board(user)`، `recovery`، `treasury` و `registry` **شکست خوردند** با همان خطا؛ `board` بدون کاربر، `overview` و `foundation` سالم ماندند. یافتهٔ ۳ **تأیید شد**. در تولید با بلوک ۲ ثانیه‌ای پس از ≈۲٫۸ ساعت از ژنسیس رخ می‌دهد، مگر نود با `--rpc-max-logs-range` بزرگ‌تر اجرا شود یا رابط تکه‌تکه بخواند.
- Besu: `eth_getLogs` برای ۰..۴۹۹۹ در ارتفاع ۳۹۷۸ خطای «Invalid params» داد (کل بازهٔ ۰..۳۹۷۸ پاسخ داد)؛ پس سقف همان ۵۰۰۰ بلوک است و خطا متن مخصوص بازه ندارد (مثل دور اول).

## آنچه آزموده نشد
زمان‌های واقعی (جدول بخش E)؛ مرورگر/کیف‌پول واقعی و رندر صفحه؛ پایش commit-seal؛ جغرافیای واقعی؛ NodeCheck پشت NAT/روی هاست جدا؛ Router: جایگزینی تراکنش، RD-5/16 روی QBFT، HA، `certifyRateStart`؛ توزیع دوم؛ HSM، webhook، `systemd`؛ پارتیشن شبکه؛ مسیر کامل جریمه (۷۲ ساعت)؛ قرعه‌کشی؛ انتقال صندلی؛ شکست جمعی ≥ ۲۰٪ با تصمیم‌های خودِ برنامه‌ریز؛ گام‌های زمانی Sale.

## تغییرات روی سرور و پاک‌سازی
**ساخته‌شده روی سرور:** پوشهٔ کاری `~/sur25c-live` (اسکریپت‌ها، ژنسیس و کلیدهای آزمایشی نودها، کد build‌شدهٔ NodeCheck)؛ شبکهٔ `sur25c-net`؛ ۹ حجم `sur25c-*-data`؛ ۹ کانتینر Besu؛ ۴ کانتینر `sur25c-nc-*` (ایمیج موجود `node:22-alpine`، بدون pull). هیچ شیء دیگری (کانتینر، حجم، شبکه، ایمیج، تنظیم سیستم) ساخته یا لمس نشد؛ `sudo` استفاده نشد.
**پاک‌سازی (اسکریپت `cleanup.sh` الگوی دور اول، فقط پیشوند `sur25c-`):** ۱۳ کانتینر، ۹ حجم و ۱ شبکه حذف شدند؛ سپس `~/sur25c-live` حذف شد. وضعیت نهایی: ۰ شیء `sur25c-*`؛ تعداد کانتینرهای دیگر سرور ۳۲ (برابر با پیش از شروع)؛ پوشهٔ `~/sur-besu-live` (دور اول) دست‌نخورده ([network/server-before-cleanup.txt](network/server-before-cleanup.txt)).
**روی PC (ویندوز):** SurKMS آزمایشی، Verifier و تونل‌های SSH این دور متوقف شدند؛ داده‌های آزمایشی در `Deployments/BesuLive/{netC,kms-data-c,runs-c}` (در `.gitignore`) ماندند. ثبت حسابرسی SurKMS: `audit chain OK (64 records)` ([network/surkms-audit-verify.txt](network/surkms-audit-verify.txt)).

> این نتایج فقط دربارهٔ هش ژنسیس ثبت‌شده، Besu `26.9.0` و همین پیکربندی‌اند و بیانیهٔ آمادگی production نیستند. هیچ push انجام نشد.
