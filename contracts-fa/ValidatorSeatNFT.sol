// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

interface ISeatRegistryHook {
    function onSeatTransferred(uint256 seatId, address from, address to) external;
}

/// @title ValidatorSeatNFT
/// @notice هر جایگاه ولیدیتور (از جمله ۷ جایگاه مؤسسین) یک توکن ERC-721 است که آزادانه قابل خرید و فروش است. مالک
///         توکن همان مالک جایگاه است: وثیقه، رأی‌ها، پاداش‌ها و حق خروج همراه آن می‌روند. انتقال فقط انتقال توکن است:
///         ValidatorsRegistry از طریق `onSeatTransferred` باخبر می‌شود و رکورد ولیدیتور را جابه‌جا می‌کند، یا وقتی
///         قواعد رعایت نشده باشد رد می‌کند (کل انتقال revert می‌شود). قواعد (سند مرجع §9، اعمال‌شده در Registry):
///           - در وضعیت Exiting / RemovedInRecovery نباشد و پروندهٔ جریمهٔ بازی نداشته باشد؛
///           - خریدار باید کاملاً احراز هویت شده باشد (IdentityRegistry.isFullyVerified)، هرگز ولیدیتور نبوده باشد،
///             پیش‌تر جایگاهی نداشته باشد و کلید اپراتور کس دیگری نباشد؛
///           - فروشنده خروج‌کرده محسوب می‌شود و دیگر هرگز نمی‌تواند ولیدیتور شود (توافق‌نامه ۱۵-۶)؛
///           - جایگاه Active هنگام انتقال به SelfSuspended می‌رود: خریدار باید توافق‌نامهٔ ولیدیتورها را بپذیرد
///             (`acceptSeatTransfer` در Registry) و Verifier باید گره را بررسی کند تا دوباره Active شود.
///         فقط ValidatorsRegistry mint می‌کند (ورود، برد قرعه‌کشی، مؤسسین genesis) و burn می‌کند (وقتی مالک خارج می‌شود).
///         `tokenURI(id)` = baseURI + id؛ آدرس پایه (در آغاز https://validator-nft.surnet.org/) را فقط
///         FoundationDAO می‌تواند تغییر دهد (پیشنهاد Execute که `setBaseURI` را صدا می‌زند).
///
///         GENESIS: constructor ندارد؛ جایگاه‌های مؤسسین را genesis-seed-helpers/ValidatorSeatNFT_GenesisSeed.sol
///         (شبیه‌سازی و استخراج) mint می‌کند، به همان ترتیبی که مؤسسین در Registry seed می‌شوند (شناسه‌های ۱ تا ۷).
contract ValidatorSeatNFT {
    address public constant REGISTRY = SurAddresses.VALIDATORS_REGISTRY;
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    string public constant name = "Sur Validator Seat";
    string public constant symbol = "SURSEAT";

    /// @notice مبنای tokenURI. مقدار اولیه بخشی از storage genesis است که seed helper می‌نویسد.
    string public baseURI = "https://validator-nft.surnet.org/";

    uint256 public totalMinted;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances; // ۰ یا ۱: یک جایگاه برای هر آدرس
    /// @notice شناسهٔ جایگاهی که یک مالک دارد (۰ = ندارد).
    mapping(address => uint256) public seatOf;
    mapping(uint256 => address) private _approved;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event BaseURIChanged(string newBaseURI);

    modifier onlyRegistry() {
        require(msg.sender == REGISTRY, "ValidatorSeatNFT: only ValidatorsRegistry");
        _;
    }

    // ------------------------------------------------------------------
    // ERC-165 / فراداده‌ی ERC-721
    // ------------------------------------------------------------------
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 || id == 0x80ac58cd || id == 0x5b5e139f;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_owners[tokenId] != address(0), "ValidatorSeatNFT: nonexistent token");
        return string.concat(baseURI, _toString(tokenId));
    }

    function setBaseURI(string calldata newBaseURI) external {
        require(msg.sender == FOUNDATION, "ValidatorSeatNFT: only FoundationDAO");
        baseURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    // ------------------------------------------------------------------
    // هستهٔ ERC-721
    // ------------------------------------------------------------------
    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "ValidatorSeatNFT: zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "ValidatorSeatNFT: nonexistent token");
        return o;
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "ValidatorSeatNFT: nonexistent token");
        return _approved[tokenId];
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function approve(address to, uint256 tokenId) external {
        address o = ownerOf(tokenId);
        require(msg.sender == o || _operatorApprovals[o][msg.sender], "ValidatorSeatNFT: not owner nor approved for all");
        _approved[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        address o = ownerOf(tokenId);
        require(o == from, "ValidatorSeatNFT: wrong owner");
        require(
            msg.sender == o || _approved[tokenId] == msg.sender || _operatorApprovals[o][msg.sender],
            "ValidatorSeatNFT: not owner nor approved"
        );
        require(to != address(0), "ValidatorSeatNFT: transfer to the zero address");
        require(_balances[to] == 0, "ValidatorSeatNFT: recipient already holds a seat");
        delete _approved[tokenId];
        _balances[from] = 0;
        _balances[to] = 1;
        _owners[tokenId] = to;
        delete seatOf[from];
        seatOf[to] = tokenId;
        emit Transfer(from, to, tokenId);
        // Registry رکورد ولیدیتور را جابه‌جا می‌کند، یا کل انتقال را revert می‌کند
        ISeatRegistryHook(REGISTRY).onSeatTransferred(tokenId, from, to);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 r) {
                require(r == IERC721Receiver.onERC721Received.selector, "ValidatorSeatNFT: receiver rejected");
            } catch {
                revert("ValidatorSeatNFT: receiver rejected");
            }
        }
    }

    // ------------------------------------------------------------------
    // فقط Registry: mint هنگام ورود، burn هنگام خروج
    // ------------------------------------------------------------------
    function mintSeat(address to) external onlyRegistry returns (uint256 id) {
        return _mintSeat(to);
    }

    /// @notice جایگاه مالکی را که خارج می‌شود burn می‌کند (اگر جایگاهی نداشته باشد کاری نمی‌کند).
    function burnSeat(address owner) external onlyRegistry {
        uint256 id = seatOf[owner];
        if (id == 0) return;
        delete _owners[id];
        delete _approved[id];
        delete seatOf[owner];
        _balances[owner] = 0;
        emit Transfer(owner, address(0), id);
    }

    function _mintSeat(address to) internal returns (uint256 id) {
        require(to != address(0) && _balances[to] == 0, "ValidatorSeatNFT: bad recipient");
        id = ++totalMinted;
        _owners[id] = to;
        _balances[to] = 1;
        seatOf[to] = id;
        emit Transfer(address(0), to, id);
    }

    function _toString(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 digits;
        for (uint256 t = v; t != 0; t /= 10) digits++;
        bytes memory b = new bytes(digits);
        while (v != 0) {
            digits--;
            b[digits] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(b);
    }
}
