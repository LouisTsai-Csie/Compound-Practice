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


contract CompoundTest is Test {

    address public admin;
    address public provider;
    address public user;
    address public liquidator;

    // CErc20Delegator
    CErc20Delegator public CTokenA; // CToken A
    CErc20Delegator public CTokenB; // CToken B

    /// Underlying Token
    UnderlyingToken public tokenA; // Underlying Token 0
    UnderlyingToken public tokenB; // Underlying Token 1
    uint256 public constant initialSupply = 1e21;
    string public constant name0 = "token0";
    string public constant symbol0 = "t0";
    string public constant name1 = "token1";
    string public constant symbol1 = "t1"; 

    /// Comptroller
    Comptroller public comptroller;

    /// WhitePaperInterestRateModel
    WhitePaperInterestRateModel public whitePaperInterestRateModel;

    /// CErc20Delegate
    CErc20Delegate public delegate;

    // SimplePriceOracle
    SimplePriceOracle public simplePriceOracle;

    // Unitroller
    Unitroller public unitroller;

    function createCErc20Token0() internal {

        CTokenA = new CErc20Delegator(
            address(tokenA),
            Comptroller(address(unitroller)),
            whitePaperInterestRateModel,
            1e18,
            name0,
            symbol0,
            tokenA.decimals(),
            payable(admin),
            address(delegate),
            bytes("")
        );

    }

    function createCErc20Token1() internal {

        CTokenB = new CErc20Delegator(
            address(tokenB),
            Comptroller(address(unitroller)),
            whitePaperInterestRateModel,
            1e18,
            name1,
            symbol1,
            tokenB.decimals(),
            payable(admin),
            address(delegate),
            bytes("")
        );
    }

    function setUp() public {
        admin = makeAddr("admin");
        provider = makeAddr("provider");
        user = makeAddr("user");
        liquidator = makeAddr("liquidator");
        
        vm.startPrank(provider);
        tokenA = new UnderlyingToken(initialSupply, name0, symbol0);
        tokenB = new UnderlyingToken(initialSupply, name1, symbol1);
        vm.stopPrank();

        vm.startPrank(admin);
        delegate = new CErc20Delegate();
        whitePaperInterestRateModel = new WhitePaperInterestRateModel(0, 0);
        comptroller = new Comptroller();
        unitroller = new Unitroller();
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);
        
        createCErc20Token0();
        createCErc20Token1();

        Comptroller(address(unitroller))._supportMarket(CToken(address(CTokenA)));
        Comptroller(address(unitroller))._supportMarket(CToken(address(CTokenB)));

        simplePriceOracle = new SimplePriceOracle();
        Comptroller(address(unitroller))._setPriceOracle(PriceOracle(address(simplePriceOracle)));

        vm.stopPrank();

        deal(address(tokenA), user, 100 * 10**tokenA.decimals()); // 100 unit of token
        deal(address(tokenA), liquidator, 100 * 10**tokenA.decimals()); // 100 unit of token
        deal(address(tokenB), user, 100 * 10**tokenB.decimals()); // 100 unit of token
        deal(address(tokenB), liquidator, 100 * 10**tokenB.decimals()); // 100 unit of token

        vm.label(admin, "admin");
        vm.label(provider, "provider");
        vm.label(user, "user");
        vm.label(liquidator, "liquidator");
    }

    function _setDefaultConfiguration() internal {
        vm.startPrank(admin);
        simplePriceOracle.setUnderlyingPrice(CToken(address(CTokenA)), 1e18); // set token A price to $1
        simplePriceOracle.setUnderlyingPrice(CToken(address(CTokenB)), 1e20); // set token B price to $100
        Comptroller(address(unitroller))._setCollateralFactor(CToken(address(CTokenB)), 5e17); // set Collateral Factor to 50%
        vm.stopPrank();
    }

    function _setBorrowConfiguration() internal {
        /// Provider mint CToken A 
        vm.startPrank(provider);
        tokenA.approve(address(CTokenA), 2**256-1);
        CTokenA.mint(100 * 10**tokenA.decimals());
        vm.stopPrank();
    }

    

    function testBorrowAndRepay() public {
        _setDefaultConfiguration();

        _setBorrowConfiguration();

        
        uint256 errorCode;
        uint256 prevBalance;
        uint256 afterBalance;
        vm.startPrank(user);
        /// Enter Markets 
        address[] memory tokens = new address[](1);
        tokens[0] = address(CTokenB);
        Comptroller(address(unitroller)).enterMarkets(tokens);

        /// Mint Operation
        tokenB.approve(address(CTokenB), 2**256-1);
        prevBalance = CTokenB.balanceOf(user);
        errorCode = CTokenB.mint(1e18);
        require(errorCode==0, "Mint Not Allowed");
        afterBalance = CTokenB.balanceOf(user);
        require(prevBalance+1e18==afterBalance, "Mint Amount Not Matched");

        /// Borrow Operation
        uint256 borrowBalance;
        errorCode = CTokenA.borrow(1e18);
        require(errorCode==0, "Borrow Not Allowed");
        borrowBalance = CTokenA.borrowBalanceCurrent(user);
        require(borrowBalance==1e18, "Borrow Balance Not Matched");
        

        /// Repay Operation
        tokenA.approve(address(CTokenA), 2**256-1);
        CTokenA.repayBorrow(1e18);
        borrowBalance = CTokenA.borrowBalanceCurrent(user);
        require(borrowBalance==0, "Borrow Balance Not Repay");
        vm.stopPrank();
    }

    function testModifyCollaterFactorToLiquidate() public {
        _setDefaultConfiguration();

        _setBorrowConfiguration();

        uint256 errorCode;
        uint256 prevBalance;
        uint256 afterBalance;
        vm.startPrank(user);
        /// Enter Markets
        address[] memory tokens = new address[](1);
        tokens[0] = address(CTokenB);
        Comptroller(address(unitroller)).enterMarkets(tokens);

        /// Mint Operation
        tokenB.approve(address(CTokenB), 2**256-1);
        prevBalance = CTokenB.balanceOf(user);
        errorCode = CTokenB.mint(1e18);
        require(errorCode==0, "Mint Not Allowed");
        afterBalance = CTokenB.balanceOf(user);
        
        /// Borrow Operation
        require(prevBalance+1e18==afterBalance, "Mint Amount Not Matched");
        errorCode = CTokenA.borrow(5e19);
        require(errorCode==0, "Borrow Not Allowed");
        vm.stopPrank();

        /// Set up liquidation configuration
        vm.startPrank(admin);
        Comptroller(address(unitroller))._setCollateralFactor(CToken(address(CTokenB)), 1e17); // set collateral factor to 10%
        Comptroller(address(unitroller))._setCloseFactor(5e17);                                // set close factor to 50%
        Comptroller(address(unitroller))._setLiquidationIncentive(1.08 * 10**18);              // set liquidation incentive to 1.08
        vm.stopPrank();

        (uint256 err, uint256 liquidity, uint256 shortfall) = Comptroller(address(unitroller)).getAccountLiquidity(user);
        require(err==0, "Account Liquidity Error");
        require(liquidity==0, "Account Liquidity Not Zero");
        require(shortfall>0, "Unable to liquidate");

        uint256 liquidateAmount = CTokenA.borrowBalanceStored(user) / 4;

        /// Liquidate Operation
        vm.startPrank(liquidator);
        tokenA.approve(address(CTokenA), 2**256-1);
        errorCode = CTokenA.liquidateBorrow(user, liquidateAmount, CTokenB);
        require(errorCode==0, "Liquidate Not Success");
        vm.stopPrank();
    }

    function testModifyOraclePriceToLiquidate() public {
        _setDefaultConfiguration();

        _setBorrowConfiguration();

        uint256 errorCode;
        uint256 prevBalance;
        uint256 afterBalance;
        vm.startPrank(user);
        /// Enter Markets
        address[] memory tokens = new address[](1);
        tokens[0] = address(CTokenB);
        Comptroller(address(unitroller)).enterMarkets(tokens);

        /// Mint Operation
        tokenB.approve(address(CTokenB), 2**256-1);
        prevBalance = CTokenB.balanceOf(user);
        errorCode = CTokenB.mint(1e18);
        require(errorCode==0, "Mint Not Allowed");
        afterBalance = CTokenB.balanceOf(user);
        
        /// Borrow Operation
        require(prevBalance+1e18==afterBalance, "Mint Amount Not Matched");
        errorCode = CTokenA.borrow(5e19);
        require(errorCode==0, "Borrow Not Allowed");
        vm.stopPrank();

        /// Set up liquidation configuration
        vm.startPrank(admin);
        simplePriceOracle.setUnderlyingPrice(CToken(address(CTokenA)), 1e19);     // set CToken A price to $1
        Comptroller(address(unitroller))._setCloseFactor(5e17);                   // set close factor to 50%
        Comptroller(address(unitroller))._setLiquidationIncentive(1.08 * 10**18); // set liquidation incentive to 1.08
        vm.stopPrank();

        (uint256 err, uint256 liquidity, uint256 shortfall) = Comptroller(address(unitroller)).getAccountLiquidity(user);
        require(err==0, "Account Liquidity Error");
        require(liquidity==0, "Account Liquidity Not Zero");
        require(shortfall>0, "Unable to liquidate");

        uint256 liquidateAmount = CTokenA.borrowBalanceStored(user) / 10;
        
        vm.startPrank(liquidator);
        tokenA.approve(address(CTokenA), 2**256-1);
        errorCode = CTokenA.liquidateBorrow(user, liquidateAmount, CTokenB);
        require(errorCode==0, "Liquidate Not Success");
        vm.stopPrank();
    }


}
