// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {LendingPool, ITierSource} from "../src/creditcoin/LendingPool.sol";
import {TUSD} from "../src/creditcoin/TUSD.sol";
import {Tier} from "../src/creditcoin/ScoreLib.sol";

/// @dev Drives tiers directly; the registry's proof-to-tier path is covered elsewhere.
contract StubTierSource is ITierSource {
    mapping(address => Tier) public tiers;
    mapping(address => uint256) public capacity;

    /// @dev Defaults to effectively unlimited demonstrated capacity so the pre-existing tier tests
    /// keep measuring what they were written to measure. The cap itself is exercised by the
    /// dedicated `test_capacityCap_*` cases below.
    function set(address borrower, Tier tier) external {
        tiers[borrower] = tier;
        capacity[borrower] = type(uint128).max;
    }

    function setCapacity(address borrower, uint256 amount) external {
        capacity[borrower] = amount;
    }

    function tierOf(address borrower) external view returns (Tier) {
        return tiers[borrower];
    }

    function demonstratedCapacityOf(address borrower) external view returns (uint256) {
        return capacity[borrower];
    }
}

/// @dev Attempts to re-enter `borrow` while receiving its collateral refund.
contract ReentrantBorrower {
    LendingPool private immutable POOL;
    bool private attacked;

    constructor(LendingPool pool) {
        POOL = pool;
    }

    function open(uint256 amount) external payable {
        POOL.borrow{value: msg.value}(amount);
    }

    function settle(TUSD asset) external {
        asset.approve(address(POOL), type(uint256).max);
        POOL.repay();
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            // Should revert under the guard; swallowed so the outer call's failure is the signal.
            try POOL.borrow{value: msg.value}(1e18) {} catch {}
        }
    }
}

/// @notice Tests for tier-priced lending.
/// @dev The claim this contract has to earn is that a Platinum borrower can take out more than
/// they post — undercollateralized credit, which no anonymous address should get. That is only
/// defensible because the tier came from cryptographically verified history, so the tests pin
/// both the numbers and the rule that terms are fixed at origination.
contract LendingPoolTest is Test {
    StubTierSource internal registry;
    TUSD internal asset;
    LendingPool internal pool;

    address internal platinum = makeAddr("platinum");
    address internal bronze = makeAddr("bronze");

    uint256 internal constant LIQUIDITY = 100_000e18;

    function setUp() public {
        registry = new StubTierSource();
        asset = new TUSD();
        pool = new LendingPool(address(registry), address(asset));

        asset.mint(address(this), LIQUIDITY);
        asset.approve(address(pool), LIQUIDITY);
        pool.fund(LIQUIDITY);

        registry.set(platinum, Tier.Platinum);
        registry.set(bronze, Tier.Bronze);

        vm.deal(platinum, 1_000 ether);
        vm.deal(bronze, 1_000 ether);
        vm.warp(1_786_000_000);
    }

    // ─── Terms by tier ────────────────────────────────────────────────────────────────────

    function test_terms_improveWithEveryTier() public {
        address[4] memory who =
            [makeAddr("b"), makeAddr("s"), makeAddr("g"), makeAddr("p")];
        Tier[4] memory tiers = [Tier.Bronze, Tier.Silver, Tier.Gold, Tier.Platinum];
        uint16[4] memory expectedRatio = [uint16(15_000), 13_000, 11_000, 8_500];
        uint16[4] memory expectedApr = [uint16(1_400), 1_100, 800, 600];

        for (uint256 i = 0; i < 4; ++i) {
            registry.set(who[i], tiers[i]);
            (Tier tier, LendingPool.Terms memory terms) = pool.quote(who[i]);
            assertEq(uint8(tier), uint8(tiers[i]));
            assertEq(terms.collateralRatioBps, expectedRatio[i]);
            assertEq(terms.aprBps, expectedApr[i]);
        }
    }

    /// @dev The headline number: 85% collateral for 100% borrowed.
    function test_terms_platinumIsUndercollateralized() public view {
        (, LendingPool.Terms memory terms) = pool.quote(platinum);
        assertLt(terms.collateralRatioBps, 10_000, "Platinum borrows more than it posts");
        assertEq(pool.collateralRequired(platinum, 1_000e18), 850e18);
    }

    function test_terms_bronzeIsOvercollateralized() public view {
        assertEq(pool.collateralRequired(bronze, 1_000e18), 1_500e18);
    }

    /// @dev The concrete benefit of a proven history: the same loan costs 650 tCTC less to
    /// collateralize at Platinum than at Bronze.
    function test_terms_platinumUnlocksRealCapitalEfficiency() public view {
        uint256 atBronze = pool.collateralRequired(bronze, 1_000e18);
        uint256 atPlatinum = pool.collateralRequired(platinum, 1_000e18);
        assertEq(atBronze - atPlatinum, 650e18);
    }

    // ─── Borrowing ────────────────────────────────────────────────────────────────────────

    function test_borrow_platinumSucceedsWithLessCollateralThanPrincipal() public {
        uint256 amount = 1_000e18;
        uint256 collateral = pool.collateralRequired(platinum, amount);

        vm.prank(platinum);
        pool.borrow{value: collateral}(amount);

        assertEq(asset.balanceOf(platinum), amount);
        assertLt(collateral, amount, "borrowed more value than posted");

        (uint256 principal, uint256 lockedCollateral,, Tier tierAtOrigination, bool active) = pool.loans(platinum);
        assertEq(principal, amount);
        assertEq(lockedCollateral, collateral);
        assertEq(uint8(tierAtOrigination), uint8(Tier.Platinum));
        assertTrue(active);
    }

    function test_borrow_rejectsInsufficientCollateral() public {
        uint256 amount = 1_000e18;
        uint256 required = pool.collateralRequired(platinum, amount);

        vm.prank(platinum);
        vm.expectRevert(
            abi.encodeWithSelector(LendingPool.InsufficientCollateral.selector, required - 1, required)
        );
        pool.borrow{value: required - 1}(amount);
    }

    function test_borrow_rejectsAboveTierLimit() public {
        vm.prank(bronze);
        vm.expectRevert(abi.encodeWithSelector(LendingPool.ExceedsTierLimit.selector, 101e18, uint256(100e18)));
        pool.borrow{value: 1_000 ether}(101e18);
    }

    function test_borrow_rejectsSecondConcurrentLoan() public {
        vm.startPrank(platinum);
        pool.borrow{value: 85e18}(100e18);

        vm.expectRevert(abi.encodeWithSelector(LendingPool.LoanAlreadyOpen.selector, platinum));
        pool.borrow{value: 85e18}(100e18);
        vm.stopPrank();
    }

    function test_borrow_rejectsZeroAmount() public {
        vm.prank(platinum);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.borrow{value: 1 ether}(0);
    }

    function test_borrow_rejectsWhenPaused() public {
        pool.pause();
        vm.prank(platinum);
        vm.expectRevert();
        pool.borrow{value: 85e18}(100e18);
    }

    function test_borrow_rejectsBeyondLiquidity() public {
        // Platinum's ceiling is 10,000 tUSD; drain the pool below that first.
        address whale = makeAddr("whale");
        registry.set(whale, Tier.Platinum);
        vm.deal(whale, 100_000 ether);

        vm.prank(whale);
        pool.borrow{value: 8_500e18}(10_000e18);

        // Repeat until liquidity is the binding constraint rather than the tier cap.
        for (uint256 i = 0; i < 9; ++i) {
            address other = makeAddr(string.concat("whale", vm.toString(i)));
            registry.set(other, Tier.Platinum);
            vm.deal(other, 100_000 ether);
            vm.prank(other);
            pool.borrow{value: 8_500e18}(10_000e18);
        }

        address last = makeAddr("last");
        registry.set(last, Tier.Platinum);
        vm.deal(last, 100_000 ether);
        vm.prank(last);
        vm.expectRevert();
        pool.borrow{value: 8_500e18}(10_000e18);
    }

    // ─── Interest and repayment ───────────────────────────────────────────────────────────

    function test_interest_accruesAtOriginationApr() public {
        vm.prank(platinum);
        pool.borrow{value: 850e18}(1_000e18);

        vm.warp(block.timestamp + 365 days);
        // 6% simple on 1,000 for one year.
        assertEq(pool.interestDue(platinum), 60e18);
        assertEq(pool.totalOwed(platinum), 1_060e18);
    }

    function test_interest_isZeroBeforeAnyTimePasses() public {
        vm.prank(platinum);
        pool.borrow{value: 850e18}(1_000e18);
        assertEq(pool.interestDue(platinum), 0);
    }

    function test_repay_closesLoanAndReturnsCollateral() public {
        uint256 amount = 1_000e18;
        uint256 collateral = pool.collateralRequired(platinum, amount);

        vm.prank(platinum);
        pool.borrow{value: collateral}(amount);

        vm.warp(block.timestamp + 182 days);
        uint256 owed = pool.totalOwed(platinum);

        // Fund the interest portion, which the borrower did not receive from the pool.
        asset.mint(platinum, owed - amount);

        uint256 balanceBefore = platinum.balance;
        vm.startPrank(platinum);
        asset.approve(address(pool), owed);
        pool.repay();
        vm.stopPrank();

        assertEq(platinum.balance - balanceBefore, collateral, "collateral returned in full");
        (,,,, bool active) = pool.loans(platinum);
        assertFalse(active);
    }

    function test_repay_rejectsWithoutActiveLoan() public {
        vm.prank(platinum);
        vm.expectRevert(abi.encodeWithSelector(LendingPool.NoActiveLoan.selector, platinum));
        pool.repay();
    }

    /// @dev A borrower who took a Platinum loan honestly must not be margin-called because their
    /// score later slipped. Terms are fixed at origination.
    function test_repay_tierDowngradeDoesNotStrandAnOpenLoan() public {
        vm.prank(platinum);
        pool.borrow{value: 850e18}(1_000e18);

        registry.set(platinum, Tier.Bronze);
        vm.warp(block.timestamp + 365 days);

        // Still 6% (Platinum), not 14% (Bronze).
        assertEq(pool.interestDue(platinum), 60e18);

        asset.mint(platinum, 60e18);
        vm.startPrank(platinum);
        asset.approve(address(pool), 1_060e18);
        pool.repay();
        vm.stopPrank();

        (,,,, bool active) = pool.loans(platinum);
        assertFalse(active, "downgrade cannot trap an existing loan");
    }

    /// @dev But a downgrade does apply to the *next* loan.
    function test_borrow_downgradeAppliesToSubsequentLoans() public {
        vm.prank(platinum);
        pool.borrow{value: 850e18}(1_000e18);

        asset.mint(platinum, 100e18);
        vm.startPrank(platinum);
        asset.approve(address(pool), type(uint256).max);
        pool.repay();
        vm.stopPrank();

        registry.set(platinum, Tier.Bronze);
        assertEq(pool.collateralRequired(platinum, 100e18), 150e18, "new loan priced at the new tier");
    }

    // ─── Safety ───────────────────────────────────────────────────────────────────────────

    /// @dev Collateral is returned by a raw call, so repay is the re-entrancy surface. State is
    /// cleared before the transfer (checks-effects-interactions) and the guard backstops it.
    function test_reentrancy_repayCannotBeReentered() public {
        ReentrantBorrower attacker = new ReentrantBorrower(pool);
        registry.set(address(attacker), Tier.Platinum);
        vm.deal(address(attacker), 1_000 ether);

        attacker.open{value: 85e18}(100e18);
        asset.mint(address(attacker), 10e18);

        attacker.settle(asset);

        // The re-entrant borrow must not have opened a second loan.
        (,,,, bool active) = pool.loans(address(attacker));
        assertFalse(active, "no loan re-opened during the collateral refund");
    }

    function test_admin_setTermsIsOwnerOnly() public {
        vm.prank(platinum);
        vm.expectRevert();
        pool.setTerms(Tier.Bronze, 100, 100, 1e18);
    }

    function test_admin_setTermsUpdatesQuotes() public {
        pool.setTerms(Tier.Bronze, 12_000, 900, 250e18);
        (, LendingPool.Terms memory terms) = pool.quote(bronze);
        assertEq(terms.collateralRatioBps, 12_000);
        assertEq(terms.aprBps, 900);
        assertEq(terms.maxBorrow, 250e18);
    }

    function test_admin_liquidateIsOwnerOnly() public {
        vm.prank(platinum);
        pool.borrow{value: 850e18}(1_000e18);

        vm.prank(bronze);
        vm.expectRevert();
        pool.liquidate(platinum);
    }

    function test_constructor_rejectsZeroAddresses() public {
        vm.expectRevert(LendingPool.ZeroAddress.selector);
        new LendingPool(address(0), address(asset));

        vm.expectRevert(LendingPool.ZeroAddress.selector);
        new LendingPool(address(registry), address(0));
    }

    // ─── The capacity cap: sybil defence by arithmetic ────────────────────────────────────

    /// @dev A wallet with a Platinum *tier* but no real mainnet history gets no undercollateralized
    /// credit at all. This is the hole that self-dealt `LoanBook` history opened, closed at the
    /// point where it actually costs the protocol money.
    function test_capacityCap_platinumWithoutRealHistoryGetsNoDiscount() public {
        registry.setCapacity(platinum, 0);

        assertEq(
            pool.collateralRequired(platinum, 1_000e18),
            1_000e18,
            "no demonstrated capacity means fully collateralized"
        );
        assertEq(pool.undercollateralizedPortion(platinum, 1_000e18), 0);
    }

    /// @dev With real history, the discount applies — but only up to what was demonstrated.
    function test_capacityCap_discountAppliesOnlyUpToCapacity() public {
        registry.setCapacity(platinum, 400e18);

        // 400 at 85% = 340, plus 600 at 100% = 600 → 940.
        assertEq(pool.collateralRequired(platinum, 1_000e18), 940e18);
        assertEq(pool.undercollateralizedPortion(platinum, 1_000e18), 400e18);
    }

    function test_capacityCap_fullDiscountWithinCapacity() public {
        registry.setCapacity(platinum, 2_000e18);
        assertEq(pool.collateralRequired(platinum, 1_000e18), 850e18, "wholly within capacity");
    }

    /// @dev Overcollateralized tiers are unaffected — the cap only ever limits a discount.
    function test_capacityCap_doesNotAffectOvercollateralizedTiers() public {
        registry.setCapacity(bronze, 0);
        assertEq(pool.collateralRequired(bronze, 1_000e18), 1_500e18);
    }

    /// @dev Splitting a history across many wallets divides capacity rather than multiplying it,
    /// so a sybil fleet gets no more total undercollateralized credit than one honest wallet.
    function test_capacityCap_isInvariantUnderIdentitySplitting() public {
        registry.setCapacity(platinum, 900e18);
        uint256 honestDiscount = 900e18 - pool.collateralRequired(platinum, 900e18);

        uint256 sybilDiscount;
        for (uint256 i = 0; i < 9; ++i) {
            address sybil = makeAddr(string.concat("sybil", vm.toString(i)));
            registry.set(sybil, Tier.Platinum);
            registry.setCapacity(sybil, 100e18); // the same 900 split nine ways
            sybilDiscount += 100e18 - pool.collateralRequired(sybil, 100e18);
        }

        assertEq(sybilDiscount, honestDiscount, "capacity is conserved across identities");
    }

    /// @dev And borrowing enforces the capped requirement, not just the quote.
    function test_capacityCap_borrowRejectsCollateralBelowCappedRequirement() public {
        registry.setCapacity(platinum, 0);

        vm.prank(platinum);
        vm.expectRevert(
            abi.encodeWithSelector(LendingPool.InsufficientCollateral.selector, 850e18, 1_000e18)
        );
        pool.borrow{value: 850e18}(1_000e18);
    }

    function testFuzz_collateralRequiredScalesLinearly(uint128 amount) public view {
        // `set` grants effectively unlimited capacity, so the pure tier ratio applies.
        uint256 required = pool.collateralRequired(platinum, amount);
        assertEq(required, (uint256(amount) * 8_500) / 10_000);
    }

    receive() external payable {}
}
