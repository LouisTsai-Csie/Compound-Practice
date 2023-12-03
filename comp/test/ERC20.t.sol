// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {UnderlyingToken} from "../src/ERC20.sol";

contract CounterTest is Test {
    
    UnderlyingToken public token;
    address public user;

    function setUp() public {
        user = makeAddr("user");
    }

    function testERC20MintOperation() public {
        // variable
        string memory name = "LOUIS";
        string memory symbol = "LS";

        // construct token
        vm.startPrank(user);
        token = new UnderlyingToken(1000, name, symbol);
        vm.stopPrank();

        // Check name
        assertEq(name, token.name());
        // Check symbol
        assertEq(symbol, token.symbol());
        // Check Decimals
        assertEq(18, token.decimals());
    }
    
}
