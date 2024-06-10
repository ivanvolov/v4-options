// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {OptionMathLib} from "@src/libraries/OptionMathLib.sol";
import {OptionBaseLib} from "@src/libraries/OptionBaseLib.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {BaseOptionHook} from "@src/BaseOptionHook.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {IHedgehogLoyaltyMock} from "@src/interfaces/IHedgehogLoyaltyMock.sol";

/// @title Call like wstETH option
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract CallETH is BaseOptionHook, ERC721 {
    using PoolIdLibrary for PoolKey;

    constructor(
        IPoolManager poolManager,
        Id _morphoMarketId,
        IHedgehogLoyaltyMock _loyalty
    ) BaseOptionHook(poolManager, _loyalty) ERC721("CallETH", "CALL") {
        morphoMarketId = _morphoMarketId;
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick,
        bytes calldata
    ) external override returns (bytes4) {
        console.log(">> afterInitialize");

        USDC.approve(OptionBaseLib.SWAP_ROUTER, type(uint256).max);
        WETH.approve(OptionBaseLib.SWAP_ROUTER, type(uint256).max);
        WSTETH.approve(OptionBaseLib.SWAP_ROUTER, type(uint256).max);
        OSQTH.approve(OptionBaseLib.SWAP_ROUTER, type(uint256).max);

        WSTETH.approve(address(morpho), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);

        setTickLast(key.toId(), tick);

        return CallETH.afterInitialize.selector;
    }

    /// @notice  Disable adding liquidity through the PM
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
        uint256 amount,
        address to
    ) external override returns (uint256 optionId) {
        console.log(">> deposit");
        if (amount == 0) revert ZeroLiquidity();
        WSTETH.transferFrom(msg.sender, address(this), amount);

        int24 tickLower;
        int24 tickUpper;
        {
            tickLower = getCurrentTick(key.toId());
            tickUpper = OptionMathLib.tickRoundDown(
                OptionMathLib.getTickFromPrice(
                    OptionMathLib.getPriceFromTick(tickLower) *
                        priceScalingFactor
                ),
                key.tickSpacing
            );
            console.log("Ticks, lower/upper:");
            console.logInt(tickLower);
            console.logInt(tickUpper);

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(tickUpper),
                TickMath.getSqrtPriceAtTick(tickLower),
                amount / weight
            );

            poolManager.unlock(
                abi.encodeCall(
                    this.unlockModifyPosition,
                    (key, int128(liquidity), tickLower, tickUpper)
                )
            );
        }

        morphoSupplyCollateral(WSTETH.balanceOf(address(this)));
        optionId = optionIdCounter;

        optionInfo[optionId] = OptionInfo({
            amount: amount,
            tick: getCurrentTick(key.toId()),
            tickLower: tickLower,
            tickUpper: tickUpper,
            created: block.timestamp,
            fee: getUserFee(msg.sender)
        });

        _mint(to, optionId);
        optionIdCounter++;
    }

    function withdraw(
        PoolKey calldata key,
        uint256 optionId,
        address to
    ) external override {
        console.log(">> withdraw");
        if (ownerOf(optionId) != msg.sender) revert NotAnOptionOwner();

        //** swap all OSQTH in WSTETH
        uint256 balanceOSQTH = OSQTH.balanceOf(address(this));
        if (balanceOSQTH != 0) {
            OptionBaseLib.swapOSQTH_WSTETH_In(uint256(int256(balanceOSQTH)));
        }

        //** close position into WSTETH & USDC
        {
            (
                uint128 liquidity,
                int24 tickLower,
                int24 tickUpper
            ) = getOptionPosition(key, optionId);

            poolManager.unlock(
                abi.encodeCall(
                    this.unlockModifyPosition,
                    (key, -int128(liquidity), tickLower, tickUpper)
                )
            );
        }

        //** if USDC is borrowed buy extra and close the position
        morphoSync();
        Market memory m = morpho.market(morphoMarketId);
        uint256 usdcToRepay = m.totalBorrowAssets;
        MorphoPosition memory p = morpho.position(
            morphoMarketId,
            address(this)
        );

        if (usdcToRepay != 0) {
            uint256 balanceUSDC = USDC.balanceOf(address(this));
            if (usdcToRepay > balanceUSDC) {
                OptionBaseLib.swapExactOutput(
                    address(WSTETH),
                    address(USDC),
                    usdcToRepay - balanceUSDC
                );
            } else {
                OptionBaseLib.swapExactOutput(
                    address(USDC),
                    address(WSTETH),
                    balanceUSDC
                );
            }

            morphoReplay(0, p.borrowShares);
        }

        morphoWithdrawCollateral(p.collateral);
        WSTETH.transfer(to, WSTETH.balanceOf(address(this)));

        delete optionInfo[optionId];
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta deltas,
        bytes calldata
    ) external virtual override returns (bytes4, int128) {
        console.log(">> afterSwap");
        if (deltas.amount0() == 0 && deltas.amount1() == 0)
            revert NoSwapWillOccur();

        int24 tick = getCurrentTick(key.toId());

        if (tick > getTickLast(key.toId())) {
            console.log("> price go up...");

            morphoBorrow(uint256(int256(-deltas.amount1())), 0);
            OptionBaseLib.swapUSDC_OSQTH_In(uint256(int256(-deltas.amount1())));
        } else if (tick < getTickLast(key.toId())) {
            console.log("> price go down...");

            MorphoPosition memory p = morpho.position(
                morphoMarketId,
                address(this)
            );
            if (p.borrowShares != 0) {
                OptionBaseLib.swapOSQTH_USDC_Out(
                    uint256(int256(deltas.amount1()))
                );

                morphoReplay(uint256(int256(deltas.amount1())), 0);
            }
        } else {
            console.log("> price not changing...");
        }

        setTickLast(key.toId(), tick);
        return (CallETH.afterSwap.selector, 0);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}
