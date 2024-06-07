// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {IMorpho, MarketParams, Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {IOracle} from "@forks/morpho/IOracle.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TestAccount, TestAccountLib} from "./libraries/TestAccountLib.t.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Position} from "v4-core/libraries/Position.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";

import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

import {HookEnabledSwapRouter} from "./libraries/HookEnabledSwapRouter.sol";
import {PutETH} from "../src/PutETH.sol";
import {OptionBaseLib} from "../src/libraries/OptionBaseLib.sol";

import {IController, Vault} from "@forks/squeeth-monorepo/core/IController.sol";
import {IMorphoChainlinkOracleV2Factory} from "@forks/morpho-oracles/IMorphoChainlinkOracleV2Factory.sol";
import {MorphoChainlinkOracleV2} from "@forks/morpho-oracles/MorphoChainlinkOracleV2.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";
import {IERC4626} from "@forks/morpho-oracles/IERC4626.sol";

import {OptionTestBase} from "./libraries/OptionTestBase.sol";
import {IOption} from "@src/interfaces/IOption.sol";

import "forge-std/console.sol";

//TODO: add here my mail and some credentials to bee cool
contract PutETHTest is OptionTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using TestAccountLib for TestAccount;

    function setUp() public {
        deployFreshManagerAndRouters();

        labelTokens();
        create_and_seed_morpho_market();
        init_hook();
        create_and_approve_accounts();
    }

    function test_morpho_blue_market() public {
        vm.startPrank(alice.addr);

        // ** Supply collateral
        uint256 collateralAmount = 10000 * 1e6;
        deal(address(USDC), address(alice.addr), collateralAmount);
        USDC.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(
            morpho.idToMarketParams(marketId),
            collateralAmount,
            alice.addr,
            ""
        );

        assertEqMorphoState(alice.addr, 0, 0, collateralAmount);
        assertEq(USDC.balanceOf(alice.addr), 0);

        // ** Borrow
        uint256 borrowAmount = 2 ether;
        (, uint256 shares) = morpho.borrow(
            morpho.idToMarketParams(marketId),
            borrowAmount,
            0,
            alice.addr,
            alice.addr
        );

        assertEqMorphoState(alice.addr, 0, shares, collateralAmount);
        assertEq(WSTETH.balanceOf(alice.addr), borrowAmount);
        vm.stopPrank();
    }

    function test_osqth_operations() public {
        IController powerTokenController = IController(
            0x64187ae08781B09368e6253F9E94951243A493D5
        );
        vm.startPrank(alice.addr);

        // ** Deposit OSQTH
        console.log("> OSQTH balance", OSQTH.balanceOf(alice.addr));
        deal(alice.addr, 100 ether);

        uint256 vaultId = powerTokenController.mintWPowerPerpAmount(0, 0, 0);
        powerTokenController.deposit{value: 10 ether}(vaultId);
        console.log("> OSQTH price", getETH_OSQTHPriceV3() / 1e18);
        console.log("> ETH price", (1e12 * 1e18) / getETH_USDCPriceV3());
        console.log("> isVaultSafe", powerTokenController.isVaultSafe(vaultId));
        powerTokenController.mintPowerPerpAmount(vaultId, 10 ether / 2, 0);

        // console.log("> OSQTH balance", OSQTH.balanceOf(alice.addr));
        assertEq(OSQTH.balanceOf(alice.addr), 28606797160868548091);
        assertEq(alice.addr.balance, 90 ether);

        Vault memory vault = powerTokenController.vaults(vaultId);

        assertEq(vault.collateralAmount, 10 ether);
        assertEq(vault.shortAmount, OSQTH.balanceOf(alice.addr));

        // ** Withdraw OSQTH
        powerTokenController.burnWPowerPerpAmount(
            vaultId,
            OSQTH.balanceOf(alice.addr),
            vault.collateralAmount
        );

        assertEq(OSQTH.balanceOf(alice.addr), 0);
        assertEq(alice.addr.balance, 100 ether);

        vm.stopPrank();
    }

    function test_deposit() public {
        uint256 amountToDeposit = 200000 * 1e6;
        deal(address(USDC), address(alice.addr), amountToDeposit);
        vm.prank(alice.addr);
        uint256 optionId = hook.deposit(key, amountToDeposit, alice.addr);
        (uint128 liquidity, , ) = hook.getOptionPosition(key, optionId);

        assertEq(liquidity, 5097266086499115);
        assertEqBalanceStateZero(alice.addr);
        assertEqMorphoState(address(hook), 0, 0, amountToDeposit / 2);
    }

    function test_deposit_withdraw_not_option_owner_revert() public {
        test_deposit();

        vm.expectRevert(IOption.NotAnOptionOwner.selector);
        hook.withdraw(key, 0, alice.addr);
    }

    function test_deposit_withdraw() public {
        test_deposit();

        vm.prank(alice.addr);
        hook.withdraw(key, 0, alice.addr);

        assertEqBalanceStateZero(address(hook));
        assertEqBalanceState(alice.addr, 0, 200000 * 1e6, 0, 0);

        (uint128 liquidity, , ) = hook.getOptionPosition(key, 0);
        assertEq(liquidity, 0);

        assertEqMorphoState(address(hook), 0, 0, 0);
    }

    function test_swap_price_up_revert() public {
        test_deposit();

        deal(address(USDC), address(swapper.addr), 10000 * 1e6);
        vm.expectRevert(IOption.NoSwapWillOccur.selector);
        swapUSDC_WSTETH_Out(1 ether);
    }

    function test_swap_price_down() public {
        test_deposit();

        deal(address(WSTETH), address(swapper.addr), 11555648042810551244);
        swapWSTETH_USDC_Out(10 * 4500 * 1e6);

        assertEqBalanceState(swapper.addr, 0, 10 * 4500 * 1e6);
        assertEqBalanceState(address(hook), 0, 10080834793);
        assertEqMorphoState(
            address(hook),
            0,
            11555648042810551244000000,
            100000000000
        );
    }

    function test_swap_price_down_then_up() public {
        test_swap_price_down();

        swapUSDC_WSTETH_Out(231112960856211000); // x% of 11555648042810551244

        assertEqBalanceState(swapper.addr, 231112960856211000, 44216245243);
        assertEqBalanceState(address(hook), 0, 9297080036);
        assertEqMorphoState(
            address(hook),
            0,
            10653418290705234894000000,
            100000000000
        );
    }

    function test_swap_price_down_then_withdraw() public {
        test_swap_price_down();

        vm.prank(alice.addr);
        hook.withdraw(key, 0, alice.addr);

        assertEqBalanceStateZero(address(hook));
        assertEqBalanceState(alice.addr, 0, 206736939618);

        (uint128 liquidity, , ) = hook.getOptionPosition(key, 0);
        assertEq(liquidity, 0);

        assertEqMorphoState(address(hook), 0, 0, 0);
    }

    // -- Helpers --

    function init_hook() internal {
        router = new HookEnabledSwapRouter(manager);

        address payable hookAddress = payable(
            address(
                uint160(
                    Hooks.AFTER_SWAP_FLAG |
                        Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                        Hooks.AFTER_INITIALIZE_FLAG
                )
            )
        );
        deployCodeTo("PutETH.sol", abi.encode(manager, marketId), hookAddress);
        PutETH _hook = PutETH(hookAddress);

        uint160 initialSQRTPrice = TickMath.getSqrtPriceAtTick(-192232);
        (key, ) = initPool(
            Currency.wrap(address(WSTETH)),
            Currency.wrap(address(USDC)),
            _hook,
            200,
            initialSQRTPrice,
            ZERO_BYTES
        );
        hook = IOption(hookAddress);
    }

    function create_and_seed_morpho_market() internal {
        create_morpho_market(
            address(WSTETH),
            address(USDC),
            915000000000000000,
            222866057499442860000000000000000000000000000 //4487 usdc for eth
        );

        // ** Deposit liquidity
        vm.startPrank(morphoLpProvider.addr);
        deal(address(WSTETH), morphoLpProvider.addr, 100 * 1e18);

        WSTETH.approve(address(morpho), type(uint256).max);
        (, uint256 shares) = morpho.supply(
            morpho.idToMarketParams(marketId),
            100 * 1e18,
            0,
            morphoLpProvider.addr,
            ""
        );

        assertEqMorphoState(morphoLpProvider.addr, shares, 0, 0);
        assertEqBalanceStateZero(morphoLpProvider.addr);
        vm.stopPrank();
    }
}
