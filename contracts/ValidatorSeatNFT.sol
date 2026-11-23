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
/// @notice Every validator seat (including the 7 founders') is an ERC-721 token that can be bought and sold freely. The owner of the
///         token IS the owner of the seat: collateral, votes, rewards and the right to exit follow it. A transfer is only a
///         transfer of the token: ValidatorsRegistry is told through `onSeatTransferred` and moves the validator record, or
///         refuses (the whole transfer reverts) when the rules are not met. Rules (reference doc §9, enforced in the Registry):
///           - not in Exiting / RemovedInRecovery, no open penalty case;
///           - the buyer must be fully verified (IdentityRegistry.isFullyVerified), must never have been a validator, must not
///             hold a seat already and must not be somebody's operator key;
///           - the buyer must have ACCEPTED THE VALIDATORS' AGREEMENT FOR THIS SEAT BEFOREHAND: the buyer's own key calls
///             `acceptSeatAgreement(seatId)` on the Registry before the transfer (the signature itself is off-chain; the chain
///             records the acceptance), and the transfer reverts without it. The acceptance is bound to that one seat id and is
///             consumed by the transfer, so nobody becomes the owner of a seat without having accepted;
///           - the seller is treated as exited and can never become a validator again (agreement 15-6);
///           - an Active seat STAYS Active: the buyer takes over the seat, the operator key and the position in the active set
///             at once, and the buyer's vote counts from the transfer (a new voter).
///         Only ValidatorsRegistry mints (entry, lottery win, genesis founders), burns (when the owner exits) and reassigns
///         (`reassignSeat`: the migration of a seat to a new address of the same person after a lost owner key).
///         `tokenURI(id)` = baseURI + id; the base URI (initially https://validator-nft.surnet.org/) can be changed only by
///         FoundationDAO (an Execute proposal calling `setBaseURI`).
///
///         GENESIS: no constructor; the founders' seats are minted by genesis-seed-helpers/ValidatorSeatNFT_GenesisSeed.sol
///         (simulate-and-extract), in the same order as the founders are seeded in the Registry (ids 1..7).
contract ValidatorSeatNFT {
    address public constant REGISTRY = SurAddresses.VALIDATORS_REGISTRY;
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    string public constant name = "Sur Validator Seat";
    string public constant symbol = "SURSEAT";

    /// @notice Base of tokenURI. The initial value is part of the genesis storage written by the seed helper.
    string public baseURI = "https://validator-nft.surnet.org/";

    uint256 public totalMinted;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances; // 0 or 1: one seat per address
    /// @notice The seat id an owner holds (0 = none).
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
    // ERC-165 / ERC-721 metadata
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
    // ERC-721 core
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
        require(to.code.length == 0, "ValidatorSeatNFT: a seat owner must be a plain wallet (EOA)"); // RD-12
        require(_balances[to] == 0, "ValidatorSeatNFT: recipient already holds a seat");
        delete _approved[tokenId];
        _balances[from] = 0;
        _balances[to] = 1;
        _owners[tokenId] = to;
        delete seatOf[from];
        seatOf[to] = tokenId;
        emit Transfer(from, to, tokenId);
        // the Registry moves the validator record, or reverts the whole transfer (a rule is broken, or the buyer has not recorded the
        // acceptance of the validators' agreement for this seat)
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
    // Registry-only: mint at entry, burn at exit
    // ------------------------------------------------------------------
    function mintSeat(address to) external onlyRegistry returns (uint256 id) {
        return _mintSeat(to);
    }

    /// @notice Burns the seat of an owner who exits (no-op if the owner holds none).
    function burnSeat(address owner) external onlyRegistry {
        uint256 id = seatOf[owner];
        if (id == 0) return;
        delete _owners[id];
        delete _approved[id];
        delete seatOf[owner];
        _balances[owner] = 0;
        emit Transfer(owner, address(0), id);
    }

    /// @notice Registry-only: moves the seat of `from` to `to` WITHOUT calling the Registry hook (the Registry has already moved the validator
    ///         record in the same transaction). Used only for the migration of a seat to a new address of the SAME person after the owner
    ///         key was lost (ValidatorsRegistry.migrateSeat). The recipient must be a plain wallet and hold no seat; any approval of the
    ///         token is cleared. Returns the seat id.
    function reassignSeat(address from, address to) external onlyRegistry returns (uint256 id) {
        id = seatOf[from];
        require(id != 0, "ValidatorSeatNFT: no seat to reassign");
        require(to != address(0) && to != from, "ValidatorSeatNFT: bad recipient");
        require(to.code.length == 0, "ValidatorSeatNFT: a seat owner must be a plain wallet (EOA)");
        require(_balances[to] == 0, "ValidatorSeatNFT: recipient already holds a seat");
        delete _approved[id];
        _balances[from] = 0;
        _balances[to] = 1;
        _owners[id] = to;
        delete seatOf[from];
        seatOf[to] = id;
        emit Transfer(from, to, id);
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
