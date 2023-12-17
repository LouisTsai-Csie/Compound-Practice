// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {ComptrollerInterface} from "../src/ComptrollerInterface.sol";
import {Comptroller} from "../src/Comptroller.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {WhitePaperInterestRateModel} from "../src/WhitePaperInterestRateModel.sol";
import {CErc20Delegate} from "../src/CErc20Delegate.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {SimplePriceOracle} from "../src/SimplePriceOracle.sol";
import {Unitroller} from "../src/Unitroller.sol";
import {CToken} from "../src/CToken.sol";
import {Liquidate} from "./liquidate.sol";

interface IERC20 {
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    function name() external returns (string memory);
    function symbol() external returns (string memory);
    function decimals() external returns (uint8);
    function totalSupply() external returns (uint256);
    function balanceOf(address _owner) external returns (uint256 balance);
    function transfer(address _to, uint256 _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
    function approve(address _spender, uint256 _value) external returns (bool success);
    function allowance(address _owner, address _spender) external returns (uint256 remaining);
}

 contract AaveFlashloanLiquidationTest is Test {
    /// Env Variable
    uint256 internal constant blockNumber = 17_465_000;

    /// Token Address
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant UNI  = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    /// Comptroller Proxy & Implementation
    Comptroller internal comptroller;
    Unitroller internal unitroller;

    /// CErc20Delegator & CErc20Delegate
    CErc20Delegator internal cUSDC;
    CErc20Delegator internal cUNI;
    CErc20Delegate  internal delegate;

    /// Interest Rate Model
    WhitePaperInterestRateModel internal model;

    /// Price Oracle
    SimplePriceOracle internal oracle;

    /// Role
    address internal admin;
    address internal user;
    address internal provider;
    address internal liquidator;

    /// Liquidator
    Liquidate bot;
    
    /// Common Variable
    uint256 internal errorCode;
    uint256 internal amount;

    function setUp() public {
        /// ENV Configuration
        vm.createSelectFork(vm.envString("MAINNET_PRC_URL"), blockNumber);

        /// Role Creation
        admin = makeAddr("admin");
        user  = makeAddr("user");
        provider   = makeAddr("provider");
        liquidator = makeAddr("liquidator");

        vm.startPrank(admin);
        /// Comptroller Configuration
        comptroller = new Comptroller();
        unitroller  = new Unitroller();
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        /// Creation
        delegate = new CErc20Delegate();
        model    = new WhitePaperInterestRateModel(0, 0);
        oracle   = new SimplePriceOracle();
        Comptroller(address(unitroller))._setPriceOracle(oracle);
        
        /**
         * @param underlying_ The address of the underlying asset
         * @param comptroller_ The address of the Comptroller
         * @param interestRateModel_ The address of the interest rate model
         * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
         * @param name_ ERC-20 name of this token
         * @param symbol_ ERC-20 symbol of this token
         * @param decimals_ ERC-20 decimal precision of this token
         * @param admin_ Address of the administrator of this token
         * @param implementation_ The address of the implementation the contract delegates to
         * @param becomeImplementationData The encoded args for becomeImplementation
         */

        /// cUNI Token Creation
        cUNI = new CErc20Delegator(
            address(UNI),
            Comptroller(address(unitroller)),
            model,
            1e18,
            "cUNI TOKEN",
            "cUNI",
            18, 
            payable(admin),
            address(delegate),
            new bytes(0)
        );

        /// cUSDC Token Creation
        cUSDC = new CErc20Delegator(
            address(USDC),
            Comptroller(address(unitroller)),
            model,
            1e6, // USDC decimal is 6
            "cUSDC TOKEN",
            "cUSDC",
            18,
            payable(admin),
            address(delegate),
            new bytes(0)
        );

        /// Price Configuration
        oracle.setUnderlyingPrice(CToken(address(cUSDC)), 1e30); // Set USDC price to $1, USDC decimal is 6
        oracle.setUnderlyingPrice(CToken(address(cUNI)), 5e18);  // Set UNI price to $5

        /// Support Market Configuration
        Comptroller(address(unitroller))._supportMarket(CToken(address(cUSDC)));
        Comptroller(address(unitroller))._supportMarket(CToken(address(cUNI)));

        /// Close Factor Configuration
        Comptroller(address(unitroller))._setCloseFactor(5e17);  // Close Factor: 50%

        /// Liquidation Incentive Configuration
        Comptroller(address(unitroller))._setLiquidationIncentive(1.08 * 1e18); // Liquidation Incentive: 8%

        /// Collateral Factor Configuration
        Comptroller(address(unitroller))._setCollateralFactor(CToken(address(cUNI)), 5e17); // Collateral Factor: 50%

        vm.stopPrank();
    }

    function _provideBorrowAsset() internal {
        vm.startPrank(provider);
        /// Token Distribution
        amount = 10000 * 10 ** IERC20(USDC).decimals();
        deal(address(USDC), provider, amount);

        /// Provide Borrowed Asset
        IERC20(USDC).approve(address(cUSDC), amount);
        errorCode = cUSDC.mint(amount);

        /// Balance Check
        assertEq(errorCode, 0);
        vm.stopPrank();
    }

    function _borrowAsset() internal {
        uint256 err;
        uint256 shortfall;
        uint256 liquidity;

        vm.startPrank(user);
        /// Token Distribution
        amount = 1000 * 10**IERC20(UNI).decimals();
        deal(UNI, user, amount);

        /// Enter Market
        address[] memory tokens = new address[](1);
        tokens[0] = address(cUNI);
        Comptroller(address(unitroller)).enterMarkets(tokens);

        /// Mint Collateral
        IERC20(UNI).approve(address(cUNI), amount);
        errorCode = cUNI.mint(amount);
        assertEq(errorCode, 0);

        /// Liquidity Check 
        // 1. User has 1000 UNI token
        // 2. UNI token price is $5
        // 3. Collateral Factor is 50%
        // Total Liquidity should be 1000 * $5 * 50% = $2500
        (err, liquidity, shortfall) = Comptroller(address(unitroller)).getAccountLiquidity(user);
        assertEq(err, 0);
        assertEq(liquidity, 2500 * 1e18);
        assertEq(shortfall, 0);

        /// Borrow Asset
        errorCode = cUSDC.borrow(2500 * 10**IERC20(USDC).decimals());
        assertEq(errorCode, 0);

        /// Liquidity Check
        // 1. User borrowed 2500 USDC token
        // 2. USDC token price is $1
        // Total Liquidity = Original Account Liquidity - Borrowed Asset Value = $2500 - $2500 = $0
        (err, liquidity, shortfall) = Comptroller(address(unitroller)).getAccountLiquidity(user);
        assertEq(err, 0);
        assertEq(liquidity, 0);
        assertEq(shortfall, 0);
        vm.stopPrank();
    }

    function _modifyUniPrice() internal {
        vm.startPrank(admin);
        /// Update UNI Price
        oracle.setUnderlyingPrice(CToken(address(cUNI)), 4e18); // Set Uni Price to $4

        /// Liquidity Check
        // 1. User has 1000 UNI as collateral
        // 2. User borrowed 2500 USDC token
        // 3. Collateral Factor is 50%
        // 4. UNI token price drop to $4
        // Account Liquidity = 1000 * 50% * $4 - 2500 * $1 = $2000 - $2500 = -500 -> shortfall
        (uint256 err, uint256 liquidity, uint256 shortfall) = Comptroller(address(unitroller)).getAccountLiquidity(user);
        assertEq(err, 0);
        assertEq(liquidity, 0);
        assertEq(shortfall, 500 * 1e18);
        vm.stopPrank();
    }

    function testFlashloanLiquidation() public {
        
        _provideBorrowAsset();

        _borrowAsset();

        _modifyUniPrice();

        vm.startPrank(liquidator);
        /// Liquidation
        bot = new Liquidate();

        /// Repay Amount Calculation
        // 1. User borrowed amount is 500
        // 2. Close Factor is 50%
        // Maximum repay amount = borrow balance * close factor
        uint256 repayAmount = cUSDC.borrowBalanceStored(user) / 2;
        uint256 initialUSDCBalance = IERC20(USDC).balanceOf(liquidator);
        bot.liquidation(repayAmount, cUSDC, user, cUNI);
        bot.withdraw();
        uint256 finalUSDCBalance = IERC20(USDC).balanceOf(liquidator);

        /// Balance Check
        assertGt(finalUSDCBalance - initialUSDCBalance, 63 * 10**IERC20(USDC).decimals());
        vm.stopPrank();
    }
 }