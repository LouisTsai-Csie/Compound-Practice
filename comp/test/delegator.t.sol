// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {UnderlyingToken} from "../src/ERC20.sol";
import {ComptrollerInterface} from "../src/ComptrollerInterface.sol";
import {Comptroller} from "../src/Comptroller.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {WhitePaperInterestRateModel} from "../src/WhitePaperInterestRateModel.sol";
import {CErc20Delegate} from "../src/CErc20Delegate.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {SimplePriceOracle} from "../src/SimplePriceOracle.sol";
import {Unitroller} from "../src/Unitroller.sol";
import {CToken} from "../src/CToken.sol";

contract CounterTest is Test {

    address public owner;
    address public user;

    // CErc20Delegator
    CErc20Delegator public delegator;
    uint256 public initialExchangeRateMantissa;
    address payable public admin;
    address public implementation;

    /// Underlying Token
    UnderlyingToken public underlyingToken;
    uint256 public initialSupply = 10 * (10 ** 5);
    string public name = "LOUIS";
    string public symbol = "LS"; 

    /// Comptroller
    Comptroller public comptroller;

    /// WhitePaperInterestRateModel
    WhitePaperInterestRateModel public whitePaperInterestRateModel;
    uint256 baseRatePerYear = 0;
    uint256 multiplierPerYear = 0;

    /// CErc20Delegate
    CErc20Delegate public delegate;

    // SimplePriceOracle
    SimplePriceOracle public simplePriceOracle;

    // Unitroller
    Unitroller public unitroller;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");


        vm.startPrank(owner);
        underlyingToken = new UnderlyingToken(initialSupply, name, symbol);
        comptroller = new Comptroller();
        unitroller = new Unitroller();
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        whitePaperInterestRateModel = new WhitePaperInterestRateModel(baseRatePerYear, multiplierPerYear);
        initialExchangeRateMantissa = 10 ** (underlyingToken.decimals() - 18);
        delegate = new CErc20Delegate();
        implementation = address(delegate);

        delegator = new CErc20Delegator(
            address(underlyingToken),
            ComptrollerInterface(address(comptroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            initialExchangeRateMantissa,
            name,
            symbol,
            underlyingToken.decimals(),
            payable(owner),
            implementation,
            bytes("")
        );

        simplePriceOracle = new SimplePriceOracle();
        comptroller._setPriceOracle(PriceOracle(address(simplePriceOracle)));

        comptroller._supportMarket(CToken(address(delegator)));

        vm.stopPrank();
    }

    function testMintRedeem() public {
        uint256 errorCode;
        vm.startPrank(user);

        deal(address(underlyingToken), user, 1000 * (10 ** 18));

        console2.log(underlyingToken.balanceOf(user));

        underlyingToken.approve(address(delegator), 2**256-1);

        errorCode = delegator.mint(100 * (10 ** 18));
        require(errorCode==0, "mint failed");

        errorCode = delegator.redeem(100 * (10 ** 18));
        require(errorCode==0, "redeem failed");

        assertGt(underlyingToken.balanceOf(user), 100 * (10 ** underlyingToken.decimals()));
        vm.stopPrank();
    }

    
}
