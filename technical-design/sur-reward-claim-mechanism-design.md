# طراحی مکانیزم حفظ پاداشِ کار پیش از خروج/تعلیق (`claimableRewards`)

> ## ⚠️ وضعیت: منسوخ — جایگزین شد با سیاست ساده‌تر
>
> صاحب پروژه این طرح (نگاشت مطالبه‌ی جدا، پرداخت دوگانه‌ی push/pull) را **رد کرد** و به‌جایش سیاست بسیار ساده‌تری انتخاب کرد: پرداخت مستقیم و فوری به تولیدکننده‌ی واقعیِ هر بلاک، صرف‌نظر از وضعیت فعلی‌اش، با فقط یک پرچم دائمی (`everActivated`) به‌عنوان سدِ حداقلی. این سند فقط به‌عنوان **تاریخچه‌ی تصمیم** نگه داشته شده (چرا طرح اول رد شد، چه مسائلی حل‌شده بود). **مرجع فعلی و اجراشده:** `sur-reward-policy-decision-2026-09-29.md`. هیچ‌کدام از این سند به `contracts/BlockRewardDistributor.sol` اعمال نشده و نخواهد شد.


> **وضعیت: فقط طراحی — هیچ خط کدی در `contracts/BlockRewardDistributor.sol` واقعی اعمال نشده.** این سند برای بررسی و تصمیم صاحب پروژه است؛ پس از تأیید، به تغییر قرارداد واقعی تبدیل می‌شود. هر عدد این سند (به‌جز مثال‌های عددی) با یک قرارداد نمونه‌ی جداگانه (نه قرارداد اصلی پروژه) روی Hardhat **واقعاً اجرا و تأیید شده** — نه صرفاً محاسبه‌ی دستی. کد آن نمونه در پیوست انتهای همین سند آمده.

## ۰. اصل پذیرفته‌شده

ولیدیتور نباید پاداشِ بلاک‌هایی را که در دوره‌ی واجد‌شرایط‌بودنش (وضعیت `Active`) واقعاً تولید کرده، صرفاً به‌خاطر خروج یا تعلیقِ **بعدی** از دست بدهد. رفتار فعلی (بدون این طرح) دقیقاً برعکس این است — طبق `sur-tokenomics.md` بخش ۶.۸.۱: سهم آن بلاک‌ها بین ولیدیتورهای باقی‌مانده در فهرست پرداخت بازتوزیع می‌شود.

---

## ۱. حسابداری — چرا دوباره‌شماری یا کمبود موجودی رخ نمی‌دهد

### ۱.۱ مشکل دقیقی که باید حل شود
در کد فعلی، `_finalizeEpoch` باقیمانده‌ی تقسیم صحیح (`rewardDust`/`feeDust`، فقط چند wei) را به خزانه می‌فرستد. اگر بدون دقت، سهم ولیدیتور غیرفعال هم به‌جای پرداخت فوری صرفاً «حذف» شود، آن مبلغ (که می‌تواند بزرگ باشد، نه فقط چند wei) به‌اشتباه در `rewardDust`/`feeDust` ظاهر و به خزانه منتقل می‌شود — یعنی **هم به خزانه می‌رود، هم بعداً وقتی ولیدیتور مطالبه کند، قرارداد باید دوباره از موجودی‌اش پرداخت کند** — دقیقاً همان «دوباره‌شماری» که شما نگرانش هستید.

### ۱.۲ راه‌حل: مبلغ مطالبه‌پذیر باید «توزیع‌شده» حساب شود، نه «باقیمانده»
طرح پیشنهادی سهم ولیدیتور غیرفعال را **از همان حلقه‌ی توزیع** (نه بعد از آن، در محاسبه‌ی dust) به یک نگاشت مطالبه‌پذیر می‌نویسد و آن را عیناً «توزیع‌شده» حساب می‌کند:

```solidity
if (REGISTRY.isValidator(v)) {
    // رفتار فعلی: پرداخت فوری
} else {
    claimableRewardShare[v]   += rewardShare;
    claimableOrdinaryFeeShare[v] += ordinaryShare;
    claimableMembershipFeeShare[v] += membershipShare;
    totalOutstandingClaims += (rewardShare + ordinaryShare + membershipShare);
}
```
چون این مبلغ در `distributedRewards`/`distributedFees` (همان جمعی که `_finalizeEpoch` برای محاسبه‌ی dust استفاده می‌کند) لحاظ می‌شود، `rewardDust`/`feeDust` دقیقاً همان باقیمانده‌ی چند-wei‌ای می‌ماند که همیشه بوده — **نه بیشتر**. پول یا فوراً پرداخت می‌شود، یا مطالبه‌پذیر می‌شود؛ هرگز هر دو، و هرگز به خزانه هم نمی‌رود.

### ۱.۳ راه‌حل: جلوگیری از خرج‌شدنِ پول رزروشده در توزیع دوره‌ی بعد
این بخشِ دقیقاً همان چیزی است که شما پرسیدید و مهم‌ترین ریسک واقعی طرح است. راه‌حل: یک شمارنده‌ی سراسری از **کل** مطالبات پرداخت‌نشده، و تغییر چک موجودیِ **هر** فراخوانِ بعدیِ `distributeRewards`:

```solidity
// چک فعلی (بدون طرح):
require(totalRewards + totalFees <= address(this).balance, "insufficient contract balance");

// چک پیشنهادی (با طرح):
require(totalRewards + totalFees <= address(this).balance - totalOutstandingClaims,
        "insufficient spendable balance after reserving outstanding claims");
```

**اثبات ریاضی که این چک کافی است** (نه فقط ادعا): فرض کنید همین چک همیشه پیش از هر توزیع اجرا شود. نشان می‌دهیم که ناوردای `موجودی قرارداد ≥ مجموع مطالبات معلق` همیشه برقرار می‌ماند:
- قبل از فراخوان: طبق فرض استقرا، `balance₀ ≥ outstanding₀`.
- چک بالا تضمین می‌کند: `balance₀ − outstanding₀ ≥ totalRewards + totalFees`.
- در طول فراخوان: مبلغ `X` (خزانه+بنیاد+سوزاندن+پرداخت فوری فعال‌ها) واقعاً از قرارداد خارج می‌شود؛ مبلغ `Y` (سهم غیرفعال‌ها) فقط به `outstanding` اضافه می‌شود، از قرارداد خارج نمی‌شود. طبق ساخت، همیشه `X + Y = totalRewards + totalFees` (کل استخر، دقیقاً).
- بعد از فراخوان: `balance₁ = balance₀ − X` و `outstanding₁ = outstanding₀ + Y`.
- می‌خواهیم: `balance₁ ≥ outstanding₁` ⟺ `balance₀ − X ≥ outstanding₀ + Y` ⟺ `balance₀ − outstanding₀ ≥ X + Y = totalRewards + totalFees` — که دقیقاً همان چیزی است که پیشاپیش تضمین کردیم. ∎

یعنی تا وقتی این یک چک رعایت شود، قرارداد **هرگز** نمی‌تواند به‌جایی برسد که موجودی‌اش برای پوشش مطالبات معلق کافی نباشد — چه ۱ epoch بعد مطالبه شود، چه ۱۰۰ epoch بعد.

### ۱.۴ راستی‌آزمایی با اجرای واقعی (نه فقط اثبات دستی)
سناریوی بخش ۴ پایین را با یک قرارداد نمونه (پیوست) روی Hardhat اجرا کردم: یک تلاش عمدی برای گزارش مبلغی که مرز بالا را نقض کند **واقعاً رد شد** (`insufficient spendable balance after reserving outstanding claims`)، و در پایان `totalOutstandingClaims` دقیقاً صفر شد بعد از این‌که هر دو ولیدیتورِ غیرفعال مطالبه‌شان را گرفتند.

---

## ۲. پوشش کارمزد عادی و کارمزد عضویت — مسیر ثبت، پرداخت، مطالبه

کد فعلی این دو نوع کارمزد را قبل از تقسیم per-validator با هم ترکیب می‌کند (`feesToDistribute = effectiveTotalFees − feeBurnAmount`، که `effectiveTotalFees = totalFees + membershipFeesThisEpoch`) — یعنی سهم هر ولیدیتور امروز **یک عدد ترکیبی** است، بدون تفکیک. طرح پیشنهادی این تفکیک را یک لایه عمیق‌تر می‌برد:

| نوع | استخر (سطح epoch) | سهم هر ولیدیتور | مسیر پرداخت (فعال) | مسیر مطالبه (غیرفعال) | نگاشتِ مطالبه |
|---|---|---|---|---|---|
| پاداش بلاک | `validatorDirectAmount = totalRewards × validatorDirectShareBps` | `× blocksMined[i] / totalBlocks` | فوری، `.call` | تجمیع در نگاشت | `claimableRewardShare[address]` |
| کارمزد عادی (پس از سوزاندن ۳۰٪) | `ordinaryFeesToDistribute = totalFees × ۷۰٪` | `× blocksMined[i] / totalBlocks` | فوری، `.call` | تجمیع در نگاشت | `claimableOrdinaryFeeShare[address]` |
| کارمزد عضویت (بدون سوزاندن) | `membershipFeesThisEpoch` (کامل) | `× blocksMined[i] / totalBlocks` | فوری، `.call` | تجمیع در نگاشت | `claimableMembershipFeeShare[address]` |

**گزارش حسابداری:** رکوردهای موجود `epochValidatorRewardShare[epochId][validator]`/`epochValidatorFeeShare[epochId][validator]` (که همین امروز، مستقل از فعال/غیرفعال‌بودن، برای هر ولیدیتور نوشته می‌شوند) بدون تغییر باقی می‌مانند؛ فقط `epochValidatorFeeShare` به دو رکورد جدا (`epochValidatorOrdinaryFeeShare`, `epochValidatorMembershipFeeShare`) شکافته می‌شود تا گزارش هر epoch بتواند این دو را جدا نشان دهد. رویداد `ValidatorRewarded` هم یک فیلد `bool pushed` تازه می‌گیرد تا از رویدادهای گذشته (که آرشیو تحلیلی/حسابرسی می‌خوانَدشان) بشود فهمید کدام مسیر رفته.

**تابع مطالبه:** یک تابع واحد `claimRewards()` که هر سه نگاشت را با هم جمع و در یک تراکنش پرداخت می‌کند (مثل پیوست) — ساده‌تر برای کاربر؛ اگر گزارش حسابداری نیاز به مطالبه‌ی جدا داشته باشد، سه تابع `claimRewardOnly()`/`claimOrdinaryFeeOnly()`/`claimMembershipFeeOnly()` هم می‌تواند اضافه شود (🔶 نیازمند تصمیم شما — پایین‌تر).

---

## ۳. مرز اعتماد — قرارداد نمی‌تواند «واجدشرایط‌بودن در لحظه‌ی تولید بلاک» را خودش تأیید کند

این نکته‌ای است که شما درست گفتید «پرچم زمانی-ولیدیتور-بوده به‌تنهایی کافی نیست» — و باید صریح باشد، نه پنهان در یک فرض ضمنی.

### ۳.۱ چرا قرارداد اصلاً نمی‌تواند این را خودش بسنجد
Solidity به تاریخچه‌ی state دسترسی ندارد (فقط ۲۵۶ بلاک آخر را با `BLOCKHASH` می‌شناسد، آن‌هم فقط هش، نه محتوای storage). یعنی وقتی `distributeRewards()` فراخوانی می‌شود، قرارداد فقط می‌تواند وضعیت **همین الان** هر آدرس را در Registry بخواند (`isValidator(v)`)، نه وضعیتش در لحظه‌ای که بلاک N تولید شد. این محدودیت **از قبل هم وجود داشت** — کل مکانیزم فعلی هم روی همین مبنا («اعتماد به آنچه اوراکل می‌گوید») ساخته شده؛ طرح تازه این مرز را عوض نمی‌کند، فقط باید آن را صریح بنویسیم.

### ۳.۲ چه چیزی این مرز اعتماد را واقعاً می‌بندد (نه یک پرچم ساده)
یک پرچم دائمی مثل «این آدرس زمانی ولیدیتور فعال بوده» **کافی نیست** چون فقط ثابت می‌کند «این آدرس یک‌بار در تاریخش واجد شرایط بوده»، نه «دقیقاً همان بلاک‌های ادعاشده را در همان بازه‌ی زمانی که واجد شرایط بود تولید کرده». تنها راه واقعی، این است که **RewardRouter/اوراکل** — نه قرارداد — این تطبیق را انجام دهد، با یکی از این دو روش:

**روش الف (ترجیحی، اگر نود آرشیوی در دسترس باشد):** برای هر بلاک در بازه، `ValidatorsRegistry.isValidator(miner)` را نه با وضعیت فعلی، بلکه با `eth_call` روی **همان ارتفاع بلاک** (پارامتر `blockTag` برابر شماره‌ی همان بلاک) بخواند. این دقیقاً وضعیت Registry را در لحظه‌ی تولید همان بلاک برمی‌گرداند — قوی‌ترین شکل ممکنِ تطبیق.

**روش ب (بدون نیاز به نود آرشیوی):** بازسازی خط زمانیِ کامل وضعیت هر ولیدیتور از رویدادهای `StatusDecisionRecorded` (فعال‌سازی/تعلیق/بازگشت/پیش‌ازخروج) از genesis تا امروز — این رویدادها حتی روی نودهای غیرآرشیوی هم معمولاً قابل‌خواندن می‌مانند (لاگ‌ها در ساختار جدای bloom-filter می‌نشینند، نه در state کامل).

### ۳.۳ نقش باقی‌مانده‌ی چک on-chain
با توجه به بند ۳.۱/۳.۲، چک `isValidator`/جایگزینش در قرارداد **هرگز** نقش «تأیید زمان‌بندی» نداشته و نخواهد داشت — نقش واقعی‌اش فقط یک **سد ایمنیِ حداقلی** در برابر اوراکلِ کاملاً خراب/مخرب است (جلوگیری از پرداخت به یک آدرس کاملاً ساختگی که هرگز ولیدیتور نبوده). این دقیقاً همان تصمیم بازِ «۱» از سند قبلی است (حذف کامل چک، یا جایگزینی با پرچم سبک‌ترِ «حداقل یک‌بار فعال شده») — **هنوز باز، هنوز نیازمند تصمیم شما**، ولی حالا با تعریف درستِ نقشش: این چک **جایگزین** مسئولیت اوراکل برای تطبیق زمانی نمی‌شود؛ فقط یک سد اضافه‌ی جانبی است.

---

## ۴. سناریوی عددی کامل — اجراشده روی Hardhat، نه فقط محاسبه‌ی دستی

**تنظیم:** بازه‌ی epoch ۱ شامل ۱۰۰ بلاک. سه ولیدیتور در طول این ۱۰۰ بلاک **واقعاً و به‌درستی** `Active` بودند: A پنجاه بلاک، B سی بلاک، C بیست بلاک. تا لحظه‌ی فراخوان `distributeRewards()`: A هنوز فعال است؛ B کاملاً خارج شده (`requestExit`+`withdrawStake`)؛ C معلق شده (`Demoted`، `isValidator()=false`). هم‌زمان یک عضو تازه کارمزد عضویت ۳۰۰ سورن پرداخته (`pendingMembershipFees`). `totalRewards`=۱۰۰۰، `totalFees`=۲۰۰ (عادی)، `validatorDirectShareBps`=۵۰٪ (پیش‌فرض).

### محاسبه (تأییدشده با اجرای واقعی قرارداد نمونه)
| | مقدار |
|---|---:|
| `foundationAmount` | ۱۵۰ |
| `validatorDirectAmount` (استخر پاداش) | ۵۰۰ |
| `treasuryAmount` | ۳۵۰ |
| سوزانده‌شده (۳۰٪ از ۲۰۰ فی عادی) | ۶۰ |
| استخر فی عادیِ توزیع‌شدنی | ۱۴۰ |
| استخر کارمزد عضویت (بدون سوزاندن) | ۳۰۰ |

| ولیدیتور | بلاک | سهم پاداش | سهم فی عادی | سهم کارمزد عضویت | جمع | مسیر |
|---|---:|---:|---:|---:|---:|---|
| A (فعال) | ۵۰ | ۲۵۰ | ۷۰ | ۱۵۰ | ۴۷۰ | پرداخت فوری ✅ |
| B (خارج‌شده) | ۳۰ | ۱۵۰ | ۴۲ | ۹۰ | ۲۸۲ | مطالبه‌پذیر ✅ |
| C (معلق) | ۲۰ | ۱۰۰ | ۲۸ | ۶۰ | ۱۸۸ | مطالبه‌پذیر ✅ |

**چک تراز Epoch۱ (اجراشده):** ورودی = ۱۰۰۰+۲۰۰+۳۰۰ = **۱۵۰۰**. خروجی = پرداخت‌فوریA(۴۷۰) + خزانه(۳۵۰) + بنیاد(۱۵۰) + سوزانده(۶۰) + مطالبه‌ی‌معلقِB‌وC(۲۸۲+۱۸۸=۴۷۰) = **۱۵۰۰**. ✅ دقیقاً برابر.

**چک مرز حفاظتی (اجراشده):** تلاش برای گزارش یک توزیع تازه با مبلغی که `موجودی − ۴۷۰ (مطالبات معلق)` را رد کند — **واقعاً و صحیح** با `insufficient spendable balance after reserving outstanding claims` رد شد.

**Epoch۲ (۵۰ بلاک، فقط A فعال، بدون کارمزد عضویت تازه):** `totalRewards`=۵۰۰، `totalFees`=۵۰. A فوراً ۲۸۵ می‌گیرد (خزانه ۱۷۵، بنیاد ۷۵). `totalOutstandingClaims` دست‌نخورده می‌ماند (۴۷۰) چون کسی مطالبه‌ی تازه‌ای اضافه نکرد.

**مطالبه‌ی نهایی:** B دقیقاً ۲۸۲ می‌گیرد؛ C دقیقاً ۱۸۸ می‌گیرد؛ `totalOutstandingClaims` نهایی = **۰**.

**چک تراز کل دو epoch (اجراشده):** ورودی کل = ۱۰۰۰+۲۰۰+۳۰۰+۵۰۰+۵۰ = **۲۰۵۰**. خروجی کل (همه‌ی پرداخت‌های فوری+خزانه+بنیاد+سوزاندن+مطالبات نهایی‌شده) = **۲۰۵۰**. ✅ دقیقاً برابر — بدون هیچ کم یا اضافه.

---

## ۵. تصمیم‌های باز — هیچ‌کدام نهایی نشده

| # | سؤال | گزینه‌ها |
|---|---|---|
| ۱ | چک ورودیِ آدرس: حذف کامل، یا جایگزینی با پرچمِ «حداقل یک‌بار فعال شده»؟ (بخش ۳.۳) | الف) حذف کامل — ساده‌ترین، اعتماد کامل به اوراکل (مثل امروز برای اعداد `totalRewards`/`totalFees`) / ب) پرچم دائمی تازه در Registry، فقط سدِ حداقلی، نه تأیید زمان‌بندی |
| ۲ | آیا `claimRewards()` یکی باشد (جمع هر سه نوع) یا سه تابع جدا برای گزارش دقیق‌تر؟ | یکی (ساده‌تر برای کاربر) / سه‌تا (شفاف‌تر برای حسابرسی) |
| ۳ | سقف زمانی برای مطالبه (بعد از N سال، مطالبه‌ی نشده کجا برود)؟ | بدون سقف / سقف با مقصد مشخص (نیازمند عدد) |
| ۴ | الگوی پرداخت برای همه یکسان شود (حتی فعال‌ها هم مطالبه‌محور) یا ترکیبی (طرح بالا) بماند؟ | ترکیبی (کمترین تغییر رفتار امروز) / یکسان‌سازی کامل (شفاف‌تر برای ممیزی، هزینه‌ی گس اضافه برای اکثریت که امروز رایگان است) |
| ۵ | آیا اثر عطف‌به‌ماسبق روی epochهای قبلاً تسویه‌شده لازم است؟ | فنی ممکن نیست — فقط از epochِ بعد از این تغییر اعمال می‌شود |

تا این تصمیم‌ها گرفته نشود، **هیچ تغییری در `contracts/BlockRewardDistributor.sol` واقعی اعمال نشده و نخواهد شد.**

---

## پیوست — کد قرارداد نمونه‌ای که برای اثبات عددی بخش ۴ استفاده شد

این فایل **جزو پروژه نیست** و جایگزین `BlockRewardDistributor.sol` واقعی نمی‌شود؛ فقط برای صحت‌سنجی مستقل حسابداریِ طرح ساخته شد.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockRegistry {
    mapping(address => bool) public active;
    function setActive(address a, bool v) external { active[a] = v; }
    function isValidator(address a) external view returns (bool) { return active[a]; }
}

contract MockClaimDesign {
    MockRegistry public immutable REGISTRY;
    address public immutable TREASURY;
    address public immutable FOUNDATION;
    uint256 public constant FOUNDATION_SHARE_BPS = 1500;
    uint256 public constant FEE_BURN_BPS = 3000;
    uint256 public constant BPS = 10000;
    uint256 public validatorDirectShareBps = 5000;
    uint256 public pendingMembershipFees;

    mapping(address => uint256) public claimableRewardShare;
    mapping(address => uint256) public claimableOrdinaryFeeShare;
    mapping(address => uint256) public claimableMembershipFeeShare;
    uint256 public totalOutstandingClaims;
    uint256 public totalBurned;
    uint256 public epochCount;

    event ValidatorPaid(address indexed v, uint256 rewardShare, uint256 ordinaryFeeShare, uint256 membershipFeeShare, uint256 total, bool pushed);
    event Claimed(address indexed v, uint256 amount);
    event EpochFinalized(uint256 epochId, uint256 foundationAmount, uint256 treasuryAmount, uint256 burned, uint256 distributedTotal);

    constructor(address registry, address treasury, address foundation) {
        REGISTRY = MockRegistry(registry); TREASURY = treasury; FOUNDATION = foundation;
    }
    receive() external payable {}
    function addMembershipFee() external payable { pendingMembershipFees += msg.value; }

    function distributeRewards(address[] calldata validators, uint256[] calldata blocksMined, uint256 totalRewards, uint256 totalFees) external {
        uint256 totalBlocks = 0;
        for (uint256 i = 0; i < blocksMined.length; i++) totalBlocks += blocksMined[i];
        require(totalBlocks > 0, "zero blocks");

        uint256 membershipFeesThisEpoch = pendingMembershipFees; pendingMembershipFees = 0;
        uint256 feeBurnAmount = (totalFees * FEE_BURN_BPS) / BPS;
        uint256 ordinaryFeesToDistribute = totalFees - feeBurnAmount;

        require(totalRewards + totalFees + membershipFeesThisEpoch <= address(this).balance - totalOutstandingClaims,
            "insufficient spendable balance after reserving outstanding claims");

        uint256 foundationAmount = (totalRewards * FOUNDATION_SHARE_BPS) / BPS;
        uint256 validatorDirectAmount = (totalRewards * validatorDirectShareBps) / BPS;
        uint256 treasuryAmount = totalRewards - foundationAmount - validatorDirectAmount;

        uint256 distTotal = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            if (blocksMined[i] == 0) continue;
            distTotal += _payOne(validators[i], blocksMined[i], totalBlocks, validatorDirectAmount, ordinaryFeesToDistribute, membershipFeesThisEpoch);
        }

        (bool tok, ) = TREASURY.call{value: treasuryAmount}(""); require(tok, "treasury failed");
        (bool fok, ) = FOUNDATION.call{value: foundationAmount}(""); require(fok, "foundation failed");
        totalBurned += feeBurnAmount;

        epochCount++;
        emit EpochFinalized(epochCount, foundationAmount, treasuryAmount, feeBurnAmount, distTotal);
    }

    function _payOne(address v, uint256 blocks_, uint256 totalBlocks, uint256 rewardPool, uint256 ordinaryPool, uint256 membershipPool) private returns (uint256 total) {
        uint256 rewardShare = (rewardPool * blocks_) / totalBlocks;
        uint256 ordinaryShare = (ordinaryPool * blocks_) / totalBlocks;
        uint256 membershipShare = (membershipPool * blocks_) / totalBlocks;
        total = rewardShare + ordinaryShare + membershipShare;
        if (REGISTRY.isValidator(v)) {
            (bool ok, ) = v.call{value: total}(""); require(ok, "push failed");
            emit ValidatorPaid(v, rewardShare, ordinaryShare, membershipShare, total, true);
        } else {
            claimableRewardShare[v] += rewardShare;
            claimableOrdinaryFeeShare[v] += ordinaryShare;
            claimableMembershipFeeShare[v] += membershipShare;
            totalOutstandingClaims += total;
            emit ValidatorPaid(v, rewardShare, ordinaryShare, membershipShare, total, false);
        }
    }

    function claimRewards() external {
        uint256 amount = claimableRewardShare[msg.sender] + claimableOrdinaryFeeShare[msg.sender] + claimableMembershipFeeShare[msg.sender];
        require(amount > 0, "nothing to claim");
        claimableRewardShare[msg.sender] = 0; claimableOrdinaryFeeShare[msg.sender] = 0; claimableMembershipFeeShare[msg.sender] = 0;
        totalOutstandingClaims -= amount;
        (bool ok, ) = msg.sender.call{value: amount}(""); require(ok, "claim failed");
        emit Claimed(msg.sender, amount);
    }
}
```
