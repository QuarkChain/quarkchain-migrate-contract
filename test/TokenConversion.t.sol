// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/TokenConversion.sol";
import "../src/mock/MockToken.sol";
import "../src/IOptimismPortal2.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Mock implementation of OptimismPortal2 for testing
contract MockOptimismPortal is IOptimismPortal2 {
    mapping(address => uint256) public mintedAmounts;
    mapping(address => uint256) public totalMinted;

    function mintTransaction(address _to, uint256 _value) external override {
        mintedAmounts[_to] = _value;
        totalMinted[_to] += _value;
    }

    function getMintedAmount(address _user) external view returns (uint256) {
        return mintedAmounts[_user];
    }

    function getTotalMinted(address _user) external view returns (uint256) {
        return totalMinted[_user];
    }
}

contract TokenConversionTest is Test {
    TokenConversion public tokenConversion;
    MockToken public erc20In;
    MockOptimismPortal public optimismPortal;

    address public admin = address(1);
    address public pauser = address(2);
    address public miner = address(3);
    address public user = address(4);

    uint256 public startTime;
    uint256 public endTime;

    function setUp() public {
        // Deploy mock token
        erc20In = new MockToken("Test Token", "TEST", true);

        // Deploy mock optimism portal
        optimismPortal = new MockOptimismPortal();

        // Set conversion period
        startTime = block.timestamp;
        endTime = block.timestamp + 7 days;

        // Deploy implementation contract
        TokenConversion implementation = new TokenConversion();

        // Encode the initialization data
        bytes memory initData = abi.encodeWithSelector(
            TokenConversion.initialize.selector,
            address(erc20In),
            address(optimismPortal),
            startTime,
            endTime,
            admin,
            pauser,
            miner
        );

        // Deploy proxy pointing to implementation
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(this), initData);

        // Cast proxy address to tokenConversion
        tokenConversion = TokenConversion(address(proxy));

        // Transfer some tokens to the test user
        vm.startPrank(address(this));
        erc20In.transfer(user, 1000 * 1e18);
        vm.stopPrank();
    }

    // ==================== Initialization Tests ====================

    function testInitialize() public view {
        assertEq(tokenConversion.erc20In(), address(erc20In));
        assertEq(tokenConversion.optimismPortal2(), address(optimismPortal));
        assertEq(tokenConversion.startTime(), startTime);
        assertEq(tokenConversion.endTime(), endTime);

        assertTrue(tokenConversion.isAdmin(admin));
        assertTrue(tokenConversion.isPauser(pauser));
        assertTrue(tokenConversion.isMiner(miner));
    }

    function testInitializeFailures() public {
        // For testing initialization failures, we need to deploy new proxies with different initialization parameters

        // Test with zero address for erc20In
        TokenConversion implementation = new TokenConversion();
        bytes memory initData = abi.encodeWithSelector(
            TokenConversion.initialize.selector,
            address(0), // erc20In = address(0)
            address(optimismPortal),
            startTime,
            endTime,
            admin,
            pauser,
            miner
        );

        vm.expectRevert("TokenConversion: invalid _erc20In token address");
        new TransparentUpgradeableProxy(address(implementation), address(this), initData);

        // Test with zero address for optimismPortal2
        implementation = new TokenConversion();
        initData = abi.encodeWithSelector(
            TokenConversion.initialize.selector,
            address(erc20In),
            address(0), // optimismPortal2 = address(0)
            startTime,
            endTime,
            admin,
            pauser,
            miner
        );

        vm.expectRevert("TokenConversion: invalid _optimismPortal2 address");
        new TransparentUpgradeableProxy(address(implementation), address(this), initData);

        // Test with invalid time period (start time after end time)
        implementation = new TokenConversion();
        initData = abi.encodeWithSelector(
            TokenConversion.initialize.selector,
            address(erc20In),
            address(optimismPortal),
            endTime, // startTime = endTime
            startTime, // endTime = startTime
            admin,
            pauser,
            miner
        );

        vm.expectRevert("TokenConversion: start time must be before end time");
        new TransparentUpgradeableProxy(address(implementation), address(this), initData);

        // Test with zero address for admin
        implementation = new TokenConversion();
        initData = abi.encodeWithSelector(
            TokenConversion.initialize.selector,
            address(erc20In),
            address(optimismPortal),
            startTime,
            endTime,
            address(0), // admin = address(0)
            pauser,
            miner
        );

        vm.expectRevert("TokenConversion: invalid admin address");
        new TransparentUpgradeableProxy(address(implementation), address(this), initData);

        // Test with zero address for pauser
        implementation = new TokenConversion();
        initData = abi.encodeWithSelector(
            TokenConversion.initialize.selector,
            address(erc20In),
            address(optimismPortal),
            startTime,
            endTime,
            admin,
            address(0), // pauser = address(0)
            miner
        );

        vm.expectRevert("TokenConversion: invalid pauser address");
        new TransparentUpgradeableProxy(address(implementation), address(this), initData);
    }

    // ==================== Convert Function Tests ====================

    function testConvert() public {
        uint256 convertAmount = 100 * 1e18;

        // Set up user to call convert
        vm.startPrank(user);

        // Approve the token conversion contract to spend user's tokens
        erc20In.approve(address(tokenConversion), convertAmount);

        // Initial balances
        uint256 initialUserBalance = erc20In.balanceOf(user);
        uint256 initialContractBalance = erc20In.balanceOf(address(tokenConversion));

        // Call convert
        tokenConversion.convert(convertAmount);

        // Final balances
        uint256 finalUserBalance = erc20In.balanceOf(user);
        uint256 finalContractBalance = erc20In.balanceOf(address(tokenConversion));

        // Verify balances changed correctly
        assertEq(initialUserBalance - finalUserBalance, convertAmount);
        assertEq(finalContractBalance - initialContractBalance, convertAmount);

        // Verify L2 tokens were minted to the user
        assertEq(optimismPortal.getMintedAmount(user), convertAmount);

        vm.stopPrank();
    }

    function testConvertFailsBeforePeriod() public {
        uint256 convertAmount = 100 * 1e18;

        // Create a new contract with a future start time
        TokenConversion implementation = new TokenConversion();
        bytes memory initData = abi.encodeWithSelector(
            TokenConversion.initialize.selector,
            address(erc20In),
            address(optimismPortal),
            block.timestamp + 1 days, // Start time is in the future
            block.timestamp + 7 days,
            admin,
            pauser,
            miner
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(this), initData);

        TokenConversion newConversion = TokenConversion(address(proxy));

        // Try to convert (should fail because period hasn't started)
        vm.startPrank(user);
        erc20In.approve(address(newConversion), convertAmount);

        vm.expectRevert("TokenConversion: conversion period has not started");
        newConversion.convert(convertAmount);

        vm.stopPrank();
    }

    function testConvertFailsAfterPeriod() public {
        uint256 convertAmount = 100 * 1e18;

        // Warp time to after the conversion period
        vm.warp(endTime + 1);

        // Try to convert (should fail because period has ended)
        vm.startPrank(user);
        erc20In.approve(address(tokenConversion), convertAmount);

        vm.expectRevert("TokenConversion: conversion period has ended");
        tokenConversion.convert(convertAmount);

        vm.stopPrank();
    }

    function testConvertFailsWhenPaused() public {
        uint256 convertAmount = 100 * 1e18;

        // Pause the contract
        vm.prank(pauser);
        tokenConversion.pause();

        // Try to convert (should fail because contract is paused)
        vm.startPrank(user);
        erc20In.approve(address(tokenConversion), convertAmount);

        // Updated to match the actual error from the contract
        // OpenZeppelin's PausableUpgradeable contract throws a custom error called EnforcedPause()
        vm.expectRevert("EnforcedPause()");
        tokenConversion.convert(convertAmount);

        vm.stopPrank();
    }

    function testConvertFailsWithInsufficientBalance() public {
        uint256 convertAmount = 2000 * 1e18; // More than user has

        // Try to convert (should fail because user doesn't have enough tokens)
        vm.startPrank(user);
        erc20In.approve(address(tokenConversion), convertAmount);

        vm.expectRevert("TokenConversion: not enough tokens");
        tokenConversion.convert(convertAmount);

        vm.stopPrank();
    }

    function testConvertFailsWithInsufficientAllowance() public {
        uint256 convertAmount = 500 * 1e18;
        uint256 lowerAllowance = 100 * 1e18; // Less than convert amount

        // Try to convert (should fail because allowance is too low)
        vm.startPrank(user);
        erc20In.approve(address(tokenConversion), lowerAllowance);

        vm.expectRevert("TokenConversion: insufficient allowance");
        tokenConversion.convert(convertAmount);

        vm.stopPrank();
    }

    // ==================== Role-Based Function Tests ====================

    function testMintL2Tokens() public {
        uint256 mintAmount = 500 * 1e18;

        // Test that only miner role can call mintL2Tokens
        vm.startPrank(miner);
        tokenConversion.mintL2Tokens(user, mintAmount);
        vm.stopPrank();

        // Verify L2 tokens were minted
        assertEq(optimismPortal.getMintedAmount(user), mintAmount);

        // Test that non-miner cannot call mintL2Tokens
        vm.startPrank(user);
        vm.expectRevert();
        tokenConversion.mintL2Tokens(user, mintAmount);
        vm.stopPrank();
    }

    function testDrain() public {
        uint256 convertAmount = 100 * 1e18;

        // First perform a conversion to have tokens in the contract
        vm.startPrank(user);
        erc20In.approve(address(tokenConversion), convertAmount);
        tokenConversion.convert(convertAmount);
        vm.stopPrank();

        // Verify contract balance
        uint256 contractBalance = erc20In.balanceOf(address(tokenConversion));
        assertEq(contractBalance, convertAmount);

        // Test that only admin role can call drain
        uint256 initialAdminBalance = erc20In.balanceOf(admin);

        vm.startPrank(admin);
        tokenConversion.drain();
        vm.stopPrank();

        // Verify tokens were transferred to admin
        uint256 finalAdminBalance = erc20In.balanceOf(admin);
        assertEq(finalAdminBalance - initialAdminBalance, convertAmount);
        assertEq(erc20In.balanceOf(address(tokenConversion)), 0);

        // Test that non-admin cannot call drain
        vm.startPrank(user);
        vm.expectRevert();
        tokenConversion.drain();
        vm.stopPrank();
    }

    function testSetConversionPeriod() public {
        uint256 newStartTime = block.timestamp + 1 days;
        uint256 newEndTime = block.timestamp + 14 days;

        // Test that only admin role can call setConversionPeriod
        vm.startPrank(admin);
        tokenConversion.setConversionPeriod(newStartTime, newEndTime);
        vm.stopPrank();

        // Verify period was updated
        assertEq(tokenConversion.startTime(), newStartTime);
        assertEq(tokenConversion.endTime(), newEndTime);

        // Test that non-admin cannot call setConversionPeriod
        vm.startPrank(user);
        vm.expectRevert();
        tokenConversion.setConversionPeriod(newStartTime, newEndTime);
        vm.stopPrank();

        // Test invalid period (start time after end time)
        vm.startPrank(admin);
        vm.expectRevert("TokenConversion: start time must be before end time");
        tokenConversion.setConversionPeriod(newEndTime, newStartTime);
        vm.stopPrank();
    }

    function testPauseUnpause() public {
        // Test that only pauser role can call pause/unpause
        vm.startPrank(pauser);
        tokenConversion.pause();
        vm.stopPrank();

        assertTrue(tokenConversion.paused());

        // Test that non-pauser cannot call pause
        vm.startPrank(user);
        vm.expectRevert();
        tokenConversion.pause();
        vm.stopPrank();

        // Test unpause
        vm.startPrank(pauser);
        tokenConversion.unpause();
        vm.stopPrank();

        assertFalse(tokenConversion.paused());

        // Test that non-pauser cannot call unpause
        vm.startPrank(user);
        vm.expectRevert();
        tokenConversion.unpause();
        vm.stopPrank();
    }
}
