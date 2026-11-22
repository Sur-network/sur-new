# بخش B — مسیرهای باقی‌ماندهٔ Verifier روی Besu با تایمر واقعی

**اجرا:** ۲۰۲۶-۱۱-۲۲، شبکهٔ C (۷ ولیدیتور)، Verifier واقعی (`serve`، سیکل هر ۳۰ ثانیه)، SurKMS واقعی (mTLS)، نود پایش n1، نود زنجیره a1 (archive)، دو نگه‌دارندهٔ شواهد.
**قواعد آزمایشی (برچسب‌خورده، مثل دور اول):** `c01-rules-v1-besu-live-test-r2`: `windowSec` ۴ ساعت → ۹۰۰ ث، `maxCheckGapSec` ۹۰ دقیقه → ۳۰۰ ث، هشدارها کوتاه، `probation.checkIntervalSec` ۳۶۰۰ → ۶۰ ث، `probation.founderConsecutiveOk` ۶ → ۳، `removal.absentHours` ۶ → ۳ (سطل‌ها ۶۰ ثانیه‌ای)؛ در ژنسیس: `recoveryPeriod` ۱۷۲۸۰۰ → ۳۷۰۰ ث. سقف تعلیق (`SUSPENSION_CAP_FRACTION=0.2`، یعنی `max(1, floor(20٪ فعال‌ها))` در ساعت لغزان) **دست‌نخورده** و در ساعت واقعی ۶۰ دقیقه‌ای. فایل‌ها: `rules-live-TESTONLY.json`، `geo-TESTONLY.csv`.
**برچسب‌دار «fixture»:** یک تعلیق دوم (owner4) با **فراخوانی مستقیم SurKMS** ساخته شد، چون سقف برنامه‌ریز تعلیق دوم را در همان ساعت نمی‌دهد و استثنای شکست جمعی قرارداد به دو تعلیق در یک پنجرهٔ ۱ ساعته نیاز دارد. این تعلیق جزو «تصمیم‌های خودِ Verifier» نیست.
**کدی تغییر نکرد.**

## نتیجه
| # | آزمایش | نتیجه |
|---|---|---|
| B1.1 | **دو ولیدیتور (owner6، owner7) همزمان بیش از ۱۵ دقیقه خاموش** (۲۸٫۶٪ مجموعه): هیچ‌کدام `INACTIVE_CONFIRMED` نشد (`UNKNOWN: NETWORK_UNHEALTHY`)، چیزی فرستاده نشد، هر دو Active ماندند | ✅ |
| B1.2 | با روشن‌شدن n6، owner7 تنها: `INACTIVE_CONFIRMED` (۰ پیشنهاد، ۳۷ نوبت)، `recordSuspension(owner7)` با SurKMS امضا و ماین شد (۳۸۳٬۶۳۱ گاز، همان عدد دور اول)، owner7 Demoted، QBFT از ۷ به ۶ | ✅ |
| B1.3 | **سقف لغزان:** n6 دوباره خاموش، پس از ۱۵ دقیقه `INACTIVE_CONFIRMED`؛ ردیف دوم **`held`** با `SUSPENSION_CAP: 1 suspensions in the last hour, cap 1 of 6 active`؛ owner6 Active ماند؛ ردیف پس از ۱۸۰۰ ثانیه `expired` شد و دوباره ارسال نشد (n6 تا آن موقع سالم بود) | ✅ |
| B2.1–2.4 | owner7 و owner4 شناسهٔ نود را با API Verifier ثبت کردند؛ **fixture:** `recordSuspension(owner4)` مستقیم از SurKMS (۳۱۴٬۹۰۹ گاز)؛ هر دو در یک دورهٔ تنزل (شمار ۲، مرجع ۷: ۲×۱۰۰۰۰ > ۷×۲۰۰۰) | ✅ |
| B2.5 | **housekeeping با کلید verifier:** پس از بستن دورهٔ ۱ ساعته، Verifier خودش `resolveMassFailureCheck` را برای پروندهٔ owner7 فرستاد (۱۰۲٬۹۷۱ گاز، `ExemptMassFailure`، `pendingSlashEpoch=0`). پروندهٔ owner4 (fixture) در جدول Verifier نیست؛ همان فراخوانی بی‌مجوز را دستی با حساب deployer زدم (`c-b2-fixture-hk.mts`، ۷۸٬۱۷۳ گاز) | ✅ (با fixture) |
| B2.6/2.7 | پس از `recoveryPeriod` ۳۷۰۰ ثانیه برنامه‌ریز **`recordRecovery`** را برای owner7 (۲۴۸٬۸۳۳ گاز) و owner4 (۲۴۸٬۸۴۵) فرستاد؛ سنجش نود: حضور در `admin_peers`، ژئو iran، همگام، نسبت ≥ ۹۵٪، پوشش ≥ ۵۰٪؛ هر دو Active، QBFT برگشت به ۷ | ✅ |
| B3 | **selfSuspend/recordResume:** owner7 `selfSuspend` (مجموعه ۶ → ۵، بدون پروندهٔ جریمه)؛ n7 خاموش + `requestResume`: برنامه‌ریز **نمی‌فرستد** (`NODE_CHECK_FAIL`)؛ با روشن‌شدن n7 و سنجش OK، `recordResume` (۲۴۵٬۳۵۵ گاز) با SurKMS و owner7 Active | ✅ ۴ از ۴ |
| B4 | **`recordPreExitViolation`:** (Verifier بدون کلاس SUSPENSION راه‌اندازی مجدد شد) n6 ۱۶ دقیقه خاموش؛ owner6 (قرارداد) با `exec` → `requestExit` در حالت Active: Exiting؛ Verifier پنجرهٔ **پیش از** درخواست را سنجید و `recordPreExitViolation` (۳۲۲٬۸۱۱ گاز) را فرستاد؛ رویداد `PreExitCaseRecorded` با `violationAt` = ثانیهٔ پیش از `exitRequestedAt` | ✅ ۳ از ۳ |
| B5 | **M12 `recordRecoveryRemoval`:** n7 پیش از بلوک پایه خاموش؛ بلوک بازگشت؛ ثبت پرونده با CLI واقعی (`recovery-case add`، چیزی روی زنجیره ثبت نمی‌شود)؛ پس از ۳ سطل پیاپی غیبت، برنامه‌ریز `recordRecoveryRemoval(owner7)` را با SurKMS فرستاد (۲۷۳٬۷۰۹ گاز): وضعیت RemovedInRecovery، حالت Recorded، اعتراض و **۳ رأی هیأت علیه حذف** ⇒ لغو (VD-4): SelfSuspended با درخواست ازسرگیری باز؛ برنامه‌ریز پس از سنجش نود `recordResume` فرستاد و **حذف دوم برای همان پرونده ثبت نکرد** | ✅ (به توضیح زیر نگاه کنید) |

**دو ردیف FAIL در `c-b5.json` از خطای خودِ اسکریپت آزمون‌اند، نه Verifier:** B5.2 مجموعهٔ QBFT را ۶ انتظار داشت ولی درست ۵ است (owner6 در B4 خارج شده بود)؛ همهٔ واقعیت‌های دیگر آن ردیف (ردیف outbox `confirmed`، وضعیت ۵، حالت Recorded) درست بودند. B5.5 آخرین ردیف `recordResume` قدیمیِ B3 را خواند؛ بررسی تصحیح‌شده `c-b5b.json` (۱ از ۱ ✅). خروجی خام دست‌نخورده نگه داشته شده است.

گاز واقعی (به‌ترتیب outbox، `gas-final.txt`): `confirmOperatorReady` ۶۴٬۴۳۲؛ `recordSuspension` ۳۸۳٬۶۳۱؛ `resolveMassFailureCheck` ۱۰۲٬۹۷۱؛ `recordRecovery` ≈۲۴۸٬۸۴۰؛ `recordResume` ۲۴۵٬۳۵۵؛ `recordPreExitViolation` ۳۲۲٬۸۱۱؛ `recordRecoveryRemoval` ۲۷۳٬۷۰۹ — همه زیر ۴٬۰۰۰٬۰۰۰ گاز مجازِ Verifier.

## یافته‌ها
- **B-F1 (رفتار طراحی‌شده، مهم برای عملیات):** پس از هر خاموشی چندنفره، تعلیق بعدی تا لغزیدن پنجره از روی دوران خاموشی (`roundChangeShare` ۰٫۲۳۳ > ۰٫۲) به تعویق می‌افتد (`NETWORK_UNHEALTHY`): n6 در ۱۲:۳۹ روشن شد، تعلیق owner7 در ۱۲:۵۲ (≈۱۳ دقیقه). با پنجرهٔ واقعی ۴ ساعته این تأخیر تا ۴ ساعت می‌شود.
- **B-F2 (Besu، مهم):** با ۲ از ۷ ولیدیتور خاموش (۵ زنده = دقیقاً حد نصاب) زنجیره **متوقف نشد** ولی کند شد: ۲ بلوک در ۲۰ ثانیه (≈۱۰ ثانیه/بلوک به‌جای ۲)؛ تراکنش‌های رابط (D) تا ۹۰ ثانیه منتظر ماندند.
- **B-F3:** `held` و سپس `expired` بدون ارسال دوباره درست رفتار کرد. در زمان `expired` نیز Verifier هیچ دستوری برای «تأیید دستی» ندارد (طراحی‌شده).
- **B-F4 (کد، نه آزموده):** مالک قراردادی نمی‌تواند شناسهٔ نود را با API ثبت کند (احراز با امضای EOA: `recoverMessageAddress`؛ از روی کد، اجرا نشد) و بنابراین مسیر بازیابی/ازسرگیری برنامه‌ریز برای مالک دارای کد (founder قراردادی در ژنسیس آزمایشی) پاسخ `AWAITING_NODE_ID` می‌دهد. مسیر pre-exit برای او بدون ثبت شناسه کار کرد.
- **B-F5:** kill سخت Verifier ⇒ lease تا ≈۵ دقیقه (تکرار یافتهٔ دور اول)؛ راه‌اندازی مجدد خودکار پس از انقضا موفق شد.
- ناسازگاری Besu با قراردادها/Verifier که نیاز به تغییر کد داشته باشد دیده نشد.

## آزموده نشد
چند تعلیق متوالیِ بدون fixture با پنجرهٔ واقعی؛ مسیر جریمهٔ کامل (تحویل، تجدیدنظر ۷۲ ساعته، `executeUncontestedSlash`)؛ `assertDeliveryDisputed`، `resolveAppealIfExpired`؛ حذف در بازیابی با ارجاع به مجمع و انقضای ۷ روزه (`expireRecoveryRemoval`)؛ `clearStaleVotes`/`refreshBoard` با زمان واقعی؛ activation ورودی پولی (۷ روز)؛ API برنامه‌ها زیر بار؛ شکست جمعی ≥ ۲۰٪ با تعلیق‌های تولیدشده توسط خود برنامه‌ریز.
