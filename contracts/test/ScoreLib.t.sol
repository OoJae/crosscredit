// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {CreditProfile, ScoreLib, Tier} from "../src/creditcoin/ScoreLib.sol";

/// @notice Tests for the credit scoring model.
///
/// @dev The most important tests here are not the arithmetic ones — they are the
/// `test_selfDealt_*` cases, which pin the property the whole model exists to enforce:
///
/// **History we cannot verify a lender for must never reach the tier that lends more than the
/// borrower posts.** Our own `LoanBook` on Sepolia has no lender; anyone can open a loan with a
/// self-declared principal and repay it to nobody for the price of gas. So its signals are capped
/// such that a *perfect, infinitely long* self-dealt record tops out at Gold. Reaching Platinum
/// requires repayments to a real third-party protocol on Ethereum mainnet, which cost real money
/// to produce.
///
/// If someone loosens a cap and self-dealt history can reach Platinum again, these tests fail.
contract ScoreLibTest is Test {
    /// @dev A fixed "now" so age arithmetic is deterministic. Roughly Aug 2026.
    uint64 internal constant NOW = 1_786_000_000;
    uint64 internal constant MONTH = 30 days;

    function _empty() internal pure returns (CreditProfile memory p) {
        return p;
    }

    // ─── The property that matters: self-dealt history cannot buy undercollateralized credit ──

    /// @dev The exact attack that motivated this model. `openLoan(1 wei) → repay(1 wei)`, repeated
    /// forever, with every proof cryptographically valid. It must not reach Platinum.
    function test_selfDealt_perfectTestnetHistoryCannotReachPlatinum() public pure {
        CreditProfile memory p = _empty();
        p.onTime = type(uint32).max;
        p.loansClosed = type(uint32).max;
        p.loansOpened = type(uint32).max;
        p.totalRepaidWei = 1_000_000 ether;
        p.oldestActivity = NOW - 3650 days; // a decade of it, so the age term is also maxed
        p.identityExpiry = NOW + 3650 days; // and an ENS name on top

        uint16 score = ScoreLib.compute(p, NOW);

        assertLt(score, ScoreLib.THRESHOLD_PLATINUM, "self-dealt history must not clear Platinum");
        assertEq(uint8(ScoreLib.tierFor(p, score)), uint8(Tier.Gold), "Gold is the ceiling without a real lender");
    }

    /// @dev The cap is structural: on-time + closed + age cannot sum past the Platinum threshold.
    function test_selfDealt_capsSumBelowPlatinum() public pure {
        uint256 ceiling = ScoreLib.CAP_ON_TIME + ScoreLib.CAP_CLOSED_LOANS + ScoreLib.CAP_AGE
            + ScoreLib.POINTS_IDENTITY;
        assertLt(ceiling, ScoreLib.THRESHOLD_PLATINUM, "testnet-only signals must not reach Platinum");
    }

    /// @dev And real third-party history does clear it — otherwise the model would be unusable.
    function test_mainnet_realHistoryReachesPlatinum() public pure {
        CreditProfile memory p = _empty();
        p.mainnetRepayments = 5;
        p.demonstratedCapacityWei = 5 ether;
        p.oldestActivity = NOW - 12 * MONTH;

        // 600 repayments + 200 capacity (capped) + 120 age (capped) = 920
        uint16 score = ScoreLib.compute(p, NOW);
        assertEq(score, 920);
        assertEq(uint8(ScoreLib.tierFor(p, score)), uint8(Tier.Platinum));
    }

    /// @dev Platinum must be reachable from third-party repayment history *alone*, with no age and
    /// no identity credential — otherwise the tier that requires real evidence could never be
    /// earned by real evidence. An earlier calibration capped the sum at 680 and made it
    /// permanently unreachable.
    function test_mainnet_platinumReachableWithoutAgeOrIdentity() public pure {
        CreditProfile memory p = _empty();
        p.mainnetRepayments = 5;
        p.demonstratedCapacityWei = 2 ether;

        uint16 score = ScoreLib.compute(p, NOW);
        assertGe(score, ScoreLib.THRESHOLD_PLATINUM, "real history alone must be able to earn Platinum");
        assertEq(uint8(ScoreLib.tierFor(p, score)), uint8(Tier.Platinum));
    }

    // ─── Calibration against the real seeded profiles ─────────────────────────────────────
    // Source of truth: docs/evidence/seeded-history.json.

    /// @dev Borrower A: 5 on-time, 3 closed, no mainnet history, seeded the same day.
    ///   on-time  min(5 × 60, 360) = 300
    ///   closed   min(3 × 30,  90) =  90
    ///   age      0 (hours old)
    ///                             = 390 → Silver
    /// Under the previous model this profile scored 710 and reached Platinum on six wei of
    /// self-dealt history. The drop is the fix, not a regression.
    function test_calibration_borrowerASettlesAtSilver() public pure {
        CreditProfile memory p = _empty();
        p.onTime = 5;
        p.loansOpened = 3;
        p.loansClosed = 3;
        p.totalRepaidWei = 0.006 ether;
        p.totalCollateralWei = 0.003 ether;
        p.oldestActivity = NOW;

        uint16 score = ScoreLib.compute(p, NOW);
        assertEq(score, 390, "calibration drift");
        assertEq(uint8(ScoreLib.tierFor(p, score)), uint8(Tier.Silver));
    }

    /// @dev The same record, a year later, earns Gold purely from elapsed time.
    function test_calibration_ageAloneLiftsBorrowerAToGold() public pure {
        CreditProfile memory p = _empty();
        p.onTime = 5;
        p.loansClosed = 3;
        p.oldestActivity = NOW - 12 * MONTH;

        uint16 score = ScoreLib.compute(p, NOW);
        assertEq(score, 510);
        assertEq(uint8(ScoreLib.tierFor(p, score)), uint8(Tier.Gold));
    }

    /// @dev Borrower B: one late repayment wipes out everything it earned.
    function test_calibration_borrowerBStaysBronze() public pure {
        CreditProfile memory p = _empty();
        p.late = 1;
        p.loansOpened = 1;
        p.loansClosed = 1;
        p.totalRepaidWei = 0.002 ether;
        p.oldestActivity = NOW;

        uint16 score = ScoreLib.compute(p, NOW);
        assertEq(score, 0);
        assertEq(uint8(ScoreLib.tierFor(p, score)), uint8(Tier.Bronze));
    }

    // ─── Time ─────────────────────────────────────────────────────────────────────────────

    /// @dev Wall-clock is the one input a scripted attacker cannot compress, so it must actually
    /// move the score. Without this term, six repayments in six blocks scores like six over six
    /// months.
    function test_age_historyLengthIsScored() public pure {
        CreditProfile memory fresh = _empty();
        fresh.onTime = 3;
        fresh.oldestActivity = NOW;

        CreditProfile memory aged = _empty();
        aged.onTime = 3;
        aged.oldestActivity = NOW - 6 * MONTH;

        assertGt(ScoreLib.compute(aged, NOW), ScoreLib.compute(fresh, NOW), "age must count");
    }

    function test_age_isCapped() public pure {
        CreditProfile memory p = _empty();
        p.oldestActivity = NOW - 12 * MONTH;
        uint16 atCap = ScoreLib.compute(p, NOW);

        p.oldestActivity = NOW - 200 * MONTH;
        assertEq(ScoreLib.compute(p, NOW), atCap, "age contribution caps");
    }

    function test_age_zeroWhenNoActivityRecorded() public pure {
        CreditProfile memory p = _empty();
        p.onTime = 1;
        assertEq(ScoreLib.compute(p, NOW), 60, "no oldestActivity means no age points");
    }

    /// @dev A clock skew that puts activity in the future must not underflow or award points.
    function test_age_futureActivityScoresZero() public pure {
        CreditProfile memory p = _empty();
        p.oldestActivity = NOW + 10 * MONTH;
        assertEq(ScoreLib.compute(p, NOW), 0);
    }

    // ─── Mainnet signals ──────────────────────────────────────────────────────────────────

    /// @dev A real repayment is worth twice a self-reported one, because a third party's capital
    /// was actually at risk.
    function test_mainnet_repaymentOutweighsSelfReported() public pure {
        CreditProfile memory selfReported = _empty();
        selfReported.onTime = 1;

        CreditProfile memory real = _empty();
        real.mainnetRepayments = 1;

        assertGt(ScoreLib.compute(real, NOW), ScoreLib.compute(selfReported, NOW));
    }

    /// @dev Capacity is the largest single repayment, so repeated small repayments cannot
    /// impersonate the ability to handle a large one.
    function test_mainnet_capacityIsCapped() public pure {
        CreditProfile memory p = _empty();
        p.demonstratedCapacityWei = 2 ether;
        uint16 atCap = ScoreLib.compute(p, NOW);

        p.demonstratedCapacityWei = 10_000 ether;
        assertEq(ScoreLib.compute(p, NOW), atCap, "a whale cannot buy a tier");
    }

    /// @dev Being liquidated is a worse signal than paying our toy contract late, and is
    /// penalised accordingly.
    function test_mainnet_liquidationHurtsMoreThanLateness() public pure {
        assertGt(ScoreLib.PENALTY_PER_LIQUIDATION, ScoreLib.PENALTY_PER_LATE);
    }

    /// @dev One liquidation bars Platinum outright, however strong the rest of the record.
    function test_mainnet_oneLiquidationBarsPlatinum() public pure {
        CreditProfile memory p = _empty();
        p.mainnetRepayments = 20;
        p.demonstratedCapacityWei = 100 ether;
        p.oldestActivity = NOW - 48 * MONTH;
        p.liquidations = 1;

        uint16 score = ScoreLib.compute(p, NOW);
        assertLt(uint8(ScoreLib.tierFor(p, score)), uint8(Tier.Platinum));
    }

    // ─── Identity ─────────────────────────────────────────────────────────────────────────

    /// @dev An unexpired ENS name or humanity claim helps a little. It is a rate limiter on cheap
    /// identity creation — about $25 for five years — not a licence to borrow.
    function test_identity_unexpiredClaimAddsPoints() public pure {
        CreditProfile memory without = _empty();
        without.onTime = 2;

        CreditProfile memory with_ = _empty();
        with_.onTime = 2;
        with_.identityExpiry = NOW + 365 days;

        assertEq(
            ScoreLib.compute(with_, NOW) - ScoreLib.compute(without, NOW),
            ScoreLib.POINTS_IDENTITY
        );
    }

    /// @dev The precompile proves past events, never current state — so a claim that has since
    /// lapsed must stop counting the moment it expires.
    function test_identity_expiredClaimIsWorthless() public pure {
        CreditProfile memory p = _empty();
        p.onTime = 2;
        p.identityExpiry = NOW - 1;

        assertEq(ScoreLib.compute(p, NOW), 120, "an expired claim contributes nothing");
    }

    /// @dev Identity alone cannot buy a tier, however many credentials are proven.
    function test_identity_aloneCannotReachSilver() public pure {
        CreditProfile memory p = _empty();
        p.identityExpiry = NOW + 3650 days;
        assertLt(ScoreLib.compute(p, NOW), ScoreLib.THRESHOLD_SILVER);
    }

    // ─── Tiers, floors, invariants ────────────────────────────────────────────────────────

    function test_tier_boundaries() public pure {
        CreditProfile memory p = _empty();
        assertEq(uint8(ScoreLib.tierFor(p, 249)), uint8(Tier.Bronze));
        assertEq(uint8(ScoreLib.tierFor(p, 250)), uint8(Tier.Silver));
        assertEq(uint8(ScoreLib.tierFor(p, 499)), uint8(Tier.Silver));
        assertEq(uint8(ScoreLib.tierFor(p, 500)), uint8(Tier.Gold));
        assertEq(uint8(ScoreLib.tierFor(p, 699)), uint8(Tier.Gold));
        assertEq(uint8(ScoreLib.tierFor(p, 700)), uint8(Tier.Platinum));
    }

    function test_tier_platinumRequiresSpotlessRecord() public pure {
        CreditProfile memory clean = _empty();
        CreditProfile memory oneLate = _empty();
        oneLate.late = 1;
        CreditProfile memory oneLiquidation = _empty();
        oneLiquidation.liquidations = 1;

        assertEq(uint8(ScoreLib.tierFor(clean, 1000)), uint8(Tier.Platinum));
        assertEq(uint8(ScoreLib.tierFor(oneLate, 1000)), uint8(Tier.Gold));
        assertEq(uint8(ScoreLib.tierFor(oneLiquidation, 1000)), uint8(Tier.Gold));
    }

    function test_floor_emptyProfileScoresZero() public pure {
        assertEq(ScoreLib.compute(_empty(), NOW), 0);
    }

    /// @dev Asserts against the **sum of the individual caps**, not against `MAX_SCORE`.
    ///
    /// `assertLe(score, MAX_SCORE)` cannot fail: `compute` clamps to `MAX_SCORE` on its last line,
    /// so the assertion restates the clamp rather than testing anything. Bounding by the caps
    /// instead makes the property bite — if any single cap stopped being applied, this fails.
    function testFuzz_scoreRespectsEveryIndividualCap(
        uint32 onTime,
        uint32 mainnet,
        uint256 capacity,
        uint32 closed,
        uint64 age,
        bool identity
    ) public pure {
        CreditProfile memory p = _empty();
        p.onTime = onTime;
        p.mainnetRepayments = mainnet;
        p.demonstratedCapacityWei = capacity;
        p.loansClosed = closed;
        p.oldestActivity = uint64(bound(age, 0, NOW));
        p.identityExpiry = identity ? NOW + 1 : 0;

        uint256 ceiling = ScoreLib.CAP_ON_TIME + ScoreLib.CAP_CLOSED_LOANS + ScoreLib.CAP_MAINNET_REPAYMENTS
            + ScoreLib.CAP_CAPACITY + ScoreLib.CAP_AGE + ScoreLib.POINTS_IDENTITY;

        assertLe(ScoreLib.compute(p, NOW), ceiling);
        assertLe(ScoreLib.compute(p, NOW), ScoreLib.MAX_SCORE);
    }

    /// @dev Saturating subtraction that actually asserts the floor.
    ///
    /// The old version asserted `<= MAX_SCORE`, which would have passed just as happily if the
    /// function returned garbage below 1000 rather than flooring at zero. This asserts the real
    /// property: once penalties exceed the capped positive score, the result is exactly 0.
    function testFuzz_penaltiesFloorAtZeroAndNeverWrap(uint32 late, uint32 liquidations) public pure {
        CreditProfile memory p = _empty();
        p.onTime = 6;
        p.mainnetRepayments = 4;
        p.late = late;
        p.liquidations = liquidations;

        uint256 positive = ScoreLib.CAP_ON_TIME + _min(4 * ScoreLib.POINTS_PER_MAINNET_REPAYMENT, ScoreLib.CAP_MAINNET_REPAYMENTS);
        uint256 penalty = uint256(late) * ScoreLib.PENALTY_PER_LATE
            + uint256(liquidations) * ScoreLib.PENALTY_PER_LIQUIDATION;

        uint16 score = ScoreLib.compute(p, NOW);
        if (penalty >= positive) {
            assertEq(score, 0, "penalties exceeding the score floor it at zero, never wrap");
        } else {
            assertEq(score, uint16(positive - penalty), "and otherwise subtract exactly");
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev The clamp is applied to the positive terms **before** penalties are subtracted.
    ///
    /// With every cap maxed the positive terms sum to 1,430 against a 1,000 ceiling, so clamping
    /// afterwards let the first 430 points of default vanish — a borrower could take two
    /// liquidations and a late payment and score exactly the same as a spotless one.
    function test_clamp_penaltiesAreNotAbsorbedByUnscorableHeadroom() public pure {
        CreditProfile memory perfect = _empty();
        perfect.onTime = 100;
        perfect.loansClosed = 100;
        perfect.mainnetRepayments = 100;
        perfect.demonstratedCapacityWei = 1_000_000 ether;
        perfect.oldestActivity = NOW - 3650 days;
        perfect.identityExpiry = NOW + 365 days;

        assertEq(ScoreLib.compute(perfect, NOW), ScoreLib.MAX_SCORE, "everything maxed hits the ceiling");

        // Built field by field, not `= perfect`. Assigning one memory struct to another copies the
        // *reference*, so mutating the copy would silently mutate the original and this test would
        // be comparing a value against itself.
        CreditProfile memory defaulted = _empty();
        defaulted.onTime = 100;
        defaulted.loansClosed = 100;
        defaulted.mainnetRepayments = 100;
        defaulted.demonstratedCapacityWei = 1_000_000 ether;
        defaulted.oldestActivity = NOW - 3650 days;
        defaulted.identityExpiry = NOW + 365 days;
        defaulted.liquidations = 1;

        assertEq(
            ScoreLib.compute(defaulted, NOW),
            ScoreLib.MAX_SCORE - ScoreLib.PENALTY_PER_LIQUIDATION,
            "a liquidation must cost its full penalty even at the ceiling"
        );
    }

    function testFuzz_moreRealRepaymentsIsNeverWorse(uint16 n) public pure {
        n = uint16(bound(n, 0, 1000));
        CreditProfile memory a = _empty();
        a.mainnetRepayments = n;
        CreditProfile memory b = _empty();
        b.mainnetRepayments = n + 1;

        assertGe(ScoreLib.compute(b, NOW), ScoreLib.compute(a, NOW));
    }

    function testFuzz_moreLiquidationsIsNeverBetter(uint16 n) public pure {
        n = uint16(bound(n, 0, 100));
        CreditProfile memory a = _empty();
        a.mainnetRepayments = 10;
        a.liquidations = n;
        CreditProfile memory b = _empty();
        b.mainnetRepayments = 10;
        b.liquidations = n + 1;

        assertLe(ScoreLib.compute(b, NOW), ScoreLib.compute(a, NOW));
    }
}
