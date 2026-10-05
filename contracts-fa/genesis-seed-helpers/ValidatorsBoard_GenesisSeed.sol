// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// کمک‌کنندهٔ seed کردن GENESIS: موقت است و هرگز روی زنجیرهٔ واقعی مستقر نمی‌شود.
//
// همتای contracts/ValidatorsBoard.sol. قرارداد واقعی constructor ندارد (در `alloc` بلاک genesis تزریق می‌شود)، ولی
// `boardMembers` (آرایهٔ پویا) و `isBoardMember` (mapping) را نمی‌شود با ساختار سطح‌قرارداد Solidity پر کرد. این کمک‌کننده همان
// منطق seed را در یک constructor بدون آرگومان اجرا می‌کند (آدرس اعضای مؤسس و زمان genesis مستقیم در همین فایل نوشته می‌شوند)،
// تا با یک‌بار اجرا روی یک زنجیرهٔ محلی موقت (Anvil یا Hardhat) خودِ EVM حساب slot با keccak256 را برای آرایه و mapping انجام دهد.
//
// همچنین `boardVersion` (برابر ۱) و `boardMonthId` (ماه میلادی UTC زمان genesis) را می‌نویسد. بدون boardMonthId هیأت مؤسس تا نخستین
// refreshBoard() اختیاری ندارد. seatMembershipEpoch مؤسسان صفر می‌ماند که برابر membershipEpoch آن‌ها در Registry است.
//
// نحوهٔ استفادهٔ ابزار genesis از این فایل:
//   ۱. FILL_IN: هر آدرس جای‌گیر را با آدرس نهایی هر عضو مؤسس هیأت و GENESIS_TIMESTAMP جای‌گیر را با زمان واقعی genesis
//      جایگزین کنید (باید با `timestamp` فایل genesis.json یکی باشد).
//   ۲. این فایل را (بدون آرگومان constructor) روی یک زنجیرهٔ محلی موقت مستقر کنید.
//   ۳. storage نهایی‌اش را بیرون بکشید (eth_getStorageAt برای هر slot لمس‌شده، یا ابزار state-dump).
//   ۴. این storage را به‌همراه bytecode runtime ValidatorsBoard.sol واقعی (نه bytecode این فایل) زیر آدرس 0x4444...4444 در `alloc`
//      فایل genesis.json بنویسید.
//   ۵. پس از ساخت بررسی کنید: boardMonthId برابر ماه زمان genesis و boardVersion برابر ۱ باشد.
//
// قاعدهٔ چیدمان storage: ترتیب و نوع متغیرهای زیر باید دقیقاً با ValidatorsBoard.sol واقعی یکی باشد. هر وقت قرارداد واقعی عوض شد
// این فایل را باید دستی به‌روز کرد.
// ============================================================================
contract ValidatorsBoard_GenesisSeed {
    uint256 public constant BOARD_SIZE = 5;

    address[] private boardMembers;
    mapping(address => bool) public isBoardMember;

    // slotهای ۲ تا ۵ قرارداد واقعی (voterCandidates، hasVotedFor، candidateVoters، voterIndexInCandidateVoters): فقط جای‌گیر.
    uint256[4] private __gap1;

    // slotهای ۶ و ۷ قرارداد واقعی. هیأت مؤسس در ماه میلادی زمان genesis خدمت می‌کند؛ بدون boardMonthId تا نخستین
    // refreshBoard() اختیاری نداشت.
    uint256 public boardVersion;
    uint256 public boardMonthId;

    // FILL_IN: زمان واقعی genesis شبکهٔ زنده (باید با `timestamp` فایل genesis.json یکی باشد).
    uint256 internal constant GENESIS_TIMESTAMP = 0;

    // ------------------------------------------------------------------
    // constructor بدون آرگومان: اعضای مؤسس هیأت (دقیقاً BOARD_SIZE = ۵ نفر) مستقیم در همین پایین نوشته شده‌اند.
    // FILL_IN: پیش از استقرار این فایل، هر address(0) را با آدرس نهایی هر عضو مؤسس هیأت جایگزین کنید.
    // ------------------------------------------------------------------
    constructor() {
        address[BOARD_SIZE] memory initialBoardMembers = [
            address(0), // Alireza Zojaji
            address(0), // Citex Corp.
            address(0), // Mahkameh Sharifzad
            //address(0), // Mostafa Naghipoorfar
            address(0), // Sepehr Mohammadi
            address(0) // Siavash Tafazzoli
        ];

        for (uint256 i = 0; i < BOARD_SIZE; i++) {
            address m = initialBoardMembers[i];
            require(m != address(0), "GenesisSeed: zero address - fill in real values first");
            require(!isBoardMember[m], "GenesisSeed: duplicate initial board member");
            boardMembers.push(m);
            isBoardMember[m] = true;
        }

        boardVersion = 1;
        boardMonthId = _monthIdOf(GENESIS_TIMESTAMP);
    }

    /// @dev همان الگوریتم تقویم میلادی ValidatorsBoard.monthIdOf: سال * ۱۲ + (ماه - ۱)، UTC.
    function _monthIdOf(uint256 timestamp) internal pure returns (uint256) {
        uint256 z = timestamp / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 year = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 month = mp < 10 ? mp + 3 : mp - 9;
        if (month <= 2) year += 1;
        return year * 12 + (month - 1);
    }

    // نمای کمکی برای بازبینی دستی هنگام آزمون — در استخراج storage نقشی ندارد.
    function getBoardMembers() external view returns (address[] memory) {
        return boardMembers;
    }
}
