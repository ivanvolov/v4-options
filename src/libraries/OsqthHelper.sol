// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TickMath} from "v4-core/libraries/TickMath.sol";

import {IController} from "squeeth-monorepo/interfaces/IController.sol";

import "forge-std/console.sol";

library OsqthHelper {
    IController public powerTokenController;
}
