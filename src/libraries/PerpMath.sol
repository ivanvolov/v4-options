import "./math/MathHelpersLib.sol";
import "./math/FixedPointMathLib.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

library PerpMath {
    using FixedPointMathLib for uint256;

    function getLiquidityFromValue(
        uint256 v,
        uint256 p,
        int24 tickLower,
        int24 tickUpper
    ) public pure returns (uint128) {
        return
            getLiquidityForValue(
                v,
                p,
                uint256(1e12).div(getPriceFromTick(tickLower)),
                uint256(1e12).div(getPriceFromTick(tickUpper))
            );
    }

    function getLiquidityForValue(
        uint256 v,
        uint256 p,
        uint256 pH,
        uint256 pL
    ) public pure returns (uint128) {
        return
            MathHelpersLib.toUint128(
                (v * 1e3) / ((p.sqrt()) * 2 - pL.sqrt() - p / (pH.sqrt()))
            );
    }

    function getPriceFromTick(int24 tick) public pure returns (uint256) {
        uint256 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        return (sqrtPriceX96 * sqrtPriceX96) >> (96 * 2);
    }
}
