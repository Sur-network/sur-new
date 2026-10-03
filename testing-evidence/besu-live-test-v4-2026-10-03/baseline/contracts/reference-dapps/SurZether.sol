// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// ⚠️⚠️⚠️  REFERENCE / PROPOSAL CONTRACT — NOT PRODUCTION-READY  ⚠️⚠️⚠️
//
// This is a REFERENCE DAPP, not one of Sur's six structural genesis contracts. It is not
// genesis-injected, has a normal constructor, and is deployed like any ordinary dApp — by the
// Foundation or by any independent developer, at any time.
//
// Full design rationale, phased rollout plan, and known risks are documented in
// sur-zether-confidential-transfers-proposal.md — read that document first.
//
// WHAT IS SAFE TO USE DIRECTLY FROM THIS FILE:
//   - The encrypted-balance storage layout (struct Ciphertext / Account).
//   - The elliptic-curve homomorphic arithmetic (_ecAdd / _ecMul), which calls Ethereum's
//     standard ecAdd (0x06) / ecMul (0x07) precompiles — precompiles present on every
//     standard EVM client, including Besu, without any client modification.
//   - The overall contract flow (register → fund → transfer → burn).
//
// WHAT IS **NOT** SAFE TO USE DIRECTLY — MUST BE REPLACED BEFORE ANY REAL DEPLOYMENT:
//   - `IZetherVerifier` is an ILLUSTRATIVE interface. It shows the SHAPE of what a Zether
//     zero-knowledge proof verifier needs to check, but its exact parameters have NOT been
//     validated against any specific published Zether reference implementation. The actual
//     verifier contract implementing this interface (Σ-Bullets / Bulletproofs verification)
//     MUST be forked from an audited, published, well-reviewed Zether implementation — never
//     written from scratch without a formal cryptography review. A subtle bug in this layer
//     can allow forged balances or theft of funds. Recommended starting point (not yet
//     independently audited for Sur's use case — see sur-zether-confidential-transfers-proposal.md,
//     section 2, for the full evaluation): https://github.com/Consensys/anonymous-zether
//     (client-side library counterpart: https://github.com/kaleido-io/anonymous-zether-client).
//     ⚠️ Do not confuse this with github.com/ZetherOrg/go-zether, an unrelated PoW blockchain
//     that happens to share the "Zether" name.
//   - This file has NEVER been audited, tested against a live network, or reviewed by a
//     cryptography specialist. Do not deploy it — on Sur mainnet, testnet, or anywhere else
//     handling real value — before completing the phased plan in the proposal document
//     (reference-implementation selection → curve/precompile compatibility check → independent
//     security audit → deployment as an ordinary reference dApp).
// ============================================================================

/// @notice ILLUSTRATIVE interface for a Zether-style zero-knowledge proof verifier.
/// @dev The exact parameter shapes here are a reasonable approximation of what a Σ-Bullets
///      transfer/burn proof needs to check (sender's current encrypted balance, both parties'
///      public keys, the encrypted transfer deltas, and the proof bytes) — but they are NOT
///      guaranteed to match any specific real implementation byte-for-byte. Whoever forks a
///      real, audited Zether verifier MUST adjust this interface (and the call sites in
///      SurZether below) to match that implementation's actual proof structure exactly.
interface IZetherVerifier {
    /// @dev Verifies that a confidential transfer is well-formed: the sender's balance after
    ///      subtracting the encrypted amount remains non-negative, the same amount is added to
    ///      the receiver, and no value was created or destroyed — all without revealing the
    ///      amount itself. Parameters are grouped into structs (rather than flat uint256
    ///      arrays) specifically to keep EVM stack usage low enough to compile without
    ///      `viaIR` — see sur-contracts-deploy-notes.md for why this project avoids `viaIR`.
    function verifyTransfer(
        SurZetherTypes.Ciphertext memory senderBalance,
        SurZetherTypes.PubKey memory senderPubKey,
        SurZetherTypes.PubKey memory receiverPubKey,
        SurZetherTypes.Ciphertext memory deltaFrom,
        SurZetherTypes.Ciphertext memory deltaTo,
        bytes memory proof
    ) external view returns (bool);

    /// @dev Verifies that a burn (confidential balance -> plain Suren) of exactly `amount` is
    ///      valid against the account's current encrypted balance, without revealing anything
    ///      about the account's balance beyond the fact that it covers `amount`.
    function verifyBurn(
        SurZetherTypes.PubKey memory pubKey,
        SurZetherTypes.Ciphertext memory balance,
        uint256 amount,
        bytes memory proof
    ) external view returns (bool);
}

/// @dev Shared struct definitions, kept in their own library so both `SurZether` and any
///      `IZetherVerifier` implementation reference the exact same types.
library SurZetherTypes {
    struct Ciphertext {
        uint256 cx;
        uint256 cy;
        uint256 dx;
        uint256 dy;
    }

    struct PubKey {
        uint256 x;
        uint256 y;
    }
}

contract SurZether {
    // ------------------------------------------------------------------
    // BN254 (alt_bn128) curve constants — this is the curve Ethereum's standard ecAdd/ecMul
    // precompiles (addresses 0x06 / 0x07) operate on. See the proposal document, section 5,
    // for the open question of whether the chosen reference Zether implementation's proof
    // system is compatible with this specific curve, or needs adaptation.
    // ------------------------------------------------------------------
    uint256 internal constant GX = 1;
    uint256 internal constant GY = 2;
    uint256 internal constant FIELD_MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    struct Account {
        uint256 pubKeyX;
        uint256 pubKeyY;
        bool registered;
    }

    /// @dev Accounts are keyed by a hash of their Zether public key — deliberately NOT by
    ///      Ethereum address, since a single Ethereum address may want multiple independent
    ///      confidential accounts, and the Zether public key is a separate elliptic-curve key
    ///      pair the client manages (see the proposal document, section 6).
    mapping(bytes32 => Account) public accounts;
    mapping(bytes32 => SurZetherTypes.Ciphertext) public balances;

    IZetherVerifier public immutable verifier;

    event Registered(bytes32 indexed accountKey);
    event Funded(bytes32 indexed accountKey, uint256 amount);
    event Transferred(bytes32 indexed fromKey, bytes32 indexed toKey);
    event Burned(bytes32 indexed accountKey, uint256 amount);

    constructor(address _verifier) {
        require(_verifier != address(0), "SurZether: zero verifier address");
        verifier = IZetherVerifier(_verifier);
    }

    // ------------------------------------------------------------------
    // Registration — associates a Zether public key (an EC point, managed client-side) with
    // an on-chain confidential account. Anyone may register any number of accounts.
    // ------------------------------------------------------------------
    function register(uint256 pubKeyX, uint256 pubKeyY) external {
        bytes32 key = _accountKey(pubKeyX, pubKeyY);
        require(!accounts[key].registered, "SurZether: already registered");
        accounts[key] = Account({pubKeyX: pubKeyX, pubKeyY: pubKeyY, registered: true});
        emit Registered(key);
    }

    // ------------------------------------------------------------------
    // Funding — converts plain (public) Suren into an initial encrypted balance entry.
    // ⚠️ The funded AMOUNT is intentionally PUBLIC here — this matches Zether's original
    // design. Confidentiality only applies to `transfer` calls that happen afterward; the
    // deposit itself is as visible as any normal transaction.
    // ------------------------------------------------------------------
    function fund(bytes32 accountKey) external payable {
        require(accounts[accountKey].registered, "SurZether: account not registered");
        require(msg.value > 0, "SurZether: zero-value funding");

        (uint256 mx, uint256 my) = _ecMul(GX, GY, msg.value);
        SurZetherTypes.Ciphertext storage bal = balances[accountKey];
        (bal.dx, bal.dy) = _ecAdd(bal.dx, bal.dy, mx, my);
        // The C-component is unaffected: a "plaintext" contribution is an ElGamal ciphertext
        // with blinding factor r = 0, i.e. C = 0*G = the point at infinity, which ecAdd leaves
        // the existing C-component unchanged when added to it.

        emit Funded(accountKey, msg.value);
    }

    // ------------------------------------------------------------------
    // Confidential transfer — the core operation. See the top-of-file warning: `proof`
    // verification is entirely delegated to `verifier`, which MUST be an audited, real Zether
    // verifier before this function is ever used with real value.
    // ------------------------------------------------------------------
    function transfer(
        bytes32 fromKey,
        bytes32 toKey,
        SurZetherTypes.Ciphertext calldata deltaFrom, // encryption of -amount, sender's key
        SurZetherTypes.Ciphertext calldata deltaTo,   // encryption of +amount, receiver's key
        bytes calldata proof
    ) external {
        require(accounts[fromKey].registered, "SurZether: sender not registered");
        require(accounts[toKey].registered, "SurZether: receiver not registered");
        require(fromKey != toKey, "SurZether: self-transfer not allowed");

        bool ok = _checkTransferProof(fromKey, toKey, deltaFrom, deltaTo, proof);
        require(ok, "SurZether: invalid transfer proof");

        _applyTransfer(fromKey, toKey, deltaFrom, deltaTo);

        emit Transferred(fromKey, toKey);
    }

    /// @dev Split out of `transfer` purely to keep EVM stack usage low enough to compile
    ///      without `viaIR` (see the note on IZetherVerifier above) — behavior is unchanged.
    function _checkTransferProof(
        bytes32 fromKey,
        bytes32 toKey,
        SurZetherTypes.Ciphertext calldata deltaFrom,
        SurZetherTypes.Ciphertext calldata deltaTo,
        bytes calldata proof
    ) private view returns (bool) {
        Account storage sender = accounts[fromKey];
        Account storage receiver = accounts[toKey];

        return verifier.verifyTransfer(
            balances[fromKey],
            SurZetherTypes.PubKey({x: sender.pubKeyX, y: sender.pubKeyY}),
            SurZetherTypes.PubKey({x: receiver.pubKeyX, y: receiver.pubKeyY}),
            deltaFrom,
            deltaTo,
            proof
        );
    }

    /// @dev Split out of `transfer` for the same stack-depth reason as `_checkTransferProof`.
    function _applyTransfer(
        bytes32 fromKey,
        bytes32 toKey,
        SurZetherTypes.Ciphertext calldata deltaFrom,
        SurZetherTypes.Ciphertext calldata deltaTo
    ) private {
        SurZetherTypes.Ciphertext storage senderBalance = balances[fromKey];
        (senderBalance.cx, senderBalance.cy) =
            _ecAdd(senderBalance.cx, senderBalance.cy, deltaFrom.cx, deltaFrom.cy);
        (senderBalance.dx, senderBalance.dy) =
            _ecAdd(senderBalance.dx, senderBalance.dy, deltaFrom.dx, deltaFrom.dy);

        SurZetherTypes.Ciphertext storage receiverBalance = balances[toKey];
        (receiverBalance.cx, receiverBalance.cy) =
            _ecAdd(receiverBalance.cx, receiverBalance.cy, deltaTo.cx, deltaTo.cy);
        (receiverBalance.dx, receiverBalance.dy) =
            _ecAdd(receiverBalance.dx, receiverBalance.dy, deltaTo.dx, deltaTo.dy);
    }

    // ------------------------------------------------------------------
    // Burn — converts an encrypted balance back into plain, withdrawable Suren. The withdrawn
    // AMOUNT becomes public at this point (inherent to leaving the confidential system), but
    // the account's remaining encrypted balance stays hidden.
    // ------------------------------------------------------------------
    function burn(bytes32 accountKey, uint256 amount, bytes calldata proof) external {
        require(accounts[accountKey].registered, "SurZether: account not registered");
        require(amount > 0, "SurZether: zero-value burn");
        require(address(this).balance >= amount, "SurZether: insufficient contract balance");

        bool ok = _checkBurnProof(accountKey, amount, proof);
        require(ok, "SurZether: invalid burn proof");

        SurZetherTypes.Ciphertext storage bal = balances[accountKey];
        (uint256 mx, uint256 my) = _ecMul(GX, GY, amount);
        (bal.dx, bal.dy) = _ecAdd(bal.dx, bal.dy, mx, _negateY(my));

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "SurZether: Suren withdrawal failed");

        emit Burned(accountKey, amount);
    }

    /// @dev Split out of `burn` for the same stack-depth reason as `_checkTransferProof`.
    function _checkBurnProof(bytes32 accountKey, uint256 amount, bytes calldata proof)
        private
        view
        returns (bool)
    {
        Account storage acc = accounts[accountKey];
        return verifier.verifyBurn(
            SurZetherTypes.PubKey({x: acc.pubKeyX, y: acc.pubKeyY}),
            balances[accountKey],
            amount,
            proof
        );
    }

    // ------------------------------------------------------------------
    // Internal helpers — elliptic-curve arithmetic and account keying.
    // ------------------------------------------------------------------

    function _accountKey(uint256 x, uint256 y) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(x, y));
    }

    function _negateY(uint256 y) internal pure returns (uint256) {
        return FIELD_MODULUS - (y % FIELD_MODULUS);
    }

    /// @dev Calls Ethereum's standard ecAdd precompile (address 0x06) — present on every
    ///      standard EVM client, including Besu, with no client-side modification required.
    function _ecAdd(uint256 x1, uint256 y1, uint256 x2, uint256 y2)
        internal
        view
        returns (uint256 x3, uint256 y3)
    {
        bool success;
        assembly {
            let input := mload(0x40)
            mstore(input, x1)
            mstore(add(input, 0x20), y1)
            mstore(add(input, 0x40), x2)
            mstore(add(input, 0x60), y2)
            success := staticcall(gas(), 0x06, input, 0x80, input, 0x40)
            x3 := mload(input)
            y3 := mload(add(input, 0x20))
        }
        require(success, "SurZether: ecAdd precompile call failed");
    }

    /// @dev Calls Ethereum's standard ecMul precompile (address 0x07) — present on every
    ///      standard EVM client, including Besu, with no client-side modification required.
    function _ecMul(uint256 x1, uint256 y1, uint256 scalar)
        internal
        view
        returns (uint256 x2, uint256 y2)
    {
        bool success;
        assembly {
            let input := mload(0x40)
            mstore(input, x1)
            mstore(add(input, 0x20), y1)
            mstore(add(input, 0x40), scalar)
            success := staticcall(gas(), 0x07, input, 0x60, input, 0x40)
            x2 := mload(input)
            y2 := mload(add(input, 0x20))
        }
        require(success, "SurZether: ecMul precompile call failed");
    }
}
