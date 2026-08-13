// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {CreditTierSBT, IERC5192, ICreditRegistry} from "../src/creditcoin/CreditTierSBT.sol";
import {CreditProfile, Tier} from "../src/creditcoin/ScoreLib.sol";

/// @dev Stands in for `CreditRegistry` so tier transitions can be driven directly. The registry's
/// own path from proof to tier is covered exhaustively in `CreditRegistry.t.sol`.
contract StubRegistry is ICreditRegistry {
    mapping(address => Tier) public tiers;
    mapping(address => uint16) public scores;
    mapping(address => CreditProfile) public storedProfiles;

    function set(address borrower, Tier tier, uint16 score) external {
        tiers[borrower] = tier;
        scores[borrower] = score;
        storedProfiles[borrower].score = score;
        storedProfiles[borrower].onTime = 5;
        storedProfiles[borrower].loansClosed = 3;
    }

    function tierOf(address borrower) external view returns (Tier) {
        return tiers[borrower];
    }

    function scoreOf(address borrower) external view returns (uint16) {
        return scores[borrower];
    }

    function profileOf(address borrower) external view returns (CreditProfile memory) {
        return storedProfiles[borrower];
    }
}

/// @notice Tests for the soulbound credit tier badge.
/// @dev The soulbinding tests carry the most weight. A transferable reputation token is not a
/// reputation token — if a badge can be sold, Platinum can be bought, and the tier stops meaning
/// anything. Every escape route out of the token is therefore closed explicitly.
contract CreditTierSBTTest is Test {
    StubRegistry internal registry;
    CreditTierSBT internal sbt;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        registry = new StubRegistry();
        sbt = new CreditTierSBT(address(registry));
        registry.set(alice, Tier.Platinum, 710);
        registry.set(bob, Tier.Bronze, 0);
    }

    // ─── Minting and syncing ──────────────────────────────────────────────────────────────

    function test_sync_mintsBadgeReflectingTier() public {
        uint256 tokenId = sbt.sync(alice);

        assertEq(sbt.ownerOf(tokenId), alice);
        assertEq(sbt.tokenOf(alice), tokenId);
        assertEq(uint8(sbt.tierOfToken(tokenId)), uint8(Tier.Platinum));
    }

    function test_sync_emitsLockedOnMint() public {
        vm.expectEmit(false, false, false, true, address(sbt));
        emit IERC5192.Locked(1);
        sbt.sync(alice);
    }

    /// @dev Anyone may refresh anyone's badge. That adds no trust: the tier comes from the
    /// registry, which only moves on verified proofs, so a caller can pay gas but not influence
    /// the outcome.
    function test_sync_isPermissionless() public {
        vm.prank(stranger);
        uint256 tokenId = sbt.sync(alice);
        assertEq(sbt.ownerOf(tokenId), alice, "badge belongs to the borrower, not the caller");
    }

    function test_sync_isIdempotent() public {
        uint256 first = sbt.sync(alice);
        uint256 second = sbt.sync(alice);
        assertEq(first, second, "no second badge");
        assertEq(sbt.balanceOf(alice), 1);
    }

    function test_sync_upgradesTierInPlace() public {
        registry.set(alice, Tier.Silver, 300);
        uint256 tokenId = sbt.sync(alice);
        assertEq(uint8(sbt.tierOfToken(tokenId)), uint8(Tier.Silver));

        registry.set(alice, Tier.Platinum, 710);
        sbt.sync(alice);

        assertEq(uint8(sbt.tierOfToken(tokenId)), uint8(Tier.Platinum), "same token, new tier");
        assertEq(sbt.balanceOf(alice), 1);
    }

    /// @dev Tiers can fall as well as rise — a badge must not become a permanent high-water mark.
    function test_sync_downgradesTier() public {
        registry.set(alice, Tier.Platinum, 710);
        uint256 tokenId = sbt.sync(alice);

        registry.set(alice, Tier.Bronze, 0);
        sbt.sync(alice);

        assertEq(uint8(sbt.tierOfToken(tokenId)), uint8(Tier.Bronze));
    }

    function test_sync_separateBadgesPerBorrower() public {
        uint256 aliceToken = sbt.sync(alice);
        uint256 bobToken = sbt.sync(bob);
        assertTrue(aliceToken != bobToken);
        assertEq(uint8(sbt.tierOfToken(bobToken)), uint8(Tier.Bronze));
    }

    function test_sync_rejectsZeroAddress() public {
        vm.expectRevert(CreditTierSBT.ZeroAddress.selector);
        sbt.sync(address(0));
    }

    // ─── Soulbinding ──────────────────────────────────────────────────────────────────────

    function test_locked_alwaysTrue() public {
        uint256 tokenId = sbt.sync(alice);
        assertTrue(sbt.locked(tokenId));
    }

    function test_soulbound_transferFromReverts() public {
        uint256 tokenId = sbt.sync(alice);

        vm.prank(alice);
        vm.expectRevert(CreditTierSBT.Soulbound.selector);
        sbt.transferFrom(alice, bob, tokenId);
    }

    function test_soulbound_safeTransferFromReverts() public {
        uint256 tokenId = sbt.sync(alice);

        vm.prank(alice);
        vm.expectRevert(CreditTierSBT.Soulbound.selector);
        sbt.safeTransferFrom(alice, bob, tokenId);
    }

    /// @dev Approvals are blocked too — leaving them enabled would imply in wallet UIs that the
    /// token can move.
    function test_soulbound_approveReverts() public {
        uint256 tokenId = sbt.sync(alice);

        vm.prank(alice);
        vm.expectRevert(CreditTierSBT.Soulbound.selector);
        sbt.approve(bob, tokenId);
    }

    function test_soulbound_setApprovalForAllReverts() public {
        sbt.sync(alice);

        vm.prank(alice);
        vm.expectRevert(CreditTierSBT.Soulbound.selector);
        sbt.setApprovalForAll(bob, true);
    }

    /// @dev A borrower cannot discard a record they dislike. Two independent things stop them:
    /// the contract exposes no public burn, and transferring to the zero address is rejected by
    /// ERC-721 itself (with `ERC721InvalidReceiver`, which fires before our soulbound check —
    /// hence the different error here). Either alone would suffice; both is better.
    function test_soulbound_ownerCannotBurnBadge() public {
        uint256 tokenId = sbt.sync(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ERC721InvalidReceiver(address)", address(0)));
        sbt.transferFrom(alice, address(0), tokenId);

        assertEq(sbt.ownerOf(tokenId), alice, "badge survives the attempt");
        assertEq(sbt.balanceOf(alice), 1);
    }

    // ─── Metadata ─────────────────────────────────────────────────────────────────────────

    function test_tokenURI_isFullyOnChain() public {
        uint256 tokenId = sbt.sync(alice);
        string memory uri = sbt.tokenURI(tokenId);

        assertTrue(
            _startsWith(uri, "data:application/json;base64,"),
            "metadata must be inline, with no gateway or pinning service to rot"
        );
    }

    /// @dev Decodes the payload and checks the tier actually appears, rather than trusting that a
    /// base64 blob of the right shape contains the right content.
    function test_tokenURI_embedsTierAndScore() public {
        uint256 tokenId = sbt.sync(alice);
        string memory decoded = _decodeJson(sbt.tokenURI(tokenId));

        assertTrue(_contains(decoded, "Platinum"), "tier name present");
        assertTrue(_contains(decoded, "710"), "score present");
        assertTrue(_contains(decoded, "data:image/svg+xml;base64,"), "inline SVG present");
    }

    /// @dev The badge renders live registry state, so a tier change shows up even before someone
    /// pays to re-sync the cached value.
    function test_tokenURI_reflectsRegistryWithoutResync() public {
        uint256 tokenId = sbt.sync(alice);
        assertTrue(_contains(_decodeJson(sbt.tokenURI(tokenId)), "Platinum"));

        registry.set(alice, Tier.Bronze, 40);
        assertTrue(
            _contains(_decodeJson(sbt.tokenURI(tokenId)), "Bronze"),
            "reads through to the registry rather than the cached tier"
        );
    }

    function test_tokenURI_revertsForUnknownToken() public {
        vm.expectRevert();
        sbt.tokenURI(999);
    }

    function test_metadata_nameAndSymbol() public view {
        assertEq(sbt.name(), "CrossCredit Credit Tier");
        assertEq(sbt.symbol(), "CCTIER");
    }

    function test_constructor_rejectsZeroRegistry() public {
        vm.expectRevert(CreditTierSBT.ZeroAddress.selector);
        new CreditTierSBT(address(0));
    }

    // ─── String helpers ───────────────────────────────────────────────────────────────────

    function _startsWith(string memory haystack, string memory needle) private pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (h.length < n.length) return false;
        for (uint256 i = 0; i < n.length; ++i) {
            if (h[i] != n[i]) return false;
        }
        return true;
    }

    function _contains(string memory haystack, string memory needle) private pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || h.length < n.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; ++i) {
            bool matched = true;
            for (uint256 j = 0; j < n.length; ++j) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }
        return false;
    }

    /// @dev Strips the `data:application/json;base64,` prefix and decodes the rest.
    function _decodeJson(string memory uri) private pure returns (string memory) {
        bytes memory raw = bytes(uri);
        uint256 prefix = bytes("data:application/json;base64,").length;
        bytes memory payload = new bytes(raw.length - prefix);
        for (uint256 i = 0; i < payload.length; ++i) {
            payload[i] = raw[i + prefix];
        }
        return string(Base64Decoder.decode(string(payload)));
    }
}

/// @dev Minimal base64 decoder so the metadata tests assert on real content rather than on the
/// shape of an opaque blob. Test-only.
library Base64Decoder {
    function decode(string memory data) internal pure returns (bytes memory) {
        bytes memory input = bytes(data);
        if (input.length == 0) return new bytes(0);

        uint256 padding;
        if (input[input.length - 1] == "=") padding++;
        if (input.length > 1 && input[input.length - 2] == "=") padding++;

        bytes memory output = new bytes((input.length / 4) * 3 - padding);
        uint256 outIndex;

        for (uint256 i = 0; i < input.length; i += 4) {
            uint256 chunk = (_value(input[i]) << 18) | (_value(input[i + 1]) << 12)
                | (_value(input[i + 2]) << 6) | _value(input[i + 3]);

            if (outIndex < output.length) output[outIndex++] = bytes1(uint8(chunk >> 16));
            if (outIndex < output.length) output[outIndex++] = bytes1(uint8(chunk >> 8));
            if (outIndex < output.length) output[outIndex++] = bytes1(uint8(chunk));
        }
        return output;
    }

    function _value(bytes1 char) private pure returns (uint256) {
        uint8 c = uint8(char);
        if (c >= 65 && c <= 90) return c - 65; // A-Z
        if (c >= 97 && c <= 122) return c - 71; // a-z
        if (c >= 48 && c <= 57) return c + 4; // 0-9
        if (c == 43) return 62; // +
        if (c == 47) return 63; // /
        return 0; // padding
    }
}
