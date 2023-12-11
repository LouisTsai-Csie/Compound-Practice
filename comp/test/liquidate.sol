// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Comptroller} from "../src/Comptroller.sol";
import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {CToken} from "../src/CToken.sol";

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
interface Aave {
    function flashLoanSimple(address, address, uint256, bytes calldata, uint16) external;
}

interface ISwapRouter {
     struct ExactInputSingleParams {
         address tokenIn;
         address tokenOut;
         uint24 fee;
         address recipient;
         uint256 deadline;
         uint256 amountIn;
         uint256 amountOutMinimum;
         uint160 sqrtPriceLimitX96;
     }
     function exactInputSingle(ISwapRouter.ExactInputSingleParams memory params) external returns (uint256 amountOut);
 }
contract Liquidate {

    /// Role
    address public admin;

    /// Contract Address
    Aave pool = Aave(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// Token Address
    address internal USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal UNI  = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    /// Common Variable
    uint256 internal errorCode;
    uint256 internal balance;

    /// Modifier
    modifier onlyAdmin() {
        require(msg.sender==admin, "Only Admin");
        _;
    }

    /// Constructor
    constructor() payable {
        admin = msg.sender;
    }

    
    function liquidation(uint256 amount, CErc20Delegator cUSDC, address borrower, CErc20Delegator cUNI) external onlyAdmin{
        bytes memory data = abi.encode(cUSDC, borrower, cUNI);

        /**
         * @param receiverAddress Address of the contract that will receive the flash borrowed funds.
         * @param asset Address of the underlying asset that will be flash borrowed.
         * @param amount Amount of asset being requested for flash borrow
         * @param params Arbitrary bytes-encoded params that will be passed to executeOperation() method of the receiver contract.
         * @param referralCode Referral Code used for 3rd party integration referral.
         */
        pool.flashLoanSimple(
            address(this),  // Reciever Address
            USDC,           // Asset
            amount,       // Amount
            data,           // Params
            0               // Referral Code
        );
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        /// Security Checks
        require(msg.sender==address(pool), "Invalid Sender");
        require(initiator==address(this), "Invalid Initiator");

        // 1. Get USDC from flashloan
        // 2. Repay debt for borrower
        // 3. Receive cUNI token as reward
        // 4. Redeem cUNI token to UNI token
        // 5. repay UNI Token and fee for Aave

        /// Liquidation
        {
        (CErc20Delegator cUSDC, address borrower, CErc20Delegator cUNI) = abi.decode(params, (CErc20Delegator, address, CErc20Delegator));
        IERC20(USDC).approve(address(cUSDC), 2**256-1);
        uint256 initialcUNIBalance = cUNI.balanceOf(address(this));
        errorCode = cUSDC.liquidateBorrow(borrower, amount, cUNI);
        uint256 finalcUNIBalance = cUNI.balanceOf(address(this));
        require(errorCode==0, "Liquidation Failed");

        /// Redeem
        balance = finalcUNIBalance - initialcUNIBalance;
        
        
        uint256 initialUNIBalance = IERC20(UNI).balanceOf(address(this));
        errorCode = cUNI.redeem(balance);
        uint256 finalUNIBalance = IERC20(UNI).balanceOf(address(this));
        require(errorCode==0, "Redeem Failed");
        /// Swap
        /**
         * @param tokenIn The contract address of the inbound token
         * @param tokenOut The contract address of the outbound token
         * @param fee The fee tier of the pool, used to determine the correct pool contract in which to execute the swap
         * @param recipient the destination address of the outbound token
         * @param deadline the unix time after which a swap will fail, to protect against long-pending transactions and wild swings in prices
         * @param amountOutMinimum protect against bad price due to a front running sandwich or price manipulation
         * @param sqrtPriceLimitX96 set the limit for the price the swap will push the pool to
         */
        balance = finalUNIBalance - initialUNIBalance;
        IERC20(UNI).approve(address(router), balance);
        }
        ISwapRouter.ExactInputSingleParams memory data =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: UNI,
                tokenOut: asset,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: IERC20(UNI).balanceOf(address(this)),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uint256 amountOut = router.exactInputSingle(data);


        /// Repay Flashloan
        // The total amount repay = borrow amount + premium (fee)
        IERC20(asset).approve(address(pool), amountOut+premium);

        return true;
    }

    function withdraw() external onlyAdmin {
        bool success = IERC20(USDC).transfer(admin, IERC20(USDC).balanceOf(address(this)));
        require(success==true, "Transfer Failed");
    }
}