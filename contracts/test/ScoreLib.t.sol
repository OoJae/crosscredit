// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {CreditProfile, ScoreLib, Tier} from "../src/creditcoin/ScoreLib.sol";

/// @notice Tests for the credit scoring model.
/// @dev Two things are being protected here. First, the arithmetic: caps, the late penalty, and
/// the floor at zero. Second — and more importantly for the demo — the **calibration against the
/// real seeded history on Sepolia**. The constants were chosen so that Borrower A's genuine
/// 9-event record reaches Platinum and Borrower B's single late repayment does not. If someone
/// retunes a constant, `test_calibration_*` fails and the demo narrative is caught before it is
/// recorded rather than after.
contract ScoreLibTest is Test {
    function _empty() internal pure returns (CreditProfile memory p) {
        return p;
    }

    // ─── Calibration against real seeded profiles ─────────────────────────────────────────
    // Source of truth: docs/evidence/seeded-history.json, captured from live Sepolia.

    /// @dev Borrower A `0x8ce707…`: 3 loans opened and closed, 5 on-time repayments, 0 late,
    /// 0.006 ETH repaid, 0.003 ETH collateral.
    ///   on-time   min(5 x 100, 600) = 500
    ///   closed    min(3 x  40, 120) = 120
    ///   volume    min(0.006e18 / 1e14, 200) =  60
    ///   collateral min(0.003e18 / 1e14, 80) =  30
    ///   penalty   0 x 150             =   0
    ///   total                         = 710  -> Platinum (>= 700 and late == 0)
    function test_calibration_borrowerAReachesPlatinum() public pure {
        CreditProfile memory p = CreditProfile({
            totalRepaidWei: 0.006 ether,
            totalCollateralWei: 0.003 ether,
            onTime: 5,
            late: 0,
            loansOpened: 3,
            loansClosed: 3,
            firstSeen: 1_786_656_000,
            score: 0
        });

        uint16 score = ScoreLib.compute(p);
        assertEq(score, 710, "calibration drift: Borrower A must score exactly 710");
        assertEq(uint8(ScoreLib.tierFor(p, score)), uint8(Tier.Platinum));
    }

    /// @dev Borrower B `0x04163f…`: 1 loan opened and closed, 0 on-time, 1 late, 0.002 ETH
    /// repaid, no collateral.
    ///   closed 40 + volume 20 = 60, penalty 150 -> floors at 0 -> Bronze.
    /// One default wipes out the credit earned by the repayment that caused it. That is the
    /// intended shape: late payment should hurt more than the payment helps.
    function test_calibration_borrowerBStaysBronze() public pure {
        CreditProfile memory p = CreditProfile({
            totalRepaidWei: 0.002 ether,
            totalCollateralWei: 0,
            onTime: 0,
            late: 1,
            loansOpened: 1,
            loansClosed: 1,
            firstSeen: 1_786_656_000,
            score: 0
        });

        uint16 score = ScoreLib.compute(p);
        assertEq(score, 0, "penalty must dominate a single late repayment");
        assertEq(uint8(ScoreLib.tierFor(p, score)), uint8(Tier.Bronze));
    }

    // ─── Tier boundaries ──────────────────────────────────────────────────────────────────

    function test_tier_boundaries() public pure {
        CreditProfile memory p = _empty();
        assertEq(uint8(ScoreLib.tierFor(p, 0)), uint8(Tier.Bronze));
        assertEq(uint8(ScoreLib.tierFor(p, 249)), uint8(Tier.Bronze));
        assertEq(uint8(ScoreLib.tierFor(p, 250)), uint8(Tier.Silver));
        assertEq(uint8(ScoreLib.tierFor(p, 499)), uint8(Tier.Silver));
        assertEq(uint8(ScoreLib.tierFor(p, 500)), uint8(Tier.Gold));
        assertEq(uint8(ScoreLib.tierFor(p, 699)), uint8(Tier.Gold));
        assertEq(uint8(ScoreLib.tierFor(p, 700)), uint8(Tier.Platinum));
    }

    /// @dev Platinum unlocks undercollateralized borrowing, so a spotless record is required on
    /// top of the score. A high scorer with one historical default caps at Gold.
    function test_tier_platinumRequiresZeroLate() public pure {
        CreditProfile memory spotless = _empty();
        CreditProfile memory blemished = _empty();
        blemished.late = 1;

        assertEq(uint8(ScoreLib.tierFor(spotless, 1000)), uint8(Tier.Platinum));
        assertEq(uint8(ScoreLib.tierFor(blemished, 1000)), uint8(Tier.Gold), "one default bars Platinum forever");
    }

    // ─── Component caps ───────────────────────────────────────────────────────────────────

    function test_caps_onTimeComponentIsCapped() public pure {
        CreditProfile memory p = _empty();
        p.onTime = 6;
        uint16 six = ScoreLib.compute(p);
        p.onTime = 600;
        assertEq(ScoreLib.compute(p), six, "on-time contribution caps at 600");
    }

    function test_caps_volumeComponentIsCapped() public pure {
        CreditProfile memory p = _empty();
        p.totalRepaidWei = 200 * 1e14;
        uint16 atCap = ScoreLib.compute(p);
        p.totalRepaidWei = 10_000 ether;
        assertEq(ScoreLib.compute(p), atCap, "a whale cannot buy a tier");
    }

    function test_caps_collateralComponentIsCapped() public pure {
        CreditProfile memory p = _empty();
        p.totalCollateralWei = 80 * 1e14;
        uint16 atCap = ScoreLib.compute(p);
        p.totalCollateralWei = 10_000 ether;
        assertEq(ScoreLib.compute(p), atCap);
    }

    function test_caps_closedLoansComponentIsCapped() public pure {
        CreditProfile memory p = _empty();
        p.loansClosed = 3;
        uint16 three = ScoreLib.compute(p);
        p.loansClosed = 300;
        assertEq(ScoreLib.compute(p), three);
    }

    // ─── Floors and invariants ────────────────────────────────────────────────────────────

    function test_floor_emptyProfileScoresZero() public pure {
        assertEq(ScoreLib.compute(_empty()), 0);
    }

    function testFuzz_scoreNeverExceedsMax(
        uint256 repaid,
        uint256 collateral,
        uint32 onTime,
        uint32 closed
    ) public pure {
        CreditProfile memory p = _empty();
        p.totalRepaidWei = repaid;
        p.totalCollateralWei = collateral;
        p.onTime = onTime;
        p.loansClosed = closed;

        assertLe(ScoreLib.compute(p), ScoreLib.MAX_SCORE);
    }

    /// @dev Saturating subtraction: no underflow, no wrap, however many defaults accumulate.
    function testFuzz_lateNeverUnderflows(uint32 onTime, uint32 late) public pure {
        CreditProfile memory p = _empty();
        p.onTime = onTime;
        p.late = late;

        uint16 score = ScoreLib.compute(p);
        assertLe(score, ScoreLib.MAX_SCORE);
        if (late > 4) assertEq(score, 0, "penalties beyond the on-time cap floor the score");
    }

    /// @dev More on-time repayments must never lower a score — otherwise good behaviour would be
    /// punished somewhere in the curve.
    function testFuzz_moreOnTimeIsNeverWorse(uint16 onTime) public pure {
        onTime = uint16(bound(onTime, 0, 1000));
        CreditProfile memory a = _empty();
        a.onTime = onTime;
        CreditProfile memory b = _empty();
        b.onTime = onTime + 1;

        assertGe(ScoreLib.compute(b), ScoreLib.compute(a));
    }

    /// @dev And an additional late repayment must never raise one.
    function testFuzz_moreLateIsNeverBetter(uint16 late) public pure {
        late = uint16(bound(late, 0, 100));
        CreditProfile memory a = _empty();
        a.onTime = 10;
        a.late = late;
        CreditProfile memory b = _empty();
        b.onTime = 10;
        b.late = late + 1;

        assertLe(ScoreLib.compute(b), ScoreLib.compute(a));
    }
}
