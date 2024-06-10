// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {MarketParamsLib} from "@forks/morpho/MarketParamsLib.sol";
import {OptionBaseLib} from "@src/libraries/OptionBaseLib.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IChainlinkOracle} from "@forks/morpho-oracles/IChainlinkOracle.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id} from "@forks/morpho/IMorpho.sol";
import {IOption} from "@src/interfaces/IOption.sol";

import {TestERC20} from "v4-core/test/TestERC20.sol";
import {Deployers} from "v4-core-test/utils/Deployers.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {HedgehogLoyaltyMock} from "@test/libraries/HedgehogLoyaltyMock.sol";

abstract contract OptionTestBase is Test, Deployers {
    using TestAccountLib for TestAccount;

    IOption hook;

    TestERC20 WSTETH;
    TestERC20 USDC;
    TestERC20 OSQTH;
    TestERC20 WETH;

    TestAccount marketCreator;
    TestAccount morphoLpProvider;
    TestAccount alice;
    TestAccount swapper;

    HookEnabledSwapRouter router;
    Id marketId;
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    uint256 optionId;

    HedgehogLoyaltyMock loyalty;

    function labelTokens() public {
        WSTETH = TestERC20(OptionBaseLib.WSTETH);
        vm.label(address(WSTETH), "WSTETH");
        USDC = TestERC20(OptionBaseLib.USDC);
        vm.label(address(USDC), "USDC");
        OSQTH = TestERC20(OptionBaseLib.OSQTH);
        vm.label(address(OSQTH), "OSQTH");
        WETH = TestERC20(OptionBaseLib.WETH);
        vm.label(address(WETH), "WETH");
    }

    function create_and_approve_accounts() public {
        alice = TestAccountLib.createTestAccount("alice");
        swapper = TestAccountLib.createTestAccount("swapper");

        vm.startPrank(alice.addr);
        WSTETH.approve(address(hook), type(uint256).max);
        WSTETH.approve(address(morpho), type(uint256).max);
        USDC.approve(address(hook), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        WSTETH.approve(address(router), type(uint256).max);
        USDC.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    // -- Uniswap V4 -- //

    function swapUSDC_WSTETH_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        router.swap(
            key,
            IPoolManager.SwapParams(
                false, // USDC -> WSTETH
                int256(amountOut),
                TickMath.MAX_SQRT_PRICE - 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    function swapWSTETH_USDC_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        router.swap(
            key,
            IPoolManager.SwapParams(
                true, // WSTETH -> USDC
                int256(amountOut),
                TickMath.MIN_SQRT_PRICE + 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    // -- Uniswap V3 -- //

    function getETH_OSQTHPriceV3() public view returns (uint256) {
        return
            OptionBaseLib.getV3PoolPrice(
                0x82c427AdFDf2d245Ec51D8046b41c4ee87F0d29C
            );
    }

    function getETH_USDCPriceV3() public view returns (uint256) {
        return
            OptionBaseLib.getV3PoolPrice(
                0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
            );
    }

    // -- Morpho -- //

    function create_morpho_market(
        address loanToken,
        address collateralToken,
        uint256 lltv,
        uint256 oracleNewPrice
    ) internal {
        marketCreator = TestAccountLib.createTestAccount("marketCreator");
        morphoLpProvider = TestAccountLib.createTestAccount("morphoLpProvider");
        MarketParams memory marketParams = MarketParams(
            loanToken,
            collateralToken,
            0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2, // This oracle is hardcoded for now
            0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, // We have only 1 irm in morpho so we can use this address
            lltv
        );

        modifyMockOracle(address(marketParams.oracle), oracleNewPrice);

        vm.prank(marketCreator.addr);
        morpho.createMarket(marketParams);
        marketId = MarketParamsLib.id(marketParams);
    }

    function modifyMockOracle(
        address oracle,
        uint256 newPrice
    ) internal returns (IChainlinkOracle iface) {
        iface = IChainlinkOracle(oracle);
        address vault = address(IChainlinkOracle(oracle).VAULT());
        uint256 conversionSample = IChainlinkOracle(oracle)
            .VAULT_CONVERSION_SAMPLE();
        address baseFeed1 = address(IChainlinkOracle(oracle).BASE_FEED_1());
        address baseFeed2 = address(IChainlinkOracle(oracle).BASE_FEED_2());
        address quoteFeed1 = address(IChainlinkOracle(oracle).QUOTE_FEED_1());
        address quoteFeed2 = address(IChainlinkOracle(oracle).QUOTE_FEED_2());
        uint256 scaleFactor = IChainlinkOracle(oracle).SCALE_FACTOR();

        vm.mockCall(
            oracle,
            abi.encodeWithSelector(iface.price.selector),
            abi.encode(newPrice)
        );
        assertEq(iface.price(), newPrice);
        assertEq(address(iface.VAULT()), vault);
        assertEq(iface.VAULT_CONVERSION_SAMPLE(), conversionSample);
        assertEq(address(iface.BASE_FEED_1()), baseFeed1);
        assertEq(address(iface.BASE_FEED_2()), baseFeed2);
        assertEq(address(iface.QUOTE_FEED_1()), quoteFeed1);
        assertEq(address(iface.QUOTE_FEED_2()), quoteFeed2);
        assertEq(iface.SCALE_FACTOR(), scaleFactor);

        return iface;
    }

    function provideLiquidityToMorpho(address asset, uint256 amount) internal {
        vm.startPrank(morphoLpProvider.addr);
        deal(asset, morphoLpProvider.addr, amount);

        TestERC20(asset).approve(address(morpho), type(uint256).max);
        (, uint256 shares) = morpho.supply(
            morpho.idToMarketParams(marketId),
            amount,
            0,
            morphoLpProvider.addr,
            ""
        );

        assertEqMorphoState(morphoLpProvider.addr, shares, 0, 0);
        assertEqBalanceStateZero(morphoLpProvider.addr);
        vm.stopPrank();
    }

    // -- Custom assertions -- //

    function assertOptionV4PositionLiquidity(
        uint256 optionId,
        uint256 _liquidity
    ) public view {
        (uint128 liquidity, , ) = hook.getOptionPosition(key, optionId);
        assertApproxEqAbs(liquidity, _liquidity, 10, "liquidity not equal");
    }

    function assertEqMorphoState(
        address owner,
        uint256 _supplyShares,
        uint256 _borrowShares,
        uint256 _collateral
    ) public view {
        MorphoPosition memory p;
        p = morpho.position(marketId, owner);
        assertApproxEqAbs(
            p.supplyShares,
            _supplyShares,
            10,
            "supply shares not equal"
        );
        assertApproxEqAbs(
            p.borrowShares,
            _borrowShares,
            10,
            "borrow shares not equal"
        );
        assertApproxEqAbs(
            p.collateral,
            _collateral,
            10000,
            "collateral not equal"
        );
    }

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0, 0, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWSTETH,
        uint256 _balanceUSDC
    ) public view {
        assertEqBalanceState(owner, _balanceWSTETH, _balanceUSDC, 0, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWSTETH,
        uint256 _balanceUSDC,
        uint256 _balanceWETH,
        uint256 _balanceOSQTH
    ) public view {
        assertEqBalanceState(
            owner,
            _balanceWSTETH,
            _balanceUSDC,
            _balanceWETH,
            _balanceOSQTH,
            0
        );
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWSTETH,
        uint256 _balanceUSDC,
        uint256 _balanceWETH,
        uint256 _balanceOSQTH,
        uint256 _balanceETH
    ) public view {
        assertApproxEqAbs(
            USDC.balanceOf(owner),
            _balanceUSDC,
            10,
            "Balance USDC not equal"
        );
        assertApproxEqAbs(
            WETH.balanceOf(owner),
            _balanceWETH,
            10,
            "Balance WETH not equal"
        );
        assertApproxEqAbs(
            OSQTH.balanceOf(owner),
            _balanceOSQTH,
            10,
            "Balance OSQTH not equal"
        );
        assertApproxEqAbs(
            WSTETH.balanceOf(owner),
            _balanceWSTETH,
            10,
            "Balance WSTETH not equal"
        );

        assertApproxEqAbs(
            owner.balance,
            _balanceETH,
            10,
            "Balance ETH not equal"
        );
    }
}
