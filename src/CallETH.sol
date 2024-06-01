// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id, Market} from "morpho-blue/interfaces/IMorpho.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

import {CurrencySettleTake} from "v4-core/libraries/CurrencySettleTake.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {BaseHook} from "./forks/BaseHook.sol";
import {PerpMath} from "./libraries/PerpMath.sol";

import "forge-std/console.sol";

contract CallETH is BaseHook {
    using CurrencySettleTake for Currency;
    using PoolIdLibrary for PoolKey;

    error ZeroLiquidity();

    error AddLiquidityThroughHook();

    error InRange();

    IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 oSQTH = IERC20(0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B);

    bytes internal constant ZERO_BYTES = bytes("");

    Id public immutable marketId;

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    mapping(PoolId => int24) public lastTick;

    function getTickLast(PoolId poolId) public view returns (int24) {
        return lastTick[poolId];
    }

    function setTickLast(PoolId poolId, int24 _tick) private {
        lastTick[poolId] = _tick;
    }

    constructor(IPoolManager poolManager, Id _marketId) BaseHook(poolManager) {
        marketId = _marketId;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick,
        bytes calldata
    ) external override returns (bytes4) {
        console.log("> afterInitialize");
        USDC.approve(address(swapRouter), type(uint256).max);
        wstETH.approve(address(swapRouter), type(uint256).max);
        oSQTH.approve(address(swapRouter), type(uint256).max);
        WETH.approve(address(swapRouter), type(uint256).max);
        IERC20(Currency.unwrap(key.currency0)).approve(
            address(morpho),
            type(uint256).max
        );
        setTickLast(key.toId(), tick);

        return CallETH.afterInitialize.selector;
    }

    // Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function deposit(
        PoolKey calldata key,
        uint256 amount
    ) external returns (int24 tickLower, int24 tickUpper) {
        console.log(">> deposit");
        if (amount == 0) revert ZeroLiquidity();
        IERC20(Currency.unwrap(key.currency0)).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        tickLower = getCurrentTick(key.toId());
        // console.log("Price from tick %s", PerpMath.getPriceFromTick(tickLower));
        tickUpper = PerpMath.tickRoundDown(
            PerpMath.getTickFromPrice(PerpMath.getPriceFromTick(tickLower) * 2),
            key.tickSpacing
        );
        // console.logInt(tickUpper);
        // tickUpper = -185296;
        console.log("> Ticks, lower/upper");
        console.logInt(tickLower);
        console.logInt(tickUpper);

        poolManager.unlock(
            abi.encodeCall(
                this.unlockDepositPlace,
                (key, amount / 2, tickLower, tickUpper)
            )
        );

        morpho.supplyCollateral(
            morpho.idToMarketParams(marketId),
            IERC20(Currency.unwrap(key.currency0)).balanceOf(address(this)),
            address(this),
            ""
        );
    }

    function unlockDepositPlace(
        PoolKey calldata key,
        uint256 amount,
        int24 tickLower,
        int24 tickUpper
    ) external selfOnly returns (bytes memory) {
        console.log(">> unlockDepositPlace");
        // console.log(amount);
        // console.logInt(tickLower);
        // console.logInt(tickUpper);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
            TickMath.getSqrtPriceAtTick(tickUpper),
            TickMath.getSqrtPriceAtTick(tickLower),
            amount
        );
        // console.log("liquidity %s", uint256(liquidity));

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int128(liquidity),
                salt: ""
            }),
            ZERO_BYTES
        );

        // console.log("> delta");
        // console.logInt(delta.amount0());
        // console.logInt(delta.amount1());

        if (delta.amount0() < 0) {
            if (delta.amount1() != 0) revert InRange();

            key.currency0.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount0())),
                false
            );
        }

        if (delta.amount1() < 0) {
            if (delta.amount0() != 0) revert InRange();

            key.currency1.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount1())),
                false
            );
        }
        return bytes("");
    }

    ISwapRouter immutable swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public constant poolWethUsdc =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant poolUsdcOSQTH =
        0x82c427AdFDf2d245Ec51D8046b41c4ee87F0d29C;

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta deltas,
        bytes calldata
    ) external virtual override returns (bytes4, int128) {
        console.log(">> afterSwap");

        int24 tick = getCurrentTick(key.toId());

        if (tick > getTickLast(key.toId())) {
            // console.log(">> price go up...");
            // console.logInt(deltas.amount0());
            // console.logInt(deltas.amount1());

            morpho.borrow(
                morpho.idToMarketParams(marketId),
                uint256(int256(-deltas.amount1())),
                0,
                address(this),
                address(this)
            );

            uint256 amountOut = swapUSDC_WETH(
                uint256(int256(-deltas.amount1()))
            );
            swapWETH_OSQTH(amountOut);
        } else if (tick < getTickLast(key.toId())) {
            // console.log(">> price go down...");
        }

        // (int24 tickLower, int24 lower, int24 upper) = _getCrossedTicks(
        //     key.toId(),
        //     key.tickSpacing
        // );
        // console.logInt(tickLower);
        // console.logInt(lower);
        // console.logInt(upper);
        // // if (lower > upper) return (LimitOrder.afterSwap.selector, 0);

        setTickLast(key.toId(), tick);
        return (CallETH.afterSwap.selector, 0);
    }

    // --- Helpers ---

    function swapWETH_OSQTH(uint256 amount) internal returns (uint256) {
        // WETH -> oSQTH
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(oSQTH),
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params);
    }

    function swapUSDC_WETH(uint256 amount) internal returns (uint256) {
        // USDC -> WETH
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(USDC),
                tokenOut: address(WETH),
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params);
    }

    function getCurrentTick(PoolId poolId) public view returns (int24) {
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, poolId);
        return currentTick;
    }
}
