// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ISwapRouter} from "@forks/ISwapRouter.sol";
import {IUniswapV3Pool} from "@forks/IUniswapV3Pool.sol";
import {OptionMathLib} from "@src/libraries/OptionMathLib.sol";

library OptionBaseLib {
    error UnsupportedTokenPair();

    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant OSQTH = 0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B;

    // ---- Uniswap V3 Swap related functions ----

    uint24 public constant WSTETH_USDC_POOL_FEE = 500;
    uint24 public constant WSTETH_ETH_POOL_FEE = 100;
    uint24 public constant ETH_OSQTH_POOL_FEE = 3000;
    uint24 public constant ETH_USDC_POOL_FEE = 500;

    function getFee(
        address tokenIn,
        address tokenOut
    ) internal pure returns (uint24) {
        (address token0, address token1) = tokenIn >= tokenOut
            ? (tokenIn, tokenOut)
            : (tokenOut, tokenIn);

        if (token0 == USDC && token1 == WSTETH) return WSTETH_USDC_POOL_FEE;
        if (token0 == WETH && token1 == WSTETH) return WSTETH_ETH_POOL_FEE;
        if (token0 == OSQTH && token1 == WETH) return ETH_OSQTH_POOL_FEE;
        if (token0 == WETH && token1 == USDC) return ETH_USDC_POOL_FEE;

        revert UnsupportedTokenPair();
    }

    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter constant swapRouter = ISwapRouter(SWAP_ROUTER);

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        return
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: getFee(tokenIn, tokenOut),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal returns (uint256) {
        return
            swapRouter.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: getFee(tokenIn, tokenOut),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountInMaximum: type(uint256).max,
                    amountOut: amountOut,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    function getV3PoolPrice(address pool) external view returns (uint256) {
        (, int24 tick, , , , , ) = IUniswapV3Pool(pool).slot0();
        return OptionMathLib.getPriceFromTick(tick);
    }

    //** MultiRouteSwaps
    /// @notice Part of this routes will change after setting up new pools like wstETH/OSQTH or USDC/OSQTH

    function swapExactOutputPath(
        bytes memory path,
        uint256 amountOut
    ) internal returns (uint256) {
        return
            swapRouter.exactOutput(
                ISwapRouter.ExactOutputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: type(uint256).max
                })
            );
    }

    function swapOSQTH_USDC_In(uint256 amountIn) internal returns (uint256) {
        return
            swapExactInput(WETH, USDC, swapExactInput(OSQTH, WETH, amountIn));
    }

    function swapUSDC_OSQTH_In(uint256 amountIn) internal returns (uint256) {
        return
            swapExactInput(WETH, OSQTH, swapExactInput(USDC, WETH, amountIn));
    }

    function swapOSQTH_WSTETH_In(uint256 amountIn) internal returns (uint256) {
        return
            swapExactInput(WETH, WSTETH, swapExactInput(OSQTH, WETH, amountIn));
    }

    function swapOSQTH_USDC_Out(uint256 amountOut) internal returns (uint256) {
        return
            swapExactOutputPath(
                abi.encodePacked(
                    USDC,
                    ETH_USDC_POOL_FEE,
                    WETH,
                    ETH_OSQTH_POOL_FEE,
                    OSQTH
                ),
                amountOut
            );
    }

    function swapUSDC_OSQTH_Out(uint256 amountOut) internal returns (uint256) {
        return
            swapExactOutputPath(
                abi.encodePacked(
                    OSQTH,
                    ETH_OSQTH_POOL_FEE,
                    WETH,
                    ETH_USDC_POOL_FEE,
                    USDC
                ),
                amountOut
            );
    }
}
