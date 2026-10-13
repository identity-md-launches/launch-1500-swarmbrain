// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmBrain} from "src/SwarmBrain.sol";

/// @dev Expected balances and allowances come from submitted operations, never from
/// reading the token's accounting. Rejected calls leave the model unchanged.
/// Four callers can spend; the token contract is also tracked as a passive recipient.
contract BrainModelHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    SwarmBrain public immutable token;
    address[5] public holders;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new SwarmBrain();
        holders[0] = address(this);
        holders[1] = makeAddr("model alice");
        holders[2] = makeAddr("model bob");
        holders[3] = makeAddr("model carol");
        holders[4] = address(token);
        expectedBalance[address(this)] = SUPPLY;
        for (uint256 i = 1; i < 4; ++i) {
            assertTrue(token.transfer(holders[i], SUPPLY / 4));
            _move(address(this), holders[i], SUPPLY / 4);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = holders[fromSeed % 4];
        address to = holders[toSeed % 5];
        uint256 amount = _amount(rawAmount, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode) external {
        address owner = holders[ownerSeed % 4];
        address spender = holders[spenderSeed % 4];
        uint256 amount;
        if (mode % 4 == 0) amount = rawAmount;
        else if (mode % 4 == 1) amount = 0;
        else if (mode % 4 == 2) amount = type(uint256).max;
        else amount = type(uint256).max - 1;
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = holders[fromSeed % 4];
        address spender = holders[spenderSeed % 4];
        address to = holders[toSeed % 5];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 limit = expectedBalance[from] < allowed ? expectedBalance[from] : allowed;
        uint256 amount = _amount(rawAmount, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (allowed != type(uint256).max) expectedAllowance[from][spender] = allowed - amount;
        _move(from, to, amount);
    }

    function rejectOverdraw(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = holders[fromSeed % 4];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _reject(
            from,
            abi.encodeCall(token.transfer, (holders[toSeed % 5], amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAllowance) external {
        address owner = holders[ownerSeed % 4];
        address spender = holders[spenderSeed % 4];
        uint256 allowed = bound(rawAllowance, 0, SUPPLY);
        _approve(owner, spender, allowed);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, holders[toSeed % 5], allowed + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
    }

    function rejectBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool infiniteApproval) external {
        address owner = holders[ownerSeed % 4];
        address spender = holders[spenderSeed % 4];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + 1;
        _approve(owner, spender, infiniteApproval ? type(uint256).max : amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, holders[toSeed % 5], amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address owner = holders[ownerSeed % 4];
        address spender = holders[spenderSeed % 4];
        uint256 amount = _amount(rawAmount, expectedBalance[owner]);
        bytes memory reason = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        _reject(owner, abi.encodeCall(token.transfer, (address(0), amount)), reason);
        _approve(owner, spender, amount);
        _reject(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), reason);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _reject(
            holders[ownerSeed % 4],
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    /// @dev Transfers have no fees: a round trip must restore both balances exactly.
    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        uint256 fromIndex = fromSeed % 4;
        address from = holders[fromIndex];
        address to = holders[(fromIndex + 1 + toSeed % 3) % 4];
        uint256 amount = _amount(rawAmount, expectedBalance[from]);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), fromBefore - amount);
        assertEq(token.balanceOf(to), toBefore + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), fromBefore);
        assertEq(token.balanceOf(to), toBefore);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) internal {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _reject(address caller, bytes memory data, bytes memory expectedReason) internal {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(reason, expectedReason, "unexpected revert reason");
    }

    /// @dev Explicitly weights zero, one base unit, and the full available amount.
    function _amount(uint256 rawAmount, uint256 limit) internal pure returns (uint256) {
        if (rawAmount % 4 == 0) return 0;
        if (rawAmount % 4 == 1) return limit == 0 ? 0 : 1;
        if (rawAmount % 4 == 2) return limit;
        return bound(rawAmount, 0, limit);
    }
}

/// @notice ERC-20 accounting and authorization must hold after every randomized call.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract SwarmBrainModelInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    BrainModelHandler internal handler;
    SwarmBrain internal token;

    function setUp() public {
        handler = new BrainModelHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = BrainModelHandler.transfer.selector;
        selectors[1] = BrainModelHandler.approve.selector;
        selectors[2] = BrainModelHandler.transferFrom.selector;
        selectors[3] = BrainModelHandler.rejectOverdraw.selector;
        selectors[4] = BrainModelHandler.rejectAllowance.selector;
        selectors[5] = BrainModelHandler.rejectBalance.selector;
        selectors[6] = BrainModelHandler.rejectZeroRecipient.selector;
        selectors[7] = BrainModelHandler.rejectZeroSpender.selector;
        selectors[8] = BrainModelHandler.roundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // Fixed supply and conservation are explicit requirements. Per-holder checks also
    // detect an incorrect redistribution that a total-balance invariant would miss.
    function invariant_BalancesMatchSubmittedTransfersAndSupplyIsConserved() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            address holder = handler.holders(i);
            uint256 balance = token.balanceOf(holder);
            assertEq(balance, handler.expectedBalance(holder), "holder balance differs from transfer history");
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    // Approvals are isolated by owner/spender, finite approvals are consumed, and
    // reverted transferFrom calls must roll allowance deductions back.
    function invariant_AllAllowancesMatchApprovalsAndSuccessfulSpends() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.holders(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.holders(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance differs from approval and spending history"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
        }
    }

    function invariant_MetadataIsStable() public view {
        assertEq(token.name(), "SwarmBrain");
        assertEq(token.symbol(), "BRAIN");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }
}
