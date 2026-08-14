// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CreditProfile, Tier} from "./ScoreLib.sol";

/// @notice The subset of `CreditRegistry` this badge reads.
interface ICreditRegistry {
    function tierOf(address borrower) external view returns (Tier);
    function scoreOf(address borrower) external view returns (uint16);
    function profileOf(address borrower) external view returns (CreditProfile memory);
}

/// @notice ERC-5192 — minimal soulbound token.
interface IERC5192 {
    /// @notice Emitted when a token is locked, i.e. made non-transferable.
    event Locked(uint256 tokenId);
    /// @notice Emitted when a token is unlocked. Never emitted here; these are permanently bound.
    event Unlocked(uint256 tokenId);

    /// @notice Whether a token is soulbound. Always true for this collection.
    function locked(uint256 tokenId) external view returns (bool);
}

/// @title CreditTierSBT
/// @author CrossCredit
/// @notice A soulbound badge showing a borrower's credit tier, rendered fully on-chain.
///
/// @dev **Why soulbound.** A transferable reputation token is not a reputation token — it is a
/// tradeable asset, and a borrower could simply buy Platinum. Binding it to the address that
/// earned it is what makes the tier mean anything, so every transfer path reverts and
/// {IERC5192-locked} is permanently true.
///
/// **Why `sync` is permissionless.** This contract stores no judgement of its own: it reads
/// `CreditRegistry`, which only moves on cryptographically verified Sepolia transactions. So
/// letting anyone refresh anyone's badge adds no trust — the caller cannot influence the outcome,
/// only pay gas to bring the badge in line with facts already on chain.
///
/// That also keeps the registry's verification hot path free of cross-contract writes: the badge
/// pulls, rather than the registry pushing. The trade-off is that a badge can lag its tier until
/// someone calls {sync}, which is why {tierOfBadge} reads through to the registry for anything
/// that must be current.
///
/// **Why the artwork is on-chain.** An SVG built in the contract has no gateway, no pinning
/// service and no link to rot. A judge in 2027 sees the same badge as a judge today.
contract CreditTierSBT is ERC721, IERC5192 {
    using Strings for uint256;

    /// @notice The registry whose verified profiles this badge reflects.
    ICreditRegistry public immutable REGISTRY;

    /// @notice Token id held by each borrower, or 0 if they have none.
    mapping(address => uint256) public tokenOf;

    /// @notice The tier recorded at the last {sync} for each token.
    mapping(uint256 => Tier) public tierOfToken;

    uint256 private _nextTokenId = 1;

    /// @notice Emitted when a badge is minted or its tier changes.
    event TierSynced(address indexed borrower, uint256 indexed tokenId, Tier previousTier, Tier newTier);

    error Soulbound();
    error NoBadge(address borrower);
    error ZeroAddress();
    error MintRequiresConsent(address borrower);
    error NoVerifiedHistory(address borrower);

    constructor(address registry) ERC721("CrossCredit Credit Tier", "CCTIER") {
        if (registry == address(0)) revert ZeroAddress();
        REGISTRY = ICreditRegistry(registry);
    }

    /// @notice Mints or refreshes `borrower`'s badge to match their verified credit tier.
    ///
    /// @dev **Re-syncing** stays permissionless and idempotent — the caller cannot influence the
    /// outcome, only pay gas to bring a badge in line with facts already on chain.
    ///
    /// **The first mint is not.** It creates a permanent, non-transferable, unburnable token in
    /// someone's wallet, and the badge is a public statement about their creditworthiness. Letting
    /// a stranger do that to an arbitrary address meant anyone could brand any wallet Bronze for
    /// the price of gas, with no way to remove it — ERC-5192 has no burn by construction. So the
    /// initial mint requires either the borrower themselves or a genuine verified history, which
    /// is the only circumstance in which the badge says anything true.
    ///
    /// @param borrower The address whose badge to bring up to date.
    /// @return tokenId The borrower's badge id.
    function sync(address borrower) external returns (uint256 tokenId) {
        if (borrower == address(0)) revert ZeroAddress();

        Tier current = REGISTRY.tierOf(borrower);
        tokenId = tokenOf[borrower];

        if (tokenId == 0) {
            if (msg.sender != borrower && REGISTRY.profileOf(borrower).firstSeen == 0) {
                revert NoVerifiedHistory(borrower);
            }
            tokenId = _nextTokenId++;
            tokenOf[borrower] = tokenId;
            // `_mint`, not `_safeMint`: the receiver hook exists to stop tokens stranding in
            // contracts that cannot move them, and nothing can move this token anyway. Requiring
            // the hook would instead lock out every smart-contract wallet — exactly the users a
            // portable credit identity is for.
            _mint(borrower, tokenId);
            // ERC-5192 requires this at mint time for tokens that are bound from birth.
            emit Locked(tokenId);
        }

        Tier previous = tierOfToken[tokenId];
        tierOfToken[tokenId] = current;
        emit TierSynced(borrower, tokenId, previous, current);
    }

    /// @notice The borrower's tier as the registry sees it *right now*, which may be ahead of the
    /// badge if it has not been synced since their last verified repayment.
    function tierOfBadge(address borrower) external view returns (Tier) {
        return REGISTRY.tierOf(borrower);
    }

    /// @inheritdoc ERC721
    /// @dev Advertises ERC-5192 (`0xb45a3c0e`) alongside ERC-721. A soulbound token that does not
    /// declare itself soulbound is one a marketplace will happily list and a wallet will happily
    /// offer to send — the standard exists so tooling can know *before* trying and failing.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC5192
    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    /// @notice Fully on-chain metadata: base64 JSON wrapping a base64 SVG.
    /// @dev Renders live registry state rather than whatever was cached at the last {sync}, so the
    /// badge never displays a stale score. Split across helpers to stay within the EVM's stack
    /// limits without resorting to via-IR, which would change every contract's bytecode.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        address owner = _requireOwned(tokenId);
        Tier tier = REGISTRY.tierOf(owner);
        uint16 score = REGISTRY.scoreOf(owner);

        string memory json = string.concat(
            _header(tokenId, _tierName(tier)),
            _attributes(owner, tier, score),
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(_renderSvg(_tierName(tier), _tierColour(tier), score))),
            '"}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _header(uint256 tokenId, string memory name) private pure returns (string memory) {
        return string.concat(
            '{"name":"CrossCredit ',
            name,
            " #",
            tokenId.toString(),
            '","description":"A soulbound credit tier earned from repayment history on Ethereum Sepolia,'
            " verified on Creditcoin through the Attestcoin Protocol. Non-transferable by design:"
            ' reputation that can be bought is not reputation.",'
        );
    }

    function _attributes(address owner, Tier tier, uint16 score) private view returns (string memory) {
        CreditProfile memory profile = REGISTRY.profileOf(owner);
        return string.concat(
            '"attributes":[{"trait_type":"Tier","value":"',
            _tierName(tier),
            '"},{"trait_type":"Score","value":',
            uint256(score).toString(),
            '},{"trait_type":"On-time repayments","value":',
            uint256(profile.onTime).toString(),
            '},{"trait_type":"Late repayments","value":',
            uint256(profile.late).toString(),
            '},{"trait_type":"Loans closed","value":',
            uint256(profile.loansClosed).toString(),
            "}],"
        );
    }

    function _tierName(Tier tier) private pure returns (string memory) {
        if (tier == Tier.Platinum) return "Platinum";
        if (tier == Tier.Gold) return "Gold";
        if (tier == Tier.Silver) return "Silver";
        return "Bronze";
    }

    function _tierColour(Tier tier) private pure returns (string memory) {
        if (tier == Tier.Platinum) return "#e5e4e2";
        if (tier == Tier.Gold) return "#d4af37";
        if (tier == Tier.Silver) return "#c0c0c0";
        return "#cd7f32";
    }

    /// @dev The score arc sweeps proportionally to score/1000 over a 260-degree dial.
    function _renderSvg(string memory tierName, string memory colour, uint16 score)
        private
        pure
        returns (string memory)
    {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">',
            '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">',
            '<stop offset="0%" stop-color="#0f1115"/><stop offset="100%" stop-color="#1c2029"/>',
            "</linearGradient></defs>",
            '<rect width="400" height="400" fill="url(#g)"/>',
            '<circle cx="200" cy="180" r="92" fill="none" stroke="#2a2f3a" stroke-width="14"/>',
            '<circle cx="200" cy="180" r="92" fill="none" stroke="',
            colour,
            '" stroke-width="14" stroke-linecap="round" stroke-dasharray="',
            _arcLength(score),
            ' 578" transform="rotate(-90 200 180)"/>',
            '<text x="200" y="176" font-family="ui-monospace,monospace" font-size="54" font-weight="700" fill="#f5f6f8" text-anchor="middle">',
            uint256(score).toString(),
            "</text>",
            '<text x="200" y="206" font-family="ui-monospace,monospace" font-size="13" fill="#8b93a5" text-anchor="middle">/ 1000</text>',
            '<text x="200" y="312" font-family="ui-monospace,monospace" font-size="30" font-weight="700" fill="',
            colour,
            '" text-anchor="middle" letter-spacing="3">',
            tierName,
            "</text>",
            '<text x="200" y="345" font-family="ui-monospace,monospace" font-size="11" fill="#6b7280" text-anchor="middle" letter-spacing="1">CROSSCREDIT / VERIFIED CROSS-CHAIN</text>',
            "</svg>"
        );
    }

    /// @dev Circumference at r=92 is ~578; the dial fills proportionally to the score.
    function _arcLength(uint16 score) private pure returns (string memory) {
        return ((uint256(score) * 578) / 1000).toString();
    }

    // ─── Soulbinding ──────────────────────────────────────────────────────────────────────

    /// @dev The single chokepoint every mint, transfer and burn passes through in OZ v5. Allowing
    /// only `from == address(0)` permits minting and blocks everything else, including burns —
    /// a borrower cannot discard an inconvenient record.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    /// @dev Approvals are meaningless for a token that cannot move, and leaving them enabled would
    /// suggest otherwise in wallet UIs.
    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }
}
