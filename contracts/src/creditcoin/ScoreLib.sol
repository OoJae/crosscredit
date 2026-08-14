// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice A borrower's credit history, rebuilt entirely from transactions Creditcoin verified
/// for itself on a supported source chain.
///
/// @dev Split deliberately into **testnet-shaped** and **mainnet-shaped** signals, because they
/// are not equivalent evidence and must not be scored as though they were. Our own `LoanBook` on
/// Sepolia can produce `onTime`/`late` because it stamps a due date — but it has no lender, so
/// anyone can manufacture that history for the price of gas. Aave has no due dates at all; what
/// it has instead is a real counterparty whose capital was genuinely at risk. See
/// `docs/THREAT_MODEL.md`.
///
/// @param totalRepaidWei Cumulative repayment across every source.
/// @param totalCollateralWei Collateral posted on the source chain.
/// @param demonstratedCapacityWei Largest single repayment to a **third-party mainnet protocol**.
/// This, not the score, is what caps undercollateralized borrowing — see {LendingPool}.
/// @param onTime Repayments made by their due date. Sepolia `LoanBook` only.
/// @param late Repayments made after their due date. Sepolia `LoanBook` only.
/// @param mainnetRepayments Repayments proven against real mainnet lending protocols.
/// @param liquidations Times this address was liquidated on mainnet — the real default signal.
/// @param loansOpened Distinct loans opened.
/// @param loansClosed Loans whose cumulative repayments reached their principal.
/// @param firstSeen When CrossCredit first ingested anything for this borrower.
/// @param oldestActivity Earliest source-chain timestamp proven. The time axis: history that took
/// years to accumulate cannot be manufactured in an afternoon.
/// @param identityExpiry Expiry of a proven identity/sunk-cost claim (ENS name, PoH humanity), or
/// zero. Stored as an expiry rather than a boolean because the precompile proves *past events*,
/// never current state.
/// @param score Cached {ScoreLib-compute} result, refreshed on every ingest.
struct CreditProfile {
    uint256 totalRepaidWei;
    uint256 totalCollateralWei;
    uint256 demonstratedCapacityWei;
    uint32 onTime;
    uint32 late;
    uint32 mainnetRepayments;
    uint32 liquidations;
    uint32 loansOpened;
    uint32 loansClosed;
    uint64 firstSeen;
    uint64 oldestActivity;
    uint64 identityExpiry;
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
/// @dev Deterministic, auditable in under a minute, and computed **inside the EVM** from events
/// the consuming chain verified itself. That last part is the difference between this and every
/// comparable system: Spectral, Cred, Nomis and RociFi all compute off-chain and deliver a number
/// by oracle or API. Here, anyone can recompute the score from public data, and nobody — including
/// us — can silently retune it.
///
/// Three properties are load-bearing:
///
/// **Real counterparty capital outweighs self-reported history.** A mainnet repayment means a
/// third-party protocol had capital at risk. A Sepolia `LoanBook` repayment means someone paid
/// gas. They are weighted accordingly, and only the former raises
/// {CreditProfile-demonstratedCapacityWei}, which is what actually gates undercollateralized
/// credit.
///
/// **Time cannot be compressed.** Wall-clock age is the one input a scripted attacker cannot
/// fabricate, so history age is scored directly and recent activity alone cannot reach the top.
///
/// **No cliff.** An earlier version jumped tiers at exactly 700, which just tells a farmer where
/// to stop. Thresholds now sit on a continuous scale and the undercollateralized benefit scales
/// with demonstrated capacity rather than switching on.
library ScoreLib {
    uint256 internal constant MAX_SCORE = 1000;

    // ─── Sepolia LoanBook signals — capped low on purpose ─────────────────────────────────
    // This history is cheap to manufacture (no lender, self-declared principal), so it can
    // establish a starting reputation but cannot by itself reach the top of the scale.

    /// @notice Points per on-time repayment on our own source contract.
    uint256 internal constant POINTS_PER_ON_TIME = 60;
    /// @notice Cap on self-reported repayment history. Deliberately below the Gold threshold.
    uint256 internal constant CAP_ON_TIME = 360;
    /// @notice Points per loan fully repaid.
    uint256 internal constant POINTS_PER_CLOSED_LOAN = 30;
    uint256 internal constant CAP_CLOSED_LOANS = 90;
    /// @notice Points deducted per late repayment.
    uint256 internal constant PENALTY_PER_LATE = 150;

    // ─── Ethereum mainnet signals — where the real weight sits ────────────────────────────

    /// @notice Points per repayment proven against a real mainnet lending protocol.
    uint256 internal constant POINTS_PER_MAINNET_REPAYMENT = 120;
    uint256 internal constant CAP_MAINNET_REPAYMENTS = 480;

    /// @notice Wei of demonstrated third-party capacity worth one point, and its cap.
    /// @dev 0.01 ETH per point. Scaled for mainnet amounts, unlike the testnet-scale volume term.
    uint256 internal constant WEI_PER_CAPACITY_POINT = 1e16;
    uint256 internal constant CAP_CAPACITY = 200;

    /// @notice Deducted per mainnet liquidation — the closest thing to a real default.
    /// @dev Heavier than a late repayment: being liquidated means a third party lost patience and
    /// seized collateral, which is a materially worse signal than paying our toy contract late.
    uint256 internal constant PENALTY_PER_LIQUIDATION = 250;

    // ─── Time ─────────────────────────────────────────────────────────────────────────────

    /// @notice Points per 30 days of proven history, and the cap.
    /// @dev The only term an attacker cannot compress. Six repayments in six blocks and six over
    /// six months score identically without this.
    uint256 internal constant POINTS_PER_MONTH = 10;
    uint256 internal constant CAP_AGE = 120;
    uint256 internal constant SECONDS_PER_MONTH = 30 days;

    /// @notice Bonus for a live identity or sunk-cost claim (unexpired ENS name, PoH humanity).
    /// @dev Small by design. An ENS name costs about $25 for five years, so it is a rate limiter,
    /// never a licence to borrow.
    uint256 internal constant POINTS_IDENTITY = 60;

    // ─── Tiers ────────────────────────────────────────────────────────────────────────────

    uint256 internal constant THRESHOLD_SILVER = 250;
    uint256 internal constant THRESHOLD_GOLD = 500;
    uint256 internal constant THRESHOLD_PLATINUM = 700;

    /// @notice Computes a borrower's score from their verified history.
    /// @param profile The borrower's verified credit profile.
    /// @param nowTimestamp Current time, for the age term. Passed in rather than read so the
    /// function stays `pure` and trivially testable.
    /// @return score A value in [0, 1000].
    function compute(CreditProfile memory profile, uint64 nowTimestamp) internal pure returns (uint16 score) {
        uint256 positive = _min(uint256(profile.onTime) * POINTS_PER_ON_TIME, CAP_ON_TIME)
            + _min(uint256(profile.loansClosed) * POINTS_PER_CLOSED_LOAN, CAP_CLOSED_LOANS)
            + _min(uint256(profile.mainnetRepayments) * POINTS_PER_MAINNET_REPAYMENT, CAP_MAINNET_REPAYMENTS)
            + _min(profile.demonstratedCapacityWei / WEI_PER_CAPACITY_POINT, CAP_CAPACITY)
            + _ageScore(profile, nowTimestamp)
            + (profile.identityExpiry > nowTimestamp ? POINTS_IDENTITY : 0);

        uint256 penalty = uint256(profile.late) * PENALTY_PER_LATE
            + uint256(profile.liquidations) * PENALTY_PER_LIQUIDATION;

        // Saturating: more penalties than points floors at zero rather than wrapping.
        uint256 net = positive > penalty ? positive - penalty : 0;

        return uint16(_min(net, MAX_SCORE));
    }

    /// @notice Points earned purely by how long this borrower's proven history spans.
    function _ageScore(CreditProfile memory profile, uint64 nowTimestamp) private pure returns (uint256) {
        if (profile.oldestActivity == 0 || nowTimestamp <= profile.oldestActivity) return 0;
        uint256 elapsed = uint256(nowTimestamp - profile.oldestActivity);
        return _min((elapsed / SECONDS_PER_MONTH) * POINTS_PER_MONTH, CAP_AGE);
    }

    /// @notice Maps a score to a tier.
    /// @dev Platinum additionally requires a clean record — no late repayments **and** no
    /// liquidations. It is the tier that can borrow more than it posts, so a single default
    /// anywhere in the proven history bars it.
    function tierFor(CreditProfile memory profile, uint16 score) internal pure returns (Tier tier) {
        bool spotless = profile.late == 0 && profile.liquidations == 0;
        if (score >= THRESHOLD_PLATINUM && spotless) return Tier.Platinum;
        if (score >= THRESHOLD_GOLD) return Tier.Gold;
        if (score >= THRESHOLD_SILVER) return Tier.Silver;
        return Tier.Bronze;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
