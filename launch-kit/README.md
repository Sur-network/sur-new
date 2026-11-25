# کیت راه‌اندازی شبکهٔ Sur (v2.5) — فایل‌های پیشنهادی نود و genesis

> **وضعیت: پیشنهاد برای تصمیم مالک؛ نه آمادهٔ production.** این پوشه فایل‌های لازم برای بلند کردن نود ولیدیتور Besu 26.9.0 (QBFT، ارز بومی سورن) و ساخت genesis را پیشنهاد می‌کند. بخشی روی Besu واقعی آزموده شده و بخشی نه؛ هر مورد در این سند و در کامنت خود فایل با برچسب **VERIFIED / UNVERIFIED / OWNER** مشخص است. هیچ کلید خصوصی و هیچ `genesis.json` «نهایی» در این پوشه نیست (و نباید باشد).

> **وضعیت (۲۰۲۶-۱۱-۲۳):** متن این راهنما پس از کامیت‌های 11ff741 و 187c7dd با قراردادها هم‌تراز شد (۱۸۶ آزمون Hardhat در ۲۱ فایل). نتیجه‌های آزمایش ثبت‌شدهٔ این کیت (genesis آزمایشی، `verify`، نود تکی) برای نسخهٔ قرارداد همان زمان ثبت شده‌اند؛ اجرای دوباره برای قراردادهای تازه در این راهنما ثبت نشده است. مقدارهای `genesis-config.json` برای ثابت‌های تازه درست‌اند (`maxEntriesPerWindow = ۱`، `probationPeriod = ۶۰۴۸۰۰`، `slashBps = ۱۰۰`؛ اکنون ثابت‌های کدند و رأی‌پذیر نیستند)؛ کار پایین‌دست: بررسی‌های GenesisBuilder (`windowStart` ← `lastPaidActivationAt`؛ پیکربندی باید ۱ / ۶۰۴۸۰۰ / ۱۰۰ باشد) و همگام‌سازی نسخهٔ قراردادها و `SOURCES.json`.

مقادیر تصمیم‌گرفتهٔ مالک (دقیقاً همین‌ها استفاده شد): `chainId 262`، زمان بلاک 3 ثانیه (تولید)، `blockReward` 2 سورن، فورک `cancun`، حالت ولیدیتور-قرارداد (`validatorcontractaddress` = `ValidatorsRegistry` `0x3333…3333`)، `gasLimit` **45,000,000** (`0x2aea540`)، سقف اندازهٔ کد قرارداد **36 KiB = 36,864 بایت** (`config.contractSizeLimit`؛ `initCodeSizeLimit` گزینهٔ genesis نیست)، `min-gas-price` = 10^14 wei = 0.0001 سورن (از اسناد و همهٔ آزمون‌های قبلی). مرجع: `offchain-services/sur-genesis-builder-tool-spec.md` (بخش «پارامترهای تصمیم‌گرفته‌شدهٔ ظرفیت»)، README ابزار GenesisBuilder (`Deployments/GenesisBuilder/README.md`)، `technical-design/sur-onchain-offchain-architecture.md`، `sur-besu-live-test-brief-v4.md`، `testing-evidence/besu-live-test-v25b-2026-11-19/scripts` و `testing-evidence/soak-kit-v25`، `parties/22-validator.md`.

## ۱. فهرست فایل‌ها

| فایل | چیست | وضعیت |
|---|---|---|
| `genesis-config.json` | **ورودی** ابزار GenesisBuilder با همهٔ مقدارهای تصمیم‌گرفته؛ جای‌گیر برای آنچه فقط مالک/کمیته می‌داند (آدرس‌ها، زمان genesis، فهرست طلب‌ها). ابزار آن را عمداً رد می‌کند | ✅ رد شدن آزموده شد (بخش ۴-۱) |
| `genesis.TEST-ONLY.json` + `genesis.TEST-ONLY.config.json` + `genesis.TEST-ONLY.README.md` | genesis **آزمایشی** ساخته‌شده با ابزار واقعی از config آزمایشی (chain id 262025، داده‌های دورریختنی)؛ **هرگز برای شبکهٔ واقعی** | ✅ build و verify آزموده شد |
| `config.toml` | پیکربندی نود ولیدیتور Besu؛ هر گزینه با کامنت فارسی: هدف، منبع، وضعیت | ✅ با Besu 26.9.0 بلند شد (بخش ۴-۳) |
| `docker-compose.yml` | یک سرویس ولیدیتور از تصویر سنجاق‌شدهٔ `hyperledger/besu:26.9.0`؛ Prometheus اختیاری با `--profile monitoring` | ✅ اجرا شد (بخش ۴-۴) |
| `.env.example` | متغیرهای compose (مسیرها، پورت‌ها، IP عمومی، نام‌ها)؛ بدون راز | ✅ `docker compose config` معتبر |
| `static-nodes.json` | آرایهٔ enode همتاها؛ تحویلی `[]`. باید وجود داشته باشد (compose آن را mount می‌کند) | ✅ با فایل خالی آزموده شد |
| `bootnodes.example.txt` | فرمت enode، روش گرفتن enode نود، دو راه اتصال (static-nodes / bootnodes) | فرمت ✅؛ نام DNS در enode ✅؛ IP و enode واقعی bootnode (نود اول) هنوز نیست |
| `prometheus.yml` | scrape نود برای profile اختیاری | ✅ target `up` |
| `.gitignore`، `.gitattributes` | جلوگیری از commit شدن `.env`، کلیدها و `genesis.json`؛ ثابت‌ماندن پایان‌خط‌ها (LF) تا sha256 همه‌جا یکسان باشد | — |
| `SHA256SUMS` | sha256 همهٔ فایل‌های کیت؛ بررسی: `sha256sum -c SHA256SUMS` | — |

## ۲. چرا `genesis.json` در کیت نیست

genesis واقعی به مقادیری وابسته است که فقط مالک/کمیته تعیین می‌کند (آدرس 7 مؤسس، 15 عضو، 21 ردیف طلب، آدرس اپراتور ولیدیتور اول، زمان genesis) و باید در لحظهٔ راه‌اندازی **با آدرس‌ها و کلید واقعی** با `build` ساخته و با `verify` بررسی شود. فایل «`genesis.json`» در این کیت یا ساختگی می‌بود یا داده‌های آزمایشی را به‌جای نهایی نشان می‌داد؛ هر دو ممنوع‌اند. `.gitignore` هم عمداً `genesis.json` را نادیده می‌گیرد. نمونهٔ آزمایشی فقط با نام `genesis.TEST-ONLY.json` هست.

## ۳. ترتیب راه‌اندازی

1. **پر کردن `genesis-config.json`** (کپی کار شود؛ مالک/کمیته): همهٔ جای‌گیرهای `OWNER-FILL` (فهرست در بخش ۶). **نام ۱۵ عضو بنیاد** در قالب خالی (`""`) است و باید با نام حقوقی واقعی و نهایی پر شود: این نام دائمی روی زنجیره نوشته می‌شود و `FoundationMembers` تابع تغییر نام ندارد (فقط حذف و افزودن دوباره با مجمع فوق‌العاده)؛ ابزار `build` نام خالی را رد می‌کند، ولی «نام ساختگی» را نمی‌گیرد؛ پس هر نام را دوباره بخوانید و تأیید کنید. آدرس‌ها باید EIP-55 باشند؛ برای chain id 262 گزینهٔ `allowUnchecksummed` رد می‌شود. `network.genesisTimestamp` باید «از اکنون تا 72 ساعت بعد» باشد (ابزار در `build` این را اجرا می‌کند). **راهنمای زمان genesis:** آن را فقط **چند دقیقه** جلوتر از لحظهٔ `build` بگذارید، نه «روز راه‌اندازی»: `verify` تا رسیدن به این زمان منتظر می‌ماند و مهلت کل آن «زمان تا genesis + 90 ثانیه (مهلت تولید بلاک) + 15 دقیقه» است (`src/verify/verify.ts:79` در GenesisBuilder)؛ اگر زمان را روزها جلو بگذارید، `verify` با کلید واقعی همان‌قدر صبر می‌کند و بعد بلاک واقعی می‌سازد (زمان گذشته برای خود `verify` مشکلی ندارد، ولی `build` آن را رد می‌کند). این زمان فیلدهای زمانی Registry و DAO را هم لنگر می‌کند (مثلاً `boardTermEnd` پیش‌فرض = زمان genesis + 730 روز)، پس مقدارش **تصمیم مالک** است و باید پیش از `build` ثابت شود؛ نودهای تولیدی هم بعد از همین زمان بلاک می‌سازند.
2. **`build`** (روی ماشین ساخت؛ نیاز: Node 22، `npm install` در GenesisBuilder، Foundry `anvil` 1.8.5):
   ```bash
   cd Deployments/GenesisBuilder   # شاخهٔ v2.5-dev
   npx tsx src/cli.ts build --config <genesis-config.json پر شده> --out genesis.json --summary genesis.summary.json
   ```
   خلاصه (`genesis.summary.json`) را بخوانید: همهٔ هشدارها در آن است. برای production نباید هشدار «gasLimit نامحدود» یا `allowUnchecksummed` بیاید.
3. **`verify`** با نود واقعی Besu، **حالت Docker و بدون `--keep-container`** (طبق هشدارهای README ابزار: با کلید واقعی، نود تأییدکننده بلاک‌های معتبر «زنجیرهٔ واقعی» می‌سازد؛ حالت Docker شبکهٔ `--internal` دارد و پس از اجرا همه چیز را حذف و بررسی می‌کند):
   ```bash
   npx tsx src/cli.ts verify --config <همان config> --genesis genesis.json \
     --docker-image hyperledger/besu:26.9.0 --docker-prefix sur-genesis-verify- \
     --node-key-file <فایل کلید اپراتور ولیدیتور اول>
   ```
   خروجی باید `verify: all checks passed` باشد. بعد از اجرا بررسی باقی‌مانده **با برچسب** (نه فقط پیشوند نام؛ ابزار روی کانتینر، شبکه و حجم برچسب `sur.genesis-verify=1` می‌گذارد، حتی اگر فرایند سخت کشته شود):
   ```bash
   docker ps -a        --filter label=sur.genesis-verify=1
   docker network ls   --filter label=sur.genesis-verify=1
   docker volume ls    --filter label=sur.genesis-verify=1
   ```
   هر سه باید خالی باشند (چیزی ماند: `docker rm -f -v <نام>`، `docker network rm <نام>`، `docker volume rm <نام>`). **قاعده: نود تولیدی ولیدیتور اول تا زمانی که کانتینر `verify` نابود و این سه بررسی خالی نشده شروع نشود:** `verify` با همان کلید اپراتور بلاک می‌سازد و اجرای هم‌زمان با یک کلید در دو محل ممنوع است (بخش ۵).
4. **پخش `genesis.json` و sha256 آن** (sha256 از کانالی مستقل از فایل، مثلاً اعلام زنده در جلسهٔ مؤسسان). هر اپراتور: `sha256sum genesis.json` و مقایسه. همهٔ نودها بایت‌به‌بایت یک فایل را دارند.
5. **هر اپراتور**: `cp .env.example .env` و پر کردن (به‌ویژه `SUR_P2P_HOST`، `SUR_GENESIS_FILE`، `SUR_NODE_KEY_FILE`)؛ کلید اپراتور را در مسیر خارج از مخزن بگذارد (بخش ۵)؛ `docker compose config`؛ سپس **chown یک‌باره روی حجم داده** (کانتینر با `user: "1000:1000"` و بدون ریشه اجرا می‌شود و خودش chown نمی‌کند) و بعد `up`:
   ```bash
   docker compose up --no-start validator          # حجم، شبکه و کانتینر ساخته می‌شود، بدون اجرا
   docker run --rm --user 0 -v sur-validator-data:/data --entrypoint chown hyperledger/besu:26.9.0 -R 1000:1000 /data
   #   نام حجم = SUR_VOLUME_NAME در .env (پیش‌فرض sur-validator-data)؛ اگر به‌جای حجم نام‌دار bind mount گذاشتید: chown -R 1000:1000 <پوشه>
   docker compose up -d
   ```
   اگر chown را فراموش کنید نود بلند نمی‌شود: `Failed to start Besu: Data directory is not writable: /data` (آزموده شد؛ بعد از chown درست است). فایل کلید هم باید مالک uid 1000 باشد (`.env.example`، بخش ۵).
6. **اتصال همتاها**: enode هر نود را بگیرید (`bootnodes.example.txt`) و در `static-nodes.json` ولیدیتورهای دیگر بگذارید (یا طرح bootnode را تصمیم بگیرید)؛ فایروال: P2P فقط برای IPهای ولیدیتورها؛ RPC و متریک هرگز عمومی نشود. **هشدار (MEDIUM-B دور ۲): قواعد `ufw` پورت منتشرشدهٔ Docker را فیلتر نمی‌کنند.** Docker برای `ports:` خودش قواعد iptables می‌نویسد (DNAT در `nat` و پذیرش در `FORWARD`)؛ ترافیک به پورت منتشرشده از زنجیرهٔ `INPUT` (که `ufw allow/deny` روی آن کار می‌کند) رد نمی‌شود. پس روی Ubuntu حتی با `ufw default deny incoming` و بدون `ufw allow 30303`، پورت 30303 از اینترنت باز می‌ماند (رفتار شناخته‌شدهٔ Docker؛ خود `ufw` روی Ubuntu در این کیت **آزموده نشد**). راه‌های درست (همه **UNVERIFIED روی سرور اوبونتو**؛ فقط الگوی `DOCKER-USER` در زیر روی موتور لینوکس dind آزموده شد، برای TCP و UDP هر دو؛ روی `ufw`/Ubuntu واقعی هنوز نه):
   - **(الف) قاعدهٔ `DOCKER-USER`** (زنجیره‌ای که Docker هرگز پاک نمی‌کند و پیش از قواعد خودش ارزیابی می‌شود). نکتهٔ حیاتی: در `FORWARD` مقصد قبلاً DNAT شده است، پس `--dport` پورت **کانتینر** را می‌بیند، نه پورت میزبان؛ برای پورت میزبان باید `conntrack --ctorigdstport` گذاشت. نمونه (رابط عمومی `eth0`، IP ولیدیتور مجاز `V1`):
     **فهرست دستور کامل برای یک یا چند IP مجاز (دقیقاً به همین ترتیب؛ آزموده در dind با دو IP مجاز، TCP و UDP):** در `iptables -I` هر قاعده بالای زنجیره می‌نشیند؛ پس **اول DROP کلی** را بگذارید و **بعد** RETURN هر IP مجاز را؛ نتیجه این می‌شود که RETURNها بالای DROP‌اند.
     ```bash
     IF=eth0; PORT=30303        # رابط عمومی؛ PORT = SUR_P2P_PORT (پورت میزبان)
     CT="-m conntrack --ctorigdstport $PORT --ctdir ORIGINAL"
     # قدم ۱ — اول DROP کلی (مبدأ هرچه باشد)؛ TCP و UDP
     for P in tcp udp; do sudo iptables -I DOCKER-USER -i $IF -p $P $CT -j DROP; done
     # قدم ۲ — بعد RETURN برای هر IP ولیدیتور مجاز (V1 V2 ... = IPv4 همهٔ ولیدیتورهای دیگر)، باز هم با -I
     for V in V1 V2 V3; do for P in tcp udp; do sudo iptables -I DOCKER-USER -i $IF -s $V -p $P $CT -j RETURN; done; done
     # قدم ۳ — ترتیب را ببینید: همهٔ RETURNها باید بالاتر از هر دو DROP باشند
     sudo iptables -S DOCKER-USER
     ```
     (برای فقط **یک** IP مجاز، فرم کوتاه‌تر `-I DOCKER-USER -i $IF ! -s V1 -p tcp $CT -j DROP` (و `udp`) هم کار می‌کند؛ این فرم در دور ۲ و ۳ آزموده شد. فرم `! -s V1,V2` کار نمی‌کند: iptables آن را رد می‌کند، «`! not allowed with multiple source or destination IP addresses`»، و قاعده اصلاً ساخته نمی‌شود.)

     **هشدارهای ترتیب (همه در dind بازتولید شدند):**
     - **ممنوع:** اول `-I ... RETURN` برای IPها و بعد `-I ... DROP`. چون هر `-I` بالای زنجیره می‌نشیند، DROP کلی **بالای** RETURNها می‌افتد و **همهٔ ولیدیتورها از جمله IPهای مجاز قفل می‌شوند** (دیده شد: هر سه کلاینت، مجاز و غیرمجاز، روی TCP و UDP مسدود شدند). این همان ترتیب جملهٔ قبلی همین بخش بود (MEDIUM-2 دور ۳).
     - **`-A` فقط وقتی درست است که ترتیب RETURN-ها، بعد DROP-ها باشد «و» زنجیره آخرش `-j RETURN` همگانی نداشته باشد.** روی زنجیرهٔ خالی (Docker 29 با backend nf_tables در dind) `-A` به ترتیب «RETURN هر IP، بعد DROP» درست کار کرد. ولی اگر `iptables -S DOCKER-USER` یک `-A DOCKER-USER -j RETURN` همگانی نشان بدهد (این RETURN انتهایی را موتور Docker **قدیمی‌تر از ۲۸** خودش به زنجیره اضافه می‌کند؛ پس به **نسخهٔ موتور Docker** بستگی دارد، نه به backend ابزار iptables (legacy یا nf_tables)؛ Docker ۲۸ و بالاتر، مثل ۲۹ در dind ما، زنجیرهٔ خالی می‌سازد)، قواعد `-A` بعد از آن هرگز ارزیابی نمی‌شوند: در dind با چنین زنجیره‌ای کلاینت غیرمجاز **وارد شد** (بی‌صدا؛ هیچ خطایی نمی‌دهد). فهرست بالا (همه با `-I`، اول DROP) در هر دو حالت (زنجیرهٔ خالی و زنجیره با RETURN همگانی در انتها) درست کار کرد؛ پس همان را استفاده کنید.
     - قفل‌شدن اشتباهی: شمارهٔ قاعدهٔ بد را با `sudo iptables -L DOCKER-USER --line-numbers -n` بگیرید و با `sudo iptables -D DOCKER-USER <شماره>` حذف کنید (یا قواعد خودتان را با `-D` و همان مشخصات پاک کنید)؛ **این را از کنسول/SSH از IP مجاز بزنید، نه از راهی که با همین قاعده قطع می‌شود.**

     **آزمون اجباری بعد از اعمال (هر دو طرف):** (۱) از یک IP **مجاز** (هر ولیدیتوری که در فهرست گذاشتید، به‌ویژه تک‌تک آن‌ها) اتصال به `<IP این نود>:30303` باید برقرار شود (TCP: `nc -zv <IP> 30303`؛ برای UDP نتیجهٔ `nc -zvu` بی‌معنی است چون بدون پاسخ هم «موفق» گزارش می‌دهد؛ معیار درست پیرینگ واقعی است: `admin_peers` همتا را نشان بدهد)؛ (۲) از یک IP **غیرمجاز** واقعی (مثلاً یک ماشین بیرونی یا گوشی با اینترنت موبایل) همان اتصال باید ناموفق باشد. آزمون فقط از یک طرف کافی نیست: آزمون فقط از IP غیرمجاز، قفل‌شدن ولیدیتورها را نمی‌بیند (همین اشتباه ترتیب با آن «موفق» به نظر می‌رسید). قواعد با راه‌اندازی دوباره ماندگار نیستند؛ باید با `netfilter-persistent` یا با `/etc/ufw/after.rules` (بخش `*filter` و `:DOCKER-USER`، طبق مستندات Docker «Docker and ufw») ماندگار شوند (**UNTESTED**: هیچ‌کدام آزموده نشد). **ترتیب در `after.rules` برعکس دستورهای `-I` بالاست:** آن فایل خط‌به‌خط و به همان ترتیب فایل اعمال می‌شود (مثل `-A`، نه `-I`)، پس خطوط **RETURN** هر IP مجاز باید **پیش از** خطوط **DROP** کلی بنشینند؛ اگر ترتیب فرمان‌های `-I` را عیناً در فایل کپی کنید (اول DROP) همهٔ ولیدیتورها قفل می‌شوند؛ همچنین خط `-j RETURN` همگانی (اگر موتور Docker آن را اضافه کرده) باید بعد از DROPها بماند. `netfilter-persistent`/`iptables-save` ترتیب **زنده** زنجیره را همان‌طور که هست ذخیره می‌کند (پس اگر قواعد زنده با ترتیب درست ساخته شده باشند، ترتیب حفظ می‌شود؛ این هم **UNTESTED**). بعد از هر روش، ترتیب را با `sudo iptables -S DOCKER-USER` ببینید؛ پس از ماندگارکردن هم آزمون دو طرفه را بعد از یک reboot تکرار کنید. `ipset` جای دیگری برای چندین IP است و آزموده نشده.
   - **(ب) فایروال بیرون از میزبان** (security group / فایروال ابری یا فایروال سخت‌افزاری مرکز داده) که Docker به آن دست نمی‌زند: پورت 30303 TCP+UDP فقط از IPهای ولیدیتورها. ساده‌ترین و کم‌خطاترین گزینه است، اگر ارائه‌دهنده دارد.
   - **(ج) `SUR_P2P_BIND`/publish روی یک رابط مشخص** (مثلاً `SUR_P2P_BIND=<IPv4 یک رابط محلی میزبان>` به‌جای `0.0.0.0`): فقط می‌گوید روی کدام **آدرس مقصد** گوش دهد؛ هیچ فیلتر **مبدأ** نیست و به‌تنهایی کافی نیست. **معنای دقیق:** `SUR_P2P_BIND` باید یک آدرس IPv4 باشد که **روی یکی از رابط‌های خود میزبان** تنظیم شده است (پیش‌فرض `0.0.0.0` = همهٔ رابط‌های IPv4). روی ابرهایی با NAT یک‌به‌یک (IP عمومی روی خود میزبان نیست، فقط IP خصوصی دارد) باید IP **خصوصی** را بگذارید، نه IP عمومی؛ مقدار غیرمحلی با «cannot assign requested address» شکست می‌خورد (مشاهدهٔ بازبین دور ۴؛ ما دوباره اجرا نکردیم). `SUR_P2P_HOST` جداست و همان IP **عمومی تبلیغ‌شده** در enode می‌ماند (به همتاها اعلام می‌شود، جایی bind نمی‌شود)، و `p2p-interface` در `config.toml` (داخل کانتینر) باید `0.0.0.0` بماند؛ محدودکردن آدرس گوش‌دادن فقط با `SUR_P2P_BIND` روی publish میزبان انجام می‌شود.
   - **IPv6: نحو کوتاه پورت، DOCKER-USER را دور می‌زند (MEDIUM-1 دور ۳؛ در کیت اصلاح شد).** نحو کوتاه بدون آدرس (`"30303:30303"`) پورت را هم روی `0.0.0.0` و هم روی `[::]` منتشر می‌کند. وقتی کانتینر روی bridge IPv4-فقط است، ترافیک `[::]` را خود `docker-proxy` (پروسهٔ میزبان) می‌گیرد و به کانتینر می‌رساند؛ این مسیر از زنجیرهٔ `INPUT` می‌گذرد و از `FORWARD`/`DOCKER-USER` رد **نمی‌شود**. نتیجه: قاعدهٔ (الف) فقط IPv4 را می‌بندد و روی میزبانی که IPv6 عمومی دارد، P2P از IPv6 برای همه باز می‌ماند (بازبین دور ۳ دید؛ ما هم در dind بازتولید کردیم، بخش ۴-۶). **اصلاح:** `docker-compose.yml` حالا آدرس IPv4 صریح می‌گذارد (`"${SUR_P2P_BIND:-0.0.0.0}:${SUR_P2P_PORT:-30303}:30303/tcp"` و `/udp`؛ `SUR_P2P_BIND` در `.env.example`) و فقط روی IPv4 گوش می‌دهد؛ `SUR_P2P_BIND` را هرگز به مقدار IPv6 (مثلاً `::`) نگذارید. بعد از `up` بررسی کنید که گوش‌دادن روی IPv6 نیست: `ss -ltnu | grep 30303` نباید `[::]:30303` نشان دهد (در dind با `netstat` دیده شد). اگر IPv6 عمومی واقعاً لازم است:
     - **قواعد `ip6tables`** باید روی `INPUT` باشند (نه `DOCKER-USER`) و فقط وقتی لازم‌اند که IPv6 را خودتان جدا منتشر کنید؛ نمونهٔ آزموده در dind با نحو کوتاه (مبدأ مجاز `V6`، رابط `eth0`): `sudo ip6tables -I INPUT -i eth0 ! -s V6 -p tcp --dport 30303 -j DROP` و همان با `-p udp`. در dind کلاینت غیرمجاز روی TCP و UDP بسته شد و کلاینت مجاز وصل ماند؛ روی میزبان واقعی، چند IPv6 مجاز، و ماندگاری **UNVERIFIED**.
     - **یا فایروال بیرون از میزبان** (security group/فایروال ابری) که IPv4 و IPv6 را هر دو فقط برای IPهای ولیدیتورها باز کند؛ ساده‌ترین راه، اگر ارائه‌دهنده دارد.
     - (فرضیه، **UNVERIFIED**: چون مسیر `docker-proxy` از `INPUT` می‌گذرد، قواعد `ufw` برای IPv6 احتمالاً روی همین مسیر اثر دارند، برخلاف IPv4؛ این را آزمایش نکردیم و نباید بدون آزمون به آن تکیه کرد.)
   - **آزمون انجام‌شده (فقط الگوی (الف))،** روی موتور لینوکس (`docker:29.7.2-dind`، iptables 1.8.13 nf_tables، یک کانتینر داخلی با `-p 40404:30303` و دو IP مبدأ در شبکهٔ bridge (یکی مجاز، یکی نه)): ① قاعدهٔ `INPUT -p tcp --dport 30303 -j DROP` اتصال به پورت منتشرشده را **نبست** (مکانیزم عبور از `INPUT`، همان زنجیرهٔ ufw)؛ ② قاعدهٔ `DOCKER-USER -p tcp --dport 30303 -j DROP` بست؛ ③ با `-p 40404:30303`، قاعدهٔ `DOCKER-USER ... --dport 40404 -j DROP` **نبست** (چون DNAT شده) ولی `! -s <IP مجاز> -i eth0 -p tcp -m conntrack --ctorigdstport 40404 --ctdir ORIGINAL -j DROP` IP مجاز را راه داد و IP دیگر را بست. **UDP، IPv6 و چند IP مجاز در دور ۳ جداگانه آزموده شدند (بخش ۴-۶).** **آزموده نشد:** خود `ufw` و Ubuntu، رابط عمومی واقعی، ماندگاری بعد از reboot، `ipset`، و موتورهای با backend غیر iptables. **API `ADMIN` در RPC فعال است** (برای `admin_nodeInfo`/`admin_peers`) و `validator` در `host-allowlist` هست: هر کانتینر دیگری که روی شبکهٔ compose (`sur`) بگذارید با `Host: validator` به ADMIN می‌رسد؛ هیچ سرویس دیگری را روی این شبکه نگذارید (سرویس‌ها باید شبکهٔ جدا و RPC جدا بدون ADMIN داشته باشند).
7. **بررسی**: `eth_chainId` = `0x106` (262)، بلاک جدید هر 3 ثانیه، `qbft_getValidatorsByBlockNumber("latest")` = اپراتور ولیدیتور اول. **توجه:** در genesis فقط ولیدیتور اول `Active` است؛ شش مؤسس دیگر `Probation`‌اند تا `setOperator` + `recordActivation` (جریان Registry). قاعدهٔ حیاتی [`parties/22-validator.md`]: تعداد نود واقعی در حال اجرا همیشه ≥ تعداد ولیدیتور فعال؛ ولیدیتور فعال‌شده بدون نود، اجماع را قفل می‌کند.

## ۴. آنچه واقعاً آزموده شد (دستور و نتیجه؛ ۲۰۲۶-۱۱-۲۰)

محیط: Docker Desktop 29.7.2 روی Windows 11 (VM لینوکس)، تصویر `hyperledger/besu:26.9.0` (محلی؛ pull نشد)، `besu/v26.9.0/linux-x86_64/openjdk-java-25`، GenesisBuilder شاخهٔ `v2.5-dev`. همهٔ منابع Docker با پیشوند `sur25k-` و حذف‌شده.

### ۴-۱. `genesis-config.json` توسط ابزار رد می‌شود
`npx tsx src/cli.ts build --config launch-kit/genesis-config.json --out <scratch>` → **exit 1**، «failed validation (73 issues)» (آدرس‌های صفر، `genesisTimestamp` صفر، **۱۵ نام خالی عضو**، `shareWeight` صفر، ردیف طلب جای‌گیر، مجموع عرضه 20,000,000 به‌جای 53,311,000). نام اعضا عمداً `""` (خالی) است تا ابزار قالب پرنشده را رد کند؛ نام جای‌گیر «OWNER-FILL …» بررسی `name` ابزار را رد نمی‌کرد (یافتهٔ بازبین، HIGH-1) و برگردانده شد؛ هیچ فایل خروجی ساخته نشد.

### ۴-۲. genesis آزمایشی
build از config آزمایشی (فقط دو patch؛ `genesis.TEST-ONLY.README.md`): exit 0، 277 assertion گذشت، sha256 `14dae94d…af79`. `verify` Docker: `all checks passed`، 326 بررسی، head=2، و حذف کامل منابع. بلاک ساخته‌شده با Cancun فعال (`admin_nodeInfo.activeFork = Cancun`).

### ۴-۳. `config.toml`
نود تکی با `docker run` از تصویر pin‌شده و **همین فایل** (فقط یک substitute: `network-id=262` → `262025` چون genesis آزمایشی chain id 262025 دارد؛ و `--p2p-host` روی خط‌فرمان). مسیرها همان `/config`، `/secrets`، `/data` هستند. نتیجه:
- `eth_chainId` = `0x3ff89` (262025 از genesis)، `net_version` = 262025، بلاک‌های #1.. تولید شد، `qbft_getValidatorsByBlockNumber("latest")` = آدرس اپراتور آزمایشی، `web3_clientVersion` = `besu/v26.9.0/...`.
- بانر شروع: `Data storage: Bonsai`، `Sync mode: Full`، `RPC HTTP APIs: ETH,NET,WEB3,QBFT,ADMIN,TXPOOL`، `Target Gas Limit: 45M`.
- **UTF-8 فارسی در کامنت‌های TOML** بدون مشکل خوانده شد.
- هشدارهای بی‌ضرر شروع: `--rpc-ws-host`/`--graphql-http-host` ignored (متغیر محیطی تصویر)، `Forcing --bonsai-limit-trie-logs-enabled=false` (FULL+Bonsai)، `Forcing price bump ... zero basefee network`. هشدار `--sync-min-peers is ignored in FULL sync-mode` در soak-kit بود و از این فایل **حذف شد**.
- `host-allowlist`: Host دیگر → 403؛ `/metrics` روی `127.0.0.1` → 200 با متریک `besu_*`.
- **نام DNS در enodeِ bootnode (۲۰۲۶-۱۱-۲۵، `offchain-services/boot-node-kit/dns-enode-test.sh`، ۶ از ۶):** `bootnodes=["enode://<کلید>@boot-node.surnet.org:30303"]` فقط با `--Xdns-enabled=true` و `--Xdns-update-enabled=true` پذیرفته می‌شود (در `docker-compose.yml` هستند؛ بدون آن‌ها «Invalid bootnode … Invalid enode URL syntax»)؛ با آن‌ها نود به bootnode وصل شد و بعد از عوض‌شدن IP آن (همان کلید) دوباره پیدایش کرد. آزموده در شبکهٔ docker با DNS داخلی؛ DNS واقعی با TTL و نام DNS در `--p2p-host` UNVERIFIED؛ پرچم‌ها آزمایشی‌اند.
- **تأیید فرمت‌ها:** `bootnodes=[…]` آرایه روی لینوکس پذیرفته شد («Resolved 1 bootnodes»؛ به bootnode واقعی وصل نشدیم)؛ `data-storage-format="FOREST"` هم بلند شد و بلاک ساخت؛ `--p2p-host` روی خط‌فرمان، مقدار فایل را بازنویسی می‌کند (enode آدرس جدید را نشان داد).

### ۴-۴. `docker-compose.yml`
`docker compose --env-file <test.env> -p sur25k -f docker-compose.yml config` معتبر؛ `.env.example` هم معتبر؛ بدون متغیرهای لازم (`SUR_P2P_HOST`، `SUR_GENESIS_FILE`، `SUR_NODE_KEY_FILE`) با پیام فارسی خطا می‌دهد. `up -d --pull never` روی genesis آزمایشی:
- کانتینر `healthy` (healthcheck خودمان)، بلاک‌ها تولید می‌شد، `eth_chainId` از `127.0.0.1:18570` = `0x3ff89`.
- **healthcheck:** تصویر `curl`/`wget`/`nc`/`socat` ندارد و `bash` 5.2 و `timeout` دارد (بررسی شد)؛ از `bash` + `/dev/tcp` + `Host: localhost` استفاده شد؛ با chainId اشتباه exit 1 می‌دهد (آزموده)، با درست exit 0. این جایگزین healthcheck خود تصویر (`[ -f /tmp/pid ]`) است.
- RPC و متریک روی `127.0.0.1` میزبان: از IP شبکهٔ خود میزبان وصل نشد (`curl` کد 000). P2P روی `0.0.0.0`.
- `docker inspect` (نسخهٔ اصلاح‌شده): `privileged=false`، `User=1000:1000`، `CapDrop=[ALL]` و `CapAdd=[]` (پنج قابلیت قبلی فقط برای entrypoint ریشه بود)، `no-new-privileges`، `restart=unless-stopped`، لاگ `json-file` سقف 50m × 10. Prometheus هم `CapDrop=[ALL]` است و با آن بالا آمد (target `up`، بدون «permission denied»).
- **توقف (HIGH-2، آزمون دوباره روی Besu 26.9.0 با `user: "1000:1000"` و حجم chown‌شده):** نسخهٔ قبلی (ریشه) هر `stop` را با SIGKILL می‌کشت: entrypoint تصویر با `su` به کاربر `besu` می‌رود و `su` با SIGTERM پروسهٔ Besu را می‌کشد؛ مقایسهٔ زنده: `docker stop -t 60` در 2 ثانیه، کد 143، فقط 8 خط `Shutdown-Hook` و آخر لاگ `Session terminated, killing shell... ...killed.`؛ پس `stop_grace_period: 60s` بی‌اثر بود. با `user: "1000:1000"` پروسهٔ اول کانتینر خودِ `java` است (`/proc/1/cmdline`) و بدون `su`: `docker compose stop` در حدود 2 ثانیه تمام شد، لاگ تا `Stopping eth Subprotocol` → `eth Subprotocol stopped.` → `Network stopped.` → `Shutting down Auto transaction logs caching service.` → `No NAT environment detected…` (hook کامل، بدون «killed»). **کد خروج هنوز 143 است، نه 0:** این کد معمول JVM پس از SIGTERM است (128+15) و نشانهٔ SIGKILL (137) نیست؛ `OOMKilled=false`. داده سالم ماند: بلاک 0x21 (33) پیش از توقف، پس از `start` هش همان بلاک بایت‌به‌بایت یکسان، زنجیره ادامه یافت (0x26) بدون ERROR/corrupt؛ `docker compose restart` هم چند ثانیه. آزمون روی Docker Desktop (VM لینوکس) بود؛ روی سرور اوبونتو انجام نشده (UNVERIFIED).
- **bind mount با نحو بلند و `create_host_path: false`** (compose): روی موتور لینوکس (`docker:dind`) با مسیر ناموجود خطای `bind source path does not exist` می‌دهد و پوشه نمی‌سازد (آزموده). روی Docker Desktop ویندوز همان مسیر ناموجود را **به‌صورت پوشه ساخت** (گزینه آنجا اثر ندارد؛ فقط محیط آزمون، نه تولید لینوکس).
- profile `monitoring`: Prometheus (تصویر محلی `prom/prometheus:v3.13.4`، pull نشد) target `validator:9545` = `up`، `ethereum_blockchain_height` = 110.
- پایان: `docker compose down -v`؛ کانتینر، شبکه و volume با پیشوند `sur25k` باقی نماند.

### ۴-۵. آزمون رفتار گزینه‌های گاز (روی چند genesis دورریختنی در scratch؛ داخل کیت نیست)
genesis دورریختنی با `gasLimit` 40,000,000 و بلاک 3 ثانیه (ساخته با همین ابزار) و یک حساب آزمایشی با 100 سورن:

| آزمون | نتیجه |
|---|---|
| `target-gas-limit=45000000` | سقف بلاک بالا رفت: #1 = 40,039,061، #5 = 40,195,687، #12 = 40,471,258 (+parent/1024 در هر بلاک) |
| بدون این گزینه | سقف 40,000,000 ثابت ماند |
| `target-gas-limit=35000000` | پایین آمد: #1 = 39,960,939، #7 = 39,727,371 |
| genesis آزمایشی (`0x1fffffffffffff`) + target 45M | آهسته پایین می‌آید: #1 = 8,998,403,161,718,785، #9 = 8,928,342,951,574,557 |
| تراکنش legacy با gasPrice = 1e14 / type‑2 با maxFee=prio=1e14 | پذیرفته و استخراج شد؛ gasUsed 21000، `effectiveGasPrice` = 1e14؛ `eth_gasPrice` = `0x5af3107a4000` (=1e14) |
| تراکنش 1e13 (**کمتر از حداقل**) با تنظیم پیش‌فرض | **پذیرفته و استخراج شد** (از RPC همین نود = «محلی» ⇒ معاف از min-gas-price) |
| 1e13 با `tx-pool-no-local-priority=true` فقط | پذیرفته شد ولی **در 15 ثانیهٔ انتظار استخراج نشد** (در `txpool_besuTransactions` ماند) |
| 1e13 با `tx-pool-min-gas-price=1e14` فقط | هنوز استخراج شد (کافی نیست) |
| 1e13 با هر دو | رد با خطای RPC `-32009 Gas price below configured minimum gas price` |
| **HIGH-3** بدون `min-priority-fee`: `eth_maxPriorityFeePerGas` / `eth_gasPrice` / `eth_feeHistory` | `0x0` / `0x5af3107a4000` (1e14) / پاداش‌ها `0x0`؛ `viem.prepareTransactionRequest` برای type-2: `maxFeePerGas=0`، `maxPriorityFeePerGas=0` ⇒ RPC رد کرد؛ تراکنش دستی type-2 با `maxFee=1e14` و `priority=0`: هش گرفت، در `txpool_besuTransactions` ماند و در 40 ثانیه **استخراج نشد** |
| با `min-priority-fee=100000000000000` (زنجیرهٔ تازه، همان genesis، یک نود) | `eth_maxPriorityFeePerGas` = `0x5af3107a4000`؛ `viem.prepareTransactionRequest`: `maxFee=prio=1e14`؛ تراکنش در بلاک 15 در 2٫0 ثانیه استخراج شد، `gasUsed` 21000، `effectiveGasPrice` = 1e14؛ `eth_feeHistory` پاداش آن بلاک `0x5af3107a4000`. هشدار گزینهٔ ناشناخته در لاگ نبود |
| با `min-priority-fee` ولی تراکنش دستی با `priority=0` و `maxFee=1e14` | **هنوز** هش می‌گیرد و استخراج نمی‌شود (گزینه فقط قیمت پیشنهادی RPC را درست می‌کند، تراکنش با priority صریح 0 را رد نمی‌کند) |
| **MEDIUM-A (دور ۲، بازبین مستقل؛ ما خودمان این ردیف را اجرا نکردیم)** با `min-priority-fee`: `eth_feeHistory` برای بلاک‌های **خالی** | پاداش‌ها همچنان `0x0`. یعنی `min-priority-fee` فقط `eth_maxPriorityFeePerGas` را درست می‌کند، نه fee history. کیف‌پول/dAppی که priority را از fee history تخمین بزند یا tip ثابت (مثلاً 1–1.5 gwei) بگذارد روی زنجیرهٔ کم‌تراکنش می‌تواند تراکنش گیرکرده بسازد. **VERIFIED (viem + حساب محلی):** مسیر `eth_maxPriorityFeePerGas`. **UNVERIFIED:** کیف‌پول‌های injected مثل MetaMask پشت wagmi |

### ۴-۶. آزمون فایروال و انتشار IPv4-فقط (دور ۳؛ ۲۰۲۶-۱۱-۲۰)

محیط: `docker:29.7.2-dind` (موتور لینوکس داخلی، iptables 1.8.13 nf_tables؛ کانتینر `sur25k-dind`، پس از آزمون حذف شد)، تصویر `busybox:1.37.0`. شبکهٔ آزمون `t6` با IPv4 `10.77.0.0/24` و IPv6 ULA `fd00:25:77::/64`؛ سه کلاینت: `cA` (10.77.0.10، مجاز)، `cA2` (10.77.0.11، مجاز دوم)، `cB` (10.77.0.20، غیرمجاز). سرور: یک کانتینر busybox روی bridge پیش‌فرض (فقط IPv4) با شنوندهٔ `nc` روی TCP **و** UDP پورت 30303 داخل کانتینر، منتشرشده روی پورت میزبان 40404. کلاینت‌ها از طریق آدرس میزبان روی شبکهٔ خودشان (`10.77.0.1` برای IPv4، `fd00:25:77::1` برای IPv6) وصل می‌شوند و قاعده‌ها روی رابط bridge همین شبکه (`-i br-…`) بودند. «REACHABLE» یعنی پاسخ شنونده برگشت. **نکته:** این آزمون با شنوندهٔ ساده بود، نه با Besu واقعی.

| آزمون | نتیجه |
|---|---|
| نحو کوتاه `-p 40404:30303/tcp` و `/udp`، بدون قاعده | `docker port`: هم `0.0.0.0:40404` و هم `[::]:40404`؛ `netstat`: گوش‌دادن روی `0.0.0.0:40404` و `:::40404` (TCP و UDP)؛ هر سه کلاینت روی IPv4 و IPv6، TCP و UDP: REACHABLE |
| نحو کوتاه + قاعدهٔ `DOCKER-USER ! -s 10.77.0.10 ... --ctorigdstport 40404 --ctdir ORIGINAL -j DROP` (TCP و UDP) | IPv4: `cA` REACHABLE، `cA2` و `cB` مسدود. **IPv6: `cB` (غیرمجاز) همچنان REACHABLE روی TCP و UDP** ⇒ دور زدن DOCKER-USER بازتولید شد |
| انتشار IPv4-فقط `-p 0.0.0.0:40404:30303/tcp` و `/udp` + همان قاعده | `docker port` و `netstat` فقط `0.0.0.0:40404` (هیچ `:::40404`)؛ IPv4: `cA` REACHABLE، `cA2`/`cB` مسدود؛ IPv6: هر دو کلاینت (حتی `cA`) بدون پاسخ (اتصال رد می‌شود؛ `nc` با کد 1 خارج شد) ⇒ مسیر IPv6 بسته است، P2P فقط IPv4 |
| انتشار روی یک آدرس مشخص `-p 10.77.0.1:40404:30303` | `netstat` فقط `10.77.0.1:40404`؛ IPv6 از `cB` بدون اتصال (شکل `SUR_P2P_BIND=<IP>`) |
| جایگزین IPv6: نحو کوتاه + `ip6tables -I INPUT -i <br> ! -s fd00:25:77::10 -p tcp --dport 40404 -j DROP` (و `udp`) | قبل: `cA` و `cB` REACHABLE؛ بعد: `cA` REACHABLE، `cB` مسدود، روی TCP و UDP |

**چند IP مجاز و ترتیب قواعد `DOCKER-USER` (MEDIUM-2 دور ۳؛ همان تنظیمات، پورت 40404، دو IP مجاز `cA` و `cA2` و یک غیرمجاز `cB`، TCP و UDP، نتیجه به‌صورت `cA cA2 cB`):**

| آزمون | نتیجه |
|---|---|
| بدون قاعده | هر سه REACHABLE (TCP و UDP) |
| `-I RETURN` برای دو IP، بعد `-I DROP` (ترتیب ممنوع) | `iptables -S`: DROPها بالا؛ **هر سه مسدود، از جمله دو IP مجاز** (قفل‌شدن ولیدیتورها) |
| `-A`: RETURN هر IP، بعد DROP، روی زنجیرهٔ خالی | `cA` و `cA2` REACHABLE، `cB` مسدود |
| **فهرست پیشنهادی:** `-I DROP` (tcp، udp)، بعد `-I RETURN` برای هر IP و پروتکل، روی زنجیرهٔ خالی | `iptables -S`: چهار RETURN بالا، دو DROP پایین؛ `cA` و `cA2` REACHABLE، `cB` مسدود (TCP و UDP) |
| همان فهرست پیشنهادی روی زنجیره‌ای که از قبل `-A DOCKER-USER -j RETURN` همگانی دارد | همان نتیجه (RETURNها، DROPها، سپس RETURN همگانی)؛ `cB` مسدود، دو IP مجاز REACHABLE |
| `-A` (RETURNها، DROPها) روی زنجیره‌ای که از قبل `-j RETURN` همگانی دارد | **هیچ‌کدام مسدود نشد** (`cB` هم REACHABLE)؛ قواعد بعد از RETURN همگانی هرگز ارزیابی نمی‌شوند |
| `! -s 10.77.0.10,10.77.0.11` | iptables خطا می‌دهد (`! not allowed with multiple source or destination IP addresses`)؛ قاعده ساخته نمی‌شود و همه باز می‌ماند |

آزموده نشد: میزبان واقعی، `ufw`/Ubuntu، ماندگاری، `ipset`، IPهای واقعی بیرونی (فقط IPهای bridge)، و ترافیک خروجی نود به همتاها (فقط ورودی آزموده شد).

**آزموده شد (VERIFIED، فقط خروجی `docker compose config`):** `docker compose config` (با و بدون `--profile monitoring`، و با `.env.example`) معتبر ماند و `host_ip: 0.0.0.0` را برای 30303/tcp و /udp نشان داد؛ با `SUR_P2P_BIND=192.0.2.5` مقدار `host_ip` همان شد؛ RPC و متریک روی `127.0.0.1` ماندند.

**آزموده نشد (UNVERIFIED):** Besu واقعی پشت همین انتشار (peering/discovery واقعی روی IPv4 با خط `ports:` جدید؛ فقط `docker compose config` و شنوندهٔ ساده)، میزبان واقعی با IPv6 عمومی، `ufw`/Ubuntu، `ip6tables` روی رابط عمومی واقعی، ماندگاری قواعد، `daemon.json` با `ipv6: true` یا `ip6tables: true`.

## ۵. مدیریت کلید (اصول؛ طراحی پروژه)

- **هیچ کلیدی در مخزن/تصویر/لاگ/`.env` نیست**؛ `.env` فقط «مسیر فایل کلید» دارد (`.gitignore` هم `.env`، `*.key`، `secrets/` را نادیده می‌گیرد). کیت هیچ کلید خصوصی ندارد (کلیدهای آزمایشی در scratch ساخته و پس از آزمون نابود شدند).
- **کلید نود = کلید اپراتور** (آدرس آن همان است که در `ValidatorsRegistry` ثبت می‌شود)، جدا از **کلید مالک که هرگز روی نود نمی‌آید**. یک نود، یک کلید؛ اجرای هم‌زمان با یک کلید در دو محل ممنوع (`parties/22-validator.md` ۵٫۱).
- **اصلاح ۲۰۲۶-۱۱-۲۲ (تصمیم مالک): کلید نود با Vault نگهداری نمی‌شود.** Besu 26.9.0 کلید نود را فقط از فایل می‌خواند (`node-private-key-file`) و امضای بلاک از راه دور (Vault Transit یا KMS) ندارد؛ پس کلید اپراتور باید به‌صورت فایل روی خودِ نود باشد. هر ولیدیتور کلید نود خودش را نگه می‌دارد (نه بنیاد). حداقل‌ها: فایل با مجوز `0400` و uid اختصاصی بدون ورود (بند پایین)، دیسک رمزشده، پشتیبان رمزشده و آفلاین، و هرگز در مخزن/تصویر/لاگ. کلیدهای **سرویس‌ها** (verifier، distributionOracle، identityOracle و HMAC) جدا هستند و در **SurKMS** می‌مانند (`offchain-services/sur-kms-spec.md`)؛ Vault/OpenBao کنار گذاشته شد. هر ولیدیتور می‌تواند برای نگهداری فایل کلید از ابزار خودش استفاده کند، به‌شرط آنکه فایل نهایی روی نود با همین مجوزها باشد.
- مجوز فایل روی لینوکس: کانتینر با `user: "1000:1000"` اجرا می‌شود؛ کلید باید **مالک uid 1000** و `0400` باشد (مالک root یا uid 1001 = Besu با خطای گمراه‌کنندهٔ «Supplied file does not contain valid keyPair» و حلقهٔ crash؛ مالک root با `0400` هم همین پیام «does not contain valid keyPair» را داد: بازبین دور ۲ بازتولید کرد؛ متن «Private key cannot be loaded from file» را سازندهٔ قبلی در آزمون خودش برای root/0400 دیده بود و بازبین آن را بازتولید نکرد، پس به آن تکیه نکنید؛ مالک 1000 درست بارگذاری شد). **این رفتار مالکیت/مجوز روی سرور اوبونتو آزموده نشده** (Docker Desktop مجوزهای bind mount را مثل لینوکس اعمال نمی‌کند؛ آزمون‌های مالکیت با حجم Docker انجام شد). حجم داده هم باید یک‌بار `chown 1000:1000` شود (بخش ۳).
- **uid اختصاصی برای نود (توصیه؛ LOW-2 دور ۲).** uid 1000 همان کاربر ورود پیش‌فرض روی بسیاری از تصویرهای Ubuntu cloud (`ubuntu`) است؛ با کلید مالک 1000 و `0400` هر کسی با آن حساب SSH کلید اپراتور را می‌خواند. **توصیه:** برای نود یک uid اختصاصی بدون ورود (مثلاً `10001`، که با هیچ کاربر میزبان تداخل نکند) بگیرید. **پیش‌فرض آزموده‌شدهٔ کیت همان `1000:1000` می‌ماند** (همهٔ آزمون‌های بخش ۴ با آن بود)؛ تغییر uid یعنی چهار تغییر هماهنگ:
  1. `docker-compose.yml`: `user: "10001:10001"`؛
  2. حجم داده: `docker run --rm --user 0 -v sur-validator-data:/data --entrypoint chown hyperledger/besu:26.9.0 -R 10001:10001 /data` (یا `chown -R 10001:10001 <پوشه>` برای bind mount)؛
  3. فایل کلید: `sudo chown 10001:10001 /opt/sur/secrets/node.key && sudo chmod 0400 /opt/sur/secrets/node.key`؛
  4. فایل‌های بخش بعد (LOW-3) برای همین uid خوانا باشند.
  **آزموده شد (Docker Desktop، موتور لینوکس؛ حجم‌های نام‌دار با مالکیت واقعی ext4، نه bind mount ویندوز):** با `--user 10001:10001`، `--cap-drop ALL`، `no-new-privileges`، حجم‌های `/config` (فقط‌خواندنی)، `/secrets` (کلید `0400`) و `/data` همه مالک 10001، Besu 26.9.0 بالا آمد (`JSON-RPC service started`)، PID 1 خود `java` با uid 10001 بود. سازندهٔ این بخش فقط راه‌اندازی را دید (بدون بلاک، چون کلید آزمایشی ولیدیتور نبود)؛ **بازبین دور ۳ تأیید کرد که با uid 10001 نود بلاک هم تولید می‌کند** (ما خودمان آن را اجرا نکردیم). shutdown تمیز و نگه‌داشت داده با uid 10001 آزموده نشد (UNVERIFIED؛ آزمون 1000:1000 در بخش ۴-۴ است).
- **فایل‌های پیکربندی باید برای uid کانتینر خوانا باشند (LOW-3 دور ۲).** `config.toml`، `genesis.json` و `static-nodes.json` فقط‌خواندنی mount می‌شوند ولی باید برای uid کانتینر قابل‌خواندن باشند (مجوز `0644` با هر مالکی، یا مالک همان uid). **آزموده شد (همان آزمون حجم نام‌دار، uid 10001):** هر یک از سه فایل با مالک `root:root` و مجوز `0600` Besu را با کد خروج 2 می‌اندازد: `config.toml` → «Unable to read TOML configuration, file not found.» (گمراه‌کننده: فایل هست ولی خوانا نیست)؛ `genesis.json` → «Failed to start Besu: Unable to load genesis file ... (Permission denied)»؛ `static-nodes.json` → «Access denied to static nodes file ... Ensure static nodes file and node data directory have correct permissions». (حالت درست با 0644 در آزمون بالا آمد.) روی bind mount سرور اوبونتو آزموده نشد.
- سه کلید اوراکل (`distributionOracle`، `verifier`، `identityOracle`) جزو این کیت نیستند و هرگز نباید باشند؛ فقط آدرس‌هایشان در `genesis-config.json` (مقدار مرجع `SurAddresses.sol`؛ OWNER تأیید کند).

## ۶. تصمیم‌گرفته / جای‌گیر / UNVERIFIED

**تصمیم‌گرفته (در فایل‌ها اعمال شد):** chainId 262؛ زمان بلاک 3 ثانیه؛ blockReward 2 سورن؛ fork cancun؛ حالت contract روی `0x3333…3333`؛ gasLimit 45,000,000؛ `contractSizeLimit` 36,864؛ `min-gas-price` 1e14.

**جای‌گیر `OWNER-FILL` در `genesis-config.json`:** `network.genesisTimestamp`؛ `validatorsRegistry.firstValidator.owner/operator`؛ شش `otherFounders`؛ 5 عضو `validatorsBoard.initialBoardMembers`؛ 15 عضو `foundationMembers.members` (نام، حساب، `shareWeight`؛ **نام حقوقی واقعی و نهایی را مالک بنویسد: نام روی زنجیره دائمی است و `FoundationMembers` تابع تغییر نام ندارد؛ فقط حذف و افزودن دوباره با مجمع فوق‌العاده؛ نام خالی را ابزار رد می‌کند**)؛ `foundationDAO.initialBoard` (5 اصلی + 2 علی‌البدل) و `initialInspector` (و اختیاری `initialOfficers`)؛ ردیف‌های `genesisClaimsVault.claims` (21 ردیف)؛ تأیید سه آدرس اوراکل.

**OWNER در سایر فایل‌ها:** IP عمومی هر ولیدیتور (`SUR_P2P_HOST`)؛ طرح bootnode (✅ `discovery-enabled=true` تصمیم مالک ۲۰۲۶-۱۱-۲۵)؛ **محدودکردن همتاها (`net-restrict` یا permissioning؛ بخش ۸)**؛ پذیرفتن دو خط `tx-pool-*` (بخش ۷-۱) و `min-priority-fee=1e14` (بخش ۷-۷؛ روی همهٔ نودها از جمله RPC؛ به‌علاوهٔ تصمیم دربارهٔ تخمین priority در dApp چون `eth_feeHistory` درست نمی‌شود)؛ نگهداری و تحویل کلید نود؛ سخت‌افزار (`parties/22-validator.md` ۵٫۱: «حداقل سخت‌افزار هنوز نیست»)؛ تنظیم حافظه JVM و محدودیت منابع (در compose کامنت شده).

**UNVERIFIED (هنوز آزموده نشده):** رفتار چند ولیدیتور با `target-gas-limit` متفاوت؛ اتصال به bootnode واقعی؛ مجوزهای فایل روی لینوکس؛ `sync-mode` به‌جز FULL با QBFT؛ رفتار RPC/تراکنش‌های رسیده از همتا (p2p) برای قیمت زیر حداقل؛ رفتار زیر بار بلاک‌های واقعاً پر؛ **تخمین priority در کیف‌پول‌های injected (MetaMask پشت wagmi) با `eth_feeHistory` صفر؛** نگهداری فایل کلید نود (دیسک رمزشده، پشتیبان)؛ آماده بودن NAT/فایروال واقعی؛ شبکهٔ چندمیزبانه.

## ۷. یافته‌ها و تعارض‌های مهم با انتظار (بدون لاپوشانی)

1. **`min-gas-price` برای تراکنش‌های محلی (از RPC همان نود) اعمال نمی‌شود.** با تنظیم پیش‌فرض Besu، تراکنش با 1e13 (کمتر از حداقل 1e14) از RPC نود ولیدیتور پذیرفته و استخراج شد. با `tx-pool-no-local-priority=true` + `tx-pool-min-gas-price=100000000000000` رد می‌شود (خطای `-32009`)؛ هر دو لازم‌اند. این دو خط در اسناد و آزمون‌های قبلی نبود؛ در `config.toml` گذاشته شدند. RPC ولیدیتور فقط محلی است، پس خطر اصلی کم است، ولی تصمیم پذیرش با مالک. همچنین `min-gas-price` تنظیم «محلی هر نود» است؛ پروتکل تراکنش ارزان‌تر را رد نمی‌کند (ولیدیتوری که کمتر بگذارد می‌پذیرد) ⇒ همهٔ ولیدیتورها باید یکسان بگذارند (سند: «هیچ مسیر رأی ندارد»).
2. **`target-gas-limit` در QBFT کار می‌کند** (برخلاف ابهام اسناد) و **با genesis = 45M بی‌اثر است**؛ پس `gasLimit` بعد از راه‌اندازی بدون genesis جدید قابل تغییر است (ولیدیتورها با مقدار یکسان)، حداکثر ≈ parent/1024 در هر بلاک. ولی این فقط با یک ولیدیتور آزموده شد؛ سند بخش ظرفیت می‌گفت «برای gasLimit راستی‌آزمایی نشده» — اکنون برای یک ولیدیتور راستی‌آزمایی است، برای چند ولیدیتور نه. هشدار: با `genesis.TEST-ONLY.json` (سقف نامحدود) و `target 45M` سقف به‌تدریج پایین می‌آید؛ آن genesis برای این‌کار نیست.
3. **`sync-min-peers=1` در soak-kit در حالت FULL بی‌اثر است** (Besu هشدار می‌دهد)؛ از `config.toml` حذف شد.
4. **`--bootnodes` ویندوزی خطا داد (سند)؛ روی لینوکس/Docker سینتکس پذیرفته شد** ولی اتصال به bootnode واقعی آزموده نشد؛ روش آزموده‌شدهٔ پروژه `static-nodes.json` است.
5. **entrypoint تصویر root است و کاربر را با `su` عوض می‌کند؛ `su` با SIGTERM پروسهٔ Besu را SIGKILL می‌کند** (یافتهٔ بازبین مستقل، HIGH-2، و در آزمون دوباره تأیید شد): پس هر توقف JVM را نیمه‌کاره می‌کشت و `stop_grace_period` بی‌اثر بود. راه‌حل: `user: "1000:1000"` (entrypoint در حالت غیرریشه `su` را رد می‌کند) + chown یک‌بارهٔ حجم داده + حذف `cap_add`؛ با آن shutdown hook کامل می‌شود (کد خروج 143 = رفتار عادی JVM پس از SIGTERM، نه SIGKILL). بخش ۳ و ۴-۴.
6. **Prometheus:** Besu `host-allowlist` را روی `/metrics` هم اعمال می‌کند و Prometheus اجازهٔ تغییر Host نمی‌دهد؛ برای همین نام سرویس `validator` به `host-allowlist` اضافه شد (بدون آن 403).
7. **`min-priority-fee` (HIGH-3؛ یافتهٔ بازبین مستقل، با آزمون دوباره تأیید شد).** `zeroBaseFee` در genesis فعال است، پس قیمت مؤثر تراکنش فقط priority fee است. بدون `min-priority-fee` در `config.toml`، `eth_maxPriorityFeePerGas` مقدار `0` می‌دهد (در حالی که `eth_gasPrice` برابر 1e14 است) و کتابخانه‌هایی مثل viem/wagmi که priority را از همین RPC می‌گیرند تراکنش type-2 با priority 0 می‌سازند: یا رد می‌شود یا (اگر maxFee دستی ≥ 1e14 باشد) هش می‌گیرد ولی هرگز استخراج نمی‌شود و nonceهای بعدی همان حساب را هم می‌بندد. `min-priority-fee=100000000000000` (1e14، برابر `min-gas-price`) **`eth_maxPriorityFeePerGas` را** درست می‌کند (VERIFIED با viem + حساب محلی). **این گزینه باید روی هر نود گذاشته شود، از جمله نودهای RPC سرویس‌ها و dApp** (آن‌ها قیمت پیشنهادی را به کیف‌پول‌ها می‌دهند) و روی همهٔ ولیدیتورها یکسان باشد.

   **محدودیت‌ها (یکی آزموده، یکی گزارش بازبین دور ۲):**
   - **`eth_feeHistory` درست نمی‌شود (MEDIUM-A):** پاداش‌های fee history برای بلاک‌های **خالی** همچنان `0x0` می‌ماند. هر کیف‌پول/کتابخانه‌ای که priority را از fee history تخمین بزند، یا tip ثابتی بسیار کمتر از 1e14 بگذارد (مثلاً 1–1.5 gwei)، روی زنجیرهٔ کم‌تراکنش tip ≈ 0 می‌گیرد و تراکنشش گیر می‌کند. **VERIFIED:** viem با حساب محلی (مسیر `eth_maxPriorityFeePerGas`). **UNVERIFIED:** کیف‌پول‌های injected مثل MetaMask پشت wagmi؛ روش تخمین آن‌ها آزموده نشد و نباید فرض شود fee history را نمی‌خوانند. **آزمون پیش از راه‌اندازی اجباری است** (چک‌لیست بخش ۸): مسیر واقعی dApp (wagmi + کیف‌پول injected) روی زنجیرهٔ دورریختنی با همین `config.toml`. گزینه‌های مالک اگر آزمون شکست خورد: (الف) dApp priority را صریحاً از `eth_maxPriorityFeePerGas` بگیرد و به کیف‌پول بدهد؛ (ب) در کد dApp tip ثابت ≥ 1e14 wei (و `maxFeePerGas` ≥ آن) بگذارد؛ (ج) هر دو.
   - **priority صریح 0 (آزموده):** تراکنشی که priority را صریح 0 بگذارد هنوز پذیرفته می‌شود و استخراج نمی‌شود؛ پس dApp/کیف‌پول نباید ثابت 0 بگذارد. **بازیابی:** همان nonce را دوباره با priority ≥ 1e14 بفرستید (بخش ۷-۸).
8. **بازیابی تراکنش گیرکرده با priority صریح 0 (LOW-1 دور ۲؛ مشاهدهٔ بازبین مستقل، ما این مرحله را دوباره اجرا نکردیم).** تراکنشی که priority را صریح 0 گذاشته باشد در **پذیرش** رد نمی‌شود (Besu آن را در pool می‌گیرد و هش می‌دهد)، استخراج نمی‌شود و nonceهای بعدی همان حساب را هم می‌بندد؛ **انقضای زمانی (time-based expiry) در این کیت وجود ندارد.** کیت pool **لایه‌ای (LAYERED)** پیش‌فرض Besu را اجرا می‌کند (`config.toml`، بخش tx-pool)؛ گزینهٔ `tx-pool-retention-hours` مخصوص pool **sequenced** است و Besu 26.9.0 اگر آن را با pool لایه‌ای بدهید **اصلاً بالا نمی‌آید** (VERIFIED زنده روی `hyperledger/besu:26.9.0` با `config.toml` همین کیت و `--tx-pool-retention-hours=13`: exit 2 با «Could not use legacy or sequenced transaction pool options with layered implementation [--tx-pool-retention-hours]»). پس آن را در `config.toml`، `.env` یا خط‌فرمان نگذارید و راه خروج تراکنش گیرکرده حساب نکنید. تراکنش گیرکرده فقط از این راه‌ها pool را ترک می‌کند: **جایگزینی** (همان nonce با priority ≥ 1e14؛ پایین‌تر)، **بیرون‌انداختن هنگام پُرشدن pool** (pool لایه‌ای هنگام پُرشدن evict می‌کند؛ آزموده نشد؛ روی زنجیرهٔ کم‌تراکنش به آن تکیه نکنید)، یا **شاید ریستارت نود** (**UNTESTED**: نمی‌دانیم pool بعد از ریستارت چه می‌کند). **بازیابی:** همان حساب همان **nonce** را دوباره بفرستد با `maxPriorityFeePerGas` ≥ 1e14 (و `maxFeePerGas` ≥ آن) تا تراکنش قبلی جایگزین شود. (پیام «Forcing price bump … zero basefee» که در لاگ دیده می‌شود **اعلان شروع نود** است، بخش ۴-۳: price bump روی این زنجیره 0 است؛ هنگام جایگزینی تراکنش لاگ نمی‌شود و نشانهٔ پذیرفته‌شدن جایگزینی نیست؛ موفقیت را از هش/استخراج تراکنش جدید ببینید.) اگر جایگزینی رد شد، افزایش بیشتر priority را امتحان کنید. جلوگیری بهتر از بازیابی است: بخش ۷-۷.

## ۸. چک‌لیست تصمیم‌های مالک/کمیتهٔ باقی‌مانده

- [ ] همهٔ مقدارهای `OWNER-FILL` در `genesis-config.json` (آدرس‌ها، هیأت‌ها، 21 ردیف طلب با جمع‌های 11,984,000 و 21,327,000 سورن)؛ بازبینی دوبارهٔ آدرس‌ها (خطای آدرس طلب قابل اصلاح نیست).
- [ ] تأیید سه آدرس اوراکل و وجود کلیدشان در SurKMS (کلیدها را خود SurKMS می‌سازد).
- [ ] بررسی دستی پیش از genesis: آدرس مالک هر ولیدیتور مؤسس و هر صندلی کیف‌پول ساده (EOA) باشد، نه قرارداد (RD-12)؛ ابزار genesis این را درون genesis نمی‌تواند ثابت کند. همچنین `receive()` قراردادهای خزانه و بنیاد هرگز نباید revert کند (اکنون ندارد؛ هر تغییر آینده را با این قید بسنجید).
- [ ] زمان genesis (≤ 72 ساعت بعد از `build`) و برنامهٔ زمانی راه‌اندازی هماهنگ.
- [ ] چه کسی/روی چه ماشینی `build` و `verify` را اجرا می‌کند (نیاز: Docker محلی، anvil 1.8.5؛ ماشین بدون دسترسی غیرضروری شبکه برای کلید واقعی).
- [ ] طرح اتصال: `static-nodes.json` یا bootnodeها (✅ `discovery-enabled=true` تصمیم مالک ۲۰۲۶-۱۱-۲۵؛ ✅ bootnode همان نود اول با نام `boot-node.surnet.org`)؛ IP عمومی هر ولیدیتور و IP و enode نود اول.
- [ ] **(تصمیم مالک — پیاده‌سازی نشده؛ MEDIUM-3 بازبینی) محدودکردن همتاها:** P2P روی `0.0.0.0` باز است با `discovery-enabled=true` و بدون `net-restrict` یا permissioning؛ کیت فقط به فایروال میزبان تکیه می‌کند که خودش ارائه نمی‌دهد. **گزینهٔ پیشنهادی:** `net-restrict=["<IP ولیدیتور ۱>/32", "<IP ولیدیتور ۲>/32", …]` در `config.toml` (یک /32 برای هر ولیدیتور؛ با `discovery-enabled=true` سازگار است ولی آنچه از راه discovery پیدا شود هم باید داخل همین فهرست باشد) یا فهرست مجاز نودها (permissioning)، به‌علاوهٔ فایروال میزبان. تا تصمیم نشده، در بخش ۳ مرحلهٔ ۶ فایروال دستی لازم است. **فایروال میزبان با `ufw` کافی نیست:** پورت P2P منتشرشدهٔ Docker از `ufw` رد می‌شود؛ فیلتر باید در زنجیرهٔ `DOCKER-USER` یا فایروال بیرونی/ابری (یا ترکیب با `net-restrict`) باشد (بخش ۳ مرحلهٔ ۶، MEDIUM-B). فقط الگوی `DOCKER-USER` با `conntrack --ctorigdstport` (TCP و UDP) و انتشار IPv4-فقط روی موتور لینوکس (dind) آزموده شد (بخش ۴-۶)؛ `ufw`/Ubuntu، `net-restrict` و permissioning آزموده نشده‌اند. **IPv6:** compose فقط IPv4 منتشر می‌کند؛ اگر IPv6 عمومی لازم شد، قاعدهٔ جدا (`ip6tables` روی `INPUT`) یا فایروال بیرونی لازم است (بخش ۳ مرحلهٔ ۶).
- [ ] برنامهٔ ساعت‌های اول: در genesis فقط **یک** ولیدیتور فعال است؛ برنامهٔ فعال‌سازی مؤسسان دیگر (`setOperator` + `recordActivation`) و نود پایش.
- [ ] **فهرست `StandbyValidators` (قرارداد دوازدهم genesis؛ بازیابی اضطراری):** در genesis فقط اولین ولیدیتور seed می‌شود. پس از فعال‌شدن مؤسسان، بنیاد با `proposeExecute` (۳ از ۵) فهرست را کامل کند (۱ تا ۱۰۰ عضو، صعودی، هر عضو کلید اپراتور فعلیِ یک صندلی **زنده**، یعنی در وضعیت Probation، Active، Demoted یا SelfSuspended؛ مالکِ خارج‌شده، برداشت‌کرده یا حذف‌شده عضو را کهنه می‌کند و `setStandby` آن را رد می‌کند (فروش یا مهاجرت صندلی کلید اپراتور را با صندلی می‌برد و عضو را کهنه نمی‌کند؛ فقط تعویض کلید توسط خودِ مالک یا خروج او کهنه‌اش می‌کند)) و پیش از اعلام راه‌اندازی `isReady()` را بررسی کند. هر تعویض کلید اپراتور فهرست را کهنه می‌کند؛ `staleMembers()` به‌طور دوره‌ای دیده شود. روی زنجیرهٔ ایستاده چیزی نوشته نمی‌شود، پس این فهرست باید از پیش آماده و تازه باشد (`governance/sur-emergency-consensus-recovery.md`).
- [ ] پذیرش `tx-pool-no-local-priority` + `tx-pool-min-gas-price` (بخش ۷-۱) و اعلام یکسان `min-gas-price` به همهٔ ولیدیتورها.
- [ ] `min-priority-fee=1e14` (بخش ۷-۷) روی **هر** نود، از جمله نودهای RPC سرویس‌ها و dApp (فقط در این فایل برای ولیدیتور هست؛ سیاست نودهای RPC باید همین را داشته باشد).
- [ ] **(اجباری پیش از راه‌اندازی؛ MEDIUM-A دور ۲) آزمون مسیر واقعی dApp:** wagmi + کیف‌پول injected (مثلاً MetaMask) روی یک زنجیرهٔ دورریختنی با همین `config.toml` و بلاک‌های خالی/کم‌تراکنش؛ تراکنش ساده و چند تراکنش پشت‌سرهم باید استخراج شوند و nonce نباید گیر کند. `min-priority-fee` فقط `eth_maxPriorityFeePerGas` را درست می‌کند، نه `eth_feeHistory` (بخش ۷-۷؛ برای کیف‌پول‌های injected **UNVERIFIED**). تصمیم مالک بر پایهٔ نتیجه: dApp priority را از `eth_maxPriorityFeePerGas` بگیرد، یا tip ثابت ≥ 1e14 wei در کد dApp، یا هر دو.
- [ ] سیاست `target-gas-limit` (همهٔ ولیدیتورها یکسان) و رویهٔ تغییر بعدی سقف گاز.
- [ ] نگهداری فایل کلید نود (دیسک رمزشده، پشتیبان رمزشدهٔ آفلاین)، مجوزها، جایگزینی کلید.
- [ ] `data-storage-format` نود ولیدیتور (Bonsai) در برابر نود RPC جداگانهٔ RewardRouter (archive/FOREST، `TRACE`) — بخش «نگه‌داری داده» سند معماری.
- [ ] سخت‌افزار حداقل، محدودیت حافظه/CPU، هشدار و پایش (F-1 در لاگ، ارتفاع گیرکرده، کندی بلاک)؛ مسئول پایش.
- [ ] رویهٔ به‌روزرسانی هماهنگ نسخهٔ Besu و `transitions.qbft` (برای تغییر ریوارد).

## ۹. موارد باز شناخته‌شده (پیش از راه‌اندازی)

- **آزمون بلندمدت با بلاک‌های واقعاً پر روی 45M** (پیش‌شرط تصمیم مالک): در این کیت **انجام نشد**؛ بلاک‌های آزموده خالی یا تقریباً خالی بودند. (پیش‌فرض Besu برای انتخاب تراکنش در شبکه‌های PoA `poa-block-txs-selection-max-time` = +75٪ زمان بلاک است؛ اثرش بر بلاک‌های پر آزموده نشده.)
- **دور 1c Besu — جریان دومرحلهٔ تعویض اپراتور** (`proposeOperator` → Verifier `confirmOperatorReady` → تعویض در QBFT): طبق `FINDINGS.md` دور 1b هنوز **هیچ شاهد زندهٔ Besu** ندارد؛ باز.
- **F-1 soak** (خطای Besu `IllegalStateException: Failed validator smart contract call`، دور اول؛ پایش در `sur-master-open-items.md`): ابزار `testing-evidence/soak-kit-v25` ساخته شده و فقط سه اجرای کوتاه روی PC سازنده (27 و 13 و 13 دقیقه) دارد؛ **تعداد ولیدیتور یکسان نبود: اجرای ۱ و ۳ با 7 ولیدیتور، اجرای ۲ با 4 ولیدیتور** (`testing-evidence/soak-kit-v25/verification/README.md`؛ پس 0 مورد در اجرای ۲ با اجرای‌های ۱ و ۳ هم‌پایه نیست) (F-1 تکرار شد ولی نرخ یکسان نبود. اجرای ۱ (27 دقیقه، 7 ولیدیتور): 9 مورد در 808 بلاک پنجره = 11.1 در هر 1000 بلاک، به‌علاوهٔ 1 مورد در bootstrap؛ اجرای ۲: 0 مورد در 383 بلاک؛ اجرای ۳: 1 مورد در 332 بلاک؛ هر سه اجرا کوتاه‌اند و نرخ پایدار نمی‌دهند؛ `testing-evidence/soak-kit-v25/verification/README.md`)؛ پوشهٔ `runs/` خالی است؛ **آزمون 72 ساعتهٔ سرور اوبونتو هنوز انجام نشده (pending). هیچ نتیجه‌ای از آن ادعا نمی‌شود.**
- شبکهٔ چندمیزبانه، تأخیر/ازدست‌رفتن بسته، کلید واقعی؛ حسابرسی امنیتی (در اسناد انجام نشده).
- آمادگی production را این کیت ادعا نمی‌کند.

## ۱۰. تکرار آزمون compose (برای شما)

```bash
# 1) کلید و genesis آزمایشی خودتان بسازید (genesis.TEST-ONLY.README.md: «ساخت دوبارهٔ آزمایشی با کلید خودتان»)
# 2) env آزمایشی: SUR_CHAIN_ID_HEX=0x3ff89، SUR_P2P_HOST=127.0.0.1، SUR_GENESIS_FILE=<genesis آزمایشی خودتان>،
#    SUR_NODE_KEY_FILE=<کلید دورریختنی>، SUR_CONFIG_FILE=<کپی config.toml با network-id=262025>،
#    SUR_CONTAINER_NAME/SUR_VOLUME_NAME/SUR_NETWORK_NAME با پیشوند دلخواه
docker compose --env-file test.env -p demo config
docker compose --env-file test.env -p demo up --no-start --pull never validator
docker run --rm --user 0 -v <SUR_VOLUME_NAME>:/data --entrypoint chown hyperledger/besu:26.9.0 -R 1000:1000 /data   # یک‌بار (بخش ۳)
docker compose --env-file test.env -p demo up -d --pull never
curl -s -X POST -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' http://127.0.0.1:8545
docker compose --env-file test.env -p demo down -v     # پاک‌سازی
```
