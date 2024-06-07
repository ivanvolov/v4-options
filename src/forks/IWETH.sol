// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

interface IWETH is IERC20Minimal {
    function withdraw(uint256 wad) external;

    function deposit() external payable;
}
