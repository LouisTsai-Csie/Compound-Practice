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
    address public user1;
    address public user2;

    // CErc20Delegator
    CErc20Delegator public delegator0; // CToken 0
    CErc20Delegator public delegator1; // CToken 1
    uint256 public initialExchangeRateMantissa;
    address payable public admin;

    /// Underlying Token
    UnderlyingToken public underlyingToken0; // Underlying Token 0
    UnderlyingToken public underlyingToken1; // Underlying Token 1
    uint256 public initialSupply = 10 * (10 ** 18);
    string public name0 = "token0";
    string public symbol0 = "t0";
    string public name1 = "token1";
    string public symbol1 = "t1"; 

    /// Comptroller
    Comptroller public comptroller0; // Comptroller0
    Comptroller public comptroller1; // Comptroller1

    /// WhitePaperInterestRateModel
    WhitePaperInterestRateModel public whitePaperInterestRateModel;
    uint256 baseRatePerYear = 0;
    uint256 multiplierPerYear = 0;

    /// CErc20Delegate
    CErc20Delegate public delegate0; 
    CErc20Delegate public delegate1;

    // SimplePriceOracle
    SimplePriceOracle public simplePriceOracle0; 
    SimplePriceOracle public simplePriceOracle1;


    // Unitroller
    Unitroller public unitroller;

    function createCErc20Token0() internal {
        underlyingToken0 = new UnderlyingToken(initialSupply, name0, symbol0);
        comptroller0 = new Comptroller();
        whitePaperInterestRateModel = new WhitePaperInterestRateModel(baseRatePerYear, multiplierPerYear);
        initialExchangeRateMantissa = 10 * (underlyingToken0.decimals() - 8);
        delegate0 = new CErc20Delegate();

        delegator0 = new CErc20Delegator(
            address(underlyingToken0),
            ComptrollerInterface(address(comptroller0)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            initialExchangeRateMantissa,
            name0,
            symbol0,
            underlyingToken0.decimals(),
            payable(owner),
            address(delegate0),
            bytes("")
        );

        comptroller0._setPriceOracle(PriceOracle(address(simplePriceOracle0)));
        comptroller1._supportMarket(CToken(address(delegator1)));
    }

    function createCErc20Token1() internal {
        underlyingToken1 = new UnderlyingToken(initialSupply, name1, symbol1);
        comptroller1 = new Comptroller();
        whitePaperInterestRateModel = new WhitePaperInterestRateModel(baseRatePerYear, multiplierPerYear);
        initialExchangeRateMantissa = 10 * (underlyingToken1.decimals() - 8);
        delegate1 = new CErc20Delegate();


        delegator1 = new CErc20Delegator(
            address(underlyingToken1),
            ComptrollerInterface(address(comptroller1)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            initialExchangeRateMantissa,
            name1,
            symbol1,
            underlyingToken1.decimals(),
            payable(owner),
            address(delegate1),
            bytes("")
        );

        comptroller1._setPriceOracle(PriceOracle(address(simplePriceOracle1)));
        comptroller1._supportMarket(CToken(address(delegator1)));
    }

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");


        vm.startPrank(owner);

        simplePriceOracle0 = new SimplePriceOracle();
        simplePriceOracle1 = new SimplePriceOracle();

        createCErc20Token0();
        createCErc20Token1();

        unitroller = new Unitroller();

        

        vm.stopPrank();
    }

    function testBorrowAndRepay() public {
        vm.startPrank(owner);
        comptroller1._setCollateralFactor(CToken(address(delegate1)), 0.5 * (10 ** 18));
        vm.stopPrank();

        simplePriceOracle0.setUnderlyingPrice(CToken(address(delegator0)), 1 * (10 ** 18));
        simplePriceOracle1.setUnderlyingPrice(CToken(address(delegator1)), 100 * (10 ** 18));

        vm.startPrank(user1);
        underlyingToken1.mint(1 * (10 ** 18));

        vm.stopPrank();

    }

    
}
