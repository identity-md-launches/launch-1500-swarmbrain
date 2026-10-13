// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmBrain} from "src/SwarmBrain.sol";

/// @notice Complements the existing suite with authorization and arithmetic boundaries.
/// forge-config: default.fuzz.runs = 1000
contract SwarmBrainEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    SwarmBrain internal token;
    address internal alice = makeAddr("edge alice");
    address internal bob = makeAddr("edge bob");
    address internal spender = makeAddr("edge spender");
    address internal otherSpender = makeAddr("edge other spender");

    function setUp() public {
        token = new SwarmBrain();
    }

    function test_OneBaseUnitIsTransferredWithoutRounding() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsWithBalanceError() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferFromDoesNotConsumeInfiniteApprovalOnFailure() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneApprovalIsFinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_DelegatedSelfTransferConsumesApprovalWithoutChangingBalance() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), address(this), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_OwnerUsingTransferFromStillNeedsApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 0);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_SelfTransferStillRequiresEnoughBalance() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroRecipientIsRejectedEvenForZeroValue() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        token.approve(spender, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalCannotTargetZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_InfiniteApprovalCanBeRevokedAndReplaced() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_ApprovalBeforeFundingSurvivesFailedSpend() public {
        vm.prank(alice);
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(bob), 0);
        token.transfer(alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_TransferToTokenContractPreservesSupply() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalIsIsolatedByOwnerAndSpender(
        uint256 first,
        uint256 second,
        uint256 third,
        uint256 rawSpend
    ) public {
        token.transfer(alice, SUPPLY);
        vm.startPrank(alice);
        token.approve(spender, first);
        token.approve(otherSpender, second);
        vm.stopPrank();
        vm.prank(bob);
        token.approve(spender, third);
        uint256 limit = first < SUPPLY ? first : SUPPLY;
        uint256 spent = bound(rawSpend, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, spent));
        assertEq(token.allowance(alice, spender), first == type(uint256).max ? first : first - spent);
        assertEq(token.allowance(alice, otherSpender), second);
        assertEq(token.allowance(bob, spender), third);
        assertEq(token.allowance(bob, otherSpender), 0);
        assertEq(token.balanceOf(alice), SUPPLY - spent);
        assertEq(token.balanceOf(bob), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AboveAllowanceRevertsWithoutStateChange(uint256 rawAllowance, uint256 rawExcess) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY);
        uint256 attempted = bound(rawExcess, approved + 1, type(uint256).max);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, attempted)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, attempted);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_BalanceFailureRestoresFiniteAllowance(uint256 rawBalance, uint256 rawAmount) public {
        uint256 held = bound(rawBalance, 0, SUPPLY);
        uint256 attempted = bound(rawAmount, held + 1, type(uint256).max - 1);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, attempted);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, attempted));
        vm.prank(spender);
        token.transferFrom(alice, bob, attempted);
        assertEq(token.allowance(alice, spender), attempted);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
