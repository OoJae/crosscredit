// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LoanBook} from "../src/sepolia/LoanBook.sol";

/// @notice Tests for the Sepolia-side credit-history source.
/// @dev A whole section here asserts on exact event topics and data layout. That is deliberate:
/// these events are a **cross-chain ABI**. `CreditRegistry` on Creditcoin decodes them from a
/// proven transaction receipt with no ability to call back, so a field moving between `topics`
/// and `data` — or an index being added or removed — silently breaks verification on the other
/// chain. These assertions are the contract between the two halves of the system.
contract LoanBookTest is Test {
    LoanBook internal book;

    address internal borrower = makeAddr("borrower");
    address internal other = makeAddr("other");

    uint256 internal constant PRINCIPAL = 0.002 ether;
    uint64 internal constant DURATION = 1 days;

    // Redeclared so `vm.expectEmit` can match them.
    event LoanOpened(uint256 indexed loanId, address indexed borrower, uint256 principal, uint64 dueDate);
    event RepaymentMade(
        uint256 indexed loanId, address indexed borrower, uint256 amount, bool onTime, uint64 timestamp
    );
    event CollateralAdded(address indexed borrower, uint256 amount);

    function setUp() public {
        book = new LoanBook();
        vm.deal(borrower, 10 ether);
        vm.deal(other, 10 ether);
        // Start at a realistic timestamp: dueDate arithmetic is uint64 seconds, and a near-zero
        // block.timestamp would make "late" cases untestable without underflow.
        vm.warp(1_786_000_000);
    }

    function _open() internal returns (uint256 loanId) {
        vm.prank(borrower);
        return book.openLoan(PRINCIPAL, DURATION);
    }

    // ─── Opening ──────────────────────────────────────────────────────────────────────────

    function test_openLoan_storesLoanAndReturnsIncrementingIds() public {
        uint256 first = _open();
        uint256 second = _open();

        assertEq(first, 1, "loan ids start at 1 so 0 can mean 'absent'");
        assertEq(second, 2);
        assertEq(book.loanCount(), 2);

        (address who, uint256 principal, uint64 dueDate, uint256 repaid, bool closed) = book.loans(first);
        assertEq(who, borrower);
        assertEq(principal, PRINCIPAL);
        assertEq(dueDate, uint64(block.timestamp) + DURATION);
        assertEq(repaid, 0);
        assertFalse(closed);
    }

    function test_openLoan_emitsLoanOpened() public {
        uint64 expectedDue = uint64(block.timestamp) + DURATION;

        vm.expectEmit(true, true, false, true, address(book));
        emit LoanOpened(1, borrower, PRINCIPAL, expectedDue);

        vm.prank(borrower);
        book.openLoan(PRINCIPAL, DURATION);
    }

    function test_openLoan_revertsOnZeroPrincipal() public {
        vm.prank(borrower);
        vm.expectRevert(LoanBook.ZeroPrincipal.selector);
        book.openLoan(0, DURATION);
    }

    function test_openLoan_revertsOnZeroDuration() public {
        vm.prank(borrower);
        vm.expectRevert(LoanBook.ZeroDuration.selector);
        book.openLoan(PRINCIPAL, 0);
    }

    /// @dev Short durations must be allowed — the demo needs a loan that can actually go late
    /// within a recording session.
    function test_openLoan_allowsShortDurationsForDemo() public {
        vm.prank(borrower);
        uint256 loanId = book.openLoan(PRINCIPAL, 60);
        (,, uint64 dueDate,,) = book.loans(loanId);
        assertEq(dueDate, uint64(block.timestamp) + 60);
    }

    // ─── Repayment ────────────────────────────────────────────────────────────────────────

    function test_repay_partialAccumulatesAndLeavesLoanOpen() public {
        uint256 loanId = _open();

        vm.prank(borrower);
        book.repay{value: 0.001 ether}(loanId);

        (,,, uint256 repaid, bool closed) = book.loans(loanId);
        assertEq(repaid, 0.001 ether);
        assertFalse(closed, "partial repayment must not close the loan");
    }

    function test_repay_reachingPrincipalClosesLoan() public {
        uint256 loanId = _open();

        vm.startPrank(borrower);
        book.repay{value: 0.001 ether}(loanId);
        book.repay{value: 0.001 ether}(loanId);
        vm.stopPrank();

        (,,, uint256 repaid, bool closed) = book.loans(loanId);
        assertEq(repaid, PRINCIPAL);
        assertTrue(closed);
    }

    function test_repay_onTimeWhenBeforeDueDate() public {
        uint256 loanId = _open();
        uint64 dueDate = uint64(block.timestamp) + DURATION;

        vm.expectEmit(true, true, false, true, address(book));
        emit RepaymentMade(loanId, borrower, 0.001 ether, true, uint64(block.timestamp));

        vm.prank(borrower);
        book.repay{value: 0.001 ether}(loanId);

        assertLe(block.timestamp, dueDate);
    }

    /// @dev Exactly at the deadline still counts as on time (`<=`). Pinning the boundary stops a
    /// future refactor from silently penalising punctual borrowers.
    function test_repay_onTimeExactlyAtDueDate() public {
        uint256 loanId = _open();
        (,, uint64 dueDate,,) = book.loans(loanId);
        vm.warp(dueDate);

        vm.expectEmit(true, true, false, true, address(book));
        emit RepaymentMade(loanId, borrower, 0.001 ether, true, uint64(dueDate));

        vm.prank(borrower);
        book.repay{value: 0.001 ether}(loanId);
    }

    function test_repay_lateOneSecondAfterDueDate() public {
        uint256 loanId = _open();
        (,, uint64 dueDate,,) = book.loans(loanId);
        vm.warp(uint256(dueDate) + 1);

        vm.expectEmit(true, true, false, true, address(book));
        emit RepaymentMade(loanId, borrower, 0.001 ether, false, uint64(dueDate) + 1);

        vm.prank(borrower);
        book.repay{value: 0.001 ether}(loanId);
    }

    /// @dev Repaying is permissionless, but the event must always credit the loan's borrower —
    /// never `msg.sender`. Otherwise a third party's repayment would build the wrong reputation.
    function test_repay_creditsLoanBorrowerNotSender() public {
        uint256 loanId = _open();

        vm.expectEmit(true, true, false, true, address(book));
        emit RepaymentMade(loanId, borrower, 0.001 ether, true, uint64(block.timestamp));

        vm.prank(other);
        book.repay{value: 0.001 ether}(loanId);
    }

    function test_repay_revertsOnUnknownLoan() public {
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(LoanBook.UnknownLoan.selector, uint256(999)));
        book.repay{value: 0.001 ether}(999);
    }

    function test_repay_revertsOnZeroValue() public {
        uint256 loanId = _open();
        vm.prank(borrower);
        vm.expectRevert(LoanBook.ZeroAmount.selector);
        book.repay{value: 0}(loanId);
    }

    function test_repay_revertsOnceClosed() public {
        uint256 loanId = _open();
        vm.startPrank(borrower);
        book.repay{value: PRINCIPAL}(loanId);

        vm.expectRevert(abi.encodeWithSelector(LoanBook.LoanClosed.selector, loanId));
        book.repay{value: 0.001 ether}(loanId);
        vm.stopPrank();
    }

    /// @dev Overpaying must not brick the loan or silently keep the excess unaccounted for; it
    /// closes cleanly and records the full amount sent.
    function test_repay_overpaymentClosesLoanAndRecordsFullAmount() public {
        uint256 loanId = _open();

        vm.prank(borrower);
        book.repay{value: PRINCIPAL * 2}(loanId);

        (,,, uint256 repaid, bool closed) = book.loans(loanId);
        assertEq(repaid, PRINCIPAL * 2);
        assertTrue(closed);
    }

    // ─── Collateral ───────────────────────────────────────────────────────────────────────

    function test_addCollateral_emitsAndAccumulates() public {
        vm.expectEmit(true, false, false, true, address(book));
        emit CollateralAdded(borrower, 0.005 ether);

        vm.prank(borrower);
        book.addCollateral{value: 0.005 ether}();

        assertEq(book.collateralOf(borrower), 0.005 ether);

        vm.prank(borrower);
        book.addCollateral{value: 0.001 ether}();
        assertEq(book.collateralOf(borrower), 0.006 ether);
    }

    function test_addCollateral_revertsOnZeroValue() public {
        vm.prank(borrower);
        vm.expectRevert(LoanBook.ZeroAmount.selector);
        book.addCollateral{value: 0}();
    }

    // ─── Cross-chain wire format ──────────────────────────────────────────────────────────
    // CreditRegistry decodes these logs on Creditcoin. If any assertion below changes, the
    // registry's decoder must change in the same commit.

    function test_wireFormat_loanOpened() public {
        vm.recordLogs();
        uint64 expectedDue = uint64(block.timestamp) + DURATION;
        vm.prank(borrower);
        book.openLoan(PRINCIPAL, DURATION);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        Vm.Log memory log = logs[0];

        assertEq(log.topics.length, 3, "sig + loanId + borrower");
        assertEq(log.topics[0], keccak256("LoanOpened(uint256,address,uint256,uint64)"));
        assertEq(uint256(log.topics[1]), 1, "loanId is indexed");
        assertEq(address(uint160(uint256(log.topics[2]))), borrower, "borrower is indexed");

        (uint256 principal, uint64 dueDate) = abi.decode(log.data, (uint256, uint64));
        assertEq(principal, PRINCIPAL);
        assertEq(dueDate, expectedDue);
    }

    function test_wireFormat_repaymentMade() public {
        uint256 loanId = _open();

        vm.recordLogs();
        vm.prank(borrower);
        book.repay{value: 0.001 ether}(loanId);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        Vm.Log memory log = logs[0];

        assertEq(log.topics.length, 3);
        assertEq(log.topics[0], keccak256("RepaymentMade(uint256,address,uint256,bool,uint64)"));
        assertEq(uint256(log.topics[1]), loanId);
        assertEq(address(uint160(uint256(log.topics[2]))), borrower);

        // Three non-indexed words. The registry relies on this exact width.
        assertEq(log.data.length, 96);
        (uint256 amount, bool onTime, uint64 timestamp) = abi.decode(log.data, (uint256, bool, uint64));
        assertEq(amount, 0.001 ether);
        assertTrue(onTime);
        assertEq(timestamp, uint64(block.timestamp));
    }

    function test_wireFormat_collateralAdded() public {
        vm.recordLogs();
        vm.prank(borrower);
        book.addCollateral{value: 0.005 ether}();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        Vm.Log memory log = logs[0];

        assertEq(log.topics.length, 2, "sig + borrower");
        assertEq(log.topics[0], keccak256("CollateralAdded(address,uint256)"));
        assertEq(address(uint160(uint256(log.topics[1]))), borrower);

        assertEq(log.data.length, 32);
        assertEq(abi.decode(log.data, (uint256)), 0.005 ether);
    }

    /// @dev The registry hardcodes these topic hashes as constants, so drift here is a
    /// cross-chain break. Values are asserted literally, not recomputed from the same source.
    function test_wireFormat_eventSignatureHashesAreStable() public pure {
        assertEq(
            keccak256("LoanOpened(uint256,address,uint256,uint64)"),
            0x0d7f8e19afd65be70c0b9ff46dab1702a44ca0e8fcd33448375d7c2690e5866b
        );
        assertEq(
            keccak256("RepaymentMade(uint256,address,uint256,bool,uint64)"),
            0x7d64aa0e099ec7ce5a5e95941014b245cf86dd8cd1115dd1ee421d8ec4d04206
        );
        assertEq(
            keccak256("CollateralAdded(address,uint256)"),
            0x7dba1be544024070cd5eebfa8bdd80a8b198cea8058c7d3cc1f8dd36e41ab2f7
        );
    }

    // ─── Fuzz ─────────────────────────────────────────────────────────────────────────────

    function testFuzz_repay_accumulatesWithoutOverflow(uint96 first, uint96 second) public {
        first = uint96(bound(first, 1, 100 ether));
        second = uint96(bound(second, 1, 100 ether));

        vm.prank(borrower);
        uint256 loanId = book.openLoan(type(uint128).max, DURATION);

        vm.deal(borrower, uint256(first) + second);
        vm.startPrank(borrower);
        book.repay{value: first}(loanId);
        book.repay{value: second}(loanId);
        vm.stopPrank();

        (,,, uint256 repaid,) = book.loans(loanId);
        assertEq(repaid, uint256(first) + uint256(second));
    }

    function testFuzz_openLoan_dueDateNeverOverflows(uint64 duration) public {
        duration = uint64(bound(duration, 1, type(uint32).max));
        vm.prank(borrower);
        uint256 loanId = book.openLoan(PRINCIPAL, duration);
        (,, uint64 dueDate,,) = book.loans(loanId);
        assertEq(dueDate, uint64(block.timestamp) + duration);
        assertGt(dueDate, block.timestamp);
    }
}
