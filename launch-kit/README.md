# کیت راه‌اندازی شبکهٔ Sur (v2.5) — فایل‌های پیشنهادی نود و genesis

> **وضعیت: پیشنهاد برای تصمیم مالک؛ نه آمادهٔ production.** این پوشه فایل‌های لازم برای بلند کردن نود ولیدیتور Besu 26.9.0 (QBFT، ارز بومی سورن) و ساخت genesis را پیشنهاد می‌کند. بخشی روی Besu واقعی آزموده شده و بخشی نه؛ هر مورد در این سند و در کامنت خود فایل با برچسب **VERIFIED / UNVERIFIED / OWNER** مشخص است. هیچ کلید خصوصی و هیچ `genesis.json` «نهایی» در این پوشه نیست (و نباید باشد).

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
| `bootnodes.example.txt` | فرمت enode، روش گرفتن enode نود، دو راه اتصال (static-nodes / bootnodes) | فرمت ✅؛ طرح تولیدی OWNER |
| `prometheus.yml` | scrape نود برای profile اختیاری | ✅ target `up` |
| `.gitignore`، `.gitattributes` | جلوگیری از commit شدن `.env`، کلیدها و `genesis.json`؛ ثابت‌ماندن پایان‌خط‌ها (LF) تا sha256 همه‌جا یکسان باشد | — |
| `SHA256SUMS` | sha256 همهٔ فایل‌های کیت؛ بررسی: `sha256sum -c SHA256SUMS` | — |

## ۲. چرا `genesis.json` در کیت نیست

genesis واقعی به مقادیری وابسته است که فقط مالک/کمیته تعیین می‌کند (آدرس 7 مؤسس، 15 عضو، 21 ردیف طلب، آدرس اپراتور ولیدیتور اول، زمان genesis) و باید در لحظهٔ راه‌اندازی **با آدرس‌ها و کلید واقعی** با `build` ساخته و با `verify` بررسی شود. فایل «`genesis.json`» در این کیت یا ساختگی می‌بود یا داده‌های آزمایشی را به‌جای نهایی نشان می‌داد؛ هر دو ممنوع‌اند. `.gitignore` هم عمداً `genesis.json` را نادیده می‌گیرد. نمونهٔ آزمایشی فقط با نام `genesis.TEST-ONLY.json` هست.

## ۳. ترتیب راه‌اندازی

1. **پر کردن `genesis-config.json`** (کپی کار شود؛ مالک/کمیته): همهٔ جای‌گیرهای `OWNER-FILL` (فهرست در بخش ۶). **نام ۱۵ عضو بنیاد** در قالب خالی (`""`) است و باید با نام حقوقی واقعی و نهایی پر شود: این نام دائمی روی زنجیره نوشته می‌شود و `FoundationMembers` تابع تغییر نام ندارد (فقط حذف و افزودن دوباره با مجمع فوق‌العاده)؛ ابزار `build` نام خالی را رد می‌کند، ولی «نام ساختگی» را نمی‌گیرد؛ پس هر نام را دوباره بخوانید و تأیید کنید. آدرس‌ها باید EIP-55 باشند؛ برای chain id 262 گزینهٔ `allowUnchecksummed` رد می‌شود. `network.genesisTimestamp` باید «از اکنون تا 72 ساعت بعد» باشد (ابزار در `build` این را اجرا می‌کند).
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
   خروجی باید `verify: all checks passed` باشد. بعد از اجرا `docker ps -a`، `docker network ls`، `docker volume ls` باید چیزی با آن پیشوند نشان ندهند.
4. **پخش `genesis.json` و sha256 آن** (sha256 از کانالی مستقل از فایل، مثلاً اعلام زنده در جلسهٔ مؤسسان). هر اپراتور: `sha256sum genesis.json` و مقایسه. همهٔ نودها بایت‌به‌بایت یک فایل را دارند.
5. **هر اپراتور**: `cp .env.example .env` و پر کردن (به‌ویژه `SUR_P2P_HOST`، `SUR_GENESIS_FILE`، `SUR_NODE_KEY_FILE`)؛ کلید اپراتور را در مسیر خارج از مخزن بگذارد (بخش ۵)؛ `docker compose config`؛ `docker compose up -d`.
6. **اتصال همتاها**: enode هر نود را بگیرید (`bootnodes.example.txt`) و در `static-nodes.json` ولیدیتورهای دیگر بگذارید (یا طرح bootnode را تصمیم بگیرید)؛ فایروال: P2P فقط برای IPهای ولیدیتورها؛ RPC و متریک هرگز عمومی نشود.
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
- **تأیید فرمت‌ها:** `bootnodes=[…]` آرایه روی لینوکس پذیرفته شد («Resolved 1 bootnodes»؛ به bootnode واقعی وصل نشدیم)؛ `data-storage-format="FOREST"` هم بلند شد و بلاک ساخت؛ `--p2p-host` روی خط‌فرمان، مقدار فایل را بازنویسی می‌کند (enode آدرس جدید را نشان داد).

### ۴-۴. `docker-compose.yml`
`docker compose --env-file <test.env> -p sur25k -f docker-compose.yml config` معتبر؛ `.env.example` هم معتبر؛ بدون متغیرهای لازم (`SUR_P2P_HOST`، `SUR_GENESIS_FILE`، `SUR_NODE_KEY_FILE`) با پیام فارسی خطا می‌دهد. `up -d --pull never` روی genesis آزمایشی:
- کانتینر `healthy` (healthcheck خودمان)، بلاک‌ها تولید می‌شد، `eth_chainId` از `127.0.0.1:18570` = `0x3ff89`.
- **healthcheck:** تصویر `curl`/`wget`/`nc`/`socat` ندارد و `bash` 5.2 و `timeout` دارد (بررسی شد)؛ از `bash` + `/dev/tcp` + `Host: localhost` استفاده شد؛ با chainId اشتباه exit 1 می‌دهد (آزموده)، با درست exit 0. این جایگزین healthcheck خود تصویر (`[ -f /tmp/pid ]`) است.
- RPC و متریک روی `127.0.0.1` میزبان: از IP شبکهٔ خود میزبان وصل نشد (`curl` کد 000). P2P روی `0.0.0.0`.
- `docker inspect`: `privileged=false`، `CapDrop=[ALL]` + `CapAdd=[CHOWN DAC_OVERRIDE FOWNER SETGID SETUID]` (لازم برای entrypoint تصویر که root است، داده را chown می‌کند و به کاربر `besu` می‌رود)، `no-new-privileges`، `restart=unless-stopped`، لاگ `json-file` سقف 50m × 10.
- `docker compose stop`: 3 ثانیه، کد خروج **143** (پیام `Session terminated, killing shell` از `su` تصویر)؛ ری‌استارت بدون خطا از همان بلاک ادامه داد (121 → 122). تمیز بودن shutdown JVM **UNVERIFIED** (در لاگ پیام خاموشی Besu ندیدیم).
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

## ۵. مدیریت کلید (اصول؛ طراحی پروژه)

- **هیچ کلیدی در مخزن/تصویر/لاگ/`.env` نیست**؛ `.env` فقط «مسیر فایل کلید» دارد (`.gitignore` هم `.env`، `*.key`، `secrets/` را نادیده می‌گیرد). کیت هیچ کلید خصوصی ندارد (کلیدهای آزمایشی در scratch ساخته و پس از آزمون نابود شدند).
- **کلید نود = کلید اپراتور** (آدرس آن همان است که در `ValidatorsRegistry` ثبت می‌شود)، جدا از **کلید مالک که هرگز روی نود نمی‌آید**. یک نود، یک کلید؛ اجرای هم‌زمان با یک کلید در دو محل ممنوع (`parties/22-validator.md` ۵٫۱).
- طراحی پروژه: هر نرم‌افزاری که کلید امضای **خود سرویس** دارد باید از HashiCorp Vault (Transit/remote signer) استفاده کند (`sur-onchain-offchain-architecture.md`: اوراکل‌ها، Verifier، RewardRouter، Identity Service). **اما Besu 26.9.0 کلید نود را از فایل می‌خواند (`node-private-key-file`) و این کیت راه Vault-Transit برای امضای بلاک پیدا/آزمایش نکرد.** پیشنهاد عملی (UNVERIFIED، تصمیم OWNER): کلید در Vault نگه‌داری شود و با Vault Agent روی tmpfs میزبان به‌صورت فایل با مجوز `0400` فقط برای کاربر سرویس رندر شود، و در `SUR_NODE_KEY_FILE` ارجاع شود.
- مجوز فایل روی لینوکس: entrypoint تصویر root است و کاربر `besu` (uid 1000) را اجرا می‌کند؛ کلیدِ mount فقط‌خواندنی باید برای آن uid خواندنی باشد (مثلاً مالک uid 1000 و `0400`). **این روی سرور اوبونتو آزموده نشده** (Docker Desktop مجوزها را مثل لینوکس اعمال نمی‌کند).
- سه کلید اوراکل (`distributionOracle`، `verifier`، `identityOracle`) جزو این کیت نیستند و هرگز نباید باشند؛ فقط آدرس‌هایشان در `genesis-config.json` (مقدار مرجع `SurAddresses.sol`؛ OWNER تأیید کند).

## ۶. تصمیم‌گرفته / جای‌گیر / UNVERIFIED

**تصمیم‌گرفته (در فایل‌ها اعمال شد):** chainId 262؛ زمان بلاک 3 ثانیه؛ blockReward 2 سورن؛ fork cancun؛ حالت contract روی `0x3333…3333`؛ gasLimit 45,000,000؛ `contractSizeLimit` 36,864؛ `min-gas-price` 1e14.

**جای‌گیر `OWNER-FILL` در `genesis-config.json`:** `network.genesisTimestamp`؛ `validatorsRegistry.firstValidator.owner/operator`؛ شش `otherFounders`؛ 5 عضو `validatorsBoard.initialBoardMembers`؛ 15 عضو `foundationMembers.members` (نام، حساب، `shareWeight`؛ **نام حقوقی واقعی و نهایی را مالک بنویسد: نام روی زنجیره دائمی است و `FoundationMembers` تابع تغییر نام ندارد؛ فقط حذف و افزودن دوباره با مجمع فوق‌العاده؛ نام خالی را ابزار رد می‌کند**)؛ `foundationDAO.initialBoard` (5 اصلی + 2 علی‌البدل) و `initialInspector` (و اختیاری `initialOfficers`)؛ ردیف‌های `genesisClaimsVault.claims` (21 ردیف)؛ تأیید سه آدرس اوراکل.

**OWNER در سایر فایل‌ها:** IP عمومی هر ولیدیتور (`SUR_P2P_HOST`)؛ طرح bootnode / `discovery-enabled`؛ پذیرفتن دو خط `tx-pool-*` (بخش ۷)؛ نگهداری و تحویل کلید نود؛ سخت‌افزار (`parties/22-validator.md` ۵٫۱: «حداقل سخت‌افزار هنوز نیست»)؛ تنظیم حافظه JVM و محدودیت منابع (در compose کامنت شده).

**UNVERIFIED (هنوز آزموده نشده):** رفتار چند ولیدیتور با `target-gas-limit` متفاوت؛ اتصال به bootnode واقعی؛ مجوزهای فایل روی لینوکس؛ shutdown تمیز JVM؛ `sync-mode` به‌جز FULL با QBFT؛ رفتار RPC/تراکنش‌های رسیده از همتا (p2p) برای قیمت زیر حداقل؛ رفتار زیر بار بلاک‌های واقعاً پر؛ Vault برای کلید نود؛ آماده بودن NAT/فایروال واقعی؛ شبکهٔ چندمیزبانه.

## ۷. یافته‌ها و تعارض‌های مهم با انتظار (بدون لاپوشانی)

1. **`min-gas-price` برای تراکنش‌های محلی (از RPC همان نود) اعمال نمی‌شود.** با تنظیم پیش‌فرض Besu، تراکنش با 1e13 (کمتر از حداقل 1e14) از RPC نود ولیدیتور پذیرفته و استخراج شد. با `tx-pool-no-local-priority=true` + `tx-pool-min-gas-price=100000000000000` رد می‌شود (خطای `-32009`)؛ هر دو لازم‌اند. این دو خط در اسناد و آزمون‌های قبلی نبود؛ در `config.toml` گذاشته شدند. RPC ولیدیتور فقط محلی است، پس خطر اصلی کم است، ولی تصمیم پذیرش با مالک. همچنین `min-gas-price` تنظیم «محلی هر نود» است؛ پروتکل تراکنش ارزان‌تر را رد نمی‌کند (ولیدیتوری که کمتر بگذارد می‌پذیرد) ⇒ همهٔ ولیدیتورها باید یکسان بگذارند (سند: «هیچ مسیر رأی ندارد»).
2. **`target-gas-limit` در QBFT کار می‌کند** (برخلاف ابهام اسناد) و **با genesis = 45M بی‌اثر است**؛ پس `gasLimit` بعد از راه‌اندازی بدون genesis جدید قابل تغییر است (ولیدیتورها با مقدار یکسان)، حداکثر ≈ parent/1024 در هر بلاک. ولی این فقط با یک ولیدیتور آزموده شد؛ سند بخش ظرفیت می‌گفت «برای gasLimit راستی‌آزمایی نشده» — اکنون برای یک ولیدیتور راستی‌آزمایی است، برای چند ولیدیتور نه. هشدار: با `genesis.TEST-ONLY.json` (سقف نامحدود) و `target 45M` سقف به‌تدریج پایین می‌آید؛ آن genesis برای این‌کار نیست.
3. **`sync-min-peers=1` در soak-kit در حالت FULL بی‌اثر است** (Besu هشدار می‌دهد)؛ از `config.toml` حذف شد.
4. **`--bootnodes` ویندوزی خطا داد (سند)؛ روی لینوکس/Docker سینتکس پذیرفته شد** ولی اتصال به bootnode واقعی آزموده نشد؛ روش آزموده‌شدهٔ پروژه `static-nodes.json` است.
5. **entrypoint تصویر root است** و پس از `chown` داده به کاربر `besu` می‌رود؛ برای همین `cap_drop: ALL` با پنج قابلیت لازم همراه شد (آزموده). این از `read_only` یا `user:` ساده‌تر ولی کمتر سخت‌گیرانه است؛ سخت‌ترکردن بیشتر آزموده نشد.
6. **Prometheus:** Besu `host-allowlist` را روی `/metrics` هم اعمال می‌کند و Prometheus اجازهٔ تغییر Host نمی‌دهد؛ برای همین نام سرویس `validator` به `host-allowlist` اضافه شد (بدون آن 403).

## ۸. چک‌لیست تصمیم‌های مالک/کمیتهٔ باقی‌مانده

- [ ] همهٔ مقدارهای `OWNER-FILL` در `genesis-config.json` (آدرس‌ها، هیأت‌ها، 21 ردیف طلب با جمع‌های 11,984,000 و 21,327,000 سورن)؛ بازبینی دوبارهٔ آدرس‌ها (خطای آدرس طلب قابل اصلاح نیست).
- [ ] تأیید سه آدرس اوراکل و وجود کلیدشان در Vault.
- [ ] زمان genesis (≤ 72 ساعت بعد از `build`) و برنامهٔ زمانی راه‌اندازی هماهنگ.
- [ ] چه کسی/روی چه ماشینی `build` و `verify` را اجرا می‌کند (نیاز: Docker محلی، anvil 1.8.5؛ ماشین بدون دسترسی غیرضروری شبکه برای کلید واقعی).
- [ ] طرح اتصال: `static-nodes.json` یا bootnodeها؛ `discovery-enabled`؛ IP عمومی هر ولیدیتور.
- [ ] برنامهٔ ساعت‌های اول: در genesis فقط **یک** ولیدیتور فعال است؛ برنامهٔ فعال‌سازی مؤسسان دیگر (`setOperator` + `recordActivation`) و نود پایش.
- [ ] پذیرش `tx-pool-no-local-priority` + `tx-pool-min-gas-price` (بخش ۷-۱) و اعلام یکسان `min-gas-price` به همهٔ ولیدیتورها.
- [ ] سیاست `target-gas-limit` (همهٔ ولیدیتورها یکسان) و رویهٔ تغییر بعدی سقف گاز.
- [ ] نگهداری کلید نود (Vault Agent/tmpfs یا روش دیگر)، مجوزها، جایگزینی کلید.
- [ ] `data-storage-format` نود ولیدیتور (Bonsai) در برابر نود RPC جداگانهٔ RewardRouter (archive/FOREST، `TRACE`) — بخش «نگه‌داری داده» سند معماری.
- [ ] سخت‌افزار حداقل، محدودیت حافظه/CPU، هشدار و پایش (F-1 در لاگ، ارتفاع گیرکرده، کندی بلاک)؛ مسئول پایش.
- [ ] رویهٔ به‌روزرسانی هماهنگ نسخهٔ Besu و `transitions.qbft` (برای تغییر ریوارد).

## ۹. موارد باز شناخته‌شده (پیش از راه‌اندازی)

- **آزمون بلندمدت با بلاک‌های واقعاً پر روی 45M** (پیش‌شرط تصمیم مالک): در این کیت **انجام نشد**؛ بلاک‌های آزموده خالی یا تقریباً خالی بودند. (پیش‌فرض Besu برای انتخاب تراکنش در شبکه‌های PoA `poa-block-txs-selection-max-time` = +75٪ زمان بلاک است؛ اثرش بر بلاک‌های پر آزموده نشده.)
- **دور 1c Besu — جریان دومرحلهٔ تعویض اپراتور** (`proposeOperator` → Verifier `confirmOperatorReady` → تعویض در QBFT): طبق `FINDINGS.md` دور 1b هنوز **هیچ شاهد زندهٔ Besu** ندارد؛ باز.
- **F-1 soak** (خطای Besu `IllegalStateException: Failed validator smart contract call`، دور اول؛ پایش در `sur-master-open-items.md`): ابزار `testing-evidence/soak-kit-v25` ساخته شده و فقط دو اجرای کوتاه روی PC سازنده (27 و 13 دقیقه) دارد (در آن، F-1 تکرار شد: 11.1 در هر 1000 بلاک)؛ پوشهٔ `runs/` خالی است؛ **آزمون 72 ساعتهٔ سرور اوبونتو هنوز انجام نشده (pending). هیچ نتیجه‌ای از آن ادعا نمی‌شود.**
- شبکهٔ چندمیزبانه، تأخیر/ازدست‌رفتن بسته، کلید واقعی و Vault؛ حسابرسی امنیتی (در اسناد انجام نشده).
- آمادگی production را این کیت ادعا نمی‌کند.

## ۱۰. تکرار آزمون compose (برای شما)

```bash
# 1) کلید و genesis آزمایشی خودتان بسازید (genesis.TEST-ONLY.README.md: «ساخت دوبارهٔ آزمایشی با کلید خودتان»)
# 2) env آزمایشی: SUR_CHAIN_ID_HEX=0x3ff89، SUR_P2P_HOST=127.0.0.1، SUR_GENESIS_FILE=<genesis آزمایشی خودتان>،
#    SUR_NODE_KEY_FILE=<کلید دورریختنی>، SUR_CONFIG_FILE=<کپی config.toml با network-id=262025>،
#    SUR_CONTAINER_NAME/SUR_VOLUME_NAME/SUR_NETWORK_NAME با پیشوند دلخواه
docker compose --env-file test.env -p demo config
docker compose --env-file test.env -p demo up -d --pull never
curl -s -X POST -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' http://127.0.0.1:8545
docker compose --env-file test.env -p demo down -v     # پاک‌سازی
```
