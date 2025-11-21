// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IOptimismPortal2.sol";

contract TokenConversion is Initializable, PausableUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");

    address public erc20In;
    address public optimismPortal2;
    uint256 public startTime;
    uint256 public endTime;

    event TokenConverted(address account, uint256 amount);
    event ConversionPeriodUpdated(uint256 startTime, uint256 endTime);
    event TokensDrained(address indexed admin, uint256 amount);
    event ContractPaused(address account);
    event ContractUnpaused(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _erc20In,
        address _optimismPortal2,
        uint256 _startTime,
        uint256 _endTime,
        address admin,
        address pauser,
        address miner
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();

        require(_erc20In != address(0), "TokenConversion: invalid _erc20In token address");
        require(_optimismPortal2 != address(0), "TokenConversion: invalid _optimismPortal2 address");
        require(_startTime < _endTime, "TokenConversion: start time must be before end time");
        require(admin != address(0), "TokenConversion: invalid admin address");
        require(pauser != address(0), "TokenConversion: invalid pauser address");

        erc20In = _erc20In;
        optimismPortal2 = _optimismPortal2;
        startTime = _startTime;
        endTime = _endTime;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(MINER_ROLE, miner);
    }

    /**
     * @notice Converts a specified amount of `erc20` tokens owned by the caller
     * into `l2 erc20` tokens at a 1:1 conversion rate.
     * @dev The caller must approve this contract to spend at least `_amount`
     * of their `erc20In` tokens before calling this function.
     * @param _amount The amount of `erc20In` tokens to convert.
     */
    function convert(uint256 _amount) external whenNotPaused {
        address sender = _msgSender();

        require(block.timestamp >= startTime, "TokenConversion: conversion period has not started");
        require(block.timestamp < endTime, "TokenConversion: conversion period has ended");

        uint256 totalBalance = IERC20(erc20In).balanceOf(sender);
        require(totalBalance >= _amount, "TokenConversion: not enough tokens");
        uint256 allowance = IERC20(erc20In).allowance(sender, address(this));
        require(allowance >= _amount, "TokenConversion: insufficient allowance");

        // transfer from user to contract
        uint256 balanceBefore = IERC20(erc20In).balanceOf(address(this));
        IERC20(erc20In).safeTransferFrom(sender, address(this), _amount);
        uint256 balanceAfter = IERC20(erc20In).balanceOf(address(this));
        require(balanceAfter - balanceBefore == _amount, "TokenConversion: transfer failed");

        // TODO
        // burn by sending to dead address
        // Do NOT send tokens to address(0).
        // Many ERC20 implementations treat address(0) as an invalid receiver
        // and will revert the transaction to prevent misuse or accidental loss.
        //
        // Instead, use the "dead" address (0x000...dEaD) which is a known burn address
        // with no private key and is used for pseudo-burning tokens.
        // address receiver = 0x000000000000000000000000000000000000dEaD;
        // IERC20(erc20In).safeTransfer(receiver, _amount);

        // mint l2 token
        IOptimismPortal2(optimismPortal2).mintTransaction(sender, _amount);

        emit TokenConverted(sender, _amount);
    }

    /**
     * @notice Mints L2 tokens to a specified address. Used to migrate QuarkChain mainnet tokens that are not mapped by ERC20 to the L2 tokens.
     * @dev Only accounts with the MINER_ROLE can call this function.
     * @param _to The address to mint L2 tokens to.
     * @param _amount The amount of L2 tokens to mint.
     */
    function mintL2Tokens(address _to, uint256 _amount) external onlyRole(MINER_ROLE) {
        IOptimismPortal2(optimismPortal2).mintTransaction(_to, _amount);
    }

    /**
     * @notice Drains all `erc20Out` tokens from the contract to the caller.
     * @dev Only the contract admin can call this function.
     */
    function drain() external onlyRole(DEFAULT_ADMIN_ROLE) {
        address sender = _msgSender();
        uint256 balance = IERC20(erc20In).balanceOf(address(this));
        require(balance > 0, "TokenConversion: no tokens to drain");

        IERC20(erc20In).safeTransfer(sender, balance);
        emit TokensDrained(sender, balance);
    }

    /**
     * @notice Sets the conversion period start and end times.
     * @dev Only the contract admin can call this function.
     * @param _startTime The new conversion period start time.
     * @param _endTime The new conversion period end time.
     */
    function setConversionPeriod(uint256 _startTime, uint256 _endTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_startTime < _endTime, "TokenConversion: start time must be before end time");

        startTime = _startTime;
        endTime = _endTime;

        emit ConversionPeriodUpdated(_startTime, _endTime);
    }

    /**
     * @notice Checks if an account has the admin role.
     * @param account The address to check for admin role.
     */
    function isAdmin(address account) public view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    /**
     * @notice Checks if an account has the pauser role.
     * @param account The address to check for pauser role.
     */
    function isPauser(address account) public view returns (bool) {
        return hasRole(PAUSER_ROLE, account);
    }

    /**
     * @notice Checks if an account has the miner role.
     * @param account The address to check for miner role.
     */
    function isMiner(address account) public view returns (bool) {
        return hasRole(MINER_ROLE, account);
    }

    /**
     * @notice Pauses the contract.
     * @dev Only the contract pauser can call this function.
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
        emit ContractPaused(_msgSender());
    }

    /**
     * @notice Unpauses the contract.
     * @dev Only the contract pauser can call this function.
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
        emit ContractUnpaused(_msgSender());
    }
}
