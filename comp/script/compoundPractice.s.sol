// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

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

contract CounterScript is Script {

    uint256 public privateKey;

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
        privateKey = vm.envUint("PRIVATE_KEY");
    }

    function run() public {
        vm.startBroadcast(privateKey);
        underlyingToken = new UnderlyingToken(initialSupply, name, symbol);
        comptroller = new Comptroller();
        whitePaperInterestRateModel = new WhitePaperInterestRateModel(baseRatePerYear, multiplierPerYear);
        initialExchangeRateMantissa = 10 * (underlyingToken.decimals() - 8);
        delegate = new CErc20Delegate();
        admin = payable(vm.envAddress("EOA_ADDRESS"));
        implementation = address(delegate);

        delegator = new CErc20Delegator(
            address(underlyingToken),
            ComptrollerInterface(address(comptroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            initialExchangeRateMantissa,
            name,
            symbol,
            underlyingToken.decimals(),
            admin,
            implementation,
            bytes("")
        );

        simplePriceOracle = new SimplePriceOracle();
        comptroller._setPriceOracle(PriceOracle(address(simplePriceOracle)));

        unitroller = new Unitroller();
        vm.stopBroadcast();
    }
}
