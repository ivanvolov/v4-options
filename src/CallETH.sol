// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id, Market} from "morpho-blue/interfaces/IMorpho.sol";

import {CurrencySettleTake} from "v4-core/libraries/CurrencySettleTake.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
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

    bytes internal constant ZERO_BYTES = bytes("");

    Id public immutable marketId;

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

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
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        console.log("> afterInitialize");
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(
            address(morpho),
            type(uint256).max
        );

        return CallETH.afterInitialize.selector;
    }

    function getTick(PoolKey calldata key) public view returns (int24) {
        (, int24 currentTick, , ) = StateLibrary.getSlot0(
            poolManager,
            key.toId()
        );
        return currentTick;
    }

    // Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function deposit(
        PoolKey calldata key,
        uint256 amount
    ) external returns (int24 tickLower, int24 tickUpper) {
        if (amount == 0) revert ZeroLiquidity();
        IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        console.log("wstETH balance %s", IERC20Minimal(Currency.unwrap(key.currency0)).balanceOf(address(this)));
        console.log("!");
        tickLower = getTick(key);
        tickUpper = PerpMath.getNearestValidTick(
            PerpMath.getTickFromPrice(PerpMath.getPriceFromTick(tickLower) / 2),
            key.tickSpacing
        );
        console.log("tickUpper %s", uint256(int256(tickUpper)));
        console.log("tickLower %s", uint256(int256(tickLower)));
        console.log("!");

        poolManager.unlock(
            abi.encodeCall(
                this.unlockDepositPlace,
                (key, amount / 2, tickLower, tickUpper)
            )
        );

        // console.log(
        //     IERC20Minimal(Currency.unwrap(key.currency1)).balanceOf(
        //         address(this)
        //     )
        // );
        // morpho.supplyCollateral(
        //     morpho.idToMarketParams(marketId),
        //     IERC20Minimal(Currency.unwrap(key.currency1)).balanceOf(
        //         address(this)
        //     ),
        //     address(this),
        //     ""
        // );
    }

    function unlockDepositPlace(
        PoolKey calldata key,
        uint256 amount,
        int24 tickLower,
        int24 tickUpper
    ) external selfOnly returns (bytes memory) {
        console.log("> unlockDepositPlace");

        console.log(amount);
        console.logInt(tickLower);
        console.logInt(tickUpper);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                        TickMath.getSqrtPriceAtTick(tickUpper), 
                        TickMath.getSqrtPriceAtTick(tickLower), 
                        amount
                        );
        console.log("liquidity %s", uint256(liquidity));
   
        int24 currentTick = getTick(key);
        console.log("currentTick %s", uint256(int256(currentTick)));

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(TickMath.getSqrtPriceAtTick(currentTick), TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidity);
        console.log("amount0 %s, amount1 %s", amount0, amount1);
        
        console.log(Currency.unwrap(key.currency0));

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
        
        console.log("> delta");
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());


        if (delta.amount0() < 0) {
            //if(delta.amount0() != 0) revert InRange();

            key.currency0.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount0())),
                false
            );
        }

        if (delta.amount1() < 0) {
            //if(delta.amount1() != 0) revert InRange();

            key.currency1.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount1())),
                false
            );
        }
    }
}
