// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC721} from "solmate/tokens/ERC721.sol";

import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";

import {Position} from "v4-core/libraries/Position.sol";
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
import {IWETH} from "./forks/IWETH.sol";
import {IController, Vault} from "@forks/squeeth-monorepo/core/IController.sol";
import {ISwapRouter} from "./forks/ISwapRouter.sol";
import {PerpMath} from "./libraries/PerpMath.sol";

import {OptionBaseLib} from "./libraries/OptionBaseLib.sol";

import "forge-std/console.sol";

contract PutETH is BaseHook, ERC721 {
    using CurrencySettleTake for Currency;
    using PoolIdLibrary for PoolKey;

    error ZeroLiquidity();

    error AddLiquidityThroughHook();

    error InRange();

    error NotAnOptionOwner();

    error NoSwapWillOccur();

    struct OptionInfo {
        uint256 amount;
        int24 tick;
        int24 tickLower;
        int24 tickUpper;
        uint256 created;
    }

    IERC20 WSTETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IWETH WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 OSQTH = IERC20(0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B);

    IController constant powerTokenController =
        IController(0x64187ae08781B09368e6253F9E94951243A493D5);

    bytes internal constant ZERO_BYTES = bytes("");

    Id public immutable marketId;

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    mapping(PoolId => int24) public lastTick;

    uint256 private optionIdCounter = 0;
    mapping(uint256 => OptionInfo) public optionInfo;

    uint256 public vaultId;

    function getTickLast(PoolId poolId) public view returns (int24) {
        return lastTick[poolId];
    }

    function setTickLast(PoolId poolId, int24 _tick) private {
        lastTick[poolId] = _tick;
    }

    constructor(
        IPoolManager poolManager,
        Id _marketId
    ) BaseHook(poolManager) ERC721("PutETH", "PUT") {
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

        USDC.approve(OptionBaseLib.SWAP_ROUTER, type(uint256).max);
        WETH.approve(OptionBaseLib.SWAP_ROUTER, type(uint256).max);
        WSTETH.approve(OptionBaseLib.SWAP_ROUTER, type(uint256).max);
        OSQTH.approve(OptionBaseLib.SWAP_ROUTER, type(uint256).max);

        WSTETH.approve(address(morpho), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);

        vaultId = powerTokenController.mintWPowerPerpAmount(0, 0, 0);

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
    ) external returns (uint256 optionId) {
        console.log(">> deposit");
        if (amount == 0) revert ZeroLiquidity();
        IERC20(Currency.unwrap(key.currency1)).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        int24 tickUpper = getCurrentTick(key.toId());
        int24 tickLower = PerpMath.tickRoundDown(
            PerpMath.getTickFromPrice(PerpMath.getPriceFromTick(tickUpper) / 2),
            key.tickSpacing
        );
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
            IERC20(Currency.unwrap(key.currency1)).balanceOf(address(this)),
            address(this),
            ZERO_BYTES
        );
        optionId = optionIdCounter;

        optionInfo[optionId] = OptionInfo({
            amount: amount,
            tick: getCurrentTick(key.toId()),
            tickLower: tickLower,
            tickUpper: tickUpper,
            created: block.timestamp
        });

        _mint(to, optionId);
        optionIdCounter++;
    }

    function withdraw(
        PoolKey calldata key,
        uint256 optionId,
        address to
    ) external {
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
                    this.unlockWithdrawPlace,
                    (key, liquidity, tickLower, tickUpper)
                )
            );
        }
        logBalances();

        uint256 wstETHToRepay;
        uint256 usdcToObtain;
        uint256 osqthToRepay;
        uint256 ethToObtain;
        {
            morpho.accrueInterest(morpho.idToMarketParams(marketId)); //TODO: is this sync morpho here or not?
            Market memory m = morpho.market(marketId);
            wstETHToRepay = m.totalBorrowAssets;
            MorphoPosition memory p = morpho.position(marketId, address(this));
            usdcToObtain = p.collateral; //TODO: this is a bad huck, fix in the future
            Vault memory vault = powerTokenController.vaults(vaultId);
            osqthToRepay = vault.shortAmount;
            ethToObtain = vault.collateralAmount;
        }

        if (wstETHToRepay == 0) {
            morpho.withdrawCollateral(
                morpho.idToMarketParams(marketId),
                usdcToObtain,
                address(this),
                address(this)
            );
            USDC.transfer(to, USDC.balanceOf(address(this)));
            return;
        }

        // ** make all amounts ready to repay, now we have WSTETH and USDC
        {
            // SWAP extra WSTETH to WETH
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
            // No we have exact WSTETH, and some USDC
            OptionBaseLib.swapUSDC_OSQTH_Out(osqthToRepay);
            // No we have exact WSTETH, exact OSQTH and some USDC
        }

        // No we have exact WSTETH, exact OSQTH and some USDC
        logBalances();

        //** close OSQTH
        {
            powerTokenController.burnWPowerPerpAmount(
                vaultId,
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
        // No we have exact WSTETH, and some USDC
        logBalances();

        // ** close morpho
        {
            console.log("!");
            morpho.repay(
                morpho.idToMarketParams(marketId),
                wstETHToRepay,
                0,
                address(this),
                ZERO_BYTES
            );

            logBalances();
            morpho.withdrawCollateral(
                morpho.idToMarketParams(marketId),
                usdcToObtain,
                address(this),
                address(this)
            );
        }
        // No we have USDC only

        logBalances();
        USDC.transfer(to, USDC.balanceOf(address(this)));
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

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
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
                salt: bytes32(ZERO_BYTES)
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
        return ZERO_BYTES;
    }

    function unlockWithdrawPlace(
        PoolKey calldata key,
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper
    ) external selfOnly returns (bytes memory) {
        console.log(">> unlockWithdrawPlace");

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: -int128(liquidity),
                salt: bytes32(ZERO_BYTES)
            }),
            ZERO_BYTES
        );

        if (delta.amount0() > 0) {
            key.currency0.take(
                poolManager,
                address(this),
                uint256(uint128(delta.amount0())),
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
        //TODO: add here revert if the pool have enough liquidity but the extra operations is not possible for the current swap magnitude

        int24 tick = getCurrentTick(key.toId());

        if (tick > getTickLast(key.toId())) {
            console.log(">> price go up...");
            // console.logInt(deltas.amount0());
            // console.logInt(deltas.amount1());
            // console.log(" %s", USDC.balanceOf(address(this)));

            OptionBaseLib.swapUSDC_OSQTH_In(uint256(int256(-deltas.amount1())));

            Vault memory vault = powerTokenController.vaults(vaultId);

            // console.log(vault.collateralAmount);
            // console.log(vault.shortAmount);
            // console.log(OSQTH.balanceOf(address(this)));
            uint256 collateralToWithdraw = PerpMath.getAssetsBuyShares(
                OSQTH.balanceOf(address(this)),
                vault.shortAmount,
                vault.collateralAmount
            );
            // console.log(collateralToWithdraw);

            powerTokenController.burnWPowerPerpAmount(
                vaultId,
                OSQTH.balanceOf(address(this)),
                collateralToWithdraw
            );

            WETH.deposit{value: collateralToWithdraw}();

            uint256 amountOut = OptionBaseLib.swapExactInput(
                address(WETH),
                address(WSTETH),
                collateralToWithdraw
            );

            morpho.repay(
                morpho.idToMarketParams(marketId),
                amountOut,
                0,
                address(this),
                ZERO_BYTES
            );
        } else if (tick < getTickLast(key.toId())) {
            console.log(">> price go down...");
            // console.logInt(deltas.amount0());
            // console.logInt(deltas.amount1());
            morpho.borrow(
                morpho.idToMarketParams(marketId),
                uint256(int256(-deltas.amount0())),
                0,
                address(this),
                address(this)
            );
            uint256 wethAmountOut = OptionBaseLib.swapExactInput(
                address(WSTETH),
                address(WETH),
                uint256(int256(-deltas.amount0()))
            );
            WETH.withdraw(wethAmountOut);
            powerTokenController.deposit{value: wethAmountOut}(vaultId);
            powerTokenController.mintPowerPerpAmount(
                vaultId,
                wethAmountOut / 2,
                0
            );
            OptionBaseLib.swapOSQTH_USDC_In(OSQTH.balanceOf(address(this)));
        } else {
            console.log(">> price not changing...");
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

    // --- Helpers ---

    function getCurrentTick(PoolId poolId) public view returns (int24) {
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, poolId);
        return currentTick;
    }

    function getOptionPosition(
        PoolKey memory key,
        uint256 optionId
    ) public view returns (uint128, int24, int24) {
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
}
