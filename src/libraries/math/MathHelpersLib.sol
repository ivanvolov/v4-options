// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * Error
 * MH1: Value is out of range for Int24 conversion.
 * MH2: Value is out of range for Uint128 conversion.
 * MH3: Value is out of range for Uint160 conversion.
 **/

library MathHelpersLib {
    /// @dev Rounds tick down towards negative infinity so that it's a multiple
    /// of `tickSpacing`.
    function floor(
        int24 tick,
        int24 tickSpacing
    ) external pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--;
        return compressed * tickSpacing;
    }

    //? Math functions

    function min(uint256 a, uint256 b) external pure returns (uint256) {
        return a < b ? a : b;
    }

    function absDifference(
        uint256 a,
        uint256 b
    ) external pure returns (uint256) {
        if (a > b) {
            return a - b;
        }
        return b - a;
    }

    //? Type casting functions
    function toInt24(int256 value) external pure returns (int24) {
        require(value >= type(int24).min && value <= type(int24).max, "MH1");
        return int24(value);
    }

    function toUint128(uint256 x) external pure returns (uint128) {
        require(x <= type(uint128).max, "MH2");
        return uint128(x);
    }

    function toUint160(uint256 x) external pure returns (uint160) {
        require(x <= type(uint160).max, "MH3");
        return uint160(x);
    }
}
