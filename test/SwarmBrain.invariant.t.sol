// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SwarmBrain} from "../src/SwarmBrain.sol";

/// @dev A closed set of holders exercises arbitrary sequences of ERC-20 operations.
contract BrainHandler is Test {
    SwarmBrain public immutable token;
    address[4] public actors;

    constructor() {
        token = new SwarmBrain();
        uint256 share = token.totalSupply() / 4;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = address(uint160(0x1000 + i));
            require(token.transfer(actors[i], share));
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 beforeAllowance = token.allowance(from, spender);
        uint256 limit = token.balanceOf(from);
        if (beforeAllowance < limit) limit = beforeAllowance;
        uint256 amount = bound(rawAmount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, actors[toSeed % 4], amount));
        assertEq(
            token.allowance(from, spender),
            beforeAllowance == type(uint256).max ? type(uint256).max : beforeAllowance - amount
        );
    }
}

contract SwarmBrainInvariantTest is StdInvariant, Test {
    BrainHandler internal handler;
    SwarmBrain internal token;
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        handler = new BrainHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = BrainHandler.transfer.selector;
        selectors[1] = BrainHandler.approve.selector;
        selectors[2] = BrainHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyIsFixedAndAllBalancesAreConserved() public view {
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            balances += token.balanceOf(handler.actors(i));
        }
        assertEq(balances, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
