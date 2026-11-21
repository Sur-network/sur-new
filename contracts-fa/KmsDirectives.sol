// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title KmsDirectives
/// @notice قرارداد بسیار کوچک genesis در `SurAddresses.KMS_DIRECTIVES` (0xBbBb...BbBb). برای هر کلید امضای سرویس SurKMS فقط یک
///         واقعیت نگه می‌دارد: آیا آن کلید «قطع» (frozen) است. KMS مقدار `frozen(slot)` را (هنگام شروع، در بازه‌های منظم و با رویداد)
///         می‌خواند و با کلید قطع‌شده امضا نمی‌کند. پول و قدرت یا وضعیت دیگری ندارد.
///         تعویض کلید اینجا نیست و در قراردادهای موجود می‌ماند (ValidatorsRegistry.setVerifier،
///         BlockRewardDistributor.setDistributionOracle، IdentityRegistry.setIdentityOracle). فهرست سرورها و قاعدهٔ هر کلید هم روی زنجیره نیست.
///
///         چه کسی می‌تواند وضعیت را عوض کند (تصمیم مالک ۲۰۲۶-۱۱-۲۱، sur-kms-spec.md بخش ۱۰):
///           - Slot.Verifier و Slot.DistributionOracle: فقط ValidatorsBoard (کنش `KmsFreeze` هیأت: حداقل ۳ رأی و اکثریت، ۱۴ روز،
///             باطل با تغییر هیأت).
///           - Slot.IdentityOracle: فقط FoundationDAO، با پیشنهاد `Execute` موجود (تغییری در FoundationDAO لازم نیست).
///         تنظیم وضعیتی که همان مقدار فعلی است بی‌صدا نادیده گرفته می‌شود (بدون رویداد) تا پیشنهاد تکراری هرگز گیر نکند.
///
///         GENESIS: بدون constructor و بدون seed حافظه (همهٔ وضعیت‌ها در آغاز false). فقط بایت‌کد اجرایی در `alloc` گذاشته می‌شود.
contract KmsDirectives {
    /// @dev سه کلید امضای سرویس SurKMS. اعداد بخشی از ABI (uint8) هستند و نباید عوض شوند.
    enum Slot { Verifier, DistributionOracle, IdentityOracle }

    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    /// @notice تا وقتی true است کلید این slot قطع است (KMS نباید با آن امضا کند).
    mapping(Slot => bool) public frozen;

    event FrozenChanged(Slot indexed slot, bool frozen);

    function setFrozen(Slot slot, bool isFrozen) external {
        if (slot == Slot.IdentityOracle) {
            require(msg.sender == FOUNDATION, "KmsDirectives: identityOracle is frozen only by FoundationDAO");
        } else {
            require(msg.sender == BOARD, "KmsDirectives: this key is frozen only by ValidatorsBoard");
        }
        if (frozen[slot] == isFrozen) return; // بی‌اثر: چیزی عوض نمی‌شود، رویدادی نیست
        frozen[slot] = isFrozen;
        emit FrozenChanged(slot, isFrozen);
    }
}
