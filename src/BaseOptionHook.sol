// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CurrencySettleTake} from "v4-core/libraries/CurrencySettleTake.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {OptionBaseLib} from "@src/libraries/OptionBaseLib.sol";

import {Position} from "v4-core/libraries/Position.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "@forks/BaseHook.sol";

import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IWETH} from "@forks/IWETH.sol";
import {IMorpho, Id} from "@forks/morpho/IMorpho.sol";
import {IOption} from "@src/interfaces/IOption.sol";
import {IHedgehogLoyaltyMock} from "@src/interfaces/IHedgehogLoyaltyMock.sol";

abstract contract BaseOptionHook is BaseHook, IOption {
    using CurrencySettleTake for Currency;

    IERC20 WSTETH = IERC20(OptionBaseLib.WSTETH);
    IWETH WETH = IWETH(OptionBaseLib.WETH);
    IERC20 USDC = IERC20(OptionBaseLib.USDC);
    IERC20 OSQTH = IERC20(OptionBaseLib.OSQTH);

    Id public immutable morphoMarketId;

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    IHedgehogLoyaltyMock public loyalty;

    uint256 public priceScalingFactor = 2;
    uint256 public cRatio = 2;
    uint256 public weight = 2;
    uint256 public performanceFee = 1e16;

    function setPriceScalingFactor(
        uint256 _priceScalingFactor
    ) external onlyHookDeployer {
        priceScalingFactor = _priceScalingFactor;
    }

    function setCRatio(uint256 _cRatio) external onlyHookDeployer {
        cRatio = _cRatio;
    }

    function setWeight(uint256 _weight) external onlyHookDeployer {
        weight = _weight;
    }

    function setPerformanceFee(
        uint256 _performanceFee
    ) external onlyHookDeployer {
        performanceFee = _performanceFee;
    }

    function getUserFee(address user) public view returns (uint256) {
        if (loyalty.isLoyal(user) == 0) return performanceFee;
        return 0;
    }

    mapping(PoolId => int24) lastTick;
    uint256 public optionIdCounter = 0;
    mapping(uint256 => OptionInfo) optionInfo;

    function getOptionInfo(
        uint256 optionId
    ) external view override returns (OptionInfo memory) {
        return optionInfo[optionId];
    }

    function getTickLast(PoolId poolId) public view override returns (int24) {
        return lastTick[poolId];
    }

    function setTickLast(PoolId poolId, int24 _tick) internal {
        lastTick[poolId] = _tick;
    }

    constructor(
        IPoolManager _poolManager,
        IHedgehogLoyaltyMock _loyalty
    ) BaseHook(_poolManager) {
        loyalty = _loyalty;
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

    function getCurrentTick(
        PoolId poolId
    ) public view override returns (int24) {
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, poolId);
        return currentTick;
    }

    function getOptionPosition(
        PoolKey memory key,
        uint256 optionId
    ) public view override returns (uint128, int24, int24) {
        OptionInfo memory info = optionInfo[optionId];

        Position.Info memory positionInfo = StateLibrary.getPosition(
            poolManager,
            PoolIdLibrary.toId(key),
            address(this),
            info.tickLower,
            info.tickUpper,
            bytes32(ZERO_BYTES)
        );
        return (positionInfo.liquidity, info.tickLower, info.tickUpper);
    }

    function unlockModifyPosition(
        PoolKey calldata key,
        int128 liquidity,
        int24 tickLower,
        int24 tickUpper
    ) external selfOnly returns (bytes memory) {
        console.log("> unlockModifyPosition");

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: bytes32(ZERO_BYTES)
            }),
            ZERO_BYTES
        );

        if (delta.amount0() < 0) {
            key.currency0.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount0())),
                false
            );
        }

        if (delta.amount0() > 0) {
            key.currency0.take(
                poolManager,
                address(this),
                uint256(uint128(delta.amount0())),
                false
            );
        }

        if (delta.amount1() < 0) {
            key.currency1.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount1())),
                false
            );
        }

        if (delta.amount1() > 0) {
            key.currency1.take(
                poolManager,
                address(this),
                uint256(uint128(delta.amount1())),
                false
            );
        }
        return ZERO_BYTES;
    }

    //TODO: remove in production
    function logBalances() internal view {
        console.log("> hook balances");
        if (WSTETH.balanceOf(address(this)) > 0)
            console.log("WSTETH", WSTETH.balanceOf(address(this)));
        if (OSQTH.balanceOf(address(this)) > 0)
            console.log("OSQTH ", OSQTH.balanceOf(address(this)));
        if (USDC.balanceOf(address(this)) > 0)
            console.log("USDC  ", USDC.balanceOf(address(this)));
        if (WETH.balanceOf(address(this)) > 0)
            console.log("WETH  ", WETH.balanceOf(address(this)));
    }

    // --- Morpho Wrappers ---

    function morphoBorrow(uint256 amount, uint256 shares) internal {
        morpho.borrow(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            shares,
            address(this),
            address(this)
        );
    }

    function morphoReplay(uint256 amount, uint256 shares) internal {
        morpho.repay(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            shares,
            address(this),
            ZERO_BYTES
        );
    }

    function morphoWithdrawCollateral(uint256 amount) internal {
        morpho.withdrawCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            address(this)
        );
    }

    function morphoSupplyCollateral(uint256 amount) internal {
        morpho.supplyCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            ZERO_BYTES
        );
    }

    function morphoSync() internal {
        morpho.accrueInterest(morpho.idToMarketParams(morphoMarketId));
    }
}
