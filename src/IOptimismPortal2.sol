// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IOptimismPortal2 {
    /// @notice Mint a specific amount of L2 native token to an address.
    function mintTransaction(address _to, uint256 _value) external;
}
