// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// کمک‌کنندهٔ seed کردن GENESIS: موقت است و هرگز روی زنجیرهٔ واقعی مستقر نمی‌شود.
//
// همتای contracts/ValidatorsRegistry.sol. قرارداد واقعی constructor ندارد (در `alloc` بلاک genesis تزریق می‌شود)، ولی
// `validators` (mapping به struct)، `activeValidators` (آرایهٔ پویا) و `activeIndex` (mapping) را نمی‌شود با ساختار
// سطح‌قرارداد Solidity پر کرد. این کمک‌کننده همان منطق seed را در یک constructor بدون آرگومان اجرا می‌کند (زمان genesis و
// آدرس مؤسسان مستقیم در همین فایل نوشته می‌شوند)، تا با یک‌بار اجرا روی یک زنجیرهٔ محلی موقت (Anvil یا Hardhat) خودِ EVM
// حساب slot با keccak256 را برای هر ورودی انجام دهد.
//
// قاعدهٔ چیدمان storage: ترتیب و نوع متغیرهای زیر باید دقیقاً با ValidatorsRegistry.sol واقعی یکی باشد. هر mapping یا آرایهٔ پویا
// یک slot برای پایهٔ خود می‌گیرد، پس هر متغیر بعد از آن به تعداد slotهای قبلش وابسته است؛ جای‌گیرها و gapهای زیر slotهای
// قرارداد واقعی را رزرو می‌کنند. هر وقت قرارداد واقعی عوض شد این فایل را باید دستی به‌روز کرد
// (با static-checks/check_genesis_helper_layout.js بررسی کنید).
//
// نحوهٔ استفادهٔ ابزار genesis از این فایل:
//   ۱. FILL_IN: زمان genesis و آدرس همهٔ ولیدیتورهای مؤسس را با مقادیر نهایی جایگزین کنید.
//      اگر شمار مؤسسان عوض شد طول آرایه (نوع و فهرست literal) را عوض کنید.
//   ۲. این فایل را (بدون آرگومان constructor) روی یک زنجیرهٔ محلی موقت مستقر کنید.
//   ۳. storage نهایی‌اش را بیرون بکشید (eth_getStorageAt برای هر slot لمس‌شده، یا ابزار state-dump).
//   ۴. این storage را به‌همراه bytecode runtime ValidatorsRegistry.sol واقعی (نه bytecode این فایل) زیر آدرس 0x3333...3333
//      در `alloc` فایل genesis.json بنویسید. slotهای جای‌گیر (`paidValidatorCount`، `verifier`، gapها) از این کمک‌کننده
//      صفر بیرون می‌آیند: آن‌ها را کپی نکنید. `paidValidatorCount` صفر می‌ماند (slot را حذف کنید).
//      `verifier` و هر scalar ساده‌ی دیگر (entryThresholdBase، growthFactorPerValidator، membershipFeeBps، پارامترهای
//      امنیتی، زمان genesis) مستقیم در `alloc` روی slot خودشان نوشته می‌شوند، همان‌طور که یادداشت‌های GENESIS FILL-IN
//      قرارداد واقعی می‌گوید.
// ============================================================================
contract ValidatorsRegistry_GenesisSeed {
    enum Status { None, Probation, Active, Demoted, Exiting }

    // تعداد و ترتیب فیلدها باید دقیقاً با struct واقعی یکی باشد، وگرنه حساب slot هر ورودی mapping خراب می‌شود.
    struct ValidatorInfo {
        Status status;
        uint256 lockedStake;
        uint256 periodStartedAt;
        uint256 pendingSlashEpoch;
        uint256 demotedAt;
        bool isPaidEntrant;
    }

    mapping(address => ValidatorInfo) public validators;

    // جای‌گیر: slot قرارداد واقعی را رزرو می‌کند. اینجا هرگز نوشته نمی‌شود؛ مؤسسان در منحنی پرداختی شمرده نمی‌شوند.
    uint256 public paidValidatorCount;

    // جای‌گیر: slot قرارداد واقعی را رزرو می‌کند. آدرس واقعی verifier مستقیم در `alloc` نوشته می‌شود.
    address public verifier;

    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // slotهای ۵ تا ۱۹ قرارداد واقعی: پارامترهای اقتصادی و زمانی و mapping با نام `massFailureChecked`. مقادیرشان را overlay
    // genesis می‌نویسد، نه این constructor.
    uint256[15] private __gap1;

    // constructor آن را می‌نویسد: هر مؤسس با everActivated = true به‌صورت Active وارد می‌شود، تا نخستین فراخوان
    // distributeRewards() بتواند به مؤسس پرداخت کند.
    mapping(address => bool) public everActivated;

    // slotهای ۲۱ تا ۳۵ قرارداد واقعی (فیلدهای بعد از everActivated تا paramProposalCount): فقط جای‌گیر.
    // statusNonce (slot 36) در genesis صفر می‌ماند؛ هر مؤسس checkpoint ‏{nonce: 0, active: true} را در activeCheckpoints
    // (slot 37) می‌گیرد، پس wasActiveAt(founder, n) برای هر پیشنهادی که پیش از نخستین تغییر وضعیت مؤسس ساخته شود true است.
    uint256[15] private __gap2;
    struct ActiveCheckpoint {
        uint64 nonce;
        bool active;
    }
    uint256 public statusNonce;
    mapping(address => ActiveCheckpoint[]) private activeCheckpoints;

    // slotهای ۳۸ و ۳۹ قرارداد واقعی: ترتیب نخستین فعال‌سازی. مؤسسان به ترتیبی که در constructor آمده‌اند ۱ تا ۷ شماره می‌گیرند؛
    // هیأت از آن برای شکستن تساوی نامزدهای هم‌رأی استفاده می‌کند (ولیدیتور قدیمی‌تر برنده است).
    uint256 public activationCount;
    mapping(address => uint256) public activationSeq;

    // ------------------------------------------------------------------
    // constructor بدون آرگومان — زمان genesis و مجموعهٔ اولیهٔ ولیدیتورها مستقیم در همین پایین نوشته شده‌اند.
    // FILL_IN: پیش از استقرار این فایل در هر جا، زمان جای‌گیر (۰) و هر آدرس 0x000...000 را با مجموعهٔ نهایی مؤسسان جایگزین کنید.
    // ------------------------------------------------------------------
    constructor() {
        uint256 genesisTimestamp = 0; // FILL_IN: زمان واقعی genesis شبکهٔ زنده

        address[7] memory initialValidators = [
            address(0), // Alireza Zojaji
            address(0), // Citex Corp. 1
            address(0), // Citex Corp. 2
            address(0), // Mahkameh Sharifzad
            address(0), // Mostafa Naghipoorfar
            address(0), // Sepehr Mohammadi
            address(0) // Siavash Tafazzoli
        ];

        for (uint256 i = 0; i < initialValidators.length; i++) {
            address v = initialValidators[i];
            require(v != address(0), "GenesisSeed: zero address - fill in real values first");
            require(validators[v].status == Status.None, "GenesisSeed: duplicate initial validator");

            validators[v] = ValidatorInfo({
                status: Status.Active,
                lockedStake: 0,
                periodStartedAt: genesisTimestamp,
                pendingSlashEpoch: 0,
                demotedAt: 0,
                isPaidEntrant: false // مؤسسان همیشه رایگان‌اند، هرگز ورودی پرداختی نیستند
            });
            activeIndex[v] = activeValidators.length + 1;
            activeValidators.push(v);
            everActivated[v] = true; // مؤسسان باید از نخستین توزیع قابل پرداخت باشند؛ everActivated را در قرارداد واقعی ببینید
            activationSeq[v] = ++activationCount;
            activeCheckpoints[v].push(ActiveCheckpoint({nonce: 0, active: true})); // L04
        }
        // paidValidatorCount و verifier عمداً دست‌نخورده می‌مانند — کامنت اعلام آن‌ها را در بالا ببینید.
    }

    // نمای کمکی برای بازبینی دستی هنگام آزمون — در استخراج storage نقشی ندارد.
    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }
}
