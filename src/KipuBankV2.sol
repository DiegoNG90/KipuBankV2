// SPDX-License-Identifier: MIT
pragma solidity > 0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


/*
    @title KipuBank V2 Smart Contract
    @author DiegoNG90. Contact through Github https://github.com/DiegoNG90
    @notice This contract allows users to deposit and withdraw Ether (ETH) and USDC. It implements a global deposit limit (`BANKCAP`) and a per-transaction withdrawal limit
    (`MAXIMUM_WITHDRAWAL_IN_USD`), both denominated in USD.
    All internal accounting (`totalDepositsInUSD`) is tracked in USD (with 6 decimals).
    @dev version 2.0.0
    @dev Implements `Ownable` from OpenZeppelin for access control over administrative functions.
    It uses Chainlink Data Feeds to convert ETH values to USD.
    It employs a nested mapping (`balances[user][token]`) for multi-token accounting,
    where `address(0)` is used to represent ETH.
    @custom::security This is a hands-on/practical work. It's not intended to be deployed in production.
 */


contract KipuBank is Ownable, ReentrancyGuard {
    /*
         @notice The Chainlink Aggregator V3 Interface used to fetch the current ETH/USD price feed.
         @dev This instance is used by internal functions to convert deposited/withdrawn ETH (Wei) into USD (6 decimals) for internal accounting and limit checking.
    */
    AggregatorV3Interface public dataFeed;
    /*
         @notice balances is a nested mapping used for multi-token accounting. 
         @dev The mapping structure is `balances[userAddress][tokenAddress]`. The first key is the user's address. The second key is the token's contract address. 
         By convention, `address(0)` is used to represent the native currency (ETH) balance in Wei.
    */
    mapping(address => mapping(address => uint256)) public balances;
    /*
        @notice USDC reference to the deployed USDC ERC-20 token contract.
        @dev This variable is set upon deployment (`immutable`) and cannot be changed. USDC (with 6 decimals) is the only ERC-20 token supported and serves as the standard 
        for all internal USD accounting.
    */
    IERC20 public immutable USDC;
    /*
        @notice MAXIMUM_WITHDRAWAL_IN_USD is the maximum value, denominated in USD (6 decimals), that can be withdrawn in a single transaction.
        @dev This value is set at deployment time (`immutable`) and enforced across both ETH and ERC-20 token withdrawals.
    */
    uint256 public immutable MAXIMUM_WITHDRAWAL_IN_USD;
    /*
        @notice BANKCAP is the absolute maximum global deposit limit for the KipuBank contract, denominated in USD (6 decimals).
        @dev This immutable ceiling prevents excessive accumulation of funds and is enforced by comparing the incoming USD value against `totalDepositsInUSD`.
     */
    uint256 public immutable BANKCAP;
    /*
        @notice totalDepositsInUSD tracks the current total value of all deposits held by the contract, denominated in USD (6 decimals).
        @dev Public visibility allows users to calculate remaining deposit capacity against the `BANKCAP`. This value is updated after every successful deposit and withdrawal.
     */
    uint256 public totalDepositsInUSD;
    /// @notice totalDepositOperations variable is a counter for the total number of successful deposit operations that have occurred.
    uint256 public totalDepositOperations;
    /// @notice totalWithdrawalsOperations variable is a Counter for the total number of successful withdrawal operations that have occurred.  
    uint256 public totalWithdrawalsOperations;


    /*
        @notice FeedSet is event that fires when an Oracle has been set succesfully.  
        @params _address address type input, _time uint256 type input
    */
    event FeedSet(address indexed _address, uint256 _time);
    /*
        @notice SuccessfulEtherWithdrawal is an event that fires when a ETH withdrawal has been made succesfully.  
        @params _sender address type input, _amount uint256 type input 
    */
    event SuccessfulEtherWithdrawal(address indexed _sender, uint256 _amount);
    /*
        @notice SuccessfulTokenWithdrawal is an event that fires when a TOKEN withdrawal has been made succesfully.  
        @params _sender address type input, _tokenAddress address type input, _amount uint256 type input
    */
    event SuccessfulTokenWithdrawal(address indexed _sender, address indexed _tokenAddress, uint256 _amount);
    /*
        @notice SuccessfulEtherDeposit is an event that fires when a ETH deposit has been made succesfully.  
        @params _sender address type input, _deposit uint256 type input
    */
    event SuccessfulEtherDeposit(address _sender, uint256 _deposit);
    /*
        @notice SuccessfulTokenDeposit is an event that fires when a TOKEN deposit has been made succesfully.  
        @params _sender address type input, _tokenAddress address type input, _amount uint256 type input
    */
    event SuccessfulTokenDeposit(address _sender, address _tokenAddress, uint256 _amount);
    
    
    /// @notice InvalidAmount is a custom error that tells KipuBank user that indicates an invalid input amount (i.e., zero value or insufficient user balance).
    error InvalidAmount(); 
    /*
        @notice WithdrawalAmountTooHigh is a custom error that indicates that the requested withdrawal amount has exceeded the per-transaction limit
        defined by `MAXIMUM_WITHDRAWAL_IN_USD`.
    */
    error WithdrawalAmountTooHigh();
    /// @notice BankCapReached is a custom error that indicates the deposit amount would cause the total contract holdings to exceed the global limit (`BANKCAP`).
    error BankCapReached(); 
    /*
        @notice FailureWithdrawal is a custom error that indicates a failure during the native ETH transfer.  
        @params _error bytes type input
    */
    error FailureWithdrawal(bytes _error);
    /// @notice TokenTransferFailed is a custom error that indicates a failure during the external ERC-20 token transfer (transfer/transferFrom). 
    error TokenTransferFailed();
    /* 
        @notice TokenNotSupported is a custom error that indicates that the token address provided is not the supported USDC token.  
        @params _tokenAddress address type input
    */
    error TokenNotSupported(address _tokenAddress);
    /// @notice InvalidContract is a custom error that indicates an invalid contract configuration during deployment or administration.
    error InvalidContract();


    /*
        @notice the constructor function initializes the contract, setting immutable limits and linking external dependencies (Oracle, USDC).
        The deployer is automatically set as the contract owner (`Ownable(msg.sender)`).
        @param _bankCap uint256 input type is the absolute maximum total deposit limit, denominated in USD (6 decimals).
        @param _maxWithdrawalInUSD uint256 input type is the maximum value a user can withdraw per transaction, denominated in USD (6 decimals).
        @param _oracle address input type is the address of the Chainlink Aggregator V3 Interface for the ETH/USD price feed.
        @param _usdcToken IERC20 (address) input type is the address of the supported USDC ERC-20 token contract.
        @dev The constructor enforces non-zero addresses for external contracts and initializes the `BANKCAP` 
        and `MAXIMUM_WITHDRAWAL_IN_USD` constants.
    */
    constructor(uint256 _bankCap, uint256 _maxWithdrawalInUSD, AggregatorV3Interface _oracle, IERC20 _usdcToken) Ownable(msg.sender) {
        if (address(_oracle) == address(0) || address(_usdcToken) == address(0)) revert InvalidContract();
        BANKCAP = _bankCap;
        MAXIMUM_WITHDRAWAL_IN_USD = _maxWithdrawalInUSD;
        dataFeed = _oracle;
        USDC = _usdcToken;
        emit FeedSet(address(_oracle), block.timestamp);
    }

    /*
        @notice Allows reception of native Ether (ETH) sent without specifying a function.
        @dev Forwards execution to `depositEther()` to enforce security checks (BANKCAP, oracle conversion) and correct accounting via the multi-token mapping.
    */
    receive() external payable {
        depositEther();
    }

    /*
        @notice setFeeds function allows the contract owner to update the Chainlink Data Feed address.
        @param _feed The new address of the Aggregator V3 Interface contract for the ETH/USD price.
        @dev This function is restricted to the contract owner via the `onlyOwner` modifier. 
        It reverts if the provided address is the zero address (0x0000000000000000000000000000000000000000).
    */
    function setFeeds(address _feed) external onlyOwner {
        if(_feed == address(0)) revert InvalidContract();
        dataFeed = AggregatorV3Interface(_feed);
        emit FeedSet(_feed, block.timestamp);
    }

    /*
        @notice depositToken function allows any user to deposit the supported ERC-20 token (USDC) into their account balance.
        @param _tokenAddress address input type is the address of the ERC-20 token being deposited. Must be USDC.
        @param _amount uint256 input type is the amount of tokens (with 6 decimals) to deposit.
        @dev depositToken requires the user to first approve the KipuBank contract to spend the tokens via `IERC20.approve()`.
        The token amount is added directly to `totalDepositsInUSD` and checked against the `BANKCAP`.
        Reverts if the token is not USDC, the amount is zero, or the BANKCAP is exceeded.
        This function follows the Checks-Effects-Interactions (CEI) pattern to ensure security.
        Emits a `SuccessfulTokenDeposit` event upon successful deposit.
    */
    function depositToken(address _tokenAddress, uint256 _amount) external{
        if(_amount <= 0) revert InvalidAmount();
        if(_tokenAddress != address(USDC)) revert TokenNotSupported(_tokenAddress);
        if (totalDepositsInUSD + _amount > BANKCAP) revert BankCapReached();

        USDC.transferFrom(msg.sender, address(this), _amount);
        incrementDepositsOperations();
        incrementDepositsInUSD(_amount);
        balances[msg.sender][_tokenAddress] += _amount;

        emit SuccessfulTokenDeposit(msg.sender, _tokenAddress, _amount);
    }

    /*
        @notice withdrawEther function processes a withdrawal request for native Ether (ETH) from the user's balance.
        @param _amount unit256 input type is the amount of ETH (in Wei) to withdraw.
        @dev The amount is converted to USD using the Chainlink oracle to check against the `MAXIMUM_WITHDRAWAL_IN_USD` limit and to update `totalDepositsInUSD`. 
        Follows the Checks-Effects-Interactions (CEI) pattern: user balance is updated before the external call (`msg.sender.call`), mitigating reentrancy risks.
        Also uses the `nonReentrant` modifier from OpenZeppelin's `ReentrancyGuard` to provide additional and enhanced security against reentrancy attacks.
        FailureWithdrawal error is thrown if the ETH transfer fails.
        Emits a `SuccessfulEtherWithdrawal` event upon successful withdrawal.
    */
    function withdrawEther(uint256 _amount) external nonReentrant{
        if (_amount == 0) revert InvalidAmount();
        uint256 userBalance = balances[msg.sender][address(0)];
        if (_amount > userBalance) revert InvalidAmount();
 
        uint256 usdValue = _getETHToUSD(_amount);
        if (usdValue > MAXIMUM_WITHDRAWAL_IN_USD) revert WithdrawalAmountTooHigh();

        decrementDepositsInUSD(usdValue);
        incrementWithdrawalsOperations();
        balances[msg.sender][address(0)] = userBalance - _amount;

        (bool success, bytes memory error) = msg.sender.call{value: _amount}("");
        if (!success) revert FailureWithdrawal(error);

        emit SuccessfulEtherWithdrawal(msg.sender, _amount);
    }

    /*
        @notice withdrawToken function processes a withdrawal request for the supported ERC-20 token (USDC) from the user's balance.
        @param _tokenAddress address input type is the address of the token to withdraw (must be USDC).
        @param _amount uint256 input type is the amount of USDC (with 6 decimals) to withdraw.
        @dev The withdrawal amount is checked against the user's token balance and the `MAXIMUM_WITHDRAWAL_IN_USD` limit. The function directly uses `USDC.transfer()`
        as the contract is the owner of the funds. Follows the Checks-Effects-Interactions (CEI) pattern.
    */
    function withdrawToken(address _tokenAddress, uint256 _amount) external {
        if(_tokenAddress != address(USDC)) revert TokenNotSupported(_tokenAddress);
        uint256 userBalance = balances[msg.sender][_tokenAddress];
        if (_amount > userBalance || _amount == 0) revert InvalidAmount();

        if (_amount > MAXIMUM_WITHDRAWAL_IN_USD) revert WithdrawalAmountTooHigh();

        balances[msg.sender][_tokenAddress] = userBalance - _amount;
        decrementDepositsInUSD(_amount);
        incrementWithdrawalsOperations();

        bool success = USDC.transfer(msg.sender, _amount);
        if (!success) revert TokenTransferFailed();

        emit SuccessfulTokenWithdrawal(msg.sender, _tokenAddress, _amount);
    }


    /*
        @notice depositEther function allows any user to deposit native Ether (ETH) into their account balance.
        @dev The value sent (`msg.value`) is converted to USD (6 decimals) using the Chainlink Oracle.
        The transaction reverts if the deposit amount causes the total deposits to exceed the `BANKCAP`
        or if the sent ETH amount is zero. Uses `address(0)` as the token address key in the `balances` mapping.
        This function follows the Checks-Effects-Interactions (CEI) pattern to ensure security.
        Emits a `SuccessfulEtherDeposit` event upon successful deposit.
    */
    function depositEther() public payable {
        if (msg.value <= 0) revert InvalidAmount();

        uint256 usdValue = _getETHToUSD(msg.value);

        if (totalDepositsInUSD + usdValue > BANKCAP) revert BankCapReached();

        incrementDepositsOperations();
        incrementDepositsInUSD(usdValue);
        balances[msg.sender][address(0)] += msg.value;

        emit SuccessfulEtherDeposit(msg.sender, msg.value);
    }


    /*
        @notice incrementWithdrawalsOperations function handles the totalWithdrawalsOperations counter increase.
        @dev Implemented with 'unchecked' block to bypass default Solidity >= 0.8.0 overflow checks. This is a safe gas optimization, 
        as 'totalWithdrawalsOperations' is a simple uint256 counter, making overflow virtually impossible to reach in practice.
    */
    function incrementWithdrawalsOperations() private {
        unchecked {
            ++totalWithdrawalsOperations;
        }
    }

    /* 
        @notice incrementDepositsOperations function handles the totalDepositOperations counter increase.
        @dev Implemented with 'unchecked' block to bypass default Solidity >= 0.8.0 overflow checks. This is a safe gas optimization, 
        as 'totalDepositOperations' is a simple uint256 counter, making overflow virtually impossible to reach in practice.
    */
    function incrementDepositsOperations() private{
        unchecked {
            ++totalDepositOperations;
        }
    }

    /* 
        @notice incrementDepositsFunds function handles the totalDepositsInUSD increase.
        @params _amount uint256 input type is the amount to increment.
    */
    function incrementDepositsInUSD(uint256 _amount) private{
        totalDepositsInUSD += _amount;
    }

    /*
        @notice decrementDepositsInUSD function handles the totalDepositsInUSD decrease.
        @params _amount uint256 input type is the amount to decrement.
    */
    function decrementDepositsInUSD(uint256 _amount) private{
        totalDepositsInUSD -= _amount;
    }

    /*
        @notice _getETHPrice retrieves the latest ETH/USD price from Chainlink data feed.
        @dev Calls `latestRoundData()` on the `dataFeed` variable to get
        the latest round information and extracts only the price (answer).
        @return int256 is the latest ETH price in USD, denominated with 8 decimals.
    */
    function _getETHPrice() private view returns (int256){
        ( , int256  _latestAnswer, , ,) = dataFeed.latestRoundData();
         return _latestAnswer;
    }

    /*
        @notice _getETHToUSD converts an amount of ETH (wei) to its equivalent in USD (6 decimals).
        @param _ethAmount La cantidad de ETH en wei (18 decimales).
        @return usdValue El valor equivalente en USD (6 decimales).
    */
    function _getETHToUSD(uint256 _ethAmount) private view returns (uint256) {
        int256 price = _getETHPrice();
        uint256 usdValue = (_ethAmount * uint256(price)) / 10**20;
        return usdValue;
    }
}
