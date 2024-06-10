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
import {IController, Vault} from "@forks/squeeth-monorepo/IController.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {IHedgehogLoyaltyMock} from "@src/interfaces/IHedgehogLoyaltyMock.sol";

/// @title Put like wstETH option
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract PutETH is BaseOptionHook, ERC721 {
    using PoolIdLibrary for PoolKey;

    IController constant powerTokenController =
        IController(0x64187ae08781B09368e6253F9E94951243A493D5);

    uint256 public powerTokenVaultId;

    constructor(
        IPoolManager poolManager,
        Id _morphoMarketId,
        IHedgehogLoyaltyMock _loyalty
    ) BaseOptionHook(poolManager, _loyalty) ERC721("PutETH", "PUT") {
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

        powerTokenVaultId = powerTokenController.mintWPowerPerpAmount(0, 0, 0);

        setTickLast(key.toId(), tick);

        return PutETH.afterInitialize.selector;
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
        USDC.transferFrom(msg.sender, address(this), amount);

        int24 tickLower;
        int24 tickUpper;
        {
            tickUpper = getCurrentTick(key.toId());
            tickLower = OptionMathLib.tickRoundDown(
                OptionMathLib.getTickFromPrice(
                    OptionMathLib.getPriceFromTick(tickUpper) /
                        priceScalingFactor
                ),
                key.tickSpacing
            );
            console.log("Ticks, lower/upper");
            console.logInt(tickLower);
            console.logInt(tickUpper);

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
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

        morphoSupplyCollateral(USDC.balanceOf(address(this)));
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

        logBalances();
        //** close uniswap position into WSTETH & USDC
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
        logBalances();

        uint256 wstETHToRepay;
        uint256 usdcToObtain;
        uint256 osqthToRepay;
        uint256 ethToObtain;
        {
            morphoSync();
            Market memory m = morpho.market(morphoMarketId);
            wstETHToRepay = m.totalBorrowAssets;
            MorphoPosition memory p = morpho.position(
                morphoMarketId,
                address(this)
            );
            usdcToObtain = p.collateral;
            Vault memory vault = powerTokenController.vaults(powerTokenVaultId);
            osqthToRepay = vault.shortAmount;
            ethToObtain = vault.collateralAmount;
        }

        if (wstETHToRepay == 0) {
            morphoWithdrawCollateral(usdcToObtain);
            USDC.transfer(to, USDC.balanceOf(address(this)));
            return;
        }

        // ** make all amounts ready to repay, now we have WSTETH and USDC
        {
            // ** SWAP extra WSTETH to WETH
            if (WSTETH.balanceOf(address(this)) > wstETHToRepay) {
                OptionBaseLib.swapExactInput(
                    address(WSTETH),
                    address(USDC),
                    WSTETH.balanceOf(address(this)) - wstETHToRepay
                );
            } else {
                OptionBaseLib.swapExactOutput(
                    address(USDC),
                    address(WSTETH),
                    wstETHToRepay - WSTETH.balanceOf(address(this))
                );
            }

            // ** No we have exact WSTETH, and some USDC
            OptionBaseLib.swapUSDC_OSQTH_Out(osqthToRepay);
            // ** No we have exact WSTETH, exact OSQTH and some USDC
        }

        // ** No we have exact WSTETH, exact OSQTH and some USDC
        logBalances();

        // ** close OSQTH
        {
            powerTokenController.burnWPowerPerpAmount(
                powerTokenVaultId,
                osqthToRepay,
                ethToObtain
            );

            WETH.deposit{value: ethToObtain}();

            OptionBaseLib.swapExactInput(
                address(WETH),
                address(USDC),
                ethToObtain
            );
        }

        // ** No we have exact WSTETH, and some USDC
        logBalances();

        // ** close morpho
        {
            morphoReplay(wstETHToRepay, 0);

            logBalances();
            morphoWithdrawCollateral(usdcToObtain);
        }
        // ** No we have USDC only

        logBalances();
        USDC.transfer(to, USDC.balanceOf(address(this)));
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
            console.log(">> price go up...");

            OptionBaseLib.swapUSDC_OSQTH_In(uint256(int256(-deltas.amount1())));

            Vault memory vault = powerTokenController.vaults(powerTokenVaultId);

            uint256 collateralToWithdraw = OptionMathLib.getAssetsBuyShares(
                OSQTH.balanceOf(address(this)),
                vault.shortAmount,
                vault.collateralAmount
            );

            powerTokenController.burnWPowerPerpAmount(
                powerTokenVaultId,
                OSQTH.balanceOf(address(this)),
                collateralToWithdraw
            );

            WETH.deposit{value: collateralToWithdraw}();

            uint256 amountOut = OptionBaseLib.swapExactInput(
                address(WETH),
                address(WSTETH),
                collateralToWithdraw
            );

            morphoReplay(amountOut, 0);
        } else if (tick < getTickLast(key.toId())) {
            console.log(">> price go down...");
            morphoBorrow(uint256(int256(-deltas.amount0())), 0);
            uint256 wethAmountOut = OptionBaseLib.swapExactInput(
                address(WSTETH),
                address(WETH),
                uint256(int256(-deltas.amount0()))
            );
            WETH.withdraw(wethAmountOut);
            powerTokenController.deposit{value: wethAmountOut}(
                powerTokenVaultId
            );
            powerTokenController.mintPowerPerpAmount(
                powerTokenVaultId,
                wethAmountOut / cRatio,
                0
            );
            OptionBaseLib.swapOSQTH_USDC_In(OSQTH.balanceOf(address(this)));
        } else {
            console.log("> price not changing...");
        }

        setTickLast(key.toId(), tick);
        return (PutETH.afterSwap.selector, 0);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ** fallback for wrapped eth unwrapping
    receive() external payable {}
}
