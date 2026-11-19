// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title FoundationMembers
/// @notice دفتر اعضای بنیاد سور و حساب سهم‌الشرکه‌ی هر عضو.
///         برای همه‌ی قراردادهای دیگر فقط‌خواندنی است (FoundationDAO از آن برای وزن رأی مجمع و برای
///         قاعده‌ی صلاحیت هیأت — «عضو بنیاد یا نماینده‌ی عضو حقوقی» — استفاده می‌کند). فهرست را فقط
///         FoundationDAO می‌تواند تغییر دهد، و FoundationDAO آن را فقط با تصمیم مجمع «فوق‌العاده»
///         عوض می‌کند (مواد ۷ و ۱۴ تا ۱۸ اساسنامه).
///
///         استقرار در GENESIS: constructor ندارد — در `alloc` بلاک genesis زیر
///         SurAddresses.FOUNDATION_MEMBERS تزریق می‌شود. فهرست اولیه توسط
///         genesis-seed-helpers/FoundationMembers_GenesisSeed.sol (که از این قرارداد ارث می‌برد، پس
///         چیدمان storage به‌حکم ساختار یکی است) با روش شبیه‌سازی و استخراج seed می‌شود.
///
///         🔶 وقتی یک عضو حذف شود سهم‌هایش از `totalShares` کم می‌شود (انتقال خودکار ندارد)؛
///         تکلیف آن سهم‌ها تصمیم مجمع فوق‌العاده است و خارج از زنجیره ثبت می‌شود.
contract FoundationMembers {
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    enum PersonType { Individual, Legal }

    struct Member {
        string name;
        PersonType personType;
        address representative; // فقط برای اعضای حقوقی؛ برای شخص حقیقی صفر
        uint256 shares;
    }

    /// @dev نمای تخت یک عضو که getAllMembers() برمی‌گرداند.
    struct MemberView {
        address account;
        string name;
        PersonType personType;
        address representative;
        uint256 shares;
    }

    address[] private _list;
    mapping(address => uint256) private _index; // اندیس ۱-مبنا در _list؛ ۰ یعنی عضو نیست
    mapping(address => Member) private _member;
    /// @notice نماینده => عضو حقوقی که نمایندگی‌اش را دارد (اگر نباشد صفر)
    mapping(address => address) public representativeOf;
    uint256 public totalShares;

    event MemberAdded(address indexed account, string name, PersonType personType, address representative, uint256 shares);
    event MemberRemoved(address indexed account, uint256 shares);
    event SharesTransferred(address indexed from, address indexed to, uint256 amount);
    event RepresentativeSet(address indexed member, address indexed representative);

    modifier onlyFoundation() {
        require(msg.sender == FOUNDATION, "FoundationMembers: only FoundationDAO");
        _;
    }

    // ------------------------------------------------------------------
    // نمایش
    // ------------------------------------------------------------------
    function isMember(address account) public view returns (bool) {
        return _index[account] != 0;
    }

    function shareOf(address account) external view returns (uint256) {
        return _member[account].shares;
    }

    function getMemberCount() external view returns (uint256) {
        return _list.length;
    }

    function memberInfo(address account) external view returns (
        string memory name,
        PersonType personType,
        address representative,
        uint256 shares
    ) {
        Member storage m = _member[account];
        return (m.name, m.personType, m.representative, m.shares);
    }

    function getAllMembers() external view returns (MemberView[] memory out) {
        out = new MemberView[](_list.length);
        for (uint256 i = 0; i < _list.length; i++) {
            Member storage m = _member[_list[i]];
            out[i] = MemberView(_list[i], m.name, m.personType, m.representative, m.shares);
        }
    }

    /// @notice قاعده‌ی صلاحیت هیأت: عضو بنیاد، یا نماینده‌ی یک عضو حقوقی.
    function isMemberOrRepresentative(address who) external view returns (bool) {
        return isMember(who) || representativeOf[who] != address(0);
    }

    /// @notice عضوی که `who` رأیش را به‌جای او می‌دهد: اگر عضو باشد خودش، اگر نماینده باشد عضوِ
    ///         نمایندگی‌شده، وگرنه آدرس صفر. برای این‌که یک عضو حقوقی و نماینده‌اش هرگز دو بار رأی ندهند.
    function memberOfVoter(address who) external view returns (address) {
        if (isMember(who)) return who;
        return representativeOf[who];
    }

    // ------------------------------------------------------------------
    // تغییرات — فقط FoundationDAO (پس از تصمیم مجمع فوق‌العاده)
    // ------------------------------------------------------------------
    function addMember(
        address account,
        string calldata name,
        PersonType personType,
        address representative,
        uint256 shares
    ) external onlyFoundation {
        _addMember(account, name, personType, representative, shares);
    }

    function removeMember(address account) external onlyFoundation {
        require(isMember(account), "FoundationMembers: not a member");
        Member storage m = _member[account];
        uint256 removedShares = m.shares;
        totalShares -= removedShares;
        if (m.representative != address(0)) delete representativeOf[m.representative];

        uint256 idx = _index[account] - 1;
        uint256 last = _list.length - 1;
        if (idx != last) {
            address moved = _list[last];
            _list[idx] = moved;
            _index[moved] = idx + 1;
        }
        _list.pop();
        delete _index[account];
        delete _member[account];
        emit MemberRemoved(account, removedShares);
    }

    function transferShares(address from, address to, uint256 amount) external onlyFoundation {
        require(isMember(from) && isMember(to), "FoundationMembers: both must be members");
        require(from != to, "FoundationMembers: same account");
        require(amount > 0 && amount <= _member[from].shares, "FoundationMembers: bad amount");
        _member[from].shares -= amount;
        _member[to].shares += amount;
        emit SharesTransferred(from, to, amount);
    }

    function setRepresentative(address account, address representative) external onlyFoundation {
        require(isMember(account), "FoundationMembers: not a member");
        Member storage m = _member[account];
        require(m.personType == PersonType.Legal, "FoundationMembers: only legal-person members");
        _checkRepresentative(account, representative);
        if (m.representative != address(0)) delete representativeOf[m.representative];
        m.representative = representative;
        representativeOf[representative] = account;
        emit RepresentativeSet(account, representative);
    }

    // ------------------------------------------------------------------
    // داخلی (کمک‌کننده‌ی seed در genesis هم از آن استفاده می‌کند)
    // ------------------------------------------------------------------
    function _addMember(
        address account,
        string memory name,
        PersonType personType,
        address representative,
        uint256 shares
    ) internal {
        require(account != address(0), "FoundationMembers: zero address");
        require(!isMember(account) && representativeOf[account] == address(0), "FoundationMembers: account in use");
        require(bytes(name).length > 0, "FoundationMembers: empty name");
        require(shares > 0, "FoundationMembers: zero shares");
        if (personType == PersonType.Legal) {
            _checkRepresentative(account, representative);
            representativeOf[representative] = account;
        } else {
            require(representative == address(0), "FoundationMembers: individual has no representative");
        }
        _list.push(account);
        _index[account] = _list.length;
        _member[account] = Member(name, personType, representative, shares);
        totalShares += shares;
        emit MemberAdded(account, name, personType, representative, shares);
    }

    function _checkRepresentative(address account, address representative) private view {
        require(representative != address(0) && representative != account, "FoundationMembers: bad representative");
        require(!isMember(representative) && representativeOf[representative] == address(0), "FoundationMembers: representative in use");
    }
}
