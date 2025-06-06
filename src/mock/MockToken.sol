// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract MockToken is MockERC20 {
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) MockERC20(_name, _symbol, 18) {
        _mint(msg.sender, _initialSupply);
    }
}
