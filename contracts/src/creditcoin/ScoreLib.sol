// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice A borrower's credit history, rebuilt entirely from Sepolia events that Creditcoin
/// verified for itself. Every field here traces back to a proven `LoanBook` log.
/// @param totalRepaidWei Cumulative wei repaid across all loans.
/// @param totalCollateralWei Cumulative wei of collateral posted.
/// @param onTime Repayments made on or before their due date.
/// @param late Repayments made after their due date. Any late repayment bars Platinum.
/// @param loansOpened Distinct loans opened.
/// @param loansClosed Loans whose cumulative repayments reached their principal.
/// @param firstSeen Timestamp of the first ingested event for this borrower.
/// @param score Cached {ScoreLib-compute} result, refreshed on every ingest.
struct CreditProfile {
    uint256 totalRepaidWei;
    uint256 totalCollateralWei;
    uint32 onTime;
    uint32 late;
    uint32 loansOpened;
    uint32 loansClosed;
    uint64 firstSeen;
    uint16 score;
}

/// @notice Credit tiers. Each maps to a collateral requirement and rate in `LendingPool`.
enum Tier {
    Bronze,
    Silver,
    Gold,
    Platinum
}

/// @title ScoreLib
/// @author CrossCredit
/// @notice Turns a verified {CreditProfile} into a 0–1000 credit score and a {Tier}.
///
/// @dev Deliberately simple, deterministic and auditable in under a minute — a judge (or a
/// borrower) should be able to read these constants and predict their own score exactly. There is
/// no oracle, no off-chain model and no owner-tunable weighting: identical history always yields
/// an identical score, which is the point of building it on verified cross-chain facts.
///
/// All functions are `internal`, so this library is inlined at compile time and needs no
/// link-time deployment (unlike `EvmV1Decoder`, whose functions are `public`).
///
/// **Constants are calibrated for testnet-scale amounts.** The original spec scored volume per
/// 0.01 ETH, which would round to zero against the 0.001–0.002 ETH loans a faucet-funded demo can
/// afford. Volume is therefore scored per 0.0001 ETH. See `docs/SCORING.md` for the full
/// rationale and the arithmetic against real seeded history.
library ScoreLib {
    /// @notice Maximum attainable score.
    uint256 internal constant MAX_SCORE = 1000;

    /// @notice Points per repayment made on time, and the cap on that component.
    /// @dev The dominant signal: repaying on time, repeatedly, is what creditworthiness means.
    uint256 internal constant POINTS_PER_ON_TIME = 100;
    uint256 internal constant CAP_ON_TIME = 600;

    /// @notice Points per loan fully repaid, and the cap on that component.
    /// @dev Rewards *finishing*, not just servicing — a borrower who closes loans is a better
    /// risk than one who makes payments indefinitely.
    uint256 internal constant POINTS_PER_CLOSED_LOAN = 40;
    uint256 internal constant CAP_CLOSED_LOANS = 120;

    /// @notice Wei of repayment worth one point, and the cap on that component.
    /// @dev 0.0001 ETH per point. Capped so a single whale repayment cannot buy a tier that
    /// consistent behaviour should earn.
    uint256 internal constant WEI_PER_VOLUME_POINT = 1e14;
    uint256 internal constant CAP_VOLUME = 200;

    /// @notice Wei of collateral worth one point, and the cap on that component.
    /// @dev Collateral is skin in the game, but it is capital rather than conduct — so it is
    /// weighted well below repayment history.
    uint256 internal constant WEI_PER_COLLATERAL_POINT = 1e14;
    uint256 internal constant CAP_COLLATERAL = 80;

    /// @notice Points deducted per late repayment.
    /// @dev Larger than the on-time reward: one default should cost more than one success earns,
    /// or the score could be farmed by borrowing recklessly and repaying often.
    uint256 internal constant PENALTY_PER_LATE = 150;

    /// @notice Score thresholds per tier.
    uint256 internal constant THRESHOLD_SILVER = 250;
    uint256 internal constant THRESHOLD_GOLD = 500;
    uint256 internal constant THRESHOLD_PLATINUM = 700;

    /// @notice Computes a borrower's score from their verified history.
    /// @dev Positive components are each capped before summing, then late penalties are
    /// subtracted with a floor at zero (never underflows). The result is capped at
    /// {MAX_SCORE}.
    /// @param profile The borrower's verified credit profile.
    /// @return score A value in [0, 1000].
    function compute(CreditProfile memory profile) internal pure returns (uint16 score) {
        uint256 positive = _min(uint256(profile.onTime) * POINTS_PER_ON_TIME, CAP_ON_TIME)
            + _min(uint256(profile.loansClosed) * POINTS_PER_CLOSED_LOAN, CAP_CLOSED_LOANS)
            + _min(profile.totalRepaidWei / WEI_PER_VOLUME_POINT, CAP_VOLUME)
            + _min(profile.totalCollateralWei / WEI_PER_COLLATERAL_POINT, CAP_COLLATERAL);

        uint256 penalty = uint256(profile.late) * PENALTY_PER_LATE;

        // Saturating subtraction: a borrower with more penalties than points floors at 0 rather
        // than reverting or wrapping.
        uint256 net = positive > penalty ? positive - penalty : 0;

        return uint16(_min(net, MAX_SCORE));
    }

    /// @notice Maps a score to a tier, applying Platinum's additional spotless-record rule.
    /// @dev Platinum unlocks undercollateralized borrowing, so it requires `late == 0` on top of
    /// the score threshold. A borrower can accumulate enough points to clear 700 despite a past
    /// default; that is good enough for Gold, not for lending them more than they post.
    /// @param profile The borrower's verified credit profile.
    /// @param score The score from {compute}.
    /// @return tier The borrower's tier.
    function tierFor(CreditProfile memory profile, uint16 score) internal pure returns (Tier tier) {
        if (score >= THRESHOLD_PLATINUM && profile.late == 0) return Tier.Platinum;
        if (score >= THRESHOLD_GOLD) return Tier.Gold;
        if (score >= THRESHOLD_SILVER) return Tier.Silver;
        return Tier.Bronze;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
