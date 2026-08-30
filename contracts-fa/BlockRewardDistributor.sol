// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function isValidator(address who) external view returns (bool);
}

/// @title BlockRewardDistributor
/// @notice دیپلوی‌شده در آدرس ثابت genesis، یعنی SurAddresses.BLOCK_REWARD_DISTRIBUTOR
///         (0x2222...2222) — همان آدرسی که باید به‌عنوان `qbft.miningbeneficiary` در
///         genesis.json تنظیم شود. بلاک‌ریوارد و فی تراکنش‌ها را به‌طور خودکار و در سطح
///         پروتکل از شبکه دریافت می‌کند (طبق آزمایش تجربی، این یک اعتبار مستقیم روی
///         state-trie است، بدون فراخوانی EVM، بدون event؛ به «یافته‌های آزمایش Besu QBFT»،
///         آزمایش ۱ مراجعه کن) و به‌صورت دوره‌ای، بر اساس داده‌ی گزارش‌شده توسط یک اوراکل
///         مجاز، بین ولیدیتورها و ValidatorsTreasury توزیع می‌کند.
///
///         قواعد توزیع (مدل نهایی — بخش ۳ سند طراحی):
///           - از کل ریوارد: ۵۰٪ (TREASURY_SHARE_BPS) به ValidatorsTreasury می‌رود، بقیه به
///             نسبت تعداد بلاک تولیدی بین ولیدیتورها تقسیم می‌شود.
///           - از کل فی: ۱۰۰٪ به نسبت تعداد بلاک تولیدی بین ولیدیتورها تقسیم می‌شود (بدون
///             سهم خزانه از فی).
///           - هر ولیدیتور دقیقاً یک پرداخت در هر فراخوانی دریافت می‌کند (یک انتقال ترکیبی
///             از سهم ریوارد + سهم فی).
///
///         صلاحیت ولیدیتور مستقیم و on-chain در برابر ValidatorsRegistry چک می‌شود — هیچ
///         لیست سفید داخلی و هیچ «اوراکل همگام‌سازی ولیدیتور» دومی وجود ندارد (آن طراحی وقتی
///         انتخاب ولیدیتور به حالت contract-mode رفت و خودِ ValidatorsRegistry مرجع واحد هم
///         برای اجماع هم برای پرداخت شد، کنار گذاشته شد؛ بخش ۵ سند طراحی را ببین).
///
///         دیپلوی genesis: این قرارداد constructor ندارد — مستقیم در alloc genesis تزریق
///         می‌شود، پس constructor هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود. آدرس‌های
///         ValidatorsRegistry، ValidatorsTreasury، و ValidatorsBoard ثابت (constant) هستند
///         (به SurAddresses.sol مراجعه کن)، چون هر شش قرارداد ساختاری یک نقشه‌ی آدرس مشترک و
///         از‌پیش‌توافق‌شده در genesis دارند. کلید اولیه‌ی distributionOracle (یک اعتبارنامه‌ی
///         عملیاتی واقعاً قابل‌چرخش، نه یک قرارداد ساختاری) و genesis timestamp واقعی، به‌جایش
///         با ابزار genesis آف‌چین پر می‌شوند (یادداشت‌های 🔶 پرکردنِ genesis پایین را ببین، و
///         "sur-contracts-deploy-notes.md" را برای این‌که چرا genesis timestamp واقعی را
///         نمی‌شود مستقیم از `block.timestamp` یک محیط شبیه‌سازی‌شده خواند).
contract BlockRewardDistributor {
    // ------------------------------------------------------------------
    // ثابت‌ها و تنظیمات
    // ------------------------------------------------------------------

    /// @notice سهم خزانه از کل ریوارد (نه فی) — واحد basis point از ۱۰۰۰۰ = ۱۰۰٪.
    uint256 public constant TREASURY_SHARE_BPS = 5000; // ۵۰٪
    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @notice حداقل فاصله‌ی مجاز بین دو فراخوانی متوالی توزیع.
    uint256 public constant MIN_DISTRIBUTION_INTERVAL = 23 hours;

    /// @notice حداقل دوره‌ی تولید بلاک در شبکه (از genesis: qbft.blockperiodseconds).
    ///         برای بررسی سلامتی تعداد بلاک گزارش‌شده توسط اوراکل استفاده می‌شود.
    uint256 public constant MIN_BLOCK_PERIOD_SECONDS = 3;

    // ------------------------------------------------------------------
    // آدرس‌های ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — دریافت‌کننده‌ی سهم ۵۰٪ ریوارد.
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    /// @notice ValidatorsBoard — تنها آدرس مجاز به چرخش distributionOracle (یک اختیار تفویضی
    ///         که صریح به هیأت داده شده؛ بخش ۴ سند طراحی را ببین).
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    /// @notice ValidatorsRegistry — مرجع واحد صلاحیت ولیدیتور، مستقیم در هر پرداخت چک می‌شود،
    ///         بدون اوراکل واسط.
    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);

    /// @notice آدرس اوراکلی که مجاز به فراخوانی تابع توزیع دوره‌ای است. تنها وظیفه‌اش گزارش
    ///         تعداد بلاک و مجموع ریوارد/فی است؛ نمی‌تواند به هیچ آدرسی که ValidatorsRegistry
    ///         الان به‌عنوان فعال نمی‌شناسد پرداخت کند.
    /// @dev 🔶 FILL_IN: آدرس اولیه‌ی distributionOracle (باید غیرصفر باشد).
    address public distributionOracle = address(0);

    /// @dev 🔶 FILL_IN: genesis timestamp واقعی شبکه‌ی زنده (نه block.timestamp هر ماشین/لحظه‌ای
    ///      که شبیه‌سازی رویش اجرا می‌شود — به sur-contracts-deploy-notes.md مراجعه کن که چرا
    ///      block.timestamp اینجا غیرقابل‌اتکاست). به‌صورت `immutable` اعلان شده تا این مقدار
    ///      مستقیم در بایت‌کد دیپلوی‌شده جاسازی شود، دقیقاً مثل حالتی که در constructor
    ///      تنظیم می‌شد.
    uint256 public immutable deployTime = 0;
    uint256 public lastDistributionTime;
    uint256 public epochCount;

    bool private locked; // نگهبان ساده‌ی reentrancy

    // ------------------------------------------------------------------
    // 🔶 پرکردنِ genesis — این قرارداد constructor ندارد چون مستقیم در alloc بلاک genesis
    // تزریق می‌شود (constructorش هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود). ابزار genesis آف‌چین
    // باید دیپلوی این قرارداد را (با دو مقدار واقعی بالا پرشده، روی یک زنجیره‌ی محلی موقت)
    // شبیه‌سازی کند و کد+storage نتیجه را در فایل نهایی genesis کپی کند. برای دستورالعمل
    // کامل به "sur-contracts-deploy-notes.md" مراجعه کن.
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // ساختار گزارش‌گیری هر epoch
    // ------------------------------------------------------------------
    struct Epoch {
        uint256 timestamp;
        uint256 totalRewards;
        uint256 totalFees;
        uint256 treasuryAmount;
        uint256 totalBlocksMined;
        uint256 validatorCount;
    }

    mapping(uint256 => Epoch) public epochs;

    mapping(uint256 => mapping(address => uint256)) public epochValidatorRewardShare;
    mapping(uint256 => mapping(address => uint256)) public epochValidatorFeeShare;
    mapping(uint256 => mapping(address => uint256)) public epochValidatorBlocks;

    mapping(address => uint256) public totalRewardsPaid;
    mapping(address => uint256) public totalFeesPaid;
    mapping(address => uint256) public totalBlocksRecorded;

    uint256 public totalDistributedToValidators;
    uint256 public totalDistributedToTreasury;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event DistributionOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event RewardsReceived(address indexed from, uint256 amount);
    event RewardsDistributed(
        uint256 indexed epochId,
        uint256 totalRewards,
        uint256 totalFees,
        uint256 treasuryAmount,
        uint256 totalBlocksMined,
        uint256 validatorCount
    );
    event ValidatorRewarded(
        uint256 indexed epochId,
        address indexed validator,
        uint256 blocksMined,
        uint256 rewardShare,
        uint256 feeShare,
        uint256 totalPayout
    );

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyDistributionOracle() {
        require(msg.sender == distributionOracle, "BlockRewardDistributor: caller is not the distribution oracle");
        _;
    }

    modifier onlyBoard() {
        require(msg.sender == BOARD, "BlockRewardDistributor: caller is not the validators board");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "BlockRewardDistributor: reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // ------------------------------------------------------------------
    // چرخش کلید اوراکل — فقط هیأت (اختیار تفویضی، به ValidatorsBoard مراجعه کن)
    // ------------------------------------------------------------------
    function setDistributionOracle(address newOracle) external onlyBoard {
        require(newOracle != address(0), "BlockRewardDistributor: zero distribution oracle address");
        emit DistributionOracleUpdated(distributionOracle, newOracle);
        distributionOracle = newOracle;
    }

    // ------------------------------------------------------------------
    // دریافت خودکار بلاک‌ریوارد و فی
    // ------------------------------------------------------------------
    /// @notice هر انتقال ساده‌ی سورن به این قرارداد (بلاک‌ریوارد/فی سطح پروتکل) اینجا دریافت
    ///         می‌شود. نکته: طبق تأیید تجربی، اعتبار سطح پروتکلِ miningbeneficiary در واقع این
    ///         تابع را فراخوانی نمی‌کند — یک نوشتن مستقیم موجودی روی state-trie است. این
    ///         receive() فقط برای انتقال‌های معمولی (مثلاً شارژ دستی یا تست) فعال می‌شود.
    receive() external payable {
        emit RewardsReceived(msg.sender, msg.value);
    }

    // ------------------------------------------------------------------
    // تابع اصلی توزیع دوره‌ای — فقط توسط اوراکل توزیع قابل‌فراخوانی است
    // ------------------------------------------------------------------
    /// @param validators لیست آدرس ولیدیتورها (بدون تکرار)
    /// @param blocksMined تعداد بلاک تولیدشده توسط هر ولیدیتور از آخرین فراخوانی به بعد (همون ترتیب validators)
    /// @param totalRewards مجموع ریوارد این epoch (به wei) — آف‌چین توسط اوراکل، از ورودی‌های «reward» تابع trace_block محاسبه می‌شود
    /// @param totalFees مجموع فی تراکنش‌های این epoch (به wei) — آف‌چین توسط اوراکل، از eth_getTransactionReceipt.gasUsed ضرب‌در effectiveGasPrice برای هر تراکنش محاسبه می‌شود (هرگز از خروجی trace_*، که برای انتقال‌های ساده gasUsed=0 گزارش می‌کند)
    function distributeRewards(
        address[] calldata validators,
        uint256[] calldata blocksMined,
        uint256 totalRewards,
        uint256 totalFees
    )
        external
        onlyDistributionOracle
        nonReentrant
    {
        require(validators.length > 0, "BlockRewardDistributor: empty validator list");
        require(validators.length == blocksMined.length, "BlockRewardDistributor: length mismatch");
        require(
            block.timestamp >= lastDistributionTime + MIN_DISTRIBUTION_INTERVAL || epochCount == 0,
            "BlockRewardDistributor: too soon since last distribution"
        );

        uint256 totalToDistribute = totalRewards + totalFees;
        require(totalToDistribute > 0, "BlockRewardDistributor: nothing to distribute");
        require(totalToDistribute <= address(this).balance, "BlockRewardDistributor: insufficient contract balance");

        uint256 totalBlocks = 0;
        for (uint256 i = 0; i < blocksMined.length; i++) {
            totalBlocks += blocksMined[i];
        }
        require(totalBlocks > 0, "BlockRewardDistributor: total blocks is zero");

        // --- بررسی سلامتی: تعداد بلاک گزارش‌شده نمی‌تواند از حداکثر فیزیکی این بازه‌ی زمانی
        // بیشتر باشد. برای epoch صفر رد می‌شود: deployTime همان genesis timestamp است، ولی
        // راه قابل‌اتکایی برای محدودکردن دقیق‌تر «زمان از genesis» غیر از «از deployTime»
        // وجود ندارد، و اولین فراخوانی توزیع یک شبکه ممکن است به‌طور مشروع یک دوره‌ی
        // ابتدایی طولانی را پوشش دهد (مثلاً بیشتر از MIN_DISTRIBUTION_INTERVAL اگر اوراکل
        // دیر شروع شده باشد) — این محدودیت فقط وقتی معنا دارد که lastDistributionTime یک
        // timestamp واقعی و on-chain از یک فراخوانی قبلی باشد.
        if (epochCount > 0) {
            uint256 elapsed = block.timestamp - lastDistributionTime;
            uint256 maxPossibleBlocks = elapsed / MIN_BLOCK_PERIOD_SECONDS;
            require(totalBlocks <= maxPossibleBlocks, "BlockRewardDistributor: reported blocks exceed physical maximum");
        }

        epochCount++;
        uint256 epochId = epochCount;

        // سهم خزانه فقط از ریوارد گرفته می‌شود، هرگز از فی
        uint256 treasuryAmount = (totalRewards * TREASURY_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 remainingRewards = totalRewards - treasuryAmount;

        // توزیع remainingRewards (به نسبت بلاک) + کل totalFees (به نسبت بلاک) — هر ولیدیتور
        // یک پرداخت ترکیبی واحد دریافت می‌کند.
        uint256 distributedRewards = 0;
        uint256 distributedFees = 0;
        uint256 validatorCount = 0;

        for (uint256 i = 0; i < validators.length; i++) {
            if (blocksMined[i] == 0) continue;

            address validator = validators[i];
            require(validator != address(0), "BlockRewardDistributor: zero validator address");
            require(REGISTRY.isValidator(validator), "BlockRewardDistributor: address is not an active validator");

            uint256 rewardShare = (remainingRewards * blocksMined[i]) / totalBlocks;
            uint256 feeShare = (totalFees * blocksMined[i]) / totalBlocks;
            uint256 payout = rewardShare + feeShare;
            if (payout == 0) continue;

            distributedRewards += rewardShare;
            distributedFees += feeShare;
            validatorCount++;

            epochValidatorRewardShare[epochId][validator] = rewardShare;
            epochValidatorFeeShare[epochId][validator] = feeShare;
            epochValidatorBlocks[epochId][validator] = blocksMined[i];
            totalRewardsPaid[validator] += rewardShare;
            totalFeesPaid[validator] += feeShare;
            totalBlocksRecorded[validator] += blocksMined[i];

            // یک انتقال ترکیبی واحد برای هر ولیدیتور در کل این فراخوانی
            (bool success, ) = validator.call{value: payout}("");
            require(success, "BlockRewardDistributor: validator transfer failed");

            emit ValidatorRewarded(epochId, validator, blocksMined[i], rewardShare, feeShare, payout);
        }

        // خرده‌ریز رند شده از تقسیم ریوارد و فی، به مبلغ خزانه اضافه می‌شود تا هیچ wei ای
        // توی قرارداد گیر نکند.
        uint256 rewardDust = remainingRewards - distributedRewards;
        uint256 feeDust = totalFees - distributedFees;
        uint256 totalTreasuryAmount = treasuryAmount + rewardDust + feeDust;

        if (totalTreasuryAmount > 0) {
            (bool tsuccess, ) = TREASURY.call{value: totalTreasuryAmount}("");
            require(tsuccess, "BlockRewardDistributor: treasury transfer failed");
        }

        totalDistributedToValidators += (distributedRewards + distributedFees);
        totalDistributedToTreasury += totalTreasuryAmount;
        lastDistributionTime = block.timestamp;

        epochs[epochId] = Epoch({
            timestamp: block.timestamp,
            totalRewards: totalRewards,
            totalFees: totalFees,
            treasuryAmount: totalTreasuryAmount,
            totalBlocksMined: totalBlocks,
            validatorCount: validatorCount
        });

        emit RewardsDistributed(epochId, totalRewards, totalFees, totalTreasuryAmount, totalBlocks, validatorCount);
    }

    // ------------------------------------------------------------------
    // توابع view / گزارش‌گیری
    // ------------------------------------------------------------------

    function getEpoch(uint256 epochId) external view returns (
        uint256 timestamp,
        uint256 totalRewards,
        uint256 totalFees,
        uint256 treasuryAmount,
        uint256 totalBlocksMined,
        uint256 validatorCount
    ) {
        Epoch storage e = epochs[epochId];
        return (e.timestamp, e.totalRewards, e.totalFees, e.treasuryAmount, e.totalBlocksMined, e.validatorCount);
    }

    function getValidatorEpochReward(uint256 epochId, address validator)
        external
        view
        returns (uint256 rewardShare, uint256 feeShare, uint256 blocks)
    {
        return (
            epochValidatorRewardShare[epochId][validator],
            epochValidatorFeeShare[epochId][validator],
            epochValidatorBlocks[epochId][validator]
        );
    }

    function getValidatorTotals(address validator)
        external
        view
        returns (uint256 totalReward, uint256 totalFee, uint256 totalBlocks)
    {
        return (totalRewardsPaid[validator], totalFeesPaid[validator], totalBlocksRecorded[validator]);
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getDistributionOracle() external view returns (address) {
        return distributionOracle;
    }

    function getLastEpochId() external view returns (uint256) {
        return epochCount;
    }

    function timeUntilNextDistribution() external view returns (uint256) {
        uint256 nextAllowed = lastDistributionTime + MIN_DISTRIBUTION_INTERVAL;
        if (block.timestamp >= nextAllowed) return 0;
        return nextAllowed - block.timestamp;
    }
}
