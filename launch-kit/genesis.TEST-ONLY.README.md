# genesis.TEST-ONLY.json — فقط برای آزمون؛ هرگز برای شبکهٔ واقعی

> ## ⛔ هشدار
> **`genesis.TEST-ONLY.json` یک genesis آزمایشی با داده‌های دورریختنی است. هرگز روی شبکهٔ واقعی (chain id 262) یا هر شبکه‌ای که پول یا حق واقعی دارد استفاده نشود، و هرگز با نام `genesis.json` در کنار فایل‌های تولیدی قرار نگیرد.**
> genesis واقعی هنگام راه‌اندازی با `build` از `genesis-config.json` (پر شده توسط مالک/کمیته) ساخته و با `verify` بررسی می‌شود؛ به همین دلیل در این پوشه فایلی به نام `genesis.json` نیست (توضیح در `README.md`، بخش «ترتیب راه‌اندازی»).

## این فایل چیست

خروجی **ابزار واقعی GenesisBuilder** (CLI شاخهٔ `v2.5-dev`، نسخهٔ `2.5.0-dev`، ref شاخه `cf5b7a6d5dad`) است که از پیکربندی آزمایشی `examples/genesis-config.local-test.json` ساخته شد. ورودی دقیق در `genesis.TEST-ONLY.config.json` در همین پوشه است (فقط دو تفاوت با فایل نمونه؛ پایین‌تر).

| ویژگی | مقدار در این فایل آزمایشی | مقدار تولیدی (تصمیم مالک) |
|---|---|---|
| chain id | **262025** (نه 262) | 262 |
| `blockperiodseconds` | 2 | 3 |
| `gasLimit` | `0x1fffffffffffff` (عملاً نامحدود؛ ابزار هشدار بلند می‌دهد) | 45,000,000 (`0x2aea540`) |
| `contractSizeLimit` | 36864 | 36864 (همین) |
| fork | cancun (`shanghaiTime`/`cancunTime` = 0) | cancun |
| آدرس‌ها | همه دورریختنی، بدون کلید شناخته‌شده؛ با `allowUnchecksummed` (برای chain id 262 ابزار این را رد می‌کند) | آدرس‌های واقعی با چک‌سام EIP-55 |
| ولیدیتور اول (`operator`) | آدرس یک کلید دورریختنی که فقط برای این آزمون ساخته و **نابود شد** | آدرس کلید واقعی اپراتور (کلید در Vault، نه در مخزن) |
| `genesisTimestamp` | `0x6affc9cb` = 2026-11-20T04:17:15Z (زمان ساخت + 60 ثانیه) | حداکثر 72 ساعت پس از زمان `build` |
| اوراکل‌ها | آدرس‌های دورریختنی `0x5400…01..03` | سه آدرس مرجع `SurAddresses.sol` (تأیید مالک) |

دو تفاوت ورودی با فایل نمونهٔ ابزار: (۱) `firstValidator.operator` = آدرس کلید دورریختنی (نمونه آدرسی بدون کلید دارد و آزمون زنده آن را جایگزین می‌کند)؛ (۲) `genesisTimestamp` از 0 به «زمان ساخت + 60 ثانیه» (ابزار صفر را رد می‌کند).

**هیچ کلید خصوصی در این کیت نیست.** چون کلید اپراتور آزمایشی دور ریخته شد، با همین فایل نمی‌شود نودی راه انداخت که بلاک تولید کند. برای آزمون خودتان یک کلید دورریختنی بسازید و دوباره بسازید (دستورها پایین‌تر). همین دلیل است که `genesis.TEST-ONLY.json` با آن کلید قابل اجرا نیست مگر `genesis.TEST-ONLY.config.json` را با آدرس کلید خودتان بازسازی کنید.

## دستور ساخت (آنچه اجرا شد)

نیاز: Node 22، Foundry `anvil` 1.8.5 (ابزار خودش `~/.foundry/bin/anvil` را پیدا می‌کند)، `npm install` در پوشهٔ GenesisBuilder.

```bash
cd Deployments/GenesisBuilder      # شاخهٔ v2.5-dev
npx tsx src/cli.ts build \
  --config <path>/genesis.TEST-ONLY.config.json \
  --out    <path>/genesis.TEST-ONLY.json \
  --summary <scratch>/genesis.TEST-ONLY.summary.json
```

نتیجه: خروجی با کد 0؛ solc 0.8.24 (optimizer 200، evm paris)، anvil 1.8.5؛ **277 post-build assertion گذشت**؛ سه هشدار غیرمانع (`allowUnchecksummed`، `gasLimit` عملاً نامحدود، `contractSizeLimitBytes = 36864` بالاتر از 24576) چاپ شد. فایل خلاصهٔ ابزار (`*.summary.json`) به‌دلیل مسیرهای محلی در کیت نیامده است.

- sha256 فایل: `14dae94d89502361a65175119e709a07a24320f3a763432d9ae5ebe5f737af79`
- 31 حساب در `alloc` (ده قرارداد ساختاری + حساب‌های طلبکاران با 100 سورن)، 53,311,000 سورن مجموع عرضه (طبق assertionهای ابزار).
- `config` شامل: `contractSizeLimit: 36864`، `zeroBaseFee: true`، `qbft.validatorcontractaddress = 0x3333…3333`، `miningbeneficiary = 0x2222…2222`، `blockreward = 2 سورن`.

## دستور راستی‌آزمایی و نتیجه

```bash
npx tsx src/cli.ts verify \
  --config  <path>/genesis.TEST-ONLY.config.json \
  --genesis <path>/genesis.TEST-ONLY.json \
  --docker-image hyperledger/besu:26.9.0 --docker-prefix sur25k-verify- \
  --node-key-file <کلید دورریختنی اپراتور آزمایشی>
```

نتیجهٔ اجرا روی همین فایل و همین config (دو بار، آخری با فایل‌های داخل `launch-kit/`):

```
verify: all checks passed     checks=326   head=2
```

یعنی: بازسازی genesis از config با فایل یکسان بود؛ نود واقعی Besu 26.9.0 در Docker از همین بایت‌ها بلند شد؛ هر حساب/اسلات alloc در بلاک 0 خوانده و مطابقت داده شد؛ بلاک‌های بعد از genesis توسط ولیدیتور اول تولید شد. پس از اجرا کانتینر، شبکهٔ `--internal` و volume ابزار حذف شدند (کنترل‌شده: `docker ps -a`، `docker network ls`، `docker volume ls` هیچ منبعی با پیشوند `sur25k-` نشان نداد).

## ساخت دوبارهٔ آزمایشی با کلید خودتان (برای آزمون compose)

```bash
openssl rand -hex 32 | tr -d '\n' > node.key          # کلید دورریختنی؛ در مخزن نگذارید
docker run --rm -v "$PWD:/k" hyperledger/besu:26.9.0 --data-path=/tmp/d \
  public-key export-address --node-private-key-file=/k/node.key --to=/k/node.addr
# آدرس داخل node.addr را در genesis.TEST-ONLY.config.json بگذارید:
#   validatorsRegistry.firstValidator.operator  و  network.genesisTimestamp = اکنون + 60
# سپس همان دستور build بالا و (اختیاری) verify.
```

## چرا `genesis.json` در کیت نیست

genesis واقعی به مقادیری وابسته است که فقط مالک/کمیته می‌تواند تعیین کند (آدرس 7 مؤسس، 15 عضو، 21 ردیف طلب، آدرس اپراتور ولیدیتور اول، زمان genesis) و باید **با کلید و آدرس‌های واقعی در لحظهٔ راه‌اندازی** ساخته و در حالت Docker بدون `--keep-container` راستی‌آزمایی شود. هر فایلی به نام `genesis.json` در این کیت یا ساختگی بود یا داده‌های آزمایشی را به‌جای نهایی نشان می‌داد؛ هر دو ممنوع‌اند.
