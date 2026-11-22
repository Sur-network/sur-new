# رکورد به‌روزرسانی ValidatorApp به قراردادهای نهایی v2.5

**تاریخ:** ۲۰۲۶-۱۱-۲۲ — **شاخهٔ کد:** `Deployments` (branch `v2.5-dev`، هیچ‌چیز push نشده) — **پوشه:** `Deployments/ValidatorApp`
**مرجع قراردادها:** `Deployments/GenesisBuilder/contracts` (هش منبع‌ها در `SOURCES.json` همان کامیت `9a94fa5` از `Plan/contracts` است؛ ABI تولیدشده همین هش‌ها را در سرفایلش دارد).

## ۱. خلاصه

اپ ولیدیتور که یک‌بار از روی بریف ساخته شده و پس از آن دست نخورده بود، با قراردادهای نهایی v2.5 هم‌خوان نبود و **با آن‌ها کار نمی‌کرد** (مثلاً `requestMembership()` بدون آرگومان، `getValidatorInfo` با شش خروجی دیگر، حالت‌های `RemovedInRecovery` و `SelfSuspended` ناشناخته). اکنون ABI از خودِ سولیدیتی تولید می‌شود، همهٔ ۷ حالت و رفتارهای نهایی روی صفحه‌ها هستند و جریان‌های اصلی روی **قراردادهای واقعی و نهایی** (anvil، genesis ساخته‌شده با CLI خود GenesisBuilder) از همان مسیر امضای اپ آزموده شده‌اند.

یک یافتهٔ فرعی: کامیت اول `src/lib/*` را اصلاً نداشت، چون `.gitignore` ریشهٔ `Deployments` الگوی `lib/` (برای پایتون) را دارد و فایل‌ها ردیابی نشده بودند. با `!/src/lib/` در `.gitignore` خودِ ValidatorApp درست شد و همهٔ فایل‌های `src/lib` اکنون در گیت هستند.

## ۲. چه چیزی عوض شد

### ناهمخوانی‌های ABI که اصلاح شد
| فرض اپ قدیمی | قرارداد نهایی |
|---|---|
| `requestMembership()` بدون آرگومان | `requestMembership(address operator)` |
| `getValidatorInfo` → status، lockedStake، periodStartedAt، lastLivenessConfirmation، livenessConfirmationsInPeriod، demotedAt | status، lockedStake، periodStartedAt، **demotedAt، pendingSlashEpoch، isPaidEntrant** (liveness آف‌چین است) |
| `enum Status` با ۵ مقدار | ۷ مقدار: + `RemovedInRecovery`، `SelfSuspended` |
| `currentEntryThreshold` با منحنی رشد | وثیقهٔ ثابت `entryCollateral` (تابع `currentEntryThreshold` هنوز هست و همان را می‌دهد) |
| وضعیت نود فقط nodeID در Verifier | کلید نود روی قرارداد (`operatorOf`، `pendingOperator`، `pendingOperatorExpiresAt`)، تعویض دومرحله‌ای |
| پاداش: رویداد/نگاشت per-epoch | توزیع صفحه‌ای؛ فقط رویداد؛ `claimable` + `claim()` |
| ورود با هر آدرس | فقط EOA (RD-12) |

### صفحه‌ها
`/status` (بازنویسی)، `/join` (بازنویسی: ورودی کلید نود، شرط‌ها پیش از پرداخت)، `/node` (بازنویسی: دومرحله‌ای)، `/exit` (بازنویسی: حذف در بازسازی، برداشت با پرونده)، و **جدید:** `/suspend`، `/rewards`، `/seat`، `/lottery`، `/verify` (فقط‌خواندنی)، بنر کلیدهای منجمد در همهٔ صفحه‌ها، FAQ بازنویسی. حذف: `/register`، `OtpPanel`، کش امضا در `sessionStorage`.

### هفت رفتار خواسته‌شده
1. **EOA (RD-12):** بررسی `getCode` پیش از پرداخت؛ متن فارسی ریورت در ورود، بلیت قرعه‌کشی و انتقال NFT. (آزموده: ورود، انتقال صندلی، بلیت.)
2. **تعویض دومرحله‌ای (VD-13):** pending / منقضی (۷ روز) / تأییدشده با هش شواهد (از `OperatorChangeConfirmed`) / لغوشده؛ متن «تصمیم با Verifier است». آزموده با تأیید واقعی Verifier، و رد `confirmOperatorReady` برای کلید متفاوت و برای پیشنهاد منقضی.
3. **VD-4:** `RemovedInRecovery` ← اعتراض ← پایان مهلت ← `expireRecoveryRemoval` ← `SelfSuspended` با `resumeRequested = true` و `RecoveryRemovalCancelled`؛ فقط `recordResume` فعال می‌کند. منشأ تعلیق (داوطلبانه یا VD-4) از ترتیب رویدادها.
4. **توزیع صفحه‌ای:** تاریخچه از `ValidatorRewarded`، `ValidatorRewardDeferred`، `DistributionPage`، `RewardsDistributed` (فقط هنگام بستن)، `DistributionAborted`، `ClaimableWithdrawn`؛ وضعیت هر توزیع باز/بسته/لغو؛ پیشرفت توزیع باز از `openDistributionInfo`. نگاشت‌های حذف‌شده و `getValidatorEpochReward` در ABI نیستند و آزمونی هست که نبودنشان را قفل می‌کند.
5. **پرداخت معوق:** `claimable`، دکمهٔ `claim()`، سطر «به claimable واریز شد (ValidatorRewardDeferred)»، توضیح برای مالک دارای کد.
6. **KmsDirectives:** بنر فقط‌خواندنی با اثر هر کلید منجمد.
7. دورهٔ آزمایشی/صندلی/قرعه‌کشی/کارمزد عضویت مطابق قرارداد نهایی؛ چک‌های ورود (هویت، سابقهٔ خروج، ظرفیت هفتگی).

### موارد فنی
- `scripts/gen-abi.mjs` (solc 0.8.24) ← `src/lib/abi/generated.ts`؛ `abi:check` در آزمون‌ها.
- `txCalls.ts`: شبیه‌سازی پیش از امضا؛ **سقف گاز صریح** برای فراخوان‌هایی که به `_notifyBoard` می‌رسند (دلیل: همان که Verifier ۴٬۰۰۰٬۰۰۰ می‌فرستد؛ برآورد کیف‌پول ممکن است درست زیر نیاز فراخوان سقف‌دار هیئت بیفتد).
- زمان همهٔ مهلت‌ها از **ساعت زنجیره** (آخرین بلاک) است، نه مرورگر.
- چالش Verifier یک‌بار مصرف است؛ اپ دیگر امضا را کش نمی‌کند.
- `tsconfig target` به ES2020 (لازم برای BigInt)؛ `layout.tsx` دیگر به نوع سراسری تولیدشدهٔ `LayoutProps` وابسته نیست.

## ۳. نتایج اجرا (واقعی، همین جلسه)

| بررسی | نتیجه |
|---|---|
| `eslint` | ۰ خطا، ۰ هشدار |
| `tsc --noEmit` | بدون خطا |
| `vitest run` | **۷ فایل، ۷۳ آزمون، همه سبز** |
| `next build` (Turbopack) | موفق؛ ۱۲ مسیر استاتیک (`/ /exit /faq /join /lottery /node /rewards /seat /status /suspend /verify /_not-found`) |

تفکیک ۷۳ آزمون: **anvil روی قراردادهای نهایی: ۱۶** (`entry` ۵، `operator` ۶، `rewards` ۳، `misc` ۲)، **واحد: ۲۶** (`contracts` ۹، `model` ۱۷)، **jsdom برای هر صفحه: ۳۱**.
آزمون‌های anvil: ورود EOA، رد قرارداد (ورود/انتقال NFT/بلیت)، سقف ورود هفتگی، هویت ناکامل، مبلغ غلط، انتقال صندلی و `acceptSeatTransfer`، دومرحله‌ای کامل با تأیید Verifier، انقضا و لغو، `setOperator` فوری برای `Probation`، VD-4 کامل تا `recordResume`، تعلیق داوطلبانه و ازسرگیری، خروج و برداشت، توزیع صفحه‌ای ۲ صفحه‌ای تا بستن، لغو پس از ۳ روز، `claim()` برای مالک دارای کد، بنر انجماد، قرعه‌کشی.

## ۴. ناهمخوانی بریف با قراردادها (قرارداد برنده شد)

| بریف / نسخهٔ اول | قرارداد | عمل |
|---|---|---|
| §۵.۱ «`requestMembership()` بدون آرگومان» | `requestMembership(address operator)` | اپ کلید نود را می‌گیرد (بقیهٔ بریف خودش مالک/اپراتور را درست می‌گوید؛ فقط این بند کهنه است) |
| بریف §۳.۲ و §۴: اپ OTP تلفن/تلگرام/بله/ایمیل را به Verifier/سرویس هویت می‌زند | Verifier مسیر OTP ندارد (حالت ب، VD-1؛ `server.ts` فقط `challenge`، `register`، `node-id`، `node-check-key`، `status`، `notifications`) | OTP پیاده نشد؛ `/verify` پرچم‌ها را از زنجیره می‌خواند و به اپ هویت لینک می‌دهد (`NEXT_PUBLIC_IDENTITY_APP_URL`) |
| سرویس هویت (`IdentityRegistry/src`) | مسیرهایش از قرارداد مشخصات هم فرق دارد (`?address=` به‌جای `?ethAddress=`، `destination`) | یک ناهمخوانی میان IdentityApp و Verifier-spec است، نه این اپ؛ همین دلیل دیگر برای نساختن OTP در این اپ |
| ثبت‌نام اولیه `POST /register` با phone/telegram | `register` فقط `{ethAddress, signature, nodeId}` و فقط برای آدرس دارای صندلی (۴۰۹ `NOT_A_VALIDATOR`) | `/register` حذف؛ nodeID در `/node` |
| پاسخ `status`: `phoneVerified، telegramVerified، lastLivenessConfirmation، isCurrentlyLive` | + `baleVerified، emailVerified، kycVerified، nodeIdRegistered، waitingFor`؛ `isCurrentlyLive` ممکن است `null` باشد | تایپ و UI به‌روز؛ `null` = نامشخص، نه شکست |
| بریف: بنر هیئت، رأی هیئت، وضعیت «امضای توافق‌نامه» | وضعیت امضا روی زنجیره نیست؛ صفحهٔ هیئت در این اپ نیست (داشبورد حکمرانی) | فقط: هشدار عضو هیئت هنگام خروج و منع تعلیق داوطلبانهٔ عضو هیئت |
| `ValidatorStatus` ۵ مقدار | ۷ مقدار | به‌روز |

## ۵. آنچه آزموده **نشده** است

- **Besu زنده و سرور اوبونتو 192.168.1.210:** خارج از دامنه بود؛ چیزی روی آن اجرا یا لمس نشد. همهٔ آزمون‌های زنجیره روی anvil محلی‌اند (EVM واقعی، بایت‌کد و حالت اولیهٔ GenesisBuilder، نه Besu).
- **مرورگر و کیف‌پول واقعی (Reown/AppKit):** اپ در مرورگر اجرا نشد؛ مسیر امضای آزمون با اتصال‌دهندهٔ `mock` wagmi است. صفحه‌های `app/*/page.tsx` و هوک‌های `useChain` فقط تایپ‌چک و بیلد شده‌اند؛ نمای‌ها (screens) با jsdom و منطق با anvil آزموده شده‌اند، اما خودِ ترکیب «هوک ← نما» در مرورگر دیده نشده.
- **API واقعی Verifier:** کلاینت فقط با fetch ساختگی که از روی `Verifier/src/api/server.ts` نوشته شد آزموده شده؛ فراخوان امضاشدهٔ واقعی (چالش ← امضا ← `PUT /node-id`، `node-check-key`) و `notifications` (اپ هنوز صفحه‌ای برایش ندارد) آزموده نشد.
- **`claim()`:** در آزمون، کد آدرس پیش از `claim` برداشته شد تا کلید آزمون بتواند امضا کند؛ برداشت توسط یک کیف‌پول قراردادیِ واقعی آزموده نشد. همچنین رد «تراکنش از طریق قرارداد با `tx.origin` متفاوت» آزموده نشد، فقط فرستندهٔ دارای کد.
- **انجماد:** پرچم با نوشتن مستقیم در storage تنظیم شد (فراخوان `setFrozen` فقط هیئت/بنیاد است)؛ مسیر رأی هیئت (`KmsFreeze`) آزموده نشد.
- **سقف گاز ۳٬۰۰۰٬۰۰۰ در `txCalls`:** منطقش از مستندات Verifier گرفته شده؛ سناریوی «برآورد کیف‌پول زیر آستانه» آزموده نشد.
- **ورود پولی تا فعال‌سازی:** فعال‌سازی ورودی پرداخت‌کننده (۱ هفته + معیار موفقیت ۹۵٪ سمت Verifier) آزموده نشد؛ فقط مؤسس‌ها با `recordActivation` فعال شدند. برندهٔ قرعه‌کشی (`drawBatch`، commit–reveal) آزموده نشد؛ فقط خرید بلیت و رد EOA.
- **`eth_getLogs` روی RPC عمومی Besu:** برش بازه‌ای (`LOG_CHUNK`) آزموده نشد؛ برای تاریخچهٔ طولانی نود با ایندکس لاگ لازم است (در README نوشته شده).
- موارد بریف که پیاده نشد: OTP چهارگانه، نمایش وضعیت امضای توافق‌نامه، صفحهٔ هیئت، مرکز اعلان‌ها (`/api/v1/notifications`).

## ۶. فایل‌ها

کد: `Deployments/ValidatorApp` (`src/lib`, `src/components/screens`, `src/hooks`, `src/app`, `scripts/gen-abi.mjs`, `test/`)، README فارسی و انگلیسی (`README.fa.md`، `README.md`)، `.env.local.example`. کامیت‌ها با مسیر صریح، بدون push.
