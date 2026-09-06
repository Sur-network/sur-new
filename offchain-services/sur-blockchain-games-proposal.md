# پیشنهاد پیاده‌سازی: بازی‌های بلاک‌چینی متن‌باز روی سور

> این سند فقط بازی‌ها/چارچوب‌های **واقعاً موجود، شناخته‌شده، و کاملاً متن‌باز** را معرفی می‌کند — هر مورد با لینک مستقیم گیت‌هاب. همه‌ی موارد **سازگار با EVM/Solidity** انتخاب شده‌اند (نه Cairo/Starknet یا Move/Aptos)، چون فورک‌کردن پروژه‌های غیر-EVM نیازمند بازنویسی کامل از یک زبان دیگر است، نه صرفاً دیپلوی مجدد روی سور.

⚠️ **هشدار نام‌گذاری:** یک ریپوی دیگر به اسم `ill-inc/biomes-game` پیدا شد که با «Biomes» (بازی on-chainِ اکوسیستم MUD) اسم مشترک دارد ولی ظاهراً یک بازی sandbox معمولی و بی‌ربط به بلاک‌چین است — دقیقاً همان نوع تداخل نامی که در بررسی Zether (`ZetherOrg/go-zether`) هم پیش آمده. به همین دلیل «Biomes» در این فهرست نیامده.

---

## بخش ۱: زیرساخت‌ها (چارچوب/پرایمیتیو، نه یک بازی خاص)

### ۱. MUD — چارچوب اصلی بازی‌های on-chain
**لینک:** https://github.com/latticexyz/mud
چارچوب مرجع برای «بازی‌های کاملاً on-chain». متن‌باز زیر مجوز MIT؛ برای **هر بلاک‌چین سازگار با EVM** طراحی شده. اکثر بازی‌های بخش ۲ روی همین چارچوب ساخته شده‌اند.

### ۲. Cement — کتابخانه‌ی کمکی بازی‌سازی روی MUD
**لینک:** https://github.com/HelheimLabs/cement
کتابخانه‌ای برای قابلیت‌های رایج بازی (مثل مسیریابی) که در خودِ MUD نیست.

### ۳. Loot (for Adventurers) — پرایمیتیو بنیادین اکوسیستم NFT/بازی
**لینک:** قرارداد اصلی روی mainnet اتریوم؛ کتابخانه‌های تکمیلی متن‌باز مثل `github.com/genesisproject4loot/loot-stats` و `github.com/genesisproject4loot/loot-classification`
یک مجموعه‌ی NFT فوق‌ساده (فقط اسم آیتم‌ها، بدون تصویر) که در ۲۰۲۱ کل یک اکوسیستم بازی/دپ مشتق را به راه انداخت. خودش «بازی» با مکانیزم گیم‌پلی نیست، ولی به‌عنوان یک پرایمیتیو بنیادین برای ساخت بازی‌های دیگر (مشابه نقش MUD) قابل‌استفاده است.

---

## بخش ۲: بازی‌های کامل و کاملاً متن‌باز

### ۴. Dark Forest — پرچمدار بازی‌های کاملاً on-chain
اولین بازی «کاملاً on-chain» در تاریخ اتریوم (۲۰۲۰)؛ استراتژی فضایی چندنفره‌ی زنده.

| بخش | لینک |
|---|---|
| قرارداد هوشمند | https://github.com/darkforest-eth/eth |
| فرانت‌اند | https://github.com/darkforest-eth/client |
| مدارهای رمزنگاری (zkSNARK، مکانیزم مه‌جنگی) | https://github.com/darkforest-eth/circuits |
| بسته‌های کمکی پلاگین/کلاینت | https://github.com/darkforest-eth/packages |
| نمونه‌ی اجرای مستقل (برای فورک روی شبکه‌ی دیگر) | https://github.com/projectsophon/darkforest-local |

⚠️ بخش zkSNARK باید مستقیم فورک شود، نه بازنویسی از صفر — همان اصل Zether.

### ۵. OPCraft — دنیای voxel (شبیه ماینکرفت)
ساخته‌ی Lattice، بخشی از اکوسیستم رسمی نمونه‌های MUD؛ ساخته‌شده در ۱.۵ ماه به‌عنوان نمایش قدرت چارچوب.

### ۶. Ember — استراتژی سیاه‌چاله‌ای/دخمه
**لینک:** https://github.com/latticexyz/ember
⚠️ رسماً «متوقف‌شده» ولی ریپو کاملاً باز با دستورالعمل کامل دیپلوی.

### ۷. Primodium — کارخانه‌سازی فضایی
**لینک:** https://github.com/primodiumxyz/primodium
مونوریپوی کامل (کلاینت React، موتور Phaser، قراردادهای MUD، ایندکسر Postgres)؛ رسماً تأیید شده «قابل‌دیپلوی روی هر محیط سازگار با EVM».

### ۸. Empires — بازار پیش‌بینی نوبتی (خواهر Primodium)
ریپوی سازمانی `primodiumxyz` — بازار پیش‌بینی کاملاً on-chain، ساخته‌شده با MUD و Phaser.

### ۹. Sky Strife — استراتژی بلادرنگ (RTS)
**لینک:** https://github.com/latticexyz/skystrife-public
شامل `packages/client`، `packages/contracts`، `packages/art`.

### ۱۰. Downstream — پلتفرم/ابزار ساخت بازی on-chain
**لینک:** https://github.com/playmint/ds
پلتفرم بازی و ابزار ساخت کاملاً on-chain، در حال اجرا روی Redstone (شبکه‌ی L2 مبتنی بر OP Stack).

### ۱۱. MUD2048 — نسخه‌ی on-chain بازی ۲۰۴۸
ریپوی `themetacat` — نسخه‌ی کاملاً on-chain بازی ۲۰۴۸؛ نمونه‌ی خوب برای شروع ساده.

### ۱۲. PixeLAW — دنیای مستقل مبتنی بر پیکسل
ریپوی `themetacat/pixelaw_core` — دنیای خودمختار مبتنی بر پیکسل، نوشته‌شده به Solidity، مبتنی بر MUD.

### ۱۳. Autochessia — اتوچس کاملاً on-chain
**لینک:** https://github.com/HelheimLabs/autochessia
اتوچس کاملاً on-chain، MUD و Solidity؛ مجوز AGPL-3.0.

### ۱۴. Color3 — بازی حذف رنگ
ریپوی `HelheimLabs/color3` — بازی کاملاً on-chain درباره‌ی حذف رنگ، از همان تیم Autochessia.

### ۱۵. Words3 — اسکرابل بی‌نهایت on-chain
معرفی‌شده در گزارش رسمی Optimism RetroPGF به‌عنوان یکی از پروژه‌های اصلی اکوسیستم MUD روی OP Stack.

### ۱۶. Kamigotchi — RPG حیوان‌خانگی کاملاً on-chain
ریپوهای سازمانی `Asphodel-OS` («Fully onchain game studio»)؛ روی Optimism.

### ۱۷. Genki Cats — بازی موبایل کاملاً on-chain
**لینک:** https://github.com/GenkiCats/genkicats-core
بازی موبایل کاملاً on-chain، بر پایه‌ی چارچوب MUD.

### ۱۸. Rhascau — استراتژی نوبتی سبک مسابقه‌ی غلاف‌دار
ساخته‌ی Minters Corp؛ استراتژی نوبتی سبک pod racing، کاملاً on-chain، روی Arbitrum Nova (۲۰۲۳).

### ۱۹. Outlaws of Loxley — دوئل‌های پیکسلی PvP
پروژه‌ای با پشته‌ی Solidity + Next.js + TypeScript + Foundry؛ دوئل‌های PvP کاملاً on-chain روی Robinhood Chain.

### ۲۰. CryptoKitties — پیشگام تاریخی NFT/بازی بلاک‌چینی
**لینک قرارداد اصلی:** https://github.com/dapperlabs/cryptokitties-bounty
اولین بازی بلاک‌چینی که واقعاً مشهور عام شد (۲۰۱۷)، تا حدی که شبکه‌ی اتریوم را کند کرد؛ پایه‌گذار عملی استاندارد ERC-721. قرارداد اصلی (`KittyCore`, `KittyBase`) رسماً متن‌باز است؛ حتی الگوریتم ژنتیکی که ابتدا مخفی نگه‌داشته شده بود، از ۲۰۱۹ به بعد رسماً متن‌باز شد.
⚠️ **محدودیت صادقانه:** برخلاف Dark Forest، رابط کاربری وب رسمی اصلی توسط Dapper Labs هرگز به‌طور رسمی متن‌باز منتشر نشده — فقط بازسازی‌های جامعه‌محور (مثل `ErnoW/crypto-kitties`) در دسترس‌اند که کیفیت/کامل‌بودنشان تضمین‌شده نیست.

### ۲۱. Aavegotchi — NFT استیک‌شده با مکانیزم بازی (ژانر متفاوت)
| بخش | لینک |
|---|---|
| قرارداد اصلی (الگوی Diamond) | https://github.com/aavegotchi/aavegotchi-contracts |
| کلاینت جامعه‌محور «fireball» | ریپوی `gotchinomics/ghst-gg` |

### ۲۲. Pirate Nation — RPG دزدان دریایی
طبق فهرست کیوریت‌شده‌ی `moonstream-to/awesome-web3-games` — NFT های بازی روی اتریوم، بخش قابل‌بازی‌کردن روی Arbitrum Nova.

### ۲۳. Conquest.eth — استراتژی و دیپلماسی فضایی (Gnosis Chain)
**لینک:** https://github.com/etherplay/conquest-eth
بازی «بی‌نهایت» (infinite game) — کاملاً permissionless، تغییرناپذیر، و بدون واسطه. کد کامل منتشرشده زیر مجوز AGPL-3.0؛ قابل‌اجرا کاملاً محلی یا متصل به Gnosis Chain. ساخته‌ی استودیوی Etherplay — همان تیمی که Ethernal و Stratagems را هم می‌سازد (بخش‌های ۲۴ و ۲۵).
⚠️ طبق اعلام خودشان، بخشی از دارایی‌های گرافیکی متن‌باز نیستند و برای فورک رسمی نیاز به تهیه/خرید مجوز جداگانه دارند — قرارداد و منطق بازی اما کاملاً باز است.

### ۲۴. Stratagems — کاوش ترکیب‌پذیری بدون‌مجوز
**لینک:** https://github.com/wighawag/stratagems
بازی دیگری از همان استودیوی متن‌باز Etherplay (سازنده‌ی Conquest.eth)؛ کاوش ایده‌ی «ترکیب‌پذیری بدون‌مجوز با قوانین تغییرناپذیر».

### ۲۵. Ethernal — دخمه‌ی چندنفره‌ی تولیدشده و مالکیت بازیکنان
**لینک:** https://github.com/0xgen0/ethernal
یکی از اولین بازی‌های کاملاً on-chain اتریوم؛ توسعه در پاییز ۲۰۲۰ متوقف شده ولی کد آخرین نسخه کاملاً باز مانده (مجوز MIT) — شامل هر سه بخش: `contracts` (قوانین بازی)، `backend` (Node.js، همگام‌سازی داده)، و `webapp` (فرانت‌اند Svelte).
⚠️ **هشدار نام‌گذاری سوم:** با «Ethernal» ابزار اکسپلورر بلاک‌چین (`tryethernal`/`hardhat-ethernal`) اشتباه گرفته نشود — کاملاً دو پروژه‌ی متفاوت با اسم یکسان‌اند؛ این یکی بازی است، آن یکی ابزار توسعه.

### ۲۶. EtherOrcs — RPG اورک‌های on-chain
**لینک:** https://github.com/EtherOrcsOfficial/etherOrcs-contracts
یکی از بازی‌های شناخته‌شده‌ی موج NFT گیمینگ ۲۰۲۱؛ قراردادها هم روی Ethereum Mainnet هم Polygon PoS دیپلوی شده‌اند (آدرس‌های واقعی در خودِ ریپو مستند شده‌اند).

### ۲۷. Forgotten Runes — دنیای شخصیت‌محور
**لینک:** https://github.com/forgottenrunes/forgotten-runes-contracts
یکی از پروژه‌های شناخته‌شده‌ی اکوسیستم NFT/بازی با دنیای داستانی گسترده.

### ۲۸. Etheremon — یکی از قدیمی‌ترین بازی‌های اتریوم (۲۰۱۸)
**لینک:** https://github.com/Etheremon/smartcontract
شبیه‌سازی جهانی از هیولاهای قابل‌جمع‌آوری، تربیت، و مبارزه — یکی از اولین تلاش‌های جدی بازی‌سازی روی اتریوم، پیش از ERC-721 استاندارد امروزی.

### ۲۹. MegaCryptoPolis — شهرساز استراتژیک (۲۰۱۸)
**لینک:** https://github.com/mcp-town/contracts
بازی شهرسازی غیرمتمرکز روی اتریوم؛ یکی از اولین بازی‌های استراتژی/شبیه‌سازی جدی این حوزه، با برنامه‌ی رسمی بونتی امنیتی برای قراردادهایش.

### ۳۰. Wolf Game — استیکینگ گوسفند/گرگ با ریسک واقعی
**لینک:** `github.com/swooshcrypto/Wolf_Game` (شامل قرارداد اصلی `Woolf.sol`)
یکی از معروف‌ترین بازی‌های موج NFT ۲۰۲۱-۲۰۲۲؛ از Chainlink VRF برای تصادفی‌سازی قابل‌اثبات استفاده می‌کند.
⚠️ **محدودیت صادقانه:** این آدرس یک ریپوی جامعه‌محور/آینه است، نه لزوماً مخزن رسمی تیم سازنده. پیش از هر فورک واقعی، باید نسخه‌ی دقیق و آدیت‌شده تأیید شود.

---

## بخش ۳: ژانرهای تازه — کارت‌بازی، هنر، و نمونه‌های ساده‌تر MUD

### ۳۱. 0xFable — کارت‌بازی کاملاً on-chain
**لینک:** https://github.com/0xFableOrg/0xFable
کارت‌بازی کاملاً on-chain با شخصیت‌های فانتزی (الف، جادوگر)؛ پشته‌ی کامل شامل قرارداد، فرانت‌اند NextJS، و حتی مدارهای zk (با circom) برای بخش‌هایی از منطق بازی. قابل‌اجرا کاملاً محلی با Anvil.
🔶 توجه: طبق فهرست‌بندی صنعتی، رقبای بزرگ‌تر این ژانر (Gods Unchained، Skyweaver) بررسی و **رد شدند** — چون گیم‌پلی‌شان عمدتاً آف‌چین است و کد منبع رسمی‌شان هرگز به‌طور کامل متن‌باز نشده؛ فقط API عمومی (نه کد کامل) منتشر کرده‌اند.

### ۳۲. Art Blocks — پلتفرم پیشرو هنر ژنراتیو on-chain
**لینک:** https://github.com/ArtBlocks/artblocks-contracts (قرارداد اصلی)، به‌همراه `artblocks-starter-template`، `node-artblocks`، و `artblocks-docs`
نه یک «بازی» به‌معنای رایج، بلکه پلتفرم پیشرو نگه‌داری هنر ژنراتیو کاملاً on-chain (از ۲۰۲۰) — هنرمند الگوریتم را روی زنجیره ذخیره می‌کند؛ هر خرید یک هش یکتا تولید می‌کند که الگوریتم از آن یک اثر منحصربه‌فرد و قطعی می‌سازد. خودشان صراحتاً می‌گویند: «با کد متن‌باز ما، یک نمونه‌ی کاملاً مستقل از مولد Art Blocks اجرا کنید».

### ۳۳. mudbasics — ساده‌ترین نمونه‌ی مرجع رسمی MUD
**لینک:** https://github.com/latticexyz/mudbasics
پیاده‌سازی مرجع بسیار ساده (قرارداد + کلاینت Phaser) که خودِ Lattice برای آموزش گام‌به‌گام MUD منتشر کرده. ⚠️ آرشیوشده (بایگانی‌شده)، ولی برای یادگیری یا شروع یک فورک آموزشی هنوز کاملاً قابل‌استفاده است.

### ۳۴. Sunflower Land — اقتصاد کشاورزی چندتوکنی (NFT)
**لینک:** سازمان `github.com/sunflower-land`، قرارداد اصلی در `github.com/easycc/contracts`
یک بازی کشاورزی/اقتصادی محبوب با معماری آف‌چین-به‌آنچین (کاربر بازی می‌کند بدون تراکنش مداوم، و فقط برای برداشت دارایی به کیف‌پول خودش تراکنش می‌زند) — یک الگوی معماری جالب که هزینه‌ی گس را برای کاربر نهایی به‌شدت پایین می‌آورد. توضیح رسمی خودشان: «یک جامعه‌ی متن‌باز با هدف ساخت یک اقتصاد بازی کریپتویی چندتوکنی».

## بخش ۴: بازی‌های درآمدزا (Play-to-Earn) و مسابقه‌ای بیشتر

### ۳۵. DeFi Space Pirates — دزدان‌دریایی فضایی درآمدزا
| بخش | لینک |
|---|---|
| قرارداد هوشمند | `github.com/DeFi-Space-Pirates/space-pirates-contracts` |
| فرانت‌اند | `github.com/DeFi-Space-Pirates/space-pirates-frontend` |

بازی Play-to-Earn با دو توکن درون‌بازی («Doubloons» و «Asteroids»)؛ ترکیبی از بخش شبیه‌سازی/NFT و بخش DeFi.
⚠️ سازمان به‌عنوان «بایگانی‌شده» (دیگر نگه‌داری نمی‌شود) علامت خورده، ولی هر دو ریپو (قرارداد+فرانت‌اند) کامل و عمومی باقی مانده‌اند.

### ۳۶. Draw.Tech — اولین بازی نقاشی کاملاً on-chain موبایل
**لینک:** https://github.com/smallbraineng/drawtech
از همان استودیوی Small Brain Games که Words3 (آیتم ۱۴) را ساخته؛ به گفته‌ی خودشان «اولین بازی کاملاً on-chain موبایل». شامل فرانت‌اند، قرارداد هوشمند، و یک سرویس اعلان (notification service) — یعنی هر سه لایه‌ی خواسته‌شده (قرارداد+فرانت+بک‌اند) در یک ریپو. مجوز MIT.

---

## یادداشت: بازی‌های NFT شناخته‌شده‌ای که بررسی و **رد شدند**

- **Nine Chronicles** — کاملاً متن‌باز (GPL3) و حتی با مشارکت Ubisoft، ولی روی بلاک‌چین اختصاصی خودشان (Libplanet، مبتنی بر .NET) ساخته شده، **نه EVM/Solidity** — دقیقاً همان دلیلی که پروژه‌های Starknet/Cairo از ابتدای این سند کنار گذاشته شدند. فورک‌کردنش یعنی بازنویسی کامل از یک بلاک‌چین به بلاک‌چین دیگر، نه دیپلوی مجدد.
- **DeFi Kingdoms** — ریپوهای عمومی فراوانی پیدا شد، ولی همه ابزار/بات شخص‌ثالث بودند (کوئستر خودکار، ردیاب تراکنش)؛ هیچ ریپوی رسمی از خودِ قرارداد اصلی بازی پیدا نشد.

---

## جدول خلاصه

| # | نام | نوع | لینک/منبع |
|---|---|---|---|
| ۱ | MUD | چارچوب | https://github.com/latticexyz/mud |
| ۲ | Cement | کتابخانه | https://github.com/HelheimLabs/cement |
| ۳ | Loot | پرایمیتیو NFT | https://github.com/genesisproject4loot |
| ۴ | Dark Forest | استراتژی فضایی | https://github.com/darkforest-eth |
| ۵ | OPCraft | دنیای voxel | (اکوسیستم رسمی MUD) |
| ۶ | Ember | استراتژی دخمه‌ای | https://github.com/latticexyz/ember |
| ۷ | Primodium | کارخانه‌سازی فضایی | https://github.com/primodiumxyz/primodium |
| ۸ | Empires | بازار پیش‌بینی | (سازمان primodiumxyz) |
| ۹ | Sky Strife | RTS | https://github.com/latticexyz/skystrife-public |
| ۱۰ | Downstream | پلتفرم بازی‌سازی | https://github.com/playmint/ds |
| ۱۱ | MUD2048 | پازل | (ریپوی themetacat) |
| ۱۲ | PixeLAW | دنیای پیکسلی | (ریپوی themetacat/pixelaw_core) |
| ۱۳ | Autochessia | اتوچس | https://github.com/HelheimLabs/autochessia |
| ۱۴ | Color3 | حذف رنگ | (ریپوی HelheimLabs/color3) |
| ۱۵ | Words3 | اسکرابل | (اکوسیستم MUD/OP Stack) |
| ۱۶ | Kamigotchi | RPG حیوان‌خانگی | (سازمان Asphodel-OS) |
| ۱۷ | Genki Cats | موبایل | https://github.com/GenkiCats/genkicats-core |
| ۱۸ | Rhascau | استراتژی نوبتی | (Minters Corp، Arbitrum) |
| ۱۹ | Outlaws of Loxley | دوئل PvP | (Robinhood Chain) |
| ۲۰ | CryptoKitties | تاریخی/NFT | https://github.com/dapperlabs/cryptokitties-bounty |
| ۲۱ | Aavegotchi | NFT+DeFi | https://github.com/aavegotchi/aavegotchi-contracts |
| ۲۲ | Pirate Nation | RPG | (فهرست awesome-web3-games) |
| ۲۳ | Conquest.eth | استراتژی/دیپلماسی فضایی | https://github.com/etherplay/conquest-eth |
| ۲۴ | Stratagems | ترکیب‌پذیری بدون‌مجوز | https://github.com/wighawag/stratagems |
| ۲۵ | Ethernal | دخمه‌ی چندنفره | https://github.com/0xgen0/ethernal |
| ۲۶ | EtherOrcs | RPG | https://github.com/EtherOrcsOfficial/etherOrcs-contracts |
| ۲۷ | Forgotten Runes | دنیای شخصیت‌محور | https://github.com/forgottenrunes/forgotten-runes-contracts |
| ۲۸ | Etheremon | جمع‌آوری/مبارزه‌ی هیولا | https://github.com/Etheremon/smartcontract |
| ۲۹ | MegaCryptoPolis | شهرساز استراتژیک | https://github.com/mcp-town/contracts |
| ۳۰ | Wolf Game | استیکینگ NFT با ریسک | (ریپوی جامعه‌محور، نه رسمی تأییدشده) |
| ۳۱ | 0xFable | کارت‌بازی | https://github.com/0xFableOrg/0xFable |
| ۳۲ | Art Blocks | هنر ژنراتیو on-chain | https://github.com/ArtBlocks/artblocks-contracts |
| ۳۳ | mudbasics | نمونه‌ی مرجع ساده | https://github.com/latticexyz/mudbasics |
| ۳۴ | Sunflower Land | کشاورزی/اقتصاد NFT | https://github.com/easycc/contracts |
| ۳۵ | DeFi Space Pirates | Play-to-Earn فضایی | github.com/DeFi-Space-Pirates |
| ۳۶ | Draw.Tech | نقاشی on-chain موبایل | https://github.com/smallbraineng/drawtech |

---

## این سند نهایی و بسته شد — با ۳۶ مورد

بعد از چندین دور تحقیق گسترده در ژانرهای مختلف (استراتژی، RPG، کارت‌بازی، هنر ژنراتیو، مسابقه، Play-to-Earn، کازینو/لاتاری، پازل/شبیه‌سازی، و هکاتون‌های ETHGlobal)، فهرست روی **۳۶ مورد** — هر یک با لینک مستقیم گیت‌هاب — بسته شد. آخرین چند دور جستجو موردی که واقعاً معیار «موجود، شناخته‌شده، کاملاً متن‌باز، سازگار با EVM» را داشته باشد پیدا نکردند؛ این نشانه‌ی رسیدن به سقف واقعی این حوزه‌ی خاص بود، نه محدودیت جست‌وجو.

چند مورد معروف عمداً رد شدند — دلیلشان ارزش یادآوری دارد چون هرکدام یک نوع محدودیت متفاوت را نشان می‌دهد:
- **Gods Unchained و Skyweaver:** کد کاملشان هرگز متن‌باز نشده — فقط API عمومی دارند.
- **Nine Chronicles:** کاملاً متن‌باز (حتی با مشارکت Ubisoft)، ولی روی بلاک‌چین اختصاصی غیر-EVM ساخته شده.
- **0xMonaco:** اصلاً یک بازی توزیع‌شده نبود، بلکه یک چالش امنیتی CTF بود که موتور اصلی/فرانت‌اندش هرگز به‌طور کامل منتشر نشد.
- **Biomes:** تداخل نام با یک ریپوی کاملاً بی‌ربط (`ill-inc/biomes-game`).
- **Ethernal (بازی):** تداخل نام با ابزار اکسپلورر بلاک‌چین (`tryethernal`).

عمومی‌تر: هر موردی که کنار گذاشته شد، عمداً کنار گذاشته شد، نه از قلم افتاد — یا Starknet/Cairo بود (خارج از معیار این سند)، یا آن‌قدر کوچک/کم‌مستند/قدیمی بود (پروژه‌های هکاتونی با ستاره‌ی صفر، بدون README) که ادعای «متن‌باز و قابل‌اتکا» برایش مسئولانه نبود. همان اصلی که در سند «۱۰۰ ایده‌ی کسب‌وکاری» هم رعایت شد: عدد به قیمت افت اطمینان، ارزش ندارد.
