# مرحلهٔ ۱ — genesis روی Besu (نتیجه: ✅ قبول، ۱۲ بررسی + ۱۴ آزمون e2e)

**تاریخ اجرا:** ۲۰۲۶-۱۱-۲۲ · **Besu:** `hyperledger/besu:26.9.0` (image id `sha256:ca05efeb…`) روی سرور Ubuntu (`192.168.1.210`، پیشوند `sur25b-`)
**مبنا:** قراردادهای `GenesisBuilder/contracts` (منبع: Plan کامیت `9a94fa5`، همگام‌شده ۲۰۲۶-۱۱-۲۱)؛ GenesisBuilder کامیت `d42e49f` (HEAD شاخهٔ v2.5-dev)؛ genesis با **خودِ CLI** (`npm run genesis:build`) از پیکربندی `network/netA-genesis-config.json` ساخته شد (زنجیرهٔ آزمایشی ۲۶۲۰۲۵، نه ۲۶۲).

## آنچه آزموده شد

| # | بررسی | نتیجه |
|---|---|---|
| ۱ | یازده قرارداد سیستمی در `alloc` با کد runtime بارگذاری شدند؛ `eth_getCode` هر یازده روی **هر نُه نود** = بایت‌کد کامپایل‌شده | ✅ |
| ۲ | هش بلاک ۰ روی هر نُه نود یکسان | ✅ |
| ۳ | **ValidatorsRegistry (۳۷٬۳۴۶ بایت، بالاتر از EIP-170 (۲۴٬۵۷۶) و بالاتر از `contractSizeLimit=36864`)** در `alloc` پذیرفته شد و `eth_call` به آن (`getValidators`، `getValidatorInfo`، `isFounder`، پارامترها) کار می‌کند | ✅ |
| ۴ | **QBFT مجموعهٔ ولیدیتور را از قرارداد Registry می‌خواند:** `qbft_getValidatorsByBlockNumber` = `Registry.getValidators()` = کلید عامل ولیدیتور اول؛ پس از فعال‌سازی ۶ بنیان‌گذار با جریان واقعی، به ۷ رسید (مرحلهٔ ۲) | ✅ |
| ۵ | موجودی‌ها: FoundationDAO = ۲۰٬۰۰۰٬۰۰۰ Suren؛ GenesisClaimsVault = `totalHeld()` | ✅ |
| ۶ | سقف گاز بلاک ۴۵٬۰۰۰٬۰۰۰ (مقدار تصمیم‌گرفتهٔ مالک) روی زنجیره | ✅ |
| ۷ | سرایند Cancun: `parentBeaconBlockRoot` = ۰، `blobGasUsed` = ۰، `excessBlobGas` = ۰، `baseFeePerGas` = ۰ (`zeroBaseFee`) | مشاهده |
| ۸ | قرارداد سیستمی EIP-4788 در آدرس استاندارد **وجود ندارد** (`eth_getCode` = `0x`) | مشاهده |
| ۹ | `trace_block` (API ‏TRACE) روی نود کار می‌کند | ✅ |
| ۱۰ | `contractSize.besu.e2e` (۹ آزمون) و `verify.besu.e2e` (۵ آزمون) از GenesisBuilder که تا امروز SKIP بودند، با `SUR_GB_BESU_IMAGE=hyperledger/besu:26.9.0` **اجرا شدند: ۱۴ از ۱۴ قبول** (cancun و london، فراتر از ۲۸۰ بررسی در verify، نبود نشت Docker، بستن خروجی شبکه، حد اندازهٔ قرارداد ۳۶٬۸۶۴ قبول / ۳۶٬۸۶۵ رد) | ✅ |

## انحراف‌ها و نکته‌ها
- آزمون‌های e2e روی **Docker Desktop همین PC** اجرا شدند (نه روی سرور): چون روی سرور Node و anvil نیست و نصب آن‌ها دانلود می‌خواست؛ همان image Besu ۲۶٫۹٫۰ (از قبل روی PC بود). شبکهٔ ۷ ولیدیتوری و همهٔ مراحل بعد روی سرور هستند.
- حساب‌های آزمایشی پُرموجودی بعد از ساخت به `alloc` افزوده شدند (GenesisBuilder گزینه‌ای برای حساب اضافی ندارد). این فقط برای پرداخت گاز آزمایش است و در `network/` ثبت شده.
- «Forcing price bump for transaction replacement to 0, since we are on a zero basefee network» در لاگ Besu: **جایگزینی تراکنش با همان قیمت گاز در شبکهٔ zero-basefee پذیرفته می‌شود** (برای RM12 مهم است؛ مرحلهٔ ۴).
- genesis دو بار برای دو نیاز ساخته شد (کلیدهای سه سرویس یک‌بار کلیدهای آزمایشی ساده و بعد آدرس‌های ساخته‌شده توسط SurKMS)؛ هش هر دو در `network/genesis-sha256.txt`. بررسی‌های بالا روی genesis اول (مرحلهٔ ۲) و دوم (مرحلهٔ ۳) یکسان‌اند چون فقط سه آدرس اوراکل عوض شد.
