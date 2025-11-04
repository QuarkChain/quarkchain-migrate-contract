// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name_, string memory symbol_, bool _initialMint) ERC20(name_, symbol_) {
        if (_initialMint) {
            _mint(msg.sender, 10000_000_000 * 1e18);
        }
    }

    function mint() public {
        _mint(msg.sender, 1000 * 10 ** 18);
    }
}
