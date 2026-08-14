// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title LoanBook
/// @author CrossCredit
/// @notice A minimal lending ledger on Ethereum Sepolia whose sole purpose is to produce
/// **attestable credit history**: borrowers open loans, repay them (on time or late), and post
/// collateral, and every one of those actions emits an event that CrossCredit later proves to
/// Creditcoin through the Attestcoin Protocol.
///
/// @dev **The events below are a cross-chain ABI, not an implementation detail.**
/// `CreditRegistry` on Creditcoin CC3 reconstructs a borrower's reputation by decoding these logs
/// out of a transaction receipt that the block-prover precompile has verified. It cannot call
/// back into this contract — Attestcoin verification is inbound-only — so:
///
///   1. Every field the registry needs must live in the event itself. There is no second lookup.
///   2. `borrower` is **indexed** in all three events. The registry reads it from a topic and
///      never from `msg.sender`, which on Creditcoin is the worker relaying the proof, not the
///      borrower. Repayment is deliberately permissionless, so `msg.sender` here would be wrong
///      too — a friend settling your loan must build *your* reputation, not theirs.
///   3. Moving a field between `topics` and `data`, or changing an event's parameter list, breaks
///      verification on the other chain. `contracts/test/LoanBook.t.sol` pins the exact wire
///      format; change it there and in the registry's decoder in the same commit.
///
/// This contract holds real value only incidentally — it is a history generator for a testnet
/// demo, not a lending product. `LendingPool` on Creditcoin is where credit is actually priced.
contract LoanBook {
    /// @param borrower Who owes the debt and earns the reputation.
    /// @param principal Amount borrowed, in wei.
    /// @param dueDate Unix timestamp after which repayment counts as late.
    /// @param repaid Cumulative wei repaid so far; may exceed `principal` on overpayment.
    /// @param closed True once `repaid >= principal`.
    struct Loan {
        address borrower;
        uint256 principal;
        uint64 dueDate;
        uint256 repaid;
        bool closed;
    }

    /// @notice Emitted when a borrower opens a loan.
    /// @dev topic0 `0x0d7f8e19afd65be70c0b9ff46dab1702a44ca0e8fcd33448375d7c2690e5866b`.
    event LoanOpened(uint256 indexed loanId, address indexed borrower, uint256 principal, uint64 dueDate);

    /// @notice Emitted on every repayment, whole or partial.
    /// @dev topic0 `0x57f8fd60d10653687e2d0846de33d6d6099eb9eb0fb197aff44c9a9d5a6af0b5`.
    /// `onTime` is computed here rather than left for the registry to infer, because the registry
    /// has no access to this chain's clock — only to what the proven receipt says.
    ///
    /// `payer` exists because repayment is permissionless and lateness is punitive. Credit accrues
    /// to `borrower`, which is what makes a friend settling your debt useful — but it also meant a
    /// stranger could settle 1 wei on your past-due loan and stamp an indelible `late` on your
    /// profile, costing 150 points and barring Platinum forever. Recording who actually paid lets
    /// the registry reward any repayment while penalising only the borrower's own lateness.
    event RepaymentMade(
        uint256 indexed loanId,
        address indexed borrower,
        address indexed payer,
        uint256 amount,
        bool onTime,
        uint64 timestamp
    );

    /// @notice Emitted when a borrower withdraws previously posted collateral.
    event CollateralWithdrawn(address indexed borrower, uint256 amount);

    /// @notice Emitted when a borrower posts collateral.
    /// @dev topic0 `0x7dba1be544024070cd5eebfa8bdd80a8b198cea8058c7d3cc1f8dd36e41ab2f7`.
    event CollateralAdded(address indexed borrower, uint256 amount);

    error ZeroPrincipal();
    error ZeroDuration();
    error ZeroAmount();
    error UnknownLoan(uint256 loanId);
    error LoanClosed(uint256 loanId);
    error InsufficientCollateral(uint256 requested, uint256 available);
    error CollateralTransferFailed();

    /// @notice Loans by id. Ids start at 1, so 0 reliably means "no loan".
    mapping(uint256 => Loan) public loans;

    /// @notice Total collateral posted per borrower, in wei.
    mapping(address => uint256) public collateralOf;

    /// @notice Number of loans ever opened; also the id of the most recent one.
    uint256 public loanCount;

    /// @notice Opens a loan and starts its repayment clock.
    /// @dev No funds move. This is a history generator: disbursement is out of scope, and adding
    /// it would force the contract to hold a float that the demo does not need.
    /// @param principal Amount borrowed, in wei. Must be non-zero.
    /// @param duration Seconds until repayment is late. Must be non-zero. Short values are
    /// intentionally allowed so a loan can be driven late during a live demo.
    /// @return loanId The new loan's id.
    function openLoan(uint256 principal, uint64 duration) external returns (uint256 loanId) {
        if (principal == 0) revert ZeroPrincipal();
        if (duration == 0) revert ZeroDuration();

        loanId = ++loanCount;
        uint64 dueDate = uint64(block.timestamp) + duration;

        loans[loanId] = Loan({
            borrower: msg.sender,
            principal: principal,
            dueDate: dueDate,
            repaid: 0,
            closed: false
        });

        emit LoanOpened(loanId, msg.sender, principal, dueDate);
    }

    /// @notice Repays a loan, wholly or partially.
    /// @dev Permissionless by design — anyone may settle anyone's debt — but credit always
    /// accrues to `loan.borrower`, never to `msg.sender`.
    /// @param loanId The loan to repay.
    function repay(uint256 loanId) external payable {
        Loan storage loan = loans[loanId];
        if (loan.borrower == address(0)) revert UnknownLoan(loanId);
        if (loan.closed) revert LoanClosed(loanId);
        if (msg.value == 0) revert ZeroAmount();

        loan.repaid += msg.value;
        bool onTime = block.timestamp <= loan.dueDate;

        if (loan.repaid >= loan.principal) {
            loan.closed = true;
        }

        emit RepaymentMade(loanId, loan.borrower, msg.sender, msg.value, onTime, uint64(block.timestamp));
    }

    /// @notice Posts collateral, strengthening the sender's credit profile.
    function addCollateral() external payable {
        if (msg.value == 0) revert ZeroAmount();

        collateralOf[msg.sender] += msg.value;

        emit CollateralAdded(msg.sender, msg.value);
    }

    /// @notice Withdraws previously posted collateral.
    /// @dev Exists because `addCollateral` accepted ETH with no way out, which made every wei ever
    /// posted permanently unrecoverable — a nonsense position for a contract whose own NatSpec
    /// calls collateral "skin in the game". Effects precede the interaction, so the re-entrant
    /// call sees a balance already decremented.
    /// @param amount Wei to withdraw.
    function withdrawCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        uint256 available = collateralOf[msg.sender];
        if (amount > available) revert InsufficientCollateral(amount, available);

        collateralOf[msg.sender] = available - amount;

        emit CollateralWithdrawn(msg.sender, amount);

        (bool ok,) = msg.sender.call{value: amount}('');
        if (!ok) revert CollateralTransferFailed();
    }
}
