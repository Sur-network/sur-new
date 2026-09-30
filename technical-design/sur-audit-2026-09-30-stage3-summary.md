# جمع‌بندی مرحلهٔ ۳ دور اصلاح ممیزی ۲۰۲۶-۰۹-۳۰ — API و راهنماهای برنامه‌نویس

> دامنه: D04، D05، D06، D15، D16 و پیگیری تغییر ABI مرحلهٔ ۱ (L01–L03) در مصرف‌کنندگان. هر مورد پیش از اصلاح با کد واقعی تطبیق داده شد. شواهد و diffها در بستهٔ افزایشی (`testing-evidence/audit-2026-09-30-stage3-docs/` و `testing-evidence/hardhat-regression/results/audit-2026-09-30-D05/`).

## ۱. وضعیت شناسه‌ها

| شناسه | شاهد در کد | اصلاح | وضعیت |
|---|---|---|---|
| D04 | `ValidatorsRegistry.ParamKey` شش مقدار دارد | جدول هشت‌مقداری منسوخ داشبورد با جدول شش‌مقداری index‌دار جایگزین شد | ✅ بسته |
| D05 (مسیر خرج خزانه) | مدل P06: مجمع فقط سقف را تعیین می‌کند | مسیر «پیشنهاد/رأی خرج» از بخش‌های ۰ و ۲ داشبورد و از UI review حذف شد | ✅ بسته |
| D05 (نصاب ذخیره‌شده) | `FoundationDAO.proposals` خصوصی است؛ `getProposal` چهار فیلد لازم را برنمی‌گرداند؛ `ValidatorsRegistry.paramProposals` عمومی است و فیلدها را دارد | getter فقط‌خواندنی `FoundationDAO.getProposalMeta(id)` در هر دو زبان (`getProposal` بدون تغییر)؛ داشبورد از آن و از `paramProposals(id)` می‌خواند | ✅ بسته — آزمون روی قرارداد واقعی ۱۸/۱۸ در EN و FA و هر دو کامپایلر؛ سورس پیش از تغییر در F2 شکست |
| D05 (اختیار هیأت در UI) | `hasBoardAuthority` تعریف زنده است | دو محل `isBoardMember` در داشبورد اصلاح شد | ✅ بسته |
| D06 | `setPhoneVerified`/`setTelegramVerified` در `IdentityRegistry` با `onlyIdentityOracle` | verifier spec اصلاح شد؛ inventory چهار کلید سرویس را می‌شمارد (`distributionOracle`، `verifier`، `identityOracle`، `paymentOracle`) | ✅ بسته در اسناد؛ اسلاید ۲۳ ارائهٔ فنی در مرحلهٔ ۵ |
| D15 | تسویه با `currentPriceMilliToman()` | برآورد portal با فرمول `reportPayment`؛ عدد صحیح فقط برای نمایش | ✅ بسته |
| D16 | `sur-identity-app-claudecode-brief.md` در Plan وجود ندارد | در inventory و UI review «موجود نیست» با مرجع موقت | ✅ ارجاع‌ها اصلاح شد؛ **نوشتن خود brief باز**؛ سند جامع هنوز بررسی نشده |

## ۲. پیگیری ABI مرحلهٔ ۱
- حذف `deployTime()` و `MIN_BLOCK_PERIOD_SECONDS()`: در deploy-notes، genesis-builder-spec، reward-router-spec، design-doc و contracts-reference اصلاح شد. شواهد تاریخی v3 دست نخورد.
- `shareProposals(id)` با ۱۰ خروجی: هیچ مصرف‌کنندهٔ موقعیتی در اسناد و اسکریپت‌ها نبود؛ ترتیب فیلدها در contracts-reference ثبت شد.

## ۳. RewardRouter — تعریف‌های یکدست‌شده در این مرحله
- **بازه:** `S = lastSettledBlock()` و `L = eth_blockNumber` (آخرین بلاک مهرشده) یک‌بار در ابتدای چرخه؛ بازهٔ تسویه و اسکن هر دو `[S+1, L]`. عبارت `head−1` از مشخصات RewardRouter (خط ۵۹، گام ۲، schema) و گزارش مرحلهٔ ۱ حذف شد؛ هم‌معنا نبود.
  یادداشت: آزمون Hardhat `test_L03_settlement_backlog.js` در سناریوی C تا `head−1` تسویه می‌کند (یک بلاک عقب‌تر از `L`)؛ این یک پارامتر آزمون است و برای ادعای «عقب‌ماندگی رشد نمی‌کند» محافظه‌کارانه‌تر است، نه تعریف مشخصات.
- **کارمزد:** `fee = gasUsed × (effectiveGasPrice − baseFeePerGas)` از رسید و هدر بلاک؛ معادلهٔ تطبیق موجودی با علامت اجزا در گام ۶.
- **ماشین حالت تراکنش:** `prepared → submitted ⇄ unknown → confirmed | reverted`؛ timeout هرگز شکست نیست. schema شامل `nonce`، `calldata` و جدول `epoch_txs` (هر تلاش: `tx_hash`، `raw_signed_tx`، پارامترهای گس، زمان ثبت پایدار و broadcast، وضعیت رسید).
- **پنجرهٔ crash بین broadcast و ثبت hash:** تراکنش امضاشده و hash آن پیش از broadcast پایدار ثبت می‌شود؛ پس از restart همان بایت‌ها تطبیق یا بازپخش می‌شوند؛ معیار پذیرش چهارحالتی در گام ۸.
- **جایگزینی تراکنش:** `REPLACE_AFTER`، `MAX_REPLACEMENTS` و حداقل افزایش ۱۰٪ فقط **پارامتر پیشنهادی** هستند و باید با تنظیمات txpool نسخهٔ واقعی Besu تطبیق و آزمون شوند؛ در این بسته تأیید اجرایی نشده‌اند.
- همهٔ موارد RewardRouter: **مشخصات آماده؛ پیاده‌سازی باز.**

## ۴. اشتباه‌های خودم در این مرحله که اصلاح شد
- در داشبورد نوشته بودم نصاب از `proposals(id)` خوانده شود؛ این getter وجود ندارد (نگاشت خصوصی است). با `getProposalMeta(id)` اصلاح شد و خود متن داشبورد این را ثبت می‌کند.
- در گام ۲ نوشته بودم «head−1» با `L` هم‌معناست؛ نبود. حذف و یکدست شد.
- گام ۸ ابتدا ثبت hash را «پس از ارسال» می‌گفت که با ترتیب ثبت پایدار پیش از broadcast تناقض داشت؛ اصلاح شد.
- اعلام «۱۰۰ فایل» برای بستهٔ پیشین نادرست بود (شمارش ورودی‌های زیپ با پوشه‌ها)؛ manifest آن بسته ۸۰ فایل داشت.

## ۵. باز می‌ماند
L05–L08؛ اجرای Besu؛ پیاده‌سازی T02 و RewardRouter (شامل recovery و پنجرهٔ crash)؛ brief اپ هویت (D16)؛ بررسی D16 در سند جامع؛ D06 در اسلاید ۲۳؛ هماهنگ‌سازی بقیهٔ اسناد، SVGها و پرزنتیشن‌ها (مراحل ۴ و ۵)؛ موارد نیازمند تصمیم مالک بخش ۷.۷ ممیزی.
