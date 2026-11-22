# بخش C — Router واقعی با مالکِ دارای کد روی زنجیرهٔ QBFT واقعی (پرداخت مؤجل و claim)

**اجرا:** ۲۰۲۶-۱۱-۲۲، شبکهٔ C. **Router واقعی** (`run-once`، `ROUTER_PAGE_SIZE=3`، نود زنجیره = archive `a1`) و **SurKMS واقعی** (کلید `distributionOracle`، mTLS، گواهی سنجاق‌شده). کدی تغییر نکرد.
**برچسب آزمایشی (مثل دور اول، شبکهٔ B):** در کد اجرایی Distributor دو ثابت کوتاه شد (`MIN_DISTRIBUTION_INTERVAL` ۲۳ ساعت → ۶۰ ثانیه، `ABORT_DELAY` ۳ روز → ۱۲۰ ثانیه)؛ برای این بخش فقط اثر ثابت‌ها نیست (یک توزیع کامل یک‌بار اجرا شد)، ولی ژنسیس همان نسخه است (`../network/TESTONLY-NOTES.txt`).
**مالک با کد:** founder شمارهٔ ۶ در ژنسیس **قرارداد** `TestOnlyToggleOwner` است (آدرس `0xC0DE…0006`): `receive()` تا `setOpen(true)` برمی‌گردد، `doClaim(dist)` و `exec(to,data)` دارد. Registry مالکان بنیان‌گذار را از پیکربندی می‌گیرد (قاعدهٔ EOA فقط هنگام ورود است)؛ این مالک با `exec` عملیات `setOperator` را انجام داد و Verifier آن را فعال کرد (۷ ولیدیتور). (ابزار ساخت ژنسیس هشدار «OWNER ACTION REQUIRED: نمی‌تواند ثابت کند مالکان EOA هستند» را چاپ کرد؛ این همان هشدار شناخته‌شده است.)

## نتیجه (۷ از ۷ ✅؛ `c-c.json`، `router-run1.out`)
| # | مورد | نتیجه |
|---|---|---|
| C.1 | یک اجرای `run-once` Router: ۱ open + ۳ page + ۱ close روی Besu، همه با امضای SurKMS؛ بازهٔ بلوک ۱–۶۶۷ (۶۶۷ بلوک)؛ هر ۵ گام `confirmed`، `reverted 0`؛ ۲ دقیقه و ۲۷ ثانیه | ✅ |
| C.2 | برای مالک با کد، رویداد `ValidatorRewardDeferred` فقط برای همان مالک (۸۵ بلوک، `110.198…` Suren)؛ فراخوانی نشد؛ هشدار Router `CONTRACT_PAYEE` | ✅ |
| C.3 | `claimable(owner6)` = مبلغ مؤجل = `totalClaimable` | ✅ |
| C.4 | `RewardsDistributed`: ۷ پرداخت‌شونده، ۶۶۷ بلوک، سازگار با open | ✅ |
| C.5 | `claim()` توسط قرارداد مالک وقتی `receive()` آن برمی‌گردد: **کل تراکنش revert** («claim transfer failed»)، اعتبار باقی می‌ماند | ✅ |
| C.6 | پس از `setOpen(true)`، `claim()` دقیقاً مبلغ اعتبار را به قرارداد می‌پردازد: `claimable 0`، موجودی قرارداد +۱۱۰٫۱۹۸… (برابر تا wei)، رویداد `ClaimableWithdrawn`، `totalClaimable 0` | ✅ |
| C.7 | claim دوم بدون اعتبار revert می‌شود (پرداخت دوبل نیست) | ✅ |

نکتهٔ انتساب: این توزیع **پس از** دو تعویض کلید نود M9 (بخش A) انجام شد؛ Router بلوک‌ها را با بازپخش رویدادها (`OperatorChangeConfirmed`) به مالک درست نسبت داد (۶ مالک EOA مستقیم پرداخت شدند، مالک ۷ قراردادی مؤجل)، و تمام معیارهای ایمنی (هویت موجودی هر بلوک روی archive) سبز بود.

## آزموده نشد
RD-5/RD-16 (تولیدکنندهٔ بدون مالک)؛ جایگزینی تراکنش توسط خود Router؛ HA؛ `certifyRateStart`؛ توزیع دوم با ثابت ۶۰ ثانیه‌ای و پایدار؛ فاصلهٔ واقعی ۲۳ ساعت و `abort` پس از ۳ روز (بخش E).
