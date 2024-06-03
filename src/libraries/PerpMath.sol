// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./math/MathHelpersLib.sol";
import "./math/FixedPointMathLib.sol";
import "./math/PRBMathUD60x18.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import "forge-std/console.sol";

library PerpMath {
    using FixedPointMathLib for uint256;

    // ---- ((p/(2**96))**2)*1e12
    function getPriceFromTick(int24 tick) internal view returns (uint256) {
        // console.log("> getPriceFromTick");
        uint256 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        // console.log("sqrtPriceX96", sqrtPriceX96);
        // return uint256(1e12).div((sqrtPriceX96 * sqrtPriceX96) >> (96 * 2));
        return (sqrtPriceX96.div(2 ** 96)).mul(sqrtPriceX96.div(2 ** 96));
    }

    // ---- Math.log(2*4486*1e-12)/Math.log(1.0001)
    // ---- (Math.log(2*4486*1e-12*1e18)-Math.log(1e18))/Math.log(1.0001)
    function getTickFromPrice(uint256 price) internal view returns (int24) {
        // console.log("> getTickFromPrice", price);
        // console.log(PRBMathUD60x18.ln(price * 1e18));
        // console.logInt(
        //     (
        //         (int256(PRBMathUD60x18.ln(price * 1e18)) -
        //             int256(41446531673892820000))
        //     ) / 99995000333297
        // );
        return
            MathHelpersLib.toInt24(
                (
                    (int256(PRBMathUD60x18.ln(price * 1e18)) -
                        int256(41446531673892820000))
                ) / 99995000333297
            );
    }

    function tickRoundDown(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        return compressed * tickSpacing;
    }

    function getAssetsBuyShares(
        uint256 borrowShares,
        uint256 totalBorrowShares,
        uint256 totalBorrowAssets
    ) internal pure returns (uint256) {
        return
            totalBorrowAssets == 0
                ? 0
                : (borrowShares * totalBorrowAssets) / totalBorrowShares;
    }
}
