# بخش A — NodeCheck (SUR_NODE_CHECK_V1) روی Besu واقعی و مسیر کامل M9 از برنامه‌ریز Verifier

**اجرا:** ۲۰۲۶-۱۱-۲۲، شبکهٔ C (Besu 26.9.0، ۹ نود، ژنسیس آزمایشی برچسب‌خورده؛ `../network/TESTONLY-NOTES.txt`). **این نخستین اجرای NodeCheck روی Besu واقعی است** (پیش‌تر فقط ۱۳۵ آزمون واحد/یکپارچه).
**اجزای واقعی:** NodeCheck (`Deployments/NodeCheck`، کد build‌شده `dist/`)، Verifier واقعی (`serve`)، SurKMS مستقل (mTLS، کلید verifier)، Besu واقعی. **کدی از Verifier / NodeCheck / SurKMS / قراردادها تغییر نکرد.**

## چیدمان
- NodeCheck در کانتینر `sur25c-nc-<node>-<port>` (ایمیج موجود `node:22-alpine`، بدون pull) با `--network container:sur25c-<node>`؛ یعنی «کنار نود» و در همان فضای شبکه: `127.0.0.1:8545` همان Besu است (فقط `eth_chainId`، `eth_blockNumber`، `eth_getBlockByNumber`)، روی آدرس خود نود گوش می‌دهد، `ALLOWED_CLIENTS` فقط دروازهٔ داکر (`198.20.77.1`). کلید پایش یک کلید تازه و جدا از کلید نود و مالک است (فایل با مجوز 600).
- دو نمونهٔ اصلی: کنار `x1` (مالک owner2، کلید نود opX1) و کنار `a1` (owner3، کلید opA1)؛ دو نمونهٔ کمکی کنار `x1` فقط برای آزمون امتناع (Besu مرده؛ مبدأ غیرمجاز).
- **سازگاری با قواعد Verifier بدون تغییر کد:** Verifier هرگز به آدرس غیرعمومی چالش نمی‌فرستد و ژئو را برای آدرس خصوصی «unknown» می‌گیرد؛ بنابراین زیرشبکهٔ داکر شبکهٔ C یک بازهٔ **عمومی‌طبقه‌بندی‌شده** (`198.20.77.0/24`، فقط روی پل داکر همین سرور) است، فایل جدول ژئو آزمایشی (`runs-c/verifier/geo.csv`: این بازه = IR) به `VERIFIER_GEOIP_DB_PATH` داده شد، و چون Verifier روی PC ویندوز اجرا می‌شود و به کانتینر دسترسی مستقیم ندارد، یک preload کوچک `fetch-remap.mjs` فقط درخواست‌های `198.20.77.*` را به تونل SSH (`127.0.0.1:<همان پورت>`) می‌برد. خود `HttpCompanionTransport` و همهٔ بررسی‌های هفتگانه بدون تغییر اجرا شدند.

## نتیجه
### A1 — آزمون مستقیم پروتکل (۲۰ از ۲۰ ✅؛ `c-a1.json`)
پاسخ ۲۰۰ و تأیید با `verifyResponse` خودِ Verifier (هفت کنترل، مرجع = نود archive a1)؛ هر سه هش بلوک درست، شناسهٔ زنجیره ۲۶۲۰۲۵؛ ۱۰ چالش پیاپی همه پاسخ و تأیید (۱٫۳ ثانیه برای ۱۰ تا). امتناع‌ها (هیچ‌چیز امضا نمی‌شود): بازپخش همان چالش `409 CHALLENGE_REPLAY`؛ چالش کهنه (مهلت ۱۰ دقیقه پیش) `408 DEADLINE_PASSED`؛ `issuedAt` یک ساعت آینده و پنجرهٔ ۶۰۰ ثانیه‌ای `400 BAD_TIME`؛ مالک/اپراتور/شناسهٔ نود دیگر `403 WRONG_IDENTITY`؛ شناسهٔ زنجیرهٔ ۲۶۲ `409 WRONG_NETWORK`؛ بلوک بالاتر از ارتفاع `409 BLOCK_NOT_AVAILABLE`؛ ۴ بلوک/نسخهٔ دیگر/فیلد اضافه `400`؛ **نود آماده نیست** (Besu محلی پاسخ نمی‌دهد) `503 NODE_RPC_UNAVAILABLE`؛ مبدأ غیرمجاز `403 FORBIDDEN_CLIENT`؛ GET `405`. سمت Verifier: پاسخ درست ولی با **کلید پایش دیگر** `BAD_SIGNATURE`؛ پاسخ درست ولی دیرهنگام `RESPONSE_AFTER_DEADLINE`.

### A2 — مسیر کامل M9 از طریق Verifier واقعی (۲۱ بررسی ✅؛ `c-a2-run1.out` + `c-a2b.out`، دیتابیس: `c-a2b-db.json`)
1. owner2 (Active) `proposeOperator(opX1)`؛ اجماع دست‌نخورده. Verifier: «شناسهٔ نود ثبت نشده» (`AWAITING_NODE_ID`)؛ پس از `PUT /api/v1/node-id`: حضور x1 در `admin_peers` نود پایش، آدرس عمومی، ژئو iran، شناسه↔اپراتور OK؛ ولی کلید پایش ثبت نشده → `UNKNOWN AWAITING_MONITOR_KEY`، چیزی فرستاده نشد.
2. ثبت کلید پایش برابر کلید نود قدیم یا کلید مالک رد شد (`422 MONITOR_KEY_NOT_DISTINCT`).
3. **نود آماده نیست:** کلید پایش با پورتی ثبت شد که NodeCheck آن Besu‌اش مرده است → `FAIL COMPANION_NO_RESPONSE`؛ هیچ confirm فرستاده نشد.
4. پورت درست (۱۹۹۵۰) → چالش با NodeCheck واقعی، هفت کنترل `OK` (`sur_node_check_v1`، ۷ بررسی OK در سیکل‌های پیاپی).
5. **`confirmOperatorReady(owner2, opX1, evidenceHash)` روی زنجیره نشست** (بلوک ۴۶۶، gasUsed ‏۶۴٬۴۳۲)، مجموعهٔ QBFT: opX1 داخل و op2 بیرون، همچنان ۷ ولیدیتور؛ نود x1 در ۲۵ بلوک بعدی بلوک پیشنهاد داد. هش شواهد در رویداد `OperatorChangeConfirmed` با هش ردیف outbox و بستهٔ شواهد دو نگه‌دارنده یکی است. تراکنش را **SurKMS واقعی** امضا کرد.
6. **کلید اشتباه:** owner3 → opA1 با کلید پایشِ نادرست ثبت‌شده: `FAIL BAD_SIGNATURE`، چیزی فرستاده نشد؛ پس از ثبت کلید درست همان پیشنهاد `OK` شد و confirm نشست (بلوک ۵۵۰)؛ QBFT: opA1 داخل، op3 بیرون.
7. **نود وجود ندارد:** owner4 → op8 (هیچ نودی با آن شناسه نیست): `FAIL PEER_ABSENT` در هر بررسی، هیچ‌چیز فرستاده نشد؛ مالک لغو کرد.

## یافته‌ها
- **(عملیاتی) دو قاعدهٔ SurKMS به‌صورت پیش‌فرض خاموش‌اند** (`confirmOperatorReady`، `recordRecoveryRemoval`؛ `rule list`). در اجرای اول Verifier بستهٔ شواهد را ساخت و امضا از SurKMS با `POLICY_DENIED: function-disabled` رد شد (هشدار `SIGNER_FAILED`)؛ ردیف outbox در حالت `prepared` ماند؛ پس از `rule enable` مدیر سرور، **همان ردیف** در سیکل بعد امضا، ارسال و تأیید شد (بدون ساخت ردیف دوم). رفتار درست و ایمن است، ولی باید در runbook بیاید: «پیش از فعال‌کردن OPCHANGE/REMOVAL در Verifier قاعدهٔ SurKMS را روشن کنید».
- **(مفروضات استقرار)** M9 فقط وقتی کار می‌کند که آدرس نودی که نود پایش در `admin_peers` می‌بیند عمومی باشد و در جدول ژئو «IR» شود و پورت NodeCheck از Verifier در همان آدرس در دسترس باشد؛ پشت NAT/آدرس خصوصی نتیجه `UNKNOWN` است (طراحی‌شده). در شبکهٔ واقعی باید آدرس دیده‌شده از نود پایش با آدرس واقعی NodeCheck یکی باشد.
- ناسازگاری Besu 26.9.0 با قالب `SUR_NODE_CHECK_V1` یا کد NodeCheck/Verifier دیده نشد.

## آزموده نشد
پایش commit-seal («not testable» در طراحی)؛ نود پایش با پوشش جغرافیایی واقعی (جدول ژئو آزمایشی)؛ NodeCheck پشت NAT/روی هاست جدا؛ ۷ روز انقضای واقعی پیشنهاد؛ بار همزمان چند مالک؛ بازیابی Verifier بین بررسی و ارسال (قفل پس از kill: دیده شد، بخش B).
