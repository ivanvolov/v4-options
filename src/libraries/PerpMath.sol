// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./math/MathHelpersLib.sol";
import "./math/FixedPointMathLib.sol";
import "./math/PRBMathUD60x18.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import "forge-std/console.sol";

library PerpMath {
    using FixedPointMathLib for uint256;

    // ((p/(2**96))**2)*1e12
    // math.log(4487*1e-12)/math.log(1.0001)
    function getPriceFromTick(int24 tick) internal view returns (uint256) {
        // console.log("> getPriceFromTick");
        uint256 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        // console.log("sqrtPriceX96", sqrtPriceX96);
        // uint256 sqrtPrice = sqrtPriceX96/
        // console.log(sqrtPriceX96 * sqrtPriceX96);
        // console.log(
        //     (sqrtPriceX96.div(2 ** 96)).mul(sqrtPriceX96.div(2 ** 96)) * 1e12
        // );
        // console.log((sqrtPriceX96.div(2 ** 96) * sqrtPriceX96) / 2 ** 96);
        // console.log((sqrtPriceX96 * sqrtPriceX96) / 2 ** 192);
        // return uint256(1e12).div((sqrtPriceX96 * sqrtPriceX96) >> (96 * 2));
        return
            (sqrtPriceX96.div(2 ** 96)).mul(sqrtPriceX96.div(2 ** 96)) * 1e12;
    }

    function getNearestValidTick(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        int24 flooredTick = (tick / tickSpacing) * tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) {
            flooredTick -= tickSpacing;
        }
        return flooredTick;
    }

    function getTickLower(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        return compressed * tickSpacing;
    }

    function getTickFromPrice(
        uint256 priceZeroForOne
    ) internal pure returns (int24) {
        return
            MathHelpersLib.toInt24(
                int256(
                    PRBMathUD60x18.ln(uint256(1e30).div(priceZeroForOne)).div(
                        99995000333297 * 1e18
                    )
                )
            );
    }

    function getTickFromPriceV2(uint256 price) internal view returns (int24) {
        console.log("price", price);
        uint256 priceZeroForOne = price.sqrt();
        console.log("priceZeroForOne", priceZeroForOne);
        return
            MathHelpersLib.toInt24(
                int256(PRBMathUD60x18.ln(price).div(99995000333297 * 1e18))
            );
    }
}
