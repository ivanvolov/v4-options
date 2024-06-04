// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC721} from "solmate/tokens/ERC721.sol";

import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id, Market} from "morpho-blue/interfaces/IMorpho.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

import {Position} from "v4-core/libraries/Position.sol";
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
import {ISwapRouter} from "./forks/ISwapRouter.sol";
import {PerpMath} from "./libraries/PerpMath.sol";

import "forge-std/console.sol";

contract CallETH is BaseHook, ERC721 {
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
    IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 OSQTH = IERC20(0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B);

    bytes internal constant ZERO_BYTES = bytes("");

    Id public immutable marketId;

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    mapping(PoolId => int24) public lastTick;

    uint256 private optionIdCounter = 0;
    mapping(uint256 => OptionInfo) public optionInfo;

    function getTickLast(PoolId poolId) public view returns (int24) {
        return lastTick[poolId];
    }

    function setTickLast(PoolId poolId, int24 _tick) private {
        lastTick[poolId] = _tick;
    }

    constructor(
        IPoolManager poolManager,
        Id _marketId
    ) BaseHook(poolManager) ERC721("CallETH", "CALL") {
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
        WETH.approve(address(swapRouter), type(uint256).max);
        WSTETH.approve(address(swapRouter), type(uint256).max);
        OSQTH.approve(address(swapRouter), type(uint256).max);

        IERC20(Currency.unwrap(key.currency0)).approve(
            address(morpho),
            type(uint256).max
        );
        IERC20(Currency.unwrap(key.currency1)).approve(
            address(morpho),
            type(uint256).max
        );

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
    ) external returns (uint256 optionId) {
        console.log(">> deposit");
        if (amount == 0) revert ZeroLiquidity();
        IERC20(Currency.unwrap(key.currency0)).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        int24 tickLower = getCurrentTick(key.toId());
        int24 tickUpper = PerpMath.tickRoundDown(
            PerpMath.getTickFromPrice(PerpMath.getPriceFromTick(tickLower) * 2),
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
            IERC20(Currency.unwrap(key.currency0)).balanceOf(address(this)),
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

        //** swap all OSQTH in WSTETH
        uint256 balanceOSQTH = OSQTH.balanceOf(address(this));
        if (balanceOSQTH != 0) {
            uint256 amountWETH = swapExactInput(
                address(OSQTH),
                address(WETH),
                uint256(int256(balanceOSQTH)),
                OSQTH_ETH_POOL_FEE
            );

            swapExactInput(
                address(WETH),
                address(WSTETH),
                amountWETH,
                WSTETH_WETH_POOL_FEE
            );
        }

        //** close position into WSTETH & USDC
        {
            //TODO: How to update liquidity here?
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

        //** Now we could have, USDC & WSTETH

        //** if USDC is borrowed buy extra and close the position
        morpho.accrueInterest(morpho.idToMarketParams(marketId)); //TODO: is this sync morpho here or not?
        Market memory m = morpho.market(marketId);
        MorphoPosition memory p = morpho.position(marketId, address(this));
        uint256 usdcToRepay = m.totalBorrowAssets; //TODO: this is a bad huck, fix in the future
        if (usdcToRepay != 0) {
            uint256 balanceUSDC = USDC.balanceOf(address(this));
            // console.log("> balanceUSDC", balanceUSDC);
            if (usdcToRepay > balanceUSDC) {
                console.log("> buy USDC to repay");
                swapExactOutput(
                    address(WSTETH),
                    address(USDC),
                    usdcToRepay - balanceUSDC,
                    WSTETH_USDC_POOL_FEE
                );
            } else {
                console.log("> sell extra USDC");
                swapExactOutput(
                    address(USDC),
                    address(WSTETH),
                    balanceUSDC,
                    WSTETH_USDC_POOL_FEE
                );
            }

            morpho.repay(
                morpho.idToMarketParams(marketId),
                0,
                p.borrowShares,
                address(this),
                ZERO_BYTES
            );
        }

        morpho.withdrawCollateral(
            morpho.idToMarketParams(marketId),
            p.collateral,
            address(this),
            address(this)
        );

        WSTETH.transfer(to, WSTETH.balanceOf(address(this)));
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

        int24 tick = getCurrentTick(key.toId());

        if (tick > getTickLast(key.toId())) {
            console.log(">> price go up...");
            // console.logInt(deltas.amount0());
            // console.logInt(deltas.amount1());

            morpho.borrow(
                morpho.idToMarketParams(marketId),
                uint256(int256(-deltas.amount1())),
                0,
                address(this),
                address(this)
            );

            uint256 amountOut = swapExactInput(
                address(USDC),
                address(WETH),
                uint256(int256(-deltas.amount1())),
                ETH_USDC_POOL_FEE
            );
            swapExactInput(
                address(WETH),
                address(OSQTH),
                amountOut,
                OSQTH_ETH_POOL_FEE
            );
        } else if (tick < getTickLast(key.toId())) {
            console.log(">> price go down...");
            // console.logInt(deltas.amount0());
            // console.logInt(deltas.amount1());

            MorphoPosition memory p = morpho.position(marketId, address(this));
            if (p.borrowShares != 0) {
                //TODO: here implement the part if borrowShares to USDC is < deltas in USDC
                swapOSQTH_WETH_USDC(uint256(int256(deltas.amount1())));

                morpho.repay(
                    morpho.idToMarketParams(marketId),
                    uint256(int256(deltas.amount1())),
                    0,
                    address(this),
                    ZERO_BYTES
                );
            }
        }

        setTickLast(key.toId(), tick);
        return (CallETH.afterSwap.selector, 0);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    // --- Helpers ---

    uint24 public constant OSQTH_ETH_POOL_FEE = 3000;
    uint24 public constant ETH_USDC_POOL_FEE = 500;
    uint24 public constant WSTETH_USDC_POOL_FEE = 500;
    uint24 public constant WSTETH_WETH_POOL_FEE = 100;

    ISwapRouter immutable swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee
    ) internal returns (uint256) {
        return
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
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
        uint256 amountOut,
        uint24 fee
    ) internal returns (uint256) {
        return
            swapRouter.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountInMaximum: type(uint256).max,
                    amountOut: amountOut,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    function swapOSQTH_WETH_USDC(uint256 amountOut) internal returns (uint256) {
        bytes memory path = abi.encodePacked(
            address(USDC),
            uint24(500),
            address(WETH),
            uint24(3000),
            address(OSQTH)
        );
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
}
