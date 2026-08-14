// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Tier} from "./ScoreLib.sol";

/// @notice The subset of `CreditRegistry` the pool reads.
interface ITierSource {
    function tierOf(address borrower) external view returns (Tier);

    /// @notice Largest single repayment this address has proven against a real third-party
    /// protocol on Ethereum mainnet. Zero for an address with no such history.
    function demonstratedCapacityOf(address borrower) external view returns (uint256);
}

/// @title LendingPool
/// @author CrossCredit
/// @notice Lends tUSD against native tCTC collateral, priced by a borrower's **verified
/// cross-chain credit tier**.
///
/// @dev This is where the whole system pays off: a borrower who proved a clean repayment history
/// on Ethereum borrows on better terms on Creditcoin, and a Platinum borrower borrows
/// **undercollateralized** — 85% collateral for 100% of value, which no anonymous address can get.
/// That is only defensible because the tier traces back through `CreditRegistry` to transactions
/// the block-prover precompile verified; a self-reported reputation could not justify lending
/// someone more than they post.
///
/// Deliberately minimal. It is not an Aave clone and does not try to be — no interest-rate curves,
/// no oracle pricing, no liquidation auctions. The tier-priced terms are the product; everything
/// else is scaffolding to demonstrate them.
///
/// Prices are fixed 1 tCTC = 1 tUSD for the demo. A real deployment needs a price feed, which is
/// noted in the roadmap rather than faked here.
contract LendingPool is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @param collateralRatioBps Collateral required per unit borrowed, in basis points.
    /// Below 10,000 means undercollateralized.
    /// @param aprBps Simple annual interest, in basis points.
    /// @param maxBorrow Ceiling per loan at this tier.
    struct Terms {
        uint16 collateralRatioBps;
        uint16 aprBps;
        uint256 maxBorrow;
    }

    /// @param principal tUSD borrowed.
    /// @param collateral tCTC locked, in wei.
    /// @param openedAt Timestamp interest accrues from.
    /// @param tierAtOrigination Tier when the loan was taken, which fixes its terms for life.
    /// @param active False once repaid or liquidated.
    struct Loan {
        uint256 principal;
        uint256 collateral;
        uint64 openedAt;
        Tier tierAtOrigination;
        bool active;
    }

    uint256 private constant BPS = 10_000;
    uint256 private constant YEAR = 365 days;

    /// @notice Registry supplying verified credit tiers.
    ITierSource public immutable REGISTRY;

    /// @notice The borrowable asset.
    IERC20 public immutable ASSET;

    /// @notice Terms per tier, indexed by {Tier}.
    mapping(Tier => Terms) public termsFor;

    /// @notice One open loan per borrower, keeping the demo legible.
    mapping(address => Loan) public loans;

    event Borrowed(address indexed borrower, uint256 principal, uint256 collateral, Tier tier, uint16 collateralRatioBps);
    event Repaid(address indexed borrower, uint256 principal, uint256 interest, uint256 collateralReturned);
    event Liquidated(address indexed borrower, uint256 principal, uint256 collateralSeized);
    event TermsUpdated(Tier tier, uint16 collateralRatioBps, uint16 aprBps, uint256 maxBorrow);

    error ZeroAmount();
    error ZeroAddress();
    error LoanAlreadyOpen(address borrower);
    error NoActiveLoan(address borrower);
    error InsufficientCollateral(uint256 supplied, uint256 required);
    error ExceedsTierLimit(uint256 requested, uint256 maximum);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error CollateralTransferFailed();

    constructor(address registry, address asset) Ownable(msg.sender) {
        if (registry == address(0) || asset == address(0)) revert ZeroAddress();
        REGISTRY = ITierSource(registry);
        ASSET = IERC20(asset);

        // Better verified history buys strictly better terms at every tier.
        termsFor[Tier.Bronze] = Terms({collateralRatioBps: 15_000, aprBps: 1_400, maxBorrow: 100e18});
        termsFor[Tier.Silver] = Terms({collateralRatioBps: 13_000, aprBps: 1_100, maxBorrow: 500e18});
        termsFor[Tier.Gold] = Terms({collateralRatioBps: 11_000, aprBps: 800, maxBorrow: 2_000e18});
        // The payoff: 85% collateral for 100% borrowed.
        termsFor[Tier.Platinum] = Terms({collateralRatioBps: 8_500, aprBps: 600, maxBorrow: 10_000e18});
    }

    /// @notice The terms a borrower qualifies for right now, given their verified tier.
    /// @dev A pull from the registry, so the pool never needs writing to when a score changes.
    function quote(address borrower) public view returns (Tier tier, Terms memory terms) {
        tier = REGISTRY.tierOf(borrower);
        terms = termsFor[tier];
    }

    /// @notice Collateral required to borrow `amount`, given the borrower's tier **and** the
    /// capital real third parties have demonstrably risked on them.
    ///
    /// @dev **This is the sybil defence, and it is arithmetic rather than an identity check.**
    ///
    /// A tier alone decides the *rate* at which credit is extended. It does not decide *how much*
    /// undercollateralized credit is available — that is capped by `demonstratedCapacityOf`, the
    /// largest single repayment the borrower has proven against a real mainnet protocol. Borrowing
    /// beyond that cap is collateralized at 100%.
    ///
    /// The consequence is that credit capacity is anchored to capital that genuinely was at risk,
    /// which makes it **invariant under identity multiplication**: splitting a history across a
    /// thousand fresh wallets divides the capacity rather than multiplying it, and a wallet with
    /// no real history gets no undercollateralized credit however high its score. Extra pseudonyms
    /// cannot manufacture extra capacity — the formal statement is in arXiv:2605.03307.
    ///
    /// It also closes the hole that motivated all of this: a borrower who farmed a spotless record
    /// on a contract with no lender can reach a good rate, but cannot borrow a penny more than
    /// they post.
    function collateralRequired(address borrower, uint256 amount) public view returns (uint256) {
        (, Terms memory terms) = quote(borrower);
        if (terms.collateralRatioBps >= BPS) {
            return (amount * terms.collateralRatioBps) / BPS;
        }

        // Undercollateralized terms apply only up to demonstrated capacity.
        uint256 capacity = REGISTRY.demonstratedCapacityOf(borrower);
        uint256 discounted = amount > capacity ? capacity : amount;
        uint256 remainder = amount - discounted;

        return (discounted * terms.collateralRatioBps) / BPS + remainder;
    }

    /// @notice How much of `amount` would be covered by the borrower's undercollateralized
    /// allowance, so a UI can show why a quote is what it is.
    function undercollateralizedPortion(address borrower, uint256 amount) external view returns (uint256) {
        (, Terms memory terms) = quote(borrower);
        if (terms.collateralRatioBps >= BPS) return 0;
        uint256 capacity = REGISTRY.demonstratedCapacityOf(borrower);
        return amount > capacity ? capacity : amount;
    }

    /// @notice Borrows `amount` tUSD, locking the tCTC sent as collateral.
    /// @dev Terms are fixed at origination. A later downgrade must not retroactively worsen an
    /// existing loan — a borrower who took a Platinum loan honestly should not be margin-called
    /// because their score later slipped.
    /// @param amount tUSD to borrow.
    function borrow(uint256 amount) external payable nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (loans[msg.sender].active) revert LoanAlreadyOpen(msg.sender);

        (Tier tier, Terms memory terms) = quote(msg.sender);
        if (amount > terms.maxBorrow) revert ExceedsTierLimit(amount, terms.maxBorrow);

        uint256 required = collateralRequired(msg.sender, amount);
        if (msg.value < required) revert InsufficientCollateral(msg.value, required);

        uint256 available = ASSET.balanceOf(address(this));
        if (amount > available) revert InsufficientLiquidity(amount, available);

        // Checks-effects-interactions: state is final before any transfer.
        loans[msg.sender] = Loan({
            principal: amount,
            collateral: msg.value,
            openedAt: uint64(block.timestamp),
            tierAtOrigination: tier,
            active: true
        });

        emit Borrowed(msg.sender, amount, msg.value, tier, terms.collateralRatioBps);
        ASSET.safeTransfer(msg.sender, amount);
    }

    /// @notice Interest owed so far — simple, not compounding, at the origination tier's APR.
    function interestDue(address borrower) public view returns (uint256) {
        Loan memory loan = loans[borrower];
        if (!loan.active) return 0;
        uint256 elapsed = block.timestamp - loan.openedAt;
        return (loan.principal * termsFor[loan.tierAtOrigination].aprBps * elapsed) / (BPS * YEAR);
    }

    /// @notice Total owed to close the loan.
    function totalOwed(address borrower) public view returns (uint256) {
        Loan memory loan = loans[borrower];
        if (!loan.active) return 0;
        return loan.principal + interestDue(borrower);
    }

    /// @notice Repays in full and releases collateral.
    /// @dev Caller must have approved `totalOwed` first.
    function repay() external nonReentrant {
        Loan memory loan = loans[msg.sender];
        if (!loan.active) revert NoActiveLoan(msg.sender);

        uint256 interest = interestDue(msg.sender);
        uint256 owed = loan.principal + interest;

        delete loans[msg.sender];

        ASSET.safeTransferFrom(msg.sender, address(this), owed);

        emit Repaid(msg.sender, loan.principal, interest, loan.collateral);

        (bool sent,) = payable(msg.sender).call{value: loan.collateral}("");
        if (!sent) revert CollateralTransferFailed();
    }

    /// @notice Seizes collateral on a defaulted loan.
    /// @dev A stub. Real liquidation needs a price feed, a health-factor threshold and an
    /// incentive for third-party liquidators; presenting owner-only seizure as more than a
    /// placeholder would be dishonest. Roadmap item.
    function liquidate(address borrower) external onlyOwner nonReentrant {
        Loan memory loan = loans[borrower];
        if (!loan.active) revert NoActiveLoan(borrower);

        delete loans[borrower];
        emit Liquidated(borrower, loan.principal, loan.collateral);

        (bool sent,) = payable(owner()).call{value: loan.collateral}("");
        if (!sent) revert CollateralTransferFailed();
    }

    // ─── Administration ───────────────────────────────────────────────────────────────────

    /// @notice Supplies borrowable liquidity. Caller must have approved `amount`.
    function fund(uint256 amount) external {
        ASSET.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Retunes a tier's terms.
    function setTerms(Tier tier, uint16 collateralRatioBps, uint16 aprBps, uint256 maxBorrow) external onlyOwner {
        termsFor[tier] = Terms({collateralRatioBps: collateralRatioBps, aprBps: aprBps, maxBorrow: maxBorrow});
        emit TermsUpdated(tier, collateralRatioBps, aprBps, maxBorrow);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Accepts tCTC so the pool can cover collateral returns.
    receive() external payable {}
}
