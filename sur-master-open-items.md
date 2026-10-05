# فهرست جامع موارد باز — پروژه‌ی سور

> فقط آنچه **هنوز باز است**. تصمیم‌های گرفته‌شده، اصلاحات انجام‌شده و روایت زمانی در `sur-progress-and-decisions-history.md` و `sur-final-decisions-2026-09-28.md` آمده است. هر ردیف به سند مبدأ ارجاع می‌دهد.
>
> این فهرست از نسخه‌ی پیشین (`_archive/sur-master-open-items-2026-10-03.md`) استخراج شده است. بخش ۸ همین سند فهرست مواردی است که وضعیتشان در نسخه‌ی پیشین پیش از دور چهارم آزمون Besu ثبت شده و باید دوباره راستی‌آزمایی شوند.

## ۱. تصمیم‌های لازم از مالک

| مورد | سند مبدأ |
|---|---|
| اعداد قاعده‌نامه‌ی `c01-rules-v1` (تعریف «بررسی موفق» و «نامشخص»؛ پیشنهادی‌اند و پیش از راه‌اندازی باید تأیید شوند) | `offchain-services/sur-verifier-service-spec.md` بخش ۶.۷ |
| هویت ۷ مسئول بازیابی اضطراری (N04) و مهلت بازپیوستن پس از بازگشت از حالت اضطراری (پیش‌فرض: هیچ) | `governance/sur-emergency-consensus-recovery.md` |
| مرجع تصمیم، نصاب قابل‌اجرا، شواهد فقدان نود، وضعیت وثیقه و حق بازگشت برای ولیدیتور همیشه‌مفقود (طراحی محض، بدون کد) | `governance/sur-emergency-consensus-recovery.md` §۴ |
| الزام حضور فیزیکی نود در ایران: آیا پیامد فوری لازم است یا مسیر پایش آف‌چین (تأخیر حدود ۱ ساعت) کافی است؟ | `economics/sur-tokenomics.md` بخش ۶.۷، `offchain-services/sur-verifier-service-spec.md` بخش ۶.۵ |
| مبلغ کل و فهرست آدرس‌به‌آدرس ردیف «جبران ولیدیتورهای شبکه‌ی قبلی»، و به‌روزرسانی جدول پیش‌بینی عرضه پس از مشخص‌شدن مبلغ | `economics/sur-tokenomics.md` |
| تولید یا نتولید `transitions.qbft` در ابزار genesis | `offchain-services/sur-genesis-builder-tool-spec.md` بخش ۱۰ |
| سرنوشت انتقال‌های مستقیم به distributor و منظور از بازگشت کارمزد تراکنش توزیع به epoch بعدی | `technical-design/sur-audit-2026-09-30-final-status.md`؛ QUESTIONS بسته‌ی v4 |
| بودجه‌ی کمپین بنیاد: برآورد ۳۹ تا ۶۵ میلیون سورن در برابر ۲۰ میلیون؛ هیچ مسیر رسمی روی زنجیره برای آن وجود ندارد | `sur-detailed-plan-and-rationale.md` بخش ۱۳.۳ |
| زمان و روش درخواست بودجه‌ی تکمیلی بنیاد؛ منبع بودجه‌ی حسابرسی امنیتی؛ اجرای برنامه‌ی جایزه‌ی باگ | `economics/sur-tokenomics.md`، `business/sur-marketing-roadmap.md`، `technical-design/sur-security-audit-plan.md` |
| اسامی افراد چرخه‌ی on-call و پیجینگ (Verifier و RewardRouter) | `offchain-services/sur-verifier-service-spec.md` |

## ۲. سرویس‌دهنده‌های خارجی — انتخاب نشده‌اند

| مورد | سند مبدأ |
|---|---|
| سرویس‌دهنده‌ی eKYC (RFP آماده است) | `offchain-services/sur-ekyc-rfp.md`، `offchain-services/sur-identity-registry-spec.md` |
| سرویس‌دهنده‌ی پیامک/تلگرام برای OTP | `offchain-services/sur-verifier-service-spec.md` |
| درگاه پرداخت `SurenSale` (زرین‌پال یا جایگزین) | `offchain-services/sur-suren-sale-spec.md` |
| شرکت یا تیم حسابرسی امنیتی قراردادها | `technical-design/sur-security-audit-plan.md` |
| مبلغ و تناوب تأمین موجودی قرارداد فروش؛ مسیر جبران پرداخت بدون دریافت سورن | `offchain-services/sur-suren-sale-spec.md` |

## ۳. پیاده‌سازی — نوشته نشده

| مورد | سند مبدأ |
|---|---|
| RewardRouter (شامل بازه‌ی P05 و تعیین بازه‌ها) | `offchain-services/sur-reward-router-spec.md` |
| Verifier (شامل `c01-rules-v1`، `recordPreExitViolation`، `syncBoard`/`refreshBoard(address[])`) | `offchain-services/sur-verifier-service-spec.md` |
| ابزار ساخت `genesis.json` تولیدی — T02 (مشخصات کامل؛ اجرا و تست `--verify` روی Besu واقعی وجود ندارد). **شامل الزام موجود:** نوشتن `boardMonthId` = ماه میلادی زمان genesis و `boardVersion` = ۱ وقتی هیأت seed می‌شود، و ترتیب `activationSeq` مؤسسان، و assert آن‌ها (مشخصات بند ۴.۲.۱)؛ این تصمیم باز نیست. دور پنجم Besu روی نسخهٔ ۲.۱.۰ هنوز اجرا نشده و باید این مقدارها را روی شبکهٔ تازه تأیید کند | `offchain-services/sur-genesis-builder-tool-spec.md`؛ `testing-evidence/besu-live-test-v4-2026-10-03/FINDINGS.md` مورد ۲۲ |
| Identity Service، PaymentReporter، اپ ولیدیتور، داشبورد حکمرانی، پرتال فروش | `offchain-services/sur-software-inventory.md` |
| ابزار بازیابی اضطراری | `governance/sur-emergency-consensus-recovery.md` |
| سرویس همراه نود برای `SUR_NODE_CHECK_V1` (فقط مشخصات) | `offchain-services/sur-node-check-protocol-spec.md` |
| صفحه‌ی حکمرانی نرخ پاداش در داشبورد | `offchain-services/sur-governance-dashboard-claudecode-brief.md` |

## ۴. جزئیات فنی باقی‌مانده

| مورد | سند مبدأ |
|---|---|
| مقدار تولیدی `gasLimit` شبکه؛ هزینه‌ی توزیع باید با آن تطبیق داده شود | `technical-design/sur-audit-2026-09-30-final-status.md` |
| مسیر رفع «پاداش واقعی بیش از سقف» برای بازه‌ی گذشته (مسیر دورزدن اضطراری وجود ندارد) | `offchain-services/sur-reward-router-spec.md` |
| طراحی هشدار «پاداش واقعی کمتر از نرخ مصوب» (قرارداد آن را نمی‌بیند) | `offchain-services/sur-reward-router-spec.md` بخش ۱۰.۲ و ۱۰.۴ |
| رویه‌ی اپراتوری هماهنگی transition پاداش در همه‌ی نودها و نودهای تازه‌وارد؛ مسئول بررسی | `offchain-services/sur-reward-router-spec.md` بخش ۱۰.۳ و ۱۰.۴ |
| داده‌های تاریخی Router: نود archive/FOREST یا جمع‌آوری لحظه‌ای (Besu بیرون از پنجره‌ی حدود ۵۱۲ بلاک `null`/`[]` بی‌خطا برمی‌گرداند) | `offchain-services/sur-reward-router-spec.md` بخش ۱۰.۴ |
| مقدار و روش تأمین موجودی گس اوراکل و هشدار موجودی کم (یک بار تراکنش با موجودی ناکافی بی‌صدا pending ماند) | `offchain-services/sur-reward-router-spec.md` بخش ۱۰.۴، `technical-design/sur-contracts-oracles-accounts-report.md` |
| توصیه‌ی heap و هشدار «نود روی ارتفاع N گیر کرده» برای نود با genesis ناهماهنگ | `technical-design/sur-contracts-deploy-notes.md` |
| نصاب دوسوم برای چرخش `paymentOracle` در `SurenSale` اگر مبالغ بزرگ‌تر شود | `offchain-services/sur-suren-sale-spec.md` |
| مدت نگهداری داده‌ی خام KYC؛ بازبینی دستی برای بازیابی هویت پرریسک | `offchain-services/sur-identity-registry-spec.md` |
| بازیابی هویت: مسیر بلندمدت «انتقال هماهنگ عضویت ولیدیتور» برای کلید گم‌شده؛ هیچ مکانیزم on-chain ابطال کلید در معرض خطر (کلید سرقت‌شده) وجود ندارد | `offchain-services/sur-identity-registry-spec.md` |
| پیش‌شرط ایمنی فعال‌سازی: ولیدیتور بدون نود واقعی می‌تواند اجماع را قفل کند؛ باید در Verifier پیاده شود | `offchain-services/sur-verifier-service-spec.md` |

## ۵. آزمون

| مورد | وضعیت | مرجع |
|---|---|---|
| اجرای ترکیبی زمان واقعی مسیر L (مرحله‌ی L4: پیشنهاد، تأخیر واقعی ۷ روزه، اجرا، ۲۰۱٬۶۰۰ بلاک، عبور از `startBlock`، تسویه) | اجرا نشده (حدود ۱۴ روز)؛ برنامه نوشته شده و منتظر مجوز جداگانه‌ی مالک است | `testing-evidence/besu-live-test-v4-2026-10-03/PLAN-path-L-real-time.md` |
| عملکرد نود و شبکه‌ی چندمیزبان | همه‌ی آزمون‌ها تک‌میزبان بودند | `testing-evidence/besu-live-test-v4-2026-10-03/LIMITATIONS.md` |
| ثابت‌های زمانی واقعی (۲۳ ساعت، ۱۸۰ روز، ۷ روز، ۲۰۱٬۶۰۰ بلاک، ۳۰ روز) | فقط روی fork آزمایشی فشرده‌شده آزموده شدند | همان |
| مسیر تحویل/اعتراض و `resolveDeliveryDisputeIfExpired` در بریف‌های UI و گام Verifier | باز | بریف‌های `offchain-services/*-claudecode-brief.md` و `offchain-services/sur-verifier-service-spec.md` |

## ۶. حقوقی و کسب‌وکار

| مورد | سند مبدأ |
|---|---|
| تنش حقوقی: ماده‌ی ۳۱ اساسنامه (تقسیم سود بین شرکا) با ماهیت غیرتجاری بنیاد (ماده‌ی ۲)؛ نیازمند وکیل مستقل. همچنین کدام مکانیزم‌های درآمدی «تجارت» محسوب می‌شوند | `governance/sur-organizational-structure.md`، `business/sur-whitepaper.md` فصل ۱۲ |
| سپیدنامه: تاریخ‌های دقیق نقشه‌ی راه (فصل ۱۰)؛ بیوگرافی تفصیلی اعضای تیم (فصل ۱۱)؛ منابع و راه ارتباطی (فصل ۱۳، خالی)؛ کاربردهای سورن فراتر از فی و وثیقه | `business/sur-whitepaper.md` |
| منوی «مزیت‌ها و خدمات» سایت: کدام ایده‌ها در فاز اول نمایش داده شوند | `business/sur-website-sitemap-proposal.md` |
| تصمیم اجرای تراکنش‌های محرمانه (Zether): انتخاب و فورک پیاده‌سازی آدیت‌شده‌ی `IZetherVerifier` (پیشنهاد: `ConsenSys/anonymous-zether`، هنوز فورک و آدیت نشده)؛ سازگاری منحنی/precompile؛ بازبینی امنیتی مستقل پیش از هر دیپلوی؛ احتمال تجاوز دیپلوی از سقف گس یک بلاک؛ تعارض با الزامات AML/KYC؛ گس بالای تراکنش‌ها | `offchain-services/sur-zether-confidential-transfers-proposal.md` |
| تصمیم اجرای بازی‌های بلاک‌چینی (اختیاری، اولویت پایین) | `offchain-services/sur-blockchain-games-proposal.md` |
| فاز اعتبارسنجی اکوسیستم (۸ تا ۱۲ هفته، یک Owner از نیروی فعلی) هنوز شروع نشده | `business/sur-dapp-business-ideas.md` |
| ایده‌های اولویت‌دار: نیازمند طراحی از پایه (داوری و حل اختلاف عمومی، Oracle بومی قیمت، لایه‌ی اعتبار) و تصمیم عملیاتی بنیاد (ابزار و مستندات فارسی) | `business/sur-dapp-business-ideas.md` |

## ۷. ریسک‌های عمومی صنعت — پوشش صریح در اسناد لازم است

| ریسک | سند مرتبط |
|---|---|
| تمرکز شبکه از اقتصاد ولیدیتور (مانع واقعی هزینه‌ی سرمایه‌ی وثیقه است، نه سخت‌افزار؛ راه‌حل مشخصی نوشته نشده) | `economics/sur-tokenomics.md` |
| ریسک نقدینگی راه‌اندازی DEX (خروج نقدینگی‌دهندگان اولیه، slippage بالا) | `technical-design/sur-dex-launch-plan.md` |
| تبانی یک‌سوم در multisig پل ارتباطی (آستانه‌ی تبانی یا لورفتن کلید نگهبانان) | `technical-design/sur-bridge-risk-analysis.md` |
| تعارض Zether با AML/KYC و گس بالای تراکنش‌های Zether (وابسته به تصمیم اجرای Zether) | `offchain-services/sur-zether-usage-guide.md` |

## ۸. موارد با وضعیت احتمالاً کهنه — راستی‌آزمایی لازم

این موارد در نسخه‌ی پیشین فهرست پیش از دور چهارم آزمون Besu یا پیش از چند اصلاح بعدی ثبت شده بودند و وضعیت جاری‌شان ثابت نشده است:

| مورد | مرجع |
|---|---|
| آیا نصاب‌های داخلی هیأت‌مدیره‌ی ولیدیتورها برای اختیارات حساس‌تر باید بالاتر از اکثریت ساده باشد | `governance/sur-organizational-structure.md` |
| راستی‌آزمایی `expected_turns` (انتخاب پیشنهاددهنده) روی نسخه‌ی دقیق Besu | `offchain-services/sur-verifier-service-spec.md` |
| پوشش آزمون خودکار برای `FoundationDAO`، `IdentityRegistry`، `ServiceStaking`، `SurenSale` (آزمون Besu آن‌ها را پوشش داده، آزمون Hardhat ندارد) | `testing-evidence/hardhat-regression/` |
| نیاز به بازبینی `sur-contracts-ui-review.md` و `business/sur-dapp-business-ideas.md` برای تصمیم‌های بعد از ۲۸ سپتامبر؛ احتمال ارجاع باقی‌مانده به مدل قدیمی | همان دو سند |
| نبود سند `offchain-services/sur-identity-app-claudecode-brief.md` در پوشه، با این‌که قبلاً به آن ارجاع داده شده است | — |
| بازیابی سقوط زیر نصاب BFT و اثر مالی واقعی جریمه روی عضو پرداخت‌کننده (در دور اول آزموده نشده بود) | `_archive/sur-master-open-items-2026-10-03.md` بخش ۲۴ |
| سناریوهای خروج بدون پرونده و تساوی رأی هیأت به‌صورت مورد جدا (در دور دوم اجرا نشده بودند؛ کم‌ریسک) | `testing-evidence/besu-live-test-v2-2026-09-28/` |
| فرایند امضای ۵ از ۷ مسئولان بازیابی هیچ کدی برای آزمودن ندارد | `governance/sur-emergency-consensus-recovery.md` |

## اولویت‌بندی پیشنهادی
1. **قبل از هرچیز:** تصمیم‌های بخش ۱ (اعداد `c01-rules-v1`، N04، `gasLimit`)، چون حسابرسی امنیتی باید روی کد نهایی انجام شود؛ پیش‌شرط ایمنی فعال‌سازی پیش از نوشتن Verifier.
2. **موازی با حسابرسی:** انتخاب سرویس‌دهنده‌های خارجی (بخش ۲) و پیاده‌سازی Router/Verifier/ابزار genesis (بخش ۳).
3. **بعداً:** محتوای باقی‌مانده‌ی سپیدنامه، Zether و بازی‌ها (بخش ۶)؛ برای انتشار عمومی و رشد اکوسیستم لازم‌اند، نه برای راه‌اندازی فنی.
