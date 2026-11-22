# طرح جدید بلاک‌چین سور

> راهنمای استفاده از این مخزن — برای هرکسی (انسان یا نمونه‌ی دیگری از Claude) که برای اولین بار وارد این پوشه می‌شود.

این پوشه شامل تمام مستندات فنی، حکمرانی، اقتصادی، و بازاریابی بازطراحی کامل بلاک‌چین سور است — یک بلاک‌چین خصوصی/کنسرسیومی بر پایه‌ی Hyperledger Besu با اجماع QBFT، با ارز بومی «سورن». این پروژه جایگزین کامل یک شبکه‌ی قبلی با همین نام است که راه‌اندازی و بعداً متوقف شده بود.

---

## از کجا شروع کنم؟

بسته به این‌که چه نقشی دارید، یکی از این‌ها را اول بخوانید:

| اگر... | این سند را بخوانید |
|---|---|
| می‌خواهید یک نگاه کلی و روایی به کل پروژه داشته باشید | `sur-comprehensive-project-document.md` |
| می‌خواهید بدانید در مورد چه موضوع‌هایی هنوز تصمیم‌گیری نشده است | `sur-master-open-items.md` |
| می‌خواهید کار را با کمک هوش مصنوعی (Claude) ادامه بدهید | `sur-project-handoff-summary.md` |
| فقط سپیدنامه‌ی عمومی پروژه را می‌خواهید | `business/sur-whitepaper.md` |
| توسعه‌دهنده‌اید و می‌خواهید قراردادها را ببینید | `contracts/` (کامنت‌ها انگلیسی) یا `contracts-fa/` (همان کد، کامنت‌های فارسی) |

---

## ساختار پوشه‌ها

### `contracts/` و `contracts-fa/`
قراردادهای اصلی Solidity — دقیقاً یک کد، دو نسخه: `contracts/` با کامنت انگلیسی (منبع صحت برای دیپلوی)، `contracts-fa/` همان فایل‌ها با کامنت فارسی (برای خواندن راحت‌تر). طرح نسخهٔ ۲.۵ دوازده قرارداد ساختاری genesis دارد (بدون `constructor`، مستقیم در بلاک آغازین تزریق می‌شوند): شش قرارداد پایه (`FoundationDAO`، `BlockRewardDistributor`، `ValidatorsRegistry`، `ValidatorsBoard`، `ValidatorsTreasury`، `IdentityRegistry`) و شش قرارداد تازه (`FoundationMembers`، `ValidatorSeatNFT`، `GenesisClaimsVault`، `ValidatorLottery`، `KmsDirectives`، `StandbyValidators` — فهرست آمادهٔ بازیابی اضطراری)؛ `SurenSale.sol` تنها قرارداد با دیپلوی معمولی است. هر دو پوشه **فقط نسخهٔ جاری** را نگه می‌دارند؛ نسخه‌های قدیمی‌تر در git هستند ([برچسب `v2.2.0`](https://github.com/Sur-network/sur-new/releases/tag/v2.2.0)). وضعیت کد (۲۰۲۶-۱۱-۱۹): از ۲.۵ نوشته شده‌اند `FoundationDAO` (۱۴ نوع پیشنهاد از جمله نوع آزاد و آشکار `Execute` و `EndSale`؛ مجمع، انتخابات)، `FoundationMembers`، `SurenSale` (مدل صرافی، بدون اوراکل پرداخت)، `ValidatorLottery`، `GenesisClaimsVault` (صندوق طلب‌ها؛ ۲۴ قسط ماهانه، با کمکی seed)، حذف ولیدیتور در بازیابی شبکه (`ValidatorsRegistry` و `ValidatorsBoard`)، تغییرات `IdentityRegistry`، `ValidatorSeatNFT` (صندلی ERC-721)، هستهٔ بازطراحی `ValidatorsRegistry`/`ValidatorsBoard` (وثیقهٔ ثابت ۵۰۰٬۰۰۰ سورن، کلید مالک/اپراتور با تعویض دومرحلهٔ کلید نود برای ولیدیتور `Active` (`proposeOperator` سپس تأیید Verifier با `confirmOperatorReady`؛ `setOperator` فقط بیرون از مجموعهٔ اجماع فوری است)، جریان مؤسسان، `SelfSuspended`، سوزاندن ۱۰۰٪ جریمه، قواعد فاصلهٔ ورود) و سوزاندن مازاد پاداش در `BlockRewardDistributor`؛ کنار آن‌ها `BlockRewardDistributor`، `ValidatorsTreasury`، `ServiceStaking` (قرارداد استیک سرویس‌ها، خارج از دوازده قرارداد ساختاری) و `SurAddresses` هستند. [به‌روزرسانی ۲۰۲۶-۱۱-۲۲: RewardRouter، Verifier، SurKMS، Identity Service، ابزار genesis، NodeCheck و چهار رابط اکنون ساخته و آزموده شده‌اند؛ آزمون Besu دو دور انجام شد؛ جزئیات: `offchain-services/sur-software-inventory.md`.] هنوز نوشته نشده‌اند (متن قدیمی): `RewardRouter` (سرویس آف‌چین، نه قرارداد) و حدود تغییر ریوارد (±۱۰٪، ۶ ماه فاصله) در `proposeRateChange`؛ ابزار genesis و سرویس‌های Verifier/Identity هم نوشته نشده‌اند.

زیرپوشه‌ی `genesis-seed-helpers/`: پنج قرارداد کمکیِ **موقت** (`FoundationDAO_GenesisSeed`، `FoundationMembers_GenesisSeed`، `ValidatorsRegistry_GenesisSeed`، `ValidatorsBoard_GenesisSeed`، `GenesisClaimsVault_GenesisSeed`) فقط برای محاسبه‌ی مقادیر اولیه‌ی genesis (لیست اعضا، ولیدیتورها، طلبکاران) روی یک شبکه‌ی محلی — بخشی از شبکه‌ی نهایی نیستند. هر کدام از قرارداد اصلی **ارث می‌برد** (چینش storage بنا به ساخت یکسان) و داده را از آرگومان‌های constructor می‌گیرد.

### `contracts-tests/`
آزمون‌های محلی Hardhat (2.29.1، solc 0.8.24، `evmVersion` paris) برای قراردادهای ۲.۵ در `contracts/`: ۹۷ آزمون در ۱۰ فایل (`BlockRewardDistributor` ۴، `FoundationDAO` ۱۶، `GenesisClaimsVault` ۵، `IdentityRegistry` ۵، `LotteryRegistry` ۳، `RecoveryRemoval` ۱۲، `SurenSale` ۱۱، `ValidatorLottery` ۱۰، `ValidatorSeatNFT` ۱۱، `ValidatorsRegistry` ۲۰)؛ اجرا: `npm install` و سپس `npm test` (هر فایل در فرایند جدا)؛ mockها در `contracts-tests/mocks`. ⚠️ این آزمون‌ها روی EVM درون‌فرایندی Hardhat اجرا می‌شوند، **نه Besu/QBFT**؛ آزمون زندهٔ Besu برای ۲.۵ جدا انجام شده است: دور اول (۲۰۲۶-۱۱-۱۹؛ Besu 26.9.0، QBFT، London، یک میزبان) در `testing-evidence/besu-live-test-v25-2026-11-19/` (۲۲ فایل نتیجه؛ آمادگی production نیست)؛ دور 1b (۲۰۲۶-۱۱-۱۹) در `testing-evidence/besu-live-test-v25b-2026-11-19/` (۷ فایل نتیجه، ۲۰۳ بررسی، همه PASS؛ بایت‌کد commit `e1a5f1f`، پیش از تعویض دومرحلهٔ کلید نود). شناسه‌های Besu (BG-… و BH-…) به همین آزمون‌های زندهٔ جدا برمی‌گردند، نه به فایل‌های Hardhat. قراردادهای واقعی با همان روش simulate-and-extract روی آدرس‌های ثابت genesis گذاشته می‌شوند.

زیرپوشه‌ی `reference-dapps/`: قراردادهای **غیرضروری و اختیاری** که هرکسی هروقت خواست دیپلوی می‌کند — فعلاً فقط `SurZether.sol` (تراکنش‌های محرمانه، پیشنهادی، **هنوز آماده‌ی دیپلوی واقعی نیست** — به هشدار داخل خودِ فایل مراجعه کنید).

### `business/`
- `sur-whitepaper.md` — سپیدنامه‌ی اصلی و عمومی پروژه.
- `sur-competitive-advantages.md` — فقط چیزهایی که **خودِ پلتفرم سور** را نسبت به بلاک‌چین‌های دیگر متمایز می‌کند (۱۲ مورد موجود + ۷ بالقوه).
- `sur-dapp-business-ideas.md` — ۱۰۰ ایده‌ی کسب‌وکاری/دپ که *می‌توان* روی سور ساخت (این با سند بالا فرق دارد — نگاه کنید به مقدمه‌ی خودِ فایل).
- `sur-website-sitemap-proposal.md` — پیشنهاد ساختار تازه‌ی وب‌سایت رسمی.
- `sur-marketing-roadmap.md` — نقشه‌ی راه بازاریابی و ترویج.

### `governance/` و `economics/`
- `sur-organizational-structure.md` — ساختار کامل بنیاد و مجمع ولیدیتورها.
- `sur-validator-agreement.md` — پیش‌نویس متن توافق‌نامه‌ی ولیدیتورها (قرارداد الگو بین بنیاد و هر ولیدیتور).
- `sur-tokenomics.md` — توکنومیکس کامل سورن.

### `parties/`
یک سند برای هر طرف پروژه (بنیاد، هیأت‌مدیره، مدیرعامل و بازرس، مؤسسان، کمیته‌ها، مجمع ولیدیتورها، هیأت‌مدیره‌ی ولیدیتورها، ولیدیتور منفرد، خریداران، صرافی‌ها، توسعه‌دهندگان، اپراتورهای اوراکل/KYC، مراجع بیرونی): امکانات، عضویت، تعاملات و ابزارها. `01-interaction-matrix.md` منبع یگانهٔ «چه کسی پیشنهاد می‌دهد، تأیید می‌کند و اجرا می‌کند» و جریان پول است؛ `00-index-and-glossary.md` فهرست اسناد، راهنمای مخاطب و واژه‌نامه.

### `technical-design/`
اسناد طراحی فنی عمیق: `sur-blockchain-design-doc.md` (معماری کلی)، `sur-onchain-offchain-architecture.md` (سهم آن‌چین و آف‌چین هر سیستم، مدل تهدید و نگه‌داری کلید)، `sur-contracts-deploy-notes.md` (نکات دیپلوی genesis)، `sur-smart-contracts-reference.md` (مرجع کامل هر قرارداد)، `sur-contracts-oracles-accounts-report.md` (فهرست اوراکل‌ها/کلیدها)، `sur-security-audit-plan.md`، و اسناد بررسی پل بین‌شبکه‌ای/DEX (`sur-bridge-*.md`, `sur-dex-launch-plan.md`).

### `offchain-services/`
اسپک کامل هر نرم‌افزار جانبی (غیر از خودِ بلاک‌چین) که برای راه‌اندازی یا اکوسیستم لازم است — سرویس Verifier، RewardRouter، ابزار genesis، صفحهٔ عمومی فروش سورن (فقط‌خواندنی؛ خرید فقط از طریق صرافی‌های مجاز) و اتصال صرافی‌ها، اپلیکیشن‌های ولیدیتور/هویت، و پیشنهادهای تازه‌تر (`sur-zether-*.md`، `sur-blockchain-games-proposal.md`). `sur-software-inventory.md` فهرست کامل و اولویت‌بندی‌شده‌ی همه‌ی این‌هاست. `sur-components-catalog.md` نقشهٔ جامع قراردادها، برنامه‌های آف‌چین و رابط‌های کاربری با وضعیت ساخت (نسبت به نسخهٔ ۲٫۲) و درصد تقریبی تغییر لازم برای ۲٫۵ است. `genesisbuilder-review-record.md` سابقهٔ ساخت و دو دور بازبینی مستقل GenesisBuilder (v2.5) است. `launch-kit/` بستهٔ پیشنهادی راه‌اندازی نود (genesis-config، config.toml، docker-compose) است و سابقهٔ بازبینی‌اش در `offchain-services/launch-kit-review-record.md`.

### `diagrams/`، `brand/`، `presentations/`
نمودارهای SVG (ساختار سازمانی، منحنی درآمد ولیدیتور)، لوگوی رسمی، و دو پاورپوینت آماده (ارائه به هیأت‌مدیره؛ ارائه‌ی فنی عمیق‌تر به تیم فنی).

### `proposals/`
طرح‌های اصلاحی پیشنهادی مالک، تحلیل هر کدام (`sur-change-proposals-analysis.md`، سند تاریخچهٔ بررسی) و تصمیم نهایی دربارهٔ هر طرح (`sur-change-proposals-decisions.md`، مرجع قطعی). اسناد طراحی پوشه‌های دیگر مطابق همین تصمیم‌ها (نسخهٔ ۲.۵) نوشته شده‌اند.

### `testing-evidence/`
شواهد خام و گزارش هر دور آزمون: `hardhat-regression/` (آزمون‌های Hardhat کد ۲.۲)، `besu-live-test-v2-…` تا `besu-live-test-v6-…` (دورهای Besu روی کد ۲.۰ تا ۲.۲، سپتامبر و اکتبر ۲۰۲۶، یک میزبان)، `audit-2026-09-30-*` (اسناد ممیزی)، و **`besu-live-test-v25-2026-11-19/`** — دور اول آزمون زندهٔ Besu برای قراردادهای ۲.۵ (Besu 26.9.0 در Docker، QBFT حالت قرارداد، بلاک ۲ ثانیه، فورک London، یک میزبان، اجراهای کوتاه): `REPORT.md` (جدول نتایج، ۲۲ فایل نتیجه در `evidence/04-results/`)، `FINDINGS.md` (یافته‌های F-1 تا F-8)، `DEVIATIONS.md`، `LIMITATIONS.md`، لاگ نودها، اسکریپت‌ها و پیکربندی شبکه‌ها. در این دور اجرا نشد: تایمرهای ۷۲ ساعت و بیشتر، آزادسازی ماهانهٔ صندوق طلب‌ها، جریمه/اعتراض، لاتاری دوم، حکمرانی نرخ ریوارد، گذار Shanghai/Cancun، `SurenSale`، `ServiceStaking`. **`besu-live-test-v25b-2026-11-19/`** — دور 1b (۲۰۲۶-۱۱-۱۹؛ همان Besu و تنظیمات): ۷ فایل نتیجه، ۲۰۳ بررسی، همه PASS (راستی‌آزمایی‌شده)؛ بایت‌کد commit `e1a5f1f`: انتقال صندلی `Active` نود را در مجموعهٔ QBFT نگه می‌دارد (همان کلید اپراتور، همان جایگاه، بدون وقفه در زمان بلاک؛ وثیقه همراه صندلی)، بنیان‌گذاران `Probation` صندلی هیأت دارند ولی اختیار ندارند و `syncBoard` برشان نمی‌دارد، برای اقدام ۳ از ۵ سه عضو فعال‌شده لازم است، حذف در بازیابی با رأی هیأت، و `clearStaleVotes` برای `SelfSuspended` پیش از ۳۰ روز رد می‌شود. ⚠️ genesis آن دور پیش از تعویض دومرحلهٔ کلید نود (`07d61fd`) ساخته شد: BH-03 فقط برای قاعدهٔ قدیمی معتبر است و جریان `proposeOperator` / `confirmOperatorReady` هنوز شاهد Besu ندارد؛ اجرانشده: قفل ۹۰روزه، انقضای ۷روزه، ارجاع به ولیدیتورها، پاکسازی رأی‌های کهنه پس از ۳۰ روز. این شواهد آمادگی production نیست. فهرست یافته‌های باز: `sur-master-open-items.md` بخش ۵.

### `_archive/`
اسناد **منسوخ‌شده که جایگزین کامل‌تری پیدا کرده‌اند** — حذف نشده‌اند، فقط دیگر منبع صحت نیستند. اگر جایی لینکی به این پوشه دیدید، به‌جایش دنبال جایگزینش در پوشه‌ی اصلی بگردید.

---

## چند نکته‌ی مهم پیش از کار با این مخزن

1. **این پروژه یک ریپوی Git هم هست** (پوشه‌ی `.git/` داخلش هست) — اگر ابزار git دارید، از تاریخچه‌ی کامیت‌ها هم می‌توانید برای فهمیدن روند تغییرات استفاده کنید.
2. **برنامه‌هایی که در این ریپو در مورد آن صحبت شده هنوز نهایی نیست**  امکان تغییرات جزئی و کلی در مورد تمام پلن‌ها و برنامه‌ها وجود دارد.
3. **قراردادهای genesis عمداً `constructor` ندارند** — این یک محدودیت شناخته‌شده‌ی وریفای‌شدن روی Blockscout است، نه سهو. جزئیات در `technical-design/sur-contracts-deploy-notes.md`.
4. اگر یک سؤال یا تصمیم به‌نظر «باز» می‌رسد، اول `sur-master-open-items.md` را چک کنید — ممکن است از قبل آنجا مستند شده باشد.
5. از طریق ایشوهای این ریپو می‌توانید پیشنهادها و نظرهای خود را ارسال کنید.

---

> **نسخهٔ قراردادها در برابر اسناد (۲۰۲۶-۱۱-۱۹):** کد `contracts/` و `contracts-fa/` فقط نسخهٔ جاری است و بخش بزرگی از طرح ۲.۵ را دارد (فهرست دقیق در بخش `contracts/` بالا و در `technical-design/sur-smart-contracts-reference.md`)؛ تنها `RewardRouter` و حدود تغییر ریوارد هنوز نوشته نشده است. بخش‌های نوشته‌شده با ۹۷ آزمون Hardhat آزموده شده‌اند (آزمون‌های Hardhat فقط روی EVM درون‌فرایندی‌اند و روی Besu اجرا نمی‌شوند). آزمون زندهٔ Besu جدا و با شناسه‌های خودش انجام شده است: دور اول (۲۰۲۶-۱۱-۱۹؛ `testing-evidence/besu-live-test-v25-2026-11-19/`، شناسه‌های BG-…) و دور 1b (`testing-evidence/besu-live-test-v25b-2026-11-19/`، شناسه‌های BH-…؛ ۲۰۳ بررسی، همه PASS)؛ بخشی از قابلیت‌های ۲.۵ در آن‌ها آزموده شده است؛ تایمرهای ۷۲ ساعت و بیشتر، آزادسازی ماهانهٔ صندوق طلب‌ها، جریمه/اعتراض، لاتاری دوم، حکمرانی نرخ ریوارد، گذار Shanghai/Cancun، `SurenSale` و `ServiceStaking` روی Besu اجرا نشده‌اند. فایل‌های باینری `Sur - Detailed Plan and Rationale.docx/.pdf` و ارائه‌های `presentations/` هنوز با طرح ۲.۵ هماهنگ نشده‌اند و **نیازمند بازتولید** از اسناد به‌روز هستند.

## وضعیت کلی پروژه (خلاصه‌ی خیلی کوتاه)

معماری فنی، حکمرانی دوگانه‌ی بنیاد/ولیدیتورها، توکنومیکس، و طرح قراردادها (دوازده قرارداد ساختاری + `SurenSale`) نوشته شده‌اند؛ از ۲.۵ تاکنون `FoundationDAO`، `FoundationMembers`، `SurenSale`، `ValidatorLottery`، `GenesisClaimsVault`، حذف در بازیابی شبکه، تغییرات `IdentityRegistry`، `ValidatorSeatNFT`، هستهٔ `ValidatorsRegistry`/`ValidatorsBoard` و سوزاندن مازاد پاداش در `contracts/` نوشته و روی Hardhat آزموده شده‌اند (۹۷ آزمون Hardhat، جدا از آزمون‌های زندهٔ Besu که در دور اول و دور 1b با شناسه‌های خودشان انجام شده‌اند؛ ⚠️ تعویض دومرحله‌ای کلید نود برای `Active` پس از هر دو دور Besu آمد: فقط روی Hardhat آزموده شده و روی Besu هنوز هیچ شاهدی ندارد). سپیدنامه تقریباً کامل است (پیشینه، نقشه‌ی راه، تیم، حدود مسئولیت‌ها نوشته شده‌اند). آنچه هنوز باز مانده عمدتاً: چند پارامتر امنیتی دقیق، انتخاب سرویس‌دهنده‌ی eKYC و توافق با صرافی‌های مجاز، تاریخ‌های دقیق نقشه‌ی راه، و ادامهٔ آزمون Besu (اجرانشده‌های دور اول و یافته‌های F-1 تا F-7؛ F-4 تصمیم‌گرفته شد: بازپخش رویداد در `RewardRouter`، و نوشتن Router باقی است) و حسابرسی نسخهٔ ۲.۵ قراردادها (و نوشتن `RewardRouter` و سرویس‌ها)، و تصمیم اجرای چند پیشنهاد تازه‌تر (Zether، بازی‌های بلاک‌چینی) — فهرست کامل و به‌روز همیشه در `sur-master-open-items.md` است.
