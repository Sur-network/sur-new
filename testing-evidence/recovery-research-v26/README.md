# پژوهش بازیابی اضطراری اجماع روی Shanghai/Cancun — گزارش (دور r26)

**تاریخ:** ۲۰۲۶-۱۱-۲۲ · **Besu:** `hyperledger/besu:26.9.0` (image id محلی `sha256:4fb1fede…`) · **اشیای Docker:** فقط `sur25r-*` (همه در پایان حذف شدند؛ بررسی شد که هیچ `sur25r-*` نمانده).
**کلیدها:** همه دورریختنی (`state-THROWAWAY-KEYS.json` در هر پوشه). قرارداد، سرویس و سند سیاست تغییر نکردند.

## ۰. انحراف از دستور (مهم)
سرور `192.168.1.210` در تمام مدت در دسترس نبود (ping: `Destination host unreachable` از 192.168.1.199؛ ssh پورت 22: timeout؛ در ARP نبود). پس **همهٔ آزمایش‌ها روی Docker Desktop همین رایانه (ویندوز، ۱۶ هستهٔ منطقی، ۱۶GB)** با همان image `hyperledger/besu:26.9.0` و همان پیشوند `sur25r-` اجرا شد. هیچ شیئی روی سرور لمس نشد (و در نتیجه `sur25c-`/`sur25b-` هم نه). تفاوت‌ها: تک‌میزبان، ۴ نود (نه ۷)، بدون شبکهٔ واقعی؛ اینکه digest ثبت‌شدهٔ سرور (`ca05efeb…`) با این image یکی است بررسی نشد. تکرار روی سرور با ابزار پیوست (`tools/lab.mjs`) ساده است.

## ۱. خلاصه
1. **علت توقف دور ششم پیدا و بازتولید شد** (آزمایش e1، همان خطای دقیق). علت یک ناسازگاری داخلی Besu است: در گذار با کلید *timestamp*، «قاعدهٔ اعتبارسنجی هدر» با timestamp **خودِ بلاک** انتخاب می‌شود ولی «فهرست ولیدیتور و extraData» با timestamp **بلاک والد**. نخستین بلاکی که `timestamp ≥ کلید` دارد همیشه والدی با timestamp کمتر دارد، پس هدرش (ساخته‌شده با قاعدهٔ قدیم: `validators=[]`) با قاعدهٔ جدید (`blockheader`: باید فهرست پر باشد) رد می‌شود، در هر دور و برای همهٔ نودها.
2. **فهرست صریح `validators` در گذار با کلید timestamp اصلاً اعمال نمی‌شود** (override در کد فقط با *شمارهٔ بلاک* جست‌وجو می‌شود) — آزمایش e6.
3. **روش کارکنندهٔ آزموده‌شده روی genesis با `shanghaiTime=cancunTime=0` و کلید timestamp: گذار `contract` ← `contract` با آدرس قرارداد «ولیدیتورهای ذخیره/اضطراری» (standby) که از قبل در state وجود دارد** (e5): از دست دادن نصاب، بازیابی، بازگشت به Registry، همگام‌سازی یک نود تازه از genesis — همه کار کرد.
4. **گذار `blockheader` در Shanghai/Cancun روش مطمئنی ندارد**: یا زنجیره می‌ایستد (e1، e6، e7)، یا فقط برای نودهای هم‌اکنون همگام کار می‌کند و **هیچ نود تازه‌ای دیگر نمی‌تواند تاریخچه را همگام کند** (e2، e4). روی London (بدون Shanghai/Cancun) همه‌چیز درست کار می‌کند (e3) ولی سور آن را ندارد.
5. قرارداد standby را **نمی‌شود هنگام بحران تزریق کرد** (تغییر `alloc` ⇐ «Supplied genesis block does not match chain data»، e8)؛ باید از پیش در state باشد.

## ۲. آنچه دور ششم دیده بود (از `FINDINGS.md` بند ۳ و `REPORT.md`)
genesis Shanghai/Cancun با `shanghaiTime=cancunTime=0`، Registry ۷تایی در حالت contract، `transitions.qbft` = [`blockheader` با ۵ آدرس در TT1، `contract` در TT2=TT1+900]. آخرین بلاک #150 با ts = TT1−3؛ تا TT2 هیچ بلاکی؛ همهٔ نودها `Invalid block header: Incorrect validators. Expected [۷ Registry] but got []`؛ ریستارت در توقف بی‌اثر؛ ۳۸۴ ثانیه پس از TT2 ادامه. کلید 100 در `blockheader` از ابتدا هیچ بلاکی نساخت.

## ۳. علت (از کد منبع Besu، شاخهٔ main — نه الزاماً عین 26.9.0؛ رفتار با آزمایش‌ها تأیید شد)
مسیرها در `besu-eth/besu` (https://github.com/besu-eth/besu):
- `consensus/qbft/.../validator/ForkingValidatorProvider.java`: `getValidatorsAfterBlock(parent)` فورک را با `(parent.number+1, parent.timestamp)` انتخاب می‌کند.
- `consensus/qbft/.../blockcreation/QbftBlockCreatorFactory.createExtraData`: حالت contract را هم با `parent.timestamp` تشخیص می‌دهد؛ در contract، `validators` و vote را **خالی** می‌نویسد.
- `consensus/qbft/.../QbftProtocolScheduleBuilder` + `BaseBftProtocolScheduleBuilder`: قاعدهٔ هدر (`QbftValidatorsValidationRule(useValidatorContract)`) بخشی از ProtocolSpec است که با timestamp **خود بلاک** انتخاب می‌شود (طراحی استاندارد Besu؛ رفتار مشاهده‌شده با آن می‌خواند). در `blockheader` قاعده می‌گوید `header.validators == getValidatorsAfterBlock(parent)` (پیام `Incorrect validators. Expected … but got …` از `BftValidatorsValidationRule`)؛ در contract می‌گوید باید خالی باشد.
- `ForkingVoteTallyCache.getValidatorsAfter` با `BftValidatorOverrides.getForBlock(nextBlockNumber)`؛ کلیدها در `QbftBesuControllerBuilder.convertBft­Forks` برابر `fork.getForkBlock()` یعنی همان عدد خام `block` (در Shanghai/Cancun یک timestamp) — هرگز با شمارهٔ بلاک برابر نمی‌شود.
- `ethereum/core/.../ProtocolScheduleBuilder`: modifier هر milestone همان آخرین کلید BFT با مقدار ≤ آن milestone است (`floor`) — منشأ مشکل e2.
- تفسیر `block` به‌عنوان timestamp در شبکهٔ time-based عمدی است (نگه‌دارندگان در https://github.com/besu-eth/besu/pull/10727 ، همچنین https://github.com/besu-eth/besu/issues/10878 ، https://github.com/besu-eth/besu/pull/10540 و https://github.com/besu-eth/besu/pull/11014 — دو مورد آخر بسته و merge‌نشده). موردی دربارهٔ این ناسازگاری contract↔blockheader با timestamp پیدا نشد.

نتیجه: نخستین بلاک با `ts ≥ TT1` (والد با ts<TT1) با `validators=[]` ساخته و با قاعدهٔ `blockheader` رد می‌شود؛ تا بلاکی با `ts ≥ TT2` (قاعدهٔ contract، فهرست خالی مجاز) پیشنهاد نشود زنجیره نمی‌ایستد/ادامه نمی‌دهد — و چون timeout دورها نمایی بالا می‌رود، ادامه با تأخیر می‌آید (دور ششم ۳۸۴ ث؛ e1 ما ۲۰۸ ث پس از TT2، بلاک #67 با فاصلهٔ ۵۰۹ ث). **بازگشت `blockheader`→`contract` با timestamp نیز همان ناسازگاری را وارونه دارد** (والد blockheader فهرست پر ساخته، قاعدهٔ contract می‌گوید خالی) — فقط در حالتی که قبلش توقف رخ داده بود دیده نشد؛ این بخش استدلال از کد است، آزموده نشده.

## ۴. آزمایش‌ها (هر پوشه: `genesis.json`، `config-n1.toml`، `spec.json`، لاگ‌های فیلترشده، مشاهدات)
۴ نود، `blockperiodseconds=2`، `requesttimeoutseconds=4`، قرارداد آزمایشی `getValidators()` (جایگزین Registry؛ فقط همین تابع را Besu صدا می‌زند) در `0x3333…`. «از دست دادن نصاب» = توقف n3,n4 از ۴ (نصاب ۳).

| # | پوشه | پیکربندی | انتظار | مشاهده |
|---|---|---|---|---|
| e1 | `e1-cancun0-…-repro` | Shanghai/Cancun=0؛ contract→blockheader(۴ آدرس)@TT1→contract@TT2؛ هر ۴ نود روشن | توقف مثل دور ۶ | **توقف**: آخرین #66 با ts=TT1−1؛ همان خط `Incorrect validators … but got []`؛ ادامه ۲۰۸ ث پس از TT2 |
| e2 | `e2-cancunG-block-key` | `shanghaiTime=cancunTime=ts ژنزیس` (نه ۰)؛ نصاب از دست رفته؛ blockheader(n1,n2) با کلید **شمارهٔ بلاک** H+1=157 | کار کند | **نودهای زنده ادامه دادند** (validators=[1,2]، #169…#226) **ولی نود تازه (volume پاک) از بلاک ۱ همگام نشد**: `Incorrect validators … got []` (بلاک ۱) — milestone تایم‌دار Cancun@G آخرین modifier را می‌گیرد |
| e3 | `e3-london-block-control` | London (بدون Shanghai)؛ blockheader@12 سپس contract@72 | کار کند (کنترل) | **کامل کار کرد**: بازیابی، پیوستن n3/n4، بازگشت؛ هر ۴ پیشنهاددهنده؛ نود تازه تا #482 همگام شد |
| e4 | `e4-cancun0-blockheader-keys` | Shanghai/Cancun=0؛ blockheader(n1,n2) با کلید **عدد کوچک H+1=14** | رفتار نامعلوم | نودهای زنده ادامه دادند (کلید ۱۴ هم timestamp گذشته است و هم تصادفاً شمارهٔ بلاک ⇒ override اعمال شد) **ولی نود تازه از بلاک ۱ رد شد**: `Block proposer is not a member of the validators … validators=[]` |
| e5 | `e5-cancun0-contract-to-contract-time-key` | Shanghai/Cancun=0؛ قرارداد standby در `0x4444…` (n1,n2)؛ گذار `contract`@ts(H)→`0x4444…`؛ بعد گذار `contract`@(+60 ث)→`0x3333…` | کار کند | **کامل کار کرد**: ادامه با [n1,n2]؛ n4 پیوست؛ **n3 با volume پاک تا #47 از genesis همگام شد**؛ پس از کلید بازگشت ۴ ولیدیتور و ۴ پیشنهاددهندهٔ چرخشی |
| e6 | `e6-cancun0-blockheader-timestamp-key` | blockheader(n1,n2) با کلید timestamp = ts(H) (گذشته) | فهرست اعمال شود؟ | **فهرست اعمال نشد**: `validators=[]`، زنجیره در #10 ایستاد (لاگ: دورهای ۳+، quorum=3) |
| e7 | `e7-cancun0-future-key-deadlock` | contract→standby با کلید **آینده** (+60 ث) پس از از دست رفتن نصاب | احتمالاً گیر | **ایستاد**: بلاک مرزی هنوز فهرست قدیم را (نصاب ۳ از ۴) لازم دارد؛ تا ۱۷۳ ث پس از کلید (آخرین مشاهده) ادامه نیافت |
| e8 | `e8-alloc-change-genesis-mismatch` | تغییر `alloc` در genesis (محتوای قرارداد standby) و ریستارت n1 | رد شود | **رد شد**: `Supplied genesis block does not match chain data` (n1 Exited 2) |

## ۵. روش بازیابی تأییدشده (e5) — برای genesis با `shanghaiTime=cancunTime=0`
پیش‌شرط: قراردادی با `getValidators()` در state با فهرست زندهٔ قابل‌نصاب (برای سور: مثلاً قرارداد «StandbyValidators» که از قبل مستقر و به‌روز نگه داشته شده؛ **باید پیش از بحران وجود داشته باشد**، e8).
۱. همهٔ نودهای بازمانده را متوقف کن؛ `H` = بزرگ‌ترین head میان آن‌ها (باید برابر باشد) و `ts(H)` را از هدر بخوان.
۲. تنها `config.transitions.qbft` را افزایش بده (alloc، extraData، بقیهٔ config دست‌نخورده؛ همان hash ژنزیس):
```json
{ "block": <ts(H)>, "validatorselectionmode": "contract",
  "validatorcontractaddress": "<STANDBY>" }
```
کلید **باید ≤ ts(H) باشد (در گذشته، نه آینده — برعکس هشدار رسمی که برای زنجیرهٔ زنده است)**؛ کلید آینده = بن‌بست (e7). کلید ≥ ts(H−1)+1 تا اعتبارسنجی تاریخچه سازگار بماند (آزموده: = ts(H)؛ ts(H−1)≥کلید آزموده نشد).
۳. genesis جدید را به همهٔ نودها بده، نودهای بازمانده را ریستارت کن؛ زنجیره با فهرست standby ادامه می‌دهد.
۴. نودهای دیگر را با همان genesis روشن کن (آزموده: دنباله‌رو شدند؛ نود با دیسک خالی هم همگام شد).
۵. بازگشت: وقتی نودهای Registry آنلاین و همگام‌اند، یک مدخل دیگر با کلید **آینده** (آزموده +60 ث) و `validatorcontractaddress` = Registry اضافه و همهٔ نودها را قبل از کلید ریستارت کن؛ بلاک مرزی را مجموعهٔ standby می‌سازد و پس از آن Registry (آزموده، ۴ پیشنهاددهنده). مدخل‌ها دائماً در genesis می‌مانند.

## ۶. بن‌بست‌ها و آنچه آزموده نشد
- `blockheader` با timestamp: در همهٔ شکل‌هایش (کلید آینده، کلید ≤ts(H)) یا ناسازگاری مرزی یا فهرست نادیده‌گرفته‌شده؛ استدلال کلی از کد؛ فقط e1/e6 مستقیماً آزموده شد.
- کلید شمارهٔ بلاک (e2/e4): «کار می‌کند» فقط برای نودهای زنده؛ **تاریخچه برای نود تازه یا بازسازی دیسک ناهمگام‌پذیر می‌شود** (snap/checkpoint sync با QBFT آزموده نشد). فقط به‌عنوان آخرین چاره تا re-genesis.
- آزموده نشد: Registry واقعی/genesis GenesisBuilder (امضای `getValidators()` در `contracts/ValidatorsRegistry.sol` هست)؛ قرارداد standby که با تراکنش بعداً مستقر شود (انتظار: همان رفتار)؛ ۷ ولیدیتور و شبکهٔ واقعی؛ build توسعهٔ `26.9-develop-260f602` و نسخه‌های دیگر؛ اختلاف head بازماندگان؛ دو بازیابی پیاپی؛ کلید ≤ ts(H−1)؛ نودی که genesis قدیم را نگه داشته؛ بازگشت `blockheader→contract` با timestamp در یک چرخهٔ کامل؛ re-genesis از snapshot state (ابزارش نوشته نشده).
- سرور آزمایش در دسترس نبود (بخش ۰).

## ۷. پیشنهاد تغییر (فقط پیشنهاد؛ سند و ابزار ویرایش نشد)
**`governance/sur-emergency-consensus-recovery.md`:**
1. بخش ۳: روش فنی را از `blockheader` به `contract→contract` (standby) تغییر بده؛ مثال JSON بخش ۵؛ بلوک «✅ London / ❌ Shanghai» را با علت (بخش ۳ این گزارش) به‌روز کن؛ `blockheader` را برای genesis دارای Shanghai/Cancun ممنوع اعلام کن.
2. هشدار «بلاک گذار نباید در گذشته باشد» را اصلاح کن: برای بازیابی، کلید باید = ts آخرین بلاک باشد؛ کلید آینده بن‌بست است.
3. تصمیم مالک لازم: **قرارداد standby** — مالک/به‌روزرسانی (همراه هر تغییر مجموعه در همان اقدام حاکمیتی)، چون هنگام بحران قابل ساخت نیست؛ تا وقتی در مدخل genesis نیاید اثری روی زنجیرهٔ سالم ندارد. این **تغییر قرارداد/ژنزیس تولید است** و باید پیش از mainnet تصمیم بگیرد (قرارداد جدید یا بهره از قرارداد موجود).
4. بخش ۴ (بازگشت): کلید آینده + ریستارت قبل از کلید.
**مشخصات ابزار بازیابی (بخش ۱۱ inventory):** گام ۶ را به مدخل `contract` با کلید خودکار = `ts(H)` تغییر بده؛ بررسی‌ها: head برابر بازماندگان؛ کلید در `(ts(H−1), ts(H)]` و بزرگ‌تر از کلیدهای قبلی؛ در آدرس standby کد هست و `getValidators()` زیرمجموعهٔ نودهای زنده با نصاب است؛ diff genesis فقط `transitions`؛ **رد هر مدخل `blockheader` وقتی `shanghaiTime/cancunTime` هست**؛ مدخل بازگشت فقط با کلید آینده؛ پس‌بررسی خودکار (head پیش می‌رود، `qbft_getValidatorsByBlockNumber`). تمرین دوره‌ای با `tools/lab.mjs`.
**پیشنهاد بالادستی (انجام نشد):** گزارش issue به Besu با e1/e6 (انتخاب فورک با timestamp بلاک والد برای provider/extraData ولی با timestamp خود بلاک برای قاعدهٔ هدر؛ override فقط با شمارهٔ بلاک).

## ۸. ابزار
`tools/lab.mjs` (gen/regen/up/stop/start/head/logs/down؛ فقط `sur25r-*`، RPC فقط 127.0.0.1، بدون pull)، `tools/specs/*`، `ToyValidators.sol` + runtime. آزمایش e1 پیش‌توقف/توقف‌خطی را `01/02` ندارد (فقط مشاهدات توقف و ادامه).
